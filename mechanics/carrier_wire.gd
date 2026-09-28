class_name CarrierWire
extends StaticBody3D
## Super Carrier: an ARRESTING WIRE. A taut steel cable stretched across a gap (local X, `length`
## long) on a sheave post at each end. Land on it and it twangs: it throws you straight up at
## `strength` m/s and keeps your run speed, like a bounce pad drawn out into a line. The node sits at
## the middle of the cable's top. A yellow hazard sling under the cable shows where it catches.
## Bot / level use: step onto it like a pad (r_pad).

@export var length: float = 10.0
@export var strength: float = 15.0
## Catch width across the cable (the collision is wider than the visible wire, on purpose).
@export var catch_width: float = 1.1

const CABLE := Color(0.72, 0.74, 0.76)
const YELLOW := Color(1.0, 0.8, 0.12)
const SEGMENTS: int = 12

var _cable: Array[MeshInstance3D] = []
var _sling_mat: StandardMaterial3D
var _t_hit: float = -10.0
var _hit_x: float = 0.0
var _sparks: GPUParticles3D
var _ring: GPUParticles3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 0.3, catch_width)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.15, 0)
	add_child(cs)
	_build()
	set_process(false)


# ---- the pad interface the Player reads --------------------------------------------------------

func get_surface_up() -> Vector3:
	return Vector3.UP


func get_launch() -> Dictionary:
	return {"velocity": Vector3(0, strength, 0), "keep_horizontal": true}


func on_bounced(p: Node3D) -> void:
	_hit_x = clampf(to_local(p.global_position).x, -length * 0.45, length * 0.45)
	_t_hit = 0.0
	set_process(true)
	_sparks.position = Vector3(_hit_x, 0.0, 0)
	_sparks.restart()
	_ring.position = Vector3(_hit_x, 0.05, 0)
	_ring.restart()
	WorldAudio.at(self, "carrier_wire_twang", to_global(Vector3(_hit_x, 0, 0)), 1.0, 40.0)


# ---- look ---------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	_t_hit += dt
	# a damped twang: the cable dips under the hit, springs back and rings out
	var amp: float = 0.45 * exp(-_t_hit * 4.0) * cos(_t_hit * 28.0)
	for i: int in _cable.size():
		var x0: float = -length * 0.5 + length * float(i) / float(SEGMENTS)
		var x1: float = -length * 0.5 + length * float(i + 1) / float(SEGMENTS)
		var y0: float = _sag(x0) * amp
		var y1: float = _sag(x1) * amp
		var seg: MeshInstance3D = _cable[i]
		seg.position = Vector3((x0 + x1) * 0.5, 0.06 + (y0 + y1) * 0.5, 0)
		seg.rotation.z = atan2(y1 - y0, x1 - x0)
	_sling_mat.emission_energy_multiplier = 0.3 + 2.0 * exp(-_t_hit * 5.0)
	if _t_hit > 1.6:
		set_process(false)


## How far the point at `x` dips for a unit twang at the hit point (tent shape to the posts).
func _sag(x: float) -> float:
	var h: float = length * 0.5
	if x < _hit_x:
		return -(x + h) / maxf(_hit_x + h, 0.01)
	return -(h - x) / maxf(h - _hit_x, 0.01)


func _build() -> void:
	var steel: StandardMaterial3D = Look.flat(CABLE, 0.25, 0.9)
	var seg_len: float = length / float(SEGMENTS)
	for i: int in SEGMENTS:
		var seg := Look.cylinder(0.075, seg_len * 1.02, steel, Vector3(-length * 0.5 + seg_len * (float(i) + 0.5), 0.06, 0), -1.0, 8)
		seg.rotation.z = PI * 0.5
		var holder := MeshInstance3D.new()
		holder.position = seg.position
		seg.position = Vector3.ZERO
		holder.add_child(seg)
		add_child(holder)
		_cable.append(holder)
	# the hazard sling under the cable that marks the catch
	_sling_mat = Look.flat(YELLOW, 0.5, 0.0, 0.3).duplicate() as StandardMaterial3D
	var sling := Look.box(Vector3(length - 0.4, 0.05, catch_width * 0.8), _sling_mat, Vector3(0, -0.12, 0))
	sling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sling)
	var dark: StandardMaterial3D = Look.flat(Color(0.1, 0.1, 0.1), 0.7)
	var n: int = int(length / 0.8)
	for i: int in n:
		if i % 2 == 1:
			continue
		var tick := Look.box(Vector3(0.4, 0.052, catch_width * 0.82), dark, Vector3(-length * 0.5 + 0.4 + float(i) * 0.8, -0.12, 0))
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tick)
	# a sheave post at each end, with its bow springs
	var post: StandardMaterial3D = Look.flat(Color(0.3, 0.31, 0.33), 0.5, 0.6)
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * (length * 0.5 + 0.2), 0, 0)
		add_child(Look.box(Vector3(0.5, 0.9, 0.9), post, p + Vector3(0, -0.3, 0)))
		var sheave := Look.cylinder(0.32, 0.18, Look.flat(YELLOW, 0.5, 0.3), p + Vector3(0, 0.08, 0))
		sheave.rotation.x = PI * 0.5
		add_child(sheave)
	var vis := AABB(Vector3(-length * 0.5 - 2, -2, -3), Vector3(length + 4, 6, 6))
	_sparks = Fx.sparks({"amount": 18, "dir": Vector3.UP, "spread": 60.0, "speed": Vector2(3.0, 7.0),
		"color": Color(3.0, 2.4, 1.2), "aabb": vis})
	add_child(_sparks)
	_ring = Fx.shockwave(1.6, {"color": Color(2.0, 1.7, 0.6)})
	_ring.visibility_aabb = vis
	add_child(_ring)
