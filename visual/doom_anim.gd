extends Node3D
## Doom Fortress, visual only: the machine's background motion. `mode`:
##  "pump"   - slides back and forth along `axis` by `amount` metres every `period` seconds (pistons,
##             rams and conrods pumping in the dark);
##  "beacon" - spins about local Y every `period` seconds; its child lights flare while they face
##             the camera side (a rotating alarm beacon);
##  "flicker"- a failing light: its OmniLight3D children stutter.
## Driven by wall-clock time with a random offset, so identical machines never move in step.

var mode: String = "pump"
var period: float = 2.0
var axis: Vector3 = Vector3.UP
var amount: float = 1.0

var _seed: float = 0.0
var _origin: Vector3 = Vector3.ZERO
var _lights: Array[Light3D] = []
var _base: Array[float] = []


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_seed = randf() * maxf(period, 0.01)
	_origin = position
	for c: Node in get_children():
		if c is Light3D:
			_lights.append(c as Light3D)
			_base.append((c as Light3D).light_energy)


func _process(dt: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001 + _seed
	match mode:
		"pump":
			var k: float = 0.5 - 0.5 * cos(t / maxf(period, 0.01) * TAU)
			position = _origin + axis * amount * k
		"beacon":
			rotate_object_local(Vector3.UP, dt * TAU / maxf(period, 0.01))
		"flicker":
			var on: bool = fmod(t * 7.3, 1.0) > 0.18 or fmod(t * 1.7, 1.0) > 0.5
			for i: int in _lights.size():
				_lights[i].light_energy = _base[i] * (1.0 if on else 0.15)
