shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Neon City light cone (searchlights, hologram projectors, headlights): a soft additive beam,
// brightest at its source (UV.y = 0 at the top of a CylinderMesh) and along its silhouette,
// fading toward the far end, with rain streaks drifting down through it. Bounded and NaN-safe.

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float strength = 0.5;
uniform float streaks = 1.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float fall = (1.0 - along) * 0.75 + 0.25;
	// brighter where the beam is seen edge-on (its rim), soft through its middle
	float ndv = abs(dot(NORMAL / max(length(NORMAL), 0.0001), VIEW / max(length(VIEW), 0.0001)));
	float rim = 0.35 + 0.65 * (1.0 - clamp(ndv, 0.0, 1.0));
	// rain streaks: thin vertical slivers sliding down
	float col = floor(UV.x * 90.0);
	float h = hash11(col);
	float y = fract(along * 3.0 - TIME * (1.2 + h * 1.5) + h * 7.0);
	float streak = step(0.82, h) * smoothstep(0.0, 0.08, y) * (1.0 - smoothstep(0.1, 0.35, y));
	float a = clamp(strength * fall * rim + streak * streaks * 0.35 * fall, 0.0, 2.0);
	ALBEDO = tint.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
