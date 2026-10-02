shader_type spatial;
// The Void's collapse fragments: pale marble slabs with a fine chessboard on top. `crack` (0..1)
// spreads a web of glowing pink fractures across them as the warning; `fade` (0..1) dissolves the
// falling slab away (opaque discard, so it still sorts and shadows like a solid).
// NaN-safe: bounded terms only.

uniform vec3 half_size = vec3(0.6, 0.25, 0.6);
uniform float crack = 0.0;
uniform float fade = 0.0;
uniform vec3 stone : source_color = vec3(0.9, 0.88, 0.95);
uniform vec3 dark : source_color = vec3(0.2, 0.15, 0.3);
uniform vec3 glow_col : source_color = vec3(1.0, 0.36, 0.72);

varying vec3 lp;
varying vec3 ln;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// distance to the nearest cell border of a jittered grid (a cheap voronoi crack web)
float web(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash13(vec3(i + g, 1.7)), hash13(vec3(i + g, 5.3)));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	if (fade > 0.0 && hash13(floor(lp * 9.0) + vec3(3.1)) < fade) {
		discard;
	}
	vec3 col = stone;
	vec2 uv = ln.y > 0.6 || ln.y < -0.6 ? lp.xz : (abs(ln.x) > 0.6 ? lp.zy : lp.xy);
	if (ln.y > 0.6) {
		vec2 c = floor(lp.xz / 0.4);
		float chk = mod(c.x + c.y, 2.0);
		col = mix(stone, mix(stone, dark, 0.5), chk * 0.5);
		vec2 e = half_size.xz - abs(lp.xz);
		float trim = 1.0 - smoothstep(0.06, 0.08, min(e.x, e.y));
		col = mix(col, glow_col * 0.8 + vec3(0.2), trim * 0.6);
	} else {
		col *= 0.78;
	}
	float w = web(uv * 2.2);
	float k = clamp(crack, 0.0, 1.0);
	float line = (1.0 - smoothstep(0.0, 0.03 + 0.06 * k, w)) * smoothstep(0.0, 0.25, k);
	col = mix(col, glow_col, line);
	ALBEDO = col;
	ROUGHNESS = 0.35;
	EMISSION = glow_col * line * (1.5 + 2.0 * k);
}
