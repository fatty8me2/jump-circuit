shader_type spatial;
// Sky Surf: a floating island. It takes the same uniforms as visual/platform.gdshader (so the level can
// swap it onto every platform the kit built): a soft meadow top dotted with little flowers inside a
// pale rolled rim and a glowing pastel trim line, cream-to-rose sides banded like cloud strata, and a
// shaded underside. Bounded colours, no divides without a guard.

uniform vec3 top_color : source_color = vec3(1.0, 0.93, 0.85);
uniform vec3 side_color : source_color = vec3(0.8, 0.58, 0.76);
uniform vec3 trim_color : source_color = vec3(1.0, 0.7, 0.58);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 petal_a : source_color = vec3(1.0, 0.55, 0.62);
uniform vec3 petal_b : source_color = vec3(1.0, 0.88, 0.5);
uniform vec3 petal_c : source_color = vec3(0.98, 0.98, 1.0);

varying vec3 lp;
varying vec3 ln;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// a soft dappled meadow: two scales of value noise nudge the top colour
		float n = noise2(lp.xz * 0.9 + vec2(half_size.x, half_size.z)) * 0.6 + noise2(lp.xz * 2.7) * 0.4;
		col = top_color * (0.93 + 0.12 * n);
		// the pale rolled rim just inside the trim
		float rim = 1.0 - smoothstep(0.14, 0.62, edge);
		col = mix(col, vec3(1.0, 0.97, 0.93), rim * 0.55);
		// flowers: a sparse scatter of petals inside the rim (not on glowing goal decks)
		if (trim_glow < 1.5) {
			vec2 q = lp.xz / 0.8;
			vec2 cell = floor(q);
			float hs = hash12(cell + vec2(half_size.x * 7.0, half_size.z * 3.0));
			vec2 off = (vec2(hash12(cell * 1.7 + 3.1), hash12(cell * 2.3 + 7.7)) - 0.5) * 0.55;
			float dd = length(fract(q) - 0.5 - off);
			float fl = (1.0 - smoothstep(0.05, 0.1, dd)) * step(0.80, hs) * smoothstep(0.55, 0.9, edge);
			vec3 pc = hs > 0.93 ? petal_a : (hs > 0.87 ? petal_b : petal_c);
			col = mix(col, pc, fl);
		}
		float inner = smoothstep(trim_width, trim_width + 0.03, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.03, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = 0.82;
	} else if (ln.y < -0.6) {
		col = side_color * 0.6;
		ROUGHNESS = 0.9;
	} else {
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		col = mix(side_color * 0.66, side_color, smoothstep(0.0, 1.0, h));
		// the trim band under the lip, then cloud strata down the cliff
		float band = smoothstep(0.14, 0.17, depth) * (1.0 - smoothstep(0.26, 0.3, depth));
		col = mix(col, trim_color * 0.95, band * 0.8);
		glow = band * 0.5;
		float strata = noise2(vec2((lp.x + lp.z) * 0.6, depth * 3.2));
		col = mix(col, col * vec3(1.08, 1.0, 1.1), strata * 0.5 * step(0.35, depth));
		ROUGHNESS = 0.88;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow;
}
