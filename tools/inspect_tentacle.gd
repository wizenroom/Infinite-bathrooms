extends SceneTree
## Inspect the tentacle FBX: meshes, anims, bounds.


func _initialize() -> void:
	var inst: Node3D = (load("res://assets/tentacle.fbx") as PackedScene).instantiate()
	root.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		print("mesh=", mi.name, " skin=", mi.skin != null, " aabb=", mi.get_aabb())
		if mi.mesh:
			var v := 0
			for s in mi.mesh.get_surface_count():
				v += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			print("  verts=", v)
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		print("skeleton=", sk.name, " bones=", sk.get_bone_count())
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		print("anims=", ap.get_animation_list())
		for n in ap.get_animation_list():
			print("  ", n, " len=", ap.get_animation(n).length)
	print("children:")
	for c in inst.get_children():
		print("  ", c.name, " [", c.get_class(), "] ",
			(c as Node3D).scale if c is Node3D else "")
	# Animated world bounds mid-anim.
	var anims: Array = inst.find_children("*", "AnimationPlayer", true, false)
	if anims.size() > 0:
		var ap2: AnimationPlayer = anims[0]
		var aname := String(ap2.get_animation_list()[0])
		ap2.play(aname)
		ap2.advance(ap2.get_animation(aname).length * 0.5)
		await process_frame
		await process_frame
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			print("mid-anim ", mi.name, " world=", mi.global_transform * mi.get_aabb())
	quit()
