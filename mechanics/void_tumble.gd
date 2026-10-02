class_name VoidTumble
extends AnimatableBody3D
## The Void: a TUMBLING ROOM. A little cube of a room - four floors round it (a chessboard,
## parquet, diamond wallpaper, tiles with a window) and a door at each end - that turns over a
## quarter turn about its local X axis once every `period`, so a wall becomes the floor. It is a
## cube, so after every turn its top is flat again; only DURING the turn is it no place to stand
## (it throws you off). Telegraphed `warn` s ahead (at least 0.8): the trim round its faces burns
## brighter and brighter pink, it shudders and sheds grit, and it creaks.
## The turn fills the first `turn` s of each cycle, eased in and out; the rest of the cycle it is
## still. Pure function of Game.course_time, identical for every racer.

const PINK := Color(1.0, 0.36, 0.72)

@export var edge: float = 1.4
@export var period: float = 3.6
@export var turn: float = 0.6
@export var phase: float = 0.0
@export var warn: float = 0.95
## +1 / -1: which way it rolls.
@export var spin: float = 1.0

var _base_basis: Basis
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _grit: GPUParticles3D
var _thud: GPUParticles3D
var _was_turning: bool = false
var _was_warn: bool = false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_base_basis = basis
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * edge
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/void_room.gdshader")
	_mat.set_shader_parameter("half_size", edge * 0.5)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * edge
	_mesh = Look.mesh_node(bm, _mat)
	add_child(_mesh)
	var hot: Color = Fx.hot(PINK, 2.0)
	var vis := AABB(-Vector3.ONE * (edge + 3.0), Vector3.ONE * (edge * 2.0 + 6.0))
	_grit = Fx.emitter({"amount": 16, "lifetime": 0.8, "shape": "box", "extents": Vector3.ONE * edge * 0.5,
		"dir": Vector3.DOWN, "spread": 30.0, "speed": Vector2(0.3, 1.0), "gravity": Vector3(0, -6.0, 0),
		"facing": "mesh", "mesh": Fx.chunk_mesh(0.07), "color": Color(0.9, 0.88, 0.95), "curve": "shrink",
		"emitting": false, "aabb": vis})
	_grit.top_level = true
	add_child(_grit)
	_thud = Fx.burst({"amount": 22, "lifetime": 0.5, "shape": "box", "extents": Vector3(edge * 0.5, 0.05, edge * 0.5),
		"dir": Vector3.UP, "spread": 80.0, "speed": Vector2(1.0, 3.0), "size": 0.14, "tex": Fx.Tex.STAR,
		"color": hot, "aabb": vis})
	_thud.top_level = true
	add_child(_thud)
	_apply(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func _cycle(time: float) -> float:
	return time / period + phase


## Turned angle (radians) about local X at `time`.
func angle_at(time: float) -> float:
	var c: float = _cycle(time)
	var q: float = floorf(c)
	var u: float = (c - q) * period
	var k: float = clampf(u / maxf(turn, 0.01), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return (q + k) * PI * 0.5 * spin


func is_still_at(time: float) -> bool:
	return fposmod(_cycle(time), 1.0) * period >= turn


## Seconds until it next starts to turn.
func time_to_turn(time: float) -> float:
	return (1.0 - fposmod(_cycle(time), 1.0)) * period


## True when it stays still over the whole of [time + a, time + b].
func still_over(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not is_still_at(time + s):
			return false
		s += 0.04
	return is_still_at(time + b)


func snap_to_clock() -> void:
	_apply(Game.course_time)
	reset_physics_interpolation()


func _apply(time: float) -> void:
	basis = _base_basis * Basis(Vector3.RIGHT, angle_at(time))


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var still: bool = is_still_at(t)
	var left: float = time_to_turn(t)
	var warning: bool = still and left < warn
	var k: float = clampf(1.0 - left / warn, 0.0, 1.0) if warning else 0.0
	_mat.set_shader_parameter("edge_glow", 3.0 * k + (2.0 if not still else 0.0))
	# the shudder is the mesh only (the collision stays put until the turn begins)
	if warning:
		var amp: float = 0.025 + 0.04 * k
		_mesh.position = Vector3(sin(t * 83.0) * amp, 0.0, cos(t * 71.0) * amp)
	elif _mesh.position != Vector3.ZERO:
		_mesh.position = Vector3.ZERO
	if warning != _was_warn:
		_was_warn = warning
		_grit.global_position = global_position
		_grit.emitting = warning
		if warning:
			# SOUND: void_tumble_warn - a deep creak and grind of stone as the room gets ready to turn (~0.95 s ahead)
			WorldAudio.at(self, "void_tumble_warn", global_position, 0.7, 32.0)
	var turning: bool = not still
	if turning != _was_turning:
		_was_turning = turning
		if turning:
			# SOUND: void_tumble_turn - the room rolling over: a heavy rushing swing
			WorldAudio.at(self, "void_tumble_turn", global_position, 0.8, 34.0)
		else:
			_thud.global_position = global_position + Vector3(0, edge * 0.5 + 0.05, 0)
			_thud.restart()
			# SOUND: void_tumble_thud - it settles on its new floor with a soft boom
			WorldAudio.at(self, "void_tumble_thud", global_position, 0.7, 30.0)
