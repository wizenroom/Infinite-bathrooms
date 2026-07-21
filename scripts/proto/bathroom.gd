extends Node3D
## Game manager: generates the infinite bathroom corridor ahead of the
## player, resolves knock outcomes, and runs HUD + win/lose.
## Lives inside the low-res SubViewport; the HUD is added to hud_parent
## (outside the viewport) so text stays crisp.
##
## Controls: WASD move, mouse look, LMB/Space swing, E knock, R restart (after end).

const PLANT_SCENE := preload("res://assets/plant.glb")

const STALL_SPACING := 2.4
const STALL_X := 3.4
const GEN_AHEAD := 45.0
const KNOCK_RANGE := 3.0
const LIGHT_EVERY_N_PAIRS := 3

# Knock outcome weights (FREE is placed deterministically, not rolled).
const W_HOSTILE := 45
const W_LOOT := 20
const W_FRIENDLY := 15
const W_EMPTY := 20

## Set by game_root before this node enters the tree.
var hud_parent: Node = null

var player: ProtoPlayer
var stalls: Array[Stall] = []
var stall_count := 0
var free_stall_index := 0
var free_stall: Stall = null
var _free_placed := false
var next_z := -4.0
var pair_count := 0
var game_ended := false
var _warn_cooldown := 0.0
var rng := RandomNumberGenerator.new()

var _bar: ProgressBar
var _msg: Label
var _msg_tween: Tween
var _overlay: ColorRect
var _overlay_label: Label


func _ready() -> void:
	rng.randomize()
	free_stall_index = 12 + rng.randi_range(0, 6)

	_build_environment()
	_build_hud()

	player = ProtoPlayer.new()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	player.died.connect(_on_player_died)
	player.hit.connect(_on_player_hit)

	_show_message("Every stall is OCCUPIED... except one. Find it. (E = knock)", 4.5)

	# Dev aid: PROTO_DEBUG=knock auto-opens the first hostile stall so the
	# interior can be checked without playing up to it.
	if OS.get_environment("PROTO_DEBUG") == "knock":
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			for s in stalls:
				if s.outcome == Stall.Outcome.HOSTILE and not s.is_open:
					player.global_position = s.global_position + s.global_transform.basis.z * -2.0
					player.look_at(s.global_position + Vector3(0, 1.2, 0))
					player.rotation.x = 0
					s.knock()
					break
		)


func _process(delta: float) -> void:
	if game_ended:
		return

	_warn_cooldown = maxf(0.0, _warn_cooldown - delta)

	# Keep the corridor generated ahead of the player.
	while next_z > player.global_position.z - GEN_AHEAD:
		_spawn_stall_pair(next_z)
		next_z -= STALL_SPACING

	_bar.value = player.urgency

	_check_win()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E and not game_ended:
			_try_knock()
		elif event.physical_keycode == KEY_R and game_ended:
			get_tree().reload_current_scene()


func _try_knock() -> void:
	# Nearest closed stall the player is roughly looking toward.
	var f := player.facing()
	var best: Stall = null
	var best_dist := KNOCK_RANGE
	for s in stalls:
		if s.is_open:
			continue
		var to_s := s.global_position - player.global_position
		to_s.y = 0
		var d := to_s.length()
		if d < best_dist and f.dot(to_s.normalized()) > 0.25:
			best_dist = d
			best = s
	if best:
		best.knock()


func _spawn_stall_pair(z: float) -> void:
	pair_count += 1
	for side in [-1, 1]:
		var stall := Stall.new()
		add_child(stall)
		stall.position = Vector3(side * STALL_X, 0, z)
		# Stall door faces local -Z; rotate so it faces the corridor center.
		stall.rotation.y = side * PI / 2.0
		stall.setup(_roll_outcome(), rng)
		stall.opened.connect(_on_stall_opened)
		stalls.append(stall)
		stall_count += 1

	# Flickering fluorescent every few pairs.
	if pair_count % LIGHT_EVERY_N_PAIRS == 0:
		var fixture := MeshInstance3D.new()
		var tube := BoxMesh.new()
		tube.size = Vector3(0.15, 0.06, 1.4)
		fixture.mesh = tube
		var tube_mat := StandardMaterial3D.new()
		tube_mat.albedo_color = Color(0.9, 0.95, 0.9)
		tube_mat.emission_enabled = true
		tube_mat.emission = Color(0.8, 0.9, 0.8)
		fixture.material_override = tube_mat
		fixture.position = Vector3(0, 2.55, z)
		add_child(fixture)

		var light := FlickerLight.new()
		light.light_color = Color(0.85, 0.95, 0.85)
		light.base_energy = 1.4
		light.omni_range = 9.0
		light.position = Vector3(0, 2.3, z)
		add_child(light)

	# Occasional roamer in the corridor so combat happens between knocks too.
	if stall_count > 8 and rng.randf() < 0.15:
		_spawn_enemy(Vector3(rng.randf_range(-1.6, 1.6), 0, z))

	# Decorative plant in the gap between stall pairs now and then.
	if rng.randf() < 0.12:
		var plant: Node3D = PLANT_SCENE.instantiate()
		var ps := rng.randf_range(0.5, 0.7)
		plant.scale = Vector3(ps, ps, ps)
		plant.position = Vector3([-2.75, 2.75][rng.randi_range(0, 1)], 0.32 * ps, z + STALL_SPACING * 0.5)
		plant.rotation.y = rng.randf_range(0, TAU)
		add_child(plant)


func _roll_outcome() -> Stall.Outcome:
	if stall_count == free_stall_index and not _free_placed:
		_free_placed = true
		return Stall.Outcome.FREE
	var roll := rng.randi_range(0, W_HOSTILE + W_LOOT + W_FRIENDLY + W_EMPTY - 1)
	if roll < W_HOSTILE:
		return Stall.Outcome.HOSTILE
	roll -= W_HOSTILE
	if roll < W_LOOT:
		return Stall.Outcome.LOOT
	roll -= W_LOOT
	if roll < W_FRIENDLY:
		return Stall.Outcome.FRIENDLY
	return Stall.Outcome.EMPTY


func _on_stall_opened(stall: Stall, outcome: Stall.Outcome) -> void:
	match outcome:
		Stall.Outcome.HOSTILE:
			_show_message("OCCUPIED!! He's getting up!!")
			# The sitting man becomes a live, furious enemy.
			stall.clear_occupant()
			_spawn_enemy(stall.interior_point())
		Stall.Outcome.LOOT:
			if not player.has_plunger and rng.randf() < 0.4:
				player.give_plunger()
				_show_message("Someone left a PLUNGER! (bigger, stronger swings)")
			else:
				player.urgency = maxf(0.0, player.urgency - 18.0)
				_show_message("Empty... a moment of calm. (urgency down)")
		Stall.Outcome.FRIENDLY:
			# He stays seated. He's busy. But he's kind.
			if not player.has_plunger:
				player.give_plunger()
				_show_message("\"Take my plunger. Godspeed.\" (he does not get up)")
			else:
				player.urgency = maxf(0.0, player.urgency - 12.0)
				_show_message("\"Good luck out there.\" (urgency down)")
		Stall.Outcome.EMPTY:
			_show_message("Vacant... but unspeakable. Not this one.")
		Stall.Outcome.FREE:
			free_stall = stall
			_show_message("THE FREE STALL! But the queue jumpers arrive...", 4.0)
			# Guards burst out of the neighboring corridor, not out of walls.
			var z := stall.global_position.z
			for i in 3:
				_spawn_enemy(Vector3(rng.randf_range(-1.5, 1.5), 0, z + [-3.0, 3.0, -5.5][i]))


func _check_win() -> void:
	if not free_stall or not free_stall.is_open:
		return
	var dist := player.global_position.distance_to(free_stall.interior_point())
	if dist > 1.4:
		return
	if get_tree().get_nodes_in_group("enemies").size() > 0:
		if _warn_cooldown <= 0.0:
			_show_message("Deal with the queue jumpers first!")
			_warn_cooldown = 2.0
		return
	_end_game(true)


func _spawn_enemy(pos: Vector3) -> void:
	var e := ProtoEnemy.new()
	add_child(e)
	e.global_position = pos + Vector3(0, 0.1, 0)


func _on_player_hit() -> void:
	var tw := create_tween()
	tw.tween_property(_bar, "modulate", Color(1, 0.3, 0.3), 0.08)
	tw.tween_property(_bar, "modulate", Color.WHITE, 0.3)


func _on_player_died() -> void:
	_end_game(false)


func _end_game(won: bool) -> void:
	if game_ended:
		return
	game_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_overlay.visible = true
	if won:
		_overlay_label.text = "RELIEF AT LAST.\n\nYou found the one free stall.\n\nPress R to queue again"
	else:
		_overlay_label.text = "You didn't make it.\n\nWe don't talk about what happened.\n\nPress R to try again"


# --- world building -------------------------------------------------------


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.58)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.045, 0.05)
	env.fog_density = 0.06
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# One long box world. 1000m of bathroom is "infinite enough".
	var world := StaticBody3D.new()
	add_child(world)
	_world_box(world, Vector3(13, 1, 1000), Vector3(0, -0.5, -480), Color(0.55, 0.58, 0.6))       # floor
	_world_box(world, Vector3(13, 1, 1000), Vector3(0, 3.1, -480), Color(0.35, 0.36, 0.38))       # ceiling
	_world_box(world, Vector3(0.4, 3.4, 1000), Vector3(-5.7, 1.6, -480), Color(0.5, 0.47, 0.4))   # left wall
	_world_box(world, Vector3(0.4, 3.4, 1000), Vector3(5.7, 1.6, -480), Color(0.5, 0.47, 0.4))    # right wall
	_world_box(world, Vector3(13, 3.4, 0.4), Vector3(0, 1.6, 3.0), Color(0.5, 0.47, 0.4))         # back wall


func _world_box(body: StaticBody3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_inst.mesh = mesh
	mesh_inst.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	var host: Node = hud_parent if hud_parent else self
	host.add_child.call_deferred(hud)

	_bar = ProgressBar.new()
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.show_percentage = false
	_bar.position = Vector2(20, 20)
	_bar.size = Vector2(280, 28)
	hud.add_child(_bar)

	var bar_label := Label.new()
	bar_label.text = "  URGENCY"
	bar_label.position = Vector2(20, 22)
	hud.add_child(bar_label)

	# Crosshair dot.
	var cross := Label.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.text = "·"
	cross.add_theme_font_size_override("font_size", 34)
	cross.modulate = Color(1, 1, 1, 0.7)
	hud.add_child(cross)

	_msg = Label.new()
	_msg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_msg.offset_top = 64
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 26)
	_msg.modulate.a = 0.0
	hud.add_child(_msg)

	var hint := Label.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -44
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "WASD move  ·  mouse look  ·  LMB / Space swing  ·  E knock"
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.55)
	hud.add_child(hint)

	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.7)
	_overlay.visible = false
	hud.add_child(_overlay)

	_overlay_label = Label.new()
	_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 40)
	_overlay.add_child(_overlay_label)


func _show_message(text: String, duration: float = 2.5) -> void:
	_msg.text = text
	if _msg_tween:
		_msg_tween.kill()
	_msg.modulate.a = 1.0
	_msg_tween = create_tween()
	_msg_tween.tween_interval(duration)
	_msg_tween.tween_property(_msg, "modulate:a", 0.0, 0.6)
