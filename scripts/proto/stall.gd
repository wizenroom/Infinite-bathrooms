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
## OCCUPIED variant; EMPTY/LOOT use VACANT. Every toilet lid is openable.

enum Outcome { HOSTILE, LOOT, FRIENDLY, EMPTY }

signal opened(stall: Stall, outcome: Outcome)

const OCC_CLOSED := preload("res://assets/stall_occupied_closed.glb")
const OCC_OPEN := preload("res://assets/stall_occupied_open.glb")
const VAC_CLOSED := preload("res://assets/stall_vacant_closed.glb")
const VAC_OPEN := preload("res://assets/stall_vacant_open.glb")
const MAN_SCENE := preload("res://assets/man_animated.glb")
const LIGHT_OPEN := preload("res://assets/light_open.glb")
const LIGHT_CLOSED := preload("res://assets/light_closed.glb")

## Baked AABB centers of the sign-light models (cancelled at mount time).
const LIGHT_OPEN_CENTER := Vector3(0.0, 0.2055, -0.0305)
const LIGHT_CLOSED_CENTER := Vector3(0.0, 0.2055, -0.6382)

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

## Merged-mesh cache, one entry per variant (the GLBs are 117 MeshInstances
## each; merging cuts a stall from ~117 draw calls to a handful).
static var _merge_cache := {}

var outcome := Outcome.EMPTY
var is_open := false
## Each throne only grants relief (or horror) once.
var seat_used := false
## Lid state: auto-opened on vacant reveals, hand-lifted (E) elsewhere.
var lid_open := false
## Set on the first knock: re-opening a closed-again stall has no surprises.
var resolved := false

var _model: Node3D = null
var _lid: MeshInstance3D = null
var _lid_pivot: Node3D = null
var _door_collider: StaticBody3D
var _occupant: Node3D = null


func setup(p_outcome: Outcome, _rng: RandomNumberGenerator) -> void:
	outcome = p_outcome
	_build_collision()
	_mount_model(false)

	# Sign light above the door (OPEN/CLOSED model) plus a matching glow.
	var claims_occupied := _has_occupant()
	var sign_scene: PackedScene = LIGHT_CLOSED if claims_occupied else LIGHT_OPEN
	var sign_center: Vector3 = LIGHT_CLOSED_CENTER if claims_occupied else LIGHT_OPEN_CENTER
	var sign_wrap := Node3D.new()
	sign_wrap.position = Vector3(0, STALL_HEIGHT + 0.18, -0.06)
	sign_wrap.scale = Vector3(0.45, 0.45, 0.45)
	add_child(sign_wrap)
	var sign_inst: Node3D = sign_scene.instantiate()
	sign_inst.position = -sign_center
	sign_wrap.add_child(sign_inst)

	var ind := OmniLight3D.new()
	ind.light_color = Color(0.9, 0.15, 0.1) if claims_occupied else Color(0.15, 0.9, 0.3)
	ind.light_energy = 0.5
	ind.omni_range = 1.2
	ind.position = Vector3(0, 2.1, -0.25)
	# Dozens of stalls are alive at once; fade the glow out with distance so
	# far ones stop costing light-pass time.
	ind.distance_fade_enabled = true
	ind.distance_fade_begin = 18.0
	ind.distance_fade_length = 6.0
	add_child(ind)


func knock() -> void:
	if is_open:
		return
	is_open = true
	if _door_collider:
		_door_collider.queue_free()
		_door_collider = null
	_mount_model(true)

	if resolved:
		# Second visit: whatever was inside already happened.
		return
	resolved = true

	if outcome == Outcome.HOSTILE or outcome == Outcome.FRIENDLY:
		_seat_occupant()
	if not _has_occupant():
		_open_lid()

	opened.emit(self, outcome)


## Push an open door shut again (only when nobody is on the throne).
func close() -> void:
	if not is_open or _occupant != null:
		return
	is_open = false
	lid_open = false
	_mount_model(false)
	_build_door_collider()


func _has_occupant() -> bool:
	return outcome == Outcome.HOSTILE or outcome == Outcome.FRIENDLY


## World position just inside the stall (enemy spawn / win check).
func interior_point() -> Vector3:
	return to_global(Vector3(0, 0, 0.6))


## Where the player ends up when sitting down (on the toilet, facing the door).
func seat_point() -> Vector3:
	return to_global(Vector3(0, 0.05, 1.0))


## An open stall with nobody on the throne can be interacted with (lid/sit).
func can_sit() -> bool:
	return is_open and _occupant == null


## Someone is on the throne (and about to be very upset if you touch it).
func has_seated_occupant() -> bool:
	return is_open and _occupant != null


## Lift the lid by hand (stalls that revealed an occupant keep it down).
func open_seat() -> void:
	_open_lid()


## Remove the sitting occupant (the manager replaces hostiles with live enemies).
func clear_occupant() -> void:
	if _occupant:
		_occupant.queue_free()
		_occupant = null


func _mount_model(open: bool) -> void:
	if _model:
		_model.queue_free()
	if _lid_pivot:
		# The lifted lid was reparented out of _model; clean it up too.
		_lid_pivot.queue_free()
		_lid_pivot = null

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

	if not _merge_cache.has(key):
		# The lid stays a separate part so it can swing open / turn gold.
		_merge_cache[key] = MeshMerge.merge_scene(scene, LID_SIZE)
	var data: Dictionary = _merge_cache[key]

	var holder := Node3D.new()
	holder.position.x = -MODEL_X_CENTER[key]
	_model.add_child(holder)

	var mi := MeshInstance3D.new()
	mi.mesh = data["mesh"]
	holder.add_child(mi)

	_lid = null
	for part in data["parts"]:
		_lid = MeshInstance3D.new()
		_lid.mesh = part["mesh"]
		_lid.transform = part["xform"]
		holder.add_child(_lid)


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


## Swing the toilet lid up around its rear (tank-side) edge. The lid is a
## separate mesh in the GLB, found by its AABB size signature; we wrap it in
## a pivot placed on the hinge edge and rotate that.
func _open_lid() -> void:
	if not _lid or lid_open:
		return
	lid_open = true
	# Lid bounds in stall-local space (world AABB axes would be wrong
	# because the manager rotates the whole stall).
	var to_stall: Transform3D = global_transform.affine_inverse() * _lid.global_transform
	var box: AABB = to_stall * _lid.mesh.get_aabb()

	var hinge := box.get_center()
	hinge.z = box.end.z - 0.02  # rear edge, next to the tank

	_lid_pivot = Node3D.new()
	add_child(_lid_pivot)
	_lid_pivot.position = hinge
	_lid.reparent(_lid_pivot)
	# Swing up over ~0.25s instead of teleporting open - reads as a real lid.
	var tw := create_tween()
	tw.tween_property(_lid_pivot, "rotation:x", deg_to_rad(100.0), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_collision() -> void:
	var walls := StaticBody3D.new()
	add_child(walls)
	var half_w := STALL_WIDTH / 2.0
	_coll_box(walls, Vector3(0.08, STALL_HEIGHT, STALL_DEPTH), Vector3(-half_w, STALL_HEIGHT / 2.0, STALL_DEPTH / 2.0))
	_coll_box(walls, Vector3(0.08, STALL_HEIGHT, STALL_DEPTH), Vector3(half_w, STALL_HEIGHT / 2.0, STALL_DEPTH / 2.0))
	_coll_box(walls, Vector3(STALL_WIDTH, STALL_HEIGHT, 0.08), Vector3(0, STALL_HEIGHT / 2.0, STALL_DEPTH))
	_build_door_collider()


func _build_door_collider() -> void:
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
