extends SceneTree
## Dev tool: measure the crawler's visual AABB mid-Crawl animation so we can
## pick the right scale and ground offset.


func _initialize() -> void:
	var inst: Node3D = (load("res://assets/crawler.glb") as PackedScene).instantiate()
	root.add_child(inst)
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	print("anim length=", ap.get_animation("Crawl").length)
	ap.play("Crawl")
	ap.advance(ap.get_animation("Crawl").length * 0.5)
	await process_frame
	await process_frame

	var merged := AABB()
	var first := true
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null:
			continue
		# get_aabb() on the instance reflects skinned deformation.
		var box: AABB = inst.global_transform.affine_inverse() * child.global_transform * child.get_aabb()
		if first:
			merged = box
			first = false
		else:
			merged = merged.merge(box)
	print("mid-crawl AABB pos=", merged.position, " size=", merged.size)

	# Check for root motion: does the position track move the hips far?
	var anim := ap.get_animation("Crawl")
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var start: Vector3 = anim.position_track_interpolate(i, 0.0)
			var end: Vector3 = anim.position_track_interpolate(i, anim.length)
			if start.distance_to(end) > 1.0:
				print("root motion track: ", anim.track_get_path(i), " moves ", start.distance_to(end))
	quit()
