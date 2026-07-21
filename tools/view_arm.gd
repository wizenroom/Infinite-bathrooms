extends SceneTree
## Dev viewer: render the arm GLB alone from a known angle and screenshot it,
## so we can pick the viewmodel rotation/scale.


func _initialize() -> void:
	var arm: Node3D = (load("res://assets/arm.glb") as PackedScene).instantiate()
	root.add_child(arm)
	# Center it at origin using the measured AABB center.
	arm.position = -Vector3(-7.351, 10.096, -0.35)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0, 12)
	cam.make_current()

	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-40, 30, 0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://arm_front.png")

	cam.position = Vector3(12, 0, 0)
	cam.rotation_degrees = Vector3(0, 90, 0)
	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://arm_side.png")
	quit()
