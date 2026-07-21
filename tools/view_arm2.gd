extends SceneTree
## Dev viewer: mount the arm under a camera exactly like player.gd does and
## screenshot, to debug viewmodel visibility.


func _initialize() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 72
	cam.near = 0.05
	cam.make_current()

	var pivot := Node3D.new()
	pivot.position = Vector3(0.32, -0.28, -0.5)
	cam.add_child(pivot)

	var arm := Node3D.new()
	arm.scale = Vector3(0.09, 0.09, 0.09)
	arm.rotation_degrees = Vector3(0, 90, 0)
	pivot.add_child(arm)
	var inst: Node3D = (load("res://assets/arm.glb") as PackedScene).instantiate()
	inst.position = -Vector3(-7.351, 10.096, -0.35)
	arm.add_child(inst)

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
	root.get_viewport().get_texture().get_image().save_png("res://arm_pov.png")
	quit()
