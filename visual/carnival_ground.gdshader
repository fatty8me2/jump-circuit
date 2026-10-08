shader_type spatial;
render_mode unshaded, fog_disabled;
// Carnival Chaos: the fairground seen from far above at dusk. A plum-dark floor of packed earth with a
// grid of lit midway lanes: small bright cells of string-light colour (stalls, tents, ride footprints)
// scattered by a hash, with pale paths between them, all fading into the fog. Static; NaN-safe (no
// divide by zero, no pow of negatives), emission bounded (<= ~2).

uniform vec3 dirt : source_color = vec3(0.10, 0.045, 0.09);
uniform vec3 lane : source_color = vec3(0.30, 0.15, 0.17);
uniform float cell = 16.0;
uniform float fade_start = 140.0;
uniform float fade_end = 520.0;

varying vec3 wp;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = wp.xz / max(cell, 1.0);
	vec2 id = floor(g);
	vec2 f = fract(g);
	float h = hash12(id);
	vec3 col = dirt;
	// pale paths along the cell borders
	float path = 1.0 - smoothstep(0.04, 0.08, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	col = mix(col, lane, path);
	// a lit patch in most cells: a tent roof / stall seen from above, in a string-light colour
	vec2 q = abs(f - 0.5);
	float inside = 1.0 - smoothstep(0.26, 0.3, max(q.x, q.y));
	if (h > 0.25) {
		float k = fract(h * 7.0);
		vec3 tint = k < 0.33 ? vec3(1.0, 0.55, 0.2) : (k < 0.66 ? vec3(1.0, 0.3, 0.45) : vec3(1.0, 0.85, 0.4));
		float ring = 1.0 - smoothstep(0.0, 0.1, abs(length(f - 0.5) - 0.22));
		col = mix(col, tint * 0.55, inside * 0.9);
		col += tint * ring * 0.5 * step(0.55, h);
		col += tint * (1.0 - smoothstep(0.0, 0.07, length(f - 0.5))) * 0.8;
	}
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	ALBEDO = col;
	ALPHA = fade;
}
