shader_type spatial;
// Lotus Drift's walkable surfaces, one shader for all four kinds (same uniforms as
// visual/platform.gdshader so a pass can swap it in place; `kind` picks the look):
//   0 flagstone  - warm grey paving in staggered slabs, mortar lines, moss creeping in from the edge
//   1 lily pad   - a round green leaf: veins fanning from the middle, a pale rim, a wedge notch
//   2 deck       - dark planks of a garden bridge, running along the long side, pegged at the ends
//   3 island     - raked pale gravel with a ring of dark moss (checkpoint isles and the finish)
// A soft lantern-gold trim glows round the top edge of flagstone and deck. Sides darken toward the
// water. Every divide is guarded and every sqrt/pow/atan input is clamped, so it is NaN-free.

uniform vec3 top_color : source_color = vec3(0.6, 0.58, 0.62);
uniform vec3 side_color : source_color = vec3(0.3, 0.3, 0.38);
uniform vec3 trim_color : source_color = vec3(1.0, 0.66, 0.25);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform int kind = 0;
uniform vec3 moss_color : source_color = vec3(0.22, 0.4, 0.22);
uniform vec3 pad_color : source_color = vec3(0.16, 0.5, 0.3);
uniform vec3 wood_color : source_color = vec3(0.34, 0.2, 0.14);

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
	vec3 col = top_color;
	float glow = 0.0;
	float rough = 0.8;
	float edge;
	if (is_round) {
		edge = half_size.x - length(lp.xz);
	} else {
		vec2 d = half_size.xz - abs(lp.xz);
		edge = min(d.x, d.y);
	}
	if (ln.y > 0.6) {
		if (kind == 1) {
			// lily pad: veins fan out from the middle, the rim is paler, one wedge is missing
			float r = length(lp.xz);
			float ang = atan(lp.z, lp.x + 0.0001);
			float rn = r / max(half_size.x, 0.05);
			float vein = abs(sin(ang * 9.0 + noise2(vec2(ang * 3.0, 1.0)) * 0.8));
			vein = smoothstep(0.82, 1.0, vein) * smoothstep(0.1, 0.35, rn) * (1.0 - smoothstep(0.82, 0.98, rn));
			vec3 inner = pad_color * 0.8;
			vec3 outer = pad_color * 1.35 + vec3(0.04, 0.07, 0.0);
			col = mix(inner, outer, smoothstep(0.1, 0.95, rn));
			col = mix(col, pad_color * 1.7, vein * 0.55);
			col *= 0.9 + 0.2 * noise2(lp.xz * 3.0);
			float rim = smoothstep(0.9, 0.97, rn);
			col = mix(col, pad_color * 1.7 + vec3(0.1, 0.1, 0.02), rim * 0.6);
			// the notch: a thin wedge where the leaf is split (dark water showing through)
			float notch_a = abs(mod(ang - 0.9 + 3.14159, 6.28318) - 3.14159);
			float notch = (1.0 - smoothstep(0.05, 0.11, notch_a)) * smoothstep(0.08, 0.2, rn);
			col = mix(col, vec3(0.03, 0.09, 0.13), notch * 0.9);
			// dew
			float dew = step(0.985, hash12(floor(lp.xz * 6.0)));
			col += vec3(0.3, 0.4, 0.4) * dew * 0.4;
			rough = 0.38;
		} else if (kind == 2) {
			// deck: planks along the long side, a seam every 0.5 m, pegs at the plank ends
			bool along_x = half_size.x > half_size.z;
			float across = along_x ? lp.z : lp.x;
			float along = along_x ? lp.x : lp.z;
			float plank = floor((across + 100.0) / 0.5);
			float seam = smoothstep(0.012, 0.03, abs(fract((across + 100.0) / 0.5) - 0.5) * 0.5 - 0.235 + 0.012) ;
			float joint = floor((along + 100.0) / 3.0 + hash12(vec2(plank, 3.0)));
			col = wood_color * (0.8 + 0.5 * hash12(vec2(plank, joint)));
			col *= 0.92 + 0.1 * noise2(vec2(along * 1.5, across * 9.0));
			float line = 1.0 - smoothstep(0.0, 0.02, abs(fract((across + 100.0) / 0.5) - 0.5) * 0.5 - 0.23);
			col = mix(col, wood_color * 0.35, clamp(line, 0.0, 1.0) * 0.8);
			float joint_line = 1.0 - smoothstep(0.0, 0.03, abs(fract((along + 100.0) / 3.0 + hash12(vec2(plank, 3.0))) - 0.5) * 3.0 - 1.4);
			col = mix(col, wood_color * 0.3, clamp(joint_line, 0.0, 1.0) * 0.6);
			rough = 0.82 - 0.15 * seam;
		} else if (kind == 3) {
			// island: raked gravel in rings, a band of moss at the rim
			float r2 = length(lp.xz);
			float rake = 0.5 + 0.5 * sin(r2 * 5.0 + noise2(lp.xz * 0.8) * 3.0);
			col = top_color * (0.88 + 0.16 * rake);
			col *= 0.94 + 0.12 * noise2(lp.xz * 7.0);
			float m2 = (1.0 - smoothstep(0.0, 0.7, edge)) * (0.5 + 0.5 * noise2(lp.xz * 1.6 + vec2(4.0, 9.0)));
			col = mix(col, moss_color, clamp(m2, 0.0, 0.9));
			rough = 0.9;
		} else {
			// flagstone: staggered slabs about 1.4 x 0.9 m, jittered tone, mortar, moss from the edge
			float row = floor(lp.z / 0.9);
			float xo = lp.x + 0.7 * mod(row, 2.0);
			float cell = floor(xo / 1.4);
			float tone = hash12(vec2(cell, row));
			col = top_color * (0.84 + 0.3 * tone);
			col = mix(col, top_color * vec3(0.9, 0.92, 1.05), step(0.7, tone) * 0.5);
			vec2 f = vec2(abs(fract(xo / 1.4) - 0.5) * 1.4, abs(fract(lp.z / 0.9) - 0.5) * 0.9);
			float mortar = smoothstep(0.64, 0.69, f.x) + smoothstep(0.41, 0.445, f.y);
			col = mix(col, side_color * 0.55, clamp(mortar, 0.0, 1.0) * 0.8);
			float m3 = (1.0 - smoothstep(0.0, 0.7, edge)) * (0.35 + 0.65 * noise2(lp.xz * 1.3));
			m3 += clamp(mortar, 0.0, 1.0) * 0.25 * noise2(lp.xz * 3.0 + vec2(8.0, 2.0));
			col = mix(col, moss_color, clamp(m3, 0.0, 0.8));
			rough = 0.8;
		}
		// the lantern-gold trim round the top edge (flagstone and deck only; pads and gravel stay soft)
		if (kind == 0 || kind == 2) {
			float inner = smoothstep(0.1, 0.12, edge);
			float outer = smoothstep(0.02, 0.04, edge);
			float trim = outer * (1.0 - inner);
			col = mix(col, trim_color, trim * 0.85);
			glow = trim;
		}
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		rough = 0.9;
	} else {
		float depth = half_size.y - lp.y;
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		vec3 base = (kind == 1) ? pad_color * 0.9 : ((kind == 2) ? wood_color * 0.8 : side_color);
		col = mix(base * 0.5, base, smoothstep(0.0, 1.0, h));
		float stripes = 0.88 + 0.12 * noise2(vec2(lp.x * 2.0 + lp.z * 2.0, lp.y * 6.0));
		col *= stripes;
		if (kind == 0 || kind == 3) {
			float moss_line = 1.0 - smoothstep(0.0, 0.5, depth);
			col = mix(col, moss_color * 0.8, moss_line * (0.35 + 0.5 * noise2(vec2(lp.x * 1.4 + lp.z * 1.4, 2.0))));
		}
		rough = 0.88;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = trim_color * min(glow, 1.0) * (0.35 + trim_glow * 0.5);
}
