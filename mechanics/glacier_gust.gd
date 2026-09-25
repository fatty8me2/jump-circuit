class_name GlacierGust
extends Area3D
## Frostbite Pass: a BLIZZARD GUST. On a fixed rhythm (Game.course_time) a wall of blown snow
## gathers at the upwind side of a stage, then races across it; wherever the front has passed
## the wind blows at full strength for `hold` seconds, then drops. It shoves you sideways -
## hardly at all with your feet on the ground (friction wins), hard in the air - so time your
## jumps between gusts, or ride one. Centre position; `push` is the peak acceleration in the
## node's local axes (the front travels along it).
##   cycle: calm -> gathering (`warn` s: snow lifts along the upwind edge) -> front crosses
##          (`travel` s) -> full blow behind it (`hold` s) -> dies away

@export var size: Vector3 = Vector3(20, 8, 30)
@export var push: Vector3 = Vector3(28, 0, 0)
@export var period: float = 4.0
@export var phase: float = 0.0
@export var travel: float = 0.6
@export var hold: float = 1.0
@export var warn: float = 1.0

const RAMP_UP: float = 0.15
const RAMP_DOWN: float = 0.35
const SHADER: Shader = preload("res://visual/glacier_gust.gdshader")

var _along: Vector3 = Vector3.RIGHT
var _span: float = 1.0
var _front: Node3D
var _front_mats: Array[ShaderMaterial] = []
var _streaks: GPUParticles3D
var _puffs: GPUParticles3D
var _lift: GPUParticles3D
var _was_active: bool = false
# sound (side effect only): the whoosh as the front launches, the wind while it blows
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
	_wind = WorldAudio.loop("wind_loop", self, -30.0, maxf(size.x, size.z) * 0.5 + 14.0, 6.0, false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_active = is_active_at(Game.course_time)
	_apply(Game.course_time)
	_front.reset_physics_interpolation()


# ---- the rhythm (pure functions of the course clock) ------------------------------------------

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


## Seconds the whole gust lasts somewhere in the box (front launch -> last point calm).
func duration() -> float:
	return travel + RAMP_UP + hold + RAMP_DOWN


## Strength 0..1 at local coordinate `lx` along the push (-span/2 upwind .. +span/2 downwind).
func strength_at_lx(time: float, lx: float) -> float:
	var s: float = _s(time)
	var tau: float = s - travel * clampf((lx + _span * 0.5) / _span, 0.0, 1.0)
	return maxf(_env(tau), _env(tau + period))


## Strength at a world point (0 outside the gust's reach along its axis).
func strength_at_point(time: float, world: Vector3) -> float:
	return strength_at_lx(time, to_local(world).dot(_along))


## Strongest push anywhere in the box at `time`.
func strength_at(time: float) -> float:
	var best: float = 0.0
	for i: int in 5:
		best = maxf(best, strength_at_lx(time, -_span * 0.5 + _span * float(i) / 4.0))
	return best


func is_active_at(time: float) -> bool:
	var s: float = _s(time)
	return s < duration() or s + period < duration()


## No wind anywhere in the box for the next `window` seconds.
func is_calm_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if is_active_at(time + s):
			return false
		s += 0.05
	return not is_active_at(time + window)


## Seconds until the next front launches (0 while a gust is on).
func time_until_gust(time: float) -> float:
	if is_active_at(time):
		return 0.0
	return period - _s(time)


# ---- gameplay ----------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_active_at(t):
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var e: float = strength_at_point(t, body.global_position)
			if e > 0.0:
				(body as Player).add_impulse(global_basis * push * e * dt)


# ---- look -----------------------------------------------------------------------------------------

func _apply(t: float) -> void:
	var s: float = _s(t)
	var active: bool = is_active_at(t)
	var until: float = period - s
	var gathering: bool = not active and until < warn
	# the front: gathers at the upwind edge, races across, fades at the far side
	var lx: float = -_span * 0.5
	var a: float = 0.0
	if gathering:
		a = 0.55 * (1.0 - until / warn)
	elif s < travel:
		lx = -_span * 0.5 + _span * (s / travel)
		a = 0.55 + 0.45 * (s / travel)
	elif s < travel + 0.4:
		lx = _span * 0.5
		a = 1.0 - (s - travel) / 0.4
	_front.visible = a > 0.01
	_front.position = _along * lx
	for m: ShaderMaterial in _front_mats:
		m.set_shader_parameter("strength", a * (1.0 if m == _front_mats[0] else 0.6))
	var e: float = strength_at(t)
	_streaks.amount_ratio = 0.12 + 0.88 * e
	_streaks.speed_scale = 0.6 + 0.8 * e
	_puffs.amount_ratio = 0.1 + 0.9 * e
	if _lift.emitting != (gathering or (active and s < travel)):
		_lift.emitting = gathering or (active and s < travel)
	if active and not _was_active:
		WorldAudio.at(self, "gust_whoosh", global_position, 1.0, maxf(size.x, size.z) + 20.0)
	_was_active = active
	if _wind != null:
		WorldAudio.set_active(_wind, e > 0.03)
		_wind.volume_db = -10.0 + linear_to_db(maxf(e, 0.02))


func _build_visual() -> void:
	var up := Vector3.UP
	var z: Vector3 = _along
	var x: Vector3 = up.cross(z).normalized()
	var across: float = maxf(absf(size.dot(x.abs())), 1.0)
	var vis := AABB(-size * 0.5 - Vector3(6, 4, 6), size + Vector3(12, 8, 12))
	# the front: three staggered sheets of blown snow, square to the push
	_front = Node3D.new()
	_front.basis = Basis(x, up, z)
	add_child(_front)
	for i: int in 3:
		var q := QuadMesh.new()
		q.size = Vector2(across * 1.05, size.y * 1.15)
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("seed", float(i) * 7.3)
		_front_mats.append(m)
		var mi := Look.mesh_node(q, m, Vector3(0, 0, -float(i) * 0.9))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_front.add_child(mi)
	# snow streaks and spindrift puffs blowing through the box (thick while it blows)
	_streaks = GlacierFx.blizzard(size, _along, int(clampf(size.x * size.z * 0.18, 40, 150)), 16.0)
	_streaks.local_coords = true
	_streaks.visibility_aabb = vis
	add_child(_streaks)
	_puffs = GlacierFx.spindrift(size * Vector3(0.9, 0.7, 0.9), _along, int(clampf(size.x * size.z * 0.02, 6, 22)), 3.2)
	_puffs.local_coords = true
	_puffs.visibility_aabb = vis
	add_child(_puffs)
	# snow lifting off along the upwind edge while the gust gathers
	_lift = Fx.emitter({"amount": int(clampf(across * 1.6, 12, 48)), "lifetime": 1.0, "emitting": false, "local": true,
		"shape": "box", "extents": Vector3(0.3, 0.2, 0.3) + x.abs() * across * 0.5, "offset": -_along * _span * 0.5 - Vector3(0, size.y * 0.4, 0),
		"dir": _along + Vector3(0, 1.2, 0), "spread": 25.0, "speed": Vector2(2.0, 5.0), "gravity": Vector3(0, -2.0, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.2, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.95, 0.97, 1.0, 0.5), "fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis})
	add_child(_lift)
