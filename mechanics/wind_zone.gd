class_name WindZone
extends Area3D
## Box of moving air: constant acceleration on the player while inside
## (updraft columns, cross-winds over narrow beams, tail-wind tunnels).

@export var size: Vector3 = Vector3(4, 8, 4)
@export var push: Vector3 = Vector3(0, 60, 0)
## Vertical speed an updraft will not push past (keeps columns controllable).
@export var max_rise: float = 14.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	# streaks enter at the upwind face, run with the wind and fade out at the downwind
	# face (every level push is axis-aligned, so the box's extent along the wind is its span)
	var along: Vector3 = push.normalized()
	var axis: Vector3 = along.abs()
	var span: float = maxf(absf(size.dot(axis)), 0.5)
	var p := GPUParticles3D.new()
	p.amount = int(clampf(size.x * size.y * size.z * 0.35, 16, 90))
	p.lifetime = maxf(span / 8.0, 0.3)  # 8 = initial_velocity_max: no streak leaves the box
	p.preprocess = p.lifetime
	p.local_coords = true
	p.visibility_aabb = AABB(-size, size * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5 * (Vector3.ONE - axis) + axis * 0.1
	pm.emission_shape_offset = -along * span * 0.5
	pm.direction = along
	pm.spread = 3.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.particle_flag_align_y = true  # the streak's long (Y) axis follows its velocity
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var m := BoxMesh.new()
	m.size = Vector3(0.05, 0.9, 0.05)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true  # needed for the fade ramp to reach the pixels
	qm.albedo_color = Color(0.92, 0.97, 1.0, 0.5)
	m.material = qm  # no billboard: a thin box reads along the wind from any angle
	p.draw_pass_1 = m
	add_child(p)
	_build_motes(along, axis, span)


## Soft motes tumbling along with the streaks, on turbulent paths (visual only).
func _build_motes(along: Vector3, axis: Vector3, span: float) -> void:
	var life: float = maxf(span / 5.0, 0.4)
	var motes: GPUParticles3D = Fx.emitter({"amount": int(clampf(size.x * size.y * size.z * 0.08, 6, 30)),
		"lifetime": life, "preprocess": life, "local": true, "shape": "box",
		"extents": size * 0.5 * (Vector3.ONE - axis) + axis * 0.1, "offset": -along * span * 0.5,
		"dir": along, "spread": 6.0, "speed": Vector2(4.0, 5.0), "turbulence": 1.2, "turbulence_scale": 3.0,
		"tex": Fx.Tex.DOT, "size": 0.16, "scale": Vector2(0.5, 1.0),
		"fade": PackedFloat32Array([0.0, 0.8, 0.8, 0.0]), "color": Color(1.6, 1.8, 2.0, 0.7),
		"aabb": AABB(-size, size * 2.0)})
	add_child(motes)


func _physics_process(dt: float) -> void:
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var dv: Vector3 = global_basis * push * dt
			if dv.y > 0.0 and p.velocity.y > max_rise:
				dv.y = 0.0
			p.add_impulse(dv)
