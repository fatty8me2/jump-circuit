class_name GardensFx
extends RefCounted
## Particle recipes for LAUNCH GARDENS (level 1): drifting pollen, falling petals, dandelion seeds,
## fireflies, hedge clippings, sprinkler drizzle, and the one-shot bursts (water spray, soil puffs,
## petal fountains, sparkle rings, fireworks) that GardensCue fires on the course clock or on
## proximity. Visual only - nothing here touches gameplay. Style follows player_visual.gd /
## wind_zone.gd: unshaded soft billboards, modest amounts, explicit visibility AABBs.

static var _soft: GradientTexture2D
static var _petal: GradientTexture2D


## Round soft dot (pollen, glints, droplets, puffs).
static func soft() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(0.5, 0.0)
		_soft.width = 32
		_soft.height = 32
	return _soft


## Harder-edged dot for petals and leaves (reads as a solid little shape, stretched by the quad).
static func petal_tex() -> GradientTexture2D:
	if _petal == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0)])
		_petal = GradientTexture2D.new()
		_petal.gradient = g
		_petal.fill = GradientTexture2D.FILL_RADIAL
		_petal.fill_from = Vector2(0.5, 0.5)
		_petal.fill_to = Vector2(0.5, 0.0)
		_petal.width = 32
		_petal.height = 32
	return _petal


static func _quad(size: Vector2, tex: Texture2D, tint: Color = Color.WHITE) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = size
	q.material = m
	return q


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Fade in, hold, fade out (alpha only; the colour comes from color / color_initial_ramp).
static func _fade(hold_from: float = 0.15, hold_to: float = 0.75) -> GradientTexture1D:
	return _ramp([0.0, hold_from, hold_to, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])


static func _emitter(amount: int, lifetime: float, box: Vector3, mesh: Mesh, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m: Vector3 = box + Vector3(6, 6, 6)
	p.visibility_aabb = AABB(-m, m * 2.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	p.process_material = pm
	p.draw_pass_1 = mesh
	return p


static func _burst_base(amount: int, lifetime: float, mesh: Mesh, pm: ParticleProcessMaterial, reach: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-reach, -reach, -reach), Vector3(reach, reach, reach) * 2.0)
	p.process_material = pm
	p.draw_pass_1 = mesh
	return p


# ---- ambient ------------------------------------------------------------------------------------

## Golden pollen motes drifting and slowly rising in a box (half-extents `box`).
static func pollen(box: Vector3, amount: int = 28) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0.12, 0.1, 0.05)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.08
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = _fade(0.2, 0.7)
	pm.color_initial_ramp = _ramp([0.0, 0.5, 1.0], [Color(1.0, 0.92, 0.45), Color(1.0, 0.98, 0.75), Color(1.0, 0.8, 0.35)])
	return _emitter(amount, 7.0, box, _quad(Vector2(0.13, 0.13), soft()), pm)


## Petals tumbling down on a light breeze. `box` is the emission volume (put it above the area).
static func petals(box: Vector3, amount: int = 18, colors: Array = []) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.5, -1, 0.2)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0.35, -0.55, 0.15)
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -140.0
	pm.angular_velocity_max = 140.0
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	pm.color_ramp = _fade(0.1, 0.85)
	var cols: Array = colors if not colors.is_empty() else [Color(1.0, 0.62, 0.72), Color(1.0, 0.86, 0.9), Color(0.98, 0.5, 0.62)]
	var offs: Array = []
	for i: int in cols.size():
		offs.append(float(i) / float(maxi(cols.size() - 1, 1)))
	pm.color_initial_ramp = _ramp(offs, cols)
	return _emitter(amount, 9.0, box, _quad(Vector2(0.24, 0.15), petal_tex()), pm)


## Dandelion seeds: white fluff riding the wind (`wind` = drift direction and speed).
static func seeds(box: Vector3, wind: Vector3, amount: int = 24) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = wind.normalized() if wind.length() > 0.01 else Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = wind.length() * 0.6
	pm.initial_velocity_max = wind.length()
	pm.gravity = Vector3(0, 0.12, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.color_ramp = _fade(0.1, 0.8)
	pm.color = Color(1, 1, 1, 0.85)
	return _emitter(amount, 8.0, box, _quad(Vector2(0.16, 0.16), soft()), pm)


## Fireflies: green-gold points that blink on and off as they wander.
static func fireflies(box: Vector3, amount: int = 20) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.2
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([0.0, 0.12, 0.3, 0.45, 0.6, 0.78, 1.0],
		[Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	pm.color = Color(0.82, 1.0, 0.45)
	return _emitter(amount, 5.0, box, _quad(Vector2(0.14, 0.14), soft()), pm)


## Fine drizzle falling from the greenhouse sprinkler pipes (thin blue-white streaks).
static func drizzle(box: Vector3, amount: int = 40) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 4.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	pm.color_ramp = _fade(0.1, 0.8)
	pm.color = Color(0.78, 0.92, 1.0, 0.55)
	var m := BoxMesh.new()
	m.size = Vector3(0.025, 0.45, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	return _emitter(amount, 1.6, box, m, pm)


## Leaves swirling UP a column (the topiary chimney's updraft).
static func leaf_updraft(box: Vector3, amount: int = 30) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, 0.4, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.25
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -200.0
	pm.angular_velocity_max = 200.0
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	pm.color_ramp = _fade(0.1, 0.75)
	pm.color_initial_ramp = _ramp([0.0, 0.5, 1.0], [Color(0.35, 0.75, 0.35), Color(0.62, 0.88, 0.4), Color(0.95, 0.8, 0.35)])
	return _emitter(amount, 4.0, box, _quad(Vector2(0.22, 0.14), petal_tex()), pm)


## Continuous spray of hedge clippings (the Trimmer's posts). Left behind in world space.
static func clippings(box: Vector3, amount: int = 26) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, -5.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.2
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.color_ramp = _fade(0.05, 0.7)
	pm.color_initial_ramp = _ramp([0.0, 0.6, 1.0], [Color(0.25, 0.6, 0.3), Color(0.45, 0.78, 0.35), Color(0.7, 0.9, 0.45)])
	var p := _emitter(amount, 1.4, box, _quad(Vector2(0.2, 0.13), petal_tex()), pm)
	p.preprocess = 0.0
	return p


# ---- one-shot bursts (fired by GardensCue) ------------------------------------------------------

## Sprinkler water spray fanning out along `dir`.
static func spray(dir: Vector3, amount: int = 46) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 22.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -14.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = _fade(0.02, 0.6)
	pm.color_initial_ramp = _ramp([0.0, 1.0], [Color(0.7, 0.88, 1.0), Color(0.95, 1.0, 1.0)])
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	return _burst_base(amount, 0.9, _quad(Vector2(0.13, 0.13), soft()), pm, 8.0)


## Soil clods and a dust ring kicked out when a potting press slams.
static func soil(amount: int = 40) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.35, 0)
	pm.spread = 88.0
	pm.flatness = 0.75
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.7
	pm.scale_max = 1.8
	pm.color_ramp = _fade(0.02, 0.55)
	pm.color_initial_ramp = _ramp([0.0, 0.5, 1.0], [Color(0.4, 0.28, 0.2), Color(0.62, 0.48, 0.34), Color(0.85, 0.76, 0.6)])
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 1.4
	pm.emission_ring_inner_radius = 1.0
	pm.emission_ring_height = 0.1
	return _burst_base(amount, 0.8, _quad(Vector2(0.24, 0.24), soft()), pm, 6.0)


## A fountain of petals shooting up and fluttering down (stage gates, pad launches).
static func petal_fountain(amount: int = 44, speed: float = 6.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 32.0
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -5.5, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.4
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.scale_min = 0.9
	pm.scale_max = 1.4
	pm.color_ramp = _fade(0.03, 0.75)
	pm.color_initial_ramp = _ramp([0.0, 0.33, 0.66, 1.0], [Color(1.0, 0.55, 0.68), Color(1.0, 0.9, 0.5), Color(1.0, 1.0, 1.0), Color(0.98, 0.6, 0.35)])
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	var p := _burst_base(amount, 2.4, _quad(Vector2(0.26, 0.17), petal_tex()), pm, 12.0)
	p.explosiveness = 0.75
	return p


## A flat ring of glints thrown outward (portal arrival, bounce launches).
static func sparkle_ring(color: Color, amount: int = 36) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.flatness = 1.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _fade(0.02, 0.6)
	pm.color = color
	return _burst_base(amount, 0.8, _quad(Vector2(0.18, 0.18), soft()), pm, 8.0)


## A firework shell: a sphere of coloured sparks that droops and fades.
static func firework(colors: Array, amount: int = 70) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -3.5, 0)
	pm.damping_min = 1.6
	pm.damping_max = 2.4
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.color_ramp = _ramp([0.0, 0.05, 0.6, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var offs: Array = []
	for i: int in colors.size():
		offs.append(float(i) / float(maxi(colors.size() - 1, 1)))
	pm.color_initial_ramp = _ramp(offs, colors)
	var p := _burst_base(amount, 1.8, _quad(Vector2(0.45, 0.45), soft()), pm, 18.0)
	p.explosiveness = 0.97
	return p
