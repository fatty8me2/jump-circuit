shader_type spatial;
render_mode unshaded, cull_disabled;
// Pixel Panic: the edge of the scrolling screen. A wall of corrupted video: coarse magenta / cyan pixel
// noise that re-rolls a dozen times a second, scanlines, rows torn sideways, a bright rolling bar and
// a white-hot leading face. Local X is across the wall, Y up, -Z the way it is travelling.
// Bounded (colour <= ~2), no divisions by variables, no pow(), no normalize().

uniform vec3 col_a : source_color = vec3(1.0, 0.2, 0.7);
uniform vec3 col_b : source_color = vec3(0.1, 0.9, 1.0);
uniform float thickness = 3.0;

varying vec3 lp;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float frame = floor(TIME * 12.0);
	float row = floor(lp.y * 2.0);
	float tear = (h21(vec2(row, frame)) - 0.5) * step(0.82, h21(vec2(row, frame + 7.0))) * 3.0;
	vec2 cell = floor(vec2(lp.x + tear, lp.y) * 1.4);
	float n = h21(cell + vec2(frame, frame * 1.7));
	vec3 col = mix(col_a, col_b, step(0.5, h21(cell + vec2(3.0, 9.0))));
	col *= 0.25 + 0.75 * n;
	float scan = step(0.5, fract(lp.y * 2.0));
	col *= 0.7 + 0.3 * scan;
	// a bright bar rolling up the wall
	float bar = 1.0 - smoothstep(0.0, 0.6, abs(fract(lp.y * 0.04 - TIME * 0.35) - 0.5) * 4.0 - 0.9);
	col += vec3(1.0, 0.9, 1.0) * clamp(bar, 0.0, 1.0) * 0.35;
	// the leading face (local -Z side) is white-hot
	float face = clamp((-lp.z) / max(thickness * 0.5, 0.01), 0.0, 1.0);
	float lead = smoothstep(0.7, 1.0, face);
	col = mix(col, vec3(1.0, 0.95, 1.0), lead * (0.55 + 0.35 * n));
	ALBEDO = clamp(col, vec3(0.0), vec3(2.0));
}
