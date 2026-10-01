shader_type spatial;
// Wild West Heist walkable wood: the platform shader's layout (bright top, inset trim line marking the
// landing's edge, darker sides) re-done as sun-bleached railroad timber. Tops are planks running along
// the longer side, each its own weathered shade, with staggered butt joints and nail heads; a painted
// trim line marks every edge you can stand on. Sides are boards in the side colour (vertical boards on
// tall car bodies, horizontal planks on decks), with iron straps, and an X-brace on small crates.
// Same uniforms as visual/platform.gdshader, so the level can swap it in. No pow() of negatives, no
// normalize() of zero, smoothstep edges in order: NaN-safe.

uniform vec3 top_color : source_color = vec3(0.56, 0.4, 0.26);
uniform vec3 side_color : source_color = vec3(0.66, 0.36, 0.22);
uniform vec3 trim_color : source_color = vec3(0.95, 0.8, 0.3);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
// 0 = auto, 1 = crate (X-braced sides), 2 = car body (vertical boards), 3 = plain planks
uniform int kind = 0;

varying vec3 lp;
varying vec3 ln;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

// grain streaks along u, planks across v (both in metres)
vec3 planks(vec2 uv, float width, vec3 base, out float gap) {
	float row = floor(uv.y / width);
	float fy = fract(uv.y / width);
	float seg_len = 2.4 + hash11(row * 7.13) * 2.2;
	float u = uv.x + hash11(row * 3.7) * 5.0;
	float seg = floor(u / seg_len);
	float fx = fract(u / seg_len);
	float shade = 0.82 + 0.3 * hash12(vec2(row, seg));
	float grain = noise2(vec2(u * 0.7, uv.y * 14.0)) * 0.5 + noise2(vec2(u * 3.0, uv.y * 40.0)) * 0.25;
	vec3 c = base * shade * (0.86 + 0.24 * grain);
	float edge_y = min(fy, 1.0 - fy) * width;
	float edge_x = min(fx, 1.0 - fx) * seg_len;
	gap = 1.0 - smoothstep(0.0, 0.025, min(edge_y, edge_x));
	// nail heads near each butt joint
	vec2 nail = vec2(edge_x, abs(fy - 0.5) * width);
	float n = 1.0 - smoothstep(0.015, 0.03, length(nail - vec2(0.09, width * 0.28)));
	c = mix(c, vec3(0.12, 0.11, 0.1), n * 0.8);
	return mix(c, c * 0.35, gap);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	int k = kind;
	if (k == 0) {
		float big = max(half_size.x, half_size.z);
		k = big < 1.35 ? 1 : (half_size.y > 0.9 ? 2 : 3);
	}
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		float gap;
		vec2 uv = half_size.z >= half_size.x ? lp.zx : lp.xz;
		col = planks(uv, 0.3, top_color, gap);
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = 0.82;
	} else if (ln.y < -0.6) {
		col = side_color * 0.4;
		ROUGHNESS = 0.95;
	} else {
		// side faces: u runs along the face, y up
		float u = abs(ln.x) > 0.5 ? lp.z : lp.x;
		float hu = abs(ln.x) > 0.5 ? half_size.z : half_size.x;
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		float gap;
		if (k == 2) {
			col = planks(vec2(lp.y * 0.6 + hu, u + 9.0), 0.28, side_color, gap);
		} else {
			col = planks(vec2(u, lp.y + 7.0), 0.26, side_color, gap);
		}
		col *= mix(0.62, 1.0, smoothstep(0.0, 0.6, h));
		// a painted trim band just under the walkable edge
		float band = smoothstep(0.1, 0.12, depth) * (1.0 - smoothstep(0.2, 0.22, depth));
		col = mix(col, trim_color * 0.85, band * 0.8);
		glow = band * 0.5;
		// iron straps
		float strap = 0.0;
		if (k == 1) {
			// a crate: frame round each face and an X-brace across it
			float fu = abs(u) / max(hu, 0.001);
			float fv = abs(lp.y) / max(half_size.y, 0.001);
			float frame = step(0.86, max(fu, fv));
			vec2 q = vec2(u / max(hu, 0.001), lp.y / max(half_size.y, 0.001));
			float x1 = abs(q.x - q.y) * 0.7071;
			float x2 = abs(q.x + q.y) * 0.7071;
			float brace = 1.0 - smoothstep(0.07, 0.09, min(x1, x2));
			col = mix(col, side_color * 0.8, max(frame, brace) * 0.9);
			col *= 1.0 - 0.25 * max(frame, brace);
		} else {
			strap = (1.0 - smoothstep(0.04, 0.06, abs(depth - 0.35))) + (1.0 - smoothstep(0.04, 0.06, abs(h - 0.06) * 2.0 * half_size.y));
			col = mix(col, vec3(0.12, 0.11, 0.1), clamp(strap, 0.0, 1.0) * 0.85);
		}
		ROUGHNESS = 0.88;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow;
}
