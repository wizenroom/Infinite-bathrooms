# map_template_builder.gd
extends RefCounted
class_name MapTemplateBuilder

var Map_Template: Array
var width: int
var height: int

var currentX := 0
var currentY := 0

const DirectionType = MapEnums.DirectionType
const RoomType = MapEnums.RoomType

var lastdir: DirectionType
var dir: DirectionType

func _init(map_width: int, map_height: int):
	width = map_width
	height = map_height
	Map_Template = make_grid()


func make_grid(default_value = null) -> Array:
	var grid = []

	for x in width:
		var column = []
		for y in height:
			column.append(default_value)
		grid.append(column)
	
	return grid


func exceed_map_bound(x: int, y: int) -> bool:
	return x < 0 or x >= width or y < 0 or y >= height


func is_inside_map_bound() -> bool:
	return not exceed_map_bound(currentX, currentY)


func pick_random_direction() -> DirectionType:
	return [DirectionType.RIGHT, DirectionType.LEFT].pick_random()
	
func tryRandomDown() -> DirectionType:
	return [lastdir,lastdir,lastdir, DirectionType.DOWN].pick_random()


func go_down():
	assert(is_inside_map_bound(), "Not inside when calling")

	Map_Template[currentX][currentY] = RoomType.DOWN

	currentY += 1
	lastdir = DirectionType.DOWN

	assert(is_inside_map_bound(), "Tried to go out of bounds")


func go_left():
	assert(is_inside_map_bound(), "Not inside when calling")

	Map_Template[currentX][currentY] = RoomType.LEFT

	currentX -= 1
	lastdir = DirectionType.LEFT

	assert(is_inside_map_bound(), "Tried to go out of bounds")

func go_right():
	assert(is_inside_map_bound(), "Not inside when calling")

	Map_Template[currentX][currentY] = RoomType.RIGHT

	currentX += 1
	lastdir = DirectionType.RIGHT

	assert(is_inside_map_bound(), "Tried to go out of bounds")


func can_go_right() -> bool:
	return not exceed_map_bound(currentX + 1, currentY)


func can_go_left() -> bool:
	return not exceed_map_bound(currentX - 1, currentY)


func can_go_down() -> bool:
	return not exceed_map_bound(currentX, currentY + 1)


func build():
	var start = randi_range(0, width - 1)
	var end = randi_range(0, width - 1)

	currentX = start
	currentY = 0

	lastdir = pick_random_direction()

	while is_inside_map_bound():
		
		if lastdir == DirectionType.DOWN:
			dir = pick_random_direction()
		else:
			dir = tryRandomDown()

		match dir:
			DirectionType.LEFT:
				if can_go_left():
					go_left()
				elif can_go_down():
					go_down()
				else:
					Map_Template[currentX][currentY] = RoomType.DOWN
					break

			DirectionType.RIGHT:
				if can_go_right():
					go_right()
				elif can_go_down():
					go_down()
				else:
					Map_Template[currentX][currentY] = RoomType.DOWN
					break
			
			DirectionType.DOWN:
				if can_go_down():
					go_down()
				else:
					Map_Template[currentX][currentY] = RoomType.DOWN
					break

			_:
				assert(false, "IMPOSSIBLE DIRECTION TYPE")

	for x in width:
		for y in height:
			if Map_Template[x][y] == null:
				Map_Template[x][y] = RoomType.FILLER
