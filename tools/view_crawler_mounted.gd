extends SceneTree
## Mount the new crawler FBX exactly like crawler.gd and screenshot.


func _initialize() -> void:
	const MODEL_SCALE := 0.12
	const MODEL_OFFSET := Vector3(0.4, 4.05, 8.5)

	var visual := Node3D.new()
	root.add_child(visual)

	var model: Node3D = (load("res://assets/crawler.fbx") as PackedScene).instantiate()
	model.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	model.position = MODEL_OFFSET * MODEL_SCALE
	visual.add_child(model)

	for mi in model.find_children("Eyes", "MeshInstance3D", true, false):
		mi.visible = false

	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var aname := String(ap.get_animation_list()[0])
	ap.get_animation(aname).loop_mode = Animation.LOOP_LINEAR
	ap.play(aname)
	ap.advance(ap.get_animation(aname).length * 0.45)

	# Floor grid reference.
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	floor_mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.32, 0.35)
	floor_mi.material_override = mat
	root.add_child(floor_mi)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(2.2, 1.4, 2.2)
	cam.look_at_from_position(cam.position, Vector3(0, 0.4, 0), Vector3.UP)
	cam.make_current()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(light)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	await process_frame
	await process_frame
	# Bone world bounds after our mount.
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for i in sk.get_bone_count():
		var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
		mn = mn.min(p)
		mx = mx.max(p)
	print("mounted bone world min=", mn, " max=", mx, " size=", mx - mn)

	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://crawler_mounted.png")
	print("saved")
	quit()
