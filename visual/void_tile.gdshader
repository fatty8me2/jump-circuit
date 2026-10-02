shader_type spatial;
// The Void's floors: clean white dream-geometry. A wide top is a chessboard (pale and violet
// squares); a small one (a post, a beam) is plain pale stone with a diamond inlay at its centre, so
// the eye finds the middle. A thin glowing trim runs round the top edge (pink, or the style's
// colour); the sides are white marble that fades toward a faint cyan line under the lip.
// Same uniforms as visual/platform.gdshader so it can replace it in place. NaN-safe.

uniform vec3 top_color : source_color = vec3(0.9, 0.89, 0.95);
uniform vec3 side_color : source_color = vec3(0.75, 0.72, 0.84);
uniform vec3 trim_color : source_color = vec3(1.0, 0.36, 0.72);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform vec3 square_dark : source_color = vec3(0.3, 0.24, 0.44);
uniform vec3 line_color : source_color = vec3(0.32, 0.9, 1.0);

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	float side_glow = 0.0;
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		float small = min(half_size.x, half_size.z);
		if (small >= 0.95) {
			vec2 c = floor(lp.xz + half_size.xz + vec2(0.0001));
			float chk = mod(c.x + c.y, 2.0);
			col = mix(top_color, square_dark, chk * 0.85);
		} else {
			col = top_color;
			vec2 a = abs(lp.xz);
			float dia = 1.0 - smoothstep(small * 0.3, small * 0.3 + 0.02, a.x + a.y);
			col = mix(col, trim_color, dia * 0.7);
			glow += dia * 0.5;
		}
		float inner = smoothstep(0.1, 0.12, edge);
		float outer = smoothstep(0.02, 0.04, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow += trim;
		ROUGHNESS = 0.4;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		ROUGHNESS = 0.9;
	} else {
		float depth = half_size.y - lp.y;
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		col = mix(side_color * 0.55, side_color, smoothstep(0.0, 1.0, h));
		float band = smoothstep(0.1, 0.12, depth) * (1.0 - smoothstep(0.16, 0.18, depth));
		col = mix(col, line_color, band);
		side_glow = band * 0.8;
		ROUGHNESS = 0.55;
	}
	ALBEDO = col;
	EMISSION = trim_color * min(glow, 1.5) * (0.6 + trim_glow) + line_color * side_glow;
}
