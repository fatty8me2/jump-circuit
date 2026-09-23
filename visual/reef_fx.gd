class_name ReefFx
extends RefCounted
## Coral Depths particle factory: soft motes, bubbles, marine snow, plankton glints,
## vent plumes and one-shot bursts. Unshaded billboards with soft textures, modest
## amounts; every emitter gets a visibility AABB that covers where its particles go.

static var _dot: GradientTexture2D
static var _ring: GradientTexture2D
static var _mats: Dictionary = {}


static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.width = 64
		_dot.height = 64
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
	return _dot


## A bubble: clear middle, bright rim, a highlight fleck.
static func bubble_tex() -> GradientTexture2D:
	if _ring == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 0.9, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		_ring = GradientTexture2D.new()
		_ring.gradient = g
		_ring.width = 64
		_ring.height = 64
		_ring.fill = GradientTexture2D.FILL_RADIAL
		_ring.fill_from = Vector2(0.5, 0.5)
		_ring.fill_to = Vector2(0.5, 0.0)
	return _ring


static func fade_ramp(color: Color, peak: float = 1.0) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	g.colors = PackedColorArray([Color(color.r, color.g, color.b, 0.0), Color(color.r, color.g, color.b, peak), Color(color.r, color.g, color.b, peak * 0.8), Color(color.r, color.g, color.b, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _material(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var key: String = "%d:%s" % [tex.get_instance_id(), str(additive)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = tex
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mats[key] = m
	return m


static func dot_quad(size: float, additive: bool = true) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _material(soft_dot(), additive)
	return q


static func bubble_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _material(bubble_tex(), false)
	return q


static func _emitter(amount: int, lifetime: float, aabb: AABB, local: bool = false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = local
	p.visibility_aabb = aabb
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Marine snow: pale flecks sinking slowly through a box, wobbling on the current.
static func marine_snow(extent: Vector3, amount: int = 70) -> GPUParticles3D:
	var p := _emitter(amount, 14.0, AABB(-extent * 0.5 - Vector3(2, 6, 2), extent + Vector3(4, 8, 4)))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent * 0.5
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0.05, -0.12, 0.02)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color_ramp = fade_ramp(Color(0.85, 0.97, 1.0), 0.75)
	p.process_material = pm
	p.draw_pass_1 = dot_quad(0.12, false)
	return p


## Plankton glints: tiny bright motes that drift and twinkle (additive).
static func plankton(extent: Vector3, color: Color, amount: int = 40) -> GPUParticles3D:
	var p := _emitter(amount, 6.0, AABB(-extent * 0.5 - Vector3(3, 3, 3), extent + Vector3(6, 6, 6)))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent * 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.35, 0.5, 0.7, 1.0])
	g.colors = PackedColorArray([Color(color.r, color.g, color.b, 0), Color(color.r, color.g, color.b, 1), Color(color.r, color.g, color.b, 0.3),
			Color(color.r, color.g, color.b, 1), Color(color.r, color.g, color.b, 0.4), Color(color.r, color.g, color.b, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = dot_quad(0.16, true)
	return p


## A rising stream of bubbles from a point (vents, clams, coral crevices).
static func bubble_stream(height: float = 10.0, amount: int = 14, spread_r: float = 0.25, size: float = 0.22) -> GPUParticles3D:
	var life: float = height / 1.8
	var p := _emitter(amount, life, AABB(Vector3(-3, -1, -3), Vector3(6, height + 3, 6)))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = spread_r
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.25, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.1
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	pm.scale_curve = _grow_curve()
	pm.color_ramp = fade_ramp(Color(0.85, 1.0, 1.0), 0.9)
	p.process_material = pm
	p.draw_pass_1 = bubble_quad(size)
	return p


static func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


## One-shot burst (restart() it to fire). Bubbles or glow sparks thrown outward.
static func burst(color: Color, amount: int = 24, speed: float = 4.0, bubbles: bool = true, size: float = 0.3, radius: float = 0.4) -> GPUParticles3D:
	var p := _emitter(amount, 1.1, AABB(Vector3(-8, -4, -8), Vector3(16, 14, 16)))
	p.preprocess = 0.0
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.92
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 2.0 if bubbles else -1.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 3.5
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = fade_ramp(color, 1.0)
	p.process_material = pm
	p.draw_pass_1 = bubble_quad(size) if bubbles else dot_quad(size, true)
	return p


## Hydrothermal shimmer: warm glowing motes rising and fading over a vent mouth.
static func vent_glow(color: Color, amount: int = 16) -> GPUParticles3D:
	var p := _emitter(amount, 2.2, AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6)))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.color_ramp = fade_ramp(color, 0.7)
	p.process_material = pm
	p.draw_pass_1 = dot_quad(0.45, true)
	return p
