class_name XenoSky
extends RefCounted
## Xeno Wilds' sky: a violet-to-teal alien sky over a low-gravity moon. A colossal ringed gas giant
## fills a third of it - rose-gold and rust storm bands with a great eye, a soft shaded terminator,
## a thin cream atmosphere limb, the rings' shadow striping its face and its own shadow cutting
## across the rings - with a small cratered second moon beside it and two suns sitting low: a
## teal-white primary and a swollen amber companion, each with its own glare. Faint stars show
## high overhead. Static (no TIME), so the radiance map is only rendered once; the auroras are
## separate meshes (visual/xeno_aurora.gdshader).

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.07, 0.02, 0.17);
uniform vec3 upper : source_color = vec3(0.26, 0.08, 0.38);
uniform vec3 horizon : source_color = vec3(0.16, 0.52, 0.56);
uniform vec3 below : source_color = vec3(0.04, 0.08, 0.12);
uniform vec3 sun1_dir = vec3(0.6, 0.25, -0.75);
uniform vec3 sun1_col : source_color = vec3(0.7, 1.0, 0.95);
uniform vec3 sun2_dir = vec3(-0.8, 0.12, -0.4);
uniform vec3 sun2_col : source_color = vec3(1.0, 0.62, 0.25);
uniform vec3 planet_dir = vec3(-0.25, 0.42, -0.87);
uniform float planet_size = 0.36;
uniform vec3 ring_normal = vec3(0.28, 0.9, 0.34);
uniform vec3 band_a : source_color = vec3(0.95, 0.72, 0.52);
uniform vec3 band_b : source_color = vec3(0.62, 0.3, 0.26);
uniform vec3 band_c : source_color = vec3(0.98, 0.9, 0.78);
uniform vec3 storm : source_color = vec3(0.9, 0.42, 0.3);
uniform vec3 moon_dir = vec3(0.35, 0.5, -0.8);
uniform float moon_size = 0.045;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

vec3 stars(vec3 d, float scale, float density, float size) {
	vec3 sd = d * scale;
	vec3 cell = floor(sd);
	vec3 f = fract(sd);
	float h = hash13(cell);
	if (h < 1.0 - density) {
		return vec3(0.0);
	}
	vec3 j = hash33(cell) * 0.6 + 0.2;
	float r = length(f - j);
	float k = 1.0 - smoothstep(0.0, size, r);
	vec3 tint = mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.8, 0.9), hash13(cell + 7.0));
	return tint * k * (0.4 + 1.2 * fract(h * 37.0));
}

// does the ray from p toward L pass through the ring annulus? (0..1 opacity)
float ring_at(vec3 q, vec3 C, float R) {
	float r = length(q - C) / R;
	if (r < 1.32 || r > 2.45) {
		return 0.0;
	}
	float bands = 0.55 + 0.45 * sin(r * 38.0) * sin(r * 11.0 + 1.3);
	float gap = smoothstep(0.012, 0.03, abs(r - 1.86)) * smoothstep(0.008, 0.02, abs(r - 2.2));
	float edge = smoothstep(1.32, 1.4, r) * (1.0 - smoothstep(2.35, 2.45, r));
	return clamp(bands, 0.0, 1.0) * gap * edge * 0.85;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 L1 = normalize(sun1_dir);
	vec3 L2 = normalize(sun2_dir);
	float up = d.y;
	// ---- the air: deep violet overhead, magenta band, teal haze at the horizon ----
	vec3 col = mix(horizon, upper, smoothstep(0.02, 0.35, up));
	col = mix(col, zenith, smoothstep(0.3, 0.95, up));
	col = mix(col, below, 1.0 - smoothstep(-0.3, 0.0, up));
	// the suns warm the air round themselves and along the horizon under them
	float s1 = max(dot(d, L1), 0.0);
	float s2 = max(dot(d, L2), 0.0);
	col += sun1_col * pow(s1, 6.0) * 0.28 + sun1_col * pow(s1, 60.0) * 0.5;
	col += sun2_col * pow(s2, 4.0) * 0.4 + sun2_col * pow(s2, 40.0) * 0.6;
	col += sun2_col * exp(-abs(up) * 9.0) * pow(max(dot(normalize(vec3(d.x, 0.0, d.z) + vec3(0.0001, 0.0, 0.0)), normalize(vec3(L2.x, 0.0, L2.z))), 0.0), 3.0) * 0.35;
	// faint stars high up
	float night = smoothstep(0.25, 0.8, up);
	col += stars(d, 160.0, 0.02, 0.16) * night * 0.9;
	col += stars(d, 60.0, 0.006, 0.1) * night * 1.6;
	// ---- the suns' discs ----
	col += sun1_col * smoothstep(0.99935, 0.9996, dot(d, L1)) * 30.0;
	col += sun2_col * smoothstep(0.9982, 0.9988, dot(d, L2)) * 14.0;
	// ---- the second moon: a small grey-violet cratered disc lit by the primary ----
	vec3 M = normalize(moon_dir);
	float mr = sin(moon_size);
	float mb = dot(d, M);
	float mdisc = mb * mb - (1.0 - mr * mr);
	if (mdisc > 0.0 && mb > 0.0) {
		vec3 mp = d * (mb - sqrt(mdisc));
		vec3 mn = normalize(mp - M);
		float lit = max(dot(mn, L1), 0.0) + max(dot(mn, L2), 0.0) * 0.4;
		float crater = smoothstep(0.55, 0.75, noise3(mn * 9.0)) * 0.35;
		vec3 ms = vec3(0.72, 0.68, 0.8) * (1.0 - crater);
		col = ms * (lit * 1.1 + 0.04);
	}
	// ---- the gas giant ----
	vec3 C = normalize(planet_dir);
	float R = sin(planet_size);
	vec3 N = normalize(ring_normal);
	float b = dot(d, C);
	float disc = b * b - (1.0 - R * R);
	float t_planet = 100000.0;
	vec3 surf = vec3(0.0);
	bool hit = disc > 0.0 && b > 0.0;
	if (hit) {
		t_planet = b - sqrt(disc);
		vec3 P = d * t_planet;
		vec3 n = normalize(P - C);
		// bands follow the planet's own latitude (its axis is the ring normal)
		float lat = dot(n, N);
		vec3 tang = normalize(cross(N, vec3(0.0, 0.0, 1.0)));
		float lon = atan(dot(n, tang), dot(n, cross(N, tang)));
		float turb = fbm(vec3(lat * 6.0, lon * 1.2, 1.0) + vec3(0.0, 0.0, lat * 4.0)) - 0.5;
		float bl = lat * 14.0 + turb * 2.4 + sin(lon * 3.0 + lat * 9.0) * 0.25;
		float k1 = 0.5 + 0.5 * sin(bl);
		float k2 = 0.5 + 0.5 * sin(bl * 2.7 + 1.1);
		vec3 ground = mix(band_b, band_a, k1);
		ground = mix(ground, band_c, smoothstep(0.7, 1.0, k2) * 0.6);
		// the great storm: an oval eye with a swirl round it
		vec2 ep = vec2(lon - 0.7, (lat + 0.28) * 3.2);
		float eye = length(ep * vec2(1.0, 1.6));
		float swirl = sin(eye * 22.0 - atan(ep.y, ep.x) * 2.0) * 0.5 + 0.5;
		ground = mix(ground, storm, (1.0 - smoothstep(0.1, 0.34, eye)) * (0.6 + 0.4 * swirl));
		ground = mix(ground, band_c, (1.0 - smoothstep(0.0, 0.08, eye)) * 0.5);
		// light: the primary shapes the terminator, the amber companion warms the other limb
		float ndl1 = dot(n, L1);
		float ndl2 = dot(n, L2);
		float light = smoothstep(-0.18, 0.5, ndl1) * 1.05 + smoothstep(-0.1, 0.6, ndl2) * 0.35;
		// ring shadow: the ray from this point toward the primary crosses the rings
		float tr = dot(C - P, N) / dot(L1, N);
		float rs = tr > 0.0 ? ring_at(P + L1 * tr, C, R) : 0.0;
		light *= 1.0 - rs * 0.75;
		surf = ground * (light * 1.15 + 0.03);
		surf *= mix(vec3(1.0), sun2_col * 1.2, smoothstep(0.0, 0.6, ndl2) * 0.25);
		// atmosphere: a thin cream limb, brightest on the lit side
		float rim = pow(1.0 - max(dot(n, -d), 0.0), 3.0);
		surf += vec3(1.0, 0.85, 0.7) * rim * (0.08 + 0.6 * smoothstep(-0.3, 0.5, ndl1));
		col = surf;
	} else {
		// a soft halo just outside the limb
		float tc = max(b, 0.0);
		float h = length(d * tc - C) - R;
		float lit = smoothstep(-0.4, 0.5, dot(normalize(d * tc - C), L1));
		col += vec3(1.0, 0.8, 0.65) * exp(-max(h, 0.0) * 60.0) * (0.1 + 0.5 * lit) * step(0.0, b);
	}
	// ---- the rings: in front of the planet, or seen past its edge ----
	float dn = dot(d, N);
	if (abs(dn) > 0.0005) {
		float t_ring = dot(C, N) / dn;
		if (t_ring > 0.0 && t_ring < t_planet) {
			vec3 Q = d * t_ring;
			float a = ring_at(Q, C, R);
			if (a > 0.0) {
				// the planet's shadow falls across the rings behind it
				vec3 toC = C - Q;
				float bb = dot(toC, L1);
				float shadow = 0.0;
				if (bb > 0.0) {
					float dist = length(toC - L1 * bb);
					shadow = 1.0 - smoothstep(R * 0.96, R * 1.02, dist);
				}
				float r = length(Q - C) / R;
				vec3 rc = mix(vec3(0.95, 0.85, 0.7), vec3(0.7, 0.55, 0.5), 0.5 + 0.5 * sin(r * 7.0));
				float rl = 0.25 + 0.95 * (1.0 - shadow * 0.9);
				// back-lit rings glow warmer when you look toward a sun through them
				rl += pow(max(dot(d, L2), 0.0), 3.0) * 0.4;
				col = mix(col, rc * rl, a);
			}
		}
	}
	COLOR = col;
}
"""

## Sun directions and the look of the giant; the level passes its lights' real directions.
static func make(sun1: Vector3, sun1_col: Color, sun2: Vector3, sun2_col: Color) -> Sky:
	var sh := Shader.new()
	sh.code = CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("sun1_dir", sun1)
	m.set_shader_parameter("sun1_col", Vector3(sun1_col.r, sun1_col.g, sun1_col.b))
	m.set_shader_parameter("sun2_dir", sun2)
	m.set_shader_parameter("sun2_col", Vector3(sun2_col.r, sun2_col.g, sun2_col.b))
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky
