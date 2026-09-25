shader_type spatial;
// Scarab Sands: the sandstorm wall rolling in on the horizon. Drawn on the inside of a huge
// open cylinder round the course; only an arc of it (centred on `arc_center`, in turns) is
// storm, fading out to either side. Billowing fbm boils up and drifts along the front, dark
// and dense at the foot, a ragged sunlit crest on top.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 dark : source_color = vec3(0.42, 0.27, 0.16);
uniform vec3 lit : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 haze : source_color = vec3(0.95, 0.75, 0.52);
uniform float arc_center = 0.3;
uniform float arc_width = 0.2;
uniform float haze_mix = 0.45;
uniform float speed = 1.0;

void fragment() {
	float t = TIME * speed;
	vec2 uv = UV;
	float da = abs(fract(uv.x - arc_center + 0.5) - 0.5);
	float side = 1.0 - smoothstep(arc_width * 0.55, arc_width, da);
	float y = 1.0 - uv.y;   // 0 at the foot, 1 at the top
	vec2 p = vec2(uv.x * 90.0, y * 5.0);
	float billow = d_fbm(p * vec2(0.5, 1.0) + vec2(t * 0.05, -t * 0.12));
	float fine = d_fbm(p * vec2(1.6, 3.0) + vec2(-t * 0.1, -t * 0.3));
	float crest = 0.55 + 0.25 * d_fbm(vec2(uv.x * 40.0 + t * 0.03, 0.0)) * side + 0.1 * side;
	float body = smoothstep(crest, crest - 0.25, y - billow * 0.25);
	float a = body * side * (0.75 + 0.25 * fine);
	vec3 col = mix(dark, lit, smoothstep(0.1, 0.95, y + (billow - 0.5) * 0.4));
	col *= 0.8 + 0.3 * fine;
	col = mix(col, haze, haze_mix * (1.0 - y * 0.5));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * smoothstep(0.0, 0.08, y + 0.02);
}
