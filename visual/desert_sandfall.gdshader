shader_type spatial;
// Scarab Sands: a curtain of pouring sand (DesertSandfall). UV.y runs 0 at the ceiling slot to
// 1 at the floor. The sand fills [tail, head] of the sheet: `head` races down when the pour
// starts, `tail` follows it down when it stops. `trickle` 0..1 shows thin warning streams.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

#include "res://visual/desert_common.gdshaderinc"

uniform vec3 sand : source_color = vec3(0.95, 0.76, 0.48);
uniform vec3 dark : source_color = vec3(0.62, 0.42, 0.24);
uniform float head = 0.0;
uniform float tail = 0.0;
uniform float trickle = 0.0;
uniform float width = 3.0;
uniform float height = 6.0;
uniform float speed = 9.0;

void fragment() {
	float t = TIME;
	float x = UV.x * width;
	float y = UV.y * height;
	// streaks: columns of noise stretched down the fall, scrolling fast
	float s1 = d_noise(vec2(x * 7.0, (y - t * speed) * 0.35));
	float s2 = d_noise(vec2(x * 15.0 + 3.0, (y - t * speed * 1.3) * 0.6));
	float dens = s1 * 0.6 + s2 * 0.4;
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	float fill = smoothstep(tail - 0.02, tail + 0.03, UV.y) * smoothstep(head + 0.02, head - 0.03, UV.y);
	float a = fill * edge * (0.55 + 0.6 * dens);
	// warning trickle: a few thin streams
	float cols = step(0.86, d_hash21(vec2(floor(x * 3.0), 1.0)));
	float thin = cols * (1.0 - smoothstep(0.02, 0.06, abs(fract(x * 3.0) - 0.5) * 0.33)) * (0.5 + 0.5 * s2);
	a = max(a, thin * trickle * edge);
	vec3 col = mix(dark, sand, 0.35 + 0.65 * dens);
	// a splash-brightened foot
	col = mix(col, sand * 1.15, smoothstep(0.85, 1.0, UV.y) * 0.5);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
