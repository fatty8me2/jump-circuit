class_name FallingBlock
extends AnimatableBody3D
## Falling block (kit obstacle): a slab hung `drop_height` metres above the floor. A dark shadow
## swells on the floor under it for `tell` seconds (and the block judders), then it DROPS. Caught
## underneath while it falls or sits = back to the checkpoint. It rests on the floor (its top is a
## solid platform), then hauls itself back up to reset.
##   clock mode (approach = false): the cycle runs on the course clock, like a crusher.
##   approach mode: idle (high, faint shadow) until a rider comes within `trigger_radius`; the
##   tell then starts at once and the block falls `tell` seconds later, then resets and re-arms.
##   s 0..rest high   ..+tell shadow grows   ..+0.3 falls   ..+1.4 down   ..+1.4 rises
## The node sits on the floor point under the centre of the block.

@export var size: Vector3 = Vector3(3.0, 1.6, 3.0)
@export var drop_height: float = 7.0
@export var period: float = 5.0
@export var phase: float = 0.0
@export var tell: float = 1.0
@export var approach: bool = false
@export var trigger_radius: float = 4.5

const FALL: float = 0.3
const DOWN: float = 1.4
const RISE: float = 1.4
## Underside height under which the block still kills.
const LETHAL_GAP: float = 0.9

var _floor: Vector3
var _floor_world: Vector3
var _rest_len: float = 1.0
var _kill: Area3D
var _trigger: Area3D
var _cycle_start: float = -1.0e9
var _shadow: MeshInstance3D
var _plate_mat: StandardMaterial3D
var _fx_phase: int = -1
var _dust: GPUParticles3D
var _debris: GPUParticles3D
var _ring: GPUParticles3D
var _lamp: OmniLight3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_floor = position
	_floor_world = global_position
	tell = maxf(tell, KitUtil.MIN_TELL)
	_rest_len = maxf(period - tell - FALL - DOWN - RISE, 0.3)
	period = _rest_len + tell + FALL + DOWN + RISE
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)
	add_child(Look.platform_box(size, "alt"))
	_plate_mat = Look.flat(Color(1.0, 0.25, 0.12), 0.4, 0.3, 0.4).duplicate() as StandardMaterial3D
	add_child(Look.box(Vector3(size.x + 0.1, 0.22, size.z + 0.1), _plate_mat, Vector3(0, -size.y * 0.5 + 0.1, 0)))
	var spike: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.24), 0.4, 0.8)
	for sx: float in [-0.3, 0.3]:
		for sz: float in [-0.3, 0.3]:
			add_child(Look.cylinder(0.16, 0.3, spike, Vector3(sx * size.x, -size.y * 0.5 - 0.1, sz * size.z), 0.04, 8))
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var ks := CollisionShape3D.new()
	var kb := BoxShape3D.new()
	kb.size = Vector3(size.x - 0.15, 0.9, size.z - 0.15)
	ks.shape = kb
	_kill.add_child(ks)
	_kill.position = Vector3(0, -size.y * 0.5 - 0.05, 0)
	add_child(_kill)
	if approach:
		_trigger = Area3D.new()
		_trigger.collision_layer = 0
		_trigger.collision_mask = 2
		_trigger.monitorable = false
		var ts := CollisionShape3D.new()
		var tc := CylinderShape3D.new()
		tc.radius = trigger_radius
		tc.height = 3.0
		ts.shape = tc
		_trigger.add_child(ts)
		_trigger.top_level = true   # stays on the floor while the block moves
		add_child(_trigger)
		_trigger.global_position = _floor_world + Vector3(0, 1.0, 0)
	# the floor shadow (a child of this body, so keep it flat in world space)
	_shadow = KitUtil.floor_quad(Vector2(size.x, size.z), Color(0, 0, 0, 0.0))
	_shadow.top_level = true
	add_child(_shadow)
	_place_shadow()
	position = _floor + Vector3(0, gap_at(Game.course_time) + size.y * 0.5, 0)
	reset_physics_interpolation()
	add_to_group("course_clock")
	add_to_group("resettable")
	_build_fx()


func _place_shadow() -> void:
	_shadow.global_position = _floor_world + Vector3(0, 0.04, 0)
	_shadow.global_rotation = Vector3.ZERO


func _build_fx() -> void:
	var reach: float = maxf(size.x, size.z)
	var vis := AABB(Vector3(-reach - 4.0, -drop_height - 3.0, -reach - 4.0), Vector3(reach * 2.0 + 8.0, drop_height + size.y + 8.0, reach * 2.0 + 8.0))
	_dust = Fx.smoke({"amount": 30, "lifetime": 1.1, "shape": "ring", "ring_radius": reach * 0.5, "ring_inner": reach * 0.35,
		"dir": Vector3(0, 0.15, 0), "spread": 180.0, "flatness": 0.9, "radial_vel": Vector2(4.0, 8.0),
		"speed": Vector2(0.0, 0.4), "damping": Vector2(5.0, 8.0), "gravity": Vector3(0, 0.6, 0), "size": 1.4,
		"color": Color(0.78, 0.72, 0.64, 0.8), "aabb": vis})
	add_child(_dust)
	_debris = Fx.debris({"amount": 22, "shape": "ring", "ring_radius": reach * 0.5, "ring_inner": reach * 0.3,
		"dir": Vector3.UP, "spread": 50.0, "radial_vel": Vector2(2.0, 5.0), "speed": Vector2(3.0, 7.0),
		"color": Color(0.4, 0.33, 0.27), "chunk": 0.2, "aabb": vis})
	add_child(_debris)
	_ring = Fx.shockwave(reach * 1.3, {"lifetime": 0.5, "color": Color(2.2, 1.7, 1.2), "aabb": vis})
	add_child(_ring)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.55, 0.3)
	_lamp.omni_range = reach * 2.0 + 2.0
	_lamp.light_energy = 0.0
	_lamp.visible = false
	_lamp.shadow_enabled = false
	add_child(_lamp)


# ---- timeline ---------------------------------------------------------------------------

## Seconds into the cycle at `time`, or -1 when an approach-mode block is idle.
func _s(time: float) -> float:
	if not approach:
		return KitUtil.cycle_s(time, period, phase)
	var s: float = time - _cycle_start
	if s < 0.0 or s >= period:
		return -1.0
	return s


## 0 resting high (or idle), 1 tell, 2 falling, 3 down, 4 rising.
func phase_at(time: float) -> int:
	var s: float = _s(time)
	if s < _rest_len:
		return 0
	s -= _rest_len
	if s < tell:
		return 1
	s -= tell
	if s < FALL:
		return 2
	s -= FALL
	return 3 if s < DOWN else 4


## Height of the block's underside above the floor at `time`.
func gap_at(time: float) -> float:
	var s: float = _s(time)
	if s < _rest_len:
		return drop_height
	s -= _rest_len + tell
	if s < 0.0:
		return drop_height
	if s < FALL:
		var k: float = s / FALL
		return drop_height * (1.0 - k * k)
	s -= FALL
	if s < DOWN:
		return 0.0
	s -= DOWN
	return drop_height * KitUtil.smooth(s / RISE)


func _deadly_at(time: float) -> bool:
	var s: float = _s(time)
	if s < 0.0:
		return false
	var ph: int = phase_at(time)
	return ph == 2 or ph == 3 or (ph == 4 and gap_at(time) < LETHAL_GAP)


## True while standing under the block is safe for the next `window` seconds (clock mode; an
## approach-mode block answers for the cycle it is in).
func is_clear_for(time: float, window: float) -> bool:
	return KitUtil.holds_for(func(x: float) -> bool: return not _deadly_at(x), time, window)


## Seconds until the block lands (clock mode: from `time`; -1 when idle in approach mode).
func time_to_land(time: float) -> float:
	var s: float = _s(time)
	if s < 0.0:
		return -1.0
	var land: float = _rest_len + tell + FALL
	if s <= land:
		return land - s
	return period - s + land if not approach else -1.0


## Approach mode: arm the cycle now (the tell starts immediately).
func arm(time: float) -> void:
	if approach and _s(time) < 0.0:
		_cycle_start = time - _rest_len


# ---- behaviour --------------------------------------------------------------------------

func snap_to_clock() -> void:
	reset_state()


func reset_state() -> void:
	_cycle_start = -1.0e9
	position = _floor + Vector3(0, gap_at(Game.course_time) + size.y * 0.5, 0)
	reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	if approach and _s(t) < 0.0 and _trigger != null:
		for b: Node3D in _trigger.get_overlapping_bodies():
			if b is Player:
				arm(t)
				break
	var s: float = _s(t)
	var shake := Vector3.ZERO
	if s >= _rest_len + tell * 0.6 and phase_at(t) == 1:
		shake = Vector3(sin(t * 90.0) * 0.05, 0, cos(t * 77.0) * 0.05)
	position = _floor + Vector3(0, gap_at(t) + size.y * 0.5, 0) + shake
	_update_shadow(t)
	if not _deadly_at(t):
		return
	for body: Node3D in _kill.get_overlapping_bodies():
		if body is Player:
			KitUtil.kill(self, "hazard")
			return


func _update_shadow(t: float) -> void:
	var ph: int = phase_at(t)
	var a: float = 0.0
	var sc: float = 0.5
	var s: float = _s(t)
	if s < 0.0 or ph == 0:
		a = 0.10
		sc = 0.45
	elif ph == 1:
		var k: float = clampf((s - _rest_len) / tell, 0.0, 1.0)
		a = lerpf(0.12, 0.7, k * k)
		sc = lerpf(0.45, 1.05, k)
	elif ph == 2:
		a = 0.8
		sc = 1.05
	elif ph == 3:
		a = 0.0
	else:
		a = 0.4 * clampf(gap_at(t) / 2.0, 0.0, 1.0)
		sc = 1.05
	_shadow.scale = Vector3(sc, 1.0, sc)
	KitUtil.set_quad_color(_shadow, Color(0.0, 0.0, 0.02, a))
	_shadow.visible = a > 0.001


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var ph: int = phase_at(t) if _s(t) >= 0.0 else 0
	var glow_e: float = 2.4 if (ph == 1 or ph == 2 or ph == 3) else 0.4
	KitUtil.glow(_plate_mat, glow_e)
	if ph == _fx_phase:
		return
	var was: int = _fx_phase
	_fx_phase = ph
	if was < 0:
		return
	if ph == 1:
		WorldAudio.at(self, "kit_block_tell", global_position, 0.7, 40.0)
	elif ph == 3 and was == 2:
		var floor_local := Vector3(0, -size.y * 0.5, 0)
		for p: GPUParticles3D in [_dust, _debris, _ring]:
			p.position = floor_local + Vector3(0, 0.08, 0)
			p.restart()
		_lamp.position = floor_local + Vector3(0, 0.8, 0)
		Fx.pulse(_lamp, 5.0, 0.0, 0.5)
		WorldAudio.at(self, "kit_block_slam", to_global(floor_local), 1.0, 55.0)
	elif ph == 4:
		WorldAudio.at(self, "kit_block_rise", global_position, 0.5, 30.0)
