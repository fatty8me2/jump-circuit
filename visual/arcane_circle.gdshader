shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// A spell circle drawn in light on the floor: two thin rings, a ring of runic ticks turning slowly,
// a six-pointed star inside. `charge` (0..1) is how far the spell has gathered: at 0 the lines are
// a dim ember, as it rises the runes spin faster and burn brighter and a bright wedge sweeps the
// outer ring like a clock hand, reaching a full white-gold circle at 1. NaN-safe, HDR bounded.

uniform vec3 tint : source_color = vec3(0.7, 0.45, 1.0);
uniform vec3 hot : source_color = vec3(1.0, 0.85, 0.5);
uniform float charge = 0.0;
uniform float idle = 0.35;

varying vec2 uvp;

void vertex() {
	uvp = UV * 2.0 - 1.0;
}

float line(float d, float w) {
	return 1.0 - smoothstep(0.0, w, abs(d));
}

void fragment() {
	vec2 p = uvp;
	float r = length(p);
	float c = clamp(charge, 0.0, 1.0);
	float ang = atan(p.y, p.x);
	float spin = TIME * (0.25 + 1.6 * c);
	float lit = idle + (1.0 - idle) * c;
	// outer rings
	float g = line(r - 0.94, 0.02) + line(r - 0.86, 0.012) * 0.7;
	// runic ticks between the rings, a bar and a notch alternating
	float seg = fract((ang + spin) / 6.2831853 * 24.0);
	float tick = step(0.35, seg) * step(seg, 0.62) * step(0.88, r) * step(r, 0.93);
	float notch = step(0.1, seg) * step(seg, 0.2) * step(0.78, r) * step(r, 0.86);
	g += tick * 0.9 + notch * 0.7;
	// six-pointed star: two triangles
	float a2 = ang - spin * 0.5;
	float tri1 = abs(r * cos(mod(a2 + 0.5236, 2.0944) - 1.0472) - 0.5);
	float tri2 = abs(r * cos(mod(a2 + 2.618, 2.0944) - 1.0472) - 0.5);
	g += (line(tri1, 0.02) + line(tri2, 0.02)) * step(r, 0.82) * 0.8;
	// inner ring and a hub dot
	g += line(r - 0.28, 0.015) * 0.7 + (1.0 - smoothstep(0.0, 0.07, r)) * 0.8;
	// charge hand: a wedge sweeping the outer ring
	float sweep = fract((ang / 6.2831853) + 0.25 + 1.0);
	float arc = step(sweep, c) * step(0.84, r) * step(r, 0.97);
	g += arc * 1.6;
	float disc = 1.0 - smoothstep(0.96, 1.0, r);
	float glow = (1.0 - smoothstep(0.0, 1.0, r)) * (0.08 + 0.35 * c);
	vec3 col = mix(tint, hot, c * c) * (g * lit + glow);
	ALBEDO = min(col * disc, vec3(3.0));
	ALPHA = 1.0;
}
