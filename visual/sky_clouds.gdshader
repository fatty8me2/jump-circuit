shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
// Soft painterly cloud puff: fresnel-faded, tinted from below.
uniform vec3 light_color : source_color = vec3(1.0);
uniform vec3 shade_color : source_color = vec3(0.7, 0.75, 0.9);
uniform float alpha = 0.9;
varying vec3 wn;
void vertex() { wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; }
void fragment() {
	float up = clamp(normalize(wn).y * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(shade_color, light_color, smoothstep(0.15, 0.85, up));
	float f = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALPHA = alpha * smoothstep(0.0, 0.55, f);
}
