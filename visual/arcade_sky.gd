class_name ArcadeSky
extends RefCounted
## Pixel Panic's sky: the inside of the cabinet's glass. A deep indigo dome posterised into hard
## bands, a field of square pixel stars (quantised in angle, so they are chunky blocks), three giant
## space-invader sprites marching across it, a posterised yellow coin-moon, CRT scanlines over everything
## and a banded magenta / cyan phosphor glow along the horizon. Below the horizon: black.
## Static (no TIME), so the radiance map renders once. Every term is bounded and NaN-safe: no pow(),
## no normalize() of a zero vector, smoothstep edges in order, divisions guarded.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.01, 0.0, 0.05);
uniform vec3 mid : source_color = vec3(0.05, 0.02, 0.16);
uniform vec3 glow_a : source_color = vec3(1.0, 0.2, 0.7);
uniform vec3 glow_b : source_color = vec3(0.1, 0.9, 1.0);
uniform vec3 moon_dir = vec3(-0.45, 0.42, -0.78);

const int INVADER[8] = int[8](0x42, 0x81, 0x5A, 0xFF, 0xDB, 0x7E, 0x3C, 0x18);

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sprite(vec2 q) {
	// q in sprite cells: 8 wide, 8 tall
	if (q.x < 0.0 || q.y < 0.0 || q.x >= 8.0 || q.y >= 8.0) {
		return 0.0;
	}
	int cx = int(floor(q.x));
	int ry = int(floor(q.y));
	int row = INVADER[ry];
	return float((row >> cx) & 1);
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	float up = clamp(d.y, -1.0, 1.0);
	// posterised dome: five hard steps
	float k = floor(clamp(up, 0.0, 1.0) * 5.0) / 5.0;
	vec3 col = mix(mid, zenith, k);
	// the phosphor glow along the horizon, in hard bands
	float band = clamp(1.0 - up * 4.0, 0.0, 1.0);
	band = floor(band * 5.0) / 5.0;
	float az = atan(d.z, d.x);
	vec3 gc = mix(glow_a, glow_b, step(0.0, sin(az * 3.0)));
	col += gc * band * 0.35;
	// chunky pixel stars: quantise the direction into cells
	vec2 g = vec2(az * 38.0, up * 60.0);
	vec2 cell = floor(g);
	float s = h21(cell);
	float star = step(0.985, s) * step(0.02, up);
	vec3 sc = mix(vec3(1.0, 0.95, 0.5), mix(glow_b, glow_a, step(0.5, h21(cell + 7.0))), step(0.5, h21(cell + 3.0)));
	col += sc * star * (0.6 + 0.8 * h21(cell + 11.0));
	// three marching invaders: sprite cells are 0.045 rad
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float a0 = -0.9 + fi * 2.3;
		float u0 = 0.38 + 0.09 * fi;
		vec2 q = vec2((az - a0) / 0.045 + 4.0, (up - u0) / 0.045 + 4.0);
		float on = sprite(q);
		vec3 ic = mix(glow_b, glow_a, step(0.5, fi - 0.5));
		col = mix(col, ic * 0.55, on * 0.85);
	}
	// the coin-moon
	vec3 m = moon_dir / max(length(moon_dir), 0.0001);
	float md = clamp(dot(d, m), -1.0, 1.0);
	float ang = acos(md);
	float disc = 1.0 - smoothstep(0.17, 0.171, ang);
	float shade = floor(clamp(md, 0.0, 1.0) * 40.0) / 40.0;
	vec3 moon = mix(vec3(1.0, 0.55, 0.1), vec3(1.0, 0.95, 0.35), clamp((shade - 0.985) * 60.0, 0.0, 1.0));
	col = mix(col, moon, disc);
	col += vec3(1.0, 0.7, 0.2) * (1.0 - smoothstep(0.17, 0.4, ang)) * 0.1;
	// CRT scanlines over everything above the horizon
	float scan = step(0.5, fract(up * 90.0));
	col *= 0.82 + 0.18 * scan;
	col = mix(col, vec3(0.0), 1.0 - smoothstep(-0.2, 0.0, up));
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
