shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Coral Depths god ray: an open cone (CylinderMesh without caps) hanging from the
// surface. Brightest where you look through the middle of it, fading toward its foot,
// shimmering. Fog-free, so it fades by camera distance itself.

uniform vec3 color : source_color = vec3(0.6, 1.0, 1.0);
uniform float intensity = 0.14;
uniform float fade_near = 30.0;
uniform float fade_far = 170.0;

varying float dist;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dist = length(wp - CAMERA_POSITION_WORLD);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.5);
	float down = UV.y;          // 0 at the top, 1 at the foot
	float fall = (1.0 - smoothstep(0.35, 1.0, down)) * smoothstep(0.0, 0.08, down);
	float shimmer = 0.75 + 0.25 * sin(TIME * 0.9 + wp.x * 0.2 + wp.z * 0.13) * sin(TIME * 1.37 + UV.x * 25.0);
	float near = smoothstep(2.0, 12.0, dist);
	float far = 1.0 - smoothstep(fade_near, fade_far, dist) * 0.8;
	ALBEDO = color * core * fall * shimmer * intensity * near * far;
}
