extends LevelBase
## 28. PIXEL PANIC - inside a retro arcade cabinet, the second-to-last course before the siege and the
## finale, and a VERY HARD one. Everything is chunky: beveled 8-bit blocks, voxel chompers and ghosts,
## CRT scanlines over a pixel sky, a dot-matrix screen far below. It is hard through precision, pace and
## combinations (twelve-plus main-path jumps at 85-94% of max reach onto 1.0-1.4 m tiles), never blind timing.
##
## (the stage list is filled in as the course is built)
##
## Arcade mechanics (own scripts): ArcadeBlock (falling tetrominoes), ArcadeChomper (chompers, ghosts and
## the pong ball on rails), ArcadePaddle (pong paddles you ride), ArcadeGlitch (RGB glitch tiles that hop),
## ArcadeScroll (the auto-scroll kill wall) and ArcadeBoss (the pixel boss). Visuals: visual/arcade_*.
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every
## shortcut. Every wait the bot makes holds for 1.5 s more.

const DEV_START: int = 0
const DEV_LAST: int = 0
## Testing aid: print when the bot starts each route step (to read off its passing times).
const DEV_TRACE: bool = true

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable surface (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _floors: Array[Dictionary] = []
## Main-line landing widths (m) and jump counts, for the report / tests.
var landing_widths: Array[float] = []
var stat_wallruns: int = 0
var stat_mantles: int = 0
var stat_branches: int = 0
var stat_shortcuts: int = 0


func _configure() -> void:
	theme_id = "arcade"
	music_track = "arcade"
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
	var tx: float = INF if absf(d.x) < 0.001 else (float(a["hx"]) - inset) / absf(d.x)
	var tz: float = INF if absf(d.z) < 0.001 else (float(a["hz"]) - inset) / absf(d.z)
	return c + d * minf(tx, tz)


## Route a jump from the edge of `a` to the middle of `b` (+ offset). speed > 0 marks a momentum jump.
func _hop(a: Dictionary, b: Dictionary, off: Vector3 = Vector3.ZERO, hold: bool = true, speed: float = 0.0) -> void:
	var to: Vector3 = (b["c"] as Vector3) + off
	r_jump(_w(_edge(a, to)), _w(to), hold)
	if speed > 0.0:
		route[route.size() - 1]["speed"] = speed
	if route_variant == 0:
		landing_widths.append(minf(float(b["hx"]), float(b["hz"])) * 2.0)


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
	var col: Color = ArcadeFx.pal(_cp_world.size() + 1)
	var fx: Array[GPUParticles3D] = ArcadeFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: arcade_checkpoint - a stage banked: a bright coin-collect arpeggio
			WorldAudio.at(self, "arcade_checkpoint", which.global_position, 0.9, 40.0)
			for p2: GPUParticles3D in _cp_bursts[which]:
				p2.restart()
				p2.emitting = true)
	return d


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

## Stand still until test() is true (a wait: the 1.0 s human-pause check applies after it).
func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Run to `from`, jump, and fly (position-hold steering) to `to`.
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


## True when every [block, from, to] stays solid over [now + from, now + to].
static func _blocks_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as ArcadeBlock).solid_over(Game.course_time, float(e[1]), float(e[2])):
			return false
	return true


## True when every [chomper, spot (world), from, to] keeps clear of its spot over [now + from, now + to].
static func _chomp_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as ArcadeChomper).clear_at(e[1], 0.95, float(e[2]), float(e[3])):
			return false
	return true


## True when every [glitch, spot index, from, to] stays on that spot over [now + from, now + to].
static func _glitch_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as ArcadeGlitch).at_over(int(e[1]), Game.course_time, float(e[2]), float(e[3])):
			return false
	return true


# ---- trace (development aid) ------------------------------------------------------------------

var _tr_bot: RouteBot
var _tr_last: int = -1


func _process(_dt: float) -> void:
	if not DEV_TRACE or player == null:
		return
	if _tr_bot == null:
		var bots: Array[Node] = find_children("*", "RouteBot", false, false)
		if bots.is_empty():
			return
		_tr_bot = bots[0] as RouteBot
	if _tr_bot.step_index != _tr_last:
		_tr_last = _tr_bot.step_index
		var kind: String = "-"
		if _tr_last < route.size():
			kind = str(route[_tr_last]["kind"])
		print("TRACE step %d %s t=%.2f pos=%s" % [_tr_last, kind, Game.course_time, str(player.global_position.snapped(Vector3.ONE * 0.1))])


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6]
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
	# (dev) a finish right after the last stage built
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "main", 1.2)
	kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
	_finish_pos = _w(Vector3(0, 0, -9.5))
	_hop(cp0, fin)
	r_walk(_w(Vector3(0, 0, -9.8)))
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_sun = n as DirectionalLight3D
			else:
				_fill = n as DirectionalLight3D


# ---- stage 1: Insert Coin - four posts and a mantle up the coin slot ------------------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(12, 2, 12), "main", 0.0, _yaw)
	_floors.append({"top": _w(Vector3.ZERO), "size": Vector3(12, 0, 12), "drop": 2.0})
	var start: Dictionary = _area(Vector3(0, 0, 0), 6.0, 6.0)
	var p1: Dictionary = _post(_ahead(start, 0.87, 0.0, 1.4), 1.4, 1.4)
	var p2: Dictionary = _post(_ahead(p1, 0.89, 0.5, 1.2, -0.5))
	var p3: Dictionary = _post(_ahead(p2, 0.90, 0.5, 1.2, 0.5))
	var p4: Dictionary = _post(_ahead(p3, 0.88, 0.5, 1.0, -0.4), 1.0, 1.0)
	var beam: Dictionary = _blk(_ahead(p4, 0.86, 0.0, 3.2, 0.4), 1.2, 3.2, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 1.6
	var slot_top := Vector3(bc.x, bc.y + 3.3, front - 1.6 - 0.7)
	var slot: Dictionary = _ledge(slot_top, Vector3(2.6, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(slot, 0.86, 0.0, 5.0, -bc.x))
	_hop(start, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, p4)
	_hop(p4, beam, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(slot_top + Vector3(0, 0, 0.2)))
	stat_mantles += 1
	_hop(slot, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Ghost Alley - two posts, the beam across a ghost's loop -----------------------------

func _chomper(kind: int, pts: Array[Vector3], speed: float, offset: float, mode: int = 1, hover: float = 0.95, radius: float = 0.85) -> ArcadeChomper:
	var c := ArcadeChomper.new()
	c.kind = kind
	c.points = pts
	c.speed = speed
	c.offset = offset
	c.mode = mode as ArcadeChomper.Mode
	c.hover = hover
	c.radius = radius
	add_child(c)
	return c


func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var a1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.2))
	var a2: Dictionary = _post(_ahead(a1, 0.88, 0.5, 1.2, 0.4))
	var beam: Dictionary = _blk(_ahead(a2, 0.86, 0.0, 12.0, -0.4), 1.2, 12.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 6.0
	var land: Dictionary = _post(_ahead(beam, 0.88, 0.0, 1.2, 0.0))
	# the ghost's loop: a long rectangle across the beam; its two long sides cross the beam at z1 and z2
	var z1: float = bc.z + 3.5
	var z2: float = bc.z - 3.5
	var loop: Array[Vector3] = [Vector3(-7.5, 0, z1), Vector3(7.5, 0, z1), Vector3(7.5, 0, z2), Vector3(-7.5, 0, z2)]
	var world_loop: Array[Vector3] = []
	for p: Vector3 in loop:
		world_loop.append(_w(Vector3(bc.x + p.x, bc.y, p.z)))
	var ghost: ArcadeChomper = _chomper(1, world_loop, 6.5, 0.0, ArcadeChomper.Mode.LOOP)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(land["c"] as Vector3).x))
	var spot1: Vector3 = _w(Vector3(bc.x, bc.y, z1))
	var spot2: Vector3 = _w(Vector3(bc.x, bc.y, z2))
	var t1: float = 3.2
	var t2: float = 3.9
	_wait(func() -> bool: return _chomp_ok([[ghost, spot1, t1 - 0.3, t1 + 0.3 + 1.5], [ghost, spot2, t2 - 0.3, t2 + 0.3 + 1.5]]))
	_hop(cp0, a1)
	_hop(a1, a2)
	_hop(a2, beam, Vector3(0, 0, 5.0))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	_hop(beam, land)
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Tetris Well - three falling pieces to a stack, mantle the tower ----------------------

## A piece for the route: a line of `n` cells running forward (-z) from the near cell, plus extra side
## cells. `near` is the top centre of the NEAR cell. Returns the route area of the line.
func _piece(near: Vector3, n: int, tint: Color, period: float, phase_s: float, extra: Array[Vector2] = []) -> Dictionary:
	var blk := ArcadeBlock.new()
	var cells: Array[Vector2] = []
	for i: int in n:
		cells.append(Vector2(0, -i))
	for e: Vector2 in extra:
		cells.append(e)
	blk.cells = cells
	blk.tint = tint
	blk.period = period
	blk.phase = fposmod(phase_s / period, 1.0)
	blk.position = _w(near) - Vector3(0, blk.thick * 0.5, 0)
	blk.rotation.y = deg_to_rad(_yaw)
	add_child(blk)
	for c: Vector2 in cells:
		var ct: Vector3 = near + Vector3(c.x * blk.cell, 0, c.y * blk.cell)
		_floors.append({"top": _w(ct), "size": _sz(Vector3(blk.cell, 0, blk.cell)), "drop": blk.thick})
	var len_m: float = float(n) * blk.cell
	var area: Dictionary = _area(near + Vector3(0, 0, -(len_m - blk.cell) * 0.5), blk.cell * 0.5, len_m * 0.5)
	area["blk"] = blk
	return area


## The near-cell top for a line of `n` cells whose route area should be centred at `c`.
func _near_of(c: Vector3, n: int) -> Vector3:
	return c + Vector3(0, 0, (float(n) - 1.0) * 0.6)


func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var period: float = 7.0
	var cA: Vector3 = _ahead(cp0, 0.87, 0.0, 3.6)
	var A: Dictionary = _piece(_near_of(cA, 3), 3, ArcadeFx.CYAN, period, 0.0)
	var cB: Vector3 = _ahead(A, 0.89, 0.5, 3.6, 0.5)
	var B: Dictionary = _piece(_near_of(cB, 3), 3, ArcadeFx.ORANGE, period, -1.0, [Vector2(1, -2)])
	var cC: Vector3 = _ahead(B, 0.90, 0.5, 2.4, -0.5)
	var C: Dictionary = _piece(_near_of(cC, 2), 2, ArcadeFx.PURPLE, period, -2.0)
	var cp_dy: float = 0.0
	var lcz: Vector3 = C["c"]
	var tower_top := Vector3(lcz.x, lcz.y + 3.3, lcz.z - 1.2 - 1.5 - 0.9)
	var tower: Dictionary = _ledge(tower_top, Vector3(2.4, 9.0, 1.8))
	var cp: Dictionary = _cp(_ahead(tower, 0.86, cp_dy, 5.0, -lcz.x))
	var ba: ArcadeBlock = A["blk"]
	var bb: ArcadeBlock = B["blk"]
	var bcc: ArcadeBlock = C["blk"]
	var tA: float = 0.6
	var tB: float = 1.6
	var tC: float = 2.6
	_wait(func() -> bool: return _blocks_ok([[ba, tA - 0.3, tA + 0.6 + 1.5], [bb, tB - 0.3, tB + 0.6 + 1.5], [bcc, tC - 0.3, tC + 0.6 + 1.5]]))
	_hop(cp0, A)
	_hop(A, B)
	_hop(B, C)
	r_mantle(_w(Vector3(lcz.x, lcz.y, lcz.z - 1.2 + 0.35)), _w(tower_top + Vector3(0, 0, 0.3)))
	stat_mantles += 1
	_hop(tower, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- shared builders for the later stages -------------------------------------------------------------

## Front-edge z (local) a source landing needs so that a jump at `pct` of max reach (rise `dy`) reaches a
## target whose near edge is at `near_z` (the inverse of _ahead).
func _front_for(near_z: float, pct: float, dy: float) -> float:
	var m: float = pct * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	var e: float = float(k) * 0.2 - 0.03
	return near_z - 0.35 + e


## Posts at `pct` from `a` toward a target whose near edge is at `near_z`, until a final hop of at most
## `final_pct` reaches it. Returns the posts' areas.
func _chain(a: Dictionary, near_z: float, pct: float, final_pct: float, dx: float = 0.0, style: String = "accent") -> Array[Dictionary]:
	var posts: Array[Dictionary] = []
	var prev: Dictionary = a
	for i: int in 8:
		var front: float = (prev["c"] as Vector3).z - float(prev["hz"])
		if front - near_z + 0.75 <= final_pct * _reach(0.0):
			break
		var c: Vector3 = _ahead(prev, pct, 0.0, 1.2, dx if i % 2 == 0 else -dx)
		prev = _post(c, 1.2, 1.2, style)
		posts.append(prev)
	return posts


func _paddle(top: Vector3, size: Vector3, travel: Vector3, period: float, phase_s: float) -> ArcadePaddle:
	var p := ArcadePaddle.new()
	p.size = size
	p.points = [Vector3.ZERO, _d(travel)]
	p.period = period
	p.phase = fposmod(phase_s / period, 1.0)
	p.position = _w(top) - Vector3(0, size.y * 0.5, 0)
	p.rotation.y = deg_to_rad(_yaw)
	add_child(p)
	return p


# ---- stage 4: Pong Court (BRANCH) - ride the paddle | run the scoreboard wall ----------------------------
# [shortcut: posts straight down the middle at 92-93%]

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT (magenta): a pong paddle ferries you down its lane to a post
	var psize := Vector3(1.8, 0.5, 2.6)
	var z_near: float = f0 - 3.9
	var z_far: float = f0 - 14.4
	var pad: ArcadePaddle = _paddle(Vector3(-3.5, 0.0, z_near), psize, Vector3(0, 0, z_far - z_near), 8.0, 0.0)
	var pa: Dictionary = _post(Vector3(-3.5, 0.0, z_far - 1.3 - 3.0 - 0.6), 1.2, 1.2)
	var mc: Vector3 = _ahead(pa, 0.88, 0.0, 3.0, 3.5)
	var merge: Dictionary = _blk(Vector3(0, 0.0, mc.z), 11.0, 3.0)
	var mz: float = mc.z
	# RIGHT (cyan): the scoreboard wall run over the void onto a post, back to the merge
	var pb_front: float = _front_for(mz + 1.5, 0.88, 0.0)
	var pb: Dictionary = _post(Vector3(3.6, 0.0, pb_front + 1.0), 2.0, 2.0)
	var pbz: float = (pb["c"] as Vector3).z
	var wz_a: float = f0 - 1.5
	var wz_b: float = pbz + 3.1
	kit.wallrun(_w(Vector3(5.7, 1.2, (wz_a + wz_b) * 0.5)), Vector3(wz_a - wz_b, 6.5, 0.6), _yaw + 90.0)
	# SHORTCUT: posts straight down the middle
	var hids: Array[Dictionary] = _chain(_area(fc, 5.5, 1.5), mz + 1.5, 0.93, 0.92, 0.0)
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		var prev: Dictionary = _area(fc, 5.5, 1.5)
		for h: Dictionary in hids:
			_hop(prev, h)
			prev = h
		_hop(prev, merge, Vector3(0, 0, 0.4))
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, f0 + 0.45)))
		route.append({"kind": "x_jump", "from": _w(Vector3(-3.5, 0, f0 + 0.45)), "when_node": pad, "when_local": Vector3(0, 0.25, 0),
			"when_point": _w(Vector3(-3.5, 0.0, z_near)), "when_radius": 0.7, "lead": 0.5,
			"to_node": pad, "to_local": Vector3(0, 0.3, 0), "hold": true})
		var far_pt: Vector3 = _w(Vector3(-3.5, 0.0, z_far)) - Vector3(0, psize.y * 0.5, 0)
		r_jump_from_ride(pad, far_pt, 0.5, _w(pa["c"]), true, Vector3(0, 0.3, 0))
		_hop(pa, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.6, 0, f0 + 0.6)))
		r_wallrun(_w(Vector3(4.0, 0, f0 + 0.35)), _w(Vector3(5.2, 1.4, f0 - 3.4)), _w(Vector3(5.2, 1.4, pbz + 7.0)), _w(Vector3(3.6, 0, pbz + 0.2)))
		_hop(pb, merge, Vector3(3.6, 0, 0.6))
	stat_branches += 1
	stat_shortcuts += 1
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Warp Zone - the pipe up to a laser-cut beam, two posts out ----------------------------------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var pad: Dictionary = _blk(_ahead(cp0, 0.87, 0.0, 2.4), 2.4, 2.4, "alt", 0.7)
	var pc: Vector3 = pad["c"]
	var hi_y: float = 4.5
	var hi: Dictionary = _blk(Vector3(pc.x, pc.y + hi_y, pc.z - 13.0), 1.2, 8.0, "alt", 0.6)
	var hc: Vector3 = hi["c"]
	var door: WarpPortal = kit.portal(_w(Vector3(pc.x, pc.y, pc.z - 0.2)), _yaw, _w(Vector3(hc.x, hc.y, hc.z + 3.7)), _yaw, 7.0)
	var laser: LaserGate = kit.laser(_w(Vector3(hc.x, hc.y + 1.2, hc.z - 0.3)), Vector3(3.2, 2.4, 0.2), 5.0, 0.3, 0.0, _yaw)
	var q1: Dictionary = _post(_ahead(hi, 0.90, -1.0, 1.2, -0.4))
	var q2: Dictionary = _post(_ahead(q1, 0.91, -1.0, 1.0, 0.4), 1.0, 1.0)
	var cp: Dictionary = _cp(_ahead(q2, 0.86, 0.0, 5.0, -(q2["c"] as Vector3).x))
	var t_laser: float = 1.7
	_wait(func() -> bool: return _dark(laser, t_laser - 0.3, t_laser + 0.4 + 1.5))
	_hop(cp0, pad)
	r_portal(_w(Vector3(pc.x, pc.y, pc.z - 0.2)), door.exit_point())
	r_walk(_w(Vector3(hc.x, hc.y, hc.z - 3.2)))
	_hop(hi, q1)
	_hop(q1, q2)
	_hop(q2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Glitch Bridge - three tiles that hop, then the mirror wall run ---------------------------------

func _glitch(spots_local: Array[Vector3], hold: float, start_s: float, tint: Color = Color(0.95, 0.96, 1.0)) -> ArcadeGlitch:
	var g := ArcadeGlitch.new()
	var ws: Array[Vector3] = []
	for s: Vector3 in spots_local:
		ws.append(_w(s))
		_floors.append({"top": _w(s), "size": _sz(Vector3(1.3, 0, 1.3)), "drop": 0.4, "frag": true})
	g.spots = ws
	g.hold = hold
	g.phase = fposmod(-start_s / (hold * float(spots_local.size())), 1.0)
	g.yaw = _yaw
	g.tint = tint
	add_child(g)
	return g


func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var hold: float = 3.6
	var c1: Vector3 = _ahead(cp0, 0.88, 0.0, 1.3)
	var a1: Dictionary = _area(c1, 0.65, 0.65)
	var c2: Vector3 = _ahead(a1, 0.88, 0.5, 1.3, -0.4)
	var a2: Dictionary = _area(c2, 0.65, 0.65)
	var c3: Vector3 = _ahead(a2, 0.89, 0.5, 1.3, 0.4)
	var a3: Dictionary = _area(c3, 0.65, 0.65)
	var t1: float = 1.0
	var t2: float = 1.9
	var t3: float = 2.8
	var g1: ArcadeGlitch = _glitch([c1, c1 + Vector3(3.2, 0.6, 0.0)], hold, t1 - 1.4, ArcadeFx.CYAN.lerp(Color.WHITE, 0.6))
	var g2: ArcadeGlitch = _glitch([c2, c2 + Vector3(-3.2, 0.6, 0.0)], hold, t2 - 1.4, ArcadeFx.MAGENTA.lerp(Color.WHITE, 0.6))
	var g3: ArcadeGlitch = _glitch([c3, c3 + Vector3(3.2, 0.6, 0.0)], hold, t3 - 1.4, ArcadeFx.YELLOW.lerp(Color.WHITE, 0.6))
	var w2: Dictionary = _post(_ahead(a3, 0.88, 0.0, 1.4, -0.4), 1.4, 1.4)
	var wc: Vector3 = w2["c"]
	var f: float = wc.z - 0.7
	kit.wallrun(_w(Vector3(wc.x - 2.3, wc.y + 1.2, f - 9.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _post(Vector3(wc.x + 0.6, wc.y, f - 22.5), 1.8, 2.4)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(wc.x + 0.6)))
	_wait(func() -> bool: return _glitch_ok([[g1, 0, t1 - 0.3, t1 + 0.3 + 1.5], [g2, 0, t2 - 0.3, t2 + 0.3 + 1.5], [g3, 0, t3 - 0.3, t3 + 0.3 + 1.5]]))
	_hop(cp0, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	_hop(a3, w2)
	r_wallrun(_w(Vector3(wc.x - 0.3, wc.y, f + 0.35)), _w(Vector3(wc.x - 1.8, wc.y + 1.4, f - 3.6)),
		_w(Vector3(wc.x - 1.8, wc.y + 1.4, f - 14.5)), _w(Vector3(wc.x + 0.6, wc.y, f - 22.2)))
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ==== END MARKER ====
