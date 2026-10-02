shader_type spatial;
render_mode cull_disabled;
// Tempest Tower: a torn tarpaulin snapping in the hurricane. A subdivided plane tied along its UV.x = 0
// edge: the free end whips and ripples harder the further it is from the tie (bounded displacement),
// and the ragged free edge is cut out by noise. Tint per material. No pow, no normalize of zero.

uniform vec4 tint : source_color = vec4(0.18, 0.36, 0.62, 1.0);
uniform float amp = 0.6;
uniform float speed = 7.0;
uniform float seed = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	float k = clamp(UV.x, 0.0, 1.0);
	float t = TIME * speed + seed * 13.0;
	float w = sin(t - UV.x * 7.0 + UV.y * 2.5) * 0.7 + sin(t * 1.7 - UV.x * 11.0 + UV.y * 5.0) * 0.3;
	VERTEX.y += w * amp * k * k;
	VERTEX.z += sin(t * 0.9 - UV.x * 4.0) * amp * 0.35 * k;
}

void fragment() {
	// ragged free edge and a couple of tears
	float rag = hash12(floor(vec2(UV.y * 24.0, seed * 7.0)));
	if (UV.x > 0.86 + 0.14 * rag) {
		discard;
	}
	float tear = step(0.92, hash12(floor(UV * vec2(9.0, 5.0)) + seed)) * step(0.35, UV.x);
	if (tear > 0.5) {
		discard;
	}
	float fold = 0.85 + 0.15 * sin(UV.y * 40.0 + UV.x * 6.0);
	ALBEDO = tint.rgb * fold;
	ROUGHNESS = 0.45;
	SPECULAR = 0.6;
}
