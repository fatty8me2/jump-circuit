shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Castle Siege banner: a hanging cloth that ripples in the smoke-wind (the ripple grows toward the
// free end and the bottom edge), with a field colour, a gold border, a swallow-tail cut and a simple
// charge (a gold chevron and a roundel). Bounded and NaN-safe: no divisions by unguarded values.

uniform vec3 field : source_color = vec3(0.7, 0.08, 0.1);
uniform vec3 gold : source_color = vec3(0.95, 0.72, 0.2);
uniform float wave = 0.14;
uniform float speed = 2.2;
uniform float seed = 0.0;
uniform float glow = 0.18;

varying vec2 st;

void vertex() {
	// UV.x across, UV.y down the cloth; the top edge is pinned
	st = UV;
	float k = clamp(UV.y, 0.0, 1.0);
	float w = sin(TIME * speed + UV.y * 5.0 + seed) * 0.6 + sin(TIME * speed * 1.7 + UV.x * 4.0 + seed * 2.0) * 0.4;
	VERTEX.z += w * wave * k;
	VERTEX.x += sin(TIME * speed * 0.8 + seed + UV.y * 3.0) * wave * 0.4 * k;
}

void fragment() {
	vec2 p = st;
	// swallow-tail cut at the bottom
	float tail = 0.86 + 0.14 * abs(p.x * 2.0 - 1.0);
	if (p.y > tail) {
		discard;
	}
	vec3 col = field;
	float border = min(min(p.x, 1.0 - p.x), min(p.y, tail - p.y));
	col = mix(col, gold, 1.0 - smoothstep(0.035, 0.06, border));
	// a gold chevron and a roundel on the field
	float chev = abs(p.y - (0.3 + abs(p.x - 0.5) * 0.9));
	col = mix(col, gold, (1.0 - smoothstep(0.035, 0.05, chev)) * step(0.12, p.y) * step(p.y, 0.62));
	float round_d = length((p - vec2(0.5, 0.62)) * vec2(1.0, 1.1));
	col = mix(col, gold, 1.0 - smoothstep(0.075, 0.09, round_d));
	// fold shading from the ripple
	float fold = 0.88 + 0.12 * sin(p.y * 22.0 + TIME * speed + seed);
	ALBEDO = col * fold;
	ROUGHNESS = 0.9;
	EMISSION = col * glow;
}
