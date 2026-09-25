class_name DesertSky
extends RefCounted
## Scarab Sands' sky: late afternoon sliding into golden hour. A deep azure zenith warming to
## peach and gold at the horizon (brightest under the sun, dustier and rosier opposite), a big
## low sun with a wide glare, sunlit cirrus streaks, a band of dust haze on the horizon and a
## pale daytime moon. Static (no TIME) so the radiance map is only rendered once.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.13, 0.3, 0.64);
uniform vec3 upper : source_color = vec3(0.42, 0.56, 0.78);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.72, 0.4);
uniform vec3 horizon_far : source_color = vec3(0.86, 0.62, 0.55);
uniform vec3 haze : source_color = vec3(0.98, 0.78, 0.52);
uniform vec3 ground : source_color = vec3(0.78, 0.55, 0.34);
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
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	// LIGHT0 can be unset (zero) when the radiance map is first baked: normalize(0) is NaN, and a
	// NaN sky blacks out every surface it lights (and glow spreads it into black blotches)
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(-0.35, 0.44, 0.83));
	float up = d.y;
	vec2 dh = normalize(d.xz + vec2(0.0001));
	vec2 lh = normalize(L.xz + vec2(0.0001));
	// clamped: rounding can push the dot a hair past -1, and pow() of a negative is NaN (a NaN
	// texel in the sky poisons its whole radiance map and blacks out every lit surface)
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);      // 1 under the sun, 0 opposite
	vec3 hor = mix(horizon_far, horizon_sun, pow(toward, 1.6));
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.28, up));
	col = mix(col, zenith, smoothstep(0.2, 0.85, up));
	// dust haze sitting on the horizon
	float band = exp(-abs(up) * 14.0);
	col = mix(col, haze * (0.85 + 0.3 * toward), band * 0.75);
	// cirrus: long streaks, lit gold toward the sun
	if (up > 0.0) {
		vec2 cp = d.xz / (up + 0.12);
		float streak = fbm(vec2(cp.x * 0.9 + cp.y * 0.35, cp.y * 3.2) * 1.4);
		float c = smoothstep(0.52, 0.8, streak) * smoothstep(0.02, 0.2, up) * (1.0 - smoothstep(0.6, 0.95, up));
		vec3 cc = mix(vec3(1.0, 0.93, 0.85), vec3(1.0, 0.7, 0.42), pow(toward, 3.0));
		col = mix(col, cc, c * 0.55);
	}
	// the sun: a warm disc, a tight glare and a wide golden bloom
	float sd = dot(d, L);
	col += vec3(1.0, 0.94, 0.8) * smoothstep(0.99962, 0.99978, sd) * 30.0;
	col += vec3(1.0, 0.82, 0.55) * pow(max(sd, 0.0), 700.0) * 4.0;
	col += vec3(1.0, 0.7, 0.4) * pow(max(sd, 0.0), 24.0) * 0.35;
	col += vec3(1.0, 0.75, 0.45) * pow(max(sd, 0.0), 4.0) * 0.12;
	// a pale daytime moon, low on the far side
	vec3 M = normalize(moon_dir);
	float md = dot(d, M);
	float disc = smoothstep(0.99975, 0.99985, md);
	float lit = 0.55 + 0.45 * noise2(d.xy * 900.0);
	col = mix(col, vec3(0.95, 0.92, 0.9) * lit, disc * 0.55);
	// below the horizon: hazy sand
	col = mix(col, mix(haze, ground, 1.0 - smoothstep(-0.35, 0.0, up)), 1.0 - smoothstep(-0.02, 0.0, up));
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
