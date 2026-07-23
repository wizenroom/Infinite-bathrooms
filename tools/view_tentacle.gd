extends SceneTree
## Render the tentacle FBX in three orientations (none, x-90, x+90) with the
## purple retro material, mid-animation, and screenshot for a visual pick.


func _initialize() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.2
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 48
	noise_tex.height = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = noise_tex
	mat.albedo_color = Color(0.58, 0.2, 0.75)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(4, 4, 4)
	mat.roughness = 0.5

	var rots := [0.0, -PI / 2.0, PI / 2.0]
	for i in rots.size():
		var wrapper := Node3D.new()
		root.add_child(wrapper)
		wrapper.position = Vector3((i - 1) * 4.0, 0, 0)
		wrapper.rotation.x = rots[i]
		var inst: Node3D = (load("res://assets/tentacle.fbx") as PackedScene).instantiate()
		for cam in inst.find_children("*", "Camera3D", true, false):
			cam.queue_free()
		wrapper.add_child(inst)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var aname := String(ap.get_animation_list()[0])
		ap.play(aname)
		ap.advance(ap.get_animation(aname).length * 0.55)
		# Floor marker under each.
		var floor_mesh := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2(3, 3)
		floor_mesh.mesh = pl
		floor_mesh.position = wrapper.position
		root.add_child(floor_mesh)

	var cam3 := Camera3D.new()
	root.add_child(cam3)
	cam3.position = Vector3(0, 3.0, 11.0)
	cam3.look_at(Vector3(0, 1.8, 0))
	cam3.make_current()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	root.add_child(sun)

	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://tent_orient.png")
	print("saved tent_orient.png")
	quit()
