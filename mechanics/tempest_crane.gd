class_name TempestCrane
extends RotatingPlatform
## Tempest Tower: the TOWER CRANE's slewing jib - the set piece. A long lattice jib on top of the
## crane mast, with its counter-jib and concrete counterweights, slews between two headings on the
## course clock: it rests at `a0` (over the roof you board it from) for `dwell` seconds, slews to
## `a1` (across the gap, over the spire tower) in `slew` seconds, rests there, and slews back. The
## walkway along the top of the jib is the platform you ride. `warn` seconds before each slew the
## jib's strobes flash and the slew horn sounds. Pure function of the clock (a RotatingPlatform with
## its own angle profile), so the bot can ask where the walkway will be.
## Positioned at the slewing ring's centre (the top of the hub); the jib points along local +X at
## angle 0 and the node itself is never turned (the headings carry the direction).

@export var a0_deg: float = 0.0
@export var a1_deg: float = 90.0
@export var dwell: float = 5.0
@export var slew: float = 7.0
@export var warn: float = 1.2
## Jib walkway: from `jib_from` to `jib_to` metres out, `jib_width` wide, `jib_thick` thick.
@export var jib_from: float = 1.6
@export var jib_to: float = 26.0
@export var jib_width: float = 1.6
@export var jib_thick: float = 0.5

var _strobe_mat: StandardMaterial3D
var _was_warn: bool = false
var _slew_loop: AudioStreamPlayer3D


func _ready() -> void:
	period = 2.0 * dwell + 2.0 * slew
	hub_radius = jib_from + 0.3
	hub_height = jib_thick
	style = "mover"
	var len: float = jib_to - jib_from
	arms = [{"pos": Vector3(jib_from + len * 0.5, 0, 0), "size": Vector3(len, jib_thick, jib_width)}]
	super._ready()
	_build()
	_slew_loop = WorldAudio.loop("tempest_crane_slew", self, -12.0, 40.0, 8.0, false)


## Seconds into the cycle (0 = the start of the rest at a0).
func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## True from the moment the jib settles at a1 until it is back at rest at a0 (it is on its way home).
func past_far_end(time: float) -> bool:
	return _s(time) >= dwell + slew


func angle_at(time: float) -> float:
	var s: float = _s(time)
	var a0: float = deg_to_rad(a0_deg)
	var a1: float = deg_to_rad(a1_deg)
	if s < dwell:
		return a0
	if s < dwell + slew:
		return lerpf(a0, a1, smoothstep(0.0, 1.0, (s - dwell) / slew))
	if s < 2.0 * dwell + slew:
		return a1
	return lerpf(a1, a0, smoothstep(0.0, 1.0, (s - 2.0 * dwell - slew) / slew))


## Which end the jib rests at (0 = a0, 1 = a1), or -1 while it slews.
func rest_end(time: float) -> int:
	var s: float = _s(time)
	if s < dwell:
		return 0
	if s < dwell + slew:
		return -1
	if s < 2.0 * dwell + slew:
		return 1
	return -1


## Seconds of rest left at the current end (0 while slewing).
func rest_left(time: float) -> float:
	var s: float = _s(time)
	if s < dwell:
		return dwell - s
	if s >= dwell + slew and s < 2.0 * dwell + slew:
		return 2.0 * dwell + slew - s
	return 0.0


## The jib rests at `end` for at least `window` more seconds.
func resting_for(time: float, end: int, window: float) -> bool:
	return rest_end(time) == end and rest_left(time) >= window


## World point of a spot on the walkway (`r` metres out, `side` across, on top) at `time`.
func walkway_point(time: float, r: float, side: float = 0.0) -> Vector3:
	return global_position + Basis(Vector3.UP, angle_at(time)) * Vector3(r, jib_thick * 0.5, side)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var left: float = rest_left(t)
	var slewing: bool = rest_end(t) < 0
	var warning: bool = not slewing and left < warn
	_strobe_mat.emission_energy_multiplier = (6.0 if fmod(t, 0.25) < 0.1 else 0.3) if warning else (2.5 if slewing else 0.6)
	if warning and not _was_warn:
		# SOUND: the slew horn (the tell, `warn` s before the jib moves)
		WorldAudio.at(self, "tempest_crane_horn", global_position + Vector3(0, 3.0, 0), 1.0, 80.0)
	_was_warn = warning
	if _slew_loop != null:
		WorldAudio.set_active(_slew_loop, slewing)


func _build() -> void:
	var yellow: StandardMaterial3D = Look.flat(Color(0.95, 0.72, 0.1), 0.5, 0.35)
	var dark: StandardMaterial3D = Look.flat(Color(0.16, 0.16, 0.17), 0.5, 0.7)
	var concrete: StandardMaterial3D = Look.flat(Color(0.55, 0.55, 0.53), 0.95)
	var cable: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.09), 0.4, 0.8)
	var top: float = jib_thick * 0.5
	var len: float = jib_to - jib_from
	# the jib's lattice: two lower chords either side of the walkway, a top chord above the middle,
	# and diagonals zig-zagging between them (decor only; the walkway is the only collision)
	var chord_y: float = -jib_thick * 0.5 - 0.1
	for sz: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(len, 0.16, 0.16), yellow, Vector3(jib_from + len * 0.5, chord_y, sz * (jib_width * 0.5 + 0.12))))
	var apex_y: float = -1.9
	add_child(Look.box(Vector3(len - 1.0, 0.16, 0.16), yellow, Vector3(jib_from + len * 0.5, apex_y, 0)))
	var bays: int = int(len / 1.6)
	for i: int in bays:
		var x0: float = jib_from + float(i) * len / float(bays)
		var x1: float = jib_from + float(i + 1) * len / float(bays)
		for sz: float in [-1.0, 1.0]:
			var a := Vector3(x0, chord_y, sz * (jib_width * 0.5 + 0.12))
			var b := Vector3(x1 if i % 2 == 0 else x0, apex_y, 0)
			add_child(TempestLoad._rod(a, b, 0.045, yellow))
			add_child(TempestLoad._rod(Vector3(x1, chord_y, sz * (jib_width * 0.5 + 0.12)), b, 0.045, yellow))
	# strobes along the walkway's edges (flash before each slew)
	_strobe_mat = Look.flat(Color(1.0, 0.35, 0.15), 0.3, 0.0, 0.6).duplicate() as StandardMaterial3D
	for i: int in 5:
		var x: float = jib_from + len * (0.15 + 0.2 * float(i))
		for sz: float in [-1.0, 1.0]:
			add_child(Look.sphere(0.09, _strobe_mat, Vector3(x, top - 0.02, sz * (jib_width * 0.5 + 0.12))))
	add_child(Look.sphere(0.22, _strobe_mat, Vector3(jib_to + 0.2, top + 0.4, 0)))
	# the trolley and hook block hanging near the tip
	add_child(Look.box(Vector3(1.2, 0.5, jib_width + 0.6), dark, Vector3(jib_to - 3.5, chord_y - 0.4, 0)))
	add_child(Look.cylinder(0.03, 8.0, cable, Vector3(jib_to - 3.5, chord_y - 4.6, 0), -1.0, 4))
	add_child(Look.box(Vector3(0.5, 0.8, 0.5), yellow, Vector3(jib_to - 3.5, chord_y - 9.0, 0)))
	# the counter-jib behind the ring: a short deck with the concrete counterweight blocks and the
	# hoist winch, the operator's cab under the ring, and the A-frame apex with its pendant cables
	add_child(Look.box(Vector3(10.0, 0.4, 2.2), dark, Vector3(-6.5, -0.2, 0)))
	for i: int in 4:
		add_child(Look.box(Vector3(1.0, 2.2, 2.4), concrete, Vector3(-10.4 + float(i) * 1.05, -1.4, 0)))
	add_child(Look.box(Vector3(1.6, 1.2, 1.6), yellow, Vector3(-4.0, 0.6, 0)))
	add_child(Look.box(Vector3(2.0, 2.2, 1.8), yellow, Vector3(0.6, -1.6, -2.2)))
	add_child(Look.box(Vector3(1.6, 1.0, 0.05), Look.flat(Color(0.35, 0.5, 0.65, 0.7), 0.1, 0.3), Vector3(0.6, -1.3, -3.12)))
	var apex := Vector3(0, 7.5, 0)
	for sz: float in [-1.0, 1.0]:
		add_child(TempestLoad._rod(Vector3(-1.2, 0, sz * 0.9), apex, 0.08, yellow))
		add_child(TempestLoad._rod(Vector3(1.2, 0, sz * 0.9), apex, 0.08, yellow))
	for sz: float in [-1.0, 1.0]:
		add_child(TempestLoad._rod(apex, Vector3(jib_to * 0.62, chord_y, sz * (jib_width * 0.5 + 0.12)), 0.035, cable))
	add_child(TempestLoad._rod(apex, Vector3(-11.0, -0.3, 0), 0.035, cable))
	add_child(Look.sphere(0.3, _strobe_mat, apex + Vector3(0, 0.3, 0)))
