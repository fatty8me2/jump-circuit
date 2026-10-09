shader_type spatial;
render_mode fog_disabled, cull_disabled;
// The smoking volcano on Dino Valley's horizon: dark basalt streaked with ash, green forest on its
// lower flanks, glowing lava veins running down from the crater, a molten crater lip. It sits
// hundreds of metres away so the scene fog is off and a haze is blended in by distance instead
// (the volcano stays a strong shape, just softened). Bounded; no unguarded divides.

uniform vec3 rock_dark : source_color = vec3(0.17, 0.14, 0.14);
uniform vec3 rock_light : source_color = vec3(0.42, 0.34, 0.3);
uniform vec3 forest : source_color = vec3(0.14, 0.3, 0.13);
uniform vec3 ash : source_color = vec3(0.62, 0.6, 0.58);
uniform vec3 haze_col : source_color = vec3(0.78, 0.82, 0.72);
uniform vec3 lava : source_color = vec3(1.0, 0.38, 0.08);
uniform float haze_k = 0.0011;
uniform float height = 200.0;

varying vec3 lp;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float h = clamp(lp.y / max(height, 1.0), 0.0, 1.0);
	float ang = atan(lp.z, lp.x + 0.001);
	float streak = vnoise(vec2(ang * 9.0, lp.y * 0.05));
	float grain = vnoise(vec2(ang * 31.0, lp.y * 0.4));
	vec3 col = mix(rock_dark, rock_light, 0.25 + 0.55 * streak);
	col *= 0.85 + 0.3 * grain;
	col = mix(col, ash, smoothstep(0.7, 0.98, h) * 0.45 * streak);
	col = mix(forest, col, smoothstep(0.08, 0.32, h + 0.1 * (grain - 0.5)));
	// lava veins down the upper flank, pulsing slowly
	float vein = smoothstep(0.74, 0.86, vnoise(vec2(ang * 5.0 + 3.0, lp.y * 0.02 - 0.0))) * smoothstep(0.55, 0.95, h);
	float pulse = 0.7 + 0.3 * sin(TIME * 1.3 + ang * 4.0);
	float lip = smoothstep(0.93, 1.0, h);
	vec3 emit = lava * (vein * 1.6 * pulse + lip * 2.2);
	float dist = length(VERTEX);
	float f = clamp(1.0 - exp(-dist * haze_k), 0.0, 0.85);
	ALBEDO = mix(col, haze_col, f);
	EMISSION = emit * (1.0 - f);
	ROUGHNESS = 0.95;
}
