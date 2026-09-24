extends LevelBase
## 6. ORBITAL DRIFT - a space station in low orbit above a night-side ocean planet. 18 stages that
## loop round the station's hub (a spinning habitat wheel, solar wings, radiators); black sky,
## hard sunlight, planetshine, and dust / ion glints / micrometeor streaks everywhere.
##
##  1 arrival        deck hops and a cargo-tug ferry                      [shortcut: antenna masts]
##  2 low-g bay      floaty 10-12 m leaps over drifting debris (OrbitalGravityBay)
##  3 solar wing     a gap crossed only along a solar panel, a second wall run onto a plate
##  4 cargo hold     up a belt dragging you back, mantle a container, mantle the tall one
##  5 airlock        FORK: laser corridor on a green wave | container climb (two mantles)
##  6 hydraulics     side rams sweep the catwalk, then the catapult ram hurls you 11 m
##  7 thruster shaft launch grates (OrbitalThruster) blast you up two decks, a side jet across the gap
##  8 compactor      three presses out of step, mantle a ledge under the last press
##                                                                      [shortcut: hull panel run]
##  9 flare deck     SET PIECE: a solar-flare front (OrbitalFlare) sweeps the deck; shelter behind
##                   the shield walls, dash pocket to pocket and out through the flare gate
## 10 junction       FORK: blinking plates + ram catwalk | hull wall run, mantle, teleporter skip
## 11 carousels      board two spinning habitat hubs, ride and leap off (second turns the other way)
## 12 pulse bay      the gravity field cycles: one floaty leap per pulse, longer each time
## 13 solar mast     chimney of three solar wings (run, kick, run, kick, run) and mantle the cap
## 14 cargo line     FORK: container stacks + a press | mass-driver boost into an 18 m/s wall run
## 15 laser lattice  beam walk, airlock laser, blinking plates, two lasers + a side jet on one beat
##                                                                      [shortcut: relay pillars]
## 16 reactor stacks three 3.3 m mantles under scanning lasers, then a ram catwalk
##                                                                      [shortcut: shield wall run]
## 17 reactor hall   low-g hall round the white-hot core: float, grate lift, wall run, low-g kick
## 18 final approach the last flare deck over crumbling plates, through the docking ring to the finish
##
## Route variants (tests): 0 = main forks, 1 = the alternative at every fork, 2 = alternatives plus
## the four shortcuts. Own pieces: mechanics/orbital_{gravity_bay,thruster,flare}.gd,
## visual/orbital_{sky,fx,station,blink}.gd.

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _tuning: MovementTuning
var _sparks: Array[GPUParticles3D] = []
var _spark_next: Array[float] = []
## World midpoint and end of every stage (ambient particle layers are hung around them).
var _mids: Array[Vector3] = []
var _ends: Array[Vector3] = []
## Course-clock bursts: {"p": GPUParticles3D, "period": float, "offset": float, "last": int}
var _clock_fx: Array[Dictionary] = []
## Press slam sparks: {"c": Crusher, "p": GPUParticles3D, "gap": float}
var _slams: Array[Dictionary] = []
## Arrival bursts that fire when the player comes within 2.5 m: {"at": Vector3, "p": GPUParticles3D, "cool": float}
var _arrivals: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "orbital"
	music_track = "b"
	kill_y = -80.0
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


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## Station deck plate (no floating-island keel): walkable box + a dark sub-frame and a glow strip under it.
func _deck(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.6) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	var under := Look.box(Vector3(sx * 0.78, 0.35, sz * 0.78), Look.flat(Look.c("decor"), 0.6, 0.5))
	under.position = _w(c + Vector3(0, -thick - 0.17, 0))
	under.rotation.y = deg_to_rad(_yaw)
	add_child(under)
	if sx >= 1.5 and sz >= 1.5:
		var strip := Look.box(Vector3(sx * 0.5, 0.06, 0.08), Look.flat(Look.c("accent2"), 0.4, 0.0, 2.5))
		strip.position = _w(c + Vector3(0, -thick - 0.36, 0))
		strip.rotation.y = deg_to_rad(_yaw)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.6) -> Dictionary:
	kit.disc(_w(c), r, thick, style, 0.0)
	var under := Look.cylinder(r * 0.7, 0.4, Look.flat(Look.c("decor"), 0.6, 0.5), _w(c + Vector3(0, -thick - 0.2, 0)), r * 0.4, 16)
	add_child(under)
	return {"c": c, "r": r}


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


## A floaty jump inside a low-g bay: a jump step the reach validator skips (normal-gravity reach does not apply).
func _float(a: Dictionary, b: Dictionary, off: Vector3 = Vector3.ZERO) -> void:
	var to: Vector3 = (b["c"] as Vector3) + off
	route.append({"kind": "b_jump", "from": _w(_edge(a, to)), "to": _w(to), "hold": true})


func _haz(c: Vector3, size: Vector3, yaw_extra: float = 0.0) -> void:
	kit.hazard(_w(c), size, _yaw + yaw_extra)


## Checkpoint dock: a 6 x 6 deck with nav beacons; the checkpoint faces local yaw `cp_yaw`.
func _dock(c: Vector3, cp_yaw: float = 0.0, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _deck(c, size, size, "main", 1.0)
	kit.checkpoint(_w(c), _yaw + cp_yaw)
	var h: float = size * 0.5 - 0.35
	for corner: Vector2 in [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]:
		_beacon(c + Vector3(corner.x, 0, corner.y), corner.x < 0.0)
	# a truss mast down into the dark so docks read as bolted to the station
	_truss_v(c + Vector3(0, -1.4, 0), 18.0)
	return d


## Antenna mast: a 1 m square top on a thin lattice mast (shortcut footing), with a red tip light.
func _mast(top: Vector3) -> Dictionary:
	kit.plat(_w(top), Vector3(1.0, 0.3, 1.0), "alt", 0.0, _yaw)
	_truss_v(top + Vector3(0, -0.3, 0), 16.0, 0.5)
	var lamp := Look.sphere(0.1, Look.flat(Color(1.0, 0.25, 0.2), 0.3, 0.0, 4.0), _w(top + Vector3(0.4, 0.2, 0.4)))
	lamp.set_script(preload("res://visual/orbital_blink.gd"))
	lamp.set("period", 1.1)
	add_child(lamp)
	return {"c": top, "hx": 0.5, "hz": 0.5}


## Nav beacon: a short post with a red (port) or green (starboard) blinking light.
func _beacon(p: Vector3, port: bool) -> void:
	var col: Color = Color(1.0, 0.2, 0.15) if port else Color(0.2, 1.0, 0.45)
	var n := Node3D.new()
	n.add_child(Look.cylinder(0.05, 0.5, Look.flat(Look.c("metal"), 0.4, 0.7), Vector3(0, 0.25, 0), -1.0, 6))
	var lamp := Look.sphere(0.09, Look.flat(col, 0.3, 0.0, 4.0), Vector3(0, 0.55, 0))
	lamp.set_script(preload("res://visual/orbital_blink.gd"))
	lamp.set("period", 1.6 if port else 1.3)
	n.add_child(lamp)
	n.position = _w(p)
	add_child(n)


## Vertical open truss (4 rails + cross braces) hanging down from `top`.
func _truss_v(top: Vector3, length: float, w: float = 0.9) -> void:
	var n := Node3D.new()
	var rail: StandardMaterial3D = Look.flat(Look.c("metal").darkened(0.35), 0.45, 0.8)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			n.add_child(Look.box(Vector3(0.1, length, 0.1), rail, Vector3(sx * w * 0.5, -length * 0.5, sz * w * 0.5)))
	var k: int = int(length / 1.6)
	for i: int in k:
		var y: float = -0.8 - float(i) * 1.6
		n.add_child(Look.box(Vector3(w, 0.07, 0.07), rail, Vector3(0, y, w * 0.5 * (1.0 if i % 2 == 0 else -1.0))))
		n.add_child(Look.box(Vector3(0.07, 0.07, w), rail, Vector3(w * 0.5 * (1.0 if i % 2 == 0 else -1.0), y - 0.8, 0)))
	n.position = _w(top)
	n.rotation.y = deg_to_rad(_yaw)
	add_child(n)


# ---- the course --------------------------------------------------------------------------------

func _build() -> void:
	# themed air at three depths around the camera (visual only)
	add_child(Ambience.make(theme_id))
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	_frame(Vector3.ZERO, 0.0)
	var cp: Vector3 = _stage_1_arrival()
	_mark(cp)
	_frame(_w(cp), 0.0)
	cp = _stage_2_lowg()
	_mark(cp)
	_frame(_w(cp), -90.0 + _yaw)
	cp = _stage_3_solar()
	_mark(cp)
	_frame(_w(cp), -90.0 + _yaw)
	cp = _stage_4_cargo()
	_mark(cp)
	_frame(_w(cp), -90.0 + _yaw)
	cp = _stage_5_airlock()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_6_hydraulics()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_7_thrusters()
	_mark(cp)
	_frame(_w(cp), _yaw - 90.0)
	cp = _stage_8_compactor()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_9_flare()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_10_junction()
	_mark(cp)
	_frame(_w(cp), _yaw - 90.0)
	cp = _stage_11_carousel()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_12_pulse()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_13_mast()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_14_cargo_line()
	_mark(cp)
	_frame(_w(cp), _yaw - 90.0)
	cp = _stage_15_lattice()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_16_stacks()
	_mark(cp)
	_frame(_w(cp), _yaw)
	cp = _stage_17_reactor()
	_mark(cp)
	_frame(_w(cp), _yaw)
	_stage_18_approach()
	_decor()


func _mark(cp_local: Vector3) -> void:
	_mids.append((_o + _w(cp_local)) * 0.5)
	_ends.append(_w(cp_local))


func _process(dt: float) -> void:
	var t: float = Game.course_time
	for e: Dictionary in _clock_fx:
		var k: int = int(floor((t + float(e["offset"])) / float(e["period"])))
		if k != int(e["last"]):
			e["last"] = k
			(e["p"] as GPUParticles3D).restart()
	for e: Dictionary in _slams:
		var g: float = (e["c"] as Crusher).gap_at(t)
		if g < 0.05 and float(e["gap"]) >= 0.05:
			(e["p"] as GPUParticles3D).restart()
		e["gap"] = g
	if player != null:
		for e: Dictionary in _arrivals:
			e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
			if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
				e["cool"] = 3.0
				(e["p"] as GPUParticles3D).restart()
	# sparking cables: each spark emitter fires on its own pseudo-random clock
	for i: int in _sparks.size():
		if t >= _spark_next[i]:
			_sparks[i].restart()
			_spark_next[i] = t + 0.6 + fposmod(sin(float(i) * 12.9898 + floor(t) * 78.233) * 43758.5453, 1.0) * 2.4
		elif _spark_next[i] - t > 4.0:
			_spark_next[i] = t


# Stage 1: arrival - warm-up hops across deck plates and a cargo tug ferry.
func _stage_1_arrival() -> Vector3:
	var start: Dictionary = _deck(Vector3.ZERO, 12.0, 12.0, "main", 1.0)
	var a1: Dictionary = _deck(Vector3(0, 0, -11.4), 2.4, 2.4)
	var a2: Dictionary = _deck(Vector3(3.0, 1.0, -17.2), 2.2, 2.2, "alt")
	var a3: Dictionary = _deck(Vector3(0, 2.0, -22.8), 2.0, 2.0)
	var a4: Dictionary = _deck(Vector3(-2.4, 2.0, -28.8), 1.8, 1.8, "alt")
	var tug: MovingPlatform = kit.mover(_w(Vector3(0, 2.0, -36.0)), Vector3(2.6, 0.5, 2.6), [Vector3.ZERO, _d(Vector3(0, 0, -8.0))], 5.0)
	var end: Dictionary = _dock(Vector3(0, 2.0, -52.0))
	_hop(start, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	_hop(a3, a4)
	# SHORTCUT: three antenna masts beside the tug lane (1 m tops, 85-90% jumps) - no waiting for the tug
	var m1: Dictionary = _mast(Vector3(-2.8, 2.4, -34.9))
	var m2: Dictionary = _mast(Vector3(-2.8, 2.8, -40.9))
	var m3: Dictionary = _mast(Vector3(-2.2, 2.4, -46.0))
	if route_variant == 2:
		_hop(a4, m1)
		_hop(m1, m2)
		_hop(m2, m3)
		_hop(m3, end, Vector3(0, 0, 1.6))
	else:
		r_wait(tug, _w(Vector3(0, 1.75, -36.0)), 0.5)
		r_jump_onto(_w(_edge(a4, Vector3(0, 2.0, -36.0))), tug, Vector3(0, 0.25, 0))
		r_jump_from_ride(tug, _w(Vector3(0, 1.75, -44.0)), 0.4, _w(Vector3(0, 2.0, -50.5)))
	r_checkpoint()
	return end["c"]


# Stage 2: the low-g bay - floaty leaps no normal jump could make (10-12 m, and 3 m UP), over debris.
func _stage_2_lowg() -> Vector3:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_bay(Vector3(0, 3.0, -25.95), Vector3(18.0, 22.0, 45.1))
	var g1: Dictionary = _deck(Vector3(0, 0, -14.5), 3.0, 3.0)
	var g2: Dictionary = _deck(Vector3(-3.5, 3.0, -26.0), 2.4, 2.4, "alt")
	var g3: Dictionary = _deck(Vector3(2.5, 5.0, -36.5), 2.2, 2.2)
	var end: Dictionary = _dock(Vector3(2.5, 5.0, -51.85), -90.0)
	# drifting debris hanging low in each gap: only a full floaty arc clears it
	_haz(Vector3(-1.8, 1.2, -20.5), Vector3(1.4, 1.0, 1.4), 20.0)
	_haz(Vector3(-0.4, 3.9, -31.0), Vector3(1.2, 1.2, 1.2), 45.0)
	_haz(Vector3(2.5, 5.8, -43.5), Vector3(1.6, 0.8, 1.2), -15.0)
	_float(dock, g1)
	_float(g1, g2)
	_float(g2, g3)
	_float(g3, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	return end["c"]


func _bay(c: Vector3, size: Vector3, period: float = 0.0, on_fraction: float = 0.6, phase: float = 0.0) -> OrbitalGravityBay:
	var bay := OrbitalGravityBay.new()
	bay.size = size
	bay.period = period
	bay.on_fraction = on_fraction
	bay.phase = phase
	bay.position = _w(c)
	bay.rotation.y = deg_to_rad(_yaw)
	add_child(bay)
	return bay


# Stage 3: the solar wing - a gap only a wall run along the solar array crosses, then a second
# run on the other side that kicks you onto a 2.6 m plate.
func _stage_3_solar() -> Vector3:
	kit.wallrun(_w(Vector3(2.0, 1.2, -13.0)), Vector3(14.0, 6.0, 0.5), _yaw + 90.0)
	var l1: Dictionary = _deck(Vector3(-1.0, 0, -25.0), 5.0, 6.0, "alt")
	kit.wallrun(_w(Vector3(-3.5, 1.2, -35.25)), Vector3(13.5, 6.0, 0.5), _yaw + 90.0)
	var l2: Dictionary = _deck(Vector3(1.5, 0, -46.5), 2.6, 2.6)
	var end: Dictionary = _dock(Vector3(1.5, 0, -56.0), -90.0)
	r_wallrun(_w(Vector3(0.3, 0, -2.6)), _w(Vector3(1.6, 1.2, -7.0)), _w(Vector3(1.6, 1.2, -17.0)), _w(Vector3(-1.0, 0, -24.0)))
	r_wallrun(_w(Vector3(-2.0, 0, -27.6)), _w(Vector3(-3.1, 1.2, -31.5)), _w(Vector3(-3.1, 1.2, -39.5)), _w(l2["c"]))
	_hop(l2, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	return end["c"]


# Stage 4: the cargo hold - run up a belt that drags you back, mantle a container, hop the stack,
# mantle the tall one.
func _stage_4_cargo() -> Vector3:
	kit.conveyor(_w(Vector3(0, 0, -9.3)), Vector3(3.0, 0.3, 12.0), _yaw + 180.0, 4.5)
	_deck(Vector3(0, -0.3, -9.3), 3.4, 12.4, "alt", 0.6)
	var c1: LedgeBlock = kit.ledge(_w(Vector3(0, 3.3, -18.3)), Vector3(3.0, 5.0, 6.0), _yaw, "alt")
	var c1a: Dictionary = _area(Vector3(0, 3.3, -18.3), 1.5, 3.0)
	var c2: Dictionary = _deck(Vector3(2.8, 3.3, -26.2), 4.4, 2.2)
	kit.ledge(_w(Vector3(2.8, 6.8, -33.6)), Vector3(3.0, 7.0, 5.0), _yaw, "main")
	var c3a: Dictionary = _area(Vector3(2.8, 6.8, -33.6), 1.5, 2.5)
	var end: Dictionary = _dock(Vector3(2.8, 6.8, -43.9), -90.0)
	r_walk(_w(Vector3(0, 0, -6.0)))
	r_mantle(_w(Vector3(0, 0, -13.7)), _w(Vector3(0, 3.3, -16.2)))
	r_walk(_w(Vector3(0, 3.3, -19.5)))
	_hop(c1a, c2)
	r_mantle(_w(Vector3(2.8, 3.3, -26.8)), _w(Vector3(2.8, 6.8, -31.8)))
	_hop(c3a, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	c1.set_meta("cargo", true)
	return end["c"]


# Stage 5: the airlock - FORK. Left: the airlock corridor, four laser doors on a green-wave rhythm
# over two pits. Right: climb the cargo stacks over it all (two mantles, crate hops).
func _stage_5_airlock() -> Vector3:
	var end: Dictionary = _dock(Vector3(0, 0, -42.0), 0.0)
	# -- laser corridor (route 0) --
	var s1: Dictionary = _deck(Vector3(-3.5, 0, -9.75), 3.0, 8.5)
	var s2: Dictionary = _deck(Vector3(-3.5, 0, -19.15), 3.0, 4.7)
	var s3: Dictionary = _deck(Vector3(-3.5, 0, -30.5), 3.0, 11.0)
	var gz: Array[float] = [-11.0, -19.0, -23.2, -29.5]
	var gates: Array = []
	var leads: Array = []
	for z: float in gz:
		var lead: float = (-7.0 - z) / 9.0 + 0.15
		var g: LaserGate = kit.laser(_w(Vector3(-3.5, 1.6, z)), Vector3(3.4, 3.2, 0.2), 2.4, 0.55, fposmod(0.775 - lead / 2.4, 1.0), _yaw)
		gates.append(g)
		leads.append(lead)
	# -- container climb (route 1) --
	kit.ledge(_w(Vector3(2.5, 3.3, -7.0)), Vector3(3.0, 5.0, 5.6), _yaw, "alt")
	var k1: Dictionary = _area(Vector3(2.5, 3.3, -7.0), 1.5, 2.8)
	var k2: Dictionary = _deck(Vector3(4.4, 3.3, -14.8), 1.8, 1.8)
	var k3: Dictionary = _deck(Vector3(2.0, 3.3, -21.25), 2.0, 4.5, "alt")
	kit.ledge(_w(Vector3(3.0, 6.5, -29.5)), Vector3(3.0, 7.0, 4.0), _yaw, "main")
	var k4: Dictionary = _area(Vector3(3.0, 6.5, -29.5), 1.5, 2.0)
	var k5: Dictionary = _deck(Vector3(1.0, 3.5, -37.0), 1.6, 1.6)
	# signposts at the fork: red for the lasers, gold for the climb
	kit.glow_strip(_w(Vector3(-2.2, 0.03, -2.8)), Vector3(1.6, 0.05, 0.2), Color(1.0, 0.25, 0.15), _yaw)
	kit.glow_strip(_w(Vector3(2.4, 0.03, -2.8)), Vector3(1.6, 0.05, 0.2), LedgeBlock.LIP_COLOR, _yaw)
	kit.banner(_w(Vector3(-2.6, 0, -2.6)), 3.6, Color(1.0, 0.3, 0.2), _yaw)
	kit.banner(_w(Vector3(2.6, 0, -2.6)), 3.6, LedgeBlock.LIP_COLOR, _yaw)
	if route_variant == 0:
		r_jump(_w(Vector3(-2.4, 0, -2.65)), _w(Vector3(-3.5, 0, -7.0)))
		r_walk(_w(Vector3(-3.5, 0, -7.0)))
		r_until(func() -> bool: return _clear(gates, leads, 0.3))
		r_jump(_w(Vector3(-3.5, 0, -13.65)), _w(Vector3(-3.5, 0, -18.0)))
		r_jump(_w(Vector3(-3.5, 0, -21.15)), _w(Vector3(-3.5, 0, -26.5)))
		r_walk(_w(Vector3(-3.5, 0, -34.0)))
		_hop(s3, end, Vector3(-1.5, 0, 1.5))
	else:
		r_mantle(_w(Vector3(2.5, 0, -2.7)), _w(Vector3(2.5, 3.3, -5.4)))
		_hop(k1, k2)
		_hop(k2, k3)
		r_mantle(_w(Vector3(2.4, 3.3, -23.2)), _w(Vector3(3.0, 6.5, -28.3)))
		_hop(k4, k5)
		_hop(k5, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	s1.clear()
	s2.clear()
	return end["c"]


## Bot: every timed hazard in `gates` (LaserGate / Piston / Crusher) is harmless when a runner leaving
## now reaches it `leads[i]` seconds from now, +- m.
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
			if g is OrbitalThruster and (g as OrbitalThruster).is_firing_at(s):
				return false
			s += 0.04
	return true


# Stage 6: the hydraulic deck - two side rams sweep the catwalk (pass between punches), then stand
# in front of the catapult ram ON PURPOSE: it hurls you 11 m across the gap to the lower deck.
func _stage_6_hydraulics() -> Vector3:
	var walk: Dictionary = _deck(Vector3(0, 0, -12.4), 2.2, 18.2)
	var rams: Array = []
	var leads: Array = []
	for z: float in [-8.5, -14.5]:
		var lead: float = (-3.6 - z) / 9.0 + 0.15
		rams.append(kit.piston(_w(Vector3(2.0, 1.6, z)), Vector3(2.2, 1.6, 1.6), _yaw + 90.0, 2.6, 2.6, fposmod(0.2 - lead / 2.6, 1.0), 13.0))
		leads.append(lead)
	var pad: Dictionary = _deck(Vector3(-0.5, 0, -25.5), 5.0, 7.0, "alt")
	var cat: Piston = kit.piston(_w(Vector3(1.8, 2.0, -25.5)), Vector3(3.0, 2.0, 1.6), _yaw + 90.0, 1.8, 3.0, 0.0, 13.0)
	var ld: Dictionary = _deck(Vector3(-11.0, -3.0, -25.5), 4.0, 4.0)
	var q: Dictionary = _deck(Vector3(-17.5, -2.5, -25.5), 1.8, 1.8, "alt")
	var end: Dictionary = _dock(Vector3(-26.0, -2.5, -25.5), 0.0)
	kit.glow_strip(_w(Vector3(0.55, 0.03, -25.5)), Vector3(0.9, 0.05, 0.9), Color(1.0, 0.72, 0.1), _yaw)
	r_walk(_w(Vector3(0, 0, -3.6)))
	r_until(func() -> bool: return _clear(rams, leads, 0.35))
	r_walk(_w(Vector3(0, 0, -22.0)))
	r_walk(_w(Vector3(0.55, 0, -25.5)))
	route.append({"kind": "kick", "from": _w(Vector3(0.55, 0, -25.5)), "to": _w(ld["c"])})
	_hop(ld, q)
	_hop(q, end, Vector3(1.6, 0, 0))
	r_checkpoint()
	walk.clear()
	pad.clear()
	cat.set_meta("catapult", true)
	return end["c"]


## RCS thruster at local `p`, blasting along local direction `dir`.
func _thruster(p: Vector3, dir: Vector3, length: float, width: float, period: float, on_fraction: float, phase: float, push: float = 80.0, max_along: float = 14.0) -> OrbitalThruster:
	var th := OrbitalThruster.new()
	th.length = length
	th.width = width
	th.period = period
	th.on_fraction = on_fraction
	th.phase = phase
	th.push = push
	th.max_along = max_along
	th.nozzle_radius = minf(width * 0.4, 1.0)
	var y: Vector3 = _d(dir).normalized()
	var x: Vector3 = Vector3.UP.cross(y)
	if x.length() < 0.01:
		x = _d(Vector3.RIGHT)
	x = x.normalized()
	th.transform = Transform3D(Basis(x, y, x.cross(y)), _w(p))
	add_child(th)
	return th


## Launch grate: a slotted deck plate with an upward thruster under it. Standing on it while it
## burns blasts you up the shaft.
func _grate(c: Vector3, size: float, length: float, period: float, on_fraction: float, phase: float, max_along: float = 14.0) -> OrbitalThruster:
	kit.plat(_w(c), Vector3(size, 0.3, size), "alt", 0.0, _yaw)
	for i: int in 4:
		var slot := Look.box(Vector3(size * 0.8, 0.02, 0.12), Look.flat(Color(1.0, 0.55, 0.15), 0.4, 0.0, 1.6))
		slot.position = _w(c + Vector3(0, 0.005, -size * 0.3 + float(i) * size * 0.2))
		slot.rotation.y = deg_to_rad(_yaw)
		slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slot)
	# frame ring round the grate (hazard stripes) so it reads as a launch pad
	kit.glow_strip(_w(c + Vector3(0, 0.02, size * 0.5 - 0.1)), Vector3(size, 0.05, 0.14), Color(1.0, 0.72, 0.1), _yaw)
	kit.glow_strip(_w(c + Vector3(0, 0.02, -size * 0.5 + 0.1)), Vector3(size, 0.05, 0.14), Color(1.0, 0.72, 0.1), _yaw)
	return _thruster(c + Vector3(0, -1.3, 0), Vector3.UP, length + 1.3, size * 0.9, period, on_fraction, phase, 80.0, max_along)


## Bot: ride a launch grate - wait on it for the burn, hold still over it while it lifts us past
## `clear_y` (local), then steer onto `to`.
func _r_lift(th: OrbitalThruster, grate: Vector3, clear_y: float, to: Vector3, lead: float = 0.0) -> void:
	r_walk(_w(grate))
	r_until(func() -> bool: return th.time_until_fire(Game.course_time) <= 0.08 + lead)
	var gy: float = _w(Vector3(0, clear_y, 0)).y
	route.append({"kind": "a_fly", "to": _w(grate), "until": func() -> bool: return player.global_position.y > gy})
	route.append({"kind": "a_fly", "to": _w(to)})


# Stage 7: the thruster shaft - launch grates blast you up to the next deck when their jets fire;
# between them a side jet sweeps the gap (jump in its quiet window).
func _stage_7_thrusters() -> Vector3:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var g1c: Vector3 = Vector3(0, 0, -8.5)
	var g1: OrbitalThruster = _grate(g1c, 3.0, 6.0, 3.0, 0.4, 0.0)
	var u1: Dictionary = _deck(Vector3(0, 7.0, -14.5), 3.0, 3.0)
	var u2: Dictionary = _deck(Vector3(-1.2, 7.0, -21.2), 2.2, 2.2, "alt")
	var blast: OrbitalThruster = _thruster(Vector3(4.5, 7.8, -17.9), Vector3.LEFT, 9.0, 2.2, 2.4, 0.45, 0.3, 90.0, 12.0)
	var g2c: Vector3 = Vector3(0, 7.0, -27.5)
	var g2: OrbitalThruster = _grate(g2c, 3.0, 6.0, 3.0, 0.4, 0.5)
	var u3: Dictionary = _deck(Vector3(0, 14.0, -33.5), 3.0, 3.0)
	var end: Dictionary = _dock(Vector3(0, 14.0, -42.5), -90.0)
	_hop(dock, _area(g1c, 1.5, 1.5))
	_r_lift(g1, g1c, 4.0, (u1["c"] as Vector3))
	r_walk(_w(_edge(u1, u2["c"], 0.6)))
	r_until(func() -> bool: return _clear([blast], [0.35], 0.3))
	_hop(u1, u2)
	_hop(u2, _area(g2c, 1.5, 1.5))
	_r_lift(g2, g2c, 11.0, (u3["c"] as Vector3))
	_hop(u3, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	return end["c"]


## Crusher whose guide columns stand across the local heading (kit.crusher puts them on world X,
## which would block a course running along X). Square presses only.
func _press(floor_top: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var c := Crusher.new()
	c.size = size
	c.lift = lift
	c.period = period
	c.phase = phase
	c.position = _w(floor_top)
	add_child(c)
	var h: float = lift + size.y + 1.5
	for sx: float in [-1.0, 1.0]:
		kit.block(_w(floor_top + Vector3(sx * (size.x * 0.5 + 0.35), h * 0.5, 0)), Vector3(0.35, h, 0.35), Look.c("metal"), true, _yaw)
	kit.block(_w(floor_top + Vector3(0, h + 0.2, 0)), Vector3(size.x + 1.1, 0.4, 0.6), Look.c("metal"), false, _yaw)
	return c


## The reactor core: a white-hot sphere in a cage of containment rings, plasma motes orbiting it,
## arcs of sparks and a pulsing light (its kill volume sits just inside the glow).
func _reactor_core(c: Vector3) -> void:
	var w: Vector3 = _w(c)
	add_child(Look.sphere(2.05, Look.flat(Color(0.75, 0.95, 1.0), 0.2, 0.0, 6.0), w))
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.18)
	var halo := Look.sphere(3.0, halo_mat, w)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	for i: int in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 3.3 + float(i) * 0.5
		ring.outer_radius = 3.5 + float(i) * 0.5
		ring.rings = 48
		ring.ring_segments = 6
		var holder := Node3D.new()
		holder.set_script(preload("res://visual/spin.gd"))
		holder.set("period", 5.0 + float(i) * 2.0)
		holder.set("axis", Vector3(0.3 * float(i), 1.0, 0.2).normalized())
		holder.position = w
		holder.rotation = Vector3(0.6 * float(i), 0.4, 0.9 - 0.5 * float(i))
		holder.add_child(Look.mesh_node(ring, Look.flat(Color(0.6, 0.64, 0.72), 0.4, 0.8)))
		add_child(holder)
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.85, 1.0)
	light.light_energy = 3.0
	light.omni_range = 16.0
	light.position = w
	add_child(light)
	OrbitalFx.swirl(self, w + Vector3(0, -1.5, 0), 3.4, Color(0.5, 0.9, 1.0), 60)
	OrbitalFx.glints(self, w, Vector3(4.0, 4.0, 4.0), 24, Color(0.7, 0.95, 1.0))
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var sp: GPUParticles3D = OrbitalFx.sparks(self, w + Vector3(cos(a), 0.3, sin(a)) * 2.2, Vector3(cos(a), 0.4, sin(a)), 18, Color(0.6, 0.9, 1.0), 6.0)
		_sparks.append(sp)
		_spark_next.append(float(i) * 0.5)


## Sparks spraying off the floor round a press every time it slams (course clock).
func _slam_fx(c: Crusher, floor_top: Vector3) -> void:
	var p: GPUParticles3D = OrbitalFx.sparks(self, _w(floor_top + Vector3(0, 0.1, 0)), Vector3.UP, 36, Color(1.0, 0.7, 0.3), 8.0)
	(p.process_material as ParticleProcessMaterial).spread = 80.0
	(p.process_material as ParticleProcessMaterial).flatness = 0.7
	_slams.append({"c": c, "p": p, "gap": c.gap_at(Game.course_time)})


## A burst of motes that fires when the player arrives at local point `at` (portal exits).
func _arrival_fx(at: Vector3, col: Color) -> void:
	var p: GPUParticles3D = OrbitalFx.burst(self, _w(at + Vector3(0, 1.0, 0)), col, 60, 7.0, 0.28)
	_arrivals.append({"at": _w(at), "p": p, "cool": 0.0})
	OrbitalFx.swirl(self, _w(at + Vector3(0, 0.1, 0)), 1.4, col, 24)


## Bot: a crusher leaves at least `head` m of room (and is harmless) from `a` to `b` seconds from now.
func _under_ok(c: Crusher, a: float, b: float, head: float = 2.3) -> bool:
	var t: float = Game.course_time
	var s: float = t + a
	while s <= t + b:
		if c.gap_at(s) < head or not c.is_clear_for(s, 0.0):
			return false
		s += 0.04
	return true


# Stage 8: the compactor line - a catwalk under three waste presses slamming out of step (dash
# from gap to gap), then a cargo ledge you must mantle while the last press is up.
func _stage_8_compactor() -> Vector3:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var w1: Dictionary = _deck(Vector3(0, 0, -16.0), 2.4, 22.0)
	var presses: Array[Crusher] = []
	var zs: Array[float] = [-9.5, -15.5, -21.5]
	for i: int in zs.size():
		presses.append(kit.crusher(_w(Vector3(0, 0, zs[i])), Vector3(3.0, 1.6, 3.0), 3.4, 2.8, 0.3 * float(i)))
		_slam_fx(presses[i], Vector3(0, 0, zs[i]))
	kit.ledge(_w(Vector3(0, 3.3, -30.5)), Vector3(3.0, 5.0, 4.0), _yaw, "alt")
	var l1: Dictionary = _area(Vector3(0, 3.3, -30.5), 1.5, 2.0)
	var c4: Crusher = kit.crusher(_w(Vector3(0, 3.3, -30.5)), Vector3(3.4, 1.6, 4.4), 3.2, 3.4, 0.55)
	_slam_fx(c4, Vector3(0, 3.3, -30.5))
	var end: Dictionary = _dock(Vector3(0, 3.3, -40.0), 0.0)
	# SHORTCUT: the hull panel beside the last press - run it past press and ledge, kick onto the dock
	kit.wallrun(_w(Vector3(-3.4, 1.5, -30.5)), Vector3(14.0, 7.0, 0.5), _yaw + 90.0)
	_hop(dock, w1, Vector3(0, 0, 9.5))
	# wait in each gap between presses, dash under the next one while it is up
	var waits: Array[float] = [-6.8, -12.75, -18.5, -24.8]
	for i: int in presses.size():
		r_walk(_w(Vector3(0, 0, waits[i])))
		var c: Crusher = presses[i]
		r_until(func() -> bool: return _under_ok(c, 0.0, 0.75))
		r_walk(_w(Vector3(0, 0, waits[i + 1])))
	if route_variant == 2:
		r_wallrun(_w(Vector3(-0.8, 0, -25.0)), _w(Vector3(-2.7, 1.4, -29.0)), _w(Vector3(-2.7, 1.4, -34.5)), _w(Vector3(0.5, 3.3, -40.0)))
	else:
		r_walk(_w(Vector3(0, 0, -26.4)))
		r_until(func() -> bool: return _under_ok(c4, 0.15, 1.6))
		r_mantle(_w(Vector3(0, 0, -26.7)), _w(Vector3(0, 3.3, -29.3)))
		_hop(l1, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	return end["c"]


## Shield wall with its sheltered pocket behind it (toward +Z local), registered with the flare.
## `c` is the pocket's floor centre, `w` its width; the wall stands on the pocket's -Z side.
func _shelter(f: OrbitalFlare, c: Vector3, w: float = 2.4, depth: float = 2.4) -> void:
	var wall_c: Vector3 = c + Vector3(0, 1.75, -depth * 0.5 - 0.25)
	kit.block(_w(wall_c), Vector3(w + 0.2, 3.5, 0.5), Look.c("side"), true, _yaw)
	# armour ribs and a hazard-striped cap on the gate side
	for i: int in 3:
		var rib := Look.box(Vector3(0.12, 3.3, 0.12), Look.flat(Look.c("metal"), 0.4, 0.8))
		rib.position = _w(wall_c + Vector3(-w * 0.35 + float(i) * w * 0.35, 0, -0.3))
		rib.rotation.y = deg_to_rad(_yaw)
		add_child(rib)
	kit.glow_strip(_w(wall_c + Vector3(0, 1.78, 0)), Vector3(w + 0.2, 0.06, 0.52), OrbitalFlare.FLARE_COLOR, _yaw)
	# the glowing floor plate that marks the pocket
	kit.glow_strip(_w(c + Vector3(0, 0.02, 0)), Vector3(w - 0.3, 0.04, depth - 0.3), Color(0.3, 0.85, 1.0), _yaw)
	var local_c: Vector3 = f.to_local(_w(c + Vector3(0, 1.7, 0)))
	f.add_shelter(local_c, Vector3(w, 3.6, depth))


## Bot: a runner sheltered at flare-local z `lz_from` may leave for `lz_to` (closer to the flare
## gate) and arrive there `need` s from now: the front has gone past us and will not reach lz_to in time.
func _flare_go(f: OrbitalFlare, lz_from: float, lz_to: float, need: float) -> bool:
	var t: float = Game.course_time
	var fz: float = f.front_z_at(t)
	if not is_nan(fz) and fz < minf(lz_from, f.length * 0.5) + 1.2:
		return false
	return f.time_until_front_at(t, lz_to) > need


# Stage 9: the flare deck - a solar flare front sweeps down the exposed deck from the flare gate
# every few seconds. Shelter behind the shield walls (glowing plates) as it passes, then dash for
# the next pocket, and out through the gate itself.
func _stage_9_flare() -> Vector3:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f := OrbitalFlare.new()
	f.width = 12.0
	f.height = 9.0
	f.length = 40.0
	f.period = 5.0
	f.sweep = 1.6
	f.phase = 0.0
	f.position = _w(Vector3(0, 0, -26.0))
	f.rotation.y = deg_to_rad(_yaw)
	add_child(f)
	var d1: Dictionary = _deck(Vector3(0, 0, -8.5), 4.0, 7.0)
	_shelter(f, Vector3(-0.8, 0, -10.3))
	var b1: Dictionary = _deck(Vector3(1.2, 0, -16.6), 2.0, 2.0, "alt")
	var b2: Dictionary = _deck(Vector3(-0.4, 0.8, -21.8), 2.0, 2.0)
	var d2: Dictionary = _deck(Vector3(0, 0.8, -28.5), 4.0, 6.0)
	_shelter(f, Vector3(-0.8, 0.8, -29.8))
	var b3: Dictionary = _deck(Vector3(1.0, 0.8, -36.2), 2.0, 2.0, "alt")
	var b4: Dictionary = _deck(Vector3(0, 0.8, -42.5), 2.2, 2.2)
	var end: Dictionary = _dock(Vector3(0, 0.8, -51.0), 0.0)
	# leg 1: dock -> first pocket
	r_until(func() -> bool: return _flare_go(f, 26.0, 15.7, 2.2))
	_hop(dock, d1, Vector3(0, 0, 2.0))
	r_walk(_w(Vector3(-0.8, 0, -10.2)))
	# leg 2: pocket 1 -> pocket 2 (three hops)
	r_until(func() -> bool: return _flare_go(f, 15.7, -3.8, 3.6))
	r_walk(_w(Vector3(1.2, 0, -10.6)))
	r_jump(_w(Vector3(1.2, 0, -11.65)), _w(b1["c"]))
	_hop(b1, b2)
	_hop(b2, d2, Vector3(0.9, 0, 1.2))
	r_walk(_w(Vector3(-0.8, 0.8, -29.7)))
	# leg 3: pocket 2 -> out through the gate
	r_until(func() -> bool: return _flare_go(f, -3.8, -22.0, 3.4))
	r_walk(_w(Vector3(1.2, 0.8, -30.0)))
	r_jump(_w(Vector3(1.2, 0.8, -31.15)), _w(b3["c"]))
	_hop(b3, b4)
	_hop(b4, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	d1.clear()
	d2.clear()
	return end["c"]


## Bot: blink platform `b` is solid for the whole window [a, b2] s from now.
func _blink_ok(b: BlinkPlatform, a: float, b2: float) -> bool:
	var t: float = Game.course_time
	var s: float = t + a
	while s <= t + b2:
		if not b.is_on_at(s):
			return false
		s += 0.05
	return true


## Fork signpost: a banner and a floor arrow strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	kit.banner(_w(p), 3.6, col, _yaw)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.3)), Vector3(1.4, 0.05, 0.2), col, _yaw)


# Stage 10: the teleporter junction - FORK. Left (red): the maintenance gauntlet, two blinking
# plates then a catwalk swept by rams. Right (gold): run the hull panel, mantle the relay
# container and dive through the teleporter that puts you past the rams.
func _stage_10_junction() -> Vector3:
	var end: Dictionary = _dock(Vector3(0, 0, -44.0), -90.0, 8.0)
	# -- gauntlet (route 0) --
	var a1: BlinkPlatform = kit.blink(_w(Vector3(-3.0, 0, -8.0)), Vector3(2.2, 0.4, 2.2), 3.2, 0.65, 0.0)
	var a2: BlinkPlatform = kit.blink(_w(Vector3(-3.0, 0.6, -13.8)), Vector3(2.2, 0.4, 2.2), 3.2, 0.65, 0.7)
	var cw: Dictionary = _deck(Vector3(-3.0, 0.6, -24.0), 2.2, 14.0)
	var a3: Dictionary = _deck(Vector3(-2.5, 0.6, -35.6), 2.0, 2.0, "alt")
	var rams: Array = []
	var leads: Array = []
	for z: float in [-21.0, -27.0]:
		var lead: float = (-17.6 - z) / 9.0 + 0.15
		rams.append(kit.piston(_w(Vector3(-5.0, 2.2, z)), Vector3(2.2, 1.6, 1.6), _yaw - 90.0, 2.6, 2.6, fposmod(0.25 - lead / 2.6, 1.0), 13.0))
		leads.append(lead)
	# -- teleporter (route 1) --
	kit.wallrun(_w(Vector3(5.0, 1.2, -13.0)), Vector3(16.0, 6.0, 0.5), _yaw + 90.0)
	var p1: Dictionary = _deck(Vector3(2.8, 0, -26.2), 3.0, 4.0, "alt")
	kit.ledge(_w(Vector3(2.8, 3.3, -31.5)), Vector3(3.0, 5.0, 4.0), _yaw, "main")
	kit.portal(_w(Vector3(2.8, 3.3, -32.6)), _yaw, _w(Vector3(-3.0, 0.6, -29.4)), _yaw, 7.0)
	_arrival_fx(Vector3(-3.0, 0.6, -30.3), WarpPortal.EXIT_COLOR)
	OrbitalFx.swirl(self, _w(Vector3(2.8, 3.4, -32.6)), 1.6, WarpPortal.ENTRY_COLOR, 26)
	_sign(Vector3(-2.2, 0, -2.4), Color(1.0, 0.3, 0.2))
	_sign(Vector3(2.2, 0, -2.4), WarpPortal.ENTRY_COLOR)
	if route_variant == 0:
		r_until(func() -> bool: return _blink_ok(a1, 0.3, 1.1) and _blink_ok(a2, 1.3, 2.3))
		r_jump(_w(Vector3(-2.6, 0, -2.65)), _w(Vector3(-3.0, 0, -8.0)))
		r_jump(_w(Vector3(-3.0, 0, -8.8)), _w(Vector3(-3.0, 0.6, -13.8)))
		r_jump(_w(Vector3(-3.0, 0.6, -14.6)), _w(Vector3(-3.0, 0.6, -18.2)))
		r_walk(_w(Vector3(-3.0, 0.6, -17.6)))
		r_until(func() -> bool: return _clear(rams, leads, 0.35))
		r_walk(_w(Vector3(-3.0, 0.6, -30.0)))
		_hop(cw, a3)
		_hop(a3, end, Vector3(-1.0, 0, 2.0))
	else:
		r_wallrun(_w(Vector3(2.0, 0, -2.6)), _w(Vector3(4.4, 1.2, -7.5)), _w(Vector3(4.4, 1.2, -17.5)), _w(p1["c"]))
		r_mantle(_w(Vector3(2.8, 0, -27.9)), _w(Vector3(2.8, 3.3, -30.3)))
		r_portal(_w(Vector3(2.8, 3.3, -33.2)), _w(Vector3(-3.0, 0.6, -30.3)))
		_hop(cw, a3)
		_hop(a3, end, Vector3(-1.0, 0, 2.0))
	r_checkpoint()
	return end["c"]


## Habitat carousel: a spinning four-arm hub (arms 3.5-8.5 m out) dressed as habitat modules.
func _carousel(hub: Vector3, period: float, phase: float) -> RotatingPlatform:
	var arms: Array[Dictionary] = [
		{"pos": Vector3(6.0, 0, 0), "size": Vector3(5.0, 0.5, 2.6)}, {"pos": Vector3(-6.0, 0, 0), "size": Vector3(5.0, 0.5, 2.6)},
		{"pos": Vector3(0, 0, 6.0), "size": Vector3(2.6, 0.5, 5.0)}, {"pos": Vector3(0, 0, -6.0), "size": Vector3(2.6, 0.5, 5.0)},
	]
	var table: RotatingPlatform = kit.spinner(_w(hub), period, arms, 2.2, phase, 0.5)
	var hull: StandardMaterial3D = Look.flat(Look.c("top"), 0.45, 0.35)
	var win: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.55), 0.3, 0.0, 3.0)
	for a: Dictionary in arms:
		var ap: Vector3 = a["pos"]
		var radial: Vector3 = ap.normalized()
		# the habitat module slung under each arm, with a lit window band
		var mod := Look.cylinder(1.1, 4.4, hull, ap + Vector3(0, -1.5, 0), -1.0, 14)
		mod.rotation = Vector3(0, 0, PI * 0.5) if absf(radial.x) > 0.5 else Vector3(PI * 0.5, 0, 0)
		table.add_child(mod)
		var band := Look.box(Vector3(4.2, 0.18, 2.3) if absf(radial.x) > 0.5 else Vector3(2.3, 0.18, 4.2), win, ap + Vector3(0, -1.45, 0))
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		table.add_child(band)
		# tip beacon
		var tip := Look.sphere(0.14, Look.flat(Color(0.3, 1.0, 0.5), 0.3, 0.0, 4.0), radial * 8.3 + Vector3(0, 0.4, 0))
		table.add_child(tip)
	# the spindle it turns on, down into the station
	add_child(Look.cylinder(0.9, 30.0, Look.flat(Look.c("decor"), 0.5, 0.6), _w(hub + Vector3(0, -15.5, 0)), 0.9, 12))
	var core := Look.sphere(1.3, Look.flat(Color(0.4, 0.8, 1.0), 0.3, 0.0, 3.0), _w(hub + Vector3(0, -2.2, 0)))
	add_child(core)
	return table


## Bot: board carousel `c` from `from` onto an arm tip passing `board`, ride it round and jump off
## toward `to` once our bearing from the hub is `lo`..`hi` degrees short of the exit line.
func _r_carousel(c: RotatingPlatform, hub: Vector3, from: Vector3, board: Vector3, to: Vector3, lo: float, hi: float) -> void:
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


# Stage 11: the habitat carousels - two spinning habitat hubs. Board an arm as it swings past,
# ride it round and leap off at the far side (mind the sideways fling), twice, the second one
# turning the other way.
func _stage_11_carousel() -> Vector3:
	var c1h: Vector3 = Vector3(0, 0, -13.0)
	var c1: RotatingPlatform = _carousel(c1h, 7.0, 0.0)
	var m: Dictionary = _deck(Vector3(0, 0.5, -26.0), 2.6, 2.6, "alt")
	var c2h: Vector3 = Vector3(0, 0.5, -38.5)
	var c2: RotatingPlatform = _carousel(c2h, -6.0, 0.1)
	var end: Dictionary = _dock(Vector3(0, 0.5, -52.5), 0.0)
	_r_carousel(c1, c1h, Vector3(0, 0, -2.7), Vector3(0, 0, -6.0), m["c"], 8.0, 22.0)
	_r_carousel(c2, c2h, Vector3(0, 0.5, -27.0), Vector3(0, 0.5, -32.0), end["c"] + Vector3(0, 0, 1.6), 8.0, 22.0)
	r_checkpoint()
	return end["c"]


## Bot: the bay's field stays on for the next `dur` s.
func _bay_ok(b: OrbitalGravityBay, dur: float) -> bool:
	return b.time_until_off(Game.course_time) > dur


# Stage 12: the pulse bay - the gravity plating here cycles: while the field hums violet a jump
# floats 10 m and more, when it flickers and dies you drop like a stone. One leap per pulse,
# each longer than the last, the final one rising to the exit.
func _stage_12_pulse() -> Vector3:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var bay: OrbitalGravityBay = _bay(Vector3(0, 4.0, -24.5), Vector3(14.0, 20.0, 41.0), 3.2, 0.62, 0.0)
	var p1: Dictionary = _deck(Vector3(0, 0, -13.2), 2.4, 2.4)
	var p2: Dictionary = _deck(Vector3(2.6, 1.0, -24.2), 2.2, 2.2, "alt")
	var p3: Dictionary = _deck(Vector3(-1.0, 1.0, -35.0), 2.0, 2.0)
	var end: Dictionary = _dock(Vector3(0, 3.5, -48.0), 0.0)
	# drifting debris low in each gap: only a full floating arc clears it
	_haz(Vector3(0, 0.6, -8.5), Vector3(1.6, 1.2, 1.2), 25.0)
	_haz(Vector3(1.4, 1.4, -19.0), Vector3(1.4, 1.0, 1.4), -30.0)
	_haz(Vector3(0.6, 1.8, -29.8), Vector3(1.8, 0.9, 1.2), 10.0)
	_haz(Vector3(-0.5, 3.0, -41.2), Vector3(1.6, 1.0, 1.4), 40.0)
	for pair: Array in [[dock, p1, Vector3.ZERO], [p1, p2, Vector3.ZERO], [p2, p3, Vector3.ZERO], [p3, end, Vector3(0, 0, 1.6)]]:
		var a: Dictionary = pair[0]
		var b: Dictionary = pair[1]
		r_walk(_w(_edge(a, (b["c"] as Vector3) + (pair[2] as Vector3), 0.9)))
		r_until(func() -> bool: return _bay_ok(bay, 1.7))
		_float(a, b, pair[2])
	r_checkpoint()
	return end["c"]


## Solar-array wall-run panel along the stage heading: centre line `x`, from z0 to z1 (z0 > z1).
## Dressed as a solar wing: blue cell grid on the outer face, a truss boom below.
func _solar_wall(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> WallRunPanel:
	var len: float = absf(z0 - z1)
	var mid: float = (z0 + z1) * 0.5
	var w: WallRunPanel = kit.wallrun(_w(Vector3(x, y, mid)), Vector3(len, height, 0.5), _yaw + 90.0)
	var side: float = signf(x)
	var cells: StandardMaterial3D = Look.flat(Color(0.10, 0.18, 0.42), 0.15, 0.6)
	var grid: StandardMaterial3D = Look.flat(Color(0.55, 0.62, 0.75), 0.4, 0.8)
	var back := Look.box(Vector3(0.08, height - 0.4, len - 0.4), cells)
	back.position = _w(Vector3(x + side * 0.3, y, mid))
	back.rotation.y = deg_to_rad(_yaw)
	add_child(back)
	var rows: int = int(height / 1.2)
	for i: int in rows:
		var bar := Look.box(Vector3(0.1, 0.05, len - 0.4), grid)
		bar.position = _w(Vector3(x + side * 0.35, y - height * 0.5 + 0.6 + float(i) * 1.2, mid))
		bar.rotation.y = deg_to_rad(_yaw)
		add_child(bar)
	_truss_v(Vector3(x + side * 0.6, y - height * 0.5, mid), 20.0, 0.7)
	return w


# Stage 13: the solar mast - two strut hops, then a chimney of three solar wings: run, kick across,
# run, kick, run, and mantle out of the last kick onto the mast cap.
func _stage_13_mast() -> Vector3:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var s1: Dictionary = _deck(Vector3(0.8, 0, -8.6), 1.8, 1.8, "alt")
	var s2: Dictionary = _deck(Vector3(-0.4, 0.8, -14.4), 1.8, 1.8)
	var st: Dictionary = _deck(Vector3(0, 0.8, -19.5), 3.0, 3.0)
	var z: float = -21.0
	_solar_wall(2.4, 2.0, z - 1.0, z - 10.5)
	_solar_wall(-2.4, 6.8, z - 8.5, z - 16.5)
	_solar_wall(2.4, 9.8, z - 14.5, z - 22.5)
	kit.ledge(_w(Vector3(-0.75, 12.7, z - 26.0)), Vector3(4.5, 6.0, 4.0), _yaw, "alt")
	var cap: Dictionary = _area(Vector3(-0.75, 12.7, z - 26.0), 2.25, 2.0)
	var end: Dictionary = _dock(Vector3(0, 12.7, z - 36.0), 0.0)
	_hop(dock, s1)
	_hop(s1, s2)
	_hop(s2, st)
	r_wallrun(_w(Vector3(0.6, 0.8, z - 0.1)), _w(Vector3(1.8, 2.2, z - 4.6)), _w(Vector3(1.8, 2.2, z - 7.5)), _w(Vector3(-1.8, 6.3, z - 11.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.8, 6.3, z - 11.4)), _w(Vector3(-1.8, 6.3, z - 14.4)), _w(Vector3(1.8, 9.3, z - 18.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.8, 9.3, z - 18.0)), _w(Vector3(1.8, 9.3, z - 19.4)), _w(Vector3(-0.75, 12.7, z - 24.6)), true, true)
	r_walk(_w(Vector3(-0.75, 12.7, z - 26.5)))
	_hop(cap, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	return end["c"]


# Stage 14: the cargo line - FORK. Left (gold): the container stacks, a mantle, crate hops and a
# press to slip under. Right (cyan): the mass-driver rail - a boost strip flings you at a hull
# panel, you run it at 18 m/s and kick off onto the dock.
func _stage_14_cargo_line() -> Vector3:
	var end: Dictionary = _dock(Vector3(0, 2.0, -36.0), -90.0)
	# -- container stacks (route 0) --
	kit.ledge(_w(Vector3(-3.0, 3.3, -6.6)), Vector3(3.0, 5.0, 4.0), _yaw, "alt")
	var k1: Dictionary = _area(Vector3(-3.0, 3.3, -6.6), 1.5, 2.0)
	var k2: Dictionary = _deck(Vector3(-3.5, 3.3, -14.0), 2.2, 2.2)
	var k3: Dictionary = _deck(Vector3(-2.5, 3.3, -20.5), 2.2, 2.2, "alt")
	var press: Crusher = _press(Vector3(-2.5, 3.3, -20.5), Vector3(2.8, 1.4, 2.8), 3.4, 3.2, 0.0)
	_slam_fx(press, Vector3(-2.5, 3.3, -20.5))
	var k4: Dictionary = _deck(Vector3(-3.0, 2.0, -27.0), 2.0, 2.0)
	# -- mass driver (route 1) --
	kit.boost(_w(Vector3(3.4, 0, -8.5)), Vector3(2.2, 0.3, 11.0), _yaw, 20.0)
	_deck(Vector3(3.4, -0.3, -8.5), 2.6, 11.0, "alt", 0.4)
	kit.wallrun(_w(Vector3(5.0, 1.5, -19.5)), Vector3(15.0, 7.0, 0.5), _yaw + 90.0)
	_sign(Vector3(-2.2, 0, -2.4), LedgeBlock.LIP_COLOR)
	_sign(Vector3(2.2, 0, -2.4), Color(0.3, 0.85, 1.0))
	if route_variant == 0:
		r_mantle(_w(Vector3(-3.0, 0, -2.7)), _w(Vector3(-3.0, 3.3, -5.4)))
		_hop(k1, k2)
		# the press covers k3: go when it has just risen, land and leap straight on
		r_walk(_w(_edge(k2, k3["c"], 0.7)))
		r_until(func() -> bool: return _under_ok(press, 0.4, 1.7, 2.0))
		_hop(k2, k3)
		_hop(k3, k4)
		_hop(k4, end, Vector3(-1.0, 0, 1.6))
	else:
		r_walk(_w(Vector3(2.6, 0, -2.7)))
		r_walk(_w(Vector3(3.9, 0, -4.0)))
		r_wallrun(_w(Vector3(3.9, 0, -13.6)), _w(Vector3(4.7, 1.6, -20.0)), _w(Vector3(4.4, 1.6, -23.5)), _w(end["c"] + Vector3(0, 0, 0.5)))
	r_checkpoint()
	return end["c"]


# Stage 15: the laser lattice - a beam walk through an airlock laser, two blinking plates, then
# a longer beam where two lasers and a side jet (shoving you off the beam) all keep their own time.
func _stage_15_lattice() -> Vector3:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var b1: Dictionary = _deck(Vector3(0, 0, -9.0), 1.2, 8.0, "alt", 0.4)
	var l1: LaserGate = kit.laser(_w(Vector3(0, 1.6, -9.0)), Vector3(2.6, 3.2, 0.2), 2.4, 0.5, 0.0, _yaw)
	var p1: BlinkPlatform = kit.blink(_w(Vector3(1.5, 0.8, -16.4)), Vector3(1.8, 0.4, 1.8), 2.8, 0.62, 0.0)
	var p2: BlinkPlatform = kit.blink(_w(Vector3(-0.5, 1.6, -21.6)), Vector3(1.8, 0.4, 1.8), 2.8, 0.62, 0.62)
	var b2: Dictionary = _deck(Vector3(0, 1.6, -30.0), 1.2, 10.0, "alt", 0.4)
	var gates: Array = []
	var leads: Array = []
	for i: int in 2:
		var z: float = [-27.8, -32.2][i]
		var lead: float = (-25.6 - z) / 9.0 + 0.2
		gates.append(kit.laser(_w(Vector3(0, 3.2, z)), Vector3(2.6, 3.2, 0.2), 2.6, 0.45, fposmod(0.725 - lead / 2.6, 1.0), _yaw))
		leads.append(lead)
	# the jet keeps the same beat, so a runner leaving on the green wave passes all three in their quiet
	var jl: float = (-25.6 + 30.0) / 9.0 + 0.2
	var jet: OrbitalThruster = _thruster(Vector3(-4.2, 2.4, -30.0), Vector3.RIGHT, 7.0, 1.8, 2.6, 0.4, fposmod(0.7 - jl / 2.6, 1.0), 110.0, 12.0)
	gates.append(jet)
	leads.append(jl)
	var end: Dictionary = _dock(Vector3(0, 1.6, -42.0), 0.0)
	# beam 1 under the airlock laser
	_hop(dock, b1, Vector3(0, 0, 2.4))
	r_walk(_w(Vector3(0, 0, -6.2)))
	r_until(func() -> bool: return _clear([l1], [0.45], 0.35))
	r_walk(_w(Vector3(0, 0, -12.4)))
	# SHORTCUT: two fixed 1 m relay pillars beside the blinking plates - no waiting, no margin
	var y1: Dictionary = _mast(Vector3(-1.4, 0.8, -17.9))
	var y2: Dictionary = _mast(Vector3(1.3, 1.6, -22.6))
	if route_variant == 2:
		_hop(b1, y1)
		_hop(y1, y2)
		_hop(y2, b2, Vector3(0, 0, 4.2))
	else:
		# the blinking plates
		r_until(func() -> bool: return _blink_ok(p1, 0.4, 1.3) and _blink_ok(p2, 1.4, 2.4))
		r_jump(_w(Vector3(0, 0, -12.6)), _w(Vector3(1.5, 0.8, -16.4)))
		r_jump(_w(Vector3(1.2, 0.8, -17.0)), _w(Vector3(-0.5, 1.6, -21.6)))
		r_jump(_w(Vector3(-0.4, 1.6, -22.2)), _w(Vector3(0, 1.6, -25.8)))
	r_walk(_w(Vector3(0, 1.6, -25.6)))
	r_until(func() -> bool: return _clear(gates, leads, 0.35))
	r_walk(_w(Vector3(0, 1.6, -34.6)))
	_hop(b2, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	return end["c"]


# Stage 16: the reactor stacks - three shielding blocks stepping up 3.3 m each (mantle, mantle,
# mantle), a scanning laser across each top, then a shove-ram catwalk to the dock.
func _stage_16_stacks() -> Vector3:
	kit.ledge(_w(Vector3(0, 3.3, -6.6)), Vector3(3.0, 5.0, 4.0), _yaw, "alt")
	kit.ledge(_w(Vector3(0, 6.6, -12.6)), Vector3(3.0, 8.0, 4.0), _yaw, "main")
	kit.ledge(_w(Vector3(1.0, 9.9, -18.6)), Vector3(3.0, 11.0, 4.0), _yaw, "alt")
	var s1: LaserGate = kit.laser(_w(Vector3(0, 3.3 + 1.6, -8.0)), Vector3(3.4, 3.2, 0.2), 2.2, 0.5, 0.0, _yaw)
	var s2: LaserGate = kit.laser(_w(Vector3(0, 6.6 + 1.6, -14.0)), Vector3(3.4, 3.2, 0.2), 2.0, 0.5, 0.4, _yaw)
	var top3: Dictionary = _area(Vector3(1.0, 9.9, -18.6), 1.5, 2.0)
	var cw: Dictionary = _deck(Vector3(1.0, 9.9, -26.55), 2.2, 11.9)
	var rams: Array = []
	var leads: Array = []
	for z: float in [-25.0, -30.0]:
		var lead: float = (-23.0 - z) / 9.0 + 0.15
		rams.append(kit.piston(_w(Vector3(3.0, 11.5, z)), Vector3(2.2, 1.6, 1.6), _yaw + 90.0, 2.6, 2.4, fposmod(0.2 - lead / 2.4, 1.0), 13.0))
		leads.append(lead)
	var end: Dictionary = _dock(Vector3(0, 9.9, -38.3), 0.0)
	# SHORTCUT: the coolant-shield panel along the first stack - run it past the first scanner and
	# mantle straight onto the second stack out of the kick
	kit.wallrun(_w(Vector3(2.6, 2.3, -7.5)), Vector3(11.0, 7.0, 0.5), _yaw + 90.0)
	if route_variant == 2:
		r_until(func() -> bool: return _clear([s1], [0.75], 0.35))
		r_wallrun(_w(Vector3(0.9, 0, -2.6)), _w(Vector3(2.0, 1.4, -5.0)), _w(Vector3(2.0, 1.4, -8.6)), _w(Vector3(0, 6.6, -12.0)))
	else:
		r_mantle(_w(Vector3(0, 0, -2.7)), _w(Vector3(0, 3.3, -5.4)))
		r_walk(_w(Vector3(0, 3.3, -7.2)))
		r_until(func() -> bool: return _clear([s1], [0.25], 0.3))
		r_mantle(_w(Vector3(0, 3.3, -8.9)), _w(Vector3(0, 6.6, -11.4)))
	r_walk(_w(Vector3(0, 6.6, -13.2)))
	r_until(func() -> bool: return _clear([s2], [0.25], 0.3))
	r_mantle(_w(Vector3(0.5, 6.6, -14.9)), _w(Vector3(1.0, 9.9, -17.4)))
	r_walk(_w(Vector3(1.0, 9.9, -20.0)))
	r_walk(_w(Vector3(1.0, 9.9, -23.0)))
	r_until(func() -> bool: return _clear(rams, leads, 0.35))
	r_walk(_w(Vector3(1.0, 9.9, -30.6)))
	_hop(cw, end, Vector3(-1.0, 0, 1.6))
	r_checkpoint()
	top3.clear()
	return end["c"]


# Stage 17: the reactor hall - the whole hall is a low-g bay round the glowing core. Float over the
# coolant trench, ride a launch grate 11 m up past the core, run the shielding wall at the top and
# kick off it - in low gravity the kick carries you all the way across to the dock.
func _stage_17_reactor() -> Vector3:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_bay(Vector3(0, 8.0, -29.0), Vector3(18.0, 28.0, 52.0))
	var r1: Dictionary = _deck(Vector3(0, 0, -13.2), 2.6, 2.6)
	var gc: Vector3 = Vector3(0, 0, -19.6)
	var g: OrbitalThruster = _grate(gc, 3.0, 5.5, 3.2, 0.35, 0.0, 14.0)
	var u: Dictionary = _deck(Vector3(-0.5, 10.0, -26.0), 3.0, 3.0, "alt")
	kit.wallrun(_w(Vector3(2.6, 11.5, -35.0)), Vector3(14.0, 7.0, 0.5), _yaw + 90.0)
	var end: Dictionary = _dock(Vector3(-1.0, 10.0, -52.0), 0.0)
	# the core: a kill sphere hanging beside the lift shaft, and the trench under the first leap
	var core_c: Vector3 = Vector3(-6.5, 6.0, -21.0)
	kit.hazard(_w(core_c), Vector3(2.3, 2.3, 2.3))
	_reactor_core(core_c)
	_haz(Vector3(0, -0.2, -7.8), Vector3(2.4, 0.8, 1.4), 0.0)
	_float(dock, r1)
	_hop(r1, _area(gc, 1.5, 1.5))
	_r_lift(g, gc, 6.0, (u["c"] as Vector3))
	r_wallrun(_w(Vector3(0.6, 10.0, -27.3)), _w(Vector3(2.0, 11.4, -31.0)), _w(Vector3(2.0, 11.4, -38.0)), _w(end["c"] + Vector3(0, 0, 1.2)))
	r_checkpoint()
	return end["c"]


# Stage 18: the final approach - the last flare deck. Crumbling hull plates between two shield
# pockets, then a sprint through the flare gate itself to the docking ring and the finish.
func _stage_18_approach() -> void:
	var dock: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f := OrbitalFlare.new()
	f.width = 12.0
	f.height = 9.0
	f.length = 36.0
	f.period = 5.0
	f.sweep = 1.4
	f.phase = 0.3
	f.position = _w(Vector3(0, 0, -24.0))
	f.rotation.y = deg_to_rad(_yaw)
	add_child(f)
	var d1: Dictionary = _deck(Vector3(0, 0, -9.0), 4.0, 6.0)
	_shelter(f, Vector3(-0.8, 0, -10.6))
	kit.collapse(_w(Vector3(1.2, 0, -16.2)), 2.2, 0.6, 2.4)
	kit.collapse(_w(Vector3(-0.4, 0.6, -21.8)), 2.2, 0.6, 2.4)
	var d2: Dictionary = _deck(Vector3(0, 0.6, -28.0), 4.0, 6.0)
	_shelter(f, Vector3(-0.8, 0.6, -29.4))
	var b1: Dictionary = _deck(Vector3(1.0, 0.6, -35.3), 2.0, 2.0, "alt")
	var b2: Dictionary = _deck(Vector3(0, 0.6, -40.8), 2.0, 2.0)
	var fin: Dictionary = _deck(Vector3(0, 0.6, -51.0), 10.0, 12.0, "main", 1.0)
	kit.finish(_w(Vector3(0, 0.6, -52.0)), _yaw)
	_mids.append(_w(Vector3(0, 0, -26.0)))
	_ends.append(_w(Vector3(0, 0.6, -52.0)))
	_docking_ring(Vector3(0, 0.6, -52.0))
	# leg 1: dock -> pocket 1
	r_until(func() -> bool: return _flare_go(f, 24.0, 13.4, 2.0))
	_hop(dock, d1, Vector3(0, 0, 2.0))
	r_walk(_w(Vector3(-0.8, 0, -10.5)))
	# leg 2: pocket 1 -> over the crumbling plates -> pocket 2
	r_until(func() -> bool: return _flare_go(f, 13.4, -5.4, 3.4))
	r_walk(_w(Vector3(1.2, 0, -10.9)))
	r_jump(_w(Vector3(1.2, 0, -11.65)), _w(Vector3(1.2, 0, -16.2)))
	r_jump(_w(Vector3(1.0, 0, -16.9)), _w(Vector3(-0.4, 0.6, -21.8)))
	r_jump(_w(Vector3(-0.3, 0.6, -22.5)), _w(Vector3(0.6, 0.6, -26.2)))
	r_walk(_w(Vector3(-0.8, 0.6, -29.3)))
	# leg 3: pocket 2 -> through the flare gate -> finish
	r_until(func() -> bool: return _flare_go(f, -5.4, -21.0, 3.2))
	r_walk(_w(Vector3(1.2, 0.6, -29.7)))
	r_jump(_w(Vector3(1.2, 0.6, -30.65)), _w(b1["c"]))
	_hop(b1, b2)
	_hop(b2, fin, Vector3(0, 0, 4.0))
	r_walk(_w(Vector3(0, 0.6, -52.5)))
	d1.clear()
	d2.clear()


## The docking ring round the finish: a huge standing torus with running lights, a slow swirl of
## gold motes and bursts of light on the course clock.
func _docking_ring(at: Vector3) -> void:
	var c: Vector3 = at + Vector3(0, 5.5, -1.5)
	var ring := TorusMesh.new()
	ring.inner_radius = 8.0
	ring.outer_radius = 9.2
	ring.rings = 64
	ring.ring_segments = 12
	var rm := Look.mesh_node(ring, Look.flat(Color(0.82, 0.84, 0.88), 0.45, 0.4), _w(c))
	rm.rotation = Vector3(PI * 0.5, deg_to_rad(_yaw), 0)
	add_child(rm)
	var lights := TorusMesh.new()
	lights.inner_radius = 7.85
	lights.outer_radius = 8.05
	lights.rings = 64
	lights.ring_segments = 6
	var lm := Look.mesh_node(lights, Look.flat(Color(1.0, 0.75, 0.3), 0.3, 0.0, 4.0), _w(c))
	lm.rotation = Vector3(PI * 0.5, deg_to_rad(_yaw), 0)
	add_child(lm)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var clamp_box := Look.box(Vector3(1.4, 1.4, 2.2), Look.flat(Look.c("decor"), 0.5, 0.6))
		clamp_box.position = _w(c + Vector3(cos(a) * 8.6, sin(a) * 8.6, 0))
		clamp_box.rotation = Vector3(0, deg_to_rad(_yaw), a)
		add_child(clamp_box)
	OrbitalFx.swirl(self, _w(at + Vector3(0, 0.2, 0)), 3.2, Color(1.0, 0.8, 0.35), 48)
	for i: int in 3:
		var b: GPUParticles3D = OrbitalFx.burst(self, _w(c + Vector3(cos(TAU * float(i) / 3.0) * 8.0, sin(TAU * float(i) / 3.0) * 8.0, 0)), Color(1.0, 0.78, 0.35), 40, 6.0, 0.3)
		_clock_fx.append({"p": b, "period": 1.8, "offset": float(i) * 0.6, "last": -99})


## Set dressing and ambient life for the whole station (visual only, all well off the course).
func _decor() -> void:
	# -- two layered ambient systems round every stage: drifting dust and twinkling ion glints --
	for i: int in _mids.size():
		var m: Vector3 = _mids[i]
		OrbitalFx.dust(self, m + Vector3(0, 3.0, 0), Vector3(20.0, 9.0, 20.0), 46)
		var col: Color = Color(0.4, 0.9, 1.0) if i % 2 == 0 else Color(0.78, 0.55, 1.0)
		OrbitalFx.glints(self, m + Vector3(0, 4.0, 0), Vector3(16.0, 7.0, 16.0), 16, col)
	# micrometeor streaks far out round the station
	OrbitalFx.streaks(self, Vector3(40, 60, -80), Vector3(160, 40, 160), 10)
	OrbitalFx.streaks(self, Vector3(60, -40, -60), Vector3(180, 30, 180), 8)
	# -- the central hub: habitat wheel, spine modules, solar wings, radiators, dish --
	var hub: Vector3 = Vector3(98, 30, -95)
	OrbitalStation.habitat_wheel(self, hub, Basis(Vector3.BACK, PI * 0.5), 26.0, 70.0)
	var along_x: Basis = Basis(Vector3.UP, PI * 0.5)
	OrbitalStation.module(self, hub + Vector3(-20, 0, 0), along_x, 16.0, 3.4)
	OrbitalStation.module(self, hub + Vector3(21, 0, 0), along_x, 18.0, 3.4, Color(0.6, 0.9, 1.0))
	OrbitalStation.module(self, hub + Vector3(0, -14, 0), Basis(Vector3.RIGHT, PI * 0.5), 14.0, 2.8)
	OrbitalStation.truss(self, hub + Vector3(0, 0, -28), hub + Vector3(0, 0, -62), 1.8)
	OrbitalStation.truss(self, hub + Vector3(0, 0, 28), hub + Vector3(0, 0, 60), 1.8)
	var face_sun: Basis = Basis(Vector3.RIGHT, deg_to_rad(-60.0))
	for zc: float in [-50.0, 48.0]:
		for sx: float in [-1.0, 1.0]:
			OrbitalStation.solar_wing(self, hub + Vector3(sx * 13.5, 0, zc), face_sun, Vector2(24.0, 10.0))
	OrbitalStation.radiator(self, hub + Vector3(-20, -8, 9), Basis.IDENTITY, Vector2(10.0, 6.0), 6)
	OrbitalStation.radiator(self, hub + Vector3(21, -8, -9), Basis(Vector3.UP, PI), Vector2(10.0, 6.0), 6)
	OrbitalStation.dish(self, hub + Vector3(30, 5, 0), Vector3(0.4, 1.0, 0.3), 5.0)
	OrbitalFx.exhaust(self, hub + Vector3(33, 0, 0), Vector3(1, 0, 0), 5.0, 0.7)
	OrbitalFx.swirl(self, hub + Vector3(0, -2, 0), 7.0, Color(0.5, 0.85, 1.0), 40)
	# -- the west power yard (under stages 7-10): a module string and two big wings --
	var west: Vector3 = Vector3(-30, 2, -105)
	OrbitalStation.module(self, west, Basis.IDENTITY, 26.0, 3.0)
	OrbitalStation.truss(self, west + Vector3(0, 0, 16), west + Vector3(0, 0, 50), 1.5)
	for sx: float in [-1.0, 1.0]:
		OrbitalStation.solar_wing(self, west + Vector3(sx * 11.0, -1, 36), face_sun, Vector2(18.0, 9.0))
	OrbitalStation.radiator(self, west + Vector3(6, -6, -4), Basis(Vector3.UP, PI * 0.5), Vector2(8.0, 5.0), 5)
	OrbitalFx.vent(self, west + Vector3(0, 0, -16.5), Vector3(0, -0.2, -1), 18)
	# -- under the opening stages: an old supply module and its truss down into the dark --
	OrbitalStation.module(self, Vector3(12, -22, -60), Basis(Vector3.UP, 0.3), 30.0, 4.0)
	OrbitalStation.truss(self, Vector3(12, -22, -40), Vector3(0, -2, -12), 1.3)
	OrbitalStation.module(self, Vector3(40, -14, -130), along_x, 22.0, 3.2, Color(0.6, 0.9, 1.0))
	# -- the arrival bay: a docked shuttle, the bay frame over the start deck, a dish --
	OrbitalStation.shuttle(self, Vector3(-21.0, -4.0, 3.0), 12.0)
	OrbitalStation.truss(self, Vector3(-19.0, -3.5, 3.0), Vector3(-6.0, -0.8, 1.0), 0.9)
	OrbitalStation.dish(self, Vector3(13.0, 1.0, -8.0), Vector3(0.5, 1.0, -0.2), 3.2)
	_truss_v_world(Vector3(13.0, 0.8, -8.0), 22.0)
	for sx: float in [-1.0, 1.0]:
		kit.block(Vector3(sx * 5.4, 3.2, -5.6), Vector3(0.5, 6.4, 0.5), Look.c("side"), false)
		kit.glow_strip(Vector3(sx * 5.4, 0.03, -5.6), Vector3(0.9, 0.05, 0.9), Look.c("accent"))
	kit.block(Vector3(0, 6.6, -5.6), Vector3(11.3, 0.5, 0.6), Look.c("side"), false)
	kit.glow_strip(Vector3(0, 6.3, -5.35), Vector3(10.0, 0.08, 0.1), Look.c("accent2"))
	for i: int in 3:
		kit.glow_strip(Vector3(0, 0.03, 1.5 - float(i) * 2.2), Vector3(1.8 - float(i) * 0.4, 0.04, 0.3), Look.c("accent"))
	# -- the east radiator farm beside stages 15-17 --
	for i: int in 4:
		OrbitalStation.radiator(self, Vector3(162, 38 + float(i) * 4.0, -150 + float(i) * 28.0), Basis(Vector3.UP, PI * 0.5), Vector2(12.0, 7.0), 5)
	OrbitalStation.truss(self, Vector3(156, 40, -160), Vector3(156, 52, -50), 1.6)
	OrbitalStation.module(self, Vector3(170, 60, -20), Basis(Vector3.UP, 0.2), 24.0, 3.6)
	# -- venting pipes and sparking cable joints under the docks --
	for i: int in _ends.size():
		var e: Vector3 = _ends[i]
		if i % 3 == 0:
			OrbitalFx.vent(self, e + Vector3(3.4, -1.6, 0.0), Vector3(1, -0.3, 0.2), 12)
		if i % 2 == 1:
			var sp: GPUParticles3D = OrbitalFx.sparks(self, e + Vector3(-0.4, -4.0, 0.4), Vector3(0.3, -1, 0.2), 20)
			_sparks.append(sp)
			_spark_next.append(float(i) * 0.37)


## Vertical truss hanging down from a world point (the local-frame _truss_v without the frame).
func _truss_v_world(top: Vector3, length: float) -> void:
	var o: Vector3 = _o
	var y: float = _yaw
	var b: Basis = _b
	_frame(Vector3.ZERO, 0.0)
	_truss_v(top, length)
	_o = o
	_yaw = y
	_b = b


# ---- environment ------------------------------------------------------------------------------

func _environment() -> void:
	for child: Node in get_children():
		if child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment
			env.background_mode = Environment.BG_SKY
			env.sky = OrbitalSky.make()
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.42, 0.50, 0.72)
			env.ambient_light_energy = 0.42
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
			env.tonemap_exposure = 1.05
			env.tonemap_white = 6.0
			env.fog_enabled = true
			env.fog_light_color = Color(0.03, 0.04, 0.09)
			env.fog_density = 0.0016
			env.fog_sky_affect = 0.0
			env.fog_aerial_perspective = 0.0
			env.fog_sun_scatter = 0.0
			env.glow_enabled = true
			env.glow_intensity = 0.85
			env.glow_bloom = 0.06
			env.glow_hdr_threshold = 1.0
			env.adjustment_enabled = true
			env.adjustment_saturation = 1.12
			env.adjustment_contrast = 1.1
		elif child is DirectionalLight3D:
			var l := child as DirectionalLight3D
			if l.name == "Sun":
				l.light_energy = 2.3
				l.shadow_blur = 0.6
				l.light_angular_distance = 0.4
			else:
				# planetshine: soft blue light from the planet below
				l.rotation_degrees = Vector3(62, 200, 0)
				l.light_color = Color(0.45, 0.62, 1.0)
				l.light_energy = 0.35
