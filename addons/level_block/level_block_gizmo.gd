@tool
extends EditorNode3DGizmoPlugin
## Draws box edges + three face-drag handles for [LevelBlock]. Dragging a handle
## grows that axis from the fixed front-bottom-right pivot corner, snapped to the
## block's [member LevelBlock.grid_step].

var _handle_axes: PackedInt32Array = [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]
## Direction each axis grows from the pivot corner (+X, minY, +Z): -X, +Y, -Z.
var _growth_dirs: PackedVector3Array = [Vector3.LEFT, Vector3.UP, Vector3.FORWARD]
var _handle_labels: PackedStringArray = ["X", "Y", "Z"]

## How far the handle dots float off their face, in local units.
const HANDLE_OFFSET: float = 0.3
## Point sprite size in pixels for the handle dots.
const HANDLE_POINT_SIZE: float = 28.0

## Axis tints matching the editor gizmo colors (X red, Y green, Z blue).
var _axis_colors: PackedColorArray = [
	Color(0.96, 0.21, 0.32), Color(0.54, 0.84, 0.10), Color(0.16, 0.55, 0.96)
]
var _handle_materials: Array[StandardMaterial3D] = []
var _undo_redo: EditorUndoRedoManager
var _drag_start: Vector3 = Vector3.ZERO


func _init(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	create_material("edges", Color(0.4, 0.8, 1.0))
	# create_handle_material()'s materials aren't retrievable via get_material(),
	# so build per-axis point materials directly and keep refs. A solid white
	# disc (tinted per axis) reads cleaner than the hollow editor ring icon.
	var dot_tex: Texture2D = _make_dot_texture()
	for axis: int in 3:
		_handle_materials.append(_make_handle_material(_axis_colors[axis], dot_tex))


## Solid white anti-aliased disc, tinted at draw time by the handle material.
func _make_dot_texture() -> ImageTexture:
	var dim: int = 64
	var center: Vector2 = Vector2(dim, dim) * 0.5
	var radius: float = dim * 0.5 - 1.0
	var img: Image = Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	for y: int in dim:
		for x: int in dim:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha: float = clampf(radius - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


## Unshaded point sprite tinted per axis, drawn on top of geometry (no depth
## test) so the dots always stay visible, using the editor handle icon.
func _make_handle_material(color: Color, tex: Texture2D) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.use_point_size = true
	mat.point_size = HANDLE_POINT_SIZE
	mat.albedo_color = color
	mat.albedo_texture = tex
	return mat


func _get_gizmo_name() -> String:
	return "LevelBlock"


func _has_gizmo(node: Node3D) -> bool:
	return node is LevelBlock


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var block: LevelBlock = gizmo.get_node_3d() as LevelBlock
	if block == null:
		return
	var s: Vector3 = block.size
	gizmo.add_lines(_edge_lines(s), get_material("edges", gizmo))
	# Collision triangles make the whole box click-selectable in the viewport —
	# the procedural mesh child is non-owned, so it can't forward selection.
	gizmo.add_collision_triangles(_selection_mesh(s))
	var points: PackedVector3Array = _handle_points(s)
	for axis: int in 3:
		gizmo.add_handles([points[axis]], _handle_materials[axis], [axis])


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return "Size %s" % _handle_labels[handle_id]


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var block: LevelBlock = gizmo.get_node_3d() as LevelBlock
	if block == null:
		return 0.0
	_drag_start = block.size
	return block.size[_handle_axes[handle_id]]


func _set_handle(
	gizmo: EditorNode3DGizmo,
	handle_id: int,
	_secondary: bool,
	camera: Camera3D,
	screen_pos: Vector2
) -> void:
	var block: LevelBlock = gizmo.get_node_3d() as LevelBlock
	if block == null:
		return
	var axis: int = _handle_axes[handle_id]
	var t: float = _ray_axis_distance(block, handle_id, camera, screen_pos)
	var step: float = maxf(block.grid_step, LevelBlock.MIN_SIZE)
	var snapped_t: float = maxf(roundf(t / step) * step, step)
	block.set_axis_size(axis, snapped_t)


func _commit_handle(
	gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, restore: Variant, cancel: bool
) -> void:
	var block: LevelBlock = gizmo.get_node_3d() as LevelBlock
	if block == null:
		return
	var axis: int = _handle_axes[handle_id]
	if cancel:
		block.set_axis_size(axis, float(restore))
		return
	var new_size: Vector3 = block.size
	_undo_redo.create_action("Resize Level Block")
	_undo_redo.add_do_property(block, &"size", new_size)
	_undo_redo.add_undo_property(block, &"size", _drag_start)
	_undo_redo.commit_action(false)


## Closest distance along the axis growth line to the mouse ray, in block space.
func _ray_axis_distance(block: LevelBlock, handle_id: int, camera: Camera3D, screen_pos: Vector2) -> float:
	var gti: Transform3D = block.global_transform.affine_inverse()
	var ray_from: Vector3 = gti * camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = (gti.basis * camera.project_ray_normal(screen_pos)).normalized()
	var da: Vector3 = _growth_dirs[handle_id]
	# Lines: P = s*da (through origin), Q = ray_from + u*ray_dir. Minimize |P-Q|.
	var b: float = da.dot(ray_dir)
	var denom: float = 1.0 - b * b
	if absf(denom) < 0.0001:
		return block.size[_handle_axes[handle_id]]
	var w0: Vector3 = -ray_from
	var d: float = da.dot(w0)
	var e: float = ray_dir.dot(w0)
	return (b * e - d) / denom


## The 8 box corners. Box spans x:[-s.x,0] y:[0,s.y] z:[-s.z,0]; pivot at (0,0,0).
func _box_corners(s: Vector3) -> PackedVector3Array:
	return [
		Vector3(0, 0, 0), Vector3(-s.x, 0, 0), Vector3(-s.x, 0, -s.z), Vector3(0, 0, -s.z),
		Vector3(0, s.y, 0), Vector3(-s.x, s.y, 0), Vector3(-s.x, s.y, -s.z), Vector3(0, s.y, -s.z),
	]


func _edge_lines(s: Vector3) -> PackedVector3Array:
	var c: PackedVector3Array = _box_corners(s)
	var lines: PackedVector3Array = []
	var edges: PackedInt32Array = [
		0, 1, 1, 2, 2, 3, 3, 0,  # bottom
		4, 5, 5, 6, 6, 7, 7, 4,  # top
		0, 4, 1, 5, 2, 6, 3, 7,  # verticals
	]
	for i: int in edges:
		lines.append(c[i])
	return lines


## Solid box as a TriangleMesh for viewport click-selection (12 tris).
func _selection_mesh(s: Vector3) -> TriangleMesh:
	var c: PackedVector3Array = _box_corners(s)
	var tris: PackedInt32Array = [
		0, 1, 2, 0, 2, 3,  # bottom
		4, 6, 5, 4, 7, 6,  # top
		0, 5, 1, 0, 4, 5,  # side -X..0 @ z=0
		1, 6, 2, 1, 5, 6,  # side @ x=-s.x
		2, 7, 3, 2, 6, 7,  # side @ z=-s.z
		3, 4, 0, 3, 7, 4,  # side @ x=0
	]
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in tris:
		st.add_vertex(c[i])
	return st.commit().generate_triangle_mesh()


func _handle_points(s: Vector3) -> PackedVector3Array:
	# Handles sit on the faces opposite the pivot, floated out along the growth
	# direction so the dots stand clear of the surface.
	var points: PackedVector3Array = [
		Vector3(-s.x, s.y * 0.5, -s.z * 0.5),  # -X face
		Vector3(-s.x * 0.5, s.y, -s.z * 0.5),  # +Y face
		Vector3(-s.x * 0.5, s.y * 0.5, -s.z),  # -Z face
	]
	for axis: int in 3:
		points[axis] += _growth_dirs[axis] * HANDLE_OFFSET
	return points
