shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Aurora Run: one rippling aurora curtain. A tall subdivided quad hung far out over the valley: the vertex
// shader folds it in slow travelling waves, the fragment paints a bright hem fading up through green, teal
// and blue into violet and magenta, with fine vertical rays that slide along it and slow brightness pulses.
// UV.x runs along the curtain, UV.y from the top (0) to the hem (1). `hue` slides the whole palette (0 = green
// hem, 1 = violet hem), `zen` swells the brightness. No divides, bounded output.

uniform vec3 hem_color : source_color = vec3(0.2, 1.0, 0.5);
uniform vec3 mid_color : source_color = vec3(0.1, 0.8, 0.95);
uniform vec3 top_color : source_color = vec3(0.75, 0.3, 1.0);
uniform float intensity = 1.0;
uniform float zen = 0.0;
uniform float fold = 40.0;
uniform float speed = 0.05;
uniform float seed = 0.0;
uniform float hue = 0.0;
uniform float ray_count = 150.0;

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
	float w = sin(UV.x * 7.0 + t * 6.0) * 0.55 + sin(UV.x * 19.0 - t * 9.0 + seed) * 0.3 + sin(UV.x * 41.0 + t * 14.0) * 0.15;
	VERTEX.z += w * fold * (0.3 + 0.7 * UV.y);
	VERTEX.x += sin(UV.y * 3.0 + t * 4.0) * fold * 0.12;
	VERTEX.y += sin(UV.x * 11.0 + t * 7.0) * fold * 0.05 * UV.y;
}

void fragment() {
	float t = TIME * speed + seed;
	float rays = noise1(uv.x * ray_count + t * 24.0) * 0.6 + noise1(uv.x * ray_count * 0.33 - t * 13.0) * 0.4;
	rays = rays * rays;
	float h = 1.0 - uv.y;
	float hem = smoothstep(0.0, 0.035, h) * (1.0 - smoothstep(0.035, 0.18, h));
	float body = smoothstep(0.0, 0.05, h) * exp(-h * 2.2);
	float ends = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	float pulse = 0.65 + 0.35 * sin(t * 22.0 + uv.x * 6.0 + noise1(uv.x * 4.0 + t) * 3.0);
	vec3 low_c = mix(hem_color, mid_color, clamp(hue, 0.0, 1.0));
	vec3 col = mix(low_c, mid_color, smoothstep(0.08, 0.4, h));
	col = mix(col, top_color, smoothstep(0.35, 0.9, h));
	float glow = body * (0.3 + 1.1 * rays) + hem * 0.7;
	ALBEDO = col * glow * ends * pulse * intensity * (1.0 + zen * 0.8);
}
