@tool
extends RefCounted
class_name VSMeshData

## Editable snapshot of a single MeshInstance3D's geometry.
## Holds per-surface vertex / normal / color arrays, rebuilds an ArrayMesh
## after edits and exposes flat lookups used by the painter and overlay.

var mesh_instance: MeshInstance3D
var surfaces: Array = []
var valid := false

var flat: Array = []

var merge_groups: Dictionary = {}

var vgroup: Array = []
var vgroup_idx: PackedInt32Array = PackedInt32Array()

var vdir: Array = []

var nsum: Array = []

var vadj: Array = []

var local_tris: PackedVector3Array = PackedVector3Array()

var local_extent := 1.0

# Occlusion BVH
const _BVH_LEAF := 6
var _bvh_min: PackedVector3Array = PackedVector3Array()
var _bvh_max: PackedVector3Array = PackedVector3Array()
var _bvh_lc: PackedInt32Array = PackedInt32Array()
var _bvh_rc: PackedInt32Array = PackedInt32Array()
var _bvh_start: PackedInt32Array = PackedInt32Array()
var _bvh_count: PackedInt32Array = PackedInt32Array()
var _bvh_order: PackedInt32Array = PackedInt32Array()

var _bc: PackedVector3Array = PackedVector3Array()
var _btmin: PackedVector3Array = PackedVector3Array()
var _btmax: PackedVector3Array = PackedVector3Array()

var selected: PackedByteArray = PackedByteArray()
var _sel_count := 0

const _QUANT := 100000.0


func pos_key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * _QUANT), roundi(v.y * _QUANT), roundi(v.z * _QUANT))


func capture(mi: MeshInstance3D) -> bool:
	mesh_instance = mi
	surfaces.clear()
	flat.clear()
	merge_groups.clear()
	valid = false

	if mi == null:
		return false
	var mesh := mi.mesh
	if mesh == null:
		return false

	for s in mesh.get_surface_count():
		var prim := Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			prim = mesh.surface_get_primitive_type(s)
		if prim != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.surface_get_arrays(s)
		var vraw = arrays[Mesh.ARRAY_VERTEX]
		if not (vraw is PackedVector3Array) or vraw.is_empty():
			continue
		var verts: PackedVector3Array = vraw
		var vcount := verts.size()

		var craw = arrays[Mesh.ARRAY_COLOR]
		var colors: PackedColorArray
		if craw is PackedColorArray and (craw as PackedColorArray).size() == vcount:
			colors = craw
		else:
			colors = PackedColorArray()
			colors.resize(vcount)
			colors.fill(Color.WHITE)
			arrays[Mesh.ARRAY_COLOR] = colors

		var nraw = arrays[Mesh.ARRAY_NORMAL]
		var had_normals: bool = nraw is PackedVector3Array and (nraw as PackedVector3Array).size() == vcount
		if not had_normals:
			var nn := PackedVector3Array()
			nn.resize(vcount)
			nn.fill(Vector3.UP)
			arrays[Mesh.ARRAY_NORMAL] = nn

		surfaces.append({
			"primitive": Mesh.PRIMITIVE_TRIANGLES,
			"arrays": arrays,
			"material": mesh.surface_get_material(s),
			"vcount": vcount,
			"had_normals": had_normals,
		})

	if surfaces.is_empty():
		return false

	_build_flat()
	_build_vdirs()
	_build_adjacency()
	_compute_extent()
	_build_tris()
	selected = PackedByteArray()
	selected.resize(flat.size())
	_sel_count = 0
	valid = true
	return true


func _build_adjacency() -> void:
	vadj.clear()
	vadj.resize(flat.size())
	var sets: Array = []
	sets.resize(flat.size())
	for i in sets.size():
		sets[i] = {}
	var base := 0
	for s in surfaces.size():
		var verts: PackedVector3Array = surfaces[s].arrays[Mesh.ARRAY_VERTEX]
		var iraw = surfaces[s].arrays[Mesh.ARRAY_INDEX]
		var has_idx: bool = iraw is PackedInt32Array and not iraw.is_empty()
		var count: int = iraw.size() if has_idx else verts.size()
		var i := 0
		while i + 2 < count:
			var a: int = base + (iraw[i] if has_idx else i)
			var b: int = base + (iraw[i + 1] if has_idx else i + 1)
			var c: int = base + (iraw[i + 2] if has_idx else i + 2)
			sets[a][b] = true; sets[a][c] = true
			sets[b][a] = true; sets[b][c] = true
			sets[c][a] = true; sets[c][b] = true
			i += 3
		base += surfaces[s].vcount
	for fi in flat.size():
		for sib in group_of(fi):
			if sib != fi:
				sets[fi][sib] = true
	for fi in flat.size():
		var arr := PackedInt32Array()
		for k in sets[fi]:
			arr.append(k)
		vadj[fi] = arr


func _build_flat() -> void:
	flat.clear()
	merge_groups.clear()
	for s in surfaces.size():
		var verts: PackedVector3Array = surfaces[s].arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var fi := flat.size()
			flat.append({ "surface": s, "index": i })
			var key := pos_key(verts[i])
			if not merge_groups.has(key):
				merge_groups[key] = []
			merge_groups[key].append(fi)

	vgroup.resize(flat.size())
	vgroup_idx = PackedInt32Array()
	vgroup_idx.resize(flat.size())
	for key in merge_groups:
		var group: Array = merge_groups[key]
		for gi in group.size():
			var fi: int = group[gi]
			vgroup[fi] = group
			vgroup_idx[fi] = gi


func _build_vdirs() -> void:
	vdir.clear()
	vdir.resize(flat.size())
	nsum.clear()
	nsum.resize(flat.size())
	for i in vdir.size():
		vdir[i] = Vector3.ZERO
		nsum[i] = Vector3.ZERO
	var base := 0
	for s in surfaces.size():
		var verts: PackedVector3Array = surfaces[s].arrays[Mesh.ARRAY_VERTEX]
		var nraw = surfaces[s].arrays[Mesh.ARRAY_NORMAL]
		var have_n: bool = nraw is PackedVector3Array and (nraw as PackedVector3Array).size() == verts.size()
		var orig_n: PackedVector3Array = nraw if have_n else PackedVector3Array()
		var iraw = surfaces[s].arrays[Mesh.ARRAY_INDEX]
		var has_idx: bool = iraw is PackedInt32Array and not iraw.is_empty()
		var count: int = iraw.size() if has_idx else verts.size()
		var i := 0
		while i + 2 < count:
			var a: int = iraw[i] if has_idx else i
			var b: int = iraw[i + 1] if has_idx else i + 1
			var c: int = iraw[i + 2] if has_idx else i + 2
			var va := verts[a]
			var vb := verts[b]
			var vc := verts[c]
			var cen := (va + vb + vc) / 3.0
			vdir[base + a] += cen - va
			vdir[base + b] += cen - vb
			vdir[base + c] += cen - vc
			var fn := (vb - va).cross(vc - va)
			if have_n and fn.dot(orig_n[a] + orig_n[b] + orig_n[c]) < 0.0:
				fn = -fn
			nsum[base + a] += fn
			nsum[base + b] += fn
			nsum[base + c] += fn
			i += 3
		base += surfaces[s].vcount
	for i in vdir.size():
		var d: Vector3 = vdir[i]
		vdir[i] = d.normalized() if d.length() > 0.0000001 else Vector3.ZERO
	base = 0
	for s in surfaces.size():
		if not surfaces[s].get("had_normals", true):
			for li in surfaces[s].vcount:
				var fn2: Vector3 = nsum[base + li]
				if fn2.length() > 0.0000001:
					surfaces[s].arrays[Mesh.ARRAY_NORMAL][li] = fn2.normalized()
		base += surfaces[s].vcount


func face_dir(fi: int) -> Vector3:
	if fi >= 0 and fi < vdir.size():
		return vdir[fi]
	return Vector3.ZERO


func _build_tris() -> void:
	local_tris = PackedVector3Array()
	for s in surfaces:
		var verts: PackedVector3Array = s.arrays[Mesh.ARRAY_VERTEX]
		var iraw = s.arrays[Mesh.ARRAY_INDEX]
		var has_idx: bool = iraw is PackedInt32Array and not iraw.is_empty()
		var count: int = iraw.size() if has_idx else verts.size()
		var i := 0
		while i + 2 < count:
			var a: int = iraw[i] if has_idx else i
			var b: int = iraw[i + 1] if has_idx else i + 1
			var c: int = iraw[i + 2] if has_idx else i + 2
			local_tris.append(verts[a])
			local_tris.append(verts[b])
			local_tris.append(verts[c])
			i += 3
	_build_bvh()


func triangle_count() -> int:
	return local_tris.size() / 3


#region Occlusion BVH

func _build_bvh() -> void:
	_bvh_min = PackedVector3Array()
	_bvh_max = PackedVector3Array()
	_bvh_lc = PackedInt32Array()
	_bvh_rc = PackedInt32Array()
	_bvh_start = PackedInt32Array()
	_bvh_count = PackedInt32Array()
	_bvh_order = PackedInt32Array()
	var tcount := local_tris.size() / 3
	if tcount == 0:
		return
	_bc = PackedVector3Array(); _bc.resize(tcount)
	_btmin = PackedVector3Array(); _btmin.resize(tcount)
	_btmax = PackedVector3Array(); _btmax.resize(tcount)
	_bvh_order.resize(tcount)
	for t in tcount:
		var i := t * 3
		var p0 := local_tris[i]
		var p1 := local_tris[i + 1]
		var p2 := local_tris[i + 2]
		_btmin[t] = p0.min(p1).min(p2)
		_btmax[t] = p0.max(p1).max(p2)
		_bc[t] = (p0 + p1 + p2) / 3.0
		_bvh_order[t] = t
	_bvh_build_range(0, tcount)
	_bc = PackedVector3Array()
	_btmin = PackedVector3Array()
	_btmax = PackedVector3Array()


func _bvh_build_range(start: int, count: int) -> int:
	var bmin := _btmin[_bvh_order[start]]
	var bmax := _btmax[_bvh_order[start]]
	var cmin := _bc[_bvh_order[start]]
	var cmax := cmin
	for k in range(start, start + count):
		var t := _bvh_order[k]
		bmin = bmin.min(_btmin[t])
		bmax = bmax.max(_btmax[t])
		cmin = cmin.min(_bc[t])
		cmax = cmax.max(_bc[t])
	var pad := Vector3.ONE * (local_extent * 1e-5)
	var node := _bvh_min.size()
	_bvh_min.append(bmin - pad)
	_bvh_max.append(bmax + pad)
	_bvh_lc.append(-1)
	_bvh_rc.append(-1)
	_bvh_start.append(start)
	_bvh_count.append(count)
	if count <= _BVH_LEAF:
		return node
	var ext := cmax - cmin
	var axis := 0
	if ext.y > ext.x:
		axis = 1
	if ext.z > ext[axis]:
		axis = 2
	if ext[axis] <= 0.0:
		return node
	var split: float = (cmin[axis] + cmax[axis]) * 0.5
	var mid := _bvh_partition(start, count, axis, split)
	if mid == start or mid == start + count:
		mid = start + count / 2
	_bvh_lc[node] = _bvh_build_range(start, mid - start)
	_bvh_rc[node] = _bvh_build_range(mid, start + count - mid)
	return node


func _bvh_partition(start: int, count: int, axis: int, split: float) -> int:
	var i := start
	var j := start + count - 1
	while i <= j:
		while i <= j and _bc[_bvh_order[i]][axis] < split:
			i += 1
		while i <= j and _bc[_bvh_order[j]][axis] >= split:
			j -= 1
		if i < j:
			var tmp := _bvh_order[i]
			_bvh_order[i] = _bvh_order[j]
			_bvh_order[j] = tmp
			i += 1
			j -= 1
	return i


func segment_hits(a: Vector3, b: Vector3) -> bool:
	if _bvh_min.is_empty():
		return _segment_hits_linear(a, b)
	var d := b - a
	var stack := PackedInt32Array([0])
	while not stack.is_empty():
		var node := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if not _seg_aabb(a, d, _bvh_min[node], _bvh_max[node]):
			continue
		var lc := _bvh_lc[node]
		if lc == -1:
			var s := _bvh_start[node]
			for k in range(s, s + _bvh_count[node]):
				var t := _bvh_order[k] * 3
				if Geometry3D.segment_intersects_triangle(a, b, local_tris[t], local_tris[t + 1], local_tris[t + 2]) != null:
					return true
		else:
			stack.push_back(lc)
			stack.push_back(_bvh_rc[node])
	return false


func _seg_aabb(a: Vector3, d: Vector3, bmin: Vector3, bmax: Vector3) -> bool:
	var tmin := 0.0
	var tmax := 1.0
	for axis in 3:
		var o: float = a[axis]
		var di: float = d[axis]
		if absf(di) < 1e-12:
			if o < bmin[axis] or o > bmax[axis]:
				return false
		else:
			var inv := 1.0 / di
			var t1: float = (bmin[axis] - o) * inv
			var t2: float = (bmax[axis] - o) * inv
			if t1 > t2:
				var tmp := t1; t1 = t2; t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return false
	return true


func _segment_hits_linear(a: Vector3, b: Vector3) -> bool:
	var n := local_tris.size()
	var i := 0
	while i < n:
		if Geometry3D.segment_intersects_triangle(a, b, local_tris[i], local_tris[i + 1], local_tris[i + 2]) != null:
			return true
		i += 3
	return false


func _compute_extent() -> void:
	var has := false
	var mn := Vector3.ZERO
	var mx := Vector3.ZERO
	for s in surfaces:
		var verts: PackedVector3Array = s.arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			if not has:
				mn = v
				mx = v
				has = true
			else:
				mn = mn.min(v)
				mx = mx.max(v)
	local_extent = maxf((mx - mn).length(), 0.001) if has else 1.0


#endregion Occlusion BVH


#region Selection
# ---------------------------------------------------------------- 
# Selection
# ---------------------------------------------------------------- 

func is_selected(fi: int) -> bool:
	return fi >= 0 and fi < selected.size() and selected[fi] == 1


func set_selected(fi: int, v: bool) -> void:
	if fi < 0 or fi >= selected.size():
		return
	var nv: int = 1 if v else 0
	if selected[fi] != nv:
		selected[fi] = nv
		_sel_count += 1 if nv == 1 else -1


func clear_selected() -> void:
	selected.fill(0)
	_sel_count = 0


func select_all_verts() -> void:
	selected.fill(1)
	_sel_count = selected.size()


func has_any_selected() -> bool:
	return _sel_count > 0


func selected_count() -> int:
	return _sel_count


func set_selection_bytes(bytes: PackedByteArray) -> void:
	if bytes.size() != flat.size():
		return
	selected = bytes.duplicate()
	_sel_count = 0
	for b in selected:
		if b == 1:
			_sel_count += 1


func get_local_vertex(fi: int) -> Vector3:
	var e = flat[fi]
	return surfaces[e.surface].arrays[Mesh.ARRAY_VERTEX][e.index]


func get_world_vertex(fi: int) -> Vector3:
	return mesh_instance.global_transform * get_local_vertex(fi)


func get_local_normal(fi: int) -> Vector3:
	var e = flat[fi]
	var normals = surfaces[e.surface].arrays[Mesh.ARRAY_NORMAL]
	if normals is PackedVector3Array and normals.size() > e.index:
		return normals[e.index]
	return Vector3.UP


func get_color(fi: int) -> Color:
	var e = flat[fi]
	return surfaces[e.surface].arrays[Mesh.ARRAY_COLOR][e.index]


func set_color(fi: int, c: Color) -> void:
	var e = flat[fi]
	surfaces[e.surface].arrays[Mesh.ARRAY_COLOR][e.index] = c


func set_local_normal(fi: int, n: Vector3) -> void:
	var e = flat[fi]
	surfaces[e.surface].arrays[Mesh.ARRAY_NORMAL][e.index] = n


#endregion Selection


#region Hard / smooth normals
# ---------------------------------------------------------------- 
# Hard / smooth normals
# ---------------------------------------------------------------- 

func hard_normal(fi: int) -> Vector3:
	if fi >= 0 and fi < nsum.size():
		var v: Vector3 = nsum[fi]
		if v.length() > 0.0000001:
			return v.normalized()
	return get_local_normal(fi)


func smooth_normal(fi: int) -> Vector3:
	var s := Vector3.ZERO
	for g in group_of(fi):
		if g >= 0 and g < nsum.size():
			s += nsum[g]
	if s.length() > 0.0000001:
		return s.normalized()
	return get_local_normal(fi)


func is_smooth_vertex(fi: int) -> bool:
	return get_local_normal(fi).dot(smooth_normal(fi)) > 0.9995


func group_of(fi: int) -> Array:
	if fi >= 0 and fi < vgroup.size() and vgroup[fi] is Array:
		return vgroup[fi]
	return [fi]


func group_index(fi: int) -> int:
	if fi >= 0 and fi < vgroup_idx.size():
		return vgroup_idx[fi]
	return 0


func is_split_vertex(fi: int) -> bool:
	return group_of(fi).size() > 1


func siblings(fi: int, merge: bool) -> Array:
	if not merge:
		return [fi]
	return merge_groups.get(pos_key(get_local_vertex(fi)), [fi])


func vertex_count() -> int:
	return flat.size()


#endregion Normals


#region Color snapshots
# ----------------------------------------------------------------
# Color snapshots (whole-mesh color (de)serialisation for undo / snapshots)
# ---------------------------------------------------------------- 

func snapshot_colors() -> Array:
	var out: Array = []
	for s in surfaces:
		out.append((s.arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate())
	return out


func restore_colors(data: Array) -> void:
	for s in mini(data.size(), surfaces.size()):
		var colors: PackedColorArray = data[s]
		if colors.size() == surfaces[s].vcount:
			surfaces[s].arrays[Mesh.ARRAY_COLOR] = colors.duplicate()
	rebuild()


#endregion Color snapshots


#region Normal topology editing
# ----------------------------------------------------------------
# Normal topology editing
# ----------------------------------------------------------------


func snapshot_surfaces() -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return []


func restore_surfaces(_data: Array) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _rederive() -> void:
	_build_flat()
	_build_vdirs()
	_build_adjacency()
	_compute_extent()
	_build_tris()
	selected = PackedByteArray()
	selected.resize(flat.size())
	_sel_count = 0


func neighbors(fi: int) -> PackedInt32Array:
	if fi >= 0 and fi < vadj.size() and vadj[fi] is PackedInt32Array:
		return vadj[fi]
	return PackedInt32Array()


func apply_normal_edit(_keys: Dictionary, _smooth: bool) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _selected_keys() -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _reselect_keys(_keys: Dictionary) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _surface_indices(_s: int, _n: int) -> PackedInt32Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return PackedInt32Array()


func _rebuild_surface_normals(_s: int, _keys: Dictionary, _smooth: bool) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _oriented_face_normal(_verts: PackedVector3Array, _normals: PackedVector3Array, _have_n: bool, _a: int, _b: int, _c: int) -> Vector3:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return Vector3.ZERO


func _with_tangents(_src: Array) -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return []


func rebuild() -> void:
	if mesh_instance == null:
		return
	var am := ArrayMesh.new()
	for s in surfaces.size():
		var surf = surfaces[s]
		am.add_surface_from_arrays(surf.primitive, surf.arrays)
		if surf.material != null:
			am.surface_set_material(s, surf.material)
	mesh_instance.mesh = am


func set_all_materials(mat: Material) -> void:
	for s in surfaces.size():
		surfaces[s].material = mat


#endregion Normal topology editing


#region Source re-sync
# ----------------------------------------------------------------
# Source mesh re-sync
# ----------------------------------------------------------------

func resync_uvs_from_mesh(_src: Mesh, _by_position: bool = false) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _resync_surface_by_index(_s: int, _sarr: Array) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _resync_surface_by_position(_s: int, _sarr: Array) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false

#endregion Source re-sync