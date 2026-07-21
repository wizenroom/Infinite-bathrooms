extends Node3D

var width = 10;
var height = 10;

var builder : MapTemplateBuilder

const RoomType = MapEnums.RoomType

const TileScene = preload("res://scenes/base_objects/floor_tile.tscn")
const ProgressTileScene = preload("res://scenes/base_objects/progress_tile.tscn")

const TILE_SIZE := 1

func build_rooms():
	for x in width:
		for y in height:
			var room = builder.Map_Template[x][y]

			var tile: Node3D

			if room == RoomType.FILLER:
				tile = TileScene.instantiate()
				add_child(tile)
			else:
				tile = ProgressTileScene.instantiate()
				add_child(tile)
				tile.set_direction(room)

			tile.position = Vector3(
				x * TILE_SIZE,
				0,
				y * TILE_SIZE
			)

			

func build_map_template() -> MapTemplateBuilder:
	var builder = MapTemplateBuilder.new(
		width,
		height
	)
	builder.build()
	return builder

func _ready():
	builder = build_map_template()
	print(builder.Map_Template)
	build_rooms()
