class_name TerrainGenerator
extends Node3D
## Noise-based heightmap terrain, regenerated at runtime.
## Swap generate_height() with your own algorithm (WFC, terragen-style erosion, etc.)
## and everything downstream (mesh, collision, spawning) keeps working.

signal terrain_ready

@export var terrain_size: int = 64
@export var cell_size: float = 1.0
@export var height_scale: float = 8.0
@export var noise_seed: int = 0
@export var noise_frequency: float = 0.05

var noise := FastNoiseLite.new()
var _mesh_instance: MeshInstance3D
var _collision_body: StaticBody3D


func _ready() -> void:
	regenerate()


func regenerate(new_seed: int = noise_seed) -> void:
	noise_seed = new_seed
	noise.seed = noise_seed
	noise.frequency = noise_frequency
	noise.fractal_octaves = 4

	_build_mesh()
	terrain_ready.emit()


## Height at world-space (x, z). This is the single source of truth
## used by both the mesh and the spawner.
func get_height(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * height_scale


## Random point on the terrain surface, handy for spawners.
func random_surface_point(rng: RandomNumberGenerator) -> Vector3:
	var half := terrain_size * cell_size * 0.5
	var x := rng.randf_range(-half, half)
	var z := rng.randf_range(-half, half)
	return Vector3(x, get_height(x, z), z)


func _build_mesh() -> void:
	if _mesh_instance:
		_mesh_instance.queue_free()
	if _collision_body:
		_collision_body.queue_free()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := terrain_size * cell_size * 0.5
	for z in terrain_size:
		for x in terrain_size:
			var x0 := x * cell_size - half
			var z0 := z * cell_size - half
			var x1 := x0 + cell_size
			var z1 := z0 + cell_size

			var a := Vector3(x0, get_height(x0, z0), z0)
			var b := Vector3(x1, get_height(x1, z0), z0)
			var c := Vector3(x0, get_height(x0, z1), z1)
			var d := Vector3(x1, get_height(x1, z1), z1)

			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)

			st.add_vertex(b)
			st.add_vertex(d)
			st.add_vertex(c)

	st.generate_normals()

	var mesh := st.commit()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.6, 0.3)
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

	_collision_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	_collision_body.add_child(shape)
	add_child(_collision_body)
