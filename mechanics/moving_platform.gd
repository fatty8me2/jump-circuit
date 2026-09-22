class_name MovingPlatform
extends AnimatableBody3D
## Kinematic platform whose pose is a pure function of Game.course_time, so the
## pattern is perfectly repeatable, needs no reset, and is identical for every
## racer in multiplayer.
##  PATH : eases back and forth through `points` (offsets from the start position)
##  ORBIT: circles `orbit_center_offset` staying upright (ferris-wheel gondola)

enum Mode { PATH, ORBIT }

@export var mode: Mode = Mode.PATH
@export var size: Vector3 = Vector3(3, 0.5, 3)
@export var points: Array[Vector3] = [Vector3.ZERO, Vector3(6, 0, 0)]
## Seconds for a full cycle (there and back / one revolution).
@export var period: float = 6.0
## 0..1 fraction of the cycle this platform starts at.
@export var phase: float = 0.0
## Fraction of each leg spent paused at the ends (PATH only).
@export var dwell: float = 0.12
@export var orbit_radius: float = 4.0
@export var orbit_axis: Vector3 = Vector3.FORWARD
@export var style: String = "mover"
@export var is_round: bool = false

var _origin: Vector3


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var cs := CollisionShape3D.new()
	if is_round:
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x * 0.5
		cyl.height = size.y
		cs.shape = cyl
		add_child(Look.platform_round(size.x * 0.5, size.y, style))
	else:
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		add_child(Look.platform_box(size, style))
	add_child(cs)
	# small thruster pods so it reads as "this one moves"
	var pod_mat: StandardMaterial3D = Look.flat(Look.c("accent2"), 0.4, 0.0, 2.2)
	for sx: int in [-1, 1]:
		var pod := Look.cylinder(0.16, 0.22, pod_mat, Vector3(sx * size.x * 0.32, -size.y * 0.5 - 0.1, 0), 0.24, 12)
		add_child(pod)
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()


func offset_at(time: float) -> Vector3:
	var u: float = fposmod(time / maxf(period, 0.01) + phase, 1.0)
	if mode == Mode.ORBIT:
		var axis: Vector3 = orbit_axis.normalized()
		var ref: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var arm: Vector3 = axis.cross(ref).normalized()
		return arm.rotated(axis, u * TAU) * orbit_radius
	if points.size() < 2:
		return Vector3.ZERO
	# ping-pong across all legs
	var legs: int = points.size() - 1
	var tri: float = 1.0 - absf(u * 2.0 - 1.0)      # 0..1..0
	var f: float = tri * float(legs)
	var leg: int = mini(int(f), legs - 1)
	var k: float = f - float(leg)
	k = clampf((k - dwell) / maxf(1.0 - 2.0 * dwell, 0.01), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return points[leg].lerp(points[leg + 1], k)


func _physics_process(_dt: float) -> void:
	position = _origin + offset_at(Game.course_time)
