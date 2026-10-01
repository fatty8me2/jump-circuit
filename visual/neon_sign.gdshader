shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Neon City signage on a QuadMesh (UV 0..1). No real words or brands - abstract glyphs only.
//  mode 0 - a tall blade sign: a stack of `cells` glyphs (bars, rings, chevrons, dots) drawn as
//           neon tubes on a dark backing, a chase of bulbs up its border, the odd tube flickering.
//  mode 1 - a holographic billboard (additive): shapes pulsing, sliding and rotating through a
//           loop of abstract "ads", scanlines, a colour-split shimmer and a frame.
//  mode 2 - a wide shop-front strip: a row of glyphs with an underline that pulses.
// Emission is bounded; no pow/normalize; NaN-safe.

uniform int mode = 0;
uniform vec4 color_a : source_color = vec4(1.0, 0.2, 0.7, 1.0);
uniform vec4 color_b : source_color = vec4(0.1, 0.95, 0.85, 1.0);
uniform float seed = 1.0;
uniform float cells = 5.0;
uniform float bright = 2.4;
uniform float alpha_scale = 1.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// distance to a segment
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}

// one abstract glyph in a unit cell (p in -0.5..0.5); returns distance to its strokes
float glyph(vec2 p, float k) {
	float d = 10.0;
	float kind = floor(k * 6.0);
	if (kind < 1.0) {
		d = abs(length(p) - 0.3);
	} else if (kind < 2.0) {
		d = min(seg(p, vec2(-0.3, -0.3), vec2(0.0, 0.3)), seg(p, vec2(0.0, 0.3), vec2(0.3, -0.3)));
	} else if (kind < 3.0) {
		d = min(seg(p, vec2(-0.3, 0.25), vec2(0.3, 0.25)), min(seg(p, vec2(-0.3, -0.25), vec2(0.3, -0.25)), seg(p, vec2(0.0, 0.25), vec2(0.0, -0.25))));
	} else if (kind < 4.0) {
		d = min(seg(p, vec2(-0.3, 0.3), vec2(-0.3, -0.3)), min(seg(p, vec2(-0.3, 0.0), vec2(0.25, 0.3)), seg(p, vec2(-0.3, 0.0), vec2(0.25, -0.3))));
	} else if (kind < 5.0) {
		d = min(abs(length(p - vec2(0.0, 0.12)) - 0.16), seg(p, vec2(-0.28, -0.3), vec2(0.28, -0.3)));
	} else {
		d = min(seg(p, vec2(-0.28, -0.28), vec2(0.28, 0.28)), seg(p, vec2(-0.28, 0.28), vec2(0.28, -0.28)));
	}
	return d;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 col = vec3(0.0);
	float a = 1.0;
	if (mode == 1) {
		// holographic billboard: 3 slides of shapes
		float slide = floor(t / 3.5 + seed);
		float st = fract(t / 3.5 + seed);
		vec2 p = (uv - 0.5) * vec2(1.6, 1.0);
		float k = hash11(slide * 7.3 + seed);
		float d;
		if (k < 0.33) {
			float r = 0.15 + 0.12 * sin(t * 3.0);
			d = min(abs(length(p) - r), abs(length(p) - r * 1.8));
		} else if (k < 0.66) {
			float ang = t * 1.2;
			mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
			vec2 q = rot * p;
			d = min(seg(q, vec2(-0.3, -0.2), vec2(0.0, 0.3)), min(seg(q, vec2(0.0, 0.3), vec2(0.3, -0.2)), seg(q, vec2(0.3, -0.2), vec2(-0.3, -0.2))));
		} else {
			d = abs(p.y - 0.12 * sin(p.x * 9.0 + t * 4.0));
			d = min(d, abs(p.y + 0.2 - 0.08 * sin(p.x * 6.0 - t * 3.0)));
		}
		float line = 1.0 - smoothstep(0.012, 0.03, d);
		float halo = 1.0 - smoothstep(0.0, 0.16, d);
		vec3 c1 = mix(color_a.rgb, color_b.rgb, step(0.5, hash11(slide + 3.0)));
		col = c1 * (line * 1.3 + halo * 0.35);
		// frame and scanlines
		vec2 e = min(uv, 1.0 - uv);
		float frame = 1.0 - smoothstep(0.01, 0.025, min(e.x, e.y));
		col += color_b.rgb * frame * 0.8;
		float scan = 0.75 + 0.25 * sin(uv.y * 160.0 - t * 8.0);
		col *= scan;
		// colour-split shimmer and a wipe between slides
		col += color_a.rgb * 0.08 * step(0.92, hash11(floor(uv.y * 40.0) + floor(t * 12.0)));
		float wipe = smoothstep(0.0, 0.08, st) * (1.0 - smoothstep(0.92, 1.0, st));
		col *= 0.25 + 0.75 * wipe;
		a = clamp((line + halo * 0.4 + frame * 0.6 + 0.06) * alpha_scale, 0.0, 1.0);
	} else {
		float n = max(cells, 1.0);
		vec2 grid;
		vec2 p;
		float idx;
		if (mode == 2) {
			grid = vec2(uv.x * n, uv.y);
			idx = floor(grid.x);
			p = vec2(fract(grid.x) - 0.5, (uv.y - 0.55) * 1.4);
		} else {
			grid = vec2(uv.x, uv.y * n);
			idx = floor(grid.y);
			p = vec2((uv.x - 0.5) * 1.15, fract(grid.y) - 0.5);
		}
		float k = hash11(idx * 3.17 + seed * 11.0);
		float d = glyph(p, k);
		float tube = 1.0 - smoothstep(0.025, 0.05, d);
		float halo = 1.0 - smoothstep(0.0, 0.2, d);
		vec3 c1 = hash11(idx + seed * 5.0) < 0.6 ? color_a.rgb : color_b.rgb;
		// the odd tube flickers or is dead
		float fl = hash11(idx * 9.1 + seed + floor(t * 9.0));
		float bad = step(0.86, hash11(idx * 4.7 + seed * 2.0));
		float lit = mix(1.0, step(0.35, fl), bad);
		vec3 backing = vec3(0.03, 0.025, 0.04);
		col = backing + c1 * (tube * 1.2 + halo * 0.3) * lit;
		// border chase lights
		vec2 e = min(uv, 1.0 - uv);
		float border = 1.0 - smoothstep(0.02, 0.04, min(e.x * (mode == 2 ? 1.0 : 3.0), e.y * (mode == 2 ? 6.0 : 1.0)));
		float chase = step(0.5, fract((uv.y + uv.x) * (mode == 2 ? 30.0 : 24.0) - t * 2.0));
		col += color_b.rgb * border * (0.3 + 0.9 * chase);
		if (mode == 2) {
			float under = (1.0 - smoothstep(0.0, 0.03, abs(uv.y - 0.12))) * (0.6 + 0.4 * sin(t * 4.0 + uv.x * 6.0));
			col += color_a.rgb * under;
		}
	}
	ALBEDO = clamp(col * bright, vec3(0.0), vec3(6.0));
	ALPHA = a;
}
