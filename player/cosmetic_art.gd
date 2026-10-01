class_name CosmeticArt
extends RefCounted
## Shared art for the earnable cosmetics worn by PlayerVisual: cached primitive meshes and
## materials, two procedural meshes (a tapered arc tube for horns / tails / plumes / bands and
## a curled hat brim), the paint-job materials and the hat models.
##
## Everything is built from primitives in code and cached per process (static), so every racer
## shares the same Mesh and Material resources; accent-coloured pieces use the wearer's own
## accent materials (PlayerVisual.accent_material) so they follow the racer colour.
##
## Hats are modelled for Volt's head: y = 0 is the crown of the head, front is -Z, and the
## head is ~0.39 m in radius (0.25 m at 0.1 m below the crown). PlayerVisual places and scales
## the anchor per character. A hat may tag nodes with metadata the visual animates:
##   "sway"  [pitch_gain, roll_gain, flutter, wag, lift]  rides the antenna spring
##   "spin"  [rad_per_s, rad_per_s_per_mps]               spins about its local Y
##   "bob"   [amplitude, rad_per_s]                       floats up and down
## Shaders: no NaN paths (clamped pow bases, no normalize of maybe-zero vectors, ordered
## smoothstep edges) and emission bounded to ~3 so the glow pass never blows out.

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}

# ---- primitive meshes (unit sized: the MeshInstance scale sizes them) -------------------------

## A sphere of diameter 1. detail 0 (small parts) .. 2 (body shells).
static func sphere(detail: int = 1) -> SphereMesh:
	var key: String = "sph%d" % detail
	var m: SphereMesh = _meshes.get(key)
	if m == null:
		m = SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = [12, 20, 28][clampi(detail, 0, 2)]
		m.rings = [6, 10, 14][clampi(detail, 0, 2)]
		_meshes[key] = m
	return m


## A box of size 1.
static func box() -> BoxMesh:
	var m: BoxMesh = _meshes.get("box")
	if m == null:
		m = BoxMesh.new()
		_meshes["box"] = m
	return m


## A cylinder / cone / frustum of height 1 (radii as given; 0.5 = diameter 1).
static func cyl(top: float, bottom: float, segs: int = 16, caps: bool = true) -> CylinderMesh:
	var key: String = "cyl|%.3f|%.3f|%d|%s" % [top, bottom, segs, caps]
	var m: CylinderMesh = _meshes.get(key)
	if m == null:
		m = CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = 1.0
		m.radial_segments = segs
		m.rings = 1
		m.cap_top = caps
		m.cap_bottom = caps
		_meshes[key] = m
	return m


## A torus in the XZ plane with these exact radii (scale 1 = real size).
static func torus(inner: float, outer: float, rings: int = 24) -> TorusMesh:
	var key: String = "tor|%.3f|%.3f|%d" % [inner, outer, rings]
	var m: TorusMesh = _meshes.get(key)
	if m == null:
		m = TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = rings
		m.ring_segments = 8
		_meshes[key] = m
	return m


## A tube along a circular arc of radius 1: it starts at the origin heading +Y and bends
## toward +X through `sweep` radians, its radius tapering r0 -> r1 (0 closes to a point).
## Scale the instance uniformly to size it (the tube radii scale with it).
static func arc(sweep: float, r0: float, r1: float, sides: int = 8, segs: int = 10) -> ArrayMesh:
	var key: String = "arc|%.3f|%.3f|%.3f|%d|%d" % [sweep, r0, r1, sides, segs]
	var cached: ArrayMesh = _meshes.get(key)
	if cached != null:
		return cached
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i: int in segs + 1:
		var t: float = float(i) / float(segs)
		var th: float = sweep * t
		var c := Vector3(1.0 - cos(th), sin(th), 0.0)
		var nrm := Vector3(cos(th), -sin(th), 0.0)   # in-plane, perpendicular to the path
		var r: float = lerpf(r0, r1, t)
		for j: int in sides:
			var ph: float = TAU * float(j) / float(sides)
			var d: Vector3 = nrm * cos(ph) + Vector3.BACK * sin(ph)
			verts.append(c + d * r)
			norms.append(d)
	for i: int in segs:
		for j: int in sides:
			var a: int = i * sides + j
			var b: int = i * sides + (j + 1) % sides
			_tri(idx, verts, norms, a, a + sides, b)
			_tri(idx, verts, norms, b, a + sides, b + sides)
	# end caps (a closed tip needs none)
	for e: int in 2:
		var t2: float = float(e)
		var r2: float = lerpf(r0, r1, t2)
		if r2 < 0.001:
			continue
		var th2: float = sweep * t2
		var tangent := Vector3(sin(th2), cos(th2), 0.0) * (1.0 if e == 1 else -1.0)
		var centre := Vector3(1.0 - cos(th2), sin(th2), 0.0)
		var base: int = verts.size()
		verts.append(centre)
		norms.append(tangent)
		for j: int in sides:
			verts.append(verts[e * segs * sides + j])
			norms.append(tangent)
		for j: int in sides:
			_tri(idx, verts, norms, base, base + 1 + j, base + 1 + (j + 1) % sides)
	var m: ArrayMesh = _array_mesh(verts, norms, idx)
	_meshes[key] = m
	return m


## A hat brim (two-sided, with a rim): an annulus whose outline and curl come from `kind`.
static func brim(kind: String) -> ArrayMesh:
	var key: String = "brim|" + kind
	var cached: ArrayMesh = _meshes.get(key)
	if cached != null:
		return cached
	var around: int = 40
	var radial: int = 5
	var thick: float = 0.018
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var e: float = 0.002
	for side: int in 2:   # 0 top, 1 underside
		var base: int = verts.size()
		for i: int in around:
			var th: float = TAU * float(i) / float(around)
			for k: int in radial + 1:
				var t: float = float(k) / float(radial)
				var p: Vector3 = _brim_point(kind, th, t)
				var n: Vector3 = (_brim_point(kind, th, minf(t + e, 1.0)) - _brim_point(kind, th, maxf(t - e, 0.0))).cross(
					_brim_point(kind, th + e, t) - _brim_point(kind, th - e, t))
				if n.length_squared() < 1e-12:
					n = Vector3.UP
				n = n.normalized()
				if n.y < 0.0:
					n = -n
				if side == 1:
					p.y -= thick
					n = -n
				verts.append(p)
				norms.append(n)
				uvs.append(Vector2(float(i) / float(around), t))
		for i: int in around:
			var i2: int = (i + 1) % around
			for k: int in radial:
				var a: int = base + i * (radial + 1) + k
				var b: int = base + i2 * (radial + 1) + k
				_tri(idx, verts, norms, a, b, a + 1)
				_tri(idx, verts, norms, b, b + 1, a + 1)
	# the outer rim strip
	var rim: int = verts.size()
	for i: int in around:
		var th: float = TAU * float(i) / float(around)
		var p: Vector3 = _brim_point(kind, th, 1.0)
		var out := Vector3(cos(th), 0.0, sin(th))
		verts.append(p)
		norms.append(out)
		uvs.append(Vector2(float(i) / float(around), 1.0))
		verts.append(p - Vector3(0.0, thick, 0.0))
		norms.append(out)
		uvs.append(Vector2(float(i) / float(around), 1.0))
	for i: int in around:
		var a: int = rim + i * 2
		var b: int = rim + ((i + 1) % around) * 2
		_tri(idx, verts, norms, a, b, a + 1)
		_tri(idx, verts, norms, b, b + 1, a + 1)
	var m: ArrayMesh = _array_mesh(verts, norms, idx, uvs)
	_meshes[key] = m
	return m


## A point on a brim: angle th (x = cos, z = sin; the front -Z is th = -PI/2), t 0 inner .. 1 edge.
static func _brim_point(kind: String, th: float, t: float) -> Vector3:
	var c: float = cos(th)
	var s: float = sin(th)
	var r_in: float = 0.2
	var r_out: float = 0.4
	var y: float = 0.0
	match kind:
		"cowboy":
			# long front and back, the sides curled up hard, the front dipping a touch
			r_in = 0.16
			r_out = 0.4 + 0.05 * s * s
			y = 0.17 * t * t * c * c - 0.035 * t * s * s
		"tricorn":
			# turned up all round into three walls; the corners point front, back-left, back-right
			var k: float = pow(maxf(cos(3.0 * (th + PI * 0.5)), 0.0), 3.0)
			r_in = 0.18
			r_out = 0.33 + 0.12 * k
			y = (0.2 + 0.03 * k) * pow(t, 1.3)
		"sunhat":
			r_in = 0.2
			r_out = 0.5
			y = -0.08 * t * t + 0.025 * sin(5.0 * th) * t * t
		"witch":
			r_in = 0.19
			r_out = 0.44
			y = -0.03 * t * t + 0.02 * sin(3.0 * th + 1.0) * t * t
		"pith":
			r_in = 0.24
			r_out = 0.42 + 0.03 * s * s
			y = -0.1 * t
		"tophat":
			r_in = 0.17
			r_out = 0.3
			y = 0.045 * t * t * c * c
	var r: float = lerpf(r_in, r_out, t)
	return Vector3(c * r, y, s * r)


## Appends a triangle wound so it faces along the vertex normals (Godot: clockwise = front).
static func _tri(idx: PackedInt32Array, verts: PackedVector3Array, norms: PackedVector3Array, a: int, b: int, c: int) -> void:
	var n: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(norms[a] + norms[b] + norms[c]) > 0.0:
		idx.append(a)
		idx.append(c)
		idx.append(b)
	else:
		idx.append(a)
		idx.append(b)
		idx.append(c)


static func _array_mesh(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array, uvs: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ---- materials -------------------------------------------------------------------------------

const UNSHADED: int = 1
const ADDITIVE: int = 2
const DOUBLE: int = 4

## A cached StandardMaterial3D (never mutate one: every racer shares it).
static func std(c: Color, rough: float = 0.55, metal: float = 0.0, emit: float = 0.0, flags: int = 0) -> StandardMaterial3D:
	var key: String = "std|%s|%.2f|%.2f|%.2f|%d" % [c.to_html(true), rough, metal, emit, flags]
	var m: StandardMaterial3D = _mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = Color(c.r, c.g, c.b)
			m.emission_energy_multiplier = emit
		if (flags & UNSHADED) != 0:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if (flags & ADDITIVE) != 0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.disable_receive_shadows = true
		if (flags & DOUBLE) != 0:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return m


## Scale-aware object-space position (pattern size stays the same on big and small parts).
const _LP: String = """
varying vec3 lp;
void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lp = VERTEX * s;
}
"""

const _NOISE: String = """
float h13(vec3 p) {
	vec3 q = fract(p * 0.1031);
	q += dot(q, q.zyx + 31.32);
	return fract((q.x + q.y) * q.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h13(i), h13(i + vec3(1.0, 0.0, 0.0)), u.x), mix(h13(i + vec3(0.0, 1.0, 0.0)), h13(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(h13(i + vec3(0.0, 0.0, 1.0)), h13(i + vec3(1.0, 0.0, 1.0)), u.x), mix(h13(i + vec3(0.0, 1.0, 1.0)), h13(i + vec3(1.0, 1.0, 1.0)), u.x), u.y);
	return mix(a, b, u.z);
}
float fbm(vec3 p) {
	return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.03 + 7.1) + 0.15 * vnoise(p * 4.1 + 3.7);
}
"""

## Shader bodies by name (header + fragment). All cheap: a few noise taps at most.
static func _shader_code(name: String) -> String:
	match name:
		"camo":
			return "shader_type spatial;\n" + _LP + _NOISE + """
void fragment() {
	vec3 p = lp * 4.5;
	float n = fbm(p);
	float m = vnoise(p * 1.7 + 11.0);
	vec3 c = vec3(0.36, 0.42, 0.24);
	c = mix(c, vec3(0.19, 0.26, 0.14), step(0.52, n));
	c = mix(c, vec3(0.46, 0.36, 0.23), step(0.62, m));
	c = mix(c, vec3(0.08, 0.09, 0.07), step(0.66, n));
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""
		"lava":
			return "shader_type spatial;\n" + _LP + _NOISE + """
void fragment() {
	vec3 p = lp * 5.0 + vec3(0.0, -TIME * 0.06, 0.0);
	float n = fbm(p);
	float crack = 1.0 - smoothstep(0.0, 0.045, abs(n - 0.5));
	float n2 = vnoise(lp * 11.0 + vec3(TIME * 0.2));
	crack = max(crack, (1.0 - smoothstep(0.0, 0.03, abs(n2 - 0.5))) * 0.6);
	float pulse = 0.7 + 0.3 * sin(TIME * 2.2 + n * 12.0);
	vec3 crust = mix(vec3(0.07, 0.05, 0.045), vec3(0.17, 0.1, 0.08), vnoise(lp * 14.0));
	vec3 hot = mix(vec3(1.0, 0.25, 0.04), vec3(1.0, 0.75, 0.2), crack);
	ALBEDO = mix(crust, hot, crack);
	ROUGHNESS = mix(0.92, 0.5, crack);
	EMISSION = hot * crack * pulse * 2.4;
}
"""
		"galaxy":
			return "shader_type spatial;\n" + _LP + _NOISE + """
void fragment() {
	vec3 p = lp * 3.2 + vec3(TIME * 0.02, 0.0, TIME * 0.015);
	float n = fbm(p);
	float n2 = fbm(p * 1.7 + 5.0);
	vec3 neb = mix(vec3(0.35, 0.1, 0.6), vec3(0.1, 0.35, 0.8), n2);
	neb = mix(neb, vec3(0.9, 0.3, 0.6), smoothstep(0.55, 0.8, n2 * n * 1.6));
	float cloud = smoothstep(0.42, 0.75, n);
	vec3 q = lp * 22.0;
	vec3 cell = floor(q);
	float h = h13(cell);
	vec3 off = vec3(h13(cell + 3.1), h13(cell + 7.7), h13(cell + 1.9)) * 0.6 + 0.2;
	float d = length(fract(q) - off);
	float star = (1.0 - smoothstep(0.0, 0.14, d)) * step(0.88, h);
	float tw = 0.55 + 0.45 * sin(TIME * (2.0 + h * 4.0) + h * 40.0);
	ALBEDO = vec3(0.025, 0.02, 0.07) + neb * cloud * 0.3;
	ROUGHNESS = 0.25;
	METALLIC = 0.1;
	EMISSION = min(neb * cloud * 0.7 + vec3(2.5, 2.4, 2.7) * star * tw, vec3(3.0));
}
"""
		"candy":
			return "shader_type spatial;\n" + _LP + """
void fragment() {
	float x = (lp.x + lp.y * 1.3 + lp.z * 0.4) * 5.0;
	float t = abs(fract(x) - 0.5) * 2.0;
	float band = smoothstep(0.47, 0.53, t);
	ALBEDO = mix(vec3(1.0, 0.96, 0.96), vec3(1.0, 0.33, 0.55), band);
	ROUGHNESS = 0.16;
	SPECULAR = 0.75;
}
"""
		"neon":
			return "shader_type spatial;\n" + _LP + """
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(f, 2.5);
	float k = clamp(lp.y * 1.4 + 0.5, 0.0, 1.0);
	vec3 col = mix(vec3(0.1, 0.95, 1.0), vec3(1.0, 0.15, 0.85), k);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	ALBEDO = vec3(0.03, 0.03, 0.05) + col * 0.05;
	ROUGHNESS = 0.3;
	EMISSION = col * (0.12 + 2.5 * rim * pulse);
}
"""
		"ghost":
			return "shader_type spatial;\nrender_mode blend_mix, cull_back, depth_draw_opaque;\n" + _LP + """
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(f, 2.0);
	float wob = 0.06 * sin(TIME * 2.4 + lp.y * 9.0);
	ALBEDO = vec3(0.82, 0.95, 1.0);
	ALPHA = clamp(0.22 + 0.62 * rim + wob, 0.08, 0.9);
	ROUGHNESS = 0.4;
	EMISSION = vec3(0.45, 0.85, 0.75) * (0.25 + 1.2 * rim);
}
"""
		"glass":
			return """shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(f, 3.0);
	ALBEDO = vec3(0.78, 0.9, 1.0);
	ALPHA = clamp(0.1 + 0.6 * rim, 0.0, 0.85);
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	EMISSION = vec3(0.6, 0.85, 1.0) * rim * 0.25;
}
"""
		"circuit":
			# Cyber Volt's glowing traces: a thin alpha-scissor shell over the body
			return "shader_type spatial;\n" + _LP + _NOISE + """
void fragment() {
	vec2 v = lp.xz;
	if (dot(v, v) < 0.00000001) {
		v = vec2(1.0, 0.0);
	}
	float a = atan(v.y, v.x) * 2.5464791;
	float y = lp.y * 9.0;
	vec2 cell = floor(vec2(a, y));
	float hr = h13(vec3(cell, 1.0));
	float hv = h13(vec3(cell, 2.0));
	vec2 f = fract(vec2(a, y)) - 0.5;
	float ring = step(abs(f.y), 0.07) * step(0.45, hr);
	float vert = step(abs(f.x), 0.07) * step(0.6, hv);
	float pad = step(length(f), 0.16) * step(0.75, hr);
	vec3 col = mix(vec3(0.1, 1.0, 0.85), vec3(1.0, 0.2, 0.8), step(0.5, h13(vec3(cell, 3.0))));
	float pulse = 0.6 + 0.4 * sin(TIME * 3.0 - lp.y * 12.0);
	ALBEDO = col * 0.3;
	EMISSION = col * (1.2 + 1.2 * pulse);
	ALPHA = max(max(ring, vert), pad);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
		"hud":
			# Cyber Volt's visor: dark glass with scanlines and a sweeping teal readout
			return "shader_type spatial;\n" + _LP + """
void fragment() {
	float scan = 0.5 + 0.5 * sin(lp.y * 220.0);
	float sweep = 1.0 - smoothstep(0.0, 0.035, abs(lp.x - 0.24 * sin(TIME * 1.3)));
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = vec3(0.02, 0.04, 0.06);
	ROUGHNESS = 0.08;
	METALLIC = 0.4;
	EMISSION = vec3(0.15, 1.0, 0.85) * (0.12 * scan + 1.6 * sweep + 0.6 * pow(f, 3.0));
}
"""
		"pharaoh":
			return "shader_type spatial;\n" + _LP + """
void fragment() {
	float t = abs(fract(lp.y * 9.0) - 0.5) * 2.0;
	float band = smoothstep(0.45, 0.55, t);
	ALBEDO = mix(vec3(1.0, 0.78, 0.25), vec3(0.12, 0.22, 0.62), band);
	METALLIC = mix(0.7, 0.0, band);
	ROUGHNESS = mix(0.3, 0.6, band);
}
"""
		"party":
			return """shader_type spatial;
void fragment() {
	float t = abs(fract(UV.x * 4.0 + UV.y * 2.0) - 0.5) * 2.0;
	float band = smoothstep(0.45, 0.55, t);
	ALBEDO = mix(vec3(1.0, 0.3, 0.6), vec3(1.0, 0.85, 0.2), band);
	ROUGHNESS = 0.45;
}
"""
		"ember":
			return """shader_type spatial;
varying vec3 mp;
void vertex() {
	mp = VERTEX;
}
void fragment() {
	float t = clamp(length(mp) / 1.3, 0.0, 1.0);
	float glow = smoothstep(0.45, 1.0, t);
	float flick = 0.8 + 0.2 * sin(TIME * 6.0 + mp.y * 10.0);
	ALBEDO = mix(vec3(0.16, 0.04, 0.03), vec3(1.0, 0.45, 0.1), glow);
	ROUGHNESS = 0.5;
	EMISSION = vec3(1.0, 0.4, 0.08) * glow * glow * 2.6 * flick;
}
"""
		"tricorn":
			# black felt brim with a gold edge
			return """shader_type spatial;
void fragment() {
	float edge = smoothstep(0.84, 0.9, UV.y);
	ALBEDO = mix(vec3(0.07, 0.06, 0.06), vec3(1.0, 0.78, 0.3), edge);
	METALLIC = edge * 0.8;
	ROUGHNESS = mix(0.8, 0.3, edge);
}
"""
		"poncho":
			return "shader_type spatial;\n" + _LP + """
void fragment() {
	float y = lp.y * 16.0;
	float t = abs(fract(y) - 0.5) * 2.0;
	float stripe = smoothstep(0.72, 0.78, t);
	float band = step(0.5, fract(y * 0.5));
	vec3 col = mix(vec3(0.95, 0.85, 0.58), vec3(0.12, 0.5, 0.48), band);
	ALBEDO = mix(vec3(0.72, 0.3, 0.16), col, stripe);
	ROUGHNESS = 0.92;
}
"""
	return "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(1.0, 0.0, 1.0); }\n"


## A cached ShaderMaterial (one per name for the whole process).
static func shader(name: String) -> ShaderMaterial:
	var key: String = "shader|" + name
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		var sh := Shader.new()
		sh.code = _shader_code(name)
		m = ShaderMaterial.new()
		m.shader = sh
		_mats[key] = m
	return m


const PAINT_SHADERS: Array[String] = ["camo", "lava", "galaxy", "candy", "neon", "ghost"]

## The paint job's material for the body shell parts, or null for "white" (each character's
## own factory finish).
static func paint_material(id: String) -> Material:
	match id:
		"white":
			return null
		"chrome":
			var key: String = "paint|chrome"
			var m: StandardMaterial3D = _mats.get(key)
			if m == null:
				m = StandardMaterial3D.new()
				m.albedo_color = Color(0.9, 0.92, 0.95)
				m.metallic = 1.0
				m.roughness = 0.07
				m.metallic_specular = 0.8
				_mats[key] = m
			return m
	if id in PAINT_SHADERS:
		return shader(id)
	return null


# ---- part helpers ----------------------------------------------------------------------------

static func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.layers = 2
	if maxf(maxf(absf(scl.x), absf(scl.y)), absf(scl.z)) < 0.07:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A part placed by a full basis (scale folded in).
static func part_b(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, b: Basis) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(b, pos)
	mi.layers = 2
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


# ---- hats ------------------------------------------------------------------------------------

## Hats that leave the crown of the head open (an antenna or a spike there stays visible).
const OPEN_HATS: Array[String] = ["none", "horns", "headphones", "crown", "halo", "snorkel"]

static func covers_crown(id: String) -> bool:
	return not (id in OPEN_HATS)


## Builds hat `id` (a Cosmetics.HATS id other than "none") for visual `v`.
static func hat(id: String, v: PlayerVisual) -> Node3D:
	var h := Node3D.new()
	match id:
		"sunhat":
			var straw := std(Color(0.93, 0.8, 0.48), 0.85)
			part(h, brim("sunhat"), straw, Vector3(0, -0.06, 0), Vector3.ONE, Vector3(0.1, 0, 0))
			part(h, sphere(1), straw, Vector3(0, 0.02, 0), Vector3(0.38, 0.24, 0.38))
			part(h, torus(0.15, 0.2), std(Color(0.3, 0.62, 0.35), 0.6), Vector3(0, -0.02, 0), Vector3(1, 0.9, 1))
			part(h, sphere(0), std(Color(0.97, 0.45, 0.6), 0.6), Vector3(0.17, 0.0, -0.09), Vector3.ONE * 0.09)
			part(h, sphere(0), std(Color(1.0, 0.85, 0.25), 0.5), Vector3(0.19, 0.01, -0.12), Vector3.ONE * 0.045)
		"hardhat":
			var yellow := std(Color(1.0, 0.78, 0.1), 0.35)
			part(h, sphere(1), yellow, Vector3(0, -0.04, 0), Vector3(0.56, 0.4, 0.6))
			part(h, sphere(1), yellow, Vector3(0, -0.085, -0.04), Vector3(0.68, 0.035, 0.76))
			part(h, sphere(1), std(Color(0.95, 0.7, 0.05), 0.4), Vector3(0, -0.04, 0), Vector3(0.07, 0.425, 0.64))
			part(h, cyl(0.5, 0.5, 12), std(Color(0.2, 0.2, 0.22), 0.5, 0.4), Vector3(0, 0.04, -0.285), Vector3(0.1, 0.05, 0.1), Vector3(PI * 0.5, 0, 0))
			part(h, sphere(0), std(Color(1.0, 0.95, 0.7), 0.3, 0.0, 2.0), Vector3(0, 0.04, -0.31), Vector3(0.08, 0.08, 0.02))
		"propeller":
			part(h, sphere(1), v.accent_material("base"), Vector3(0, -0.03, 0), Vector3(0.5, 0.34, 0.5))
			part(h, sphere(1), std(Color(0.15, 0.3, 0.75), 0.5), Vector3(0, -0.07, -0.2), Vector3(0.4, 0.03, 0.3))
			part(h, cyl(0.5, 0.5, 8), std(Color(0.85, 0.85, 0.88), 0.4, 0.6), Vector3(0, 0.17, 0), Vector3(0.025, 0.08, 0.025))
			var spin: Node3D = pivot(h, Vector3(0, 0.21, 0))
			spin.set_meta("spin", [3.0, 2.2])
			part(spin, sphere(0), std(Color(1.0, 0.85, 0.2), 0.4), Vector3.ZERO, Vector3.ONE * 0.05)
			part(spin, box(), std(Color(0.95, 0.25, 0.25), 0.5), Vector3(0.16, 0, 0), Vector3(0.28, 0.012, 0.07), Vector3(0.25, 0, 0))
			part(spin, box(), std(Color(0.25, 0.6, 1.0), 0.5), Vector3(-0.16, 0, 0), Vector3(0.28, 0.012, 0.07), Vector3(-0.25, 0, 0))
		"tophat":
			var felt := std(Color(0.08, 0.08, 0.1), 0.45)
			var brass := std(Color(0.82, 0.6, 0.25), 0.3, 0.85)
			part(h, brim("tophat"), felt, Vector3(0, -0.05, 0))
			part(h, cyl(0.5, 0.5, 20), felt, Vector3(0, 0.12, 0), Vector3(0.36, 0.34, 0.36))
			part(h, cyl(0.5, 0.5, 20), brass, Vector3(0, -0.005, 0), Vector3(0.375, 0.06, 0.375))
			# a clockwork gear on the side, turning
			var gear: Node3D = pivot(h, Vector3(0.19, 0.12, 0), Vector3(0, 0, -PI * 0.5))
			gear.set_meta("spin", [1.6, 0.0])
			part(gear, cyl(0.5, 0.5, 12), brass, Vector3.ZERO, Vector3(0.13, 0.025, 0.13))
			part(gear, box(), brass, Vector3.ZERO, Vector3(0.17, 0.02, 0.028))
			part(gear, box(), brass, Vector3.ZERO, Vector3(0.028, 0.02, 0.17))
			part(gear, sphere(0), std(Color(0.3, 0.22, 0.12), 0.4, 0.6), Vector3(0, 0.012, 0), Vector3(0.04, 0.02, 0.04))
		"snorkel":
			part(h, torus(0.25, 0.3), std(Color(0.1, 0.1, 0.12), 0.7), Vector3(0, -0.12, 0), Vector3(1, 0.8, 1), Vector3(0.25, 0, 0))
			part(h, sphere(1), std(Color(0.1, 0.1, 0.12), 0.6), Vector3(0, -0.13, -0.27), Vector3(0.36, 0.17, 0.12), Vector3(-0.35, 0, 0))
			part(h, sphere(1), shader("glass"), Vector3(0, -0.13, -0.31), Vector3(0.3, 0.13, 0.08), Vector3(-0.35, 0, 0))
			part(h, cyl(0.5, 0.5, 10), std(Color(1.0, 0.72, 0.1), 0.45), Vector3(-0.3, -0.04, -0.04), Vector3(0.05, 0.42, 0.05))
			part(h, cyl(0.5, 0.5, 10), std(Color(1.0, 0.35, 0.1), 0.45), Vector3(-0.3, 0.19, -0.04), Vector3(0.07, 0.07, 0.07))
		"bubble":
			part(h, sphere(2), shader("glass"), Vector3(0, -0.05, 0), Vector3.ONE * 0.66)
			part(h, torus(0.29, 0.34), std(Color(0.7, 0.72, 0.78), 0.3, 0.8), Vector3(0, -0.17, 0), Vector3(1, 0.7, 1))
			part(h, cyl(0.5, 0.5, 8), std(Color(0.7, 0.72, 0.78), 0.3, 0.8), Vector3(0.27, -0.06, 0.06), Vector3(0.025, 0.2, 0.025), Vector3(0, 0, -0.3))
			part(h, sphere(0), std(Color(1.0, 0.3, 0.25), 0.3, 0.0, 2.4), Vector3(0.3, 0.04, 0.06), Vector3.ONE * 0.06)
		"antennae":
			part(h, torus(0.25, 0.3), std(Color(0.4, 0.85, 0.35), 0.5), Vector3(0, -0.1, 0), Vector3(1, 0.7, 1))
			for side: float in [-1.0, 1.0]:
				var stalk: Node3D = pivot(h, Vector3(0.12 * side, -0.04, 0))
				stalk.set_meta("sway", [0.7, 0.7, 0.18, 0.0, 0.0])
				var b := Basis.IDENTITY.scaled(Vector3.ONE * 0.32)
				if side < 0.0:
					b = Basis(Vector3.UP, PI) * b
				part_b(stalk, arc(0.7, 0.05, 0.035, 6, 8), std(Color(0.5, 0.95, 0.35), 0.5), Vector3.ZERO, b)
				part(stalk, sphere(0), std(Color(0.6, 1.0, 0.3), 0.3, 0.0, 2.2), Vector3(0.075 * side, 0.21, 0), Vector3.ONE * 0.1)
		"horns":
			for side: float in [-1.0, 1.0]:
				# up out of the head, curling back; leaning out to the side
				var b := Basis(Vector3.BACK, -0.45 * side) * Basis(Vector3.UP, -PI * 0.5) * Basis.IDENTITY.scaled(Vector3.ONE * 0.24)
				part_b(h, arc(1.4, 0.32, 0.0, 8, 10), shader("ember"), Vector3(0.17 * side, -0.07, -0.06), b)
		"viking":
			var steel := std(Color(0.62, 0.64, 0.68), 0.35, 0.8)
			var bronze := std(Color(0.75, 0.5, 0.25), 0.35, 0.7)
			var horn := std(Color(0.95, 0.9, 0.75), 0.5)
			part(h, sphere(1), steel, Vector3(0, -0.04, 0), Vector3(0.6, 0.42, 0.62))
			part(h, torus(0.24, 0.31), bronze, Vector3(0, -0.1, 0), Vector3(1, 0.8, 1))
			part(h, sphere(1), bronze, Vector3(0, -0.04, 0), Vector3(0.07, 0.44, 0.64))
			part(h, box(), bronze, Vector3(0, -0.17, -0.3), Vector3(0.05, 0.16, 0.03))
			# horns: out of the sides, sweeping up (path +Y -> out, bend -> up)
			part_b(h, arc(1.1, 0.24, 0.0, 8, 10), horn, Vector3(-0.27, -0.05, 0), Basis(Vector3.BACK, PI * 0.5).scaled(Vector3.ONE * 0.28))
			part_b(h, arc(1.1, 0.24, 0.0, 8, 10), horn, Vector3(0.27, -0.05, 0), (Basis(Vector3.UP, PI) * Basis(Vector3.BACK, PI * 0.5)).scaled(Vector3.ONE * 0.28))
		"pharaoh":
			var cloth := shader("pharaoh")
			var gold := std(Color(1.0, 0.78, 0.25), 0.25, 0.9)
			part(h, sphere(1), cloth, Vector3(0, -0.06, 0.02), Vector3(0.66, 0.44, 0.68))
			for side: float in [-1.0, 1.0]:
				part(h, box(), cloth, Vector3(0.36 * side, -0.29, -0.14), Vector3(0.05, 0.4, 0.14), Vector3(0, 0, 0.12 * side))
			part(h, cyl(0.3, 0.5, 12), cloth, Vector3(0, -0.3, 0.27), Vector3(0.22, 0.34, 0.12))
			part(h, torus(0.29, 0.33), gold, Vector3(0, -0.1, 0), Vector3(1, 0.8, 1))
			part(h, sphere(0), gold, Vector3(0, -0.03, -0.33), Vector3(0.06, 0.12, 0.05))
		"witch":
			var felt := std(Color(0.16, 0.1, 0.22), 0.75)
			part(h, brim("witch"), felt, Vector3(0, -0.06, 0))
			part(h, cyl(0.3, 0.5, 16), felt, Vector3(0, 0.09, 0), Vector3(0.4, 0.3, 0.4))
			# the bent tip: an arc bending back
			part_b(h, arc(0.95, 0.4, 0.0, 10, 10), felt, Vector3(0, 0.235, 0), Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * 0.3))
			part(h, torus(0.17, 0.215), std(Color(0.55, 0.2, 0.7), 0.6), Vector3(0, -0.01, 0), Vector3(1, 1.1, 1))
			part(h, box(), std(Color(1.0, 0.8, 0.25), 0.3, 0.8), Vector3(0, -0.01, -0.205), Vector3(0.07, 0.07, 0.02))
		"tricorn":
			var felt := std(Color(0.1, 0.08, 0.07), 0.8)
			var gold := std(Color(1.0, 0.78, 0.3), 0.3, 0.8)
			part(h, brim("tricorn"), shader("tricorn"), Vector3(0, -0.06, 0))
			part(h, sphere(1), felt, Vector3(0, 0.0, 0), Vector3(0.4, 0.26, 0.4))
			for k: int in 3:
				var th: float = -PI * 0.5 + TAU * float(k) / 3.0
				part(h, sphere(0), gold, Vector3(cos(th) * 0.43, 0.175, sin(th) * 0.43), Vector3.ONE * 0.045)
		"cupcake":
			part(h, cyl(0.5, 0.4, 12), std(Color(0.55, 0.8, 0.95), 0.6), Vector3(0, -0.02, 0), Vector3(0.42, 0.13, 0.42))
			var icing := std(Color(1.0, 0.62, 0.78), 0.35)
			part(h, torus(0.13, 0.23), icing, Vector3(0, 0.06, 0), Vector3(1, 1.2, 1))
			part(h, sphere(1), icing, Vector3(0, 0.1, 0), Vector3(0.32, 0.2, 0.32))
			part(h, sphere(1), icing, Vector3(0, 0.18, 0), Vector3(0.18, 0.15, 0.18))
			var cols: Array[Color] = [Color(0.3, 0.7, 1.0), Color(1.0, 0.9, 0.3), Color(0.5, 1.0, 0.5), Color(1.0, 1.0, 1.0)]
			for k: int in 4:
				var th: float = TAU * float(k) / 4.0 + 0.4
				part(h, box(), std(cols[k], 0.5), Vector3(cos(th) * 0.13, 0.15, sin(th) * 0.13), Vector3(0.014, 0.014, 0.045), Vector3(0.3, th, 0.2))
			part(h, sphere(0), std(Color(0.85, 0.05, 0.12), 0.15), Vector3(0, 0.29, 0), Vector3.ONE * 0.09)
			part(h, cyl(0.5, 0.5, 6), std(Color(0.35, 0.55, 0.2), 0.6), Vector3(0.015, 0.35, 0), Vector3(0.012, 0.08, 0.012), Vector3(0, 0, -0.35))
		"pilot":
			part(h, sphere(1), std(Color(0.92, 0.93, 0.95), 0.3), Vector3(0, -0.07, 0.01), Vector3(0.66, 0.5, 0.7))
			part(h, sphere(1), v.accent_material("base"), Vector3(0, -0.07, 0.01), Vector3(0.12, 0.52, 0.72))
			part(h, sphere(1), std(Color(0.1, 0.12, 0.16), 0.05, 0.6), Vector3(0, 0.0, -0.17), Vector3(0.6, 0.26, 0.4))
			for side: float in [-1.0, 1.0]:
				part(h, sphere(0), std(Color(0.55, 0.57, 0.62), 0.4, 0.5), Vector3(0.33 * side, -0.19, 0.02), Vector3(0.12, 0.17, 0.17))
		"kasa":
			var straw := std(Color(0.86, 0.74, 0.46), 0.9)
			var weave := std(Color(0.62, 0.5, 0.3), 0.9)
			part(h, cyl(0.02, 0.5, 20), straw, Vector3(0, 0.06, 0), Vector3(1.04, 0.24, 1.04))
			part(h, torus(0.34, 0.37), weave, Vector3(0, 0.015, 0), Vector3(1, 0.4, 1))
			part(h, torus(0.17, 0.2), weave, Vector3(0, 0.1, 0), Vector3(1, 0.4, 1))
			part(h, sphere(0), weave, Vector3(0, 0.18, 0), Vector3.ONE * 0.05)
		"pith":
			var khaki := std(Color(0.82, 0.74, 0.55), 0.8)
			part(h, sphere(1), khaki, Vector3(0, -0.02, 0), Vector3(0.56, 0.42, 0.6))
			part(h, brim("pith"), khaki, Vector3(0, -0.07, 0))
			part(h, torus(0.26, 0.295), std(Color(0.45, 0.32, 0.2), 0.7), Vector3(0, -0.05, 0), Vector3(1, 0.9, 1.06))
			part(h, sphere(0), khaki, Vector3(0, 0.19, 0), Vector3(0.06, 0.04, 0.06))
		"cowboy":
			var hat_root: Node3D = pivot(h, Vector3.ZERO, Vector3(0.08, 0, 0))
			var felt := std(Color(0.55, 0.36, 0.2), 0.85)
			part(hat_root, cyl(0.4, 0.5, 20), felt, Vector3(0, 0.04, 0), Vector3(0.4, 0.2, 0.36))
			part(hat_root, sphere(1), std(Color(0.42, 0.27, 0.15), 0.85), Vector3(0, 0.135, 0), Vector3(0.1, 0.04, 0.26))
			part(hat_root, torus(0.17, 0.205), std(Color(0.2, 0.13, 0.08), 0.6), Vector3(0, -0.025, 0), Vector3(1, 1.1, 0.9))
			part(hat_root, brim("cowboy"), felt, Vector3(0, -0.06, 0))
			part(hat_root, sphere(0), std(Color(0.85, 0.85, 0.88), 0.25, 0.9), Vector3(0, -0.025, -0.19), Vector3(0.045, 0.045, 0.02))
		"headphones":
			part_b(h, arc(PI, 0.08, 0.08, 8, 16), std(Color(0.2, 0.95, 1.0), 0.4, 0.0, 1.2), Vector3(-0.32, -0.26, 0.02), Basis.IDENTITY.scaled(Vector3.ONE * 0.32))
			for side: float in [-1.0, 1.0]:
				part(h, cyl(0.5, 0.5, 16), std(Color(0.08, 0.08, 0.12), 0.35), Vector3(0.37 * side, -0.26, 0.02), Vector3(0.2, 0.08, 0.2), Vector3(0, 0, PI * 0.5))
				part(h, torus(0.07, 0.095, 20), std(Color(1.0, 0.2, 0.9), 0.3, 0.0, 2.2), Vector3(0.41 * side, -0.26, 0.02), Vector3.ONE, Vector3(0, 0, PI * 0.5))
		"beanie":
			part(h, sphere(1), v.accent_material("base"), Vector3(0, -0.07, 0), Vector3(0.6, 0.46, 0.6))
			part(h, torus(0.17, 0.33), std(Color(0.95, 0.95, 0.92), 1.0), Vector3(0, -0.13, 0), Vector3(1, 0.85, 1))
			part(h, sphere(0), std(Color(0.95, 0.95, 0.92), 1.0), Vector3(0, 0.19, 0), Vector3.ONE * 0.16)
		"crown":
			var gold := std(Color(1.0, 0.78, 0.25), 0.2, 1.0)
			part(h, cyl(0.5, 0.5, 20, false), std(Color(1.0, 0.78, 0.25), 0.2, 1.0, 0.0, DOUBLE), Vector3(0, -0.01, 0), Vector3(0.42, 0.13, 0.42))
			part(h, sphere(1), std(Color(0.6, 0.06, 0.12), 0.9), Vector3(0, -0.01, 0), Vector3(0.39, 0.2, 0.39))
			for k: int in 4:
				var th: float = -PI * 0.5 + TAU * float(k) / 4.0
				var at := Vector3(cos(th) * 0.2, 0.0, sin(th) * 0.2)
				part(h, cyl(0.0, 0.5, 8), gold, at + Vector3(0, 0.11, 0), Vector3(0.08, 0.12, 0.08))
				part(h, sphere(0), std(Color(1.0, 0.97, 0.9), 0.2), at + Vector3(0, 0.18, 0), Vector3.ONE * 0.04)
			var gems: Array[Color] = [Color(0.95, 0.1, 0.2), Color(0.15, 0.4, 1.0), Color(0.1, 0.85, 0.35)]
			for k: int in 3:
				var th: float = -PI * 0.5 + (float(k) - 1.0) * 0.8
				part(h, sphere(0), std(gems[k], 0.1, 0.2, 0.4), Vector3(cos(th) * 0.212, -0.01, sin(th) * 0.212), Vector3(0.05, 0.05, 0.025), Vector3(0, -th - PI * 0.5, 0))
		"halo":
			var float_node: Node3D = pivot(h, Vector3(0, 0.2, 0), Vector3(0.12, 0, 0))
			float_node.set_meta("bob", [0.03, 2.2])
			float_node.set_meta("spin", [0.6, 0.0])
			part(float_node, torus(0.17, 0.205, 32), std(Color(1.0, 0.86, 0.45), 0.3, 0.0, 2.5), Vector3.ZERO)
			var glow: MeshInstance3D = part(float_node, torus(0.14, 0.24, 32), std(Color(1.0, 0.9, 0.5, 0.22), 0.5, 0.0, 0.0, UNSHADED | ADDITIVE), Vector3.ZERO, Vector3(1, 0.6, 1))
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"party":
			var tilt: Node3D = pivot(h, Vector3(0, -0.06, 0), Vector3(0, 0, 0.18))
			part(tilt, cyl(0.0, 0.5, 16), shader("party"), Vector3(0, 0.21, 0), Vector3(0.32, 0.42, 0.32))
			part(tilt, sphere(0), v.accent_material("base"), Vector3(0, 0.43, 0), Vector3.ONE * 0.1)
	return h
