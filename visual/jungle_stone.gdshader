shader_type spatial;
// Jungle Temple walkable surface: the platform shader's layout (bright top, inset trim line, darker
// sides) re-done as old temple stone in the rainforest. Tops are worn flagstones with moss creeping
// in from the joints and the edges; sides are staggered ashlar courses, a carved glyph band under the
// lip (some glyphs inlaid with glowing jade), moss and drips spilling over the lip, and dark water
// stains rising from below. Same uniforms as visual/platform.gdshader, so the level can swap it in.

#include "res://visual/jungle_common.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.6, 0.6, 0.5);
uniform vec3 side_color : source_color = vec3(0.4, 0.42, 0.34);
uniform vec3 trim_color : source_color = vec3(0.3, 0.95, 0.7);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 moss : source_color = vec3(0.24, 0.42, 0.14);
uniform vec3 moss_light : source_color = vec3(0.42, 0.6, 0.2);
// 0..1: how much moss (the level raises it on the old ruins, lowers it on carved temple blocks)
uniform float mossy = 0.55;

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
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
		vec2 fs = j_courses(wp.xz, vec2(1.6, 1.1));
		float joint = 1.0 - smoothstep(0.02, 0.07, fs.x);
		col = top_color * (0.86 + 0.18 * fs.y) * (1.0 - 0.3 * joint);
		col *= 0.9 + 0.14 * j_noise(wp.xz * 2.7);
		// moss: in the joints, near the edges, in patches
		float patchy = j_fbm(wp.xz * 0.45 + vec2(wp.y * 0.21, 3.0));
		float m = clamp(joint * 0.8 + smoothstep(0.62, 0.9, patchy) * 0.9 + (1.0 - smoothstep(0.15, 0.7, edge)) * 0.35, 0.0, 1.0) * mossy;
		vec3 mc = mix(moss, moss_light, j_noise(wp.xz * 5.0));
		col = mix(col, mc, m * smoothstep(trim_width + 0.05, trim_width + 0.3, edge) * 0.9);
		// the trim line that marks every landing's edge
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = mix(0.86, 0.95, m);
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		ROUGHNESS = 0.95;
	} else {
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		vec2 blk = j_courses(vec2(u, wp.y), vec2(1.25, 0.6));
		float joint = 1.0 - smoothstep(0.015, 0.05, blk.x);
		col = side_color * (0.84 + 0.22 * blk.y) * (1.0 - 0.38 * joint);
		col *= 0.84 + 0.26 * j_noise(vec2(u, wp.y) * 2.1);
		// the carved glyph band just under the lip, some cells inlaid with jade
		float band = smoothstep(0.1, 0.13, depth) * (1.0 - smoothstep(0.52, 0.55, depth));
		vec2 g = j_glyph_band(vec2(u, depth - 0.12), 0.42);
		float carve = g.x * band;
		col = mix(col, col * 0.4, carve);
		float inlay = carve * step(0.62, g.y);
		col = mix(col, trim_color * 0.75, inlay * 0.75);
		emit += trim_color * inlay * 0.45 * (0.5 + trim_glow);
		// thin trim line above the band
		float line = 1.0 - smoothstep(0.012, 0.03, abs(depth - 0.08));
		col = mix(col, trim_color * 0.9, line * 0.8);
		glow = line * 0.5;
		// moss spilling over the lip in tongues, and moss in the joints
		float tongue = j_noise(vec2(u * 1.3, 0.0)) * 0.7 + j_noise(vec2(u * 4.1, 2.0)) * 0.3;
		float drape = (1.0 - smoothstep(0.0, 0.25 + tongue * 0.9 * mossy, depth - 0.02)) * step(0.02, depth);
		float jm = joint * smoothstep(0.55, 0.8, j_fbm(vec2(u, wp.y) * 0.6)) * mossy;
		col = mix(col, mix(moss, moss_light, tongue), clamp(drape * mossy * 1.2 + jm, 0.0, 1.0) * (1.0 - carve));
		// dark wet stains rising from the bottom of tall blocks
		float stain = (1.0 - smoothstep(0.0, 0.45, h)) * smoothstep(0.6, 0.9, j_noise(vec2(u * 0.7, wp.y * 0.15)) + 0.3);
		col *= 1.0 - 0.35 * stain;
		col = mix(col * 0.65, col, smoothstep(0.0, 0.7, h));
		ROUGHNESS = 0.92;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow + emit;
}
