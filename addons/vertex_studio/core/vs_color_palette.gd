@tool
extends Resource
class_name VSColorPalette

## Just like Godot's own `ColorPalette`, a Resource with a `colors` `PackedColorArray`.
## Since `ColorPalette` was added to Godot 4.4, this makes
## it possible to use the resource in Godot versions prior to 4.4.
## TODO: Remove this and use `ColorPalette` directly when versions prior to 4.4 are too old to be supported

@export var colors: PackedColorArray = PackedColorArray()


static func has_native() -> bool:
	return ClassDB.class_exists("ColorPalette")


static func create(cols: PackedColorArray) -> Resource:
	if has_native():
		var pal: Resource = ClassDB.instantiate("ColorPalette")
		pal.set("colors", cols)
		return pal
	var pal := VSColorPalette.new()
	pal.colors = cols
	return pal


static func colors_from(res: Variant) -> PackedColorArray:
	if res == null or not (res is Resource):
		return PackedColorArray()
	if has_native() and res.get_class() == "ColorPalette":
		var native = res.get("colors")
		if native is PackedColorArray:
			return native
	if res is VSColorPalette:
		return (res as VSColorPalette).colors
	if "colors" in res and res.colors is PackedColorArray:
		return res.colors
	return PackedColorArray()
