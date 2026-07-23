class_name ViewModelComponent
extends Node3D

const DEFAULT_Z := 0.0
const MAX_Z := -0.5

@export var move_time := 0.1
@export var punch_time := 0.08


enum MoveDirection {
	NONE,
	FORWARD,
	BACKWARD,
}


@onready var normalized_node: Node3D = $NormalizedNode


var is_moving := false
var is_punching := false
var move_direction := MoveDirection.NONE


func can_accept_input() -> bool:
	return not is_moving and not is_punching


func at_default() -> bool:
	return is_equal_approx(normalized_node.position.z, DEFAULT_Z)


func at_max() -> bool:
	return is_equal_approx(normalized_node.position.z, MAX_Z)


func move_forward(skip:bool = false) -> void:
	if not(skip):
		if not can_accept_input():
			return
	if at_max():
		return

	is_moving = true
	move_direction = MoveDirection.FORWARD

	var tween := create_tween()

	tween.tween_property(
		normalized_node,
		"position:z",
		MAX_Z,
		move_time
	)

	await tween.finished

	is_moving = false
	move_direction = MoveDirection.NONE


func move_backward(skip:bool = false) -> void:
	if not(skip):
		if not can_accept_input():
			return
	if at_default():
		return

	is_moving = true
	move_direction = MoveDirection.BACKWARD

	var tween := create_tween()

	tween.tween_property(
		normalized_node,
		"position:z",
		DEFAULT_Z,
		move_time
	)

	await tween.finished

	is_moving = false
	move_direction = MoveDirection.NONE


func punch(skip:bool = false) -> void:
	if not(skip):
		if not can_accept_input():
			return

	is_punching = true

	var tween := create_tween()

	tween.tween_property(
		normalized_node,
		"position:z",
		MAX_Z,
		punch_time
	)

	tween.tween_property(
		normalized_node,
		"position:z",
		DEFAULT_Z,
		punch_time
	)

	await tween.finished

	is_punching = false
