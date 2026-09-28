shader_type spatial;
// Sugar Rush: candy-cane stripes. Spiral bands round a cylinder: UV.x runs round it, and the
// twist climbs with UV.y (or with world height, for meshes stretched by their transform). Glossy
// hard candy with a soft sheen.

uniform vec3 color_a : source_color = vec3(1.0, 0.2, 0.3);
uniform vec3 color_b : source_color = vec3(1.0, 0.97, 0.95);
uniform float stripes = 3.0;
uniform float twist = 1.0;
uniform bool world_twist = false;
uniform float gloss = 0.22;
uniform float glow = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float v = world_twist ? wp.y * twist : UV.y * twist;
	float x = UV.x * stripes + v;
	float s = fract(x);
	float e = clamp(fwidth(x) * 1.2, 0.002, 0.2);
	float d = abs(s - 0.5);
	float m = 1.0 - smoothstep(0.25 - e, 0.25 + e, d);
	vec3 col = mix(color_b, color_a, m);
	ALBEDO = col;
	ROUGHNESS = gloss;
	SPECULAR = 0.65;
	EMISSION = col * glow;
}
