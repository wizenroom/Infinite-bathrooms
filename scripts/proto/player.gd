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

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.2, 1.2)
		_head.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo:
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

	# Failsafe: physics depenetration can very occasionally pop a body through
	# the ceiling; drop back inside instead of walking on the roof.
	if global_position.y > 2.4:
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
