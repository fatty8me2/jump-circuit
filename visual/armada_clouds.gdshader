shader_type spatial;
// Storm Armada: the sea of storm clouds far below the fleet. A huge flat sheet shaded as billowing
// cloud tops rolling slowly downwind: dark blue-grey in the troughs, paler on the crests, gilded
// where you look toward the sunset, and lit from inside by lightning (`flash` at `flash_pos`,
// driven by the level's storm). Unshaded (the clouds make their own light); fog fades it out.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 trough : source_color = vec3(0.07, 0.08, 0.12);
uniform vec3 crest : source_color = vec3(0.34, 0.36, 0.44);
uniform vec3 sunset : source_color = vec3(1.0, 0.58, 0.3);
uniform vec3 bolt : source_color = vec3(0.65, 0.75, 1.0);
uniform vec2 sun_dir = vec2(0.0, -1.0);
uniform vec2 wind = vec2(1.6, 0.5);
uniform float flash = 0.0;
uniform vec3 flash_pos = vec3(0.0, 0.0, 0.0);
uniform float flash_radius = 220.0;

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
	vec2 p = wp.xz * 0.012 + wind * TIME * 0.004;
	float big = fbm(p);
	float fine = fbm(p * 3.1 + vec2(big * 1.5, -TIME * 0.01));
	float h = clamp(big * 0.75 + fine * 0.4, 0.0, 1.0);
	// crests lit from the west, troughs in shadow
	float lit = smoothstep(0.35, 0.8, h);
	vec3 col = mix(trough, crest, lit);
	// looking toward the sunset the crests glow gold
	vec3 to = wp - CAMERA_POSITION_WORLD;
	vec2 dir = normalize(to.xz + vec2(0.0001, 0.0));
	vec2 sd = normalize(sun_dir + vec2(0.0001, 0.0));
	float toward = clamp(dot(dir, sd) * 0.5 + 0.5, 0.0, 1.0);
	float glowdir = toward * toward * toward * toward;
	float far = smoothstep(150.0, 900.0, length(to.xz));
	col = mix(col, sunset * (0.4 + 0.7 * lit), glowdir * far * 0.75 * lit);
	// lightning flickering inside the clouds
	float dist = length(wp.xz - flash_pos.xz);
	float f = clamp(flash, 0.0, 1.0) * exp(-dist / max(flash_radius, 1.0));
	col += bolt * f * (0.6 + 1.6 * (1.0 - lit)) * 1.4;
	ALBEDO = clamp(col, vec3(0.0), vec3(4.0));
}
