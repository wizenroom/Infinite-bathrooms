@tool
extends RefCounted
class_name VSPainter

## Owns the current paint targets and performs the actual color edits.

var state: VSState
var targets: Array[VSMeshData] = []

# Screen-space fan spread for split verts (pixels, before editor scale)
const SPLIT_SPREAD_PX := 16.0
# Precision tool zoom when hovering a physical vertex
const PRECISION_ZOOM := 3.0
const OCCLUSION_TRI_LIMIT := 200000

var _fan_cache: Dictionary = {}
var _fan_token: int = 0

var _occ_cache: Dictionary = {}
var _occ_cam: Camera3D = null
var _occ_xform := Transform3D()
var _occ_proj := -1
var _occ_fov := 0.0
var _occ_size := 0.0

var _occ_inv: Dictionary = {}

var _occ_last_mid := 0
var _occ_last_slot: Array = []

var _plock: Dictionary = {}

var _in_stroke := false
var _stroke_origin: Array = []
var _stroke_weight: Array = []


func _init(p_state: VSState) -> void:
	state = p_state


func begin_stroke() -> void:
	_in_stroke = true
	_stroke_origin.clear()
	_stroke_weight.clear()
	for md in targets:
		var n := md.vertex_count()
		var oc := PackedColorArray()
		oc.resize(n)
		for fi in n:
			oc[fi] = md.get_color(fi)
		var w := PackedFloat32Array()
		w.resize(n)
		_stroke_origin.append(oc)
		_stroke_weight.append(w)


func end_stroke() -> void:
	_in_stroke = false
	_stroke_origin.clear()
	_stroke_weight.clear()


func set_targets_from_node(root: Node) -> void:
	targets.clear()
	_fan_cache.clear()
	_occ_cache.clear()
	_occ_inv.clear()
	_occ_cam = null
	_occ_last_mid = 0
	_occ_last_slot = []
	_plock = {}
	if root == null:
		return
	var nodes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		nodes.append(root)
	if state.include_children:
		_collect_children(root, nodes)
	for mi in nodes:
		var md := VSMeshData.new()
		if md.capture(mi):
			targets.append(md)


func _collect_children(node: Node, out: Array[MeshInstance3D]) -> void:
	for c in node.get_children():
		if c is MeshInstance3D and not out.has(c):
			out.append(c)
		_collect_children(c, out)


func total_vertices() -> int:
	var n := 0
	for md in targets:
		n += md.vertex_count()
	return n


func total_triangles() -> int:
	var n := 0
	for md in targets:
		n += md.triangle_count()
	return n


func has_targets() -> bool:
	return not targets.is_empty()


#region Selection
# ---------------------------------------------------------------- 
# Selection
# ---------------------------------------------------------------- 

func has_selection() -> bool:
	for md in targets:
		if md.has_any_selected():
			return true
	return false


func total_selected() -> int:
	var n := 0
	for md in targets:
		n += md.selected_count()
	return n


func clear_selection() -> void:
	for md in targets:
		md.clear_selected()


func select_all() -> void:
	for md in targets:
		md.select_all_verts()


func invert_selection() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func selection_groups() -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return []


func apply_selection_groups(_data: Array) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func select_marquee(camera: Camera3D, pts: PackedVector2Array, type: int, mode: int) -> void:
	if pts.is_empty():
		return
	if mode == 0:
		clear_selection()
	var rect := _shape_bounds(pts)
	for md in targets:
		var basis := md.mesh_instance.global_transform.basis
		for fi in md.vertex_count():
			var world := md.get_world_vertex(fi)
			if not is_in_front(camera, world):
				continue
			if state.front_verts_only:
				var wn := (basis * md.get_local_normal(fi)).normalized()
				if not is_front_facing(camera, world, wn):
					continue
				if occluded(camera, md, fi, world):
					continue
			var sp := camera.unproject_position(world) + split_screen_offset(camera, md, fi)
			if _point_in_shape(sp, pts, type, rect):
				md.set_selected(fi, mode != 2)


func select_point(camera: Camera3D, mouse: Vector2, mode: int) -> bool:
	var best := maxf(state.dot_size, 8.0) * EditorInterface.get_editor_scale()
	var bmd: VSMeshData = null
	var bfi := -1
	var do_occ := state.front_verts_only and total_triangles() <= OCCLUSION_TRI_LIMIT
	for md in targets:
		if not is_instance_valid(md.mesh_instance):
			continue
		var basis := md.mesh_instance.global_transform.basis
		for fi in md.vertex_count():
			var world := md.get_world_vertex(fi)
			if not is_in_front(camera, world):
				continue
			if state.front_verts_only:
				var wn := (basis * md.get_local_normal(fi)).normalized()
				if not is_front_facing(camera, world, wn):
					continue
				if do_occ and occluded(camera, md, fi, world):
					continue
			var sp := camera.unproject_position(world) + split_screen_offset(camera, md, fi)
			var d := sp.distance_to(mouse)
			if d < best:
				best = d
				bmd = md
				bfi = fi
	if mode == 0:
		clear_selection()
	if bfi < 0:
		return mode == 0
	for fi in _point_select_indices(bmd, bfi):
		bmd.set_selected(fi, mode != 2)
	return true


func _point_select_indices(md: VSMeshData, fi: int) -> Array:
	if state.shared_verts == VSState.SharedVerts.SPLIT:
		return [fi]
	return md.group_of(fi)


func linked_materials() -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return []


func select_by_material(_mat, _mode: int) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func point_in_marquee(sp: Vector2, pts: PackedVector2Array, type: int) -> bool:
	if pts.size() < 2:
		return false
	return _point_in_shape(sp, pts, type, _shape_bounds(pts))


func _shape_bounds(pts: PackedVector2Array) -> Rect2:
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn)


func _point_in_shape(sp: Vector2, pts: PackedVector2Array, type: int, rect: Rect2) -> bool:
	match type:
		VSState.SelectType.RECTANGLE:
			return _rect_hit(sp, rect)
		VSState.SelectType.ELLIPSE:
			return _ellipse_hit(sp, rect)
		_:
			return _lasso_hit(sp, pts)


func _rect_hit(_sp: Vector2, _rect: Rect2) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _ellipse_hit(_sp: Vector2, _rect: Rect2) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _lasso_hit(_sp: Vector2, _pts: PackedVector2Array) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func is_in_front(camera: Camera3D, world: Vector3) -> bool:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return true
	return not camera.is_position_behind(world)


func within_draw_distance(camera: Camera3D, world: Vector3) -> bool:
	if state.draw_distance <= 0.0:
		return true
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return true
	return camera.global_transform.origin.distance_to(world) <= state.draw_distance


func view_to_camera_dir(camera: Camera3D, world: Vector3) -> Vector3:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return camera.global_transform.basis.z.normalized()
	return (camera.global_transform.origin - world).normalized()


func is_front_facing(camera: Camera3D, world: Vector3, world_normal: Vector3) -> bool:
	return world_normal.dot(view_to_camera_dir(camera, world)) > 0.0


func split_screen_offset(_camera: Camera3D, _md: VSMeshData, _fi: int) -> Vector2:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return Vector2.ZERO


func precision_offset(_camera: Camera3D, _md: VSMeshData, _fi: int) -> Vector2:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return Vector2.ZERO


func _fan_dir(_camera: Camera3D, _md: VSMeshData, _fi: int) -> Vector2:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return Vector2.ZERO


func _group_fan_dirs(_camera: Camera3D, _md: VSMeshData, _group: Array) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _camera_token(camera: Camera3D) -> int:
	var t := camera.global_transform
	var arr := [t.origin, t.basis.x, t.basis.y, t.basis.z,
		camera.projection, camera.fov, camera.size, camera.near, camera.far]
	var vp := camera.get_viewport()
	if vp:
		arr.append(vp.get_visible_rect().size)
	return hash(arr)


func occluded(camera: Camera3D, md: VSMeshData, fi: int, world: Vector3) -> bool:
	if _occ_view_changed(camera):
		_occ_cache.clear()
		_occ_inv.clear()
		_occ_last_mid = 0
		_occ_last_slot = []
	var mid := md.mesh_instance.get_instance_id()
	var slot = _occ_last_slot
	if mid != _occ_last_mid or slot.size() != md.vertex_count():
		slot = _occ_cache.get(mid)
		if slot == null or slot.size() != md.vertex_count():
			slot = []
			slot.resize(md.vertex_count())
			slot.fill(0)
			_occ_cache[mid] = slot
		_occ_last_mid = mid
		_occ_last_slot = slot
	var v: int = slot[fi]
	if v != 0:
		return v == 2
	var res := is_occluded(camera, world)
	slot[fi] = 2 if res else 1
	return res


func _occ_view_changed(camera: Camera3D) -> bool:
	if camera == _occ_cam and camera.global_transform == _occ_xform \
			and camera.projection == _occ_proj \
			and is_equal_approx(camera.fov, _occ_fov) \
			and is_equal_approx(camera.size, _occ_size):
		return false
	_occ_cam = camera
	_occ_xform = camera.global_transform
	_occ_proj = camera.projection
	_occ_fov = camera.fov
	_occ_size = camera.size
	return true


func _target_inv(md: VSMeshData) -> Transform3D:
	var mid := md.mesh_instance.get_instance_id()
	var inv = _occ_inv.get(mid)
	if inv == null:
		inv = md.mesh_instance.global_transform.affine_inverse()
		_occ_inv[mid] = inv
	return inv


func is_occluded(camera: Camera3D, point_world: Vector3) -> bool:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var dir := camera.global_transform.basis.z.normalized()
		for md in targets:
			var inv := _target_inv(md)
			var lp := inv * point_world
			var l_dir := (inv.basis * dir).normalized()
			var l_start := lp + l_dir * (md.local_extent * 0.001)
			var l_end := lp + l_dir * (md.local_extent * 1000.0)
			if md.segment_hits(l_start, l_end):
				return true
		return false

	var cam_pos := camera.global_transform.origin
	var to_cam := cam_pos - point_world
	var dist := to_cam.length()
	if dist < 0.0001:
		return false
	var dirn := to_cam / dist
	var eps := maxf(0.01, dist * 0.002)
	var start_world := point_world + dirn * eps
	for md in targets:
		var inv := _target_inv(md)
		var lf := inv * start_world
		var lt := inv * cam_pos
		if md.segment_hits(lf, lt):
			return true
	return false


#endregion Selection


#region Color ops
# ---------------------------------------------------------------- 
# Color ops
# ---------------------------------------------------------------- 

func _apply_op(old: Color, target_col: Color, weight: float) -> Color:
	var mask := state.channel_mask()
	var single := state.is_single_channel()
	var comps := [old.r, old.g, old.b, old.a]
	var tgt := [target_col.r, target_col.g, target_col.b, target_col.a]
	for i in 4:
		if not mask[i]:
			continue
		var tv: float = state.channel_value if single else tgt[i]
		match state.operation:
			VSState.Op.REPLACE:
				comps[i] = lerp(comps[i], tv, weight)
			VSState.Op.ADD:
				comps[i] = clampf(comps[i] + tv * weight, 0.0, 1.0)
			VSState.Op.ERASE:
				comps[i] = lerp(comps[i], 1.0, weight)
	return Color(comps[0], comps[1], comps[2], comps[3])


#endregion Color ops


#region Brush painting
# ----------------------------------------------------------------
# Brush painting
# ---------------------------------------------------------------- 

func paint(camera: Camera3D, mouse: Vector2) -> bool:
	var touched := false
	var radius := state.radius
	var target_col := state.color
	var sel_on := has_selection()
	var do_occ := state.front_verts_only and total_triangles() <= OCCLUSION_TRI_LIMIT

	for ti in targets.size():
		var md: VSMeshData = targets[ti]
		var n := md.vertex_count()
		if n == 0:
			continue
		var weights := PackedFloat32Array()
		weights.resize(n)

		for fi in n:
			var world := md.get_world_vertex(fi)
			if not is_in_front(camera, world):
				weights[fi] = 0.0
				continue
			if not within_draw_distance(camera, world):
				weights[fi] = 0.0
				continue
			var screen := camera.unproject_position(world) + split_screen_offset(camera, md, fi)
			var d := screen.distance_to(mouse)
			if d > radius:
				weights[fi] = 0.0
				continue
			if state.front_verts_only:
				var world_n := (md.mesh_instance.global_transform.basis * md.get_local_normal(fi)).normalized()
				if not is_front_facing(camera, world, world_n):
					weights[fi] = 0.0
					continue
				if do_occ and occluded(camera, md, fi, world):
					weights[fi] = 0.0
					continue
			var t := clampf(d / radius, 0.0, 1.0)
			var fall := clampf(state.falloff.sample_baked(t), 0.0, 1.0) if state.falloff else (1.0 - t)
			weights[fi] = fall * state.opacity

		if state.shared_verts == VSState.SharedVerts.MERGE:
			for key in md.merge_groups:
				var group: Array = md.merge_groups[key]
				var best := 0.0
				for fi in group:
					best = maxf(best, weights[fi])
				if best > 0.0:
					for fi in group:
						weights[fi] = best

		if sel_on:
			for fi in n:
				if not md.is_selected(fi):
					weights[fi] = 0.0

		if _in_stroke:
			var origin: PackedColorArray = _stroke_origin[ti]
			var swt: PackedFloat32Array = _stroke_weight[ti]
			for fi in n:
				var w: float = weights[fi]
				if w <= swt[fi]:
					continue
				swt[fi] = w
				md.set_color(fi, _apply_op(origin[fi], target_col, w))
				touched = true
		else:
			for fi in n:
				var w: float = weights[fi]
				if w <= 0.0:
					continue
				md.set_color(fi, _apply_op(md.get_color(fi), target_col, w))
				touched = true

	return touched


func commit() -> void:
	for md in targets:
		md.rebuild()


#endregion Brush


#region Eyedropper
# ----------------------------------------------------------------
# Eyedropper
# ---------------------------------------------------------------- 

func sample(camera: Camera3D, mouse: Vector2, max_px := 40.0):
	var best_d := max_px
	var best: Variant = null
	for md in targets:
		for fi in md.vertex_count():
			var world := md.get_world_vertex(fi)
			if not is_in_front(camera, world):
				continue
			var d := (camera.unproject_position(world) + split_screen_offset(camera, md, fi)).distance_to(mouse)
			if d < best_d:
				best_d = d
				best = md.get_color(fi)
	return best


#endregion Eyedropper


#region Precision tool
# ----------------------------------------------------------------
# Precision tool
# ----------------------------------------------------------------

func precision_lock() -> Dictionary:
	return _plock


func clear_precision_lock() -> void:
	_plock = {}


func precision_update(_camera: Camera3D, _mouse: Vector2) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _make_plock(_camera: Camera3D, _md: VSMeshData, _group: Array, _mouse: Vector2, _center: Vector2) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _acquire_clump(_camera: Camera3D, _mouse: Vector2) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func paint_precision(_camera: Camera3D, _mouse: Vector2) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


#endregion Precision


#region Paint normals
# ----------------------------------------------------------------
# Paint normals
# ----------------------------------------------------------------

func paint_normals(_camera: Camera3D, _mouse: Vector2, _smooth: bool) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func fill_normals(_smooth: bool) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


#endregion Paint normals


#region Blur
# ----------------------------------------------------------------
# Blur
# ----------------------------------------------------------------

func paint_blur(camera: Camera3D, mouse: Vector2) -> bool:
	var radius := state.radius
	if radius <= 0.0:
		return false
	var sel_on := has_selection()
	var strength := clampf(state.opacity, 0.0, 1.0)
	var mask := state.channel_mask()
	var do_occ := state.front_verts_only and total_triangles() <= OCCLUSION_TRI_LIMIT
	var touched := false
	for md in targets:
		if not is_instance_valid(md.mesh_instance):
			continue
		var basis := md.mesh_instance.global_transform.basis
		var n := md.vertex_count()
		var updates: Dictionary = {}
		for fi in n:
			if sel_on and not md.is_selected(fi):
				continue
			var world := md.get_world_vertex(fi)
			if not is_in_front(camera, world):
				continue
			if not within_draw_distance(camera, world):
				continue
			var d := camera.unproject_position(world).distance_to(mouse)
			if d > radius:
				continue
			if state.front_verts_only:
				var wn := (basis * md.get_local_normal(fi)).normalized()
				if not is_front_facing(camera, world, wn):
					continue
				if do_occ and occluded(camera, md, fi, world):
					continue
			var neigh := md.neighbors(fi)
			if neigh.is_empty():
				continue
			var t := clampf(d / radius, 0.0, 1.0)
			var fall := clampf(state.falloff.sample_baked(t), 0.0, 1.0) if state.falloff else (1.0 - t)
			var w := fall * strength
			if w <= 0.0:
				continue
			var acc := Color(0, 0, 0, 0)
			for nb in neigh:
				acc += md.get_color(nb)
			var inv := 1.0 / float(neigh.size())
			acc = Color(acc.r * inv, acc.g * inv, acc.b * inv, acc.a * inv)
			var own := md.get_color(fi)
			var comps := [own.r, own.g, own.b, own.a]
			var avg := [acc.r, acc.g, acc.b, acc.a]
			for i in 4:
				if mask[i]:
					comps[i] = lerp(comps[i], avg[i], w)
			updates[fi] = Color(comps[0], comps[1], comps[2], comps[3])
		for fi in updates:
			md.set_color(fi, updates[fi])
			touched = true
	return touched


func snapshot_surfaces_all() -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return []


func restore_surfaces_all(_data: Array) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


#endregion Blur


#region Bulk actions
# ----------------------------------------------------------------
# Bulk actions
# ----------------------------------------------------------------

func fill_all(col: Color) -> void:
	var t := clampf(state.opacity, 0.0, 1.0)
	var sel_on := has_selection()
	for md in targets:
		for fi in md.vertex_count():
			if sel_on and not md.is_selected(fi):
				continue
			md.set_color(fi, _mask_apply(md.get_color(fi), col, t))
	commit()


func erase_all() -> void:
	var sel_on := has_selection()
	for md in targets:
		for fi in md.vertex_count():
			if sel_on and not md.is_selected(fi):
				continue
			var mask := state.channel_mask()
			var c := md.get_color(fi)
			var comps := [c.r, c.g, c.b, c.a]
			for i in 4:
				if mask[i]:
					comps[i] = 1.0
			md.set_color(fi, Color(comps[0], comps[1], comps[2], comps[3]))
	commit()


func _mask_apply(old: Color, col: Color, t := 1.0) -> Color:
	var mask := state.channel_mask()
	var single := state.is_single_channel()
	var oc := [old.r, old.g, old.b, old.a]
	var nc := [col.r, col.g, col.b, col.a]
	for i in 4:
		if mask[i]:
			var tv: float = state.channel_value if single else nc[i]
			oc[i] = lerp(oc[i], tv, t)
	return Color(oc[0], oc[1], oc[2], oc[3])


func replace_color(_target_col: Color, _new_col: Color, _threshold: float) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _color_close(_a: Color, _b: Color, _t: float) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


#endregion Bulk actions


#region Undo / snapshots
# ----------------------------------------------------------------
# Undo / snapshots
# ----------------------------------------------------------------

func snapshot_all() -> Array:
	var out: Array = []
	for md in targets:
		out.append(md.snapshot_colors())
	return out


func restore_all(data: Array) -> void:
	for i in mini(data.size(), targets.size()):
		targets[i].restore_colors(data[i])

#endregion


#region Source re-sync
# ----------------------------------------------------------------
# Source mesh re-sync
# ----------------------------------------------------------------

func resync_uvs(_sources: Array, _by_position := false) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}

#endregion Source re-sync