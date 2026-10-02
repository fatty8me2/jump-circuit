class_name AbyssTell
extends Node3D
## The Abyss: an extra, early warning for a shared machine (an anchor drop, a mantis-shrimp ram):
## a cluster of bioluminescent warning lights on it that wake `lead` seconds before it strikes -
## dim, then brighter and faster-pulsing - with a creak sound at the start, and go dark once it
## has struck. Purely visual / audible: it reads the machine's clock through `strike_in`
## (seconds until the next strike at a course time), never drives it.

@export var lead: float = 1.1
@export var tint: Color = Color(1.0, 0.3, 0.2)
## Sound played as the warning starts.
@export var clip: String = "abyss_anchor_creak"
## Callable(time: float) -> float: seconds until the next strike (0 or less while striking).
var strike_in: Callable
## Called (time) -> bool: true while it is striking / dangerous (the lights stay hot).
var striking: Callable

var _mat: StandardMaterial3D
var _light: OmniLight3D
var _was: bool = false


func _m() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = tint
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.emission_enabled = true
		_mat.emission = tint
		_mat.emission_energy_multiplier = 0.0
	return _mat


func _ready() -> void:
	_m()
	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.light_energy = 0.0
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)


## A warning lamp (sphere) at a local position.
func add_lamp(local: Vector3, r: float = 0.14) -> void:
	var s := Look.sphere(r, _m(), local)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)


func _process(_dt: float) -> void:
	if not strike_in.is_valid():
		return
	var t: float = Game.course_time
	var hot: bool = striking.is_valid() and bool(striking.call(t))
	var left: float = float(strike_in.call(t))
	var warning: bool = not hot and left > 0.0 and left < lead
	var k: float = 0.0
	if warning:
		var w: float = 1.0 - left / lead
		var pulse: float = 0.5 + 0.5 * sin(t * lerpf(8.0, 30.0, w))
		k = lerpf(0.3, 1.0, w) * lerpf(0.6, 1.0, pulse)
	elif hot:
		k = 0.8
	_mat.emission_energy_multiplier = 4.0 * k
	_light.light_energy = 2.0 * k
	if warning and not _was:
		WorldAudio.at(self, clip, global_position, 0.8, 35.0)
	_was = warning
