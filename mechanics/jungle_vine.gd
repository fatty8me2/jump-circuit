class_name JungleVine
extends MovingPlatform
## Jungle Temple: a vine swing - a lashed-log seat hung on two thick lianas from a branch,
## swinging across a gap on the course clock (a pendulum: angle = swing_deg * sin(2 pi (t / period
## + phase))). The seat stays level; ride it out to the far end of its arc, where it all but stops,
## and step off. A MovingPlatform, so a rider is carried with its full velocity and the route bot
## can ask where it WILL be (offset_at). Positioned like kit.mover: the centre of the seat's
## collision box at the BOTTOM of its arc.

## Vine length (m) from the branch to the seat.
@export var rope: float = 8.0
@export var swing_deg: float = 38.0
## Horizontal direction of the swing (world); the seat reaches +dir at angle +swing_deg.
@export var swing_dir: Vector3 = Vector3(0, 0, -1)

const BARK := Color(0.36, 0.25, 0.16)
const LIANA := Color(0.24, 0.32, 0.14)
const LEAF := Color(0.22, 0.48, 0.16)

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
	_build_seat()
	_build_rig()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func _hums() -> bool:
	return false


## Three logs side by side across the swing, lashed with vine, a jade bead on each lashing so the
## ride reads at a glance; flat-topped enough to stand on (the collision is the box).
func _build_seat() -> void:
	var across: Vector3 = Vector3.UP.cross(swing_dir).normalized()
	var width: float = absf(size.dot(across.abs()))
	var along: float = absf(size.dot(swing_dir.abs()))
	var bark: StandardMaterial3D = Look.flat(BARK, 0.92)
	var r: float = along / 6.0
	for i: int in 3:
		var piece := Look.cylinder(r, width, bark, swing_dir * (float(i) - 1.0) * r * 2.0 + Vector3(0, size.y * 0.5 - r, 0), -1.0, 10)
		piece.basis = _lay(across)
		add_child(piece)
	# the lashings and the jade beads
	var lash: StandardMaterial3D = Look.flat(LIANA, 0.9)
	var jade: StandardMaterial3D = Look.flat(Color(0.25, 0.95, 0.65), 0.3, 0.0, 1.6)
	for s: float in [-1.0, 1.0]:
		var band := Look.box(across * 0.12 + Vector3(0, size.y * 0.8, 0) + swing_dir.abs() * along * 1.02, lash, across * s * (width * 0.5 - 0.3))
		add_child(band)
		add_child(Look.sphere(0.1, jade, across * s * (width * 0.5 - 0.3) + Vector3(0, size.y * 0.5 + 0.05, 0)))


## A basis that lays a (Y-up) cylinder along `axis`.
static func _lay(axis: Vector3) -> Basis:
	var y: Vector3 = axis.normalized()
	var x: Vector3 = y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


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
	# a creak of the branch at each end of the arc
	var k: int = int(floor((Game.course_time / period + phase) * 2.0 + 0.5))
	if k != _creaked:
		_creaked = k
		WorldAudio.at(self, "jungle_vine_creak", global_position + Vector3.UP * rope, 0.5, 24.0)


## The two lianas hang from the branch and turn with the swing (a visual on its own node), with
## leaves sprouting along them and a knot of roots round the branch at the top.
func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.top_level = true
	add_child(_rig)
	var vine: StandardMaterial3D = Look.flat(LIANA, 0.9)
	var leaf: StandardMaterial3D = Look.flat(LEAF, 0.85)
	var side: Vector3 = Vector3.UP.cross(swing_dir).normalized()
	var width: float = absf(size.dot(side.abs()))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(_origin))
	for s: float in [-1.0, 1.0]:
		var x: Vector3 = side * s * (width * 0.5 - 0.3)
		_rig.add_child(Look.cylinder(0.075, rope, vine, x + Vector3(0, -rope * 0.5 + size.y * 0.5, 0), 0.06, 6))
		var n: int = int(rope / 1.3)
		for i: int in n:
			var y: float = -rope + size.y + 0.8 + float(i) * (rope - 1.2) / float(maxi(n, 1))
			var lf := Look.box(Vector3(0.36, 0.03, 0.18), leaf, x + Vector3(rng.randf_range(-0.12, 0.12), y, rng.randf_range(-0.12, 0.12)))
			lf.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
			_rig.add_child(lf)
	# the knot round the branch
	_rig.add_child(Look.sphere(0.4, Look.flat(BARK.darkened(0.2), 0.95)))
	_pose_rig(Game.course_time)


func _pose_rig(t: float) -> void:
	if _rig == null:
		return
	var pivot: Vector3 = get_parent().global_transform * (_origin + Vector3.UP * rope) if get_parent() is Node3D else _origin + Vector3.UP * rope
	var axis: Vector3 = Vector3.UP.cross(swing_dir).normalized()
	# positive angle swings the seat toward +swing_dir: a rotation about (dir x up) = -axis
	_rig.global_transform = Transform3D(Basis(-axis, angle_at(t)), pivot)
