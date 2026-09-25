class_name DesertQuicksand
extends AnimatableBody3D
## Scarab Sands: a pit of quicksand. Its sand surface looks level with the floor, but the
## footing under it sinks while you stand on it (SINK m/s) and swallows you once you are
## `kill_depth` down; step off and it slowly firms up again. While in it the sand clings: your
## run is dragged down to about 6 m/s, so a jump out of it is short - and starts lower.
## Positioned at the centre of the sand surface; `size` is the pit's footprint (x, z).
## reset_state() firms it up at once (player respawn).

@export var size: Vector2 = Vector2(3.0, 3.0)
@export var kill_depth: float = 1.0
## Sinking and recovery speed (m/s).
@export var sink: float = 0.5
@export var recover: float = 1.2

## Fraction of your speed the sand takes away (target speed = run / (1 + STICK)).
const STICK: float = 0.5
const SLAB: float = 0.6

var _base: Vector3
var _depth: float = 0.0
var _load_tick: int = -100
var _was_loaded: bool = false
var _surface: MeshInstance3D
var _mat: ShaderMaterial
var _swirl: GPUParticles3D
var _plops: GPUParticles3D
var _gulp: GPUParticles3D
var _player: Node3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	add_to_group("resettable")
	_base = position
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, SLAB, size.y)
	var cs := CollisionShape3D.new()
	cs.shape = bs
	cs.position = Vector3(0, -SLAB * 0.5, 0)
	add_child(cs)
	_build_visual()


func _build_visual() -> void:
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 12
	pm.subdivide_depth = 12
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/desert_quicksand.gdshader")
	_mat.set_shader_parameter("radius", minf(size.x, size.y) * 0.5)
	_surface = Look.mesh_node(pm, _mat)
	# the sand surface stays level while the footing beneath it sinks (you sink INTO it)
	_surface.top_level = true
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	_surface.global_position = global_position + Vector3(0, 0.02, 0)
	var vis := AABB(Vector3(-size.x - 2, -2, -size.y - 2), Vector3(size.x * 2 + 4, 6, size.y * 2 + 4))
	var r: float = minf(size.x, size.y) * 0.5
	_swirl = Fx.emitter({"amount": 26, "lifetime": 1.0, "emitting": false, "shape": "ring", "ring_radius": r * 0.9,
		"ring_inner": r * 0.4, "ring_height": 0.05, "speed": Vector2(0.0, 0.2), "radial": Vector2(-3.0, -1.5),
		"additive": false, "size": 0.09, "color": Color(0.7, 0.5, 0.3, 0.9),
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	_swirl.top_level = true
	add_child(_swirl)
	_swirl.global_position = global_position + Vector3(0, 0.05, 0)
	_plops = Fx.emitter({"amount": 8, "lifetime": 0.7, "shape": "box", "extents": Vector3(size.x * 0.4, 0.02, size.y * 0.4),
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.4, 1.0), "gravity": Vector3(0, -3, 0), "additive": false,
		"size": 0.14, "curve": "pop", "color": Color(0.6, 0.42, 0.25, 0.8), "aabb": vis})
	_plops.top_level = true
	add_child(_plops)
	_plops.global_position = global_position + Vector3(0, 0.03, 0)
	_gulp = Fx.smoke({"amount": 24, "lifetime": 1.0, "shape": "box", "extents": Vector3(size.x * 0.3, 0.1, size.y * 0.3),
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(1.5, 3.5), "size": 1.0, "color": Color(0.9, 0.7, 0.45, 0.7), "aabb": vis})
	_gulp.top_level = true
	add_child(_gulp)
	_gulp.global_position = global_position + Vector3(0, 0.1, 0)


## Player contract: called every tick while stood on.
func apply_rider_load(_point: Vector3, _force: float) -> void:
	_load_tick = Engine.get_physics_frames()


## Player contract: the sand drags against your run.
func surface_velocity() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		_player = WorldAudio.local_player(self)
		if _player == null:
			return Vector3.ZERO
	var v: Vector3 = (_player as CharacterBody3D).velocity
	return Vector3(v.x, 0, v.z) * -STICK


func depth() -> float:
	return _depth


func reset_state() -> void:
	_depth = 0.0
	_load_tick = -100
	_was_loaded = false
	position = _base
	reset_physics_interpolation()
	_mat.set_shader_parameter("pull", 0.0)
	_swirl.emitting = false


func _physics_process(dt: float) -> void:
	var loaded: bool = Engine.get_physics_frames() - _load_tick <= 2
	if loaded:
		_depth = minf(_depth + sink * dt, kill_depth + 0.2)
	else:
		_depth = maxf(_depth - recover * dt, 0.0)
	position = _base - Vector3(0, _depth, 0)
	if loaded and not _was_loaded:
		_swirl.emitting = true
		WorldAudio.at(self, "quicksand_sink", global_position, 0.8, 30.0)
	elif not loaded and _was_loaded:
		_swirl.emitting = false
	_was_loaded = loaded
	_mat.set_shader_parameter("pull", clampf(_depth / kill_depth, 0.0, 1.0))
	if loaded and _depth >= kill_depth:
		_gulp.restart()
		var n: Node = self
		while n != null and not n.has_method("fail"):
			n = n.get_parent()
		if n != null:
			n.call_deferred("fail", "hazard")
		_load_tick = -100
