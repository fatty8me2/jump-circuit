class_name DesertSandfall
extends Node3D
## Scarab Sands: a curtain of sand pouring from a slot in the ceiling on a rhythm
## (Game.course_time) - a timing gate. Positioned at the floor point under the middle of the
## curtain; local X runs across it (`width`), local Z through it (`depth`). For `warn` seconds
## before each pour thin streams trickle and grit sifts down; then the sand front races down
## from the slot (FALL m/s), pours, and when it stops the tail falls away. Wherever the sand
## is, it buries you: deadly. Clear gaps below the head and above the tail are safe.

@export var width: float = 3.0
@export var height: float = 7.0
@export var depth: float = 1.2
@export var period: float = 3.0
## Fraction of the period the slot is pouring (the tail still has to fall after that).
@export var on_fraction: float = 0.45
@export var phase: float = 0.0
@export var warn: float = 0.6

## Speed of the falling sand front and tail (m/s).
const FALL: float = 16.0

var _area: Area3D
var _mat: ShaderMaterial
var _splash: GPUParticles3D
var _grains: GPUParticles3D
var _trickle: GPUParticles3D
var _cloud: GPUParticles3D
var _loop: AudioStreamPlayer3D


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var bs := BoxShape3D.new()
	bs.size = Vector3(width - 0.2, height, depth)
	var cs := CollisionShape3D.new()
	cs.shape = bs
	_area.add_child(cs)
	_area.position = Vector3(0, height * 0.5, 0)
	add_child(_area)
	_build()
	add_to_group("course_clock")
	var pouring: bool = is_pouring_at(Game.course_time)
	_loop = WorldAudio.loop("sandfall_loop", self, -8.0, 26.0, 5.0, pouring)
	if _loop != null:
		_loop.position = Vector3(0, 1.5, 0)
	_apply(Game.course_time)


func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/desert_sandfall.gdshader")
	_mat.set_shader_parameter("width", width)
	_mat.set_shader_parameter("height", height)
	for dz: float in [-depth * 0.3, 0.0, depth * 0.3]:
		var q := QuadMesh.new()
		q.size = Vector2(width, height)
		var mi := Look.mesh_node(q, _mat, Vector3(0, height * 0.5, dz))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var vis := AABB(Vector3(-width - 3, -1, -depth - 3), Vector3(width * 2 + 6, height + 4, depth * 2 + 6))
	_splash = Fx.emitter({"amount": 36, "lifetime": 0.9, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.45, 0.1, depth * 0.4), "dir": Vector3.UP, "spread": 70.0, "speed": Vector2(1.5, 4.0),
		"gravity": Vector3(0, -3, 0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.1, "curve": "puff",
		"angle": Vector2(0, 360), "color": Color(0.95, 0.78, 0.52, 0.55), "fade": PackedFloat32Array([0.0, 0.9, 0.0]), "aabb": vis})
	_splash.position = Vector3(0, 0.1, 0)
	add_child(_splash)
	_grains = Fx.emitter({"amount": 40, "lifetime": 0.6, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.45, 0.05, depth * 0.3), "dir": Vector3.UP, "spread": 60.0, "speed": Vector2(2.0, 5.0),
		"gravity": Vector3(0, -14, 0), "additive": false, "size": 0.08, "color": Color(0.92, 0.72, 0.45),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_grains.position = Vector3(0, 0.1, 0)
	add_child(_grains)
	_trickle = Fx.emitter({"amount": 26, "lifetime": height / 9.0, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.42, 0.05, depth * 0.2), "dir": Vector3.DOWN, "spread": 2.0, "speed": Vector2(1.0, 2.0),
		"gravity": Vector3(0, -12, 0), "facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false,
		"size": Vector2(0.05, 0.5), "color": Color(0.95, 0.78, 0.5, 0.9), "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_trickle.position = Vector3(0, height - 0.1, 0)
	add_child(_trickle)
	_cloud = Fx.emitter({"amount": 10, "lifetime": 1.4, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.5, 0.2, depth * 0.5), "dir": Vector3.DOWN, "spread": 40.0, "speed": Vector2(0.5, 1.5),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.4, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.95, 0.8, 0.56, 0.35), "fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis})
	_cloud.position = Vector3(0, height - 0.3, 0)
	add_child(_cloud)


func _k(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


func is_pouring_at(time: float) -> bool:
	return _k(time) < on_fraction * period


## The span of the curtain filled with sand at `time`, as local heights [lo, hi] (lo > hi: none).
func sand_span_at(time: float) -> Vector2:
	var k: float = _k(time)
	var on_t: float = on_fraction * period
	if k < on_t:
		# the front falls from the slot; everything above it is sand
		return Vector2(maxf(height - FALL * k, 0.0), height)
	var since: float = k - on_t
	var tail: float = height - FALL * since
	if tail <= 0.0:
		return Vector2(1.0, -1.0)
	return Vector2(0.0, tail)


## True if sand fills any part of the height band [y0, y1] (local, above the floor) at `time`.
func blocks_at(time: float, y0: float = 0.0, y1: float = 2.0) -> bool:
	var s: Vector2 = sand_span_at(time)
	return s.x <= s.y and s.x < y1 and s.y > y0


## Seconds until the next pour starts (0 while pouring).
func time_until_pour(time: float) -> float:
	var k: float = _k(time)
	return 0.0 if k < on_fraction * period else period - k


## True if a runner at floor level is safe in the curtain for the whole window [time + a, time + b].
func is_clear_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if blocks_at(time + s, 0.0, 2.0):
			return false
		s += 0.04
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var s: Vector2 = sand_span_at(t)
	var lo: float = s.x
	var hi: float = s.y
	if lo > hi:
		lo = height
		hi = height
	# shader: UV.y 0 at the slot, 1 at the floor
	_mat.set_shader_parameter("tail", 1.0 - hi / height)
	_mat.set_shader_parameter("head", 1.0 - lo / height)
	var until: float = time_until_pour(t)
	var warning: bool = until > 0.0 and until < warn
	_mat.set_shader_parameter("trickle", 1.0 if warning else 0.0)
	var hitting: bool = s.x <= 0.01 and s.y > 0.3
	if _splash.emitting != hitting:
		_splash.emitting = hitting
		_grains.emitting = hitting
	if _trickle.emitting != warning:
		_trickle.emitting = warning
		_cloud.emitting = warning
	WorldAudio.set_active(_loop, is_pouring_at(t))


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var s: Vector2 = sand_span_at(t)
	if s.x > s.y:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var y: float = to_local(body.global_position).y
			if s.x < y + 1.7 and s.y > y + 0.1:
				var n: Node = self
				while n != null and not n.has_method("fail"):
					n = n.get_parent()
				if n != null:
					n.call_deferred("fail", "hazard")
			return
