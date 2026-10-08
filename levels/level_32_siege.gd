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
##  3 Boulder Field    a post, the 16 m causeway under two BOULDERS and the barbican GAP WALL (kit),
##                      WALL RUN the siege-tower hoarding
##  4 The Gatehouse     BRANCH: a 12 m beam under two ARROW VOLLEYS | a court under BOILING OIL + MANTLE
##                      [shortcut: arrow-slit stones across the middle]
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
const DEV_LAST: int = 0

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


## Warning lamps that flash for `lead` seconds before a cycling machine's hazard begins (at fraction `u0` of
## its period) with a clip: the tell for crushers and pistons, whose own build-up is too short.
var _tells: Array[Dictionary] = []


func _tell_lamp(parent: Node3D, pos: Vector3, period: float, phase: float, u0: float, lead: float, clip: String) -> void:
	var mat: StandardMaterial3D = Look.flat(Color(1.0, 0.55, 0.1), 0.4, 0.0, 0.0).duplicate() as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 0.0
	var lamp := Look.sphere(0.17, mat, pos)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lamp)
	_tells.append({"mat": mat, "period": period, "phase": phase, "u0": u0, "lead": lead, "clip": clip, "node": lamp, "was": false})


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	for e: Dictionary in _tells:
		var period: float = e["period"]
		var u: float = fposmod(t / period + float(e["phase"]), 1.0)
		var s_to: float = fposmod((float(e["u0"]) - u) * period, period)
		var on: bool = s_to < float(e["lead"]) and s_to > 0.0
		var mat: StandardMaterial3D = e["mat"]
		mat.emission_energy_multiplier = (5.0 if fmod(t, 0.24) < 0.14 else 1.2) if on else 0.0
		if on and not bool(e["was"]):
			# SOUND: siege_warning_horn - a short horn blast / rattle one second before the machine strikes
			WorldAudio.at(self, str(e["clip"]), (e["node"] as Node3D).global_position, 0.8, 40.0)
		e["was"] = on


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
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14]
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
	var b1: SiegeBoulder = _boulder(Vector3(cwc.x, cwc.y, cwc.z + 4.6), 1.55, 4.6, 0.55, Vector3(-8, 44, -64))
	var b2: SiegeBoulder = _boulder(Vector3(cwc.x, cwc.y, cwc.z + 1.4), 1.55, 4.6, 0.45, Vector3(8, 44, -64))
	# the barbican gate: a sliding iron-bound bulkhead across the causeway (kit gap wall)
	var gw: GapWall = kit.gap_wall(_w(Vector3(cwc.x, cwc.y, cwc.z - 3.6)), _yaw, 3.4, 10.0, 0.0, {"open_time": 4.0})
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
	_wait(func() -> bool: return b1.is_clear_between(Game.course_time, 0.1, 0.7 + 1.5) and b2.is_clear_between(Game.course_time, 0.5, 1.1 + 1.5),
		_w(Vector3(cwc.x, cwc.y, z0 - 1.2)))
	r_walk(_w(Vector3(cwc.x, cwc.y, cwc.z - 0.9)))
	_wait(func() -> bool: return gw.is_open_for(Game.course_time, 0.8 + 1.5), _w(Vector3(cwc.x, cwc.y, cwc.z - 0.9)))
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


# ---- stage 4: The Gatehouse (BRANCH) - the gap-wall portcullis lane | boiling oil court + mantle -----
# [shortcut: arrow-slit stones across the middle]

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	# LEFT: a 12 m beam under two arrow volleys loosed from the gatehouse's murder slits
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.5)
	var lane: Dictionary = _blk(_ahead(left, 0.86, 0.0, 12.0), 1.2, 12.0, "alt", 0.6)
	var lc: Vector3 = lane["c"]
	var va := SiegeVolley.new()
	va.size = Vector2(2.0, 3.0)
	va.period = 5.0
	va.phase = 0.0
	va.rotation.y = deg_to_rad(_yaw)
	va.position = _w(Vector3(lc.x, lc.y, lc.z + 2.5))
	add_child(va)
	var vb := SiegeVolley.new()
	vb.size = Vector2(2.0, 3.0)
	vb.period = 5.0
	vb.phase = 0.3
	vb.rotation.y = deg_to_rad(_yaw)
	vb.position = _w(Vector3(lc.x, lc.y, lc.z - 2.5))
	add_child(vb)
	var pa: Dictionary = _post(_ahead(lane, 0.88, 0.0, 1.2))
	var mc: Vector3 = _ahead(pa, 0.86, 0.0, 3.0)
	var merge: Dictionary = _blk(Vector3(0, mc.y, mc.z), 11.0, 3.0)
	# RIGHT: a court the oil sweeps across, a timber beam, then mantle the guardroom wall
	var right: Dictionary = _area(Vector3(3.6, 0, fc.z), 1.5, 1.5)
	var court: Dictionary = _blk(_ahead(right, 0.86, 0.0, 6.0, 0.0), 6.0, 6.0)
	var cc: Vector3 = court["c"]
	var oil := SiegeOil.new()
	oil.length = 6.0
	oil.width = 6.0
	oil.period = 6.0
	oil.speed = 6.0
	oil.pour = 1.2
	oil.tilt_time = 1.2
	oil.rotation.y = deg_to_rad(_yaw)
	oil.position = _w(Vector3(0.6, cc.y, cc.z))
	add_child(oil)
	var case_c: Vector3 = _behind(merge, 0.86, -3.3, 1.6, 3.5)
	var case_top := Vector3(3.5, case_c.y, case_c.z)
	var case: Dictionary = _ledge(case_top, Vector3(2.6, 9.0, 1.6))
	var beam_front: float = case_top.z + 0.8 + 1.6
	var near_z: float = _ahead(court, 0.86, 0.0, 0.0, 3.5).z
	var blen: float = near_z - beam_front
	var beam: Dictionary = _blk(Vector3(3.5, cc.y, (near_z + beam_front) * 0.5), 1.2, blen, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	# SHORTCUT: arrow-slit stones across the middle
	var gap_total: float = (fc.z - 1.5) - (mc.z + 1.5)
	var g_max: float = 0.92 * _reach(0.0) - 0.75
	var n_st: int = clampi(ceili((gap_total - g_max) / (g_max + 1.2)), 2, 6)
	var stones: Array[Dictionary] = _stones(_area(fc, 5.5, 1.5), merge, n_st)
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z)))
		var prev: Dictionary = _area(fc, 5.5, 1.5)
		for s: Dictionary in stones:
			_hop(prev, s)
			prev = s
		_hop(prev, merge, Vector3(0, 0, 0.4))
	elif route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_hop(left, lane, Vector3(0, 0, 5.0))
		_wait(func() -> bool: return va.is_clear_between(Game.course_time, 0.2, 0.85 + 1.5) and vb.is_clear_between(Game.course_time, 0.7, 1.3 + 1.5),
			_w(Vector3(lc.x, lc.y, lc.z + 5.0)))
		r_walk(_w(Vector3(lc.x, lc.y, lc.z - 5.2)))
		_hop(lane, pa)
		_hop(pa, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.5, 0, fc.z + 0.6)))
		_wait(func() -> bool: return oil.clear_for(2.9, 0.5, 2.0 + 1.5), _w(Vector3(3.5, 0, fc.z + 0.6)))
		_hop(right, court, Vector3(-0.1, 0, 1.0))
		r_walk(_w(Vector3(3.5, cc.y, cc.z - 2.4)))
		r_jump(_w(Vector3(3.5, cc.y, cc.z - 3.0 + 0.35)), _w(Vector3(3.5, bc.y, bc.z + blen * 0.5 - 0.6)))
		r_walk(_w(Vector3(3.5, bc.y, beam_front + 0.9)))
		r_mantle(_w(Vector3(3.5, bc.y, beam_front + 0.35)), _w(case_top + Vector3(0, 0, 0.2)))
		_hop(case, merge, Vector3(3.5, 0, 0.6))
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, fc.z + 1.2), CRIMSON)
	_sign(Vector3(3.6, 0, fc.z + 1.2), GOLD)
	_guard_dress(case_top, 2.6, 9.0, 1.6)
	var yr: float = deg_to_rad(_yaw)
	deco.gatehouse(_w(Vector3(lc.x, lc.y - 26.0, lc.z + 10.0)), yr, 12.0, 24.0)
	deco.brazier(_w(Vector3(-5.0, 0.0, fc.z + 0.6)), 1.0)
	return cp["c"]


## Fork signpost: two posts with glowing caps and a strip on the floor in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.12, 2.2, 0.12), Look.flat(Color(0.3, 0.2, 0.13), 0.9), _w(p + Vector3(sx * 1.1, 1.1, 0))))
		var lamp := Look.sphere(0.2, Look.flat(col, 0.3, 0.0, 3.0), _w(p + Vector3(sx * 1.1, 2.35, 0)))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.5)), _sz(Vector3(1.2, 0.05, 0.25)), col)


## A stone guard-room wall you mantle: dark arrow slits, a lit window and iron straps.
func _guard_dress(top: Vector3, w: float, h: float, d: float) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(_b, _w(top - Vector3(0, h * 0.5, 0)))
	add_child(n)
	var iron: StandardMaterial3D = Look.flat(Color(0.15, 0.15, 0.17), 0.45, 0.7)
	for sz: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(w * 0.9, 0.2, 0.05), iron, Vector3(0, -h * 0.5 + h * 0.45, sz * (d * 0.5 + 0.03))))
		var win := Look.box(Vector3(0.22, 1.0, 0.06), Look.flat(Color(1.0, 0.62, 0.2), 0.4, 0.0, 2.6), Vector3(0, -h * 0.5 + h * 0.62, sz * (d * 0.5 + 0.04)))
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(win)


# ---- stage 5: Siege Tower - ride the tower up the wall, leap onto the battlements through a volley ----

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var dock: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 4.4), 4.4, 4.4)
	var dc: Vector3 = dock["c"]
	var zf: float = dc.z - 2.2
	var rise: float = 10.0
	var run_len: float = 16.0
	var t0 := Vector3(dc.x, dc.y, zf - 1.5 - 1.7)
	var t1: Vector3 = t0 + Vector3(0, rise, -run_len)
	var pts: Array[Vector3] = [Vector3.ZERO, _d(Vector3(0, rise, -run_len))]
	var tower: MovingPlatform = kit.mover(_w(t0), _sz(Vector3(3.4, 0.5, 3.4)), pts, 14.0, 0.0)
	tower.dwell = 0.3
	_tower_dress(tower)
	var near: float = t1.z - 1.7 - 1.2
	var wallp: Dictionary = _blk(Vector3(dc.x, t1.y, near - 4.0), 4.4, 8.0)
	var vol := SiegeVolley.new()
	vol.size = Vector2(4.0, 3.2)
	vol.period = 7.0
	vol.phase = 0.7857
	vol.rotation.y = deg_to_rad(_yaw)
	vol.position = _w(Vector3(dc.x, t1.y, near - 4.2))
	add_child(vol)
	var cp: Dictionary = _cp(_ahead(wallp, 0.86, 0.0, 5.0, -dc.x))
	_hop(cp0, dock)
	r_walk(_w(Vector3(dc.x, dc.y, zf + 0.6)))
	r_wait(tower, _w(t0 - Vector3(0, 0.25, 0)), 0.3)
	r_jump_onto(_w(Vector3(dc.x, dc.y, zf + 0.35)), tower, Vector3(0, 0.2, 0))
	r_jump_from_ride(tower, _w(t1 - Vector3(0, 0.25, 0)), 0.5, _w(Vector3(dc.x, t1.y, near - 2.2)))
	r_walk(_w(Vector3(dc.x, t1.y, near - 1.2)))
	_wait(func() -> bool: return vol.is_clear_between(Game.course_time, 0.1, 1.0 + 1.5), _w(Vector3(dc.x, t1.y, near - 1.2)))
	r_walk(_w(Vector3(dc.x, t1.y, near - 7.3)))
	_hop(wallp, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the outer wall the tower is wheeled up to: a long curtain wall with a tower either side
	var yr: float = deg_to_rad(_yaw)
	deco.wall(_w(Vector3(dc.x, t1.y - 24.0, near - 10.0)), yr + PI * 0.5, 40.0, 24.0)
	deco.tower(_w(Vector3(dc.x - 9.0, t1.y - 28.0, near - 26.0)), 5.0, 32.0, true)
	deco.tower(_w(Vector3(dc.x + 9.0, t1.y - 28.0, near + 4.0)), 5.0, 32.0, true)
	deco.brazier(_w(Vector3(dc.x - 1.8, dc.y, dc.z + 1.6)), 1.0)
	return cp["c"]


## The siege tower under its deck: timber legs, rungs and cross-braces down into the smoke, wheels at
## the foot, hide shields along the deck's sides and a pennant at the back.
func _tower_dress(tower: MovingPlatform) -> void:
	var wood: StandardMaterial3D = Look.flat(Color(0.32, 0.22, 0.14), 0.9)
	var hide: StandardMaterial3D = Look.flat(Color(0.45, 0.32, 0.22), 0.95)
	var h: float = 13.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			tower.add_child(Look.box(Vector3(0.34, h, 0.34), wood, Vector3(sx * 1.6, -0.25 - h * 0.5, sz * 1.6)))
			var wheel := Look.cylinder(0.8, 0.4, wood, Vector3(sx * 1.9, -0.25 - h + 0.3, sz * 1.6), -1.0, 12)
			wheel.rotation.z = PI * 0.5
			tower.add_child(wheel)
	for i: int in 4:
		var y: float = -0.25 - 1.5 - 3.0 * float(i)
		for sx2: float in [-1.0, 1.0]:
			tower.add_child(Look.box(Vector3(0.2, 0.2, 3.4), wood, Vector3(sx2 * 1.6, y, 0)))
		for sz2: float in [-1.0, 1.0]:
			tower.add_child(Look.box(Vector3(3.4, 0.2, 0.2), wood, Vector3(0, y, sz2 * 1.6)))
	tower.add_child(Look.box(Vector3(3.5, h * 0.8, 0.12), hide, Vector3(0, -0.25 - h * 0.45, 1.75)))
	for sx3: float in [-1.0, 1.0]:
		tower.add_child(Look.box(Vector3(0.14, 1.1, 3.4), hide, Vector3(sx3 * 1.78, 0.8, 0)))
	var flag := Look.box(Vector3(0.05, 0.7, 1.0), Look.flat(CRIMSON, 0.7, 0.0, 0.3), Vector3(0, 2.6, 1.6))
	tower.add_child(flag)
	tower.add_child(Look.cylinder(0.04, 2.6, wood, Vector3(0, 1.5, 1.6), -1.0, 4))


# ---- stage 6: The Wall-Walk - a merlon, the 14 m walk under the battering ram, merlons, the turret mantle ----

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.90, 0.0, 1.2))
	var walk: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 14.0), 1.2, 14.0, "alt", 0.6)
	var wc: Vector3 = walk["c"]
	var ram := SiegeRam.new()
	ram.period = 8.0
	ram.rotation.y = deg_to_rad(_yaw)
	ram.position = _w(Vector3(wc.x, wc.y + 1.0 + ram.rope_length, wc.z))
	add_child(ram)
	var p2: Dictionary = _post(_ahead(walk, 0.88, 0.0, 1.2))
	var p3: Dictionary = _post(_ahead(p2, 0.90, 0.6, 1.2, 0.4))
	var p3c: Vector3 = p3["c"]
	var top := Vector3(p3c.x, p3c.y + 3.3, p3c.z - 0.6 - 1.4 - 1.0)
	var ld: Dictionary = _ledge(top, Vector3(2.8, 9.0, 2.0))
	var cp: Dictionary = _cp(_ahead(ld, 0.85, 0.0, 5.0, -p3c.x))
	_hop(cp0, p1)
	_hop(p1, walk, Vector3(0, 0, 6.2))
	_wait(func() -> bool: return ram.clear_between(0.0, 0.4, 1.1 + 1.5), _w(Vector3(wc.x, wc.y, wc.z + 6.2)))
	r_walk(_w(Vector3(wc.x, wc.y, wc.z - 6.2)))
	_hop(walk, p2)
	_hop(p2, p3)
	r_mantle(_w(Vector3(p3c.x, p3c.y, p3c.z - 0.3)), _w(top + Vector3(0, 0, 0.3)))
	_hop(ld, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_guard_dress(top, 2.8, 9.0, 2.0)
	var yr: float = deg_to_rad(_yaw)
	deco.wall(_w(Vector3(wc.x, wc.y - 20.0, wc.z)), yr + PI * 0.5, 60.0, 19.0)
	deco.tower(_w(Vector3(wc.x + 7.0, wc.y - 24.0, wc.z - 30.0)), 4.5, 27.0, false)
	deco.banner(_w(Vector3(wc.x + 4.4, wc.y - 5.0, wc.z + 3.0)), 5.0, yr, CRIMSON)
	return cp["c"]


# ---- stage 7: Portcullis Row - the walk under two falling portcullises, mantle under the third -------

## A portcullis that drops: the crusher, dressed with an iron grille and teeth.
func _portcullis(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var c: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	var iron: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.14), 0.45, 0.75)
	for sz: float in [-1.0, 1.0]:
		for i: int in 7:
			c.add_child(Look.box(Vector3(0.07, size.y * 0.9, 0.07), iron, Vector3(-size.x * 0.4 + size.x * 0.8 * float(i) / 6.0, 0.0, sz * (size.z * 0.5 + 0.05))))
		c.add_child(Look.box(Vector3(size.x * 0.9, 0.08, 0.08), iron, Vector3(0, size.y * 0.2, sz * (size.z * 0.5 + 0.06))))
	# the warning lamp: flashes for the second before the gate drops
	_tell_lamp(c, Vector3(0, size.y * 0.5 + 0.25, 0), period, phase, 0.5, 1.0, "siege_warning_horn")
	return c


func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.2))
	var walk: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 16.0, 0.0), 1.4, 16.0, "alt", 0.6)
	var wc: Vector3 = walk["c"]
	var w0: float = wc.z + 8.0
	var period: float = 6.0
	var t1: float = 2.4
	var t2: float = 3.0
	var t3: float = 3.7
	var c1: Crusher = _portcullis(Vector3(wc.x, wc.y, w0 - 5.0), Vector3(2.2, 1.2, 2.0), 3.2, period, fposmod(0.92 - (t1 - 0.4) / period, 1.0))
	var c2: Crusher = _portcullis(Vector3(wc.x, wc.y, w0 - 10.5), Vector3(2.2, 1.2, 2.0), 3.2, period, fposmod(0.92 - (t2 - 0.4) / period, 1.0))
	var ledge_top := Vector3(wc.x, wc.y + 3.3, w0 - 16.0 - 1.2 - 1.1)
	var ld: Dictionary = _ledge(ledge_top, Vector3(3.6, 9.0, 2.2))
	var c3: Crusher = _portcullis(ledge_top, Vector3(2.4, 1.0, 1.6), 2.6, period, fposmod(0.92 - (t3 - 0.4) / period, 1.0))
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
	_guard_dress(ledge_top, 3.6, 9.0, 2.2)
	var yr: float = deg_to_rad(_yaw)
	deco.wall(_w(Vector3(wc.x - 6.0, wc.y - 18.0, wc.z)), yr + PI * 0.5, 40.0, 17.0)
	deco.tower(_w(Vector3(wc.x + 8.0, wc.y - 22.0, wc.z - 6.0)), 4.0, 25.0, true)
	return cp["c"]


# ---- stage 8: Bailey Gate (BRANCH) - the ballista rams | hall wall run + buttress mantle ------------
# [shortcut: hidden stones down the middle]

## A ballista port that punches a ram across the route: the piston, with a stone embrasure round it.
func _ballista(top: Vector3, dir: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.2)
	var p: Piston = kit.piston(_w(top), size, _yaw - 90.0 * dir, stroke, period, phase, 10.0)
	var b := Basis(Vector3.UP, deg_to_rad(_yaw - 90.0 * dir))
	var depth: float = stroke + 0.45
	var c: Vector3 = _w(top) - Vector3(0, size.y * 0.5, 0) + b * Vector3(0, 0, size.z * 0.5 + depth * 0.5 + 0.02)
	var n := Node3D.new()
	n.transform = Transform3D(b, c)
	add_child(n)
	var stone: StandardMaterial3D = Look.flat(STONE, 0.92)
	var h: float = size.y + 1.8
	var w: float = size.x + 1.0
	n.add_child(Look.box(Vector3(0.5, h, depth), stone, Vector3(-w * 0.5 + 0.25, 0, 0)))
	n.add_child(Look.box(Vector3(0.5, h, depth), stone, Vector3(w * 0.5 - 0.25, 0, 0)))
	n.add_child(Look.box(Vector3(w - 1.0, 0.9, depth), stone, Vector3(0, h * 0.5 - 0.45, 0)))
	n.add_child(Look.box(Vector3(w - 1.0, 0.9, depth), stone, Vector3(0, -h * 0.5 + 0.45, 0)))
	var lamp := Look.box(Vector3(0.5, 0.12, 0.05), Look.flat(Color(1.0, 0.6, 0.2), 0.4, 0.0, 2.4), Vector3(0, h * 0.5 - 0.9, -depth * 0.5 - 0.03))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(lamp)
	_tell_lamp(n, Vector3(0, h * 0.5 + 0.3, -depth * 0.5), period, phase, 0.45, 1.0, "siege_warning_horn")
	return p


func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.5)
	var beam: Dictionary = _blk(_ahead(left, 0.86, 0.0, 12.0), 1.2, 12.0, "alt", 0.6)
	var bz: float = (beam["c"] as Vector3).z
	var d1: Piston = _ballista(Vector3(-3.5 - 0.6 - 0.6 - 0.15, 1.35, bz + 2.5), 1.0, 2.6, 5.0, 0.0)
	var d2: Piston = _ballista(Vector3(-3.5 - 0.6 - 0.6 - 0.15, 1.35, bz - 2.5), 1.0, 2.6, 5.0, fposmod(-0.07, 1.0))
	var pa: Dictionary = _post(_ahead(beam, 0.88, 0.0, 1.2))
	var merge: Dictionary = _blk(Vector3(0, 0, (pa["c"] as Vector3).z - 0.6 - 4.2 - 1.5), 11.0, 3.0)
	kit.wallrun(_w(Vector3(5.7, 1.2, f0 - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(3.6, 0.0, f0 - 19.6), 2.0, 2.0)
	var case_top := Vector3(3.6, 3.3, f0 - 19.6 - 1.0 - 1.6 - 0.8)
	var case: Dictionary = _ledge(case_top, Vector3(2.6, 9.0, 1.6))
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
	_sign(Vector3(-3.5, 0, fc.z + 1.2), CRIMSON)
	_sign(Vector3(3.6, 0, fc.z + 1.2), GOLD)
	_guard_dress(case_top, 2.6, 9.0, 1.6)
	# the great hall wall behind the wall-run panel
	add_child(Look.box(_sz(Vector3(1.4, 14.0, 17.0)), Look.flat(STONE, 0.92), _w(Vector3(6.6, 1.2, f0 - 9.0))))
	deco.wall_banner(_w(Vector3(7.4, 8.0, f0 - 9.0)), Basis(Vector3.UP, deg_to_rad(_yaw) + PI * 0.5), CRIMSON, 3.0, 7.0)
	pb.clear()
	return cp["c"]


# ---- stage 9: The Mace Tower - the spinning mace on a tower top, then the flame gate and the mantle -----

## World park angle (degrees about Y from +X toward -Z) of the local direction `v`.
func _park_deg(v: Vector3) -> float:
	var w: Vector3 = _d(v)
	return rad_to_deg(atan2(-w.z, w.x))


## A flame jet gate: the laser, with a burning brazier on each post and a one-second warning.
func _flame_gate(center: Vector3, period: float, on_frac: float, phase: float) -> LaserGate:
	var g: LaserGate = kit.laser(_w(center), Vector3(3.2, 2.4, 0.2), period, on_frac, phase, _yaw)
	g.warn = 1.0
	var iron: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.16), 0.45, 0.7)
	var post_h: float = maxf(g.size.y + 0.8, 1.2)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (g.size.x * 0.5 + 0.18)
		g.add_child(Look.cylinder(0.3, 0.3, iron, Vector3(x, post_h * 0.5 + 0.15, 0), 0.2, 8))
		var coals := Look.sphere(0.2, Look.flat(Color(1.0, 0.45, 0.1), 0.4, 0.0, 3.0), Vector3(x, post_h * 0.5 + 0.38, 0))
		coals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(coals)
	return g


func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var tw: Dictionary = _blk(_ahead(cp0, 0.88, 0.0, 11.0), 11.0, 11.0)
	var tc: Vector3 = tw["c"]
	var ham: SpinHammer = kit.hammer(_w(tc), 4.5, 7.2, 0.0, _park_deg(Vector3(-1, 0, 0)), 1.0)
	var p1: Dictionary = _post(_ahead(tw, 0.88, 0.0, 1.2, 2.4))
	var p2: Dictionary = _post(_ahead(p1, 0.90, 0.6, 1.2, -0.4))
	var beam: Dictionary = _blk(_ahead(p2, 0.86, 0.0, 14.0, -0.4), 1.2, 14.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 7.0
	var l1: LaserGate = _flame_gate(Vector3(bc.x, bc.y + 1.2, bc.z + 2.5), 5.0, 0.3, 0.0)
	var l2: LaserGate = _flame_gate(Vector3(bc.x, bc.y + 1.2, bc.z - 2.5), 5.0, 0.3, fposmod(-0.12, 1.0))
	var ward_top := Vector3(bc.x, bc.y + 3.3, front - 1.4 - 0.9)
	var ward: Dictionary = _ledge(ward_top, Vector3(2.8, 9.0, 1.8))
	var cp: Dictionary = _cp(_ahead(ward, 0.85, 0.0, 5.0, -bc.x))
	r_walk(_w(Vector3(2.4, 0, 1.2)))
	_wait(func() -> bool: return ham.is_parked_for(Game.course_time, 2.9 + 1.5), _w(Vector3(2.4, 0, 1.2)))
	_hop(cp0, tw, Vector3(2.4, 0, 4.6))
	r_walk(_w(Vector3(2.4, tc.y, tc.z - 4.6)))
	r_jump(_w(Vector3(2.4, tc.y, tc.z - 5.5 + 0.35)), _w((p1["c"] as Vector3)))
	_hop(p1, p2)
	r_walk(_w(_edge(p2, bc + Vector3(0, 0, 6.2))))
	_wait(func() -> bool: return _dark(l1, 0.9, 1.9 + 1.5) and _dark(l2, 1.4, 2.4 + 1.5), _w(_edge(p2, bc + Vector3(0, 0, 6.2))))
	_hop(p2, beam, Vector3(0, 0, 6.2))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(ward_top + Vector3(0, 0, 0.3)))
	_hop(ward, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_guard_dress(ward_top, 2.8, 9.0, 1.8)
	deco.tower(_w(Vector3(tc.x - 10.0, tc.y - 30.0, tc.z)), 4.5, 30.0, true)
	deco.banner(_w(Vector3(tc.x - 5.0, tc.y, tc.z + 4.8)), 4.0, deg_to_rad(_yaw), CRIMSON)
	return cp["c"]


# ---- stage 10: The Postern (BRANCH) - the sally-port door | the falling-block corridor ----------------
# [shortcut: the small door on the hanging stone]

## A stone doorway round a warp ring: jambs, a lintel and a lit seam. `floor_pos` / yaw as given to kit.portal.
func _dress_portal(floor_pos: Vector3, yaw_deg: float, col: Color) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), floor_pos)
	add_child(n)
	var stone: StandardMaterial3D = Look.flat(STONE, 0.9)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.4, 3.2, 0.5), stone, Vector3(sx * 1.8, 1.6, 0)))
	n.add_child(Look.box(Vector3(4.2, 0.4, 0.55), stone, Vector3(0, 3.4, 0)))
	n.add_child(Look.box(Vector3(3.6, 0.06, 0.06), Look.flat(col, 0.3, 0.0, 2.4), Vector3(0, 3.18, -0.28)))


func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT: the sally-port door on the fork sends you up onto the lintel beam high ahead
	var hi: Dictionary = _blk(Vector3(-3.5, 4.5, f0 - 9.0), 1.2, 5.0, "alt", 0.6)
	var door: WarpPortal = kit.portal(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, _w(Vector3(-3.5, 4.5, f0 - 7.2)), _yaw, 7.0)
	_dress_portal(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, GOLD)
	_dress_portal(_w(Vector3(-3.5, 4.5, f0 - 7.2)), _yaw, GOLD)
	var la: Dictionary = _post(_ahead(hi, 0.90, -1.5, 1.2, 0.3))
	var la2: Dictionary = _post(_ahead(la, 0.90, -1.5, 1.2, -0.3))
	var mc: Vector3 = _ahead(la2, 0.86, -1.5, 3.0)
	var merge: Dictionary = _blk(Vector3(0, mc.y, mc.z), 11.0, 3.0)
	var mz: float = mc.z
	# RIGHT: a corridor beam under a falling block (the portcullis), then the merge
	var right: Dictionary = _area(Vector3(4.0, 0, fc.z), 1.5, 1.5)
	var rb_near: float = _ahead(right, 0.86, 0.0, 0.0).z
	var rb_front: float = _behind(merge, 0.88, 0.0, 0.0, 4.0).z
	var rb_len: float = rb_near - rb_front
	var rb: Dictionary = _blk(Vector3(4.0, 0, (rb_near + rb_front) * 0.5), 1.2, rb_len, "alt", 0.6)
	var rbz: float = (rb["c"] as Vector3).z
	var blk: FallingBlock = kit.falling_block(_w(Vector3(4.0, 0, rbz)), Vector3(3.0, 1.6, 3.0), 7.0, 6.0, 0.0, false)
	# SHORTCUT: a small stone hangs off the fork's front; the door on it opens onto the merge
	var sp: Dictionary = _post(_ahead(_area(fc, 5.5, 1.5), 0.93, 0.0, 1.2), 1.2, 1.2, "accent")
	var spc: Vector3 = sp["c"]
	var sdoor: WarpPortal = kit.portal(_w(spc + Vector3(0, 0, -0.3)), _yaw, _w(Vector3(0.5, mc.y, mz + 0.8)), _yaw, 6.0)
	_dress_portal(_w(spc + Vector3(0, 0, -0.3)), _yaw, GOLD)
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
		_hop(right, rb, Vector3(0, 0, rb_len * 0.5 - 0.6))
		r_walk(_w(Vector3(4.0, 0, rbz + 4.5)))
		_wait(func() -> bool: return blk.is_clear_for(Game.course_time, 1.4 + 1.5), _w(Vector3(4.0, 0, rbz + 4.5)))
		r_walk(_w(Vector3(4.0, 0, rb_front + 0.9)))
		_hop(rb, merge, Vector3(4.0, 0, 0.6))
	var cp: Dictionary = _cp(_ahead(merge, 0.86, 0.0, 5.0))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, fc.z + 1.2), CRIMSON)
	_sign(Vector3(4.0, 0, fc.z + 1.2), GOLD)
	for k: int in 4:
		var side: float = -1.0 if k % 2 == 0 else 1.0
		deco.brazier(_w(Vector3(side * 5.3, 0, fc.z + 0.4 - 0.9 * float(k % 2))), 1.0)
	deco.keep(_w(Vector3(-16.0, -30.0, f0 - 14.0)), deg_to_rad(_yaw), 16.0, 52.0)
	return cp["c"]


# ---- stage 11: Cannon Wall - the cannons across the long beam, two chained wall runs up the keep wall -----

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.90, 0.0, 1.2))
	var beam: Dictionary = _blk(_ahead(p1, 0.86, 0.0, 16.0), 1.2, 16.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var z_a: float = bc.z + 3.5
	var z_b: float = bc.z - 3.5
	# a cannon each side of the beam, firing across it at chest height
	var bat_a: CannonBattery = kit.battery(_w(Vector3(bc.x - 4.4, bc.y, z_a)), _yaw - 90.0, 14.0, 9.0, 5.0, 0.0, 1.0)
	var bat_b: CannonBattery = kit.battery(_w(Vector3(bc.x + 4.4, bc.y, z_b)), _yaw + 90.0, 14.0, 9.0, 5.0, 0.06, 1.0)
	var wr0: Dictionary = _blk(_ahead(beam, 0.88, 0.0, 3.0, 0.0), 6.0, 3.0)
	var w0c: Vector3 = wr0["c"]
	var xs: float = w0c.x + 1.8
	var f0: float = w0c.z - 1.5
	kit.wallrun(_w(Vector3(xs + 1.9, w0c.y + 1.2, f0 - 7.0)), Vector3(12.0, 6.5, 0.6), _yaw + 90.0)
	kit.wallrun(_w(Vector3(xs - 2.7, w0c.y + 3.6, f0 - 17.5)), Vector3(9.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _post(Vector3(xs - 0.6, w0c.y, f0 - 27.6), 1.6, 1.6)
	var pb2: Dictionary = _post(_ahead(pb, 0.88, 0.0, 1.2))
	var cp: Dictionary = _cp(_ahead(pb2, 0.86, 0.0, 5.0, -(pb2["c"] as Vector3).x))
	_hop(cp0, p1)
	_hop(p1, beam, Vector3(0, 0, 7.2))
	var d: float = 4.4 - 1.9
	_wait(func() -> bool: return bat_a.is_clear_for(d - 0.7, d + 0.7, 0.6 + 0.5 + 1.5) and bat_b.is_clear_for(d - 0.7, d + 0.7, 1.1 + 0.5 + 1.5),
		_w(Vector3(bc.x, bc.y, bc.z + 7.2)))
	r_walk(_w(Vector3(bc.x, bc.y, bc.z - 7.2)))
	_hop(beam, wr0)
	r_walk(_w(Vector3(xs, w0c.y, f0 + 0.9)))
	r_wallrun(_w(Vector3(xs + 0.4, w0c.y, f0 + 0.35)), _w(Vector3(xs + 1.4, w0c.y + 1.4, f0 - 3.2)), _w(Vector3(xs + 1.4, w0c.y + 1.4, f0 - 10.6)), _w(Vector3(xs - 2.2, w0c.y + 4.4, f0 - 14.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(xs - 2.2, w0c.y + 4.4, f0 - 14.4)), _w(Vector3(xs - 2.2, w0c.y + 4.4, f0 - 19.6)), _w(Vector3(xs - 0.6, w0c.y, f0 - 27.4)), true, true)
	_hop(pb, pb2)
	_hop(pb2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the keep wall behind the wall-run panels, with a great banner, and the gun platforms
	add_child(Look.box(_sz(Vector3(1.4, 16.0, 30.0)), Look.flat(STONE, 0.92), _w(Vector3(xs + 2.8, w0c.y + 2.0, f0 - 12.0))))
	deco.wall_banner(_w(Vector3(xs + 3.6, w0c.y + 9.0, f0 - 12.0)), Basis(Vector3.UP, deg_to_rad(_yaw) + PI * 0.5), CRIMSON, 3.0, 8.0)
	return cp["c"]


# ---- stage 12: Crumbling Stair - six crumbling steps under an arrow volley -----------------------------
# [shortcut: a max-height mantle up the buttress, then its narrow cornice]

## A crumbling stair step (square), gone a moment after you land on it.
func _crumble(top: Vector3, edge: float = 1.4, delay: float = 0.9) -> Dictionary:
	var cpl := CollapsingPlatform.new()
	cpl.size = Vector3(edge, 0.4, edge)
	cpl.delay = delay
	cpl.respawn = 3.0
	cpl.is_round = false
	cpl.rotation.y = deg_to_rad(_yaw)
	cpl.position = _w(top) - Vector3(0, 0.2, 0)
	add_child(cpl)
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
	var vol := SiegeVolley.new()
	vol.size = Vector2(2.4, 2.4)
	vol.period = 6.0
	vol.phase = 0.0
	vol.rotation.y = deg_to_rad(_yaw)
	vol.position = _w(lc)
	add_child(vol)
	prev = land
	for i: int in 2:
		prev = _crumble(_ahead(prev, 0.87, 0.6, 1.4, 0.4 if i == 0 else -0.4))
		steps.append(prev)
	var cp: Dictionary = _cp(_ahead(prev, 0.86, 0.0, 5.0, -(prev["c"] as Vector3).x))
	var cpc: Vector3 = cp["c"]
	var t_land: float = 4.35
	# SHORTCUT: the buttress beside the checkpoint (a 4.1 m mantle) and its narrow cornice running on to the checkpoint
	var col: Dictionary = _ledge(Vector3(1.9, 4.1, -2.5 - 0.9), Vector3(1.4, 12.0, 1.8), "accent")
	var cor_front: float = _behind(cp, 0.88, cpc.y - 4.1, 0.0, 1.9).z
	var cor_near: float = -2.5 - 1.8
	var cor_len: float = cor_near - cor_front
	var cornice: Dictionary = _blk(Vector3(1.9, 4.1, (cor_near + cor_front) * 0.5), 1.0, cor_len, "accent", 0.5)
	var vol_phase: float = fposmod(-(t_land + 1.2) / 6.0, 1.0)
	vol.phase = vol_phase
	if route_variant == 2:
		r_walk(_w(Vector3(1.9, 0, -1.6)))
		r_mantle(_w(Vector3(1.9, 0, -2.5 + 0.25)), _w(Vector3(1.9, 4.1, -2.5 - 1.0)))
		r_walk(_w(Vector3(1.9, 4.1, cor_front + 0.9)))
		r_jump(_w(Vector3(1.9, 4.1, cor_front + 0.35)), _w(cpc + Vector3(1.9, 0, 1.2)))
	else:
		_wait(func() -> bool: return vol.is_clear_between(Game.course_time, t_land - 0.3, t_land + 0.4 + 1.5))
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
	_guard_dress(Vector3(1.9, 4.1, -3.4), 1.4, 12.0, 1.8)
	var yr: float = deg_to_rad(_yaw)
	deco.stakes(_w(Vector3(-5.5, 0, lc.z)), yr + PI * 0.5, 4, 0.8, 1.6)
	deco.brazier(_w(lc + Vector3(2.0, 0, 0.0)), 1.0)
	return cp["c"]


# ---- stage 13: The Windlass - ride the turning wheel, leap off to the stones, mantle out -----------------

func _stage_13() -> Vector3:
	var hub := Vector3(-3.0, 0, -11.0)
	var arms: Array[Dictionary] = [
		{"pos": Vector3(4.6, 0, 0), "size": Vector3(4.6, 0.5, 1.6)}, {"pos": Vector3(-4.6, 0, 0), "size": Vector3(4.6, 0.5, 1.6)},
		{"pos": Vector3(0, 0, 4.6), "size": Vector3(1.6, 0.5, 4.6)}, {"pos": Vector3(0, 0, -4.6), "size": Vector3(1.6, 0.5, 4.6)},
	]
	var board: RotatingPlatform = kit.spinner(_w(hub), 7.0, arms, 2.4, 0.0, 0.5)
	var m: Dictionary = _post(Vector3(-3.0, 0.5, -22.5), 1.6, 1.6)
	var p2: Dictionary = _post(_ahead(m, 0.86, 0.0, 1.2, 1.0))
	var p3: Dictionary = _post(_ahead(p2, 0.90, 0.6, 1.2, -0.4))
	var p3c: Vector3 = p3["c"]
	var top := Vector3(p3c.x, p3c.y + 3.3, p3c.z - 0.6 - 1.4 - 1.0)
	var ld: Dictionary = _ledge(top, Vector3(2.8, 9.0, 2.0))
	var cp: Dictionary = _cp(_ahead(ld, 0.85, 0.0, 5.0, -p3c.x))
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
	_hop(p2, p3)
	r_mantle(_w(Vector3(p3c.x, p3c.y, p3c.z - 0.3)), _w(top + Vector3(0, 0, 0.3)))
	_hop(ld, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_windlass_dress(board, arms)
	deco.banner(_w(Vector3(-9.0, 0, -5.0)), 4.5, deg_to_rad(_yaw), GOLD)
	deco.rubble(_w(Vector3(6.0, -8.0, -12.0)), 5)
	return cp["c"]


## The wheel is a windlass: dark planks across its arms, an iron-banded drum and a coil of rope on the hub.
func _windlass_dress(board: RotatingPlatform, arms: Array[Dictionary]) -> void:
	var plank: StandardMaterial3D = Look.flat(Color(0.2, 0.14, 0.1), 0.9)
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
			var psz := Vector3(maxf(sz.x, sz.z) / float(n), 0.02, minf(sz.x, sz.z) - 0.3) if along_x else Vector3(minf(sz.x, sz.z) - 0.3, 0.02, maxf(sz.x, sz.z) / float(n))
			var sq := Look.box(psz, plank, pos + off + Vector3(0, sz.y * 0.5 + 0.011, 0))
			sq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			board.add_child(sq)
	var tm := TorusMesh.new()
	tm.inner_radius = 2.2
	tm.outer_radius = 2.35
	tm.rings = 48
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, Look.flat(GOLD, 0.3, 0.0, 1.6), Vector3(0, 0.27, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(ring)


# ---- stage 14: Keep Gate - three stones under staggered boulders, mantle the keep's plinth ------------------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var q1: Dictionary = _post(_ahead(cp0, 0.88, 0.0, 1.4), 1.4, 1.4)
	var q2: Dictionary = _post(_ahead(q1, 0.90, 0.6, 1.3, 0.4), 1.3, 1.3)
	var q3: Dictionary = _post(_ahead(q2, 0.90, 0.6, 1.3, -0.4), 1.3, 1.3)
	var q4: Dictionary = _post(_ahead(q3, 0.92, 0.0, 1.2, 0.4))
	var q4c: Vector3 = q4["c"]
	var top := Vector3(q4c.x, q4c.y + 3.3, q4c.z - 0.6 - 1.4 - 1.0)
	var ld: Dictionary = _ledge(top, Vector3(3.0, 9.0, 2.0))
	var cp: Dictionary = _cp(_ahead(ld, 0.85, 0.0, 5.0, -q4c.x))
	var period: float = 4.8
	var rings: Array[SiegeBoulder] = []
	var posts: Array[Dictionary] = [q1, q2, q3]
	var base_ph: float = 0.0
	for i: int in 3:
		var c: Vector3 = (posts[i]["c"] as Vector3)
		rings.append(_boulder(c, 1.5, period, base_ph - 0.18 * float(i), Vector3(-6.0 + 6.0 * float(i), 44, -64)))
	var rr: Array[SiegeBoulder] = rings
	_wait(func() -> bool: return rr[0].is_clear_between(Game.course_time, 0.5, 0.95 + 1.5) and rr[1].is_clear_between(Game.course_time, 1.3, 1.8 + 1.5) \
		and rr[2].is_clear_between(Game.course_time, 2.1, 2.65 + 1.5))
	_hop(cp0, q1)
	_hop(q1, q2)
	_hop(q2, q3)
	_hop(q3, q4)
	r_mantle(_w(Vector3(q4c.x, q4c.y, q4c.z - 0.3)), _w(top + Vector3(0, 0, 0.3)))
	_hop(ld, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_guard_dress(top, 3.0, 9.0, 2.0)
	var yr: float = deg_to_rad(_yaw)
	deco.keep(_w(Vector3(0.0, (q1["c"] as Vector3).y - 30.0, q4c.z - 14.0)), yr, 20.0, 64.0)
	return cp["c"]



# ---- stage 15: THE TREBUCHET - flung over the inner wall, up the keep to the banner -----------------------

var _finish_light: OmniLight3D
var _banner_flag: Node3D


func _stage_15() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	# the yard: the trebuchet's sling basket (the launch barrel) stands on a stone apron
	var yard: Dictionary = _blk(_ahead(cp0, 0.86, 0.0, 6.0), 6.0, 6.0)
	var yc: Vector3 = yard["c"]
	var barrel_at := Vector3(0, yc.y, yc.z - 0.4)
	# the foot of the keep, 22 m on and 6 m up, past the inner wall; the climb is Void-style, relative to it
	var kz: float = barrel_at.z - 22.0
	var kland: Dictionary = _blk(Vector3(0, 6.0 + yc.y, kz + 0.5), 6.0, 6.4, "alt", 1.0)
	var origin_z: float = kz - 1.5 + 15.2
	var oy: float = yc.y
	var barrel: LaunchBarrel = kit.barrel(_w(barrel_at), _w(Vector3(0, 6.0 + yc.y, kz)), 6.0, 4.0, 0.0, 1.2)
	# the climb: three buttress panels up the keep, the roof ledge, then merlons to the banner
	_chimney_panel(2.3, oy + 7.2, origin_z - 19.5, origin_z - 26.0)
	_chimney_panel(-2.3, oy + 12.0, origin_z - 24.5, origin_z - 32.5)
	_chimney_panel(2.3, oy + 15.0, origin_z - 30.5, origin_z - 38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, oy + 17.9, origin_z - 42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var m1: Dictionary = _post(_ahead(top, 0.88, 0.6, 1.3, 0.75), 1.3, 1.3)
	var m2: Dictionary = _post(_ahead(m1, 0.90, 0.6, 1.2, -0.4))
	var m3: Dictionary = _post(_ahead(m2, 0.92, 0.6, 1.2, 0.4))
	var roof: Dictionary = _blk(_ahead(m3, 0.88, 0.6, 6.0, -0.4), 6.0, 6.0, "goal", 1.2)
	var rc: Vector3 = roof["c"]
	kit.finish(_w(rc + Vector3(0, 0, -0.4)), _yaw)
	_finish_pos = _w(rc + Vector3(0, 0, -0.4))
	_hop(cp0, yard)
	r_barrel(barrel, _w(Vector3(0, 6.0 + yc.y, kz)))
	r_walk(_w(Vector3(0, 6.0 + yc.y, kz + 1.0)))
	r_wallrun(_w(Vector3(0.5, oy + 6.0, origin_z - 15.95)), _w(Vector3(1.7, oy + 7.4, origin_z - 20.6)), _w(Vector3(1.7, oy + 7.4, origin_z - 23.5)), _w(Vector3(-1.7, oy + 11.5, origin_z - 27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, oy + 11.5, origin_z - 27.4)), _w(Vector3(-1.7, oy + 11.5, origin_z - 30.4)), _w(Vector3(1.7, oy + 14.5, origin_z - 34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, oy + 14.5, origin_z - 34.0)), _w(Vector3(1.7, oy + 14.5, origin_z - 35.4)), _w(Vector3(-0.75, oy + 17.9, origin_z - 40.6)), true, true)
	_hop(top, m1)
	_hop(m1, m2)
	_hop(m2, m3)
	_hop(m3, roof, Vector3(0, 0, 1.2))
	r_walk(_w(rc + Vector3(0, 0, -0.6)))
	# the trebuchet beside the basket, throwing when you are flung; the inner wall it throws over
	var yr: float = deg_to_rad(_yaw)
	var tb: SiegeTrebuchet = deco.trebuchet(_w(Vector3(-6.2, yc.y, yc.z + 1.0)), yr, 1.0)
	tb.link_barrel(barrel)
	deco.wall(_w(Vector3(0, yc.y - 6.0, (barrel_at.z + kz) * 0.5)), yr, 36.0, 12.0)
	deco.keep(_w(Vector3(18.0, oy - 4.0, origin_z - 28.0)), yr, 22.0, 42.0)
	deco.brazier(_w(Vector3(2.4, yc.y, yc.z + 2.2)), 1.0, true)
	deco.brazier(_w(Vector3(-2.4, yc.y, yc.z + 2.2)), 1.0)
	deco.banner(_w(Vector3(2.4, rc.y, rc.z + 1.6)), 7.0, yr, CRIMSON, 2.2, 4.6)
	deco.banner(_w(Vector3(-2.4, rc.y, rc.z + 1.6)), 7.0, yr, GOLD, 2.2, 4.6)
	# the great banner: the finish stands under a huge standard on a tall staff
	deco.banner(_w(rc + Vector3(0, 0, -2.2)), 16.0, yr, CRIMSON, 4.4, 9.0)
	_finish_light = OmniLight3D.new()
	_finish_light.light_color = Color(1.0, 0.6, 0.25)
	_finish_light.light_energy = 2.0
	_finish_light.omni_range = 14.0
	_finish_light.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(_finish_light)


func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	# the stone of the keep behind the panel
	var stone: StandardMaterial3D = Look.flat(STONE, 0.92)
	add_child(Look.box(_sz(Vector3(0.9, height + 1.0, absf(z0 - z1) + 0.4)), stone, _w(Vector3(x + signf(x) * 0.7, y, (z0 + z1) * 0.5))))




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
