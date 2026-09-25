shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Frostbite Pass: the leading edge of a blizzard gust - a wall of blown snow racing across
// a stage. Billowing noise sheets streaming along the sheet, fine horizontal streaks,
// soft edges all round. `strength` fades the whole sheet in and out.

uniform vec4 tint : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform float strength = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 p = vec2(UV.x * 5.0 + seed, UV.y * 2.5);
	float n = noise(p + vec2(TIME * 1.3, TIME * 0.4)) * 0.6 + noise(p * 2.6 - vec2(TIME * 2.1, 0.0)) * 0.4;
	float streak = noise(vec2(UV.x * 3.0 - TIME * 4.0, UV.y * 55.0 + seed));
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x) * smoothstep(1.0, 0.75, UV.y) * smoothstep(0.0, 0.35, UV.y);
	ALBEDO = tint.rgb;
	ALPHA = clamp((smoothstep(0.35, 0.8, n) * 0.75 + streak * streak * 0.4) * edge * strength, 0.0, 0.85);
}
