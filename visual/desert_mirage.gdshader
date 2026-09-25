shader_type spatial;
// Scarab Sands: a mirage platform (DesertMirage). Sun-gold sandstone with a turquoise rim
// that wavers in the heat: `shimmer` sets how hard it wobbles and flickers (building up
// before it fades), `solidity` how real it looks (1 solid, ~0.12 a faint heat ghost).
render_mode cull_back, depth_prepass_alpha;

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.98, 0.84, 0.55);
uniform vec3 side_color : source_color = vec3(0.8, 0.58, 0.34);
uniform vec3 rim_color : source_color = vec3(0.3, 1.0, 0.92);
uniform vec3 half_size = vec3(1.0, 0.25, 1.0);
uniform float solidity = 1.0;
uniform float shimmer = 0.0;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	float t = TIME;
	float w = shimmer * (0.05 + 0.1 * (1.0 - solidity));
	VERTEX.x += sin(VERTEX.y * 9.0 + VERTEX.z * 2.0 + t * 11.0) * w;
	VERTEX.z += sin(VERTEX.y * 7.0 + VERTEX.x * 2.5 + t * 9.0) * w;
	VERTEX.y += sin(VERTEX.x * 3.0 + t * 7.0) * w * 0.4;
}

void fragment() {
	float t = TIME;
	vec3 col;
	float rim = 0.0;
	if (ln.y > 0.6) {
		vec2 d = half_size.xz - abs(lp.xz);
		float edge = min(d.x, d.y);
		col = top_color * (0.92 + 0.1 * d_noise(lp.xz * 3.0));
		rim = 1.0 - smoothstep(0.06, 0.16, edge);
	} else {
		col = side_color * (0.85 + 0.15 * d_noise(lp.xy * 4.0 + lp.zy * 4.0));
		rim = 1.0 - smoothstep(0.03, 0.1, half_size.y - abs(lp.y));
	}
	// heat bands climbing through it
	float bands = smoothstep(0.6, 1.0, sin(lp.y * 18.0 - t * 6.0 + lp.x * 2.0) * 0.5 + 0.5);
	float flick = 0.75 + 0.25 * sin(t * 37.0 + lp.x * 3.0);
	ALBEDO = mix(col, rim_color, rim * 0.7);
	EMISSION = rim_color * rim * (0.8 + 1.6 * shimmer) * flick + top_color * bands * shimmer * 0.6 + rim_color * (1.0 - solidity) * 0.5;
	ALPHA = clamp(solidity * (1.0 - 0.3 * shimmer * bands), 0.0, 1.0);
	ROUGHNESS = 0.8;
}
