class_name HyperloopSky
extends RefCounted
## Hyperloop's sky: a clear, cold DAWN above a sea of cloud. A deep teal-blue zenith (the last few stars
## still showing) clears through glass-cyan to a nearly white horizon with a band of pale rose-gold under
## the sun; the sun is a small low disc with a soft halo and a few long light shafts. High above run
## ruler-straight CONTRAILS - parallel white lines, the sky's own mag-rails - lit rose on the sun side.
## Below the horizon an endless sea of low cloud rolls away, white on top with cool cyan hollows and a
## faint grid of far city light glowing through it, thinning into haze at the edge of the world.
## Static (no TIME) so the radiance map is rendered once. Every term is bounded and NaN-safe: no pow()
## of a value that can be negative, no normalize() of a vector that can be zero, smoothstep edges in
## order, divisions guarded.

## Sun elevation / heading of the sky disc (the Sun light uses Look's sun_rot, a touch higher).
const SUN_ROT := Vector3(-14, 205, 0)

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.04, 0.16, 0.36);
uniform vec3 upper : source_color = vec3(0.20, 0.52, 0.80);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.86, 0.80);
uniform vec3 horizon_far : source_color = vec3(0.86, 0.94, 1.0);
uniform vec3 haze : source_color = vec3(0.94, 0.97, 1.0);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.96);
uniform vec3 cloud_shade : source_color = vec3(0.50, 0.70, 0.88);
uniform vec3 sun_dir = vec3(-0.40, 0.24, -0.88);

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
	vec3 L = sun_dir;
	float ll = length(L);
	L = ll > 0.001 ? L / ll : vec3(0.0, 0.3, -1.0);
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001, 0.0);
	vec2 lh = L.xz + vec2(0.0001, 0.0);
	dh = dh / max(length(dh), 0.0001);
	lh = lh / max(length(lh), 0.0001);
	// 1 under the sun, 0 opposite (clamped: rounding can push the dot past -1)
	float toward = clamp(dot(dh, lh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 hor = mix(horizon_far, horizon_sun, toward * toward);
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.34, up));
	col = mix(col, zenith, smoothstep(0.2, 0.95, up));
	float sd = clamp(dot(d, L), -1.0, 1.0);
	if (up >= 0.0) {
		// a pale band of haze hugging the horizon, rosier under the sun
		float band = exp(-up * 8.0);
		col = mix(col, haze * (0.85 + 0.2 * toward), band * (0.40 + 0.35 * toward));
		// the last stars, only in the deepest blue
		vec2 sp = d.xz / (up + 0.3) * 38.0;
		float st = step(0.9965, hash12(floor(sp)));
		col += vec3(0.8, 0.9, 1.0) * st * smoothstep(0.55, 0.9, up) * 0.6;
		// contrails: long parallel straight lines (the sky's mag-rails), lit rose toward the sun
		vec2 cp = d.xz / (up + 0.12);
		float lane = abs(fract(cp.x * 0.11 + cp.y * 0.035) - 0.5);
		float line = 1.0 - smoothstep(0.0, 0.012, lane - 0.004);
		float breakup = smoothstep(0.35, 0.6, fbm(vec2(cp.y * 0.08, cp.x * 0.02) + vec2(2.0, 5.0)));
		float tr = line * breakup * smoothstep(0.08, 0.3, up) * (1.0 - smoothstep(0.6, 0.95, up));
		vec3 tc = mix(vec3(1.0, 1.0, 1.0), vec3(1.0, 0.78, 0.72), toward * toward);
		col = mix(col, tc, tr * 0.7);
	}
	// light shafts fanning out of the sun
	vec3 ax = cross(L, vec3(0.0, 1.0, 0.0));
	float axl = length(ax);
	ax = axl > 0.001 ? ax / axl : vec3(1.0, 0.0, 0.0);
	vec3 ay = cross(ax, L);
	float sx = dot(d, ax);
	float sy = dot(d, ay);
	float ang = atan(sy, sx + 0.0002);
	float shaft = noise2(vec2(ang * 4.0, 3.0)) * 0.6 + noise2(vec2(ang * 11.0, 9.0)) * 0.4;
	float glow_r = max(sd, 0.0);
	float g2 = glow_r * glow_r;
	float g4 = g2 * g2;
	float g8 = g4 * g4;
	col += vec3(1.0, 0.88, 0.80) * smoothstep(0.5, 0.9, shaft) * g4 * 0.18;
	// the sun: a small clean disc, a tight glare and a wide rose-gold bloom
	col += vec3(1.0, 0.96, 0.88) * smoothstep(0.99975, 0.99985, sd) * 12.0;
	col += vec3(1.0, 0.88, 0.74) * g8 * g8 * 0.30;
	col += vec3(1.0, 0.80, 0.70) * g8 * 0.16;
	col += vec3(1.0, 0.82, 0.74) * g4 * 0.10;
	// below the horizon: the sea of cloud, white on top with cool hollows and city light glowing through
	if (up < 0.0) {
		float depth = -up;
		vec2 sp2 = d.xz / (depth + 0.05) * 0.55;
		float n1 = fbm(sp2 * 0.9);
		float n2 = fbm(sp2 * 2.3 + vec2(7.0, 2.0));
		float dens = clamp(n1 * 0.7 + n2 * 0.5, 0.0, 1.0);
		float lit = smoothstep(0.35, 0.75, dens);
		float rake = clamp(0.5 + (fbm(sp2 * 0.9 + lh * 0.12) - n1) * 9.0, 0.0, 1.0);
		vec3 tops = mix(cloud_shade, cloud_lit, clamp(lit * 0.55 + rake * 0.55, 0.0, 1.0));
		tops = mix(tops, tops * vec3(1.02, 0.97, 0.96), 1.0 - toward);
		// a faint street grid of far city light showing through the thin patches
		vec2 gp = sp2 * 5.0;
		vec2 gl = abs(fract(gp) - 0.5);
		float grid = (1.0 - smoothstep(0.0, 0.05, 0.5 - max(gl.x, gl.y) * 1.0)) * (1.0 - lit) * smoothstep(0.18, 0.5, depth);
		tops += vec3(0.3, 0.8, 1.0) * grid * 0.10;
		float far_fade = 1.0 - smoothstep(0.0, 0.18, depth);
		col = mix(tops, hor * 1.04, far_fade * 0.85);
		col += vec3(1.0, 0.82, 0.74) * g4 * 0.08;
	}
	COLOR = clamp(col, vec3(0.0), vec3(3.0));
}
"""


static func sun_direction() -> Vector3:
	return Basis.from_euler(Vector3(deg_to_rad(SUN_ROT.x), deg_to_rad(SUN_ROT.y), deg_to_rad(SUN_ROT.z))) * Vector3(0, 0, 1)


static func make() -> Sky:
	var sh := Shader.new()
	sh.code = CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("sun_dir", sun_direction())
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky
