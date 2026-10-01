shader_type spatial;
// Wild West Heist: the canyon floor far below the trestle, sliding past (`scroll` = metres travelled,
// so the ground runs back along +Z under the static train). Red sand and scrub, sun-baked mud cracks
// toward the banks, and a winding river down the middle with sun glitter and ripples. Bounded
// emission, NaN-safe (no pow of negatives, no normalize of zero).

uniform float scroll = 0.0;
uniform vec3 sand : source_color = vec3(0.78, 0.46, 0.28);
uniform vec3 sand_dark : source_color = vec3(0.55, 0.28, 0.16);
uniform vec3 water : source_color = vec3(0.16, 0.42, 0.44);
uniform vec3 water_glint : source_color = vec3(1.0, 0.78, 0.5);
uniform float river_w = 9.0;

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
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p = p * 2.07 + vec2(5.2, 1.3);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wp.x, wp.z - scroll);
	// the river meanders down the canyon
	float centre = sin(p.y * 0.012) * 18.0 + sin(p.y * 0.031 + 1.3) * 7.0;
	float d = abs(p.x - centre);
	float bank = smoothstep(river_w, river_w + 4.0, d + (fbm(p * 0.08) - 0.5) * 4.0);
	float n = fbm(p * 0.05);
	vec3 ground = mix(sand_dark, sand, smoothstep(0.3, 0.7, n));
	// scrub and boulders as dark speckles, mud cracks near the water
	float scrub = step(0.82, fbm(p * 0.6));
	ground = mix(ground, vec3(0.32, 0.3, 0.16), scrub * 0.6);
	float crack = 1.0 - smoothstep(0.0, 0.06, abs(fract(fbm(p * 0.35) * 6.0) - 0.5));
	ground = mix(ground, sand_dark * 0.6, crack * (1.0 - smoothstep(river_w + 4.0, river_w + 18.0, d)) * 0.5);
	// water: deep in the middle, sun glitter and slow ripples drifting downstream
	float deep = 1.0 - smoothstep(0.0, river_w, d);
	vec3 w = mix(water * 1.3, water * 0.75, deep);
	float rip = noise2(vec2(p.x * 0.6, p.y * 0.25 + TIME * 0.6)) * noise2(vec2(p.x * 1.3 + 4.0, p.y * 0.5 - TIME * 0.4));
	float glint = smoothstep(0.55, 0.75, rip);
	w = mix(w, water_glint, glint * 0.5);
	vec3 col = mix(w, ground, bank);
	ALBEDO = col;
	ROUGHNESS = mix(0.15, 0.95, bank);
	METALLIC = 0.0;
	EMISSION = water_glint * glint * (1.0 - bank) * 0.6;
}
