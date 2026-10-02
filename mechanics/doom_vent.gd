class_name DoomVent
extends Node3D
## Doom Fortress: a STEAM VENT on the course clock - a round iron grate over a boiler pipe.
##  * LIFT vents (`lift` = true, white steam, grate solid): when the vent BLASTS, anyone standing on
##    the grate is flung up (and a little along the vent's facing) by `launch`, like a spring.
##  * SCALD vents (`lift` = false, red-hot): the blast is a column of scalding steam `plume` metres
##    tall that sends you back to the checkpoint for `blast` seconds. The grate itself is only a
##    decal on whatever floor it sits in (solid = false), so it can be set into a beam or a deck.
## The tell is loud and early: for the last `warn` seconds before each blast the grate glows from
## below, steam streaks hiss up through the bars, the pressure lamp flashes and a whistle sounds.
## A pure function of Game.course_time (identical for every racer). Positioned by the centre of
## the grate's TOP.

@export var lift: bool = true
@export var radius: float = 1.2
@export var period: float = 3.6
@export var phase: float = 0.0
## Seconds of warning before each blast.
@export var warn: float = 1.0
## Seconds the blast lasts (a scald vent is deadly for all of it; a lift vent launches at its start).
@export var blast: float = 0.8
## Launch velocity in the vent's own frame (local -Z is "forward"). Lift vents only.
@export var launch: Vector3 = Vector3(0, 19, -2.0)
## Height of the scalding column above the grate. Scald vents only.
@export var plume: float = 3.2
## Build a solid grate disc (lift vents stand alone; scald vents usually sit in a floor).
@export var solid: bool = true
## Height of the boiler housing under a solid grate (visual).
@export var base_height: float = 1.2

## The blast starts at this point of the cycle.
const FIRE: float = 0.8
## A lift vent launches riders during the first LAUNCH_WINDOW seconds of the blast.
const LAUNCH_WINDOW: float = 0.12

var _glow_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _area: Area3D
var _hiss: GPUParticles3D
var _jet: GPUParticles3D
var _jet2: GPUParticles3D
var _cool: float = 0.0
var _fired: int = -999
var _warned: int = -999
var _hit_tick: int = -100
var _light: OmniLight3D


func _ready() -> void:
	_build()
	add_to_group("course_clock")


func _u(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0)


func _cycle(time: float) -> int:
	return int(floor(time / maxf(period, 0.01) + phase))


## Seconds from `time` until the next blast starts.
func time_until_fire(time: float) -> float:
	return fposmod(FIRE - _u(time), 1.0) * period


## True while the vent is blasting at `time`.
func is_blasting_at(time: float) -> bool:
	var s: float = fposmod(_u(time) - FIRE, 1.0) * period
	return s < blast


## True while the vent hisses its warning at `time`.
func is_warning_at(time: float) -> bool:
	var left: float = time_until_fire(time)
	return left < warn and not is_blasting_at(time)


## No blast at any point of [now + a, now + b].
func clear_for(a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_blasting_at(Game.course_time + s):
			return false
		s += 0.04
	return true


## World velocity a rider is thrown with.
func launch_velocity() -> Vector3:
	return global_basis.orthonormalized() * launch


func snap_to_clock() -> void:
	pass


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_cool = maxf(_cool - dt, 0.0)
	var s: float = fposmod(_u(t) - FIRE, 1.0) * period
	if lift:
		if s < LAUNCH_WINDOW and _cool <= 0.0:
			for body: Node3D in _area.get_overlapping_bodies():
				if body is Player:
					(body as Player).knockback(launch_velocity())
					_cool = LAUNCH_WINDOW + 0.1
		return
	if s >= blast:
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		return
	var p: Vector3 = to_local(pl.global_position)
	if Vector2(p.x, p.z).length() < radius * 0.95 and p.y > -0.4 and p.y < plume:
		var tick: int = Engine.get_physics_frames()
		if tick - _hit_tick > 30:
			_hit_tick = tick
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var cyc: int = _cycle(t)
	var warning: bool = is_warning_at(t)
	var blasting: bool = is_blasting_at(t)
	var left: float = time_until_fire(t)
	var k: float = clampf(1.0 - left / maxf(warn, 0.01), 0.0, 1.0) if warning else 0.0
	_glow_mat.emission_energy_multiplier = 0.3 + (3.0 * k if warning else 0.0) + (3.2 if blasting else 0.0)
	_lamp_mat.emission_energy_multiplier = (4.0 if fmod(t, 0.2) < 0.1 else 0.6) if warning else (4.0 if blasting else 0.4)
	if _light != null:
		_light.light_energy = 0.4 + 2.0 * k + (3.0 if blasting else 0.0)
	_hiss.emitting = warning
	if warning and cyc != _warned and left > warn * 0.5:
		_warned = cyc
		# SOUND: doom_vent_hiss - pressure building, a rising whistle (the ~1 s warning)
		WorldAudio.at(self, "doom_vent_hiss", global_position, 0.8, 30.0)
	if blasting and cyc != _fired:
		_fired = cyc
		_jet.restart()
		_jet.emitting = true
		if _jet2 != null:
			_jet2.restart()
			_jet2.emitting = true
		# SOUND: doom_vent_blast - the steam jet roaring out
		WorldAudio.at(self, "doom_vent_blast", global_position, 1.0, 40.0)


func _build() -> void:
	var iron: StandardMaterial3D = DoomDecor.iron()
	var steel: StandardMaterial3D = DoomDecor.steel()
	var tint: Color = Color(1.0, 0.95, 0.85) if lift else Color(1.0, 0.25, 0.08)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = tint * 0.3
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.6, 0.3) if lift else Color(1.0, 0.18, 0.04)
	_glow_mat.emission_energy_multiplier = 0.3
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(1.0, 0.2, 0.1)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.15, 0.05)
	_lamp_mat.emission_energy_multiplier = 0.4
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = 0.4
		cs.shape = cyl
		cs.position = Vector3(0, -0.2, 0)
		body.add_child(cs)
		add_child(body)
		# the boiler housing under it, hazard ring round the rim
		add_child(Look.cylinder(radius * 0.9, base_height, iron, Vector3(0, -0.4 - base_height * 0.5, 0), radius * 0.7, 16))
		add_child(Look.cylinder(radius + 0.08, 0.4, steel, Vector3(0, -0.2, 0), -1.0, 24))
		add_child(DoomDecor.ns(Look.cylinder(radius + 0.1, 0.12, DoomDecor.hazard(0.5), Vector3(0, -0.06, 0), -1.0, 24)))
	else:
		add_child(Look.cylinder(radius + 0.05, 0.06, steel, Vector3(0, -0.02, 0), -1.0, 24))
	# the glowing throat under the bars, and the bars
	add_child(DoomDecor.ns(Look.cylinder(radius * 0.85, 0.04, _glow_mat, Vector3(0, 0.005, 0), -1.0, 20)))
	var bars: int = int(radius * 4.0)
	for i: int in bars:
		var x: float = -radius * 0.8 + (float(i) + 0.5) * radius * 1.6 / float(bars)
		var half: float = sqrt(maxf(radius * radius * 0.72 - x * x, 0.01))
		add_child(Look.box(Vector3(0.07, 0.06, half * 2.0), iron, Vector3(x, 0.035, 0)))
	# the pressure lamp on a stalk at the rim
	var lamp_at := Vector3(radius + 0.25, 0.0, 0.0)
	add_child(Look.box(Vector3(0.1, 0.5, 0.1), iron, lamp_at + Vector3(0, 0.25, 0)))
	add_child(DoomDecor.ns(Look.sphere(0.14, _lamp_mat, lamp_at + Vector3(0, 0.55, 0))))
	if lift:
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		_area.monitorable = false
		var acs := CollisionShape3D.new()
		var as_ := CylinderShape3D.new()
		as_.radius = radius - 0.05
		as_.height = 1.0
		acs.shape = as_
		acs.position = Vector3(0, 0.5, 0)
		_area.add_child(acs)
		add_child(_area)
	_hiss = DoomFx.hiss(radius, Color(1.0, 0.98, 0.95, 0.5) if lift else Color(1.0, 0.55, 0.4, 0.55))
	_hiss.position = Vector3(0, 0.05, 0)
	add_child(_hiss)
	var h: float = 6.0 if lift else plume
	_jet = DoomFx.jet(h, radius, Color(0.95, 0.93, 0.9, 0.55) if lift else Color(1.0, 0.5, 0.35, 0.5), 60 if lift else 50)
	_jet.position = Vector3(0, 0.1, 0)
	add_child(_jet)
	if not lift:
		# the scald column's hot core: bright embers riding the steam
		_jet2 = Fx.sparks({"amount": 30, "lifetime": 0.6, "explosiveness": 0.4, "shape": "sphere", "radius": radius * 0.5,
			"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(plume * 1.5, plume * 2.4), "gravity": Vector3(0, -4.0, 0),
			"color": Color(3.0, 0.9, 0.3), "size": Vector2(0.05, 0.4),
			"aabb": AABB(Vector3(-3, -1, -3), Vector3(6, plume + 6.0, 6))})
		_jet2.position = Vector3(0, 0.1, 0)
		add_child(_jet2)
	if not lift:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.3, 0.1)
		_light.light_energy = 0.4
		_light.omni_range = 4.5
		_light.position = Vector3(0, 0.6, 0)
		add_child(_light)
