shader_type spatial;
// Tempest Tower curtain wall (the tower's finished floors and the far skyscrapers alike): storm-grey
// glass in floors of `floor_h` metres, a grid of slim aluminium mullions, a dark spandrel band at
// each floor, a seeded share of panes showing cool office light through the gloom, and sheets of
// rain running down the glass. Roof faces are wet concrete. Everything is in WORLD space, so any box
// (or MultiMesh instance) can share the one material. Emission bounded; no pow, no normalize of zero.

uniform vec3 glass_a : source_color = vec3(0.16, 0.2, 0.25);
uniform vec3 glass_b : source_color = vec3(0.26, 0.31, 0.36);
uniform vec3 frame : source_color = vec3(0.55, 0.57, 0.6);
uniform vec3 spandrel : source_color = vec3(0.1, 0.11, 0.13);
uniform vec3 roof : source_color = vec3(0.36, 0.37, 0.38);
uniform vec3 office : source_color = vec3(0.85, 0.92, 1.0);
uniform float floor_h = 4.0;
uniform float bay = 1.5;
uniform float lit_share = 0.18;
uniform float glow = 0.55;
uniform float rain = 1.0;

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
	vec3 col = roof;
	vec3 emit = vec3(0.0);
	float rough = 0.7;
	float metal = 0.1;
	if (abs(n.y) > 0.6) {
		// wet concrete roof: puddle sheen in patches
		float p = hash12(floor(wp.xz * 0.25));
		rough = mix(0.75, 0.25, step(0.6, p));
		col = roof * (0.85 + 0.15 * p);
	} else {
		float u = abs(n.x) > abs(n.z) ? wp.z : wp.x;
		float side_seed = abs(n.x) > abs(n.z) ? (n.x > 0.0 ? 1.0 : 2.0) : (n.z > 0.0 ? 3.0 : 4.0);
		vec2 cell = vec2(floor(u / bay), floor(wp.y / floor_h));
		vec2 f = vec2(fract(u / bay), fract(wp.y / floor_h));
		float mull = 1.0 - step(0.05, f.x) * step(f.x, 0.95);
		float band = 1.0 - step(0.16, f.y);
		float s = hash12(cell + side_seed * 17.0);
		vec3 glass = mix(glass_a, glass_b, hash12(cell * 0.5 + side_seed));
		// office light through the panes (whole floors on, the odd pane alone)
		float floor_on = hash12(vec2(cell.y, side_seed + floor(u / (bay * 9.0))));
		float on = step(1.0 - lit_share, mix(s, floor_on, 0.6));
		// rain sheets running down the glass
		float lane = hash12(vec2(floor(u * 6.0), side_seed));
		float run = fract(wp.y * 0.35 + TIME * (0.6 + lane * 0.9) + lane * 7.0);
		float sheet = smoothstep(0.75, 1.0, run) * step(0.55, lane) * rain;
		col = glass * (1.0 + 0.35 * sheet);
		col = mix(col, spandrel, band);
		col = mix(col, frame, mull);
		emit = office * on * (1.0 - band) * (1.0 - mull) * glow * (0.6 + 0.4 * hash12(cell + 3.0));
		rough = mix(0.06 + 0.1 * sheet, 0.45, max(band, mull));
		metal = mix(0.65, 0.4, max(band, mull));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = clamp(emit, vec3(0.0), vec3(2.0));
}
