shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Jungle Temple: a faint rainbow arc in the mist of a waterfall, drawn on a quad (the arc's centre
// at the middle of the quad's bottom edge). Additive and kept faint.

uniform float strength = 0.3;

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y) * 2.0;
	float r = length(p);
	float k = clamp((r - 0.72) / 0.22, 0.0, 1.0);
	float band = smoothstep(0.0, 0.1, k) * (1.0 - smoothstep(0.9, 1.0, k)) * step(0.72, r) * (1.0 - step(0.94, r));
	float h = 1.0 - k;
	vec3 c = clamp(vec3(abs(h * 6.0 - 3.0) - 1.0, 2.0 - abs(h * 6.0 - 2.0), 2.0 - abs(h * 6.0 - 4.0)), 0.0, 1.0);
	float fade = smoothstep(0.0, 0.4, p.y);
	ALBEDO = c * band * fade * strength;
}
