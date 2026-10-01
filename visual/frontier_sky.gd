class_name FrontierSky
extends RefCounted
## Wild West Heist's sky: a desert sunset. A deep violet-blue zenith falling through dusty rose to a
## burning orange horizon, a HUGE low sun sitting just over the far mesas (its lower rim cut by their
## flat-topped silhouettes), long streaks of cloud lit pink and gold from beneath, a dusty haze along
## the horizon all the way round, and the first faint stars overhead. Static (no TIME), so the
## radiance map renders once. Every term is bounded and NaN-safe: pow() only of clamped values, no
## normalize() of a zero vector, smoothstep edges in order.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.12, 0.13, 0.34);
uniform vec3 upper : source_color = vec3(0.46, 0.32, 0.5);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.62, 0.26);
uniform vec3 horizon_far : source_color = vec3(0.9, 0.46, 0.34);
uniform vec3 mesa_col : source_color = vec3(0.26, 0.11, 0.12);
uniform vec3 below : source_color = vec3(0.32, 0.16, 0.12);
uniform float sun_size = 0.055;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash12(vec2(i, 1.7)), hash12(vec2(i + 1.0, 1.7)), f);
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

// height of the mesa skyline (in sky elevation, ~sin of the angle) at azimuth `az`
float skyline(float az) {
	float x = az * 9.0;
	// flat-topped mesas: blocky noise, steep sides
	float m = noise1(x * 0.6);
	float tops = smoothstep(0.45, 0.55, m) * (0.035 + 0.03 * noise1(x * 0.6 + 40.0));
	float buttes = smoothstep(0.62, 0.66, noise1(x * 2.1 + 9.0)) * 0.05 * noise1(x * 0.3 + 3.0);
	float low = 0.006 + 0.012 * noise1(x * 3.0);
	return max(max(tops, buttes), low);
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(-0.7, 0.18, -0.6));
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	vec2 lh = L.xz + vec2(0.0001);
	lh = lh / max(length(lh), 0.0001);
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	float tw2 = toward * toward;
	vec3 hor = mix(horizon_far, horizon_sun, tw2 * tw2);
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.32, up));
	col = mix(col, zenith, smoothstep(0.28, 0.85, up));
	// a band of glowing dust low along the horizon, hottest toward the sun
	col += vec3(1.0, 0.5, 0.2) * (1.0 - smoothstep(0.0, 0.12, abs(up - 0.02))) * (0.12 + 0.35 * tw2 * tw2);
	// the sun: a huge soft disc with a hot core, sitting on the mesas
	float sd = clamp(dot(d, L), -1.0, 1.0);
	float ang = acos(sd);
	float disc = 1.0 - smoothstep(sun_size * 0.94, sun_size, ang);
	vec3 sun_c = mix(vec3(1.6, 0.85, 0.35), vec3(2.2, 1.6, 0.8), 1.0 - smoothstep(0.0, sun_size, ang));
	col = mix(col, sun_c, disc);
	float halo = clamp(1.0 - ang / 0.6, 0.0, 1.0);
	col += vec3(1.0, 0.55, 0.22) * halo * halo * halo * 0.55;
	col += vec3(1.0, 0.7, 0.4) * clamp(1.0 - ang / 0.15, 0.0, 1.0) * 0.4;
	// long streaks of cloud lit from below: pink away from the sun, gold toward it
	if (up > 0.0) {
		vec2 cp = d.xz / (up + 0.12);
		float s = fbm(vec2(cp.x * 0.35, cp.y * 2.4) + vec2(4.0, 1.0));
		float c = smoothstep(0.58, 0.8, s) * smoothstep(0.02, 0.1, up) * (1.0 - smoothstep(0.35, 0.7, up));
		vec3 cc = mix(vec3(0.95, 0.5, 0.55), vec3(1.0, 0.72, 0.4), tw2);
		cc = mix(cc, vec3(0.35, 0.22, 0.4), smoothstep(0.25, 0.6, up));
		col = mix(col, cc, c * 0.8);
		// first stars, faint, high up
		vec2 sc = d.xz / (up + 0.001) * 70.0;
		vec2 cell = floor(sc);
		vec2 f = fract(sc) - 0.5;
		float star = (1.0 - smoothstep(0.0, 0.1, length(f))) * step(0.988, hash12(cell));
		col += vec3(1.0, 0.95, 0.9) * star * 0.5 * smoothstep(0.45, 0.8, up) * (1.0 - tw2);
	}
	// the mesa skyline all round, hazy blue-purple with distance, in front of the sun
	float az = atan(dh.y, dh.x);
	float sk = skyline(az);
	float m = 1.0 - smoothstep(sk - 0.002, sk + 0.002, up);
	vec3 mc = mix(mesa_col, hor * 0.55, 0.35 + 0.3 * (1.0 - tw2));
	col = mix(col, mc, m * smoothstep(-0.2, -0.0, up));
	// below the horizon: the dusty desert floor in shadow
	col = mix(col, below, 1.0 - smoothstep(-0.08, 0.0, up));
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
