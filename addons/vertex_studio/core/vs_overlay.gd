@tool
extends RefCounted
class_name VSOverlay

## Draws everything on top of the 3D viewport: wireframe, vertex squares,
## the brush circle and the swatch strip under the brush.

var state: VSState
var painter: VSPainter

const HARD_COLOR := Color(1.0, 0.5, 0.5)
const SMOOTH_COLOR := Color(0.45, 0.75, 1.0)

var mouse := Vector2.ZERO
var mouse_inside := false
var eyedropper := false

var _pick_icon: Texture2D = load("res://addons/vertex_studio/icons/pick.svg")

var _op_icons: Array[Texture2D] = [
	load("res://addons/vertex_studio/icons/brush.svg"),
	load("res://addons/vertex_studio/icons/mode_add.svg"),
	load("res://addons/vertex_studio/icons/mode_erase.svg"),
	load("res://addons/vertex_studio/icons/mode_precision.svg"),
	load("res://addons/vertex_studio/icons/mode_normals.svg"),
	load("res://addons/vertex_studio/icons/mode_blur.svg"),
]

var _select_icons: Array[Texture2D] = [
	load("res://addons/vertex_studio/icons/select_lasso.svg"),
	load("res://addons/vertex_studio/icons/select_rectangle.svg"),
	load("res://addons/vertex_studio/icons/select_ellipse.svg"),
	load("res://addons/vertex_studio/icons/cursor.svg"),
]
var _precision_icon: Texture2D = load("res://addons/vertex_studio/icons/mode_precision.svg")

var selecting := false
var sel_points := PackedVector2Array()
var sel_type := 0

var sel_modifier := 0

var _precision_md: VSMeshData = null
var _precision_group: Array = []
var _precision_lock: Dictionary = {}


func _init(p_state: VSState, p_painter: VSPainter) -> void:
	state = p_state
	painter = p_painter


func draw(overlay: Control, camera: Camera3D) -> void:
	if camera == null or painter == null or not painter.has_targets():
		return

	var precision := state.tool_mode == VSState.ToolMode.PAINT \
		and state.operation == VSState.Op.PRECISION
	_precision_md = null
	_precision_group = []
	_precision_lock = {}
	if precision and not eyedropper and state.tool_enabled and mouse_inside:
		_precision_lock = painter.precision_lock()
		if not _precision_lock.is_empty():
			_precision_md = _precision_lock["md"]
			_precision_group = _precision_lock["group"]

	if state.show_wireframe:
		_draw_wireframe(overlay, camera)

	var normals_tool := state.tool_mode == VSState.ToolMode.PAINT \
		and state.operation == VSState.Op.NORMALS and state.tool_enabled
	if state.show_vertices or normals_tool:
		_draw_vertices(overlay, camera)

	if eyedropper:
		if mouse_inside:
			_draw_pick_icon(overlay)
	elif state.tool_mode == VSState.ToolMode.PAINT:
		if precision:
			if state.tool_enabled and mouse_inside:
				_draw_precision(overlay, camera)
				_draw_cursor_icon(overlay, _precision_icon)
		elif state.tool_enabled and mouse_inside:
			_draw_brush(overlay)
	else:
		if selecting:
			_draw_marquee(overlay)
		if state.tool_enabled and mouse_inside:
			_draw_select_icon(overlay)


func _draw_pick_icon(overlay: Control) -> void:
	if _pick_icon == null:
		return
	var s := 24.0 * EditorInterface.get_editor_scale()
	var pos := mouse - Vector2(s, s) * 0.5

	overlay.draw_texture_rect(_pick_icon, Rect2(pos + Vector2(1, 1), Vector2(s, s)), false, Color(0, 0, 0, 0.7))
	overlay.draw_texture_rect(_pick_icon, Rect2(pos, Vector2(s, s)), false, Color(1, 1, 1, 1))


func _draw_wireframe(overlay: Control, camera: Camera3D) -> void:
	var col := Color(0, 0, 0, 0.35)
	for md in painter.targets:
		if not is_instance_valid(md.mesh_instance):
			continue
		var xform := md.mesh_instance.global_transform
		for s in md.surfaces:
			var verts: PackedVector3Array = s.arrays[Mesh.ARRAY_VERTEX]
			var iraw = s.arrays[Mesh.ARRAY_INDEX]
			var has_idx: bool = iraw is PackedInt32Array and not iraw.is_empty()
			var indices: PackedInt32Array = iraw if has_idx else PackedInt32Array()
			var count: int = indices.size() if has_idx else verts.size()
			var i := 0
			while i + 2 < count:
				var a: int = indices[i] if has_idx else i
				var b: int = indices[i + 1] if has_idx else i + 1
				var c: int = indices[i + 2] if has_idx else i + 2
				var pa := xform * verts[a]
				var pb := xform * verts[b]
				var pc := xform * verts[c]
				_edge(overlay, camera, pa, pb, col)
				_edge(overlay, camera, pb, pc, col)
				_edge(overlay, camera, pc, pa, col)
				i += 3


func _edge(overlay: Control, camera: Camera3D, a: Vector3, b: Vector3, col: Color) -> void:
	if not painter.is_in_front(camera, a) or not painter.is_in_front(camera, b):
		return
	overlay.draw_line(camera.unproject_position(a), camera.unproject_position(b), col, 1.0)


func _draw_vertices(overlay: Control, camera: Camera3D) -> void:
	var base := state.dot_size
	var r := state.radius
	var do_occlusion: bool = state.front_verts_only and painter.total_triangles() <= VSPainter.OCCLUSION_TRI_LIMIT
	var sel_on := painter.has_selection()
	var hide_others := sel_on and state.tool_mode == VSState.ToolMode.PAINT
	var brush_active := state.tool_mode == VSState.ToolMode.PAINT and state.tool_enabled and mouse_inside
	var precision := state.tool_mode == VSState.ToolMode.PAINT and state.operation == VSState.Op.PRECISION
	var normals := state.tool_mode == VSState.ToolMode.PAINT and state.operation == VSState.Op.NORMALS
	var eff_r := r
	if precision:
		eff_r = maxf(base, 8.0) * EditorInterface.get_editor_scale()
	for md in painter.targets:
		if not is_instance_valid(md.mesh_instance):
			continue
		var basis := md.mesh_instance.global_transform.basis
		for fi in md.vertex_count():
			var is_sel := md.is_selected(fi)
			if hide_others and not is_sel:
				continue
			var world := md.get_world_vertex(fi)
			if not painter.is_in_front(camera, world):
				continue
			if not painter.within_draw_distance(camera, world):
				continue
			if _precision_md == md and fi in _precision_group:
				continue
			var base_sp := camera.unproject_position(world)
			if not _precision_lock.is_empty() and bool(_precision_lock["is_fan"]):
				if base_sp.distance_to(_precision_lock["center"]) <= float(_precision_lock["radius"]):
					continue
			var offset := Vector2.ZERO if normals else painter.split_screen_offset(camera, md, fi)
			var sp := base_sp + offset
			var d := sp.distance_to(mouse) if mouse_inside else INF
			var near := d <= eff_r
			if not state.always_show_vertices and not is_sel and not near:
				if not (selecting and painter.point_in_marquee(sp, sel_points, sel_type)):
					continue
			if state.front_verts_only:
				var world_n := (basis * md.get_local_normal(fi)).normalized()
				if not painter.is_front_facing(camera, world, world_n):
					continue
				if do_occlusion and painter.occluded(camera, md, fi, world):
					continue
			var size := base
			if brush_active and near and not precision:
				var k := 1.0 - clampf(d / r, 0.0, 1.0)
				size = base * lerp(1.0, 2.4, k)
			var col := md.get_color(fi)
			if normals:
				col = SMOOTH_COLOR if md.is_smooth_vertex(fi) else HARD_COLOR
			var rect := Rect2(sp - Vector2(size, size) * 0.5, Vector2(size, size))
			if offset != Vector2.ZERO:
				overlay.draw_line(base_sp, sp, Color(0, 0, 0, 0.6), 1.0)

			if sel_on and is_sel:
				overlay.draw_rect(rect.grow(3.0), Color(1.0, 0.8, 0.1, 1.0), true)
			else:
				overlay.draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.9), true)
			overlay.draw_rect(rect, Color(col.r, col.g, col.b, 1.0), true)
			overlay.draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.0)


func _draw_brush(overlay: Control) -> void:
	var r := state.radius
	var base_col := state.color
	if state.operation == VSState.Op.NORMALS:
		base_col = SMOOTH_COLOR if state.normals_mode == VSState.NormalsMode.SMOOTH else HARD_COLOR
	var fill := Color(base_col.r, base_col.g, base_col.b, 0.15)
	overlay.draw_circle(mouse, r, fill)
	overlay.draw_arc(mouse, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 2.0, true)
	overlay.draw_arc(mouse, r, 0.0, TAU, 48, Color(0, 0, 0, 0.5), 4.0, true)
	_draw_op_icon(overlay, mouse + Vector2(0.0, r + 6.0 * EditorInterface.get_editor_scale()))


func _draw_op_icon(overlay: Control, top_center: Vector2) -> void:
	var op := state.operation
	if op < 0 or op >= _op_icons.size():
		return
	var tex := _op_icons[op]
	if tex == null:
		return
	var s := 20.0 * EditorInterface.get_editor_scale()
	var pos := Vector2(top_center.x - s * 0.5, top_center.y)
	overlay.draw_texture_rect(tex, Rect2(pos + Vector2(1, 1), Vector2(s, s)), false, Color(0, 0, 0, 0.7))
	overlay.draw_texture_rect(tex, Rect2(pos, Vector2(s, s)), false, Color(1, 1, 1, 1))


func _draw_precision(overlay: Control, camera: Camera3D) -> void:
	if _precision_md == null or _precision_group.is_empty():
		return
	if not is_instance_valid(_precision_md.mesh_instance):
		return
	var md := _precision_md
	var base := state.dot_size * 3.0
	var sel_on := painter.has_selection()
	if not _precision_lock.is_empty() and bool(_precision_lock["is_fan"]):
		var c: Vector2 = _precision_lock["center"]
		var rad := float(_precision_lock["radius"])
		overlay.draw_circle(c, rad, Color(state.color.r, state.color.g, state.color.b, 0.15))
		overlay.draw_arc(c, rad, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 1.5, true)
	for fi in _precision_group:
		var base_sp := camera.unproject_position(md.get_world_vertex(fi))
		var offset := painter.precision_offset(camera, md, fi)
		var sp := base_sp + offset
		var rect := Rect2(sp - Vector2(base, base) * 0.5, Vector2(base, base))
		if offset != Vector2.ZERO:
			overlay.draw_line(base_sp, sp, Color(0, 0, 0, 0.6), 1.0)
		var col := md.get_color(fi)
		if sel_on and md.is_selected(fi):
			overlay.draw_rect(rect.grow(2.0), Color(1.0, 0.8, 0.1, 1.0), true)
		else:
			overlay.draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.9), true)
		overlay.draw_rect(rect, Color(col.r, col.g, col.b, 1.0), true)
		overlay.draw_rect(rect, Color(1, 1, 1, 0.3), false, 1.0)


func _draw_select_icon(overlay: Control) -> void:
	var st := state.select_type
	if st < 0 or st >= _select_icons.size():
		return
	_draw_cursor_icon(overlay, _select_icons[st])
	if sel_modifier != 0:
		var scale := EditorInterface.get_editor_scale()
		var s := 20.0 * scale
		var icon_pos := mouse + Vector2(10.0, 10.0) * scale
		var center := Vector2(icon_pos.x + s + 6.0 * scale, icon_pos.y + s * 0.5)
		_draw_sel_sign(overlay, center, sel_modifier == 1, scale)


func _draw_sel_sign(overlay: Control, center: Vector2, plus: bool, scale: float) -> void:
	var half := 5.0 * scale
	var w := 2.0 * scale
	var shadow := Color(0, 0, 0, 0.7)
	var off := Vector2(1, 1)
	overlay.draw_line(center + Vector2(-half, 0) + off, center + Vector2(half, 0) + off, shadow, w)
	if plus:
		overlay.draw_line(center + Vector2(0, -half) + off, center + Vector2(0, half) + off, shadow, w)
	overlay.draw_line(center + Vector2(-half, 0), center + Vector2(half, 0), Color(1, 1, 1, 1), w)
	if plus:
		overlay.draw_line(center + Vector2(0, -half), center + Vector2(0, half), Color(1, 1, 1, 1), w)


func _draw_cursor_icon(overlay: Control, tex: Texture2D) -> void:
	if tex == null:
		return
	var scale := EditorInterface.get_editor_scale()
	var s := 20.0 * scale
	var pos := mouse + Vector2(10.0, 10.0) * scale
	overlay.draw_texture_rect(tex, Rect2(pos + Vector2(1, 1), Vector2(s, s)), false, Color(0, 0, 0, 0.7))
	overlay.draw_texture_rect(tex, Rect2(pos, Vector2(s, s)), false, Color(1, 1, 1, 1))


func _draw_marquee(overlay: Control) -> void:
	if sel_points.size() < 2:
		return
	var line := Color(1.0, 0.85, 0.15, 0.95)
	var fill := Color(1.0, 0.85, 0.15, 0.10)
	match sel_type:
		VSState.SelectType.RECTANGLE:
			var r := _bounds(sel_points)
			overlay.draw_rect(r, fill, true)
			overlay.draw_rect(r, line, false, 1.5)
		VSState.SelectType.ELLIPSE:
			var r := _bounds(sel_points)
			var pts := _ellipse_points(r, 48)
			overlay.draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			overlay.draw_polyline(pts, line, 1.5, true)
		_:
			var closed := sel_points.duplicate()
			closed.append(sel_points[0])
			overlay.draw_polyline(closed, line, 1.5, true)


func _bounds(pts: PackedVector2Array) -> Rect2:
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn)


func _ellipse_points(r: Rect2, segments: int) -> PackedVector2Array:
	var c := r.get_center()
	var rad := r.size * 0.5
	var out := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / segments
		out.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	return out
