shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// A waterfall sheet for Dino Valley's mesas: white water streaming down, brighter streaks racing
// ahead of a paler body, feathered at the lip and the foot. World-space streaks so a wide fall
// does not stretch. Bounded.

uniform vec3 tint : source_color = vec3(0.88, 0.96, 1.0);

varying vec3 wp;
varying vec3 lp;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = wp.x + wp.z;
	float s1 = vnoise(vec2(u * 2.2, wp.y * 0.35 + TIME * 4.5));
	float s2 = vnoise(vec2(u * 5.0 + 3.0, wp.y * 0.6 + TIME * 7.0));
	float a = 0.45 + 0.4 * s1 + 0.3 * s2;
	float edge = 1.0 - smoothstep(0.35, 0.5, abs(lp.x) / max(abs(lp.x) + 4.0, 0.001));
	ALBEDO = tint * (0.85 + 0.35 * s2);
	ALPHA = clamp(a * 0.8, 0.0, 0.92) * (0.6 + 0.4 * edge);
}
