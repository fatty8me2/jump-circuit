class_name OlympusSpirit
extends Area3D
## Sky Citadel: a WIND SPIRIT. A cloud-white sprite with a puffed face and a long scarf of mist lives
## at the upwind end of a gust lane. On a fixed rhythm (Game.course_time, identical for every racer)
## it GATHERS for `warn` s (at least 0.8: it swells out of the cloud, wisps spiral into it and it
## whistles), then RUSHES down the lane in `travel` s; wherever it has passed, the wind blows at
## full strength for `hold` s, then dies away. It shoves you along the lane's push: a lean with your
## feet on the marble (friction wins), hard in the air - so jump the gaps between gusts, or ride them.
## Centre position; `push` is the peak acceleration in the node's local axes (the spirit travels
## along it).
##   cycle: calm -> gathering (`warn` s) -> the spirit crosses (`travel` s) -> full blow (`hold` s) -> dies
##   bot helpers: is_active_at(t), is_calm_for(t, window), strength_at_point(t, p)

@export var size: Vector3 = Vector3(10, 6, 28)
@export var push: Vector3 = Vector3(26, 0, 0)
@export var period: float = 7.0
@export var phase: float = 0.0
@export var travel: float = 0.7
@export var hold: float = 1.3
@export var warn: float = 1.1

const RAMP_UP: float = 0.15
const RAMP_DOWN: float = 0.35
## Share of the push felt with your feet on the ground.
const GROUND_GRIP: float = 0.2
const MIST := Color(0.96, 0.98, 1.0)
const SKY := Color(0.55, 0.82, 1.0)

var _along: Vector3 = Vector3.RIGHT
var _span: float = 1.0
var _front: Node3D
var _face: Node3D
var _face_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _scarf: GPUParticles3D
var _gather: GPUParticles3D
var _streaks: GPUParticles3D
var _was_active: bool = false
var _was_gathering: bool = false
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
	# SOUND: olympus_wind_loop - the gust roaring along the lane while it blows (loop, level follows the strength)
	_wind = WorldAudio.loop("olympus_wind_loop", self, -30.0, maxf(size.x, size.z) * 0.5 + 14.0, 6.0, false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_active = is_active_at(Game.course_time)
	_was_gathering = false
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


## Seconds the whole gust lasts somewhere in the lane (the spirit sets off -> the last point is calm).
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


## No wind anywhere in the lane over [time, time + window].
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
	var crossing: bool = false
	if s < travel:
		lx = -_span * 0.5 + _span * (s / travel)
		crossing = true
	_front.position = _along * lx
	# the spirit: swells out of the cloud while it gathers, full size as it runs, gone once the gust has passed
	var sc: float = 0.0
	if gathering:
		sc = 0.25 + 0.75 * clampf(1.0 - until / maxf(warn, 0.01), 0.0, 1.0)
	elif crossing:
		sc = 1.0
	elif active and s < travel + 0.6:
		sc = clampf(1.0 - (s - travel) / 0.6, 0.0, 1.0)
	_face.visible = sc > 0.02
	_face.scale = Vector3.ONE * maxf(sc, 0.01)
	if gathering:
		# the eyes open as it breathes in, then it blows
		_eye_mat.emission_energy_multiplier = lerpf(0.5, 3.0, clampf(1.0 - until / warn, 0.0, 1.0))
	else:
		_eye_mat.emission_energy_multiplier = 3.0
	if _scarf.emitting != crossing:
		_scarf.emitting = crossing
	if _gather.emitting != gathering:
		_gather.emitting = gathering
	var e: float = strength_at(t)
	_streaks.amount_ratio = 0.08 + 0.92 * e
	_streaks.speed_scale = 0.6 + 0.8 * e
	if gathering and not _was_gathering:
		# SOUND: olympus_spirit_call - a rising whistle as the spirit draws breath upwind (the tell, `warn` s ahead)
		WorldAudio.at(self, "olympus_spirit_call", global_position - _along * _span * 0.4, 0.8, maxf(size.x, size.z) + 20.0)
	_was_gathering = gathering
	if active and not _was_active:
		# SOUND: olympus_spirit_gust - the rush of the gust sweeping the lane
		WorldAudio.at(self, "olympus_spirit_gust", global_position, 1.0, maxf(size.x, size.z) + 20.0)
	_was_active = active
	if _wind != null:
		WorldAudio.set_active(_wind, e > 0.03)
		_wind.volume_db = -10.0 + linear_to_db(maxf(e, 0.02))


func _build_visual() -> void:
	var z: Vector3 = _along
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	var across: float = maxf(absf(size.dot(x.abs())), 1.0)
	var vis := AABB(-size * 0.5 - Vector3(8, 4, 8), size + Vector3(16, 8, 16))
	_front = Node3D.new()
	add_child(_front)
	# the spirit's face: a puffed pale head, glowing eyes, a round blowing mouth, facing downwind
	_face = Node3D.new()
	_face.position = Vector3(0, 0.0, 0)
	_front.add_child(_face)
	_face_mat = StandardMaterial3D.new()
	_face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_face_mat.albedo_color = Color(MIST.r, MIST.g, MIST.b, 0.5)
	_face_mat.disable_receive_shadows = true
	var head := Look.sphere(0.95, _face_mat)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face.add_child(head)
	for side: float in [-1.0, 1.0]:
		var cheek := Look.sphere(0.5, _face_mat, Vector3(0, -0.15, 0) + x * side * 0.62 + z * 0.35)
		cheek.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_face.add_child(cheek)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = SKY
	_eye_mat.emission_enabled = true
	_eye_mat.emission = SKY
	_eye_mat.emission_energy_multiplier = 3.0
	for side2: float in [-1.0, 1.0]:
		var eye := Look.sphere(0.13, _eye_mat, Vector3(0, 0.25, 0) + x * side2 * 0.34 + z * 0.8)
		eye.scale = Vector3(1.0, 1.4, 1.0)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_face.add_child(eye)
	var mouth_mat := StandardMaterial3D.new()
	mouth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mouth_mat.albedo_color = Color(0.3, 0.5, 0.78)
	var mouth := Look.sphere(0.2, mouth_mat, Vector3(0, -0.28, 0) + z * 0.88)
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face.add_child(mouth)
	# the scarf: ribbons of mist streaming back from the spirit as it runs (world-space, so they trail)
	_scarf = Fx.emitter({"amount": 60, "lifetime": 1.0, "emitting": false, "local": false,
		"shape": "sphere", "radius": 0.5, "dir": -z + Vector3(0, 0.1, 0), "spread": 25.0, "speed": Vector2(1.0, 3.0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.0, "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-80, 80), "turbulence": 0.6, "color": Color(1.0, 1.0, 1.0, 0.6),
		"fade": PackedFloat32Array([0.0, 0.7, 0.0]), "aabb": AABB(Vector3(-200, -60, -200), Vector3(400, 120, 400))})
	_front.add_child(_scarf)
	# wisps spiralling into the spirit while it gathers
	_gather = Fx.emitter({"amount": 40, "lifetime": 0.9, "emitting": false, "local": true, "shape": "sphere", "radius": 2.6,
		"speed": Vector2.ZERO, "radial": Vector2(-8.0, -5.0), "tex": Fx.Tex.DOT, "size": 0.2,
		"pick": PackedColorArray([Fx.hot(SKY, 1.8), Color(1.6, 1.7, 1.8)]), "curve": "pop", "aabb": vis})
	_front.add_child(_gather)
	# streaks of mist blowing through the lane while it blows (thin when calm)
	_streaks = Fx.emitter({"amount": int(clampf(size.x * size.z * 0.12, 40, 150)), "lifetime": 1.4, "local": true,
		"shape": "box", "extents": size * 0.5, "dir": _along, "spread": 6.0, "speed": Vector2(10.0, 16.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.04, 0.55),
		"color": Color(1.0, 1.0, 1.0, 0.5), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	add_child(_streaks)
	# a ring of low cloud-swirl at the upwind end marks where it starts
	var mark := Fx.emitter({"amount": int(clampf(across * 1.2, 8, 30)), "lifetime": 3.0, "preprocess": 3.0, "local": true,
		"shape": "box", "extents": Vector3(0.3, 0.1, 0.3) + x.abs() * across * 0.5, "offset": -_along * _span * 0.5 - Vector3(0, size.y * 0.35, 0),
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.2, 0.7), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.2,
		"curve": "puff", "color": Color(1.0, 1.0, 1.0, 0.35), "fade": PackedFloat32Array([0.0, 0.7, 0.0]), "aabb": vis})
	add_child(mark)
