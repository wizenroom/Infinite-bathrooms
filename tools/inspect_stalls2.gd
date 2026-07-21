extends SceneTree
## Dev tool v2: world-space AABBs for the stall GLBs (transform-aware).

const PATHS := [
	"res://assets/stall_vacant_closed.glb",
	"res://assets/stall_vacant_open.glb",
	"res://assets/stall_occupied_open.glb",
	"res://assets/stall_occupied_closed.glb",
]

const DOOR_SIG := Vector3(0.700696, 0.452389, 1.675518)
const LID_SIG := Vector3(0.39523, 0.492031, 0.058429)


func _init() -> void:
	for path in PATHS:
		print("\n=== ", path, " ===")
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		var merged := AABB()
		var first := true
		for child in inst.get_children():
			if child is MeshInstance3D and child.mesh:
				var box: AABB = child.transform * child.mesh.get_aabb()
				if first:
					merged = box
					first = false
				else:
					merged = merged.merge(box)
				var s: Vector3 = child.mesh.get_aabb().size
				if s.distance_to(DOOR_SIG) < 0.01:
					print("  DOOR node=", child.name, " world_aabb pos=", box.position, " size=", box.size, " rot=", child.rotation_degrees)
				if s.distance_to(LID_SIG) < 0.01:
					print("  LID  node=", child.name, " world_aabb pos=", box.position, " size=", box.size)
				# grandchildren (toilet paper)
			for gc in child.get_children():
				if gc is MeshInstance3D and gc.mesh:
					var gbox: AABB = child.transform * (gc.transform * gc.mesh.get_aabb())
					merged = merged.merge(gbox)
		print("  MERGED pos=", merged.position, " size=", merged.size, " end=", merged.end)
		inst.free()
	quit()
