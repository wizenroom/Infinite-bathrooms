extends SceneTree
## Dump crawler FBX transform hierarchy + mid-crawl visual screenshot.


func _initialize() -> void:
	var inst: Node3D = (load("res://assets/crawler.fbx") as PackedScene).instantiate()
	root.add_child(inst)
	_dump(inst, 0)

	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var aname := String(ap.get_animation_list()[0])
	ap.get_animation(aname).loop_mode = Animation.LOOP_LINEAR
	ap.play(aname)
	ap.advance(ap.get_animation(aname).length * 0.4)

	# Camera looking at crawler from the side/front.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(2.5, 1.2, 1.5)
	cam.look_at(Vector3(0, 0.4, 0.9))
	cam.make_current()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://crawler_new.png")
	print("saved crawler_new.png")
	quit()


func _dump(n: Node, depth: int) -> void:
	if depth > 5:
		return
	var extra := ""
	if n is Node3D:
		var n3 := n as Node3D
		extra = " pos=%s rot=%s scale=%s" % [n3.position, n3.rotation_degrees, n3.scale]
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_dump(c, depth + 1)
