@tool
extends EditorPlugin
## Registers the [LevelBlock] face-drag gizmo. The node itself is a global
## class ([code]class_name LevelBlock[/code] + [code]@icon[/code]), so it
## shows in Create New Node without a custom-type registration.

const LevelBlockGizmo := preload("res://addons/level_block/level_block_gizmo.gd")

var _gizmo: EditorNode3DGizmoPlugin


func _enter_tree() -> void:
	_gizmo = LevelBlockGizmo.new(get_undo_redo())
	add_node_3d_gizmo_plugin(_gizmo)


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_gizmo)
	_gizmo = null
