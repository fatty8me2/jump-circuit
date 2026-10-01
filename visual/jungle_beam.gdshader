shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Jungle Temple: a god ray falling through a gap in the canopy, on a tall open cylinder (UV.y 0 at
// the top). Soft at its silhouette (fresnel), faded in at the top and out toward the ground, and
// flickering slowly as leaves drift across the gap. Additive, and kept faint.

#include "res://visual/jungle_common.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0, 0.92, 0.7);
uniform float strength = 0.16;

void fragment() {
	float fres = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float soft = fres * fres;
	float along = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float flick = 0.7 + 0.3 * j_noise(vec2(UV.x * 7.0, TIME * 0.35 + UV.y * 1.5));
	ALBEDO = color * clamp(strength * soft * along * flick, 0.0, 1.0);
}
