class_name AscentFx
extends Node3D
## THE FINAL ASCENT's particle effects (neon night spire).
## Static builders make the ambient layers (rising neon motes, falling data rain, beacon embers);
## an AscentFx node is a triggered burst: it restarts its one-shot emitters every time `trigger`
## flips from false to true (course-clock events like a press slamming or a ram punching, or the
## player arriving somewhere), or when fire() is called.

## Returns true while the event is "on"; the burst fires on the rising edge.
var trigger: Callable
var _was: bool = false
var _shots: Array[GPUParticles3D] = []

static var _dot: GradientTexture2D


func _ready() -> void:
	for c: Node in get_children():
		if c is GPUParticles3D and (c as GPUParticles3D).one_shot:
			_shots.append(c as GPUParticles3D)
	if trigger.is_valid():
		_was = bool(trigger.call())


func fire() -> void:
	for p: GPUParticles3D in _shots:
		p.restart()


func _physics_process(_dt: float) -> void:
	if not trigger.is_valid():
		return
	var now: bool = bool(trigger.call())
	if now and not _was:
		fire()
	_was = now


# ---- building blocks ------------------------------------------------------------------------------

static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
		_dot.width = 64
		_dot.height = 64
	return _dot


## Unshaded additive quad, tinted by the particle colour. `streak` = a thin vertical line that stays upright.
static func _quad(size: Vector2, streak: bool = false) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	if streak:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
	else:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = soft_dot()
	q.material = m
	return q


## Colour over life: fade in, hold, fade out (alpha only).
static func _ramp(col: Color, peak: float = 1.0, fade_in: float = 0.15) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, fade_in, 0.7, 1.0])
	g.colors = PackedColorArray([Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, peak), Color(col.r, col.g, col.b, peak * 0.7), Color(col.r, col.g, col.b, 0.0)])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _emitter(amount: int, life: float, extents: Vector3, quad: QuadMesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(-extents - Vector3(6, 6, 6), extents * 2.0 + Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	p.process_material = pm
	p.draw_pass_1 = quad
	return p


# ---- ambient layers -------------------------------------------------------------------------------

## Neon motes: slow glints drifting up around the spire, twinkling as they go.
static func motes(center: Vector3, extents: Vector3, col: Color, amount: int = 32, size: float = 0.16) -> GPUParticles3D:
	var p := _emitter(amount, 6.0, extents, _quad(Vector2(size, size)))
	p.preprocess = 6.0
	p.position = center
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0.15, 0.12, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = _ramp(col, 1.0, 0.25)
	return p


## Data rain: thin cyan streaks falling past the route (a curtain beside it, never on it).
static func rain(center: Vector3, extents: Vector3, col: Color, amount: int = 48) -> GPUParticles3D:
	var p := _emitter(amount, 1.6, extents, _quad(Vector2(0.035, 0.9), true))
	p.preprocess = 1.6
	p.position = center
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_box_extents = Vector3(extents.x, 0.2, extents.z)
	p.position = center + Vector3(0, extents.y, 0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = _ramp(col, 0.8, 0.1)
	return p


## Sparks shooting up and falling back (the data uplinks, the beacon).
static func fountain(center: Vector3, col: Color, amount: int = 40, speed: float = 6.0, radius: float = 0.4) -> GPUParticles3D:
	var p := _emitter(amount, 1.3, Vector3(radius, 0.1, radius), _quad(Vector2(0.12, 0.12)))
	p.position = center
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.2
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.color_ramp = _ramp(col, 1.0, 0.05)
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, speed * speed / 9.0 + 12.0, 16))
	return p


# ---- triggered bursts -----------------------------------------------------------------------------

## One-shot spray at `pos`: `dir` ZERO = all round (flattened), else a cone along dir. Fires on trigger's rising edge.
static func burst(pos: Vector3, col: Color, when: Callable, amount: int = 36, speed: float = 6.0, dir: Vector3 = Vector3.ZERO, life: float = 0.7, size: float = 0.14) -> AscentFx:
	var fx := AscentFx.new()
	fx.position = pos
	fx.trigger = when
	var p := _emitter(amount, life, Vector3(0.25, 0.1, 0.25), _quad(Vector2(size, size)))
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.92
	var pm := p.process_material as ParticleProcessMaterial
	if dir == Vector3.ZERO:
		pm.direction = Vector3(0, 0.3, 0)
		pm.spread = 180.0
		pm.flatness = 0.7
	else:
		pm.direction = dir.normalized()
		pm.spread = 28.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -7.0, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = _ramp(col, 1.0, 0.02)
	fx.add_child(p)
	return fx


## Add a soft puff (steam / dust cloud) to a burst node: big slow quads.
static func add_puff(fx: AscentFx, col: Color, amount: int = 14, dir: Vector3 = Vector3.UP, speed: float = 2.5) -> void:
	var p := _emitter(amount, 1.1, Vector3(0.4, 0.3, 0.4), _quad(Vector2(0.9, 0.9)))
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.8
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized()
	pm.spread = 40.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.color_ramp = _ramp(col, 0.45, 0.1)
	fx.add_child(p)
