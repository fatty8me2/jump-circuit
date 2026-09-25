shader_type spatial;
// Scarab Sands: the surface of a quicksand pool (DesertQuicksand). Slow swirling sand that
// drains toward a dimple in the middle; `pull` (0..1) deepens the swirl while someone sinks.

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 sand : source_color = vec3(0.86, 0.64, 0.38);
uniform vec3 wet : source_color = vec3(0.55, 0.36, 0.2);
uniform float pull = 0.0;
uniform float radius = 1.5;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
	float r = length(VERTEX.xz) / max(radius, 0.1);
	VERTEX.y -= (1.0 - smoothstep(0.0, 0.8, r)) * (0.04 + 0.22 * pull);
}

void fragment() {
	float t = TIME;
	float r = length(lp.xz) / max(radius, 0.1);
	float a = atan(lp.z, lp.x);
	float swirl = a + (1.0 - r) * (3.0 + 5.0 * pull) - t * (0.35 + 1.4 * pull);
	float bands = d_fbm(vec2(swirl * 1.6, r * 6.0 - t * 0.2));
	vec3 col = mix(wet, sand, smoothstep(0.25, 0.75, bands));
	col = mix(col, wet * 0.8, (1.0 - smoothstep(0.0, 0.45, r)) * (0.3 + 0.4 * pull));
	float grain = d_noise(lp.xz * 25.0 + vec2(t * 0.5, 0.0));
	ALBEDO = col * (0.92 + 0.12 * grain);
	ROUGHNESS = 0.97;
}
