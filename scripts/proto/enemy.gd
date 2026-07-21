class_name ProtoEnemy
extends CharacterBody3D
## Melee occupant: chases the player, telegraphs with the punch wind-up
## animation, then lunges. Three fist hits (two plunger hits) to kill.

const MAN_SCENE := preload("res://assets/man_animated.glb")

const SPEED := 3.7
const AGGRO_RANGE := 11.0
const WINDUP_TIME := 0.4
const STRIKE_TIME := 0.25
const RECOVER_TIME := 0.5
const ATTACK_ANIM_TIME := WINDUP_TIME + STRIKE_TIME

var hp := 3

var _state := "chase"
var _timer := 0.0
var _has_struck := false
var _knockback := Vector3.ZERO
var _strike_dir := Vector3.ZERO
var _visual: Node3D
var _anim: AnimationPlayer
var _meshes: Array = []
var _flash_mat: StandardMaterial3D
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

	_visual = Node3D.new()
	add_child(_visual)

	var model := MAN_SCENE.instantiate()
	# glTF forward is +Z, Godot forward is -Z; flip so he runs face-first.
	model.rotation.y = PI
	_visual.add_child(model)

	_meshes = model.find_children("*", "MeshInstance3D", true, false)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(0.9, 0.9, 0.9)

	var anims := model.find_children("*", "AnimationPlayer", true, false)
	if anims.size() > 0:
		_anim = anims[0]
		for anim_name in ["Walk", "Run", "Sit"]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		_play("Run")


func _play(anim_name: String, speed := 1.0) -> void:
	if _anim and _anim.has_animation(anim_name):
		if _anim.current_animation != anim_name or not _anim.is_playing():
			_anim.play(anim_name, 0.15, speed)


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
				_play("Walk", 0.3)
			else:
				velocity.x = dir.x * SPEED + _knockback.x
				velocity.z = dir.z * SPEED + _knockback.z
				_play("Run")
			if dist < 1.9:
				_state = "windup"
				_timer = WINDUP_TIME
				if _anim and _anim.has_animation("Attack_Punch"):
					var punch_speed: float = _anim.get_animation("Attack_Punch").length / ATTACK_ANIM_TIME
					_anim.play("Attack_Punch", 0.05, punch_speed)
		"windup":
			velocity.x = _knockback.x
			velocity.z = _knockback.z
			_timer -= delta
			if _timer <= 0.0:
				_state = "strike"
				_timer = STRIKE_TIME
				_has_struck = false
				_strike_dir = dir
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
		"recover":
			velocity.x = _knockback.x
			velocity.z = _knockback.z
			_timer -= delta
			if _timer <= 0.0:
				_state = "chase"

	_knockback = _knockback.lerp(Vector3.ZERO, 8.0 * delta)

	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 18.0 * delta

	move_and_slide()

	var face := Vector3(velocity.x, 0, velocity.z)
	if _state == "windup" or _state == "strike":
		face = _player.global_position - global_position
		face.y = 0
	if face.length() > 0.3:
		var d := face.normalized()
		_visual.rotation.y = atan2(-d.x, -d.z)


func take_hit(dmg: int, from_dir: Vector3) -> void:
	if _state == "dead":
		return
	hp -= dmg
	_knockback = from_dir * 9.0
	for mi in _meshes:
		mi.material_overlay = _flash_mat
	get_tree().create_timer(0.09).timeout.connect(func() -> void:
		if is_instance_valid(self):
			for mi in _meshes:
				if is_instance_valid(mi):
					mi.material_overlay = null
	)
	if hp <= 0:
		_die()


func _die() -> void:
	_state = "dead"
	remove_from_group("enemies")
	if _anim:
		_anim.pause()
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(_visual, "rotation:x", -PI / 2.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(_visual, "position:y", -1.2, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
