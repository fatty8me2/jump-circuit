class_name PartyFx
extends RefCounted
## Particle and flash toolkit for Party Mode. Everything is built from many modest
## GPUParticles3D emitters on unshaded, additive, soft round quads (cheap, and the level's
## glow turns them into light), plus short-lived OmniLight3D flashes and tweened meshes.
## Materials and textures are cached; one-shot effects free themselves.
## Graphics Quality is respected like visual/fx.gd: emitter amounts scale by `density()`
## (Low 45 %, Medium 75 %, High 100 %) and light flashes are skipped on Low.

const LAYER: int = 2   # "characters": keeps blob-shadow decals off the effects

static var _mats: Dictionary = {}
static var _tex: GradientTexture2D
static var _spark_tex: GradientTexture2D
static var _ramps: Dictionary = {}
static var _flutter: CurveXYZTexture
static var _burst_mesh: ArrayMesh
static var _shard_mesh: Mesh
static var _shaders: Dictionary = {}
static var _star5: ImageTexture


## Drops the cached materials / textures (the party layer calls this when it leaves, so
## nothing is held after Party Mode ends; the next use rebuilds them).
static func clear_caches() -> void:
	_mats.clear()
	_ramps.clear()
	_tex = null
	_spark_tex = null
	_flutter = null
	_burst_mesh = null
	_shard_mesh = null
	_shaders.clear()
	_star5 = null


# ---- quality ---------------------------------------------------------------------------

## THE one knob for every Party Mode particle amount (PartyFx.emitter, HeroFx.em and the
## per-frame spawn rates all go through it). Today it is the game's Graphics Quality scale:
## Low 0.45, Medium 0.75, High 1.0 (Fx.density). When Settings grows a
## `particle_scale()` (an "Ultra" tier, ~1.6-2.0) it is picked up here automatically - or
## make this the single line `return Settings.particle_scale()`.
static func quality_scale() -> float:
	var st: Object = Engine.get_main_loop()
	if st is SceneTree and (st as SceneTree).root != null:
		var s: Node = (st as SceneTree).root.get_node_or_null("Settings")
		if s != null and s.has_method("particle_scale"):
			return clampf(float(s.call("particle_scale")), 0.2, 2.5)
	return Fx.density()


## Old name, kept for callers: the same as quality_scale().
static func density() -> float:
	return quality_scale()


## `n` particles scaled by quality (never below 1).
static func count(n: int) -> int:
	return maxi(1, roundi(float(n) * quality_scale()))


## Light flashes are skipped on Low quality.
static func lights_on() -> bool:
	return quality_scale() >= 0.5


## Optional extra layers (lingering embers, secondary debris, heat shimmer) are skipped on
## Low so it stays light.
static func rich() -> bool:
	return quality_scale() >= 0.6


## 0..1: how far the current camera is from a big effect at `pos` of size `radius` (0 =
## the camera is inside it). Big dark / bright volumes fade by this so they never fill the
## local player's own view.
static func camera_clear(pos: Vector3, radius: float) -> float:
	var st: Object = Engine.get_main_loop()
	if not (st is SceneTree):
		return 1.0
	var vp: Viewport = (st as SceneTree).root
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam == null:
		return 1.0
	var d: float = cam.global_position.distance_to(pos)
	return clampf((d - radius * 0.9) / maxf(radius * 1.2, 0.5), 0.0, 1.0)


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
## `tex`: "" (dot, or the hard spark when `spark`), "star", "smoke", "ring", "streak".
## billboard=false: the particle transform decides (velocity streaks, flat rings).
static func particle_mat(color: Color, additive: bool = true, spark: bool = false, tex: String = "", billboard: bool = true) -> StandardMaterial3D:
	var tname: String = tex if tex != "" else ("spark" if spark else "dot")
	var key: String = "p:%s:%s:%s:%s" % [color, additive, tname, billboard]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	match tname:
		"spark":
			m.albedo_texture = spark_texture()
		"star":
			m.albedo_texture = Fx.texture(Fx.Tex.STAR)
		"smoke":
			m.albedo_texture = Fx.texture(Fx.Tex.SMOKE)
		"ring":
			m.albedo_texture = Fx.texture(Fx.Tex.RING)
		"streak":
			m.albedo_texture = Fx.texture(Fx.Tex.SPARK)
		"star5":
			m.albedo_texture = star5_texture()
		"none":
			pass
		_:
			m.albedo_texture = dot_texture()
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
	else:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


## Glowing solid (unshaded) for charge balls, blades, beams. alpha < 1 blends additively.
static func glow_mat(color: Color, energy: float = 2.0, additive: bool = false) -> StandardMaterial3D:
	var key: String = "g:%s:%.2f:%s" % [color, energy, additive]
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


## Paper flapping: the particle's height flips between full and edge-on a few times.
static func _flutter_curve() -> CurveXYZTexture:
	if _flutter == null:
		var one := Curve.new()
		one.add_point(Vector2(0, 1))
		one.add_point(Vector2(1, 1))
		var flap := Curve.new()
		for i: int in 9:
			flap.add_point(Vector2(float(i) / 8.0, 1.0 if i % 2 == 0 else 0.12))
		var fade := Curve.new()
		fade.add_point(Vector2(0, 1))
		fade.add_point(Vector2(0.8, 1))
		fade.add_point(Vector2(1, 0))
		_flutter = CurveXYZTexture.new()
		_flutter.curve_x = fade
		_flutter.curve_y = flap
		_flutter.curve_z = one
	return _flutter


## Each particle picks one colour of `colors` (constant steps, no in-between blends).
static func _pick_ramp(colors: Array) -> GradientTexture1D:
	var key: String = "pick" + str(colors)
	if _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i: int in colors.size():
		offs.append(float(i) / float(colors.size()))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	_ramps[key] = t
	return t


# ---- emitters ------------------------------------------------------------------------------

## Generic emitter. Keys (all optional):
##  amount, lifetime, one_shot, explosiveness, randomness, size, color, colors (ramp),
##  additive, spark, dir, spread, vmin, vmax, gravity, damping, radial (radial accel),
##  tangential, orbit, shape ("point" | "sphere" | "shell" | "ring" | "box"), radius,
##  inner, axis (ring axis), extents (box), scale_min, scale_max, shrink (bool, default true),
##  grow (bool), local (local_coords), aabb (visibility half-size), flat (flatness),
##  angle (random rotation), fixed_fps, initial (random per-particle colour ramp),
##  exact (keep `amount` whatever the quality), tex ("star" | "smoke" | "ring" | "streak"),
##  facing ("billboard" | "velocity" streaks | "flat" in the local XZ plane | "mesh" + mesh),
##  size (float or Vector2), spin (deg/s, +-), turbulence (strength), hue (+- variation),
##  pick (Array of colours: each particle takes one, no blends - confetti), flutter
##  (paper-like flapping), life_rand (lifetime randomness), linear (accel along the
##  velocity), preprocess, offset (emission offset).
static func emitter(o: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.layers = LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = int(o.get("amount", 24)) if bool(o.get("exact", false)) else count(int(o.get("amount", 24)))
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
	if o.has("offset"):
		pm.emission_shape_offset = o["offset"]
	if o.has("linear"):
		pm.linear_accel_min = float(o["linear"]) * 0.7
		pm.linear_accel_max = float(o["linear"])
	if o.has("spin"):
		pm.angular_velocity_min = -float(o["spin"])
		pm.angular_velocity_max = float(o["spin"])
	if o.has("turbulence"):
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = float(o["turbulence"])
		pm.turbulence_noise_scale = float(o.get("turbulence_scale", 3.0))
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.2
	if o.has("hue"):
		pm.hue_variation_min = -float(o["hue"])
		pm.hue_variation_max = float(o["hue"])
	if o.has("life_rand"):
		pm.lifetime_randomness = float(o["life_rand"])
	if o.has("preprocess"):
		p.preprocess = float(o["preprocess"])
	if bool(o.get("align", false)):
		pm.particle_flag_align_y = true
	if bool(o.get("flutter", false)):
		pm.scale_curve = _flutter_curve()
	elif bool(o.get("grow", false)):
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
	if o.has("pick"):
		pm.color_initial_ramp = _pick_ramp(o["pick"])
	p.process_material = pm
	var facing: String = str(o.get("facing", "billboard"))
	if facing == "mesh":
		p.draw_pass_1 = o["mesh"]
	else:
		var q := QuadMesh.new()
		var sv: Variant = o.get("size", 0.25)
		q.size = sv if sv is Vector2 else Vector2(float(sv), float(sv))
		if facing == "flat":
			q.orientation = PlaneMesh.FACE_Y
		if facing == "velocity":
			pm.particle_flag_align_y = true
			p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		q.material = particle_mat(col, bool(o.get("additive", true)), bool(o.get("spark", false)), str(o.get("tex", "")), facing == "billboard")
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
	if not lights_on() or parent == null or not parent.is_inside_tree():
		return
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


## A basis looking along `dir` that never fails (zero / vertical directions from the network).
static func facing(dir: Vector3) -> Basis:
	if dir.length() < 0.001:
		return Basis.IDENTITY
	var d: Vector3 = dir.normalized()
	return Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)


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


# ---- item / event polish: shared effects --------------------------------------------------

const CONFETTI: Array = [Color(1.0, 0.35, 0.55), Color(0.35, 0.8, 1.0), Color(1.0, 0.88, 0.25),
	Color(0.45, 1.0, 0.5), Color(0.8, 0.5, 1.0), Color(1.0, 0.6, 0.2)]


## Cartoon impact stars: four-point glints thrown out flat around `pos` (in the plane
## whose normal is `normal`), spinning as they fly and fade.
static func star_ring(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.9, 0.35), amount: int = 10, speed: float = 6.0, size: float = 0.45, normal: Vector3 = Vector3.UP) -> void:
	one_shot(parent, pos, {"amount": amount, "lifetime": 0.6, "size": size, "color": color, "tex": "star5",
		"additive": false, "dir": Vector3(1, 0, 0), "spread": 180.0, "flat": 1.0, "vmin": speed * 0.6, "vmax": speed,
		"damping": speed * 1.5, "spin": 280.0, "angle": true, "basis": Fx.basis_up(normal), "grow": true,
		"explosiveness": 1.0, "aabb": speed + 3.0,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	one_shot(parent, pos, {"amount": maxi(amount / 2, 3), "lifetime": 0.35, "size": size * 0.9, "color": color.lerp(Color(1.6, 1.6, 1.4), 0.4),
		"tex": "star", "dir": Vector3(1, 0, 0), "spread": 180.0, "flat": 1.0, "vmin": speed * 0.3, "vmax": speed * 0.7,
		"damping": speed * 1.5, "angle": true, "basis": Fx.basis_up(normal), "explosiveness": 1.0, "aabb": speed + 3.0})


## Paper confetti: fluttering coloured scraps that tumble down.
static func confetti(parent: Node, pos: Vector3, amount: int = 60, speed: float = 7.0, dir: Vector3 = Vector3.UP, spread: float = 75.0, life: float = 1.8) -> void:
	one_shot(parent, pos, {"amount": amount, "lifetime": life, "size": Vector2(0.24, 0.14), "color": Color(1.25, 1.25, 1.25),
		"additive": false, "tex": "none", "vmin": speed * 0.4, "vmax": speed, "dir": dir, "spread": spread,
		"gravity": Vector3(0, -7.0, 0), "damping": speed * 0.45, "angle": true, "spin": 520.0, "flutter": true,
		"pick": CONFETTI, "life_rand": 0.35, "turbulence": 1.2, "explosiveness": 0.95, "aabb": 10.0,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})


## A comic "POW!" call-out: a spiky starburst behind bold text that slams in, holds and
## fades while drifting up. Always drawn on top.
static func comic_burst(parent: Node, pos: Vector3, text: String, fill: Color, size: float = 1.0, ink: Color = Color(0.3, 0.07, 0.02)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var mats: Array[StandardMaterial3D] = []
	for layer_i: int in 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.no_depth_test = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 1 + layer_i
		m.albedo_color = ink if layer_i == 0 else Color(fill.r * 1.3, fill.g * 1.3, fill.b * 1.3, 1.0)
		mats.append(m)
		var mi: MeshInstance3D = part(root, _starburst_mesh(), m, Vector3.ZERO, Vector3.ONE * size * (1.16 if layer_i == 0 else 1.0))
		mi.sorting_offset = float(layer_i)
	var l := Label3D.new()
	l.text = text
	l.font_size = 110
	l.outline_size = 26
	l.modulate = Color(1.0, 1.0, 0.92)
	l.outline_modulate = ink
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 4
	l.outline_render_priority = 3
	l.pixel_size = 0.0062 * size
	l.layers = LAYER
	root.add_child(l)
	root.scale = Vector3.ONE * 0.15
	var tw: Tween = root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * 1.15, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector3.ONE, 0.1)
	tw.tween_interval(0.35)
	tw.tween_property(root, "scale", Vector3.ONE * 1.25, 0.28)
	for m: StandardMaterial3D in mats:
		tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.28)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.28)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.28)
	tw.tween_callback(root.queue_free)
	var up: Tween = root.create_tween()
	up.tween_property(root, "position:y", root.position.y + 0.7, 0.85).set_ease(Tween.EASE_OUT)


## A 14-spike irregular starburst in the XY plane (radius ~1), built once.
static func _starburst_mesh() -> ArrayMesh:
	if _burst_mesh != null:
		return _burst_mesh
	var radii: Array[float] = [1.0, 0.86, 1.12, 0.92, 1.04, 0.8, 1.15, 0.9, 1.0, 0.84, 1.1, 0.95, 1.02, 0.82]
	var n: int = radii.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i: int in n * 2:
		var a: float = TAU * float(i) / float(n * 2) + 0.2
		var r: float = radii[i / 2] if i % 2 == 0 else 0.6
		pts.append(Vector3(cos(a) * r * 1.25, sin(a) * r, 0.0))
	for i: int in pts.size():
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[(i + 1) % pts.size()])
		st.add_vertex(pts[i])
	_burst_mesh = st.commit()
	return _burst_mesh


## The big KO: white-hot flash, a gold star ring, streaking sparks, confetti, a light pillar
## and a "KO!" burst.
static func ko_burst(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.45, 0.25)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	# kept soft: a camera right next to the KO (a claw on a practice dummy) sits inside these orbs
	orb_pulse(parent, pos, Color(1, 1, 1, 0.3), 0.2, 0.8, 0.12, 1.1)
	orb_pulse(parent, pos, Color(color.r, color.g, color.b, 0.28), 0.4, 2.0, 0.4, 0.8)
	star_ring(parent, pos, Color(1.0, 0.88, 0.35), 14, 9.0, 0.65)
	star_ring(parent, pos + Vector3(0, 0.2, 0), Color(1.0, 1.0, 0.9), 8, 5.0, 0.4, Vector3(0.3, 0.2, 1.0))
	one_shot(parent, pos, {"amount": 44, "lifetime": 0.55, "size": Vector2(0.1, 0.8), "color": color.lerp(Color(1.4, 1.2, 0.8), 0.5),
		"tex": "streak", "facing": "velocity", "vmin": 8.0, "vmax": 16.0, "damping": 14.0, "gravity": Vector3(0, -8, 0),
		"aabb": 14.0, "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	confetti(parent, pos + Vector3(0, 0.3, 0), 44, 9.0, Vector3.UP, 85.0, 1.6)
	ring_pulse(parent, pos, Vector3.UP, color, 0.3, 3.6, 0.42, 0.14)
	ring_pulse(parent, pos, Vector3.UP, Color(1, 1, 1), 0.2, 2.4, 0.3, 0.08)
	beam(parent, pos - Vector3(0, 0.9, 0), pos + Vector3(0, 7.5, 0), Color(color.r, color.g, color.b, 0.35), 0.5, 0.5, 1.8)
	beam(parent, pos - Vector3(0, 0.9, 0), pos + Vector3(0, 7.5, 0), Color(1, 0.95, 0.85, 0.5), 0.12, 0.35, 1.8)
	smoke(parent, pos, Color(0.3, 0.26, 0.3, 0.55), 12, 0.8, 1.2)
	comic_burst(parent, pos + Vector3(0, 1.4, 0), "KO!", Color(1.0, 0.3, 0.2), 1.25)
	# the ground under them takes it (a dust ring and a scorch) and gold motes hang after
	if parent is Node3D and (parent as Node3D).is_inside_tree():
		var gq := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, -3.0, 0), 1)
		var gh: Dictionary = (parent as Node3D).get_world_3d().direct_space_state.intersect_ray(gq)
		if not gh.is_empty():
			HeroFx.dust_ring(parent, gh["position"] as Vector3, Color(0.9, 0.86, 0.78, 0.5), 0.8, 12, 5.0)
			scorch(parent, gh["position"] as Vector3, 1.0, 1.6, color)
	if rich():
		embers(parent, pos, 0.8, Color(1.8, 1.4, 0.5), 22, 1.4, 1.2)
	HeroFx.sparks(parent, pos, color.lerp(Color(1.6, 1.4, 1.0), 0.5), 26, 11.0, Vector3.UP, 180.0, 0.5)
	flash(parent, pos, color.lerp(Color.WHITE, 0.25), 4.5, 10.0, 0.4)


## A scorched ring left on the ground: a dark soft disc with a glowing rim that cools, and
## a few embers drifting up. `pos` is on the ground.
static func scorch(parent: Node, pos: Vector3, radius: float = 1.2, life: float = 1.8, glow: Color = Color(1.0, 0.6, 0.25)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos + Vector3(0, 0.05, 0)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.albedo_texture = dot_texture()
	dark.albedo_color = Color(0.05, 0.04, 0.07, 0.75)
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rim := StandardMaterial3D.new()
	rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rim.albedo_texture = Fx.texture(Fx.Tex.RING)
	rim.albedo_color = Color(glow.r * 2.5, glow.g * 2.5, glow.b * 2.5, 1.0)
	rim.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * radius * 2.0
	part(root, pm, dark, Vector3.ZERO)
	var rm: MeshInstance3D = part(root, pm, rim, Vector3(0, 0.01, 0), Vector3.ONE * 0.6)
	var tw: Tween = root.create_tween().set_parallel(true)
	tw.tween_property(rm, "scale", Vector3.ONE * 1.05, life * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(rim, "albedo_color", Color(glow.r * 0.6, glow.g * 0.2, 0.05, 0.0), life * 0.6)
	tw.tween_property(dark, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(root.queue_free)
	one_shot(parent, pos + Vector3(0, 0.1, 0), {"amount": 14, "lifetime": 0.9, "size": 0.1, "color": glow.lerp(Color(1.5, 1.2, 0.6), 0.3),
		"shape": "ring", "radius": radius * 0.8, "inner": radius * 0.3, "dir": Vector3.UP, "spread": 20.0,
		"vmin": 0.6, "vmax": 2.0, "explosiveness": 0.2, "spark": true, "turbulence": 1.0})


## Forked lightning: a jagged main bolt with a few branches splitting off it, a white-hot
## core in a coloured glow, and a spark shower + flash where it lands.
static func forked_bolt(parent: Node, from: Vector3, to: Vector3, color: Color, seed_value: int = 0, time: float = 0.3, branches: int = 3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d: Vector3 = to - from
	var length: float = d.length()
	if length < 0.1:
		return
	var axis: Vector3 = d / length
	var s1: Vector3 = axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var s2: Vector3 = axis.cross(s1).normalized()
	var n: int = 10
	var pts: Array[Vector3] = [from]
	for i: int in range(1, n):
		var k: float = float(i) / float(n)
		var j: float = length * 0.07 * sin(k * PI)
		pts.append(from + d * k + s1 * rng.randf_range(-j, j) * 1.6 + s2 * rng.randf_range(-j, j) * 1.6)
	pts.append(to)
	var core := Color(1.0, 1.0, 1.0, 1.0).lerp(color, 0.25)
	for i: int in n:
		var w: float = lerpf(1.0, 0.6, float(i) / float(n))
		beam(parent, pts[i], pts[i + 1], core, 0.055 * w, time, 4.0)
		beam(parent, pts[i], pts[i + 1], Color(color.r, color.g, color.b, 0.25), 0.18 * w, time * 0.8, 1.6)
	for b: int in branches:
		var at: int = rng.randi_range(2, n - 3)
		var p: Vector3 = pts[at]
		var bdir: Vector3 = (axis + s1 * rng.randf_range(-1.1, 1.1) + s2 * rng.randf_range(-1.1, 1.1)).normalized()
		var blen: float = length * rng.randf_range(0.15, 0.3)
		for k: int in 3:
			var q: Vector3 = p + bdir * blen / 3.0 + s1 * rng.randf_range(-0.3, 0.3) + s2 * rng.randf_range(-0.3, 0.3)
			beam(parent, p, q, core, 0.035, time * 0.8, 5.0)
			beam(parent, p, q, Color(color.r, color.g, color.b, 0.22), 0.14, time * 0.6, 2.0)
			p = q
	sparks(parent, to, color.lerp(Color.WHITE, 0.5), 26, 8.0)
	one_shot(parent, to, {"amount": 20, "lifetime": 0.35, "size": Vector2(0.06, 0.5), "color": Color(1.4, 1.5, 2.0),
		"tex": "streak", "facing": "velocity", "vmin": 6.0, "vmax": 12.0, "damping": 10.0, "dir": Vector3.UP,
		"spread": 80.0, "gravity": Vector3(0, -10, 0), "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	flash(parent, to + Vector3(0, 1, 0), color, 9.0, 11.0, 0.3)


## A dark storm cloud that boils up at `pos`, flickers with inner lightning, drizzles and
## drifts apart after `life` seconds (frees itself).
static func storm_cloud(parent: Node, pos: Vector3, radius: float = 1.8, life: float = 1.4, seed_value: int = 0) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var ext := Vector3(radius, radius * 0.25, radius)
	# the body: a quick billow that builds it, then a steady churn
	var billow: GPUParticles3D = emitter({"amount": 22, "lifetime": 0.9, "size": radius * 1.8, "color": Color(0.3, 0.31, 0.4, 0.95),
		"additive": false, "tex": "smoke", "shape": "box", "extents": ext * 0.7, "vmin": 0.3, "vmax": 1.2,
		"spread": 180.0, "damping": 1.5, "grow": true, "angle": true, "spin": 25.0, "one_shot": true, "explosiveness": 0.9,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)], "aabb": radius * 3.0})
	root.add_child(billow)
	billow.emitting = true
	var churn: GPUParticles3D = emitter({"amount": 16, "lifetime": 1.2, "size": radius * 1.5, "color": Color(0.26, 0.27, 0.36, 0.9),
		"additive": false, "tex": "smoke", "shape": "box", "extents": ext, "vmin": 0.1, "vmax": 0.5, "spread": 180.0,
		"grow": true, "angle": true, "spin": 30.0, "preprocess": 0.4, "aabb": radius * 3.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)]})
	root.add_child(churn)
	# inner flicker: bluish glows blinking inside the cloud
	var glow: GPUParticles3D = emitter({"amount": 6, "lifetime": 0.18, "size": radius * 1.2, "color": Color(0.55, 0.65, 1.3, 0.5),
		"shape": "box", "extents": ext * 0.8, "vmin": 0.0, "vmax": 0.1, "shrink": false, "randomness": 1.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], "aabb": radius * 3.0})
	root.add_child(glow)
	# drizzle
	var rain: GPUParticles3D = emitter({"amount": 26, "lifetime": 0.55, "size": Vector2(0.03, 0.42), "color": Color(0.7, 0.8, 1.1, 0.7),
		"tex": "streak", "facing": "velocity", "shape": "box", "extents": Vector3(radius * 0.8, 0.1, radius * 0.8),
		"offset": Vector3(0, -radius * 0.25, 0), "dir": Vector3.DOWN, "spread": 5.0, "vmin": 9.0, "vmax": 12.0,
		"shrink": false, "aabb": radius * 4.0 + 8.0, "colors": [Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.5)]})
	root.add_child(rain)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tw: Tween = root.create_tween()
	for i: int in 3:
		tw.tween_interval(life * 0.22 + rng.randf() * 0.1)
		var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.2), rng.randf_range(-1, 1)) * radius * 0.6
		tw.tween_callback(func() -> void:
			if is_instance_valid(root) and root.is_inside_tree():
				crackle(root, root.global_position + off, radius * 0.5, Color(0.75, 0.85, 1.0), 4, 0.08))
	tw.tween_interval(maxf(life - 0.9, 0.1))
	tw.tween_callback(func() -> void:
		for c: Node in root.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false)
	tw.tween_interval(1.3)
	tw.tween_callback(root.queue_free)
	return root


## Shared shard mesh for mesh particles (a four-sided spike along +Y, lit, tinted by the
## particle colour).
static func shard_mesh() -> Mesh:
	if _shard_mesh == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.5
		c.height = 1.8
		c.radial_segments = 4
		c.rings = 1
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.08
		m.metallic = 0.2
		m.emission_enabled = true
		m.emission = Color(0.35, 0.6, 0.8)
		m.emission_energy_multiplier = 0.6
		m.rim_enabled = true
		m.rim = 1.0
		c.material = m
		_shard_mesh = c
	return _shard_mesh


## Spiky shards (ice, glass) flying out and tumbling down, pointing along their flight.
static func shards(parent: Node, pos: Vector3, color: Color, amount: int = 16, speed: float = 6.0, size: float = 0.18, dir: Vector3 = Vector3.UP, spread: float = 90.0) -> void:
	one_shot(parent, pos, {"amount": amount, "lifetime": 0.9, "facing": "mesh", "mesh": shard_mesh(), "align": true,
		"color": color, "shape": "sphere", "radius": 0.3, "dir": dir, "spread": spread, "vmin": speed * 0.4, "vmax": speed,
		"gravity": Vector3(0, -18, 0), "damping": 1.0, "scale_min": size * 0.5, "scale_max": size, "explosiveness": 1.0,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1)], "aabb": speed + 4.0})


## Lit tumbling chunks (rubble, clods) - Fx's shared chunk mesh.
static func debris(parent: Node, pos: Vector3, color: Color, amount: int = 12, speed: float = 5.0, chunk: float = 0.16) -> void:
	one_shot(parent, pos, {"amount": amount, "lifetime": 1.0, "facing": "mesh", "mesh": Fx.chunk_mesh(chunk),
		"color": color, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 70.0, "vmin": speed * 0.5,
		"vmax": speed, "gravity": Vector3(0, -20, 0), "scale_min": 0.5, "scale_max": 1.2, "angle": true, "spin": 400.0,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1)], "aabb": speed + 4.0})


## A swirling portal disc facing `normal` that irises open, spins and snaps shut after
## `life` s (frees itself).
static func portal(parent: Node, pos: Vector3, normal: Vector3, color: Color, radius: float = 1.0, life: float = 0.8) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_transform = Transform3D(Fx.basis_up(normal if normal.length() > 0.01 else Vector3.UP), pos)
	var spin := Node3D.new()
	root.add_child(spin)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.86
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 6
	part(spin, tm, glow_mat(color, 1.5), Vector3.ZERO)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	part(spin, disc, glow_mat(Color(color.r * 0.15, color.g * 0.3, color.b * 0.45, 0.6), 1.0), Vector3.ZERO)
	# spiral arms: particles orbiting and sinking to the centre
	var arms: GPUParticles3D = emitter({"amount": 40, "lifetime": 0.5, "size": 0.14, "color": color,
		"shape": "ring", "radius": 0.95, "inner": 0.8, "dir": Vector3(1, 0, 0), "spread": 0.0, "vmin": 0.0, "vmax": 0.0,
		"radial": -3.4, "local": true, "spark": true, "aabb": 3.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	spin.add_child(arms)
	part(spin, sphere_mesh(0.1, 10), glow_mat(Color(1, 1, 1), 1.5), Vector3.ZERO)
	root.scale = Vector3.ONE * 0.01
	var tw: Tween = root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * radius, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(life - 0.32, 0.05))
	tw.tween_property(root, "scale", Vector3(0.01, 1.0, 0.01) * radius, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)
	var sp: Tween = spin.create_tween().set_loops(maxi(int(life / 0.4) + 1, 1))
	sp.tween_property(spin, "rotation:y", -TAU, 0.4).from(0.0)
	return root


# ---- screen-space warps (heat shimmer, gravity lens) --------------------------------------

const _HEAT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.012;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float fall = clamp(1.0 - dot(c, c), 0.0, 1.0);
	vec2 wob = vec2(sin(UV.y * 29.0 - TIME * 19.0), cos(UV.x * 23.0 + TIME * 15.0));
	ALBEDO = textureLod(screen_tex, SCREEN_UV + wob * strength * fall * amount, 0.0).rgb;
	ALPHA = fall * amount;
}
"""

const _LENS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.08;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 rim_color : source_color = vec4(0.7, 0.4, 1.0, 1.0);
uniform float dark = 0.85;
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = 1.0 - facing;
	vec2 n = vec2(NORMAL.x, -NORMAL.y);
	vec2 uv = SCREEN_UV + n * strength * amount * (0.35 + facing);
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;
	col *= mix(1.0, 1.0 - dark, pow(facing, 4.0) * amount);
	col += rim_color.rgb * pow(edge, 3.0) * 2.5 * amount;
	ALBEDO = col;
	ALPHA = smoothstep(0.0, 0.35, facing + 0.2) * amount;
}
"""


static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = code
		_shaders[key] = sh
	return _shaders[key]


## Heat shimmer: a camera-facing quad that wobbles what is behind it. `amount` fades it.
static func heat_haze(size: float = 1.0, strength: float = 0.012) -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = _shader("heat", _HEAT_SHADER)
	m.set_shader_parameter("strength", strength)
	# drawn first among the see-through things: it wobbles the solid world behind it, and the
	# flames and glows drawn after it stay on top instead of being painted over
	m.render_priority = -120
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A gravity lens: a sphere that pulls the world behind it inward, darkens its heart and
## rims itself in `rim`. Its material has an `amount` parameter to tween.
static func lens_sphere(radius: float, rim: Color, strength: float = 0.08) -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = _shader("lens", _LENS_SHADER)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("rim_color", rim)
	var mi := MeshInstance3D.new()
	mi.mesh = sphere_mesh(radius, 32)
	mi.material_override = m
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---- timed items running out ----------------------------------------------------------------

## True while a running-out costume should show: steady until the last `window` seconds,
## then blinking faster and faster.
static func blink_on(time_left: float, window: float = 2.0) -> bool:
	if time_left >= window:
		return true
	var k: float = clampf(1.0 - time_left / window, 0.0, 1.0)
	return fmod((window - time_left) * lerpf(5.0, 13.0, k), 1.0) < 0.6


## Pops a node in from nothing (elastic), e.g. a costume piece or a respawning prop.
static func pop_in(node: Node3D, time: float = 0.35, to: Vector3 = Vector3.ONE) -> void:
	node.scale = to * 0.05
	node.create_tween().tween_property(node, "scale", to, time).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# ---- motion helpers ----------------------------------------------------------------------------

## Cartoon speed lines: thin white streaks shooting along from -> to.
static func speed_lines(parent: Node, from: Vector3, to: Vector3, color: Color = Color(1.5, 1.5, 1.5, 0.8), amount: int = 18, width: float = 0.45) -> void:
	var d: Vector3 = to - from
	var length: float = d.length()
	if length < 0.1:
		return
	var b: Basis = beam_transform(from, to, 1.0).basis.orthonormalized()
	one_shot(parent, (from + to) * 0.5, {"amount": amount, "lifetime": 0.22, "size": Vector2(0.035, 1.1), "color": color,
		"tex": "streak", "facing": "velocity", "shape": "box", "extents": Vector3(width, length * 0.5, width), "basis": b,
		"dir": Vector3.UP, "spread": 2.0, "vmin": length * 2.0, "vmax": length * 3.5, "explosiveness": 0.8,
		"shrink": false, "aabb": length + 4.0, "colors": [Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]})


## Sparks zipping along the line from -> to (a pull, a tether, a siphon).
static func tether(parent: Node, from: Vector3, to: Vector3, color: Color, amount: int = 10, speed: float = 9.0) -> void:
	var d: Vector3 = to - from
	var length: float = d.length()
	if length < 0.3:
		return
	var b: Basis = beam_transform(from, to, 1.0).basis.orthonormalized()
	one_shot(parent, from.lerp(to, 0.35), {"amount": amount, "lifetime": minf(length / speed, 0.6), "size": Vector2(0.06, 0.5),
		"color": color, "tex": "streak", "facing": "velocity", "shape": "box", "extents": Vector3(0.12, length * 0.35, 0.12),
		"basis": b, "dir": Vector3.UP, "spread": 4.0, "vmin": speed * 0.8, "vmax": speed, "explosiveness": 0.3,
		"shrink": false, "aabb": length + 3.0, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})


## A wavy ribbon along from -> to (ray-gun beams): `waves` sine periods of amplitude `amp`,
## in the plane turned `roll` radians about the ray, coloured along its length by `hue0`..
## (a rainbow when `rainbow`), fading over `time`.
static func wave_ribbon(parent: Node, from: Vector3, to: Vector3, color: Color, amp: float = 0.25, waves: float = 4.0, width: float = 0.08, time: float = 0.4, roll: float = 0.0, rainbow: bool = false, energy: float = 1.3) -> void:
	var d: Vector3 = to - from
	var length: float = d.length()
	if length < 0.1:
		return
	var axis: Vector3 = d / length
	var s1: Vector3 = axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var s2: Vector3 = axis.cross(s1).normalized()
	var side: Vector3 = s1 * cos(roll) + s2 * sin(roll)
	var wdir: Vector3 = axis.cross(side).normalized()
	var steps: int = clampi(int(length * 6.0), 12, 160)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in steps + 1:
		var k: float = float(i) / float(steps)
		var env: float = clampf(k * 6.0, 0.0, 1.0)
		var off: Vector3 = side * sin(k * waves * TAU) * amp * env
		var c: Color = Color.from_hsv(fmod(k * 1.5, 1.0), 0.7, 1.0) if rainbow else Color.WHITE
		im.surface_set_color(c)
		im.surface_add_vertex(d * k + off - wdir * width)
		im.surface_set_color(c)
		im.surface_add_vertex(d * k + off + wdir * width)
	im.surface_end()
	var mat: StandardMaterial3D = fading_mat(color, energy)
	mat.vertex_color_use_as_albedo = true
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = from
	var tw: Tween = mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## A glowing ball with a trail that flies from -> to along an arc (`lift` m high at the
## middle) in `time` s, then pops.
static func comet(parent: Node, from: Vector3, to: Vector3, color: Color, lift: float = 2.0, time: float = 0.35, size: float = 0.22) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = from
	part(root, sphere_mesh(size, 12), glow_mat(color.lerp(Color.WHITE, 0.5), 3.0), Vector3.ZERO)
	var tr: GPUParticles3D = emitter({"amount": 40, "lifetime": 0.3, "size": size * 1.6, "color": color, "vmin": 0.0,
		"vmax": 0.3, "fixed_fps": 0, "aabb": from.distance_to(to) + 6.0})
	root.add_child(tr)
	var mid: Vector3 = (from + to) * 0.5 + Vector3(0, lift, 0)
	var tw: Tween = root.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(root):
			var a: Vector3 = from.lerp(mid, k)
			var b: Vector3 = mid.lerp(to, k)
			root.global_position = a.lerp(b, k), 0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(root) and root.is_inside_tree():
			burst(root.get_parent(), root.global_position, color, 14, 3.0, 0.2, 0.35)
			tr.emitting = false
			for c: Node in root.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).visible = false)
	tw.tween_interval(0.4)
	tw.tween_callback(root.queue_free)


# ---- cartoon stars ------------------------------------------------------------------------------

## A five-point cartoon star, white with a grey rim (tint it): fill + outline in one texture.
static func star5_texture() -> Texture2D:
	if _star5 == null:
		var px: int = 64
		var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
		var h: float = float(px - 1) * 0.5
		for y: int in px:
			for x: int in px:
				var u: float = (float(x) - h) / h
				var v: float = (float(y) - h) / h
				var r: float = sqrt(u * u + v * v)
				var t: float = absf(fposmod(atan2(u, -v) / TAU * 5.0, 1.0) - 0.5) * 2.0
				var edge: float = lerpf(0.45, 0.97, pow(t, 1.6))
				var alpha: float = clampf((edge - r) / 0.05, 0.0, 1.0)
				var val: float = 1.0 if r < edge - 0.16 else 0.42
				# a soft highlight toward the top-left
				val = minf(val + clampf(0.25 - (u + 0.2) * (u + 0.2) - (v + 0.25) * (v + 0.25), 0.0, 0.25), 1.0)
				img.set_pixel(x, y, Color(val, val, val, alpha))
		img.generate_mipmaps()
		_star5 = ImageTexture.create_from_image(img)
	return _star5


## A camera-facing cartoon star (dizzy stars, sparkles that must read on bright levels).
static func star_sprite(size: float, color: Color) -> MeshInstance3D:
	var key: String = "star5:%s" % color
	var m: StandardMaterial3D = _mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = star5_texture()
		m.albedo_color = color
		m.disable_receive_shadows = true
		_mats[key] = m
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---- heavy pass: layered building blocks ---------------------------------------------------------
# Bigger effects are stacked from these: ground damage (cracks, scorch, footprints), lingering
# embers, burning debris that sparks where it lands, dust walls, a fire mushroom, lightning
# crawling over a sphere. All free themselves; amounts go through quality_scale().

## A flat mark's material: mix-blended (reads on bright grass), HDR colour, vertex alpha.
static func _flat_mat(color: Color, tex: Texture2D, priority: int = 0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	if tex != null:
		m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.render_priority = priority
	return m


## Glowing cracks split across the ground from `pos` (on the ground, normal `up`): jagged,
## branching lines with a dark rim, white-hot at the centre, cooling to a dull red and
## fading over `life` s; embers seep out of them (not on Low).
static func ground_cracks(parent: Node, pos: Vector3, radius: float, hot: Color = Color(2.6, 1.2, 0.3), n: int = 8, life: float = 2.6, seed_value: int = 0, up: Vector3 = Vector3.UP, rim: Color = Color(0.05, 0.02, 0.02, 0.85)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else randi()
	var lines: Array = []   # [points, width]
	var w0: float = clampf(radius * 0.022, 0.035, 0.09)
	for i: int in n:
		var a: float = TAU * float(i) / float(n) + rng.randf_range(-0.35, 0.35)
		var length: float = radius * rng.randf_range(0.55, 1.0)
		var pts: Array[Vector3] = [Vector3(cos(a), 0, sin(a)) * radius * rng.randf_range(0.05, 0.15)]
		var da: float = a
		var steps: int = 6
		for s: int in steps:
			da += rng.randf_range(-0.5, 0.5)
			pts.append(pts[-1] + Vector3(cos(da), 0, sin(da)) * length / float(steps))
		lines.append([pts, w0 * rng.randf_range(0.8, 1.2)])
		if rng.randf() < 0.65:
			var from: int = rng.randi_range(2, 4)
			var bp: Array[Vector3] = [pts[from]]
			var ba: float = da + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.5, 1.0)
			for s: int in 3:
				ba += rng.randf_range(-0.4, 0.4)
				bp.append(bp[-1] + Vector3(cos(ba), 0, sin(ba)) * length * 0.13)
			lines.append([bp, w0 * 0.6])
	glow_lines(parent, pos, lines, hot, life, up, rim)
	if rich():
		HeroFx.pop(parent, {"amount": 10 + n * 2, "lifetime": 1.3, "shape": "ring", "ring_radius": radius * 0.7,
			"ring_inner": radius * 0.1, "dir": up, "spread": 20.0, "speed": Vector2(0.4, 1.6), "gravity": up * 0.8,
			"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.05, 0.16), "turbulence": 0.8,
			"explosiveness": 0.15, "color": Color(hot.r, hot.g * 0.8, hot.b * 0.6), "box_aabb": radius + 4.0,
			"fade": PackedFloat32Array([0.0, 1.0, 0.7, 0.0])}, pos + up * 0.05, Fx.basis_up(up))


## Draws glowing lines flat on the ground at `pos` (normal `up`): `lines` = [[points (local,
## XZ plane), half-width], ...]. Each has a dark rim, is hottest at its start and cools to a
## dull red, then fades over `life` s.
static func glow_lines(parent: Node, pos: Vector3, lines: Array, hot: Color, life: float, up: Vector3 = Vector3.UP, rim: Color = Color(0.05, 0.02, 0.02, 0.85)) -> void:
	if parent == null or not parent.is_inside_tree() or lines.is_empty():
		return
	var glow := ImmediateMesh.new()
	var dark := ImmediateMesh.new()
	for pass_i: int in 2:
		var im: ImmediateMesh = dark if pass_i == 0 else glow
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for L: Array in lines:
			var pts2: Array[Vector3] = L[0]
			var w: float = float(L[1]) * (3.2 if pass_i == 0 else 1.0)
			for k: int in pts2.size() - 1:
				var a0: Vector3 = pts2[k]
				var a1: Vector3 = pts2[k + 1]
				var side: Vector3 = (a1 - a0).cross(Vector3.UP).normalized()
				var u0: float = float(k) / float(pts2.size() - 1)
				var u1: float = float(k + 1) / float(pts2.size() - 1)
				var ww0: float = w * (1.0 - u0 * 0.85)
				var ww1: float = w * (1.0 - u1 * 0.85)
				var c0 := Color(1, 1, 1, 1.0 - u0 * 0.5)
				var c1 := Color(1, 1, 1, 1.0 - u1 * 0.5)
				if pass_i == 1:
					c0 = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(1.0, 0.55, 0.3, 0.7), u0)
					c1 = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(1.0, 0.55, 0.3, 0.7), u1)
				for v: Array in [[a0 - side * ww0, c0], [a0 + side * ww0, c0], [a1 + side * ww1, c1],
						[a0 - side * ww0, c0], [a1 + side * ww1, c1], [a1 - side * ww1, c1]]:
					im.surface_set_color(v[1])
					im.surface_add_vertex(v[0])
		im.surface_end()
	var root := Node3D.new()
	parent.add_child(root)
	root.global_transform = Transform3D(Fx.basis_up(up), pos + up * 0.03)
	var dark_mat: StandardMaterial3D = _flat_mat(rim, null, 0)
	var glow_m: StandardMaterial3D = _flat_mat(Color(hot.r * 1.3, hot.g * 1.3, hot.b * 1.3, hot.a), null, 1)
	part(root, dark, dark_mat, Vector3.ZERO)
	part(root, glow, glow_m, Vector3(0, 0.01, 0))
	var tw: Tween = root.create_tween()
	tw.tween_property(glow_m, "albedo_color", Color(hot.r * 0.45, hot.g * 0.12, hot.b * 0.05, 1.0), life * 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(glow_m, "albedo_color:a", 0.0, life * 0.55).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(dark_mat, "albedo_color:a", 0.0, life * 0.55).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


## Claw gouges: `n` roughly parallel jagged glowing furrows torn into the ground along `dir`
## (`spacing` m apart, `length` m long) that smoulder and fade over `life` s.
static func claw_gouges(parent: Node, pos: Vector3, dir: Vector3, length: float, n: int = 3, spacing: float = 0.3, hot: Color = Color(2.6, 1.0, 0.25), life: float = 2.2, up: Vector3 = Vector3.UP) -> void:
	var f: Vector3 = Vector3(dir.x, 0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else Vector3.FORWARD
	var side: Vector3 = f.cross(Vector3.UP).normalized()
	var lines: Array = []
	for i: int in n:
		var off: float = (float(i) - float(n - 1) * 0.5) * spacing
		var pts: Array[Vector3] = []
		var steps: int = 7
		for k: int in steps + 1:
			var u: float = float(k) / float(steps)
			var j: float = randf_range(-0.05, 0.05) if k > 0 and k < steps else 0.0
			pts.append(f * (u * length) + side * (off * (0.7 + 0.3 * u) + j))
		lines.append([pts, clampf(length * 0.02, 0.04, 0.07)])
	glow_lines(parent, pos, lines, hot, life, up)
	if rich():
		for i: int in 3:
			HeroFx.pop(parent, {"amount": 6, "lifetime": 1.0, "shape": "sphere", "radius": 0.15, "dir": up, "spread": 25.0,
				"speed": Vector2(0.3, 1.2), "gravity": up * 0.6, "facing": "velocity", "tex": Fx.Tex.SPARK,
				"size": Vector2(0.04, 0.14), "turbulence": 0.8, "explosiveness": 0.1, "color": Color(hot.r, hot.g * 0.8, hot.b * 0.6),
				"fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0])}, pos + f * length * (0.25 + 0.3 * float(i)) + up * 0.05)

## Lingering embers drifting up and around from a volume (`radius`) for about `life` s.
static func embers(parent: Node, pos: Vector3, radius: float, color: Color = Color(2.6, 1.1, 0.3), amount: int = 30, life: float = 1.8, rise: float = 1.5) -> void:
	HeroFx.pop(parent, {"amount": amount, "lifetime": life, "shape": "sphere", "radius": radius, "dir": Vector3.UP,
		"spread": 60.0, "speed": Vector2(0.3, rise), "gravity": Vector3(0, rise * 0.6, 0), "damping": Vector2(0.3, 0.8),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.05, 0.17), "turbulence": 1.4, "explosiveness": 0.25,
		"scale": Vector2(0.6, 1.3), "color": color, "box_aabb": radius + life * rise + 3.0,
		"fade": PackedFloat32Array([0.0, 1.0, 0.8, 0.0])}, pos)


## A wall of dust thrown out along the ground (a big blast's skirt): tall soft puffs rolling
## outward, plus low fast streaks.
static func dust_wall(parent: Node, pos: Vector3, radius: float, color: Color = Color(0.85, 0.8, 0.72, 0.7), amount: int = 26) -> void:
	var fade: float = camera_clear(pos, radius * 0.6)
	HeroFx.pop(parent, {"amount": amount, "lifetime": 1.3, "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, clampf(radius * 0.55, 0.8, 3.2)),
		"shape": "ring", "ring_radius": radius * 0.25, "ring_inner": radius * 0.1, "dir": Vector3(1, 0.3, 0), "spread": 180.0,
		"flatness": 0.8, "speed": Vector2(radius * 1.6, radius * 3.0), "damping": Vector2(radius * 1.8, radius * 2.6),
		"gravity": Vector3(0, 0.6, 0), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-40, 40),
		"color": Color(color.r, color.g, color.b, color.a * (0.35 + 0.65 * fade)), "box_aabb": radius * 3.0 + 4.0,
		"fade": PackedFloat32Array([0.0, 0.9, 0.5, 0.0])}, pos + Vector3(0, 0.2, 0))
	HeroFx.pop(parent, {"amount": amount, "lifetime": 0.5, "shape": "ring", "ring_radius": radius * 0.2, "ring_inner": 0.1,
		"dir": Vector3(1, 0.1, 0), "spread": 180.0, "flatness": 0.95, "speed": Vector2(radius * 3.0, radius * 5.0),
		"damping": Vector2(radius * 4.0, radius * 6.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.12, 0.9), "additive": false, "color": Color(color.r, color.g, color.b, color.a * 0.8),
		"box_aabb": radius * 3.0 + 4.0}, pos + Vector3(0, 0.15, 0))


## Chunks flung out of a blast on real arcs: each glows and trails fire and smoke, and where it
## lands it bursts into sparks and leaves a little scorch (`hot` = its glow, `rock` = its body).
## `up` 0..1 = how steep they fly.
static func burning_debris(parent: Node, pos: Vector3, amount: int = 8, speed: float = 9.0, hot: Color = Color(2.4, 0.9, 0.2), rock: Color = Color(0.22, 0.18, 0.2), up: float = 0.7, flame: bool = true) -> void:
	if parent == null or not parent.is_inside_tree() or not (parent is Node3D):
		return
	var space: PhysicsDirectSpaceState3D = (parent as Node3D).get_world_3d().direct_space_state
	var n: int = maxi(1, roundi(float(amount) * minf(quality_scale(), 1.6)))
	var g := Vector3(0, -22.0, 0)
	var chunk_mat: StandardMaterial3D = solid_mat(rock, 0.0, 0.9)
	var core_mat: StandardMaterial3D = glow_mat(hot, 1.0)
	var trail_o: Dictionary = {"amount": 22, "lifetime": 0.45, "fixed_fps": 0,
		"speed": Vector2(0.0, 0.4), "spread": 180.0, "gravity": Vector3(0, 1.5, 0), "curve": "shrink",
		"tex": Fx.Tex.SMOKE, "additive": false, "angle": Vector2(0, 360), "box_aabb": 30.0,
		"colors": PackedColorArray([Color(hot.r, hot.g, hot.b, 0.9), Color(hot.r * 0.6, hot.g * 0.3, hot.b * 0.2, 0.6), Color(0.2, 0.18, 0.2, 0.4), Color(0.2, 0.18, 0.2, 0.0)]),
		"color_offsets": PackedFloat32Array([0.0, 0.25, 0.55, 1.0])}
	if not flame:
		trail_o = {"amount": 12, "lifetime": 0.5, "fixed_fps": 0, "speed": Vector2(0.0, 0.3), "spread": 180.0,
			"curve": "puff", "tex": Fx.Tex.SMOKE, "additive": false, "angle": Vector2(0, 360), "box_aabb": 30.0,
			"color": Color(minf(rock.r * 2.5, 1.0), minf(rock.g * 2.5, 1.0), minf(rock.b * 2.5, 1.0), 0.5), "fade": PackedFloat32Array([0.8, 0.0])}
	for i: int in n:
		var a: float = randf() * TAU
		var v0: Vector3 = (Vector3(cos(a), lerpf(0.4, 1.8, up) * randf_range(0.7, 1.2), sin(a))).normalized() * speed * randf_range(0.55, 1.0)
		var land_t: float = 1.6
		var land_p: Vector3 = Vector3.INF
		var land_n: Vector3 = Vector3.UP
		var prev: Vector3 = pos
		var t: float = 0.0
		while t < 1.6:
			t += 0.05
			var q: Vector3 = pos + v0 * t + g * (0.5 * t * t)
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(prev, q, 1))
			if not hit.is_empty() and t > 0.08:
				land_t = t
				land_p = hit["position"]
				land_n = hit["normal"]
				break
			prev = q
		var root := Node3D.new()
		parent.add_child(root)
		root.global_position = pos
		var body := Node3D.new()
		root.add_child(body)
		var sz: float = randf_range(0.12, 0.26)
		part(body, box_mesh(Vector3.ONE * sz), chunk_mat, Vector3.ZERO, Vector3(1.0, 0.7, 0.85), Vector3(randf() * 90, randf() * 90, 0))
		if flame:
			part(body, sphere_mesh(sz * 0.55, 8), core_mat, Vector3.ZERO)
		var to: Dictionary = trail_o.duplicate()
		to["size"] = sz * 2.2
		var trail: GPUParticles3D = HeroFx.em(to)
		root.add_child(trail)
		var spin := Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		var tw: Tween = root.create_tween()
		tw.tween_method(func(tt: float) -> void:
			if is_instance_valid(root):
				root.global_position = pos + v0 * tt + g * (0.5 * tt * tt)
				body.rotation = spin * tt, 0.0, land_t, land_t)
		var lp: Vector3 = land_p
		var ln: Vector3 = land_n
		tw.tween_callback(func() -> void:
			if not is_instance_valid(root) or not root.is_inside_tree():
				return
			trail.emitting = false
			body.visible = false
			if lp != Vector3.INF:
				HeroFx.sparks(parent, lp + ln * 0.05, Color(hot.r, hot.g * 0.9, hot.b * 0.7), 10, 5.0, ln, 70.0, 0.3)
				HeroFx.pop(parent, {"amount": 5, "lifetime": 0.6, "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.45,
					"speed": Vector2(0.3, 1.0), "spread": 60.0, "dir": ln, "curve": "puff", "angle": Vector2(0, 360),
					"color": Color(0.3, 0.27, 0.28, 0.5), "fade": PackedFloat32Array([0.0, 0.8, 0.0])}, lp + ln * 0.1)
				if rich() and flame:
					scorch(parent, lp, sz * 3.0, 1.2, Color(hot.r * 0.4, hot.g * 0.4, hot.b * 0.4)))
		tw.tween_interval(0.6)
		tw.tween_callback(root.queue_free)


## A mushroom of fire: a column boiling up from `pos` to `height`, a cap rolling outward at
## the top, a smoke skirt at the foot and embers raining out of it.
static func fire_mushroom(parent: Node, pos: Vector3, height: float, radius: float, hot: Color = Color(2.4, 1.5, 0.6), mid: Color = Color(1.9, 0.55, 0.08), smoke_col: Color = Color(0.2, 0.15, 0.18, 0.75)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var fade: float = 0.35 + 0.65 * camera_clear(pos + Vector3(0, height * 0.5, 0), radius + height * 0.3)
	var cols := PackedColorArray([hot, mid, Color(smoke_col.r, smoke_col.g, smoke_col.b, smoke_col.a * fade), Color(smoke_col.r, smoke_col.g, smoke_col.b, 0.0)])
	var offs := PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
	# the stem
	HeroFx.pop(parent, {"amount": 26, "lifetime": 1.5, "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, radius * 0.8),
		"shape": "sphere", "radius": radius * 0.25, "dir": Vector3.UP, "spread": 10.0, "speed": Vector2(height * 1.2, height * 2.2),
		"damping": Vector2(height * 1.1, height * 1.6), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-60, 60),
		"explosiveness": 0.55, "colors": cols, "color_offsets": offs, "box_aabb": height + radius * 3.0}, pos)
	# the cap: rolls out at the top a beat later
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos + Vector3(0, height, 0)
	var tw: Tween = root.create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(root) or not root.is_inside_tree():
			return
		HeroFx.pop(root, {"amount": 30, "lifetime": 1.6, "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, radius * 1.0),
			"shape": "ring", "ring_radius": radius * 0.35, "ring_inner": radius * 0.1, "dir": Vector3(1, 0.35, 0), "spread": 180.0,
			"flatness": 0.55, "speed": Vector2(radius * 1.2, radius * 2.4), "damping": Vector2(radius * 1.2, radius * 1.8),
			"gravity": Vector3(0, 0.8, 0), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-50, 50),
			"explosiveness": 0.7, "colors": cols, "color_offsets": offs, "box_aabb": radius * 4.0 + 3.0}, root.global_position)
		HeroFx.pop(root, {"amount": 20, "lifetime": 0.8, "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, true, radius * 0.7),
			"shape": "sphere", "radius": radius * 0.35, "spread": 180.0, "speed": Vector2(radius * 0.6, radius * 1.4),
			"damping": Vector2(radius, radius * 1.5), "curve": "puff", "angle": Vector2(0, 360),
			"colors": PackedColorArray([hot, Color(mid.r, mid.g, mid.b, 0.6), Color(mid.r, mid.g, mid.b, 0.0)]), "box_aabb": radius * 4.0 + 3.0}, root.global_position)
		if rich():
			embers(root, root.global_position, radius * 0.8, Color(hot.r, hot.g * 0.7, hot.b * 0.4), 30, 2.2, 1.2))
	tw.tween_interval(2.6)
	tw.tween_callback(root.queue_free)
	# the skirt of smoke at the foot
	HeroFx.pop(parent, {"amount": 16, "lifetime": 1.4, "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, radius * 0.8),
		"shape": "ring", "ring_radius": radius * 0.4, "ring_inner": radius * 0.2, "dir": Vector3(1, 0.1, 0), "spread": 180.0,
		"flatness": 0.9, "speed": Vector2(radius * 1.5, radius * 2.5), "damping": Vector2(radius * 1.6, radius * 2.2),
		"curve": "puff", "angle": Vector2(0, 360), "colors": cols, "color_offsets": PackedFloat32Array([0.0, 0.08, 0.35, 1.0]),
		"box_aabb": radius * 4.0 + 3.0}, pos + Vector3(0, 0.2, 0))


## Lightning crawling over a sphere's surface: `n` short bolts between random points on it.
static func lightning_shell(parent: Node, center: Vector3, radius: float, color: Color, n: int = 4, time: float = 0.12) -> void:
	for i: int in n:
		var a: Vector3 = Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1)).normalized()
		var b: Vector3 = (a + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.9).normalized()
		var prev: Vector3 = center + a * radius
		var segs: int = 5
		for s: int in range(1, segs + 1):
			var k: float = float(s) / float(segs)
			var d: Vector3 = a.slerp(b, k).normalized()
			var p: Vector3 = center + d * radius * (1.0 + randf_range(-0.06, 0.12)) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * radius * 0.05
			beam(parent, prev, p, color, 0.035, time, 5.0)
			beam(parent, prev, p, Color(color.r, color.g, color.b, 0.3), 0.12, time * 0.8, 1.6)
			prev = p


## A glowing footprint pressed into the ground that cools and fades (fire runners).
static func footprint(parent: Node, pos: Vector3, facing_dir: Vector3, hot: Color = Color(2.4, 0.9, 0.2), life: float = 1.6, size: float = 0.36) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if not _mats.has("print_mesh"):
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		_mats["print_mesh"] = pm
	var m: StandardMaterial3D = _flat_mat(hot, dot_texture(), 1)
	var mi := MeshInstance3D.new()
	mi.mesh = _mats["print_mesh"]
	mi.material_override = m
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var f: Vector3 = Vector3(facing_dir.x, 0, facing_dir.z)
	var b: Basis = facing(f) if f.length() > 0.01 else Basis.IDENTITY
	mi.global_transform = Transform3D(b * Basis.from_scale(Vector3(size * 0.62, 1.0, size)), pos + Vector3(0, 0.04, 0))
	var tw: Tween = mi.create_tween()
	tw.tween_property(m, "albedo_color", Color(hot.r * 0.35, hot.g * 0.08, 0.02, 0.9), life * 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color", Color(0.06, 0.04, 0.04, 0.0), life * 0.65).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## Frost spreading over the ground (a frozen racer's feet): a pale icy sheen, white crystal
## cracks and a low creeping mist, melting away over `life` s.
static func frost_patch(parent: Node, pos: Vector3, radius: float, life: float = 3.0, up: Vector3 = Vector3.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if not _mats.has("print_mesh"):
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		_mats["print_mesh"] = pm
	var m: StandardMaterial3D = _flat_mat(Color(0.85, 0.96, 1.0, 0.0), dot_texture(), 0)
	var mi := MeshInstance3D.new()
	mi.mesh = _mats["print_mesh"]
	mi.material_override = m
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D(Fx.basis_up(up) * Basis.from_scale(Vector3.ONE * radius * 2.2), pos + up * 0.03)
	var tw: Tween = mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.75, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_interval(life * 0.5)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	ground_cracks(parent, pos, radius, Color(1.5, 1.9, 2.3), 9, life, 0, up, Color(0.55, 0.8, 0.95, 0.45))
	HeroFx.pop(parent, {"amount": 18, "lifetime": 1.6, "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, 1.0),
		"shape": "ring", "ring_radius": radius * 0.6, "ring_inner": radius * 0.2, "dir": Vector3(1, 0.05, 0), "spread": 180.0,
		"flatness": 0.9, "speed": Vector2(0.4, 1.2), "damping": Vector2(0.4, 0.8), "curve": "puff", "angle": Vector2(0, 360),
		"explosiveness": 0.5, "color": Color(0.92, 0.97, 1.0, 0.45), "fade": PackedFloat32Array([0.0, 0.8, 0.5, 0.0]),
		"box_aabb": radius * 3.0}, pos + up * 0.2)


## A small jagged electric arc between two points (no light, no sparks): a white core in a
## coloured glow that flickers out over `time`.
static func arc_between(parent: Node, a: Vector3, b: Vector3, color: Color, time: float = 0.1, segs: int = 5) -> void:
	var prev: Vector3 = a
	var d: Vector3 = b - a
	var jit: float = d.length() * 0.12
	for i: int in range(1, segs + 1):
		var k: float = float(i) / float(segs)
		var p: Vector3 = a + d * k
		if i < segs:
			p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jit
		beam(parent, prev, p, Color(1.0, 1.0, 1.0).lerp(color, 0.3), 0.025, time, 4.0)
		beam(parent, prev, p, Color(color.r, color.g, color.b, 0.3), 0.09, time * 0.8, 1.6)
		prev = p
