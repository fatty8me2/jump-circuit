extends LevelBase
## 19. NEON CITY - cyberpunk rooftops at night in the rain. Eighteen stages, each ending on a
## checkpoint, climbing from the low roofs of a dense, wet downtown - noodle-bar signs, water tanks,
## AC units and steam vents - across alleys, skybridges and a traffic canyon, up the tallest tower to
## the top of its antenna spire with the whole city below. Hot magenta, amber and teal signs on wet,
## mirror-puddled roofs; hover traffic streaming between the towers; rain everywhere.
##
##  1 Noodle Roof        hops over the alley on AC units and a water tank, MANTLE the penthouse
##  2 Signal Alley       fire-escape hops, WALL RUN the giant blade sign over the alley
##  3 Hologram Crossing  a wave of HOLOGRAM platforms flickering out one after another
##  4 Searchlight Yard   BRANCH: the long catwalk under a SEARCHLIGHT DRONE | MANTLE the sign
##                       gantry and hop along the billboard tops
##  5 Window Washers     ride two GONDOLAS up the tower face, the security LASER on the roof
##  6 Exhaust Row        a neon belt running back at you, the exhaust-fan rams (PISTONS)
##  7 Rush Hour          a broken skybridge cut by two lanes of CROSSING TRAFFIC - jump between cars
##  8 Awning Hop         bounce awnings (pads) up the balconies, two HOLOGRAMS to the checkpoint
##  9 Compactor Alley    BRANCH: the service belt under two trash COMPACTORS (crushers), MANTLE
##                       out | MANTLE the kiosk and WALL RUN the blade sign
##                       [shortcut: WALL RUN the alley wall past both compactors onto the block]
## 10 SKYWAY             SET PIECE: board a hover car at the station, ride it out over the traffic
##                       canyon, hop across to the car in the next lane as it draws alongside, and
##                       ride that one into the far station
## 11 Sign Chimney       a bounce awning up to the chimney, three WALL RUNS up between two signs,
##                       out onto the top
## 12 Transit Gate      BRANCH: two HOLOGRAMS and a DRONE-swept roof | MANTLE the transit kiosk, beat
##                       its LASER and take the PORTAL
## 13 Neon Rail          a neon boost rail into a long leap, two LASER fences, MANTLE out
##                       [shortcut: the side catwalk and the elevator PORTAL]
## 14 Billboard Carousel ride the rotating rooftop billboard round and jump off at the exit
## 15 Drone Ledge        a narrow ledge round the tower under two SEARCHLIGHT DRONES, MANTLE out
##                       [shortcut: a max-height MANTLE up the service pillar, the cable duct]
## 16 Express Lane       board a hover car on the climbing express lane and ride it up the tower
## 17 The Crown          two MANTLES, the crown COMPACTOR, two HOLOGRAMS
##                       [shortcut: WALL RUN the crown's flank past the compactor]
## 18 Antenna Spire      WALL RUN the spire's fin, MANTLE onto the antenna deck, the finish
##
## Neon mechanics (own scripts): NeonTraffic (hover-car lanes: rideable cars and crossing traffic),
## NeonDrone (searchlight drones), NeonHolo (hologram platforms with a glitch tell). Route variants
## for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut.

const MAGENTA := Color(1.0, 0.2, 0.7)
const AMBER := Color(1.0, 0.62, 0.15)
const TEAL := Color(0.1, 0.95, 0.85)
const VIOLET := Color(0.62, 0.3, 1.0)
const RED := Color(1.0, 0.15, 0.2)

## The street far below (visual) and the kill floor.
const STREET_Y: float = -60.0
## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: NeonDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Bursts that fire when the player arrives at a spot (portal exits): {"at", "p": [GPUParticles3D], "cool"}
var _arrivals: Array[Dictionary] = []
## Places set dressing keeps clear of (world x, y, z, flat radius).
var _keep_out: Array[Vector4] = []
## Every walkable roof (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _roofs: Array[Dictionary] = []
var _lanes: Array[NeonTraffic] = []


func _configure() -> void:
	theme_id = "neon"
	music_track = "neon"
	kill_y = -45.0
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


## A wet rooftop slab (walkable), with a tower (or a pylon for a small one) built down to the street.
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, under: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if under:
		_roofs.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": thick})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A round landing (a water-tank lid, a vent cap) on its own pylon.
func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.8) -> Dictionary:
	var body: StaticBody3D = kit.disc(_w(c), r, thick, style, 0.0)
	_roofs.append({"top": _w(c), "size": Vector3(r * 1.4, 0, r * 1.4), "drop": thick})
	return {"c": c, "r": r, "node": body}


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	_roofs.append({"top": _w(top), "size": _sz(Vector3(size.x, 0, size.z)), "drop": size.y})
	return {"c": top, "hx": size.x * 0.5, "hz": size.z * 0.5}


## Takeoff spot on `a`: on the line toward `toward`, `inset` metres inside the edge.
func _edge(a: Dictionary, toward: Vector3, inset: float = 0.35) -> Vector3:
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


## A hologram platform whose top is at local `c`.
func _holo(c: Vector3, size: float, period: float, on: float, phase: float, tint: Color = TEAL) -> NeonHolo:
	var h := NeonHolo.new()
	h.size = Vector3(size, 0.35, size)
	h.period = period
	h.on_fraction = on
	h.phase = phase
	h.tint = tint
	h.rotation.y = deg_to_rad(_yaw)
	h.position = _w(c) - Vector3(0, 0.175, 0)
	add_child(h)
	# the projector's pylon down to the street
	var py: float = _w(c).y - 0.35 - h.projector_drop - 0.15
	_pylon(Vector3(_w(c).x, py, _w(c).z), 0.25)
	return h


## A searchlight drone sweeping its pool between local floor points a and b.
func _drone(a: Vector3, b: Vector3, period: float, phase: float, hover: float = 7.5, radius: float = 1.7) -> NeonDrone:
	var d := NeonDrone.new()
	d.a = _w(a)
	d.b = _w(b)
	d.period = period
	d.phase = phase
	d.hover = hover
	d.radius = radius
	add_child(d)
	return d


## A security beam across the route at local floor point `c` (`width` across) between two posts.
func _beam(c: Vector3, width: float, period: float, on: float, phase: float, height: float = 2.4) -> LaserGate:
	return kit.laser(_w(c + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.2), period, on, phase, _yaw)


## Checkpoint roof facing the next stage's heading (_next_yaw), with its neon.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var k: int = _cp_world.size()
	var col: Color = [MAGENTA, TEAL, AMBER][k % 3]
	# banked-stage feedback: a shower of neon sparks, a puff of rain-mist and a ring
	var fx: Array[GPUParticles3D] = NeonFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6 if p != fx[2] else 0.05, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: neon_checkpoint - a stage banked (an electric zap-chime and a burst of sparks)
			WorldAudio.at(self, "neon_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	# a short neon post on the two back corners
	var h: float = size * 0.5 - 0.35
	for s: float in [-1.0, 1.0]:
		var post := Look.box(Vector3(0.16, 1.4, 0.16), Look.flat(col, 0.3, 0.0, 3.0), _w(c + Vector3(s * h, 0.7, h)))
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(post)
	return d


## Fork signpost: two neon arrow posts and a floor strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.3, 1.3]:
		var post := Look.box(Vector3(0.14, 2.4, 0.14), Look.flat(Color(0.08, 0.08, 0.1), 0.4, 0.6), _w(p + Vector3(sx, 1.2, 0)))
		add_child(post)
		var lamp := Look.box(Vector3(0.3, 0.5, 0.3), Look.flat(col, 0.3, 0.0, 3.5), _w(p + Vector3(sx, 2.5, 0)))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.6)), _sz(Vector3(1.4, 0.05, 0.3)), col)


## A slim steel pylon from `top` down to the street (holo projectors, small landings).
func _pylon(top: Vector3, r: float) -> void:
	var h: float = top.y - STREET_Y
	if h < 1.0:
		return
	var n := Look.box(Vector3(r * 2.0, h, r * 2.0), Look.flat(Color(0.09, 0.09, 0.11), 0.35, 0.7), Vector3(top.x, top.y - h * 0.5, top.z))
	add_child(n)


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


static func _dark(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


static func _ram_clear(p: Piston, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


static func _press_ok(c: Crusher, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if c.gap_at(Game.course_time + s) < 2.0 or not c.is_clear_for(Game.course_time + s, 0.0):
			return false
		s += 0.04
	return true


static func _holo_ok(h: NeonHolo, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not h.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


## Stand still until `node` (a mover) is within `radius` of `point` (a wait: the pause hook applies).
func _wait_mover(node: MovingPlatform, point: Vector3, radius: float) -> void:
	r_wait(node, point, radius)


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = NeonDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	var starts: Array[int] = []
	var origins: Array[Vector3] = []
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		starts.append(route.size())
		origins.append(_o)
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	starts.append(route.size())
	origins.append(_o)
	_stage_18()
	_surroundings()
	_neon_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


# ---- stage 1: Noodle Roof - hops over the alley, mantle the penthouse ------------------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	_roofs.append({"top": _w(Vector3.ZERO), "size": Vector3(14, 0, 14), "drop": 2.0})
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	var a1: Dictionary = _blk(Vector3(0, 0.6, -12.4), 2.6, 2.6, "alt")
	var t1: Dictionary = _disc(Vector3(2.2, 1.2, -18.6), 1.3, "alt")
	var r2: Dictionary = _blk(Vector3(0, 1.2, -28.6), 8.0, 8.0)
	var pent: Dictionary = _ledge(Vector3(0, 4.5, -36.8), Vector3(6.0, 9.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 4.5, -46.1))
	_hop(start, a1)
	_hop(a1, t1)
	_hop(t1, r2)
	r_walk(_w(Vector3(0, 1.2, -31.0)))
	r_mantle(_w(Vector3(0, 1.2, -32.25)), _w(Vector3(0, 4.5, -37.0)))
	_hop(pent, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the noodle bar roof you start on: its blade sign, AC units, vents and a dish
	deco.blade_sign(_w(Vector3(-6.4, 0, 5.6)), 2.0, 7.0, deg_to_rad(_yaw) + PI * 0.5, MAGENTA, AMBER)
	deco.ac_unit(_w(Vector3(4.6, 0, 4.4)), Vector3(1.8, 1.1, 1.5), 0.2)
	deco.ac_unit(_w(Vector3(4.8, 0, 1.6)), Vector3(1.6, 1.0, 1.4), -0.1)
	deco.vent(_w(Vector3(-5.2, 0, -1.0)), 1.6, 6.0)
	deco.dish(_w(Vector3(-5.0, 0, 3.0)), 0.8, 2.3)
	deco.strip_sign(_w(Vector3(0, -1.2, -7.05)), 8.0, 1.0, deg_to_rad(_yaw), AMBER, MAGENTA)
	# the alley's far side: the AC unit is real, the water tank stands on its stilts
	deco.water_tank(_w(Vector3(2.2, -3.6, -18.6)), 1.2, 3.0, 1.8)
	deco.vent(_w(Vector3(-3.0, 1.2, -26.2)), 1.2, 5.0)
	deco.ac_unit(_w(Vector3(3.0, 1.2, -30.8)), Vector3(1.4, 0.9, 1.2), 0.3)
	deco.antenna(_w(Vector3(-2.2, 4.5, -37.8)), 5.0)
	deco.blade_sign(_w(Vector3(3.8, -6.0, -24.6)), 1.8, 6.5, deg_to_rad(_yaw) + PI * 0.5, TEAL, MAGENTA)
	r2.clear()
	return cp["c"]


# ---- stage 2: Signal Alley - fire-escape hops, wall run the blade sign -----------------------------

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f1: Dictionary = _blk(Vector3(0, 0.6, -8.0), 3.0, 3.0, "alt")
	var f2: Dictionary = _blk(Vector3(-1.0, 1.2, -13.6), 2.6, 2.6, "alt")
	var s1: Dictionary = _blk(Vector3(0.2, 1.2, -21.0), 3.0, 3.0, "alt")
	kit.wallrun(_w(Vector3(2.5, 2.4, -32.0)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var s2: Dictionary = _blk(Vector3(-0.2, 1.2, -45.0), 3.6, 5.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 1.2, -54.4))
	_hop(cp0, f1)
	_hop(f1, f2)
	_hop(f2, s1)
	r_wallrun(_w(Vector3(0.5, 1.2, -22.15)), _w(Vector3(2.0, 2.6, -26.1)), _w(Vector3(2.0, 2.6, -37.0)), _w(Vector3(-0.2, 1.2, -44.3)))
	_hop(s2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the sign the panel is part of: a huge blade of glyphs on the tower behind it
	deco.blade_sign(_w(Vector3(3.6, -4.0, -32.0)), 3.0, 14.0, deg_to_rad(_yaw) + PI * 0.5, MAGENTA, TEAL)
	_backing(Vector3(5.6, -8.0, -32.0), Vector3(3.0, 30.0, 20.0))
	# fire-escape railings and drips, an alley of steam below
	for z: float in [-8.0, -13.6, -21.0]:
		NeonFx.drips(self, _w(Vector3(-1.6, 1.0, z - 1.4)), _w(Vector3(1.6, 1.0, z - 1.4)), 6)
	deco.vent(_w(Vector3(-4.0, -12.0, -30.0)), 2.0, 9.0, false)
	deco.vent(_w(Vector3(-3.0, -12.0, -38.0)), 2.0, 9.0, false)
	deco.water_tank(_w(Vector3(1.2, 1.2, -55.5)), 1.0, 2.0, 1.4)
	f2.clear()
	return cp["c"]


## A solid-looking tower slab behind a wall-run panel (visual, no collision).
func _backing(c: Vector3, size: Vector3) -> void:
	var mi := Look.box(_sz(size), NeonDecor.facade(), _w(c))
	add_child(mi)


# ---- stage 3: Hologram Crossing - a wave of hologram platforms ----------------------------------------

func _stage_3() -> Vector3:
	var s0: Dictionary = _blk(Vector3(0, 0, -8.0), 6.0, 4.0)
	var mz: Array[Vector3] = [Vector3(0, 0, -16.0), Vector3(0, 0.6, -22.05), Vector3(1.1, 1.2, -27.95), Vector3(0.1, 1.2, -35.0)]
	var holos: Array[NeonHolo] = []
	var tints: Array[Color] = [TEAL, MAGENTA, TEAL, MAGENTA]
	for i: int in mz.size():
		holos.append(_holo(mz[i], 2.1, 5.0, 0.7, fposmod(-0.15 * float(i), 1.0), tints[i]))
	var merge: Dictionary = _blk(Vector3(0, 1.2, -42.8), 6.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -51.3))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), s0, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(0, 0, -8.4)))
	var starts: Array[float] = [0.6, 1.35, 2.1, 2.85]
	_wait(func() -> bool:
		for i: int in holos.size():
			if not _holo_ok(holos[i], starts[i] - 0.1, starts[i] + 1.55):
				return false
		return true)
	var prev: Dictionary = s0
	for i: int in mz.size():
		var m: Dictionary = _area(mz[i], 1.05, 1.05)
		_hop(prev, m)
		prev = m
	_hop(prev, merge, Vector3(0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# a canyon of signs either side of the crossing
	for i: int in 3:
		var z: float = -14.0 - 9.0 * float(i)
		deco.blade_sign(_w(Vector3(-7.5, -6.0, z)), 2.0, 9.0, deg_to_rad(_yaw) + PI * 0.5, [MAGENTA, AMBER, TEAL][i], VIOLET)
	deco.billboard(_w(Vector3(8.5, 6.0, -26.0)), 9.0, 5.0, deg_to_rad(_yaw) - PI * 0.5, TEAL, MAGENTA)
	_backing(Vector3(11.0, -14.0, -26.0), Vector3(4.0, 36.0, 22.0))
	NeonFx.motes(self, _w(Vector3(0, 2.0, -26.0)), _sz(Vector3(4.0, 2.5, 12.0)), 50)
	merge.clear()
	return cp["c"]


# ---- stage 4: Searchlight Yard (BRANCH) - the drone catwalk, or the sign gantry -------------------



func _stage_4() -> Vector3:
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (magenta): the catwalk, swept by a searchlight drone
	var walk: Dictionary = _blk(Vector3(-3.5, 0, -23.0), 2.6, 22.0, "alt", 0.8)
	var dr: NeonDrone = _drone(Vector3(-12.0, 0, -23.0), Vector3(-0.8, 0, -23.0), 9.0, 0.0)
	# RIGHT (teal): mantle the sign gantry, then the billboard tops
	_ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 8.0, 3.2), "alt")
	var g1: Dictionary = _blk(Vector3(4.2, 3.3, -20.6), 1.8, 1.8, "accent", 0.6)
	var g2: Dictionary = _blk(Vector3(3.6, 3.3, -26.2), 1.8, 1.8, "accent", 0.6)
	var g3: Dictionary = _blk(Vector3(4.2, 3.3, -31.6), 1.8, 1.8, "accent", 0.6)
	var merge: Dictionary = _blk(Vector3(0, 0, -40.0), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 0, -49.5))
	_sign(Vector3(-3.5, 0, -6.6), MAGENTA)
	_sign(Vector3(4.0, 0, -6.6), TEAL)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -9.0)))
		r_jump(_w(Vector3(-3.5, 0, -9.65)), _w(Vector3(-3.5, 0, -13.6)))
		r_walk(_w(Vector3(-3.5, 0, -18.0)))
		var lane: Array = [_w(Vector3(-3.5, 0, -21.0)), _w(Vector3(-3.5, 0, -23.0)), _w(Vector3(-3.5, 0, -25.0))]
		_wait(func() -> bool: return dr.clear_of(lane, 0.7, 0.0, 2.4), _w(Vector3(-3.5, 0, -18.0)))
		r_walk(_w(Vector3(-3.5, 0, -33.4)))
		r_jump(_w(Vector3(-3.5, 0, -33.65)), _w(Vector3(-2.5, 0, -39.6)))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		_hop(_area(Vector3(4.0, 3.3, -13.6), 1.5, 1.6), g1)
		_hop(g1, g2)
		_hop(g2, g3)
		_hop(g3, merge, Vector3(3.0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the gantry: billboard faces under the tops, a holo ad over the yard
	for g: Dictionary in [g1, g2, g3]:
		var gc: Vector3 = g["c"]
		deco.strip_sign(_w(gc + Vector3(0, -1.0, 0.95)), 1.7, 1.2, deg_to_rad(_yaw), TEAL, AMBER)
	deco.billboard(_w(Vector3(-13.0, 7.0, -30.0)), 8.0, 4.5, deg_to_rad(_yaw) + PI * 0.5, MAGENTA, AMBER)
	deco.water_tank(_w(Vector3(-5.5, 0, -7.5)), 1.0, 2.0, 1.2)
	deco.ac_unit(_w(Vector3(5.0, 0, -40.5)), Vector3(1.6, 1.0, 1.4), 0.1)
	deco.vent(_w(Vector3(-5.0, 0, -41.0)), 1.4, 6.0)
	walk.clear()
	return cp["c"]


# ---- stage 5: Window Washers - two gondolas up the tower face, the roof's security laser ------------

func _stage_5() -> Vector3:
	var appr: Dictionary = _blk(Vector3(0, 0, -8.0), 6.0, 4.0)
	# the tower: its roof (y 14) starts right behind the face the gondolas ride up
	var roof: Dictionary = _blk(Vector3(0, 14.0, -18.5), 10.0, 11.0, "main", 1.2)
	var g1: MovingPlatform = kit.mover(_w(Vector3(0, 0, -11.6)), _sz(Vector3(3.0, 0.4, 2.0)), [Vector3.ZERO, Vector3(0, 7.0, 0)], 9.0, 0.0)
	g1.dwell = 0.3
	var g2: MovingPlatform = kit.mover(_w(Vector3(3.8, 7.0, -11.6)), _sz(Vector3(3.0, 0.4, 2.0)), [Vector3.ZERO, Vector3(0, 7.0, 0)], 9.0, 0.5)
	g2.dwell = 0.3
	_gondola(g1, 7.0)
	_gondola(g2, 7.0)
	var beam: LaserGate = _beam(Vector3(0, 14.0, -18.0), 10.0, 4.5, 0.4, 0.0)
	var cp: Dictionary = _cp(Vector3(0, 14.0, -29.0))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), appr, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(0, 0, -9.3)))
	var bottom1: Vector3 = _w(Vector3(0, -0.2, -11.6))
	_wait_mover(g1, bottom1, 0.3)
	r_jump_onto(_w(Vector3(0, 0, -9.65)), g1, Vector3(0, 0.2, 0))
	var top1: Vector3 = _w(Vector3(0, 6.8, -11.6))
	route.append({"kind": "candy_ride", "stand": Vector3(0, 0.2, 0), "cars": [g2], "local": Vector3(0, 0.2, 0), "until": func() -> bool:
		return g1.global_position.distance_to(top1) < 0.3 and g2.global_position.distance_to(_g_bottom(g2)) < 0.3})
	var top2: Vector3 = _w(Vector3(3.8, 13.8, -11.6))
	route.append({"kind": "candy_ride", "stand": Vector3(0, 0.2, 0), "to": _w(Vector3(2.0, 14.0, -14.6)), "until": func() -> bool:
		return g2.global_position.distance_to(top2) < 0.3})
	_wait(func() -> bool: return _dark(beam, 0.05, 2.0), _w(Vector3(2.0, 14.0, -14.6)))
	r_walk(_w(Vector3(0.5, 14.0, -23.2)))
	_hop(roof, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the tower face behind the gondolas: lit windows, a vertical sign, the davits on the roof
	deco.blade_sign(_w(Vector3(-4.2, -4.0, -12.95)), 2.2, 12.0, deg_to_rad(_yaw), AMBER, MAGENTA)
	deco.antenna(_w(Vector3(-4.0, 14.0, -22.5)), 7.0)
	deco.water_tank(_w(Vector3(3.5, 14.0, -22.6)), 1.2, 2.4, 1.6)
	deco.vent(_w(Vector3(-3.6, 14.0, -15.4)), 1.0, 5.0)
	appr.clear()
	return cp["c"]


func _g_bottom(g: MovingPlatform) -> Vector3:
	return g.global_position - g.offset_at(Game.course_time)


## Window-cleaning gondola dressing: a cage rail round the platform, its cables up to a davit arm on
## the roof (`rise` m above its lowest stop), and the winch's hum while it moves.
func _gondola(g: MovingPlatform, rise: float) -> void:
	var steel: StandardMaterial3D = Look.flat(Color(0.75, 0.75, 0.8), 0.3, 0.7)
	var yellow: StandardMaterial3D = Look.flat(AMBER, 0.4, 0.2, 1.2)
	var s: Vector3 = g.size
	for sx: float in [-1.0, 1.0]:
		g.add_child(Look.box(Vector3(0.06, 1.0, s.z), steel, Vector3(sx * (s.x * 0.5 - 0.05), 0.7, 0)))
		g.add_child(Look.box(Vector3(0.08, 0.08, s.z), yellow, Vector3(sx * (s.x * 0.5 - 0.05), 1.2, 0)))
	g.add_child(Look.box(Vector3(s.x, 0.08, 0.08), yellow, Vector3(0, 1.2, s.z * 0.5 - 0.05)))
	var top: Vector3 = g.global_position - g.offset_at(Game.course_time) + Vector3(0, rise + 9.0, 0)
	for sx2: float in [-1.0, 1.0]:
		var c := Look.cylinder(0.03, rise + 9.0, Look.flat(Color(0.2, 0.2, 0.22), 0.4, 0.6), Vector3.ZERO, -1.0, 4)
		c.position = top + g.basis * Vector3(sx2 * (s.x * 0.5 - 0.2), -(rise + 9.0) * 0.5, 0)
		add_child(c)
	add_child(Look.box(Vector3(0.3, 0.3, 2.4), steel, top + Vector3(0, 0.2, 0)))
	# SOUND: neon_gondola_motor - the winch whirring while the cradle moves (loop)
	var hum: AudioStreamPlayer3D = WorldAudio.loop("neon_gondola_motor", g, -10.0, 18.0, 3.0)
	if hum != null:
		var t := Timer.new()
		t.wait_time = 0.2
		t.autostart = true
		t.timeout.connect(func() -> void:
			var v: float = (g.offset_at(Game.course_time + 0.1) - g.offset_at(Game.course_time)).length()
			WorldAudio.set_active(hum, v > 0.02))
		g.add_child(t)


# ---- stage 6: Exhaust Row - the neon belt, the fan rams [shortcut: wall run the exhaust tower] -------

func _stage_6() -> Vector3:
	kit.conveyor(_w(Vector3(0, 0, -11.0)), Vector3(2.6, 0.4, 12.0), _yaw + 180.0, 5.0)
	kit.block(_w(Vector3(0, -1.0, -11.0)), _sz(Vector3(2.2, 1.6, 11.6)), Color(0.08, 0.06, 0.1), false)
	_neon_rail(Vector3(0, 0, -11.0), 12.0, 2.6, MAGENTA)
	_roofs.append({"top": _w(Vector3(0, -0.2, -11.0)), "size": _sz(Vector3(2.6, 0, 12.0)), "drop": 1.8})
	var f: Dictionary = _blk(Vector3(0, 0.6, -25.0), 3.0, 10.0, "alt")
	var p0: Piston = _fan(Vector3(3.2, 1.9, -23.0), 90.0, 3.0, 6.0, 0.0)
	kit.block(_w(Vector3(4.6, 1.4, -23.0)), Vector3(2.4, 3.0, 2.2), Color(0.12, 0.12, 0.15), true, _yaw)
	var p1: Piston = _fan(Vector3(-3.2, 1.9, -27.0), -90.0, 3.0, 6.0, fposmod(-0.05, 1.0))
	kit.block(_w(Vector3(-4.6, 1.4, -27.0)), Vector3(2.4, 3.0, 2.2), Color(0.12, 0.12, 0.15), true, _yaw)
	var cp: Dictionary = _cp(Vector3(0, 0.6, -37.0))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -6.4)))
	r_walk(_w(Vector3(0, 0, -16.4)))
	r_jump(_w(Vector3(0, 0, -16.7)), _w(Vector3(0, 0.6, -21.4)))
	_wait(func() -> bool: return _ram_clear(p0, 0.0, 1.7) and _ram_clear(p1, 0.3, 2.3), _w(Vector3(0, 0.6, -21.0)))
	r_walk(_w(Vector3(0, 0.6, -29.2)))
	_hop(f, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the row: exhaust stacks steaming, a strip of shop signs along the belt
	deco.vent(_w(Vector3(6.6, 0.6, -18.0)), 3.0, 8.0)
	deco.vent(_w(Vector3(-6.6, 0.6, -32.0)), 3.0, 8.0, false)
	deco.strip_sign(_w(Vector3(1.6, -0.8, -11.0)), 10.0, 1.2, deg_to_rad(_yaw) + PI * 0.5, AMBER, TEAL)
	deco.blade_sign(_w(Vector3(-6.0, 1.0, -36.0)), 1.8, 7.0, deg_to_rad(_yaw), TEAL, MAGENTA)
	return cp["c"]


## A neon tube along each side of a belt (`c` = belt top centre, local frame).
func _neon_rail(c: Vector3, length: float, width: float, col: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		var tube := Look.box(_sz(Vector3(0.1, 0.1, length)), Look.flat(col, 0.3, 0.0, 3.5), _w(c + Vector3(sx * (width * 0.5 + 0.08), 0.05, 0)))
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tube)


## An exhaust-fan ram: the piston with a big caged fan on its face.
func _fan(top: Vector3, yaw_extra: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.8, 1.3, 1.4)
	var p: Piston = kit.piston(_w(top), size, _yaw + yaw_extra, stroke, period, phase, 9.0)
	var face := Look.cylinder(0.62, 0.12, Look.flat(Color(0.1, 0.1, 0.12), 0.4, 0.6), Vector3(0, 0, -size.z * 0.5 - 0.06), -1.0, 20)
	face.rotation.x = PI * 0.5
	p.add_child(face)
	var fan := Node3D.new()
	fan.set_script(preload("res://visual/spin.gd"))
	fan.set("period", 0.35)
	fan.set("axis", Vector3(0, 0, 1))
	fan.position = Vector3(0, 0, -size.z * 0.5 - 0.14)
	for b: int in 4:
		var blade := Look.box(Vector3(1.0, 0.18, 0.03), Look.flat(Color(0.6, 0.6, 0.65), 0.3, 0.7))
		blade.rotation.z = float(b) * PI * 0.25
		fan.add_child(blade)
	p.add_child(fan)
	p.add_child(Look.box(Vector3(1.3, 0.06, 0.06), Look.flat(AMBER, 0.3, 0.0, 2.5), Vector3(0, 0.62, -size.z * 0.5 - 0.1)))
	return p


# ---- stage 7: Rush Hour - a broken skybridge cut by two lanes of crossing traffic -------------------

func _stage_7() -> Vector3:
	var b1: Dictionary = _blk(Vector3(0, 0, -9.5), 2.8, 7.0, "alt", 0.8, false)
	var b2: Dictionary = _blk(Vector3(0, 0, -19.6), 2.8, 6.0, "alt", 0.8, false)
	var b3: Dictionary = _blk(Vector3(0, 0, -29.2), 2.8, 6.0, "alt", 0.8, false)
	var cp: Dictionary = _cp(Vector3(0, 0, -39.2))
	# lane A (z -14.8) streams right to left, lane B (z -24.4) left to right; both drop away 40 m
	# on their return so the loops never come near the course
	var la: NeonTraffic = _crossing_lane(-14.8, 1.0, 12.0, 6, 0.0, 12.0)
	var lb: NeonTraffic = _crossing_lane(-24.4, -1.0, 10.0, 5, 17.0, 20.0)
	_bridge_dress(b1, b2, b3)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), b1, Vector3(0, 0, 1.2))
	r_walk(_w(Vector3(0, 0, -12.3)))
	var pa: Vector3 = _w(Vector3(0, 1.3, -14.8))
	_wait(func() -> bool: return la.clear_at(pa, 2.2, 0.0, 2.1), _w(Vector3(0, 0, -12.3)))
	r_jump(_w(Vector3(0, 0, -12.65)), _w(Vector3(0, 0, -18.2)))
	r_walk(_w(Vector3(0, 0, -21.9)))
	var pb: Vector3 = _w(Vector3(0, 1.3, -24.4))
	_wait(func() -> bool: return lb.clear_at(pb, 2.2, 0.0, 2.1), _w(Vector3(0, 0, -21.9)))
	r_jump(_w(Vector3(0, 0, -22.25)), _w(Vector3(0, 0, -27.8)))
	_hop(b3, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## A lane of crossing traffic across the course at local z, flowing toward local +x (dir +1) or -x.
func _crossing_lane(z: float, dir: float, speed: float, cars: int, offset: float, radius: float) -> NeonTraffic:
	var t := NeonTraffic.new()
	var a: Vector3 = _w(Vector3(-45.0 * dir, 2.6, z))
	var b: Vector3 = _w(Vector3(45.0 * dir, 2.6, z))
	# turn back toward the stage's start side (local +z, clear of the previous stage's towers),
	# diving 40 m below on the return so the loop never comes near the course
	var side: float = dir
	t.path = NeonTraffic.lane(a, b, side, radius, 40.0)
	t.speed = speed
	t.cars = cars
	t.offset = offset
	t.deadly = true
	t.tall = true
	t.palette = PackedColorArray([AMBER, RED, Color(0.9, 0.9, 1.0)])
	add_child(t)
	t.add_crossing(_w(Vector3(0, 1.3, z)), _d(Vector3(0, 0, 1)), 2.6, _w(Vector3(0, 0, z)).y)
	_lanes.append(t)
	return t


func _bridge_dress(b1: Dictionary, b2: Dictionary, b3: Dictionary) -> void:
	# the bridge's broken ends: girders, hanging cables, sparks spitting from cut wiring
	for b: Dictionary in [b1, b2, b3]:
		var c: Vector3 = b["c"]
		var hz: float = b["hz"]
		for sx: float in [-1.0, 1.0]:
			var rail := Look.box(_sz(Vector3(0.08, 0.08, hz * 2.0)), Look.flat(MAGENTA, 0.3, 0.0, 3.0), _w(c + Vector3(sx * 1.45, 0.9, 0)))
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(rail)
			for k: int in int(hz):
				add_child(Look.box(Vector3(0.06, 0.9, 0.06), Look.flat(Color(0.2, 0.2, 0.24), 0.4, 0.6), _w(c + Vector3(sx * 1.45, 0.45, -hz + 0.5 + float(k) * 2.0))))
		add_child(Look.box(_sz(Vector3(2.0, 1.2, hz * 2.0)), Look.flat(Color(0.08, 0.08, 0.1), 0.4, 0.6), _w(c + Vector3(0, -1.4, 0))))
	NeonFx.sign_sparks(self, _w(Vector3(0.9, -0.5, -13.1)))
	NeonFx.sign_sparks(self, _w(Vector3(-0.9, -0.5, -22.7)), Color(1.6, 2.2, 2.6))
	# signs at the bridge head
	deco.blade_sign(_w(Vector3(-4.0, -2.0, -6.0)), 2.0, 8.0, deg_to_rad(_yaw) + PI * 0.5, RED, AMBER)
	deco.billboard(_w(Vector3(14.0, 8.0, -20.0)), 10.0, 6.0, deg_to_rad(_yaw) - PI * 0.5, AMBER, MAGENTA)


# ---- stage 8: Awning Hop - bounce awnings up the balconies, two holograms --------------------------

func _stage_8() -> Vector3:
	var p0: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 6.0)
	var pad1 := Vector3(0, 0, -10.6)
	kit.pad(_w(pad1), 21.0, 0.0, 0.0, 1.2)
	var bal1: Dictionary = _blk(Vector3(0, 5.8, -17.5), 4.0, 5.0, "alt")
	var pad2 := Vector3(0, 5.8, -18.6)
	kit.pad(_w(pad2), 21.0, 0.0, 0.0, 1.2)
	var bal2: Dictionary = _blk(Vector3(0, 11.6, -25.8), 4.0, 5.0, "alt")
	var h1: NeonHolo = _holo(Vector3(0, 11.6, -33.4), 2.4, 5.0, 0.7, 0.0, MAGENTA)
	var h2: NeonHolo = _holo(Vector3(0, 12.2, -39.4), 2.4, 5.0, 0.7, fposmod(-0.15, 1.0), TEAL)
	var cp: Dictionary = _cp(Vector3(0, 12.2, -47.6))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), p0, Vector3(0, 0, 1.2))
	r_walk(_w(pad1 + Vector3(0, 0, 1.4)))
	r_pad(_w(pad1), _w((bal1["c"] as Vector3) + Vector3(0, 0, 0.6)))
	r_walk(_w(pad2 + Vector3(0, 0, 1.2)))
	r_pad(_w(pad2), _w((bal2["c"] as Vector3) + Vector3(0, 0, 0.4)))
	r_walk(_w(Vector3(0, 11.6, -26.6)))
	_wait(func() -> bool: return _holo_ok(h1, 0.3, 1.3 + 1.0) and _holo_ok(h2, 1.0, 2.1 + 1.0))
	_hop(bal2, _area(Vector3(0, 11.6, -33.4), 1.2, 1.2))
	_hop(_area(Vector3(0, 11.6, -33.4), 1.2, 1.2), _area(Vector3(0, 12.2, -39.4), 1.2, 1.2))
	_hop(_area(Vector3(0, 12.2, -39.4), 1.2, 1.2), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the balconies: striped awnings over the pads, shop strips, laundry lines, a tower behind
	_awning(pad1, MAGENTA)
	_awning(pad2, TEAL)
	deco.strip_sign(_w(Vector3(0, 4.6, -14.95)), 3.8, 0.9, deg_to_rad(_yaw), AMBER, MAGENTA)
	deco.strip_sign(_w(Vector3(0, 10.4, -23.25)), 3.8, 0.9, deg_to_rad(_yaw), TEAL, AMBER)
	deco.blade_sign(_w(Vector3(3.2, 3.0, -17.0)), 1.6, 8.0, deg_to_rad(_yaw) + PI * 0.5, VIOLET, TEAL)
	deco.billboard(_w(Vector3(-9.0, 16.0, -38.0)), 8.0, 5.0, deg_to_rad(_yaw) + PI * 0.5, MAGENTA, TEAL)
	p0.clear()
	return cp["c"]


## A striped shop awning tilted over a bounce pad (purely visual, high enough not to touch the arc).
func _awning(pad: Vector3, col: Color) -> void:
	for i: int in 6:
		var stripe := Look.box(Vector3(0.42, 0.06, 1.8), Look.flat(col if i % 2 == 0 else Color(0.9, 0.88, 0.85), 0.6), _w(pad + Vector3(-1.05 + 0.42 * float(i), 3.1, 2.2)))
		stripe.rotation = Vector3(-0.25, deg_to_rad(_yaw), 0)
		add_child(stripe)
	kit.glow_strip(_w(pad + Vector3(0, 0.05, 1.4)), _sz(Vector3(2.4, 0.06, 0.12)), col)


# ---- stage 9: Compactor Alley (BRANCH) - the belt under the compactors, or the kiosk and the sign ----

func _stage_9() -> Vector3:
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (amber): the service belt under two trash compactors, mantle out
	kit.conveyor(_w(Vector3(-3.5, 0, -22.35)), Vector3(2.8, 0.4, 20.7), _yaw, 4.0)
	kit.block(_w(Vector3(-3.5, -1.0, -22.35)), _sz(Vector3(2.4, 1.6, 20.3)), Color(0.08, 0.06, 0.1), false)
	_neon_rail(Vector3(-3.5, 0, -22.35), 20.7, 2.8, AMBER)
	_roofs.append({"top": _w(Vector3(-3.5, -0.2, -22.35)), "size": _sz(Vector3(2.8, 0, 20.7)), "drop": 1.8})
	var c1: Crusher = _compactor(Vector3(-3.5, 0, -18.5), Vector3(3.2, 1.4, 3.0), 3.4, 4.0, 0.0)
	var c2: Crusher = _compactor(Vector3(-3.5, 0, -26.5), Vector3(3.2, 1.4, 3.0), 3.4, 4.0, 0.85)
	_ledge(Vector3(-3.5, 3.3, -37.2), Vector3(3.4, 8.0, 3.4))
	# RIGHT (teal): mantle the kiosk, run the blade sign, drop off its foot
	_ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 8.0, 3.2), "alt")
	kit.wallrun(_w(Vector3(6.5, 4.5, -24.7)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(3.8, 4.4, -36.0), 3.6, 4.0, "alt")
	var merge: Dictionary = _blk(Vector3(0, 5.0, -42.5), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 5.0, -52.0))
	deco.blade_sign(_w(Vector3(7.4, -2.0, -24.7)), 2.4, 14.0, deg_to_rad(_yaw) + PI * 0.5, TEAL, MAGENTA)
	_backing(Vector3(9.2, -10.0, -24.7), Vector3(3.0, 36.0, 18.0))
	# SHORTCUT: the alley wall - a wall-run panel along the belt's left, clear of the compactors'
	# frames; kick off its end straight onto the top of the mantle block
	kit.wallrun(_w(Vector3(-7.1, 2.0, -24.0)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	_backing(Vector3(-8.5, -10.0, -24.0), Vector3(2.0, 36.0, 18.0))
	_sign(Vector3(-3.5, 0, -6.6), AMBER)
	_sign(Vector3(4.0, 0, -6.6), TEAL)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), fork, Vector3(0, 0, 0.6))
	if route_variant == 2:
		r_walk(_w(Vector3(-3.5, 0, -9.0)))
		r_jump(_w(Vector3(-3.5, 0, -9.65)), _w(Vector3(-3.5, 0, -12.6)))
		r_wallrun(_w(Vector3(-4.1, 0, -13.6)), _w(Vector3(-6.5, 1.4, -18.6)), _w(Vector3(-6.5, 1.4, -29.4)), _w(Vector3(-3.5, 3.3, -36.7)))
		_hop(_area(Vector3(-3.5, 3.3, -37.2), 1.7, 1.7), merge, Vector3(-3.0, 0, 0.8))
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -9.0)))
		r_jump(_w(Vector3(-3.5, 0, -9.65)), _w(Vector3(-3.5, 0, -13.2)))
		_wait(func() -> bool: return _press_ok(c1, 0.1, 1.8) and _press_ok(c2, 0.6, 2.4), _w(Vector3(-3.5, 0, -13.4)))
		r_walk(_w(Vector3(-3.5, 0, -31.8)))
		r_mantle(_w(Vector3(-3.5, 0, -32.3)), _w(Vector3(-3.5, 3.3, -36.4)))
		_hop(_area(Vector3(-3.5, 3.3, -37.2), 1.7, 1.7), merge, Vector3(-3.0, 0, 0.8))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(4.3, 3.3, -14.85)), _w(Vector3(6.0, 4.7, -18.8)), _w(Vector3(6.0, 4.7, -29.7)), _w(Vector3(3.8, 4.4, -35.3)))
		_hop(l2, merge, Vector3(2.0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	deco.vent(_w(Vector3(-6.4, 0, -14.0)), 1.6, 6.0)
	deco.ac_unit(_w(Vector3(-6.0, 5.0, -42.0)), Vector3(1.6, 1.0, 1.4), 0.2)
	deco.water_tank(_w(Vector3(5.2, 5.0, -43.2)), 1.0, 2.0, 1.2)
	return cp["c"]


## A trash compactor: the crusher dressed as a ribbed steel ram with hazard chevrons.
func _compactor(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	var steel: StandardMaterial3D = Look.flat(Color(0.3, 0.3, 0.34), 0.35, 0.7)
	for i: int in 4:
		cr.add_child(Look.box(Vector3(size.x + 0.06, 0.1, 0.12), steel, Vector3(0, size.y * 0.5 + 0.05, -size.z * 0.5 + 0.4 + float(i) * (size.z - 0.8) / 3.0)))
	for sx: float in [-1.0, 1.0]:
		cr.add_child(Look.box(Vector3(0.05, size.y * 0.6, size.z * 0.9), Look.flat(AMBER, 0.4, 0.0, 1.6), Vector3(sx * (size.x * 0.5 + 0.03), 0, 0)))
	return cr


# ---- stage 10: SKYWAY - the hover-car lanes across the traffic canyon -------------------------------

var _l1: NeonTraffic
var _l2: NeonTraffic


func _stage_10() -> Vector3:
	# station A: a long platform beside the first lane
	_blk(Vector3(0.9, 0, -14.0), 3.4, 22.0, "main", 1.0)
	# the two lanes: each a rounded rectangle loop, riding straight down the station side. Lane 1
	# loops away to the right, lane 2 (4 m to the left of lane 1) away to the left; they run side by
	# side for 27 m (z -43..-70), their cars in step, so you can hop across between them.
	var f: Vector3 = _d(Vector3(0, 0, -1))
	_l1 = NeonTraffic.new()
	_l1.path = NeonTraffic.rect(_w(Vector3(4.2, 0, -10.0)), f, 60.0, 36.0, 1.0, 15.0, 10.0)
	_l1.speed = 7.0
	_l1.cars = 8
	_l1.offset = 0.0
	_l1.palette = PackedColorArray([MAGENTA, AMBER, TEAL])
	add_child(_l1)
	_l2 = NeonTraffic.new()
	_l2.path = NeonTraffic.rect(_w(Vector3(0.2, 0, -43.0)), f, 60.0, 36.0, -1.0, 15.0, 10.0)
	_l2.speed = 7.0
	_l2.cars = 8
	_l2.offset = -33.0
	_l2.palette = PackedColorArray([TEAL, VIOLET, MAGENTA])
	add_child(_l2)
	_lanes.append(_l1)
	_lanes.append(_l2)
	# station B beside lane 2, far down the canyon; the checkpoint just past it
	_blk(Vector3(3.6, 0, -97.0), 3.6, 20.0, "main", 1.0)
	var cp: Dictionary = _cp(Vector3(4.6, 0, -110.0))
	_station_dress(Vector3(0.9, 0, -14.0), 22.0, -1.0)
	_station_dress(Vector3(3.6, 0, -97.0), 20.0, 1.0)
	var o: Vector3 = _o
	var inv: Basis = _b.inverse()
	r_walk(_w(Vector3(1.2, 0, -8.0)))
	r_walk(_w(Vector3(2.2, 0, -14.0)))
	route.append({"kind": "candy_board", "from": _w(Vector3(2.2, 0, -14.0)), "cars": _l1.car_nodes, "reach": 2.4, "lead": 0.45, "local": Vector3(0, 0.1, 0.4)})
	route.append({"kind": "candy_ride", "stand": Vector3(-0.3, 0.1, 0.0), "cars": _l2.car_nodes, "local": Vector3(0, 0.1, 0.4), "until": func() -> bool:
		return (inv * (player.global_position - o)).z < -50.0})
	route.append({"kind": "candy_ride", "stand": Vector3(0.3, 0.1, 0.0), "to": _w(Vector3(3.6, 0, -100.5)), "until": func() -> bool:
		return (inv * (player.global_position - o)).z < -92.0})
	r_walk(_w(Vector3(4.2, 0, -104.0)))
	r_walk(_w(Vector3(4.6, 0, -110.0)))
	r_checkpoint()
	# the canyon: the towers either side, giant holo ads, traffic streaming far below
	for i: int in 4:
		var z: float = -20.0 - 22.0 * float(i)
		deco.billboard(_w(Vector3(-48.0, 10.0 + 4.0 * float(i % 2), z)), 14.0, 8.0, deg_to_rad(_yaw) + PI * 0.5, deco.pick_neon(), deco.pick_neon())
		deco.billboard(_w(Vector3(52.0, 6.0 + 4.0 * float(i % 2), z - 10.0)), 14.0, 8.0, deg_to_rad(_yaw) - PI * 0.5, deco.pick_neon(), deco.pick_neon())
	for k: int in 3:
		NeonFx.traffic_stream(self, _w(Vector3(-8.0 + 8.0 * float(k), -22.0 - 6.0 * float(k), -55.0)), _d(Vector3(0, 0, -1 if k % 2 == 0 else 1)), 120.0, 22.0, 26, k % 2 == 1)
	NeonFx.motes(self, _w(Vector3(2.0, 3.0, -55.0)), _sz(Vector3(8.0, 4.0, 40.0)), 80)
	return cp["c"]


## Station dressing: a canopy on posts along the platform's far side (`side` = which side of the
## platform the posts stand on, away from the lane), lamps and a strip sign.
func _station_dress(c: Vector3, length: float, side: float) -> void:
	var hx: float = 1.7
	var n: int = int(length / 5.0)
	var steel: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.15), 0.35, 0.7)
	for i: int in n + 1:
		var z: float = c.z + length * 0.5 - float(i) * length / float(n)
		add_child(Look.box(Vector3(0.14, 4.2, 0.14), steel, _w(Vector3(c.x + side * hx, c.y + 2.1, z))))
	var roof := Look.box(_sz(Vector3(1.6, 0.12, length)), Look.flat(Color(0.1, 0.1, 0.13), 0.3, 0.5), _w(Vector3(c.x + side * (hx - 0.7), c.y + 4.3, c.z)))
	add_child(roof)
	kit.glow_strip(_w(Vector3(c.x + side * (hx - 1.45), c.y + 4.22, c.z)), _sz(Vector3(0.1, 0.06, length)), TEAL)
	deco.strip_sign(_w(Vector3(c.x + side * (hx + 0.05), c.y + 3.2, c.z)), length * 0.6, 0.9, deg_to_rad(_yaw) + (PI * 0.5 if side < 0.0 else -PI * 0.5), MAGENTA, AMBER)
	for i: int in 3:
		kit.lamp(_w(Vector3(c.x + side * (hx - 0.2), c.y, c.z + length * 0.35 - float(i) * length * 0.35)), 2.8, i == 1, AMBER)


# ---- stage 11: Sign Chimney - an awning bounce up, three wall runs, out onto the top -----------------

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f: Dictionary = _blk(Vector3(0, 0, -9.6), 5.0, 6.0, "alt", 1.2)
	var padp := Vector3(0, 0, -10.6)
	kit.pad(_w(padp), 21.0, 0.0, 0.0, 1.2)
	_blk(Vector3(0, 6.0, -15.2), 3.0, 3.0, "main", 1.2, false)
	_chimney_panel(2.3, 7.2, -19.5, -26.0)
	_chimney_panel(-2.3, 12.0, -24.5, -32.5)
	_chimney_panel(2.3, 15.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 17.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 17.9, -51.2))
	_hop(cp0, f, Vector3(0, 0, 1.6))
	r_walk(_w(padp + Vector3(0, 0, 1.4)))
	r_pad(_w(padp), _w(Vector3(0, 6.0, -14.8)))
	r_walk(_w(Vector3(0, 6.0, -13.9)))
	r_wallrun(_w(Vector3(0.5, 6.0, -15.85)), _w(Vector3(1.7, 7.4, -20.6)), _w(Vector3(1.7, 7.4, -23.5)), _w(Vector3(-1.7, 11.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 11.5, -27.4)), _w(Vector3(-1.7, 11.5, -30.4)), _w(Vector3(1.7, 14.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 14.5, -34.0)), _w(Vector3(1.7, 14.5, -35.4)), _w(Vector3(-0.75, 17.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_awning(padp, AMBER)
	NeonFx.rain(self, _w(Vector3(0, 14.0, -28.0)), _sz(Vector3(3.0, 6.0, 10.0)), 120)
	NeonFx.motes(self, _w(Vector3(0, 12.0, -28.0)), _sz(Vector3(2.0, 6.0, 10.0)), 40)
	return cp["c"]


## A chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by a sign on its tower.
func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	_backing(Vector3(x + signf(x) * 1.1, y - 6.0, (z0 + z1) * 0.5), Vector3(1.6, height + 14.0, absf(z0 - z1) + 1.0))
	deco.strip_sign(_w(Vector3(x + signf(x) * 0.3, y + height * 0.5 + 0.7, (z0 + z1) * 0.5)), absf(z0 - z1) - 0.5, 0.8, deg_to_rad(_yaw) + (-PI * 0.5 if x > 0.0 else PI * 0.5), MAGENTA if x > 0.0 else TEAL, AMBER)


# ---- stage 12: Transit Gate (BRANCH) - holograms and a drone, or the kiosk's laser and portal ------

func _stage_12() -> Vector3:
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (violet): two holograms, a drone-swept roof
	var hx1: NeonHolo = _holo(Vector3(-3.5, 0, -15.5), 2.4, 5.0, 0.7, 0.0, VIOLET)
	var hx2: NeonHolo = _holo(Vector3(-3.5, 0.6, -21.5), 2.4, 5.0, 0.7, fposmod(-0.15, 1.0), MAGENTA)
	var lr: Dictionary = _blk(Vector3(-3.5, 1.2, -31.0), 3.0, 10.0, "alt")
	var dr: NeonDrone = _drone(Vector3(-12.0, 1.2, -31.0), Vector3(-1.0, 1.2, -31.0), 8.0, 0.3)
	var merge: Dictionary = _blk(Vector3(0, 1.2, -41.5), 12.0, 4.0)
	# RIGHT (amber): mantle the transit kiosk, beat its laser, take the portal
	_ledge(Vector3(4.0, 3.3, -14.0), Vector3(3.4, 8.0, 4.0), "alt")
	var gate: LaserGate = _beam(Vector3(4.0, 3.3, -14.4), 3.2, 4.5, 0.35, 0.2)
	var portal: WarpPortal = kit.portal(_w(Vector3(4.0, 3.3, -15.4)), _yaw, _w(Vector3(2.5, 1.2, -40.6)), _yaw, 7.0)
	_arrival(Vector3(2.5, 1.2, -41.2), AMBER)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -51.0))
	_sign(Vector3(-3.5, 0, -6.6), VIOLET)
	_sign(Vector3(4.0, 0, -6.6), AMBER)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.6)))
		_wait(func() -> bool: return _holo_ok(hx1, 0.3, 1.3 + 1.0) and _holo_ok(hx2, 1.0, 2.1 + 1.0))
		_hop(_area(Vector3(-3.5, 0, -8.0), 1.5, 2.0), _area(Vector3(-3.5, 0, -15.5), 1.2, 1.2))
		_hop(_area(Vector3(-3.5, 0, -15.5), 1.2, 1.2), _area(Vector3(-3.5, 0.6, -21.5), 1.2, 1.2))
		_hop(_area(Vector3(-3.5, 0.6, -21.5), 1.2, 1.2), lr, Vector3(0, 0, 3.5))
		var lane: Array = [_w(Vector3(-3.5, 1.2, -29.0)), _w(Vector3(-3.5, 1.2, -31.0)), _w(Vector3(-3.5, 1.2, -33.0))]
		_wait(func() -> bool: return dr.clear_of(lane, 0.7, 0.0, 2.2), _w(Vector3(-3.5, 1.2, -26.6)))
		r_walk(_w(Vector3(-3.5, 1.2, -35.6)))
		_hop(lr, merge, Vector3(-2.0, 0, 0.8))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		_wait(func() -> bool: return _dark(gate, 0.0, 2.6))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -12.6)))
		r_portal(_w(Vector3(4.0, 3.3, -15.6)), portal.exit_point())
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the transit kiosk: a lit canopy over the portal, ticket-machine glow
	deco.blade_sign(_w(Vector3(6.2, 3.3, -14.0)), 1.2, 4.0, deg_to_rad(_yaw), AMBER, TEAL)
	deco.billboard(_w(Vector3(-12.0, 9.0, -20.0)), 8.0, 4.5, deg_to_rad(_yaw) + PI * 0.5, VIOLET, MAGENTA)
	return cp["c"]


## A burst of neon sparks and mist where a portal lets you out (fired when you arrive).
func _arrival(at: Vector3, col: Color) -> void:
	var fx: Array[GPUParticles3D] = NeonFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(at + Vector3(0, 0.6, 0))
		add_child(p)
	_arrivals.append({"at": _w(at), "p": fx, "cool": 0.0})
	NeonFx.rising(self, _w(at), 1.2, 2.5, 14, col)


# ---- stage 13: Neon Rail - the boost rail into a long leap, two laser fences, mantle out -----------
# [shortcut: the side catwalk and the elevator portal]

func _stage_13() -> Vector3:
	kit.boost(_w(Vector3(0, 0, -8.0)), Vector3(2.6, 0.4, 10.0), _yaw, 18.0)
	kit.block(_w(Vector3(0, -0.6, -8.0)), _sz(Vector3(2.6, 0.8, 10.0)), Color(0.08, 0.06, 0.1), false)
	_neon_rail(Vector3(0, 0, -8.0), 10.0, 2.6, TEAL)
	_roofs.append({"top": _w(Vector3(0, -0.2, -8.0)), "size": _sz(Vector3(2.6, 0, 10.0)), "drop": 1.0})
	var r1: Dictionary = _blk(Vector3(0, 0, -30.0), 3.0, 16.0, "alt")
	var f1: LaserGate = _beam(Vector3(0, 0, -30.4), 3.0, 4.0, 0.35, 0.0)
	var f2: LaserGate = _beam(Vector3(0, 0, -34.6), 3.0, 4.0, 0.35, fposmod(-0.08, 1.0))
	_ledge(Vector3(0, 3.3, -41.2), Vector3(4.0, 8.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -50.5))
	# SHORTCUT: a side catwalk off the rail's landing, and the service elevator's portal on it
	var cw: Dictionary = _blk(Vector3(6.8, 0, -24.0), 1.6, 5.0, "accent", 0.6)
	var portal: WarpPortal = kit.portal(_w(Vector3(6.8, 0, -25.0)), _yaw, _w(Vector3(1.6, 3.3, -49.0)), _yaw, 6.0)
	_arrival(Vector3(1.6, 3.3, -49.6), TEAL)
	r_walk(_w(Vector3(0, 0, -3.5)))
	r_jump(_w(Vector3(0, 0, -12.65)), _w(Vector3(0, 0, -24.6)))
	route[route.size() - 1]["speed"] = 18.0
	if route_variant == 2:
		r_walk(_w(Vector3(0.6, 0, -22.6)))
		r_jump(_w(Vector3(1.15, 0, -22.6)), _w(Vector3(6.8, 0, -22.6)))
		r_portal(_w(Vector3(6.8, 0, -25.2)), portal.exit_point())
		r_walk(_w(Vector3(0.5, 3.3, -50.3)))
	else:
		r_walk(_w(Vector3(0, 0, -26.6)))
		_wait(func() -> bool: return _dark(f1, 0.05, 1.7) and _dark(f2, 0.4, 2.3), _w(Vector3(0, 0, -26.6)))
		r_walk(_w(Vector3(0, 0, -37.6)))
		r_mantle(_w(Vector3(0, 0, -37.65)), _w(Vector3(0, 3.3, -41.3)))
		_hop(_area(Vector3(0, 3.3, -41.2), 2.0, 1.7), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	deco.strip_sign(_w(Vector3(1.6, -0.8, -8.0)), 8.0, 1.0, deg_to_rad(_yaw) + PI * 0.5, TEAL, MAGENTA)
	deco.blade_sign(_w(Vector3(8.2, 0, -24.0)), 1.0, 3.6, deg_to_rad(_yaw) - PI * 0.5, AMBER, TEAL)
	deco.billboard(_w(Vector3(-9.0, 8.0, -24.0)), 10.0, 5.0, deg_to_rad(_yaw) + PI * 0.5, TEAL, AMBER)
	NeonFx.motes(self, _w(Vector3(0, 2.5, -22.0)), _sz(Vector3(3.0, 2.0, 12.0)), 40)
	r1.clear()
	cw.clear()
	return cp["c"]


# ---- stage 14: Billboard Carousel - ride the rotating rooftop billboard ------------------------------

func _stage_14() -> Vector3:
	var hub := Vector3(-3.0, 0, -13.0)
	var arms: Array[Dictionary] = [
		{"pos": Vector3(6.0, 0, 0), "size": Vector3(5.0, 0.5, 2.6)}, {"pos": Vector3(-6.0, 0, 0), "size": Vector3(5.0, 0.5, 2.6)},
		{"pos": Vector3(0, 0, 6.0), "size": Vector3(2.6, 0.5, 5.0)}, {"pos": Vector3(0, 0, -6.0), "size": Vector3(2.6, 0.5, 5.0)},
	]
	var dial: RotatingPlatform = kit.spinner(_w(hub), 7.0, arms, 2.4, 0.0, 0.5)
	_carousel_dress(dial, hub, arms)
	var m: Dictionary = _blk(Vector3(-3.0, 0.5, -26.0), 2.6, 2.6, "alt")
	var merge: Dictionary = _blk(Vector3(0, 0.5, -32.6), 14.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 0.5, -42.0))
	var tips: Array = [Vector3(7.0, 0.25, 0), Vector3(-7.0, 0.25, 0), Vector3(0, 0.25, 7.0), Vector3(0, 0.25, -7.0)]
	r_walk(_w(Vector3(-2.6, 0, -2.7)))
	route.append({"kind": "x_jump", "from": _w(Vector3(-2.6, 0, -2.7)), "to_node": dial, "to_locals": tips, "reach": 3.5, "lead": 0.55})
	var hw: Vector3 = _w(hub)
	var ex: Vector3 = _w(m["c"]) - hw
	ex = Vector3(ex.x, 0, ex.z).normalized()
	var sgn: float = signf(dial.period)
	route.append({"kind": "h_jump", "to": _w(m["c"]), "test": func() -> bool:
		var rel: Vector3 = player.global_position - hw
		rel = Vector3(rel.x, 0, rel.z).normalized()
		var a: float = rad_to_deg(atan2(rel.cross(ex).y, rel.dot(ex))) * sgn
		return a >= 8.0 and a <= 22.0})
	_hop(m, merge, Vector3(1.0, 0, 0.4))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	deco.vent(_w(Vector3(6.0, 0.5, -31.6)), 1.6, 6.0)
	deco.ac_unit(_w(Vector3(-6.0, 0.5, -33.0)), Vector3(1.6, 1.0, 1.4), 0.1)
	return cp["c"]


## The carousel: each arm carries a double-sided holo ad on a short mast, the hub a lit crown, and
## a ring of neon runs round the rooftop it turns over.
func _carousel_dress(dial: RotatingPlatform, hub: Vector3, arms: Array[Dictionary]) -> void:
	var cols: Array[Color] = [MAGENTA, TEAL, AMBER, VIOLET]
	for i: int in arms.size():
		var ap: Vector3 = arms[i]["pos"]
		var dir: Vector3 = ap.normalized()
		var at: Vector3 = dir * 8.2 + Vector3(0, 0.25, 0)
		var lamp := Look.sphere(0.22, Look.flat(cols[i], 0.3, 0.0, 4.0), at + Vector3(0, 0.25, 0))
		dial.add_child(lamp)
	dial.add_child(Look.cylinder(1.0, 1.2, Look.flat(Color(0.1, 0.1, 0.12), 0.3, 0.7), Vector3(0, 0.85, 0), 0.6, 16))
	var crown := Look.cylinder(0.65, 0.2, Look.flat(MAGENTA, 0.3, 0.0, 3.5), Vector3(0, 1.5, 0), -1.0, 16)
	dial.add_child(crown)
	var tm := TorusMesh.new()
	tm.inner_radius = 8.6
	tm.outer_radius = 8.9
	tm.rings = 64
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, Look.flat(TEAL, 0.3, 0.0, 2.5), _w(hub + Vector3(0, -1.2, 0)))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_pylon(_w(hub + Vector3(0, -0.6, 0)), 1.2)
	deco.billboard(_w(hub + Vector3(0, 9.0, -11.0)), 12.0, 6.0, deg_to_rad(_yaw), MAGENTA, TEAL)
	_keep_out.append(Vector4(_w(hub).x, _w(hub).y, _w(hub).z, 10.0))


# ---- stage 15: Drone Ledge - a narrow ledge round the tower under two drones, mantle out ------------
# [shortcut: a max-height mantle up the service pillar]

func _stage_15() -> Vector3:
	var walk: Dictionary = _blk(Vector3(0, 0, -16.0), 2.2, 24.0, "alt", 0.8)
	var d1: NeonDrone = _drone(Vector3(0, 0, -10.0), Vector3(9.0, 0, -10.0), 7.0, 0.0, 7.0)
	var d2: NeonDrone = _drone(Vector3(0, 0, -20.0), Vector3(9.0, 0, -20.0), 7.0, 0.5, 7.0)
	_ledge(Vector3(0, 3.3, -31.7), Vector3(3.0, 8.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -41.1))
	# the tower wall the ledge clings to (on its left)
	_backing(Vector3(-5.6, -6.0, -16.0), Vector3(4.0, 40.0, 26.0))
	# SHORTCUT: the service pillar - a near-maximum mantle beside the start, then the cable duct
	# along the wall (a 0.9 m beam, just outside the searchlights' reach) to the mantle block's top
	var pil: Dictionary = _ledge(Vector3(-2.4, 4.1, -5.2), Vector3(1.4, 12.0, 1.6), "accent")
	var duct: Dictionary = _blk(Vector3(-2.4, 4.1, -18.2), 0.9, 24.4, "accent", 0.4)
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -5.4)))
	if route_variant == 2:
		r_walk(_w(Vector3(-0.5, 0, -5.2)))
		r_mantle(_w(Vector3(-0.75, 0, -5.2)), _w(Vector3(-2.4, 4.1, -5.3)))
		r_walk(_w(Vector3(-2.4, 4.1, -7.0)))
		r_walk(_w(Vector3(-2.4, 4.1, -29.8)))
		r_jump(_w(Vector3(-2.4, 4.1, -30.0)), _w(Vector3(-0.3, 3.3, -32.0)))
		_hop(_area(Vector3(0, 3.3, -31.7), 1.5, 1.7), cp, Vector3(0, 0, 1.5))
	else:
		r_walk(_w(Vector3(0, 0, -6.4)))
		var p1: Array = [_w(Vector3(0, 0, -8.6)), _w(Vector3(0, 0, -10.0)), _w(Vector3(0, 0, -11.4))]
		_wait(func() -> bool: return d1.clear_of(p1, 0.6, 0.0, 2.2), _w(Vector3(0, 0, -6.4)))
		r_walk(_w(Vector3(0, 0, -15.0)))
		var p2: Array = [_w(Vector3(0, 0, -18.6)), _w(Vector3(0, 0, -20.0)), _w(Vector3(0, 0, -21.4))]
		_wait(func() -> bool: return d2.clear_of(p2, 0.6, 0.0, 2.2), _w(Vector3(0, 0, -15.0)))
		r_walk(_w(Vector3(0, 0, -27.6)))
		r_mantle(_w(Vector3(0, 0, -27.65)), _w(Vector3(0, 3.3, -31.6)))
		_hop(_area(Vector3(0, 3.3, -31.7), 1.5, 1.7), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	deco.strip_sign(_w(Vector3(-3.55, 2.2, -14.0)), 9.0, 1.0, deg_to_rad(_yaw) + PI * 0.5, MAGENTA, TEAL)
	deco.blade_sign(_w(Vector3(-2.8, 9.0, -24.0)), 1.4, 7.0, deg_to_rad(_yaw), AMBER, VIOLET)
	walk.clear()
	pil.clear()
	duct.clear()
	return cp["c"]


# ---- stage 16: Express Lane - board a hover car on the climbing lane -------------------------------

var _express: NeonTraffic


func _stage_16() -> Vector3:
	_blk(Vector3(0.9, 0, -11.5), 3.4, 17.0, "main", 1.0)
	_express = NeonTraffic.new()
	_express.path = _express_path()
	_express.speed = 7.5
	_express.cars = 7
	_express.offset = 0.0
	_express.palette = PackedColorArray([AMBER, MAGENTA, TEAL])
	add_child(_express)
	_lanes.append(_express)
	_blk(Vector3(0.9, 12.0, -67.0), 3.4, 16.0, "main", 1.0)
	var cp: Dictionary = _cp(Vector3(1.6, 12.0, -78.0))
	_station_dress(Vector3(0.9, 0, -11.5), 17.0, -1.0)
	_station_dress(Vector3(0.9, 12.0, -67.0), 16.0, -1.0)
	var o: Vector3 = _o
	var inv: Basis = _b.inverse()
	r_walk(_w(Vector3(1.2, 0, -8.0)))
	r_walk(_w(Vector3(2.2, 0, -12.0)))
	route.append({"kind": "candy_board", "from": _w(Vector3(2.2, 0, -12.0)), "cars": _express.car_nodes, "reach": 2.4, "lead": 0.45, "local": Vector3(0, 0.1, 0.4)})
	route.append({"kind": "candy_ride", "stand": Vector3(-0.3, 0.1, 0.0), "to": _w(Vector3(1.2, 12.0, -67.0)), "until": func() -> bool:
		return (inv * (player.global_position - o)).z < -62.0})
	r_walk(_w(Vector3(1.6, 12.0, -74.0)))
	r_walk(_w(Vector3(1.6, 12.0, -78.0)))
	r_checkpoint()
	# the express rises along the tower face: lit windows, a giant blade sign, a holo ad
	_backing(Vector3(-6.0, -10.0, -36.0), Vector3(6.0, 60.0, 50.0))
	deco.blade_sign(_w(Vector3(-2.8, 2.0, -30.0)), 2.6, 16.0, deg_to_rad(_yaw) + PI * 0.5, MAGENTA, AMBER)
	deco.billboard(_w(Vector3(-3.0, 18.0, -50.0)), 10.0, 5.0, deg_to_rad(_yaw) + PI * 0.5, TEAL, VIOLET)
	NeonFx.motes(self, _w(Vector3(4.0, 7.0, -36.0)), _sz(Vector3(4.0, 7.0, 30.0)), 60)
	return cp["c"]


## The express lane's loop (world): the climbing ride straight past both stations, then on up to
## 30 m before it swings round (high over the next stage), the long descent back on the far side and
## the low turn back to the start - clear of every roof.
func _express_path() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var a := Vector3(4.2, 0, -6.0)
	var b := Vector3(4.2, 12.0, -66.0)
	var c := Vector3(4.2, 30.0, -84.0)
	var r: float = 12.0
	var step: float = 0.5
	var n: int = int(a.distance_to(b) / step)
	for i: int in n:
		pts.append(_w(a.lerp(b, float(i) / float(n))))
	# ease up into the climb so the turn from level-ish to steep is smooth
	var n2: int = int(b.distance_to(c) / step)
	for i: int in n2:
		var k: float = float(i) / float(n2)
		pts.append(_w(Vector3(4.2, lerpf(b.y, c.y, k * k * (3.0 - 2.0 * k)), lerpf(b.z, c.z, k))))
	# the high turn to the right
	var c1 := Vector3(4.2 + r, c.y, c.z)
	var na: int = int(PI * r / step)
	for i: int in na:
		var ang: float = PI * float(i) / float(na)
		pts.append(_w(c1 + Vector3(-r * cos(ang), 0, -r * sin(ang))))
	# the long descent home on the far side
	var rb := Vector3(4.2 + 2.0 * r, c.y, c.z)
	var ra := Vector3(4.2 + 2.0 * r, 0.0, a.z)
	var n3: int = int(rb.distance_to(ra) / step)
	for i: int in n3:
		var k2: float = float(i) / float(n3)
		var e: float = k2 * k2 * (3.0 - 2.0 * k2)
		pts.append(_w(Vector3(rb.x, lerpf(rb.y, ra.y, e), lerpf(rb.z, ra.z, k2))))
	# the low turn back onto the ride
	var c2 := Vector3(4.2 + r, 0.0, a.z)
	for i: int in na:
		var ang2: float = PI * float(i) / float(na)
		pts.append(_w(c2 + Vector3(r * cos(ang2), 0, r * sin(ang2))))
	return pts


# ---- stage 17: The Crown - two mantles, the crown compactor, two holograms --------------------------

func _stage_17() -> Vector3:
	_ledge(Vector3(0, 3.3, -7.2), Vector3(6.0, 8.0, 3.4))
	_ledge(Vector3(0, 6.6, -10.6), Vector3(4.5, 11.0, 3.4), "alt")
	var walk: Dictionary = _blk(Vector3(0, 6.6, -18.4), 2.6, 8.0, "alt")
	var press: Crusher = _compactor(Vector3(0, 6.6, -18.4), Vector3(3.0, 1.2, 2.6), 3.4, 4.2, 0.0)
	var h1: NeonHolo = _holo(Vector3(0, 7.2, -26.8), 2.4, 5.0, 0.7, 0.0, MAGENTA)
	var h2: NeonHolo = _holo(Vector3(0, 7.8, -32.6), 2.4, 5.0, 0.7, fposmod(-0.15, 1.0), TEAL)
	var cp: Dictionary = _cp(Vector3(0, 7.8, -41.4))
	# SHORTCUT: the crown's flank - a wall-run panel outside the compactor's frame, kick off onto
	# the first hologram
	kit.wallrun(_w(Vector3(3.8, 8.4, -19.0)), Vector3(12.0, 6.5, 0.6), _yaw + 90.0)
	_backing(Vector3(5.2, 0.0, -19.0), Vector3(2.0, 24.0, 14.0))
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -7.4)))
	r_mantle(_w(Vector3(0, 3.3, -8.55)), _w(Vector3(0, 6.6, -10.8)))
	if route_variant == 2:
		r_walk(_w(Vector3(1.2, 6.6, -11.0)))
		_wait(func() -> bool: return _holo_ok(h1, 1.2, 2.2 + 1.0) and _holo_ok(h2, 1.9, 3.0 + 1.0))
		r_wallrun(_w(Vector3(1.6, 6.6, -11.95)), _w(Vector3(3.3, 8.0, -15.8)), _w(Vector3(3.3, 8.0, -22.6)), _w(Vector3(0, 7.2, -26.8)))
	else:
		_hop(_area(Vector3(0, 6.6, -10.6), 2.25, 1.7), walk, Vector3(0, 0, 2.2))
		_wait(func() -> bool: return _press_ok(press, 0.1, 1.9), _w(Vector3(0, 6.6, -15.4)))
		r_walk(_w(Vector3(0, 6.6, -21.9)))
		_wait(func() -> bool: return _holo_ok(h1, 0.2, 1.2 + 1.0) and _holo_ok(h2, 0.9, 2.0 + 1.0))
		_hop(walk, _area(Vector3(0, 7.2, -26.8), 1.2, 1.2))
	_hop(_area(Vector3(0, 7.2, -26.8), 1.2, 1.2), _area(Vector3(0, 7.8, -32.6), 1.2, 1.2))
	_hop(_area(Vector3(0, 7.8, -32.6), 1.2, 1.2), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	deco.antenna(_w(Vector3(-2.6, 6.6, -12.0)), 6.0)
	deco.dish(_w(Vector3(1.8, 6.6, -11.6)), 0.8, 1.0)
	deco.billboard(_w(Vector3(10.0, 14.0, -30.0)), 9.0, 5.0, deg_to_rad(_yaw) - PI * 0.5, AMBER, MAGENTA)
	return cp["c"]


# ---- stage 18: Antenna Spire - wall run the spire's fin, mantle onto the antenna deck, finish -------

var _spire_light: OmniLight3D


func _stage_18() -> void:
	var s1: Dictionary = _blk(Vector3(0.2, 0.6, -8.2), 3.0, 3.0, "alt")
	kit.wallrun(_w(Vector3(2.5, 1.8, -19.3)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var s2: Dictionary = _blk(Vector3(-0.2, 0.6, -32.3), 3.6, 5.0, "alt")
	_ledge(Vector3(0, 3.9, -39.0), Vector3(4.0, 10.0, 3.4))
	var deck: Dictionary = _disc(Vector3(0, 3.9, -47.4), 4.2, "main", 1.2)
	kit.finish(_w(Vector3(0, 3.9, -48.0)), _yaw)
	_finish_pos = _w(Vector3(0, 3.9, -48.0))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), s1)
	r_wallrun(_w(Vector3(0.5, 0.6, -9.35)), _w(Vector3(2.0, 2.0, -13.4)), _w(Vector3(2.0, 2.0, -24.3)), _w(Vector3(-0.2, 0.6, -31.6)))
	r_walk(_w(Vector3(0, 0.6, -34.2)))
	r_mantle(_w(Vector3(0, 0.6, -34.45)), _w(Vector3(0, 3.9, -39.2)))
	_hop(_area(Vector3(0, 3.9, -39.0), 2.0, 1.7), deck, Vector3(0, 0, 0.0))
	r_walk(_w(Vector3(0, 3.9, -48.2)))
	# the spire: a needle mast above the deck, its fin the wall run, warning lights all the way up
	deco.blade_sign(_w(Vector3(3.6, -5.0, -19.3)), 3.0, 16.0, deg_to_rad(_yaw) + PI * 0.5, MAGENTA, AMBER)
	_backing(Vector3(5.4, -12.0, -19.3), Vector3(2.6, 40.0, 18.0))
	var mast_base: Vector3 = _w(Vector3(0, 3.9, -53.0))
	var steel: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.18), 0.3, 0.8)
	add_child(Look.cylinder(0.9, 40.0, steel, mast_base + Vector3(0, 20.0, 0), 0.25, 12))
	for i: int in 8:
		var y: float = 3.0 + float(i) * 4.8
		var lamp := Look.sphere(0.22, Look.flat(RED, 0.3, 0.0, 6.0), mast_base + Vector3(0, y, 0.6))
		lamp.set_script(preload("res://visual/neon_blink.gd"))
		lamp.set("period", 1.2)
		add_child(lamp)
		var ring := Look.cylinder(0.95 - float(i) * 0.08, 0.15, Look.flat([MAGENTA, TEAL, AMBER][i % 3], 0.3, 0.0, 3.0), mast_base + Vector3(0, y + 1.2, 0), -1.0, 12)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
	_spire_light = OmniLight3D.new()
	_spire_light.light_color = MAGENTA
	_spire_light.light_energy = 2.0
	_spire_light.omni_range = 14.0
	_spire_light.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(_spire_light)
	NeonFx.rising(self, _w(Vector3(0, 3.95, -47.4)), 3.6, 6.0, 40, MAGENTA)
	deck.clear()
	s1.clear()
	s2.clear()


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
	_env.sky = NeonSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.38, 0.62)
	_env.ambient_light_energy = 0.55
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.1
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.3, 0.12, 0.26)
	_env.fog_density = 0.0042
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.2
	_env.fog_sun_scatter = 0.0
	_env.fog_height = STREET_Y + 30.0
	_env.fog_height_density = 0.03
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.25
	_env.adjustment_contrast = 1.1
	# wet roofs: screen-space reflections on the higher quality settings
	if int(Settings.quality) >= 2:
		_env.ssr_enabled = true
		_env.ssr_max_steps = 48
		_env.ssr_fade_in = 0.2
		_env.ssr_fade_out = 2.0
		_env.ssr_depth_tolerance = 0.3
	# no sun: a dim violet moonlight through the cloud, and a warm amber bounce off the street
	_sun.light_color = Color(0.62, 0.5, 0.9)
	_sun.light_energy = 0.55
	_sun.rotation_degrees = Vector3(-55, 135, 0)
	_sun.shadow_blur = 2.0
	_fill.light_color = Color(1.0, 0.55, 0.3)
	_fill.light_energy = 0.35
	_fill.rotation_degrees = Vector3(35, -45, 0)


## Swap every walkable surface to the wet-roof shader (same colours).
func _neon_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = preload("res://visual/neon_roof.gdshader")
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


## Every point the route passes (takeoffs, landings, walk targets) - set dressing keeps clear of them.
func _route_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for st: Dictionary in route:
		for key: String in ["from", "to", "entry", "exit", "top"]:
			if st.has(key) and st[key] is Vector3 and (st[key] as Vector3) != Vector3.ZERO:
				pts.append(st[key])
	for p: Vector3 in _cp_world:
		pts.append(p)
	for r: Dictionary in _roofs:
		pts.append(r["top"])
	return pts


func _clear_of(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist:
			return false
	for k: Vector4 in _keep_out:
		if Vector2(p.x - k.x, p.z - k.z).length() < k.w + dist * 0.5:
			return false
	return true


func _surroundings() -> void:
	var pts: Array[Vector3] = _route_points()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p: Vector3 in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid: Vector3 = (lo + hi) * 0.5
	var span: Vector3 = hi - lo
	var rng: RandomNumberGenerator = kit.rng
	# the traffic loops are part of the course too: keep the city off the lanes
	for t: NeonTraffic in _lanes:
		for i: int in range(0, t.path.size(), 12):
			var q: Vector3 = t.path[i]
			_keep_out.append(Vector4(q.x, q.y, q.z, 7.0))
	# towers under every roof (pylons under the small ones)
	for r: Dictionary in _roofs:
		var top: Vector3 = r["top"]
		var s: Vector3 = r["size"]
		var drop: float = float(r["drop"])
		if minf(s.x, s.z) >= 4.5:
			deco.tower(top, Vector2(s.x, s.z), STREET_Y, 0.0, drop)
		elif maxf(s.x, s.z) >= 8.0:
			# a long narrow walk: a pylon every 8 m
			var along_x: bool = s.x > s.z
			var n: int = int(maxf(s.x, s.z) / 8.0) + 1
			for i: int in n:
				var k: float = -0.5 + (float(i) + 0.5) / float(n)
				var off: Vector3 = Vector3(k * s.x, 0, 0) if along_x else Vector3(0, 0, k * s.z)
				_pylon(top + off - Vector3(0, drop, 0), 0.3)
		else:
			_pylon(top - Vector3(0, drop, 0), minf(s.x, s.z) * 0.22)
	# the street canyon far below and its haze
	deco.street(Vector3(mid.x, 0, mid.z), maxf(span.x, span.z) * 0.5 + 300.0, STREET_Y)
	NeonFx.haze(self, Vector3(mid.x, STREET_Y + 12.0, mid.z), Vector3(span.x * 0.5 + 60.0, 8.0, span.z * 0.5 + 60.0), 40)
	# the city round the course: mid-distance towers with rooftop clutter and signs
	var placed: int = 0
	var tries: int = 0
	while placed < 70 and tries < 900:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 90.0, hi.x + 90.0), 0, rng.randf_range(lo.z - 90.0, hi.z + 90.0))
		var w: float = rng.randf_range(10.0, 22.0)
		var d: float = rng.randf_range(10.0, 22.0)
		if not _clear_of(p, pts, maxf(w, d) * 0.5 + 14.0):
			continue
		var h: float = rng.randf_range(lo.y + 10.0, hi.y + 50.0) - STREET_Y
		var top := Vector3(p.x, STREET_Y + h, p.z)
		var mi := Look.box(Vector3(w, h, d), NeonDecor.facade(0.36, 1.6), Vector3(p.x, STREET_Y + h * 0.5, p.z))
		add_child(mi)
		var roll: float = rng.randf()
		if roll < 0.35:
			deco.water_tank(top + Vector3(rng.randf_range(-w, w) * 0.3, 0, rng.randf_range(-d, d) * 0.3), rng.randf_range(1.2, 2.2), rng.randf_range(2.0, 3.5), 1.8)
		elif roll < 0.6:
			deco.antenna(top + Vector3(rng.randf_range(-w, w) * 0.3, 0, rng.randf_range(-d, d) * 0.3), rng.randf_range(5.0, 12.0))
		if rng.randf() < 0.55:
			# a blade sign down one corner
			var face: int = rng.randi() % 4
			var yaw: float = PI * 0.5 * float(face)
			var out: Vector3 = Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
			var half: float = (d if face % 2 == 0 else w) * 0.5
			var side: Vector3 = Basis(Vector3.UP, yaw) * Vector3(1, 0, 0) * ((w if face % 2 == 0 else d) * 0.5 - 1.5)
			deco.blade_sign(Vector3(p.x, top.y - rng.randf_range(14.0, 30.0), p.z) + out * (half + 1.4) + side, rng.randf_range(2.0, 3.4), rng.randf_range(10.0, 20.0), yaw + PI * 0.5, deco.pick_neon(), deco.pick_neon(), false)
		elif rng.randf() < 0.5:
			var face2: int = rng.randi() % 4
			var yaw2: float = PI * 0.5 * float(face2)
			var out2: Vector3 = Basis(Vector3.UP, yaw2) * Vector3(0, 0, 1)
			var half2: float = (d if face2 % 2 == 0 else w) * 0.5
			deco.billboard(Vector3(p.x, top.y - rng.randf_range(4.0, 14.0), p.z) + out2 * (half2 + 0.6), minf(w, d) * 0.8, minf(w, d) * 0.45, yaw2, deco.pick_neon(), deco.pick_neon(), false)
		_keep_out.append(Vector4(p.x, 0, p.z, maxf(w, d) * 0.6))
		placed += 1
	# the far skyline, as one MultiMesh, and giant holograms between the far towers
	var center := Vector3(mid.x, 0, mid.z)
	var r0: float = maxf(span.x, span.z) * 0.5 + 110.0
	deco.skyline(center, r0, r0 + 260.0, 170, STREET_Y, func(q: Vector3, rad: float) -> bool: return _clear_of(q, pts, rad + 20.0))
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0 + rng.randf_range(-0.2, 0.2)
		var rr: float = r0 + rng.randf_range(20.0, 120.0)
		var at := Vector3(mid.x + cos(a) * rr, rng.randf_range(lo.y + 20.0, hi.y + 60.0), mid.z + sin(a) * rr)
		deco.mega_billboard(at, rng.randf_range(30.0, 55.0), rng.randf_range(18.0, 30.0), atan2(mid.x - at.x, mid.z - at.z))
	# far traffic: streams of light flowing between the towers at several heights
	for i: int in 14:
		var a2: float = rng.randf() * TAU
		var rr2: float = rng.randf_range(60.0, r0 + 40.0)
		var c2 := Vector3(mid.x + cos(a2) * rr2, rng.randf_range(STREET_Y + 10.0, hi.y + 30.0), mid.z + sin(a2) * rr2)
		var dir := Vector3(-sin(a2), 0, cos(a2))
		NeonFx.traffic_stream(self, c2, dir, rng.randf_range(120.0, 220.0), rng.randf_range(18.0, 30.0), 20, i % 2 == 0)
	# ambient life along the whole route: rain curtains, splashes on the roofs, neon motes, steam
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 6.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 10.0, 7.0, absf(here.z - prev.z) * 0.5 + 10.0)
		NeonFx.rain(self, c3 + Vector3(0, 4.0, 0), ext, 160)
		NeonFx.motes(self, c3, ext * 0.8, 30)
	for r2: Dictionary in _roofs:
		var s2: Vector3 = r2["size"]
		var area: float = s2.x * s2.z
		if area >= 9.0:
			NeonFx.splashes(self, r2["top"], Vector2(s2.x * 0.45, s2.z * 0.45), clampi(int(area * 0.5), 6, 40))


# ---- live effects -----------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null:
		return
	for e: Dictionary in _arrivals:
		e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
		if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
			e["cool"] = 3.0
			for p: GPUParticles3D in e["p"]:
				p.restart()
				p.emitting = true


## The summit goes off: neon fireworks over the spire, sparks off the deck, the mast lights up.
func _finish_sequence() -> void:
	var cols: Array[Color] = [Fx.hot(MAGENTA, 2.6), Fx.hot(TEAL, 2.6), Fx.hot(AMBER, 2.6), Fx.hot(VIOLET, 2.6)]
	for i: int in 6:
		var fw: GPUParticles3D = NeonFx.firework(cols[i % cols.size()], 90)
		fw.position = _finish_pos + Vector3(-10.0 + 4.0 * float(i), 14.0 + float(i % 2) * 5.0, -8.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	var fx: Array[GPUParticles3D] = NeonFx.cp_burst(MAGENTA)
	for p: GPUParticles3D in fx:
		p.position = _finish_pos + Vector3(0, 0.6, 0)
		add_child(p)
		p.restart()
		p.emitting = true
	# SOUND: neon_finish - fireworks crackling over the spire and the city's sirens answering
	WorldAudio.at(self, "neon_finish", _finish_pos + Vector3(0, 10.0, -8.0), 1.0, 120.0)
	if _spire_light != null:
		var tw: Tween = create_tween()
		_spire_light.light_energy = 9.0
		tw.tween_property(_spire_light, "light_energy", 2.0, 1.6)
	await get_tree().create_timer(0.9).timeout
