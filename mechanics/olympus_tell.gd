class_name OlympusTell
extends Node3D
## Sky Citadel: a gilded SUN-GLYPH tablet set beside a shared machine (a laser gate, a bull ram, a
## falling pediment) that warns before it fires. Over the last `window` seconds before
## `left.call(Game.course_time)` reaches zero the sun glyph brightens from soft gold to white-hot,
## its rays flicker and a little bronze bell rings faster and faster, so every timed hazard has a
## visible and audible tell of at least 0.8 s. Visual and sound only: it never touches gameplay.

## Seconds until the hazard next fires, as a function of course time.
var left: Callable
@export var window: float = 1.1
## Scale of the tablet.
@export var scale_k: float = 1.0

const GOLD := Color(1.0, 0.78, 0.28)
const HOT := Color(1.0, 0.95, 0.7)

var _mat: StandardMaterial3D
var _lamp: OmniLight3D
var _tick: int = -1


func _ready() -> void:
	add_to_group("course_clock")
	var k: float = scale_k
	var marble: StandardMaterial3D = Look.flat(Color(0.95, 0.92, 0.84), 0.5)
	add_child(Look.box(Vector3(0.7, 0.9, 0.16) * k, marble, Vector3(0, 0.45 * k, 0)))
	add_child(Look.box(Vector3(0.78, 0.08, 0.22) * k, Look.flat(GOLD, 0.35, 0.5, 0.3), Vector3(0, 0.94 * k, 0)))
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = GOLD
	_mat.emission_enabled = true
	_mat.emission = GOLD
	_mat.emission_energy_multiplier = 0.6
	# the sun glyph on both faces: a ring, a boss and eight short rays
	for s: float in [-1.0, 1.0]:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.13 * k
		tm.outer_radius = 0.18 * k
		tm.rings = 18
		tm.ring_segments = 6
		var ring := Look.mesh_node(tm, _mat, Vector3(0, 0.46 * k, s * 0.09 * k))
		ring.rotation.x = PI * 0.5
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		var boss := Look.sphere(0.07 * k, _mat, Vector3(0, 0.46 * k, s * 0.1 * k))
		boss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(boss)
		for i: int in 8:
			var a: float = TAU * float(i) / 8.0
			var ray := Look.box(Vector3(0.025, 0.09, 0.02) * k, _mat, Vector3(cos(a) * 0.26 * k, 0.46 * k + sin(a) * 0.26 * k, s * 0.09 * k))
			ray.rotation.z = a - PI * 0.5
			ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ray)
	_lamp = OmniLight3D.new()
	_lamp.light_color = HOT
	_lamp.light_energy = 0.0
	_lamp.omni_range = 3.5
	_lamp.position = Vector3(0, 0.5 * k, 0)
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
		_mat.emission = GOLD.lerp(HOT, w)
		_mat.albedo_color = _mat.emission
		_mat.emission_energy_multiplier = (0.8 + 2.2 * w) * flick
		_lamp.light_energy = 1.2 * w
		var tk: int = int(floor(w * 5.0 + w * w * 4.0))
		if tk != _tick:
			_tick = tk
			# SOUND: olympus_tell_tick - a small bronze bell, faster as the hazard nears
			WorldAudio.at(self, "olympus_tell_tick", global_position, 0.5, 22.0)
	else:
		_tick = -1
		if _lamp.light_energy != 0.0:
			_mat.emission = GOLD
			_mat.albedo_color = GOLD
			_mat.emission_energy_multiplier = 0.6
			_lamp.light_energy = 0.0
