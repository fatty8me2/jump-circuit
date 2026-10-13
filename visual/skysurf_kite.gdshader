shader_type spatial;
// Sky Surf: a kite and its tail of bows. Vertex colours carry the paint (rgb) and how loose the cloth
// is (alpha: 0 = rigid kite, 1 = free end of the tail), so the tail streams and flutters in the wind
// while the sail only rocks a little. A function of TIME only. Double sided, softly lit.
render_mode cull_disabled;

uniform float sway = 1.0;
uniform float seed = 0.0;

varying vec3 paint;

void vertex() {
	float w = COLOR.a;
	float t = clamp(-VERTEX.y * 0.12, 0.0, 1.5);
	VERTEX.x += sin(TIME * 2.3 + seed + VERTEX.y * 0.8) * 0.45 * w * t * sway;
	VERTEX.z += cos(TIME * 1.7 + seed + VERTEX.y * 0.6) * 0.3 * w * t * sway;
	VERTEX.z += sin(TIME * 1.3 + seed) * 0.08 * (1.0 - w) * VERTEX.y * sway;
	paint = COLOR.rgb;
}

void fragment() {
	ALBEDO = paint;
	EMISSION = paint * 0.18;
	ROUGHNESS = 0.75;
}
