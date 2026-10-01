class_name SakuraGust
extends Area3D
## Sakura Peaks: a MOUNTAIN GUST across the rope bridges. On a fixed rhythm (Game.course_time) the
## wind gathers on the upwind side - blossom lifts off the slope there - then a wave of petals
## races across the box; wherever the wave has passed the wind blows at full strength for `hold`
## seconds, then drops. It shoves you sideways: only a lean with your feet on the planks
## (friction wins), hard in the air - so jump the broken spans between gusts.
## Centre position; `push` is the peak acceleration in the node's local axes (the wave travels
## along it).
##   cycle: calm -> gathering (`warn` s) -> wave crosses (`travel` s) -> full blow (`hold` s) -> dies

@export var size: Vector3 = Vector3(16, 8, 30)
@export var push: Vector3 = Vector3(30, 0, 0)
@export var period: float = 6.0
@export var phase: float = 0.0
@export var travel: float = 0.6
@export var hold: float = 1.2
@export var warn: float = 1.2

const RAMP_UP: float = 0.15
const RAMP_DOWN: float = 0.35
## Share of the push felt with your feet on the ground.
const GROUND_GRIP: float = 0.2

var _along: Vector3 = Vector3.RIGHT
var _span: float = 1.0
var _front: Node3D
var _wave: GPUParticles3D
var _streaks: GPUParticles3D
var _lift: GPUParticles3D
var _was_active: bool = false
var _wind: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	_along = push.normalized() if push.length() > 0.01 else Vector3.RIGHT
	_span = maxf(absf(size.dot(_along.abs())), 1.0)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_build_visual()
	_wind = WorldAudio.loop("sakura_wind", self, -30.0, maxf(size.x, size.z) * 0.5 + 14.0, 6.0, false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_active = is_active_at(Game.course_time)
	_apply(Game.course_time)
	_front.reset_physics_interpolation()


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


## Seconds the whole gust lasts somewhere in the box (wave launch -> last point calm).
func duration() -> float:
	return travel + RAMP_UP + hold + RAMP_DOWN


func strength_at_lx(time: float, lx: float) -> float:
	var s: float = _s(time)
	var tau: float = s - travel * clampf((lx + _span * 0.5) / _span, 0.0, 1.0)
	return maxf(_env(tau), _env(tau + period))


func strength_at_point(time: float, world: Vector3) -> float:
	return strength_at_lx(time, to_local(world).dot(_along))


func strength_at(time: float) -> float:
	var best: float = 0.0
	for i: int in 5:
		best = maxf(best, strength_at_lx(time, -_span * 0.5 + _span * float(i) / 4.0))
	return best


func is_active_at(time: float) -> bool:
	var s: float = _s(time)
	return s < duration() or s + period < duration()


## No wind anywhere in the box over [time, time + window].
func is_calm_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if is_active_at(time + s):
			return false
		s += 0.05
	return not is_active_at(time + window)


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_active_at(t):
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var pl := body as Player
			var e: float = strength_at_point(t, body.global_position)
			# boots on the planks: the wind only leans on you (a fifth of its strength)
			if pl.grounded:
				e *= GROUND_GRIP
			if e > 0.0:
				pl.add_impulse(global_basis * push * e * dt)


func _apply(t: float) -> void:
	var s: float = _s(t)
	var active: bool = is_active_at(t)
	var until: float = period - s
	var gathering: bool = not active and until < warn
	var lx: float = -_span * 0.5
	var on: bool = false
	if s < travel:
		lx = -_span * 0.5 + _span * (s / travel)
		on = true
	_front.position = _along * lx
	if _wave.emitting != on:
		_wave.emitting = on
	var e: float = strength_at(t)
	_streaks.amount_ratio = 0.08 + 0.92 * e
	_streaks.speed_scale = 0.6 + 0.8 * e
	if _lift.emitting != (gathering or (active and s < travel)):
		_lift.emitting = gathering or (active and s < travel)
	if gathering and not _was_gathering:
		# SOUND: the wind rising in the trees upwind (the tell, `warn` s ahead)
		WorldAudio.at(self, "sakura_gust_rise", global_position - _along * _span * 0.4, 0.8, maxf(size.x, size.z) + 20.0)
	_was_gathering = gathering
	if active and not _was_active:
		# SOUND: the gust front sweeping across
		WorldAudio.at(self, "sakura_gust", global_position, 1.0, maxf(size.x, size.z) + 20.0)
	_was_active = active
	if _wind != null:
		WorldAudio.set_active(_wind, e > 0.03)
		_wind.volume_db = -10.0 + linear_to_db(maxf(e, 0.02))


var _was_gathering: bool = false


func _build_visual() -> void:
	var up := Vector3.UP
	var z: Vector3 = _along
	var x: Vector3 = up.cross(z).normalized()
	var across: float = maxf(absf(size.dot(x.abs())), 1.0)
	var vis := AABB(-size * 0.5 - Vector3(8, 4, 8), size + Vector3(16, 8, 16))
	# the wave: a thin wall of petals that rides the front (emitter moves, petals stream downwind)
	_front = Node3D.new()
	add_child(_front)
	_wave = Fx.emitter({"amount": int(clampf(across * 9.0, 60, 260)), "lifetime": 1.1, "emitting": false, "local": false,
		"shape": "box", "extents": Vector3(0.4, size.y * 0.35, 0.4) + x.abs() * across * 0.5,
		"dir": _along + Vector3(0, 0.15, 0), "spread": 12.0, "speed": Vector2(8.0, 14.0), "damping": Vector2(4.0, 6.0),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.2, "curve": "flat", "pick": SakuraFx.PETALS,
		"angle": Vector2(0, 360), "spin": Vector2(-500, 500), "turbulence": 0.8,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": AABB(Vector3(-200, -60, -200), Vector3(400, 120, 400))})
	_front.add_child(_wave)
	# streaks of blossom blowing through the box while it blows (thin when calm)
	_streaks = Fx.emitter({"amount": int(clampf(size.x * size.z * 0.12, 40, 160)), "lifetime": 1.4, "local": true,
		"shape": "box", "extents": size * 0.5, "dir": _along, "spread": 6.0, "speed": Vector2(10.0, 16.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.04, 0.5),
		"color": Color(1.0, 0.86, 0.9, 0.45), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	add_child(_streaks)
	# petals lifting off along the upwind edge while the gust gathers
	_lift = Fx.emitter({"amount": int(clampf(across * 2.2, 16, 70)), "lifetime": 1.3, "emitting": false, "local": true,
		"shape": "box", "extents": Vector3(0.3, 0.2, 0.3) + x.abs() * across * 0.5, "offset": -_along * _span * 0.5 - Vector3(0, size.y * 0.3, 0),
		"dir": _along * 0.6 + Vector3(0, 1.0, 0), "spread": 25.0, "speed": Vector2(2.0, 4.5), "gravity": Vector3(0, -1.0, 0),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.22, "curve": "flat", "pick": SakuraFx.PETALS,
		"angle": Vector2(0, 360), "spin": Vector2(-300, 300), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	add_child(_lift)
