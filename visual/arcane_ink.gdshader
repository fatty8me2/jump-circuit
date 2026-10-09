shader_type spatial;
// Arcane ink: a glossy blue-black liquid that flows along local X. Slow folded waves catch a
// violet sheen, thin gold script (glints that look like handwriting) drifts along with the flow,
// and `agitation` (0..1, the tell and the surge) churns it: faster flow, brighter edges, foam.
// Opaque. NaN-safe: no pow() of negatives, no normalize(), smoothstep edges in order.

uniform vec3 ink_color : source_color = vec3(0.025, 0.02, 0.07);
uniform vec3 sheen_color : source_color = vec3(0.34, 0.2, 0.75);
uniform vec3 script_color : source_color = vec3(1.0, 0.78, 0.35);
uniform float flow = 1.0;
uniform float agitation = 0.0;
uniform float scale = 0.6;

varying vec3 wp;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = VERTEX;
}

void fragment() {
	float t = TIME;
	float spd = flow * (1.0 + 1.6 * clamp(agitation, 0.0, 1.0));
	vec2 p = vec2(wp.x * scale - t * spd * 0.55, wp.z * scale * 1.3);
	float w1 = vnoise(p * 1.7 + vec2(0.0, t * 0.25));
	float w2 = vnoise(p * 3.9 + vec2(11.3, -t * 0.4));
	float wave = w1 * 0.65 + w2 * 0.35;
	vec3 col = ink_color + sheen_color * smoothstep(0.55, 0.95, wave) * 0.55;
	// drifting handwriting: elongated glints along the flow
	vec2 sp = vec2(wp.x * scale * 2.2 - t * spd * 0.9, wp.z * scale * 7.0);
	float line = h21(floor(sp * vec2(0.35, 1.0)));
	float glyph = step(0.82, vnoise(sp * vec2(1.2, 0.5) + line * 13.0)) * step(0.6, line);
	col += script_color * glyph * (0.35 + 0.9 * clamp(agitation, 0.0, 1.0));
	// foam / churn when agitated
	float churn = smoothstep(0.6, 0.9, vnoise(p * 6.0 + vec2(t * 2.0, 3.0))) * clamp(agitation, 0.0, 1.0);
	col += sheen_color * churn * 0.8;
	ALBEDO = col;
	ROUGHNESS = 0.08;
	METALLIC = 0.35;
	SPECULAR = 0.9;
	EMISSION = col * 0.12 + sheen_color * churn * 0.35 + script_color * glyph * 0.25;
}
