class_name OlympusSky
extends RefCounted
## Sky Citadel's sky: golden hour above the clouds. A deep cobalt zenith warms through clear blue to
## peach and molten gold at the horizon (brightest under the sun, rosier opposite); the sun is a big
## low disc with a wide glare, crepuscular shafts fanning out from it and high streaks of cirrus lit
## from below. Below the horizon an endless sea of cloud tops rolls away, gold where the sun rakes
## them and lavender in their hollows, thinning into haze at the edge of the world. Static (no TIME)
## so the radiance map is rendered once. Every term is bounded and NaN-safe: no pow() of a value that
## can be negative, no normalize() of a vector that can be zero, smoothstep edges in order, divisions
## guarded.

## The direction TOWARD the sun (world), matching Sun rotation (-22, 200, 0).
const SUN_DIR := Vector3(-0.317, 0.375, -0.871)

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.10, 0.22, 0.58);
uniform vec3 upper : source_color = vec3(0.34, 0.54, 0.84);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.76, 0.42);
uniform vec3 horizon_far : source_color = vec3(0.96, 0.66, 0.58);
uniform vec3 haze : source_color = vec3(1.0, 0.82, 0.58);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.88, 0.66);
uniform vec3 cloud_shade : source_color = vec3(0.60, 0.52, 0.72);
uniform vec3 fallback_sun = vec3(-0.317, 0.375, -0.871);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	// LIGHT0 can be unset (zero) when the radiance map is first baked: normalize(0) is NaN, and a
	// NaN sky blacks out every surface it lights, so fall back to the intended sun direction
	vec3 L = fallback_sun;
	if (LIGHT0_ENABLED) {
		float ll = length(LIGHT0_DIRECTION);
		if (ll > 0.001) {
			L = LIGHT0_DIRECTION / ll;
		}
	}
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001, 0.0);
	vec2 lh = L.xz + vec2(0.0001, 0.0);
	dh = dh / max(length(dh), 0.0001);
	lh = lh / max(length(lh), 0.0001);
	// 1 under the sun, 0 opposite (clamped: rounding can push the dot past -1, and pow of a negative is NaN)
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 hor = mix(horizon_far, horizon_sun, toward * toward);
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.3, up));
	col = mix(col, zenith, smoothstep(0.18, 0.9, up));
	float sd = clamp(dot(d, L), -1.0, 1.0);
	if (up >= 0.0) {
		// a haze of gold hugging the horizon, thickest under the sun
		float band = exp(-up * 9.0);
		col = mix(col, haze * (0.8 + 0.4 * toward), band * (0.45 + 0.4 * toward));
		// cirrus: long streaks lit from below by the low sun
		vec2 cp = d.xz / (up + 0.1);
		float streak = fbm(vec2(cp.x * 0.8 + cp.y * 0.3, cp.y * 3.0) * 1.3);
		float c = smoothstep(0.5, 0.78, streak) * smoothstep(0.03, 0.22, up) * (1.0 - smoothstep(0.55, 0.95, up));
		vec3 cc = mix(vec3(1.0, 0.92, 0.88), vec3(1.0, 0.66, 0.4), toward * toward);
		col = mix(col, cc, c * 0.55);
	}
	// crepuscular shafts fanning out of the sun
	vec3 ax = cross(L, vec3(0.0, 1.0, 0.0));
	float axl = length(ax);
	ax = axl > 0.001 ? ax / axl : vec3(1.0, 0.0, 0.0);
	vec3 ay = cross(ax, L);
	float sx = dot(d, ax);
	float sy = dot(d, ay);
	float ang = atan(sy, sx + 0.0002);
	float shaft = noise2(vec2(ang * 5.0, 3.0)) * 0.6 + noise2(vec2(ang * 13.0, 9.0)) * 0.4;
	float glow_r = max(sd, 0.0);
	col += vec3(1.0, 0.82, 0.5) * smoothstep(0.45, 0.9, shaft) * glow_r * glow_r * glow_r * 0.3;
	// the sun: a warm disc, a tight glare and a wide golden bloom
	col += vec3(1.0, 0.95, 0.82) * smoothstep(0.99955, 0.99975, sd) * 14.0;
	col += vec3(1.0, 0.84, 0.55) * glow_r * glow_r * glow_r * glow_r * glow_r * glow_r * glow_r * glow_r * 0.22;
	col += vec3(1.0, 0.72, 0.42) * glow_r * glow_r * glow_r * glow_r * 0.14;
	// below the horizon: the sea of cloud tops, gold where the sun rakes them, lavender in the hollows
	if (up < 0.0) {
		float depth = -up;
		vec2 sp = d.xz / (depth + 0.045) * 0.55;
		float n1 = fbm(sp * 0.9);
		float n2 = fbm(sp * 2.3 + vec2(7.0, 2.0));
		float dens = clamp(n1 * 0.7 + n2 * 0.5, 0.0, 1.0);
		float lit = smoothstep(0.35, 0.75, dens);
		// the side of each billow facing the sun is bright: shade by how the density rises toward it
		float rake = clamp(0.5 + (fbm(sp * 0.9 + lh * 0.12) - n1) * 9.0, 0.0, 1.0);
		vec3 tops = mix(cloud_shade, cloud_lit, clamp(lit * 0.55 + rake * 0.55, 0.0, 1.0));
		tops = mix(tops, tops * vec3(1.05, 0.95, 0.9), 1.0 - toward);
		// thin into haze toward the horizon and toward the edge of the world
		float far_fade = 1.0 - smoothstep(0.0, 0.16, depth);
		col = mix(tops, hor * 1.05, far_fade * 0.85);
		col += vec3(1.0, 0.72, 0.4) * glow_r * glow_r * glow_r * glow_r * 0.1;
	}
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
