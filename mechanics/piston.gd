class_name Piston
extends AnimatableBody3D
## A ram that punches out of its housing along local -Z on a fixed rhythm
## (Game.course_time), holds, and pulls back slowly. Its striped face SHOVES a
## player it catches while extending (knockback along the stroke) - off a
## walkway, into a pit, or on purpose across a gap. Its top is solid ground that
## you can ride. Placed at the block's centre when fully retracted.
##   u 0.00-0.45 retracted   0.45-0.55 punch   0.55-0.80 held out   0.80-1.00 retract

@export var size: Vector3 = Vector3(3, 1.6, 2)
@export var stroke: float = 3.0
@export var period: float = 3.0
@export var phase: float = 0.0
## Shove speed on top of the stroke speed, and its lift.
@export var strength: float = 13.0
@export var lift: float = 5.0

const PUNCH_START: float = 0.45
const PUNCH_END: float = 0.55
const RETRACT_START: float = 0.8

var _origin: Vector3
var _face: Area3D
var _cool: float = 0.0


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	add_child(Look.platform_box(size, "mover"))
	# hazard-striped push face
	var stripe_a: StandardMaterial3D = Look.flat(Color(1.0, 0.72, 0.1), 0.5, 0.1, 0.6)
	var stripe_b: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.14), 0.6, 0.2)
	var n: int = maxi(int(size.x / 0.5), 2)
	for i: int in n:
		var w: float = size.x / float(n)
		var bar := Look.box(Vector3(w, size.y - 0.1, 0.06), stripe_a if i % 2 == 0 else stripe_b, Vector3(-size.x * 0.5 + (float(i) + 0.5) * w, 0, -size.z * 0.5 - 0.03))
		add_child(bar)
	# the rod back into the housing
	var rod := Look.cylinder(minf(size.y, size.x) * 0.2, stroke + 0.2, Look.flat(Color(0.75, 0.78, 0.82), 0.25, 0.9), Vector3(0, 0, size.z * 0.5 + (stroke + 0.2) * 0.5))
	rod.rotation.x = PI * 0.5
	add_child(rod)
	_face = Area3D.new()
	_face.collision_layer = 0
	_face.collision_mask = 2
	_face.monitorable = false
	var fs := BoxShape3D.new()
	fs.size = Vector3(size.x + 0.2, maxf(size.y - 0.25, 0.3), 0.7)
	var fcs := CollisionShape3D.new()
	fcs.shape = fs
	_face.add_child(fcs)
	_face.position = Vector3(0, -0.12, -size.z * 0.5 - 0.3)
	add_child(_face)
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func snap_to_clock() -> void:
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()


## 0 (retracted) .. 1 (fully out) at `time`.
func extension_at(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	if u < PUNCH_START:
		return 0.0
	if u < PUNCH_END:
		var k: float = (u - PUNCH_START) / (PUNCH_END - PUNCH_START)
		return k * k
	if u < RETRACT_START:
		return 1.0
	var r: float = (u - RETRACT_START) / (1.0 - RETRACT_START)
	return 1.0 - r * r * (3.0 - 2.0 * r)


func is_punching_at(time: float) -> bool:
	var u: float = fposmod(time / period + phase, 1.0)
	return u >= PUNCH_START and u < PUNCH_END


func offset_at(time: float) -> Vector3:
	return transform.basis * Vector3(0, 0, -stroke * extension_at(time))


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	position = _origin + offset_at(t)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0 or not is_punching_at(t):
		return
	for body: Node3D in _face.get_overlapping_bodies():
		if body is Player:
			var dir: Vector3 = -global_basis.z
			dir.y = 0.0
			var ram_speed: float = stroke / ((PUNCH_END - PUNCH_START) * period)
			(body as Player).knockback(dir.normalized() * (ram_speed + strength) + Vector3(0, lift, 0))
			_cool = 0.4
			Sfx.play_at("whack", global_position, 0.08, 1.0)
