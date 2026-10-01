shader_type spatial;
// Jungle Temple: canopy foliage on plain spheres. The surface is pushed in and out by world-space
// noise into leafy lumps, coloured from deep shade through mid green to sunlit leaf tips, and lit
// from behind a little where the sun shines through.

#include "res://visual/jungle_common.gdshaderinc"

uniform vec3 leaf_dark : source_color = vec3(0.07, 0.17, 0.06);
uniform vec3 leaf : source_color = vec3(0.18, 0.38, 0.11);
uniform vec3 leaf_light : source_color = vec3(0.44, 0.62, 0.2);
uniform float lump = 0.3;

varying vec3 wp;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = j_noise(w.xz * 0.35 + vec2(w.y * 0.2)) * 0.6 + j_noise(w.xy * 0.9 + vec2(3.0, w.z * 0.5)) * 0.4;
	VERTEX += NORMAL * (n - 0.5) * lump * 2.0;
	wp = w;
}

void fragment() {
	float n = j_fbm(wp.xz * 1.2 + vec2(wp.y * 0.7));
	float clump = smoothstep(0.32, 0.72, n);
	vec3 col = mix(leaf_dark, leaf, clump);
	col = mix(col, leaf_light, smoothstep(0.68, 0.9, j_noise(wp.xz * 3.5 + vec2(wp.y))) * clump);
	ALBEDO = col;
	ROUGHNESS = 0.82;
	BACKLIGHT = vec3(0.22, 0.38, 0.08);
}
