shader_type spatial;
// Scarab Sands dunes and the sand sea: warm sand with wind ripples that bend round the dune,
// darker troughs, and tiny glints of quartz that sparkle in the low sun.

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 sand : source_color = vec3(0.95, 0.74, 0.46);
uniform vec3 shade : source_color = vec3(0.72, 0.46, 0.28);
uniform float ripple_scale = 1.6;
uniform float sparkle = 1.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float warp = d_fbm(wp.xz * 0.02) * 12.0;
	float r = sin((wp.x * 0.8 + wp.z * 0.35 + warp) * ripple_scale) * 0.5 + 0.5;
	float big = d_fbm(wp.xz * 0.006 + vec2(4.0, 1.0));
	vec3 col = mix(shade, sand, smoothstep(0.15, 0.85, big));
	col *= 0.9 + 0.1 * r;
	// steeper faces (slip faces) a touch darker and redder
	col = mix(col, shade * 0.9, smoothstep(0.75, 0.35, wn.y) * 0.5);
	// quartz glints
	float g = step(0.985, d_hash21(floor(wp.xz * 6.0))) * sparkle;
	vec3 v = normalize(VIEW);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	EMISSION = vec3(1.0, 0.9, 0.7) * g * 0.6 * smoothstep(0.2, 0.9, dot(v, NORMAL));
}
