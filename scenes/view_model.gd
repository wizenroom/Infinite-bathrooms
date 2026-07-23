class_name ViewModelComponent
extends Node3D

const DEFAULT_Z := 0.0
const MAX_Z := -0.5

@onready var normalized_node: Node3D = $NormalizedNode


func move_forward(time: float) -> void:
	var tween := create_tween()

	tween.tween_property(
		normalized_node,
		"position:z",
		MAX_Z,
		time
	)

	await tween.finished


func move_backward(time: float) -> void:
	var tween := create_tween()

	tween.tween_property(
		normalized_node,
		"position:z",
		DEFAULT_Z,
		time
	)

	await tween.finished


func thrust_with_times(push_time: float, pull_time: float) -> void:
	var tween := create_tween()

	tween.tween_property(
		normalized_node,
		"position:z",
		MAX_Z,
		push_time
	)

	tween.tween_property(
		normalized_node,
		"position:z",
		DEFAULT_Z,
		pull_time
	)

	await tween.finished


func thrust(attack_time: float, attack_ratio: float = 0.5) -> void:
	var push_time := attack_time * attack_ratio
	var pull_time := attack_time - push_time

	await thrust_with_times(push_time, pull_time)
