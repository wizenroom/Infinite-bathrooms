extends SceneTree
## Re-measure the fixed sink_table AABB.

func _initialize() -> void:
	var inst: Node3D = (load("res://assets/sink_table.glb") as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var merged := AABB()
	var first := true
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null:
			continue
		var box: AABB = inst.global_transform.affine_inverse() * child.global_transform * child.mesh.get_aabb()
		print("  ", child.name, " pos=", child.position, " rot=", child.rotation_degrees, " aabb=", box)
		if first:
			merged = box
			first = false
		else:
			merged = merged.merge(box)
	print("MERGED pos=", merged.position, " size=", merged.size)
	print("CENTER xz=", Vector3(merged.get_center().x, merged.position.y, merged.get_center().z))
	print("BOTTOM_Y=", merged.position.y)
	quit()
