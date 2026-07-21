extends SceneTree
## Dev tool: dump the crawler scene tree with transforms.


func _initialize() -> void:
	var model: Node3D = (load("res://assets/crawler.glb") as PackedScene).instantiate()
	root.add_child(model)
	_dump(model, 0)
	quit()


func _dump(node: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		line += " pos=%s rot=%s scale=%s" % [node.position, node.rotation_degrees, node.scale]
	if node is MeshInstance3D:
		line += " skel=" + str(node.get("skeleton"))
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)
