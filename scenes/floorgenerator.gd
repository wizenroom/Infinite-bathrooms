extends Node3D

const FLOOR_TILE = preload("res://scenes/base_objects/floor_tile.tscn")
const PROGRESS_TILE = preload("res://scenes/base_objects/progress_tile.tscn")

@export var width := 4
@export var height := 4
@export var tile_size := 1.0
@export var tile_scale := 2.0

var Map_Template := make_grid(width, height)
var Map_Instances := make_grid(width, height)

enum RoomType {
	FILLER,
    UP,
    RIGHT,
    DOWN,
    LEFT
}

func make_grid(width: int, height: int, default_value = null) -> Array:
	var grid = []

	for y in height:
		var row = []
		for x in width:
			row.append(default_value)
		grid.append(row)

	return grid

func build_map_template():
	pass

func _ready():
	for z in height:
		for x in width:
			var tile = FLOOR_TILE.instantiate()
			tile.position = Vector3(
				x * tile_size * tile_scale,
				0,
				z * tile_size * tile_scale
			)
			tile.scale = Vector3.ONE * tile_scale
			add_child(tile)
