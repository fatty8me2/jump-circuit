class_name JungleSky
extends RefCounted
## Jungle Temple's sky: a humid tropical afternoon. A deep teal-blue zenith paling to a warm, misty
## cream-green at the horizon, towering cumulus banks along the horizon lit gold on top and blue-grey
## underneath, a soft haze band where the forest steams, and a bright high sun with a wide glare.
## Static (no TIME) so the radiance map is only rendered once.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.2, 0.43, 0.62);
uniform vec3 upper : source_color = vec3(0.47, 0.66, 0.76);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 horizon_far : source_color = vec3(0.78, 0.86, 0.78);
uniform vec3 haze : source_color = vec3(0.8, 0.87, 0.76);
uniform vec3 ground : source_color = vec3(0.2, 0.3, 0.2);

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
	// LIGHT0 can be unset (zero) when the radiance map is first baked: never normalize a zero vector
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.3, 0.75, 0.55));
	float up = d.y;
	vec2 dh = normalize(d.xz + vec2(0.0001));
	vec2 lh = normalize(L.xz + vec2(0.0001));
	// clamped: a dot a hair past -1 would make pow() return NaN, and a NaN sky blacks out the level
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 hor = mix(horizon_far, horizon_sun, pow(toward, 2.0));
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.3, up));
	col = mix(col, zenith, smoothstep(0.25, 0.9, up));
	// the forest steaming: a haze band on the horizon
	float band = exp(-abs(up) * 12.0);
	col = mix(col, haze * (0.9 + 0.2 * toward), band * 0.7);
	// cumulus banks: billowing tops near the horizon, thinning upward
	if (up > -0.02) {
		// (dh is never zero, so atan never sees (0, 0) straight up)
		float az = atan(dh.y, dh.x);
		vec2 cp = vec2(az * 3.2, up * 9.0);
		float tower = fbm(vec2(cp.x, 0.0) * 0.8) * 0.32 + 0.04;
		float body = fbm(cp * vec2(1.0, 1.6) + vec2(0.0, -up * 4.0));
		float c = smoothstep(0.42, 0.6, body) * (1.0 - smoothstep(tower * 0.65, tower, up)) * smoothstep(-0.02, 0.03, up);
		float lit = smoothstep(0.0, 0.25, up / max(tower, 0.01)) * 0.6 + 0.4 * toward;
		vec3 cc = mix(vec3(0.58, 0.66, 0.72), mix(vec3(1.0, 0.98, 0.94), vec3(1.0, 0.9, 0.72), toward), clamp(lit, 0.0, 1.0));
		col = mix(col, cc, c * 0.92);
		// wisps high up
		vec2 wp = d.xz / (up + 0.15);
		float wisp = smoothstep(0.58, 0.82, fbm(wp * 0.5 + vec2(0.0, 7.0))) * smoothstep(0.15, 0.4, up) * (1.0 - smoothstep(0.75, 0.98, up));
		col = mix(col, vec3(0.98, 0.98, 0.95), wisp * 0.4);
	}
	// the sun: a white disc, a tight glare and a wide warm bloom (kept bounded)
	float sd = dot(d, L);
	col += vec3(1.0, 0.97, 0.88) * smoothstep(0.9996, 0.99978, sd) * 18.0;
	col += vec3(1.0, 0.9, 0.7) * pow(max(sd, 0.0), 600.0) * 3.0;
	col += vec3(1.0, 0.88, 0.62) * pow(max(sd, 0.0), 18.0) * 0.28;
	// below the horizon: the misty forest floor far away
	col = mix(col, mix(haze, ground, 1.0 - smoothstep(-0.35, 0.0, up)), 1.0 - smoothstep(-0.03, 0.0, up));
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
