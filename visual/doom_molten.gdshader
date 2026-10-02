shader_type spatial;
// Doom Fortress molten metal: white-hot where it flows fastest, cooling to orange and a dark
// floating crust at the edges, the crust drifting along `flow` (world xz, m/s). Used for the forge
// channels far below, the crucible pours and the reactor's coolant-starved glow. Emission is
// clamped (no blown-out sky) and every term is NaN-safe.

uniform vec3 hot_color : source_color = vec3(1.0, 0.62, 0.22);
uniform vec3 warm_color : source_color = vec3(0.95, 0.24, 0.04);
uniform vec3 crust_color : source_color = vec3(0.07, 0.03, 0.02);
uniform vec2 flow = vec2(0.0, 0.0);
uniform float heat : hint_range(0.0, 3.0) = 1.6;
uniform float crust : hint_range(0.0, 1.0) = 0.45;
uniform float scale = 0.5;

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = mod(TIME, 1000.0);
	vec2 p = (wp.xz + wp.y * 0.3 - flow * t) * scale;
	float n = fbm(p + vec2(t * 0.05, -t * 0.03));
	float n2 = fbm(p * 2.3 - vec2(t * 0.11, t * 0.07));
	float c = smoothstep(1.0 - crust, 1.0 - crust * 0.4, n * 0.7 + n2 * 0.5);
	float hot = clamp(1.0 - c, 0.0, 1.0);
	vec3 glow_col = mix(warm_color, hot_color, smoothstep(0.35, 0.9, n2));
	ALBEDO = mix(glow_col * 0.25, crust_color, c);
	ROUGHNESS = mix(0.35, 0.95, c);
	METALLIC = 0.0;
	EMISSION = clamp(glow_col * heat * hot * (0.75 + 0.5 * n), vec3(0.0), vec3(4.0));
}
