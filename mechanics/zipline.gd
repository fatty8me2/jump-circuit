class_name Zipline
extends Node3D
## Zipline (kit obstacle). A trolley rides a cable from the node's position (the start HANG
## point) to `end`, on the course clock. Stand under it (or jump into it) while it is not on
## its way back and you grab on: you hang `hang` metres below it and ride. Press jump to let
## go with the cable's speed kept (plus a small hop); otherwise you are released at the far end
## with the same speed. The trolley waits `dwell` seconds at the start (its lamp flashes and the
## cable rattles for the last second: the tell), rides, rests at the far end and returns empty.
##   s 0..dwell wait   dwell..dwell+ride ride   ..+0.35 rest   then return (not grabbable)
## Put the start hang point about 2.2 m above the start floor so a waiting rider stands on it.

@export var end: Vector3 = Vector3(0, 0, -20)
@export var speed: float = 11.0
@export var dwell: float = 1.4
@export var phase: float = 0.0
## Metres from the trolley down to the rider's feet.
@export var hang: float = 1.9
## Upward hop when the rider presses jump.
@export var hop: float = 6.0

const RAMP: float = 0.2
const REST: float = 0.35

var _a: Vector3
var _b: Vector3
var _ride: float = 1.0
var _return: float = 1.0
var _period: float = 1.0
var _handle: Node3D
var _lamp_mat: StandardMaterial3D
var _area: Area3D
var _rider: Player = null
var _was_control: bool = true
var _blend: float = 0.0
var _cool_until: float = -1.0
var _cable: MeshInstance3D
var _hum: AudioStreamPlayer3D
var _last_s: float = -1.0
var _released_tick: int = -100000
var _burst: GPUParticles3D
var _want_release: bool = false


func _ready() -> void:
	process_physics_priority = KitUtil.EARLY
	dwell = maxf(dwell, KitUtil.MIN_TELL + 0.1)
	_a = global_position
	_b = end
	var length: float = _a.distance_to(_b)
	_ride = maxf(length / (maxf(speed, 1.0) * (1.0 - RAMP * 0.5)), 0.5)
	_return = maxf(length / (speed * 1.6), 0.9)
	_period = dwell + _ride + REST + _return
	_build()
	_apply(Game.course_time)
	add_to_group("resettable")
	add_to_group("course_clock")


func _build() -> void:
	var metal: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.7)
	var cable_mat: StandardMaterial3D = Look.flat(Color(0.1, 0.1, 0.12), 0.5, 0.6)
	_cable = KitUtil.link(0.045, cable_mat)
	add_child(_cable)
	KitUtil.place_link(_cable, Vector3.ZERO, _b - _a)
	# a mast and cross-arm at each end, on the side of the line
	var along: Vector3 = (_b - _a)
	along.y = 0.0
	var side: Vector3 = Vector3.UP.cross(along.normalized() if along.length() > 0.1 else Vector3.FORWARD).normalized() * 1.5
	for end_pt: Vector3 in [Vector3.ZERO, _b - _a]:
		var base: Vector3 = end_pt + side
		var mast_h: float = 2.6
		add_child(Look.cylinder(0.13, mast_h, metal, base + Vector3(0, -mast_h * 0.5 + 0.4, 0), 0.1, 8))
		var arm := KitUtil.link(0.07, metal)
		add_child(arm)
		KitUtil.place_link(arm, base + Vector3(0, 0.4, 0), end_pt)
		add_child(Look.sphere(0.16, Look.flat(Look.c("accent"), 0.4, 0.2, 1.2), end_pt))
	# the trolley: two wheels on the cable, a hanger and a grip bar
	_handle = Node3D.new()
	add_child(_handle)
	_lamp_mat = Look.flat(Look.c("accent2"), 0.4, 0.1, 0.6).duplicate() as StandardMaterial3D
	_handle.add_child(Look.box(Vector3(0.5, 0.28, 0.34), metal, Vector3(0, -0.05, 0)))
	_handle.add_child(Look.sphere(0.12, _lamp_mat, Vector3(0, 0.16, 0)))
	_handle.add_child(Look.cylinder(0.04, hang - 0.5, Look.flat(Color(0.12, 0.12, 0.14), 0.5, 0.5), Vector3(0, -0.2 - (hang - 0.5) * 0.5, 0), -1.0, 6))
	var bar := Look.cylinder(0.06, 0.9, Look.flat(Look.c("accent"), 0.5, 0.2, 0.8), Vector3(0, -hang + 0.45, 0), -1.0, 8)
	bar.rotation.z = PI * 0.5
	_handle.add_child(bar)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.7, 2.6, 1.7)
	cs.shape = bs
	_area.add_child(cs)
	_area.position = Vector3(0, -1.0, 0)
	_handle.add_child(_area)
	_burst = Fx.sparks({"amount": 24, "lifetime": 0.4, "shape": "point", "dir": Vector3.UP, "spread": 120.0,
		"speed": Vector2(2.0, 6.0), "color": Color(2.4, 1.8, 0.9), "aabb": AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))})
	_handle.add_child(_burst)
	_hum = WorldAudio.loop("kit_zipline_whirr", _handle, -14.0, 30.0, 4.0)
	WorldAudio.set_active(_hum, false)


# ---- predictions -----------------------------------------------------------------------

func period() -> float:
	return _period


func ride_time() -> float:
	return _ride


func _s(time: float) -> float:
	return KitUtil.cycle_s(time, _period, phase)


func _profile(k: float) -> float:
	var v0: float = 1.0 / (1.0 - RAMP * 0.5)
	if k < RAMP:
		return v0 * k * k / (2.0 * RAMP)
	return v0 * (RAMP * 0.5 + (k - RAMP))


func _profile_rate(k: float) -> float:
	var v0: float = 1.0 / (1.0 - RAMP * 0.5)
	return v0 * minf(k / RAMP, 1.0)


## Where the trolley (its hang point) is at `time`.
func handle_at(time: float) -> Vector3:
	var s: float = _s(time)
	if s < dwell:
		return _a
	if s < dwell + _ride:
		return _a.lerp(_b, _profile((s - dwell) / _ride))
	if s < dwell + _ride + REST:
		return _b
	return _b.lerp(_a, KitUtil.smooth((s - dwell - _ride - REST) / _return))


## The trolley's velocity at `time` (zero when waiting, resting or returning slowly is included).
func velocity_at(time: float) -> Vector3:
	var s: float = _s(time)
	if s >= dwell and s < dwell + _ride:
		return (_b - _a) * _profile_rate((s - dwell) / _ride) / _ride
	return Vector3.ZERO


## The velocity of a rider let go at the end of the ride (full cruise speed).
func exit_velocity() -> Vector3:
	return (_b - _a) * _profile_rate(1.0) / _ride


## Riders can grab while it waits and rides; not while it returns or rests at the far end.
func grabbable_at(time: float) -> bool:
	return _s(time) < dwell + _ride


## Seconds until the trolley next leaves the start (0 while it is riding right now).
func departs_in(time: float) -> float:
	var s: float = _s(time)
	if s < dwell:
		return dwell - s
	if s < dwell + _ride:
		return 0.0
	return _period - s + dwell


## World position the rider's feet ride through at `time` (while hanging).
func rider_feet_at(time: float) -> Vector3:
	return handle_at(time) - Vector3(0, hang, 0)


## Where to stand to be picked up at the start.
func stand_point() -> Vector3:
	return _a - Vector3(0, hang, 0)


## Let go of the cable now, as if jump was pressed (the route bot uses this).
func release_rider() -> void:
	if _rider != null:
		_want_release = true


func is_riding() -> bool:
	return _rider != null


func carrying() -> Player:
	return _rider


func released_within(window: float) -> bool:
	return float(Engine.get_physics_frames() - _released_tick) / float(Engine.physics_ticks_per_second) <= window


# ---- behaviour -------------------------------------------------------------------------

func snap_to_clock() -> void:
	reset_state()
	_apply(Game.course_time)


func reset_state() -> void:
	_let_go(false, Vector3.ZERO)
	_cool_until = -1.0


func _on_rider_teleported() -> void:
	if _rider != null:
		_let_go(false, Vector3.ZERO)
		_cool_until = Game.course_time + 0.6


func _let_go(fly: bool, v: Vector3, hop_y: float = 0.0) -> void:
	var p: Player = _rider
	_rider = null
	_want_release = false
	WorldAudio.set_active(_hum, false)
	if p == null or not is_instance_valid(p):
		return
	if p.teleported.is_connected(_on_rider_teleported):
		p.teleported.disconnect(_on_rider_teleported)
	p.control_enabled = _was_control
	if fly:
		p.velocity = v
		p.set("_coyote", 0.0)
		p.set("_buffer", 0.0)
		if hop_y > 0.0:
			p.add_impulse(Vector3(0, hop_y, 0))   # also cancels variable-jump gravity and the floor snap
		_released_tick = Engine.get_physics_frames()
		_cool_until = Game.course_time + 0.8
		_burst.restart()
		WorldAudio.at(self, "kit_zipline_release", p.global_position, 0.8, 35.0)


func _apply(time: float) -> void:
	var pos: Vector3 = handle_at(time)
	_handle.global_position = pos
	_area.force_update_transform()
	# tell: lamp flashes (and the trolley judders) through the last second of the wait
	var s: float = _s(time)
	var left: float = dwell - s
	var glow_e: float = 0.6
	if left > 0.0 and left < 1.0 and s < dwell:
		glow_e = 0.6 + 3.0 * (1.0 if fmod(left, 0.2) > 0.1 else 0.2)
		_handle.global_position += Vector3(sin(time * 90.0), 0.0, cos(time * 77.0)) * 0.02
	KitUtil.glow(_lamp_mat, glow_e)


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	var s: float = _s(t)
	if _rider != null:
		if not is_instance_valid(_rider):
			_rider = null
			return
		_apply(t)
		_blend = minf(_blend + dt / 0.12, 1.0)
		var feet: Vector3 = rider_feet_at(t)
		_rider.global_position = _rider.global_position.lerp(feet, KitUtil.smooth(_blend))
		var v: Vector3 = velocity_at(t)
		_rider.velocity = v
		_rider.set("_no_snap", 0.2)
		_rider.grounded = false
		# a jump press (read before the Player's own step clears it) or a scripted release
		var jump: bool = _want_release or bool(_rider.get("_jump_press_queued"))
		if jump or not grabbable_at(t):
			_rider.set("_jump_press_queued", false)
			# a rider let go at the very end (no jump) keeps the speed too
			_let_go(true, v if jump else exit_velocity(), hop if jump else 0.0)
		WorldAudio.set_active(_hum, true)
		_last_s = s
		return
	_apply(t)
	_last_s = s
	_sounds(s)
	if t < _cool_until or not grabbable_at(t):
		return
	var p: Player = KitUtil.player_in(_area, true)
	if p != null:
		_grab(p)


func _grab(p: Player) -> void:
	_rider = p
	_was_control = p.control_enabled
	p.control_enabled = false
	_blend = 0.0
	if not p.teleported.is_connected(_on_rider_teleported):
		p.teleported.connect(_on_rider_teleported)
	_burst.restart()
	WorldAudio.at(self, "kit_zipline_grab", _handle.global_position, 0.8, 35.0)


var _tell_played: bool = false

func _sounds(s: float) -> void:
	var left: float = dwell - s
	if s < dwell and left < 1.0 and left > 0.0:
		if not _tell_played:
			_tell_played = true
			WorldAudio.at(self, "kit_zipline_ready", _handle.global_position, 0.6, 30.0)
	else:
		_tell_played = false
