shader_type spatial;
// The Abyss: walkable trench rock. Dark basalt with a mottled, pitted top, so the course reads as
// stone in the black water - but every walkable top carries its OWN light: a bright glowing band of
// bioluminescent growth round its edge, glowing dots of lichen stepping in from the corners, and
// faint cold flecks across the surface, so in pitch darkness you still see exactly where you can
// stand. The sides fade into the dark below a thin glowing lip. Emission is bounded (no blow-out).

uniform vec3 top_color : source_color = vec3(0.3, 0.36, 0.4);
uniform vec3 side_color : source_color = vec3(0.1, 0.14, 0.18);
uniform vec3 trim_color : source_color = vec3(0.1, 1.0, 0.85);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform float edge_glow = 1.6;

varying vec3 lp;
varying vec3 ln;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col;
	vec3 glow = vec3(0.0);
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		float n = noise(lp.xz * 1.7) * 0.6 + noise(lp.xz * 5.3) * 0.4;
		col = top_color * (0.55 + 0.5 * n);
		// pits of darker rock
		col *= 1.0 - 0.35 * smoothstep(0.62, 0.8, noise(lp.xz * 2.6 + 7.0));
		// the glowing rim: a hard bright band right at the edge, a soft halo inward
		float band = 1.0 - smoothstep(0.08, 0.14, edge);
		float halo = (1.0 - smoothstep(0.1, 0.55, edge)) * 0.35;
		col = mix(col, trim_color * 0.6, band);
		glow += trim_color * (band * edge_glow + halo * 0.35);
		// lichen dots along the rim, half a metre in
		vec2 cell = floor(lp.xz * 2.0);
		float h = hash(cell);
		vec2 fc = fract(lp.xz * 2.0) - 0.5;
		float dotm = (1.0 - smoothstep(0.08, 0.16, length(fc))) * step(0.72, h) * (1.0 - smoothstep(0.3, 0.7, edge));
		glow += trim_color * dotm * 0.9;
		// faint cold flecks across the surface (so a big top never reads as a hole)
		vec2 cell2 = floor(lp.xz * 4.0);
		vec2 fc2 = fract(lp.xz * 4.0) - 0.5;
		float fleck = (1.0 - smoothstep(0.04, 0.09, length(fc2))) * step(0.9, hash(cell2 + 3.1));
		glow += vec3(0.35, 0.6, 0.7) * fleck * 0.35;
		ROUGHNESS = 0.82;
	} else if (ln.y < -0.6) {
		col = side_color * 0.4;
		ROUGHNESS = 0.95;
	} else {
		float depth = half_size.y - lp.y;
		float n2 = noise(vec2(lp.x + lp.z, lp.y) * 2.2);
		col = side_color * mix(0.85, 0.35, clamp(depth / max(half_size.y * 2.0, 0.01), 0.0, 1.0)) * (0.7 + 0.5 * n2);
		// a thin glowing lip just under the top edge
		float lip = smoothstep(0.03, 0.06, depth) * (1.0 - smoothstep(0.1, 0.14, depth));
		col = mix(col, trim_color * 0.5, lip);
		glow += trim_color * lip * edge_glow * 0.7;
		ROUGHNESS = 0.9;
	}
	ALBEDO = col;
	EMISSION = min(glow * (1.0 + trim_glow * 0.4), vec3(4.0));
}
