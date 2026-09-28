shader_type spatial;
// Storm Armada: an airship's hull (decor). UV.x runs along the hull in metres (stern 0 -> bow),
// UV.y is the depth below the deck line in metres. Clinker strakes of tarred oak, a painted band
// with a row of gun ports (brass-framed, some glowing with lamplight) under the rail, a gilded
// rubbing strake, and a copper-sheathed bottom going green at the keel. Wet sheen from the rain.
render_mode cull_disabled;

uniform vec3 wood : source_color = vec3(0.3, 0.19, 0.11);
uniform vec3 paint : source_color = vec3(0.12, 0.22, 0.3);
uniform vec3 gilt : source_color = vec3(0.9, 0.66, 0.3);
uniform vec3 copper : source_color = vec3(0.55, 0.32, 0.2);
uniform vec3 verdigris : source_color = vec3(0.25, 0.5, 0.42);
uniform vec3 lamp : source_color = vec3(1.0, 0.66, 0.3);
uniform float depth = 4.0;
uniform float port_spacing = 2.6;
uniform float lit_ports = 0.35;

float hash11(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

void fragment() {
	float u = UV.x;
	float dd = UV.y;
	// strakes
	float sk = fract(dd / 0.34);
	float strake = smoothstep(0.0, 0.2, sk);
	float id = hash11(floor(dd / 0.34) * 7.1 + floor(u / 3.3) * 1.3);
	vec3 col = wood * (0.8 + 0.3 * id) * (0.7 + 0.3 * strake);
	col *= 0.9 + 0.15 * noise1(u * 3.0 + dd * 11.0);
	float rough = 0.65;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	// the gilded rail and rubbing strake
	float rail = 1.0 - smoothstep(0.12, 0.16, dd);
	float rub = smoothstep(1.35, 1.38, dd) * (1.0 - smoothstep(1.5, 1.53, dd));
	// painted band with the gun ports
	float band = smoothstep(0.18, 0.22, dd) * (1.0 - smoothstep(1.3, 1.34, dd));
	col = mix(col, paint * (0.85 + 0.2 * id), band);
	float pu = fract(u / port_spacing + 0.5) - 0.5;
	float cell = floor(u / port_spacing + 0.5);
	vec2 q = vec2(pu * port_spacing, dd - 0.76);
	float frame = 1.0 - smoothstep(0.34, 0.37, max(abs(q.x), abs(q.y)));
	float hole = 1.0 - smoothstep(0.26, 0.29, max(abs(q.x), abs(q.y)));
	float port = band * frame;
	col = mix(col, gilt * 0.9, port * (1.0 - hole));
	float lit = step(hash11(cell * 3.7 + 1.9), lit_ports);
	col = mix(col, mix(vec3(0.02), lamp * 0.6, lit), port * hole);
	emit += lamp * lit * port * hole * 1.6;
	col = mix(col, gilt, max(rail, rub));
	metal = max(rail, rub) * 0.7 + port * (1.0 - hole) * 0.6;
	rough = mix(rough, 0.3, max(rail, rub));
	// copper bottom, greening toward the keel
	float cu = smoothstep(depth * 0.55, depth * 0.58, dd);
	float green = smoothstep(depth * 0.7, depth * 1.0, dd) * (0.6 + 0.4 * noise1(u * 1.7 + dd * 3.0));
	vec3 plate = mix(copper, verdigris, green);
	float seam = step(0.93, fract(u / 1.2)) + step(0.9, fract(dd / 0.6));
	plate *= 1.0 - 0.25 * clamp(seam, 0.0, 1.0);
	col = mix(col, plate, cu);
	metal = mix(metal, 0.55, cu);
	rough = mix(rough, 0.45, cu);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
