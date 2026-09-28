class_name ManorSky
extends RefCounted
## Phantom Manor's sky: midnight under a huge blood moon. A near-black violet zenith, a bruised
## purple band down to a sickly green glow on the horizon, a dense field of cold stars, and the
## moon itself - a great copper-red disc with dark maria, a darkened limb, a wide red halo and
## torn clouds drifting across it, lit crimson on the side toward it. The moon sits where the
## level's key light comes from (LIGHT0), so the moonlight and the disc agree. Static (no TIME),
## so the radiance map is only rendered once.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.018, 0.01, 0.04);
uniform vec3 upper : source_color = vec3(0.07, 0.035, 0.11);
uniform vec3 horizon : source_color = vec3(0.2, 0.08, 0.16);
uniform vec3 green_glow : source_color = vec3(0.12, 0.24, 0.14);
uniform vec3 ground : source_color = vec3(0.035, 0.03, 0.05);
uniform vec3 moon_col : source_color = vec3(0.95, 0.24, 0.12);
uniform float moon_size = 0.9915;

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
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
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
	vec3 tint = mix(vec3(0.8, 0.82, 1.0), vec3(1.0, 0.85, 0.8), hash13(cell + 7.0));
	return tint * k * (0.35 + 1.4 * fract(h * 37.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	// LIGHT0 can be unset (zero) while the radiance map is first baked: never normalize a zero
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.25, 0.32, -0.9));
	float up = d.y;
	vec3 col = mix(horizon, upper, smoothstep(0.0, 0.3, up));
	col = mix(col, zenith, smoothstep(0.25, 0.9, up));
	// the sickly green graveyard glow hanging on the horizon, away from the moon
	vec2 dh = normalize(d.xz + vec2(0.0001, 0.0));
	vec2 lh = normalize(L.xz + vec2(0.0001, 0.0));
	float away = clamp(0.5 - 0.5 * dot(dh, lh), 0.0, 1.0);
	col += green_glow * exp(-abs(up) * 9.0) * (0.35 + 0.65 * away);
	// stars (fading into the horizon murk and under the moon's glare)
	float md = clamp(dot(d, L), -1.0, 1.0);
	float vis = smoothstep(0.03, 0.35, up) * (1.0 - smoothstep(0.93, 0.985, md));
	col += stars(d, 160.0, 0.018, 0.17) * 1.1 * vis;
	col += stars(d, 380.0, 0.03, 0.22) * 0.45 * vis;
	col += stars(d, 60.0, 0.005, 0.1) * 2.0 * vis;
	// the moon's red halo: a wide wash and a tight corona
	float near_m = clamp(md, 0.0, 1.0);
	col += moon_col * pow(near_m, 8.0) * 0.16;
	col += moon_col * pow(near_m, 60.0) * 0.35;
	col += vec3(1.0, 0.4, 0.25) * pow(near_m, 600.0) * 0.6;
	// the disc: copper-red with dark maria and a darkened limb
	float disc = smoothstep(moon_size, moon_size + 0.0004, md);
	if (disc > 0.0) {
		float rim = clamp((md - moon_size) / (1.0 - moon_size), 0.0, 1.0);
		float limb = 0.45 + 0.55 * sqrt(rim);
		float maria = fbm(d * 38.0);
		float craters = smoothstep(0.62, 0.7, noise3(d * 140.0));
		vec3 surf = moon_col * (0.75 + 0.5 * smoothstep(0.35, 0.7, maria)) * (1.0 - 0.25 * craters);
		surf = mix(surf * 0.55, surf, smoothstep(0.4, 0.6, maria));
		col = mix(col, surf * limb * 1.35, disc);
	}
	// torn clouds drifting across the sky, lit crimson toward the moon, black-violet away from it
	if (up > -0.02) {
		vec3 cp = vec3(d.x / (up + 0.25), 0.0, d.z / (up + 0.25));
		float c = fbm(cp * vec3(1.2, 1.0, 2.6) + vec3(3.0, 0.0, 0.0));
		float cover = smoothstep(0.5, 0.78, c) * smoothstep(0.0, 0.12, up + 0.02) * (1.0 - smoothstep(0.55, 0.9, up));
		vec3 lit = mix(vec3(0.06, 0.035, 0.07), moon_col * 0.55, pow(near_m, 5.0));
		col = mix(col, lit, cover * 0.85);
	}
	// below the horizon: the dark valley in the mist
	col = mix(col, ground, 1.0 - smoothstep(-0.06, 0.0, up));
	COLOR = col;
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
