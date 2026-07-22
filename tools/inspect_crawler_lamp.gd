extends SceneTree
## Inspect the new crawler FBX + ceiling lamp GLB.


func _initialize() -> void:
	_audit("res://assets/crawler.fbx")
	_audit("res://assets/lamp.glb")
	await _anim_bounds("res://assets/crawler.fbx")
	quit()


func _audit(path: String) -> void:
	print("==== ", path, " ====")
	var scene: PackedScene = load(path)
	if scene == null:
		print("FAILED TO LOAD")
		return
	var inst: Node = scene.instantiate()
	var tris := 0
	var verts := 0
	var mesh_count := 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		mesh_count += 1
		var box: AABB = mi.get_aabb()
		print("  mesh=", mi.name, " skin=", mi.skin != null,
			" aabb_pos=", box.position, " aabb_size=", box.size)
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var t: int = (idx.size() / 3) if (idx != null and idx.size() > 0) else (v.size() / 3)
			verts += v.size()
			tris += t
	print("  TOTAL meshes=", mesh_count, " verts=", verts, " tris=", tris)
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		print("  skeleton=", sk.name, " bones=", sk.get_bone_count())
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		print("  anims=", ap.get_animation_list())
	var merged := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != inst and n != null:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box2: AABB = xf * mi.get_aabb()
		if first:
			merged = box2
			first = false
		else:
			merged = merged.merge(box2)
	print("  merged AABB pos=", merged.position, " size=", merged.size,
		" center=", merged.get_center())
	inst.free()


func _anim_bounds(path: String) -> void:
	print("==== mid-crawl bone bounds ", path, " ====")
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	var anims: Array = inst.find_children("*", "AnimationPlayer", true, false)
	if anims.is_empty():
		print("  no AnimationPlayer")
		return
	var ap: AnimationPlayer = anims[0]
	var names := ap.get_animation_list()
	print("  playing first of ", names)
	var aname: String = "Crawl" if ap.has_animation("Crawl") else String(names[0])
	ap.play(aname)
	ap.advance(ap.get_animation(aname).length * 0.5)
	await process_frame
	await process_frame

	var skels: Array = inst.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("  no skeleton")
		return
	var sk: Skeleton3D = skels[0]
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for i in sk.get_bone_count():
		var p: Vector3 = sk.get_bone_global_pose(i).origin
		mn = mn.min(p)
		mx = mx.max(p)
	print("  bone bounds min=", mn, " max=", mx, " size=", mx - mn, " center=", (mn + mx) * 0.5)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mi.global_transform * mi.get_aabb()
		print("  skinned ", mi.name, " world=", box)
