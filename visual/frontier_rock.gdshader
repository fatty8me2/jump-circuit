shader_type spatial;
// Wild West Heist red rock: canyon walls, mesas, buttes and hoodoos. Horizontal sandstone strata in
// rust, brick and cream bands (by height), broken by noise, streaked with dark desert varnish running
// down the faces, paler and dustier on the flat tops. Coordinates are world space minus `scroll` along
// Z, so a wall whose texture should slide past the train (the world moving) and a prop that is itself
// moved by a FrontierScroll can both keep the rock fixed to the scenery. NaN-safe: no pow() of
// negatives, no normalize() of zero, smoothstep edges in order.

uniform vec3 band_a : source_color = vec3(0.70, 0.30, 0.16);
uniform vec3 band_b : source_color = vec3(0.86, 0.48, 0.26);
uniform vec3 band_c : source_color = vec3(0.93, 0.74, 0.52);
uniform vec3 varnish : source_color = vec3(0.24, 0.12, 0.08);
uniform float scroll = 0.0;
uniform float strata = 0.11;
uniform float fade_low = -70.0;

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
	wp.z -= scroll;
	vec3 n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float nl = length(n);
	wn = nl > 0.0001 ? n / nl : vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// horizontal coordinate along the face (whichever of x / z it runs along)
	float along = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
	float warp = fbm(vec2(along * 0.03, wp.y * 0.05)) * 6.0;
	float y = wp.y + warp;
	float b = fract(y * strata);
	float band_n = fbm(vec2(floor(y * strata) * 3.1, 2.0));
	vec3 col = mix(band_a, band_b, smoothstep(0.2, 0.5, b));
	col = mix(col, band_c, smoothstep(0.78, 0.86, b) * (0.5 + 0.5 * band_n));
	// thin dark seams between layers
	col *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.035, b));
	float grit = fbm(vec2(along * 0.4, wp.y * 0.4));
	col *= 0.82 + 0.3 * grit;
	// desert varnish running down the faces in streaks
	float streak = fbm(vec2(along * 0.18, wp.y * 0.012));
	float v = smoothstep(0.55, 0.75, streak) * (1.0 - clamp(abs(wn.y), 0.0, 1.0));
	col = mix(col, varnish, v * 0.55);
	// flat tops: pale dust and scrub
	float up = clamp(wn.y, 0.0, 1.0);
	col = mix(col, band_c * 0.95, smoothstep(0.6, 0.9, up) * 0.7);
	col *= mix(0.55, 1.0, smoothstep(fade_low, fade_low + 50.0, wp.y));
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.92;
}
