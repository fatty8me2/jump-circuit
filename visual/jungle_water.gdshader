shader_type spatial;
// Jungle Temple: the river and the flooded forest floor. Murky green-brown water drifting along
// `flow`, rippled (the normal comes from the drifting noise), with pale streaks of foam and scum and a
// glossy sheen that catches the sky. Opaque: the water is far too murky to see into.

#include "res://visual/jungle_common.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.07, 0.17, 0.12);
uniform vec3 shallow : source_color = vec3(0.2, 0.33, 0.22);
uniform vec3 foam : source_color = vec3(0.82, 0.88, 0.8);
uniform vec2 flow = vec2(0.0, 0.6);
uniform float ripple = 5.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz * 0.16;
	vec2 drift = flow * TIME * 0.12;
	float n1 = j_fbm(p + drift);
	float n2 = j_fbm(p * 2.3 - drift * 1.6 + vec2(4.0, 1.0));
	float e = 0.06;
	float gx = j_fbm(p + vec2(e, 0.0) + drift) - n1 + (j_fbm(p * 2.3 + vec2(e, 0.0) - drift * 1.6 + vec2(4.0, 1.0)) - n2) * 0.5;
	float gz = j_fbm(p + vec2(0.0, e) + drift) - n1 + (j_fbm(p * 2.3 + vec2(0.0, e) - drift * 1.6 + vec2(4.0, 1.0)) - n2) * 0.5;
	vec3 wn = vec3(-gx * ripple, 1.0, -gz * ripple);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float n = n1 * 0.6 + n2 * 0.4;
	vec3 col = mix(deep, shallow, smoothstep(0.3, 0.8, n));
	float streak = smoothstep(0.68, 0.86, j_fbm(vec2(p.x * 3.0, p.y * 0.7) + drift * 2.5));
	col = mix(col, foam, streak * 0.22);
	ALBEDO = col;
	ROUGHNESS = 0.07;
	SPECULAR = 0.55;
}
