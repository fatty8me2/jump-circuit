class_name SiegeVolley
extends Node3D
## Castle Siege: an ARROW VOLLEY. Archers on the far battlements loose a volley that lands on this
## painted strip of stone once per `period` (Game.course_time). The strip is always faintly marked
## (red chevrons that point toward the archers); for `warn` seconds (the tell, at least 0.8) before the
## arrows land a horn sounds, the chevrons flare amber and a bar of light sweeps across the strip, and
## for the last half second the arrows themselves are seen streaking down. The strip is deadly for
## `deadly` seconds (everything inside it, from the floor to head height), then the arrows stand in the
## stone. Node origin = the floor point at the strip's centre; `size` = (width across x, depth along z).
## A pure function of the course clock: identical for every racer.

@export var size: Vector2 = Vector2(3.0, 5.0)
@export var period: float = 4.5
@export var phase: float = 0.0
@export var warn: float = 1.4
@export var deadly: float = 0.4
## Height the arrows fall from.
@export var drop: float = 15.0

const FALL_TIME: float = 0.55

var _strip_mat: StandardMaterial3D
var _bar: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _rain: GPUParticles3D
var _stuck: Array[MeshInstance3D] = []
var _puff: GPUParticles3D
var _was_deadly: bool = false
var _horned: bool = false
var _rained: bool = false
var _hit_tick: int = -100


func _ready() -> void:
	warn = maxf(warn, 0.8)
	_build()
	_was_deadly = is_deadly_at(Game.course_time)
	_apply(Game.course_time)
	add_to_group("course_clock")


func snap_to_clock() -> void:
	_was_deadly = is_deadly_at(Game.course_time)
	_apply(Game.course_time)


func _s(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0) * period


func is_deadly_at(time: float) -> bool:
	return _s(time) < deadly


## Seconds until the next landing (0 while deadly).
func time_until_impact(time: float) -> float:
	var s: float = _s(time)
	return 0.0 if s < deadly else period - s


## True when no volley lands on the strip anywhere in [time + a, time + b] (a little margin either side).
func is_clear_between(time: float, a: float, b: float, margin: float = 0.12) -> bool:
	var s: float = a - margin
	while s <= b + margin:
		if is_deadly_at(time + s):
			return false
		s += 0.03
	return not is_deadly_at(time + b + margin)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_deadly_at(t):
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		return
	var p: Vector3 = to_local(pl.global_position)
	if absf(p.x) < size.x * 0.5 + 0.15 and absf(p.z) < size.y * 0.5 + 0.15 and p.y > -1.0 and p.y < 2.4:
		var tick: int = Engine.get_physics_frames()
		if tick - _hit_tick > 20:
			_hit_tick = tick
			KitUtil.kill(self)


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var until: float = time_until_impact(t)
	var deadly_now: bool = until <= 0.0
	var glow: float = 0.7 + 0.25 * sin(t * 2.5)
	var sweep: float = -1.0
	if deadly_now:
		glow = 6.0
		sweep = 1.0
	elif until < warn:
		var k: float = 1.0 - until / warn
		glow = 1.3 + 4.5 * k * (0.7 + 0.3 * sin(t * (9.0 + 22.0 * k)))
		sweep = k
	_strip_mat.emission_energy_multiplier = glow
	_bar.visible = sweep >= 0.0
	if _bar.visible:
		# a bar of light sweeps from the archers' side (far end, local -z) toward the near end
		_bar.position.z = lerpf(-size.y * 0.5, size.y * 0.5, clampf(sweep, 0.0, 1.0))
		_bar_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.25 + 0.45 * sweep)
	# the horn at the start of the tell
	if until < warn and not deadly_now:
		if not _horned:
			_horned = true
			# SOUND: siege_volley_horn - a war horn blast and the creak of drawn bows (the audible tell)
			WorldAudio.at(self, "siege_volley_horn", global_position + Vector3(0, 2.0, 0), 0.9, 55.0)
		if not _rained and until < FALL_TIME:
			_rained = true
			_rain.restart()
			_rain.emitting = true
			# SOUND: siege_volley_whoosh - a hundred arrows hissing down
			WorldAudio.at(self, "siege_volley_whoosh", global_position + Vector3(0, 4.0, 0), 0.9, 50.0)
	elif until > warn + 0.3:
		_horned = false
		_rained = false
	if deadly_now and not _was_deadly:
		_puff.restart()
		_puff.emitting = true
		for a: MeshInstance3D in _stuck:
			a.visible = true
		# SOUND: siege_volley_hit - a rattle of arrows thudding into stone and timber
		WorldAudio.at(self, "siege_volley_hit", global_position + Vector3(0, 0.5, 0), 1.0, 55.0)
	_was_deadly = deadly_now


func _build() -> void:
	# the strip: a faint red-and-amber painted panel with chevrons pointing toward the archers (-z)
	_strip_mat = StandardMaterial3D.new()
	_strip_mat.albedo_color = Color(0.3, 0.07, 0.04)
	_strip_mat.emission_enabled = true
	_strip_mat.emission = Color(1.0, 0.45, 0.1)
	_strip_mat.emission_energy_multiplier = 1.0
	var rim := 0.12
	for sx: float in [-1.0, 1.0]:
		var edge := Look.box(Vector3(rim, 0.05, size.y), _strip_mat, Vector3(sx * (size.x * 0.5 - rim * 0.5), 0.04, 0))
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(edge)
	for sz: float in [-1.0, 1.0]:
		var edge2 := Look.box(Vector3(size.x, 0.05, rim), _strip_mat, Vector3(0, 0.04, sz * (size.y * 0.5 - rim * 0.5)))
		edge2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(edge2)
	var nchev: int = maxi(int(size.y / 1.6), 1)
	for i: int in nchev:
		var z: float = -size.y * 0.5 + (float(i) + 0.5) * size.y / float(nchev)
		for sx2: float in [-1.0, 1.0]:
			var arm := Look.box(Vector3(size.x * 0.34, 0.04, 0.1), _strip_mat, Vector3(sx2 * size.x * 0.15, 0.04, z + 0.14))
			arm.rotation.y = -sx2 * 0.55
			arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(arm)
	# the light bar sweeping the strip
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bar_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.3)
	_bar = Look.box(Vector3(size.x - 0.2, 0.03, 0.34), _bar_mat, Vector3(0, 0.07, 0))
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	# arrows standing in the stone after a volley (they appear at the first hit and stay)
	var shaft: StandardMaterial3D = Look.flat(Color(0.5, 0.36, 0.2), 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x * 7.0 + global_position.z * 13.0)) + 11
	for i: int in 14:
		var a := Look.box(Vector3(0.035, 0.7, 0.035), shaft, Vector3(rng.randf_range(-0.5, 0.5) * size.x, 0.28, rng.randf_range(-0.5, 0.5) * size.y))
		a.rotation = Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		a.visible = false
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(a)
		_stuck.append(a)
	# the rain: streaks of arrows falling over the strip (fired by hand, see _apply)
	var vis := AABB(Vector3(-size.x - 2.0, -2.0, -size.y - 2.0), Vector3(size.x * 2.0 + 4.0, drop + 6.0, size.y * 2.0 + 4.0))
	_rain = Fx.emitter({"amount": clampi(int(size.x * size.y * 2.2), 24, 90), "lifetime": FALL_TIME + 0.05, "one_shot": true,
		"emitting": false, "explosiveness": 0.35, "shape": "box", "extents": Vector3(size.x * 0.5, 0.1, size.y * 0.5),
		"offset": Vector3(0, drop, 0), "dir": Vector3.DOWN, "spread": 3.0, "speed": Vector2(drop / FALL_TIME - 1.0, drop / FALL_TIME + 1.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.05, 1.1), "color": Color(2.2, 1.7, 1.0),
		"fade": PackedFloat32Array([1.0, 1.0, 1.0]), "aabb": vis})
	add_child(_rain)
	_puff = Fx.smoke({"amount": 16, "lifetime": 0.9, "shape": "box", "extents": Vector3(size.x * 0.5, 0.05, size.y * 0.5),
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(0.8, 2.2), "size": 0.9, "color": Color(0.7, 0.62, 0.52, 0.55),
		"aabb": vis})
	_puff.position = Vector3(0, 0.2, 0)
	add_child(_puff)
