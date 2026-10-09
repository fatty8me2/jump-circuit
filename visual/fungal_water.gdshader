shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Mushroom Hollow: a sunlit forest stream seen from above. Clear blue-green water drifting along the
// plane's local +X (UV.x), with soft light ripples and sun glints sliding over it, pale foam along
// both banks (UV.y 0 and 1) and a darker deep middle. Unlit emission is bounded (< 1.6).

uniform vec3 shallow : source_color = vec3(0.34, 0.74, 0.72);
uniform vec3 deep : source_color = vec3(0.12, 0.42, 0.52);
uniform vec3 foam : source_color = vec3(0.92, 0.98, 0.95);
uniform float flow_speed = 0.35;
uniform float tiles = 14.0;

varying vec2 wuv;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wuv = UV;
}

void fragment() {
	vec2 p = vec2(wuv.x * tiles - TIME * flow_speed * 3.0, wuv.y * tiles * 0.35);
	float r1 = noise2(p * 1.7);
	float r2 = noise2(p * 3.9 + vec2(-TIME * 0.7, 3.0));
	float ripple = r1 * 0.6 + r2 * 0.4;
	float mid = 1.0 - abs(wuv.y * 2.0 - 1.0);
	vec3 col = mix(shallow, deep, smoothstep(0.1, 0.9, mid) * 0.8);
	col = mix(col, col * 1.25 + vec3(0.04, 0.06, 0.05), smoothstep(0.55, 0.85, ripple) * 0.6);
	// glints
	float glint = smoothstep(0.84, 0.95, noise2(p * 5.3 + vec2(TIME * 1.1, 7.0)));
	// foam at the banks
	float bank = 1.0 - smoothstep(0.0, 0.07 + 0.04 * noise2(p * 2.0), min(wuv.y, 1.0 - wuv.y));
	col = mix(col, foam, bank * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	EMISSION = vec3(1.0, 0.95, 0.8) * glint * 0.9 + col * 0.12;
}
