class_name ProtoPlayer
extends CharacterBody3D
## First-person player: mouse look, WASD relative to facing, LMB swing.
## Urgency is both the health bar and the timer - it rises constantly,
## spikes when hit, and slows your desperate shuffle as it fills.

signal died
signal hit
signal inventory_changed

const PLUNGER_SCENE := preload("res://assets/plunger.glb")
const ARM_SCENE := preload("res://assets/arm.glb")
const BROOM_SCENE := preload("res://assets/janitor_broom.glb")
const BODY_SCENE := preload("res://assets/man_animated.glb")

## Baked center of the arm mesh (cancelled at mount time).
const ARM_CENTER := Vector3(-7.351, 10.096, -0.350)
const BROOM_CENTER := Vector3(3.568, 0.0758, -2.4754)

const BASE_SPEED := 4.6
const PANIC_SPEED := 2.2
const MOUSE_SENS := 0.0022
const URGENCY_PER_SEC := 1.1
const URGENCY_PER_HIT := 10.0

var urgency := 0.0
var attack_damage := 1
var attack_range := 2.2
var attack_cooldown := 0.5
var has_plunger := false
## Movement/attack lock while scripted (sitting on a toilet). Look stays free.
var locked := false

## Four slots; slot 1 is permanently the bare hand, pickups fill slots 2-4.
## Press 1-4 to equip a slot (an empty slot also swings bare fists).
var inventory: Array = ["hand", "", "", ""]
var equipped_slot := 0

var _attack_timer := 0.0
var _knockback := Vector3.ZERO
var _dead := false
var _pitch := 0.0
var _bob_time := 0.0
var _head: Node3D
var _cam: Camera3D
var _arm_pivot: Node3D
var _arm: Node3D
var _plunger: Node3D = null
var _broom: Node3D = null
var _body: Node3D = null
var _body_anim: AnimationPlayer = null
## First seconds after spawn: snap to floor every frame (kills roof pops).
var _spawn_grace := 2.5


func _ready() -> void:
	add_to_group("player")

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.35
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	_head = Node3D.new()
	_head.position.y = 1.62
	add_child(_head)

	_cam = Camera3D.new()
	_cam.fov = 72
	_cam.near = 0.05
	_head.add_child(_cam)
	_cam.make_current()

	# Faint personal glow so nearby geometry (and the viewmodel) always reads.
	var glow := OmniLight3D.new()
	glow.light_energy = 0.4
	glow.omni_range = 5.0
	glow.light_color = Color(0.9, 0.95, 1.0)
	glow.shadow_enabled = false
	_head.add_child(glow)

	# Viewmodel: real arm model, punching until the plunger shows up.
	_arm_pivot = Node3D.new()
	_arm_pivot.position = Vector3(0.3, -0.2, -0.45)
	_arm_pivot.rotation_degrees = Vector3(12, -6, 0)
	_cam.add_child(_arm_pivot)

	_arm = Node3D.new()
	_arm.scale = Vector3(0.09, 0.09, 0.09)
	_arm.rotation_degrees = Vector3(0, 90, 0)  # model fingers point +X; face them forward
	_arm_pivot.add_child(_arm)
	var arm_inst: Node3D = ARM_SCENE.instantiate()
	arm_inst.position = -ARM_CENTER
	_arm.add_child(arm_inst)

	# Full body ready from the start (hidden until you sit - then the camera
	# pulls out and you watch yourself on the throne, Sit anim playing).
	_body = BODY_SCENE.instantiate()
	_body.rotation.y = PI
	_body.position = Vector3(0, 0.35, 0)
	_body.visible = false
	add_child(_body)
	var anims := _body.find_children("*", "AnimationPlayer", true, false)
	if anims.size() > 0:
		_body_anim = anims[0]
		if _body_anim.has_animation("Sit"):
			_body_anim.get_animation("Sit").loop_mode = Animation.LOOP_NONE

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if locked:
			return  # seated: the camera is doing its own thing
		rotation.y -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.2, 1.2)
		_head.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo and not locked:
		match event.physical_keycode:
			KEY_1: _equip(0)
			KEY_2: _equip(1)
			KEY_3: _equip(2)
			KEY_4: _equip(3)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	urgency = minf(100.0, urgency + URGENCY_PER_SEC * delta)
	if urgency >= 100.0:
		_dead = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)

	var input_dir := Vector2.ZERO
	if not locked:
		if Input.is_physical_key_pressed(KEY_W):
			input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S):
			input_dir.y += 1
		if Input.is_physical_key_pressed(KEY_A):
			input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D):
			input_dir.x += 1
		input_dir = input_dir.normalized()

	var speed: float = lerpf(BASE_SPEED, PANIC_SPEED, urgency / 100.0)
	var move := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)) * speed
	velocity.x = move.x + _knockback.x
	velocity.z = move.z + _knockback.z
	_knockback = _knockback.lerp(Vector3.ZERO, 8.0 * delta)

	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 18.0 * delta

	move_and_slide()

	# Shove physics props (janitor cart, brooms): CharacterBody3D doesn't
	# push RigidBody3Ds on its own, so hand over a little momentum per hit.
	# Capped so light stuff (a broom) topples instead of launching to orbit.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb:
			rb.apply_impulse(-c.get_normal() * minf(rb.mass, 6.0) * 0.12,
				c.get_position() - rb.global_position)

	# Roof-spawn killer. During grace, snap to the floor every frame no
	# matter what depenetration did. After that, still never allow y > 1.5
	# (stall tops / ceiling) - nothing walkable lives up there.
	if _spawn_grace > 0.0:
		_spawn_grace -= delta
		if global_position.y > 0.15 or global_position.y < -0.05:
			global_position.y = 0.1
			velocity.y = 0.0
	elif global_position.y > 1.5 or global_position.y < -0.5:
		global_position.y = 0.1
		velocity.y = 0.0

	# Head bob, increasingly frantic as urgency rises.
	if input_dir.length() > 0.1 and is_on_floor():
		_bob_time += delta * (7.0 + urgency * 0.06)
		_head.position.y = 1.62 + sin(_bob_time) * (0.035 + urgency * 0.0006)
	else:
		_head.position.y = lerpf(_head.position.y, 1.62, 10.0 * delta)

	if not locked and _attack_timer <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)):
		_attack()


## Horizontal facing direction (used for attacks and by the manager).
func facing() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0
	return f.normalized()


func _attack() -> void:
	_attack_timer = attack_cooldown

	var f := facing()
	for e in get_tree().get_nodes_in_group("enemies"):
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0
		if to_e.length() <= attack_range and f.dot(to_e.normalized()) > 0.45:
			e.take_hit(attack_damage, to_e.normalized())

	# Viewmodel jab.
	var tw := create_tween()
	tw.tween_property(_arm_pivot, "position:z", -0.85, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_arm_pivot, "position:z", -0.5, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Killed outright (Rush). No urgency ceremony - lights out, full stop.
func die_instantly() -> void:
	if _dead:
		return
	_dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	died.emit()


func take_hit(from_dir: Vector3) -> void:
	if _dead:
		return
	urgency = minf(100.0, urgency + URGENCY_PER_HIT)
	_knockback = from_dir * 7.0
	# Camera jolt.
	var tw := create_tween()
	tw.tween_property(_head, "rotation:z", 0.06, 0.05)
	tw.tween_property(_head, "rotation:z", 0.0, 0.2)
	hit.emit()


## Sit down: your own body appears on the throne playing the Sit animation
## and the camera pulls out through the door so you can watch yourself.
## Movement, attacks and mouse look are locked until stand_up().
func sit_down() -> void:
	locked = true
	_body.visible = true
	if _body_anim and _body_anim.has_animation("Sit"):
		_body_anim.play("Sit")
		# When the sit-down motion finishes, freeze on the seated pose.
		if not _body_anim.animation_finished.is_connected(_hold_sit_pose):
			_body_anim.animation_finished.connect(_hold_sit_pose)
	_arm_pivot.visible = false
	_pitch = 0.0
	_head.rotation.x = 0.0

	# Camera swings out in front (the open door side) and turns back around
	# so you can see yourself sitting - same man model the NPCs use.
	var tw := create_tween().set_parallel()
	tw.tween_property(_cam, "position", Vector3(0, 0.25, -2.1), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cam, "rotation:y", PI, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cam, "rotation:x", -0.18, 0.45)


func _hold_sit_pose(_anim_name: StringName) -> void:
	if _body_anim and _body_anim.has_animation("Sit"):
		_body_anim.play("Sit")
		_body_anim.seek(_body_anim.get_animation("Sit").length - 0.02)
		_body_anim.pause()


## Reverse of sit_down; unlocks controls once the camera is back in the skull.
func stand_up() -> void:
	if _body:
		_body.visible = false
	if _body_anim:
		_body_anim.stop()
	_arm_pivot.visible = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_cam, "position", Vector3.ZERO, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_cam, "rotation:y", 0.0, 0.35)
	tw.tween_property(_cam, "rotation:x", 0.0, 0.35)
	tw.chain().tween_callback(func() -> void: locked = false)


func give_plunger() -> void:
	add_item("plunger")


## Put an item into the first free slot (2-4; slot 1 is the hand) and equip
## it. Returns false when full or already carried (weapons don't stack).
func add_item(item: String) -> bool:
	if item in inventory:
		return false
	for i in range(1, inventory.size()):
		if inventory[i] == "":
			inventory[i] = item
			if item == "plunger":
				has_plunger = true
			_equip(i)
			return true
	return false


## Equip whatever sits in the given slot; hand/empty slots swing bare fists.
func _equip(slot: int) -> void:
	equipped_slot = slot
	var item: String = inventory[slot]

	_arm.visible = item == "hand" or item == ""
	if _plunger:
		_plunger.visible = item == "plunger"
	if _broom:
		_broom.visible = item == "broom"

	match item:
		"plunger":
			if not _plunger:
				_plunger = PLUNGER_SCENE.instantiate()
				_plunger.scale = Vector3(1.2, 1.2, 1.2)
				_plunger.position = Vector3(0, -0.12, 0.05)
				_plunger.rotation_degrees = Vector3(-70, 0, 0)
				_arm_pivot.add_child(_plunger)
			# Heavy swings: more damage but slow.
			attack_damage = 2
			attack_range = 2.5
			attack_cooldown = 0.75
		"broom":
			if not _broom:
				_broom = Node3D.new()
				_broom.scale = Vector3(0.55, 0.55, 0.55)
				# Lance grip: bristle head forward, handle back to the hand.
				_broom.position = Vector3(-0.08, -0.18, -0.3)
				_broom.rotation_degrees = Vector3(70, 10, 0)
				_arm_pivot.add_child(_broom)
				var inst: Node3D = BROOM_SCENE.instantiate()
				inst.position = -BROOM_CENTER
				_broom.add_child(inst)
			# Long and quick, but it only sweeps for 1 damage.
			attack_damage = 1
			attack_range = 3.1
			attack_cooldown = 0.35
		_:
			attack_damage = 1
			attack_range = 2.2
			attack_cooldown = 0.5

	inventory_changed.emit()
