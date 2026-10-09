shader_type spatial;
// Dino Valley walkable surface: the platform shader's layout (bright top, inset trim line, darker
// sides) re-done as a grass-topped sandstone stack. Tops are mown-looking meadow with darker clumps, a
// few buttercups and dry earth creeping in from the edges, then the usual trim line marking where you
// can stand. Sides are weathered strata (bands of ochre, rust and cream), a ragged fringe of turf
// hanging over the lip and cracks. Same uniforms as visual/platform.gdshader so the level swaps it in.
// Nothing here can divide by zero or take pow() of a negative.

uniform vec3 top_color : source_color = vec3(0.46, 0.64, 0.22);
uniform vec3 side_color : source_color = vec3(0.66, 0.46, 0.28);
uniform vec3 trim_color : source_color = vec3(1.0, 0.74, 0.28);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 flower : source_color = vec3(1.0, 0.86, 0.3);

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 wn;

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

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	vec3 emit = vec3(0.0);
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		float n = vnoise(wp.xz * 1.3);
		float n2 = vnoise(wp.xz * 7.0 + vec2(5.0, 2.0));
		vec3 grass = mix(top_color * 0.82, top_color * 1.12, n);
		grass = mix(grass, top_color * 0.7, smoothstep(0.55, 0.85, vnoise(wp.xz * 0.5 + vec2(9.0, 4.0))) * 0.5);
		grass *= 0.92 + 0.16 * n2;
		// dry earth creeping in from the edges
		float rim = 1.0 - smoothstep(0.12, 0.6, edge);
		col = mix(grass, side_color * 1.05, rim * (0.35 + 0.4 * n));
		// buttercups
		vec2 cell = floor(wp.xz * 2.6);
		vec2 fr = fract(wp.xz * 2.6) - 0.5;
		vec2 off = vec2(hash21(cell + 1.3), hash21(cell + 7.9)) - 0.5;
		float fl = step(0.9, hash21(cell)) * (1.0 - smoothstep(0.05, 0.1, length(fr - off * 0.5)));
		col = mix(col, flower, fl * 0.9 * (1.0 - rim));
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = 0.88;
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		ROUGHNESS = 0.95;
	} else {
		float depth = half_size.y - lp.y;
		float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		// strata: bands whose tone is picked per band, wobbling with the horizontal position
		float yy = wp.y * 1.7 + vnoise(vec2(u * 0.35, wp.y * 0.6)) * 1.6;
		float band = floor(yy);
		float tone = hash21(vec2(band, 3.0));
		vec3 base = mix(side_color * 0.78, side_color * 1.18, tone);
		base = mix(base, vec3(0.78, 0.6, 0.42), step(0.72, hash21(vec2(band, 8.0))) * 0.55);
		base = mix(base, side_color * 0.55, step(0.9, hash21(vec2(band, 5.0))));
		col = base * (0.88 + 0.2 * vnoise(vec2(u * 2.4, wp.y * 3.0)));
		// hairline cracks
		float crack = 1.0 - smoothstep(0.0, 0.04, abs(vnoise(vec2(u * 1.6, wp.y * 0.8)) - 0.5));
		col *= 1.0 - 0.18 * crack;
		// the glowing trim band just under the lip (as the platform shader), then a turf fringe over it
		float tb = smoothstep(0.16, 0.18, depth) * (1.0 - smoothstep(0.26, 0.28, depth));
		col = mix(col, trim_color * 0.9, tb * 0.8);
		glow = tb * 0.5;
		float fringe = 0.12 + 0.5 * vnoise(vec2(u * 3.1, 1.0));
		float turf = 1.0 - smoothstep(fringe * 0.4, fringe, depth);
		col = mix(col, top_color * 0.8, clamp(turf, 0.0, 1.0));
		// darker toward the foot of tall stacks
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		col = mix(col * 0.62, col, smoothstep(0.0, 0.6, h));
		ROUGHNESS = 0.92;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow + emit;
}
