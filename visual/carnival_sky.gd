class_name CarnivalSky
extends RefCounted
## Carnival Chaos's sky: a funfair sunset. A deep indigo zenith with the first stars, melting through
## violet and magenta into a blazing orange-and-gold horizon where a fat low sun is half sunk; long
## streaky clouds lit rose underneath and gold on top; a slow warm glow round the sun. Below the horizon
## a plum-brown haze (the fairground's glow lights it from underneath). Static (no TIME), so the radiance
## map is rendered once. Every term is bounded and NaN-safe: pow() only of clamped values, no normalize()
## of a zero vector, smoothstep edges in order, divisions guarded.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.07, 0.05, 0.22);
uniform vec3 upper : source_color = vec3(0.30, 0.14, 0.45);
uniform vec3 mid : source_color = vec3(0.82, 0.30, 0.48);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.62, 0.22);
uniform vec3 horizon_far : source_color = vec3(0.95, 0.42, 0.45);
uniform vec3 below : source_color = vec3(0.26, 0.10, 0.16);

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
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	vec3 L = vec3(0.5, 0.12, -0.85);
	if (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) {
		L = normalize(LIGHT0_DIRECTION);
	}
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	vec2 lh = L.xz + vec2(0.0001);
	lh = lh / max(length(lh), 0.0001);
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	float az = atan(dh.y, dh.x);
	// the dome: indigo overhead, violet, magenta, then a horizon that burns orange toward the sun
	vec3 col = mix(upper, zenith, smoothstep(0.25, 0.95, up));
	col = mix(mid, col, smoothstep(0.02, 0.45, up));
	vec3 hor = mix(horizon_far, horizon_sun, toward * toward);
	col = mix(col, hor, 1.0 - smoothstep(0.0, 0.2 + 0.1 * toward, up));
	// first stars up high
	if (up > 0.35) {
		vec2 sp = d.xz / (up + 0.4) * 60.0;
		float h = hash12(floor(sp));
		float tw = step(0.992, h) * (1.0 - smoothstep(0.0, 0.35, length(fract(sp) - 0.5)));
		col += vec3(1.0, 0.95, 0.85) * tw * smoothstep(0.35, 0.7, up) * 1.2;
	}
	// long streaky clouds: stretched along the horizon, gold on the sunward side, rose underneath
	if (up > 0.0) {
		vec2 cp = vec2(az * 2.6, up * 9.0);
		float cl = fbm(cp * vec2(0.7, 1.7) + vec2(4.0, 1.0));
		float cover = smoothstep(0.52, 0.78, cl) * smoothstep(0.0, 0.08, up) * (1.0 - smoothstep(0.35, 0.65, up));
		vec3 lit = mix(vec3(0.95, 0.38, 0.5), vec3(1.0, 0.78, 0.4), toward);
		vec3 shade = mix(vec3(0.35, 0.14, 0.34), vec3(0.62, 0.24, 0.3), toward);
		float edge = smoothstep(0.0, 0.12, fbm(cp * vec2(0.7, 1.7) + vec2(4.0, 1.0) + vec2(0.0, 0.6)) - cl + 0.1);
		col = mix(col, mix(shade, lit, edge), cover * 0.85);
	}
	// the sun: a fat disc, half sunk, in a wide warm glow
	float sd = clamp(dot(d, L), -1.0, 1.0);
	float disc = smoothstep(0.9965, 0.9985, sd);
	float glow = pow(max(sd, 0.0), 18.0);
	float wide = pow(max(sd, 0.0), 4.0);
	col += vec3(1.0, 0.55, 0.2) * glow * 0.9 + vec3(1.0, 0.4, 0.3) * wide * 0.25;
	col = mix(col, vec3(1.0, 0.9, 0.62) * 2.0, disc * smoothstep(-0.02, 0.01, up + 0.012));
	// below the horizon: a warm plum haze, lit from underneath by the fairground
	col = mix(col, below, 1.0 - smoothstep(-0.3, 0.0, up));
	col += vec3(1.0, 0.55, 0.25) * (1.0 - smoothstep(0.0, 0.18, abs(up + 0.04))) * 0.25 * toward;
	COLOR = clamp(col, vec3(0.0), vec3(4.0));
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
