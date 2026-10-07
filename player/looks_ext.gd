class_name LooksExt
extends RefCounted
## Paints, trails and finish celebrations added in the v2.0 update. The original dispatchers
## (CosmeticArt.paint_material, PlayerVisual.trail_layers, PlayerVisual.play_finish) fall
## through to these for any id they don't know, so new items never touch their match blocks.
##
## NaN guard rules for the paint shaders below: no division, no pow, no normalize, and every
## HDR value stays at or under ~3. The test block in tests/run_tests.gd checks the first three.

static var _paint_mats: Dictionary = {}
static var _glyph_textures: Dictionary = {}
static var _glyph_meshes: Dictionary = {}
static var _misc_meshes: Dictionary = {}


# ---- paints ------------------------------------------------------------------------------------

## The shader source of a paint, or "" for an id this file doesn't know.
static func paint_shader_code(id: String) -> String:
	match id:
		"goldleaf":
			return "shader_type spatial;\n" + CosmeticArt._LP + CosmeticArt._NOISE + """
void fragment() {
	vec3 p = lp * 9.0;
	float n = fbm(p);
	float crack = 1.0 - smoothstep(0.0, 0.05, abs(vnoise(p * 2.3) - 0.5));
	vec3 gold = mix(vec3(0.5, 0.33, 0.1), vec3(1.0, 0.82, 0.38), n);
	ALBEDO = gold * (1.0 - 0.45 * crack);
	METALLIC = 1.0;
	ROUGHNESS = clamp(0.2 + 0.4 * crack + 0.15 * (n - 0.5), 0.05, 1.0);
	EMISSION = vec3(1.0, 0.75, 0.3) * crack * 0.12;
}
"""
		"pixel":
			return "shader_type spatial;\n" + CosmeticArt._LP + CosmeticArt._NOISE + """
void fragment() {
	vec3 g = floor(lp * 11.0);
	float h = h13(g);
	vec3 c = mix(vec3(0.95, 0.3, 0.35), vec3(0.25, 0.65, 1.0), step(0.35, h));
	c = mix(c, vec3(1.0, 0.88, 0.3), step(0.62, h));
	c = mix(c, vec3(0.45, 1.0, 0.5), step(0.84, h));
	vec2 f = fract(lp.xy * 11.0);
	float bevel = step(0.12, f.x) * step(0.12, f.y) * step(f.x, 0.88) * step(f.y, 0.88);
	ALBEDO = c * mix(0.55, 1.0, bevel);
	ROUGHNESS = 0.45;
	EMISSION = c * bevel * 0.18;
}
"""
		"marble":
			return "shader_type spatial;\n" + CosmeticArt._LP + CosmeticArt._NOISE + """
void fragment() {
	float w = lp.x * 0.9 + lp.y * 0.5 + fbm(lp * 3.0) * 2.4;
	float vein = 1.0 - smoothstep(0.0, 0.08, abs(sin(w * 7.0)));
	float fine = 1.0 - smoothstep(0.0, 0.06, abs(sin(w * 19.0 + 1.3)));
	vec3 stone = vec3(0.93, 0.93, 0.95);
	vec3 veinc = vec3(0.3, 0.34, 0.45);
	ALBEDO = mix(stone, veinc, max(vein, fine * 0.5));
	ROUGHNESS = 0.16;
	SPECULAR = 0.7;
}
"""
		"toxic":
			return "shader_type spatial;\n" + CosmeticArt._LP + CosmeticArt._NOISE + """
void fragment() {
	vec3 p = lp * 6.0 + vec3(0.0, TIME * 0.3, 0.0);
	float n = fbm(p);
	float glow = smoothstep(0.42, 0.8, n);
	float bub = 0.5 + 0.5 * sin(TIME * 3.0 + n * 14.0);
	vec3 slime = mix(vec3(0.08, 0.22, 0.04), vec3(0.5, 1.0, 0.12), glow);
	ALBEDO = slime;
	ROUGHNESS = 0.22;
	SPECULAR = 0.6;
	EMISSION = vec3(0.45, 1.0, 0.1) * glow * (0.5 + 0.4 * bub);
}
"""
		"aurora":
			return "shader_type spatial;\n" + CosmeticArt._LP + CosmeticArt._NOISE + """
void fragment() {
	float n = fbm(vec3(lp.x * 2.5 + TIME * 0.15, lp.y * 1.6 - TIME * 0.1, lp.z * 2.5));
	float band = 0.5 + 0.5 * sin(lp.y * 15.0 + n * 9.0 + TIME * 0.9);
	vec3 a = mix(vec3(0.1, 1.0, 0.65), vec3(0.65, 0.3, 1.0), band);
	float curtain = smoothstep(0.3, 0.8, n);
	ALBEDO = vec3(0.03, 0.04, 0.09);
	ROUGHNESS = 0.35;
	EMISSION = a * (0.2 + 1.3 * curtain);
}
"""
		"stained":
			return "shader_type spatial;\n" + CosmeticArt._LP + CosmeticArt._NOISE + """
void fragment() {
	vec2 p = lp.xy * 6.0;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float lead = 1.0 - smoothstep(0.0, 0.07, edge);
	float h = h13(vec3(cell, 4.0));
	vec3 jewel = mix(vec3(0.9, 0.12, 0.2), vec3(0.12, 0.35, 0.95), step(0.34, h));
	jewel = mix(jewel, vec3(1.0, 0.8, 0.12), step(0.67, h));
	ALBEDO = mix(jewel, vec3(0.04, 0.04, 0.05), lead);
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	EMISSION = jewel * (1.0 - lead) * 0.55;
}
"""
	return ""


## The paint's material for the body shell, or null (falls back to the factory finish).
static func paint_material(id: String) -> Material:
	var code: String = paint_shader_code(id)
	if code == "":
		return null
	if _paint_mats.has(id):
		return _paint_mats[id]
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	_paint_mats[id] = m
	return m


# ---- trails ------------------------------------------------------------------------------------

## Glyph colour at (x, y) in [-1, 1]^2, y up. Alpha carries the shape.
static func _glyph_color(kind: String, x: float, y: float) -> Color:
	var a: float = 0.0
	var rgb: Color = Color(1.0, 1.0, 1.0)
	match kind:
		"heart":
			var hx: float = x * 1.15
			var hy: float = y * 1.15 - 0.08
			var q: float = hx * hx + hy * hy - 1.0
			var v: float = q * q * q - hx * hx * hy * hy * hy
			a = 1.0 - smoothstep(-0.03, 0.03, v)
		"pixel":
			a = 1.0 if (absf(x) < 0.82 and absf(y) < 0.82) else 0.0
		"note":
			var head_d: float = sqrt((x + 0.35) * (x + 0.35) + (y + 0.55) * (y + 0.55))
			var head: float = 1.0 - smoothstep(0.2, 0.26, head_d)
			var stem: float = 1.0 if (x > 0.14 and x < 0.24 and y > -0.5 and y < 0.62) else 0.0
			var ax: float = 0.24
			var ay: float = 0.62
			var abx: float = 0.36
			var aby: float = -0.37
			var apx: float = x - ax
			var apy: float = y - ay
			var t: float = clampf((apx * abx + apy * aby) / (abx * abx + aby * aby), 0.0, 1.0)
			var flag_d: float = sqrt((apx - t * abx) * (apx - t * abx) + (apy - t * aby) * (apy - t * aby))
			var flag: float = 1.0 - smoothstep(0.1, 0.13, flag_d)
			a = maxf(maxf(head, stem), flag)
		"ink":
			var r: float = sqrt(x * x + y * y)
			var edge: float = 0.72 + 0.1 * sin(atan2(y, x) * 5.0)
			a = 1.0 - smoothstep(edge - 0.04, edge + 0.04, r)
			# a darker rim makes it read as a bubble rather than a blot
			var rim: float = smoothstep(edge - 0.2, edge - 0.08, r)
			rgb = Color(1.0 - 0.4 * rim, 1.0 - 0.4 * rim, 1.0 - 0.4 * rim)
		"leaf":
			var w: float = 0.42 * (1.0 - y * y)
			a = 1.0 - smoothstep(w - 0.03, w + 0.03, absf(x))
			var rib: float = 1.0 - smoothstep(0.0, 0.05, absf(x))
			rgb = Color(1.0 - 0.45 * rib, 1.0 - 0.45 * rib, 1.0 - 0.45 * rib)
		"moon":
			var d1: float = sqrt(x * x + y * y)
			var d2: float = sqrt((x - 0.35) * (x - 0.35) + (y - 0.2) * (y - 0.2))
			var disc: float = 1.0 - smoothstep(0.76, 0.8, d1)
			var bite: float = 1.0 - smoothstep(0.66, 0.7, d2)
			a = disc * (1.0 - bite)
	return Color(rgb.r, rgb.g, rgb.b, a)


static func _glyph_texture(kind: String) -> Texture2D:
	if _glyph_textures.has(kind):
		return _glyph_textures[kind]
	var n: int = 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for py: int in n:
		for px: int in n:
			var x: float = (float(px) + 0.5) / float(n) * 2.0 - 1.0
			var y: float = 1.0 - (float(py) + 0.5) / float(n) * 2.0
			img.set_pixel(px, py, _glyph_color(kind, x, y))
	var t: ImageTexture = ImageTexture.create_from_image(img)
	_glyph_textures[kind] = t
	return t


## A billboarded unit quad carrying a glyph; trails scale it with the emitter's "scale".
static func _glyph_mesh(kind: String, additive: bool) -> Mesh:
	var key: String = "%s|%s" % [kind, additive]
	if _glyph_meshes.has(key):
		return _glyph_meshes[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _glyph_texture(kind)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	_glyph_meshes[key] = q
	return q


## Unlit cube for pixel bursts (particle colour tints it).
static func _cube_mesh() -> Mesh:
	if _misc_meshes.has("cube"):
		return _misc_meshes["cube"]
	var b := BoxMesh.new()
	b.size = Vector3.ONE * 0.16
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	b.material = m
	_misc_meshes["cube"] = b
	return b


## Glossy ellipsoid for balloons (particle colour tints it).
static func _balloon_mesh() -> Mesh:
	if _misc_meshes.has("balloon"):
		return _misc_meshes["balloon"]
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.1
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.3
	m.metallic_specular = 0.6
	s.material = m
	_misc_meshes["balloon"] = s
	return s


## Trail emitter layers (same dictionary format as PlayerVisual.trail_layers).
static func trail_layers(id: String, tint: Color) -> Array[Dictionary]:
	match id:
		"hearts":
			return [
				{"amount": 26, "lifetime": 1.2, "facing": "mesh", "mesh": _glyph_mesh("heart", true),
					"scale": Vector2(0.22, 0.28), "shape": "sphere", "radius": 0.2, "dir": Vector3.UP, "spread": 35.0,
					"speed": Vector2(0.4, 1.0), "gravity": Vector3(0, 0.8, 0), "turbulence": 0.5, "curve": "pop",
					"colors": PackedColorArray([Color(2.4, 0.6, 1.1, 1.0), Color(2.6, 0.9, 1.4, 0.9), Color(2.0, 0.4, 0.9, 0.0)])},
			]
		"pixels":
			return [
				{"amount": 30, "lifetime": 0.7, "facing": "mesh", "mesh": _glyph_mesh("pixel", true),
					"scale": Vector2(0.11, 0.11), "shape": "sphere", "radius": 0.25, "dir": Vector3.UP, "spread": 180.0,
					"speed": Vector2(0.1, 0.6), "gravity": Vector3(0, -1.5, 0), "curve": "shrink",
					"pick": PackedColorArray([Color(2.4, 0.6, 0.6), Color(0.6, 2.0, 2.4), Color(2.4, 2.2, 0.6), Color(0.8, 2.4, 0.8)])},
			]
		"notes":
			return [
				{"amount": 18, "lifetime": 1.4, "facing": "mesh", "mesh": _glyph_mesh("note", false),
					"scale": Vector2(0.2, 0.26), "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 50.0,
					"speed": Vector2(0.3, 0.9), "gravity": Vector3(0, 1.0, 0), "angle": Vector2(-25, 25), "curve": "pop",
					"pick": PackedColorArray([Color(1.6, 1.2, 2.6), Color(0.9, 2.0, 2.4), Color(2.4, 1.6, 0.9)])},
			]
		"ink":
			return [
				{"amount": 24, "lifetime": 1.5, "facing": "mesh", "mesh": _glyph_mesh("ink", false),
					"scale": Vector2(0.3, 0.4), "shape": "sphere", "radius": 0.2, "dir": Vector3.UP, "spread": 180.0,
					"speed": Vector2(0.1, 0.5), "gravity": Vector3(0, 1.6, 0), "turbulence": 0.6, "curve": "flat",
					"color": Color(0.14, 0.06, 0.26, 0.9), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
			]
		"leaves":
			return [
				{"amount": 22, "lifetime": 1.6, "facing": "mesh", "mesh": _glyph_mesh("leaf", false),
					"scale": Vector2(0.28, 0.34), "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 120.0,
					"speed": Vector2(0.2, 0.8), "gravity": Vector3(0, -1.8, 0), "turbulence": 0.9,
					"spin": Vector2(-200, 200), "angle": Vector2(0, 360), "curve": "shrink",
					"pick": PackedColorArray([Color(0.95, 0.55, 0.15), Color(0.45, 0.8, 0.2), Color(0.85, 0.3, 0.12)])},
			]
		"stars":
			return [
				{"amount": 14, "lifetime": 1.0, "tex": Fx.Tex.STAR, "size": 0.26, "shape": "sphere", "radius": 0.25,
					"speed": Vector2(0.0, 0.4), "spread": 180.0, "curve": "pop", "angle": Vector2(0, 360),
					"spin": Vector2(-200, 200), "color": Color(2.6, 2.2, 0.8)},
				{"amount": 10, "lifetime": 1.2, "facing": "mesh", "mesh": _glyph_mesh("moon", true),
					"scale": Vector2(0.24, 0.24), "shape": "sphere", "radius": 0.35, "speed": Vector2(0.0, 0.3),
					"spread": 180.0, "gravity": Vector3(0, 0.4, 0), "curve": "shrink",
					"color": Color(1.6, 1.8, 2.6)},
			]
	return []


# ---- finish celebrations -------------------------------------------------------------------------

## Finish celebration `id` at `at` for visual `v` (the "fin_<id>" sound is played by the caller).
## Every emitter must be a self-freeing Fx.spawn scaled by the Particles slider.
static func play_finish(v: PlayerVisual, id: String, at: Vector3) -> void:
	match id:
		"balloons":
			_fin_balloons(v, at)
		"disco":
			_fin_disco(v, at)
		"meteor":
			_fin_meteor(v, at)
		"pixelburst":
			_fin_pixelburst(v, at)
		_:
			pass


## Balloons drift up out of the crowd and fade as they shrink.
static func _fin_balloons(v: PlayerVisual, at: Vector3) -> void:
	var pick := PackedColorArray([Color(2.4, 0.5, 0.6), Color(0.5, 1.6, 2.4), Color(2.4, 2.1, 0.5),
		Color(0.6, 2.2, 0.8), Color(1.8, 0.7, 2.4)])
	Fx.spawn(v, Fx.emitter({"amount": 18, "lifetime": 2.6, "one_shot": true, "explosiveness": 0.35,
		"shape": "sphere", "radius": 1.1, "facing": "mesh", "mesh": _balloon_mesh(), "dir": Vector3.UP,
		"spread": 25.0, "speed": Vector2(1.0, 2.0), "gravity": Vector3(0, 1.4, 0), "damping": Vector2(0.2, 0.4),
		"scale": Vector2(0.8, 1.2), "curve": "shrink", "turbulence": 0.7, "pick": pick, "layers": 2}),
		at + Vector3(0, 0.6, 0))
	Fx.spawn(v, Fx.shockwave(2.4, {"lifetime": 0.5, "color": Color(1.6, 1.2, 2.2), "layers": 2}),
		at + Vector3(0, 0.08, 0))


## A mirror-ball shower of glitter with coloured light sweeps across the floor.
static func _fin_disco(v: PlayerVisual, at: Vector3) -> void:
	var glitter := PackedColorArray([Color(2.6, 2.6, 2.8), Color(2.2, 0.6, 2.6), Color(0.6, 2.2, 2.6),
		Color(2.6, 2.2, 0.6)])
	Fx.spawn(v, Fx.emitter({"amount": 70, "lifetime": 2.4, "one_shot": true, "shape": "ring",
		"ring_axis": Vector3.UP, "ring_radius": 2.8, "ring_height": 0.2, "tex": Fx.Tex.STAR, "additive": true,
		"size": 0.2, "dir": Vector3.DOWN, "spread": 20.0, "speed": Vector2(0.3, 0.9), "scale": Vector2(0.6, 1.0),
		"angle": Vector2(0, 360), "spin": Vector2(-200, 200), "curve": "flat", "pick": glitter, "layers": 2}),
		at + Vector3(0, 4.5, 0))
	Fx.spawn(v, Fx.shockwave(3.0, {"lifetime": 0.6, "color": Color(1.4, 0.6, 2.0), "layers": 2}),
		at + Vector3(0, 0.08, 0))
	var cols: Array[Color] = [Color(2.0, 0.5, 1.2), Color(0.4, 1.6, 2.0), Color(2.0, 1.6, 0.4), Color(0.5, 2.0, 0.8)]
	var tw: Tween = v.create_tween()
	for k: int in 6:
		var col: Color = cols[k % cols.size()]
		var spot: Vector3 = at + Vector3(cos(float(k) * 1.05) * 4.0, 2.5, sin(float(k) * 1.05) * 4.0)
		tw.tween_callback(func() -> void:
			if v.is_inside_tree():
				Fx.flash(v, spot, col, 3.0, 9.0, 0.45))
		tw.tween_interval(0.35)


## A fireball falls from the sky onto the spot; the impact throws debris and a shockwave.
static func _fin_meteor(v: PlayerVisual, at: Vector3) -> void:
	var hit: Vector3 = at + Vector3(0, 0.6, 0)
	var from: Vector3 = at + Vector3(randf_range(-4.0, 4.0), 14.0, randf_range(-4.0, 4.0))
	var head: MeshInstance3D = Fx.sprite(Color(3.0, 1.6, 0.6), 1.2, Fx.Tex.DOT, true)
	head.top_level = true
	v.add_child(head)
	head.global_position = from
	var tw: Tween = head.create_tween()
	tw.tween_property(head, "global_position", hit, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _fin_meteor_impact(v, at, hit))
	tw.tween_callback(head.queue_free)
	# a fiery tail: one small burst left behind the head every few hundredths of a second
	var tail: Tween = v.create_tween()
	for k: int in 9:
		tail.tween_callback(func() -> void:
			if is_instance_valid(head) and head.is_inside_tree():
				Fx.spawn(v, Fx.burst({"amount": 10, "lifetime": 0.5, "spread": 60.0, "speed": Vector2(0.2, 0.8),
					"size": 0.3, "curve": "shrink", "color": Color(2.4, 1.0, 0.3), "layers": 2}), head.global_position))
		tail.tween_interval(0.055)


static func _fin_meteor_impact(v: PlayerVisual, at: Vector3, hit: Vector3) -> void:
	if not v.is_inside_tree():
		return
	Fx.spawn(v, Fx.shockwave(3.4, {"lifetime": 0.5, "color": Color(2.4, 1.1, 0.4), "layers": 2}), at + Vector3(0, 0.08, 0))
	Fx.spawn(v, Fx.debris({"amount": 18, "chunk": 0.2, "color": Color(1.2, 0.7, 0.4)}), hit)
	Fx.spawn(v, Fx.smoke({"amount": 14, "lifetime": 1.1, "shape": "ring", "ring_radius": 0.8, "size": 0.9,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(1.0, 2.5), "color": Color(0.35, 0.3, 0.3, 0.6),
		"layers": 2}), at)
	Fx.spawn(v, Fx.sparks({"amount": 36, "lifetime": 0.6, "dir": Vector3.UP, "spread": 80.0,
		"speed": Vector2(5.0, 10.0), "color": Color(2.6, 1.4, 0.5), "layers": 2}), hit)
	Fx.flash(v, hit + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.3), 7.0, 14.0, 0.6)


## Square pixels burst out in a sphere, then a flat ring of them skims the ground.
static func _fin_pixelburst(v: PlayerVisual, at: Vector3) -> void:
	var pick := PackedColorArray([Color(2.4, 0.5, 0.5), Color(0.5, 2.0, 2.4), Color(2.4, 2.2, 0.5),
		Color(0.6, 2.4, 0.7), Color(2.0, 0.6, 2.4), Color(2.6, 2.6, 2.6)])
	var hub: Vector3 = at + Vector3(0, 1.4, 0)
	Fx.spawn(v, Fx.burst({"amount": 80, "lifetime": 1.3, "facing": "mesh", "mesh": _cube_mesh(), "spread": 180.0,
		"speed": Vector2(4.0, 8.0), "damping": Vector2(1.5, 2.5), "gravity": Vector3(0, -8.0, 0),
		"scale": Vector2(0.6, 1.0), "curve": "flat", "spin": Vector2(-500, 500), "angle": Vector2(0, 360),
		"pick": pick, "layers": 2}), hub)
	Fx.spawn(v, Fx.burst({"amount": 40, "lifetime": 1.0, "facing": "mesh", "mesh": _cube_mesh(), "dir": Vector3.UP,
		"flatness": 1.0, "spread": 180.0, "speed": Vector2(5.0, 7.0), "damping": Vector2(2.0, 3.0),
		"gravity": Vector3(0, -6.0, 0), "scale": Vector2(0.5, 0.8), "curve": "shrink", "angle": Vector2(0, 360),
		"pick": pick, "layers": 2}), at + Vector3(0, 0.3, 0))
	Fx.flash(v, hub, Color(1.0, 0.95, 0.6), 3.5, 9.0, 0.4)
