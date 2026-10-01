class_name SakuraBamboo
extends Node3D
## Sakura Peaks: a BAMBOO SPRING LAUNCHER. A tall green culm is bent over and lashed down to a
## round woven mat on a stone base; the mat is the platform. On the course clock the lashing is
## worked loose: for the last `WARN` of each turn the culm creaks and quivers, the mat sinks a
## hand's breadth as the rope strains and the red rope tag flashes - then SNAP: the bamboo flicks
## straight, the mat jerks up and anyone standing on it is flung up (and a little along the
## launcher's facing) by `launch`. The culm bends back down for the next turn.
## A pure function of Game.course_time: stand on the mat and wait.
##   u 0.00-POP resting (the last WARN of it straining)   POP-POP+OUT flick   ..HOLD held up   ..1 bending back
## Positioned by the centre of the mat's TOP at rest; its base stands on the floor below.

@export var radius: float = 1.25
## Height of the stone base under the mat (to the floor).
@export var base_height: float = 1.2
@export var period: float = 3.2
@export var phase: float = 0.0
## Launch velocity in the launcher's own frame (local -Z is "forward").
@export var launch: Vector3 = Vector3(0, 18, -2)
@export var rise: float = 1.0
## Height of the bent culm's root behind the mat.
@export var culm_height: float = 7.0

const POP: float = 0.78
const OUT: float = 0.04
const HOLD: float = 0.86
const WARN: float = 0.27
const SEGS: int = 9

var _mat: AnimatableBody3D
var _area: Area3D
var _culm: Array[MeshInstance3D] = []
var _leaves: Node3D
var _tag_mat: StandardMaterial3D
var _snap_fx: GPUParticles3D
var _leaf_fx: GPUParticles3D
var _cool: float = 0.0
var _popped: int = -1
var _warned: int = -1


func _ready() -> void:
	_build()
	_pose(Game.course_time)
	add_to_group("course_clock")


func _u(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0)


## 0 (lashed down) .. 1 (flicked up) at `time`; slightly negative while straining.
func extension_at(time: float) -> float:
	var u: float = _u(time)
	if u < POP - WARN:
		return 0.0
	if u < POP:
		return -0.18 * smoothstep(POP - WARN, POP - WARN * 0.4, u)
	if u < POP + OUT:
		var k: float = (u - POP) / OUT
		return 1.0 - (1.0 - k) * (1.0 - k)
	if u < HOLD:
		return 1.0
	var r: float = (u - HOLD) / (1.0 - HOLD)
	return 1.0 - r * r * (3.0 - 2.0 * r)


## Seconds from `time` until the next snap.
func time_until_pop(time: float) -> float:
	return fposmod(POP - _u(time), 1.0) * period


## True while the mat is down (safe to step onto).
func is_resting_at(time: float) -> bool:
	return _u(time) < POP


## World velocity a rider is thrown with.
func launch_velocity() -> Vector3:
	return global_basis.orthonormalized() * launch


func snap_to_clock() -> void:
	_pose(Game.course_time)
	if _mat != null:
		_mat.reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_pose(t)
	_cool = maxf(_cool - dt, 0.0)
	var u: float = _u(t)
	if u >= POP and u < POP + OUT and _cool <= 0.0:
		for body: Node3D in _area.get_overlapping_bodies():
			if body is Player:
				(body as Player).knockback(launch_velocity())
				_cool = OUT * period + 0.1


func _pose(t: float) -> void:
	if _mat != null:
		_mat.position = Vector3(0, rise * extension_at(t), 0)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var u: float = _u(t)
	var e: float = extension_at(t)
	var warn: bool = u > POP - WARN and u < POP
	_bend(e, warn, t)
	_tag_mat.emission_energy_multiplier = 3.2 if (warn and fmod(t, 0.16) < 0.08) else 0.6
	var cycle: int = int(floor(t / maxf(period, 0.01) + phase))
	if u >= POP and u < HOLD and cycle != _popped:
		_popped = cycle
		_snap_fx.restart()
		_snap_fx.emitting = true
		_leaf_fx.restart()
		_leaf_fx.emitting = true
		# SOUND: the culm whipping straight, a sharp wooden crack
		WorldAudio.at(self, "sakura_bamboo_snap", global_position, 1.0, 40.0)
	if warn and cycle != _warned:
		_warned = cycle
		# SOUND: the lashing creaking under strain, just before the snap
		WorldAudio.at(self, "sakura_bamboo_creak", global_position, 0.8, 30.0)


## The culm: a Bezier from its root (behind and above the base) to the mat's rim. Bent hard over
## while lashed, it straightens toward vertical as the mat flicks up.
func _bend(e: float, warn: bool, t: float) -> void:
	var root := Vector3(radius + 1.1, -base_height, 0)
	var tip: Vector3 = _mat.position + Vector3(radius * 0.6, 0.15, 0)
	var straight: float = clampf(e, 0.0, 1.0)
	var ctrl: Vector3 = root + Vector3(0.6 + 1.2 * straight, culm_height * (1.0 + 0.25 * straight), 0)
	var q: float = 0.05 * sin(t * 60.0) if warn else 0.0
	var prev: Vector3 = root
	for i: int in SEGS:
		var k: float = float(i + 1) / float(SEGS)
		var p: Vector3 = root.lerp(ctrl, k).lerp(ctrl.lerp(tip, k), k) + Vector3(0, 0, q)
		var seg: MeshInstance3D = _culm[i]
		var d: Vector3 = p - prev
		var len: float = maxf(d.length(), 0.01)
		var up: Vector3 = d / len
		var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		seg.basis = Basis(side, up * len, side.cross(up))
		seg.position = (p + prev) * 0.5
		prev = p
	_leaves.position = ctrl.lerp(tip, 0.35) + Vector3(0, 0.6, 0)


func _build() -> void:
	var stone: StandardMaterial3D = SakuraDecor.mat(SakuraDecor.STONE, 0.95)
	var weave: StandardMaterial3D = SakuraDecor.mat(Color(0.78, 0.62, 0.36), 0.9)
	var green: StandardMaterial3D = SakuraDecor.mat(SakuraDecor.BAMBOO, 0.5)
	# the base: a squat stone drum standing on the floor (static, solid)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var bs := CylinderShape3D.new()
	bs.radius = radius
	bs.height = base_height - 0.3
	var bcs := CollisionShape3D.new()
	bcs.shape = bs
	bcs.position = Vector3(0, -0.3 - (base_height - 0.3) * 0.5, 0)
	body.add_child(bcs)
	add_child(body)
	add_child(Look.cylinder(radius + 0.1, base_height - 0.3, stone, Vector3(0, -0.3 - (base_height - 0.3) * 0.5, 0), radius, 10))
	add_child(Look.cylinder(radius + 0.18, 0.12, SakuraDecor.mat(SakuraDecor.MOSS, 0.95), Vector3(0, -base_height + 0.06, 0), -1.0, 10))
	# the mat (the platform you ride): kinematic, sits on the drum at rest
	_mat = AnimatableBody3D.new()
	_mat.sync_to_physics = false
	_mat.collision_layer = 1
	_mat.collision_mask = 0
	var ms := CylinderShape3D.new()
	ms.radius = radius - 0.05
	ms.height = 0.3
	var mcs := CollisionShape3D.new()
	mcs.shape = ms
	mcs.position = Vector3(0, -0.15, 0)
	_mat.add_child(mcs)
	add_child(_mat)
	_mat.add_child(Look.cylinder(radius, 0.3, weave, Vector3(0, -0.15, 0), -1.0, 24))
	# woven rings on the mat and a red rope tag that flashes in the warning
	for i: int in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = radius * (0.3 + 0.22 * float(i))
		tm.outer_radius = radius * (0.3 + 0.22 * float(i)) + 0.05
		tm.rings = 24
		tm.ring_segments = 4
		_mat.add_child(Look.mesh_node(tm, SakuraDecor.mat(Color(0.55, 0.4, 0.22), 0.9), Vector3(0, 0.01, 0)))
	_tag_mat = StandardMaterial3D.new()
	_tag_mat.albedo_color = SakuraDecor.VERMILION
	_tag_mat.emission_enabled = true
	_tag_mat.emission = Color(1.0, 0.3, 0.15)
	_tag_mat.emission_energy_multiplier = 0.6
	_mat.add_child(Look.box(Vector3(0.5, 0.06, 0.5), _tag_mat, Vector3(radius * 0.6, 0.03, 0)))
	# the culm: segments re-posed every frame along the bend
	for i: int in SEGS:
		var seg := Look.cylinder(0.16 - 0.008 * float(i), 1.0, green, Vector3.ZERO, -1.0, 8)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(seg)
		_culm.append(seg)
	_leaves = Node3D.new()
	add_child(_leaves)
	var leaf: StandardMaterial3D = SakuraDecor.mat(Color(0.34, 0.52, 0.22), 0.8)
	for i: int in 4:
		var lf := Look.sphere(1.0, leaf, Vector3(cos(float(i) * 1.6) * 0.6, float(i % 2) * 0.3, sin(float(i) * 1.6) * 0.6))
		lf.scale = Vector3(1.0, 0.18, 0.4)
		lf.rotation.y = float(i) * 0.9
		_leaves.add_child(lf)
	# a kick detector over the mat: anyone standing on it when it snaps is launched
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var as_ := CylinderShape3D.new()
	as_.radius = radius - 0.1
	as_.height = 0.9
	var acs := CollisionShape3D.new()
	acs.shape = as_
	acs.position = Vector3(0, 0.45, 0)
	_area.add_child(acs)
	_mat.add_child(_area)
	var vis := AABB(Vector3(-6, -3, -6), Vector3(12, 18, 12))
	_snap_fx = SakuraFx.petal_pop(radius, 40, 7.0)
	_snap_fx.visibility_aabb = vis
	_snap_fx.position = Vector3(0, 0.3, 0)
	add_child(_snap_fx)
	_leaf_fx = Fx.burst({"amount": 18, "lifetime": 1.4, "shape": "sphere", "radius": 0.8, "tex": Fx.Tex.PETAL, "additive": false,
		"size": 0.3, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -3.0, 0), "curve": "flat",
		"color": Color(0.42, 0.62, 0.28), "angle": Vector2(0, 360), "spin": Vector2(-300, 300), "aabb": vis})
	_leaf_fx.position = Vector3(radius + 1.0, culm_height * 0.6, 0)
	add_child(_leaf_fx)
	_bend(0.0, false, 0.0)
