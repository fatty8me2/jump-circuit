class_name BalanceFx
extends RefCounted
## Particle recipes for Balance Works (level 3): sea spray over the kill water, drifting
## yard glints, wind streaks, trolley / pulley sparks, steam, stage-clear bursts.
## All GPUParticles3D with soft unshaded billboard quads and explicit visibility AABBs.
## ProximityBurst / ClockBurst fire one-shot effects when the player arrives or when a
## machine hits a beat of the course clock.

static var _soft: GradientTexture2D
static var _hard: GradientTexture2D


static func soft_tex() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.width = 64
		_soft.height = 64
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(0.5, 0.0)
	return _soft


## Small bright dot with a hot core (sparks, glints).
static func spark_tex() -> GradientTexture2D:
	if _hard == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
		_hard = GradientTexture2D.new()
		_hard.gradient = g
		_hard.width = 32
		_hard.height = 32
		_hard.fill = GradientTexture2D.FILL_RADIAL
		_hard.fill_from = Vector2(0.5, 0.5)
		_hard.fill_to = Vector2(0.5, 0.0)
	return _hard


static func quad_mat(color: Color, additive: bool = false, sharp: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = spark_tex() if sharp else soft_tex()
	m.disable_receive_shadows = true
	return m


static func ramp(colors: PackedColorArray, offsets: PackedFloat32Array = PackedFloat32Array()) -> GradientTexture1D:
	var g := Gradient.new()
	if offsets.is_empty():
		offsets.resize(colors.size())
		for i: int in colors.size():
			offsets[i] = float(i) / float(maxi(colors.size() - 1, 1))
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _base(amount: int, lifetime: float, quad: float, mat: StandardMaterial3D, aabb: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.visibility_aabb = aabb
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	q.material = mat
	p.draw_pass_1 = q
	return p


## Sea spray / mist hanging over kill water: big faint puffs drifting up and downwind.
static func mist(size: Vector3, color: Color = Color(0.85, 1.0, 0.97), amount: int = 14) -> GPUParticles3D:
	var p := _base(amount, 6.0, 1.0, quad_mat(color), AABB(Vector3(-size.x, -2, -size.z), Vector3(size.x * 2.0, 10, size.z * 2.0)))
	p.preprocess = 6.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(size.x * 0.5, 0.2, size.z * 0.5)
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.25, 0.05, 0)
	pm.scale_min = 1.6
	pm.scale_max = 3.4
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.color_ramp = ramp(PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.34), Color(1, 1, 1, 0)]), PackedFloat32Array([0.0, 0.35, 1.0]))
	p.process_material = pm
	return p


## Drifting glints: tiny twinkling motes that wander through a volume (yard dust in the sun).
static func motes(size: Vector3, color: Color, amount: int = 24, quad: float = 0.12) -> GPUParticles3D:
	var p := _base(amount, 7.0, quad, quad_mat(color, true, true), AABB(-size, size * 2.0))
	p.preprocess = 7.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5
	pm.direction = Vector3(0.4, 0.3, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.15, 0.08, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = ramp(PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]))
	p.process_material = pm
	return p


## Wind streaks flying along `dir` through a box (thin boxes aligned to their velocity).
static func streaks(size: Vector3, dir: Vector3, color: Color = Color(1, 1, 1, 0.3), amount: int = 20, speed: float = 9.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	var along: Vector3 = dir.normalized()
	var span: float = maxf(absf(size.dot(along.abs())), 1.0)
	p.lifetime = span / speed
	p.preprocess = p.lifetime
	p.visibility_aabb = AABB(-size, size * 2.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5 * (Vector3.ONE - along.abs()) + along.abs() * 0.1
	pm.emission_shape_offset = -along * span * 0.5
	pm.direction = along
	pm.spread = 4.0
	pm.initial_velocity_min = speed * 0.8
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.particle_flag_align_y = true
	pm.color_ramp = ramp(PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]), PackedFloat32Array([0.0, 0.2, 0.7, 1.0]))
	p.process_material = pm
	var m := BoxMesh.new()
	m.size = Vector3(0.04, 1.3, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	m.material = mat
	p.draw_pass_1 = m
	return p


## Spark shower (grinding wheels, laser emitters, welding): bright, fast, falling.
static func sparks(color: Color = Color(1.0, 0.8, 0.35), amount: int = 16, speed: float = 3.5, lifetime: float = 0.7, dir: Vector3 = Vector3(0, 1, 0), spread: float = 60.0) -> GPUParticles3D:
	var p := _base(amount, lifetime, 0.09, quad_mat(color, true, true), AABB(Vector3(-4, -6, -4), Vector3(8, 9, 8)))
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = ramp(PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.7, 0.4, 0.9), Color(1, 0.4, 0.2, 0)]))
	p.process_material = pm
	return p


## Soft rising steam / dust puffs (hydraulics, counterweights, slam dust).
static func steam(color: Color = Color(0.95, 1.0, 1.0), amount: int = 12, speed: float = 1.8, lifetime: float = 1.6, spread: float = 30.0, dir: Vector3 = Vector3.UP) -> GPUParticles3D:
	var p := _base(amount, lifetime, 0.7, quad_mat(color), AABB(Vector3(-6, -3, -6), Vector3(12, 12, 12)))
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.2, 0.6, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.6
	pm.scale_min = 0.8
	pm.scale_max = 2.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.color_ramp = ramp(PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)]), PackedFloat32Array([0.0, 0.15, 1.0]))
	p.process_material = pm
	return p


## One-shot radial burst (stage-clear confetti, slam dust ring, portal arrival).
static func burst(color: Color, amount: int = 40, speed: float = 6.0, lifetime: float = 1.2, flat: float = 0.0, gravity: float = -6.0, quad: float = 0.18) -> GPUParticles3D:
	var p := _base(amount, lifetime, quad, quad_mat(color, true, true), AABB(Vector3(-10, -6, -10), Vector3(20, 16, 20)))
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.flatness = flat
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.hue_variation_min = -0.04
	pm.hue_variation_max = 0.04
	pm.color_ramp = ramp(PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]))
	p.process_material = pm
	return p


## Fires its one-shot children when the level's player comes within `radius` (re-arms once they leave).
class ProximityBurst extends Node3D:
	var radius: float = 3.0
	var _armed: bool = true
	var _player: Node3D

	func _physics_process(_dt: float) -> void:
		if _player == null or not is_instance_valid(_player):
			var n: Node = get_parent()
			while n != null and not (n is LevelBase):
				n = n.get_parent()
			if n == null or (n as LevelBase).player == null:
				return
			_player = (n as LevelBase).player
		var d: float = global_position.distance_to(_player.global_position)
		if _armed and d < radius:
			_armed = false
			for c: Node in get_children():
				if c is GPUParticles3D:
					(c as GPUParticles3D).restart()
		elif not _armed and d > radius * 2.0:
			_armed = true


## Fires its one-shot children on every rising edge of `trigger.call(course_time)`.
class ClockBurst extends Node3D:
	var trigger: Callable
	var _was: bool = true

	func _physics_process(_dt: float) -> void:
		if not trigger.is_valid():
			return
		var now: bool = bool(trigger.call(Game.course_time))
		if now and not _was:
			for c: Node in get_children():
				if c is GPUParticles3D:
					(c as GPUParticles3D).restart()
		_was = now
