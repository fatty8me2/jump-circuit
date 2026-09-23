extends LevelBase
## 6. ORBITAL DRIFT - a space station in low orbit (WIP header, rewritten when the course is done).

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _tuning: MovementTuning
var _sparks: Array[GPUParticles3D] = []
var _spark_next: Array[float] = []


func _configure() -> void:
	theme_id = "orbital"
	music_track = "b"
	kill_y = -80.0
	route_variants = 1


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
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	_frame(Vector3.ZERO, 0.0)
	var cp: Vector3 = _stage_1_arrival()
	_frame(_w(cp), 0.0)
	cp = _stage_2_lowg()
	_frame(_w(cp), -90.0 + _yaw)
	cp = _stage_3_solar()
	_frame(_w(cp), -90.0 + _yaw)
	cp = _stage_4_cargo()
	_frame(_w(cp), -90.0 + _yaw)
	cp = _stage_5_airlock()
	_frame(_w(cp), _yaw)
	cp = _stage_6_hydraulics()
	_frame(_w(cp), 90.0 + _yaw)
	_stage_end()


func _process(dt: float) -> void:
	# sparking cables: each spark emitter fires on its own pseudo-random clock
	var t: float = Game.course_time
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
	var a4: Dictionary = _deck(Vector3(-2.6, 2.0, -29.4), 1.8, 1.8, "alt")
	var tug: MovingPlatform = kit.mover(_w(Vector3(0, 2.0, -36.0)), Vector3(2.6, 0.5, 2.6), [Vector3.ZERO, _d(Vector3(0, 0, -8.0))], 5.0)
	var end: Dictionary = _dock(Vector3(0, 2.0, -52.0))
	_hop(start, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	_hop(a3, a4)
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
	var end: Dictionary = _dock(Vector3(2.8, 6.8, -44.4), -90.0)
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
	var end: Dictionary = _dock(Vector3(-26.0, -2.5, -25.5), 90.0)
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


# temporary end
func _stage_end() -> void:
	_deck(Vector3(0, 0, -12.0), 10.0, 10.0, "main", 1.0)
	kit.finish(_w(Vector3(0, 0, -14.0)), _yaw)
	r_jump(_w(Vector3(0, 0, -2.7)), _w(Vector3(0, 0, -8.5)))
	r_walk(_w(Vector3(0, 0, -14.0)))


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
