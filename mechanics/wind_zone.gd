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
	var p := GPUParticles3D.new()
	p.amount = int(clampf(size.x * size.y * size.z * 0.35, 16, 90))
	p.lifetime = 1.1
	p.preprocess = 1.1
	p.local_coords = true
	p.visibility_aabb = AABB(-size, size * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5
	pm.direction = push.normalized()
	pm.spread = 3.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.9)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(1, 1, 1, 0.35)
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = qm
	p.draw_pass_1 = q
	add_child(p)


func _physics_process(dt: float) -> void:
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var dv: Vector3 = global_basis * push * dt
			if dv.y > 0.0 and p.velocity.y > max_rise:
				dv.y = 0.0
			p.add_impulse(dv)
