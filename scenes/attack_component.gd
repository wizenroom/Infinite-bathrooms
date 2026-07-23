class_name AttackComponent
extends Node

signal attack_started(data: AttackData)
signal attack_finished(data: AttackData)

@export var punch: AttackData
@export var view_model: ViewModelComponent

const AttackType = AttackEnums.Type
@onready var hitboxes = {
	AttackType.Punch : $PunchHitbox
}

var _is_attacking := false
var _can_attack := true

func attack() -> bool:
	if !_can_attack:
		return false

	if punch == null:
		push_warning("No Punch AttackData assigned.")
		return false

	_can_attack = false
	_is_attacking = true
	
	for enemy in get_hit(AttackType.Punch):
		enemy.damage(punch.damage)

	attack_started.emit(punch)
	view_model.thrust(punch.length)

	await get_tree().create_timer(punch.length).timeout

	_is_attacking = false

	attack_finished.emit(punch)

	await get_tree().create_timer(punch.cooldown).timeout

	_can_attack = true

	return true
	

func is_attacking() -> bool:
	return _is_attacking


func can_attack() -> bool:
	return _can_attack
	
func get_hit(type: AttackType) -> Array[Node3D]:
	var hitbox := get_hitbox(type)
	var hits: Array[Node3D] = []

	for body in hitbox.get_overlapping_bodies():
		if is_enemy(body):
			hits.append(body)

	return hits


func get_hitbox(type: AttackType) -> Area3D:
	return hitboxes[type]


func is_enemy(body: Node) -> bool:
	return body is Enemy
