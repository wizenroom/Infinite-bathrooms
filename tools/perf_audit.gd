extends SceneTree
## Dev tool: triangle/vertex counts and mesh instance counts per asset.

const PATHS := [
	"res://assets/crawler.glb",
	"res://assets/tree.glb",
	"res://assets/janitor_cart.glb",
	"res://assets/janitor_broom.glb",
	"res://assets/wet_floor_sign.glb",
	"res://assets/sink_table.glb",
	"res://assets/wall.glb",
	"res://assets/floor_tile.glb",
	"res://assets/ceiling_tile.glb",
	"res://assets/stall_vacant_closed.glb",
	"res://assets/stall_occupied_closed.glb",
	"res://assets/man_animated.glb",
	"res://assets/plant.glb",
	"res://assets/arm.glb",
	"res://assets/light_open.glb",
	"res://assets/plunger.glb",
]


func _init() -> void:
	for path in PATHS:
		var inst: Node = (load(path) as PackedScene).instantiate()
		var tris := 0
		var verts := 0
		var mesh_count := 0
		var surf_count := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			mesh_count += 1
			for s in mi.mesh.get_surface_count():
				surf_count += 1
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				verts += v.size()
				var idx = arrays[Mesh.ARRAY_INDEX]
				if idx != null and idx.size() > 0:
					tris += idx.size() / 3
				else:
					tris += v.size() / 3
		print(path.get_file(), "  meshes=", mesh_count, " surfaces=", surf_count,
			" verts=", verts, " tris=", tris)
		inst.free()
	quit()
