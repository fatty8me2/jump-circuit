class_name SakuraPetal
extends AnimatableBody3D
## Sakura Peaks: a FALLING-BLOSSOM PLATFORM. A great cherry petal floating in the air, bobbing a
## little on the breeze. Stand on it and (after `sink_delay`) it sinks under your weight at
## `sink_speed`, down to `max_sink`, shedding petals; step off and it floats slowly back up.
## Dawdle and the next hop is out of reach. Rider-driven (reset on respawn); the bob is a pure
## function of the course clock. Readable: the petal blushes deeper and sheds as it sinks.
## Positioned at the centre of its TOP surface at rest.

@export var radius: float = 1.3
@export var sink_delay: float = 0.2
@export var sink_speed: float = 1.1
@export var max_sink: float = 3.5
@export var rise_speed: float = 0.9
@export var tint: Color = Color(1.0, 0.72, 0.82)
@export var bob: float = 0.08
@export var bob_period: float = 3.0
@export var bob_phase: float = 0.0
## Turn of the petal's shape round the vertical (looks only).
@export var turn: float = 0.0

var _origin: Vector3
var _offset: float = 0.0
var _load_time: float = 0.0
var _load_frame: int = -100
var _sinking: bool = false
var _skin: StandardMaterial3D
var _shed: GPUParticles3D
var _shape_root: Node3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.4
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.2, 0)
	add_child(cs)
	_build_visual()
	add_to_group("resettable")
	add_to_group("course_clock")
	position = _origin + Vector3(0, _bob_at(Game.course_time), 0)
	reset_physics_interpolation()


func _bob_at(time: float) -> float:
	return bob * sin(TAU * (time / maxf(bob_period, 0.01) + bob_phase))


## How far it has sunk (>= 0).
func sunk() -> float:
	return -_offset


## Player contract: called every tick while stood on.
func apply_rider_load(_point: Vector3, _force: float) -> void:
	if Engine.get_physics_frames() - _load_frame > 1:
		# SOUND: a soft papery sigh as the petal starts to give under you
		WorldAudio.at(self, "sakura_petal_sink", global_position, 0.6, 30.0)
	_load_frame = Engine.get_physics_frames()


func reset_state() -> void:
	_offset = 0.0
	_load_time = 0.0
	_load_frame = -100
	position = _origin + Vector3(0, _bob_at(Game.course_time), 0)
	reset_physics_interpolation()


func snap_to_clock() -> void:
	position = _origin + Vector3(0, _offset + _bob_at(Game.course_time), 0)
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var loaded: bool = Engine.get_physics_frames() - _load_frame <= 1
	_sinking = false
	if loaded:
		_load_time += dt
		if _load_time >= sink_delay:
			_offset = maxf(_offset - sink_speed * dt, -max_sink)
			_sinking = _offset > -max_sink
	else:
		_load_time = 0.0
		_offset = minf(_offset + rise_speed * dt, 0.0)
	position = _origin + Vector3(0, _offset + _bob_at(Game.course_time), 0)


func _process(_dt: float) -> void:
	var k: float = clampf(-_offset / maxf(max_sink, 0.1), 0.0, 1.0)
	_skin.albedo_color = tint.lerp(Color(0.9, 0.36, 0.52), k)
	_skin.emission_energy_multiplier = 0.25 + 0.9 * k
	if _shed.emitting != _sinking:
		_shed.emitting = _sinking


func _build_visual() -> void:
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = tint
	_skin.roughness = 0.85
	_skin.emission_enabled = true
	_skin.emission = Color(1.0, 0.55, 0.68)
	_skin.emission_energy_multiplier = 0.25
	_skin.rim_enabled = true
	_skin.rim = 0.5
	_shape_root = Node3D.new()
	_shape_root.rotation.y = turn
	add_child(_shape_root)
	# the petal: a broad flattened lobe, a notched tip (two smaller lobes) and a pale heart, all
	# with the top surface at y = 0
	var lobe := Look.sphere(1.0, _skin, Vector3(0, -0.2, 0.1 * radius))
	lobe.scale = Vector3(radius * 1.05, 0.22, radius * 1.0)
	_shape_root.add_child(lobe)
	for sx: float in [-1.0, 1.0]:
		var tip := Look.sphere(1.0, _skin, Vector3(sx * radius * 0.32, -0.21, -radius * 0.62))
		tip.scale = Vector3(radius * 0.5, 0.2, radius * 0.55)
		_shape_root.add_child(tip)
	var heart := Look.sphere(1.0, SakuraDecor.blossom(Color(1.0, 0.92, 0.94)), Vector3(0, -0.15, radius * 0.45))
	heart.scale = Vector3(radius * 0.35, 0.12, radius * 0.3)
	_shape_root.add_child(heart)
	# a few veins
	for i: int in 3:
		var v := Look.box(Vector3(0.05, 0.02, radius * 1.2), SakuraDecor.mat(Color(0.95, 0.5, 0.65), 0.8), Vector3((float(i) - 1.0) * radius * 0.3, 0.005, 0.0))
		v.rotation.y = (float(i) - 1.0) * 0.25
		_shape_root.add_child(v)
	_shed = Fx.emitter({"amount": 16, "lifetime": 2.2, "emitting": false, "shape": "sphere", "radius": radius * 0.8,
		"dir": Vector3(0.2, -1, 0), "spread": 40.0, "speed": Vector2(0.5, 1.4), "gravity": Vector3(0, -1.2, 0),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.16, "curve": "flat", "pick": SakuraFx.PETALS,
		"angle": Vector2(0, 360), "spin": Vector2(-250, 250), "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": AABB(Vector3(-radius - 4.0, -8.0, -radius - 4.0), Vector3(radius * 2.0 + 8.0, 10.0, radius * 2.0 + 8.0))})
	_shed.position = Vector3(0, -0.3, 0)
	add_child(_shed)
