shader_type sky;
// Cinder Peak: a red-black night under the eruption. Near-black zenith with a few stars
// struggling through the ash haze, smoke bands lit from below, a deep red glow along the
// horizon that swells toward the volcano (`volcano_dir`), and a darker, smoky underside.
// Static (no TIME), so the radiance map is baked once; the eruption's flashes are lights.

render_mode use_debanding;

uniform vec3 volcano_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 zenith : source_color = vec3(0.012, 0.008, 0.012);
uniform vec3 horizon : source_color = vec3(0.3, 0.06, 0.03);
uniform vec3 glow : source_color = vec3(0.95, 0.25, 0.05);
uniform vec3 smoke : source_color = vec3(0.1, 0.035, 0.03);
uniform vec3 ground : source_color = vec3(0.06, 0.02, 0.015);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise3(p);
		p = p * 2.02 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 vd = normalize(vec3(volcano_dir.x, 0.0, volcano_dir.z));
	float up = d.y;
	float toward = clamp(dot(normalize(vec3(d.x, 0.0, d.z)), vd), -1.0, 1.0);
	float lean = 0.5 + 0.5 * toward;
	// base gradient: black zenith down to a red horizon, brighter toward the volcano
	vec3 col = mix(horizon * (0.55 + 0.9 * lean * lean), zenith, smoothstep(-0.02, 0.55 - 0.2 * lean, up));
	// the glow dome over the eruption
	float dome = exp(-pow(max(up, 0.0) / (0.12 + 0.35 * lean), 2.0)) * pow(lean, 6.0);
	col += glow * dome * 0.55;
	// smoke bands drifting across the sky, lit from below near the horizon
	float s = fbm(vec3(d.x * 3.0, up * 9.0, d.z * 3.0));
	float band = smoothstep(0.45, 0.8, s) * smoothstep(0.7, 0.05, up) * step(0.0, up + 0.02);
	col = mix(col, smoke + glow * 0.18 * lean * (1.0 - up), band * 0.8);
	// a few stars through the haze, mostly away from the glow
	vec3 sd = d * 180.0;
	vec3 cell = floor(sd);
	float h = hash13(cell);
	if (h > 0.9965 && up > 0.15) {
		float k = smoothstep(0.35, 0.0, length(fract(sd) - 0.5));
		col += vec3(1.0, 0.85, 0.75) * k * (0.35 + 0.8 * fract(h * 91.0)) * smoothstep(0.15, 0.6, up) * (1.0 - band) * (1.0 - 0.8 * lean);
	}
	// below the horizon: the dark smoky lowlands with a faint lava-lit haze
	float below = smoothstep(0.02, -0.25, up);
	col = mix(col, ground + glow * 0.06 * lean, below);
	COLOR = col;
}
