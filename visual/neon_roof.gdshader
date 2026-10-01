shader_type spatial;
// Neon City walkable surface: the platform shader's layout (top, inset trim, darker sides) re-done
// as a rain-soaked city rooftop. Tops are dark tar-and-concrete slabs with expansion joints, gloss
// everywhere and real standing puddles (near-mirror roughness, so the signs reflect in them) that
// ripple with rain drops; the trim is a neon tube round the edge. Sides are wet concrete with a lit
// neon band under the lip and dark rain streaks running down. Same uniforms as
// visual/platform.gdshader so the level can swap it in. Bounded and NaN-safe.

uniform vec3 top_color : source_color = vec3(0.26, 0.26, 0.32);
uniform vec3 side_color : source_color = vec3(0.12, 0.12, 0.16);
uniform vec3 trim_color : source_color = vec3(1.0, 0.2, 0.7);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;

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

// expanding rain ripples in a grid of cells: returns a ring height 0..1
float ripples(vec2 p, float t) {
	vec2 cell = floor(p);
	float h = 0.0;
	for (int j = -1; j <= 0; j++) {
		for (int i = -1; i <= 0; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			float s = hash12(c);
			vec2 ctr = c + vec2(hash12(c + 3.1), hash12(c + 7.7));
			float ph = fract(t * (0.8 + 0.4 * s) + s * 9.0);
			float r = length(p - ctr);
			float ring = 1.0 - smoothstep(0.0, 0.05, abs(r - ph * 0.6));
			h += ring * (1.0 - ph);
		}
	}
	return clamp(h, 0.0, 1.0);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	float rough = 0.4;
	float metal = 0.0;
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// slabs and joints
		vec2 g = abs(fract(wp.xz / 2.4) - 0.5);
		float joint = 1.0 - smoothstep(0.0, 0.03, 0.5 - max(g.x, g.y));
		float id = hash12(floor(wp.xz / 2.4));
		col = top_color * (0.72 + 0.22 * id) * (1.0 - 0.35 * joint);
		col *= 0.85 + 0.2 * noise2(wp.xz * 3.0);
		// standing water: puddles where the roof dips, a sheen of wet everywhere else
		float pud = smoothstep(0.52, 0.62, noise2(wp.xz * 0.45) * 0.65 + noise2(wp.xz * 1.7) * 0.35);
		pud *= smoothstep(0.25, 0.6, edge);
		col = mix(col, col * 0.35, pud);
		rough = mix(0.32, 0.03, pud);
		metal = pud * 0.25;
		float rip = ripples(wp.xz * 2.2, TIME) * pud;
		NORMAL_MAP = vec3(0.5 + rip * 0.25, 0.5 + rip * 0.25, 1.0);
		// the neon tube round every landing's edge
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		rough = mix(rough, 0.2, trim);
		glow = trim;
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		rough = 0.8;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		float along = abs(ln.x) > abs(ln.z) ? wp.z : wp.x;
		col = mix(side_color * 0.6, side_color, smoothstep(0.0, 1.0, h));
		// dark rain streaks running down from the lip
		float streak = noise2(vec2(along * 6.0, wp.y * 0.4));
		col *= 0.8 + 0.25 * streak;
		// a lit neon band just under the lip
		float band = smoothstep(0.14, 0.16, depth) * (1.0 - smoothstep(0.26, 0.28, depth));
		col = mix(col, trim_color * 0.9, band * 0.85);
		glow = band * 0.7;
		rough = mix(0.45, 0.25, smoothstep(0.4, 0.7, streak));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = trim_color * glow * clamp(trim_glow + 1.2, 0.0, 3.0);
}
