extends SceneTree
## Quick visual of the fixed sink, centered and scaled.

const SINK_OFF := Vector3(11.8065, -0.1394, 36.0145)
const S := 0.16


func _initialize() -> void:
	var wrapper := Node3D.new()
	root.add_child(wrapper)
	wrapper.scale = Vector3(S, S, S)
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
	cam.position = Vector3(0, 1.1, -2.4)
	cam.rotation_degrees = Vector3(-8, 180, 0)
	cam.make_current()

	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://sink_fixed.png")
	quit()
