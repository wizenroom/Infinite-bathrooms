extends Node3D

const RoomType = MapEnums.RoomType

@onready var arrow: MeshInstance3D = $Arrow

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_direction(RoomType.RIGHT)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func set_direction(roomtype: RoomType) -> void:
	match roomtype:
		RoomType.DOWN:
			arrow.rotation_degrees.y = 90
		RoomType.LEFT:
			arrow.rotation_degrees.y = 0
		RoomType.UP:
			arrow.rotation_degrees.y = 270
		RoomType.RIGHT:
			arrow.rotation_degrees.y = 180
