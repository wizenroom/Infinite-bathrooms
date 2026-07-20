class_name ProtoEnemy
extends CharacterBody3D
## Melee occupant: chases the player, telegraphs with a wind-up,
## then lunges. Two fist hits (one plunger hit) to kill.

const SPEED := 3.2
const AGGRO_RANGE := 9.0
const WINDUP_TIME := 0.5
const STRIKE_TIME := 0.25
const RECOVER_TIME := 0.6

var hp := 2

var _state := "chase"
var _timer := 0.0
var _has_struck := false
var _knockback := Vector3.ZERO
var _strike_dir := Vector3.ZERO
var _mat: StandardMaterial3D
var _visual: MeshInstance3D
var _player: Node3D


func _ready() -> void:
	add_to_group("enemies")

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.7
	cap.radius = 0.38
	col.shape = cap
	col.position.y = 0.85
	add_child(col)

	_visual = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.height = 1.7
	mesh.radius = 0.38
	_visual.mesh = mesh
	_visual.position.y = 0.85
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.75, 0.2, 0.15)
	_visual.material_override = _mat
	add_child(_visual)


func _physics_process(delta: float) -> void:
	if _state == "dead":
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not _player:
			return

	var to_player := _player.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()
	var dir := to_player.normalized()

	match _state:
		"chase":
			if dist > AGGRO_RANGE:
				# Out of range: loiter menacingly instead of chasing.
				velocity.x = _knockback.x
				velocity.z = _knockback.z
			else:
				velocity.x = dir.x * SPEED + _knockback.x
				velocity.z = dir.z * SPEED + _knockback.z
			if dist < 1.9:
				_state = "windup"
				_timer = WINDUP_TIME
				_mat.albedo_color = Color(1.0, 0.55, 0.1)
		"windup":
			velocity.x = _knockback.x
			velocity.z = _knockback.z
			_timer -= delta
			if _timer <= 0.0:
				_state = "strike"
				_timer = STRIKE_TIME
				_has_struck = false
				_strike_dir = dir
				_mat.albedo_color = Color(1.0, 0.15, 0.1)
		"strike":
			velocity.x = _strike_dir.x * 9.0 + _knockback.x
			velocity.z = _strike_dir.z * 9.0 + _knockback.z
			if not _has_struck and dist < 1.5:
				_player.take_hit(dir)
				_has_struck = true
			_timer -= delta
			if _timer <= 0.0:
				_state = "recover"
				_timer = RECOVER_TIME
				_mat.albedo_color = Color(0.55, 0.25, 0.3)
		"recover":
			velocity.x = _knockback.x
			velocity.z = _knockback.z
			_timer -= delta
			if _timer <= 0.0:
				_state = "chase"
				_mat.albedo_color = Color(0.75, 0.2, 0.15)

	_knockback = _knockback.lerp(Vector3.ZERO, 8.0 * delta)

	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 18.0 * delta

	move_and_slide()

	if velocity.length() > 0.5:
		var flat := Vector3(velocity.x, 0, velocity.z)
		if flat.length() > 0.1:
			_visual.rotation.y = atan2(-flat.x, -flat.z) - rotation.y


func take_hit(dmg: int, from_dir: Vector3) -> void:
	if _state == "dead":
		return
	hp -= dmg
	_knockback = from_dir * 9.0
	var flash := create_tween()
	flash.tween_property(_mat, "albedo_color", Color.WHITE, 0.05)
	flash.tween_property(_mat, "albedo_color", Color(0.75, 0.2, 0.15), 0.15)
	if hp <= 0:
		_die()


func _die() -> void:
	_state = "dead"
	remove_from_group("enemies")
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(1.4, 0.08, 1.4), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.4)
	tw.tween_callback(queue_free)
