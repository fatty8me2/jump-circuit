shader_type spatial;
// Storm Armada walkable surface: the platform shader's layout (bright top, inset trim line,
// darker sides) re-done as rain-soaked ship's timber. Tops are deck planks running along the
// platform's long side, with caulked seams, butt joints, trenails and wet, glossy patches where
// the rain pools; the trim is a brass strip round the edge. Sides are clinker strakes with a brass
// band under the lip. Same uniforms as visual/platform.gdshader, so the level can swap it in.

uniform vec3 top_color : source_color = vec3(0.62, 0.45, 0.3);
uniform vec3 side_color : source_color = vec3(0.36, 0.24, 0.16);
uniform vec3 trim_color : source_color = vec3(0.95, 0.75, 0.3);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 brass : source_color = vec3(0.88, 0.64, 0.3);

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;

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
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	float rough = 0.8;
	float metal = 0.0;
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// planks run along the longer side: u across the planks, v along them
		bool along_z = half_size.z >= half_size.x;
		float u = along_z ? lp.x : lp.z;
		float v = along_z ? lp.z : lp.x;
		float pw = 0.3;
		float row = floor(u / pw);
		float fu = fract(u / pw);
		float seam = 1.0 - smoothstep(0.0, 0.06, min(fu, 1.0 - fu));
		// staggered butt joints every couple of metres
		float plank_len = 2.4;
		float vv = v / plank_len + hash12(vec2(row, 3.7));
		float fv = fract(vv);
		float butt = 1.0 - smoothstep(0.0, 0.012, min(fv, 1.0 - fv));
		float id = hash12(vec2(row, floor(vv)));
		vec3 plank = top_color * (0.82 + 0.3 * id);
		// grain
		float grain = noise2(vec2(u * 30.0, v * 1.5 + id * 20.0));
		plank *= 0.9 + 0.16 * grain;
		// trenails at the plank ends
		vec2 nail = vec2(fu - 0.5, (fv < 0.5 ? fv : fv - 1.0) * plank_len);
		float trenail = 1.0 - smoothstep(0.03, 0.05, length(vec2(abs(nail.x) - 0.25, nail.y - 0.1) * vec2(pw, 1.0)));
		col = plank * (1.0 - 0.55 * max(seam, butt));
		col = mix(col, top_color * 0.45, trenail * 0.6);
		// rain: wet dark patches that shine
		float wet = smoothstep(0.45, 0.75, noise2(wp.xz * 0.35) * 0.7 + noise2(wp.xz * 1.3) * 0.3);
		col *= 1.0 - 0.25 * wet;
		rough = mix(0.72, 0.18, wet);
		// the brass edging strip that marks every landing's edge
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		rough = mix(rough, 0.3, trim);
		metal = trim * 0.6;
		glow = trim;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		rough = 0.9;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		// clinker strakes: overlapping horizontal planks, each slightly shaded at its lower edge
		float sk = fract(wp.y / 0.32);
		float strake = smoothstep(0.0, 0.25, sk);
		float along = abs(ln.x) > abs(ln.z) ? wp.z : wp.x;
		float id = hash12(vec2(floor(wp.y / 0.32), floor(along / 3.1)));
		col = side_color * (0.8 + 0.25 * id) * (0.72 + 0.28 * strake);
		col *= 0.9 + 0.14 * noise2(vec2(along * 1.5, wp.y * 20.0));
		col = mix(col * 0.6, col, smoothstep(0.0, 0.8, h));
		// a brass band just under the lip, with rivets
		float band = smoothstep(0.1, 0.12, depth) * (1.0 - smoothstep(0.24, 0.26, depth));
		float rivet = 1.0 - smoothstep(0.03, 0.05, length(vec2(fract(along / 0.5) - 0.5, (depth - 0.18) * 2.0)) );
		col = mix(col, brass * (0.8 + 0.3 * rivet), band);
		rough = mix(0.82, 0.35, band);
		metal = band * 0.7;
		glow = band * 0.4;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = trim_color * glow * trim_glow;
}
