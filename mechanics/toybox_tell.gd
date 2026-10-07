class_name ToyboxTell
extends Node3D
## Toybox Tumble: a little toy warning lamp - a round bulb in a painted holder - set beside a
## shared machine (a laser, a piston, a press). Over the last `window` seconds before
## `left.call(Game.course_time)` reaches zero the bulb swells from friendly green to hot red,
## flickers faster and faster and a toy rattle ticks on the same beat, so every timed hazard has
## a visible and audible tell of at least a second. Visual and sound only.

## Seconds until the hazard next fires, as a function of course time.
var left: Callable
@export var window: float = 1.2
@export var stem: float = 0.0

const GREEN := Color(0.4, 0.95, 0.5)
const HOT := Color(1.0, 0.25, 0.15)

var _mat: StandardMaterial3D
var _lamp: OmniLight3D
var _bulb: MeshInstance3D
var _tick: int = -1


func _ready() -> void:
	add_to_group("course_clock")
	var paint: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.2), 0.5)
	if stem > 0.0:
		add_child(Look.cylinder(0.07, stem, Look.flat(Color(0.9, 0.9, 0.95), 0.4, 0.6), Vector3(0, -stem * 0.5, 0), -1.0, 8))
	add_child(Look.box(Vector3(0.62, 0.16, 0.62), paint, Vector3(0, -0.34, 0)))
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = GREEN
	_mat.emission_enabled = true
	_mat.emission = GREEN
	_mat.emission_energy_multiplier = 0.5
	_bulb = Look.sphere(0.3, _mat, Vector3(0, 0, 0))
	add_child(_bulb)
	# three little ear-flaps round the bulb, like a toy siren
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var fin := Look.box(Vector3(0.05, 0.4, 0.16), paint, Vector3(cos(a) * 0.34, 0.0, sin(a) * 0.34))
		fin.rotation.y = -a
		add_child(fin)
	_lamp = OmniLight3D.new()
	_lamp.light_color = HOT
	_lamp.light_energy = 0.0
	_lamp.omni_range = 4.0
	add_child(_lamp)


func snap_to_clock() -> void:
	_process(0.0)


func _process(_dt: float) -> void:
	if not left.is_valid():
		return
	var l: float = float(left.call(Game.course_time))
	if l < window:
		var w: float = clampf(1.0 - l / window, 0.0, 1.0)
		var flick: float = 0.65 + 0.35 * sin(Game.course_time * (14.0 + 30.0 * w))
		_mat.emission = GREEN.lerp(HOT, clampf(w * 1.6, 0.0, 1.0))
		_mat.albedo_color = _mat.emission
		_mat.emission_energy_multiplier = (0.8 + 3.0 * w) * flick
		_bulb.scale = Vector3.ONE * (1.0 + 0.25 * w * flick)
		_lamp.light_energy = 1.4 * w
		var tk: int = int(floor(w * 5.0 + w * w * 5.0))
		if tk != _tick:
			_tick = tk
			# SOUND: toybox_tell_tick - a toy rattle ticking faster and faster (about 1.2 s ahead of the hazard)
			WorldAudio.at(self, "toybox_tell_tick", global_position, 0.5, 24.0)
	else:
		_tick = -1
		if _lamp.light_energy != 0.0:
			_mat.emission = GREEN
			_mat.albedo_color = GREEN
			_mat.emission_energy_multiplier = 0.5
			_bulb.scale = Vector3.ONE
			_lamp.light_energy = 0.0
