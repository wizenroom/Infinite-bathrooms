class_name FlickerLight
extends OmniLight3D
## Fluorescent tube behavior: constant subtle hum-jitter plus occasional
## full brownout stutters.

var base_energy := 1.2
var _time := 0.0
var _dropout := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_time = _rng.randf() * 10.0


func _process(delta: float) -> void:
	_time += delta
	if _dropout > 0.0:
		_dropout -= delta
		light_energy = base_energy * (0.05 if fmod(_time, 0.08) < 0.04 else 0.5)
		return
	if _rng.randf() < 0.002:
		_dropout = _rng.randf_range(0.2, 0.9)
		return
	light_energy = base_energy * (0.92 + 0.08 * sin(_time * 47.0) * sin(_time * 13.0))
