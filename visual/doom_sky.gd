class_name DoomSky
extends RefCounted
## Doom Fortress's "sky": the inside of the doomsday machine. There is no open air - overhead a
## soot-black vault criss-crossed by the silhouettes of colossal girders and lattice trusses, fading
## into smoke; round the horizon the far halls glow forge-orange through the haze, with one hot
## direction (the reactor) burning brighter; below, the pits of molten metal light everything from
## underneath in deep red. Static (no TIME) so the radiance map renders once. Bounded and NaN-safe:
## pow() only of clamped values, no normalize() of a zero vector, smoothstep edges in order.

const CODE: String = """
shader_type sky;
render_mode use_debanding;

uniform vec3 vault : source_color = vec3(0.018, 0.012, 0.012);
uniform vec3 smoke : source_color = vec3(0.10, 0.04, 0.03);
uniform vec3 forge : source_color = vec3(0.85, 0.26, 0.06);
uniform vec3 pit : source_color = vec3(0.45, 0.06, 0.02);
uniform vec3 core_dir = vec3(0.0, 0.18, -1.0);
uniform vec3 core_col : source_color = vec3(1.0, 0.45, 0.18);

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float dl = length(d);
	d = dl > 0.0001 ? d / dl : vec3(0.0, 1.0, 0.0);
	float up = d.y;
	vec2 dh = d.xz + vec2(0.0001);
	dh = dh / max(length(dh), 0.0001);
	float az = atan(dh.y, dh.x);
	// base: the black vault above, a smoky forge-lit band round the horizon, the red pits below
	float hz = 1.0 - smoothstep(0.0, 0.45, up);
	vec3 col = mix(vault, smoke, hz);
	float warm = fbm(vec2(az * 2.2, up * 3.0) + vec2(4.0, 1.0));
	col += forge * (0.10 + 0.22 * warm) * (1.0 - smoothstep(-0.05, 0.28, up)) * smoothstep(-0.35, -0.02, up);
	// the reactor's direction burns brighter (the goal, visible from the start)
	vec3 C = core_dir / max(length(core_dir), 0.0001);
	float cd = clamp(dot(d, C), -1.0, 1.0);
	float cg = clamp(cd, 0.0, 1.0);
	col += core_col * (pow(cg, 18.0) * 0.55 + pow(cg, 4.0) * 0.12);
	// the vault: girders and trusses as dark silhouettes against faint smoke-light
	if (up > 0.05) {
		vec2 cp = d.xz / (up + 0.05);
		vec2 gl = abs(fract(cp * 0.35) - 0.5);
		float beam = 1.0 - smoothstep(0.0, 0.03, min(gl.x, gl.y));
		vec2 tl = abs(fract((cp.x + cp.y) * 0.7 + vec2(0.0, 0.5)) - 0.5);
		float truss = (1.0 - smoothstep(0.0, 0.02, tl.x)) * step(0.5, fract(cp.y * 0.35));
		float lit = fbm(cp * 0.25) * 0.08 * (1.0 - smoothstep(0.1, 0.9, up));
		col += vec3(0.5, 0.18, 0.1) * lit;
		col *= 1.0 - 0.75 * clamp(beam + truss * 0.6, 0.0, 1.0) * (1.0 - smoothstep(0.7, 1.0, up));
	}
	// below: the molten pits glowing up through smoke
	float below = 1.0 - smoothstep(-0.25, 0.0, up);
	float pits = fbm(vec2(az * 3.0, up * 6.0) + vec2(9.0, 3.0));
	col = mix(col, pit * (0.5 + 0.9 * pits) + forge * 0.08, below);
	COLOR = clamp(col, vec3(0.0), vec3(3.0));
}
"""


static func make(core_dir: Vector3 = Vector3(0, 0.18, -1)) -> Sky:
	var sh := Shader.new()
	sh.code = CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("core_dir", core_dir)
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky
