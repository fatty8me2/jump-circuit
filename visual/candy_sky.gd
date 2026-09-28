class_name CandySky
extends RefCounted
## Sugar Rush's sky: a sweet dreamy afternoon. A soft blue zenith melting through lilac into a
## candyfloss-pink and peach horizon, banks of cotton-candy cloud (pink, lilac and cream, lit gold
## toward the sun) heaped along the horizon, wisps higher up, a huge rainbow arching over the far
## side of the world, a soft white sun with a warm glow, and a few pale daytime sparkles. Static
## (no TIME) so the radiance map is only rendered once. Every term is bounded and NaN-safe: pow()
## only of clamped values, no normalize() of a zero vector, smoothstep edges in order.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.42, 0.66, 1.0);
uniform vec3 upper : source_color = vec3(0.72, 0.74, 1.0);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.86, 0.74);
uniform vec3 horizon_far : source_color = vec3(1.0, 0.74, 0.88);
uniform vec3 below : source_color = vec3(0.96, 0.78, 0.9);
uniform vec3 rainbow_dir = vec3(0.15, -0.28, -0.95);
uniform float rainbow_radius = 0.72;
uniform float rainbow_width = 0.085;

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
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

vec3 hue(float h) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k;
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	vec3 L = (LIGHT0_ENABLED && length(LIGHT0_DIRECTION) > 0.001) ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.4, 0.5, 0.6));
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	vec2 lh = L.xz + vec2(0.0001);
	lh = lh / max(length(lh), 0.0001);
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 hor = mix(horizon_far, horizon_sun, pow(toward, 1.8));
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.3, up));
	col = mix(col, zenith, smoothstep(0.25, 0.9, up));
	// the rainbow: a band at a fixed angle round its centre direction, fading into the horizon
	vec3 R = rainbow_dir / max(length(rainbow_dir), 0.0001);
	float ang = acos(clamp(dot(d, R), -1.0, 1.0));
	float rb = (ang - rainbow_radius) / rainbow_width;
	if (rb > 0.0 && rb < 1.0) {
		float fade = smoothstep(0.0, 0.18, rb) * (1.0 - smoothstep(0.82, 1.0, rb));
		float vis = smoothstep(-0.02, 0.1, up) * (1.0 - smoothstep(0.55, 0.9, up));
		col = mix(col, hue(0.8 - rb * 0.8) * 1.05 + 0.1, fade * vis * 0.55);
	}
	// a soft secondary glow just outside it
	float rb2 = (ang - rainbow_radius - rainbow_width * 1.9) / (rainbow_width * 0.8);
	if (rb2 > 0.0 && rb2 < 1.0) {
		float fade2 = smoothstep(0.0, 0.3, rb2) * (1.0 - smoothstep(0.7, 1.0, rb2));
		col = mix(col, hue(rb2 * 0.8) + 0.2, fade2 * 0.14 * smoothstep(0.0, 0.1, up));
	}
	// cotton-candy cloud banks heaped along the horizon, wisps higher up
	if (up > -0.05) {
		float az = atan(dh.y, dh.x);
		float bank = fbm(vec2(az * 3.2, up * 9.0)) + 0.35 * fbm(vec2(az * 9.0, up * 20.0));
		float h = 0.08 + 0.16 * fbm(vec2(az * 1.7, 4.0));
		float c = smoothstep(0.62, 0.9, bank + (h - up) * 2.2) * (1.0 - smoothstep(h + 0.02, h + 0.2, up));
		c *= smoothstep(-0.05, 0.02, up);
		float tint = fbm(vec2(az * 2.1, 7.0));
		vec3 cc = mix(vec3(1.0, 0.76, 0.9), vec3(0.86, 0.8, 1.0), smoothstep(0.35, 0.65, tint));
		cc = mix(cc, vec3(1.0, 0.97, 0.92), smoothstep(0.0, 0.2, h - up) * 0.4);
		cc = mix(cc, vec3(1.0, 0.9, 0.7), pow(toward, 3.0) * 0.45);
		col = mix(col, cc, c * 0.92);
		// wisps
		if (up > 0.0) {
			vec2 cp = d.xz / (up + 0.15);
			float w = fbm(cp * 0.9 + vec2(2.0, 5.0));
			float wc = smoothstep(0.55, 0.8, w) * smoothstep(0.05, 0.25, up) * (1.0 - smoothstep(0.6, 0.95, up));
			col = mix(col, vec3(1.0, 0.93, 0.98), wc * 0.5);
		}
	}
	// the sun: a soft white disc, a warm glow and a wide sweet haze
	float sd = clamp(dot(d, L), -1.0, 1.0);
	float sp = max(sd, 0.0);
	col += vec3(1.0, 0.98, 0.9) * smoothstep(0.9994, 0.9997, sd) * 8.0;
	col += vec3(1.0, 0.9, 0.8) * pow(sp, 500.0) * 1.6;
	col += vec3(1.0, 0.82, 0.8) * pow(sp, 18.0) * 0.22;
	// pale daytime sparkles high up
	if (up > 0.25) {
		vec2 sc = d.xz / (up + 0.001) * 60.0;
		vec2 cell = floor(sc);
		float s = hash12(cell);
		vec2 f = fract(sc) - 0.5;
		float star = (1.0 - smoothstep(0.0, 0.12, length(f))) * step(0.985, s);
		col += vec3(1.0, 0.95, 1.0) * star * 0.35 * smoothstep(0.25, 0.6, up);
	}
	// below the horizon: a soft pink haze over the chocolate sea
	col = mix(col, below, 1.0 - smoothstep(-0.12, 0.0, up));
	COLOR = max(col, vec3(0.0));
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
