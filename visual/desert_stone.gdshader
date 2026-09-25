shader_type spatial;
// Scarab Sands walkable surface: the platform shader's layout (bright top, inset trim line,
// darker sides) re-done as sun-baked sandstone. Tops are flagstones half buried in wind-rippled
// sand; sides are staggered ashlar courses with a band of carved glyphs (gold and turquoise
// inlay) under the lip. Same uniforms as visual/platform.gdshader, so the level can swap it in.

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.92, 0.78, 0.52);
uniform vec3 side_color : source_color = vec3(0.7, 0.5, 0.3);
uniform vec3 trim_color : source_color = vec3(0.2, 0.75, 0.8);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 sand_color : source_color = vec3(0.96, 0.8, 0.52);
uniform vec3 gold : source_color = vec3(1.0, 0.72, 0.22);

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	vec3 emit = vec3(0.0);
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// flagstones
		vec2 fs = d_courses(wp.xz, vec2(1.7, 1.25));
		float joint = 1.0 - smoothstep(0.02, 0.06, fs.x);
		col = top_color * (0.9 + 0.12 * fs.y) * (1.0 - 0.28 * joint);
		col *= 0.93 + 0.1 * d_noise(wp.xz * 3.1);
		// drifted sand: rippled patches filling the joints and the middle of the slab
		float drift = smoothstep(0.42, 0.7, d_fbm(wp.xz * 0.35 + vec2(wp.y * 0.3, 0.0)) + joint * 0.25);
		float ripple = sin(wp.x * 5.5 + wp.z * 1.2 + d_noise(wp.xz * 0.8) * 5.0) * 0.5 + 0.5;
		vec3 sand = sand_color * (0.9 + 0.1 * ripple);
		col = mix(col, sand, drift * smoothstep(0.25, 0.8, edge) * 0.85);
		// the trim line that marks every landing's edge
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = 0.88;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		ROUGHNESS = 0.95;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		// ashlar courses round the block, along whichever horizontal axis this face runs
		float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		vec2 blk = d_courses(vec2(u, wp.y), vec2(1.3, 0.62));
		float joint = 1.0 - smoothstep(0.015, 0.05, blk.x);
		col = side_color * (0.86 + 0.2 * blk.y) * (1.0 - 0.35 * joint);
		col *= 0.85 + 0.25 * d_noise(vec2(u, wp.y) * 2.3);
		col = mix(col * 0.6, col, smoothstep(0.0, 0.8, h));
		// the carved glyph band just under the lip, inlaid with gold and turquoise
		float band = smoothstep(0.1, 0.13, depth) * (1.0 - smoothstep(0.55, 0.58, depth));
		vec2 g = d_glyph_band(vec2(u, depth - 0.12), 0.45);
		float carve = g.x * band;
		vec3 inlay = g.y < 0.5 ? gold : trim_color;
		col = mix(col, col * 0.42, carve);
		col = mix(col, inlay * 0.8, carve * step(0.55, g.y + 0.2) * 0.7);
		emit += inlay * carve * step(0.55, g.y + 0.2) * 0.35 * (0.4 + trim_glow);
		// thin trim line above and below the band
		float lines = (1.0 - smoothstep(0.012, 0.03, abs(depth - 0.1))) + (1.0 - smoothstep(0.012, 0.03, abs(depth - 0.6)));
		col = mix(col, trim_color * 0.9, clamp(lines, 0.0, 1.0) * 0.8);
		glow = clamp(lines, 0.0, 1.0) * 0.5;
		// sand dusting in the joints and along the top of each course
		col = mix(col, sand_color * 0.9, joint * 0.25 * smoothstep(0.3, 0.7, d_noise(vec2(u, wp.y) * 1.4)));
		ROUGHNESS = 0.9;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow + emit;
}
