shader_type spatial;
// Frostbite Pass walkable surface: the platform shader's layout (bright top, glowing inset
// trim, darker sides) re-done as wind-packed snow over glacier ice. Tops: soft snow with
// drift ripples and a frost glitter that twinkles as the view moves; sides: blue ice with
// cloudy depth, glowing hairline veins and a band of rime under the lip. Same uniforms as
// visual/platform.gdshader so the level can swap it in and keep each piece's colours.

uniform vec3 top_color : source_color = vec3(0.92, 0.95, 1.0);
uniform vec3 side_color : source_color = vec3(0.45, 0.62, 0.8);
uniform vec3 trim_color : source_color = vec3(0.55, 0.9, 1.0);
uniform vec3 half_size = vec3(1.0, 0.5, 1.0);
uniform bool is_round = false;
uniform float trim_width = 0.14;
uniform float trim_glow = 0.0;
uniform vec3 vein_color : source_color = vec3(0.5, 0.95, 1.0);

varying vec3 lp;
varying vec3 ln;
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

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col;
	float glow = 0.0;
	vec3 extra = vec3(0.0);
	float n1 = noise3(wp * 1.3);
	if (ln.y > 0.6) {
		float edge;
		if (is_round) {
			edge = half_size.x - length(lp.xz);
		} else {
			vec2 d = half_size.xz - abs(lp.xz);
			edge = min(d.x, d.y);
		}
		// wind-packed snow: soft drift ripples, faint blue in the hollows
		float ripple = sin(wp.x * 1.9 + wp.z * 0.7 + noise3(vec3(wp.xz * 0.5, 0.0)) * 5.0) * 0.5 + 0.5;
		col = top_color * (0.9 + 0.07 * ripple + 0.06 * (n1 - 0.5));
		col = mix(col, top_color * vec3(0.8, 0.88, 1.0), (1.0 - ripple) * 0.2);
		float inner = smoothstep(trim_width, trim_width + 0.02, edge);
		float outer = smoothstep(trim_width * 0.35, trim_width * 0.35 + 0.02, edge);
		float trim = outer * (1.0 - inner);
		col = mix(col, trim_color, trim);
		glow = trim;
		// frost glitter: tiny cells that flash as the view direction changes
		vec3 cell = floor(wp * 9.0);
		float h = hash13(cell);
		float tw = hash13(cell + floor(VIEW * 6.0) * 13.0);
		extra = vec3(0.8, 0.95, 1.0) * step(0.985, h) * step(0.5, tw) * 2.5;
		ROUGHNESS = 0.8;
	} else if (ln.y < -0.6) {
		col = side_color * 0.5;
		ROUGHNESS = 0.4;
	} else {
		float h2 = clamp((lp.y + half_size.y) / (2.0 * half_size.y), 0.0, 1.0);
		float depth = half_size.y - lp.y;
		// glacier ice: cloudy blue depth, bright hairline veins, a rime band under the lip
		float cloud = noise3(wp * vec3(0.6, 1.4, 0.6)) * 0.6 + noise3(wp * 2.1) * 0.4;
		col = mix(side_color * 0.55, side_color * 1.15, smoothstep(0.0, 1.0, h2) * 0.6 + cloud * 0.4);
		float v = noise3(wp * vec3(1.1, 2.3, 1.1) + vec3(cloud * 1.5));
		float veins = 1.0 - smoothstep(0.0, 0.05, abs(v - 0.5));
		col = mix(col, vein_color, veins * 0.35);
		float rime = 1.0 - smoothstep(0.08, 0.22, depth + (n1 - 0.5) * 0.08);
		col = mix(col, top_color, rime * 0.85);
		float band = smoothstep(0.26, 0.28, depth) * (1.0 - smoothstep(0.36, 0.38, depth));
		col = mix(col, trim_color * 0.9, band * 0.7);
		glow = band * 0.5;
		extra = vein_color * veins * 0.35 + side_color * 0.08;
		ROUGHNESS = 0.2;
		SPECULAR = 0.7;
	}
	ALBEDO = col;
	EMISSION = trim_color * glow * trim_glow + extra;
}
