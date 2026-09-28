shader_type spatial;
// Phantom Manor walkable surface: the platform shader's layout (bright top, inset trim line,
// darker sides) re-done for a haunted house. Outside (wood = 0) tops are worn, lichen-stained
// graveyard flagstones; inside (wood = 1) they are dark, scuffed oak floorboards. Sides are
// gothic ashlar courses with a moulding and a band of pale trefoil tracery under the lip. The
// trim line glows ectoplasm green. Same uniforms as visual/platform.gdshader (plus `wood`), so
// the level can swap it in. Every term is bounded (no pow of a negative, no normalize of zero).

uniform vec3 top_color : source_color = vec3(0.55, 0.52, 0.58);
uniform vec3 side_color : source_color = vec3(0.22, 0.18, 0.26);
uniform vec3 trim_color : source_color = vec3(0.6, 1.0, 0.7);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform float wood = 0.0;
uniform vec3 wood_color : source_color = vec3(0.34, 0.22, 0.17);
uniform vec3 moss_color : source_color = vec3(0.26, 0.34, 0.2);

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 wn;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), f.x), mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * n2(p);
		p = p * 2.03 + vec2(4.1, 1.3);
		a *= 0.5;
	}
	return s;
}

// Staggered courses: x = distance to the nearest joint (0 on a joint), y = per-block random.
vec2 courses(vec2 p, vec2 blk) {
	float row = floor(p.y / blk.y);
	float x = p.x / blk.x + 0.5 * mod(row, 2.0);
	vec2 f = vec2(fract(x), fract(p.y / blk.y));
	float d = min(min(f.x, 1.0 - f.x) * blk.x, min(f.y, 1.0 - f.y) * blk.y);
	return vec2(d, h12(vec2(floor(x), row)));
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
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// outside: flagstones with lichen creeping out of the joints
		vec2 fs = courses(wp.xz, vec2(1.5, 1.1));
		float joint = 1.0 - smoothstep(0.02, 0.06, fs.x);
		vec3 stone = top_color * (0.82 + 0.2 * fs.y) * (1.0 - 0.35 * joint);
		stone *= 0.85 + 0.2 * n2(wp.xz * 2.7);
		float lichen = smoothstep(0.5, 0.75, fbm(wp.xz * 0.7) + joint * 0.3);
		stone = mix(stone, moss_color, lichen * 0.55);
		// inside: long oak boards along whichever axis the slab is longer, nail heads, scuffs
		bool along_x = half_size.x > half_size.z;
		vec2 bp = along_x ? wp.xz : wp.zx;
		vec2 bd = courses(vec2(bp.x, bp.y), vec2(2.8, 0.26));
		float seam = 1.0 - smoothstep(0.008, 0.025, bd.x);
		float grain = sin(bp.y * 90.0 + n2(bp * vec2(0.6, 12.0)) * 6.0) * 0.5 + 0.5;
		vec3 oak = wood_color * (0.72 + 0.4 * bd.y) * (0.9 + 0.12 * grain) * (1.0 - 0.55 * seam);
		oak *= 0.8 + 0.25 * n2(wp.xz * 1.3);
		col = mix(stone, oak, clamp(wood, 0.0, 1.0));
		// the trim line that marks every landing's edge
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = mix(0.9, 0.62, clamp(wood, 0.0, 1.0));
	} else if (ln.y < -0.6) {
		col = side_color * 0.45;
		ROUGHNESS = 0.95;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		vec2 blk = courses(vec2(u, wp.y), vec2(1.2, 0.55));
		float joint = 1.0 - smoothstep(0.015, 0.045, blk.x);
		col = side_color * (0.8 + 0.3 * blk.y) * (1.0 - 0.4 * joint);
		col *= 0.8 + 0.3 * n2(vec2(u, wp.y) * 2.1);
		col = mix(col * 0.55, col, smoothstep(0.0, 0.8, h));
		// damp streaks running down from the lip
		float streak = smoothstep(0.55, 0.8, n2(vec2(u * 3.0, 0.5))) * smoothstep(0.1, 1.8, depth);
		col = mix(col, col * 0.6, streak * 0.5);
		// a pale moulding and a band of trefoil tracery under the lip
		float mould = (1.0 - smoothstep(0.02, 0.05, abs(depth - 0.12))) + (1.0 - smoothstep(0.02, 0.05, abs(depth - 0.52)));
		float band = smoothstep(0.16, 0.19, depth) * (1.0 - smoothstep(0.46, 0.49, depth));
		float cell = fract(u / 0.5) - 0.5;
		float arch = length(vec2(cell, (depth - 0.26) * 1.4));
		float lobe = abs(arch - 0.16);
		float tracery = (1.0 - smoothstep(0.018, 0.04, lobe)) * band;
		vec3 bone = vec3(0.78, 0.74, 0.66);
		col = mix(col, bone * 0.55, clamp(mould, 0.0, 1.0) * 0.8);
		col = mix(col, bone * 0.5, tracery * 0.75);
		col = mix(col, trim_color * 0.8, (1.0 - smoothstep(0.012, 0.03, abs(depth - 0.08))) * 0.9);
		glow = (1.0 - smoothstep(0.012, 0.03, abs(depth - 0.08))) * 0.6;
		ROUGHNESS = 0.9;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * clamp(trim_glow, 0.0, 3.0);
}
