extends Node3D

@onready var arrow: MeshInstance3D = $Arrow

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func set_direction(direction: Vector2i) -> void:
	match direction:
		Vector2i.UP:
			arrow.rotation_degrees.y = 0
		Vector2i.RIGHT:
			arrow.rotation_degrees.y = 90
		Vector2i.DOWN:
			arrow.rotation_degrees.y = 180
		Vector2i.LEFT:
			arrow.rotation_degrees.y = 270
			
