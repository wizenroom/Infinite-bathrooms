extends SceneTree
## Dev viewer: sink and tree from 4 sides to determine facing.

const SINK_OFF := Vector3(10.9226, -0.1394, 36.0145)


func _initialize() -> void:
	var wrapper := Node3D.new()
	root.add_child(wrapper)
	wrapper.scale = Vector3(0.13, 0.13, 0.13)
	var sink: Node3D = (load("res://assets/sink_table.glb") as PackedScene).instantiate()
	sink.position = -SINK_OFF
	wrapper.add_child(sink)

	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-50, 25, 0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.25, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()

	var shots := {
		"sink_pz": [Vector3(0, 1.0, 3.0), Vector3(-8, 0, 0)],
		"sink_nz": [Vector3(0, 1.0, -3.0), Vector3(-8, 180, 0)],
		"sink_px": [Vector3(3.0, 1.0, 0), Vector3(-8, 90, 0)],
		"sink_nx": [Vector3(-3.0, 1.0, 0), Vector3(-8, -90, 0)],
	}
	for shot_name in shots:
		cam.position = shots[shot_name][0]
		cam.rotation_degrees = shots[shot_name][1]
		for i in 4:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://%s.png" % shot_name)
	quit()
