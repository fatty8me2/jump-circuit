shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Frostbite Pass: big translucent glacier ice (the frozen falls, fortress walls, seracs,
// crystal spires). Cloudy blue depth, a bright fresnel rim, glowing hairline veins inside;
// `streaks` > 0 stretches the pattern vertically into the flow lines of frozen water.
// World-space noise, so neighbouring blocks read as one mass of ice.

uniform vec3 deep_color : source_color = vec3(0.14, 0.38, 0.78);
uniform vec3 shallow_color : source_color = vec3(0.62, 0.86, 1.0);
uniform vec3 vein_color : source_color = vec3(0.55, 1.0, 1.0);
uniform float glow = 0.7;
uniform float streaks = 0.0;
uniform float alpha = 0.8;

varying vec3 wp;

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

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise3(p);
		p = p * 2.07 + vec3(3.1, 1.7, 5.3);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	float stretch = mix(1.0, 0.12, streaks);
	vec3 q = wp * vec3(0.35, 0.35 * stretch, 0.35);
	float cloud = fbm(q);
	float v = noise3(wp * vec3(0.9, 0.9 * stretch, 0.9) + vec3(cloud * 2.0));
	float veins = 1.0 - smoothstep(0.0, 0.05, abs(v - 0.5));
	float flow = streaks * smoothstep(0.55, 0.9, noise3(vec3((wp.x + wp.z) * 2.3, wp.y * 0.08, 0.5)));
	vec3 col = mix(deep_color, shallow_color, clamp(cloud * 0.9 + fres * 0.7, 0.0, 1.0));
	col = mix(col, vec3(0.95, 0.98, 1.0), flow * 0.5);
	ALBEDO = col;
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 0.7;
	RIM = 0.6;
	RIM_TINT = 0.3;
	EMISSION = (deep_color * 0.35 + vein_color * veins * 0.8 + shallow_color * flow * 0.4) * glow + vec3(0.6, 0.9, 1.0) * fres * 0.25 * glow;
	ALPHA = clamp(alpha * (0.72 + 0.28 * fres + 0.1 * cloud), 0.0, 1.0);
}
