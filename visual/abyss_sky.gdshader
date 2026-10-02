shader_type sky;
// The Abyss: the "sky" is the water itself. Straight up, a long way off, the last ghost of daylight
// - a faint, slowly rippling smear of blue-green from a surface you will never see; it fades to
// nothing well above the horizon. Level and below: black water with the faintest blue cast, and a
// few very dim, slowly blinking specks of distant life. Everything is bounded (no NaN, no blow-out).

uniform vec3 zenith : source_color = vec3(0.02, 0.09, 0.12);
uniform vec3 deep : source_color = vec3(0.004, 0.012, 0.022);
uniform vec3 floor_col : source_color = vec3(0.0, 0.004, 0.008);
uniform float time_scale = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 col = mix(deep, floor_col, 1.0 - smoothstep(-0.6, 0.0, up));
	// the far-off surface light, only near the zenith
	float z = smoothstep(0.45, 1.0, up);
	vec2 p = d.xz / max(d.y, 0.2) * 3.0;
	float t = TIME * time_scale;
	float rip = noise(p + vec2(t, -t * 0.7)) * 0.6 + noise(p * 2.3 - vec2(t * 1.3, t)) * 0.4;
	col += zenith * z * (0.55 + 0.6 * rip);
	// dim specks of life far off in the dark (around and below the horizon), blinking slowly
	float dx = abs(d.x) < 1e-4 ? 1e-4 : d.x;
	vec2 q = vec2(atan(d.z, dx) * 40.0, up * 60.0);
	vec2 cell = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = hash(cell);
	float spec = (1.0 - smoothstep(0.05, 0.14, length(f))) * step(0.985, h) * (1.0 - z);
	float blink = 0.5 + 0.5 * sin(TIME * (0.4 + h * 1.3) + h * 40.0);
	col += mix(vec3(0.1, 0.5, 0.6), vec3(0.5, 0.2, 0.6), fract(h * 13.0)) * spec * blink * 0.6;
	COLOR = clamp(col, vec3(0.0), vec3(2.0));
}
