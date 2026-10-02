class_name TempestGust
extends Area3D
## Tempest Tower: a HURRICANE GUST across a stretch of the climb. On a fixed rhythm (Game.course_time)
## a squall line comes at the tower: a grey wall of rain with roofing scraps, insulation and tarp
## rags tumbling in it appears `approach` metres upwind and races in, reaching the box `warn` seconds
## (1.2 s) after it shows. Wherever the front has passed, the wind blows at full strength for `hold`
## seconds, then drops. With your boots on steel it only leans on you (a fifth of its strength); in
## the air it throws you off the tower - so jump the gaps between squalls.
## Centre position; `push` is the peak acceleration in the node's local axes (the front travels along
## it).
##   cycle (u = 0 at the front reaching the box):  calm -> front approaching (`warn` s, the tell) ->
##   front crosses the box (`travel` s) -> full blow (`hold` s) -> dies (RAMP_DOWN)

@export var size: Vector3 = Vector3(16, 10, 30)
@export var push: Vector3 = Vector3(32, 0, 0)
@export var period: float = 7.0
@export var phase: float = 0.0
@export var travel: float = 0.5
@export var hold: float = 1.3
@export var warn: float = 1.2
## How far upwind of the box the squall line shows up (it covers this in `warn` seconds).
@export var approach: float = 16.0

const RAMP_UP: float = 0.12
const RAMP_DOWN: float = 0.4
## Share of the push felt with your feet on the steel.
const GROUND_GRIP: float = 0.2
const RAIN := Color(0.78, 0.82, 0.88, 0.55)
static var DEBRIS: PackedColorArray = PackedColorArray([Color(0.22, 0.22, 0.24), Color(0.85, 0.85, 0.82), Color(0.95, 0.55, 0.15),
		Color(0.35, 0.45, 0.62), Color(0.6, 0.58, 0.52)])

var _along: Vector3 = Vector3.RIGHT
var _across: Vector3 = Vector3.FORWARD
var _span: float = 1.0
var _width: float = 1.0
var _front: Node3D
var _sheet: GPUParticles3D
var _junk: GPUParticles3D
var _streaks: GPUParticles3D
var _spray: GPUParticles3D
var _was_active: bool = false
var _was_coming: bool = false
var _wind: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	_along = push.normalized() if push.length() > 0.01 else Vector3.RIGHT
	_across = Vector3.UP.cross(_along).normalized()
	_span = maxf(absf(size.dot(_along.abs())), 1.0)
	_width = maxf(absf(size.dot(_across.abs())), 1.0)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_build_visual()
	_wind = WorldAudio.loop("tempest_wind", self, -30.0, maxf(size.x, size.z) * 0.5 + 16.0, 6.0, false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_active = is_active_at(Game.course_time)
	_was_coming = _coming(Game.course_time)
	_apply(Game.course_time)
	_front.reset_physics_interpolation()


## Seconds into the cycle, where 0 = the front reaching the box's upwind face.
func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


func _env(tau: float) -> float:
	if tau < 0.0:
		return 0.0
	if tau < RAMP_UP:
		return smoothstep(0.0, RAMP_UP, tau)
	if tau < RAMP_UP + hold:
		return 1.0
	if tau < RAMP_UP + hold + RAMP_DOWN:
		return 1.0 - smoothstep(RAMP_UP + hold, RAMP_UP + hold + RAMP_DOWN, tau)
	return 0.0


## Seconds the whole gust lasts somewhere in the box (front at the face -> last point calm).
func duration() -> float:
	return travel + RAMP_UP + hold + RAMP_DOWN


func strength_at_lx(time: float, lx: float) -> float:
	var s: float = _s(time)
	var tau: float = s - travel * clampf((lx + _span * 0.5) / _span, 0.0, 1.0)
	return maxf(_env(tau), _env(tau + period))


func strength_at_point(time: float, world: Vector3) -> float:
	return strength_at_lx(time, (global_basis.inverse() * (world - global_position)).dot(_along))


func strength_at(time: float) -> float:
	var best: float = 0.0
	for i: int in 5:
		best = maxf(best, strength_at_lx(time, -_span * 0.5 + _span * float(i) / 4.0))
	return best


func is_active_at(time: float) -> bool:
	var s: float = _s(time)
	return s < duration() or s + period < duration()


## True while the squall line is visibly racing in (the tell).
func _coming(time: float) -> bool:
	return not is_active_at(time) and period - _s(time) < warn


## No wind anywhere in the box over [time, time + window].
func is_calm_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if is_active_at(time + s):
			return false
		s += 0.05
	return not is_active_at(time + window)


## Seconds until the next front reaches the box (0 while it blows).
func time_until_gust(time: float) -> float:
	if is_active_at(time):
		return 0.0
	return period - _s(time)


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_active_at(t):
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var pl := body as Player
			var e: float = strength_at_point(t, body.global_position)
			# boots on the steel: the wind only leans on you
			if pl.grounded:
				e *= GROUND_GRIP
			if e > 0.0:
				pl.add_impulse(global_basis * push * e * dt)


func _apply(t: float) -> void:
	var s: float = _s(t)
	var active: bool = is_active_at(t)
	var until: float = period - s
	var coming: bool = _coming(t)
	# the squall line: from `approach` upwind of the box, in to its face over `warn`, then across it
	var lx: float = -_span * 0.5
	var show: bool = false
	if coming:
		lx = -_span * 0.5 - approach * clampf(until / warn, 0.0, 1.0)
		show = true
	elif s < travel:
		lx = -_span * 0.5 + _span * (s / travel)
		show = true
	elif s < travel + 0.5:
		lx = _span * 0.5 + (s - travel) * 18.0
		show = true
	_front.position = _along * lx
	if _sheet.emitting != show:
		_sheet.emitting = show
		_junk.emitting = show
	var e: float = strength_at(t)
	_streaks.amount_ratio = 0.06 + 0.94 * e
	_streaks.speed_scale = 0.6 + 0.8 * e
	if _spray.emitting != (e > 0.2):
		_spray.emitting = e > 0.2
	if coming and not _was_coming:
		# SOUND: the squall roaring in from upwind (the tell, `warn` s ahead of the shove)
		WorldAudio.at(self, "tempest_gust_rise", global_position - _along * (_span * 0.5 + approach * 0.5), 0.9, maxf(size.x, size.z) + 30.0)
	_was_coming = coming
	if active and not _was_active:
		# SOUND: the gust front slamming into the tower
		WorldAudio.at(self, "tempest_gust", global_position, 1.0, maxf(size.x, size.z) + 24.0)
	_was_active = active
	if _wind != null:
		WorldAudio.set_active(_wind, e > 0.03)
		_wind.volume_db = -8.0 + linear_to_db(maxf(e, 0.02))


func _build_visual() -> void:
	var vis := AABB(-size * 0.5 - Vector3(10, 6, 10) - _along.abs() * approach, size + Vector3(20, 12, 20) + _along.abs() * approach * 2.0)
	var big := AABB(Vector3(-200, -80, -200), Vector3(400, 160, 400))
	# the squall line: a sheet of driven rain riding the front (the emitter moves, the rain streams
	# downwind) with roofing scraps and rags tumbling in it
	_front = Node3D.new()
	add_child(_front)
	var ext: Vector3 = Vector3(0.6, size.y * 0.5, 0.6) + _across.abs() * _width * 0.5
	_sheet = Fx.emitter({"amount": int(clampf(_width * size.y * 1.6, 90, 320)), "lifetime": 0.7, "emitting": false, "local": false,
		"shape": "box", "extents": ext, "dir": _along + Vector3(0, -0.35, 0), "spread": 6.0, "speed": Vector2(16.0, 24.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.035, 1.1), "color": RAIN,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": big})
	_front.add_child(_sheet)
	_junk = Fx.emitter({"amount": int(clampf(_width * 2.2, 18, 70)), "lifetime": 1.3, "emitting": false, "local": false,
		"shape": "box", "extents": ext, "dir": _along + Vector3(0, 0.25, 0), "spread": 25.0, "speed": Vector2(9.0, 15.0),
		"damping": Vector2(1.0, 3.0), "gravity": Vector3(0, -3.0, 0), "tex": Fx.Tex.PETAL, "additive": false,
		"size": 0.32, "scale": Vector2(0.6, 1.6), "curve": "flat", "pick": DEBRIS, "angle": Vector2(0, 360),
		"spin": Vector2(-720, 720), "turbulence": 1.0, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": big})
	_front.add_child(_junk)
	# rain streaks blowing through the box while it blows (thin drizzle when calm)
	_streaks = Fx.emitter({"amount": int(clampf(size.x * size.z * 0.14, 50, 200)), "lifetime": 1.0, "local": true,
		"shape": "box", "extents": size * 0.5, "dir": _along + Vector3(0, -0.2, 0), "spread": 5.0, "speed": Vector2(14.0, 20.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.03, 0.8),
		"color": RAIN, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	add_child(_streaks)
	# spray whipped off the steel while it blows
	_spray = Fx.emitter({"amount": int(clampf(_width * 1.4, 14, 50)), "lifetime": 0.9, "emitting": false, "local": true,
		"shape": "box", "extents": Vector3(size.x * 0.45, 0.3, size.z * 0.45), "offset": Vector3(0, -size.y * 0.3, 0),
		"dir": _along + Vector3(0, 0.3, 0), "spread": 20.0, "speed": Vector2(5.0, 9.0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 1.2, "curve": "puff", "color": Color(0.82, 0.86, 0.9, 0.22), "angle": Vector2(0, 360),
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	add_child(_spray)
