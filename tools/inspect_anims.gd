extends SceneTree
## Dev tool: dumps animation track info for the man rig to check for root motion.

func _init() -> void:
	var ps: PackedScene = load("res://assets/man_animated.glb")
	var inst := ps.instantiate()
	root.add_child(inst)
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	for anim_name in ap.get_animation_list():
		var anim := ap.get_animation(anim_name)
		print(anim_name, "  length=", anim.length)
		for i in anim.get_track_count():
			if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
				var path := anim.track_get_path(i)
				var kc := anim.track_get_key_count(i)
				var first: Vector3 = anim.track_get_key_value(i, 0)
				var last: Vector3 = anim.track_get_key_value(i, kc - 1)
				print("  POS track ", path, "  first=", first, " last=", last, " keys=", kc)
	inst.free()
	quit()
