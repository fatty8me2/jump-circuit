shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Phantom Manor: a portrait's gaze beam. UV.x runs from the eyes (0) to where it burns the
// floor (1), UV.y across it. A hot core with soft edges, crawling sparkle, brightest at the
// eyes and flaring again where it lands. Bounded output (strength and glow are clamped).

uniform vec3 color : source_color = vec3(0.55, 1.0, 0.5);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float glow : hint_range(0.0, 3.0) = 1.8;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 0.35, across);
	float soft = 1.0 - smoothstep(0.2, 1.0, across);
	float along = UV.x;
	float ends = 0.55 + 0.45 * (1.0 - smoothstep(0.0, 0.25, along)) + 0.5 * smoothstep(0.85, 1.0, along);
	float crawl = 0.75 + 0.25 * sin(along * 40.0 - TIME * 18.0);
	float a = (core * 0.9 + soft * 0.35) * ends * crawl * clamp(strength, 0.0, 1.0);
	ALBEDO = color * clamp(a, 0.0, 1.5) * clamp(glow, 0.0, 3.0);
}
