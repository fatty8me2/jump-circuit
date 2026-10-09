shader_type spatial;
// The Arcane Library's floors: warm polished wood. A wide top is laid in long planks (each a touch
// lighter or darker, with a fine grain and a dark seam) inside a violet inlay line and a gold edge;
// a small one (a post, a beam, a stepping stone) is oxblood leather with a gold diamond tooled into
// its centre, so the eye finds the middle. The sides are dark mahogany with a thin gold band under
// the lip. Same uniforms as visual/platform.gdshader so it can replace it in place. NaN-safe: no
// pow() of negatives, no normalize(), every divide guarded.

uniform vec3 top_color : source_color = vec3(0.55, 0.34, 0.2);
uniform vec3 side_color : source_color = vec3(0.3, 0.17, 0.1);
uniform vec3 trim_color : source_color = vec3(1.0, 0.8, 0.35);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform vec3 inlay_color : source_color = vec3(0.5, 0.32, 0.9);

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
			// long planks along z
			float pw = 0.5;
			float pi_ = floor((lp.x + half_size.x) / pw);
			float pf = fract((lp.x + half_size.x) / pw);
			float seg = floor((lp.z + half_size.z) / 2.3 + h21(vec2(pi_, 3.0)) * 4.0);
			float tone = h21(vec2(pi_, seg));
			col = top_color * (0.82 + 0.34 * tone);
			float grain = sin((lp.z + lp.x * 3.0) * 17.0 + tone * 40.0) * 0.5 + 0.5;
			col *= 0.95 + 0.07 * grain;
			float seam = 1.0 - smoothstep(0.0, 0.05, min(pf, 1.0 - pf));
			col = mix(col, col * 0.45, seam * 0.8);
			// violet inlay line inside the gold edge
			float inl = 1.0 - smoothstep(0.0, 0.025, abs(edge - 0.3));
			col = mix(col, inlay_color, inl * 0.85);
			glow += inl * 0.25;
		} else {
			col = top_color * 0.62;
			vec2 a = abs(lp.xz);
			float dia = 1.0 - smoothstep(small * 0.34, small * 0.34 + 0.02, a.x + a.y);
			float ring = 1.0 - smoothstep(0.0, 0.02, abs(a.x + a.y - small * 0.5));
			col = mix(col, trim_color, max(dia * 0.55, ring * 0.7));
			glow += dia * 0.35 + ring * 0.2;
		}
		float inner = smoothstep(0.1, 0.12, edge);
		float outer = smoothstep(0.02, 0.04, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow += trim;
		ROUGHNESS = 0.42;
		METALLIC = 0.05;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		ROUGHNESS = 0.9;
	} else {
		float depth = half_size.y - lp.y;
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		col = mix(side_color * 0.5, side_color, smoothstep(0.0, 1.0, h));
		float band = smoothstep(0.1, 0.12, depth) * (1.0 - smoothstep(0.16, 0.18, depth));
		col = mix(col, trim_color, band);
		side_glow = band * 0.5;
		// a fine vertical reeding down the mahogany
		float reed = smoothstep(0.42, 0.5, abs(fract((lp.x + lp.z) * 2.2) - 0.5));
		col *= 1.0 - 0.14 * reed * step(0.25, depth);
		ROUGHNESS = 0.6;
	}
	ALBEDO = col;
	EMISSION = trim_color * min(glow, 1.5) * (0.25 + trim_glow) + trim_color * side_glow * 0.5;
}
