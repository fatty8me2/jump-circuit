shader_type spatial;
// Super Carrier: the fire-suppression foam flooding the hangar deck. A thick, slowly heaving blanket
// of bubbles: cells of foam that swell and pop, creamy where it piles up, slick and wet in the
// troughs, drifting in lazy swirls away from the sprinkler heads. It glows faintly so it always reads
// as "the floor you must not touch" in the dim hangar. Bounded: no pow(), no normalize() of zero.

uniform vec3 cream : source_color = vec3(0.95, 0.94, 0.86);
uniform vec3 trough : source_color = vec3(0.62, 0.66, 0.62);
uniform float glow = 0.18;

varying vec3 wp;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash22(i).x;
	float b = hash22(i + vec2(1.0, 0.0)).x;
	float c = hash22(i + vec2(0.0, 1.0)).x;
	float d = hash22(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// bubble cells: distance to the nearest (slowly breathing) cell centre
float cells(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = hash22(i + o);
			vec2 c = o + 0.5 + 0.35 * sin(t * (0.4 + h.x) + h * 6.2831);
			best = min(best, length(f - c) / (0.55 + 0.25 * h.y));
		}
	}
	return best;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 q = wp.xz + vec2(sin(wp.z * 0.05 + t * 0.2), cos(wp.x * 0.06 + t * 0.17)) * 1.5;
	float big = cells(q * 0.45, t * 0.6);
	float small = cells(q * 1.6 + 7.0, t * 1.1);
	float heap = noise2(q * 0.08 + vec2(t * 0.02, 0.0)) * 0.6 + noise2(q * 0.3) * 0.4;
	float rim = smoothstep(0.55, 0.95, big) * 0.6 + smoothstep(0.6, 1.0, small) * 0.4;
	float f = clamp(0.55 + heap * 0.5 - rim * 0.45, 0.0, 1.0);
	vec3 col = mix(trough, cream, f);
	// glistening wet highlights between the bubbles
	float wet = 1.0 - smoothstep(0.0, 0.25, abs(big - 0.8));
	ALBEDO = col;
	ROUGHNESS = mix(0.25, 0.85, f) - wet * 0.15;
	SPECULAR = 0.4;
	vec3 nrm = normalize(vec3((noise2(q * 2.0) - 0.5) * 0.6, 1.0, (noise2(q * 2.0 + 3.0) - 0.5) * 0.6));
	NORMAL = (VIEW_MATRIX * vec4(nrm, 0.0)).xyz;
	EMISSION = cream * glow * (0.6 + 0.4 * f);
}
