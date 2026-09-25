shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Xeno Wilds: an aurora ribbon - a vast vertical curtain (a subdivided PlaneMesh standing up) that
// ripples along its length, with bright vertical rays sliding across it: green-teal at its hem,
// fading through violet into the sky above. Far away and additive, so it only ever adds light.

uniform vec3 hem_color : source_color = vec3(0.3, 1.0, 0.7);
uniform vec3 crown_color : source_color = vec3(0.75, 0.3, 1.0);
uniform float intensity = 1.0;
uniform float wave = 18.0;
uniform float speed = 0.12;
uniform float seed = 0.0;

void vertex() {
	float t = TIME * speed + seed;
	// the curtain folds back and forth along its length
	VERTEX.z += sin(UV.x * 9.0 + t * 3.0) * wave * 0.6 + sin(UV.x * 23.0 - t * 5.0) * wave * 0.15;
	VERTEX.y += sin(UV.x * 5.0 + t * 2.0) * wave * 0.2;
}

void fragment() {
	float t = TIME * speed + seed;
	float v = 1.0 - UV.y;
	// rays: thin vertical streaks drifting along the ribbon
	float rays = 0.5 + 0.5 * sin(UV.x * 140.0 + t * 9.0 + sin(UV.x * 31.0 - t * 4.0) * 2.0);
	rays = pow(rays, 3.0);
	float hem = smoothstep(0.0, 0.08, v) * (1.0 - smoothstep(0.08, 0.9, v));
	float glow = smoothstep(0.0, 0.1, v) * (1.0 - smoothstep(0.3, 1.0, v));
	float ends = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
	vec3 col = mix(hem_color, crown_color, smoothstep(0.1, 0.7, v));
	float a = (hem * 0.7 + glow * 0.5) * (0.35 + 0.9 * rays) * ends;
	a *= 0.7 + 0.3 * sin(UV.x * 7.0 - t * 2.5);
	ALBEDO = col * a * intensity;
}
