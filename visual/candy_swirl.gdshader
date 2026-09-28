shader_type spatial;
// Sugar Rush: a lollipop / peppermint swirl. A spiral of `arms` bands winding out from the centre
// of the mesh's local XZ plane (a flat cylinder is a lollipop disc or a peppermint wheel; a sphere
// becomes a round swirled sucker). The rim of a disc gets plain stripes. Glossy boiled sugar.

uniform vec3 color_a : source_color = vec3(1.0, 0.25, 0.45);
uniform vec3 color_b : source_color = vec3(1.0, 0.97, 0.95);
uniform float arms = 3.0;
uniform float turns = 1.6;
uniform float radius = 1.0;
uniform float gloss = 0.15;
uniform float glow = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = lp.xz;
	float r = length(q) / max(radius, 0.001);
	// atan(0, 0) is undefined on some drivers: give the exact centre a fixed angle
	float a = r > 0.0001 ? atan(q.y, q.x) : 0.0;
	float x = a / 6.2831853 * arms + r * turns * arms;
	float s = fract(x);
	float e = clamp(fwidth(x) * 1.2, 0.002, 0.2);
	float d = abs(s - 0.5);
	float m = 1.0 - smoothstep(0.25 - e, 0.25 + e, d);
	vec3 col = mix(color_b, color_a, m);
	// a pale sugary highlight toward the middle
	col = mix(col, vec3(1.0), (1.0 - smoothstep(0.0, 0.25, r)) * 0.12);
	ALBEDO = col;
	ROUGHNESS = gloss;
	SPECULAR = 0.7;
	CLEARCOAT = 0.6;
	CLEARCOAT_ROUGHNESS = 0.1;
	EMISSION = col * glow;
}
