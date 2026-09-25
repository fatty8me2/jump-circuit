shader_type spatial;
// Cinder Peak eruption cloud: the ash column and its anvil. Drawn on a few big smooth
// meshes (tapered cylinders, flattened spheres) far from the course: billowing 3D noise
// rolls upward and outward over the surface, the silhouette is soft and lumpy (fresnel +
// noise), the lower column glows red from the fountain beneath it and every lightning
// flash lights the cloud from inside around `flash_pos`. Ignores fog (it is fogged by hand
// toward `haze_color`, so it still reads through the smoke from the far start).

render_mode unshaded, fog_disabled, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 ash_dark : source_color = vec3(0.06, 0.045, 0.045);
uniform vec3 ash_light : source_color = vec3(0.24, 0.19, 0.18);
uniform vec3 under_color : source_color = vec3(1.0, 0.28, 0.05);
uniform vec3 flash_color : source_color = vec3(0.75, 0.7, 1.0);
uniform vec3 haze_color : source_color = vec3(0.16, 0.05, 0.035);
uniform float glow_base = 0.0;
uniform float glow_top = 600.0;
uniform float glow = 1.0;
uniform float rise = 6.0;
uniform float noise_scale = 0.012;
uniform float opacity = 0.95;
uniform float edge = 1.6;
uniform float flash = 0.0;
uniform vec3 flash_pos = vec3(0.0);
uniform float flash_radius = 300.0;
uniform float haze_start = 350.0;
uniform float haze_end = 1800.0;
// billowing silhouette: vertices pushed out along their normals by rising noise (metres)
uniform float disp = 0.0;
// the fire lights the cloud from below only near the column: the underglow fades with
// horizontal distance from it (otherwise the whole anvil became a bright orange ceiling)
uniform vec3 glow_center = vec3(0.0);
uniform float glow_reach = 100000.0;
// per-billow fade (rising puffs fade in at the vent and out at the top)
instance uniform float fade = 1.0;

varying vec3 wp;
varying vec3 op;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		s += a * noise3(p);
		p = p * 2.13 + vec3(1.7, 9.2, 3.1);
		a *= 0.48;
	}
	return s;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (disp > 0.0) {
		vec3 q = w * noise_scale * 1.3;
		q.y -= TIME * rise * noise_scale * 1.3;
		float n = noise3(q) * 0.65 + noise3(q * 2.1 + 7.0) * 0.35;
		VERTEX += NORMAL * (n - 0.35) * disp;
		w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	wp = w;
	op = VERTEX;
}

void fragment() {
	float t = TIME;
	vec3 p = wp * noise_scale;
	p.y -= t * rise * noise_scale;
	float b = fbm(p + vec3(0.0, 0.0, t * 0.01));
	float b2 = fbm(p * 2.3 + vec3(b * 1.5, -t * 0.02, 0.0));
	float bill = b * 0.65 + b2 * 0.45;
	// lumpy soft silhouette
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float body = smoothstep(0.0, 1.0, pow(facing, 0.7) * edge * (0.55 + bill));
	float a = clamp(body * opacity * fade, 0.0, 1.0);
	// self-shadowed billows: brighter tops of each roll
	vec3 col = mix(ash_dark, ash_light, smoothstep(0.35, 0.85, bill));
	// underlit by the fountain and the lava lake
	float low = 1.0 - clamp((wp.y - glow_base) / max(glow_top - glow_base, 1.0), 0.0, 1.0);
	float under = pow(low, 2.2) * glow * (0.55 + 0.9 * (1.0 - bill));
	float hd = length(wp.xz - glow_center.xz) / glow_reach;
	under *= exp(-hd * hd);
	col += under_color * min(under, 1.1) * 1.1;
	// lightning inside the cloud
	float fd = length(wp - flash_pos) / flash_radius;
	col += flash_color * flash * exp(-fd * fd * 2.5) * (0.6 + bill) * 2.5;
	// hand-made aerial perspective (the course fog is off here)
	float dist = length(wp - CAMERA_POSITION_WORLD);
	float hz = smoothstep(haze_start, haze_end, dist) * 0.55;
	col = mix(col, haze_color, hz);
	ALBEDO = col;
	ALPHA = a;
}
