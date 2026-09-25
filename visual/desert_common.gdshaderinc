// Scarab Sands: noise, block courses and carved glyphs shared by the desert shaders.

float d_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 d_hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float d_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = d_hash21(i);
	float b = d_hash21(i + vec2(1.0, 0.0));
	float c = d_hash21(i + vec2(0.0, 1.0));
	float d = d_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float d_fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * d_noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// Staggered ashlar courses: x = distance to the nearest joint (0 at a joint), y = block id hash.
vec2 d_courses(vec2 p, vec2 block) {
	float row = floor(p.y / block.y);
	float x = p.x / block.x + (mod(row, 2.0) * 0.5);
	vec2 f = vec2(fract(x), fract(p.y / block.y));
	float edge = min(min(f.x, 1.0 - f.x) * block.x, min(f.y, 1.0 - f.y) * block.y);
	return vec2(edge, d_hash21(vec2(floor(x), row)));
}

// One carved glyph in a unit cell (p in -1..1). Returns the carved mask 0..1.
float d_glyph(vec2 p, float h) {
	float r = length(p);
	float w = 0.09;
	float m = 0.0;
	if (h < 0.14) {
		// sun disc with a ring
		m = max(1.0 - smoothstep(0.2, 0.26, r), 1.0 - smoothstep(w * 0.5, w, abs(r - 0.55)));
	} else if (h < 0.28) {
		// the eye: an almond outline and an iris
		float e = abs(p.y) - 0.34 * (1.0 - p.x * p.x / 0.72);
		m = (1.0 - smoothstep(w * 0.5, w, abs(e))) * step(abs(p.x), 0.85);
		m = max(m, 1.0 - smoothstep(0.14, 0.2, r));
		m = max(m, (1.0 - smoothstep(w * 0.4, w * 0.8, abs(p.y - 0.62 + 0.2 * p.x * p.x))) * step(abs(p.x), 0.7));
	} else if (h < 0.42) {
		// water: three zig-zag lines
		float z = abs(fract(p.x * 2.5) - 0.5) * 0.35;
		for (int i = 0; i < 3; i++) {
			float y0 = -0.45 + float(i) * 0.45;
			m = max(m, 1.0 - smoothstep(w * 0.4, w * 0.8, abs(p.y - y0 - z)));
		}
		m *= step(abs(p.x), 0.85);
	} else if (h < 0.56) {
		// ankh: loop on a cross
		float loop = 1.0 - smoothstep(w * 0.5, w, abs(length((p - vec2(0.0, 0.42)) * vec2(1.0, 0.8)) - 0.28));
		float stem = (1.0 - smoothstep(w * 0.6, w * 1.1, abs(p.x))) * step(p.y, 0.15) * step(-0.9, p.y);
		float bar = (1.0 - smoothstep(w * 0.6, w * 1.1, abs(p.y - 0.05))) * step(abs(p.x), 0.5);
		m = max(max(loop, stem), bar);
	} else if (h < 0.7) {
		// a bird in profile: body, head and tail wedges
		float body = 1.0 - smoothstep(0.9, 1.0, length((p - vec2(0.0, -0.1)) * vec2(1.7, 2.6)));
		float head = 1.0 - smoothstep(0.12, 0.18, length(p - vec2(0.42, 0.28)));
		float leg = (1.0 - smoothstep(w * 0.4, w * 0.8, abs(p.x - 0.05))) * step(-0.8, p.y) * step(p.y, -0.3);
		m = max(max(body, head), leg);
	} else if (h < 0.84) {
		// scarab: oval body with a split, a sun disc held over its head
		float body = abs(length(p * vec2(1.6, 1.15) - vec2(0.0, -0.15)) - 0.5);
		m = 1.0 - smoothstep(w * 0.5, w, body);
		m = max(m, (1.0 - smoothstep(w * 0.3, w * 0.6, abs(p.x))) * step(p.y, 0.25) * step(-0.65, p.y));
		m = max(m, 1.0 - smoothstep(0.14, 0.19, length(p - vec2(0.0, 0.66))));
	} else {
		// reed pair (two stems with leaf tips)
		for (int i = 0; i < 2; i++) {
			float x0 = -0.22 + float(i) * 0.44;
			float stem = (1.0 - smoothstep(w * 0.4, w * 0.8, abs(p.x - x0))) * step(abs(p.y), 0.7);
			float leaf = 1.0 - smoothstep(0.1, 0.16, length((p - vec2(x0 + 0.12, 0.58)) * vec2(1.0, 0.55)));
			m = max(m, max(stem, leaf));
		}
	}
	return clamp(m, 0.0, 1.0);
}

// A band of carved glyph columns over `p` (cell size `cell`). x = carved mask, y = cell hash.
vec2 d_glyph_band(vec2 p, float cell) {
	vec2 c = floor(p / cell);
	vec2 f = fract(p / cell) * 2.0 - 1.0;
	float h = d_hash21(c + vec2(3.1, 7.7));
	return vec2(d_glyph(f * 1.15, h), d_hash21(c + vec2(11.0, 5.0)));
}
