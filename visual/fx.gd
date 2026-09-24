class_name Fx
extends RefCounted
## Shared particle-effect library. Purely cosmetic: nothing built here collides,
## pushes or times anything.
##
## Everything is a GPUParticles3D configured from a small option Dictionary (see
## `emitter`), with named presets on top: soft `burst`s, velocity-stretched `sparks`,
## flat `shockwave` rings, rising `embers`, `smoke` puffs, lit `debris` chunks and
## world-space `trail`s. Textures, draw materials and quad meshes are built once and
## shared (colour comes from the particle, so one material serves every tint).
## Emitter sizes are scaled by Settings.particle_scale() (see `density`).
##
## Typical use:
##   var sp := Fx.sparks({"color": Color(2, 1.4, 0.4), "amount": 24})
##   add_child(sp)
##   ...
##   sp.restart()                            # a prebuilt one-shot, fired on the event
## or, for a rare one-off that cleans up after itself:
##   Fx.spawn(self, Fx.burst({...}), global_position)

enum Tex { DOT, RING, STAR, SMOKE, SPARK, PETAL, BUBBLE }

## Render layer used for effects that should stay out of the player's blob-shadow
## decal (it culls layer 1 only) - same as the character layer.
const LAYER: int = 2

static var _textures: Dictionary = {}
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _curves: Dictionary = {}


# ---- quality -------------------------------------------------------------------------

## Particle density for the graphics quality setting (Settings.particle_scale()):
## Low 0.45, Medium 0.75, High 1, Ultra 1.75.
static func density() -> float:
	var st: Object = Engine.get_main_loop()
	if st is SceneTree and (st as SceneTree).root != null:
		var s: Node = (st as SceneTree).root.get_node_or_null("Settings")
		if s != null and s.has_method("particle_scale"):
			return float(s.call("particle_scale"))
	return 1.0


## True on Ultra: the few extras that only the top tier pays for (extra layers, lights).
static func ultra() -> bool:
	return density() > 1.2


## `n` particles scaled by density (never below 1).
static func count(n: int) -> int:
	return maxi(1, roundi(float(n) * density()))


# ---- textures ------------------------------------------------------------------------

static func texture(kind: Tex) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var t: Texture2D
	match kind:
		Tex.DOT:
			t = _radial(PackedFloat32Array([0.0, 0.18, 0.55, 1.0]), PackedFloat32Array([1.0, 0.85, 0.28, 0.0]), 64)
		Tex.RING:
			t = _radial(PackedFloat32Array([0.0, 0.58, 0.78, 0.86, 1.0]), PackedFloat32Array([0.0, 0.0, 1.0, 0.55, 0.0]), 128)
		Tex.STAR:
			t = _star(64)
		Tex.SMOKE:
			t = _smoke(64)
		Tex.SPARK:
			t = _spark(16, 64)
		Tex.PETAL:
			t = _petal(48)
		Tex.BUBBLE:
			t = _bubble(64)
	_textures[kind] = t
	return t


static func _radial(offsets: PackedFloat32Array, alphas: PackedFloat32Array, px: int) -> GradientTexture2D:
	var g := Gradient.new()
	var cols := PackedColorArray()
	for a: float in alphas:
		cols.append(Color(1, 1, 1, a))
	g.offsets = offsets
	g.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = px
	tex.height = px
	return tex


## Four-point glint: a soft core plus two thin cross flares.
static func _star(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var h: float = float(px - 1) * 0.5
	for y: int in px:
		for x: int in px:
			var u: float = (float(x) - h) / h
			var v: float = (float(y) - h) / h
			var r: float = sqrt(u * u + v * v)
			var core: float = clampf(1.0 - r * 2.4, 0.0, 1.0)
			var flare: float = maxf(clampf(1.0 - absf(u) * 14.0, 0.0, 1.0) * (1.0 - absf(v)), clampf(1.0 - absf(v) * 14.0, 0.0, 1.0) * (1.0 - absf(u)))
			var halo: float = clampf(1.0 - r, 0.0, 1.0) * 0.25
			var a: float = clampf(core * core + flare * flare + halo * halo, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Lumpy soft puff: radial falloff broken up by value noise.
static func _smoke(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var h: float = float(px - 1) * 0.5
	for y: int in px:
		for x: int in px:
			var u: float = (float(x) - h) / h
			var v: float = (float(y) - h) / h
			var r: float = sqrt(u * u + v * v)
			var fall: float = clampf(1.0 - r, 0.0, 1.0)
			fall = fall * fall * (3.0 - 2.0 * fall)
			var n: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(fall * (0.45 + 0.8 * n), 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## A solid little teardrop leaf / petal (tinted per particle; spin it).
static func _petal(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var h: float = float(px - 1) * 0.5
	for y: int in px:
		for x: int in px:
			var u: float = (float(x) - h) / h
			var v: float = (float(y) - h) / h
			# ellipse, pinched toward one end
			var w: float = 0.42 * (1.0 - 0.45 * v)
			var d: float = sqrt(pow(u / maxf(w, 0.05), 2.0) + v * v)
			var a: float = clampf((1.0 - d) * 6.0, 0.0, 1.0)
			var shade: float = 0.82 + 0.18 * clampf(1.0 - absf(u) * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return ImageTexture.create_from_image(img)


## A bubble: thin bright rim, faint body and a highlight glint.
static func _bubble(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var h: float = float(px - 1) * 0.5
	for y: int in px:
		for x: int in px:
			var u: float = (float(x) - h) / h
			var v: float = (float(y) - h) / h
			var r: float = sqrt(u * u + v * v)
			var rim: float = clampf(1.0 - absf(r - 0.86) * 9.0, 0.0, 1.0)
			var body: float = 0.12 * clampf(1.0 - r, 0.0, 1.0) if r < 0.9 else 0.0
			var gl: float = clampf(1.0 - Vector2(u + 0.35, v + 0.35).length() * 5.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(rim * 0.9 + body + gl, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Long soft streak (the quad is stretched along the particle's velocity).
static func _spark(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var u: float = (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v: float = (float(y) + 0.5) / float(h) * 2.0 - 1.0
			var a: float = exp(-u * u * 9.0) * clampf(1.0 - v * v, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# ---- ramps and curves ------------------------------------------------------------------

## Alpha ramp over a particle's life (colour stays white; tint comes from `color`).
static func ramp(alphas: PackedFloat32Array, offsets: PackedFloat32Array = PackedFloat32Array()) -> GradientTexture1D:
	var g := Gradient.new()
	var offs: PackedFloat32Array = offsets
	if offs.is_empty():
		for i: int in alphas.size():
			offs.append(float(i) / float(maxi(alphas.size() - 1, 1)))
	var cols := PackedColorArray()
	for a: float in alphas:
		cols.append(Color(1, 1, 1, a))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


## A colour gradient over life (HDR allowed: values over 1 bloom).
static func color_ramp(colors: PackedColorArray, offsets: PackedFloat32Array = PackedFloat32Array()) -> GradientTexture1D:
	var g := Gradient.new()
	var offs: PackedFloat32Array = offsets
	if offs.is_empty():
		for i: int in colors.size():
			offs.append(float(i) / float(maxi(colors.size() - 1, 1)))
	g.offsets = offs
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	t.width = 64
	return t


## Named scale-over-life curves: "shrink" 1->0, "grow" 0.2->1, "pop" 0->1->0,
## "puff" 0.35->1 easing out, "flat" 1.
static func curve(name: String) -> CurveTexture:
	if _curves.has(name):
		return _curves[name]
	var c := Curve.new()
	match name:
		"shrink":
			c.add_point(Vector2(0.0, 1.0))
			c.add_point(Vector2(1.0, 0.0))
		"grow":
			c.add_point(Vector2(0.0, 0.2), 0.0, 2.0)
			c.add_point(Vector2(1.0, 1.0))
		"pop":
			c.add_point(Vector2(0.0, 0.0))
			c.add_point(Vector2(0.2, 1.0))
			c.add_point(Vector2(1.0, 0.0))
		"puff":
			c.add_point(Vector2(0.0, 0.35), 0.0, 2.2)
			c.add_point(Vector2(1.0, 1.0))
		_:
			c.add_point(Vector2(0.0, 1.0))
			c.add_point(Vector2(1.0, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	_curves[name] = t
	return t


# ---- draw materials and meshes ---------------------------------------------------------

## Shared unshaded draw material. `facing`: "billboard" (camera-facing sprite),
## "none" (the particle transform decides: velocity-stretched or flat).
static func material(tex: Tex, additive: bool, facing: String = "billboard") -> StandardMaterial3D:
	var key: String = "%d|%s|%s" % [tex, additive, facing]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture(tex)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if facing == "billboard":
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_materials[key] = m
	return m


## Shared quad for a material and size. `flat` lies in the local XZ plane (rings).
static func quad(mat: Material, size: Vector2, flat: bool = false) -> Mesh:
	var key: String = "%d|%s|%s" % [mat.get_instance_id(), size, flat]
	if _meshes.has(key):
		return _meshes[key]
	var q := QuadMesh.new()
	q.size = size
	if flat:
		q.orientation = PlaneMesh.FACE_Y
	q.material = mat
	_meshes[key] = q
	return q


## Small lit chunk for debris (vertex colour tints it, the scale curve shrinks it away).
static func chunk_mesh(size: float) -> Mesh:
	var key: String = "chunk|%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var b := BoxMesh.new()
	b.size = Vector3.ONE * size
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	b.material = m
	_meshes[key] = b
	return b


# ---- the generic emitter ------------------------------------------------------------------

## Builds (does not add) a GPUParticles3D from options. Keys (all optional):
##   amount:int (scaled by density; "exact_amount": true keeps it)   lifetime:float
##   one_shot:bool   explosiveness:float   randomness:float   preprocess:float
##   local:bool (particles follow the node)   emitting:bool (continuous ones start on)
##   fixed_fps:int (simulation rate; 0 = every frame, smooth world-space trails)
##   tex:Tex   additive:bool   size:float|Vector2   facing:"billboard"|"velocity"|"flat"|"mesh"
##   mesh:Mesh (for facing "mesh")   color:Color (HDR ok)   fade:PackedFloat32Array alpha-over-life
##   colors:PackedColorArray colour-over-life   pick:PackedColorArray (each particle picks one)
##   shape:"point"|"sphere"|"shell"|"box"|"ring"   radius   extents:Vector3   ring_radius
##   ring_inner   ring_axis:Vector3   ring_height   offset:Vector3
##   dir:Vector3   spread   flatness   speed:Vector2 (min,max)   gravity:Vector3
##   damping:Vector2   radial:Vector2 (radial accel)   linear:Vector2   radial_vel:Vector2
##   scale:Vector2   curve:String (see `curve`)   angle:Vector2   spin:Vector2
##   turbulence:float (noise strength)   hue:float (+- hue variation)   aabb:AABB   layers:int
static func emitter(o: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var n: int = int(o.get("amount", 16))
	p.amount = n if bool(o.get("exact_amount", false)) else count(n)
	p.lifetime = float(o.get("lifetime", 0.6))
	p.one_shot = bool(o.get("one_shot", false))
	p.explosiveness = float(o.get("explosiveness", 0.0))
	p.randomness = float(o.get("randomness", 0.0))
	p.preprocess = float(o.get("preprocess", 0.0))
	p.local_coords = bool(o.get("local", false))
	p.fixed_fps = int(o.get("fixed_fps", 30))
	p.emitting = bool(o.get("emitting", not p.one_shot))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = int(o.get("layers", 1))
	if o.has("aabb"):
		p.visibility_aabb = o["aabb"]
	var pm := ParticleProcessMaterial.new()
	match String(o.get("shape", "point")):
		"sphere":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = float(o.get("radius", 0.5))
		"shell":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			pm.emission_sphere_radius = float(o.get("radius", 0.5))
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = o.get("extents", Vector3.ONE * 0.5)
		"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = o.get("ring_axis", Vector3.UP)
			pm.emission_ring_radius = float(o.get("ring_radius", 1.0))
			pm.emission_ring_inner_radius = float(o.get("ring_inner", 0.0))
			pm.emission_ring_height = float(o.get("ring_height", 0.02))
	if o.has("offset"):
		pm.emission_shape_offset = o["offset"]
	pm.direction = o.get("dir", Vector3.UP)
	pm.spread = float(o.get("spread", 45.0))
	pm.flatness = float(o.get("flatness", 0.0))
	var sp: Vector2 = o.get("speed", Vector2(1.0, 2.0))
	pm.initial_velocity_min = sp.x
	pm.initial_velocity_max = sp.y
	pm.gravity = o.get("gravity", Vector3.ZERO)
	var dm: Vector2 = o.get("damping", Vector2.ZERO)
	pm.damping_min = dm.x
	pm.damping_max = dm.y
	if o.has("radial"):
		var ra: Vector2 = o["radial"]
		pm.radial_accel_min = ra.x
		pm.radial_accel_max = ra.y
	if o.has("linear"):
		var la: Vector2 = o["linear"]
		pm.linear_accel_min = la.x
		pm.linear_accel_max = la.y
	if o.has("radial_vel"):
		var rv: Vector2 = o["radial_vel"]
		pm.radial_velocity_min = rv.x
		pm.radial_velocity_max = rv.y
	var sc: Vector2 = o.get("scale", Vector2(0.7, 1.0))
	pm.scale_min = sc.x
	pm.scale_max = sc.y
	if o.has("curve"):
		pm.scale_curve = curve(String(o["curve"]))
	if o.has("angle"):
		var an: Vector2 = o["angle"]
		pm.angle_min = an.x
		pm.angle_max = an.y
	if o.has("spin"):
		var sn: Vector2 = o["spin"]
		pm.angular_velocity_min = sn.x
		pm.angular_velocity_max = sn.y
	if o.has("turbulence"):
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = float(o["turbulence"])
		pm.turbulence_noise_scale = float(o.get("turbulence_scale", 4.0))
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	if o.has("hue"):
		pm.hue_variation_min = -float(o["hue"])
		pm.hue_variation_max = float(o["hue"])
	pm.color = o.get("color", Color.WHITE)
	if o.has("colors"):
		pm.color_ramp = color_ramp(o["colors"], o.get("color_offsets", PackedFloat32Array()))
	else:
		pm.color_ramp = ramp(o.get("fade", PackedFloat32Array([1.0, 0.0])), o.get("fade_offsets", PackedFloat32Array()))
	if o.has("pick"):
		var pick: PackedColorArray = o["pick"]
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var offs := PackedFloat32Array()
		for i: int in pick.size():
			offs.append(float(i) / float(pick.size()))
		g.offsets = offs
		g.colors = pick
		var gt := GradientTexture1D.new()
		gt.gradient = g
		gt.use_hdr = true
		pm.color_initial_ramp = gt
	var facing: String = String(o.get("facing", "billboard"))
	var tex: Tex = o.get("tex", Tex.DOT)
	var additive: bool = bool(o.get("additive", true))
	var size_v: Variant = o.get("size", 0.3)
	var size: Vector2 = size_v if size_v is Vector2 else Vector2.ONE * float(size_v)
	match facing:
		"velocity":
			pm.particle_flag_align_y = true
			p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
			p.draw_pass_1 = quad(material(tex, additive, "none"), size)
		"flat":
			p.draw_pass_1 = quad(material(tex, additive, "none"), size, true)
		"mesh":
			p.draw_pass_1 = o["mesh"]
		_:
			p.draw_pass_1 = quad(material(tex, additive, "billboard"), size)
	p.process_material = pm
	return p


# ---- presets --------------------------------------------------------------------------------

## Explosive one-shot of soft glowing dots.
static func burst(o: Dictionary = {}) -> GPUParticles3D:
	var d: Dictionary = {
		"amount": 24, "lifetime": 0.6, "one_shot": true, "explosiveness": 0.95,
		"spread": 180.0, "speed": Vector2(2.0, 5.0), "damping": Vector2(3.0, 5.0),
		"scale": Vector2(0.5, 1.0), "curve": "shrink", "size": 0.25,
	}
	d.merge(o, true)
	return emitter(d)


## Hot streaks stretched along their velocity; one-shot by default.
static func sparks(o: Dictionary = {}) -> GPUParticles3D:
	var d: Dictionary = {
		"amount": 24, "lifetime": 0.5, "one_shot": true, "explosiveness": 0.9,
		"spread": 70.0, "speed": Vector2(4.0, 9.0), "gravity": Vector3(0, -14.0, 0),
		"damping": Vector2(1.0, 3.0), "scale": Vector2(0.6, 1.0), "curve": "shrink",
		"facing": "velocity", "tex": Tex.SPARK, "size": Vector2(0.06, 0.45),
		"color": Color(2.4, 1.6, 0.6),
	}
	d.merge(o, true)
	return emitter(d)


## One flat ring that swells from the emitter's origin in its local XZ plane (orient
## the node so its local Y is the ring's normal). `radius` is the final radius.
static func shockwave(radius: float, o: Dictionary = {}) -> GPUParticles3D:
	var d: Dictionary = {
		"amount": 1, "exact_amount": true, "lifetime": 0.4, "one_shot": true, "explosiveness": 1.0,
		"speed": Vector2.ZERO, "spread": 0.0, "facing": "flat", "tex": Tex.RING, "size": 1.0,
		"scale": Vector2(radius * 2.0, radius * 2.0), "curve": "grow",
		"fade": PackedFloat32Array([1.0, 0.8, 0.0]), "color": Color(1.6, 1.6, 1.6),
	}
	d.merge(o, true)
	return emitter(d)


## Continuous slow risers (embers, motes, bubbles).
static func embers(o: Dictionary = {}) -> GPUParticles3D:
	var d: Dictionary = {
		"amount": 12, "lifetime": 1.6, "shape": "box", "extents": Vector3(1, 0.1, 1),
		"dir": Vector3.UP, "spread": 15.0, "speed": Vector2(0.4, 1.1),
		"fade": PackedFloat32Array([0.0, 1.0, 0.8, 0.0]), "scale": Vector2(0.5, 1.0),
		"size": 0.14, "color": Color(2.0, 0.5, 0.2), "turbulence": 0.6,
	}
	d.merge(o, true)
	return emitter(d)


## Expanding soft puffs (dust, steam, smoke). Mix blend by default.
static func smoke(o: Dictionary = {}) -> GPUParticles3D:
	var d: Dictionary = {
		"amount": 12, "lifetime": 0.9, "one_shot": true, "explosiveness": 0.85,
		"tex": Tex.SMOKE, "additive": false, "size": 0.7, "spread": 60.0,
		"speed": Vector2(1.0, 2.5), "damping": Vector2(2.0, 4.0), "curve": "puff",
		"fade": PackedFloat32Array([0.0, 0.7, 0.35, 0.0]), "fade_offsets": PackedFloat32Array([0.0, 0.12, 0.55, 1.0]),
		"angle": Vector2(0.0, 360.0), "spin": Vector2(-40.0, 40.0), "color": Color(1, 1, 1, 0.8),
	}
	d.merge(o, true)
	return emitter(d)


## Tumbling lit chunks that fall and shrink away.
static func debris(o: Dictionary = {}) -> GPUParticles3D:
	var d: Dictionary = {
		"amount": 14, "lifetime": 0.9, "one_shot": true, "explosiveness": 0.95,
		"facing": "mesh", "mesh": chunk_mesh(float(o.get("chunk", 0.14))), "spread": 70.0,
		"speed": Vector2(3.0, 6.0), "gravity": Vector3(0, -22.0, 0), "scale": Vector2(0.5, 1.2),
		"curve": "shrink", "spin": Vector2(-400.0, 400.0), "angle": Vector2(0.0, 360.0),
		"color": Color(0.55, 0.5, 0.45), "fade": PackedFloat32Array([1.0, 1.0]),
	}
	d.merge(o, true)
	return emitter(d)


## A world-space trail: stationary dots left behind a moving emitter. Simulated every
## frame (at the default 30 steps a fast emitter leaves a string of separate beads).
static func trail(o: Dictionary = {}) -> GPUParticles3D:
	var d: Dictionary = {
		"amount": 30, "lifetime": 0.4, "emitting": false, "speed": Vector2(0.0, 0.2), "fixed_fps": 0,
		"spread": 180.0, "curve": "shrink", "size": 0.3, "color": Color(1.2, 1.2, 1.2),
	}
	d.merge(o, true)
	return emitter(d)


## A camera-facing glowing sprite (not a particle): gleams, lens glints, cores.
## The material is shared per colour and texture; `own_material` gives a private copy
## (for fading one sprite's alpha on its own).
static func sprite(color: Color, size: float, tex: Tex = Tex.STAR, own_material: bool = false) -> MeshInstance3D:
	var key: String = "sprite|%s|%d" % [color, tex]
	var m: StandardMaterial3D = _materials.get(key)
	if m == null or own_material:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = texture(tex)
		m.albedo_color = color
		m.disable_receive_shadows = true
		if not own_material:
			_materials[key] = m
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---- one-off helpers ------------------------------------------------------------------------

## Adds a one-shot emitter to `parent` at `at` (global), fires it and frees it when done.
static func spawn(parent: Node, p: GPUParticles3D, at: Vector3, basis: Basis = Basis.IDENTITY) -> GPUParticles3D:
	p.one_shot = true
	p.emitting = false
	parent.add_child(p)
	p.global_transform = Transform3D(basis, at)
	p.finished.connect(p.queue_free)
	p.restart()
	return p


## Fires a prebuilt one-shot at a global point (and orientation).
static func fire(p: GPUParticles3D, at: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	if p == null or not p.is_inside_tree():
		return
	p.global_transform = Transform3D(basis, at)
	p.restart()


## A basis whose local Y is `up` (for shockwaves and radial kicks on any surface).
static func basis_up(up: Vector3) -> Basis:
	var y: Vector3 = up.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = ref.cross(y).normalized()
	return Basis(x, y, x.cross(y))


## A brief light flash that frees itself (no shadows). Skipped on Low quality.
static func flash(parent: Node, at: Vector3, color: Color, energy: float = 4.0, light_range: float = 6.0, time: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree() or density() < 0.5:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = at
	var tw: Tween = l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)


## Reusable flash on an existing light: jump to `energy`, ease back to `rest`.
static func pulse(light: Light3D, energy: float, rest: float = 0.0, time: float = 0.35) -> void:
	if light == null or not light.is_inside_tree():
		return
	light.light_energy = energy
	light.visible = true
	var tw: Tween = light.create_tween()
	tw.tween_property(light, "light_energy", rest, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if rest <= 0.0:
		tw.tween_callback(light.hide)


## HDR tint: `c` brightened so additive particles bloom under the glow pass.
static func hot(c: Color, k: float = 2.0) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)
