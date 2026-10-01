// Jungle Temple shared shader helpers: hash noise, fbm, stone courses, carved glyph bands.
// Everything here is bounded (no pow of negatives, no normalize of zero vectors).

float j_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float j_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(j_hash12(i), j_hash12(i + vec2(1.0, 0.0)), f.x),
		mix(j_hash12(i + vec2(0.0, 1.0)), j_hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float j_fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * j_noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// Staggered stone courses: x = distance to the nearest joint (0 on a joint), y = per-block shade 0..1.
vec2 j_courses(vec2 p, vec2 block) {
	float row = floor(p.y / block.y);
	float off = mod(row, 2.0) * 0.5;
	vec2 q = vec2(p.x / block.x + off, p.y / block.y);
	vec2 f = fract(q);
	vec2 cell = floor(q);
	float d = min(min(f.x, 1.0 - f.x) * block.x, min(f.y, 1.0 - f.y) * block.y);
	return vec2(d, j_hash12(cell + 3.1));
}

// A band of carved glyph cells along u (cell size `cell`, band height ~cell): x = carved (0..1),
// y = a per-cell random 0..1 (which inlay colour / whether it is inlaid).
vec2 j_glyph_band(vec2 p, float cell) {
	vec2 c = vec2(floor(p.x / cell), 0.0);
	vec2 f = vec2(fract(p.x / cell), clamp(p.y / cell, 0.0, 1.0)) - 0.5;
	float h = j_hash12(c + 7.7);
	float carve = 0.0;
	// a ring, a cross, or stacked bars, depending on the cell
	float r = length(f);
	if (h < 0.33) {
		carve = 1.0 - smoothstep(0.03, 0.06, abs(r - 0.28));
		carve = max(carve, 1.0 - smoothstep(0.05, 0.08, r));
	} else if (h < 0.66) {
		carve = max(1.0 - smoothstep(0.04, 0.07, abs(f.x)), 1.0 - smoothstep(0.04, 0.07, abs(f.y)));
		carve *= 1.0 - smoothstep(0.32, 0.36, max(abs(f.x), abs(f.y)));
	} else {
		float bars = 1.0 - smoothstep(0.03, 0.06, abs(fract(f.y * 3.0 + 0.5) - 0.5) * 0.33);
		carve = bars * (1.0 - smoothstep(0.3, 0.34, abs(f.x))) * (1.0 - smoothstep(0.38, 0.42, abs(f.y)));
	}
	// the cell's frame
	float frame = 1.0 - smoothstep(0.02, 0.05, 0.46 - max(abs(f.x), abs(f.y)));
	return vec2(clamp(max(carve, frame * 0.7), 0.0, 1.0), j_hash12(c + 1.3));
}
