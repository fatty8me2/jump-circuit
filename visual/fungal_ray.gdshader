shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
// Mushroom Hollow: a shaft of warm sunlight slanting through the canopy. Put on a tall, open
// cylinder: the edge fades by the viewing angle (so it has no hard outline), the ends fade by UV,
// and a slow shimmer runs along it. Output is bounded (alpha-scaled, colour < 1.2).

uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.55);
uniform float strength = 0.22;

void fragment() {
	vec3 n = NORMAL;
	vec3 v = VIEW;
	float nl = max(length(n), 0.0001);
	float vl = max(length(v), 0.0001);
	float f = abs(dot(n / nl, v / vl));
	f = clamp(f, 0.0, 1.0);
	float ends = smoothstep(0.0, 0.22, UV.y) * (1.0 - smoothstep(0.6, 1.0, UV.y));
	float shimmer = 0.8 + 0.2 * sin(UV.y * 9.0 - TIME * 0.8 + UV.x * 12.0);
	ALBEDO = tint;
	ALPHA = clamp(f * f * ends * shimmer * strength, 0.0, 0.5);
}
