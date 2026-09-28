extends LevelBase
## 14. SUPER CARRIER - an enormous jump course through a supercarrier steaming across open ocean on a
## bright day, finishing at the very top of the island's mast. Eighteen stages, each ending on a
## checkpoint: in over the fantail at the stern, forward through the three hangar bays (the fire-
## suppression foam is flooding the hangar deck: touch it and you are out), out through the hangar door
## onto the deck-edge elevator and up the hull, across the bow while the catapults launch jets, aft
## through the torn-up forward flight deck (it is off for refit: the girders are no floor) and over the
## arresting wires, then up the island - its ladders, the antenna screen, the turning radar, the mast.
##
##  1 Fantail          the stern porch over the wake; crates in the foam, MANTLE the crate stack
##  2 The Flood        ride a tow tug out over the foam, the tyre-stack pad, the catwalk, a second tug
##                     [shortcut: a 90% leap to the maintenance hatch (PORTAL), out at the catwalk's end]
##  3 Steam Line       BRANCH: the catwalk under the burst steam line - steam jets (LASERS) and hydraulic
##                     rams (PISTONS) | MANTLE the pipe rack and WALL RUN the hull plating over the foam
##  4 Fire Door        through the divisional fire door between closings, under the weapons lift (CRUSHER),
##                     MANTLE onto the landing
##  5 Crane Run        ride the bridge crane's hanging pallet across the bay, a crumbling pallet
##                     [shortcut: two hook blocks beside the crane's run - 1 m landings, no waiting]
##  6 Tug Lanes        hop between towed pallets crossing their lanes, past the swinging cargo hooks
##  7 Helo Bay         ride a heavy-lift helicopter's turning rotor across the bay, a tyre pad up
##  8 Launch Engine    stand on the test catapult's shuttle and get flung across the bay, a steam jet (LASER)
##  9 Elevator One     out through the hangar door onto the deck-edge elevator and up the hull to the deck
## 10 Cat Two          THE LAUNCH, part 1: once the port catapult fires, run down its lane (the shuttle
##                     track's boost, gaps in the deck) and get off it before the next jet comes
## 11 Cat One          THE LAUNCH, part 2: back up the starboard lane toward the next jet rising on its
##                     lift as its blast deflector goes up - off the lane before it fires
## 12 Blast Alley      BRANCH: dash between the parked jets' engine run-ups on the deck strip | drop to the
##                     gallery catwalk under the deck edge, WALL RUN the hull, MANTLE back up
## 13 Deck Park        a tractor's ram (PISTON) across the girder, ride a towed dolly, under the hook block
##                     (CRUSHER)
## 14 The Wires        bounce across the arresting-gear pit on the taut cross-deck pendants
## 15 Island Base      MANTLE up the island's ladders, the gallery past the antenna rams (PISTONS), under
##                     the hatch cover (CRUSHER) [shortcut: a 90% leap to a watertight door (PORTAL)]
## 16 Antenna Screen   BRANCH: a chimney of three WALL RUNS between the island and the screen | three
##                     MANTLES up the screen's sea side
## 17 Radar Deck       ride the big turning radar round the island's face, up onto the bridge roof
##                     [shortcut: WALL RUN the status board past the radar]
## 18 The Mast         hop the sweeping radar, MANTLE up pri-fly, hop round the yardarms, MANTLE onto the
##                     masthead: the finish, where three jets roar past trailing smoke
##
## Carrier mechanics (own scripts): CarrierCatapult (a steam catapult you ride), CarrierBlast (jet
## engine run-ups that shove you), CarrierWire (arresting wires that bounce), CarrierElevator (the
## deck-edge aircraft elevator), CarrierFireDoor (the hangar's divisional doors), and the set piece
## CarrierLaunch (jets launched off the bow on the course clock: lift, blast deflector, spool, shot).
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every
## shortcut.

const FOAM_Y: float = -17.0
const HANGAR_FLOOR: float = -17.8
const CEIL_Y: float = -1.6
const DECK_Y: float = 0.0
const SEA_Y: float = -30.0

const YELLOW := Color(1.0, 0.8, 0.12)
const RED := Color(1.0, 0.22, 0.15)
const BLUE := Color(0.3, 0.6, 1.0)
const CRATE_A := Color(0.62, 0.64, 0.6)
const CRATE_B := Color(0.38, 0.44, 0.34)

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _cp_world: Array[Vector3] = []
var _cp_nodes: Array[Checkpoint] = []
var _finish_pos: Vector3 = Vector3.ZERO
## Where the hangar, the elevator, the deck and the island ended up (set by the stages).
var _anchor: Dictionary = {}


func _configure() -> void:
	theme_id = "carrier"
	music_track = "carrier"
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


## Local y of a world height (for things standing on the hangar floor, the deck, the sea).
func _ly(world_y: float) -> float:
	return world_y - _o.y


## A steel plate you land on, held up by a pair of stanchions down to `floor_y` (world).
func _plate(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.6, floor_y: float = HANGAR_FLOOR) -> Dictionary:
	kit.plat(_w(c), _sz(Vector3(sx, thick, sz)), style, 0.0)
	_legs(c - Vector3(0, thick, 0), sx, sz, floor_y)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


func _legs(top: Vector3, sx: float, sz: float, floor_y: float) -> void:
	var wt: Vector3 = _w(top)
	var h: float = wt.y - floor_y
	if h <= 0.2:
		return
	var mat: StandardMaterial3D = Look.flat(Color(0.36, 0.38, 0.4), 0.6, 0.5)
	for sxs: float in [-1.0, 1.0]:
		for szs: float in [-1.0, 1.0]:
			var p := Vector3(sxs * maxf(sx * 0.5 - 0.3, 0.1), 0, szs * maxf(sz * 0.5 - 0.3, 0.1))
			var leg := Look.box(Vector3(0.18, h, 0.18), mat, _w(top + p) - Vector3(0, h * 0.5, 0))
			add_child(leg)
	if h > 3.0:
		var brace := Look.box(_sz(Vector3(sx - 0.4, 0.12, 0.12)), mat, _w(top - Vector3(0, h * 0.5, 0)))
		add_child(brace)


## A stack of shipping crates standing on the hangar floor; its top is walkable.
func _stack(c: Vector3, sx: float, sz: float, style: String = "main", floor_y: float = HANGAR_FLOOR) -> Dictionary:
	kit.plat(_w(c), _sz(Vector3(sx, 0.5, sz)), style, 0.0)
	var top_y: float = _w(c).y - 0.5
	var y: float = floor_y
	var i: int = 0
	while y < top_y - 0.1:
		var h: float = minf(kit.rng.randf_range(1.2, 1.9), top_y - y)
		var col: Color = CRATE_A if i % 2 == 0 else CRATE_B
		var cr := Look.box(_sz(Vector3(sx - 0.1, h, sz - 0.1)), Look.flat(col.darkened(kit.rng.randf_range(0.0, 0.15)), 0.75, 0.2), Vector3.ZERO)
		cr.position = Vector3(_w(c).x, y + h * 0.5, _w(c).z)
		cr.rotation.y = deg_to_rad(_yaw + kit.rng.randf_range(-3.0, 3.0))
		add_child(cr)
		y += h
		i += 1
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


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


## A mover with its hover pods taken off (carrier movers are tugs, trolleys and pallets).
func _mover(top: Vector3, size: Vector3, pts: Array[Vector3], period: float, phase: float = 0.0, dwell: float = 0.25) -> MovingPlatform:
	var wp: Array[Vector3] = []
	for p: Vector3 in pts:
		wp.append(_d(p))
	var m := MovingPlatform.new()
	m.size = _sz(size)
	m.points = wp
	m.period = period
	m.phase = phase
	m.dwell = dwell
	m.style = "alt"
	m.position = _w(top) - Vector3(0, size.y * 0.5, 0)
	add_child(m)
	for ch: Node in m.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is CylinderMesh:
			ch.queue_free()
	return m


## Checkpoint landing facing the next stage's heading (_next_yaw).
func _cp(c: Vector3, size: float = 6.0, floor_y: float = HANGAR_FLOOR) -> Dictionary:
	var d: Dictionary = _plate(c, size, size, "main", 1.0, floor_y)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	_cp_nodes.append(cp)
	return d


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
	set_spawn(Vector3(0, -11.9, 16), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, 0.0, -90.0, 0.0, 90.0, 0.0, 90.0, 0.0, -90.0, 180.0, 180.0, 180.0, -150.0, 0.0, 90.0, -90.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	_frame(Vector3(0, -12.0, 12.0), yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	_stage_18()
	_hangar_basics()
	_surroundings()
	_carrier_materials()
	_checkpoint_fx()


## Up on the island, landing far below the level you have climbed to counts as a fall (you would
## otherwise land alive on the deck or a lower roof, stuck 10-20 m under your checkpoint).
func _check_failure() -> void:
	super._check_failure()
	if finished or player == null or not player.grounded:
		return
	var floor_y: float = -INF
	for f: Vector2 in _floors:
		if current_checkpoint >= int(f.x):
			floor_y = maxf(floor_y, f.y)
	if player.global_position.y < floor_y:
		fail()


## (checkpoint index, lowest safe height): once that checkpoint is banked, standing below it is a fall.
var _floors: Array[Vector2] = []


# ---- stage 1: Fantail - the stern deck under the round-down, crates in the foam, a mantle ----------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3(0, 0, 1.0)), _sz(Vector3(20, 2, 16)), "main", 0.0)
	var start: Dictionary = _area(Vector3(0, 0, 0), 10.0, 7.0)
	var c1: Dictionary = _stack(Vector3(0, -0.8, -11.4), 2.4, 2.4)
	var c2: Dictionary = _stack(Vector3(2.6, -1.6, -16.4), 2.2, 2.2, "alt")
	var c3: Dictionary = _stack(Vector3(0.4, -2.2, -22.0), 2.2, 2.2)
	var l1: Dictionary = _ledge(Vector3(0.4, 0.8, -26.25), Vector3(3.2, _ly(HANGAR_FLOOR) * -1.0 + 0.8, 2.2))
	var cp: Dictionary = _cp(Vector3(0, 0.8, -35.2))
	_hop(start, c1)
	_hop(c1, c2)
	_hop(c2, c3)
	r_mantle(_w(Vector3(0.4, -2.2, -22.75)), _w(Vector3(0.4, 0.8, -26.4)))
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: The Flood - ride the tugs across the foam, the tyre bounce, the catwalk ----------------

func _stage_2() -> Vector3:
	var t1: MovingPlatform = _mover(Vector3(0, -3.4, -7.0), Vector3(2.8, 0.4, 3.2), [Vector3.ZERO, Vector3(0, 0, -8.0)], 8.0, 0.0)
	var pad_p := Vector3(0, -3.0, -21.6)
	kit.pad(_w(pad_p), 18.0, 0.0, 0.0, 1.2)
	_stack(pad_p - Vector3(0, 0.3, 0), 2.6, 2.6)
	_plate(Vector3(0, 1.2, -29.6), 2.4, 6.0, "alt", 0.5)
	var t2: MovingPlatform = _mover(Vector3(0, -1.0, -38.0), Vector3(3.0, 0.4, 3.0), [Vector3.ZERO, Vector3(-9.0, 0, 0)], 9.0, 0.0)
	var cp: Dictionary = _cp(Vector3(-9.0, -0.4, -45.6))
	# ride the first tug out across the foam (board it at its near rest, off at its far rest)
	# SHORTCUT: a maintenance hatch on a far ledge (a 90% leap) - its passage lets you out at the
	# catwalk's end, past both the tug and the tyre stack
	_plate(Vector3(-8.9, 0.3, -2.0), 1.4, 1.4, "accent", 0.5)
	kit.portal(_w(Vector3(-8.9, 0.3, -2.4)), _yaw, _w(Vector3(0, 1.2, -30.2)), _yaw, 5.0)
	_hatch_frame(Vector3(-8.9, 0.3, -2.9))
	_arrival(_w(Vector3(0, 1.2, -31.0)))
	if route_variant == 2:
		r_walk(_w(Vector3(-2.4, 0, -2.0)))
		r_jump(_w(Vector3(-2.65, 0, -2.0)), _w(Vector3(-8.9, 0.3, -2.0)))
		r_portal(_w(Vector3(-8.9, 0.3, -2.6)), _w(Vector3(0, 1.2, -31.0)))
	else:
		var near1: Vector3 = Vector3.ZERO
		var far1: Vector3 = _d(Vector3(0, 0, -8.0))
		_board(_w(Vector3(0, 0, -2.65)), t1, Vector3(0, 0.2, 0.4), func() -> bool: return _mover_at(t1, near1, 0.3, 0.0, 0.7))
		r_jump_from_ride(t1, _home(t1) + far1, 0.3, _w(pad_p), true, Vector3(0, 0.2, -0.8))
		r_pad(_w(pad_p), _w(Vector3(0, 1.2, -28.4)))
	r_walk(_w(Vector3(0, 1.2, -32.2)))
	var far2: Vector3 = _d(Vector3(-9.0, 0, 0))
	_board(_w(Vector3(0, 1.2, -32.25)), t2, Vector3(0, 0.2, 0.3), func() -> bool: return _mover_at(t2, Vector3.ZERO, 0.3, 0.0, 0.8))
	r_jump_from_ride(t2, _home(t2) + far2, 0.3, _w(Vector3(-9.0, -0.4, -44.2)), true, Vector3(0, 0.2, -0.6))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Steam Line (BRANCH) - steam jets and rams on the catwalk | the hull run ------------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _plate(Vector3(0, 0, -7.0), 12.0, 3.0, "main", 0.8)
	# RIGHT: the catwalk under the burst steam line - steam jets across it, rams from the wall
	_plate(Vector3(3.5, 0, -24.5), 2.2, 32.0, "alt", 0.5)
	var jets: Array[LaserGate] = []
	var jz: Array[float] = [-13.0, -23.0, -33.0]
	for i: int in 3:
		jets.append(kit.laser(_w(Vector3(3.5, 1.2, jz[i])), Vector3(3.4, 2.4, 0.3), 3.8, 0.3, fposmod(0.3 * float(i), 1.0), _yaw))
	var rams: Array[Piston] = []
	var rz: Array[float] = [-18.0, -28.0]
	for i: int in 2:
		rams.append(kit.piston(_w(Vector3(6.6, 1.3, rz[i])), Vector3(1.6, 1.2, 1.4), _yaw + 90.0, 3.2, 4.4, fposmod(0.15 + 0.5 * float(i), 1.0), 9.0))
	# LEFT: up the pipe rack, then run the hull plating over the foam
	_ledge(Vector3(-5.5, 3.3, -11.5), Vector3(2.4, _ly(HANGAR_FLOOR) * -1.0 + 3.3, 3.0), "alt")
	kit.wallrun(_w(Vector3(-7.5, 4.5, -22.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _plate(Vector3(-5.5, 3.3, -35.0), 3.0, 4.0, "alt", 0.6)
	var merge: Dictionary = _plate(Vector3(0, 0, -41.6), 12.0, 2.2, "main", 0.8)
	var cp: Dictionary = _cp(Vector3(0, 0, -50.5))
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(3.5, 0, -7.6)))
		r_walk(_w(Vector3(3.5, 0, -9.6)))
		var g0: LaserGate = jets[0]
		var g1: LaserGate = jets[1]
		var g2: LaserGate = jets[2]
		var p0: Piston = rams[0]
		var p1: Piston = rams[1]
		_wait(func() -> bool: return _dark(g0, 0.0, 2.0), _w(Vector3(3.5, 0, -10.6)))
		r_walk(_w(Vector3(3.5, 0, -15.6)))
		_wait(func() -> bool: return _ram_clear(p0, 0.0, 1.8), _w(Vector3(3.5, 0, -15.6)))
		r_walk(_w(Vector3(3.5, 0, -20.6)))
		_wait(func() -> bool: return _dark(g1, 0.0, 2.0), _w(Vector3(3.5, 0, -20.6)))
		r_walk(_w(Vector3(3.5, 0, -25.6)))
		_wait(func() -> bool: return _ram_clear(p1, 0.0, 1.8), _w(Vector3(3.5, 0, -25.6)))
		r_walk(_w(Vector3(3.5, 0, -30.6)))
		_wait(func() -> bool: return _dark(g2, 0.0, 2.0), _w(Vector3(3.5, 0, -30.6)))
		r_walk(_w(Vector3(3.5, 0, -41.4)))
	else:
		r_walk(_w(Vector3(-5.5, 0, -6.6)))
		r_mantle(_w(Vector3(-5.5, 0, -7.6)), _w(Vector3(-5.5, 3.3, -11.3)))
		r_wallrun(_w(Vector3(-5.3, 3.3, -12.65)), _w(Vector3(-7.0, 4.7, -16.6)), _w(Vector3(-7.0, 4.7, -27.5)), _w(Vector3(-5.5, 3.3, -34.3)))
		_hop(l2, merge, Vector3(-3.0, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Fire Door - through the divisional door, under the weapons lift, a mantle --------------

func _stage_4() -> Vector3:
	_plate(Vector3(0, 0, -9.75), 1.8, 13.5, "alt", 0.6)
	var door := CarrierFireDoor.new()
	var dx: float = _w(Vector3(0, 0, -9.0)).x
	door.reach_left = 17.5 + dx
	door.reach_right = 17.5 - dx
	door.height = CEIL_Y - HANGAR_FLOOR
	door.open_gap = 3.0
	door.period = 8.0
	door.open_time = 3.8
	door.phase = 0.0
	door.rotation.y = deg_to_rad(_yaw)
	door.position = Vector3(_w(Vector3(0, 0, -9.0)).x, HANGAR_FLOOR, _w(Vector3(0, 0, -9.0)).z)
	add_child(door)
	_plate(Vector3(0, 0, -21.0), 2.4, 9.0, "alt", 0.6)
	var press: Crusher = kit.crusher(_w(Vector3(0, 0, -21.0)), Vector3(2.2, 1.4, 2.4), 3.2, 4.4, 0.0, _yaw)
	var l2: Dictionary = _ledge(Vector3(0, 3.3, -28.65), Vector3(3.0, _ly(HANGAR_FLOOR) * -1.0 + 3.3, 2.2))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -37.5))
	r_walk(_w(Vector3(0, 0, -4.2)))
	_wait(func() -> bool: return door.is_open_for(Game.course_time, 0.0, 2.6), _w(Vector3(0, 0, -4.4)))
	r_walk(_w(Vector3(0, 0, -17.4)))
	_wait(func() -> bool: return _press_ok(press, 0.0, 2.2), _w(Vector3(0, 0, -17.6)))
	r_walk(_w(Vector3(0, 0, -24.8)))
	r_mantle(_w(Vector3(0, 0, -25.15)), _w(Vector3(0, 3.3, -28.8)))
	_hop(l2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Crane Run - ride the bridge crane's pallet across the bay, a crumbling pallet ----------

func _stage_5() -> Vector3:
	var p: MovingPlatform = _mover(Vector3(0, -1.6, -7.0), Vector3(3.0, 0.4, 3.0), [Vector3.ZERO, Vector3(0, 0, -6.5)], 8.0, 0.0)
	_anchor["crane_z"] = _o.z
	# the pallet hangs from the crane's hook block on its cables
	var cab: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.22), 0.4, 0.8)
	var top_y: float = CEIL_Y - 1.6 - (_w(Vector3(0, -1.6, 0)).y)
	for sx: float in [-1.0, 1.0]:
		p.add_child(Look.box(Vector3(0.06, top_y, 0.06), cab, Vector3(sx * 1.2, 0.2 + top_y * 0.5, 0)))
	p.add_child(Look.box(Vector3(1.2, 0.8, 0.8), Look.flat(YELLOW, 0.5, 0.3), Vector3(0, 0.2 + top_y - 0.4, 0)))
	kit.collapse(_w(Vector3(0.4, -1.0, -18.4)), 2.2, 0.55, 2.4)
	var cp: Dictionary = _cp(Vector3(0, -0.4, -24.0), 5.0)
	var far: Vector3 = _d(Vector3(0, 0, -6.5))
	# SHORTCUT: two hook blocks hanging beside the crane's run (1 m landings) - no waiting for it
	var h1: Dictionary = _plate(Vector3(3.3, -0.6, -7.6), 1.0, 1.0, "accent", 0.5, CEIL_Y)
	var h2: Dictionary = _plate(Vector3(3.3, -0.8, -12.8), 1.0, 1.0, "accent", 0.5, CEIL_Y)
	if route_variant == 2:
		r_walk(_w(Vector3(2.3, 0, -2.3)))
		r_jump(_w(Vector3(2.6, 0, -2.65)), _w((h1["c"] as Vector3)))
		_hop(h1, h2)
		_hop(h2, _area(Vector3(0.4, -1.0, -18.4), 1.1, 1.1))
	else:
		_board(_w(Vector3(0, 0, -2.65)), p, Vector3(0, 0.2, 0.3), func() -> bool: return _mover_at(p, Vector3.ZERO, 0.3, 0.0, 0.7))
		r_jump_from_ride(p, _home(p) + far, 0.3, _w(Vector3(0.4, -1.0, -18.4)), true, Vector3(0, 0.2, -0.6))
	r_jump(_w(Vector3(0.4, -1.0, -19.15)), _w(Vector3(0, -0.4, -22.6)))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Tug Lanes - hop the towed pallets lane to lane, the swinging hooks -----------------------

func _stage_6() -> Vector3:
	var m1: MovingPlatform = _mover(Vector3(0, -2.0, -8.0), Vector3(3.0, 0.4, 3.0), [Vector3.ZERO, Vector3(-10.0, 0, 0)], 10.0, 0.0)
	var m2: MovingPlatform = _mover(Vector3(-10.0, -2.0, -14.0), Vector3(3.0, 0.4, 3.0), [Vector3.ZERO, Vector3(10.0, 0, 0)], 10.0, 0.5)
	var s1: Dictionary = _stack(Vector3(0, -1.4, -20.5), 2.2, 2.2)
	var hooks: Array[Pendulum] = []
	hooks.append(kit.pendulum(_w(Vector3(0, 7.5, -23.5)), 7.0, 6.4, 0.0, _yaw, 45.0))
	var s2: Dictionary = _stack(Vector3(0.4, -0.8, -26.5), 1.8, 1.8, "alt")
	hooks.append(kit.pendulum(_w(Vector3(0.4, 7.5, -29.4)), 7.0, 6.4, 0.5, _yaw, 45.0))
	var cp: Dictionary = _cp(Vector3(0, -0.8, -34.6), 5.0)
	var off1: Vector3 = _d(Vector3(-10.0, 0, 0))
	_board(_w(Vector3(0, 0, -2.65)), m1, Vector3(0, 0.2, 0.3), func() -> bool: return _mover_at(m1, Vector3.ZERO, 0.3, 0.0, 0.7))
	r_jump_from_ride(m1, _home(m1) + off1, 0.3, _w(Vector3(-10.0, -2.0, -14.0)), true, Vector3(0, 0.2, -0.6))
	var off2: Vector3 = _d(Vector3(10.0, 0, 0))
	r_jump_from_ride(m2, _home(m2) + off2, 0.3, _w(Vector3(0, -1.4, -20.3)), true, Vector3(0, 0.2, -0.6))
	var h0: Pendulum = hooks[0]
	var h1: Pendulum = hooks[1]
	_wait(func() -> bool: return _hook_clear(h0, 0.2, 2.1))
	_hop(s1, s2)
	_wait(func() -> bool: return _hook_clear(h1, 0.2, 2.1))
	_hop(s2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## The hook's head stays out to the side of the route over [now + a, now + b].
static func _hook_clear(p: Pendulum, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if absf(sin(p.angle_at(Game.course_time + s))) * p.length < 2.6:
			return false
		s += 0.03
	return true


# ---- stage 7: Helo Hangar - ride a helicopter's turning rotor across the foam, tyre pads up -----------

func _stage_7() -> Vector3:
	var hub := Vector3(0, -1.2, -11.0)
	var rotor: RotatingPlatform = _rotor(hub, 10.0, 0.0)
	_anchor["rotor"] = _w(hub)
	_stack(Vector3(0, -1.2, -22.0), 2.4, 4.4)
	var pad_p := Vector3(0, -1.2, -23.1)
	kit.pad(_w(pad_p), 19.0, 0.0, 0.0, 1.1)
	var cp: Dictionary = _cp(Vector3(0, 3.0, -30.5))
	_r_dial(rotor, hub, Vector3(0, 0, -2.6), Vector3(0, -1.2, -4.4), Vector3(0, -1.2, -20.6), 4.0, 16.0)
	r_pad(_w(pad_p), _w(Vector3(0, 3.0, -29.0)))
	r_checkpoint()
	return cp["c"]


## A helicopter's rotor turning slowly: four long blades you can ride (hub at local `hub`).
func _rotor(hub: Vector3, period: float, phase: float) -> RotatingPlatform:
	var arms: Array[Dictionary] = []
	for i: int in 4:
		var a: float = float(i) / 4.0 * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var along: Vector3 = Vector3(6.4, 0.3, 1.6) if i % 2 == 0 else Vector3(1.6, 0.3, 6.4)
		arms.append({"pos": dir * 4.4, "size": along})
	return kit.spinner(_w(hub), period, arms, 1.2, phase, 0.4)


## Bot: board spinner `c` from `from` onto an arm tip passing `board`, ride it round and jump off
## toward `to` once our bearing from the hub is `lo`..`hi` degrees short of the exit line.
func _r_dial(c: RotatingPlatform, hub: Vector3, from: Vector3, board: Vector3, to: Vector3, lo: float, hi: float,
		tips: Array = [Vector3(7.0, 0.2, 0), Vector3(-7.0, 0.2, 0), Vector3(0, 0.2, 7.0), Vector3(0, 0.2, -7.0)], land: Vector3 = Vector3(6.4, 0.2, 0)) -> void:
	r_walk(_w(from))
	route.append({"kind": "x_wait", "nodes": [c], "locals": tips, "point": _w(board), "radius": 0.9, "lead": 0.55})
	route.append({"kind": "x_jump", "from": _w(from), "picked": true, "to_local": land})
	var hw: Vector3 = _w(hub)
	var ex: Vector3 = _w(to) - hw
	ex = Vector3(ex.x, 0, ex.z).normalized()
	var sgn: float = signf(c.period)
	route.append({"kind": "h_jump", "to": _w(to), "test": func() -> bool:
		var rel: Vector3 = player.global_position - hw
		rel = Vector3(rel.x, 0, rel.z).normalized()
		var a: float = rad_to_deg(atan2(rel.cross(ex).y, rel.dot(ex))) * sgn
		return a >= lo and a <= hi})


# ---- stage 8: Launch Engine - ride the test catapult across the bay, the steam jets --------------------

func _stage_8() -> Vector3:
	var cat := CarrierCatapult.new()
	cat.track_length = 4.2
	cat.period = 5.0
	cat.launch_speed = 24.0
	cat.launch_lift = 11.0
	cat.rotation.y = deg_to_rad(_yaw)
	cat.position = _w(Vector3(0, 0, -6.5))
	add_child(cat)
	_plate(Vector3(0, 0, -7.0), 3.4, 8.0, "main", 0.6)
	var land: Dictionary = _plate(Vector3(0, -1.0, -25.8), 3.0, 8.6, "alt", 0.6)
	var g: LaserGate = kit.laser(_w(Vector3(0, 0.2, -27.6)), Vector3(3.4, 2.4, 0.3), 3.6, 0.3, 0.2, _yaw)
	var cp: Dictionary = _cp(Vector3(0, -1.0, -38.0))
	r_walk(_w(Vector3(0, 0, -6.5)))
	route.append({"kind": "kick", "from": _w(Vector3(0, 0, -6.5)), "to": _w(Vector3(0, -1.0, -24.0))})
	r_walk(_w(Vector3(0, -1.0, -25.4)))
	_wait(func() -> bool: return _dark(g, 0.0, 2.0), _w(Vector3(0, -1.0, -25.4)))
	r_walk(_w(Vector3(0, -1.0, -29.6)))
	_hop(land, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Elevator One - out through the hangar door onto the deck-edge lift, up the hull ----------

func _stage_9() -> Vector3:
	# the lift: 14 x 14 m outboard of the port hull, resting at the hangar gallery, rising to the deck
	var e := CarrierElevator.new()
	e.size = Vector3(14.0, 0.8, 14.0)
	e.points = [Vector3.ZERO, Vector3(0, DECK_Y - _o.y, 0)]
	e.period = 14.0
	e.phase = 0.0
	e.open_side = _d(Vector3(0, 0, -1))
	e.position = _w(Vector3(0, 0, -10.5)) - Vector3(0, 0.4, 0)
	add_child(e)
	# the door sill between the gallery and the lift
	kit.plat(_w(Vector3(0, 0, -3.25)), _sz(Vector3(6.0, 0.6, 0.5)), "alt", 0.0)
	# the port apron on the flight deck above, where the lift lets you off
	var top_y: float = DECK_Y - _o.y
	var cp: Dictionary = _deck_cp(Vector3(_o.x - 0.5, DECK_Y, _o.z), 6.0, 6.0)
	r_walk(_w(Vector3(0, 0, -2.2)))
	var home: Vector3 = _home(e)
	_wait(func() -> bool: return _mover_at(e, Vector3.ZERO, 0.05, 0.0, 2.4), _w(Vector3(0, 0, -2.2)))
	r_walk(_w(Vector3(0, 0, -8.0)))
	r_wait(e, home + Vector3(0, top_y, 0), 0.05)
	r_walk(_w(Vector3(0, top_y, -2.0)))
	r_walk(Vector3(_o.x - 0.5, DECK_Y, _o.z))
	r_checkpoint()
	return _l(cp["w"])


# ---- flight deck helpers --------------------------------------------------------------------------

## World point -> the current frame's local coordinates.
func _l(world: Vector3) -> Vector3:
	return _b.inverse() * (world - _o)


## A stretch of intact flight deck (world x0..x1, z0..z1), top at DECK_Y, 1.6 m thick.
func _deck(x0: float, x1: float, z0: float, z1: float, style: String = "main") -> Dictionary:
	var c := Vector3((x0 + x1) * 0.5, DECK_Y, (z0 + z1) * 0.5)
	var sz := Vector3(absf(x1 - x0), 1.6, absf(z1 - z0))
	kit.plat(c, sz, style, 0.0)
	return {"w": c, "hx": sz.x * 0.5, "hz": sz.z * 0.5}


## A checkpoint standing on a new patch of deck at world `c`.
func _deck_cp(c: Vector3, sx: float, sz: float) -> Dictionary:
	var d: Dictionary = _deck(c.x - sx * 0.5, c.x + sx * 0.5, c.z - sz * 0.5, c.z + sz * 0.5)
	var cp: Checkpoint = kit.checkpoint(c, _next_yaw)
	_cp_world.append(c)
	_cp_nodes.append(cp)
	return d


## A catapult launch set piece whose jet holds at world `hold`, launching toward -Z (the bow).
func _launch(hold: Vector3, phase: float, bow_z: float, lane: Array[Vector2]) -> CarrierLaunch:
	var l := CarrierLaunch.new()
	l.track_length = absf(bow_z - hold.z)
	# the track is only painted where the deck is (local z ranges)
	var keep: Array[Vector2] = []
	for seg: Vector2 in lane:
		keep.append(Vector2(seg.x - hold.z, seg.y - hold.z))
	l.track_spans = keep
	l.period = 10.0
	l.phase = phase
	l.position = hold
	add_child(l)
	return l


const BOW_Z: float = -339.0
const HOLD_Z: float = -229.4
## The intact stretches of the two bow catapult lanes (world z from, to); the gaps between are open deck.
const LANE2: Array[Vector2] = [Vector2(-238.4, -251.0), Vector2(-257.0, -270.0), Vector2(-275.0, -280.0), Vector2(-283.5, -339.0)]
const LANE1: Array[Vector2] = [Vector2(-238.4, -256.0), Vector2(-259.5, -268.0), Vector2(-273.0, -282.0), Vector2(-285.5, -339.0)]


# ---- stage 10: Cat Two - run down the port catapult lane between launches -------------------------------

var _cat1: CarrierLaunch
var _cat2: CarrierLaunch


func _stage_10() -> Vector3:
	_cat2 = _launch(Vector3(-7.0, DECK_Y, HOLD_Z), 0.0, BOW_Z, LANE2)
	_cat1 = _launch(Vector3(9.0, DECK_Y, HOLD_Z), 0.5, BOW_Z, LANE1)
	# the port apron beside the lift (the checkpoint patch is part of it)
	_deck(-19.0, -13.0, -216.0, -226.3)
	_deck(-19.0, -13.0, -232.3, -248.0)
	# both lanes' blast-deflector strips and the lanes themselves, forward of the lifts
	_deck(-12.5, -1.5, -216.0, -220.3)
	_deck(3.5, 14.5, -216.0, -220.3)
	for seg: Vector2 in LANE2:
		_deck(-12.0, -2.0, seg.x, seg.y)
	# the catapult's shuttle track: a boost strip that flings you down the lane
	kit.boost(Vector3(-8.5, DECK_Y + 0.02, -247.5), Vector3(2.4, 0.3, 7.0), 0.0, 13.0)
	var cp: Dictionary = _deck_cp(Vector3(1.0, DECK_Y, -292.0), 5.0, 9.0)
	var c2: CarrierLaunch = _cat2
	var entry_z: float = -243.0 - HOLD_Z
	var exit_z: float = -292.0 - HOLD_Z
	r_walk(Vector3(-15.0, DECK_Y, -243.0))
	_wait(func() -> bool: return c2.lane_safe_for(Game.course_time, entry_z, exit_z, 0.0, 7.2), Vector3(-15.0, DECK_Y, -243.0))
	r_jump(Vector3(-13.35, DECK_Y, -243.0), Vector3(-9.0, DECK_Y, -243.6))
	r_walk(Vector3(-8.5, DECK_Y, -250.4))
	r_jump(Vector3(-8.5, DECK_Y, -250.65), Vector3(-8.5, DECK_Y, -260.0))
	route[route.size() - 1]["speed"] = 13.0
	r_walk(Vector3(-8.5, DECK_Y, -269.4))
	r_jump(Vector3(-8.5, DECK_Y, -269.65), Vector3(-8.5, DECK_Y, -276.2))
	r_walk(Vector3(-8.5, DECK_Y, -279.4))
	r_jump(Vector3(-8.5, DECK_Y, -279.65), Vector3(-8.0, DECK_Y, -285.0))
	r_walk(Vector3(-2.7, DECK_Y, -292.0))
	r_jump(Vector3(-2.35, DECK_Y, -292.0), Vector3(1.0, DECK_Y, -292.0))
	r_checkpoint()
	return _l(cp["w"])


# ---- stage 11: Cat One - back up the starboard lane toward the next jet, between launches ----------------

func _stage_11() -> Vector3:
	for seg: Vector2 in LANE1:
		_deck(4.0, 14.0, seg.x, seg.y)
	_deck(15.0, 24.0, -242.0, -248.0)
	var cp: Dictionary = _deck_cp(Vector3(19.5, DECK_Y, -236.0), 9.0, 12.0)
	var c1: CarrierLaunch = _cat1
	var entry_z: float = -292.0 - HOLD_Z
	var exit_z: float = -244.0 - HOLD_Z
	r_walk(Vector3(3.0, DECK_Y, -292.0))
	_wait(func() -> bool: return c1.lane_safe_for(Game.course_time, exit_z, entry_z, 0.0, 7.4), Vector3(3.0, DECK_Y, -292.0))
	r_jump(Vector3(3.15, DECK_Y, -292.0), Vector3(7.0, DECK_Y, -291.0))
	r_walk(Vector3(7.0, DECK_Y, -286.0))
	r_jump(Vector3(7.0, DECK_Y, -285.85), Vector3(7.0, DECK_Y, -280.8))
	r_walk(Vector3(7.0, DECK_Y, -273.6))
	r_jump(Vector3(7.0, DECK_Y, -273.35), Vector3(7.0, DECK_Y, -266.8))
	r_walk(Vector3(7.0, DECK_Y, -260.1))
	r_jump(Vector3(7.0, DECK_Y, -259.85), Vector3(7.0, DECK_Y, -254.8))
	r_walk(Vector3(13.3, DECK_Y, -244.0))
	r_jump(Vector3(13.65, DECK_Y, -244.0), Vector3(17.0, DECK_Y, -244.0))
	r_walk(Vector3(19.5, DECK_Y, -238.0))
	r_checkpoint()
	return _l(cp["w"])


# ---- stage 12: Blast Alley (BRANCH) - dash between jet run-ups on the deck strip | the gallery catwalk ---

func _stage_12() -> Vector3:
	var x0: float = 13.0
	var x1: float = 24.0
	_deck(x0, x1, -230.0, -174.0)
	var blasts: Array[CarrierBlast] = []
	var jz: Array[float] = [-209.0, -199.0, -189.0, -179.0]
	for i: int in jz.size():
		var b := CarrierBlast.new()
		b.size = Vector3(5.0, 4.0, 16.0)
		b.push = 85.0
		b.period = 5.4
		b.blast_time = 1.4
		b.warn = 1.0
		b.phase = fposmod(-0.22 * float(i), 1.0)
		b.rotation.y = deg_to_rad(-90.0)
		b.position = Vector3(x0 - 0.6, DECK_Y, jz[i])
		add_child(b)
		blasts.append(b)
		_parked_jet(Vector3(x0 - 7.9, DECK_Y, jz[i]), 90.0)
		_deck(-4.0, x0, jz[i] - 3.6, jz[i] + 3.6)
	var cp: Dictionary = _deck_cp(Vector3(18.5, DECK_Y, -168.0), 11.0, 12.0)
	# the gallery catwalk under the deck edge (the other way): gaps, a wall run on the hull, a mantle up
	var cy: float = DECK_Y - 4.0
	var cy3: float = DECK_Y - 3.3
	_catwalk(Vector3(25.8, cy, -210.0), 2.8, 12.0)
	_catwalk(Vector3(25.8, cy, -198.2), 2.8, 4.0)
	kit.wallrun(Vector3(24.4, cy + 1.2, -186.7), Vector3(16.0, 5.0, 0.5), 90.0)
	_catwalk(Vector3(25.8, cy3, -172.4), 2.8, 7.6)
	kit.ledge(Vector3(23.4, DECK_Y, -171.0), Vector3(1.6, 3.4, 5.0), 0.0, "alt")
	if route_variant != 1:
		for i: int in jz.size():
			var bl: CarrierBlast = blasts[i]
			var wz: float = jz[i] - 4.0
			_wait(func() -> bool: return bl.is_calm_for(Game.course_time, 0.0, 2.4), Vector3(18.5, DECK_Y, wz))
			r_walk(Vector3(18.5, DECK_Y, jz[i] + 4.6))
		r_walk(Vector3(18.5, DECK_Y, -168.0))
	else:
		r_walk(Vector3(22.5, DECK_Y, -221.0))
		r_jump(Vector3(23.65, DECK_Y, -216.5), Vector3(25.8, cy, -212.0))
		r_walk(Vector3(25.8, cy, -204.5))
		r_jump(Vector3(25.8, cy, -204.35), Vector3(25.8, cy, -198.8))
		r_wallrun(Vector3(25.8, cy, -196.55), Vector3(24.9, cy + 1.4, -192.4), Vector3(24.9, cy + 1.4, -181.5), Vector3(25.8, cy3, -174.8))
		r_walk(Vector3(26.4, cy3, -172.8))
		r_mantle(Vector3(26.6, cy3, -172.8), Vector3(22.8, DECK_Y, -171.6))
		r_walk(Vector3(18.5, DECK_Y, -168.0))
	r_checkpoint()
	return _l(cp["w"])


## A strike fighter parked on the deck with its nose toward `yaw` (visual + a solid fuselage).
func _parked_jet(at: Vector3, yaw: float, folded: bool = true) -> Node3D:
	var j: Node3D = CarrierCraft.jet(folded)
	j.position = at
	j.rotation.y = deg_to_rad(yaw)
	add_child(j)
	_solid(at + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 2.0, 0.4), Vector3(3.4, 2.4, 15.0), yaw)
	return j


## An invisible solid box (the collision of a piece of scenery built from primitives).
func _solid(center: Vector3, size: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.rotation.y = deg_to_rad(yaw)
	body.position = center
	add_child(body)
	return body


## A grated catwalk section (world centre of its top), hung off the hull.
func _catwalk(c: Vector3, sx: float, sz: float) -> void:
	kit.plat(c, Vector3(sx, 0.3, sz), "alt", 0.0)


# ---- stage 13: Deck Park - the tractor's ram on the girder, a towed dolly, the hook block ----------------

func _stage_13() -> Vector3:
	# a girder across the torn-up deck, a tractor ramming across it
	kit.plat(Vector3(18.5, DECK_Y, -156.5), Vector3(1.2, 0.8, 11.0), "alt", 0.0)
	var ram: Piston = kit.piston(Vector3(23.0, DECK_Y + 1.3, -158.0), Vector3(1.6, 1.2, 1.6), 90.0, 3.4, 5.0, 0.2, 9.0)
	# the ram rides out along a rail girder from its housing on the sponson's edge
	kit.plat(Vector3(23.6, DECK_Y - 0.1, -158.0), Vector3(8.2, 0.3, 1.4), "alt", 0.0)
	deco_later.append(func() -> void:
		var t: Node3D = CarrierCraft.tractor()
		t.position = Vector3(0, -0.75, 1.2)
		t.rotation.y = PI
		ram.add_child(t))
	_deck(14.0, 23.0, -151.0, -147.0)
	var tug: MovingPlatform = MovingPlatform.new()
	tug.size = Vector3(3.2, 0.5, 3.2)
	tug.points = [Vector3.ZERO, Vector3(0, 0, 9.0)]
	tug.period = 8.0
	tug.dwell = 0.25
	tug.style = "alt"
	tug.position = Vector3(18.5, DECK_Y - 0.25, -142.8)
	add_child(tug)
	for ch: Node in tug.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is CylinderMesh:
			ch.queue_free()
	_deck(15.0, 22.0, -129.8, -119.0)
	var press: Crusher = kit.crusher(Vector3(18.5, DECK_Y, -125.9), Vector3(2.4, 1.4, 2.6), 3.2, 4.4, 0.4, 0.0)
	var cp: Dictionary = _deck_cp(Vector3(18.5, DECK_Y, -116.0), 7.0, 6.0)
	r_walk(Vector3(18.5, DECK_Y, -160.8))
	_wait(func() -> bool: return _ram_clear(ram, 0.0, 2.0), Vector3(18.5, DECK_Y, -160.8))
	r_walk(Vector3(18.5, DECK_Y, -150.0))
	var home: Vector3 = _home(tug)
	_board(Vector3(18.5, DECK_Y, -147.35), tug, Vector3(0, 0.25, 0.4), func() -> bool: return _mover_at(tug, Vector3.ZERO, 0.3, 0.0, 0.7))
	r_jump_from_ride(tug, home + Vector3(0, 0, 9.0), 0.3, Vector3(18.5, DECK_Y, -128.8), true, Vector3(0, 0.25, 0.8))
	_wait(func() -> bool: return _press_ok(press, 0.0, 2.2), Vector3(18.5, DECK_Y, -128.6))
	r_walk(Vector3(18.5, DECK_Y, -122.4))
	r_walk(Vector3(18.5, DECK_Y, -117.0))
	r_checkpoint()
	return _l(cp["w"])


# ---- stage 14: The Wires - bounce across the arresting-gear pit on the taut cross-deck pendants ------------

func _stage_14() -> Vector3:
	var wz: Array[float] = [-108.5, -103.0, -97.5]
	for z: float in wz:
		var w := CarrierWire.new()
		w.length = 16.0
		w.strength = 15.0
		w.position = Vector3(18.0, DECK_Y + 0.35, z)
		add_child(w)
	# the aft flight deck: intact, the landing area, the island
	_deck(-19.0, 26.0, -93.0, 22.0)
	_deck(-42.0, -19.0, -93.0, 12.0)
	var cpw := Vector3(18.5, DECK_Y, -86.0)
	var cp: Checkpoint = kit.checkpoint(cpw, _next_yaw)
	_cp_world.append(cpw)
	_cp_nodes.append(cp)
	r_jump(Vector3(18.5, DECK_Y, -113.35), Vector3(18.5, DECK_Y + 0.35, -108.5))
	r_pad(Vector3(18.5, DECK_Y + 0.35, -108.5), Vector3(18.5, DECK_Y + 0.35, -103.0))
	r_pad(Vector3(18.5, DECK_Y + 0.35, -103.0), Vector3(18.5, DECK_Y + 0.35, -97.5))
	r_pad(Vector3(18.5, DECK_Y + 0.35, -97.5), Vector3(18.5, DECK_Y, -90.5))
	r_walk(Vector3(18.5, DECK_Y, -86.5))
	r_checkpoint()
	return _l(cpw)


# ---- the island ------------------------------------------------------------------------------------

## The island's solid blocks (the stages climb round the outside; decor dresses them later).
func _island_body() -> void:
	_solid(Vector3(30.0, 6.6, -62.0), Vector3(12.0, 13.2, 36.0))
	_solid(Vector3(30.0, 16.5, -63.5), Vector3(10.0, 6.6, 27.0))
	_solid(Vector3(30.0, 21.6, -60.0), Vector3(11.0, 3.6, 16.0))


# ---- stage 15: Island Base - up the ladders, along the gallery past the antenna rams, under the hatch ------

func _stage_15() -> Vector3:
	_island_body()
	_ledge_w(Vector3(22.2, 3.3, -77.5), Vector3(3.6, 3.3, 6.0))
	_ledge_w(Vector3(22.2, 6.6, -71.0), Vector3(3.6, 6.6, 3.0))
	kit.plat(Vector3(22.5, 6.6, -54.75), Vector3(3.0, 0.5, 29.5), "alt", 0.0)
	var rams: Array[Piston] = []
	for z: float in [-64.0, -56.0]:
		rams.append(kit.piston(Vector3(24.9, 6.6 + 1.3, z), Vector3(1.6, 1.2, 1.6), 90.0, 3.0, 4.8, 0.0 if z < -60.0 else 0.5, 9.0))
	var press: Crusher = kit.crusher(Vector3(22.5, 6.6, -50.0), Vector3(2.6, 1.2, 2.4), 3.0, 4.4, 0.3, 0.0)
	# round the aft face to the outboard balcony
	kit.plat(Vector3(30.0, 6.6, -42.0), Vector3(12.0, 0.5, 4.0), "alt", 0.0)
	var cpw := Vector3(38.3, 6.6, -42.0)
	kit.plat(cpw, Vector3(4.6, 0.8, 4.0), "main", 0.0)
	var cp: Checkpoint = kit.checkpoint(cpw, _next_yaw)
	_cp_world.append(cpw)
	_cp_nodes.append(cp)
	_floors.append(Vector2(_cp_world.size(), DECK_Y + 1.0))
	# SHORTCUT: a watertight door on a balcony on the island's forward face (a 90% leap from the first
	# ladder landing) - the passage inside lets you out on the aft gallery, past the rams and the hatch
	kit.plat(Vector3(29.2, 3.3, -82.4), Vector3(1.4, 0.4, 1.4), "accent", 0.0)
	kit.portal(Vector3(29.5, 3.3, -82.4), -90.0, Vector3(31.0, 6.6, -42.0), -90.0, 5.0)
	_arrival(Vector3(31.8, 6.6, -42.0))
	r_walk(Vector3(22.2, DECK_Y, -83.2))
	r_mantle(Vector3(22.2, DECK_Y, -82.9), Vector3(22.2, 3.3, -79.8))
	if route_variant == 2:
		r_walk(Vector3(23.0, 3.3, -80.1))
		r_jump(Vector3(23.3, 3.3, -80.3), Vector3(29.1, 3.3, -82.4))
		r_portal(Vector3(29.6, 3.3, -82.4), Vector3(31.8, 6.6, -42.0))
		r_walk(Vector3(38.3, 6.6, -42.4))
		r_checkpoint()
		return _l(cpw)
	r_mantle(Vector3(22.2, 3.3, -74.85), Vector3(22.2, 6.6, -71.6))
	r_walk(Vector3(22.5, 6.6, -66.4))
	var r0: Piston = rams[0]
	var r1: Piston = rams[1]
	_wait(func() -> bool: return _ram_clear(r0, 0.0, 2.0), Vector3(22.5, 6.6, -66.4))
	r_walk(Vector3(22.5, 6.6, -60.0))
	_wait(func() -> bool: return _ram_clear(r1, 0.0, 2.0), Vector3(22.5, 6.6, -60.0))
	r_walk(Vector3(22.5, 6.6, -53.2))
	_wait(func() -> bool: return _press_ok(press, 0.0, 2.2), Vector3(22.5, 6.6, -53.2))
	r_walk(Vector3(22.5, 6.6, -42.0))
	r_walk(Vector3(37.0, 6.6, -42.0))
	r_walk(Vector3(38.3, 6.6, -42.4))
	r_checkpoint()
	return _l(cpw)


# ---- stage 16: Antenna Screen (BRANCH) - the wall-run chimney up between the island and the screen |
# ---- the ledges up the screen's sea side --------------------------------------------------------------

func _stage_16() -> Vector3:
	# (frame: the outboard balcony, heading forward along the island's sea face)
	var panels: Array[Vector4] = [Vector4(2.3, 1.2, -5.3, -11.8), Vector4(-2.3, 6.0, -10.3, -18.3), Vector4(2.3, 9.0, -16.3, -24.3)]
	for pv: Vector4 in panels:
		var zc: float = (pv.z + pv.w) * 0.5
		var ln: float = absf(pv.z - pv.w)
		kit.wallrun(_w(Vector3(pv.x, pv.y, zc)), Vector3(ln, 7.0, 0.5), _yaw + 90.0)
	var top: Dictionary = _ledge(Vector3(-0.75, 11.9, -27.4), Vector3(4.5, 14.0, 3.2), "alt")
	var cp: Dictionary = _cp(Vector3(0, 11.9, -37.0), 6.0, _o.y + 4.0)
	_floors.append(Vector2(_cp_world.size(), 16.0))
	# the sea side of the screen: a gantry of ledges (the other way up)
	kit.plat(_w(Vector3(4.65, 0, -0.5)), _sz(Vector3(4.7, 0.6, 4.0)), "alt", 0.0)
	_ledge(Vector3(5.5, 3.3, -5.75), Vector3(3.0, 5.0, 3.0), "alt")
	_ledge(Vector3(5.5, 6.6, -10.55), Vector3(3.0, 5.0, 2.5), "alt")
	var b3: Dictionary = _ledge(Vector3(5.5, 9.9, -15.1), Vector3(3.0, 5.0, 2.5), "alt")
	var b3b: Dictionary = _plate(Vector3(5.0, 10.6, -20.3), 2.2, 2.2, "alt", 0.5, _o.y + 6.0)
	var b4: Dictionary = _plate(Vector3(5.5, 11.4, -25.8), 2.5, 2.5, "alt", 0.5, _o.y + 6.0)
	if route_variant != 1:
		r_wallrun(_w(Vector3(0.5, 0, -1.65)), _w(Vector3(1.7, 1.4, -6.4)), _w(Vector3(1.7, 1.4, -9.3)), _w(Vector3(-1.7, 5.5, -13.2)))
		r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 5.5, -13.2)), _w(Vector3(-1.7, 5.5, -16.2)), _w(Vector3(1.7, 8.5, -19.8)), true, true)
		r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 8.5, -19.8)), _w(Vector3(1.7, 8.5, -21.2)), _w(Vector3(-0.75, 11.9, -26.4)), true, true)
	else:
		r_walk(_w(Vector3(2.0, 0, 1.0)))
		r_walk(_w(Vector3(5.5, 0, 0.0)))
		r_mantle(_w(Vector3(5.5, 0, -1.85)), _w(Vector3(5.5, 3.3, -5.4)))
		r_mantle(_w(Vector3(5.5, 3.3, -6.9)), _w(Vector3(5.5, 6.6, -10.2)))
		r_mantle(_w(Vector3(5.5, 6.6, -11.45)), _w(Vector3(5.5, 9.9, -14.8)))
		_hop(b3, b3b)
		_hop(b3b, b4)
		_hop(b4, top, Vector3(0.6, 0, 0.6))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## A yardarm platform round the mast (2.6 m square at `top`), braced back to the mast by an arm.
func _yardarm(top: Vector3) -> Dictionary:
	kit.plat(top, Vector3(2.6, 0.4, 2.6), "alt", 0.0)
	var from := Vector3(30.0, top.y - 0.5, -56.5)
	var to := Vector3(top.x, top.y - 0.5, top.z)
	var d: Vector3 = to - from
	var arm := Look.box(Vector3(0.35, 0.35, d.length()), Look.flat(Color(0.62, 0.64, 0.66), 0.5, 0.5))
	arm.position = (from + to) * 0.5
	arm.rotation.y = atan2(-d.x, -d.z)
	add_child(arm)
	var brace := Look.box(Vector3(0.18, 0.18, d.length() * 0.8), Look.flat(Color(0.62, 0.64, 0.66), 0.5, 0.5))
	brace.position = (from + to) * 0.5 - Vector3(0, 1.0, 0)
	brace.rotation = Vector3(atan2(1.4, d.length() * 0.8), atan2(-d.x, -d.z), 0)
	add_child(brace)
	return {"c": top, "hx": 1.3, "hz": 1.3}


## The antenna screen standing off the island's sea face: a lattice of posts and rails with mesh
## panels, carrying the chimney's outer wall-run plates (their solid backs are the screen).
func _antenna_screen() -> void:
	var post: StandardMaterial3D = Look.flat(Color(0.55, 0.58, 0.6), 0.5, 0.5)
	var mesh_m: StandardMaterial3D = Look.flat(Color(0.3, 0.32, 0.34, 0.55), 0.8, 0.3)
	var x: float = 41.3
	var z: float = -44.5
	while z >= -66.5:
		add_child(Look.box(Vector3(0.3, 17.0, 0.3), post, Vector3(x + 0.2, 12.0, z)))
		z -= 5.5
	for y: float in [4.0, 9.0, 14.0, 19.5]:
		add_child(Look.box(Vector3(0.25, 0.25, 22.0), post, Vector3(x + 0.2, y, -55.5)))
	var panel := Look.box(Vector3(0.05, 15.0, 21.8), mesh_m, Vector3(x + 0.35, 11.8, -55.5))
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)
	# struts back to the island's roof edge
	for zz: float in [-47.0, -56.0]:
		var st := Look.box(Vector3(5.6, 0.25, 0.25), post, Vector3(38.5, 20.3, zz))
		add_child(st)


## A flight-deck status board on struts (the face you can wall-run is the kit panel in front).
func _status_board(c: Vector3, length: float) -> void:
	var back: StandardMaterial3D = Look.flat(Color(0.22, 0.24, 0.26), 0.6, 0.3)
	add_child(Look.box(Vector3(length + 0.6, 7.0, 0.3), back, c + Vector3(0, 0, 0.3)))
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.3, 0.3, 1.6), back, c + Vector3(sx * (length * 0.5 - 0.6), 2.4, 1.1)))
		add_child(Look.box(Vector3(0.3, 0.3, 1.6), back, c + Vector3(sx * (length * 0.5 - 0.6), -2.4, 1.1)))


## An oval watertight-door frame standing round a portal (local floor point, facing the frame's -Z).
func _hatch_frame(c: Vector3) -> void:
	var fm: StandardMaterial3D = Look.flat(Color(0.34, 0.36, 0.38), 0.5, 0.5)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.25
	ring.outer_radius = 1.55
	ring.rings = 24
	ring.ring_segments = 8
	var n := Look.mesh_node(ring, fm)
	n.rotation = Vector3(PI * 0.5, deg_to_rad(_yaw), 0)
	n.scale = Vector3(0.8, 1.0, 1.2)
	n.position = _w(c + Vector3(0, 1.3, 0))
	add_child(n)
	for i: int in 4:
		var dog := Look.box(Vector3(0.3, 0.12, 0.12), Look.flat(YELLOW, 0.5, 0.3))
		dog.position = _w(c + Vector3(1.05 * cos(float(i) * PI * 0.5 + 0.4), 1.3 + 1.45 * sin(float(i) * PI * 0.5 + 0.4), 0.1))
		add_child(dog)


## A mantle ledge in world coordinates (top centre, size), unturned.
func _ledge_w(top: Vector3, size: Vector3, style: String = "main") -> void:
	kit.ledge(top, size, 0.0, style)


# ---- stage 17: Radar Deck - ride the big turning radar round the island's face, up onto the bridge roof -----

func _stage_17() -> Vector3:
	_frame(Vector3.ZERO, 0.0)
	var hub := Vector3(29.5, 18.5, -89.0)
	var arms: Array[Dictionary] = [{"pos": Vector3(4.8, 0, 0), "size": Vector3(6.4, 0.4, 2.2)}, {"pos": Vector3(-4.8, 0, 0), "size": Vector3(6.4, 0.4, 2.2)}]
	var radar: RotatingPlatform = kit.spinner(hub, 12.0, arms, 1.4, 0.0, 0.4)
	_anchor["radar"] = radar
	var p1: Dictionary = _plate(Vector3(19.0, 18.5, -88.0), 4.0, 4.0, "alt", 0.5, DECK_Y)
	var p2: Dictionary = _plate(Vector3(22.5, 19.4, -82.0), 3.0, 3.0, "alt", 0.5, DECK_Y)
	var cpw := Vector3(26.8, 19.8, -74.8)
	var cp: Checkpoint = kit.checkpoint(cpw, _next_yaw)
	_cp_world.append(cpw)
	_cp_nodes.append(cp)
	var tips: Array = [Vector3(7.4, 0.2, 0), Vector3(-7.4, 0.2, 0)]
	# SHORTCUT: run the flight-deck status board along the island's face, kick off to a landing past
	# the radar (no waiting for the ride)
	kit.wallrun(Vector3(30.9, 19.7, -78.75), Vector3(7.0, 6.5, 0.5), 0.0)
	_status_board(Vector3(30.9, 19.7, -78.45), 7.0)
	if route_variant == 2:
		r_walk(Vector3(38.0, 18.5, -80.7))
		r_wallrun(Vector3(35.65, 18.5, -80.7), Vector3(31.8, 19.9, -79.25), Vector3(28.2, 19.9, -79.25), Vector3(19.2, 18.5, -87.6))
	else:
		_r_dial(radar, hub, Vector3(35.7, 18.5, -81.6), Vector3(34.25, 18.5, -83.3), Vector3(19.5, 18.5, -89.0), 4.0, 14.0, tips, Vector3(6.9, 0.2, 0))
	_hop(p1, p2)
	r_jump(Vector3(23.65, 19.4, -80.85), Vector3(26.5, 19.8, -75.6))
	r_walk(Vector3(26.8, 19.8, -75.0))
	r_checkpoint()
	return cpw


# ---- stage 18: The Mast - past the sweeping radar, up pri-fly, round the yardarms to the masthead ----------

func _stage_18() -> void:
	_frame(Vector3.ZERO, 0.0)
	var sw: Sweeper = kit.sweeper(Vector3(30.0, 19.8, -74.2), 2.2, 2, 3.6, 0.0)
	_ledge_w(Vector3(32.0, 23.4, -69.0), Vector3(4.0, 3.6, 2.0), "alt")
	_solid(Vector3(30.0, 27.3, -56.5), Vector3(3.0, 7.8, 3.0))
	_ledge_w(Vector3(30.0, 26.7, -61.5), Vector3(5.0, 3.3, 3.0))
	var y2: Dictionary = _yardarm(Vector3(37.2, 28.2, -57.5))
	var y3: Dictionary = _yardarm(Vector3(35.2, 29.7, -51.6))
	var y3b: Dictionary = _yardarm(Vector3(29.0, 30.5, -50.0))
	var y4: Dictionary = _yardarm(Vector3(24.5, 31.2, -55.3))
	kit.ledge(Vector3(30.0, 34.5, -56.5), Vector3(5.0, 3.3, 5.0), 0.0, "accent")
	kit.finish(Vector3(30.0, 34.5, -56.5), 180.0)
	_finish_pos = Vector3(30.0, 34.5, -56.5)
	var y1: Dictionary = _area(Vector3(30.0, 26.7, -61.5), 2.5, 1.5)
	r_walk(Vector3(28.0, 19.8, -74.6))
	route.append({"kind": "b_sweep", "to": Vector3(32.8, 19.8, -72.4), "sweeper": sw, "tol": 0.5})
	r_mantle(Vector3(32.5, 19.8, -72.4), Vector3(32.0, 23.4, -68.6))
	r_walk(Vector3(30.0, 23.4, -65.4))
	r_mantle(Vector3(30.0, 23.4, -65.4), Vector3(30.0, 26.7, -61.2))
	_hop(y1, y2)
	_hop(y2, y3)
	_hop(y3, y3b)
	_hop(y3b, y4)
	r_mantle(Vector3(25.45, 31.2, -55.3), Vector3(28.8, 34.5, -55.8))
	r_walk(Vector3(30.0, 34.5, -56.5))


func _hangar_basics() -> void:
	# the foam over the hangar deck: touch it and you are out
	var net := KillZone.new()
	net.show_mesh = false
	net.size = Vector3(80.0, 1.0, 400.0)
	net.position = Vector3(0, FOAM_Y - 0.4, -150.0)
	add_child(net)
	# the torn-up flight deck forward: a fall between the girders is a fall
	var dn := KillZone.new()
	dn.show_mesh = false
	dn.size = Vector3(45.0, 0.4, 240.0)
	dn.position = Vector3(3.5, DECK_Y - 1.9, -225.0)
	add_child(dn)


# ---- the ship, the sea and the sky round the course --------------------------------------------------

var deco: CarrierDecor
## Dressing to add once the decor exists (queued by the stages).
var deco_later: Array[Callable] = []


func _surroundings() -> void:
	deco = CarrierDecor.new(self, kit.rng)
	var stern_z: float = 22.0
	var bow_z: float = -345.0
	deco.sea(SEA_Y, stern_z, bow_z, 19.0)
	deco.hull(SEA_Y, HANGAR_FLOOR, DECK_Y - 1.6, stern_z, -232.0, bow_z, -222.3, -236.3)
	deco.hangar(HANGAR_FLOOR, FOAM_Y, CEIL_Y, 17.5, stern_z - 2.0, -232.0, -93.0, [-60.0])
	deco.angled_sponson(-42.0, -19.0, 12.0, -93.0, DECK_Y - 1.6)
	deco.steel_box(Vector3(19.0, DECK_Y - 6.6, -140.0), Vector3(24.0, DECK_Y - 1.6, -232.0), CarrierDecor.HAZE_DARK)
	deco.aft_markings(DECK_Y, stern_z, -80.0)
	for seg: Vector2 in LANE2:
		deco.lane_marks(-7.0, seg.x, seg.y, DECK_Y, 5.0)
	for seg: Vector2 in LANE1:
		deco.lane_marks(9.0, seg.x, seg.y, DECK_Y, 5.0)
	var holes: Array[Rect2] = [Rect2(-12.9, -238.8, 11.8, 18.8), Rect2(3.1, -238.8, 11.8, 18.8)]
	deco.refit_girders(-18.5, 24.0, -94.0, BOW_Z + 2.0, DECK_Y - 1.0, holes)
	_hangar_dressing()
	_deck_dressing()
	_island_dressing()
	_far_scenery()
	_ambient_fx()
	for f: Callable in deco_later:
		f.call()


## The hangar: aircraft standing in the foam, sprinklers raining foam, beacons, the crane over the
## crane run, bubbles on the foam.
func _hangar_dressing() -> void:
	var fl: float = HANGAR_FLOOR
	for p: Vector4 in [Vector4(10.0, 0.0, -10.0, 15.0), Vector4(10.5, 0.0, -45.0, -8.0), Vector4(10.0, 0.0, -88.0, 10.0), Vector4(9.5, 0.0, -110.0, -12.0)]:
		var j: Node3D = CarrierCraft.jet(true)
		j.position = Vector3(p.x, fl, p.z)
		j.rotation.y = deg_to_rad(p.w)
		add_child(j)
	var h: Node3D = CarrierCraft.helo(true)
	h.position = Vector3(-4.0, fl, -176.0)
	h.rotation.y = deg_to_rad(160.0)
	add_child(h)
	for p: Vector3 in [Vector3(-12.0, fl, 2.0), Vector3(12.5, fl, -66.0), Vector3(-13.0, fl, -140.0)]:
		var t: Node3D = CarrierCraft.tug()
		t.position = p
		t.rotation.y = kit.rng.randf() * TAU
		add_child(t)
	# the heavy-lift helicopter whose turning rotor you ride in the helo bay (the rotor is the ride)
	var hub: Vector3 = _anchor.get("rotor", Vector3.ZERO)
	if hub != Vector3.ZERO:
		var big: Node3D = CarrierCraft.helo(true)
		big.get_node("Rotor").queue_free()
		big.scale = Vector3.ONE * 1.72
		big.position = Vector3(hub.x, fl, hub.z - 0.35)
		big.rotation.y = PI
		add_child(big)
	# sprinklers raining foam under the intact deck, and the bubbles popping on the foam
	var z: float = 14.0
	while z > -92.0:
		for sx: float in [-1.0, 1.0]:
			CarrierFx.sprinkler(self, Vector3(sx * 8.5, CEIL_Y - 1.6, z + sx * 6.0), CEIL_Y - 1.6 - FOAM_Y, 22)
		z -= 18.0
	z = 10.0
	while z > -228.0:
		CarrierFx.foam_pops(self, Vector3(0, FOAM_Y + 0.2, z), Vector3(16.0, 0.1, 14.0), 50)
		z -= 30.0
	for zz: float in [5.0, -35.0, -75.0, -115.0, -155.0, -195.0]:
		for sx: float in [-1.0, 1.0]:
			deco.beacon(Vector3(sx * 17.2, -6.0, zz + sx * 8.0))
	var crane_z: float = _anchor.get("crane_z", 0.0)
	if crane_z != 0.0:
		deco.crane_bridge(crane_z, CEIL_Y - 1.2, 17.5)


## The flight deck: parked aircraft and tractors aft, gun mounts and launchers on the sponsons, whip
## antennas, the landing lens, the refit's scaffolding, welders and work lights, safety nets.
func _deck_dressing() -> void:
	var y: float = DECK_Y
	for p: Vector4 in [Vector4(14.0, 0.0, 12.0, 60.0), Vector4(14.5, 0.0, -1.0, 60.0), Vector4(15.0, 0.0, -14.0, 60.0), Vector4(-30.0, 0.0, 4.0, -120.0)]:
		_parked_jet(Vector3(p.x, y, p.z), p.w)
	for p: Vector3 in [Vector3(12.0, y, -34.0), Vector3(-6.0, y, 14.0)]:
		var hh: Node3D = CarrierCraft.helo(true)
		hh.position = p
		hh.rotation.y = deg_to_rad(95.0)
		add_child(hh)
		_solid(p + Vector3(0, 2.0, 0), Vector3(3.0, 3.6, 6.0), 95.0)
	for p: Vector3 in [Vector3(6.0, y, 4.0), Vector3(19.0, y, -24.0), Vector3(-20.0, y, -40.0)]:
		var tr: Node3D = CarrierCraft.tractor()
		tr.position = p
		tr.rotation.y = kit.rng.randf() * TAU
		add_child(tr)
	for m: Vector4 in [Vector4(28.2, -2.2, 18.0, 180.0), Vector4(-22.2, -2.2, 18.0, 180.0), Vector4(-22.0, -2.2, -300.0, 0.0)]:
		deco.steel_box(Vector3(m.x - 2.2, m.y - 0.8, m.z - 2.2), Vector3(m.x + 2.2, m.y, m.z + 2.2), CarrierDecor.HAZE_DARK)
		deco.ciws(Vector3(m.x, m.y, m.z), m.w)
	for m: Vector4 in [Vector4(28.8, -2.2, 2.0, 90.0), Vector4(-44.6, -2.2, -70.0, -90.0)]:
		deco.steel_box(Vector3(m.x - 2.0, m.y - 0.8, m.z - 2.2), Vector3(m.x + 2.0, m.y, m.z + 2.2), CarrierDecor.HAZE_DARK)
		deco.launcher(Vector3(m.x, m.y, m.z), m.w)
	deco.whips(26.2, 10.0, -38.0, -2.0, 1.0)
	deco.whips(-42.2, 8.0, -80.0, -2.0, -1.0)
	deco.landing_lens(Vector3(-40.0, y, -30.0))
	deco.safety_net(-42.0, 10.0, -6.5, -1.0, y)
	deco.safety_net(-42.0, -16.5, -90.0, -1.0, y)
	deco.safety_net(26.0, 18.0, -40.0, 1.0, y)
	# the flight deck crew in their jerseys (never on the route)
	var jerseys: PackedColorArray = CarrierFx.crew()
	var crew_at: Array[Vector4] = [Vector4(10.0, 0.0, 8.0, 0.0), Vector4(12.0, 0.0, -6.0, 3.0), Vector4(7.0, 0.0, -18.0, 5.0),
		Vector4(-2.0, 0.0, 6.0, 1.0), Vector4(-24.0, 0.0, 0.0, 2.0), Vector4(-10.0, 0.0, -40.0, 6.0), Vector4(4.0, 0.0, -60.0, 4.0),
		Vector4(-17.5, 0.0, -219.0, 1.0), Vector4(-14.5, 0.0, -221.0, 0.0), Vector4(22.5, 0.0, -246.5, 1.0), Vector4(14.0, 0.0, -78.0, 6.0)]
	for c: Vector4 in crew_at:
		var man: Node3D = CarrierCraft.crew(jerseys[int(c.w) % jerseys.size()])
		man.position = Vector3(c.x, y, c.z)
		man.rotation.y = kit.rng.randf() * TAU
		add_child(man)
	# the landing signal officers' platform on the port quarter, three of them on it
	deco.steel_box(Vector3(-46.5, y - 1.2, -15.0), Vector3(-42.0, y - 0.4, -8.0), CarrierDecor.HAZE_DARK)
	add_child(Look.box(Vector3(0.2, 1.4, 5.0), Look.flat(Color(0.3, 0.32, 0.34, 0.7), 0.3, 0.3), Vector3(-46.3, y + 0.3, -11.5)))
	for i: int in 3:
		var lso: Node3D = CarrierCraft.crew(jerseys[6])
		lso.position = Vector3(-44.5, y - 0.4, -13.5 + float(i) * 2.0)
		lso.rotation.y = PI * 0.5
		add_child(lso)
	# the arresting-gear engines under the wires, venting steam
	for z: float in [-98.0, -103.5, -109.0]:
		var eng := Look.cylinder(1.0, 16.0, Look.flat(Color(0.42, 0.44, 0.46), 0.4, 0.7), Vector3.ZERO, -1.0, 16)
		eng.rotation.z = PI * 0.5
		eng.position = Vector3(17.0, DECK_Y - 3.4, z)
		add_child(eng)
		CarrierFx.steam(self, Vector3(12.0 + kit.rng.randf_range(0.0, 10.0), DECK_Y - 2.4, z), 0.6, 2.2, 10)
	# the refit forward: scaffolding towers, welders, work lights over the open deck
	for p: Vector3 in [Vector3(-16.0, -1.0, -120.0), Vector3(0.0, -1.0, -150.0), Vector3(-3.0, -1.0, -200.0), Vector3(22.0, -1.0, -265.0), Vector3(-17.0, -1.0, -300.0)]:
		deco.scaffold(Vector3(p.x, 0, p.z), p.y, 5.5)
	for p: Vector3 in [Vector3(-10.0, -0.6, -110.0), Vector3(5.0, -0.6, -140.0), Vector3(-15.0, -0.6, -180.0), Vector3(20.5, -0.6, -300.0), Vector3(-1.0, -0.6, -320.0)]:
		CarrierFx.welding(self, p)
	for p: Vector3 in [Vector3(-8.0, y, -91.0), Vector3(-17.5, y, -246.5), Vector3(23.0, y, -247.0)]:
		deco.work_light(p, Vector3(0.3, -0.4, -1.0))


## The island: plated blocks with window bands, radar faces, the lattice mast and its yardarms.
func _island_dressing() -> void:
	var levels: Array = [
		{"a": Vector3(24.0, DECK_Y, -80.0), "b": Vector3(36.0, 13.2, -44.0), "win": 2.4, "wh": 0.8},
		{"a": Vector3(25.0, 13.2, -77.0), "b": Vector3(35.0, 19.8, -50.0), "win": 2.8, "wh": 1.6},
		{"a": Vector3(24.5, 19.8, -68.0), "b": Vector3(35.5, 23.4, -52.0), "win": 1.7, "wh": 1.4},
	]
	deco.island(24.0, 36.0, -80.0, -44.0, levels)
	deco.array_face(Vector3(23.9, 10.0, -58.0), -PI * 0.5)
	deco.array_face(Vector3(36.1, 10.0, -66.0), PI * 0.5)
	deco.array_face(Vector3(30.0, 10.0, -80.1), PI)
	deco.mast(30.0, -56.5, 23.4, 31.2, 3.0, [{"y": 29.0, "span": 9.0}], false)
	_antenna_screen()
	# the masthead above the finish: a pole, a yardarm, the top radar
	var pole := Look.cylinder(0.3, 9.0, Look.flat(Color(0.62, 0.64, 0.66), 0.5, 0.5), Vector3(31.8, 39.0, -54.8), 0.18, 10)
	add_child(pole)
	add_child(Look.box(Vector3(7.0, 0.2, 0.2), Look.flat(Color(0.62, 0.64, 0.66), 0.5, 0.5), Vector3(31.8, 41.0, -54.8)))
	var top := Node3D.new()
	top.set_script(CarrierDecor.SPIN)
	top.set("period", 3.2)
	top.add_child(Look.box(Vector3(4.0, 0.9, 0.25), Look.flat(Color(0.72, 0.74, 0.76), 0.5, 0.4), Vector3(0, 0.5, 0)))
	top.position = Vector3(31.8, 43.6, -54.8)
	add_child(top)
	for sx: float in [-1.0, 1.0]:
		for i: int in 3:
			var fm: StandardMaterial3D = Look.flat([YELLOW, BLUE, RED][i], 0.8)
			add_child(Look.box(Vector3(0.05, 0.6, 0.8), fm, Vector3(31.8 + sx * 3.2, 40.4 - float(i) * 0.75, -54.4)))
	# the big turning radar's face (dress the ride's arms as an antenna)
	var radar: RotatingPlatform = _anchor.get("radar", null)
	if radar != null:
		var grid: StandardMaterial3D = Look.flat(Color(0.6, 0.62, 0.64), 0.5, 0.5)
		for sx: float in [-1.0, 1.0]:
			for i: int in 6:
				radar.add_child(Look.box(Vector3(0.08, 0.06, 2.1), grid, Vector3(sx * (2.2 + float(i) * 1.1), 0.23, 0)))
		radar.add_child(Look.cylinder(1.0, 17.0, Look.flat(HAZE_POST, 0.6, 0.4), Vector3(0, -8.7, 0), 0.7, 12))


const HAZE_POST := Color(0.45, 0.48, 0.5)


## Far away: escorts on the horizon, the plane guard, the air patrol, gulls round the stern and the mast.
func _far_scenery() -> void:
	deco.escort(Vector3(-760.0, SEA_Y, -520.0), 150.0, 0.0)
	deco.escort(Vector3(880.0, SEA_Y, -240.0), 170.0, 0.0)
	deco.escort(Vector3(-520.0, SEA_Y, 640.0), 125.0, 0.0)
	deco.escort(Vector3(420.0, SEA_Y, -1150.0), 180.0, 0.0)
	deco.plane_guard(Vector3(-140.0, 18.0, -40.0), 70.0, 60.0)
	deco.patrol(Vector3(60.0, 190.0, -180.0), 420.0, 55.0)
	deco.gulls(Vector3(0.0, -3.0, 34.0), 12.0, 5, 14.0)
	deco.gulls(Vector3(30.0, 46.0, -60.0), 18.0, 6, 20.0)
	deco.gulls(Vector3(-10.0, 14.0, -300.0), 22.0, 5, 17.0)


## Particles everywhere: spray off the bow and along the hull, mist over the wake, sun glitter on
## the sea, salt glints and steam over the deck, dust in the light shafts falling into the hangar.
func _ambient_fx() -> void:
	for sx: float in [-1.0, 1.0]:
		CarrierFx.spray(self, Vector3(sx * 16.0, SEA_Y + 1.5, -335.0), Vector3(5.0, 1.0, 8.0), 50, Vector3(sx, 0, 0))
		CarrierFx.droplets(self, Vector3(sx * 17.0, SEA_Y + 2.0, -330.0), Vector3(4.0, 1.0, 8.0), 60, Vector3(sx, 0, 0))
		var z: float = -300.0
		while z < 10.0:
			CarrierFx.spray(self, Vector3(sx * 20.5, SEA_Y + 0.8, z), Vector3(1.5, 0.5, 18.0), 14, Vector3(sx, 0, 0))
			z += 45.0
	CarrierFx.wake_mist(self, Vector3(0, SEA_Y + 2.0, 60.0), Vector3(22.0, 2.0, 30.0), 30)
	CarrierFx.wake_mist(self, Vector3(0, SEA_Y + 2.0, 130.0), Vector3(34.0, 2.0, 40.0), 26)
	var sun_dir: Vector3 = -_sun.global_basis.z if _sun != null else Vector3(0.4, -0.6, 0.6)
	var g: Vector3 = Vector3(-sun_dir.x, 0, -sun_dir.z).normalized() * 160.0
	CarrierFx.glitter(self, Vector3(g.x, SEA_Y + 0.3, g.z - 120.0), Vector3(70.0, 0.1, 90.0), 110)
	CarrierFx.glitter(self, Vector3(g.x * 1.8, SEA_Y + 0.3, g.z * 1.8 - 120.0), Vector3(120.0, 0.1, 140.0), 90)
	# along the route: salt glints outside, dust in the daylight falling into the forward hangar
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3(0, -12.0, 12.0)
		var c: Vector3 = (here + prev) * 0.5 + Vector3(0, 3.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 8.0, 5.0, absf(here.z - prev.z) * 0.5 + 8.0)
		if c.y > -4.0:
			CarrierFx.salt(self, c, ext, 40)
		elif c.z < -93.0:
			CarrierFx.shaft_dust(self, c + Vector3(0, 2.0, 0), ext, 50)
	for p: Vector3 in [Vector3(0, -1.0, -129.0), Vector3(12.0, -1.0, -121.0)]:
		CarrierFx.steam(self, p, 1.4, 2.5, 18)


# ---- materials, bursts, live effects -------------------------------------------------------------------

const STEEL_SHADER: Shader = preload("res://visual/carrier_steel.gdshader")


## Swap every walkable surface to the painted-steel shader (same colours).
func _carrier_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = STEEL_SHADER
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


var _cp_bursts: Dictionary = {}


## Banked-stage feedback: a burst in the deck crew's jersey colours and a puff of catapult steam.
func _checkpoint_fx() -> void:
	for cp: Checkpoint in _cp_nodes:
		var at: Vector3 = cp.global_position
		_cp_bursts[cp] = [CarrierFx.crew_burst(self, at + Vector3(0, 0.8, 0), 60, 7.0), CarrierFx.steam_burst(self, at + Vector3(0, 0.3, 0), 1.2, 26)]
		cp.reached.connect(func(which: Checkpoint) -> void:
			if which.index > current_checkpoint:
				for p: GPUParticles3D in _cp_bursts[which]:
					p.restart()
					p.emitting = true)


## Bursts that fire when the player arrives at a spot (portal exits): {"at", "p", "cool"}
var _arrivals: Array[Dictionary] = []


func _arrival(at: Vector3) -> void:
	var a: GPUParticles3D = CarrierFx.steam_burst(self, at + Vector3(0, 0.4, 0), 1.0, 24)
	var b: GPUParticles3D = CarrierFx.crew_burst(self, at + Vector3(0, 1.0, 0), 30, 5.0)
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


## The finish: three jets thunder past the masthead trailing coloured smoke, a burst of crew colours
## and a flash of light.
func _finish_sequence() -> void:
	var cols: Array[Color] = [Color(0.9, 0.2, 0.15, 0.8), Color(0.95, 0.95, 0.95, 0.8), Color(0.2, 0.35, 0.9, 0.8)]
	for i: int in 3:
		var j: Node3D = CarrierCraft.jet(false)
		var trail: GPUParticles3D = CarrierFx.smoke_trail(cols[i])
		trail.position = Vector3(0, 2.0, 8.0)
		j.add_child(trail)
		add_child(j)
		var off := Vector3((float(i) - 1.0) * 14.0, 12.0 + absf(float(i) - 1.0) * -3.0, (absf(float(i) - 1.0)) * 12.0)
		var from: Vector3 = _finish_pos + Vector3(-60.0, 0, 320.0) + off
		var to: Vector3 = _finish_pos + Vector3(40.0, 10.0, -420.0) + off
		j.position = from
		j.look_at(to, Vector3.UP)
		var tw: Tween = create_tween()
		tw.tween_property(j, "position", to, 3.2)
		tw.tween_callback(j.queue_free)
		WorldAudio.at(self, "carrier_flyover", _finish_pos, 1.0, 300.0)
	var b: GPUParticles3D = CarrierFx.crew_burst(self, _finish_pos + Vector3(0, 1.2, 0), 120, 10.0)
	b.restart()
	b.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.95, 0.85)
	flash.light_energy = 6.0
	flash.omni_range = 26.0
	flash.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(flash)
	var tw2: Tween = create_tween()
	tw2.tween_property(flash, "light_energy", 0.0, 1.4)
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
	_env.sky = CarrierSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.72, 0.78, 0.9)
	_env.ambient_light_energy = 0.62
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.74, 0.82, 0.92)
	_env.fog_density = 0.0011
	_env.fog_aerial_perspective = 0.45
	_env.fog_sky_affect = 0.1
	_env.fog_sun_scatter = 0.3
	_env.fog_height = -20.0
	_env.fog_height_density = 0.012
	_env.glow_enabled = true
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 1.2
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.08
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.light_energy = 2.6
	_sun.rotation_degrees = Vector3(-42, 205, 0)
	_sun.shadow_blur = 0.8
	_sun.light_angular_distance = 0.4
	# the "fill" becomes the blue of the open sky from the other side
	_fill.light_color = Color(0.6, 0.72, 0.95)
	_fill.light_energy = 0.4
	_fill.rotation_degrees = Vector3(-50, 25, 0)
