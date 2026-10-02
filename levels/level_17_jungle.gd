extends LevelBase
## 17. JUNGLE TEMPLE - overgrown ruins deep in a rainforest. Eighteen stages, each ending on a
## checkpoint: up out of the river on its stepping stones and log rafts, past the falls, through the
## dart gallery and the glyph gate, up into the canopy on flower pads and vines, through the sun court
## and the idol hall, down the great ramp ahead of the rolling boulder, across the gorge on the vines,
## over the moat, and up the five tiers of the step pyramid to the altar on its summit.
##
##  1 River Landing    stepping stones out of the river, MANTLE the broken stair
##  2 Log Rafts        ride a raft up the river, a pier, a second raft
##                     [shortcut: a line of mossy pillar tops along the bank - 1 m landings, no rafts]
##  3 Falls Pool       BRANCH: swing across the plunge pool on a VINE | WALL RUN the wet cliff under the falls
##  4 Dart Gallery     a sunken corridor of DART TRAPS (carved faces), then a crumbling stone bridge
##  5 Glyph Gate       step on the glyph plate and race over the spike pit before the gate shuts
##  6 Canopy           giant flower pads up into the canopy, two VINE swings branch to branch
##  7 Root Stair       MANTLE the great root, WALL RUN the trunk, MANTLE onto the temple balcony
##  8 Sun Court        BRANCH: through the jade sun-beams (LASERS) | MANTLE the colonnade, hop the column
##                     tops [shortcut: a 79% leap to the idol's mouth (PORTAL), out past the beams]
##  9 Stone Faces      a narrow beam over the ravine, stone tongues (PISTONS) shoving across it, crumbling slabs
## 10 Idol Hall        under the ceiling blocks (CRUSHERS), a dart lane, MANTLE up to the high door
## 11 THE BOULDER RUN  step on the idol plate: the temple wakes, a colossal stone ball drops behind you and
##                     rolls down the great ramp - run, hop the spike trenches, dive into the side alcove
##                     while it plunges into the river
## 12 The Gorge        three VINE swings across the gorge [shortcut: two WALL RUNS along the gorge walls]
## 13 Spike Bridge     BRANCH: a rising crumbling bridge over the spike pit, MANTLE | a chimney of two WALL RUNS
## 14 Moat             the causeway's DART TRAPS, a raft across the moat to the pyramid plaza
##                     [shortcut: three idol-head pillars out of the moat - 1 m landings, no raft]
## 15 First Terrace    two MANTLES up the buttresses of the first tier, the terrace's CRUSHER and dart lane
## 16 Serpent Stair    BRANCH: past the serpent rams (PISTONS), two MANTLES up the second tier | WALL RUN the
##                     stela frieze, through the serpent's mouth (PORTAL) to the second terrace
## 17 Upper Tiers      a chimney of two WALL RUNS up the third tier, then round the terrace: step on the glyph
##                     plate and race over the spike beds before its gate shuts
## 18 The Altar        the dart lanes of the north terrace, four MANTLES up the last two tiers, MANTLE onto
##                     the altar on the summit: the finish
##
## Jungle mechanics (own scripts): JungleVine (vine swings you ride), JungleRaft (log rafts),
## JungleDarts (dart traps with a clicking, glowing tell), JungleGlyphGate (pressure plate + stone gate
## with a countdown), and the set piece JungleBoulder. Route variants for the bot: 0 = main line,
## 1 = every alternative branch, 2 = main line + every shortcut.

const WATER_Y: float = -2.0

const JADE := Color(0.25, 0.95, 0.65)
const GOLD := Color(1.0, 0.76, 0.28)
const RED := Color(1.0, 0.3, 0.18)

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_nodes: Array[Checkpoint] = []
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable / solid piece of the course (world AABBs): decor keeps clear of them.
var _solids: Array[AABB] = []
## Platform tops that stand on a rock pillar down to the water: [top centre, size] (world).
var _piers: Array[Array] = []
## Stage frames (origin, yaw) - for the scenery round the route.
var _stage_frames: Array[Array] = []
## Where the falls, the pyramid etc. ended up (set by the stages).
var _anchor: Dictionary = {}
var _boulder: JungleBoulder
var deco: JungleDecor


func _configure() -> void:
	theme_id = "jungle"
	music_track = "jungle"
	kill_y = WATER_Y - 8.0
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


## Remember a solid box (world centre + world size) so the scenery keeps clear of it.
func _note(center: Vector3, size: Vector3) -> void:
	_solids.append(AABB(center - size * 0.5, size))


## A walkable stone block (local top centre, local size across x / along z). `pier`: a rock pillar
## stands under it down to the water (the scenery builds it later).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, pier: bool = true) -> Dictionary:
	var top: Vector3 = _w(c)
	var size: Vector3 = _sz(Vector3(sx, thick, sz))
	kit.plat(top, size, style, 0.0)
	_note(top - Vector3(0, thick * 0.5, 0), size)
	if pier:
		_piers.append([top - Vector3(0, thick, 0), size])
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A mantle ledge (local top centre, local size; size.y is the block's height).
func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	var ws: Vector3 = _sz(size)
	_note(_w(top) - Vector3(0, size.y * 0.5, 0), ws)
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


## Checkpoint landing facing the next stage's heading (_next_yaw).
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.2)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	_cp_nodes.append(cp)
	return d


## A KillZone strip of spikes (local floor centre of the pit, local size); the decor plants stakes.
func _spikes(floor_c: Vector3, sx: float, sz: float) -> void:
	var k := KillZone.new()
	k.show_mesh = false
	k.size = _sz(Vector3(sx, 1.2, sz))
	k.position = _w(floor_c + Vector3(0, 0.5, 0))
	add_child(k)
	_spike_beds.append([_w(floor_c), _sz(Vector3(sx, 0, sz))])


var _spike_beds: Array[Array] = []


# ---- mechanic helpers -------------------------------------------------------------------------

## A vine swing: its seat's top at local `bottom_top` at the bottom of the arc, swinging along -Z.
func _vine(bottom_top: Vector3, rope: float, deg: float, period: float, phase: float) -> JungleVine:
	var s := JungleVine.new()
	var size := Vector3(2.6, 0.35, 2.6)
	s.size = size
	s.rope = rope
	s.swing_deg = deg
	s.period = period
	s.phase = phase
	s.swing_dir = _d(Vector3(0, 0, -1))
	s.position = _w(bottom_top) - Vector3(0, size.y * 0.5, 0)
	s.set_meta("bottom", s.position)
	add_child(s)
	var reach: float = rope * sin(deg_to_rad(deg)) + 1.4
	_note(_w(bottom_top + Vector3(0, rope * 0.5, 0)), _sz(Vector3(2.8, rope + 1.0, reach * 2.0)))
	_vines.append(s)
	return s


var _vines: Array[JungleVine] = []


## A swing's seat centre (world) at the near (-1) or far (+1) end of its arc.
func _vine_end(s: JungleVine, side: float) -> Vector3:
	var a: float = deg_to_rad(s.swing_deg) * side
	var bottom: Vector3 = s.get_meta("bottom")
	return bottom + s.swing_dir * s.rope * sin(a) + Vector3.UP * s.rope * (1.0 - cos(a))


## Bot: jump from `from` onto a swing seat once it is (in `lead` s) within `radius` of `point`.
func _swing_board(from: Vector3, node: MovingPlatform, point: Vector3, radius: float = 0.45, lead: float = 0.4) -> void:
	route.append({"kind": "x_jump", "from": from, "to_node": node, "to_local": Vector3(0, 0.175, 0),
		"when_node": node, "when_local": Vector3.ZERO, "when_point": point, "when_radius": radius, "lead": lead})


## Bot: ride vine `s` to the far end of its arc and jump off toward `to` (world).
func _swing_off(s: JungleVine, to: Vector3) -> void:
	r_jump_from_ride(s, _vine_end(s, 1.0), 0.45, to, true, Vector3(0, 0.175, 0) + s.swing_dir * 0.5)


## A log raft (top at local `top` at its first stop), travelling `travel` (local) and back.
func _raft(top: Vector3, size: Vector3, travel: Vector3, period: float, phase: float) -> JungleRaft:
	var r := JungleRaft.new()
	r.size = _sz(size)
	r.points = [Vector3.ZERO, _d(travel)]
	r.period = period
	r.phase = phase
	r.dwell = 0.2
	r.position = _w(top) - Vector3(0, size.y * 0.5, 0)
	add_child(r)
	_note(_w(top + travel * 0.5), _sz(size) + _d(travel).abs() + Vector3(0.4, 1.0, 0.4))
	return r


## A dart trap whose face stands at local floor point `at`, firing along local +X across `span` m.
func _darts(at: Vector3, span: float, depth: float, period: float, phase: float, height: float = 2.2) -> JungleDarts:
	var d := JungleDarts.new()
	d.span = span
	d.depth = depth
	d.height = height
	d.period = period
	d.phase = phase
	d.fire_time = 1.0
	d.warn = 1.0
	d.rotation.y = deg_to_rad(_yaw)
	d.position = _w(at)
	add_child(d)
	return d


## A jade sun-beam (laser) across local x from `x0` to `x1` at local z, the tell stretched to 0.9 s.
func _beam(x0: float, x1: float, y: float, z: float, period: float, on_fraction: float, phase: float) -> LaserGate:
	var g: LaserGate = kit.laser(_w(Vector3((x0 + x1) * 0.5, y, z)), Vector3(absf(x1 - x0), 2.4, 0.3), period, on_fraction, phase, _yaw)
	g.warn = 0.9
	return g


# ---- bot helpers (all deterministic, from the course clock) ---------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## A jump onto moving `node` (landing at its local `off`) that fires once test() is true.
func _board(from: Vector3, node: Node3D, off: Vector3, test: Callable) -> void:
	route.append({"kind": "h_jump", "from": from, "to_node": node, "to_local": off, "test": test})


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


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	_restyle_environment()
	deco = JungleDecor.new(self, kit.rng)
	set_spawn(Vector3(0, 0.1, 4.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7,
			_stage_8, _stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1] if i + 1 < yaws.size() else 0.0
		_stage_frames.append([_o, _yaw])
		var end: Vector3 = stages[i].call()
		_frame(_w(end), _next_yaw)
	_pyramid_stages()
	_water()
	_surroundings()
	_jungle_materials()
	_checkpoint_fx()


## The river and the flooded forest floor: touch the water and you are out.
func _water() -> void:
	var net := KillZone.new()
	net.show_mesh = false
	net.size = Vector3(3000.0, 1.0, 3000.0)
	net.position = Vector3(0, WATER_Y - 0.45, -400.0)
	add_child(net)


# ---- stage 1: River Landing - stepping stones out of the river, a mantle up the broken stair --------

func _stage_1() -> Vector3:
	var start: Dictionary = _blk(Vector3(0, 0, 2.0), 10.0, 12.0, "main", 2.0)
	var s1: Dictionary = _blk(Vector3(0.8, 0.4, -9.2), 2.6, 2.6, "alt")
	var s2: Dictionary = _blk(Vector3(-1.0, 1.0, -14.6), 2.4, 2.4, "alt")
	var s3: Dictionary = _blk(Vector3(0.6, 1.6, -19.8), 2.4, 2.4, "alt")
	var l1: Dictionary = _ledge(Vector3(0.4, 4.9, -24.2), Vector3(4.0, 6.9, 2.6))
	var cp: Dictionary = _cp(Vector3(0, 4.9, -31.5))
	_anchor["start"] = _w(Vector3(0, 0, 2.0))
	_hop(start, s1)
	_hop(s1, s2)
	_hop(s2, s3)
	r_mantle(_w(Vector3(0.6, 1.6, -20.65)), _w(Vector3(0.4, 4.9, -24.4)))
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Log Rafts - ride the rafts up the river [shortcut: the pillar tops along the bank] ------

func _stage_2() -> Vector3:
	var r1: JungleRaft = _raft(Vector3(0, -6.4, -8.5), Vector3(3.0, 0.5, 4.4), Vector3(0, 0, -15.0), 11.0, 0.0)
	var p1: Dictionary = _blk(Vector3(0, -5.4, -29.8), 3.0, 3.0, "alt")
	var r2: JungleRaft = _raft(Vector3(0, -6.4, -36.0), Vector3(3.0, 0.5, 4.4), Vector3(0, 0, -14.0), 11.0, 0.43)
	var cp: Dictionary = _cp(Vector3(0, -4.9, -57.5))
	# SHORTCUT: mossy pillar tops along the bank (1.1 m landings) - no waiting for the rafts
	var pills: Array[Dictionary] = []
	var py: Array[float] = [-1.0, -1.6, -2.2, -2.6, -3.0, -3.4, -3.8, -4.2, -4.6]
	for i: int in py.size():
		pills.append(_blk(Vector3(4.6, py[i], -7.6 - 5.6 * float(i)), 1.1, 1.1, "accent"))
	_anchor["river_z"] = _o.z
	if route_variant == 2:
		var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
		_hop(cp0, pills[0])
		for i: int in range(1, pills.size()):
			_hop(pills[i - 1], pills[i])
		_hop(pills[pills.size() - 1], cp, Vector3(1.6, 0, 1.6))
	else:
		_board(_w(Vector3(0, 0, -2.65)), r1, Vector3(0, 0.25, 0.6), func() -> bool: return _mover_at(r1, Vector3.ZERO, 0.3, 0.0, 1.0))
		r_jump_from_ride(r1, _home(r1) + _d(Vector3(0, 0, -15.0)), 0.3, _w(Vector3(0, -5.4, -29.4)), true, Vector3(0, 0.25, 0) + _d(Vector3(0, 0, -1.2)))
		var far2: Vector3 = _d(Vector3(0, 0, -14.0))
		_board(_w(_edge(p1, Vector3(0, 0, -40.0))), r2, Vector3(0, 0.25, 0.6), func() -> bool: return _mover_at(r2, Vector3.ZERO, 0.3, 0.0, 1.0))
		r_jump_from_ride(r2, _home(r2) + far2, 0.3, _w(Vector3(0, -4.9, -56.0)), true, Vector3(0, 0.25, 0) + _d(Vector3(0, 0, -1.2)))
	r_walk(_w(Vector3(0, -4.9, -57.2)))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Falls Pool (BRANCH) - a vine over the plunge pool | a wall run under the falls -------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -7.0), 12.0, 3.0)
	# LEFT: the vine over the plunge pool
	var v: JungleVine = _vine(Vector3(-3.5, -1.7, -15.9), 8.0, 38.0, 5.0, 0.0)
	var la: Dictionary = _blk(Vector3(-3.5, 0, -26.0), 3.0, 3.0, "alt")
	# RIGHT: the wet cliff under the falls, a wall run, a landing
	kit.wallrun(_w(Vector3(5.0, 1.2, -19.0)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	_note(_w(Vector3(5.0, 1.2, -19.0)), _sz(Vector3(0.8, 6.5, 16.0)))
	var rb: Dictionary = _blk(Vector3(3.0, 0, -27.5), 3.0, 3.4, "alt")
	var merge: Dictionary = _blk(Vector3(0, 0.5, -31.8), 12.0, 2.6)
	var cp: Dictionary = _cp(Vector3(0, 0.5, -40.5))
	_anchor["falls"] = _w(Vector3(9.0, 0, -19.0))
	_anchor["falls_dir"] = _d(Vector3(-1, 0, 0))
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -7.4)))
		_swing_board(_w(Vector3(-3.5, 0, -8.15)), v, _vine_end(v, -1.0))
		_swing_off(v, _w(Vector3(-3.5, 0, -25.6)))
		_hop(la, merge, Vector3(-2.0, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.2, 0, -6.4)))
		r_wallrun(_w(Vector3(3.2, 0, -8.15)), _w(Vector3(4.5, 1.4, -12.6)), _w(Vector3(4.5, 1.4, -21.0)), _w(Vector3(3.0, 0, -27.3)))
		_hop(rb, merge, Vector3(1.0, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Dart Gallery - the corridor of dart traps, the crumbling bridge ------------------------

func _stage_4() -> Vector3:
	var floor_c := Vector3(0, 0, -20.0)
	_blk(floor_c, 3.6, 34.0, "main", 1.0)
	# the gallery walls (solid; the left one carries the dart faces)
	for sx: float in [-1.0, 1.0]:
		var wc: Vector3 = _w(Vector3(sx * 2.6, 1.9, -20.5))
		kit.block(wc, _sz(Vector3(1.6, 5.8, 33.0)), Color(0.42, 0.43, 0.35), true, 0.0)
		_note(wc, _sz(Vector3(1.6, 5.8, 33.0)))
	var traps: Array[JungleDarts] = []
	var tz: Array[float] = [-9.5, -16.5, -23.5, -30.5]
	for i: int in tz.size():
		traps.append(_darts(Vector3(-1.75, 0, tz[i]), 3.5, 1.4, 4.4, 0.2 * float(i)))
	# the crumbling bridge
	var slabs: Array[Dictionary] = []
	for i: int in 4:
		var c := Vector3(0, 0, -40.6 - 4.5 * float(i))
		var cp_slab := CollapsingPlatform.new()
		cp_slab.size = _sz(Vector3(2.6, 0.4, 2.6))
		cp_slab.is_round = false
		cp_slab.delay = 0.75
		cp_slab.respawn = 3.0
		cp_slab.position = _w(c) - Vector3(0, 0.2, 0)
		add_child(cp_slab)
		_note(_w(c) - Vector3(0, 0.2, 0), _sz(Vector3(2.6, 0.4, 2.6)))
		slabs.append(_area(c, 1.3, 1.3))
	var cp: Dictionary = _cp(Vector3(0, 0, -61.0))
	r_walk(_w(Vector3(0, 0, -5.0)))
	for i: int in traps.size():
		var t: JungleDarts = traps[i]
		var at: Vector3 = _w(Vector3(0, 0, tz[i] + 2.2))
		r_walk(at)
		_wait(func() -> bool: return t.is_safe_for(Game.course_time, 0.0, 2.2), at)
	r_walk(_w(Vector3(0, 0, -36.2)))
	r_jump(_w(Vector3(0, 0, -36.65)), _w(Vector3(0, 0, -40.6)))
	for i: int in range(1, slabs.size()):
		_hop(slabs[i - 1], slabs[i])
	_hop(slabs[3], cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Glyph Gate - the plate opens the gate; race over the spike pit before it shuts --------

func _stage_5() -> Vector3:
	var l0: Dictionary = _blk(Vector3(0, 0, -6.0), 6.0, 6.0)
	var p1: Dictionary = _blk(Vector3(1.0, 0, -14.0), 2.2, 2.2, "alt", 1.0, false)
	var p2: Dictionary = _blk(Vector3(-1.0, 0.6, -19.4), 2.2, 2.2, "alt", 1.0, false)
	var p3: Dictionary = _blk(Vector3(0.8, 1.2, -24.6), 2.2, 2.2, "alt", 1.0, false)
	var p4: Dictionary = _blk(Vector3(-0.2, 1.2, -29.8), 2.2, 2.2, "alt", 1.0, false)
	# the spike pit under the stepping stones (its floor, walls and stakes)
	var pit_y: float = -3.0
	_blk(Vector3(0, pit_y, -21.0), 8.0, 21.6, "alt", 1.0)
	_spikes(Vector3(0, pit_y, -21.0), 8.0, 21.6)
	for i: int in 4:
		var pc: Vector3 = [p1["c"], p2["c"], p3["c"], p4["c"]][i]
		var h: float = pc.y - pit_y
		var col: Vector3 = _w(Vector3(pc.x, pit_y + h * 0.5 - 0.5, pc.z))
		kit.block(col, _sz(Vector3(1.8, h - 1.0, 1.8)), Color(0.4, 0.41, 0.34), true, 0.0)
	# the wall with the gate in it, and the passage beyond
	var gate := JungleGlyphGate.new()
	gate.width = 3.2
	gate.height = 3.6
	gate.open_time = 7.0
	gate.plate = Vector3(0, 0, -6.5) - Vector3(0, 1.2, -34.0)
	gate.rotation.y = deg_to_rad(_yaw)
	gate.position = _w(Vector3(0, 1.2, -34.0))
	add_child(gate)
	_note(_w(Vector3(0, 4.0, -34.0)), _sz(Vector3(5.2, 8.0, 1.6)))
	for sx: float in [-1.0, 1.0]:
		var wc: Vector3 = _w(Vector3(sx * 6.1, 4.2, -34.0))
		kit.block(wc, _sz(Vector3(7.8, 10.4, 1.5)), Color(0.42, 0.43, 0.35), true, 0.0)
		_note(wc, _sz(Vector3(7.8, 10.4, 1.5)))
	var door: Dictionary = _blk(Vector3(0, 1.2, -37.5), 4.0, 8.0)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -46.5))
	_anchor["gate1"] = gate
	r_walk(_w(Vector3(0, 0, -6.5)))
	_hop(l0, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, p4)
	r_jump(_w(_edge(p4, Vector3(0, 0, -36.0))), _w(Vector3(0, 1.2, -36.0)))
	_hop(door, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Canopy - flower pads up into the canopy, two vines branch to branch -------------------

func _stage_6() -> Vector3:
	var base: Dictionary = _blk(Vector3(0, 0, -5.0), 3.0, 4.0, "alt")
	var pad1 := Vector3(0, 0, -5.5)
	kit.pad(_w(pad1), 19.0, 0.0, 0.0, 1.2)
	var b1: Dictionary = _blk(Vector3(0, 4.4, -12.0), 3.0, 5.0, "alt", 1.0, false)
	var pad2 := Vector3(0, 4.4, -13.4)
	kit.pad(_w(pad2), 19.0, 0.0, 0.0, 1.1)
	var b2: Dictionary = _blk(Vector3(0, 8.8, -18.5), 3.0, 4.0, "alt", 1.0, false)
	var v1: JungleVine = _vine(Vector3(0, 7.1, -27.2), 8.0, 38.0, 5.0, 0.0)
	var b3: Dictionary = _blk(Vector3(0, 8.8, -36.0), 3.0, 3.0, "alt", 1.0, false)
	var v2: JungleVine = _vine(Vector3(0, 7.1, -44.2), 8.0, 38.0, 5.0, 0.18)
	var cp: Dictionary = _cp(Vector3(0, 8.8, -54.0))
	_anchor["canopy"] = [_w(Vector3(0, 4.4, -12.0)), _w(Vector3(0, 8.8, -18.5)), _w(Vector3(0, 8.8, -36.0)), _w(Vector3(0, 8.8, -54.0))]
	r_walk(_w(Vector3(0, 0, -3.6)))
	r_pad(_w(pad1), _w(Vector3(0, 4.4, -10.6)))
	r_walk(_w(Vector3(0, 4.4, -11.2)))
	r_pad(_w(pad2), _w(Vector3(0, 8.8, -18.0)))
	r_walk(_w(Vector3(0, 8.8, -19.4)))
	_swing_board(_w(Vector3(0, 8.8, -20.15)), v1, _vine_end(v1, -1.0))
	_swing_off(v1, _w(Vector3(0, 8.8, -35.6)))
	r_walk(_w(Vector3(0, 8.8, -36.6)))
	_swing_board(_w(Vector3(0, 8.8, -37.15)), v2, _vine_end(v2, -1.0))
	_swing_off(v2, _w(Vector3(0, 8.8, -53.0)))
	r_walk(_w(Vector3(0, 8.8, -53.6)))
	r_checkpoint()
	b1.clear()
	b2.clear()
	b3.clear()
	base.clear()
	return cp["c"]


# ---- stage 7: Root Stair - mantle the root, wall-run the trunk, mantle onto the temple balcony --------

func _stage_7() -> Vector3:
	var r1: Dictionary = _ledge(Vector3(0, 3.3, -6.3), Vector3(4.0, 6.0, 2.6), "alt")
	kit.wallrun(_w(Vector3(-3.4, 4.6, -16.5)), Vector3(14.0, 6.5, 0.6), _yaw + 90.0)
	_note(_w(Vector3(-3.4, 4.6, -16.5)), _sz(Vector3(0.8, 6.5, 14.0)))
	_anchor["trunk"] = _w(Vector3(-7.4, 0, -16.5))
	var r2: Dictionary = _blk(Vector3(-0.6, 3.6, -26.4), 3.0, 3.4, "alt", 1.0, false)
	var l2: Dictionary = _ledge(Vector3(-0.6, 7.0, -31.4), Vector3(4.0, 7.0, 2.6))
	var cp: Dictionary = _cp(Vector3(0, 7.0, -38.5))
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -6.5)))
	r_wallrun(_w(Vector3(-1.0, 3.3, -7.25)), _w(Vector3(-2.7, 4.7, -11.6)), _w(Vector3(-2.7, 4.7, -19.5)), _w(Vector3(-0.6, 3.6, -26.2)))
	r_mantle(_w(Vector3(-0.6, 3.6, -27.75)), _w(Vector3(-0.6, 7.0, -31.6)))
	_hop(l2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	r1.clear()
	r2.clear()
	return cp["c"]


# ---- stage 8: Sun Court (BRANCH) - the jade sun-beams | the colonnade [shortcut: the idol's mouth] -----

func _stage_8() -> Vector3:
	var court: Dictionary = _blk(Vector3(0, 0, -20.0), 12.0, 28.0)
	# RIGHT (main): three sun-beams sweeping the court in a wave
	var beams: Array[LaserGate] = []
	var bz: Array[float] = [-12.0, -19.0, -26.0]
	for i: int in bz.size():
		beams.append(_beam(-2.8, 6.0, 1.2, bz[i], 3.6, 0.42, fposmod(-0.18 * float(i), 1.0)))
	# a low wall between the court and the colonnade (the beams' far posts stand on it)
	var lw: Vector3 = _w(Vector3(-3.3, 0.45, -19.0))
	kit.block(lw, _sz(Vector3(0.5, 0.9, 22.0)), Color(0.42, 0.43, 0.35), true, 0.0)
	_note(lw, _sz(Vector3(0.5, 0.9, 22.0)))
	# LEFT: up the colonnade base, along the column tops
	var lb: Dictionary = _ledge(Vector3(-4.5, 3.3, -9.8), Vector3(3.0, 3.3, 2.4), "alt")
	var cols: Array[Dictionary] = []
	var cy: Array[float] = [3.6, 3.9, 3.6]
	for i: int in 3:
		cols.append(_blk(Vector3(-4.5, cy[i], -15.6 - 5.4 * float(i)), 1.6, 1.6, "alt", 0.6, false))
		var colc: Vector3 = _w(Vector3(-4.5, (cy[i] - 0.6) * 0.5, -15.6 - 5.4 * float(i)))
		kit.block(colc, _sz(Vector3(1.2, cy[i] - 0.6, 1.2)), Color(0.5, 0.5, 0.42), true, 0.0)
	var cp: Dictionary = _cp(Vector3(0, 0, -41.0))
	# SHORTCUT: a 79% leap to the idol's lip, through its mouth (PORTAL) past the beams
	_blk(Vector3(10.2, 1.4, -9.6), 1.2, 1.2, "accent", 0.6, false)
	kit.block(_w(Vector3(10.2, 0.1, -9.6)), Vector3(1.0, 2.0, 1.0), Color(0.4, 0.41, 0.34), true, 0.0)
	kit.portal(_w(Vector3(10.2, 1.4, -10.0)), _yaw, _w(Vector3(2.0, 0, -30.6)), _yaw, 5.0)
	_anchor["idol"] = [_w(Vector3(10.2, 1.4, -12.7)), _yaw]
	_piers.append([_w(Vector3(10.2, -0.3, -12.7)), _sz(Vector3(5.4, 0, 4.4))])
	_arrival(_w(Vector3(2.0, 0, -31.4)))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), court, Vector3(0, 0, 13.2))
	if route_variant == 1:
		r_walk(_w(Vector3(-4.5, 0, -6.6)))
		r_mantle(_w(Vector3(-4.5, 0, -7.0)), _w(Vector3(-4.5, 3.3, -10.0)))
		_hop(lb, cols[0])
		_hop(cols[0], cols[1])
		_hop(cols[1], cols[2])
		r_jump(_w(_edge(cols[2], Vector3(-2.0, 0, -32.0))), _w(Vector3(-2.0, 0, -31.5)))
	elif route_variant == 2:
		r_walk(_w(Vector3(5.4, 0, -9.6)))
		r_jump(_w(Vector3(5.65, 0, -9.6)), _w(Vector3(10.2, 1.4, -9.6)))
		r_portal(_w(Vector3(10.2, 1.4, -10.2)), _w(Vector3(2.0, 0, -31.4)))
	else:
		var wz: Array[float] = [-9.8, -16.8, -23.8]
		for i: int in beams.size():
			var g: LaserGate = beams[i]
			var at: Vector3 = _w(Vector3(1.5, 0, wz[i]))
			r_walk(at)
			_wait(func() -> bool: return _dark(g, 0.0, 1.55), at)
		r_walk(_w(Vector3(1.0, 0, -31.0)))
	_hop(_area(Vector3(0, 0, -31.0), 6.0, 3.0), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	court.clear()
	return cp["c"]


# ---- stage 9: Stone Faces - the beam over the ravine, the stone tongues (PISTONS), crumbling slabs -----

func _stage_9() -> Vector3:
	_blk(Vector3(0, 0, -18.5), 1.4, 31.0, "alt", 0.8, false)
	var rams: Array[Piston] = []
	var rz: Array[float] = [-10.0, -18.5, -27.0]
	for i: int in rz.size():
		var p: Piston = kit.piston(_w(Vector3(3.0, 1.3, rz[i])), Vector3(1.4, 1.2, 1.4), _yaw + 90.0, 3.4, 5.0, fposmod(0.3 * float(i), 1.0), 9.0)
		rams.append(p)
		_tell(_w(Vector3(3.0, 2.6, rz[i])), func(t: float) -> float: return _until_punch(p, t))
		_note(_w(Vector3(3.0 + 2.2, 0.7, rz[i])), _sz(Vector3(6.0, 1.6, 1.8)))
	_anchor["faces"] = [_w(Vector3(8.4, 0, -18.5)), _d(Vector3(-1, 0, 0))]
	var slabs: Array[Dictionary] = []
	for i: int in 2:
		var c := Vector3(0, 0, -37.8 - 4.2 * float(i))
		var s := CollapsingPlatform.new()
		s.size = _sz(Vector3(2.2, 0.4, 2.2))
		s.is_round = false
		s.delay = 0.75
		s.respawn = 3.0
		s.position = _w(c) - Vector3(0, 0.2, 0)
		add_child(s)
		_note(_w(c) - Vector3(0, 0.2, 0), _sz(Vector3(2.2, 0.4, 2.2)))
		slabs.append(_area(c, 1.1, 1.1))
	var cp: Dictionary = _cp(Vector3(0, 0, -49.5))
	r_walk(_w(Vector3(0, 0, -5.4)))
	for i: int in rams.size():
		var p: Piston = rams[i]
		var at: Vector3 = _w(Vector3(0, 0, rz[i] + 1.8))
		r_walk(at)
		_wait(func() -> bool: return _ram_clear(p, 0.0, 2.0), at)
	r_walk(_w(Vector3(0, 0, -33.6)))
	r_jump(_w(Vector3(0, 0, -33.75)), _w(Vector3(0, 0, -37.8)))
	_hop(slabs[0], slabs[1])
	_hop(slabs[1], cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## Seconds until a piston next punches.
static func _until_punch(p: Piston, t: float) -> float:
	var u: float = fposmod(t / p.period + p.phase, 1.0)
	return fposmod(Piston.PUNCH_START - u, 1.0) * p.period


## Seconds until a crusher next slams.
static func _until_slam(c: Crusher, t: float) -> float:
	var u: float = fposmod(t / c.period + c.phase, 1.0)
	return fposmod(Crusher.SLAM - u, 1.0) * c.period


# ---- stage 10: Idol Hall - under the ceiling blocks (CRUSHERS), a dart lane, mantle to the high door ---

func _stage_10() -> Vector3:
	_blk(Vector3(0, 0, -17.0), 3.6, 28.0, "main", 1.0, false)
	var presses: Array[Crusher] = []
	var cz: Array[float] = [-9.0, -16.5]
	for i: int in cz.size():
		var c: Crusher = kit.crusher(_w(Vector3(0, 0, cz[i])), Vector3(3.0, 1.4, 2.6), 3.2, 4.6, 0.35 * float(i), _yaw)
		presses.append(c)
		_tell(_w(Vector3(2.3, 4.2, cz[i])), func(t: float) -> float: return _until_slam(c, t))
	var dt: JungleDarts = _darts(Vector3(-1.75, 0, -23.5), 3.5, 1.4, 4.4, 0.5)
	# the hall's walls
	for sx: float in [-1.0, 1.0]:
		var wc: Vector3 = _w(Vector3(sx * 2.6, 3.0, -17.0))
		kit.block(wc, _sz(Vector3(1.6, 8.0, 28.0)), Color(0.4, 0.41, 0.34), true, 0.0)
		_note(wc, _sz(Vector3(1.6, 8.0, 28.0)))
	var l: Dictionary = _ledge(Vector3(0, 3.4, -33.6), Vector3(4.0, 4.4, 2.6))
	var cp: Dictionary = _cp(Vector3(0, 3.4, -41.0))
	_anchor["hall"] = [_w(Vector3(0, 0, -17.0)), _yaw]
	r_walk(_w(Vector3(0, 0, -5.6)))
	for i: int in presses.size():
		var c: Crusher = presses[i]
		var at: Vector3 = _w(Vector3(0, 0, cz[i] + 3.0))
		r_walk(at)
		_wait(func() -> bool: return _press_ok(c, 0.0, 2.3), at)
	var at2: Vector3 = _w(Vector3(0, 0, -21.2))
	r_walk(at2)
	_wait(func() -> bool: return dt.is_safe_for(Game.course_time, 0.0, 2.2), at2)
	r_walk(_w(Vector3(0, 0, -30.4)))
	r_mantle(_w(Vector3(0, 0, -30.65)), _w(Vector3(0, 3.4, -33.8)))
	_hop(l, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 11: THE BOULDER RUN - the idol plate wakes the temple; outrun the ball down the ramp -------

func _stage_11() -> Vector3:
	# the top landing (the plate is near its far end), the ramp down, spike trenches, the lower run
	_blk(Vector3(0, 0, -8.5), 6.0, 11.0, "main", 1.2)
	var r1_len: float = 24.0
	var r1_drop: float = 5.0
	var pitch1: float = rad_to_deg(atan2(r1_drop, r1_len))
	kit.ramp(_w(Vector3(0, -r1_drop * 0.5, -14.0 - r1_len * 0.5)), Vector3(6.0, 0.6, sqrt(r1_len * r1_len + r1_drop * r1_drop)), -pitch1, _yaw, "main")
	_note(_w(Vector3(0, -2.5, -26.0)), _sz(Vector3(6.0, 6.0, 24.0)))
	_spikes(Vector3(0, -8.0, -39.5), 6.0, 3.0)
	_blk(Vector3(0, -8.0, -39.5), 6.0, 3.0, "alt", 0.6, false)
	var f1: Dictionary = _blk(Vector3(0, -5.0, -46.5), 6.0, 11.0)
	_spikes(Vector3(0, -8.0, -53.5), 6.0, 3.0)
	_blk(Vector3(0, -8.0, -53.5), 6.0, 3.0, "alt", 0.6, false)
	kit.ramp(_w(Vector3(0, -7.5, -55.0 - r1_len * 0.5)), Vector3(6.0, 0.6, sqrt(r1_len * r1_len + r1_drop * r1_drop)), -pitch1, _yaw, "main")
	_note(_w(Vector3(0, -7.5, -67.0)), _sz(Vector3(6.0, 6.0, 24.0)))
	_spikes(Vector3(0, -13.0, -80.5), 6.0, 3.0)
	_blk(Vector3(0, -13.0, -80.5), 6.0, 3.0, "alt", 0.6, false)
	var f2: Dictionary = _blk(Vector3(0, -10.0, -87.0), 6.0, 10.0)
	# the alcove to the side, where you dive out of its way; the ball runs on off the lip
	var cp: Dictionary = _cp(Vector3(-7.6, -10.0, -88.0))
	_anchor["lip"] = [_w(Vector3(0, -10.0, -92.0)), _d(Vector3(0, 0, -1))]
	# the ball and its niche above the top landing
	var niche: Vector3 = _w(Vector3(0, 8.6, -5.0))
	var b := JungleBoulder.new()
	b.radius = 2.6
	b.delay = 2.0
	b.v_start = 3.0
	b.accel = 3.0
	b.v_max = 7.5
	b.pit_time = 1.2
	var pts: Array[Vector3] = []
	var rr: float = 2.6
	for lp: Vector3 in [Vector3(0, rr, -5.0), Vector3(0, rr, -14.0), Vector3(0, rr - r1_drop, -38.0), Vector3(0, rr - r1_drop, -55.0),
			Vector3(0, rr - 2.0 * r1_drop, -79.0), Vector3(0, rr - 2.0 * r1_drop, -92.0)]:
		pts.append(_w(lp) - niche)
	b.track = pts
	b.trigger_pos = _w(Vector3(0, 1.0, -11.0)) - niche
	b.trigger_size = _sz(Vector3(6.0, 2.0, 1.0))
	b.position = niche
	add_child(b)
	_boulder = b
	_anchor["niche"] = [niche, _yaw]
	_anchor["plate"] = _w(Vector3(0, 0, -11.0))
	# the run: no stopping
	r_walk(_w(Vector3(0, 0, -12.0)))
	r_walk(_w(Vector3(0, -4.6, -36.5)))
	r_jump(_w(Vector3(0, -4.95, -37.6)), _w(Vector3(0, -5.0, -42.5)))
	r_walk(_w(Vector3(0, -5.0, -51.2)))
	r_jump(_w(Vector3(0, -5.0, -51.65)), _w(Vector3(0, -5.4, -56.6)))
	r_walk(_w(Vector3(0, -9.6, -77.5)))
	r_jump(_w(Vector3(0, -9.95, -78.6)), _w(Vector3(0, -10.0, -83.4)))
	r_walk(_w(Vector3(-2.0, -10.0, -86.6)))
	r_jump(_w(Vector3(-2.65, -10.0, -87.2)), _w(Vector3(-7.6, -10.0, -88.0)))
	r_checkpoint()
	f1.clear()
	f2.clear()
	return cp["c"]


# ---- stage 12: The Gorge - three vines across [shortcut: two wall runs along the gorge walls] -------

func _stage_12() -> Vector3:
	var v1: JungleVine = _vine(Vector3(0, -1.7, -10.2), 8.0, 38.0, 5.0, 0.0)
	var l1: Dictionary = _blk(Vector3(0, 0, -19.5), 3.0, 3.0, "alt")
	var v2: JungleVine = _vine(Vector3(0, -1.1, -27.9), 8.0, 38.0, 5.0, 0.2)
	var l2: Dictionary = _blk(Vector3(0, 0.6, -37.2), 3.0, 3.0, "alt")
	var v3: JungleVine = _vine(Vector3(0, -0.5, -45.6), 8.0, 38.0, 5.0, 0.4)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -55.5))
	# SHORTCUT: run the gorge's left wall, kick across to its right wall, kick down onto the second landing
	kit.wallrun(_w(Vector3(-3.0, 1.2, -13.0)), Vector3(14.0, 6.5, 0.5), _yaw + 90.0)
	kit.wallrun(_w(Vector3(3.0, 3.6, -26.0)), Vector3(12.0, 7.0, 0.5), _yaw + 90.0)
	_note(_w(Vector3(-3.0, 1.2, -13.0)), _sz(Vector3(0.7, 6.5, 14.0)))
	_note(_w(Vector3(3.0, 3.6, -26.0)), _sz(Vector3(0.7, 7.0, 12.0)))
	_anchor["gorge"] = [_o, _yaw]
	if route_variant == 2:
		r_wallrun(_w(Vector3(-1.4, 0, -2.65)), _w(Vector3(-2.5, 1.4, -7.4)), _w(Vector3(-2.5, 1.4, -15.6)), _w(Vector3(2.5, 3.8, -21.4)))
		r_wallrun(Vector3.ZERO, _w(Vector3(2.5, 3.8, -21.4)), _w(Vector3(2.5, 3.8, -28.6)), _w(Vector3(0, 0.6, -36.6)), true, true)
	else:
		_swing_board(_w(Vector3(0, 0, -2.65)), v1, _vine_end(v1, -1.0))
		_swing_off(v1, _w(Vector3(0, 0, -19.1)))
		r_walk(_w(Vector3(0, 0, -20.1)))
		_swing_board(_w(Vector3(0, 0, -20.65)), v2, _vine_end(v2, -1.0))
		_swing_off(v2, _w(Vector3(0, 0.6, -36.8)))
	r_walk(_w(Vector3(0, 0.6, -37.8)))
	_swing_board(_w(Vector3(0, 0.6, -38.35)), v3, _vine_end(v3, -1.0))
	_swing_off(v3, _w(Vector3(0, 1.2, -54.5)))
	r_walk(_w(Vector3(0, 1.2, -55.2)))
	r_checkpoint()
	l1.clear()
	l2.clear()
	return cp["c"]


# ---- stage 13: Spike Bridge (BRANCH) - the rising crumbling bridge | a chimney of two wall runs ---------

func _stage_13() -> Vector3:
	var fork: Dictionary = _blk(Vector3(0, 0, -5.75), 12.0, 5.5)
	# LEFT (main): crumbling slabs climbing over the spike pit, a static step, a mantle
	var sy: Array[float] = [0.6, 1.4, 2.2]
	var slabs: Array[Dictionary] = []
	for i: int in sy.size():
		var c := Vector3(-3.5, sy[i], -11.0 - 4.2 * float(i))
		var s := CollapsingPlatform.new()
		s.size = _sz(Vector3(2.4, 0.4, 2.4))
		s.is_round = false
		s.delay = 0.8
		s.respawn = 3.0
		s.position = _w(c) - Vector3(0, 0.2, 0)
		add_child(s)
		_note(_w(c) - Vector3(0, 0.2, 0), _sz(Vector3(2.4, 0.4, 2.4)))
		slabs.append(_area(c, 1.2, 1.2))
	var step: Dictionary = _blk(Vector3(-3.5, 3.3, -23.0), 2.4, 2.4, "alt", 1.0, false)
	kit.block(_w(Vector3(-3.5, -0.35, -23.0)), Vector3(1.6, 6.3, 1.6), Color(0.4, 0.41, 0.34), true, 0.0)
	_spikes(Vector3(-3.0, -3.5, -17.0), 6.0, 16.0)
	_blk(Vector3(-3.0, -3.5, -17.0), 6.0, 16.0, "alt", 1.0, true)
	# RIGHT: the chimney between two stelae
	kit.wallrun(_w(Vector3(5.8, 1.2, -12.55)), Vector3(6.5, 7.0, 0.5), _yaw + 90.0)
	kit.wallrun(_w(Vector3(1.2, 6.0, -18.3)), Vector3(8.0, 7.0, 0.5), _yaw + 90.0)
	_note(_w(Vector3(5.8, 1.2, -12.55)), _sz(Vector3(0.7, 7.0, 6.5)))
	_note(_w(Vector3(1.2, 6.0, -18.3)), _sz(Vector3(0.7, 7.0, 8.0)))
	var merge: Dictionary = _ledge(Vector3(0, 6.6, -27.5), Vector3(12.0, 10.6, 3.0))
	var cp: Dictionary = _cp(Vector3(0, 6.6, -35.0))
	_anchor["stelae"] = [_w(Vector3(5.8, 0, -12.55)), _w(Vector3(1.2, 0, -18.3)), _yaw]
	if route_variant == 1:
		r_walk(_w(Vector3(4.0, 0, -5.0)))
		r_wallrun(_w(Vector3(4.0, 0, -5.65)), _w(Vector3(5.2, 1.4, -10.4)), _w(Vector3(5.2, 1.4, -13.3)), _w(Vector3(1.8, 5.5, -17.2)))
		r_wallrun(Vector3.ZERO, _w(Vector3(1.8, 5.5, -17.2)), _w(Vector3(1.8, 5.5, -20.2)), _w(Vector3(1.2, 6.6, -27.0)), true, true)
	else:
		r_walk(_w(Vector3(-3.5, 0, -7.6)))
		r_jump(_w(Vector3(-3.5, 0, -8.15)), _w(Vector3(-3.5, 0.6, -11.0)))
		_hop(slabs[0], slabs[1])
		_hop(slabs[1], slabs[2])
		_hop(slabs[2], step)
		r_mantle(_w(Vector3(-3.5, 3.3, -23.85)), _w(Vector3(-3.5, 6.6, -26.6)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	fork.clear()
	return cp["c"]


# ---- stage 14: Moat - the causeway's dart traps, a raft across the moat to the pyramid plaza ----------

func _stage_14() -> Vector3:
	_blk(Vector3(0, 0, -12.0), 3.0, 18.0)
	var traps: Array[JungleDarts] = []
	var tz: Array[float] = [-8.0, -15.0]
	for i: int in tz.size():
		traps.append(_darts(Vector3(-1.55, 0, tz[i]), 3.1, 1.4, 4.0, 0.35 * float(i)))
		var fc: Vector3 = _w(Vector3(-2.3, 1.9, tz[i]))
		kit.block(fc, _sz(Vector3(1.4, 3.8, 2.6)), Color(0.42, 0.43, 0.35), true, 0.0)
		_note(fc, _sz(Vector3(1.4, 3.8, 2.6)))
		var rc: Vector3 = _w(Vector3(2.2, 1.4, tz[i]))
		kit.block(rc, _sz(Vector3(1.2, 2.8, 2.0)), Color(0.42, 0.43, 0.35), true, 0.0)
		_note(rc, _sz(Vector3(1.2, 2.8, 2.0)))
	var moat_y: float = -3.6
	var r: JungleRaft = _raft(Vector3(0, moat_y + 0.5, -25.6), Vector3(3.0, 0.5, 4.4), Vector3(0, 0, -14.0), 10.0, 0.0)
	var cp: Dictionary = _cp(Vector3(0, -2.0, -46.0))
	_anchor["moat"] = [_w(Vector3(0, moat_y, -45.5)), _yaw]
	# the moat lies on the hill the pyramid stands on (a rock plateau out of the river)
	_piers.append([_w(Vector3(0, moat_y - 0.2, -45.5)), _sz(Vector3(88.0, 0, 89.0))])
	var moat := KillZone.new()
	moat.show_mesh = false
	moat.size = Vector3(90.0, 1.0, 90.0)
	moat.position = _w(Vector3(0, moat_y - 0.5, -45.5))
	add_child(moat)
	# SHORTCUT: three idol-head pillars standing out of the moat (1 m tops) - no waiting for the raft
	var pills: Array[Dictionary] = []
	var pz: Array[float] = [-26.4, -32.0, -37.6]
	var pyy: Array[float] = [-0.4, -0.9, -1.4]
	for i: int in 3:
		pills.append(_blk(Vector3(3.0, pyy[i], pz[i]), 1.0, 1.0, "accent", 0.6))
	r_walk(_w(Vector3(0, 0, -3.6)))
	for i: int in traps.size():
		var t: JungleDarts = traps[i]
		var at: Vector3 = _w(Vector3(0, 0, tz[i] + 2.4))
		r_walk(at)
		_wait(func() -> bool: return t.is_safe_for(Game.course_time, 0.0, 2.2), at)
	if route_variant == 2:
		r_walk(_w(Vector3(0.9, 0, -20.2)))
		r_jump(_w(Vector3(1.0, 0, -20.65)), _w(pills[0]["c"]))
		_hop(pills[0], pills[1])
		_hop(pills[1], pills[2])
		_hop(pills[2], cp, Vector3(1.6, 0, 1.6))
	else:
		r_walk(_w(Vector3(0, 0, -20.4)))
		_board(_w(Vector3(0, 0, -20.65)), r, Vector3(0, 0.25, 0.6), func() -> bool: return _mover_at(r, Vector3.ZERO, 0.3, 0.0, 1.0))
		r_jump_from_ride(r, _home(r) + _d(Vector3(0, 0, -14.0)), 0.3, _w(Vector3(0, -2.0, -44.5)), true, Vector3(0, 0.25, 0) + _d(Vector3(0, 0, -1.2)))
	r_walk(_w(Vector3(0, -2.0, -45.7)))
	r_checkpoint()
	return cp["c"]


# ---- the pyramid ---------------------------------------------------------------------------------
# Five tiers, 6.6 m each, stepping in 7 m a side round a core; stages 15-18 climb round its terraces.
# Built in the frame of the plaza checkpoint at its foot (axis-aligned to that frame): the first tier's
# front face is 8 m ahead of it. "Terrace k" is the top of tier k outside tier k + 1.

const TIER_H: float = 6.6
const TIER_STEP: float = 7.0
const PYR_HALF: float = 34.0
const PYR_Z: float = -42.0

var _pyr_o: Vector3
var _pyr_yaw: float


func _tier_top(i: int) -> float:
	return TIER_H * float(i + 1)


func _tier_half(i: int) -> float:
	return PYR_HALF - TIER_STEP * float(i)


## A checkpoint standing straight on a terrace (the terrace is its floor).
func _cp_bare(c: Vector3, yaw: float) -> void:
	var cp: Checkpoint = kit.checkpoint(_w(c), yaw)
	_cp_world.append(_w(c))
	_cp_nodes.append(cp)


func _pyramid_stages() -> void:
	_pyr_o = _o
	_pyr_yaw = _yaw
	_anchor["pyramid"] = [_w(Vector3(0, 0, PYR_Z)), _yaw]
	for i: int in 5:
		var h: float = _tier_half(i)
		var size := Vector3(h * 2.0, TIER_H, h * 2.0)
		kit.plat(_w(Vector3(0, _tier_top(i), PYR_Z)), size, "main", 0.0)
		_note(_w(Vector3(0, _tier_top(i) - TIER_H * 0.5, PYR_Z)), size)
	# the plaza between the checkpoint and the first tier, and the hill the pyramid stands on
	_blk(Vector3(0, 0, -5.5), 20.0, 5.0, "main", 1.0)
	_piers.append([_w(Vector3(0, 0, PYR_Z)), Vector3(PYR_HALF * 2.0 + 6.0, 0, PYR_HALF * 2.0 + 6.0)])
	_stage_15()
	_stage_16()
	_stage_17()
	_stage_18()


# ---- stage 15: First Terrace - mantle the buttresses, the terrace's crusher and dart lane ---------------

func _stage_15() -> void:
	_frame(_pyr_o, _pyr_yaw)
	var t0: float = _tier_top(0)
	var face: float = PYR_Z + _tier_half(0)          # -8: the first tier's front face
	var mid: float = face - TIER_STEP * 0.5            # -11.5: the middle of the front terrace
	var a: Dictionary = _ledge(Vector3(2.0, 3.3, face + 1.1), Vector3(3.6, 3.3, 2.2), "alt")
	var b: Dictionary = _ledge(Vector3(7.6, t0, face + 1.1), Vector3(3.6, t0, 2.2), "alt")
	var press: Crusher = kit.crusher(_w(Vector3(15.5, t0, mid)), Vector3(3.0, 1.4, 3.0), 3.0, 4.6, 0.1, _yaw + 90.0)
	_tell(_w(Vector3(15.5, t0 + 3.2, face - TIER_STEP + 0.1)), func(t: float) -> float: return _until_slam(press, t))
	var dt: JungleDarts = _darts(Vector3(21.5, t0, face - TIER_STEP + 0.02), TIER_STEP, 1.4, 4.4, 0.6)
	dt.rotation.y = deg_to_rad(_yaw - 90.0)
	_cp_bare(Vector3(30.5, t0, mid), _yaw)
	r_walk(_w(Vector3(2.0, 0, face + 4.4)))
	r_mantle(_w(Vector3(2.0, 0, face + 4.55)), _w(Vector3(2.0, 3.3, face + 0.9)))
	r_walk(_w(Vector3(3.2, 3.3, face + 1.1)))
	r_mantle(_w(Vector3(3.45, 3.3, face + 1.1)), _w(Vector3(7.8, t0, face + 1.0)))
	r_walk(_w(Vector3(10.6, t0, mid)))
	r_walk(_w(Vector3(12.0, t0, mid)))
	_wait(func() -> bool: return _press_ok(press, 0.0, 2.3), _w(Vector3(12.0, t0, mid)))
	r_walk(_w(Vector3(19.0, t0, mid)))
	_wait(func() -> bool: return dt.is_safe_for(Game.course_time, 0.0, 2.2), _w(Vector3(19.0, t0, mid)))
	r_walk(_w(Vector3(30.2, t0, mid)))
	r_checkpoint()
	a.clear()
	b.clear()


# ---- stage 16: Serpent Stair (BRANCH) - north past the serpent rams, two buttresses up the second tier |
# ---- the stela wall run and the serpent's mouth (PORTAL) up to the second terrace -----------------------

func _stage_16() -> void:
	_frame(_pyr_o, _pyr_yaw)
	var t0: float = _tier_top(0)
	var t1: float = _tier_top(1)
	var fx: float = _tier_half(1)          # 27: the second tier's east face
	var ox: float = _tier_half(0)          # 34: the first terrace's outer edge
	var lane: float = (fx + ox) * 0.5      # 30.5
	# MAIN: the serpent rams punch out of the second tier across the terrace
	var rams: Array[Piston] = []
	var rz: Array[float] = [-19.0, -26.0]
	for i: int in rz.size():
		var p: Piston = kit.piston(_w(Vector3(fx + 0.75, t0 + 1.3, rz[i])), Vector3(1.4, 1.2, 1.4), _yaw - 90.0, 2.6, 5.0, 0.5 * float(i), 9.0)
		rams.append(p)
		_tell(_w(Vector3(fx + 0.1, t0 + 2.7, rz[i] - 1.4)), func(t: float) -> float: return _until_punch(p, t), _yaw + 90.0)
	var c: Dictionary = _ledge(Vector3(fx + 1.1, t0 + 3.3, -33.0), Vector3(2.2, 3.3, 3.6), "alt")
	var d: Dictionary = _ledge(Vector3(fx + 1.15, t1, -38.6), Vector3(2.3, TIER_H, 3.6), "alt")
	# ALT: the stela frieze along the terrace's outer edge, the serpent's mouth
	kit.wallrun(_w(Vector3(ox - 0.4, t0 + 1.2, -21.0)), Vector3(14.0, 6.5, 0.5), _yaw + 90.0)
	_note(_w(Vector3(ox - 0.4, t0 + 1.2, -21.0)), _sz(Vector3(0.7, 6.5, 14.0)))
	kit.portal(_w(Vector3(31.5, t0, -36.0)), _yaw, _w(Vector3(23.5, t1, -34.0)), _yaw, 5.0)
	_anchor["serpent_mouth"] = [_w(Vector3(31.5, t0, -37.4)), _yaw]
	_arrival(_w(Vector3(23.5, t1, -34.9)))
	_cp_bare(Vector3(23.5, t1, -36.6), _yaw)
	if route_variant == 1:
		r_walk(_w(Vector3(31.8, t0, -9.4)))
		r_wallrun(_w(Vector3(31.8, t0, -11.05)), _w(Vector3(33.1, t0 + 1.4, -15.5)), _w(Vector3(33.1, t0 + 1.4, -24.5)), _w(Vector3(31.2, t0, -31.6)))
		r_walk(_w(Vector3(31.5, t0, -33.4)))
		r_portal(_w(Vector3(31.5, t0, -36.2)), _w(Vector3(23.5, t1, -34.9)))
		r_walk(_w(Vector3(23.5, t1, -36.4)))
	else:
		r_walk(_w(Vector3(lane, t0, -14.0)))
		for i: int in rams.size():
			var p: Piston = rams[i]
			var at: Vector3 = _w(Vector3(lane, t0, rz[i] + 1.8))
			r_walk(at)
			_wait(func() -> bool: return _ram_clear(p, 0.0, 2.0), at)
		r_walk(_w(Vector3(32.4, t0, -31.8)))
		r_walk(_w(Vector3(32.9, t0, -33.0)))
		r_mantle(_w(Vector3(31.55, t0, -33.0)), _w(Vector3(28.4, t0 + 3.3, -33.0)))
		r_walk(_w(Vector3(28.1, t0 + 3.3, -34.2)))
		r_mantle(_w(Vector3(28.1, t0 + 3.3, -34.45)), _w(Vector3(28.2, t1, -37.6)))
		r_walk(_w(Vector3(25.2, t1, -38.4)))
		r_walk(_w(Vector3(23.5, t1, -36.9)))
	r_checkpoint()
	c.clear()
	d.clear()


# ---- stage 17: Upper Tiers - a chimney of wall runs up the third tier, the glyph gate round the terrace ---

func _stage_17() -> void:
	_frame(_pyr_o, _pyr_yaw)
	var t1: float = _tier_top(1)
	var t2: float = _tier_top(2)
	var f2: float = _tier_half(2)            # 20: the third tier's east face
	kit.wallrun(_w(Vector3(f2 + 0.25, t1 + 1.2, -48.0)), Vector3(8.0, 7.0, 0.5), _yaw + 90.0)
	kit.wallrun(_w(Vector3(f2 + 5.1, t1 + 6.0, -52.0)), Vector3(8.0, 7.0, 0.5), _yaw + 90.0)
	_note(_w(Vector3(f2 + 5.1, t1 + 4.75, -52.0)), _sz(Vector3(0.7, 9.5, 8.0)))
	var foot: Vector3 = _w(Vector3(f2 + 5.1, t1 + 1.25, -52.0))
	kit.block(foot, _sz(Vector3(0.5, 2.5, 8.0)), Color(0.42, 0.43, 0.35), true, 0.0)
	var e: Dictionary = _ledge(Vector3(f2 + 1.1, t2, -61.0), Vector3(2.2, TIER_H, 3.6), "alt")
	# round the corner onto the north side of the third terrace: the plate, spike beds, the gate
	var nz: float = PYR_Z - _tier_half(3) - TIER_STEP * 0.5     # -58.5: the middle of the north terrace
	var plate_w: Vector3 = _w(Vector3(18.0, t2, nz))
	var gate := JungleGlyphGate.new()
	gate.width = 3.2
	gate.height = 3.4
	gate.open_time = 4.6
	gate.warn = 1.4
	var g_yaw: float = _yaw + 90.0
	gate.rotation.y = deg_to_rad(g_yaw)
	gate.position = _w(Vector3(4.5, t2, nz))
	gate.plate = Basis(Vector3.UP, deg_to_rad(g_yaw)).inverse() * (plate_w - gate.position)
	add_child(gate)
	_anchor["gate2"] = gate
	# walls either side of the doorway, from the fourth tier's face to the terrace edge
	var north_face: float = PYR_Z - _tier_half(3)          # -55
	var edge: float = PYR_Z - _tier_half(2)                # -62
	for span: Vector2 in [Vector2(north_face, nz + 2.6), Vector2(nz - 2.6, edge)]:
		var zc: float = (span.x + span.y) * 0.5
		var ln: float = absf(span.x - span.y)
		if ln > 0.05:
			var wc: Vector3 = _w(Vector3(4.5, t2 + 4.2, zc))
			kit.block(wc, _sz(Vector3(1.4, 8.4, ln)), Color(0.42, 0.43, 0.35), true, 0.0)
	_note(_w(Vector3(4.5, t2 + 4.2, nz)), _sz(Vector3(1.6, 8.4, 7.0)))
	for x: float in [14.0, 9.0]:
		_spike_bed(Vector3(x, t2, nz), 2.2, 6.6)
	_cp_bare(Vector3(1.5, t2, nz), _yaw + 90.0)
	r_walk(_w(Vector3(22.2, t1, -38.6)))
	r_wallrun(_w(Vector3(22.2, t1, -40.35)), _w(Vector3(20.95, t1 + 1.4, -45.1)), _w(Vector3(20.95, t1 + 1.4, -48.0)), _w(Vector3(24.4, t1 + 5.5, -51.9)))
	r_wallrun(Vector3.ZERO, _w(Vector3(24.4, t1 + 5.5, -51.9)), _w(Vector3(24.4, t1 + 5.5, -54.9)), _w(Vector3(21.1, t2, -60.6)), true, true)
	r_walk(_w(Vector3(18.0, t2, nz)))
	r_walk(_w(Vector3(15.7, t2, nz)))
	r_jump(_w(Vector3(15.45, t2, nz)), _w(Vector3(12.2, t2, nz)))
	r_jump(_w(Vector3(10.45, t2, nz)), _w(Vector3(7.2, t2, nz)))
	r_walk(_w(Vector3(1.8, t2, nz)))
	r_checkpoint()
	e.clear()


## A bed of stakes on a terrace (local floor centre; sx along x, sz along z): touch it and you are out.
func _spike_bed(c: Vector3, sx: float, sz: float) -> void:
	var k := KillZone.new()
	k.show_mesh = false
	k.size = _sz(Vector3(sx, 0.7, sz))
	k.position = _w(c + Vector3(0, 0.35, 0))
	add_child(k)
	_spike_beds.append([_w(c), _sz(Vector3(sx, 0, sz))])
	_note(_w(c + Vector3(0, 0.35, 0)), _sz(Vector3(sx, 0.7, sz)))


# ---- stage 18: The Altar - the summit stair's dart lanes, the buttresses, the altar --------------------

func _stage_18() -> void:
	_frame(_pyr_o, _pyr_yaw)
	var t2: float = _tier_top(2)
	var t3: float = _tier_top(3)
	var t4: float = _tier_top(4)
	var nz: float = PYR_Z - _tier_half(3) - TIER_STEP * 0.5     # -58.5
	var n3: float = PYR_Z - _tier_half(3)                       # -55: the fourth tier's north face
	var n4: float = PYR_Z - _tier_half(4)                       # -48: the summit's north face
	# two dart faces on the fourth tier firing out across the north terrace
	var traps: Array[JungleDarts] = []
	var dx: Array[float] = [-1.5, -5.6]
	for x: float in dx:
		var d: JungleDarts = _darts(Vector3(x, t2, n3 - 0.02), TIER_STEP, 1.4, 4.4, 0.0 if x > -3.0 else 0.45)
		d.rotation.y = deg_to_rad(_yaw + 90.0)
		traps.append(d)
	# up onto the fourth tier: a buttress against its face, a second standing free at the corner
	var f1: Dictionary = _ledge(Vector3(-10.6, t2 + 3.3, n3 - 1.1), Vector3(3.6, 3.3, 2.2), "alt")
	var f2: Dictionary = _ledge(Vector3(-16.2, t3, n3 - 1.1), Vector3(3.6, TIER_H, 2.2), "alt")
	# up onto the summit: two more buttresses
	var g1: Dictionary = _ledge(Vector3(-3.0, t3 + 3.3, n4 - 1.1), Vector3(3.6, 3.3, 2.2), "alt")
	var g2: Dictionary = _ledge(Vector3(2.6, t4, n4 - 1.1), Vector3(3.6, TIER_H, 2.2), "alt")
	# the altar on the summit
	var altar_top := Vector3(0, t4 + 3.3, PYR_Z + 1.0)
	_ledge(altar_top, Vector3(5.0, 3.3, 4.0), "accent")
	kit.finish(_w(altar_top), _yaw)
	_finish_pos = _w(altar_top)
	_anchor["altar"] = _w(altar_top)
	var lane: float = nz - 1.2
	r_walk(_w(Vector3(1.0, t2, lane)))
	for i: int in traps.size():
		var d: JungleDarts = traps[i]
		var x: float = dx[i]
		var at: Vector3 = _w(Vector3(x + 2.3, t2, lane))
		r_walk(at)
		_wait(func() -> bool: return d.is_safe_for(Game.course_time, 0.0, 2.2), at)
	r_walk(_w(Vector3(-6.6, t2, n3 - 1.1)))
	r_mantle(_w(Vector3(-6.45, t2, n3 - 1.1)), _w(Vector3(-10.0, t2 + 3.3, n3 - 1.1)))
	r_walk(_w(Vector3(-11.8, t2 + 3.3, n3 - 1.1)))
	r_mantle(_w(Vector3(-12.05, t2 + 3.3, n3 - 1.1)), _w(Vector3(-15.8, t3, n3 - 1.0)))
	r_jump(_w(Vector3(-14.75, t3, n3 - 0.35)), _w(Vector3(-11.0, t3, n3 + 2.6)))
	r_walk(_w(Vector3(-8.5, t3, n4 - 1.1)))
	r_mantle(_w(Vector3(-7.15, t3, n4 - 1.1)), _w(Vector3(-3.6, t3 + 3.3, n4 - 1.1)))
	r_walk(_w(Vector3(-1.4, t3 + 3.3, n4 - 1.1)))
	r_mantle(_w(Vector3(-1.55, t3 + 3.3, n4 - 1.1)), _w(Vector3(2.2, t4, n4 - 1.0)))
	r_walk(_w(Vector3(0, t4, altar_top.z - 5.6)))
	r_mantle(_w(Vector3(0, t4, altar_top.z - 4.35)), _w(altar_top + Vector3(0, 0, -0.4)))
	r_walk(_w(altar_top))
	f1.clear()
	f2.clear()
	g1.clear()
	g2.clear()


# ---- tells for the shared machines (pistons, crushers): a jade glyph that brightens and ticks ---------

## A glyph lamp at `at` that lights up over the last second before `left.call(t)` reaches 0.
func _tell(at: Vector3, left: Callable, yaw: float = INF) -> void:
	var t := JungleTell.new()
	t.left = left
	t.position = at
	t.rotation.y = deg_to_rad(_yaw if yaw == INF else yaw)
	add_child(t)


# ---- set dressing, particles, environment ------------------------------------------------------------

## The route as a polyline (every step's takeoff / landing / wall-run point and the checkpoints), for
## the scenery's clearance checks.
func _route_path() -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(Vector3(0, 0, 4.0))
	for step: Dictionary in route:
		for key: String in ["from", "entry", "exit", "top", "to"]:
			if step.has(key) and step[key] is Vector3:
				var p: Vector3 = step[key]
				if p != Vector3.ZERO:
					pts.append(p)
	return pts


func _surroundings() -> void:
	deco.solids = _solids
	deco.path = _route_path()
	deco.build_piers(_piers, WATER_Y)
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for p: Vector3 in _cp_world:
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	var mid: Vector3 = (lo + hi) * 0.5
	_anchor["mid"] = mid
	deco.water(Vector3(mid.x, WATER_Y, mid.z), Vector2(2400.0, 2400.0), Vector2(0.0, 0.6))
	_dress_stages()
	_forest()
	var pyr: Array = _anchor["pyramid"]
	deco.pyramid(pyr[0], pyr[1], 5, TIER_H, PYR_HALF, TIER_STEP)
	deco.far_scenery(mid, WATER_Y)
	_ambient_fx()


## Scenery tied to particular stages (the anchors they left).
func _dress_stages() -> void:
	var sun_dir: Vector3 = -_sun.global_basis.z if _sun != null else Vector3(0.3, -0.8, 0.5)
	# 1: the landing - stelae and braziers either side of the start, a stone face watching the river
	var s0: Vector3 = _anchor["start"]
	deco.stela(s0 + Vector3(-4.2, 0, -2.0), 0.0)
	deco.stela(s0 + Vector3(4.2, 0, -2.0), 0.0)
	deco.brazier(s0 + Vector3(-3.8, 0, 4.8))
	deco.brazier(s0 + Vector3(3.8, 0, 4.8))
	deco.stone_face(Vector3(-14.0, WATER_Y - 1.0, -16.0), Vector3(1, 0, 0.2), 9.0)
	deco.broken_stair(Vector3(9.0, WATER_Y, -14.0), PI * 0.5, 6)
	# 2: the river - lilies and reeds, mist on the water
	var rz: float = _anchor["river_z"]
	deco.lilies(Vector3(0, WATER_Y, rz - 30.0), Vector2(18.0, 30.0), 40, WATER_Y)
	JungleFx.mist(self, Vector3(0, WATER_Y + 1.5, rz - 30.0), Vector3(16.0, 1.0, 26.0), 14)
	# 3: the falls by the plunge pool
	var fp: Vector3 = _anchor["falls"]
	var fd: Vector3 = _anchor["falls_dir"]
	deco.falls(Vector3(fp.x, WATER_Y, fp.z), fd, fp.y - WATER_Y + 14.0, 8.0, true)
	# 6: the canopy - giant trees holding the branches
	for p: Vector3 in (_anchor["canopy"] as Array):
		# (the canopy run heads along world x: the trees stand either side of it)
		deco.giant_tree(Vector3(p.x, WATER_Y, p.z - 9.0), 46.0, 2.4)
		deco.giant_tree(Vector3(p.x - 4.0, WATER_Y, p.z + 9.0), 42.0, 2.2)
	# 7: the great trunk whose bark you run along
	var tk: Vector3 = _anchor["trunk"]
	_trunk(Vector3(tk.x, WATER_Y, tk.z), 52.0, 3.5)
	# 8: the idol whose mouth is the portal
	var idol: Array = _anchor["idol"]
	deco.stone_face(idol[0] - Vector3(0, 1.6, 0), Basis(Vector3.UP, deg_to_rad(idol[1])) * Vector3(0, 0, 1), 5.0, false)
	# 9: the wall of carved faces the stone tongues come out of
	var faces: Array = _anchor["faces"]
	var fw: Vector3 = faces[0]
	var fdir: Vector3 = faces[1]
	var along: Vector3 = fdir.cross(Vector3.UP)
	_wall_of_faces(fw, fdir, along)
	# 11: the boulder's niche, its clamps, the temple facade over the ramp
	var niche: Array = _anchor["niche"]
	_niche(niche[0], niche[1])
	var lip: Array = _anchor["lip"]
	deco.falls((lip[0] as Vector3) + (lip[1] as Vector3) * 26.0 + Vector3(0, WATER_Y - (lip[0] as Vector3).y, 0), -(lip[1] as Vector3), 30.0, 12.0, true)
	# 12: the gorge walls
	var gorge: Array = _anchor["gorge"]
	_gorge(gorge[0], gorge[1])
	# 13: the stelae the chimney is carved into
	var st: Array = _anchor["stelae"]
	_stela_backs(st[0], st[1], st[2])
	# 14: the moat
	var moat: Array = _anchor["moat"]
	var mw := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(66.0, 66.0)
	mw.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = preload("res://visual/jungle_water.gdshader")
	wm.set_shader_parameter("flow", Vector2(0.3, 0.1))
	mw.material_override = wm
	mw.position = moat[0]
	mw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mw)
	deco.lilies(moat[0], Vector2(30.0, 30.0), 30, (moat[0] as Vector3).y)
	# the idol plate that wakes the boulder
	var plate_at: Vector3 = _anchor["plate"]
	add_child(Look.cylinder(1.5, 0.06, Look.flat(JungleDecor.STONE.lightened(0.15), 0.8), plate_at + Vector3(0, 0.03, 0), -1.0, 24))
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.25
	tm.rings = 24
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, Look.flat(RED, 0.3, 0.0, 2.2), plate_at + Vector3(0, 0.07, 0))
	ring.scale = Vector3(1, 0.08, 1)
	add_child(ring)
	JungleFx.jade_rise(self, plate_at, 1.2, 3.0, 12)
	# braziers and jade sparks at every checkpoint
	for i: int in _cp_world.size():
		var c: Vector3 = _cp_world[i]
		JungleFx.jade_rise(self, c, 1.6, 4.0, 10)
	# god rays slanting down through the canopy along the course
	for i: int in range(1, _cp_world.size(), 2):
		var c: Vector3 = (_cp_world[i] + _cp_world[i - 1]) * 0.5
		deco.god_ray(c + Vector3(kit.rng.randf_range(-8.0, 8.0), -2.0, kit.rng.randf_range(-8.0, 8.0)), 60.0, 3.2, sun_dir)


## A colossal trunk (no buttress fins: the route runs right along its bark), its crown far above.
func _trunk(base: Vector3, height: float, radius: float) -> void:
	var bark: StandardMaterial3D = Look.flat(JungleDecor.BARK_PALE.lerp(JungleDecor.BARK, 0.4), 0.92)
	var t := Look.cylinder(radius, height, bark, base + Vector3(0, height * 0.5, 0), radius * 0.7, 14)
	add_child(t)
	var lm: ShaderMaterial = deco.leaf(0.2)
	for i: int in 5:
		var a: float = float(i) / 5.0 * TAU
		var blob := Look.sphere(1.0, lm, base + Vector3(cos(a) * 9.0, height + kit.rng.randf_range(-2.0, 2.0), sin(a) * 9.0))
		blob.scale = Vector3(10.0, 5.0, 10.0)
		add_child(blob)
	deco.vine_curtain(base + Vector3(-radius, height - 4.0, -radius), base + Vector3(radius, height - 4.0, radius), 24.0, 10)


## The wall the stone tongues come out of: a long carved wall with a face over each ram.
func _wall_of_faces(mid: Vector3, facing: Vector3, along: Vector3) -> void:
	var wall_c: Vector3 = mid - facing * 0.6 + Vector3(0, 1.0, 0)
	var size: Vector3 = (along * 34.0 + facing * 1.6).abs() + Vector3(0, 12.0, 0)
	var w := Look.box(size, deco.stone(JungleDecor.STONE, 0.7, size * 0.5), wall_c)
	add_child(w)
	for k: int in 3:
		var off: float = 8.5 - 8.5 * float(k)
		deco.stone_face(mid + along * off + facing * 0.4 + Vector3(0, 3.2, 0), facing, 3.6, false)


## The niche the ball waits in: a temple facade with pillars either side of the ball, a carved lintel
## above it, and two stone clamps holding it.
func _niche(at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var st: ShaderMaterial = deco.stone(JungleDecor.STONE, 0.5, Vector3(1, 4, 1))
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box((b * Vector3(1.2, 0, 3.0)).abs() + Vector3(0, 14.2, 0), st, at + b * Vector3(sx * 3.9, 0, 0.0) + Vector3(0, -2.7, 0)))
		var clamp_n := Look.box((b * Vector3(0.6, 0, 1.6)).abs() + Vector3(0, 0.8, 0), Look.flat(JungleDecor.STONE_DARK, 0.9), at + b * Vector3(sx * 3.0, 0, 0))
		add_child(clamp_n)
	add_child(Look.box((b * Vector3(9.0, 0, 3.4)).abs() + Vector3(0, 1.6, 0), st, at + Vector3(0, 4.3, 0)))
	var jade: StandardMaterial3D = Look.flat(JADE, 0.3, 0.0, 1.6)
	for i: int in 7:
		add_child(Look.box((b * Vector3(0.5, 0, 0.1)).abs() + Vector3(0, 0.5, 0), jade, at + b * Vector3((float(i) - 3.0) * 1.1, 0, 1.72) + Vector3(0, 4.3, 0)))
	deco.stone_face(at + Vector3(0, 5.2, 0) - b * Vector3(0, 0, 0.6), b * Vector3(0, 0, 1), 3.0, false)


## The gorge: rock walls either side of the vines (behind the shortcut's wall-run panels).
func _gorge(origin: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var rock: ShaderMaterial = deco.stone(JungleDecor.ROCK, 0.85, Vector3(4, 8, 22))
	for sx: float in [-1.0, 1.0]:
		var c: Vector3 = origin + b * Vector3(sx * 8.4, 0, -27.0)
		var top_y: float = origin.y + 12.0
		var size: Vector3 = (b * Vector3(10.0, 0, 42.0)).abs() + Vector3(0, top_y - WATER_Y, 0)
		add_child(Look.box(size, rock, Vector3(c.x, (top_y + WATER_Y) * 0.5, c.z)))
		deco.vine_curtain(origin + b * Vector3(sx * 3.5, 12.0, -8.0), origin + b * Vector3(sx * 3.5, 12.0, -48.0), 9.0, 14)
	deco.falls(origin + b * Vector3(-3.0, 0, -38.0) + Vector3(0, WATER_Y - origin.y, 0), b * Vector3(1, 0, 0), 12.0 + origin.y - WATER_Y, 6.0, false)


## The carved stelae the chimney's wall-run panels are set into.
func _stela_backs(p1: Vector3, p2: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var st: ShaderMaterial = deco.stone(JungleDecor.STONE, 0.45, Vector3(0.4, 5, 5))
	add_child(Look.box((b * Vector3(0.5, 0, 6.8)).abs() + Vector3(0, 11.0, 0), st, p1 + b * Vector3(0.55, 0, 0) + Vector3(0, 2.0, 0)))
	add_child(Look.box((b * Vector3(0.5, 0, 8.3)).abs() + Vector3(0, 16.5, 0), st, p2 + b * Vector3(-0.55, 0, 0) + Vector3(0, 4.75, 0)))


## Giant trees and palms round the whole course (each placement checked against the route).
func _forest() -> void:
	for f: Array in _stage_frames:
		var o: Vector3 = f[0]
		var b := Basis(Vector3.UP, deg_to_rad(float(f[1])))
		for k: int in 7:
			var side: float = -1.0 if k % 2 == 0 else 1.0
			var at: Vector3 = o + b * Vector3(side * kit.rng.randf_range(14.0, 36.0), 0, -kit.rng.randf_range(0.0, 55.0))
			deco.giant_tree(Vector3(at.x, WATER_Y, at.z), kit.rng.randf_range(34.0, 58.0), kit.rng.randf_range(1.6, 2.6))
		for k: int in 5:
			var side2: float = -1.0 if k % 2 == 0 else 1.0
			var at2: Vector3 = o + b * Vector3(side2 * kit.rng.randf_range(7.0, 16.0), 0, -kit.rng.randf_range(0.0, 50.0))
			deco.palm(Vector3(at2.x, WATER_Y, at2.z), kit.rng.randf_range(6.0, 11.0))
	# round the pyramid's hill
	var pyr: Array = _anchor["pyramid"]
	var pc: Vector3 = pyr[0]
	for k: int in 16:
		var a: float = float(k) / 16.0 * TAU
		var r: float = PYR_HALF + kit.rng.randf_range(10.0, 30.0)
		deco.giant_tree(Vector3(pc.x + cos(a) * r, WATER_Y, pc.z + sin(a) * r), kit.rng.randf_range(40.0, 62.0), kit.rng.randf_range(1.8, 2.8))
	deco.toucans(pc + Vector3(0, 52.0, 0), 34.0, 4, 8.0)
	var m: Vector3 = _anchor["mid"]
	deco.toucans(Vector3(m.x, 40.0, m.z), 90.0, 5, 9.0)
	for i: int in range(0, _cp_world.size(), 3):
		deco.toucans(_cp_world[i] + Vector3(0, 26.0, 0), 22.0, 2, 6.0)


## Air along the route: butterflies, pollen in the light, leaves falling, drips, mist on the water.
func _ambient_fx() -> void:
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3(0, 0, 4.0)
		var c: Vector3 = (here + prev) * 0.5 + Vector3(0, 3.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 8.0, 4.0, absf(here.z - prev.z) * 0.5 + 8.0)
		JungleFx.butterflies(self, c, ext * Vector3(0.7, 0.6, 0.7), 8)
		JungleFx.motes(self, c + Vector3(0, 2.0, 0), ext, 40)
		JungleFx.leaves(self, c + Vector3(0, 14.0, 0), ext * Vector3(1.0, 2.0, 1.0), 18)
		if c.y < WATER_Y + 14.0:
			JungleFx.mist(self, Vector3(c.x, WATER_Y + 1.2, c.z), Vector3(ext.x + 6.0, 0.8, ext.z + 6.0), 8)
	for p: Array in _piers:
		var top: Vector3 = p[0]
		var size: Vector3 = p[1]
		if size.x < 30.0 and kit.rng.randf() < 0.35:
			JungleFx.drips(self, top - Vector3(0, 0.3, 0), Vector3(size.x * 0.4, 0.05, size.z * 0.4), top.y - WATER_Y, 6)


# ---- materials, bursts, live effects -------------------------------------------------------------------

const STONE_SHADER: Shader = preload("res://visual/jungle_stone.gdshader")


## Swap every walkable surface to the mossy temple stone shader (same colours).
func _jungle_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = STONE_SHADER
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		var half: Vector3 = sm.get_shader_parameter("half_size")
		r.set_shader_parameter("mossy", 0.35 if half.x > 20.0 else 0.6)
		m.material_override = r


var _cp_bursts: Dictionary = {}


## Banked-stage feedback: a burst of jade and gold glints and a puff of leaves.
func _checkpoint_fx() -> void:
	for cp: Checkpoint in _cp_nodes:
		var at: Vector3 = cp.global_position
		_cp_bursts[cp] = [JungleFx.glints(self, at + Vector3(0, 1.0, 0), 50, 7.0), JungleFx.leaf_burst(self, at + Vector3(0, 0.8, 0), 30, 5.0)]
		cp.reached.connect(func(which: Checkpoint) -> void:
			if which.index > current_checkpoint:
				for p: GPUParticles3D in _cp_bursts[which]:
					p.restart()
					p.emitting = true)


## Bursts that fire when the player arrives at a spot (portal exits): {"at", "p", "cool"}
var _arrivals: Array[Dictionary] = []


func _arrival(at: Vector3) -> void:
	var a: GPUParticles3D = JungleFx.glints(self, at + Vector3(0, 1.0, 0), 34, 5.0)
	var b: GPUParticles3D = JungleFx.leaf_burst(self, at + Vector3(0, 0.6, 0), 20, 4.0)
	_arrivals.append({"at": at, "p": [a, b], "cool": 0.0})


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


## The finish: a column of jade light shoots up from the altar, glints and leaves burst, the braziers
## flare, and a flock of toucans takes off over the summit.
func _finish_sequence() -> void:
	var col: GPUParticles3D = JungleFx.jade_column(self, _finish_pos, 100)
	col.restart()
	col.emitting = true
	var g: GPUParticles3D = JungleFx.glints(self, _finish_pos + Vector3(0, 1.4, 0), 120, 10.0)
	g.restart()
	g.emitting = true
	var lb: GPUParticles3D = JungleFx.leaf_burst(self, _finish_pos + Vector3(0, 1.0, 0), 60, 8.0)
	lb.restart()
	lb.emitting = true
	deco.toucans(_finish_pos + Vector3(0, 8.0, 0), 12.0, 6, 11.0)
	WorldAudio.at(self, "jungle_altar", _finish_pos, 1.0, 120.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.5, 1.0, 0.75)
	flash.light_energy = 6.0
	flash.omni_range = 26.0
	flash.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.6)
	await get_tree().create_timer(1.1).timeout


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
	_env.sky = JungleSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.74, 0.6)
	_env.ambient_light_energy = 0.62
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.46, 0.58, 0.44)
	_env.fog_density = 0.0026
	_env.fog_aerial_perspective = 0.15
	_env.fog_sky_affect = 0.15
	_env.fog_sun_scatter = 0.1
	_env.fog_height = WATER_Y + 7.0
	_env.fog_height_density = 0.035
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 1.2
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.16
	_env.adjustment_contrast = 1.12
	_sun.light_color = Color(1.0, 0.93, 0.76)
	_sun.light_energy = 2.2
	_sun.rotation_degrees = Vector3(-52, 160, 0)
	_sun.shadow_blur = 1.0
	_sun.light_angular_distance = 0.5
	# the "fill" becomes the green light bounced up off the forest
	_fill.light_color = Color(0.5, 0.75, 0.5)
	_fill.light_energy = 0.32
	_fill.rotation_degrees = Vector3(-30, -20, 0)
