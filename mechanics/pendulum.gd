class_name Pendulum
extends Node3D
## Swinging hammer. It does not kill: it HITS - the player is thrown along the
## swing at the head speed plus a kick. Deterministic from Game.course_time.
## Swings side to side along local X (rotate the node to re-aim it).

@export var length: float = 7.0
@export var swing_deg: float = 55.0
@export var period: float = 3.2
@export var phase: float = 0.0
@export var head_radius: float = 1.1
@export var kick: float = 9.0

var _arm: Node3D
var _area: Area3D
var _cool: float = 0.0


func _ready() -> void:
	_arm = Node3D.new()
	add_child(_arm)
	var metal: StandardMaterial3D = Look.flat(Color(0.2, 0.21, 0.27), 0.35, 0.8)
	_arm.add_child(Look.cylinder(0.12, length, metal, Vector3(0, -length * 0.5, 0), -1.0, 10))
	var head := Look.cylinder(head_radius, head_radius * 1.5, Look.flat(Color(0.9, 0.25, 0.2), 0.4, 0.4, 0.6), Vector3(0, -length, 0), -1.0, 20)
	head.rotation.z = PI / 2.0
	_arm.add_child(head)
	add_child(Look.sphere(0.35, metal))
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var s := SphereShape3D.new()
	s.radius = head_radius * 1.05
	var cs := CollisionShape3D.new()
	cs.shape = s
	_area.add_child(cs)
	_area.position = Vector3(0, -length, 0)
	_arm.add_child(_area)
	_apply(Game.course_time)
	add_to_group("course_clock")


## restart_run() winds the clock back in place: take the new pose now, without a streak.
func snap_to_clock() -> void:
	_apply(Game.course_time)
	reset_physics_interpolation()


func angle_at(time: float) -> float:
	return deg_to_rad(swing_deg) * sin(TAU * (time / period + phase))


func _apply(time: float) -> void:
	_arm.rotation.z = angle_at(time)


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var w: float = deg_to_rad(swing_deg) * cos(TAU * (t / period + phase)) * TAU / period
			var tangent: Vector3 = global_basis * (Basis(Vector3.BACK, angle_at(t)) * Vector3.RIGHT)
			var dir: Vector3 = tangent * signf(w)
			if absf(w) < 0.05:
				dir = (body.global_position - _area.global_position).normalized()
			var p := body as Player
			p.knockback(dir * (absf(w) * length + kick) + Vector3(0, 7.0, 0))
			_cool = 0.5
			Sfx.play_at("whack", _area.global_position, 0.08, 1.0)
