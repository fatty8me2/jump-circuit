class_name SpinHammer
extends Node3D
## Spinning hammer (kit obstacle): a heavy-headed arm on a post that sweeps a full circle around a
## VERTICAL axis, then parks. It does not kill - it HITS: a rider the arm or head touches is
## thrown outward and along the swing. The gap to pass is the parked time.
##   s 0..rest parked at park_deg (cross the circle now)   ..+tell winds back 30 deg (glows)
##   ..+swing_time one full revolution (eased) and back to the park angle
## Angles are degrees about Y from local +X toward local -Z. The node sits on the floor at the
## post; the arm swings `arm_height` above it.

@export var arm_length: float = 5.0
@export var arm_height: float = 0.9
@export var head_radius: float = 0.95
@export var period: float = 4.8
@export var phase: float = 0.0
@export var tell: float = 0.9
@export var swing_time: float = 1.2
## Where the arm waits (deg about Y; 180 = pointing along local -X).
@export var park_deg: float = 180.0
## +1 sweeps counter-clockwise seen from above, -1 clockwise.
@export var spin_dir: float = 1.0
@export var windup_deg: float = 30.0
@export var kick: float = 7.0

var _arm: Node3D
var _area: Area3D
var _rest_len: float = 1.0
var _cool: float = 0.0
var _glow_mat: StandardMaterial3D
var _fx_phase: int = -1
var _swooshes: Array[Swoosh] = []
var _rims: Array[Node3D] = []
var _flash: GPUParticles3D
var _trail: GPUParticles3D


func _ready() -> void:
	tell = maxf(tell, KitUtil.MIN_TELL)
	spin_dir = 1.0 if spin_dir >= 0.0 else -1.0
	_rest_len = maxf(period - tell - swing_time, 0.4)
	period = _rest_len + tell + swing_time
	var metal: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.7)
	# the post (solid, so nobody walks through the hub)
	var post := StaticBody3D.new()
	post.collision_layer = 1
	post.collision_mask = 0
	var pc := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.55
	cyl.height = arm_height + 0.6
	pc.shape = cyl
	pc.position = Vector3(0, (arm_height + 0.6) * 0.5, 0)
	post.add_child(pc)
	post.add_child(Look.cylinder(0.55, arm_height + 0.6, Look.flat(Color(0.14, 0.15, 0.2), 0.4, 0.7), pc.position, 0.42, 14))
	add_child(post)
	_arm = Node3D.new()
	_arm.position = Vector3(0, arm_height, 0)
	add_child(_arm)
	_glow_mat = Look.flat(Look.c("accent"), 0.4, 0.3, 0.5).duplicate() as StandardMaterial3D
	# arm along local +X, a hot head at the tip
	_arm.add_child(Look.box(Vector3(arm_length, 0.28, 0.34), metal, Vector3(arm_length * 0.5, 0, 0)))
	var head := Look.cylinder(head_radius, head_radius * 1.7, _glow_mat, Vector3(arm_length, 0, 0), -1.0, 18)
	_arm.add_child(head)
	_arm.add_child(Look.sphere(0.4, metal, Vector3.ZERO))
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var bs := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(arm_length, 1.1, 0.7)
	bs.shape = bb
	bs.position = Vector3(arm_length * 0.5, 0, 0)
	_area.add_child(bs)
	var hs := CollisionShape3D.new()
	var hsh := CylinderShape3D.new()
	hsh.radius = head_radius * 1.05
	hsh.height = head_radius * 1.9
	hs.shape = hsh
	hs.position = Vector3(arm_length, 0, 0)
	_area.add_child(hs)
	_arm.add_child(_area)
	_apply(Game.course_time)
	add_to_group("course_clock")
	var vis := AABB(Vector3(-arm_length - 4.0, -2.0, -arm_length - 4.0), Vector3(arm_length * 2.0 + 8.0, 8.0, arm_length * 2.0 + 8.0))
	_trail = Fx.trail({"amount": 40, "lifetime": 0.3, "shape": "sphere", "radius": head_radius * 0.7,
		"size": head_radius * 1.0, "curve": "shrink", "color": Color(1.6, 0.6, 0.3, 0.4),
		"fade": PackedFloat32Array([0.8, 0.0]), "emitting": false, "aabb": vis})
	_trail.position = Vector3(arm_length, 0, 0)
	_arm.add_child(_trail)
	_flash = Fx.sparks({"amount": 30, "lifetime": 0.4, "shape": "sphere", "radius": head_radius * 0.6,
		"dir": Vector3.UP, "spread": 80.0, "speed": Vector2(2.0, 6.0), "color": Color(2.6, 1.8, 0.7), "aabb": vis})
	_flash.position = Vector3(arm_length, 0, 0)
	_arm.add_child(_flash)
	for sy: float in [-1.0, 1.0]:
		var rim := Node3D.new()
		rim.position = Vector3(arm_length, sy * head_radius * 0.8, 0)
		_arm.add_child(rim)
		_rims.append(rim)
		var sw: Swoosh = Swoosh.make(Color(1.0, 0.35, 0.15, 0.8), head_radius * 0.5, 0.3, false)
		sw.spacing = 0.12
		add_child(sw)
		_swooshes.append(sw)


# ---- timeline ---------------------------------------------------------------------------

func _s(time: float) -> float:
	return KitUtil.cycle_s(time, period, phase)


## 0 parked, 1 wind-up (the tell), 2 sweeping.
func phase_at(time: float) -> int:
	var s: float = _s(time)
	if s < _rest_len:
		return 0
	return 1 if s < _rest_len + tell else 2


## The arm's angle in degrees (about Y from +X toward -Z) at `time`.
func angle_at(time: float) -> float:
	var s: float = _s(time)
	if s < _rest_len:
		return park_deg
	s -= _rest_len
	var back: float = park_deg - spin_dir * windup_deg
	if s < tell:
		return lerpf(park_deg, back, KitUtil.smooth(s / tell))
	s -= tell
	return lerpf(back, park_deg + spin_dir * 360.0, KitUtil.smoother(s / swing_time))


## Head speed in m/s at `time` (0 while parked).
func tip_speed_at(time: float) -> float:
	var d: float = 0.01
	var w: float = deg_to_rad(angle_at(time + d) - angle_at(time - d)) / (2.0 * d)
	return absf(w) * arm_length


## True when the arm stays parked for the whole next `window` s (safe to cross the circle).
func is_parked_for(time: float, window: float) -> bool:
	return KitUtil.holds_for(func(x: float) -> bool: return phase_at(x) == 0, time, window)


## Seconds of parked time left (0 unless parked).
func parked_left(time: float) -> float:
	return _rest_len - _s(time) if phase_at(time) == 0 else 0.0


## Seconds until the arm is next parked (0 if it is).
func parked_in(time: float) -> float:
	if phase_at(time) == 0:
		return 0.0
	return period - _s(time)


# ---- behaviour --------------------------------------------------------------------------

func snap_to_clock() -> void:
	_apply(Game.course_time)
	_arm.reset_physics_interpolation()
	for s: Swoosh in _swooshes:
		s.clear()


func _apply(time: float) -> void:
	_arm.rotation.y = deg_to_rad(angle_at(time))


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	_cool = maxf(_cool - dt, 0.0)
	var speed: float = tip_speed_at(t)
	if _cool > 0.0 or speed < 5.0:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var rel: Vector3 = body.global_position - global_position
			rel.y = 0.0
			var out: Vector3 = rel.normalized() if rel.length() > 0.05 else Vector3.RIGHT
			# the swing's direction at the rider: Y x r, turned by the spin direction and the sign of the arm's motion
			var w: float = deg_to_rad(angle_at(t + 0.01) - angle_at(t - 0.01)) / 0.02
			var tangent: Vector3 = Vector3.UP.cross(out) * signf(w)
			var push: float = clampf(speed * 0.5 + 5.0, 8.0, 16.0)
			(body as Player).knockback((out * 0.55 + tangent * 0.8).normalized() * push + Vector3(0, 8.0 + kick * 0.1, 0))
			_cool = 0.6
			Sfx.play_at("whack", body.global_position, 0.08, 1.0)
			return


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var ph: int = phase_at(t)
	for i: int in _swooshes.size():
		_swooshes[i].feed(_rims[i].global_position, ph == 2 and tip_speed_at(t) > 6.0, dt)
	_trail.emitting = ph == 2 and tip_speed_at(t) > 6.0
	if ph == 1:
		var k: float = clampf((_s(t) - _rest_len) / tell, 0.0, 1.0)
		KitUtil.glow(_glow_mat, 0.5 + 4.0 * k)
	elif ph == 0:
		KitUtil.glow(_glow_mat, 0.5)
	if ph == _fx_phase:
		return
	var was: int = _fx_phase
	_fx_phase = ph
	if was < 0:
		return
	var head: Vector3 = _arm.to_global(Vector3(arm_length, 0, 0))
	if ph == 1:
		WorldAudio.at(self, "kit_hammer_tell", global_position, 0.7, 35.0)
	elif ph == 2:
		_flash.restart()
		WorldAudio.at(self, "kit_hammer_swing", head, 0.9, 45.0)
	elif ph == 0:
		WorldAudio.at(self, "kit_hammer_park", head, 0.5, 30.0)
