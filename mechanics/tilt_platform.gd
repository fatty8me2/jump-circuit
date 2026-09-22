class_name TiltPlatform
extends Node3D
## Weight-reactive platform. A Jolt RigidBody3D (axis-locked, spring-centred,
## damped, hard-limited) does the real simulation: the player's weight is applied
## as a force at the contact point each tick and landings add an impulse.
## The player never touches that body directly - a kinematic surface mirrors its
## pose, so footing stays stable and carrying is reliable.
##
## World X/Z are the tilt axes. edge_tilt_deg is the resting tilt when the player
## stands at the very edge; max_tilt_deg is the hard stop.

@export var size: Vector3 = Vector3(8, 0.4, 2.4)
@export var tilt_about_x: bool = false
@export var tilt_about_z: bool = true
@export var edge_tilt_deg: float = 16.0
@export var max_tilt_deg: float = 24.0
## Metres the platform sinks under a standing player (0 = vertical motion locked).
@export var sink_depth: float = 0.0
@export var board_mass: float = 120.0
@export var damping_ratio: float = 0.55
@export var impact_scale: float = 0.35
## "fulcrum" draws a pivot stand below, "cables" hangs it from a frame above.
@export var support: String = "fulcrum"
@export var is_round: bool = false

const RIDER_WEIGHT: float = 70.0 * 42.0

var _sim: RigidBody3D
var _surface: TiltSurface
var _rest: Transform3D
var _inertia: Vector3
var _k: Vector3 = Vector3.ZERO      # angular spring per axis (x, -, z)
var _ky: float = 0.0
var _cables: Array[MeshInstance3D] = []
var _cable_anchor_y: float = 7.0


func _ready() -> void:
	add_to_group("resettable")
	_sim = RigidBody3D.new()
	_sim.collision_layer = 0
	_sim.collision_mask = 0
	_sim.mass = board_mass
	_sim.gravity_scale = 0.0
	_sim.can_sleep = false
	_sim.axis_lock_linear_x = true
	_sim.axis_lock_linear_z = true
	_sim.axis_lock_linear_y = sink_depth <= 0.0
	_sim.axis_lock_angular_y = true
	_sim.axis_lock_angular_x = not tilt_about_x
	_sim.axis_lock_angular_z = not tilt_about_z
	_sim.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var sim_shape := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = size
	sim_shape.shape = sb
	_sim.add_child(sim_shape)
	_inertia = Vector3(
		board_mass / 12.0 * (size.y * size.y + size.z * size.z),
		board_mass / 12.0 * (size.x * size.x + size.z * size.z),
		board_mass / 12.0 * (size.x * size.x + size.y * size.y))
	_sim.inertia = _inertia
	add_child(_sim)

	var edge: float = deg_to_rad(maxf(edge_tilt_deg, 1.0))
	_k.x = RIDER_WEIGHT * size.z * 0.5 / edge
	_k.z = RIDER_WEIGHT * size.x * 0.5 / edge
	if sink_depth > 0.0:
		_ky = RIDER_WEIGHT / sink_depth

	_surface = TiltSurface.new()
	_surface.owner_platform = self
	_surface.sync_to_physics = false
	_surface.collision_layer = 1
	_surface.collision_mask = 0
	var cs := CollisionShape3D.new()
	if is_round:
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x * 0.5
		cyl.height = size.y
		cs.shape = cyl
		_surface.add_child(Look.platform_round(size.x * 0.5, size.y, "tilt"))
	else:
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		_surface.add_child(Look.platform_box(size, "tilt"))
	_surface.add_child(cs)
	add_child(_surface)
	_rest = _sim.global_transform
	_build_support()


func _build_support() -> void:
	var metal: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.7)
	if support == "fulcrum":
		var post := Look.cylinder(0.32, 5.0, Look.flat(Look.c("side").darkened(0.15), 0.8), Vector3(0, -size.y * 0.5 - 2.8, 0), 0.22)
		add_child(post)
		var pm := PrismMesh.new()
		pm.size = Vector3(1.3, 0.75, minf(size.z, size.x) * 0.9)
		var wedge := Look.mesh_node(pm, metal, Vector3(0, -size.y * 0.5 - 0.4, 0))
		if tilt_about_x and not tilt_about_z:
			wedge.rotation.y = PI / 2.0
		add_child(wedge)
		add_child(Look.sphere(0.2, Look.flat(Look.c("accent"), 0.4, 0.2, 1.5), Vector3(0, -size.y * 0.5 - 0.05, 0)))
	elif support == "cables":
		var frame_mat: StandardMaterial3D = Look.flat(Look.c("decor"), 0.6, 0.4)
		add_child(Look.box(Vector3(size.x * 0.7, 0.3, 0.3), frame_mat, Vector3(0, _cable_anchor_y, 0)))
		add_child(Look.box(Vector3(0.3, 0.3, size.z * 0.7), frame_mat, Vector3(0, _cable_anchor_y, 0)))
		add_child(Look.cylinder(0.12, 30.0, frame_mat, Vector3(0, _cable_anchor_y + 15.0, 0)))
		var cable_mat: StandardMaterial3D = Look.flat(Color(0.12, 0.13, 0.16), 0.5, 0.6)
		for i: int in 4:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.035
			cm.bottom_radius = 0.035
			cm.height = 1.0
			cm.radial_segments = 6
			var cable := Look.mesh_node(cm, cable_mat)
			cable.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(cable)
			_cables.append(cable)


func _corner(i: int) -> Vector3:
	var sx: float = -1.0 if i % 2 == 0 else 1.0
	var sz: float = -1.0 if i < 2 else 1.0
	var inset: float = 0.85 if not is_round else 0.62
	return Vector3(sx * size.x * 0.5 * inset, size.y * 0.5, sz * size.z * 0.5 * inset)


func _process(_dt: float) -> void:
	if _cables.is_empty():
		return
	var xf: Transform3D = _surface.get_global_transform_interpolated()
	var inv: Transform3D = global_transform.affine_inverse()
	for i: int in 4:
		var a: Vector3 = inv * (xf * _corner(i))
		var b := Vector3(a.x * 0.45, _cable_anchor_y, a.z * 0.45)
		var mid: Vector3 = (a + b) * 0.5
		var dir: Vector3 = b - a
		var cable: MeshInstance3D = _cables[i]
		var up: Vector3 = dir.normalized()
		var side: Vector3 = up.cross(Vector3.FORWARD).normalized()
		cable.transform = Transform3D(Basis(side, up * dir.length(), side.cross(up)), mid)


func _physics_process(_dt: float) -> void:
	var b: Basis = _sim.global_basis
	var up: Vector3 = b.y
	var ang := Vector3(atan2(up.z, up.y), 0.0, -atan2(up.x, up.y))
	var w: Vector3 = _sim.angular_velocity
	var limit: float = deg_to_rad(max_tilt_deg)
	var torque := Vector3.ZERO
	for axis: int in [0, 2]:
		var k: float = _k[axis]
		var c: float = 2.0 * damping_ratio * sqrt(k * _inertia[axis])
		var tq: float = -k * ang[axis] - c * w[axis]
		var over: float = absf(ang[axis]) - limit
		if over > 0.0:
			# hard stop: very stiff, heavily damped
			tq += -signf(ang[axis]) * over * k * 40.0 - w[axis] * c * 3.0
		torque[axis] = tq
	_sim.apply_torque(torque)
	if sink_depth > 0.0:
		var dy: float = _sim.global_position.y - _rest.origin.y
		var cy: float = 2.0 * 0.6 * sqrt(_ky * board_mass)
		var f: float = -_ky * dy - cy * _sim.linear_velocity.y
		if dy < -sink_depth * 1.6:
			f += (-sink_depth * 1.6 - dy) * _ky * 30.0
		_sim.apply_central_force(Vector3(0, f, 0))
	_surface.global_transform = _sim.global_transform


# ---- called through the surface by Player ------------------------------------

func rider_load(point: Vector3, force: float) -> void:
	_sim.apply_force(Vector3(0, -force, 0), point - _sim.global_position)


func rider_impact(point: Vector3, impulse: float) -> void:
	_sim.apply_impulse(Vector3(0, -impulse * impact_scale, 0), point - _sim.global_position)
	Sfx.play_at("creak", point, 0.08, clampf(impulse / 900.0, 0.2, 1.0))


func tilt_degrees() -> Vector2:
	var up: Vector3 = _sim.global_basis.y
	return Vector2(rad_to_deg(atan2(up.z, up.y)), rad_to_deg(-atan2(up.x, up.y)))


func reset_state() -> void:
	var rid: RID = _sim.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, _rest)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	_sim.global_transform = _rest
	_surface.global_transform = _rest
	_surface.reset_physics_interpolation()
