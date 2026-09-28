shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Phantom Manor: ectoplasm. A translucent, rim-lit ghost skin that wavers with slow bands of
// light crawling up through it. `solidity` 0..1 fades it from a faint heat-ghost outline to a
// dense glowing body; `shimmer` 0..1 makes it waver and flicker (the warning before it goes).
// Every output is bounded: the rim power is clamped, the colour is scaled by at most `glow`.

uniform vec3 tint : source_color = vec3(0.55, 1.0, 0.72);
uniform float solidity : hint_range(0.0, 1.0) = 1.0;
uniform float shimmer : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 3.0) = 1.1;
uniform float wobble : hint_range(0.0, 0.3) = 0.04;
uniform float band_scale = 1.6;

varying vec3 wp;

float h11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void vertex() {
	float t = TIME;
	float w = wobble * (1.0 + 2.5 * shimmer);
	VERTEX.x += sin(VERTEX.y * 3.1 + t * 2.3) * w;
	VERTEX.z += cos(VERTEX.y * 2.7 + t * 1.9) * w;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(clamp(1.0 - ndv, 0.0, 1.0), 2.2);
	// slow bands of light rising through the body
	float bands = sin(wp.y * band_scale * 3.0 - TIME * 1.7 + sin(wp.x * 1.3 + wp.z * 0.9) * 1.5) * 0.5 + 0.5;
	float body = 0.18 + 0.22 * bands;
	// warning flicker: quick drop-outs while it wavers
	float fl = 1.0 - shimmer * 0.55 * step(0.62, h11(floor(TIME * 14.0)));
	float a = clamp((rim * 0.9 + body) * mix(0.25, 1.0, solidity) * fl, 0.0, 1.0);
	ALBEDO = tint * a * clamp(glow, 0.0, 3.0);
}
