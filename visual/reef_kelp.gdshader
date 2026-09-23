shader_type spatial;
render_mode cull_disabled;
// Coral Depths kelp: a tall ribbon (QuadMesh subdivided along its height) that sways in
// the current - the bend grows with height - and bulges into leaves along its length.
// Works on single meshes and MultiMeshes (MODEL_MATRIX includes the instance).

uniform vec3 base_color : source_color = vec3(0.22, 0.34, 0.12);
uniform vec3 tip_color : source_color = vec3(0.55, 0.78, 0.3);
uniform float sway = 0.9;
uniform float speed = 0.8;
uniform vec3 current_dir = vec3(1.0, 0.0, 0.3);
uniform float glow = 0.12;

varying float hgt;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = UV.y;
	hgt = 1.0 - h;
	float k = hgt * hgt;
	float t = TIME * speed + origin.x * 0.13 + origin.z * 0.17;
	// leaves: widen the ribbon in lobes
	VERTEX.x *= 1.0 + 0.9 * max(0.0, sin(hgt * 38.0 + origin.x));
	vec3 bend = normalize(current_dir) * (sin(t) * 0.6 + 0.5) + vec3(-current_dir.z, 0.0, current_dir.x) * sin(t * 1.7 + 1.3) * 0.35;
	vec3 wbend = (inverse(mat3(MODEL_MATRIX)) * bend) * sway * k * 3.0;
	VERTEX += wbend;
}

void fragment() {
	vec3 col = mix(base_color, tip_color, hgt);
	float vein = smoothstep(0.08, 0.0, abs(UV.x - 0.5));
	col *= 0.85 + 0.25 * vein;
	ALBEDO = col;
	EMISSION = tip_color * glow * hgt;
	ROUGHNESS = 0.6;
	BACKLIGHT = tip_color * 0.35;
}
