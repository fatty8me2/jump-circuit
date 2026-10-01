shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Jungle Temple: a waterfall curtain on a quad (UV.y 0 at the lip, 1 at the foot). Streaks of white
// water racing down, thinning toward the edges, broken up into spray near the foot.

#include "res://visual/jungle_common.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.86, 0.95, 0.94);
uniform float speed = 1.4;
uniform float opacity = 0.85;

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float s = j_noise(vec2(uv.x * 38.0, uv.y * 3.0 - t * 4.0)) * 0.55 + j_noise(vec2(uv.x * 85.0, uv.y * 7.0 - t * 6.5)) * 0.45;
	float edge = smoothstep(0.0, 0.1, uv.x) * smoothstep(0.0, 0.1, 1.0 - uv.x);
	float lip = smoothstep(0.0, 0.03, uv.y);
	float foot = 1.0 - smoothstep(0.8, 1.0, uv.y) * 0.6;
	float a = clamp((0.3 + s * 0.7) * edge * lip * foot, 0.0, 1.0);
	ALBEDO = tint * (0.72 + 0.38 * s);
	ALPHA = a * opacity;
}
