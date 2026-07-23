@tool
extends RefCounted
class_name VSStore

## Persistent per-mesh data for Vertex Studio (vertex groups, variation/snapshot history,
## original material overrides, etc.). Centralised here so the plugin and `VSRuntime` share one source of truth.
##
## Stored in both node metadata and a project-local config file,
## in order to allow for reconciliation in case of:
## 1. Source file re-syncing
## 2. Instanced scene made local
##
## Format:
## - Node: meta `vs_<field>`
## - File: res://.vertex_studio/scene_data.cfg  [scene_data]  "<scene>::<mesh path>" = {field: value}

const PREFS_PATH := "res://.vertex_studio/scene_data.cfg"
const DIR := "res://.vertex_studio"
const SECTION := "scene_data"
## Node-metadata mirror keys (`vs_<field>`). Metadata TRAVELS WITH THE NODE, so it
## survives Make Local / instancing (where the scene key changes); the file below
## survives inherited-scene re-imports (which wipe metadata). We keep both.
const META_PREFIX := "vs_"

const VGROUPS := "vgroups"
const SNAP_LAST := "snap_last"
const SNAP_HISTORY := "snap_history"
const ORIG_OVERRIDES := "orig_overrides"
const HAS_RUNTIME := "has_runtime"


static func _root(mi: Node) -> Node:
	if mi == null or not is_instance_valid(mi):
		return null
	return mi.owner if mi.owner != null else mi


static func _scene_key(mi: Node) -> String:
	var root := _root(mi)
	if root == null:
		return ""
	var scene: String = root.scene_file_path
	if scene == "":
		return ""
	var mesh_path := "."
	if mi != root:
		if root.is_ancestor_of(mi):
			mesh_path = str(root.get_path_to(mi))
		else:
			mesh_path = str(mi.name)
	return scene + "::" + mesh_path


static func get_field(mi: Node, field: String, default: Variant = null) -> Variant:
	var mk := META_PREFIX + field
	if mi != null and is_instance_valid(mi) and mi.has_meta(mk):
		return mi.get_meta(mk)
	var key := _scene_key(mi)
	if key != "":
		var cfg := ConfigFile.new()
		if cfg.load(PREFS_PATH) == OK:
			var d: Variant = cfg.get_value(SECTION, key, {})
			if d is Dictionary and (d as Dictionary).has(field):
				var v: Variant = (d as Dictionary)[field]
				if mi != null and is_instance_valid(mi):
					mi.set_meta(mk, v)
				return v
	return default


static func set_field(mi: Node, field: String, value: Variant) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var mk := META_PREFIX + field
	if value == null:
		if mi.has_meta(mk):
			mi.remove_meta(mk)
	else:
		mi.set_meta(mk, value)
	if not Engine.is_editor_hint():
		return
	var key := _scene_key(mi)
	if key == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)
	var d: Variant = cfg.get_value(SECTION, key, {})
	if not (d is Dictionary):
		d = {}
	if value == null:
		(d as Dictionary).erase(field)
	else:
		(d as Dictionary)[field] = value
	if (d as Dictionary).is_empty():
		if cfg.has_section_key(SECTION, key):
			cfg.erase_section_key(SECTION, key)
	else:
		cfg.set_value(SECTION, key, d)
	_ensure_dir()
	cfg.save(PREFS_PATH)


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
