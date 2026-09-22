shader_type spatial;
// Scrolling chevrons for boost strips and conveyors (arrow runs toward local -Z).
uniform vec3 base_color : source_color = vec3(0.08, 0.1, 0.16);
uniform vec3 arrow_color : source_color = vec3(0.2, 1.0, 0.9);
uniform float scroll_speed = 3.0;
uniform float glow = 2.5;
uniform float spacing = 1.6;
uniform vec3 half_size = vec3(1.0, 0.1, 3.0);
varying vec3 lp;
varying vec3 ln;
void vertex() { lp = VERTEX; ln = NORMAL; }
void fragment() {
	vec3 col = base_color;
	float g = 0.0;
	if (ln.y > 0.6) {
		float x = abs(lp.x) / max(half_size.x, 0.01);
		float v = (lp.z + x * half_size.x * 0.8) / spacing + TIME * scroll_speed / spacing;
		float f = fract(v);
		float chev = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.34, 0.4, f));
		chev *= 1.0 - smoothstep(0.82, 0.9, x);
		float edge = smoothstep(0.9, 0.93, x);
		g = max(chev, edge);
		col = mix(base_color, arrow_color, g);
	}
	ALBEDO = col;
	EMISSION = arrow_color * g * glow;
	ROUGHNESS = 0.5;
}
