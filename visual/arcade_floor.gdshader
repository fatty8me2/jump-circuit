shader_type spatial;
render_mode unshaded, cull_disabled;
// The screen far below Pixel Panic: a huge dot-matrix display seen from above. Every cell is a
// red / green / blue stripe triad; a low-resolution image of lit blocks (random palette colours that
// shuffle slowly in bands) is drawn across it and fades out with distance into the dark.
// Visual only. Bounded and NaN-safe.

uniform float cell = 8.0;
uniform float fade_dist = 480.0;

varying vec3 wp;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float c = max(cell, 0.5);
	vec2 g = wp.xz / c;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float n = h21(id);
	float lit = step(0.72, n);
	vec3 hue = vec3(0.1, 0.9, 1.0);
	float pick = h21(id + vec2(5.0, 9.0));
	hue = mix(hue, vec3(1.0, 0.2, 0.7), step(0.33, pick));
	hue = mix(hue, vec3(1.0, 0.9, 0.15), step(0.66, pick));
	// the RGB triad stripes inside each cell
	float stripe = floor(f.x * 3.0);
	vec3 tri = vec3(step(abs(stripe), 0.5), step(abs(stripe - 1.0), 0.5), step(abs(stripe - 2.0), 0.5));
	float gap = step(0.08, f.y) * step(f.y, 0.92);
	vec3 col = mix(vec3(0.015, 0.012, 0.03), hue * 0.7, lit) * (0.35 + 0.65 * tri) * gap;
	col += vec3(0.02, 0.015, 0.05);
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_dist * 0.2, fade_dist, d);
	ALBEDO = col * fade;
}
