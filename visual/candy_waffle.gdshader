shader_type spatial;
// Sugar Rush: waffle / wafer. A diamond lattice of baked ridges in world space, for the waffle
// cones hanging under the floating dessert islands and for the wafer walls. `square` switches to
// the square grid of a wafer biscuit.

uniform vec3 base_color : source_color = vec3(0.9, 0.64, 0.34);
uniform vec3 ridge_color : source_color = vec3(0.62, 0.38, 0.17);
uniform float cell = 0.55;
uniform bool square = false;
uniform float glow = 0.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
	vec2 q = square ? vec2(u, wp.y) / cell : vec2(u + wp.y, u - wp.y) / cell;
	vec2 g = abs(fract(q) - 0.5);
	float line = 1.0 - smoothstep(0.06, 0.12, min(g.x, g.y));
	float pit = smoothstep(0.1, 0.45, min(g.x, g.y));
	vec3 col = mix(base_color * (0.92 + 0.1 * pit), ridge_color, line * 0.75);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	EMISSION = col * glow;
}
