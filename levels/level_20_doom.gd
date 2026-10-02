extends LevelBase
## 20. DOOM FORTRESS - inside a giant doomsday machine that is tearing itself apart. Fifteen stages
## (fourteen checkpoints), each chaining two or three demands back to back, from the furnace gate up
## through the gear halls, the press line, the crucible row and the alarm halls to the reactor chamber,
## where you climb round the melting core between its pulses to the off switch on top of it.
## Black iron and riveted steel, red alarm light, molten orange; sparks and steam everywhere.
## VERY HARD: precision on 1.0-1.4 m posts and beams at 85-94% of reach, hazards threaded on the move.
##
##  1 Furnace Gate       three pylon hops over the pour channel, a COLLAPSING CATWALK run, MANTLE
##                       the blast door
##  2 Steam Shaft        a LIFT VENT blasts you up the shaft; run the beam right behind the rolling
##                       wave of SCALD VENTS; a long hop to a post
##                       [shortcut: the boiler pipe - a max-height MANTLE and a hop to a 1 m pipe cap]
##  3 Gear Hall          BRANCH: board a colossal GEAR's rim, hop to the meshing gear, leap off its
##                       rim onto the posts | WALL RUN the gear housing, MANTLE the bearing block
##  4 Press Line         run the rail under two drop-forge PRESSES (crushers), MANTLE under a third
##                       press's cycle, a 94% leap to the ram beam, past two PISTON rams
##  5 Crucible Row       BRANCH: hop the rivet posts across three POUR lanes behind the rolling pours
##                       | MANTLE the gantry and BOOST into a leap over the lanes
##  6 Alarm Hall         the ALARM lockdown: a grate run, the unpowered posts, the second grate under
##                       its LASER fence, MANTLE the gallery
##                       [shortcut: the cable trays - two hops on 1 m brackets past the first grate]
##  7 Grinder Bridge     two GRINDERS (sweepers) across the bridge, a chain of COLLAPSING CATWALK plates
##  8 Smelter Leap       BRANCH: a CONVEYOR into a BOOST strip and a long leap onto the beam, its
##                       LASER, two posts | two posts to the service deck, its PRESS, the PORTAL
##  9 Flywheel           board a pallet on the giant FLYWHEEL, ride it up, leap onto the high beam,
##                       WALL RUN the housing
## 10 Vent Chimney       a LIFT VENT into a three-panel WALL RUN chimney, out over the top
## 11 Crane Pit          a spring plate (PAD), ride the crane pallet (MOVER) over the pit, the failing
##                       MAG-PLATES (blinks), a post        [shortcut: two rivet posts beside the
##                       crane, each hop at the very limit]
## 12 Coolant Pumps      the oncoming SCALD VENTS along the pipe, the pump lift (MOVER), a long hop
##                       [shortcut: the pump housing - two max-height MANTLES]
## 13 Reactor Floor      SET PIECE: into the reactor chamber, where the PULSE RINGS fire up the core;
##                       cross the floor tier behind a pulse, MANTLE onto the first tier
## 14 Reactor Spiral     round the core behind the climbing pulses, MANTLE onto the second tier, a
##                       LIFT VENT up to the third
## 15 Meltdown           COLLAPSING CATWALKS round the core, a LIFT VENT, two MANTLES onto the switch
##                       deck on top of the core - throw the OFF SWITCH (the finish)
##
## Doom mechanics (own scripts): DoomVent (lift and scald steam vents), DoomPour (crucible pours down a
## lane), DoomCatwalk (collapsing catwalk sections), DoomAlarm (klaxon lockdown cycles), DoomGear
## (rideable gears), DoomReactor (the core's pulse rings). Route variants for the bot: 0 = main line,
## 1 = every alternative branch, 2 = main line + every shortcut.

const ALARM := Color(1.0, 0.08, 0.04)
const MOLTEN := Color(1.0, 0.45, 0.08)
const HAZARD := Color(1.0, 0.62, 0.06)

## The molten pits far below (visual) - the kill floor is under them.
const PIT_Y: float = -36.0
## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: DoomDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Bursts that fire when the player arrives at a spot (portal exits): {"at", "p": [GPUParticles3D], "cool"}
var _arrivals: Array[Dictionary] = []
## Every walkable piece (world): {"stage": int, "aabb": AABB, "support": bool}
var _walk: Array[Dictionary] = []
var _stage: int = 1
## Timed machines with an extra warning lamp: {"kind", "node", "mats": [StandardMaterial3D], "cycle": int}
var _tells: Array[Dictionary] = []
var _reactor: DoomReactor
var _switch_lever: Node3D
## Where the reactor chamber stands (world), set by stage 12.
var _rc: Vector3 = Vector3.ZERO
## Stage 13's frame origin (the reactor stages share it).
var _rc_o: Vector3 = Vector3.ZERO


func _configure() -> void:
	theme_id = "doom"
	music_track = "doom"
	kill_y = PIT_Y - 12.0
	# 0 = main line, 1 = every alternative branch, 2 = main line taking every optional shortcut
	route_variants = 3


# ---- local-frame helpers --------------------------------------------------------------------

func _frame(origin: Vector3, yaw_deg: float) -> void:
	_o = origin
	_yaw = yaw_deg
	_b = Basis(Vector3.UP, deg_to_rad(yaw_deg))


func _w(l: Vector3) -> Vector3:
	return _o + _b * l


func _d(v: Vector3) -> Vector3:
	return _b * v


## A local size (x across, z along) turned into world axes (frames only turn in 90 degree steps).
func _sz(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0 else size


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## Records a walkable piece (world top centre, world size) for the overlap check and the supports.
func _reg(top: Vector3, size: Vector3, support: bool = true) -> void:
	_walk.append({"stage": _stage, "aabb": AABB(top - Vector3(size.x * 0.5, size.y, size.z * 0.5), size), "support": support})


## A deck plate / block (walkable) with its top at local `c`.
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, support: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	_reg(_w(c), _sz(Vector3(sx, thick, sz)), support)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A square rivet post (a small precision landing) on its own column.
func _post(c: Vector3, w: float = 1.2, style: String = "alt") -> Dictionary:
	return _blk(c, w, w, style, 0.6)


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	_reg(_w(top), _sz(size), false)
	return {"c": top, "hx": size.x * 0.5, "hz": size.z * 0.5}


## Takeoff spot on `a`: on the line toward `toward`, `inset` metres inside the edge.
func _edge(a: Dictionary, toward: Vector3, inset: float = 0.3) -> Vector3:
	var c: Vector3 = a["c"]
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	if a.has("r"):
		return c + d * (float(a["r"]) - inset)
	var tx: float = INF if absf(d.x) < 0.001 else (float(a["hx"]) - inset) / absf(d.x)
	var tz: float = INF if absf(d.z) < 0.001 else (float(a["hz"]) - inset) / absf(d.z)
	return c + d * minf(tx, tz)


## Route a jump from the edge of `a` to the middle of `b` (+ offset). speed > 0 marks a momentum jump.
func _hop(a: Dictionary, b: Dictionary, off: Vector3 = Vector3.ZERO, hold: bool = true, speed: float = 0.0) -> void:
	var to: Vector3 = (b["c"] as Vector3) + off
	r_jump(_w(_edge(a, to)), _w(to), hold)
	if speed > 0.0:
		route[route.size() - 1]["speed"] = speed


func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


func _kick(from: Vector3, to: Vector3) -> void:
	route.append({"kind": "kick", "from": _w(from), "to": _w(to)})


## Checkpoint deck facing the next stage's heading (_next_yaw), with its beacons and burst.
func _cp(c: Vector3, size: float = 5.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.2)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var fx: Array[GPUParticles3D] = DoomFx.cp_burst()
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6 if p != fx[2] else 0.05, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: doom_checkpoint - a stage banked (a heavy relay clunk and a hiss of steam)
			WorldAudio.at(self, "doom_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	# alarm beacons on the two back corners
	var h: float = size * 0.5 - 0.3
	for s: float in [-1.0, 1.0]:
		deco.beacon(_w(c + Vector3(s * h, 0, h)), 1.2 + 0.2 * s, s > 0.0)
	return d


## Fork signpost: a warning-lamp post at a corner of the fork and a floor strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	add_child(Look.box(Vector3(0.16, 2.4, 0.16), DoomDecor.iron(), _w(p + Vector3(0, 1.2, 0))))
	add_child(DoomDecor.ns(Look.box(Vector3(0.34, 0.5, 0.34), Look.flat(col, 0.3, 0.0, 3.5), _w(p + Vector3(0, 2.6, 0)))))
	kit.glow_strip(_w(p + Vector3(0, 0.03, -1.4)), _sz(Vector3(0.3, 0.05, 1.6)), col)


# ---- mechanic builders (local frame) ---------------------------------------------------------------

## A steam vent whose grate top is at local `c`, facing the frame's heading (+ extra yaw).
func _vent(c: Vector3, lift: bool, period: float, phase: float, radius: float = 1.2, launch: Vector3 = Vector3(0, 19, -2.0), yaw_extra: float = 0.0, solid: bool = true) -> DoomVent:
	var v := DoomVent.new()
	v.lift = lift
	v.radius = radius
	v.period = period
	v.phase = phase
	v.launch = launch
	v.solid = lift and solid
	v.position = _w(c)
	v.rotation.y = deg_to_rad(_yaw + yaw_extra)
	add_child(v)
	if lift and solid:
		_reg(_w(c), Vector3(radius * 2.0, 0.4, radius * 2.0))
	return v


## Phase for a vent that blasts `at` seconds into the cycle (t = 0 at course start).
static func _vent_phase(period: float, at: float) -> float:
	return fposmod(DoomVent.FIRE - at / period, 1.0)


## A pour lane: crucible head at local `head` (lane floor height), flowing toward local +X * dir.
func _pour(head: Vector3, dir: float, length: float, width: float, period: float, phase: float, speed: float = 9.0, pour: float = 1.2) -> DoomPour:
	var p := DoomPour.new()
	p.length = length
	p.width = width
	p.period = period
	p.phase = phase
	p.speed = speed
	p.pour = pour
	p.position = _w(head)
	p.rotation.y = deg_to_rad(_yaw + (0.0 if dir > 0.0 else 180.0))
	add_child(p)
	return p


## A drop-forge press over local floor point `c` with its warning lamps (lit ~1 s before the slam).
func _press(c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(c), size, lift, period, phase, _yaw)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.04, 0.02)
	mat.emission_enabled = true
	mat.emission = ALARM
	mat.emission_energy_multiplier = 0.3
	var h: float = lift + size.y + 1.5
	for sx: float in [-1.0, 1.0]:
		deco.lamp(_w(c + Vector3(sx * (size.x * 0.5 + 0.35), h + 0.25, 0)), mat)
	# the press's face: a hazard-striped die
	cr.add_child(DoomDecor.ns(Look.box(Vector3(size.x + 0.04, 0.16, size.z + 0.04), DoomDecor.hazard(0.6), Vector3(0, -size.y * 0.5 + 0.08, 0))))
	_tells.append({"kind": "press", "node": cr, "mats": [mat], "cycle": -999})
	return cr


## A piston ram (local `top` = its top when retracted) with a warning lamp on its housing.
func _ram(top: Vector3, size: Vector3, yaw_extra: float, stroke: float, period: float, phase: float, strength: float = 11.0) -> Piston:
	var p: Piston = kit.piston(_w(top), size, _yaw + yaw_extra, stroke, period, phase, strength)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.04, 0.02)
	mat.emission_enabled = true
	mat.emission = ALARM
	mat.emission_energy_multiplier = 0.3
	var back: Vector3 = Basis(Vector3.UP, deg_to_rad(_yaw + yaw_extra)) * Vector3(0, 0, size.z * 0.5 + stroke + 0.45)
	deco.lamp(_w(top) + back + Vector3(0, 0.75, 0), mat)
	_tells.append({"kind": "ram", "node": p, "mats": [mat], "cycle": -999})
	return p


## A laser fence across the route at local floor point `c` (`width` across), with a 1 s tell.
func _beam(c: Vector3, width: float, period: float, on: float, phase: float, height: float = 2.4) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.2), period, on, phase, _yaw)
	g.warn = 1.0
	return g


## A collapsing catwalk section with its top at local `c` (size x across, z along).
func _catwalk(c: Vector3, sx: float, sz: float, delay: float = 0.45, respawn: float = 2.2) -> DoomCatwalk:
	var cw := DoomCatwalk.new()
	cw.size = _sz(Vector3(sx, 0.3, sz))
	cw.delay = delay
	cw.respawn = respawn
	cw.position = _w(c) - Vector3(0, 0.15, 0)
	add_child(cw)
	_reg(_w(c), _sz(Vector3(sx, 0.3, sz)), false)
	return cw


# ---- bot helpers (all deterministic, from the course clock) ----------------------------------------

static func _press_ok(c: Crusher, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if c.gap_at(Game.course_time + s) < 2.0 or not c.is_clear_for(Game.course_time + s, 0.0):
			return false
		s += 0.04
	return true


static func _ram_clear(p: Piston, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


static func _dark(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


static func _blink_ok(bp: BlinkPlatform, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not bp.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = DoomDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12]
	var starts: Array[int] = []
	var origins: Array[Vector3] = []
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_stage = i + 1
		_next_yaw = yaws[i + 1]
		starts.append(route.size())
		origins.append(_o)
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	# the reactor chamber (13-15) is built round the core in stage 13's frame
	_rc_o = _o
	for k: int in 3:
		_stage = stages.size() + 1 + k
		_frame(_rc_o, 0.0)
		starts.append(route.size())
		origins.append(_o if k == 0 else _cp_world[_cp_world.size() - 1])
		[_stage_13, _stage_14, _stage_15][k].call()
	_surroundings()
	_doom_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


# ---- stage 1: Furnace Gate - pylon hops, the collapsing catwalk, mantle the blast door ---------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(12, 2, 12), "main", 0.0, _yaw)
	_reg(_w(Vector3.ZERO), Vector3(12, 2, 12))
	var start: Dictionary = _area(Vector3.ZERO, 6.0, 6.0)
	var p1: Dictionary = _post(Vector3(0, 0, -11.6), 1.4)
	var p2: Dictionary = _post(Vector3(0.6, 0.6, -17.4))
	var p3: Dictionary = _post(Vector3(0, 0.6, -23.2))
	for i: int in 4:
		_catwalk(Vector3(0, 0, -30.1 - 3.0 * float(i)), 1.4, 3.0)
	for sx: float in [-1.0, 1.0]:
		deco.girder(_w(Vector3(sx * 0.95, 9.0, -27.6)), _w(Vector3(sx * 0.95, 9.0, -41.4)), 0.4)
		for k: int in 5:
			deco.chain(_w(Vector3(sx * 0.95, 8.75, -28.6 - 3.0 * float(k))), 8.6)
	var door: Dictionary = _ledge(Vector3(0, 3.3, -43.9), Vector3(5.0, 8.0, 3.0))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -52.0))
	_hop(start, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, _area(Vector3(0, 0, -30.1), 0.7, 1.5))
	r_walk(_w(Vector3(0, 0, -39.4)))
	r_mantle(_w(Vector3(0, 0, -40.2)), _w(Vector3(0, 3.3, -43.7)))
	_hop(door, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the furnace gate: two great iron jambs and a lintel round the blast door, beacons on top
	for sx: float in [-1.0, 1.0]:
		deco.wall_slab(_w(Vector3(sx * 4.6, 2.0, -43.9)), Vector3(3.0, 16.0, 2.4), _yaw + 90.0)
		deco.beacon(_w(Vector3(sx * 4.6, 10.0, -43.9)), 1.3, sx > 0.0, 1.4)
	deco.wall_slab(_w(Vector3(0, 11.5, -43.9)), Vector3(12.0, 3.0, 2.4), _yaw)
	deco.hazard_band(_w(Vector3(0, 9.9, -42.6)), _sz(Vector3(6.2, 0.4, 0.1)), _yaw, 0.4)
	# the pour channel the pylons stand in, far below
	deco.channel(_w(Vector3(0, -8.0, -17.4)), 60.0, 6.0, _yaw + 90.0, 1.2)
	DoomFx.embers(self, _w(Vector3(0, -4.0, -17.4)), _sz(Vector3(10.0, 3.0, 4.0)), 50)
	# gears turning in the dark either side of the gate
	deco.gear(_w(Vector3(-16.0, 4.0, -30.0)), 9.0, 24, 1.6, 22.0, Vector3(0, 0, 90))
	deco.gear(_w(Vector3(17.0, -2.0, -22.0)), 7.0, 20, 1.4, -16.0, Vector3(0, 0, 90))
	deco.pump(_w(Vector3(-9.0, -14.0, -8.0)), 10.0, 0.8, 2.6)
	deco.pump(_w(Vector3(9.0, -14.0, -12.0)), 10.0, 0.8, 3.1)
	return cp["c"]


# ---- stage 2: Steam Shaft - a lift vent, the rolling scald-vent beam, a long hop to a post -----------

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var period: float = 4.4
	var t_lift: float = 1.0
	var v: DoomVent = _vent(Vector3(0, 0, -8.2), true, period, _vent_phase(period, t_lift), 1.2, Vector3(0, 19, -2.5))
	var l1: Dictionary = _blk(Vector3(0, 5.0, -12.4), 3.0, 4.0)
	_blk(Vector3(0, 5.0, -22.9), 1.2, 17.0, "alt", 0.6)
	var beam: Dictionary = _area(Vector3(0, 5.0, -22.9), 0.6, 8.5)
	# the scald vents fire in a wave down the beam just after the lift vent throws you up: land and
	# run straight down it behind the wave
	var zs: Array[float] = [-18.0, -22.5, -27.0]
	var svs: Array[DoomVent] = []
	for i: int in zs.size():
		var sv: DoomVent = _vent(Vector3(0, 5.0, zs[i]), false, period, _vent_phase(period, t_lift + 0.25 + 0.5 * float(i)), 0.6)
		sv.plume = 3.2
		svs.append(sv)
	var post: Dictionary = _post(Vector3(0, 5.6, -36.6))
	var cp: Dictionary = _cp(Vector3(0, 5.6, -44.4))
	# SHORTCUT: the boiler pipe - a max-height mantle beside the start, a 1 m pipe cap at the limit
	# of a jump, and you are up without waiting for the vent (but out of step with the scald wave)
	_ledge(Vector3(-3.6, 4.1, -2.0), Vector3(1.6, 10.0, 2.4), "accent")
	var cap: Dictionary = _blk(Vector3(-3.0, 4.7, -8.8), 1.0, 1.0, "accent", 0.5)
	deco.pipe(_w(Vector3(-3.0, 4.2, -8.8)), _w(Vector3(-3.0, -12.0, -8.8)), 0.4)
	if route_variant == 2:
		r_walk(_w(Vector3(-1.9, 0, -2.0)))
		r_mantle(_w(Vector3(-2.2, 0, -2.0)), _w(Vector3(-3.6, 4.1, -2.2)))
		r_walk(_w(Vector3(-3.6, 4.1, -1.0)))
		r_jump(_w(Vector3(-3.6, 4.1, -2.95)), _w(Vector3(-3.0, 4.7, -8.8)))
		r_jump(_w(Vector3(-3.0, 4.7, -9.1)), _w(Vector3(-0.6, 5.0, -11.6)))
		_wait(func() -> bool: return svs[0].clear_for(0.3, 2.7) and svs[1].clear_for(0.8, 3.2) and svs[2].clear_for(1.3, 3.7), _w(Vector3(-0.3, 5.0, -12.0)))
	else:
		_hop(cp0, {"c": Vector3(0, 0, -8.2), "r": 1.2})
		_kick(Vector3(0, 0, -8.2), Vector3(0, 5.0, -12.0))
	r_walk(_w(Vector3(0, 5.0, -30.8)))
	_hop(beam, post)
	_hop(post, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the shaft: boiler walls either side, pipes and steam everywhere
	for sx: float in [-1.0, 1.0]:
		deco.wall_slab(_w(Vector3(sx * 5.5, 4.0, -16.0)), Vector3(18.0, 20.0, 1.0), _yaw + 90.0)
		deco.pipe(_w(Vector3(sx * 4.6, -6.0, -9.0)), _w(Vector3(sx * 4.6, 14.0, -9.0)), 0.45)
		deco.pipe(_w(Vector3(sx * 4.4, 9.0, -7.0)), _w(Vector3(sx * 4.4, 9.0, -25.0)), 0.3)
		DoomFx.wisps(self, _w(Vector3(sx * 4.6, 9.0, -14.0)), 3.0, 10)
	deco.beacon(_w(Vector3(-1.2, 5.0, -10.7)), 1.1, true)
	DoomFx.falling_sparks(self, _w(Vector3(0, 14.0, -24.0)), _sz(Vector3(3.0, 1.0, 9.0)), 30)
	deco.channel(_w(Vector3(0, -9.0, -26.0)), 40.0, 5.0, _yaw, 1.0)
	deco.stack(_w(Vector3(12.0, -20.0, -30.0)), 34.0, 2.4)
	l1.clear()
	return cp["c"]


# ---- stage 3: Gear Hall (BRANCH) - ride the gears | wall run the housing and mantle -------------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var ga := DoomGear.new()
	ga.radius = 6.5
	ga.teeth = 18
	ga.period = 11.0
	ga.position = _w(Vector3(0, 0, -15.0))
	add_child(ga)
	_reg(_w(Vector3(0, 0, -15.0)), Vector3(16.2, 0.6, 16.2), false)
	var gb := DoomGear.new()
	gb.radius = 5.0
	gb.teeth = 14
	gb.period = -9.0
	gb.position = _w(Vector3(11.0, 1.2, -24.0))
	add_child(gb)
	_reg(_w(Vector3(11.0, 1.2, -24.0)), Vector3(13.2, 0.6, 13.2), false)
	var e1: Dictionary = _post(Vector3(6.0, 1.8, -30.0))
	var e2: Dictionary = _post(Vector3(6.0, 1.8, -36.2))
	var merge: Dictionary = _blk(Vector3(3.5, 1.8, -43.8), 8.0, 5.0)
	var cp: Dictionary = _cp(Vector3(2.0, 1.8, -54.0))
	# ALT: the gear housing wall (a wall run), the landing and the bearing block (a mantle)
	var q1: Dictionary = _post(Vector3(-7.0, 0, -5.4), 1.4)
	kit.wallrun(_w(Vector3(-10.0, 2.6, -17.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	deco.wall_slab(_w(Vector3(-10.9, 1.0, -17.5)), Vector3(17.0, 12.0, 1.2), _yaw + 90.0)
	var r1: Dictionary = _blk(Vector3(-3.0, 0.6, -29.0), 2.6, 4.0, "alt")
	var mb: Dictionary = _ledge(Vector3(-1.0, 3.9, -34.5), Vector3(3.0, 8.0, 3.0), "alt")
	_sign(Vector3(-2.25, 0, 0.8), ALARM)
	_sign(Vector3(2.25, 0, 0.8), MOLTEN)
	if route_variant == 1:
		r_walk(_w(Vector3(-1.9, 0, -1.9)))
		r_jump(_w(Vector3(-2.1, 0, -2.2)), _w(Vector3(-7.0, 0, -5.4)))
		r_wallrun(_w(Vector3(-7.0, 0, -5.9)), _w(Vector3(-9.3, 1.8, -11.0)), _w(Vector3(-9.3, 1.8, -21.0)), _w(r1["c"]))
		r_walk(_w(Vector3(-2.0, 0.6, -30.4)))
		r_mantle(_w(Vector3(-1.8, 0.6, -30.7)), _w(Vector3(-1.0, 3.9, -34.3)))
		_hop(mb, merge, Vector3(-2.5, 0, 1.0))
	else:
		# board gear A's rim where it passes nearest, ride it round to the mesh, hop across to gear B,
		# ride B round to its west side (moving forward) and leap off onto the first post
		r_walk(_w(Vector3(0, 0, -1.6)))
		r_jump(_w(Vector3(0, 0, -2.2)), _w(Vector3(0, 0.05, -8.5)))
		var rim_b: Array = []
		for k: int in 24:
			rim_b.append(gb.rim_local(TAU * float(k) / 24.0))
		route.append({"kind": "x_jump", "to_node": gb, "to_locals": rim_b, "reach": 3.0, "lead": 0.35})
		# leave from B's west side, where the rim runs straight at the first post
		var hw: Vector3 = gb.position
		var ex: Vector3 = _d(Vector3(-1, 0, 0))
		route.append({"kind": "h_jump", "to": _w(e1["c"]), "test": func() -> bool:
			var rel: Vector3 = player.global_position - hw
			rel = Vector3(rel.x, 0, rel.z).normalized()
			return absf(rad_to_deg(atan2(rel.cross(ex).y, rel.dot(ex)))) <= 8.0})
		_hop(e1, e2)
		_hop(e2, merge, Vector3(1.0, 0, 1.5))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the hall: an idler gear deep under the mesh, bearings, beacons, sparks off the teeth
	deco.gear(_w(Vector3(5.5, -6.0, -19.5)), 4.0, 14, 1.2, 6.0, Vector3.ZERO)
	DoomFx.spark_spray(self, _w(Vector3(5.6, 0.4, -19.6)), _d(Vector3(0.3, 0.5, -1)), 24)
	DoomFx.spark_spray(self, _w(Vector3(0, -0.8, -15.0)), Vector3(0, -1, 0), 14)
	deco.wall_slab(_w(Vector3(18.5, 4.0, -26.0)), Vector3(30.0, 22.0, 1.4), _yaw + 90.0)
	deco.gear(_w(Vector3(21.5, 9.0, -40.0)), 8.0, 22, 1.4, -20.0, Vector3(0, 0, 90))
	deco.beacon(_w(Vector3(7.1, 1.8, -45.9)), 1.0, true)
	deco.pump(_w(Vector3(-7.0, -16.0, -42.0)), 12.0, 0.9, 2.8)
	DoomFx.haze(self, _w(Vector3(3.0, -4.0, -25.0)), _sz(Vector3(18.0, 4.0, 20.0)), 30)
	q1.clear()
	return cp["c"]


# ---- stage 4: Press Line - the presses, a mantle under a press, the 92% leap, the rams ------------------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var rail: Dictionary = _blk(Vector3(0, 0, -16.8), 1.4, 18.4, "alt", 0.6)
	var period: float = 4.8
	var c1: Crusher = _press(Vector3(0, 0, -12.5), Vector3(2.4, 1.2, 2.2), 3.2, period, 0.0)
	var c2: Crusher = _press(Vector3(0, 0, -18.5), Vector3(2.4, 1.2, 2.2), 3.2, period, fposmod(-0.66 / period, 1.0))
	var ldg: Dictionary = _ledge(Vector3(0, 3.3, -29.3), Vector3(2.6, 8.0, 2.6))
	var c3: Crusher = _press(Vector3(0, 3.3, -29.3), Vector3(2.2, 1.0, 2.0), 3.0, period, 0.35)
	var rb: Dictionary = _blk(Vector3(0, 3.3, -40.5), 1.2, 9.0, "alt", 0.6)
	var p1: Piston = _ram(Vector3(2.0, 4.3, -38.8), Vector3(1.4, 1.0, 1.0), 90.0, 2.4, 5.2, 0.0)
	var p2: Piston = _ram(Vector3(-2.0, 4.3, -42.2), Vector3(1.4, 1.0, 1.0), -90.0, 2.4, 5.2, fposmod(-0.38 / 5.2, 1.0))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -52.0))
	_hop(cp0, rail, Vector3(0, 0, 8.2))
	_wait(func() -> bool: return _press_ok(c1, 0.1, 2.3) and _press_ok(c2, 0.75, 2.95), _w(Vector3(0, 0, -8.6)))
	r_walk(_w(Vector3(0, 0, -25.4)))
	_wait(func() -> bool: return _press_ok(c3, 0.0, 2.7), _w(Vector3(0, 0, -25.4)))
	r_mantle(_w(Vector3(0, 0, -25.7)), _w(Vector3(0, 3.3, -29.1)))
	_hop(ldg, rb, Vector3(0, 0, 3.5))
	_wait(func() -> bool: return _ram_clear(p1, 0.1, 2.05) and _ram_clear(p2, 0.45, 2.45), _w(Vector3(0, 3.3, -37.0)))
	r_walk(_w(Vector3(0, 3.3, -44.6)))
	_hop(rb, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the line: the forge hammers' gantry overhead, sparks off the dies, a molten channel below
	deco.truss(_w(Vector3(-3.6, 12.0, -6.0)), _w(Vector3(-3.6, 12.0, -46.0)), 2.0, 10)
	deco.wall_slab(_w(Vector3(-6.5, 2.0, -30.0)), Vector3(40.0, 18.0, 1.2), _yaw + 90.0)
	deco.channel(_w(Vector3(0, -8.0, -30.0)), 50.0, 5.0, _yaw, 1.4)
	DoomFx.embers(self, _w(Vector3(0, -4.0, -28.0)), _sz(Vector3(3.0, 3.0, 20.0)), 40)
	for z: float in [-12.5, -18.5, -29.3]:
		DoomFx.spark_spray(self, _w(Vector3(1.4, 0.3 if z > -25.0 else 3.6, z)), _d(Vector3(1, 0.4, 0)), 14)
	return cp["c"]


# ---- stage 5: Crucible Row (BRANCH) - posts across the pour lanes | mantle and boost over them ----------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var lanes: Array[DoomPour] = []
	var zs: Array[float] = [-7.9, -14.2, -20.5]
	var posts: Array[Dictionary] = []
	for i: int in 3:
		lanes.append(_pour(Vector3(-12.0, -0.6, zs[i]), 1.0, 24.0, 5.4, 6.0, fposmod(-0.75 * float(i) / 6.0, 1.0), 9.0, 1.2))
		posts.append(_post(Vector3(0, 0, zs[i])))
	var exit: Dictionary = _blk(Vector3(0, 0, -28.6), 6.0, 5.0)
	var cp: Dictionary = _cp(Vector3(0, 0, -38.0))
	# ALT: the gantry - mantle up beside the start, boost along it and leap the lanes
	var a1: Dictionary = _ledge(Vector3(4.6, 3.3, -0.6), Vector3(2.6, 8.0, 3.0), "alt")
	kit.boost(_w(Vector3(4.6, 3.3, -5.0)), Vector3(1.6, 0.4, 5.8), _yaw, 18.0)
	_reg(_w(Vector3(4.6, 3.3, -5.0)), _sz(Vector3(1.6, 0.4, 5.8)), false)
	var h: Dictionary = _blk(Vector3(4.6, 3.3, -19.6), 2.0, 2.4, "accent", 0.6, false)
	for hx: float in [3.9, 5.3]:
		deco.girder(_w(Vector3(hx, 14.0, -2.0)), _w(Vector3(hx, 14.0, -24.0)), 0.5)
		for hz: float in [-3.2, -7.4, -18.8, -20.4]:
			deco.chain(_w(Vector3(hx, 13.75, hz)), 10.6)
	_sign(Vector3(-2.25, 0, 0.8), MOLTEN)
	_sign(Vector3(2.25, 0, 0.8), ALARM)
	if route_variant == 1:
		r_walk(_w(Vector3(1.9, 0, -0.6)))
		r_mantle(_w(Vector3(2.2, 0, -0.6)), _w(Vector3(4.4, 3.3, -0.6)))
		r_walk(_w(Vector3(4.6, 3.3, -1.2)))
		r_jump(_w(Vector3(4.6, 3.3, -7.6)), _w(Vector3(4.6, 3.3, -19.4)))
		route[route.size() - 1]["speed"] = 18.0
		_hop(h, exit, Vector3(0, 0, 0.5))
	else:
		var xs: Array[float] = []
		for i: int in 3:
			xs.append(lanes[i].lane_x(_w(posts[i]["c"])))
		r_walk(_w(Vector3(0, 0, -1.7)))
		_wait(func() -> bool:
			for i: int in 3:
				if not lanes[i].clear_for(xs[i], 0.4 + 0.75 * float(i), 2.45 + 0.75 * float(i)):
					return false
			return true, _w(Vector3(0, 0, -1.7)))
		_hop(cp0, posts[0])
		_hop(posts[0], posts[1])
		_hop(posts[1], posts[2])
		_hop(posts[2], exit, Vector3(0, 0, 1.0))
	_hop(exit, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the row: crucible furnaces along the lanes' heads, a gantry crane overhead, stacks beyond
	deco.wall_slab(_w(Vector3(-15.5, 3.0, -14.2)), Vector3(22.0, 16.0, 2.0), _yaw + 90.0)
	deco.truss(_w(Vector3(-14.0, 14.0, -4.0)), _w(Vector3(14.0, 14.0, -4.0)), 1.6, 8)
	deco.truss(_w(Vector3(-14.0, 14.0, -24.0)), _w(Vector3(14.0, 14.0, -24.0)), 1.6, 8)
	deco.stack(_w(Vector3(-22.0, -10.0, -10.0)), 40.0, 2.0)
	deco.stack(_w(Vector3(-24.0, -10.0, -22.0)), 44.0, 2.4)
	deco.channel(_w(Vector3(15.6, -2.0, -14.2)), 24.0, 4.0, _yaw, 1.6)
	DoomFx.embers(self, _w(Vector3(0, 0.5, -14.2)), _sz(Vector3(12.0, 1.5, 9.0)), 60)
	a1.clear()
	h.clear()
	return cp["c"]


# ---- stage 6: Alarm Hall - the lockdown cycle: grate run, the dead posts, the second grate, mantle ------

func _stage_6() -> Vector3:
	var alarm := DoomAlarm.new()
	alarm.period = 6.0
	alarm.lock = 2.2
	alarm.warn = 1.2
	alarm.position = _w(Vector3(0, 2.0, -24.0))
	add_child(alarm)
	_blk(Vector3(0, 0, -8.5), 1.4, 12.0, "alt", 0.6)
	alarm.add_grate(_w(Vector3(0, 0, -8.5)), Vector2(1.4, 12.0), _yaw)
	var ga: Dictionary = _area(Vector3(0, 0, -8.5), 0.7, 6.0)
	var pp1: Dictionary = _post(Vector3(0, 0.6, -20.0))
	var pp2: Dictionary = _post(Vector3(0, 1.2, -25.9))
	var pp3: Dictionary = _post(Vector3(0, 0.6, -32.0))
	_blk(Vector3(0, 0, -42.0), 1.4, 10.0, "alt", 0.6)
	alarm.add_grate(_w(Vector3(0, 0, -42.0)), Vector2(1.4, 10.0), _yaw)
	_beam(Vector3(0, 0, -42.0), 2.6, alarm.period, alarm.lock / alarm.period, alarm.laser_phase(), 2.6)
	var gal: Dictionary = _ledge(Vector3(0, 3.3, -50.5), Vector3(4.0, 8.0, 3.0))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -59.1))
	# SHORTCUT: the cable trays along the hall - two 1 m tray brackets at the limit of a jump, never
	# powered, straight to the dead posts (no wait for the lockdown to lift)
	var t1: Dictionary = _post(Vector3(-2.6, 0.6, -7.8), 1.0, "accent")
	var t2: Dictionary = _post(Vector3(-2.6, 1.2, -13.9), 1.0, "accent")
	if route_variant == 2:
		r_walk(_w(Vector3(-0.4, 0, -0.6)))
		_hop(_area(Vector3.ZERO, 2.5, 2.5), t1)
		_hop(t1, t2)
		_hop(t2, pp1)
	else:
		r_walk(_w(Vector3(0, 0, -1.8)))
		_wait(func() -> bool: return alarm.safe_for(0.0, 3.3), _w(Vector3(0, 0, -1.8)))
		_hop(ga, pp1)
	_hop(pp1, pp2)
	_hop(pp2, pp3)
	_wait(func() -> bool: return alarm.safe_for(0.0, 3.4), _w(Vector3(0, 0.6, -32.0)))
	r_jump(_w(Vector3(0, 0.6, -32.3)), _w(Vector3(0, 0, -38.2)))
	r_walk(_w(Vector3(0, 0, -46.3)))
	r_mantle(_w(Vector3(0, 0, -46.7)), _w(Vector3(0, 3.3, -50.3)))
	_hop(gal, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the hall: walls lined with alarm beacons the klaxon spins up, cable trays, a control gallery
	for sx: float in [-1.0, 1.0]:
		deco.wall_slab(_w(Vector3(sx * 7.0, 3.0, -26.0)), Vector3(44.0, 18.0, 1.2), _yaw + 90.0)
		for i: int in 4:
			var z: float = -8.0 - 11.0 * float(i)
			var b := Node3D.new()
			b.position = _w(Vector3(sx * 5.9, 5.0 + float(i % 2), z))
			add_child(b)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.5, 0.05, 0.03)
			mat.emission_enabled = true
			mat.emission = ALARM
			mat.emission_energy_multiplier = 1.2
			b.add_child(Look.box(Vector3(0.5, 0.3, 0.5), DoomDecor.iron()))
			b.add_child(DoomDecor.ns(Look.sphere(0.28, mat, Vector3(0, 0.3, 0))))
			var spin := Node3D.new()
			spin.position = Vector3(0, 0.3, 0)
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 1.6
			cm.height = 7.0
			cm.radial_segments = 10
			cm.rings = 1
			cm.cap_top = false
			cm.cap_bottom = false
			for s2: float in [-1.0, 1.0]:
				var blade := Look.mesh_node(cm, DoomDecor.beam_material(ALARM, 0.14), Vector3(s2 * 3.5, 0, 0))
				blade.rotation.z = s2 * PI * 0.5
				DoomDecor.ns(blade)
				spin.add_child(blade)
			b.add_child(spin)
			var l: OmniLight3D = null
			if i % 2 == 0:
				l = OmniLight3D.new()
				l.light_color = Color(1.0, 0.1, 0.05)
				l.omni_range = 11.0
				l.position = Vector3(-sx * 0.8, 0.4, 0)
				b.add_child(l)
			alarm.add_beacon(spin, mat, l)
		deco.pipe(_w(Vector3(sx * 5.8, 9.0, -4.0)), _w(Vector3(sx * 5.8, 9.0, -48.0)), 0.35)
	deco.channel(_w(Vector3(0, -7.0, -26.0)), 46.0, 5.0, _yaw, 1.0)
	DoomFx.haze(self, _w(Vector3(0, 2.0, -26.0)), _sz(Vector3(5.0, 3.0, 20.0)), 20, Color(0.4, 0.08, 0.05, 0.18))
	return cp["c"]


# ---- stage 7: Grinder Bridge - two grinders across the bridge, the collapsing plates -------------------

func _stage_7() -> Vector3:
	var br: Dictionary = _blk(Vector3(0, 0, -14.4), 1.6, 14.0, "main", 0.6)
	var s1: Sweeper = kit.sweeper(_w(Vector3(2.8, 0, -11.6)), 4.0, 1, 3.2, 0.0)
	var s2: Sweeper = kit.sweeper(_w(Vector3(-2.8, 0, -20.0)), 4.0, 1, -3.4, 0.25)
	for hub: Vector3 in [Vector3(2.8, 0, -11.6), Vector3(-2.8, 0, -20.0)]:
		deco.column(_w(hub), PIT_Y, 0.8, true)
		DoomFx.spark_spray(self, _w(hub + Vector3(0, 0.5, 0)), Vector3.UP, 12)
	var c1: Dictionary = _area(Vector3(0, 0, -26.6), 0.7, 0.7)
	var c2: Dictionary = _area(Vector3(0, 0.6, -32.7), 0.7, 0.7)
	var c3: Dictionary = _area(Vector3(0, 0.6, -39.1), 0.7, 0.7)
	var c4: Dictionary = _area(Vector3(0, 0, -45.5), 0.7, 0.7)
	for c: Dictionary in [c1, c2, c3, c4]:
		_catwalk(c["c"], 1.4, 1.4, 0.5, 2.0)
		for sx: float in [-1.0, 1.0]:
			var cc: Vector3 = c["c"]
			deco.chain(_w(Vector3(cc.x + sx * 0.75, 10.15, cc.z)), 10.0 - cc.y)
	for sx2: float in [-1.0, 1.0]:
		deco.girder(_w(Vector3(sx2 * 0.75, 10.4, -24.0)), _w(Vector3(sx2 * 0.75, 10.4, -48.0)), 0.4)
	var cp: Dictionary = _cp(Vector3(0, 0, -53.9))
	_hop(_area(Vector3.ZERO, 2.5, 2.5), br, Vector3(0, 0, 6.8))
	route.append({"kind": "b_sweep", "to": _w(Vector3(0, 0, -15.6)), "sweeper": s1, "tol": 0.5})
	route.append({"kind": "b_sweep", "to": _w(Vector3(0, 0, -20.6)), "sweeper": s2})
	_hop(br, c1)
	_hop(c1, c2)
	_hop(c2, c3)
	_hop(c3, c4)
	_hop(c4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the bridge's grinding rollers' housings, a hall of gears, sparks raining
	for sx: float in [-1.0, 1.0]:
		deco.gear(_w(Vector3(sx * 12.0, -4.0, -30.0)), 10.0, 26, 1.8, 24.0 * sx, Vector3(0, 0, 90))
	deco.truss(_w(Vector3(-8.0, 12.0, -6.0)), _w(Vector3(-8.0, 12.0, -50.0)), 2.0, 12)
	DoomFx.falling_sparks(self, _w(Vector3(0, 12.0, -36.0)), _sz(Vector3(3.0, 1.0, 12.0)), 40)
	deco.channel(_w(Vector3(0, -9.0, -30.0)), 50.0, 6.0, _yaw, 1.2)
	return cp["c"]


# ---- stage 8: Smelter Leap (BRANCH) - conveyor, boost, the long leap, the beam's laser | the portal -----

func _stage_8() -> Vector3:
	kit.conveyor(_w(Vector3(0, 0, -6.5)), Vector3(2.0, 0.4, 8.0), _yaw + 180.0, 5.0)
	_reg(_w(Vector3(0, 0, -6.5)), _sz(Vector3(2.0, 0.4, 8.0)))
	kit.boost(_w(Vector3(0, 0, -13.5)), Vector3(2.0, 0.4, 6.0), _yaw, 20.0)
	_reg(_w(Vector3(0, 0, -13.5)), _sz(Vector3(2.0, 0.4, 6.0)))
	var bm: Dictionary = _blk(Vector3(0, 0, -34.85), 1.2, 12.0, "alt", 0.6)
	var las: LaserGate = _beam(Vector3(0, 0, -38.6), 2.4, 4.4, 0.3, 0.0, 2.4)
	var q1: Dictionary = _post(Vector3(0, 0.6, -46.0))
	var q2: Dictionary = _post(Vector3(0, 0.6, -52.0))
	var cp: Dictionary = _cp(Vector3(0, 0.6, -60.2))
	# ALT: two posts to the service deck, its press over the hatch, and the portal
	var r1: Dictionary = _post(Vector3(4.4, 0.6, -7.2))
	var r2: Dictionary = _post(Vector3(4.4, 1.2, -13.2))
	var dk: Dictionary = _blk(Vector3(4.4, 1.2, -19.5), 2.6, 3.6)
	var press: Crusher = _press(Vector3(4.4, 1.2, -19.2), Vector3(2.2, 1.0, 2.2), 3.2, 4.4, 0.0)
	var portal: WarpPortal = kit.portal(_w(Vector3(4.4, 1.2, -20.7)), _yaw, _w(Vector3(3.6, 0.6, -51.8)), _yaw, 6.0)
	var ed: Dictionary = _blk(Vector3(3.6, 0.6, -52.4), 2.4, 2.4, "accent")
	_arrival(Vector3(3.6, 0.6, -52.4))
	_sign(Vector3(-2.25, 0, 0.8), MOLTEN)
	_sign(Vector3(2.25, 0, 0.8), ALARM)
	if route_variant == 1:
		r_walk(_w(Vector3(1.8, 0, -1.6)))
		r_jump(_w(Vector3(2.0, 0, -2.2)), _w(r1["c"]))
		_hop(r1, r2)
		_wait(func() -> bool: return _press_ok(press, 0.5, 2.7), _w(r2["c"]))
		_hop(r2, dk, Vector3(0, 0, 1.0))
		r_portal(_w(Vector3(4.4, 1.2, -21.0)), portal.exit_point())
		_hop(ed, cp, Vector3(-1.5, 0, 1.5))
	else:
		r_walk(_w(Vector3(0, 0, -1.0)))
		r_jump(_w(Vector3(0, 0, -16.2)), _w(Vector3(0, 0, -30.4)))
		route[route.size() - 1]["speed"] = 20.0
		r_walk(_w(Vector3(0, 0, -36.6)))
		_wait(func() -> bool: return _dark(las, 0.0, 2.7), _w(Vector3(0, 0, -36.6)))
		_hop(bm, q1)
		_hop(q1, q2)
		_hop(q2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the smelter: a glowing furnace mouth beside the leap, the slag pit below it, chain hoists
	deco.wall_slab(_w(Vector3(-6.0, 2.0, -24.0)), Vector3(40.0, 16.0, 1.6), _yaw + 90.0)
	var mouth := Look.box(_sz(Vector3(0.4, 4.0, 8.0)), DoomDecor.molten(Vector2(0, -0.6), 2.0, 0.3, 0.8), _w(Vector3(-5.1, 2.0, -24.0)))
	add_child(DoomDecor.ns(mouth))
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.45, 0.15)
	fl.light_energy = 3.0
	fl.omni_range = 14.0
	fl.position = _w(Vector3(-3.5, 2.5, -24.0))
	add_child(fl)
	deco.channel(_w(Vector3(0, -6.0, -24.0)), 16.0, 8.0, _yaw + 90.0, 0.8)
	DoomFx.embers(self, _w(Vector3(0, -2.0, -24.0)), _sz(Vector3(4.0, 3.0, 7.0)), 60)
	for z: float in [-20.0, -28.0]:
		deco.chain(_w(Vector3(-2.0, 12.0, z)), 6.0)
	return cp["c"]


## A burst of sparks and steam where a portal lets you out (fired when you arrive).
func _arrival(at: Vector3) -> void:
	var fx: Array[GPUParticles3D] = DoomFx.cp_burst()
	for p: GPUParticles3D in fx:
		p.position = _w(at + Vector3(0, 0.6, 0))
		add_child(p)
	_arrivals.append({"at": _w(at), "p": fx, "cool": 0.0})


# ---- stage 9: Flywheel - ride a pallet up the flywheel, leap off at the top, wall run the housing -------

func _stage_9() -> Vector3:
	var bd: Dictionary = _blk(Vector3(0, 0, -8.8), 3.0, 2.4)
	var center := Vector3(0, 7.2, -12.0)
	var axis: Vector3 = _d(Vector3(0, 0, 1))
	var pallets: Array = []
	for k: int in 6:
		var pl: MovingPlatform = kit.orbiter(_w(center), 7.0, axis, Vector3(2.4, 0.4, 2.0), 14.0, float(k) / 6.0)
		pallets.append(pl)
		_pallet_dress(pl)
	deco.gear(_w(center + Vector3(0, 0, -1.6)), 6.0, 24, 1.0, 14.0, Vector3(90, 0, 0) + Vector3(0, _yaw, 0))
	_blk(Vector3(0, 13.6, -21.0), 1.2, 10.0, "alt", 0.6)
	var beam: Dictionary = _area(Vector3(0, 13.6, -21.0), 0.6, 5.0)
	kit.wallrun(_w(Vector3(-2.6, 15.6, -34.0)), Vector3(14.0, 6.5, 0.6), _yaw + 90.0)
	deco.wall_slab(_w(Vector3(-3.5, 14.0, -34.0)), Vector3(15.0, 12.0, 1.2), _yaw + 90.0)
	var cp: Dictionary = _cp(Vector3(3.0, 13.6, -47.5))
	_hop(_area(Vector3.ZERO, 2.5, 2.5), bd)
	r_walk(_w(Vector3(0, 0, -9.6)))
	var top_y: float = _w(center).y + 6.6
	var cw: Vector3 = _w(center)
	# step aboard as a pallet swings down past the deck (x_wait measures in 3D: the pallet passing
	# over the top of the wheel is right above the deck too)
	route.append({"kind": "x_wait", "nodes": pallets, "locals": [Vector3(0, 0.1, 0)], "point": _w(center + Vector3(-1.6, -6.8, 0)), "radius": 0.8, "lead": 0.5})
	route.append({"kind": "x_jump", "from": _w(Vector3(0, 0, -9.6)), "to_local": Vector3(0, 0.1, 0), "picked": true})
	route.append({"kind": "candy_ride", "stand": Vector3(0, 0.1, 0), "to": _w(Vector3(0, 13.6, -17.4)), "until": func() -> bool:
		var fb: Object = player.floor_body
		if fb == null or not is_instance_valid(fb) or not (fb is Node3D):
			return false
		var q: Vector3 = (fb as Node3D).global_position
		return q.y > top_y and Vector2(q.x - cw.x, q.z - cw.z).length() < 0.8})
	r_walk(_w(Vector3(0, 13.6, -25.3)))
	r_wallrun(_w(Vector3(0, 13.6, -25.7)), _w(Vector3(-2.0, 15.0, -30.0)), _w(Vector3(-2.0, 15.0, -38.5)), _w(cp["c"]))
	r_checkpoint()
	# the flywheel's axle runs back into a bearing block behind the wheel, sparks off the hub
	deco.pipe(_w(center + Vector3(0, 0, -1.4)), _w(center + Vector3(0, 0, -10.0)), 0.7)
	add_child(Look.box(_sz(Vector3(4.0, 6.0, 2.0)), DoomDecor.iron(), _w(center + Vector3(0, -1.0, -11.0))))
	deco.column(_w(center + Vector3(0, -4.0, -11.0)), PIT_Y, 1.6, true)
	DoomFx.spark_spray(self, _w(center + Vector3(0, 0, -2.2)), Vector3(0, -1, 0), 20)
	deco.pump(_w(Vector3(8.0, -8.0, -30.0)), 12.0, 1.0, 2.4)
	beam.clear()
	return cp["c"]


## A flywheel pallet: a steel tray with hazard edges and the hanger arms up to its pin.
func _pallet_dress(pl: MovingPlatform) -> void:
	var s: Vector3 = pl.size
	for sx: float in [-1.0, 1.0]:
		pl.add_child(DoomDecor.ns(Look.box(Vector3(0.08, 0.08, s.z), DoomDecor.hazard(0.5), Vector3(sx * (s.x * 0.5 - 0.04), s.y * 0.5 + 0.04, 0))))
	pl.add_child(Look.box(Vector3(0.3, 0.3, s.z * 0.6), DoomDecor.iron(), Vector3(0, -s.y * 0.5 - 0.15, 0)))


# ---- stage 10: Vent Chimney - a lift vent into a three-panel wall-run chimney, out over the top ---------

func _stage_10() -> Vector3:
	var f: Dictionary = _blk(Vector3(0, 0, -10.0), 4.0, 5.0)
	_vent(Vector3(0, 0, -10.6), true, 3.6, 0.0, 1.2, Vector3(0, 21, -2.5), 0.0, false)
	_blk(Vector3(0, 6.0, -15.2), 3.0, 3.0, "main", 1.2)
	_chimney_panel(2.3, 7.2, -19.5, -26.0)
	_chimney_panel(-2.3, 12.0, -24.5, -32.5)
	_chimney_panel(2.3, 15.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 17.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 17.9, -51.2))
	_hop(_area(Vector3.ZERO, 2.5, 2.5), f, Vector3(0, 0, 0.4))
	_kick(Vector3(0, 0, -10.6), Vector3(0, 6.0, -14.8))
	r_walk(_w(Vector3(0, 6.0, -13.9)))
	r_wallrun(_w(Vector3(0.5, 6.0, -15.85)), _w(Vector3(1.7, 7.4, -20.6)), _w(Vector3(1.7, 7.4, -23.5)), _w(Vector3(-1.7, 11.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 11.5, -27.4)), _w(Vector3(-1.7, 11.5, -30.4)), _w(Vector3(1.7, 14.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 14.5, -34.0)), _w(Vector3(1.7, 14.5, -35.4)), _w(Vector3(-0.75, 17.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the chimney: steam boiling up it, the boiler under the vent, gears behind the walls
	DoomFx.wisps(self, _w(Vector3(0, 8.0, -28.0)), 8.0, 30, 1.5)
	DoomFx.falling_sparks(self, _w(Vector3(0, 24.0, -30.0)), _sz(Vector3(2.0, 1.0, 8.0)), 24)
	deco.stack(_w(Vector3(-9.0, -10.0, -12.0)), 30.0, 1.8)
	deco.gear(_w(Vector3(9.0, 14.0, -30.0)), 6.0, 18, 1.0, 9.0, Vector3(0, 0, 90))
	f.clear()
	return cp["c"]


## A chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by a riveted wall.
func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	deco.wall_slab(_w(Vector3(x + signf(x) * 1.0, y - 4.0, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1) + 1.0, height + 8.0, 1.4), _yaw + 90.0)


# ---- stage 11: Crane Pit - the spring plate, the crane pallet over the pit, the failing mag-plates -------

func _stage_11() -> Vector3:
	var f: Dictionary = _blk(Vector3(0, 0, -7.9), 2.6, 2.6)
	var padp := Vector3(0, 0, -7.9)
	kit.pad(_w(padp), 20.0, 0.0, 0.0, 1.1)
	var h: Dictionary = _blk(Vector3(0, 5.0, -14.25), 2.4, 2.9)
	var cr: MovingPlatform = kit.mover(_w(Vector3(0, 5.0, -17.8)), _sz(Vector3(2.4, 0.4, 2.4)), [Vector3.ZERO, _d(Vector3(0, 0, -14.0))], 8.0, 0.0)
	_crane_dress(cr)
	var g: Dictionary = _blk(Vector3(0, 5.0, -35.4), 2.4, 2.4)
	var b1: BlinkPlatform = kit.blink(_w(Vector3(0, 5.0, -41.9)), Vector3(1.4, 0.4, 1.4), 4.0, 0.72, 0.0)
	var b2: BlinkPlatform = kit.blink(_w(Vector3(0, 5.6, -47.7)), Vector3(1.4, 0.4, 1.4), 4.0, 0.72, fposmod(-0.75 / 4.0, 1.0))
	b1.warn = 1.0
	b2.warn = 1.0
	_reg(_w(Vector3(0, 5.0, -41.9)), Vector3(1.4, 0.4, 1.4))
	_reg(_w(Vector3(0, 5.6, -47.7)), Vector3(1.4, 0.4, 1.4))
	var q: Dictionary = _post(Vector3(0, 5.6, -53.8))
	var cp: Dictionary = _cp(Vector3(0, 5.6, -61.6))
	# SHORTCUT: two rivet posts beside the crane's path - jumps at the very limit instead of the ride
	var sp1: Dictionary = _post(Vector3(2.2, 5.4, -21.1), 1.2, "accent")
	var sp2: Dictionary = _post(Vector3(2.2, 5.4, -27.9), 1.2, "accent")
	_hop(_area(Vector3.ZERO, 2.5, 2.5), f)
	r_walk(_w(padp + Vector3(0, 0, 0.9)))
	r_pad(_w(padp), _w(h["c"]))
	var near: Vector3 = cr.position
	var far: Vector3 = cr.position + _d(Vector3(0, 0, -14.0))
	if route_variant == 2:
		r_walk(_w(Vector3(0.8, 5.0, -14.4)))
		_hop(h, sp1)
		_hop(sp1, sp2)
		_hop(sp2, g, Vector3(1.0, 0, 0.9))
	else:
		r_walk(_w(Vector3(0, 5.0, -14.6)))
		r_wait(cr, near, 0.3)
		r_jump_onto(_w(Vector3(0, 5.0, -14.9)), cr, Vector3(0, 0.2, 0))
		r_jump_from_ride(cr, far, 0.4, _w(g["c"]))
	_wait(func() -> bool: return _blink_ok(b1, 0.4, 2.8) and _blink_ok(b2, 1.15, 3.55), _w(g["c"]))
	_hop(g, _area(Vector3(0, 5.0, -41.9), 0.7, 0.7))
	_hop(_area(Vector3(0, 5.0, -41.9), 0.7, 0.7), _area(Vector3(0, 5.6, -47.7), 0.7, 0.7))
	_hop(_area(Vector3(0, 5.6, -47.7), 0.7, 0.7), q)
	_hop(q, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the crane: its rails along the pit's sides, the trolley overhead, chains
	for sx: float in [-1.0, 1.0]:
		deco.girder(_w(Vector3(sx * 2.2, 11.0, -12.0)), _w(Vector3(sx * 2.2, 11.0, -38.0)), 0.7)
	deco.truss(_w(Vector3(-6.0, 15.0, -16.0)), _w(Vector3(6.0, 15.0, -16.0)), 1.4, 6)
	deco.truss(_w(Vector3(-6.0, 15.0, -34.0)), _w(Vector3(6.0, 15.0, -34.0)), 1.4, 6)
	deco.channel(_w(Vector3(0, -6.0, -26.0)), 30.0, 10.0, _yaw + 90.0, 0.6)
	DoomFx.embers(self, _w(Vector3(0, -2.0, -26.0)), _sz(Vector3(6.0, 3.0, 12.0)), 60)
	deco.stack(_w(Vector3(12.0, -14.0, -48.0)), 40.0, 2.6)
	return cp["c"]


## The crane pallet: hazard edges, and four cables up to a trolley that rides along the overhead rails.
func _crane_dress(cr: MovingPlatform) -> void:
	var s: Vector3 = cr.size
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var cable := Look.cylinder(0.035, 6.0, DoomDecor.iron(), Vector3(sx * (s.x * 0.5 - 0.15), 3.0 + s.y * 0.5, sz * (s.z * 0.5 - 0.15)), -1.0, 4)
			cr.add_child(cable)
	cr.add_child(Look.box(Vector3(s.x + 0.6, 0.5, 1.0), DoomDecor.steel(), Vector3(0, 6.1, 0)))
	cr.add_child(DoomDecor.ns(Look.box(Vector3(s.x + 0.04, 0.1, s.z + 0.04), DoomDecor.hazard(0.5), Vector3(0, s.y * 0.5 - 0.02, 0))))


# ---- stage 12: Coolant Pumps - the oncoming scald vents, the pump lift, a long hop -----------------------

func _stage_12() -> Vector3:
	var beam: Dictionary = _blk(Vector3(0, 0, -16.4), 1.2, 18.0, "alt", 0.6)
	var period: float = 3.6
	var vz: Array[float] = [-12.0, -16.5, -21.0]
	var vents: Array[DoomVent] = []
	for i: int in 3:
		# the near vent fires first: a wave of scalding steam running down the pipe ahead of you
		vents.append(_vent(Vector3(0, 0, vz[i]), false, period, _vent_phase(period, 1.0 + 0.5 * float(i)), 0.6))
	var lift: MovingPlatform = kit.mover(_w(Vector3(0, 0, -28.2)), _sz(Vector3(2.4, 0.4, 2.4)), [Vector3.ZERO, Vector3(0, 8.0, 0)], 7.0, 0.0)
	_lift_dress(lift, 8.0)
	var t: Dictionary = _blk(Vector3(0, 8.0, -33.4), 3.0, 3.0)
	var p1: Dictionary = _post(Vector3(0, 8.6, -40.2))
	var cp: Dictionary = _cp(Vector3(0, 8.6, -47.8))
	_hop(_area(Vector3.ZERO, 2.5, 2.5), beam, Vector3(0, 0, 8.2))
	_wait(func() -> bool: return vents[0].clear_for(0.15, 2.25) and vents[1].clear_for(0.65, 2.75) and vents[2].clear_for(1.15, 3.3), _w(Vector3(0, 0, -8.2)))
	# SHORTCUT: the pump housing - two 1.2 m pillars beside the lift, each a max-height mantle
	_ledge(Vector3(2.6, 4.1, -27.0), Vector3(1.2, 10.0, 1.2), "accent")
	var k2: Dictionary = _ledge(Vector3(2.6, 8.2, -29.4), Vector3(1.2, 10.0, 1.2), "accent")
	var bottom: Vector3 = lift.position
	var topp: Vector3 = lift.position + Vector3(0, 8.0, 0)
	if route_variant == 2:
		r_walk(_w(Vector3(0.3, 0, -24.9)))
		r_mantle(_w(Vector3(0.45, 0, -25.2)), _w(Vector3(2.6, 4.1, -27.0)))
		r_walk(_w(Vector3(2.6, 4.1, -27.25)))
		r_mantle(_w(Vector3(2.6, 4.1, -27.45)), _w(Vector3(2.6, 8.2, -29.4)))
		_hop(k2, t)
	else:
		r_walk(_w(Vector3(0, 0, -25.0)))
		r_wait(lift, bottom, 0.25)
		r_jump_onto(_w(Vector3(0, 0, -25.1)), lift, Vector3(0, 0.2, 0))
		r_jump_from_ride(lift, topp, 0.3, _w(t["c"]))
	_hop(t, p1)
	_hop(p1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the pump room: coolant pipes along the beam, pump housings, steam
	for sx: float in [-1.0, 1.0]:
		deco.pipe(_w(Vector3(sx * 1.4, -0.6, -6.0)), _w(Vector3(sx * 1.4, -0.6, -26.0)), 0.35)
		deco.pump(_w(Vector3(sx * 5.0, -12.0, -16.0)), 12.0, 1.1, 2.0 + sx * 0.3)
		DoomFx.wisps(self, _w(Vector3(sx * 1.4, -0.2, -16.0)), 2.5, 10, 0.6)
	deco.wall_slab(_w(Vector3(0, 2.0, -36.6)), Vector3(10.0, 8.0, 1.0), _yaw)
	return cp["c"]


## The pump lift's guide rails and its piston rod (`rise` = travel).
func _lift_dress(lift: MovingPlatform, rise: float) -> void:
	var s: Vector3 = lift.size
	var base: Vector3 = lift.position
	for sx: float in [-1.0, 1.0]:
		var rail := Look.box(Vector3(0.25, rise + 3.0, 0.25), DoomDecor.steel(), base + _d(Vector3(sx * (s.x * 0.5 + 0.25), 0, 0)) + Vector3(0, (rise + 3.0) * 0.5 - 1.0, 0))
		add_child(rail)
	add_child(Look.cylinder(0.4, 12.0, DoomDecor.steel(), base + Vector3(0, -6.2, 0), -1.0, 12))
	lift.add_child(DoomDecor.ns(Look.box(Vector3(s.x + 0.04, 0.1, s.z + 0.04), DoomDecor.hazard(0.5), Vector3(0, s.y * 0.5 - 0.02, 0))))


# ---- the reactor chamber (stages 13-15) ------------------------------------------------------------------
# Everything is placed round the core by angle (degrees, 0 = toward the chamber door, increasing round
# toward local +X), radius from the core's axis and height above the chamber's floor tier.

const RC_LOCAL := Vector3(0, 0, -20.0)
const TIER_H: float = 3.3


func _pol(phi_deg: float, r: float, h: float) -> Vector3:
	var a: float = deg_to_rad(phi_deg)
	return RC_LOCAL + Vector3(sin(a) * r, h, cos(a) * r)


## The tangent heading (frame yaw, degrees) of travel round the core in the direction of increasing angle.
static func _tan_yaw(phi_deg: float) -> float:
	return phi_deg + 90.0


func _reactor_build() -> void:
	_reactor = DoomReactor.new()
	_reactor.core_radius = 2.6
	_reactor.reach = 8.0
	_reactor.height = 17.5
	_reactor.tiers = PackedFloat32Array([0.0, TIER_H, TIER_H * 2.0, TIER_H * 3.0, TIER_H * 4.0, TIER_H * 5.0])
	_reactor.period = 7.0
	_reactor.step = 1.0
	_reactor.fire = 0.5
	_reactor.charge = 1.2
	_reactor.position = _w(RC_LOCAL)
	add_child(_reactor)
	_rc = _w(RC_LOCAL)
	# the chamber: a ring of riveted wall panels at r 15 (open at the door), gantry rings and pipes
	var segs: int = 28
	for i: int in segs:
		var phi: float = 360.0 * (float(i) + 0.5) / float(segs)
		if phi < 14.0 or phi > 346.0:
			continue
		var c: Vector3 = _pol(phi, 15.6, 8.0)
		deco.wall_slab(_w(c), Vector3(TAU * 15.6 / float(segs) + 0.1, 46.0, 1.2), _yaw + phi + 90.0, i % 3 == 0)
	for k: int in 4:
		var h: float = -4.0 + 9.0 * float(k)
		for i2: int in 16:
			var p0: float = 360.0 * float(i2) / 16.0
			var p1: float = 360.0 * float(i2 + 1) / 16.0
			if p0 < 20.0 or p1 > 340.0:
				continue
			deco.pipe(_w(_pol(p0, 14.6, h)), _w(_pol(p1, 14.6, h)), 0.35)
	# coolant pipes feeding the core from the walls, bent and broken, venting steam
	for i3: int in 6:
		var phi2: float = 30.0 + 60.0 * float(i3)
		var h2: float = TIER_H * (0.5 + float(i3 % 3) * 1.6) + 1.4
		deco.pipe(_w(_pol(phi2, 14.6, h2 + 2.0)), _w(_pol(phi2, 9.6, h2 + 2.0)), 0.5, DoomDecor.rust())
		DoomFx.wisps(self, _w(_pol(phi2, 9.4, h2 + 2.0)), 2.5, 10, 0.4)
	deco.channel(_w(RC_LOCAL + Vector3(0, -10.0, 0)), 34.0, 34.0, _yaw, 0.6)
	DoomFx.falling_sparks(self, _w(RC_LOCAL + Vector3(0, 28.0, 0)), Vector3(10.0, 1.0, 10.0), 50)
	DoomFx.haze(self, _w(RC_LOCAL + Vector3(0, -2.0, 0)), Vector3(14.0, 4.0, 14.0), 26, Color(0.45, 0.14, 0.06, 0.2))
	for i4: int in 6:
		var phi3: float = 30.0 + 60.0 * float(i4)
		deco.beacon(_w(_pol(phi3, 14.4, 2.0 + 5.0 * float(i4 % 3))), 0.9 + 0.1 * float(i4), i4 % 2 == 0, 1.4)


## A balcony on the safe ring (beyond the pulses' reach) with a hazard edge on its inner side.
func _balcony(phi: float, r: float, h: float, size: float = 3.0) -> Dictionary:
	var d: Dictionary = _blk(_pol(phi, r, h), size, size, "main", 0.8, false)
	deco.girder(_w(_pol(phi, r, h - 0.6)), _w(_pol(phi, 15.0, h - 0.6)), 0.6)
	return d


## A post inside the danger ring, hung on a strut from the chamber wall.
func _rpost(phi: float, r: float, h: float, w: float = 1.2) -> Dictionary:
	var d: Dictionary = _blk(_pol(phi, r, h), w, w, "alt", 0.6, false)
	deco.girder(_w(_pol(phi, r + 0.4, h - 0.9)), _w(_pol(phi, 15.0, h - 2.6)), 0.4)
	return d


## A checkpoint on the safe ring facing round the core (increasing angle).
func _rcp(phi: float, r: float, h: float, face_deg: float) -> Dictionary:
	_next_yaw = face_deg
	var d: Dictionary = _cp(_pol(phi, r, h))
	deco.girder(_w(_pol(phi, r, h - 1.0)), _w(_pol(phi, 15.0, h - 1.0)), 0.8)
	return d


# ---- stage 13: Reactor Floor - behind a pulse across the floor tier, mantle onto the first tier ----------

func _stage_13() -> Vector3:
	_reactor_build()
	var b0: Dictionary = _balcony(0.0, 11.0, 0.0)
	var d1: Dictionary = _rpost(40.0, 6.6, 0.0)
	var d2: Dictionary = _rpost(92.0, 6.6, 0.6)
	var m1: Dictionary = _ledge(_pol(136.0, 6.6, TIER_H), Vector3(2.6, 8.0, 2.6))
	var cp: Dictionary = _rcp(160.0, 12.4, TIER_H, 160.0 - 90.0)
	_hop(_area(Vector3.ZERO, 2.5, 2.5), b0)
	r_walk(_w(_pol(0.0, 10.6, 0.0)))
	_wait(func() -> bool: return _reactor.zone_clear(0, 0.0, 4.1) and _reactor.zone_clear(1, 1.8, 5.3), _w(_pol(0.0, 10.6, 0.0)))
	_hop(b0, d1)
	_hop(d1, d2)
	r_mantle(_w(_edge(d2, m1["c"])), _w(_pol(136.0, 6.6, TIER_H)))
	_hop(m1, cp)
	r_checkpoint()
	return cp["c"]


# ---- stage 14: Reactor Spiral - posts round the core behind a pulse, mantle, a lift vent up a tier ------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(_pol(160.0, 12.4, TIER_H), 2.5, 2.5)
	var d3: Dictionary = _rpost(190.0, 6.6, TIER_H + 0.6)
	var d4: Dictionary = _rpost(248.0, 6.6, TIER_H)
	var m2: Dictionary = _ledge(_pol(288.0, 6.6, TIER_H * 2.0), Vector3(2.6, 8.0, 2.6))
	var b2: Dictionary = _balcony(312.0, 10.6, TIER_H * 2.0)
	var vphi: float = 342.0
	var cphi: float = 6.0
	_aimed_vent(vphi, 10.4, TIER_H * 2.0, _pol(cphi, 11.2, TIER_H * 3.0), 3.2)
	var cp: Dictionary = _rcp(cphi, 11.2, TIER_H * 3.0, cphi - 90.0)
	_wait(func() -> bool: return _reactor.zone_clear(1, 0.0, 4.3) and _reactor.zone_clear(2, 2.0, 5.3), _w(_pol(160.0, 11.6, TIER_H)))
	_hop(cp0, d3)
	_hop(d3, d4)
	r_mantle(_w(_edge(d4, m2["c"])), _w(_pol(288.0, 6.6, TIER_H * 2.0)))
	_hop(m2, b2)
	r_jump(_w(_edge(b2, _pol(vphi, 10.4, TIER_H * 2.0))), _w(_pol(vphi, 10.4, TIER_H * 2.0)))
	route.append({"kind": "kick", "from": _w(_pol(vphi, 10.4, TIER_H * 2.0)), "to": _w(cp["c"])})
	r_checkpoint()
	return cp["c"]


## A lift vent on the safe ring whose push points at `target` (local).
func _aimed_vent(phi: float, r: float, h: float, target: Vector3, period: float) -> DoomVent:
	var at: Vector3 = _pol(phi, r, h)
	var v: DoomVent = _vent(at, true, period, 0.0, 1.2, Vector3(0, 19, -3.0))
	var d: Vector3 = target - at
	v.rotation.y = deg_to_rad(_yaw) + atan2(-d.x, -d.z)
	deco.girder(_w(_pol(phi, r, h - 1.8)), _w(_pol(phi, 15.0, h - 1.8)), 0.6)
	return v


# ---- stage 15: Meltdown - collapsing catwalks round the core, the lift vent, mantle onto the switch deck --

func _stage_15() -> void:
	var h3: float = TIER_H * 3.0
	var cp0: Dictionary = _area(_pol(6.0, 11.2, h3), 2.5, 2.5)
	var cws: Array[Dictionary] = []
	for phi: float in [44.0, 102.0, 162.0]:
		cws.append(_area(_pol(phi, 6.6, h3), 0.7, 0.7))
		_catwalk(_pol(phi, 6.6, h3), 1.4, 1.4, 0.5, 2.0)
		deco.girder(_w(_pol(phi, 7.0, h3 - 0.9)), _w(_pol(phi, 15.0, h3 - 2.6)), 0.4)
	var vphi: float = 186.0
	var b4phi: float = 210.0
	_aimed_vent(vphi, 10.4, h3, _pol(b4phi, 10.6, h3 + TIER_H), 3.0)
	var b4: Dictionary = _balcony(b4phi, 10.6, h3 + TIER_H)
	var d5: Dictionary = _rpost(236.0, 6.6, h3 + TIER_H + 0.6)
	var m5: Dictionary = _ledge(_pol(270.0, 6.4, TIER_H * 5.0), Vector3(2.6, 8.0, 2.6))
	# the switch deck on top of the core, and the off switch
	var deck_top: Vector3 = RC_LOCAL + Vector3(0, TIER_H * 6.0, 0)
	kit.ledge(_w(deck_top), Vector3(9.0, 2.0, 9.0), _yaw, "main")
	_reg(_w(deck_top), Vector3(9.0, 2.0, 9.0), false)
	kit.finish(_w(deck_top + Vector3(1.8, 0, 0)), _yaw - 90.0)
	_finish_pos = _w(deck_top + Vector3(1.8, 0, 0))
	_switch_build(_w(deck_top + Vector3(3.4, 0, 0)))
	_wait(func() -> bool: return _reactor.zone_clear(3, 0.0, 4.3), _w(_pol(6.0, 10.6, h3)))
	_hop(cp0, cws[0])
	_hop(cws[0], cws[1])
	_hop(cws[1], cws[2])
	r_jump(_w(_edge(cws[2], _pol(vphi, 10.4, h3))), _w(_pol(vphi, 10.4, h3)))
	route.append({"kind": "kick", "from": _w(_pol(vphi, 10.4, h3)), "to": _w(b4["c"])})
	_wait(func() -> bool: return _reactor.zone_clear(4, 0.0, 3.1) and _reactor.zone_clear(5, 1.0, 4.4), _w(b4["c"]))
	_hop(b4, d5)
	r_mantle(_w(_edge(d5, m5["c"])), _w(_pol(270.0, 6.4, TIER_H * 5.0)))
	var inner: Vector3 = _pol(270.0, 5.4, TIER_H * 5.0)
	r_mantle(_w(inner), _w(deck_top + Vector3(-3.2, 0, 0)))
	r_walk(_finish_pos)


## The off switch: a massive lever on a pedestal beside the finish, thrown when the level is won.
func _switch_build(at: Vector3) -> void:
	var base := Node3D.new()
	base.position = at
	add_child(base)
	base.add_child(Look.box(Vector3(1.2, 1.4, 1.6), DoomDecor.iron(), Vector3(0, 0.7, 0)))
	base.add_child(DoomDecor.ns(Look.box(Vector3(1.24, 0.3, 1.64), DoomDecor.hazard(0.8), Vector3(0, 1.2, 0))))
	_switch_lever = Node3D.new()
	_switch_lever.position = Vector3(0, 1.4, 0)
	_switch_lever.rotation.z = 0.7
	base.add_child(_switch_lever)
	_switch_lever.add_child(Look.cylinder(0.08, 1.8, DoomDecor.steel(), Vector3(0, 0.9, 0), -1.0, 8))
	_switch_lever.add_child(DoomDecor.ns(Look.sphere(0.22, DoomDecor.alarm(4.0), Vector3(0, 1.85, 0))))
	deco.beacon(at + Vector3(0, 1.4, 0.9), 0.6, true, 1.2)


## The off switch thrown: the lever slams over, the core cools, the alarms die and the chamber fills
## with cooling sparks.
func _finish_sequence() -> void:
	if _switch_lever != null:
		var tw: Tween = create_tween()
		tw.tween_property(_switch_lever, "rotation:z", -0.7, 0.25).set_trans(Tween.TRANS_BACK)
	if _reactor != null:
		_reactor.shut_down()
	var fx: Array[GPUParticles3D] = DoomFx.shutdown_burst(3.0)
	for p: GPUParticles3D in fx:
		p.position = _rc + Vector3(0, TIER_H * 6.0 + 1.0, 0)
		add_child(p)
		p.restart()
		p.emitting = true
	# SOUND: doom_finish - the off switch thrown: a huge relay clunk, the machine spinning down
	WorldAudio.at(self, "doom_finish", _finish_pos, 1.0, 120.0)
	await get_tree().create_timer(0.9).timeout


# ---- environment ----------------------------------------------------------------------------------

func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_sun = n as DirectionalLight3D
			else:
				_fill = n as DirectionalLight3D
	_env.background_mode = Environment.BG_SKY
	_env.sky = DoomSky.make(Vector3(0.35, 0.22, -1.0))
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.36, 0.3)
	_env.ambient_light_energy = 0.55
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.15
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.2, 0.07, 0.05)
	_env.fog_density = 0.0055
	_env.fog_aerial_perspective = 0.3
	_env.fog_sky_affect = 0.25
	_env.fog_sun_scatter = 0.0
	_env.fog_height = PIT_Y + 18.0
	_env.fog_height_density = 0.04
	_env.glow_enabled = true
	_env.glow_intensity = 0.75
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.15
	_env.adjustment_contrast = 1.12
	# no daylight in here: a dull red key from the forges below and a cold steel fill from above
	_sun.light_color = Color(1.0, 0.5, 0.32)
	_sun.light_energy = 0.75
	_sun.rotation_degrees = Vector3(-38, 200, 0)
	_sun.shadow_blur = 1.5
	_fill.light_color = Color(0.55, 0.6, 0.75)
	_fill.light_energy = 0.3
	_fill.rotation_degrees = Vector3(-60, 30, 0)


## Swap every walkable surface to the riveted deck-plate shader (same colours).
func _doom_materials() -> void:
	var plate: Shader = preload("res://visual/doom_plate.gdshader")
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = plate
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


## Columns and girders holding every walkable piece up out of the pits, the pits themselves, the far
## machinery and the ambient air along the route.
func _surroundings() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for wk: Dictionary in _walk:
		var ab: AABB = wk["aabb"]
		lo = lo.min(ab.position)
		hi = hi.max(ab.end)
		if not bool(wk["support"]):
			continue
		var top: Vector3 = ab.get_center() + Vector3(0, ab.size.y * 0.5, 0)
		var base: float = ab.position.y
		var w: float = clampf(minf(ab.size.x, ab.size.z) * 0.45, 0.35, 1.4)
		if ab.size.x >= 4.0 and ab.size.z >= 4.0:
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var corner := Vector3(top.x + sx * (ab.size.x * 0.5 - 0.6), base, top.z + sz * (ab.size.z * 0.5 - 0.6))
					deco.column(corner, PIT_Y, 0.6, false)
		elif maxf(ab.size.x, ab.size.z) >= 7.0:
			var along_x: bool = ab.size.x > ab.size.z
			var n: int = int(maxf(ab.size.x, ab.size.z) / 7.0) + 1
			for i: int in n:
				var k: float = -0.5 + (float(i) + 0.5) / float(n)
				var off: Vector3 = Vector3(k * ab.size.x, 0, 0) if along_x else Vector3(0, 0, k * ab.size.z)
				deco.column(Vector3(top.x, base, top.z) + off, PIT_Y, w * 0.6, false)
		else:
			deco.column(Vector3(top.x, base, top.z), PIT_Y, w, true)
	var mid: Vector3 = (lo + hi) * 0.5
	var span: Vector3 = hi - lo
	# the molten pits: one huge glowing floor far below, and its rising embers and smoke
	var pit := Look.box(Vector3(span.x + 400.0, 0.5, span.z + 400.0), DoomDecor.molten(Vector2(0.4, 0.2), 1.2, 0.55, 0.08), Vector3(mid.x, PIT_Y, mid.z))
	pit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pit)
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 10.0, 6.0, absf(here.z - prev.z) * 0.5 + 10.0)
		DoomFx.embers(self, Vector3(c3.x, c3.y - 8.0, c3.z), ext, 50)
		DoomFx.haze(self, Vector3(c3.x, c3.y - 14.0, c3.z), ext * 1.4, 18)


# ---- live effects -----------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null:
		return
	var t: float = Game.course_time
	for tl: Dictionary in _tells:
		var left: float = INF
		var period: float = 1.0
		var cyc: int = 0
		match str(tl["kind"]):
			"press":
				var cr: Crusher = tl["node"]
				period = cr.period
				var u: float = fposmod(t / cr.period + cr.phase, 1.0)
				left = fposmod(Crusher.SLAM - u, 1.0) * cr.period
				cyc = int(floor(t / cr.period + cr.phase - Crusher.SLAM))
			"ram":
				var p: Piston = tl["node"]
				period = p.period
				var u2: float = fposmod(t / p.period + p.phase, 1.0)
				left = fposmod(Piston.PUNCH_START - u2, 1.0) * p.period
				cyc = int(floor(t / p.period + p.phase - Piston.PUNCH_START))
		var warning: bool = left < 1.0
		var e: float = (4.5 if fmod(t, 0.2) < 0.1 else 1.2) if warning else 0.3
		for m: StandardMaterial3D in (tl["mats"] as Array):
			m.emission_energy_multiplier = e
		if warning and int(tl["cycle"]) != cyc:
			tl["cycle"] = cyc
			var n3: Node3D = tl["node"]
			# SOUND: doom_press_warn - a warning bell clanging ~1 s before a press slams or a ram punches
			WorldAudio.at(self, "doom_press_warn", n3.global_position, 0.8, 30.0)
	for e2: Dictionary in _arrivals:
		e2["cool"] = maxf(float(e2["cool"]) - dt, 0.0)
		if float(e2["cool"]) <= 0.0 and player.global_position.distance_to(e2["at"]) < 2.5:
			e2["cool"] = 3.0
			for p2: GPUParticles3D in e2["p"]:
				p2.restart()
				p2.emitting = true
