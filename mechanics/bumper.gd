class_name Bumper
extends Area3D
## Pinball bumper post: touching it throws you directly away at a fixed speed
## with a little lift. Same contact, same result - routes can be built on it.

@export var radius: float = 0.9
@export var height: float = 1.6
@export var strength: float = 16.0
@export var lift: float = 8.0

var _cool: float = 0.0
var _vis: Node3D
var _pulse: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius + 0.15
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	add_child(cs)
	_vis = Node3D.new()
	add_child(_vis)
	var cap: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.18), 0.4, 0.6)
	_vis.add_child(Look.cylinder(radius, height, Look.flat(Color(0.95, 0.3, 0.75), 0.35, 0.2, 1.2), Vector3(0, height * 0.5, 0), radius * 0.85, 20))
	_vis.add_child(Look.cylinder(radius * 1.15, 0.2, cap, Vector3(0, height + 0.1, 0), -1.0, 20))
	_vis.add_child(Look.cylinder(radius * 1.15, 0.2, cap, Vector3(0, 0.1, 0), -1.0, 20))


func _physics_process(dt: float) -> void:
	_cool = maxf(_cool - dt, 0.0)
	_pulse = maxf(_pulse - dt * 4.0, 0.0)
	_vis.scale = Vector3(1.0 + _pulse * 0.25, 1.0, 1.0 + _pulse * 0.25)
	if _cool > 0.0:
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var away: Vector3 = p.global_position - global_position
			away.y = 0.0
			if away.length() < 0.05:
				away = Vector3.FORWARD
			p.velocity = away.normalized() * strength + Vector3(0, lift, 0)
			p.add_impulse(Vector3(0, 0.01, 0))
			_cool = 0.25
			_pulse = 1.0
			Sfx.play_at("bounce", global_position, 0.05, 0.9)
