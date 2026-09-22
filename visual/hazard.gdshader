shader_type spatial;
// Kill surface: hot red with moving dark hazard stripes. Reads as danger at any distance.
uniform vec3 hot : source_color = vec3(1.0, 0.16, 0.12);
uniform vec3 dark : source_color = vec3(0.25, 0.02, 0.04);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float x = (wp.x + wp.y + wp.z) * 0.9 + TIME * 0.35;
	float s = fract(x);
	// Filter the stripes by their screen-space frequency: widen the edges as they
	// shrink, then fade to the stripe average once they go sub-pixel (no moire).
	float w = fwidth(x);
	float e = max(0.05, w);
	float stripe = smoothstep(0.5 - e, 0.5, s) * (1.0 - smoothstep(1.0 - e, 1.0, s));
	stripe = mix(stripe, 0.5, smoothstep(0.3, 0.8, w));
	float pulse = 0.75 + 0.25 * sin(TIME * 4.0);
	ALBEDO = mix(hot, dark, stripe);
	EMISSION = hot * (1.0 - stripe) * 2.2 * pulse;
	ROUGHNESS = 0.4;
}
