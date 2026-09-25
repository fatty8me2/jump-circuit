shader_type spatial;
// Scarab Sands: a dusty sunbeam slanting through a gap in the temple roof. An open cone
// (CylinderMesh, no caps) laid along the sun; brightest through its middle, fading toward the
// foot, with slow motes of dust glittering inside. Fog-free: it fades by camera distance.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.5);
uniform float intensity = 0.16;
uniform float fade_far = 140.0;

varying float dist;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dist = length(wp - CAMERA_POSITION_WORLD);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.0);
	float down = UV.y;
	float fall = (1.0 - smoothstep(0.45, 1.0, down)) * smoothstep(0.0, 0.06, down);
	float t = TIME;
	float motes = step(0.93, d_noise(vec2(UV.x * 60.0, down * 30.0 - t * 0.4)));
	float drift = 0.8 + 0.2 * d_noise(vec2(UV.x * 8.0 + t * 0.1, down * 4.0 - t * 0.15));
	float near = smoothstep(1.5, 8.0, dist);
	float far = 1.0 - smoothstep(20.0, fade_far, dist) * 0.85;
	ALBEDO = color * (core * drift + motes * 1.5 * core) * fall * intensity * near * far;
}
