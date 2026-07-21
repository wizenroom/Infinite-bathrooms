class_name Stall
extends Node3D
## One bathroom stall using the real stall models. The root sits at the
## door plane; the door faces local -Z (toward the corridor once the
## manager rotates the stall). Interior spans local z 0..1.9.
##
## The four GLB variants (occupied/vacant x closed/open) were exported
## side by side from one Blender scene, so each carries a baked X offset
## that we cancel out. "Opening" the door = swapping closed -> open model.
##
## Signs on the models do the signaling: stalls with a man inside use the
## OCCUPIED variant, and EMPTY/LOOT/FREE use the VACANT variant - so
## "vacant" stalls are the gamble worth taking (gross, loot, or the prize).

enum Outcome { HOSTILE, LOOT, FRIENDLY, EMPTY, FREE }

signal opened(stall: Stall, outcome: Outcome)

const OCC_CLOSED := preload("res://assets/stall_occupied_closed.glb")
const OCC_OPEN := preload("res://assets/stall_occupied_open.glb")
const VAC_CLOSED := preload("res://assets/stall_vacant_closed.glb")
const VAC_OPEN := preload("res://assets/stall_vacant_open.glb")
const MAN_SCENE := preload("res://assets/man_animated.glb")

## Baked export X centers per variant (stalls sat side by side in Blender),
## measured from merged world AABBs.
const MODEL_X_CENTER := {
	"occ_closed": 3.060,
	"occ_open": 6.689,
	"vac_closed": -0.133,
	"vac_open": -3.919,
}
## Distance from model origin to the door hinge plane (+Z in model space).
const MODEL_FRONT_Z := 0.42
## The toilet lid mesh, identified by its mesh AABB size signature.
const LID_SIZE := Vector3(0.39523, 0.492031, 0.058429)

const STALL_WIDTH := 1.29
const STALL_DEPTH := 1.57
const STALL_HEIGHT := 2.29

var outcome := Outcome.EMPTY
var is_open := false

var _model: Node3D = null
var _door_collider: StaticBody3D
var _occupant: Node3D = null


func setup(p_outcome: Outcome, _rng: RandomNumberGenerator) -> void:
	outcome = p_outcome
	_build_collision()
	_mount_model(false)

	# Indicator light above the stall, matching the model's sign.
	var claims_occupied := _has_occupant()
	var ind := OmniLight3D.new()
	ind.light_color = Color(0.9, 0.15, 0.1) if claims_occupied else Color(0.15, 0.9, 0.3)
	ind.light_energy = 0.5
	ind.omni_range = 1.2
	ind.position = Vector3(0, 2.1, -0.25)
	add_child(ind)


func knock() -> void:
	if is_open:
		return
	is_open = true
	_door_collider.queue_free()
	_mount_model(true)

	if outcome == Outcome.HOSTILE or outcome == Outcome.FRIENDLY:
		_seat_occupant()
	if outcome == Outcome.FREE:
		_bless_the_throne()
	if not _has_occupant():
		_open_lid()

	opened.emit(self, outcome)


func _has_occupant() -> bool:
	return outcome == Outcome.HOSTILE or outcome == Outcome.FRIENDLY


## World position just inside the stall (enemy spawn / win check).
func interior_point() -> Vector3:
	return to_global(Vector3(0, 0, 0.6))


## Remove the sitting occupant (the manager replaces hostiles with live enemies).
func clear_occupant() -> void:
	if _occupant:
		_occupant.queue_free()
		_occupant = null


func _mount_model(open: bool) -> void:
	if _model:
		_model.queue_free()

	var key: String
	var scene: PackedScene
	if _has_occupant():
		key = "occ_open" if open else "occ_closed"
		scene = OCC_OPEN if open else OCC_CLOSED
	else:
		key = "vac_open" if open else "vac_closed"
		scene = VAC_OPEN if open else VAC_CLOSED

	_model = Node3D.new()
	_model.rotation.y = PI  # model front is +Z; our door faces -Z
	_model.position.z = MODEL_FRONT_Z  # door hinge plane lands on local z=0
	add_child(_model)

	var inst: Node3D = scene.instantiate()
	inst.position.x = -MODEL_X_CENTER[key]
	_model.add_child(inst)


func _seat_occupant() -> void:
	_occupant = MAN_SCENE.instantiate()
	_occupant.rotation.y = PI  # face the door
	_occupant.position = Vector3(0, 0.35, 0.95)
	add_child(_occupant)
	var anims := _occupant.find_children("*", "AnimationPlayer", true, false)
	if anims.size() > 0:
		var ap: AnimationPlayer = anims[0]
		if ap.has_animation("Sit"):
			ap.play("Sit")
			ap.advance(ap.get_animation("Sit").length - 0.02)


## The free stall: golden light and a glowing lid (found by mesh signature).
func _bless_the_throne() -> void:
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.3)
	glow.light_energy = 2.2
	glow.omni_range = 2.8
	glow.position = Vector3(0, 1.5, 1.0)
	add_child(glow)

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.85, 0.3)
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.8, 0.2)
	gold.emission_energy_multiplier = 1.5
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var s: Vector3 = mi.mesh.get_aabb().size
		if s.distance_to(LID_SIZE) < 0.03:
			mi.material_override = gold


## Swing the toilet lid up around its rear (tank-side) edge. The lid is a
## separate mesh in the GLB, found by its AABB size signature; we wrap it in
## a pivot placed on the hinge edge and rotate that.
func _open_lid() -> void:
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		if mi.mesh.get_aabb().size.distance_to(LID_SIZE) > 0.03:
			continue

		# Lid bounds in stall-local space (world AABB axes would be wrong
		# because the manager rotates the whole stall).
		var to_stall: Transform3D = global_transform.affine_inverse() * mi.global_transform
		var box: AABB = to_stall * mi.mesh.get_aabb()

		var hinge := box.get_center()
		hinge.z = box.end.z - 0.02  # rear edge, next to the tank

		var pivot := Node3D.new()
		add_child(pivot)
		pivot.position = hinge
		mi.reparent(pivot)
		pivot.rotation.x = deg_to_rad(100.0)
		return


func _build_collision() -> void:
	var walls := StaticBody3D.new()
	add_child(walls)
	var half_w := STALL_WIDTH / 2.0
	_coll_box(walls, Vector3(0.08, STALL_HEIGHT, STALL_DEPTH), Vector3(-half_w, STALL_HEIGHT / 2.0, STALL_DEPTH / 2.0))
	_coll_box(walls, Vector3(0.08, STALL_HEIGHT, STALL_DEPTH), Vector3(half_w, STALL_HEIGHT / 2.0, STALL_DEPTH / 2.0))
	_coll_box(walls, Vector3(STALL_WIDTH, STALL_HEIGHT, 0.08), Vector3(0, STALL_HEIGHT / 2.0, STALL_DEPTH))

	_door_collider = StaticBody3D.new()
	add_child(_door_collider)
	_coll_box(_door_collider, Vector3(STALL_WIDTH, STALL_HEIGHT, 0.08), Vector3(0, STALL_HEIGHT / 2.0, 0))


func _coll_box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)
