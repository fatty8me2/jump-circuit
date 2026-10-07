shader_type spatial;
// Mushroom Hollow: the forest floor far below the course - deep green moss in great soft drifts,
// patches of brown earth and fallen needles, clover and pale flecks, all fading into the warm haze.
// Static (world-space noise, no TIME). Every term bounded and NaN-free.

uniform vec3 moss_a : source_color = vec3(0.27, 0.46, 0.17);
uniform vec3 moss_b : source_color = vec3(0.4, 0.58, 0.22);
uniform vec3 earth : source_color = vec3(0.34, 0.24, 0.14);
uniform float scale = 0.06;

varying vec3 wp;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(3.7, 1.3);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = wp.xz * scale;
	float big = fbm(q * 0.6);
	float mid = fbm(q * 2.4 + vec2(9.0, 4.0));
	float fine = noise2(wp.xz * 1.3);
	vec3 col = mix(moss_a, moss_b, smoothstep(0.3, 0.7, big));
	col *= 0.85 + 0.3 * mid;
	float soil = smoothstep(0.62, 0.78, fbm(q * 0.9 + vec2(20.0, 7.0)));
	col = mix(col, earth * (0.8 + 0.4 * mid), soil * 0.8);
	float fleck = smoothstep(0.86, 0.94, noise2(wp.xz * 0.9 + vec2(4.0, 12.0)));
	col = mix(col, vec3(0.78, 0.84, 0.5), fleck * 0.35 * (1.0 - soil));
	col *= 0.92 + 0.12 * fine;
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
