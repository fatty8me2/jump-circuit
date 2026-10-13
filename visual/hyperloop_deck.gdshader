shader_type spatial;
// Hyperloop's decks: white ceramic transit panels. The top is a cool white skin cut into panels by
// hairline seams, with a bright cyan border line and a ring of landing-strip dashes just inside it (so
// an edge reads from far away at speed); the sides are brushed steel with fine horizontal grooves and
// a cyan light band under the lip. Same uniforms as visual/platform.gdshader so it replaces it in place.
// NaN-safe: every divide is guarded, no pow() of a negative.

uniform vec3 top_color : source_color = vec3(0.94, 0.97, 1.0);
uniform vec3 side_color : source_color = vec3(0.52, 0.62, 0.74);
uniform vec3 trim_color : source_color = vec3(0.22, 0.92, 1.0);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_glow = 0.0;
uniform float panel = 3.0;
uniform float dash_pitch = 1.1;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	float rough = 0.34;
	float metal = 0.0;
	if (ln.y > 0.6) {
		float edge;
		float along;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
			along = atan(lp.z, lp.x + 0.0001) * half_size.x;
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
			// distance travelled along the nearest edge (for the dashes)
			along = d.x < d.y ? lp.z : lp.x;
		}
		// ceramic panels: hairline seams every `panel` metres, a faint tint shift per panel
		vec2 pq = lp.xz / max(panel, 0.5);
		vec2 cell = floor(pq);
		vec2 f = abs(fract(pq) - 0.5);
		float seam = 1.0 - smoothstep(0.0, 0.025, 0.5 - max(f.x, f.y));
		float tint = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		col = top_color * (0.97 + 0.04 * tint);
		col = mix(col, side_color * 0.8, seam * 0.35);
		// the bright border line and the landing-strip dashes inside it
		float inner = smoothstep(0.12, 0.14, edge);
		float outer = smoothstep(0.04, 0.06, edge);
		float line = outer * (1.0 - inner);
		float dashes_zone = smoothstep(0.24, 0.26, edge) * (1.0 - smoothstep(0.42, 0.44, edge));
		float dash = step(0.5, fract(along / max(dash_pitch, 0.3))) * dashes_zone;
		col = mix(col, trim_color, clamp(line + dash * 0.55, 0.0, 1.0));
		glow = line + dash * 0.45;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		rough = 0.9;
	} else {
		float depth = half_size.y - lp.y;
		float h = clamp((lp.y + half_size.y) / max(2.0 * half_size.y, 0.001), 0.0, 1.0);
		col = mix(side_color * 0.6, side_color, smoothstep(0.0, 1.0, h));
		float band = smoothstep(0.13, 0.15, depth) * (1.0 - smoothstep(0.24, 0.26, depth));
		col = mix(col, trim_color * 0.85, band * 0.9);
		glow = band * 0.7;
		float grooves = smoothstep(0.42, 0.5, abs(fract(depth * 3.0) - 0.5));
		col *= 1.0 - 0.14 * grooves * step(0.35, depth);
		rough = 0.5;
		metal = 0.35;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = trim_color * glow * trim_glow;
}
