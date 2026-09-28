shader_type spatial;
// Super Carrier walkable surface: the platform shader's layout (bright top, inset trim line, darker
// sides) re-done as a warship's painted steel. Tops are non-skid deck coating over welded plates with
// tie-down cups; the trim is a band of yellow-and-black hazard striping round the edge; sides are
// haze-grey plating with weld seams, rows of rivets and faint rust weeping from the seams.
// Same uniforms as visual/platform.gdshader, so the level can swap it in.

uniform vec3 top_color : source_color = vec3(0.4, 0.42, 0.44);
uniform vec3 side_color : source_color = vec3(0.55, 0.58, 0.6);
uniform vec3 trim_color : source_color = vec3(1.0, 0.82, 0.2);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.16;
uniform float trim_glow = 0.0;

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 wn;

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
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz + vec3(0.0, 0.0001, 0.0));
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
		// welded deck plates (2 x 4 m) and the grit of the non-skid coating
		vec2 pl = wp.xz / vec2(2.0, 4.0);
		vec2 pf = abs(fract(pl) - 0.5);
		float seam = 1.0 - smoothstep(0.0, 0.012, 0.5 - max(pf.x * 1.0, pf.y));
		float grit = noise2(wp.xz * 9.0) * 0.6 + noise2(wp.xz * 31.0) * 0.4;
		float plate = hash12(floor(pl));
		col = top_color * (0.9 + 0.12 * plate) * (0.92 + 0.14 * grit);
		col *= 1.0 - 0.18 * seam;
		// scuffs and tyre marks
		float scuff = smoothstep(0.62, 0.8, noise2(wp.xz * 0.35 + vec2(wp.y)));
		col = mix(col, col * 0.78, scuff * 0.5);
		// tie-down cups every 1.5 m
		vec2 cup = abs(fract(wp.xz / 1.5) - 0.5) * 1.5;
		float c = 1.0 - smoothstep(0.07, 0.1, length(cup));
		col = mix(col, vec3(0.12, 0.13, 0.14), c * 0.8);
		// hazard striping round the edge
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.2, trim_width * 0.2 + 0.02, edge);
		float band = outer * (1.0 - inner);
		float diag = step(0.5, fract((wp.x + wp.z) * 1.6));
		vec3 stripe = mix(vec3(0.07, 0.07, 0.07), trim_color, diag);
		col = mix(col, stripe, band);
		glow = band * diag;
		ROUGHNESS = 0.86 - 0.1 * scuff;
		METALLIC = 0.12;
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		ROUGHNESS = 0.9;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		// hull plating: 3 x 1.5 m plates, weld seams, rivet rows along the seams
		vec2 pl = vec2(u / 3.0, wp.y / 1.5);
		vec2 pf = abs(fract(pl) - 0.5);
		float seam = 1.0 - smoothstep(0.0, 0.015, 0.5 - max(pf.x, pf.y));
		float rv = (1.0 - smoothstep(0.02, 0.035, abs(fract(wp.y / 1.5) - 0.12))) * step(0.5, fract(u * 3.0));
		float plate = hash12(floor(pl) + 7.0);
		col = side_color * (0.86 + 0.14 * plate) * (1.0 - 0.2 * seam);
		col = mix(col, side_color * 0.62, rv * 0.6);
		// rust weeping down from the seams
		float weep = smoothstep(0.55, 0.9, noise2(vec2(u * 2.2, floor(wp.y / 1.5) * 3.1))) * (1.0 - smoothstep(0.0, 0.5, fract(wp.y / 1.5))) * 0.35;
		col = mix(col, vec3(0.42, 0.26, 0.16), weep);
		col = mix(col * 0.72, col, smoothstep(0.0, 0.7, h));
		// a painted band just under the lip in the trim colour
		float depth = half_size.y - lp.y;
		float band = smoothstep(0.1, 0.12, depth) * (1.0 - smoothstep(0.2, 0.22, depth));
		col = mix(col, trim_color * 0.85, band * 0.8);
		glow = band * 0.4;
		ROUGHNESS = 0.8;
		METALLIC = 0.2;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow;
}
