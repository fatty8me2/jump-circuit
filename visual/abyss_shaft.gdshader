shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// The Abyss: a shaft of the last surface light, slanting down into the trench and dying out long
// before it reaches the bottom. Used on an open cylinder (UV.y 0 at the top, 1 at the bottom):
// brightest at the top, gone by the lower third; soft at its silhouette edges; slow ripples
// drift down it. Additive and bounded.

uniform vec3 tint : source_color = vec3(0.25, 0.55, 0.6);
uniform float strength = 0.25;

void fragment() {
	float down = clamp(UV.y, 0.0, 1.0);
	float fade = 1.0 - smoothstep(0.0, 0.7, down);
	fade *= fade;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = smoothstep(0.05, 0.6, facing);
	float rip = 0.75 + 0.25 * sin(UV.x * 37.0 + TIME * 0.6) * sin(UV.y * 9.0 - TIME * 0.35);
	ALBEDO = clamp(tint * strength * fade * soft * rip, vec3(0.0), vec3(1.0));
}
