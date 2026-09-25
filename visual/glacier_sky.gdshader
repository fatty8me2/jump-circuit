shader_type sky;
render_mode use_debanding;
// Frostbite Pass: a clear polar night sky over the pass. Deep blue zenith, a cold teal
// afterglow low in the west, a dense star dome with the milky band, a big pale moon and
// a faint green-violet aurora glow painted behind the animated curtains the level hangs
// in front of it. Static (no TIME), so the radiance map is only rendered once.

uniform vec3 zenith : source_color = vec3(0.01, 0.02, 0.07);
uniform vec3 mid : source_color = vec3(0.04, 0.09, 0.2);
uniform vec3 horizon : source_color = vec3(0.2, 0.34, 0.5);
uniform vec3 afterglow : source_color = vec3(0.35, 0.5, 0.62);
uniform vec3 ground : source_color = vec3(0.16, 0.22, 0.32);
uniform vec3 moon_dir = vec3(-0.35, 0.42, -0.84);
uniform vec3 glow_dir = vec3(0.7, 0.05, 0.3);
uniform vec3 aurora_a : source_color = vec3(0.2, 0.9, 0.55);
uniform vec3 aurora_b : source_color = vec3(0.55, 0.3, 0.95);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

vec3 stars(vec3 d, float scale, float density, float size) {
	vec3 sd = d * scale;
	vec3 cell = floor(sd);
	vec3 f = fract(sd);
	float h = hash13(cell);
	if (h < 1.0 - density) {
		return vec3(0.0);
	}
	vec3 j = hash33(cell) * 0.6 + 0.2;
	float r = length(f - j);
	float k = smoothstep(size, 0.0, r);
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.8), hash13(cell + 7.0));
	return tint * k * (0.4 + 1.6 * fract(h * 37.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	vec3 col = mix(horizon, mid, smoothstep(0.0, 0.25, up));
	col = mix(col, zenith, smoothstep(0.2, 0.85, up));
	// the last cold light low in one quarter of the sky
	vec3 gd = normalize(glow_dir);
	float toward = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(gd.x, 0.0, gd.z))), 0.0);
	col += afterglow * pow(toward, 3.0) * exp(-max(up, 0.0) * 7.0) * 0.55;
	// stars and the milky band (fading into the horizon haze)
	float vis = smoothstep(0.02, 0.3, up);
	vec3 ba = normalize(vec3(0.3, 0.75, 0.55));
	float bd = dot(d, ba);
	float band = exp(-bd * bd / 0.03);
	col += vec3(0.1, 0.11, 0.18) * band * smoothstep(0.35, 0.85, fbm(d * 4.0)) * vis * 0.8;
	col += stars(d, 170.0, 0.014 + 0.03 * band, 0.16) * 1.3 * vis;
	col += stars(d, 400.0, 0.02 + 0.05 * band, 0.22) * 0.55 * vis;
	col += stars(d, 70.0, 0.006, 0.1) * 2.6 * vis;
	// a soft aurora glow behind the curtains: green low, violet above
	float ang = atan(d.x, d.z);
	float wav = sin(ang * 3.0 + fbm(d * 2.0) * 3.0) * 0.5 + 0.5;
	float lowband = exp(-pow((up - 0.28 - wav * 0.12) / 0.1, 2.0));
	float highband = exp(-pow((up - 0.48 - wav * 0.1) / 0.14, 2.0));
	float veil = smoothstep(0.3, 0.8, fbm(vec3(ang * 2.0, up * 3.0, 0.0)));
	col += aurora_a * lowband * veil * 0.22 + aurora_b * highband * veil * 0.12;
	// the moon: a big pale disc with faint maria and a halo
	vec3 md = normalize(moon_dir);
	float m = dot(d, md);
	float disc = smoothstep(0.99945, 0.99965, m);
	float maria = fbm(d * 60.0);
	col = mix(col, vec3(0.92, 0.95, 1.0) * (0.85 + 0.25 * maria), disc);
	col += vec3(0.5, 0.6, 0.8) * pow(max(m, 0.0), 600.0) * 0.8;
	col += vec3(0.3, 0.4, 0.6) * pow(max(m, 0.0), 30.0) * 0.12;
	// below the horizon: the snowfields lit by the moon, into haze
	col = mix(col, ground, smoothstep(0.0, -0.08, up));
	COLOR = col;
}
