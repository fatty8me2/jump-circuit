class_name SakuraSky
extends RefCounted
## Sakura Peaks' sky: a mountain dusk. A deep indigo zenith where the first stars are coming out,
## melting through violet and rose into a blazing apricot-and-vermilion horizon round a huge low
## sun, long streaks of cloud lit pink and gold from below, and a thin crescent moon rising on the
## far side. Static (no TIME), so the radiance map is rendered once. Every term is bounded and
## NaN-safe: pow() only of clamped values, no normalize() of a possibly zero vector, smoothstep
## edges in order, and the sun's HDR peak capped.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.09, 0.09, 0.26);
uniform vec3 upper : source_color = vec3(0.36, 0.25, 0.5);
uniform vec3 rose : source_color = vec3(0.92, 0.5, 0.58);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.58, 0.26);
uniform vec3 horizon_far : source_color = vec3(0.78, 0.46, 0.6);
uniform vec3 below : source_color = vec3(0.62, 0.44, 0.54);
uniform vec3 moon_dir = vec3(-0.55, 0.42, 0.72);

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
	for (int i = 0; i < 5; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.6, 0.15, -0.8));
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	vec2 lh = L.xz + vec2(0.0001);
	lh = lh / max(length(lh), 0.0001);
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	// the gradient: the horizon glows apricot toward the sun and rose-mauve away from it
	vec3 hor = mix(horizon_far, horizon_sun, pow(toward, 2.2));
	vec3 col = mix(hor, rose, smoothstep(0.02, 0.16, up) * (1.0 - toward * 0.5));
	col = mix(col, upper, smoothstep(0.1, 0.42, up));
	col = mix(col, zenith, smoothstep(0.35, 0.95, up));
	// a warm band hugging the horizon all the way round
	col += vec3(0.35, 0.16, 0.06) * (1.0 - smoothstep(0.0, 0.08, abs(up))) * (0.4 + 0.6 * toward);
	// long streaks of cloud, lit gold and pink from below by the low sun
	if (up > -0.02) {
		vec2 cp = d.xz / (up + 0.12);
		float n = fbm(vec2(cp.x * 0.35, cp.y * 1.6) + vec2(3.0, 1.0));
		float streak = smoothstep(0.52, 0.78, n) * smoothstep(-0.02, 0.06, up) * (1.0 - smoothstep(0.22, 0.5, up));
		vec3 lit = mix(vec3(0.95, 0.5, 0.62), vec3(1.0, 0.72, 0.4), pow(toward, 2.0));
		lit = mix(lit, vec3(0.42, 0.3, 0.5), smoothstep(0.12, 0.4, up));
		col = mix(col, lit, streak * 0.75);
	}
	// stars: coming out in the darkening upper sky, away from the sun
	if (up > 0.12) {
		vec2 sc = d.xz / (up + 0.001) * 70.0;
		vec2 cell = floor(sc);
		float s = hash12(cell);
		vec2 f = fract(sc) - 0.5;
		float star = (1.0 - smoothstep(0.0, 0.1, length(f))) * step(0.982, s);
		float tw = 0.6 + 0.4 * hash12(cell + 7.0);
		col += vec3(1.0, 0.95, 0.9) * star * tw * smoothstep(0.15, 0.6, up) * (1.0 - toward * 0.8) * 1.1;
	}
	// the crescent moon on the far side
	vec3 M = moon_dir / max(length(moon_dir), 0.0001);
	float md = clamp(dot(d, M), -1.0, 1.0);
	vec3 off = normalize(M + vec3(0.03, 0.02, 0.0));
	float od = clamp(dot(d, off), -1.0, 1.0);
	float disc = smoothstep(0.99955, 0.9997, md);
	float bite = smoothstep(0.99955, 0.9997, od);
	col = mix(col, vec3(1.0, 0.96, 0.86) * 1.6, clamp(disc - bite, 0.0, 1.0));
	col += vec3(0.5, 0.45, 0.6) * pow(max(md, 0.0), 400.0) * 0.25;
	// the great low sun: a soft disc with haze bands, a hot glow and a wide warm bloom
	float sd = clamp(dot(d, L), -1.0, 1.0);
	float sp = max(sd, 0.0);
	float sdisc = smoothstep(0.9982, 0.9988, sd);
	float bands = 1.0 - 0.35 * smoothstep(0.4, 0.6, noise2(vec2(d.y * 120.0, 0.0))) * smoothstep(-0.05, 0.06, d.y - L.y + 0.01);
	col = mix(col, vec3(1.0, 0.62, 0.32) * 3.2 * bands, sdisc);
	col += vec3(1.0, 0.5, 0.22) * pow(sp, 90.0) * 1.1;
	col += vec3(1.0, 0.45, 0.25) * pow(sp, 9.0) * 0.32;
	// below the horizon: the misty valley
	col = mix(col, below, 1.0 - smoothstep(-0.14, 0.0, up));
	COLOR = clamp(col, vec3(0.0), vec3(6.0));
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
