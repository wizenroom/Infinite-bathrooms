extends SceneTree
## Dev tool: true animated bounds of the crawler, from bone global poses
## (mesh AABBs lie for skinned meshes - they return bind-pose bounds).


func _initialize() -> void:
	var model: Node3D = (load("res://assets/crawler.glb") as PackedScene).instantiate()
	root.add_child(model)
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play("Crawl")
	ap.advance(0.5)
	await process_frame
	await process_frame

	for sk in model.find_children("*", "Skeleton3D", true, false):
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in sk.get_bone_count():
			# Bone pose in model-root space.
			var p: Vector3 = (model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(i)).origin
			lo = lo.min(p)
			hi = hi.max(p)
		print("skeleton ", sk.get_parent().name, "/", sk.name,
			" bones=", sk.get_bone_count(), " lo=", lo, " hi=", hi, " size=", hi - lo)
	quit()
