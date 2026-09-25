shader_type spatial;
// Xeno Wilds walkable surface: the platform shader's layout (bright top, glowing inset trim,
// darker sides) re-done as alien ground - a spongy moss top threaded with a network of glowing
// veins that pulse slowly outward, over banded violet rock studded with luminous crystal grains.
// Same uniforms as visual/platform.gdshader so the level can swap it in and keep each piece's colours.

uniform vec3 top_color : source_color = vec3(0.85, 0.82, 0.74);
uniform vec3 side_color : source_color = vec3(0.45, 0.42, 0.5);
uniform vec3 trim_color : source_color = vec3(1.0, 0.75, 0.3);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 vein_color : source_color = vec3(0.35, 1.0, 0.85);
uniform float vein_strength = 0.9;
uniform vec3 grain_color : source_color = vec3(1.0, 0.45, 0.95);

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

// distance to the nearest cell border (small along the veins), plus the cell's own random value
vec2 veins(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(ip + g);
			float d = length(g + o - fp);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = o.x;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec2(f2 - f1, id);
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	vec3 emit = vec3(0.0);
	float n1 = vnoise(wp.xz * 1.3 + wp.y);
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// moss: soft clumps and a fine nap
		float clump = vnoise(wp.xz * 0.9);
		float nap = vnoise(wp.xz * 7.0);
		col = top_color * (0.82 + 0.2 * clump + 0.08 * (nap - 0.5));
		// the vein network, pulsing outward along the veins
		vec2 v = veins(wp.xz * 0.55);
		float line = 1.0 - smoothstep(0.0, 0.06, v.x);
		float pulse = 0.55 + 0.45 * sin(TIME * 1.6 - length(wp.xz) * 0.35 + v.y * 6.2831);
		col = mix(col, col * 0.6, line * 0.5);
		emit += vein_color * line * pulse * vein_strength;
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = 0.9;
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		ROUGHNESS = 0.95;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		// banded alien rock with glittering crystal grains
		float strata = 0.5 + 0.5 * sin(wp.y * 5.0 + vnoise(vec2(wp.x + wp.z, wp.y) * 1.2) * 3.0);
		col = mix(side_color * 0.55, side_color * 1.1, smoothstep(0.0, 1.0, h));
		col *= 0.78 + 0.22 * strata + 0.15 * (n1 - 0.5);
		float grain = step(0.9, vnoise(vec2(wp.x - wp.z, wp.y) * 8.0 + 3.0));
		col = mix(col, grain_color, grain * 0.5);
		emit += grain_color * grain * 0.9;
		float band = smoothstep(0.16, 0.18, depth) * (1.0 - smoothstep(0.30, 0.32, depth));
		col = mix(col, trim_color * 0.9, band * 0.85);
		glow = band * 0.6;
		ROUGHNESS = 0.88;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow + emit;
}
