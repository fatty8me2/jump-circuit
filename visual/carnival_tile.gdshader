shader_type spatial;
// Carnival Chaos: midway boardwalk. Walkable tops are warm painted planks (the plank grain runs along
// local X, with dark seams and a little wear) with a band of MARQUEE BULBS round the edge: bright dashes
// that chase slowly (only the dashes glow, so the edge reads against any background). Small tops (posts,
// beams, drums) get a painted star-and-ring inlay instead of a big plank field so the middle is easy to
// find. Sides are circus stripes (the style colour and cream) that darken toward the keel.
// Same uniforms as visual/platform.gdshader so it can replace it in place. NaN-safe: no pow of negatives,
// no divide by zero (all denominators clamped), bounded HDR (emission <= ~2.5).

uniform vec3 top_color : source_color = vec3(0.78, 0.55, 0.36);
uniform vec3 side_color : source_color = vec3(0.95, 0.9, 0.8);
uniform vec3 trim_color : source_color = vec3(1.0, 0.82, 0.2);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform vec3 stripe_b : source_color = vec3(0.92, 0.2, 0.25);
uniform vec3 seam_color : source_color = vec3(0.34, 0.2, 0.13);

varying vec3 lp;
varying vec3 ln;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
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
		float along;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
			along = atan(lp.z, lp.x + 0.00001) * half_size.x;
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
			along = (d.x < d.y) ? lp.z : lp.x;
		}
		float small_side = min(half_size.x, half_size.z);
		if (small_side >= 1.1) {
			// plank field: boards 0.45 m wide across local Z, staggered ends
			float row = floor((lp.z + half_size.z + 0.0001) / 0.45);
			float stagger = hash11(row) * 1.7;
			float cell = floor((lp.x + half_size.x + stagger) / 2.6);
			float tone = hash11(row * 7.0 + cell);
			col = top_color * (0.9 + 0.2 * tone);
			float seam_z = abs(fract((lp.z + half_size.z) / 0.45) - 0.5);
			col = mix(col, seam_color, smoothstep(0.455, 0.5, seam_z) * 0.55);
		} else {
			// a small tile: a painted board with a bright ring and a star-ish diamond in the middle
			col = top_color;
			vec2 a = abs(lp.xz);
			float ring = 1.0 - smoothstep(0.0, 0.05, abs(length(lp.xz) - small_side * 0.45));
			float dia = 1.0 - smoothstep(small_side * 0.2, small_side * 0.2 + 0.03, a.x + a.y);
			col = mix(col, trim_color, max(ring * 0.8, dia));
			glow += max(ring * 0.5, dia * 0.8);
		}
		// marquee bulbs round the rim: dashes every 0.5 m that chase slowly
		float band = smoothstep(0.03, 0.06, edge) * (1.0 - smoothstep(0.17, 0.2, edge));
		float dash_u = along / 0.5 - TIME * 0.6;
		float dash = smoothstep(0.15, 0.3, fract(dash_u)) * (1.0 - smoothstep(0.55, 0.7, fract(dash_u)));
		vec3 painted = mix(stripe_b, vec3(0.98, 0.94, 0.84), step(0.5, fract(dash_u)));
		col = mix(col, painted, band * 0.7);
		float edge_line = 1.0 - smoothstep(0.0, 0.03, edge);
		col = mix(col, trim_color, edge_line);
		glow += band * dash * 0.9 + edge_line * 0.5;
		ROUGHNESS = 0.65;
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		ROUGHNESS = 0.9;
	} else {
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		float ang = is_round ? atan(lp.z, lp.x + 0.00001) * half_size.x : (abs(ln.x) > 0.5 ? lp.z : lp.x);
		float stripe = step(0.5, fract(ang / 0.55));
		col = mix(side_color, stripe_b, stripe);
		col *= mix(0.55, 1.0, smoothstep(0.0, 1.0, h));
		ROUGHNESS = 0.7;
	}
	ALBEDO = col;
	EMISSION = trim_color * min(glow, 1.4) * (0.55 + 0.4 * trim_glow);
}
