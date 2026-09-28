class_name CarrierCatapult
extends Node3D
## Super Carrier: a steam catapult you ride. The node sits on the centre of the launch plate's top
## (the shuttle's spot at the aft end of its track); the track runs along local -Z for
## `track_length`. Stand on the plate and wait: on a fixed rhythm (Game.course_time) the launch
## valve opens and the shuttle rips down the track, flinging whoever stands on the plate forward at
## `launch_speed` and up at `launch_lift`. It is readable: for `warn` seconds before every shot the
## shooter lamps flash, steam hisses out of the slot and the plate tensions down a few centimetres.
##   cycle (s into the period): 0 FIRE -> shuttle runs out (RUN s) -> steam cloud -> shuttle crawls
##   back (RETRACT) -> armed -> the last `warn` s: tension, lamps, hiss

@export var track_length: float = 24.0
@export var plate_size: Vector3 = Vector3(2.8, 0.4, 2.8)
@export var period: float = 6.0
@export var phase: float = 0.0
@export var launch_speed: float = 18.0
@export var launch_lift: float = 8.0
@export var warn: float = 1.6

const RUN: float = 0.45
const HOLD: float = 0.35
## Fraction of the period the shuttle takes to crawl back.
const RETRACT: float = 0.35

const STEEL := Color(0.46, 0.48, 0.5)
const YELLOW := Color(1.0, 0.8, 0.12)

var _plate: StaticBody3D
var _plate_vis: Node3D
var _shuttle: Node3D
var _area: Area3D
var _lamps: Array[MeshInstance3D] = []
var _lamp_mat_on: StandardMaterial3D
var _lamp_mat_off: StandardMaterial3D
var _hiss: GPUParticles3D
var _steam: GPUParticles3D
var _blast: GPUParticles3D
var _sparks: GPUParticles3D
var _prev_s: float = 0.0
var _was_warn: bool = false
var _was_back: bool = false


func _ready() -> void:
	_build()
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_prev_s = _s(Game.course_time)
	_apply(Game.course_time)


# ---- the rhythm (pure functions of the course clock) ---------------------------------------------

func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## Seconds until the next shot (a full period right after one).
func time_until_fire(time: float) -> float:
	var s: float = _s(time)
	return period - s if s > 0.0001 else 0.0


## True if a shot happens in [time + a, time + b].
func fires_between(time: float, a: float, b: float) -> bool:
	var until: float = time_until_fire(time + a)
	return until <= b - a


## Shuttle position along the track (0 = on the plate, 1 = at the far end).
func shuttle_at(time: float) -> float:
	var s: float = _s(time)
	if s < RUN:
		var k: float = s / RUN
		return k * k
	if s < RUN + HOLD:
		return 1.0
	var back: float = RETRACT * period
	if s < RUN + HOLD + back:
		var r: float = (s - RUN - HOLD) / back
		return 1.0 - r * r * (3.0 - 2.0 * r)
	return 0.0


# ---- gameplay ----------------------------------------------------------------------------------

func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var s: float = _s(t)
	# the clock wrapped past the shot since the last tick: fire
	if s < _prev_s and _prev_s - s > period * 0.5:
		_fire()
	_prev_s = s


func _fire() -> void:
	var dir: Vector3 = -global_basis.z
	dir.y = 0.0
	dir = dir.normalized()
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			(body as Player).knockback(dir * launch_speed + Vector3(0, launch_lift, 0))
	_blast.restart()
	_sparks.restart()
	WorldAudio.at(self, "carrier_cat_launch", global_position, 1.0, 60.0)


# ---- look -----------------------------------------------------------------------------------------

func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var s: float = _s(t)
	var until: float = period - s
	var warning: bool = until < warn
	var k: float = shuttle_at(t)
	_shuttle.position = Vector3(0, 0.02, -k * track_length)
	# the plate tensions down as the valve builds pressure
	var sink: float = 0.0
	if warning:
		sink = -0.06 * (1.0 - until / warn)
	_plate_vis.position.y = sink
	var flash: bool = warning and fposmod(t * 4.0, 1.0) < 0.5
	for l: MeshInstance3D in _lamps:
		l.material_override = _lamp_mat_on if flash else _lamp_mat_off
	if _hiss.emitting != warning:
		_hiss.emitting = warning
	# steam wisps boil out of the slot while the shuttle is out and coming back
	var venting: bool = s < RUN + HOLD + RETRACT * period * 0.6
	if _steam.emitting != venting:
		_steam.emitting = venting
	if warning and not _was_warn:
		WorldAudio.at(self, "carrier_cat_hiss", global_position, 0.8, 35.0)
	var back: bool = s >= RUN + HOLD and k > 0.0
	if back and not _was_back:
		WorldAudio.at(self, "carrier_cat_retract", global_position - global_basis.z * track_length, 0.6, 40.0)
	_was_back = back
	_was_warn = warning


func _build() -> void:
	# the launch plate you stand on (solid) - hazard-striped rim, a grid of grip studs
	_plate = StaticBody3D.new()
	_plate.collision_layer = 1
	_plate.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = plate_size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -plate_size.y * 0.5, 0)
	_plate.add_child(cs)
	add_child(_plate)
	_plate_vis = Node3D.new()
	_plate.add_child(_plate_vis)
	var steel: StandardMaterial3D = Look.flat(STEEL, 0.55, 0.6)
	_plate_vis.add_child(Look.box(plate_size, steel, Vector3(0, -plate_size.y * 0.5, 0)))
	var stripe_a: StandardMaterial3D = Look.flat(YELLOW, 0.6, 0.0, 0.25)
	var stripe_b: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.08), 0.7)
	var n: int = 8
	for side: int in 4:
		for i: int in n:
			var f: float = (float(i) + 0.5) / float(n) - 0.5
			var along: float = (plate_size.x if side < 2 else plate_size.z)
			var p := Vector3.ZERO
			var sz := Vector3.ZERO
			if side < 2:
				p = Vector3(f * along, 0.012, (plate_size.z * 0.5 - 0.12) * (1.0 if side == 0 else -1.0))
				sz = Vector3(along / float(n), 0.03, 0.22)
			else:
				p = Vector3((plate_size.x * 0.5 - 0.12) * (1.0 if side == 2 else -1.0), 0.012, f * along)
				sz = Vector3(0.22, 0.03, along / float(n))
			var b := Look.box(sz, stripe_a if i % 2 == 0 else stripe_b, p)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_plate_vis.add_child(b)
	# the track: a dark slot with two rails running away along -Z
	var slot := Look.box(Vector3(0.36, 0.04, track_length), Look.flat(Color(0.05, 0.05, 0.06), 0.8), Vector3(0, 0.005, -track_length * 0.5))
	slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slot)
	var rail: StandardMaterial3D = Look.flat(Color(0.7, 0.72, 0.74), 0.3, 0.9)
	for sx: float in [-1.0, 1.0]:
		var r := Look.box(Vector3(0.1, 0.05, track_length), rail, Vector3(sx * 0.3, 0.02, -track_length * 0.5))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(r)
	# the shuttle: a squat spreader with a tow hook poking out of the slot
	_shuttle = Node3D.new()
	add_child(_shuttle)
	var dark: StandardMaterial3D = Look.flat(Color(0.2, 0.21, 0.22), 0.4, 0.8)
	_shuttle.add_child(Look.box(Vector3(0.5, 0.22, 1.3), dark, Vector3(0, 0.1, 0)))
	_shuttle.add_child(Look.box(Vector3(0.16, 0.35, 0.3), Look.flat(YELLOW, 0.5, 0.2, 0.4), Vector3(0, 0.3, -0.45)))
	# the shooter lamps either side of the plate
	_lamp_mat_on = Look.flat(YELLOW, 0.3, 0.0, 3.0)
	_lamp_mat_off = Look.flat(YELLOW.darkened(0.6), 0.4, 0.0, 0.1)
	for sx: float in [-1.0, 1.0]:
		var post := Look.cylinder(0.08, 0.7, dark, Vector3(sx * (plate_size.x * 0.5 + 0.5), 0.35, plate_size.z * 0.3))
		add_child(post)
		var lamp := Look.sphere(0.16, _lamp_mat_off, Vector3(sx * (plate_size.x * 0.5 + 0.5), 0.78, plate_size.z * 0.3))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
		_lamps.append(lamp)
	# the zone over the plate that the shot takes with it
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var as_ := BoxShape3D.new()
	as_.size = Vector3(plate_size.x - 0.1, 1.4, plate_size.z - 0.1)
	var acs := CollisionShape3D.new()
	acs.shape = as_
	acs.position = Vector3(0, 0.7, 0)
	_area.add_child(acs)
	add_child(_area)
	# effects: a hiss off the plate while it tensions, steam along the slot after a shot, the blast
	var vis := AABB(Vector3(-4, -2, -track_length - 4), Vector3(8, 10, track_length + 8))
	_hiss = Fx.smoke({"amount": 16, "lifetime": 0.9, "one_shot": false, "explosiveness": 0.0, "emitting": false,
		"shape": "box", "extents": Vector3(plate_size.x * 0.4, 0.05, plate_size.z * 0.4), "dir": Vector3.UP,
		"spread": 30.0, "speed": Vector2(0.8, 2.0), "size": 0.8, "color": Color(1, 1, 1, 0.5), "aabb": vis})
	add_child(_hiss)
	_steam = Fx.smoke({"amount": int(clampf(track_length * 1.6, 12, 60)), "lifetime": 1.8, "one_shot": false,
		"explosiveness": 0.0, "emitting": false, "shape": "box", "extents": Vector3(0.2, 0.05, track_length * 0.5),
		"offset": Vector3(0, 0, -track_length * 0.5), "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(1.0, 2.6),
		"size": 1.4, "color": Color(0.95, 0.96, 1.0, 0.55), "aabb": vis})
	add_child(_steam)
	_blast = Fx.smoke({"amount": 40, "lifetime": 1.3, "shape": "box", "extents": Vector3(0.4, 0.1, 1.0),
		"dir": Vector3(0, 0.4, 1), "spread": 45.0, "speed": Vector2(3.0, 8.0), "damping": Vector2(2.0, 4.0),
		"size": 1.8, "color": Color(1, 1, 1, 0.8), "aabb": vis})
	add_child(_blast)
	_sparks = Fx.sparks({"amount": 26, "shape": "box", "extents": Vector3(0.2, 0.05, 0.6), "dir": Vector3(0, 0.3, -1),
		"spread": 25.0, "speed": Vector2(6.0, 14.0), "color": Color(3.0, 2.2, 1.0), "aabb": vis})
	add_child(_sparks)
