class_name AbyssLeviathan
extends Area3D
## The Abyss set piece: THE LEVIATHAN. Something enormous patrols the trench floor - you only ever
## see a wall of darkness sliding past, rows of pale lights along its flank and one huge eye. On a
## fixed rhythm (Game.course_time) it sweeps by beside the path, and the water it shoves ahead of
## it - its SURGE - races across the stage and pushes everything sideways. Feet on the ground you
## can hold on (friction wins); in the air it carries you off the posts. It is told well ahead:
## for `warn` seconds before the surge its eye opens and its lights wake in the dark upstream, it
## moans, and a wall of stirred-up silt gathers at the upwind edge; then the front crosses in
## `travel` seconds, it blows for `hold` seconds behind it, and dies away.
## Centre position; `push` is the peak acceleration in the node's local axes (the front travels
## along it). The creature passes along local Z on the upwind (-push) side, `distance` m out.

@export var size: Vector3 = Vector3(16, 8, 30)
@export var push: Vector3 = Vector3(30, 0, 0)
@export var period: float = 7.0
@export var phase: float = 0.0
@export var travel: float = 0.5
@export var hold: float = 1.4
@export var warn: float = 1.4
@export var distance: float = 16.0

const RAMP_UP: float = 0.15
const RAMP_DOWN: float = 0.4

var _along: Vector3 = Vector3.RIGHT
var _span: float = 1.0
var _beast: Node3D
var _lights_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _eye_light: OmniLight3D
var _front: GPUParticles3D
var _gather: GPUParticles3D
var _streaks: GPUParticles3D
var _was_active: bool = false
var _was_warn: bool = false
var _rush: AudioStreamPlayer3D


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
	# SOUND: abyss_surge_loop - the roar of displaced water while the surge blows (loop)
	_rush = WorldAudio.loop("abyss_surge_loop", self, -10.0, maxf(size.x, size.z) * 0.5 + 16.0, 6.0, false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_active = is_active_at(Game.course_time)
	_was_warn = false
	_apply(Game.course_time)


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


func duration() -> float:
	return travel + RAMP_UP + hold + RAMP_DOWN


func strength_at_lx(time: float, lx: float) -> float:
	var s: float = _s(time)
	var tau: float = s - travel * clampf((lx + _span * 0.5) / _span, 0.0, 1.0)
	return maxf(_env(tau), _env(tau + period))


func strength_at_point(time: float, world: Vector3) -> float:
	return strength_at_lx(time, to_local(world).dot(_along))


func is_active_at(time: float) -> bool:
	var s: float = _s(time)
	return s < duration() or s + period < duration()


## No surge anywhere for the whole of [time + a, time + b].
func calm_between(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_active_at(time + s):
			return false
		s += 0.04
	return not is_active_at(time + b)


func time_until_surge(time: float) -> float:
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
	var warning: bool = not active and until < warn
	# the beast glides past along local Z on the upwind side: it comes out of the dark upstream as
	# the warning starts, is level with the stage as the surge breaks, and slides away downstream
	var k: float = 0.0
	var vis: bool = false
	if warning:
		k = -(until / warn)
		vis = true
	elif s < duration() + 1.5:
		k = s / (duration() + 1.5)
		vis = true
	_beast.visible = vis
	if vis:
		var reach: float = size.z * 0.5 + 40.0
		_beast.position = -_along * (_span * 0.5 + distance) + _cross() * k * reach + Vector3(0, -2.0, 0)
	var wake: float = 0.0
	if warning:
		wake = 1.0 - until / warn
	elif active:
		wake = 1.0
	elif s < duration() + 1.5:
		wake = 1.0 - (s - duration()) / 1.5
	_lights_mat.emission_energy_multiplier = 0.2 + 2.6 * clampf(wake, 0.0, 1.0)
	_eye_mat.emission_energy_multiplier = 0.3 + 5.0 * clampf(wake, 0.0, 1.0)
	_eye_light.light_energy = 3.0 * clampf(wake, 0.0, 1.0)
	if _gather.emitting != warning:
		_gather.emitting = warning
	var e: float = 0.0
	for i: int in 5:
		e = maxf(e, strength_at_lx(t, -_span * 0.5 + _span * float(i) / 4.0))
	_streaks.amount_ratio = 0.05 + 0.95 * e
	if warning != _was_warn:
		_was_warn = warning
		if warning:
			# SOUND: abyss_leviathan_moan - a vast, low moan out of the dark upstream (the surge's tell, ~1.4 s ahead)
			WorldAudio.at(self, "abyss_leviathan_moan", global_position - _along * (_span * 0.5 + distance), 1.0, 90.0)
	if active and not _was_active:
		_front.restart()
		# SOUND: abyss_surge_whoosh - the front of the surge breaking over the stage
		WorldAudio.at(self, "abyss_surge_whoosh", global_position, 1.0, maxf(size.x, size.z) + 20.0)
	_was_active = active
	if _rush != null:
		WorldAudio.set_active(_rush, e > 0.03)
		_rush.volume_db = -8.0 + linear_to_db(maxf(e, 0.02))


func _cross() -> Vector3:
	return Vector3.UP.cross(_along).normalized()


func _build_visual() -> void:
	var cross: Vector3 = _cross()
	var vis := AABB(-size * 0.5 - Vector3(8, 6, 8), size + Vector3(16, 12, 16))
	# the beast: a vast dark body you only glimpse - a long flank of overlapping slabs, rows of
	# pale photophores and one huge eye near the front. It faces along `cross` (its direction of travel).
	_beast = Node3D.new()
	# local +X faces the course (downwind), -Z (the head) points along its travel (+cross)
	_beast.basis = Basis(_along, Vector3.UP, -cross)
	add_child(_beast)
	var hide_mat: StandardMaterial3D = Look.flat(Color(0.02, 0.03, 0.04), 0.7, 0.1)
	_lights_mat = StandardMaterial3D.new()
	_lights_mat.albedo_color = Color(0.5, 0.85, 1.0)
	_lights_mat.emission_enabled = true
	_lights_mat.emission = Color(0.5, 0.85, 1.0)
	_lights_mat.emission_energy_multiplier = 0.2
	_lights_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.9, 0.7, 0.3)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.65, 0.25)
	_eye_mat.emission_energy_multiplier = 0.3
	# body segments along local -Z (its head toward -Z, which is its direction of travel)
	var seg: int = 9
	for i: int in seg:
		var k: float = float(i) / float(seg - 1)
		var r: float = lerpf(5.5, 1.6, k) * (1.0 - 0.35 * pow(1.0 - k, 6.0))
		var body := Look.sphere(1.0, hide_mat, Vector3(0, -k * 1.5, float(i) * 6.5))
		body.scale = Vector3(r * 0.9, r, 5.0)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beast.add_child(body)
		# photophores in two rows along the flank facing the course
		for row: float in [0.35, -0.25]:
			var dot := Look.sphere(0.22, _lights_mat, Vector3(r * 0.86, -k * 1.5 + row * r, float(i) * 6.5))
			dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_beast.add_child(dot)
			var dot2 := Look.sphere(0.18, _lights_mat, Vector3(r * 0.86, -k * 1.5 + row * r, float(i) * 6.5 + 3.2))
			dot2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_beast.add_child(dot2)
	# a fin rising out of the dark and the tail fluke far behind
	var fin := Look.box(Vector3(0.4, 4.0, 8.0), hide_mat, Vector3(0, 5.6, 14.0))
	fin.rotation.x = 0.5
	_beast.add_child(fin)
	var fluke := Look.box(Vector3(14.0, 0.4, 4.0), hide_mat, Vector3(0, -1.5, float(seg) * 6.5 + 2.0))
	_beast.add_child(fluke)
	var eye := Look.sphere(0.8, _eye_mat, Vector3(4.6, 0.8, -2.0))
	_beast.add_child(eye)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(1.0, 0.7, 0.35)
	_eye_light.omni_range = 14.0
	_eye_light.light_energy = 0.0
	_eye_light.shadow_enabled = false
	_eye_light.position = Vector3(6.5, 0.8, -2.0)
	_beast.add_child(_eye_light)
	# the silt front gathering upwind, then rolling across with the surge
	var ext := Vector3.ONE * 0.4 + cross.abs() * size.dot(cross.abs()) * 0.5 + Vector3(0, size.y * 0.35, 0)
	_gather = Fx.emitter({"amount": int(clampf(size.dot(cross.abs()) * 2.0, 16, 60)), "lifetime": 1.2, "emitting": false,
		"local": true, "shape": "box", "extents": ext, "offset": -_along * _span * 0.5,
		"dir": _along + Vector3(0, 0.4, 0), "spread": 30.0, "speed": Vector2(0.6, 2.0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 1.8, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.28, 0.36, 0.4, 0.4), "fade": PackedFloat32Array([0.0, 0.9, 0.0]), "aabb": vis})
	add_child(_gather)
	_front = Fx.burst({"amount": int(clampf(size.dot(cross.abs()) * 3.0, 24, 90)), "lifetime": travel + 0.9,
		"explosiveness": 0.9, "local": true, "shape": "box", "extents": ext, "offset": -_along * _span * 0.5,
		"dir": _along, "spread": 8.0, "speed": Vector2(_span / maxf(travel, 0.1) * 0.9, _span / maxf(travel, 0.1) * 1.1),
		"damping": Vector2(2.0, 4.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 2.2, "curve": "puff",
		"angle": Vector2(0, 360), "color": Color(0.3, 0.4, 0.44, 0.45), "fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0]),
		"scale": Vector2(0.6, 1.2), "aabb": vis})
	add_child(_front)
	# streaks of glowing motes racing across while it blows
	var life: float = maxf(_span / 14.0, 0.3)
	_streaks = Fx.emitter({"amount": int(clampf(size.x * size.z * 0.25, 30, 140)), "lifetime": life, "preprocess": life,
		"local": true, "shape": "box", "extents": size * 0.5 * (Vector3.ONE - _along.abs()) + _along.abs() * 0.1,
		"offset": -_along * _span * 0.5, "dir": _along, "spread": 4.0, "speed": Vector2(12.0, 16.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.04, 0.9),
		"color": Color(0.7, 1.3, 1.5, 0.6), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	add_child(_streaks)
