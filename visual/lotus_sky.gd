class_name LotusSky
extends RefCounted
## Lotus Drift's sky: a misty dusk. A peach glow sits low on the horizon under a long violet band,
## deepening through plum to indigo overhead, with the first stars out high up. A big pale moon
## hangs a little above the far ridges, wrapped in a soft halo; five layers of mountain ridge march
## away to the horizon, each paler and mistier than the one in front, the farthest half lost in
## glowing fog; a few long, flat clouds streak the glow, lit rose underneath. Below the horizon the
## sky is the dark of the water.
## Static (no TIME): the radiance map is rendered once. Every term is bounded and NaN-safe: no
## pow() of negatives, no normalize() of a zero vector, smoothstep edges in order, divides guarded.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.045, 0.05, 0.16);
uniform vec3 upper : source_color = vec3(0.16, 0.12, 0.33);
uniform vec3 band : source_color = vec3(0.72, 0.38, 0.52);
uniform vec3 glow : source_color = vec3(1.0, 0.64, 0.42);
uniform vec3 below : source_color = vec3(0.025, 0.07, 0.1);
uniform vec3 moon_color : source_color = vec3(1.0, 0.95, 0.82);
uniform vec3 moon_dir = vec3(-0.34, 0.2, -0.92);
uniform vec3 ridge_near : source_color = vec3(0.09, 0.07, 0.17);
uniform vec3 ridge_far : source_color = vec3(0.62, 0.4, 0.5);

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

// a ridge line: height (in sky-up units) of layer k in the horizontal direction h (noise sampled
// on a circle, so it has no seam)
float ridge(vec2 h, float k) {
	float base = 0.035 + 0.02 * k;
	return base + (0.07 + 0.012 * k) * fbm(h * (2.6 + 0.5 * k) + vec2(k * 11.0, k * 3.7)) + 0.03 * noise2(h * 9.0 + vec2(k * 5.0, k));
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	float az = atan(dh.y, dh.x);
	// the dome: glow low, a rose-violet band above it, indigo overhead
	vec3 col = mix(glow, band, smoothstep(0.0, 0.14, up));
	col = mix(col, upper, smoothstep(0.1, 0.42, up));
	col = mix(col, zenith, smoothstep(0.35, 0.95, up));
	// the sunset side is brighter: the glow leans toward -Z / +X
	float side = 0.5 + 0.5 * dot(dh, normalize(vec2(0.35, -0.94)));
	col += glow * 0.35 * side * (1.0 - smoothstep(0.0, 0.22, up));
	// stars, only high up and only in the dark of the dome
	if (up > 0.18) {
		vec2 sp = vec2(az * 40.0, up * 60.0);
		vec2 cell = floor(sp);
		float r = hash12(cell);
		vec2 f = fract(sp) - 0.5;
		float star = step(0.93, r) * (1.0 - smoothstep(0.0, 0.2 + 0.15 * hash12(cell + 3.0), length(f)));
		col += vec3(1.0, 0.95, 0.9) * star * smoothstep(0.18, 0.5, up) * (0.5 + 0.5 * hash12(cell + 9.0));
	}
	// long flat clouds, lit rose from below by the glow
	float cl = fbm(vec2(dh.x * 2.6 + dh.y * 1.3, up * 16.0 + dh.y * 3.0) + vec2(2.0, 5.0));
	float cband = smoothstep(0.06, 0.14, up) * (1.0 - smoothstep(0.22, 0.4, up));
	float cm = smoothstep(0.52, 0.72, cl) * cband;
	col = mix(col, mix(band * 1.15, glow, 0.35), cm * 0.55);
	// the moon and its halo
	vec3 M = moon_dir / max(length(moon_dir), 0.0001);
	float md = clamp(dot(d, M), -1.0, 1.0);
	float ang = acos(md);
	float disc = 1.0 - smoothstep(0.052, 0.058, ang);
	vec3 mcol = moon_color * 1.35;
	// a few soft maria on the face
	vec3 ax = normalize(cross(M, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
	vec3 ay = cross(ax, M);
	vec2 q = vec2(dot(d, ax), dot(d, ay)) * 17.0;
	mcol *= 0.9 + 0.12 * fbm(q * 3.0 + vec2(1.0, 2.0));
	col = mix(col, mcol, disc);
	col += moon_color * (1.0 - smoothstep(0.05, 0.3, ang)) * 0.22;
	col += moon_color * (1.0 - smoothstep(0.05, 0.9, ang)) * 0.05;
	// five ridges, far to near; each fades into the glowing mist
	float amount = 0.0;
	vec3 land = col;
	for (int i = 0; i < 5; i++) {
		float k = float(4 - i);
		float h = ridge(dh, k);
		float inside = 1.0 - smoothstep(h - 0.004, h + 0.004, up);
		float t = k / 4.0;
		vec3 rc = mix(ridge_near, ridge_far, t);
		// mist hugging the foot of each ridge
		float mist = smoothstep(h - 0.09, h, up) * (1.0 - smoothstep(h, h + 0.02, up));
		land = mix(land, glow * 0.8 + band * 0.2, mist * 0.25 * (0.4 + 0.6 * t));
		land = mix(land, rc, inside);
		// the far ones dissolve into fog
		land = mix(land, mix(band, glow, 0.5), inside * t * 0.45);
	}
	col = land;
	// below the horizon: the dark water
	col = mix(col, below, 1.0 - smoothstep(-0.2, 0.0, up));
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
