class_name OrbitalSky
extends RefCounted
## Orbital Drift's sky: a procedural sky shader with a real star dome (three star
## layers + the galactic band), the sun's hard white disc, and a huge ocean planet
## filling the lower sky - continents, cloud bands, a lit crescent with a sun glint,
## city lights on the night side and a blue atmosphere limb. Static (no TIME), so
## the radiance map is only rendered once.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 planet_dir = vec3(0.25, -0.55, -0.8);
uniform float planet_size = 0.74;
uniform vec3 ocean : source_color = vec3(0.03, 0.12, 0.32);
uniform vec3 shallows : source_color = vec3(0.06, 0.32, 0.46);
uniform vec3 land : source_color = vec3(0.34, 0.33, 0.20);
uniform vec3 desert : source_color = vec3(0.62, 0.48, 0.30);
uniform vec3 atmo : source_color = vec3(0.35, 0.62, 1.0);
uniform vec3 city : source_color = vec3(1.0, 0.68, 0.32);
uniform vec3 band_axis = vec3(0.35, 0.8, 0.45);

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
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
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
	vec3 tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.7), hash13(cell + 7.0));
	return tint * k * (0.4 + 1.6 * fract(h * 37.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 L = normalize(LIGHT0_DIRECTION);
	vec3 col = vec3(0.0);

	// ---- deep sky: galactic band + stars ----
	vec3 ba = normalize(band_axis);
	float bd = dot(d, ba);
	float band = exp(-bd * bd / 0.035);
	float neb = fbm(d * 3.5 + vec3(2.0));
	float neb2 = fbm(d * 9.0);
	col += vec3(0.20, 0.16, 0.34) * band * smoothstep(0.35, 0.8, neb) * 0.55;
	col += vec3(0.10, 0.18, 0.30) * band * smoothstep(0.45, 0.9, neb2) * 0.45;
	col += vec3(0.02, 0.015, 0.04) * band;
	col += stars(d, 170.0, 0.012 + 0.03 * band, 0.16) * 1.4;
	col += stars(d, 420.0, 0.02 + 0.06 * band, 0.22) * 0.6;
	col += stars(d, 70.0, 0.006, 0.1) * 3.0;

	// ---- the sun: hard white disc and a thin glare ----
	float sd = dot(d, L);
	col += vec3(1.0, 0.98, 0.94) * smoothstep(0.99955, 0.99975, sd) * 40.0;
	col += vec3(1.0, 0.95, 0.85) * pow(max(sd, 0.0), 900.0) * 6.0;
	col += vec3(0.9, 0.9, 1.0) * pow(max(sd, 0.0), 40.0) * 0.12;

	// ---- the planet ----
	vec3 C = normalize(planet_dir);
	float R = sin(planet_size);
	float b = dot(d, C);
	float c = dot(C, C) - R * R;
	float disc = b * b - c;
	if (disc > 0.0 && b > 0.0) {
		float t = b - sqrt(disc);
		vec3 P = d * t;
		vec3 n = normalize(P - C);
		float ndl = dot(n, L);
		float day = smoothstep(-0.12, 0.22, ndl);
		float diff = max(ndl, 0.0);
		vec3 q = n * 2.6;
		float cont = fbm(q + vec3(4.0, 1.0, 7.0));
		float landm = smoothstep(0.52, 0.56, cont);
		float shelf = smoothstep(0.46, 0.52, cont) * (1.0 - landm);
		float dry = smoothstep(0.5, 0.7, fbm(q * 2.0 + vec3(9.0)));
		vec3 ground = mix(ocean, shallows, shelf);
		ground = mix(ground, mix(land, desert, dry), landm);
		// polar ice
		float pole = smoothstep(0.78, 0.88, abs(dot(n, normalize(vec3(0.1, 1.0, 0.25)))));
		ground = mix(ground, vec3(0.85, 0.9, 0.95), pole);
		// cloud bands, sheared along latitude
		vec3 cq = n * 4.0;
		cq.x += sin(n.y * 9.0) * 0.6;
		float cl = smoothstep(0.5, 0.78, fbm(cq + vec3(1.0, 5.0, 2.0)));
		vec3 surf = ground * (diff * 1.25 + 0.015);
		surf = mix(surf, vec3(1.0) * (diff * 1.35 + 0.02), cl * 0.85);
		// sun glint on open water
		vec3 h = normalize(L - d);
		float spec = pow(max(dot(n, h), 0.0), 60.0) * (1.0 - landm) * (1.0 - cl) * day;
		surf += vec3(1.0, 0.95, 0.85) * spec * 1.6;
		// city lights on the night side
		float lights = smoothstep(0.78, 0.92, noise3(n * 520.0)) * smoothstep(0.55, 0.75, noise3(n * 14.0 + 3.0));
		surf += city * lights * landm * (1.0 - day) * (1.0 - cl * 0.8) * 0.45;
		// atmosphere: blue limb, strongest on the lit side
		float rim = pow(1.0 - max(dot(n, -d), 0.0), 3.0);
		surf += atmo * rim * (0.25 + 1.5 * smoothstep(-0.35, 0.5, ndl));
		surf += atmo * 0.05 * day;
		col = surf;
	} else {
		// halo just outside the limb
		float tc = max(b, 0.0);
		vec3 closest = d * tc;
		float h = length(closest - C) - R;
		vec3 nn = normalize(closest - C);
		float lit = smoothstep(-0.45, 0.45, dot(nn, L));
		float glow = exp(-max(h, 0.0) * 55.0) * 1.1 + exp(-max(h, 0.0) * 12.0) * 0.25;
		col = mix(col, col * 0.2, exp(-max(h, 0.0) * 55.0) * lit);
		col += atmo * glow * (0.12 + 1.3 * lit) * step(0.0, b);
		// a thin warm sunrise arc where the limb meets the terminator
		float term = exp(-pow(dot(nn, L) / 0.12, 2.0));
		col += vec3(1.0, 0.55, 0.25) * exp(-max(h, 0.0) * 90.0) * term * 0.9 * step(0.0, b);
	}
	COLOR = col;
}
"""


static func make() -> Sky:
	var sh := Shader.new()
	sh.code = CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky
