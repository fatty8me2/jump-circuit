shader_type spatial;
// A bookshelf face drawn procedurally on a box: rows of leather spines (random widths, heights, a
// gilt band and a title label), dark cavities behind them, wooden shelf planks between the rows and
// a frame round the edge. Books show on the +-X and +-Z faces; the top and bottom are plain wood.
// `size` is the box size, `tone` shifts the palette. NaN-safe: no pow() of negatives, no normalize().

uniform vec3 size = vec3(2.0, 4.0, 1.0);
uniform vec3 wood : source_color = vec3(0.24, 0.12, 0.07);
uniform vec3 gilt : source_color = vec3(1.0, 0.78, 0.35);
uniform float tone = 0.0;
uniform float row_h = 0.85;
uniform float glow = 0.0;

varying vec3 lp;
varying vec3 ln;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 spine(float r) {
	if (r < 0.18) return vec3(0.45, 0.07, 0.1);
	if (r < 0.34) return vec3(0.1, 0.13, 0.4);
	if (r < 0.48) return vec3(0.08, 0.28, 0.17);
	if (r < 0.62) return vec3(0.4, 0.22, 0.08);
	if (r < 0.74) return vec3(0.34, 0.1, 0.38);
	if (r < 0.86) return vec3(0.55, 0.42, 0.16);
	return vec3(0.17, 0.15, 0.2);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col = wood;
	float em = 0.0;
	float side = max(abs(ln.x), abs(ln.z));
	if (side > 0.6) {
		float u = (abs(ln.z) > 0.6 ? lp.x : lp.z) + (abs(ln.z) > 0.6 ? size.x : size.z) * 0.5;
		float w = abs(ln.z) > 0.6 ? size.x : size.z;
		float v = lp.y + size.y * 0.5;
		float edge = min(min(u, w - u), min(v, size.y - v));
		if (edge < 0.14) {
			col = wood * 1.15;
		} else {
			float row = floor(v / row_h);
			float fr = v / row_h - row;
			if (fr < 0.09) {
				col = wood * 1.3;
			} else {
				float bu = u / 0.17;
				float bi = floor(bu);
				float seed = row * 13.0 + tone;
				float hh = 0.55 + 0.4 * h21(vec2(bi, seed));
				float body = (fr - 0.09) / 0.91;
				col = vec3(0.03, 0.02, 0.04);
				if (body < hh && h21(vec2(bi * 1.3, seed + 5.0)) > 0.06) {
					float r = h21(vec2(bi * 2.1 + tone, seed + 1.0));
					col = spine(r) * (0.6 + 0.5 * fract(bu));
					float band = step(abs(body - hh * 0.8), 0.03) + step(abs(body - hh * 0.25), 0.02);
					col = mix(col, gilt * 0.8, clamp(band, 0.0, 1.0) * 0.8);
					float label = step(0.4, fract(bu)) * step(fract(bu), 0.8) * step(abs(body - hh * 0.55), 0.07) * step(0.5, h21(vec2(bi, seed + 9.0)));
					col = mix(col, vec3(0.9, 0.82, 0.62), label * 0.8);
				}
			}
		}
		em = glow * 0.15;
	} else {
		col = wood * 0.9;
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
	EMISSION = col * em;
}
