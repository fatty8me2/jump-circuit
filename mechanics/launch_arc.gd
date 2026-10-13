class_name LaunchArc
extends Node3D
## Launch arc (flow kit, docs/FLOW_KIT.md): a ramp whose lip throws you into a predictable arc with
## your speed kept. The node's origin is the FOOT (the middle of the ramp's low edge, where it meets
## the deck at feet height); the ramp climbs toward local -Z (yaw turns it) for `length` metres along
## the slope to the LIP, `length * sin(pitch)` higher. lip() is that point in the world. The ramp is a
## FlowSurface (gain 0), so a rider keeps all their speed up it.
## When the rider reaches the lip they leave with
##     horizontal speed hs = clamp(speed along the ramp, min_speed, cap)      (sideways drift halved)
##     vertical speed   vy = clamp(hs * tan(pitch) * lift, 3, 18)
## which is a pure function of hs: launch_velocity(hs) / arc_points(hs) / landing(hs, y) predict it
## with Ballistics, so a level can place the landing deck (and rings along the arc) exactly. Hold
## the stick forward in flight and the real arc matches the prediction.

@export var pitch_deg: float = 24.0
@export var width: float = 6.0
@export var length: float = 9.0
@export var min_speed: float = 8.0
@export var cap: float = 30.0
@export var lift: float = 1.0

var ramp: FlowSurface
var launches: int = 0

const EARLY: int = -50
const REARM_SECONDS: float = 0.6

var _lip_local: Vector3 = Vector3.ZERO
var _area: Area3D
var _last_tick: int = -100000
var _launched_tick: int = -100000
var _lip_mat: StandardMaterial3D
var _burst: GPUParticles3D


func _ready() -> void:
	process_physics_priority = KitUtil.EARLY
	_build()


func _build() -> void:
	var th: float = deg_to_rad(pitch_deg)
	var thick: float = 0.6
	ramp = FlowSurface.new()
	ramp.gain = 0.0
	ramp.cap = 34.0
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thick, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	ramp.add_child(cs)
	_lip_local = Vector3(0, length * sin(th), -length * cos(th))
	var normal := Vector3(0, cos(th), sin(th))
	ramp.position = _lip_local * 0.5 - normal * (thick * 0.5)
	ramp.rotation_degrees.x = pitch_deg
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/strip.gdshader")
	m.set_shader_parameter("half_size", Vector3(width, thick, length) * 0.5)
	var col: Color = Look.c("accent2").lerp(Color(0.55, 1.0, 0.9), 0.3)
	m.set_shader_parameter("arrow_color", Color(col.r, col.g, col.b))
	m.set_shader_parameter("scroll_speed", 5.0)
	m.set_shader_parameter("glow", 1.4)
	var bm := BoxMesh.new()
	bm.size = Vector3(width, thick, length)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	ramp.add_child(mi)
	add_child(ramp)
	# a glowing lip bar across the edge, so you can see where the throw happens
	_lip_mat = (Look.flat(col, 0.3, 0.0, 2.2).duplicate()) as StandardMaterial3D
	add_child(Look.box(Vector3(width, 0.14, 0.3), _lip_mat, _lip_local + Vector3(0, 0.02, 0.12)))
	# trigger over the last stretch of ramp
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var acs := CollisionShape3D.new()
	var abs_ := BoxShape3D.new()
	abs_.size = Vector3(width, 6.0, 4.0)
	acs.shape = abs_
	_area.add_child(acs)
	_area.position = _lip_local + Vector3(0, 0.0, 1.4)
	add_child(_area)
	_burst = Fx.sparks({"amount": 26, "lifetime": 0.45, "shape": "box", "extents": Vector3(width * 0.4, 0.05, 0.2),
		"dir": Vector3(0, 1, -1).normalized(), "spread": 35.0, "speed": Vector2(5.0, 11.0),
		"color": Color(col.r * 2.2, col.g * 2.2, col.b * 2.2), "aabb": AABB(Vector3(-6, -3, -8), Vector3(12, 8, 12))})
	_burst.position = _lip_local + Vector3(0, 0.1, 0.2)
	add_child(_burst)


## Direction of the ramp on the ground plane (the way you run up it).
func forward() -> Vector3:
	var f: Vector3 = -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


## The lip in world space (the launch leaves from here).
func lip() -> Vector3:
	return global_transform * (Vector3(0, length * sin(deg_to_rad(pitch_deg)), -length * cos(deg_to_rad(pitch_deg))))


## The velocity a rider whose speed along the ramp is `hs` leaves with.
func launch_velocity(hs: float) -> Vector3:
	var h: float = clampf(hs, min_speed, cap)
	var vy: float = clampf(h * tan(deg_to_rad(pitch_deg)) * lift, 3.0, 18.0)
	return forward() * h + Vector3(0, vy, 0)


## Positions along the flight from the lip for a launch at `hs` (hold-forward Ballistics model).
func arc_points(hs: float, duration: float = 2.5) -> PackedVector3Array:
	return Ballistics.arc(KitUtil.tuning(), lip(), launch_velocity(hs), duration)


## Where a launch at `hs` comes down through height `y` (world).
func landing(hs: float, y: float) -> Vector3:
	return Ballistics.landing_point(KitUtil.tuning(), lip(), launch_velocity(hs), y)


func launched_within(seconds: float) -> bool:
	return float(Engine.get_physics_frames() - _launched_tick) / float(Engine.physics_ticks_per_second) <= seconds


func _physics_process(dt: float) -> void:
	var p: Player = KitUtil.player_in(_area)
	if p == null:
		return
	var now: int = Engine.get_physics_frames()
	if now - _last_tick < int(REARM_SECONDS * float(Engine.physics_ticks_per_second)):
		return
	var fwd: Vector3 = forward()
	var hv := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var along: float = hv.dot(fwd)
	var s: float = (p.global_position - lip()).dot(fwd)
	# the throw happens on the tick that carries the rider over the lip
	if s + maxf(along, 0.0) * dt * 1.01 < 0.0:
		return
	if s > 0.8:
		return   # already past it (dropped in from the side)
	_last_tick = now
	_launched_tick = now
	launches += 1
	var side: Vector3 = hv - fwd * along
	var v: Vector3 = launch_velocity(along) + side * 0.5
	p.flow_launch(v)
	_burst.restart()
	_lip_mat.emission_energy_multiplier = 6.0
	var tw: Tween = create_tween()
	tw.tween_property(_lip_mat, "emission_energy_multiplier", 2.2, 0.5)
	WorldAudio.at(self, "flow_launch", global_position, 0.9, 55.0, 0.03)
