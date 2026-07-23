class_name FlickerLight
extends OmniLight3D
## Fluorescent tube behavior: constant subtle hum-jitter plus occasional
## full brownout stutters. The Rush event drives every tube at once through
## the "flicker_lights" group: `panic` strobes, `blackout` kills them dead.

var base_energy := 1.2
## Rush incoming: violent full-corridor strobe.
var panic := false
## Rush passing: pitch black.
var blackout := false
var _time := 0.0
var _dropout := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("flicker_lights")
	_rng.randomize()
	_time = _rng.randf() * 10.0


func _process(delta: float) -> void:
	_time += delta
	if blackout:
		light_energy = 0.0
		return
	if panic:
		light_energy = base_energy * (1.7 if fmod(_time, 0.09) < 0.045 else 0.03)
		return
	if _dropout > 0.0:
		_dropout -= delta
		light_energy = base_energy * (0.05 if fmod(_time, 0.08) < 0.04 else 0.5)
		return
	if _rng.randf() < 0.002:
		_dropout = _rng.randf_range(0.2, 0.9)
		return
	light_energy = base_energy * (0.92 + 0.08 * sin(_time * 47.0) * sin(_time * 13.0))
