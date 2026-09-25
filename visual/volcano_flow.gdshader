shader_type spatial;
// Cinder Peak flowing lava: falls, curtains and rivers drawn on a quad or ribbon whose UV.y
// runs downstream (0 = source). Streaky churning melt racing along V, darker crust skins
// riding the edges, a white-hot core, soft ragged side edges. `size` is the quad's size in
// metres so the streaks keep their scale on any fall. `cut_top` / `cut_bottom` (0..1 of
// the length) hide the part not yet poured / already drained, with a bright ragged front.

render_mode cull_disabled, shadows_disabled;

uniform vec2 size = vec2(3.0, 10.0);
uniform float speed = 6.0;
uniform float heat = 1.0;
uniform float cut_top : hint_range(0.0, 1.0) = 0.0;
uniform float cut_bottom : hint_range(0.0, 1.0) = 1.0;
uniform float edge_soft = 0.22;
uniform vec3 hot_color : source_color = vec3(1.0, 0.55, 0.12);
uniform vec3 white_hot : source_color = vec3(1.0, 0.9, 0.5);
uniform vec3 crust_color : source_color = vec3(0.12, 0.05, 0.03);

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 m = vec2(UV.x * size.x, UV.y * size.y);
	float t = TIME * speed;
	// streaks: noise stretched along the flow, scrolled downstream at two rates
	float s1 = vnoise(vec2(m.x * 2.2, m.y * 0.25 - t * 0.25));
	float s2 = vnoise(vec2(m.x * 4.5 + 7.0, m.y * 0.5 - t * 0.42));
	float s3 = vnoise(vec2(m.x * 1.1 + 3.0, m.y * 0.12 - t * 0.12));
	float streak = s1 * 0.5 + s2 * 0.3 + s3 * 0.35;
	float across = abs(UV.x - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 0.75, across);
	float skin = smoothstep(0.55, 0.85, streak + across * 0.45);
	vec3 melt = mix(hot_color, white_hot, clamp(core * 0.7 + (streak - 0.5) * 1.2, 0.0, 1.0));
	vec3 col = mix(melt, crust_color, skin * 0.85);
	// ragged side edges and the pour front / tail
	float side = 1.0 - smoothstep(1.0 - edge_soft - 0.12 * s2, 1.0 - 0.05 * s1, across);
	float rag = (s2 - 0.5) * 0.04;
	float vis = step(cut_top + rag, UV.y) * step(UV.y, cut_bottom + rag);
	float front = (1.0 - smoothstep(0.0, 0.04, abs(UV.y - cut_bottom - rag))) * step(cut_bottom, 0.999);
	ALBEDO = col * 0.35;
	EMISSION = (melt * (1.0 - skin * 0.85) * 2.2 + white_hot * front * 2.5) * heat;
	ALPHA = side * vis;
	ROUGHNESS = 0.5;
}
