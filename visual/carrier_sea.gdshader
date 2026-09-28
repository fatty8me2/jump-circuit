shader_type spatial;
render_mode cull_disabled;
// Super Carrier: the open ocean round the ship. Deep blue water whose waves are drawn in the normal
// (no vertex displacement: one flat plane stays cheap at any size), glittering under the sun, and the
// white water the carrier makes as it steams ahead at speed: a churning wake widening astern, a bow
// wave, and foam hugging the hull at the waterline. The whole pattern streams aft with the ship's
// speed, so the carrier reads as under way. Bounded: no pow() on negatives, no zero normalize().

uniform vec3 deep : source_color = vec3(0.02, 0.1, 0.2);
uniform vec3 shallow : source_color = vec3(0.06, 0.26, 0.38);
uniform vec3 foam : source_color = vec3(0.92, 0.95, 0.97);
// the ship's footprint at the waterline: stern z, bow z, half beam (world)
uniform float stern_z = 22.0;
uniform float bow_z = -345.0;
uniform float beam = 20.0;
uniform float ship_x = 0.0;
uniform float speed = 9.0;

varying vec3 wp;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p = p * 2.1 + vec2(4.1, 1.3);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	// the sea flows aft past the ship
	vec2 q = wp.xz + vec2(0.0, t * speed);
	// wave slopes: long swells plus chop
	vec2 g = vec2(0.0);
	g += vec2(0.32, 0.12) * cos(dot(q, vec2(0.021, 0.013)) + t * 0.6);
	g += vec2(-0.1, 0.28) * cos(dot(q, vec2(-0.011, 0.034)) + t * 0.9);
	g += vec2(0.14, -0.2) * cos(dot(q, vec2(0.07, -0.052)) + t * 1.4);
	float n1 = noise2(q * 0.35 + vec2(t * 0.2, 0.0));
	float n2 = noise2(q * 0.35 + vec2(0.37, t * 0.2));
	g += vec2(n1 - 0.5, n2 - 0.5) * 0.5;
	vec3 nrm = normalize(vec3(-g.x * 0.35, 1.0, -g.y * 0.35));
	NORMAL = (VIEW_MATRIX * vec4(nrm, 0.0)).xyz;
	// white water: the wake astern, the bow wave and the foam along the hull
	float dx = abs(wp.x - ship_x);
	float astern = wp.z - stern_z;
	float wake = 0.0;
	if (astern > 0.0) {
		float width = beam * 0.8 + astern * 0.18;
		float core = 1.0 - smoothstep(width * 0.35, width, dx);
		float fade = 1.0 - smoothstep(60.0, 520.0, astern);
		// the kelvin arms: two bright lines spreading at ~20 degrees
		float arm = 1.0 - smoothstep(0.0, 6.0 + astern * 0.03, abs(dx - (beam + astern * 0.36)));
		wake = (core * 0.9 + arm * 0.6) * fade;
	}
	float along = step(bow_z, wp.z) * step(wp.z, stern_z);
	float hull = along * (1.0 - smoothstep(beam, beam + 5.0, dx)) * 0.8;
	float ahead = bow_z - wp.z;
	float bow = (1.0 - smoothstep(0.0, 14.0, abs(ahead + 2.0))) * (1.0 - smoothstep(beam * 0.3, beam * 1.2, dx)) * 0.9;
	float bow_arms = step(0.0, -ahead) * (1.0 - smoothstep(0.0, 5.0, abs(dx - beam - (wp.z - bow_z) * 0.05))) * (1.0 - smoothstep(0.0, 160.0, wp.z - bow_z)) * 0.7;
	float white = clamp(wake + hull + bow + bow_arms, 0.0, 1.0);
	float broken = fbm(q * 0.12) * 0.7 + fbm(q * 0.5) * 0.3;
	float f = smoothstep(0.35, 0.75, white * (0.55 + broken * 0.9));
	// scattered whitecaps in the open sea
	float caps = smoothstep(0.78, 0.9, fbm(q * 0.05 + vec2(0.0, t * 0.05))) * 0.35;
	f = clamp(f + caps * smoothstep(0.6, 0.9, noise2(q * 0.8)), 0.0, 1.0);
	vec3 water = mix(deep, shallow, clamp(0.5 + g.x * 0.4 + (n1 - 0.5) * 0.4, 0.0, 1.0));
	ALBEDO = mix(water, foam, f);
	ROUGHNESS = mix(0.06, 0.8, f);
	METALLIC = mix(0.15, 0.0, f);
	SPECULAR = 0.6;
}
