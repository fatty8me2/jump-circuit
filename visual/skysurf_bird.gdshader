shader_type spatial;
// Sky Surf: a flock of birds wheeling over a point. One MultiMesh, no per-frame script: each instance
// sits at its flock's centre (its transform) and INSTANCE_CUSTOM carries (phase, radius, speed, height),
// so the shader flies it round a circle with a gentle bob, turns it along its path and flaps its wings.
// The mesh is a flat "V": x is the span, -z the nose. Unshaded, double sided, bounded.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.92);
uniform float flap_rate = 9.0;

varying vec3 shade;

void vertex() {
	float a = INSTANCE_CUSTOM.x + TIME * INSTANCE_CUSTOM.z;
	float r = INSTANCE_CUSTOM.y;
	float turn = sign(INSTANCE_CUSTOM.z + 0.0001);
	vec3 off = vec3(cos(a) * r, INSTANCE_CUSTOM.w + sin(a * 2.3) * 1.2, sin(a) * r);
	// the heading along the circle (the tangent), and a bank into the turn
	vec3 fwd = vec3(-sin(a), 0.0, cos(a)) * turn;
	vec3 side = vec3(fwd.z, 0.0, -fwd.x);
	vec3 upv = vec3(0.0, 1.0, 0.0);
	float flap = sin(TIME * flap_rate + INSTANCE_CUSTOM.x * 5.0);
	vec3 v = VERTEX;
	v.y += abs(v.x) * flap * 0.55;
	// local -z is the nose, so map -z onto the heading
	vec3 world_off = side * v.x + upv * v.y - fwd * v.z;
	// (the instance transform is a pure translation to the flock's centre, so model space is world space)
	VERTEX = off + world_off;
	shade = tint * (0.82 + 0.18 * flap);
}

void fragment() {
	ALBEDO = shade;
}
