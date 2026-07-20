extends Node3D
## Press R to regenerate the terrain with a new seed (jam-friendly iteration).

@onready var terrain: TerrainGenerator = $Terrain


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		terrain.regenerate(randi())
