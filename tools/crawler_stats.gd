extends SceneTree
## Per-mesh breakdown of crawler.glb so we can reconcile Blender's 45k vs Godot's 919k.


func _init() -> void:
	var path := "res://assets/crawler.glb"
	var f := FileAccess.open(path, FileAccess.READ)
	print("file size MB=", f.get_length() / 1024.0 / 1024.0)
	f = null

	var inst: Node = (load(path) as PackedScene).instantiate()
	print("--- scene tree (depth<=3) ---")
	_dump(inst, 0, 3)

	print("--- meshes ---")
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		print("MeshInstance: ", mi.name, "  path=", mi.get_path())
		print("  skin=", mi.skin != null, "  skeleton=", mi.skeleton)
		if mi.mesh == null:
			print("  (no mesh)")
			continue
		print("  mesh class=", mi.mesh.get_class(), "  surfaces=", mi.mesh.get_surface_count())
		var total_v := 0
		var total_t := 0
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var tris: int = (idx.size() / 3) if (idx != null and idx.size() > 0) else (v.size() / 3)
			total_v += v.size()
			total_t += tris
			var mat = mi.mesh.surface_get_material(s)
			print("  surf ", s, ": verts=", v.size(), " tris=", tris,
				" mat=", (mat.resource_name if mat else "none"))
		print("  TOTAL verts=", total_v, " tris=", total_t)

	print("--- skeletons ---")
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		print("Skeleton: ", sk.name, " bones=", sk.get_bone_count())

	print("--- animations ---")
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		print("AnimPlayer: ", ap.name, " anims=", ap.get_animation_list())
		for n in ap.get_animation_list():
			var a: Animation = ap.get_animation(n)
			print("  ", n, " length=", a.length, " tracks=", a.get_track_count())

	inst.free()
	quit()


func _dump(n: Node, depth: int, max_d: int) -> void:
	if depth > max_d:
		return
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]")
	for c in n.get_children():
		_dump(c, depth + 1, max_d)
