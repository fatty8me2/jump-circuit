shader_type spatial;
// Pixel Panic's floors: 8-bit tiles. The top is a grid of chunky 0.25 m pixels in two shades of the
// style's colour with a few lit "dither" pixels, a stepped pixel border in the trim colour round the
// edge, and scanlines; the sides are banded rows like a sprite sheet. Same uniforms as
// visual/platform.gdshader so it can replace it in place. Bounded, no divisions by variables, no pow().

uniform vec3 top_color : source_color = vec3(0.1, 0.3, 1.0);
uniform vec3 side_color : source_color = vec3(0.05, 0.08, 0.3);
uniform vec3 trim_color : source_color = vec3(1.0, 0.95, 0.2);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform float pixel = 0.25;

varying vec3 lp;
varying vec3 ln;

float h21(vec2 p) {
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
	float px = max(pixel, 0.05);
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		vec2 c = floor(lp.xz / px);
		float chk = mod(c.x + c.y, 2.0);
		float n = h21(c);
		col = top_color * (0.82 + 0.18 * chk);
		// a few bright dither pixels
		col = mix(col, min(top_color * 1.6 + vec3(0.15), vec3(1.4)), step(0.93, n) * 0.8);
		// the stepped border: one pixel wide, trim coloured
		float border = 1.0 - step(px, edge);
		col = mix(col, trim_color, border);
		glow += border;
		// scanlines
		col *= 0.88 + 0.12 * step(0.5, fract(lp.z / (px * 2.0)));
		ROUGHNESS = 0.8;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		ROUGHNESS = 0.9;
	} else {
		float depth = half_size.y - lp.y;
		float row = floor(depth / px);
		float shade = 0.7 + 0.3 * mod(row, 2.0);
		col = side_color * shade;
		float band = 1.0 - step(px, depth);
		col = mix(col, trim_color * 0.9, band);
		glow += band * 0.6;
		ROUGHNESS = 0.85;
	}
	ALBEDO = col;
	EMISSION = trim_color * min(glow, 1.5) * (0.5 + trim_glow) + top_color * 0.08;
}
