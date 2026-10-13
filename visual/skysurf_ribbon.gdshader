shader_type spatial;
// Sky Surf: a wind ribbon. A long soft strip that ripples in the wind with bright pulses streaming
// along it in the direction of travel, fading out at both ends and along both edges. UV.x is the
// distance along the ribbon in metres, UV.y runs 0..1 across it. Unshaded and translucent; purely
// decorative, a function of TIME only. NaN-safe: every divide is guarded.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec3 color_a : source_color = vec3(1.0, 0.62, 0.7);
uniform vec3 color_b : source_color = vec3(1.0, 0.95, 0.8);
uniform float total = 40.0;
uniform float speed = 6.0;
uniform float wave = 0.35;
uniform float strength = 0.7;
uniform float phase = 0.0;

varying float along;
varying float across;

void vertex() {
	along = UV.x;
	across = UV.y;
	float ends = smoothstep(0.0, 4.0, UV.x) * (1.0 - smoothstep(max(total - 4.0, 0.0), max(total, 0.1), UV.x));
	VERTEX.y += sin(UV.x * 0.55 - TIME * 2.4 + phase) * wave * ends;
	VERTEX.x += cos(UV.x * 0.4 - TIME * 1.7 + phase * 1.7) * wave * 0.5 * ends;
}

void fragment() {
	float edge = 1.0 - abs(across * 2.0 - 1.0);
	float body = smoothstep(0.0, 0.45, edge);
	float pulse = 0.5 + 0.5 * sin(along * 0.55 - TIME * speed + phase);
	float fine = 0.5 + 0.5 * sin(along * 2.3 - TIME * speed * 1.7);
	float ends = smoothstep(0.0, 5.0, along) * (1.0 - smoothstep(max(total - 5.0, 0.0), max(total, 0.1), along));
	vec3 col = mix(color_a, color_b, pulse * 0.8 + fine * 0.2);
	ALBEDO = col * (1.0 + 0.5 * pulse);
	ALPHA = clamp(body * ends * strength * (0.45 + 0.55 * pulse), 0.0, 1.0);
}
