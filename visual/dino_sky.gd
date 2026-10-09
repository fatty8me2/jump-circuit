class_name DinoSky
extends RefCounted
## Dino Valley's sky: a warm, clear prehistoric morning. Deep blue overhead warming through turquoise to
## a gold haze at the horizon, a big sun with a wide glare, towering cumulus banks, high wisps - and three
## layers of hazy blue mountain ridges around the whole horizon, so wherever the course turns there is
## depth. (The smoking volcano is a real mesh, visual/dino_volcano.gd.) Static (no TIME), so the radiance
## map is only rendered once. Every normalize / atan is guarded: a NaN sky blacks the level out.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.16, 0.38, 0.78);
uniform vec3 upper : source_color = vec3(0.42, 0.7, 0.9);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.86, 0.6);
uniform vec3 horizon_far : source_color = vec3(0.8, 0.88, 0.84);
uniform vec3 haze : source_color = vec3(0.86, 0.88, 0.74);

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

// ridge height (in sky-up units) of a mountain layer at azimuth az; the seam at +-PI is hidden by
// sampling the noise on a circle
float ridge(float az, float seed, float base, float amp) {
	vec2 c = vec2(cos(az), sin(az)) * 2.2;
	return base + amp * fbm(c + vec2(seed, seed * 0.7));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.5, 0.55, 0.65));
	float up = d.y;
	vec2 dh = normalize(d.xz + vec2(0.0001, 0.0));
	vec2 lh = normalize(L.xz + vec2(0.0001, 0.0));
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 hor = mix(horizon_far, horizon_sun, toward * toward);
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.28, up));
	col = mix(col, zenith, smoothstep(0.22, 0.85, up));
	float band = exp(-abs(up) * 9.0);
	col = mix(col, haze * (0.92 + 0.15 * toward), band * 0.55);
	float az = atan(dh.y, dh.x);
	if (up > -0.02) {
		// cumulus banks, thinning upward
		vec2 cp = vec2(az * 3.0, up * 9.0);
		float tower = fbm(vec2(cp.x, 0.0) * 0.8 + 4.0) * 0.34 + 0.06;
		float body = fbm(cp * vec2(1.0, 1.6) + vec2(0.0, -up * 4.0));
		float c = smoothstep(0.43, 0.62, body) * (1.0 - smoothstep(tower * 0.65, tower, up)) * smoothstep(0.02, 0.07, up);
		float lit = smoothstep(0.0, 0.3, up / max(tower, 0.01)) * 0.55 + 0.45 * toward;
		vec3 cc = mix(vec3(0.62, 0.7, 0.8), mix(vec3(1.0, 0.99, 0.95), vec3(1.0, 0.9, 0.72), toward), clamp(lit, 0.0, 1.0));
		col = mix(col, cc, c * 0.9);
		vec2 wp = d.xz / (up + 0.18);
		float wisp = smoothstep(0.55, 0.82, fbm(wp * 0.45 + vec2(0.0, 9.0))) * smoothstep(0.18, 0.45, up) * (1.0 - smoothstep(0.78, 0.98, up));
		col = mix(col, vec3(0.99, 0.98, 0.94), wisp * 0.4);
	}
	// three hazy ridgelines: the far one palest, the near one deepest
	float r3 = ridge(az, 11.0, 0.02, 0.07);
	float r2 = ridge(az, 5.0, 0.012, 0.055);
	float r1 = ridge(az, 1.0, 0.004, 0.04);
	vec3 far_c = mix(vec3(0.62, 0.72, 0.8), haze, 0.35);
	vec3 mid_c = mix(vec3(0.42, 0.58, 0.58), haze, 0.22);
	vec3 near_c = vec3(0.26, 0.42, 0.28);
	col = mix(col, far_c, (1.0 - smoothstep(r3 - 0.004, r3, up)) * step(-0.05, up));
	col = mix(col, mid_c, (1.0 - smoothstep(r2 - 0.004, r2, up)) * step(-0.05, up));
	col = mix(col, near_c, (1.0 - smoothstep(r1 - 0.004, r1, up)) * step(-0.05, up));
	// the sun: a disc, a tight glare and a wide warm bloom (bounded)
	float sd = dot(d, L);
	col += vec3(1.0, 0.97, 0.86) * smoothstep(0.9995, 0.99975, sd) * 16.0;
	col += vec3(1.0, 0.9, 0.7) * pow(max(sd, 0.0), 500.0) * 3.0;
	col += vec3(1.0, 0.88, 0.62) * pow(max(sd, 0.0), 14.0) * 0.3;
	// below the horizon: the misty valley floor, far away
	col = mix(col, mix(haze, vec3(0.34, 0.44, 0.26), 1.0 - smoothstep(-0.4, 0.0, up)), 1.0 - smoothstep(-0.05, -0.0, up));
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
