class_name TempestSky
extends RefCounted
## Tempest Tower's sky: a hurricane in daylight. No sun disc - a low, ragged slate-grey cloud deck
## races overhead, brighter where the daylight soaks through thinner patches, darker in the rolling
## folds. On one side of the horizon the storm wall stands like a cliff of near-black cloud, its foot
## hung with curtains of rain; on the other, a sickly pale break glows low on the horizon. Below the
## horizon, grey rain haze over the city. Static (no TIME) so the radiance map is rendered once.
## Every term is bounded and NaN-safe: no pow() of a negative, no normalize() of a zero vector,
## smoothstep edges in order.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.2, 0.22, 0.26);
uniform vec3 deck : source_color = vec3(0.34, 0.37, 0.42);
uniform vec3 thin : source_color = vec3(0.62, 0.66, 0.7);
uniform vec3 wall : source_color = vec3(0.07, 0.08, 0.1);
uniform vec3 pale : source_color = vec3(0.78, 0.8, 0.72);
uniform vec3 haze : source_color = vec3(0.32, 0.35, 0.39);
uniform vec3 below : source_color = vec3(0.2, 0.22, 0.25);
uniform float wall_az = 2.3;
uniform float break_az = -0.9;

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
		p = p * 2.07 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	float az = atan(dh.y, dh.x);
	// how much this direction faces the storm wall / the pale break (0..1, soft)
	float ww = clamp(0.5 + 0.5 * cos(az - wall_az), 0.0, 1.0);
	ww = smoothstep(0.35, 0.95, ww);
	float wb = clamp(0.5 + 0.5 * cos(az - break_az), 0.0, 1.0);
	wb = smoothstep(0.6, 1.0, wb);
	// base: the cloud deck overhead into a pale grey horizon haze
	vec3 col = mix(haze, deck, smoothstep(0.0, 0.35, up));
	col = mix(col, zenith, smoothstep(0.35, 1.0, up));
	if (up > -0.05) {
		vec2 cp = d.xz / (up + 0.1);
		float c = fbm(cp * 0.6 + vec2(az * 0.2, 2.0));
		float c2 = fbm(cp * 2.2 + vec2(c * 3.0, 5.0));
		float folds = smoothstep(0.3, 0.85, c * 0.75 + c2 * 0.4);
		// thin patches where the daylight soaks through, dark rolling folds elsewhere
		col = mix(col * 0.72, mix(col, thin, 0.55), folds);
		// streaks of scud racing low under the deck
		float scud = smoothstep(0.55, 0.8, noise2(vec2(az * 9.0 + c * 4.0, up * 30.0)));
		col = mix(col, deck * 0.6, scud * 0.4 * (1.0 - smoothstep(0.05, 0.4, up)));
		// the storm wall: a cliff of near-black cloud rising from the horizon, ragged at the top
		float top = 0.12 + 0.28 * ww + 0.06 * (fbm(vec2(az * 3.0, 1.0)) - 0.5);
		float in_wall = (1.0 - smoothstep(top - 0.05, top + 0.03, up)) * ww;
		col = mix(col, wall * (0.8 + 0.4 * c2), in_wall * 0.92);
		// rain curtains hanging from it
		float curtain = noise2(vec2(az * 60.0, up * 3.0)) * (1.0 - smoothstep(0.0, top, up)) * ww;
		col = mix(col, haze * 0.7, curtain * 0.35);
		// the pale break low on the far horizon
		col += pale * wb * 0.35 * (1.0 - smoothstep(0.0, 0.12, up)) * smoothstep(-0.03, 0.02, up);
	}
	// below the horizon: rain haze over the city, darker toward the storm
	vec3 low = mix(below, below * 0.6, ww);
	col = mix(col, low, 1.0 - smoothstep(-0.12, 0.0, up));
	COLOR = clamp(col, vec3(0.0), vec3(2.0));
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
