shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Xeno Wilds: the edge of a drift well's gravity field - a faint fresnel sphere with slow
// ripples of light crawling over it. Nearly invisible face-on, glowing at the rim.

uniform vec3 tint : source_color = vec3(0.7, 0.45, 1.0);
uniform float strength = 0.55;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	f = pow(f, 3.0);
	float rip = 0.5 + 0.5 * sin(wp.y * 1.3 - TIME * 1.1 + sin(wp.x * 0.4 + wp.z * 0.3) * 2.0);
	ALBEDO = tint * (f * (0.6 + 0.6 * rip)) * strength;
}
