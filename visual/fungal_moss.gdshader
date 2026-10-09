shader_type spatial;
// Mushroom Hollow: a mossy bark-and-leaf-litter block. The walkable top is sun-warmed moss with
// clover flecks and a lighter, frayed rim (so the edge reads from far); the sides are rough
// brown bark with vertical grain and moss draping down from the top; the underside is dark. With
// `wood` set (a branch, a log) the top is pale wood with growth rings instead of moss.
// Same uniforms as platform.gdshader so Look's material parameters carry straight over.

uniform vec3 top_color : source_color = vec3(0.45, 0.66, 0.26);
uniform vec3 side_color : source_color = vec3(0.5, 0.34, 0.2);
uniform vec3 trim_color : source_color = vec3(1.0, 0.93, 0.7);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform bool wood = false;

varying vec3 lp;
varying vec3 ln;

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
		float n1 = noise2(lp.xz * 2.3);
		float n2 = noise2(lp.xz * 7.1 + vec2(11.0, 3.0));
		if (wood) {
			float rings = 0.5 + 0.5 * sin(length(lp.xz * vec2(1.0, 0.35)) * 14.0 + n1 * 3.0);
			col = top_color * (0.88 + 0.16 * rings) * (0.94 + 0.1 * n2);
			ROUGHNESS = 0.8;
		} else {
			col = top_color * (0.86 + 0.26 * n1) * (0.94 + 0.12 * n2);
			// clover flecks: little light blobs
			float fleck = smoothstep(0.80, 0.9, noise2(lp.xz * 9.0 + vec2(5.0, 9.0)));
			col = mix(col, top_color * 1.35 + vec3(0.04, 0.06, 0.0), fleck * 0.55);
			ROUGHNESS = 0.9;
		}
		// the rim: a pale frayed band of dry grass / bark edge
		float frayed = trim_width * (0.7 + 0.9 * noise2(lp.xz * 5.0 + vec2(2.0, 8.0)));
		float rim = 1.0 - smoothstep(frayed * 0.55, frayed, edge);
		col = mix(col, trim_color * 0.88, rim * 0.78);
		glow = rim * 0.35;
	} else if (ln.y < -0.6) {
		col = side_color * 0.42;
		ROUGHNESS = 0.95;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		float along = lp.x + lp.z;
		float grain = noise2(vec2(along * 5.0, lp.y * 0.6));
		float grain2 = noise2(vec2(along * 14.0, lp.y * 1.2 + 4.0));
		col = side_color * (0.62 + 0.38 * smoothstep(0.0, 1.0, h)) * (0.8 + 0.3 * grain) * (0.92 + 0.14 * grain2);
		// moss draping down from the top, ragged
		float drape = 0.16 + 0.3 * noise2(vec2(along * 3.0, 6.0));
		float m = 1.0 - smoothstep(drape * 0.7, drape, depth);
		if (!wood) {
			col = mix(col, top_color * 0.9, m);
		}
		ROUGHNESS = 0.92;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * (0.15 + trim_glow * 0.3);
}
