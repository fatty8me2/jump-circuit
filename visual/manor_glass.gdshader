shader_type spatial;
render_mode unshaded, cull_disabled;
// Phantom Manor: a lancet window of broken stained glass glowing from inside. UV space is the
// window's quad (0..1 across, 0..1 up); the top is a pointed gothic arch, everything outside it
// is discarded. Leaded panes in jewel colours (violet, blood red, poison green, amber), a
// rose of tracery near the top, a few panes knocked out (dark holes), and a slow candle
// flicker. Emission is bounded by `glow`.

uniform vec3 col_a : source_color = vec3(0.55, 0.2, 0.85);
uniform vec3 col_b : source_color = vec3(0.9, 0.12, 0.16);
uniform vec3 col_c : source_color = vec3(0.3, 0.95, 0.45);
uniform vec3 col_d : source_color = vec3(1.0, 0.62, 0.2);
uniform float glow : hint_range(0.0, 4.0) = 1.6;
uniform float broken : hint_range(0.0, 1.0) = 0.18;
uniform float seed = 0.0;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33 + seed);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV;
	uv.y = 1.0 - uv.y;
	// pointed arch: from the springing line at 0.7 two arcs (radius 0.34, centred 0.34 in from
	// each jamb) rise to meet in a point at the top
	if (uv.y > 0.7) {
		float x = abs(uv.x - 0.5);
		if (length(vec2(0.5 - x - 0.34, uv.y - 0.7)) > 0.34) {
			discard;
		}
	}
	// lead cames: a diamond lattice below, a rose of spokes in the arch
	vec2 g = vec2((uv.x + uv.y) * 5.0, (uv.x - uv.y) * 5.0);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float lead = 1.0 - smoothstep(0.03, 0.07, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	vec2 rc = vec2(0.5, 0.8);
	vec2 rd = uv - rc;
	float rr = length(rd);
	float rose = step(rr, 0.16);
	if (rose > 0.5) {
		float ang = atan(rd.y, rd.x + 0.0001);
		float spoke = abs(fract(ang / 6.2831853 * 8.0) - 0.5);
		lead = max(1.0 - smoothstep(0.02, 0.06, spoke * rr * 6.0), 1.0 - smoothstep(0.012, 0.03, abs(rr - 0.08)));
		lead = max(lead, 1.0 - smoothstep(0.012, 0.03, abs(rr - 0.155)));
		cell = vec2(floor(ang * 1.27), floor(rr * 10.0));
	}
	float frame = 1.0 - smoothstep(0.03, 0.05, min(min(uv.x, 1.0 - uv.x), uv.y));
	float pick = h12(cell + seed * 3.1);
	vec3 pane = pick < 0.25 ? col_a : (pick < 0.5 ? col_b : (pick < 0.75 ? col_c : col_d));
	pane *= 0.65 + 0.5 * h12(cell * 1.7 + 4.0);
	float hole = step(1.0 - broken, h12(cell * 2.3 + 9.0));
	float flick = 0.85 + 0.15 * sin(TIME * 6.3 + seed * 7.0) * sin(TIME * 2.1 + seed);
	vec3 c = pane * (1.0 - hole * 0.92) * flick;
	c = mix(c, vec3(0.03, 0.025, 0.04), clamp(lead + frame, 0.0, 1.0));
	ALBEDO = c * clamp(glow, 0.0, 4.0);
}
