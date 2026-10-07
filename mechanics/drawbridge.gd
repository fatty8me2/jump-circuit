class_name Drawbridge
extends Node3D
## Drawbridge (kit obstacle): a deck hinged at its near edge that hauls itself up on chains and
## lowers again, on a cycle of the course clock. The node sits at the HINGE, at deck-top height;
## the deck runs `length` metres along local -Z (turned by yaw). Raised, it stands as a wall
## above the hinge edge and the gap it spanned is open. A rider on the deck as it rises slides
## back toward the hinge (the slope is steep) - cross while it is down.
##   s 0..down_hold  flat (cross now)   ..+warn  chains rattle and glow (the tell)
##   ..+1.1 rises   ..+1.3 held up   ..+1.3 lowers
## Build the gatehouse (frame + chains) is automatic; the hinge edge needs ground behind it.

@export var length: float = 8.0
@export var width: float = 3.4
@export var thick: float = 0.5
@export var raise_deg: float = 80.0
@export var period: float = 9.0
@export var phase: float = 0.0
@export var warn: float = 1.0

const RAISE: float = 1.1
const UP_HOLD: float = 1.3
const LOWER: float = 1.3
const FRAME_H: float = 7.0

var _deck: AnimatableBody3D
var _down_hold: float = 1.0
var _chain_mat: StandardMaterial3D
var _chains: Array[MeshInstance3D] = []
var _fx_phase: int = -1
var _dust: GPUParticles3D
var _ring: GPUParticles3D
var _last_angle: float = 0.0


func _ready() -> void:
	warn = maxf(warn, KitUtil.MIN_TELL)
	_down_hold = maxf(period - warn - RAISE - UP_HOLD - LOWER, 1.0)
	period = _down_hold + warn + RAISE + UP_HOLD + LOWER
	_deck = AnimatableBody3D.new()
	_deck.sync_to_physics = false
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, thick, length)
	cs.shape = bs
	cs.position = Vector3(0, -thick * 0.5, -length * 0.5)
	_deck.add_child(cs)
	var planks := Look.platform_box(Vector3(width, thick, length), "mover")
	planks.position = cs.position
	_deck.add_child(planks)
	var iron: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.7)
	var hinge := Look.cylinder(0.22, width + 0.3, iron, Vector3(0, -thick * 0.5, 0), -1.0, 10)
	hinge.rotation.z = PI * 0.5
	_deck.add_child(hinge)
	_chain_mat = Look.flat(Look.c("accent"), 0.4, 0.5, 0.4).duplicate() as StandardMaterial3D
	add_child(_deck)
	_build_frame(iron)
	_apply(Game.course_time)
	add_to_group("course_clock")
	var vis := AABB(Vector3(-width - 3.0, -2.0, -length - 3.0), Vector3(width * 2.0 + 6.0, FRAME_H + 4.0, length + 8.0))
	_dust = Fx.smoke({"amount": 22, "lifetime": 0.9, "shape": "box", "extents": Vector3(width * 0.5, 0.05, 0.3),
		"dir": Vector3.UP, "spread": 75.0, "flatness": 0.5, "speed": Vector2(1.0, 3.4), "size": 1.1,
		"color": Color(0.8, 0.74, 0.66, 0.6), "aabb": vis})
	add_child(_dust)
	_ring = Fx.shockwave(width * 0.9, {"lifetime": 0.4, "color": Color(1.8, 1.5, 1.1), "aabb": vis})
	add_child(_ring)


func _build_frame(iron: StandardMaterial3D) -> void:
	# a gatehouse arch behind the hinge: two posts and a beam the chains hang from
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.5, FRAME_H, 0.5), Look.flat(Look.c("side"), 0.85), Vector3(sx * (width * 0.5 + 0.55), FRAME_H * 0.5 - thick, 0.9)))
	add_child(Look.box(Vector3(width + 1.9, 0.5, 0.7), Look.flat(Look.c("trim"), 0.75), Vector3(0, FRAME_H - thick, 0.9)))
	for sx: float in [-1.0, 1.0]:
		var c := KitUtil.link(0.06, _chain_mat)
		add_child(c)
		_chains.append(c)


# ---- timeline ---------------------------------------------------------------------------

func _s(time: float) -> float:
	return KitUtil.cycle_s(time, period, phase)


## 0 flat, 1 warning (still flat), 2 rising, 3 held up, 4 lowering.
func phase_at(time: float) -> int:
	var s: float = _s(time)
	if s < _down_hold:
		return 0
	s -= _down_hold
	if s < warn:
		return 1
	s -= warn
	if s < RAISE:
		return 2
	s -= RAISE
	return 3 if s < UP_HOLD else 4


## Deck lift in degrees at `time` (0 flat).
func angle_at(time: float) -> float:
	var s: float = _s(time) - _down_hold - warn
	if s < 0.0:
		return 0.0
	if s < RAISE:
		return raise_deg * KitUtil.smooth(s / RAISE)
	s -= RAISE
	if s < UP_HOLD:
		return raise_deg
	s -= UP_HOLD
	return raise_deg * (1.0 - KitUtil.smooth(s / LOWER))


## True while the deck is flat and will stay flat (and un-warned) for the next `window` s.
func is_down_for(time: float, window: float) -> bool:
	return KitUtil.holds_for(func(x: float) -> bool: return phase_at(x) == 0, time, window)


## True while the deck is flat or within `max_deg` of it (including the warning).
func is_nearly_flat(time: float, max_deg: float = 4.0) -> bool:
	return angle_at(time) <= max_deg


## Seconds until the deck is next flat and clear to cross (0 if it is now).
func down_in(time: float) -> float:
	if phase_at(time) == 0:
		return 0.0
	var s: float = _s(time)
	return period - s


## Seconds of safe crossing left (0 unless phase 0).
func down_left(time: float) -> float:
	if phase_at(time) != 0:
		return 0.0
	return _down_hold - _s(time)


# ---- behaviour --------------------------------------------------------------------------

func snap_to_clock() -> void:
	_apply(Game.course_time)
	_deck.reset_physics_interpolation()


func _apply(time: float) -> void:
	var a: float = angle_at(time)
	_last_angle = a
	_deck.rotation.x = deg_to_rad(a)
	# the chains run from the beam to the deck's free corners
	var turn := Basis(Vector3.RIGHT, deg_to_rad(a))
	for i: int in 2:
		var sx: float = -1.0 if i == 0 else 1.0
		var tip: Vector3 = turn * Vector3(sx * (width * 0.5 - 0.15), 0.0, -length)
		var top := Vector3(sx * (width * 0.5 - 0.15), FRAME_H - thick - 0.25, 0.9)
		KitUtil.place_link(_chains[i], top, tip)


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var ph: int = phase_at(t)
	if ph == 1:
		var k: float = 1.0 - (_down_hold + warn - _s(t)) / warn
		KitUtil.glow(_chain_mat, 0.4 + 3.0 * (1.0 if fmod(_s(t), 0.2) > 0.1 else 0.3) * clampf(k * 2.0, 0.2, 1.0))
	elif ph == 0:
		KitUtil.glow(_chain_mat, 0.4)
	if ph == _fx_phase:
		return
	var was: int = _fx_phase
	_fx_phase = ph
	if was < 0:
		return
	var mid: Vector3 = global_position + global_basis * Vector3(0, 0, -length * 0.5)
	if ph == 1:
		WorldAudio.at(self, "kit_drawbridge_chains", mid, 0.7, 40.0)
	elif ph == 2:
		WorldAudio.at(self, "kit_drawbridge_raise", mid, 0.7, 40.0)
	elif ph == 4:
		WorldAudio.at(self, "kit_drawbridge_lower", mid, 0.6, 40.0)
	elif ph == 0 and was == 4:
		_dust.position = Vector3(0, 0.1, -length)
		_dust.restart()
		_ring.position = Vector3(0, 0.08, -length + 0.4)
		_ring.restart()
		WorldAudio.at(self, "kit_drawbridge_thud", global_position + global_basis * Vector3(0, 0, -length), 1.0, 55.0)
