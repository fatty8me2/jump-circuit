class_name Crusher
extends AnimatableBody3D
## A heavy press that hangs `lift` metres above the floor, shudders, slams down,
## holds and hauls itself back up - on a fixed rhythm (Game.course_time). Caught
## under it while it drops or rests = back to the checkpoint. Its top is solid
## and rideable (an elevator with a nasty underside). Positioned by the floor
## point under its centre; the block's bottom rests `lift` above it.
##   u 0.00-0.42 up   0.42-0.50 shudder   0.50-0.56 slam   0.56-0.72 down   0.72-1.00 rise

@export var size: Vector3 = Vector3(3, 2, 3)
@export var lift: float = 3.2
@export var period: float = 3.2
@export var phase: float = 0.0

const SHUDDER: float = 0.42
const SLAM: float = 0.50
const DOWN: float = 0.56
const RISE: float = 0.72

var _floor: Vector3
var _kill: Area3D
var _plate_mat: StandardMaterial3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_floor = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	add_child(Look.platform_box(size, "alt"))
	_plate_mat = Look.flat(Color(1.0, 0.2, 0.12), 0.4, 0.3, 0.4)
	add_child(Look.box(Vector3(size.x + 0.1, 0.25, size.z + 0.1), _plate_mat, Vector3(0, -size.y * 0.5 + 0.1, 0)))
	var tooth: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.24), 0.4, 0.8)
	for sx: float in [-0.3, 0.3]:
		for sz: float in [-0.3, 0.3]:
			add_child(Look.cylinder(0.18, 0.3, tooth, Vector3(sx * size.x, -size.y * 0.5 - 0.1, sz * size.z), 0.05, 8))
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var ks := BoxShape3D.new()
	ks.size = Vector3(size.x - 0.15, 0.9, size.z - 0.15)
	var kcs := CollisionShape3D.new()
	kcs.shape = ks
	_kill.add_child(kcs)
	# from 0.5 below the underside to 0.4 inside it: only a player it lands on can be in there
	_kill.position = Vector3(0, -size.y * 0.5 - 0.05, 0)
	add_child(_kill)
	position = _floor + Vector3(0, gap_at(Game.course_time) + size.y * 0.5, 0)
	reset_physics_interpolation()
	add_to_group("course_clock")


func snap_to_clock() -> void:
	position = _floor + Vector3(0, gap_at(Game.course_time) + size.y * 0.5, 0)
	reset_physics_interpolation()


## Height of the press's underside above the floor at `time`.
func gap_at(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	if u < SLAM:
		return lift
	if u < DOWN:
		var k: float = (u - SLAM) / (DOWN - SLAM)
		return lift * (1.0 - k * k)
	if u < RISE:
		return 0.0
	var r: float = (u - RISE) / (1.0 - RISE)
	return lift * r * r * (3.0 - 2.0 * r)


## True while it is safe to stand under it for the next `window` seconds.
func is_clear_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if _deadly(time + s):
			return false
		s += 0.05
	return true


func _deadly(time: float) -> bool:
	var u: float = fposmod(time / period + phase, 1.0)
	return u >= SLAM and u < RISE + 0.08


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var u: float = fposmod(t / period + phase, 1.0)
	var shake := Vector3.ZERO
	if u >= SHUDDER and u < SLAM:
		shake = Vector3(sin(t * 90.0) * 0.05, 0, cos(t * 77.0) * 0.05)
	position = _floor + Vector3(0, gap_at(t) + size.y * 0.5, 0) + shake
	var glow: float = 2.4 if (u >= SHUDDER and u < RISE) else 0.4
	if not is_equal_approx(_plate_mat.emission_energy_multiplier, glow):
		_plate_mat.emission_energy_multiplier = glow
	if not _deadly(t):
		return
	for body: Node3D in _kill.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return
