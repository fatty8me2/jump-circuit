class_name ArcaneInk
extends Node3D
## Arcane Library: INK RIVER. A river of living ink runs across the walkway under a little plank bridge.
## Most of the time it flows low and harmless below the bridge; on a fixed rhythm (the course clock,
## so identical for every racer) it SURGES and floods over the planks:
##   dry        the ink runs low under the bridge, quiet
##   tell       (>= 0.8 s) the ink churns and bubbles, the gold script races along it, two will-o-wisp
##              flames over the river flash violet and a gurgle rises - nothing can hurt you yet
##   rise       the ink swells up over the bridge (0.8 s)
##   wet        the bridge is under ink: touching it sends you back to the checkpoint
##   fall       the ink drains away (it is harmless once it is back below your feet)
## Place the node at the bridge's deck-top height at the middle of the lane. `size` is the river
## (x = how wide it flows across the path, z = how long the gap is along the path). The ink slab never
## touches the platforms either side of the gap (it stops 5 cm short).

@export var size: Vector2 = Vector2(12.0, 4.0)
@export var period: float = 7.0
@export var phase: float = 0.0
@export var tell_time: float = 1.1
@export var rise_time: float = 0.8
@export var wet_time: float = 1.8
@export var fall_time: float = 0.7
@export var flow: float = 1.0

const LOW: float = -0.5
const HIGH: float = 0.55
## The ink is deadly while its surface is above this height over the deck.
const DEADLY_Y: float = 0.06

var _area: Area3D
var _slab: MeshInstance3D
var _mat: ShaderMaterial
var _bubbles: GPUParticles3D
var _splash: GPUParticles3D
var _wisps: Array[MeshInstance3D] = []
var _wisp_mats: Array[StandardMaterial3D] = []
var _state: int = -1
var _loop: AudioStreamPlayer3D


func _ready() -> void:
	tell_time = maxf(tell_time, KitUtil.MIN_TELL)
	rise_time = maxf(rise_time, KitUtil.MIN_TELL)
	period = maxf(period, tell_time + rise_time + wet_time + fall_time + 1.5)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, HIGH - LOW - 0.1, size.y)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, (HIGH + LOW) * 0.5, 0)
	_area.add_child(cs)
	add_child(_area)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/arcane_ink.gdshader")
	_mat.set_shader_parameter("flow", flow)
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.4, maxf(size.y - 0.1, 0.5))
	_slab = Look.mesh_node(bm, _mat)
	_slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_slab)
	_build_fx()
	_apply(Game.course_time)
	add_to_group("course_clock")


## Seconds into the cycle when the dry spell ends and the tell begins.
func dry_time() -> float:
	return period - tell_time - rise_time - wet_time - fall_time


## Height of the ink's surface over the deck at `time`.
func ink_y(time: float) -> float:
	var s: float = KitUtil.cycle_s(time, period, phase)
	s -= dry_time() + tell_time
	if s < 0.0:
		return LOW
	if s < rise_time:
		return lerpf(LOW, HIGH, KitUtil.smooth(s / rise_time))
	s -= rise_time
	if s < wet_time:
		return HIGH
	s -= wet_time
	if s < fall_time:
		return lerpf(HIGH, LOW, KitUtil.smooth(s / fall_time))
	return LOW


func is_deadly_at(time: float) -> bool:
	return ink_y(time) > DEADLY_Y


## 0 dry, 1 tell, 2 rising, 3 wet, 4 draining.
func state_at(time: float) -> int:
	var s: float = KitUtil.cycle_s(time, period, phase)
	var d: float = dry_time()
	if s < d:
		return 0
	s -= d
	if s < tell_time:
		return 1
	s -= tell_time
	if s < rise_time:
		return 2
	s -= rise_time
	if s < wet_time:
		return 3
	return 4


## True while the bridge stays free of ink for the whole of [time, time + window].
func dry_for(time: float, window: float) -> bool:
	return KitUtil.holds_for(func(x: float) -> bool: return not is_deadly_at(x), time, window, 0.04)


## Seconds until the ink next starts to rise over the bridge (0 while it is up).
func rise_in(time: float) -> float:
	var s: float = 0.0
	while s < period + 1.0:
		if is_deadly_at(time + s):
			return s
		s += 0.05
	return period


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	if not is_deadly_at(Game.course_time):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			KitUtil.kill(self)
			return


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var y: float = ink_y(t)
	_slab.position = Vector3(0, y - 0.2, 0)
	var st: int = state_at(t)
	var s: float = KitUtil.cycle_s(t, period, phase) - dry_time()
	var agit: float = 0.0
	match st:
		1:
			agit = clampf(s / tell_time, 0.0, 1.0)
		2, 3:
			agit = 1.0
		4:
			agit = 0.5
	_mat.set_shader_parameter("agitation", agit)
	# the wisps over the river flash violet through the tell and burn while the ink is up
	for i: int in _wisps.size():
		var e: float = 0.5
		if st == 1:
			e = 1.5 + 5.0 * (0.5 + 0.5 * sin(t * (10.0 + 14.0 * agit))) * agit
		elif st == 2 or st == 3:
			e = 6.0
		_wisp_mats[i].emission_energy_multiplier = e
	if st != _state:
		_state = st
		match st:
			1:
				_bubbles.emitting = true
				# SOUND: arcane_ink_bubble - the ink starts to gurgle and churn (~1.1 s before it rises)
				WorldAudio.at(self, "arcane_ink_bubble", global_position, 0.8, 30.0)
			2:
				_splash.restart()
				_splash.emitting = true
				# SOUND: arcane_ink_surge - a heavy rush as the ink swells over the bridge
				WorldAudio.at(self, "arcane_ink_surge", global_position, 1.0, 36.0)
			4:
				_bubbles.emitting = false
			0:
				_bubbles.emitting = false


func _build_fx() -> void:
	var vis := AABB(Vector3(-size.x * 0.5 - 2.0, -2.0, -size.y * 0.5 - 2.0), Vector3(size.x + 4.0, 7.0, size.y + 4.0))
	_bubbles = Fx.emitter({"amount": 40, "lifetime": 1.1, "emitting": false, "shape": "box",
		"extents": Vector3(size.x * 0.22, 0.05, size.y * 0.4), "dir": Vector3.UP, "spread": 25.0,
		"speed": Vector2(0.6, 2.4), "gravity": Vector3(0, -3.0, 0), "tex": Fx.Tex.BUBBLE, "size": 0.2,
		"additive": false, "color": Color(0.35, 0.22, 0.7, 0.8), "curve": "shrink", "turbulence": 0.6,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	_bubbles.position = Vector3(0, LOW + 0.1, 0)
	add_child(_bubbles)
	_splash = Fx.sparks({"amount": 30, "lifetime": 0.8, "shape": "box", "extents": Vector3(size.x * 0.2, 0.05, size.y * 0.4),
		"dir": Vector3.UP, "spread": 40.0, "speed": Vector2(3.0, 7.5), "gravity": Vector3(0, -14.0, 0),
		"color": Color(1.0, 0.8, 0.45) * 2.0, "size": Vector2(0.06, 0.4), "aabb": vis})
	_splash.position = Vector3(0, 0.1, 0)
	add_child(_splash)
	# two will-o-wisp flames hovering over the river at its banks
	for sx: float in [-1.0, 1.0]:
		var m: StandardMaterial3D = Look.flat(Color(0.6, 0.4, 1.0), 0.3, 0.0, 0.5).duplicate() as StandardMaterial3D
		var w: MeshInstance3D = Look.sphere(0.16, m, Vector3(sx * (size.x * 0.5 - 1.0), 1.7, 0.0))
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
		_wisps.append(w)
		_wisp_mats.append(m)
	_loop = WorldAudio.loop("arcane_ink_flow", self, -17.0, 16.0, 4.0)
