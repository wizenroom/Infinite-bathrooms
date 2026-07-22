extends Node3D
## Press R to regenerate the terrain with a new seed (jam-friendly iteration).

@onready var terrain: TerrainGenerator = $Terrain


func _unhandled_input(event: InputEvent) -> void:
	pass
