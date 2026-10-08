shader_type spatial;
// Sky Citadel's floors: polished cream marble with soft grey-violet veining, a gold inset line
// round the top edge and a thin lapis line inside it (on wide slabs), paving joints every two
// metres; the sides are fluted marble with a gold fillet under the lip, darker toward the keel.
// Same uniforms as visual/platform.gdshader so it can replace it in place. NaN-safe: every
// smoothstep has ordered edges, nothing is divided or raised to a power that can go negative.

uniform vec3 top_color : source_color = vec3(0.95, 0.92, 0.85);
uniform vec3 side_color : source_color = vec3(0.78, 0.72, 0.62);
uniform vec3 trim_color : source_color = vec3(1.0, 0.78, 0.28);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform vec3 vein_color : source_color = vec3(0.60, 0.62, 0.74);
uniform vec3 inlay_color : source_color = vec3(0.28, 0.50, 0.86);

varying vec3 lp;
varying vec3 ln;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// thin ridged veins: 1 on a vein, 0 elsewhere
float veins(vec2 p) {
	float n = vnoise(p * 1.1) * 0.62 + vnoise(p * 2.7 + vec2(4.0, 9.0)) * 0.38;
	float v = 1.0 - abs(n * 2.0 - 1.0);
	return smoothstep(0.9, 0.99, v);
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
		vec2 seed = lp.xz + vec2(half_size.x * 7.3, half_size.z * 3.1);
		float v = veins(seed);
		float soft = vnoise(seed * 0.45) * 0.12;
		col = top_color * (1.0 - soft);
		col = mix(col, vein_color, v * 0.5);
		// paving joints every two metres
		vec2 g = abs(fract(lp.xz / 2.0) - 0.5);
		float joint = 1.0 - smoothstep(0.0, 0.012, 0.5 - max(g.x, g.y));
		col *= 1.0 - 0.07 * joint;
		// a lapis line inside the gold, only on slabs wide enough to carry it
		float small = min(half_size.x, half_size.z);
		float lapis = smoothstep(0.26, 0.28, edge) * (1.0 - smoothstep(0.31, 0.33, edge)) * smoothstep(0.7, 0.9, small);
		col = mix(col, inlay_color, lapis * 0.85);
		float inner = smoothstep(0.12, 0.14, edge);
		float outer = smoothstep(0.04, 0.06, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = 0.32;
		METALLIC = 0.0;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		ROUGHNESS = 0.9;
	} else {
		float depth = half_size.y - lp.y;
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		col = mix(side_color * 0.6, side_color, smoothstep(0.0, 1.0, h));
		float band = smoothstep(0.1, 0.12, depth) * (1.0 - smoothstep(0.17, 0.19, depth));
		col = mix(col, trim_color * 0.95, band * 0.9);
		glow = band * 0.5;
		// flutes: soft vertical grooves below the fillet
		float fl = 0.5 + 0.5 * sin((lp.x + lp.z) * 11.0);
		col *= 1.0 - 0.1 * fl * step(0.25, depth);
		ROUGHNESS = 0.55;
	}
	ALBEDO = col;
	EMISSION = trim_color * min(glow, 1.5) * (0.18 + trim_glow * 0.5);
}
