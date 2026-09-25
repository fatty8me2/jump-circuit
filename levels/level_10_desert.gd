extends LevelBase
## 10. SCARAB SANDS - an ancient desert sun temple full of traps. Eighteen stages, each ending on a
## checkpoint: out across ruined colonnades over a sea of towering dunes at golden hour (colossal
## pyramids, buried colossi and a sandstorm wall on the horizon, oases at the checkpoints), up the
## great stair through the temple gate, and on through glyph-carved halls of gold and turquoise,
## torches and dusty sunbeams, to the sanctum under the great sun disc. The light sinks toward
## sunset as you go.
##
##  1 Dune Gate        column drums over the sand sea, the first spike-trap plate
##                     [shortcut: mantle the broken obelisk, leap past the plate]
##  2 Colonnade        MANTLE the fallen capital, hop the column tops, WALL RUN the frieze over the gap
##  3 Quicksand Flats  quicksand stepping pits (short, sinking jumps), the sand river running back
##                     at you with a spike plate on it, MANTLE out of the flow
##  4 Dust Devil Mesa  ride a whirlwind up the mesa, another one across the chasm
##  5 Mirage Road      BRANCH: a wave of mirage slabs over the sand sea | MANTLE the arch foot and
##                     WALL RUN its flank
##  6 Dune Slide       the slip face flings you ~15 m over the chasm (23 m/s), a sun pad to the plateau
##  7 Scarab Bridge    beams swept by scarab swarms (sweepers), stone rams (PISTONS), crumbling slabs
##  8 Temple Stair     MANTLE the great steps: over a spike plate, under a falling block (CRUSHER),
##                     through the temple gate
##  9 Hall of Spikes   BRANCH: five spike plates firing in turn and a dart LASER | MANTLE up to the
##                     gallery and WALL RUN the glyph wall
## 10 Sandfall Gallery narrow beams over the pit under curtains of pouring sand, a dart LASER
## 11 Blade Crypt      bronze blades swinging across every stepping stone, crumbling slabs
## 12 Sun Well         a whirlwind up the well, a chimney of three WALL RUNS, MANTLE out at the top
## 13 Sundial Court    BRANCH: ride the great spinning sundial | two MANTLES up the gnomon and its
##                     sun ring (PORTAL)
## 14 Tomb of Kings    crumbling slabs and mirages, the rams' corridor on a green wave (PISTONS)
##                     [shortcut: a 90% leap to the hidden tomb, time its sliding door, its PORTAL]
## 15 THE BOULDER RUN  step on the sun plate: a colossal carved ball drops from the ceiling and rolls
##                     after you down the corridor - hop, leap, down the ramp, WALL RUN the pit it
##                     falls into
## 16 Quicksand Crypt  MANTLE out of the sinking sand, a spike plate, a whirlwind up to the ledge
##                     [shortcut: WALL RUN the crypt wall over the quicksand and the ledge]
## 17 Sandfall Stair   three MANTLES up through pouring sand, under a CRUSHER
##                     [shortcut: WALL RUN the flank and MANTLE the top step out of the kick]
## 18 Sanctum of Sun   mirages over the pit, the dart gate, the last WALL RUN, MANTLE onto the altar,
##                     the finish under the great sun disc
##
## Desert mechanics (own scripts): DesertSpikeTrap (spike plates on a rhythm, glyph warning),
## DesertSandfall (pouring sand curtains, timing gates), DesertQuicksand (sinking, clinging sand),
## DesertDustDevil (wandering whirlwinds you ride), DesertMirage (heat-haze platforms), and the
## set piece DesertBoulder. Route variants for the bot: 0 = main line, 1 = every alternative
## branch, 2 = main line + every shortcut.

const STONE_SHADER: Shader = preload("res://visual/desert_stone.gdshader")

const GOLD := Color(1.0, 0.72, 0.22)
const TURQ := Color(0.2, 0.9, 0.85)
const RED := Color(1.0, 0.32, 0.2)

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: DesertDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_nodes: Array[Checkpoint] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Stage frames (origin, yaw) and stage end points, for hall and ambient dressing.
var _stage_frames: Array[Array] = []
## Bursts that fire when the player arrives at a spot (portal exits): {"at", "p": [GPUParticles3D], "cool"}
var _arrivals: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "desert"
	music_track = "desert"
	kill_y = -34.0
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


## Sandstone block (walkable) with a pier of masonry under it down toward the sand.
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, pier: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if pier:
		_pier(c - Vector3(0, thick, 0), sx * 0.7, sz * 0.7)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A fallen column drum (round landing) on a slimmer shaft.
func _drum(c: Vector3, r: float, style: String = "main", thick: float = 0.8, pier: bool = true) -> Dictionary:
	var body: StaticBody3D = kit.disc(_w(c), r, thick, style, 0.0)
	if pier:
		var h: float = clampf(_w(c).y + 30.0, 6.0, 60.0)
		var col := Look.cylinder(r * 0.78, h, deco.stone(DesertDecor.SANDSTONE, 1.0, -1.0, 0.9, Vector2(3.0, 1.2)), _w(c - Vector3(0, thick + h * 0.5, 0)), r * 0.82, 14)
		add_child(col)
	return {"c": c, "r": r, "node": body}


## Masonry pier hanging under a landing, down toward the sand sea (decor, no collision).
func _pier(top: Vector3, sx: float, sz: float) -> void:
	var h: float = clampf(_w(top).y + 30.0, 4.0, 60.0)
	var p := Look.box(Vector3(maxf(sx, 0.5), h, maxf(sz, 0.5)), deco.stone(DesertDecor.SANDSTONE, 1.0, -1.0, 0.9, Vector2(2.4, 1.2)), _w(top - Vector3(0, h * 0.5, 0)))
	p.rotation.y = deg_to_rad(_yaw)
	add_child(p)


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


## Kill brick dressed as a row of bronze spikes (a permanent trap).
func _haz(c: Vector3, size: Vector3, yaw_extra: float = 0.0) -> void:
	kit.hazard(_w(c), size, _yaw + yaw_extra)


## Spike-trap plate set into the floor at local `c` (floor top), footprint (sx, sz).
func _spikes(c: Vector3, sx: float, sz: float, period: float, on: float, phase: float, height: float = 1.0) -> DesertSpikeTrap:
	var t := DesertSpikeTrap.new()
	t.size = Vector3(sx, height, sz)
	t.period = period
	t.on_fraction = on
	t.phase = phase
	t.rotation.y = deg_to_rad(_yaw)
	t.position = _w(c)
	add_child(t)
	return t


## Quicksand pit at local `c` (sand surface), footprint (sx, sz), framed by a stone rim.
func _quicksand(c: Vector3, sx: float, sz: float, rim: float = 0.35, pier: bool = true) -> Dictionary:
	var q := DesertQuicksand.new()
	q.size = Vector2(sx, sz) if absf(fmod(absf(_yaw), 180.0) - 90.0) >= 1.0 else Vector2(sz, sx)
	q.position = _w(c)
	add_child(q)
	for s: float in [-1.0, 1.0]:
		kit.plat(_w(c + Vector3(s * (sx * 0.5 + rim * 0.5), 0.0, 0)), _sz(Vector3(rim, 0.8, sz + rim * 2.0)), "alt", 0.0)
		kit.plat(_w(c + Vector3(0, 0.0, s * (sz * 0.5 + rim * 0.5))), _sz(Vector3(sx, 0.8, rim)), "alt", 0.0)
	# the pit's floor box (under the sinking sand, out of sight)
	kit.block(_w(c - Vector3(0, 1.9, 0)), _sz(Vector3(sx + rim * 2.0, 0.4, sz + rim * 2.0)), DesertDecor.SANDSTONE, false)
	if pier:
		_pier(c - Vector3(0, 2.0, 0), sx * 0.8, sz * 0.8)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5, "node": q}


func _wind(c: Vector3, size: Vector3, push: Vector3, max_rise: float = 14.0) -> WindZone:
	return kit.wind(_w(c), _sz(size), _b * push, max_rise)


## Dust devil with its foot at local `c`, wandering through local offsets `pts`.
func _devil(c: Vector3, height: float, pts: Array[Vector3], period: float, phase: float = 0.0, radius: float = 1.7) -> DesertDustDevil:
	var dd := DesertDustDevil.new()
	dd.radius = radius
	dd.height = height
	var wp: Array[Vector3] = []
	for p: Vector3 in pts:
		wp.append(_b * p)
	if wp.is_empty():
		wp.append(Vector3.ZERO)
	dd.points = wp
	dd.period = period
	dd.phase = phase
	dd.position = _w(c)
	add_child(dd)
	return dd


## Mirage slab whose top is at local `top`.
func _mirage(top: Vector3, sx: float, sz: float, period: float, on: float, phase: float) -> DesertMirage:
	var m := DesertMirage.new()
	m.size = _sz(Vector3(sx, 0.5, sz))
	m.period = period
	m.on_fraction = on
	m.phase = phase
	m.position = _w(top) - Vector3(0, 0.25, 0)
	add_child(m)
	return m


## Sand curtain across the route at local floor point `c` (x across the route).
func _sandfall(c: Vector3, width: float, height: float, period: float, on: float, phase: float, depth: float = 1.2) -> DesertSandfall:
	var s := DesertSandfall.new()
	s.width = width
	s.height = height
	s.depth = depth
	s.period = period
	s.on_fraction = on
	s.phase = phase
	s.rotation.y = deg_to_rad(_yaw)
	s.position = _w(c)
	add_child(s)
	# the lintel with the slot the sand pours out of
	var lintel := Look.box(Vector3(width + 1.6, 0.9, depth + 1.0), deco.stone(DesertDecor.PALE, 1.0, -1.0, 0.9, Vector2(1.8, 0.9)), _w(c + Vector3(0, height + 0.45, 0)))
	lintel.rotation.y = deg_to_rad(_yaw)
	add_child(lintel)
	for sx: float in [-1.0, 1.0]:
		var post := Look.box(Vector3(0.7, height + 0.9, 0.9), deco.stone(DesertDecor.SANDSTONE, 1.0, height - 0.5, 0.6, Vector2(1.2, 0.8)), _w(c + Vector3(sx * (width * 0.5 + 0.45), (height + 0.9) * 0.5 - 0.4, 0)))
		post.rotation.y = deg_to_rad(_yaw)
		add_child(post)
	return s


## Checkpoint landing facing the next stage's heading (_next_yaw).
func _cp(c: Vector3, size: float = 6.0, oasis: bool = false) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	_cp_nodes.append(cp)
	var h: float = size * 0.5 - 0.45
	if oasis:
		_oasis_terrace(c, size)
	else:
		for s: float in [-1.0, 1.0]:
			deco.brazier(_w(c + Vector3(s * h, 0, h)), 1.3, s < 0.0, 0.8)
	# banked-stage feedback: a fountain of sand and gold glints
	var burst: GPUParticles3D = DesertFx.sand_burst(self, _w(c) + Vector3(0, 0.3, 0), 1.6, 36, 6.0)
	var glints: GPUParticles3D = DesertFx.glints(self, _w(c) + Vector3(0, 0.8, 0), GOLD, 40, 7.0)
	_cp_bursts[cp] = [burst, glints]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


## A sand terrace beside a checkpoint with an oasis pool and palms (on the side away from
## where the next stage leaves).
func _oasis_terrace(c: Vector3, size: float) -> void:
	var turn: float = wrapf(_next_yaw - _yaw, -180.0, 180.0)
	var side: float = 1.0 if turn < -1.0 else -1.0
	var tc: Vector3 = c + Vector3(side * (size * 0.5 + 3.8), -0.35, 0.6)
	kit.plat(_w(tc), _sz(Vector3(7.6, 1.0, 7.4)), "alt", 0.0)
	_pier(tc - Vector3(0, 1.0, 0), 5.0, 5.0)
	deco.oasis(_w(tc + Vector3(side * 0.6, 0.02, 0)), 2.2, 3)


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Position-hold flight (bot): steer toward `to` (a point, or a Callable returning one) until
## `until` is true (or, without it, until landing).
func _fly(to: Variant, until: Variant = null, jump_from: Variant = null) -> void:
	var s: Dictionary = {"kind": "desert_fly", "to": to}
	if until != null:
		s["until"] = until
	if jump_from != null:
		s["jump_from"] = jump_from
	route.append(s)


static func _spikes_safe(t: DesertSpikeTrap, a: float, b: float) -> bool:
	return t.is_safe_for(Game.course_time, a, b)


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = DesertDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		_stage_frames.append([_o, _yaw])
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	_stage_frames.append([_o, _yaw])
	_stage_18()
	_surroundings()
	_desert_materials()
	_dev_hooks()


# ---- stage 1: Dune Gate - drums over the sand sea, the first spike trap -------------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	_pier(Vector3(0, -2, 0), 10.0, 10.0)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	# the gateway you start under: two pylon towers and a lintel with the sun disc
	for sx: float in [-1.0, 1.0]:
		kit.block(_w(Vector3(sx * 4.6, 4.5, -5.4)), Vector3(2.4, 9.0, 2.0), DesertDecor.SANDSTONE, true, _yaw)
		deco.brazier(_w(Vector3(sx * 5.8, 0, -3.2)), 1.5, sx < 0.0)
	var gate := Look.box(Vector3(11.8, 1.4, 2.4), deco.stone(DesertDecor.PALE, -0.8, 0.8, 0.6, Vector2(1.8, 0.9)), _w(Vector3(0, 9.4, -5.4)))
	gate.rotation.y = deg_to_rad(_yaw)
	add_child(gate)
	deco.glyph(_w(Vector3(0, 9.4, -4.18)), _d(Vector3(0, 0, 1)), 1.6, 0.05, GOLD, 2.0)
	var a1: Dictionary = _blk(Vector3(0, 0, -12.4), 3.0, 3.0)
	var a2: Dictionary = _drum(Vector3(3.0, 1.0, -18.0), 1.3)
	var a3: Dictionary = _blk(Vector3(0.4, 2.0, -23.6), 2.4, 2.4, "alt")
	var slab: Dictionary = _blk(Vector3(0.4, 2.0, -32.4), 3.0, 9.0)
	var trap: DesertSpikeTrap = _spikes(Vector3(0.4, 2.0, -32.4), 3.0, 2.6, 2.4, 0.42, 0.0)
	var cp: Dictionary = _cp(Vector3(0.4, 2.0, -43.4), 6.0, true)
	_hop(start, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	# SHORTCUT: the broken obelisk beside a3 - mantle it and leap past the trap plate
	var obl: Dictionary = _ledge(Vector3(-2.4, 5.3, -27.8), Vector3(1.8, 7.3, 1.8), "accent")
	_pier(Vector3(-2.4, -2.0, -27.8), 1.4, 1.4)
	if route_variant == 2:
		r_mantle(_w(_edge(a3, obl["c"])), _w((obl["c"] as Vector3) + Vector3(0, 0, 0.2)))
		r_walk(_w(Vector3(-2.3, 5.3, -28.2)))
		_wait(func() -> bool: return _spikes_safe(trap, 0.2, 1.3))
		r_jump(_w(Vector3(-2.1, 5.3, -28.35)), _w(Vector3(0.4, 2.0, -35.3)))
	else:
		_hop(a3, slab, Vector3(0, 0, 3.4))
		r_walk(_w(Vector3(0.4, 2.0, -29.4)))
		_wait(func() -> bool: return _spikes_safe(trap, 0.05, 0.75))
		r_walk(_w(Vector3(0.4, 2.0, -35.6)))
	_hop(slab, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Colonnade - mantle the capital, the column tops, run the frieze wall over the gap ----

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
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
	# the ruined frieze wall behind the run panel, and the colonnade it once belonged to
	var fr := Look.box(Vector3(0.9, 11.0, 17.0), deco.stone(DesertDecor.SANDSTONE, -3.0, 4.5, 1.0), _w(Vector3(3.3, 3.5, -39.9)))
	fr.rotation.y = deg_to_rad(_yaw)
	add_child(fr)
	for z: float in [-10.0, -16.0, -22.0]:
		deco.column(_w(Vector3(-5.5, -8.0, z)), 14.0 + kit.rng.randf_range(-3.0, 3.0), 0.9, z < -20.0)
	return cp["c"]


# ---- stage 3: Quicksand Flats - quicksand stepping stones, the sand river, a mantle out ----------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var s1: Dictionary = _blk(Vector3(0, -1.0, -7.8), 2.6, 2.6)
	var q1: Dictionary = _quicksand(Vector3(0.3, -1.0, -13.4), 2.6, 2.6)
	var q2: Dictionary = _quicksand(Vector3(-1.2, -1.4, -18.7), 2.4, 2.4)
	var s2: Dictionary = _blk(Vector3(0, -1.4, -23.4), 2.0, 2.0, "alt")
	# the sand river: a channel of flowing sand running back at you, a trap plate halfway up it
	kit.conveyor(_w(Vector3(0, -1.4, -30.9)), Vector3(2.4, 0.4, 10.0), _yaw + 180.0, 5.0)
	_pier(Vector3(0, -1.8, -30.9), 2.0, 9.0)
	var trap: DesertSpikeTrap = _spikes(Vector3(0, -1.4, -31.0), 2.4, 1.4, 2.2, 0.36, 0.3, 0.9)
	var top: Dictionary = _ledge(Vector3(0, 1.8, -38.6), Vector3(3.4, 6.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 1.8, -47.8), 6.0, true)
	_hop(cp0, s1)
	_hop(s1, q1)
	_hop(q1, q2, Vector3.ZERO, true, 6.0)
	_hop(q2, s2, Vector3(0, 0, 0.3), true, 6.0)
	r_jump(_w(Vector3(0, -1.4, -24.05)), _w(Vector3(0, -1.4, -27.6)))
	_wait(func() -> bool: return _spikes_safe(trap, 0.0, 1.1), _w(Vector3(0, -1.4, -28.9)))
	r_mantle(_w(Vector3(0, -1.4, -34.9)), _w(Vector3(0, 1.8, -38.2)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# sand spilling off the end of the river into the dark
	DesertFx.trickle(self, _w(Vector3(0, -1.5, -25.9)), 18.0, 40)
	for x: float in [-0.8, 0.0, 0.8]:
		DesertFx.trickle(self, _w(Vector3(x, -1.5, -25.95)), 14.0, 16)
	return cp["c"]


# ---- stage 4: Dust Devil Mesa - ride a whirlwind up the mesa, another across the gap -----------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var basin: Dictionary = _blk(Vector3(0, -3.0, -10.5), 7.0, 9.0, "alt", 1.2)
	var d1: DesertDustDevil = _devil(Vector3(0, -3.0, -12.2), 11.5, [Vector3(-1.0, 0, 0), Vector3(1.0, 0, 0)], 4.0)
	d1.carry = 1.0
	d1.center_pull = 1.0
	var mesa1: Dictionary = _blk(Vector3(0, 5.5, -17.7), 4.0, 5.0, "main", 1.2)
	var d2: DesertDustDevil = _devil(Vector3(0, -3.0, -23.2), 11.5, [Vector3.ZERO, Vector3(0, 0, -12.0)], 7.0)
	var mesa2: Dictionary = _blk(Vector3(0, 5.5, -40.7), 4.0, 5.0, "main", 1.2)
	var cp: Dictionary = _cp(Vector3(0, 5.5, -50.9))
	# the basin floor the second devil wanders over (far below the mesas): fall in and ride it back up
	_blk(Vector3(0, -3.0, -29.2), 5.0, 16.0, "alt", 1.2)
	_hop(cp0, basin, Vector3(0, 0, 3.0))
	r_walk(_w(Vector3(0, -3.0, -10.9)))
	var y1: float = _w(mesa1["c"]).y
	_fly(func() -> Vector3: return d1.global_position, func() -> bool: return player.global_position.y > y1 + 2.4)
	_fly(_w((mesa1["c"] as Vector3) + Vector3(0, 0, 0.5)))
	r_walk(_w(Vector3(0, 5.5, -19.0)))
	var near_p: Vector3 = _w(Vector3(0, -3.0, -23.2))
	var far_p: Vector3 = _w(Vector3(0, -3.0, -35.2))
	_wait(func() -> bool: return Vector2(d2.global_position.x - near_p.x, d2.global_position.z - near_p.z).length() < 0.4)
	var y2: float = _w(mesa2["c"]).y
	_fly(func() -> Vector3: return d2.global_position, func() -> bool:
		return Vector2(d2.global_position.x - far_p.x, d2.global_position.z - far_p.z).length() < 0.4 and player.global_position.y > y2 + 2.4,
		_w(Vector3(0, 5.5, -19.85)))
	_fly(_w((mesa2["c"] as Vector3) + Vector3(0, 0, 0.8)))
	_hop(mesa2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Mirage Road (BRANCH) - a wave of mirages over the sand sea, or the wind-carved arch ----

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, false)
	_pier(Vector3(-3.5, -1.0, -8.0), 3.0, 3.0)
	_pier(Vector3(3.5, -1.0, -8.0), 3.0, 3.0)
	# LEFT (turquoise): the mirage road - five slabs of heat haze, real one after another
	var mz: Array[Vector3] = [Vector3(-3.5, 0.0, -16.0), Vector3(-3.5, 0.6, -22.05), Vector3(-2.4, 1.2, -27.95), Vector3(-3.4, 1.2, -35.0)]
	var mirages: Array[DesertMirage] = []
	for i: int in mz.size():
		mirages.append(_mirage(mz[i], 2.1, 2.1, 3.0, 0.5, fposmod(-0.25 * float(i), 1.0)))
	var merge: Dictionary = _blk(Vector3(0, 1.2, -42.8), 12.0, 4.0, "main", 1.0, false)
	_pier(Vector3(-3.5, 0.2, -42.8), 3.0, 3.0)
	_pier(Vector3(3.5, 0.2, -42.8), 3.0, 3.0)
	# RIGHT (gold): the arch - mantle its foot, run its flank, drop off the far pier
	var l1: Dictionary = _ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 6.3, 3.2), "alt")
	kit.wallrun(_w(Vector3(6.5, 4.5, -24.7)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(3.8, 3.3, -37.0), 3.6, 4.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 1.2, -51.3), 6.0, true)
	# the arch itself: the wall run is its inner face; a great span overhead to the far pier
	var arch_mat: ShaderMaterial = deco.stone(Color(0.86, 0.58, 0.36), 1.0, -1.0, 0.9, Vector2(3.0, 1.4))
	var flank := Look.box(Vector3(1.4, 14.0, 18.0), arch_mat, _w(Vector3(7.5, 1.0, -24.7)))
	flank.rotation.y = deg_to_rad(_yaw)
	add_child(flank)
	var span := Look.box(Vector3(3.0, 2.6, 10.0), arch_mat, _w(Vector3(7.8, 9.2, -35.0)))
	span.rotation.y = deg_to_rad(_yaw)
	add_child(span)
	var foot := Look.box(Vector3(3.0, 20.0, 4.0), arch_mat, _w(Vector3(8.0, 0.4, -40.0)))
	foot.rotation.y = deg_to_rad(_yaw)
	add_child(foot)
	# signposts at the fork: turquoise banners for the mirages, gold for the climb
	kit.banner(_w(Vector3(-5.6, 0, -7.0)), 3.6, TURQ, _yaw)
	kit.banner(_w(Vector3(-1.6, 0, -7.0)), 3.6, TURQ, _yaw)
	kit.banner(_w(Vector3(2.4, 0, -7.0)), 3.6, GOLD, _yaw)
	kit.banner(_w(Vector3(5.6, 0, -7.0)), 3.6, GOLD, _yaw)
	kit.glow_strip(_w(Vector3(-3.5, 0.03, -9.4)), _sz(Vector3(1.4, 0.05, 0.9)), TURQ)
	kit.glow_strip(_w(Vector3(4.0, 0.03, -9.4)), _sz(Vector3(1.4, 0.05, 0.9)), GOLD)
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.4)))
		var starts: Array[float] = [0.6, 1.35, 2.1, 2.85]
		_wait(func() -> bool:
			for i: int in mirages.size():
				if not _mirage_ok(mirages[i], starts[i] - 0.1, starts[i] + 0.55):
					return false
			return true)
		var prev: Dictionary = _area(Vector3(-3.5, 0, -8.0), 1.5, 2.0)
		for i: int in mz.size():
			var m: Dictionary = _area(mz[i], 1.05, 1.05)
			_hop(prev, m)
			prev = m
		_hop(prev, merge, Vector3(-3.0, 0, 0.8))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(4.3, 3.3, -14.85)), _w(Vector3(6.0, 4.7, -18.8)), _w(Vector3(6.0, 4.7, -29.7)), _w(Vector3(3.8, 3.3, -36.3)))
		_hop(l2, merge, Vector3(3.0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


static func _mirage_ok(m: DesertMirage, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not m.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


# ---- stage 6: Dune Slide - the slip face flings you over the chasm, a sun pad up to the plateau ----

func _stage_6() -> Vector3:
	# the slip face: 16 m of loose sand at 25 degrees down to a lip
	var pitch: float = -25.0
	var slide_len: float = 16.0
	var drop: float = slide_len * sin(deg_to_rad(25.0))
	var run: float = slide_len * cos(deg_to_rad(25.0))
	var sc := Vector3(0, -0.05 - drop * 0.5, -3.1 - run * 0.5)
	kit.slick(_w(sc), Vector3(3.2, 0.4, slide_len), _yaw, pitch)
	var lip_z: float = -3.1 - run
	var lip_y: float = -0.05 - drop
	_pier(Vector3(0, lip_y - 0.5, lip_z + 1.0), 2.4, 2.4)
	var land: Dictionary = _blk(Vector3(0, lip_y - 1.0, lip_z - 15.2 - 4.0), 3.4, 8.0)
	var pad_p := Vector3(0, lip_y - 1.0, lip_z - 15.2 - 6.2)
	var pad: BouncePad = kit.pad(_w(pad_p), 21.0, 0.0, 0.0, 1.2)
	var plateau: Dictionary = _blk(Vector3(0, lip_y + 4.8, lip_z - 15.2 - 13.4), 4.0, 5.0, "main", 1.4)
	var cp: Dictionary = _cp(Vector3(0, lip_y + 4.8, lip_z - 15.2 - 23.0))
	# the dune the slip face belongs to, streaming sand off its crest
	deco.dune(_w(Vector3(-9.0, lip_y - 20.0, lip_z + 2.0)), Vector3(12.0, 24.0, 18.0), 0.3, true)
	deco.dune(_w(Vector3(9.0, lip_y - 22.0, lip_z + 4.0)), Vector3(10.0, 22.0, 16.0), 1.2)
	for i: int in 3:
		DesertFx.trickle(self, _w(Vector3(-1.0 + float(i), lip_y - 0.3, lip_z - 0.2)), 20.0, 18)
	r_walk(_w(Vector3(0, 0, -2.4)))
	r_jump(_w(Vector3(0, lip_y, lip_z + 0.35)), _w((land["c"] as Vector3) + Vector3(0, 0, 2.2)))
	route[route.size() - 1]["speed"] = 23.0
	r_walk(_w(pad_p + Vector3(0, 0, 1.4)))
	r_pad(_w(pad_p), _w((plateau["c"] as Vector3) + Vector3(0, 0, 0.6)))
	_hop(plateau, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	pad.set_meta("sun_pad", true)
	return cp["c"]


# ---- stage 7: Scarab Bridge - scarab swarms sweeping the beams, stone rams, crumbling slabs --------

func _stage_7() -> Vector3:
	var b1: Dictionary = _blk(Vector3(0, 0, -9.6), 1.4, 8.2, "alt", 0.8)
	var sw1: Sweeper = _scarabs(Vector3(0, 0, -10.6), 3.0, 2, 3.2, 0.0)
	var b2: Dictionary = _blk(Vector3(0, 0.6, -18.8), 1.4, 6.0, "alt", 0.8)
	var rams: Array[Piston] = []
	var rz: Array[float] = [-17.8, -21.0]
	for i: int in 2:
		rams.append(kit.piston(_w(Vector3(3.2, 1.9, rz[i])), Vector3(1.8, 1.3, 1.4), _yaw + 90.0, 3.0, 2.6, [0.1, 0.962][i], 8.0))
		kit.block(_w(Vector3(4.6, 1.4, rz[i])), Vector3(2.4, 3.0, 2.2), DesertDecor.SANDSTONE, true, _yaw)
	kit.collapse(_w(Vector3(-0.8, 0.6, -25.2)), 2.0, 0.5, 2.4)
	kit.collapse(_w(Vector3(0.6, 1.2, -30.4)), 2.0, 0.5, 2.4)
	var b4: Dictionary = _blk(Vector3(0, 1.2, -39.1), 1.4, 10.0, "alt", 0.8)
	var sw2: Sweeper = _scarabs(Vector3(0, 1.2, -39.4), 3.0, 2, 2.8, 0.3)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -50.0))
	# the bridge's pylons (the rams' side has the ram housings instead)
	for z: float in [-5.2, -14.6, -23.0, -34.0, -45.0]:
		for sx: float in [-1.0, 1.0]:
			if sx > 0.0 and z > -23.0 and z < -14.0:
				continue
			kit.block(_w(Vector3(sx * 2.4, 1.2, z)), Vector3(0.9, 5.0, 0.9), DesertDecor.SANDSTONE, false, _yaw)
	var land1: Vector3 = _w(Vector3(0, 0, -6.2))
	_wait(func() -> bool: return _bars_far(sw1, land1, 0.3, 1.0, 0.7))
	r_jump(_w(Vector3(0, 0, -2.65)), land1)
	route.append({"kind": "b_sweep", "to": _w(Vector3(0, 0, -13.3)), "sweeper": sw1, "tol": 0.5})
	r_jump(_w(Vector3(0, 0, -13.35)), _w(Vector3(0, 0.6, -16.2)))
	var p0: Piston = rams[0]
	var p1: Piston = rams[1]
	_wait(func() -> bool: return _ram_clear(p0, 0.0, 0.5) and _ram_clear(p1, 0.4, 1.0))
	r_walk(_w(Vector3(0, 0.6, -21.4)))
	r_jump(_w(Vector3(0, 0.6, -21.45)), _w(Vector3(-0.8, 0.6, -25.2)))
	r_jump(_w(Vector3(-0.6, 0.6, -25.8)), _w(Vector3(0.6, 1.2, -30.4)))
	r_jump(_w(Vector3(0.5, 1.2, -31.0)), _w(Vector3(0, 1.2, -35.0)))
	route.append({"kind": "b_sweep", "to": _w(Vector3(0, 1.2, -43.4)), "sweeper": sw2, "tol": 0.5})
	_hop(b4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	b1.clear()
	b2.clear()
	return cp["c"]


## No sweeper bar comes within `min_ang` (rad) of world point `p` during [now + a, now + b].
static func _bars_far(sw: Sweeper, p: Vector3, a: float, b: float, min_ang: float) -> bool:
	var rel: Vector3 = p - sw.global_position
	var me: float = atan2(-rel.z, rel.x)
	var s: float = a
	while s <= b:
		for i: int in sw.bar_count:
			var bar: float = sw.angle_at(Game.course_time + s) + TAU * float(i) / float(sw.bar_count)
			if absf(wrapf(me - bar, -PI, PI)) < min_ang:
				return false
		s += 0.05
	return true


## A scarab swarm: sweeper bars dressed as lines of scuttling bronze-and-turquoise beetles
## circling a scarab idol.
func _scarabs(floor_c: Vector3, arm: float, bars: int, period: float, phase: float) -> Sweeper:
	var sw: Sweeper = kit.sweeper(_w(floor_c), arm, bars, period, phase)
	var pivot: Node3D = sw.get_child(0) as Node3D
	var shell: StandardMaterial3D = Look.flat(Color(0.08, 0.42, 0.4), 0.25, 0.7, 0.2)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.3, 0.9, 0.4)
	for holder: Node in pivot.get_children():
		var h := holder as Node3D
		var n: int = int(arm / 0.5)
		for i: int in n:
			var x: float = 0.45 + float(i) * arm / float(n)
			var body := Look.sphere(0.24, shell, Vector3(x, 0.5, 0.05 * sin(float(i) * 1.7)))
			body.scale = Vector3(0.8, 0.55, 1.1)
			h.add_child(body)
			h.add_child(Look.sphere(0.1, gold, Vector3(x, 0.52, -0.25)))
	var idol := Look.sphere(0.6, shell, _w(floor_c + Vector3(0, 0.9, 0)))
	idol.scale = Vector3(0.9, 0.6, 1.2)
	add_child(idol)
	add_child(Look.sphere(0.32, Look.flat(GOLD, 0.25, 0.9, 1.5), _w(floor_c + Vector3(0, 1.55, 0))))
	return sw


static func _ram_clear(p: Piston, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


# ---- stage 8: Temple Stair - mantle the great steps over a spike plate and under a falling block --

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var l0: Dictionary = _blk(Vector3(0, 0, -8.5), 6.0, 4.0)
	_ledge(Vector3(0, 3.3, -14.2), Vector3(6.0, 5.5, 3.4))
	var trap: DesertSpikeTrap = _spikes(Vector3(0, 3.3, -15.05), 6.0, 1.7, 3.0, 0.4, 0.133)
	_ledge(Vector3(0, 6.6, -17.6), Vector3(3.6, 8.8, 3.4), "alt")
	var press: Crusher = kit.crusher(_w(Vector3(0, 6.6, -17.6)), Vector3(3.2, 1.4, 3.0), 3.4, 3.0, 0.2, _yaw)
	_ledge(Vector3(0, 9.9, -21.0), Vector3(3.6, 12.0, 3.4), "alt")
	var cp: Dictionary = _cp(Vector3(0, 9.9, -27.8))
	_hop(cp0, l0, Vector3(0, 0, 1.0))
	r_mantle(_w(Vector3(0, 0, -10.15)), _w(Vector3(0, 3.3, -13.3)))
	r_walk(_w(Vector3(0, 3.3, -13.0)))
	_wait(func() -> bool: return _spikes_safe(trap, 0.0, 0.5) and _press_ok(press, 0.4, 1.9))
	r_mantle(_w(Vector3(0, 3.3, -13.35)), _w(Vector3(0, 6.6, -16.8)))
	r_mantle(_w(Vector3(0, 6.6, -17.0)), _w(Vector3(0, 9.9, -20.4)))
	_hop(_area(Vector3(0, 9.9, -21.0), 1.8, 1.7), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the temple gate over the top step, colossal statues at the foot of the stair
	_temple_gate(Vector3(0, 9.9, -21.6))
	for sx: float in [-1.0, 1.0]:
		deco.statue(_w(Vector3(sx * 6.5, -12.0, -9.0)), 2.2, deg_to_rad(_yaw) + PI)
		deco.brazier(_w(Vector3(sx * 2.6, 0, -7.0)), 1.4, sx < 0.0, 1.0)
	return cp["c"]


# ---- stage 9: Hall of Spikes (BRANCH) - the spike-plate floor on its rhythm, or the gallery above ----

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -7.5), 10.0, 3.0, "main", 1.0, false)
	# LEFT (red): the spike walk - five plates firing in turn, a dart laser at the end
	_blk(Vector3(-2.8, 0, -24.0), 2.6, 30.0, "alt", 1.0, false)
	var plates: Array[DesertSpikeTrap] = []
	for k: int in 5:
		plates.append(_spikes(Vector3(-2.8, 0, -12.2 - 4.0 * float(k)), 2.6, 2.0, 2.2, 0.4, 0.5 * float(k % 2)))
	var dart: LaserGate = _dart(Vector3(-2.8, 0, -33.6), 2.6, 2.2, 0.45, 0.3)
	# RIGHT (gold): up onto the gallery, run the glyph wall, drop from the balcony
	_ledge(Vector3(3.2, 3.3, -11.8), Vector3(3.0, 14.0, 3.0), "alt")
	kit.wallrun(_w(Vector3(5.4, 4.5, -22.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var g2: Dictionary = _blk(Vector3(3.2, 3.3, -35.8), 3.2, 3.6, "alt", 1.0, false)
	var merge: Dictionary = _blk(Vector3(0, 0, -40.5), 10.0, 3.0, "main", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, 0, -48.5))
	var gw := Look.box(Vector3(0.8, 12.0, 17.0), deco.stone(DesertDecor.SANDSTONE, -2.0, 4.5, 0.9), _w(Vector3(6.1, 3.0, -22.5)))
	gw.rotation.y = deg_to_rad(_yaw)
	add_child(gw)
	_sign(Vector3(-2.8, 0, -6.4), RED)
	_sign(Vector3(3.2, 0, -6.4), GOLD)
	_hall(-4.0, -44.0)
	_hop(cp0, fork, Vector3(0, 0, 0.8))
	if route_variant != 1:
		r_walk(_w(Vector3(-2.8, 0, -9.8)))
		var pads: Array[float] = [-10.0, -14.2, -18.2, -22.2, -26.2, -30.6]
		for k: int in 5:
			var tr: DesertSpikeTrap = plates[k]
			_wait(func() -> bool: return _spikes_safe(tr, 0.0, 0.55), _w(Vector3(-2.8, 0, pads[k])))
			r_walk(_w(Vector3(-2.8, 0, pads[k + 1])))
		_wait(func() -> bool: return _dark(dart, 0.05, 0.55), _w(Vector3(-2.8, 0, -31.8)))
		r_walk(_w(Vector3(-2.8, 0, -36.4)))
		r_walk(_w(Vector3(-1.4, 0, -40.0)))
	else:
		r_walk(_w(Vector3(3.2, 0, -7.4)))
		r_mantle(_w(Vector3(3.2, 0, -8.65)), _w(Vector3(3.2, 3.3, -11.6)))
		r_wallrun(_w(Vector3(3.4, 3.3, -12.95)), _w(Vector3(4.9, 4.7, -17.0)), _w(Vector3(4.9, 4.7, -27.8)), _w(Vector3(3.2, 3.3, -35.2)))
		_hop(g2, merge, Vector3(1.0, 0, 0.4))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## The temple's front: two great sloped pylons either side of the gateway with a winged sun disc
## over it, and the facade wall running off to either side (local `c` = the gateway's floor).
func _temple_gate(c: Vector3) -> void:
	var st: ShaderMaterial = deco.stone(DesertDecor.PALE, -4.0, 8.0, 1.0, Vector2(3.0, 1.5))
	for sx: float in [-1.0, 1.0]:
		# a sloped pylon tower either side, reaching down the temple's front
		var cm := CylinderMesh.new()
		cm.top_radius = 2.4 * 0.7071
		cm.bottom_radius = 3.6 * 0.7071
		cm.height = 34.0
		cm.radial_segments = 4
		cm.rings = 1
		var py := Look.mesh_node(cm, st, _w(c + Vector3(sx * 4.8, -8.0, 0)))
		py.rotation.y = deg_to_rad(_yaw) + PI * 0.25
		py.scale = Vector3(1.0, 1.0, 0.7)
		add_child(py)
		kit.banner(_w(c + Vector3(sx * 4.8, 5.0, 1.4)), 5.0, GOLD if sx < 0.0 else TURQ, _yaw)
	var lintel := Look.box(Vector3(12.0, 1.8, 2.4), st, _w(c + Vector3(0, 8.6, 0)))
	lintel.rotation.y = deg_to_rad(_yaw)
	add_child(lintel)
	var disc := deco.sun_disc(_w(c + Vector3(0, 8.6, 1.3)), 1.2, deg_to_rad(_yaw))
	disc.scale = Vector3.ONE * 0.9
	for sx: float in [-1.0, 1.0]:
		var wing := Look.box(Vector3(3.6, 0.8, 0.3), Look.flat(GOLD, 0.25, 0.85, 0.9), _w(c + Vector3(sx * 2.9, 8.8, 1.3)))
		wing.rotation = Vector3(0, deg_to_rad(_yaw), sx * 0.12)
		add_child(wing)


## A dart laser: a curtain of red light between two carved glyph posts across the route (local
## floor point `c`, `width` across).
func _dart(c: Vector3, width: float, period: float, on: float, phase: float, height: float = 2.4) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.2), period, on, phase, _yaw)
	for sx: float in [-1.0, 1.0]:
		var post := Look.box(Vector3(0.7, height + 1.4, 0.8), deco.stone(DesertDecor.PALE, 0.2, height + 0.2, 0.55, Vector2(1.2, 0.7)), _w(c + Vector3(sx * (width * 0.5 + 0.55), (height + 1.4) * 0.5 - 0.3, 0)))
		post.rotation.y = deg_to_rad(_yaw)
		add_child(post)
		deco.glyph(_w(c + Vector3(sx * (width * 0.5 + 0.55), height + 0.5, 0.42)), _d(Vector3(0, 0, 1)), 0.6, 0.2, RED, 1.6)
	return g


## Fork signpost: a banner and a floor strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	kit.banner(_w(p + Vector3(-1.4, 0, 0)), 3.6, col, _yaw)
	kit.banner(_w(p + Vector3(1.4, 0, 0)), 3.6, col, _yaw)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.6)), _sz(Vector3(1.4, 0.05, 0.3)), col)


## The beam stays dark over the whole window [now + a, now + b].
static func _dark(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


# ---- stage 10: Sandfall Gallery - beams over the pit under curtains of pouring sand ----------------

func _stage_10() -> Vector3:
	_blk(Vector3(0, 0, -9.6), 1.2, 8.0, "alt", 0.8, false)
	var f1: DesertSandfall = _sandfall(Vector3(0, 0, -10.4), 3.0, 7.5, 3.0, 0.45, 0.0)
	var b2: Dictionary = _blk(Vector3(1.4, 0.8, -19.0), 1.2, 6.0, "alt", 0.8, false)
	var f2: DesertSandfall = _sandfall(Vector3(1.4, 0.8, -19.0), 3.0, 6.7, 3.0, 0.45, 0.6)
	_blk(Vector3(0, 1.6, -28.6), 1.2, 8.0, "alt", 0.8, false)
	var f3: DesertSandfall = _sandfall(Vector3(0, 1.6, -26.6), 3.0, 6.0, 2.4, 0.4, 0.0)
	var f4: DesertSandfall = _sandfall(Vector3(0, 1.6, -30.6), 3.0, 6.0, 2.4, 0.4, 0.5)
	var b4: Dictionary = _blk(Vector3(0, 1.6, -38.2), 2.0, 4.0, "alt", 0.8, false)
	var dart: LaserGate = _dart(Vector3(0, 1.6, -38.2), 2.0, 2.2, 0.5, 0.0)
	var cp: Dictionary = _cp(Vector3(0, 1.6, -47.6))
	_hall(-4.0, -43.6)
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -6.4)))
	_wait(func() -> bool: return f1.is_clear_for(Game.course_time, 0.0, 0.5), _w(Vector3(0, 0, -8.6)))
	r_walk(_w(Vector3(0, 0, -12.8)))
	r_jump(_w(Vector3(0, 0, -13.25)), _w(Vector3(1.4, 0.8, -17.0)))
	_wait(func() -> bool: return f2.is_clear_for(Game.course_time, 0.0, 0.5), _w(Vector3(1.4, 0.8, -17.2)))
	r_walk(_w(Vector3(1.4, 0.8, -21.2)))
	_hop(b2, _area(Vector3(0, 1.6, -25.0), 0.6, 0.4))
	_wait(func() -> bool: return f3.is_clear_for(Game.course_time, 0.0, 0.5), _w(Vector3(0, 1.6, -25.1)))
	r_walk(_w(Vector3(0, 1.6, -28.6)))
	_wait(func() -> bool: return f4.is_clear_for(Game.course_time, 0.0, 0.5), _w(Vector3(0, 1.6, -28.6)))
	r_walk(_w(Vector3(0, 1.6, -32.2)))
	r_jump(_w(Vector3(0, 1.6, -32.25)), _w(Vector3(0, 1.6, -36.8)))
	_wait(func() -> bool: return _dark(dart, 0.05, 0.5), _w(Vector3(0, 1.6, -36.8)))
	r_walk(_w(Vector3(0, 1.6, -39.4)))
	_hop(b4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 11: Blade Crypt - bronze blades swinging across every stepping stone, crumbling slabs --

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var ps: Array[Vector3] = [Vector3(0, 0, -8.2), Vector3(0.5, 0.6, -14.3), Vector3(-0.4, 1.2, -20.4)]
	var blocks: Array[Dictionary] = []
	var blades: Array[Pendulum] = []
	var phases: Array[float] = [0.0, 0.542, 0.083]
	for i: int in ps.size():
		blocks.append(_blk(ps[i], 2.2 if i == 0 else 2.0, 2.2 if i == 0 else 2.0, "alt", 1.0, false))
		blades.append(_blade(ps[i] + Vector3(0, 10.0, 0), 8.5, 2.4, phases[i]))
	kit.collapse(_w(Vector3(0.6, 1.2, -26.2)), 2.0, 0.5, 2.4)
	kit.collapse(_w(Vector3(-0.4, 1.8, -31.6)), 2.0, 0.5, 2.4)
	var cp: Dictionary = _cp(Vector3(0, 1.8, -40.2))
	_hall(-4.0, -36.2)
	var b0: Pendulum = blades[0]
	_wait(func() -> bool: return _blade_clear(b0, 0.35, 1.05))
	_hop(cp0, blocks[0])
	for i: int in range(1, blocks.size()):
		var bl: Pendulum = blades[i]
		var land: float = 0.55
		route.append({"kind": "b_wait", "test": func() -> bool: return _blade_clear(bl, land - 0.15, land + 0.45)})
		_hop(blocks[i - 1], blocks[i])
	_hop(blocks[2], _area(Vector3(0.6, 1.2, -26.2), 1.0, 1.0))
	_hop(_area(Vector3(0.6, 1.2, -26.2), 1.0, 1.0), _area(Vector3(-0.4, 1.8, -31.6), 1.0, 1.0))
	_hop(_area(Vector3(-0.4, 1.8, -31.6), 1.0, 1.0), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## A swinging bronze axe-blade hung from `pivot` (local), swinging across the route. It does
## not cut - it hurls you (the Pendulum rule) - but over the pit that is the same thing.
func _blade(pivot: Vector3, length: float, period: float, phase: float) -> Pendulum:
	var p: Pendulum = kit.pendulum(_w(pivot), length, period, phase, _yaw, 55.0)
	var arm := p.get_child(0) as Node3D
	# swap the hammer head for a crescent blade of bronze with a red-hot edge
	(arm.get_child(1) as Node3D).visible = false
	var bronze: StandardMaterial3D = Look.flat(Color(0.72, 0.48, 0.22), 0.3, 0.85, 0.1)
	var edge: StandardMaterial3D = Look.flat(Color(1.0, 0.3, 0.15), 0.3, 0.4, 2.0)
	var head := Node3D.new()
	head.position = Vector3(0, -length, 0)
	arm.add_child(head)
	var disc := Look.cylinder(1.25, 0.14, bronze, Vector3.ZERO, -1.0, 28)
	disc.rotation.x = PI * 0.5
	head.add_child(disc)
	var rim := Look.cylinder(1.32, 0.06, edge, Vector3(0, -0.02, 0), -1.0, 28)
	rim.rotation.x = PI * 0.5
	head.add_child(rim)
	head.add_child(Look.box(Vector3(0.5, 0.9, 0.3), bronze, Vector3(0, 0.9, 0)))
	head.add_child(Look.sphere(0.2, Look.flat(TURQ, 0.3, 0.2, 1.5), Vector3(0, 0.3, 0.12)))
	# the beam it hangs from
	var beam := Look.box(Vector3(6.0, 0.8, 0.8), deco.stone(DesertDecor.PALE), _w(pivot + Vector3(0, 0.3, 0)))
	beam.rotation.y = deg_to_rad(_yaw)
	add_child(beam)
	return p


## The blade's head stays well out to the side of the route over [now + a, now + b].
static func _blade_clear(p: Pendulum, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if absf(sin(p.angle_at(Game.course_time + s))) * p.length < 2.6:
			return false
		s += 0.03
	return true


# ---- stage 12: Sun Well - a whirlwind up the well, then a chimney of glyph walls to the top -------

func _stage_12() -> Vector3:
	_blk(Vector3(0, 0, -9.6), 5.0, 6.0, "alt", 1.2, false)
	var d1: DesertDustDevil = _devil(Vector3(0, 0, -10.2), 12.0, [Vector3(0, 0, 0.6), Vector3(0, 0, -0.6)], 3.0)
	d1.carry = 1.0
	d1.center_pull = 1.0
	var l1: Dictionary = _blk(Vector3(0, 9.0, -14.7), 3.0, 3.0, "main", 1.2, false)
	_well_panel(2.3, 10.2, -19.5, -26.0)
	_well_panel(-2.3, 15.0, -24.5, -32.5)
	_well_panel(2.3, 18.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 20.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 20.9, -51.2))
	_hall(-4.0, -47.2, 7.0, -11.0, 30.0)
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -8.0)))
	var y1: float = _w(l1["c"]).y
	_fly(func() -> Vector3: return d1.global_position, func() -> bool: return player.global_position.y > y1 + 2.2)
	_fly(_w((l1["c"] as Vector3) + Vector3(0, 0, 0.4)))
	r_walk(_w(Vector3(0, 9.0, -13.8)))
	r_wallrun(_w(Vector3(0.5, 9.0, -15.85)), _w(Vector3(1.7, 10.4, -20.6)), _w(Vector3(1.7, 10.4, -23.5)), _w(Vector3(-1.7, 14.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 14.5, -27.4)), _w(Vector3(-1.7, 14.5, -30.4)), _w(Vector3(1.7, 17.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 17.5, -34.0)), _w(Vector3(1.7, 17.5, -35.4)), _w(Vector3(-0.75, 20.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# light pouring straight down the well
	for i: int in 3:
		deco.beam(_w(Vector3(kit.rng.randf_range(-3.0, 3.0), 30.0, -12.0 - float(i) * 12.0)), Vector3(0.15, -1, -0.1), 34.0, 1.6, 3.2, 0.12)
	return cp["c"]


## A chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by a carved slab.
func _well_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	var back := Look.box(Vector3(0.6, height + 2.0, absf(z0 - z1) + 1.0), deco.stone(DesertDecor.PALE, -height * 0.5, height * 0.5, 0.8), _w(Vector3(x + signf(x) * 0.55, y, (z0 + z1) * 0.5)))
	back.rotation.y = deg_to_rad(_yaw)
	add_child(back)


# ---- stage 13: Sundial Court (BRANCH) - ride the great sundial, or climb the gnomon to the sun ring --

func _stage_13() -> Vector3:
	var hub := Vector3(-3.0, 0, -13.0)
	var dial: RotatingPlatform = _sundial(hub, 7.0, 0.0)
	_dev_dial = dial
	var m: Dictionary = _blk(Vector3(-3.0, 0.5, -26.0), 2.6, 2.6, "alt", 1.0, false)
	var merge: Dictionary = _blk(Vector3(0, 0.5, -32.6), 14.0, 3.0, "main", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, 0.5, -42.0))
	# the gnomon route (right, clear of the dial's sweep): a walkway, two mantles up the gnomon's
	# stepped base, the sun ring at the top
	_blk(Vector3(6.25, 0, -1.5), 6.5, 3.0, "alt", 1.0, false)
	_ledge(Vector3(9.5, 3.3, -6.5), Vector3(3.0, 14.0, 3.0), "alt")
	var g2: Dictionary = _blk(Vector3(9.8, 3.3, -12.8), 2.0, 2.0, "alt", 1.0, false)
	_ledge(Vector3(9.8, 6.6, -17.6), Vector3(3.0, 17.0, 3.0), "alt")
	var portal: WarpPortal = kit.portal(_w(Vector3(9.8, 6.6, -18.5)), _yaw, _w(Vector3(2.5, 0.5, -32.6)), _yaw, 7.0)
	_arrival(Vector3(2.5, 0.5, -33.2), GOLD)
	var ring := deco.sun_disc(_w(Vector3(9.8, 12.5, -19.6)), 1.6, deg_to_rad(_yaw))
	ring.scale = Vector3.ONE * 0.6
	_sign(Vector3(-2.0, 0, -1.8), TURQ)
	_sign(Vector3(6.4, 0, -0.6), GOLD)
	_hall(-4.0, -38.0, 14.0)
	if route_variant != 1:
		_r_dial(dial, hub, Vector3(-2.6, 0, -2.7), Vector3(-3.0, 0, -6.0), (m["c"] as Vector3), 8.0, 22.0)
		_hop(m, merge, Vector3(1.0, 0, 0.4))
	else:
		r_walk(_w(Vector3(6.0, 0, -1.6)))
		r_walk(_w(Vector3(9.5, 0, -1.2)))
		r_mantle(_w(Vector3(9.5, 0, -2.65)), _w(Vector3(9.5, 3.3, -6.0)))
		_hop(_area(Vector3(9.5, 3.3, -6.5), 1.5, 1.5), g2)
		r_mantle(_w(Vector3(9.8, 3.3, -13.45)), _w(Vector3(9.8, 6.6, -17.0)))
		r_portal(_w(Vector3(9.8, 6.6, -18.6)), portal.exit_point())
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## The great sundial: a spinning bronze-rimmed disc hub with four stone arms (3.5-8.5 m out),
## a gnomon of gold on the hub.
func _sundial(hub: Vector3, period: float, phase: float) -> RotatingPlatform:
	var arms: Array[Dictionary] = [
		{"pos": Vector3(6.0, 0, 0), "size": Vector3(5.0, 0.5, 2.6)}, {"pos": Vector3(-6.0, 0, 0), "size": Vector3(5.0, 0.5, 2.6)},
		{"pos": Vector3(0, 0, 6.0), "size": Vector3(2.6, 0.5, 5.0)}, {"pos": Vector3(0, 0, -6.0), "size": Vector3(2.6, 0.5, 5.0)},
	]
	var table: RotatingPlatform = kit.spinner(_w(hub), period, arms, 2.4, phase, 0.5)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.25, 0.9, 0.8)
	var gn := CylinderMesh.new()
	gn.top_radius = 0.0
	gn.bottom_radius = 0.9
	gn.height = 3.0
	gn.radial_segments = 3
	table.add_child(Look.mesh_node(gn, gold, Vector3(0, 1.75, 0)))
	for a: Dictionary in arms:
		var ap: Vector3 = a["pos"]
		table.add_child(Look.sphere(0.25, Look.flat(TURQ, 0.3, 0.2, 2.0), ap.normalized() * 8.3 + Vector3(0, 0.4, 0)))
	var tm := TorusMesh.new()
	tm.inner_radius = 8.6
	tm.outer_radius = 9.0
	tm.rings = 64
	tm.ring_segments = 6
	add_child(Look.mesh_node(tm, Look.flat(Color(0.7, 0.48, 0.22), 0.35, 0.8), _w(hub + Vector3(0, -1.2, 0))))
	add_child(Look.cylinder(1.2, 40.0, deco.stone(DesertDecor.SANDSTONE), _w(hub + Vector3(0, -20.6, 0)), 1.4, 16))
	return table


## Bot: board sundial `c` from `from` onto an arm tip passing `board`, ride it round and jump off
## toward `to` once our bearing from the hub is `lo`..`hi` degrees short of the exit line.
func _r_dial(c: RotatingPlatform, hub: Vector3, from: Vector3, board: Vector3, to: Vector3, lo: float, hi: float) -> void:
	var tips: Array = [Vector3(7.0, 0.25, 0), Vector3(-7.0, 0.25, 0), Vector3(0, 0.25, 7.0), Vector3(0, 0.25, -7.0)]
	r_walk(_w(from))
	route.append({"kind": "x_wait", "nodes": [c], "locals": tips, "point": _w(board), "radius": 0.9, "lead": 0.55})
	route.append({"kind": "x_jump", "from": _w(from), "picked": true, "to_local": Vector3(6.6, 0.25, 0)})
	var hw: Vector3 = _w(hub)
	var ex: Vector3 = _w(to) - hw
	ex = Vector3(ex.x, 0, ex.z).normalized()
	var sgn: float = signf(c.period)
	route.append({"kind": "h_jump", "to": _w(to), "test": func() -> bool:
		var rel: Vector3 = player.global_position - hw
		rel = Vector3(rel.x, 0, rel.z).normalized()
		var a: float = rad_to_deg(atan2(rel.cross(ex).y, rel.dot(ex))) * sgn
		return a >= lo and a <= hi})


## A burst of sand and glints where a portal lets you out (fired when you arrive).
func _arrival(at: Vector3, col: Color) -> void:
	var p: GPUParticles3D = DesertFx.glints(self, _w(at + Vector3(0, 1.0, 0)), col, 50, 7.0)
	var s: GPUParticles3D = DesertFx.sand_burst(self, _w(at + Vector3(0, 0.3, 0)), 1.0, 24, 4.0)
	_arrivals.append({"at": _w(at), "p": [p, s], "cool": 0.0})
	DesertFx.rising_glints(self, _w(at), 1.2, 2.5, col, 16)


# ---- stage 14: Tomb of Kings - crumbling slabs, mirages, the rams' corridor [shortcut: the tomb] ----

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	kit.collapse(_w(Vector3(0, 0, -7.8)), 2.2, 0.5, 2.4)
	var m1: DesertMirage = _mirage(Vector3(0.8, 0.6, -13.6), 2.0, 2.0, 2.6, 0.55, 0.0)
	kit.collapse(_w(Vector3(-0.6, 1.2, -19.2)), 2.0, 0.5, 2.4)
	var m2: DesertMirage = _mirage(Vector3(0.4, 1.8, -24.8), 2.0, 2.0, 2.6, 0.55, 0.27)
	var walk: Dictionary = _blk(Vector3(0, 1.8, -36.0), 2.4, 12.0, "alt", 1.0, false)
	var rams: Array[Piston] = []
	var rz: Array[float] = [-32.0, -36.0, -40.0]
	for i: int in 3:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		rams.append(kit.piston(_w(Vector3(side * 3.5, 3.1, rz[i])), Vector3(1.8, 1.3, 1.5), _yaw + 90.0 * side, 3.4, 2.4, fposmod(0.1 - 0.12 * float(i), 1.0), 8.0))
		kit.block(_w(Vector3(side * 4.9, 2.8, rz[i])), Vector3(2.4, 3.2, 2.4), DesertDecor.SANDSTONE, true, _yaw)
	var cp: Dictionary = _cp(Vector3(0, 1.8, -49.2))
	_hall(-4.0, -45.2)
	# SHORTCUT: the hidden tomb - a 1.2 m ledge off the checkpoint's corner, a stone door that slides
	# open and shut, and the tomb's portal that lets you out at the end of the rams' corridor
	_blk(Vector3(-4.3, 0.4, -8.4), 1.2, 1.2, "accent", 0.6)
	var door: MovingPlatform = kit.mover(_w(Vector3(-4.3, 3.4, -9.2)), _sz(Vector3(2.8, 3.0, 0.4)), [Vector3.ZERO, _d(Vector3(-3.6, 0, 0))], 4.0, 0.0)
	kit.portal(_w(Vector3(-4.3, 0.4, -9.8)), _yaw, _w(Vector3(0, 1.8, -41.4)), _yaw, 6.0)
	_arrival(Vector3(0, 1.8, -41.4), TURQ)
	var facade := Look.box(Vector3(6.0, 6.0, 1.0), deco.stone(DesertDecor.PALE, -1.0, 2.5, 0.6), _w(Vector3(-5.2, 3.1, -10.9)))
	facade.rotation.y = deg_to_rad(_yaw)
	add_child(facade)
	deco.glyph(_w(Vector3(-4.3, 5.4, -10.38)), _d(Vector3(0, 0, 1)), 1.2, 0.77, TURQ, 1.8)
	if route_variant == 2:
		r_walk(_w(Vector3(-2.6, 0, -2.2)))
		_wait(func() -> bool: return _door_open(door, 0.4, 1.3))
		r_jump(_w(Vector3(-2.65, 0, -2.65)), _w(Vector3(-4.3, 0.4, -8.3)))
		r_portal(_w(Vector3(-4.3, 0.4, -10.0)), _w(Vector3(0, 1.8, -41.4)))
	else:
		_wait(func() -> bool: return _mirage_ok(m1, 1.2, 2.2) and _mirage_ok(m2, 3.1, 4.1))
		_hop(cp0, _area(Vector3(0, 0, -7.8), 1.1, 1.1))
		_hop(_area(Vector3(0, 0, -7.8), 1.1, 1.1), _area(Vector3(0.8, 0.6, -13.6), 1.0, 1.0))
		_hop(_area(Vector3(0.8, 0.6, -13.6), 1.0, 1.0), _area(Vector3(-0.6, 1.2, -19.2), 1.0, 1.0))
		_hop(_area(Vector3(-0.6, 1.2, -19.2), 1.0, 1.0), _area(Vector3(0.4, 1.8, -24.8), 1.0, 1.0))
		_hop(_area(Vector3(0.4, 1.8, -24.8), 1.0, 1.0), walk, Vector3(0, 0, 5.2))
		var r0: Piston = rams[0]
		var r1: Piston = rams[1]
		var r2: Piston = rams[2]
		_wait(func() -> bool: return _ram_clear(r0, 0.0, 0.5) and _ram_clear(r1, 0.35, 0.95) and _ram_clear(r2, 0.75, 1.35), _w(Vector3(0, 1.8, -30.4)))
		r_walk(_w(Vector3(0, 1.8, -41.4)))
	_hop(walk, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	m1.set_meta("tomb", true)
	return cp["c"]


## The tomb door has slid clear of the doorway over [now + a, now + b].
static func _door_open(d: MovingPlatform, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if d.offset_at(Game.course_time + s).length() < 2.4:
			return false
		s += 0.05
	return true


# ---- stage 15: THE BOULDER RUN - step on the sun plate and run -----------------------------------

var _boulder: DesertBoulder


func _stage_15() -> Vector3:
	# the corridor: flat, a gap, a ramp down, flat again, then the pit you wall-run across
	var a: Dictionary = _blk(Vector3(0, 0, -12.5), 5.0, 19.0, "main", 1.0, false)
	_haz(Vector3(0, 0.3, -14.0), Vector3(5.0, 0.6, 0.8))
	kit.ramp(_w(Vector3(0, -1.5, -32.25)), Vector3(5.0, 0.6, 13.83), -12.53, _yaw, "main")
	var c: Dictionary = _blk(Vector3(0, -3.0, -43.0), 5.0, 8.0, "main", 1.0, false)
	_haz(Vector3(0, -2.7, -43.2), Vector3(5.0, 0.6, 0.8))
	kit.wallrun(_w(Vector3(2.3, -1.8, -56.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var d: Dictionary = _blk(Vector3(-0.4, -3.0, -69.5), 3.6, 5.0, "main", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, -3.0, -79.0))
	# corridor walls (solid: the ball fills the corridor, there is no way round it)
	for sx: float in [-1.0, 1.0]:
		_wall(Vector3(sx * 3.3, -1.0, -25.0), Vector3(1.2, 22.0, 44.0), -4.0, 6.0)
	_wall(Vector3(-3.3, -3.0, -57.0), Vector3(1.2, 20.0, 20.0), -2.0, 6.0)
	var back := Look.box(Vector3(0.6, 9.0, 17.0), deco.stone(DesertDecor.PALE, -3.0, 3.0, 0.9), _w(Vector3(2.9, -1.8, -56.5)))
	back.rotation.y = deg_to_rad(_yaw)
	add_child(back)
	# the hatch over the corridor mouth and the ball waiting in it
	var hatch_l := Vector3(0, 11.6, -4.2)
	for sx: float in [-1.0, 1.0]:
		var jamb := Look.box(Vector3(1.6, 4.0, 6.0), deco.stone(DesertDecor.PALE, 0.5, 3.5, 0.6), _w(hatch_l + Vector3(sx * 3.2, 0.2, 0)))
		jamb.rotation.y = deg_to_rad(_yaw)
		add_child(jamb)
	var lintel := Look.box(Vector3(8.0, 1.4, 6.4), deco.stone(DesertDecor.PALE), _w(hatch_l + Vector3(0, 3.0, 0)))
	lintel.rotation.y = deg_to_rad(_yaw)
	add_child(lintel)
	deco.glyph(_w(hatch_l + Vector3(0, 3.0, 3.25)), _d(Vector3(0, 0, 1)), 1.6, 0.77, RED, 2.2, true)
	var b := DesertBoulder.new()
	b.radius = 2.4
	b.delay = 0.5
	b.v_start = 4.0
	b.accel = 7.0
	b.v_max = 11.0
	b.pit_time = 0.85
	var hw: Vector3 = _w(hatch_l)
	var pts: Array[Vector3] = []
	for lp: Vector3 in [Vector3(0, 2.4, -4.2), Vector3(0, 2.4, -25.5), Vector3(0, -0.6, -39.0), Vector3(0, -0.6, -47.2)]:
		pts.append(_w(lp) - hw)
	b.track = pts
	b.trigger_pos = _w(Vector3(0, 1.0, -6.4)) - hw
	b.trigger_size = _sz(Vector3(5.0, 2.0, 1.0))
	b.position = hw
	add_child(b)
	_boulder = b
	# the sun plate that springs it
	deco.glyph(_w(Vector3(0, 0.03, -6.4)), Vector3.UP, 2.2, 0.05, GOLD, 1.8, true)
	_hall(-4.0, -75.0, 12.0, -14.0, 16.0)
	# the run: no stopping
	r_jump(_w(Vector3(0, 0, -12.9)), _w(Vector3(0, 0, -16.2)))
	r_jump(_w(Vector3(0, 0, -21.65)), _w(Vector3(0, -0.6, -28.0)))
	r_jump(_w(Vector3(0, -3.0, -42.1)), _w(Vector3(0, -3.0, -44.6)))
	r_wallrun(_w(Vector3(0.4, -3.0, -46.65)), _w(Vector3(1.8, -1.6, -50.6)), _w(Vector3(1.8, -1.6, -61.5)), _w(Vector3(-0.4, -3.0, -68.8)))
	_hop(d, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	a.clear()
	c.clear()
	return cp["c"]


# ---- stage 16: Quicksand Crypt - out of the sinking sand onto the ledge, spikes, a whirlwind up ---

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var q1: Dictionary = _quicksand(Vector3(0, -0.6, -7.6), 3.0, 3.0, 0.35, false)
	_ledge(Vector3(0, 2.6, -12.8), Vector3(3.4, 9.0, 2.6))
	var w1: Dictionary = _blk(Vector3(0, 2.6, -18.6), 2.4, 6.0, "alt", 1.0, false)
	var trap: DesertSpikeTrap = _spikes(Vector3(0, 2.6, -18.6), 2.4, 2.0, 2.0, 0.4, 0.0)
	var q2: Dictionary = _quicksand(Vector3(0.4, 2.0, -25.6), 2.6, 2.6, 0.35, false)
	_blk(Vector3(0, -6.0, -31.0), 5.0, 5.0, "alt", 1.0, false)
	var dd: DesertDustDevil = _devil(Vector3(0, -6.0, -31.0), 15.0, [Vector3(-0.8, 0, 0), Vector3(0.8, 0, 0)], 3.6)
	dd.carry = 1.0
	dd.center_pull = 1.0
	var h: Dictionary = _blk(Vector3(0, 7.0, -35.5), 3.0, 3.0, "main", 1.2, false)
	var cp: Dictionary = _cp(Vector3(0, 7.0, -45.0))
	_hall(-4.0, -41.0)
	# SHORTCUT: run the crypt wall past the quicksand and the ledge, kick up onto the walkway
	kit.wallrun(_w(Vector3(3.0, 1.0, -13.0)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var wb := Look.box(Vector3(0.6, 9.0, 17.0), deco.stone(DesertDecor.PALE, -3.0, 3.0, 0.9), _w(Vector3(3.6, 1.0, -13.0)))
	wb.rotation.y = deg_to_rad(_yaw)
	add_child(wb)
	if route_variant == 2:
		r_wallrun(_w(Vector3(0.3, 0, -2.65)), _w(Vector3(2.5, 1.4, -6.6)), _w(Vector3(2.5, 1.4, -13.0)), _w(Vector3(0, 2.6, -20.4)))
	else:
		_hop(cp0, q1, Vector3.ZERO)
		r_mantle(_w(Vector3(0, -0.6, -8.4)), _w(Vector3(0, 2.6, -12.4)))
		r_walk(_w(Vector3(0, 2.6, -14.8)))
		_wait(func() -> bool: return _spikes_safe(trap, 0.0, 0.6), _w(Vector3(0, 2.6, -16.0)))
		r_walk(_w(Vector3(0, 2.6, -20.6)))
	_hop(w1, q2, Vector3.ZERO)
	var y1: float = _w(h["c"]).y
	_fly(func() -> Vector3: return dd.global_position, func() -> bool: return player.global_position.y > y1 + 2.2, _w(Vector3(0.4, 2.0, -26.5)))
	_fly(_w((h["c"] as Vector3) + Vector3(0, 0, 0.4)))
	_hop(h, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	q1.clear()
	return cp["c"]


# ---- stage 17: Sandfall Stair - mantle up three steps through the pouring sand, under the press ---

func _stage_17() -> Vector3:
	var s0: Dictionary = _blk(Vector3(0, 0, -8.0), 5.0, 4.0, "alt", 1.0, false)
	var falls: Array[DesertSandfall] = []
	var faces: Array[float] = [-11.7, -16.9, -22.1]
	for k: int in 3:
		var y: float = 3.3 * float(k)
		_ledge(Vector3(0, y + 3.3, faces[k] - 1.7), Vector3(5.0, 6.0 + y, 3.4), "alt" if k % 2 == 0 else "main")
		falls.append(_sandfall(Vector3(0, y, faces[k] + 0.5), 5.0, 7.5, 3.9, 0.4, fposmod(-0.36 * float(k), 1.0), 1.0))
	var w: Dictionary = _blk(Vector3(0, 9.9, -30.0), 3.0, 6.0, "alt", 1.0, false)
	var press: Crusher = kit.crusher(_w(Vector3(0, 9.9, -30.0)), Vector3(3.2, 1.4, 3.0), 3.4, 2.8, 0.1, _yaw)
	var cp: Dictionary = _cp(Vector3(0, 9.9, -40.0))
	_hall(-4.0, -36.0, 11.0, -11.0, 24.0)
	# SHORTCUT: the stair's flank wall - a short run off the first step, a kick, and catch the top
	# step's lip out of the kick (a mantle through the third curtain)
	kit.wallrun(_w(Vector3(-3.2, 6.0, -19.6)), Vector3(8.8, 8.0, 0.6), _yaw + 90.0)
	if route_variant == 2:
		var f0: DesertSandfall = falls[0]
		var f2: DesertSandfall = falls[2]
		_hop(_area(Vector3.ZERO, 3.0, 3.0), s0, Vector3(0, 0, 0.6))
		_wait(func() -> bool: return f0.is_clear_for(Game.course_time, 0.0, 0.9), _w(Vector3(0, 0, -8.6)))
		r_mantle(_w(Vector3(0, 0, -9.65)), _w(Vector3(0, 3.3, -12.6)))
		_wait(func() -> bool: return _fall_clear(f2, 0.3, 1.4, 0.0, 5.0), _w(Vector3(0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(-0.6, 3.3, -14.75)), _w(Vector3(-2.7, 5.4, -17.2)), _w(Vector3(-2.7, 5.4, -18.4)), _w(Vector3(0, 9.9, -23.4)))
	else:
		_hop(_area(Vector3.ZERO, 3.0, 3.0), s0, Vector3(0, 0, 0.6))
		var fs: Array[DesertSandfall] = falls
		_wait(func() -> bool: return fs[0].is_clear_for(Game.course_time, 0.0, 0.9), _w(Vector3(0, 0, -8.6)))
		r_mantle(_w(Vector3(0, 0, -9.65)), _w(Vector3(0, 3.3, -12.6)))
		_wait(func() -> bool: return fs[1].is_clear_for(Game.course_time, 0.0, 0.9), _w(Vector3(0, 3.3, -13.6)))
		r_mantle(_w(Vector3(0, 3.3, -14.55)), _w(Vector3(0, 6.6, -17.8)))
		_wait(func() -> bool: return fs[2].is_clear_for(Game.course_time, 0.0, 0.9), _w(Vector3(0, 6.6, -18.8)))
		r_mantle(_w(Vector3(0, 6.6, -19.75)), _w(Vector3(0, 9.9, -23.0)))
	r_walk(_w(Vector3(0, 9.9, -26.2)))
	_wait(func() -> bool: return _press_ok(press, 0.0, 0.8))
	r_walk(_w(Vector3(0, 9.9, -32.4)))
	_hop(w, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## No sand in the height band [y0, y1] of curtain `f` over [now + a, now + b].
static func _fall_clear(f: DesertSandfall, a: float, b: float, y0: float, y1: float) -> bool:
	var s: float = a
	while s <= b:
		if f.blocks_at(Game.course_time + s, y0, y1):
			return false
		s += 0.04
	return true


# ---- stage 18: Sanctum of the Sun - mirages over the pit, the dart gate, the last wall run, the altar ----

func _stage_18() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var mp: Array[Vector3] = [Vector3(0, 0, -8.6), Vector3(1.2, 0.6, -14.4), Vector3(-0.2, 1.2, -20.3)]
	var ms: Array[DesertMirage] = []
	for i: int in mp.size():
		ms.append(_mirage(mp[i], 2.0, 2.0, 2.7, 0.5, fposmod(-0.26 * float(i), 1.0)))
	var l1: Dictionary = _blk(Vector3(0, 1.2, -27.4), 3.0, 3.0, "main", 1.0, false)
	var dart: LaserGate = _dart(Vector3(0, 1.2, -29.4), 3.2, 2.0, 0.45, 0.2)
	var l2: Dictionary = _blk(Vector3(0, 1.2, -31.2), 3.0, 2.4, "main", 1.0, false)
	_well_panel(2.3, 2.4, -34.0, -50.0, 6.5)
	var d: Dictionary = _blk(Vector3(-0.4, 1.2, -57.2), 3.6, 5.0, "alt", 1.0, false)
	_ledge(Vector3(0, 4.5, -63.4), Vector3(8.0, 7.0, 3.4))
	var dais: Dictionary = _blk(Vector3(0, 4.5, -71.1), 14.0, 12.0, "main", 1.6, false)
	kit.finish(_w(Vector3(0, 4.5, -72.0)), _yaw)
	_finish_pos = _w(Vector3(0, 4.5, -72.0))
	_sun_disc = deco.sun_disc(_w(Vector3(0, 21.0, -80.0)), 7.5, deg_to_rad(_yaw))
	_hall(-4.0, -84.0, 12.0, -11.0, 30.0)
	_sanctum(Vector3(0, 4.5, -71.1))
	_wait(func() -> bool: return _mirage_ok(ms[0], 0.45, 1.05) and _mirage_ok(ms[1], 1.2, 1.85) and _mirage_ok(ms[2], 1.95, 2.6))
	var prev: Dictionary = cp0
	for i: int in mp.size():
		var m: Dictionary = _area(mp[i], 1.0, 1.0)
		_hop(prev, m)
		prev = m
	_hop(prev, l1)
	_wait(func() -> bool: return _dark(dart, 0.05, 0.6), _w(Vector3(0, 1.2, -27.8)))
	r_walk(_w(Vector3(0, 1.2, -31.0)))
	r_wallrun(_w(Vector3(0.3, 1.2, -32.05)), _w(Vector3(1.8, 2.6, -36.0)), _w(Vector3(1.8, 2.6, -46.9)), _w(Vector3(-0.4, 1.2, -56.4)))
	r_mantle(_w(Vector3(0, 1.2, -59.35)), _w(Vector3(0, 4.5, -62.6)))
	r_walk(_w(Vector3(0, 4.5, -68.0)))
	r_walk(_w(Vector3(0, 4.5, -72.4)))
	l2.clear()
	d.clear()
	dais.clear()


var _sun_disc: Node3D


## The sanctum round the finish: obelisks and statues flanking the dais, braziers, rising glints.
func _sanctum(c: Vector3) -> void:
	for sx: float in [-1.0, 1.0]:
		deco.obelisk(_w(c + Vector3(sx * 6.2, 0, -3.0)), 12.0, 1.3)
		deco.statue(_w(c + Vector3(sx * 8.8, -6.0, -8.0)), 1.6, deg_to_rad(_yaw))
		for k: int in 2:
			deco.brazier(_w(c + Vector3(sx * 5.8, 0, 3.8 - float(k) * 6.0)), 1.4, k == 0, 1.1)
	DesertFx.rising_glints(self, _w(c + Vector3(0, 0.1, 0)), 5.0, 8.0, GOLD, 40)
	DesertFx.motes(self, _w(c + Vector3(0, 5.0, -3.0)), Vector3(7, 5, 7), 60, Color(2.6, 1.9, 0.9))


## A solid carved wall (the camera leans on it instead of sinking into it).
func _wall(c: Vector3, size: Vector3, glyph_lo: float = 1.0, glyph_hi: float = -1.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.box(size, deco.stone(DesertDecor.SANDSTONE, glyph_lo, glyph_hi, 1.0, Vector2(2.6, 1.3))))
	body.rotation.y = deg_to_rad(_yaw)
	body.position = _w(c)
	add_child(body)


## Temple hall round the current stage, local z from z0 down to z1 (z0 > z1): carved walls at
## x = +-hw, a colonnade inside them, lintels overhead with dusty sunbeams slanting between,
## torches, glowing glyph panels, and far below a pit of quicksand (an invisible catch net: a
## fall down there is a fall).
func _hall(z0: float, z1: float, hw: float = 11.0, floor_y: float = -11.0, top_y: float = 15.0) -> void:
	var len: float = z0 - z1
	var mid: float = (z0 + z1) * 0.5
	var h: float = top_y - floor_y
	for sx: float in [-1.0, 1.0]:
		_wall(Vector3(sx * (hw + 0.7), floor_y + h * 0.5, mid), Vector3(1.4, h, len), -h * 0.5 + 9.0, h * 0.5 - 4.0)
		# the colonnade
		var n: int = maxi(int(len / 7.0), 1)
		for i: int in n + 1:
			var z: float = z0 - float(i) * len / float(n)
			deco.column(_w(Vector3(sx * (hw - 1.3), floor_y, z)), top_y - floor_y - 3.0, 0.85, false)
		# torches on the wall every other bay
		for i: int in n:
			if i % 2 == 1:
				continue
			var tz: float = z0 - (float(i) + 0.5) * len / float(n)
			deco.brazier(_w(Vector3(sx * (hw - 0.4), 2.2, tz)), 0.01, true, 0.9)
			deco.glyph(_w(Vector3(sx * hw, 6.0, tz)), _d(Vector3(-sx, 0, 0)), 2.4, [0.05, 0.2, 0.5, 0.77][(i >> 1) % 4], GOLD if sx < 0.0 else TURQ, 1.4, true)
	# lintels overhead, and sunbeams through the gaps between them
	var sun_dir: Vector3 = _sun.global_basis.z * -1.0 if _sun != null else Vector3(0.5, -0.45, 0.6)
	var nl: int = maxi(int(len / 6.0), 1)
	for i: int in nl + 1:
		var z: float = z0 - float(i) * len / float(nl)
		var l := Look.box(Vector3(hw * 2.0 + 2.8, 1.4, 1.6), deco.stone(DesertDecor.PALE, 1.0, -1.0, 0.9, Vector2(2.2, 1.1)), _w(Vector3(0, top_y + 0.7, z)))
		l.rotation.y = deg_to_rad(_yaw)
		add_child(l)
		if i < nl and i % 2 == 0:
			var bz: float = z - len / float(nl) * 0.5
			deco.beam(_w(Vector3(kit.rng.randf_range(-hw * 0.5, hw * 0.5), top_y + 1.0, bz)), sun_dir, 34.0, 1.2, 2.6, 0.14)
	# the pit: sand far below with a catch net just above it
	var pm := PlaneMesh.new()
	pm.size = Vector2(hw * 2.0, len)
	var sand := Look.mesh_node(pm, deco.dune_mat(), _w(Vector3(0, floor_y, mid)))
	sand.rotation.y = deg_to_rad(_yaw)
	sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sand)
	var net := KillZone.new()
	net.show_mesh = false
	net.size = _sz(Vector3(hw * 2.0, 1.0, len))
	net.position = _w(Vector3(0, floor_y + 1.5, mid))
	add_child(net)
	DesertFx.motes(self, _w(Vector3(0, 4.0, mid)), _sz(Vector3(hw * 0.8, 6.0, len * 0.5)), 50, Color(2.4, 1.8, 1.0))


static func _press_ok(c: Crusher, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if c.gap_at(Game.course_time + s) < 2.0 or not c.is_clear_for(Game.course_time + s, 0.0):
			return false
		s += 0.04
	return true


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
	_env.sky = DesertSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.95, 0.78, 0.62)
	_env.ambient_light_energy = 0.62
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.96, 0.78, 0.55)
	_env.fog_density = 0.0024
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.12
	_env.fog_sun_scatter = 0.45
	_env.fog_height = -14.0
	_env.fog_height_density = 0.03
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.15
	_env.adjustment_contrast = 1.1
	_sun.light_color = Color(1.0, 0.8, 0.56)
	_sun.light_energy = 2.5
	_sun.rotation_degrees = Vector3(-26, 220, 0)
	_sun.shadow_blur = 0.5
	_sun.light_angular_distance = 0.5
	# the "fill" becomes the blue bounce of the open sky from the other side
	_fill.light_color = Color(0.55, 0.66, 0.95)
	_fill.light_energy = 0.4
	_fill.rotation_degrees = Vector3(-50, 40, 0)


## Swap every walkable surface to the sandstone shader (same colours).
func _desert_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = STONE_SHADER
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
	var sea_y: float = -38.0
	deco.sand_sea(Vector3(mid.x, sea_y, mid.z), maxf(span.x, span.z) + 1600.0)
	# dunes rolling away under the course and towering round it
	var placed: int = 0
	var tries: int = 0
	while placed < 34 and tries < 400:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 160.0, hi.x + 160.0), sea_y, rng.randf_range(lo.z - 160.0, hi.z + 160.0))
		var big: bool = rng.randf() < 0.4
		var clear: float = 55.0 if big else 30.0
		if not _clear_of(p, pts, clear):
			continue
		var h: float = rng.randf_range(30.0, 62.0) if big else rng.randf_range(12.0, 26.0)
		deco.dune(p, Vector3(rng.randf_range(40.0, 90.0), h, rng.randf_range(30.0, 70.0)), rng.randf() * TAU, big and rng.randf() < 0.6)
		placed += 1
	# dunes low under the course (well below the landings)
	for i: int in _cp_world.size():
		var c: Vector3 = _cp_world[i]
		deco.dune(Vector3(c.x + rng.randf_range(-20.0, 20.0), sea_y, c.z + rng.randf_range(-20.0, 20.0)), Vector3(rng.randf_range(30.0, 50.0), rng.randf_range(8.0, 14.0), rng.randf_range(25.0, 40.0)), rng.randf() * TAU)
	# far horizon: the pyramids, colossi, obelisks and the sandstorm wall
	deco.pyramid(Vector3(mid.x - 330.0, sea_y - 8.0, mid.z - 420.0), 300.0, 200.0, 0.3)
	deco.pyramid(Vector3(mid.x - 90.0, sea_y - 8.0, mid.z - 560.0), 220.0, 150.0, 0.1)
	deco.pyramid(Vector3(mid.x - 470.0, sea_y - 8.0, mid.z - 190.0), 160.0, 105.0, 0.5)
	deco.pyramid(Vector3(mid.x + 180.0, sea_y - 8.0, mid.z - 600.0), 120.0, 80.0, 0.7)
	deco.colossus(Vector3(mid.x - 150.0, sea_y + 2.0, mid.z - 260.0), 3.4, 0.5)
	deco.colossus(Vector3(mid.x - 190.0, sea_y + 2.0, mid.z - 200.0), 3.4, 0.5)
	deco.buried_head(Vector3(mid.x + 190.0, sea_y + 4.0, mid.z + 60.0), 4.0, -1.8)
	deco.buried_head(Vector3(mid.x - 240.0, sea_y + 2.0, mid.z + 140.0), 3.0, 2.3)
	for i: int in 6:
		var a: float = -2.2 + float(i) * 0.25
		deco.obelisk(Vector3(mid.x + cos(a) * 230.0, sea_y + 4.0, mid.z + sin(a) * 230.0), rng.randf_range(38.0, 55.0), 4.5)
	deco.storm_wall(Vector3(mid.x, sea_y, mid.z), 640.0, 260.0, 0.02, 0.22)
	# heat shimmer boiling off the sand sea round the course
	for i: int in 8:
		var a2: float = TAU * float(i) / 8.0 + rng.randf_range(-0.2, 0.2)
		var r: float = rng.randf_range(90.0, 150.0)
		deco.haze(Vector3(mid.x + cos(a2) * r, sea_y + rng.randf_range(4.0, 14.0), mid.z + sin(a2) * r), rng.randf_range(80.0, 140.0), 16.0, 0.003)
	# ambient life along the whole route: blown sand, golden motes, rolling veils
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c2: Vector3 = (here + prev) * 0.5 + Vector3(0, 3.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 7.0, absf(here.z - prev.z) * 0.5 + 12.0)
		DesertFx.sand_drift(self, c2, ext, 60)
		DesertFx.motes(self, c2 + Vector3(0, 2.0, 0), ext * 0.8, 40)
		DesertFx.veils(self, c2 + Vector3(0, -8.0, 0), ext + Vector3(20, 4, 20), 10)


# ---- live effects -----------------------------------------------------------------------------------

## The light at the first dunes (0) and in the sanctum (1): the afternoon sinks into golden hour
## as you climb into the temple - the haze thickens to amber and the sun turns orange.
const FOG_A := Color(0.96, 0.78, 0.55)
const FOG_B := Color(0.98, 0.62, 0.36)
const SUN_A := Color(1.0, 0.8, 0.56)
const SUN_B := Color(1.0, 0.64, 0.36)
const AMB_A := Color(0.95, 0.78, 0.62)
const AMB_B := Color(1.0, 0.7, 0.5)

var _hour: float = 0.0


func _process(dt: float) -> void:
	if player == null:
		return
	if _env != null:
		var target: float = clampf(float(current_checkpoint) / float(maxi(checkpoints.size(), 1)), 0.0, 1.0)
		_hour = move_toward(_hour, target, dt * 0.06)
		_env.fog_light_color = FOG_A.lerp(FOG_B, _hour)
		_env.ambient_light_color = AMB_A.lerp(AMB_B, _hour)
		_env.fog_density = lerpf(0.0024, 0.0034, _hour)
		_sun.light_color = SUN_A.lerp(SUN_B, _hour)
		_sun.light_energy = lerpf(2.5, 2.8, _hour)
	for e: Dictionary in _arrivals:
		e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
		if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
			e["cool"] = 3.0
			for p: GPUParticles3D in e["p"]:
				p.restart()
				p.emitting = true


## The sun gate goes off: the great disc flares, gold and turquoise glints and a column of sand
## burst from the dais, and a wash of light.
func _finish_sequence() -> void:
	var cols: Array[Color] = [GOLD, TURQ, Color(1.0, 0.9, 0.6)]
	for i: int in 3:
		var b: GPUParticles3D = DesertFx.glints(self, _finish_pos + Vector3(0, 1.0 + float(i) * 1.2, 0), cols[i], 70, 9.0 + 2.0 * float(i))
		b.restart()
		b.emitting = true
	var s: GPUParticles3D = DesertFx.sand_burst(self, _finish_pos + Vector3(0, 0.4, 0), 2.5, 60, 9.0)
	s.restart()
	s.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.78, 0.45)
	flash.light_energy = 8.0
	flash.omni_range = 26.0
	flash.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.4)
	if _sun_disc != null:
		var tw2: Tween = create_tween()
		tw2.tween_property(_sun_disc, "scale", Vector3.ONE * 1.15, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_sun_disc, "scale", Vector3.ONE, 0.6)
	await get_tree().create_timer(0.9).timeout


# ---- dev hooks (temporary) -------------------------------------------------------------------------

var _dev_was_ground: bool = true


func _physics_process(dt: float) -> void:
	super(dt)
	if player != null and OS.has_environment("DESERT_SPEED"):
		if _dev_was_ground and not player.grounded:
			var v: Vector3 = player.velocity
			print("TAKEOFF at %s speed %.2f vy %.2f" % [str(player.global_position.snapped(Vector3.ONE * 0.01)), Vector2(v.x, v.z).length(), v.y])
		if not _dev_was_ground and player.grounded:
			print("LAND at %s" % str(player.global_position.snapped(Vector3.ONE * 0.01)))
		_dev_was_ground = player.grounded
		if _boulder != null and not _boulder.is_armed():
			var gap: float = player.global_position.distance_to(_boulder.to_global(_boulder.position_at(_boulder.elapsed()))) - _boulder.radius
			if player.is_wall_running() and not _dev_boulder_said:
				_dev_boulder_said = true
				print("BOULDER at wall run: e %.2f gap %.2f (ball leaves track at %.2f)" % [_boulder.elapsed(), gap, _boulder.run_time()])
			if Engine.get_physics_frames() % 30 == 0:
				print("BOULDER e %.2f gap %.2f player %s" % [_boulder.elapsed(), gap, str(player.global_position.snapped(Vector3.ONE * 0.1))])
		elif _boulder != null:
			_dev_boulder_said = false
		if _dev_dial != null and false:
			var rel: Vector3 = player.global_position - _dev_dial.global_position
			print("DIAL t %.2f ang %.2f rel %s floor %s gr %s pv %s v %s" % [Game.course_time, _dev_dial.angle_at(Game.course_time), str(rel.snapped(Vector3.ONE * 0.01)), str(player.floor_body), str(player.grounded), str(player.platform_velocity.snapped(Vector3.ONE * 0.01)), str(player.velocity.snapped(Vector3.ONE * 0.01))])


var _dev_dial: RotatingPlatform
var _dev_boulder_said: bool = false


func _dev_hooks() -> void:
	var from: int = int(OS.get_environment("DESERT_FROM")) if OS.has_environment("DESERT_FROM") else 0
	if from > 1 and from - 2 < _cp_nodes.size():
		var marks: Array[int] = []
		for i: int in route.size():
			if str(route[i]["kind"]) == "checkpoint":
				marks.append(i)
		var cp: Checkpoint = _cp_nodes[from - 2]
		set_spawn(cp.position + Vector3(0, 0.15, 0), cp.rotation_degrees.y)
		route = route.slice(marks[from - 2] + 1)
	if OS.has_environment("DESERT_JUMPS"):
		get_tree().create_timer(0.4).timeout.connect(_dev_jumps)


func _dev_jumps() -> void:
	var t: MovementTuning = load("res://resources/default_tuning.tres") as MovementTuning
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var k: int = 0
	for s: int in route.size():
		var step: Dictionary = route[s]
		if str(step["kind"]) == "checkpoint":
			k += 1
		if str(step["kind"]) != "jump" or step.has("to_node"):
			continue
		var from: Vector3 = step["from"]
		var to: Vector3 = step["to"]
		var flat := Vector3(to.x - from.x, 0, to.z - from.z)
		var total: float = flat.length()
		var dir: Vector3 = flat.normalized()
		var left: bool = false
		var d: float = 0.0
		var need := Vector2(total, to.y - from.y)
		while d <= total:
			var p: Vector3 = from + dir * d
			if not left:
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p + Vector3(0, -0.7, 0), 1)
				if space.intersect_ray(q).is_empty():
					left = true
			else:
				var q2 := PhysicsRayQueryParameters3D.create(Vector3(p.x, to.y + 1.2, p.z), Vector3(p.x, to.y - 0.9, p.z), 1)
				var hit: Dictionary = space.intersect_ray(q2)
				if not hit.is_empty():
					need = Vector2(d + 0.4, (hit["position"] as Vector3).y - from.y)
					break
			d += 0.2
		var v: float = t.max_speed if float(step.get("speed", -1.0)) <= 0.0 else float(step["speed"])
		var land: Vector3 = Ballistics.landing_point(t, Vector3.ZERO, Vector3(0, t.jump_velocity, -v), need.y)
		print("JUMP stage %d step %d: need %.2f m dy %.2f -> %.0f%%" % [k + 1, s, need.x, need.y, need.x / absf(land.z) * 100.0])
