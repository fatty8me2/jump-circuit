shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Frostbite Pass: a pane of thin ice. Clear and glassy with a frosted rim; once stood on,
// white cracks spread out from the first footprint (`origin`, local XZ) as `crack` runs
// 0 -> 1, glowing brighter the closer it is to giving way. `fade` fades a regrowing pane in.

uniform vec3 tint : source_color = vec3(0.62, 0.86, 1.0);
uniform vec3 deep : source_color = vec3(0.12, 0.32, 0.62);
uniform vec3 crack_color : source_color = vec3(0.85, 1.0, 1.0);
uniform vec3 half_size = vec3(1.0, 0.15, 1.0);
uniform vec2 origin = vec2(0.0, 0.0);
uniform float crack = 0.0;
uniform float fade = 1.0;

varying vec3 lp;
varying vec3 ln;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// distance between the two nearest cell points: small along the cell borders
float borders(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(ip + g);
			float d = length(g + o - fp);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	vec3 col = mix(deep, tint, 0.55 + 0.45 * fres);
	float lines = 0.0;
	float frost = 0.0;
	if (ln.y > 0.6) {
		vec2 d2 = half_size.xz - abs(lp.xz);
		float edge = min(d2.x, d2.y);
		frost = 1.0 - smoothstep(0.0, 0.28, edge);
		float dist = length(lp.xz - origin);
		float reach = crack * (length(half_size.xz) * 2.0 + 0.4);
		float within = 1.0 - smoothstep(reach - 0.35, reach, dist);
		float cells = 1.0 - smoothstep(0.0, 0.045, borders(lp.xz * 1.7 + vec2(3.7, 1.3)));
		float ang = atan(lp.z - origin.y, lp.x - origin.x);
		float spokes = 1.0 - smoothstep(0.0, 0.08, abs(sin(ang * 3.0 + dist * 0.9)) * (0.3 + dist));
		lines = max(cells, spokes * step(0.001, crack)) * within * step(0.001, crack);
		col = mix(col, vec3(0.92, 0.97, 1.0), frost * 0.6);
		col = mix(col, crack_color, lines);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.05, 0.5, frost);
	SPECULAR = 0.8;
	RIM = 0.5;
	RIM_TINT = 0.4;
	EMISSION = tint * 0.18 + crack_color * lines * (0.8 + 3.0 * crack) + vec3(0.5, 0.85, 1.0) * fres * 0.2;
	ALPHA = clamp((0.62 + 0.3 * fres + 0.25 * frost + lines) * fade, 0.0, 1.0);
}
