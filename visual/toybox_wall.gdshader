shader_type spatial;
render_mode unshaded, cull_disabled;
// Toybox Tumble's bedroom walls: pale blue wallpaper with wide cream stripes and little yellow
// stars, a painted baseboard and a chair rail, warmer toward the floor where the sun lands.
// World-space, no TIME. NaN-safe.

uniform vec3 paper_a : source_color = vec3(0.62, 0.8, 0.95);
uniform vec3 paper_b : source_color = vec3(0.98, 0.94, 0.84);
uniform vec3 star_col : source_color = vec3(1.0, 0.86, 0.3);
uniform vec3 board : source_color = vec3(0.98, 0.96, 0.92);
uniform float floor_y = -14.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float u = wp.x + wp.z;
	float h = wp.y - floor_y;
	float stripe = step(0.5, fract(u / 18.0));
	vec3 col = mix(paper_a, paper_b, stripe);
	// stars on the blue stripes
	vec2 cell = vec2(u / 9.0, h / 9.0);
	vec2 id = floor(cell);
	vec2 f = fract(cell) - vec2(0.5);
	float on = step(0.6, hash12(id)) * (1.0 - stripe);
	float star = 1.0 - smoothstep(0.1, 0.16, length(f));
	col = mix(col, star_col, star * on);
	// chair rail and baseboard
	float rail = 1.0 - smoothstep(0.0, 0.5, abs(h - 38.0) - 1.4);
	col = mix(col, board, rail);
	float bb = 1.0 - smoothstep(0.0, 0.5, h - 6.0);
	col = mix(col, board, bb);
	// warm light low down, a touch dimmer up high
	col *= mix(1.0, 0.78, smoothstep(40.0, 220.0, h));
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
}
