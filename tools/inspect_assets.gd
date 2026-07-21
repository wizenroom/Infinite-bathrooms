extends SceneTree
## Dev tool: prints AABB and animation names for each GLB asset.
## Run: godot --headless --script res://tools/inspect_assets.gd

const PATHS := [
	"res://assets/toilet.glb",
	"res://assets/plunger.glb",
	"res://assets/man_animated.glb",
	"res://assets/plant.glb",
]


func _init() -> void:
	for path in PATHS:
		var ps: PackedScene = load(path)
		if ps == null:
			print(path, "  FAILED TO LOAD")
			continue
		var inst := ps.instantiate()
		root.add_child(inst)

		var merged := AABB()
		var first := true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			if first:
				merged = b
				first = false
			else:
				merged = merged.merge(b)
		print(path)
		print("  size=", merged.size, "  pos=", merged.position)

		for ap in inst.find_children("*", "AnimationPlayer", true, false):
			print("  animations=", ap.get_animation_list())

		inst.free()
	quit()
