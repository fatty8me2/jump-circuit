shader_type spatial;
render_mode unshaded, cull_disabled;
// The endless chessboard far below The Void: huge squares of pale and dark, thin glowing seams
// between them, fading out with distance into the violet dark. Visual only (no collision).
// NaN-safe: bounded terms, guarded divisions.

uniform float cell = 14.0;
uniform vec3 pale : source_color = vec3(0.34, 0.31, 0.42);
uniform vec3 dark : source_color = vec3(0.035, 0.02, 0.06);
uniform vec3 seam : source_color = vec3(1.0, 0.36, 0.72);
uniform float fade_dist = 520.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float c = max(cell, 0.5);
	vec2 g = wp.xz / c;
	vec2 i = floor(g);
	float chk = mod(i.x + i.y, 2.0);
	vec3 col = mix(dark, pale, chk);
	vec2 f = abs(fract(g) - 0.5);
	float line = 1.0 - smoothstep(0.485, 0.495, max(f.x, f.y));
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_dist * 0.25, fade_dist, d);
	col = mix(dark, col, fade);
	ALBEDO = col + seam * (1.0 - line) * 0.5 * fade;
}
