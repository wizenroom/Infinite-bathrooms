extends Node

class_name TileLibrary

const TileType = MapEnums.TileType

func get_random_tile(tile_type: TileType) -> Node:
	var loader: Node
	
	
#	GET THE TYPE
	match tile_type:
		TileType.DOWN:
			loader = $LoaderDown
		TileType.STRAIGHTTHROUGH:
			loader = $LoaderStraightThrough

	
	if loader.get_child_count() == 0:
		push_error("Loader has no tiles.")
		return null

	#PICK RANDOM
	return loader.get_children().pick_random().duplicate()
