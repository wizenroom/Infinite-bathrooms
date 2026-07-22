extends Node3D

var width = 5;
var height = 5;

var builder : MapTemplateBuilder

const RoomType = MapEnums.RoomType

const TileScene = preload("res://scenes/base_objects/floor_tile.tscn")
const ProgressTileScene = preload("res://scenes/base_objects/progress_tile.tscn")
const TILE_LIBRARY_SCENE = preload("res://scenes/floors/tile_library.tscn")

const TILE_SIZE := 50

var tile_library : TileLibrary
const tiletype = MapEnums.TileType

func build_rooms():
	for x in width:
		for y in height:
			var room = builder.Map_Template[x][y]

			var tile: Node3D

			if room == RoomType.FILLER:
				tile = tile_library.get_random_tile(tiletype.STRAIGHTTHROUGH)
				add_child(tile)
			elif room == RoomType.DOWN:
				tile = tile_library.get_random_tile(tiletype.DOWN)
				add_child(tile)
			else:
				tile = tile_library.get_random_tile(tiletype.STRAIGHTTHROUGH)
				add_child(tile)
				#tile.set_direction(room)
			
			tile.scale = Vector3i.ONE * TILE_SIZE
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
	tile_library = TILE_LIBRARY_SCENE.instantiate()
	builder = build_map_template()
	print(builder.Map_Template)
	build_rooms()
	
