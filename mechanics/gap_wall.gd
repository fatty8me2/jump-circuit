class_name GapWall
extends Node3D
## Gap wall (kit obstacle): a tall wall across a lane with a doorway. Every cycle the wall slides
## sideways along local X so the doorway moves off the lane (the lane is shut), waits, and slides
## back. The node sits on the floor at the lane centre; the lane runs along local Z, so yaw 0
## means "walk along -Z through the wall".
##   s 0..open_time  doorway on the lane (the last `warn` s: the lamp over it flashes amber)
##   ..+move_time slides shut   ..+closed_time shut (lamp red)   ..+move_time slides back
## The wall is solid and pushes you along as it slides: do not stand in the doorway when it shuts.

@export var gap: float = 3.4
@export var height: float = 5.0
@export var thick: float = 1.0
## How far the wall slides to shut the lane (must exceed gap / 2 + the lane's half width).
@export var slide: float = 4.4
@export var period: float = 8.0
@export var phase: float = 0.0
@export var open_time: float = 2.6
@export var move_time: float = 1.2
@export var warn: float = 1.0
## +1 slides toward local +X to shut, -1 toward -X.
@export var side: float = 1.0

var _wall: AnimatableBody3D
var _lamp_mat: StandardMaterial3D
var _closed_time: float = 1.0
var _fx_state: int = -1
var _dust: GPUParticles3D


func _ready() -> void:
	warn = clampf(maxf(warn, KitUtil.MIN_TELL), 0.0, open_time)
	move_time = maxf(move_time, KitUtil.MIN_TELL)
	_closed_time = maxf(period - open_time - 2.0 * move_time, 0.5)
	period = open_time + 2.0 * move_time + _closed_time
	side = 1.0 if side >= 0.0 else -1.0
	_wall = AnimatableBody3D.new()
	_wall.sync_to_physics = false
	_wall.collision_layer = 1
	_wall.collision_mask = 0
	add_child(_wall)
	var piece_w: float = slide + gap * 0.5 + 2.5
	var body_mat: StandardMaterial3D = Look.flat(Look.c("side").lerp(Look.c("metal"), 0.4), 0.8, 0.2)
	var stripe_a: StandardMaterial3D = Look.flat(Color(1.0, 0.72, 0.1), 0.5, 0.1, 0.5)
	var stripe_b: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.14), 0.6, 0.2)
	for sgn: float in [-1.0, 1.0]:
		var cx: float = sgn * (gap * 0.5 + piece_w * 0.5)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(piece_w, height, thick)
		cs.shape = bs
		cs.position = Vector3(cx, height * 0.5, 0)
		_wall.add_child(cs)
		_wall.add_child(Look.box(Vector3(piece_w, height, thick), body_mat, cs.position))
		_wall.add_child(Look.box(Vector3(piece_w + 0.1, 0.35, thick + 0.12), Look.flat(Look.c("trim"), 0.6), Vector3(cx, height - 0.17, 0)))
		# hazard stripes down the doorway jambs
		var n: int = int(height / 0.5)
		for i: int in n:
			_wall.add_child(Look.box(Vector3(0.3, height / float(n), thick + 0.06), stripe_a if i % 2 == 0 else stripe_b,
				Vector3(sgn * (gap * 0.5 + 0.15), (float(i) + 0.5) * height / float(n), 0)))
	# the lamp above the doorway (moves with it)
	_lamp_mat = Look.flat(Color(0.2, 1.0, 0.4), 0.4, 0.1, 1.5).duplicate() as StandardMaterial3D
	_wall.add_child(Look.box(Vector3(gap + 0.6, 0.3, thick + 0.2), Look.flat(Look.c("metal"), 0.5, 0.6), Vector3(0, height - 0.45, 0)))
	_wall.add_child(Look.box(Vector3(gap - 0.4, 0.18, thick + 0.26), _lamp_mat, Vector3(0, height - 0.45, 0)))
	_apply(Game.course_time)
	add_to_group("course_clock")
	var vis := AABB(Vector3(-slide - 8.0, -1.0, -4.0), Vector3(slide * 2.0 + 16.0, height + 3.0, 8.0))
	_dust = Fx.smoke({"amount": 14, "lifetime": 0.8, "shape": "box", "extents": Vector3(0.4, 0.05, thick * 0.5),
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(0.6, 2.0), "size": 0.8, "color": Color(0.8, 0.75, 0.68, 0.5), "aabb": vis})
	add_child(_dust)


# ---- timeline ---------------------------------------------------------------------------

func _s(time: float) -> float:
	return KitUtil.cycle_s(time, period, phase)


## 0 open, 1 warning (open, lamp flashing), 2 sliding shut, 3 shut, 4 sliding back.
func state_at(time: float) -> int:
	var s: float = _s(time)
	if s < open_time - warn:
		return 0
	if s < open_time:
		return 1
	s -= open_time
	if s < move_time:
		return 2
	s -= move_time
	if s < _closed_time:
		return 3
	return 4


## How far the doorway's centre is from the lane centre at `time` (signed, along local X).
func offset_at(time: float) -> float:
	var s: float = _s(time)
	if s < open_time:
		return 0.0
	s -= open_time
	if s < move_time:
		return side * slide * KitUtil.smooth(s / move_time)
	s -= move_time
	if s < _closed_time:
		return side * slide
	s -= _closed_time
	return side * slide * (1.0 - KitUtil.smooth(s / move_time))


## True while a rider walking the lane fits through the doorway for the whole next `window` s.
func is_open_for(time: float, window: float, clearance: float = 1.1) -> bool:
	var half: float = gap * 0.5 - clearance * 0.5
	return KitUtil.holds_for(func(x: float) -> bool: return absf(offset_at(x)) <= half, time, window, 0.04)


## Seconds until the doorway is next fully on the lane and about to stay there (0 if now).
func open_in(time: float) -> float:
	var s: float = 0.0
	while s < period + 1.0:
		if is_open_for(time + s, 1.0):
			return s
		s += 0.05
	return period


# ---- behaviour --------------------------------------------------------------------------

func snap_to_clock() -> void:
	_apply(Game.course_time)
	_wall.reset_physics_interpolation()


func _apply(time: float) -> void:
	_wall.position.x = offset_at(time)


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var st: int = state_at(t)
	var col: Color
	match st:
		0:
			col = Color(0.2, 1.0, 0.4)
		1:
			col = Color(1.0, 0.65, 0.1) if fmod(_s(t), 0.2) > 0.1 else Color(0.35, 0.22, 0.05)
		2:
			col = Color(1.0, 0.2, 0.15)
		3:
			col = Color(1.0, 0.2, 0.15)
		_:
			col = Color(1.0, 0.65, 0.1)
	if not _lamp_mat.albedo_color.is_equal_approx(col):
		_lamp_mat.albedo_color = col
		_lamp_mat.emission = col
	if st == _fx_state:
		return
	var was: int = _fx_state
	_fx_state = st
	if was < 0:
		return
	var at: Vector3 = _wall.global_position + Vector3(0, height * 0.5, 0)
	if st == 1:
		WorldAudio.at(self, "kit_gapwall_warn", at, 0.6, 35.0)
	elif st == 2:
		WorldAudio.at(self, "kit_gapwall_slide", at, 0.9, 45.0)
	elif st == 4:
		WorldAudio.at(self, "kit_gapwall_slide", at, 0.6, 40.0)
	elif st == 3 and was == 2:
		_dust.position = Vector3(offset_at(t), 0.1, 0)
		_dust.restart()
		WorldAudio.at(self, "kit_gapwall_thud", at, 1.0, 50.0)
