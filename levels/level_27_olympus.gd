extends LevelBase
## 27. SKY CITADEL - the HARD marble course. A city of temples adrift on a sea of golden-hour cloud:
## cream marble and gold, fluted colonnades, aqueducts and tholoi, giant statues, floating rock
## islands and a low sun that never sets. No lightning anywhere: the gods are not watching, and the
## only sky that strikes is the sun itself, thrown across the courts by mirrors.
## Seventeen stages, sixteen checkpoints; it is hard through precision (eight-plus main-path jumps at
## 85-91% of max reach onto 1.2-1.5 m posts), timing and combinations, never through blind timing.
##
##  1 Cloud Landing     a stair of three floating posts and a beam, MANTLE the great gate
##  2 Crumbling Colonnade  five fluted columns that give way a beat after you land: keep moving
##  3 Helios Walk       two posts, a long beam through two SUN GATES (lasers), WALL RUN the temple wall
##  (the rest of the stages are listed here as they are built)
##
## Olympus mechanics (own scripts): OlympusChariot (a winged chariot you ride), OlympusColumn (crumbling
## column), OlympusMirror (a sun mirror that sweeps a blade of light), OlympusSpirit (a wind spirit's gust
## lane). Visuals: visual/olympus_{sky,decor,fx}.gd, olympus_marble.gdshader. Route variants for the bot:
## 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut. Every wait the bot makes
## holds for 1.5 s more, and every window also covers a 1.0 s human pause.

const GOLD := Color(1.0, 0.78, 0.28)
const MARBLE := Color(0.95, 0.92, 0.84)
const LAPIS := Color(0.28, 0.5, 0.86)
const SKY_BLUE := Color(0.55, 0.82, 1.0)

## The pause a hesitating human takes (the bot test pauses this long after every wait and checkpoint).
const PAUSE: float = 1.0
## Extra seconds of slack on every wait.
const SLACK: float = 1.5

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: OlympusDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable surface (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _floors: Array[Dictionary] = []
## Where each stage's frame starts (world), for scenery and dev tools.
var _stage_origin: Array[Vector3] = []


func _configure() -> void:
	theme_id = "olympus"
	music_track = "olympus"
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


## A walkable marble slab (local top centre `c`, sx across, sz along).
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


## A crumbling column whose capital is the landing (local top centre `c`).
func _crumb(c: Vector3, edge: float = 1.5, delay: float = 0.9) -> Dictionary:
	var col := OlympusColumn.new()
	col.edge = edge
	col.delay = delay
	col.position = _w(c)
	col.rotation.y = deg_to_rad(_yaw)
	add_child(col)
	_floors.append({"top": _w(c), "size": _sz(Vector3(edge, 0, edge)), "drop": 0.5, "col": true})
	return {"c": c, "hx": edge * 0.5, "hz": edge * 0.5}


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
	var fx: Array[GPUParticles3D] = OlympusFx.cp_burst(GOLD)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	# a brazier at each back corner and a gold standard behind the slab
	deco.brazier(_w(c + Vector3(-size * 0.5 + 0.35, 0, size * 0.5 - 0.35)), 0.8)
	deco.brazier(_w(c + Vector3(size * 0.5 - 0.35, 0, size * 0.5 - 0.35)), 0.8)
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: olympus_checkpoint - a stage banked: a golden lyre chord and a shimmer of light
			WorldAudio.at(self, "olympus_checkpoint", which.global_position, 0.9, 40.0)
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


## The sun mirror throws no blade at any time in [now + a, now + b].
static func _mirror_dark(m: OlympusMirror, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if m.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


## A MovingPlatform stays within `r` of its offset `at` (world offset) over [now + a, now + b].
static func _mover_at(m: MovingPlatform, at: Vector3, r: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if m.offset_at(Game.course_time + s).distance_to(at) > r:
			return false
		s += 0.05
	return true


# ---- the course ---------------------------------------------------------------------------------

## Testing aids (environment variables): build every stage but start at stage N / stop after stage N.
func _dev(name: String) -> int:
	var v: String = OS.get_environment(name)
	return int(v) if v != "" else 0


func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	deco = OlympusDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16]
	var dev_last: int = _dev("OLY_LAST")
	var dev_start: int = _dev("OLY_START")
	var last: int = stages.size() if (dev_last <= 0 or dev_last > stages.size()) else dev_last
	var starts: Array[int] = []
	var origins: Array[Vector3] = []
	_frame(Vector3.ZERO, yaws[0])
	for i: int in last:
		_next_yaw = yaws[i + 1]
		starts.append(route.size())
		origins.append(_o)
		_stage_origin.append(_o)
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	starts.append(route.size())
	origins.append(_o)
	if last == stages.size():
		_stage_17()
	else:
		# (dev) the finish right after the last stage built
		var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
		var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "main", 1.2)
		kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
		_finish_pos = _w(Vector3(0, 0, -9.5))
		_hop(cp0, fin)
		r_walk(_w(Vector3(0, 0, -9.8)))
	_surroundings()
	_marble_materials()
	if dev_start > 1:
		set_spawn(origins[dev_start - 1] + Vector3(0, 0.1, 0), yaws[dev_start - 1])
		route = route.slice(starts[dev_start - 1])


# ---- stage 1: Cloud Landing - a stair of floating posts, mantle the great gate ----------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(12, 2, 12), "main", 0.0, _yaw)
	_floors.append({"top": _w(Vector3.ZERO), "size": Vector3(12, 0, 12), "drop": 2.0})
	var start: Dictionary = _area(Vector3(0, 0, 0), 6.0, 6.0)
	var p1: Dictionary = _post(_ahead(start, 0.86, 0.0, 1.3), 1.3, 1.3)
	var p2: Dictionary = _post(_ahead(p1, 0.86, 0.6, 1.2, -0.4))
	var p3: Dictionary = _post(_ahead(p2, 0.86, 0.6, 1.2, 0.4))
	var beam: Dictionary = _blk(_ahead(p3, 0.86, 0.0, 3.0, -0.4), 1.2, 3.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 1.5
	# the gate: a mantle wall across a 1.6 m gap, its top 3.3 m above the beam
	var gate_top := Vector3(bc.x, bc.y + 3.3, front - 1.6 - 0.7)
	var gate: Dictionary = _ledge(gate_top, Vector3(2.6, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(gate, 0.86, 0.0, 5.0, -bc.x))
	_hop(start, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, beam, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(gate_top + Vector3(0, 0, 0.2)))
	_hop(gate, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_gate_dress(gate_top, 2.6, 9.0, 1.4)
	# the first sight of the citadel: a temple on a far island, a statue, an aqueduct, the sun ahead
	var yr: float = deg_to_rad(_yaw)
	deco.temple(_w(Vector3(-22.0, -4.0, -30.0)), OlympusDecor.turn(yr + 0.3), 6, 8, 5.0, true)
	deco.statue(_w(Vector3(17.0, -2.0, -26.0)), OlympusDecor.turn(yr + 2.8), 12.0, 1)
	deco.tholos(_w(Vector3(-12.0, -6.0, 6.0)), 4.2, 10, 4.2)
	return cp["c"]


## Dressing for a mantle wall built as a temple gate: flanking half-columns, a lapis frieze and a gold
## cornice on both broad faces (local top centre, size).
func _gate_dress(top: Vector3, w: float, h: float, d: float) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(_b, _w(top - Vector3(0, h * 0.5, 0)))
	add_child(n)
	var marble: StandardMaterial3D = Look.flat(MARBLE, 0.5)
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var col := Look.cylinder(0.26, h * 0.62, marble, Vector3(sx * (w * 0.5 - 0.32), h * 0.5 - h * 0.31 - 0.06, sz * (d * 0.5 + 0.1)), 0.22, 10)
			n.add_child(col)
		n.add_child(Look.box(Vector3(w * 0.66, 0.34, 0.05), Look.flat(LAPIS, 0.6), Vector3(0, h * 0.5 - 0.62, sz * (d * 0.5 + 0.03))))
		n.add_child(Look.box(Vector3(w + 0.2, 0.1, 0.1), Look.flat(GOLD, 0.35, 0.5, 0.4), Vector3(0, h * 0.5 - 0.28, sz * (d * 0.5 + 0.05))))


# ---- stage 2: Crumbling Colonnade - five columns that give way, keep moving --------------------------

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var prev: Dictionary = cp0
	var cols: Array[Dictionary] = []
	var pcts: Array[float] = [0.86, 0.86, 0.86, 0.86, 0.86]
	var dys: Array[float] = [0.6, 0.0, 0.6, 0.0, 0.6]
	var dxs: Array[float] = [0.0, 0.4, -0.4, 0.4, -0.4]
	for i: int in 5:
		prev = _crumb(_ahead(prev, pcts[i], dys[i], 1.5, dxs[i]))
		cols.append(prev)
	var land: Dictionary = _post(_ahead(prev, 0.86, 0.0, 1.6, -(prev["c"] as Vector3).x * 0.0), 1.6, 1.6, "alt")
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(land["c"] as Vector3).x))
	prev = cp0
	for c: Dictionary in cols:
		_hop(prev, c)
		prev = c
	_hop(prev, land)
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# a ruined colonnade drifting beside the route, an aqueduct far off
	var yr: float = deg_to_rad(_yaw)
	deco.colonnade(_w(Vector3(-9.0, -3.0, -16.0)), OlympusDecor.turn(yr + PI * 0.5), 6, 3.0, 6.0, 0.45)
	deco.aqueduct(_w(Vector3(18.0, -14.0, -30.0)), OlympusDecor.turn(yr + 0.5), 5, 5.0, 9.0)
	return cp["c"]


# ---- stage 3: Helios Walk - two posts, a beam through two sun gates, wall run the temple wall ---------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.86, 0.0, 1.2))
	var p2: Dictionary = _post(_ahead(p1, 0.86, 0.6, 1.2, 0.4))
	var beam: Dictionary = _blk(_ahead(p2, 0.86, 0.0, 14.0, -0.4), 1.2, 14.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 7.0
	var l1: LaserGate = kit.laser(_w(Vector3(bc.x, bc.y + 1.2, bc.z + 2.5)), Vector3(3.2, 2.4, 0.2), 5.0, 0.3, 0.0, _yaw)
	var l2: LaserGate = kit.laser(_w(Vector3(bc.x, bc.y + 1.2, bc.z - 2.5)), Vector3(3.2, 2.4, 0.2), 5.0, 0.3, fposmod(-0.12, 1.0), _yaw)
	l1.warn = 0.95
	l2.warn = 0.95
	_dress_laser(l1)
	_dress_laser(l2)
	_gate_tell(l1, Vector3(bc.x, bc.y, bc.z + 2.5))
	_gate_tell(l2, Vector3(bc.x, bc.y, bc.z - 2.5))
	# the temple wall: a wall-run panel on the right over the cloud, a landing post beyond
	var f: float = front
	kit.wallrun(_w(Vector3(bc.x + 2.3, bc.y + 1.2, f - 9.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _post(Vector3(bc.x - 0.6, bc.y, f - 22.5), 1.8, 2.4)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(bc.x - 0.6)))
	_wait(func() -> bool: return _dark(l1, 2.8, 3.3 + SLACK) and _dark(l2, 3.3, 3.9 + SLACK))
	_hop(cp0, p1)
	_hop(p1, p2)
	_hop(p2, beam, Vector3(0, 0, 6.2))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.6)))
	r_wallrun(_w(Vector3(bc.x + 0.3, bc.y, f + 0.35)), _w(Vector3(bc.x + 1.8, bc.y + 1.4, f - 3.6)),
		_w(Vector3(bc.x + 1.8, bc.y + 1.4, f - 14.5)), _w(Vector3(bc.x - 0.6, bc.y, f - 22.2)))
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the wall is a temple's flank: columns and a frieze behind the panel
	var yr: float = deg_to_rad(_yaw)
	deco.colonnade(_w(Vector3(bc.x + 3.6, bc.y - 0.2, f - 9.5)), OlympusDecor.turn(yr + PI * 0.5), 8, 2.2, 7.0, 0.4)
	deco.statue(_w(Vector3(-12.0, -3.0, f - 6.0)), OlympusDecor.turn(yr - 0.6), 10.0, 2)
	return cp["c"]


# ---- shared machine helpers (stages 4+) ----------------------------------------------------------------

## A wind-spirit gust lane (local centre, local size: x across / z along the path, push in local axes).
func _gust(center: Vector3, size: Vector3, push: Vector3, period: float, phase: float) -> OlympusSpirit:
	var g := OlympusSpirit.new()
	g.size = size
	g.push = push
	g.period = period
	g.phase = phase
	g.rotation.y = deg_to_rad(_yaw)
	g.position = _w(center)
	add_child(g)
	return g


## No gust anywhere in the lane over [now + a, now + b].
static func _calm(g: OlympusSpirit, a: float, b: float) -> bool:
	return g.is_calm_for(Game.course_time + a, b - a)


## A sun-glyph tablet at world `pos` (facing the stage heading) that rings before `left` reaches zero.
func _tell(pos: Vector3, left: Callable, k: float = 1.0, yaw_deg: float = 1000.0) -> void:
	var t := OlympusTell.new()
	t.left = left
	t.scale_k = k
	t.position = pos
	t.rotation.y = deg_to_rad(_yaw if yaw_deg > 999.0 else yaw_deg)
	add_child(t)


## Seconds until a crusher's slam (u = 0.50 of its cycle), as a function of the course clock.
static func _slam_left(t: float, c: Crusher) -> float:
	return fposmod(0.5 - fposmod(t / c.period + c.phase, 1.0), 1.0) * c.period


## Seconds until a piston's punch (u = 0.45).
static func _punch_left(t: float, p: Piston) -> float:
	return fposmod(0.45 - fposmod(t / p.period + p.phase, 1.0), 1.0) * p.period


## Fork signpost: two gilded posts with glowing caps and a strip on the floor in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		add_child(Look.cylinder(0.07, 2.2, Look.flat(MARBLE, 0.4), _w(p + Vector3(sx * 1.1, 1.1, 0)), 0.09, 8))
		var lamp := Look.sphere(0.2, Look.flat(col, 0.3, 0.0, 3.0), _w(p + Vector3(sx * 1.1, 2.35, 0)))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.5)), _sz(Vector3(1.2, 0.05, 0.25)), col)


## A winged chariot (local deck-top centre at its first stop, local deck size, local travel).
func _chariot(top: Vector3, size: Vector3, travel: Vector3, period: float, phase: float, dwell: float = 0.3) -> OlympusChariot:
	var c := OlympusChariot.new()
	c.size = _sz(size)
	var pts: Array[Vector3] = [Vector3.ZERO, _d(travel)]
	c.points = pts
	c.period = period
	c.phase = phase
	c.dwell = dwell
	c.facing = deg_to_rad(_yaw)
	c.position = _w(top) - Vector3(0, size.y * 0.5, 0)
	add_child(c)
	_floors.append({"top": _w(top), "size": _sz(Vector3(size.x, 0, size.z)), "drop": 0.8, "col": true})
	_floors.append({"top": _w(top + travel), "size": _sz(Vector3(size.x, 0, size.z)), "drop": 0.8, "col": true})
	return c


## Where a MovingPlatform rests at the start of its cycle (world), whatever the clock says.
static func _home(m: MovingPlatform) -> Vector3:
	return m.position - m.offset_at(Game.course_time)


## Bot: jump from `from` onto a moving platform's deck once `test` says it is docked.
func _board(from: Vector3, node: Node3D, off: Vector3, test: Callable) -> void:
	route.append({"kind": "h_jump", "from": from, "to_node": node, "to_local": off, "test": test})


## A bull ram: a piston shoving across the walkway. `top` = the ram's top centre when shut (local);
## `dir` = +1 punches towards +x, -1 towards -x.
func _ram(top: Vector3, dir: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.2)
	var p: Piston = kit.piston(_w(top), size, _yaw - 90.0 * dir, stroke, period, phase, 10.0)
	_dress_ram(_w(top), size, stroke, _yaw - 90.0 * dir)
	_tell(_w(top) + _b * Vector3(-dir * (size.z * 0.5 + 0.6), 0.9, 0.0), _punch_left.bind(p), 0.9)
	return p


## The ram's marble housing round the rod, its horned face: `top` / `yaw` as given to kit.piston (world).
func _dress_ram(top: Vector3, size: Vector3, stroke: float, yaw_deg: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var depth: float = stroke + 0.45
	var c: Vector3 = top - Vector3(0, size.y * 0.5, 0) + b * Vector3(0, 0, size.z * 0.5 + depth * 0.5 + 0.02)
	var n := Node3D.new()
	n.transform = Transform3D(b, c)
	add_child(n)
	var marble: StandardMaterial3D = Look.flat(MARBLE, 0.5)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.35, 0.5, 0.4)
	var h: float = size.y + 1.6
	var w: float = size.x + 0.8
	n.add_child(Look.box(Vector3(0.4, h, depth), marble, Vector3(-w * 0.5 + 0.2, 0, 0)))
	n.add_child(Look.box(Vector3(0.4, h, depth), marble, Vector3(w * 0.5 - 0.2, 0, 0)))
	n.add_child(Look.box(Vector3(w - 0.8, 0.78, depth), marble, Vector3(0, h * 0.5 - 0.39, 0)))
	n.add_child(Look.box(Vector3(w - 0.8, 0.78, depth), marble, Vector3(0, -h * 0.5 + 0.39, 0)))
	n.add_child(Look.box(Vector3(w + 0.12, 0.1, depth + 0.12), gold, Vector3(0, h * 0.5 + 0.05, 0)))
	# the bull's relief on the face: a lapis band and a pair of gold horns curving up
	for sy: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(w - 0.9, 0.5, 0.05), Look.flat(LAPIS, 0.6), Vector3(0, sy * (h * 0.5 - 0.39), -depth * 0.5 - 0.03)))
	for sx: float in [-1.0, 1.0]:
		var horn := Look.cylinder(0.0, 0.5, gold, Vector3(sx * (w * 0.5 - 0.15), h * 0.5 + 0.3, -depth * 0.5), 0.1, 8)
		horn.rotation.z = -sx * 0.45
		n.add_child(horn)


## The sun mirror (local floor position of its pedestal; headings in degrees, + = toward local +X).
func _mirror(pos: Vector3, ya: float, yb: float, period: float, on_time: float, phase: float, beam_len: float = 9.0) -> OlympusMirror:
	var m := OlympusMirror.new()
	m.beam_len = beam_len
	m.yaw_a = ya
	m.yaw_b = yb
	m.period = period
	m.on_time = on_time
	m.phase = phase
	m.sun_dir = OlympusSky.SUN_DIR
	m.rotation.y = deg_to_rad(_yaw)
	m.position = _w(pos)
	add_child(m)
	_floors.append({"top": _w(pos), "size": Vector3(1.2, 0, 1.2), "drop": 1.0, "col": true})
	return m


# ---- stage 4: Whistling Terrace - precision posts across two wind-spirit lanes ------------------------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var a1: Dictionary = _post(_ahead(cp0, 0.86, 0.0, 1.3), 1.3, 1.3)
	var a2: Dictionary = _post(_ahead(a1, 0.88, 0.6, 1.2, 0.4))
	var a3: Dictionary = _post(_ahead(a2, 0.86, 0.6, 1.2, -0.4))
	var a4: Dictionary = _post(_ahead(a3, 0.86, 0.0, 1.2, 0.4))
	var rest: Dictionary = _blk(_ahead(a4, 0.86, 0.6, 3.0, -0.4), 2.2, 3.0, "alt", 0.6)
	var cp: Dictionary = _cp(_ahead(rest, 0.86, 0.0, 5.0, -(rest["c"] as Vector3).x))
	# two lanes of wind: the first spirit crosses the first pair of posts, the second the next pair,
	# and the second sets off 2.0 s after the first (so a runner who sees one pass crosses the other)
	var period: float = 8.0
	var c1: Vector3 = ((a1["c"] as Vector3) + (a2["c"] as Vector3)) * 0.5
	var c2: Vector3 = ((a3["c"] as Vector3) + (a4["c"] as Vector3)) * 0.5
	var g1: OlympusSpirit = _gust(c1 + Vector3(0, 1.5, 0), Vector3(16.0, 7.0, 9.0), Vector3(26.0, 0, 0), period, 0.0)
	var g2: OlympusSpirit = _gust(c2 + Vector3(0, 1.5, 0), Vector3(16.0, 7.0, 9.0), Vector3(-26.0, 0, 0), period, fposmod(-2.0 / period, 1.0))
	# the bot crosses the first pair 0.0-2.4 s after it sets off and the second 2.0-4.6 s (+1.5 s slack,
	# which also covers the 1.0 s human pause)
	_wait(func() -> bool: return _calm(g1, -0.2, 2.4 + SLACK) and _calm(g2, 1.9, 4.6 + SLACK))
	_hop(cp0, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	_hop(a3, a4)
	_hop(a4, rest)
	_hop(rest, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the terrace: a tholos on the cloud, a laurel-crowned statue, a cloud-fall off a far island
	var yr: float = deg_to_rad(_yaw)
	deco.tholos(_w(Vector3(-13.0, -2.0, c1.z - 2.0)), 4.0, 10, 4.0)
	deco.statue(_w(Vector3(14.0, -3.0, c2.z - 6.0)), OlympusDecor.turn(yr + PI * 0.5 + 0.2), 14.0, 1)
	deco.island(_w(Vector3(-24.0, -5.0, c2.z - 14.0)), 12.0, 20.0, true, true)
	return cp["c"]


# ---- stage 5: Chariot Crossing (BRANCH) - ride the winged chariot | wall run and mantle the temple flank
# [shortcut: a chain of 94% leaps down the middle]

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# RIGHT (lapis): run the temple flank (wall run), a post, mantle the cella wall, drop to the merge
	kit.wallrun(_w(Vector3(5.7, 1.2, f0 - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, 0.0, f0 - 19.6), 2.0, 2.0)
	var case_top := Vector3(3.6, 3.3, f0 - 19.6 - 1.0 - 1.6 - 0.8)
	var case: Dictionary = _ledge(case_top, Vector3(2.6, 9.0, 1.6))
	var merge: Dictionary = _blk(_ahead(case, 0.84, -3.3, 3.0, -3.6), 11.0, 3.0)
	var mc: Vector3 = merge["c"]
	# LEFT (gold): the chariot, docked 0.9 m off the fork's front edge, flies 'travel' to dock 1 m off the merge
	var z0: float = f0 - 0.9 - 1.6
	var z_end: float = mc.z + 1.5 + 1.0 + 1.6
	var travel := Vector3(0, 0, z_end - z0)
	var car: OlympusChariot = _chariot(Vector3(-3.5, 0.0, z0), Vector3(2.8, 0.5, 3.2), travel, 13.0, 0.0, 0.3)
	# SHORTCUT: a line of small posts down the middle of the chasm (94% leaps)
	var hp: Dictionary = _area(fc, 5.5, 1.5)
	var hids: Array[Dictionary] = []
	var guard: int = 0
	while (hp["c"] as Vector3).z - float(hp["hz"]) - (mc.z + 1.5) > 5.4 and guard < 8:
		hp = _post(_ahead(hp, 0.93, 0.0, 1.2), 1.2, 1.2, "accent")
		hids.append(hp)
		guard += 1
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		var prev: Dictionary = _area(fc, 5.5, 1.5)
		for h: Dictionary in hids:
			_hop(prev, h)
			prev = h
		_hop(prev, merge, Vector3(0, 0, 0.4))
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, f0 + 0.9)))
		_wait(func() -> bool: return _mover_at(car, Vector3.ZERO, 0.2, 0.0, 2.4), _w(Vector3(-3.5, 0, f0 + 0.9)))
		_board(_w(Vector3(-3.5, 0, f0 + 0.35)), car, _d(Vector3(0, 0.25, 0.9)), func() -> bool: return _mover_at(car, Vector3.ZERO, 0.2, 0.0, 1.6))
		r_jump_from_ride(car, _home(car) + _d(travel), 0.3, _w(Vector3(-3.5, 0, mc.z + 0.9)), true, Vector3(0, 0.25, 0) + _d(Vector3(0, 0, -1.0)))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.0, 0, f0 + 0.35)), _w(Vector3(5.2, 1.4, f0 - 3.4)), _w(Vector3(5.2, 1.4, f0 - 12.6)), _w(Vector3(3.6, 0, f0 - 19.4)))
		r_mantle(_w(Vector3(3.6, 0, f0 - 19.6 - 0.65)), _w(case_top + Vector3(0, 0, 0.2)))
		_hop(case, merge, Vector3(3.6, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the forks' signposts, a temple flank behind the wall run, islands drifting in the chasm
	_sign(Vector3(-3.5, 0, fc.z + 1.2), GOLD)
	_sign(Vector3(3.6, 0, fc.z + 1.2), SKY_BLUE)
	var yr: float = deg_to_rad(_yaw)
	deco.colonnade(_w(Vector3(7.2, 0.8, f0 - 9.0)), OlympusDecor.turn(yr + PI * 0.5), 8, 2.0, 7.0, 0.4)
	deco.island(_w(Vector3(-16.0, -6.0, (f0 + mc.z) * 0.5)), 9.0, 16.0, true, true)
	deco.statue(_w(Vector3(14.0, -4.0, f0 - 22.0)), OlympusDecor.turn(yr + 0.3), 12.0, 2)
	return cp["c"]


# ---- stage 6: Aqueduct Run - posts, then the narrow aqueduct past two bull rams, mantle the arcade wall ----

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var a1: Dictionary = _post(_ahead(cp0, 0.86, 0.0, 1.3), 1.3, 1.3)
	var beam: Dictionary = _blk(_ahead(a1, 0.86, 0.6, 18.0, 0.4), 1.4, 18.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var bn: float = bc.z + 9.0
	# two bull rams in the aqueduct's piers shoving across the walkway, one from each side
	var r1: Piston = _ram(Vector3(bc.x - 0.7 - 0.6 - 0.15, bc.y + 1.35, bn - 6.0), 1.0, 2.6, 6.5, 0.0)
	var r2: Piston = _ram(Vector3(bc.x + 0.7 + 0.6 + 0.15, bc.y + 1.35, bn - 11.5), -1.0, 2.6, 6.5, fposmod(-0.6 / 6.5, 1.0))
	var wall_top := Vector3(bc.x, bc.y + 3.3, bn - 18.0 - 1.6 - 1.2)
	var wall: Dictionary = _ledge(wall_top, Vector3(3.0, 9.0, 2.4))
	var cp: Dictionary = _cp(_ahead(wall, 0.86, 0.0, 5.0, -bc.x))
	_hop(cp0, a1)
	_hop(a1, beam, Vector3(0, 0, 8.0))
	# stand at the beam head until both rams are home for the walk past them
	r_walk(_w(Vector3(bc.x, bc.y, bn - 2.0)))
	# the bot reaches ram 1 (4 m on) and ram 2 (9.5 m on) this long after the wait ends
	var t1: float = 0.65
	var t2: float = 1.25
	_wait(func() -> bool: return _ram_clear(r1, t1 - 0.4, t1 + 0.5 + SLACK) and _ram_clear(r2, t2 - 0.4, t2 + 0.5 + SLACK),
		_w(Vector3(bc.x, bc.y, bn - 2.0)))
	r_walk(_w(Vector3(bc.x, bc.y, bn - 18.0 + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, bn - 18.0 + 0.35)), _w(wall_top + Vector3(0, 0, 0.3)))
	_hop(wall, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the aqueduct itself: arches under the walkway, a far run of arches beyond
	var yr: float = deg_to_rad(_yaw)
	deco.aqueduct(_w(Vector3(bc.x, bc.y - 11.5, bc.z)), OlympusDecor.turn(yr + PI * 0.5), 4, 4.0, 8.0)
	deco.aqueduct(_w(Vector3(24.0, bc.y - 14.0, bc.z - 6.0)), OlympusDecor.turn(yr + 0.2), 5, 5.0, 11.0)
	return cp["c"]


# ---- stage 7: Press Hall - three platforms under falling pediments, mantle the cella wall --------------------

## A falling pediment: the crusher, dressed (a gilded gable on its top, a lapis band round it). The sun-glyph
## tablet on the lintel rings before each slam.
func _press(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var c: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.35, 0.5, 0.4)
	c.add_child(Look.box(Vector3(size.x + 0.12, 0.12, size.z + 0.12), gold, Vector3(0, size.y * 0.5 - 0.06, 0)))
	var gable := PrismMesh.new()
	gable.size = Vector3(size.x + 0.1, 0.5, size.z + 0.1)
	c.add_child(Look.mesh_node(gable, Look.flat(MARBLE, 0.5), Vector3(0, size.y * 0.5 + 0.25, 0)))
	var h: float = lift + size.y + 1.5
	_tell(_w(floor_c) + Vector3(0, h + 0.4, 0), _slam_left.bind(c), 1.6)
	return c


func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.86, 0.0, 1.3), 1.3, 1.3)
	var q1: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 2.2), 2.2, 2.2, "alt", 0.6)
	var q2: Dictionary = _blk(_ahead(q1, 0.86, 0.6, 2.2, 0.4), 2.2, 2.2, "alt", 0.6)
	var q3: Dictionary = _blk(_ahead(q2, 0.86, 0.6, 2.2, -0.4), 2.2, 2.2, "alt", 0.6)
	var q3c: Vector3 = q3["c"]
	var ledge_top := Vector3(q3c.x, q3c.y + 3.3, q3c.z - 1.1 - 1.6 - 1.3)
	var cella: Dictionary = _ledge(ledge_top, Vector3(3.0, 9.0, 2.6))
	var k1: Dictionary = _crumb(_ahead(cella, 0.86, 0.0, 1.5, 0.4))
	var p2: Dictionary = _post(_ahead(k1, 0.86, 0.6, 1.2, -0.4))
	var cp: Dictionary = _cp(_ahead(p2, 0.86, 0.0, 5.0, -(p2["c"] as Vector3).x))
	# three presses, one over each platform, each safe from the moment the bot could first be there to
	# well after it has left (+1.5 s slack, which covers the 1.0 s pause); staggered one hop apart
	var period: float = 6.4
	var los: Array[float] = [1.7, 2.7, 3.7]
	var his: Array[float] = [2.3 + SLACK, 3.3 + SLACK, 4.9 + SLACK]
	var presses: Array[Crusher] = []
	var plats: Array[Dictionary] = [q1, q2, q3]
	for i: int in 3:
		presses.append(_press((plats[i]["c"] as Vector3), Vector3(2.0, 1.0, 2.0), 5.2, period, fposmod(0.83 - los[i] / period, 1.0)))
	_wait(func() -> bool:
		for i: int in 3:
			if not _press_ok(presses[i], los[i], his[i]):
				return false
		return true)
	_hop(cp0, p1)
	_hop(p1, q1)
	_hop(q1, q2)
	_hop(q2, q3)
	r_walk(_w(Vector3(q3c.x, q3c.y, q3c.z - 1.1 + 0.9)))
	r_mantle(_w(Vector3(q3c.x, q3c.y, q3c.z - 1.1 + 0.35)), _w(ledge_top + Vector3(0, 0, 0.3)))
	_hop(cella, k1)
	_hop(k1, p2)
	_hop(p2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the cella wall behind the mantle is a temple front; a row of broken columns stands round the hall
	_gate_dress(ledge_top, 3.0, 9.0, 2.6)
	var yr: float = deg_to_rad(_yaw)
	deco.temple(_w(Vector3(-20.0, -6.0, q2["c"].z - 8.0)), OlympusDecor.turn(yr + 0.4), 5, 7, 5.0, true)
	deco.statue(_w(Vector3(14.0, -2.0, q1["c"].z - 6.0)), OlympusDecor.turn(yr - 0.5), 11.0, 1)
	return cp["c"]


# ---- stage 8: Cloud Gates (BRANCH) - a cloud gate that lifts you | a ladder of crumbling columns -------
# [shortcut: the small gate on the hanging post]

## A cloud gate: the warp portal ring in a frame of two marble pillars and a gilded lintel.
func _dress_portal(floor_pos: Vector3, yaw_deg: float, col: Color) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), floor_pos)
	add_child(n)
	var marble: StandardMaterial3D = Look.flat(MARBLE, 0.5)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.cylinder(0.2, 3.2, marble, Vector3(sx * 1.78, 1.6, 0), 0.17, 12))
		n.add_child(Look.box(Vector3(0.55, 0.16, 0.55), marble, Vector3(sx * 1.78, 0.08, 0)))
	n.add_child(Look.box(Vector3(4.2, 0.28, 0.4), marble, Vector3(0, 3.34, 0)))
	n.add_child(Look.box(Vector3(4.3, 0.08, 0.46), Look.flat(GOLD, 0.35, 0.5, 0.5), Vector3(0, 3.52, 0)))
	n.add_child(Look.box(Vector3(3.6, 0.06, 0.06), Look.flat(col, 0.3, 0.0, 2.4), Vector3(0, 3.18, -0.2)))
	# a little cloud puffed round each pillar's foot
	for sx2: float in [-1.0, 1.0]:
		n.add_child(Look.sphere(0.5, Look.cloud_material(), Vector3(sx2 * 1.78, 0.15, 0.1)))


func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# the two branches must end level with each other: dry-run both chains (pure maths), then shift the left
	var c1: Dictionary = _crumb(Vector3(4.0, 1.0, f0 - 5.0), 1.5)
	var c2: Dictionary = _crumb(_ahead(c1, 0.86, 1.0, 1.5, -0.3), 1.5)
	var c3: Dictionary = _crumb(_ahead(c2, 0.86, 1.0, 1.5, 0.3), 1.5)
	var c4: Dictionary = _crumb(_ahead(c3, 0.86, 1.0, 1.5, -0.3), 1.5)
	var arch: Dictionary = _blk(_ahead(c4, 0.86, 0.5, 3.0, 0.3), 1.6, 3.0, "alt", 0.6)
	var rb1: Dictionary = _post(_ahead(arch, 0.90, -1.5, 1.2, -0.3))
	var rb2: Dictionary = _post(_ahead(rb1, 0.90, -1.5, 1.2, 0.3))
	var hi_dry: Dictionary = _area(Vector3(-3.5, 4.5, f0 - 9.0), 0.6, 2.5)
	var la_dry: Dictionary = _area(_ahead(hi_dry, 0.90, -1.5, 1.2, 0.3), 0.6, 0.6)
	var la2_dry: Dictionary = _area(_ahead(la_dry, 0.90, -1.5, 1.2, -0.3), 0.6, 0.6)
	var dz: float = (rb2["c"] as Vector3).z - (la2_dry["c"] as Vector3).z
	# LEFT (gold): a cloud gate on the fork sends you up onto the high beam, then two drops
	var hi: Dictionary = _blk(Vector3(-3.5, 4.5, f0 - 9.0 + dz), 1.2, 5.0, "alt", 0.6)
	var door: WarpPortal = kit.portal(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, _w(Vector3(-3.5, 4.5, f0 - 7.2 + dz)), _yaw, 7.0)
	_dress_portal(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, GOLD)
	_dress_portal(_w(Vector3(-3.5, 4.5, f0 - 7.2 + dz)), _yaw, SKY_BLUE)
	var la: Dictionary = _post(_ahead(hi, 0.90, -1.5, 1.2, 0.3))
	var la2: Dictionary = _post(_ahead(la, 0.90, -1.5, 1.2, -0.3))
	var mc: Vector3 = _ahead(la2, 0.86, -1.5, 3.0)
	var merge: Dictionary = _blk(Vector3(0, 0, mc.z), 11.0, 3.0)
	# SHORTCUT: a small post hangs off the fork's front; the cloud gate on it opens onto the merge
	var sp: Dictionary = _post(_ahead(_area(fc, 5.5, 1.5), 0.93, 0.0, 1.2), 1.2, 1.2, "accent")
	var spc: Vector3 = sp["c"]
	var sdoor: WarpPortal = kit.portal(_w(spc + Vector3(0, 0, -0.3)), _yaw, _w(Vector3(0.5, 0, mc.z + 0.8)), _yaw, 6.0)
	_dress_portal(_w(spc + Vector3(0, 0, -0.3)), _yaw, GOLD)
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		_hop(_area(fc, 5.5, 1.5), sp, Vector3(0, 0, 0.35))
		r_portal(_w(spc + Vector3(0, 0, -0.6)), sdoor.exit_point())
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		r_portal(_w(Vector3(-3.5, 0, fc.z - 0.9)), door.exit_point())
		r_walk(_w(Vector3(-3.5, 4.5, f0 - 10.0 + dz)))
		_hop(hi, la)
		_hop(la, la2)
		_hop(la2, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(4.0, 0, fc.z + 0.6)))
		r_jump(_w(Vector3(4.0, 0, f0 + 0.35)), _w(c1["c"]))
		_hop(c1, c2)
		_hop(c2, c3)
		_hop(c3, c4)
		_hop(c4, arch)
		_hop(arch, rb1)
		_hop(rb1, rb2)
		_hop(rb2, merge, Vector3(4.0, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, fc.z + 1.2), GOLD)
	_sign(Vector3(4.0, 0, fc.z + 1.2), SKY_BLUE)
	var yr: float = deg_to_rad(_yaw)
	deco.tholos(_w(Vector3(-16.0, -3.0, f0 - 8.0)), 4.5, 10, 4.4)
	deco.statue(_w(Vector3(17.0, -1.0, f0 - 14.0)), OlympusDecor.turn(yr + 0.6), 13.0, 2)
	return cp["c"]


# ---- stage 9: Hall of Mirrors - a long court crossed by two sun mirrors' blades ---------------------------

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.86, 0.0, 1.3), 1.3, 1.3)
	var p2: Dictionary = _post(_ahead(p1, 0.86, 0.6, 1.2, 0.4))
	var court: Dictionary = _blk(_ahead(p2, 0.86, 0.0, 16.0, -0.4), 2.4, 16.0, "alt", 0.6)
	var cc: Vector3 = court["c"]
	var cn: float = cc.z + 8.0
	var p3: Dictionary = _post(_ahead(court, 0.86, 0.6, 1.2, 0.4))
	var cp: Dictionary = _cp(_ahead(p3, 0.86, 0.0, 5.0, -(p3["c"] as Vector3).x))
	# two sun mirrors on pedestals either side of the court, sweeping their blades across it in turn:
	# the left one over the first stretch, the right one over the second
	var period: float = 7.0
	var on_time: float = 1.4
	var mz1: float = cn - 5.0
	var mz2: float = cn - 11.0
	var m1: OlympusMirror = _mirror(Vector3(cc.x - 4.6, cc.y, mz1), 60.0, 120.0, period, on_time, 0.0, 8.0)
	var m2: OlympusMirror = _mirror(Vector3(cc.x + 4.6, cc.y, mz2), -60.0, -120.0, period, on_time, fposmod(-0.7 / period, 1.0), 8.0)
	# the bot is at the first stretch (4.5 m on) 0.9-1.9 s after it lands on the court, the second 1.5-2.5 s
	var t1: float = 0.9
	var t2: float = 1.6
	_hop(cp0, p1)
	_hop(p1, p2)
	_hop(p2, court, Vector3(0, 0, 7.0))
	r_walk(_w(Vector3(cc.x, cc.y, cn - 1.0)))
	_wait(func() -> bool: return _mirror_dark(m1, 0.0, t1 + 0.8 + SLACK) and _mirror_dark(m2, t2 - 0.7, t2 + 0.8 + SLACK),
		_w(Vector3(cc.x, cc.y, cn - 1.0)))
	r_walk(_w(Vector3(cc.x, cc.y, cn - 16.0 + 0.9)))
	_hop(court, p3, Vector3(0, 0, 0.2))
	_hop(p3, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# a court of mirrors: tall polished shields standing along both sides, statues at the far end
	var yr: float = deg_to_rad(_yaw)
	deco.colonnade(_w(Vector3(cc.x - 8.0, cc.y - 0.2, cc.z)), OlympusDecor.turn(yr + PI * 0.5), 7, 2.8, 6.0, 0.4)
	deco.colonnade(_w(Vector3(cc.x + 8.0, cc.y - 0.2, cc.z)), OlympusDecor.turn(yr + PI * 0.5), 7, 2.8, 6.0, 0.4)
	deco.statue(_w(Vector3(cc.x - 13.0, cc.y - 4.0, cc.z - 4.0)), OlympusDecor.turn(yr + 0.8), 12.0, 1)
	return cp["c"]


# ---- stage 10: The Stepping Stones - small landings, two of them crumbling [shortcut: a cloud bounce pad] --

## The pad strength whose angled launch (pitch degrees) first comes down at `dist` m ahead and `dy` higher.
func _pad_strength(pitch: float, dist: float, dy: float) -> float:
	var best: float = 30.0
	var s: float = 14.0
	while s <= 34.0:
		var v0 := Vector3(0.0, s * sin(deg_to_rad(pitch)), -s * cos(deg_to_rad(pitch)))
		var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, v0, dy)
		best = s
		if absf(land.z) >= dist:
			break
		s += 0.25
	return best


func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var s1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.2), 1.2, 1.2)
	var s2: Dictionary = _crumb(_ahead(s1, 0.86, 0.6, 1.4, 0.6), 1.4)
	var s3: Dictionary = _blk(_ahead(s2, 0.86, 0.0, 2.4, -0.6), 3.8, 2.4, "accent", 0.6)
	var s4: Dictionary = _post(_ahead(s3, 0.86, 0.6, 1.2, 0.7))
	var s5: Dictionary = _crumb(_ahead(s4, 0.86, -0.6, 1.4, -0.6), 1.4)
	var s6: Dictionary = _post(_ahead(s5, 0.86, 0.6, 1.2, 0.5))
	var s7: Dictionary = _post(_ahead(s6, 0.88, 0.6, 1.2, -0.5))
	var rest: Dictionary = _blk(_ahead(s7, 0.86, 0.0, 4.0, 0.0), 3.6, 4.0, "alt", 0.6)
	var rc: Vector3 = rest["c"]
	var cp: Dictionary = _cp(_ahead(rest, 0.86, 0.0, 5.0, -rc.x))
	# SHORTCUT: a cloud bounce pad on the left of the third stone throws you over the middle four
	# stones onto the rest platform (steer in the air; the landing is 3.6 x 4 m)
	var s3c: Vector3 = s3["c"]
	var pad_at := Vector3(s3c.x - 1.4, s3c.y, s3c.z + 0.2)
	var dist: float = pad_at.z - (rc.z + 0.5)
	var strength: float = _pad_strength(50.0, dist, rc.y - pad_at.y)
	var pad: BouncePad = kit.pad(_w(pad_at), strength, 50.0, _yaw, 0.7)
	_floors.append({"top": _w(pad_at), "size": Vector3(1.6, 0, 1.6), "drop": 0.6, "col": true})
	deco.cloud_puff(_w(pad_at + Vector3(0, -0.1, 0)))
	var steps: Array[Dictionary] = [s1, s2, s3, s4, s5, s6, s7]
	if route_variant == 2:
		_hop(cp0, s1)
		_hop(s1, s2)
		_hop(s2, s3)
		r_pad(pad.global_position, _w(rc + Vector3(0, 0, 0.5)))
	else:
		var prev: Dictionary = cp0
		for st: Dictionary in steps:
			_hop(prev, st)
			prev = st
		_hop(s7, rest)
	_hop(rest, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	var yr: float = deg_to_rad(_yaw)
	deco.island(_w(Vector3(-14.0, -4.0, (s4["c"] as Vector3).z)), 10.0, 18.0, true, true)
	deco.island(_w(Vector3(15.0, -7.0, (s2["c"] as Vector3).z - 6.0)), 8.0, 15.0, true, false)
	deco.temple(_w(Vector3(0.0, -22.0, (s5["c"] as Vector3).z - 30.0)), OlympusDecor.turn(yr), 6, 8, 5.0, true)
	return cp["c"]


# ---- stage 11: Pantheon Chimney - a cloud pad throws you up, a three-panel wall-run chimney, out onto the roof ---

func _chimney_panel(l: Vector3, x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(l + Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)


func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var padp: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 3.0), 3.0, 3.0, "main", 0.8)
	var pc: Vector3 = padp["c"]
	var strength: float = 21.0
	var arc: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, strength, -8.5), 6.0)
	var l := Vector3(pc.x, 6.0, pc.z + arc.z)
	var landing: Dictionary = _blk(l, 2.8, 2.8, "main", 0.8)
	var pad: BouncePad = kit.pad(_w(pc), strength, 0.0, _yaw, 1.0)
	deco.cloud_puff(_w(pc + Vector3(0, -0.1, 0)))
	# the chimney: three alternating panels climbing the inside of a temple drum, then the roof ledge
	_chimney_panel(l, 2.3, 1.2, -4.3, -10.8)
	_chimney_panel(l, -2.3, 6.0, -9.3, -17.3)
	_chimney_panel(l, 2.3, 9.0, -15.3, -23.3)
	var top: Dictionary = _ledge(l + Vector3(-0.75, 11.9, -26.8), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(_ahead(top, 0.85, 0.0, 5.0, 0.75))
	_hop(cp0, padp)
	r_pad(_w(pc), _w(l))
	r_walk(_w(l + Vector3(0, 0, 0.8)))
	r_wallrun(_w(l + Vector3(0.5, 0, -0.75)), _w(l + Vector3(1.7, 1.4, -5.4)), _w(l + Vector3(1.7, 1.4, -8.3)), _w(l + Vector3(-1.7, 5.5, -12.2)))
	r_wallrun(Vector3.ZERO, _w(l + Vector3(-1.7, 5.5, -12.2)), _w(l + Vector3(-1.7, 5.5, -15.2)), _w(l + Vector3(1.7, 8.5, -18.8)), true, true)
	r_wallrun(Vector3.ZERO, _w(l + Vector3(1.7, 8.5, -18.8)), _w(l + Vector3(1.7, 8.5, -20.2)), _w(l + Vector3(-0.75, 11.9, -25.4)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the drum: tall marble walls behind the panels with gold windows, an oculus of sun over the roof
	var marble: StandardMaterial3D = Look.flat(MARBLE, 0.5)
	add_child(Look.box(_sz(Vector3(0.6, 20.0, 22.0)), marble, _w(l + Vector3(3.1, 8.0, -13.0))))
	add_child(Look.box(_sz(Vector3(0.6, 18.0, 14.0)), marble, _w(l + Vector3(-3.1, 10.0, -13.0))))
	for w: Vector3 in [Vector3(2.78, 6.0, -12.2), Vector3(-2.78, 2.0, -18.0)]:
		var win := Look.box(_sz(Vector3(0.08, 2.4, 1.8)), Look.flat(Color(1.0, 0.82, 0.5), 0.3, 0.0, 1.8), _w(l + w))
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(win)
	deco.god_ray(_w(l + Vector3(0, 30.0, -20.0)), OlympusDecor.turn(deg_to_rad(_yaw), 0.5), 5.0, 30.0)
	deco.statue(_w(Vector3(-13.0, 3.0, pc.z - 6.0)), OlympusDecor.turn(deg_to_rad(_yaw) - 0.4), 12.0, 1)
	return cp["c"]


# ---- stage 12: Chariot Run (BRANCH) - the climbing chariot | two stacked mantles up the cella walls ---------

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	var fa: Dictionary = _area(Vector3(3.6, 0, fc.z), 1.5, 1.5)
	# RIGHT (lapis): a post, mantle a wall, mantle the wall behind it, hop up to the merge
	var pb: Dictionary = _post(_ahead(fa, 0.86, 0.0, 2.0), 2.0, 2.0)
	var pbc: Vector3 = pb["c"]
	var top_a := Vector3(3.6, pbc.y + 3.3, pbc.z - 1.0 - 1.6 - 1.2)
	var led_a: Dictionary = _ledge(top_a, Vector3(3.0, 9.0, 2.4))
	var top_b := Vector3(3.6, top_a.y + 3.3, top_a.z - 2.4)
	var led_b: Dictionary = _ledge(top_b, Vector3(3.0, 12.0, 2.4))
	var mcv: Vector3 = _ahead(led_b, 0.84, 1.4, 3.0, -3.6)
	var merge: Dictionary = _blk(Vector3(0, mcv.y, mcv.z), 11.0, 3.0)
	var mc: Vector3 = merge["c"]
	# LEFT (gold): the chariot climbs from the fork to the merge's level
	var z0: float = f0 - 0.9 - 1.6
	var z_end: float = mc.z + 1.5 + 1.0 + 1.6
	var travel := Vector3(0, mc.y, z_end - z0)
	var car: OlympusChariot = _chariot(Vector3(-3.5, 0.0, z0), Vector3(2.8, 0.5, 3.2), travel, 14.0, 0.0, 0.3)
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, f0 + 0.9)))
		_wait(func() -> bool: return _mover_at(car, Vector3.ZERO, 0.2, 0.0, 2.4), _w(Vector3(-3.5, 0, f0 + 0.9)))
		_board(_w(Vector3(-3.5, 0, f0 + 0.35)), car, _d(Vector3(0, 0.25, 0.9)), func() -> bool: return _mover_at(car, Vector3.ZERO, 0.2, 0.0, 1.6))
		r_jump_from_ride(car, _home(car) + _d(travel), 0.3, _w(Vector3(-3.5, mc.y, mc.z + 0.9)), true, Vector3(0, 0.25, 0) + _d(Vector3(0, 0, -1.0)))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		_hop(fa, pb)
		r_walk(_w(Vector3(3.6, 0, pbc.z - 1.0 + 0.9)))
		r_mantle(_w(Vector3(3.6, 0, pbc.z - 1.0 + 0.35)), _w(top_a + Vector3(0, 0, 0.3)))
		r_walk(_w(top_a + Vector3(0, 0, -1.2 + 0.9)))
		r_mantle(_w(top_a + Vector3(0, 0, -1.2 + 0.35)), _w(top_b + Vector3(0, 0, 0.3)))
		_hop(led_b, merge, Vector3(3.6, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, fc.z + 1.2), GOLD)
	_sign(Vector3(3.6, 0, fc.z + 1.2), SKY_BLUE)
	_gate_dress(top_a, 3.0, 9.0, 2.4)
	_gate_dress(top_b, 3.0, 12.0, 2.4)
	var yr: float = deg_to_rad(_yaw)
	deco.island(_w(Vector3(-17.0, -3.0, (f0 + mc.z) * 0.5)), 10.0, 18.0, true, true)
	deco.temple(_w(Vector3(18.0, 1.0, (f0 + mc.z) * 0.5 - 6.0)), OlympusDecor.turn(yr + PI * 0.5), 5, 7, 5.0, true)
	return cp["c"]


# ---- stage 13: Spirit Ridge - columns through a gust, then the mirror ridge ----------------------------

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var c1: Dictionary = _crumb(_ahead(cp0, 0.86, 0.6, 1.5))
	var c2: Dictionary = _crumb(_ahead(c1, 0.86, 0.0, 1.5, 0.4))
	var c3: Dictionary = _crumb(_ahead(c2, 0.86, 0.6, 1.5, -0.4))
	var rest: Dictionary = _blk(_ahead(c3, 0.86, 0.0, 2.6), 2.6, 2.6, "alt", 0.6)
	var rc: Vector3 = rest["c"]
	var ridge: Dictionary = _blk(_ahead(rest, 0.86, 0.0, 10.0), 1.6, 10.0, "alt", 0.6)
	var gc: Vector3 = ridge["c"]
	var gn: float = gc.z + 5.0
	var d1: Dictionary = _crumb(_ahead(ridge, 0.86, 0.6, 1.5, 0.4))
	var d2: Dictionary = _post(_ahead(d1, 0.86, 0.0, 1.2, -0.4))
	var cp: Dictionary = _cp(_ahead(d2, 0.86, 0.0, 5.0, -(d2["c"] as Vector3).x))
	var mid: Vector3 = ((c1["c"] as Vector3) + (c3["c"] as Vector3)) * 0.5
	var g1: OlympusSpirit = _gust(mid + Vector3(0, 1.5, 0), Vector3(16.0, 7.0, 13.0), Vector3(26.0, 0, 0), 9.0, 0.0)
	var m1: OlympusMirror = _mirror(Vector3(gc.x - 4.4, gc.y, gn - 5.0), 60.0, 120.0, 7.0, 1.4, 0.0, 8.0)
	_wait(func() -> bool: return _calm(g1, -0.2, 3.6 + SLACK))
	_hop(cp0, c1)
	_hop(c1, c2)
	_hop(c2, c3)
	_hop(c3, rest)
	r_walk(_w(Vector3(rc.x, rc.y, rc.z - 1.0)))
	_wait(func() -> bool: return _mirror_dark(m1, 0.0, 2.0 + SLACK), _w(Vector3(rc.x, rc.y, rc.z - 1.0)))
	_hop(rest, ridge, Vector3(0, 0, 4.0))
	r_walk(_w(Vector3(gc.x, gc.y, gn - 10.0 + 0.9)))
	_hop(ridge, d1)
	_hop(d1, d2)
	_hop(d2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	var yr: float = deg_to_rad(_yaw)
	deco.colonnade(_w(Vector3(gc.x + 7.0, gc.y - 0.2, gc.z)), OlympusDecor.turn(yr + PI * 0.5), 6, 2.6, 6.0, 0.4)
	deco.tholos(_w(Vector3(-15.0, -3.0, rc.z - 4.0)), 4.2, 10, 4.2)
	return cp["c"]


# ---- stage 14: Sun Stair - four landings climbing, three sun gates to run through on the beat -----------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var l1: Dictionary = _blk(_ahead(cp0, 0.86, 0.6, 3.0), 3.0, 3.0, "alt", 0.6)
	var l2: Dictionary = _blk(_ahead(l1, 0.86, 0.6, 3.0, 0.4), 3.0, 3.0, "alt", 0.6)
	var l3: Dictionary = _blk(_ahead(l2, 0.86, 0.0, 3.0, -0.4), 3.0, 3.0, "alt", 0.6)
	var l4: Dictionary = _blk(_ahead(l3, 0.86, 0.6, 3.0, 0.4), 3.0, 3.0, "alt", 0.6)
	var land: Dictionary = _post(_ahead(l4, 0.86, 0.6, 1.4, -0.4), 1.4, 1.4)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(land["c"] as Vector3).x))
	var period: float = 4.4
	var gates: Array[LaserGate] = []
	var plats: Array[Dictionary] = [l1, l2, l4]
	var pass_t: Array[float] = [1.3, 2.4, 4.6]
	for i: int in 3:
		var pc: Vector3 = plats[i]["c"]
		var g: LaserGate = kit.laser(_w(pc + Vector3(0, 1.2, 0.0)), Vector3(3.2, 2.4, 0.2), period, 0.3, fposmod(0.3 - (pass_t[i] - 0.6) / period, 1.0), _yaw)
		g.warn = 0.95
		_dress_laser(g)
		_gate_tell(g, pc)
		gates.append(g)
	_wait(func() -> bool:
		for i: int in 3:
			if not _dark(gates[i], pass_t[i] - 0.5, pass_t[i] + 0.5 + SLACK):
				return false
		return true)
	_hop(cp0, l1, Vector3(0, 0, 1.0))
	_hop(l1, l2, Vector3(0, 0, 1.0))
	_hop(l2, l3)
	_hop(l3, l4, Vector3(0, 0, 1.0))
	_hop(l4, land)
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	var yr: float = deg_to_rad(_yaw)
	deco.statue(_w(Vector3(-11.0, -2.0, (l2["c"] as Vector3).z)), OlympusDecor.turn(yr - 0.6), 11.0, 1)
	deco.aqueduct(_w(Vector3(14.0, -12.0, (l3["c"] as Vector3).z - 10.0)), OlympusDecor.turn(yr + 0.4), 5, 5.0, 10.0)
	return cp["c"]


## A sun-glyph tablet beside a sun gate that rings before the beam fires.
func _gate_tell(g: LaserGate, pc: Vector3) -> void:
	_tell(_w(pc + Vector3(-2.2, 0.0, 0.0)), func(t: float) -> float: return g.time_until_on(t), 0.8)


# ---- stage 15: Sky Colonnade (BRANCH) - the mirror walk | two chained mirror-wall runs ----------------------
# [shortcut: a 4.1 m mantle up the broken column, then its narrow cornice]

func _e(pct: float, dy: float) -> float:
	var m: float = pct * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	return float(k) * 0.2 - 0.03


func _stage_15() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# RIGHT (lapis): run the right wall, kick across to the left one, run it, kick to a post
	kit.wallrun(_w(Vector3(6.1, 1.2, f0 - 7.0)), Vector3(12.0, 6.5, 0.6), _yaw + 90.0)
	kit.wallrun(_w(Vector3(1.5, 3.6, f0 - 17.5)), Vector3(9.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, -0.6, f0 - 27.6), 1.6, 1.6)
	var pb2: Dictionary = _post(_ahead(pb, 0.88, 0.0, 1.2))
	var mcv: Vector3 = _ahead(pb2, 0.86, 0.0, 3.0, -3.6)
	var merge: Dictionary = _blk(Vector3(0, mcv.y, mcv.z), 11.0, 3.0)
	var mz: float = mcv.z
	# LEFT (gold): a long beam walked past three sun mirrors; its length is set so both branches meet
	var pa_z: float = mz + 1.5 - 0.35 + _e(0.86, 0.0) + 0.6
	var beam_front: float = pa_z + 0.6 - 0.35 + _e(0.88, -0.6)
	var beam_near: float = f0 + 0.35 - _e(0.86, 0.0)
	var blen: float = beam_near - beam_front
	var beam: Dictionary = _blk(Vector3(-3.5, 0.0, (beam_near + beam_front) * 0.5), 1.4, blen, "alt", 0.6)
	var pa: Dictionary = _post(Vector3(-3.5, -0.6, pa_z))
	# the three mirrors, alternate sides, each over its own third of the walk
	var period: float = 7.4
	var mirrors: Array[OlympusMirror] = []
	var arr_t: Array[float] = []
	for i: int in 3:
		var mzz: float = beam_near - blen * (0.2 + 0.3 * float(i))
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var mr: OlympusMirror = _mirror(Vector3(-3.5 + side * 4.6, 0.0, mzz), 90.0 * (-side) + 30.0 * side, 90.0 * (-side) - 30.0 * side, period, 1.3, fposmod(-0.5 * float(i) / period, 1.0), 8.0)
		mirrors.append(mr)
		arr_t.append(maxf((beam_near - mzz - 1.0 - 2.6) / 9.0, 0.0) + 0.1)
	# SHORTCUT: the broken column (a 4.1 m mantle) and its narrow cornice, a hop to the merge
	var col: Dictionary = _ledge(Vector3(0, 4.1, f0 - 0.9), Vector3(1.4, 12.0, 1.8), "accent")
	var cornice: Dictionary = _blk(Vector3(0, 4.1, f0 - 1.8 - 6.0 - 0.4), 1.0, 12.0, "accent", 0.5)
	var n2: Vector3 = _ahead(cornice, 0.88, 0.0, 0.0)
	var l2: float = n2.z - (mz + 1.5 + 4.5)
	var cornice2: Dictionary = _blk(Vector3(0, 4.1, n2.z - l2 * 0.5), 1.0, l2, "accent", 0.5)
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
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
		_hop(_area(Vector3(-3.5, 0, fc.z), 1.5, 1.5), beam, Vector3(0, 0, blen * 0.5 - 0.9))
		_wait(func() -> bool:
			for i: int in 3:
				if not _mirror_dark(mirrors[i], arr_t[i] - 0.1, arr_t[i] + 0.9 + SLACK):
					return false
			return true, _w(Vector3(-3.5, 0, beam_near - 1.0)))
		r_walk(_w(Vector3(-3.5, 0, beam_front + 0.9)))
		_hop(beam, pa)
		_hop(pa, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.2, 0, f0 + 0.35)), _w(Vector3(5.6, 1.4, f0 - 3.2)), _w(Vector3(5.6, 1.4, f0 - 10.6)), _w(Vector3(2.0, 4.4, f0 - 14.4)))
		r_wallrun(Vector3.ZERO, _w(Vector3(2.0, 4.4, f0 - 14.4)), _w(Vector3(2.0, 4.4, f0 - 19.6)), _w(Vector3(3.6, mcv.y, f0 - 27.4)), true, true)
		_hop(pb, pb2)
		_hop(pb2, merge, Vector3(3.6, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, fc.z + 1.2), GOLD)
	_sign(Vector3(3.6, 0, fc.z + 1.2), SKY_BLUE)
	var yr: float = deg_to_rad(_yaw)
	deco.colonnade(_w(Vector3(7.0, 1.2, f0 - 7.0)), OlympusDecor.turn(yr + PI * 0.5), 6, 2.2, 7.0, 0.4)
	deco.statue(_w(Vector3(-13.0, -3.0, f0 - 12.0)), OlympusDecor.turn(yr + 0.5), 12.0, 2)
	return cp["c"]


# ---- stage 16: Gate of Dawn - crumbling steps, a short chariot hop, the longest leap, the porch mantle -------

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var c1: Dictionary = _crumb(_ahead(cp0, 0.86, 0.6, 1.5))
	var c2: Dictionary = _crumb(_ahead(c1, 0.86, 0.0, 1.5, 0.4))
	var d0: Dictionary = _blk(_ahead(c2, 0.86, 0.0, 3.0, -0.4), 3.0, 3.0, "alt", 0.6)
	var d0c: Vector3 = d0["c"]
	var f0: float = d0c.z - 1.5
	var z0: float = f0 - 0.9 - 1.6
	var z_end: float = z0 - 14.0
	var d1c := Vector3(d0c.x, d0c.y, z_end - 1.6 - 1.0 - 1.5)
	var d1: Dictionary = _blk(d1c, 3.0, 3.0, "alt", 0.6)
	var car: OlympusChariot = _chariot(Vector3(d0c.x, d0c.y, z0), Vector3(2.8, 0.5, 3.2), Vector3(0, 0, -14.0), 11.0, 0.0, 0.3)
	var far: Dictionary = _post(_ahead(d1, 0.88, 0.0, 1.2, 0.0))
	var fz: Vector3 = far["c"]
	var porch_top := Vector3(fz.x, fz.y + 3.3, fz.z - 0.6 - 1.4 - 1.3)
	var porch: Dictionary = _ledge(porch_top, Vector3(3.0, 9.0, 2.6))
	var p2: Dictionary = _post(_ahead(porch, 0.86, 0.0, 1.4, 0.4), 1.4, 1.4)
	var cp: Dictionary = _cp(_ahead(p2, 0.86, 0.0, 5.0, -(p2["c"] as Vector3).x))
	_hop(cp0, c1)
	_hop(c1, c2)
	_hop(c2, d0)
	r_walk(_w(Vector3(d0c.x, d0c.y, f0 + 0.9)))
	_wait(func() -> bool: return _mover_at(car, Vector3.ZERO, 0.2, 0.0, 2.4), _w(Vector3(d0c.x, d0c.y, f0 + 0.9)))
	_board(_w(Vector3(d0c.x, d0c.y, f0 + 0.35)), car, _d(Vector3(0, 0.25, 0.9)), func() -> bool: return _mover_at(car, Vector3.ZERO, 0.2, 0.0, 1.6))
	r_jump_from_ride(car, _home(car) + _d(Vector3(0, 0, -14.0)), 0.3, _w(d1c + Vector3(0, 0, 0.9)), true, Vector3(0, 0.25, 0) + _d(Vector3(0, 0, -1.0)))
	_hop(d1, far)
	r_mantle(_w(Vector3(fz.x, fz.y, fz.z - 0.3)), _w(porch_top + Vector3(0, 0, 0.3)))
	_hop(porch, p2)
	_hop(p2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_gate_dress(porch_top, 3.0, 9.0, 2.6)
	var yr: float = deg_to_rad(_yaw)
	deco.temple(_w(Vector3(-20.0, -2.0, d0c.z - 10.0)), OlympusDecor.turn(yr + 0.3), 6, 8, 5.5, true)
	deco.statue(_w(Vector3(15.0, -1.0, d1c.z)), OlympusDecor.turn(yr - 0.4), 14.0, 1)
	return cp["c"]


# ---- stage 17: THE SUN TEMPLE STAIR - the set piece. Eight landings climb to the sun disc while four giant
# statues turn and sweep their hand-mirrors' blades across the stair; the finish is the gate in the sun.

var _finish_light: OmniLight3D


## Dress a sun mirror as a giant statue: robed legs below, and a torso, head and outstretched arm
## holding a gilded hand-mirror that turn with the blade (on the mirror's pivot).
func _statue_mirror(m: OlympusMirror) -> void:
	var marble: StandardMaterial3D = Look.flat(MARBLE, 0.5)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.35, 0.5, 0.45)
	m.add_child(Look.cylinder(1.0, 2.0, marble, Vector3(0, 1.0, 0), 0.75, 14))
	m.add_child(Look.box(Vector3(2.4, 0.3, 2.4), Look.flat(Color(0.84, 0.76, 0.64), 0.7), Vector3(0, 0.15, 0)))
	var p: Node3D = m.pivot
	p.add_child(Look.cylinder(0.82, 2.0, marble, Vector3(0, 0.9, 0), 0.7, 14))
	p.add_child(Look.cylinder(0.3, 0.5, marble, Vector3(0, 2.15, 0), -1.0, 10))
	p.add_child(Look.sphere(0.5, marble, Vector3(0, 2.75, 0)))
	p.add_child(Look.cylinder(0.52, 0.34, gold, Vector3(0, 3.0, 0), 0.46, 12))
	p.add_child(Look.box(Vector3(0.12, 0.4, 0.8), gold, Vector3(0, 3.3, 0)))
	p.add_child(Look.box(Vector3(2.1, 0.5, 0.6), marble, Vector3(0, 1.75, 0.0)))
	var arm := Look.box(Vector3(0.38, 0.38, 2.7), marble, Vector3(0, 0.0, -1.75))
	p.add_child(arm)
	var disc := Look.cylinder(0.75, 0.1, Look.flat(Color(1.0, 0.95, 0.8), 0.1, 1.0, 0.5), Vector3(0, 0.1, -3.15), -1.0, 24)
	disc.rotation.x = PI * 0.5
	p.add_child(disc)
	var rim := Look.cylinder(0.82, 0.08, gold, Vector3(0, 0.1, -3.1), -1.0, 24)
	rim.rotation.x = PI * 0.5
	p.add_child(rim)


func _stage_17() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var lands: Array[Dictionary] = []
	var prev: Dictionary = cp0
	var pcts: Array[float] = [0.84, 0.86, 0.84, 0.86, 0.84, 0.86, 0.84, 0.86]
	for i: int in 8:
		var dx: float = 0.0 if i == 0 else (0.4 if i % 2 == 1 else -0.4)
		prev = _blk(_ahead(prev, pcts[i], 1.0, 2.6, dx), 3.2, 2.6, "main", 0.8)
		lands.append(prev)
	var last: Vector3 = lands[7]["c"]
	var fin: Dictionary = _blk(_ahead(lands[7], 0.84, 1.0, 6.0, -last.x), 6.0, 6.0, "goal", 1.0)
	var fc: Vector3 = fin["c"]
	kit.finish(_w(fc + Vector3(0, 0, -1.0)), _yaw)
	_finish_pos = _w(fc + Vector3(0, 0, -1.0))
	# four statues, each turning its hand-mirror's blade across two landings
	var period: float = 6.6
	var on_time: float = 1.5
	var stat: Array[OlympusMirror] = []
	var los: Array[float] = []
	var his: Array[float] = []
	for k: int in 4:
		var a: Vector3 = lands[2 * k]["c"]
		var b: Vector3 = lands[2 * k + 1]["c"]
		var side: float = -1.0 if k % 2 == 0 else 1.0
		var mid := Vector3(side * 5.6, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
		_blk(mid + Vector3(0, 0, 0), 2.8, 2.8, "alt", 0.8)
		var lo: float = 0.1 + 0.82 * float(2 * k + 1) - 0.8
		var hi: float = 0.1 + 0.82 * float(2 * k + 2) + 0.6 + SLACK
		var m: OlympusMirror = _mirror(mid, 90.0 * (-side) + 42.0 * side, 90.0 * (-side) - 42.0 * side, period, on_time,
			fposmod((on_time + 0.2 - lo) / period, 1.0), 8.5)
		m.plain_head = false
		m.head_h = 2.2
		m.min_range = 3.3
		m.beam_h = 3.6
		m.half_width = 0.55
		stat.append(m)
		los.append(lo)
		his.append(hi)
	_wait(func() -> bool:
		for k: int in 4:
			if not _mirror_dark(stat[k], los[k], his[k]):
				return false
		return true)
	var pv: Dictionary = cp0
	for l: Dictionary in lands:
		_hop(pv, l)
		pv = l
	_hop(pv, fin, Vector3(0, 0, 1.0))
	r_walk(_w(fc + Vector3(0, 0, -1.0)))
	# build the statues' bodies after the mirrors exist (they need their pivots)
	for m2: OlympusMirror in stat:
		_statue_mirror(m2)
	# the temple at the top: the great sun disc rising behind a colonnade, braziers up the stair
	var yr: float = deg_to_rad(_yaw)
	deco.sun_disc(_w(fc + Vector3(0, 11.0, -9.0)), OlympusDecor.turn(yr + PI), 9.0, 24)
	deco.temple(_w(fc + Vector3(0, -0.2, -8.0)), OlympusDecor.turn(yr), 6, 5, 7.0, true)
	OlympusFx.halo(self, _w(fc + Vector3(0, 11.0, -8.5)), 10.5, 90, GOLD, Vector3(0, 0, 1))
	OlympusFx.motes(self, _w(fc + Vector3(0, 5.0, -2.0)), _sz(Vector3(8.0, 6.0, 8.0)), 80)
	for l2: Dictionary in lands:
		var lc: Vector3 = l2["c"]
		deco.brazier(_w(lc + Vector3(-1.4, 0, 0.3)), 0.7)
		deco.brazier(_w(lc + Vector3(1.4, 0, 0.3)), 0.7)
	_finish_light = OmniLight3D.new()
	_finish_light.light_color = Color(1.0, 0.82, 0.5)
	_finish_light.light_energy = 2.0
	_finish_light.omni_range = 18.0
	_finish_light.position = _finish_pos + Vector3(0, 5.0, 0)
	add_child(_finish_light)
	for k2: int in 4:
		deco.statue(_w(Vector3((-1.0 if k2 % 2 == 0 else 1.0) * 16.0, lands[k2 * 2]["c"].y - 3.0, lands[k2 * 2]["c"].z)), OlympusDecor.turn(yr + 0.3 * float(k2)), 12.0, 1)


# ---- live effects -----------------------------------------------------------------------------------

## The sun blazes: gold and light fountain out of the disc over the gate.
func _finish_sequence() -> void:
	var cols: Array[Color] = [GOLD, Color(1.0, 0.95, 0.8), SKY_BLUE, GOLD, Color(1.0, 0.95, 0.8)]
	for i: int in cols.size():
		var fw: GPUParticles3D = OlympusFx.finale(cols[i], 80)
		fw.position = _finish_pos + Vector3(-6.0 + 3.0 * float(i), 6.0 + float(i % 2) * 3.0, -2.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	var fx: Array[GPUParticles3D] = OlympusFx.cp_burst(GOLD)
	for p2: GPUParticles3D in fx:
		p2.position = _finish_pos + Vector3(0, 0.6, 0)
		add_child(p2)
		p2.restart()
		p2.emitting = true
	# SOUND: olympus_finish - the sun temple opens: a swell of brass and choir
	WorldAudio.at(self, "olympus_finish", _finish_pos + Vector3(0, 3.0, 0), 1.0, 120.0)
	if _finish_light != null:
		_finish_light.light_energy = 9.0
		var tw: Tween = create_tween()
		tw.tween_property(_finish_light, "light_energy", 2.0, 1.6)
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
	_env.sky = OlympusSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.92, 0.84, 0.82)
	_env.ambient_light_energy = 0.78
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(1.0, 0.82, 0.62)
	_env.fog_density = 0.0013
	_env.fog_aerial_perspective = 0.5
	_env.fog_sky_affect = 0.2
	_env.fog_sun_scatter = 0.35
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.06
	# a warm low key light from the sun ahead, and a cool sky-blue fill from behind and above
	_sun.light_color = Color(1.0, 0.85, 0.6)
	_sun.light_energy = 1.7
	_sun.rotation_degrees = Vector3(-22, 200, 0)
	_fill.light_color = Color(0.62, 0.72, 1.0)
	_fill.light_energy = 0.38
	_fill.rotation_degrees = Vector3(-35, 20, 0)


# ---- machine dressing ---------------------------------------------------------------------------

## A sun gate: a gilded pillar either side of a laser, each topped with a sun disc on a stand.
func _dress_laser(g: LaserGate) -> void:
	var post_h: float = maxf(g.size.y + 0.8, 1.2)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.3, 0.7, 0.5)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.95, 0.8)
	glass.metallic = 1.0
	glass.roughness = 0.08
	glass.emission_enabled = true
	glass.emission = GOLD
	glass.emission_energy_multiplier = 0.6
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (g.size.x * 0.5 + 0.18)
		g.add_child(Look.box(Vector3(0.5, 0.12, 0.5), gold, Vector3(x, post_h * 0.5 + 0.06, 0)))
		var disc := Look.cylinder(0.34, 0.05, glass, Vector3(x, post_h * 0.5 + 0.5, 0), -1.0, 20)
		disc.rotation = Vector3(PI * 0.5, 0.0, sx * 0.4)
		g.add_child(disc)
		for i: int in 8:
			var a: float = TAU * float(i) / 8.0
			var ray := Look.box(Vector3(0.05, 0.16, 0.03), gold, Vector3(cos(a) * 0.42, post_h * 0.5 + 0.5 + sin(a) * 0.42, 0))
			ray.rotation.z = a - PI * 0.5
			g.add_child(ray)


# ---- scenery ----------------------------------------------------------------------------------------

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
	# under every floor: a broken column dangling under a small one, a stepped keel under a big one -
	# never where it would poke through anything walkable below
	for f: Dictionary in _floors:
		if f.has("col"):
			continue
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		var under: Vector3 = t - Vector3(0, float(f["drop"]), 0)
		if maxf(s.x, s.z) <= 2.7:
			var length: float = rng.randf_range(2.5, 5.0)
			if _box_free(under - Vector3(0, length * 0.5 + 1.5, 0), Vector3(0.5, length * 0.5 + 1.5, 0.5), f):
				deco.hang_column(under, minf(s.x, s.z) * 0.18, length)
		elif minf(s.x, s.z) >= 2.9:
			var depth: float = clampf(minf(s.x, s.z) * 0.6, 1.5, 5.0)
			if _box_free(under - Vector3(0, depth * 0.5, 0), Vector3(s.x * 0.5, depth * 0.5, s.z * 0.5), f):
				deco.keel(under, s.x, s.z, depth)
	# ambient life along the route: dust motes rising, feathers tumbling, wisps of cloud sliding by
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 8.0, absf(here.z - prev.z) * 0.5 + 12.0)
		OlympusFx.motes(self, c3, ext, 90)
		OlympusFx.feathers(self, c3 + Vector3(0, 5.0, 0), ext, 24)
		OlympusFx.wisps(self, c3 - Vector3(0, 9.0, 0), ext * Vector3(1.0, 0.5, 1.0), 8)
	# far scenery round the course: temples, tholoi, statues, aqueducts and islands, kept well clear
	var placed: int = 0
	var tries: int = 0
	while placed < 34 and tries < 900:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 120.0, hi.x + 120.0), rng.randf_range(lo.y - 40.0, hi.y + 25.0), rng.randf_range(lo.z - 120.0, hi.z + 120.0))
		if not _clear_of(p, pts, 36.0):
			continue
		var roll: float = rng.randf()
		var yaw: float = rng.randf() * TAU
		if roll < 0.24:
			var tn: Node3D = deco.island(p, rng.randf_range(10.0, 18.0), rng.randf_range(14.0, 26.0), true, rng.randf() < 0.5)
			tn.rotation.y = yaw
			if rng.randf() < 0.6:
				deco.temple(p + Vector3(0, 0.1, 0), OlympusDecor.turn(yaw), rng.randi_range(4, 6), rng.randi_range(6, 8), rng.randf_range(4.5, 6.0))
		elif roll < 0.42:
			deco.tholos(p, rng.randf_range(3.5, 5.5), 10, rng.randf_range(3.8, 5.0))
			deco.island(p + Vector3(0, -0.4, 0), 10.0, 18.0, false, false)
		elif roll < 0.58:
			deco.statue(p, OlympusDecor.turn(yaw), rng.randf_range(14.0, 24.0), rng.randi_range(0, 2))
		elif roll < 0.74:
			deco.aqueduct(p, OlympusDecor.turn(yaw), rng.randi_range(4, 7), 5.0, rng.randf_range(10.0, 14.0))
		else:
			deco.colonnade(p, OlympusDecor.turn(yaw), rng.randi_range(5, 9), 3.2, rng.randf_range(6.0, 9.0), 0.5)
		placed += 1
	# drifting cloud banks below and around, some of them above the floor of the world
	for i2: int in 46:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(0.0, maxf(span.x, span.z) * 0.5 + 140.0)
		kit.cloud(Vector3(mid.x + cos(a) * r, rng.randf_range(lo.y - 70.0, hi.y + 20.0), mid.z + sin(a) * r), rng.randf_range(1.5, 3.4))


## Swap every walkable surface to the veined marble shader (same colours and sizes).
func _marble_materials() -> void:
	var sh: Shader = preload("res://visual/olympus_marble.gdshader")
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = sh
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r
