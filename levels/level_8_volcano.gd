extends LevelBase
## 8. CINDER PEAK - WIP

const ROCK_SHADER: Shader = preload("res://visual/volcano_rock.gdshader")
const SKY_SHADER: Shader = preload("res://visual/volcano_sky.gdshader")

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (set dressing and ambient layers follow them).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every basalt column mesh hung under a platform shares one material.
var _column_mat: StandardMaterial3D


func _configure() -> void:
	theme_id = "volcano"
	music_track = "volcano"
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


func _d(l: Vector3) -> Vector3:
	return _b * l


## A local size (x across, z along) turned into world axes (frames only turn in 90 degree steps).
func _sz(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0 else size


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## A walkable basalt slab on top of a hexagonal column that runs down into the dark.
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, column: bool = true) -> Dictionary:
	var body: StaticBody3D = kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if column:
		_column(_w(c - Vector3(0, thick, 0)), clampf(minf(sx, sz) * 0.42, 0.45, 2.2))
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5, "node": body}


## A hexagonal basalt column hanging down from world point `top` (visual only).
func _column(top: Vector3, radius: float, length: float = 46.0) -> void:
	if _column_mat == null:
		_column_mat = Look.flat(Color(0.13, 0.11, 0.11), 0.92)
	var r: float = snappedf(radius, 0.1)
	var n := Look.cylinder(r, length, _column_mat, top - Vector3(0, length * 0.5, 0), r * 1.08, 6)
	n.rotation.y = deg_to_rad(_yaw) + 0.26
	add_child(n)


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	_column(_w(top - Vector3(0, size.y, 0)), clampf(minf(size.x, size.z) * 0.4, 0.5, 2.0))
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


func _haz(c: Vector3, size: Vector3, yaw_extra: float = 0.0) -> KillZone:
	return kit.hazard(_w(c), size, _yaw + yaw_extra)


## Checkpoint platform facing the next stage's heading (_next_yaw), dressed as a cairn camp.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var h: float = size * 0.5 - 0.5
	_cairn(_w(c + Vector3(-h, 0, h)))
	_cairn(_w(c + Vector3(h, 0, -h)))
	# banked-stage feedback: a fountain of embers and a burst of sparks
	var f: GPUParticles3D = VolcanoFx.fountain(self, _w(c) + Vector3(0, 0.3, 0), 50, 10.0)
	var s: GPUParticles3D = VolcanoFx.sparks(self, _w(c) + Vector3(0, 0.6, 0), 30, 8.0)
	_cp_bursts[cp] = [f, s]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart())
	return d


## A little stack of basalt stones with an ember glowing on top (decor).
func _cairn(p: Vector3) -> void:
	var n := Node3D.new()
	var stone: StandardMaterial3D = Look.flat(Color(0.2, 0.17, 0.16), 0.9)
	for i: int in 3:
		var s := Look.cylinder(0.32 - 0.07 * float(i), 0.22, stone, Vector3(0.03 * float(i), 0.11 + 0.22 * float(i), 0), -1.0, 6)
		s.rotation.y = float(i) * 0.7
		n.add_child(s)
	n.add_child(Look.sphere(0.1, Look.flat(Color(1.0, 0.5, 0.15), 0.4, 0.0, 4.0), Vector3(0.06, 0.78, 0)))
	n.position = p
	add_child(n)


## A lava pool in the stage frame: `c` is the centre of its surface, `size` local (x across, z along).
func _lava(c: Vector3, size: Vector2, flow: Vector2 = Vector2(0.0, 0.35), crust: float = 0.55) -> VolcanoLava:
	var l := VolcanoLava.new()
	l.size = size
	var f: Vector3 = _b * Vector3(flow.x, 0, flow.y)
	l.flow = Vector2(f.x, f.z)
	l.crust = crust
	l.position = _w(c)
	l.rotation.y = deg_to_rad(_yaw)
	add_child(l)
	return l


## A lava-bomb landing ring on the floor at local `c`. The bomb comes in from the volcano.
func _bomb(c: Vector3, radius: float, period: float, phase: float, warn: float = 1.5) -> VolcanoBomb:
	var bm := VolcanoBomb.new()
	bm.radius = radius
	bm.period = period
	bm.phase = phase
	bm.warn = warn
	bm.source = _bomb_source(_w(c))
	bm.position = _w(c)
	add_child(bm)
	return bm


## Where a bomb landing at world `at` comes from: up and back toward the summit.
func _bomb_source(at: Vector3) -> Vector3:
	var toward: Vector3 = _summit_guess - at
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 1.0 else Vector3.FORWARD
	return toward * 55.0 + Vector3(0, 65.0, 0)


## Rough summit direction for bomb sources while the course is built (refined in _surroundings).
var _summit_guess: Vector3 = Vector3(0, 150, -600)


func _basalt(c: Vector3, radius: float = 1.25, mode: VolcanoBasalt.Mode = VolcanoBasalt.Mode.SINK) -> VolcanoBasalt:
	var bs := VolcanoBasalt.new()
	bs.radius = radius
	bs.mode = mode
	bs.position = _w(c)
	bs.rotation.y = deg_to_rad(_yaw)
	add_child(bs)
	return bs


func _pulse_basalt(c: Vector3, period: float, phase: float, depth: float = 2.6, up: float = 0.45, radius: float = 1.2) -> VolcanoBasalt:
	var bs := VolcanoBasalt.new()
	bs.radius = radius
	bs.mode = VolcanoBasalt.Mode.PULSE
	bs.period = period
	bs.phase = phase
	bs.depth = depth
	bs.up_fraction = up
	bs.position = _w(c)
	bs.rotation.y = deg_to_rad(_yaw)
	add_child(bs)
	return bs


func _crust(c: Vector3, sx: float, sz: float, delay: float = 0.8) -> VolcanoCrust:
	var cr := VolcanoCrust.new()
	cr.size = _sz(Vector3(sx, 0.4, sz))
	cr.delay = delay
	cr.position = _w(c)
	add_child(cr)
	return cr


func _fumarole(floor_c: Vector3, height: float, period: float, on: float, phase: float, width: float = 2.4, along: float = 2.4, push: float = 80.0, max_rise: float = 12.0) -> VolcanoFumarole:
	var f := VolcanoFumarole.new()
	f.size = Vector3(width, height, along)
	f.period = period
	f.on_fraction = on
	f.phase = phase
	f.push = push
	f.max_rise = max_rise
	f.position = _w(floor_c)
	f.rotation.y = deg_to_rad(_yaw)
	add_child(f)
	return f


## A lava curtain across the path at local floor point `c` (across = local X unless `turn`).
func _lavafall(c: Vector3, width: float, height: float, period: float, on: float, phase: float, below: float = 8.0, turn: float = 0.0) -> VolcanoLavaFall:
	var lf := VolcanoLavaFall.new()
	lf.size = Vector3(width, height, 0.7)
	lf.below = below
	lf.period = period
	lf.on_fraction = on
	lf.phase = phase
	lf.position = _w(c)
	lf.rotation.y = deg_to_rad(_yaw + turn)
	add_child(lf)
	return lf


## Position-hold flight (bot): steer toward `to` until `until` is true (or, without it, until landing).
func _fly(to: Vector3, until: Variant = null) -> void:
	var s: Dictionary = {"kind": "a_fly", "to": to}
	if until != null:
		s["until"] = until
	route.append(s)


## A jump the reach validator skips (a vent carries it): sprint through the takeoff at `from`
## and keep steering at `aim` (beyond the landing) until we touch down.
func _float_jump(from: Vector3, _to: Vector3, aim: Vector3) -> void:
	route.append({"kind": "h_jump", "from": from, "to": aim, "hold": true, "sprint": true})


# ---- bot conditions (all deterministic, from the course clock) --------------------------------------

static func _venting(f: VolcanoFumarole, need: float) -> bool:
	var t: float = Game.course_time
	return f.is_venting_at(t) and f.vent_left(t) > need


static func _bomb_clear(bm: VolcanoBomb, a: float, b: float) -> bool:
	return bm.is_clear_between(Game.course_time, a, b)


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9,
			_stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17, _stage_18]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		var end: Vector3 = stages[i].call()
		if i + 1 < stages.size():
			_frame(_w(end), yaws[i + 1])
	_surroundings()
	_volcano_materials()


# ---- stage 1: Ashfall Trail - hops up the lower flank, the first sinking basalt, a basalt step to mantle ----

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	_column(_w(Vector3(0, -2, 0)), 5.0)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	var a1: Dictionary = _blk(Vector3(0, 0.6, -11.8), 2.4, 2.4)
	var b1c := Vector3(2.6, 1.3, -17.4)
	_basalt(b1c, 1.3)
	var a2: Dictionary = _blk(Vector3(0.4, 2.3, -23.2), 2.0, 2.0, "alt")
	var m1: Dictionary = _ledge(Vector3(0.4, 5.6, -28.8), Vector3(4.0, 8.0, 3.0))
	var cp: Dictionary = _cp(Vector3(0.4, 5.6, -37.8))
	_lava(Vector3(0, -3.0, -21.0), Vector2(18.0, 30.0))
	_hop(start, a1)
	r_jump(_w(_edge(a1, b1c)), _w(b1c))
	r_jump(_w(b1c + (Vector3(0.4, 0, -23.2) - b1c).normalized() * 0.75), _w(a2["c"]))
	r_mantle(_w(_edge(a2, m1["c"])), _w((m1["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(m1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Sulphur Vents - a fumarole lifts you to a shelf, a pulsing vent floats you over a chasm ----

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var v1f: Dictionary = _blk(Vector3(0, 0, -9.0), 4.0, 6.0, "alt")
	var v1: VolcanoFumarole = _fumarole(Vector3(0, 0, -10.0), 8.0, 3.6, 0.5, 0.0)
	var s1: Dictionary = _blk(Vector3(0, 7.2, -16.8), 3.0, 3.0)
	var h1: Dictionary = _blk(Vector3(2.6, 7.2, -23.0), 1.6, 1.6, "alt")
	# the float: a vent in the chasm, 4 m deep along the path - jump into it and it carries you over
	_blk(Vector3(2.2, 1.0, -29.6), 3.0, 4.6, "alt", 1.0)
	var v2: VolcanoFumarole = _fumarole(Vector3(2.2, 1.0, -29.6), 11.5, 3.2, 0.62, 0.3, 2.6, 4.2, 80.0, 11.0)
	var l2: Dictionary = _blk(Vector3(1.4, 7.2, -38.2), 3.0, 5.0)
	var m2: Dictionary = _ledge(Vector3(1.4, 10.5, -44.0), Vector3(4.0, 9.0, 3.0), "alt")
	var cp: Dictionary = _cp(Vector3(1.0, 10.5, -53.2))
	_lava(Vector3(0.8, -2.5, -27.0), Vector2(16.0, 40.0), Vector2(0.4, 0.2))
	_hop(cp0, v1f, Vector3(0, 0, 1.6))
	r_walk(_w(Vector3(0, 0, -8.0)))
	_wait(func() -> bool: return _venting(v1, 1.3))
	var s1y: float = _w(s1["c"]).y
	_fly(_w(Vector3(0, 0, -10.0)), func() -> bool: return player.global_position.y > s1y + 1.2)
	_fly(_w(s1["c"]))
	_hop(s1, h1)
	r_walk(_w(Vector3(2.6, 7.2, -22.3)))
	_wait(func() -> bool: return _venting(v2, 1.6))
	_float_jump(_w(Vector3(2.45, 7.2, -23.45)), _w((l2["c"] as Vector3) + Vector3(0, 0, 0.8)), _w((l2["c"] as Vector3) + Vector3(0, 0, -2.0)))
	r_walk(_w(Vector3(1.4, 7.2, -39.6)))
	r_mantle(_w(Vector3(1.4, 7.2, -40.35)), _w((m2["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(m2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Bomb Field - cooled slabs across a lava lake; lava bombs land on the rings in turn ----

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var p1: Dictionary = _blk(Vector3(0, 0, -9.8), 3.0, 3.4)
	var p2: Dictionary = _blk(Vector3(3.0, 0.8, -17.0), 2.6, 2.6, "alt")
	var p3: Dictionary = _blk(Vector3(0.2, 1.6, -23.6), 2.6, 2.6)
	var p4: Dictionary = _blk(Vector3(-2.8, 1.6, -30.2), 2.2, 2.2, "alt")
	var cp: Dictionary = _cp(Vector3(-1.0, 1.6, -39.0))
	var b1: VolcanoBomb = _bomb(Vector3(0, 0, -9.8), 1.6, 3.2, 0.0)
	var b2: VolcanoBomb = _bomb(Vector3(3.0, 0.8, -17.0), 1.3, 3.2, 0.5)
	var b3: VolcanoBomb = _bomb(Vector3(0.2, 1.6, -23.6), 1.3, 3.2, 0.0)
	var b4: VolcanoBomb = _bomb(Vector3(-2.8, 1.6, -30.2), 1.1, 3.2, 0.5)
	_lava(Vector3(0, -2.8, -20.0), Vector2(18.0, 34.0), Vector2(-0.3, 0.1), 0.45)
	var bombs: Array[VolcanoBomb] = [b1, b2, b3, b4]
	var pads: Array[Dictionary] = [cp0, p1, p2, p3, p4]
	for i: int in bombs.size():
		var nb: VolcanoBomb = bombs[i]
		r_walk(_w(_edge(pads[i], pads[i + 1]["c"], 0.9)))
		_wait(func() -> bool: return _bomb_clear(nb, 0.0, 1.9))
		_hop(pads[i], pads[i + 1])
	_hop(p4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Obsidian Cliff - wall-run the glassy cliff over the lava river, mantle, run the far cliff ----

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var r1: Dictionary = _blk(Vector3(0, 0, -8.0), 3.0, 4.0, "alt")
	_panel(2.3, 1.2, -11.5, -27.5, 6.5)
	var r2: Dictionary = _blk(Vector3(-0.4, 0, -32.5), 3.6, 5.0, "alt")
	var m: Dictionary = _ledge(Vector3(-0.4, 3.3, -40.0), Vector3(4.0, 6.0, 3.0))
	_panel(-2.6, 4.5, -45.0, -59.0, 6.5)
	var cp: Dictionary = _cp(Vector3(1.4, 3.3, -64.0))
	_lava(Vector3(0, -3.5, -34.0), Vector2(18.0, 72.0), Vector2(0.0, 0.6), 0.4)
	_hop(cp0, r1, Vector3(0, 0, 0.8))
	r_wallrun(_w(Vector3(0.3, 0, -9.65)), _w(Vector3(1.8, 1.4, -13.6)), _w(Vector3(1.8, 1.4, -24.5)), _w(r2["c"]))
	r_mantle(_w(Vector3(-0.4, 0, -34.6)), _w(Vector3(-0.4, 3.3, -39.8)))
	r_wallrun(_w(Vector3(-0.6, 3.3, -41.15)), _w(Vector3(-2.0, 4.7, -46.0)), _w(Vector3(-2.0, 4.7, -54.5)), _w((cp["c"] as Vector3) + Vector3(-0.4, 0, 1.2)))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Crust Flow - rafts of cooling crust on a lava river, a flame jet over the gap ----
##  [shortcut: five 1 m obsidian spikes up the right bank - no rafts, no waiting]

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_lava(Vector3(0, -0.42, -20.0), Vector2(20.0, 34.0), Vector2(0.9, 0.0), 0.7)
	var c1c := Vector3(0.6, 0, -9.2)
	var c2c := Vector3(-1.8, 0, -15.0)
	_crust(c1c, 2.2, 2.2)
	_crust(c2c, 2.0, 2.0)
	var i1: Dictionary = _blk(Vector3(0.2, 0.5, -20.8), 2.2, 2.2)
	var jet: LaserGate = _flame(Vector3(0.8, 1.7, -24.1), 4.2, 3.6, 2.4, 0.5, 0.0)
	var c3c := Vector3(1.4, 0, -27.2)
	var c4c := Vector3(-0.8, 0, -32.8)
	_crust(c3c, 2.0, 2.0)
	_crust(c4c, 2.0, 2.0)
	var cp: Dictionary = _cp(Vector3(0, 0.8, -40.6))
	# SHORTCUT: 1 m obsidian spikes up the right bank, every jump near full reach
	var spikes: Array[Dictionary] = []
	var sp: Array[Vector3] = [Vector3(3.4, 0.6, -7.6), Vector3(4.2, 1.1, -13.6), Vector3(3.9, 1.5, -19.6), Vector3(3.3, 1.8, -25.6), Vector3(2.6, 1.8, -31.6)]
	for p: Vector3 in sp:
		spikes.append(_spike(p))
	if route_variant == 2:
		_hop(cp0, spikes[0])
		for i: int in spikes.size() - 1:
			_hop(spikes[i], spikes[i + 1])
		_hop(spikes[spikes.size() - 1], cp, Vector3(0, 0, 1.5))
	else:
		var c1: Dictionary = _area(c1c, 1.1, 1.1)
		var c2: Dictionary = _area(c2c, 1.0, 1.0)
		var c3: Dictionary = _area(c3c, 1.0, 1.0)
		var c4: Dictionary = _area(c4c, 1.0, 1.0)
		_hop(cp0, c1)
		_hop(c1, c2)
		_hop(c2, i1)
		r_walk(_w(_edge(i1, c3c, 0.8)))
		_wait(func() -> bool: return _jet_off(jet, 0.0, 0.8))
		_hop(i1, c3)
		_hop(c3, c4)
		_hop(c4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Lavafall Gorge (BRANCH) - hop the gorge floor between three lava falls, or run the wall above ----

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, false)
	_column(_w(Vector3(-3.5, -1.0, -8.0)), 1.4)
	_column(_w(Vector3(3.5, -1.0, -8.0)), 1.4)
	# LEFT (red): the gorge floor, three lava falls pouring across the gaps
	var a1: Dictionary = _blk(Vector3(-3.5, 0, -15.8), 2.2, 4.0, "alt")
	var a2: Dictionary = _blk(Vector3(-3.5, 0, -23.8), 2.2, 4.0, "alt")
	var a3: Dictionary = _blk(Vector3(-3.5, 0, -31.8), 2.2, 4.0, "alt")
	var falls: Array[VolcanoLavaFall] = []
	var fz: Array[float] = [-11.9, -19.8, -27.8]
	for i: int in 3:
		falls.append(_lavafall(Vector3(-3.5, 0, fz[i]), 3.2, 6.5, 3.0, 0.5, fposmod(0.62 - 0.36 * float(i), 1.0), 6.0))
	# RIGHT (gold): mantle the step, run the gorge wall above the falls, kick onto a pillar
	var l1: Dictionary = _ledge(Vector3(3.5, 3.3, -13.0), Vector3(3.0, 6.0, 3.0), "alt")
	_panel(5.8, 4.3, -16.5, -31.0, 6.5)
	var p1: Dictionary = _blk(Vector3(2.8, 3.3, -34.0), 2.0, 2.0)
	var merge: Dictionary = _blk(Vector3(0, 0, -39.8), 12.0, 4.0, "main", 1.0, false)
	_column(_w(Vector3(-3.5, -1.0, -39.8)), 1.4)
	_column(_w(Vector3(3.5, -1.0, -39.8)), 1.4)
	var cp: Dictionary = _cp(Vector3(0, 0, -49.3))
	_lava(Vector3(0, -6.0, -25.0), Vector2(16.0, 50.0), Vector2(0.0, 1.2), 0.35)
	_sign(Vector3(-3.5, 0, -6.6), Color(1.0, 0.3, 0.15))
	_sign(Vector3(3.5, 0, -6.6), LedgeBlock.LIP_COLOR)
	_hop(cp0, fork, Vector3(0, 0, 1.0))
	if route_variant != 1:
		var prev: Dictionary = _area(Vector3(-3.5, 0, -8.0), 1.2, 2.0)
		var nxt: Array[Dictionary] = [a1, a2, a3]
		for i: int in 3:
			var lf: VolcanoLavaFall = falls[i]
			r_walk(_w(_edge(prev, nxt[i]["c"], 0.7)))
			_wait(func() -> bool: return lf.is_clear_between(Game.course_time, 0.1, 0.75))
			_hop(prev, nxt[i])
			prev = nxt[i]
		_hop(a3, merge, Vector3(-3.0, 0, 0.4))
	else:
		r_walk(_w(Vector3(3.5, 0, -8.8)))
		r_mantle(_w(Vector3(3.5, 0, -9.65)), _w(Vector3(3.5, 3.3, -12.6)))
		r_wallrun(_w(Vector3(3.8, 3.3, -14.15)), _w(Vector3(5.2, 4.5, -17.9)), _w(Vector3(5.2, 4.5, -27.0)), _w(p1["c"]))
		_hop(p1, merge, Vector3(0.4, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 7: Basalt Organ - columns rise and sink through the lava in a wave; rams sweep the causeway ----

func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var lava_y: float = -1.5
	_lava(Vector3(0.2, lava_y, -22.0), Vector2(16.0, 34.0), Vector2(0.2, 0.3), 0.5)
	var tops: Array[Vector3] = [Vector3(0, 0.4, -7.6), Vector3(-2.0, 0.9, -13.4), Vector3(0.2, 1.4, -19.2), Vector3(2.2, 1.9, -25.0), Vector3(0.4, 2.4, -30.8)]
	var cols: Array[VolcanoBasalt] = []
	for i: int in tops.size():
		cols.append(_pulse_basalt(tops[i], 4.0, fposmod(-0.25 * float(i), 1.0), tops[i].y - lava_y + 1.0, 0.45))
	var cw: Dictionary = _blk(Vector3(0.4, 2.4, -41.0), 2.2, 9.0, "alt")
	var rams: Array = []
	var leads: Array = []
	for z: float in [-39.0, -43.0]:
		var lead: float = (-37.2 - z) / 9.0 + 0.15
		rams.append(kit.piston(_w(Vector3(3.6, 3.7, z)), Vector3(2.0, 1.3, 1.6), _yaw + 90.0, 3.4, 2.6, fposmod(0.2 - lead / 2.6, 1.0), 10.0))
		leads.append(lead)
		_ram_dress(rams[rams.size() - 1] as Piston)
	var cp: Dictionary = _cp(Vector3(0.4, 2.4, -53.5))
	var prev: Dictionary = cp0
	for i: int in cols.size():
		var nxt: VolcanoBasalt = cols[i]
		var cur: VolcanoBasalt = cols[i - 1] if i > 0 else null
		var nd: Dictionary = {"c": tops[i], "r": 1.2}
		r_walk(_w(_edge(prev, tops[i], 0.6)))
		_wait(func() -> bool: return nxt.is_up_between(Game.course_time, 0.3, 1.25) and (cur == null or cur.is_up_between(Game.course_time, 0.0, 0.25)))
		_hop(prev, nd)
		prev = nd
	_hop(prev, cw, Vector3(0, 0, 3.6))
	r_walk(_w(Vector3(0.4, 2.4, -37.2)))
	r_until(func() -> bool: return _clear(rams, leads, 0.35))
	r_walk(_w(Vector3(0.4, 2.4, -45.2)))
	_hop(cw, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 8: Tephra Rain (BRANCH) - hop the bomb-struck stepping stones, or climb to the obsidian gate ----

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, false)
	_column(_w(Vector3(-3.5, -1.0, -8.0)), 1.4)
	_column(_w(Vector3(3.5, -1.0, -8.0)), 1.4)
	# LEFT (red): three stones and the merge's edge, each struck in turn by a bomb
	var t1: Dictionary = _blk(Vector3(-3.6, 0.4, -14.8), 2.0, 2.0)
	var t2: Dictionary = _blk(Vector3(-5.2, 0.8, -21.0), 1.8, 1.8, "alt")
	var t3: Dictionary = _blk(Vector3(-3.0, 1.2, -27.0), 1.8, 1.8)
	var merge: Dictionary = _blk(Vector3(0, 1.2, -34.0), 12.0, 4.0, "main", 1.0, false)
	_column(_w(Vector3(-3.5, 0.2, -34.0)), 1.4)
	_column(_w(Vector3(3.5, 0.2, -34.0)), 1.4)
	var bombs: Array[VolcanoBomb] = []
	var bc: Array[Vector3] = [Vector3(-3.6, 0.4, -14.8), Vector3(-5.2, 0.8, -21.0), Vector3(-3.0, 1.2, -27.0), Vector3(-3.2, 1.2, -33.2)]
	for i: int in bc.size():
		bombs.append(_bomb(bc[i], 1.1 if i < 3 else 1.6, 2.6, fposmod(0.1 - 0.42 * float(i), 1.0), 1.3))
	# RIGHT (gold): mantle the pillar, hop a sinking column to the knob, dive through the obsidian gate
	var pl: Dictionary = _ledge(Vector3(3.5, 3.3, -13.4), Vector3(2.6, 6.0, 2.6), "alt")
	var sbc := Vector3(4.4, 3.0, -19.2)
	_basalt(sbc, 1.15)
	var kn: Dictionary = _blk(Vector3(3.4, 3.6, -24.8), 2.4, 2.4, "accent")
	var gate: WarpPortal = _gate(Vector3(3.4, 3.6, -25.4), Vector3(1.8, 1.2, -33.0))
	var cp: Dictionary = _cp(Vector3(0, 1.2, -43.0))
	_lava(Vector3(0, -3.0, -21.0), Vector2(18.0, 34.0), Vector2(-0.5, 0.2), 0.5)
	_sign(Vector3(-3.5, 0, -6.6), Color(1.0, 0.3, 0.15))
	_sign(Vector3(3.5, 0, -6.6), WarpPortal.ENTRY_COLOR)
	_hop(cp0, fork, Vector3(0, 0, 1.0))
	if route_variant != 1:
		var stones: Array[Dictionary] = [_area(Vector3(-3.5, 0, -8.0), 1.2, 2.0), t1, t2, t3]
		for i: int in 3:
			var nb: VolcanoBomb = bombs[i]
			var after: VolcanoBomb = bombs[i + 1]
			r_walk(_w(_edge(stones[i], stones[i + 1]["c"], 0.6)))
			_wait(func() -> bool: return _bomb_clear(nb, 0.2, 1.5) and _bomb_clear(after, 0.9, 1.9))
			_hop(stones[i], stones[i + 1])
		r_walk(_w(_edge(t3, Vector3(-2.0, 1.2, -33.4), 0.6)))
		var last: VolcanoBomb = bombs[3]
		_wait(func() -> bool: return _bomb_clear(last, 0.2, 1.6))
		_hop(t3, merge, Vector3(-1.4, 0, 0.6))
		r_walk(_w(Vector3(0, 1.2, -34.4)))
	else:
		r_walk(_w(Vector3(3.5, 0, -8.8)))
		r_mantle(_w(Vector3(3.5, 0, -9.65)), _w(Vector3(3.5, 3.3, -13.2)))
		r_jump(_w(_edge(pl, sbc)), _w(sbc))
		r_jump(_w(sbc + (Vector3(3.4, 0, -24.8) - sbc).normalized() * 0.7), _w(kn["c"]))
		r_portal(_w(Vector3(3.4, 3.6, -25.4)), gate.exit_point())
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Obsidian Chimney - three wall runs zig-zag up a split fissure, mantle out of the last kick ----

func _stage_9() -> Vector3:
	_panel(2.3, 1.2, -6.0, -12.5, 7.0)
	_panel(-2.3, 6.0, -11.0, -19.0, 7.0)
	_panel(2.3, 9.0, -17.0, -25.0, 7.0)
	var top: Dictionary = _ledge(Vector3(-0.75, 11.9, -28.5), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 11.9, -38.0))
	_lava(Vector3(0, -4.0, -16.0), Vector2(12.0, 28.0), Vector2(0.0, -0.4), 0.3)
	r_wallrun(_w(Vector3(0.5, 0, -2.6)), _w(Vector3(1.7, 1.4, -7.1)), _w(Vector3(1.7, 1.4, -10.0)), _w(Vector3(-1.7, 5.5, -13.9)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 5.5, -13.9)), _w(Vector3(-1.7, 5.5, -16.9)), _w(Vector3(1.7, 8.5, -20.5)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 8.5, -20.5)), _w(Vector3(1.7, 8.5, -21.9)), _w(Vector3(-0.75, 11.9, -27.1)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 10: Hammer Ridge - basalt hammers slam on a knife ridge, mantle up under the third ----
##  [shortcut: wall-run the ridge's outer cliff past both hammers, mantle out of the kick]

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var ridge: Dictionary = _blk(Vector3(0, 0, -13.0), 2.2, 16.0, "alt")
	var h1: Crusher = _hammer(Vector3(0, 0, -9.5), Vector3(3.0, 1.6, 3.0), 3.2, 2.8, 0.0)
	var h2: Crusher = _hammer(Vector3(0, 0, -15.5), Vector3(3.0, 1.6, 3.0), 3.2, 2.8, 0.45)
	var lg: Dictionary = _ledge(Vector3(0, 3.3, -25.0), Vector3(3.4, 7.0, 4.0))
	var h3: Crusher = _hammer(Vector3(0, 3.3, -24.4), Vector3(3.4, 1.6, 2.6), 3.0, 2.8, 0.7)
	var s1: Dictionary = _blk(Vector3(2.0, 3.3, -32.6), 1.8, 1.8)
	var cp: Dictionary = _cp(Vector3(0.6, 3.3, -41.4))
	_lava(Vector3(0, -4.0, -22.0), Vector2(16.0, 38.0), Vector2(0.3, 0.3), 0.5)
	# SHORTCUT: the cliff panel along the ridge's outer flank
	_panel(-3.3, 1.2, -7.0, -21.0, 7.0)
	_hop(cp0, ridge, Vector3(0, 0, 6.6))
	if route_variant == 2:
		r_wallrun(_w(Vector3(-0.5, 0, -5.4)), _w(Vector3(-2.7, 1.4, -8.8)), _w(Vector3(-2.7, 1.4, -16.8)), _w(Vector3(0.9, 3.3, -26.2)))
		r_until(func() -> bool: return _open(h3, 0.0, 0.8))
		r_walk(_w(Vector3(1.2, 3.3, -26.6)))
	else:
		r_walk(_w(Vector3(0, 0, -6.4)))
		r_until(func() -> bool: return _open(h1, 0.0, 0.75) and _open(h2, 0.5, 1.45))
		r_walk(_w(Vector3(0, 0, -12.5)))
		r_walk(_w(Vector3(0, 0, -19.6)))
		r_until(func() -> bool: return _open(h3, 0.15, 1.3))
		r_mantle(_w(Vector3(0, 0, -20.65)), _w(Vector3(0, 3.3, -24.4)))
		r_walk(_w(Vector3(0.9, 3.3, -26.4)))
	r_jump(_w(Vector3(1.1, 3.3, -26.65)), _w(s1["c"]))
	_hop(s1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 11: THE MAGMA CHAMBER - drop into a drained magma chamber and out-climb the rising lava ----

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var tide: VolcanoLava = _lava(Vector3(0, -11.5, -31.0), Vector2(16.0, 56.0), Vector2(0.0, 0.25), 0.35)
	tide.rise = 10.8
	tide.period = 16.0
	tide.drain = 2.0
	tide.low = 5.0
	tide.climb = 7.0
	tide.snap_to_clock()
	var d1: Dictionary = _blk(Vector3(0, -3.2, -8.6), 2.4, 2.4)
	var d2: Dictionary = _blk(Vector3(2.2, -6.4, -14.0), 2.2, 2.2, "alt")
	var f1: Dictionary = _blk(Vector3(0.2, -9.0, -19.4), 2.4, 2.4)
	var f2c := Vector3(-1.8, -9.0, -24.6)
	_basalt(f2c, 1.2)
	var f3: Dictionary = _blk(Vector3(0, -8.4, -30.4), 3.4, 3.6, "alt")
	var vent: VolcanoFumarole = _fumarole(Vector3(0, -8.4, -30.8), 9.0, 4.0, 1.0, 0.0)
	var u1: Dictionary = _blk(Vector3(0, -3.4, -37.4), 3.0, 3.0)
	_panel(-2.6, -2.2, -40.0, -52.0, 6.5)
	var u2: Dictionary = _blk(Vector3(0.6, 0.0, -56.6), 2.4, 2.4)
	var ex: Dictionary = _ledge(Vector3(0.6, 3.3, -62.4), Vector3(3.0, 8.0, 3.0), "alt")
	var cp: Dictionary = _cp(Vector3(0.6, 3.3, -71.0))
	_chamber(Vector3(0, -11.5, -31.0), Vector2(16.0, 56.0))
	# go the moment the lava has drained: 5 s of floor, then the tide climbs 1.5 m every second
	r_walk(_w(_edge(cp0, d1["c"], 0.8)))
	_wait(func() -> bool: return tide.offset_at(Game.course_time) < 0.01 and tide.time_until_climb(Game.course_time) > 4.55)
	_hop(cp0, d1)
	_hop(d1, d2)
	_hop(d2, f1)
	r_jump(_w(_edge(f1, f2c)), _w(f2c))
	r_jump(_w(f2c + (Vector3(0, 0, -30.4) - f2c).normalized() * 0.75), _w((f3["c"] as Vector3) + Vector3(0, 0, 0.6)))
	var uy: float = _w(u1["c"]).y
	_fly(_w(Vector3(0, -8.4, -30.8)), func() -> bool: return player.global_position.y > uy + 1.4)
	_fly(_w(u1["c"]))
	r_wallrun(_w(Vector3(-0.4, -3.4, -38.55)), _w(Vector3(-2.0, -2.0, -41.8)), _w(Vector3(-2.0, -2.0, -48.8)), _w(u2["c"]))
	r_mantle(_w(_edge(u2, ex["c"])), _w((ex["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(ex, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	vent.set_meta("chamber", true)
	return cp["c"]


## The magma chamber's walls: a ring of dark basalt cliffs round the tide's footprint (visual only,
## so the camera never snags on them), glowing seams, and vents fuming into the chamber.
func _chamber(c: Vector3, size: Vector2) -> void:
	var rock: StandardMaterial3D = Look.flat(Color(0.1, 0.085, 0.085), 0.9)
	var seam: StandardMaterial3D = Look.flat(Color(1.0, 0.38, 0.08), 0.4, 0.0, 2.2)
	var h: float = 17.0
	for side: float in [-1.0, 1.0]:
		var wall := Look.box(Vector3(2.0, h, size.y), rock)
		wall.position = _w(c + Vector3(side * (size.x * 0.5 + 1.0), h * 0.5 - 3.0, 0))
		wall.rotation.y = deg_to_rad(_yaw)
		add_child(wall)
		for k: int in 5:
			var s := Look.box(Vector3(0.12, 0.35, size.y * 0.9), seam)
			s.position = _w(c + Vector3(side * (size.x * 0.5 - 0.02), 1.5 + float(k) * 2.2, 0))
			s.rotation.y = deg_to_rad(_yaw)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(s)
		VolcanoFx.embers(self, _w(c + Vector3(side * size.x * 0.3, 2.0, 0)), _sz(Vector3(2.0, 1.0, size.y * 0.45)), 30, 2.0)
	var back := Look.box(Vector3(size.x + 4.0, h, 2.0), rock)
	back.position = _w(c + Vector3(0, h * 0.5 - 3.0, -size.y * 0.5 - 1.0))
	back.rotation.y = deg_to_rad(_yaw)
	add_child(back)
	VolcanoFx.smoke(self, _w(c + Vector3(0, 12.0, 0)), 5.0, 18.0, 14, Color(0.22, 0.12, 0.1, 0.45), 5.0)


# ---- stage 12: Flame Gallery - a basalt beam through flame jets, cooling crust that blinks, a vent pad up ----
##  [shortcut: two 1 m spikes beside the blinking crust - no waiting on the cooling]

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var beam: Dictionary = _blk(Vector3(0, 0, -11.5), 1.2, 13.0, "accent", 0.8)
	var jets: Array = []
	var leads: Array = []
	for z: float in [-9.0, -14.0]:
		var lead: float = (-5.6 - z) / 9.0 + 0.15
		jets.append(_flame(Vector3(0, 1.7, z), 3.2, 3.4, 2.4, 0.45, fposmod(0.72 - lead / 2.4, 1.0)))
		leads.append(lead)
	var bl1: BlinkPlatform = kit.blink(_w(Vector3(1.5, 0.6, -22.8)), _sz(Vector3(2.0, 0.5, 2.0)), 3.0, 0.6, 0.0)
	var bl2: BlinkPlatform = kit.blink(_w(Vector3(-0.5, 1.2, -28.4)), _sz(Vector3(2.0, 0.5, 2.0)), 3.0, 0.6, 0.45)
	var p1: Dictionary = _blk(Vector3(0.6, 1.2, -34.4), 2.6, 2.6, "alt")
	kit.pad(_w(Vector3(0.6, 1.2, -34.4)), 18.0, 0.0, _yaw, 1.1)
	var top: Dictionary = _blk(Vector3(0.6, 6.2, -41.2), 2.4, 2.4)
	var cp: Dictionary = _cp(Vector3(0.6, 6.2, -50.2))
	_lava(Vector3(0, -3.0, -24.0), Vector2(16.0, 44.0), Vector2(-0.4, 0.4), 0.5)
	var s1: Dictionary = _spike(Vector3(-1.6, 0.6, -23.0))
	var s2: Dictionary = _spike(Vector3(0.8, 1.0, -28.6))
	_hop(cp0, beam, Vector3(0, 0, 5.6))
	r_walk(_w(Vector3(0, 0, -5.6)))
	r_until(func() -> bool: return _clear(jets, leads, 0.3))
	r_walk(_w(Vector3(0, 0, -17.4)))
	if route_variant == 2:
		r_jump(_w(Vector3(-0.1, 0, -17.65)), _w(s1["c"]))
		_hop(s1, s2)
		_hop(s2, p1)
	else:
		r_until(func() -> bool: return _blink_ok(bl1, 0.35, 1.3) and _blink_ok(bl2, 1.3, 2.3))
		r_jump(_w(Vector3(0, 0, -17.65)), _w(Vector3(1.5, 0.6, -22.8)))
		r_jump(_w(Vector3(1.2, 0.6, -23.5)), _w(Vector3(-0.5, 1.2, -28.4)))
		r_jump(_w(Vector3(-0.3, 1.2, -29.1)), _w(p1["c"]))
	r_pad(_w(Vector3(0.6, 1.2, -34.4)), _w(top["c"]))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 13: Lava River Run (BRANCH) - a boost strip flings you over the river, or ride the rafts and a vent pad ----

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, false)
	_column(_w(Vector3(-3.5, -1.0, -8.0)), 1.4)
	_column(_w(Vector3(3.5, -1.0, -8.0)), 1.4)
	_lava(Vector3(0, -1.0, -28.0), Vector2(18.0, 36.0), Vector2(1.4, 0.0), 0.6)
	# LEFT (cyan): the boost strip and a 15 m leap onto a landing, a sinking column to the bank
	kit.boost(_w(Vector3(-3.5, 0, -15.0)), Vector3(2.4, 0.5, 10.0), _yaw, 20.0)
	_blk(Vector3(-3.5, -0.5, -15.0), 2.8, 10.0, "alt", 0.6)
	var l1: Dictionary = _blk(Vector3(-3.5, -0.2, -35.0), 3.0, 5.0)
	var sbc := Vector3(-1.4, 0.2, -42.6)
	_basalt(sbc, 1.2)
	# RIGHT (gold): two crust rafts, a vent pad over the widest water, a last raft
	var r1c := Vector3(3.5, -0.6, -14.4)
	var r2c := Vector3(4.6, -0.6, -20.0)
	_crust(r1c, 2.2, 2.2)
	_crust(r2c, 2.2, 2.2)
	var pi: Dictionary = _blk(Vector3(3.4, -0.2, -25.8), 2.6, 2.6, "alt")
	kit.pad(_w(Vector3(3.4, -0.2, -25.8)), 17.0, 0.0, _yaw, 1.1)
	var r3c := Vector3(2.8, -0.6, -34.4)
	var r4c := Vector3(1.6, -0.6, -40.8)
	_crust(r3c, 2.4, 2.4)
	_crust(r4c, 2.2, 2.2)
	var merge: Dictionary = _blk(Vector3(0, 0.0, -48.4), 12.0, 4.0, "main", 1.0, false)
	_column(_w(Vector3(-3.5, -1.0, -48.4)), 1.4)
	_column(_w(Vector3(3.5, -1.0, -48.4)), 1.4)
	var cp: Dictionary = _cp(Vector3(0, 0.0, -57.8))
	_sign(Vector3(-3.5, 0, -6.6), Color(0.3, 0.85, 1.0))
	_sign(Vector3(3.5, 0, -6.6), LedgeBlock.LIP_COLOR)
	_hop(cp0, fork, Vector3(0, 0, 1.0))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.6)))
		r_jump(_w(Vector3(-3.5, 0, -19.6)), _w((l1["c"] as Vector3) + Vector3(0, 0, 0.4)))
		route[route.size() - 1]["speed"] = 20.0
		r_walk(_w(Vector3(-3.0, -0.2, -38.0)))
		r_jump(_w(_edge(l1, sbc)), _w(sbc))
		r_jump(_w(sbc + (Vector3(-1.0, 0, -48.4) - sbc).normalized() * 0.75), _w(Vector3(-1.2, 0.0, -48.0)))
	else:
		var r1: Dictionary = _area(r1c, 1.1, 1.1)
		var r2: Dictionary = _area(r2c, 1.1, 1.1)
		var r3: Dictionary = _area(r3c, 1.2, 1.2)
		var r4: Dictionary = _area(r4c, 1.1, 1.1)
		_hop(_area(Vector3(3.5, 0, -8.0), 1.2, 2.0), r1)
		_hop(r1, r2)
		_hop(r2, pi, Vector3(0, 0, 1.2))
		r_pad(_w(Vector3(3.4, -0.2, -25.8)), _w(r3c))
		_hop(r3, r4)
		_hop(r4, merge, Vector3(1.6, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 14: Cinder Chute - a slide of loose cinders launches you over a gap, a vent pad at speed, mantle ----

func _stage_14() -> Vector3:
	kit.slick(_w(Vector3(0, -2.45, -11.0)), Vector3(2.6, 0.5, 16.0), _yaw, -18.0)
	_column(_w(Vector3(0, -5.2, -14.0)), 1.0)
	var l1: Dictionary = _blk(Vector3(0, -7.4, -32.6), 3.0, 7.0, "alt")
	kit.pad(_w(Vector3(0, -7.4, -35.0)), 20.0, 0.0, _yaw, 1.2)
	var top: Dictionary = _ledge(Vector3(0, -0.2, -41.6), Vector3(3.2, 8.0, 3.0))
	var cp: Dictionary = _cp(Vector3(0.4, -0.2, -50.6))
	_lava(Vector3(0, -11.0, -30.0), Vector2(16.0, 44.0), Vector2(0.0, 0.8), 0.4)
	r_walk(_w(Vector3(0, 0, -3.8)))
	r_jump(_w(Vector3(0, -4.85, -18.6)), _w((l1["c"] as Vector3) + Vector3(0, 0, 1.4)))
	route[route.size() - 1]["speed"] = 17.0
	r_pad(_w(Vector3(0, -7.4, -35.0)), _w((top["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 15: Bomb Ridge - a knife ridge under a barrage, a hammer on the next, wall-run the cliff home ----

func _stage_15() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var ridge: Dictionary = _blk(Vector3(0, 0, -12.5), 1.6, 15.0, "alt")
	var bombs: Array = []
	var leads: Array = []
	for z: float in [-8.0, -12.5, -17.0]:
		var lead: float = (-5.4 - z) / 9.0 + 0.1
		bombs.append(_bomb(Vector3(0, 0, z), 1.3, 2.8, fposmod(0.5 - lead / 2.8, 1.0), 1.2))
		leads.append(lead)
	var r2: Dictionary = _blk(Vector3(0.8, 0.8, -27.0), 1.8, 6.0)
	var hm: Crusher = _hammer(Vector3(0.8, 0.8, -27.0), Vector3(2.6, 1.6, 2.6), 3.0, 2.6, 0.3)
	_panel(3.0, 2.0, -33.0, -46.0, 6.5)
	var cp: Dictionary = _cp(Vector3(0.2, 1.6, -54.6))
	_lava(Vector3(0, -3.5, -28.0), Vector2(16.0, 52.0), Vector2(0.5, 0.0), 0.5)
	_hop(cp0, ridge, Vector3(0, 0, 6.3))
	r_walk(_w(Vector3(0, 0, -5.4)))
	r_until(func() -> bool: return _clear(bombs, leads, 0.3))
	r_walk(_w(Vector3(0, 0, -19.6)))
	r_until(func() -> bool: return _open(hm, 0.35, 1.2))
	r_jump(_w(Vector3(0, 0, -19.65)), _w(Vector3(0.8, 0.8, -25.2)))
	r_walk(_w(Vector3(0.8, 0.8, -29.0)))
	r_wallrun(_w(Vector3(1.0, 0.8, -29.65)), _w(Vector3(2.4, 2.2, -33.6)), _w(Vector3(2.4, 2.2, -42.6)), _w((cp["c"] as Vector3) + Vector3(0.4, 0, 1.2)))
	r_checkpoint()
	return cp["c"]


# ---- stage 16: Curtain Run - wall-run behind a lava fall, mantle, two columns breathing in the lava ----
##  [shortcut: the ledge's back wall is a panel too - run it and skip the columns]

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var r1: Dictionary = _blk(Vector3(0, 0, -8.0), 3.0, 4.0, "alt")
	_panel(-2.3, 1.2, -11.5, -27.5, 6.5)
	var fall: VolcanoLavaFall = _lavafall(Vector3(-1.4, 0, -19.5), 3.0, 7.0, 3.2, 0.5, 0.0, 6.0)
	var r2: Dictionary = _blk(Vector3(0.4, 0, -32.5), 3.6, 5.0, "alt")
	var m: Dictionary = _ledge(Vector3(0.4, 3.3, -40.0), Vector3(4.0, 6.0, 3.0))
	var lava_y: float = 0.6
	var k1c := Vector3(-1.0, 3.8, -46.6)
	var k2c := Vector3(1.2, 4.3, -52.4)
	var k1: VolcanoBasalt = _pulse_basalt(k1c, 3.6, 0.0, k1c.y - lava_y + 1.0, 0.5)
	var k2: VolcanoBasalt = _pulse_basalt(k2c, 3.6, -0.3, k2c.y - lava_y + 1.0, 0.5)
	var cp: Dictionary = _cp(Vector3(0.4, 4.3, -61.0))
	_lava(Vector3(0, -4.0, -24.0), Vector2(16.0, 36.0), Vector2(0.0, 0.5), 0.4)
	_lava(Vector3(0.2, lava_y, -50.0), Vector2(10.0, 14.0), Vector2(0.3, 0.0), 0.5)
	_hop(cp0, r1, Vector3(0, 0, 0.8))
	# the curtain crosses the run: leave the plate so you pass it just after it stops
	r_walk(_w(Vector3(-0.3, 0, -8.0)))
	r_until(func() -> bool: return fall.is_clear_between(Game.course_time, 1.0, 1.5, 0.0, 4.5))
	r_wallrun(_w(Vector3(-0.3, 0, -9.65)), _w(Vector3(-1.8, 1.4, -13.6)), _w(Vector3(-1.8, 1.4, -24.5)), _w(r2["c"]))
	r_mantle(_w(Vector3(0.4, 0, -34.6)), _w(Vector3(0.4, 3.3, -39.8)))
	var ka: Dictionary = {"c": k1c, "r": 1.2}
	var kb: Dictionary = {"c": k2c, "r": 1.2}
	r_walk(_w(_edge(m, k1c, 0.6)))
	_wait(func() -> bool: return k1.is_up_between(Game.course_time, 0.3, 1.3) and k2.is_up_between(Game.course_time, 1.2, 2.2))
	_hop(m, ka)
	_hop(ka, kb)
	_hop(kb, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 17: Caldera Steps - fumaroles up the crater's outer wall, bombs on the shelf, a sinking column ----
##  [shortcut: a hidden obsidian gate on a 1 m knob off the checkpoint's corner]

func _stage_17() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var v1f: Dictionary = _blk(Vector3(0, 0, -8.8), 4.0, 5.4, "alt")
	var v1: VolcanoFumarole = _fumarole(Vector3(0, 0, -9.6), 7.6, 3.4, 0.5, 0.2)
	var s1: Dictionary = _blk(Vector3(0, 6.2, -16.0), 3.0, 3.0)
	var sb: VolcanoBomb = _bomb(Vector3(0, 6.2, -16.0), 1.5, 3.4, 0.32, 1.4)
	var h1: Dictionary = _blk(Vector3(-2.2, 6.8, -21.8), 1.8, 1.8, "alt")
	var h2c := Vector3(0.4, 7.4, -27.4)
	_basalt(h2c, 1.15)
	var v2f: Dictionary = _blk(Vector3(0.4, 4.6, -34.0), 3.6, 4.6, "alt")
	var v2: VolcanoFumarole = _fumarole(Vector3(0.4, 4.6, -35.0), 6.0, 3.0, 0.55, 0.5)
	var top: Dictionary = _ledge(Vector3(0.4, 11.6, -38.6), Vector3(4.0, 9.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0.8, 11.6, -48.0))
	_lava(Vector3(0, -3.0, -24.0), Vector2(16.0, 44.0), Vector2(0.0, 0.3), 0.5)
	_lava(Vector3(-0.6, 4.0, -26.0), Vector2(8.0, 10.0), Vector2(0.2, 0.1), 0.45)
	# SHORTCUT: a 1 m knob out past the checkpoint's corner hides an obsidian gate onto the upper shelf
	var kn: Dictionary = _spike(Vector3(6.2, 0.4, -7.0))
	var gate: WarpPortal = _gate(Vector3(6.2, 0.4, -7.0), Vector3(-2.2, 6.8, -20.6))
	if route_variant == 2:
		r_jump(_w(_edge(cp0, kn["c"])), _w(kn["c"]))
		r_portal(_w(Vector3(6.2, 0.4, -7.2)), gate.exit_point())
		r_walk(_w(Vector3(-2.2, 6.8, -21.6)))
	else:
		_hop(cp0, v1f, Vector3(0, 0, 1.4))
		r_walk(_w(Vector3(0, 0, -7.6)))
		_wait(func() -> bool: return _venting(v1, 1.3) and _bomb_clear(sb, 0.6, 2.6))
		var sy: float = _w(s1["c"]).y
		_fly(_w(Vector3(0, 0, -9.6)), func() -> bool: return player.global_position.y > sy + 1.2)
		_fly(_w(s1["c"]))
		_hop(s1, h1)
	r_jump(_w(_edge(h1, h2c)), _w(h2c))
	r_jump(_w(h2c + (Vector3(0.4, 0, -34.0) - h2c).normalized() * 0.7), _w((v2f["c"] as Vector3) + Vector3(0, 0, 1.4)))
	r_walk(_w(Vector3(0.4, 4.6, -33.2)))
	_wait(func() -> bool: return _venting(v2, 1.1))
	_fly(_w((top["c"] as Vector3) + Vector3(0, 0, 0.4)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 18: The Crater Rim - columns breathing in the caldera lake, a lava curtain, the last mantle ----

func _stage_18() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var lava_y: float = -2.0
	_lava(Vector3(0, lava_y, -22.0), Vector2(18.0, 36.0), Vector2(0.0, 0.5), 0.45)
	var tops: Array[Vector3] = [Vector3(0.2, 0.2, -7.8), Vector3(2.2, 0.8, -13.6), Vector3(0.0, 1.4, -19.4)]
	var cols: Array[VolcanoBasalt] = []
	for i: int in tops.size():
		cols.append(_pulse_basalt(tops[i], 3.6, fposmod(-0.28 * float(i), 1.0), tops[i].y - lava_y + 1.0, 0.45))
	var gate_floor: Dictionary = _blk(Vector3(-0.4, 1.4, -26.8), 2.4, 4.4, "alt")
	var fall: VolcanoLavaFall = _lavafall(Vector3(-0.4, 1.4, -30.6), 3.6, 6.0, 2.8, 0.5, 0.25, 5.0)
	var l2: Dictionary = _blk(Vector3(-0.4, 1.4, -34.6), 2.4, 3.6)
	var rim: Dictionary = _ledge(Vector3(-0.4, 4.7, -40.2), Vector3(6.0, 9.0, 3.2), "alt")
	var fin: Dictionary = _blk(Vector3(0, 4.7, -49.5), 12.0, 12.0, "main", 1.6)
	kit.finish(_w(Vector3(0, 4.7, -51.0)), _yaw)
	_finish_pos = _w(Vector3(0, 4.7, -51.0))
	var prev: Dictionary = cp0
	for i: int in cols.size():
		var nxt: VolcanoBasalt = cols[i]
		var cur: VolcanoBasalt = cols[i - 1] if i > 0 else null
		var nd: Dictionary = {"c": tops[i], "r": 1.2}
		r_walk(_w(_edge(prev, tops[i], 0.6)))
		_wait(func() -> bool: return nxt.is_up_between(Game.course_time, 0.3, 1.2) and (cur == null or cur.is_up_between(Game.course_time, 0.0, 0.25)))
		_hop(prev, nd)
		prev = nd
	_hop(prev, gate_floor, Vector3(0, 0, 1.2))
	r_walk(_w(Vector3(-0.4, 1.4, -28.2)))
	r_until(func() -> bool: return fall.is_clear_between(Game.course_time, 0.1, 0.7))
	_hop(gate_floor, l2)
	r_mantle(_w(_edge(l2, rim["c"])), _w((rim["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(rim, fin, Vector3(0, 0, 3.5))
	r_walk(_w(Vector3(0, 4.7, -51.4)))
	return fin["c"]


# ---- themed machines and set pieces --------------------------------------------------------------

## A basalt hammer: a crusher whose press is a bundle of hexagonal basalt columns with a glowing
## underside, turned with the stage so its guide posts flank the path.
func _hammer(c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(c), size, lift, period, phase, _yaw)
	var rock: StandardMaterial3D = Look.flat(Color(0.16, 0.13, 0.13), 0.88)
	var r: float = minf(size.x, size.z) * 0.3
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + 0.4
		var col := Look.cylinder(r, size.y + 0.8 + 0.4 * float(i % 2), rock, Vector3(cos(a) * size.x * 0.26, 0.5, sin(a) * size.z * 0.26), r * 1.05, 6)
		cr.add_child(col)
	return cr


## The press is up (gap >= `head` m) over the whole window [now + a, now + b].
static func _open(cr: Crusher, a: float, b: float, head: float = 2.3) -> bool:
	var s: float = a
	while s <= b:
		if cr.gap_at(Game.course_time + s) < head:
			return false
		s += 0.04
	return true


static func _blink_ok(bp: BlinkPlatform, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not bp.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true

## Wall-run panel along the stage heading at local x, from z0 to z1 (z0 > z1), centred at height y,
## set in a face of glassy obsidian.
func _panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> WallRunPanel:
	var span: float = absf(z0 - z1)
	var p: WallRunPanel = kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(span, height, 0.5), _yaw + 90.0)
	var side: float = signf(x)
	var glass: StandardMaterial3D = Look.flat(Color(0.05, 0.04, 0.06), 0.12, 0.3)
	var slab := Look.box(Vector3(1.2, height + 3.0, span + 1.6), glass)
	slab.position = _w(Vector3(x + side * 0.9, y - 0.8, (z0 + z1) * 0.5))
	slab.rotation.y = deg_to_rad(_yaw)
	add_child(slab)
	return p


## A flame jet: a laser gate whose posts are fissure vents; it roars fire while live.
func _flame(center: Vector3, width: float, height: float, period: float, on: float, phase: float, yaw_extra: float = 0.0) -> LaserGate:
	var g: LaserGate = kit.laser(_w(center), Vector3(width, height, 0.25), period, on, phase, _yaw + yaw_extra)
	# the fissure vents the jet roars out of, crusted with sulphur
	var crust: StandardMaterial3D = Look.flat(Color(0.2, 0.16, 0.12), 0.9)
	var mouth: StandardMaterial3D = Look.flat(Color(1.0, 0.45, 0.1), 0.4, 0.0, 2.5)
	for sx: float in [-1.0, 1.0]:
		var v := Look.cylinder(0.55, 0.6, crust, g.to_global(Vector3(sx * (width * 0.5 + 0.1), -height * 0.5 + 0.1, 0)), 0.35, 8)
		add_child(v)
		add_child(Look.cylinder(0.3, 0.05, mouth, v.position + Vector3(0, 0.31, 0), -1.0, 8))
	# the flame sheet itself: tongues of fire licking up the whole curtain while it is live,
	# a lazy smoulder of sparks while it is not
	var fire: GPUParticles3D = Fx.emitter({"amount": 90, "lifetime": 0.55, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.45, 0.15, 0.08), "dir": Vector3.UP, "spread": 10.0, "speed": Vector2(height * 1.2, height * 1.9),
		"tex": Fx.Tex.SMOKE, "size": 0.9, "scale": Vector2(0.6, 1.3), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-90, 90),
		"colors": PackedColorArray([Color(3.2, 2.2, 0.8, 0.0), Color(3.0, 1.2, 0.25, 0.9), Color(1.2, 0.2, 0.05, 0.0)]),
		"aabb": AABB(Vector3(-width - 2.0, -height, -3.0), Vector3(width * 2.0 + 4.0, height * 3.0, 6.0))})
	fire.position = Vector3(0, -height * 0.5, 0)
	g.add_child(fire)
	var smoulder: GPUParticles3D = Fx.embers({"amount": 14, "lifetime": 1.2, "extents": Vector3(width * 0.45, 0.05, 0.1),
		"speed": Vector2(0.5, 1.6), "color": Color(3.0, 1.0, 0.3), "size": 0.12})
	smoulder.position = Vector3(0, -height * 0.5, 0)
	g.add_child(smoulder)
	_jets.append({"g": g, "fire": fire})
	return g


## Basalt dressing on a piston ram: a hexagonal column riding with it out of the cliff.
func _ram_dress(p: Piston) -> void:
	var col := Look.cylinder(1.0, 1.4, Look.flat(Color(0.18, 0.15, 0.14), 0.88), Vector3(0, 0, 0.1), 1.05, 6)
	col.rotation = Vector3(PI * 0.5, 0, 0)
	p.add_child(col)
	var seam := Look.cylinder(1.06, 0.08, Look.flat(Color(1.0, 0.4, 0.08), 0.4, 0.0, 2.0), Vector3(0, 0, -0.5), -1.0, 6)
	seam.rotation = Vector3(PI * 0.5, 0, 0)
	p.add_child(seam)


## An obsidian gate (portal) at local floor `entry`, exiting at local floor `exit_at` facing the stage heading.
func _gate(entry: Vector3, exit_at: Vector3) -> WarpPortal:
	return kit.portal(_w(entry), _yaw, _w(exit_at), _yaw, 7.0)


## A 1 m obsidian spike top (shortcut footing).
func _spike(top: Vector3) -> Dictionary:
	kit.plat(_w(top), Vector3(1.0, 0.4, 1.0), "accent", 0.0, _yaw)
	_column(_w(top - Vector3(0, 0.4, 0)), 0.45)
	return {"c": top, "hx": 0.5, "hz": 0.5}


## Fork signpost: a banner and a floor strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	kit.banner(_w(p), 3.6, col, _yaw)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.3)), Vector3(1.4, 0.05, 0.2), col, _yaw)


static func _jet_off(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


## Bot: every timed hazard in `gates` is harmless when a runner leaving now reaches it `leads[i]` s from now, +- m.
func _clear(gates: Array, leads: Array, m: float) -> bool:
	var t: float = Game.course_time
	for i: int in gates.size():
		var a: float = t + float(leads[i])
		var s: float = a - m
		while s <= a + m:
			var g: Node = gates[i]
			if g is LaserGate and (g as LaserGate).is_on_at(s):
				return false
			if g is Piston and (g as Piston).extension_at(s) > 0.02:
				return false
			if g is Crusher and not (g as Crusher).is_clear_for(s, 0.0):
				return false
			if g is VolcanoBomb and (g as VolcanoBomb).is_deadly_at(s):
				return false
			if g is VolcanoLavaFall and (g as VolcanoLavaFall).covers_at(s, -0.5, 2.2):
				return false
			s += 0.04
	return true


func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


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
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	_env.sky.sky_material = sky_mat
	_env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	_env.fog_light_color = FOG_COLOR
	_env.fog_density = 0.0042
	_env.fog_aerial_perspective = 0.25
	_env.fog_sky_affect = 0.0
	_env.fog_sun_scatter = 0.0
	_env.fog_height = -20.0
	_env.fog_height_density = 0.004
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = AMBIENT
	_env.ambient_light_energy = 0.62
	_env.tonemap_exposure = 1.1
	_env.glow_intensity = 1.05
	_env.glow_bloom = 0.12
	_env.glow_hdr_threshold = 0.95
	_env.adjustment_saturation = 1.18
	_env.adjustment_contrast = 1.12
	# key light: the eruption's glow from the summit (aimed properly once the summit is placed)
	_sun.light_color = Color(1.0, 0.48, 0.2)
	_sun.light_energy = SUN_ENERGY
	_sun.rotation_degrees = Vector3(-34, 0, 0)
	# fill: cold moonlight through the ash from behind the climb
	_fill.light_color = Color(0.42, 0.44, 0.9)
	_fill.light_energy = FILL_ENERGY
	_fill.rotation_degrees = Vector3(-55, 160, 0)


# ---- the world round the course -------------------------------------------------------------------

const FOG_COLOR := Color(0.12, 0.04, 0.03)
const AMBIENT := Color(0.58, 0.28, 0.22)
const SUN_ENERGY: float = 1.35
const FILL_ENERGY: float = 0.32
const CRATER_R: float = 75.0

var peak: VolcanoPeak
var deco: VolcanoDecor
## Flame jets: {"g": LaserGate, "fire": GPUParticles3D} - the fire sheet runs while the jet is live.
var _jets: Array[Dictionary] = []
var _ember_rain: GPUParticles3D
var _lightning_kick: float = 0.0
var _surge_kick: float = 0.0


## Every point the route passes (takeoffs, landings, walk targets, checkpoints).
func _route_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for st: Dictionary in route:
		for key: String in ["from", "to", "entry", "exit", "top"]:
			if st.has(key) and st[key] is Vector3 and (st[key] as Vector3) != Vector3.ZERO:
				pts.append(st[key])
	for p: Vector3 in _cp_world:
		pts.append(p)
	pts.append(_finish_pos)
	return pts


func _clear_of(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist:
			return false
	return true


## The route height nearest to world XZ `p` (for placing decor relative to the course).
func _course_y(p: Vector3, pts: Array[Vector3]) -> float:
	var best: float = INF
	var y: float = 0.0
	for q: Vector3 in pts:
		var d: float = Vector2(p.x - q.x, p.z - q.z).length_squared()
		if d < best:
			best = d
			y = q.y
	return y


func _surroundings() -> void:
	var pts: Array[Vector3] = _route_points()
	deco = VolcanoDecor.new(self, kit.rng)
	# the summit crater lies just past the finish terrace (stage 18's frame is still current)
	var crater: Vector3 = _w(Vector3(0, 0, -55.5 - 6.0 - CRATER_R))
	var rim: float = _finish_pos.y - 3.0
	peak = VolcanoPeak.make(self, crater, rim, CRATER_R, pts, _finish_pos - crater)
	peak.lightning.connect(_on_lightning)
	peak.surged.connect(_on_surge)
	# aim the key light from the glowing summit down across the course
	var mid := Vector3.ZERO
	for p: Vector3 in _cp_world:
		mid += p
	mid /= float(maxi(_cp_world.size(), 1))
	var dir: Vector3 = Vector3(mid.x - crater.x, 0, mid.z - crater.z).normalized()
	dir = (dir * cos(deg_to_rad(34.0)) + Vector3.DOWN * sin(deg_to_rad(34.0))).normalized()
	_sun.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), _sun.global_position)
	var sky: ShaderMaterial = _env.sky.sky_material as ShaderMaterial
	var to_summit: Vector3 = (crater - mid).normalized()
	sky.set_shader_parameter("volcano_dir", to_summit)
	# the sister volcano smoking on the horizon, off the summit's shoulder
	var side: Vector3 = Vector3(-to_summit.z, 0, to_summit.x)
	deco.sister(crater + to_summit * 900.0 + side * 1500.0 + Vector3(0, -260.0, 0), 620.0, 820.0)
	_course_decor(pts)
	_ambient_layers()
	_ember_rain = Fx.emitter({"amount": 260, "lifetime": 3.2, "emitting": false, "shape": "box", "extents": Vector3(24, 1, 24),
		"dir": Vector3(0.15, -1, 0.1), "spread": 12.0, "speed": Vector2(3.0, 7.0), "gravity": Vector3(0, -3.0, 0),
		"turbulence": 1.2, "tex": Fx.Tex.DOT, "size": 0.2, "scale": Vector2(0.5, 1.3),
		"colors": PackedColorArray([Color(3.4, 1.6, 0.4, 0.0), Color(3.2, 1.2, 0.3, 1.0), Color(1.4, 0.3, 0.05, 0.0)]),
		"aabb": AABB(Vector3(-40, -60, -40), Vector3(80, 80, 80))})
	_ember_rain.top_level = true
	add_child(_ember_rain)


## Basalt organs, obsidian blades, charred snags, sulphur vents, lava cliffs and boulders placed
## round the route, never on it, and never tall enough in front of a checkpoint to block the view.
func _course_decor(pts: Array[Vector3]) -> void:
	var rng: RandomNumberGenerator = kit.rng
	var anchors: Array[Vector3] = [Vector3.ZERO]
	anchors.append_array(_cp_world)
	anchors.append(_finish_pos)
	for i: int in anchors.size() - 1:
		var a: Vector3 = anchors[i]
		var b: Vector3 = anchors[i + 1]
		var along: Vector3 = Vector3(b.x - a.x, 0, b.z - a.z)
		var len_ab: float = along.length()
		along = along / maxf(len_ab, 0.01)
		var across := Vector3(-along.z, 0, along.x)
		# basalt organs flanking the stage, well out to the sides
		for k: int in 3:
			var p: Vector3 = a.lerp(b, rng.randf()) + across * (rng.randf_range(15.0, 28.0) * (-1.0 if rng.randf() < 0.5 else 1.0))
			if _clear_of(p, pts, 12.0):
				var cy: float = _course_y(p, pts)
				deco.organ(Vector3(p.x, cy - 30.0, p.z), cy + rng.randf_range(-6.0, 5.0), rng.randf_range(2.5, 5.0), rng.randi_range(5, 9))
		# small pieces a bit nearer: obsidian, snags, boulders, sulphur vents (on organ-top ledges)
		for k: int in 5:
			var p2: Vector3 = a.lerp(b, rng.randf()) + across * (rng.randf_range(9.0, 18.0) * (-1.0 if rng.randf() < 0.5 else 1.0))
			if not _clear_of(p2, pts, 8.0):
				continue
			var cy2: float = _course_y(p2, pts) - rng.randf_range(1.0, 5.0)
			deco.organ(Vector3(p2.x, cy2 - 30.0, p2.z), cy2, 1.6, 3)
			match k % 4:
				0:
					deco.obsidian(Vector3(p2.x, cy2, p2.z), rng.randf_range(0.8, 1.4))
				1:
					deco.snag(Vector3(p2.x, cy2, p2.z), rng.randf_range(0.8, 1.2))
				2:
					deco.boulders(Vector3(p2.x, cy2, p2.z), rng.randf_range(0.8, 1.4))
				_:
					deco.sulphur_vent(Vector3(p2.x, cy2, p2.z))
		# every few stages a lava fall pours off a cliff beside the climb
		if i % 3 == 1:
			var s: float = -1.0 if i % 2 == 0 else 1.0
			var foot: Vector3 = a.lerp(b, 0.5) + across * s * 34.0
			if _clear_of(foot, pts, 22.0):
				var fy: float = _course_y(foot, pts) - 14.0
				deco.lava_cliff(Vector3(foot.x, fy, foot.z), rng.randf_range(22.0, 34.0), rng.randf_range(4.0, 7.0), -across * s)
		# a slow smoke layer drifting below the course
		var sm: GPUParticles3D = VolcanoFx.smoke(self, a.lerp(b, 0.5) + Vector3(0, -22.0, 0), 16.0, 14.0, 6, Color(0.16, 0.09, 0.08, 0.5), 18.0)
		(sm.process_material as ParticleProcessMaterial).gravity = VolcanoPeak.WIND * 0.8
	# the trailhead: a gateway of basalt organs and a cairn line out of the start
	deco.organ(Vector3(-9.0, -30.0, -4.0), 5.5, 2.4, 7)
	deco.organ(Vector3(9.5, -30.0, -2.0), 6.5, 2.6, 8)
	deco.snag(Vector3(-5.8, 0, 5.4), 1.2)
	deco.sulphur_vent(Vector3(5.6, 0, 4.8))
	deco.obsidian(Vector3(-5.9, 0, -5.2), 0.9)


## Two layered ambient systems round every stage: ash sifting down and embers climbing, plus
## hot glints hanging in the air; and heat haze over every lava pool the level made.
func _ambient_layers() -> void:
	var anchors: Array[Vector3] = [Vector3.ZERO]
	anchors.append_array(_cp_world)
	anchors.append(_finish_pos)
	for i: int in anchors.size() - 1:
		var a: Vector3 = anchors[i]
		var b: Vector3 = anchors[i + 1]
		var c: Vector3 = (a + b) * 0.5 + Vector3(0, 6.0, 0)
		var ext := Vector3(absf(b.x - a.x) * 0.5 + 16.0, 11.0, absf(b.z - a.z) * 0.5 + 16.0)
		VolcanoFx.ash(self, c + Vector3(0, 4.0, 0), ext, 60)
		VolcanoFx.embers(self, c + Vector3(0, -8.0, 0), ext * Vector3(0.8, 0.4, 0.8), 45, 2.2)
		add_child(_glints(c, ext))
	for l: Node in find_children("*", "VolcanoLava", true, false):
		var lava := l as VolcanoLava
		if lava.rise <= 0.0 and lava.size.x * lava.size.y < 900.0:
			VolcanoFx.haze(lava, Vector3(0, 0.1, 0), minf(lava.size.x, 12.0), 5.0, 0.004)


func _glints(c: Vector3, ext: Vector3) -> GPUParticles3D:
	var g: GPUParticles3D = Fx.emitter({"amount": 24, "lifetime": 4.0, "preprocess": 4.0, "shape": "box", "extents": ext * 0.8,
		"speed": Vector2(0.05, 0.3), "spread": 180.0, "tex": Fx.Tex.STAR, "size": 0.35, "curve": "pop",
		"color": Color(3.0, 1.6, 0.6), "aabb": AABB(-ext - Vector3.ONE * 4.0, ext * 2.0 + Vector3.ONE * 8.0)})
	g.position = c
	return g


# ---- live effects: flame jets, lightning and surges answered by the sky, the finish ----------------------

func _process(dt: float) -> void:
	var t: float = Game.course_time
	for j: Dictionary in _jets:
		var on: bool = (j["g"] as LaserGate).is_on_at(t)
		var fire: GPUParticles3D = j["fire"]
		if fire.emitting != on:
			fire.emitting = on
	if _env == null or peak == null:
		return
	_lightning_kick = maxf(_lightning_kick - dt * 5.0, 0.0)
	_surge_kick = maxf(_surge_kick - dt * 0.45, 0.0)
	var surge: float = maxf(peak.surge_at(t), _surge_kick)
	_fill.light_energy = FILL_ENERGY + 1.6 * _lightning_kick
	_fill.light_color = Color(0.42, 0.44, 0.9).lerp(Color(0.8, 0.82, 1.0), _lightning_kick)
	_sun.light_energy = SUN_ENERGY + 1.4 * surge
	_env.ambient_light_energy = 0.62 + 0.35 * surge + 0.4 * _lightning_kick
	_env.fog_light_color = FOG_COLOR.lerp(Color(0.32, 0.09, 0.04), surge * 0.7)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and _ember_rain != null:
		_ember_rain.global_position = cam.global_position + Vector3(0, 16.0, 0) - cam.global_basis.z * 8.0
		var rain: bool = surge > 0.25
		if _ember_rain.emitting != rain:
			_ember_rain.emitting = rain


func _on_lightning(_pos: Vector3, strength: float) -> void:
	_lightning_kick = maxf(_lightning_kick, strength)


func _on_surge(strength: float) -> void:
	_surge_kick = maxf(_surge_kick, minf(strength, 1.0))


## The crater rim goes off: the fountain surges, a fountain of fire and embers bursts over the
## terrace and the whole mountain flares.
func _finish_sequence() -> void:
	if peak != null:
		peak.force_surge()
	for i: int in 3:
		var f: GPUParticles3D = VolcanoFx.fountain(self, _finish_pos + Vector3(float(i - 1) * 2.5, 0.5, 0), 90, 14.0 + 2.0 * float(i))
		f.restart()
	var s: GPUParticles3D = VolcanoFx.sparks(self, _finish_pos + Vector3(0, 2.0, 0), 70, 12.0)
	s.restart()
	Fx.flash(self, _finish_pos + Vector3(0, 3.0, 0), Color(1.0, 0.55, 0.2), 8.0, 22.0, 1.4)
	await get_tree().create_timer(0.9).timeout


## Swap every walkable surface to the volcanic rock shader (same colours and trims).
func _volcano_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = ROCK_SHADER
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r
