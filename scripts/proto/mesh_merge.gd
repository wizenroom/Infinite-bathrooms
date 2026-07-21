class_name MeshMerge
extends RefCounted
## Merges every MeshInstance3D in a scene into one ArrayMesh with one surface
## per material. Detail-heavy GLBs (the stalls are 117 separate meshes) render
## with a handful of draw calls instead of hundreds.

## Merge the given PackedScene. Meshes whose AABB size matches skip_size
## (e.g. the toilet lid that must animate separately) are excluded from the
## merge and returned as separate parts.
## Returns { "mesh": ArrayMesh, "parts": [{ "mesh": Mesh, "xform": Transform3D }] }.
static func merge_scene(scene: PackedScene, skip_size := Vector3.ZERO) -> Dictionary:
	var root: Node3D = scene.instantiate()
	var tools := {}  # material -> SurfaceTool
	var parts: Array = []

	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xform := _relative_xform(root, mi)
		if skip_size != Vector3.ZERO and mi.mesh.get_aabb().size.distance_to(skip_size) < 0.03:
			parts.append({ "mesh": mi.mesh, "xform": xform })
			continue
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(s)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				if mat:
					st.set_material(mat)
				tools[mat] = st
			tools[mat].append_from(mi.mesh, s, xform)

	var merged := ArrayMesh.new()
	for mat in tools:
		tools[mat].commit(merged)
	root.free()
	return { "mesh": merged, "parts": parts }


static func _relative_xform(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		xform = (n as Node3D).transform * xform
		n = n.get_parent()
	return xform
