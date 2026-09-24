class_name OrbitalFx
extends RefCounted
## Orbital Drift particle kit: every emitter is a GPUParticles3D of small unshaded,
## additive billboard dots (the soft radial texture), with its visibility AABB sized
## to what it can actually reach so nothing is culled while on screen.


static func _mat(color: Color = Color.WHITE, additive: bool = true, billboard: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = OrbitalGravityBay._dot()
	m.disable_receive_shadows = true
	return m


static func _ramp(colors: Array, offsets: Array = []) -> GradientTexture1D:
	var g := Gradient.new()
	if offsets.is_empty():
		var o := PackedFloat32Array()
		for i: int in colors.size():
			o.append(float(i) / float(colors.size() - 1))
		g.offsets = o
	else:
		g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _node(parent: Node3D, pos: Vector3, amount: int, lifetime: float, pm: ParticleProcessMaterial, quad: float, mat: StandardMaterial3D, aabb: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = lifetime
	p.process_material = pm
	p.visibility_aabb = aabb
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	q.material = mat
	p.draw_pass_1 = q
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Floating station dust: tiny specks drifting every which way in a box (ambient layer 1).
static func dust(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 60, color: Color = Color(0.85, 0.9, 1.0)) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.3, 0.2, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	var p := _node(parent, center, amount, 9.0, pm, 0.09, _mat(color), AABB(-extents - Vector3.ONE * 4.0, extents * 2.0 + Vector3.ONE * 8.0))
	p.preprocess = 9.0
	p.local_coords = true
	return p


## Ion glints: fewer, bigger, coloured motes that twinkle on and off (ambient layer 2).
static func glints(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 24, color: Color = Color(0.4, 0.9, 1.0)) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var p := _node(parent, center, amount, 4.0, pm, 0.2, _mat(color), AABB(-extents - Vector3.ONE * 3.0, extents * 2.0 + Vector3.ONE * 6.0))
	p.preprocess = 4.0
	p.local_coords = true
	return p


## Far micrometeor streaks crossing the sky around the station (ambient layer 3).
static func streaks(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 14) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(1, -0.25, 0.4)
	pm.spread = 12.0
	pm.initial_velocity_min = 60.0
	pm.initial_velocity_max = 110.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 0.95, 0.85, 1), Color(1.0, 0.6, 0.3, 0)])
	var p := GPUParticles3D.new()
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = 1.4
	p.randomness = 0.6
	p.process_material = pm
	p.visibility_aabb = AABB(-extents - Vector3.ONE * 200.0, extents * 2.0 + Vector3.ONE * 400.0)
	var m := BoxMesh.new()
	m.size = Vector3(0.25, 9.0, 0.25)
	m.material = _mat(Color(1, 1, 1, 0.8), true, false)
	p.draw_pass_1 = m
	p.position = center
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Decorative engine / RCS exhaust along local +Y of `basis` (station modules, the docked ship).
static func exhaust(parent: Node3D, pos: Vector3, dir: Vector3, length: float = 6.0, radius: float = 0.6, color: Color = Color(0.6, 0.8, 1.0)) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.5
	pm.direction = dir.normalized()
	pm.spread = 7.0
	pm.initial_velocity_min = length * 1.6
	pm.initial_velocity_max = length * 2.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = radius * 2.2
	pm.scale_max = radius * 3.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(color.r, color.g, color.b, 0.9), Color(color.r * 0.8, color.g * 0.6, color.b, 0.35), Color(0.3, 0.3, 0.5, 0)], [0.0, 0.08, 0.5, 1.0])
	var p := _node(parent, pos, 50, 0.55, pm, 1.0, _mat(), AABB(Vector3.ONE * -(length + 3.0), Vector3.ONE * (length + 3.0) * 2.0))
	p.local_coords = false
	return p


## Venting gas: slow white puffs spreading out of a pipe end.
static func vent(parent: Node3D, pos: Vector3, dir: Vector3, amount: int = 16) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 14.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.3))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(0.9, 0.95, 1.0, 0.45), Color(0.8, 0.85, 0.95, 0)], [0.0, 0.15, 1.0])
	var p := _node(parent, pos, amount, 2.6, pm, 1.2, _mat(Color.WHITE, false), AABB(Vector3.ONE * -9.0, Vector3.ONE * 18.0))
	p.preprocess = 2.6
	return p


## Sparks: a one-shot spray of hot fragments flying straight (no gravity up here) and fading.
## Call restart() on it to fire (the level fires them on the course clock / on contact).
static func sparks(parent: Node3D, pos: Vector3, dir: Vector3, amount: int = 22, color: Color = Color(1.0, 0.75, 0.35), speed: float = 7.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 55.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.particle_flag_align_y = true
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(color.r, color.g, color.b, 1), Color(color.r, color.g * 0.5, color.b * 0.3, 0)], [0.0, 0.3, 1.0])
	var p := GPUParticles3D.new()
	p.amount = Fx.count(roundi(amount * Fx.LEVEL_BOOST))
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.process_material = pm
	p.visibility_aabb = AABB(Vector3.ONE * -(speed + 2.0), Vector3.ONE * (speed + 2.0) * 2.0)
	var m := BoxMesh.new()
	m.size = Vector3(0.04, 0.35, 0.04)
	m.material = _mat(Color(1, 1, 1, 1), true, false)
	p.draw_pass_1 = m
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## One-shot ring/sphere burst of glowing motes (portal arrivals, gate beacons, the finish).
static func burst(parent: Node3D, pos: Vector3, color: Color, amount: int = 40, speed: float = 6.0, size: float = 0.3, flat: bool = false) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	if flat:
		pm.flatness = 0.9
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.damping_min = speed * 0.4
	pm.damping_max = speed * 0.8
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(color.r, color.g, color.b, 0.9), Color(color.r, color.g, color.b, 0)], [0.0, 0.25, 1.0])
	var p := _node(parent, pos, amount, 1.0, pm, size, _mat(), AABB(Vector3.ONE * -(speed + 3.0), Vector3.ONE * (speed + 3.0) * 2.0))
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	return p


## A slow swirl of motes hanging round a point (portal arrival pads, the reactor core).
static func swirl(parent: Node3D, pos: Vector3, radius: float, color: Color, amount: int = 30) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.7
	pm.emission_ring_height = 0.4
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.orbit_velocity_min = 0.15
	pm.orbit_velocity_max = 0.3
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(color.r, color.g, color.b, 1), Color(color.r, color.g, color.b, 0)])
	var p := _node(parent, pos, amount, 2.4, pm, 0.16, _mat(), AABB(Vector3(-radius - 3, -1, -radius - 3), Vector3(radius * 2 + 6, 6, radius * 2 + 6)))
	p.preprocess = 2.4
	p.local_coords = true
	return p
