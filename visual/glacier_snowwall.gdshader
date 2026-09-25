shader_type spatial;
render_mode diffuse_burley, specular_disabled;
// Frostbite Pass: the boiling face of an avalanche. Big spheres whose surface churns with
// animated noise (vertex displacement), shaded from bright powder to cold blue in the folds.

uniform vec3 snow : source_color = vec3(0.93, 0.96, 1.0);
uniform vec3 shade : source_color = vec3(0.5, 0.6, 0.82);
uniform float boil = 1.0;
uniform float seed = 0.0;

varying float n;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
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

void vertex() {
	vec3 p = VERTEX * 2.2 + vec3(seed, TIME * 1.1 * boil, TIME * 0.7 * boil);
	n = noise3(p) * 0.65 + noise3(p * 2.3 + vec3(7.0)) * 0.35;
	VERTEX += NORMAL * (n - 0.45) * 0.4 * boil;
}

void fragment() {
	ALBEDO = mix(shade, snow, clamp(0.35 + 0.75 * n, 0.0, 1.0));
	ROUGHNESS = 1.0;
	EMISSION = vec3(0.25, 0.38, 0.62) * 0.15;
}
