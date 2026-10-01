shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_disabled;
// Neon City searchlight pool on a wet rooftop: a hot white-amber disc with a pulsing red danger
// rim and a few rain ripples breaking it up. Lies flat (QuadMesh facing up), UV 0..1 across.
// Bounded and NaN-safe.

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.15, 0.2, 1.0);
uniform float strength = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.3;
	float r = length(p);
	float disc = 1.0 - smoothstep(0.8, 1.0, r);
	float core = 1.0 - smoothstep(0.0, 0.85, r);
	float ring = smoothstep(0.86, 0.96, r) * (1.0 - smoothstep(1.0, 1.1, r));
	float pulse = 0.65 + 0.35 * sin(TIME * 9.0);
	// little expanding rain ripples
	vec2 cell = floor(p * 3.0);
	float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	vec2 f = fract(p * 3.0) - 0.5;
	float ph = fract(TIME * 0.9 + seed);
	float rip = (1.0 - smoothstep(0.0, 0.05, abs(length(f) - ph * 0.45))) * (1.0 - ph) * disc;
	vec3 c = tint.rgb * (disc * 0.55 + core * 0.9 + rip * 0.5) + rim.rgb * ring * pulse * 1.6;
	ALBEDO = c * strength;
	ALPHA = clamp(disc + ring, 0.0, 1.0);
}
