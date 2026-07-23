extends SceneTree
## Merged AABBs of the janitor cart + broom so physics colliders can be sized.


func _initialize() -> void:
	for path in ["res://assets/janitor_cart.glb", "res://assets/janitor_broom.glb"]:
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		await process_frame
		var merged := AABB()
		var first := true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mi.global_transform * mi.get_aabb()
			merged = box if first else merged.merge(box)
			first = false
		print(path.get_file(), " aabb pos=", merged.position, " size=", merged.size,
			" center=", merged.get_center())
		inst.free()
	quit()
