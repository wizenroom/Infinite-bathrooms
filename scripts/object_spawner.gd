class_name ObjectSpawner
extends Node3D
## Spawns objects on the terrain surface once it has been generated.
## Assign spawn_scene in the inspector, or leave empty to get
## placeholder boxes so you can see spawning working immediately.

@export var terrain: TerrainGenerator
@export var spawn_scene: PackedScene
@export var spawn_count: int = 30
@export var spawn_seed: int = 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if terrain:
		terrain.terrain_ready.connect(_on_terrain_ready)


func _on_terrain_ready() -> void:
	clear_spawned()
	_rng.seed = spawn_seed if spawn_seed != 0 else randi()

	for i in spawn_count:
		var pos := terrain.random_surface_point(_rng)
		var obj := _make_object()
		add_child(obj)
		obj.global_position = pos


func clear_spawned() -> void:
	for child in get_children():
		child.queue_free()


func _make_object() -> Node3D:
	if spawn_scene:
		return spawn_scene.instantiate()

	# Placeholder: a small colored box.
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	box.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(_rng.randf(), 0.7, 0.9)
	box.material_override = mat
	box.position.y += 0.25
	return box
