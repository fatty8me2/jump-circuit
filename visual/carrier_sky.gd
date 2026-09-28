class_name CarrierSky
extends RefCounted
## Super Carrier's sky: a bright day at sea. A deep blue zenith paling to a hazy white-blue horizon,
## a hot white sun with a soft glare, fair-weather cumulus in rows with flat grey-blue bases and
## sunlit tops, a thin veil of high cirrus, and below the horizon the dark blue of the open ocean.
## Static (no TIME) so the radiance map is only rendered once. NaN-safe: every pow() argument is
## clamped and nothing normalizes a vector that can be zero.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.12, 0.32, 0.72);
uniform vec3 upper : source_color = vec3(0.34, 0.56, 0.88);
uniform vec3 horizon : source_color = vec3(0.78, 0.86, 0.94);
uniform vec3 sea : source_color = vec3(0.05, 0.16, 0.28);

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
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.4, 0.62, 0.66));
	float up = d.y;
	float sd = clamp(dot(d, L), -1.0, 1.0);
	float toward = clamp(sd * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(horizon, upper, smoothstep(0.0, 0.25, up));
	col = mix(col, zenith, smoothstep(0.18, 0.9, up));
	// the horizon haze is brighter toward the sun
	col += vec3(0.1, 0.08, 0.05) * pow(toward, 6.0) * (1.0 - smoothstep(0.0, 0.35, up));
	// cumulus: puffy rows, flat grey-blue bases, bright tops toward the sun
	if (up > 0.0) {
		vec2 cp = d.xz / (up + 0.08);
		float n = fbm(cp * 0.55 + vec2(3.0, 1.0));
		float cover = smoothstep(0.54, 0.74, n) * smoothstep(0.015, 0.1, up) * (1.0 - smoothstep(0.45, 0.8, up));
		float shade = clamp(fbm(cp * 0.55 + vec2(3.2, 0.7)) - n + 0.5, 0.0, 1.0);
		vec3 lit = mix(vec3(0.72, 0.76, 0.84), vec3(1.0, 0.99, 0.96), shade);
		lit += vec3(0.15, 0.12, 0.08) * pow(toward, 4.0);
		col = mix(col, lit, cover * 0.92);
		// high cirrus veil
		float ci = smoothstep(0.55, 0.8, fbm(vec2(cp.x * 0.25 + cp.y * 0.1, cp.y * 0.9) * 0.6 + vec2(11.0, 4.0)));
		col = mix(col, vec3(0.95, 0.97, 1.0), ci * 0.25 * smoothstep(0.1, 0.4, up));
	}
	// the sun: disc, tight glare, wide soft bloom
	col += vec3(1.0, 0.97, 0.9) * smoothstep(0.99955, 0.99975, sd) * 26.0;
	col += vec3(1.0, 0.95, 0.85) * pow(max(sd, 0.0), 900.0) * 3.0;
	col += vec3(1.0, 0.92, 0.8) * pow(max(sd, 0.0), 28.0) * 0.28;
	col += vec3(0.9, 0.92, 1.0) * pow(max(sd, 0.0), 5.0) * 0.08;
	// below the horizon: the open sea, with the haze sitting on it
	float below = 1.0 - smoothstep(-0.02, 0.0, up);
	vec3 water = mix(horizon * 0.8, sea, smoothstep(-0.2, -0.01, -up) );
	col = mix(col, water, below);
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
