shader_type spatial;
// Castle Siege masonry: the walkable top is laid flagstone (irregular slabs with dark mortar and a
// bright worn edge line, the "trim"), the sides are staggered brick courses that darken toward the
// underside and soot-stain toward the bottom. Same parameters as platform.gdshader so Look's materials
// can be swapped one for one. Every term is bounded and NaN-safe (no pow of negatives, no division by
// a possibly-zero value, smoothstep edges in order).

uniform vec3 top_color : source_color = vec3(0.6, 0.58, 0.54);
uniform vec3 side_color : source_color = vec3(0.38, 0.36, 0.34);
uniform vec3 trim_color : source_color = vec3(0.85, 0.2, 0.15);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform float slab_size = 1.1;
uniform float brick_h = 0.34;
uniform float brick_w = 0.82;

varying vec3 lp;
varying vec3 ln;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	float rough = 0.85;
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// laid flagstones: offset every other row, hashed tone per slab, dark mortar lines
		vec2 g = lp.xz / max(slab_size, 0.1);
		float row = floor(g.y);
		g.x += 0.5 * mod(row, 2.0);
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float tone = hash21(cell + vec2(3.1, 9.7));
		float mortar = 1.0 - smoothstep(0.0, 0.05, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		col = top_color * (0.84 + 0.3 * tone);
		col = mix(col, top_color * 0.42, mortar * 0.7);
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim * 0.85);
		glow = trim;
		rough = 0.88;
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		rough = 0.95;
	} else {
		// staggered brick courses; the horizontal coordinate runs along whichever face this is
		float u = abs(ln.x) > abs(ln.z) ? lp.z : lp.x;
		float v = lp.y + half_size.y;
		float bh = max(brick_h, 0.08);
		float course = floor(v / bh);
		float x = u / max(brick_w, 0.1) + 0.5 * mod(course, 2.0);
		vec2 bc = vec2(floor(x), course);
		vec2 bf = vec2(fract(x), fract(v / bh));
		float tone = hash21(bc + vec2(7.3, 1.9));
		float mort = 1.0 - smoothstep(0.0, 0.07, min(min(bf.x, 1.0 - bf.x), min(bf.y, 1.0 - bf.y)));
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		col = mix(side_color * 0.55, side_color, smoothstep(0.0, 1.0, h));
		col *= 0.8 + 0.4 * tone;
		col = mix(col, side_color * 0.3, mort * 0.75);
		// the trim band just under the lip
		float band = smoothstep(0.14, 0.16, depth) * (1.0 - smoothstep(0.26, 0.28, depth));
		col = mix(col, trim_color * 0.85, band * 0.8);
		glow = band * 0.5;
		rough = 0.92;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = trim_color * glow * trim_glow;
}
