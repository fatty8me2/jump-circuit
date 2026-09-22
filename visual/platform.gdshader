shader_type spatial;
// Stylised architectural block: bright walkable top with an inset trim line and
// faint paving grid, darker banded sides that fade toward the underside.

uniform vec3 top_color : source_color = vec3(0.85, 0.82, 0.74);
uniform vec3 side_color : source_color = vec3(0.45, 0.42, 0.5);
uniform vec3 trim_color : source_color = vec3(1.0, 0.75, 0.3);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform float grid_size = 2.0;

varying vec3 lp;
varying vec3 ln;

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
		vec2 g = abs(fract(lp.xz / grid_size) - 0.5);
		float grid = 1.0 - smoothstep(0.0, 0.02, 0.5 - max(g.x, g.y));
		col = top_color * (1.0 - 0.09 * grid);
		float inner = smoothstep(trim_width, trim_width + 0.02, edge) ;
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		ROUGHNESS = 0.78;
	} else if (ln.y < -0.6) {
		col = side_color * 0.55;
		ROUGHNESS = 0.9;
	} else {
		float h = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		col = mix(side_color * 0.62, side_color, smoothstep(0.0, 1.0, h));
		float band = smoothstep(0.16, 0.18, depth) * (1.0 - smoothstep(0.30, 0.32, depth));
		col = mix(col, trim_color * 0.9, band * 0.85);
		glow = band * 0.6;
		float ribs = smoothstep(0.46, 0.5, abs(fract(depth * 0.9) - 0.5));
		col *= 1.0 - 0.12 * ribs * step(0.4, depth);
		ROUGHNESS = 0.85;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow;
}
