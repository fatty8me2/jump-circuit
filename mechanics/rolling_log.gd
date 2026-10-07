class_name RollingLog
extends StaticBody3D
## Rolling log (kit obstacle). A fat cylinder lying along local X that you run along. Its skin
## turns, so it DRAGS whatever stands on it sideways (along local Z) the way a conveyor does.
## With `period` > 0 the roll reverses on a sine: the push is strongest mid-swing and eases
## through zero, so the log visibly slows and stops for a moment before it turns the other way
## (that slow-down is the tell, a fifth of a period or more). period 0 = constant roll.
##   push(t) = speed * sin(2 pi (t / period + phase))      (local +Z positive)
## `top` is the centre of the TOP line of the log, like every platform.

@export var length: float = 12.0
@export var radius: float = 1.2
@export var speed: float = 4.0
@export var period: float = 0.0
@export var phase: float = 0.0

var _drum: Node3D
var _end_mat: StandardMaterial3D
var _hum: AudioStreamPlayer3D
var _last_sign: int = 0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = length
	cs.shape = sh
	cs.rotation.z = PI * 0.5
	add_child(cs)
	_drum = Node3D.new()
	add_child(_drum)
	var bark: StandardMaterial3D = Look.flat(Look.c("decor").darkened(0.45), 0.9)
	var core := Look.cylinder(radius, length, bark, Vector3.ZERO, -1.0, 28)
	core.rotation.z = PI * 0.5
	_drum.add_child(core)
	var ridge: StandardMaterial3D = Look.flat(Look.c("decor").darkened(0.2), 0.9)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var r := Look.box(Vector3(length * 0.97, 0.16, 0.34), ridge, Vector3(0, cos(a), sin(a)) * radius)
		r.rotation.x = a
		_drum.add_child(r)
	# iron rims at both ends, and a lamp each side that shows which way it is pushing
	var iron: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.7)
	_end_mat = Look.flat(Look.c("accent"), 0.4, 0.2, 1.4).duplicate() as StandardMaterial3D
	for sx: float in [-1.0, 1.0]:
		var rim := Look.cylinder(radius * 1.04, 0.2, iron, Vector3(sx * (length * 0.5 - 0.1), 0, 0), -1.0, 28)
		rim.rotation.z = PI * 0.5
		add_child(rim)
		add_child(Look.sphere(0.18, _end_mat, Vector3(sx * (length * 0.5 + 0.15), radius * 0.2, 0)))
	_hum = WorldAudio.loop("kit_log_roll", self, -16.0, 24.0, 4.0)
	_apply(Game.course_time)
	add_to_group("course_clock")


## Local +Z push (m/s) the log gives a rider at `time`.
func speed_at(time: float) -> float:
	if period <= 0.0:
		return speed
	return speed * sin(TAU * (time / period + phase))


## True while the push stays under `max_push` m/s for the next `window` seconds.
func is_calm_for(time: float, window: float, max_push: float = 1.0) -> bool:
	return KitUtil.holds_for(func(x: float) -> bool: return absf(speed_at(x)) <= max_push, time, window)


## Seconds until the push next drops under `max_push` (0 if it already is).
func calm_in(time: float, max_push: float = 1.0) -> float:
	var s: float = 0.0
	while s < 20.0:
		if absf(speed_at(time + s)) <= max_push:
			return s
		s += 0.05
	return 20.0


func surface_velocity() -> Vector3:
	var z: Vector3 = global_basis.z
	z.y = 0.0
	return z.normalized() * speed_at(Game.course_time)


func _angle_at(time: float) -> float:
	if period <= 0.0:
		return speed * time / radius
	var w: float = TAU / period
	return -speed / (w * radius) * cos(w * time + TAU * phase)


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _apply(time: float) -> void:
	_drum.rotation.x = _angle_at(time)
	var s: float = speed_at(time)
	var k: float = clampf(s / maxf(speed, 0.01), -1.0, 1.0)
	var a: Color = Look.c("accent")
	var b: Color = Look.c("accent2")
	var col: Color = a.lerp(b, (k + 1.0) * 0.5)
	if not _end_mat.albedo_color.is_equal_approx(col):
		_end_mat.albedo_color = col
		_end_mat.emission = col
	KitUtil.glow(_end_mat, 0.4 + 1.2 * absf(k))


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _process(_dt: float) -> void:
	var s: float = speed_at(Game.course_time)
	if _hum != null:
		WorldAudio.set_active(_hum, absf(s) > 0.15)
		_hum.pitch_scale = clampf(0.7 + absf(s) / maxf(speed, 0.5) * 0.5, 0.6, 1.3)
	var sg: int = int(signf(s)) if absf(s) > 0.15 else 0
	if sg != 0 and _last_sign != 0 and sg != _last_sign:
		WorldAudio.at(self, "kit_log_reverse", global_position, 0.6, 30.0)
	if sg != 0:
		_last_sign = sg
