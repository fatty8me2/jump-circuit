class_name Flipper
extends AnimatableBody3D
## Flipper paddle (kit obstacle): a pinball flipper lying flat. The paddle (solid, rideable) sits
## at `rest_deg` (yaw, 0 = along local +X, positive turns it toward local -Z), winds back a few
## degrees through `tell` seconds (it glows and shudders), then SWATS through `swing_deg` in
## 0.12 s. Anything standing on or beside it during the swat is thrown along the swing: harder
## near the tip. It holds up, then eases back down. All on the course clock.
##   s 0..rest still   ..+tell wind-up   ..+0.12 swat   ..+0.5 held up   ..+0.8 return
## Node origin = the pivot, at the paddle's top surface height.

@export var length: float = 5.0
@export var width: float = 1.6
@export var thick: float = 0.4
@export var rest_deg: float = 0.0
@export var swing_deg: float = 80.0
@export var period: float = 4.0
@export var phase: float = 0.0
@export var tell: float = 0.9
## Horizontal throw speed at the tip (m/s); near the pivot it is 40% of this.
@export var power: float = 15.0
@export var lift: float = 8.0

const FLIP: float = 0.12
const HOLD: float = 0.5
const RETURN: float = 0.8
const WINDUP_DEG: float = 8.0

var _hit: Area3D
var _cool: float = 0.0
var _rest_len: float = 1.0
var _glow_mat: StandardMaterial3D
var _flash: GPUParticles3D
var _ring: GPUParticles3D
var _puff: GPUParticles3D
var _lamp: OmniLight3D
var _fx_phase: int = -1


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	tell = maxf(tell, KitUtil.MIN_TELL)
	_rest_len = maxf(period - tell - FLIP - HOLD - RETURN, 0.3)
	period = _rest_len + tell + FLIP + HOLD + RETURN
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, thick, width)
	cs.shape = bs
	# 3 cm proud of the deck it sits on, so a flush floor never z-fights it
	cs.position = Vector3(length * 0.5, -thick * 0.5 + 0.03, 0)
	add_child(cs)
	var body := Look.platform_box(Vector3(length, thick, width), "accent")
	body.position = cs.position
	add_child(body)
	_glow_mat = Look.flat(Look.c("accent2"), 0.4, 0.2, 0.5).duplicate() as StandardMaterial3D
	# the swatting edge: a glowing bar along the leading side, and a round bumper at the tip
	add_child(Look.box(Vector3(length - 0.2, 0.14, 0.14), _glow_mat, Vector3(length * 0.5, 0.05, -width * 0.5 + 0.1)))
	add_child(Look.cylinder(width * 0.55, thick + 0.1, Look.flat(Look.c("metal"), 0.4, 0.7), Vector3(0, -thick * 0.5, 0), -1.0, 18))
	add_child(Look.cylinder(width * 0.4, thick + 0.12, Look.flat(Look.c("accent"), 0.4, 0.1, 1.2), Vector3(length - width * 0.45, -thick * 0.5, 0), -1.0, 16))
	_hit = Area3D.new()
	_hit.collision_layer = 0
	_hit.collision_mask = 2
	_hit.monitorable = false
	var hs := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = Vector3(length + 0.3, 2.0, width + 0.6)
	hs.shape = hb
	_hit.add_child(hs)
	_hit.position = Vector3(length * 0.5, 0.95, 0)
	add_child(_hit)
	rotation.y = deg_to_rad(angle_at(Game.course_time))
	reset_physics_interpolation()
	add_to_group("course_clock")
	_build_fx()


func _build_fx() -> void:
	var vis := AABB(Vector3(-length - 4.0, -3.0, -length - 4.0), Vector3(length * 2.0 + 8.0, 8.0, length * 2.0 + 8.0))
	_flash = Fx.sparks({"amount": 40, "lifetime": 0.4, "shape": "box", "extents": Vector3(length * 0.45, 0.05, 0.1),
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(3.0, 9.0), "color": Color(2.6, 1.8, 0.7), "aabb": vis})
	_flash.position = Vector3(length * 0.5, 0.1, 0)
	add_child(_flash)
	_puff = Fx.smoke({"amount": 12, "lifetime": 0.7, "shape": "box", "extents": Vector3(length * 0.4, 0.05, 0.2),
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(0.8, 2.4), "size": 0.7, "color": Color(0.9, 0.86, 0.8, 0.55), "aabb": vis})
	_puff.position = _flash.position
	add_child(_puff)
	_ring = Fx.shockwave(length * 0.5, {"lifetime": 0.3, "color": Color(2.2, 1.6, 0.6), "aabb": vis})
	_ring.position = Vector3(length - width * 0.45, 0.06, 0)
	add_child(_ring)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.7, 0.35)
	_lamp.omni_range = length + 3.0
	_lamp.light_energy = 0.0
	_lamp.visible = false
	_lamp.shadow_enabled = false
	_lamp.position = Vector3(length * 0.5, 1.0, 0)
	add_child(_lamp)


# ---- timeline ---------------------------------------------------------------------------

func _s(time: float) -> float:
	return KitUtil.cycle_s(time, period, phase)


func _dir() -> float:
	return 1.0 if swing_deg >= 0.0 else -1.0


## 0 rest, 1 wind-up (the tell), 2 swat, 3 held up, 4 returning.
func phase_at(time: float) -> int:
	var s: float = _s(time)
	if s < _rest_len:
		return 0
	s -= _rest_len
	if s < tell:
		return 1
	s -= tell
	if s < FLIP:
		return 2
	s -= FLIP
	return 3 if s < HOLD else 4


## The paddle's yaw in degrees at `time`.
func angle_at(time: float) -> float:
	var s: float = _s(time)
	var back: float = rest_deg - _dir() * WINDUP_DEG
	var top: float = rest_deg + swing_deg
	if s < _rest_len:
		return rest_deg
	s -= _rest_len
	if s < tell:
		return lerpf(rest_deg, back, KitUtil.smooth(s / tell))
	s -= tell
	if s < FLIP:
		var k: float = s / FLIP
		return lerpf(back, top, 1.0 - (1.0 - k) * (1.0 - k))
	s -= FLIP
	if s < HOLD:
		return top
	s -= HOLD
	return lerpf(top, rest_deg, KitUtil.smooth(s / RETURN))


func is_swatting_at(time: float) -> bool:
	return phase_at(time) == 2


## Seconds until the next swat begins.
func time_to_swat(time: float) -> float:
	var s: float = _s(time)
	var at: float = _rest_len + tell
	return at - s if s <= at else period - s + at


## True when no swat happens in [time, time + window] (so the paddle stays down and still, or
## is already held up / returning).
func swat_free_for(time: float, window: float) -> bool:
	return phase_at(time) != 2 and time_to_swat(time) > window


## The velocity a rider standing at `world_pos` is thrown with by the swat.
func throw_velocity(world_pos: Vector3) -> Vector3:
	var r: Vector3 = world_pos - global_position
	r.y = 0.0
	var tangent: Vector3 = Vector3.UP.cross(r)
	if tangent.length() < 0.01:
		return Vector3(0, lift, 0)
	var reach: float = clampf(r.length() / length, 0.0, 1.0)
	return tangent.normalized() * _dir() * power * (0.4 + 0.6 * reach) + Vector3(0, lift, 0)


# ---- behaviour --------------------------------------------------------------------------

func snap_to_clock() -> void:
	rotation.y = deg_to_rad(angle_at(Game.course_time))
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	rotation.y = deg_to_rad(angle_at(t))
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0 or not (is_swatting_at(t) or is_swatting_at(t - 0.04)):
		return
	for body: Node3D in _hit.get_overlapping_bodies():
		if body is Player:
			(body as Player).knockback(throw_velocity(body.global_position))
			_cool = 0.5
			Sfx.play_at("whack", body.global_position, 0.08, 1.0)
			return


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var ph: int = phase_at(t)
	if ph == 1:
		var k: float = clampf(1.0 - time_to_swat(t) / tell, 0.0, 1.0)
		KitUtil.glow(_glow_mat, 0.5 + 4.0 * k)
	elif ph == 0 or ph == 4:
		KitUtil.glow(_glow_mat, 0.5)
	if ph == _fx_phase:
		return
	var was: int = _fx_phase
	_fx_phase = ph
	if was < 0:
		return
	if ph == 1:
		WorldAudio.at(self, "kit_flipper_tell", global_position + global_basis.x * length * 0.5, 0.6, 30.0)
	elif ph == 2:
		_flash.restart()
		_puff.restart()
		_ring.restart()
		Fx.pulse(_lamp, 4.0, 0.0, 0.3)
		KitUtil.glow(_glow_mat, 5.0)
		WorldAudio.at(self, "kit_flipper_swat", global_position + global_basis.x * length * 0.5, 1.0, 45.0)
	elif ph == 4:
		WorldAudio.at(self, "kit_flipper_return", global_position, 0.4, 25.0)
