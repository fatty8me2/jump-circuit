shader_type spatial;
// Neon City building skin (near towers under the rooftops and the far skyline alike): dark wet
// concrete and glass in floors of `floor_h` metres, a grid of windows of which a seeded share are
// lit - warm sodium amber, cool teal office light, the odd hot-pink apartment - with blinds and
// shadows breaking them up, and wet vertical streaks. Roof faces are dark tar. Everything is in
// WORLD space, so any box (or MultiMesh instance) can share the one material. Emission bounded.

uniform vec3 wall : source_color = vec3(0.07, 0.065, 0.09);
uniform vec3 lit_a : source_color = vec3(1.0, 0.66, 0.3);
uniform vec3 lit_b : source_color = vec3(0.35, 0.9, 0.95);
uniform vec3 lit_c : source_color = vec3(1.0, 0.35, 0.7);
uniform float floor_h = 3.4;
uniform float bay = 2.2;
uniform float lit_share = 0.38;
uniform float glow = 1.6;

varying vec3 wp;
varying vec3 wn;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 n = wn / max(length(wn), 0.0001);
	vec3 col = wall;
	vec3 emit = vec3(0.0);
	float rough = 0.35;
	if (abs(n.y) > 0.6) {
		col = wall * 0.7;
		rough = 0.5;
	} else {
		float u = abs(n.x) > abs(n.z) ? wp.z : wp.x;
		float side_seed = abs(n.x) > abs(n.z) ? (n.x > 0.0 ? 1.0 : 2.0) : (n.z > 0.0 ? 3.0 : 4.0);
		vec2 cell = vec2(floor(u / bay), floor(wp.y / floor_h));
		vec2 f = vec2(fract(u / bay), fract(wp.y / floor_h));
		float win = step(0.14, f.x) * step(f.x, 0.86) * step(0.22, f.y) * step(f.y, 0.82);
		float s = hash12(cell + side_seed * 17.0);
		// lit windows cluster by floor (whole offices on), with scattered single ones
		float floor_on = hash12(vec2(cell.y, side_seed + floor(u / (bay * 7.0))));
		float on = step(1.0 - lit_share, mix(s, floor_on, 0.55));
		float pick = hash12(cell * 1.7 + 4.0);
		vec3 lc = pick < 0.55 ? lit_a : (pick < 0.88 ? lit_b : lit_c);
		// blinds: some lit windows half shaded
		float blind = step(0.7, hash12(cell + 9.0)) * step(f.y, 0.5);
		float inten = (0.55 + 0.45 * hash12(cell + 2.0)) * (1.0 - 0.7 * blind);
		vec3 glass = mix(vec3(0.03, 0.035, 0.05), vec3(0.06, 0.05, 0.08), hash12(cell + 5.0));
		col = mix(col, glass, win);
		emit = lc * inten * on * win * glow;
		rough = mix(0.45, 0.08, win);
		// wet streaks down the concrete
		float streak = hash12(vec2(floor(u * 3.0), side_seed));
		col *= mix(1.0, 0.75, step(0.7, streak) * (1.0 - win));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.1;
	EMISSION = clamp(emit, vec3(0.0), vec3(3.0));
}
