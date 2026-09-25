shader_type spatial;
render_mode cull_disabled;
// Xeno Wilds: an acid lake / pool surface - a glowing lime-yellow liquid with drifting cells of
// scum, slowly crawling bright veins and a hot shimmer, darkening toward its edges. Flat plane
// (PlaneMesh / QuadMesh facing up); world-space so neighbouring pools line up.

uniform vec3 deep_color : source_color = vec3(0.18, 0.32, 0.02);
uniform vec3 hot_color : source_color = vec3(0.85, 1.0, 0.2);
uniform vec3 scum_color : source_color = vec3(0.35, 0.55, 0.08);
uniform float glow = 1.6;
uniform float scale = 0.35;

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
			o = 0.5 + 0.4 * sin(t + 6.2831 * o);
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
	vec2 p = wp.xz * scale;
	float t = TIME * 0.35;
	float a = cells(p + vec2(t * 0.2, -t * 0.13), t);
	float b = cells(p * 2.3 + vec2(-t * 0.3, t * 0.25), t * 1.4 + 3.0);
	float vein = 1.0 - smoothstep(0.0, 0.08, a);
	float fine = 1.0 - smoothstep(0.0, 0.06, b);
	float scum = smoothstep(0.25, 0.55, a);
	vec3 col = mix(hot_color, scum_color, scum * 0.75);
	col = mix(col, deep_color, smoothstep(0.45, 0.9, b) * 0.5);
	float shimmer = 0.75 + 0.25 * sin(TIME * 2.0 + wp.x * 0.7 + wp.z * 0.5);
	ALBEDO = col * 0.5;
	EMISSION = hot_color * (vein * 1.2 + fine * 0.5 + (1.0 - scum) * 0.35) * glow * shimmer;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
