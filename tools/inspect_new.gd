extends SceneTree
## Dev tool: world AABBs + animations for the new asset batch.

const PATHS := [
	"res://assets/arm.glb",
	"res://assets/light_open.glb",
	"res://assets/light_closed.glb",
	"res://assets/wall.glb",
	"res://assets/janitor_cart.glb",
	"res://assets/janitor_broom.glb",
	"res://assets/tree.glb",
	"res://assets/wet_floor_sign.glb",
	"res://assets/sink_table.glb",
	"res://assets/crawler.glb",
]


func _initialize() -> void:
	for path in PATHS:
		print("\n=== ", path, " ===")
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		await process_frame

		var merged := AABB()
		var first := true
		var mesh_count := 0
		for child in inst.find_children("*", "MeshInstance3D", true, false):
			if child.mesh == null:
				continue
			mesh_count += 1
			var box: AABB = inst.global_transform.affine_inverse() * child.global_transform * child.mesh.get_aabb()
			if first:
				merged = box
				first = false
			else:
				merged = merged.merge(box)
		print("  meshes=", mesh_count, " MERGED pos=", merged.position, " size=", merged.size)

		for ap in inst.find_children("*", "AnimationPlayer", true, false):
			print("  anims=", ap.get_animation_list())

		inst.queue_free()
	quit()
