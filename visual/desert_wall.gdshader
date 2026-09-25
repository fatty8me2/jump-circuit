shader_type spatial;
// Scarab Sands architecture: temple walls, pillars, statues and the far pyramids. World-space
// ashlar courses with weathering, and (between glyph_lo and glyph_hi, in the mesh's own height)
// columns of carved hieroglyphs, some inlaid with gold or turquoise that catch the light.

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 stone : source_color = vec3(0.78, 0.6, 0.38);
uniform vec3 inlay_a : source_color = vec3(1.0, 0.72, 0.22);
uniform vec3 inlay_b : source_color = vec3(0.15, 0.78, 0.78);
uniform vec2 block = vec2(2.2, 1.1);
uniform float glyph_lo = 1.0;
uniform float glyph_hi = -1.0;
uniform float glyph_cell = 0.9;
uniform float inlay_glow = 0.35;
uniform float weather = 1.0;
// darken toward the base (sand-scoured) over this many metres (0 = off)
uniform float base_fade = 0.0;

varying vec3 lp;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wn);
	vec2 q;
	if (n.y > 0.7) {
		q = wp.xz;
	} else {
		q = vec2(n.x > n.z ? wp.z : wp.x, wp.y);
	}
	vec2 blk = d_courses(q, block);
	float joint = 1.0 - smoothstep(0.02, 0.07, blk.x);
	vec3 col = stone * (0.85 + 0.22 * blk.y) * (1.0 - 0.32 * joint);
	float grime = d_fbm(q * 0.35);
	col *= mix(1.0, 0.75 + 0.35 * grime, weather);
	col *= 0.9 + 0.12 * d_noise(q * 3.7);
	if (base_fade > 0.0) {
		col *= mix(0.7, 1.0, smoothstep(0.0, base_fade, lp.y + base_fade * 0.5));
	}
	vec3 emit = vec3(0.0);
	if (n.y < 0.7 && lp.y > glyph_lo && lp.y < glyph_hi) {
		vec2 g = d_glyph_band(q - vec2(0.0, glyph_lo), glyph_cell);
		// frame lines between glyph columns
		float colline = 1.0 - smoothstep(0.015, 0.04, (0.5 - abs(fract(q.x / glyph_cell) - 0.5)) * glyph_cell);
		float carve = g.x;
		col = mix(col, col * 0.45, carve);
		col = mix(col, col * 0.7, clamp(colline, 0.0, 1.0) * 0.5);
		if (g.y > 0.62) {
			vec3 inl = g.y > 0.82 ? inlay_b : inlay_a;
			col = mix(col, inl, carve * 0.85);
			emit += inl * carve * inlay_glow;
		}
	}
	ALBEDO = col;
	EMISSION = emit;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
}
