extends Node
## Scene root: renders the game world inside a low-resolution SubViewport
## (nearest-neighbor upscale) with the retro post shader on top.
## The HUD is parented here, outside the pixelation, so text stays readable.

const BATHROOM_SCENE := preload("res://scenes/bathroom.tscn")
const RETRO_SHADER := preload("res://shaders/retro.gdshader")

const SHRINK := 4  # render at 1/4 resolution


func _ready() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = SHRINK
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = RETRO_SHADER
	mat.set_shader_parameter("pixel_scale", float(SHRINK))
	container.material = mat
	add_child(container)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	container.add_child(vp)

	var world: Node3D = BATHROOM_SCENE.instantiate()
	world.hud_parent = self
	vp.add_child(world)
