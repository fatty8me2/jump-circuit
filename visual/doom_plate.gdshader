shader_type spatial;
// Doom Fortress walkable surface: the platform shader's layout (top, inset trim, darker sides)
// re-done as the doomsday machine's deck plating. Tops are worn gunmetal plates with welded seams, a
// faint diamond tread and rivets at the corners; the trim round the edge is a band of hazard stripes.
// Sides are riveted black iron with a thin alarm-lit strip under the lip and rust streaks below.
// Same uniforms as visual/platform.gdshader so the level can swap it in. Bounded and NaN-safe.

uniform vec3 top_color : source_color = vec3(0.30, 0.30, 0.32);
uniform vec3 side_color : source_color = vec3(0.10, 0.10, 0.11);
uniform vec3 trim_color : source_color = vec3(1.0, 0.62, 0.06);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.16;
uniform float trim_glow = 0.0;

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
	float rough = 0.55;
	float metal = 0.55;
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// plates and welded seams on a 1.6 m grid (local space, so moving parts carry their plating)
		vec2 cell = lp.xz / 1.6;
		vec2 g = abs(fract(cell) - 0.5);
		float seam = 1.0 - smoothstep(0.0, 0.025, 0.5 - max(g.x, g.y));
		float id = hash12(floor(cell));
		col = top_color * (0.8 + 0.22 * id);
		// diamond tread
		vec2 tp = lp.xz * 5.0;
		vec2 tr = abs(fract(vec2(tp.x + tp.y, tp.x - tp.y) * 0.5) - 0.5);
		float tread = smoothstep(0.32, 0.36, min(tr.x, tr.y));
		col *= 1.0 - 0.08 * tread;
		// scuffs and soot
		float grime = noise2(lp.xz * 0.9) * 0.6 + noise2(lp.xz * 4.0) * 0.4;
		col *= 0.78 + 0.3 * grime;
		col *= 1.0 - 0.4 * seam;
		// rivets near each plate corner
		vec2 rc = abs(fract(cell) - 0.5);
		float rv = 1.0 - smoothstep(0.03, 0.045, length(rc - vec2(0.42, 0.42)));
		col = mix(col, top_color * 1.5, rv * 0.7);
		// hazard stripes round the edge
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(0.02, 0.04, edge);
		float trim = outer * (1.0 - inner);
		float stripe = step(0.5, fract((lp.x + lp.z) * 1.6));
		vec3 band = mix(vec3(0.03, 0.03, 0.03), trim_color, stripe);
		col = mix(col, band, trim);
		glow = trim * stripe;
		rough = mix(0.5, 0.75, trim);
		metal = mix(0.6, 0.1, trim);
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		rough = 0.9;
	} else {
		float depth = half_size.y - lp.y;
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		col = mix(side_color * 0.7, side_color, smoothstep(0.0, 1.0, h));
		// rivet rows along the side
		float along = (abs(ln.x) > 0.5) ? lp.z : lp.x;
		float rr = 1.0 - smoothstep(0.035, 0.05, length(vec2(fract(along * 2.5) - 0.5, (depth - 0.32) * 2.5)));
		col = mix(col, side_color * 2.4, rr * 0.8);
		// the alarm-lit strip under the lip
		float band = smoothstep(0.09, 0.11, depth) * (1.0 - smoothstep(0.17, 0.19, depth));
		col = mix(col, trim_color * 0.85, band);
		glow = band * 0.7;
		// rust streaks running down
		float rust = smoothstep(0.55, 0.85, noise2(vec2(along * 3.0, depth * 0.4)));
		col = mix(col, vec3(0.22, 0.09, 0.04), rust * 0.45 * step(0.25, depth));
		rough = 0.8;
		metal = 0.4;
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = trim_color * clamp(glow * trim_glow, 0.0, 3.0);
}
