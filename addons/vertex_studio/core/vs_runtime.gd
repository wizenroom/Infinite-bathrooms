@tool
extends Node
class_name VSRuntime

## Runtime variation switcher and tweening engine. Parent must be a MeshInstance3D.[br]
##
## DEVELOPER NOTE: except for switching variations in the inspector, the blending functions (aka tweening) are still very much experimental,
## and the runtime performance is not ideal (or better yet, it's still terrible), so use it at your own risk. You have been warned :)
## [br]
## Select variation with the `variation` property:[br]
## - "None" restores the base mesh (actually it restores the baseline stored on this node).
## - "Restore base instance" reloads mesh + groups from the owning scene on disk (live link to the source scene),
##	  effectively deleting any "mesh" data override that is in this instance (see `_restore_base_from_scene`
##    and `_load_base_from_scene_file`). This effectively restores from the base mesh/base scene.
## [br]
## Blend between two snapshots. Empty string `""` to revert to the base mesh:[br]
## - Uses blending shader (runs on the GPU, faster): `runtime.tween_snapshots("res://snapshots/moss.tres", "res://snapshots/blood.tres", 2.0)`[br]
## - Respects the mesh custom material, runs on the CPU (slower): `runtime.tween_snapshots_cpu("res://snapshots/moss.tres", "res://snapshots/blood.tres", 2.0)`
##
## [br]
## Blend from whatever is currently active toward a target:
## `runtime.tween_to_snapshot("res://snapshots/blood.tres", 1.5)` and `tween_to_snapshot_cpu("res://snapshots/blood.tres", 1.5)`
## [br]
## Cancel mid-blend (leaves the mesh at the current interpolated state):
## `runtime.stop_snapshot_blend()` and `stop_snapshot_blend_cpu()`
## [br]
## Signal:
## `runtime.snapshot_blend_finished.connect(func(p): print("blended vertex colors! new snapshot: ", p))`

enum BlendMaterialType { Unlit, Lit }

signal snapshot_blend_finished(to_path: String)

## Variation to apply to the mesh instance, creating a different, non-destructive variation of the mesh.
## You can revert back to the baseline mesh by selecting "None". 
## In case the base mesh is not fully restored,
## click "Restore base instance" to force reload data from the base mesh scene file.
@export var variation: int = 0:
	set(value):
		if _activate_idx == value:
			return
		_activate_idx = value
		_apply_snapshot_index(value)
	get:
		return _activate_idx

## Restore base instance from the original scene.
## Notice that if this is a duplicated instance child from a parent with "Editable Children" active,
## this will not work, as the link with the base instance is lost.
@export_tool_button("Restore base instance", "Reload") var _restore_base_instance_btn = restore_base_from_original_scene

## When blending snapshots in the GPU, use the unlit or the lit shader?
@export var blend_material_type: BlendMaterialType = BlendMaterialType.Unlit

@export_storage var _baseline_mesh: ArrayMesh = null
@export_storage var _baseline_groups: Dictionary = {}
@export_storage var _active_path: String = ""

var _activate_idx := 0
var _snapshot_paths: PackedStringArray = PackedStringArray([""])
var _applying := false

# Live snapshot blend (tween) state
const _BLEND_SHADER_UNLIT: Shader = preload("res://addons/vertex_studio/shaders/vs_snapshot_blend_unlit.gdshader")
const _BLEST_SHADER_LIT: Shader = preload("res://addons/vertex_studio/shaders/vs_snapshot_blend_lit.gdshader")
var _blend_tween: Tween = null
var _blend_installed := false
var _blend_value := 0.0
var _blend_base_path: String = ""
var _blend_custom_path: String = ""
var _blend_base_surfaces: Array = []
var _blend_custom_surfaces: Array = []
var _blend_materials: Array = []
var _blend_saved_overrides: Array = []
var _blend_src_mats: Array = []
var _blend_saved_aabb := AABB()
var _blend_from_path: String = ""
var _blend_to_path: String = ""

var _blend_is_cpu := false
var _blend_cpu_materials: Array = []


#region Lifecycle


func _enter_tree() -> void:
	refresh_snapshot_options()
	if _baseline_mesh == null and _active_path == "":
		capture_baseline()
	if _active_path != "":
		call_deferred("_apply_snapshot_path", _active_path)


func _validate_property(property: Dictionary) -> void:
	if property.name != "variation":
		return
	refresh_snapshot_options()
	var labels: PackedStringArray = PackedStringArray(["None"])
	for i in range(1, _snapshot_paths.size()):
		labels.append(_snapshot_paths[i].get_file())
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = ",".join(labels)
	property.tooltip = (
		"Apply a variation to the MeshInstance3D, creating a non-destructive "
		+ "different variation of the mesh.")


#endregion Lifecycle


#region Snapshot switching
# ----------------------------------------------------------------
# Snapshot switching
# ----------------------------------------------------------------

func set_active_snapshot(_path: String) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func get_active_snapshot() -> String:
	return _active_path


func get_snapshots_file_paths() -> PackedStringArray:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return PackedStringArray()


func refresh_snapshot_options() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func capture_baseline() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func restore_baseline() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func restore_base_from_original_scene() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _clear_baseline() -> void:
	_baseline_mesh = null
	_baseline_groups = {}


func _set_snapshot_none_silent() -> void:
	if _active_path == "" and _activate_idx == 0:
		return
	_applying = true
	_active_path = ""
	_activate_idx = 0
	notify_property_list_changed()
	_applying = false


func _apply_snapshot_index(_idx: int) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _apply_snapshot_path(_path: String) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _source_scene_context(_mi: MeshInstance3D) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _restore_base_from_scene(_mi: MeshInstance3D) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _load_base_from_scene_file(_ctx: Dictionary) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _is_packed_scene_file(_path: String) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _mesh_instance() -> MeshInstance3D:
	var p := get_parent()
	return p as MeshInstance3D if p is MeshInstance3D else null


func _read_groups_from_mesh(_mi: MeshInstance3D) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _apply_groups_to_mesh(_groups: Dictionary) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


#endregion Snapshot switching


#region Snapshot Tweening in the GPU (EXPERIMENTAL!)

func tween_snapshots(_from_path: String, _to_path: String, _duration: float = 1.0) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func tween_to_snapshot(_to_path: String, _duration: float = 1.0) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func stop_snapshot_blend() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _kill_blend_tween() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _blend_pair_matches(_from_path: String, _to_path: String) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _drive_blend(_start: float, _end: float, _duration: float) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _finish_blend() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _teardown_blend() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _clear_blend_cache() -> void:
	_blend_installed = false
	_blend_value = 0.0
	_blend_base_path = ""
	_blend_custom_path = ""
	_blend_base_surfaces = []
	_blend_custom_surfaces = []
	_blend_materials = []
	_blend_saved_overrides = []
	_blend_src_mats = []
	_blend_saved_aabb = AABB()
	_blend_from_path = ""
	_blend_to_path = ""
	_blend_is_cpu = false
	_blend_cpu_materials = []


func _apply_blend(t: float) -> void:
	_blend_value = t
	for mat in _blend_materials:
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("blend", t)


func _install_gpu_blend(_mi: MeshInstance3D, _from_s: Array, _to_s: Array) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _make_blend_material(src: Variant) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _BLEND_SHADER_UNLIT if blend_material_type == BlendMaterialType.Unlit else _BLEST_SHADER_LIT
	mat.set_shader_parameter("blend", 0.0)
	mat.set_shader_parameter("use_vertex_color", true)
	var tex := _albedo_texture_of(src)
	mat.set_shader_parameter("has_texture", tex != null)
	if tex != null:
		mat.set_shader_parameter("albedo_texture", tex)
	if src is StandardMaterial3D:
		mat.set_shader_parameter("roughness_value", (src as StandardMaterial3D).roughness)
	return mat


func _albedo_texture_of(m: Variant) -> Texture2D:
	if m is StandardMaterial3D:
		return (m as StandardMaterial3D).albedo_texture
	if m is ShaderMaterial:
		var t: Variant = (m as ShaderMaterial).get_shader_parameter("albedo_texture")
		if t is Texture2D:
			return t as Texture2D
	return null


func _pack_v3_custom(_src: Variant, _fallback: PackedVector3Array) -> PackedFloat32Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return PackedFloat32Array()


func _pack_color_custom(_src: Variant, _fallback: PackedColorArray) -> PackedFloat32Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return PackedFloat32Array()


func _blend_union_aabb(_from_s: Array, _to_s: Array) -> AABB:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return AABB()


func _resolve_blend_surfaces(_path: String) -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return []


func _load_snapshot_cached(path: String) -> VSSnapshot:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var res: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return res as VSSnapshot if res is VSSnapshot else null


func _snapshot_groups(_path: String) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


func _snapshot_full_surfaces(_snap: VSSnapshot, _mi: MeshInstance3D) -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return []


func _surfaces_from_mesh(_mesh: Mesh) -> Array:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return []


func _blend_topology_matches(_a: Array, _b: Array) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


#endregion GPU


#region Snapshot Tweening in the CPU (EXPERIMENTAL!)
# ----------------------------------------------------------------
# Snapshot tweening in the CPU (EXPERIMENTAL!)
# ----------------------------------------------------------------

func tween_snapshots_cpu(_from_path: String, _to_path: String, _duration: float = 1.0) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func tween_to_snapshot_cpu(_to_path: String, _duration: float = 1.0) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func stop_snapshot_blend_cpu() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _drive_blend_cpu(_start: float, _end: float, _duration: float) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _finish_blend_cpu() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _apply_blend_cpu(_t: float) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _blend_v3(_a: Variant, _b: Variant, _t: float) -> Variant:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return null


func _blend_norm(_a: Variant, _b: Variant, _t: float) -> Variant:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return null


func _blend_col(_a: Variant, _b: Variant, _t: float) -> Variant:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return null


func _blend_v2(_a: Variant, _b: Variant, _t: float) -> Variant:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return null


#endregion CPU