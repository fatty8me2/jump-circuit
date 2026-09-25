class_name DesertDustDevil
extends Node3D
## Scarab Sands: a dust devil - a whirlwind that wanders back and forth along `points`
## (offsets from where it starts, eased ping-pong like MovingPlatform; a pure function of
## Game.course_time). Step into its funnel and it lifts you (an updraft, gravity is 30 up /
## 42 down) and carries you along with it; at the top you float out over the lip. Ride it up
## to ledges you could never jump to, or across a gap. Positioned at the foot of the funnel.

@export var radius: float = 1.6
@export var height: float = 9.0
@export var points: Array[Vector3] = [Vector3.ZERO]
@export var period: float = 6.0
@export var phase: float = 0.0
@export var dwell: float = 0.12
## Upward acceleration inside the funnel, and the rise speed it will not push past.
@export var push: float = 72.0
@export var max_rise: float = 8.0
## How hard it drags you along with it (1/s) and toward its axis (1/s^2).
@export var carry: float = 3.0
@export var center_pull: float = 2.0

var _origin: Vector3
var _area: Area3D
var _spin: Node3D
var _loop: AudioStreamPlayer3D


func _ready() -> void:
	_origin = position
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	_area.position = Vector3(0, height * 0.5, 0)
	add_child(_area)
	_build_visual()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	_loop = WorldAudio.loop("dustdevil_loop", self, -6.0, 28.0, 5.0)
	if _loop != null:
		_loop.position = Vector3(0, 2.0, 0)


func _build_visual() -> void:
	_spin = Node3D.new()
	_spin.set_script(preload("res://visual/spin.gd"))
	_spin.set("period", -0.9)
	add_child(_spin)
	var shader: Shader = preload("res://visual/desert_devil.gdshader")
	for i: int in 2:
		var cm := CylinderMesh.new()
		cm.bottom_radius = radius * (0.35 + 0.15 * float(i))
		cm.top_radius = radius * (1.25 + 0.35 * float(i))
		cm.height = height + 1.5
		cm.radial_segments = 20
		cm.rings = 4
		cm.cap_top = false
		cm.cap_bottom = false
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("spin", 1.4 + 0.5 * float(i))
		m.set_shader_parameter("opacity", 0.6 - 0.2 * float(i))
		var mi := Look.mesh_node(cm, m, Vector3(0, (height + 1.5) * 0.5, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spin.add_child(mi)
	var vis := AABB(Vector3(-radius * 3, -1, -radius * 3), Vector3(radius * 6, height + 6, radius * 6))
	# grains whirling up the funnel (they ride the spinning holder)
	var grains: GPUParticles3D = Fx.emitter({"amount": 70, "lifetime": 1.6, "preprocess": 1.6, "local": true,
		"shape": "ring", "ring_radius": radius * 0.9, "ring_inner": radius * 0.3, "ring_height": 0.4,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(height * 0.45, height * 0.7), "radial": Vector2(0.5, 1.5),
		"additive": false, "size": 0.1, "color": Color(0.85, 0.66, 0.42, 0.9), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": vis})
	_spin.add_child(grains)
	# a skirt of dust boiling round the foot
	var skirt: GPUParticles3D = Fx.emitter({"amount": 18, "lifetime": 1.2, "preprocess": 1.2, "shape": "ring",
		"ring_radius": radius * 1.1, "ring_inner": radius * 0.5, "ring_height": 0.1, "dir": Vector3.UP, "spread": 40.0,
		"speed": Vector2(0.8, 2.0), "radial": Vector2(0.5, 2.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.6,
		"curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-90, 90), "color": Color(0.92, 0.75, 0.5, 0.5),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis})
	skirt.position = Vector3(0, 0.2, 0)
	add_child(skirt)
	# loose debris (dry leaves, pebbles) whipped round high up
	var debris: GPUParticles3D = Fx.emitter({"amount": 10, "lifetime": 2.5, "preprocess": 2.5, "local": true,
		"shape": "ring", "ring_radius": radius * 1.1, "ring_inner": radius * 0.8, "ring_height": height * 0.8,
		"dir": Vector3.UP, "spread": 30.0, "speed": Vector2(0.5, 1.5), "tex": Fx.Tex.PETAL, "additive": false, "size": 0.2,
		"angle": Vector2(0, 360), "spin": Vector2(-400, 400), "color": Color(0.55, 0.4, 0.22),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	debris.position = Vector3(0, height * 0.5, 0)
	_spin.add_child(debris)


## Offset of the funnel's foot from its start at `time` (eased ping-pong through `points`).
func offset_at(time: float) -> Vector3:
	if points.size() < 2:
		return points[0] if points.size() == 1 else Vector3.ZERO
	var u: float = fposmod(time / maxf(period, 0.01) + phase, 1.0)
	var legs: int = points.size() - 1
	var tri: float = 1.0 - absf(u * 2.0 - 1.0)
	var f: float = tri * float(legs)
	var leg: int = mini(int(f), legs - 1)
	var k: float = f - float(leg)
	k = clampf((k - dwell) / maxf(1.0 - 2.0 * dwell, 0.01), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return points[leg].lerp(points[leg + 1], k)


## World position of the funnel's foot at `time` (bots, level helpers).
func foot_at(time: float) -> Vector3:
	var parent_xf: Transform3D = (get_parent() as Node3D).global_transform if get_parent() is Node3D else Transform3D.IDENTITY
	return parent_xf * (_origin + offset_at(time))


func snap_to_clock() -> void:
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	position = _origin + offset_at(t)
	var vel: Vector3 = (offset_at(t + 0.05) - offset_at(t - 0.05)) / 0.1
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var dv := Vector3(0, push * dt, 0)
			if p.velocity.y > max_rise:
				dv.y = 0.0
			var rel: Vector3 = vel - Vector3(p.velocity.x, 0, p.velocity.z)
			var to_axis: Vector3 = global_position - p.global_position
			to_axis.y = 0.0
			dv += rel * carry * dt + to_axis * center_pull * dt
			p.add_impulse(dv)
