shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;
// Lotus Drift's pond water: dark teal glass that mirrors the dusk sky at a low angle (peach at the
// horizon, indigo overhead), slow crossing ripples that bend the normal, glints of the low sun,
// and a faint ring-ripple field. Opaque (the lilies sit on it). Moves with TIME only in the
// surface detail, so the radiance map the sky renders is unaffected.
// NaN-safe: normalize() only of vectors with a positive floor length, pow() of clamped bases.

uniform vec3 deep_color : source_color = vec3(0.025, 0.09, 0.13);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.26, 0.3);
uniform vec3 sky_low : source_color = vec3(1.0, 0.62, 0.45);
uniform vec3 sky_high : source_color = vec3(0.2, 0.16, 0.36);
uniform vec3 glint_color : source_color = vec3(1.0, 0.8, 0.6);
uniform vec3 sun_dir = vec3(0.45, 0.12, -0.7);
uniform float flow_speed = 0.05;

varying vec3 wp;

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

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float t = TIME;
	// two crossing ripple fields, their gradient is the bump
	float a = noise2(p * 0.9 + vec2(t * 0.11, t * 0.07));
	float b = noise2(p * 1.7 + vec2(-t * 0.09, t * 0.13) + vec2(7.3, 1.9));
	float c = noise2(p * 3.4 + vec2(t * 0.17, -t * 0.12) + vec2(2.1, 5.5));
	float e = 0.35;
	float ax = noise2((p + vec2(e, 0.0)) * 0.9 + vec2(t * 0.11, t * 0.07)) - a;
	float az = noise2((p + vec2(0.0, e)) * 0.9 + vec2(t * 0.11, t * 0.07)) - a;
	float bx = noise2((p + vec2(e, 0.0)) * 1.7 + vec2(-t * 0.09, t * 0.13) + vec2(7.3, 1.9)) - b;
	float bz = noise2((p + vec2(0.0, e)) * 1.7 + vec2(-t * 0.09, t * 0.13) + vec2(7.3, 1.9)) - b;
	vec3 n_world = vec3(-(ax * 0.5 + bx * 0.35) * 0.9, 1.0, -(az * 0.5 + bz * 0.35) * 0.9);
	n_world = n_world / max(length(n_world), 0.0001);
	NORMAL = normalize(mat3(VIEW_MATRIX) * n_world + vec3(0.0, 0.0001, 0.0));
	vec3 vdir = normalize(VIEW + vec3(0.0, 0.0, 0.0001));
	float fres = pow(clamp(1.0 - clamp(dot(NORMAL, vdir), 0.0, 1.0), 0.0, 1.0), 4.0);
	// the mirrored sky: reflect the view ray off the bumped surface in world space
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(-vdir, 0.0)).xyz + vec3(0.0, 0.0, 0.0001));
	vec3 refl = reflect(view_w, n_world);
	float up = clamp(refl.y, 0.0, 1.0);
	vec3 sky = mix(sky_low, sky_high, smoothstep(0.0, 0.6, up));
	sky += sky_low * 0.4 * (1.0 - smoothstep(0.0, 0.12, up));
	// the low sun's glitter: a lobe of the reflection near the sun, broken up by the fine ripples
	vec3 sd = sun_dir / max(length(sun_dir), 0.0001);
	float sun_lobe = pow(clamp(dot(refl, sd), 0.0, 1.0), 40.0);
	float glitter = smoothstep(0.55, 0.85, c) * (0.4 + 0.6 * sun_lobe) * (0.35 + 0.65 * sun_lobe);
	vec3 base = mix(deep_color, shallow_color, 0.3 + 0.5 * a);
	ALBEDO = base;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	float mirror = clamp(0.18 + 0.82 * fres, 0.0, 1.0);
	EMISSION = sky * mirror * 0.75 + glint_color * glitter * 0.9;
}
