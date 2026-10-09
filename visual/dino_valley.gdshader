shader_type spatial;
// Dino Valley's floor, far below the stacks: green meadow in big soft patches, darker forest,
// a meandering turquoise river with sandy banks and slow flowing highlights. Lit by the sun and
// faded into the haze by the scene fog. World-space, so it never swims as the camera moves.
// All noise is bounded and every divide is by a constant.

uniform vec3 meadow : source_color = vec3(0.4, 0.58, 0.2);
uniform vec3 meadow_dry : source_color = vec3(0.62, 0.62, 0.3);
uniform vec3 forest : source_color = vec3(0.12, 0.3, 0.12);
uniform vec3 sand : source_color = vec3(0.82, 0.72, 0.48);
uniform vec3 water : source_color = vec3(0.12, 0.6, 0.66);
uniform float river_offset = 0.0;

varying vec3 wp;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(7.1, 3.3);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float bend = sin(p.y * 0.0045) * 90.0 + sin(p.y * 0.013 + 1.7) * 28.0 + river_offset;
	float d = abs(p.x - bend);
	float w = 15.0 + 5.0 * sin(p.y * 0.02);
	float riv = 1.0 - smoothstep(w * 0.8, w, d);
	float bank = 1.0 - smoothstep(w, w + 9.0, d);
	float patch_n = fbm(p * 0.011 + vec2(5.0, 1.0));
	float f = smoothstep(0.5, 0.62, patch_n);
	vec3 col = mix(meadow, meadow_dry, smoothstep(0.35, 0.7, fbm(p * 0.02 + vec2(2.0, 8.0))));
	col *= 0.86 + 0.28 * vnoise(p * 0.07);
	col = mix(col, forest * (0.75 + 0.5 * vnoise(p * 0.35)), f);
	col = mix(col, sand, bank * (1.0 - f * 0.4) * 0.85);
	float flow = vnoise(vec2(p.x * 0.25, p.y * 0.07 - TIME * 0.4));
	vec3 wcol = water * (0.75 + 0.5 * flow);
	col = mix(col, wcol, riv);
	ALBEDO = min(col, vec3(1.0));
	ROUGHNESS = mix(0.92, 0.12, riv);
	SPECULAR = mix(0.2, 0.8, riv);
}
