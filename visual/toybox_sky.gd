class_name ToyboxSky
extends RefCounted
## Toybox Tumble's sky: the high ceiling of a bedroom in the afternoon. Warm cream plaster overhead
## fading to honey-gold toward the walls, a soft pool of window light blooming low on the sun side
## with a faint cross of mullions in it, and a dusting of little cream clouds painted on the plaster.
## Static (no TIME). Every term is bounded and NaN-safe: no pow() of negatives, no normalize() of a
## zero vector, smoothstep edges in order, divisions guarded.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.98, 0.93, 0.84);
uniform vec3 mid : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 low : source_color = vec3(0.98, 0.7, 0.45);
uniform vec3 below : source_color = vec3(0.62, 0.46, 0.34);
uniform vec3 window_col : source_color = vec3(1.0, 0.96, 0.82);
uniform vec3 sun_dir = vec3(0.55, 0.38, 0.75);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	float up = d.y;
	vec3 col = mix(mid, zenith, smoothstep(0.1, 0.8, up));
	col = mix(low, col, smoothstep(-0.05, 0.3, up));
	// painted clouds on the plaster overhead
	if (up > 0.15) {
		vec2 sp = d.xz / max(up + 0.2, 0.05) * 2.2;
		float c = noise2(sp * 1.3) * 0.65 + noise2(sp * 3.1) * 0.35;
		col = mix(col, vec3(1.0, 0.99, 0.95), smoothstep(0.58, 0.8, c) * 0.55 * smoothstep(0.15, 0.4, up));
	}
	// the window light: a broad bloom on the sun side, with a pale cross of mullions
	vec3 S = sun_dir / max(length(sun_dir), 0.0001);
	float sd = clamp(dot(d, S), -1.0, 1.0);
	float bloom = smoothstep(0.55, 0.98, sd);
	col = mix(col, window_col, bloom * 0.7);
	float core = smoothstep(0.93, 0.995, sd);
	col += vec3(0.5, 0.45, 0.3) * core;
	vec3 ax = normalize(cross(S, vec3(0.0, 1.0, 0.0)) + vec3(0.0001, 0.0, 0.0001));
	vec3 ay = cross(ax, S);
	vec2 q = vec2(dot(d, ax), dot(d, ay));
	float mull = (1.0 - smoothstep(0.004, 0.012, min(abs(q.x), abs(q.y)))) * smoothstep(0.88, 0.95, sd) * (1.0 - smoothstep(0.985, 0.998, sd));
	col = mix(col, vec3(0.85, 0.72, 0.5), mull * 0.6);
	// below the horizon: warm floorboards fading away
	col = mix(col, below, 1.0 - smoothstep(-0.3, 0.0, up));
	COLOR = clamp(col, vec3(0.0), vec3(2.0));
}
"""


static func make() -> Sky:
	var sh := Shader.new()
	sh.code = CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky
