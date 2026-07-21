extends SceneTree
## Dev check: open an EMPTY stall and print the lid AABB in stall space.
## Closed lid should be flat (small Y extent); open lid should be tall
## (large Y extent, small Z extent) and sit near the tank.

const LID_SIZE := Vector3(0.39523, 0.492031, 0.058429)


func _initialize() -> void:
	var stall := Stall.new()
	root.add_child(stall)
	var rng := RandomNumberGenerator.new()
	stall.setup(Stall.Outcome.EMPTY, rng)
	# Global transforms only resolve once the tree starts processing.
	await process_frame
	print("CLOSED: ", _lid_box(stall))
	stall.knock()
	await process_frame
	print("OPEN:   ", _lid_box(stall))
	quit()


func _lid_box(stall: Node3D) -> String:
	for mi in stall.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		if mi.mesh.get_aabb().size.distance_to(LID_SIZE) > 0.03:
			continue
		var xf: Transform3D = stall.global_transform.affine_inverse() * mi.global_transform
		var box: AABB = xf * mi.mesh.get_aabb()
		return "pos=%s size=%s" % [box.position, box.size]
	return "lid not found"
