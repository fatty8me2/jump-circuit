class_name JungleTell
extends Node3D
## Jungle Temple: a carved jade glyph set by a shared machine (a stone ram, a ceiling block) that
## warns before it fires. Over the last `window` seconds before `left.call(Game.course_time)` reaches
## zero the glyph brightens from jade to hot red and a stone mechanism ticks faster and faster, so
## every timed hazard has a visible and audible tell. Visual and sound only.

## Seconds until the hazard next fires, as a function of course time.
var left: Callable
@export var window: float = 1.1

const JADE := Color(0.25, 0.95, 0.65)
const HOT := Color(1.0, 0.32, 0.16)

var _mat: StandardMaterial3D
var _lamp: OmniLight3D
var _tick: int = -1


func _ready() -> void:
	add_to_group("course_clock")
	var stone: StandardMaterial3D = Look.flat(Color(0.4, 0.41, 0.34), 0.9)
	add_child(Look.box(Vector3(0.7, 0.7, 0.18), stone))
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = JADE
	_mat.emission_enabled = true
	_mat.emission = JADE
	_mat.emission_energy_multiplier = 0.5
	# the glyph: an eye in a ring, on both faces
	for s: float in [-1.0, 1.0]:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.18
		tm.outer_radius = 0.26
		tm.rings = 16
		tm.ring_segments = 6
		var ring := Look.mesh_node(tm, _mat, Vector3(0, 0, s * 0.1))
		ring.rotation.x = PI * 0.5
		add_child(ring)
		add_child(Look.box(Vector3(0.12, 0.12, 0.04), _mat, Vector3(0, 0, s * 0.1)))
	_lamp = OmniLight3D.new()
	_lamp.light_color = HOT
	_lamp.light_energy = 0.0
	_lamp.omni_range = 3.5
	add_child(_lamp)


func snap_to_clock() -> void:
	_process(0.0)


func _process(_dt: float) -> void:
	if not left.is_valid():
		return
	var l: float = float(left.call(Game.course_time))
	if l < window:
		var w: float = clampf(1.0 - l / window, 0.0, 1.0)
		var flick: float = 0.7 + 0.3 * sin(Game.course_time * (16.0 + 26.0 * w))
		_mat.emission = JADE.lerp(HOT, w)
		_mat.albedo_color = _mat.emission
		_mat.emission_energy_multiplier = (0.8 + 3.4 * w) * flick
		_lamp.light_energy = 1.4 * w
		var tk: int = int(floor(w * 5.0 + w * w * 4.0))
		if tk != _tick:
			_tick = tk
			WorldAudio.at(self, "jungle_trap_tick", global_position, 0.55, 22.0)
	else:
		_tick = -1
		if _lamp.light_energy != 0.0:
			_mat.emission = JADE
			_mat.albedo_color = JADE
			_mat.emission_energy_multiplier = 0.5
			_lamp.light_energy = 0.0
