extends Node3D
## Game manager: generates the infinite bathroom corridor ahead of the
## player, resolves knock outcomes, and runs HUD + win/lose.
## Lives inside the low-res SubViewport; the HUD is added to hud_parent
## (outside the viewport) so text stays crisp.
##
## Controls: WASD move, mouse look, LMB/Space swing, E knock, R restart (after end).

## Entity scenes (each is a root node + script; they build themselves).
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const CRAWLER_ENEMY_SCENE := preload("res://scenes/crawler.tscn")
const STALL_SCENE := preload("res://scenes/stall.tscn")

const PLANT_SCENE := preload("res://assets/plant.glb")
const FLOOR_TILE := preload("res://assets/floor_tile.glb")
const CEILING_TILE := preload("res://assets/ceiling_tile.glb")
const WALL_PANEL := preload("res://assets/wall.glb")

## The tile/wall meshes sit at a baked offset in their GLBs; cancel it out.
const TILE_BAKED_CENTER := Vector3(-15.24463, -1.17534, 0.300203)
const TILE_SIZE := 2.0
const CEILING_Y := 2.8
## Stall depth is 1.57 from the door plane at x=3.4, so backs end at 4.97.
const WALL_X := 5.17

## Corridor props: scene, baked offset to cancel (XZ center, Y bottom), scale,
## optional collision box (size + center) so they work as obstacles.
## The cart and broom moved out of here - they're physics objects now.
const PROP_DEFS := [
	{ "scene": preload("res://assets/wet_floor_sign.glb"), "off": Vector3(4.605, 0.0277, -0.0044), "scale": 0.18,
		"col_size": Vector3(0.35, 0.85, 0.25), "col_pos": Vector3(0, 0.42, 0) },
	{ "scene": preload("res://assets/plant.glb"), "off": Vector3(0, -0.32, 0), "scale": 0.6 },
	{ "scene": preload("res://assets/lamp.glb"), "off": Vector3(0, -0.5709, 0), "scale": 0.55,
		"col_size": Vector3(0.7, 3.4, 0.7), "col_pos": Vector3(0, 1.7, 0) },
]

## Pushable cart + fall-over-able broom (measured merged AABBs).
const CART_DEF := { "scene": preload("res://assets/janitor_cart.glb"),
	"off": Vector3(-0.246, 0.0, -0.0905) }
const BROOM_DEF := { "scene": preload("res://assets/janitor_broom.glb"),
	"off": Vector3(3.568, 0.0758, -2.4754) }
const BROOM_HEIGHT := 0.9

const SINK_SCENE := preload("res://assets/sink_table.glb")
const SINK_OFF := Vector3(11.8065, -0.1394, 36.0145)
const TENTACLE_SCENE := preload("res://assets/tentacle.fbx")
const TREE_SCENE := preload("res://assets/tree.glb")
const TREE_OFF := Vector3(1.438, -0.0163, -0.9305)

## The user's OPEN/CLOSE hanging light models double as the corridor lights,
## dangling from the ceiling. 1.52 x 0.41 flat signs; centers to cancel.
const CEIL_LIGHT_OPEN := preload("res://assets/light_open.glb")
const CEIL_LIGHT_CLOSED := preload("res://assets/light_closed.glb")
const CEIL_LIGHT_CENTERS := {
	"open": Vector3(0.0, 0.0, 0.0),
	"closed": Vector3(0.0, 0.0, -0.607684),
}
const CEIL_LIGHT_SCALE := 0.7
const CEIL_LIGHT_HEIGHT := 0.411

const STALL_SPACING := 1.4  # stall models are 1.29 wide; keep the row tight
const STALL_X := 3.4
const GEN_AHEAD := 45.0
const KNOCK_RANGE := 3.0
const LIGHT_EVERY_N_PAIRS := 5

# Knock outcome weights. No "prize stall" - every toilet is a gamble.
const W_HOSTILE := 45
const W_LOOT := 20
const W_FRIENDLY := 15
const W_EMPTY := 20

## Set by game_root before this node enters the tree.
var hud_parent: Node = null

var player: ProtoPlayer
var stalls: Array[Stall] = []
var stall_count := 0
var next_z := -4.0
var next_tile_z := 4.0
var pair_count := 0
var game_ended := false
var _warn_cooldown := 0.0
var rng := RandomNumberGenerator.new()

## --- Rush (the entity) -----------------------------------------------------
## Lights strobe for 5s (get to a stall!), then 4s of pitch black while he
## sweeps the corridor. Anyone in the open - player or NPC - dies.
# A JPEG despite the source file's .png name (same story as the slot art).
const RUSH_TEX := preload("res://assets/rush.jpg")
const RUSH_FLICKER_TIME := 5.0
const RUSH_DARK_TIME := 4.0
const RUSH_KILL_RADIUS := 1.8

var _rush_state := ""  # "" / "flicker" / "dark"
var _rush_timer := 0.0
var _next_rush := 0.0
var _rush_node: Node3D = null
var _rush_speed := 0.0
var _rush_wobble := 0.0
var _pending_death_text := ""

var _bar: ProgressBar
var _msg: Label
var _msg_tween: Tween
var _overlay: ColorRect
var _overlay_label: Label

## Everything spawned per-z, so geometry behind the player can be freed.
var _spawned: Array = []  # [{ "z": float, "node": Node }]
var _prop_merge_cache := {}

## Crawlers are pooled: built once at startup and woken on demand so spawn
## never hitch-instantiates the skinned mesh mid-game.
var _crawler_pool: Array = []

var _slot_frames: Array = []
var _slot_labels: Array = []
var _prompt: Label3D
var _prompt_hud: Label
var _prompt_pulse := 0.0


func _ready() -> void:
	rng.randomize()

	_build_environment()
	_build_hud()

	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.1, 0)
	add_child(player)
	player.died.connect(_on_player_died)
	player.hit.connect(_on_player_hit)
	player.inventory_changed.connect(_refresh_inventory)
	_refresh_inventory()  # show HAND in slot 1 from the start

	# Pool crawlers AFTER the player is on the floor, and only once physics
	# has settled - building them in the same frame as the player was the
	# roof-launch culprit.
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		for i in 2:
			var c: ProtoCrawler = CRAWLER_ENEMY_SCENE.instantiate()
			add_child(c)
			_crawler_pool.append(c)
	)

	# Floating 3D "E - ..." over the target (retro via the viewport) PLUS a
	# crisp HUD copy so the prompt is never missable through the pixel mess.
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Interaction hints get their own chunkier pixel-game font.
	_prompt.font = load("res://assets/pixel_game_font.otf")
	_prompt.font_size = 96
	_prompt.outline_size = 22
	_prompt.modulate = Color(0.85, 1.0, 0.55)
	_prompt.outline_modulate = Color(0, 0, 0, 0.95)
	_prompt.no_depth_test = true
	_prompt.pixel_size = 0.0045
	_prompt.visible = false
	add_child(_prompt)

	# Wanderers further down the hall - never on top of the spawn tile.
	# Deferred so the player's spawn transform is fully committed first;
	# spawning another CharacterBody3D in the same _ready was eating the
	# player's global_position (they both ended up on the wanderer tile).
	call_deferred("_spawn_starting_wanderers")

	_show_message("The bathroom goes on forever. Hold it together.", 4.5)


func _spawn_starting_wanderers() -> void:
	# Re-assert spawn before/after - belt and suspenders against the
	# same-frame CharacterBody3D transform clobber.
	player.global_position = Vector3(0, 0.1, 0)
	_spawn_wanderer(Vector3(-1.0, 0, -14.0))
	_spawn_wanderer(Vector3(1.2, 0, -22.0))
	player.global_position = Vector3(0, 0.1, 0)

	# Dev aid: PROTO_DEBUG=knock / PROTO_DEBUG=lid auto-opens the first
	# hostile / vacant stall so the interior can be checked without playing.
	var dbg := OS.get_environment("PROTO_DEBUG")
	if dbg == "dump":
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			for mi in find_children("*", "MeshInstance3D", true, false):
				var box: AABB = mi.global_transform * mi.get_aabb()
				if box.size.length() > 4.0 and box.position.z > -8.0:
					print("BIG: ", mi.get_path(), " box=", box)
			for e in get_tree().get_nodes_in_group("enemies"):
				print("ENEMY: ", e.get_script().resource_path.get_file(), " at ", e.global_position)
			print("player at ", player.global_position, " urgency=", player.urgency)
			print("dump done")
		)
	if dbg == "stress":
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_spawn_fallen_tree(player.global_position.z - 6.0)
			_spawn_fallen_tree(player.global_position.z - 10.0)
			_spawn_crawler(player.global_position + Vector3(-0.8, 0, -16.0))
			_spawn_crawler(player.global_position + Vector3(0.8, 0, -18.0))
		)
		# Report FPS while everything is alive, then bail (CI-style check).
		for t in [3.0, 4.5, 6.0, 7.5]:
			get_tree().create_timer(t).timeout.connect(func() -> void:
				print("STRESS fps=", Engine.get_frames_per_second())
			)
		get_tree().create_timer(8.5).timeout.connect(func() -> void:
			get_tree().quit()
		)
	if dbg == "tree":
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_spawn_fallen_tree(player.global_position.z - 7.0)
		)
	if dbg == "crawler":
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_spawn_crawler(player.global_position + Vector3(0.4, 0, -3.5))
		)
	if dbg == "inv":
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			player.add_item("plunger")
			player.add_item("broom")
		)
	if dbg == "sit":
		# End-to-end E-key path: knock an EMPTY stall, walk in, sit, resolve.
		var target: Array = [null]
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			for s in stalls:
				if s.outcome == Stall.Outcome.EMPTY and not s.is_open and s.global_position.z < -6.0:
					target[0] = s
					player.global_position = s.global_position + s.global_transform.basis.z * -1.8
					var dir := s.global_position - player.global_position
					player.rotation.y = atan2(-dir.x, -dir.z)
					print("SIT-TEST target1=", _interact_target().get("action"))
					_interact()
					print("SIT-TEST knocked: open=", s.is_open, " lid=", s.lid_open)
					# Step onto the tile in front of the bowl.
					player.global_position = s.to_global(Vector3(0, 0.1, 0.5))
					break
		)
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			print("SIT-TEST urgency before=", player.urgency)
			player.urgency = 30.0
			print("SIT-TEST target2=", _interact_target().get("action"))
			_interact()
		)
		get_tree().create_timer(7.0).timeout.connect(func() -> void:
			print("SIT-TEST urgency after=", player.urgency, " locked=", player.locked,
				" msg=", _msg.text, " player_y=", player.global_position.y)
			var s: Stall = target[0]
			if s:
				# Walk back out and close the door behind you like a gentleman.
				player.global_position = s.to_global(Vector3(0, 0.1, -1.3))
				var dir := s.global_position - player.global_position
				player.rotation.y = atan2(-dir.x, -dir.z)
				print("SIT-TEST target3=", _interact_target().get("action"))
				_interact()
				print("SIT-TEST closed: open=", s.is_open)
				print("SIT-TEST reopen-label=", _interact_target().get("label"))
			get_tree().quit()
		)
	if dbg == "disturb":
		# Yank the seat from under a seated occupant; he must go hostile.
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			for s in stalls:
				if (s.outcome == Stall.Outcome.FRIENDLY or s.outcome == Stall.Outcome.HOSTILE) \
						and not s.is_open and s.global_position.z < -6.0:
					player.global_position = s.global_position + s.global_transform.basis.z * -1.8
					var dir := s.global_position - player.global_position
					player.rotation.y = atan2(-dir.x, -dir.z)
					s.knock()
					print("DISTURB-TEST outcome=", s.outcome, " seated=", s.has_seated_occupant())
					if s.has_seated_occupant():
						print("DISTURB-TEST target=", _interact_target().get("action"))
						var before := get_tree().get_nodes_in_group("enemies").size()
						_interact()
						print("DISTURB-TEST enemies ", before, " -> ",
							get_tree().get_nodes_in_group("enemies").size(),
							" msg=", _msg.text)
					break
		)
		get_tree().create_timer(3.5).timeout.connect(func() -> void:
			print("DISTURB-TEST player_y=", player.global_position.y)
			get_tree().quit()
		)
	if dbg == "tent":
		# Visual check: tentacle erupting from an opened bowl.
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			for s in stalls:
				if not s.is_open and s.global_position.z < -5.0 and s.global_position.z > -12.0:
					s.knock()
					_spawn_tentacle(s)
					player.global_position = s.to_global(Vector3(0, 0.1, -2.0))
					var dir := s.global_position + Vector3(0, 0.8, 0) - player.global_position
					player.rotation.y = atan2(-dir.x, -dir.z)
					break
		)
		get_tree().create_timer(2.4).timeout.connect(func() -> void:
			_show_message("He's getting up. He knows what you did.")
		)
		get_tree().create_timer(2.8).timeout.connect(func() -> void:
			print("TENT-TEST urgency=", player.urgency)
			# Root window = retro viewport + HUD overlay together.
			get_tree().root.get_texture().get_image().save_png("res://tent_check.png")
			get_tree().quit()
		)
	if dbg == "tent2":
		# Second beat: mid-flail, urgency ticking.
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			for s in stalls:
				if not s.is_open and s.global_position.z < -5.0 and s.global_position.z > -12.0:
					s.knock()
					_spawn_tentacle(s)
					player.global_position = s.to_global(Vector3(0, 0.1, -1.2))
					var dir := s.global_position + Vector3(0, 1.2, 0) - player.global_position
					player.rotation.y = atan2(-dir.x, -dir.z)
					break
		)
		get_tree().create_timer(3.4).timeout.connect(func() -> void:
			print("TENT2-TEST urgency=", player.urgency)
			get_viewport().get_texture().get_image().save_png("res://tent2_check.png")
			get_tree().quit()
		)
	if dbg == "npc":
		# Chat check: wanderer in front, RMB'd programmatically.
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_spawn_wanderer(Vector3(0.4, 0, -5.5))
			player.global_position = Vector3(0.4, 0.1, -3.2)
			player.rotation.y = 0.0
		)
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			var npc := _chat_target()
			print("NPC-TEST target=", npc, " name=", npc.npc_name if npc is ProtoEnemy else "?")
			_chat()
		)
		get_tree().create_timer(3.4).timeout.connect(func() -> void:
			get_tree().root.get_texture().get_image().save_png("res://npc_check.png")
			get_tree().quit()
		)
	if dbg == "cart":
		# Cart + leaning broom in front of the player; shove the cart and
		# watch the broom lose its support.
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			var cart := _spawn_cart(Vector3(0.0, 0, -6.0), 0.0)
			# Deterministic extras so the screenshot always has both brooms:
			# one on the cart, one on the right wall.
			_spawn_broom(Vector3(0.82, 0, -6.0), Vector3(-1, 0, 0), 0.2, cart)
			_spawn_broom(Vector3(WALL_X - 0.32, 0, -5.2), Vector3(1, 0, 0))
			player.global_position = Vector3(0.5, 0.1, -3.0)
			player.rotation.y = -0.35
		)
		get_tree().create_timer(2.6).timeout.connect(func() -> void:
			get_tree().root.get_texture().get_image().save_png("res://cart_check1.png")
			for child in get_children():
				if child is RigidBody3D and child.mass > 10.0:
					child.apply_central_impulse(Vector3(3.0, 0, -40.0))
					print("CART-TEST shoved cart")
		)
		get_tree().create_timer(4.4).timeout.connect(func() -> void:
			for child in get_children():
				if child is RigidBody3D:
					print("CART-TEST body mass=", child.mass, " pos=", child.global_position,
						" rot=", child.rotation)
			get_tree().root.get_texture().get_image().save_png("res://cart_check2.png")
			get_tree().quit()
		)
	if dbg == "rush":
		# Full Rush sequence: flicker, blackout, sweep. Player stands in the
		# open on purpose - he should not survive this.
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_spawn_wanderer(Vector3(-1.2, 0, -8.0))
			_spawn_wanderer(Vector3(1.0, 0, -11.0))
			_start_rush()
			print("RUSH-TEST started, enemies=", get_tree().get_nodes_in_group("enemies").size())
		)
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			var hidden := 0
			for e in get_tree().get_nodes_in_group("enemies"):
				if e is ProtoEnemy and (e as ProtoEnemy).is_hidden():
					hidden += 1
			print("RUSH-TEST flicker phase, hidden=", hidden)
			get_tree().root.get_texture().get_image().save_png("res://rush1.png")
		)
		get_tree().create_timer(8.35).timeout.connect(func() -> void:
			print("RUSH-TEST dark phase, rush_z=", _rush_node.position.z if _rush_node else 0.0,
				" player_z=", player.global_position.z)
			get_tree().root.get_texture().get_image().save_png("res://rush2.png")
		)
		get_tree().create_timer(11.0).timeout.connect(func() -> void:
			print("RUSH-TEST over: game_ended=", game_ended,
				" overlay=", _overlay_label.text.replace("\n", " / "),
				" enemies_left=", get_tree().get_nodes_in_group("enemies").size())
			get_tree().root.get_texture().get_image().save_png("res://rush3.png")
			get_tree().quit()
		)
	if dbg == "rushsafe":
		# Survival path: player tucked inside an open stall must live, and
		# the corridor must come back to life afterwards.
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			for s in stalls:
				if s.global_position.z < -5.0 and s.global_position.z > -16.0 and not s.is_open:
					s.knock()
					if s.has_seated_occupant():
						continue
					player.global_position = s.interior_point() + Vector3(0, 0.1, 0)
					break
			print("RUSHSAFE-TEST in_stall=", _player_in_stall())
			_start_rush()
		)
		for t in [4.0, 6.4, 8.0, 10.0]:
			get_tree().create_timer(t).timeout.connect(func() -> void:
				var near := 0
				for e in get_tree().get_nodes_in_group("enemies"):
					if e.global_position.distance_to(player.global_position) < 1.6:
						near += 1
				print("RUSHSAFE-TEST t=", t, " pos=", player.global_position,
					" in_stall=", _player_in_stall(), " npcs_near=", near,
					" ended=", game_ended)
			)
		get_tree().create_timer(11.2).timeout.connect(func() -> void:
			print("RUSHSAFE-TEST game_ended=", game_ended, " rush_state='", _rush_state,
				"' lights_back=", not get_tree().get_nodes_in_group("flicker_lights")[0].blackout)
			get_tree().quit()
		)
	if dbg == "wanderer":
		# Stand in front of a fresh wanderer and screenshot the new model.
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_spawn_wanderer(Vector3(0.5, 0, -6.0))
			player.global_position = Vector3(0.5, 0.1, -3.5)
			player.rotation.y = 0.0
		)
		get_tree().create_timer(3.5).timeout.connect(func() -> void:
			get_viewport().get_texture().get_image().save_png("res://wanderer_check.png")
			get_tree().quit()
		)
	if dbg == "top":
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			var cam := Camera3D.new()
			add_child(cam)
			cam.global_position = Vector3(0, 2.4, 1.5)
			cam.rotation_degrees = Vector3(-15, 0, 0)
			cam.far = 200
			cam.fov = 85
			cam.make_current()
		)
	if dbg == "knock" or dbg == "lid":
		var want: Stall.Outcome = Stall.Outcome.HOSTILE if dbg == "knock" else Stall.Outcome.EMPTY
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			for s in stalls:
				if s.outcome == want and not s.is_open:
					player.global_position = s.global_position + s.global_transform.basis.z * -2.2
					player.look_at(s.global_position + Vector3(0, 1.2, 0))
					player.rotation.x = 0
					player._pitch = -0.35
					player._head.rotation.x = -0.35
					s.knock()
					break
		)


func _process(delta: float) -> void:
	if game_ended:
		return

	_warn_cooldown = maxf(0.0, _warn_cooldown - delta)

	_tick_rush(delta)

	# Keep the corridor generated ahead of the player.
	while next_z > player.global_position.z - GEN_AHEAD:
		_spawn_stall_pair(next_z)
		next_z -= STALL_SPACING
	while next_tile_z > player.global_position.z - GEN_AHEAD:
		_spawn_tile_row(next_tile_z)
		next_tile_z -= TILE_SIZE

	_prune_behind()

	_bar.value = player.urgency

	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E and not game_ended:
			_interact()
		elif event.physical_keycode == KEY_R and game_ended:
			get_tree().reload_current_scene()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT \
			and not game_ended and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_chat()


## One-off 3D speech at a world position (seated occupants, crawlers - anyone
## without their own bubble). Words live in the scene, not on the screen.
func _say_3d(pos: Vector3, text: String, dur := 3.0) -> void:
	var lab := Label3D.new()
	lab.text = text
	lab.font = load("res://assets/pixel_font.ttf")
	lab.font_size = 30
	lab.outline_size = 8
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lab.width = 320.0
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD
	lab.modulate = Color(1.0, 0.98, 0.85)
	add_child(lab)
	_track(lab, pos.z)
	lab.global_position = pos
	get_tree().create_timer(dur).timeout.connect(func() -> void:
		if is_instance_valid(lab):
			lab.queue_free()
	)


## The nearest conversable NPC roughly in front of the player.
func _chat_target() -> Node3D:
	var f: Vector3 = player.facing()
	var best: Node3D = null
	var best_score := 0.55
	for e in get_tree().get_nodes_in_group("enemies"):
		var to_e: Vector3 = e.global_position - player.global_position
		# Pooled crawlers park 60m below the floor - not conversable.
		if absf(to_e.y) > 2.0:
			continue
		to_e.y = 0
		var d := to_e.length()
		if d > 3.2 or d < 0.01:
			continue
		var score := f.dot(to_e.normalized())
		if score > best_score:
			best_score = score
			best = e
	return best


func _chat() -> void:
	var npc := _chat_target()
	if npc == null:
		return
	if npc is ProtoEnemy:
		(npc as ProtoEnemy).chat()
	else:
		# The crawler. It does not have a lot to say.
		_say_3d(npc.global_position + Vector3(0, 1.0, 0),
			["*wet gurgling*", "*slap slap slap*", "*a sound you will not forget*"].pick_random(), 2.0)


## What would E do right now? One resolver feeds both the floating prompt
## and the actual keypress, so what you read is always what you get.
## Returns {} or { "action", "stall", "point", "label" }.
func _interact_target() -> Dictionary:
	if player.locked or game_ended:
		return {}
	var f := player.facing()
	var best: Dictionary = {}
	var best_score := 0.15
	for s in stalls:
		var lp: Vector3 = s.to_local(player.global_position)
		var inside: bool = absf(lp.x) < 0.85 and lp.z > -0.15 and lp.z < Stall.STALL_DEPTH + 0.1
		# Standing in the doorway, looking in - still counts as "at the toilet".
		var at_doorway: bool = absf(lp.x) < 0.9 and lp.z > -1.4 and lp.z < 0.35
		var looking_in: bool = f.dot(s.global_transform.basis.z) > 0.35
		var cand := {}

		if not s.is_open:
			cand = { "action": "knock" if not s.resolved else "open", "stall": s,
				"point": s.to_global(Vector3(0, 1.4, -0.12)), "max_d": KNOCK_RANGE,
				"label": "E - KNOCK" if not s.resolved else "E - OPEN DOOR" }
		elif s.has_seated_occupant():
			# Occupied seat is ALWAYS openable - yanking it angers them.
			cand = { "action": "disturb", "stall": s,
				"point": s.to_global(Vector3(0, 1.15, 0.95)), "max_d": 3.2,
				"label": "E - OPEN LID" }
		elif (inside or (at_doorway and looking_in)) and not s.seat_used:
			# Prefer the toilet over closing the door when you're aimed at it.
			cand = { "action": "sit" if s.lid_open else "lid", "stall": s,
				"point": s.to_global(Vector3(0, 1.05, 1.0)), "max_d": 3.2,
				"label": "E - SIT" if s.lid_open else "E - OPEN LID" }
		else:
			cand = { "action": "close", "stall": s,
				"point": s.to_global(Vector3(0, 1.4, -0.12)), "max_d": 2.4,
				"label": "E - CLOSE DOOR" }

		var to_p: Vector3 = cand["point"] - player.global_position
		to_p.y = 0
		var d := to_p.length()
		if d > cand["max_d"]:
			continue
		var score: float = f.dot(to_p.normalized()) if d > 0.01 else 1.0
		if inside:
			score += 2.5
		elif at_doorway and looking_in and cand["action"] in ["lid", "sit", "disturb"]:
			score += 1.2
		if score > best_score:
			best_score = score
			best = cand
	return best


func _interact() -> void:
	var t := _interact_target()
	if t.is_empty():
		return
	var stall: Stall = t["stall"]
	match t["action"]:
		"knock", "open":
			stall.knock()
		"close":
			stall.close()
		"lid":
			stall.open_seat()
			_show_message("You lift the lid...")
		"sit":
			_sit_on(stall)
		"disturb":
			_disturb(stall)


## Yanking the lid out from under a seated occupant. He minds. A lot.
func _disturb(stall: Stall) -> void:
	var was_friendly := stall.outcome == Stall.Outcome.FRIENDLY
	stall.clear_occupant()
	stall.open_seat()
	if was_friendly:
		_show_message("He was NICE to you. Was.")
	else:
		_show_message("You lifted HIS seat. He objects. VIOLENTLY.")
	# Spawn clear of the player so physics can't catapult anyone.
	var pos := stall.interior_point()
	if pos.distance_to(player.global_position) < 1.1:
		pos = stall.to_global(Vector3(0, 0, -1.4))
	_spawn_enemy(pos).say("I WAS SITTING THERE!", 2.2)


## The toilet as a push-your-luck gamble: your body sits down on it while
## the camera pulls out to watch. Usually relief. Sometimes the bowl bites.
func _sit_on(stall: Stall) -> void:
	if player.locked:
		return
	if stall.seat_used:
		_show_message("No. Once was enough.")
		return
	stall.seat_used = true

	# Face out through the door, glide onto the seat, sit.
	var out_dir := -stall.global_transform.basis.z
	player.rotation.y = atan2(out_dir.x, out_dir.z) + PI
	player.locked = true
	var tw := create_tween()
	tw.tween_property(player, "global_position", stall.seat_point(), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(player.sit_down)
	tw.tween_interval(1.5)
	tw.tween_callback(func() -> void:
		if rng.randf() < 0.65:
			# The ONLY source of relief in the whole place now. Worth the risk.
			player.urgency = maxf(0.0, player.urgency - 35.0)
			_show_message("Sweet, shameful relief... (urgency WAY down)")
			get_tree().create_timer(0.8).timeout.connect(player.stand_up)
		else:
			_spawn_tentacle(stall)
			_show_message("SOMETHING IN THE BOWL!!")
			get_tree().create_timer(0.5).timeout.connect(func() -> void:
				player.stand_up()
				player.urgency = minf(100.0, player.urgency + 8.0)
				# The grab hurls you back out through the door.
				player.take_hit(out_dir)
			)
	)


## The tentacle FBX erupting out of the bowl - upright, animated, purple, and
## it squeezes your bladder: urgency ticks up while you stand next to it.
## Still no collider, so it can't physics-launch anybody - that bug is dead.
func _spawn_tentacle(stall: Stall) -> void:
	var wrapper := Node3D.new()
	add_child(wrapper)
	_track(wrapper, stall.global_position.z)
	wrapper.global_position = stall.seat_point() + Vector3(0, -0.05, 0)
	wrapper.global_rotation.y = stall.global_rotation.y

	var inst: Node3D = TENTACLE_SCENE.instantiate()
	# The FBX ships with its own Camera3D; that must never become current.
	for cam in inst.find_children("*", "Camera3D", true, false):
		cam.queue_free()
	# The FBX lies flat along Z; stand it up so it GROWS out of the bowl.
	inst.rotation.x = -PI / 2.0
	wrapper.add_child(inst)

	# Purple retro skin: same chunky nearest-filtered noise the trees use.
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _tree_retro_material(Color(0.58, 0.2, 0.75))

	var anims := inst.find_children("*", "AnimationPlayer", true, false)
	if anims.size() > 0:
		var ap: AnimationPlayer = anims[0]
		ap.play(String(ap.get_animation_list()[0]))

	# Erupt: swell up from the bowl instead of popping in at full size.
	wrapper.scale = Vector3(0.05, 0.05, 0.05)
	var grow := create_tween()
	grow.tween_property(wrapper, "scale", Vector3(0.55, 0.55, 0.55), 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Urgency damage: being near the flailing thing is bad for your bladder.
	var dmg := Timer.new()
	dmg.wait_time = 0.4
	dmg.autostart = true
	wrapper.add_child(dmg)
	dmg.timeout.connect(func() -> void:
		if wrapper.global_position.distance_to(player.global_position) < 2.3:
			player.urgency = minf(100.0, player.urgency + 2.5)
	)

	# Play the eruption, then sink back into the bowl.
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		if is_instance_valid(wrapper):
			var tw := create_tween()
			tw.tween_property(wrapper, "scale", Vector3(0.02, 0.02, 0.02), 0.35) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(wrapper.queue_free)
	)


# --- Rush -------------------------------------------------------------------

func _tick_rush(delta: float) -> void:
	match _rush_state:
		"":
			if _next_rush <= 0.0:
				# First scare lands a bit sooner than the steady rhythm.
				_next_rush = rng.randf_range(30.0, 45.0)
			_next_rush -= delta
			# Hold the scare until the corridor has grown some hiding spots.
			if _next_rush <= 0.0 and stall_count > 8:
				_start_rush()
		"flicker":
			_rush_timer -= delta
			if _rush_timer <= 0.0:
				_rush_go_dark()
		"dark":
			_rush_timer -= delta
			_move_rush(delta)
			if _rush_timer <= 0.0:
				_end_rush()


func _start_rush() -> void:
	_rush_state = "flicker"
	_rush_timer = RUSH_FLICKER_TIME
	for l in get_tree().get_nodes_in_group("flicker_lights"):
		l.panic = true
	_show_message("THE LIGHTS-- GET IN A STALL. NOW.")

	# Every NPC drops what they're doing and sprints for cover. Including
	# the one that was mid-swing at your face. Especially that one.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is ProtoEnemy:
			var spot := _nearest_hiding_spot(e.global_position)
			(e as ProtoEnemy).rush_panic(spot)


## Nearest usable stall interior for a panicking NPC. Open and unoccupied
## preferred; if there's nothing, the nearest door to die in front of.
func _nearest_hiding_spot(from: Vector3) -> Vector3:
	var best_spot := from
	var best_d := INF
	var fallback := from
	var fallback_d := INF
	for s in stalls:
		var d := s.global_position.distance_to(from)
		if d < fallback_d:
			fallback_d = d
			fallback = s.to_global(Vector3(0, 0, -0.6))
		if s.is_open and not s.has_seated_occupant() and d < best_d:
			best_d = d
			best_spot = s.interior_point()
	return best_spot if best_d < INF else fallback


func _rush_go_dark() -> void:
	_rush_state = "dark"
	_rush_timer = RUSH_DARK_TIME
	for l in get_tree().get_nodes_in_group("flicker_lights"):
		l.panic = false
		l.blackout = true
	_show_message("")

	# The entity itself: the painted face, glowing in the dark, coming from
	# the deep end of the corridor and screaming past the spawn side.
	_rush_node = Node3D.new()
	add_child(_rush_node)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = RUSH_TEX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Additive: the black canvas vanishes, the face and eyes burn.
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = mat
	_rush_node.add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.15, 0.1)
	glow.light_energy = 2.6
	glow.omni_range = 13.0
	_rush_node.add_child(glow)

	var start_z := player.global_position.z - 60.0
	var end_z := player.global_position.z + 24.0
	_rush_speed = (end_z - start_z) / RUSH_DARK_TIME
	_rush_node.position = Vector3(0, 1.45, start_z)


func _move_rush(delta: float) -> void:
	if _rush_node == null:
		return
	_rush_wobble += delta * 9.0
	_rush_node.position.z += _rush_speed * delta
	_rush_node.position.x = sin(_rush_wobble) * 0.9
	_rush_node.position.y = 1.45 + sin(_rush_wobble * 1.7) * 0.35

	var rz := _rush_node.position.z
	# The player: caught in the open when he passes = dead. No wounds, no
	# knockback, no negotiation.
	if absf(rz - player.global_position.z) < RUSH_KILL_RADIUS and not _player_in_stall():
		_pending_death_text = "RUSH.\n\nYou were not in a stall."
		player.die_instantly()
		return
	# NPCs still scrambling in the corridor get the same treatment.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is ProtoEnemy and not (e as ProtoEnemy).is_hidden() \
				and absf(e.global_position.z - rz) < RUSH_KILL_RADIUS \
				and absf(e.global_position.y) < 2.0:
			(e as ProtoEnemy).rush_die()


func _end_rush() -> void:
	_rush_state = ""
	_next_rush = rng.randf_range(40.0, 70.0)
	for l in get_tree().get_nodes_in_group("flicker_lights"):
		l.blackout = false
	if _rush_node:
		_rush_node.queue_free()
		_rush_node = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is ProtoEnemy:
			(e as ProtoEnemy).rush_over()
	_show_message("...it's gone. For now.")


## Physically inside any stall's footprint (door open or closed) = safe.
func _player_in_stall() -> bool:
	for s in stalls:
		var lp: Vector3 = s.to_local(player.global_position)
		if absf(lp.x) < 0.9 and lp.z > 0.0 and lp.z < Stall.STALL_DEPTH + 0.15:
			return true
	return false


## Keep the floating E-prompt glued to the current interact target.
func _update_prompt() -> void:
	_prompt_pulse += get_process_delta_time() * 4.0
	var pulse := 0.75 + 0.25 * sin(_prompt_pulse)
	var t := _interact_target()
	if t.is_empty():
		# No stall business in reach - maybe somebody to talk to instead.
		var npc := _chat_target()
		if npc != null:
			var label := "RMB - ...WHY?"
			if npc is ProtoEnemy:
				var pe := npc as ProtoEnemy
				label = ("RMB - TALK TO %s" if pe.neutral else "RMB - REASON WITH %s") % pe.npc_name
			# Chest height - the name tag and speech bubble own the head space.
			t = { "label": label, "point": npc.global_position + Vector3(0, 1.1, 0) }
		else:
			_prompt.visible = false
			if _prompt_hud:
				_prompt_hud.visible = false
			return
	_prompt.visible = true
	_prompt.text = t["label"]
	_prompt.global_position = t["point"] + Vector3(0, 0.28, 0)
	_prompt.modulate = Color(0.85, 1.0, 0.55, pulse)
	if _prompt_hud:
		_prompt_hud.visible = true
		_prompt_hud.text = t["label"]
		_prompt_hud.modulate = Color(0.9, 1.0, 0.65, pulse)


func _spawn_stall_pair(z: float) -> void:
	pair_count += 1
	for side in [-1, 1]:
		# Now and then a sink station interrupts the stall row.
		if pair_count > 2 and rng.randf() < 0.1:
			_spawn_sink(side, z)
			continue
		var stall: Stall = STALL_SCENE.instantiate()
		add_child(stall)
		_track(stall, z)
		stall.position = Vector3(side * STALL_X, 0, z)
		# Stall door faces local -Z; rotate so it faces the corridor center.
		stall.rotation.y = side * PI / 2.0
		stall.setup(_roll_outcome(), rng)
		stall.opened.connect(_on_stall_opened)
		stalls.append(stall)
		stall_count += 1

	# Hanging OPEN/CLOSE light every few pairs - the corridor's actual lighting.
	if pair_count % LIGHT_EVERY_N_PAIRS == 1:
		_spawn_ceiling_light(z)

	# Occasional roamer in the corridor so combat happens between knocks too.
	# Never within ~15m of the player so nobody gets jumped at spawn.
	var far_enough: bool = z < player.global_position.z - 15.0 if player else false
	if far_enough and stall_count > 12 and rng.randf() < 0.08:
		_spawn_enemy(Vector3(rng.randf_range(-1.6, 1.6), 0, z))
	# Deeper in, crawlers start skittering down the corridor.
	if far_enough and stall_count > 20 and rng.randf() < 0.04:
		_spawn_crawler(Vector3(rng.randf_range(-1.6, 1.6), 0, z))
	# Wanderers are harmless; they can appear anywhere, even near the player.
	if pair_count > 2 and rng.randf() < 0.1:
		_spawn_wanderer(Vector3(rng.randf_range(-1.8, 1.8), 0, z))

	# Janitorial clutter - never in the first ~10m (props were launching the
	# player onto the roof at spawn via depenetration).
	if pair_count > 6 and rng.randf() < 0.18:
		var r := rng.randf()
		var pz := z + STALL_SPACING * 0.5
		if r < 0.3:
			# Cart parked mid-corridor-ish, usually with its broom leaning on it.
			_spawn_cart(Vector3(rng.randf_range(-2.2, 2.2), 0, pz), rng.randf_range(0, TAU))
		elif r < 0.45:
			# Lone broom: always leaning against the corridor wall, never
			# free-standing in space like a haunted exhibit.
			var side := [-1.0, 1.0][rng.randi_range(0, 1)] as float
			_spawn_broom(Vector3(side * (WALL_X - 0.32), 0, pz), Vector3(side, 0, 0))
		else:
			var def: Dictionary = PROP_DEFS[rng.randi_range(0, PROP_DEFS.size() - 1)]
			var px: float = [-2.55, 2.55][rng.randi_range(0, 1)]
			if rng.randf() < 0.3:
				px = rng.randf_range(-1.4, 1.4)
			_spawn_prop(def, Vector3(px, 0, pz), rng.randf_range(0, TAU))

	# Rarely: an entire fallen tree, jammed diagonally through the building.
	if pair_count > 10 and rng.randf() < 0.025:
		_spawn_fallen_tree(z)


func _roll_outcome() -> Stall.Outcome:
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
			# He stays seated at first, glaring. Linger (or yank his seat)
			# and he gets up. Walk away fast enough and nothing happens.
			_show_message("OCCUPIED. He is glaring at you.")
			_say_3d(stall.seat_point() + Vector3(0, 1.35, 0), "DO YOU MIND?!", 2.2)
			get_tree().create_timer(rng.randf_range(2.5, 5.0)).timeout.connect(func() -> void:
				if is_instance_valid(stall) and stall.has_seated_occupant() \
						and stall.global_position.distance_to(player.global_position) < 7.0:
					stall.clear_occupant()
					_show_message("He's had ENOUGH. He's getting up!!")
					var pos := stall.interior_point()
					if pos.distance_to(player.global_position) < 1.1:
						pos = stall.to_global(Vector3(0, 0, -1.4))
					_spawn_enemy(pos).say("YOU COULDN'T JUST WALK AWAY!", 2.2)
			)
		Stall.Outcome.LOOT:
			if not player.has_plunger and rng.randf() < 0.4:
				player.give_plunger()
				_show_message("Someone left a PLUNGER! (stronger but slower swings)")
			else:
				# No freebies: doors don't relieve anything anymore. Only
				# actually sitting on a bowl lowers urgency now.
				_show_message("Empty. Staring at it helps nothing. SIT somewhere.")
		Stall.Outcome.FRIENDLY:
			# He stays seated. He's busy. But he's kind.
			if not player.has_plunger:
				player.give_plunger()
				_say_3d(stall.seat_point() + Vector3(0, 1.35, 0), "Take my plunger. Godspeed.", 3.0)
				_show_message("Got a PLUNGER! (stronger but slower swings)")
			else:
				_say_3d(stall.seat_point() + Vector3(0, 1.35, 0), "Good luck out there.", 3.0)
		Stall.Outcome.EMPTY:
			# Sometimes "vacant" just means whatever's in there doesn't count as a person.
			if stall_count > 16 and rng.randf() < 0.3:
				_show_message("...it was NOT empty. IT CRAWLS!!")
				_spawn_crawler(stall.interior_point())
			else:
				_show_message("Vacant... but unspeakable. Sit if you dare.")


func _spawn_enemy(pos: Vector3) -> ProtoEnemy:
	var e: ProtoEnemy = ENEMY_SCENE.instantiate()
	# Set local position BEFORE add_child - setting global_position on a
	# brand-new CharacterBody3D in the same _ready as the player was
	# clobbering the player's transform (both ended up on one tile).
	e.position = pos + Vector3(0, 0.1, 0)
	add_child(e)
	return e


## A Wanderer: same guy, zero malice. He's just also stuck in here, pacing
## the corridor like you. Hitting him changes his mind about the "zero malice".
func _spawn_wanderer(pos: Vector3) -> void:
	var e: ProtoEnemy = ENEMY_SCENE.instantiate()
	e.neutral = true
	e.position = pos + Vector3(0, 0.1, 0)
	add_child(e)


func _spawn_crawler(pos: Vector3) -> void:
	# Wake a pooled crawler; when both are already loose, a regular occupant
	# steps in instead (more than 2 of these models alive tanks the GPU).
	for c in _crawler_pool:
		if c.sleeping:
			c.wake(pos + Vector3(0, 0.1, 0))
			return
	_spawn_enemy(pos)


func _track(node: Node, z: float) -> void:
	_spawned.append({ "z": z, "node": node })


## Free world geometry the player has left behind. Without this the corridor
## accumulates forever and the frame rate dies a slow death.
func _prune_behind() -> void:
	var cutoff := player.global_position.z + 12.0
	var kept: Array = []
	for entry in _spawned:
		# Untyped on purpose: tracked nodes can be freed elsewhere (broom
		# pickups free their wrapper); a typed assignment would error on them.
		var node = entry["node"]
		if not is_instance_valid(node):
			continue
		if entry["z"] > cutoff:
			if node is Stall:
				stalls.erase(node)
			node.queue_free()
		else:
			kept.append(entry)
	_spawned = kept

	# Enemies abandoned far behind stop mattering; cull them too.
	# Pooled crawlers go back to sleep instead of being freed.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.z > player.global_position.z + 20.0:
			if e is ProtoCrawler:
				e.sleep()
			else:
				e.queue_free()


## The corridor lighting: one of the OPEN/CLOSE hanging light models dangling
## from the ceiling, sign face toward the walker, with the flicker light in it.
func _spawn_ceiling_light(z: float) -> void:
	var open := rng.randf() < 0.5
	var scene: PackedScene = CEIL_LIGHT_OPEN if open else CEIL_LIGHT_CLOSED
	var center: Vector3 = CEIL_LIGHT_CENTERS["open"] if open else CEIL_LIGHT_CENTERS["closed"]

	var wrapper := Node3D.new()
	add_child(wrapper)
	_track(wrapper, z)
	wrapper.scale = Vector3(CEIL_LIGHT_SCALE, CEIL_LIGHT_SCALE, CEIL_LIGHT_SCALE)
	# Model bottom sits at its local y=0; hang so the top touches the ceiling.
	wrapper.position = Vector3(0, CEILING_Y - CEIL_LIGHT_HEIGHT * CEIL_LIGHT_SCALE, z)
	var inst: Node3D = scene.instantiate()
	inst.position = -center
	wrapper.add_child(inst)

	var light := FlickerLight.new()
	# OPEN glows the sickly green, CLOSED glows dirty red - so the corridor
	# breathes in alternating colors as you go.
	light.light_color = Color(0.75, 0.95, 0.75) if open else Color(0.95, 0.7, 0.65)
	light.base_energy = 1.4
	light.omni_range = 9.0
	light.position = Vector3(0, CEILING_Y - 0.5, z)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 24.0
	light.distance_fade_length = 8.0
	add_child(light)
	_track(light, z)


func _spawn_prop(def: Dictionary, pos: Vector3, yaw: float) -> void:
	var wrapper := Node3D.new()
	add_child(wrapper)
	_track(wrapper, pos.z)
	var s: float = def["scale"]
	wrapper.scale = Vector3(s, s, s)
	wrapper.position = pos
	wrapper.rotation.y = yaw

	# Merged single-mesh version (the cart alone is 82 MeshInstances raw),
	# hidden past the fog.
	if not _prop_merge_cache.has(def["scene"]):
		_prop_merge_cache[def["scene"]] = MeshMerge.merge_scene(def["scene"])["mesh"]
	var mi := MeshInstance3D.new()
	mi.mesh = _prop_merge_cache[def["scene"]]
	mi.position = -def["off"]
	mi.visibility_range_end = 32.0
	wrapper.add_child(mi)

	if def.has("col_size"):
		var body := StaticBody3D.new()
		add_child(body)
		_track(body, pos.z)
		body.position = pos
		body.rotation.y = yaw
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = def["col_size"] * s
		col.shape = shape
		col.position = def["col_pos"] * s
		body.add_child(col)

	# Pickup props (the broom): walk over it to grab it into the inventory.
	if def.has("pickup_item"):
		var item: String = def["pickup_item"]
		var area := Area3D.new()
		wrapper.add_child(area)
		var acol := CollisionShape3D.new()
		var asphere := SphereShape3D.new()
		asphere.radius = 0.8
		acol.shape = asphere
		acol.position.y = 0.4
		area.add_child(acol)
		area.body_entered.connect(func(body_in: Node3D) -> void:
			if body_in is ProtoPlayer and body_in.add_item(item):
				_show_message("Picked up the %s! (1-4 to switch items)" % item.to_upper())
				wrapper.queue_free()
		)


## The janitorial cart is a real physics object now: shove it and it rolls.
## Rotation is locked to yaw so it can't tip into the geometry.
func _spawn_cart(pos: Vector3, yaw: float) -> RigidBody3D:
	var cart := RigidBody3D.new()
	cart.mass = 30.0
	cart.axis_lock_angular_x = true
	cart.axis_lock_angular_z = true
	cart.linear_damp = 3.5
	cart.angular_damp = 6.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	cart.physics_material_override = pm
	add_child(cart)
	_track(cart, pos.z)
	cart.position = pos
	cart.rotation.y = yaw

	if not _prop_merge_cache.has(CART_DEF["scene"]):
		_prop_merge_cache[CART_DEF["scene"]] = MeshMerge.merge_scene(CART_DEF["scene"])["mesh"]
	var mi := MeshInstance3D.new()
	mi.mesh = _prop_merge_cache[CART_DEF["scene"]]
	mi.position = -CART_DEF["off"]
	mi.visibility_range_end = 32.0
	cart.add_child(mi)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.25, 1.09, 0.7)
	col.shape = box
	col.position = Vector3(0, 0.56, 0)
	cart.add_child(col)

	# The janitor's broom usually stays with his cart, leaning on it. Shove
	# the cart out from under it and physics does the rest.
	if rng.randf() < 0.7:
		var side_dir := Vector3(cos(yaw), 0, -sin(yaw))
		if rng.randf() < 0.5:
			side_dir = -side_dir
		_spawn_broom(pos + side_dir * 0.82, -side_dir, 0.2, cart)
	return cart


## A broom that actually leans (on a wall or the cart) and falls over when
## disturbed. Never free-standing - brooms don't do that. `support` is the
## body it leans on: touching it doesn't drop the broom, but taking it AWAY does.
func _spawn_broom(pos: Vector3, lean_dir: Vector3, tilt := 0.36, support: PhysicsBody3D = null) -> void:
	var broom := RigidBody3D.new()
	broom.mass = 1.5
	broom.linear_damp = 0.3
	broom.angular_damp = 0.5
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	broom.physics_material_override = pm
	add_child(broom)
	_track(broom, pos.z)
	broom.position = pos + Vector3(0, 0.05, 0)
	# Yaw local +Z toward the support, then pitch into the lean.
	broom.rotation = Vector3(tilt, atan2(lean_dir.x, lean_dir.z), 0.0)
	# Frozen in the lean - raw physics let it slide down the wall on spawn.
	# The first PERSON (or cart) that touches it unfreezes it, and over it goes.
	broom.freeze = true

	if not _prop_merge_cache.has(BROOM_DEF["scene"]):
		_prop_merge_cache[BROOM_DEF["scene"]] = MeshMerge.merge_scene(BROOM_DEF["scene"])["mesh"]
	var mi := MeshInstance3D.new()
	mi.mesh = _prop_merge_cache[BROOM_DEF["scene"]]
	mi.position = -BROOM_DEF["off"]
	mi.visibility_range_end = 32.0
	broom.add_child(mi)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, BROOM_HEIGHT - 0.04, 0.1)
	col.shape = box
	col.position = Vector3(0, BROOM_HEIGHT * 0.5 + 0.05, 0)
	broom.add_child(col)

	# Still a pickup: walk over it (fallen or not) to grab it.
	var area := Area3D.new()
	broom.add_child(area)
	var acol := CollisionShape3D.new()
	var asphere := SphereShape3D.new()
	asphere.radius = 0.6
	acol.shape = asphere
	acol.position.y = 0.35
	area.add_child(acol)
	area.body_entered.connect(func(body_in: Node3D) -> void:
		if body_in is ProtoPlayer and body_in.add_item("broom"):
			_show_message("Picked up the BROOM! (1-4 to switch items)")
			broom.queue_free()
			return
		# Bumped by a person or a stray cart (never the floor, never its own
		# support): drop the lean.
		if body_in is CharacterBody3D \
				or (body_in is RigidBody3D and body_in != broom and body_in != support):
			broom.freeze = false
	)
	if support != null:
		# The cart rolled out from under it: gravity resumes.
		area.body_exited.connect(func(body_out: Node3D) -> void:
			if body_out == support and is_instance_valid(broom):
				broom.freeze = false
		)


## Sink station in place of a stall: back against the side wall, mirror
## facing the corridor, with a small collision block.
func _spawn_sink(side: int, z: float) -> void:
	const SINK_SCALE := 0.16
	# Model depth ~5.3 units * scale ~ 0.85; keep its back at the wall.
	var x: float = side * (WALL_X - 0.45)
	# Two basins side by side, filling the width the missing stall leaves.
	for dz in [-0.35, 0.35]:
		var wrapper := Node3D.new()
		add_child(wrapper)
		_track(wrapper, z)
		wrapper.scale = Vector3(SINK_SCALE, SINK_SCALE, SINK_SCALE)
		wrapper.position = Vector3(x, 0, z + dz)
		# Basin lip faces -Z in model space (like the stall doors); turn it
		# toward the corridor center.
		wrapper.rotation.y = side * PI / 2.0
		var inst: Node3D = SINK_SCENE.instantiate()
		inst.position = -SINK_OFF
		wrapper.add_child(inst)

	var body := StaticBody3D.new()
	add_child(body)
	_track(body, z)
	body.position = Vector3(x, 0.6, z)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.2, 0.8)
	col.shape = shape
	body.add_child(col)

	# A greasy little mirror light so the station reads from afar.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.8, 0.85, 1.0)
	lamp.light_energy = 0.6
	lamp.omni_range = 2.5
	lamp.position = Vector3(x, 1.8, z)
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 18.0
	lamp.distance_fade_length = 6.0
	add_child(lamp)
	_track(lamp, z)


## Random-tint canopy palette: mostly plausible greens, occasionally wrong.
const TREE_CANOPY_TINTS := [
	Color(0.25, 0.55, 0.2), Color(0.15, 0.4, 0.18), Color(0.7, 0.45, 0.12),
	Color(0.65, 0.6, 0.2), Color(0.55, 0.2, 0.5), Color(0.3, 0.5, 0.55),
]
const TREE_TRUNK_TINTS := [
	Color(0.4, 0.28, 0.18), Color(0.35, 0.32, 0.3), Color(0.45, 0.22, 0.15),
]

var _tree_noise_tex: NoiseTexture2D = null


## A huge tree jammed through the bathroom, clipping floor and ceiling.
## Two flavors: steeply LEANING (trunk is a solid obstacle to shoulder past)
## and fully FALLEN, near-horizontal overhead (set dressing only - a collidable
## horizontal trunk would wall off the corridor and soft-lock the run).
func _spawn_fallen_tree(z: float) -> void:
	var wrapper := Node3D.new()
	add_child(wrapper)
	_track(wrapper, z)
	var s := rng.randf_range(0.9, 1.3)
	wrapper.scale = Vector3(s, s, s)
	var leaning := rng.randf() < 0.6
	if leaning:
		wrapper.position = Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(0.0, 0.7), z)
		wrapper.rotation = Vector3(
			rng.randf_range(-0.55, 0.55),
			rng.randf_range(0, TAU),
			rng.randf_range(-0.55, 0.55),
		)
	else:
		wrapper.position = Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(0.2, 1.2), z)
		wrapper.rotation = Vector3(
			rng.randf_range(-0.5, 0.5) + [-1.9, 1.9][rng.randi_range(0, 1)],
			rng.randf_range(0, TAU),
			rng.randf_range(-0.4, 0.4),
		)
	var inst: Node3D = TREE_SCENE.instantiate()
	inst.position = -Vector3(TREE_OFF.x, 4.5, TREE_OFF.z)  # pivot near trunk middle
	wrapper.add_child(inst)

	# Random retro texture: pixel noise + a random tint per tree. The mesh
	# with the biggest bounds is the canopy, the rest is trunk.
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	var canopy: MeshInstance3D = null
	var best_vol := -1.0
	for mi in meshes:
		var v: float = mi.get_aabb().get_volume()
		if v > best_vol:
			best_vol = v
			canopy = mi
	var canopy_tint: Color = TREE_CANOPY_TINTS[rng.randi_range(0, TREE_CANOPY_TINTS.size() - 1)]
	var trunk_tint: Color = TREE_TRUNK_TINTS[rng.randi_range(0, TREE_TRUNK_TINTS.size() - 1)]
	for mi in meshes:
		mi.material_override = _tree_retro_material(canopy_tint if mi == canopy else trunk_tint)
		# 345k triangles; stop rendering it once the fog has swallowed it.
		mi.visibility_range_end = 42.0

	# Trunk collider along the tree's local up-axis (pivot sits mid-trunk).
	if leaning:
		var body := StaticBody3D.new()
		wrapper.add_child(body)
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 9.0
		col.shape = cap
		body.add_child(col)


func _tree_retro_material(tint: Color) -> StandardMaterial3D:
	if _tree_noise_tex == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.2
		_tree_noise_tex = NoiseTexture2D.new()
		_tree_noise_tex.noise = noise
		_tree_noise_tex.width = 48
		_tree_noise_tex.height = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tree_noise_tex
	mat.albedo_color = tint
	# Chunky nearest-filtered noise = the retro look.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(4, 4, 4)
	mat.roughness = 1.0
	return mat


func _on_player_hit() -> void:
	var tw := create_tween()
	tw.tween_property(_bar, "modulate", Color(1, 0.3, 0.3), 0.08)
	tw.tween_property(_bar, "modulate", Color.WHITE, 0.3)


func _on_player_died() -> void:
	_end_game(false, _pending_death_text)


func _end_game(won: bool, custom := "") -> void:
	if game_ended:
		return
	game_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_overlay.visible = true
	if won:
		_overlay_label.text = "RELIEF AT LAST.\n\nPress R to queue again"
	elif custom != "":
		_overlay_label.text = custom + "\n\nPress R to try again"
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

	# One long box world; floor/ceiling are collision-only, the tile models
	# provide the visuals. Walls sit flush against the stall backs.
	var world := StaticBody3D.new()
	add_child(world)
	_world_box(world, Vector3(13, 1, 1000), Vector3(0, -0.5, -480), Color.BLACK, false)                    # floor
	_world_box(world, Vector3(13, 1, 1000), Vector3(0, CEILING_Y + 0.51, -480), Color.BLACK, false)        # ceiling
	_world_box(world, Vector3(0.4, 3.4, 1000), Vector3(-WALL_X - 0.21, 1.6, -480), Color.BLACK, false)     # left wall
	_world_box(world, Vector3(0.4, 3.4, 1000), Vector3(WALL_X + 0.21, 1.6, -480), Color.BLACK, false)      # right wall
	_world_box(world, Vector3(11, 3.4, 0.4), Vector3(0, 1.6, 3.0), Color(0.5, 0.47, 0.4))                  # back wall


func _world_box(body: StaticBody3D, size: Vector3, pos: Vector3, color: Color, visible_mesh := true) -> void:
	if visible_mesh:
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


func _spawn_tile_row(z: float) -> void:
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		_place_tile(FLOOR_TILE, Vector3(x, -0.005, z))
		_place_tile(CEILING_TILE, Vector3(x, CEILING_Y, z))
	# Wall panels standing upright, textured face toward the corridor.
	_place_tile(WALL_PANEL, Vector3(-WALL_X, CEILING_Y / 2.0, z), PI / 2.0)
	_place_tile(WALL_PANEL, Vector3(WALL_X, CEILING_Y / 2.0, z), -PI / 2.0)


func _place_tile(scene: PackedScene, pos: Vector3, roll := 0.0) -> void:
	var wrapper := Node3D.new()
	add_child(wrapper)
	_track(wrapper, pos.z)
	wrapper.position = pos
	if roll != 0.0:
		# Standing panel: the 2m tile only covers 2 of the 2.8m height.
		wrapper.scale.y = CEILING_Y / TILE_SIZE
	var rot := Node3D.new()
	rot.rotation.z = roll
	wrapper.add_child(rot)
	var inst: Node3D = scene.instantiate()
	inst.position = -TILE_BAKED_CENTER
	rot.add_child(inst)


func _build_hud() -> void:
	# PixelI for the readouts (urgency, messages, inventory, overlays);
	# the E-prompts use the chunkier PixelGame font, set where they're built.
	# Explicit per-label overrides - the built-in theme beats any fallback.
	var ui_font: Font = load("res://assets/pixel_font.ttf")

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
	bar_label.add_theme_font_override("font", ui_font)
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

	# Crisp on-screen interaction prompt (above the crosshair). Always readable
	# even when the 3D Label3D gets lost in the pixel shader / fog.
	_prompt_hud = Label.new()
	_prompt_hud.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_hud.offset_top = 36
	_prompt_hud.offset_bottom = 72
	_prompt_hud.offset_left = -220
	_prompt_hud.offset_right = 220
	_prompt_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_hud.add_theme_font_override("font", load("res://assets/pixel_game_font.otf"))
	_prompt_hud.add_theme_font_size_override("font_size", 28)
	_prompt_hud.modulate = Color(0.9, 1.0, 0.65)
	_prompt_hud.visible = false
	hud.add_child(_prompt_hud)

	_msg = Label.new()
	_msg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_msg.offset_top = 64
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_override("font", ui_font)
	_msg.add_theme_font_size_override("font_size", 26)
	_msg.modulate.a = 0.0
	hud.add_child(_msg)

	# Inventory: four painted slot frames, nearest-filtered so the scaled-down
	# brush strokes go chunky instead of blurry (matches the retro filter).
	var slot_tex := AtlasTexture.new()
	# The provided slot art is a JPEG (black canvas, no alpha) despite the
	# original .png name; crop the painted frame out of the canvas.
	slot_tex.atlas = load("res://assets/inventory_slot.jpg")
	slot_tex.region = Rect2(195, 175, 505, 540)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.offset_left = 20
	row.offset_top = -140
	row.offset_bottom = -60
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override("separation", 10)
	hud.add_child(row)
	for i in 4:
		var frame := TextureRect.new()
		frame.texture = slot_tex
		frame.custom_minimum_size = Vector2(76, 80)
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(frame)

		var num := Label.new()
		num.text = str(i + 1)
		num.position = Vector2(10, 4)
		num.add_theme_font_override("font", ui_font)
		num.add_theme_font_size_override("font_size", 13)
		num.modulate = Color(1, 1, 1, 0.6)
		frame.add_child(num)

		var lab := Label.new()
		lab.set_anchors_preset(Control.PRESET_FULL_RECT)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.add_theme_font_override("font", ui_font)
		lab.add_theme_font_size_override("font_size", 12)
		lab.modulate = Color(0.75, 1.0, 0.75)
		frame.add_child(lab)

		_slot_frames.append(frame)
		_slot_labels.append(lab)

	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.7)
	_overlay.visible = false
	hud.add_child(_overlay)

	_overlay_label = Label.new()
	_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_override("font", ui_font)
	_overlay_label.add_theme_font_size_override("font_size", 40)
	_overlay.add_child(_overlay_label)


func _refresh_inventory() -> void:
	if not player:
		return
	for i in _slot_frames.size():
		var item: String = player.inventory[i]
		_slot_labels[i].text = item.to_upper()
		var selected: bool = player.equipped_slot == i and item != ""
		_slot_frames[i].modulate = Color(1, 1, 1, 1) if selected else Color(0.7, 0.7, 0.7, 0.65)


func _show_message(text: String, duration: float = 2.5) -> void:
	_msg.text = text
	if _msg_tween:
		_msg_tween.kill()
	_msg.modulate.a = 1.0
	_msg_tween = create_tween()
	_msg_tween.tween_interval(duration)
	_msg_tween.tween_property(_msg, "modulate:a", 0.0, 0.6)
