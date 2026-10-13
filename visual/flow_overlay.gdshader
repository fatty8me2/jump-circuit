shader_type canvas_item;
render_mode unshaded, blend_mix;
// Flow meter screen layer (visual/flow_fx.gd): a soft vignette and radial speed lines. Both are 0..1
// strengths eased by the script; at 0 the layer is hidden. No texture reads, every divide guarded.

uniform float lines : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vig_color : source_color = vec4(0.02, 0.04, 0.10, 1.0);
uniform vec4 line_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float aspect = 1.78;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void fragment() {
	// -aspect..aspect across, -1..1 down; r = 0 at the centre, ~2 in the corners
	vec2 p = (UV - vec2(0.5)) * vec2(max(aspect, 0.5), 1.0) * 2.0;
	float r = length(p);

	float vig = smoothstep(0.6, 1.7, r) * clamp(vignette, 0.0, 1.0);

	float ang = atan(p.y, p.x + 0.00001) / 6.2831853 + 0.5;   // 0..1 around the screen
	float bins = 84.0;
	float cell = ang * bins;
	float id = floor(cell);
	float f = fract(cell);
	// each streak flickers on and off at its own pace, so the ring never looks like a fixed pattern
	float seed = hash11(id);
	float tick = floor(TIME * (3.0 + 4.0 * seed) + seed * 9.0);
	float on = step(0.68, hash11(id + tick * 13.0));
	float shape = 1.0 - smoothstep(0.0, 0.16, abs(f - 0.5));
	float inner = 0.85 + 0.5 * hash11(id + 7.0);
	float reach = smoothstep(inner, inner + 0.55, r);
	float ln = on * shape * reach * clamp(lines, 0.0, 1.0) * 0.55;

	float a = clamp(vig + ln, 0.0, 1.0);
	vec3 rgb = mix(vig_color.rgb, line_color.rgb, ln / max(vig + ln, 0.0001));
	COLOR = vec4(rgb, a);
}
