class_name Enemy
extends CharacterBody3D

@export var max_health := 100.0

var health := max_health


func _ready() -> void:
	health = max_health


func damage(amount: float) -> void:
	health -= amount

	print("Enemy took ", amount, " damage. Health: ", health)

	if health <= 0.0:
		die()


func die() -> void:
	queue_free()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()
