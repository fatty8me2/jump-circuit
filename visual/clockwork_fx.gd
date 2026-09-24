class_name ClockworkFx
extends Node3D
## Clockwork Heights particle effects (owned by the level). Static builders for the
## ambient layers (brass dust, rising embers, steam) and one-shot bursts (gear sparks,
## slam dust, music-box notes, arrival flashes), plus the node itself: a trigger that
## restarts its bursts on the course clock (every racer sees the same tick) or when the
## player comes near. Style follows player_visual / wind_zone: unshaded billboard quads
## with a soft radial texture, modest amounts, fade ramps.

enum Mode { CLOCK, NEAR }

var mode: Mode = Mode.CLOCK
## CLOCK: cycle length and phase (fraction); bursts fire as the cycle passes each of `fire_at`.
var period: float = 2.0
var phase: float = 0.0
var fire_at: Array[float] = [0.0]
## NEAR: fire when the player comes within `radius`; re-arms once they are 1.6x that away.
var radius: float = 5.0
var bursts: Array[GPUParticles3D] = []

var _last_u: float = -1.0
var _armed: bool = true
var _player: Node3D


func _ready() -> void:
	add_to_group("course_clock")


func snap_to_clock() -> void:
	_last_u = -1.0


func fire() -> void:
	for b: GPUParticles3D in bursts:
		b.restart()


func _physics_process(_dt: float) -> void:
	if mode == Mode.CLOCK:
		var u: float = fposmod(Game.course_time / period + phase, 1.0)
		if _last_u >= 0.0:
			for f: float in fire_at:
				if (u >= f and _last_u < f) or (u < _last_u and (_last_u < f or u >= f)):
					fire()
					break
		_last_u = u
		return
	if _player == null or not is_instance_valid(_player):
		var lvl: Node = get_parent()
		while lvl != null and not (lvl is LevelBase):
			lvl = lvl.get_parent()
		if lvl == null or (lvl as LevelBase).player == null:
			return
		_player = (lvl as LevelBase).player
	var d: float = _player.global_position.distance_to(global_position)
	if _armed and d < radius:
		_armed = false
		fire()
	elif d > radius * 1.6:
		_armed = true


# ---- builders ---------------------------------------------------------------------------------

static var _dot_tex: GradientTexture2D


static func soft_dot() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = g
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(0.5, 0.0)
		_dot_tex.width = 64
		_dot_tex.height = 64
	return _dot_tex


## Billboard quad for particles. `glow` = additive (sparks, glints), else alpha (dust, steam).
static func quad(size: float, color: Color, glow: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = soft_dot()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	q.material = m
	return q


## Thin streak box (sparks): its long Y axis follows the velocity.
static func streak(length: float, color: Color) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.045, length, 0.045)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	bm.material = m
	return bm


static func ramp(stops: Array) -> GradientTexture1D:
	# stops: [[offset, Color], ...]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(float(s[0]))
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _fade_in_out() -> GradientTexture1D:
	return ramp([[0.0, Color(1, 1, 1, 0)], [0.2, Color(1, 1, 1, 1)], [0.75, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]])


static func _shrink_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.15))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(1.0, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Slow drifting motes filling a box (ambient brass dust, glints). Continuous.
static func motes(extent: Vector3, amount: int, color: Color, size: float = 0.14, glow: bool = true, lifetime: float = 7.0, rise: float = 0.15) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.randomness = 0.5
	p.visibility_aabb = AABB(-extent - Vector3(2, 2, 2), extent * 2.0 + Vector3(4, 4 + rise * lifetime * 2.0, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0.05, rise, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = _fade_in_out()
	p.process_material = pm
	p.draw_pass_1 = quad(size, color, glow)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Warm embers / fireflies rising out of a box, flickering. Continuous.
static func embers(extent: Vector3, amount: int, color: Color, size: float = 0.12) -> GPUParticles3D:
	var p := motes(extent, amount, color, size, true, 5.0, 0.7)
	var pm := p.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.spread = 35.0
	pm.color_ramp = ramp([[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, 1)], [0.3, Color(1, 1, 1, 0.45)], [0.5, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.5)], [1.0, Color(1, 1, 1, 0)]])
	pm.scale_curve = _shrink_curve()
	return p


## Steam plume along `dir` (continuous puffs that grow and fade).
static func steam(dir: Vector3, amount: int = 14, speed: float = 2.4, size: float = 1.1, color: Color = Color(0.92, 0.88, 0.98, 0.42), lifetime: float = 2.2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = lifetime
	p.preprocess = lifetime
	var reach: float = speed * lifetime + 4.0
	p.visibility_aabb = AABB(Vector3(-reach, -reach, -reach), Vector3(reach, reach, reach) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 14.0
	pm.initial_velocity_min = speed * 0.7
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.2, 0.6, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _grow_curve()
	pm.color_ramp = ramp([[0.0, Color(1, 1, 1, 0)], [0.15, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	p.process_material = pm
	p.draw_pass_1 = quad(size, color, false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## One-shot burst of soft puffs (slam dust, steam blasts, arrival flashes). Fire with restart().
static func puff_burst(amount: int, color: Color, speed: float = 3.0, size: float = 0.6, lifetime: float = 0.9, glow: bool = false, flat: float = 0.0, up: float = 0.4) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = lifetime
	p.explosiveness = 0.95
	var reach: float = speed * lifetime + 3.0
	p.visibility_aabb = AABB(Vector3(-reach, -reach, -reach), Vector3(reach, reach, reach) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, up, 0) if up > 0.0 else Vector3(0, 1, 0)
	pm.spread = 90.0 if up < 1.0 else 30.0
	pm.flatness = flat
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -1.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _grow_curve()
	pm.color_ramp = ramp([[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	p.process_material = pm
	p.draw_pass_1 = quad(size, color, glow)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## One-shot shower of bright sparks (gear teeth, slams, ticks). Fire with restart().
static func spark_burst(amount: int, color: Color, speed: float = 7.0, dir: Vector3 = Vector3.UP, spread: float = 60.0, lifetime: float = 0.7) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = lifetime
	p.explosiveness = 1.0
	p.randomness = 0.4
	var reach: float = speed * lifetime + 4.0
	p.visibility_aabb = AABB(Vector3(-reach, -reach * 1.5, -reach), Vector3(reach * 2.0, reach * 2.5, reach * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -16.0, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = ramp([[0.0, Color(1, 1, 1, 1)], [0.6, Color(1, 0.8, 0.5, 0.9)], [1.0, Color(1, 0.4, 0.1, 0)]])
	p.process_material = pm
	p.draw_pass_1 = streak(0.32, color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Continuous trickle of sparks (grinding gear teeth, the finish fountain).
static func spark_stream(amount: int, color: Color, speed: float = 5.0, dir: Vector3 = Vector3.UP, spread: float = 25.0, lifetime: float = 0.9) -> GPUParticles3D:
	var p := spark_burst(amount, color, speed, dir, spread, lifetime)
	p.one_shot = false
	p.emitting = true
	p.explosiveness = 0.0
	p.preprocess = lifetime
	return p
