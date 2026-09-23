shader_type spatial;
// Coral Depths walkable surface: the platform shader's layout (bright top, glowing inset
// trim, darker sides) re-done as sand over coral rock, with animated caustic light
// dancing across every top. Same uniforms as visual/platform.gdshader so the level can
// swap it in and keep each piece's colours.

uniform vec3 top_color : source_color = vec3(0.85, 0.82, 0.74);
uniform vec3 side_color : source_color = vec3(0.45, 0.42, 0.5);
uniform vec3 trim_color : source_color = vec3(1.0, 0.75, 0.3);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 caustic_color : source_color = vec3(0.55, 0.95, 1.0);
uniform float caustic_strength = 0.55;
uniform vec3 speck_color : source_color = vec3(1.0, 0.45, 0.7);

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

// distance between the two nearest animated cell points: small along cell borders
float cells(vec2 p, float t) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(ip + g);
			o = 0.5 + 0.42 * sin(t + 6.2831 * o);
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

float caustic(vec2 p, float t) {
	float a = cells(p * 0.55, t * 0.9);
	float b = cells(p * 0.8 + vec2(3.1, 1.7), t * 1.2 + 2.0);
	float ca = 1.0 - smoothstep(0.0, 0.16, a);
	float cb = 1.0 - smoothstep(0.0, 0.12, b);
	return ca * ca * 0.65 + cb * cb * 0.45;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	float caus = 0.0;
	float n1 = vnoise(wp.xz * 1.7 + wp.y);
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// sand: soft ripples + grain
		float ripple = sin(wp.x * 2.3 + wp.z * 0.9 + vnoise(wp.xz * 0.6) * 4.0) * 0.5 + 0.5;
		col = top_color * (0.9 + 0.08 * ripple + 0.08 * (n1 - 0.5));
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		caus = caustic(wp.xz, TIME);
		ROUGHNESS = 0.85;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		ROUGHNESS = 0.95;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		// porous coral rock: blotches, pits and bright polyp specks
		float n2 = vnoise(vec2(wp.x + wp.z, wp.y) * 3.1);
		col = mix(side_color * 0.6, side_color * 1.08, smoothstep(0.0, 1.0, h));
		col *= 0.82 + 0.3 * n2;
		float speck = step(0.86, vnoise(vec2(wp.x - wp.z, wp.y) * 9.0 + 7.0));
		col = mix(col, speck_color, speck * 0.55);
		glow = speck * 0.35;
		float band = smoothstep(0.16, 0.18, depth) * (1.0 - smoothstep(0.30, 0.32, depth));
		col = mix(col, trim_color * 0.9, band * 0.85);
		glow += band * 0.6;
		caus = caustic(vec2(wp.x + wp.z, wp.y * 1.4), TIME) * 0.25 * h;
		ROUGHNESS = 0.9;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow + speck_color * 0.0 + caustic_color * caus * caustic_strength;
}
