class_name Stall
extends Node3D
## One bathroom stall. The root sits at the door plane; the door faces
## local -Z. What's inside is decided at generation time (the "spawner
## decides what answers the knock" mechanic).
##
## Readable signals for the player:
##  - Indicator light above the door: red = occupied (hostile), green = maybe
##    safe. 15% of indicators lie.
##  - Feet under the door: usually means a hostile occupant.

enum Outcome { HOSTILE, LOOT, FRIENDLY, EMPTY, FREE }

signal opened(stall: Stall, outcome: Outcome)

const TOILET_SCENE := preload("res://assets/toilet.glb")

const WALL_COLOR := Color(0.16, 0.45, 0.42)
const DOOR_COLOR := Color(0.12, 0.36, 0.34)

var outcome := Outcome.EMPTY
var is_open := false
var indicator_lies := false

var _door_pivot: Node3D


func setup(p_outcome: Outcome, rng: RandomNumberGenerator) -> void:
	outcome = p_outcome
	indicator_lies = rng.randf() < 0.15
	_build(rng)


func knock() -> void:
	if is_open:
		return
	is_open = true
	var tw := create_tween()
	tw.tween_property(_door_pivot, "rotation:y", deg_to_rad(-115.0), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	opened.emit(self, outcome)


## World position just inside the stall (used for the win check).
func interior_point() -> Vector3:
	return to_global(Vector3(0, 0, 1.0))


func _build(rng: RandomNumberGenerator) -> void:
	var walls := StaticBody3D.new()
	add_child(walls)

	_solid_box(walls, Vector3(2.1, 2.4, 0.1), Vector3(0, 1.2, 2.0), WALL_COLOR)   # back
	_solid_box(walls, Vector3(0.1, 2.4, 2.0), Vector3(-1.0, 1.2, 1.0), WALL_COLOR) # left
	_solid_box(walls, Vector3(0.1, 2.4, 2.0), Vector3(1.0, 1.2, 1.0), WALL_COLOR)  # right

	# Door on a pivot so it can swing open.
	_door_pivot = Node3D.new()
	_door_pivot.position = Vector3(-0.85, 0, 0)
	add_child(_door_pivot)

	var door_body := StaticBody3D.new()
	_door_pivot.add_child(door_body)
	_solid_box(door_body, Vector3(1.6, 2.0, 0.07), Vector3(0.85, 1.3, 0), DOOR_COLOR)

	# Indicator light above the door.
	var shows_occupied := outcome == Outcome.HOSTILE
	if indicator_lies:
		shows_occupied = not shows_occupied
	var ind := MeshInstance3D.new()
	var ind_mesh := BoxMesh.new()
	ind_mesh.size = Vector3(0.18, 0.18, 0.08)
	ind.mesh = ind_mesh
	ind.position = Vector3(0, 2.15, -0.08)
	var ind_mat := StandardMaterial3D.new()
	var ind_color := Color(0.9, 0.15, 0.1) if shows_occupied else Color(0.15, 0.9, 0.3)
	ind_mat.albedo_color = ind_color
	ind_mat.emission_enabled = true
	ind_mat.emission = ind_color
	ind_mat.emission_energy_multiplier = 1.6
	ind.material_override = ind_mat
	add_child(ind)

	# Feet under the door for most hostiles.
	if outcome == Outcome.HOSTILE and rng.randf() < 0.85:
		for x_off in [-0.2, 0.2]:
			var foot := MeshInstance3D.new()
			var foot_mesh := BoxMesh.new()
			foot_mesh.size = Vector3(0.22, 0.14, 0.45)
			foot.mesh = foot_mesh
			foot.position = Vector3(x_off, 0.07, 0.35)
			var foot_mat := StandardMaterial3D.new()
			foot_mat.albedo_color = Color(0.15, 0.1, 0.08)
			foot.material_override = foot_mat
			add_child(foot)

	# The porcelain itself (model AABB is 2x2x2 centered at origin).
	var toilet: Node3D = TOILET_SCENE.instantiate()
	var s := 0.45
	toilet.scale = Vector3(s, s, s)
	toilet.position = Vector3(0, s, 1.5)
	toilet.rotation.y = PI  # face the door
	add_child(toilet)

	if outcome == Outcome.FREE:
		# Golden halo so the prize reads instantly when the door opens.
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.85, 0.3)
		glow.light_energy = 2.0
		glow.omni_range = 2.5
		glow.position = Vector3(0, 1.4, 1.4)
		add_child(glow)


func _solid_box(body: StaticBody3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_inst.mesh = mesh
	mesh_inst.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)
