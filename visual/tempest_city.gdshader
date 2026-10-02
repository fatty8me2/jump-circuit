shader_type spatial;
// Tempest Tower: the city far below, seen through the storm - a grid of blocks and streets in WORLD
// space on one huge plane: grey and tar roofs of every shade, wet streets shining, a few parks, and
// the odd string of headlights and lit windows smudged by the rain. Bounded emission, no NaN.

uniform vec3 street : source_color = vec3(0.1, 0.11, 0.12);
uniform vec3 roof_a : source_color = vec3(0.3, 0.31, 0.33);
uniform vec3 roof_b : source_color = vec3(0.18, 0.19, 0.2);
uniform vec3 park : source_color = vec3(0.16, 0.22, 0.14);
uniform float block = 60.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = wp.xz / block;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float road = 1.0 - step(0.08, f.x) * step(f.x, 0.92) * step(0.08, f.y) * step(f.y, 0.92);
	float h = hash12(cell);
	// buildings inside each block: a sub-grid of roofs
	vec2 sub = floor(f * 4.0);
	float hs = hash12(cell * 4.0 + sub);
	vec3 col = mix(roof_b, roof_a, hs);
	if (h < 0.08) {
		col = park * (0.8 + 0.4 * hs);
	}
	float gap = 1.0 - step(0.06, fract(f.x * 4.0)) * step(0.06, fract(f.y * 4.0));
	col = mix(col, roof_b * 0.6, gap * 0.6);
	col = mix(col, street, road);
	// headlights and the odd lit window, smudged
	float lights = step(0.985, hash12(floor(wp.xz * 0.5))) * road;
	float win = step(0.993, hash12(floor(wp.xz * 0.7) + 3.0)) * (1.0 - road);
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.2, road);
	METALLIC = 0.0;
	EMISSION = clamp(vec3(1.0, 0.85, 0.6) * lights * 0.9 + vec3(0.8, 0.9, 1.0) * win * 0.5, vec3(0.0), vec3(1.5));
}
