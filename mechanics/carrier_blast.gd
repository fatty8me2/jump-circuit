class_name CarrierBlast
extends Area3D
## Super Carrier: JET BLAST. A parked jet runs its engines up on a fixed rhythm (Game.course_time) and
## its exhaust shoves anything behind it along local -Z. The node sits on the deck under the nozzles;
## the blast fills a box `size` (width, height, length) reaching back from here. Readable: for `warn`
## seconds first the engines spool (the nozzles glow and heat shimmer pours out), then the blast
## roars for `blast_time` seconds. Grounded you can just about lean into it; in the air it throws you.
##   cycle (s into the period): 0 spool .. warn -> ramp up .. full blast .. ramp down -> idle

@export var size: Vector3 = Vector3(5.0, 4.0, 16.0)
@export var push: float = 70.0
@export var period: float = 5.0
@export var phase: float = 0.0
@export var warn: float = 1.2
@export var blast_time: float = 1.6
## Nozzle height (visual) and spacing (twin engines, 0 = one).
@export var nozzle_height: float = 1.5
@export var nozzle_gap: float = 1.1

const RAMP: float = 0.2

var _streaks: GPUParticles3D
var _haze: GPUParticles3D
var _heat: GPUParticles3D
var _cones: Array[Node3D] = []
var _cone_mat: StandardMaterial3D
var _was_on: bool = false
var _was_spool: bool = false
var _roar: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, size.y * 0.5, -size.z * 0.5)
	add_child(cs)
	_build()
	_roar = WorldAudio.loop("carrier_jet_roar", self, -6.0, size.z + 20.0, 6.0, false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_on = is_blowing_at(Game.course_time)
	_apply(Game.course_time)


# ---- the rhythm ------------------------------------------------------------------------------------

func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## 0..1 blast strength at `time`.
func strength_at(time: float) -> float:
	var s: float = _s(time) - warn
	if s < 0.0:
		return 0.0
	if s < RAMP:
		return smoothstep(0.0, RAMP, s)
	if s < blast_time:
		return 1.0
	if s < blast_time + RAMP:
		return 1.0 - smoothstep(blast_time, blast_time + RAMP, s)
	return 0.0


func is_blowing_at(time: float) -> bool:
	return strength_at(time) > 0.0


func is_spooling_at(time: float) -> bool:
	return _s(time) < warn


## No blast anywhere over [time + a, time + b].
func is_calm_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_blowing_at(time + s):
			return false
		s += 0.04
	return not is_blowing_at(time + b)


## Seconds until the next blast begins (0 while one is on).
func time_until_blast(time: float) -> float:
	if is_blowing_at(time):
		return 0.0
	var s: float = _s(time)
	return warn - s if s < warn else period - s + warn


# ---- gameplay ----------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	var e: float = strength_at(t)
	if e <= 0.0:
		return
	var dir: Vector3 = -global_basis.z
	dir.y = 0.0
	dir = dir.normalized()
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			# strongest right behind the nozzles, easing off down the plume
			var d: float = clampf(-to_local(body.global_position).z / size.z, 0.0, 1.0)
			(body as Player).add_impulse(dir * push * e * (1.0 - 0.35 * d) * dt)


# ---- look ------------------------------------------------------------------------------------------

func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var e: float = strength_at(t)
	var s: float = _s(t)
	var spool: bool = s < warn
	var glow: float = e
	if spool:
		glow = 0.35 * (s / warn)
	_streaks.amount_ratio = maxf(e, 0.0)
	if _streaks.emitting != (e > 0.02):
		_streaks.emitting = e > 0.02
	if _haze.emitting != (spool or e > 0.02):
		_haze.emitting = spool or e > 0.02
	if _heat.emitting != (e > 0.3):
		_heat.emitting = e > 0.3
	for c: Node3D in _cones:
		c.visible = glow > 0.03
		c.scale = Vector3(1.0, 1.0, 0.4 + glow * 0.9)
	_cone_mat.emission_energy_multiplier = 0.4 + 2.2 * glow
	var on: bool = e > 0.0
	if spool and not _was_spool:
		WorldAudio.at(self, "carrier_jet_spool", global_position + Vector3(0, nozzle_height, 0), 0.8, 45.0)
	_was_spool = spool
	_was_on = on
	if _roar != null:
		WorldAudio.set_active(_roar, glow > 0.05)
		_roar.volume_db = -8.0 + linear_to_db(maxf(glow, 0.05))


func _build() -> void:
	var vis := AABB(Vector3(-size.x - 2, -1, -size.z - 6), Vector3(size.x * 2 + 4, size.y + 8, size.z + 10))
	# afterburner cones out of each nozzle (visual only; scale and glow follow the throttle)
	_cone_mat = Look.flat(Color(1.0, 0.55, 0.25), 0.3, 0.0, 0.4).duplicate() as StandardMaterial3D
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.albedo_color = Color(1.0, 0.6, 0.3, 0.55)
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var xs: Array[float] = [0.0]
	if nozzle_gap > 0.0:
		xs = [-nozzle_gap * 0.5, nozzle_gap * 0.5]
	for x: float in xs:
		var holder := Node3D.new()
		holder.position = Vector3(x, nozzle_height, 0)
		add_child(holder)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.42
		cm.height = 2.6
		cm.radial_segments = 12
		cm.rings = 1
		var cone := Look.mesh_node(cm, _cone_mat)
		cone.rotation.x = -PI * 0.5
		cone.position = Vector3(0, 0, -1.3)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pivot := Node3D.new()
		holder.add_child(pivot)
		pivot.add_child(cone)
		_cones.append(pivot)
	# the exhaust: hot streaks tearing back along the plume, a boil of heat shimmer, grey haze
	_streaks = Fx.emitter({"amount": int(clampf(size.z * 3.0, 24, 90)), "lifetime": 0.55, "emitting": false,
		"shape": "box", "extents": Vector3(size.x * 0.18, 0.3, 0.2), "offset": Vector3(0, nozzle_height, -0.4),
		"dir": Vector3(0, 0.02, -1), "spread": 7.0, "speed": Vector2(size.z * 1.4, size.z * 2.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.08, 1.4), "color": Color(1.6, 1.3, 1.0, 0.55),
		"fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0]), "aabb": vis})
	add_child(_streaks)
	_haze = Fx.smoke({"amount": int(clampf(size.z * 1.2, 10, 40)), "lifetime": 1.2, "one_shot": false, "explosiveness": 0.0,
		"emitting": false, "shape": "box", "extents": Vector3(size.x * 0.2, 0.3, 0.3), "offset": Vector3(0, nozzle_height, -0.8),
		"dir": Vector3(0, 0.15, -1), "spread": 18.0, "speed": Vector2(size.z * 0.5, size.z * 0.9), "damping": Vector2(1.0, 2.0),
		"size": 2.2, "color": Color(0.75, 0.74, 0.72, 0.28), "aabb": vis})
	add_child(_haze)
	_heat = Fx.emitter({"amount": 20, "lifetime": 0.35, "emitting": false, "shape": "box",
		"extents": Vector3(maxf(nozzle_gap * 0.5, 0.2), 0.15, 0.1), "offset": Vector3(0, nozzle_height, -0.6),
		"dir": Vector3(0, 0, -1), "spread": 10.0, "speed": Vector2(8.0, 14.0), "tex": Fx.Tex.DOT, "size": 0.7,
		"curve": "shrink", "colors": PackedColorArray([Color(2.6, 1.6, 0.8, 0.9), Color(2.0, 0.8, 0.3, 0.5), Color(0.6, 0.3, 0.2, 0.0)]),
		"aabb": vis})
	add_child(_heat)
