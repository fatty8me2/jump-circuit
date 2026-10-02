extends LevelBase
## 13. SUGAR RUSH - a candy and toy-box dreamworld. Eighteen stages, each ending on a checkpoint,
## across floating dessert islands (frosted cakes on upside-down waffle cones) over a sea of molten
## chocolate: gumdrop hills, lollipop trees and candy canes below, ice-cream mountains, a cake castle
## and a great rainbow on the horizon, candyfloss clouds, and sprinkles drifting down through a
## pastel sky. A bounce and momentum showcase: jellies that throw you higher the harder you land,
## jack-in-the-boxes, wind-up soldiers, a toy railway and the great gumball machine.
##
##  1 Frosting Gate      gumdrop hops over the chocolate river, the first JELLY up onto the cake
##  2 Wafer Walk         MANTLE the toy blocks, cupcake tops, WALL RUN the wafer over the gap
##  3 Licorice Lane      a licorice belt running back at you, a narrow bridge crossed by marching
##                       wind-up SOLDIERS, MANTLE out
##  4 Jack Shelves       two JACK-IN-THE-BOXES fling you up the toy shelves
##                       [shortcut: a little jelly beside the first jack skips its wait]
##  5 Jelly Pond         BRANCH: three jellies climbing over the chocolate pond | MANTLE the block
##                       and WALL RUN the wafer
##  6 Melting Parlor     melting scoops, the sugar-glass LASER, a sprinkle boost into a long leap
##  7 Taffy Pull         sagging taffy bridges, the boxing-glove rams (PISTONS)
##  8 Cookie Press       a cookie belt under two cookie stamps (CRUSHERS), MANTLE out
##                       [shortcut: WALL RUN the oven wall past both stamps]
##  9 Candyfloss Clouds  BRANCH: a wave of candyfloss clouds (blinks) | a jelly up onto the gift box
##                       and its PORTAL
## 10 SUGAR RUSH EXPRESS SET PIECE: board the toy train from the station, ride it out over the
##                       chocolate lake, hop across to the train running alongside, and ride that one
##                       into the far station
## 11 Gumball Chute      climb the chute while giant gumballs roll down it, ducking into alcoves
## 12 Wafer Chimney      a jack up to the chimney, three WALL RUNS up it, MANTLE out at the top
## 13 Toy Parade        BRANCH: the parade ground and its three marching soldiers | the jack balcony
##                       [shortcut: drop to the jellies in the chocolate and bounce to the far side]
## 14 Lollipop Swings    giant lollipops swinging across the gaps, melting scoops
## 15 Rainbow Rush       a rainbow boost into a long leap, down onto a jelly and up to the checkpoint
## 16 Licorice Factory   the candy-cane sweeper, the belt between the boxing gloves (PISTONS)
##                       [shortcut: time the gift box's lid and take its PORTAL to the checkpoint]
## 17 Jelly Tower        bounce, bounce higher, land: two jellies up the tower, a candy cart across
## 18 Gumball Summit     two MANTLES up the cake, the last sugar-glass LASER, the last jack up onto the
##                       summit dais under the rainbow, the finish by the great gumball machine
##
## Candy mechanics (own scripts): CandyJelly (the harder you land the higher it throws you),
## CandyJack (jack-in-the-box launchers on the clock), CandySoldier (wind-up drummers that shove),
## CandyTrain (the toy railway, the set piece) and CandyGumball (the gumball run). Route variants
## for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut.

const PINK := Color(1.0, 0.45, 0.65)
const MINT := Color(0.45, 0.95, 0.75)
const LEMON := Color(1.0, 0.88, 0.35)
const SKY := Color(0.45, 0.75, 1.0)
const GRAPE := Color(0.72, 0.5, 1.0)
const ORANGE := Color(1.0, 0.6, 0.28)
const CHERRY := Color(1.0, 0.18, 0.28)
const CREAM := Color(1.0, 0.96, 0.9)

const FROSTING_SHADER: Shader = preload("res://visual/candy_frosting.gdshader")
const SEA_Y: float = -30.0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: CandyDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Bursts that fire when the player arrives at a spot (portal exits): {"at", "p": [GPUParticles3D], "cool"}
var _arrivals: Array[Dictionary] = []
## Places set dressing keeps clear of (world, flat radius): big set pieces.
var _keep_out: Array[Vector4] = []


func _configure() -> void:
	theme_id = "candy"
	music_track = "candy"
	kill_y = SEA_Y + 2.0
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


## A frosted cake slab (walkable) with a waffle cone hanging under it.
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, -1.0, _yaw)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A round landing (a gumdrop cake) on its cone.
func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.8) -> Dictionary:
	var body: StaticBody3D = kit.disc(_w(c), r, thick, style)
	return {"c": c, "r": r, "node": body}


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


## A jelly trampoline whose top is at local `c`.
func _jelly(c: Vector3, r: float, tint: Color, plinth: float = 0.9) -> Dictionary:
	var j := CandyJelly.new()
	j.radius = r
	j.tint = tint
	j.plinth = plinth
	j.position = _w(c)
	add_child(j)
	return {"c": c, "r": r, "node": j}


## A jack-in-the-box whose hat (at rest) is at local `c`; its box stands on the floor below.
## `launch` is in the stage's frame (local -Z = onward).
func _jack(c: Vector3, period: float, phase: float, launch: Vector3 = Vector3(0, 19, -2.5), tint: Color = SKY) -> CandyJack:
	var j := CandyJack.new()
	j.period = period
	j.phase = phase
	j.launch = launch
	j.tint = tint
	j.rotation.y = deg_to_rad(_yaw)
	j.position = _w(c)
	add_child(j)
	return j


## A wind-up soldier marching from local `c` (floor) along local offset `along` and back.
func _soldier(c: Vector3, along: Vector3, period: float, phase: float, coat: Color = CHERRY) -> CandySoldier:
	var s := CandySoldier.new()
	s.to = _d(along)
	s.period = period
	s.phase = phase
	s.coat = coat
	s.position = _w(c)
	add_child(s)
	CandySoldier.track(self, _w(c), _w(c + along), Color(1.0, 0.95, 0.6))
	return s


## A river of molten chocolate at local `c` (surface), size (x across, z along): a kill surface.
func _choco(c: Vector3, sx: float, sz: float, net: bool = true) -> void:
	var s: Vector3 = _sz(Vector3(sx, 0, sz))
	deco.choco_plane(_w(c), Vector2(s.x, s.z), 0.0, Vector2(_d(Vector3(0, 0, 0.6)).x, _d(Vector3(0, 0, 0.6)).z))
	if net:
		var k := KillZone.new()
		k.show_mesh = false
		k.size = _sz(Vector3(sx, 1.0, sz))
		k.position = _w(c + Vector3(0, 0.2, 0))
		add_child(k)
	CandyFx.choco_bubbles(self, _w(c + Vector3(0, 0.05, 0)), _sz(Vector3(sx * 0.45, 0.1, sz * 0.45)), clampi(int(sx * sz * 0.05), 8, 40))


## A sugar-glass beam across the route at local floor point `c` (`width` across) between two
## lollipop posts.
func _beam(c: Vector3, width: float, period: float, on: float, phase: float, height: float = 2.4) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.2), period, on, phase, _yaw)
	for sx: float in [-1.0, 1.0]:
		deco.lollipop(_w(c + Vector3(sx * (width * 0.5 + 0.75), 0, 0)), height + 0.4, 0.55, CHERRY if sx < 0.0 else SKY, CREAM, deg_to_rad(_yaw))
	return g


## A cookie stamp: the crusher dressed as a giant iced cookie press.
func _press(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	var cookie: StandardMaterial3D = Look.flat(Color(0.86, 0.6, 0.32), 0.85)
	cr.add_child(Look.box(Vector3(size.x + 0.08, size.y * 0.55, size.z + 0.08), cookie, Vector3(0, size.y * 0.2, 0)))
	cr.add_child(Look.box(Vector3(size.x + 0.1, 0.16, size.z + 0.1), Look.flat(PINK, 0.5), Vector3(0, size.y * 0.5 + 0.02, 0)))
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var chip := Look.sphere(0.16, Look.flat(Color(0.3, 0.16, 0.08), 0.5), Vector3(cos(a) * size.x * 0.52, size.y * 0.1, sin(a) * size.z * 0.3))
		cr.add_child(chip)
	return cr


## A boxing-glove ram: the piston with a red glove on its face.
func _glove(top: Vector3, yaw_extra: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.8, 1.3, 1.4)
	var p: Piston = kit.piston(_w(top), size, _yaw + yaw_extra, stroke, period, phase, 8.0)
	var glove := Look.sphere(0.62, CandyDecor.gloss(CHERRY), Vector3(0, 0, -size.z * 0.5 - 0.3))
	glove.scale = Vector3(1.1, 0.95, 0.75)
	p.add_child(glove)
	p.add_child(Look.cylinder(0.5, 0.25, Look.flat(CREAM, 0.6), Vector3(0, 0, -size.z * 0.5 + 0.05), -1.0, 16))
	var thumb := Look.sphere(0.25, CandyDecor.gloss(CHERRY), Vector3(0.55, 0.15, -size.z * 0.5 - 0.2))
	p.add_child(thumb)
	return p


## Checkpoint landing facing the next stage's heading (_next_yaw), with its sweets.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var h: float = size * 0.5 - 0.45
	var cols: Array[Color] = [PINK, SKY, LEMON, MINT, GRAPE]
	var k: int = _cp_world.size()
	for s: float in [-1.0, 1.0]:
		deco.lollipop(_w(c + Vector3(s * h, 0, h)), 1.8, 0.5, cols[(k + int(s + 1.0)) % cols.size()], CREAM, deg_to_rad(_yaw))
	# banked-stage feedback: a pop of confetti and a fountain of sugar sparkles
	var burst: GPUParticles3D = CandyFx.confetti(1.6, 60, 8.0)
	burst.position = _w(c) + Vector3(0, 0.6, 0)
	add_child(burst)
	var glint: GPUParticles3D = Fx.burst({"amount": 40, "lifetime": 1.2, "shape": "sphere", "radius": 0.6, "tex": Fx.Tex.STAR,
		"size": 0.35, "speed": Vector2(2.0, 5.0), "gravity": Vector3(0, -2.0, 0), "curve": "pop", "pick": CandyFx.HOT,
		"aabb": AABB(Vector3(-8, -4, -8), Vector3(16, 14, 16))})
	glint.position = _w(c) + Vector3(0, 1.4, 0)
	add_child(glint)
	_cp_bursts[cp] = [burst, glint]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: a party-popper pop as a stage is banked
			WorldAudio.at(self, "candy_confetti", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


## Fork signpost: two lollipops and a floor strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.4, 1.4]:
		deco.lollipop(_w(p + Vector3(sx, 0, 0)), 2.6, 0.55, col, CREAM, deg_to_rad(_yaw))
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.6)), _sz(Vector3(1.4, 0.05, 0.3)), col)


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Stand on a launcher (jack) at `from` until it throws us, then steer to `to`.
func _kick(from: Vector3, to: Vector3) -> void:
	route.append({"kind": "kick", "from": _w(from), "to": _w(to)})


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


## The jack's hat stays down (safe to step onto) over [now + a, now + b].
static func _resting(j: CandyJack, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not j.is_resting_at(Game.course_time + s):
			return false
		s += 0.05
	return true


static func _blink_ok(m: BlinkPlatform, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not m.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


## The swinging lollipop's head stays well out to the side of the route over [now + a, now + b].
static func _swing_clear(p: Pendulum, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if absf(sin(p.angle_at(Game.course_time + s))) * p.length < 2.7:
			return false
		s += 0.03
	return true


static func _door_open(d: MovingPlatform, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if d.offset_at(Game.course_time + s).length() < 2.4:
			return false
		s += 0.05
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = CandyDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	_stage_18()
	_surroundings()
	_candy_materials()


# ---- stage 1: Frosting Gate - gumdrops over the chocolate river, the first jelly -------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", -1.0, _yaw)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	var g1: Dictionary = _disc(Vector3(0, 0, -12.2), 1.3)
	var g2: Dictionary = _disc(Vector3(2.4, 0.6, -17.4), 1.2, "alt")
	var j1: Dictionary = _jelly(Vector3(0, 0.6, -23.6), 1.6, PINK)
	var cake: Dictionary = _blk(Vector3(0, 5.4, -30.0), 4.0, 4.0, "main", 1.2)
	var cp: Dictionary = _cp(Vector3(0, 5.4, -39.5))
	_hop(start, g1)
	_hop(g1, g2)
	_hop(g2, j1)
	r_pad(_w(j1["c"]), _w((cake["c"] as Vector3) + Vector3(0, 0, 0.4)))
	_hop(cake, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the gate you start under: two giant candy canes and a rainbow arch of gumdrops
	for sx: float in [-1.0, 1.0]:
		deco.candy_cane(_w(Vector3(sx * 5.6, 0, -5.6)), 7.5, 0.42, deg_to_rad(_yaw) + (0.0 if sx < 0.0 else PI))
		deco.cupcake(_w(Vector3(sx * 5.2, 0, 4.8)), 0.9, PINK if sx < 0.0 else MINT, SKY if sx < 0.0 else LEMON)
		deco.gumdrop(_w(Vector3(sx * 4.8, 0, 1.5)), 0.7, GRAPE if sx < 0.0 else ORANGE)
	var cols: Array[Color] = [CHERRY, ORANGE, LEMON, MINT, SKY, GRAPE]
	for i: int in 13:
		var a: float = PI * float(i) / 12.0
		var gp := _w(Vector3(-cos(a) * 5.6, 7.4 + sin(a) * 3.2, -5.6))
		deco.gumdrop(gp, 0.45, cols[i % cols.size()])
	_choco(Vector3(0, -6.0, -20.0), 30.0, 44.0)
	CandyFx.sprinkles(self, _w(Vector3(0, 6.0, -18.0)), _sz(Vector3(8.0, 5.0, 16.0)), 70)
	return cp["c"]


# ---- stage 2: Wafer Walk - mantle the toy blocks, the cupcake tops, run the wafer over the gap ----

func _stage_2() -> Vector3:
	var m1: Dictionary = _ledge(Vector3(0, 3.3, -7.2), Vector3(5.0, 7.3, 3.4))
	var c1: Dictionary = _disc(Vector3(-2.0, 3.9, -13.4), 1.0)
	var c2: Dictionary = _disc(Vector3(1.6, 4.7, -18.3), 0.95, "alt")
	var c3: Dictionary = _disc(Vector3(-0.4, 5.3, -23.6), 0.95)
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
	# the wafer the panel is set in, and cupcake tops round the hops
	deco.wafer(_w(Vector3(3.3, 5.0, -39.9)), _sz(Vector3(0.9, 11.0, 17.0)), 0.0)
	for c: Dictionary in [c1, c2, c3]:
		var p: Vector3 = _w(c["c"])
		var frost := Look.cylinder(float(c["r"]) * 1.02, 0.25, Look.flat([PINK, MINT, LEMON][int(absf(p.z)) % 3], 0.5), p - Vector3(0, 0.95, 0), float(c["r"]) * 1.1, 24)
		add_child(frost)
	for z: float in [-10.0, -16.0, -22.0]:
		deco.lollipop_tree(_w(Vector3(-6.0, -9.0, z)), 14.0 + kit.rng.randf_range(-2.0, 2.0), 2.2, [PINK, SKY, MINT][int(-z) % 3])
	deco.toy_block(_w(Vector3(4.2, 0, -3.8)), 1.4, SKY, 0.3)
	deco.toy_block(_w(Vector3(-4.0, 0, -4.2)), 1.2, LEMON, -0.2)
	_choco(Vector3(0, -3.0, -40.0), 18.0, 30.0)
	return cp["c"]


# ---- stage 3: Licorice Lane - the belt running back at you, soldiers crossing the bridge ---------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	kit.conveyor(_w(Vector3(0, 0, -11.0)), Vector3(2.6, 0.4, 12.0), _yaw + 180.0, 5.0)
	kit.block(_w(Vector3(0, -1.0, -11.0)), _sz(Vector3(2.2, 1.6, 11.6)), Color(0.14, 0.06, 0.1), false)
	var br: Dictionary = _blk(Vector3(0, 0.6, -30.0), 2.4, 20.0, "alt", 0.8)
	# the soldiers' cross walks (either side of the bridge, never overlapping it)
	for z: float in [-25.0, -34.0]:
		for sx: float in [-1.0, 1.0]:
			kit.plat(_w(Vector3(sx * 3.9, 0.6, z)), _sz(Vector3(3.0, 0.6, 1.4)), "alt", 0.8, _yaw)
	var sa: CandySoldier = _soldier(Vector3(-5.2, 0.6, -25.0), Vector3(10.4, 0, 0), 12.0, 0.0, CHERRY)
	var sb: CandySoldier = _soldier(Vector3(5.2, 0.6, -34.0), Vector3(-10.4, 0, 0), 12.0, 0.36, SKY)
	var top: Dictionary = _ledge(Vector3(0, 3.9, -43.5), Vector3(3.4, 7.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.9, -52.8))
	var xa: Vector3 = _w(Vector3(0, 0.6, -25.0))
	var xb: Vector3 = _w(Vector3(0, 0.6, -34.0))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -6.4)))
	r_walk(_w(Vector3(0, 0, -16.4)))
	r_jump(_w(Vector3(0, 0, -16.7)), _w(Vector3(0, 0.6, -21.4)))
	r_walk(_w(Vector3(0, 0.6, -22.4)))
	_wait(func() -> bool: return sa.lane_clear(xa, 1.6, 0.0, 2.0))
	r_walk(_w(Vector3(0, 0.6, -30.8)))
	_wait(func() -> bool: return sb.lane_clear(xb, 1.6, 0.0, 2.0))
	r_walk(_w(Vector3(0, 0.6, -38.6)))
	r_mantle(_w(Vector3(0, 0.6, -39.75)), _w(Vector3(0, 3.9, -43.1)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	cp0.clear()
	br.clear()
	_choco(Vector3(0, -3.0, -28.0), 16.0, 36.0)
	# licorice twists and gumdrops along the river banks
	for i: int in 4:
		deco.gumdrop(_w(Vector3(-7.5 + 15.0 * float(i % 2), -3.0, -14.0 - 8.0 * float(i))), 1.6, deco.pick_pastel())
	deco.candy_cane(_w(Vector3(3.2, 0.6, -40.6)), 3.2, 0.2, deg_to_rad(_yaw))
	deco.candy_cane(_w(Vector3(-3.2, 0.6, -40.6)), 3.2, 0.2, deg_to_rad(_yaw) + PI)
	return cp["c"]


# ---- stage 4: Jack Shelves - jack-in-the-boxes up the toy shelves --------------------------------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f0: Dictionary = _blk(Vector3(0, 0, -8.5), 6.0, 5.0)
	var ja: CandyJack = _jack(Vector3(0, 1.4, -9.6), 3.0, 0.0, Vector3(0, 19, -2.5), SKY)
	_blk(Vector3(0, 5.8, -16.5), 4.0, 6.0, "alt")
	var jb: CandyJack = _jack(Vector3(0, 7.2, -18.0), 3.0, 0.5, Vector3(0, 19, -2.5), GRAPE)
	var sh2: Dictionary = _blk(Vector3(0, 12.0, -24.8), 4.0, 5.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 12.0, -34.8))
	# SHORTCUT: a little jelly off the corner of the floor - jump on it and it throws you straight
	# up to the first shelf, no waiting for the jack
	var js: Dictionary = _jelly(Vector3(2.3, 0, -12.4), 1.0, LEMON, 0.7)
	_hop(cp0, f0, Vector3(0, 0, 0.8))
	if route_variant == 2:
		r_jump(_w(Vector3(1.6, 0, -10.65)), _w(js["c"]))
		r_pad(_w(js["c"]), _w(Vector3(0.6, 5.8, -15.4)))
	else:
		_wait(func() -> bool: return _resting(ja, 0.0, 1.8))
		r_jump(_w(Vector3(0, 0, -7.3)), _w(Vector3(0, 1.4, -9.6)))
		_kick(Vector3(0, 1.4, -9.6), Vector3(0, 5.8, -15.0))
	_wait(func() -> bool: return _resting(jb, 0.0, 1.8))
	r_jump(_w(Vector3(0, 5.8, -15.4)), _w(Vector3(0, 7.2, -18.0)))
	_kick(Vector3(0, 7.2, -18.0), Vector3(0, 12.0, -24.4))
	_hop(sh2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the toy cupboard: tall painted side panels, toy blocks and a ball on the shelves
	for sx: float in [-1.0, 1.0]:
		var side := Look.box(_sz(Vector3(0.6, 26.0, 26.0)), Look.flat(Color(0.98, 0.9, 0.8), 0.7), _w(Vector3(sx * 6.4, 2.0, -18.0)))
		add_child(side)
		add_child(Look.box(_sz(Vector3(0.7, 0.5, 26.4)), Look.flat(PINK if sx < 0.0 else MINT, 0.5), _w(Vector3(sx * 6.4, 15.2, -18.0))))
	deco.toy_block(_w(Vector3(-1.6, 5.8, -18.6)), 0.9, CHERRY, 0.4)
	deco.toy_block(_w(Vector3(1.5, 12.0, -26.4)), 0.8, LEMON, -0.3)
	deco.toy_block(_w(Vector3(-2.2, 0, -10.2)), 1.0, MINT, 0.1)
	_choco(Vector3(0, -5.0, -20.0), 12.0, 30.0)
	return cp["c"]


# ---- stage 5: Jelly Pond (BRANCH) - three jellies climbing over the pond, or the block and wafer ----

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (pink): the jelly steps
	var j1: Dictionary = _jelly(Vector3(-3.5, -1.5, -15.5), 1.6, PINK)
	var j2: Dictionary = _jelly(Vector3(-3.5, 1.5, -23.5), 1.6, GRAPE)
	var j3: Dictionary = _jelly(Vector3(-3.5, 3.0, -32.5), 1.6, SKY)
	# RIGHT (mint): mantle the block, run the wafer, drop off the wafer's foot
	_ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 7.3, 3.2), "alt")
	kit.wallrun(_w(Vector3(6.5, 4.5, -24.7)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(3.8, 4.4, -36.0), 3.6, 4.0, "alt")
	var merge: Dictionary = _blk(Vector3(0, 5.0, -42.5), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 5.0, -52.0))
	deco.wafer(_w(Vector3(7.3, 3.5, -24.7)), _sz(Vector3(0.9, 12.0, 17.0)), 0.0)
	_sign(Vector3(-3.5, 0, -6.6), PINK)
	_sign(Vector3(4.0, 0, -6.6), MINT)
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.4)))
		r_jump(_w(Vector3(-3.5, 0, -9.65)), _w(j1["c"]))
		r_pad(_w(j1["c"]), _w(j2["c"]))
		r_pad(_w(j2["c"]), _w(j3["c"]))
		r_pad(_w(j3["c"]), _w(Vector3(-3.0, 5.0, -41.8)))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(4.3, 3.3, -14.85)), _w(Vector3(6.0, 4.7, -18.8)), _w(Vector3(6.0, 4.7, -29.7)), _w(Vector3(3.8, 4.4, -35.3)))
		_hop(l2, merge, Vector3(2.0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_choco(Vector3(-2.0, -5.0, -26.0), 16.0, 34.0)
	for z: float in [-14.0, -26.0, -38.0]:
		deco.lollipop_tree(_w(Vector3(-10.0, -5.0, z)), 12.0, 2.0, [LEMON, PINK, SKY][int(-z) % 3])
	return cp["c"]


# ---- stage 6: Melting Parlor - melting scoops, the sugar-glass beam, a sprinkle boost -------------

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var sp: Array[Vector3] = [Vector3(0, 0, -8.2), Vector3(0.6, 0.6, -13.8), Vector3(-0.5, 1.2, -19.4)]
	var scol: Array[Color] = [PINK, MINT, LEMON]
	for i: int in sp.size():
		_scoop(sp[i], scol[i])
	var br: Dictionary = _blk(Vector3(0, 1.2, -28.2), 2.4, 8.4, "alt", 0.8)
	var beam: LaserGate = _beam(Vector3(0, 1.2, -28.0), 2.4, 4.0, 0.35, 0.0)
	kit.boost(_w(Vector3(0, 1.2, -34.2)), Vector3(2.4, 0.4, 3.6), _yaw, 16.0)
	kit.block(_w(Vector3(0, 0.6, -34.2)), _sz(Vector3(2.4, 0.8, 3.6)), Color(1.0, 0.85, 0.9), false)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -48.5))
	_hop(cp0, _area(sp[0], 1.1, 1.1))
	_hop(_area(sp[0], 1.1, 1.1), _area(sp[1], 1.1, 1.1))
	_hop(_area(sp[1], 1.1, 1.1), _area(sp[2], 1.1, 1.1))
	_hop(_area(sp[2], 1.1, 1.1), br, Vector3(0, 0, 2.6))
	r_walk(_w(Vector3(0, 1.2, -26.4)))
	_wait(func() -> bool: return _dark(beam, 0.05, 1.8))
	r_walk(_w(Vector3(0, 1.2, -33.0)))
	r_jump(_w(Vector3(0, 1.2, -35.75)), _w(Vector3(0, 1.2, -47.0)))
	route[route.size() - 1]["speed"] = 16.0
	r_checkpoint()
	# the parlour: striped awning posts, giant cones, sprinkles raining off the boost
	for sx: float in [-1.0, 1.0]:
		deco.ice_cream(_w(Vector3(sx * 6.0, -8.0, -12.0)), 7.0, PINK if sx < 0.0 else MINT, LEMON)
		deco.candy_cane(_w(Vector3(sx * 1.0, 1.2, -24.4)), 4.0, 0.14, deg_to_rad(_yaw) + (PI if sx > 0.0 else 0.0))
	CandyFx.sprinkles(self, _w(Vector3(0, 4.0, -40.0)), _sz(Vector3(3.0, 3.0, 6.0)), 40)
	_choco(Vector3(0, -4.0, -24.0), 14.0, 44.0)
	cp0.clear()
	return cp["c"]


## A melting ice-cream scoop: a collapsing platform with a dome of ice cream on it and drips below.
func _scoop(c: Vector3, col: Color) -> void:
	var cp: CollapsingPlatform = kit.collapse(_w(c), 2.2, 0.5, 2.4)
	var dome := Look.sphere(1.1, Look.flat(col, 0.6), Vector3(0, -0.32, 0))
	dome.scale = Vector3(1.0, 0.35, 1.0)
	cp.add_child(dome)
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0 + 0.3
		var drip := Look.sphere(0.14, Look.flat(col, 0.6), Vector3(cos(a) * 1.02, -0.45, sin(a) * 1.02))
		drip.scale = Vector3(0.8, 2.0, 0.8)
		cp.add_child(drip)
	CandyFx.sift(self, _w(c) + Vector3(0, -0.8, 0), 6.0, 10)


# ---- stage 7: Taffy Pull - sagging taffy bridges, the boxing gloves --------------------------------

func _stage_7() -> Vector3:
	var along_x: bool = absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0
	var opts: Dictionary = {"tilt_about_x": along_x, "tilt_about_z": not along_x, "edge_tilt_deg": 9.0, "max_tilt_deg": 14.0, "sink_depth": 0.35}
	kit.tilt(_w(Vector3(0, 0, -9.5)), _sz(Vector3(2.4, 0.4, 7.0)), opts)
	kit.tilt(_w(Vector3(0, 0.4, -19.5)), _sz(Vector3(2.4, 0.4, 7.0)), opts)
	var f: Dictionary = _blk(Vector3(0, 0.8, -31.0), 3.0, 10.0, "alt")
	var p0: Piston = _glove(Vector3(3.2, 2.1, -29.0), 90.0, 3.0, 5.0, 0.0)
	kit.block(_w(Vector3(4.6, 1.6, -29.0)), Vector3(2.4, 3.0, 2.2), Color(1.0, 0.85, 0.3), true, _yaw)
	var p1: Piston = _glove(Vector3(-3.2, 2.1, -33.0), -90.0, 3.0, 5.0, 0.9)
	kit.block(_w(Vector3(-4.6, 1.6, -33.0)), Vector3(2.4, 3.0, 2.2), Color(0.5, 0.8, 1.0), true, _yaw)
	var cp: Dictionary = _cp(Vector3(0, 0.8, -43.0))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -7.2)))
	r_walk(_w(Vector3(0, 0, -12.4)))
	r_jump(_w(Vector3(0, 0, -12.6)), _w(Vector3(0, 0.4, -17.2)))
	r_walk(_w(Vector3(0, 0.4, -22.4)))
	r_jump(_w(Vector3(0, 0.4, -22.6)), _w(Vector3(0, 0.8, -27.0)))
	_wait(func() -> bool: return _ram_clear(p0, 0.0, 0.7) and _ram_clear(p1, 0.4, 1.3), _w(Vector3(0, 0.8, -27.0)))
	r_walk(_w(Vector3(0, 0.8, -35.2)))
	_hop(f, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# taffy: pulled ropes of pink and mint looping down from each bridge, posts of striped candy
	for z: float in [-6.0, -13.0, -16.0, -23.0]:
		for sx: float in [-1.0, 1.0]:
			deco.candy_cane(_w(Vector3(sx * 1.5, -6.0, z)), 3.8 + (0.4 if z < -14.0 else 0.0), 0.16, deg_to_rad(_yaw) + (PI if sx > 0.0 else 0.0))
	_choco(Vector3(0, -6.0, -24.0), 14.0, 40.0)
	return cp["c"]


# ---- stage 8: Cookie Press - the cookie belt under two stamps [shortcut: run the oven wall] -------

func _stage_8() -> Vector3:
	kit.conveyor(_w(Vector3(0, 0, -16.0)), Vector3(2.8, 0.4, 20.0), _yaw, 4.0)
	kit.block(_w(Vector3(0, -1.0, -16.0)), _sz(Vector3(2.4, 1.6, 19.6)), Color(0.5, 0.3, 0.16), false)
	var p1: Crusher = _press(Vector3(0, 0, -12.0), Vector3(3.2, 1.4, 3.0), 3.4, 4.0, 0.0)
	var p2: Crusher = _press(Vector3(0, 0, -20.0), Vector3(3.2, 1.4, 3.0), 3.4, 4.0, 0.85)
	var top: Dictionary = _ledge(Vector3(0, 3.3, -30.5), Vector3(4.0, 7.3, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -40.0))
	# SHORTCUT: the oven wall - a wall-run panel along the belt's left, clear of the stamps' frames
	kit.wallrun(_w(Vector3(-3.6, 2.0, -18.0)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	deco.choco_bar(_w(Vector3(-4.3, 2.0, -18.0)), _sz(Vector3(0.8, 7.5, 17.0)), 0.0)
	if route_variant == 2:
		r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -6.6)))
		r_wallrun(_w(Vector3(-0.6, 0, -7.6)), _w(Vector3(-3.0, 1.4, -12.6)), _w(Vector3(-3.0, 1.4, -23.4)), _w(Vector3(0, 3.3, -30.0)))
	else:
		r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -7.0)))
		_wait(func() -> bool: return _press_ok(p1, 0.1, 0.8) and _press_ok(p2, 0.6, 1.4), _w(Vector3(0, 0, -7.4)))
		r_walk(_w(Vector3(0, 0, -25.0)))
		r_mantle(_w(Vector3(0, 0, -25.6)), _w(Vector3(0, 3.3, -30.1)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the bakery: a gingerbread oven wall behind the stamps, cookie stacks and sugar dust
	for z: float in [-8.0, -24.0]:
		deco.cake(_w(Vector3(4.6, -2.0, z)), 1.4, 3, [PINK, SKY][int(-z) % 2])
	CandyFx.sparkles(self, _w(Vector3(0, 3.0, -16.0)), _sz(Vector3(3.0, 2.5, 10.0)), 30, Color(2.2, 2.0, 1.6))
	_choco(Vector3(0, -5.0, -20.0), 14.0, 34.0)
	return cp["c"]


# ---- stage 9: Candyfloss Clouds (BRANCH) - the cloud wave, or the jelly, the gift box and its portal --

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (sky): four candyfloss clouds that puff away and back, one after another
	var mz: Array[Vector3] = [Vector3(-3.5, 0.0, -16.0), Vector3(-3.5, 0.6, -22.05), Vector3(-2.4, 1.2, -27.95), Vector3(-3.4, 1.2, -35.0)]
	var clouds: Array[BlinkPlatform] = []
	for i: int in mz.size():
		clouds.append(kit.blink(_w(mz[i]), _sz(Vector3(2.1, 0.5, 2.1)), 4.0, 0.6, fposmod(-0.1875 * float(i), 1.0)))
		CandyFx.candyfloss(self, _w(mz[i] + Vector3(0, -0.8, 0)), Vector3(1.4, 0.4, 1.4), 5)
	var merge: Dictionary = _blk(Vector3(0, 1.2, -42.8), 12.0, 4.0)
	# RIGHT (lemon): a jelly up onto the gift box, and the gift box's portal
	var jr: Dictionary = _jelly(Vector3(3.5, 0, -14.0), 1.4, LEMON)
	var gift: Dictionary = _blk(Vector3(3.5, 5.0, -20.5), 3.0, 3.0, "accent", 3.0)
	var portal: WarpPortal = kit.portal(_w(Vector3(3.5, 5.0, -21.3)), _yaw, _w(Vector3(2.5, 1.2, -41.4)), _yaw, 7.0)
	_arrival(Vector3(2.5, 1.2, -42.0), LEMON)
	_gift_bow(Vector3(3.5, 5.0, -20.5), 3.0, CHERRY)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -51.3))
	_sign(Vector3(-3.5, 0, -6.6), SKY)
	_sign(Vector3(3.5, 0, -6.6), LEMON)
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.4)))
		var starts: Array[float] = [0.6, 1.35, 2.1, 2.85]
		_wait(func() -> bool:
			for i: int in clouds.size():
				if not _blink_ok(clouds[i], starts[i] - 0.1, starts[i] + 0.55):
					return false
			return true)
		var prev: Dictionary = _area(Vector3(-3.5, 0, -8.0), 1.5, 2.0)
		for i: int in mz.size():
			var m: Dictionary = _area(mz[i], 1.05, 1.05)
			_hop(prev, m)
			prev = m
		_hop(prev, merge, Vector3(-3.0, 0, 0.8))
	else:
		r_walk(_w(Vector3(3.5, 0, -8.6)))
		r_jump(_w(Vector3(3.5, 0, -9.65)), _w(jr["c"]))
		r_pad(_w(jr["c"]), _w(Vector3(3.5, 5.0, -19.7)))
		r_portal(_w(Vector3(3.5, 5.0, -21.5)), portal.exit_point())
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	gift.clear()
	# candyfloss cloud banks drifting under the clouds
	CandyFx.candyfloss(self, _w(Vector3(-3.5, -3.0, -26.0)), _sz(Vector3(5.0, 2.0, 12.0)), 16)
	_choco(Vector3(0, -6.0, -26.0), 16.0, 40.0)
	return cp["c"]


## A ribbon and bow round a gift box (a slab whose top is at local `top`, `s` wide).
func _gift_bow(top: Vector3, s: float, col: Color) -> void:
	var rib: StandardMaterial3D = CandyDecor.gloss(col)
	var a := Look.box(_sz(Vector3(0.4, 3.02, s + 0.04)), rib, _w(top - Vector3(0, 1.5, 0)))
	add_child(a)
	var b := Look.box(_sz(Vector3(s + 0.04, 3.02, 0.4)), rib, _w(top - Vector3(0, 1.5, 0)))
	add_child(b)
	for sx: float in [-1.0, 1.0]:
		var loop := Look.sphere(0.4, rib, _w(top + Vector3(sx * 0.9, 0.05, s * 0.5 - 0.2)))
		loop.scale = Vector3(1.4, 0.5, 0.7)
		add_child(loop)


## A burst of confetti and glitter where a portal lets you out (fired when you arrive).
func _arrival(at: Vector3, col: Color) -> void:
	var p: GPUParticles3D = CandyFx.confetti(1.0, 40, 6.0)
	p.position = _w(at + Vector3(0, 0.6, 0))
	add_child(p)
	var g: GPUParticles3D = Fx.burst({"amount": 30, "lifetime": 1.0, "shape": "sphere", "radius": 0.5, "tex": Fx.Tex.STAR,
		"size": 0.3, "speed": Vector2(2.0, 4.0), "curve": "pop", "color": Fx.hot(col, 2.2),
		"aabb": AABB(Vector3(-6, -3, -6), Vector3(12, 10, 12))})
	g.position = _w(at + Vector3(0, 1.0, 0))
	add_child(g)
	_arrivals.append({"at": _w(at), "p": [p, g], "cool": 0.0})
	CandyFx.rising(self, _w(at), 1.2, 2.5, 14)


# ---- stage 10: SUGAR RUSH EXPRESS - the toy railway ---------------------------------------------

var _t1: CandyTrain
var _t2: CandyTrain


func _stage_10() -> Vector3:
	# station A: a long frosted platform beside the first line
	_blk(Vector3(0.9, 0, -14.0), 3.4, 22.0, "main", 1.0)
	# the two lines: each a rounded rectangle loop, riding straight down the station side. Line 1
	# loops away to the right, line 2 (4 m to the left of line 1) away to the left; they run side by
	# side for 27 m (z -43..-70), their trains in step, so you can hop across between them.
	var f: Vector3 = _d(Vector3(0, 0, -1))
	_t1 = CandyTrain.new()
	_t1.path = CandyTrain.rect(_w(Vector3(4.2, 0, -10.0)), f, 60.0, 36.0, 1.0, 15.0, 6.0)
	_t1.speed = 7.0
	_t1.trains = 3
	_t1.wagons = 3
	_t1.offset = 0.0
	_t1.engine_color = CHERRY
	_t1.ground_y = SEA_Y
	add_child(_t1)
	_t2 = CandyTrain.new()
	_t2.path = CandyTrain.rect(_w(Vector3(0.2, 0, -43.0)), f, 60.0, 36.0, -1.0, 15.0, 5.0)
	_t2.speed = 7.0
	_t2.trains = 3
	_t2.wagons = 3
	_t2.offset = -33.0
	_t2.engine_color = Color(0.3, 0.6, 1.0)
	_t2.wagon_colors = PackedColorArray([Color(1.0, 0.6, 0.8), Color(0.7, 1.0, 0.6), Color(1.0, 0.8, 0.5)])
	_t2.ground_y = SEA_Y
	add_child(_t2)
	_t1.whistle_at = 0.0
	_t2.whistle_at = 50.0
	# station B beside line 2, far down the lake; the checkpoint just past it
	_blk(Vector3(3.6, 0, -97.0), 3.6, 20.0, "main", 1.0)
	var cp: Dictionary = _cp(Vector3(4.6, 0, -110.0))
	_station_dress(Vector3(0.9, 0, -14.0), 22.0, -1.0)
	_station_dress(Vector3(3.6, 0, -97.0), 20.0, 1.0)
	_keep_out.append(Vector4(_w(Vector3(20.0, 0, -40.0)).x, 0.0, _w(Vector3(20.0, 0, -40.0)).z, 32.0))
	_keep_out.append(Vector4(_w(Vector3(-16.0, 0, -75.0)).x, 0.0, _w(Vector3(-16.0, 0, -75.0)).z, 34.0))
	var o: Vector3 = _o
	var inv: Basis = _b.inverse()
	var t1w: Array = []
	for list: Array in _t1.wagons_by_train:
		t1w.append_array(list)
	var t2w: Array = []
	for list2: Array in _t2.wagons_by_train:
		t2w.append_array(list2)
	r_walk(_w(Vector3(1.2, 0, -8.0)))
	r_walk(_w(Vector3(2.2, 0, -14.0)))
	route.append({"kind": "candy_board", "from": _w(Vector3(2.2, 0, -14.0)), "cars": t1w, "reach": 2.4, "lead": 0.45, "local": Vector3(0, 0.1, 0.4)})
	route.append({"kind": "candy_ride", "stand": Vector3(-0.3, 0.1, 0.0), "cars": t2w, "local": Vector3(0, 0.1, 0.4), "until": func() -> bool:
		return (inv * (player.global_position - o)).z < -50.0})
	route.append({"kind": "candy_ride", "stand": Vector3(0.3, 0.1, 0.0), "to": _w(Vector3(3.6, 0, -100.5)), "until": func() -> bool:
		return (inv * (player.global_position - o)).z < -92.0})
	r_walk(_w(Vector3(4.2, 0, -104.0)))
	r_walk(_w(Vector3(4.6, 0, -110.0)))
	r_checkpoint()
	# the lake the lines cross, and candy islands in it
	CandyFx.sprinkles(self, _w(Vector3(2.0, 6.0, -55.0)), _sz(Vector3(8.0, 5.0, 40.0)), 90)
	CandyFx.bubbles(self, _w(Vector3(2.0, 2.0, -60.0)), _sz(Vector3(14.0, 6.0, 40.0)), 40)
	return cp["c"]


## Station dressing: a striped awning on candy-cane posts along the platform's far side (`side`
## = which side of the platform the posts stand on, away from the track), lamps and a sign.
func _station_dress(c: Vector3, length: float, side: float) -> void:
	var hx: float = 1.7
	var n: int = int(length / 5.0)
	for i: int in n + 1:
		var z: float = c.z + length * 0.5 - float(i) * length / float(n)
		deco.candy_cane(_w(Vector3(c.x + side * hx, c.y, z)), 4.2, 0.13, deg_to_rad(_yaw) + (PI if side > 0.0 else 0.0))
	for i: int in 6:
		var stripe := Look.box(_sz(Vector3(1.4, 0.12, length / 6.0 - 0.05)), Look.flat(PINK if i % 2 == 0 else CREAM, 0.6), _w(Vector3(c.x + side * (hx - 0.7), c.y + 4.3, c.z + length * 0.5 - (float(i) + 0.5) * length / 6.0)))
		add_child(stripe)
	for i: int in 3:
		kit.lamp(_w(Vector3(c.x + side * (hx - 0.2), c.y, c.z + length * 0.35 - float(i) * length * 0.35)), 2.8, i == 1, LEMON)


# ---- stage 11: Gumball Chute - up the chute while the gumballs roll down it ----------------------

var _gum: CandyGumball


func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	# the chute: a ramp rising 8 m over 40 m between wafer walls, alcoves on its right
	var pitch: float = rad_to_deg(atan(8.0 / 40.0))
	var rl: float = sqrt(40.0 * 40.0 + 8.0 * 8.0)
	kit.ramp(_w(Vector3(0, 4.0, -26.6)), Vector3(3.4, 0.6, rl), pitch, _yaw, "alt")
	var alc: Array[float] = [-17.0, -29.0]
	_chute_walls(pitch, rl, alc)
	for z: float in alc:
		var y: float = (-z - 6.6) * 0.2
		_blk(Vector3(3.2, y, z), 3.0, 3.2, "accent", 0.6)
	var ex: Dictionary = _blk(Vector3(3.9, 7.1, -42.2), 3.4, 4.4, "accent", 0.8)
	var cp: Dictionary = _cp(Vector3(9.8, 7.1, -47.0))
	# the gumballs: out of the machine's mouth, down the chute, over the lip and down the drain
	var g := CandyGumball.new()
	var pts := PackedVector3Array()
	for lp: Vector3 in [Vector3(0, 9.5, -48.8), Vector3(0, 9.6, -46.6), Vector3(0, 1.6, -6.6), Vector3(0, 1.1, -5.4), Vector3(0, -0.6, -4.9), Vector3(0, -8.0, -4.8)]:
		pts.append(_w(lp))
	g.path = pts
	g.radius = 1.5
	g.speed = 7.0
	g.interval = 8.0
	g.phase = 0.0
	add_child(g)
	_gum = g
	deco.gumball_machine(_w(Vector3(0, 3.1, -53.0)), 1.2, deg_to_rad(_yaw))
	kit.plat(_w(Vector3(0, 3.1, -53.0)), Vector3(10.0, 1.0, 10.0), "alt", -1.0, _yaw)
	# the drain the gumballs drop into (between the checkpoint and the chute's lip)
	var drain := Look.cylinder(1.9, 3.0, Look.flat(Color(0.9, 0.3, 0.45), 0.4), _w(Vector3(0, -6.2, -4.8)), 2.4, 20)
	add_child(drain)
	_keep_out.append(Vector4(_w(Vector3(0, 0, -30.0)).x, 0.0, _w(Vector3(0, 0, -30.0)).z, 30.0))
	var gum: CandyGumball = g
	# the chute's centre line in world space, every 2 m (built now: _w() follows the build frame)
	var line: Dictionary = {}
	var zz: float = -6.0
	while zz >= -44.0:
		line[zz] = _w(Vector3(0, maxf((-zz - 6.6) * 0.2, 0.0) + 1.5, zz))
		zz -= 2.0
	var seg_clear := func(z0: float, z1: float, t: float) -> bool:
		for key: float in line.keys():
			if key <= z0 + 0.01 and key >= z1 - 0.01 and not gum.clear_near(line[key], 0.6, 0.0, t):
				return false
		return true
	_wait(func() -> bool: return bool(seg_clear.call(-6.0, -18.0, 3.0)))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0.3, -8.2)))
	r_walk(_w(Vector3(0.6, 1.8, -15.6)))
	r_walk(_w(Vector3(3.2, 2.1, -17.0)))
	_wait(func() -> bool: return bool(seg_clear.call(-15.0, -30.0, 2.6)), _w(Vector3(3.3, 2.1, -17.0)))
	r_walk(_w(Vector3(0.7, 2.1, -17.3)))
	r_walk(_w(Vector3(0.6, 4.2, -27.8)))
	r_walk(_w(Vector3(3.2, 4.5, -29.0)))
	_wait(func() -> bool: return bool(seg_clear.call(-27.0, -43.0, 2.8)), _w(Vector3(3.3, 4.5, -29.0)))
	r_walk(_w(Vector3(0.7, 4.5, -29.3)))
	r_walk(_w(Vector3(0.6, 6.8, -40.6)))
	r_walk(_w(Vector3(3.6, 7.1, -42.0)))
	_hop(ex, cp, Vector3(-1.2, 0, 0.8))
	r_checkpoint()
	cp0.clear()
	CandyFx.sparkles(self, _w(Vector3(0, 6.0, -28.0)), _sz(Vector3(4.0, 4.0, 18.0)), 40)
	_choco(Vector3(0, -8.0, -24.0), 20.0, 44.0)
	return cp["c"]


## The chute's side walls: solid wafer slabs following the slope, the right one broken by the
## alcoves and the exit at the top.
func _chute_walls(pitch: float, rl: float, alc: Array[float]) -> void:
	var cuts: Array[Vector2] = []
	for z: float in alc:
		cuts.append(Vector2(z + 1.6, z - 1.6))
	cuts.append(Vector2(-40.0, -46.6))
	# left wall: one slab along the whole chute
	_slope_slab(-1.95, -6.6, -46.6, pitch)
	# right wall: slabs between the openings
	var z0: float = -6.6
	for c: Vector2 in cuts:
		if z0 - c.x > 0.3:
			_slope_slab(1.95, z0, c.x, pitch)
		z0 = c.y
	# alcove back and side walls
	for z: float in alc:
		var y: float = (-z - 6.6) * 0.2
		_wall(Vector3(4.95, y + 1.4, z), Vector3(0.5, 3.4, 3.8))
		for s: float in [-1.0, 1.0]:
			_wall(Vector3(3.3, y + 1.4, z + s * 1.85), Vector3(3.4, 3.4, 0.4))


## A wall slab along the chute at local x from z0 down to z1 (z0 > z1), 3 m above the ramp.
func _slope_slab(x: float, z0: float, z1: float, pitch: float) -> void:
	var len: float = (z0 - z1) / cos(deg_to_rad(pitch))
	var zc: float = (z0 + z1) * 0.5
	var yc: float = (-zc - 6.6) * 0.2 + 1.2
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 3.6, len)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.box(Vector3(0.5, 3.6, len), CandyDecor.waffle_material(true, Color(0.95, 0.78, 0.5), 0.35)))
	body.add_child(Look.box(Vector3(0.6, 0.18, len), Look.flat(PINK, 0.5), Vector3(0, 1.85, 0)))
	body.rotation_degrees = Vector3(pitch, _yaw, 0)
	body.position = _w(Vector3(x, yc, zc))
	add_child(body)


## A solid block of wafer (the camera leans on it).
func _wall(c: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.box(size, CandyDecor.waffle_material(true, Color(0.95, 0.78, 0.5), 0.35)))
	body.rotation.y = deg_to_rad(_yaw)
	body.position = _w(c)
	add_child(body)


# ---- stage 12: Wafer Chimney - a jack up to the chimney, three wall runs, a mantle out -----------

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f: Dictionary = _blk(Vector3(0, 0, -9.6), 5.0, 6.0, "alt", 1.2)
	var ja: CandyJack = _jack(Vector3(0, 1.4, -9.8), 3.2, 0.3, Vector3(0, 19, -2.5), PINK)
	_blk(Vector3(0, 6.0, -15.2), 3.0, 3.0, "main", 1.2)
	_chimney_panel(2.3, 7.2, -19.5, -26.0)
	_chimney_panel(-2.3, 12.0, -24.5, -32.5)
	_chimney_panel(2.3, 15.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 17.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 17.9, -51.2))
	_hop(cp0, f, Vector3(0, 0, 1.6))
	_wait(func() -> bool: return _resting(ja, 0.0, 1.8))
	r_jump(_w(Vector3(0, 0, -8.0)), _w(Vector3(0, 1.4, -9.8)))
	_kick(Vector3(0, 1.4, -9.8), Vector3(0, 6.0, -14.8))
	r_walk(_w(Vector3(0, 6.0, -13.9)))
	r_wallrun(_w(Vector3(0.5, 6.0, -15.85)), _w(Vector3(1.7, 7.4, -20.6)), _w(Vector3(1.7, 7.4, -23.5)), _w(Vector3(-1.7, 11.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 11.5, -27.4)), _w(Vector3(-1.7, 11.5, -30.4)), _w(Vector3(1.7, 14.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 14.5, -34.0)), _w(Vector3(1.7, 14.5, -35.4)), _w(Vector3(-0.75, 17.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	CandyFx.sparkles(self, _w(Vector3(0, 12.0, -28.0)), _sz(Vector3(2.0, 8.0, 10.0)), 40, Color(2.4, 1.8, 1.2))
	CandyFx.bubbles(self, _w(Vector3(0, 8.0, -28.0)), _sz(Vector3(3.0, 6.0, 12.0)), 20)
	_choco(Vector3(0, -6.0, -24.0), 12.0, 40.0)
	return cp["c"]


## A chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by a wafer slab.
func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	deco.wafer(_w(Vector3(x + signf(x) * 0.55, y, (z0 + z1) * 0.5)), _sz(Vector3(0.6, height + 2.0, absf(z0 - z1) + 1.0)), 0.0)


# ---- stage 13: Toy Parade (BRANCH) - the parade ground, or the jack balcony [shortcut: jellies] ----

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -7.5), 10.0, 3.0)
	# LEFT (cherry): the parade ground and its three drummers marching across it
	_blk(Vector3(-2.8, 0, -25.0), 3.0, 32.0, "alt")
	var lanes: Array[float] = [-15.0, -23.0, -31.0]
	var sol: Array[CandySoldier] = []
	var coats: Array[Color] = [CHERRY, SKY, GRAPE]
	for i: int in lanes.size():
		kit.plat(_w(Vector3(-6.4, 0, lanes[i])), _sz(Vector3(4.2, 0.6, 1.4)), "alt", 0.8, _yaw)
		kit.plat(_w(Vector3(-0.75, 0, lanes[i])), _sz(Vector3(1.1, 0.6, 1.4)), "alt", 0.8, _yaw)
		sol.append(_soldier(Vector3(-8.0, 0, lanes[i]), Vector3(7.5, 0, 0), 10.0, [0.0, 0.33, 0.66][i], coats[i]))
	var merge: Dictionary = _blk(Vector3(0, 0, -42.5), 10.0, 3.0)
	# RIGHT (lemon): the balcony - two jacks throwing you forward along it
	_blk(Vector3(3.2, 0, -11.4), 2.6, 2.6, "alt")
	var ja: CandyJack = _jack(Vector3(3.2, 1.4, -11.4), 3.0, 0.0, Vector3(0, 16, -7), LEMON)
	_blk(Vector3(3.2, 2.0, -22.5), 3.0, 5.0, "alt")
	var jb: CandyJack = _jack(Vector3(3.2, 3.4, -23.6), 3.0, 0.5, Vector3(0, 16, -7), ORANGE)
	var p3: Dictionary = _blk(Vector3(3.2, 2.0, -33.5), 3.0, 4.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 0, -51.5))
	# SHORTCUT: three jellies down in the chocolate between the routes
	var js1: Dictionary = _jelly(Vector3(0.9, -6.0, -17.0), 1.6, MINT)
	var js2: Dictionary = _jelly(Vector3(0.9, -4.0, -26.0), 1.6, PINK)
	var js3: Dictionary = _jelly(Vector3(0.9, -2.0, -35.0), 1.6, LEMON)
	_sign(Vector3(-2.8, 0, -6.4), CHERRY)
	_sign(Vector3(3.2, 0, -6.4), LEMON)
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant == 2:
		r_jump(_w(Vector3(0.9, 0, -8.65)), _w(js1["c"]))
		r_pad(_w(js1["c"]), _w(js2["c"]))
		r_pad(_w(js2["c"]), _w(js3["c"]))
		r_pad(_w(js3["c"]), _w(Vector3(0.6, 0, -42.0)))
	elif route_variant != 1:
		r_walk(_w(Vector3(-2.8, 0, -8.4)))
		var holds: Array[float] = [-12.8, -20.8, -28.8]
		for i: int in lanes.size():
			var s: CandySoldier = sol[i]
			var x: Vector3 = _w(Vector3(-2.8, 0, lanes[i]))
			r_walk(_w(Vector3(-2.8, 0, holds[i])))
			_wait(func() -> bool: return s.lane_clear(x, 1.7, 0.0, 2.0))
		r_walk(_w(Vector3(-2.8, 0, -36.6)))
		r_walk(_w(Vector3(-1.6, 0, -40.6)))
	else:
		r_walk(_w(Vector3(3.2, 0, -8.2)))
		_wait(func() -> bool: return _resting(ja, 0.0, 1.8))
		r_jump(_w(Vector3(3.2, 0, -8.65)), _w(Vector3(3.2, 1.4, -11.4)))
		_kick(Vector3(3.2, 1.4, -11.4), Vector3(3.2, 2.0, -21.0))
		_wait(func() -> bool: return _resting(jb, 0.0, 1.8))
		r_jump(_w(Vector3(3.2, 2.0, -21.2)), _w(Vector3(3.2, 3.4, -23.6)))
		_kick(Vector3(3.2, 3.4, -23.6), Vector3(3.2, 2.0, -32.4))
		_hop(p3, merge, Vector3(1.5, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_choco(Vector3(0, -7.0, -26.0), 22.0, 40.0)
	for sx: float in [-1.0, 1.0]:
		deco.toy_block(_w(Vector3(sx * 8.5, 0, -8.0)), 1.6, [CHERRY, SKY][int(sx + 1.0) >> 1], 0.2 * sx)
	return cp["c"]


# ---- stage 14: Lollipop Swings - giant lollipops swinging across the gaps, melting scoops ---------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var ps: Array[Vector3] = [Vector3(0, 0, -8.2), Vector3(0.4, 0.6, -14.3), Vector3(-0.4, 1.2, -20.4)]
	var stones: Array[Dictionary] = []
	for i: int in ps.size():
		stones.append(_blk(ps[i], 2.2, 2.2, "alt"))
	# a lollipop swinging across each gap (between the checkpoint and stone 1, and so on)
	var gaps: Array[float] = [-5.05, -11.25, -17.35]
	var gy: Array[float] = [0.0, 0.3, 0.9]
	var swings: Array[Pendulum] = []
	var phases: Array[float] = [0.0, 0.33, 0.66]
	var cols: Array[Color] = [PINK, SKY, MINT]
	for i: int in gaps.size():
		swings.append(_swing(Vector3(0, gy[i] + 10.4, gaps[i]), 8.8, 6.0, phases[i], cols[i]))
	_scoop(Vector3(0.6, 1.2, -26.2), LEMON)
	_scoop(Vector3(-0.4, 1.8, -31.6), GRAPE)
	var cp: Dictionary = _cp(Vector3(0, 1.8, -40.2))
	var prev: Dictionary = cp0
	for i: int in stones.size():
		var sw: Pendulum = swings[i]
		_wait(func() -> bool: return _swing_clear(sw, 0.0, 1.8))
		_hop(prev, stones[i])
		prev = stones[i]
	_hop(stones[2], _area(Vector3(0.6, 1.2, -26.2), 1.1, 1.1))
	_hop(_area(Vector3(0.6, 1.2, -26.2), 1.1, 1.1), _area(Vector3(-0.4, 1.8, -31.6), 1.1, 1.1))
	_hop(_area(Vector3(-0.4, 1.8, -31.6), 1.1, 1.1), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_choco(Vector3(0, -5.0, -20.0), 16.0, 40.0)
	for z: float in [-6.0, -18.0, -30.0]:
		for sx: float in [-1.0, 1.0]:
			deco.lollipop_tree(_w(Vector3(sx * 11.0, -5.0, z)), 12.0 + kit.rng.randf_range(-2.0, 2.0), 2.0, deco.pick_pastel())
	return cp["c"]


## A giant lollipop on a candy-cane stick, swinging across the route from a frame above.
func _swing(pivot: Vector3, length: float, period: float, phase: float, col: Color) -> Pendulum:
	var p: Pendulum = kit.pendulum(_w(pivot), length, period, phase, _yaw, 55.0)
	var arm := p.get_child(0) as Node3D
	# swap the hammer for the lollipop: a striped stick and a big swirled disc facing the route
	(arm.get_child(0) as Node3D).visible = false
	(arm.get_child(1) as Node3D).visible = false
	arm.add_child(Look.cylinder(0.12, length, CandyDecor.stripe_material(CREAM, col, 2.0, 3.0), Vector3(0, -length * 0.5, 0), -1.0, 10))
	var disc := Look.cylinder(1.25, 0.4, CandyDecor.swirl_material(col, CREAM, 3.0, 1.25), Vector3(0, -length, 0), -1.0, 32)
	disc.rotation.x = PI * 0.5
	arm.add_child(disc)
	# the frame it hangs from: a candy-cane crossbar on two posts beside the route
	var bar := Look.cylinder(0.25, 7.0, CandyDecor.stripe_material(CHERRY, CREAM, 3.0, 2.0), _w(pivot + Vector3(0, 0.3, 0)))
	bar.rotation = Vector3(0, deg_to_rad(_yaw), PI * 0.5)
	add_child(bar)
	return p


# ---- stage 15: Rainbow Rush - a rainbow boost into a long leap, a jelly up to the checkpoint ------

func _stage_15() -> Vector3:
	kit.boost(_w(Vector3(0, 0, -8.0)), Vector3(2.6, 0.4, 10.0), _yaw, 18.0)
	kit.block(_w(Vector3(0, -0.6, -8.0)), _sz(Vector3(2.6, 0.8, 10.0)), Color(1.0, 0.9, 0.95), false)
	var r1: Dictionary = _blk(Vector3(0, 0, -28.0), 3.0, 12.0, "alt")
	var j: Dictionary = _jelly(Vector3(0, -4.0, -40.0), 1.6, ORANGE)
	var cp: Dictionary = _cp(Vector3(0, 3.0, -49.0))
	r_walk(_w(Vector3(0, 0, -3.5)))
	r_jump(_w(Vector3(0, 0, -12.65)), _w(Vector3(0, 0, -26.0)))
	route[route.size() - 1]["speed"] = 18.0
	r_walk(_w(Vector3(0, 0, -31.0)))
	_hop(r1, j)
	r_pad(_w(j["c"]), _w(Vector3(0, 3.0, -47.5)))
	r_checkpoint()
	# the rainbow: six bands running under the boost and the landing, and a rainbow arch overhead
	var cols: Array[Color] = [Color(1.0, 0.3, 0.35), Color(1.0, 0.6, 0.25), Color(1.0, 0.92, 0.35), Color(0.45, 0.9, 0.45), Color(0.4, 0.7, 1.0), Color(0.7, 0.45, 1.0)]
	for i: int in 6:
		var x: float = -1.25 + float(i) * 0.5
		var band := Look.box(_sz(Vector3(0.5, 0.3, 28.0)), Look.flat(cols[i], 0.5, 0.0, 0.5), _w(Vector3(x, -3.6, -20.0)))
		add_child(band)
	deco.rainbow(_w(Vector3(0, -4.0, -20.0)), 16.0, 0.9, deg_to_rad(_yaw))
	CandyFx.sparkles(self, _w(Vector3(0, 3.0, -20.0)), _sz(Vector3(3.0, 3.0, 14.0)), 50, Color(2.4, 2.0, 2.6))
	_choco(Vector3(0, -8.0, -28.0), 16.0, 50.0)
	r1.clear()
	return cp["c"]


# ---- stage 16: Licorice Factory - the sweeper, the belt between the gloves [shortcut: gift portal] --

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_blk(Vector3(0, 0, -10.2), 1.4, 9.4, "alt", 0.8)
	# the sweeper turns beside the walkway, its canes sweeping across it
	_blk(Vector3(1.7, 0, -10.6), 1.2, 1.2, "accent", 0.6)
	var sw: Sweeper = _cane_sweeper(Vector3(1.7, 0, -10.6), 3.0, 1, 4.4, 0.0)
	kit.conveyor(_w(Vector3(0, 0.6, -22.0)), Vector3(2.6, 0.4, 11.0), _yaw + 180.0, 4.0)
	kit.block(_w(Vector3(0, -0.4, -22.0)), _sz(Vector3(2.2, 1.6, 10.6)), Color(0.14, 0.06, 0.1), false)
	var p0: Piston = _glove(Vector3(3.2, 1.9, -20.5), 90.0, 3.0, 5.0, 0.1)
	kit.block(_w(Vector3(4.6, 1.4, -20.5)), Vector3(2.4, 3.0, 2.2), Color(1.0, 0.5, 0.7), true, _yaw)
	var p1: Piston = _glove(Vector3(-3.2, 1.9, -25.0), -90.0, 3.0, 5.0, 0.0)
	kit.block(_w(Vector3(-4.6, 1.4, -25.0)), Vector3(2.4, 3.0, 2.2), Color(0.6, 0.9, 1.0), true, _yaw)
	var e: Dictionary = _blk(Vector3(0, 0.6, -31.0), 3.0, 5.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 0.6, -41.5))
	# SHORTCUT: the gift box off the checkpoint's corner - its lid slides open and shut; inside,
	# its portal lets you out on the checkpoint
	_blk(Vector3(-4.8, 0.4, -6.4), 1.3, 1.3, "accent", 0.6)
	var door: MovingPlatform = kit.mover(_w(Vector3(-4.8, 3.4, -7.4)), _sz(Vector3(2.6, 3.0, 0.4)), [Vector3.ZERO, _d(Vector3(-3.6, 0, 0))], 6.0, 0.0)
	kit.portal(_w(Vector3(-4.8, 0.4, -7.2)), _yaw, _w(Vector3(0, 0.6, -39.6)), _yaw, 6.0)
	_arrival(Vector3(0, 0.6, -40.2), PINK)
	var box := Look.box(_sz(Vector3(3.2, 4.2, 3.2)), Look.flat(Color(0.45, 0.75, 1.0), 0.5), _w(Vector3(-4.8, 2.1 + 0.4, -9.4)))
	add_child(box)
	var rib := Look.box(_sz(Vector3(0.5, 4.25, 3.25)), CandyDecor.gloss(CHERRY), _w(Vector3(-4.8, 2.1 + 0.4, -9.4)))
	add_child(rib)
	if route_variant == 2:
		r_walk(_w(Vector3(-2.6, 0, -2.2)))
		_wait(func() -> bool: return _door_open(door, 0.4, 1.3))
		r_jump(_w(Vector3(-2.65, 0, -2.65)), _w(Vector3(-4.8, 0.4, -6.2)))
		r_portal(_w(Vector3(-4.8, 0.4, -7.4)), _w(Vector3(0, 0.6, -40.2)))
		r_walk(_w(Vector3(0, 0.6, -41.5)))
	else:
		var land1: Vector3 = _w(Vector3(0, 0, -6.2))
		_wait(func() -> bool: return _bars_far(sw, land1, 0.3, 1.0, 0.7))
		r_jump(_w(Vector3(0, 0, -2.65)), land1)
		var lane: Array[Vector3] = [_w(Vector3(0, 0, -8.0)), _w(Vector3(0, 0, -10.6)), _w(Vector3(0, 0, -13.2))]
		_wait(func() -> bool:
			for q: Vector3 in lane:
				if not _bars_far(sw, q, 0.0, 1.3, 0.8):
					return false
			return true, land1)
		route.append({"kind": "b_sweep", "to": _w(Vector3(0, 0, -14.5)), "sweeper": sw, "tol": 0.5})
		r_jump(_w(Vector3(0, 0, -14.55)), _w(Vector3(0, 0.6, -18.0)))
		_wait(func() -> bool: return _ram_clear(p0, 0.0, 0.7) and _ram_clear(p1, 0.4, 1.3), _w(Vector3(0, 0.6, -18.0)))
		r_walk(_w(Vector3(0, 0.6, -27.1)))
		r_jump(_w(Vector3(0, 0.6, -27.2)), _w(Vector3(0, 0.6, -30.0)))
		_hop(e, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	cp0.clear()
	CandyFx.sprinkles(self, _w(Vector3(0, 5.0, -22.0)), _sz(Vector3(5.0, 4.0, 14.0)), 50)
	_choco(Vector3(0, -5.0, -22.0), 16.0, 40.0)
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


## A spinning sweeper whose bars are dressed as candy canes round a peppermint hub.
func _cane_sweeper(floor_c: Vector3, arm: float, bars: int, period: float, phase: float) -> Sweeper:
	var sw: Sweeper = kit.sweeper(_w(floor_c), arm, bars, period, phase)
	var pivot: Node3D = sw.get_child(0) as Node3D
	var mat: ShaderMaterial = CandyDecor.stripe_material(CHERRY, CREAM, 3.0, 4.0)
	for holder: Node in pivot.get_children():
		var h := holder as Node3D
		var cane := Look.cylinder(0.2, arm, mat, Vector3(arm * 0.5 + 0.3, 0.45, 0), -1.0, 10)
		cane.rotation.z = PI * 0.5
		h.add_child(cane)
	var hub := Look.cylinder(0.75, 0.3, CandyDecor.swirl_material(CHERRY, CREAM, 4.0, 0.75), _w(floor_c + Vector3(0, 1.2, 0)), -1.0, 24)
	add_child(hub)
	return sw


# ---- stage 17: Jelly Tower - bounce, bounce higher, land ------------------------------------------

func _stage_17() -> Vector3:
	var j1: Dictionary = _jelly(Vector3(0, 0, -7.6), 1.6, PINK)
	var sh1: Dictionary = _blk(Vector3(0, 8.0, -13.4), 3.5, 3.5, "alt")
	var j2: Dictionary = _jelly(Vector3(0, 8.0, -19.0), 1.6, MINT)
	var sh2: Dictionary = _blk(Vector3(0, 16.0, -24.8), 3.5, 3.5, "alt")
	var cart: MovingPlatform = kit.mover(_w(Vector3(0, 16.0, -29.5)), Vector3(2.6, 0.5, 2.6), [Vector3.ZERO, _d(Vector3(0, 0, -6.0))], 6.0, 0.0)
	var cp: Dictionary = _cp(Vector3(0, 16.0, -43.0))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(j1["c"]))
	r_pad(_w(j1["c"]), _w(j1["c"]))
	r_pad(_w(j1["c"]), _w(Vector3(0, 8.0, -13.0)))
	_hop(sh1, j2)
	r_pad(_w(j2["c"]), _w(j2["c"]))
	r_pad(_w(j2["c"]), _w(Vector3(0, 16.0, -24.4)))
	r_wait(cart, _w(Vector3(0, 15.75, -29.5)), 0.6)
	r_jump_onto(_w(Vector3(0, 16.0, -26.2)), cart, Vector3(0, 0.25, 0))
	r_jump_from_ride(cart, _w(Vector3(0, 15.75, -35.5)), 0.6, _w(Vector3(0, 16.0, -41.5)))
	r_checkpoint()
	sh2.clear()
	# the tower: a stack of toy blocks behind the jellies, fairy-light garlands and bubbles
	for i: int in 5:
		deco.toy_block(_w(Vector3(-4.6, -2.0 + float(i) * 4.0, -16.0)), 4.0, [PINK, SKY, LEMON, MINT, GRAPE][i], 0.15 * float(i))
	CandyFx.bubbles(self, _w(Vector3(0, 8.0, -16.0)), _sz(Vector3(3.0, 8.0, 8.0)), 30)
	CandyFx.sparkles(self, _w(Vector3(0, 10.0, -16.0)), _sz(Vector3(3.0, 8.0, 8.0)), 40)
	_choco(Vector3(0, -6.0, -20.0), 14.0, 40.0)
	return cp["c"]


# ---- stage 18: Gumball Summit - mantle the cake, the last beam, the last jack, the finish ---------

var _machine: Node3D


func _stage_18() -> void:
	_ledge(Vector3(0, 3.3, -7.2), Vector3(6.0, 7.3, 3.4))
	_ledge(Vector3(0, 6.6, -10.6), Vector3(4.5, 10.6, 3.4), "alt")
	var p: Dictionary = _blk(Vector3(0, 6.6, -16.4), 4.0, 5.0, "alt")
	var beam: LaserGate = _beam(Vector3(0, 6.6, -14.8), 4.0, 5.0, 0.3, 0.5)
	var ja: CandyJack = _jack(Vector3(0, 8.0, -17.6), 3.0, 0.0, Vector3(0, 20, -3), CHERRY)
	var dais: Dictionary = _disc(Vector3(0, 13.0, -25.5), 4.2, "main", 1.2)
	kit.finish(_w(Vector3(0, 13.0, -26.5)), _yaw)
	_finish_pos = _w(Vector3(0, 13.0, -26.5))
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -7.4)))
	r_mantle(_w(Vector3(0, 3.3, -8.55)), _w(Vector3(0, 6.6, -10.8)))
	_hop(_area(Vector3(0, 6.6, -10.6), 2.25, 1.7), p, Vector3(0, 0, 2.2))
	_wait(func() -> bool: return _dark(beam, 0.05, 1.8), _w(Vector3(0, 6.6, -14.2)))
	r_walk(_w(Vector3(0, 6.6, -16.0)))
	_wait(func() -> bool: return _resting(ja, 0.0, 1.8))
	r_jump(_w(Vector3(0, 6.6, -15.8)), _w(Vector3(0, 8.0, -17.6)))
	_kick(Vector3(0, 8.0, -17.6), Vector3(0, 13.0, -24.4))
	r_walk(_w(Vector3(0, 13.0, -26.8)))
	dais.clear()
	# the summit: the great gumball machine behind the dais, a rainbow arch over it, cakes and fireworks
	_machine = deco.gumball_machine(_w(Vector3(0, 2.0, -40.0)), 2.0, deg_to_rad(_yaw))
	kit.plat(_w(Vector3(0, 2.0, -40.0)), Vector3(16.0, 1.0, 16.0), "main", -1.0, _yaw)
	deco.rainbow(_w(Vector3(0, 5.0, -28.0)), 20.0, 1.1, deg_to_rad(_yaw))
	for sx: float in [-1.0, 1.0]:
		deco.cake(_w(Vector3(sx * 9.0, 5.0, -22.0)), 2.2, 3, PINK if sx < 0.0 else SKY)
		deco.lollipop(_w(Vector3(sx * 3.2, 13.0, -23.2)), 2.6, 0.6, CHERRY if sx < 0.0 else MINT, CREAM, deg_to_rad(_yaw))
	CandyFx.rising(self, _w(Vector3(0, 13.1, -25.5)), 3.6, 6.0, 40)
	CandyFx.sprinkles(self, _w(Vector3(0, 18.0, -26.0)), _sz(Vector3(8.0, 5.0, 8.0)), 60)
	_keep_out.append(Vector4(_w(Vector3(0, 0, -40.0)).x, 0.0, _w(Vector3(0, 0, -40.0)).z, 22.0))


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
	_env.sky = CandySky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(1.0, 0.88, 0.96)
	_env.ambient_light_energy = 0.7
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 6.0
	# polish pass: the near-white haze washed the frosting platforms into the sky; thinner, pinker
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.9, 0.66, 0.84)
	_env.fog_density = 0.0011
	_env.fog_aerial_perspective = 0.3
	_env.fog_sky_affect = 0.1
	_env.fog_sun_scatter = 0.05
	_env.fog_height = SEA_Y + 8.0
	_env.fog_height_density = 0.015
	_env.glow_enabled = true
	_env.glow_intensity = 0.4
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 1.2
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.22
	_env.adjustment_contrast = 1.12
	_sun.light_color = Color(1.0, 0.95, 0.88)
	_sun.light_energy = 1.9
	_sun.rotation_degrees = Vector3(-38, 150, 0)
	_sun.shadow_blur = 1.2
	# the fill becomes a soft lilac bounce from the other side
	_fill.light_color = Color(0.8, 0.75, 1.0)
	_fill.light_energy = 0.45
	_fill.rotation_degrees = Vector3(-40, -30, 0)


## Swap every walkable surface to the frosting shader (same colours), and every waffle cone under
## the islands to the waffle shader.
func _candy_materials() -> void:
	var keel: StandardMaterial3D = Look.flat(Look.c("side").darkened(0.18), 0.9)
	var cone: ShaderMaterial = CandyDecor.waffle_material(false, Color(0.9, 0.64, 0.34), 0.5)
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		if m.material_override == keel:
			m.material_override = cone
			continue
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = FROSTING_SHADER
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
	for k: Vector4 in _keep_out:
		if Vector2(p.x - k.x, p.z - k.z).length() < k.w + dist * 0.5:
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
	# the railway loops are part of the course too: keep the scenery off the lines
	for t: CandyTrain in [_t1, _t2]:
		if t == null:
			continue
		for i: int in range(0, t.path.size(), 16):
			var q: Vector3 = t.path[i]
			_keep_out.append(Vector4(q.x, q.y, q.z, 6.0))
	# the chocolate sea under everything (a fall into it is caught by kill_y)
	deco.choco_plane(Vector3(mid.x, SEA_Y, mid.z), Vector2(maxf(span.x, span.z) + 1400.0, maxf(span.x, span.z) + 1400.0), 0.0, Vector2(0.3, 0.2))
	# gumdrop hills, lollipop trees and candy canes rising out of the sea round the course
	var placed: int = 0
	var tries: int = 0
	while placed < 60 and tries < 800:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 140.0, hi.x + 140.0), SEA_Y, rng.randf_range(lo.z - 140.0, hi.z + 140.0))
		var kind: int = rng.randi() % 4
		var clear: float = [34.0, 22.0, 18.0, 30.0][kind]
		if not _clear_of(p, pts, clear):
			continue
		match kind:
			0:
				deco.gumdrop(p - Vector3(0, 2.0, 0), rng.randf_range(10.0, 22.0), deco.pick_pastel())
			1:
				deco.lollipop_tree(p, rng.randf_range(16.0, 30.0), rng.randf_range(3.5, 6.0), deco.pick_pastel())
			2:
				deco.candy_cane(p, rng.randf_range(18.0, 34.0), rng.randf_range(0.8, 1.3), rng.randf() * TAU, [CHERRY, MINT.darkened(0.2), GRAPE][rng.randi() % 3])
			3:
				deco.cupcake(p, rng.randf_range(6.0, 11.0), deco.pick_pastel(), deco.pick_pastel())
		placed += 1
	# floating doughnuts and cotton-candy clouds in the sky round the course
	var donuts: int = 0
	var dt_: int = 0
	while donuts < 14 and dt_ < 200:
		dt_ += 1
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(110.0, 190.0)
		var dp := Vector3(mid.x + cos(a) * r, rng.randf_range(lo.y, hi.y + 30.0), mid.z + sin(a) * r)
		if not _clear_of(dp, pts, 40.0):
			continue
		deco.donut(dp, rng.randf_range(4.0, 8.0), Vector3(rng.randf_range(-1.0, 1.0), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)), deco.pick_pastel())
		donuts += 1
	# candyfloss clouds: a high deck over the whole course and a low one over the chocolate
	kit.cloud_field(Vector3(mid.x, hi.y + 45.0, mid.z), Vector3(span.x * 0.5 + 180.0, 10.0, span.z * 0.5 + 180.0), 26)
	kit.cloud_field(Vector3(mid.x, SEA_Y + 10.0, mid.z), Vector3(span.x * 0.5 + 220.0, 4.0, span.z * 0.5 + 220.0), 14)
	# far horizon: ice-cream mountains, the cake castle, a great rainbow and chocolate falls
	var far: float = maxf(span.x, span.z) * 0.5 + 260.0
	var mcols: Array[Color] = [PINK, MINT, Color(1.0, 0.85, 0.6), GRAPE.lightened(0.2), SKY]
	for i: int in 12:
		var a2: float = TAU * float(i) / 12.0 + rng.randf_range(-0.12, 0.12)
		var rr: float = far + rng.randf_range(0.0, 120.0)
		var mp := Vector3(mid.x + cos(a2) * rr, SEA_Y - 4.0, mid.z + sin(a2) * rr)
		var h: float = rng.randf_range(90.0, 170.0)
		deco.mountain(mp, h * 0.55, h, mcols[i % mcols.size()])
		if i % 3 == 0:
			var fall_top := mp + Vector3(0, h * 0.55, 0) + (Vector3(mid.x, 0, mid.z) - mp).normalized() * h * 0.26
			deco.choco_fall(fall_top, 10.0, h * 0.55 + 4.0, atan2(mid.x - mp.x, mid.z - mp.z))
	deco.castle(Vector3(mid.x - far * 0.7, SEA_Y - 2.0, mid.z - far * 0.75), 2.4)
	deco.rainbow(Vector3(mid.x + far * 0.2, SEA_Y - 10.0, mid.z - far * 0.95), 240.0, 12.0, 0.2)
	# ambient life along the whole route: sprinkles, sugar sparkles, bubbles and candyfloss wisps
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c2: Vector3 = (here + prev) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 10.0, 6.0, absf(here.z - prev.z) * 0.5 + 10.0)
		CandyFx.sprinkles(self, c2 + Vector3(0, 3.0, 0), ext, 50)
		CandyFx.sparkles(self, c2, ext * 0.8, 30)
		CandyFx.bubbles(self, c2 + Vector3(0, -6.0, 0), ext + Vector3(8, 3, 8), 12)
		CandyFx.candyfloss(self, c2 + Vector3(0, -12.0, 0), ext + Vector3(20, 3, 20), 8)


# ---- live effects -----------------------------------------------------------------------------------

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


## The summit goes off: fireworks over the gumball machine, confetti off the dais, a wash of light.
func _finish_sequence() -> void:
	for i: int in 5:
		var fw: GPUParticles3D = CandyFx.firework(CandyFx.HOT[i % CandyFx.HOT.size()], 80)
		fw.position = _finish_pos + Vector3(-8.0 + 4.0 * float(i), 12.0 + float(i % 2) * 4.0, -8.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	var c: GPUParticles3D = CandyFx.confetti(2.5, 120, 10.0)
	c.position = _finish_pos + Vector3(0, 0.6, 0)
	add_child(c)
	c.restart()
	c.emitting = true
	# SOUND: fireworks bursting over the summit
	WorldAudio.at(self, "candy_fireworks", _finish_pos + Vector3(0, 10.0, -8.0), 1.0, 120.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.95)
	flash.light_energy = 6.0
	flash.omni_range = 24.0
	flash.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.4)
	if _machine != null:
		var tw2: Tween = create_tween()
		tw2.tween_property(_machine, "scale", Vector3.ONE * 1.06, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_machine, "scale", Vector3.ONE, 0.5)
	await get_tree().create_timer(0.9).timeout
