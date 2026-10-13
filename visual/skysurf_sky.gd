class_name SkysurfSky
extends RefCounted
## Sky Surf's sky: the minute the sun clears the horizon. A periwinkle zenith melting through lilac and
## rose into a band of peach-gold at the horizon, a big soft sun low ahead with a slow fan of light
## rays, layered cloud banks along the horizon (gold underlit toward the sun, lilac on the far side),
## fine cirrus combed across the upper sky, and a haze of pink below the horizon that matches the
## cloud sea. Static (no TIME), so the radiance map renders once. Every term is bounded and NaN-safe:
## pow() only of clamped values, no normalize() of a zero vector, smoothstep edges in order.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.40, 0.50, 0.92);
uniform vec3 upper : source_color = vec3(0.74, 0.64, 0.95);
uniform vec3 rose : source_color = vec3(1.0, 0.70, 0.78);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 horizon_far : source_color = vec3(0.98, 0.74, 0.84);
uniform vec3 below : source_color = vec3(0.95, 0.76, 0.88);

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
		p = p * 2.03 + vec2(3.7, 1.3);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.4, 0.3, -0.85));
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	vec2 lh = L.xz + vec2(0.0001);
	lh = lh / max(length(lh), 0.0001);
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	float az = atan(dh.y, dh.x);

	// the gradient: gold at the sun's side of the horizon, pink on the far side, rose, lilac, periwinkle
	vec3 hor = mix(horizon_far, horizon_sun, pow(toward, 2.2));
	vec3 col = mix(hor, rose, smoothstep(0.0, 0.10, up));
	col = mix(col, upper, smoothstep(0.07, 0.34, up));
	col = mix(col, zenith, smoothstep(0.28, 0.95, up));

	// cirrus combed across the upper sky, stretched along the horizon and gilded toward the sun
	if (up > 0.05) {
		float cirrus = fbm(vec2(az * 2.4, up * 26.0) + vec2(fbm(vec2(az * 5.0, up * 9.0)) * 1.4, 0.0));
		float cm = smoothstep(0.52, 0.82, cirrus) * smoothstep(0.05, 0.22, up) * (1.0 - smoothstep(0.55, 0.95, up));
		vec3 cc = mix(vec3(1.0, 0.88, 0.94), vec3(1.0, 0.86, 0.66), pow(toward, 2.5));
		col = mix(col, cc, cm * 0.5);
	}

	// cloud banks heaped on the horizon: bright tops, lilac bellies, gold underlight toward the sun
	if (up > -0.04) {
		float bank = fbm(vec2(az * 3.0, up * 11.0)) + 0.4 * fbm(vec2(az * 8.0, up * 24.0));
		float h = 0.05 + 0.13 * fbm(vec2(az * 1.5, 4.0));
		float c = smoothstep(0.64, 0.92, bank + (h - up) * 2.4) * (1.0 - smoothstep(h + 0.02, h + 0.16, up));
		c *= smoothstep(-0.04, 0.02, up);
		vec3 cc2 = mix(vec3(0.86, 0.78, 0.96), vec3(1.0, 0.95, 0.92), smoothstep(0.0, 0.14, up));
		cc2 = mix(cc2, vec3(1.0, 0.80, 0.56), pow(toward, 2.0) * (1.0 - smoothstep(0.0, 0.1, up)) * 0.9);
		col = mix(col, cc2, c * 0.9);
	}

	// the sun: a big soft disc, a warm halo, a wide glow and a slow fan of rays
	float sd = clamp(dot(d, L), -1.0, 1.0);
	float sp = max(sd, 0.0);
	col += vec3(1.0, 0.95, 0.80) * smoothstep(0.9985, 0.9993, sd) * 5.0;
	col += vec3(1.0, 0.82, 0.58) * pow(sp, 160.0) * 1.1;
	col += vec3(1.0, 0.78, 0.60) * pow(sp, 14.0) * 0.30;
	vec3 ax = abs(L.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 u = cross(L, ax);
	u = u / max(length(u), 0.0001);
	vec3 v = cross(L, u);
	float th = atan(dot(d, v), dot(d, u));
	float rays = noise2(vec2(th * 5.0, 1.0)) * 0.6 + noise2(vec2(th * 13.0, 7.0)) * 0.4;
	col += vec3(1.0, 0.84, 0.62) * pow(sp, 5.0) * smoothstep(0.35, 0.9, rays) * 0.22;

	// below the horizon: a pink-lilac haze that meets the cloud sea
	col = mix(col, below, 1.0 - smoothstep(-0.16, 0.0, up));
	COLOR = max(col, vec3(0.0));
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
