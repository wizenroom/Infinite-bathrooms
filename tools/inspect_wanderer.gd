extends SceneTree
## Inspect the new wanderer GLB: meshes, skeleton, animations, and per-anim
## "active" span (first/last keyframe times) so empty lead-in/out can be cut.


func _initialize() -> void:
	var inst: Node3D = (load("res://assets/wanderer.glb") as PackedScene).instantiate()
	root.add_child(inst)

	print("children:")
	for c in inst.get_children():
		print("  ", c.name, " [", c.get_class(), "]",
			" scale=" + str((c as Node3D).scale) if c is Node3D else "")

	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var v := 0
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				v += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		print("mesh=", mi.name, " skin=", mi.skin != null, " verts=", v, " aabb=", mi.get_aabb())

	for sk in inst.find_children("*", "Skeleton3D", true, false):
		print("skeleton=", sk.name, " bones=", sk.get_bone_count())

	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		print("ANIMS=", ap.get_animation_list())
		for n in ap.get_animation_list():
			var a: Animation = ap.get_animation(n)
			# Scan all tracks for the first/last key time and how much actually moves.
			var first_key := INF
			var last_key := -INF
			var moving_tracks := 0
			for t in a.get_track_count():
				var kc := a.track_get_key_count(t)
				if kc == 0:
					continue
				first_key = minf(first_key, a.track_get_key_time(t, 0))
				last_key = maxf(last_key, a.track_get_key_time(t, kc - 1))
				# Does this track change value at all?
				if a.track_get_type(t) == Animation.TYPE_POSITION_3D and kc > 1:
					var v0: Vector3 = a.track_get_key_value(t, 0)
					for k in range(1, kc):
						if (a.track_get_key_value(t, k) as Vector3).distance_to(v0) > 0.001:
							moving_tracks += 1
							break
				elif a.track_get_type(t) == Animation.TYPE_ROTATION_3D and kc > 1:
					var q0: Quaternion = a.track_get_key_value(t, 0)
					for k in range(1, kc):
						if (a.track_get_key_value(t, k) as Quaternion).angle_to(q0) > 0.01:
							moving_tracks += 1
							break
			print("  ", n, " len=", a.length, " tracks=", a.get_track_count(),
				" keys ", first_key, "..", last_key, " moving=", moving_tracks)

	# Mid-anim world bounds (ground offset / scale check).
	var anims: Array = inst.find_children("*", "AnimationPlayer", true, false)
	if anims.size() > 0:
		var ap2: AnimationPlayer = anims[0]
		for n in ap2.get_animation_list():
			ap2.play(n)
			ap2.advance(ap2.get_animation(n).length * 0.5)
			await process_frame
			await process_frame
			var merged := AABB()
			var first := true
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var box: AABB = mi.global_transform * mi.get_aabb()
				merged = box if first else merged.merge(box)
				first = false
			print("mid-", n, " world=", merged)
	quit()
