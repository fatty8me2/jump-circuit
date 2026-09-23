class_name PartyFx
extends RefCounted
## Particle and flash toolkit for Party Mode. Everything is built from many modest
## GPUParticles3D emitters on unshaded, additive, soft round quads (cheap, and the level's
## glow turns them into light), plus short-lived OmniLight3D flashes and tweened meshes.
## Materials and textures are cached; one-shot effects free themselves.

const LAYER: int = 2   # "characters": keeps blob-shadow decals off the effects

static var _mats: Dictionary = {}
static var _tex: GradientTexture2D
static var _spark_tex: GradientTexture2D
static var _ramps: Dictionary = {}


## Drops the cached materials / textures (the party layer calls this when it leaves, so
## nothing is held after Party Mode ends; the next use rebuilds them).
static func clear_caches() -> void:
	_mats.clear()
	_ramps.clear()
	_tex = null
	_spark_tex = null


# ---- materials ------------------------------------------------------------------------

## Soft radial dot, white; tinted per particle by vertex colour.
static func dot_texture() -> GradientTexture2D:
	if _tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(0.5, 0.0)
		_tex.width = 64
		_tex.height = 64
	return _tex


## Hard-cored spark: bright centre, quick falloff.
static func spark_texture() -> GradientTexture2D:
	if _spark_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.15, Color(1, 1, 1, 0.9))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_spark_tex = GradientTexture2D.new()
		_spark_tex.gradient = g
		_spark_tex.fill = GradientTexture2D.FILL_RADIAL
		_spark_tex.fill_from = Vector2(0.5, 0.5)
		_spark_tex.fill_to = Vector2(0.5, 0.0)
		_spark_tex.width = 32
		_spark_tex.height = 32
	return _spark_tex


## Billboard particle material. additive=false gives alpha-blended smoke.
static func particle_mat(color: Color, additive: bool = true, spark: bool = false) -> StandardMaterial3D:
	var key: String = "p:%s:%s:%s" % [color.to_html(), additive, spark]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = spark_texture() if spark else dot_texture()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.no_depth_test = false
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


## Glowing solid (unshaded) for charge balls, blades, beams. alpha < 1 blends additively.
static func glow_mat(color: Color, energy: float = 2.0, additive: bool = false) -> StandardMaterial3D:
	var key: String = "g:%s:%.2f:%s" % [color.to_html(), energy, additive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	if additive or color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


## Lit, emissive part for costume pieces (tunic, cap, ears): reads as a solid object.
static func solid_mat(color: Color, emit: float = 0.0, rough: float = 0.55, metal: float = 0.0) -> StandardMaterial3D:
	var key: String = "s:%s:%.2f:%.2f:%.2f" % [color.to_html(), emit, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


## Fresh (uncached) copy of a glow material, for effects that fade their own alpha.
static func fading_mat(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m: StandardMaterial3D = glow_mat(color, energy, true).duplicate() as StandardMaterial3D
	return m


## Colour-over-life ramp from a list of colours (evenly spaced).
static func ramp(colors: Array) -> GradientTexture1D:
	var key: String = str(colors)
	if _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	g.remove_point(1)
	g.set_color(0, colors[0])
	g.set_offset(0, 0.0)
	for i: int in range(1, colors.size()):
		g.add_point(float(i) / float(colors.size() - 1), colors[i])
	var t := GradientTexture1D.new()
	t.gradient = g
	_ramps[key] = t
	return t


static func _shrink_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


static func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(0.3, 1))
	c.add_point(Vector2(1, 0.8))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


# ---- emitters ------------------------------------------------------------------------------

## Generic emitter. Keys (all optional):
##  amount, lifetime, one_shot, explosiveness, randomness, size, color, colors (ramp),
##  additive, spark, dir, spread, vmin, vmax, gravity, damping, radial (radial accel),
##  tangential, orbit, shape ("point" | "sphere" | "shell" | "ring" | "box"), radius,
##  inner, axis (ring axis), extents (box), scale_min, scale_max, shrink (bool, default true),
##  grow (bool), local (local_coords), aabb (visibility half-size), flat (flatness),
##  angle (random rotation), fixed_fps, initial (random per-particle colour ramp).
static func emitter(o: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.layers = LAYER
	p.amount = int(o.get("amount", 24))
	p.lifetime = float(o.get("lifetime", 0.6))
	p.one_shot = bool(o.get("one_shot", false))
	p.explosiveness = float(o.get("explosiveness", 0.0))
	p.randomness = float(o.get("randomness", 0.3))
	p.local_coords = bool(o.get("local", false))
	p.emitting = not p.one_shot and bool(o.get("emitting", true))
	var half: float = float(o.get("aabb", 6.0))
	p.visibility_aabb = AABB(Vector3.ONE * -half, Vector3.ONE * half * 2.0)
	var pm := ParticleProcessMaterial.new()
	var shape: String = str(o.get("shape", "point"))
	match shape:
		"sphere":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = float(o.get("radius", 0.5))
		"shell":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			pm.emission_sphere_radius = float(o.get("radius", 0.5))
		"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = o.get("axis", Vector3.UP)
			pm.emission_ring_radius = float(o.get("radius", 1.0))
			pm.emission_ring_inner_radius = float(o.get("inner", float(o.get("radius", 1.0)) * 0.9))
			pm.emission_ring_height = float(o.get("height", 0.05))
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = o.get("extents", Vector3.ONE * 0.5)
		_:
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.direction = o.get("dir", Vector3.UP)
	pm.spread = float(o.get("spread", 180.0))
	pm.flatness = float(o.get("flat", 0.0))
	pm.initial_velocity_min = float(o.get("vmin", 1.0))
	pm.initial_velocity_max = float(o.get("vmax", 3.0))
	pm.gravity = o.get("gravity", Vector3.ZERO)
	var damp: float = float(o.get("damping", 0.0))
	pm.damping_min = damp * 0.7
	pm.damping_max = damp
	var radial: float = float(o.get("radial", 0.0))
	pm.radial_accel_min = radial
	pm.radial_accel_max = radial
	var tang: float = float(o.get("tangential", 0.0))
	pm.tangential_accel_min = tang
	pm.tangential_accel_max = tang
	var orbit: float = float(o.get("orbit", 0.0))
	if orbit != 0.0:
		pm.orbit_velocity_min = orbit * 0.8
		pm.orbit_velocity_max = orbit
	pm.scale_min = float(o.get("scale_min", 0.6))
	pm.scale_max = float(o.get("scale_max", 1.0))
	if bool(o.get("grow", false)):
		pm.scale_curve = _grow_curve()
	elif bool(o.get("shrink", true)):
		pm.scale_curve = _shrink_curve()
	if bool(o.get("angle", false)):
		pm.angle_min = -180.0
		pm.angle_max = 180.0
	var col: Color = o.get("color", Color.WHITE)
	if o.has("colors"):
		pm.color_ramp = ramp(o["colors"])
	else:
		pm.color_ramp = ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	if o.has("initial"):
		# a random colour per particle, picked from this ramp (confetti)
		pm.color_initial_ramp = ramp(o["initial"])
	p.process_material = pm
	var q := QuadMesh.new()
	var s: float = float(o.get("size", 0.25))
	q.size = Vector2(s, s)
	q.material = particle_mat(col, bool(o.get("additive", true)), bool(o.get("spark", false)))
	p.draw_pass_1 = q
	if o.has("fixed_fps"):
		p.fixed_fps = int(o["fixed_fps"])
	return p


## Adds `node` to `parent` at world `pos` and frees it after `life` seconds.
static func spawn(parent: Node, node: Node3D, pos: Vector3, life: float) -> Node3D:
	parent.add_child(node)
	node.global_position = pos
	auto_free(node, life)
	return node


static func auto_free(node: Node, after: float) -> void:
	if not node.is_inside_tree():
		return
	# a bound method, not a lambda: the connection dies with the node if it goes first
	node.get_tree().create_timer(after, false).timeout.connect(node.queue_free)


## One-shot emitter fired at `pos`, freed afterwards.
static func one_shot(parent: Node, pos: Vector3, o: Dictionary) -> GPUParticles3D:
	var d: Dictionary = o.duplicate()
	d["one_shot"] = true
	if not d.has("explosiveness"):
		d["explosiveness"] = 0.9
	var p: GPUParticles3D = emitter(d)
	parent.add_child(p)
	p.global_position = pos
	if d.has("basis"):
		p.global_basis = d["basis"]
	p.emitting = true
	auto_free(p, p.lifetime + 0.6)
	return p


## Round burst of glowing dots.
static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 32, speed: float = 6.0, size: float = 0.25, life: float = 0.6) -> void:
	one_shot(parent, pos, {"amount": amount, "lifetime": life, "size": size, "color": color,
		"vmin": speed * 0.4, "vmax": speed, "damping": speed * 1.2, "shape": "sphere", "radius": 0.2,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]})


## Fast bright sparks with gravity (hits, clashes, fuses).
static func sparks(parent: Node, pos: Vector3, color: Color, amount: int = 24, speed: float = 9.0, dir: Vector3 = Vector3.UP, spread: float = 180.0) -> void:
	one_shot(parent, pos, {"amount": amount, "lifetime": 0.45, "size": 0.12, "color": color, "spark": true,
		"vmin": speed * 0.5, "vmax": speed, "dir": dir, "spread": spread, "gravity": Vector3(0, -14, 0),
		"damping": 2.0, "scale_min": 0.5, "scale_max": 1.2})


## Rising puff of soft (non-additive) smoke.
static func smoke(parent: Node, pos: Vector3, color: Color = Color(0.25, 0.25, 0.28, 0.6), amount: int = 16, radius: float = 0.6, life: float = 1.2) -> void:
	one_shot(parent, pos, {"amount": amount, "lifetime": life, "size": radius * 1.4, "color": color, "additive": false,
		"vmin": 0.4, "vmax": 1.6, "dir": Vector3.UP, "spread": 60.0, "gravity": Vector3(0, 0.8, 0), "damping": 0.6,
		"shape": "sphere", "radius": radius * 0.6, "grow": true, "explosiveness": 0.7, "angle": true,
		"colors": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)]})


## Short light flash that fades out.
static func flash(parent: Node, pos: Vector3, color: Color, energy: float = 6.0, range_m: float = 8.0, time: float = 0.35) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw: Tween = l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


## Flat expanding ring on the ground (shockwave), plus a ring of dust thrown outward.
static func shockwave(parent: Node, pos: Vector3, color: Color, radius: float = 4.0, time: float = 0.45) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 6
	var mat: StandardMaterial3D = fading_mat(color, 3.0)
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.2, 0.05, 0.2)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.12, radius), time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)
	one_shot(parent, pos + Vector3(0, 0.15, 0), {"amount": 36, "lifetime": 0.55, "size": 0.35, "color": color,
		"shape": "ring", "radius": 0.4, "inner": 0.2, "dir": Vector3(1, 0.15, 0), "spread": 180.0, "flat": 1.0,
		"vmin": radius * 2.0, "vmax": radius * 3.2, "damping": radius * 3.0})


## Growing, fading sphere (fireball core, implosions with grow < 1).
static func orb_pulse(parent: Node, pos: Vector3, color: Color, from_r: float, to_r: float, time: float, energy: float = 3.0) -> void:
	var mat: StandardMaterial3D = fading_mat(color, energy)
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 24
	s.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * maxf(from_r, 0.01)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * maxf(to_r, 0.01), time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## The big one: fireball, sparks, smoke, debris, ground shockwave and a light flash.
static func explosion(parent: Node, pos: Vector3, core: Color, edge: Color, radius: float = 4.0) -> void:
	orb_pulse(parent, pos, Color(1, 1, 1, 0.9), 0.3, radius * 0.45, 0.18, 4.0)
	orb_pulse(parent, pos, core, 0.5, radius * 0.9, 0.45, 2.5)
	one_shot(parent, pos, {"amount": 64, "lifetime": 0.7, "size": 0.7, "color": core, "shape": "sphere",
		"radius": 0.4, "vmin": radius * 1.5, "vmax": radius * 3.0, "damping": radius * 3.5,
		"colors": [Color(1, 1, 1, 1), edge, Color(edge.r, edge.g, edge.b, 0)]})
	sparks(parent, pos, edge.lerp(Color.WHITE, 0.4), 40, radius * 4.0)
	one_shot(parent, pos, {"amount": 14, "lifetime": 1.1, "size": 0.18, "color": edge, "spark": true,
		"vmin": radius * 2.0, "vmax": radius * 3.5, "gravity": Vector3(0, -18, 0), "dir": Vector3.UP, "spread": 70.0,
		"scale_min": 0.8, "scale_max": 1.4, "shrink": false})
	smoke(parent, pos, Color(0.18, 0.16, 0.2, 0.7), 18, radius * 0.5, 1.6)
	shockwave(parent, pos + Vector3(0, -0.4, 0), edge, radius * 1.2, 0.5)
	flash(parent, pos, core.lerp(Color.WHITE, 0.3), 10.0, radius * 4.0, 0.5)


## Collapse inward: particles drawn to the centre, then a pop (gravity bomb, warp).
static func implode(parent: Node, pos: Vector3, color: Color, radius: float = 3.0) -> void:
	one_shot(parent, pos, {"amount": 48, "lifetime": 0.55, "size": 0.3, "color": color, "shape": "shell",
		"radius": radius, "vmin": 0.0, "vmax": 0.2, "radial": -radius * 7.0, "explosiveness": 0.8,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.2)], "shrink": false})
	orb_pulse(parent, pos, color, radius * 0.8, 0.2, 0.5, 2.0)


## Stretched glowing cylinder between two points; fades and thins over `time`.
static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, radius: float = 0.25, time: float = 0.3, energy: float = 3.0) -> MeshInstance3D:
	var length: float = from.distance_to(to)
	if length < 0.01:
		return null
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 16
	cm.rings = 1
	var mat: StandardMaterial3D = fading_mat(color, energy)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = beam_transform(from, to, radius)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "scale", Vector3(radius * 0.2, length, radius * 0.2), time)
	tw.chain().tween_callback(mi.queue_free)
	return mi


## Transform that maps a unit cylinder (height 1 along Y, centred) onto from -> to.
static func beam_transform(from: Vector3, to: Vector3, radius: float) -> Transform3D:
	var d: Vector3 = to - from
	var length: float = maxf(d.length(), 0.001)
	var y: Vector3 = d / length
	var x: Vector3 = y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x * radius, y * length, z * radius), (from + to) * 0.5)


## Jagged lightning between two points: a few glowing segments + a spark shower at the end.
static func bolt(parent: Node, from: Vector3, to: Vector3, color: Color, seed_value: int = 0, time: float = 0.25) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n: int = 7
	var prev: Vector3 = from
	var side: Vector3 = (to - from).cross(Vector3.FORWARD).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	for i: int in range(1, n + 1):
		var k: float = float(i) / float(n)
		var p: Vector3 = from.lerp(to, k)
		if i < n:
			p += side * rng.randf_range(-0.7, 0.7) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		beam(parent, prev, p, color, 0.07, time, 5.0)
		beam(parent, prev, p, Color(color.r, color.g, color.b, 0.35), 0.22, time * 0.8, 2.0)
		prev = p
	sparks(parent, to, color.lerp(Color.WHITE, 0.5), 24, 7.0)
	flash(parent, to + Vector3(0, 1, 0), color, 8.0, 10.0, 0.25)


## A glowing arc swept around `center` in the plane given by `basis` (x = right, -z = forward),
## from angle a0 to a1 (radians, 0 = forward); fades out. Plus sparks along it.
static func arc(parent: Node, center: Vector3, basis: Basis, radius: float, a0: float, a1: float, color: Color, width: float = 0.35, time: float = 0.22) -> void:
	var im := ImmediateMesh.new()
	var steps: int = 18
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in steps + 1:
		var k: float = float(i) / float(steps)
		var a: float = lerpf(a0, a1, k)
		var dir := Vector3(sin(a), 0, -cos(a))
		var w: float = width * sin(k * PI) + 0.02
		im.surface_set_color(Color(1, 1, 1, k))
		im.surface_add_vertex(dir * (radius - w))
		im.surface_set_color(Color(1, 1, 1, k))
		im.surface_add_vertex(dir * (radius + w))
	im.surface_end()
	var mat: StandardMaterial3D = fading_mat(color, 3.0)
	mat.vertex_color_use_as_albedo = true
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D(basis, center)
	var tw: Tween = mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	var mid: float = (a0 + a1) * 0.5
	var tip: Vector3 = center + basis * (Vector3(sin(a1), 0, -cos(a1)) * radius)
	sparks(parent, tip, color.lerp(Color.WHITE, 0.4), 14, 5.0, basis * Vector3(sin(mid), 0.3, -cos(mid)), 50.0)


## Particles scattered along a segment (beam trails, rays, chains): a one-shot box emitter
## stretched from `from` to `to`.
static func streak(parent: Node, from: Vector3, to: Vector3, color: Color, amount: int = 40, size: float = 0.22, life: float = 0.5, width: float = 0.3, speed: float = 1.5, spark: bool = false) -> void:
	var d: Vector3 = to - from
	var length: float = d.length()
	if length < 0.05:
		return
	var xf: Transform3D = beam_transform(from, to, 1.0)
	var b: Basis = xf.basis.orthonormalized()
	one_shot(parent, (from + to) * 0.5, {"amount": amount, "lifetime": life, "size": size, "color": color,
		"shape": "box", "extents": Vector3(width, length * 0.5, width), "basis": b, "vmin": speed * 0.3, "vmax": speed,
		"spread": 180.0, "damping": speed, "explosiveness": 0.85, "spark": spark, "aabb": length + 4.0,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)]})


## Little electric crackle: a few short jagged glowing segments around `center` (no light).
static func crackle(parent: Node, center: Vector3, radius: float, color: Color, segs: int = 4, time: float = 0.1) -> void:
	var prev: Vector3 = center + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * radius
	for i: int in segs:
		var nxt: Vector3 = prev + Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized() * radius * 0.45
		beam(parent, prev, nxt, color, 0.025, time, 6.0)
		prev = nxt


## Comic call-out ("POW!") that pops up, floats and fades.
static func popup_text(parent: Node, pos: Vector3, text: String, color: Color, size: int = 120) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 28
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.05, 0.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	l.layers = LAYER
	parent.add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 0.3
	var tw: Tween = l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y + 1.2, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


## Expanding ring in any plane (rings travelling along a ray, magnet field lines).
static func ring_pulse(parent: Node, pos: Vector3, normal: Vector3, color: Color, from_r: float, to_r: float, time: float = 0.35, thick: float = 0.12) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0 - thick
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 6
	var mat: StandardMaterial3D = fading_mat(color, 3.0)
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var n: Vector3 = normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var x: Vector3 = n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(n).normalized()
	mi.global_transform = Transform3D(Basis(x, n, z), pos)
	var b0: Basis = mi.basis
	mi.scale = Vector3(from_r, from_r, from_r)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_method(func(r: float) -> void:
		if is_instance_valid(mi):
			mi.basis = b0.scaled(Vector3(r, r, r)), maxf(from_r, 0.01), maxf(to_r, 0.01), time).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Camera shake for the local player (if the camera is an OrbitCamera).
static func shake(level: Node, amount: float) -> void:
	if level == null or not is_instance_valid(level):
		return
	var cam: Variant = level.get("camera")
	if cam is OrbitCamera and is_instance_valid(cam):
		(cam as OrbitCamera).add_trauma(amount)


# ---- small mesh helpers for costumes ------------------------------------------------

static func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot_deg
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func sphere_mesh(r: float = 0.5, segs: int = 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(segs / 2, 4)
	return s


static func cone_mesh(r: float, h: float, segs: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = r
	c.top_radius = 0.0
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func cyl_mesh(r: float, h: float, top: float = -1.0, segs: int = 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = r
	c.top_radius = r if top < 0.0 else top
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
