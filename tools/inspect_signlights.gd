extends SceneTree
## Merged AABBs of the OPEN/CLOSE hanging light models.


func _init() -> void:
	for path in ["res://assets/light_open.glb", "res://assets/light_closed.glb"]:
		var inst: Node = (load(path) as PackedScene).instantiate()
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
			var box: AABB = xf * mi.get_aabb()
			merged = box if first else merged.merge(box)
			first = false
		print(path.get_file(), " pos=", merged.position, " size=", merged.size,
			" center=", merged.get_center(), " top_y=", merged.position.y + merged.size.y)
		inst.free()
	quit()
