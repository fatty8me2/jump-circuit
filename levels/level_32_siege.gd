extends LevelBase
## 32. CASTLE SIEGE - the last and hardest course before The Final Ascent. A medieval castle under
## siege at dusk: the sky bleeds orange and plum, fires burn in the camps and the towers, banners of
## crimson and gold snap in the smoke-wind and the defenders' trebuchets hurl flaming stones that land
## on painted rings you can watch coming. You storm it from the besiegers' camp: across the moat,
## through the gatehouse, up a siege tower onto the outer wall, along the battlements, through the
## bailey, and at the end the trebuchet itself flings you over the inner wall to the foot of the keep,
## where you climb the stone to plant yourself at the banner.
## Fifteen stages, fourteen checkpoints; it is hard through precision (twelve-plus main-path jumps at
## 85-94% of max reach, a third of them onto 1.0-1.4 m posts), pace and combinations, never through
## blind timing: every timed hazard shows its tell for 0.8 s or more, and every wait of the route bot
## holds for 1.5 s more.
##
##  1 The Camp          four stakes-top posts, a timber beam, MANTLE the palisade gate
##  2 The Moat          two piers, the DRAWBRIDGE (kit) over the moat, a cratered apron under a BOULDER
##  3 Boulder Field     a post, the 16 m causeway under two BOULDERS, WALL RUN the siege-tower hoarding
##  4 The Gatehouse     BRANCH: the GAP WALL (kit) portcullis lane | a court under BOILING OIL + MANTLE
##                      [shortcut: four arrow-slit stones across the middle at 94/92%]
##  5 Siege Tower       board the SIEGE TOWER (it rides you up the wall), leap onto the battlements
##                      through an ARROW VOLLEY
##  6 The Wall-Walk     four merlons and a 12 m walk under the swinging BATTERING RAM
##  7 Portcullis Row    the walk under two falling PORTCULLISES (crushers), MANTLE under the third
##  8 Bailey Gate       BRANCH: the BALLISTA RAMS (pistons) shoot across the beam | WALL RUN the hall
##                      wall, MANTLE the buttress [shortcut: four hidden stones down the middle]
##  9 The Mace Tower    a round tower top under a spinning MACE (kit hammer), then a FLAME GATE (laser)
## 10 The Postern       BRANCH: the sally-port DOOR (portal) up to the lintel | the FALLING BLOCK
##                      (kit) corridor [shortcut: the small door on the hanging stone]
## 11 Cannon Wall       the CANNONS (kit battery) fire across a long beam, two chained WALL RUNS
## 12 Crumbling Stair   six CRUMBLING steps under an ARROW VOLLEY [shortcut: a 4.1 m MANTLE up the
##                      buttress, then its narrow cornice]
## 13 The Windlass      board the turning WINDLASS wheel (spinner), leap off to the stones
## 14 Keep Gate         three stones under staggered BOULDERS (the wave follows a running player),
##                      MANTLE the keep's plinth
## 15 THE TREBUCHET     SET PIECE: step into the sling basket; the arm swings after its tell and
##                      flings you over the inner wall to the foot of the keep; WALL RUN the keep's
##                      three buttresses, MANTLE the roof ledge, hop the merlons, and plant yourself
##                      at the banner, the finish
##
## Siege mechanics (own scripts): SiegeBoulder (trebuchet boulders and their landing shadows),
## SiegeRam (battering ram), SiegeOil (boiling oil), SiegeVolley (arrow volleys), SiegeTrebuchet
## (scenery that throws what really happens). Kit: drawbridge, gap wall, spinning hammer, falling
## block, cannon battery, launch barrel. Visuals: visual/siege_{sky,decor,fx}.gd, siege_stone and
## siege_banner shaders. Route variants for the bot: 0 = main line, 1 = every alternative branch,
## 2 = main line + every shortcut. Every wait the bot makes holds for 1.5 s more.

const CRIMSON := Color(0.74, 0.1, 0.12)
const GOLD := Color(0.95, 0.72, 0.2)
const FIRE := Color(1.0, 0.5, 0.14)
const STONE := Color(0.46, 0.43, 0.41)

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 3

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: SiegeDecor
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
	theme_id = "siege"
	music_track = "siege"
	kill_y = -80.0
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


## A walkable stone slab (local top centre `c`, sx across, sz along).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, keel: float = 0.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw)
	_floors.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": thick})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A small stone post (a landing about a metre across).
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


## The mirror of _ahead: the local top centre of a platform `sz` deep BEHIND block `b` (further +z) from
## which a jump needs `pct` of max reach to land on `b`'s near edge; `dy` = b's height minus the platform's.
func _behind(b: Dictionary, pct: float, dy: float, sz: float, dx: float = 0.0) -> Vector3:
	var bc: Vector3 = b["c"]
	var near: float = bc.z + float(b["hz"])
	var m: float = pct * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	var e: float = float(k) * 0.2 - 0.03
	return Vector3(bc.x + dx, bc.y - dy, near + e - 0.35 + sz * 0.5)


## Stepping stones laid evenly along local -z from `a`'s front edge to `b`'s near edge: `n` stones, each
## `sz` square, all at b's height... (dy spread evenly), returned in order.
func _stones(a: Dictionary, b: Dictionary, n: int, sz: float = 1.2, style: String = "accent") -> Array[Dictionary]:
	var ac: Vector3 = a["c"]
	var bc: Vector3 = b["c"]
	var z0: float = ac.z - float(a["hz"])
	var z1: float = bc.z + float(b["hz"])
	var gap: float = (z0 - z1 - float(n) * sz) / float(n + 1)
	var out: Array[Dictionary] = []
	for i: int in n:
		var z: float = z0 - gap * float(i + 1) - sz * (float(i) + 0.5)
		var t: float = float(i + 1) / float(n + 1)
		out.append(_post(Vector3(lerpf(ac.x, bc.x, t), lerpf(ac.y, bc.y, t), z), sz, sz, style))
	return out


## Checkpoint slab facing the next stage's heading (_next_yaw), with a banner and two braziers.
func _cp(c: Vector3, size: float = 5.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.2)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var fx: Array[GPUParticles3D] = SiegeFx.cp_burst(FIRE if _cp_world.size() % 2 == 0 else GOLD)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: siege_checkpoint - a stage banked: a horn call over a snare roll and a shower of embers
			WorldAudio.at(self, "siege_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	# a banner pole and two brazier tripods at the slab's back corners (clear of the way on)
	var back: float = size * 0.5 - 0.5
	deco.banner(_w(c + Vector3(-back, 0, back)), 4.4, deg_to_rad(_yaw), CRIMSON)
	deco.brazier(_w(c + Vector3(back, 0, back)), 1.0, true)
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


## A trebuchet boulder zone on the floor at local `c`: `phase` is a fraction of the period; `src` is
## where the stone comes from, in local axes (toward the castle by default).
func _boulder(c: Vector3, radius: float, period: float, phase: float, src: Vector3 = Vector3(0, 44, -64)) -> SiegeBoulder:
	var b := SiegeBoulder.new()
	b.radius = radius
	b.period = period
	b.phase = phase
	b.source = _d(src)
	b.position = _w(c)
	add_child(b)
	return b


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	deco = SiegeDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, -90.0, -90.0, -90.0, 0.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3]
	# @@STAGES@@
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
	if last == 14:
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
	_siege_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


# ---- stage 1: The Camp - four stone posts, a timber beam, mantle the palisade gate ------------------

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
	# the palisade gate: a mantle wall across a 1.6 m gap, its top 3.3 m above the beam
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
	_palisade_dress(door_top, 2.6, 9.0, 1.4)
	# the besiegers' camp behind the start: tents, fires, supplies and stakes
	var yr: float = deg_to_rad(_yaw)
	deco.tent(_w(Vector3(-4.2, 0.0, 4.4)), yr + 0.3, Vector3(3.2, 2.6, 4.2), Color(0.62, 0.55, 0.42))
	deco.tent(_w(Vector3(4.4, 0.0, 4.2)), yr - 0.2, Vector3(3.0, 2.4, 3.8), Color(0.55, 0.2, 0.18))
	deco.campfire(_w(Vector3(0.0, 0.0, 5.2)))
	deco.supplies(_w(Vector3(-5.0, 0.0, -1.6)), yr + 0.4)
	deco.stakes(_w(Vector3(0.0, 0.0, -5.5)), yr, 5, 0.9, 1.7)
	deco.banner(_w(Vector3(5.2, 0.0, -3.0)), 5.0, yr, CRIMSON)
	return cp["c"]


## The palisade gate you mantle: a wall of sharpened timber with iron straps and a lit torch.
func _palisade_dress(top: Vector3, w: float, h: float, d: float) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(_b, _w(top - Vector3(0, h * 0.5, 0)))
	add_child(n)
	var wood: StandardMaterial3D = Look.flat(Color(0.3, 0.2, 0.13), 0.9)
	var iron: StandardMaterial3D = Look.flat(Color(0.15, 0.15, 0.17), 0.45, 0.7)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.28, h + 0.5, d + 0.3), wood, Vector3(sx * (w * 0.5 + 0.14), -0.1, 0)))
	for sz: float in [-1.0, 1.0]:
		for i: int in 2:
			n.add_child(Look.box(Vector3(w * 0.9, 0.16, 0.05), iron, Vector3(0, -h * 0.5 + h * (0.3 + 0.35 * float(i)), sz * (d * 0.5 + 0.03))))
		n.add_child(Look.sphere(0.1, Look.flat(GOLD, 0.3, 0.0, 1.8), Vector3(w * 0.3, -h * 0.5 + h * 0.5, sz * (d * 0.5 + 0.08))))


# ---- stage 2: The Moat - two piers, the drawbridge, the cratered apron under a boulder ---------------

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var m1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.3), 1.3, 1.3)
	var m2: Dictionary = _post(_ahead(m1, 0.90, 0.6, 1.2, 0.4))
	var ap: Dictionary = _blk(_ahead(m2, 0.88, 0.0, 4.0, -0.4), 4.4, 4.0)
	var ac: Vector3 = ap["c"]
	var hinge_z: float = ac.z - 2.0
	var bridge: Drawbridge = kit.drawbridge(_w(Vector3(ac.x, ac.y, hinge_z)), 8.0, 3.4, _yaw, 9.5, 0.0)
	var far: Dictionary = _blk(Vector3(ac.x, ac.y, hinge_z - 8.0 - 3.5), 4.4, 7.0)
	var fc: Vector3 = far["c"]
	var ring: SiegeBoulder = _boulder(Vector3(fc.x, fc.y, fc.z), 1.9, 4.6, 0.3)
	var cp: Dictionary = _cp(_ahead(far, 0.86, 0.0, 5.0, -fc.x))
	_hop(cp0, m1)
	_hop(m1, m2)
	_hop(m2, ap)
	r_walk(_w(Vector3(ac.x, ac.y, hinge_z + 1.2)))
	_wait(func() -> bool: return bridge.is_down_for(Game.course_time, 1.6 + 1.5), _w(Vector3(ac.x, ac.y, hinge_z + 1.2)))
	r_walk(_w(Vector3(fc.x, fc.y, fc.z + 3.2)))
	# the ring: the bot reaches it about 0.3 s after stepping off the deck and is through in under a second
	_wait(func() -> bool: return ring.is_clear_between(Game.course_time, 0.0, 1.4 + 1.5), _w(Vector3(fc.x, fc.y, fc.z + 3.2)))
	_hop(far, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the moat: dark water far below, a gatehouse beyond the bridge, torches on the apron
	deco.brazier(_w(ac + Vector3(2.0, 0, 1.4)), 1.0)
	deco.brazier(_w(ac + Vector3(-2.0, 0, 1.4)), 1.0)
	deco.rubble(_w(Vector3(fc.x + 1.9, fc.y, fc.z + 2.6)), 4)
	deco.gatehouse(_w(Vector3(14.0, -9.0, fc.z - 5.0)), deg_to_rad(_yaw) - 0.5, 9.0, 24.0)
	return cp["c"]


# ---- stage 3: Boulder Field - a post, the causeway under two boulders, wall run the hoarding ---------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.90, 0.0, 1.2))
	var cw: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 16.0, 0.0), 3.0, 16.0, "alt", 0.8)
	var cwc: Vector3 = cw["c"]
	var b1: SiegeBoulder = _boulder(Vector3(cwc.x, cwc.y, cwc.z + 3.2), 1.55, 4.6, 0.55, Vector3(-8, 44, -64))
	var b2: SiegeBoulder = _boulder(Vector3(cwc.x, cwc.y, cwc.z - 3.4), 1.55, 4.6, 0.45, Vector3(8, 44, -64))
	var w2: Dictionary = _post(_ahead(cw, 0.88, 0.0, 1.4, 0.0), 1.4, 1.4)
	var wc: Vector3 = w2["c"]
	var f: float = wc.z - 0.7
	kit.wallrun(_w(Vector3(wc.x + 2.3, wc.y + 1.2, f - 9.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _post(Vector3(wc.x - 0.6, wc.y, f - 22.5), 1.8, 2.4)
	var cp: Dictionary = _cp(_ahead(land, 0.86, 0.0, 5.0, -(wc.x - 0.6)))
	var z0: float = cwc.z + 8.0
	_hop(cp0, p1)
	# onto the causeway, then to the first ring (3.2 m in), the second (6.6 m in) and the end
	_hop(p1, cw, Vector3(0, 0, 7.0))
	r_walk(_w(Vector3(cwc.x, cwc.y, z0 - 1.2)))
	_wait(func() -> bool: return b1.is_clear_between(Game.course_time, 0.1, 1.0 + 1.5) and b2.is_clear_between(Game.course_time, 0.5, 1.6 + 1.5),
		_w(Vector3(cwc.x, cwc.y, z0 - 1.2)))
	r_walk(_w(Vector3(cwc.x, cwc.y, cwc.z - 7.2)))
	_hop(cw, w2)
	r_wallrun(_w(Vector3(wc.x + 0.3, wc.y, f + 0.35)), _w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 3.6)),
		_w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 14.5)), _w(Vector3(wc.x - 0.6, wc.y, f - 22.2)))
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the hoarding behind the wall-run panel: a siege tower's timber skin, and the broken field
	deco.siege_tower_prop(_w(Vector3(wc.x + 5.6, wc.y - 18.0, f - 9.5)), deg_to_rad(_yaw) + PI * 0.5, 22.0)
	deco.rubble(_w(Vector3(cwc.x + 4.5, cwc.y - 6.0, cwc.z)), 5)
	deco.stakes(_w(Vector3(cwc.x - 3.0, cwc.y, cwc.z + 6.0)), deg_to_rad(_yaw) + PI * 0.5, 3, 0.8, 1.6)
	return cp["c"]


# @@MORE_STAGES@@

func _stage_15() -> void:
	pass


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
	_env.sky = SiegeSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.62, 0.42, 0.5)
	_env.ambient_light_energy = 0.62
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.5, 0.26, 0.2)
	_env.fog_density = 0.0042
	_env.fog_aerial_perspective = 0.45
	_env.fog_sky_affect = 0.35
	_env.fog_sun_scatter = 0.3
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.08
	# the low sun: where the sky shows it (SiegeSky's sun_dir), warm and long-shadowed; a cool plum fill
	var sun_dir := Vector3(-0.35, 0.05, -0.93).normalized()
	_sun.light_color = Color(1.0, 0.62, 0.34)
	_sun.light_energy = 1.35
	_sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	_fill.light_color = Color(0.45, 0.35, 0.65)
	_fill.light_energy = 0.34
	_fill.basis = Basis.looking_at(Vector3(0.4, -0.3, 0.8).normalized(), Vector3.UP)


## Every walkable surface (world) and every route point: far scenery keeps clear of them.
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
	# under every floor: a slim pier of masonry under a small one, a stepped base under a big one -
	# never where it would poke through anything walkable below
	for f: Dictionary in _floors:
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		var under: Vector3 = t - Vector3(0, float(f["drop"]), 0)
		if maxf(s.x, s.z) <= 2.7:
			var length: float = rng.randf_range(4.0, 9.0)
			if _box_free(under - Vector3(0, length * 0.5 + 1.5, 0), Vector3(0.5, length * 0.5 + 1.5, 0.5), f):
				deco.column(under, minf(s.x, s.z) * 0.2, length)
		elif minf(s.x, s.z) >= 2.9:
			var depth: float = clampf(minf(s.x, s.z) * 0.7, 1.5, 6.0)
			if _box_free(under - Vector3(0, depth * 0.5, 0), Vector3(s.x * 0.5, depth * 0.5, s.z * 0.5), f):
				deco.keel(under, s.x, s.z, depth)
	# the burnt ground far below, fading into the smoke
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600, 2600)
	ground.mesh = pm
	ground.material_override = Look.flat(Color(0.1, 0.07, 0.06), 1.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position = Vector3(mid.x, lo.y - 70.0, mid.z)
	add_child(ground)
	# far scenery round the course: castles, towers and curtain walls, the besiegers' tents and
	# siege towers, trebuchets, dead trees and the glow of campfires - kept well clear of the route
	var placed: int = 0
	var tries: int = 0
	while placed < 34 and tries < 900:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 120.0, hi.x + 120.0), 0.0, rng.randf_range(lo.z - 120.0, hi.z + 120.0))
		p.y = lo.y - 70.0
		if not _clear_of(Vector3(p.x, mid.y, p.z), pts, 40.0):
			continue
		var roll: float = rng.randf()
		var yaw: float = rng.randf() * TAU
		if roll < 0.2:
			deco.castle(p, yaw, rng.randf_range(0.9, 1.5))
		elif roll < 0.42:
			deco.tower(p, rng.randf_range(4.0, 7.0), rng.randf_range(30.0, 60.0), rng.randf() < 0.7)
		elif roll < 0.58:
			deco.wall(p, yaw, rng.randf_range(40.0, 80.0), rng.randf_range(16.0, 26.0))
		elif roll < 0.72:
			deco.siege_tower_prop(p, yaw, rng.randf_range(16.0, 28.0))
		elif roll < 0.86:
			var tb: SiegeTrebuchet = deco.trebuchet(p, yaw, rng.randf_range(2.0, 3.2))
			tb.phase = rng.randf()
		else:
			for k: int in 4:
				deco.tent(p + Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14)), rng.randf() * TAU,
					Vector3(6.0, 5.0, 8.0), Color(0.6, 0.5, 0.4) if rng.randf() < 0.5 else Color(0.6, 0.2, 0.18))
			deco.campfire(p)
		placed += 1
	# smoke columns from burning camps and villages, leaning on the wind
	for i: int in 9:
		var sp := Vector3(rng.randf_range(lo.x - 150.0, hi.x + 150.0), lo.y - 70.0, rng.randf_range(lo.z - 150.0, hi.z + 150.0))
		SiegeFx.smoke_column(self, sp, rng.randf_range(80.0, 140.0), rng.randf_range(14.0, 22.0), 30)
		SiegeFx.fire(self, sp + Vector3(0, 1.0, 0), 4.0)
	# ambient life along the route: embers rising off the fires and ash sifting through
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 9.0, absf(here.z - prev.z) * 0.5 + 12.0)
		SiegeFx.embers(self, c3 - Vector3(0, 3.0, 0), ext * Vector3(0.8, 0.9, 0.8), 36)
		SiegeFx.ash(self, c3 + Vector3(0, 3.0, 0), ext, 50)
	if _cp_world.is_empty():
		SiegeFx.embers(self, mid, Vector3(30, 9, 30), 36)


## Swap every walkable surface to the masonry shader (same colours and sizes).
func _siege_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = preload("res://visual/siege_stone.gdshader")
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


# ---- live effects -----------------------------------------------------------------------------------

func _finish_sequence() -> void:
	var cols: Array[Color] = [CRIMSON, GOLD, FIRE, CRIMSON, GOLD]
	for i: int in cols.size():
		var fw: GPUParticles3D = SiegeFx.finale(cols[i], 80)
		fw.position = _finish_pos + Vector3(-6.0 + 3.0 * float(i), 6.0 + float(i % 2) * 3.0, -2.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	var fx: Array[GPUParticles3D] = SiegeFx.cp_burst(GOLD)
	for p2: GPUParticles3D in fx:
		p2.position = _finish_pos + Vector3(0, 0.6, 0)
		add_child(p2)
		p2.restart()
		p2.emitting = true
	# SOUND: siege_finish - the banner is raised: a brass fanfare over drums and a roar of the army
	WorldAudio.at(self, "siege_finish", _finish_pos + Vector3(0, 3.0, 0), 1.0, 120.0)
	await get_tree().create_timer(0.9).timeout
