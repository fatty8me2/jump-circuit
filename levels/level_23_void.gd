extends LevelBase
## 23. THE VOID - the last level before the finale and the hardest of the set. A surreal dream of
## floating impossible geometry coming apart in a violet-black nothing: clean white chessboard floors,
## doors standing open on nothing, Escher stairs at every angle, clocks with no hands, rooms hanging
## upside down, mirrors, and a sky shattered into shards (some show the wrong sky behind them).
## Fifteen stages, fourteen checkpoints; it is hard through precision (twelve-plus main-path jumps at
## 85-94% of max reach onto 1.2-1.4 m posts), pace and combinations, never through blind timing.
##
##  1 The Threshold     a stair of four floating posts, MANTLE the great door across a gap
##  2 Phase Steps       the PINK pair, a white spacer, the CYAN pair (the sets swap on one beat), WALL RUN
##                      the mirror over the void onto a post
##  3 Mirror Beam       two posts, the 14 m beam through two MIRROR BEAMS (lasers), MANTLE the wardrobe
##  4 The Rift          two floating leaps through a LOW-GRAVITY RIFT, then the long jump out
##  5 Tumbling Rooms    four little ROOMS that turn over on a wave (a wall becomes the floor), MANTLE out
##  6 Drawer Hall       BRANCH: the beam the DRAWERS (pistons) shoot across | WALL RUN the bookcase,
##                      MANTLE the case [shortcut: four hidden posts down the middle at 94/92%]
##  7 Clockfall         the walk under two FALLING CLOCKS (crushers), MANTLE under the third, two posts
##  8 Door Maze         BRANCH: the DOOR (portal) up to a lintel beam, two drops | the UP-DRAFT RIFT to an
##                      arch, two posts [shortcut: the small door on the hanging post]
##  9 Chess Turntable   board the turning chessboard (spinner), ride it, leap off to the pawn posts
## 10 Inverted Room     a post, the UP-DRAFT into the room hanging overhead, its three-panel WALL-RUN
##                      chimney, out onto its floor
## 11 Mirror Gallery    BRANCH: pink tiles and a MIRROR BEAM | two chained mirror WALL RUNS
##                      [shortcut: a 4.1 m MANTLE up the broken column, then its 1 m cornices]
## 12 Escher Stairs     six CRUMBLING steps, a DRAWER shooting across the landing between them
## 13 Rooms and Rift    three faster TUMBLING ROOMS, a LOW-GRAVITY leap up [shortcut: WALL RUN the rooms]
## 14 The Unravelling   pink tiles, the walk under a FALLING CLOCK, the longest jump (94%), MANTLE
## 15 THE COLLAPSE      SET PIECE: step on the first fragment and the dream falls apart behind you in a
##                      wave (each fragment cracks pink 0.95 s before it drops); outrun it up twelve
##                      fragments to the door in the sky, the finish
##
## Void mechanics (own scripts): VoidPhase (pink / cyan phase tiles), VoidRift (low-gravity and up-draft
## rifts), VoidTumble (tumbling rooms), VoidCollapse (the collapse). Visuals: visual/void_{sky,decor,fx}.gd,
## void_{tile,room,shard,floor}.gdshader. Route variants for the bot: 0 = main line, 1 = every
## alternative branch, 2 = main line + every shortcut. Every wait the bot makes holds for 1.5 s more.

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.32, 0.9, 1.0)
const WHITE := Color(0.92, 0.9, 0.97)
const VIOLET := Color(0.55, 0.3, 0.95)

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: VoidDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable surface (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _floors: Array[Dictionary] = []
## Bursts that fire when the player arrives at a spot (portal exits): {"at", "p": [GPUParticles3D], "cool"}
var _arrivals: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "void"
	music_track = "void"
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


## A walkable white slab (local top centre `c`, sx across, sz along).
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
	var col: Color = PINK if _cp_world.size() % 2 == 0 else CYAN
	var fx: Array[GPUParticles3D] = VoidFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: void_checkpoint - a stage banked: a glassy bell bloom and a shower of light
			WorldAudio.at(self, "void_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


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


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	deco = VoidDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14]
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
	if last == stages.size():
		_stage_15()
	else:
		# (dev) the finish right after the last stage built
		var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
		var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "main", 1.2)
		kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
		_finish_pos = _w(Vector3(0, 0, -9.5))
		_hop(cp0, fin)
		r_walk(_w(Vector3(0, 0, -9.8)))
	_surroundings()
	_void_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


# ---- stage 1: The Threshold - a stair of floating posts, mantle the door ------------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(12, 2, 12), "main", 0.0, _yaw)
	_floors.append({"top": _w(Vector3.ZERO), "size": Vector3(12, 0, 12), "drop": 2.0})
	var start: Dictionary = _area(Vector3(0, 0, 0), 6.0, 6.0)
	var p1: Dictionary = _post(_ahead(start, 0.86, 0.0, 1.3), 1.3, 1.3)
	var p2: Dictionary = _post(_ahead(p1, 0.88, 0.6, 1.2, -0.4))
	var p3: Dictionary = _post(_ahead(p2, 0.90, 0.6, 1.2, 0.4))
	var beam: Dictionary = _blk(_ahead(p3, 0.86, 0.0, 3.0, -0.4), 1.2, 3.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 1.5
	# the door: a mantle wall across a 1.6 m gap, its top 3.3 m above the beam
	var door_top := Vector3(bc.x, bc.y + 3.3, front - 1.6 - 0.7)
	var door: Dictionary = _ledge(door_top, Vector3(2.6, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(door, 0.86, 0.0, 5.0, -bc.x))
	_hop(start, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, beam, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(door_top + Vector3(0, 0, 0.2)))
	_hop(door, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the mantle wall is a great door: its frame, panels and a glowing knob; an arch behind the start
	_door_dress(door_top, 2.6, 9.0, 1.4)
	deco.arch(_w(Vector3(0, 0, 7.2)), VoidDecor.turn(deg_to_rad(_yaw)), 9.0, 10.0, PINK)
	deco.door(_w(Vector3(5.5, 1.5, -12.0)), VoidDecor.turn(deg_to_rad(_yaw) - 0.5, 0.0, 0.15), 1.6, 2.9, CYAN, 0.8)
	deco.door(_w(Vector3(-6.0, -1.0, -20.0)), VoidDecor.turn(deg_to_rad(_yaw) + 0.7, 0.0, -0.2), 1.6, 2.9, PINK, 1.1)
	deco.clock(_w(Vector3(16.0, 9.0, -24.0)), VoidDecor.turn(deg_to_rad(_yaw) + 1.2, 1.3, 0.2), 5.5, 0.25)
	deco.stairs(_w(Vector3(-9.0, -3.0, -6.0)), VoidDecor.turn(deg_to_rad(_yaw) + 0.4, 0.0, 0.6), 9, 1.8, 0.35, 0.5)
	return cp["c"]


## Frame, panels and a knob on a mantle wall dressed as a door (local top centre, its size).
func _door_dress(top: Vector3, w: float, h: float, d: float) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(_b, _w(top - Vector3(0, h * 0.5, 0)))
	add_child(n)
	var white: StandardMaterial3D = Look.flat(WHITE, 0.45)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.24, h + 0.4, d + 0.3), white, Vector3(sx * (w * 0.5 + 0.12), -0.2, 0)))
	for sz: float in [-1.0, 1.0]:
		for i: int in 2:
			n.add_child(Look.box(Vector3(w * 0.66, h * 0.3, 0.04), Look.flat(Color(0.8, 0.77, 0.88), 0.55), Vector3(0, -h * 0.5 + h * (0.24 + 0.42 * float(i)), sz * (d * 0.5 + 0.02))))
		var knob := Look.sphere(0.1, Look.flat(PINK, 0.3, 0.0, 2.4), Vector3(w * 0.32, -h * 0.5 + h * 0.5, sz * (d * 0.5 + 0.08)))
		n.add_child(knob)


# ---- stage 2: Phase Steps - the pink and cyan sets, then the mirror wall ------------------------

## A phase tile at local top `c` (set 0 = pink, 1 = cyan).
func _phase_tile(c: Vector3, set_id: int, period: float, phase: float, sx: float = 1.3, sz: float = 1.3) -> VoidPhase:
	var p := VoidPhase.new()
	p.size = Vector3(sx, 0.4, sz)
	p.period = period
	p.phase = phase
	p.set_id = set_id
	p.rotation.y = deg_to_rad(_yaw)
	p.position = _w(c) - Vector3(0, 0.2, 0)
	add_child(p)
	_floors.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": 0.4})
	return p


## True when every [tile, from, to] stays solid over [now + from, now + to].
static func _phases_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as VoidPhase).solid_over(Game.course_time, float(e[1]), float(e[2])):
			return false
	return true


func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var period: float = 6.4
	var c1: Vector3 = _ahead(cp0, 0.86, 0.0, 1.3)
	var t1: VoidPhase = _phase_tile(c1, 0, period, 0.0)
	var a1: Dictionary = _area(c1, 0.65, 0.65)
	var c2: Vector3 = _ahead(a1, 0.88, 0.6, 1.3, 0.4)
	var t2: VoidPhase = _phase_tile(c2, 0, period, 0.0)
	var a2: Dictionary = _area(c2, 0.65, 0.65)
	var sp: Dictionary = _blk(_ahead(a2, 0.86, 0.0, 4.0, -0.4), 1.2, 4.0, "alt", 0.6)
	var c3: Vector3 = _ahead(sp, 0.88, 0.0, 1.3, 0.0)
	var t3: VoidPhase = _phase_tile(c3, 1, period, 0.0)
	var a3: Dictionary = _area(c3, 0.65, 0.65)
	var c4: Vector3 = _ahead(a3, 0.88, 0.6, 1.3, -0.4)
	var t4: VoidPhase = _phase_tile(c4, 1, period, 0.0)
	var a4: Dictionary = _area(c4, 0.65, 0.65)
	var w2: Dictionary = _post(_ahead(a4, 0.87, 0.0, 1.4, 0.4), 1.4, 1.4)
	# the mirror wall: a wall-run panel on the right, over the void
	var wc: Vector3 = w2["c"]
	var f: float = wc.z - 0.7
	kit.wallrun(_w(Vector3(wc.x + 2.3, wc.y + 1.2, f - 9.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _post(Vector3(wc.x - 0.6, wc.y, f - 22.5), 1.8, 2.4)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(wc.x - 0.6)))
	# the pink pair must hold from landing on the first to leaving the second (+1.5 s slack)
	_wait(func() -> bool: return _phases_ok([[t1, 1.0, 2.8], [t2, 1.75, 3.6]]))
	_hop(cp0, a1)
	_hop(a1, a2)
	_hop(a2, sp, Vector3(0, 0, 1.0))
	var sp_c: Vector3 = sp["c"]
	r_walk(_w(Vector3(sp_c.x, sp_c.y, sp_c.z - 0.6)))
	_wait(func() -> bool: return _phases_ok([[t3, 0.8, 2.6], [t4, 1.55, 3.4]]), _w(Vector3(sp_c.x, sp_c.y, sp_c.z - 0.6)))
	_hop(sp, a3)
	_hop(a3, a4)
	_hop(a4, w2)
	r_wallrun(_w(Vector3(wc.x + 0.3, wc.y, f + 0.35)), _w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 3.6)),
		_w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 14.5)), _w(Vector3(wc.x - 0.6, wc.y, f - 22.2)))
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the mirror behind the wall-run panel, doors drifting beside the pink and cyan tiles
	deco.mirror(_w(Vector3(wc.x + 3.0, wc.y + 1.2, f - 9.5)), VoidDecor.turn(deg_to_rad(_yaw) + PI * 0.5), 16.6, 7.4)
	deco.door(_w(Vector3(-4.5, 0.0, (c1.z + c2.z) * 0.5)), VoidDecor.turn(deg_to_rad(_yaw) + 0.3), 1.4, 2.6, PINK, 0.5)
	deco.door(_w(Vector3(4.6, 0.6, (c3.z + c4.z) * 0.5)), VoidDecor.turn(deg_to_rad(_yaw) - 0.3), 1.4, 2.6, CYAN, 0.5)
	VoidFx.halo(self, _w(Vector3(-4.5, 1.4, (c1.z + c2.z) * 0.5)), 1.2, 16, PINK)
	VoidFx.halo(self, _w(Vector3(4.6, 2.0, (c3.z + c4.z) * 0.5)), 1.2, 16, CYAN)
	return cp["c"]


# ---- stage 3: Mirror Beam - two posts, the beam under the mirror lasers, mantle the wardrobe -----

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.90, 0.0, 1.2))
	var p2: Dictionary = _post(_ahead(p1, 0.88, 0.6, 1.2, 0.4))
	var beam: Dictionary = _blk(_ahead(p2, 0.86, 0.0, 14.0, -0.4), 1.2, 14.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 7.0
	var l1: LaserGate = kit.laser(_w(Vector3(bc.x, bc.y + 1.2, bc.z + 2.5)), Vector3(3.2, 2.4, 0.2), 5.0, 0.3, 0.0, _yaw)
	var l2: LaserGate = kit.laser(_w(Vector3(bc.x, bc.y + 1.2, bc.z - 2.5)), Vector3(3.2, 2.4, 0.2), 5.0, 0.3, fposmod(-0.12, 1.0), _yaw)
	_dress_laser(l1)
	_dress_laser(l2)
	var ward_top := Vector3(bc.x, bc.y + 3.3, front - 1.4 - 0.9)
	var ward: Dictionary = _ledge(ward_top, Vector3(2.8, 9.0, 1.8))
	var cp: Dictionary = _cp(_ahead(ward, 0.85, 0.0, 5.0, -bc.x))
	_wait(func() -> bool: return _dark(l1, 2.8, 3.3 + 1.5) and _dark(l2, 3.3, 3.9 + 1.5))
	_hop(cp0, p1)
	_hop(p1, p2)
	_hop(p2, beam, Vector3(0, 0, 6.2))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(ward_top + Vector3(0, 0, 0.3)))
	_hop(ward, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# mirrors along the beam either side, the wardrobe's doors
	for k: int in 3:
		var z: float = bc.z + 5.0 - 5.0 * float(k)
		deco.mirror(_w(Vector3(bc.x - 3.4, bc.y - 0.6, z)), VoidDecor.turn(deg_to_rad(_yaw) - PI * 0.5 + 0.3), 2.0, 3.6)
		deco.mirror(_w(Vector3(bc.x + 3.4, bc.y - 0.6, z - 2.5)), VoidDecor.turn(deg_to_rad(_yaw) + PI * 0.5 - 0.3), 2.0, 3.6)
	_door_dress(ward_top, 2.8, 9.0, 1.8)
	deco.clock(_w(Vector3(-12.0, 6.0, bc.z)), VoidDecor.turn(deg_to_rad(_yaw) + PI * 0.5, PI * 0.5, 0.0), 4.0, 0.0)
	return cp["c"]


# ---- stage 4: The Rift - two floating leaps through a low-gravity rift, the long jump out --------

func _rift(center: Vector3, size: Vector3, lift: float, max_rise: float = 9.0) -> VoidRift:
	var r := VoidRift.new()
	r.size = _sz(size)
	r.lift = lift
	r.max_rise = max_rise
	r.position = _w(center)
	add_child(r)
	return r


func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	# the rift: from just past the checkpoint's edge, over the first two posts
	_rift(Vector3(0, 2.0, -14.0), Vector3(7.0, 10.0, 22.0), 16.0)
	var r1: Dictionary = _post(Vector3(-0.6, 0.6, -13.5), 1.4, 1.4)
	var r2: Dictionary = _post(Vector3(0.6, 2.4, -24.5), 1.4, 1.4)
	var p: Dictionary = _post(_ahead(r2, 0.93, 0.0, 1.2, -0.4))
	var cp: Dictionary = _cp(_ahead(p, 0.86, 0.0, 5.0, -(p["c"] as Vector3).x))
	_fly(_w(Vector3(0, 0, -2.15)), _w(Vector3(-0.6, 0.6, -13.5)))
	_fly(_w(_edge(r1, r2["c"])), _w(Vector3(0.6, 2.4, -24.5)))
	_hop(r2, p)
	_hop(p, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the rift is a tear between two arches; broken stairs and sky shards drift round it
	deco.arch(_w(Vector3(0, -3.6, -2.0)), VoidDecor.turn(deg_to_rad(_yaw)), 9.0, 12.5, PINK)
	deco.arch(_w(Vector3(0, -3.6, -26.0)), VoidDecor.turn(deg_to_rad(_yaw)), 9.0, 12.5, CYAN)
	deco.stairs(_w(Vector3(7.0, -2.0, -8.0)), VoidDecor.turn(deg_to_rad(_yaw) + 0.3, 0.0, -0.9), 10, 2.0, 0.35, 0.5)
	deco.stairs(_w(Vector3(-7.5, 6.0, -18.0)), VoidDecor.turn(deg_to_rad(_yaw) - 0.5, PI, 0.2), 10, 2.0, 0.35, 0.5)
	for k: int in 4:
		deco.sky_shard(_w(Vector3(-9.0 + 6.0 * float(k), 11.0 + float(k % 2) * 3.0, -8.0 - 5.0 * float(k))), 2.5, VoidDecor.turn(float(k), 0.4, 0.6))
	return cp["c"]


# ---- stage 5: Tumbling Rooms - a run of little rooms that turn over on a wave, mantle out --------

func _tumble(top: Vector3, edge: float, period: float, phase: float, spin: float = 1.0) -> VoidTumble:
	var t := VoidTumble.new()
	t.edge = edge
	t.period = period
	t.phase = phase
	t.spin = spin
	t.rotation.y = deg_to_rad(_yaw)
	t.position = _w(top) - Vector3(0, edge * 0.5, 0)
	add_child(t)
	_floors.append({"top": _w(top), "size": _sz(Vector3(edge, 0, edge)), "drop": edge})
	return t


static func _rooms_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as VoidTumble).still_over(Game.course_time, float(e[1]), float(e[2])):
			return false
	return true


func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var period: float = 4.2
	var rooms: Array[VoidTumble] = []
	var areas: Array[Dictionary] = []
	var prev: Dictionary = cp0
	var dys: Array[float] = [0.0, 0.4, 0.4, 0.0]
	var pcts: Array[float] = [0.86, 0.87, 0.88, 0.86]
	var dxs: Array[float] = [0.0, 0.4, -0.4, 0.4]
	for i: int in 4:
		var c: Vector3 = _ahead(prev, pcts[i], dys[i], 1.4, dxs[i])
		# each room turns 0.75 s after the one before it: the wave follows a running player
		rooms.append(_tumble(c, 1.4, period, fposmod(-0.75 * float(i) / period, 1.0), 1.0 if i % 2 == 0 else -1.0))
		var a: Dictionary = _area(c, 0.7, 0.7)
		areas.append(a)
		prev = a
	var lc: Vector3 = (areas[3]["c"] as Vector3)
	var hang_top := Vector3(lc.x, lc.y + 3.3, lc.z - 0.7 - 1.5 - 1.0)
	var hang: Dictionary = _ledge(hang_top, Vector3(3.0, 9.0, 2.0))
	var cp: Dictionary = _cp(_ahead(hang, 0.85, 0.0, 5.0, -lc.x))
	_wait(func() -> bool: return _rooms_ok([[rooms[0], 0.9, 1.2 + 1.5], [rooms[1], 1.7, 2.0 + 1.5],
			[rooms[2], 2.5, 2.8 + 1.5], [rooms[3], 3.3, 3.7 + 1.5]]))
	prev = cp0
	for i: int in 4:
		_hop(prev, areas[i])
		prev = areas[i]
	r_mantle(_w(Vector3(lc.x, lc.y, lc.z - 0.35)), _w(hang_top + Vector3(0, 0, 0.3)))
	_hop(hang, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# a whole room hangs upside down over the tumbling ones; the mantle wall is a wardrobe
	deco.upside_room(_w(Vector3(0.0, 10.5, (areas[1]["c"] as Vector3).z)), deg_to_rad(_yaw), 7.0, 6.0, 3.2)
	_door_dress(hang_top, 3.0, 9.0, 2.0)
	deco.clock(_w(Vector3(-8.0, 2.0, (areas[2]["c"] as Vector3).z)), VoidDecor.turn(deg_to_rad(_yaw) + PI * 0.5, PI * 0.5, 0.3), 3.2, 0.4)
	deco.door(_w(Vector3(6.5, -0.5, (areas[0]["c"] as Vector3).z)), VoidDecor.turn(deg_to_rad(_yaw) - 0.9, 0.0, 0.3), 1.6, 2.9, CYAN, 0.9)
	return cp["c"]


# ---- stage 6: Drawer Hall (BRANCH) - the drawers' beam | the bookcase wall run and mantle ---------
# [shortcut: a 94% leap to the hidden post in the middle]

## A drawer that shoots out of a floating chest across the route: the piston, dressed. `top` is the
## ram's top centre when shut; it punches toward local +x when `dir` = 1 (-x when -1).
func _drawer(top: Vector3, dir: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.2)
	var p: Piston = kit.piston(_w(top), size, _yaw - 90.0 * dir, stroke, period, phase, 10.0)
	_dress_drawer(_w(top), size, stroke, _yaw - 90.0 * dir)
	return p


func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT (pink): the beam the drawers shoot across, then a post
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.5)
	var beam: Dictionary = _blk(_ahead(left, 0.86, 0.0, 12.0), 1.2, 12.0, "alt", 0.6)
	var bz: float = (beam["c"] as Vector3).z
	var d1: Piston = _drawer(Vector3(-3.5 - 0.6 - 0.6 - 0.15, 1.35, bz + 2.5), 1.0, 2.6, 5.0, 0.0)
	var d2: Piston = _drawer(Vector3(-3.5 - 0.6 - 0.6 - 0.15, 1.35, bz - 2.5), 1.0, 2.6, 5.0, fposmod(-0.07, 1.0))
	var pa: Dictionary = _post(_ahead(beam, 0.88, 0.0, 1.2))
	var merge: Dictionary = _blk(Vector3(0, 0, (pa["c"] as Vector3).z - 0.6 - 4.2 - 1.5), 11.0, 3.0)
	var mc: Vector3 = merge["c"]
	# RIGHT (cyan): the bookcase wall run, a post, mantle the case's top, drop to the merge
	kit.wallrun(_w(Vector3(5.7, 1.2, f0 - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, 0.0, f0 - 19.6), 2.0, 2.0)
	var case_top := Vector3(3.6, 3.3, f0 - 19.6 - 1.0 - 1.6 - 0.8)
	var case: Dictionary = _ledge(case_top, Vector3(2.6, 9.0, 1.6))
	# SHORTCUT: the hidden posts down the middle - a 94% leap off the fork, then three at 92%
	var hids: Array[Dictionary] = []
	var hp: Dictionary = _area(fc, 5.5, 1.5)
	for i: int in 4:
		hp = _post(_ahead(hp, 0.94 if i == 0 else 0.92, 0.6 if i == 0 else 0.0, 1.2), 1.2, 1.2, "accent")
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
		var lane_t: Array[float] = [1.3, 1.85]
		_wait(func() -> bool: return _ram_clear(d1, lane_t[0] - 0.3, lane_t[0] + 0.4 + 1.5) and _ram_clear(d2, lane_t[1] - 0.3, lane_t[1] + 0.4 + 1.5),
			_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_hop(left, beam, Vector3(0, 0, 4.5))
		r_walk(_w(Vector3(-3.5, 0, bz - 5.2)))
		_hop(beam, pa)
		_hop(pa, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.0, 0, f0 + 0.35)), _w(Vector3(5.2, 1.4, f0 - 3.4)), _w(Vector3(5.2, 1.4, f0 - 12.6)), _w(Vector3(3.6, 0, f0 - 19.4)))
		r_mantle(_w(Vector3(3.6, 0, f0 - 19.6 - 0.65)), _w(case_top + Vector3(0, 0, 0.2)))
		_hop(case, merge, Vector3(3.6, 0, 0.6))
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the bookcase behind the wall run, the case you mantle, signposts at the fork
	_bookcase(Vector3(6.75, 1.2, f0 - 9.0), 16.0, 12.0)
	_door_dress(case_top, 2.6, 9.0, 1.6)
	_sign(Vector3(-3.5, 0, fc.z + 1.2), PINK)
	_sign(Vector3(3.6, 0, fc.z + 1.2), CYAN)
	deco.clock(_w(Vector3(-11.0, 4.0, bz)), VoidDecor.turn(deg_to_rad(_yaw) - PI * 0.5, PI * 0.5, -0.2), 4.0, 0.3)
	pb.clear()
	return cp["c"]


## A towering white bookcase standing behind a wall-run panel (local centre of the panel's back,
## its length along z and height): shelves with rows of books above and below the panel.
func _bookcase(c: Vector3, length: float, height: float) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(_b, _w(c))
	add_child(n)
	var white: StandardMaterial3D = Look.flat(WHITE, 0.5)
	n.add_child(Look.box(Vector3(1.0, height, length), white, Vector3(0.4, 0, 0)))
	var cols: Array[Color] = [PINK, CYAN, Color(0.95, 0.85, 0.5), Color(0.55, 0.4, 0.9), Color(0.92, 0.9, 0.97)]
	var rng: RandomNumberGenerator = kit.rng
	for y: float in [-height * 0.5 + 0.6, -height * 0.5 + 1.8, height * 0.5 - 2.6, height * 0.5 - 1.4]:
		n.add_child(Look.box(Vector3(0.5, 0.08, length), white, Vector3(-0.3, y, 0)))
		var z: float = -length * 0.5 + 0.3
		while z < length * 0.5 - 0.3:
			var t: float = rng.randf_range(0.12, 0.3)
			var bh: float = rng.randf_range(0.6, 0.95)
			n.add_child(Look.box(Vector3(0.36, bh, t), Look.flat(cols[rng.randi() % cols.size()], 0.7), Vector3(-0.28, y + 0.04 + bh * 0.5, z + t * 0.5)))
			z += t + 0.02


## Fork signpost: two posts with glowing caps and a strip on the floor in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.12, 2.2, 0.12), Look.flat(WHITE, 0.4), _w(p + Vector3(sx * 1.1, 1.1, 0))))
		var lamp := Look.sphere(0.2, Look.flat(col, 0.3, 0.0, 3.0), _w(p + Vector3(sx * 1.1, 2.35, 0)))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.5)), _sz(Vector3(1.2, 0.05, 0.25)), col)


# ---- stage 7: Clockfall - the walk under the falling clocks, mantle under the last one ------------

## A handless clock that falls: the crusher, dressed.
func _clock_press(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var c: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	_dress_clock(c)
	return c


func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.2))
	var walk: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 16.0, 0.0), 1.4, 16.0, "alt", 0.6)
	var wc: Vector3 = walk["c"]
	var w0: float = wc.z + 8.0
	var period: float = 6.0
	# the bot's passing times (s after it sets off from the checkpoint): under press 1, press 2, the mantle
	var t1: float = 2.4
	var t2: float = 3.0
	var t3: float = 3.7
	var c1: Crusher = _clock_press(Vector3(wc.x, wc.y, w0 - 5.0), Vector3(2.2, 1.2, 2.0), 3.2, period, fposmod(0.92 - (t1 - 0.4) / period, 1.0))
	var c2: Crusher = _clock_press(Vector3(wc.x, wc.y, w0 - 10.5), Vector3(2.2, 1.2, 2.0), 3.2, period, fposmod(0.92 - (t2 - 0.4) / period, 1.0))
	var ledge_top := Vector3(wc.x, wc.y + 3.3, w0 - 16.0 - 1.2 - 1.1)
	var ld: Dictionary = _ledge(ledge_top, Vector3(3.6, 9.0, 2.2))
	var c3: Crusher = _clock_press(ledge_top, Vector3(2.4, 1.0, 1.6), 2.6, period, fposmod(0.92 - (t3 - 0.4) / period, 1.0))
	var p2: Dictionary = _post(_ahead(ld, 0.88, 0.0, 1.2, 0.4))
	var p3: Dictionary = _post(_ahead(p2, 0.88, 0.6, 1.2, -0.4))
	var cp: Dictionary = _cp(_ahead(p3, 0.86, 0.0, 5.0, -(p3["c"] as Vector3).x))
	_wait(func() -> bool: return _press_ok(c1, t1 - 0.3, t1 + 0.3 + 1.5) and _press_ok(c2, t2 - 0.3, t2 + 0.3 + 1.5) \
		and _press_ok(c3, t3 - 0.3, t3 + 1.2 + 1.5))
	_hop(cp0, p1)
	_hop(p1, walk, Vector3(0, 0, 7.0))
	r_walk(_w(Vector3(wc.x, wc.y, w0 - 16.0 + 0.9)))
	r_mantle(_w(Vector3(wc.x, wc.y, w0 - 16.0 + 0.35)), _w(ledge_top + Vector3(0, 0, 0.5)))
	_hop(ld, p2)
	_hop(p2, p3)
	_hop(p3, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# a giant clock melting over a floating block beside the walk, more clocks in the dark
	add_child(Look.box(_sz(Vector3(4.0, 3.0, 4.0)), Look.flat(WHITE, 0.5), _w(Vector3(-7.5, -1.5, wc.z))))
	deco.clock(_w(Vector3(-7.5, 0.1, wc.z + 0.6)), VoidDecor.turn(deg_to_rad(_yaw) + 0.4, 0.0, 0.0), 2.4, 0.6)
	deco.clock(_w(Vector3(9.0, 7.0, wc.z - 4.0)), VoidDecor.turn(deg_to_rad(_yaw) - PI * 0.5, PI * 0.5, 0.25), 5.0, 0.0)
	deco.clock(_w(Vector3(-10.0, 10.0, w0 - 18.0)), VoidDecor.turn(deg_to_rad(_yaw) + 0.8, 1.1, 0.0), 3.5, 0.2)
	_door_dress(ledge_top, 3.6, 9.0, 2.2)
	return cp["c"]


# ---- stage 8: Door Maze (BRANCH) - the door that sends you up | the up-draft rift -----------------
# [shortcut: the small door on the hanging post]

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT (pink): a door on the fork sends you up onto the lintel beam high ahead
	var hi: Dictionary = _blk(Vector3(-3.5, 4.5, f0 - 9.0), 1.2, 5.0, "alt", 0.6)
	var door: WarpPortal = kit.portal(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, _w(Vector3(-3.5, 4.5, f0 - 7.2)), _yaw, 7.0)
	_dress_portal(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, PINK)
	_dress_portal(_w(Vector3(-3.5, 4.5, f0 - 7.2)), _yaw, CYAN)
	var la: Dictionary = _post(_ahead(hi, 0.90, -1.5, 1.2, 0.3))
	var la2: Dictionary = _post(_ahead(la, 0.90, -1.5, 1.2, -0.3))
	# RIGHT (cyan): an up-draft rift lifts you to the arch, then two posts
	_rift(Vector3(4.0, 2.0, f0 - 4.5), Vector3(3.4, 12.0, 3.4), 58.0, 8.0)
	var arch: Dictionary = _blk(Vector3(4.0, 5.0, f0 - 9.6), 1.4, 3.6, "alt", 0.6)
	var rb1: Dictionary = _post(_ahead(arch, 0.90, -1.5, 1.2, -0.3))
	var rb2: Dictionary = _post(_ahead(rb1, 0.90, -1.5, 1.2, 0.3))
	var mc: Vector3 = _ahead(la2, 0.86, -1.5, 3.0)
	var merge: Dictionary = _blk(Vector3(0, 0, mc.z), 11.0, 3.0)
	var mz: float = mc.z
	# SHORTCUT: a small post hangs off the fork's front; the door on it opens onto the merge
	var sp: Dictionary = _post(_ahead(_area(fc, 5.5, 1.5), 0.93, 0.0, 1.2), 1.2, 1.2, "accent")
	var spc: Vector3 = sp["c"]
	var sdoor: WarpPortal = kit.portal(_w(spc + Vector3(0, 0, -0.3)), _yaw, _w(Vector3(0.5, 0, mz + 0.8)), _yaw, 6.0)
	_dress_portal(_w(spc + Vector3(0, 0, -0.3)), _yaw, PINK)
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		_hop(_area(fc, 5.5, 1.5), sp, Vector3(0, 0, 0.35))
		r_portal(_w(spc + Vector3(0, 0, -0.6)), sdoor.exit_point())
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		r_portal(_w(Vector3(-3.5, 0, fc.z - 0.9)), door.exit_point())
		r_walk(_w(Vector3(-3.5, 4.5, f0 - 10.0)))
		_hop(hi, la)
		_hop(la, la2)
		_hop(la2, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(4.0, 0, fc.z + 0.6)))
		var top_y: float = _w(Vector3(0, 7.0, 0)).y
		route.append({"kind": "desert_fly", "jump_from": _w(Vector3(4.0, 0, f0 + 0.35)), "to": _w(Vector3(4.0, 0, f0 - 4.5)),
			"until": func() -> bool: return player.global_position.y > top_y})
		route.append({"kind": "desert_fly", "to": _w(Vector3(4.0, 5.0, f0 - 9.2))})
		r_walk(_w(Vector3(4.0, 5.0, f0 - 10.4)))
		_hop(arch, rb1)
		_hop(rb1, rb2)
		_hop(rb2, merge, Vector3(4.0, 0, 0.6))
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# a hall of doors: dark doors standing round the fork, the arch over the up-draft's landing
	_sign(Vector3(-3.5, 0, fc.z + 1.2), PINK)
	_sign(Vector3(4.0, 0, fc.z + 1.2), CYAN)
	deco.arch(_w(Vector3(4.0, 5.0 - 0.6, f0 - 9.6)), VoidDecor.turn(deg_to_rad(_yaw)), 3.4, 6.0, CYAN)
	for k: int in 5:
		var side: float = -1.0 if k % 2 == 0 else 1.0
		deco.door(_w(Vector3(side * (8.5 + float(k)), -1.0 + float(k) * 1.2, f0 - 3.0 - 5.0 * float(k))),
			VoidDecor.turn(deg_to_rad(_yaw) + side * 0.6, 0.0, side * 0.15), 1.6, 2.9, PINK if k % 2 == 0 else CYAN, 0.2 + 0.25 * float(k))
	return cp["c"]


# ---- stage 9: The Chess Turntable - ride the turning board, leap off to the pawn posts -----------

func _stage_9() -> Vector3:
	var hub := Vector3(-3.0, 0, -11.0)
	var arms: Array[Dictionary] = [
		{"pos": Vector3(4.6, 0, 0), "size": Vector3(4.6, 0.5, 1.6)}, {"pos": Vector3(-4.6, 0, 0), "size": Vector3(4.6, 0.5, 1.6)},
		{"pos": Vector3(0, 0, 4.6), "size": Vector3(1.6, 0.5, 4.6)}, {"pos": Vector3(0, 0, -4.6), "size": Vector3(1.6, 0.5, 4.6)},
	]
	var board: RotatingPlatform = kit.spinner(_w(hub), 7.0, arms, 2.4, 0.0, 0.5)
	var m: Dictionary = _post(Vector3(-3.0, 0.5, -22.5), 1.6, 1.6)
	var p2: Dictionary = _post(_ahead(m, 0.86, 0.0, 1.2, 1.0))
	var cp: Dictionary = _cp(_ahead(p2, 0.86, 0.0, 5.0, 2.0))
	var tips: Array = [Vector3(6.2, 0.25, 0), Vector3(-6.2, 0.25, 0), Vector3(0, 0.25, 6.2), Vector3(0, 0.25, -6.2)]
	r_walk(_w(Vector3(-1.8, 0, -2.2)))
	route.append({"kind": "x_jump", "from": _w(Vector3(-1.8, 0, -2.2)), "to_node": board, "to_locals": tips, "reach": 3.2, "lead": 0.55})
	var hw: Vector3 = _w(hub)
	var ex: Vector3 = _w(m["c"]) - hw
	ex = Vector3(ex.x, 0, ex.z).normalized()
	var sgn: float = signf(board.period)
	route.append({"kind": "h_jump", "to": _w(m["c"]), "test": func() -> bool:
		var rel: Vector3 = player.global_position - hw
		rel = Vector3(rel.x, 0, rel.z).normalized()
		var a: float = rad_to_deg(atan2(rel.cross(ex).y, rel.dot(ex))) * sgn
		return a >= 8.0 and a <= 22.0})
	_hop(m, p2)
	_hop(p2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the board's squares on its arms and hub, giant pieces on floating squares round it
	_board_dress(board, arms)
	var hwc: Vector3 = hub
	var spots: Array[Vector3] = [Vector3(-12.5, -1.0, 2.0), Vector3(9.5, -0.5, -5.0), Vector3(-13.0, 1.0, -9.0), Vector3(6.5, -2.0, -17.0)]
	for k: int in spots.size():
		var at: Vector3 = _w(hwc + spots[k])
		add_child(Look.box(Vector3(3.2, 0.4, 3.2), Look.flat(WHITE if k % 2 == 0 else Color(0.2, 0.15, 0.3), 0.4), at - Vector3(0, 0.2, 0)))
		deco.chess(at, 2.2 + 0.4 * float(k % 2), k % 2 == 1, k == 2)
	return cp["c"]


## The turntable is a chessboard: alternating dark squares along each arm and a crown on the hub.
func _board_dress(board: RotatingPlatform, arms: Array[Dictionary]) -> void:
	var dark: StandardMaterial3D = Look.flat(Color(0.22, 0.16, 0.34), 0.4)
	for a: Dictionary in arms:
		var pos: Vector3 = a["pos"]
		var sz: Vector3 = a["size"]
		var along_x: bool = sz.x > sz.z
		var n: int = int(maxf(sz.x, sz.z) / 1.15)
		for i: int in n:
			if i % 2 == 0:
				continue
			var k: float = -0.5 + (float(i) + 0.5) / float(n)
			var off := Vector3(k * sz.x, 0, 0) if along_x else Vector3(0, 0, k * sz.z)
			var sq := Look.box(Vector3(maxf(sz.x, sz.z) / float(n), 0.02, minf(sz.x, sz.z) - 0.3) if along_x else Vector3(minf(sz.x, sz.z) - 0.3, 0.02, maxf(sz.x, sz.z) / float(n)), dark, pos + off + Vector3(0, sz.y * 0.5 + 0.011, 0))
			sq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			board.add_child(sq)
	var tm := TorusMesh.new()
	tm.inner_radius = 2.2
	tm.outer_radius = 2.35
	tm.rings = 48
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, Look.flat(PINK, 0.3, 0.0, 2.4), Vector3(0, 0.27, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(ring)


# ---- stage 10: The Inverted Room - an up-draft into the hanging room, its chimney, mantle out -----

func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)


func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var step: Dictionary = _post(_ahead(cp0, 0.87, 0.0, 1.2))
	_rift(Vector3(0, 1.0, -11.8), Vector3(3.4, 18.0, 3.4), 70.0, 8.0)
	var landing: Dictionary = _blk(Vector3(0, 6.0, -15.2), 2.4, 2.4, "main", 0.8)
	_chimney_panel(2.3, 7.2, -19.5, -26.0)
	_chimney_panel(-2.3, 12.0, -24.5, -32.5)
	_chimney_panel(2.3, 15.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 17.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(_ahead(top, 0.85, 0.0, 5.0, 0.75))
	var top_y: float = _w(Vector3(0, 7.6, 0)).y
	_hop(cp0, step)
	route.append({"kind": "desert_fly", "jump_from": _w(_edge(step, Vector3(0, 0, -11.8))), "to": _w(Vector3(0, 0, -11.8)),
		"until": func() -> bool: return player.global_position.y > top_y})
	route.append({"kind": "desert_fly", "to": _w(Vector3(0, 6.0, -14.8))})
	r_walk(_w(Vector3(0, 6.0, -14.4)))
	r_wallrun(_w(Vector3(0.5, 6.0, -15.95)), _w(Vector3(1.7, 7.4, -20.6)), _w(Vector3(1.7, 7.4, -23.5)), _w(Vector3(-1.7, 11.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 11.5, -27.4)), _w(Vector3(-1.7, 11.5, -30.4)), _w(Vector3(1.7, 14.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 14.5, -34.0)), _w(Vector3(1.7, 14.5, -35.4)), _w(Vector3(-0.75, 17.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the room: papered walls behind the chimney panels (a window, a door on its side), its
	# floor hanging overhead with the furniture dangling, the up-draft's arch below
	var paper: StandardMaterial3D = Look.flat(Color(0.86, 0.8, 0.92), 0.7)
	add_child(Look.box(_sz(Vector3(0.6, 20.0, 22.0)), paper, _w(Vector3(3.1, 8.0, -29.0))))
	add_child(Look.box(_sz(Vector3(0.6, 18.0, 14.0)), paper, _w(Vector3(-3.1, 10.0, -29.0))))
	for w: Vector3 in [Vector3(2.78, 12.0, -28.2), Vector3(-2.78, 8.0, -34.0)]:
		var win := Look.box(_sz(Vector3(0.08, 2.2, 1.8)), Look.flat(Color(1.0, 0.82, 0.6), 0.3, 0.0, 1.8), _w(w))
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(win)
	deco.door(_w(Vector3(3.45, 0.5, -22.0)), VoidDecor.turn(deg_to_rad(_yaw) + PI * 0.5, 0.0, PI), 1.6, 2.9, CYAN, 0.4)
	deco.upside_room(_w(Vector3(-0.75, 29.0, -30.0)), deg_to_rad(_yaw), 7.0, 22.0, 3.6)
	deco.arch(_w(Vector3(0, -14.0, -11.8)), VoidDecor.turn(deg_to_rad(_yaw)), 5.0, 6.0, PINK)
	landing.clear()
	return cp["c"]


# ---- stage 11: Mirror Gallery (BRANCH) - pink tiles and a mirror beam | two mirror wall runs ------
# [shortcut: a max-height mantle up the broken column, then its narrow cornice]

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	var period: float = 6.4
	# LEFT (pink): two pink tiles, a beam through a mirror beam, a post
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.5)
	var c1: Vector3 = _ahead(left, 0.88, 0.0, 1.3)
	var t1: VoidPhase = _phase_tile(c1, 0, period, 0.0)
	var a1: Dictionary = _area(c1, 0.65, 0.65)
	var c2: Vector3 = _ahead(a1, 0.88, 0.6, 1.3, 0.3)
	var t2: VoidPhase = _phase_tile(c2, 0, period, 0.0)
	var a2: Dictionary = _area(c2, 0.65, 0.65)
	var beam: Dictionary = _blk(_ahead(a2, 0.86, 0.0, 8.0, -0.3), 1.2, 8.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	# the beam fires on the tiles' beat, while you would be on the tiles' far side waiting for pink
	var gate: LaserGate = kit.laser(_w(Vector3(bc.x, bc.y + 1.2, bc.z)), Vector3(3.2, 2.4, 0.2), period, 0.3, fposmod(-4.7 / period, 1.0), _yaw)
	_dress_laser(gate)
	var pa: Dictionary = _post(_ahead(beam, 0.88, -0.6, 1.2))
	var mc: Vector3 = _ahead(pa, 0.86, 0.0, 3.0)
	var merge: Dictionary = _blk(Vector3(0, mc.y, mc.z), 11.0, 3.0)
	var mz: float = mc.z
	# RIGHT (cyan): run the right mirror, kick across to the left one, run it, kick to a post
	kit.wallrun(_w(Vector3(6.1, 1.2, f0 - 7.0)), Vector3(12.0, 6.5, 0.6), _yaw + 90.0)
	kit.wallrun(_w(Vector3(1.5, 3.6, f0 - 17.5)), Vector3(9.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, mc.y, f0 - 27.6), 1.6, 1.6)
	var pb2: Dictionary = _post(_ahead(pb, 0.88, 0.0, 1.2))
	# SHORTCUT: the broken column (a 4.1 m mantle) and its narrow cornice to the merge
	var col: Dictionary = _ledge(Vector3(0, 4.1, f0 - 0.9), Vector3(1.4, 12.0, 1.8), "accent")
	var cornice: Dictionary = _blk(Vector3(0, 4.1, f0 - 1.8 - 6.0 - 0.4), 1.0, 12.0, "accent", 0.5)
	var n2: Vector3 = _ahead(cornice, 0.88, 0.0, 0.0)
	var l2: float = n2.z - (mz + 1.5 + 4.5)
	var cornice2: Dictionary = _blk(Vector3(0, 4.1, n2.z - l2 * 0.5), 1.0, l2, "accent", 0.5)
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z + 0.9)))
		r_mantle(_w(Vector3(0, 0, fc.z + 0.65)), _w(Vector3(0, 4.1, f0 - 1.0)))
		_hop(col, cornice, Vector3(0, 0, 5.0))
		r_walk(_w(Vector3(0, 4.1, f0 - 13.6)))
		_hop(cornice, cornice2, Vector3(0, 0, l2 * 0.5 - 0.8))
		r_walk(_w(Vector3(0, 4.1, n2.z - l2 + 0.6)))
		_hop(cornice2, merge, Vector3(0, 0, 0.4))
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_wait(func() -> bool: return _phases_ok([[t1, 0.85, 2.6], [t2, 1.6, 3.4]]) and _dark(gate, 2.6, 3.3 + 1.5),
			_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_hop(left, a1)
		_hop(a1, a2)
		_hop(a2, beam, Vector3(0, 0, 3.0))
		r_walk(_w(Vector3(bc.x, bc.y, bc.z - 3.2)))
		_hop(beam, pa)
		_hop(pa, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.2, 0, f0 + 0.35)), _w(Vector3(5.6, 1.4, f0 - 3.2)), _w(Vector3(5.6, 1.4, f0 - 10.6)), _w(Vector3(2.0, 4.4, f0 - 14.4)))
		r_wallrun(Vector3.ZERO, _w(Vector3(2.0, 4.4, f0 - 14.4)), _w(Vector3(2.0, 4.4, f0 - 19.6)), _w(Vector3(3.6, mc.y, f0 - 27.4)), true, true)
		_hop(pb, pb2)
		_hop(pb2, merge, Vector3(3.6, 0, 0.6))
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the gallery: tall mirrors behind both mirror panels, mirrors along the pink side, signposts
	deco.mirror(_w(Vector3(6.85, 1.2, f0 - 7.0)), VoidDecor.turn(deg_to_rad(_yaw) + PI * 0.5), 12.6, 7.2)
	for k: int in 3:
		deco.mirror(_w(Vector3(-7.6, -0.5, f0 - 6.0 - 7.0 * float(k))), VoidDecor.turn(deg_to_rad(_yaw) - PI * 0.5 + 0.25), 2.2, 3.8)
	_sign(Vector3(-3.5, 0, fc.z + 1.2), PINK)
	_sign(Vector3(3.6, 0, fc.z + 1.2), CYAN)
	return cp["c"]


# ---- stage 12: Escher Stairs - crumbling steps up to the drawer landing, more steps -------------

## A crumbling stair step (square), gone a moment after you land on it.
func _crumble(top: Vector3, edge: float = 1.4, delay: float = 0.6) -> Dictionary:
	var cp := CollapsingPlatform.new()
	cp.size = Vector3(edge, 0.4, edge)
	cp.delay = delay
	cp.respawn = 3.0
	cp.is_round = false
	cp.rotation.y = deg_to_rad(_yaw)
	cp.position = _w(top) - Vector3(0, 0.2, 0)
	add_child(cp)
	_floors.append({"top": _w(top), "size": Vector3(edge, 0, edge), "drop": 0.4})
	return {"c": top, "hx": edge * 0.5, "hz": edge * 0.5}


func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var prev: Dictionary = cp0
	var steps: Array[Dictionary] = []
	var dxs: Array[float] = [0.0, 0.4, -0.4, 0.4]
	for i: int in 4:
		prev = _crumble(_ahead(prev, 0.87, 0.6, 1.4, dxs[i]))
		steps.append(prev)
	var land: Dictionary = _blk(_ahead(prev, 0.86, 0.6, 2.6, -0.4), 2.6, 2.6, "alt", 0.6)
	var lc: Vector3 = land["c"]
	# a drawer shoots across the landing from the left
	var dr: Piston = _drawer(Vector3(lc.x - 1.3 - 0.6 - 0.15, lc.y + 1.35, lc.z), 1.0, 3.0, 6.0, 0.0)
	prev = land
	for i: int in 2:
		prev = _crumble(_ahead(prev, 0.87, 0.6, 1.4, 0.4 if i == 0 else -0.4))
		steps.append(prev)
	var cp: Dictionary = _cp(_ahead(prev, 0.86, 0.0, 5.0, -(prev["c"] as Vector3).x))
	var t_land: float = 4.35
	_wait(func() -> bool: return _ram_clear(dr, t_land - 0.3, t_land + 0.4 + 1.5))
	prev = cp0
	for i: int in 4:
		_hop(prev, steps[i])
		prev = steps[i]
	_hop(prev, land)
	prev = land
	for i: int in range(4, 6):
		_hop(prev, steps[i])
		prev = steps[i]
	_hop(prev, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# Escher's staircase: flights at every angle round the crumbling steps, one upside down overhead
	var yr: float = deg_to_rad(_yaw)
	deco.stairs(_w(Vector3(-6.0, -1.0, -6.0)), VoidDecor.turn(yr + PI * 0.5, 0.0, 0.0), 10, 2.0, 0.4, 0.55)
	deco.stairs(_w(Vector3(8.0, 2.5, -14.0)), VoidDecor.turn(yr - PI * 0.5, 0.0, PI * 0.5), 10, 2.0, 0.4, 0.55)
	deco.stairs(_w(Vector3(0.0, 14.0, -20.0)), VoidDecor.turn(yr, PI, 0.0), 12, 2.4, 0.4, 0.55)
	deco.stairs(_w(Vector3(-7.0, 5.0, -30.0)), VoidDecor.turn(yr + 0.4, 0.0, -PI * 0.5), 9, 2.0, 0.4, 0.55)
	return cp["c"]


# ---- stage 13: Rooms and Rift - three faster tumbling rooms, a low-gravity leap up ---------------
# [shortcut: the wall run along the rooms]

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var period: float = 3.6
	var rooms: Array[VoidTumble] = []
	var areas: Array[Dictionary] = []
	var prev: Dictionary = cp0
	var dxs: Array[float] = [0.0, 0.4, -0.4]
	for i: int in 3:
		var c: Vector3 = _ahead(prev, 0.87, 0.0 if i == 0 else 0.4, 1.4, dxs[i])
		rooms.append(_tumble(c, 1.4, period, fposmod(-0.75 * float(i) / period, 1.0), -1.0 if i % 2 == 0 else 1.0))
		var a: Dictionary = _area(c, 0.7, 0.7)
		areas.append(a)
		prev = a
	var p1: Dictionary = _post(_ahead(prev, 0.87, 0.0, 1.4, 0.0), 1.4, 1.4)
	var p1c: Vector3 = p1["c"]
	# the rift: a low-gravity leap from the post up onto the high post
	_rift(p1c + Vector3(0, 3.0, -7.0), Vector3(5.0, 9.0, 11.0), 16.0)
	var hi: Dictionary = _post(p1c + Vector3(0.0, 3.0, -11.0), 1.4, 1.4)
	var cp: Dictionary = _cp(_ahead(hi, 0.86, 0.0, 5.0, -p1c.x))
	# SHORTCUT: a wall-run panel along the rooms' left, kick off onto the post past them
	var wz0: float = -4.0
	var wz1: float = p1c.z + 4.0
	kit.wallrun(_w(Vector3(-2.6, 1.2, (wz0 + wz1) * 0.5)), Vector3(wz0 - wz1, 6.5, 0.6), _yaw + 90.0)
	if route_variant == 2:
		r_walk(_w(Vector3(-0.6, 0, -1.4)))
		r_wallrun(_w(Vector3(-0.6, 0, -2.15)), _w(Vector3(-2.1, 1.4, -6.0)), _w(Vector3(-2.1, 1.4, p1c.z + 6.6)), _w(p1c + Vector3(0, 0, 0.2)))
	else:
		_wait(func() -> bool: return _rooms_ok([[rooms[0], 0.9, 1.2 + 1.5], [rooms[1], 1.7, 2.0 + 1.5], [rooms[2], 2.5, 2.8 + 1.5]]))
		prev = cp0
		for i: int in 3:
			_hop(prev, areas[i])
			prev = areas[i]
		_hop(prev, p1)
	_fly(_w(_edge(p1, hi["c"])), _w(hi["c"] as Vector3))
	_hop(hi, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	deco.arch(_w(p1c + Vector3(0, -4.5, -1.6)), VoidDecor.turn(deg_to_rad(_yaw)), 8.0, 15.0, CYAN)
	deco.upside_room(_w(Vector3(4.0, 10.5, (areas[1]["c"] as Vector3).z)), deg_to_rad(_yaw) + PI * 0.5, 6.0, 5.0, 3.0)
	deco.door(_w(Vector3(6.0, 0.5, (areas[0]["c"] as Vector3).z)), VoidDecor.turn(deg_to_rad(_yaw) - 0.7, 0.0, 0.2), 1.6, 2.9, PINK, 0.7)
	return cp["c"]


# ---- stage 14: The Unravelling - pink tiles, the falling clock, the longest jump, mantle out ------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var period: float = 6.4
	var c1: Vector3 = _ahead(cp0, 0.88, 0.0, 1.3)
	var t1: VoidPhase = _phase_tile(c1, 0, period, 0.0)
	var a1: Dictionary = _area(c1, 0.65, 0.65)
	var c2: Vector3 = _ahead(a1, 0.88, 0.6, 1.3, -0.4)
	var t2: VoidPhase = _phase_tile(c2, 0, period, 0.0)
	var a2: Dictionary = _area(c2, 0.65, 0.65)
	var walk: Dictionary = _blk(_ahead(a2, 0.86, 0.0, 6.0, 0.4), 1.4, 6.0, "alt", 0.6)
	var wc: Vector3 = walk["c"]
	var t_press: float = 2.6
	var press: Crusher = _clock_press(wc, Vector3(2.2, 1.2, 2.0), 3.2, period, fposmod(0.92 - 1.5 / period, 1.0))
	# the longest jump of the level, onto a single post
	var far: Dictionary = _post(_ahead(walk, 0.92, 0.0, 1.2))
	var fz: Vector3 = far["c"]
	var top := Vector3(fz.x, fz.y + 3.3, fz.z - 0.6 - 1.4 - 1.0)
	var ld: Dictionary = _ledge(top, Vector3(2.8, 9.0, 2.0))
	var cp: Dictionary = _cp(_ahead(ld, 0.85, 0.0, 5.0, -fz.x))
	_wait(func() -> bool: return _phases_ok([[t1, 1.05, 2.8], [t2, 1.8, 3.6]]) and _press_ok(press, t_press, t_press + 0.7 + 1.5))
	_hop(cp0, a1)
	_hop(a1, a2)
	_hop(a2, walk, Vector3(0, 0, 1.6))
	r_walk(_w(Vector3(wc.x, wc.y, wc.z - 2.2)))
	_hop(walk, far)
	r_mantle(_w(Vector3(fz.x, fz.y, fz.z - 0.3)), _w(top + Vector3(0, 0, 0.3)))
	_hop(ld, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# time itself unravelling: clocks melting off blocks and drifting in pieces round the long jump
	var yr: float = deg_to_rad(_yaw)
	add_child(Look.box(_sz(Vector3(3.0, 2.0, 3.0)), Look.flat(WHITE, 0.5), _w(Vector3(-6.5, -1.0, wc.z))))
	deco.clock(_w(Vector3(-6.5, 0.1, wc.z + 0.5)), VoidDecor.turn(yr - 0.5), 2.0, 0.7)
	deco.clock(_w(Vector3(7.5, 5.0, fz.z + 3.0)), VoidDecor.turn(yr - PI * 0.5, PI * 0.5, 0.0), 4.5, 0.0)
	deco.clock(_w(Vector3(-9.0, 9.0, fz.z - 6.0)), VoidDecor.turn(yr + 0.6, 1.2, 0.3), 3.0, 0.3)
	_door_dress(top, 2.8, 9.0, 2.0)
	return cp["c"]


# ---- stage 15: THE COLLAPSE - outrun the dream falling apart, up the fragments to the door -------

var _collapse: VoidCollapse
var _finish_light: OmniLight3D


func _stage_15() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var frags: Array[Dictionary] = []
	var areas: Array[Dictionary] = []
	var prev: Dictionary = cp0
	var dys: Array[float] = [0.0, 0.6, 0.6, 0.0, 0.6, 0.6, 0.0, 0.6, 0.6, 0.6, 0.0, 0.6]
	var pcts: Array[float] = [0.86, 0.87, 0.88, 0.89, 0.87, 0.88, 0.90, 0.87, 0.88, 0.87, 0.89, 0.86]
	var sizes: Array[float] = [1.5, 1.4, 1.3, 1.3, 1.4, 1.3, 1.2, 1.4, 1.3, 1.3, 1.2, 1.4]
	for i: int in dys.size():
		var dx: float = 0.0 if i == 0 else (0.4 if i % 2 == 1 else -0.4)
		var c: Vector3 = _ahead(prev, pcts[i], dys[i], sizes[i], dx)
		frags.append({"top": _w(c), "size": Vector3(sizes[i], 0.5, sizes[i]), "yaw": _yaw})
		var a: Dictionary = _area(c, sizes[i] * 0.5, sizes[i] * 0.5)
		areas.append(a)
		_floors.append({"top": _w(c), "size": Vector3(sizes[i], 0, sizes[i]), "drop": 0.5, "frag": true})
		prev = a
	_collapse = VoidCollapse.new()
	_collapse.frags = frags
	_collapse.speed = 5.5
	_collapse.delay = 2.4
	_collapse.tell = 0.95
	_collapse.trigger_pos = frags[0]["top"] + Vector3(0, 1.2, 0)
	_collapse.trigger_size = Vector3(sizes[0] + 0.6, 2.4, sizes[0] + 0.6)
	add_child(_collapse)
	# the door in the sky: a last slab and the finish gate inside a towering door frame
	var lc: Vector3 = (areas[areas.size() - 1]["c"] as Vector3)
	var fin: Dictionary = _blk(_ahead(areas[areas.size() - 1], 0.86, 0.6, 4.0, -lc.x), 4.0, 4.0, "main", 1.0)
	var fc: Vector3 = fin["c"]
	kit.finish(_w(fc + Vector3(0, 0, -0.4)), _yaw)
	_finish_pos = _w(fc + Vector3(0, 0, -0.4))
	prev = cp0
	for a2: Dictionary in areas:
		_hop(prev, a2)
		prev = a2
	_hop(prev, fin, Vector3(0, 0, 0.6))
	r_walk(_w(fc + Vector3(0, 0, -0.6)))
	# the door in the sky: a towering frame round the finish gate, swung wide open onto the light
	var yr: float = deg_to_rad(_yaw)
	deco.door(_w(fc + Vector3(0, 0, -0.4)), VoidDecor.turn(yr), 6.6, 6.6, PINK, -1.35)
	VoidFx.halo(self, _w(fc + Vector3(0, 3.3, -0.4)), 4.2, 40, CYAN)
	VoidFx.motes(self, _w(fc + Vector3(0, 3.0, -2.0)), _sz(Vector3(3.0, 3.0, 2.0)), 40)
	_finish_light = OmniLight3D.new()
	_finish_light.light_color = PINK
	_finish_light.light_energy = 2.0
	_finish_light.omni_range = 14.0
	_finish_light.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(_finish_light)
	# the stair of fragments climbs past broken arches and doors drifting apart
	for k: int in 4:
		var side: float = -1.0 if k % 2 == 0 else 1.0
		var at: Vector3 = (areas[k * 3]["c"] as Vector3)
		deco.door(_w(at + Vector3(side * 6.5, -1.0, 0.0)), VoidDecor.turn(yr + side * 0.8, 0.0, side * 0.25), 1.6, 2.9, CYAN if k % 2 == 0 else PINK, 0.4 + 0.2 * float(k))
		deco.sky_shard(_w(at + Vector3(-side * 8.0, 4.0, -2.0)), 2.5, VoidDecor.turn(float(k), 0.5, 0.7))


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
	_env.sky = VoidSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.52, 0.82)
	_env.ambient_light_energy = 0.62
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.12, 0.05, 0.2)
	_env.fog_density = 0.0035
	_env.fog_aerial_perspective = 0.4
	_env.fog_sky_affect = 0.15
	_env.fog_sun_scatter = 0.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.65
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 1.15
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.08
	# a cool white key light from high in the shattered sky, and a rose fill from below
	_sun.light_color = Color(0.92, 0.88, 1.0)
	_sun.light_energy = 1.05
	_sun.rotation_degrees = Vector3(-58, 30, 0)
	_fill.light_color = Color(1.0, 0.5, 0.78)
	_fill.light_energy = 0.32
	_fill.rotation_degrees = Vector3(30, -150, 0)


# ---- machine dressing ---------------------------------------------------------------------------

## The drawer's chest: a white cabinet round the ram's rod (the ram slides out of its face) with
## drawer fronts above and below the opening. `top` / `yaw` as given to kit.piston (world).
func _dress_drawer(top: Vector3, size: Vector3, stroke: float, yaw_deg: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var depth: float = stroke + 0.45
	var c: Vector3 = top - Vector3(0, size.y * 0.5, 0) + b * Vector3(0, 0, size.z * 0.5 + depth * 0.5 + 0.02)
	var n := Node3D.new()
	n.transform = Transform3D(b, c)
	add_child(n)
	var white: StandardMaterial3D = Look.flat(WHITE, 0.5)
	var bone: StandardMaterial3D = Look.flat(Color(0.8, 0.77, 0.87), 0.6)
	var h: float = size.y + 1.6
	var w: float = size.x + 0.8
	# the carcass: sides, top and bottom round the ram's opening, a back
	n.add_child(Look.box(Vector3(0.4, h, depth), white, Vector3(-w * 0.5 + 0.2, 0, 0)))
	n.add_child(Look.box(Vector3(0.4, h, depth), white, Vector3(w * 0.5 - 0.2, 0, 0)))
	n.add_child(Look.box(Vector3(w - 0.8, 0.78, depth), white, Vector3(0, h * 0.5 - 0.39, 0)))
	n.add_child(Look.box(Vector3(w - 0.8, 0.78, depth), white, Vector3(0, -h * 0.5 + 0.39, 0)))
	n.add_child(Look.box(Vector3(w + 0.12, 0.1, depth + 0.12), bone, Vector3(0, h * 0.5 + 0.05, 0)))
	# drawer fronts on the face, with glowing knobs
	for sy: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(w - 0.9, 0.6, 0.05), bone, Vector3(0, sy * (h * 0.5 - 0.39), -depth * 0.5 - 0.03)))
		n.add_child(Look.sphere(0.07, Look.flat(PINK, 0.3, 0.0, 2.4), Vector3(0, sy * (h * 0.5 - 0.39), -depth * 0.5 - 0.1)))


## A handless clock face on both broad sides of a falling-clock press (moves with it).
func _dress_clock(c: Crusher) -> void:
	var s: Vector3 = c.size
	var r: float = minf(s.x, s.y) * 0.44
	for sz: float in [-1.0, 1.0]:
		var face := Look.cylinder(r, 0.06, Look.flat(Color(0.96, 0.94, 0.9), 0.5), Vector3(0, 0.05, sz * (s.z * 0.5 + 0.03)), -1.0, 28)
		face.rotation.x = PI * 0.5
		c.add_child(face)
		var rim := Look.cylinder(r + 0.06, 0.04, Look.flat(Color(0.2, 0.15, 0.3), 0.4, 0.4), Vector3(0, 0.05, sz * (s.z * 0.5 + 0.015)), -1.0, 28)
		rim.rotation.x = PI * 0.5
		c.add_child(rim)
		for i: int in 12:
			var a: float = TAU * float(i) / 12.0
			var mk := Look.box(Vector3(0.04, r * 0.16, 0.02), Look.flat(Color(0.12, 0.09, 0.18), 0.5), Vector3(cos(a) * r * 0.8, 0.05 + sin(a) * r * 0.8, sz * (s.z * 0.5 + 0.07)))
			mk.rotation.z = a + PI * 0.5
			c.add_child(mk)
		c.add_child(Look.sphere(0.07, Look.flat(PINK, 0.3, 0.0, 2.2), Vector3(0, 0.05, sz * (s.z * 0.5 + 0.08))))


## A white door frame round a warp ring (the ring is the doorway's light). `floor_pos` / yaw as
## given to kit.portal (world).
func _dress_portal(floor_pos: Vector3, yaw_deg: float, col: Color) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), floor_pos)
	add_child(n)
	var white: StandardMaterial3D = Look.flat(WHITE, 0.45)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.22, 3.2, 0.3), white, Vector3(sx * 1.78, 1.6, 0)))
	n.add_child(Look.box(Vector3(3.9, 0.26, 0.36), white, Vector3(0, 3.33, 0)))
	n.add_child(Look.box(Vector3(3.6, 0.06, 0.06), Look.flat(col, 0.3, 0.0, 2.4), Vector3(0, 3.2, -0.2)))


## Mirror shards on a mirror beam's posts.
func _dress_laser(g: LaserGate) -> void:
	var post_h: float = maxf(g.size.y + 0.8, 1.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.85, 0.86, 0.96)
	glass.metallic = 1.0
	glass.roughness = 0.05
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (g.size.x * 0.5 + 0.18)
		var cap := Look.box(Vector3(0.5, 0.12, 0.5), Look.flat(WHITE, 0.45), Vector3(x, post_h * 0.5 + 0.06, 0))
		g.add_child(cap)
		var m := Look.box(Vector3(0.5, 0.8, 0.04), glass, Vector3(x, post_h * 0.5 + 0.55, 0))
		m.rotation = Vector3(0.0, sx * 0.6, 0.15)
		g.add_child(m)


## Every point the route passes (takeoffs, landings, walk targets) and every floor: the far
## scenery keeps clear of them.
func _route_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for st: Dictionary in route:
		for key: String in ["from", "to", "entry", "exit", "top", "jump_from"]:
			if st.has(key) and st[key] is Vector3 and (st[key] as Vector3) != Vector3.ZERO:
				pts.append(st[key])
	for p: Vector3 in _cp_world:
		pts.append(p)
	for f: Dictionary in _floors:
		pts.append(f["top"])
	return pts


func _clear_of(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist and absf(p.y - q.y) < dist + 30.0:
			return false
	return true


## True when nothing walkable sits inside the box (world centre, half extents).
func _box_free(c: Vector3, h: Vector3, skip: Dictionary = {}) -> bool:
	for f: Dictionary in _floors:
		if f == skip:
			continue
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		if absf(t.x - c.x) < h.x + s.x * 0.5 and absf(t.z - c.z) < h.z + s.z * 0.5 and t.y > c.y - h.y - 0.5 and t.y - float(f["drop"]) < c.y + h.y:
			return false
	return true


func _surroundings() -> void:
	var rng: RandomNumberGenerator = kit.rng
	var pts: Array[Vector3] = _route_points()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p: Vector3 in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid: Vector3 = (lo + hi) * 0.5
	var span: Vector3 = hi - lo
	# under every floor: a slim broken column under a small one, a stepped keel under a big one -
	# never where it would poke through anything walkable below
	for f: Dictionary in _floors:
		if f.has("frag"):
			continue
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		var under: Vector3 = t - Vector3(0, float(f["drop"]), 0)
		if maxf(s.x, s.z) <= 2.7:
			var length: float = rng.randf_range(2.5, 5.0)
			if _box_free(under - Vector3(0, length * 0.5 + 1.5, 0), Vector3(0.5, length * 0.5 + 1.5, 0.5), f):
				deco.column(under, minf(s.x, s.z) * 0.18, length)
		elif minf(s.x, s.z) >= 2.9:
			var depth: float = clampf(minf(s.x, s.z) * 0.6, 1.5, 5.0)
			if _box_free(under - Vector3(0, depth * 0.5, 0), Vector3(s.x * 0.5, depth * 0.5, s.z * 0.5), f):
				deco.keel(under, s.x, s.z, depth)
	# the endless chessboard far below, fading into the fog
	var board := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2400, 2400)
	board.mesh = pm
	var bmat := ShaderMaterial.new()
	bmat.shader = preload("res://visual/void_floor.gdshader")
	board.material_override = bmat
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.position = Vector3(mid.x, lo.y - 90.0, mid.z)
	add_child(board)
	# far scenery round the course: Escher knots, great doors, rooms hanging upside down, giant clocks,
	# chess pieces, slivers of the sky - kept well clear of the route
	var placed: int = 0
	var tries: int = 0
	while placed < 46 and tries < 900:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 110.0, hi.x + 110.0), rng.randf_range(lo.y - 30.0, hi.y + 45.0), rng.randf_range(lo.z - 110.0, hi.z + 110.0))
		if not _clear_of(p, pts, 34.0):
			continue
		var roll: float = rng.randf()
		var yaw: float = rng.randf() * TAU
		if roll < 0.18:
			deco.escher(p, rng.randf_range(1.6, 3.2))
		elif roll < 0.34:
			deco.giant_door(p, yaw, rng.randf_range(4.0, 8.0))
		elif roll < 0.48:
			var room: Node3D = deco.upside_room(p, yaw, rng.randf_range(8.0, 14.0), rng.randf_range(7.0, 11.0), rng.randf_range(4.0, 6.0))
			room.scale = Vector3.ONE * rng.randf_range(1.2, 2.2)
		elif roll < 0.62:
			deco.clock(p, VoidDecor.turn(yaw, rng.randf_range(0.9, 1.6), rng.randf_range(-0.3, 0.3)), rng.randf_range(5.0, 11.0), rng.randf_range(0.0, 0.5))
		elif roll < 0.74:
			deco.arch(p, VoidDecor.turn(yaw, 0.0, rng.randf_range(-0.6, 0.6)), rng.randf_range(8.0, 14.0), rng.randf_range(10.0, 18.0), PINK if rng.randf() < 0.5 else CYAN)
		elif roll < 0.86:
			var slab := Look.box(Vector3(16, 1.2, 16), Look.flat(WHITE, 0.5), p)
			add_child(slab)
			for k: int in rng.randi_range(2, 4):
				deco.chess(p + Vector3(rng.randf_range(-6, 6), 0.6, rng.randf_range(-6, 6)), rng.randf_range(3.0, 5.0), rng.randf() < 0.5, rng.randf() < 0.35)
		else:
			deco.stairs(p, VoidDecor.turn(yaw, rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2)), rng.randi_range(8, 14), rng.randf_range(3.0, 5.0), 0.8, 1.1)
		placed += 1
	# the sky's fallen pieces drifting all round, near and far
	for i: int in 40:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(maxf(span.x, span.z) * 0.5 + 40.0, maxf(span.x, span.z) * 0.5 + 220.0)
		var p2 := Vector3(mid.x + cos(a) * r, rng.randf_range(lo.y - 20.0, hi.y + 70.0), mid.z + sin(a) * r)
		deco.sky_shard(p2, rng.randf_range(4.0, 12.0), VoidDecor.turn(rng.randf() * TAU, rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8)))
	# ambient life along the route: shards drifting down, pink and cyan glints rising
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 5.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 9.0, absf(here.z - prev.z) * 0.5 + 12.0)
		VoidFx.fragments(self, c3 + Vector3(0, 4.0, 0), ext, 70)
		VoidFx.motes(self, c3 - Vector3(0, 3.0, 0), ext * Vector3(0.8, 0.9, 0.8), 40)


## Swap every walkable surface to the white chessboard shader (same colours and sizes).
func _void_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = preload("res://visual/void_tile.gdshader")
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


# ---- live effects -----------------------------------------------------------------------------------

## The door in the sky blazes: light and glass fountain out of it and the last of the dream falls away.
func _finish_sequence() -> void:
	var cols: Array[Color] = [PINK, CYAN, WHITE, PINK, CYAN]
	for i: int in cols.size():
		var fw: GPUParticles3D = VoidFx.finale(cols[i], 80)
		fw.position = _finish_pos + Vector3(-6.0 + 3.0 * float(i), 6.0 + float(i % 2) * 3.0, -2.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	var fx: Array[GPUParticles3D] = VoidFx.cp_burst(PINK)
	for p2: GPUParticles3D in fx:
		p2.position = _finish_pos + Vector3(0, 0.6, 0)
		add_child(p2)
		p2.restart()
		p2.emitting = true
	# SOUND: void_finish - the door in the sky opens: a rising choir and a shimmer of breaking glass
	WorldAudio.at(self, "void_finish", _finish_pos + Vector3(0, 3.0, 0), 1.0, 120.0)
	if _finish_light != null:
		_finish_light.light_energy = 9.0
		var tw: Tween = create_tween()
		tw.tween_property(_finish_light, "light_energy", 2.0, 1.6)
	await get_tree().create_timer(0.9).timeout


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
