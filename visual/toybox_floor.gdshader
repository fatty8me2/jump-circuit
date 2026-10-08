shader_type spatial;
render_mode unshaded, cull_back;
// Toybox Tumble's bedroom floor far below the course: warm wooden planks, and on them a big play rug
// printed with roads (grey strips with dashed yellow centre lines), green park patches, a blue pond
// and a border of cream and red. World-space (so it lines up with the room), no TIME. Unshaded, with
// a soft darkening toward the edges so it fades into the fog. NaN-safe.

uniform vec2 rug_center = vec2(0.0, 0.0);
uniform vec2 rug_half = vec2(140.0, 260.0);
uniform vec3 plank_a : source_color = vec3(0.72, 0.5, 0.3);
uniform vec3 plank_b : source_color = vec3(0.64, 0.43, 0.26);
uniform vec3 rug_base : source_color = vec3(0.98, 0.9, 0.7);
uniform vec3 road : source_color = vec3(0.45, 0.47, 0.52);
uniform vec3 grass : source_color = vec3(0.55, 0.78, 0.4);
uniform vec3 water : source_color = vec3(0.4, 0.7, 0.95);
uniform vec3 border_red : source_color = vec3(0.85, 0.28, 0.25);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = wp.xz;
	// planks, 3 m wide, staggered ends every 24 m
	float row = floor(p.x / 3.0);
	float off = hash12(vec2(row, 3.0)) * 24.0;
	float along = floor((p.y + off) / 24.0);
	float tone = hash12(vec2(row, along));
	vec3 col = mix(plank_a, plank_b, tone);
	float seam = min(abs(fract(p.x / 3.0) - 0.5), 0.5);
	col *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.025, 0.5 - seam));
	float seam2 = abs(fract((p.y + off) / 24.0) - 0.5);
	col *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.01, 0.5 - seam2));
	// the rug
	vec2 r = (p - rug_center) / max(rug_half, vec2(1.0));
	float inside = 1.0 - smoothstep(0.98, 1.0, max(abs(r.x), abs(r.y)));
	if (inside > 0.0) {
		vec3 rc = rug_base;
		// border bands
		float m = max(abs(r.x), abs(r.y));
		float band = smoothstep(0.9, 0.905, m) * (1.0 - smoothstep(0.95, 0.955, m));
		rc = mix(rc, border_red, band);
		// roads: a grid of strips 12 m wide every 90 m, dashed centre lines
		vec2 g = p - rug_center;
		vec2 cell = fract(g / 90.0);
		float rx = 1.0 - smoothstep(0.0, 0.01, abs(cell.x - 0.5) - 0.066);
		float rz = 1.0 - smoothstep(0.0, 0.01, abs(cell.y - 0.5) - 0.066);
		float roads = max(rx, rz);
		rc = mix(rc, road, roads * step(m, 0.9));
		float dash_x = rx * (1.0 - smoothstep(0.0, 0.004, abs(cell.x - 0.5) - 0.006)) * step(0.5, fract(g.y / 9.0));
		float dash_z = rz * (1.0 - smoothstep(0.0, 0.004, abs(cell.y - 0.5) - 0.006)) * step(0.5, fract(g.x / 9.0));
		rc = mix(rc, vec3(1.0, 0.85, 0.25), max(dash_x, dash_z) * step(m, 0.9));
		// park blocks: grass in some of the squares between roads, a pond in one
		vec2 id = floor(g / 90.0);
		float h = hash12(id + vec2(7.0, 11.0));
		float block = (1.0 - roads) * step(m, 0.88);
		if (h < 0.45) {
			rc = mix(rc, grass, block * 0.9);
		}
		if (h > 0.9) {
			vec2 pc = (fract(g / 90.0) - vec2(0.5)) * 90.0;
			float pond = 1.0 - smoothstep(18.0, 20.0, length(pc));
			rc = mix(rc, water, pond * block);
		}
		col = mix(col, rc, inside);
	}
	// soft light pool from the window and a fade at the edges of the floor
	float fade = 1.0 - smoothstep(380.0, 640.0, length(p - rug_center));
	col *= 0.82 + 0.18 * fade;
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
}
