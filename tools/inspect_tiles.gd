extends SceneTree
## Dev tool: node tree + world AABBs for the tile GLBs.

const PATHS := [
	"res://assets/floor_tile.glb",
	"res://assets/ceiling_tile.glb",
]


func _init() -> void:
	for path in PATHS:
		print("\n=== ", path, " ===")
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		var merged := AABB()
		var first := true
		for child in inst.find_children("*", "MeshInstance3D", true, false):
			if child.mesh == null:
				continue
			var box: AABB = child.transform * child.mesh.get_aabb()
			print("  ", child.name, " pos=", child.position, " rot=", child.rotation_degrees, " world_aabb pos=", box.position, " size=", box.size)
			if first:
				merged = box
				first = false
			else:
				merged = merged.merge(box)
		print("  MERGED pos=", merged.position, " size=", merged.size)
	quit()
