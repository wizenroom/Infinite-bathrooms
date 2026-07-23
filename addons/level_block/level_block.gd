@tool
@icon("res://addons/level_block/icon.svg")
class_name LevelBlock
extends Node3D
## Greybox box primitive. Node origin sits at the front-bottom-right corner
## (+X, minY, +Z); the block grows into -X, +Y, -Z from that grid-snappable
## corner. Mesh + collision are rebuilt procedurally and never serialized into
## the scene (children carry no owner) — only [member size], [member grid_step],
## [member material], and the collision flags persist.

const MIN_SIZE: float = 0.05

## Box extents in local units. Spans the box across [member size] on each axis.
@export var size: Vector3 = Vector3.ONE:
	set(value):
		var step: float = maxf(grid_step, MIN_SIZE)
		size = value.max(Vector3(MIN_SIZE, MIN_SIZE, MIN_SIZE)).snapped(
			Vector3(step, step, step),
		)
		_rebuild()
## Snap increment applied to [member size] (and used by the gizmo handles).
@export var grid_step: float = 1.0:
	set(value):
		grid_step = maxf(value, MIN_SIZE)
		_rebuild()
## Surface material for the greybox faces.
@export var material: Material = preload("res://addons/level_block/default_material.tres"):
	set(value):
		material = value
		if _mesh_instance != null:
			_mesh_instance.material_override = material
## Physics layer(s) the static body occupies. Set to your world/collision layer.
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		if _body != null:
			_body.collision_layer = collision_layer
## Physics layer(s) the static body scans. Static geometry usually scans nothing.
@export_flags_3d_physics var collision_mask: int = 0:
	set(value):
		collision_mask = value
		if _body != null:
			_body.collision_mask = collision_mask

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D


func _ready() -> void:
	_rebuild()


## Editor-only setter used by the gizmo to grow one axis from the fixed corner.
func set_axis_size(axis: int, value: float) -> void:
	var new_size: Vector3 = size
	new_size[axis] = value
	size = new_size


## Builds (or refreshes) the non-serialized child mesh + collision. Idempotent.
func _rebuild() -> void:
	if not is_node_ready():
		return
	_ensure_children()
	var box_mesh: BoxMesh = _mesh_instance.mesh
	box_mesh.size = size
	var box_shape: BoxShape3D = _shape.shape
	box_shape.size = size
	# BoxMesh/BoxShape3D are center-origin. Offset so the node origin lands on the
	# front-bottom-right corner (+X, minY, +Z); block grows into -X, +Y, -Z.
	var center: Vector3 = Vector3(-size.x * 0.5, size.y * 0.5, -size.z * 0.5)
	_mesh_instance.position = center
	_shape.position = center
	update_gizmos()


## Creates the runtime children once (no owner → kept out of the .tscn). On a
## @tool script reload the instance vars reset but the children persist, so we
## re-adopt the meta-tagged survivors instead of spawning duplicates.
func _ensure_children() -> void:
	if _mesh_instance == null:
		_mesh_instance = _find_proc_child(&"_lb_mesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.mesh = BoxMesh.new()
		_mesh_instance.set_meta(&"_lb_mesh", true)
		add_child(_mesh_instance)
	_mesh_instance.material_override = material
	if _body == null:
		_body = _find_proc_child(&"_lb_body") as StaticBody3D
		if _body != null:
			_shape = _body.get_child(0) as CollisionShape3D
	if _body == null:
		_body = StaticBody3D.new()
		_body.set_meta(&"_lb_body", true)
		_shape = CollisionShape3D.new()
		_shape.shape = BoxShape3D.new()
		_body.add_child(_shape)
		add_child(_body)
	_body.collision_layer = collision_layer
	_body.collision_mask = collision_mask


## Returns the procedural child carrying [param meta_key], or null. Bounded scan.
func _find_proc_child(meta_key: StringName) -> Node:
	for child: Node in get_children():
		if child.has_meta(meta_key):
			return child
	return null
