shader_type spatial;
// Pixel Panic: a chunky 8-bit beveled block (a tetromino cell, a voxel of scenery). Bright
// top-left bevel, dark bottom-right bevel, a flat face with a little pixel glint and faint
// scanlines. `flash` (0..1) pulses the whole block toward white (a row about to clear).
// Every term is bounded; there are no divisions, no pow() and no normalize().

uniform vec3 tint : source_color = vec3(0.1, 0.9, 1.0);
uniform vec3 half_size = vec3(0.6, 0.3, 0.6);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 2.0) = 0.35;
uniform float bevel = 0.11;

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
	float b = max(bevel, 0.02);
	vec3 col = tint;
	float lit = 0.0;
	if (edge < b) {
		// the bevel: light from the top-left
		float side = (q.x * -1.0 + q.y) > 0.0 ? 1.0 : 0.0;
		col = mix(tint * 0.38, min(tint * 1.55 + vec3(0.22), vec3(1.6)), side);
		lit = side * 0.2;
	} else {
		// the face: a pixel glint in the corner and faint scanlines
		float gx = q.x + hs.x - b * 2.0;
		float gy = hs.y - b * 2.0 - q.y;
		float glint = step(0.0, gx) * step(gx, b * 1.6) * step(0.0, gy) * step(gy, b * 1.6);
		float scan = 0.88 + 0.12 * step(0.5, fract(lp.y * 7.0));
		col = tint * scan;
		col = mix(col, min(tint * 1.8 + vec3(0.35), vec3(1.6)), glint);
		lit = 0.1;
	}
	col = mix(col, vec3(1.0), clamp(flash, 0.0, 1.0) * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.55;
	EMISSION = tint * (glow * (0.35 + lit)) + vec3(1.0) * clamp(flash, 0.0, 1.0) * 1.2;
}
