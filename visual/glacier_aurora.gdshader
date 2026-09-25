shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Frostbite Pass: an aurora curtain. A tall subdivided quad hung far out over the pass;
// the vertex shader folds it like a drifting curtain, the fragment paints a bright green
// hem fading up into violet, with fine vertical rays sliding along it and slow pulses.
// UV.x runs along the curtain, UV.y from the top (0) to the hem (1).

uniform vec3 low_color : source_color = vec3(0.25, 1.0, 0.55);
uniform vec3 high_color : source_color = vec3(0.72, 0.35, 1.0);
uniform float intensity = 1.0;
uniform float fold = 20.0;
uniform float speed = 0.05;
uniform float seed = 0.0;

varying vec2 uv;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void vertex() {
	uv = UV;
	float t = TIME * speed + seed;
	float w = sin(UV.x * 9.0 + t * 6.0) * 0.6 + sin(UV.x * 23.0 - t * 9.0 + seed) * 0.4;
	VERTEX.z += w * fold * (0.35 + 0.65 * UV.y);
	VERTEX.x += sin(UV.y * 3.0 + t * 4.0) * fold * 0.15;
}

void fragment() {
	float t = TIME * speed + seed;
	float rays = noise1(uv.x * 160.0 + t * 24.0) * 0.6 + noise1(uv.x * 51.0 - t * 13.0) * 0.4;
	rays = rays * rays;
	float h = 1.0 - uv.y;
	float hem = smoothstep(0.0, 0.04, h) * (1.0 - smoothstep(0.04, 0.2, h));
	float body = smoothstep(0.0, 0.05, h) * exp(-h * 2.4);
	float ends = smoothstep(0.0, 0.15, uv.x) * smoothstep(1.0, 0.85, uv.x);
	float pulse = 0.6 + 0.4 * sin(t * 25.0 + uv.x * 7.0 + noise1(uv.x * 5.0 + t) * 3.0);
	vec3 col = mix(low_color, high_color, smoothstep(0.12, 0.75, h));
	ALBEDO = col * (body * (0.35 + 1.1 * rays) + hem * 0.6) * ends * pulse * intensity;
}
