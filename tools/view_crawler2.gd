extends SceneTree
## Dev viewer: crawler with the leftover metarig removed, life-size.


func _initialize() -> void:
	var model: Node3D = (load("res://assets/crawler.glb") as PackedScene).instantiate()
	root.add_child(model)

	for child in model.find_children("metarig", "", true, false):
		print("removing ", child.get_path())
		child.get_parent().remove_child(child)
		child.queue_free()

	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	ap.get_animation("Crawl").loop_mode = Animation.LOOP_LINEAR
	ap.play("Crawl")
	ap.advance(0.5)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.4, 3.5)
	cam.rotation_degrees = Vector3(-15, 0, 0)
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
	root.get_viewport().get_texture().get_image().save_png("res://crawler_fixed_front.png")

	cam.position = Vector3(3.5, 1.4, -0.9)
	cam.rotation_degrees = Vector3(-15, 90, 0)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://crawler_fixed_side.png")
	quit()
