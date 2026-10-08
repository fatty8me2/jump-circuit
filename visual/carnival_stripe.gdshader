shader_type spatial;
render_mode cull_disabled;
// Carnival Chaos: big-top canvas. Radial stripes round the local Y axis (tent roofs, carousel
// canopies and decks), alternating two colours, with a soft seam line and a faint canvas weave.
// A lit material; every term is bounded and NaN-safe (atan guarded, no pow, no divides by zero).

uniform vec3 color_a : source_color = vec3(0.95, 0.2, 0.25);
uniform vec3 color_b : source_color = vec3(0.98, 0.93, 0.8);
uniform float stripes = 12.0;
uniform float glow = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = lp.xz;
	float ang = atan(q.y, q.x + 0.00001);
	float u = ang / 6.2831853 * max(stripes, 1.0);
	float f = fract(u);
	float band = step(0.5, f);
	float seam = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.45, 0.5, f)) + smoothstep(0.5, 0.55, f) * (1.0 - smoothstep(0.95, 1.0, f));
	vec3 col = mix(color_a, color_b, band);
	col *= 0.86 + 0.14 * seam;
	float weave = 0.5 + 0.5 * sin(lp.y * 40.0) * sin(ang * 60.0);
	col *= 0.97 + 0.03 * weave;
	ALBEDO = col;
	ROUGHNESS = 0.75;
	EMISSION = col * glow;
}
