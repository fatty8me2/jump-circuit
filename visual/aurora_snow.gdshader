shader_type spatial;
render_mode cull_back;
// Aurora Run: moonless snowfields lit by the aurora. Vertex colour R says how rocky a face is (0 = powder
// snow, 1 = dark rock). The snow is a cold blue-white with soft drifts and a faint glitter; a slow wash of
// aurora light (green -> teal -> violet) rolls across it in world space as a gentle emission, and a little
// rim of the same light catches edges. No divides, bounded output.

uniform vec3 snow_a : source_color = vec3(0.78, 0.88, 0.98);
uniform vec3 snow_b : source_color = vec3(0.45, 0.60, 0.82);
uniform vec3 rock_color : source_color = vec3(0.10, 0.13, 0.20);
uniform vec3 glow_a : source_color = vec3(0.15, 1.0, 0.55);
uniform vec3 glow_b : source_color = vec3(0.65, 0.35, 1.0);
uniform float glow_amount = 0.5;
uniform float sparkle = 1.0;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float drift = noise2(wpos.xz * 0.06) * 0.6 + noise2(wpos.xz * 0.23) * 0.4;
	vec3 snow = mix(snow_b, snow_a, drift);
	float rock = clamp(COLOR.r, 0.0, 1.0);
	vec3 base = mix(snow, rock_color, rock);
	float wave = sin(wpos.z * 0.012 + TIME * 0.12 + sin(wpos.x * 0.02) * 1.5) * 0.5 + 0.5;
	vec3 wash = mix(glow_a, glow_b, wave);
	float lit = (1.0 - rock) * (0.55 + 0.45 * drift);
	float cell = hash12(floor(wpos.xz * 2.5));
	float tw = step(0.992, cell) * (0.5 + 0.5 * sin(TIME * 3.0 + cell * 60.0));
	ALBEDO = base;
	ROUGHNESS = mix(0.55, 0.9, rock);
	SPECULAR = 0.5;
	EMISSION = wash * glow_amount * 0.07 * lit + vec3(0.7, 0.9, 1.0) * tw * sparkle * lit * 0.8;
}
