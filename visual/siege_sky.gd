class_name SiegeSky
extends RefCounted
## Castle Siege's sky: a DUSK UNDER SIEGE. A bruised indigo dome falls through plum and rose into a
## horizon burning orange-gold; the sun is a fat blood-orange disc half sunk behind far hills and
## veiled in smoke. Great dark columns of smoke rise from burning towns and camps and lean away on the
## wind, lit orange on their under-edges; low on the horizon a scatter of tiny fires glows; the first
## stars show overhead. Static (no TIME), so the radiance map is rendered once. Every term is bounded
## and NaN-safe: no pow() of negatives, no normalize() of a zero vector, smoothstep edges in order.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.045, 0.04, 0.12);
uniform vec3 upper : source_color = vec3(0.2, 0.1, 0.24);
uniform vec3 rose : source_color = vec3(0.62, 0.22, 0.26);
uniform vec3 horizon : source_color = vec3(1.0, 0.5, 0.16);
uniform vec3 below : source_color = vec3(0.16, 0.085, 0.07);
uniform vec3 sun_dir = vec3(-0.35, 0.05, -0.93);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(4.1, 1.7);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	float az = atan(dh.y, dh.x);
	// base gradient: indigo overhead, plum, rose, then the burning horizon band
	vec3 col = mix(upper, zenith, smoothstep(0.25, 0.9, up));
	col = mix(col, rose, 1.0 - smoothstep(0.0, 0.42, up));
	col = mix(col, horizon, 1.0 - smoothstep(0.0, 0.16, up));
	// the sun: a big blood-orange disc low in the sky with a wide glow, half behind the hills
	vec3 S = sun_dir / max(length(sun_dir), 0.0001);
	float cs = clamp(dot(d, S), -1.0, 1.0);
	float ang = acos(cs);
	float disc = 1.0 - smoothstep(0.075, 0.085, ang);
	col += vec3(1.0, 0.42, 0.1) * (1.0 - smoothstep(0.0, 0.7, ang)) * 0.55;
	col = mix(col, vec3(1.0, 0.62, 0.22) * 1.6, disc * 0.95);
	// smoke columns: tall stretched noise, thresholded into plumes that lean on the wind
	float lean = up * 1.4;
	float col_n = fbm(vec2((az + lean) * 3.2, up * 2.2) + vec2(2.0, 0.0));
	float plume = smoothstep(0.52, 0.72, col_n) * smoothstep(-0.02, 0.1, up) * (1.0 - smoothstep(0.45, 0.8, up));
	vec3 smoke = mix(vec3(0.08, 0.05, 0.07), vec3(0.24, 0.12, 0.1), smoothstep(0.0, 0.3, up));
	// lit from below by the fires: orange on the lower edge of each plume
	float rimlight = smoothstep(0.0, 0.4, 0.7 - col_n) * (1.0 - smoothstep(0.0, 0.3, up));
	smoke += vec3(0.9, 0.35, 0.08) * rimlight * 0.35;
	col = mix(col, smoke, plume * 0.82);
	// the sun sinks behind the far hills: a dark ridge line with soft bumps
	float ridge = 0.012 + 0.03 * fbm(vec2(az * 2.6, 0.5)) + 0.012 * noise2(vec2(az * 14.0, 2.0));
	float hill = 1.0 - smoothstep(ridge - 0.004, ridge + 0.004, up);
	col = mix(col, vec3(0.07, 0.04, 0.05), hill * step(-0.02, up));
	// tiny fires on the hills: a scatter of warm points just above the ridge
	vec2 fp = vec2(az * 40.0, up * 90.0);
	vec2 fi = floor(fp);
	float fr = hash12(fi);
	vec2 ff = fract(fp) - 0.5;
	float fire = step(0.93, fr) * (1.0 - smoothstep(0.1, 0.22, length(ff))) * step(0.0, up) * (1.0 - smoothstep(0.02, 0.07, up));
	col += vec3(1.0, 0.5, 0.12) * fire * 1.4;
	// the first stars, high up and only where the smoke is thin
	vec2 sp = vec2(az * 55.0, up * 55.0);
	vec2 si = floor(sp);
	float sr = hash12(si + vec2(9.1, 3.3));
	vec2 sf = fract(sp) - 0.5;
	float star = step(0.97, sr) * (1.0 - smoothstep(0.04, 0.14, length(sf))) * smoothstep(0.3, 0.7, up) * (1.0 - plume);
	col += vec3(0.9, 0.85, 1.0) * star * 0.8;
	// below the horizon: a warm dark haze
	col = mix(col, below, 1.0 - smoothstep(-0.2, 0.0, up));
	COLOR = clamp(col, vec3(0.0), vec3(3.0));
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
