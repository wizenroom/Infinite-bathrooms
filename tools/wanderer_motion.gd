extends SceneTree
## Sample each wanderer animation over time and report when the pose actually
## moves - reveals dead "empty frame" spans inside clips.


func _initialize() -> void:
	var inst: Node3D = (load("res://assets/wanderer.glb") as PackedScene).instantiate()
	root.add_child(inst)
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	await process_frame

	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n)
		ap.play(n)
		ap.seek(0.0, true)
		await process_frame
		var prev := _pose(sk)
		var step := 0.04
		var moving_spans: Array = []
		var span_start := -1.0
		var t := step
		while t <= a.length + 0.001:
			ap.seek(minf(t, a.length), true)
			await process_frame
			var cur := _pose(sk)
			var delta := 0.0
			for i in cur.size():
				delta += (cur[i] as Vector3).distance_to(prev[i])
			prev = cur
			var is_moving := delta > 0.01
			if is_moving and span_start < 0.0:
				span_start = t - step
			elif not is_moving and span_start >= 0.0:
				moving_spans.append([span_start, t - step])
				span_start = -1.0
			t += step
		if span_start >= 0.0:
			moving_spans.append([span_start, a.length])
		print(n, " len=", a.length, " moving spans=", moving_spans)
	quit()


func _pose(sk: Skeleton3D) -> Array:
	var out: Array = []
	for i in sk.get_bone_count():
		out.append(sk.get_bone_global_pose(i).origin)
	return out
