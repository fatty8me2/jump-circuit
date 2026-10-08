extends LevelBase
## 28. PIXEL PANIC - inside a retro arcade cabinet, the second-to-last course before the siege and the
## finale, and a VERY HARD one. Everything is chunky: beveled 8-bit blocks, voxel chompers and ghosts,
## CRT scanlines over a pixel sky, a dot-matrix screen far below. It is hard through precision, pace and
## combinations (twelve-plus main-path jumps at 85-94% of max reach onto 1.0-1.4 m tiles), never blind timing.
##
##  1 Insert Coin     four posts and a beam, MANTLE the coin slot
##  2 Ghost Alley     two posts, the beam across a ghost's loop (chomper)
##  3 Tetris Well     three falling tetrominoes stack into stairs, MANTLE the tower
##  4 Pong Court      BRANCH: ride the pong paddle | WALL RUN the scoreboard [shortcut: posts down the middle]
##  5 Warp Zone       the WARP PIPE (portal) up to a beam under an invader LASER, two posts out
##  6 Glitch Bridge   three RGB glitch tiles that hop, WALL RUN the mirror
##  7 Bat and Block   a PISTON (pong bat) and a falling O-block (CRUSHER) on a beam, MANTLE
##  8 Pac Maze        BRANCH: two ghosts across the beam | two chained WALL RUNS [shortcut: 4.1 m MANTLE + cornice]
##  9 Scroll Screen   the AUTO-SCROLL wall chases you over posts and a WALL RUN
## 10 Stack Climb     three pieces stack a stair, MANTLE the tower, WALL RUN out
## 11 Space Invaders  BRANCH: three marching LASERS | MANTLE the invader block [shortcut: the warp pipe]
## 12 Pong Arena      two sideways paddles ferry you past a slow pong ball
## 13 Crossfire       two hopping glitch tiles, a ghost over the gap, a bat [shortcut: the secret warp pipe]
## 14 Level Up        two falling O-blocks, MANTLE, the longest jump (94%), WALL RUN
## 15 THE PIXEL BOSS SET PIECE: the screen scrolls behind you while the boss's gaze slams telegraphed
##                    columns on the platforms; run to the HIGH SCORE gate
##
## Arcade mechanics (own scripts): ArcadeBlock (falling tetrominoes), ArcadeChomper (chompers, ghosts and
## the pong ball on rails), ArcadePaddle (pong paddles you ride), ArcadeGlitch (RGB glitch tiles that hop),
## ArcadeScroll (the auto-scroll kill wall) and ArcadeBoss (the pixel boss). Visuals: visual/arcade_*.
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every
## shortcut. Every wait the bot makes holds for 1.5 s more.

const DEV_START: int = 0
const DEV_LAST: int = 0
## Testing aid: print when the bot starts each route step (to read off its passing times).
const DEV_TRACE: bool = false
## Every block / glitch tile is laid out CLOCK_SHIFT s ahead of the bot's release time, so the time-gated
## platforms are already solid when the level loads (test_m measures jumps against live collision).
const CLOCK_SHIFT: float = 2.0
## Testing aid: start the course clock here (a different alignment of every timed machine for the bot).
const DEV_SKEW: float = 0.0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: ArcadeDecor
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
	deco = ArcadeDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14]
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
		var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
		var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "main", 1.2)
		kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
		_finish_pos = _w(Vector3(0, 0, -9.5))
		_hop(cp0, fin)
		r_walk(_w(Vector3(0, 0, -9.8)))
	_surroundings()
	_arcade_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])
	if DEV_SKEW > 0.0:
		Game.course_time = DEV_SKEW


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
	_env.sky = ArcadeSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.5, 0.9)
	_env.ambient_light_energy = 0.7
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.1
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.06, 0.03, 0.16)
	_env.fog_density = 0.003
	_env.fog_aerial_perspective = 0.3
	_env.fog_sky_affect = 0.1
	_env.glow_enabled = true
	_env.glow_intensity = 0.85
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.25
	_env.adjustment_contrast = 1.12
	# a cool key light from the top of the cabinet and a magenta fill from the screen below
	_sun.light_color = Color(0.85, 0.9, 1.0)
	_sun.light_energy = 1.0
	_sun.rotation_degrees = Vector3(-60, 20, 0)
	_fill.light_color = Color(1.0, 0.3, 0.75)
	_fill.light_energy = 0.4
	_fill.rotation_degrees = Vector3(35, -150, 0)


## Every point the route passes and every floor: the far scenery keeps clear of them.
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
	# the dot-matrix screen far below
	var board := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2400, 2400)
	board.mesh = pm
	var bmat := ShaderMaterial.new()
	bmat.shader = preload("res://visual/arcade_floor.gdshader")
	board.material_override = bmat
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.position = Vector3(mid.x, lo.y - 70.0, mid.z)
	add_child(board)
	# big voxel signs along the course
	var signs: Array[String] = ["INSERT COIN", "1UP", "HI SCORE", "READY", "PLAY", "LEVEL 28", "PIXEL PANIC", "GAME ON"]
	var n_signs: int = 0
	var tries: int = 0
	while n_signs < 26 and tries < 600:
		tries += 1
		var p2 := Vector3(rng.randf_range(lo.x - 90.0, hi.x + 90.0), rng.randf_range(lo.y - 25.0, hi.y + 40.0), rng.randf_range(lo.z - 90.0, hi.z + 90.0))
		if not _clear_of(p2, pts, 26.0):
			continue
		var yaw: float = rng.randf() * TAU
		var roll: float = rng.randf()
		var b: Basis = ArcadeDecor.turn(yaw, rng.randf_range(-0.2, 0.2), rng.randf_range(-0.15, 0.15))
		if roll < 0.2:
			deco.text(p2, signs[rng.randi() % signs.size()], rng.randf_range(1.2, 2.2), ArcadeFx.pal(rng.randi()), b, 1.2)
		elif roll < 0.4:
			deco.sprite(p2, ArcadeDecor.INVADER, rng.randf_range(2.0, 4.2), ArcadeFx.pal(rng.randi()), b)
		elif roll < 0.5:
			deco.sprite(p2, ArcadeDecor.SQUID, rng.randf_range(2.0, 3.6), ArcadeFx.pal(rng.randi()), b)
		elif roll < 0.62:
			deco.sprite(p2, ArcadeDecor.GHOST, rng.randf_range(2.0, 3.8), ArcadeFx.pal(rng.randi() % 4 + 3), b)
		elif roll < 0.7:
			deco.sprite(p2, ArcadeDecor.HEART, rng.randf_range(1.6, 2.8), ArcadeFx.RED, b)
		elif roll < 0.78:
			deco.sprite(p2, ArcadeDecor.COIN, rng.randf_range(1.6, 3.2), ArcadeFx.YELLOW, b)
		elif roll < 0.9:
			deco.stack(p2 - Vector3(0, 6.0, 0), rng.randi_range(5, 8), rng.randi_range(5, 11), 1.8, ArcadeDecor.turn(yaw))
		else:
			deco.pong(p2, 1.5, b)
		n_signs += 1
	# a joystick and buttons far below the course, like a control panel
	for k: int in 3:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(60.0, 140.0)
		var at := Vector3(mid.x + cos(a) * r, lo.y - 60.0, mid.z + sin(a) * r)
		if k == 0:
			deco.joystick(at, 4.0)
		else:
			deco.button(at, 5.0, ArcadeFx.pal(k * 3))
	# pixels drifting up round every stage
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 3.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 8.0, absf(here.z - prev.z) * 0.5 + 12.0)
		ArcadeFx.pixels(self, c3, ext, 60)
	var tail: Vector3 = _finish_pos
	deco.text(tail + _d(Vector3(0, 11.0, -3.0)), "HIGH SCORE", 1.1, ArcadeFx.YELLOW, Basis(_b), 1.6)
	var sx: Array[float] = [-9.0, 9.0]
	for x: float in sx:
		deco.sprite(tail + _d(Vector3(x, 0.0, -2.0)), ArcadeDecor.GHOST, 0.9, ArcadeFx.pal(int(x) + 20), Basis(_b))


## Swap every walkable surface to the pixel-tile shader (same colours and sizes).
func _arcade_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = preload("res://visual/arcade_tile.gdshader")
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


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
	blk.phase = fposmod((phase_s + CLOCK_SHIFT) / period, 1.0)
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
	var tA: float = 1.2
	var tB: float = 2.0
	var tC: float = 2.8
	var cA: Vector3 = _ahead(cp0, 0.87, 0.0, 3.6)
	var A: Dictionary = _piece(_near_of(cA, 3), 3, ArcadeFx.CYAN, period, 2.5 - tA)
	var cB: Vector3 = _ahead(A, 0.89, 0.5, 3.6, 0.5)
	var B: Dictionary = _piece(_near_of(cB, 3), 3, ArcadeFx.ORANGE, period, 2.5 - tB, [Vector2(1, -2)])
	var cC: Vector3 = _ahead(B, 0.90, 0.5, 2.4, -0.5)
	var C: Dictionary = _piece(_near_of(cC, 2), 2, ArcadeFx.PURPLE, period, 2.5 - tC)
	var cp_dy: float = 0.0
	var lcz: Vector3 = C["c"]
	var tower_top := Vector3(lcz.x, lcz.y + 3.3, lcz.z - 1.2 - 1.5 - 0.9)
	var tower: Dictionary = _ledge(tower_top, Vector3(2.4, 9.0, 1.8))
	var cp: Dictionary = _cp(_ahead(tower, 0.86, cp_dy, 5.0, -lcz.x))
	var ba: ArcadeBlock = A["blk"]
	var bb: ArcadeBlock = B["blk"]
	var bcc: ArcadeBlock = C["blk"]
	_wait(func() -> bool: return _blocks_ok([[ba, tA - 0.3, tA + 0.4 + 1.5], [bb, tB - 0.3, tB + 0.4 + 1.5], [bcc, tC - 0.3, tC + 0.4 + 1.5]]))
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
		r_walk(_w(Vector3(4.0, 0, fc.z + 1.3)))
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
	g.phase = fposmod(-(start_s - CLOCK_SHIFT) / (hold * float(spots_local.size())), 1.0)
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


# ---- stage 7: Bat and Block - a pong paddle punches across the beam, a falling O-block, a mantle ----------

## Phase fraction that puts cycle position `u0` at course time `t0` (the machines are lined up for the bot's
## passing times, measured with DEV_TRACE: the wait releases when every machine is in its window).
func _ph(u0: float, t0: float, period: float) -> float:
	return fposmod(u0 - t0 / period, 1.0)


## A pong paddle that punches across the route: the piston. `top` is the ram's top centre when shut; it
## punches toward local +x when dir = 1 (-x when -1).
func _bat(top: Vector3, dir: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.2)
	return kit.piston(_w(top), size, _yaw - 90.0 * dir, stroke, period, phase, 10.0)


func _press(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	return kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)


func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.2))
	var walk: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 15.0, 0.0), 1.4, 15.0, "alt", 0.6)
	var wc: Vector3 = walk["c"]
	var w0: float = wc.z + 7.5
	var period: float = 6.0
	var t_bat: float = 2.5
	var t_press: float = 3.4
	var bat: Piston = _bat(Vector3(wc.x - 0.7 - 0.6 - 0.15, wc.y + 1.35, w0 - 4.0), 1.0, 2.6, period, _ph(0.0, t_bat - 0.5, period))
	var press: Crusher = _press(Vector3(wc.x, wc.y, w0 - 10.0), Vector3(2.2, 1.2, 2.0), 3.2, period, _ph(0.90, t_press - 0.5, period))
	var ledge_top := Vector3(wc.x, wc.y + 3.3, w0 - 15.0 - 1.2 - 1.1)
	var ld: Dictionary = _ledge(ledge_top, Vector3(3.6, 9.0, 2.2))
	var p2: Dictionary = _post(_ahead(ld, 0.88, 0.0, 1.2, 0.4))
	var p3: Dictionary = _post(_ahead(p2, 0.90, 0.6, 1.0, -0.4), 1.0, 1.0)
	var cp: Dictionary = _cp(_ahead(p3, 0.86, 0.0, 5.0, -(p3["c"] as Vector3).x))
	_wait(func() -> bool: return _ram_clear(bat, t_bat - 0.3, t_bat + 0.4 + 1.5) and _press_ok(press, t_press - 0.3, t_press + 0.3 + 1.5))
	_hop(cp0, p1)
	_hop(p1, walk, Vector3(0, 0, 7.0))
	r_walk(_w(Vector3(wc.x, wc.y, w0 - 15.0 + 0.9)))
	r_mantle(_w(Vector3(wc.x, wc.y, w0 - 15.0 + 0.35)), _w(ledge_top + Vector3(0, 0, 0.5)))
	stat_mantles += 1
	_hop(ld, p2)
	_hop(p2, p3)
	_hop(p3, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 8: Pac Maze (BRANCH) - two ghosts across the beam | two chained wall runs ---------------------
# [shortcut: a 4.1 m mantle up the power-pellet column, then its narrow cornice]

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# RIGHT (cyan): run the right wall, kick across to the left one, run it, kick to a post
	kit.wallrun(_w(Vector3(6.1, 1.2, f0 - 7.0)), Vector3(12.0, 6.5, 0.6), _yaw + 90.0)
	kit.wallrun(_w(Vector3(1.5, 3.6, f0 - 17.5)), Vector3(9.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, 0.0, f0 - 27.6), 1.6, 1.6)
	var pb2: Dictionary = _post(_ahead(pb, 0.88, 0.0, 1.2))
	var mc: Vector3 = _ahead(pb2, 0.86, 0.0, 3.0)
	var merge: Dictionary = _blk(Vector3(0, 0.0, mc.z), 11.0, 3.0)
	var mz: float = mc.z
	# LEFT (magenta): a beam across two ghosts' rails, then posts to the merge
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.5)
	var beam: Dictionary = _blk(_ahead(left, 0.86, 0.0, 13.0), 1.2, 13.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var z1: float = bc.z + 3.5
	var z2: float = bc.z - 3.0
	var t1: float = 1.35
	var t2: float = 2.1
	var rail: float = 20.0
	var spd: float = 4.0
	var c1: float = t1 + 2.8
	var c2: float = t2 + 2.8
	var g1: ArcadeChomper = _chomper(1, [_w(Vector3(bc.x - rail * 0.5, bc.y, z1)), _w(Vector3(bc.x + rail * 0.5, bc.y, z1))], spd, rail * 0.5 - spd * c1)
	var g2: ArcadeChomper = _chomper(3, [_w(Vector3(bc.x + rail * 0.5, bc.y, z2)), _w(Vector3(bc.x - rail * 0.5, bc.y, z2))], spd, rail * 0.5 - spd * c2)
	var posts: Array[Dictionary] = _chain(beam, mz + 1.5, 0.88, 0.88, 0.0, "accent")
	# SHORTCUT: the power-pellet column (a 4.1 m mantle) and its narrow cornice, then a drop to the merge
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
		_wait(func() -> bool: return _chomp_ok([[g1, _w(Vector3(bc.x, bc.y, z1)), t1 - 0.3, t1 + 0.3 + 1.5], [g2, _w(Vector3(bc.x, bc.y, z2)), t2 - 0.3, t2 + 0.3 + 1.5]]),
			_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_hop(left, beam, Vector3(0, 0, 5.5))
		r_walk(_w(Vector3(bc.x, bc.y, bc.z - 5.8)))
		var prev: Dictionary = beam
		for p: Dictionary in posts:
			_hop(prev, p)
			prev = p
		_hop(prev, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(4.2, 0, fc.z + 1.3)))
		r_wallrun(_w(Vector3(4.2, 0, f0 + 0.35)), _w(Vector3(5.6, 1.4, f0 - 3.2)), _w(Vector3(5.6, 1.4, f0 - 10.6)), _w(Vector3(2.0, 4.4, f0 - 14.4)))
		r_wallrun(Vector3.ZERO, _w(Vector3(2.0, 4.4, f0 - 14.4)), _w(Vector3(2.0, 4.4, f0 - 19.6)), _w(Vector3(3.6, 0.0, f0 - 27.4)), true, true)
		_hop(pb, pb2)
		_hop(pb2, merge, Vector3(3.6, 0, 0.6))
	stat_branches += 1
	stat_shortcuts += 1
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Scroll Screen - the screen scrolls: run the posts and the wall ahead of the static --------

func _scroll(pts_local: Array[Vector3], trigger_local: Vector3, speed: float, delay: float, lead: float, stop_before_end: float) -> ArcadeScroll:
	var s := ArcadeScroll.new()
	var ws: Array[Vector3] = []
	for p: Vector3 in pts_local:
		ws.append(_w(p))
	s.path = ws
	s.speed = speed
	s.delay = delay
	s.lead = lead
	s.stop_before_end = stop_before_end
	s.trigger_pos = _w(trigger_local)
	s.trigger_size = Vector3(2.4, 3.0, 2.4)
	add_child(s)
	return s


func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var s1: Dictionary = _post(_ahead(cp0, 0.87, 0.0, 1.4), 1.4, 1.4)
	var s2: Dictionary = _post(_ahead(s1, 0.89, 0.5, 1.2, -0.5))
	var s3: Dictionary = _post(_ahead(s2, 0.90, 0.5, 1.2, 0.5))
	var beam: Dictionary = _blk(_ahead(s3, 0.86, 0.0, 4.0, -0.5), 1.2, 4.0, "alt", 0.6)
	var w2: Dictionary = _post(_ahead(beam, 0.88, 0.0, 1.6, 0.5), 1.6, 1.6)
	var wc: Vector3 = w2["c"]
	var f: float = wc.z - 0.8
	kit.wallrun(_w(Vector3(wc.x + 2.4, wc.y + 1.2, f - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _post(Vector3(wc.x - 0.6, wc.y, f - 21.5), 1.6, 2.0)
	var s4: Dictionary = _post(_ahead(land, 0.90, 0.5, 1.0, 0.4), 1.0, 1.0)
	var cp: Dictionary = _cp(_ahead(s4, 0.86, 0.0, 5.0, -(s4["c"] as Vector3).x))
	var pts: Array[Vector3] = [Vector3.ZERO, s1["c"], s2["c"], s3["c"], beam["c"], w2["c"], land["c"], s4["c"], cp["c"]]
	_scroll(pts, (s1["c"] as Vector3) + Vector3(0, 1.2, 0), 4.6, 2.4, 16.0, 6.0)
	_hop(cp0, s1)
	_hop(s1, s2)
	_hop(s2, s3)
	_hop(s3, beam, Vector3(0, 0, 0.5))
	_hop(beam, w2)
	r_wallrun(_w(Vector3(wc.x + 0.3, wc.y, f + 0.35)), _w(Vector3(wc.x + 1.9, wc.y + 1.4, f - 3.6)),
		_w(Vector3(wc.x + 1.9, wc.y + 1.4, f - 14.0)), _w(Vector3(wc.x - 0.6, wc.y, f - 21.2)))
	_hop(land, s4)
	_hop(s4, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 10: Stack Climb - three pieces stack up a stair, MANTLE the tower, wall run out ---------------

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var period: float = 7.0
	var tA: float = 1.2
	var tB: float = 2.0
	var tC: float = 2.8
	var cA: Vector3 = _ahead(cp0, 0.87, 1.2, 2.4)
	var A: Dictionary = _piece(_near_of(cA, 2), 2, ArcadeFx.CYAN, period, 2.5 - tA)
	var cB: Vector3 = _ahead(A, 0.88, 1.2, 3.6, 0.5)
	var B: Dictionary = _piece(_near_of(cB, 3), 3, ArcadeFx.GREEN, period, 2.5 - tB, [Vector2(-1, 0)])
	var cC: Vector3 = _ahead(B, 0.89, 1.2, 2.4, -0.5)
	var C: Dictionary = _piece(_near_of(cC, 2), 2, ArcadeFx.RED, period, 2.5 - tC)
	var lc: Vector3 = C["c"]
	var tower_top := Vector3(lc.x, lc.y + 3.3, lc.z - 1.2 - 1.5 - 0.9)
	var tower: Dictionary = _ledge(tower_top, Vector3(2.4, 9.0, 1.8))
	var w2: Dictionary = _post(_ahead(tower, 0.88, 0.0, 1.6, -0.3), 1.6, 1.6)
	var wc: Vector3 = w2["c"]
	var f: float = wc.z - 0.8
	kit.wallrun(_w(Vector3(wc.x - 2.4, wc.y + 1.2, f - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _post(Vector3(wc.x + 0.6, wc.y, f - 21.5), 1.6, 2.0)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(wc.x + 0.6)))
	var ba: ArcadeBlock = A["blk"]
	var bb: ArcadeBlock = B["blk"]
	var bcc: ArcadeBlock = C["blk"]
	_wait(func() -> bool: return _blocks_ok([[ba, tA - 0.3, tA + 0.4 + 1.5], [bb, tB - 0.3, tB + 0.4 + 1.5], [bcc, tC - 0.3, tC + 0.4 + 1.5]]))
	_hop(cp0, A)
	_hop(A, B)
	_hop(B, C)
	r_mantle(_w(Vector3(lc.x, lc.y, lc.z - 1.2 + 0.35)), _w(tower_top + Vector3(0, 0, 0.3)))
	stat_mantles += 1
	_hop(tower, w2)
	r_wallrun(_w(Vector3(wc.x - 0.3, wc.y, f + 0.35)), _w(Vector3(wc.x - 1.9, wc.y + 1.4, f - 3.6)),
		_w(Vector3(wc.x - 1.9, wc.y + 1.4, f - 14.0)), _w(Vector3(wc.x + 0.6, wc.y, f - 21.2)))
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 11: Space Invaders (BRANCH) - the marching laser lane | the mantle stair --------------------
# [shortcut: the warp pipe on the small post]

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# RIGHT (cyan): mantle the first invader block, cross its top, drop to a post
	var la_top := Vector3(3.6, 3.3, f0 - 1.6 - 1.2)
	var la: Dictionary = _ledge(la_top, Vector3(2.4, 9.0, 2.4))
	var tb: Dictionary = _blk(_ahead(la, 0.86, 0.0, 8.0), 1.2, 8.0, "alt", 0.6)
	var pr: Dictionary = _post(_ahead(tb, 0.85, -3.3, 1.2))
	var mc: Vector3 = _ahead(pr, 0.86, 0.0, 3.0)
	var merge: Dictionary = _blk(Vector3(0, 0.0, mc.z), 11.0, 3.0)
	var mz: float = mc.z
	# LEFT (magenta): a beam under three lasers that march across it
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.5)
	var beam: Dictionary = _blk(_ahead(left, 0.86, 0.0, 14.0), 1.2, 14.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var period: float = 5.4
	var t0: float = 1.0
	var lz: Array[float] = [bc.z + 3.5, bc.z, bc.z - 3.5]
	var tl: Array[float] = [t0 + 0.3, t0 + 0.7, t0 + 1.05]
	var lasers: Array[LaserGate] = []
	for k: int in 3:
		lasers.append(kit.laser(_w(Vector3(bc.x, bc.y + 1.2, lz[k])), Vector3(3.2, 2.4, 0.2), period, 0.3, _ph(0.3, tl[k] - 0.5, period), _yaw))
	var posts: Array[Dictionary] = _chain(beam, mz + 1.5, 0.88, 0.88, 0.0, "accent")
	# SHORTCUT: a small post off the fork's front; the warp pipe on it opens onto the merge
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
		_wait(func() -> bool: return _dark(lasers[0], tl[0] - 0.3, tl[0] + 0.3 + 1.5) and _dark(lasers[1], tl[1] - 0.3, tl[1] + 0.3 + 1.5) \
			and _dark(lasers[2], tl[2] - 0.3, tl[2] + 0.3 + 1.5), _w(Vector3(-3.5, 0, fc.z + 0.6)))
		_hop(left, beam, Vector3(0, 0, 6.0))
		r_walk(_w(Vector3(bc.x, bc.y, bc.z - 6.2)))
		var prev: Dictionary = beam
		for p: Dictionary in posts:
			_hop(prev, p)
			prev = p
		_hop(prev, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_mantle(_w(Vector3(3.6, 0, f0 + 0.35)), _w(la_top + Vector3(0, 0, 0.3)))
		stat_mantles += 1
		_hop(la, tb)
		r_walk(_w(Vector3(3.6, 3.3, (tb["c"] as Vector3).z - 3.4)))
		_hop(tb, pr)
		_hop(pr, merge, Vector3(0, 0, 0.6))
	stat_branches += 1
	stat_shortcuts += 1
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 12: Pong Arena - two sideways paddles ferry you across, a slow ball roams the middle -----------

## A paddle you ride sideways: it slides along x from `x0` to `x1` at height `y`, lane centre z.
func _lane_paddle(x0: float, x1: float, y: float, z: float, period: float, phase_s: float) -> ArcadePaddle:
	return _paddle(Vector3(x0, y, z), Vector3(2.6, 0.5, 1.8), Vector3(x1 - x0, 0, 0), period, phase_s)


func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var xa: float = -3.5
	var xb: float = 3.5
	var pa: Dictionary = _post(_ahead(cp0, 0.84, 0.0, 1.4, xa), 1.4, 1.4)
	var pac: Vector3 = pa["c"]
	var z1: float = pac.z - 0.7 - 2.6 - 0.9
	var period: float = 6.0
	var tb: float = 1.4
	var p1: ArcadePaddle = _lane_paddle(xa, xb, pac.y, z1, period, 0.0)
	var m: Dictionary = _post(Vector3(xb, pac.y, z1 - 0.9 - 3.0 - 0.7), 1.4, 1.4)
	var mc: Vector3 = m["c"]
	var z2: float = mc.z - 0.7 - 2.6 - 0.9
	var t_m: float = tb + 4.2
	var p2: ArcadePaddle = _lane_paddle(xb, xa, pac.y, z2, period, -3.9)
	var pb: Dictionary = _post(Vector3(xa, pac.y, z2 - 0.9 - 3.0 - 0.7), 1.4, 1.4)
	var pbc: Vector3 = pb["c"]
	var q1: Dictionary = _post(_ahead(pb, 0.84, 0.5, 1.2, 1.6))
	var q2: Dictionary = _post(_ahead(q1, 0.86, 0.5, 1.0, 1.6), 1.0, 1.0)
	var cp: Dictionary = _cp(_ahead(q2, 0.86, 0.0, 5.0, 1.0))
	# the ball: a slow pong ball bouncing in the court between the lanes
	var lo := Vector3(-8.0, pac.y, mc.z - 2.4)
	var hi := Vector3(8.0, pac.y, mc.z + 2.4)
	var ball: ArcadeChomper = _chomper(5, [_w(lo), _w(hi)], 0.0, 0.0, ArcadeChomper.Mode.COURT, 0.7, 0.55)
	ball.vel = Vector2(3.0, 1.1)
	ball.court_o = Vector2(3.0, 1.0)
	_wait(func() -> bool: return p1.offset_at(Game.course_time + tb).length() < 0.45 		and ball.clear_at(_w(Vector3(mc.x, mc.y, mc.z)), 1.5, t_m - 1.0, t_m + 1.0 + 1.5))
	_hop(cp0, pa)
	route.append({"kind": "x_jump", "from": _w(_edge(pa, Vector3(xa, 0, z1))), "when_node": p1, "when_local": Vector3(0, 0.25, 0),
		"when_point": _w(Vector3(xa, pac.y, z1)), "when_radius": 0.8, "lead": 0.5,
		"to_node": p1, "to_local": Vector3(0, 0.3, 0), "hold": true})
	var p1_end: Vector3 = _w(Vector3(xb, pac.y, z1)) - Vector3(0, 0.25, 0)
	r_jump_from_ride(p1, p1_end, 0.5, _w(mc), true, Vector3(0, 0.3, 0))
	route.append({"kind": "x_jump", "from": _w(_edge(m, Vector3(xb, 0, z2))), "when_node": p2, "when_local": Vector3(0, 0.25, 0),
		"when_point": _w(Vector3(xb, pac.y, z2)), "when_radius": 0.8, "lead": 0.5,
		"to_node": p2, "to_local": Vector3(0, 0.3, 0), "hold": true})
	var p2_end: Vector3 = _w(Vector3(xa, pac.y, z2)) - Vector3(0, 0.25, 0)
	r_jump_from_ride(p2, p2_end, 0.5, _w(pbc), true, Vector3(0, 0.3, 0))
	_hop(pb, q1)
	_hop(q1, q2)
	_hop(q2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 13: Crossfire - two hopping glitch tiles, a ghost over the gap, a bat on the last beam ------------
# [shortcut: the secret warp pipe past the tiles]

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var hold: float = 3.0
	var a1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.2))
	var g1c: Vector3 = _ahead(a1, 0.88, 0.0, 1.3, 0.3)
	var g1a: Dictionary = _area(g1c, 0.65, 0.65)
	var a2: Dictionary = _post(_ahead(g1a, 0.89, 0.4, 1.2, -0.3))
	var g2c: Vector3 = _ahead(a2, 0.88, 0.0, 1.3, 0.3)
	var g2a: Dictionary = _area(g2c, 0.65, 0.65)
	var a3: Dictionary = _blk(_ahead(g2a, 0.86, 0.0, 4.4, -0.3), 1.2, 4.4, "alt", 0.6)
	var a3c: Vector3 = a3["c"]
	var a4: Dictionary = _post(_ahead(a3, 0.90, 0.5, 1.0, 0.4), 1.0, 1.0)
	var cp: Dictionary = _cp(_ahead(a4, 0.86, 0.0, 5.0, -(a4["c"] as Vector3).x))
	var t1: float = 0.95
	var t2: float = 2.55
	var t_ghost: float = 2.1
	var t_bat: float = 3.95
	var period: float = 6.0
	var g1: ArcadeGlitch = _glitch([g1c, g1c + Vector3(3.2, 0.6, 0.0)], hold, t1 - 0.8, ArcadeFx.CYAN.lerp(Color.WHITE, 0.6))
	var g2: ArcadeGlitch = _glitch([g2c, g2c + Vector3(-3.2, 0.6, 0.0)], hold, t2 - 0.8, ArcadeFx.YELLOW.lerp(Color.WHITE, 0.6))
	# the ghost patrols a long rail across the flight between the second post and the second tile
	var a2c: Vector3 = a2["c"]
	var zg: float = (a2c.z - 0.6 + g2c.z + 0.65) * 0.5
	var rail: float = 24.0
	var spd: float = 4.0
	var gh: ArcadeChomper = _chomper(2, [_w(Vector3(a2c.x - rail * 0.5, a2c.y, zg)), _w(Vector3(a2c.x + rail * 0.5, a2c.y, zg))], spd, rail * 0.5 - spd * (t_ghost + 2.8 - CLOCK_SHIFT))
	var bat: Piston = _bat(Vector3(a3c.x - 0.6 - 0.6 - 0.15, a3c.y + 1.35, a3c.z), 1.0, 2.6, period, _ph(0.0, t_bat - 0.5 - CLOCK_SHIFT, period))
	# SHORTCUT: a small post beside the first post; the secret warp pipe on it opens onto the last beam
	var sp: Dictionary = _post(_ahead(a1, 0.84, 0.0, 1.2, -2.8), 1.2, 1.2, "accent")
	var spc: Vector3 = sp["c"]
	var sdoor: WarpPortal = kit.portal(_w(spc + Vector3(0, 0, -0.3)), _yaw, _w(Vector3(a3c.x, a3c.y, a3c.z + 1.6)), _yaw, 6.0)
	var spot_g: Vector3 = _w(Vector3(a2c.x, a2c.y, zg))
	if route_variant == 2:
		_wait(func() -> bool: return _ram_clear(bat, 2.1 - 0.3, 2.1 + 0.4 + 1.5))
	_hop(cp0, a1)
	if route_variant == 2:
		_hop(a1, sp)
		r_portal(_w(spc + Vector3(0, 0, -0.6)), sdoor.exit_point())
		r_walk(_w(Vector3(a3c.x, a3c.y, a3c.z - 1.6)))
	else:
		_wait(func() -> bool: return _glitch_ok([[g1, 0, t1 - 0.3, t1 + 0.3 + 1.5], [g2, 0, t2 - 0.3, t2 + 0.3 + 1.5]]) \
			and gh.clear_at(spot_g, 0.95, t_ghost - 0.5, t_ghost + 0.5 + 1.5) and _ram_clear(bat, t_bat - 0.3, t_bat + 0.4 + 1.5))
		_hop(a1, g1a)
		_hop(g1a, a2)
		_hop(a2, g2a)
		_hop(g2a, a3)
		r_walk(_w(Vector3(a3c.x, a3c.y, a3c.z - 1.9)))
	_hop(a3, a4)
	_hop(a4, cp, Vector3(0, 0, 1.2))
	stat_shortcuts += 1
	r_checkpoint()
	return cp["c"]


# ---- stage 14: Level Up - two falling O-blocks on the beam, MANTLE, the longest jump, the wall run ---------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.2))
	var walk: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 13.0), 1.4, 13.0, "alt", 0.6)
	var wc: Vector3 = walk["c"]
	var w0: float = wc.z + 6.5
	var period: float = 6.0
	var t1: float = 2.4
	var t2: float = 3.2
	var c1: Crusher = _press(Vector3(wc.x, wc.y, w0 - 3.5), Vector3(2.2, 1.2, 2.0), 3.2, period, _ph(0.90, t1 - 0.5, period))
	var c2: Crusher = _press(Vector3(wc.x, wc.y, w0 - 8.0), Vector3(2.2, 1.2, 2.0), 3.2, period, _ph(0.90, t2 - 0.5, period))
	var ledge_top := Vector3(wc.x, wc.y + 3.3, w0 - 13.0 - 1.4 - 1.0)
	var ld: Dictionary = _ledge(ledge_top, Vector3(3.2, 9.0, 2.0))
	var runway: Dictionary = _blk(_ahead(ld, 0.88, 0.0, 5.0, 0.0), 1.2, 5.0, "alt", 0.6)
	var far: Dictionary = _post(_ahead(runway, 0.92, 0.0, 1.2, 0.0))
	var farc: Vector3 = far["c"]
	var f: float = farc.z - 0.6
	kit.wallrun(_w(Vector3(farc.x + 2.4, farc.y + 1.2, f - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _post(Vector3(farc.x - 0.6, farc.y, f - 21.5), 1.6, 2.0)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(farc.x - 0.6)))
	_wait(func() -> bool: return _press_ok(c1, t1 - 0.3, t1 + 0.3 + 1.5) and _press_ok(c2, t2 - 0.3, t2 + 0.3 + 1.5))
	_hop(cp0, p1)
	_hop(p1, walk, Vector3(0, 0, 6.0))
	r_walk(_w(Vector3(wc.x, wc.y, w0 - 13.0 + 0.9)))
	r_mantle(_w(Vector3(wc.x, wc.y, w0 - 13.0 + 0.35)), _w(ledge_top + Vector3(0, 0, 0.4)))
	stat_mantles += 1
	r_walk(_w(Vector3(ledge_top.x, ledge_top.y, ledge_top.z - 0.4)))
	_hop(ld, runway, Vector3(0, 0, 1.6))
	r_walk(_w((runway["c"] as Vector3) + Vector3(0, 0, -1.9)))
	_hop(runway, far)
	r_wallrun(_w(Vector3(farc.x + 0.3, farc.y, f + 0.35)), _w(Vector3(farc.x + 1.9, farc.y + 1.4, f - 3.6)),
		_w(Vector3(farc.x + 1.9, farc.y + 1.4, f - 14.0)), _w(Vector3(farc.x - 0.6, farc.y, f - 21.2)))
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 15: THE PIXEL BOSS - the screen scrolls, the boss takes aim, the HIGH SCORE gate ----------------

var boss: ArcadeBoss
var _finish_light: OmniLight3D


func _stage_15() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	# the arena: eleven small platforms in a line, the boss's gaze falling on some of them
	var pcts: Array[float] = [0.88, 0.86, 0.90, 0.90, 0.86, 0.91, 0.88, 0.90, 0.91, 0.88, 0.90]
	var dys: Array[float] = [0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.5, 0.0, 0.5, 0.0, 0.5]
	var lens: Array[float] = [1.2, 3.0, 1.2, 1.2, 4.0, 1.0, 2.4, 1.2, 1.0, 3.0, 1.2]
	var wid: Array[float] = [1.2, 1.2, 1.2, 1.2, 1.2, 1.0, 2.4, 1.2, 1.0, 1.2, 1.2]
	var dxs: Array[float] = [0.0, 0.0, 0.4, -0.4, 0.0, 0.4, 0.0, -0.4, 0.4, 0.0, -0.4]
	var areas: Array[Dictionary] = []
	var prev: Dictionary = cp0
	for i: int in pcts.size():
		var c: Vector3 = _ahead(prev, pcts[i], dys[i], lens[i], dxs[i])
		var a: Dictionary
		if lens[i] > 2.0:
			a = _blk(c, wid[i], lens[i], "alt", 0.6)
		else:
			a = _post(c, wid[i], lens[i])
		areas.append(a)
		prev = a
	var last: Dictionary = areas[areas.size() - 1]
	var fin: Dictionary = _blk(_ahead(last, 0.86, 0.5, 6.0, -(last["c"] as Vector3).x), 6.0, 6.0, "main", 1.2)
	var fc: Vector3 = fin["c"]
	kit.finish(_w(fc + Vector3(0, 0, -0.6)), _yaw)
	_finish_pos = _w(fc + Vector3(0, 0, -0.6))
	# the scrolling screen: it starts when you step on the first platform
	var pts: Array[Vector3] = [Vector3.ZERO]
	for a2: Dictionary in areas:
		pts.append(a2["c"])
	pts.append(fc)
	_scroll(pts, (areas[0]["c"] as Vector3) + Vector3(0, 1.2, 0), 4.0, 3.0, 20.0, 8.0)
	# the boss, towering past the podium and facing the course; its gaze falls on four of the platforms
	boss = ArcadeBoss.new()
	boss.boss_pos = _w(fc + Vector3(0, -3.0, -32.0))
	boss.face_dir = _d(Vector3(0, 0, 1))
	add_child(boss)
	var tau: Array[float] = [1.16, 1.98, 2.88, 3.70, 4.49, 5.53, 6.31, 7.20, 8.0, 8.79, 9.71]
	var period: float = 6.5
	var targets: Array[int] = [2, 4, 6, 8]
	var fire_idx: Array[int] = []
	for k: int in targets:
		var ac: Vector3 = areas[k]["c"]
		var half: Vector2 = Vector2(0.9, 0.9) if lens[k] < 2.0 else Vector2(wid[k] * 0.5 + 0.4, minf(lens[k] * 0.5, 1.6) + 0.2)
		var fire_t: float = tau[k] - 2.3
		fire_idx.append(boss.add_attack(_w(ac), half if absf(fmod(_yaw, 180.0)) < 1.0 else Vector2(half.y, half.x), period, 1.1 - fire_t))
	_wait(func() -> bool:
		for j: int in targets.size():
			var tk: float = tau[targets[j]]
			if not boss.window_clear(fire_idx[j], Game.course_time, tk - 0.7, tk + 0.4 + 1.5):
				return false
		return true)
	prev = cp0
	for i2: int in areas.size():
		_hop(prev, areas[i2])
		prev = areas[i2]
	_hop(prev, fin, Vector3(0, 0, 0.6))
	r_walk(_w(fc + Vector3(0, 0, -0.9)))
	# the high-score podium: a frame round the gate and a glow on the floor
	_finish_light = OmniLight3D.new()
	_finish_light.light_color = ArcadeFx.YELLOW
	_finish_light.light_energy = 2.0
	_finish_light.omni_range = 16.0
	_finish_light.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(_finish_light)


func _finish_sequence() -> void:
	var cols: Array[Color] = [ArcadeFx.MAGENTA, ArcadeFx.CYAN, ArcadeFx.YELLOW, ArcadeFx.GREEN, ArcadeFx.ORANGE]
	for i: int in cols.size():
		var fw: GPUParticles3D = ArcadeFx.finale(cols[i], 80)
		fw.position = _finish_pos + _d(Vector3(-6.0 + 3.0 * float(i), 6.0 + float(i % 2) * 3.0, -2.0))
		add_child(fw)
		fw.restart()
		fw.emitting = true
	if boss != null:
		boss.finish_burst()
	# SOUND: arcade_finish - HIGH SCORE: a rising chiptune fanfare
	WorldAudio.at(self, "arcade_finish", _finish_pos + Vector3(0, 3.0, 0), 1.0, 120.0)
	if _finish_light != null:
		_finish_light.light_energy = 9.0
		create_tween().tween_property(_finish_light, "light_energy", 2.0, 1.6)
	await get_tree().create_timer(0.9).timeout

