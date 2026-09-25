shader_type spatial;
// Scarab Sands oasis pools: clear turquoise water over pale sand, lazy ripples, a bright
// fresnel sheen and sun sparkles dancing on the surface.
render_mode cull_disabled;

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 shallow : source_color = vec3(0.3, 0.92, 0.85);
uniform vec3 deep : source_color = vec3(0.04, 0.45, 0.55);
uniform float radius = 4.0;

varying vec3 wp;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = wp.xz;
	float h1 = d_noise(p * 1.3 + vec2(t * 0.35, t * 0.2));
	float h2 = d_noise(p * 2.7 - vec2(t * 0.25, -t * 0.4));
	float h = h1 * 0.6 + h2 * 0.4;
	float dx = d_noise(p * 1.3 + vec2(t * 0.35 + 0.05, t * 0.2)) - h1;
	float dz = d_noise(p * 1.3 + vec2(t * 0.35, t * 0.2 + 0.05)) - h1;
	vec3 nw = normalize(vec3(-dx * 3.0, 1.0, -dz * 3.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float edge = clamp(length(lp.xz) / max(radius, 0.1), 0.0, 1.0);
	vec3 col = mix(deep, shallow, smoothstep(0.35, 1.0, edge) * 0.8 + h * 0.2);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
	ALBEDO = col;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	float spark = step(0.93, d_noise(p * 9.0 + vec2(t * 1.3, -t * 0.9))) * step(0.5, h);
	EMISSION = col * 0.25 + vec3(1.0, 0.95, 0.8) * spark * 1.5 + vec3(0.6, 0.9, 1.0) * fres * 0.25;
}
