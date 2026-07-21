extends SceneTree
## Dev viewer: mount the broom under a camera exactly like player.gd does and
## screenshot, to tune the broom viewmodel transform.


func _initialize() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 72
	cam.near = 0.05
	cam.make_current()

	var pivot := Node3D.new()
	pivot.position = Vector3(0.3, -0.2, -0.45)
	pivot.rotation_degrees = Vector3(12, -6, 0)
	cam.add_child(pivot)

	var broom := Node3D.new()
	broom.scale = Vector3(0.55, 0.55, 0.55)
	broom.position = Vector3(-0.08, -0.18, -0.3)
	broom.rotation_degrees = Vector3(70, 10, 0)
	pivot.add_child(broom)
	var inst: Node3D = (load("res://assets/janitor_broom.glb") as PackedScene).instantiate()
	inst.position = -Vector3(3.568, 0.0758, -2.4754)
	broom.add_child(inst)

	# Print the raw AABB so the transform can be reasoned about.
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		print(mi.name, " aabb=", mi.global_transform * mi.get_aabb())

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.25, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://broom_pov.png")
	quit()
