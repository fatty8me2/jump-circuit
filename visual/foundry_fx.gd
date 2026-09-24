class_name FoundryFx
extends RefCounted
## Particle effects for Bounce Foundry (level 2): ambient embers and ash, spark
## fountains, steam jets, heat motes, and bursts that fire on the course clock
## (crusher slams, piston punches) or when the player arrives (stage gates, finish).
## All GPUParticles3D: unshaded billboard quads with a soft dot, or thin
## velocity-aligned boxes for sparks. Amounts stay modest; many small emitters.

const EMBER := Color(1.0, 0.55, 0.16)
const SPARK := Color(1.0, 0.78, 0.35)
const SLAG := Color(1.0, 0.42, 0.08)
const STEAM := Color(0.86, 0.78, 0.82)
const ASH := Color(0.55, 0.48, 0.58)

static var _dot: GradientTexture2D


static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
		_dot.width = 64
		_dot.height = 64
	return _dot


## Billboarded soft quad. additive = glowing (embers, sparks), otherwise alpha (steam, ash).
static func quad(size: float, color: Color, additive: bool) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = soft_dot()
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q


## Thin glowing box that the process material aligns with its velocity (a spark streak).
static func streak(length: float, color: Color) -> BoxMesh:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	var b := BoxMesh.new()
	b.size = Vector3(0.045, length, 0.045)
	b.material = m
	return b


static func ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i: int in stops.size():
		offs.append(float(stops[i][0]))
		cols.append(stops[i][1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func fade_ramp(peak: float = 1.0, hot: Color = Color(1, 1, 1)) -> GradientTexture1D:
	return ramp([[0.0, Color(hot.r, hot.g, hot.b, 0.0)], [0.12, Color(hot.r, hot.g, hot.b, peak)], [0.7, Color(1, 1, 1, peak * 0.7)], [1.0, Color(1, 1, 1, 0.0)]])


static func _emitter(amount: int, lifetime: float, aabb: AABB, mesh: Mesh, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = Fx.count(amount)
	p.lifetime = lifetime
	p.visibility_aabb = aabb
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _add(parent: Node3D, n: Node3D, pos: Vector3) -> void:
	n.position = pos
	parent.add_child(n)


# ---- ambient ------------------------------------------------------------------------------

## Embers rising out of the furnace air, drifting and flickering out. Box `extent` is half-size.
static func embers(parent: Node3D, center: Vector3, extent: Vector3, amount: int = 60) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0.25, 0.5, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	pm.color_ramp = ramp([[0.0, Color(1, 0.85, 0.5, 0)], [0.1, Color(1, 0.8, 0.45, 1)], [0.6, Color(1, 0.45, 0.12, 0.9)], [1.0, Color(0.8, 0.15, 0.05, 0)]])
	var p := _emitter(amount, 7.0, AABB(-extent - Vector3(6, 4, 6), extent * 2.0 + Vector3(12, 22, 12)), quad(0.22, EMBER, true), pm)
	p.preprocess = 7.0
	_add(parent, p, center)
	return p


## Slow falling ash flakes (alpha), a darker second layer under the embers.
static func ash(parent: Node3D, center: Vector3, extent: Vector3, amount: int = 40) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent
	pm.direction = Vector3(1, -0.4, 0.3)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.3, -0.35, 0.1)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = fade_ramp(0.55)
	var p := _emitter(amount, 10.0, AABB(-extent - Vector3(6, 8, 6), extent * 2.0 + Vector3(12, 12, 12)), quad(0.16, ASH, false), pm)
	p.preprocess = 10.0
	_add(parent, p, center)
	return p


## Hot shimmering motes that hang near molten things (pools, the glowing core).
static func motes(parent: Node3D, center: Vector3, extent: Vector3, amount: int = 24, color: Color = SLAG) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent
	pm.direction = Vector3.UP
	pm.spread = 90.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.25, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.color_ramp = ramp([[0.0, Color(1, 1, 1, 0)], [0.3, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]])
	var p := _emitter(amount, 3.0, AABB(-extent - Vector3(2, 2, 2), extent * 2.0 + Vector3(4, 6, 4)), quad(0.3, color, true), pm)
	p.preprocess = 3.0
	_add(parent, p, center)
	return p


# ---- set-piece emitters --------------------------------------------------------------------

## Continuous spray of spark streaks from `pos` along `dir` (grinding, pouring, welding).
static func sparks(parent: Node3D, pos: Vector3, dir: Vector3, amount: int = 24, speed: float = 6.0, spread: float = 30.0, lifetime: float = 0.8) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -14, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = ramp([[0.0, Color(1, 1, 0.85, 1)], [0.5, Color(1, 0.7, 0.3, 1)], [1.0, Color(1, 0.3, 0.05, 0)]])
	var r: float = speed * lifetime + 2.0
	var p := _emitter(amount, lifetime, AABB(Vector3(-r, -r * 1.5, -r), Vector3(r * 2.0, r * 2.5, r * 2.0)), streak(0.32, SPARK), pm)
	_add(parent, p, pos)
	return p


## Rising sparks: the smelter flue's updraft carries a stream of them.
static func rising_sparks(parent: Node3D, center: Vector3, extent: Vector3, amount: int = 40, speed: float = 5.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 1.5, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2
	pm.particle_flag_align_y = true
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = ramp([[0.0, Color(1, 0.9, 0.6, 0)], [0.1, Color(1, 0.85, 0.5, 1)], [0.7, Color(1, 0.5, 0.15, 0.9)], [1.0, Color(0.9, 0.2, 0.05, 0)]])
	var life: float = 3.2
	var p := _emitter(amount, life, AABB(-extent - Vector3(3, 1, 3), extent * 2.0 + Vector3(6, speed * life + 6.0, 6)), streak(0.26, SPARK), pm)
	p.preprocess = life
	_add(parent, p, center)
	return p


## Steam jet: soft puffs pushed out along `dir`, spreading and fading.
static func steam(parent: Node3D, pos: Vector3, dir: Vector3, amount: int = 14, speed: float = 3.0, size: float = 1.0) -> GPUParticles3D:
	var p: GPUParticles3D = _steam(dir, amount, speed, size, 14.0)
	_add(parent, p, pos)
	return p


## One-shot cloud of steam blown out sideways (a press slam, a piston stroke) - fire with restart().
static func steam_puff(amount: int = 14, speed: float = 2.5, size: float = 1.2, dir: Vector3 = Vector3.UP) -> GPUParticles3D:
	var p: GPUParticles3D = _steam(dir, amount, speed, size, 80.0 if dir == Vector3.UP else 20.0)
	p.one_shot = true
	p.explosiveness = 0.8
	p.emitting = false
	return p


static func _steam(dir: Vector3, amount: int, speed: float, size: float, spread: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.7
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 1.0
	pm.scale_max = 2.2
	pm.scale_curve = _grow_curve()
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.color_ramp = ramp([[0.0, Color(1, 1, 1, 0)], [0.15, Color(1, 1, 1, 0.45)], [1.0, Color(1, 1, 1, 0)]])
	var r: float = speed * 2.5 + 3.0
	return _emitter(amount, 2.2, AABB(Vector3(-r, -2, -r), Vector3(r * 2.0, r + 4.0, r * 2.0)), quad(size, STEAM, false), pm)


static func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


## One-shot burst of spark streaks (and a flash of glow puffs) - fire it with restart().
static func burst(amount: int = 40, speed: float = 8.0, color: Color = SPARK, up: float = 0.5, flat: float = 0.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0 if up <= 0.0 else 70.0
	pm.flatness = flat
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -16, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = ramp([[0.0, Color(1, 1, 0.9, 1)], [0.4, Color(1, 0.75, 0.35, 1)], [1.0, Color(1, 0.25, 0.05, 0)]])
	var r: float = speed * 1.4 + 3.0
	var p := _emitter(amount, 1.0, AABB(Vector3(-r, -r * 1.5, -r), Vector3(r * 2.0, r * 2.5, r * 2.0)), streak(0.3, color), pm)
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	return p


## Big, slow glowing flakes for celebration bursts (checkpoint gates, the finish).
static func glitter(amount: int, speed: float, color: Color) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -5, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = ramp([[0.0, Color(1, 1, 1, 1)], [0.6, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0)]])
	var r: float = speed * 2.0 + 4.0
	var p := _emitter(amount, 1.8, AABB(Vector3(-r, -r, -r), Vector3(r * 2.0, r * 2.5, r * 2.0)), quad(0.32, color, true), pm)
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	return p


# ---- triggered bursts --------------------------------------------------------------------

## Fires its bursts each time the course clock crosses `at_u` of a cycle
## (fposmod(t / period + phase, 1)) - e.g. a crusher's slam or a piston's punch.
class ClockBurst extends Node3D:
	var period: float = 3.0
	var phase: float = 0.0
	var at_u: float = 0.5
	var bursts: Array[GPUParticles3D] = []
	var _last_u: float = -1.0

	func _physics_process(_dt: float) -> void:
		var u: float = fposmod(Game.course_time / period + phase, 1.0)
		if _last_u >= 0.0:
			var crossed: bool = (_last_u < at_u and at_u <= u) if u >= _last_u else (_last_u < at_u or at_u <= u)
			# a restart (clock back to 0) jumps u backwards by a lot: not a crossing
			if crossed and fposmod(u - _last_u, 1.0) < 0.25:
				for b: GPUParticles3D in bursts:
					b.restart()
		_last_u = u


## Fires its bursts when the player comes within `radius` (then waits for them to leave).
class NearBurst extends Node3D:
	var radius: float = 3.0
	var repeat: float = 0.0          # > 0: keep firing every `repeat` s while the player is near
	var bursts: Array[GPUParticles3D] = []
	var _inside: bool = false
	var _next: float = 0.0
	var _level: LevelBase

	func _ready() -> void:
		var n: Node = get_parent()
		while n != null and not (n is LevelBase):
			n = n.get_parent()
		_level = n as LevelBase

	func _physics_process(dt: float) -> void:
		if _level == null or _level.player == null:
			return
		var near: bool = _level.player.global_position.distance_to(global_position) <= radius
		_next -= dt
		if near and (not _inside or (repeat > 0.0 and _next <= 0.0)):
			for b: GPUParticles3D in bursts:
				b.restart()
			_next = repeat
		_inside = near


static func clock_burst(parent: Node3D, pos: Vector3, period: float, phase: float, at_u: float, bursts: Array[GPUParticles3D]) -> ClockBurst:
	var c := ClockBurst.new()
	c.period = period
	c.phase = phase
	c.at_u = at_u
	for b: GPUParticles3D in bursts:
		c.add_child(b)
		c.bursts.append(b)
	_add(parent, c, pos)
	return c


static func near_burst(parent: Node3D, pos: Vector3, radius: float, bursts: Array[GPUParticles3D], repeat: float = 0.0) -> NearBurst:
	var n := NearBurst.new()
	n.radius = radius
	n.repeat = repeat
	for b: GPUParticles3D in bursts:
		n.add_child(b)
		n.bursts.append(b)
	_add(parent, n, pos)
	return n
