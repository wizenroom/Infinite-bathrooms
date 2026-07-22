class_name ProtoCrawler
extends CharacterBody3D
## The thing that crawls out of "vacant" stalls. Faster than the occupants,
## lower to the ground (harder to notice), lunges without much warning.
## Two fist hits (one plunger hit) to kill.
##
## Decimated FBX (~50k verts / 29 deform bones). Still pooled so waking one
## never hitch-instantiates mid-game. Stop-motion anim ticks keep the crawl
## looking jerky/creepy and cheap.

const CRAWLER_SCENE := preload("res://assets/crawler.fbx")

## Metarig carries a baked ~9.1 scale + 180° X flip; these cancel it down to
## ~1.8m long on the floor with the head toward local -Z.
const MODEL_SCALE := 0.12
const MODEL_OFFSET := Vector3(0.4, 4.05, 8.5)

const SPEED := 4.4
const AGGRO_RANGE := 14.0
const WINDUP_TIME := 0.25
const STRIKE_TIME := 0.2
const RECOVER_TIME := 0.8
## Stop-motion animation tick (seconds per pose).
const ANIM_STEP := 0.1

var hp := 2
var sleeping := true

var _state := "chase"
var _timer := 0.0
var _stuck_time := 0.0
var _has_struck := false
var _knockback := Vector3.ZERO
var _strike_dir := Vector3.ZERO
var _anim_accum := 0.0
var _anim_speed := 1.6
var _visual: Node3D
var _col: CollisionShape3D
var _anim: AnimationPlayer
var _meshes: Array = []
var _flash_mat: StandardMaterial3D
var _player: Node3D


func _ready() -> void:
	# Nothing collides WITH the crawler (layer 0): the player would otherwise
	# get shoved around or end up standing on it. It still hits via the lunge.
	collision_layer = 0
	collision_mask = 1

	# A sphere instead of a body-shaped box: long boxes wedge on stall door
	# frames and wall corners, spheres roll around them.
	_col = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.38
	_col.shape = sphere
	_col.position.y = 0.38
	add_child(_col)

	_visual = Node3D.new()
	add_child(_visual)

	var model: Node3D = CRAWLER_SCENE.instantiate()
	model.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	model.position = MODEL_OFFSET * MODEL_SCALE
	_visual.add_child(model)

	# The Eyes mesh is not skinned - it floats at the standing bind pose. Hide it.
	for mi in model.find_children("Eyes", "MeshInstance3D", true, false):
		mi.visible = false

	_meshes = model.find_children("Man", "MeshInstance3D", true, false)
	for mi in _meshes:
		mi.visibility_range_end = 26.0
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(0.9, 0.9, 0.9)

	var anims := model.find_children("*", "AnimationPlayer", true, false)
	if anims.size() > 0:
		_anim = anims[0]
		# FBX export names the clip "Scene"; fall back to whatever is there.
		var clip := "Crawl" if _anim.has_animation("Crawl") else String(_anim.get_animation_list()[0])
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		# Manual mode: we advance it ourselves in coarse stop-motion steps.
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_anim.play(clip)

	sleep()


## Park the crawler: invisible, no physics, no animation, no group presence.
func sleep() -> void:
	sleeping = true
	visible = false
	set_physics_process(false)
	_col.set_deferred("disabled", true)
	remove_from_group("enemies")
	remove_from_group("crawlers")


## Bring a pooled crawler back to life at the given position.
func wake(pos: Vector3) -> void:
	sleeping = false
	hp = 2
	_state = "chase"
	_knockback = Vector3.ZERO
	_stuck_time = 0.0
	_visual.rotation = Vector3.ZERO
	_visual.position = Vector3.ZERO
	global_position = pos
	visible = true
	set_physics_process(true)
	_col.set_deferred("disabled", false)
	add_to_group("enemies")
	add_to_group("crawlers")


func _physics_process(delta: float) -> void:
	# Stop-motion: advance the heavy 222-bone rig at ANIM_STEP intervals only.
	if _anim and _state != "dead":
		_anim_accum += delta * _anim_speed
		if _anim_accum >= ANIM_STEP:
			_anim.advance(_anim_accum)
			_anim_accum = 0.0

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
				velocity.x = _knockback.x
				velocity.z = _knockback.z
				_anim_speed = 0.4
			else:
				velocity.x = dir.x * SPEED + _knockback.x
				velocity.z = dir.z * SPEED + _knockback.z
				_anim_speed = 1.6
			if dist < 1.7:
				_state = "windup"
				_timer = WINDUP_TIME
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
			velocity.x = _strike_dir.x * 11.0 + _knockback.x
			velocity.z = _strike_dir.z * 11.0 + _knockback.z
			if not _has_struck and dist < 1.4:
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

	var wanted_speed := Vector2(velocity.x, velocity.z).length()
	move_and_slide()

	# Unstick: wanted to move but barely did (wedged on a stall wall or door
	# frame) -> after a moment, hop sideways toward the corridor center.
	if _state == "chase" and wanted_speed > 1.0:
		var actual := Vector2(get_real_velocity().x, get_real_velocity().z).length()
		if actual < 0.4:
			_stuck_time += delta
			if _stuck_time > 0.7:
				_stuck_time = 0.0
				var center_dir := signf(-global_position.x)
				_knockback = Vector3(center_dir * 5.0, 0, 0)
		else:
			_stuck_time = 0.0

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
	_knockback = from_dir * 7.0
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
	_col.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(_visual, "rotation:z", PI, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.4)
	tw.tween_property(_visual, "position:y", -0.9, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Back into the pool instead of freeing; the manager reuses us.
	tw.tween_callback(sleep)
