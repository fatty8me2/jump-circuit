shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
// Pixel Panic: the outline of a block that is about to land (and of a tile about to arrive).
// A bright pixel frame round every face with a faint scanlined fill. `pulse` (0..1) swells it.
// Bounded, no divisions, no pow().

uniform vec3 tint : source_color = vec3(0.1, 0.9, 1.0);
uniform vec3 half_size = vec3(0.6, 0.3, 0.6);
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float fill : hint_range(0.0, 1.0) = 0.12;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 an = abs(ln);
	vec2 q;
	vec2 hs;
	if (an.y > 0.5) {
		q = lp.xz;
		hs = half_size.xz;
	} else if (an.x > 0.5) {
		q = lp.zy;
		hs = half_size.zy;
	} else {
		q = lp.xy;
		hs = half_size.xy;
	}
	vec2 d = hs - abs(q);
	float edge = min(d.x, d.y);
	float frame = 1.0 - step(0.07, edge);
	float scan = step(0.5, fract(lp.y * 6.0 + lp.x * 6.0 + lp.z * 6.0));
	float a = frame * (0.55 + 0.45 * pulse) + (fill + 0.25 * pulse) * (0.5 + 0.5 * scan);
	ALBEDO = tint * (1.0 + 1.4 * pulse) * clamp(a, 0.0, 1.0);
	ALPHA = 1.0;
}
