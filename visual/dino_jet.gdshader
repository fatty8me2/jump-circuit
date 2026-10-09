shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Dino Valley geyser column: a roaring jet of white water, streaks racing up its skin and a soft
// fresnel rim. `power` (0..1) grows it in and out, `height` is the column's length so the top
// feathers away into spray. Everything is bounded (no divide by zero, no pow of a negative).

uniform vec3 tint : source_color = vec3(0.86, 0.95, 1.0);
uniform float power = 1.0;
uniform float height = 6.0;
uniform float speed = 1.8;
uniform float warm = 0.0;

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
}

void fragment() {
	float h = clamp((lp.y + height * 0.5) / max(height, 0.1), 0.0, 1.0);
	float ang = atan(lp.z, lp.x + 0.0001);
	float t = TIME * speed;
	float streak = vnoise(vec2(ang * 2.4, h * height * 0.55 - t * 3.0));
	float streak2 = vnoise(vec2(ang * 5.1 + 7.0, h * height * 0.9 - t * 4.6));
	float body = 0.34 + 0.5 * streak + 0.3 * streak2;
	float rim = 1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fade = smoothstep(0.0, 0.08, h) * (1.0 - smoothstep(0.72, 1.0, h));
	float a = clamp(body * (0.55 + 0.9 * rim) * fade * power, 0.0, 0.92);
	vec3 col = mix(tint, vec3(1.0, 0.93, 0.78), warm) * (0.9 + 0.5 * streak2);
	ALBEDO = min(col, vec3(1.6));
	ALPHA = a;
}
