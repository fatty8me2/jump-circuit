class_name HeroFx
extends RefCounted
## Shared looks for the three hero transformations (Nine-Tailed Fox, Hero's Tunic, Golden
## Surge Hair): energy shaders, quality-scaled one-shot emitters, swept slash ribbons, body
## afterimages, a body-following costume rig and a local screen flash.
## Purely cosmetic: nothing here collides, pushes or times anything.
##
## Particles are built with the shared `Fx` library (so their amounts follow Settings.quality:
## Low 45%, Medium 75%, High 100%) on the character render layer; light flashes go through
## `Fx.flash` (skipped on Low). One-shots free themselves on a timer (headless runs never
## signal `finished`).

const LAYER: int = 2

static var _shaders: Dictionary = {}
static var _mats: Dictionary = {}


## Drops the cached shaders / materials (the next use rebuilds them).
static func clear_caches() -> void:
	_shaders.clear()
	_mats.clear()


static func density() -> float:
	return Fx.density()


static func low() -> bool:
	return Fx.density() < 0.5


# ---- emitters ------------------------------------------------------------------------------

## A `Fx.emitter` on the character layer, with a few extras:
##   orbit: float (orbit velocity around the emitter's Y, turns per second)
##   tangential: float (tangential acceleration)
##   box_aabb: float (visibility half-size, default 4)
static func em(o: Dictionary) -> GPUParticles3D:
	var d: Dictionary = o.duplicate()
	if not d.has("layers"):
		d["layers"] = LAYER
	if not d.has("aabb"):
		var h: float = float(d.get("box_aabb", 4.0))
		d["aabb"] = AABB(Vector3.ONE * -h, Vector3.ONE * h * 2.0)
	var p: GPUParticles3D = Fx.emitter(d)
	var pm := p.process_material as ParticleProcessMaterial
	if bool(d.get("align", false)):
		pm.particle_flag_align_y = true
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	if d.has("orbit"):
		pm.orbit_velocity_min = float(d["orbit"]) * 0.8
		pm.orbit_velocity_max = float(d["orbit"])
	if d.has("tangential"):
		pm.tangential_accel_min = float(d["tangential"]) * 0.8
		pm.tangential_accel_max = float(d["tangential"])
	return p


## A teardrop flame (round at the bottom, pointed at the top), white; tinted per particle.
## Use with "facing": "velocity" so the tip trails along the motion.
static func flame_texture() -> Texture2D:
	if _mats.has("flame_tex"):
		return _mats["flame_tex"]
	var w: int = 32
	var h: int = 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var u: float = (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v: float = 1.0 - (float(y) + 0.5) / float(h)   # 0 bottom .. 1 top
			# half-width: a round base swelling to v ~ 0.25, then tapering to a point
			var hw: float = sqrt(clampf(v / 0.25, 0.0, 1.0)) if v < 0.25 else pow(clampf((1.0 - v) / 0.75, 0.0, 1.0), 1.3)
			hw *= 0.9
			var d: float = absf(u) / maxf(hw, 0.001)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			a *= smoothstep(0.0, 0.08, v)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_mats["flame_tex"] = t
	return t


## A velocity-aligned quad with the flame texture (flame tongues). Cached per blend and size.
static func flame_quad(additive: bool, size: Vector2) -> QuadMesh:
	var key: String = "flameq|%s|%s" % [additive, size]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = flame_texture()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = size
	q.material = m
	_mats[key] = q
	return q


## Flame-tongue emitter options: velocity-aligned teardrops (merge into an `em` dictionary).
static func tongues(size: Vector2, additive: bool = false) -> Dictionary:
	return {"facing": "mesh", "mesh": flame_quad(additive, size), "align": true}


## A particle quad whose material fades where it meets geometry (big puffs of smoke and
## fire would otherwise show hard lines where they cut the ground). Cached per texture,
## blend and size.
static func soft_quad(tex: Fx.Tex, additive: bool, size: float) -> QuadMesh:
	var key: String = "soft|%d|%s|%.2f" % [tex, additive, size]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Fx.texture(tex)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = maxf(size * 0.35, 0.3)
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = m
	_mats[key] = q
	return q


## Fires a one-shot emitter at a global point (and orientation), freed on a timer.
static func pop(parent: Node, o: Dictionary, at: Vector3, basis: Basis = Basis.IDENTITY) -> GPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var d: Dictionary = o.duplicate()
	d["one_shot"] = true
	d["emitting"] = false
	if not d.has("explosiveness"):
		d["explosiveness"] = 0.9
	var p: GPUParticles3D = em(d)
	parent.add_child(p)
	p.global_transform = Transform3D(basis, at)
	p.emitting = true
	free_after(p, p.lifetime * (2.0 - p.explosiveness) + 0.4)
	return p


static func free_after(node: Node, after: float) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.get_tree().create_timer(after, false).timeout.connect(node.queue_free)


## Light flash (skipped on Low quality).
static func flash(parent: Node, at: Vector3, color: Color, energy: float = 6.0, light_range: float = 8.0, time: float = 0.35) -> void:
	Fx.flash(parent, at, color, energy, light_range, time)


## Velocity-stretched sparks.
static func sparks(parent: Node, at: Vector3, color: Color, amount: int = 24, speed: float = 9.0, dir: Vector3 = Vector3.UP, spread: float = 70.0, length: float = 0.45) -> void:
	pop(parent, {"amount": amount, "lifetime": 0.45, "spread": spread, "dir": dir,
		"speed": Vector2(speed * 0.45, speed), "gravity": Vector3(0, -14, 0), "damping": Vector2(1.0, 3.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.07, length), "curve": "shrink",
		"color": color}, at)


## Soft glowing burst.
static func burst(parent: Node, at: Vector3, color: Color, amount: int = 30, speed: float = 6.0, size: float = 0.3, life: float = 0.55) -> void:
	pop(parent, {"amount": amount, "lifetime": life, "spread": 180.0, "speed": Vector2(speed * 0.35, speed),
		"damping": Vector2(speed * 0.8, speed * 1.4), "size": size, "curve": "shrink", "color": color,
		"shape": "sphere", "radius": 0.15}, at)


## Glinting stars that pop and twinkle out.
static func stars(parent: Node, at: Vector3, color: Color, amount: int = 10, speed: float = 3.0, size: float = 0.45, radius: float = 0.4) -> void:
	pop(parent, {"amount": amount, "lifetime": 0.6, "spread": 180.0, "speed": Vector2(speed * 0.3, speed),
		"damping": Vector2(speed, speed * 2.0), "size": size, "curve": "pop", "color": color, "tex": Fx.Tex.STAR,
		"shape": "sphere", "radius": radius, "angle": Vector2(0, 360), "spin": Vector2(-180, 180)}, at)


## Flat ground ring (a swelling ring texture) at `at` with normal `up`.
static func ground_ring(parent: Node, at: Vector3, color: Color, radius: float, time: float = 0.4, up: Vector3 = Vector3.UP) -> void:
	pop(parent, {"amount": 1, "exact_amount": true, "lifetime": time, "explosiveness": 1.0, "speed": Vector2.ZERO,
		"spread": 0.0, "facing": "flat", "tex": Fx.Tex.RING, "size": 1.0, "scale": Vector2(radius * 2.0, radius * 2.0),
		"curve": "grow", "fade": PackedFloat32Array([1.0, 0.8, 0.0]), "color": color}, at + up * 0.06, Fx.basis_up(up))


## Dust thrown out along the ground.
static func dust_ring(parent: Node, at: Vector3, color: Color = Color(0.9, 0.85, 0.75, 0.7), radius: float = 1.0, amount: int = 18, speed: float = 5.0) -> void:
	pop(parent, {"amount": amount, "lifetime": 0.8, "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.7,
		"shape": "ring", "ring_radius": radius * 0.4, "ring_inner": radius * 0.2, "dir": Vector3(1, 0.25, 0), "spread": 180.0,
		"flatness": 0.85, "speed": Vector2(speed * 0.5, speed), "damping": Vector2(speed * 0.9, speed * 1.4), "curve": "puff",
		"fade": PackedFloat32Array([0.0, 0.8, 0.3, 0.0]), "angle": Vector2(0, 360), "spin": Vector2(-60, 60),
		"color": color}, at + Vector3(0, 0.15, 0))


## Smoke puff (mix-blended).
static func smoke(parent: Node, at: Vector3, color: Color = Color(0.3, 0.28, 0.3, 0.7), amount: int = 14, size: float = 1.0, life: float = 1.0, speed: float = 2.0) -> void:
	pop(parent, {"amount": amount, "lifetime": life, "facing": "mesh", "mesh": soft_quad(Fx.Tex.SMOKE, false, size),
		"spread": 180.0, "shape": "sphere", "radius": size * 0.3, "speed": Vector2(speed * 0.3, speed),
		"damping": Vector2(speed * 0.8, speed * 1.5), "gravity": Vector3(0, 1.2, 0), "curve": "puff",
		"fade": PackedFloat32Array([0.0, 0.8, 0.4, 0.0]), "angle": Vector2(0, 360), "spin": Vector2(-50, 50),
		"color": color}, at)


# ---- shaders --------------------------------------------------------------------------------

const NOISE_GLSL: String = """
float hfx_h(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float hfx_n(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hfx_h(i), hfx_h(i + vec3(1, 0, 0)), f.x), mix(hfx_h(i + vec3(0, 1, 0)), hfx_h(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hfx_h(i + vec3(0, 0, 1)), hfx_h(i + vec3(1, 0, 1)), f.x), mix(hfx_h(i + vec3(0, 1, 1)), hfx_h(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
"""

## Additive flame shell: a fresnel rim of licking, rising energy (chakra cloak, auras, flame
## fringes). `lick` pushes the surface out in noisy tongues (more on the upper half),
## `stretch` pulls the top up into a pointed flame silhouette.
const FLAME_SHELL: String = """
shader_type spatial;
render_mode unshaded, BLEND, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 core : source_color = vec4(1.0, 0.35, 0.05, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float energy = 2.0;
uniform float alpha = 1.0;
uniform float rise = 2.5;
uniform float lick = 0.1;
uniform float stretch = 0.0;
uniform float grow = 0.0;
uniform float freq = 4.5;
uniform float base_alpha = 0.12;
uniform float band_col = 0.45;
uniform float band_alpha = 0.95;
varying vec3 wpos;
varying float upk;
NOISE
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = hfx_n(w * freq + vec3(0.0, -TIME * rise, TIME * 0.4));
	float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	upk = up;
	VERTEX += NORMAL * (grow + lick * n * (0.35 + up));
	VERTEX.y += stretch * n * up * up * up;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.8);
	vec3 q = wpos * freq * 1.3 + vec3(0.0, -TIME * rise * 1.4, 0.0);
	float n = hfx_n(q) * 0.62 + hfx_n(q * 2.3 + vec3(3.1)) * 0.38;
	float band = smoothstep(0.38, 0.8, n);
	vec3 c = mix(core.rgb, rim.rgb, clamp(fres * 0.9 + band * band_col, 0.0, 1.0));
	ALBEDO = c * energy;
	ALPHA = clamp((base_alpha + fres * 0.95) * (1.0 - band_alpha * 0.55 + band * band_alpha) * (0.7 + upk * 0.5) * alpha, 0.0, 1.0);
}
"""

## Solid energy body (fox tails and ears, the golden hair): unshaded, a hot fresnel rim and
## flowing noise bands. Per-instance tint in INSTANCE_CUSTOM.rgb (multimesh) and
## `dissolve` 0..1 burns it away with glowing ember edges.
const ENERGY_BODY: String = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform vec4 base : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.75, 0.25, 1.0);
uniform float energy = 1.3;
uniform float rim_amt = 0.85;
uniform float dissolve = 0.0;
uniform float flow = 3.0;
uniform float flash = 0.0;
uniform bool use_custom = false;
varying vec3 wpos;
varying vec4 cust;
NOISE
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cust = use_custom ? INSTANCE_CUSTOM : vec4(1.0);
}
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	float n = hfx_n(wpos * 5.5 + vec3(0.0, -TIME * flow, 0.0)) * 0.6 + hfx_n(wpos * 12.0 - vec3(0.0, TIME * flow * 1.7, 0.0)) * 0.4;
	vec3 tint = base.rgb * cust.rgb;
	vec3 c = mix(tint * (0.75 + 0.5 * n), hot.rgb * 1.3, clamp(fres * rim_amt + (n - 0.55) * 0.6 + cust.a - 1.0, 0.0, 1.0));
	c = mix(c, vec3(1.6), flash);
	if (dissolve > 0.0) {
		float e = n - dissolve * 1.1 + 0.05;
		if (e < 0.0) {
			discard;
		}
		c = mix(edge.rgb * 3.0, c, smoothstep(0.0, 0.1, e));
	}
	ALBEDO = c * energy;
}
"""

## Additive energy beam along a unit cylinder's Y: a white-hot core, shimmering scrolling
## bands and a soft fresnel edge (the Energy Wave).
const BEAM: String = """
shader_type spatial;
render_mode unshaded, BLEND, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform float energy = 2.5;
uniform float alpha = 1.0;
uniform float scroll = 18.0;
uniform float length_m = 10.0;
uniform float edge_alpha = 0.25;
varying vec3 lpos;
NOISE
void vertex() {
	lpos = VERTEX;
	float n = hfx_n(vec3(VERTEX.y * length_m * 1.5 - TIME * scroll, atan(VERTEX.x, VERTEX.z) * 2.0, TIME * 3.0));
	VERTEX.xz *= 0.88 + 0.24 * n;
}
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float coref = pow(abs(facing), 3.0);
	float along = lpos.y * length_m;
	float n = hfx_n(vec3(along * 0.9 - TIME * scroll, lpos.x * 6.0, lpos.z * 6.0 + TIME * 4.0));
	float bands = 0.6 + 0.4 * sin(along * 2.2 - TIME * scroll * 1.6 + n * 4.0);
	vec3 c = mix(glow.rgb, core.rgb, clamp(coref * 1.1 + n * 0.2, 0.0, 1.0));
	ALBEDO = c * energy * (0.75 + 0.45 * bands);
	float tip = smoothstep(0.5, 0.47, lpos.y) * smoothstep(-0.5, -0.49, lpos.y);
	ALPHA = clamp((edge_alpha + pow(facing, 1.3) * 0.9) * alpha * tip, 0.0, 1.0);
}
"""


static func shader(key: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var code: String = ""
	match key:
		"flame":
			code = FLAME_SHELL.replace("BLEND", "blend_add")
		"flame_mix":
			code = FLAME_SHELL.replace("BLEND", "blend_mix")
		"energy":
			code = ENERGY_BODY
		"beam":
			code = BEAM.replace("BLEND", "blend_add")
		"beam_mix":
			code = BEAM.replace("BLEND", "blend_mix")
	var sh := Shader.new()
	sh.code = code.replace("NOISE", NOISE_GLSL)
	_shaders[key] = sh
	return sh


## A fresh flame-shell material (each costume fades its own).
static func flame_mat(core: Color, rim: Color, energy: float = 2.0, lick: float = 0.1, rise: float = 2.5, mix: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("flame_mix" if mix else "flame")
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("lick", lick)
	m.set_shader_parameter("rise", rise)
	return m


## A fresh energy-body material.
static func energy_mat(base: Color, hot: Color, energy: float = 1.3, flow: float = 3.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("energy")
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("hot", hot)
	m.set_shader_parameter("edge", hot)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("flow", flow)
	return m


static func beam_mat(core: Color, glow: Color, energy: float = 2.5, mix: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("beam_mix" if mix else "beam")
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("energy", energy)
	return m


## Tweens a shader parameter.
static func tween_param(node: Node, mat: ShaderMaterial, param: String, from: float, to: float, time: float) -> Tween:
	var tw: Tween = node.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(param, v), from, to, time)
	return tw


# ---- meshes ---------------------------------------------------------------------------------

static func mesh_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = PartyFx.part(parent, mesh, mat, pos, scl, rot_deg)
	return mi


## A camera-facing glow sprite with its own material (fade its albedo alpha freely).
static func glow_sprite(parent: Node3D, color: Color, size: float, tex: Fx.Tex = Fx.Tex.DOT, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var s: MeshInstance3D = Fx.sprite(color, size, tex, true)
	s.layers = LAYER
	s.position = pos
	parent.add_child(s)
	return s


## A torus ring swelling from `from_r` to `to_r` in the plane facing `normal`, fading out.
## Alpha-blended by default (keeps its colour against a bright sky); additive glows.
static func ring(parent: Node, pos: Vector3, normal: Vector3, color: Color, from_r: float, to_r: float, time: float = 0.35, thick: float = 0.12, additive: bool = false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0 - thick
	tm.outer_radius = 1.0
	tm.rings = 36
	tm.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var n: Vector3 = normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var b0: Basis = Fx.basis_up(n)
	mi.global_transform = Transform3D(b0.scaled(Vector3.ONE * maxf(from_r, 0.01)), pos)
	var a0: float = color.a
	var tw: Tween = mi.create_tween()
	tw.tween_method(func(k: float) -> void:
		var r: float = lerpf(from_r, to_r, 1.0 - pow(1.0 - k, 3.0))
		mi.global_transform = Transform3D(b0.scaled(Vector3.ONE * maxf(r, 0.01)), pos)
		mat.albedo_color.a = a0 * (1.0 - k * k), 0.0, 1.0, time)
	tw.tween_callback(mi.queue_free)


## A sphere swelling (or collapsing) from `from_r` to `to_r` while it fades.
static func orb(parent: Node, pos: Vector3, color: Color, from_r: float, to_r: float, time: float, additive: bool = true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.mesh = PartyFx.sphere_mesh(1.0, 24)
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * maxf(from_r, 0.01)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * maxf(to_r, 0.01), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## A dome of flame (flame-shell shader on a sphere) that swells to `radius` and fades.
static func dome(parent: Node, pos: Vector3, core: Color, rim: Color, radius: float, grow_t: float = 0.35, fade_t: float = 0.5, mix: bool = true, energy: float = 1.6, base_a: float = 0.2) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m: ShaderMaterial = flame_mat(core, rim, energy, 0.1, 3.0, mix)
	m.set_shader_parameter("freq", 1.4)
	m.set_shader_parameter("base_alpha", base_a)
	m.set_shader_parameter("band_col", 0.08)
	m.set_shader_parameter("band_alpha", 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = PartyFx.sphere_mesh(1.0, 32)
	mi.material_override = m
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw: Tween = mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, grow_t).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_method(func(v: float) -> void: m.set_shader_parameter("alpha", v), 1.0, 0.8, grow_t)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("alpha", v), 0.8, 0.0, fade_t).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mi, "scale", Vector3.ONE * radius * 1.08, fade_t)
	tw.tween_callback(mi.queue_free)


## Cartoon fireball: puffy flame balls (alpha-blended, yellow -> orange -> smoke) thrown out.
static func fireball(parent: Node, pos: Vector3, radius: float, amount: int = 26, hot: Color = Color(2.2, 1.6, 0.6), mid: Color = Color(1.8, 0.55, 0.08), smoke_col: Color = Color(0.25, 0.2, 0.22, 0.6)) -> void:
	pop(parent, {"amount": amount, "lifetime": 0.75, "facing": "mesh", "mesh": soft_quad(Fx.Tex.SMOKE, false, radius * 0.7),
		"shape": "sphere", "radius": radius * 0.25, "spread": 180.0, "speed": Vector2(radius * 1.2, radius * 2.8),
		"damping": Vector2(radius * 3.0, radius * 4.5), "gravity": Vector3(0, 1.5, 0), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-90, 90),
		"colors": PackedColorArray([hot, mid, smoke_col, Color(smoke_col.r, smoke_col.g, smoke_col.b, 0.0)]),
		"color_offsets": PackedFloat32Array([0.0, 0.25, 0.6, 1.0])}, pos)


# ---- slash ribbons --------------------------------------------------------------------------

## A glowing swept ribbon around `center` in the plane of `basis` (x right, -z forward) that
## draws itself from angle a0 to a1 (radians, 0 = forward) over `sweep` seconds - a bright
## head with a tapering, fading tail - then fades out over `fade`. `width` is the ribbon's
## half-width at its fattest; `inner` > 0 makes a filled crescent (a sword swing's smear).
static func slash(parent: Node, center: Vector3, basis: Basis, radius: float, a0: float, a1: float,
		color: Color, width: float = 0.25, sweep: float = 0.09, fade: float = 0.22, core: Color = Color(1.4, 1.4, 1.4), additive: bool = false) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D(basis, center)
	var draw := func(k: float, fade_k: float) -> void:
		im.clear_surfaces()
		var steps: int = 22
		var head: float = clampf(k, 0.0, 1.0)
		if head <= 0.01:
			return
		# a soft stroke: three rows (inner edge, bright spine, outer edge), pointed at both ends
		var rows: Array = []
		for i: int in steps + 1:
			var u: float = float(i) / float(steps) * head
			var a: float = lerpf(a0, a1, u)
			var dir := Vector3(sin(a), 0, -cos(a))
			var rel: float = u / head
			var w: float = width * pow(sin(PI * clampf(rel * 0.92 + 0.04, 0.0, 1.0)), 0.6) + 0.01
			var fa: float = smoothstep(0.0, 0.3, rel) * (1.0 - fade_k)
			var spine: Color = color.lerp(core, 0.35 + 0.65 * pow(rel, 2.0))
			spine.a = fa
			var edge_c: Color = color
			edge_c.a = fa * 0.12
			rows.append([dir * (radius - w), dir * radius, dir * (radius + w * 0.6), edge_c, spine])
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i: int in steps:
			var r0: Array = rows[i]
			var r1: Array = rows[i + 1]
			for band: int in 2:
				# quad between row band and band+1 of both steps
				var e0: int = band
				var e1: int = band + 1
				var c00: Color = r0[4] if e0 == 1 else r0[3]
				var c01: Color = r0[4] if e1 == 1 else r0[3]
				var c10: Color = r1[4] if e0 == 1 else r1[3]
				var c11: Color = r1[4] if e1 == 1 else r1[3]
				im.surface_set_color(c00)
				im.surface_add_vertex(r0[e0])
				im.surface_set_color(c01)
				im.surface_add_vertex(r0[e1])
				im.surface_set_color(c11)
				im.surface_add_vertex(r1[e1])
				im.surface_set_color(c00)
				im.surface_add_vertex(r0[e0])
				im.surface_set_color(c11)
				im.surface_add_vertex(r1[e1])
				im.surface_set_color(c10)
				im.surface_add_vertex(r1[e0])
		im.surface_end()
	draw.call(0.02, 0.0)
	var tw: Tween = mi.create_tween()
	tw.tween_method(func(k: float) -> void: draw.call(k, 0.0), 0.02, 1.0, maxf(sweep, 0.01)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(f: float) -> void: draw.call(1.0, f), 0.0, 1.0, fade).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	return mi


## A live weapon trail: while `active`, samples two points of a moving node (`a_local` and
## `b_local` in its space, e.g. a blade's hilt and tip) each frame and draws the swept band
## between the last few samples, fading with age.
class Trail extends MeshInstance3D:
	var target: Node3D
	var a_local: Vector3 = Vector3.ZERO
	var b_local: Vector3 = Vector3(0, 1, 0)
	var color: Color = Color(0.7, 0.95, 1.0)
	var hot: Color = Color(1.5, 1.6, 1.7)
	var max_age: float = 0.16
	var active: bool = false
	var _pts: Array = []   # [a, b, age]
	var _im := ImmediateMesh.new()

	func _init() -> void:
		mesh = _im
		top_level = true
		layers = HeroFx.LAYER
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_receive_shadows = true
		material_override = mat

	func _process(dt: float) -> void:
		global_transform = Transform3D.IDENTITY
		for p: Array in _pts:
			p[2] = float(p[2]) + dt
		while not _pts.is_empty() and float(_pts[0][2]) > max_age:
			_pts.pop_front()
		if active and target != null and is_instance_valid(target) and target.is_inside_tree():
			var xf: Transform3D = target.global_transform
			var a: Vector3 = xf * a_local
			var b: Vector3 = xf * b_local
			# sub-sample fast swings so the band stays a smooth curve
			if not _pts.is_empty():
				var la: Vector3 = _pts[-1][0]
				var lb: Vector3 = _pts[-1][1]
				var gap: float = lb.distance_to(b)
				var n: int = mini(int(gap / 0.12), 6)
				for i: int in n:
					var k: float = float(i + 1) / float(n + 1)
					_pts.append([la.lerp(a, k), lb.lerp(b, k), 0.0])
			_pts.append([a, b, 0.0])
		_im.clear_surfaces()
		if _pts.size() < 2:
			return
		var aabb := AABB(_pts[0][0], Vector3.ZERO)
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for p: Array in _pts:
			var k: float = clampf(1.0 - float(p[2]) / max_age, 0.0, 1.0)
			var c: Color = color.lerp(hot, k * k)
			c.a = k * k
			var ci: Color = c
			ci.a = c.a * 0.15
			_im.surface_set_color(ci)
			_im.surface_add_vertex(p[0])
			_im.surface_set_color(c)
			_im.surface_add_vertex(p[1])
			aabb = aabb.expand(p[0]).expand(p[1])
		_im.surface_end()
		custom_aabb = aabb.grow(0.5)


# ---- afterimages ----------------------------------------------------------------------------

## A translucent snapshot of every visible mesh under `root` (the racer's model plus its
## costume) left in the world, fading over `time`. `stretch` smears it along `dir`.
static func afterimage(world: Node, root: Node3D, color: Color, time: float = 0.3, dir: Vector3 = Vector3.ZERO, energy: float = 1.6) -> void:
	if world == null or root == null or not root.is_inside_tree() or not world.is_inside_tree():
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 0.5)
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	var holder := Node3D.new()
	world.add_child(holder)
	holder.global_transform = Transform3D.IDENTITY
	var n: int = 0
	for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or not m.is_visible_in_tree() or m.mesh == null or m is HeroFx.Trail or m.has_meta("no_ghost"):
			continue
		if m.mesh is ImmediateMesh or m.mesh is QuadMesh:
			continue
		var g := MeshInstance3D.new()
		g.mesh = m.mesh
		g.material_override = mat
		g.layers = LAYER
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(g)
		g.global_transform = m.global_transform
		n += 1
		if n >= 40:
			break
	var tw: Tween = holder.create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	if dir.length() > 0.01:
		tw.tween_property(holder, "position", -dir.normalized() * 0.35, time)
	tw.chain().tween_callback(holder.queue_free)


# ---- the costume rig ------------------------------------------------------------------------

## Follows the Volt model's squash / stretch / lean pivot, so a costume parented here bends
## and bounces with the body. (Reads PlayerVisual's pivot; never writes it.)
class Rig extends Node3D:
	var pivot: Node3D

	func _ready() -> void:
		var pv: Node = get_parent()
		while pv != null and not (pv is PlayerVisual):
			pv = pv.get_parent()
		if pv != null:
			var r: Variant = pv.get("_root")
			if r is Node3D:
				pivot = r

	func _process(_dt: float) -> void:
		if pivot != null and is_instance_valid(pivot):
			transform = pivot.transform


# ---- screen flash ---------------------------------------------------------------------------

## A brief full-screen colour flash for the local player's own big moments.
static func screen_flash(host: Node, color: Color, alpha: float = 0.45, time: float = 0.35) -> void:
	if host == null or not host.is_inside_tree():
		return
	var cl := CanvasLayer.new()
	cl.layer = 5
	var r := ColorRect.new()
	r.color = Color(color.r, color.g, color.b, alpha)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(r)
	host.add_child(cl)
	var tw: Tween = cl.create_tween()
	tw.tween_property(r, "color:a", 0.0, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(cl.queue_free)
