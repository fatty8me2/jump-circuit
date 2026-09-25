shader_type spatial;
// Cinder Peak molten lava surface (pools, the rising chamber, rivers seen from above).
// World-space XZ, so any number of planes tile seamlessly: dark rafts of cooling crust
// drift along `flow` over a white-hot, churning melt; the seams between rafts glow
// hottest, hot spots swell and fade, and the whole surface breathes. `crust` 0 = all
// molten, 1 = mostly skinned over. `heat` scales the glow (surges push it up).

render_mode cull_disabled;

uniform vec2 flow = vec2(0.0, 0.35);
uniform float crust : hint_range(0.0, 1.0) = 0.55;
uniform float heat = 1.0;
uniform float scale = 0.32;
uniform vec3 hot_color : source_color = vec3(1.0, 0.62, 0.16);
uniform vec3 white_hot : source_color = vec3(1.0, 0.92, 0.55);
uniform vec3 crust_color : source_color = vec3(0.09, 0.05, 0.045);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

// x: distance to nearest cell point, y: f2 - f1 (seams), z: cell id hash
vec3 cells(vec2 p, float t) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 h = hash2(ip + g);
			vec2 o = 0.5 + 0.38 * sin(t * 0.35 + 6.2831 * h);
			float d = length(g + o - fp);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = h.x;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f1, f2 - f1, id);
}

void fragment() {
	float t = TIME;
	vec2 p = wp.xz * scale - flow * t * scale;
	vec2 w = vec2(fbm(p * 0.8 + t * 0.05), fbm(p * 0.8 + vec2(5.2, 1.3) - t * 0.04)) - 0.5;
	vec3 c = cells(p + w * 1.2, t);
	float churn = fbm(p * 2.6 + w * 2.0 + t * 0.18);
	// raft coverage: the crust skins over the middle of each cell, the seams stay open
	float raft = smoothstep(0.02, 0.22 + 0.25 * (1.0 - crust), c.y) * step(0.35 - 0.3 * crust, c.z + 0.35 * crust);
	raft *= smoothstep(0.25, 0.6, churn + crust * 0.45);
	float seam = 1.0 - smoothstep(0.0, 0.09, c.y);
	float spot = smoothstep(0.62, 0.9, fbm(p * 1.3 - t * 0.12));
	float breathe = 0.85 + 0.15 * sin(t * 1.7 + c.z * 12.0);
	vec3 melt = mix(hot_color, white_hot, clamp(spot * 0.8 + seam * 0.6, 0.0, 1.0));
	vec3 col = mix(melt, crust_color, raft);
	// cooling crust keeps a dull red glow where it is thin
	vec3 emit = melt * (1.0 - raft) * (1.6 + 1.4 * seam) * breathe * heat;
	emit += hot_color * raft * 0.12 * (1.0 - smoothstep(0.1, 0.5, c.y)) * heat;
	ALBEDO = col * 0.4;
	EMISSION = emit;
	ROUGHNESS = mix(0.35, 0.95, raft);
	SPECULAR = 0.3;
}
