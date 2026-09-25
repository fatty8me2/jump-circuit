shader_type spatial;
// Cinder Peak walkable surface: the platform shader's layout (readable top, glowing inset
// trim, darker sides) re-done as volcanic rock. Tops are cooled ropey pahoehoe crust with
// vesicle specks and faint hot seams that breathe; sides are columnar basalt (vertical
// facets, cooling joints) warmed from below by the lava light. Same uniforms as
// visual/platform.gdshader so the level swaps it in and keeps each piece's colours.

uniform vec3 top_color : source_color = vec3(0.85, 0.82, 0.74);
uniform vec3 side_color : source_color = vec3(0.45, 0.42, 0.5);
uniform vec3 trim_color : source_color = vec3(1.0, 0.75, 0.3);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 seam_color : source_color = vec3(1.0, 0.36, 0.06);
uniform vec3 under_glow : source_color = vec3(0.9, 0.22, 0.04);

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// f2 - f1 of a cell pattern: small along the seams between cells
float seams(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(ip + g);
			float d = length(g + o - fp);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

void fragment() {
	vec3 col;
	vec3 emit = vec3(0.0);
	float glow_amt = max(trim_glow, 0.9);
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// ropey pahoehoe: warped bands of crust with a little sheen
		vec2 q = wp.xz * 0.9;
		float warp = vnoise(q * 0.7) * 3.0;
		float rope = 0.5 + 0.5 * sin(q.x * 2.3 + q.y * 1.1 + warp * 2.2);
		float blotch = vnoise(wp.xz * 0.35);
		col = top_color * (0.82 + 0.16 * rope + 0.12 * (blotch - 0.5));
		// vesicles: tiny dark pits and the odd glinting speck of glass
		float pit = step(0.93, hash2(floor(wp.xz * 9.0)).x);
		col *= 1.0 - 0.3 * pit;
		// faint hot seams that breathe (kept low: the top must read as solid ground)
		float s = seams(wp.xz * 0.55);
		float seam = 1.0 - smoothstep(0.0, 0.06, s);
		float breathe = 0.55 + 0.45 * sin(TIME * 1.3 + blotch * 9.0);
		col = mix(col, seam_color * 0.35, seam * 0.5);
		emit += seam_color * seam * 0.35 * breathe;
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		emit += trim_color * trim * glow_amt;
		ROUGHNESS = 0.72 - 0.2 * rope * 0.3;
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		emit += under_glow * 0.18;
		ROUGHNESS = 0.95;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		// columnar basalt: vertical facets with dark joints between them
		float around = (abs(ln.x) > abs(ln.z)) ? lp.z : lp.x;
		float facet = abs(fract(around * 0.85 + 0.5 * vnoise(vec2(around, 3.0))) - 0.5);
		float joint = smoothstep(0.44, 0.5, facet);
		float band = floor(lp.y * 1.2 + vnoise(vec2(around * 2.0, 1.0)) * 0.8);
		float chip = hash2(vec2(floor(around * 0.85), band)).x;
		col = side_color * (0.75 + 0.35 * chip) * (1.0 - 0.45 * joint);
		col = mix(col * 0.6, col, smoothstep(0.0, 1.0, h));
		// the glowing seam just under the lip
		float lip = smoothstep(0.16, 0.18, depth) * (1.0 - smoothstep(0.28, 0.30, depth));
		col = mix(col, trim_color * 0.9, lip * 0.8);
		emit += trim_color * lip * 0.55 * glow_amt;
		// warmed from below by the lava light
		emit += under_glow * pow(1.0 - h, 3.0) * 0.22;
		ROUGHNESS = 0.9;
	}
	ALBEDO = col;
	EMISSION = emit;
}
