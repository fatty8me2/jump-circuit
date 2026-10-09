class_name FungalTell
extends Node3D
## Mushroom Hollow: a WARNING TOADSTOOL. A small cluster of red-capped toadstools set beside a machine (a frog's tongue, a falling acorn,
## a sunbeam lens). Over the last `window` seconds before `left.call(Game.course_time)` reaches zero
## the caps glow hotter and blink faster and a bright "tick-tick" quickens, so every timed hazard has
## a visible AND audible tell well before it fires. Visual and sound only: it only reads the
## machine's clock, it never drives it.

## Seconds until the hazard next fires, as a function of course time.
var left: Callable
@export var window: float = 1.2
@export var clip: String = "fungal_tell_tick"

const CALM := Color(1.0, 0.85, 0.35)
const HOT := Color(1.0, 0.28, 0.12)

var _mat: StandardMaterial3D
var _lamp: OmniLight3D
var _tick: int = -1


func _ready() -> void:
	add_to_group("course_clock")
	var stalk: StandardMaterial3D = Look.flat(Color(0.97, 0.93, 0.82), 0.8)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.9, 0.25, 0.2)
	_mat.roughness = 0.5
	_mat.emission_enabled = true
	_mat.emission = CALM
	_mat.emission_energy_multiplier = 0.15
	var spot: StandardMaterial3D = Look.flat(Color(1.0, 0.96, 0.85), 0.5)
	for i: int in 3:
		var h: float = 0.42 + 0.16 * float(i % 2)
		var r: float = 0.2 + 0.05 * float(i % 3)
		var at := Vector3((float(i) - 1.0) * 0.34, 0.0, 0.06 * float(i % 2))
		add_child(Look.cylinder(0.05, h, stalk, at + Vector3(0, h * 0.5, 0), 0.04, 8))
		var cap := Look.sphere(r, _mat, at + Vector3(0, h, 0))
		cap.scale = Vector3(1.0, 0.62, 1.0)
		add_child(cap)
		for j: int in 3:
			var a: float = TAU * float(j) / 3.0 + float(i)
			add_child(Look.sphere(0.04, spot, at + Vector3(cos(a) * r * 0.55, h + r * 0.5, sin(a) * r * 0.55)))
	_lamp = OmniLight3D.new()
	_lamp.light_color = HOT
	_lamp.light_energy = 0.0
	_lamp.omni_range = 4.0
	_lamp.position = Vector3(0, 0.8, 0)
	add_child(_lamp)


func snap_to_clock() -> void:
	_process(0.0)


func _process(_dt: float) -> void:
	if not left.is_valid():
		return
	var l: float = float(left.call(Game.course_time))
	if l > 0.0 and l < window:
		var w: float = clampf(1.0 - l / window, 0.0, 1.0)
		var flick: float = 0.6 + 0.4 * sin(Game.course_time * (14.0 + 30.0 * w))
		_mat.emission = CALM.lerp(HOT, w)
		_mat.emission_energy_multiplier = (0.6 + 3.2 * w) * flick
		_lamp.light_energy = 1.2 * w * flick
		var tk: int = int(floor(w * 5.0 + w * w * 5.0))
		if tk != _tick:
			_tick = tk
			WorldAudio.at(self, clip, global_position, 0.55, 24.0)
	else:
		_tick = -1
		if _lamp.light_energy != 0.0:
			_mat.emission = CALM
			_mat.emission_energy_multiplier = 0.15
			_lamp.light_energy = 0.0
