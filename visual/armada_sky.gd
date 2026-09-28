class_name ArmadaSky
extends RefCounted
## Storm Armada's sky: a thunderstorm high above the clouds at sunset. A low, heavy storm deck
## rolls overhead (dark slate blue, lumpy, lit from underneath where the sunset catches it),
## and far ahead, low in the west, the sunset breaks through a long gap between the storm deck
## and the cloud sea below - a band of molten gold and rose with shafts of light fanning up
## through the ragged cloud edge. Behind you the storm is darkest. Below the horizon: the
## cloud tops. Static (no TIME), so the radiance map renders once; the lightning, the rain and the
## moving cloud sea are separate effects.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.05, 0.07, 0.11);
uniform vec3 deck : source_color = vec3(0.16, 0.19, 0.26);
uniform vec3 deck_lit : source_color = vec3(0.62, 0.36, 0.26);
uniform vec3 gap_hot : source_color = vec3(1.0, 0.62, 0.28);
uniform vec3 gap_rose : source_color = vec3(0.86, 0.42, 0.42);
uniform vec3 far_storm : source_color = vec3(0.11, 0.13, 0.19);
uniform vec3 sea_top : source_color = vec3(0.3, 0.32, 0.4);
uniform vec3 sea_low : source_color = vec3(0.08, 0.09, 0.13);

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
	for (int i = 0; i < 6; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	// LIGHT0 can be unset (zero) while the radiance map is first baked: never normalize a zero vector
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.05, 0.2, -0.98));
	float up = d.y;
	vec2 dh = normalize(d.xz + vec2(0.0001, 0.0));
	vec2 lh = normalize(L.xz + vec2(0.0001, 0.0));
	// 1 toward the sunset, 0 straight behind (clamped: rounding can push the dot past -1 and pow() of a negative is NaN)
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	float sunward = pow(toward, 5.0);
	// the storm deck overhead: lumpy mammatus-like cloud seen from below, projected on a low ceiling
	float h = max(up, 0.0);
	vec2 cp = d.xz / (h + 0.08);
	float c1 = fbm(cp * 0.55);
	float c2 = fbm(cp * 1.6 + vec2(c1 * 2.0, 0.0));
	float lumps = clamp(c1 * 0.65 + c2 * 0.5, 0.0, 1.0);
	vec3 storm = mix(deck * 0.6, deck, lumps);
	// sunset light catching the underside of the deck near the horizon, strongest toward the sun
	float under = (1.0 - smoothstep(0.0, 0.45, h)) * sunward;
	storm = mix(storm, deck_lit * (0.55 + 0.6 * lumps), under * 0.85);
	storm = mix(storm, zenith, smoothstep(0.35, 0.95, h));
	// the far side of the storm, behind you: darker still
	storm = mix(storm, far_storm, (1.0 - toward) * 0.5 * (1.0 - smoothstep(0.0, 0.5, h)));
	// the gap: a band of open sky between the cloud deck (ragged lower edge) and the cloud sea
	float edge = 0.055 + 0.05 * fbm(dh * 5.0 + vec2(0.5, 3.1)) - 0.02 * sunward;
	float gap = (1.0 - smoothstep(edge - 0.03, edge + 0.02, up)) * smoothstep(-0.03, 0.005, up);
	vec3 open = mix(gap_rose, gap_hot, clamp(sunward * 1.4, 0.0, 1.0)) * (0.35 + 1.4 * sunward);
	open = mix(open, open * 1.6 + vec3(0.25, 0.12, 0.0), smoothstep(-0.01, 0.03, up) * (1.0 - smoothstep(0.03, 0.06, up)) * sunward);
	vec3 col = mix(storm, open, gap * (0.25 + 0.75 * smoothstep(0.1, 0.8, toward)));
	// shafts of light fanning up through the deck's edge above the sun
	float ang = atan(dh.x * lh.y - dh.y * lh.x, dot(dh, lh));
	float rays = pow(clamp(noise2(vec2(ang * 22.0, 3.0)), 0.0, 1.0), 3.0);
	col += gap_hot * rays * sunward * 0.3 * smoothstep(0.02, 0.1, up) * (1.0 - smoothstep(0.1, 0.35, up));
	// the sun itself, low and swollen, half behind the cloud-sea's rim
	float sd = clamp(dot(d, L), -1.0, 1.0);
	col += vec3(1.0, 0.8, 0.5) * smoothstep(0.9994, 0.9997, sd) * 12.0 * smoothstep(-0.01, 0.01, up + 0.004);
	col += vec3(1.0, 0.6, 0.3) * pow(max(sd, 0.0), 400.0) * 2.5;
	col += vec3(1.0, 0.55, 0.28) * pow(max(sd, 0.0), 12.0) * 0.4 * (1.0 - smoothstep(0.1, 0.4, h));
	// below the horizon: the tops of the cloud sea, lit gold toward the sun
	float down = clamp(-up, 0.0, 1.0);
	vec2 sp = d.xz / (down + 0.05);
	float tops = fbm(sp * 0.4);
	vec3 sea = mix(sea_low, sea_top, clamp(tops * 1.2 - down * 1.5, 0.0, 1.0));
	sea = mix(sea, gap_hot * 0.8, sunward * (1.0 - smoothstep(0.0, 0.2, down)) * 0.6 * tops);
	col = mix(col, sea, smoothstep(0.0, 0.02, down));
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
