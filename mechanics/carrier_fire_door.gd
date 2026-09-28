class_name CarrierFireDoor
extends Node3D
## Super Carrier: a hangar DIVISIONAL FIRE DOOR. Two towering steel leaves slide in from both sides
## on a fixed rhythm (Game.course_time), close the bay off, hold, and slide open again. You pass
## through the gap while it is open; caught in the seam as they meet, you are crushed. Readable:
## the lamps over the doorway turn from green to flashing red `warn` seconds before the leaves move,
## a klaxon sounds, and the leading edges carry yellow-and-black bands. The node sits on the floor
## line at the middle of the doorway; the leaves slide along local X, the passage runs along Z.
##   cycle (s into the period): open .. `warn` warning .. closing (MOVE s) .. closed (hold) .. opening

## Width of the whole doorway (each leaf is half of it), its height, the leaf thickness.
@export var width: float = 34.0
@export var height: float = 15.0
@export var thickness: float = 1.2
## Gap left between the leaves when open.
@export var open_gap: float = 4.0
@export var period: float = 7.0
@export var phase: float = 0.0
## Seconds held open / closed.
@export var open_time: float = 3.6
@export var warn: float = 1.2

const MOVE: float = 0.9
const YELLOW := Color(1.0, 0.8, 0.12)

var _leaves: Array[AnimatableBody3D] = []
var _kill: Area3D
var _lamps: Array[MeshInstance3D] = []
var _green: StandardMaterial3D
var _red: StandardMaterial3D
var _red_off: StandardMaterial3D
var _dust: GPUParticles3D
var _was_moving: bool = false
var _was_warn: bool = false


func _ready() -> void:
	_build()
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_apply(Game.course_time)
	for l: AnimatableBody3D in _leaves:
		l.reset_physics_interpolation()


func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## Gap between the leaves at `time` (open_gap .. 0).
func gap_at(time: float) -> float:
	var s: float = _s(time)
	var closed_time: float = period - open_time - 2.0 * MOVE
	if s < open_time:
		return open_gap
	if s < open_time + MOVE:
		var k: float = (s - open_time) / MOVE
		return open_gap * (1.0 - k * k)
	if s < open_time + MOVE + closed_time:
		return 0.0
	var r: float = (s - open_time - MOVE - closed_time) / MOVE
	return open_gap * r * r * (3.0 - 2.0 * r)


## The doorway stays at least `min_gap` wide over [time + a, time + b].
func is_open_for(time: float, a: float, b: float, min_gap: float = 0.0) -> bool:
	var need: float = open_gap * 0.95 if min_gap <= 0.0 else min_gap
	var s: float = a
	while s <= b:
		if gap_at(time + s) < need:
			return false
		s += 0.04
	return true


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if gap_at(t) > 1.3:
		return
	for body: Node3D in _kill.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return


func _apply(t: float) -> void:
	var g: float = gap_at(t)
	var leaf_w: float = (width - open_gap) * 0.5
	for i: int in 2:
		var sx: float = -1.0 if i == 0 else 1.0
		_leaves[i].position = Vector3(sx * (g * 0.5 + leaf_w * 0.5), height * 0.5, 0)
	var s: float = _s(t)
	var warning: bool = s >= open_time - warn and s < open_time
	var moving: bool = g > 0.0 and g < open_gap
	var shut: bool = g <= 0.0 or (moving and not (s >= open_time + MOVE))
	var flash: bool = fposmod(t * 3.0, 1.0) < 0.5
	for l: MeshInstance3D in _lamps:
		if warning or shut or moving:
			l.material_override = _red if (flash or shut) else _red_off
		else:
			l.material_override = _green
	if moving and not _was_moving:
		_dust.restart()
		WorldAudio.at(self, "carrier_door_grind", global_position + Vector3(0, 3, 0), 1.0, 60.0)
	if warning and not _was_warn:
		WorldAudio.at(self, "carrier_door_klaxon", global_position + Vector3(0, height * 0.6, 0), 0.9, 60.0)
	_was_moving = moving
	_was_warn = warning


func _build() -> void:
	var leaf_w: float = (width - open_gap) * 0.5
	var steel: StandardMaterial3D = Look.flat(Color(0.5, 0.53, 0.56), 0.6, 0.45)
	var rib: StandardMaterial3D = Look.flat(Color(0.4, 0.43, 0.46), 0.6, 0.5)
	var ya: StandardMaterial3D = Look.flat(YELLOW, 0.6, 0.0, 0.2)
	var yb: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.08), 0.7)
	for i: int in 2:
		var sx: float = -1.0 if i == 0 else 1.0
		var leaf := AnimatableBody3D.new()
		leaf.sync_to_physics = false
		leaf.collision_layer = 1
		leaf.collision_mask = 0
		var bs := BoxShape3D.new()
		bs.size = Vector3(leaf_w, height, thickness)
		var cs := CollisionShape3D.new()
		cs.shape = bs
		leaf.add_child(cs)
		leaf.add_child(Look.box(Vector3(leaf_w, height, thickness), steel))
		# stiffening ribs on both faces
		var nr: int = int(height / 2.5)
		for k: int in nr:
			for fz: float in [-1.0, 1.0]:
				leaf.add_child(Look.box(Vector3(leaf_w - 0.4, 0.3, 0.16), rib, Vector3(0, -height * 0.5 + 1.25 + float(k) * 2.5, fz * (thickness * 0.5 + 0.08))))
		# hazard bands down the leading edge
		var nb: int = int(height / 1.0)
		for k: int in nb:
			var band := Look.box(Vector3(0.5, height / float(nb), thickness + 0.06), ya if k % 2 == 0 else yb,
				Vector3(-sx * (leaf_w * 0.5 - 0.25), -height * 0.5 + (float(k) + 0.5) * height / float(nb), 0))
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			leaf.add_child(band)
		add_child(leaf)
		_leaves.append(leaf)
	# the overhead track and the lamps over the doorway
	add_child(Look.box(Vector3(width + 2.0, 1.0, thickness + 1.0), Look.flat(Color(0.3, 0.32, 0.34), 0.6, 0.5), Vector3(0, height + 0.5, 0)))
	_green = Look.flat(Color(0.2, 1.0, 0.35), 0.3, 0.0, 2.4)
	_red = Look.flat(Color(1.0, 0.15, 0.1), 0.3, 0.0, 3.0)
	_red_off = Look.flat(Color(0.4, 0.06, 0.05), 0.4, 0.0, 0.2)
	for fz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var lamp := Look.sphere(0.3, _green, Vector3(sx * (open_gap * 0.5 + 1.2), height - 0.6, fz * (thickness * 0.5 + 0.4)))
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(lamp)
			_lamps.append(lamp)
	# the seam where the leaves meet: deadly while they close on it
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var ks := BoxShape3D.new()
	ks.size = Vector3(1.1, height, thickness + 0.4)
	var kcs := CollisionShape3D.new()
	kcs.shape = ks
	_kill.add_child(kcs)
	_kill.position = Vector3(0, height * 0.5, 0)
	add_child(_kill)
	_dust = Fx.smoke({"amount": 30, "lifetime": 1.2, "shape": "box", "extents": Vector3(open_gap * 0.5, height * 0.4, 0.4),
		"offset": Vector3(0, height * 0.5, 0), "dir": Vector3(0, -0.3, 1), "spread": 90.0, "speed": Vector2(1.0, 3.0),
		"size": 1.6, "color": Color(0.8, 0.8, 0.78, 0.35),
		"aabb": AABB(Vector3(-width * 0.5, -2, -8), Vector3(width, height + 6, 16))})
	add_child(_dust)
