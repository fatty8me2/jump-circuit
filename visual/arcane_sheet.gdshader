shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// A curtain of golden sand held in the air (the closed hourglass gate): grains stream down it, a
// bright edge runs along the top and a soft wash fills it. `amount` 0..1 fades the whole sheet in
// and out (the warning ramps it up while the gate is still open). NaN-safe, HDR bounded.

uniform vec3 sand_color : source_color = vec3(1.0, 0.78, 0.32);
uniform float amount = 1.0;
uniform vec2 size = vec2(3.0, 3.0);

varying vec2 lp;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	lp = VERTEX.xy;
}

void fragment() {
	float a = clamp(amount, 0.0, 1.0);
	vec2 q = vec2((lp.x + size.x * 0.5) * 9.0, lp.y * 5.0 + TIME * 3.0);
	float cell = h21(floor(q));
	float grain = step(0.7, cell) * (1.0 - smoothstep(0.0, 0.5, length(fract(q) - 0.5)));
	float streak = smoothstep(0.3, 1.0, sin(lp.x * 11.0 + lp.y * 1.5 - TIME * 2.0) * 0.5 + 0.5) * 0.18;
	float wash = 0.22 + streak;
	float top = smoothstep(size.y * 0.5 - 0.35, size.y * 0.5, lp.y);
	float alpha = clamp((wash + grain * 0.8 + top * 0.5) * a, 0.0, 0.92);
	vec3 col = sand_color * (0.9 + 1.1 * grain + 0.8 * top);
	ALBEDO = min(col, vec3(2.4));
	ALPHA = alpha;
}
