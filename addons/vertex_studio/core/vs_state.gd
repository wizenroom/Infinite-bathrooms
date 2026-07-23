@tool
extends RefCounted
class_name VSState

## Shared, observable state for the whole addon.
## The UI panel writes to it, the overlay and painter read from it.

signal changed
signal color_changed
signal view_changed

enum Op { REPLACE, ADD, ERASE, PRECISION, NORMALS, BLUR }
enum NormalsMode { HARD, SMOOTH }
enum Target { VERTEX, EDGE, FACE }
enum SharedVerts { MERGE, SPLIT }
enum Channel { RGBA, R, G, B, A }
enum Debug { OFF, R, G, B, A }
enum ToolMode { PAINT, SELECT }
enum SelectType { LASSO, RECTANGLE, ELLIPSE, POINT, LINKED }
# What to do with the mesh's materials when Vertex Studio stops editing it?
enum CommitMode { RESTORE, STANDARD, KEEP }

# ---------------------------------------------------------------- 
# Tool
# ---------------------------------------------------------------- 

var tool_enabled := false
var tool_mode: int = ToolMode.PAINT
var select_type: int = SelectType.RECTANGLE

# ---------------------------------------------------------------- 
# View
# ---------------------------------------------------------------- 

var show_wireframe := false
var show_vertex_colors := true
var show_textured := true
var include_children := true
var isolate := false
var debug_channel: int = Debug.OFF

# ---------------------------------------------------------------- 
# Paint
# ---------------------------------------------------------------- 

var operation: int = Op.REPLACE
var target: int = Target.VERTEX
var shared_verts: int = SharedVerts.MERGE
var normals_mode: int = NormalsMode.SMOOTH
var opacity := 1.0
var radius := 40.0
var channel_r := true
var channel_g := true
var channel_b := true
var channel_a := true
var color := Color(0.0, 1.0, 0.0, 1.0)
var channel_value := 1.0
var falloff: Curve
var front_verts_only := true
var draw_distance := 50.0
var dot_size := 10.0
var show_vertices := true
var always_show_vertices := true
var realtime_painting := true

var auto_focus_node_tab := true

# ---------------------------------------------------------------- 
# Swatches
# ---------------------------------------------------------------- 

var swatches: Array[Color] = [
	Color.WHITE,
	Color.BLACK,
	Color(1, 0, 0, 1),
	Color(0, 1, 0, 1),
	Color(0, 0, 1, 1),
]

# ---------------------------------------------------------------- 
# Actions
# ---------------------------------------------------------------- 

var replace_target := Color(1, 0, 0, 1)
var replace_new := Color(0, 1, 0, 1)
var replace_threshold := 0.05

# ----------------------------------------------------------------
# Material
# ----------------------------------------------------------------

var commit_mode: int = CommitMode.RESTORE
var setup_meshes: Dictionary = {}
var section_open: Dictionary = {}

# ---------------------------------------------------------------- 
# Snapshot
# ---------------------------------------------------------------- 

var snapshot_path := ""


func _init() -> void:
	falloff = Curve.new()
	falloff.add_point(Vector2(0.0, 1.0))
	falloff.add_point(Vector2(1.0, 1.0))


func emit_changed() -> void:
	changed.emit()


func channel_mask() -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return [true, true, true, true]


func is_rgba_mode() -> bool:
	return channel_r and channel_g and channel_b and channel_a


func is_single_channel() -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func set_channel_rgba() -> void:
	channel_r = true
	channel_g = true
	channel_b = true
	channel_a = true


func apply_channel_button(idx: int, shift: bool) -> void:
	if idx == Channel.RGBA:
		set_channel_rgba()
		return
	var ci: int = idx - 1
	if not shift:
		for i in 4:
			_set_channel_i(i, i == ci)
		return
	if is_rgba_mode():
		_set_channel_i(ci, false)
	else:
		_set_channel_i(ci, not _get_channel_i(ci))
	if _active_channel_count() == 0:
		set_channel_rgba()


func channel_button_pressed(idx: int) -> bool:
	if idx == Channel.RGBA:
		return is_rgba_mode()
	return _get_channel_i(idx - 1) and not is_rgba_mode()


func _active_channel_count() -> int:
	var n := 0
	for on in channel_mask():
		if on:
			n += 1
	return n


func _get_channel_i(i: int) -> bool:
	match i:
		0: return channel_r
		1: return channel_g
		2: return channel_b
		3: return channel_a
	return false


func _set_channel_i(i: int, on: bool) -> void:
	match i:
		0: channel_r = on
		1: channel_g = on
		2: channel_b = on
		3: channel_a = on


func get_swatch(i: int) -> Color:
	if i >= 0 and i < swatches.size():
		return swatches[i]
	return Color.WHITE


# ---------------------------------------------------------------- 
# Persistence
# ---------------------------------------------------------------- 

func to_dict() -> Dictionary:
	var pts: Array = []
	if falloff:
		for i in falloff.point_count:
			var p := falloff.get_point_position(i)
			pts.append([p.x, p.y])
	return {
		"show_wireframe": show_wireframe,
		"show_vertex_colors": show_vertex_colors,
		"show_textured": show_textured,
		"include_children": include_children,
		"debug_channel": debug_channel,
		"select_type": select_type,
		"operation": operation,
		"target": target,
		"shared_verts": shared_verts,
		"normals_mode": normals_mode,
		"opacity": opacity,
		"radius": radius,
		"channel_mask": [channel_r, channel_g, channel_b, channel_a],
		"channel_value": channel_value,
		"color": color,
		"front_verts_only": front_verts_only,
		"draw_distance": draw_distance,
		"dot_size": dot_size,
		"show_vertices": show_vertices,
		"always_show_vertices": always_show_vertices,
		"realtime_painting": realtime_painting,
		"auto_focus_node_tab": auto_focus_node_tab,
		"swatches": swatches.map(func(c): return c),
		"replace_target": replace_target,
		"replace_new": replace_new,
		"replace_threshold": replace_threshold,
		"falloff": pts,
		"commit_mode": commit_mode,
		"setup_meshes": setup_meshes,
		"section_open": section_open,
	}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	show_wireframe = _vb(d.get("show_wireframe"), show_wireframe)
	show_vertex_colors = _vb(d.get("show_vertex_colors"), show_vertex_colors)
	show_textured = _vb(d.get("show_textured"), show_textured)
	include_children = _vb(d.get("include_children"), include_children)
	debug_channel = _vi(d.get("debug_channel"), debug_channel)
	select_type = _vi(d.get("select_type"), select_type)
	operation = _vi(d.get("operation"), operation)
	target = _vi(d.get("target"), target)
	shared_verts = _vi(d.get("shared_verts"), shared_verts)
	normals_mode = _vi(d.get("normals_mode"), normals_mode)
	opacity = _vf(d.get("opacity"), opacity)
	radius = _vf(d.get("radius"), radius)
	_apply_channel_prefs(d)
	channel_value = _vf(d.get("channel_value"), channel_value)
	color = _vc(d.get("color"), color)
	front_verts_only = _vb(d.get("front_verts_only"), front_verts_only)
	draw_distance = _vf(d.get("draw_distance"), draw_distance)
	dot_size = _vf(d.get("dot_size"), dot_size)
	show_vertices = _vb(d.get("show_vertices"), show_vertices)
	always_show_vertices = _vb(d.get("always_show_vertices"), always_show_vertices)
	realtime_painting = _vb(d.get("realtime_painting"), realtime_painting)
	auto_focus_node_tab = _vb(d.get("auto_focus_node_tab"), auto_focus_node_tab)
	replace_target = _vc(d.get("replace_target"), replace_target)
	replace_new = _vc(d.get("replace_new"), replace_new)
	replace_threshold = _vf(d.get("replace_threshold"), replace_threshold)
	commit_mode = _vi(d.get("commit_mode"), commit_mode)
	var sm = d.get("setup_meshes", {})
	if sm is Dictionary:
		setup_meshes = sm

	var so = d.get("section_open", {})
	if so is Dictionary:
		section_open = so

	var sw: Array = d.get("swatches", [])
	if sw is Array and not sw.is_empty():
		var arr: Array[Color] = []
		for c in sw:
			if c is Color:
				arr.append(c)
		if not arr.is_empty():
			swatches = arr

	var pts = d.get("falloff", [])
	_apply_falloff_prefs(pts)


func _apply_channel_prefs(d: Dictionary) -> void:
	var mask = d.get("channel_mask", [])
	if mask is Array and mask.size() == 4:
		channel_r = _vb(mask[0], channel_r)
		channel_g = _vb(mask[1], channel_g)
		channel_b = _vb(mask[2], channel_b)
		channel_a = _vb(mask[3], channel_a)
		if _active_channel_count() == 0:
			set_channel_rgba()
		return
	var legacy: int = _vi(d.get("channel"), Channel.RGBA)
	match legacy:
		Channel.R:
			channel_r = true
			channel_g = false
			channel_b = false
			channel_a = false
		Channel.G:
			channel_r = false
			channel_g = true
			channel_b = false
			channel_a = false
		Channel.B:
			channel_r = false
			channel_g = false
			channel_b = true
			channel_a = false
		Channel.A:
			channel_r = false
			channel_g = false
			channel_b = false
			channel_a = true
		_:
			set_channel_rgba()


func _apply_falloff_prefs(_pts: Variant) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


static func _vi(v, def: int) -> int:
	if v is int: return v
	if v is float: return int(v)
	if v is bool: return 1 if v else 0
	return def


static func _vf(v, def: float) -> float:
	if v is float: return v
	if v is int: return float(v)
	return def


static func _vb(v, def: bool) -> bool:
	if v is bool: return v
	return def


static func _vc(v, def: Color) -> Color:
	if v is Color: return v
	return def
