extends SceneTree
## Dev viewer: render the crawler with the same transform crawler.gd uses,
## from front and side, at two animation times.


func _initialize() -> void:
	var holder := Node3D.new()
	root.add_child(holder)

	var model: Node3D = (load("res://assets/crawler.glb") as PackedScene).instantiate()
	holder.add_child(model)

	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	ap.get_animation("Crawl").loop_mode = Animation.LOOP_LINEAR
	ap.play("Crawl")

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.5, -6.0)
	cam.rotation_degrees = Vector3(-5, 180, 0)
	cam.make_current()

	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-45, 30, 0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.25, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	for i in 8:
		await process_frame
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		print("mesh ", mi.name, " skinned_aabb=", mi.global_transform * mi.get_aabb())
	for sk in model.find_children("*", "Skeleton3D", true, false):
		print("skeleton ", sk.name, " bones=", sk.get_bone_count(), " xform=", sk.global_transform)
	root.get_viewport().get_texture().get_image().save_png("res://crawler_front.png")

	cam.position = Vector3(-6.0, 1.5, 0.8)
	cam.rotation_degrees = Vector3(-5, -90, 0)
	ap.advance(0.4)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://crawler_side.png")
	quit()
