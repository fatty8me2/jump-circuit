class_name SakuraBridge
extends Node3D
## Sakura Peaks: a SWAYING ROPE BRIDGE between two peaks. A plank deck slung on two hand ropes,
## sagging in the middle, built of short spans that each sway sideways on the course clock - a
## slow wave that runs along the bridge from end to end (strongest mid-span, still at the anchors).
## Some spans are broken out: jump them. Riders are carried with the deck (each span is a
## kinematic body; it never teleports). A pure function of Game.course_time.
## Node origin = the deck top at the near anchor; the bridge runs along local -Z for `length`,
## rising `rise` to the far anchor and sagging `sag` below the chord at mid-span.

@export var length: float = 60.0
@export var rise: float = 0.0
@export var sag: float = 3.0
@export var width: float = 2.0
@export var span_length: float = 3.0
## Indices of spans that are broken out (gaps to jump).
@export var gaps: Array[int] = []
@export var sway: float = 0.35
@export var period: float = 4.5
## Phase lag (cycles) from one end of the bridge to the other: the travelling wave.
@export var wave: float = 0.6

var _spans: Array[AnimatableBody3D] = []
var _span_k: Array[float] = []
var _rest: Array[Vector3] = []
var _count: int = 0


func _ready() -> void:
	_build()
	_apply(Game.course_time)
	add_to_group("course_clock")


## Deck height (local y) at fraction k (0 near anchor .. 1 far anchor).
func deck_y(k: float) -> float:
	return rise * k - sag * 4.0 * k * (1.0 - k)


## Local deck point (at rest, no sway) at fraction k.
func deck_local(k: float) -> Vector3:
	return Vector3(0, deck_y(k), -length * k)


## World deck point (at rest) at fraction k, nudged `up` above the planks.
func deck_point(k: float, up: float = 0.0) -> Vector3:
	return global_transform * (deck_local(k) + Vector3(0, up, 0))


## Fraction along the bridge of span i's middle.
func span_mid(i: int) -> float:
	return (float(i) + 0.5) / float(_count)


## Number of spans.
func span_count() -> int:
	return _count


## Sideways offset (local x) of the deck at fraction k and `time`.
func sway_at(time: float, k: float) -> float:
	return sway * sin(PI * clampf(k, 0.0, 1.0)) * sin(TAU * (time / maxf(period, 0.01) - wave * k))


func snap_to_clock() -> void:
	_apply(Game.course_time)
	for s: AnimatableBody3D in _spans:
		s.reset_physics_interpolation()


func _apply(time: float) -> void:
	for i: int in _spans.size():
		_spans[i].position = _rest[i] + Vector3(sway_at(time, _span_k[i]), 0, 0)


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _build() -> void:
	_count = maxi(int(ceil(length / span_length)), 1)
	var plank: StandardMaterial3D = SakuraDecor.mat(Color(0.5, 0.36, 0.24), 0.9)
	var plank2: StandardMaterial3D = SakuraDecor.mat(Color(0.44, 0.31, 0.2), 0.9)
	var rope_m: StandardMaterial3D = SakuraDecor.mat(Color(0.7, 0.58, 0.36), 0.9)
	var dark: StandardMaterial3D = SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.8)
	for i: int in _count:
		var k0: float = float(i) / float(_count)
		var k1: float = float(i + 1) / float(_count)
		var a: Vector3 = deck_local(k0)
		var b: Vector3 = deck_local(k1)
		if gaps.has(i):
			# a broken span: two splintered plank stubs hanging off each side of the gap
			var deco := Node3D.new()
			add_child(deco)
			for e: float in [0.0, 1.0]:
				var at: Vector3 = a.lerp(b, e)
				var stub := Look.box(Vector3(width * 0.4, 0.08, 0.9), plank2, at + Vector3(width * (0.2 if e < 0.5 else -0.25), -0.7, -0.3 if e < 0.5 else 0.3))
				stub.rotation.x = 1.2 if e < 0.5 else -1.1
				deco.add_child(stub)
			continue
		var mid: Vector3 = (a + b) * 0.5
		var d: Vector3 = b - a
		var len: float = d.length()
		var pitch: float = atan2(d.y, -d.z)
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, 0.25, len + 0.04)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, -0.125, 0)
		cs.rotation.x = pitch
		body.add_child(cs)
		# planks across the span with thin gaps, two stringers under them, the hand ropes on posts
		var vis := Node3D.new()
		vis.rotation.x = pitch
		body.add_child(vis)
		var n: int = maxi(int(len / 0.55), 2)
		for j: int in n:
			var z: float = -len * 0.5 + (float(j) + 0.5) * len / float(n)
			vis.add_child(Look.box(Vector3(width + (0.1 if j % 2 == 0 else -0.05), 0.16, len / float(n) - 0.06), plank if j % 3 != 1 else plank2, Vector3(0, -0.08, z)))
		for sx: float in [-1.0, 1.0]:
			vis.add_child(Look.box(Vector3(0.14, 0.14, len), dark, Vector3(sx * (width * 0.5 - 0.15), -0.25, 0)))
			vis.add_child(Look.cylinder(0.05, 1.05, dark, Vector3(sx * (width * 0.5 + 0.02), 0.45, -len * 0.5 + 0.1), -1.0, 6))
			var hr := Look.cylinder(0.035, len, rope_m, Vector3(sx * (width * 0.5 + 0.02), 0.95, 0), -1.0, 5)
			hr.rotation.x = PI * 0.5
			vis.add_child(hr)
		body.position = mid
		add_child(body)
		_spans.append(body)
		_span_k.append((k0 + k1) * 0.5)
		_rest.append(mid)
	# SOUND: ropes and planks creaking as the bridge sways (a loop from the middle of the span)
	var mid_node := Node3D.new()
	mid_node.position = deck_local(0.5)
	add_child(mid_node)
	WorldAudio.loop("sakura_bridge_creak", mid_node, -12.0, length * 0.5 + 10.0, 8.0)
	# the main cables from anchor to anchor (static, under the hand ropes) - visual only
	var prev_l: Vector3 = deck_local(0.0)
	for i: int in range(1, 13):
		var k: float = float(i) / 12.0
		var p: Vector3 = deck_local(k)
		for sx: float in [-1.0, 1.0]:
			var a2: Vector3 = prev_l + Vector3(sx * (width * 0.5 + 0.25), -0.3, 0)
			var b2: Vector3 = p + Vector3(sx * (width * 0.5 + 0.25), -0.3, 0)
			var dd: Vector3 = b2 - a2
			var c := Look.cylinder(0.06, dd.length(), rope_m, (a2 + b2) * 0.5, -1.0, 5)
			c.rotation.x = PI * 0.5 + atan2(dd.y, -dd.z)
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(c)
		prev_l = p
