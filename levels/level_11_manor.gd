extends LevelBase
## 11. PHANTOM MANOR - a haunted gothic mansion and its graveyard on a cliff, at midnight under a
## huge blood moon. Eighteen stages, each ending on a checkpoint: in through the lychgate over the
## graves floating in the valley fog (leaning tombstones, mausoleums, dead trees, will-o'-wisps,
## a hedge maze), up the cliff stair to the manor's porch, then through the house - foyer,
## library, portrait gallery, dining hall, chapel, the grand ballroom, the hall of mirrors, the
## servants' stair and the attic - out across the rooftops and up the bell tower to the belfry.
## The fog reddens and the moonlight strengthens as you climb.
##
##  1 Lychgate        grave slabs and plinths over the misty valley, two patches of ROTTEN BOARDS
##                    [shortcut: MANTLE the weeping angel's plinth, leap to the crypt roof]
##  2 Mausoleum Row   MANTLE the crypt, grave plinths, WALL RUN the great mausoleum's flank
##  3 Hedge Maze      BRANCH: ride two POSSESSED COFFINS ferrying over the sunken graves | MANTLE
##                    the clipped yew and WALL RUN the hedge
##  4 Open Graves     two COFFIN LIDS that slam shut (CRUSHERS), rotten boards, a spectral
##                    tripwire (LASER)
##  5 Dead Orchard    board the GIBBET CAGE as it hangs still, swing across the ravine, a grave
##                    pad up the bank  [shortcut: two rotten stumps beside the cage's path]
##  6 Cliff Stair     three MANTLES up the cliff past a tripwire (LASER), the suit of armour's
##                    lance (PISTON) across the terrace, the manor's porch
##  7 The Foyer       BRANCH: PHANTOM FURNITURE (table, armoire, piano, chest) phasing in and out
##                    over the fallen floor | two MANTLES up the grand stair, rotten balcony boards
##  8 The Library     rotten boards, MANTLE the bookcase, WALL RUN the towering shelves
##                    [shortcut: ride a possessed bookcase the length of the library]
##  9 Portrait Gallery the ancestors' GAZE sweeps the gallery whenever their eyes open - cross
##                    while they are shut  [shortcut: MANTLE the sideboard, step through its
##                    MIRROR (PORTAL) to the far end]
## 10 Dining Hall     along the table: a carousel of possessed chairs (SWEEPER) whirling across it -
##                    run behind a row as it sweeps past - a candle tripwire (LASER), the armoire's
##                    ram (PISTON)
## 11 The Chapel      PHANTOM PEWS over the crypt, a COFFIN LID (CRUSHER) in the nave, MANTLE the altar
## 12 THE GRAND BALLROOM  ride a WALTZING GHOST COUPLE round the fallen dance floor, then the
##                    GREAT CHANDELIER on 16 m of chain across the hall
##                    [shortcut: MANTLE the musicians' ledge, WALL RUN the mirrored wall]
## 13 Hall of Mirrors BRANCH: step into the looking glass (PORTAL) and out high on the gallery |
##                    climb the MIRROR CHIMNEY - three chained WALL RUNS
## 14 Servants' Stair ride two haunted TRUNKS up the stairwell over the rotten stairs, MANTLE out
## 15 The Attic       rotten boards, a portrait's GAZE across the floor, bobbing trunks
##                    [shortcut: MANTLE onto a rafter and walk it over the gaze]
## 16 The Rooftops    along the slate ridge, WALL RUN the chimney stack, a gargoyle pad up
## 17 Bell Tower      MANTLES up the buttresses, slip past the SWINGING BELL (a pendulum that hurls you)
## 18 The Belfry      phantom slabs round the spire, the tripwire, the last WALL RUN, MANTLE onto
##                    the belfry dais - the finish under the great bell and the blood moon
##
## Manor mechanics (own scripts): ManorPhantom (phantom furniture, solid only while its ghost
## lantern burns), ManorGaze (a portrait's sweeping gaze beam), ManorChandelier (swinging rides:
## the gibbet cage and the great chandelier), ManorPossessed (possessed furniture and the waltzing
## couples, moving platforms), ManorFloorboards (rotten boards). Route variants for the bot:
## 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut.

const SURFACE_SHADER: Shader = preload("res://visual/manor_stone.gdshader")

const ECTO := Color(0.55, 1.0, 0.6)
const VIOLET := Color(0.7, 0.4, 1.0)
const BLOOD := Color(1.0, 0.25, 0.22)
const CANDLE := Color(1.0, 0.72, 0.4)
## Where the blood moon hangs (the key light comes from here).
const MOON_DIR := Vector3(0.28, 0.3, -0.91)

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: ManorDecor
var _env: Environment
var _moon: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_nodes: Array[Checkpoint] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Which stages are indoors (their floors become oak boards), by stage number.
var _indoor: Dictionary = {}
var _stage_no: int = 0
## Bursts that fire when the player arrives at a spot (mirror exits): {"at", "p": [GPUParticles3D], "cool"}
var _arrivals: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "manor"
	music_track = "manor"
	kill_y = -40.0
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


func _ry() -> float:
	return deg_to_rad(_yaw)


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## A walkable block with a masonry foundation under it (down into the fog, outdoors).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, pier: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if pier:
		_pier(c - Vector3(0, thick, 0), sx * 0.75, sz * 0.75)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A round landing (a grave plinth / a stump top) on a slimmer column.
func _drum(c: Vector3, r: float, style: String = "main", thick: float = 0.8, pier: bool = true) -> Dictionary:
	var body: StaticBody3D = kit.disc(_w(c), r, thick, style, 0.0)
	if pier:
		var h: float = clampf(_w(c).y + 30.0, 6.0, 60.0)
		add_child(Look.cylinder(r * 0.72, h, deco.stone(ManorDecor.STONE_DARK), _w(c - Vector3(0, thick + h * 0.5, 0)), r * 0.8, 12))
	return {"c": c, "r": r, "node": body}


## Masonry pier under a landing, down into the fog of the valley (decor, no collision).
func _pier(top: Vector3, sx: float, sz: float) -> void:
	var h: float = clampf(_w(top).y + 30.0, 4.0, 60.0)
	var size := Vector3(maxf(sx, 0.5), h, maxf(sz, 0.5))
	var p := Look.box(size, deco.stone(ManorDecor.STONE_DARK.lightened(0.04)), _w(top - Vector3(0, h * 0.5, 0)))
	p.rotation.y = _ry()
	add_child(p)


## A floating clod of graveyard earth with a headstone on it (decor, off the route).
func _isle(c: Vector3, s: float = 1.0) -> void:
	var size := Vector3(3.0, 0.8, 2.6) * s
	var earth := Look.box(size, Look.flat(Color(0.11, 0.09, 0.1), 1.0), _w(c) - Vector3(0, size.y * 0.5, 0))
	earth.rotation.y = _ry() + kit.rng.randf_range(-0.5, 0.5)
	earth.add_child(Look.underside(size, 2.8 * s, false))
	add_child(earth)
	deco.tombstone(_w(c + Vector3(kit.rng.randf_range(-0.5, 0.5), 0, 0)), _ry() + kit.rng.randf_range(-0.3, 0.3), -1, 1.1 * s)
	if kit.rng.randf() < 0.5:
		deco.candelabra(_w(c + Vector3(1.0 * s, 0, 0.6 * s)), 0.3, false, ECTO)


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
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


## Rotten floorboards over a hole, top centre at local `c`.
func _boards(c: Vector3, sx: float, sz: float, delay: float = 0.9, respawn_s: float = 3.0) -> Dictionary:
	var fb := ManorFloorboards.new()
	fb.size = _sz(Vector3(sx, 0.4, sz))
	fb.delay = delay
	fb.respawn = respawn_s
	fb.position = _w(c) - Vector3(0, 0.2, 0)
	add_child(fb)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5, "node": fb}


## Phantom furniture whose top is at local `top`.
func _phantom(top: Vector3, sx: float, sz: float, kind: String, period: float, on: float, phase: float, lantern: bool = true) -> ManorPhantom:
	var p := ManorPhantom.new()
	p.size = Vector3(sx, 0.5, sz)
	p.kind = kind
	p.period = period
	p.on_fraction = on
	p.phase = phase
	p.lantern = lantern
	p.rotation.y = _ry()
	p.position = _w(top) - Vector3(0, 0.25, 0)
	add_child(p)
	return p


## Possessed furniture on a path (local offsets `pts` from local top `top`).
func _possessed(top: Vector3, size: Vector3, kind: String, pts: Array[Vector3], period: float, phase: float = 0.0, dwell: float = 0.2) -> ManorPossessed:
	var m := ManorPossessed.new()
	m.kind = kind
	m.size = size
	var wp: Array[Vector3] = []
	for p: Vector3 in pts:
		wp.append(_b * p)
	m.points = wp
	m.period = period
	m.phase = phase
	m.dwell = dwell
	m.rotation.y = _ry()
	m.position = _w(top) - Vector3(0, size.y * 0.5, 0)
	add_child(m)
	return m


## A swing ride hung so its tray's top is at local `top` at the bottom of the swing, swinging
## along the local route axis (z): positive angles swing toward local -Z.
func _swing(top: Vector3, kind: String, length: float, swing_deg: float, period: float, phase: float, radius: float) -> ManorChandelier:
	var c := ManorChandelier.new()
	c.kind = kind
	c.length = length
	c.swing_deg = swing_deg
	c.period = period
	c.phase = phase
	c.radius = radius
	# the chandelier swings along its local X; turned +90 degrees that is the route's -Z
	c.rotation.y = _ry() + PI * 0.5
	c.position = _w(top) - Vector3(0, 0.2, 0)
	add_child(c)
	return c


## Spectral tripwire: a beam of ghost-light between two candle posts across the route (local
## floor point `c`, `width` across).
func _tripwire(c: Vector3, width: float, period: float, on: float, phase: float, height: float = 2.4, pier: bool = true) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.2), period, on, phase, _yaw)
	for sx: float in [-1.0, 1.0]:
		var lp: Vector3 = c + Vector3(sx * (width * 0.5 + 0.3), 0, 0)
		var p: Vector3 = _w(lp)
		kit.block(p + Vector3(0, (height + 0.6) * 0.5 - 0.1, 0), Vector3(0.5, height + 0.6, 0.5), ManorDecor.STONE_DARK, true, _yaw)
		deco.candelabra(p + Vector3(0, height + 0.5, 0), 0.4, false, ECTO)
		if pier:
			_pier(lp - Vector3(0, 0.1, 0), 0.5, 0.5)
	return g


## Checkpoint landing facing the next stage's heading (_next_yaw).
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	_cp_nodes.append(cp)
	var h: float = size * 0.5 - 0.45
	var inside: bool = _indoor.has(_stage_no)
	for s: float in [-1.0, 1.0]:
		if inside:
			deco.candelabra(_w(c + Vector3(s * h, 0, h)), 2.0, s < 0.0, CANDLE)
		else:
			deco.lamp_post(_w(c + Vector3(s * h, 0, h)), 3.2, s < 0.0)
	# banked-stage feedback: a gust of ectoplasm and violet sparks
	var burst: GPUParticles3D = ManorFx.ecto_burst(self, _w(c) + Vector3(0, 0.4, 0), 1.4, 34, 5.0)
	var glints: GPUParticles3D = ManorFx.glints(self, _w(c) + Vector3(0, 0.8, 0), VIOLET, 40, 7.0)
	_cp_bursts[cp] = [burst, glints]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


## Fork signpost: two lanterns and a floor strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.4, 1.4]:
		deco.lamp_post(_w(p + Vector3(sx, 0, 0)), 2.6, false, col)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.6)), _sz(Vector3(1.4, 0.05, 0.3)), col)


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Jump from `from` onto moving `node` (landing at `local` on it, world-oriented offset from its
## origin) the moment its origin will be within `radius` of `when` in `lead` seconds.
func _board(from: Vector3, node: Node3D, when: Vector3, radius: float, local: Vector3, lead: float = 0.45) -> void:
	route.append({"kind": "x_jump", "from": from, "when_node": node, "when_local": Vector3.ZERO,
		"when_point": when, "when_radius": radius, "lead": lead, "to_node": node, "to_local": local, "hold": true})


## Riding `node`: jump to `to` as soon as its origin is within `radius` of `point`.
func _leave(node: Node3D, point: Vector3, radius: float, to: Vector3, stand: Variant = null) -> void:
	r_jump_from_ride(node, point, radius, to, true, stand)


static func _phantoms_ok(ps: Array[ManorPhantom], starts: Array[float], a: float, b: float) -> bool:
	for i: int in ps.size():
		if not ps[i].is_on_for(Game.course_time, starts[i] + a, starts[i] + b):
			return false
	return true


## Running from `p0` to `p1` (starting any time up to `late` s from now, at 7.5 - 9.5 m/s) stays
## clear of every bar of sweeper `sw` (their full length, at the bar's thickness plus a margin).
static func _sweep_clear(sw: Sweeper, p0: Vector3, p1: Vector3, late: float) -> bool:
	var d := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
	var total: float = d.length()
	d = d / total
	var hub := Vector2(sw.global_position.x, sw.global_position.z)
	var delay: float = 0.0
	while delay <= late + 0.001:
		for speed: float in [7.5, 9.5]:
			var s: float = 0.0
			while s <= delay + total / speed + 0.4:
				var along: float = clampf(speed * (s - delay) - 0.2, 0.0, total)
				var p := Vector2(p0.x + d.x * along, p0.z + d.z * along)
				for i: int in sw.bar_count:
					var a: float = sw.angle_at(Game.course_time + s) + TAU * float(i) / float(sw.bar_count)
					var dir := Vector2(cos(a), -sin(a))
					var near: Vector2 = Geometry2D.get_closest_point_to_segment(p, hub + dir * 0.3, hub + dir * (0.3 + sw.arm_length))
					if near.distance_to(p) < 0.8:
						return false
				s += 0.02
		delay += 0.25
	return true


## The beam stays dark over the whole window [now + a, now + b].
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


# ---- the course ---------------------------------------------------------------------------------

## Half-width of each indoor stage's room (the walls stand just outside it); outdoor stages have none.
const ROOM_HW: Dictionary = {7: 11.0, 8: 10.0, 9: 6.2, 10: 9.0, 11: 10.0, 12: 17.0, 13: 11.0, 14: 7.0, 15: 9.0}

var _prev_yaw: float = 0.0


func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = ManorDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	for n: int in ROOM_HW:
		_indoor[n] = true
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	_frame(Vector3.ZERO, yaws[0])
	_prev_yaw = yaws[0]
	var ranges: Array = []
	for i: int in stages.size():
		_stage_no = i + 1
		_next_yaw = yaws[i + 1]
		var before: int = get_child_count()
		var end: Vector3 = stages[i].call()
		ranges.append([_stage_no, before, get_child_count()])
		_prev_yaw = _yaw
		_frame(_w(end), yaws[i + 1])
	_stage_no = 18
	_next_yaw = yaws[18]
	_stage_18()
	_surroundings()
	_manor_materials(ranges)


# ---- stage 1: Lychgate - hops over leaning graves, the first rotten boards ---------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	_pier(Vector3(0, -2, 0), 10.0, 10.0)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	_lychgate(Vector3(0, 0, -5.4))
	var a1: Dictionary = _blk(Vector3(0, 0, -12.4), 3.0, 3.0)
	var a2: Dictionary = _drum(Vector3(3.0, 1.0, -18.0), 1.3)
	var a3: Dictionary = _blk(Vector3(0.4, 2.0, -23.6), 2.4, 2.4, "alt")
	var b1: Dictionary = _boards(Vector3(0.4, 2.0, -28.9), 2.4, 2.4)
	var b2: Dictionary = _boards(Vector3(0.4, 2.0, -32.9), 2.4, 2.4)
	var s2: Dictionary = _blk(Vector3(0.4, 2.0, -37.0), 3.0, 3.0)
	var cp: Dictionary = _cp(Vector3(0.4, 2.0, -44.5))
	_hop(start, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	# SHORTCUT: the weeping angel's plinth beside a3 - mantle it, leap to the crypt roof past the boards
	var obl: Dictionary = _ledge(Vector3(-2.4, 5.3, -27.8), Vector3(1.8, 7.3, 1.8), "accent")
	_pier(Vector3(-2.4, -2.0, -27.8), 1.4, 1.4)
	var roof: Dictionary = _blk(Vector3(-2.4, 2.6, -35.5), 2.6, 3.0, "accent", 1.0, false)
	deco.mausoleum(_w(Vector3(-2.4, -8.0, -35.5)), _ry(), 2.5, 2.9, 9.6, false, false)
	if route_variant == 2:
		r_mantle(_w(_edge(a3, obl["c"])), _w((obl["c"] as Vector3) + Vector3(0, 0, 0.2)))
		r_walk(_w(Vector3(-2.3, 5.3, -28.2)))
		r_jump(_w(Vector3(-2.3, 5.3, -28.4)), _w(Vector3(-2.4, 2.6, -35.0)))
		_hop(roof, cp, Vector3(-1.0, 0, 1.5))
	else:
		_hop(a3, b1)
		_hop(b1, b2)
		_hop(b2, s2)
		_hop(s2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the graves either side of the path, and two angels at the gate
	for i: int in 7:
		var z: float = -9.0 - float(i) * 5.0
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		_isle(Vector3(sx * kit.rng.randf_range(6.5, 9.0), kit.rng.randf_range(-5.0, -1.0), z), kit.rng.randf_range(0.9, 1.3))
	for sx: float in [-1.0, 1.0]:
		deco.angel(_w(Vector3(sx * 5.6, 0, 5.4)), _ry(), 0.8)
	b1.clear()
	b2.clear()
	return cp["c"]


## The lychgate you start under: two stone posts, a steep little roof, gargoyles, railings.
func _lychgate(c: Vector3) -> void:
	for sx: float in [-1.0, 1.0]:
		kit.block(_w(c + Vector3(sx * 4.6, 3.6, 0)), Vector3(1.4, 7.2, 1.4), ManorDecor.STONE_DARK, true, _yaw)
		deco.gargoyle(_w(c + Vector3(sx * 4.6, 7.2, 0)), _ry() + PI, 0.9)
	var beam := Look.box(Vector3(11.4, 0.6, 1.0), deco.stone(ManorDecor.BARK.lightened(0.1)), _w(c + Vector3(0, 7.5, 0)))
	beam.rotation.y = _ry()
	add_child(beam)
	var pm := PrismMesh.new()
	pm.size = Vector3(12.4, 2.4, 3.2)
	var roof := Look.mesh_node(pm, Look.flat(ManorDecor.ROOF, 0.6, 0.3), _w(c + Vector3(0, 9.0, 0)))
	roof.rotation.y = _ry()
	add_child(roof)
	deco.fence(_w(c + Vector3(-5.3, 0, 0)), _w(c + Vector3(-6.8, 0, 2.0)), 1.8)
	deco.fence(_w(c + Vector3(5.3, 0, 0)), _w(c + Vector3(6.8, 0, 2.0)), 1.8)


# ---- stage 2: Mausoleum Row - mantle the crypt, grave plinths, run the mausoleum wall ---------------

func _stage_2() -> Vector3:
	var m1: Dictionary = _ledge(Vector3(0, 3.3, -7.2), Vector3(5.0, 6.3, 3.4))
	var c1: Dictionary = _drum(Vector3(-2.0, 3.9, -13.4), 1.0)
	var c2: Dictionary = _drum(Vector3(1.6, 4.7, -18.3), 0.95, "alt")
	var c3: Dictionary = _drum(Vector3(-0.4, 5.3, -23.6), 0.95)
	var s1: Dictionary = _blk(Vector3(0.2, 5.3, -28.9), 3.0, 3.0, "alt")
	kit.wallrun(_w(Vector3(2.5, 6.5, -39.9)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var s2: Dictionary = _blk(Vector3(-0.2, 5.3, -52.9), 3.6, 5.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 5.3, -62.3))
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -7.4)))
	_hop(m1, c1)
	_hop(c1, c2)
	_hop(c2, c3)
	_hop(c3, s1)
	r_wallrun(_w(Vector3(0.5, 5.3, -30.05)), _w(Vector3(2.0, 6.7, -34.0)), _w(Vector3(2.0, 6.7, -44.9)), _w(Vector3(-0.2, 5.3, -52.2)))
	_hop(s2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the great mausoleum whose flank you run: its wall behind the panel, a pediment, a lit window
	deco.wall(_w(Vector3(3.6, 1.0, -39.9)), _sz(Vector3(1.4, 16.0, 17.0)), 0.0, ManorDecor.STONE.darkened(0.25), false)
	var pm := PrismMesh.new()
	pm.size = Vector3(1.8, 3.0, 18.0)
	var ped := Look.mesh_node(pm, deco.stone(ManorDecor.STONE_DARK), _w(Vector3(3.6, 10.5, -39.9)))
	ped.rotation.y = _ry()
	add_child(ped)
	for z: float in [-31.4, -48.4]:
		add_child(Look.cylinder(0.45, 15.0, deco.stone(ManorDecor.BONE.darkened(0.35)), _w(Vector3(3.4, 1.5, z)), 0.4, 12))
	deco.window(_w(Vector3(2.85, 11.2, -39.9)), _ry() - PI * 0.5, 1.4, 3.0, 2, true)
	for z: float in [-11.0, -19.0, -27.0]:
		_isle(Vector3(-6.5, kit.rng.randf_range(-1.0, 2.0), z), 1.1)
	deco.dead_tree(_w(Vector3(-15.0, -14.0, -30.0)), 18.0, 0.4)
	return cp["c"]


# ---- stage 3: Hedge Maze (BRANCH) - the floating coffins, or over the hedge -----------------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, false)
	_pier(Vector3(-3.5, -1.0, -8.0), 3.0, 3.0)
	_pier(Vector3(3.5, -1.0, -8.0), 3.0, 3.0)
	# LEFT (green): two possessed coffins ferrying back and forth over the sunken graves
	var k1: ManorPossessed = _possessed(Vector3(-3.5, 0.0, -13.5), Vector3(2.2, 0.5, 3.0), "coffin", [Vector3.ZERO, Vector3(0, 0, -9.0)], 7.0, 0.0, 0.18)
	var k2: ManorPossessed = _possessed(Vector3(-3.5, 1.2, -26.5), Vector3(2.2, 0.5, 3.0), "coffin", [Vector3.ZERO, Vector3(0, 0, -9.0)], 7.0, 0.5, 0.18)
	var merge: Dictionary = _blk(Vector3(0, 1.2, -42.8), 12.0, 4.0, "main", 1.0, false)
	_pier(Vector3(-3.5, 0.2, -42.8), 3.0, 3.0)
	_pier(Vector3(3.5, 0.2, -42.8), 3.0, 3.0)
	# RIGHT (violet): mantle the clipped yew, run the hedge wall, drop off the far arbour
	var l1: Dictionary = _ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 6.3, 3.2), "alt")
	kit.wallrun(_w(Vector3(6.5, 4.5, -24.7)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(3.8, 3.3, -37.0), 3.6, 4.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 1.2, -51.3))
	deco.hedge(_w(Vector3(7.5, 1.5, -24.7)), _sz(Vector3(1.4, 12.0, 18.0)))
	deco.hedge(_w(Vector3(7.8, -3.0, -37.0)), _sz(Vector3(2.0, 12.0, 6.0)))
	deco.hedge(_w(Vector3(-8.5, -3.0, -25.0)), _sz(Vector3(1.6, 10.0, 30.0)))
	_sign(Vector3(-3.5, 0, -7.0), ECTO)
	_sign(Vector3(4.0, 0, -7.0), VIOLET)
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -9.5)))
		# board the first coffin at the near end of its run, ride it, hop to the second as it arrives
		_board(_w(Vector3(-3.5, 0, -9.65)), k1, _w(Vector3(-3.5, 0, -13.5)) - Vector3(0, 0.25, 0), 0.5, Vector3(0, 0.25, 0))
		route.append({"kind": "x_jump", "from_node": k1, "from_local": _d(Vector3(0, 0.25, -0.9)),
			"when_node": k2, "when_local": Vector3.ZERO, "when_point": _w(Vector3(-3.5, 1.2, -26.5)) - Vector3(0, 0.25, 0),
			"when_radius": 0.5, "lead": 0.45, "to_node": k2, "to_local": Vector3(0, 0.25, 0), "hold": true})
		_leave(k2, _w(Vector3(-3.5, 1.2, -35.5)) - Vector3(0, 0.25, 0), 0.4, _w(Vector3(-3.0, 1.2, -42.0)), Vector3(0, 0.25, -0.8))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(4.3, 3.3, -14.85)), _w(Vector3(6.0, 4.7, -18.8)), _w(Vector3(6.0, 4.7, -29.7)), _w(Vector3(3.8, 3.3, -36.3)))
		_hop(l2, merge, Vector3(3.0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the sunken graves under the coffins
	for i: int in 4:
		_isle(Vector3(-3.5 + kit.rng.randf_range(-1.5, 1.5), -6.0 - float(i % 2) * 2.0, -15.0 - float(i) * 6.5), 1.0)
	fork.clear()
	l1.clear()
	return cp["c"]


# ---- stage 4: Open Graves - coffin lids that slam, rotten boards, a spectral tripwire ------------

func _stage_4() -> Vector3:
	var w1: Dictionary = _blk(Vector3(0, 0, -9.5), 2.6, 11.0, "alt", 1.0)
	var p1: Crusher = _coffin_lid(Vector3(0, 0, -7.0), 4.4, 0.0)
	var p2: Crusher = _coffin_lid(Vector3(0, 0, -12.5), 4.4, 0.5)
	var fb: Dictionary = _boards(Vector3(0, 0, -17.4), 2.4, 2.4)
	var w2: Dictionary = _blk(Vector3(0, 0.6, -23.5), 2.6, 6.0, "alt", 1.0)
	var tw: LaserGate = _tripwire(Vector3(0, 0.6, -23.5), 2.6, 4.0, 0.4, 0.3)
	var cp: Dictionary = _cp(Vector3(0, 0.6, -32.0))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -4.7)))
	_wait(func() -> bool: return _press_ok(p1, 0.0, 1.9), _w(Vector3(0, 0, -4.7)))
	r_walk(_w(Vector3(0, 0, -9.7)))
	_wait(func() -> bool: return _press_ok(p2, 0.0, 1.9), _w(Vector3(0, 0, -9.7)))
	r_walk(_w(Vector3(0, 0, -14.5)))
	_hop(_area(Vector3(0, 0, -9.5), 1.3, 5.5), fb)
	_hop(fb, w2, Vector3(0, 0, 1.8))
	_wait(func() -> bool: return _dark(tw, 0.05, 1.55), _w(Vector3(0, 0.6, -21.8)))
	r_walk(_w(Vector3(0, 0.6, -25.6)))
	_hop(w2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# open graves either side, the dead trees
	for i: int in 4:
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		_isle(Vector3(sx * kit.rng.randf_range(5.5, 7.5), kit.rng.randf_range(-4.0, -1.0), -4.0 - float(i) * 5.0), 1.0)
	deco.dead_tree(_w(Vector3(15.0, -16.0, -20.0)), 20.0, 1.2)
	deco.dead_tree(_w(Vector3(-14.0, -16.0, -6.0)), 16.0, 2.6)
	w1.clear()
	return cp["c"]


## A coffin lid that slams: the crusher dressed as a black coffin with a brass cross, between two
## gallows posts on stone piers.
func _coffin_lid(floor_c: Vector3, period: float, phase: float) -> Crusher:
	var size := Vector3(2.8, 1.2, 2.6)
	var cr: Crusher = kit.crusher(_w(floor_c), size, 3.4, period, phase, _yaw)
	for sx: float in [-1.0, 1.0]:
		_pier(floor_c + Vector3(sx * (size.x * 0.5 + 0.35), 0, 0), 0.45, 0.45)
	var wood: StandardMaterial3D = Look.flat(ManorPossessed.WOOD_DARK, 0.7)
	var brass: StandardMaterial3D = Look.flat(ManorPossessed.BRASS, 0.35, 0.85)
	cr.add_child(Look.box(Vector3(size.x + 0.3, 0.3, size.z + 0.3), wood, Vector3(0, size.y * 0.5 + 0.15, 0)))
	cr.add_child(Look.box(Vector3(0.24, 0.05, size.z * 0.7), brass, Vector3(0, size.y * 0.5 + 0.32, 0)))
	cr.add_child(Look.box(Vector3(size.x * 0.5, 0.05, 0.24), brass, Vector3(0, size.y * 0.5 + 0.32, -size.z * 0.18)))
	_coffins.append(cr)
	return cr


var _coffins: Array[Crusher] = []
var _coffin_u: Array[float] = []


# ---- stage 5: Dead Orchard - ride the gibbet cage over the ravine [shortcut: the stumps] -----------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var t1: Dictionary = _blk(Vector3(0, 0, -8.2), 4.0, 3.4)
	# the cage: bottom of its swing at z -17 (tray top 1.87 m under its ends), ends at -11.9 / -22.1
	var cage: ManorChandelier = _swing(Vector3(0, -2.17, -17.0), "cage", 8.0, 40.0, 6.0, 0.0, 1.3)
	var t2: Dictionary = _blk(Vector3(0, 0, -27.1), 4.0, 6.0)
	var pad_p := Vector3(0, 0, -28.4)
	var pad: BouncePad = kit.pad(_w(pad_p), 21.0, 0.0, 0.0, 1.2)
	var plateau: Dictionary = _blk(Vector3(0, 5.8, -35.6), 4.0, 5.0, "main", 1.4)
	var cp: Dictionary = _cp(Vector3(0, 5.8, -45.2))
	# the gnarled tree the cage hangs from: a trunk to the side and a great limb over the ravine
	var pivot: Vector3 = _w(Vector3(0, -2.17 + 8.0, -17.0))
	add_child(Look.cylinder(1.1, 30.0, deco.stone(ManorDecor.BARK), _w(Vector3(-7.5, -8.0, -17.0)), 0.7, 9))
	var root_p: Vector3 = _w(Vector3(-7.5, 7.5, -17.0))
	var limb := Look.cylinder(0.55, pivot.distance_to(root_p) + 0.6, deco.stone(ManorDecor.BARK), (pivot + root_p) * 0.5 + Vector3(0, 0.3, 0), 0.3, 7)
	var dir: Vector3 = (pivot - root_p).normalized()
	var side: Vector3 = dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	limb.basis = Basis(side, dir, side.cross(dir))
	add_child(limb)
	deco.dead_tree(_w(Vector3(-7.5, 7.0, -17.0)), 10.0, 0.7)
	# SHORTCUT: two rotten stumps beside the cage's path - no waiting for the swing
	var st1: Dictionary = _drum(Vector3(-2.6, 0, -14.4), 0.55, "accent", 0.8)
	var st2: Dictionary = _drum(Vector3(-2.6, 0, -19.6), 0.55, "accent", 0.8)
	_hop(cp0, t1, Vector3(0, 0, 0.6))
	if route_variant == 2:
		_hop(t1, st1)
		_hop(st1, st2)
		_hop(st2, t2, Vector3(-1.0, 0, 2.0))
	else:
		# board the cage as it hangs still at the near end of its swing, ride it over, step off
		r_walk(_w(Vector3(0, 0, -9.2)))
		_board(_w(Vector3(0, 0, -9.55)), cage, cage.end_origin(-1.0), 0.7, Vector3(0, 0.2, 0), 0.4)
		_leave(cage, cage.end_origin(1.0), 0.6, _w(Vector3(0, 0, -26.0)), Vector3(0, 0.2, 0))
	r_walk(_w(pad_p + Vector3(0, 0, 1.4)))
	r_pad(_w(pad_p), _w((plateau["c"] as Vector3) + Vector3(0, 0, 0.6)))
	_hop(plateau, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	pad.set_meta("grave_pad", true)
	# a burial mound round the pad
	var mound := Look.sphere(1.8, Look.flat(Color(0.12, 0.1, 0.09), 1.0), _w(pad_p + Vector3(0, -1.55, 0)))
	mound.scale = Vector3(1.4, 0.55, 1.4)
	add_child(mound)
	deco.dead_tree(_w(Vector3(15.0, -18.0, -10.0)), 22.0, 2.0)
	deco.dead_tree(_w(Vector3(14.0, -14.0, -31.0)), 18.0, 4.0)
	ManorFx.wisps(self, _w(Vector3(0, -2.0, -17.0)), _sz(Vector3(7.0, 3.0, 9.0)), 14)
	t1.clear()
	st1.clear()
	st2.clear()
	return cp["c"]


# ---- stage 6: Cliff Stair - mantle up the cliff past a tripwire to the terrace, the knight's lance ----

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var l0: Dictionary = _blk(Vector3(0, 0, -8.5), 6.0, 4.0)
	_ledge(Vector3(0, 3.3, -14.2), Vector3(6.0, 5.5, 3.4))
	var tw: LaserGate = _tripwire(Vector3(0, 3.3, -15.0), 5.0, 4.0, 0.4, 0.0, 2.4, false)
	_ledge(Vector3(0, 6.6, -17.6), Vector3(3.6, 8.8, 3.4), "alt")
	_ledge(Vector3(0, 9.9, -21.0), Vector3(3.6, 12.0, 3.4), "alt")
	var terrace: Dictionary = _blk(Vector3(0, 9.9, -29.0), 5.0, 9.0, "main", 1.4)
	var ram: Piston = kit.piston(_w(Vector3(3.9, 11.2, -29.0)), Vector3(1.8, 1.3, 1.4), _yaw + 90.0, 3.8, 4.6, 0.1, 8.0)
	_pier(Vector3(4.2, 9.4, -29.0), 1.8, 1.8)
	kit.block(_w(Vector3(4.2, 9.4, -29.0)), Vector3(1.8, 1.0, 1.8), ManorDecor.STONE_DARK, true, _yaw)
	var cp: Dictionary = _cp(Vector3(0, 9.9, -39.5))
	_knight(Vector3(3.6, 9.9, -32.6))
	_hop(cp0, l0, Vector3(0, 0, 1.0))
	r_mantle(_w(Vector3(0, 0, -10.15)), _w(Vector3(0, 3.3, -13.3)))
	r_walk(_w(Vector3(0, 3.3, -13.1)))
	_wait(func() -> bool: return _dark(tw, 0.05, 1.9))
	r_mantle(_w(Vector3(0, 3.3, -13.35)), _w(Vector3(0, 6.6, -16.8)))
	r_mantle(_w(Vector3(0, 6.6, -17.0)), _w(Vector3(0, 9.9, -20.4)))
	_hop(_area(Vector3(0, 9.9, -21.0), 1.8, 1.7), terrace, Vector3(0, 0, 2.6))
	_wait(func() -> bool: return _ram_clear(ram, 0.0, 1.8), _w(Vector3(0, 9.9, -26.8)))
	r_walk(_w(Vector3(0, 9.9, -32.2)))
	_hop(terrace, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the cliff the stair climbs, far down in the fog, and angels at its foot
	deco.cliff(_w(Vector3(0, -21.0, -24.0)), _sz(Vector3(22.0, 30.0, 6.0)))
	for sx: float in [-1.0, 1.0]:
		deco.angel(_w(Vector3(sx * 2.4, 0, -9.9)), _ry(), 0.7)
		deco.lamp_post(_w(Vector3(sx * 2.2, 9.9, -24.9)), 3.0, sx > 0.0)
	l0.clear()
	return cp["c"]


## A suit of armour standing guard beside the terrace; its lance is the piston.
func _knight(base: Vector3) -> void:
	var steel: StandardMaterial3D = Look.flat(Color(0.42, 0.42, 0.46), 0.3, 0.9)
	var n := Node3D.new()
	n.position = _w(base)
	n.rotation.y = _ry()
	add_child(n)
	n.add_child(Look.box(Vector3(1.0, 1.4, 0.7), steel, Vector3(0, 2.5, 0)))
	n.add_child(Look.cylinder(0.3, 0.5, steel, Vector3(0, 3.5, 0), 0.26, 10))
	n.add_child(Look.sphere(0.34, steel, Vector3(0, 3.9, 0)))
	n.add_child(Look.box(Vector3(0.5, 0.06, 0.1), Look.flat(Color(0.05, 0.05, 0.05), 0.9), Vector3(0, 3.95, -0.3)))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.cylinder(0.18, 1.8, steel, Vector3(sx * 0.3, 0.9, 0), 0.14, 8))
		n.add_child(Look.sphere(0.26, steel, Vector3(sx * 0.62, 3.1, 0)))
		n.add_child(_ns(Look.sphere(0.05, Look.flat(ECTO, 0.4, 0.0, 3.0), Vector3(sx * 0.1, 3.95, -0.33))))


static func _ns(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---- stage 7: The Foyer (BRANCH) - phantom furniture over the fallen floor, or up the grand stair ----

func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, false)
	# LEFT (green): phantom furniture, one piece after another, over the hole in the floor
	var pz: Array[Vector3] = [Vector3(-3.5, 0.0, -16.0), Vector3(-3.5, 0.6, -22.05), Vector3(-2.4, 1.2, -27.95), Vector3(-3.4, 1.2, -35.0)]
	var kinds: Array[String] = ["table", "armoire", "piano", "chest"]
	var ph: Array[ManorPhantom] = []
	for i: int in pz.size():
		ph.append(_phantom(pz[i], 2.3, 2.2, kinds[i], 4.0, 0.65, fposmod(-0.2125 * float(i), 1.0)))
	var merge: Dictionary = _blk(Vector3(0, 1.2, -42.8), 12.0, 4.0, "main", 1.0, false)
	# RIGHT (violet): up the grand staircase (two landings), along the rotten balcony, down
	_ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 14.0, 3.2), "alt")
	_ledge(Vector3(4.0, 6.6, -16.8), Vector3(3.0, 17.0, 3.2), "alt")
	var bb: Array[Dictionary] = []
	for i: int in 3:
		bb.append(_boards(Vector3(4.0, 6.6, -21.6 - float(i) * 4.4), 2.4, 2.4))
	var l2: Dictionary = _blk(Vector3(3.8, 3.9, -37.2), 3.6, 3.6, "alt", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -51.3))
	_sign(Vector3(-3.5, 0, -7.0), ECTO)
	_sign(Vector3(4.0, 0, -7.0), VIOLET)
	_room(-51.3, -11.0, 18.0)
	_grand_stair(Vector3(4.0, 0, -12.0))
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.4)))
		# (measured: the bot lands on each piece ~0.97 / 1.81 / 2.65 / 3.53 s after it sets off, and is
		# off it ~0.3 s later; each window covers that plus a full second of hesitation)
		var starts: Array[float] = [0.87, 1.71, 2.55, 3.43]
		_wait(func() -> bool: return _phantoms_ok(ph, starts, 0.0, 1.5))
		var prev: Dictionary = _area(Vector3(-3.5, 0, -8.0), 1.5, 2.0)
		for i: int in pz.size():
			var m: Dictionary = _area(pz[i], 1.15, 1.1)
			_hop(prev, m)
			prev = m
		_hop(prev, merge, Vector3(-3.0, 0, 0.8))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -12.8)))
		r_mantle(_w(Vector3(4.0, 3.3, -12.7)), _w(Vector3(4.0, 6.6, -16.4)))
		var prev2: Dictionary = _area(Vector3(4.0, 6.6, -16.8), 1.5, 1.6)
		for b: Dictionary in bb:
			_hop(prev2, b)
			prev2 = b
		_hop(prev2, l2)
		_hop(l2, merge, Vector3(3.0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# a great chandelier hanging dead over the hall, and the family portraits
	_hanging_chandelier(Vector3(-3.0, 12.0, -26.0), 2.6)
	fork.clear()
	return cp["c"]


## The grand staircase's banisters and carpet running up beside the two landings (decor).
func _grand_stair(foot: Vector3) -> void:
	var wood: StandardMaterial3D = Look.flat(ManorPossessed.WOOD, 0.6)
	var carpet: StandardMaterial3D = Look.flat(Color(0.35, 0.05, 0.08), 0.95)
	for sx: float in [-1.0, 1.0]:
		var rail := Look.box(Vector3(0.14, 0.14, 9.0), wood, _w(foot + Vector3(sx * 1.6, 4.4, -3.4)))
		rail.basis = Basis(Vector3.UP, _ry()) * Basis(Vector3.RIGHT, 0.62)
		add_child(rail)
		for i: int in 6:
			add_child(Look.cylinder(0.06, 1.2, wood, _w(foot + Vector3(sx * 1.6, 0.6 + float(i) * 1.3, -0.4 - float(i) * 1.1)), -1.0, 6))
	var run := Look.box(Vector3(1.6, 0.04, 3.2), carpet, _w(foot + Vector3(0, 3.33, -1.6)))
	run.rotation.y = _ry()
	add_child(run)
	var run2 := Look.box(Vector3(1.6, 0.04, 3.2), carpet, _w(foot + Vector3(0, 6.63, -4.8)))
	run2.rotation.y = _ry()
	add_child(run2)


## A dead chandelier hanging from the rafters (decor): brass rings, dripping candles, a lamp.
func _hanging_chandelier(c: Vector3, r: float) -> void:
	var brass: StandardMaterial3D = Look.flat(ManorChandelier.BRASS, 0.3, 0.9)
	var n := Node3D.new()
	n.position = _w(c)
	add_child(n)
	for k: int in 2:
		var tm := TorusMesh.new()
		tm.inner_radius = r * (1.0 - 0.35 * float(k)) - 0.08
		tm.outer_radius = r * (1.0 - 0.35 * float(k)) + 0.08
		tm.rings = 32
		tm.ring_segments = 6
		n.add_child(Look.mesh_node(tm, brass, Vector3(0, float(k) * 0.9, 0)))
	n.add_child(Look.cylinder(0.06, 8.0, Look.flat(ManorDecor.IRON, 0.5, 0.7), Vector3(0, 4.8, 0), -1.0, 5))
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var p := Vector3(cos(a), 0, sin(a)) * r
		n.add_child(Look.cylinder(0.06, 0.4, Look.flat(Color(0.88, 0.86, 0.78), 0.6), p + Vector3(0, 0.25, 0), -1.0, 6))
		var f := Fx.sprite(Color(2.2, 1.4, 0.6), 0.34, Fx.Tex.DOT)
		f.position = p + Vector3(0, 0.55, 0)
		n.add_child(f)
	var o := OmniLight3D.new()
	o.light_color = CANDLE
	o.light_energy = 2.2
	o.omni_range = 14.0
	o.shadow_enabled = false
	n.add_child(o)


# ---- stage 8: The Library - rotten boards, mantle the bookcase, run the shelves [shortcut: ride] ----

func _stage_8() -> Vector3:
	var s1: Dictionary = _blk(Vector3(0, 0, -8.6), 3.0, 3.0, "main", 1.0, false)
	var ba: Dictionary = _boards(Vector3(0, 0.6, -13.8), 2.4, 2.4)
	var bb: Dictionary = _boards(Vector3(0, 1.2, -18.6), 2.4, 2.4)
	var shelf: Dictionary = _ledge(Vector3(0, 4.5, -23.5), Vector3(4.0, 15.0, 3.4), "alt")
	kit.wallrun(_w(Vector3(2.5, 5.7, -34.7)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var s2: Dictionary = _blk(Vector3(-0.2, 4.5, -47.7), 3.6, 5.0, "alt", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, 4.5, -57.1))
	_room(-57.1, -11.0, 20.0)
	_bookcases()
	# SHORTCUT: a possessed bookcase that floats up the length of the library
	var ride: ManorPossessed = _possessed(Vector3(-3.6, 0.3, -9.0), Vector3(2.4, 0.6, 3.2), "bookcase", [Vector3.ZERO, Vector3(0, 4.2, -38.2)], 11.0, 0.0, 0.16)
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -8.2)))
	if route_variant == 2:
		_board(_w(Vector3(-1.15, 0, -8.8)), ride, _w(Vector3(-3.6, 0.3, -9.0)) - Vector3(0, 0.3, 0), 0.4, Vector3(0, 0.3, 0), 0.4)
		_leave(ride, _w(Vector3(-3.6, 4.5, -47.2)) - Vector3(0, 0.3, 0), 0.35, _w(Vector3(-0.4, 4.5, -48.2)), Vector3(0, 0.3, 0))
	else:
		_hop(s1, ba)
		_hop(ba, bb)
		r_mantle(_w(Vector3(0, 1.2, -19.45)), _w(Vector3(0, 4.5, -22.6)))
		r_walk(_w(Vector3(0.3, 4.5, -24.4)))
		r_wallrun(_w(Vector3(0.5, 4.5, -24.85)), _w(Vector3(2.0, 5.9, -28.8)), _w(Vector3(2.0, 5.9, -39.7)), _w(Vector3(-0.2, 4.5, -47.0)))
	_hop(s2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	shelf.clear()
	return cp["c"]


## The library's towering shelves behind the run panel, and reading lamps on the landings (decor).
func _bookcases() -> void:
	var dark: StandardMaterial3D = Look.flat(ManorPossessed.WOOD_DARK, 0.8)
	var back := Look.box(Vector3(1.0, 18.0, 18.0), dark, _w(Vector3(3.4, 1.0, -34.7)))
	back.rotation.y = _ry()
	add_child(back)
	var cols: Array[Color] = [Color(0.4, 0.1, 0.1), Color(0.12, 0.2, 0.3), Color(0.3, 0.26, 0.12), Color(0.18, 0.3, 0.16), Color(0.25, 0.12, 0.3)]
	for row: int in 7:
		var y: float = -6.0 + float(row) * 2.2
		if y > 1.5 and y < 9.0:
			continue
		var shelf := Look.box(Vector3(0.5, 0.08, 17.0), dark, _w(Vector3(2.85, y, -34.7)))
		shelf.rotation.y = _ry()
		add_child(shelf)
		for k: int in 10:
			var bk := Look.box(Vector3(0.32, 1.1 + 0.4 * kit.rng.randf(), 1.4), Look.flat(cols[(row + k) % cols.size()], 0.85), _w(Vector3(2.9, y + 0.7, -43.0 + float(k) * 1.65)))
			bk.rotation.y = _ry()
			add_child(bk)
	# the shelves on the far wall and the rolling ladder
	for i: int in 4:
		var bc := Look.box(Vector3(3.0, 14.0, 1.0), dark, _w(Vector3(-9.2 + float(i) * 0.0, 0.0, -12.0 - float(i) * 9.0)))
		bc.rotation.y = _ry() + PI * 0.5
		add_child(bc)
	var green: Color = Color(0.4, 1.0, 0.5)
	for z: float in [-8.6, -47.7]:
		deco.candelabra(_w(Vector3(1.2, 0, z) + Vector3(0, 0, 0)) + Vector3(0, 4.5 if z < -20.0 else 0.0, 0), 1.2, z < -20.0, green)


# ---- stage 9: Portrait Gallery - the ancestors' gaze sweeps the long gallery [shortcut: the mirror] ----

func _stage_9() -> Vector3:
	var g1: Dictionary = _blk(Vector3(0, 0, -10.5), 5.0, 13.0, "main", 1.0, false)
	var g2: Dictionary = _blk(Vector3(0, 0, -24.5), 5.0, 11.0, "main", 1.0, false)
	var g3: Dictionary = _blk(Vector3(0, 0, -39.0), 5.0, 14.0, "main", 1.0, false)
	var gz: Array[float] = [-10.5, -24.5, -38.5]
	var gaze: Array[ManorGaze] = []
	for i: int in 3:
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		gaze.append(_gaze(Vector3(sx * 6.1, 0, gz[i]), sx, 6.0, 0.4, [0.0, 0.33, 0.66][i]))
	var cp: Dictionary = _cp(Vector3(0, 0, -53.0))
	_room(-53.0, -11.0, 12.0, false)
	# SHORTCUT: a sideboard against the right wall with a tall mirror on it - step through it and
	# come out of the mirror at the far end of the gallery
	_ledge(Vector3(4.15, 3.3, -7.6), Vector3(2.7, 14.0, 4.0), "accent")
	var mirror: WarpPortal = _mirror(Vector3(4.15, 3.3, -9.1), 0.0, Vector3(0, 0, -43.0), 0.0)
	var g0: ManorGaze = gaze[0]
	var g1n: ManorGaze = gaze[1]
	var g2n: ManorGaze = gaze[2]
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -4.6)))
	if route_variant == 2:
		_wait(func() -> bool: return g0.is_shut_for(Game.course_time, 0.0, 2.7), _w(Vector3(0, 0, -4.6)))
		r_walk(_w(Vector3(0.8, 0, -6.2)))
		r_mantle(_w(Vector3(1.0, 0, -6.2)), _w(Vector3(3.8, 3.3, -6.2)))
		r_walk(_w(Vector3(4.15, 3.3, -5.95)))
		r_portal(_w(Vector3(4.15, 3.3, -9.4)), mirror.exit_point())
	else:
		_wait(func() -> bool: return g0.is_shut_for(Game.course_time, 0.0, 2.6), _w(Vector3(0, 0, -4.6)))
		r_walk(_w(Vector3(0, 0, -16.6)))
		_wait(func() -> bool: return g1n.is_shut_for(Game.course_time, 0.0, 2.9), _w(Vector3(0, 0, -16.6)))
		_hop(g1, g2, Vector3(0, 0, 4.0))
		r_walk(_w(Vector3(0, 0, -29.6)))
		_wait(func() -> bool: return g2n.is_shut_for(Game.course_time, 0.0, 2.9), _w(Vector3(0, 0, -29.6)))
		_hop(g2, g3, Vector3(0, 0, 4.0))
		r_walk(_w(Vector3(0, 0, -44.0)))
	_hop(g3, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# alcove pillars at the safe spots between the portraits
	for z: float in [-18.0, -31.0]:
		for sx: float in [-1.0, 1.0]:
			add_child(Look.cylinder(0.45, 30.0, deco.stone(ManorDecor.BONE.darkened(0.4)), _w(Vector3(sx * 5.4, 4.0, z)), 0.4, 12))
	return cp["c"]


## A gaze portrait on the gallery wall at local floor point `at` (sx: -1 left wall, +1 right wall).
func _gaze(at: Vector3, sx: float, period: float, on: float, phase: float, reach: float = 9.0, sweep: float = 36.0) -> ManorGaze:
	var g := ManorGaze.new()
	g.period = period
	g.on_fraction = on
	g.phase = phase
	g.reach = reach
	g.eye_height = 3.2
	g.sweep_deg = sweep
	g.warn = 1.2
	# facing across the gallery (its -Z out of the wall)
	g.rotation.y = _ry() + (-PI * 0.5 if sx < 0.0 else PI * 0.5)
	g.position = _w(at + Vector3(0, 3.2 - 0.35, 0))
	add_child(g)
	return g


## A mirror portal: a tall gilt-framed looking glass around the warp ring (entry at local floor
## `entry`, facing `yaw_off` from the route), and a twin mirror where you come out.
func _mirror(entry: Vector3, yaw_off: float, exit_l: Vector3, exit_yaw_off: float) -> WarpPortal:
	var p: WarpPortal = kit.portal(_w(entry), _yaw + yaw_off, _w(exit_l), _yaw + exit_yaw_off, 7.0)
	for pos: Vector3 in [entry, exit_l]:
		var yaw: float = _ry() + deg_to_rad(yaw_off if pos == entry else exit_yaw_off)
		var n := Node3D.new()
		n.position = _w(pos)
		n.rotation.y = yaw
		add_child(n)
		var gold: StandardMaterial3D = Look.flat(Color(0.7, 0.54, 0.24), 0.3, 0.9)
		for sx: float in [-1.0, 1.0]:
			n.add_child(Look.box(Vector3(0.22, 3.4, 0.3), gold, Vector3(sx * 1.62, 1.7, 0.05)))
			n.add_child(Look.sphere(0.16, gold, Vector3(sx * 1.62, 3.5, 0.05)))
		n.add_child(Look.box(Vector3(3.46, 0.26, 0.3), gold, Vector3(0, 3.3, 0.05)))
		var crest := Look.cylinder(0.5, 0.2, gold, Vector3(0, 3.62, 0.05), -1.0, 16)
		crest.rotation.x = PI * 0.5
		n.add_child(crest)
		ManorFx.rising(self, _w(pos), 1.0, 3.0, VIOLET, 14)
	_arrival(exit_l, VIOLET)
	return p


## A burst of ectoplasm and glints where a mirror lets you out (fired when you arrive).
func _arrival(at: Vector3, col: Color) -> void:
	var p: GPUParticles3D = ManorFx.glints(self, _w(at + Vector3(0, 1.0, 0)), col, 50, 7.0)
	var s: GPUParticles3D = ManorFx.ecto_burst(self, _w(at + Vector3(0, 0.3, 0)), 1.0, 24, 4.0)
	_arrivals.append({"at": _w(at), "p": [p, s], "cool": 0.0})


# ---- stage 10: Dining Hall - the carousel of possessed chairs, candle tripwire, the armoire ram ----

func _stage_10() -> Vector3:
	var table: Dictionary = _blk(Vector3(0, 0.6, -22.0), 3.4, 30.0, "alt", 1.0, false)
	# the carousel stands on a pedestal beside the table; its two rows of chairs sweep along the
	# table away from you - let a row go by, run along behind it, and be off before the next comes
	kit.block(_w(Vector3(3.0, 0.1, -14.0)), Vector3(1.4, 1.0, 1.4), ManorDecor.STONE_DARK, true, _yaw)
	_pier(Vector3(3.0, -0.4, -14.0), 1.2, 1.2)
	var sw: Sweeper = _chairs(Vector3(3.0, 0.6, -14.0), 4.6, 2, -5.0, 0.0)
	var tw: LaserGate = _tripwire(Vector3(0, 0.6, -25.0), 2.8, 4.0, 0.4, 0.5, 2.4, true)
	var ram: Piston = kit.piston(_w(Vector3(3.3, 1.9, -31.0)), Vector3(1.8, 1.3, 1.4), _yaw + 90.0, 3.6, 4.6, 0.2, 8.0)
	kit.block(_w(Vector3(3.5, 0.1, -31.0)), Vector3(2.0, 1.0, 2.0), ManorDecor.STONE_DARK, true, _yaw)
	var cp: Dictionary = _cp(Vector3(0, 0.6, -43.5))
	_room(-43.5, -11.0, 14.0)
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0.6, -8.2)))
	# across the carousel: wait for a row of chairs to sweep past, then run along behind it (the
	# check allows for starting anywhere up to a second late, at any pace from 7.5 to 9.5 m/s)
	var c0: Vector3 = _w(Vector3(0, 0.6, -9.0))
	var c1: Vector3 = _w(Vector3(0, 0.6, -19.4))
	r_walk(c0)
	_wait(func() -> bool: return _sweep_clear(sw, c0, c1, 1.0), c0)
	r_walk(c1)
	r_walk(_w(Vector3(0, 0.6, -23.4)))
	_wait(func() -> bool: return _dark(tw, 0.05, 1.55), _w(Vector3(0, 0.6, -23.4)))
	r_walk(_w(Vector3(0, 0.6, -28.8)))
	_wait(func() -> bool: return _ram_clear(ram, 0.0, 1.8), _w(Vector3(0, 0.6, -28.8)))
	r_walk(_w(Vector3(0, 0.6, -34.0)))
	_hop(table, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the banquet: candlesticks, a rotten feast, the armoire the ram bursts out of
	for z: float in [-8.0, -20.5, -35.5]:
		for sx: float in [-1.0, 1.0]:
			deco.candelabra(_w(Vector3(sx * 1.25, 0.6, z)), 0.6, false, CANDLE)
	var arm := Look.box(Vector3(2.4, 4.2, 2.2), Look.flat(ManorPossessed.WOOD_DARK, 0.8), _w(Vector3(5.6, 2.6, -31.0)))
	arm.rotation.y = _ry()
	add_child(arm)
	_hanging_chandelier(Vector3(0, 10.0, -22.0), 3.0)
	return cp["c"]


## The carousel: a sweeper whose bars are rows of possessed dining chairs whirling round a
## candelabrum on the table.
func _chairs(floor_c: Vector3, arm: float, bars: int, period: float, phase: float) -> Sweeper:
	var sw: Sweeper = kit.sweeper(_w(floor_c), arm, bars, period, phase)
	var pivot: Node3D = sw.get_child(0) as Node3D
	var wood: StandardMaterial3D = Look.flat(ManorPossessed.WOOD, 0.7)
	var velvet: StandardMaterial3D = Look.flat(Color(0.4, 0.06, 0.12), 0.9)
	for holder: Node in pivot.get_children():
		var h := holder as Node3D
		var n: int = int(arm / 0.9)
		for i: int in n:
			var x: float = 0.7 + float(i) * arm / float(n)
			h.add_child(Look.box(Vector3(0.7, 0.1, 0.6), velvet, Vector3(x, 0.55, 0)))
			h.add_child(Look.box(Vector3(0.7, 0.8, 0.08), wood, Vector3(x, 0.95, 0.28)))
	add_child(Look.cylinder(0.12, 1.8, Look.flat(ManorPossessed.BRASS, 0.35, 0.85), _w(floor_c + Vector3(0, 0.9, 0)), -1.0, 8))
	ManorFx.flame(self, _w(floor_c + Vector3(0, 1.9, 0)), 1.2, ECTO)
	return sw


# ---- stage 11: The Chapel - phantom pews over the crypt, the coffin at the altar, climb the altar ----

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var mp: Array[Vector3] = [Vector3(0, 0, -8.6), Vector3(1.2, 0.6, -14.0), Vector3(-0.2, 1.2, -19.6)]
	var pews: Array[ManorPhantom] = []
	for i: int in mp.size():
		pews.append(_phantom(mp[i], 2.6, 2.0, "bench", 4.2, 0.62, fposmod(-0.2 * float(i), 1.0)))
	var nave: Dictionary = _blk(Vector3(0, 1.2, -28.6), 3.0, 7.8, "main", 1.0, false)
	var lid: Crusher = _coffin_lid(Vector3(0, 1.2, -29.4), 4.4, 0.25)
	_ledge(Vector3(0, 4.5, -36.2), Vector3(6.0, 16.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 4.5, -44.0))
	_room(-44.0, -11.0, 16.0)
	var p0: ManorPhantom = pews[0]
	var p1: ManorPhantom = pews[1]
	var p2: ManorPhantom = pews[2]
	_wait(func() -> bool: return p0.is_on_for(Game.course_time, 1.02, 2.47) and p1.is_on_for(Game.course_time, 1.86, 3.31) and p2.is_on_for(Game.course_time, 2.69, 4.14))
	var prev: Dictionary = cp0
	for i: int in mp.size():
		var m: Dictionary = _area(mp[i], 1.3, 1.0)
		_hop(prev, m)
		prev = m
	_hop(prev, nave, Vector3(0, 0, 2.7))
	_wait(func() -> bool: return _press_ok(lid, 0.0, 2.0), _w(Vector3(0, 1.2, -26.3)))
	r_walk(_w(Vector3(0, 1.2, -32.0)))
	r_mantle(_w(Vector3(0, 1.2, -32.15)), _w(Vector3(0, 4.5, -35.3)))
	_hop(_area(Vector3(0, 4.5, -36.2), 3.0, 1.7), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the altar: candles, a great rose window of stained glass, a cross of light
	for sx: float in [-1.0, 1.0]:
		deco.candelabra(_w(Vector3(sx * 2.4, 4.5, -37.2)), 1.6, sx < 0.0, ECTO)
	# pews in the crypt far below, where the floor fell in
	for i: int in 6:
		var pew := Look.box(Vector3(5.0, 1.0, 0.8), Look.flat(ManorPossessed.WOOD_DARK, 0.8), _w(Vector3(kit.rng.randf_range(-4.0, 4.0), -10.4, -6.0 - float(i) * 5.0)))
		pew.rotation.y = _ry() + kit.rng.randf_range(-0.6, 0.6)
		add_child(pew)
	return cp["c"]


# ---- stage 12: THE GRAND BALLROOM - ride the waltz, then the great chandelier [shortcut: the mirror wall] ----

func _stage_12() -> Vector3:
	var balcony: Dictionary = _blk(Vector3(0, 0, -5.5), 10.0, 5.0, "main", 1.0, false)
	# the waltz: three ghost couples on torn-up rounds of parquet, circling over the fallen floor
	var centre := Vector3(-2.0, -0.3, -18.0)
	var dancers: Array[ManorPossessed] = []
	for i: int in 3:
		dancers.append(_dancer(centre, 7.0, 12.0, float(i) / 3.0))
	var island: Dictionary = _blk(Vector3(1.8, -0.3, -29.6), 8.4, 3.6, "main", 1.0, false)
	# the great chandelier: 16 m of chain from the rafters, swinging along the hall
	var chand: ManorChandelier = _swing(Vector3(0, -1.88, -40.0), "chandelier", 16.0, 24.0, 8.0, 0.0, 1.8)
	var gallery: Dictionary = _blk(Vector3(0, -0.5, -51.1), 5.0, 5.0, "main", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, -0.5, -60.5))
	_room(-60.5, -12.0, 16.0, false)
	var axle := Look.box(Vector3(36.0, 0.9, 0.9), Look.flat(ManorPossessed.WOOD_DARK, 0.85), _w(Vector3(0, 14.12 + 0.45, -40.0)))
	axle.rotation.y = _ry()
	add_child(axle)
	_ballroom(centre)
	# SHORTCUT: up to the musicians' ledge, along the mirrored wall, down onto the orchestra island
	_ledge(Vector3(6.0, 3.3, -9.0), Vector3(2.8, 15.3, 3.4), "accent")
	kit.wallrun(_w(Vector3(8.6, 4.5, -20.2)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var screen := Look.box(Vector3(0.3, 9.0, 17.0), Look.flat(Color(0.5, 0.56, 0.72), 0.03, 1.0), _w(Vector3(9.1, 4.5, -20.2)))
	screen.rotation.y = _ry()
	add_child(screen)
	var gilt := Look.box(Vector3(0.36, 9.6, 17.6), Look.flat(Color(0.62, 0.48, 0.22), 0.35, 0.85), _w(Vector3(9.35, 4.5, -20.2)))
	gilt.rotation.y = _ry()
	add_child(gilt)
	_pier(Vector3(9.2, 0.0, -20.2), 0.5, 16.0)
	var near_p: Vector3 = _w(centre + Vector3(0, 0, 7.0)) - Vector3(0, 0.2, 0)
	var far_p: Vector3 = _w(centre + Vector3(0, 0, -7.0)) - Vector3(0, 0.2, 0)
	if route_variant == 2:
		r_walk(_w(Vector3(4.8, 0, -4.6)))
		r_mantle(_w(Vector3(4.8, 0, -5.0)), _w(Vector3(6.0, 3.3, -8.4)))
		r_wallrun(_w(Vector3(6.1, 3.3, -10.35)), _w(Vector3(8.1, 4.7, -14.3)), _w(Vector3(8.1, 4.7, -22.0)), _w(Vector3(4.2, -0.3, -29.6)))
		r_walk(_w(Vector3(0.2, -0.3, -30.6)))
	else:
		r_walk(_w(Vector3(-2.0, 0, -7.2)))
		_board(_w(Vector3(-2.0, 0, -7.65)), dancers[0], near_p, 0.8, Vector3(0, 0.2, 0), 0.5)
		_leave(dancers[0], far_p, 0.7, _w(Vector3(-0.6, -0.3, -29.4)), Vector3(0, 0.2, 0))
		r_walk(_w(Vector3(0, -0.3, -30.6)))
	_board(_w(Vector3(0, -0.3, -31.05)), chand, chand.end_origin(-1.0), 0.8, Vector3(0, 0.2, 0), 0.45)
	_leave(chand, chand.end_origin(1.0), 0.6, _w(Vector3(0, -0.5, -50.6)), Vector3(0, 0.2, 0))
	_hop(gallery, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	balcony.clear()
	island.clear()
	return cp["c"]


## A waltzing couple on a round of parquet, orbiting `centre` (local top) at radius `r`.
func _dancer(centre: Vector3, r: float, period: float, phase: float) -> ManorPossessed:
	var m := ManorPossessed.new()
	m.kind = "dancers"
	m.mode = MovingPlatform.Mode.ORBIT
	m.size = Vector3(3.2, 0.4, 3.2)
	m.is_round = true
	m.orbit_radius = r
	m.orbit_axis = Vector3.UP
	m.period = period
	m.phase = phase
	m.position = _w(centre) - Vector3(0, 0.2, 0)
	add_child(m)
	return m


## The ballroom: mirrored walls, a gallery of candelabras, ghosts dancing on the broken floor far
## below, blood-red petals drifting down through the moonlight.
func _ballroom(centre: Vector3) -> void:
	# ghost couples still dancing down on what is left of the floor (unreachable, decor)
	for i: int in 5:
		var d: ManorPossessed = _dancer(Vector3(centre.x, -11.0, centre.z - 10.0), 6.0 + float(i % 2) * 3.0, 16.0 + float(i) * 2.0, float(i) / 5.0)
		d.collision_layer = 0
	var pm := PlaneMesh.new()
	pm.size = Vector2(26.0, 50.0)
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.22, 0.14, 0.1)
	floor_m.roughness = 0.25
	floor_m.metallic = 0.2
	var parquet := Look.mesh_node(pm, floor_m, _w(Vector3(0, -11.4, -30.0)))
	parquet.rotation.y = _ry()
	add_child(parquet)
	# tall mirrors down both walls
	for sx: float in [-1.0, 1.0]:
		for k: int in 5:
			var z: float = -8.0 - float(k) * 11.0
			var mirror := Look.box(Vector3(0.1, 4.4, 3.6), Look.flat(Color(0.55, 0.6, 0.75), 0.02, 1.0), _w(Vector3(sx * 16.9, 2.4, z)))
			mirror.rotation.y = _ry()
			add_child(mirror)
			var fr := Look.box(Vector3(0.2, 5.0, 4.2), Look.flat(Color(0.62, 0.48, 0.22), 0.35, 0.85), _w(Vector3(sx * 16.97, 2.4, z)))
			fr.rotation.y = _ry()
			add_child(fr)
	ManorFx.petals(self, _w(Vector3(0, 8.0, -30.0)), _sz(Vector3(12.0, 5.0, 25.0)), 50)
	ManorFx.ghost_motes(self, _w(Vector3(0, -6.0, -25.0)), _sz(Vector3(12.0, 4.0, 20.0)), 40)
	_hanging_chandelier(Vector3(-9.0, 12.0, -22.0), 2.2)
	_hanging_chandelier(Vector3(9.5, 12.0, -46.0), 2.2)
	# the orchestra's ghostly grand piano and music stands on the island
	var piano: Node3D = kit.block(_w(Vector3(2.6, 0.2, -28.6)), _sz(Vector3(2.4, 1.0, 1.6)), Color(0.03, 0.03, 0.04), true, 0.0)
	piano.add_child(Look.box(Vector3(0.1, 1.2, 1.4), Look.flat(Color(0.03, 0.03, 0.04), 0.2, 0.3), Vector3(0.6, 1.1, 0)))


# ---- stage 13: Hall of Mirrors (BRANCH) - step through the looking glass, or climb the mirror chimney ----

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -7.5), 14.0, 3.0, "main", 1.0, false)
	# LEFT (green): hop to the mirror island, step into the glass, come out high on the gallery
	var isle: Dictionary = _blk(Vector3(-4.0, 0, -13.8), 3.0, 4.0, "alt", 1.0, false)
	var mirror: WarpPortal = _mirror(Vector3(-4.0, 0, -14.9), 0.0, Vector3(-3.0, 11.9, -42.3), 0.0)
	# RIGHT (violet): the mirror chimney - three wall runs from wall to wall, up to the gallery
	var r0: Dictionary = _blk(Vector3(6.0, 0, -12.2), 3.0, 3.0, "alt", 1.0, false)
	_mirror_panel(8.3, 1.2, -17.0, -23.5)
	_mirror_panel(3.7, 6.0, -22.0, -30.0)
	_mirror_panel(8.3, 9.0, -28.0, -36.0)
	_ledge(Vector3(5.25, 11.9, -39.5), Vector3(4.5, 24.0, 4.0), "alt")
	var merge: Dictionary = _blk(Vector3(0, 11.9, -43.5), 12.0, 4.0, "main", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, 11.9, -52.0))
	_sign(Vector3(-4.0, 0, -6.6), ECTO)
	_sign(Vector3(5.2, 0, -6.6), VIOLET)
	_room(-52.0, -11.0, 26.0)
	_hop(cp0, fork, Vector3(0, 0, 0.5))
	if route_variant != 1:
		_hop(_area(Vector3(-4.0, 0, -7.5), 2.0, 1.5), isle, Vector3(0, 0, 1.2))
		r_portal(_w(Vector3(-4.0, 0, -15.2)), mirror.exit_point())
		r_walk(_w(Vector3(-2.0, 11.9, -43.8)))
	else:
		_hop(_area(Vector3(5.0, 0, -7.5), 2.0, 1.5), r0, Vector3(0, 0, 0.6))
		r_wallrun(_w(Vector3(6.5, 0, -13.35)), _w(Vector3(7.7, 1.4, -18.1)), _w(Vector3(7.7, 1.4, -21.0)), _w(Vector3(4.3, 5.5, -24.9)))
		r_wallrun(Vector3.ZERO, _w(Vector3(4.3, 5.5, -24.9)), _w(Vector3(4.3, 5.5, -27.9)), _w(Vector3(7.7, 8.5, -31.5)), true, true)
		r_wallrun(Vector3.ZERO, _w(Vector3(7.7, 8.5, -31.5)), _w(Vector3(7.7, 8.5, -32.9)), _w(Vector3(5.25, 11.9, -40.6)), true, true)
		r_walk(_w(Vector3(3.0, 11.9, -42.4)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	fork.clear()
	return cp["c"]


## A mirror-chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by a tall looking glass.
func _mirror_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	var s: float = signf(x - 6.0)
	var back := Look.box(Vector3(0.3, height + 2.0, absf(z0 - z1) + 1.0), Look.flat(Color(0.5, 0.56, 0.72), 0.03, 1.0), _w(Vector3(x + s * 0.45, y, (z0 + z1) * 0.5)))
	back.rotation.y = _ry()
	add_child(back)
	var frame := Look.box(Vector3(0.36, height + 2.6, absf(z0 - z1) + 1.6), Look.flat(Color(0.62, 0.48, 0.22), 0.35, 0.85), _w(Vector3(x + s * 0.7, y, (z0 + z1) * 0.5)))
	frame.rotation.y = _ry()
	add_child(frame)


# ---- stage 14: Servants' Stair - ride the haunted trunks up the stairwell over the rotten stairs ----

func _stage_14() -> Vector3:
	var e1: ManorPossessed = _possessed(Vector3(0, 0, -7.2), Vector3(2.4, 0.8, 2.4), "trunk", [Vector3.ZERO, Vector3(0, 5.0, 0)], 6.0, 0.0, 0.25)
	var l1: Dictionary = _blk(Vector3(0, 5.0, -12.7), 3.0, 3.0, "alt", 1.0, false)
	var b1: Dictionary = _boards(Vector3(0, 5.6, -17.2), 2.4, 2.4)
	var l2: Dictionary = _blk(Vector3(0, 6.2, -21.6), 3.0, 3.0, "alt", 1.0, false)
	var e2: ManorPossessed = _possessed(Vector3(0, 6.2, -26.3), Vector3(2.4, 0.8, 2.4), "trunk", [Vector3.ZERO, Vector3(0, 5.0, 0)], 6.0, 0.5, 0.25)
	var l3: Dictionary = _blk(Vector3(0, 11.2, -31.8), 3.0, 3.0, "alt", 1.0, false)
	_ledge(Vector3(0, 14.5, -37.4), Vector3(4.0, 26.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 14.5, -46.0))
	_room(-46.0, -11.0, 30.0)
	var top: float = 0.4
	_board(_w(Vector3(0, 0, -2.65)), e1, _w(Vector3(0, 0, -7.2)) - Vector3(0, top, 0), 0.35, Vector3(0, top, 0), 0.5)
	_leave(e1, _w(Vector3(0, 5.0, -7.2)) - Vector3(0, top, 0), 0.3, _w(Vector3(0, 5.0, -12.4)), Vector3(0, top, 0))
	_hop(l1, b1)
	_hop(b1, l2)
	_board(_w(Vector3(0, 6.2, -22.75)), e2, _w(Vector3(0, 6.2, -26.3)) - Vector3(0, top, 0), 0.35, Vector3(0, top, 0), 0.5)
	_leave(e2, _w(Vector3(0, 11.2, -26.3)) - Vector3(0, top, 0), 0.3, _w(Vector3(0, 11.2, -31.5)), Vector3(0, top, 0))
	r_mantle(_w(Vector3(0, 11.2, -32.95)), _w(Vector3(0, 14.5, -36.6)))
	_hop(_area(Vector3(0, 14.5, -37.4), 2.0, 1.7), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the old servants' bells on their springs, a dumbwaiter shaft, broken stairs down the walls
	var brass: StandardMaterial3D = Look.flat(ManorPossessed.BRASS, 0.35, 0.85)
	for i: int in 8:
		var bell := Look.cylinder(0.12, 0.2, brass, _w(Vector3(-6.6, 7.0 + float(i % 2) * 0.6, -10.0 - float(i) * 1.1)), 0.05, 10)
		add_child(bell)
	for i: int in 10:
		var step := Look.box(Vector3(1.6, 0.3, 1.1), Look.flat(ManorPossessed.WOOD, 0.8), _w(Vector3(5.4, -2.0 + float(i) * 1.6, -8.0 - float(i) * 3.2)))
		step.rotation = Vector3(0, _ry(), kit.rng.randf_range(-0.25, 0.25))
		add_child(step)
	b1.clear()
	return cp["c"]


# ---- stage 15: The Attic - rotten boards, a portrait's gaze, bobbing trunks [shortcut: the rafters] ----

func _stage_15() -> Vector3:
	var ba: Dictionary = _boards(Vector3(0, 0, -7.6), 2.4, 2.4)
	var bb: Dictionary = _blk(Vector3(1.0, 0.6, -12.2), 2.4, 2.4, "alt", 1.0, false)
	var f1: Dictionary = _blk(Vector3(0, 0.6, -21.0), 4.0, 10.0, "main", 1.0, false)
	var gaze: ManorGaze = _gaze(Vector3(-8.9, 0.6, -22.0), -1.0, 6.5, 0.4, 0.2, 10.5, 24.0)
	var t1: ManorPossessed = _possessed(Vector3(0, 0.9, -29.6), Vector3(2.4, 0.8, 2.2), "trunk", [Vector3.ZERO, Vector3(0, 0.8, 0)], 3.2, 0.0, 0.1)
	var t2: ManorPossessed = _possessed(Vector3(-0.6, 1.2, -34.2), Vector3(2.4, 0.8, 2.2), "trunk", [Vector3.ZERO, Vector3(0, 0.8, 0)], 3.2, 0.5, 0.1)
	var f2: Dictionary = _blk(Vector3(0, 1.2, -39.6), 4.0, 4.0, "main", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -48.6))
	_room(-48.6, -11.0, 9.5, false)
	_attic_roof(-48.6)
	# SHORTCUT: up onto a rafter over the portrait's gaze and along it to the far floor
	_ledge(Vector3(2.4, 3.9, -16.9), Vector3(1.2, 14.0, 1.2), "accent")
	kit.plat(_w(Vector3(2.4, 3.9, -26.6)), _sz(Vector3(1.0, 0.4, 18.2)), "accent", 0.0)
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -7.4)))
	_hop(ba, bb)
	_hop(bb, f1, Vector3(0, 0, 4.0))
	if route_variant == 2:
		r_walk(_w(Vector3(0.4, 0.6, -16.9)))
		r_mantle(_w(Vector3(0.5, 0.6, -16.9)), _w(Vector3(2.4, 3.9, -17.2)))
		r_walk(_w(Vector3(2.4, 3.9, -34.8)))
		r_jump(_w(Vector3(2.4, 3.9, -35.3)), _w(Vector3(1.0, 1.2, -38.4)))
	else:
		r_walk(_w(Vector3(0, 0.6, -16.4)))
		_wait(func() -> bool: return gaze.is_shut_for(Game.course_time, 0.0, 2.8), _w(Vector3(0, 0.6, -16.4)))
		r_walk(_w(Vector3(0, 0.6, -25.3)))
		r_jump_onto(_w(Vector3(0, 0.6, -25.65)), t1, Vector3(0, 0.4, 0))
		r_jump_onto(_w(Vector3(0, 0.9, -30.4)), t2, Vector3(0, 0.4, 0))
		r_jump(_w(Vector3(-0.4, 1.2, -35.0)), _w(Vector3(0, 1.2, -38.8)))
	_hop(f2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# junk under the eaves: trunks, a dressmaker's dummy, a rocking horse, sheeted furniture
	var sheet: StandardMaterial3D = Look.flat(Color(0.7, 0.68, 0.66), 0.95)
	for i: int in 6:
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var lump := Look.sphere(0.9, sheet, _w(Vector3(sx * 7.2, -9.8, -6.0 - float(i) * 6.5)))
		lump.scale = Vector3(1.2, 1.1, 1.0)
		add_child(lump)
	ba.clear()
	return cp["c"]


## The attic's steep roof over the stage: rafters, the slopes of slate with holes torn in them.
func _attic_roof(z1: float) -> void:
	var wood: StandardMaterial3D = Look.flat(ManorPossessed.WOOD_DARK, 0.85)
	var slate: StandardMaterial3D = Look.flat(ManorDecor.ROOF, 0.7, 0.2)
	var len: float = -z1 + 4.0
	for sx: float in [-1.0, 1.0]:
		for k: int in 3:
			var z: float = -2.0 - float(k) * len / 3.0 - len / 6.0
			var slab := Look.box(Vector3(10.0, 0.3, len / 3.0 - 1.5), slate, _w(Vector3(sx * 5.2, 13.0, z)))
			slab.basis = Basis(Vector3.UP, _ry()) * Basis(Vector3.BACK, sx * 0.62)
			add_child(slab)
	var n: int = int(len / 3.0)
	for i: int in n:
		var z2: float = -2.0 - float(i) * 3.0
		for sx: float in [-1.0, 1.0]:
			var r := Look.box(Vector3(10.4, 0.35, 0.3), wood, _w(Vector3(sx * 4.9, 13.6, z2)))
			r.basis = Basis(Vector3.UP, _ry()) * Basis(Vector3.BACK, sx * 0.62)
			add_child(r)


# ---- stage 16: The Rooftops - out through the dormer, along the ridges, run the chimney stack ----

func _stage_16() -> Vector3:
	var r1: Dictionary = _blk(Vector3(0, 0, -10.0), 1.4, 14.0, "alt", 1.0, false)
	kit.wallrun(_w(Vector3(2.5, 1.2, -26.5)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var s2: Dictionary = _blk(Vector3(-0.2, 0, -39.5), 3.6, 5.0, "main", 1.0, false)
	var pad_p := Vector3(-0.2, 0, -41.0)
	kit.pad(_w(pad_p), 21.0, 0.0, 0.0, 1.2)
	var r2: Dictionary = _blk(Vector3(-0.2, 5.8, -48.2), 4.0, 5.0, "main", 1.4, false)
	var cp: Dictionary = _cp(Vector3(0, 5.8, -57.8))
	# the roofs under the ridges (steep slate: you slide off), the chimney stack you run
	_roof(Vector3(0, 0, -10.0), 14.0, 7.0)
	_roof(Vector3(0, 0, -39.5), 8.0, 6.0)
	_roof(Vector3(-0.2, 5.8, -48.2), 7.0, 5.0)
	var stack := Look.box(Vector3(3.4, 18.0, 17.0), deco.wall_mat(Vector3(3.4, 18.0, 17.0), ManorDecor.WALL.darkened(0.1)), _w(Vector3(4.5, -3.0, -26.5)))
	stack.rotation.y = _ry()
	add_child(stack)
	for k: int in 4:
		var pot := Look.cylinder(0.5, 1.8, Look.flat(Color(0.35, 0.2, 0.16), 0.9), _w(Vector3(4.5, 6.9, -20.5 - float(k) * 4.0)), 0.42, 10)
		add_child(pot)
		ManorFx.ground_fog(self, _w(Vector3(4.5, 9.0, -20.5 - float(k) * 4.0)), Vector3(0.6, 1.0, 0.6), 4, Color(0.3, 0.26, 0.3, 0.35))
	for gz: float in [-18.4, -34.6]:
		deco.gargoyle(_w(Vector3(3.3, 6.0, gz)), _ry() + PI * 0.5, 1.1)
	r_walk(_w(Vector3(0, 0, -16.0)))
	r_wallrun(_w(Vector3(0.3, 0, -16.65)), _w(Vector3(2.0, 1.4, -20.6)), _w(Vector3(2.0, 1.4, -31.5)), _w(Vector3(-0.2, 0, -38.8)))
	r_walk(_w(pad_p + Vector3(0, 0, 1.4)))
	r_pad(_w(pad_p), _w((r2["c"] as Vector3) + Vector3(0, 0, 0.6)))
	_hop(r2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	add_child(ManorBats.make(_w(Vector3(0, 12.0, -30.0)), 10, Vector2(14, 10), 4.0, 1.0, 0.5))
	r1.clear()
	s2.clear()
	return cp["c"]


## A steep slate roof under a ridge walk: two solid slopes you slide off, down to the eaves.
func _roof(ridge_top: Vector3, length: float, half_span: float) -> void:
	var slate: StandardMaterial3D = Look.flat(ManorDecor.ROOF.lightened(0.05), 0.7, 0.2)
	var ang: float = deg_to_rad(52.0)
	var run: float = half_span / cos(ang)
	for sx: float in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(run, 0.4, length)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		body.add_child(Look.box(Vector3(run, 0.4, length), slate))
		# the slope's upper edge tucked under the ridge block, falling away to the side
		var c: Vector3 = ridge_top + Vector3(sx * (0.7 + half_span * 0.5), -1.2 - tan(ang) * half_span * 0.5, 0)
		body.basis = Basis(Vector3.UP, _ry()) * Basis(Vector3.BACK, -sx * ang)
		body.position = _w(c)
		add_child(body)


# ---- stage 17: The Bell Tower - mantle the buttresses, slip past the swinging bell ------------------

func _stage_17() -> Vector3:
	var b0: Dictionary = _blk(Vector3(0, 0, -8.5), 6.0, 4.0, "main", 1.0, true)
	_ledge(Vector3(0, 3.3, -14.2), Vector3(6.0, 5.5, 3.4))
	_ledge(Vector3(0, 6.6, -17.6), Vector3(3.6, 8.8, 3.4), "alt")
	var walk: Dictionary = _blk(Vector3(0, 6.6, -24.3), 2.4, 10.0, "alt", 1.0, true)
	var bell: Pendulum = _bell_swing(Vector3(0, 16.1, -24.7), 8.5, 6.0, 0.0)
	var l3: Dictionary = _blk(Vector3(0, 6.6, -33.0), 3.0, 3.0, "main", 1.0, true)
	_ledge(Vector3(0, 9.9, -38.0), Vector3(4.0, 12.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 9.9, -47.0))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), b0, Vector3(0, 0, 1.0))
	r_mantle(_w(Vector3(0, 0, -10.15)), _w(Vector3(0, 3.3, -13.3)))
	r_mantle(_w(Vector3(0, 3.3, -13.35)), _w(Vector3(0, 6.6, -16.8)))
	r_walk(_w(Vector3(0, 6.6, -20.2)))
	_wait(func() -> bool: return _bell_clear(bell, 0.2, 1.9), _w(Vector3(0, 6.6, -20.2)))
	r_walk(_w(Vector3(0, 6.6, -28.6)))
	_hop(walk, l3, Vector3(0, 0, 0.4))
	r_mantle(_w(Vector3(0, 6.6, -34.15)), _w(Vector3(0, 9.9, -37.2)))
	_hop(_area(Vector3(0, 9.9, -38.0), 2.0, 1.7), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the tower: a great round shaft of stone beside the climb, buttresses, a clock face
	deco.tower(_w(Vector3(14.0, -30.0, -26.0)), 5.5, 52.0, 14.0, 5)
	var face := Look.cylinder(2.2, 0.3, Look.flat(Color(0.85, 0.82, 0.7), 0.6, 0.0, 0.6), _w(Vector3(8.4, 14.0, -26.0)), -1.0, 32)
	face.basis = Basis(Vector3.UP, _ry()) * Basis(Vector3.BACK, PI * 0.5)
	add_child(face)
	for k: int in 2:
		var hand := Look.box(Vector3(0.1, 1.8 - 0.6 * float(k), 0.12), Look.flat(Color(0.05, 0.05, 0.05), 0.5), _w(Vector3(8.2, 14.4 - 0.2 * float(k), -26.0)))
		hand.basis = Basis(Vector3.UP, _ry()) * Basis(Vector3.RIGHT, 0.6 + 2.1 * float(k))
		add_child(hand)
	b0.clear()
	walk.clear()
	return cp["c"]


## The swinging bell: a pendulum whose head is a bronze bell, hung from a timber yoke over the
## buttress walk. It does not crush - it hurls you (the Pendulum rule) - but up here that is the same.
func _bell_swing(pivot: Vector3, length: float, period: float, phase: float) -> Pendulum:
	var p: Pendulum = kit.pendulum(_w(pivot), length, period, phase, _yaw, 55.0)
	var arm := p.get_child(0) as Node3D
	(arm.get_child(1) as Node3D).visible = false
	var bronze: StandardMaterial3D = Look.flat(Color(0.52, 0.37, 0.2), 0.35, 0.85)
	var head := Node3D.new()
	head.position = Vector3(0, -length + 0.9, 0)
	arm.add_child(head)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 1.2
	cm.height = 1.7
	cm.radial_segments = 24
	head.add_child(Look.mesh_node(cm, bronze, Vector3(0, -0.4, 0)))
	head.add_child(Look.sphere(0.55, bronze, Vector3(0, 0.45, 0)))
	head.add_child(Look.sphere(0.25, Look.flat(Color(0.2, 0.15, 0.1), 0.5, 0.8), Vector3(0, -1.2, 0)))
	var timber: StandardMaterial3D = deco.stone(ManorDecor.BARK.lightened(0.1))
	var axle := Look.box(Vector3(0.7, 0.7, 4.6), timber, _w(pivot + Vector3(0, 0.3, 0)))
	axle.rotation.y = _ry()
	add_child(axle)
	for sz: float in [-1.0, 1.0]:
		var beam := Look.box(Vector3(6.2, 0.6, 0.6), timber, _w(pivot + Vector3(0, 0.3, sz * 2.0)))
		beam.rotation.y = _ry()
		add_child(beam)
		for sx: float in [-1.0, 1.0]:
			var post := Look.box(Vector3(0.6, 44.0, 0.6), deco.stone(ManorDecor.STONE_DARK), _w(pivot + Vector3(sx * 2.8, -21.7, sz * 2.0)))
			post.rotation.y = _ry()
			add_child(post)
	_bells.append(p)
	return p


var _bells: Array[Pendulum] = []


## The bell's head stays well out to the side of the walk over [now + a, now + b].
static func _bell_clear(p: Pendulum, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if absf(sin(p.angle_at(Game.course_time + s))) * p.length < 3.4:
			return false
		s += 0.03
	return true


# ---- stage 18: The Belfry - phantom steps round the spire, the last wall run, the great bell ----

func _stage_18() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var mp: Array[Vector3] = [Vector3(0, 0, -8.6), Vector3(1.2, 0.6, -14.0), Vector3(-0.2, 1.2, -19.6)]
	var ps: Array[ManorPhantom] = []
	for i: int in mp.size():
		ps.append(_phantom(mp[i], 2.4, 2.2, "slab", 4.2, 0.62, fposmod(-0.2 * float(i), 1.0)))
	var l1: Dictionary = _blk(Vector3(0, 1.2, -28.85), 3.0, 7.1, "main", 1.0, true)
	var tw: LaserGate = _tripwire(Vector3(0, 1.2, -29.4), 3.2, 4.0, 0.4, 0.2, 2.4, true)
	kit.wallrun(_w(Vector3(2.3, 2.4, -42.0)), Vector3(16.0, 6.5, 0.5), _yaw + 90.0)
	var d: Dictionary = _blk(Vector3(-0.4, 1.2, -57.2), 3.6, 5.0, "alt", 1.0, true)
	_ledge(Vector3(0, 4.5, -63.4), Vector3(8.0, 7.0, 3.4))
	var dais: Dictionary = _blk(Vector3(0, 4.5, -71.1), 14.0, 12.0, "main", 1.6, true)
	kit.finish(_w(Vector3(0, 4.5, -72.0)), _yaw)
	_finish_pos = _w(Vector3(0, 4.5, -72.0))
	_belfry(Vector3(0, 4.5, -71.1))
	# the spire wall behind the run panel
	var back := Look.box(Vector3(0.8, 12.0, 17.0), deco.wall_mat(Vector3(0.8, 12.0, 17.0), ManorDecor.WALL), _w(Vector3(2.95, 2.4, -42.0)))
	back.rotation.y = _ry()
	add_child(back)
	for z: float in [-36.0, -48.0]:
		deco.window(_w(Vector3(2.55, 8.6, z)), _ry() - PI * 0.5, 1.2, 2.6, int(absf(z)), false)
	var p0: ManorPhantom = ps[0]
	var p1: ManorPhantom = ps[1]
	var p2: ManorPhantom = ps[2]
	_wait(func() -> bool: return p0.is_on_for(Game.course_time, 1.02, 2.47) and p1.is_on_for(Game.course_time, 1.86, 3.31) and p2.is_on_for(Game.course_time, 2.69, 4.14))
	var prev: Dictionary = cp0
	for i: int in mp.size():
		var m: Dictionary = _area(mp[i], 1.2, 1.1)
		_hop(prev, m)
		prev = m
	_hop(prev, l1, Vector3(0, 0, 2.3))
	r_walk(_w(Vector3(0, 1.2, -27.8)))
	_wait(func() -> bool: return _dark(tw, 0.05, 1.6), _w(Vector3(0, 1.2, -27.8)))
	r_walk(_w(Vector3(0, 1.2, -31.0)))
	r_wallrun(_w(Vector3(0.3, 1.2, -32.05)), _w(Vector3(1.8, 2.6, -36.0)), _w(Vector3(1.8, 2.6, -46.9)), _w(Vector3(-0.4, 1.2, -56.4)))
	r_mantle(_w(Vector3(0, 1.2, -59.35)), _w(Vector3(0, 4.5, -62.6)))
	r_walk(_w(Vector3(0, 4.5, -68.0)))
	r_walk(_w(Vector3(0, 4.5, -72.4)))
	d.clear()
	dais.clear()


var _great_bell: Node3D


## The belfry over the finish: four stone piers, arches, a pointed spire, the great bell hanging
## in the middle, candles round the dais, gargoyles at the corners, the blood moon behind.
func _belfry(c: Vector3) -> void:
	var st: ShaderMaterial = deco.wall_mat(Vector3(1.4, 14.0, 1.4), ManorDecor.WALL)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var pier := Look.box(Vector3(1.4, 14.0, 1.4), st, _w(c + Vector3(sx * 6.2, 7.0, sz * 5.2)))
			pier.rotation.y = _ry()
			add_child(pier)
			deco.gargoyle(_w(c + Vector3(sx * 6.2, 14.0, sz * 5.2)), _ry() + atan2(sx, sz), 1.2)
	var roof_base := Look.box(Vector3(14.6, 1.0, 12.6), deco.stone(ManorDecor.STONE_DARK), _w(c + Vector3(0, 14.5, 0)))
	roof_base.rotation.y = _ry()
	add_child(roof_base)
	var spire := Look.cylinder(8.0, 16.0, Look.flat(ManorDecor.ROOF, 0.6, 0.3), _w(c + Vector3(0, 23.0, 0)), 0.0, 4)
	spire.rotation.y = _ry() + PI * 0.25
	add_child(spire)
	_great_bell = deco.bell(_w(c + Vector3(0, 13.9, -0.9)), 2.2)
	for k: int in 6:
		var a: float = TAU * float(k) / 6.0
		deco.candelabra(_w(c + Vector3(cos(a) * 5.0, 0, sin(a) * 4.2)), 1.3, k % 2 == 0, ECTO if k % 2 == 0 else CANDLE)
	ManorFx.rising(self, _w(c + Vector3(0, 0.1, 0)), 4.5, 8.0, ECTO, 36)
	ManorFx.petals(self, _w(c + Vector3(0, 9.0, 0)), _sz(Vector3(6.0, 3.0, 5.0)), 30)


# ---- rooms ----------------------------------------------------------------------------------------

## The indoor room round the current stage, from its start (local z 0) to its checkpoint at local
## `cp_z`: walls of old masonry at x = +-hw (hw per stage, ROOM_HW) standing from the cellar floor
## `floor_y` up to `top_y`, stained-glass windows and candle sconces along them, rafters overhead
## with the moon showing between them, and far below the cellar where the floor fell in (an
## invisible catch net: a fall down there is a fall). Where the route turns, each wall is cut
## back or run on so the rooms meet in clean corners.
func _room(cp_z: float, floor_y: float, top_y: float, lamps: bool = true) -> void:
	var hw: float = ROOM_HW[_stage_no]
	var prev_hw: float = float(ROOM_HW.get(_stage_no - 1, 4.0)) + 1.4
	var next_hw: float = float(ROOM_HW.get(_stage_no + 1, 4.0)) + 1.4
	var d_in: float = wrapf(_yaw - _prev_yaw, -180.0, 180.0)
	var d_out: float = wrapf(_next_yaw - _yaw, -180.0, 180.0)
	# per side (-1 left, +1 right): where its wall starts and ends along local z
	var zs: Dictionary = {-1: 0.0, 1: 0.0}
	var ze: Dictionary = {-1: cp_z, 1: cp_z}
	if not ROOM_HW.has(_stage_no - 1):
		zs = {-1: 2.0, 1: 2.0}
	if absf(d_in) > 1.0:
		var inner: int = -1 if d_in > 0.0 else 1
		zs[inner] = -prev_hw
		zs[-inner] = prev_hw
	if not ROOM_HW.has(_stage_no + 1) and absf(d_out) <= 1.0:
		ze = {-1: cp_z - 2.0, 1: cp_z - 2.0}
	if absf(d_out) > 1.0:
		var inner2: int = -1 if d_out > 0.0 else 1
		ze[inner2] = cp_z + next_hw
		ze[-inner2] = cp_z - next_hw
	var h: float = top_y - floor_y
	var col: Color = ManorDecor.WALL
	for side: int in [-1, 1]:
		var z0: float = zs[side]
		var z1: float = ze[side]
		var len: float = z0 - z1
		if len < 0.5:
			continue
		var x: float = float(side) * (hw + 0.7)
		deco.wall(_w(Vector3(x, floor_y + h * 0.5, (z0 + z1) * 0.5)), _sz(Vector3(1.4, h, len)), 0.0, col, true)
		# windows high up and sconces lower down, alternating along the wall
		var n: int = maxi(int(len / 9.0), 1)
		for i: int in n:
			var z: float = z0 - (float(i) + 0.5) * len / float(n)
			var wy: float = minf(top_y - 5.0, 7.5)
			deco.window(_w(Vector3(float(side) * (hw + 0.02), wy, z)), _ry() + (PI * 0.5 if side < 0 else -PI * 0.5), 1.8, 4.2, _stage_no * 3 + i, i % 2 == 0)
			if lamps and (i % 2 == 1 or n == 1):
				_sconce(Vector3(float(side) * (hw - 0.15), 3.2, z + len / float(n) * 0.35), side)
	# rafters overhead
	var zmax: float = maxf(zs[-1], zs[1])
	var zmin: float = minf(ze[-1], ze[1])
	var span: float = zmax - zmin
	var nb: int = maxi(int(span / 6.0), 1)
	var beam_m: StandardMaterial3D = Look.flat(ManorPossessed.WOOD_DARK, 0.85)
	for i: int in nb + 1:
		var z: float = zmax - float(i) * span / float(nb)
		var b := Look.box(Vector3(hw * 2.0 + 2.8, 0.9, 0.9), beam_m, _w(Vector3(0, top_y + 0.45, z)))
		b.rotation.y = _ry()
		add_child(b)
	# the cellar: a dark floor far below with the catch net just above it
	var pm := PlaneMesh.new()
	pm.size = Vector2(hw * 2.0, span)
	var cellar := Look.mesh_node(pm, Look.flat(Color(0.05, 0.04, 0.05), 1.0), _w(Vector3(0, floor_y, (zmax + zmin) * 0.5)))
	cellar.rotation.y = _ry()
	cellar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cellar)
	var net := KillZone.new()
	net.show_mesh = false
	net.size = _sz(Vector3(hw * 2.0, 1.0, span))
	net.position = _w(Vector3(0, floor_y + 1.5, (zmax + zmin) * 0.5))
	add_child(net)
	# air: dust in the candlelight, ghost-lights rising out of the cellar, fog down in it
	var mid: float = (zmax + zmin) * 0.5
	ManorFx.dust(self, _w(Vector3(0, 4.0, mid)), _sz(Vector3(hw * 0.8, 5.0, span * 0.45)), 40)
	ManorFx.ghost_motes(self, _w(Vector3(0, floor_y + 5.0, mid)), _sz(Vector3(hw * 0.8, 4.0, span * 0.45)), 30)
	ManorFx.ground_fog(self, _w(Vector3(0, floor_y + 2.0, mid)), _sz(Vector3(hw * 0.8, 1.5, span * 0.45)), 10, Color(0.4, 0.36, 0.5, 0.35))


## A wall sconce: an iron bracket with two candles (a flame, and every other one a light).
func _sconce(at: Vector3, side: int) -> void:
	var p: Vector3 = _w(at)
	var iron: StandardMaterial3D = Look.flat(ManorDecor.IRON, 0.5, 0.7)
	var arm := Look.box(Vector3(0.6, 0.08, 0.08), iron, p)
	arm.rotation.y = _ry()
	add_child(arm)
	var inward: Vector3 = _d(Vector3(-float(side) * 0.3, 0, 0))
	add_child(Look.cylinder(0.05, 0.3, Look.flat(Color(0.88, 0.86, 0.78), 0.6), p + inward + Vector3(0, 0.18, 0), -1.0, 6))
	ManorFx.flame(self, p + inward + Vector3(0, 0.38, 0), 0.8, CANDLE)
	_sconces += 1
	if _sconces % 2 == 0:
		var o := OmniLight3D.new()
		o.light_color = CANDLE
		o.light_energy = 1.4
		o.omni_range = 8.0
		o.shadow_enabled = false
		o.position = p + inward * 2.0 + Vector3(0, 0.5, 0)
		add_child(o)


var _sconces: int = 0


# ---- environment ----------------------------------------------------------------------------------

func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_moon = n as DirectionalLight3D
			else:
				_fill = n as DirectionalLight3D
	_env.background_mode = Environment.BG_SKY
	_env.sky = ManorSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.44, 0.7)
	_env.ambient_light_energy = 0.62
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.15
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.2, 0.14, 0.26)
	_env.fog_density = 0.0055
	_env.fog_aerial_perspective = 0.3
	_env.fog_sky_affect = 0.1
	_env.fog_sun_scatter = 0.35
	_env.fog_height = -8.0
	_env.fog_height_density = 0.06
	_env.glow_enabled = true
	_env.glow_intensity = 0.75
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.1
	# the key light is the blood moon: red, low, ahead of the route
	_moon.basis = Basis.looking_at(-MOON_DIR.normalized(), Vector3.UP)
	_moon.light_color = Color(1.0, 0.5, 0.44)
	_moon.light_energy = 1.3
	_moon.shadow_blur = 0.8
	_moon.light_angular_distance = 1.5
	# the "fill" becomes a cold violet skylight from the other side
	_fill.light_color = Color(0.55, 0.5, 0.95)
	_fill.light_energy = 0.45
	_fill.rotation_degrees = Vector3(-55, -30, 0)


## Swap every walkable surface to the manor shader (same colours): flagstones outside, oak
## boards inside. `ranges` = [stage, first child, end child] per stage.
func _manor_materials(ranges: Array) -> void:
	var wood_nodes: Dictionary = {}
	for r: Array in ranges:
		if not _indoor.has(int(r[0])):
			continue
		for i: int in range(int(r[1]), int(r[2])):
			if i < get_child_count():
				wood_nodes[get_child(i)] = true
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = SURFACE_SHADER
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		r.set_shader_parameter("trim_glow", maxf(float(sm.get_shader_parameter("trim_glow")), 0.45))
		var n: Node = m
		var wood: float = 0.0
		while n != null and n != self:
			if wood_nodes.has(n):
				wood = 1.0
				break
			n = n.get_parent()
		r.set_shader_parameter("wood", wood)
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
	return pts


func _clear_of(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist:
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
	var valley_y: float = -30.0
	# the valley floor: dark earth far below, in the fog
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * (maxf(span.x, span.z) + 1400.0)
	var ground := Look.mesh_node(pm, Look.flat(Color(0.05, 0.045, 0.06), 1.0), Vector3(mid.x, valley_y, mid.z))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	# graves, mausoleums and dead trees down in the valley round the course
	var placed: int = 0
	var tries: int = 0
	while placed < 70 and tries < 600:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 90.0, hi.x + 90.0), valley_y, rng.randf_range(lo.z - 90.0, hi.z + 90.0))
		if not _clear_of(p, pts, 9.0):
			continue
		var roll: float = rng.randf()
		if roll < 0.6:
			deco.tombstone(p, rng.randf() * TAU, -1, rng.randf_range(1.2, 2.2))
		elif roll < 0.8:
			deco.dead_tree(p, rng.randf_range(12.0, 24.0), rng.randf() * TAU)
		else:
			deco.mausoleum(p, rng.randf() * TAU, rng.randf_range(4.0, 7.0), rng.randf_range(5.0, 8.0), rng.randf_range(5.0, 9.0))
		placed += 1
	# the manor on its hill, far off to one side, and its towers against the sky
	deco.manor(Vector3(mid.x - 190.0, valley_y + 10.0, mid.z - 120.0), deg_to_rad(40.0), 1.6)
	deco.tower(Vector3(mid.x + 160.0, valley_y, mid.z - 200.0), 7.0, 70.0, 26.0, 5, 0.03)
	deco.tower(Vector3(mid.x - 240.0, valley_y, mid.z + 60.0), 6.0, 55.0, 20.0, 4, -0.05)
	for i: int in 6:
		var a: float = rng.randf() * TAU
		deco.cliff(Vector3(mid.x + cos(a) * 260.0, valley_y + 10.0, mid.z + sin(a) * 260.0), Vector3(90, 70, 50), rng.randf() * TAU)
	# bats wheeling across the face of the moon, and round the course
	add_child(ManorBats.make(mid + MOON_DIR.normalized() * 240.0 + Vector3(0, 10, 0), 18, Vector2(45, 20), 25.0, 4.0, 0.2))
	add_child(ManorBats.make(mid + Vector3(0, 30, 0), 12, Vector2(70, 50), 10.0, 1.4, 0.3))
	# ambient life along the whole route: rolling ground fog, will-o'-wisps, dead leaves
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c2: Vector3 = (here + prev) * 0.5 + Vector3(0, 2.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 6.0, absf(here.z - prev.z) * 0.5 + 12.0)
		ManorFx.ground_fog(self, c2 + Vector3(0, -9.0, 0), ext + Vector3(16, 3, 16), 16)
		ManorFx.wisps(self, c2 + Vector3(0, -3.0, 0), ext, 16)
		ManorFx.leaves(self, c2 + Vector3(0, 2.0, 0), ext * 0.8, 26)


# ---- live effects -----------------------------------------------------------------------------------

## The night deepens as you go: the fog turns from bruised violet to blood, and the moonlight
## grows stronger and redder as you climb from the graveyard to the belfry.
const FOG_A := Color(0.2, 0.14, 0.26)
const FOG_B := Color(0.3, 0.1, 0.16)
const MOON_A := Color(1.0, 0.5, 0.44)
const MOON_B := Color(1.0, 0.36, 0.3)

var _night: float = 0.0
var _bell_eta: Array[float] = []


func _process(dt: float) -> void:
	if player == null:
		return
	if _env != null:
		var target: float = clampf(float(current_checkpoint) / float(maxi(checkpoints.size(), 1)), 0.0, 1.0)
		_night = move_toward(_night, target, dt * 0.06)
		_env.fog_light_color = FOG_A.lerp(FOG_B, _night)
		_moon.light_color = MOON_A.lerp(MOON_B, _night)
		_moon.light_energy = lerpf(1.3, 1.6, _night)
	for e: Dictionary in _arrivals:
		e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
		if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
			e["cool"] = 3.0
			for p: GPUParticles3D in e["p"]:
				p.restart()
				p.emitting = true
			WorldAudio.at(self, "manor_mirror_chime", e["at"], 0.9, 30.0)
	if not WorldAudio.enabled():
		return
	# the coffin lids bang shut (on top of the press's own slam)
	if _coffin_u.size() != _coffins.size():
		_coffin_u.resize(_coffins.size())
		_coffin_u.fill(0.0)
	for i: int in _coffins.size():
		var c: Crusher = _coffins[i]
		var u: float = fposmod(Game.course_time / c.period + c.phase, 1.0)
		if _coffin_u[i] < Crusher.SLAM and u >= Crusher.SLAM:
			WorldAudio.at(c, "manor_coffin_slam", c.global_position, 1.0, 36.0)
		_coffin_u[i] = u
	# the swinging bell tolls as it reaches the top of its swing on one side
	if _bell_eta.size() != _bells.size():
		_bell_eta.resize(_bells.size())
		_bell_eta.fill(-1.0)
	for i: int in _bells.size():
		var b: Pendulum = _bells[i]
		var eta: float = b.period - fposmod(Game.course_time + (b.phase - 0.25) * b.period, b.period)
		if _bell_eta[i] >= 0.0 and eta > _bell_eta[i] + 0.5:
			WorldAudio.at(b, "manor_bell_toll", b.global_position, 1.0, 70.0)
		_bell_eta[i] = eta


## The belfry goes off: the great bell swings and tolls, ectoplasm and violet sparks burst from the
## dais, a green-and-red flash lights the spire, and the bats pour out across the moon.
func _finish_sequence() -> void:
	var cols: Array[Color] = [ECTO, VIOLET, BLOOD]
	for i: int in 3:
		var b: GPUParticles3D = ManorFx.glints(self, _finish_pos + Vector3(0, 1.0 + float(i) * 1.3, 0), cols[i], 70, 9.0 + 2.0 * float(i))
		b.restart()
		b.emitting = true
	var s: GPUParticles3D = ManorFx.ecto_burst(self, _finish_pos + Vector3(0, 0.4, 0), 2.5, 60, 9.0)
	s.restart()
	s.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.6, 1.0, 0.65)
	flash.light_energy = 8.0
	flash.omni_range = 26.0
	flash.position = _finish_pos + Vector3(0, 5.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_color", Color(1.0, 0.3, 0.25), 0.7)
	tw.parallel().tween_property(flash, "light_energy", 0.0, 1.4)
	WorldAudio.at(self, "manor_bell_toll", _finish_pos + Vector3(0, 10.0, 0), 1.0, 80.0)
	if _great_bell != null:
		var tw2: Tween = create_tween()
		var yaw: float = _great_bell.rotation.y
		for k: int in 3:
			var a: float = 0.35 * (1.0 - 0.3 * float(k))
			tw2.tween_property(_great_bell, "rotation", Vector3(a, yaw, 0), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw2.tween_property(_great_bell, "rotation", Vector3(-a, yaw, 0), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw2.tween_property(_great_bell, "rotation", Vector3(0, yaw, 0), 0.4).set_trans(Tween.TRANS_SINE)
	var bats: ManorBats = ManorBats.make(_finish_pos + Vector3(0, 12.0, -6.0), 24, Vector2(10, 8), 4.0, 1.0, 1.4)
	add_child(bats)
	await get_tree().create_timer(0.9).timeout
