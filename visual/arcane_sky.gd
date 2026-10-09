class_name ArcaneSky
extends RefCounted
## The Arcane Library's "sky": there is no sky, only the library going on for ever. Round you,
## on a great cylinder of distance, stand walls of bookshelves between stone piers, rank upon rank
## of leather spines in oxblood, indigo, green and gold with candle flames burning here and there
## (soft warm glows), fading up and down into violet haze. Overhead the shelves give way to the
## ribs of a dark vault; below, they run on down into purple dark. One tall ROSE WINDOW of violet,
## rose and gold stained glass hangs low in one quarter, lit from behind, with a halo of light.
## Static (no TIME), so the radiance map is rendered once. Every term is bounded and NaN-safe: no
## pow() of negatives, no normalize() of a zero vector, smoothstep edges in order, divisions guarded.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 vault : source_color = vec3(0.02, 0.012, 0.055);
uniform vec3 haze : source_color = vec3(0.2, 0.09, 0.26);
uniform vec3 glow : source_color = vec3(1.0, 0.56, 0.2);
uniform vec3 violet : source_color = vec3(0.56, 0.32, 1.0);
uniform vec3 gold : source_color = vec3(1.0, 0.78, 0.35);
uniform vec3 window_dir = vec3(0.55, 0.3, -0.78);

float h11(float n) {
	return fract(sin(n * 127.1 + 31.7) * 43758.5453);
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 book_color(float r) {
	if (r < 0.2) return vec3(0.42, 0.07, 0.1);
	if (r < 0.4) return vec3(0.1, 0.12, 0.36);
	if (r < 0.55) return vec3(0.08, 0.26, 0.17);
	if (r < 0.7) return vec3(0.36, 0.2, 0.08);
	if (r < 0.82) return vec3(0.3, 0.1, 0.34);
	if (r < 0.92) return vec3(0.5, 0.38, 0.14);
	return vec3(0.16, 0.14, 0.18);
}

// one cylinder of shelves: az in [-pi, pi], yc = height on the cylinder, n piers round it
vec3 shelves(float az, float yc, float n, float rows, float seed, out float lit) {
	float u = (az + 3.14159265) / 6.2831853 * n;
	float cell = floor(u);
	float cid = mod(cell, n);
	float fu = fract(u);
	float rr = yc * rows;
	float row = floor(rr);
	float fr = fract(rr);
	lit = 0.0;
	// the stone piers between bays, with a gold seam
	if (fu < 0.07 || fu > 0.93) {
		float seam = 1.0 - smoothstep(0.0, 0.012, abs(min(fu, 1.0 - fu) - 0.035));
		return vec3(0.1, 0.07, 0.12) + gold * seam * 0.2;
	}
	// shelf planks
	if (fr < 0.08) {
		return vec3(0.17, 0.09, 0.05);
	}
	float bu = (fu - 0.07) / 0.86;
	float nb = 20.0;
	float bi = floor(bu * nb);
	float hr = h21(vec2(cid * 31.0 + bi, row * 7.0 + seed));
	float hh = 0.5 + 0.42 * h21(vec2(bi + seed, cid + row * 3.0));
	float body = (fr - 0.08) / 0.92;
	vec3 col = vec3(0.025, 0.015, 0.03);
	if (body < hh && hr > 0.07) {
		col = book_color(h21(vec2(bi * 1.7 + cid, row + seed))) * (0.55 + 0.5 * fract(bu * nb));
		// a gilt band near the top of the spine
		col += gold * 0.14 * step(abs(body - hh * 0.85), 0.03);
	}
	// a candle burning in some bays: bright flame, warm light on the books around it
	float cr = h21(vec2(cid + seed * 3.0, row));
	if (cr > 0.86) {
		vec2 cp = vec2(bu - 0.5, fr - 0.3);
		float flame = 1.0 - smoothstep(0.0, 0.07, length(cp * vec2(1.0, 0.7)));
		float spill = 1.0 - smoothstep(0.0, 0.5, length(cp * vec2(0.8, 1.3)));
		col += glow * spill * 0.55 + vec3(1.6, 1.15, 0.6) * flame;
		lit = 1.0;
	}
	return col;
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	float lxz = max(length(d.xz), 0.0001);
	float az = atan(d.z / lxz, d.x / lxz);
	float yc = clamp(d.y / lxz, -8.0, 8.0);
	float up = d.y;
	vec3 col = vault;
	// two cylinders of shelves, a near one with big books and a far one with fine ones
	float lit1;
	float lit2;
	float fade = 1.0 - smoothstep(1.5, 5.0, abs(yc));
	vec3 s1 = shelves(az, yc * 0.55 + 0.02, 14.0, 5.0, 1.0, lit1);
	vec3 s2 = shelves(az + 0.1, yc * 0.9 + 0.03, 31.0, 7.0, 7.0, lit2);
	float far_k = smoothstep(0.55, 1.4, abs(yc));
	vec3 wall = mix(s1, s2 * 0.8, far_k);
	// the haze thickens with height and depth: warm at the horizon, violet away from it
	float hz = 1.0 - smoothstep(0.0, 1.2, abs(yc));
	wall = mix(wall, haze * 0.55, 0.38 + 0.4 * (1.0 - hz));
	wall += glow * hz * 0.05;
	col = mix(col, wall, fade);
	// the vault overhead: dark ribs converging on the zenith, picked out in violet
	if (up > 0.35) {
		float rib = 1.0 - smoothstep(0.0, 0.03, abs(fract(az / 6.2831853 * 10.0 + 0.5) - 0.5));
		float ring = 1.0 - smoothstep(0.0, 0.02, abs(fract(up * 3.2) - 0.5));
		col = mix(col, vault * 1.5, smoothstep(0.35, 0.7, up));
		col += violet * (rib * 0.08 + ring * 0.03) * smoothstep(0.35, 0.8, up);
	}
	// below: the library runs on down into purple dark
	col = mix(col, vault * 0.7, (1.0 - smoothstep(-0.9, 0.0, up)) * 0.75);
	// the rose window, lit from behind
	vec3 C = window_dir / max(length(window_dir), 0.0001);
	float cd = clamp(dot(d, C), -1.0, 1.0);
	float ang = acos(cd);
	if (ang < 0.42) {
		vec3 ax = cross(C, vec3(0.0, 1.0, 0.0));
		float al = length(ax);
		ax = al > 0.0001 ? ax / al : vec3(1.0, 0.0, 0.0);
		vec3 ay = cross(ax, C);
		vec2 q = vec2(dot(d, ax), dot(d, ay));
		float rr = length(q);
		float qa = atan(q.y, q.x + 0.00001);
		float R = 0.26;
		float face = 1.0 - smoothstep(R - 0.004, R, rr);
		float petal = floor((qa + 3.14159265) / 6.2831853 * 12.0);
		float pr = h11(petal + 3.0);
		vec3 glass = pr < 0.33 ? violet : (pr < 0.66 ? vec3(0.95, 0.3, 0.5) : gold);
		float ring_id = floor(rr / R * 3.0);
		glass = mix(glass, vec3(1.0, 0.9, 0.6), step(ring_id, 0.5) * 0.5);
		float sg = fract((qa + 3.14159265) / 6.2831853 * 12.0);
		float seg_d = min(sg, 1.0 - sg);
		float rg = fract(rr / R * 3.0);
		float ring_d = min(rg, 1.0 - rg);
		float lead = max(1.0 - smoothstep(0.0, 0.012, seg_d), 1.0 - smoothstep(0.0, 0.012, ring_d));
		float bright = 1.1 - 0.5 * smoothstep(0.0, R, rr);
		vec3 wc = glass * bright * (1.0 - 0.8 * clamp(lead, 0.0, 1.0));
		col = mix(col, wc, face);
		// the frame and a halo of light round it
		float frame = (1.0 - smoothstep(0.004, 0.012, abs(rr - R - 0.008)));
		col += gold * frame * 0.6;
		col += mix(violet, gold, 0.5) * (1.0 - smoothstep(R, 0.42, rr)) * 0.18 * (1.0 - face);
	}
	COLOR = clamp(col, vec3(0.0), vec3(3.0));
}
"""


static func make() -> Sky:
	var sh := Shader.new()
	sh.code = CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky
