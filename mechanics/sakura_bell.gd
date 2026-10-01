class_name SakuraBell
extends Node3D
## Sakura Peaks: a SWINGING TEMPLE-BELL LOG (a shumoku battering ram). A great log hangs level on
## two ropes from a timber frame and swings along its own length on the course clock; at the end of
## every swing toward the bell its striking end booms against a bronze temple bell. Anything in its
## way is rammed: thrown along the swing (log speed + `kick`, and up) - off a walkway, down a stair.
## It never kills by itself. The swing is always in view, the ropes creak at each end and the bell
## booms on the beat, so its rhythm is readable from far off.
## Node origin = the middle of the frame's beam; the log hangs `rope_length` below it, its axis
## along local X, swinging along local X (rotate the node to re-aim it). The bell hangs at +X.

@export var rope_length: float = 4.5
@export var log_length: float = 3.6
@export var log_radius: float = 0.42
@export var swing_deg: float = 40.0
@export var period: float = 4.0
@export var phase: float = 0.0
@export var kick: float = 7.0
@export var with_bell: bool = true
## Frame half-width across the swing (local Z): the posts stand this far out either side.
@export var frame_half: float = 1.6


## Height of the frame's beam (the node origin) above the floor the log swings over.
static func pivot_height(rope: float, radius: float) -> float:
	return rope + radius + 0.6

var _log: Node3D
var _ropes: Array[Node3D] = []
var _area: Area3D
var _cool: float = 0.0
var _bell: Node3D
var _bell_x: float = 0.0
var _struck: int = -1
var _whooshed: int = -1
var _hit_fx: GPUParticles3D
var _dust: GPUParticles3D
var _bell_swing: float = 0.0


func _ready() -> void:
	_build()
	_apply(Game.course_time)
	add_to_group("course_clock")


func angle_at(time: float) -> float:
	return deg_to_rad(swing_deg) * sin(TAU * (time / period + phase))


## Local X of the log's centre at `time`.
func offset_at(time: float) -> float:
	return rope_length * sin(angle_at(time))


## True when the log's body stays out of the local X band [x0, x1] (plus `margin`) at `time`.
func clear_of_band(time: float, x0: float, x1: float, margin: float = 0.45) -> bool:
	var c: float = offset_at(time)
	var h: float = log_length * 0.5 + log_radius + margin
	return c + h < x0 or c - h > x1


## Clear of the band over the whole window [now + a, now + b].
func clear_between(x0: float, x1: float, a: float, b: float, margin: float = 0.45) -> bool:
	var s: float = a
	while s <= b:
		if not clear_of_band(Game.course_time + s, x0, x1, margin):
			return false
		s += 0.03
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)
	_log.reset_physics_interpolation()


func _apply(time: float) -> void:
	var a: float = angle_at(time)
	_log.position = Vector3(rope_length * sin(a), -rope_length * cos(a), 0)
	for r: Node3D in _ropes:
		r.rotation.z = a


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var w: float = deg_to_rad(swing_deg) * cos(TAU * (t / period + phase)) * TAU / period
			var along: Vector3 = global_basis.x.normalized() * (signf(w) if absf(w) > 0.05 else signf(body.global_position.dot(global_basis.x) - _log.global_position.dot(global_basis.x)))
			(body as Player).knockback(along * (absf(w) * rope_length + kick) + Vector3(0, 6.0, 0))
			_cool = 0.6
			_hit_fx.global_position = body.global_position + Vector3(0, 0.8, 0)
			_hit_fx.restart()
			_hit_fx.emitting = true
			# SOUND: a heavy wooden thump as the log rams the runner
			WorldAudio.at(self, "sakura_log_thump", body.global_position, 1.0, 40.0)


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var u: float = fposmod(t / period + phase, 1.0)
	var cycle: int = int(floor(t / period + phase))
	# the strike: the log reaches the bell at the top of its +X swing (u = 0.25)
	if with_bell and u >= 0.245 and u < 0.5 and cycle != _struck:
		_struck = cycle
		_bell_swing = 1.0
		_dust.restart()
		_dust.emitting = true
		# SOUND: the great bell booming as the log strikes it (the tell: one boom per swing)
		WorldAudio.at(self, "sakura_bell_bong", _bell.global_position if _bell != null else global_position, 1.0, 70.0, 0.02)
	# a creak of the ropes as the log swings back through the bottom (once per half swing)
	var half: int = int(floor((t / period + phase) * 2.0 + 0.5))
	if half != _whooshed:
		_whooshed = half
		WorldAudio.at(self, "sakura_log_whoosh", _log.global_position, 0.7, 30.0)
	if _bell != null:
		_bell_swing = maxf(_bell_swing - dt * 0.8, 0.0)
		_bell.rotation.z = -0.08 * _bell_swing * sin(t * 7.0)


func _build() -> void:
	var wood: StandardMaterial3D = SakuraDecor.mat(Color(0.42, 0.3, 0.2), 0.85)
	var dark: StandardMaterial3D = SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.8)
	var rope_m: StandardMaterial3D = SakuraDecor.mat(Color(0.75, 0.6, 0.35), 0.9)
	var floor_y: float = -(rope_length + log_radius + 0.6)
	# the frame: two posts either side of the swing (local +-Z), a beam and a little roof
	var span: float = rope_length * sin(deg_to_rad(swing_deg)) * 2.0 + log_length + 1.0
	# (the posts run on down past the floor: the frame stands on the slope below the path)
	var foot: float = floor_y - 8.0
	for sz: float in [-1.0, 1.0]:
		var post := Look.box(Vector3(0.35, -foot + 0.4, 0.35), dark, Vector3(0, foot * 0.5 + 0.2, sz * frame_half))
		add_child(post)
	add_child(Look.box(Vector3(0.5, 0.45, frame_half * 2.0 + 0.8), dark, Vector3(0, 0.15, 0)))
	var roof := Look.box(Vector3(1.4, 0.2, frame_half * 2.0 + 1.6), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15), Vector3(0, 0.55, 0))
	add_child(roof)
	# the log on its ropes
	_log = Node3D.new()
	add_child(_log)
	var body := Look.cylinder(log_radius, log_length, wood, Vector3.ZERO, -1.0, 14)
	body.rotation.z = PI * 0.5
	_log.add_child(body)
	for sx: float in [-1.0, 1.0]:
		var cap := Look.cylinder(log_radius * 1.04, 0.16, dark, Vector3(sx * (log_length * 0.5 - 0.1), 0, 0), -1.0, 14)
		cap.rotation.z = PI * 0.5
		_log.add_child(cap)
		# rope bands where the slings hold it
		var band := Look.cylinder(log_radius * 1.06, 0.12, rope_m, Vector3(sx * log_length * 0.28, 0, 0), -1.0, 14)
		band.rotation.z = PI * 0.5
		_log.add_child(band)
	# a red-and-white braided tassel off the striking end
	_log.add_child(Look.sphere(0.16, SakuraDecor.mat(SakuraDecor.VERMILION, 0.6), Vector3(log_length * 0.5 + 0.05, -log_radius * 0.6, 0)))
	# ropes: from the beam down to the log's slings (each a pivoting rod)
	for sx: float in [-1.0, 1.0]:
		var holder := Node3D.new()
		holder.position = Vector3(sx * log_length * 0.28, 0, 0)
		add_child(holder)
		var r := Look.cylinder(0.04, rope_length, rope_m, Vector3(0, -rope_length * 0.5, 0), -1.0, 5)
		holder.add_child(r)
		_ropes.append(holder)
	# the bell at +X: hung from its own little frame just past the end of the swing
	_bell_x = rope_length * sin(deg_to_rad(swing_deg)) + log_length * 0.5 + 0.95
	if with_bell:
		_bell = SakuraDecor.new(self, RandomNumberGenerator.new()).temple_bell(Vector3(_bell_x + 0.0, -rope_length + 1.3, 0), 0.95)
		add_child(Look.box(Vector3(0.4, 0.4, 2.6), dark, Vector3(_bell_x, -rope_length + 1.55, 0)))
		for sz: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.3, -foot - rope_length + 1.9, 0.3), dark, Vector3(_bell_x, foot + (-foot - rope_length + 1.9) * 0.5, sz * 1.15)))
	# the ram detector: a capsule round the log
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var cap_s := CapsuleShape3D.new()
	cap_s.radius = log_radius + 0.05
	cap_s.height = log_length + 0.1
	var cs := CollisionShape3D.new()
	cs.shape = cap_s
	cs.rotation.z = PI * 0.5
	_area.add_child(cs)
	_log.add_child(_area)
	var vis := AABB(Vector3(-span, -rope_length - 4.0, -6), Vector3(span * 2.0, rope_length + 8.0, 12))
	_hit_fx = SakuraFx.petal_pop(0.8, 30, 6.0)
	_hit_fx.visibility_aabb = AABB(Vector3(-8, -6, -8), Vector3(16, 14, 16))
	add_child(_hit_fx)
	# the strike: dust and petals shaken off the bell
	_dust = Fx.burst({"amount": 26, "lifetime": 1.6, "shape": "sphere", "radius": 1.0, "tex": Fx.Tex.PETAL, "additive": false,
		"size": 0.16, "speed": Vector2(0.6, 2.0), "gravity": Vector3(0, -1.6, 0), "curve": "flat", "pick": SakuraFx.PETALS,
		"angle": Vector2(0, 360), "spin": Vector2(-200, 200), "aabb": vis})
	_dust.position = Vector3(_bell_x, -rope_length + 0.6, 0)
	add_child(_dust)
