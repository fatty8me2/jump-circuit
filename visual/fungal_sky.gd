class_name FungalSky
extends RefCounted
## Mushroom Hollow's sky: a warm, sunny storybook afternoon seen through the leaves. A clear
## cerulean overhead warming through a pale aqua into a creamy gold at the horizon, fat white
## cumulus (lit gold on the sun side, soft lilac-grey underneath) heaped along the horizon with
## wisps higher up, a big soft sun with a warm halo, and, low all round the horizon, a ragged dark-green
## fringe of far treetops and giant leaves so the world reads as a forest floor. Not night, not
## alien: a picture-book day. Static (no TIME), so the radiance map is rendered once. Every term is
## bounded and NaN-safe: pow() only of clamped values, no normalize() of a zero vector, smoothstep
## edges in order, divisions guarded.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.27, 0.55, 0.9);
uniform vec3 upper : source_color = vec3(0.52, 0.78, 0.95);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.9, 0.62);
uniform vec3 horizon_far : source_color = vec3(0.86, 0.92, 0.78);
uniform vec3 below : source_color = vec3(0.4, 0.55, 0.28);
uniform vec3 canopy : source_color = vec3(0.2, 0.36, 0.14);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
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
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.4, 0.5, 0.6));
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	vec2 lh = L.xz + vec2(0.0001);
	lh = lh / max(length(lh), 0.0001);
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 hor = mix(horizon_far, horizon_sun, pow(toward, 1.6));
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.28, up));
	col = mix(col, zenith, smoothstep(0.22, 0.95, up));
	float az = atan(dh.y, dh.x);
	if (up > -0.05) {
		// fat cumulus banks heaped along the horizon
		float bank = fbm(vec2(az * 3.0, up * 8.0)) + 0.35 * fbm(vec2(az * 8.0, up * 19.0));
		float h = 0.1 + 0.2 * fbm(vec2(az * 1.5, 4.0));
		float c = smoothstep(0.6, 0.88, bank + (h - up) * 2.0) * (1.0 - smoothstep(h + 0.02, h + 0.22, up));
		c *= smoothstep(-0.05, 0.03, up);
		vec3 cc = mix(vec3(0.82, 0.84, 0.92), vec3(1.0, 0.99, 0.95), smoothstep(0.0, 0.25, up - 0.02 + fbm(vec2(az * 5.0, 2.0)) * 0.1));
		cc = mix(cc, vec3(1.0, 0.92, 0.68), pow(toward, 3.0) * 0.5);
		col = mix(col, cc, c * 0.94);
		// wisps and small puffs higher up
		if (up > 0.0) {
			vec2 cp = d.xz / (up + 0.2);
			float w = fbm(cp * 0.8 + vec2(2.0, 5.0));
			float wc = smoothstep(0.56, 0.78, w) * smoothstep(0.06, 0.28, up) * (1.0 - smoothstep(0.55, 0.95, up));
			col = mix(col, vec3(1.0, 0.99, 0.96), wc * 0.65);
		}
	}
	// the sun: a soft bright disc, a warm halo and a wide golden haze
	float sd = clamp(dot(d, L), -1.0, 1.0);
	float sp = max(sd, 0.0);
	col += vec3(1.0, 0.96, 0.8) * smoothstep(0.9993, 0.9997, sd) * 7.0;
	col += vec3(1.0, 0.88, 0.62) * pow(sp, 450.0) * 1.5;
	col += vec3(1.0, 0.82, 0.5) * pow(sp, 14.0) * 0.28;
	// a ragged fringe of far treetops and leaves all round the horizon
	float fringe_h = 0.045 + 0.075 * fbm(vec2(az * 6.0, 11.0)) + 0.03 * noise2(vec2(az * 40.0, 3.0));
	float fr = 1.0 - smoothstep(fringe_h - 0.012, fringe_h, up);
	vec3 leafcol = mix(canopy, canopy * 1.7 + vec3(0.05, 0.08, 0.0), smoothstep(0.0, fringe_h, up));
	leafcol = mix(leafcol, horizon_far, 0.28);
	col = mix(col, leafcol, fr * 0.92);
	// below the horizon: the green haze of the forest floor
	col = mix(col, below, 1.0 - smoothstep(-0.14, -0.01, up));
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
