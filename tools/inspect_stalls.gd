extends SceneTree
## Dev tool: dumps node tree + mesh AABBs for the stall GLBs.

const PATHS := [
	"res://assets/stall_vacant_closed.glb",
	"res://assets/stall_vacant_open.glb",
	"res://assets/stall_occupied_open.glb",
	"res://assets/stall_occupied_closed.glb",
]


func _init() -> void:
	for path in PATHS:
		print("\n=== ", path, " ===")
		var ps: PackedScene = load(path)
		if ps == null:
			print("  FAILED TO LOAD")
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		_dump(inst, 0)
		inst.free()
	quit()


func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var info := indent + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		info += "  pos=" + str(node.position) + " rot_deg=" + str(node.rotation_degrees) + " scl=" + str(node.scale)
	if node is MeshInstance3D and node.mesh:
		var aabb: AABB = node.mesh.get_aabb()
		info += "  aabb_size=" + str(aabb.size) + " aabb_pos=" + str(aabb.position)
	print(info)
	for child in node.get_children():
		_dump(child, depth + 1)
