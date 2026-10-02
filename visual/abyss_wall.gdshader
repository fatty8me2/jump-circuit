shader_type spatial;
// The Abyss: the trench walls and scenery rock (never walkable). Near-black basalt in world space,
// ribbed and pitted, speckled with sparse spots of bioluminescent growth that breathe slowly - so
// the walls of the trench show as a starry darkness rather than a lit surface. Bounded emission.

uniform vec3 rock : source_color = vec3(0.05, 0.07, 0.09);
uniform vec3 glow_a : source_color = vec3(0.1, 1.0, 0.8);
uniform vec3 glow_b : source_color = vec3(0.7, 0.35, 1.0);
uniform float spots = 0.6;

varying vec3 wp;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = noise(wp * 0.35) * 0.6 + noise(wp * 1.3) * 0.4;
	float ribs = 0.5 + 0.5 * sin(wp.y * 1.7 + n * 4.0);
	vec3 col = rock * (0.6 + 0.6 * n) * (0.8 + 0.3 * ribs);
	// spots of glowing growth on a coarse lattice
	vec3 cell = floor(wp * 0.9);
	vec3 f = fract(wp * 0.9) - 0.5;
	float h = hash(cell);
	float spot = (1.0 - smoothstep(0.06, 0.16, length(f))) * step(1.0 - 0.06 * spots, h);
	float breathe = 0.6 + 0.4 * sin(TIME * (0.3 + h) + h * 30.0);
	vec3 g = mix(glow_a, glow_b, step(0.5, fract(h * 7.0)));
	ALBEDO = col;
	ROUGHNESS = 0.92;
	EMISSION = clamp(g * spot * breathe * 1.4, vec3(0.0), vec3(3.0));
}
