shader_type spatial;
// The Void's tumbling rooms: a cube whose four faces around its turning axis (local X) are four
// different floors of a little dream room - a chessboard, parquet, diamond wallpaper and a tiled
// floor with a window let into it - so whichever face is up reads as somewhere to stand, and when
// it turns, a wall becomes the floor. The two end faces are walls with a door. A pink trim runs
// round every face; `edge_glow` lights it up as the warning before a turn.
// NaN-safe: no pow / normalize / division by uniforms that can be zero.

uniform float half_size = 0.7;
uniform float edge_glow = 0.0;
uniform vec3 light_col : source_color = vec3(0.93, 0.92, 0.97);
uniform vec3 dark_col : source_color = vec3(0.16, 0.12, 0.24);
uniform vec3 trim_col : source_color = vec3(1.0, 0.36, 0.72);
uniform vec3 alt_col : source_color = vec3(0.32, 0.9, 1.0);

varying vec3 lp;
varying vec3 ln;

float checker(vec2 p) {
	vec2 c = floor(p);
	return mod(c.x + c.y, 2.0);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	float hs = max(half_size, 0.05);
	vec3 n = ln;
	vec3 an = abs(n);
	vec2 uv;
	int face;
	if (an.x > 0.6) {
		uv = lp.zy;
		face = 4;
	} else if (an.y > 0.6) {
		uv = lp.xz;
		face = n.y > 0.0 ? 0 : 1;
	} else {
		uv = lp.xy;
		face = n.z > 0.0 ? 2 : 3;
	}
	// 0..1 across the face
	vec2 f = clamp(uv / (2.0 * hs) + 0.5, vec2(0.0), vec2(1.0));
	vec3 col = light_col;
	float win_glow = 0.0;
	float door_glow = 0.0;
	if (face == 0) {
		// chessboard, three by three
		col = mix(light_col, dark_col, checker(f * 3.0));
	} else if (face == 1) {
		// parquet: alternating strips
		float s = checker(vec2(f.x * 4.0, floor(f.y * 8.0) * 0.5));
		col = mix(light_col * 0.92, mix(light_col, dark_col, 0.55), s);
	} else if (face == 2) {
		// diamond wallpaper
		vec2 d = abs(fract(f * 3.0 + vec2(0.5 * floor(f.y * 3.0), 0.0)) - 0.5);
		float dia = 1.0 - smoothstep(0.32, 0.36, d.x + d.y);
		col = mix(light_col, mix(light_col, alt_col, 0.35), dia);
	} else if (face == 3) {
		// pale tiles with a window looking out into the void
		vec2 g = abs(fract(f * 4.0) - 0.5);
		float grout = 1.0 - smoothstep(0.44, 0.47, max(g.x, g.y));
		col = light_col * (0.82 + 0.18 * grout);
		vec2 w = abs(f - vec2(0.5));
		float win = 1.0 - smoothstep(0.17, 0.19, max(w.x, w.y));
		col = mix(col, dark_col * 0.6, win);
		win_glow = win * 0.6 * (0.5 + 0.5 * f.y);
	} else {
		// the end walls: a door, its frame lit from within
		col = mix(light_col * 0.85, dark_col, 0.2);
		vec2 dd = abs(f - vec2(0.5, 0.42));
		float door = 1.0 - smoothstep(0.0, 0.01, max(dd.x - 0.17, dd.y - 0.3));
		float frame = (1.0 - smoothstep(0.0, 0.01, max(dd.x - 0.2, dd.y - 0.33))) * (1.0 - door);
		col = mix(col, dark_col, door);
		col = mix(col, alt_col, frame);
		door_glow = frame * 1.2;
	}
	// trim round every face
	vec2 e = min(f, 1.0 - f);
	float edge = min(e.x, e.y) * 2.0 * hs;
	float trim = 1.0 - smoothstep(0.07, 0.09, edge);
	col = mix(col, trim_col, trim);
	ALBEDO = col;
	ROUGHNESS = 0.6;
	EMISSION = trim_col * trim * (0.4 + clamp(edge_glow, 0.0, 4.0)) + alt_col * door_glow * 0.6 + trim_col * win_glow * 0.4;
}
