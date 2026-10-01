shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, shadows_disabled;
// Neon City hologram slab: a translucent projected floor. A bright grid on its top face, scanlines
// rolling across every face, brighter edges seen edge-on. `glitch` (0..1) is the vanish warning:
// the slab tears into horizontal bands that jitter sideways, splits into magenta / cyan and
// stutters. `ghost` (0..1) dims it to the faint outline it leaves while it is switched off.
// Bounded and NaN-safe.

uniform vec4 tint : source_color = vec4(0.1, 0.95, 0.85, 1.0);
uniform vec4 split : source_color = vec4(1.0, 0.2, 0.7, 1.0);
uniform float glitch = 0.0;
uniform float ghost = 0.0;
uniform vec3 half_size = vec3(1.0, 0.2, 1.0);

varying vec3 lp;
varying vec3 ln;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	// tearing: bands of the slab slide sideways while it glitches
	float band = floor((VERTEX.y + VERTEX.z * 0.5) * 6.0 + floor(TIME * 18.0));
	VERTEX.x += (hash11(band) - 0.5) * 0.35 * glitch;
}

void fragment() {
	float t = TIME;
	vec3 n = ln / max(length(ln), 0.0001);
	float ndv = clamp(abs(dot(NORMAL / max(length(NORMAL), 0.0001), VIEW / max(length(VIEW), 0.0001))), 0.0, 1.0);
	float edge_glow = 1.0 - ndv;
	// scanlines rolling across every face
	float scan = 0.5 + 0.5 * sin((lp.y * 14.0 + lp.z * 3.0 + lp.x * 1.5) * 6.2832 * 0.5 - t * 6.0);
	float bright = 0.55 + 0.25 * scan + 0.5 * edge_glow;
	// grid on the top face, and a hot rim round its edge
	if (n.y > 0.6) {
		vec2 g = abs(fract(lp.xz * 1.25) - 0.5);
		float grid = 1.0 - smoothstep(0.0, 0.035, 0.5 - max(g.x, g.y));
		vec2 d = half_size.xz - abs(lp.xz);
		float rim = 1.0 - smoothstep(0.04, 0.16, min(d.x, d.y));
		bright += grid * 0.7 + rim * 1.4;
	}
	// glitch: stutter (whole slab blinks), colour split, static
	float stutter = step(0.5, hash11(floor(t * 22.0))) * glitch;
	float stat = hash11(floor(lp.x * 40.0) + floor(lp.z * 40.0) * 57.0 + floor(t * 30.0) * 13.0);
	vec3 col = mix(tint.rgb, split.rgb, glitch * step(0.55, hash11(floor(lp.y * 9.0 + t * 25.0))));
	bright *= 1.0 - 0.75 * stutter;
	bright += stat * glitch * 0.6;
	float a = (0.38 + 0.3 * edge_glow + 0.1 * scan) * (1.0 - ghost * 0.85);
	bright *= 1.0 - ghost * 0.7;
	ALBEDO = col * clamp(bright, 0.0, 3.0);
	ALPHA = clamp(a * (1.0 - stutter * 0.6), 0.0, 1.0);
}
