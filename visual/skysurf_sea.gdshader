shader_type spatial;
// Sky Surf: the sea of cloud far below the islands. A huge flat sheet shaded as soft billows drifting
// slowly downwind: lilac in the troughs, cream-pink on the crests, gilded where you look toward the
// sunrise, with long low swells. Unshaded (the clouds make their own light); fog carries it to the
// horizon. NaN-safe: no normalize of a zero vector, divides guarded.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 trough : source_color = vec3(0.70, 0.60, 0.86);
uniform vec3 crest : source_color = vec3(1.0, 0.91, 0.90);
uniform vec3 sunrise : source_color = vec3(1.0, 0.76, 0.5);
uniform vec2 sun_dir = vec2(0.5, -0.87);
uniform vec2 wind = vec2(0.8, 0.3);

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
	for (int i = 0; i < 5; i++) {
		s += a * noise2(p);
		p = p * 2.02 + vec2(5.3, 1.9);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz * 0.011 + wind * TIME * 0.004;
	float big = fbm(p);
	float fine = fbm(p * 3.3 + vec2(big * 1.6, -TIME * 0.008));
	float h = clamp(big * 0.78 + fine * 0.38, 0.0, 1.0);
	float lit = smoothstep(0.32, 0.78, h);
	vec3 col = mix(trough, crest, lit);
	// looking toward the sunrise the crests glow gold
	vec3 to = wp - CAMERA_POSITION_WORLD;
	vec2 dir = to.xz;
	float dl = length(dir);
	dir = dl > 0.001 ? dir / dl : vec2(0.0, -1.0);
	vec2 sd = sun_dir;
	float sl = length(sd);
	sd = sl > 0.001 ? sd / sl : vec2(0.0, -1.0);
	float toward = clamp(dot(dir, sd) * 0.5 + 0.5, 0.0, 1.0);
	float glowdir = toward * toward * toward;
	float far = smoothstep(120.0, 800.0, dl);
	col = mix(col, sunrise * (0.55 + 0.6 * lit), glowdir * (0.25 + 0.55 * far) * (0.35 + 0.65 * lit));
	ALBEDO = clamp(col, vec3(0.0), vec3(3.0));
}
