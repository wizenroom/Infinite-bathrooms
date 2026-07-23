class_name Utils

extends RefCounted

static func clamp01(value: float) -> float:
	return clamp(value, 0.0, 1.0)


static func random_sign() -> int:
	return 1 if randf() > 0.5 else -1


static func wait(seconds: float) -> void:
	await Engine.get_main_loop().create_timer(seconds).timeout
