class_name NeonSky
extends RefCounted
## Neon City's sky: a wet, overcast city night. No stars - a low, heavy rain-cloud deck hangs over
## downtown, lit from below by the city: hot magenta in one quarter, sodium amber in another, a teal
## glow off the harbour side, all of it soaking up into the cloud base as light pollution. Toward the
## horizon the haze thickens into a bright pink-orange band; overhead the cloud is a dark plum with
## brighter folds where the glow catches it. A faint blurred moon tries to break through. Static (no
## TIME) so the radiance map is only rendered once. Every term is bounded and NaN-safe: pow() only of
## clamped values, no normalize() of a zero vector, smoothstep edges in order.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.035, 0.018, 0.05);
uniform vec3 deck : source_color = vec3(0.16, 0.05, 0.14);
uniform vec3 glow_magenta : source_color = vec3(0.95, 0.16, 0.55);
uniform vec3 glow_amber : source_color = vec3(1.0, 0.5, 0.14);
uniform vec3 glow_teal : source_color = vec3(0.1, 0.6, 0.62);
uniform vec3 below : source_color = vec3(0.12, 0.04, 0.08);
uniform vec3 moon_dir = vec3(-0.35, 0.42, -0.84);

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
		p = p * 2.03 + vec2(1.7, 9.2);
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
	dh = dh / max(length(dh), 0.0001);
	float az = atan(dh.y, dh.x);
	// the city's glow by quarter: magenta, amber, teal, blended round the horizon
	float wm = clamp(0.5 + 0.5 * cos(az - 0.6), 0.0, 1.0);
	float wa = clamp(0.5 + 0.5 * cos(az - 2.7), 0.0, 1.0);
	float wt = clamp(0.5 + 0.5 * cos(az + 1.9), 0.0, 1.0);
	wm = wm * wm;
	wa = wa * wa;
	wt = wt * wt * 0.7;
	vec3 city = (glow_magenta * wm + glow_amber * wa + glow_teal * wt) / max(wm + wa + wt, 0.001);
	// base gradient: bright haze band at the horizon into the dark plum deck
	float hz = 1.0 - smoothstep(0.0, 0.32, up);
	vec3 col = mix(zenith, deck, 1.0 - smoothstep(0.15, 0.85, up));
	col = mix(col, city * 0.55, hz * hz);
	col += city * 0.35 * (1.0 - smoothstep(-0.02, 0.08, up)) * smoothstep(-0.1, 0.0, up);
	// the cloud deck: big rolling folds, their undersides catching the glow
	if (up > -0.02) {
		vec2 cp = d.xz / (up + 0.12);
		float c = fbm(cp * 0.55 + vec2(3.0, 1.0));
		float c2 = fbm(cp * 1.6 + vec2(c * 2.0, 7.0));
		float folds = smoothstep(0.35, 0.8, c * 0.7 + c2 * 0.45);
		float lit = (1.0 - smoothstep(0.05, 0.6, up));
		col = mix(col, mix(deck * 0.7, city * 0.5, lit * 0.8), folds * 0.75);
		// gaps in the cloud are darker
		col *= 0.75 + 0.25 * folds;
		// streaks of rain hanging from the deck in the distance
		float rain = noise2(vec2(az * 80.0, up * 4.0)) * (1.0 - smoothstep(0.0, 0.25, up));
		col += city * 0.08 * rain;
	}
	// a faint moon smeared through the cloud
	vec3 M = moon_dir / max(length(moon_dir), 0.0001);
	float md = clamp(dot(d, M), -1.0, 1.0);
	float mp = max(md, 0.0);
	col += vec3(0.75, 0.7, 0.85) * smoothstep(0.9990, 0.9995, md) * 0.35;
	col += vec3(0.6, 0.45, 0.7) * pow(mp, 60.0) * 0.18;
	// below the horizon: the street haze far down
	col = mix(col, below + city * 0.12, 1.0 - smoothstep(-0.15, 0.0, up));
	COLOR = clamp(col, vec3(0.0), vec3(4.0));
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
