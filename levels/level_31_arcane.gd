extends LevelBase
## 31. ARCANE LIBRARY - an endless wizard's library by candlelight (HARD tier). Walls of bookshelves
## going up and down out of sight, oak floors and oxblood leather, gold trim, violet spell-light, loose
## pages drifting through the candle smoke. The books fly, the ink floods, the shelves slide shut, the
## hourglass gates run out of sand and the spell circles throw you across the dark.
## Seventeen stages, sixteen checkpoints; hard through precision (nine-plus main-path jumps at 85-88%
## of max reach onto 1.2-1.4 m posts) and a stream of different machines, never through blind timing.
##
##  1 The Reading Room   a stair of four floating posts, a reading desk, MANTLE the bookcase
##  2 Flying Books       two great BOOKS flap you up across the dark, one gap each
##  3 The Ink Ford       a plank bridge over an INK RIVER that floods, a hop over a second one
##  4 Sliding Shelves    a long beam through two SLIDING BOOKSHELVES (gap walls), MANTLE the cabinet
##  5 The Spell Circle   a SPELL CIRCLE throws you across the chasm, WALL RUN the shelf
##  6 The Stacks         BRANCH: the beam through two HOURGLASS GATES | WALL RUN the case, MANTLE it
##                       [shortcut: four hidden posts down the middle at 93/91%]
##  7 Falling Tomes      a beam under two FALLING TOMES (falling blocks), MANTLE, two posts
##  8 The Quill Line     ride the QUILL LINE (zipline) over the hall, a landing hop
##  9 Lectern Aisle      the walk past two LECTERN RAMS (pistons), a HOURGLASS GATE, MANTLE
## 10 Inkwell Hall       BRANCH: the candle-beam (laser) over an INK bridge | a flying BOOK to the stacks
##                       [shortcut: the SPELL DOOR (portal) on the hanging post]
## 11 The Lectern        a SEESAW lectern across the gap, then a book ride
## 12 Reading Wing       BRANCH: the DOOR (portal) | WALL RUN the chimney [shortcut: a 4.1 m MANTLE]
## 13 The Book Press     two BOOK PRESSES (crushers), a CIRCLE throw, MANTLE
## 14 Floating Stairs    seven CRUMBLING steps round a QUILL SWEEPER [shortcut: a circle throw]
## 15 The Great Shelf    three chained WALL RUNS up the shelves, an INK bridge at the top
## 16 The Observatory    a SLIDING SHELF, an HOURGLASS GATE, a circle throw, the foot of the tower
## 17 THE ORRERY TOWER   SET PIECE: ride the rotating rings up to the open grimoire, the finish
##
## Arcane mechanics (own scripts): ArcaneBook (flying books), ArcaneInk (ink rivers that flood),
## ArcaneCircle (spell circles), ArcaneHourglass (time gates). Kit obstacles (docs/KIT_OBSTACLES.md):
## gap_wall (sliding shelves), falling_block (tomes), zipline (the quill line), seesaw (the lectern).
## Visuals: visual/arcane_{sky,decor,fx}.gd, arcane_{tile,ink,sheet,circle,books}.gdshader. Route
## variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut.
## Every wait the bot makes holds for 1.5 s more.

const GOLD := Color(1.0, 0.78, 0.35)
const VIOLET := Color(0.62, 0.4, 1.0)
const PARCHMENT := Color(0.96, 0.9, 0.74)
const OXBLOOD := Color(0.5, 0.1, 0.22)

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 6
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: ArcaneDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable surface (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _floors: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "arcane"
	music_track = "arcane"
	kill_y = -60.0
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


## A walkable slab (local top centre `c`, sx across, sz along).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, keel: float = 0.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw)
	_floors.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": thick})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A small floating post (a landing about a metre across).
func _post(c: Vector3, sx: float = 1.2, sz: float = 1.2, style: String = "accent") -> Dictionary:
	return _blk(c, sx, sz, style, 0.6)


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
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var col: Color = GOLD if _cp_world.size() % 2 == 0 else VIOLET
	var fx: Array[GPUParticles3D] = ArcaneFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: arcane_checkpoint - a stage banked: a celesta glissando and a flutter of pages
			WorldAudio.at(self, "arcane_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


# ---- machine helpers ----------------------------------------------------------------------------

## A flying book (an ArcaneBook mover): `top` is its top centre at the start (local), `offset` the
## far end (local offset), one full there-and-back trip takes `period`.
func _book(top: Vector3, size: Vector3, offset: Vector3, period: float, phase: float, cover: Color = OXBLOOD) -> ArcaneBook:
	var bk := ArcaneBook.new()
	bk.size = size
	bk.points = [Vector3.ZERO, _d(offset)]
	bk.period = period
	bk.phase = phase
	bk.cover = cover
	bk.position = _w(top) - Vector3(0, size.y * 0.5, 0)
	add_child(bk)
	return bk


## An ink river across the path under a bridge (local `top` = the bridge deck, gap = its length).
func _ink(top: Vector3, gap: float, period: float, phase: float, width: float = 14.0) -> ArcaneInk:
	var ink := ArcaneInk.new()
	ink.size = Vector2(width, gap)
	ink.period = period
	ink.phase = phase
	ink.rotation.y = deg_to_rad(_yaw)
	ink.position = _w(top)
	add_child(ink)
	return ink


## An hourglass time gate across the path (local floor point).
func _gate(c: Vector3, period: float, phase: float, open_time: float = 4.4, width: float = 3.0) -> ArcaneHourglass:
	var g := ArcaneHourglass.new()
	g.width = width
	g.period = period
	g.phase = phase
	g.open_time = open_time
	g.rotation.y = deg_to_rad(_yaw)
	g.position = _w(c)
	add_child(g)
	return g


## A spell circle at local top centre `c` that throws you to local feet position `target`.
func _circle(c: Vector3, target: Vector3, arc: float = 3.2, radius: float = 1.6, tint: Color = VIOLET) -> ArcaneCircle:
	var ac := ArcaneCircle.new()
	ac.radius = radius
	ac.arc = arc
	ac.tint = tint
	ac.target = _w(target)
	ac.position = _w(c)
	add_child(ac)
	_floors.append({"top": _w(c), "size": Vector3(radius * 2.0, 0, radius * 2.0), "drop": 0.3})
	return ac


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

## Stand still until test() is true (a wait: the 1.0 s human-pause check applies after it).
func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Run to `from`, jump, and fly (position-hold steering) to `to`: for arcs a rift bends.
func _fly(from: Vector3, to: Vector3, gain: float = 1.6, damp: float = 0.45) -> void:
	route.append({"kind": "desert_fly", "jump_from": from, "to": to, "gain": gain, "damp": damp})


## Board a mover (flying book) from `from`, ride it, and hop off to `to` once `until` is true.
func _ride(from: Vector3, car: MovingPlatform, local: Vector3, to: Vector3, until: Callable, reach: float = 3.2) -> void:
	route.append({"kind": "candy_board", "from": from, "cars": [car], "reach": reach, "lead": 0.45, "local": local})
	route.append({"kind": "candy_ride", "stand": local - Vector3(0, 0.0, 0), "to": to, "until": until})


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


## True when every [gate, from, to] stays open over [now + from, now + to].
static func _gates_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as ArcaneHourglass).open_for(Game.course_time + float(e[1]), float(e[2]) - float(e[1])):
			return false
	return true


## True when every [ink, from, to] stays dry over [now + from, now + to].
static func _inks_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as ArcaneInk).dry_for(Game.course_time + float(e[1]), float(e[2]) - float(e[1])):
			return false
	return true


## True when every [wall, from, to] has its doorway on the lane over [now + from, now + to].
static func _walls_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as GapWall).is_open_for(Game.course_time + float(e[1]), float(e[2]) - float(e[1])):
			return false
	return true


## True when every [block, from, to] is clear over [now + from, now + to].
static func _blocks_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as FallingBlock).is_clear_for(Game.course_time + float(e[1]), float(e[2]) - float(e[1])):
			return false
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	deco = ArcaneDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10]
	var last: int = stages.size() if DEV_LAST <= 0 else mini(DEV_LAST, stages.size())
	var starts: Array[int] = []
	var origins: Array[Vector3] = []
	_frame(Vector3.ZERO, yaws[0])
	for i: int in last:
		_next_yaw = yaws[i + 1]
		starts.append(route.size())
		origins.append(_o)
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	starts.append(route.size())
	origins.append(_o)
	if last == stages.size() and false:
		pass
	else:
		# (dev) the finish right after the last stage built
		var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
		var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "main", 1.2)
		kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
		_finish_pos = _w(Vector3(0, 0, -9.5))
		_hop(cp0, fin)
		r_walk(_w(Vector3(0, 0, -9.8)))
	_arcane_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


# ---- stage 1: The Reading Room - a stair of floating posts, a desk, mantle the bookcase -----------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(12, 2, 12), "main", 0.0, _yaw)
	_floors.append({"top": _w(Vector3.ZERO), "size": Vector3(12, 0, 12), "drop": 2.0})
	var start: Dictionary = _area(Vector3(0, 0, 0), 6.0, 6.0)
	var p1: Dictionary = _post(_ahead(start, 0.86, 0.0, 1.4), 1.4, 1.4)
	var p2: Dictionary = _post(_ahead(p1, 0.87, 0.6, 1.3, -0.4), 1.3, 1.3)
	var p3: Dictionary = _post(_ahead(p2, 0.88, 0.6, 1.2, 0.4))
	var desk: Dictionary = _blk(_ahead(p3, 0.86, 0.0, 3.0, -0.4), 2.0, 3.0, "alt", 0.6)
	var bc: Vector3 = desk["c"]
	var front: float = bc.z - 1.5
	# the bookcase: a mantle wall across a 1.6 m gap, its top 3.3 m above the desk
	var case_top := Vector3(bc.x, bc.y + 3.3, front - 1.6 - 0.7)
	var case_: Dictionary = _ledge(case_top, Vector3(2.6, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(case_, 0.86, 0.0, 5.0, -bc.x))
	_hop(start, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, desk, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(case_top + Vector3(0, 0, 0.2)))
	_hop(case_, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Flying Books - two great books flap you up across the dark --------------------------

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var dock_a: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 3.0), 3.4, 3.0)
	var ac: Vector3 = dock_a["c"]
	var a_front: float = ac.z - 1.5
	var bsz := Vector3(2.8, 0.35, 2.4)
	var local := Vector3(0, bsz.y * 0.5 + 0.05, 0)
	# book 1: 13 m ahead, 2.5 m up; it rests 1.2 m off each dock
	var run: float = 13.0
	var rise: float = 2.5
	var b1_top := Vector3(ac.x, ac.y, a_front - 1.2 - bsz.z * 0.5)
	var b1: ArcaneBook = _book(b1_top, bsz, Vector3(0, rise, -run), 9.0, 0.0)
	var b1_far: Vector3 = b1_top + Vector3(0, rise, -run)
	var dock_b: Dictionary = _blk(Vector3(ac.x, ac.y + rise, b1_far.z - bsz.z * 0.5 - 1.2 - 1.5), 3.4, 3.0)
	var bc: Vector3 = dock_b["c"]
	var b_front: float = bc.z - 1.5
	# book 2: 13 m on and 2.5 m up again, the other way round in its beat
	var b2_top := Vector3(bc.x, bc.y, b_front - 1.2 - bsz.z * 0.5)
	var b2: ArcaneBook = _book(b2_top, bsz, Vector3(0, rise, -run), 9.0, 0.5, Color(0.12, 0.2, 0.5))
	var b2_far: Vector3 = b2_top + Vector3(0, rise, -run)
	var dock_c: Dictionary = _blk(Vector3(bc.x, bc.y + rise, b2_far.z - bsz.z * 0.5 - 1.2 - 1.5), 3.4, 3.0)
	var p: Dictionary = _post(_ahead(dock_c, 0.87, 0.0, 1.4, 0.4), 1.4, 1.4)
	var cp: Dictionary = _cp(_ahead(p, 0.86, 0.0, 5.0, -(p["c"] as Vector3).x))
	_hop(cp0, dock_a)
	r_walk(_w(Vector3(ac.x, ac.y, ac.z + 0.3)))
	var far1w: Vector3 = _w(b1_far) - Vector3(0, bsz.y * 0.5, 0)
	_ride(_w(Vector3(ac.x, ac.y, a_front + 0.45)), b1, local, _w(bc + Vector3(0, 0, 0.3)),
		func() -> bool: return b1.global_position.distance_to(far1w) < 0.8)
	r_walk(_w(Vector3(bc.x, bc.y, bc.z + 0.3)))
	var far2w: Vector3 = _w(b2_far) - Vector3(0, bsz.y * 0.5, 0)
	_ride(_w(Vector3(bc.x, bc.y, b_front + 0.45)), b2, local, _w((dock_c["c"] as Vector3) + Vector3(0, 0, 0.3)),
		func() -> bool: return b2.global_position.distance_to(far2w) < 0.8)
	_hop(dock_c, p)
	_hop(p, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: The Ink Ford - a plank over an ink river that floods, a hop over a second ---------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var bank_a: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 3.2), 3.4, 3.2)
	var a: Vector3 = bank_a["c"]
	var a_front: float = a.z - 1.6
	var gap1: float = 4.0
	var bank_b: Dictionary = _blk(Vector3(a.x, a.y, a_front - gap1 - 1.6), 3.4, 3.2)
	var b: Vector3 = bank_b["c"]
	var b_front: float = b.z - 1.6
	_blk(Vector3(a.x, a.y, a_front - gap1 * 0.5), 1.6, gap1 + 0.04, "alt", 0.3, 0.0)
	var ink1: ArcaneInk = _ink(Vector3(a.x, a.y, a_front - gap1 * 0.5), gap1, 8.0, 0.0)
	# the second river is jumped, no bridge: the landing is a 2.4 m slab
	var c: Vector3 = _ahead(bank_b, 0.88, 0.0, 2.4)
	var land: Dictionary = _blk(c, 2.4, 2.4, "alt", 0.6)
	var gap2: float = b_front - (c.z + 1.2)
	var ink2: ArcaneInk = _ink(Vector3(b.x, b.y, b_front - gap2 * 0.5), gap2, 8.0, 0.35)
	var p1: Dictionary = _post(_ahead(land, 0.87, 0.6, 1.3, 0.4), 1.3, 1.3)
	var p2: Dictionary = _post(_ahead(p1, 0.88, 0.0, 1.2, -0.4))
	var cp: Dictionary = _cp(_ahead(p2, 0.86, 0.0, 5.0, -(p2["c"] as Vector3).x))
	_hop(cp0, bank_a)
	r_walk(_w(Vector3(a.x, a.y, a.z + 0.5)))
	_wait(func() -> bool: return _inks_ok([[ink1, 0.0, 3.0]]), _w(Vector3(a.x, a.y, a.z + 0.5)))
	r_walk(_w(Vector3(b.x, b.y, b.z + 0.5)))
	_wait(func() -> bool: return _inks_ok([[ink2, 0.6, 3.0]]), _w(Vector3(b.x, b.y, b.z + 0.5)))
	_hop(bank_b, land)
	_hop(land, p1)
	_hop(p1, p2)
	_hop(p2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Sliding Shelves - a beam through two sliding bookshelves, mantle the cabinet -------------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.87, 0.0, 1.3))
	var beam: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 22.0, 0.0), 1.4, 22.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var back: float = bc.z + 11.0
	var front: float = bc.z - 11.0
	var z1: float = back - 8.0
	var z2: float = back - 16.0
	var opts: Dictionary = {"open_time": 3.6, "move_time": 1.2, "warn": 1.1}
	var w1: GapWall = kit.gap_wall(_w(Vector3(bc.x, bc.y, z1)), _yaw, 3.4, 9.0, 0.0, opts)
	var w2: GapWall = kit.gap_wall(_w(Vector3(bc.x, bc.y, z2)), _yaw, 3.4, 9.0, 0.4, opts)
	var cab_top := Vector3(bc.x, bc.y + 3.3, front - 1.6 - 0.7)
	var cab: Dictionary = _ledge(cab_top, Vector3(2.8, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(cab, 0.85, 0.0, 5.0, -bc.x))
	_hop(cp0, p1)
	_hop(p1, beam, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(bc.x, bc.y, z1 + 3.5)))
	_wait(func() -> bool: return _walls_ok([[w1, 0.0, 2.4]]), _w(Vector3(bc.x, bc.y, z1 + 3.5)))
	r_walk(_w(Vector3(bc.x, bc.y, z2 + 3.5)))
	_wait(func() -> bool: return _walls_ok([[w2, 0.0, 2.4]]), _w(Vector3(bc.x, bc.y, z2 + 3.5)))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(cab_top + Vector3(0, 0, 0.3)))
	_hop(cab, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: The Spell Circle - thrown across the chasm, wall run the shelf --------------------------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.87, 0.0, 1.4), 1.4, 1.4)
	var cc: Vector3 = _ahead(p1, 0.86, 0.0, 3.2)
	var disc_c := Vector3(cc.x, cc.y, cc.z)
	var land_c := Vector3(0, cc.y + 2.0, cc.z - 15.0)
	var land: Dictionary = _blk(land_c, 11.0, 5.2, "main", 1.0)
	var circ: ArcaneCircle = _circle(disc_c, Vector3(land_c.x, land_c.y, land_c.z), 3.4)
	var f0: float = land_c.z - 2.6
	# the shelf wall-run: along the right end of the landing, over the void
	kit.wallrun(_w(Vector3(5.7, land_c.y + 1.2, f0 - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, land_c.y, f0 - 19.6), 2.2, 2.2)
	var cp: Dictionary = _cp(_ahead(pb, 0.86, 0.0, 5.0, -3.6))
	_hop(cp0, p1)
	_hop(p1, _area(disc_c, 1.6, 1.6))
	r_walk(_w(disc_c + Vector3(0, 0, -0.2)))
	route.append({"kind": "kick", "from": _w(disc_c + Vector3(0, 0, -0.2)), "to": _w(land_c)})
	r_walk(_w(Vector3(3.6, land_c.y, f0 + 2.2)))
	r_wallrun(_w(Vector3(4.0, land_c.y, f0 + 0.35)), _w(Vector3(5.2, land_c.y + 1.4, f0 - 3.4)),
		_w(Vector3(5.2, land_c.y + 1.4, f0 - 12.6)), _w(Vector3(3.6, land_c.y, f0 - 19.4)))
	_hop(pb, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: The Stacks (BRANCH) - the beam through two hourglass gates | wall run the case ---------------
# [shortcut: four hidden posts down the middle at 93 / 91%]

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT (main): a beam through two hourglass gates, then a post
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.5)
	var beam: Dictionary = _blk(_ahead(left, 0.86, 0.0, 14.0), 1.2, 14.0, "alt", 0.6)
	var bz: float = (beam["c"] as Vector3).z
	var g1: ArcaneHourglass = _gate(Vector3(-3.5, 0, bz + 3.0), 8.0, 0.0, 4.4)
	var g2: ArcaneHourglass = _gate(Vector3(-3.5, 0, bz - 2.0), 8.0, 0.0, 4.4)
	var pa: Dictionary = _post(_ahead(beam, 0.88, 0.0, 1.2))
	var merge: Dictionary = _blk(Vector3(0, 0, (pa["c"] as Vector3).z - 0.6 - 4.2 - 1.5), 11.0, 3.0)
	var mc: Vector3 = merge["c"]
	# RIGHT (alt): the case's wall run, a post, mantle the top, drop to the merge
	kit.wallrun(_w(Vector3(5.7, 1.2, f0 - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, 0.0, f0 - 19.6), 2.0, 2.0)
	var case_top := Vector3(3.6, 3.3, f0 - 19.6 - 1.0 - 1.6 - 0.8)
	var case_: Dictionary = _ledge(case_top, Vector3(2.6, 9.0, 1.6))
	# SHORTCUT: hidden posts down the middle
	var hids: Array[Dictionary] = []
	var hp: Dictionary = _area(fc, 5.5, 1.5)
	for i: int in 4:
		hp = _post(_ahead(hp, 0.93 if i == 0 else 0.91, 0.6 if i == 0 else 0.0, 1.2), 1.2, 1.2, "accent")
		hids.append(hp)
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		var prev: Dictionary = _area(fc, 5.5, 1.5)
		for h: Dictionary in hids:
			_hop(prev, h)
			prev = h
		_hop(prev, merge, Vector3(0, 0, 0.4))
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_hop(left, beam, Vector3(0, 0, 0.6))
		r_walk(_w(Vector3(-3.5, 0, bz + 6.0)))
		_wait(func() -> bool: return _gates_ok([[g1, 0.0, 2.4], [g2, 0.55, 2.9]]), _w(Vector3(-3.5, 0, bz + 6.0)))
		r_walk(_w(Vector3(-3.5, 0, bz - 6.0)))
		_hop(beam, pa)
		_hop(pa, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.0, 0, f0 + 0.35)), _w(Vector3(5.2, 1.4, f0 - 3.4)), _w(Vector3(5.2, 1.4, f0 - 12.6)), _w(Vector3(3.6, 0, f0 - 19.4)))
		r_mantle(_w(Vector3(3.6, 0, f0 - 19.6 - 0.65)), _w(case_top + Vector3(0, 0, 0.2)))
		_hop(case_, merge, Vector3(3.6, 0, 0.6))
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	pb.clear()
	return cp["c"]


# ---- stage 7: Falling Tomes - the beam under two falling books, mantle, two posts ------------------

func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.2))
	var walk: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 18.0), 1.4, 18.0, "alt", 0.6)
	var wc: Vector3 = walk["c"]
	var back: float = wc.z + 9.0
	var front: float = wc.z - 9.0
	var t1: FallingBlock = kit.falling_block(_w(Vector3(wc.x, wc.y, back - 6.0)), Vector3(3.0, 1.6, 3.0), 7.0, 6.5, 0.0)
	var t2: FallingBlock = kit.falling_block(_w(Vector3(wc.x, wc.y, back - 12.0)), Vector3(3.0, 1.6, 3.0), 7.0, 6.5, 0.0)
	var ledge_top := Vector3(wc.x, wc.y + 3.3, front - 1.6 - 0.7)
	var ld: Dictionary = _ledge(ledge_top, Vector3(3.0, 9.0, 1.4))
	var p2: Dictionary = _post(_ahead(ld, 0.87, 0.0, 1.2, 0.4))
	var p3: Dictionary = _post(_ahead(p2, 0.88, 0.6, 1.2, -0.4))
	var cp: Dictionary = _cp(_ahead(p3, 0.86, 0.0, 5.0, -(p3["c"] as Vector3).x))
	_hop(cp0, p1)
	_hop(p1, walk, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(wc.x, wc.y, back - 1.8)))
	_wait(func() -> bool: return _blocks_ok([[t1, 0.15, 2.45], [t2, 0.8, 3.1]]), _w(Vector3(wc.x, wc.y, back - 1.8)))
	r_walk(_w(Vector3(wc.x, wc.y, front + 0.9)))
	r_mantle(_w(Vector3(wc.x, wc.y, front + 0.35)), _w(ledge_top + Vector3(0, 0, 0.3)))
	_hop(ld, p2)
	_hop(p2, p3)
	_hop(p3, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 8: The Quill Line - ride the line over the hall, then a landing hop chain ----------------

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var dock: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 5.0), 6.0, 5.0)
	var dc: Vector3 = dock["c"]
	var start_top := Vector3(dc.x, dc.y, dc.z - 0.5)
	var end_top: Vector3 = start_top + Vector3(0, 0, -26.0)
	var land: Dictionary = _blk(Vector3(dc.x, dc.y, start_top.z - 29.0), 14.0, 14.0, "main", 1.0)
	var zip: Zipline = kit.zipline(_w(start_top), _w(end_top), 11.0, 1.6, 0.0)
	var p1: Dictionary = _post(_ahead(land, 0.87, 0.0, 1.3, 0.4))
	var p2: Dictionary = _post(_ahead(p1, 0.88, 0.6, 1.2, -0.4))
	var cp: Dictionary = _cp(_ahead(p2, 0.86, 0.0, 5.0, -(p2["c"] as Vector3).x))
	_hop(cp0, dock)
	r_zipline(zip, _w(start_top + Vector3(0, 2.2, -20.0)), 0.6, _w(Vector3(dc.x, dc.y, start_top.z - 28.0)))
	r_walk(_w(Vector3(dc.x, dc.y, (land["c"] as Vector3).z - 2.0)))
	_hop(land, p1)
	_hop(p1, p2)
	_hop(p2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Lectern Aisle - past two lectern rams, an hourglass gate, mantle -------------------------

func _lectern(wc: Vector3, z: float, dir: float, phase: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.2)
	var x: float = wc.x - dir * (0.6 + 0.6 + 0.15)
	return kit.piston(_w(Vector3(x, wc.y + 1.35, z)), size, _yaw - 90.0 * dir, 2.6, 6.5, phase, 10.0)


func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.87, 0.0, 1.3))
	var aisle: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 20.0), 1.4, 20.0, "alt", 0.6)
	var wc: Vector3 = aisle["c"]
	var back: float = wc.z + 10.0
	var front: float = wc.z - 10.0
	var ra: Piston = _lectern(wc, back - 5.0, 1.0, 0.0)
	var rb: Piston = _lectern(wc, back - 9.0, -1.0, fposmod(-0.55 / 6.5, 1.0))
	var gate: ArcaneHourglass = _gate(Vector3(wc.x, wc.y, back - 14.0), 8.0, 0.25, 4.4)
	var ledge_top := Vector3(wc.x, wc.y + 3.3, front - 1.6 - 0.7)
	var ld: Dictionary = _ledge(ledge_top, Vector3(2.8, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(ld, 0.85, 0.0, 5.0, -wc.x))
	_hop(cp0, p1)
	_hop(p1, aisle, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(wc.x, wc.y, back - 2.0)))
	var tA: float = 0.65
	var tB: float = 1.2
	var tG: float = 1.75
	_wait(func() -> bool: return _ram_clear(ra, tA - 0.3, tA + 0.4 + 1.5) and _ram_clear(rb, tB - 0.3, tB + 0.4 + 1.5) \
		and _gates_ok([[gate, tG - 0.2, tG + 0.6 + 1.5]]), _w(Vector3(wc.x, wc.y, back - 2.0)))
	r_walk(_w(Vector3(wc.x, wc.y, front + 0.9)))
	r_mantle(_w(Vector3(wc.x, wc.y, front + 0.35)), _w(ledge_top + Vector3(0, 0, 0.3)))
	_hop(ld, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 10: Inkwell Hall (BRANCH) - candle beam and an ink bridge | a flying book --------------------
# [shortcut: the spell door on the hanging post]

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT (main): a beam under a candle beam (laser), a plank over an ink river, the merge
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.5)
	var beam: Dictionary = _blk(_ahead(left, 0.86, 0.0, 12.0), 1.2, 12.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var bfront: float = bc.z - 6.0
	var lz: float = bc.z + 1.5
	var gate: LaserGate = kit.laser(_w(Vector3(bc.x, bc.y + 1.2, lz)), Vector3(3.2, 2.4, 0.2), 5.0, 0.3, 0.0, _yaw)
	var ink_gap: float = 4.0
	var mz: float = bfront - ink_gap - 1.5
	var merge: Dictionary = _blk(Vector3(0, 0, mz), 11.0, 3.0)
	_blk(Vector3(bc.x, bc.y, bfront - ink_gap * 0.5), 1.6, ink_gap + 0.04, "alt", 0.3, 0.0)
	var ink: ArcaneInk = _ink(Vector3(bc.x, bc.y, bfront - ink_gap * 0.5), ink_gap, 8.0, 0.0)
	# RIGHT (alt): a flying book from the fork's right end to the merge
	var bsz := Vector3(2.8, 0.35, 2.4)
	var local := Vector3(0, bsz.y * 0.5 + 0.05, 0)
	var rb_top := Vector3(3.6, 0.0, f0 - 1.2 - bsz.z * 0.5)
	var far_z: float = (mz + 1.5) + 1.2 + bsz.z * 0.5
	var book: ArcaneBook = _book(rb_top, bsz, Vector3(0, 0, far_z - rb_top.z), 11.0, 0.0, Color(0.1, 0.3, 0.25))
	var book_far: Vector3 = rb_top + Vector3(0, 0, far_z - rb_top.z)
	# SHORTCUT: a post hangs off the fork's front and the spell door on it opens onto the merge
	var sp: Dictionary = _post(_ahead(_area(fc, 5.5, 1.5), 0.93, 0.0, 1.2), 1.2, 1.2, "accent")
	var spc: Vector3 = sp["c"]
	var sdoor: WarpPortal = kit.portal(_w(spc + Vector3(0, 0, -0.3)), _yaw, _w(Vector3(0.5, 0, mz + 0.8)), _yaw, 6.0)
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		_hop(_area(fc, 5.5, 1.5), sp, Vector3(0, 0, 0.35))
		r_portal(_w(spc + Vector3(0, 0, -0.6)), sdoor.exit_point())
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_hop(left, beam, Vector3(0, 0, 0.6))
		r_walk(_w(Vector3(bc.x, bc.y, bc.z + 5.0)))
		_wait(func() -> bool: return _dark(gate, 0.1, 0.9 + 1.5) and _inks_ok([[ink, 0.9, 2.8 + 1.5]]), _w(Vector3(bc.x, bc.y, bc.z + 5.0)))
		r_walk(_w(Vector3(bc.x, bc.y, mz + 0.8)))
		r_walk(_w(Vector3(0, 0, mz + 0.6)))
	else:
		r_walk(_w(Vector3(3.6, 0, f0 + 1.6)))
		var far_w: Vector3 = _w(book_far) - Vector3(0, bsz.y * 0.5, 0)
		_ride(_w(Vector3(3.6, 0, f0 + 0.45)), book, local, _w(Vector3(3.6, 0, mz + 0.3)),
			func() -> bool: return book.global_position.distance_to(far_w) < 0.8)
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
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
	_env.background_mode = Environment.BG_SKY
	_env.sky = ArcaneSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.82, 0.62, 0.8)
	_env.ambient_light_energy = 0.7
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.2, 0.1, 0.26)
	_env.fog_density = 0.0045
	_env.fog_aerial_perspective = 0.5
	_env.fog_sky_affect = 0.25
	_env.fog_sun_scatter = 0.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.1
	_env.adjustment_contrast = 1.06
	# a warm candle-gold key light from high among the shelves, and a violet fill from below
	_sun.light_color = Color(1.0, 0.82, 0.58)
	_sun.light_energy = 1.1
	_sun.rotation_degrees = Vector3(-52, 28, 0)
	_fill.light_color = Color(0.62, 0.42, 1.0)
	_fill.light_energy = 0.4
	_fill.rotation_degrees = Vector3(32, -150, 0)


## Swap every walkable surface to the parquet-and-leather shader (same colours and sizes).
func _arcane_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = preload("res://visual/arcane_tile.gdshader")
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r
