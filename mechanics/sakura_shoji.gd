class_name SakuraShoji
extends Node3D
## Sakura Peaks: PAPER SLIDING DOORS. A doorway in a timber-and-paper screen wall whose two shoji
## panels slide shut across it and open again on the course clock. For `WARN` s before they close
## the lamps behind the paper flare and the panels twitch in their track (and clack); then they
## slide shut. Shut, the doorway is a wall. Anyone in the doorway as they close is bundled back out
## the way they came (a shove, never a kill). Pass while they are open.
## A pure function of Game.course_time.
## Node origin = the floor point in the middle of the doorway; local X across it, the corridor runs
## along local Z. The wall pockets either side are solid and part of this node.

@export var width: float = 2.8
@export var height: float = 2.8
@export var period: float = 4.0
@export var phase: float = 0.0
## Fraction of the cycle spent fully open.
@export var open_fraction: float = 0.5
## Width of the solid screen wall either side (the pockets the panels slide into).
@export var wing: float = 3.2

const WARN: float = 0.8
const CLOSE_TIME: float = 0.25
const OPEN_TIME: float = 0.45
## The panels run in a track just in front of the screen wall (so they never fight its paper).
const TRACK_Z: float = 0.13

var _panels: Array[AnimatableBody3D] = []
var _area: Area3D
var _glow: Array[StandardMaterial3D] = []
var _cool: float = 0.0
var _warned: int = -1
var _shut: int = -1
var _puff: GPUParticles3D


func _ready() -> void:
	_build()
	_apply(Game.course_time)
	add_to_group("course_clock")


func _s(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0) * period


## 0 (open) .. 1 (shut) at `time`. Cycle: open (open_fraction) -> close -> shut -> open.
func closed_at(time: float) -> float:
	var s: float = _s(time)
	var open_end: float = period * open_fraction
	if s < open_end:
		return 0.0
	if s < open_end + CLOSE_TIME:
		var k: float = (s - open_end) / CLOSE_TIME
		return k * k * (3.0 - 2.0 * k)
	var shut_end: float = period - OPEN_TIME
	if s < shut_end:
		return 1.0
	var k2: float = (s - shut_end) / OPEN_TIME
	return 1.0 - k2 * k2 * (3.0 - 2.0 * k2)


## Seconds until the doors start closing (0 while they are closing or shut).
func time_until_close(time: float) -> float:
	var s: float = _s(time)
	var open_end: float = period * open_fraction
	return open_end - s if s < open_end else 0.0


## The doorway stays fully open over [now + a, now + b].
func open_between(a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if closed_at(Game.course_time + s) > 0.02:
			return false
		s += 0.03
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)
	for p: AnimatableBody3D in _panels:
		p.reset_physics_interpolation()


func _apply(time: float) -> void:
	var c: float = closed_at(time)
	var q: float = width * 0.25
	for i: int in _panels.size():
		var sx: float = -1.0 if i == 0 else 1.0
		# open: tucked into the pocket beside the doorway; shut: meeting in the middle
		var open_x: float = sx * (width * 0.5 + q + 0.05)
		var shut_x: float = sx * q
		_panels[i].position = Vector3(lerpf(open_x, shut_x, c), height * 0.5, TRACK_Z)


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0 or closed_at(t) <= 0.05:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var lz: float = to_local(body.global_position).z
			var back: Vector3 = global_basis.z.normalized() * (1.0 if lz >= 0.0 else -1.0)
			(body as Player).knockback(back * 7.5 + Vector3(0, 5.0, 0))
			_cool = 0.5


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var s: float = _s(t)
	var open_end: float = period * open_fraction
	var warn: bool = s > open_end - WARN and s < open_end
	var c: float = closed_at(t)
	var flare: float = 0.6
	if warn:
		flare = 1.2 + (1.4 if fmod(t, 0.2) < 0.1 else 0.6)
	elif c > 0.5:
		flare = 1.0
	for m: StandardMaterial3D in _glow:
		m.emission_energy_multiplier = flare
	var cycle: int = int(floor(t / maxf(period, 0.01) + phase))
	if warn and cycle != _warned:
		_warned = cycle
		# SOUND: the frames rattling in their track (the tell, ~0.8 s before they slam)
		WorldAudio.at(self, "sakura_shoji_rattle", global_position, 0.8, 35.0)
	if c > 0.9 and cycle != _shut:
		_shut = cycle
		_puff.restart()
		_puff.emitting = true
		# SOUND: the panels clapping shut
		WorldAudio.at(self, "sakura_shoji_slam", global_position, 1.0, 40.0)
	# panels twitch in the warning
	if warn:
		for i: int in _panels.size():
			_panels[i].position.y = height * 0.5 + 0.02 * sin(t * 55.0 + float(i))


func _panel_visual(parent: Node3D, w: float, h: float, glow_m: StandardMaterial3D) -> void:
	var frame: StandardMaterial3D = SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.7)
	parent.add_child(Look.box(Vector3(w, h, 0.06), glow_m))
	for sx: float in [-1.0, 1.0]:
		parent.add_child(Look.box(Vector3(0.1, h, 0.14), frame, Vector3(sx * (w * 0.5 - 0.05), 0, 0)))
	for sy: float in [-1.0, 1.0]:
		parent.add_child(Look.box(Vector3(w, 0.12, 0.14), frame, Vector3(0, sy * (h * 0.5 - 0.06), 0)))
	# the kumiko lattice
	for i: int in 3:
		parent.add_child(Look.box(Vector3(0.04, h - 0.2, 0.1), frame, Vector3((float(i) - 1.0) * w * 0.25, 0, 0)))
	for j: int in 5:
		parent.add_child(Look.box(Vector3(w - 0.2, 0.04, 0.1), frame, Vector3(0, -h * 0.5 + (float(j) + 1.0) * h / 6.0, 0)))


func _build() -> void:
	var dark: StandardMaterial3D = SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.7)
	var q: float = width * 0.25
	# the wall either side: solid screens with lattice faces (they hold the pockets)
	for sx: float in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var bs := BoxShape3D.new()
		bs.size = Vector3(wing, height + 0.6, 0.5)
		var cs := CollisionShape3D.new()
		cs.shape = bs
		body.add_child(cs)
		body.position = Vector3(sx * (width * 0.5 + wing * 0.5), (height + 0.6) * 0.5, 0)
		add_child(body)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = SakuraDecor.PAPER
		gm.roughness = 0.95
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.75, 0.45)
		gm.emission_energy_multiplier = 0.6
		_glow.append(gm)
		var face := Node3D.new()
		face.position = Vector3(0, -0.3, 0)
		body.add_child(face)
		_panel_visual(face, wing, height, gm)
		body.add_child(Look.box(Vector3(wing, 0.3, 0.55), dark, Vector3(0, (height + 0.6) * 0.5 - 0.15, 0)))
	# lintel and threshold track
	add_child(Look.box(Vector3(width + wing * 2.0 + 0.4, 0.4, 0.7), dark, Vector3(0, height + 0.6 + 0.2, 0)))
	add_child(Look.box(Vector3(width + 0.2, 0.05, 0.4), SakuraDecor.mat(SakuraDecor.LACQUER, 0.4), Vector3(0, 0.025, 0)))
	# a little tiled roof over the gate
	var tile: StandardMaterial3D = SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15)
	var roof := Look.box(Vector3(width + wing * 2.0 + 1.2, 0.18, 1.6), tile, Vector3(0, height + 1.1, 0))
	add_child(roof)
	# the two sliding panels (kinematic, solid)
	for sx: float in [-1.0, 1.0]:
		var p := AnimatableBody3D.new()
		p.sync_to_physics = false
		p.collision_layer = 1
		p.collision_mask = 0
		var ps := BoxShape3D.new()
		ps.size = Vector3(width * 0.5, height, 0.16)
		var pcs := CollisionShape3D.new()
		pcs.shape = ps
		p.add_child(pcs)
		var gm2 := StandardMaterial3D.new()
		gm2.albedo_color = SakuraDecor.PAPER
		gm2.roughness = 0.95
		gm2.cull_mode = BaseMaterial3D.CULL_DISABLED
		gm2.emission_enabled = true
		gm2.emission = Color(1.0, 0.75, 0.45)
		gm2.emission_energy_multiplier = 0.6
		_glow.append(gm2)
		_panel_visual(p, width * 0.5, height, gm2)
		# a painted blossom branch on each panel (abstract: a dark stroke and pink dabs)
		p.add_child(Look.box(Vector3(width * 0.4, 0.05, 0.08), dark, Vector3(0, height * 0.15, 0)))
		for k: int in 4:
			p.add_child(Look.sphere(0.09, SakuraDecor.blossom(SakuraDecor.BLOSSOM_DEEP), Vector3((float(k) - 1.5) * width * 0.09, height * 0.15 + 0.1 * float(k % 2), 0)))
		add_child(p)
		_panels.append(p)
		p.position = Vector3(sx * (width * 0.5 + q + 0.05), height * 0.5, TRACK_Z)
	# the shove detector: the doorway itself
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var ab := BoxShape3D.new()
	ab.size = Vector3(width, height, 1.1)
	var acs := CollisionShape3D.new()
	acs.shape = ab
	_area.add_child(acs)
	_area.position = Vector3(0, height * 0.5, 0)
	add_child(_area)
	_puff = SakuraFx.petal_pop(width * 0.5, 24, 3.0)
	_puff.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
	_puff.position = Vector3(0, height * 0.6, 0)
	add_child(_puff)
