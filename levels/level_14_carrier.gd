extends LevelBase
## 14. SUPER CARRIER - (header written when the course is final)

const FOAM_Y: float = -17.0
const HANGAR_FLOOR: float = -17.8
const CEIL_Y: float = -1.6
const DECK_Y: float = 0.0
const SEA_Y: float = -30.0
const HANGAR_HW: float = 17.0

const YELLOW := Color(1.0, 0.8, 0.12)
const RED := Color(1.0, 0.22, 0.15)
const GREEN := Color(0.25, 1.0, 0.4)
const BLUE := Color(0.3, 0.6, 1.0)
const STEEL := Color(0.5, 0.53, 0.56)
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
var _stage_frames: Array[Array] = []
var _stage_route_start: Array[int] = []
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


## A jump that only fires once test() is true (no pause: you see it coming and go).
func _jump_when(from: Vector3, to: Vector3, test: Callable) -> void:
	route.append({"kind": "h_jump", "from": from, "to": to, "test": test})


## A jump onto moving `node` (landing at its local `off`) that fires once test() is true.
func _board(from: Vector3, node: Node3D, off: Vector3, test: Callable) -> void:
	route.append({"kind": "h_jump", "from": from, "to_node": node, "to_local": off, "test": test})


## Position-hold flight (bot): steer toward `to` until `until` is true (or, without it, until landing).
func _fly(to: Variant, until: Variant = null, jump_from: Variant = null) -> void:
	var s: Dictionary = {"kind": "desert_fly", "to": to}
	if until != null:
		s["until"] = until
	if jump_from != null:
		s["jump_from"] = jump_from
	route.append(s)


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


## A MovingPlatform stays within `r` of its offset `at` (world offset) over [now + a, now + b].
## Where a mover's offsets are measured from (world).
static func _home(m: MovingPlatform) -> Vector3:
	return m.position - m.offset_at(Game.course_time)


static func _mover_at(m: MovingPlatform, at: Vector3, r: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if m.offset_at(Game.course_time + s).distance_to(at) > r:
			return false
		s += 0.05
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_restyle_environment()
	set_spawn(Vector3(0, -11.9, 16), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, 0.0, -90.0, 0.0, 90.0, 0.0, 90.0, 0.0, 180.0, 180.0, 180.0, 180.0, 180.0, 0.0, 90.0, 180.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	_frame(Vector3(0, -12.0, 12.0), yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		_stage_frames.append([_o, _yaw])
		_stage_route_start.append(route.size())
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	_stage_frames.append([_o, _yaw])
	_stage_route_start.append(route.size())
	_stage_18()
	_hangar_basics()
	_dev_start()


## Up on the island, the flight deck far below counts as a fall (you would otherwise land alive on
## the deck, 20 m under your checkpoint).
func _check_failure() -> void:
	super._check_failure()
	if finished or player == null or current_checkpoint < _island_cp:
		return
	if player.grounded and player.global_position.y < DECK_Y + 1.0:
		fail()


## Index (1-based) of the first checkpoint up on the island (set when the island is built).
var _island_cp: int = 999


## Dev only: `-- --carrier_from=K` starts the bot (and the spawn) at stage K.
func _dev_start() -> void:
	var k: int = 0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--carrier_from="):
			k = int(a.trim_prefix("--carrier_from="))
	if k <= 1 or k - 1 > _cp_world.size():
		return
	route = route.slice(_stage_route_start[k - 1])
	var f: Array = _stage_frames[k - 1]
	set_spawn((f[0] as Vector3) + Vector3(0, 0.1, 0), float(f[1]))


# ---- stage 1: Fantail - the stern deck under the round-down, crates in the foam, a mantle ----------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3(0, 0, 1.0)), _sz(Vector3(20, 2, 16)), "main", 0.0)
	var start: Dictionary = _area(Vector3(0, 0, 0), 10.0, 7.0)
	var c1: Dictionary = _stack(Vector3(0, -0.8, -11.4), 2.4, 2.4)
	var c2: Dictionary = _stack(Vector3(2.6, -1.6, -16.4), 2.2, 2.2, "alt")
	var c3: Dictionary = _stack(Vector3(0.4, -2.2, -22.0), 2.2, 2.2)
	var l1: Dictionary = _ledge(Vector3(0.4, 0.8, -26.65), Vector3(3.2, _ly(HANGAR_FLOOR) * -1.0 + 0.8, 3.0))
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
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var t1: MovingPlatform = _mover(Vector3(0, -3.4, -7.0), Vector3(2.8, 0.4, 3.2), [Vector3.ZERO, Vector3(0, 0, -8.0)], 8.0, 0.0)
	var pad_p := Vector3(0, -3.0, -21.6)
	kit.pad(_w(pad_p), 18.0, 0.0, 0.0, 1.2)
	_stack(pad_p - Vector3(0, 0.3, 0), 2.6, 2.6)
	var k: Dictionary = _plate(Vector3(0, 1.2, -29.6), 2.4, 6.0, "alt", 0.5)
	var t2: MovingPlatform = _mover(Vector3(0, -1.0, -38.0), Vector3(3.0, 0.4, 3.0), [Vector3.ZERO, Vector3(-9.0, 0, 0)], 9.0, 0.0)
	var cp: Dictionary = _cp(Vector3(-9.0, -0.4, -45.6))
	# ride the first tug out across the foam (board it at its near rest, off at its far rest)
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
	k.clear()
	cp0.clear()
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
		jets.append(kit.laser(_w(Vector3(3.5, 1.2, jz[i])), Vector3(3.4, 2.4, 0.3), 3.4, 0.35, fposmod(0.3 * float(i), 1.0), _yaw))
	var rams: Array[Piston] = []
	var rz: Array[float] = [-18.0, -28.0]
	for i: int in 2:
		rams.append(kit.piston(_w(Vector3(6.6, 1.3, rz[i])), Vector3(1.6, 1.2, 1.4), _yaw + 90.0, 3.2, 3.0, fposmod(0.15 + 0.5 * float(i), 1.0), 9.0))
	# LEFT: up the pipe rack, then run the hull plating over the foam
	_ledge(Vector3(-5.5, 3.3, -11.5), Vector3(2.4, _ly(HANGAR_FLOOR) * -1.0 + 3.3, 3.0), "alt")
	kit.wallrun(_w(Vector3(-7.5, 4.5, -22.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _plate(Vector3(-5.5, 3.3, -35.0), 3.0, 4.0, "alt", 0.6)
	var merge: Dictionary = _plate(Vector3(0, 0, -42.0), 12.0, 3.0, "main", 0.8)
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
		_wait(func() -> bool: return _dark(g0, 0.0, 1.5), _w(Vector3(3.5, 0, -10.6)))
		r_walk(_w(Vector3(3.5, 0, -15.6)))
		_wait(func() -> bool: return _ram_clear(p0, 0.0, 1.3), _w(Vector3(3.5, 0, -15.6)))
		r_walk(_w(Vector3(3.5, 0, -20.6)))
		_wait(func() -> bool: return _dark(g1, 0.0, 1.5), _w(Vector3(3.5, 0, -20.6)))
		r_walk(_w(Vector3(3.5, 0, -25.6)))
		_wait(func() -> bool: return _ram_clear(p1, 0.0, 1.3), _w(Vector3(3.5, 0, -25.6)))
		r_walk(_w(Vector3(3.5, 0, -30.6)))
		_wait(func() -> bool: return _dark(g2, 0.0, 1.5), _w(Vector3(3.5, 0, -30.6)))
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
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_plate(Vector3(0, 0, -9.75), 1.8, 13.5, "alt", 0.6)
	var door := CarrierFireDoor.new()
	door.width = 2.0 * (HANGAR_HW + absf(_w(Vector3.ZERO).x)) + 2.0
	door.height = CEIL_Y - HANGAR_FLOOR
	door.open_gap = 4.2
	door.period = 8.0
	door.open_time = 3.8
	door.phase = 0.0
	door.rotation.y = deg_to_rad(_yaw)
	door.position = Vector3(_w(Vector3(0, 0, -9.0)).x, HANGAR_FLOOR, _w(Vector3(0, 0, -9.0)).z)
	add_child(door)
	_anchor["door1"] = door.position
	var b2: Dictionary = _plate(Vector3(0, 0, -21.0), 2.4, 9.0, "alt", 0.6)
	var press: Crusher = kit.crusher(_w(Vector3(0, 0, -21.0)), Vector3(2.2, 1.4, 2.4), 3.2, 3.4, 0.0, _yaw)
	var l2: Dictionary = _ledge(Vector3(0, 3.3, -29.05), Vector3(3.0, _ly(HANGAR_FLOOR) * -1.0 + 3.3, 3.0))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -37.5))
	r_walk(_w(Vector3(0, 0, -4.2)))
	_wait(func() -> bool: return door.is_open_for(Game.course_time, 0.0, 2.6), _w(Vector3(0, 0, -4.4)))
	r_walk(_w(Vector3(0, 0, -17.4)))
	_wait(func() -> bool: return _press_ok(press, 0.0, 1.6), _w(Vector3(0, 0, -17.6)))
	r_walk(_w(Vector3(0, 0, -24.8)))
	r_mantle(_w(Vector3(0, 0, -25.15)), _w(Vector3(0, 3.3, -28.8)))
	_hop(l2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	b2.clear()
	cp0.clear()
	return cp["c"]


# ---- stage 5: Crane Run - ride the bridge crane's pallet across the bay, a crumbling pallet ----------

func _stage_5() -> Vector3:
	var p: MovingPlatform = _mover(Vector3(0, -1.6, -7.0), Vector3(3.0, 0.4, 3.0), [Vector3.ZERO, Vector3(0, 0, -6.5)], 8.0, 0.0)
	kit.collapse(_w(Vector3(0.4, -1.0, -18.4)), 2.2, 0.55, 2.4)
	var cp: Dictionary = _cp(Vector3(0, -0.4, -24.0), 5.0)
	var far: Vector3 = _d(Vector3(0, 0, -6.5))
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
	hooks.append(kit.pendulum(_w(Vector3(0, 7.5, -23.5)), 7.0, 3.0, 0.0, _yaw, 50.0))
	var s2: Dictionary = _stack(Vector3(0.4, -0.8, -26.5), 2.2, 2.2, "alt")
	hooks.append(kit.pendulum(_w(Vector3(0.4, 7.5, -29.4)), 7.0, 3.0, 0.5, _yaw, 50.0))
	var cp: Dictionary = _cp(Vector3(0, -0.8, -34.6))
	var off1: Vector3 = _d(Vector3(-10.0, 0, 0))
	_board(_w(Vector3(0, 0, -2.65)), m1, Vector3(0, 0.2, 0.3), func() -> bool: return _mover_at(m1, Vector3.ZERO, 0.3, 0.0, 0.7))
	r_jump_from_ride(m1, _home(m1) + off1, 0.3, _w(Vector3(-10.0, -2.0, -14.0)), true, Vector3(0, 0.2, -0.6))
	var off2: Vector3 = _d(Vector3(10.0, 0, 0))
	r_jump_from_ride(m2, _home(m2) + off2, 0.3, _w(Vector3(0, -1.4, -20.3)), true, Vector3(0, 0.2, -0.6))
	var h0: Pendulum = hooks[0]
	var h1: Pendulum = hooks[1]
	_wait(func() -> bool: return _hook_clear(h0, 0.2, 1.1))
	_hop(s1, s2)
	_wait(func() -> bool: return _hook_clear(h1, 0.2, 1.1))
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
	var s1: Dictionary = _stack(Vector3(0, -1.2, -22.0), 2.4, 4.4)
	var pad_p := Vector3(0, -1.2, -23.1)
	kit.pad(_w(pad_p), 19.0, 0.0, 0.0, 1.1)
	var cp: Dictionary = _cp(Vector3(0, 3.0, -30.5))
	_r_dial(rotor, hub, Vector3(0, 0, -2.6), Vector3(0, -1.2, -4.4), Vector3(0, -1.2, -20.6), 4.0, 16.0)
	r_pad(_w(pad_p), _w(Vector3(0, 3.0, -29.0)))
	r_checkpoint()
	s1.clear()
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
	var land: Dictionary = _plate(Vector3(0, -1.0, -26.5), 3.0, 10.0, "alt", 0.6)
	var g: LaserGate = kit.laser(_w(Vector3(0, 0.2, -29.0)), Vector3(3.4, 2.4, 0.3), 3.0, 0.35, 0.2, _yaw)
	var cp: Dictionary = _cp(Vector3(0, -1.0, -38.0))
	r_walk(_w(Vector3(0, 0, -6.5)))
	route.append({"kind": "kick", "from": _w(Vector3(0, 0, -6.5)), "to": _w(Vector3(0, -1.0, -24.0))})
	r_walk(_w(Vector3(0, -1.0, -26.8)))
	_wait(func() -> bool: return _dark(g, 0.0, 1.4), _w(Vector3(0, -1.0, -26.8)))
	r_walk(_w(Vector3(0, -1.0, -30.8)))
	_hop(land, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Elevator One - out through the hangar door onto the deck-edge lift, up the hull ----------

var _elev: CarrierElevator


func _stage_9() -> Vector3:
	# the lift: 14 x 14 m outboard of the port hull, resting at the hangar gallery, rising to the deck
	var e := CarrierElevator.new()
	e.size = Vector3(14.0, 0.8, 14.0)
	e.points = [Vector3.ZERO, Vector3(0, DECK_Y - _o.y, 0)]
	e.period = 14.0
	e.phase = 0.0
	e.open_side = _d(Vector3(0, 0, -1))
	e.position = _w(Vector3(0, 0, -10.0)) - Vector3(0, 0.4, 0)
	add_child(e)
	_elev = e
	_anchor["elevator"] = _w(Vector3(0, 0, -10.0))
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
func _launch(hold: Vector3, phase: float, bow_z: float) -> CarrierLaunch:
	var l := CarrierLaunch.new()
	l.track_length = absf(bow_z - hold.z)
	l.period = 10.0
	l.phase = phase
	l.position = hold
	add_child(l)
	return l


const BOW_Z: float = -339.0
const HOLD_Z: float = -229.4


# ---- stage 10: Cat Two - run down the port catapult lane between launches -------------------------------

var _cat1: CarrierLaunch
var _cat2: CarrierLaunch


func _stage_10() -> Vector3:
	_cat2 = _launch(Vector3(-7.0, DECK_Y, HOLD_Z), 0.0, BOW_Z)
	_cat1 = _launch(Vector3(9.0, DECK_Y, HOLD_Z), 0.5, BOW_Z)
	# the port apron beside the lift (the checkpoint patch is part of it)
	_deck(-19.0, -13.0, -216.0, -226.3)
	_deck(-19.0, -13.0, -232.3, -248.0)
	# both lanes' blast-deflector strips and the lanes themselves, forward of the lifts
	_deck(-12.5, -1.5, -216.0, -220.3)
	_deck(3.5, 14.5, -216.0, -220.3)
	var lane2: Array[Vector2] = [Vector2(-238.4, -252.0), Vector2(-255.5, -270.0), Vector2(-274.0, -280.0), Vector2(-283.5, BOW_Z)]
	for seg: Vector2 in lane2:
		_deck(-12.0, -2.0, seg.x, seg.y)
	var cp: Dictionary = _deck_cp(Vector3(1.0, DECK_Y, -292.0), 5.0, 9.0)
	var c2: CarrierLaunch = _cat2
	var entry_z: float = -243.0 - HOLD_Z
	var exit_z: float = -292.0 - HOLD_Z
	r_walk(Vector3(-15.0, DECK_Y, -243.0))
	_wait(func() -> bool: return c2.lane_safe_for(Game.course_time, entry_z, exit_z, 0.0, 7.2), Vector3(-15.0, DECK_Y, -243.0))
	r_jump(Vector3(-13.35, DECK_Y, -243.0), Vector3(-9.0, DECK_Y, -243.6))
	r_walk(Vector3(-8.5, DECK_Y, -251.4))
	r_jump(Vector3(-8.5, DECK_Y, -251.65), Vector3(-8.5, DECK_Y, -256.8))
	r_walk(Vector3(-8.5, DECK_Y, -269.4))
	r_jump(Vector3(-8.5, DECK_Y, -269.65), Vector3(-8.5, DECK_Y, -275.2))
	r_walk(Vector3(-8.5, DECK_Y, -279.4))
	r_jump(Vector3(-8.5, DECK_Y, -279.65), Vector3(-8.0, DECK_Y, -285.0))
	r_walk(Vector3(-2.7, DECK_Y, -292.0))
	r_jump(Vector3(-2.35, DECK_Y, -292.0), Vector3(1.0, DECK_Y, -292.0))
	r_checkpoint()
	return _l(cp["w"])


# ---- stage 11: Cat One - back up the starboard lane toward the next jet, between launches ----------------

func _stage_11() -> Vector3:
	var lane1: Array[Vector2] = [Vector2(-238.4, -256.0), Vector2(-259.5, -268.0), Vector2(-272.0, -282.0), Vector2(-285.5, BOW_Z)]
	for seg: Vector2 in lane1:
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
	r_walk(Vector3(7.0, DECK_Y, -272.6))
	r_jump(Vector3(7.0, DECK_Y, -272.35), Vector3(7.0, DECK_Y, -266.8))
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
		b.period = 4.8
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
			_wait(func() -> bool: return bl.is_calm_for(Game.course_time, 0.0, 2.0), Vector3(18.5, DECK_Y, wz))
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
	var ram: Piston = kit.piston(Vector3(23.0, DECK_Y + 1.3, -158.0), Vector3(1.6, 1.2, 1.6), 90.0, 3.4, 4.4, 0.2, 9.0)
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
	var isl: Dictionary = _deck(15.0, 22.0, -129.8, -119.0)
	var press: Crusher = kit.crusher(Vector3(18.5, DECK_Y, -125.9), Vector3(2.4, 1.4, 2.6), 3.2, 3.4, 0.4, 0.0)
	var cp: Dictionary = _deck_cp(Vector3(18.5, DECK_Y, -116.0), 7.0, 6.0)
	r_walk(Vector3(18.5, DECK_Y, -160.8))
	_wait(func() -> bool: return _ram_clear(ram, 0.0, 1.6), Vector3(18.5, DECK_Y, -160.8))
	r_walk(Vector3(18.5, DECK_Y, -150.0))
	var home: Vector3 = _home(tug)
	_board(Vector3(18.5, DECK_Y, -147.35), tug, Vector3(0, 0.25, 0.4), func() -> bool: return _mover_at(tug, Vector3.ZERO, 0.3, 0.0, 0.7))
	r_jump_from_ride(tug, home + Vector3(0, 0, 9.0), 0.3, Vector3(18.5, DECK_Y, -128.8), true, Vector3(0, 0.25, 0.8))
	_wait(func() -> bool: return _press_ok(press, 0.0, 1.6), Vector3(18.5, DECK_Y, -128.6))
	r_walk(Vector3(18.5, DECK_Y, -122.4))
	r_walk(Vector3(18.5, DECK_Y, -117.0))
	r_checkpoint()
	isl.clear()
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

const ISLAND_X0: float = 24.0
const ISLAND_X1: float = 36.0
const ISLAND_Z0: float = -80.0
const ISLAND_Z1: float = -44.0


## The island's solid blocks (the stages climb round the outside; decor dresses them later).
func _island_body() -> void:
	_solid(Vector3(30.0, 6.6, -62.0), Vector3(12.0, 13.2, 36.0))
	_solid(Vector3(30.0, 16.5, -63.5), Vector3(10.0, 6.6, 27.0))
	_solid(Vector3(30.0, 21.6, -60.0), Vector3(11.0, 3.6, 16.0))


# ---- stage 15: Island Base - up the ladders, along the gallery past the antenna rams, under the hatch ------

func _stage_15() -> Vector3:
	_island_body()
	_ledge_w(Vector3(22.2, 3.3, -76.5), Vector3(3.6, 3.3, 4.0))
	_ledge_w(Vector3(22.2, 6.6, -71.0), Vector3(3.6, 6.6, 3.0))
	kit.plat(Vector3(22.5, 6.6, -54.75), Vector3(3.0, 0.5, 29.5), "alt", 0.0)
	var rams: Array[Piston] = []
	for z: float in [-64.0, -56.0]:
		rams.append(kit.piston(Vector3(24.9, 6.6 + 1.3, z), Vector3(1.6, 1.2, 1.6), 90.0, 3.0, 3.6, 0.0 if z < -60.0 else 0.5, 9.0))
	var press: Crusher = kit.crusher(Vector3(22.5, 6.6, -50.0), Vector3(2.6, 1.2, 2.4), 3.0, 3.6, 0.3, 0.0)
	# round the aft face to the outboard balcony
	kit.plat(Vector3(31.25, 6.6, -42.0), Vector3(14.5, 0.5, 4.0), "alt", 0.0)
	var cpw := Vector3(38.3, 6.6, -42.0)
	kit.plat(cpw, Vector3(4.6, 0.8, 4.0), "main", 0.0)
	var cp: Checkpoint = kit.checkpoint(cpw, _next_yaw)
	_cp_world.append(cpw)
	_cp_nodes.append(cp)
	_island_cp = _cp_world.size()
	r_walk(Vector3(22.2, DECK_Y, -81.2))
	r_mantle(Vector3(22.2, DECK_Y, -80.9), Vector3(22.2, 3.3, -77.8))
	r_mantle(Vector3(22.2, 3.3, -74.85), Vector3(22.2, 6.6, -71.6))
	r_walk(Vector3(22.5, 6.6, -66.4))
	var r0: Piston = rams[0]
	var r1: Piston = rams[1]
	_wait(func() -> bool: return _ram_clear(r0, 0.0, 1.3), Vector3(22.5, 6.6, -66.4))
	r_walk(Vector3(22.5, 6.6, -60.0))
	_wait(func() -> bool: return _ram_clear(r1, 0.0, 1.3), Vector3(22.5, 6.6, -60.0))
	r_walk(Vector3(22.5, 6.6, -53.2))
	_wait(func() -> bool: return _press_ok(press, 0.0, 1.5), Vector3(22.5, 6.6, -53.2))
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
		if pv.x > 0.0:
			_solid(_w(Vector3(pv.x + 0.55, pv.y, zc)), _sz(Vector3(0.6, 9.0, ln + 1.0)))
	var top: Dictionary = _ledge(Vector3(-0.75, 11.9, -27.8), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 11.9, -37.0), 6.0, _o.y + 4.0)
	# the sea side of the screen: a gantry of ledges (the other way up)
	kit.plat(_w(Vector3(4.65, 0, -0.5)), _sz(Vector3(4.7, 0.6, 4.0)), "alt", 0.0)
	var b1: Dictionary = _ledge(Vector3(5.5, 3.3, -5.75), Vector3(3.0, 5.0, 3.0), "alt")
	var b2: Dictionary = _ledge(Vector3(5.5, 6.6, -10.55), Vector3(3.0, 5.0, 2.5), "alt")
	var b3: Dictionary = _ledge(Vector3(5.5, 9.9, -15.1), Vector3(3.0, 5.0, 2.5), "alt")
	var b4: Dictionary = _plate(Vector3(4.0, 11.4, -21.0), 2.5, 2.5, "alt", 0.5, _o.y + 6.0)
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
		_hop(b3, b4)
		_hop(b4, top, Vector3(0, 0, 1.2))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	b1.clear()
	b2.clear()
	return cp["c"]


## A mantle ledge in world coordinates (top centre, size), unturned.
func _ledge_w(top: Vector3, size: Vector3, style: String = "main") -> void:
	kit.ledge(top, size, 0.0, style)


# ---- stage 17: Radar Deck - ride the big turning radar round the island's face, up onto the bridge roof -----

func _stage_17() -> Vector3:
	_frame(Vector3.ZERO, 0.0)
	var hub := Vector3(29.5, 18.5, -89.0)
	var arms: Array[Dictionary] = [{"pos": Vector3(4.8, 0, 0), "size": Vector3(6.4, 0.4, 2.2)}, {"pos": Vector3(-4.8, 0, 0), "size": Vector3(6.4, 0.4, 2.2)}]
	var radar: RotatingPlatform = kit.spinner(hub, 12.0, arms, 1.4, 0.0, 0.4)
	var p1: Dictionary = _plate(Vector3(19.5, 18.5, -89.0), 3.0, 3.0, "alt", 0.5, DECK_Y)
	var p2: Dictionary = _plate(Vector3(22.5, 19.4, -82.0), 3.0, 3.0, "alt", 0.5, DECK_Y)
	kit.plat(Vector3(30.0, 19.8, -72.5), Vector3(10.0, 0.4, 9.0), "main", 0.0)
	var cpw := Vector3(26.8, 19.8, -74.8)
	var cp: Checkpoint = kit.checkpoint(cpw, _next_yaw)
	_cp_world.append(cpw)
	_cp_nodes.append(cp)
	var tips: Array = [Vector3(7.4, 0.2, 0), Vector3(-7.4, 0.2, 0)]
	_r_dial(radar, hub, Vector3(35.7, 18.5, -81.6), Vector3(34.25, 18.5, -83.3), Vector3(19.5, 18.5, -89.0), 4.0, 14.0, tips, Vector3(6.9, 0.2, 0))
	_hop(p1, p2)
	r_jump(Vector3(23.65, 19.4, -80.85), Vector3(26.5, 19.8, -75.6))
	r_walk(Vector3(26.8, 19.8, -75.0))
	r_checkpoint()
	return cpw


# ---- stage 18: The Mast - past the sweeping radar, up pri-fly, round the yardarms to the masthead ----------

func _stage_18() -> void:
	_frame(Vector3.ZERO, 0.0)
	var sw: Sweeper = kit.sweeper(Vector3(31.0, 19.8, -72.0), 3.0, 2, 3.6, 0.0)
	_ledge_w(Vector3(32.0, 23.4, -68.0), Vector3(4.0, 3.6, 2.0), "alt")
	kit.plat(Vector3(30.0, 23.4, -60.0), Vector3(11.0, 0.4, 16.0), "main", 0.0)
	_solid(Vector3(30.0, 27.3, -56.5), Vector3(3.0, 7.8, 3.0))
	_ledge_w(Vector3(30.0, 26.7, -61.5), Vector3(5.0, 3.3, 3.0))
	var y2: Dictionary = _plate(Vector3(34.8, 28.2, -58.5), 2.6, 2.6, "alt", 0.4, 23.4)
	var y3: Dictionary = _plate(Vector3(33.8, 29.7, -53.5), 2.6, 2.6, "alt", 0.4, 23.4)
	var y3b: Dictionary = _plate(Vector3(29.8, 30.5, -51.2), 2.6, 2.6, "alt", 0.4, 23.4)
	var y4: Dictionary = _plate(Vector3(26.0, 31.2, -55.0), 2.6, 2.6, "alt", 0.4, 23.4)
	kit.ledge(Vector3(30.0, 34.5, -56.5), Vector3(5.0, 3.3, 5.0), 0.0, "accent")
	kit.finish(Vector3(30.0, 34.5, -56.5), 180.0)
	_finish_pos = Vector3(30.0, 34.5, -56.5)
	var y1: Dictionary = _area(Vector3(30.0, 26.7, -61.5), 2.5, 1.5)
	r_walk(Vector3(28.0, 19.8, -74.6))
	route.append({"kind": "b_sweep", "to": Vector3(33.0, 19.8, -71.3), "sweeper": sw, "tol": 0.5})
	r_mantle(Vector3(32.5, 19.8, -71.4), Vector3(32.0, 23.4, -67.6))
	r_walk(Vector3(30.0, 23.4, -65.4))
	r_mantle(Vector3(30.0, 23.4, -65.4), Vector3(30.0, 26.7, -61.2))
	_hop(y1, y2)
	_hop(y2, y3)
	_hop(y3, y3b)
	_hop(y3b, y4)
	r_mantle(Vector3(25.1, 31.2, -55.0), Vector3(28.8, 34.5, -55.5))
	r_walk(Vector3(30.0, 34.5, -56.5))


func _hangar_basics() -> void:
	# the foam over the hangar deck: touch it and you are out
	var net := KillZone.new()
	net.show_mesh = false
	net.size = Vector3(80.0, 1.0, 400.0)
	net.position = Vector3(0, FOAM_Y - 0.4, -150.0)
	add_child(net)
	var pm := PlaneMesh.new()
	pm.size = Vector2(80.0, 400.0)
	var foam := Look.mesh_node(pm, Look.flat(Color(0.92, 0.93, 0.88), 0.9), Vector3(0, FOAM_Y, -150.0))
	add_child(foam)
	# the torn-up flight deck forward: a fall between the girders is a fall
	var dn := KillZone.new()
	dn.show_mesh = false
	dn.size = Vector3(45.0, 0.4, 240.0)
	dn.position = Vector3(3.5, DECK_Y - 1.9, -225.0)
	add_child(dn)


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
