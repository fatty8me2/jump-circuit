class_name FrontierDoors
extends Node3D
## Wild West Heist: SALOON DOORS. A pair of batwing doors across a doorway that swing open and slap
## shut on a fixed rhythm (Game.course_time). Shut, they bar the way (solid). Just before they open
## they rattle on their hinges; open, the way is clear; and when they swing shut on you they bounce
## you straight back out of the doorway the way you came (+Z of the node), the classic heave-ho.
## The node sits on the floor in the middle of the doorway; local X runs across it.
##   cycle (s into the period): 0 shut .. shut_time - rattle: rattle .. swing open (SWING) .. open ..
##   swing shut (SWING) .. period

@export var width: float = 2.6
@export var leaf_bottom: float = 0.35
@export var leaf_top: float = 2.3
@export var period: float = 3.2
@export var phase: float = 0.0
@export var shut_time: float = 1.2
@export var rattle: float = 0.8
@export var throw: float = 9.0

const SWING: float = 0.22
const OPEN_DEG: float = 95.0

var _leaves: Array[Node3D] = []
var _block: CollisionShape3D
var _area: Area3D
var _cool: float = 0.0
var _was_open: bool = false
var _was_rattle: bool = false


func _ready() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(width, 3.2, 0.3)
	_block = CollisionShape3D.new()
	_block.shape = box
	_block.position = Vector3(0, 1.6, 0)
	body.add_child(_block)
	add_child(body)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var ab := BoxShape3D.new()
	ab.size = Vector3(width, 2.4, 1.6)
	var acs := CollisionShape3D.new()
	acs.shape = ab
	acs.position = Vector3(0, 1.2, 0)
	_area.add_child(acs)
	add_child(_area)
	_build()
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_open = not is_shut_at(Game.course_time)
	_apply(Game.course_time)


# ---- the rhythm --------------------------------------------------------------------------------------

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


## Shut (or nearly): the doorway is barred.
func is_shut_at(time: float) -> bool:
	return open_at(time) < 0.3


## The doors stay open (passable) for all of [time + a, time + b].
func is_open_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if open_at(time + s) < 0.95:
			return false
		s += 0.03
	return open_at(time + b) >= 0.95


func _swinging_shut(time: float) -> bool:
	var s: float = _s(time)
	return s >= period - SWING


# ---- gameplay ------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	var shut: bool = is_shut_at(t)
	if _block.disabled == shut:
		_block.set_deferred("disabled", not shut)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0 or not _swinging_shut(t):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var back: Vector3 = global_basis.z
			back.y = 0.0
			(body as Player).knockback(back.normalized() * throw + Vector3(0, 6.0, 0))
			_cool = 0.6
			# SOUND: the doors slapping you out of the saloon
			WorldAudio.at(self, "frontier_door_slap", global_position + Vector3(0, 1.2, 0), 1.0, 30.0)
			return


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var open: bool = not is_shut_at(t)
	if open != _was_open:
		_was_open = open
		# SOUND: the creak of the doors swinging open, the clack as they swing shut
		WorldAudio.at(self, "frontier_door_creak" if open else "frontier_door_clack", global_position + Vector3(0, 1.3, 0), 0.7, 30.0, 0.08)
	var s: float = _s(t)
	var rat: bool = s >= shut_time - rattle and s < shut_time
	if rat and not _was_rattle:
		WorldAudio.at(self, "frontier_door_rattle", global_position + Vector3(0, 1.3, 0), 0.5, 25.0, 0.06)
	_was_rattle = rat


func _apply(t: float) -> void:
	var k: float = open_at(t)
	var s: float = _s(t)
	var jig: float = 0.0
	if s >= shut_time - rattle and s < shut_time:
		jig = sin(s * 70.0) * deg_to_rad(5.0)
	for i: int in _leaves.size():
		var side: float = -1.0 if i == 0 else 1.0
		# both leaves swing away from you (toward -Z)
		_leaves[i].rotation.y = -side * (deg_to_rad(OPEN_DEG) * k + jig)


func _build() -> void:
	var wood: StandardMaterial3D = Look.flat(Color(0.55, 0.32, 0.16), 0.75)
	var dark: StandardMaterial3D = Look.flat(Color(0.3, 0.17, 0.09), 0.8)
	var brass: StandardMaterial3D = Look.flat(Color(0.95, 0.75, 0.32), 0.3, 0.8, 0.2)
	var h: float = leaf_top - leaf_bottom
	var w: float = width * 0.5 - 0.06
	for side: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side * width * 0.5, 0, 0)
		add_child(hinge)
		_leaves.append(hinge)
		var cx: float = -side * w * 0.5
		var leaf := Node3D.new()
		hinge.add_child(leaf)
		# frame, slats and the scalloped top rail of a batwing door
		leaf.add_child(Look.box(Vector3(w, 0.14, 0.08), dark, Vector3(cx, leaf_bottom + 0.07, 0)))
		leaf.add_child(Look.box(Vector3(w, 0.12, 0.08), dark, Vector3(cx, leaf_bottom + h * 0.62, 0)))
		for sx: float in [-1.0, 1.0]:
			leaf.add_child(Look.box(Vector3(0.12, h, 0.09), dark, Vector3(cx + sx * (w * 0.5 - 0.06), leaf_bottom + h * 0.5, 0)))
		var slats: int = 5
		for k: int in slats:
			var x: float = cx - w * 0.5 + 0.12 + (float(k) + 0.5) * (w - 0.24) / float(slats)
			leaf.add_child(Look.box(Vector3((w - 0.24) / float(slats) - 0.04, h * 0.55, 0.05), wood, Vector3(x, leaf_bottom + h * 0.35, 0)))
		var crown := Look.cylinder(w * 0.5, 0.07, wood, Vector3(cx, leaf_bottom + h * 0.68, 0), -1.0, 16)
		crown.rotation.x = PI * 0.5
		crown.scale = Vector3(1.0, 1.0, 0.55)
		leaf.add_child(crown)
		leaf.add_child(Look.sphere(0.06, brass, Vector3(cx + side * (w * 0.5 - 0.15), leaf_bottom + h * 0.45, 0.07)))
		for y: float in [leaf_bottom + 0.3, leaf_bottom + h - 0.3]:
			leaf.add_child(Look.cylinder(0.05, 0.22, brass, Vector3(side * -0.02, y, 0), -1.0, 8))
