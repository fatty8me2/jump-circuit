class_name FrontierVault
extends AnimatableBody3D
## Wild West Heist: the express car's VAULT DOOR. A round iron safe door on a hinge that swings open
## and slams shut on a fixed rhythm (Game.course_time). Behind it the vault (a warp portal) whisks you
## through the car. Shut, the door bars the way (solid); it unbolts with a clank and a turn of its
## wheel `warn` seconds before it swings, so the opening is always called. The node sits on the floor at
## the hinge side of the doorway; the door covers `width` metres toward +X when shut (local -Z faces you).
##   cycle (s into the period): 0 shut .. shut_time - warn: wheel turns .. shut_time: swings open (SWING)
##   .. open .. period - SWING: swings shut .. period

@export var width: float = 2.6
@export var height: float = 2.8
@export var period: float = 5.0
@export var phase: float = 0.0
@export var shut_time: float = 2.2
@export var warn: float = 0.8

const SWING: float = 0.35

var _leaf: Node3D
var _wheel: Node3D
var _shape: CollisionShape3D
var _was_open: bool = false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_leaf = Node3D.new()
	add_child(_leaf)
	var iron: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.22), 0.35, 0.8)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.78, 0.3), 0.25, 0.9, 0.3)
	var r: float = minf(width, height) * 0.5
	var disc := Look.cylinder(r, 0.36, iron, Vector3(width * 0.5, height * 0.5, 0), -1.0, 28)
	disc.rotation.x = PI * 0.5
	_leaf.add_child(disc)
	var rim := Look.cylinder(r * 1.04, 0.2, gold, Vector3(width * 0.5, height * 0.5, -0.1), -1.0, 28)
	rim.rotation.x = PI * 0.5
	_leaf.add_child(rim)
	_wheel = Node3D.new()
	_wheel.position = Vector3(width * 0.5, height * 0.5, -0.32)
	_leaf.add_child(_wheel)
	for k: int in 3:
		var spoke := Look.box(Vector3(r * 1.3, 0.1, 0.08), gold)
		spoke.rotation.z = PI * float(k) / 3.0
		_wheel.add_child(spoke)
	_wheel.add_child(Look.sphere(0.16, gold))
	for k2: int in 6:
		var a: float = TAU * float(k2) / 6.0
		_leaf.add_child(Look.sphere(0.07, gold, Vector3(width * 0.5 + cos(a) * r * 0.82, height * 0.5 + sin(a) * r * 0.82, -0.2)))
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.4)
	_shape = CollisionShape3D.new()
	_shape.shape = box
	_shape.position = Vector3(width * 0.5, height * 0.5, 0)
	add_child(_shape)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_open = not is_shut_at(Game.course_time)
	_apply(Game.course_time)


func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## 0 = shut, 1 = wide open.
func open_at(time: float) -> float:
	var s: float = _s(time)
	if s < shut_time:
		return 0.0
	if s < shut_time + SWING:
		return smoothstep(0.0, 1.0, (s - shut_time) / SWING)
	if s < period - SWING:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (s - (period - SWING)) / SWING)


func is_shut_at(time: float) -> bool:
	return open_at(time) < 0.5


## Wide open for all of [time + a, time + b].
func is_open_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if open_at(time + s) < 0.98:
			return false
		s += 0.03
	return open_at(time + b) >= 0.98


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var k: float = open_at(t)
	# the door swings out toward you (+Z side) on its hinge at local x = 0
	_leaf.rotation.y = -deg_to_rad(100.0) * k
	_shape.position = Vector3(width * 0.5, height * 0.5, 0).rotated(Vector3.UP, _leaf.rotation.y)
	_shape.rotation.y = _leaf.rotation.y
	if _shape.disabled != (k > 0.5):
		_shape.set_deferred("disabled", k > 0.5)
	var s: float = _s(t)
	if s >= shut_time - warn and s < shut_time:
		_wheel.rotation.z = (s - (shut_time - warn)) / warn * TAU * 0.75


func _process(_dt: float) -> void:
	var open: bool = not is_shut_at(Game.course_time)
	if open != _was_open:
		_was_open = open
		# SOUND: the bolts drawing back and the heavy door swinging, then the slam as it shuts
		WorldAudio.at(self, "frontier_vault_open" if open else "frontier_vault_slam", global_position + Vector3(width * 0.5, 1.4, 0), 0.9, 35.0)
