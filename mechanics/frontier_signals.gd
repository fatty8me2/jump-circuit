class_name FrontierSignals
extends Node3D
## Wild West Heist: SIGNAL ARMS sweeping the car roofs. The train never moves (the world scrolls
## past it, see visual/frontier_scroll.gd), so a trackside signal post comes up out of the canyon far
## ahead and slides back along the train at the scenery's speed. Each post carries a long striped
## arm. Out ahead the arm stands up; as the post nears the stretch of roofs this line guards (the
## window) its lamps start blinking, its bell rings and the arm swings down level across the train
## ahead of the window, so a lowered arm is always seen coming. While it is down the arm sweeps
## back over the roofs at `arm_y`. A LOW arm (a knee-high bar, `lethal` off) only trips you: it
## bumps you up off your feet and your run is gone (a missed hop costs time, not a life). A HIGH one
## (a tall low-bridge board) sends you back to the checkpoint: get down below it (into a gondola's
## pit, onto a deck). Past the window it
## swings up again; far behind, the post sinks out of sight and comes round again in front.
## Every post is a pure function of Game.course_time (z = front + (speed * t + i * spacing) mod span).
## The node sits at the level origin (it is not moved); all numbers are level coordinates.

## Where the posts appear (most negative z: far ahead) and vanish (far behind).
@export var z_front: float = -100.0
@export var z_back: float = 100.0
## The stretch where the arms are down: from `win_a` (front edge) back to `win_b`.
@export var win_a: float = -40.0
@export var win_b: float = 40.0
@export var spacing: float = 36.0
@export var offset: float = 0.0
## Which side of the track the posts stand on (+x / -x) and how far out.
@export var side_x: float = 3.7
## Height of the lowered arm's centre line, its height (a knee-high bar is thin; a "low bridge"
## board is tall, so it cannot be jumped) and its depth along the track.
@export var arm_y: float = 5.45
@export var arm_thick: float = 0.32
@export var arm_depth: float = 0.32
@export var speed: float = FrontierScroll.SPEED
## Seconds the arm takes to swing down (all of it ahead of the window) and up again.
@export var swing: float = 0.9
## Whether the arm kills (tall boards) or just trips you up (knee-high bars).
@export var lethal: bool = true

const RISE: float = 14.0
const SINK_DEPTH: float = 18.0

var _posts: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _areas: Array[Area3D] = []
var _lamps: Array[MeshInstance3D] = []
var _trails: Array[GPUParticles3D] = []
var _span: float = 0.0
var _lamp_mat_on: StandardMaterial3D
var _lamp_mat_off: StandardMaterial3D
var _was_down: Array[bool] = []
var _was_swinging: Array[bool] = []
var _trip_cool: float = 0.0


func _ready() -> void:
	var n: int = maxi(int(ceil((z_back - z_front) / spacing)), 1)
	_span = float(n) * spacing
	_lamp_mat_on = Look.flat(Color(1.0, 0.18, 0.08), 0.3, 0.0, 4.0)
	_lamp_mat_off = Look.flat(Color(0.35, 0.08, 0.05), 0.5, 0.0, 0.2)
	for i: int in n:
		_build_post(i)
		_was_down.append(false)
		_was_swinging.append(false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_pose(Game.course_time)
	for p: Node3D in _posts:
		p.reset_physics_interpolation()


# ---- the rhythm (pure functions of the course clock) ------------------------------------------------

## Level z of post `i` at `time`.
func post_z(i: int, time: float) -> float:
	return z_front + fposmod(float(i) * spacing + speed * time + offset, _span)


## How far the arm of a post at `z` is lowered: 0 = standing up, 1 = level across the train.
func lowered_at_z(z: float) -> float:
	var lead: float = speed * swing
	if z < win_a - lead or z > win_b + lead:
		return 0.0
	if z < win_a:
		return smoothstep(win_a - lead, win_a, z)
	if z > win_b:
		return 1.0 - smoothstep(win_b, win_b + lead, z)
	return 1.0


## Sinks the posts out of sight at both ends of the stream (metres below their place).
func _sink_at_z(z: float) -> float:
	var a: float = 1.0 - smoothstep(z_front, z_front + RISE, z)
	var b: float = smoothstep(z_front + _span - RISE, z_front + _span, z)
	return SINK_DEPTH * maxf(a, b)


## The arm of a post at `z` is down and deadly.
func deadly_at_z(z: float) -> bool:
	return lowered_at_z(z) > 0.985 and _sink_at_z(z) < 0.01


## Bot helper (duck typed like the ascent stream): will a deadly arm be within `reach` (along the
## track) of a body standing at `p` at `time`? Only arms at the body's height count.
func threat(p: Vector3, time: float, reach: float) -> bool:
	if p.y > arm_y + arm_thick * 0.5 + 0.02 or p.y + 1.8 < arm_y - arm_thick * 0.5:
		return false
	for i: int in _posts.size():
		var z: float = post_z(i, time)
		if absf(z - p.z) <= reach + arm_depth * 0.5 + 0.4 and deadly_at_z(z):
			return true
	return false


## Bot helper: no deadly arm passes over any point of the roof stretch [z0, z1] (z0 < z1) at body
## height `feet_y` during [now + a, now + b].
func clear_for(z0: float, z1: float, feet_y: float, a: float, b: float) -> bool:
	if feet_y > arm_y + arm_thick * 0.5 + 0.02 or feet_y + 1.8 < arm_y - arm_thick * 0.5:
		return true
	var s: float = a
	while s <= b:
		var t: float = Game.course_time + s
		for i: int in _posts.size():
			var z: float = post_z(i, t)
			if z >= z0 - 0.6 and z <= z1 + 0.6 and deadly_at_z(z):
				return false
		s += 0.04
	return true


# ---- gameplay ----------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_pose(t)
	_trip_cool = maxf(_trip_cool - dt, 0.0)
	for i: int in _posts.size():
		if not deadly_at_z(post_z(i, t)):
			continue
		for body: Node3D in _areas[i].get_overlapping_bodies():
			if body is Player and not lethal:
				if _trip_cool <= 0.0:
					# tripped: popped up off your feet, your run gone, nudged back the way the arm goes.
					# Clipped in mid-air (over a coupling) it only bumps you up and lets your jump carry on.
					var pl := body as Player
					if pl.grounded:
						pl.knockback(Vector3(0, 5.5, 1.5))
					else:
						pl.knockback(Vector3(pl.velocity.x, maxf(pl.velocity.y, 5.5), pl.velocity.z))
					_trip_cool = 0.6
					# SOUND: the bar clipping your boots
					WorldAudio.at(self, "frontier_signal_thwack", (body as Node3D).global_position + Vector3(0, 0.5, 0), 0.8, 30.0)
				return
			if body is Player:
				var n: Node = self
				while n != null and not n.has_method("fail"):
					n = n.get_parent()
				if n != null:
					n.call_deferred("fail", "hazard")
				return


func _pose(t: float) -> void:
	for i: int in _posts.size():
		var z: float = post_z(i, t)
		var k: float = lowered_at_z(z)
		_posts[i].position = Vector3(side_x, -_sink_at_z(z), z)
		# k = 0: the arm points straight up; k = 1: it lies level across the train
		_arms[i].rotation.z = lerpf(-PI * 0.5, 0.0, k) * signf(side_x)
		var down: bool = deadly_at_z(z)
		var swinging: bool = k > 0.01 and not down
		if down != _was_down[i] or swinging != _was_swinging[i]:
			_trails[i].emitting = down
			if swinging and not _was_swinging[i] and z < win_a:
				# SOUND: the crossing bell as the arm starts down, then the clank as it locks level
				WorldAudio.at(self, "frontier_signal_bell", _posts[i].global_position + Vector3(0, arm_y, 0), 0.8, 60.0)
			if down and not _was_down[i]:
				WorldAudio.at(self, "frontier_signal_clank", _posts[i].global_position + Vector3(0, arm_y, 0), 0.7, 45.0)
		_was_down[i] = down
		_was_swinging[i] = swinging


func _process(_dt: float) -> void:
	# lamps blink while the post is armed (only the visible flicker; the state is set in _pose)
	var on: bool = fmod(Game.course_time, 0.5) < 0.25
	for i: int in _posts.size():
		var z: float = post_z(i, Game.course_time)
		var armed: bool = lowered_at_z(z) > 0.01 or (z > win_a - speed * swing * 2.5 and z < win_b)
		_lamps[i].material_override = _lamp_mat_on if armed and on else _lamp_mat_off


# ---- look ----------------------------------------------------------------------------------------------

func _build_post(_i: int) -> void:
	var post := Node3D.new()
	add_child(post)
	_posts.append(post)
	var wood: StandardMaterial3D = Look.flat(Color(0.32, 0.22, 0.15), 0.9)
	var iron: StandardMaterial3D = Look.flat(Color(0.16, 0.15, 0.15), 0.45, 0.6)
	var top: float = arm_y + arm_thick * 0.5 + 2.4
	# the post stands on a trestle outrigger beside the track and reaches well below it
	post.add_child(Look.box(Vector3(0.34, top + 8.0, 0.34), wood, Vector3(0, (top - 8.0) * 0.5, 0)))
	post.add_child(Look.box(Vector3(0.9, 0.12, 0.9), iron, Vector3(0, top + 0.06, 0)))
	# the lamp box on top, with a red lamp facing both ways along the track
	post.add_child(Look.box(Vector3(0.5, 0.6, 0.5), iron, Vector3(0, top + 0.42, 0)))
	var lamp := Look.sphere(0.2, _lamp_mat_off, Vector3(0, top + 0.45, 0))
	lamp.scale = Vector3(1.4, 1.0, 1.4)
	post.add_child(lamp)
	_lamps.append(lamp)
	# a crossbuck board for character
	for s: float in [-1.0, 1.0]:
		var board := Look.box(Vector3(0.12, 2.0, 0.3), Look.flat(Color(0.92, 0.88, 0.78), 0.8), Vector3(0, top - 1.2, 0))
		board.rotation.z = s * 0.8
		post.add_child(board)
	# the arm: pivot on the post at arm height, the blade reaching across the train toward -side
	var pivot := Node3D.new()
	pivot.position = Vector3(0, arm_y, 0)
	post.add_child(pivot)
	_arms.append(pivot)
	var reach: float = absf(side_x) * 2.0 + 0.8
	var dir: float = -signf(side_x)
	var stripes: int = maxi(int(reach / 1.6), 3)
	for k: int in stripes:
		var col: Color = Color(0.92, 0.12, 0.08) if k % 2 == 0 else Color(0.96, 0.94, 0.88)
		var seg := Look.box(Vector3(reach / float(stripes) + 0.01, arm_thick, arm_depth), Look.flat(col, 0.5, 0.0, 0.3 if k % 2 == 0 else 0.0),
			Vector3(dir * (0.3 + (float(k) + 0.5) * reach / float(stripes)), 0, 0))
		pivot.add_child(seg)
	# the counterweight behind the pivot, and the pivot hub
	pivot.add_child(Look.box(Vector3(0.9, minf(arm_thick + 0.2, 0.9), arm_depth + 0.1), iron, Vector3(-dir * 0.55, 0, 0)))
	var hub := Look.cylinder(0.26, 0.5, iron, Vector3.ZERO, -1.0, 12)
	hub.rotation.x = PI * 0.5
	pivot.add_child(hub)
	# its kill box along the blade
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(reach, arm_thick, arm_depth + 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(dir * (0.3 + reach * 0.5), 0, 0)
	area.add_child(cs)
	pivot.add_child(area)
	_areas.append(area)
	# a wake of dust streaming off the blade while it sweeps the roofs (world space)
	var trail: GPUParticles3D = Fx.trail({"amount": 40, "lifetime": 0.5, "shape": "box",
		"extents": Vector3(reach * 0.5, arm_thick * 0.3, 0.1), "size": 0.45, "tex": Fx.Tex.SMOKE, "additive": false,
		"color": Color(0.95, 0.78, 0.55, 0.35), "fade": PackedFloat32Array([0.6, 0.0]), "emitting": false,
		"aabb": AABB(Vector3(-400, -60, -400), Vector3(800, 120, 800))})
	trail.position = Vector3(dir * (0.3 + reach * 0.5), 0, 0)
	pivot.add_child(trail)
	_trails.append(trail)
