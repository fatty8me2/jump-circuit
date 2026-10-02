class_name VoidSky
extends RefCounted
## The Void's sky: a SHATTERED dream sky. A violet-black dome has cracked like a pane of glass into
## great shards, their seams glowing thin pink and cyan; some shards have slipped and show the wrong
## sky behind them - a pale lavender-and-rose daylight, as if another day were on the far side - and
## a few have fallen out altogether, leaving holes of deeper black. A colossal clock face with no
## hands hangs low in one quarter of the sky, cracked across. Toward the horizon a soft band of
## rose and violet haze; below it, nothing but a slow fade into darkness.
## Not space: no stars, no planet - a dream coming apart. Static (no TIME), so the radiance map is
## rendered once. Every term is bounded and NaN-safe: no pow() of negatives, no normalize() of a
## zero vector, smoothstep edges in order, divisions guarded.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.025, 0.006, 0.05);
uniform vec3 mid : source_color = vec3(0.09, 0.03, 0.16);
uniform vec3 haze : source_color = vec3(0.42, 0.16, 0.42);
uniform vec3 below : source_color = vec3(0.012, 0.004, 0.025);
uniform vec3 day_a : source_color = vec3(0.78, 0.66, 0.9);
uniform vec3 day_b : source_color = vec3(0.98, 0.72, 0.8);
uniform vec3 pink : source_color = vec3(1.0, 0.36, 0.72);
uniform vec3 cyan : source_color = vec3(0.32, 0.9, 1.0);
uniform vec3 clock_dir = vec3(0.55, 0.32, -0.77);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p = p * 2.07 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return s;
}

// voronoi: x = distance to the nearest seam, yz = id of the shard
vec3 shards(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash12(i + g), hash12(i + g + vec2(19.1, 7.3)));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = i + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d2 - d1, id);
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	float up = d.y;
	// base dome: violet-black overhead, a rose-violet haze band at the horizon
	vec3 col = mix(mid, zenith, smoothstep(0.05, 0.75, up));
	float band = 1.0 - smoothstep(0.0, 0.3, abs(up - 0.02));
	col = mix(col, haze, band * 0.75);
	if (up > -0.05) {
		// the shattered pane: big shards in a projection that grows toward the horizon
		vec2 sp = d.xz / max(up + 0.35, 0.05) * 1.6;
		vec3 v = shards(sp);
		float seam = v.x;
		float r = hash12(v.yz);
		float r2 = hash12(v.yz + vec2(4.2, 1.3));
		float fade_h = smoothstep(-0.05, 0.12, up);
		// slipped shards show the pale other-sky (a soft gradient with drifting cloud)
		if (r < 0.22) {
			float cl = fbm(sp * 1.3 + v.yz);
			vec3 day = mix(day_a, day_b, clamp(0.5 + 0.5 * sin(r2 * 6.28 + sp.y * 0.4), 0.0, 1.0));
			day = mix(day, vec3(0.98, 0.96, 1.0), smoothstep(0.55, 0.8, cl) * 0.6);
			col = mix(col, day * (0.55 + 0.25 * r2), fade_h * 0.85);
		} else if (r > 0.9) {
			// a shard fallen out: a hole of deeper black
			col = mix(col, below * 0.5, fade_h * 0.85);
		} else {
			// most shards: the dark dome, each tilted a touch so it catches light differently
			col *= 0.8 + 0.45 * r2;
		}
		// glowing seams, pink and cyan by shard
		float line = 1.0 - smoothstep(0.0, 0.035, seam);
		vec3 sc = mix(pink, cyan, step(0.5, r2));
		col += sc * line * 0.9 * fade_h;
		col += sc * (1.0 - smoothstep(0.0, 0.18, seam)) * 0.12 * fade_h;
	}
	// soft dream-wisps in the haze band
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	float az = atan(dh.y, dh.x);
	float w = fbm(vec2(az * 2.4, up * 7.0) + vec2(5.0, 1.0));
	col += mix(pink, cyan, smoothstep(0.3, 0.7, noise2(vec2(az * 1.3, 2.0)))) * smoothstep(0.55, 0.85, w) * band * 0.22;
	// the colossal clock with no hands: a pale rim, twelve marks, a crack across it
	vec3 C = clock_dir / max(length(clock_dir), 0.0001);
	float cd = clamp(dot(d, C), -1.0, 1.0);
	float ang = acos(cd);
	if (ang < 0.3) {
		vec3 ax = normalize(cross(C, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
		vec3 ay = cross(ax, C);
		vec2 q = vec2(dot(d, ax), dot(d, ay));
		float rr = length(q);
		float face = 1.0 - smoothstep(0.205, 0.21, rr);
		col = mix(col, vec3(0.86, 0.82, 0.92) * 0.32, face * 0.85);
		float rim = (1.0 - smoothstep(0.004, 0.008, abs(rr - 0.2))) + (1.0 - smoothstep(0.002, 0.005, abs(rr - 0.185))) * 0.6;
		float qa = atan(q.y, q.x);
		float mk = abs(fract(qa / 6.2831853 * 12.0 + 0.5) - 0.5);
		float marks = (1.0 - smoothstep(0.03, 0.05, mk)) * step(0.155, rr) * (1.0 - step(0.18, rr));
		float crack = (1.0 - smoothstep(0.0, 0.003, abs(q.y - 0.35 * q.x + 0.02 * sin(q.x * 90.0)))) * face;
		col += vec3(0.95, 0.92, 1.0) * (rim + marks) * 0.9;
		col += pink * crack * 1.2;
		col += vec3(0.6, 0.45, 0.8) * (1.0 - smoothstep(0.2, 0.3, rr)) * 0.06;
	}
	// below the horizon: a slow fall into darkness
	col = mix(col, below, 1.0 - smoothstep(-0.25, 0.0, up));
	COLOR = clamp(col, vec3(0.0), vec3(3.0));
}
"""


static func make() -> Sky:
	var sh := Shader.new()
	sh.code = CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky
