class_name JungleRaft
extends MovingPlatform
## Jungle Temple: a log raft poled up and down the river between two landings on the course clock
## (a MovingPlatform PATH, so a rider is carried with its full velocity and the bot can read
## offset_at). Five logs lashed side by side, a pole post with a jade lantern, and a gentle bob on
## the current (part of offset_at, so it is deterministic too). A wake of foam streams off it while
## it moves and it knocks against the landing at each end. Positioned like kit.mover.

const BARK := Color(0.42, 0.29, 0.18)
const LASH := Color(0.3, 0.36, 0.16)
const JADE := Color(0.25, 0.95, 0.65)

## Height (m) of the bob on the current.
@export var bob: float = 0.05

var _wake: GPUParticles3D
var _was_moving: bool = false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	_build_logs()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func _hums() -> bool:
	return false


func offset_at(time: float) -> Vector3:
	return super.offset_at(time) + Vector3(0, bob * sin(time * 2.1 + phase * 7.0), 0)


func _build_logs() -> void:
	# the logs run along the raft's longer horizontal side
	var long_x: bool = size.x >= size.z
	var length: float = size.x if long_x else size.z
	var width: float = size.z if long_x else size.x
	var along: Vector3 = Vector3.RIGHT if long_x else Vector3.BACK
	var across: Vector3 = Vector3.BACK if long_x else Vector3.RIGHT
	var n: int = 5
	var r: float = width / float(n) * 0.5
	var bark: StandardMaterial3D = Look.flat(BARK, 0.92)
	var ends: StandardMaterial3D = Look.flat(BARK.lightened(0.25), 0.9)
	for i: int in n:
		var off: Vector3 = across * (float(i) - float(n - 1) * 0.5) * r * 2.0 + Vector3(0, size.y * 0.5 - r, 0)
		var lg := Look.cylinder(r, length + (0.15 if i % 2 == 0 else -0.1), bark, off, -1.0, 9)
		lg.basis = JungleVine._lay(along)
		add_child(lg)
		for s: float in [-1.0, 1.0]:
			var cap := Look.cylinder(r * 0.92, 0.04, ends, off + along * s * (length * 0.5 + (0.08 if i % 2 == 0 else -0.05)), -1.0, 9)
			cap.basis = JungleVine._lay(along)
			add_child(cap)
	var lash: StandardMaterial3D = Look.flat(LASH, 0.9)
	for s: float in [-0.32, 0.32]:
		add_child(Look.box(along * 0.14 + Vector3(0, r * 2.0 + 0.04, 0) + across * width * 1.04, lash, along * s * length + Vector3(0, size.y * 0.5 - r, 0)))
	# a pole post with a little jade lantern at the back corner
	var post_at: Vector3 = along * (length * 0.5 - 0.35) + across * (width * 0.5 - 0.3)
	add_child(Look.cylinder(0.06, 1.6, Look.flat(BARK.darkened(0.25), 0.9), post_at + Vector3(0, size.y * 0.5 + 0.8, 0), 0.05, 6))
	add_child(Look.sphere(0.16, Look.flat(JADE, 0.3, 0.0, 2.2), post_at + Vector3(0, size.y * 0.5 + 1.65, 0)))
	_wake = Fx.emitter({"amount": 26, "lifetime": 1.4, "shape": "box",
		"extents": Vector3(size.x * 0.5, 0.05, size.z * 0.5), "dir": Vector3.UP, "spread": 60.0,
		"speed": Vector2(0.3, 1.0), "gravity": Vector3(0, -1.0, 0), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 0.7, "curve": "puff", "angle": Vector2(0, 360), "color": Color(0.9, 0.97, 0.95, 0.5),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": AABB(Vector3(-20, -4, -20), Vector3(40, 8, 40))})
	_wake.position = Vector3(0, -size.y * 0.5 - 0.1, 0)
	_wake.emitting = false
	add_child(_wake)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var v: float = (super.offset_at(t + 0.05) - super.offset_at(t)).length() / 0.05
	var moving: bool = v > 0.6
	_wake.emitting = moving
	if _was_moving and not moving:
		WorldAudio.at(self, "jungle_raft_bump", global_position, 0.7, 26.0)
	_was_moving = moving
