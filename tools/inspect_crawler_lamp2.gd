extends SceneTree
## Focused: crawler bone bounds + lamp totals / real AABB.


func _initialize() -> void:
	await _crawler()
	_lamp()
	quit()


func _crawler() -> void:
	var inst: Node3D = (load("res://assets/crawler.fbx") as PackedScene).instantiate()
	root.add_child(inst)
	# Dump top of tree once.
	print("crawler children:")
	for c in inst.get_children():
		print("  ", c.name, " [", c.get_class(), "]")
		for c2 in c.get_children():
			print("    ", c2.name, " [", c2.get_class(), "]")

	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	print("anims=", ap.get_animation_list())
	var aname := String(ap.get_animation_list()[0])
	var anim: Animation = ap.get_animation(aname)
	print("anim=", aname, " len=", anim.length, " tracks=", anim.get_track_count())
	ap.get_animation(aname).loop_mode = Animation.LOOP_LINEAR
	ap.play(aname)
	ap.advance(anim.length * 0.5)
	await process_frame
	await process_frame

	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	print("bones=", sk.get_bone_count())
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for i in sk.get_bone_count():
		var p: Vector3 = sk.get_bone_global_pose(i).origin
		mn = mn.min(p)
		mx = mx.max(p)
		print("  bone ", i, " ", sk.get_bone_name(i), " ", p)
	print("BONE min=", mn, " max=", mx, " size=", mx - mn, " center=", (mn + mx) * 0.5)

	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mi.global_transform * mi.get_aabb()
		print("MESH ", mi.name, " world pos=", box.position, " size=", box.size)


func _lamp() -> void:
	var inst: Node3D = (load("res://assets/lamp.glb") as PackedScene).instantiate()
	var tris := 0
	var verts := 0
	var mesh_count := 0
	var merged := AABB()
	var first := true
	var big: Array = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		mesh_count += 1
		var xf := _local_xf(inst, mi)
		var box: AABB = xf * mi.get_aabb()
		if first:
			merged = box
			first = false
		else:
			merged = merged.merge(box)
		if box.size.length() > 0.05:
			big.append([mi.name, box])
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var t: int = (idx.size() / 3) if (idx != null and idx.size() > 0) else (v.size() / 3)
			verts += v.size()
			tris += t
	print("LAMP meshes=", mesh_count, " verts=", verts, " tris=", tris)
	print("LAMP merged pos=", merged.position, " size=", merged.size, " center=", merged.get_center())
	print("LAMP non-tiny meshes:")
	for e in big:
		print("  ", e[0], " ", e[1])
	inst.free()


func _local_xf(root_n: Node, leaf: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = leaf
	while n != root_n and n != null:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
