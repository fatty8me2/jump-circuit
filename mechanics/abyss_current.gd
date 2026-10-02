class_name AbyssCurrent
extends Area3D
## The Abyss: a CURRENT - a river of moving water you can only see by what it carries: a stream of
## glowing plankton streaking along it and motes tumbling with it. Inside the box it pushes you
## like a conveyor in the air (an acceleration; gravity is 30 up / 42 down, so an up-current needs
## more than 42 to lift a falling player).
## With `period` > 0 it is a VENT that erupts on the clock (Game.course_time): it is calm, then for
## `warn` seconds it rumbles and a thin trickle of bubbles and shimmer rises from its mouth, then
## it blasts for `on_fraction` of the cycle. Active while fposmod(t / period + phase, 1) < on_fraction.
## Centre position; `push` is in the node's local axes (every level push is axis-aligned).

@export var size: Vector3 = Vector3(4, 8, 4)
@export var push: Vector3 = Vector3(0, 60, 0)
## Vertical speed an up-current will not push past.
@export var max_rise: float = 14.0
## 0 = always on. Otherwise the vent's cycle (s).
@export var period: float = 0.0
@export var on_fraction: float = 0.4
@export var phase: float = 0.0
@export var warn: float = 1.0
@export var tint: Color = Color(0.3, 1.0, 0.9)

var _along: Vector3 = Vector3.UP
var _span: float = 1.0
var _streaks: GPUParticles3D
var _motes: GPUParticles3D
var _bubbles: GPUParticles3D
var _trickle: GPUParticles3D
var _blast: GPUParticles3D
var _was_on: bool = false
var _was_warn: bool = false
var _loop: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_along = push.normalized() if push.length() > 0.01 else Vector3.UP
	_span = maxf(absf(size.dot(_along.abs())), 0.5)
	_build()
	# SOUND: abyss_current_loop - a deep rushing hiss of moving water while the current runs (loop)
	_loop = WorldAudio.loop("abyss_current_loop", self, -12.0, maxf(maxf(size.x, size.y), size.z) * 0.5 + 12.0, 5.0, period <= 0.0)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_on = is_active_at(Game.course_time)
	_was_warn = false
	_apply(Game.course_time)


func pulsing() -> bool:
	return period > 0.0


func is_active_at(time: float) -> bool:
	if period <= 0.0:
		return true
	return fposmod(time / period + phase, 1.0) < on_fraction


## Seconds until it next erupts (0 while erupting).
func time_until_on(time: float) -> float:
	if is_active_at(time):
		return 0.0
	return (1.0 - fposmod(time / period + phase, 1.0)) * period


## Active for the whole of [time + a, time + b].
func on_between(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not is_active_at(time + s):
			return false
		s += 0.04
	return is_active_at(time + b)


## Calm for the whole of [time + a, time + b].
func calm_between(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_active_at(time + s):
			return false
		s += 0.04
	return not is_active_at(time + b)


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	if not is_active_at(t):
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var dv: Vector3 = global_basis * push * dt
			if dv.y > 0.0 and p.velocity.y > max_rise:
				dv.y = 0.0
			p.add_impulse(dv)


func _process(_dt: float) -> void:
	if period > 0.0:
		_apply(Game.course_time)


func _apply(t: float) -> void:
	var on: bool = is_active_at(t)
	var warning: bool = period > 0.0 and not on and time_until_on(t) < warn
	_streaks.amount_ratio = 1.0 if on else 0.08
	_motes.amount_ratio = 1.0 if on else 0.1
	if _bubbles != null:
		_bubbles.amount_ratio = 1.0 if on else 0.15
	if _trickle != null and _trickle.emitting != warning:
		_trickle.emitting = warning
	if warning != _was_warn:
		_was_warn = warning
		if warning:
			# SOUND: abyss_vent_rumble - a low gurgling rumble building under the vent (~1 s ahead)
			WorldAudio.at(self, "abyss_vent_rumble", global_position, 0.8, 35.0)
	if on != _was_on:
		_was_on = on
		if on and period > 0.0:
			if _blast != null:
				_blast.restart()
			# SOUND: abyss_vent_burst - the vent erupts in a roar of bubbles
			WorldAudio.at(self, "abyss_vent_burst", global_position, 0.9, 40.0)
		WorldAudio.set_active(_loop, on)


func _build() -> void:
	var axis: Vector3 = _along.abs()
	var vis := AABB(-size - Vector3.ONE * 3.0, size * 2.0 + Vector3.ONE * 6.0)
	var ext: Vector3 = size * 0.5 * (Vector3.ONE - axis) + axis * 0.1
	var off: Vector3 = -_along * _span * 0.5
	var hot: Color = Fx.hot(tint, 2.0)
	# glowing plankton streaking along the current (stretched along their velocity)
	var life: float = maxf(_span / 7.0, 0.3)
	_streaks = Fx.emitter({"amount": int(clampf(size.x * size.y * size.z * 0.3, 16, 90)), "lifetime": life,
		"preprocess": life, "local": true, "shape": "box", "extents": ext, "offset": off, "dir": _along, "spread": 3.0,
		"speed": Vector2(6.0, 8.0), "facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.04, 0.6),
		"color": Color(hot.r, hot.g, hot.b, 0.8), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	add_child(_streaks)
	var life2: float = maxf(_span / 4.0, 0.4)
	_motes = Fx.emitter({"amount": int(clampf(size.x * size.y * size.z * 0.08, 8, 34)), "lifetime": life2,
		"preprocess": life2, "local": true, "shape": "box", "extents": ext, "offset": off, "dir": _along, "spread": 8.0,
		"speed": Vector2(3.5, 4.5), "turbulence": 1.0, "turbulence_scale": 3.0, "tex": Fx.Tex.DOT, "size": 0.12,
		"scale": Vector2(0.5, 1.0), "pick": PackedColorArray([hot, Color(0.9, 0.95, 1.0, 0.6)]),
		"fade": PackedFloat32Array([0.0, 0.8, 0.8, 0.0]), "aabb": vis})
	add_child(_motes)
	if _along.y > 0.5:
		# up-currents and vents carry bubbles
		_bubbles = Fx.emitter({"amount": int(clampf(size.x * size.z * 4.0, 14, 60)), "lifetime": life2,
			"preprocess": life2, "local": true, "shape": "box", "extents": ext, "offset": off, "dir": Vector3.UP,
			"spread": 6.0, "speed": Vector2(4.0, 7.0), "turbulence": 1.4, "turbulence_scale": 2.0, "tex": Fx.Tex.BUBBLE,
			"size": 0.2, "scale": Vector2(0.4, 1.2), "color": Color(0.7, 1.1, 1.2, 0.7),
			"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
		add_child(_bubbles)
	if period > 0.0:
		_trickle = Fx.emitter({"amount": 24, "lifetime": 1.0, "local": true, "shape": "box", "extents": ext * 0.8,
			"offset": off, "dir": _along, "spread": 12.0, "speed": Vector2(1.0, 2.5), "tex": Fx.Tex.BUBBLE, "size": 0.14,
			"color": Color(1.0, 1.4, 1.5, 0.8), "emitting": false, "aabb": vis})
		add_child(_trickle)
		_blast = Fx.burst({"amount": 40, "lifetime": 0.8, "explosiveness": 0.9, "local": true, "shape": "box",
			"extents": ext, "offset": off, "dir": _along, "spread": 18.0, "speed": Vector2(8.0, 14.0),
			"damping": Vector2(4.0, 6.0), "tex": Fx.Tex.BUBBLE, "size": 0.3, "scale": Vector2(0.4, 1.0),
			"color": Color(1.0, 1.5, 1.6, 0.85), "aabb": vis})
		add_child(_blast)
