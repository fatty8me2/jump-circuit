shader_type spatial;
// Scarab Sands: the whirling funnel of a dust devil (DesertDustDevil). Drawn on an open cone;
// spiral bands of dust wind up it, thicker at the silhouette (it reads as a volume) and
// fading out at the foot and the ragged top.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 dust : source_color = vec3(0.9, 0.7, 0.45);
uniform vec3 lit : source_color = vec3(1.0, 0.86, 0.6);
uniform float spin = 1.6;
uniform float opacity = 0.55;
uniform float rise = 1.2;

void fragment() {
	float t = TIME;
	float y = 1.0 - UV.y;
	float band = d_fbm(vec2(UV.x * 5.0 + y * 2.2 - t * spin, y * 3.0 - t * rise));
	float fine = d_noise(vec2(UV.x * 18.0 + y * 6.0 - t * spin * 1.6, y * 9.0 - t * rise * 1.4));
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = smoothstep(0.35, 0.75, band) * (0.35 + 0.65 * rim) * (0.7 + 0.5 * fine);
	a *= smoothstep(0.0, 0.12, y) * smoothstep(1.0, 0.75 - 0.15 * band, y);
	ALBEDO = mix(dust, lit, y * 0.6 + fine * 0.3);
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
