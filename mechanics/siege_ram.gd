class_name SiegeRam
extends Node3D
## Castle Siege: a SWINGING BATTERING RAM. An iron-shod log hangs on chains from a timber gantry
## across a wall-walk and swings back and forth ACROSS it on the course clock (the log lies along
## local Z, along the walk; it swings along local X). Where it sweeps the walk it rams whatever is
## there: the runner is thrown along the swing (log speed + `kick`, and up) - off the walkway. It never
## kills by itself. The swing is always in view (nothing is hidden), the chains creak at each end of
## every swing and the head booms, so the rhythm reads from far off; the log crosses the lane's
## centre line twice a period, each time for a fraction of a second.
## Node origin = the middle of the gantry's top beam; the log hangs `rope_length` below it. A pure
## function of Game.course_time.

@export var rope_length: float = 3.8
@export var log_length: float = 3.4
@export var log_radius: float = 0.4
@export var swing_deg: float = 42.0
@export var period: float = 5.0
@export var phase: float = 0.0
@export var kick: float = 7.0
## Half-width of the gantry across the swing: the posts stand this far out either side (local X).
@export var frame_half: float = 4.6

var _log: Node3D
var _chains: Array[Node3D] = []
var _area: Area3D
var _cool: float = 0.0
var _hit_fx: GPUParticles3D
var _creaked: int = -1
var _boomed: int = -1


## Height of the gantry beam above the floor the log swings over (the log's centre rides ~1 m up).
static func beam_height(rope: float) -> float:
	return rope + 1.0


func _ready() -> void:
	_build()
	_apply(Game.course_time)
	add_to_group("course_clock")


func angle_at(time: float) -> float:
	return deg_to_rad(swing_deg) * sin(TAU * (time / period + phase))


## Local X of the log's centre at `time`.
func x_at(time: float) -> float:
	return rope_length * sin(angle_at(time))


## Speed of the log along X at `time` (signed, m/s).
func speed_at(time: float) -> float:
	var w: float = deg_to_rad(swing_deg) * cos(TAU * (time / period + phase)) * TAU / period
	return w * rope_length * cos(angle_at(time))


## True when the log is clear of the lane line at local X = `x` (its body plus `margin`) at `time`.
func clear_at(time: float, x: float, margin: float = 0.9) -> bool:
	return absf(x_at(time) - x) > log_radius + margin


## Clear of the lane line over the whole window [now + a, now + b].
func clear_between(x: float, a: float, b: float, margin: float = 0.9) -> bool:
	var s: float = a
	while s <= b:
		if not clear_at(Game.course_time + s, x, margin):
			return false
		s += 0.03
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)
	_log.reset_physics_interpolation()


func _apply(time: float) -> void:
	var a: float = angle_at(time)
	_log.position = Vector3(rope_length * sin(a), -rope_length * cos(a), 0)
	for c: Node3D in _chains:
		c.rotation.z = a


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var v: float = speed_at(t)
			var dir: float = signf(v) if absf(v) > 0.3 else signf(to_local(body.global_position).x - _log.position.x)
			var along: Vector3 = global_basis.x.normalized() * dir
			(body as Player).knockback(along * (absf(v) + kick) + Vector3(0, 6.0, 0))
			_cool = 0.6
			_hit_fx.global_position = body.global_position + Vector3(0, 0.8, 0)
			_hit_fx.restart()
			_hit_fx.emitting = true
			# SOUND: siege_ram_thud - the ram's iron head slamming into the runner
			WorldAudio.at(self, "siege_ram_thud", body.global_position, 1.0, 40.0)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var u: float = t / period + phase
	# the creak of the chains at each end of the swing (every half period, at the turnaround)
	var turn: int = int(floor(u * 2.0 + 0.5))
	if turn != _creaked:
		_creaked = turn
		# SOUND: siege_ram_creak - chains and timber groaning as the ram reaches the top of its swing
		WorldAudio.at(self, "siege_ram_creak", global_position + Vector3(0, -rope_length, 0), 0.7, 34.0)
	# a low boom when the log passes the middle (every half period, a quarter period later)
	var mid: int = int(floor(u * 2.0 + 0.0))
	if mid != _boomed:
		_boomed = mid
		# SOUND: siege_ram_whoosh - the log sweeping through the bottom of its swing
		WorldAudio.at(self, "siege_ram_whoosh", _log.global_position, 0.6, 30.0)


func _build() -> void:
	var wood: StandardMaterial3D = Look.flat(Color(0.36, 0.25, 0.16), 0.9)
	var dark: StandardMaterial3D = Look.flat(Color(0.2, 0.14, 0.1), 0.9)
	var iron: StandardMaterial3D = Look.flat(Color(0.16, 0.16, 0.18), 0.45, 0.7)
	var floor_y: float = -(rope_length + 1.0)
	var foot: float = floor_y - 9.0
	# the gantry: two stout posts either side of the swing with a cross-braced beam and a pitched roof
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.5, -foot + 0.4, 0.5), dark, Vector3(sx * frame_half, foot * 0.5 + 0.2, 0)))
		for sz: float in [-1.0, 1.0]:
			var brace := Look.box(Vector3(0.18, 1.9, 0.18), wood, Vector3(sx * (frame_half - 0.75), -0.7, sz * 0.9))
			brace.rotation.z = sx * 0.62
			add_child(brace)
	add_child(Look.box(Vector3(frame_half * 2.0 + 0.9, 0.5, 0.7), dark, Vector3(0, 0.1, 0)))
	for sz2: float in [-1.0, 1.0]:
		var slope := Look.box(Vector3(frame_half * 2.0 + 1.2, 0.12, 1.2), Look.flat(Color(0.3, 0.17, 0.12), 0.8), Vector3(0, 0.55, sz2 * 0.55))
		slope.rotation.x = sz2 * 0.42
		add_child(slope)
	# the log on its chains
	_log = Node3D.new()
	add_child(_log)
	var body := Look.cylinder(log_radius, log_length, wood, Vector3.ZERO, -1.0, 14)
	body.rotation.x = PI * 0.5
	_log.add_child(body)
	for sz3: float in [-1.0, 1.0]:
		var band := Look.cylinder(log_radius * 1.08, 0.16, iron, Vector3(0, 0, sz3 * log_length * 0.3), -1.0, 14)
		band.rotation.x = PI * 0.5
		_log.add_child(band)
	# the iron ram's head at the front end (a blunt cone with horns)
	var head := Look.cylinder(log_radius * 1.18, 0.55, iron, Vector3(0, 0, -log_length * 0.5 - 0.2), log_radius * 0.8, 12)
	head.rotation.x = PI * 0.5
	_log.add_child(head)
	for sx2: float in [-1.0, 1.0]:
		var horn := Look.cylinder(0.08, 0.5, iron, Vector3(sx2 * 0.38, 0.14, -log_length * 0.5 - 0.1), 0.02, 6)
		horn.rotation = Vector3(PI * 0.5 - 0.5, 0, sx2 * 0.55)
		_log.add_child(horn)
	# chains from the beam to the log's slings
	for sz4: float in [-1.0, 1.0]:
		var holder := Node3D.new()
		holder.position = Vector3(0, 0, sz4 * log_length * 0.3)
		add_child(holder)
		holder.add_child(Look.cylinder(0.05, rope_length, iron, Vector3(0, -rope_length * 0.5, 0), -1.0, 5))
		for i: int in 5:
			holder.add_child(Look.sphere(0.09, iron, Vector3(0, -rope_length * (0.12 + 0.19 * float(i)), 0)))
		_chains.append(holder)
	# a red pennon on the gantry
	var flag := Look.box(Vector3(0.05, 0.55, 0.9), Look.flat(Color(0.75, 0.1, 0.1), 0.7, 0.0, 0.2), Vector3(frame_half, 1.4, 0))
	add_child(flag)
	# the ram detector: a box round the log
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var bx := BoxShape3D.new()
	bx.size = Vector3(log_radius * 2.0 + 0.2, log_radius * 2.0 + 0.2, log_length + 0.9)
	var cs := CollisionShape3D.new()
	cs.shape = bx
	_area.add_child(cs)
	_log.add_child(_area)
	_hit_fx = Fx.burst({"amount": 22, "lifetime": 0.6, "tex": Fx.Tex.STAR, "size": 0.26, "spread": 90.0,
		"speed": Vector2(3.0, 7.0), "gravity": Vector3(0, -9.0, 0), "color": Fx.hot(Color(1.0, 0.8, 0.5), 2.0),
		"aabb": AABB(Vector3(-8, -6, -8), Vector3(16, 14, 16))})
	add_child(_hit_fx)
