shader_type sky;
// Coral Depths: the view from under the sea. No sun disc - a bright rippled window
// overhead (the surface seen from below), faint rays fanning down from it, aqua haze
// at eye level and the abyss darkening below. Static (no TIME) so the radiance map
// is baked once.

uniform vec3 surface_color : source_color = vec3(0.75, 1.0, 1.0);
uniform vec3 top_color : source_color = vec3(0.12, 0.55, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.05, 0.34, 0.45);
uniform vec3 deep_color : source_color = vec3(0.0, 0.04, 0.09);

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float cells(vec2 p) {
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

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.75, up));
	col = mix(col, deep_color, smoothstep(0.02, -0.55, up));
	// Snell's window: the bright disc of the surface straight overhead, rippled
	float window = smoothstep(0.62, 0.93, up);
	vec2 uv = d.xz / max(up, 0.08);
	float rip = 1.0 - smoothstep(0.0, 0.2, cells(uv * 2.2));
	col = mix(col, surface_color, window * (0.55 + 0.35 * rip));
	// rays fanning down from the window
	float ang = atan(d.x, d.z);
	float rays = pow(0.5 + 0.5 * sin(ang * 19.0 + sin(ang * 5.0) * 2.5), 6.0);
	rays *= smoothstep(0.05, 0.6, up) * (1.0 - window);
	col += surface_color * rays * 0.12;
	COLOR = col;
}
