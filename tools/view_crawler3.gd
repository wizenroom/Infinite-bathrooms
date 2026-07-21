extends SceneTree
## Dev viewer: crawler at corrected scale/offset, 4 angles.

const S := 0.12
## Animated bone bounds in model space: lo(-6.7,-4.05,-15.6) hi(5.9,1.9,-1.4).
const OFFSET := Vector3(0.4, 4.05, 8.5)  # recenter XZ, lift lowest bone to ground


func _initialize() -> void:
	var holder := Node3D.new()
	root.add_child(holder)

	var model: Node3D = (load("res://assets/crawler.glb") as PackedScene).instantiate()
	model.scale = Vector3(S, S, S)
	model.position = OFFSET * S
	holder.add_child(model)

	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	ap.get_animation("Crawl").loop_mode = Animation.LOOP_LINEAR
	ap.play("Crawl")
	ap.advance(0.5)

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

	# Ground reference plane.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	ground.mesh = pm
	root.add_child(ground)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()

	var shots := {
		"crawler_v3_front": [Vector3(0, 1.2, -3.5), Vector3(-12, 180, 0)],
		"crawler_v3_back": [Vector3(0, 1.2, 3.5), Vector3(-12, 0, 0)],
		"crawler_v3_side": [Vector3(-3.5, 1.2, 0), Vector3(-12, -90, 0)],
		"crawler_v3_top": [Vector3(0, 5, 0.01), Vector3(-89, 0, 0)],
	}
	for shot_name in shots:
		cam.position = shots[shot_name][0]
		cam.rotation_degrees = shots[shot_name][1]
		for i in 5:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://%s.png" % shot_name)
	quit()
