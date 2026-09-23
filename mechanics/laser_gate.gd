class_name LaserGate
extends Node3D
## A kill beam between two emitter posts that fires on a fixed rhythm driven by
## Game.course_time (identical for every racer). Off: a faint dotted guide line.
## For `warn` seconds before firing the guide flickers bright. On: a solid red
## beam that sends you back to the checkpoint. Local X runs between the posts.

@export var size: Vector3 = Vector3(4, 0.25, 0.25)
@export var period: float = 3.0
@export var on_fraction: float = 0.5
@export var phase: float = 0.0
@export var warn: float = 0.45

var _area: Area3D
var _beam: MeshInstance3D
var _guide: MeshInstance3D
var _guide_mat: StandardMaterial3D


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size * Vector3(1.0, 0.92, 0.92)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	add_child(_area)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(1.0, 0.18, 0.12)
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(1.0, 0.15, 0.1)
	beam_mat.emission_energy_multiplier = 4.0
	_beam = Look.box(size, beam_mat)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_guide_mat = StandardMaterial3D.new()
	_guide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_guide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guide_mat.albedo_color = Color(1.0, 0.3, 0.2, 0.18)
	_guide = Look.box(Vector3(size.x, size.y * 0.3, size.z * 0.3), _guide_mat)
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_guide)
	var post_mat: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.18), 0.4, 0.7)
	var eye_mat: StandardMaterial3D = Look.flat(Color(1.0, 0.25, 0.15), 0.3, 0.0, 2.5)
	var post_h: float = maxf(size.y + 0.8, 1.2)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.36, post_h, 0.36), post_mat, Vector3(sx * (size.x * 0.5 + 0.18), 0, 0)))
		add_child(Look.box(Vector3(0.1, maxf(size.y, 0.2) + 0.1, maxf(size.z, 0.2) + 0.1), eye_mat, Vector3(sx * (size.x * 0.5 + 0.02), 0, 0)))
	_apply()


func is_on_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < on_fraction


## Seconds until the beam next switches on (0 while it is on).
func time_until_on(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return 0.0 if u < on_fraction else (1.0 - u) * period


## Seconds until the beam next switches off (0 while it is off).
func time_until_off(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (on_fraction - u) * period if u < on_fraction else 0.0


func _apply() -> void:
	var t: float = Game.course_time
	var on: bool = is_on_at(t)
	_beam.visible = on
	_guide.visible = not on
	var a: float = 0.18
	var until_on: float = time_until_on(t)
	if not on and until_on < warn:
		a = 0.75 if fmod(until_on, 0.12) > 0.06 else 0.35
	if not is_equal_approx(_guide_mat.albedo_color.a, a):
		var c: Color = _guide_mat.albedo_color
		c.a = a
		_guide_mat.albedo_color = c


func _physics_process(_dt: float) -> void:
	_apply()
	if not is_on_at(Game.course_time):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return
