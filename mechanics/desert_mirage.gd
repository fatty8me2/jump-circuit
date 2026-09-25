class_name DesertMirage
extends AnimatableBody3D
## Scarab Sands: a mirage - a sandstone slab that is only real part of the time, fading in and
## out with the heat on a fixed rhythm (Game.course_time; a blink variant). It never just
## vanishes: for `warn` seconds before it goes, it wavers harder and harder, its rim flares
## and it turns glassy; while gone a faint heat ghost hangs there, and for `warn` seconds
## before it returns the ghost fills back in. Solid only while real. Positioned like a
## platform (centre of the slab).

@export var size: Vector3 = Vector3(2.2, 0.5, 2.2)
@export var period: float = 3.0
@export var on_fraction: float = 0.55
@export var phase: float = 0.0
@export var warn: float = 0.7

const GHOST: float = 0.14

var _shape: CollisionShape3D
var _mat: ShaderMaterial
var _solid: bool = true
var _fx_on: bool = true
var _warned: bool = false
var _fade: GPUParticles3D
var _form: GPUParticles3D
var _heat: GPUParticles3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	var box := BoxShape3D.new()
	box.size = size
	_shape = CollisionShape3D.new()
	_shape.shape = box
	add_child(_shape)
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_width = 4
	bm.subdivide_depth = 4
	bm.subdivide_height = 2
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/desert_mirage.gdshader")
	_mat.set_shader_parameter("half_size", size * 0.5)
	var mi := Look.mesh_node(bm, _mat)
	add_child(mi)
	var vis := AABB(-size * 0.5 - Vector3(2, 2, 2), size + Vector3(4, 6, 4))
	var gold: Color = Fx.hot(Color(1.0, 0.8, 0.4), 2.0)
	_fade = Fx.burst({"amount": 30, "lifetime": 0.9, "explosiveness": 0.6, "shape": "box", "extents": size * 0.5,
		"dir": Vector3.UP, "spread": 40.0, "speed": Vector2(0.5, 2.0), "gravity": Vector3(0, 1.5, 0),
		"damping": Vector2(0.5, 1.5), "size": 0.18, "tex": Fx.Tex.STAR, "color": gold, "turbulence": 0.8, "aabb": vis})
	add_child(_fade)
	_form = Fx.burst({"amount": 26, "lifetime": 0.45, "explosiveness": 0.9, "shape": "box",
		"extents": size * 0.5 + Vector3(0.8, 0.5, 0.8), "speed": Vector2.ZERO, "radial": Vector2(-12.0, -8.0),
		"size": 0.16, "tex": Fx.Tex.STAR, "curve": "pop", "color": Fx.hot(Color(0.3, 1.0, 0.9), 2.0), "aabb": vis})
	add_child(_form)
	# heat rising off it all the time (thicker while it is only a ghost)
	_heat = Fx.emitter({"amount": 10, "lifetime": 1.4, "preprocess": 1.4, "shape": "box",
		"extents": Vector3(size.x * 0.45, 0.05, size.z * 0.45), "dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.6, 1.2),
		"turbulence": 1.0, "tex": Fx.Tex.DOT, "size": 0.12, "color": Color(2.0, 1.5, 0.8, 0.8), "curve": "pop", "aabb": vis})
	_heat.position = Vector3(0, size.y * 0.5, 0)
	add_child(_heat)
	_fx_on = is_on_at(Game.course_time)
	_apply(Game.course_time)


func _u(time: float) -> float:
	return fposmod(time / period + phase, 1.0)


func is_on_at(time: float) -> bool:
	return _u(time) < on_fraction


## Seconds of solidity left (0 while gone).
func time_until_off(time: float) -> float:
	var u: float = _u(time)
	return (on_fraction - u) * period if u < on_fraction else 0.0


## Seconds until it is real again (0 while solid).
func time_until_on(time: float) -> float:
	var u: float = _u(time)
	return 0.0 if u < on_fraction else (1.0 - u) * period


func _apply(t: float) -> void:
	var on: bool = is_on_at(t)
	var solidity: float = 1.0
	var shimmer: float = 0.0
	if on:
		var left: float = time_until_off(t)
		if left < warn:
			var k: float = 1.0 - left / warn
			shimmer = k
			solidity = lerpf(1.0, 0.55, k) * (0.85 + 0.15 * sin(t * 31.0))
	else:
		var until: float = time_until_on(t)
		shimmer = 0.6
		solidity = GHOST
		if until < warn:
			var k2: float = 1.0 - until / warn
			solidity = lerpf(GHOST, 0.7, k2)
			shimmer = lerpf(0.6, 1.0, k2)
	_mat.set_shader_parameter("solidity", solidity)
	_mat.set_shader_parameter("shimmer", shimmer)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	var on: bool = is_on_at(t)
	var warning: bool = (on and time_until_off(t) < warn) or (not on and time_until_on(t) < warn)
	if warning and not _warned:
		WorldAudio.at(self, "mirage_shimmer", global_position, 0.6, 30.0)
	_warned = warning
	if on == _fx_on:
		return
	_fx_on = on
	(_form if on else _fade).restart()


func _physics_process(_dt: float) -> void:
	var on: bool = is_on_at(Game.course_time)
	if on != _solid:
		_solid = on
		_shape.set_deferred("disabled", not on)
