shader_type sky;
render_mode use_debanding;
// Aurora Run: a perfectly clear mountain night. A deep indigo dome packed with stars and the milky band,
// a cold teal glow along the horizon, and a broad green / teal / violet wash painted across the sky ahead
// (-Z) behind the animated curtains the level hangs in front of it. Static (no TIME), so the radiance map
// is rendered once. Every divide and pow is guarded; brightness is bounded.

uniform vec3 zenith : source_color = vec3(0.006, 0.010, 0.045);
uniform vec3 mid : source_color = vec3(0.02, 0.05, 0.14);
uniform vec3 horizon : source_color = vec3(0.07, 0.24, 0.32);
uniform vec3 ground : source_color = vec3(0.05, 0.10, 0.16);
uniform vec3 aurora_a : source_color = vec3(0.15, 1.0, 0.55);
uniform vec3 aurora_b : source_color = vec3(0.12, 0.75, 1.0);
uniform vec3 aurora_c : source_color = vec3(0.70, 0.30, 1.0);
uniform vec3 glow_dir = vec3(0.0, 0.0, -1.0);
uniform float wash = 0.32;

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
	vec3 tint = mix(vec3(0.7, 0.85, 1.0), vec3(1.0, 0.92, 0.8), hash13(cell + 7.0));
	return tint * k * (0.4 + 1.6 * fract(h * 37.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	vec3 col = mix(horizon, mid, smoothstep(0.0, 0.22, up));
	col = mix(col, zenith, smoothstep(0.18, 0.8, up));
	// stars and the milky band, fading into the horizon haze
	float vis = smoothstep(0.015, 0.28, up);
	vec3 ba = normalize(vec3(0.5, 0.65, 0.4));
	float bd = dot(d, ba);
	float band = exp(-bd * bd / 0.035);
	col += vec3(0.10, 0.12, 0.2) * band * smoothstep(0.3, 0.85, fbm(d * 4.0)) * vis * 0.9;
	col += stars(d, 160.0, 0.015 + 0.035 * band, 0.16) * 1.4 * vis;
	col += stars(d, 380.0, 0.02 + 0.05 * band, 0.22) * 0.6 * vis;
	col += stars(d, 65.0, 0.006, 0.1) * 2.8 * vis;
	// the broad aurora wash: green low, teal above, violet at the crown, strongest ahead
	vec3 gd = normalize(glow_dir);
	float toward = max(dot(normalize(vec3(d.x, 0.0001, d.z)), normalize(vec3(gd.x, 0.0001, gd.z))), 0.0);
	float wide = 0.25 + 0.75 * toward * sqrt(toward);
	float ang = atan(d.x, -d.z);
	float wav = sin(ang * 2.6 + fbm(d * 2.2) * 3.2) * 0.5 + 0.5;
	float q1 = (up - 0.2 - wav * 0.1) / 0.11;
	float q2 = (up - 0.42 - wav * 0.12) / 0.17;
	float q3 = (up - 0.68 - wav * 0.1) / 0.2;
	float low = exp(-q1 * q1);
	float midb = exp(-q2 * q2);
	float high = exp(-q3 * q3);
	float veil = smoothstep(0.22, 0.75, fbm(vec3(ang * 2.0, up * 3.2, 0.0)));
	col += (aurora_a * low + aurora_b * midb * 0.8 + aurora_c * high * 0.7) * veil * wide * wash;
	// the cold glow low on the horizon, where the snowfields reflect it
	col += horizon * 0.5 * exp(-max(up, 0.0) * 9.0) * (0.4 + 0.6 * toward);
	col = mix(col, ground, smoothstep(0.0, -0.08, up));
	COLOR = min(col, vec3(4.0));
}
