extends LevelBase
## 30. DINO VALLEY (campaign index 20) - a lush prehistoric valley in warm morning sun, a smoking
## volcano on the horizon, herds grazing far below the sandstone stacks you leap between. Seventeen
## stages, sixteen checkpoints, HARD tier: precision hops onto 1.2-1.6 m landings at 85-90% of max
## reach, with the valley's own machines (geysers, tar pits, a stampede lane, pterodactyl and
## brontosaurus rides) and the generic kit (rolling logs, a vine zipline, falling boulders, a log
## seesaw, a club-tailed ankylosaur) between them, ending on the T-REX CHASE.
##
##  1 Hatchery Shore    the nest island, four stones across the shallows, a fallen trunk, MANTLE the
##                      great boulder
##  2 Log Jam           two ROLLING LOGS (kit) turning across the river in turn
##  3 Geyser Terraces   a GEYSER holds you up to the first terrace, a second lifts you to the cliff
##                      [shortcut: MANTLE the 4 m cliff]
##  4 Vine Gorge        ride the VINE ZIPLINE (kit) across the gorge, three fern-tops
##                      [shortcut: two WALL RUNS along the gorge walls]
##  5 Tar Fields        BRANCH: wade the TAR PITS | WALL RUN the mammoth's ribs and MANTLE its skull
##                      [shortcut: four bone stakes down the middle at 92%]
##  6 Stampede Flats    two STAMPEDE lanes with a tail-flame vent (LASER) between them
##  7 Pterodactyl Pass  ride a PTERODACTYL over the canyon, WALL RUN the far cliff
##  8 Horn Ledge        the TRICERATOPS charge (PISTONS) along a narrow ledge, MANTLE the rock shelf
##  9 Bronto Crossing   BRANCH: ride the BRONTOSAURUS NECK up to the cliff | hop the vertebrae and
##                      MANTLE out [shortcut: the hollow log (PORTAL)]
## 10 Stomp Hall        the giant FOOT (CRUSHER) stamping the canyon floor, a log SEESAW (kit), WALL RUN
## 11 Boulder Slope     FALLING BOULDERS (kit) down the volcano's flank, then WALL RUN the ash cliff
## 12 Burrow Maze       BRANCH: through the BURROW (portal) to the ledge | the flame vents (LASERS)
##                      and fern-tops [shortcut: a 94% leap to the nest ledge]
## 13 Club Tail         an ANKYLOSAUR's spinning tail (HAMMER, kit) on the round rock, MANTLE out
## 14 Second Springs    a PTERODACTYL over the tar, a GEYSER up the cliff [shortcut: 94% stakes]
## 15 Canyon Rim        a long chain of stacks at 86-89% with a STAMPEDE lane between, a chimney of WALL RUNS
## 16 The Egg Gate      tar stones and a geyser to the canyon mouth: the last checkpoint
## 17 THE CHASE         SET PIECE: step over the line and the T-REX comes out of the canyon behind you.
##                      Run the canyon floor ahead of it (jump the logs and gaps), MANTLE the nest
##                      cliff: the finish, a clutch of eggs.
##
## Dino mechanics (own scripts): DinoGeyser (a water jet that holds you aloft), DinoTar (a slowing,
## sinking pit), DinoStampede (a herd across a lane), DinoRex (the chase). Visuals: visual/dino_*.gd.
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every
## shortcut. Every wait the bot makes holds for 1.5 s more.

const GOLD := Color(1.0, 0.74, 0.28)
const ORANGE := Color(1.0, 0.5, 0.12)
const TEAL := Color(0.25, 0.82, 0.72)
const BONE := Color(0.93, 0.9, 0.78)
const FERN := Color(0.3, 0.55, 0.16)

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable surface (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _floors: Array[Dictionary] = []
## Stage frames (origin, yaw) for the scenery.
var _stage_frames: Array[Array] = []


func _configure() -> void:
	theme_id = "dino"
	music_track = "dino"
	kill_y = -90.0
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


## A walkable stack top (local top centre `c`, sx across, sz along).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.9, keel: float = 0.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw)
	_floors.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": thick})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A small stone / fern-top / bone stake (a landing about a metre and a quarter across).
func _post(c: Vector3, sx: float = 1.3, sz: float = 1.3, style: String = "accent") -> Dictionary:
	return _blk(c, sx, sz, style, 0.7)


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	_floors.append({"top": _w(top), "size": _sz(Vector3(size.x, 0, size.z)), "drop": size.y})
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


## The validator's max reach (m) for a plain running jump that lands `dy` higher (test_m's measure).
func _reach(dy: float) -> float:
	var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, _tuning.jump_velocity, -_tuning.max_speed), dy)
	return absf(land.z)


## Local top centre of a landing `sz` deep straight ahead (-z) of `a`, placed so that the jump from
## 0.35 m inside a's front edge needs `pct` of max reach by test_m's measure (to 0.4 m past the near
## edge, scanned in 0.2 m steps: rounded up, so it needs `pct` to `pct` + 3%).
func _ahead(a: Dictionary, pct: float, dy: float, sz: float, dx: float = 0.0) -> Vector3:
	var ac: Vector3 = a["c"]
	var front: float = ac.z - float(a["hz"])
	var m: float = (pct - 0.02) * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	var e: float = float(k) * 0.2 - 0.03
	return Vector3(ac.x + dx, ac.y + dy, front + 0.35 - e - sz * 0.5)


## Checkpoint slab facing the next stage's heading (_next_yaw).
func _cp(c: Vector3, size: float = 5.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.2)
	kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	return d


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

## Stand still until test() is true (a wait: the 1.0 s human-pause check applies after it).
func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Run to `from`, jump, and fly (position-hold steering) to `to`: for arcs a column bends.
func _fly(from: Vector3, to: Vector3, gain: float = 1.6, damp: float = 0.45) -> void:
	route.append({"kind": "desert_fly", "jump_from": from, "to": to, "gain": gain, "damp": damp})


## True when test(t) holds at every course time t in [now + a, now + b].
static func _ok(test: Callable, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not bool(test.call(Game.course_time + s)):
			return false
		s += 0.04
	return true


static func _dark(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


static func _ram_clear(p: Piston, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.04
	return true


static func _press_ok(c: Crusher, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if c.gap_at(Game.course_time + s) < 2.2 or not c.is_clear_for(Game.course_time + s, 0.0):
			return false
		s += 0.04
	return true


## Where a mover's offsets are measured from (world).
static func _home(m: MovingPlatform) -> Vector3:
	return m.position - m.offset_at(Game.course_time)


## A MovingPlatform stays within `r` of its offset `at` (world offset) over [now + a, now + b].
static func _mover_at(m: MovingPlatform, at: Vector3, r: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if m.offset_at(Game.course_time + s).distance_to(at) > r:
			return false
		s += 0.05
	return true


## A jump onto moving `node` (landing at its local `off`) that fires once test() is true.
func _board(from: Vector3, node: Node3D, off: Vector3, test: Callable) -> void:
	route.append({"kind": "h_jump", "from": from, "to_node": node, "to_local": off, "test": test})


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16]
	var last: int = stages.size() if DEV_LAST <= 0 else mini(DEV_LAST, stages.size())
	var starts: Array[int] = []
	var origins: Array[Vector3] = []
	_frame(Vector3.ZERO, yaws[0])
	for i: int in last:
		_next_yaw = yaws[i + 1]
		starts.append(route.size())
		origins.append(_o)
		_stage_frames.append([_o, _yaw])
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	starts.append(route.size())
	origins.append(_o)
	if last == stages.size():
		_stage_17()
	else:
		_dev_finish()
	_surroundings()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


func _dev_finish() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "main", 1.2)
	kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
	_finish_pos = _w(Vector3(0, 0, -9.5))
	_hop(cp0, fin)
	r_walk(_w(Vector3(0, 0, -9.8)))


# ---- stage 1: Hatchery Shore - four stones across the shallows, a trunk, mantle the boulder ------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(12, 2, 12), "main", 0.0, _yaw)
	_floors.append({"top": _w(Vector3.ZERO), "size": Vector3(12, 0, 12), "drop": 2.0})
	var start: Dictionary = _area(Vector3(0, 0, 0), 6.0, 6.0)
	var p1: Dictionary = _post(_ahead(start, 0.86, 0.0, 1.4), 1.4, 1.4)
	var p2: Dictionary = _post(_ahead(p1, 0.87, 0.5, 1.3, 0.4))
	var p3: Dictionary = _post(_ahead(p2, 0.88, 0.0, 1.3, -0.4))
	var trunk: Dictionary = _blk(_ahead(p3, 0.86, 0.0, 4.0, 0.0), 1.4, 4.0, "alt", 0.7)
	var tc: Vector3 = trunk["c"]
	var front: float = tc.z - 2.0
	var rock_top := Vector3(tc.x, tc.y + 3.3, front - 1.6 - 0.8)
	var rock: Dictionary = _ledge(rock_top, Vector3(2.8, 9.0, 1.6))
	var cp: Dictionary = _cp(_ahead(rock, 0.85, 0.0, 5.0, -tc.x))
	_hop(start, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, trunk, Vector3(0, 0, 1.0))
	r_walk(_w(Vector3(tc.x, tc.y, front + 0.9)))
	r_mantle(_w(Vector3(tc.x, tc.y, front + 0.35)), _w(rock_top + Vector3(0, 0, 0.2)))
	_hop(rock, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Log Jam - two rolling logs across the river -----------------------------------------

## A rolling log along the course: `top` is the local centre of its top line, `len` m long. The roll
## pushes you sideways (the log turns across the course) and slows to a stop before it reverses.
func _log(top: Vector3, len: float, phase: float) -> RollingLog:
	var lg: RollingLog = kit.log_roller(_w(top), len, 2.4, _yaw + 90.0, 2.6, 8.0, phase)
	_floors.append({"top": _w(top), "size": _sz(Vector3(2.0, 0, len)), "drop": 2.4})
	return lg


func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var a: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 3.0), 3.4, 3.0)
	var ac: Vector3 = a["c"]
	var len1: float = 11.0
	var l1_top := Vector3(ac.x, ac.y, ac.z - 1.5 - 0.15 - len1 * 0.5)
	_log(l1_top, len1, 0.0)
	var b: Dictionary = _blk(Vector3(ac.x, ac.y, l1_top.z - len1 * 0.5 - 0.15 - 1.5), 3.4, 3.0)
	var c: Dictionary = _blk(_ahead(b, 0.87, 0.0, 3.0, 0.3), 3.4, 3.0)
	var cc: Vector3 = c["c"]
	var l2_top := Vector3(cc.x, cc.y, cc.z - 1.5 - 0.15 - len1 * 0.5)
	_log(l2_top, len1, 0.5)
	var cp: Dictionary = _cp(Vector3(cc.x, cc.y, l2_top.z - len1 * 0.5 - 0.15 - 2.5))
	_hop(cp0, a)
	r_walk(_w(Vector3(ac.x, ac.y, ac.z - 1.6)))
	r_walk(_w(Vector3(l1_top.x, l1_top.y, l1_top.z + len1 * 0.5 - 0.5)))
	r_walk(_w(Vector3(l1_top.x, l1_top.y, l1_top.z - len1 * 0.5 + 0.3)))
	r_walk(_w(Vector3(ac.x, ac.y, (b["c"] as Vector3).z)))
	_hop(b, c)
	r_walk(_w(Vector3(cc.x, cc.y, cc.z - 1.6)))
	r_walk(_w(Vector3(l2_top.x, l2_top.y, l2_top.z + len1 * 0.5 - 0.5)))
	r_walk(_w(Vector3(l2_top.x, l2_top.y, l2_top.z - len1 * 0.5 + 0.3)))
	r_walk(_w(cp["c"] as Vector3))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Geyser Terraces - a geyser holds you up to each terrace -----------------------------

const GEYSER_HEIGHT: float = 5.6

## A geyser on the vent slab `slab` (the floor point under it is the slab's top centre).
func _geyser(slab: Dictionary, period: float, phase: float) -> DinoGeyser:
	var g := DinoGeyser.new()
	g.height = GEYSER_HEIGHT
	g.period = period
	g.phase = phase
	g.position = _w(slab["c"] as Vector3)
	add_child(g)
	return g


## Bot: stand on the vent, wait for the jet to hold us up, then fly to `to` (world) and land.
func _ride_geyser(g: DinoGeyser, to: Vector3) -> void:
	var vent: Vector3 = g.position
	r_walk(vent)
	# arriving mid-eruption: let this one die down and take the next from the start
	_wait(func() -> bool: return not g.is_erupting_at(Game.course_time), vent)
	var top_y: float = vent.y + GEYSER_HEIGHT - 0.7
	route.append({"kind": "desert_fly", "to": vent, "until": func() -> bool: return player.global_position.y > top_y})
	route.append({"kind": "desert_fly", "to": to})


func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var g1s: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 4.0), 4.0, 4.0)
	var g1c: Vector3 = g1s["c"]
	var t1: Dictionary = _blk(g1c + Vector3(0, 3.4, -5.4), 4.4, 4.4, "alt")
	var t2: Dictionary = _blk(_ahead(t1, 0.87, 0.4, 4.0), 4.4, 4.4)
	var t2c: Vector3 = t2["c"]
	var cp: Dictionary = _cp(t2c + Vector3(0, 3.4, -6.0))
	var g1: DinoGeyser = _geyser(g1s, 8.0, 0.0)
	var g2: DinoGeyser = _geyser(t2, 8.6, 0.35)
	# SHORTCUT: a shelf to the right of the vent and a 3.4 m mantle up onto the first terrace's side
	var sh: Dictionary = _blk(g1c + Vector3(6.2, 0, 1.5), 3.0, 3.0, "accent", 0.9)
	var mtop: Vector3 = (sh["c"] as Vector3) + Vector3(0, 3.4, -1.5 - 1.6 - 0.8)
	var m: Dictionary = _ledge(mtop, Vector3(3.0, 9.0, 1.6))
	_hop(cp0, g1s)
	if route_variant == 2:
		_hop(g1s, sh)
		r_mantle(_w(Vector3((sh["c"] as Vector3).x, (sh["c"] as Vector3).y, (sh["c"] as Vector3).z - 0.9 - 0.4)), _w(mtop + Vector3(0, 0, 0.2)))
		_hop(m, t1)
	else:
		_ride_geyser(g1, _w(t1["c"] as Vector3))
	_hop(t1, t2)
	_ride_geyser(g2, _w(cp["c"] as Vector3))
	r_checkpoint()
	g1.set_meta("n", 1)
	g2.set_meta("n", 2)
	return cp["c"]


# ---- stage 4: Vine Gorge - ride the vine zipline over the gorge, three fern-tops ------------------
# [shortcut: two wall runs along the gorge walls]

## The kit zipline, dressed as a jungle vine: a green rope between two leaning fern-palm trunks, the
## trolley a knotted loop. (Kit machines keep their logic; only the metal is swapped for plants.)
func _vine(start_floor: Vector3, end_floor: Vector3) -> Zipline:
	var z: Zipline = kit.zipline(_w(start_floor), _w(end_floor), 11.0, 1.6, 0.0)
	var vine: StandardMaterial3D = Look.flat(Color(0.28, 0.46, 0.14), 0.85)
	var cable: MeshInstance3D = z.get("_cable") as MeshInstance3D
	if cable != null:
		cable.material_override = vine
	var bark: StandardMaterial3D = Look.flat(Color(0.4, 0.28, 0.17), 0.95)
	var leaf: StandardMaterial3D = Look.flat(FERN, 0.8)
	# hide the kit's steel masts and arms, grow palm trunks in their place
	for ch: Node in z.get_children():
		if ch is MeshInstance3D and ch != cable:
			(ch as MeshInstance3D).visible = false
	var span: Vector3 = _w(end_floor) - _w(start_floor)
	for end_pt: Vector3 in [Vector3.ZERO, span]:
		var side: Vector3 = Vector3.UP.cross(span.normalized()).normalized() * 1.6
		var foot: Vector3 = end_pt + side - Vector3(0, 0.35, 0)
		var top: Vector3 = end_pt + side * 0.4 + Vector3(0, 2.6, 0)
		var d: Vector3 = top - foot
		var trunk: MeshInstance3D = Look.cylinder(0.16, d.length(), bark, (foot + top) * 0.5, 0.1, 8)
		trunk.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
		z.add_child(trunk)
		for i: int in 5:
			var a: float = TAU * float(i) / 5.0
			var frond: MeshInstance3D = Look.box(Vector3(0.12, 0.03, 1.5), leaf, top + Vector3(cos(a), -0.2, sin(a)) * 0.65)
			frond.rotation = Vector3(0.45, -a + PI * 0.5, 0)
			z.add_child(frond)
		z.add_child(Look.sphere(0.2, Look.flat(ORANGE, 0.5, 0.0, 1.2), end_pt))
	return z


func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var ledge: Dictionary = _blk(_ahead(cp0, 0.87, 0.0, 4.0), 4.0, 4.0, "alt")
	var lc: Vector3 = ledge["c"]
	var far: Dictionary = _blk(Vector3(0, 0.6, -37.0), 6.0, 8.0)
	var fc: Vector3 = far["c"]
	var z: Zipline = _vine(lc, Vector3(lc.x, lc.y + 0.6, fc.z + 1.0))
	var f1: Dictionary = _post(_ahead(far, 0.88, 0.0, 1.4, 0.4), 1.4, 1.4)
	var f2: Dictionary = _post(_ahead(f1, 0.89, 0.5, 1.3, -0.5))
	var f3: Dictionary = _post(_ahead(f2, 0.88, 0.0, 1.3, 0.4))
	var cp: Dictionary = _cp(_ahead(f3, 0.86, 0.0, 5.0, -(f3["c"] as Vector3).x))
	# SHORTCUT: the gorge's two walls, run one and kick across to the other onto the far ledge
	kit.wallrun(_w(Vector3(-3.0, 1.2, -13.0)), Vector3(14.0, 6.5, 0.5), _yaw + 90.0)
	kit.wallrun(_w(Vector3(3.0, 3.6, -26.0)), Vector3(12.0, 7.0, 0.5), _yaw + 90.0)
	if route_variant == 2:
		r_walk(_w(Vector3(-1.4, 0, -1.6)))
		r_wallrun(_w(Vector3(-1.4, 0, -2.65)), _w(Vector3(-2.5, 1.4, -7.4)), _w(Vector3(-2.5, 1.4, -15.6)), _w(Vector3(2.5, 3.8, -21.4)))
		r_wallrun(Vector3.ZERO, _w(Vector3(2.5, 3.8, -21.4)), _w(Vector3(2.5, 3.8, -28.6)), _w(Vector3(0, 0.6, -36.6)), true, true)
	else:
		_hop(cp0, ledge)
		r_zipline(z, _w(Vector3(lc.x, lc.y + 2.2 + 0.55, lc.z - 24.5)), 0.7, _w(Vector3(0, 0.6, fc.z + 1.0)))
	_hop(far, f1)
	_hop(f1, f2)
	_hop(f2, f3)
	_hop(f3, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Tar Fields (BRANCH) - wade the tar pits | the mammoth's ribs -------------------------
# [shortcut: five bone stakes down the middle at 91-92%]

## A tar pit as a floor: `top` is the local centre of its top, sx across, sz along.
func _tar(top: Vector3, sx: float, sz: float, sink: float = 1.3) -> DinoTar:
	var t := DinoTar.new()
	t.size = _sz(Vector3(sx, 1.4, sz))
	t.sink_max = sink
	t.position = _w(top) - Vector3(0, 0.7, 0)
	add_child(t)
	_floors.append({"top": _w(top), "size": _sz(Vector3(sx, 0, sz)), "drop": 1.4})
	return t


func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# RIGHT: the mammoth's rib cage wall run, a stake, mantle the skull, two stakes down to the merge
	kit.wallrun(_w(Vector3(5.7, 1.2, f0 - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, 0.0, f0 - 19.6), 2.0, 2.0)
	var skull_top := Vector3(3.6, 3.3, f0 - 19.6 - 1.0 - 1.6 - 0.8)
	var skull: Dictionary = _ledge(skull_top, Vector3(2.6, 9.0, 1.6))
	var q1: Dictionary = _post(_ahead(skull, 0.80, -3.3, 1.4, 0.0), 1.4, 1.4)
	var merge: Dictionary = _blk(_ahead(q1, 0.88, 0.0, 8.0, -(q1["c"] as Vector3).x), 11.0, 8.0)
	var mz: float = (merge["c"] as Vector3).z + 4.0
	# LEFT (main): tar pit, a stone, a leap to a post, the second tar pit, onto the merge
	var lx: float = -3.5
	var t1_len: float = 9.0
	var t1: DinoTar = _tar(Vector3(lx, 0, f0 - t1_len * 0.5), 3.6, t1_len)
	var s1: Dictionary = _blk(Vector3(lx, 0, f0 - t1_len - 1.2), 3.4, 2.4, "alt")
	var pa: Dictionary = _post(_ahead(s1, 0.87, 0.0, 1.5), 1.5, 1.5)
	var pac: Vector3 = pa["c"]
	# the far stone and the post beside the merge are placed from the merge back, so the second pit
	# takes up exactly the room that is left
	var pc_probe: Vector3 = _ahead(_area(Vector3.ZERO, 1.7, 1.2), 0.87, 0.0, 1.5)
	var s2z: float = (mz + 0.75) - pc_probe.z
	var t2_len: float = (pac.z - 0.75) - (s2z + 1.2)
	var t2: DinoTar = _tar(Vector3(lx, 0, pac.z - 0.75 - t2_len * 0.5), 3.6, t2_len)
	var s2: Dictionary = _blk(Vector3(lx, 0, s2z), 3.4, 2.4, "alt")
	var pc: Dictionary = _post(_ahead(s2, 0.87, 0.0, 1.5), 1.5, 1.5)
	# SHORTCUT: five bone stakes down the middle
	var hids: Array[Dictionary] = []
	var hp: Dictionary = _area(fc, 5.5, 1.5)
	for i: int in 5:
		hp = _post(_ahead(hp, 0.92 if i == 0 else 0.91, 0.0, 1.2), 1.2, 1.2, "accent")
		hids.append(hp)
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		var prev: Dictionary = _area(fc, 5.5, 1.5)
		for h: Dictionary in hids:
			_hop(prev, h)
			prev = h
		_hop(prev, merge, Vector3(0, 0, 0.4))
	elif route_variant == 1:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.0, 0, f0 + 0.35)), _w(Vector3(5.2, 1.4, f0 - 3.4)), _w(Vector3(5.2, 1.4, f0 - 12.6)), _w(Vector3(3.6, 0, f0 - 19.4)))
		r_mantle(_w(Vector3(3.6, 0, f0 - 19.6 - 0.65)), _w(skull_top + Vector3(0, 0, 0.2)))
		_hop(skull, q1)
		_hop(q1, merge, Vector3((q1["c"] as Vector3).x, 0, 0.6))
	else:
		r_walk(_w(Vector3(lx, 0, fc.z + 0.6)))
		r_walk(_w(Vector3(lx, 0, f0 - t1_len + 1.0)))
		r_jump(_w(Vector3(lx, 0, f0 - t1_len + 0.3)), _w(Vector3(lx, 0, f0 - t1_len - 1.4)))
		_hop(s1, pa)
		r_walk(_w(Vector3(lx, 0, pac.z - 0.9)))
		r_walk(_w(Vector3(lx, 0, s2z + 1.2 + 1.0)))
		r_jump(_w(Vector3(lx, 0, s2z + 1.2 + 0.3)), _w(Vector3(lx, 0, s2z)))
		_hop(s2, pc)
		r_walk(_w(Vector3(0, 0, mz - 5.0)))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	pb.clear()
	t1.set_meta("n", 1)
	t2.set_meta("n", 2)
	return cp["c"]


# ---- shared pieces for the stages below -----------------------------------------------------------------

## A wall run off the right of platform `a` (any size): the panel along its right and a 1.8 x 2.4 landing
## post straight on. `_wall_geo` builds them and returns the landing; `_wall_steps` is the bot's run.
func _wall_geo(a: Dictionary, panel_len: float = 16.0) -> Dictionary:
	var wc: Vector3 = a["c"]
	var f: float = wc.z - float(a["hz"])
	kit.wallrun(_w(Vector3(wc.x + 2.3, wc.y + 1.2, f - 9.5)), Vector3(panel_len, 6.5, 0.6), _yaw + 90.0)
	return _post(Vector3(wc.x - 0.6, wc.y, f - 22.5), 1.8, 2.4)


func _wall_steps(a: Dictionary) -> void:
	var wc: Vector3 = a["c"]
	var f: float = wc.z - float(a["hz"])
	r_wallrun(_w(Vector3(wc.x + 0.3, wc.y, f + 0.35)), _w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 3.6)),
		_w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 14.5)), _w(Vector3(wc.x - 0.6, wc.y, f - 22.2)))


## Safe-to-be-in-the-lane for the whole of [now + a, now + b] (a stampede lane).
func _lane_wait(s: DinoStampede, x: float, b: float, hold: Vector3) -> void:
	_wait(func() -> bool: return s.clear_for(x, 0.0, b), hold)


func _stampede(center: Vector3, width: float, per: float, ph: float, dir: float, span: float = 26.0) -> DinoStampede:
	var s := DinoStampede.new()
	s.span = span
	s.width = width
	s.period = per
	s.phase = ph
	s.direction = dir
	s.rotation.y = deg_to_rad(_yaw)
	s.position = _w(center)
	add_child(s)
	return s


## A flame vent: a kit laser dressed with fumarole cones, the tell stretched to 0.9 s.
func _flame(center: Vector3, width: float, per: float, on_fraction: float, ph: float) -> LaserGate:
	var g: LaserGate = kit.laser(_w(center), Vector3(width, 2.4, 0.3), per, on_fraction, ph, _yaw)
	g.warn = 0.9
	DinoDress.vent_posts(g)
	return g


# ---- stage 6: Stampede Flats - two herds thunder across the deck, then a flame vent ----------------------

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var deck: Dictionary = _blk(_ahead(cp0, 0.87, 0.0, 24.0), 12.0, 24.0)
	var dc: Vector3 = deck["c"]
	var ne: float = dc.z + 12.0
	var s1: DinoStampede = _stampede(Vector3(0, dc.y, ne - 8.0), 5.0, 7.0, 0.0, 1.0)
	var s2: DinoStampede = _stampede(Vector3(0, dc.y, ne - 17.0), 5.0, 7.4, 0.45, -1.0)
	var neck: Dictionary = _blk(Vector3(0, dc.y, dc.z - 16.0), 3.6, 8.0, "alt")
	var flame: LaserGate = _flame(Vector3(0, dc.y + 1.2, dc.z - 16.0), 3.6, 5.4, 0.42, 0.0)
	var post: Dictionary = _post(_ahead(neck, 0.88, 0.0, 1.4))
	var cp: Dictionary = _cp(_ahead(post, 0.86, 0.0, 5.0, -(post["c"] as Vector3).x))
	_hop(cp0, deck, Vector3(0, 0, 10.5))
	var stand1: Vector3 = _w(Vector3(0, dc.y, ne - 3.0))
	r_walk(stand1)
	_lane_wait(s1, 0.0, 2.9, stand1)
	var isl: Vector3 = _w(Vector3(0, dc.y, ne - 12.5))
	r_walk(isl)
	_lane_wait(s2, 0.0, 2.9, isl)
	r_walk(_w(Vector3(0, dc.y, ne - 21.5)))
	var at: Vector3 = _w(Vector3(0, dc.y, dc.z - 12.0 - 1.0))
	r_walk(at)
	_wait(func() -> bool: return _dark(flame, 0.0, 0.6 + 0.4 + 1.5), at)
	r_walk(_w(Vector3(0, dc.y, dc.z - 16.0 - 3.2)))
	_hop(neck, post)
	_hop(post, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 7: Pterodactyl Pass - ride a pterodactyl over the canyon, run the far cliff --------------------

## A pterodactyl carrying a stone saddle along `travel` (local) and back: a kit mover in a skin.
func _ptero(home_top: Vector3, travel: Vector3, per: float, ph: float) -> MovingPlatform:
	var pts: Array[Vector3] = [Vector3.ZERO, _d(travel)]
	var m: MovingPlatform = kit.mover(_w(home_top), _sz(Vector3(2.8, 0.5, 3.6)), pts, per, ph)
	m.dwell = 0.2
	DinoDress.ptero_mount(m)
	return m


## Bot: hop onto a ridden platform `m` from `from` (world), and off at its far end onto `to` (world).
func _ride(from: Vector3, m: MovingPlatform, travel: Vector3, to: Vector3) -> void:
	_board(from, m, Vector3(0, 0.25, 0.6), func() -> bool: return _mover_at(m, Vector3.ZERO, 0.3, 0.0, 1.0))
	r_jump_from_ride(m, _home(m) + _d(travel), 0.3, to, true, Vector3(0, 0.25, 0) + _d(Vector3(0, 0, -1.2)))


func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var travel := Vector3(0, 2.0, -17.5)
	var r1: MovingPlatform = _ptero(Vector3(0, 0, -8.2), travel, 12.0, 0.0)
	var b: Dictionary = _blk(Vector3(0, 2.0, -31.6), 3.4, 3.4, "alt")
	var w2: Dictionary = _post(_ahead(b, 0.88, 0.0, 1.4, 0.4), 1.4, 1.4)
	var land: Dictionary = _wall_geo(w2)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(land["c"] as Vector3).x))
	_ride(_w(Vector3(0, 0, -2.65)), r1, travel, _w(Vector3(0, 2.0, -31.2)))
	_hop(b, w2)
	_wall_steps(w2)
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 8: Horn Ledge - triceratops charging out of the cliff along a narrow ledge, mantle out --------

## A triceratops head punching out of the cliff across a ledge: a kit piston in a skin, with a ground tell.
## `dir` 1 = the head sits on the left and charges right.
func _trike(ledge_c: Vector3, dir: float, z: float, per: float, ph: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.2)
	var x: float = ledge_c.x - dir * (0.8 + 0.6 + 0.15)
	var p: Piston = kit.piston(_w(Vector3(x, ledge_c.y + 1.35, z)), size, _yaw - 90.0 * dir, 2.6, per, ph, 10.0)
	DinoDress.trike_ram(p)
	DinoTell.make(self, _w(Vector3(ledge_c.x, ledge_c.y, z)), Vector2(1.7, 1.9), per, ph, 0.45, "dino_trike_paw", 0.95, _yaw)
	return p


static func _rams_clear(rams: Array[Piston], ts: Array[float]) -> bool:
	for i: int in rams.size():
		if not _ram_clear(rams[i], ts[i] - 0.35, ts[i] + 0.35 + 1.5):
			return false
	return true


func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var beam: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 22.0), 1.6, 22.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var period: float = 6.0
	var zs: Array[float] = [bc.z + 6.0, bc.z, bc.z - 6.0]
	var ts: Array[float] = [0.65, 1.35, 2.05]
	var rams: Array[Piston] = []
	for i: int in 3:
		var ph: float = fposmod(0.02 - (ts[i] - 0.35) / period, 1.0)
		rams.append(_trike(bc, 1.0 if i % 2 == 0 else -1.0, zs[i], period, ph))
	var front: float = bc.z - 11.0
	var rock_top := Vector3(bc.x, bc.y + 3.3, front - 1.6 - 0.8)
	var rock: Dictionary = _ledge(rock_top, Vector3(3.0, 9.0, 1.6))
	var cp: Dictionary = _cp(_ahead(rock, 0.85, 0.0, 5.0, -bc.x))
	_hop(cp0, beam, Vector3(0, 0, 9.5))
	var spot: Vector3 = _w(Vector3(bc.x, bc.y, bc.z + 9.4))
	r_walk(spot)
	_wait(func() -> bool: return _rams_clear(rams, ts), spot)
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(rock_top + Vector3(0, 0, 0.2)))
	_hop(rock, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Bronto Crossing (BRANCH) - ride the brontosaurus's neck | the ribs and the skull -----------
# [shortcut: the hollow log (portal) from the fork's middle]

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# RIGHT: the wall run along a fossil rib cage, a stake, mantle the great skull, drop to the merge
	kit.wallrun(_w(Vector3(5.7, 1.2, f0 - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, 0.0, f0 - 19.6), 2.0, 2.0)
	var skull_top := Vector3(3.6, 3.3, f0 - 19.6 - 1.0 - 1.6 - 0.8)
	var skull: Dictionary = _ledge(skull_top, Vector3(2.6, 9.0, 1.6))
	var merge: Dictionary = _blk(_ahead(skull, 0.85, -3.3, 8.0, -3.6), 11.0, 8.0)
	var mc: Vector3 = merge["c"]
	# LEFT: the brontosaurus lowers its head to the ledge; ride it up to the high rock
	var head_travel := Vector3(0, 7.0, -14.0)
	var hpts: Array[Vector3] = [Vector3.ZERO, _d(head_travel)]
	var head: MovingPlatform = kit.mover(_w(Vector3(-3.5, 0, f0 - 2.6)), _sz(Vector3(3.0, 0.5, 3.2)), hpts, 12.0, 0.0)
	head.dwell = 0.2
	DinoNeckDress.mount_head(head)
	var hi: Dictionary = _blk(Vector3(-3.5, 7.0, f0 - 21.4), 4.0, 4.0, "alt")
	# the great body stands beside the course, its neck reaching to the head
	var body: DinoCreature = DinoCreature.make("bronto", 1.7)
	body.position = _w(Vector3(-17.0, -4.0, f0 - 8.0))
	body.rotation_degrees.y = _yaw - 90.0
	body.amount = 0.0
	add_child(body)
	var shoulder: Vector3 = body.global_transform * Vector3(0, 4.8, -3.3)
	DinoNeckDress.make(self, shoulder, head, 10)
	# SHORTCUT: a hollow log in the middle of the fork leads straight to the merge
	var sp: Dictionary = _post(_ahead(_area(fc, 5.5, 1.5), 0.92, 0.0, 1.6, 0.6), 1.6, 1.6, "accent")
	var spc: Vector3 = sp["c"]
	var portal: WarpPortal = kit.portal(_w(spc + Vector3(0, 0, -0.1)), _yaw, _w(Vector3(0.5, 0, mc.z + 2.0)), _yaw, 7.0)
	DinoDress.hollow_log(self, _w(spc + Vector3(0, 0, -0.1)), _yaw)
	DinoDress.hollow_log(self, _w(Vector3(0.5, 0, mc.z + 2.0)), _yaw)
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0.6, 0, fc.z)))
		_hop(_area(fc, 5.5, 1.5), sp, Vector3(0, 0, 0.3))
		r_portal(_w(spc + Vector3(0, 0, -0.6)), portal.exit_point())
	elif route_variant == 1:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.0, 0, f0 + 0.35)), _w(Vector3(5.2, 1.4, f0 - 3.4)), _w(Vector3(5.2, 1.4, f0 - 12.6)), _w(Vector3(3.6, 0, f0 - 19.4)))
		r_mantle(_w(Vector3(3.6, 0, f0 - 19.6 - 0.65)), _w(skull_top + Vector3(0, 0, 0.2)))
		_hop(skull, merge, Vector3(3.6, 0, 0.8))
	else:
		_board(_w(Vector3(-3.5, 0, f0 + 0.35)), head, Vector3(0, 0.25, 0.6), func() -> bool: return _mover_at(head, Vector3.ZERO, 0.3, 0.0, 1.0))
		r_jump_from_ride(head, _home(head) + _d(head_travel), 0.3, _w(Vector3(-3.5, 7.0, f0 - 21.4)), true, Vector3(0, 0.25, 0) + _d(Vector3(0, 0, -1.2)))
		_hop(hi, merge, Vector3(-3.5, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	pb.clear()
	return cp["c"]


# ---- stage 10: Stomp Hall - the giant foot stamping the canyon floor, a log seesaw, a wall run -----------

func _foot(floor_top: Vector3, per: float, ph: float) -> Crusher:
	var c: Crusher = kit.crusher(_w(floor_top), Vector3(2.4, 1.4, 2.6), 3.4, per, ph, _yaw)
	DinoDress.foot(c)
	DinoTell.make(self, _w(floor_top), Vector2(2.6, 2.8), per, ph, Crusher.SLAM, "dino_foot_rumble", 0.95, _yaw)
	return c


func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var hall: Dictionary = _blk(_ahead(cp0, 0.87, 0.0, 22.0), 3.4, 22.0, "alt")
	var hc: Vector3 = hall["c"]
	var f1: Crusher = _foot(Vector3(hc.x, hc.y, hc.z + 4.0), 6.0, 0.0)
	var f2: Crusher = _foot(Vector3(hc.x, hc.y, hc.z - 4.5), 6.0, 0.37)
	var bz: float = hc.z - 11.0
	var deck: Dictionary = _blk(Vector3(hc.x, hc.y, bz - 2.0), 5.0, 4.0)
	var saw_c := Vector3(hc.x, hc.y, bz - 4.0 - 4.5)
	var saw: Seesaw = kit.seesaw(_w(saw_c), 9.0, 2.6, false, 0.0)
	var land: Dictionary = _blk(Vector3(hc.x, hc.y, bz - 4.0 - 9.0 - 1.0 - 2.0), 3.6, 4.0, "alt")
	var lnd: Dictionary = _wall_geo(land)
	var cp: Dictionary = _cp(_ahead(lnd, 0.86, 0.0, 5.0, -(lnd["c"] as Vector3).x))
	_hop(cp0, hall, Vector3(0, 0, 9.5))
	var a1: Vector3 = _w(Vector3(hc.x, hc.y, hc.z + 8.5))
	r_walk(a1)
	_wait(func() -> bool: return _press_ok(f1, 0.0, 1.0 + 0.4 + 1.5), a1)
	var a2: Vector3 = _w(Vector3(hc.x, hc.y, hc.z + 0.9))
	r_walk(a2)
	_wait(func() -> bool: return _press_ok(f2, 0.0, 1.2 + 0.4 + 1.5), a2)
	r_walk(_w(Vector3(hc.x, hc.y, bz - 1.0)))
	r_walk(_w(saw_c))
	r_walk(_w(saw_c + Vector3(0, 0, -3.9)))
	r_jump(_w(saw_c + Vector3(0, 0, -4.1)), _w(Vector3(hc.x, hc.y, (land["c"] as Vector3).z)))
	_wall_steps(land)
	_hop(lnd, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	saw.set_meta("n", 1)
	return cp["c"]


# ---- stage 11: Boulder Slope - boulders rolled off the volcano drop on the decks, then a wall run ------------

## A boulder hung over a deck: the kit's falling block in a skin. Safe while it hangs and while its
## shadow swells (1 s); then it drops. Period 7 leaves 3.9 s of safe time.
func _boulder(floor_top: Vector3, per: float, ph: float) -> FallingBlock:
	var b: FallingBlock = kit.falling_block(_w(floor_top), Vector3(3.0, 1.6, 3.0), 7.0, per, ph, false)
	DinoDress.boulder(b)
	return b


func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var decks: Array[Dictionary] = []
	var boulders: Array[FallingBlock] = []
	var prev: Dictionary = cp0
	var dys: Array[float] = [0.0, 0.5, 0.5]
	var pcts: Array[float] = [0.87, 0.88, 0.88]
	for i: int in 3:
		var d: Dictionary = _blk(_ahead(prev, pcts[i], dys[i], 7.0), 3.4, 7.0, "alt" if i % 2 == 0 else "main")
		var dc: Vector3 = d["c"]
		boulders.append(_boulder(dc, 7.0, 0.31 * float(i)))
		decks.append(d)
		prev = d
	var post: Dictionary = _post(_ahead(prev, 0.88, 0.0, 1.4))
	var land: Dictionary = _wall_geo(post)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(land["c"] as Vector3).x))
	prev = cp0
	for i: int in 3:
		var d2: Dictionary = decks[i]
		var dc2: Vector3 = d2["c"]
		_hop(prev, d2, Vector3(0, 0, 2.6))
		var spot: Vector3 = _w(Vector3(dc2.x, dc2.y, dc2.z + 2.7))
		r_walk(spot)
		var b: FallingBlock = boulders[i]
		_wait(func() -> bool: return b.is_clear_for(Game.course_time, 0.95 + 1.5), spot)
		r_walk(_w(Vector3(dc2.x, dc2.y, dc2.z - 2.9)))
		prev = d2
	_hop(prev, post)
	_wall_steps(post)
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 12: Burrow Maze (BRANCH) - the burrow (portal) up to the ledge | the flame vents --------------
# [shortcut: five stakes straight across the middle at 91-92%]

## Stakes down a line from `a` until the merge (whose near edge is at local z `near_z`) can be reached at
## 89% or less. Returns the stakes in order.
func _stakes_toward(a: Dictionary, near_z: float, pct: float = 0.87, size: float = 1.3, style: String = "accent") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cur: Dictionary = a
	for i: int in 8:
		var front: float = (cur["c"] as Vector3).z - float(cur["hz"])
		var need: float = front + 0.35 - near_z + 0.4
		if need / _reach(0.0) <= 0.89:
			break
		cur = _post(_ahead(cur, pct, 0.0, size), size, size, style)
		out.append(cur)
	return out


func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT (main): the burrow's mouth on the fork leads out of a root on the lintel beam high ahead
	var hi: Dictionary = _blk(Vector3(-3.5, 4.5, f0 - 9.0), 1.4, 5.0, "alt", 0.6)
	var door: WarpPortal = kit.portal(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, _w(Vector3(-3.5, 4.5, f0 - 7.2)), _yaw, 7.0)
	DinoDress.hollow_log(self, _w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw)
	DinoDress.hollow_log(self, _w(Vector3(-3.5, 4.5, f0 - 7.2)), _yaw)
	var la: Dictionary = _post(_ahead(hi, 0.86, -1.5, 1.3, 0.3))
	var la2: Dictionary = _post(_ahead(la, 0.86, -1.5, 1.3, -0.3))
	var merge: Dictionary = _blk(_ahead(la2, 0.86, -1.5, 8.0, -(la2["c"] as Vector3).x), 11.0, 8.0)
	var mc: Vector3 = merge["c"]
	var near_z: float = mc.z + 4.0
	# RIGHT: a beam through two flame vents, then stakes to the merge
	var rl: Dictionary = _area(Vector3(4.0, 0, fc.z), 1.5, 1.5)
	var rbeam: Dictionary = _blk(_ahead(rl, 0.86, 0.0, 12.0), 1.4, 12.0, "alt", 0.6)
	var rb: Vector3 = rbeam["c"]
	var period: float = 5.4
	var ts: Array[float] = [0.7, 1.35]
	var flames: Array[LaserGate] = []
	for i: int in 2:
		var ph: float = fposmod(0.44 - (ts[i] - 0.35) / period, 1.0)
		flames.append(_flame(Vector3(rb.x, rb.y + 1.2, rb.z + 2.5 - 5.0 * float(i)), 3.2, period, 0.42, ph))
	var rstakes: Array[Dictionary] = _stakes_toward(rbeam, near_z)
	# SHORTCUT: stakes straight across the middle of the fork
	var sstakes: Array[Dictionary] = _stakes_toward(_area(fc, 5.5, 1.5), near_z, 0.91, 1.2)
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		var prev: Dictionary = _area(fc, 5.5, 1.5)
		for h: Dictionary in sstakes:
			_hop(prev, h)
			prev = h
		_hop(prev, merge, Vector3(0, 0, 0.4))
	elif route_variant == 1:
		r_walk(_w(Vector3(4.0, 0, fc.z + 0.6)))
		_hop(rl, rbeam, Vector3(0, 0, 4.5))
		var spot: Vector3 = _w(Vector3(rb.x, rb.y, rb.z + 5.6))
		r_walk(spot)
		_wait(func() -> bool: return _flames_dark(flames, ts), spot)
		r_walk(_w(Vector3(rb.x, rb.y, rb.z - 5.4)))
		var prev2: Dictionary = rbeam
		for h2: Dictionary in rstakes:
			_hop(prev2, h2)
			prev2 = h2
		_hop(prev2, merge, Vector3((prev2["c"] as Vector3).x, 0, 0.6))
	else:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		r_portal(_w(Vector3(-3.5, 0, fc.z - 0.9)), door.exit_point())
		r_walk(_w(Vector3(-3.5, 4.5, f0 - 10.0)))
		_hop(hi, la)
		_hop(la, la2)
		_hop(la2, merge, Vector3((la2["c"] as Vector3).x, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


static func _flames_dark(flames: Array[LaserGate], ts: Array[float]) -> bool:
	for i: int in flames.size():
		if not _dark(flames[i], ts[i] - 0.35, ts[i] + 0.35 + 1.5):
			return false
	return true


# ---- stage 13: Club Tail - an ankylosaur's spinning tail on the round rock, mantle out ---------------------

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.87, 0.0, 1.6), 1.6, 1.6)
	var rock: Dictionary = _blk(_ahead(p1, 0.87, 0.0, 16.0), 16.0, 16.0)
	var rc: Vector3 = rock["c"]
	var ham: SpinHammer = kit.hammer(_w(rc), 5.0, 7.2, 0.0, 180.0, 1.0)
	DinoDress.club_tail(ham)
	var front: float = rc.z - 8.0
	var ledge_top := Vector3(2.0, rc.y + 3.3, front - 1.6 - 0.8)
	var ledge: Dictionary = _ledge(ledge_top, Vector3(3.2, 9.0, 1.6))
	var cp: Dictionary = _cp(_ahead(ledge, 0.85, 0.0, 5.0, -2.0))
	_hop(cp0, p1)
	_hop(p1, rock, Vector3(0, 0, 7.2))
	var spot: Vector3 = _w(Vector3(2.0, rc.y, rc.z + 7.3))
	r_walk(spot)
	_wait(func() -> bool: return ham.is_parked_for(Game.course_time, 3.3), spot)
	r_walk(_w(Vector3(2.0, rc.y, front + 0.9)))
	r_mantle(_w(Vector3(2.0, rc.y, front + 0.35)), _w(ledge_top + Vector3(0, 0, 0.2)))
	_hop(ledge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 14: Second Springs - a pterodactyl over the gorge, a geyser up the cliff ------------------------
# [shortcut: five stakes straight over the gorge at 91-92%]

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var a: Dictionary = _blk(_ahead(cp0, 0.87, 0.0, 3.4), 3.4, 3.4, "alt")
	var ac: Vector3 = a["c"]
	var travel := Vector3(0, 1.0, -19.0)
	var r1: MovingPlatform = _ptero(Vector3(ac.x, ac.y, ac.z - 1.7 - 1.4 - 1.8), travel, 13.0, 0.0)
	var home_z: float = ac.z - 1.7 - 1.4 - 1.8
	var g_slab: Dictionary = _blk(Vector3(ac.x, ac.y + 1.0, home_z - 19.0 - 1.8 - 2.2 - 2.2), 4.4, 4.4)
	var gc: Vector3 = g_slab["c"]
	var geyser: DinoGeyser = _geyser(g_slab, 8.4, 0.2)
	var terr: Dictionary = _blk(gc + Vector3(0, 3.4, -5.4), 4.4, 4.4, "alt")
	var s1: Dictionary = _post(_ahead(terr, 0.87, 0.0, 1.3, 0.4))
	var s2: Dictionary = _post(_ahead(s1, 0.88, 0.4, 1.3, -0.4))
	var s3: Dictionary = _post(_ahead(s2, 0.88, 0.0, 1.3, 0.4))
	var cp: Dictionary = _cp(_ahead(s3, 0.86, 0.0, 5.0, -(s3["c"] as Vector3).x))
	var stakes: Array[Dictionary] = _stakes_toward(a, gc.z + 2.2, 0.91, 1.2)
	_hop(cp0, a)
	if route_variant == 2:
		var prev: Dictionary = a
		for h: Dictionary in stakes:
			_hop(prev, h)
			prev = h
		_hop(prev, g_slab, Vector3(0, 0, 1.0))
	else:
		_ride(_w(_edge(a, Vector3(ac.x, ac.y, home_z))), r1, travel, _w(Vector3(gc.x, gc.y, gc.z + 1.0)))
	_ride_geyser(geyser, _w(terr["c"] as Vector3))
	_hop(terr, s1)
	_hop(s1, s2)
	_hop(s2, s3)
	_hop(s3, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 15: Canyon Rim - a long chain of stacks, a stampede across the rim, a chimney of wall runs ------

func _stage_15() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var c1: Dictionary = _post(_ahead(cp0, 0.87, 0.0, 1.4), 1.4, 1.4)
	var c2: Dictionary = _post(_ahead(c1, 0.88, 0.5, 1.3, 0.4))
	var c3: Dictionary = _post(_ahead(c2, 0.87, -0.4, 1.3, -0.4))
	var deck: Dictionary = _blk(_ahead(c3, 0.87, 0.0, 14.0), 5.0, 14.0)
	var dc: Vector3 = deck["c"]
	var lane: DinoStampede = _stampede(Vector3(dc.x, dc.y, dc.z), 4.0, 7.0, 0.2, 1.0, 8.0)
	var d1: Dictionary = _post(_ahead(deck, 0.88, 0.0, 1.3, 0.3))
	var d2: Dictionary = _post(_ahead(d1, 0.87, 0.4, 1.3, -0.3))
	# the chimney: two wall runs between the canyon walls, from the last stake
	var z0: float = (d2["c"] as Vector3).z + 2.35
	var x0: float = (d2["c"] as Vector3).x
	var y0: float = (d2["c"] as Vector3).y
	kit.wallrun(_w(Vector3(x0 - 3.0, y0 + 1.2, z0 - 13.0)), Vector3(14.0, 6.5, 0.5), _yaw + 90.0)
	kit.wallrun(_w(Vector3(x0 + 3.0, y0 + 3.6, z0 - 26.0)), Vector3(12.0, 7.0, 0.5), _yaw + 90.0)
	var far: Dictionary = _blk(Vector3(x0, y0 + 0.6, z0 - 37.0), 6.0, 8.0)
	var cp: Dictionary = _cp(_ahead(far, 0.86, 0.0, 5.0, -x0))
	_hop(cp0, c1)
	_hop(c1, c2)
	_hop(c2, c3)
	_hop(c3, deck, Vector3(0, 0, 6.0))
	var spot: Vector3 = _w(Vector3(dc.x, dc.y, dc.z + 3.6))
	r_walk(spot)
	_lane_wait(lane, 0.0, 2.6, spot)
	r_walk(_w(Vector3(dc.x, dc.y, dc.z - 6.0)))
	_hop(deck, d1)
	_hop(d1, d2)
	var dcz: Vector3 = d2["c"]
	r_wallrun(_w(Vector3(x0, y0, dcz.z - 0.3)), _w(Vector3(x0 - 2.5, y0 + 1.4, z0 - 7.4)), _w(Vector3(x0 - 2.5, y0 + 1.4, z0 - 15.6)), _w(Vector3(x0 + 2.5, y0 + 3.8, z0 - 21.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(x0 + 2.5, y0 + 3.8, z0 - 21.4)), _w(Vector3(x0 + 2.5, y0 + 3.8, z0 - 28.6)), _w(Vector3(x0, y0 + 0.6, z0 - 36.6)), true, true)
	_hop(far, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 16: The Egg Gate - tar stones, a leap, a geyser up to the canyon mouth ---------------------------

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var i1: Dictionary = _blk(_ahead(cp0, 0.87, 0.0, 2.4), 3.0, 2.4, "alt")
	var i1c: Vector3 = i1["c"]
	var tar_len: float = 8.0
	var t: DinoTar = _tar(Vector3(i1c.x, i1c.y, i1c.z - 1.2 - tar_len * 0.5), 3.4, tar_len)
	var i2: Dictionary = _blk(Vector3(i1c.x, i1c.y, i1c.z - 1.2 - tar_len - 1.2), 3.0, 2.4, "alt")
	var p: Dictionary = _post(_ahead(i2, 0.88, 0.0, 1.4))
	var g_slab: Dictionary = _blk(_ahead(p, 0.87, 0.0, 4.4), 4.4, 4.4)
	var gc: Vector3 = g_slab["c"]
	var geyser: DinoGeyser = _geyser(g_slab, 8.2, 0.6)
	var cp: Dictionary = _cp(gc + Vector3(0, 3.4, -5.6), 6.0)
	_hop(cp0, i1)
	r_walk(_w(Vector3(i1c.x, i1c.y, i1c.z - 1.0)))
	r_walk(_w(Vector3(i1c.x, i1c.y, i1c.z - 1.2 - tar_len + 1.0)))
	r_jump(_w(Vector3(i1c.x, i1c.y, i1c.z - 1.2 - tar_len + 0.3)), _w(Vector3(i1c.x, i1c.y, i1c.z - 1.2 - tar_len - 1.3)))
	_hop(i2, p)
	_hop(p, g_slab, Vector3(0, 0, 0.6))
	_ride_geyser(geyser, _w(cp["c"] as Vector3))
	r_checkpoint()
	t.set_meta("n", 3)
	return cp["c"]


# ---- stage 17: THE CHASE - step over the line and the T-rex comes out of the canyon behind you --------------

var _rex: DinoRex
var _nest_pos: Vector3 = Vector3.ZERO

const CHASE_RUN: Array = [
	# [gap before, length, width, hurdle height (0 = none)]
	[0.0, 12.0, 6.0, 0.0],
	[2.2, 10.0, 5.0, 0.9],
	[3.0, 12.0, 4.6, 1.1],
	[2.0, 16.0, 1.8, 0.0],
	[4.4, 9.0, 4.0, 0.0],
]


## A fallen tree across the canyon floor: hop it.
func _hurdle(z: float, width: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, h, 0.9)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var bark: StandardMaterial3D = Look.flat(Color(0.4, 0.28, 0.17), 0.95)
	var lg: MeshInstance3D = Look.cylinder(h * 0.52, width + 0.4, bark, Vector3.ZERO, -1.0, 12)
	lg.rotation.z = PI * 0.5
	body.add_child(lg)
	body.add_child(Look.cylinder(h * 0.5, 0.04, Look.flat(Color(0.7, 0.55, 0.38), 0.8), Vector3(width * 0.5 + 0.2, 0, 0), -1.0, 12))
	(body.get_child(body.get_child_count() - 1) as MeshInstance3D).rotation.z = PI * 0.5
	body.rotation_degrees.y = _yaw
	body.position = _w(Vector3(0, h * 0.5, z))
	add_child(body)


func _stage_17() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var z: float = -2.5
	var segs: Array[Dictionary] = []
	var prev: Dictionary = cp0
	for spec: Array in CHASE_RUN:
		var gap: float = float(spec[0])
		var len: float = float(spec[1])
		var w: float = float(spec[2])
		var h: float = float(spec[3])
		var zc: float = z - gap - len * 0.5
		var seg: Dictionary = _blk(Vector3(0, 0, zc), w, len, "alt" if w < 2.0 else "main", 0.9)
		if h > 0.0:
			_hurdle(zc, w, h)
		segs.append({"a": seg, "gap": gap, "len": len, "h": h, "zc": zc, "near": z - gap})
		z = z - gap - len
	var end_z: float = z
	# the nest cliff: a 3.3 m rock across a short gap (the rex cannot climb it), a ledge top, then stacks
	var rock_top := Vector3(0, 3.3, end_z - 1.6 - 0.8)
	var rock: Dictionary = _ledge(rock_top, Vector3(4.2, 9.0, 1.6))
	var top: Dictionary = _blk(Vector3(0, 3.3, rock_top.z - 0.8 - 3.0), 4.2, 6.0, "main", 0.9)
	var s1: Dictionary = _post(_ahead(top, 0.84, 0.0, 1.8), 1.8, 1.8)
	var s2: Dictionary = _post(_ahead(s1, 0.85, 0.4, 1.7, 0.4), 1.7, 1.7)
	var s3: Dictionary = _post(_ahead(s2, 0.85, 0.0, 1.7, -0.4), 1.7, 1.7)
	var nest: Dictionary = _blk(_ahead(s3, 0.85, 0.0, 7.0, -(s3["c"] as Vector3).x), 7.0, 7.0, "main", 1.2)
	var nc: Vector3 = nest["c"]
	_nest_pos = _w(nc)
	kit.finish(_w(nc + Vector3(0, 0, -1.0)), _yaw)
	_finish_pos = _w(nc + Vector3(0, 0, -1.0))
	# the rex: out of the canyon wall to the left, onto the floor behind the start, then along the run
	var pts_local: Array[Vector3] = [Vector3(-11, 0, 9), Vector3(-6, 0, 6), Vector3(-2, 0, 2.5), Vector3(0, 0, -2.0),
		Vector3(0, 0, end_z + 2.0)]
	var origin: Vector3 = _w(pts_local[0])
	var rex := DinoRex.new()
	var tr: Array[Vector3] = []
	for p: Vector3 in pts_local:
		tr.append(_w(p) - origin)
	rex.track = tr
	rex.delay = 2.6
	rex.v_start = 5.8
	rex.accel = 0.8
	rex.v_max = 8.4
	rex.position = origin
	rex.trigger_pos = _w(Vector3(0, 1.5, -3.4)) - origin
	rex.trigger_size = _sz(Vector3(6.0, 3.0, 1.2))
	add_child(rex)
	_rex = rex
	# the run: step over the line, then sprint, hop the trunks, leap the gaps, climb the nest cliff
	for i: int in segs.size():
		var sd: Dictionary = segs[i]
		var h: float = float(sd["h"])
		var zc: float = float(sd["zc"])
		if i == 0:
			r_walk(_w(Vector3(0, 0, -4.0)))
		else:
			var pv: Dictionary = segs[i - 1]
			r_jump(_w(Vector3(0, 0, float(pv["near"]) - float(pv["len"]) + 0.35)), _w(Vector3(0, 0, float(sd["near"]) - 1.4)), true)
		if h > 0.0:
			r_jump(_w(Vector3(0, 0, zc + 1.9)), _w(Vector3(0, 0, zc - 2.6)), true)
		if i == 3:
			r_walk(_w(Vector3(0, 0, zc - float(sd["len"]) * 0.5 + 1.0)))
	r_walk(_w(Vector3(0, 0, end_z + 0.9)))
	r_mantle(_w(Vector3(0, 0, end_z + 0.35)), _w(rock_top + Vector3(0, 0, 0.2)))
	r_walk(_w(Vector3(0, 3.3, (top["c"] as Vector3).z - 1.0)))
	_hop(top, s1)
	_hop(s1, s2)
	_hop(s2, s3)
	_hop(s3, nest, Vector3(0, 0, 0.6))
	r_walk(_w(nc + Vector3(0, 0, -1.2)))
	_nest_dress(nc)


func _nest_dress(nc: Vector3) -> void:
	var twig: StandardMaterial3D = Look.flat(Color(0.45, 0.32, 0.2), 0.95)
	var egg: StandardMaterial3D = Look.flat(Color(0.95, 0.93, 0.82), 0.5)
	var spot: StandardMaterial3D = Look.flat(Color(0.45, 0.6, 0.25), 0.6)
	for k: int in 22:
		var a: float = TAU * float(k) / 22.0
		var tw: MeshInstance3D = Look.cylinder(0.09, 2.2, twig, _w(nc + Vector3(cos(a) * 2.9, 0.25, sin(a) * 2.9 + 1.0)), -1.0, 5)
		tw.rotation = Vector3(sin(a) * 1.2, a, PI * 0.5 + cos(a) * 0.3)
		add_child(tw)
	for k2: int in 5:
		var e: MeshInstance3D = Look.sphere(0.42, egg if k2 % 2 == 0 else spot, _w(nc + Vector3((float(k2) - 2.0) * 0.55, 0.45, 2.1 + float(k2 % 2) * 0.3)))
		e.scale = Vector3(0.8, 1.15, 0.8)
		add_child(e)


func _finish_sequence() -> void:
	# the eggs glow, the rex roars from far below and a flock of pterodactyls wheels over the nest
	var fw: GPUParticles3D = Fx.sparks({"amount": 90, "lifetime": 1.4, "one_shot": true, "explosiveness": 0.9, "shape": "sphere",
		"radius": 0.6, "dir": Vector3.UP, "spread": 35.0, "speed": Vector2(8.0, 14.0), "gravity": Vector3(0, -9, 0),
		"color": Fx.hot(GOLD, 2.2), "size": Vector2(0.08, 0.6), "aabb": AABB(Vector3(-20, -5, -20), Vector3(40, 40, 40))})
	fw.position = _nest_pos + Vector3(0, 1.5, 0)
	add_child(fw)
	fw.restart()
	fw.emitting = true
	# SOUND: dino_finish - hatchlings chirp as the eggs crack and a far-off rex bellows in defeat
	WorldAudio.at(self, "dino_finish", _nest_pos + Vector3(0, 2.0, 0), 1.0, 120.0)
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


func _surroundings() -> void:
	pass
