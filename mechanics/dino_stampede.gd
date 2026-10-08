class_name DinoStampede
extends Node3D
## Dino Valley: a STAMPEDE lane. Every `period` s a herd of runners bursts out of the haze at one end
## of a wide trampled deck and thunders across it to the other end, `count` ranks deep with the
## ranks `gap` m apart, filling the whole `width` of the lane. Anyone the herd runs over is sent back
## to the checkpoint; the gaps between herds (and between the ranks) are the way across.
## The tell is long and loud: a rumble and a herd call the moment it sets off (`run_in` s of running
## before it reaches the centre of the lane, over 1.8 s by default), a dust cloud boiling off its
## front, the herd itself in plain view coming across the deck, and the lane strip flashing amber.
## A pure function of Game.course_time. The node sits at the floor point in the middle of the lane;
## the herd runs along local X (`direction` +1 = toward +X), the way across is along local Z.

@export var span: float = 26.0
@export var width: float = 5.0
@export var speed: float = 14.0
@export var period: float = 7.0
@export var phase: float = 0.0
@export var count: int = 3
@export var gap: float = 4.5
@export var lead: float = 14.0
@export var direction: float = 1.0
@export var creature_scale: float = 1.5
@export var kind: String = "raptor"

const KILL_HALF_LEN: float = 1.5
const KILL_HEIGHT: float = 2.1

var _run: float = 1.0
var _start_x: float = 0.0
var _rows: Array[Array] = []
var _strip: MeshInstance3D
var _dust: GPUParticles3D
var _thunder: AudioStreamPlayer3D
var _voice: Node3D
var _last_u: float = -1.0
var _shake_t: float = 0.0
var _abreast: int = 3


func _ready() -> void:
	direction = 1.0 if direction >= 0.0 else -1.0
	_abreast = maxi(roundi(width / 1.9), 1)
	_start_x = -direction * (span * 0.5 + lead)
	_run = (span + 2.0 * lead + float(count - 1) * gap) / maxf(speed, 1.0)
	period = maxf(period, _run + 1.5)
	_build()
	add_to_group("course_clock")
	_apply(Game.course_time)


# ---- the clock ---------------------------------------------------------------------------------

func _s(time: float) -> float:
	return KitUtil.cycle_s(time, period, phase)


## Lane-local x of rank `r` at `time` (INF when the herd is not on its way).
func rank_x(r: int, time: float) -> float:
	var s: float = _s(time)
	if s > _run:
		return INF
	return _start_x + direction * speed * s - direction * gap * float(r)


## Seconds into the cycle at which the herd's front reaches local x.
func front_reaches(x: float) -> float:
	return (x - _start_x) * direction / speed


## No rank can touch the crossing at lane-local x `x` during [now + a, now + b] (margin metres either side).
func clear_for(x: float, a: float, b: float, margin: float = 1.0) -> bool:
	var s: float = a
	while s <= b:
		var t: float = Game.course_time + s
		for r: int in count:
			var rx: float = rank_x(r, t)
			if rx != INF and absf(rx - x) < KILL_HALF_LEN + margin:
				return false
		s += 0.04
	return true


## Seconds from `time` until the front of the next herd starts running (0 while one is on the deck).
func sets_off_in(time: float) -> float:
	var s: float = _s(time)
	return 0.0 if s <= _run else period - s


func snap_to_clock() -> void:
	_apply(Game.course_time)


# ---- behaviour -----------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	var s: float = _s(t)
	if s > _run:
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl != null:
		var p: Vector3 = to_local(pl.global_position)
		if absf(p.z) <= width * 0.5 + 0.35 and p.y > -0.6 and p.y < KILL_HEIGHT:
			for r: int in count:
				var rx: float = rank_x(r, t)
				if rx != INF and absf(rx - p.x) < KILL_HALF_LEN + 0.2:
					KitUtil.kill(self, "hazard")
					return
		# the ground shakes as the herd passes close by
		var near: float = absf(rank_x(0, t) - p.x)
		if near < 30.0 and absf(p.z) < width + 14.0:
			_shake_t -= dt
			if _shake_t <= 0.0:
				_shake_t = 0.22
				_shake(clampf(0.16 * (1.0 - near / 30.0), 0.02, 0.2))


func _apply(t: float) -> void:
	var s: float = _s(t)
	var on: bool = s <= _run
	# the lane strip flashes amber from the moment the herd sets off until its last rank has passed
	var flash: float = 0.0
	if on:
		flash = 0.35 + 0.35 * (1.0 if fmod(s, 0.3) < 0.15 else 0.35)
	KitUtil.set_quad_color(_strip, Color(1.0, 0.62, 0.12, flash))
	_strip.visible = on
	for r: int in _rows.size():
		var row: Array = _rows[r]
		var rx: float = rank_x(r, t)
		var vis: bool = rx != INF and absf(rx) < span * 0.5 + lead + 4.0
		for c: Variant in row:
			var d: DinoCreature = c as DinoCreature
			d.visible = vis
			if vis:
				d.position.x = rx
				d.gait = s * speed * 1.55 + float(d.get_meta("off", 0.0))
				d.amount = 1.0
	if on and _dust != null:
		_dust.emitting = true
		_dust.position = Vector3(clampf(rank_x(0, t), -span * 0.5 - lead, span * 0.5 + lead), 0.3, 0)
	elif _dust != null:
		_dust.emitting = false
	if _voice != null:
		_voice.position = Vector3(clampf(rank_x(0, t), -span * 0.5 - lead, span * 0.5 + lead), 1.0, 0)
	WorldAudio.set_active(_thunder, on)
	var u: float = s
	if _last_u >= 0.0 and u < _last_u and u < 0.3:
		# SOUND: dino_stampede_call - the herd's bellow as it sets off (the audible tell)
		WorldAudio.at(self, "dino_stampede_call", global_position + Vector3(_start_x * 0.3, 1.5, 0), 1.0, 90.0)
	_last_u = u


func _shake(amount: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and cam.has_method("add_trauma"):
		cam.call("add_trauma", amount)


# ---- look ----------------------------------------------------------------------------------------

func _build() -> void:
	# the trampled lane: a strip of churned earth with a flashing amber overlay for the tell
	var dirt: MeshInstance3D = KitUtil.floor_quad(Vector2(span + lead, width + 1.6), Color(0.36, 0.26, 0.17, 0.5))
	dirt.position = Vector3(0, 0.025, 0)
	add_child(dirt)
	_strip = KitUtil.floor_quad(Vector2(span + lead, width + 1.0), Color(1.0, 0.62, 0.12, 0.0))
	_strip.position = Vector3(0, 0.05, 0)
	add_child(_strip)
	# hoof-print chevrons on the lane showing the way the herd runs
	var chev: StandardMaterial3D = Look.flat(Color(0.2, 0.14, 0.09), 0.95)
	for i: int in 8:
		var x: float = (float(i) - 3.5) * (span / 8.0)
		var tri := Look.box(Vector3(0.9, 0.02, 0.22), chev, Vector3(x, 0.035, 0))
		tri.rotation.y = 0.5 * direction
		tri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tri)
		var tri2 := Look.box(Vector3(0.9, 0.02, 0.22), chev, Vector3(x, 0.035, 0))
		tri2.rotation.y = -0.5 * direction
		tri2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tri2)
	# the herd: `count` ranks, `_abreast` runners shoulder to shoulder in each
	for r: int in count:
		var row: Array = []
		for k: int in _abreast:
			var d: DinoCreature = DinoCreature.make(kind, creature_scale, Color(0, 0, 0, 0), 1)
			var zc: float = (float(k) - float(_abreast - 1) * 0.5) * (width / float(_abreast))
			d.position = Vector3(0, 0, zc)
			d.rotation.y = -PI * 0.5 * direction
			d.set_meta("off", float(r * 3 + k) * 1.3)
			d.visible = false
			add_child(d)
			row.append(d)
		_rows.append(row)
	var vis := AABB(Vector3(-span, -2.0, -width - 8.0), Vector3(span * 2.0, 10.0, width * 2.0 + 16.0))
	_dust = Fx.emitter({"amount": 64, "lifetime": 1.8, "shape": "box", "extents": Vector3(0.6, 0.2, width * 0.5), "emitting": false,
		"dir": Vector3(-direction, 0.4, 0), "spread": 40.0, "speed": Vector2(1.5, 4.5), "gravity": Vector3(0, 0.5, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 2.6, "scale": Vector2(0.7, 1.4), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-30, 30), "color": Color(0.82, 0.68, 0.46, 0.55),
		"fade": PackedFloat32Array([0.0, 0.9, 0.0]), "aabb": vis})
	_dust.top_level = false
	add_child(_dust)
	_voice = Node3D.new()
	add_child(_voice)
	_thunder = WorldAudio.loop("dino_stampede_thunder", _voice, -3.0, 70.0, 10.0, false)
