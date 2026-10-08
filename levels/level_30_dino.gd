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
	var m: float = pct * _reach(dy)
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
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5]
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
		_dev_finish()
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

const GEYSER_HEIGHT: float = 5.2

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
	var top_y: float = vent.y + GEYSER_HEIGHT - 0.7
	route.append({"kind": "desert_fly", "to": vent, "until": func() -> bool: return player.global_position.y > top_y})
	route.append({"kind": "desert_fly", "to": to})


func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var g1s: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 4.0), 4.0, 4.0)
	var g1c: Vector3 = g1s["c"]
	var t1: Dictionary = _blk(g1c + Vector3(0, 3.4, -5.8), 4.4, 4.4, "alt")
	var t2: Dictionary = _blk(_ahead(t1, 0.87, 0.4, 4.0), 4.4, 4.4)
	var t2c: Vector3 = t2["c"]
	var cp: Dictionary = _cp(t2c + Vector3(0, 3.4, -6.4))
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
	var far: Dictionary = _blk(Vector3(0, 0.6, lc.z - 25.0), 6.0, 8.0)
	var fc: Vector3 = far["c"]
	var z: Zipline = _vine(lc, Vector3(lc.x, lc.y + 0.6, fc.z + 1.0))
	var f1: Dictionary = _post(_ahead(far, 0.88, 0.0, 1.4, 0.4), 1.4, 1.4)
	var f2: Dictionary = _post(_ahead(f1, 0.89, 0.5, 1.3, -0.5))
	var f3: Dictionary = _post(_ahead(f2, 0.88, 0.0, 1.3, 0.4))
	var cp: Dictionary = _cp(_ahead(f3, 0.86, 0.0, 5.0, -(f3["c"] as Vector3).x))
	# SHORTCUT: the gorge's two walls, run one and kick across to the other onto the far ledge
	kit.wallrun(_w(Vector3(-3.4, 1.2, lc.z + 1.5)), Vector3(14.0, 6.5, 0.5), _yaw + 90.0)
	kit.wallrun(_w(Vector3(3.4, 3.6, lc.z - 11.5)), Vector3(12.0, 7.0, 0.5), _yaw + 90.0)
	_hop(cp0, ledge)
	if route_variant == 2:
		r_wallrun(_w(Vector3(-1.4, 0, lc.z + 6.9)), _w(Vector3(-2.5, 1.4, lc.z + 3.0)), _w(Vector3(-2.5, 1.4, lc.z - 3.8)), _w(Vector3(2.7, 3.8, lc.z - 9.5)))
		r_wallrun(Vector3.ZERO, _w(Vector3(2.7, 3.8, lc.z - 9.5)), _w(Vector3(2.7, 3.8, lc.z - 16.8)), _w(Vector3(0, 0.6, fc.z + 2.0)), true, true)
	else:
		r_zipline(z, _w(Vector3(lc.x, lc.y + 2.2 + 0.45, lc.z - 18.0)), 0.7, _w(Vector3(0, 0.6, fc.z + 1.0)))
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
	var q1: Dictionary = _post(_ahead(skull, 0.87, 0.0, 1.4, 0.0), 1.4, 1.4)
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
