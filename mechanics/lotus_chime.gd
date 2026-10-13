class_name LotusChime
extends Node3D
## Lotus Drift: a WIND CHIME. A little pavilion-eave frame with a ring of glass and bronze tubes
## hanging from it, swaying in the breeze. Run past within `radius` and it rings: the faster you
## pass, the harder it rings and the further the sparkle flies, so a clean fast line plays a
## pentatonic phrase down the course (each chime has its own note, `note` 0..4). Nothing here
## affects play; it is the level's way of showing you are in the flow.
## Node origin = the top of the hanging cord (the eave); the tubes hang below it.

@export var note: int = 0
@export var radius: float = 5.0
@export var height: float = 2.0
@export var tint: Color = Color(1.0, 0.8, 0.5)

const NOTES: Array[float] = [1.0, 1.122, 1.26, 1.498, 1.682]

var _tubes: Array[Node3D] = []
var _hub: Node3D
var _swing: float = 0.0
var _ring: float = 0.0
var _cool: float = 0.0
var _phase: float = 0.0
var _player: Player
var _spark: GPUParticles3D


func _ready() -> void:
	_phase = float(get_instance_id() % 628) / 100.0
	var wood := Look.flat(Color(0.3, 0.18, 0.13), 0.8)
	var metal := Look.flat(Color(0.86, 0.72, 0.4), 0.3, 0.7)
	var glass := Look.flat(tint, 0.2, 0.0, 1.2)
	# the cord and the disc the tubes hang from
	add_child(Look.cylinder(0.012, height * 0.45, wood, Vector3(0, -height * 0.225, 0), -1.0, 4))
	_hub = Node3D.new()
	_hub.position = Vector3(0, -height * 0.45, 0)
	add_child(_hub)
	_hub.add_child(Look.cylinder(0.26, 0.05, wood, Vector3.ZERO, 0.24, 12))
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var l: float = height * (0.4 + 0.1 * float(i % 3))
		var holder := Node3D.new()
		holder.position = Vector3(cos(a) * 0.19, -0.03, sin(a) * 0.19)
		_hub.add_child(holder)
		holder.add_child(Look.cylinder(0.011, 0.14, wood, Vector3(0, -0.07, 0), -1.0, 4))
		holder.add_child(Look.cylinder(0.04, l, metal if i % 2 == 0 else glass, Vector3(0, -0.14 - l * 0.5, 0), -1.0, 8))
		_tubes.append(holder)
	# the clapper and its sail
	_hub.add_child(Look.cylinder(0.012, height * 0.5, wood, Vector3(0, -height * 0.25, 0), -1.0, 4))
	_hub.add_child(Look.sphere(0.06, metal, Vector3(0, -height * 0.5, 0)))
	_hub.add_child(Look.box(Vector3(0.22, 0.3, 0.012), Look.flat(Color(1.0, 0.9, 0.7), 0.9, 0.0, 0.8), Vector3(0, -height * 0.5 - 0.22, 0)))
	_spark = Fx.burst({"amount": 14, "lifetime": 1.1, "tex": Fx.Tex.STAR, "size": 0.16, "shape": "sphere", "radius": 0.2,
		"speed": Vector2(0.4, 1.6), "gravity": Vector3(0, -0.6, 0), "color": Fx.hot(tint, 2.4), "curve": "shrink",
		"aabb": AABB(Vector3(-3, -4, -3), Vector3(6, 6, 6))})
	_spark.position = Vector3(0, -height * 0.7, 0)
	add_child(_spark)


func _process(dt: float) -> void:
	_cool = maxf(_cool - dt, 0.0)
	var t: float = Time.get_ticks_msec() * 0.001
	var breeze: float = 0.07 * sin(t * 0.9 + _phase) + 0.04 * sin(t * 1.9 + _phase * 2.0)
	_ring = maxf(_ring - dt * 1.4, 0.0)
	_swing = lerpf(_swing, 0.0, 1.0 - exp(-dt * 1.2))
	var sway: float = breeze + _swing * sin(t * 7.0) * 0.5
	if _hub != null:
		_hub.rotation = Vector3(sway * 0.8, _phase + t * 0.15, sway)
	for i: int in _tubes.size():
		_tubes[i].rotation = Vector3(0.05 * sin(t * 6.0 + float(i)) * _ring, 0, 0.06 * sin(t * 5.0 + float(i) * 1.7) * _ring)
	if _player == null or not is_instance_valid(_player):
		_player = WorldAudio.local_player(self) as Player
	if _player == null or _cool > 0.0:
		return
	var p: Vector3 = _player.global_position
	var near := Vector3(global_position.x, p.y, global_position.z)
	if p.distance_to(near) > radius or absf(p.y - (global_position.y - height)) > radius * 1.4:
		return
	var sp: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	if sp < 3.0:
		return
	_cool = 1.1
	_ring = clampf(sp / 22.0 + 0.3, 0.3, 1.0)
	_swing = _ring
	_spark.restart()
	_spark.emitting = true
	# SOUND: lotus_chime - a few glass-and-bronze tubes struck, pentatonic, brighter when you pass faster
	WorldAudio.at(self, "lotus_chime", global_position - Vector3(0, height * 0.6, 0), 0.5 + 0.5 * _ring, 36.0, 0.0)
