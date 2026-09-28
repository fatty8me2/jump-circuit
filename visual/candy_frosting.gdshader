shader_type spatial;
// Sugar Rush walkable surface: the platform shader's layout (bright top, inset trim line, darker
// sides) re-done as cake. Tops are smooth frosting in the platform's top colour, scattered with
// rainbow sprinkles, with a piped candy trim marking every landing's edge; sides are sponge with a
// cream filling band, and the frosting drips down over the lip in rounded runs. Same uniforms as
// visual/platform.gdshader, so the level can swap it in.

uniform vec3 top_color : source_color = vec3(1.0, 0.9, 0.95);
uniform vec3 side_color : source_color = vec3(0.95, 0.55, 0.7);
uniform vec3 trim_color : source_color = vec3(1.0, 0.35, 0.55);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 sponge : source_color = vec3(0.98, 0.82, 0.55);

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
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

vec3 sprinkle_color(float h) {
	if (h < 0.17) return vec3(1.0, 0.3, 0.45);
	if (h < 0.34) return vec3(0.35, 0.7, 1.0);
	if (h < 0.5) return vec3(1.0, 0.85, 0.2);
	if (h < 0.67) return vec3(0.45, 0.9, 0.5);
	if (h < 0.84) return vec3(0.75, 0.45, 1.0);
	return vec3(1.0, 1.0, 1.0);
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
		// smooth frosting with a soft swirl in it
		float sw = noise2(wp.xz * 0.9) * 0.6 + noise2(wp.xz * 2.7) * 0.4;
		col = top_color * (0.95 + 0.08 * sw);
		// sprinkles: at most one short rod per cell, randomly turned and coloured
		vec2 g = wp.xz * 3.0;
		vec2 cell = floor(g);
		float h = hash12(cell);
		if (h > 0.45) {
			vec2 f = fract(g) - 0.5;
			float ang = hash12(cell + 7.3) * 6.2831853;
			vec2 dir = vec2(cos(ang), sin(ang));
			vec2 off = vec2(hash12(cell + 1.7), hash12(cell + 4.1)) * 0.4 - 0.2;
			vec2 q = f - off;
			float along = dot(q, dir);
			float across = dot(q, vec2(-dir.y, dir.x));
			float rod = (1.0 - smoothstep(0.12, 0.16, abs(along))) * (1.0 - smoothstep(0.035, 0.055, abs(across)));
			col = mix(col, sprinkle_color(hash12(cell + 3.9)), rod * smoothstep(0.2, 0.35, edge));
		}
		// the piped trim round the edge
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		float bead = 0.85 + 0.15 * sin((wp.x + wp.z) * 18.0);
		col = mix(col, trim_color * bead, trim);
		glow = trim;
		ROUGHNESS = 0.55;
	} else if (ln.y < -0.6) {
		col = side_color * 0.55;
		ROUGHNESS = 0.9;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		float u;
		if (is_round) {
			u = (length(lp.xz) > 0.0001 ? atan(lp.z, lp.x) : 0.0) * half_size.x;
		} else {
			u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		}
		// sponge with a pale cream filling band through the middle of thick slabs
		float pores = noise2(vec2(u, wp.y) * 9.0);
		col = mix(side_color, sponge, 0.35) * (0.9 + 0.12 * pores);
		float fill = smoothstep(0.02, 0.05, abs(h - 0.45) - 0.08);
		col = mix(vec3(1.0, 0.96, 0.92), col, mix(1.0, fill, step(0.9, half_size.y * 2.0)));
		col = mix(col * 0.72, col, smoothstep(0.0, 0.6, h));
		// frosting running down over the lip in rounded drips
		float wave = sin(u * 3.1 + noise2(vec2(u * 0.7, 3.0)) * 4.0) * 0.5 + 0.5;
		float len = 0.12 + 0.3 * wave * wave * noise2(vec2(u * 1.3, 1.0));
		float drip = 1.0 - smoothstep(len - 0.02, len + 0.02, depth);
		col = mix(col, top_color * 0.97, drip);
		// the piped trim band just under the lip
		float band = smoothstep(0.03, 0.05, depth) * (1.0 - smoothstep(0.09, 0.11, depth));
		col = mix(col, trim_color, band * 0.8);
		glow = band * 0.6;
		ROUGHNESS = mix(0.85, 0.5, drip);
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow;
}
