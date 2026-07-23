class_name AttackData
extends Resource

@export_group("Animation")
@export var action: AttackEnums.Type

@export_group("Timing")
@export var length := 0.2
@export var cooldown := 0.5

@export_group("Stats")
@export var damage := 10.0
@export var range := 2.0

@export_group("HitboxName")
@export var Hitbox : AttackEnums.Type
