shader_type spatial;
// Storm Armada: an airship's gas envelope (decor, on a SphereMesh whose poles point fore and aft).
// Long gores in two alternating colours running nose to tail, stitched seams, a diamond rope net
// over the top half, a brass-studded belly band, and a faint wet sheen. Lightning (`flash`) lights
// the fabric from above.

uniform vec3 color_a : source_color = vec3(0.62, 0.2, 0.16);
uniform vec3 color_b : source_color = vec3(0.86, 0.78, 0.6);
uniform vec3 rope : source_color = vec3(0.35, 0.28, 0.2);
uniform float gores = 12.0;
uniform float flash = 0.0;

varying vec3 wn;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// UV.x goes round the long axis, UV.y from nose to tail
	vec3 ln = normalize(wn + vec3(0.0, 0.00001, 0.0));
	float g = UV.x * gores;
	float gi = mod(floor(g), 2.0);
	vec3 col = mix(color_a, color_b, gi);
	float fg = fract(g);
	float seam = 1.0 - smoothstep(0.0, 0.04, min(fg, 1.0 - fg));
	col *= 1.0 - 0.35 * seam;
	// the rope net: diamonds over the upper half (world up)
	vec2 n = vec2(UV.x * gores * 1.5, UV.y * 14.0);
	float d1 = abs(fract(n.x + n.y) - 0.5);
	float d2 = abs(fract(n.x - n.y) - 0.5);
	float net = (1.0 - smoothstep(0.0, 0.05, min(d1, d2)));
	float upper = smoothstep(-0.1, 0.3, ln.y);
	col = mix(col, rope, net * upper * 0.8);
	// a darker, weathered belly and ends
	float ends = smoothstep(0.35, 0.5, abs(UV.y - 0.5));
	col *= 1.0 - 0.3 * ends;
	col *= 0.75 + 0.25 * smoothstep(-0.8, 0.6, ln.y);
	ALBEDO = col;
	ROUGHNESS = 0.55 - 0.2 * upper;
	EMISSION = vec3(0.6, 0.7, 1.0) * clamp(flash, 0.0, 1.0) * 0.5 * smoothstep(0.0, 1.0, ln.y);
}
