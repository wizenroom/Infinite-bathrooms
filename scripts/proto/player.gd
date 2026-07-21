class_name ProtoPlayer
extends CharacterBody3D
## First-person player: mouse look, WASD relative to facing, LMB swing.
## Urgency is both the health bar and the timer - it rises constantly,
## spikes when hit, and slows your desperate shuffle as it fills.

signal died
signal hit

const PLUNGER_SCENE := preload("res://assets/plunger.glb")

const BASE_SPEED := 4.6
const PANIC_SPEED := 2.2
const MOUSE_SENS := 0.0022
const ATTACK_COOLDOWN := 0.5
const URGENCY_PER_SEC := 1.1
const URGENCY_PER_HIT := 10.0

var urgency := 0.0
var attack_damage := 1
var attack_range := 2.2
var has_plunger := false

var _attack_timer := 0.0
var _knockback := Vector3.ZERO
var _dead := false
var _pitch := 0.0
var _bob_time := 0.0
var _head: Node3D
var _cam: Camera3D
var _arm_pivot: Node3D
var _fist: MeshInstance3D
var _plunger: Node3D = null


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

	# Viewmodel: bare fist until the plunger shows up.
	_arm_pivot = Node3D.new()
	_arm_pivot.position = Vector3(0.32, -0.28, -0.5)
	_cam.add_child(_arm_pivot)

	_fist = MeshInstance3D.new()
	var fist_mesh := BoxMesh.new()
	fist_mesh.size = Vector3(0.13, 0.13, 0.22)
	_fist.mesh = fist_mesh
	var fist_mat := StandardMaterial3D.new()
	fist_mat.albedo_color = Color(0.85, 0.66, 0.5)
	_fist.material_override = fist_mat
	_arm_pivot.add_child(_fist)

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

	# Head bob, increasingly frantic as urgency rises.
	if input_dir.length() > 0.1 and is_on_floor():
		_bob_time += delta * (7.0 + urgency * 0.06)
		_head.position.y = 1.62 + sin(_bob_time) * (0.035 + urgency * 0.0006)
	else:
		_head.position.y = lerpf(_head.position.y, 1.62, 10.0 * delta)

	if _attack_timer <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)):
		_attack()


## Horizontal facing direction (used for attacks and by the manager).
func facing() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0
	return f.normalized()


func _attack() -> void:
	_attack_timer = ATTACK_COOLDOWN

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
	if has_plunger:
		return
	has_plunger = true
	attack_damage = 2
	attack_range = 2.8

	_fist.visible = false
	_plunger = PLUNGER_SCENE.instantiate()
	_plunger.scale = Vector3(1.2, 1.2, 1.2)
	_plunger.position = Vector3(0, -0.12, 0.05)
	_plunger.rotation_degrees = Vector3(-70, 0, 0)
	_arm_pivot.add_child(_plunger)
