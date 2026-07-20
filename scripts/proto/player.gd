class_name ProtoPlayer
extends CharacterBody3D
## Top-down player: WASD move, mouse aim, LMB/Space melee swing.
## Urgency is both the health bar and the timer - it rises constantly,
## spikes when hit, and slows you down as it fills.

signal died
signal hit

const BASE_SPEED := 5.0
const PANIC_SPEED := 2.4
const ATTACK_COOLDOWN := 0.45
const URGENCY_PER_SEC := 1.1
const URGENCY_PER_HIT := 10.0

var urgency := 0.0
var attack_damage := 1
var attack_range := 2.0
var has_plunger := false
var facing := Vector3.FORWARD

var _attack_timer := 0.0
var _knockback := Vector3.ZERO
var _dead := false
var _visual: Node3D


func _ready() -> void:
	add_to_group("player")

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.4
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	_visual = Node3D.new()
	add_child(_visual)

	var body_mesh := MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.height = 1.8
	cap_mesh.radius = 0.4
	body_mesh.mesh = cap_mesh
	body_mesh.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.8, 0.25)
	body_mesh.material_override = mat
	_visual.add_child(body_mesh)

	# Nose so you can read facing from above.
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.18, 0.18, 0.5)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 1.4, -0.5)
	nose.material_override = mat
	_visual.add_child(nose)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 12.5, 7.5)
	cam.rotation_degrees = Vector3(-58, 0, 0)
	cam.fov = 55
	add_child(cam)
	cam.make_current()


func _physics_process(delta: float) -> void:
	if _dead:
		return

	urgency = minf(100.0, urgency + URGENCY_PER_SEC * delta)
	if urgency >= 100.0:
		_dead = true
		died.emit()
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)
	_update_aim()

	var input_dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.z += 1
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var speed: float = lerpf(BASE_SPEED, PANIC_SPEED, urgency / 100.0)
	velocity.x = input_dir.x * speed + _knockback.x
	velocity.z = input_dir.z * speed + _knockback.z
	_knockback = _knockback.lerp(Vector3.ZERO, 8.0 * delta)

	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 18.0 * delta

	move_and_slide()

	_visual.rotation.y = atan2(-facing.x, -facing.z)

	if _attack_timer <= 0.0 and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)):
		_attack()


func _update_aim() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var mpos := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mpos)
	var dir := cam.project_ray_normal(mpos)
	if absf(dir.y) < 0.001:
		return
	var t := -origin.y / dir.y
	if t <= 0.0:
		return
	var aim_point := origin + dir * t
	var to_aim := aim_point - global_position
	to_aim.y = 0
	if to_aim.length() > 0.25:
		facing = to_aim.normalized()


func _attack() -> void:
	_attack_timer = ATTACK_COOLDOWN

	for e in get_tree().get_nodes_in_group("enemies"):
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0
		if to_e.length() <= attack_range and facing.dot(to_e.normalized()) > 0.35:
			e.take_hit(attack_damage, to_e.normalized())

	# Quick swing visual: a fading slab in front of the player.
	var slash := MeshInstance3D.new()
	var slash_mesh := BoxMesh.new()
	slash_mesh.size = Vector3(1.7, 0.1, attack_range)
	slash.mesh = slash_mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.4, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.2)
	slash.material_override = mat
	get_parent().add_child(slash)
	slash.global_position = global_position + facing * (attack_range * 0.5) + Vector3(0, 1.1, 0)
	slash.rotation.y = atan2(-facing.x, -facing.z)
	var tw := slash.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(slash.queue_free)


func take_hit(from_dir: Vector3) -> void:
	if _dead:
		return
	urgency = minf(100.0, urgency + URGENCY_PER_HIT)
	_knockback = from_dir * 7.0
	hit.emit()


func give_plunger() -> void:
	has_plunger = true
	attack_damage = 2
	attack_range = 2.7
