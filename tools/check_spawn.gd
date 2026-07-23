extends SceneTree


func _initialize() -> void:
	var w = load("res://scenes/bathroom.tscn").instantiate()
	root.add_child(w)
	for i in 4:
		await process_frame
	print("IMMEDIATE player=", w.player.global_position)
	for i in 30:
		await process_frame
	print("T+0.5ish player=", w.player.global_position)
	for e in w.get_tree().get_nodes_in_group("enemies"):
		print("  enemy=", e.global_position, " neutral=", e.get("neutral"))
	for i in 90:
		await process_frame
	print("T+2ish player=", w.player.global_position)
	print("  player class=", w.player.get_class(), " script=", w.player.get_script().resource_path)
	quit()
