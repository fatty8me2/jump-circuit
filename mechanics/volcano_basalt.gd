class_name VolcanoBasalt
extends AnimatableBody3D
## Cinder Peak: a hexagonal basalt column standing in lava. Two kinds:
##  SINK  - stand on it and (after `sink_delay`) it sinks at `sink_speed`, down to `max_sink`;
##          step off and it rises back. Stay too long and it takes you under the surface
##          (the lava around it burns). Rider-driven, reset on respawn.
##  PULSE - rises and sinks on a rhythm (Game.course_time), like a slow piston: fully up for
##          `up_fraction` of the cycle, then it slides under the lava and comes back.
## Positioned at the centre of its TOP surface at rest.

enum Mode { SINK, PULSE }

@export var mode: Mode = Mode.SINK
## Hexagon circumradius of the top.
@export var radius: float = 1.3
## Length of the column below its top (reaches down into the lava).
@export var column: float = 9.0
@export var sink_delay: float = 0.15
@export var sink_speed: float = 1.0
@export var max_sink: float = 3.0
@export var rise_speed: float = 1.4
@export var period: float = 4.0
@export var phase: float = 0.0
@export var depth: float = 2.6
@export var up_fraction: float = 0.45
@export var move_fraction: float = 0.14

var _origin: Vector3
var _offset: float = 0.0
var _loaded: bool = false
var _load_time: float = 0.0
var _load_frame: int = -100
var _heat_mat: StandardMaterial3D
var _steam: GPUParticles3D
var _was_moving_down: bool = false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var shape := CylinderShape3D.new()
	shape.radius = radius * 0.9
	shape.height = column
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -column * 0.5, 0)
	add_child(cs)
	_build_visual()
	if mode == Mode.PULSE:
		add_to_group("course_clock")
		_offset = offset_at(Game.course_time)
	else:
		add_to_group("resettable")
	position = _origin + Vector3(0, _offset, 0)
	reset_physics_interpolation()


## PULSE: height of the top relative to rest at `time` (<= 0).
func offset_at(time: float) -> float:
	if mode != Mode.PULSE:
		return _offset
	var u: float = fposmod(time / period + phase, 1.0)
	if u < up_fraction:
		return 0.0
	u -= up_fraction
	if u < move_fraction:
		var k: float = u / move_fraction
		return -depth * k * k * (3.0 - 2.0 * k)
	var down: float = 1.0 - up_fraction - 2.0 * move_fraction
	u -= move_fraction
	if u < down:
		return -depth
	var k2: float = clampf((u - down) / move_fraction, 0.0, 1.0)
	return -depth * (1.0 - k2 * k2 * (3.0 - 2.0 * k2))


## PULSE: fully up (safe to stand on) at `time`.
func is_up_at(time: float) -> bool:
	return offset_at(time) > -0.03


## PULSE: seconds of "fully up" left from `time` (0 when not up).
func up_left(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (up_fraction - u) * period if u < up_fraction else 0.0


## PULSE: the column stays up over the whole window [now + a, now + b].
func is_up_between(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not is_up_at(time + s):
			return false
		s += 0.04
	return true


## Player contract: called every tick while stood on.
func apply_rider_load(_point: Vector3, _force: float) -> void:
	if mode != Mode.SINK:
		return
	if Engine.get_physics_frames() - _load_frame > 1:
		WorldAudio.at(self, "basalt_sink", global_position, 0.7, 30.0)
	_load_frame = Engine.get_physics_frames()


func reset_state() -> void:
	if mode != Mode.SINK:
		return
	_offset = 0.0
	_loaded = false
	_load_time = 0.0
	_load_frame = -100
	position = _origin
	reset_physics_interpolation()


func snap_to_clock() -> void:
	_offset = offset_at(Game.course_time)
	position = _origin + Vector3(0, _offset, 0)
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var moving_down: bool = false
	if mode == Mode.PULSE:
		var t: float = Game.course_time
		var o: float = offset_at(t)
		moving_down = o < _offset - 0.0005
		_offset = o
		if moving_down and not _was_moving_down:
			WorldAudio.at(self, "basalt_sink", global_position, 0.5, 30.0)
	else:
		# the rider re-arms the load every tick it stands here (apply_rider_load)
		_loaded = Engine.get_physics_frames() - _load_frame <= 1
		if _loaded:
			_load_time += dt
			if _load_time >= sink_delay:
				_offset = maxf(_offset - sink_speed * dt, -max_sink)
				moving_down = _offset > -max_sink
		else:
			_load_time = 0.0
			_offset = minf(_offset + rise_speed * dt, 0.0)
	_was_moving_down = moving_down
	position = _origin + Vector3(0, _offset, 0)
	var hot: float = clampf(-_offset / maxf(max_sink if mode == Mode.SINK else depth, 0.1), 0.0, 1.0)
	_heat_mat.emission_energy_multiplier = 0.6 + 4.0 * hot + (1.5 if moving_down else 0.0)
	if _steam.emitting != moving_down:
		_steam.emitting = moving_down


func _build_visual() -> void:
	var rock := Look.platform_material(Vector3(radius * 0.87, column * 0.5, radius * 0.87), "alt", true)
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.05
	cm.height = column
	cm.radial_segments = 6
	cm.rings = 1
	var body := Look.mesh_node(cm, rock, Vector3(0, -column * 0.5, 0))
	add_child(body)
	# a glowing seam round the top edge that runs hotter the deeper it has sunk
	_heat_mat = StandardMaterial3D.new()
	_heat_mat.albedo_color = Color(0.3, 0.08, 0.02)
	_heat_mat.emission_enabled = true
	_heat_mat.emission = Color(1.0, 0.4, 0.08)
	_heat_mat.emission_energy_multiplier = 0.6
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.86
	tm.outer_radius = radius * 1.02
	tm.rings = 6
	tm.ring_segments = 4
	var seam := Look.mesh_node(tm, _heat_mat, Vector3(0, -0.28, 0))
	seam.scale = Vector3(1, 0.4, 1)
	seam.rotation.y = PI / 6.0
	seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(seam)
	# hissing steam while it slides into the melt
	_steam = Fx.emitter({"amount": 18, "lifetime": 1.2, "emitting": false, "shape": "ring", "ring_radius": radius * 1.05,
		"ring_inner": radius * 0.8, "dir": Vector3.UP, "spread": 15.0, "speed": Vector2(1.5, 3.0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 0.9, "curve": "puff", "color": Color(0.8, 0.7, 0.6, 0.45),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "angle": Vector2(0, 360),
		"aabb": AABB(Vector3(-radius - 3.0, -column, -radius - 3.0), Vector3(radius * 2.0 + 6.0, column + 8.0, radius * 2.0 + 6.0))})
	_steam.position = Vector3(0, -0.4, 0)
	add_child(_steam)
