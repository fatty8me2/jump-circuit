shader_type spatial;
// Kill surface: hot red with moving dark hazard stripes. Reads as danger at any distance.
uniform vec3 hot : source_color = vec3(1.0, 0.16, 0.12);
uniform vec3 dark : source_color = vec3(0.25, 0.02, 0.04);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float s = fract((wp.x + wp.y + wp.z) * 0.9 + TIME * 0.35);
	float stripe = smoothstep(0.45, 0.5, s) * (1.0 - smoothstep(0.95, 1.0, s));
	float pulse = 0.75 + 0.25 * sin(TIME * 4.0);
	ALBEDO = mix(hot, dark, stripe);
	EMISSION = hot * (1.0 - stripe) * 2.2 * pulse;
	ROUGHNESS = 0.4;
}
