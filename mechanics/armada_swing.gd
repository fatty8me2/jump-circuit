class_name ArmadaSwing
extends MovingPlatform
## Storm Armada: a rope swing - a plank seat hung on two ropes from a yardarm, swinging across
## a gap on the course clock (a pendulum: angle = swing_deg * sin(2 pi (t / period + phase))).
## The plank stays level; ride it out to the far end of its arc (where it all but stops) and step
## off. A MovingPlatform, so the route bot can ask where it WILL be (offset_at).
## Positioned like kit.mover: the centre of the plank's collision box at the BOTTOM of its arc.

## Rope length (m) from the pivot to the plank.
@export var rope: float = 8.0
@export var swing_deg: float = 38.0
## Horizontal direction of the swing (world); the plank reaches +dir at angle +swing_deg.
@export var swing_dir: Vector3 = Vector3(0, 0, -1)

var _rig: Node3D
var _creaked: int = 0


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	swing_dir = Vector3(swing_dir.x, 0.0, swing_dir.z).normalized()
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	add_child(Look.platform_box(size, style))
	# iron straps round the plank ends
	var iron: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.22), 0.4, 0.8)
	var across: Vector3 = Vector3.UP.cross(swing_dir).abs()
	var width: float = size.dot(across)
	var along: float = size.dot(swing_dir.abs())
	for s: float in [-1.0, 1.0]:
		var sz: Vector3 = across * 0.08 + Vector3(0, size.y + 0.06, 0) + swing_dir.abs() * along * 0.9
		add_child(Look.box(sz, iron, across * s * (width * 0.5 - 0.25)))
	_build_rig()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func angle_at(time: float) -> float:
	return deg_to_rad(swing_deg) * sin(TAU * (time / maxf(period, 0.01) + phase))


func offset_at(time: float) -> Vector3:
	var a: float = angle_at(time)
	return swing_dir * rope * sin(a) + Vector3.UP * rope * (1.0 - cos(a))


func snap_to_clock() -> void:
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	_pose_rig(Game.course_time)


func _process(_dt: float) -> void:
	_pose_rig(Game.course_time)
	# a creak at each end of the arc
	var k: int = int(floor((Game.course_time / period + phase) * 2.0 + 0.5))
	if k != _creaked:
		_creaked = k
		WorldAudio.at(self, "armada_swing_creak", global_position, 0.5, 22.0)


## The two ropes hang from the pivot and turn with the swing (a visual on its own node).
func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.top_level = true
	add_child(_rig)
	var rope_mat: StandardMaterial3D = Look.flat(Color(0.6, 0.48, 0.32), 0.9)
	var side: Vector3 = Vector3.UP.cross(swing_dir).normalized()
	var width: float = size.dot(side.abs())
	for s: float in [-1.0, 1.0]:
		var r := Look.cylinder(0.045, rope, rope_mat, side * s * (width * 0.5 - 0.25) + Vector3(0, -rope * 0.5 + size.y * 0.5, 0), -1.0, 6)
		_rig.add_child(r)
	# a brass pulley block at the pivot
	_rig.add_child(Look.sphere(0.22, Look.flat(Color(0.86, 0.63, 0.3), 0.3, 0.9)))
	_pose_rig(Game.course_time)


func _pose_rig(t: float) -> void:
	if _rig == null:
		return
	var pivot: Vector3 = get_parent().global_transform * (_origin + Vector3.UP * rope) if get_parent() is Node3D else _origin + Vector3.UP * rope
	var axis: Vector3 = Vector3.UP.cross(swing_dir).normalized()
	# positive angle swings the plank toward +swing_dir: a rotation about (dir x up) = -axis
	_rig.global_transform = Transform3D(Basis(-axis, angle_at(t)), pivot)
