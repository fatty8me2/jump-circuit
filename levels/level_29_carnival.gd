extends LevelBase
## 29. CARNIVAL CHAOS - a funfair at sunset (the MEDIUM tier: playful, readable, generous landings; the hardest
## main-path jump sits at 82-86% of max reach and almost every landing is 1.4 m or more across). Painted
## boardwalk decks float over the dark, lit fairground, linked by string lights; you ride a carousel, coaster
## cars and Ferris-wheel gondolas, step across whack-a-mole pistons, get swatted by a pinball flipper, run the
## midway between rolling balls, and finish by being fired out of the human-cannonball cannon to the big top.
## Eighteen stages, seventeen checkpoints.
##
##  1 Ticket Gate     three posts and a beam, MANTLE the ticket booth
##  2 Mole Row        four WHACK-A-MOLE pistons pop up in a wave
##  3 Carousel        board the turning CAROUSEL and leap off to the far post
##  4 Strongman       the SPINNING HAMMER on a round deck, then WALL RUN the striped tent wall
##  5 Pinball Pier    BRANCH: five hops (84%) | the FLIPPER swats you across [shortcut: 90% leap to the merge]
##  6 Coaster Station BRANCH: ride the COASTER CAR over the chasm | the SEESAW planks
##  7 Mallet Alley    ring-toss CANNONBALL lane, then MALLET PISTONS punch across a beam
##  8 Ferris Wheel    board the turning WHEEL's gondolas, ride up, MANTLE out at the top [shortcut: wall run]
##  9 Zipline         BRANCH: the ZIPLINE over the midway | the mole stepping stones
## 10 Funhouse Doors  GAP WALLS slide shut, then the MIRROR BEAMS (lasers)
## 11 Hall of Mirrors BRANCH: the funhouse DOOR (portal) | MANTLE route [shortcut]
## 12 Drop Tower      FALLING BLOCKS and the dropping weights (crusher), WALL RUN onto the tower
## 13 Barrel Rollers  the ROLLING LOG, moles, WALL RUN [shortcut]
## 14 Big Dipper      the second COASTER, a long hill ride up [shortcut]
## 15 Twin Carousels  two counter-turning carousels, mole stones between
## 16 Midnight Wheel  the great wheel's gondolas to the big top roof [shortcut]
## 17 Big Top Climb   the tent climb: mantles, mallets, a wall run
## 18 THE HUMAN CANNONBALL (set piece): load into the great cannon, sit out the fuse, and be fired across
##                    the fairground to the finish under the big top
##
## Carnival mechanics (own scripts): CarnivalMole (whack-a-mole pistons), CarnivalCarousel, CarnivalCoaster
## (rideable car on a rail), CarnivalWheel (+ its Gondola platforms), CarnivalCannon (the cannon set piece).
## Visuals: visual/carnival_{sky,decor,fx}.gd, carnival_{tile,stripe,ground}.gdshader.
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut.
## Every wait the bot makes holds for 1.5 s more.

const RED := Color(0.93, 0.2, 0.26)
const CREAM := Color(0.99, 0.94, 0.82)
const GOLD := Color(1.0, 0.8, 0.25)
const TEAL := Color(0.2, 0.75, 0.8)
const PINK := Color(1.0, 0.42, 0.62)

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: CarnivalDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable surface (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _floors: Array[Dictionary] = []
var _finish_light: OmniLight3D
var _stage_no: int = 0


func _configure() -> void:
	theme_id = "carnival"
	music_track = "carnival"
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


## A walkable deck (local top centre `c`, sx across, sz along).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, keel: float = 0.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw)
	_floors.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": thick, "stage": _stage_no})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A small floating post (a landing about 1.6-2 m across).
func _post(c: Vector3, sx: float = 1.8, sz: float = 1.8, style: String = "accent") -> Dictionary:
	return _blk(c, sx, sz, style, 0.6)


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	_floors.append({"top": _w(top), "size": _sz(Vector3(size.x, 0, size.z)), "drop": size.y, "stage": _stage_no})
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
	route[route.size() - 1]["land_w"] = minf(float(b["hx"]), float(b["hz"])) * 2.0
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
	var col: Color = GOLD if _cp_world.size() % 2 == 0 else PINK
	var fx: Array[GPUParticles3D] = CarnivalFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: carnival_checkpoint - a brassy "ta-da" stinger and a ding of the bell
			WorldAudio.at(self, "carnival_checkpoint", which.global_position, 0.9, 40.0)
			for p2: GPUParticles3D in _cp_bursts[which]:
				p2.restart()
				p2.emitting = true)
	# a little bunting arch over every checkpoint
	deco.pole(_w(c + Vector3(-2.2, 0, 0.3)), 4.2, RED)
	deco.pole(_w(c + Vector3(2.2, 0, 0.3)), 4.2, TEAL)
	deco.string_lights(_w(c + Vector3(-2.2, 4.4, 0.3)), _w(c + Vector3(2.2, 4.4, 0.3)), 0.5, 0.55, true)
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


## True when every [mole, from, to] stays fully up over [now + from, now + to].
static func _moles_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as CarnivalMole).up_over(Game.course_time, float(e[1]), float(e[2])):
			return false
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	deco = CarnivalDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	var last: int = stages.size() if DEV_LAST <= 0 else mini(DEV_LAST, stages.size())
	var starts: Array[int] = []
	var origins: Array[Vector3] = []
	_frame(Vector3.ZERO, yaws[0])
	for i: int in last:
		_stage_no = i + 1
		_next_yaw = yaws[i + 1]
		starts.append(route.size())
		origins.append(_o)
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	starts.append(route.size())
	origins.append(_o)
	_stage_no = last + 1
	if last == 17:
		_stage_18()
	else:
		# (dev) the finish right after the last stage built
		var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
		var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "main", 1.2)
		kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
		_finish_pos = _w(Vector3(0, 0, -9.5))
		_hop(cp0, fin)
		r_walk(_w(Vector3(0, 0, -9.8)))
	player_failed.connect(func(c: String) -> void: print("FAILCAUSE ", c, " ", player.global_position, " t=", Game.course_time))  # DEBUG-HOOK
	_surroundings()
	_carnival_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])
		if OS.get_environment("BOT_WAIT_UNTIL") != "":  # DEBUG-HOOK
			var until_t: float = float(OS.get_environment("BOT_WAIT_UNTIL"))  # DEBUG-HOOK
			route.insert(0, {"kind": "b_wait", "test": func() -> bool: return Game.course_time >= until_t})  # DEBUG-HOOK


# ---- stage 1: Ticket Gate - three posts and a beam, mantle the ticket booth -----------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	_floors.append({"top": _w(Vector3.ZERO), "size": Vector3(14, 0, 14), "drop": 2.0, "stage": _stage_no})
	var start: Dictionary = _area(Vector3(0, 0, 0), 7.0, 7.0)
	var p1: Dictionary = _post(_ahead(start, 0.68, 0.0, 1.8))
	var p2: Dictionary = _post(_ahead(p1, 0.72, 0.0, 1.8, -0.5))
	var p3: Dictionary = _post(_ahead(p2, 0.76, 0.4, 1.7, 0.5), 1.7, 1.7)
	var beam: Dictionary = _blk(_ahead(p3, 0.74, 0.0, 3.0, -0.5), 1.6, 3.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 1.5
	# the ticket booth: a mantle wall across a 1.6 m gap, its roof 3.3 m above the beam
	var booth_top := Vector3(bc.x, bc.y + 3.3, front - 1.6 - 0.7)
	var booth: Dictionary = _ledge(booth_top, Vector3(2.8, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(booth, 0.76, 0.0, 5.0, -bc.x))
	_hop(start, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, beam, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(booth_top + Vector3(0, 0, 0.2)))
	_hop(booth, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_booth_dress(booth_top, 2.8, 9.0, 1.4)
	# the entrance: a great lit gate behind the start, bunting, balloons and the first tents
	deco.pole(_w(Vector3(-5.5, 0, 6.0)), 7.0, RED)
	deco.pole(_w(Vector3(5.5, 0, 6.0)), 7.0, TEAL)
	deco.string_lights(_w(Vector3(-5.5, 7.2, 6.0)), _w(Vector3(5.5, 7.2, 6.0)), 1.4, 0.7)
	deco.bunting(_w(Vector3(-5.5, 6.6, 6.0)), _w(Vector3(5.5, 6.6, 6.0)), 1.0, 14)
	deco.balloons(_w(Vector3(-6.2, 0, 3.0)), 5, 4.5)
	deco.balloons(_w(Vector3(6.2, 0, 2.0)), 4, 3.8)
	deco.arrow_sign(_w(Vector3(3.4, 0, -4.8)), deg_to_rad(_yaw), 0.0, GOLD)
	return cp["c"]


## Ticket booth dressing for a mantle wall (local top centre, its size): an awning, a glowing window
## and a striped roof lip.
func _booth_dress(top: Vector3, w: float, h: float, d: float) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(_b, _w(top - Vector3(0, h * 0.5, 0)))
	add_child(n)
	n.add_child(Look.box(Vector3(w + 0.3, 0.2, d + 0.3), Look.flat(RED, 0.5), Vector3(0, h * 0.5 + 0.05, 0)))
	var aw: ShaderMaterial = CarnivalDecor.stripe_mat(RED, CREAM, 10.0)
	for sz: float in [-1.0, 1.0]:
		var awn := Look.box(Vector3(w + 0.4, 0.1, 0.9), aw, Vector3(0, h * 0.5 - 1.3, sz * (d * 0.5 + 0.4)))
		awn.rotation.x = -sz * 0.35
		n.add_child(awn)
		var win := Look.box(Vector3(w * 0.6, 0.9, 0.06), Look.flat(Color(1.0, 0.82, 0.45), 0.3, 0.0, 1.8), Vector3(0, h * 0.5 - 2.2, sz * (d * 0.5 + 0.03)))
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(win)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.14, h + 0.3, d + 0.3), Look.flat(CREAM, 0.5), Vector3(sx * (w * 0.5 + 0.07), -0.1, 0)))


# ---- stage 2: Mole Row - four whack-a-mole pistons pop up in a wave ---------------------------------

## A whack-a-mole piston whose top sits at local `c` when up. `phase` is a fraction of the period.
func _mole(c: Vector3, period: float, phase: float, up_time: float = 5.0) -> CarnivalMole:
	var m := CarnivalMole.new()
	m.size = Vector3(1.9, 0.5, 1.9)
	m.period = period
	m.phase = phase
	m.up_time = up_time
	m.rotation.y = deg_to_rad(_yaw)
	m.position = _w(c) - Vector3(0, 0.25, 0)
	add_child(m)
	_floors.append({"top": _w(c), "size": _sz(Vector3(1.9, 0, 1.9)), "drop": 0.5, "frag": true, "stage": _stage_no})
	return m


func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var period: float = 7.4
	var stagger: float = 0.6
	var moles: Array[CarnivalMole] = []
	var areas: Array[Dictionary] = []
	var prev: Dictionary = cp0
	var pcts: Array[float] = [0.72, 0.74, 0.76, 0.74]
	var dys: Array[float] = [0.0, 0.0, 0.5, 0.0]
	var dxs: Array[float] = [0.0, 0.5, -0.5, 0.4]
	for i: int in 4:
		var c: Vector3 = _ahead(prev, pcts[i], dys[i], 1.9, dxs[i])
		moles.append(_mole(c, period, fposmod(-stagger * float(i) / period, 1.0)))
		var a: Dictionary = _area(c, 0.95, 0.95)
		areas.append(a)
		prev = a
	var cp: Dictionary = _cp(_ahead(prev, 0.76, 0.0, 5.0, -(prev["c"] as Vector3).x))
	# the bot reaches mole i about 1.2 + 0.85 i s after it sets off and leaves it ~0.5 s later
	_wait(func() -> bool: return _moles_ok([[moles[0], 0.8, 2.0 + 1.5], [moles[1], 1.65, 2.85 + 1.5],
			[moles[2], 2.5, 3.7 + 1.5], [moles[3], 3.35, 4.55 + 1.5]]))
	prev = cp0
	for i: int in 4:
		_hop(prev, areas[i])
		prev = areas[i]
	_hop(prev, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the game booth: a painted board of holes along the left, a giant mallet, bunting and balloons
	_mole_booth(Vector3(-6.0, 0, (areas[1]["c"] as Vector3).z))
	deco.balloons(_w(Vector3(6.5, -4.0, (areas[0]["c"] as Vector3).z)), 4, 6.0)
	deco.string_lights(_w(Vector3(-6.0, 5.5, -2.0)), _w(Vector3(6.0, 5.5, (areas[3]["c"] as Vector3).z - 2.0)), 1.6, 0.8)
	return cp["c"]


## The whack-a-mole game's painted backboard standing beside the row (local floor point of its centre).
func _mole_booth(at: Vector3) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(_b, _w(at + Vector3(0, -2.0, 0)))
	add_child(n)
	n.add_child(Look.box(Vector3(0.5, 7.0, 9.0), Look.flat(Color(0.5, 0.25, 0.2), 0.8), Vector3(-0.6, 3.5, 0)))
	n.add_child(Look.box(Vector3(0.3, 1.2, 9.4), Look.flat(RED, 0.5), Vector3(-0.5, 7.2, 0)))
	var hole := Look.flat(Color(0.08, 0.04, 0.05), 0.9)
	for iy: int in 3:
		for iz: int in 4:
			var disc := Look.cylinder(0.6, 0.05, hole, Vector3(-0.31, 1.6 + 1.7 * float(iy), -3.0 + 2.0 * float(iz)), -1.0, 14)
			disc.rotation.z = PI * 0.5
			n.add_child(disc)
	# a great foam mallet leaning on it
	var handle := Look.box(Vector3(0.22, 4.2, 0.22), Look.flat(Color(0.8, 0.6, 0.3), 0.7), Vector3(0.6, 2.3, 4.6))
	handle.rotation.z = 0.25
	n.add_child(handle)
	var head := Look.cylinder(0.9, 1.8, Look.flat(RED, 0.5), Vector3(1.4, 4.7, 4.6), -1.0, 16)
	head.rotation.z = 0.25 + PI * 0.5
	n.add_child(head)


# ---- stage 3: Carousel - board the turning carousel, leap off to the far post --------------------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.70, 0.0, 2.0), 2.0, 2.0)
	var p1c: Vector3 = p1["c"]
	var radius: float = 4.6
	var hub := Vector3(p1c.x, 0, p1c.z - 1.0 - 2.0 - radius)
	var car := CarnivalCarousel.new()
	car.radius = radius
	car.period = 15.0
	car.position = _w(hub) - Vector3(0, 0.25, 0)
	add_child(car)
	_floors.append({"top": _w(hub), "size": Vector3(radius * 2.0, 0, radius * 2.0), "drop": 0.5, "frag": true, "stage": _stage_no})
	var m: Dictionary = _post(Vector3(hub.x, 0.5, hub.z - radius - 4.0 - 1.0), 2.0, 2.0)
	var p2: Dictionary = _post(_ahead(m, 0.74, 0.0, 2.0, 0.5), 2.0, 2.0)
	var cp: Dictionary = _cp(_ahead(p2, 0.76, 0.0, 5.0, -(p2["c"] as Vector3).x))
	_hop(cp0, p1)
	# ride on: jump to the rim as a ride point comes within reach
	var locals: Array = []
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0
		locals.append(Vector3(cos(a) * (radius - 0.9), 0.25, sin(a) * (radius - 0.9)))
	var stand: Vector3 = _w(_edge(p1, hub))
	r_walk(stand)
	route.append({"kind": "x_jump", "from": stand, "to_node": car, "to_locals": locals, "reach": 3.8, "lead": 0.55})
	var hw: Vector3 = _w(hub)
	var ex: Vector3 = _w(m["c"]) - hw
	ex = Vector3(ex.x, 0, ex.z).normalized()
	var sgn: float = signf(car.period)
	route.append({"kind": "h_jump", "to": _w(m["c"]), "test": func() -> bool:
		var rel: Vector3 = player.global_position - hw
		rel = Vector3(rel.x, 0, rel.z).normalized()
		var a: float = rad_to_deg(atan2(rel.cross(ex).y, rel.dot(ex))) * sgn
		return a >= 8.0 and a <= 22.0})
	_hop(m, p2)
	_hop(p2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	deco.tent(_w(Vector3(hub.x - 14.0, -6.0, hub.z)), 5.5, 4.0, 4.5, 0.4)
	deco.tent(_w(Vector3(hub.x + 13.0, -5.0, hub.z - 6.0)), 4.5, 3.5, 4.0, -0.3, TEAL, CREAM)
	deco.balloons(_w(Vector3(hub.x + 6.0, -2.0, hub.z + 2.0)), 5, 5.0)
	return cp["c"]


# ---- stage 4: Strongman - the spinning hammer on a round deck, then the striped tent wall -----------------

## The wall-run set used by several stages, split in two so the geometry can be built before the
## checkpoint slab exists. From post `w` run a panel on its right (local +x) 16 m and kick onto a post.
## `_wall_geometry` builds the panel, a canvas sheet behind it and the landing post (returned);
## `_wall_route` adds the bot's run.
func _wall_geometry(w: Dictionary, land_size: Vector2 = Vector2(1.8, 2.4)) -> Dictionary:
	var wc: Vector3 = w["c"]
	var f: float = wc.z - float(w["hz"])
	kit.wallrun(_w(Vector3(wc.x + 2.3, wc.y + 1.2, f - 9.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var sheet := Look.box(_sz(Vector3(0.4, 8.0, 17.0)), CarnivalDecor.stripe_mat(RED, CREAM, 18.0), _w(Vector3(wc.x + 2.9, wc.y + 1.4, f - 9.5)))
	add_child(sheet)
	return _post(Vector3(wc.x - 0.6, wc.y, f - 22.5), land_size.x, land_size.y)


func _wall_route(w: Dictionary) -> void:
	var wc: Vector3 = w["c"]
	var f: float = wc.z - float(w["hz"])
	r_wallrun(_w(Vector3(wc.x + 0.3, wc.y, f + 0.35)), _w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 3.6)),
		_w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 14.5)), _w(Vector3(wc.x - 0.6, wc.y, f - 22.2)))


func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.74, 0.0, 2.0), 2.0, 2.0)
	var p1c: Vector3 = p1["c"]
	var radius: float = 7.5
	var dc := Vector3(0.0, 0.0, p1c.z - 1.0 - 2.0 - radius)
	kit.disc(_w(dc), radius, 0.8, "main", 0.0)
	_floors.append({"top": _w(dc), "size": Vector3(radius * 2.0, 0, radius * 2.0), "drop": 0.8, "stage": _stage_no})
	# the hammer: parked toward local -x; the path hugs local +x
	var ham: SpinHammer = kit.hammer(_w(dc), 5.0, 7.0, 0.0, _yaw + 180.0)
	var px: float = 2.2
	var half: float = sqrt(radius * radius - px * px)
	var enter := Vector3(px, 0, dc.z + half - 0.9)
	var leave := Vector3(px, 0, dc.z - half + 0.9)
	var exit_area: Dictionary = _area(Vector3(px, 0, dc.z - half), 1.0, 0.0)
	var w2: Dictionary = _post(_ahead(exit_area, 0.76, 0.0, 1.8), 1.8, 1.8)
	var land: Dictionary = _wall_geometry(w2)
	var cp: Dictionary = _cp(_ahead(land, 0.76, 0.0, 5.0, -(land["c"] as Vector3).x))
	_hop(cp0, p1)
	_hop(p1, _area(Vector3(px, 0, dc.z + half - 1.5), 3.0, 1.5))
	r_walk(_w(enter))
	_wait(func() -> bool: return ham.is_parked_for(Game.course_time, 3.4), _w(enter))
	r_walk(_w(leave))
	_hop(exit_area, w2)
	_wall_route(w2)
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# a strongman's tent: the bell tower of the High Striker beside the disc, flags and bunting
	_high_striker(Vector3(-11.5, -6.0, dc.z))
	deco.tent(_w(Vector3(14.0, -8.0, dc.z - 4.0)), 5.0, 3.5, 4.0, 0.2, TEAL, CREAM)
	deco.bunting(_w(Vector3(-4.0, 6.0, dc.z + 8.0)), _w(Vector3(8.0, 6.0, dc.z + 8.0)), 1.2, 10)
	return cp["c"]


## The High Striker: a tall scale with a bell on top, scenery (local ground point).
func _high_striker(at: Vector3) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(_b, _w(at))
	add_child(n)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.3, 0.8, 0.2)
	n.add_child(Look.box(Vector3(0.8, 16.0, 0.8), CarnivalDecor.stripe_mat(RED, CREAM, 6.0), Vector3(0, 8.0, 0)))
	n.add_child(Look.sphere(1.0, gold, Vector3(0, 16.6, 0)))
	n.add_child(Look.box(Vector3(2.0, 0.6, 2.0), Look.flat(RED, 0.5), Vector3(0, 0.3, 0)))
	n.add_child(Look.cylinder(0.9, 0.4, Look.flat(CREAM, 0.5), Vector3(0, 0.9, 0), -1.0, 12))


# ---- stage 5: Pinball Pier - BRANCH: the flipper swats you across | a plain leap ------------------------------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var deck_a: Dictionary = _blk(_ahead(cp0, 0.72, 0.0, 7.0), 10.0, 7.0)
	var ac: Vector3 = deck_a["c"]
	var zp: float = ac.z - 3.5 + 1.2
	var fl: Flipper = kit.flipper(_w(Vector3(0.5, ac.y, zp)), 5.0, _yaw, 80.0, 5.0, 0.0)
	var deck_b: Dictionary = _blk(Vector3(2.5, ac.y, zp - 9.0), 10.0, 8.0)
	var cp: Dictionary = _cp(_ahead(deck_b, 0.74, 0.0, 5.0, -2.5))
	_hop(cp0, deck_a, Vector3(0, 0, 1.0))
	if route_variant == 1:
		# the plain leap: a normal running jump across the gap
		r_walk(_w(Vector3(0.5, ac.y, zp - 0.2)))
		_hop(deck_a, deck_b, Vector3(0, 0, 3.0))
	else:
		var stand: Vector3 = _w(Vector3(4.6, ac.y, zp))
		r_walk(stand)
		route.append({"kind": "kick", "from": stand, "to": _w(Vector3(2.5, ac.y, zp - 9.0))})
	_hop(deck_b, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	fl.add_child(Look.sphere(0.45, Look.flat(RED, 0.4, 0.0, 0.6), Vector3(4.7, 0.1, 0.0)))
	# pinball bumpers: glowing mushroom caps round the pier
	for k: int in 4:
		var bx: float = [-7.5, 7.5, -8.5, 8.0][k]
		var bz: float = zp - 2.0 - 3.5 * float(k)
		add_child(Look.cylinder(1.2, 1.0, Look.flat(PINK, 0.3, 0.0, 0.8), _w(Vector3(bx, ac.y - 3.0, bz)), 0.9, 16))
		add_child(Look.cylinder(1.25, 0.18, Look.flat(GOLD, 0.3, 0.0, 2.2), _w(Vector3(bx, ac.y - 2.4, bz)), -1.0, 16))
	deco.string_lights(_w(Vector3(-6.0, ac.y + 5.0, ac.z)), _w(Vector3(6.0, ac.y + 5.0, ac.z - 12.0)), 1.4, 0.8)
	return cp["c"]


# ---- stage 6: Coaster Station - BRANCH: ride the coaster car | the seesaw planks ----------------------------------

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.76, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	var y: float = fc.y
	var merge: Dictionary = _blk(Vector3(0, y, f0 - 25.9), 11.0, 3.0)
	# LEFT: the coaster, docked at A beside the fork, running 18.6 m to B beside the merge
	var za: float = f0 - 0.9 - 2.0
	var car := CarnivalCoaster.new()
	car.size = Vector3(3.0, 0.5, 4.0)
	car.points = [Vector3.ZERO, Vector3(0, 1.5, -5.0), Vector3(0, 3.5, -10.0), Vector3(0, 1.5, -14.5), Vector3(0, 0, -18.6)]
	car.dock = 4.0
	car.travel = 5.0
	car.dock_b = 2.5
	car.back = 2.0
	car.position = _w(Vector3(-3.5, y, za)) - Vector3(0, 0.25, 0)
	car.rotation.y = deg_to_rad(_yaw)
	add_child(car)
	# RIGHT: two seesaws and an island
	kit.seesaw(_w(Vector3(3.5, y, f0 - 0.6 - 4.5)), 9.0, 2.6, false, 0.0)
	_blk(Vector3(3.5, y, f0 - 0.6 - 9.0 - 0.6 - 2.0), 4.0, 4.0, "alt", 0.8)
	var s2z: float = f0 - 0.6 - 9.0 - 0.6 - 4.0 - 0.6 - 4.5
	kit.seesaw(_w(Vector3(3.5, y, s2z)), 9.0, 2.6, false, 0.0)
	var cp: Dictionary = _cp(_ahead(merge, 0.76, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 1:
		r_walk(_w(Vector3(3.5, y, f0 + 0.6)))
		r_walk(_w(Vector3(3.5, y, f0 - 1.2)))
		r_walk(_w(Vector3(3.5, y, f0 - 5.1)))
		r_walk(_w(Vector3(3.5, y, f0 - 8.8)))
		r_walk(_w(Vector3(3.5, y, f0 - 11.4)))
		r_walk(_w(Vector3(3.5, y, f0 - 14.0)))
		r_walk(_w(Vector3(3.5, y, s2z + 3.3)))
		r_walk(_w(Vector3(3.5, y, s2z)))
		r_walk(_w(Vector3(3.5, y, s2z - 3.6)))
		r_walk(_w(Vector3(3.5, y, f0 - 25.2)))
		_hop(merge, cp, Vector3(0, 0, 1.2))
	else:
		var stand: Vector3 = _w(Vector3(-3.5, y, f0 + 0.6))
		r_walk(stand)
		_wait(func() -> bool: return car.docked_for(Game.course_time, 0, 3.0), stand)
		route.append({"kind": "x_jump", "from": _w(Vector3(-3.5, y, f0 - 0.1)), "to_node": car, "to_local": Vector3(0, 0.3, 0.2), "hold": true})
		route.append({"kind": "candy_ride", "stand": Vector3(0, 0.3, 0.2), "to": _w(Vector3(0, y, f0 - 25.9 + 0.2)),
			"until": func() -> bool: return car.dock_at(Game.course_time) == 1})
		_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the station: a ticket kiosk and arrow signs for the two ways
	deco.kiosk(_w(Vector3(-8.5, y - 4.0, f0 - 3.0)), deg_to_rad(_yaw) + 1.2, TEAL)
	deco.arrow_sign(_w(Vector3(-4.2, y, fc.z + 0.2)), deg_to_rad(_yaw), -1.0, RED)
	deco.arrow_sign(_w(Vector3(4.2, y, fc.z + 0.2)), deg_to_rad(_yaw), 1.0, TEAL)
	return cp["c"]


# ---- stage 7: Mallet Alley - the ring-toss cannonballs roll across the deck, then mallets punch the beam ---

## A mallet that punches out of a striped launcher across the route: the piston, dressed. `top` is the ram's top
## centre when retracted; it punches toward local +x when `dir` = 1 (-x when -1).
func _mallet(top: Vector3, dir: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.2)
	var p: Piston = kit.piston(_w(top), size, _yaw - 90.0 * dir, stroke, period, phase, 10.0)
	var b := Basis(Vector3.UP, deg_to_rad(_yaw - 90.0 * dir))
	var depth: float = stroke + 0.45
	var c: Vector3 = _w(top) - Vector3(0, size.y * 0.5, 0) + b * Vector3(0, 0, size.z * 0.5 + depth * 0.5 + 0.02)
	var n := Node3D.new()
	n.transform = Transform3D(b, c)
	add_child(n)
	var h: float = size.y + 1.6
	var w: float = size.x + 0.8
	var stripe: ShaderMaterial = CarnivalDecor.stripe_mat(RED, CREAM, 8.0)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.35, 0.7, 0.2)
	n.add_child(Look.box(Vector3(0.4, h, depth), stripe, Vector3(-w * 0.5 + 0.2, 0, 0)))
	n.add_child(Look.box(Vector3(0.4, h, depth), stripe, Vector3(w * 0.5 - 0.2, 0, 0)))
	n.add_child(Look.box(Vector3(w - 0.8, 0.78, depth), stripe, Vector3(0, h * 0.5 - 0.39, 0)))
	n.add_child(Look.box(Vector3(w - 0.8, 0.78, depth), stripe, Vector3(0, -h * 0.5 + 0.39, 0)))
	n.add_child(Look.box(Vector3(w + 0.12, 0.12, depth + 0.12), gold, Vector3(0, h * 0.5 + 0.06, 0)))
	return p


func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var deck: Dictionary = _blk(_ahead(cp0, 0.74, 0.0, 14.0), 8.0, 14.0)
	var dc: Vector3 = deck["c"]
	var lane_z: float = dc.z + 1.0
	# the ring-toss cannon on a little stand at the right, rolling balls across the deck toward local -x
	_blk(Vector3(10.6, dc.y, lane_z), 3.0, 3.0, "alt", 0.8)
	var bat: CannonBattery = kit.battery(_w(Vector3(10.6, dc.y, lane_z)), _yaw + 90.0, 24.0, 9.0, 4.4, 0.0, 0.0)
	var beam: Dictionary = _blk(_ahead(deck, 0.76, 0.0, 12.0), 1.6, 12.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var m1: Piston = _mallet(Vector3(bc.x - 1.55, bc.y + 1.35, bc.z + 2.5), 1.0, 2.6, 5.0, 0.0)
	var m2: Piston = _mallet(Vector3(bc.x - 1.55, bc.y + 1.35, bc.z - 2.5), 1.0, 2.6, 5.0, fposmod(-0.07, 1.0))
	var pa: Dictionary = _post(_ahead(beam, 0.76, 0.0, 2.0), 2.0, 2.0)
	var cp: Dictionary = _cp(_ahead(pa, 0.76, 0.0, 5.0, -(pa["c"] as Vector3).x))
	_hop(cp0, deck, Vector3(0, 0, 5.0))
	r_walk(_w(Vector3(0, dc.y, lane_z + 3.2)))
	# lane stretch d 7.0..10.2 m from the muzzle (1.9 m in front of the node) is where the path crosses it
	_wait(func() -> bool: return bat.is_clear_for(7.0, 10.2, 2.4), _w(Vector3(0, dc.y, lane_z + 3.2)))
	r_walk(_w(Vector3(0, dc.y, lane_z - 4.0)))
	r_walk(_w(Vector3(0, dc.y, dc.z - 6.2)))
	var lane_t: Array[float] = [1.3, 1.85]
	_wait(func() -> bool: return _ram_clear(m1, lane_t[0] - 0.3, lane_t[0] + 0.4 + 1.5) and _ram_clear(m2, lane_t[1] - 0.3, lane_t[1] + 0.4 + 1.5),
		_w(Vector3(0, dc.y, dc.z - 6.2)))
	_hop(deck, beam, Vector3(0, 0, 4.5))
	r_walk(_w(Vector3(bc.x, bc.y, bc.z - 5.2)))
	_hop(beam, pa)
	_hop(pa, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the ring-toss stall: bottles on a shelf, hoops, a striped awning and a row of lights
	deco.kiosk(_w(Vector3(-9.5, dc.y - 4.0, dc.z)), deg_to_rad(_yaw) - 1.4, GOLD)
	deco.string_lights(_w(Vector3(-4.0, dc.y + 6.0, dc.z + 6.0)), _w(Vector3(4.0, dc.y + 6.0, dc.z - 6.0)), 1.4, 0.8)
	deco.balloons(_w(Vector3(7.0, dc.y - 3.0, dc.z - 6.0)), 5, 5.0)
	return cp["c"]


# ---- stage 8: Ferris Wheel - ride a gondola up the front of the wheel, mantle out at the top ---------------------

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var lp: Dictionary = _blk(_ahead(cp0, 0.74, 0.0, 6.0), 5.0, 6.0)
	var zc: float = (lp["c"] as Vector3).z
	var radius: float = 6.5
	var yc: float = radius
	var xw: float = -5.0
	var wheel := CarnivalWheel.new()
	wheel.radius = radius
	wheel.period = 28.0
	wheel.count = 6
	wheel.position = _w(Vector3(xw, yc, zc))
	wheel.rotation.y = deg_to_rad(_yaw)
	add_child(wheel)
	var ed_y: float = yc + 2.0
	_blk(Vector3(0, ed_y, zc - 6.1), 5.0, 6.0)
	var ed_front: float = zc - 6.1 - 3.0
	var ledge_top := Vector3(0, ed_y + 3.3, ed_front - 1.6 - 0.7)
	var ledge: Dictionary = _ledge(ledge_top, Vector3(2.8, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(ledge, 0.76, 0.0, 5.0))
	var centre: Vector3 = _w(Vector3(xw, yc, zc))
	_hop(cp0, lp)
	var stand: Vector3 = _w(Vector3(-2.15, 0, zc))
	r_walk(stand)
	route.append({"kind": "carnival_board", "from": stand, "cars": wheel.gondolas, "fwd": _b * Vector3(0, 0, -1), "lead": 0.5, "local": Vector3(0, 0.3, 0)})
	route.append({"kind": "candy_ride", "stand": Vector3(0, 0.3, 0), "to": _w(Vector3(-0.5, ed_y, zc - 6.1)),
		"until": func() -> bool:
			var fb: Object = player.floor_body
			if not (fb is CarnivalWheel.Gondola):
				return false
			return (fb as Node3D).global_position.y + 0.25 - centre.y >= 2.0})
	r_walk(_w(Vector3(0, ed_y, ed_front + 0.9)))
	r_mantle(_w(Vector3(0, ed_y, ed_front + 0.35)), _w(ledge_top + Vector3(0, 0, 0.2)))
	_hop(ledge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the wheel's boarding steps and a barker's booth; fairy lights strung from the hub to the ground
	deco.kiosk(_w(Vector3(4.8, -4.0, zc + 4.0)), deg_to_rad(_yaw) + 0.3, RED)
	deco.balloons(_w(Vector3(-11.5, -2.0, zc + 2.0)), 6, 6.0)
	deco.pole(_w(Vector3(3.2, 0, zc + 3.4)), 3.5, TEAL)
	return cp["c"]


# ---- stage 9: Zipline Gorge - BRANCH: the zipline over the gorge | the whack-a-mole stepping stones ---------------

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.76, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	var y: float = fc.y
	# RIGHT: five mole stones across the gorge
	var period: float = 7.4
	var moles: Array[CarnivalMole] = []
	var areas: Array[Dictionary] = []
	var prev: Dictionary = _area(Vector3(3.5, y, fc.z), 1.5, 1.5)
	var dxs: Array[float] = [0.0, 0.5, -0.5, 0.5, -0.4]
	for i: int in 5:
		var c: Vector3 = _ahead(prev, 0.74 + 0.01 * float(i % 3), 0.0, 1.9, dxs[i])
		moles.append(_mole(c, period, fposmod(-0.6 * float(i) / period, 1.0)))
		var a: Dictionary = _area(c, 0.95, 0.95)
		areas.append(a)
		prev = a
	var merge: Dictionary = _blk(_ahead(prev, 0.76, 0.0, 8.0, -(prev["c"] as Vector3).x), 11.0, 8.0)
	var mfront: float = (merge["c"] as Vector3).z + 4.0
	# LEFT: the zipline from the fork to the merge deck, 4 m past its edge
	var z_end: float = mfront - 4.0
	var zip: Zipline = kit.zipline(_w(Vector3(-3.5, y, f0 + 0.8)), _w(Vector3(-3.5, y, z_end)), 11.0, 1.4)
	var cp: Dictionary = _cp(_ahead(merge, 0.76, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 1:
		r_walk(_w(Vector3(3.5, y, fc.z)))
		_wait(func() -> bool: return _moles_ok([[moles[0], 0.8, 2.0 + 1.5], [moles[1], 1.65, 2.85 + 1.5],
				[moles[2], 2.5, 3.7 + 1.5], [moles[3], 3.35, 4.55 + 1.5], [moles[4], 4.2, 5.4 + 1.5]]), _w(Vector3(3.5, y, fc.z)))
		prev = _area(Vector3(3.5, y, fc.z), 1.5, 1.5)
		for i: int in 5:
			_hop(prev, areas[i])
			prev = areas[i]
		_hop(prev, merge, Vector3(0, 0, 1.0))
	else:
		r_walk(_w(Vector3(-3.5, y, f0 + 0.6)))
		route.append({"kind": "k_zip", "zip": zip, "point": _w(Vector3(-3.5, y + 2.2, mfront + 2.0)), "radius": 0.6, "to": _w(Vector3(-3.5, y, z_end))})
		r_walk(_w(Vector3(-3.5, y, z_end - 1.0)))
	r_walk(_w(merge["c"] as Vector3))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	deco.arrow_sign(_w(Vector3(-4.2, y, fc.z + 0.2)), deg_to_rad(_yaw), -1.0, GOLD)
	deco.arrow_sign(_w(Vector3(4.2, y, fc.z + 0.2)), deg_to_rad(_yaw), 1.0, TEAL)
	deco.far_wheel(_w(Vector3(24.0, y - 10.0, f0 - 18.0)), 14.0, deg_to_rad(_yaw))
	return cp["c"]


# ---- stage 10: Funhouse Doors - the sliding doors, then the mirror beams [shortcut: the side catwalk] -------------

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var deck: Dictionary = _blk(_ahead(cp0, 0.76, 0.0, 34.0), 7.0, 34.0)
	var dc: Vector3 = deck["c"]
	var y: float = dc.y
	var z0: float = dc.z + 17.0
	var gw1: GapWall = kit.gap_wall(_w(Vector3(0, y, z0 - 8.0)), _yaw, 3.4, 9.0, 0.0, {"open_time": 3.6})
	var gw2: GapWall = kit.gap_wall(_w(Vector3(0, y, z0 - 17.0)), _yaw, 3.4, 9.0, 0.5, {"open_time": 3.6})
	var lz: float = z0 - 25.0
	var l1: LaserGate = kit.laser(_w(Vector3(0, y + 1.2, lz)), Vector3(7.0, 2.4, 0.2), 5.0, 0.3, 0.0, _yaw)
	var l2: LaserGate = kit.laser(_w(Vector3(0, y + 1.2, lz - 3.5)), Vector3(7.0, 2.4, 0.2), 5.0, 0.3, fposmod(-0.07, 1.0), _yaw)
	# SHORTCUT: a catwalk outside the laser posts
	_blk(Vector3(5.6, y, lz - 1.5), 1.6, 12.0, "accent", 0.6)
	var pb: Dictionary = _post(_ahead(deck, 0.76, 0.0, 2.0), 2.0, 2.0)
	var cp: Dictionary = _cp(_ahead(pb, 0.76, 0.0, 5.0, -(pb["c"] as Vector3).x))
	_hop(cp0, deck, Vector3(0, 0, 15.0))
	r_walk(_w(Vector3(0, y, z0 - 2.5)))
	_wait(func() -> bool: return gw1.is_open_for(Game.course_time, 0.8 + 1.5), _w(Vector3(0, y, z0 - 2.5)))
	r_walk(_w(Vector3(0, y, z0 - 11.0)))
	_wait(func() -> bool: return gw2.is_open_for(Game.course_time, 0.8 + 1.5), _w(Vector3(0, y, z0 - 11.0)))
	r_walk(_w(Vector3(0, y, lz + 2.5)))
	if route_variant == 2:
		r_walk(_w(Vector3(3.0, y, lz + 2.3)))
		r_jump(_w(Vector3(3.1, y, lz + 2.3)), _w(Vector3(5.6, y, lz + 2.3)))
		r_walk(_w(Vector3(5.6, y, lz - 6.0)))
		r_jump(_w(Vector3(5.6, y, lz - 6.5)), _w(Vector3(2.4, y, lz - 6.5)))
	else:
		_wait(func() -> bool: return _dark(l1, 0.0, 0.5 + 1.5) and _dark(l2, 0.3, 1.1 + 1.5), _w(Vector3(0, y, lz + 2.5)))
		r_walk(_w(Vector3(0, y, lz - 5.0)))
	r_walk(_w(Vector3(0, y, dc.z - 15.8)))
	_hop(deck, pb)
	_hop(pb, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the funhouse front: a laughing painted face over the doors, mirror shards on the beam posts
	for g: LaserGate in [l1, l2]:
		for sx: float in [-1.0, 1.0]:
			var m := Look.box(Vector3(0.5, 0.9, 0.05), Look.flat(Color(0.85, 0.9, 1.0), 0.05, 1.0), Vector3(sx * (g.size.x * 0.5 + 0.18), g.size.y * 0.5 + 0.9, 0))
			m.rotation = Vector3(0.0, sx * 0.6, 0.15)
			g.add_child(m)
	deco.string_lights(_w(Vector3(-4.5, y + 6.5, z0 - 2.0)), _w(Vector3(4.5, y + 6.5, z0 - 2.0)), 1.0, 0.7)
	deco.string_lights(_w(Vector3(-4.5, y + 6.5, z0 - 14.0)), _w(Vector3(4.5, y + 6.5, z0 - 14.0)), 1.0, 0.7)
	return cp["c"]


# ---- stage 11: Hall of Mirrors - BRANCH: the funhouse door | the mantle route [shortcut: the mirror wall run] ------

## A funhouse door frame around a warp ring (`floor_pos` / yaw as given to kit.portal, world).
func _door_frame(floor_pos: Vector3, yaw_deg: float, col: Color) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), floor_pos)
	add_child(n)
	var stripe: ShaderMaterial = CarnivalDecor.stripe_mat(col, CREAM, 8.0)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.3, 3.4, 0.4), stripe, Vector3(sx * 1.8, 1.7, 0)))
	n.add_child(Look.box(Vector3(4.1, 0.34, 0.44), stripe, Vector3(0, 3.5, 0)))
	n.add_child(Look.sphere(0.24, Look.flat(GOLD, 0.3, 0.0, 2.6), Vector3(0, 3.95, 0)))


func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.76, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	var y: float = fc.y
	# LEFT: the door whisks you to the exit deck E, then two posts and the merge
	var e: Dictionary = _blk(Vector3(-3.5, y, f0 - 14.0), 5.0, 5.0)
	var door: WarpPortal = kit.portal(_w(Vector3(-3.5, y, fc.z - 0.6)), _yaw, _w(Vector3(-3.5, y, f0 - 12.8)), _yaw, 7.0)
	_door_frame(_w(Vector3(-3.5, y, fc.z - 0.6)), _yaw, RED)
	_door_frame(_w(Vector3(-3.5, y, f0 - 12.8)), _yaw, TEAL)
	var p1: Dictionary = _post(_ahead(e, 0.76, 0.0, 2.0, 0.4), 2.0, 2.0)
	var p2: Dictionary = _post(_ahead(p1, 0.78, 0.0, 2.0, -0.4), 2.0, 2.0)
	var merge: Dictionary = _blk(_ahead(p2, 0.78, 0.0, 3.0, -(p2["c"] as Vector3).x), 11.0, 3.0)
	var mc: Vector3 = merge["c"]
	var mfront: float = mc.z + 1.5
	# RIGHT: the mantle route - a 3.3 m crate, posts along its top, then the long drop to the merge
	var crate_top := Vector3(3.5, y + 3.3, f0 - 1.6 - 3.0)
	var crate: Dictionary = _ledge(crate_top, Vector3(2.8, 9.0, 6.0))
	var q: Dictionary = crate
	var qs: Array[Dictionary] = []
	while (q["c"] as Vector3).z - float(q["hz"]) - mfront > 8.4:
		q = _post(_ahead(q, 0.75, 0.0, 2.0, 0.4 if qs.size() % 2 == 0 else -0.4), 2.0, 2.0)
		qs.append(q)
	# SHORTCUT: the mirror wall run from a post on the fork's lip, landing near the merge
	var w: Dictionary = _post(_ahead(_area(fc, 5.5, 1.5), 0.76, 0.0, 1.8, 0.0), 1.8, 1.8)
	var wl: Dictionary = _wall_geometry(w)
	var cp: Dictionary = _cp(_ahead(merge, 0.76, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 1:
		r_walk(_w(Vector3(3.5, y, fc.z + 0.3)))
		r_mantle(_w(Vector3(3.5, y, f0 + 0.35)), _w(crate_top + Vector3(0, 0, 0.2)))
		var prev: Dictionary = crate
		for qq: Dictionary in qs:
			_hop(prev, qq)
			prev = qq
		_hop(prev, merge, Vector3(0, 0, 0.6))
	elif route_variant == 2:
		r_walk(_w(Vector3(0, y, fc.z)))
		_hop(_area(fc, 5.5, 1.5), w)
		_wall_route(w)
		_hop(wl, merge, Vector3(0, 0, 0.6))
	else:
		r_walk(_w(Vector3(-3.5, y, fc.z + 0.6)))
		r_portal(_w(Vector3(-3.5, y, fc.z - 0.9)), door.exit_point())
		r_walk(_w(Vector3(-3.5, y, f0 - 14.5)))
		_hop(e, p1)
		_hop(p1, p2)
		_hop(p2, merge, Vector3(-3.5, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# mirrors along both sides, tall distorting panels in funhouse colours
	for k: int in 4:
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.8, 0.88, 1.0)
		glass.metallic = 1.0
		glass.roughness = 0.06
		var mir := Look.box(_sz(Vector3(0.2, 7.0, 3.2)), glass, _w(Vector3(-9.5, y + 1.0, f0 - 6.0 - 8.0 * float(k))))
		mir.rotation.y = deg_to_rad(_yaw) + 0.25
		add_child(mir)
	deco.arrow_sign(_w(Vector3(-4.2, y, fc.z + 0.2)), deg_to_rad(_yaw), -1.0, RED)
	deco.arrow_sign(_w(Vector3(4.2, y, fc.z + 0.2)), deg_to_rad(_yaw), 1.0, GOLD)
	return cp["c"]


# ---- stage 12: Drop Tower - falling blocks, the dropping weight, a wall run onto the tower ----------------------------

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var deck: Dictionary = _blk(_ahead(cp0, 0.74, 0.0, 22.0), 6.4, 22.0)
	var dc: Vector3 = deck["c"]
	var y: float = dc.y
	var z0: float = dc.z + 11.0
	var b1: FallingBlock = kit.falling_block(_w(Vector3(0, y, z0 - 5.0)), _sz(Vector3(6.4, 1.6, 3.0)), 7.0, 6.0, 0.0)
	var b2: FallingBlock = kit.falling_block(_w(Vector3(0, y, z0 - 14.0)), _sz(Vector3(6.4, 1.6, 3.0)), 7.0, 6.0, 0.5)
	_blk(Vector3(5.4, y, z0 - 11.0), 1.6, 18.0, "accent", 0.6)
	var beam: Dictionary = _blk(_ahead(deck, 0.76, 0.0, 10.0), 1.8, 10.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var press: Crusher = kit.crusher(_w(Vector3(bc.x, bc.y, bc.z)), Vector3(2.4, 1.2, 2.0), 3.2, 6.0, 0.0, _yaw)
	var w2: Dictionary = _post(_ahead(beam, 0.76, 0.0, 1.8), 1.8, 1.8)
	var land: Dictionary = _wall_geometry(w2)
	var cp: Dictionary = _cp(_ahead(land, 0.76, 0.0, 5.0, -(land["c"] as Vector3).x))
	_hop(cp0, deck, Vector3(0, 0, 9.0))
	if route_variant == 2:
		# SHORTCUT: step out onto the catwalk beside the deck and walk past both blocks
		r_walk(_w(Vector3(3.0, y, z0 - 2.0)))
		r_jump(_w(Vector3(3.0, y, z0 - 2.0)), _w(Vector3(5.4, y, z0 - 2.0)))
		r_walk(_w(Vector3(5.4, y, z0 - 19.0)))
		r_jump(_w(Vector3(5.4, y, z0 - 19.3)), _w(Vector3(2.4, y, z0 - 19.3)))
	else:
		r_walk(_w(Vector3(0, y, z0 - 1.5)))
		_wait(func() -> bool: return b1.is_clear_for(Game.course_time, 0.9 + 1.5), _w(Vector3(0, y, z0 - 1.5)))
		r_walk(_w(Vector3(0, y, z0 - 10.0)))
		_wait(func() -> bool: return b2.is_clear_for(Game.course_time, 0.9 + 1.5), _w(Vector3(0, y, z0 - 10.0)))
	r_walk(_w(Vector3(0, y, dc.z - 10.0)))
	var tp: float = 1.4
	_wait(func() -> bool: return _press_ok(press, tp - 0.3, tp + 0.8 + 1.5), _w(Vector3(0, y, dc.z - 10.0)))
	_hop(deck, beam, Vector3(0, 0, 4.5))
	r_walk(_w(Vector3(bc.x, bc.y, bc.z - 4.8)))
	_hop(beam, w2)
	_wall_route(w2)
	_hop(land, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the drop tower: a tall striped tower with a cage, and the strongman's weights
	_high_striker(Vector3(-9.5, y - 6.0, dc.z - 2.0))
	_high_striker(Vector3(9.5, y - 6.0, dc.z + 6.0))
	deco.balloons(_w(Vector3(8.0, y - 4.0, dc.z - 8.0)), 6, 6.0)
	return cp["c"]


# ---- stage 13: Barrel Rollers - the rolling logs, a pair of moles between them -------------------------------------

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var deck: Dictionary = _blk(_ahead(cp0, 0.76, 0.0, 6.0), 7.0, 6.0)
	var dc: Vector3 = deck["c"]
	var y: float = dc.y
	var f: float = dc.z - 3.0
	var log_len: float = 12.0
	kit.log_roller(_w(Vector3(0, y, f - 0.4 - log_len * 0.5)), log_len, 2.6, _yaw + 90.0, 3.0, 6.0, 0.0)
	var isl: Dictionary = _blk(Vector3(0, y, f - 0.4 - log_len - 0.4 - 1.8), 6.0, 3.6, "alt", 0.8)
	var period: float = 7.4
	var c1: Vector3 = _ahead(isl, 0.74, 0.0, 1.9, 0.5)
	var mo1: CarnivalMole = _mole(c1, period, 0.0)
	var a1: Dictionary = _area(c1, 0.95, 0.95)
	var c2: Vector3 = _ahead(a1, 0.74, 0.0, 1.9, -0.5)
	var mo2: CarnivalMole = _mole(c2, period, fposmod(-0.6 / period, 1.0))
	var a2: Dictionary = _area(c2, 0.95, 0.95)
	var isl2: Dictionary = _blk(_ahead(a2, 0.74, 0.0, 3.6, -c2.x), 6.0, 3.6, "alt", 0.8)
	var ic2: Vector3 = isl2["c"]
	var f2: float = ic2.z - 1.8
	kit.log_roller(_w(Vector3(0, y, f2 - 0.4 - log_len * 0.5)), log_len, 2.6, _yaw + 90.0, 3.0, 6.0, 0.5)
	var cp: Dictionary = _cp(Vector3(0, y, f2 - 0.4 - log_len - 0.4 - 2.5))
	_hop(cp0, deck, Vector3(0, 0, 1.0))
	r_walk(_w(Vector3(0, y, f + 0.8)))
	r_walk(_w(Vector3(0, y, f - 1.6)))
	r_walk(_w(Vector3(0, y, f - 0.4 - log_len + 0.8)))
	r_walk(_w(Vector3(0, y, (isl["c"] as Vector3).z)))
	_wait(func() -> bool: return _moles_ok([[mo1, 0.8, 2.0 + 1.5], [mo2, 1.65, 2.85 + 1.5]]), _w(Vector3(0, y, (isl["c"] as Vector3).z)))
	_hop(isl, a1)
	_hop(a1, a2)
	_hop(a2, isl2)
	r_walk(_w(Vector3(0, y, f2 - 1.6)))
	r_walk(_w(Vector3(0, y, f2 - 0.4 - log_len + 0.8)))
	r_walk(_w(Vector3(0, y, f2 - 0.4 - log_len - 0.4 - 2.0)))
	r_checkpoint()
	for k: int in 5:
		var bz: float = f - 3.0 - 6.0 * float(k)
		add_child(Look.cylinder(0.8, 1.3, Look.flat(Color(0.55, 0.32, 0.18), 0.8), _w(Vector3(-7.0, y - 3.0, bz)), 0.7, 14))
		add_child(Look.cylinder(0.82, 0.1, Look.flat(GOLD, 0.3, 0.8), _w(Vector3(-7.0, y - 2.5, bz)), -1.0, 14))
	deco.bunting(_w(Vector3(-5.0, y + 5.0, f - 2.0)), _w(Vector3(5.0, y + 5.0, f - 14.0)), 1.2, 14)
	deco.bunting(_w(Vector3(5.0, y + 5.0, f2 - 2.0)), _w(Vector3(-5.0, y + 5.0, f2 - 14.0)), 1.2, 14)
	return cp["c"]


# ---- stage 14: The Big Dipper - the long coaster up the hill [shortcut: the post line beside the rails] --------------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var za: float = -2.5 - 0.9 - 2.0
	var car := CarnivalCoaster.new()
	car.size = Vector3(3.0, 0.5, 4.0)
	car.tint = Color(0.2, 0.6, 0.95)
	car.points = [Vector3.ZERO, Vector3(0, 2.5, -6.0), Vector3(0, 7.5, -13.0), Vector3(0, 6.0, -20.0), Vector3(0, 4.0, -30.0)]
	car.dock = 4.5
	car.travel = 5.5
	car.dock_b = 2.2
	car.back = 2.2
	car.position = _w(Vector3(0, 0, za)) - Vector3(0, 0.25, 0)
	car.rotation.y = deg_to_rad(_yaw)
	add_child(car)
	var merge: Dictionary = _blk(Vector3(0, 4.0, za - 30.0 - 2.0 - 0.9 - 2.5), 8.0, 5.0)
	var mfront: float = (merge["c"] as Vector3).z + 2.5
	# SHORTCUT: a line of posts climbing beside the rails
	var posts: Array[Dictionary] = []
	var q: Dictionary = cp0
	while (q["c"] as Vector3).z - float(q["hz"]) - mfront > 7.6 and posts.size() < 6:
		q = _post(_ahead(q, 0.86, 1.0 if (q["c"] as Vector3).y < 3.5 else 0.0, 2.0, 4.0 - (q["c"] as Vector3).x), 2.0, 2.0)
		posts.append(q)
	var cp: Dictionary = _cp(_ahead(merge, 0.76, 0.0, 5.0))
	if route_variant == 2:
		var prev: Dictionary = cp0
		for pp: Dictionary in posts:
			_hop(prev, pp)
			prev = pp
		_hop(prev, merge, Vector3(-4.0, 0, 0.6))
	else:
		var stand: Vector3 = _w(Vector3(0, 0, 0.4))
		r_walk(stand)
		_wait(func() -> bool: return car.docked_for(Game.course_time, 0, 3.0), stand)
		route.append({"kind": "x_jump", "from": _w(Vector3(0, 0, -2.0)), "to_node": car, "to_local": Vector3(0, 0.3, 0.2), "hold": true})
		route.append({"kind": "candy_ride", "stand": Vector3(0, 0.3, 0.2), "to": _w(Vector3(0, 4.0, (merge["c"] as Vector3).z + 0.2)),
			"until": func() -> bool: return car.dock_at(Game.course_time) == 1})
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	deco.far_coaster(_w(Vector3(-24.0, -14.0, 6.0)), deg_to_rad(_yaw) + 0.2, 90.0, 14.0)
	deco.arrow_sign(_w(Vector3(-2.2, 0, 1.6)), deg_to_rad(_yaw), 0.0, RED)
	deco.balloons(_w(Vector3(7.5, 2.0, -12.0)), 6, 6.0)
	return cp["c"]


# ---- stage 15: Twin Carousels - two turning decks, turning opposite ways ------------------------------------------------

## Ride a carousel: from the edge of `from_a` onto the turning deck (hub is the local floor point of its centre) and
## off again toward `exit_a` as it comes round. Returns the carousel.
func _carousel(from_a: Dictionary, hub: Vector3, radius: float, period: float, exit_a: Dictionary) -> CarnivalCarousel:
	var car := CarnivalCarousel.new()
	car.radius = radius
	car.period = period
	car.position = _w(hub) - Vector3(0, 0.25, 0)
	add_child(car)
	_floors.append({"top": _w(hub), "size": Vector3(radius * 2.0, 0, radius * 2.0), "drop": 0.5, "frag": true, "stage": _stage_no})
	var locals: Array = []
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0
		locals.append(Vector3(cos(a) * (radius - 0.9), 0.25, sin(a) * (radius - 0.9)))
	var stand: Vector3 = _w(_edge(from_a, hub))
	r_walk(stand)
	route.append({"kind": "x_jump", "from": stand, "to_node": car, "to_locals": locals, "reach": 3.8, "lead": 0.55})
	var hw: Vector3 = _w(hub)
	var target: Vector3 = _w(exit_a["c"])
	var ex: Vector3 = Vector3(target.x - hw.x, 0, target.z - hw.z).normalized()
	var sgn: float = signf(period)
	var lead_deg: float = rad_to_deg(TAU / absf(period)) * 0.6
	route.append({"kind": "h_jump", "to": target, "test": func() -> bool:
		var rel: Vector3 = player.global_position - hw
		rel = Vector3(rel.x, 0, rel.z).normalized()
		var a2: float = rad_to_deg(atan2(rel.cross(ex).y, rel.dot(ex))) * sgn
		return a2 >= lead_deg - 7.0 and a2 <= lead_deg + 7.0})
	return car


func _stage_15() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.70, 0.0, 2.0), 2.0, 2.0)
	var r1: float = 4.2
	var hub1 := Vector3(0, 0, (p1["c"] as Vector3).z - 1.0 - 2.0 - r1)
	var isl: Dictionary = _post(Vector3(0, 0, hub1.z - r1 - 4.0 - 1.5), 3.0, 3.0)
	var r2: float = 5.0
	var hub2 := Vector3(0, 1.0, (isl["c"] as Vector3).z - 1.5 - 2.0 - r2)
	var m2: Dictionary = _post(Vector3(0, 1.5, hub2.z - r2 - 4.0 - 1.0), 2.0, 2.0)
	var p3: Dictionary = _post(_ahead(m2, 0.76, 0.0, 2.0, 0.4), 2.0, 2.0)
	var cp: Dictionary = _cp(_ahead(p3, 0.76, 0.0, 5.0, -0.4))
	_hop(cp0, p1)
	_carousel(p1, hub1, r1, 13.0, isl)
	_carousel(isl, hub2, r2, -12.0, m2)
	_hop(m2, p3)
	_hop(p3, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	deco.tent(_w(Vector3(-15.0, -6.0, hub1.z)), 6.0, 4.0, 5.0, 0.4, TEAL, CREAM)
	deco.tent(_w(Vector3(15.0, -6.0, hub2.z)), 6.0, 4.0, 5.0, -0.3, PINK, CREAM)
	deco.balloons(_w(Vector3(-8.0, -2.0, hub2.z + 4.0)), 6, 5.0)
	return cp["c"]


# ---- stage 16: Midnight Wheel - the great wheel, up to the big top's roof ---------------------------------------------------------

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var lp: Dictionary = _blk(_ahead(cp0, 0.74, 0.0, 6.0), 5.0, 6.0)
	var zc: float = (lp["c"] as Vector3).z
	var radius: float = 9.0
	var yc: float = radius
	var xw: float = -5.0
	var wheel := CarnivalWheel.new()
	wheel.radius = radius
	wheel.period = 26.0
	wheel.count = 8
	wheel.tint = Color(0.35, 0.3, 0.85)
	wheel.position = _w(Vector3(xw, yc, zc))
	wheel.rotation.y = deg_to_rad(_yaw)
	add_child(wheel)
	var ed_y: float = yc + 0.94 * radius - 0.2
	_blk(Vector3(0, ed_y, zc - 3.1), 5.0, 6.0)
	var ed_front: float = zc - 3.1 - 3.0
	var ledge_top := Vector3(0, ed_y + 3.3, ed_front - 1.6 - 0.7)
	var ledge: Dictionary = _ledge(ledge_top, Vector3(2.8, 9.0, 1.4))
	var cp: Dictionary = _cp(_ahead(ledge, 0.76, 0.0, 5.0))
	var centre: Vector3 = _w(Vector3(xw, yc, zc))
	_hop(cp0, lp)
	var stand: Vector3 = _w(Vector3(-2.15, 0, zc))
	r_walk(stand)
	route.append({"kind": "carnival_board", "from": stand, "cars": wheel.gondolas, "fwd": _b * Vector3(0, 0, -1), "lead": 0.5, "local": Vector3(0, 0.3, 0)})
	route.append({"kind": "candy_ride", "stand": Vector3(0, 0.3, 0), "to": _w(Vector3(-0.5, ed_y, zc - 3.1)),
		"until": func() -> bool:
			var fb: Object = player.floor_body
			if not (fb is CarnivalWheel.Gondola):
				return false
			return (fb as Node3D).global_position.y + 0.25 - centre.y >= 0.9 * radius - 0.6})
	r_walk(_w(Vector3(0, ed_y, ed_front + 0.9)))
	r_mantle(_w(Vector3(0, ed_y, ed_front + 0.35)), _w(ledge_top + Vector3(0, 0, 0.2)))
	_hop(ledge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	deco.big_top(_w(Vector3(-30.0, -20.0, zc - 40.0)), 1.4, 0.3)
	deco.balloons(_w(Vector3(-12.0, 4.0, zc + 3.0)), 6, 6.0)
	return cp["c"]


# ---- stage 17: Big Top Climb - mantle the canvas, run its wall, mallets across the ridge -----------------------------------

func _stage_17() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var ledge_top := Vector3(0, 3.3, -2.5 - 1.6 - 1.5)
	var la: Dictionary = _ledge(ledge_top, Vector3(2.8, 9.0, 3.0))
	var p1: Dictionary = _post(_ahead(la, 0.76, 0.0, 2.0, 0.4), 2.0, 2.0)
	var w2: Dictionary = _post(_ahead(p1, 0.78, 0.0, 1.8, -0.4), 1.8, 1.8)
	var land: Dictionary = _wall_geometry(w2)
	var beam: Dictionary = _blk(_ahead(land, 0.76, 0.0, 10.0, -(land["c"] as Vector3).x), 1.6, 10.0, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var m1: Piston = _mallet(Vector3(bc.x - 1.55, bc.y + 1.35, bc.z + 2.5), 1.0, 2.6, 6.5, 0.0)
	var m2: Piston = _mallet(Vector3(bc.x - 1.55, bc.y + 1.35, bc.z - 2.5), 1.0, 2.6, 6.5, fposmod(-0.05, 1.0))
	var q: Dictionary = _post(_ahead(beam, 0.76, 0.0, 2.0), 2.0, 2.0)
	var qc: Vector3 = q["c"]
	var top2 := Vector3(qc.x, qc.y + 3.3, qc.z - 1.0 - 1.6 - 1.5)
	var lb: Dictionary = _ledge(top2, Vector3(2.8, 9.0, 3.0))
	var cp: Dictionary = _cp(_ahead(lb, 0.76, 0.0, 5.0, -qc.x))
	r_walk(_w(Vector3(0, 0, -1.6)))
	r_mantle(_w(Vector3(0, 0, -2.15)), _w(ledge_top + Vector3(0, 0, 1.0)))
	_hop(la, p1)
	_hop(p1, w2)
	_wall_route(w2)
	_hop(land, beam, Vector3(0, 0, 4.5))
	r_walk(_w(Vector3(bc.x, bc.y, bc.z + 4.7)))
	_wait(func() -> bool: return _ram_clear(m1, 0.2, 1.1 + 1.5) and _ram_clear(m2, 0.7, 1.7 + 1.5), _w(Vector3(bc.x, bc.y, bc.z + 4.7)))
	r_walk(_w(Vector3(bc.x, bc.y, bc.z - 5.2)))
	_hop(beam, q)
	r_walk(_w(Vector3(qc.x, qc.y, qc.z - 0.3)))
	r_mantle(_w(Vector3(qc.x, qc.y, qc.z - 0.65)), _w(top2 + Vector3(0, 0, 1.0)))
	_hop(lb, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	deco.big_top(_w(Vector3(-4.0, -30.0, -30.0)), 1.0, 0.2)
	deco.string_lights(_w(Vector3(-6.0, 9.0, -4.0)), _w(Vector3(6.0, 9.0, -30.0)), 1.6, 0.8)
	return cp["c"]


# ---- stage 18: THE HUMAN CANNONBALL (set piece) - fire out of the great cannon to the big top ------------------------------

func _stage_18() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var pad: Dictionary = _blk(Vector3(0, 0, -9.0), 7.0, 7.0, "main", 1.2)
	var shot: float = 18.0
	var target_c := Vector3(0, 4.0, -9.0 - shot)
	var cannon := CarnivalCannon.new()
	cannon.target = _w(target_c)
	cannon.arc = 7.0
	cannon.period = 3.0
	cannon.phase = 0.0
	cannon.tell = 1.6
	cannon.mouth = 1.2
	cannon.position = _w(Vector3(0, 0, -9.0)) + Vector3(0, 1.15, 0)
	add_child(cannon)
	# the landing: the ring of the big top, a wide stage
	_blk(target_c, 14.0, 12.0, "main", 1.4)
	kit.finish(_w(target_c + Vector3(0, 0, -2.5)), _yaw)
	_finish_pos = _w(target_c + Vector3(0, 0, -2.5))
	_hop(cp0, pad, Vector3(0, 0, 2.3))
	r_barrel(cannon, _w(target_c))
	r_walk(_w(target_c + Vector3(0, 0, -2.5)))
	# the big top rising behind the finish, with a ring of lights, spotlights and the crowd's balloons
	deco.big_top(_w(target_c + Vector3(0, -7.0, -26.0)), 1.1, deg_to_rad(_yaw) + 0.1)
	deco.pole(_w(target_c + Vector3(-7.5, -1.4, 4.5)), 9.0, RED)
	deco.pole(_w(target_c + Vector3(7.5, -1.4, 4.5)), 9.0, TEAL)
	deco.string_lights(_w(target_c + Vector3(-7.5, 7.6, 4.5)), _w(target_c + Vector3(7.5, 7.6, 4.5)), 1.6, 0.7)
	deco.string_lights(_w(Vector3(-3.4, 5.0, -9.0)), _w(target_c + Vector3(-7.5, 7.6, 4.5)), 4.0, 0.9, true)
	deco.string_lights(_w(Vector3(3.4, 5.0, -9.0)), _w(target_c + Vector3(7.5, 7.6, 4.5)), 4.0, 0.9, true)
	deco.balloons(_w(target_c + Vector3(-9.0, -1.4, 0.0)), 7, 6.0)
	deco.balloons(_w(target_c + Vector3(9.0, -1.4, -3.0)), 7, 6.0)
	deco.searchlights(_w(target_c + Vector3(-14.0, -12.0, -10.0)), 2)
	deco.searchlights(_w(target_c + Vector3(14.0, -12.0, -10.0)), 2)
	_finish_light = OmniLight3D.new()
	_finish_light.light_color = GOLD
	_finish_light.light_energy = 2.0
	_finish_light.omni_range = 16.0
	_finish_light.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(_finish_light)


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
	_env.sky = CarnivalSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.72, 0.5, 0.64)
	_env.ambient_light_energy = 0.95
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.08
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.95, 0.46, 0.44)
	_env.fog_density = 0.0016
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.2
	_env.fog_sun_scatter = 0.12
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.15
	_env.adjustment_contrast = 1.06
	# a low, golden-orange sun from ahead-left, and a cool violet fill from the other side
	_sun.light_color = Color(1.0, 0.68, 0.42)
	_sun.light_energy = 1.25
	_sun.rotation_degrees = Vector3(-19, 150, 0)
	_fill.light_color = Color(0.55, 0.45, 0.95)
	_fill.light_energy = 0.35
	_fill.rotation_degrees = Vector3(35, -30, 0)


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
	# stilts: a striped pole under every small deck, a pair under a big one - down into the dusk haze
	var pole_mat: ShaderMaterial = CarnivalDecor.stripe_mat(RED, CREAM, 6.0)
	for f: Dictionary in _floors:
		if f.has("frag"):
			continue
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		var under: Vector3 = t - Vector3(0, float(f["drop"]), 0)
		var len: float = 26.0
		var big: bool = minf(s.x, s.z) >= 3.4
		var offs: Array[Vector3] = [Vector3.ZERO]
		if big:
			var ox: float = s.x * 0.5 - 0.9
			var oz: float = s.z * 0.5 - 0.9
			offs = [Vector3(-ox, 0, -oz), Vector3(ox, 0, oz)]
		for o: Vector3 in offs:
			var c: Vector3 = under + o - Vector3(0, len * 0.5, 0)
			if _box_free(c, Vector3(0.4, len * 0.5, 0.4), f):
				add_child(Look.cylinder(0.24 if not big else 0.34, len, pole_mat, c, -1.0, 8))
	# the fairground far below
	deco.ground(Vector3(mid.x, lo.y - 70.0, mid.z), 2600.0)
	# far scenery round the course, clear of the route
	var placed: int = 0
	var tries: int = 0
	while placed < 30 and tries < 700:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 130.0, hi.x + 130.0), rng.randf_range(lo.y - 70.0, lo.y - 30.0), rng.randf_range(lo.z - 130.0, hi.z + 130.0))
		if not _clear_of(p, pts, 40.0):
			continue
		var roll: float = rng.randf()
		var yaw: float = rng.randf() * TAU
		if roll < 0.55:
			var col_a: Color = [RED, TEAL, GOLD, PINK][rng.randi() % 4]
			deco.tent(p, rng.randf_range(5.0, 9.0), rng.randf_range(3.0, 5.0), rng.randf_range(4.0, 8.0), yaw, col_a, CREAM)
		elif roll < 0.75:
			deco.kiosk(p, yaw, [RED, TEAL, PINK][rng.randi() % 3])
		elif roll < 0.9:
			deco.balloons(p, 6, rng.randf_range(10.0, 22.0))
		else:
			deco.pole(p, rng.randf_range(16.0, 28.0), RED)
		placed += 1
	# the skyline of rides: a giant wheel, a coaster skeleton and the big top, far off
	var far: float = maxf(span.x, span.z) * 0.5 + 170.0
	deco.far_wheel(Vector3(mid.x + far, lo.y + 30.0, mid.z - 40.0), 52.0, 0.0)
	deco.far_wheel(Vector3(mid.x - far * 0.9, lo.y + 24.0, mid.z + 60.0), 38.0, PI)
	deco.far_coaster(Vector3(mid.x - 80.0, lo.y - 40.0, mid.z + far), 0.5, 180.0, 20.0)
	deco.far_coaster(Vector3(mid.x + 120.0, lo.y - 40.0, mid.z - far), 3.4, 160.0, 24.0)
	deco.searchlights(Vector3(mid.x + far * 0.5, lo.y - 60.0, mid.z - far * 0.9), 3)
	# fireworks bursting over the fairground
	var cols: Array[Color] = [Color(1.0, 0.45, 0.55), Color(1.0, 0.85, 0.3), Color(0.4, 0.8, 1.0), Color(0.6, 1.0, 0.6), Color(1.0, 0.5, 1.0)]
	for i: int in 7:
		var a: float = TAU * float(i) / 7.0 + 0.4
		var r: float = maxf(span.x, span.z) * 0.5 + rng.randf_range(90.0, 200.0)
		CarnivalFx.firework(self, Vector3(mid.x + cos(a) * r, hi.y + rng.randf_range(10.0, 50.0), mid.z + sin(a) * r), cols[i % cols.size()], rng.randf_range(3.2, 5.0), rng.randf_range(0.0, 4.0))
	# ambient life along the route: confetti drifting down, warm glints rising
	for i2: int in _cp_world.size():
		var here: Vector3 = _cp_world[i2]
		var prev: Vector3 = _cp_world[i2 - 1] if i2 > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 5.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 9.0, absf(here.z - prev.z) * 0.5 + 12.0)
		CarnivalFx.confetti_drift(self, c3 + Vector3(0, 4.0, 0), ext, 60)
		CarnivalFx.glints(self, c3 - Vector3(0, 2.0, 0), ext * Vector3(0.8, 0.9, 0.8), 36)


## Swap every walkable surface to the boardwalk shader (same colours and sizes).
func _carnival_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = preload("res://visual/carnival_tile.gdshader")
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


# ---- live effects -----------------------------------------------------------------------------------

## The big top lights up: a fountain of fireworks and confetti over the finish.
func _finish_sequence() -> void:
	var cols: Array[Color] = [PINK, GOLD, TEAL, RED, CREAM]
	for i: int in cols.size():
		var fw: GPUParticles3D = CarnivalFx.finale(cols[i], 80)
		fw.position = _finish_pos + Vector3(-6.0 + 3.0 * float(i), 1.0 + float(i % 2) * 2.0, -2.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	var fx: Array[GPUParticles3D] = CarnivalFx.cp_burst(GOLD)
	for p2: GPUParticles3D in fx:
		p2.position = _finish_pos + Vector3(0, 0.6, 0)
		add_child(p2)
		p2.restart()
		p2.emitting = true
	# SOUND: carnival_finish - a full brass-band flourish and a barrage of rockets
	WorldAudio.at(self, "carnival_finish", _finish_pos + Vector3(0, 3.0, 0), 1.0, 120.0)
	if _finish_light != null:
		_finish_light.light_energy = 9.0
		var tw: Tween = create_tween()
		tw.tween_property(_finish_light, "light_energy", 2.0, 1.6)
	await get_tree().create_timer(0.9).timeout
