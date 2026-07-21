extends Node3D

var width = 4;
var height = 4;

var builder : MapTemplateBuilder

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
