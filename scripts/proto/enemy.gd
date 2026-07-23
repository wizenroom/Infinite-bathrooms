class_name ProtoEnemy
extends CharacterBody3D
## Melee occupant: chases the player, telegraphs with the punch wind-up
## animation, then lunges. Three fist hits (two plunger hits) to kill.
##
## Also doubles as the WANDERER when `neutral` is true: same man, but he's
## just... here, wandering the bathroom like you. Harmless until someone
## hits him. Hostiles use the same wander/idle brain whenever the player is
## out of aggro range, so nobody stands around like a mannequin anymore.

const MAN_SCENE := preload("res://assets/man_animated.glb")
## Wanderers get the newer skinned man export (same clip names, lighter mesh).
const WANDERER_SCENE := preload("res://assets/wanderer.glb")
const SPEECH_FONT := preload("res://assets/pixel_font.ttf")

const NPC_NAMES := [
	"GARY", "DALE", "PHIL", "MARV", "EUGENE", "CLIFF", "BORIS", "STAN",
	"OTIS", "REG", "WALT", "HUGO", "SEYMOUR", "TERRENCE", "KEV", "BART",
	"WIZEN", "SEAN", "ERIC", "ELON MUSK", "BILL GATES", "HAMILTON", "HAMLET",
	"DOOMSLAYER", "JOHN", "KEVIN", "JACK", "WALTER WHITE", "KENNEDY", "ETHAN",
	"NICK", "SANTA", "TYGO", "JOHN LENNON", "MARK BROWN", "IVAN", "OWEN", 
]

## Yelled at random while chasing the player.
const CHASE_LINES := [
	"GET OUT OF MY BATHROOM!",
	"YOU KNOCKED. I ANSWERED!",
	"THAT WAS MY STALL!",
	"COME HERE!",
	"I JUST WANTED PRIVACY!",
	"YOU LIFTED THE SEAT. THE SEAT!",
	"THERE'S NO PAPER ANYWHERE ANYWAY!",
	"I WASN'T DONE!",
]

## RMB'd a hostile mid-rampage. Bold move.
const HOSTILE_CHAT_LINES := [
	"TALK? NOW?!",
	"WE ARE PAST WORDS.",
	"RUN.",
	"APOLOGIZE TO THE SEAT.",
	"NO.",
	"F*** YOU"
]

## First time you talk to a wanderer he introduces himself.
const INTRO_LINES := [
	"I'm %s. Been in here... days? Weeks?",
	"Name's %s. Don't ask how I got here.",
	"%s. Former janitor. Currently... resident.",
	"They call me %s. The stalls know me.",
]

## General wanderer small talk.
const LORE_LINES := [
	"The stalls change when you're not looking.",
	"Don't trust the vacant signs.",
	"I heard something UNDER the floor.",
	"The janitor never came back for his cart.",
	"The exit's gone. I checked. Twice.",
	"I saw a tentacle once. I don't sit anymore.",
	"The lights hum a song. Listen.",
	"Some of these doors weren't here yesterday.",
]

const ADVICE_LINES := [
	"Knock first. ALWAYS knock.",
	"If the bowl gurgles, run.",
	"Save it for a clean one. Trust me.",
	"Don't lift a stranger's seat. Ever.",
	"The plunger is mightier than the fist.",
]

## When the player is visibly about to burst.
const URGENT_LINES := [
	"You look like you REALLY need to go.",
	"Dude. Just pick a stall.",
	"You're doing the dance. I know the dance.",
	"Hey, hey. Breathe. Clench.",
]

## A neutral guy who just got hit with a plunger.
const PROVOKED_LINES := [
	"THAT'S IT!",
	"I TRUSTED YOU!",
	"WRONG GUY. WRONG DAY.",
	"MY LAST NERVE!",
]

## Talked to again too soon.
const BORED_LINES := [
	"Enough small talk.",
	"I said what I said.",
	"Shouldn't you be finding a toilet?",
	"...",
]

## The lights start strobing and everyone KNOWS.
const RUSH_PANIC_LINES := [
	"HIDE!",
	"HE'S COMING!",
	"STALL. NOW!",
	"NOT AGAIN!",
	"MOVE MOVE MOVE!",
	"THE LIGHTS! GO!",
]

const SPEED := 3.7
const WANDER_SPEED := 1.4
const AGGRO_RANGE := 11.0
const WINDUP_TIME := 0.4
const STRIKE_TIME := 0.25
const RECOVER_TIME := 0.5
const ATTACK_ANIM_TIME := WINDUP_TIME + STRIKE_TIME

var hp := 3
## Wanderers: no aggro until provoked (hit once).
var neutral := false
var npc_name := ""

var _state := "chase"
var _timer := 0.0
var _has_struck := false
var _knockback := Vector3.ZERO
var _strike_dir := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _idle_timer := 0.0
var _flee_target := Vector3.ZERO
var _visual: Node3D
var _anim: AnimationPlayer
var _meshes: Array = []
var _flash_mat: StandardMaterial3D
var _player: Node3D
var _speech: Label3D
var _speech_token := 0
var _taunt_timer := 0.0
var _chat_cooldown := 0.0
var _chat_face := 0.0
var _said_intro := false


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

	var model: Node3D = (WANDERER_SCENE if neutral else MAN_SCENE).instantiate()
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
		_trim_dead_tails(_anim)
		for anim_name in ["Walk", "Run", "Sit"]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

	# Everybody in here has a name. It makes hitting them feel worse.
	npc_name = NPC_NAMES[randi_range(0, NPC_NAMES.size() - 1)]
	var tag := Label3D.new()
	tag.text = npc_name
	tag.font = SPEECH_FONT
	tag.font_size = 40
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.02, 0)
	tag.modulate = Color(0.8, 0.85, 0.8, 0.85)
	tag.visibility_range_end = 8.0
	add_child(tag)

	# Speech bubble: 3D text floating over the head, wrapped, short-lived.
	_speech = Label3D.new()
	_speech.font = SPEECH_FONT
	_speech.font_size = 30
	_speech.outline_size = 8
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.position = Vector3(0, 2.28, 0)
	# Anchored at the bottom so long wrapped lines grow UP, away from the
	# name tag under them.
	_speech.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_speech.width = 320.0
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD
	_speech.modulate = Color(1.0, 0.98, 0.85)
	_speech.visibility_range_end = 16.0
	_speech.visible = false
	add_child(_speech)

	if neutral:
		# Position isn't final until the manager places us; pick a target on
		# the first physics tick instead.
		_state = "idle"
		_idle_timer = randf_range(0.2, 1.5)


## The baked exports carry dead "empty frames" at the end of some clips
## (keys exist but nothing moves). Cut each clip at its last key that
## actually changes value so loops and holds don't sit through the padding.
static func _trim_dead_tails(ap: AnimationPlayer) -> void:
	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n)
		var last_change := 0.0
		for t in a.get_track_count():
			var kc := a.track_get_key_count(t)
			for k in range(kc - 1, 0, -1):
				var cur: Variant = a.track_get_key_value(t, k)
				var prev: Variant = a.track_get_key_value(t, k - 1)
				var changed := false
				match a.track_get_type(t):
					Animation.TYPE_POSITION_3D:
						changed = (cur as Vector3).distance_to(prev) > 0.0005
					Animation.TYPE_ROTATION_3D:
						changed = (cur as Quaternion).angle_to(prev) > 0.004
					_:
						changed = cur != prev
				if changed:
					last_change = maxf(last_change, a.track_get_key_time(t, k))
					break
		if last_change > 0.05 and last_change < a.length - 0.01:
			a.length = last_change


## 3D speech: the words live above his head in the scene, not on your HUD.
func say(text: String, dur := 2.6) -> void:
	if _state == "dead":
		return
	_speech_token += 1
	var token := _speech_token
	_speech.text = text
	_speech.visible = true
	get_tree().create_timer(dur).timeout.connect(func() -> void:
		if is_instance_valid(self) and _speech_token == token:
			_speech.visible = false
	)


## RMB chat. Wanderers stop and talk (diverse pools, context-aware).
## Hostiles... also respond, in their way - and might hesitate mid-chase.
func chat() -> void:
	if _state == "dead":
		return
	if not neutral:
		say(HOSTILE_CHAT_LINES[randi_range(0, HOSTILE_CHAT_LINES.size() - 1)], 1.8)
		# Talking to a rampage sometimes buys you half a second of confusion.
		if _state == "chase" and randf() < 0.3:
			_state = "recover"
			_timer = 0.7
		return
	if _chat_cooldown > 0.0:
		say(BORED_LINES[randi_range(0, BORED_LINES.size() - 1)], 1.6)
		return
	_chat_cooldown = 6.0
	# He stops walking and faces you for the exchange.
	_state = "idle"
	_idle_timer = maxf(_idle_timer, 2.6)
	_chat_face = 2.6
	var urgent := is_instance_valid(_player) and _player.get("urgency") != null \
		and float(_player.get("urgency")) > 70.0
	var line: String
	if not _said_intro:
		_said_intro = true
		line = INTRO_LINES[randi_range(0, INTRO_LINES.size() - 1)] % npc_name
	elif urgent and randf() < 0.5:
		line = URGENT_LINES[randi_range(0, URGENT_LINES.size() - 1)]
	elif randf() < 0.4:
		line = ADVICE_LINES[randi_range(0, ADVICE_LINES.size() - 1)]
	else:
		line = LORE_LINES[randi_range(0, LORE_LINES.size() - 1)]
	say(line, 3.2)


## Rush is coming: drop EVERYTHING and sprint for a stall. Even hostiles
## value their life over their grudge.
func rush_panic(spot: Vector3) -> void:
	if _state == "dead":
		return
	_flee_target = spot
	_state = "flee"
	if randf() < 0.7:
		say(RUSH_PANIC_LINES[randi_range(0, RUSH_PANIC_LINES.size() - 1)], 1.8)


## Rush has passed; whoever is still alive goes back to their business.
func rush_over() -> void:
	if _state == "flee" or _state == "hide":
		if neutral:
			_pick_wander_target()
		else:
			_state = "chase"


## Reached cover before Rush swept through?
func is_hidden() -> bool:
	return _state == "hide"


## Rush caught him in the open. There is no second opinion.
func rush_die() -> void:
	if _state != "dead":
		hp = 0
		_die()


func _pick_wander_target() -> void:
	_wander_target = Vector3(randf_range(-2.0, 2.0), 0, global_position.z + randf_range(-8.0, 8.0))
	_wander_timer = randf_range(3.0, 6.0)
	_state = "wander"


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

	_chat_cooldown = maxf(0.0, _chat_cooldown - delta)
	_chat_face = maxf(0.0, _chat_face - delta)

	match _state:
		"flee":
			# Sprint for the assigned stall, shrugging off knockback less
			# than usual - the alternative is death.
			var to_f := _flee_target - global_position
			to_f.y = 0
			if to_f.length() < 0.45:
				_state = "hide"
				velocity.x = _knockback.x
				velocity.z = _knockback.z
			else:
				var fd := to_f.normalized()
				velocity.x = fd.x * SPEED * 1.15 + _knockback.x
				velocity.z = fd.z * SPEED * 1.15 + _knockback.z
				_play("Run", 1.2)
		"hide":
			# Cower in the stall until the manager sounds the all-clear.
			# Shoved out (by a certain someone defending their stall)?
			# Scramble right back in.
			velocity.x = _knockback.x
			velocity.z = _knockback.z
			_play("Walk", 0.1)
			var back := _flee_target - global_position
			back.y = 0
			if back.length() > 0.7:
				_state = "flee"
		"wander":
			# Amble toward the current spot; hostiles snap to chase on sight.
			if not neutral and dist < AGGRO_RANGE:
				_state = "chase"
			else:
				_wander_timer -= delta
				var to_t := _wander_target - global_position
				to_t.y = 0
				if _wander_timer <= 0.0 or to_t.length() < 0.5:
					_state = "idle"
					_idle_timer = randf_range(1.0, 3.5)
					velocity.x = _knockback.x
					velocity.z = _knockback.z
				else:
					var wd := to_t.normalized()
					velocity.x = wd.x * WANDER_SPEED + _knockback.x
					velocity.z = wd.z * WANDER_SPEED + _knockback.z
					_play("Walk", 0.65)
		"idle":
			# Stand around, sway a little, then pick somewhere else to be.
			velocity.x = _knockback.x
			velocity.z = _knockback.z
			if not neutral and dist < AGGRO_RANGE:
				_state = "chase"
			else:
				_idle_timer -= delta
				_play("Walk", 0.1)
				if _idle_timer <= 0.0:
					_pick_wander_target()
		"chase":
			if dist > AGGRO_RANGE:
				# Lost interest: go back to wandering the bathroom.
				_pick_wander_target()
			else:
				velocity.x = dir.x * SPEED + _knockback.x
				velocity.z = dir.z * SPEED + _knockback.z
				_play("Run")
				# Hostiles narrate the chase. Loudly. In 3D.
				_taunt_timer -= delta
				if _taunt_timer <= 0.0:
					say(CHASE_LINES[randi_range(0, CHASE_LINES.size() - 1)], 2.0)
					_taunt_timer = randf_range(2.8, 5.0)
			if _state == "chase" and dist < 1.9:
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

	# NPCs bump brooms and carts around too - the bathroom feels lived-in.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb:
			rb.apply_central_impulse(-c.get_normal() * minf(rb.mass, 6.0) * 0.08)

	var face := Vector3(velocity.x, 0, velocity.z)
	if _state == "windup" or _state == "strike" or _chat_face > 0.0:
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
	# Wanderers don't stay neutral about being hit with a plunger. But mid-
	# Rush, survival beats revenge: stay fleeing, settle scores afterwards.
	if neutral:
		neutral = false
		if _state != "flee" and _state != "hide":
			_state = "chase"
			say(PROVOKED_LINES[randi_range(0, PROVOKED_LINES.size() - 1)], 2.0)
		else:
			say("AFTER. YOU'RE DEAD AFTER.", 1.6)
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
	_speech.visible = false
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
