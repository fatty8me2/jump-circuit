shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
// Lotus Drift's moving water: the stream slides and the little waterfalls. The mesh's UV.y runs
// DOWNSTREAM (0 at the head, `length_m` metres at the tail), UV.x across (0..1). Long streaks of
// foam and glints scroll downstream at `speed` m/s, faster toward the middle of the channel, with
// clear banks at the edges and a bright lip at the head. `fall` turns it into a vertical curtain
// (streaks stretch, edges feather). Nothing here reads a texture; every term is bounded.

uniform vec3 water_color : source_color = vec3(0.16, 0.6, 0.66);
uniform vec3 foam_color : source_color = vec3(0.9, 1.0, 1.0);
uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.4);
uniform float speed = 7.0;
uniform float length_m = 20.0;
uniform float width_m = 4.0;
uniform float alpha = 0.78;
uniform float fall = 0.0;

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

void fragment() {
	float u = clamp(UV.x, 0.0, 1.0);
	float s = UV.y * length_m;                       // metres downstream
	float x = (u - 0.5) * width_m;                   // metres across
	float mid = 1.0 - smoothstep(0.0, 1.0, abs(u - 0.5) * 2.0);
	float v = speed * (0.55 + 0.7 * mid);
	// stretched streaks: tall in the flow direction
	float st = noise2(vec2(x * 1.7, s * 0.28 - TIME * v * 0.28));
	float st2 = noise2(vec2(x * 3.9 + 5.0, s * 0.5 - TIME * v * 0.5));
	float foam = smoothstep(0.62, 0.9, st * 0.6 + st2 * 0.5);
	float glint = smoothstep(0.82, 0.97, st2) * mid;
	// the rills: slow dark and light bands crossing the channel
	float bands = 0.5 + 0.5 * sin(s * 0.9 - TIME * v * 0.9 + noise2(vec2(x, s * 0.1)) * 3.0);
	vec3 col = water_color * (0.75 + 0.35 * bands);
	col = mix(col, foam_color, foam * 0.8);
	col += glow_color * glint * 0.35;
	float edge = smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.86, 1.0, u));
	float head = smoothstep(0.0, 0.02, UV.y);
	float a = alpha * (0.45 + 0.55 * edge) * head;
	a = mix(a, a * (0.75 + 0.25 * foam), fall);
	a = clamp(a + foam * 0.15 * edge, 0.0, 0.95);
	ALBEDO = col;
	ALPHA = a;
}
