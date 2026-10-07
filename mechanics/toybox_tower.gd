class_name ToyboxTower
extends AnimatableBody3D
## Toybox Tumble: a TOPPLING BLOCK TOWER. A stack of painted blocks standing at the edge of a
## gap. On a rhythm (a pure function of Game.course_time, identical for every racer) it wobbles for
## `wobble` s (the tell: it creaks, sways and its blocks glow), then topples across the gap and
## lies there as a BRIDGE for `flat_time`. The last `lift_tell` s of that the blocks pulse and a
## chime rings (get off!), and then it springs back upright (`rise_time`), ready to topple again.
## The node sits at the hinge: the near end's top edge, level with the platform you cross from.
## Flat, the walkable top (y = 0) runs `length` m toward local -Z, level with the platform on the
## far side. `thickness` is the block depth (the tower's footprint when it stands).

@export var width: float = 2.4
@export var thickness: float = 1.6
@export var length: float = 8.0
## Seconds standing (the last `wobble` of them swaying), the fall, the bridge and the rise.
@export var up_time: float = 2.4
@export var wobble: float = 1.2
@export var fall_time: float = 0.5
@export var flat_time: float = 5.6
@export var lift_tell: float = 1.2
@export var rise_time: float = 1.0
@export var phase: float = 0.0
@export var colors: PackedColorArray = PackedColorArray([Color(0.95, 0.28, 0.25), Color(1.0, 0.8, 0.2), Color(0.25, 0.55, 0.95), Color(0.3, 0.75, 0.4)])

var _blocks: Array[MeshInstance3D] = []
var _glow: Array[StandardMaterial3D] = []
var _dust_near: GPUParticles3D
var _dust_far: GPUParticles3D
var _stage: int = -1
var _tick: int = -1
var _base_basis: Basis = Basis.IDENTITY


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_base_basis = basis
	var box := BoxShape3D.new()
	box.size = Vector3(width, thickness, length)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, -thickness * 0.5, -length * 0.5)
	add_child(cs)
	_build_blocks()
	var vis := AABB(Vector3(-8, -4, -length - 8.0), Vector3(16, length + 12.0, length + 16.0))
	_dust_near = Fx.burst({"amount": 22, "lifetime": 0.9, "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.2,
		"shape": "box", "extents": Vector3(width * 0.5, 0.1, 0.4), "dir": Vector3.UP, "spread": 70.0,
		"speed": Vector2(1.0, 3.5), "color": Color(0.95, 0.88, 0.75, 0.55), "curve": "puff", "aabb": vis})
	_dust_near.top_level = true
	add_child(_dust_near)
	_dust_far = Fx.burst({"amount": 28, "lifetime": 1.0, "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.4,
		"shape": "box", "extents": Vector3(width * 0.5, 0.1, 0.6), "dir": Vector3.UP, "spread": 75.0,
		"speed": Vector2(1.5, 4.5), "color": Color(0.95, 0.88, 0.75, 0.55), "curve": "puff", "aabb": vis})
	_dust_far.top_level = true
	add_child(_dust_far)
	_apply(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func _build_blocks() -> void:
	var n: int = maxi(int(round(length / thickness)), 2)
	var seg: float = length / float(n)
	for i: int in n:
		var col: Color = colors[i % colors.size()]
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.45
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.0
		_glow.append(m)
		var z: float = -(float(i) + 0.5) * seg
		var b := Look.box(Vector3(width, thickness, seg - 0.04), m, Vector3(0, -thickness * 0.5, z))
		add_child(b)
		_blocks.append(b)
		# the walking face: a lighter inset panel with a star, flush on top (this is the bridge's floor)
		var top := Look.box(Vector3(width - 0.4, 0.03, seg - 0.4), Look.flat(col.lerp(Color.WHITE, 0.35), 0.5), Vector3(0, 0.012, z))
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(top)
		# rounded corner studs on the side faces so it reads as a toy block, not a plank
		for sx: float in [-1.0, 1.0]:
			var pip := Look.cylinder(0.22, 0.05, Look.flat(col.lerp(Color.WHITE, 0.5), 0.5), Vector3(sx * (width * 0.5 + 0.02), -thickness * 0.5, z), -1.0, 12)
			pip.rotation.z = PI * 0.5
			add_child(pip)
	# a low base the tower stands on when it is upright (tucked inside the bridge when it lies down)
	var base := Look.box(Vector3(width - 0.2, 0.6, thickness + 0.4), Look.flat(Color(0.55, 0.38, 0.25), 0.7), Vector3(0, -0.34, -thickness * 0.5 + 0.2))
	add_child(base)


func _period() -> float:
	return up_time + fall_time + flat_time + rise_time


func _u(time: float) -> float:
	return fposmod(time + phase, _period())


## Stage at `time`: 0 standing, 1 wobbling, 2 falling, 3 flat, 4 flat and about to lift, 5 rising.
func stage_at(time: float) -> int:
	var u: float = _u(time)
	if u < up_time - wobble:
		return 0
	if u < up_time:
		return 1
	if u < up_time + fall_time:
		return 2
	var fl_end: float = up_time + fall_time + flat_time
	if u < fl_end - lift_tell:
		return 3
	if u < fl_end:
		return 4
	return 5


## Tilt about the hinge: PI/2 standing, 0 lying flat.
func angle_at(time: float) -> float:
	var u: float = _u(time)
	var up: float = PI * 0.5
	var st: int = stage_at(time)
	match st:
		0:
			return up
		1:
			var k: float = (u - (up_time - wobble)) / maxf(wobble, 0.01)
			var sway: float = 0.5 - 0.5 * cos(u * (9.0 + 14.0 * k))
			return up - deg_to_rad(1.0 + 7.0 * k) * sway
		2:
			var f: float = clampf((u - up_time) / maxf(fall_time, 0.01), 0.0, 1.0)
			return up * (1.0 - f * f)
		3, 4:
			return 0.0
	var r: float = clampf((u - (up_time + fall_time + flat_time)) / maxf(rise_time, 0.01), 0.0, 1.0)
	return up * (r * r * (3.0 - 2.0 * r))


## True when the bridge lies flat over all of [time + a, time + b].
func flat_over(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		var st: int = stage_at(time + s)
		if st != 3 and st != 4:
			return false
		s += 0.05
	var sb: int = stage_at(time + b)
	return sb == 3 or sb == 4


## Seconds until it next lies flat (0 while it does).
func time_to_flat(time: float) -> float:
	var s: float = 0.0
	while s < _period():
		var st: int = stage_at(time + s)
		if st == 3 or st == 4:
			return s
		s += 0.05
	return _period()


func snap_to_clock() -> void:
	_apply(Game.course_time)
	reset_physics_interpolation()


func _apply(time: float) -> void:
	basis = _base_basis * Basis(Vector3.RIGHT, angle_at(time))


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var st: int = stage_at(t)
	var u: float = _u(t)
	# glow tell: swelling through the wobble, pulsing through the last second of the bridge
	var g: float = 0.0
	if st == 1:
		g = 0.3 + 1.6 * clampf((u - (up_time - wobble)) / maxf(wobble, 0.01), 0.0, 1.0)
	elif st == 4:
		var fl_end: float = up_time + fall_time + flat_time
		var w: float = clampf(1.0 - (fl_end - u) / maxf(lift_tell, 0.01), 0.0, 1.0)
		g = (0.4 + 1.8 * w) * (0.55 + 0.45 * sin(t * (12.0 + 18.0 * w)))
	for m: StandardMaterial3D in _glow:
		m.emission_energy_multiplier = g
	if st == 4:
		var tk: int = int(floor(t * 5.0))
		if tk != _tick:
			_tick = tk
			# SOUND: toybox_tower_chime - a music-box chime each beat of the last second (get off, it lifts)
			WorldAudio.at(self, "toybox_tower_chime", global_position + Vector3(0, 1.0, 0), 0.6, 30.0)
	if st == _stage:
		return
	var was: int = _stage
	_stage = st
	if was < 0:
		return
	match st:
		1:
			# SOUND: toybox_tower_creak - wooden blocks creaking as the tower starts to sway (1.2 s before it falls)
			WorldAudio.at(self, "toybox_tower_creak", global_position + Vector3(0, length * 0.5, 0), 0.8, 36.0)
		2:
			# SOUND: toybox_tower_fall - the stack tumbling over: a clatter of wooden blocks
			WorldAudio.at(self, "toybox_tower_fall", global_position + Vector3(0, length * 0.5, 0), 0.9, 40.0)
		3:
			_dust_near.global_position = global_position + Vector3(0, 0.2, 0)
			_dust_near.restart()
			_dust_far.global_position = global_position + global_basis * Vector3(0, 0.2, -length)
			_dust_far.restart()
			# SOUND: toybox_tower_thud - the tower slaps down across the gap
			WorldAudio.at(self, "toybox_tower_thud", global_position + Vector3(0, 0, -length * 0.5), 1.0, 44.0)
		5:
			# SOUND: toybox_tower_lift - the blocks ratchet back up like a toy on a spring
			WorldAudio.at(self, "toybox_tower_lift", global_position + Vector3(0, 0, -length * 0.5), 0.8, 36.0)
