shader_type spatial;
// Sugar Rush: molten chocolate. Glossy, slowly churning swirls of dark and milk chocolate with
// ribbons of cream folded through, flowing along `flow` (world XZ, m/s). With `falling` it runs
// down the surface instead (chocolate falls). Everything is bounded: no pow() of negatives, no
// normalize() of zero, smoothstep edges in order.

uniform vec3 dark : source_color = vec3(0.2, 0.09, 0.05);
uniform vec3 milk : source_color = vec3(0.5, 0.27, 0.14);
uniform vec3 cream : source_color = vec3(0.93, 0.8, 0.65);
uniform vec2 flow = vec2(0.0, 0.4);
uniform float scale = 0.08;
uniform bool falling = false;
uniform float cream_amount = 0.25;

varying vec3 wp;
varying vec3 wn;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 p;
	if (falling) {
		float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		p = vec2(u * 0.6, wp.y * 0.12 + TIME * 0.9);
	} else {
		p = wp.xz * scale - flow * TIME * scale;
	}
	float warp = fbm(p * 1.3 + vec2(TIME * 0.03, -TIME * 0.02));
	float n = fbm(p + vec2(warp * 1.6, warp * 1.1));
	vec3 col = mix(dark, milk, smoothstep(0.3, 0.75, n));
	// cream ribbons folded through
	float rib = abs(fract(n * 3.0 + warp) - 0.5);
	float c = (1.0 - smoothstep(0.0, 0.06, rib)) * cream_amount * smoothstep(0.35, 0.6, warp);
	col = mix(col, cream, c);
	ALBEDO = col;
	ROUGHNESS = 0.14 + 0.1 * n;
	SPECULAR = 0.75;
	CLEARCOAT = 0.5;
	CLEARCOAT_ROUGHNESS = 0.15;
	// gentle ripples in the gloss
	float h = fbm(p * 3.0 + vec2(TIME * 0.1, 0.0));
	NORMAL_MAP = vec3(0.5 + (h - 0.5) * 0.35, 0.5 + (warp - 0.5) * 0.35, 1.0);
	NORMAL_MAP_DEPTH = 0.6;
}
