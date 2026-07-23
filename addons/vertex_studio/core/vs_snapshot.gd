@tool
extends Resource
class_name VSSnapshot

## Stores the full editable geometry (vertex/normal/color/uv/index, which includes topology
## hard/smooth splits) plus the active selection for one or more meshes, so a
## snapshot restores the EXACT mesh state.[br][br]
##
## Format:[br]
## - `"name": String`[br]
## - `"vcount": int`[br]
## - `"full_surfaces": Array[Array]` per-surface `ARRAY_MAX` arrays (`VSMeshData.snapshot_surfaces`)[br]
## - `"selected": PackedByteArray` per flat vertex index (1 = selected)

@export var meshes: Array = []
# Vertex groups (`{name: Array[PackedVector3Array]}`)
@export var vertex_groups: Dictionary = {}


func capture_from(_painter: VSPainter) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func apply_to(_painter: VSPainter) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func apply_to_mesh_instance(_mi: MeshInstance3D, _index: int = -1) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false
