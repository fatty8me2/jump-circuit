shader_type spatial;
// Toybox Tumble's floors: painted plastic building blocks. A top wide enough for it carries a grid of
// round studs (shaded so each reads as a little bump), a bright inset border keeps the edge readable,
// and the sides are glossy moulded plastic with a lighter band under the lip. Same uniforms as
// visual/platform.gdshader so it replaces it in place. NaN-safe: every divide is guarded.

uniform vec3 top_color : source_color = vec3(0.93, 0.27, 0.25);
uniform vec3 side_color : source_color = vec3(0.6, 0.15, 0.15);
uniform vec3 trim_color : source_color = vec3(1.0, 0.85, 0.2);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform float stud_pitch = 0.9;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	float rough = 0.45;
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		col = top_color;
		// studs: a centred grid of round bumps, only where the whole stud fits inside the border
		vec2 span = max(half_size.xz * 2.0 - vec2(0.7), vec2(0.0));
		vec2 cells = floor(span / max(stud_pitch, 0.1) + vec2(0.0001));
		if (cells.x >= 1.0 && cells.y >= 1.0) {
			vec2 origin = -cells * stud_pitch * 0.5;
			vec2 q = (lp.xz - origin) / max(stud_pitch, 0.1);
			vec2 cid = floor(q);
			if (cid.x >= 0.0 && cid.y >= 0.0 && cid.x < cells.x && cid.y < cells.y) {
				vec2 uv = (fract(q) - vec2(0.5)) / 0.34;
				float r = length(uv);
				float disc = 1.0 - smoothstep(0.92, 1.0, r);
				float lit = clamp(0.5 - 0.5 * dot(uv, vec2(0.6, 0.8)), 0.0, 1.0);
				float ring = smoothstep(0.7, 0.9, r) * (1.0 - smoothstep(0.92, 1.0, r));
				vec3 stud = top_color * (0.82 + 0.5 * lit);
				stud *= 1.0 - 0.28 * ring;
				col = mix(col, stud, disc);
				rough = mix(rough, 0.3, disc);
			}
		}
		float inner = smoothstep(0.13, 0.15, edge);
		float outer = smoothstep(0.04, 0.06, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		rough = 0.9;
	} else {
		float depth = half_size.y - lp.y;
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		col = mix(side_color * 0.7, side_color, smoothstep(0.0, 1.0, h));
		float band = smoothstep(0.1, 0.12, depth) * (1.0 - smoothstep(0.22, 0.24, depth));
		col = mix(col, top_color * 1.1, band * 0.6);
		rough = 0.35;
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	EMISSION = trim_color * glow * (0.15 + trim_glow * 0.6);
}
