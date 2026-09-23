shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never, blend_add;
// Coral Depths: the sea surface seen from below - a sheet of rippling light far above.

uniform vec3 color : source_color = vec3(0.55, 0.95, 1.0);
uniform float intensity = 0.55;
uniform float fade_dist = 260.0;

varying vec3 wp;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float cells(vec2 p, float t) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(ip + g);
			o = 0.5 + 0.42 * sin(t + 6.2831 * o);
			float d = length(g + o - fp);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float a = cells(wp.xz * 0.06, TIME * 0.5);
	float b = cells(wp.xz * 0.11 + vec2(4.0, 1.0), TIME * 0.7);
	float lines = (1.0 - smoothstep(0.0, 0.2, a)) * 0.7 + (1.0 - smoothstep(0.0, 0.15, b)) * 0.5;
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_dist * 0.35, fade_dist, d);
	ALBEDO = color * (0.25 + lines) * intensity * fade;
}
