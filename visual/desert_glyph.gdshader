shader_type spatial;
// Scarab Sands: one glowing hieroglyph on a flat quad (trap plates, doors, the sun gate).
// `kind` picks the glyph (0.05 sun, 0.2 eye, 0.35 water, 0.5 ankh, 0.63 bird, 0.77 scarab,
// 0.9 reeds); `glow` drives the brightness (traps pulse it as a warning).
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0, 0.72, 0.25);
uniform float glow = 0.5;
uniform float kind = 0.05;
uniform bool framed = true;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float m = d_glyph(p * 1.25, kind);
	if (framed) {
		vec2 d = 1.0 - abs(p);
		float frame = 1.0 - smoothstep(0.03, 0.07, min(d.x, d.y));
		m = max(m, frame * 0.8);
	}
	ALBEDO = color * glow;
	ALPHA = m;
}
