shader_type spatial;
// Dino Valley tar pit: black, glossy and slow. The top is a heaving skin of tar with an oily violet
// sheen, rings spreading from bubbles that rise and pop, and (as you sink) a warm bruise-red glow
// creeping in so the danger reads before it bites. Sides are sticky dark brown drips.
// Bounded everywhere: no divide by a value that can be zero, no pow of a negative.

uniform vec3 tar : source_color = vec3(0.045, 0.04, 0.05);
uniform vec3 sheen : source_color = vec3(0.34, 0.2, 0.5);
uniform vec3 warn_col : source_color = vec3(1.0, 0.32, 0.1);
// 0 fresh .. 1 about to swallow you
uniform float danger = 0.0;
uniform vec3 half_size = vec3(3.0, 0.5, 3.0);

varying vec3 wp;
varying vec3 lp;
varying vec3 ln;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	return vec2(hash21(p), hash21(p + vec2(17.3, 5.1)));
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
	if (NORMAL.y > 0.6) {
		VERTEX.y += 0.025 * sin(wp.x * 1.7 + TIME * 1.3) * sin(wp.z * 1.3 - TIME * 0.9);
	}
}

void fragment() {
	if (ln.y > 0.6) {
		vec2 p = wp.xz;
		float n = vnoise(p * 1.1 + vec2(TIME * 0.12, -TIME * 0.09));
		float n2 = vnoise(p * 3.1 - vec2(TIME * 0.2, TIME * 0.15));
		// bubbles: one candidate per cell, a ring spreading and fading as it pops
		vec2 q = p * 0.8;
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float id = hash21(cell);
		vec2 centre = 0.25 + 0.5 * hash22(cell + 3.7);
		float life = fract(TIME * (0.18 + 0.1 * id) + id * 5.0);
		float on = step(0.45 - 0.25 * danger, id);
		float ring = (1.0 - smoothstep(0.0, 0.035, abs(length(f - centre) - life * 0.3))) * (1.0 - life) * on;
		float fres = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
		vec3 col = tar * (0.7 + 0.8 * n);
		col += sheen * (0.12 + 0.55 * n2) * (0.25 + fres);
		col += vec3(0.5, 0.45, 0.5) * ring * 0.5;
		float edge = min(half_size.x - abs(lp.x), half_size.z - abs(lp.z));
		col = mix(col, tar * 0.5, 1.0 - smoothstep(0.0, 0.5, edge));
		ALBEDO = min(col, vec3(1.0));
		ROUGHNESS = 0.1;
		METALLIC = 0.25;
		SPECULAR = 0.9;
		EMISSION = warn_col * danger * (0.12 + 0.35 * n) + sheen * ring * 0.4;
	} else {
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		float drip = vnoise(vec2((abs(ln.x) > abs(ln.z) ? wp.z : wp.x) * 2.3, 1.0));
		vec3 col = mix(vec3(0.1, 0.07, 0.05), tar, smoothstep(0.35, 0.95, h + drip * 0.4));
		ALBEDO = col;
		ROUGHNESS = 0.5;
	}
}
