shader_type spatial;
render_mode cull_disabled;
// Tempest Tower's unfinished floors: the bare steel skeleton. On any box, every face is cut away
// except the steel - columns every `bay` metres, an edge beam at every floor, X-bracing in a seeded
// share of the bays and a yellow edge-protection rail a metre above each floor - so you see right
// through the frame to the slabs and the storm behind. Red-oxide primer with grey galvanised
// bracing. WORLD space, so one material serves every frame box. Top and bottom faces are open.

uniform vec3 primer : source_color = vec3(0.5, 0.2, 0.13);
uniform vec3 galv : source_color = vec3(0.52, 0.54, 0.56);
uniform vec3 rail : source_color = vec3(0.95, 0.72, 0.1);
uniform float floor_h = 4.0;
uniform float bay = 8.0;
uniform float col_w = 0.7;
uniform float beam_h = 0.55;
uniform float brace_share = 0.35;

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
	if (abs(n.y) > 0.6) {
		discard;
	}
	float u = abs(n.x) > abs(n.z) ? wp.z : wp.x;
	float side_seed = abs(n.x) > abs(n.z) ? (n.x > 0.0 ? 1.0 : 2.0) : (n.z > 0.0 ? 3.0 : 4.0);
	float fu = fract(u / bay) * bay;
	float fy = fract(wp.y / floor_h) * floor_h;
	float column = step(fu, col_w * 0.5) + step(bay - col_w * 0.5, fu);
	float beam = step(fy, beam_h);
	vec2 cell = vec2(floor(u / bay), floor(wp.y / floor_h));
	float brace = 0.0;
	if (hash12(cell + side_seed * 13.0) < brace_share) {
		float a = fu / bay;
		float b = fy / floor_h;
		float w = 0.045;
		brace = max(step(abs(a - b), w), step(abs(a + b - 1.0), w));
	}
	float guard = step(abs(fy - 1.1), 0.05) * (1.0 - step(0.75, hash12(vec2(cell.y, side_seed))));
	float steel = max(max(column, beam), brace);
	if (steel < 0.5 && guard < 0.5) {
		discard;
	}
	vec3 col = mix(galv, primer, max(column, beam));
	col = mix(col, rail, guard * (1.0 - steel));
	// rain-darkened streaks down the columns
	col *= 0.8 + 0.2 * hash12(vec2(floor(u * 2.0), floor(wp.y * 0.5)));
	ALBEDO = col;
	ROUGHNESS = 0.55;
	METALLIC = 0.5;
}
