extends LevelBase
## 21. THE ABYSS - down, then up, a black ocean trench. Fifteen stages, each ending on a checkpoint:
## over the trench lip and down through glowing gardens, past the anchors of a lost ship, a lane of
## anglerfish and the skeleton of a whale, into the deep where the leviathan patrols; then up the
## smoking vents, a kelp chimney and a field of wreckage to the wrecked deep-sea submarine, and the
## top of its conning tower. Pitch-dark water lit only by things that glow and by your own lamp;
## every place you can stand carries its own glowing rim.
##
##  1 Trench Lip       drops onto glowing posts, two GLOW CAPS, MANTLE the lip, a long leap down
##  2 Glow Garden      four glow caps in a cross CURRENT, a long leap, two SIPHONOPHORE curtains (LASERS)
##                     [shortcut: two 94% diagonal leaps over a coral knob round the curtains]
##  3 Kelp Wall        BRANCH: a post chain across a current | WALL RUN the kelp wall, MANTLE the ledge
##  4 Anchor Drop      run under two ANCHOR DROPS (CRUSHERS), MANTLE up under a third, a leap down
##                     [shortcut: WALL RUN the trench wall past the anchors, kick up onto the ledge]
##  5 Angler's Lane    a 1.4 m ledge through three ANGLERFISH jaws snapping in a wave, a post drop
##  6 Whale Fall       down the whale's spine (vertebra posts), WALL RUN its ribcage, MANTLE the skull
##                     [shortcut: a 94% leap to the knob by the pelvis and the eye-socket PORTAL]
##  7 The Drop         long leaps down onto posts in a cross current, past the MANTIS SHRIMP's ram
##                     (PISTON), the hardest leap of the level down to the checkpoint
##  8 LEVIATHAN PASS   SET PIECE: a chain of posts on the trench floor; the leviathan sweeps past in
##                     the dark and its SURGE (told by its moan, its waking lights and a silt wall)
##                     shoves everything in the water sideways - be on a post when it breaks
##  9 Plankton Lift    BRANCH: ride an up-CURRENT column, two glow caps | three MANTLES up the
##                     wreck blocks past a siphonophore curtain, two posts
## 10 Kelp Chimney     a jellyfish bounce, three WALL RUNS up between the kelp walls, a long leap
## 11 Lantern Climb    a rising wave of glow caps, then a leap through an angler's mouth
##                     [shortcut: a knob off the checkpoint and the siphon PORTAL onto the shelf]
## 12 Debris Field     BRANCH: a fallen girder swept by two shrimp rams (PISTONS) | MANTLE the wreck
##                     block, WALL RUN the hull plate
## 13 The Hull         WALL RUN the submarine's hull, under the hatch press (CRUSHER), MANTLE the deck
## 14 Deck Run         bollard posts over the flooded deck, two siphonophore curtains, a 91% leap
## 15 Conning Tower    two MANTLES up the tower, a curtain, two glow caps, the finish on top
##
## Abyss mechanics (own scripts): AbyssLamp (glow caps - solid only while lit, with a flicker tell),
## AbyssCurrent (plankton currents and timed vents), AbyssAngler (anglerfish jaws), AbyssLeviathan
## (the set piece's surge), AbyssTell (early warning lights on the shared machines).
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every
## shortcut.

const CYAN := Color(0.1, 1.0, 0.85)
const GREEN := Color(0.35, 1.0, 0.45)
const VIOLET := Color(0.7, 0.35, 1.0)
const PINK := Color(1.0, 0.35, 0.8)
const AMBER := Color(1.0, 0.6, 0.2)
const RED := Color(1.0, 0.2, 0.15)

## The abyss far below (visual only).
const FLOOR_Y: float = -80.0
## The floor of the trench where the course bottoms out (stages 7-9): seen, and a catch net.
const DEEP_Y: float = -22.0
## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## The trench rock with its glowing rims (replaces the platform shader on every walkable top).
const ROCK_SHADER: Shader = preload("res://visual/abyss_rock.gdshader")

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: AbyssDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _lamp_light: OmniLight3D
## World-space checkpoint positions in build order (set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
var _arrivals: Array[Dictionary] = []
## Places set dressing keeps clear of (world x, y, z, flat radius).
var _keep_out: Array[Vector4] = []
## Every walkable top (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _tops: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "abyss"
	music_track = "abyss"
	kill_y = -70.0
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


## A slab of trench rock (walkable), with a rock column under it down into the dark.
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, under: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if under:
		_tops.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": thick})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A local point dropped onto the trench floor (DEEP_Y).
func _deep(l: Vector3) -> Vector3:
	var p: Vector3 = _w(l)
	return Vector3(p.x, DEEP_Y, p.z)


## A patch of the trench floor (local x0..x1, z0..z1 in the current frame): dark rock, with an
## invisible catch net just above it so a fall ends as you reach the silt instead of passing through.
func _deep_floor(x0: float, x1: float, z0: float, z1: float) -> void:
	var c: Vector3 = _deep(Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5))
	var size: Vector3 = _sz(Vector3(absf(x1 - x0), 0, absf(z1 - z0)))
	deco.rock(c - Vector3(0, 1.0, 0), Vector3(size.x, 2.0, size.z), 0.0, 1.0)
	var net := KillZone.new()
	net.size = Vector3(size.x, 1.0, size.z)
	net.show_mesh = false
	net.position = c + Vector3(0, 0.7, 0)
	add_child(net)
	AbyssFx.silt(self, c + Vector3(0, 2.0, 0), Vector3(size.x * 0.4, 1.5, size.z * 0.4), 16)


## A small square rock post (the precision landings).
func _post(c: Vector3, w: float = 1.2, style: String = "alt") -> Dictionary:
	return _blk(c, w, w, style, 0.8)


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	_tops.append({"top": _w(top), "size": _sz(Vector3(size.x, 0, size.z)), "drop": size.y})
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


## A glow cap whose top is at local `c` (radius r).
func _lamp(c: Vector3, r: float, period: float, on: float, phase: float, tint: Color = CYAN) -> AbyssLamp:
	var l := AbyssLamp.new()
	l.radius = r
	l.period = period
	l.on_fraction = on
	l.phase = fposmod(phase, 1.0)
	l.tint = tint
	l.stalk = clampf(_w(c).y - FLOOR_Y - 2.0, 2.0, 30.0)
	l.position = _w(c) - Vector3(0, l.thick * 0.5, 0)
	add_child(l)
	return l


func _lamp_area(c: Vector3, r: float) -> Dictionary:
	return {"c": c, "r": r}


## A siphonophore curtain across the route at local floor point `c`: a kill beam (laser) between two
## posts with a long glowing colonial jelly strung along above it. Its charge-up shows for 1 s.
func _curtain(c: Vector3, width: float, period: float, on: float, phase: float, height: float = 2.4) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.2), period, on, fposmod(phase, 1.0), _yaw)
	g.warn = 1.0
	var bead: StandardMaterial3D = Look.flat(PINK, 0.4, 0.0, 2.2)
	var n: int = int(width / 0.35)
	for i: int in n + 1:
		var x: float = -width * 0.5 + width * float(i) / float(n)
		var s := Look.sphere(0.07 + 0.03 * float(i % 3), bead, _w(c + Vector3(x, height + 0.35 + 0.12 * sin(float(i) * 1.7), 0)))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
	return g


## An anchor drop: the crusher dressed as a lost ship's anchor on its chain, with warning lamps
## that wake 1.1 s before it falls (the shudder alone is too short a tell).
func _anchor(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(floor_c), size, lift, period, fposmod(phase, 1.0), _yaw)
	var iron: StandardMaterial3D = Look.flat(Color(0.16, 0.12, 0.1), 0.6, 0.6)
	var rust: StandardMaterial3D = Look.flat(Color(0.35, 0.18, 0.1), 0.85, 0.3)
	# the shank up the middle and the stock across the top, flukes either side
	cr.add_child(Look.box(Vector3(0.5, 2.6, 0.5), iron, Vector3(0, size.y * 0.5 + 1.3, 0)))
	cr.add_child(Look.box(Vector3(size.x + 0.4, 0.3, 0.3), rust, Vector3(0, size.y * 0.5 + 2.4, 0)))
	for sx: float in [-1.0, 1.0]:
		var fl := Look.box(Vector3(0.35, 1.1, size.z * 0.8), iron, Vector3(sx * (size.x * 0.5 + 0.15), size.y * 0.5 - 0.1, 0))
		fl.rotation.z = sx * 0.35
		cr.add_child(fl)
	# chain links running up out of sight
	for i: int in 8:
		var link := Look.box(Vector3(0.12, 0.5, 0.3) if i % 2 == 0 else Vector3(0.3, 0.5, 0.12), rust, Vector3(0, size.y * 0.5 + 2.8 + float(i) * 0.45, 0))
		cr.add_child(link)
	var tell := AbyssTell.new()
	tell.clip = "abyss_anchor_creak"
	tell.strike_in = func(t: float) -> float:
		var u: float = fposmod(t / cr.period + cr.phase, 1.0)
		return fposmod(Crusher.SLAM - u, 1.0) * cr.period
	tell.striking = func(t: float) -> bool: return not cr.is_clear_for(t, 0.0)
	cr.add_child(tell)
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			tell.add_lamp(Vector3(sx2 * (size.x * 0.5 - 0.2), -size.y * 0.5 + 0.05, sz2 * (size.z * 0.5 - 0.2)), 0.12)
	return cr


## Checkpoint rock facing the next stage's heading (_next_yaw), with its glow.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var k: int = _cp_world.size()
	var col: Color = [CYAN, GREEN, VIOLET, PINK][k % 4]
	var fx: Array[GPUParticles3D] = AbyssFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6 if p != fx[2] else 0.05, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: abyss_checkpoint - a stage banked (a bright glassy bloom and a rush of bubbles)
			WorldAudio.at(self, "abyss_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	# glowing anemones on the two back corners
	var h: float = size * 0.5 - 0.5
	for s: float in [-1.0, 1.0]:
		deco.anemone(_w(c + Vector3(s * h, 0, h)), col, 0.35)
	return d


## Fork signpost: two glowing kelp stalks and a strip on the rock in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.3, 1.3]:
		var stalk := Look.cylinder(0.06, 2.4, Look.flat(Color(0.05, 0.1, 0.1), 0.6), _w(p + Vector3(sx, 1.2, 0)), 0.04, 6)
		add_child(stalk)
		var bulb := Look.sphere(0.22, Look.flat(col, 0.3, 0.0, 3.5), _w(p + Vector3(sx, 2.5, 0)))
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.6)), _sz(Vector3(1.4, 0.05, 0.3)), col)


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


static func _dark(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
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


static func _ram_clear(p: Piston, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


static func _lit(l: AbyssLamp, a: float, b: float) -> bool:
	return l.on_between(Game.course_time, a, b)


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = AbyssDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, -90.0, -90.0, -90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, -90.0, -90.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14]
	var starts: Array[int] = []
	var origins: Array[Vector3] = []
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		starts.append(route.size())
		origins.append(_o)
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	starts.append(route.size())
	origins.append(_o)
	_stage_15()
	_surroundings()
	_abyss_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


# ---- stage 1: Trench Lip - drops onto posts, two glow caps, mantle, a leap down -----------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	_tops.append({"top": _w(Vector3.ZERO), "size": Vector3(14, 0, 14), "drop": 2.0})
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	var p1: Dictionary = _post(Vector3(0, -1.2, -12.7), 1.4)
	var p2: Dictionary = _blk(Vector3(0, -1.8, -19.0), 3.0, 3.0, "alt")
	var l1: AbyssLamp = _lamp(Vector3(0, -1.8, -25.0), 0.65, 6.0, 0.75, 0.0, CYAN)
	var l2: AbyssLamp = _lamp(Vector3(0, -1.8, -30.4), 0.65, 6.0, 0.75, -0.12, GREEN)
	var land: Dictionary = _blk(Vector3(0, -2.4, -36.4), 4.0, 4.0)
	var lip: Dictionary = _ledge(Vector3(0, 0.9, -42.6), Vector3(4.0, 10.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 0.3, -52.5))
	_hop(start, p1)
	_hop(p1, p2)
	r_walk(_w(Vector3(0, -1.8, -19.4)))
	_wait(func() -> bool: return _lit(l1, 0.3, 1.3 + 1.5) and _lit(l2, 1.0, 2.1 + 1.5), _w(Vector3(0, -1.8, -19.4)))
	_hop(p2, _lamp_area(Vector3(0, -1.8, -25.0), 0.65))
	_hop(_lamp_area(Vector3(0, -1.8, -25.0), 0.65), _lamp_area(Vector3(0, -1.8, -30.4), 0.65))
	_hop(_lamp_area(Vector3(0, -1.8, -30.4), 0.65), land, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(0, -2.4, -37.6)))
	r_mantle(_w(Vector3(0, -2.4, -38.05)), _w(Vector3(0, 0.9, -42.6)))
	_hop(lip, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# the lip of the trench: a ridge of rock either side of the start, the first kelp and worms
	deco.rock(_w(Vector3(-11.0, -4.0, -2.0)), _sz(Vector3(6.0, 12.0, 18.0)), 0.1)
	deco.rock(_w(Vector3(11.5, -3.0, 1.0)), _sz(Vector3(7.0, 10.0, 16.0)), -0.08)
	for i: int in 4:
		deco.kelp(_w(Vector3(-5.6 + float(i) * 0.5, 0.0, 5.5 - float(i) * 1.7)), 3.0 + float(i) * 0.6, [CYAN, GREEN][i % 2])
	deco.worms(_w(Vector3(5.0, 0.0, -4.5)), 9)
	deco.anemone(_w(Vector3(4.5, 0.0, 4.5)), PINK, 0.5)
	p1.clear()
	return cp["c"]


# ---- stage 2: Glow Garden - glow caps in a cross current, a long leap, two siphonophore curtains ------

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var zs: Array[float] = [-8.0, -13.3, -18.6, -23.9]
	var tints: Array[Color] = [CYAN, GREEN, CYAN, GREEN]
	var lamps: Array[AbyssLamp] = []
	for i: int in zs.size():
		lamps.append(_lamp(Vector3(0, -0.6, zs[i]), 0.65, 6.0, 0.72, -0.1 * float(i), tints[i]))
	var cur := AbyssCurrent.new()
	cur.size = _sz(Vector3(9.0, 6.0, 22.0))
	cur.push = _d(Vector3(6.0, 0, 0))
	cur.position = _w(Vector3(0, 1.0, -16.0))
	add_child(cur)
	var walk: Dictionary = _blk(Vector3(0, -1.2, -37.5), 2.4, 15.5, "alt", 0.8)
	var g1: LaserGate = _curtain(Vector3(0, -1.2, -37.5), 2.4, 4.5, 0.3, 0.0)
	var g2: LaserGate = _curtain(Vector3(0, -1.2, -41.5), 2.4, 4.5, 0.3, -0.11)
	var cp: Dictionary = _cp(Vector3(0, -0.6, -52.85))
	# SHORTCUT: a coral knob off the walk's right side - two long diagonal leaps round the curtains
	var knob: Dictionary = _blk(Vector3(3.4, -1.2, -39.5), 1.0, 1.0, "accent", 0.6)
	r_walk(_w(Vector3(0, 0, -1.6)))
	_wait(func() -> bool:
		for i: int in lamps.size():
			var t0: float = 0.6 + 0.75 * float(i)
			if not _lit(lamps[i], t0 - 0.2, t0 + 0.6 + 1.5):
				return false
		return true, _w(Vector3(0, 0, -1.6)))
	var prev: Dictionary = cp0
	for i: int in zs.size():
		var m: Dictionary = _lamp_area(Vector3(0, -0.6, zs[i]), 0.65)
		_hop(prev, m)
		prev = m
	_hop(prev, walk, Vector3(0, 0, 6.0))
	if route_variant == 2:
		r_walk(_w(Vector3(0.6, -1.2, -32.6)))
		r_jump(_w(Vector3(0.85, -1.2, -33.9)), _w(Vector3(3.4, -1.2, -39.5)))
		r_jump(_w(Vector3(3.25, -1.2, -39.75)), _w(Vector3(0.3, -1.2, -44.8)))
	else:
		r_walk(_w(Vector3(0, -1.2, -32.4)))
		_wait(func() -> bool: return _dark(g1, 0.2, 1.0 + 1.5) and _dark(g2, 0.6, 1.5 + 1.5), _w(Vector3(0, -1.2, -32.4)))
		r_walk(_w(Vector3(0, -1.2, -44.6)))
	_hop(walk, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# the garden: kelp forests either side of the current, anemones and worm thickets on the rock
	for i: int in 6:
		var z: float = -6.0 - 4.0 * float(i)
		deco.kelp(_w(Vector3(-6.5 - float(i % 2) * 1.2, -5.0, z)), 7.0 + float(i % 3), [CYAN, GREEN, VIOLET][i % 3])
		deco.kelp(_w(Vector3(7.0 + float(i % 2) * 1.3, -5.0, z - 2.0)), 6.0 + float((i + 1) % 3), [GREEN, CYAN][i % 2])
	AbyssFx.plankton(self, _w(Vector3(0, 1.0, -16.0)), _sz(Vector3(5.0, 3.0, 11.0)), 50)
	walk.clear()
	knob.clear()
	return cp["c"]


# ---- stage 3: Kelp Wall (BRANCH) - a post chain across a current, or the wall run and the ledge -------

func _stage_3() -> Vector3:
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (cyan): a chain of posts across a current pushing toward the wall
	var pz: Array[float] = [-15.6, -21.2, -26.8, -32.4]
	var posts: Array[Dictionary] = []
	for z: float in pz:
		posts.append(_post(Vector3(-3.5, 0, z), 1.2))
	var cur := AbyssCurrent.new()
	cur.size = _sz(Vector3(6.0, 6.0, 26.0))
	cur.push = _d(Vector3(5.0, 0, 0))
	cur.position = _w(Vector3(-3.5, 1.5, -22.0))
	add_child(cur)
	# RIGHT (violet): wall-run the kelp wall, kick onto the block, mantle the ledge, drop to the merge
	kit.wallrun(_w(Vector3(6.5, 2.4, -19.5)), Vector3(14.0, 6.5, 0.6), _yaw + 90.0)
	var kb: Dictionary = _blk(Vector3(3.2, 0, -26.5), 3.0, 3.0, "alt")
	var kl: Dictionary = _ledge(Vector3(3.2, 3.3, -32.2), Vector3(3.0, 9.0, 3.4), "alt")
	var merge: Dictionary = _blk(Vector3(0, 0, -39.5), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 0.6, -49.1))
	_sign(Vector3(-3.5, 0, -6.6), CYAN)
	_sign(Vector3(4.0, 0, -6.6), VIOLET)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.4)))
		var prev: Dictionary = _area(Vector3(-3.5, 0, -8.0), 1.5, 2.0)
		for p: Dictionary in posts:
			_hop(prev, p)
			prev = p
		_hop(prev, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(4.5, 0, -8.8)))
		r_wallrun(_w(Vector3(4.6, 0, -9.65)), _w(Vector3(6.0, 1.4, -13.6)), _w(Vector3(6.0, 1.4, -21.5)), _w(Vector3(3.2, 0, -26.3)))
		r_walk(_w(Vector3(3.2, 0, -27.2)))
		r_mantle(_w(Vector3(3.2, 0, -27.65)), _w(Vector3(3.2, 3.3, -32.0)))
		_hop(kl, merge, Vector3(3.2, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# the kelp wall: a cliff of rock behind the panel, hung with glowing kelp
	deco.rock(_w(Vector3(8.6, -6.0, -21.0)), _sz(Vector3(3.6, 30.0, 26.0)), 0.0, 1.0)
	for i: int in 5:
		deco.kelp(_w(Vector3(7.6, 9.0, -13.0 - 3.2 * float(i))), 2.5, [VIOLET, CYAN][i % 2])
	deco.rock(_w(Vector3(-10.0, -8.0, -24.0)), _sz(Vector3(4.0, 22.0, 30.0)), 0.0, 0.8)
	AbyssFx.plankton(self, _w(Vector3(-3.5, 1.5, -24.0)), _sz(Vector3(3.0, 2.5, 12.0)), 40)
	fork.clear()
	kb.clear()
	return cp["c"]


# ---- stage 4: Anchor Drop - under two anchor drops, a mantle under a third, a leap down --------------

func _stage_4() -> Vector3:
	var walk: Dictionary = _blk(Vector3(0, -0.6, -16.0), 2.6, 16.0, "alt", 0.8)
	var c1: Crusher = _anchor(Vector3(0, -0.6, -13.0), Vector3(2.8, 1.2, 2.4), 3.4, 4.6, 0.0)
	var c2: Crusher = _anchor(Vector3(0, -0.6, -19.0), Vector3(2.8, 1.2, 2.4), 3.4, 4.6, -0.15)
	var top: Dictionary = _ledge(Vector3(0, 2.7, -28.2), Vector3(3.0, 9.0, 3.4))
	var c3: Crusher = _anchor(Vector3(0, 2.7, -28.2), Vector3(2.6, 1.0, 2.6), 3.2, 4.6, -0.38)
	var cp: Dictionary = _cp(Vector3(0, 0.0, -38.9))
	# SHORTCUT: the trench wall beside the anchors - wall-run past them and kick up onto the ledge top
	kit.wallrun(_w(Vector3(-3.4, 1.6, -17.0)), Vector3(14.0, 7.0, 0.6), _yaw + 90.0)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), walk, Vector3(0, 0, 7.4))
	if route_variant == 2:
		r_walk(_w(Vector3(-0.4, -0.6, -8.8)))
		_wait(func() -> bool: return _press_ok(c3, 1.0, 2.0 + 1.5), _w(Vector3(-0.4, -0.6, -8.8)))
		r_wallrun(_w(Vector3(-0.6, -0.6, -9.6)), _w(Vector3(-2.8, 0.8, -13.6)), _w(Vector3(-2.8, 0.8, -22.0)), _w(Vector3(0, 2.7, -27.6)))
	else:
		r_walk(_w(Vector3(0, -0.6, -9.0)))
		_wait(func() -> bool: return _press_ok(c1, 0.2, 0.9 + 1.5) and _press_ok(c2, 0.8, 1.6 + 1.5) and _press_ok(c3, 1.9, 2.9 + 1.5), _w(Vector3(0, -0.6, -9.0)))
		r_walk(_w(Vector3(0, -0.6, -23.2)))
		r_mantle(_w(Vector3(0, -0.6, -23.65)), _w(Vector3(0, 2.7, -28.0)))
	_hop(top, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# the wreck the anchors hang from is lost in the dark above: its shadow, hanging cable
	deco.rock(_w(Vector3(-5.5, -6.0, -18.0)), _sz(Vector3(3.0, 16.0, 22.0)), 0.0, 0.9)
	deco.rock(_w(Vector3(5.8, -6.0, -20.0)), _sz(Vector3(3.0, 16.0, 26.0)), 0.0, 0.9)
	walk.clear()
	return cp["c"]


# ---- stage 5: Angler's Lane - a narrow ledge through three anglerfish jaws, a post drop ---------------

func _stage_5() -> Vector3:
	var lane: Dictionary = _blk(Vector3(0, -0.6, -19.2), 1.4, 22.0, "alt", 0.8)
	var az: Array[float] = [-13.5, -19.5, -25.5]
	var fish: Array[AbyssAngler] = []
	for i: int in az.size():
		fish.append(_angler(Vector3(0, -0.6, az[i]), 4.5, -0.15 * float(i)))
	var p1: Dictionary = _post(Vector3(0, -1.8, -36.4), 1.2)
	var p2: Dictionary = _post(Vector3(0, -2.4, -42.2), 1.2)
	var cp: Dictionary = _cp(Vector3(0, -3.0, -50.6))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), lane, Vector3(0, 0, 10.4))
	r_walk(_w(Vector3(0, -0.6, -9.2)))
	# the bot runs the lane: in each mouth from about 0.45 + 0.67 i s to 0.85 + 0.67 i s
	_wait(func() -> bool:
		for i: int in fish.size():
			var t0: float = 0.4 + 0.67 * float(i)
			if not fish[i].clear_between(Game.course_time, t0 - 0.2, t0 + 0.6 + 1.5):
				return false
		return true, _w(Vector3(0, -0.6, -9.2)))
	r_walk(_w(Vector3(0, -0.6, -29.4)))
	_hop(lane, p1)
	_hop(p1, p2)
	_hop(p2, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# the lane clings to the trench wall on the left; the anglers lie in its hollows
	deco.rock(_w(Vector3(-8.0, -4.0, -19.0)), _sz(Vector3(4.0, 22.0, 30.0)), 0.0, 0.9)
	deco.rock(_w(Vector3(-6.4, 6.5, -19.0)), _sz(Vector3(2.0, 2.0, 30.0)), 0.0, 0.6)
	for i: int in 4:
		deco.kelp(_w(Vector3(-6.2, 7.5, -10.0 - 6.0 * float(i))), 2.0, VIOLET)
	lane.clear()
	p1.clear()
	return cp["c"]


## An anglerfish lying beside the path at local floor point `c` (its head on local -X).
func _angler(c: Vector3, period: float, phase: float, width: float = 2.6) -> AbyssAngler:
	var a := AbyssAngler.new()
	a.width = width
	a.length = 2.6
	a.period = period
	a.phase = fposmod(phase, 1.0)
	a.rotation.y = deg_to_rad(_yaw)
	a.position = _w(c)
	add_child(a)
	_keep_out.append(Vector4(_w(c).x, _w(c).y, _w(c).z, 6.0))
	return a


# ---- stage 6: Whale Fall - down the whale's spine, WALL RUN the ribcage, MANTLE onto the skull --------
# [shortcut: a 92% leap to the knob by the skull and the eye-socket PORTAL]

func _stage_6() -> Vector3:
	var vz: Array[float] = [-8.95, -14.25, -19.55, -25.05]
	var vy: Array[float] = [-1.2, -1.8, -2.4, -3.0]
	var verts: Array[Dictionary] = []
	for i: int in vz.size():
		verts.append(_vertebra(Vector3(0, vy[i], vz[i]), 1.1))
	var pelvis: Dictionary = _blk(Vector3(0, -3.6, -31.5), 3.0, 3.0, "alt")
	kit.wallrun(_w(Vector3(2.6, -1.2, -43.0)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _blk(Vector3(-0.4, -3.6, -53.2), 2.6, 3.0, "alt")
	var skull: Dictionary = _ledge(Vector3(0, -0.3, -58.9), Vector3(4.0, 10.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, -0.9, -69.05))
	# SHORTCUT: the knob off the pelvis's left side and the portal in the skull's eye
	var knob: Dictionary = _blk(Vector3(-7.35, -3.6, -31.5), 1.0, 1.0, "accent", 0.6)
	var portal: WarpPortal = kit.portal(_w(Vector3(-7.35, -3.6, -31.5)), _yaw, _w(Vector3(0, -0.3, -58.0)), _yaw, 6.0)
	_arrival(Vector3(0, -0.3, -58.4), PINK)
	var prev: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	for v: Dictionary in verts:
		_hop(prev, v)
		prev = v
	_hop(prev, pelvis)
	if route_variant == 2:
		r_walk(_w(Vector3(-0.6, -3.6, -31.5)))
		r_jump(_w(Vector3(-1.15, -3.6, -31.5)), _w(Vector3(-7.35, -3.6, -31.5)))
		r_portal(_w(Vector3(-7.35, -3.6, -31.7)), portal.exit_point())
		r_walk(_w(Vector3(0, -0.3, -59.0)))
	else:
		r_walk(_w(Vector3(0.3, -3.6, -30.4)))
		r_wallrun(_w(Vector3(0.5, -3.6, -32.65)), _w(Vector3(2.0, -2.2, -36.6)), _w(Vector3(2.0, -2.2, -45.5)), _w(Vector3(-0.4, -3.6, -53.0)))
		r_walk(_w(Vector3(-0.2, -3.6, -54.0)))
		r_mantle(_w(Vector3(0, -3.6, -54.35)), _w(Vector3(0, -0.3, -58.7)))
	_hop(skull, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	_whale_dress()
	knob.clear()
	land.clear()
	return cp["c"]


## A vertebra of the whale's spine (a narrow bone landing) on its stalk of rock.
func _vertebra(c: Vector3, w: float) -> Dictionary:
	var d: Dictionary = _blk(c, w, w, "alt", 0.7)
	# bone wings either side of the landing, below its top so they never get in the way
	for sx: float in [-1.0, 1.0]:
		var wing := Look.box(_sz(Vector3(1.4, 0.3, 0.5)), AbyssDecor.bone_mat(), _w(c + Vector3(sx * (w * 0.5 + 0.7), -0.55, 0)))
		add_child(wing)
	return d


func _whale_dress() -> void:
	# the ribs arch over the course from the spine's right side, the wall-run panel among them
	for i: int in 7:
		var z: float = -33.0 - 3.2 * float(i)
		deco.rib(_w(Vector3(4.2, -6.0, z)), 13.0 - absf(float(i) - 3.0) * 0.5, -8.0, deg_to_rad(_yaw), 0.32)
	deco.rib(_w(Vector3(-3.6, -6.0, -40.0)), 6.0, -3.0, deg_to_rad(_yaw), 0.3)
	deco.rib(_w(Vector3(-3.6, -6.0, -46.0)), 5.4, -3.0, deg_to_rad(_yaw), 0.3)
	# the jaw bones flanking the skull, and the skull's brow
	var bone: StandardMaterial3D = AbyssDecor.bone_mat()
	for sx: float in [-1.0, 1.0]:
		var jaw := Look.box(_sz(Vector3(0.6, 0.8, 5.6)), bone, _w(Vector3(sx * 3.1, -2.6, -62.9)))
		jaw.rotation.y = deg_to_rad(_yaw) + sx * 0.12
		add_child(jaw)
	deco.rock(_w(Vector3(-11.0, -10.0, -40.0)), _sz(Vector3(4.0, 22.0, 40.0)), 0.0, 0.8)
	AbyssFx.plankton(self, _w(Vector3(0, -1.0, -45.0)), _sz(Vector3(4.0, 3.0, 14.0)), 40)


## A burst of glowing plankton where a portal lets you out (fired when you arrive).
func _arrival(at: Vector3, col: Color) -> void:
	var fx: Array[GPUParticles3D] = AbyssFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(at + Vector3(0, 0.6, 0))
		add_child(p)
	_arrivals.append({"at": _w(at), "p": fx, "cool": 0.0})
	AbyssFx.rising(self, _w(at), 1.2, 2.5, 14, col)


# ---- stage 7: The Drop - long leaps down in a cross current, past the mantis shrimp's ram --------------

func _stage_7() -> Vector3:
	var d1: Dictionary = _post(Vector3(0, -2.4, -9.6), 1.2)
	var d2: Dictionary = _post(Vector3(0, -4.8, -15.8), 1.2)
	var ledge: Dictionary = _blk(Vector3(0, -7.2, -24.8), 2.4, 6.0, "alt", 0.8)
	var ram: Piston = _shrimp(Vector3(2.0, -7.2 + 1.3, -25.3), 5.0, 0.0)
	var d4: Dictionary = _post(Vector3(0, -9.6, -34.1), 1.2)
	var cp: Dictionary = _cp(Vector3(0, -12.0, -44.0))
	var cur := AbyssCurrent.new()
	cur.size = _sz(Vector3(8.0, 8.0, 14.0))
	cur.push = _d(Vector3(-5.0, 0, 0))
	cur.position = _w(Vector3(0, -1.5, -12.0))
	add_child(cur)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), d1)
	_hop(d1, d2)
	_hop(d2, ledge, Vector3(0, 0, 2.4))
	r_walk(_w(Vector3(0, -7.2, -22.6)))
	_wait(func() -> bool: return _ram_clear(ram, 0.0, 0.7 + 1.5), _w(Vector3(0, -7.2, -22.6)))
	r_walk(_w(Vector3(0, -7.2, -27.4)))
	_hop(ledge, d4)
	_hop(d4, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# a steep wall of the trench on the right, the shrimp's burrow cut into it; smokers far below
	deco.rock(_w(Vector3(6.0, -10.0, -22.0)), _sz(Vector3(4.0, 26.0, 34.0)), 0.0, 0.9)
	_deep_floor(-24.0, 10.0, 4.0, -50.0)
	deco.chimney(_deep(Vector3(-9.0, 0, -30.0)), 11.0)
	deco.chimney(_deep(Vector3(-14.0, 0, -18.0)), 9.0)
	AbyssFx.plankton(self, _w(Vector3(0, -3.0, -12.0)), _sz(Vector3(4.0, 4.0, 7.0)), 30)
	d1.clear()
	d2.clear()
	return cp["c"]


## The mantis shrimp: a ram (piston) punching out across the path from its burrow on the right
## (local +X), dressed as the shrimp's club and armoured head, with warning lights that wake 1.1 s
## before each punch.
func _shrimp(top: Vector3, period: float, phase: float, stroke: float = 2.9) -> Piston:
	var size := Vector3(1.6, 1.3, 1.4)
	var p: Piston = kit.piston(_w(top), size, _yaw + 90.0, stroke, period, fposmod(phase, 1.0), 12.0)
	var shell: StandardMaterial3D = Look.flat(Color(0.15, 0.5, 0.45), 0.4, 0.2, 0.3)
	var club: StandardMaterial3D = Look.flat(Color(0.95, 0.35, 0.2), 0.35, 0.1, 0.6)
	var face := Look.sphere(0.55, club, Vector3(0, 0, -size.z * 0.5 - 0.15))
	face.scale = Vector3(1.2, 1.0, 0.6)
	p.add_child(face)
	for i: int in 3:
		var seg := Look.box(Vector3(size.x + 0.1, 0.22, 0.3), shell, Vector3(0, size.y * 0.5 - 0.05, -size.z * 0.5 + 0.25 + float(i) * 0.4))
		p.add_child(seg)
	var tell := AbyssTell.new()
	tell.clip = "abyss_shrimp_click"
	tell.tint = Color(1.0, 0.45, 0.15)
	tell.strike_in = func(t: float) -> float:
		var u: float = fposmod(t / p.period + p.phase, 1.0)
		return fposmod(Piston.PUNCH_START - u, 1.0) * p.period
	tell.striking = func(t: float) -> bool: return p.is_punching_at(t)
	p.add_child(tell)
	# its stalked eyes on top, glowing
	for sx: float in [-0.4, 0.4]:
		tell.add_lamp(Vector3(sx, size.y * 0.5 + 0.35, -size.z * 0.5 + 0.2), 0.12)
		p.add_child(Look.cylinder(0.04, 0.3, shell, Vector3(sx, size.y * 0.5 + 0.15, -size.z * 0.5 + 0.2), -1.0, 6))
	return p


# ---- stage 8: LEVIATHAN PASS - the precision chain on the trench floor, the leviathan's surges ---------

var _leviathan: AbyssLeviathan


func _stage_8() -> Vector3:
	var q1: Dictionary = _post(Vector3(0, 0, -8.5), 1.2)
	var q2: Dictionary = _post(Vector3(0, 0.6, -13.9), 1.2)
	var q3: Dictionary = _post(Vector3(0, 0.6, -19.5), 1.2)
	var rest: Dictionary = _blk(Vector3(0, 0, -26.1), 2.0, 4.0, "main", 1.0)
	var q4: Dictionary = _post(Vector3(0, 0, -33.9), 1.2)
	var q5: Dictionary = _post(Vector3(0, 0.6, -39.4), 1.2)
	var q6: Dictionary = _post(Vector3(0, 1.2, -44.6), 1.2)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -52.6))
	_leviathan = AbyssLeviathan.new()
	_leviathan.size = Vector3(14.0, 9.0, 52.0)
	_leviathan.push = Vector3(30.0, 0, 0)
	_leviathan.period = 8.0
	_leviathan.warn = 1.5
	_leviathan.travel = 0.5
	_leviathan.hold = 1.6
	_leviathan.distance = 18.0
	_leviathan.rotation.y = deg_to_rad(_yaw)
	_leviathan.position = _w(Vector3(0, 2.5, -26.0))
	add_child(_leviathan)
	var lev: AbyssLeviathan = _leviathan
	r_walk(_w(Vector3(0, 0, -1.8)))
	_wait(func() -> bool: return lev.calm_between(Game.course_time, 0.0, 3.4 + 1.5), _w(Vector3(0, 0, -1.8)))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), q1)
	_hop(q1, q2)
	_hop(q2, q3)
	_hop(q3, rest, Vector3(0, 0, 1.2))
	r_walk(_w(Vector3(0, 0, -24.8)))
	_wait(func() -> bool: return lev.calm_between(Game.course_time, 0.0, 3.2 + 1.5), _w(Vector3(0, 0, -24.8)))
	_hop(rest, q4)
	_hop(q4, q5)
	_hop(q5, q6)
	_hop(q6, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# the trench floor: black smokers, worm fields and bones of things the leviathan left
	_deep_floor(-36.0, 16.0, 6.0, -60.0)
	deco.chimney(_deep(Vector3(5.5, 0, -18.0)), 12.0)
	deco.chimney(_deep(Vector3(6.5, 0, -38.0)), 14.0)
	deco.worms(_deep(Vector3(4.0, 0, -28.0)), 10, 1.2)
	deco.worms(_deep(Vector3(-3.0, 0, -8.0)), 8, 1.0)
	deco.worms(_deep(Vector3(2.5, 0, -46.0)), 8, 1.0)
	deco.rock(_w(Vector3(11.0, -6.0, -26.0)), _sz(Vector3(4.0, 30.0, 56.0)), 0.0, 1.0)
	deco.rib(_deep(Vector3(-5.0, 0, -12.0)), 7.0, 3.0, deg_to_rad(_yaw) + PI, 0.3)
	deco.rib(_deep(Vector3(-6.0, 0, -15.0)), 6.4, 2.6, deg_to_rad(_yaw) + PI, 0.3)
	_keep_out.append(Vector4(_w(Vector3(-25.0, 0, -26.0)).x, 0, _w(Vector3(-25.0, 0, -26.0)).z, 30.0))
	AbyssFx.silt(self, _w(Vector3(0, -2.0, -26.0)), _sz(Vector3(10.0, 2.0, 26.0)), 24)
	q1.clear()
	q2.clear()
	q3.clear()
	q4.clear()
	q5.clear()
	q6.clear()
	return cp["c"]


# ---- stage 9: Plankton Lift (BRANCH) - ride the current up, two glow caps | three MANTLES past a curtain -

func _stage_9() -> Vector3:
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (green): an up-current column out over the drop, a shelf beside its top, two glow caps
	var col := AbyssCurrent.new()
	col.size = Vector3(2.4, 8.5, 2.4)
	col.push = Vector3(0, 72.0, 0)
	col.max_rise = 12.0
	col.tint = GREEN
	col.rotation.y = deg_to_rad(_yaw)
	col.position = _w(Vector3(-3.5, 3.25, -13.5))
	add_child(col)
	var shelf: Dictionary = _blk(Vector3(-3.5, 8.4, -16.9), 2.0, 2.8, "alt", 0.8)
	var l1: AbyssLamp = _lamp(Vector3(-3.5, 9.0, -22.4), 0.65, 5.5, 0.72, 0.0, GREEN)
	var l2: AbyssLamp = _lamp(Vector3(-3.5, 9.6, -27.3), 0.65, 5.5, 0.72, -0.12, CYAN)
	# RIGHT (pink): three stacked mantles, a siphonophore curtain across the middle ledge, two posts
	_ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 8.0, 3.4), "alt")
	_ledge(Vector3(4.0, 6.6, -17.0), Vector3(3.0, 11.0, 3.4), "alt")
	var k3: Dictionary = _ledge(Vector3(4.0, 9.9, -20.4), Vector3(3.0, 14.0, 3.4), "alt")
	var gate: LaserGate = _curtain(Vector3(4.0, 6.6, -17.5), 3.0, 5.0, 0.3, 0.2)
	var bp: Dictionary = _post(Vector3(4.0, 10.2, -27.0), 1.2)
	var merge: Dictionary = _blk(Vector3(0, 10.2, -34.0), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 10.8, -43.6))
	_sign(Vector3(-3.5, 0, -6.6), GREEN)
	_sign(Vector3(4.0, 0, -6.6), PINK)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.6)))
		var top_y: float = _w(Vector3(0, 7.2, 0)).y
		route.append({"kind": "desert_fly", "jump_from": _w(Vector3(-3.5, 0, -9.65)), "to": _w(Vector3(-3.5, 6.0, -13.5)),
			"until": func() -> bool: return player.global_position.y > top_y})
		route.append({"kind": "a_fly", "to": _w(Vector3(-3.5, 8.4, -16.9))})
		r_walk(_w(Vector3(-3.5, 8.4, -16.6)))
		_wait(func() -> bool: return _lit(l1, 0.2, 1.0 + 1.5) and _lit(l2, 0.8, 1.8 + 1.5), _w(Vector3(-3.5, 8.4, -16.6)))
		_hop(shelf, _lamp_area(Vector3(-3.5, 9.0, -22.4), 0.65))
		_hop(_lamp_area(Vector3(-3.5, 9.0, -22.4), 0.65), _lamp_area(Vector3(-3.5, 9.6, -27.3), 0.65))
		_hop(_lamp_area(Vector3(-3.5, 9.6, -27.3), 0.65), merge, Vector3(-3.5, 0, 1.2))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.4)))
		r_mantle(_w(Vector3(4.0, 3.3, -14.95)), _w(Vector3(4.0, 6.6, -16.6)))
		_wait(func() -> bool: return _dark(gate, 0.0, 1.2 + 1.5), _w(Vector3(4.0, 6.6, -16.6)))
		r_mantle(_w(Vector3(4.0, 6.6, -17.9)), _w(Vector3(4.0, 9.9, -20.2)))
		_hop(k3, bp)
		_hop(bp, merge, Vector3(4.0, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# a field of black smokers below the lift, the current's mouth a glowing vent
	_deep_floor(-20.0, 12.0, 4.0, -40.0)
	deco.chimney(_deep(Vector3(-3.5, 0, -13.5)), _w(Vector3(0, -1.6, 0)).y - DEEP_Y, false)
	AbyssFx.bubbles(self, _w(Vector3(-3.5, -1.0, -13.5)), 10.0, 22, 0.8)
	deco.chimney(_deep(Vector3(-9.0, 0, -20.0)), 12.0)
	deco.chimney(_deep(Vector3(-10.5, 0, -9.0)), 9.0)
	deco.rock(_w(Vector3(8.6, -4.0, -18.0)), _sz(Vector3(3.6, 30.0, 16.0)), 0.0, 0.9)
	fork.clear()
	return cp["c"]


# ---- stage 10: Kelp Chimney - a jellyfish bounce up, three WALL RUNS up between the kelp walls --------

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f: Dictionary = _blk(Vector3(0, 0, -9.6), 5.0, 6.0, "alt", 1.2)
	var padp := Vector3(0, 0, -10.6)
	kit.pad(_w(padp), 21.0, 0.0, 0.0, 1.2)
	_jelly_pad(padp)
	_blk(Vector3(0, 6.0, -15.2), 2.6, 2.6, "main", 1.2, false)
	_chimney_panel(2.3, 7.2, -19.5, -26.0)
	_chimney_panel(-2.3, 12.0, -24.5, -32.5)
	_chimney_panel(2.3, 15.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 17.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 17.9, -52.05))
	_hop(cp0, f, Vector3(0, 0, 1.6))
	r_walk(_w(padp + Vector3(0, 0, 1.4)))
	r_pad(_w(padp), _w(Vector3(0, 6.0, -14.8)))
	r_walk(_w(Vector3(0, 6.0, -14.1)))
	r_wallrun(_w(Vector3(0.5, 6.0, -15.85)), _w(Vector3(1.7, 7.4, -20.6)), _w(Vector3(1.7, 7.4, -23.5)), _w(Vector3(-1.7, 11.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 11.5, -27.4)), _w(Vector3(-1.7, 11.5, -30.4)), _w(Vector3(1.7, 14.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 14.5, -34.0)), _w(Vector3(1.7, 14.5, -35.4)), _w(Vector3(-0.75, 17.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	AbyssFx.plankton(self, _w(Vector3(0, 12.0, -28.0)), _sz(Vector3(2.0, 6.0, 10.0)), 50)
	AbyssFx.bubbles(self, _w(Vector3(0, 1.0, -28.0)), 18.0, 20, 1.0)
	return cp["c"]


## A chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by a kelp-hung cliff.
func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	deco.rock(_w(Vector3(x + signf(x) * 1.2, y - 6.0, (z0 + z1) * 0.5)), _sz(Vector3(1.6, height + 14.0, absf(z0 - z1) + 1.0)), 0.0, 1.0)
	for i: int in 3:
		var z: float = z0 - (float(i) + 0.5) * absf(z0 - z1) / 3.0
		deco.kelp(_w(Vector3(x + signf(x) * 0.45, y + height * 0.5, z)), 1.4, [GREEN, CYAN, VIOLET][i])


## A bounce pad dressed as a big glowing jellyfish bell (visual only: the pad does the work).
func _jelly_pad(c: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = VIOLET
	mat.emission_energy_multiplier = 1.2
	var tm := TorusMesh.new()
	tm.inner_radius = 1.25
	tm.outer_radius = 1.5
	tm.rings = 32
	tm.ring_segments = 8
	var rim := Look.mesh_node(tm, mat, _w(c + Vector3(0, 0.08, 0)))
	rim.scale = Vector3(1, 0.5, 1)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	var ten: StandardMaterial3D = Look.flat(Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.6), 0.5, 0.0, 1.4)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		add_child(Look.box(Vector3(0.04, 1.6, 0.04), ten, _w(c + Vector3(cos(a) * 1.35, -0.9, sin(a) * 1.35))))


# ---- stage 11: Lantern Climb - a rising wave of glow caps, a leap through an angler's mouth ------------

func _stage_11() -> Vector3:
	var zs: Array[float] = [-8.0, -12.9, -17.8, -22.7]
	var lamps: Array[AbyssLamp] = []
	for i: int in zs.size():
		lamps.append(_lamp(Vector3(0, 0.6 * float(i + 1), zs[i]), 0.6, 5.5, 0.7, -0.12 * float(i), [CYAN, GREEN, VIOLET, PINK][i]))
	var shelf: Dictionary = _blk(Vector3(0, 2.4, -29.3), 3.0, 4.0, "alt")
	var jaw: AbyssAngler = _angler(Vector3(0, 2.4, -29.9), 4.0, 0.0, 3.1)
	var cp: Dictionary = _cp(Vector3(0, 2.4, -39.55))
	# SHORTCUT: a knob off the checkpoint's left corner and the siphon PORTAL on it, out onto the shelf
	var knob: Dictionary = _blk(Vector3(-3.0, 0.6, -8.2), 1.0, 1.0, "accent", 0.6)
	var portal: WarpPortal = kit.portal(_w(Vector3(-3.0, 0.6, -8.2)), _yaw, _w(Vector3(0, 2.4, -27.5)), _yaw, 6.0)
	_arrival(Vector3(0, 2.4, -27.8), VIOLET)
	if route_variant == 2:
		r_walk(_w(Vector3(-2.0, 0, -1.8)))
		r_jump(_w(Vector3(-2.3, 0, -2.65)), _w(Vector3(-3.0, 0.6, -8.2)))
		r_portal(_w(Vector3(-3.0, 0.6, -8.4)), portal.exit_point())
	else:
		r_walk(_w(Vector3(0, 0, -1.6)))
		_wait(func() -> bool:
			for i: int in lamps.size():
				var t0: float = 0.6 + 0.7 * float(i)
				if not _lit(lamps[i], t0 - 0.2, t0 + 0.55 + 1.5):
					return false
			return true, _w(Vector3(0, 0, -1.6)))
		var prev: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
		for i: int in zs.size():
			var m: Dictionary = _lamp_area(Vector3(0, 0.6 * float(i + 1), zs[i]), 0.6)
			_hop(prev, m)
			prev = m
		_hop(prev, shelf, Vector3(0, 0, 1.3))
	r_walk(_w(Vector3(0, 2.4, -27.9)))
	_wait(func() -> bool: return jaw.clear_between(Game.course_time, 0.0, 0.6 + 1.5), _w(Vector3(0, 2.4, -27.9)))
	_hop(shelf, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	deco.rock(_w(Vector3(-8.0, -6.0, -20.0)), _sz(Vector3(4.0, 22.0, 34.0)), 0.0, 0.9)
	for i: int in 5:
		deco.kelp(_w(Vector3(4.0 + float(i % 2), -4.0, -6.0 - 5.0 * float(i))), 8.0, [CYAN, VIOLET][i % 2])
	knob.clear()
	return cp["c"]


# ---- stage 12: Debris Field (BRANCH) - a girder past two shrimp rams | MANTLE, WALL RUN the hull plate --

func _stage_12() -> Vector3:
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (amber): a post, a fallen girder swept by two mantis-shrimp rams, a leap up to the merge
	var p: Dictionary = _post(Vector3(-3.5, 0, -15.5), 1.2)
	var girder: Dictionary = _blk(Vector3(-3.5, 0, -27.7), 1.2, 15.4, "alt", 0.6)
	var r1: Piston = _shrimp(Vector3(-1.9, 1.3, -25.0), 4.6, 0.0, 2.4)
	var r2: Piston = _shrimp(Vector3(-1.9, 1.3, -30.5), 4.6, -0.13, 2.4)
	# RIGHT (cyan): mantle the wreck block, wall-run the hull plate, land on the plate, drop to the merge
	_ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 8.0, 3.2), "alt")
	kit.wallrun(_w(Vector3(6.5, 4.5, -24.7)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(3.8, 4.4, -35.3), 3.6, 4.0, "alt")
	var merge: Dictionary = _blk(Vector3(0, 0.6, -42.0), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -51.6))
	_sign(Vector3(-3.5, 0, -6.6), AMBER)
	_sign(Vector3(4.0, 0, -6.6), CYAN)
	_hop(_area(Vector3.ZERO, 3.0, 3.0), fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.6)))
		_hop(_area(Vector3(-3.5, 0, -8.0), 1.5, 2.0), p)
		_hop(p, girder, Vector3(0, 0, 6.8))
		r_walk(_w(Vector3(-3.5, 0, -21.6)))
		_wait(func() -> bool: return _ram_clear(r1, 0.0, 0.6 + 1.5) and _ram_clear(r2, 0.5, 1.2 + 1.5), _w(Vector3(-3.5, 0, -21.6)))
		r_walk(_w(Vector3(-3.5, 0, -33.6)))
		_hop(girder, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(4.3, 3.3, -14.85)), _w(Vector3(6.0, 4.7, -18.8)), _w(Vector3(6.0, 4.7, -29.7)), _w(Vector3(3.8, 4.4, -35.3)))
		_hop(l2, merge, Vector3(2.0, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# the debris: a torn hull plate behind the panel, wreckage strewn over the trench
	deco.rock(_w(Vector3(8.4, -8.0, -24.7)), _sz(Vector3(2.4, 30.0, 18.0)), 0.0, 0.5)
	_wreck_plate(Vector3(6.85, 4.5, -24.7), Vector3(0.1, 6.6, 16.2))
	deco.rock(_w(Vector3(-0.4, -8.0, -26.0)), _sz(Vector3(2.0, 14.0, 12.0)), 0.0, 0.6)
	AbyssFx.bubbles(self, _w(Vector3(-6.5, -2.0, -30.0)), 14.0, 14, 0.5)
	return cp["c"]


## A rusted steel plate (visual) - the wreck's skin behind a wall-run panel.
func _wreck_plate(c: Vector3, size: Vector3) -> void:
	var rust: StandardMaterial3D = Look.flat(Color(0.22, 0.13, 0.09), 0.85, 0.4)
	add_child(Look.box(_sz(size), rust, _w(c)))
	var rivet: StandardMaterial3D = Look.flat(AMBER, 0.4, 0.0, 1.2)
	for i: int in int(size.z / 2.0):
		add_child(Look.sphere(0.07, rivet, _w(c + Vector3(-size.x * 0.5 - 0.02, size.y * 0.5 - 0.3, -size.z * 0.5 + 1.0 + 2.0 * float(i)))))


# ---- stage 13: The Hull - WALL RUN the submarine's hull, under the hatch press, MANTLE onto the deck -----

func _stage_13() -> Vector3:
	var d: Dictionary = _blk(Vector3(0, 0.6, -9.0), 2.4, 3.0, "alt")
	kit.wallrun(_w(Vector3(2.6, 3.0, -21.0)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var deck: Dictionary = _blk(Vector3(-0.2, 0.6, -36.4), 2.6, 12.0, "alt", 0.8)
	var hatch: Crusher = _hatch(Vector3(-0.2, 0.6, -33.6), 4.6, 0.0)
	var top: Dictionary = _ledge(Vector3(-0.2, 3.9, -46.2), Vector3(4.0, 10.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -56.3))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), d)
	r_wallrun(_w(Vector3(0.5, 0.6, -10.15)), _w(Vector3(2.0, 2.0, -14.2)), _w(Vector3(2.0, 2.0, -23.6)), _w(Vector3(-0.2, 0.6, -31.4)))
	r_walk(_w(Vector3(-0.2, 0.6, -31.2)))
	_wait(func() -> bool: return _press_ok(hatch, 0.0, 0.9 + 1.5), _w(Vector3(-0.2, 0.6, -31.2)))
	r_walk(_w(Vector3(-0.2, 0.6, -42.0)))
	r_mantle(_w(Vector3(-0.2, 0.6, -42.05)), _w(Vector3(-0.2, 3.9, -46.0)))
	_hop(top, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	_sub_hull()
	deck.clear()
	return cp["c"]


## The hatch press: a crusher dressed as a heavy round deck hatch on its hinge arm.
func _hatch(floor_c: Vector3, period: float, phase: float) -> Crusher:
	var size := Vector3(2.6, 0.9, 2.4)
	var cr: Crusher = _anchor_like(floor_c, size, 3.4, period, phase)
	var steel: StandardMaterial3D = Look.flat(Color(0.2, 0.22, 0.2), 0.6, 0.6)
	var wheel := Look.cylinder(0.5, 0.12, Look.flat(AMBER, 0.4, 0.3, 0.8), Vector3(0, size.y * 0.5 + 0.1, 0), -1.0, 16)
	cr.add_child(wheel)
	cr.add_child(Look.box(Vector3(0.3, 0.3, 3.0), steel, Vector3(0, size.y * 0.5 + 0.3, 1.0)))
	return cr


## A crusher with the abyss warning lamps (no anchor dressing).
func _anchor_like(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(floor_c), size, lift, period, fposmod(phase, 1.0), _yaw)
	var tell := AbyssTell.new()
	tell.clip = "abyss_anchor_creak"
	tell.strike_in = func(t: float) -> float:
		var u: float = fposmod(t / cr.period + cr.phase, 1.0)
		return fposmod(Crusher.SLAM - u, 1.0) * cr.period
	tell.striking = func(t: float) -> bool: return not cr.is_clear_for(t, 0.0)
	cr.add_child(tell)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			tell.add_lamp(Vector3(sx * (size.x * 0.5 - 0.2), -size.y * 0.5 + 0.05, sz * (size.z * 0.5 - 0.2)), 0.12)
	return cr


func _sub_hull() -> void:
	# the submarine lies along the stage on its side: the hull you run is its flank (behind the
	# panel), the deck walk its spine; portholes glow along it
	var hull: StandardMaterial3D = Look.flat(Color(0.2, 0.22, 0.2), 0.7, 0.5)
	var body := Look.cylinder(4.2, 44.0, hull, Vector3.ZERO, -1.0, 24)
	body.basis = _b * Basis(Vector3.RIGHT, PI * 0.5)
	body.position = _w(Vector3(7.2, -1.2, -30.0))
	add_child(body)
	var nose := Look.sphere(4.2, hull, _w(Vector3(7.2, -1.2, -8.0)))
	add_child(nose)
	for i: int in 6:
		var port := Look.cylinder(0.3, 0.12, Look.flat(Color(1.0, 0.85, 0.5), 0.3, 0.0, 2.6), _w(Vector3(3.1, -0.6, -12.0 - 5.0 * float(i))), -1.0, 12)
		port.basis = _b * Basis(Vector3.FORWARD, PI * 0.5)
		port.position = _w(Vector3(3.05, -1.4, -12.0 - 5.0 * float(i)))
		add_child(port)
	_keep_out.append(Vector4(_w(Vector3(7.2, 0, -30.0)).x, 0, _w(Vector3(7.2, 0, -30.0)).z, 24.0))


# ---- stage 14: Deck Run - bollards over the flooded deck, two siphonophore curtains, a leap to the tower -
# [shortcut: the knob beside the curtains]

func _stage_14() -> Vector3:
	var b1: Dictionary = _post(Vector3(0, 0, -8.5), 1.2)
	var b2: Dictionary = _post(Vector3(0, 0, -14.0), 1.2)
	var b3: Dictionary = _post(Vector3(0, 0, -19.5), 1.2)
	var plate: Dictionary = _blk(Vector3(0, 0, -28.0), 2.4, 8.0, "alt", 0.8)
	var g1: LaserGate = _curtain(Vector3(0, 0, -27.0), 2.4, 4.5, 0.3, 0.0)
	var g2: LaserGate = _curtain(Vector3(0, 0, -30.0), 2.4, 4.5, 0.3, -0.08)
	var cp: Dictionary = _cp(Vector3(0, 0.6, -39.7))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), b1)
	_hop(b1, b2)
	_hop(b2, b3)
	_hop(b3, plate, Vector3(0, 0, 3.2))
	r_walk(_w(Vector3(0, 0, -25.0)))
	_wait(func() -> bool: return _dark(g1, 0.1, 0.5 + 1.5) and _dark(g2, 0.4, 1.0 + 1.5), _w(Vector3(0, 0, -25.0)))
	r_walk(_w(Vector3(0, 0, -31.4)))
	_hop(plate, cp, Vector3(0, 0, 1.6))
	r_checkpoint()
	# the sub's deck: its hull below the bollards, the tower ahead
	var hull: StandardMaterial3D = Look.flat(Color(0.2, 0.22, 0.2), 0.7, 0.5)
	var body := Look.cylinder(3.6, 40.0, hull, Vector3.ZERO, -1.0, 24)
	body.basis = _b * Basis(Vector3.RIGHT, PI * 0.5)
	body.position = _w(Vector3(0, -5.2, -20.0))
	add_child(body)
	AbyssFx.bubbles(self, _w(Vector3(2.2, -1.5, -11.0)), 8.0, 10, 0.4)
	AbyssFx.bubbles(self, _w(Vector3(-2.2, -1.5, -22.0)), 8.0, 10, 0.4)
	return cp["c"]


# ---- stage 15: Conning Tower - two MANTLES up the tower, a curtain, two glow caps, the finish on top ------

var _tower_light: OmniLight3D


func _stage_15() -> void:
	_ledge(Vector3(0, 3.3, -7.2), Vector3(6.0, 8.0, 3.4))
	_ledge(Vector3(0, 6.6, -10.6), Vector3(4.5, 11.0, 3.4), "alt")
	var walk: Dictionary = _blk(Vector3(0, 6.6, -18.4), 2.6, 8.0, "alt")
	var gate: LaserGate = _curtain(Vector3(0, 6.6, -18.4), 2.6, 4.2, 0.3, 0.0)
	var l1: AbyssLamp = _lamp(Vector3(0, 7.2, -26.8), 0.65, 5.0, 0.72, 0.0, CYAN)
	var l2: AbyssLamp = _lamp(Vector3(0, 7.8, -32.6), 0.65, 5.0, 0.72, -0.12, PINK)
	var deck: Dictionary = {"c": Vector3(0, 8.4, -40.4), "r": 3.0}
	kit.disc(_w(Vector3(0, 8.4, -40.4)), 3.0, 1.2, "main", 0.0)
	_tops.append({"top": _w(Vector3(0, 8.4, -40.4)), "size": Vector3(4.2, 0, 4.2), "drop": 1.2})
	kit.finish(_w(Vector3(0, 8.4, -41.0)), _yaw)
	_finish_pos = _w(Vector3(0, 8.4, -41.0))
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -7.4)))
	r_mantle(_w(Vector3(0, 3.3, -8.55)), _w(Vector3(0, 6.6, -10.8)))
	_hop(_area(Vector3(0, 6.6, -10.6), 2.25, 1.7), walk, Vector3(0, 0, 2.2))
	_wait(func() -> bool: return _dark(gate, 0.0, 0.6 + 1.5) and _lit(l1, 1.0, 1.8 + 1.5) and _lit(l2, 1.6, 2.5 + 1.5), _w(Vector3(0, 6.6, -16.2)))
	r_walk(_w(Vector3(0, 6.6, -21.9)))
	_hop(walk, _lamp_area(Vector3(0, 7.2, -26.8), 0.65))
	_hop(_lamp_area(Vector3(0, 7.2, -26.8), 0.65), _lamp_area(Vector3(0, 7.8, -32.6), 0.65))
	_hop(_lamp_area(Vector3(0, 7.8, -32.6), 0.65), deck)
	r_walk(_w(Vector3(0, 8.4, -41.2)))
	_tower_dress()


func _tower_dress() -> void:
	# the sail: the tower's armoured flanks either side of the climb, its periscope masts and the
	# lamps that blaze when you reach the top
	var hull: StandardMaterial3D = Look.flat(Color(0.2, 0.22, 0.2), 0.7, 0.5)
	var rust: StandardMaterial3D = Look.flat(Color(0.3, 0.16, 0.09), 0.85, 0.3)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(_sz(Vector3(0.6, 12.0, 34.0)), hull, _w(Vector3(sx * 4.6, 1.0, -24.0))))
		add_child(Look.box(_sz(Vector3(0.66, 0.3, 34.0)), rust, _w(Vector3(sx * 4.6, 7.2, -24.0))))
	var mast_base: Vector3 = _w(Vector3(0, 8.4, -43.0))
	add_child(Look.cylinder(0.25, 9.0, hull, mast_base + Vector3(0, 4.5, 0), 0.18, 10))
	add_child(Look.cylinder(0.18, 6.0, hull, mast_base + _d(Vector3(1.2, 3.0, 0.4)), -1.0, 8))
	add_child(Look.box(Vector3(0.4, 0.4, 0.8), Look.flat(AMBER, 0.4, 0.0, 2.0), mast_base + Vector3(0, 9.0, 0)))
	_tower_light = OmniLight3D.new()
	_tower_light.light_color = CYAN
	_tower_light.light_energy = 1.5
	_tower_light.omni_range = 14.0
	_tower_light.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(_tower_light)
	AbyssFx.rising(self, _w(Vector3(0, 8.45, -40.4)), 2.6, 5.0, 36, CYAN)
	_keep_out.append(Vector4(_finish_pos.x, 0, _finish_pos.z, 12.0))


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
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://visual/abyss_sky.gdshader")
	sky.sky_material = sm
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.2, 0.42, 0.55)
	_env.ambient_light_energy = 0.35
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.15
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.008, 0.04, 0.06)
	_env.fog_density = 0.016
	_env.fog_aerial_perspective = 0.0
	_env.fog_sky_affect = 0.6
	_env.fog_sun_scatter = 0.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 0.9
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.2
	_env.adjustment_contrast = 1.12
	# no sun down here: the faintest cold glow from far above, and a deep blue fill
	_sun.light_color = Color(0.3, 0.6, 0.75)
	_sun.light_energy = 0.12
	_sun.rotation_degrees = Vector3(-82, 20, 0)
	_sun.shadow_enabled = false
	_fill.light_color = Color(0.12, 0.3, 0.45)
	_fill.light_energy = 0.12
	_fill.rotation_degrees = Vector3(30, -60, 0)


## Swap every walkable surface to the trench-rock shader with its glowing rim (same colours).
func _abyss_materials() -> void:
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


## Every point the route passes (takeoffs, landings, walk targets) - set dressing keeps clear of them.
func _route_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for st: Dictionary in route:
		for key: String in ["from", "to", "entry", "exit", "top"]:
			if st.has(key) and st[key] is Vector3 and (st[key] as Vector3) != Vector3.ZERO:
				pts.append(st[key])
	for p: Vector3 in _cp_world:
		pts.append(p)
	for r: Dictionary in _tops:
		pts.append(r["top"])
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
	# rock columns under every top, down into the dark
	for r: Dictionary in _tops:
		var top: Vector3 = r["top"]
		var s: Vector3 = r["size"]
		var drop: float = float(r["drop"])
		var rad: float = clampf(minf(s.x, s.z) * 0.32, 0.35, 2.6)
		if maxf(s.x, s.z) >= 8.0 and minf(s.x, s.z) < 4.0:
			var along_x: bool = s.x > s.z
			var n: int = int(maxf(s.x, s.z) / 6.0) + 1
			for i: int in n:
				var k: float = -0.5 + (float(i) + 0.5) / float(n)
				var off: Vector3 = Vector3(k * s.x, 0, 0) if along_x else Vector3(0, 0, k * s.z)
				deco.column(top + off - Vector3(0, drop, 0), rad, FLOOR_Y)
		else:
			deco.column(top - Vector3(0, drop, 0), rad, FLOOR_Y)
	# the trench floor far below and its silt
	deco.trench_floor(Vector3(mid.x, FLOOR_Y, mid.z), maxf(span.x, span.z) * 0.5 + 120.0)
	# the trench walls: great cliffs of rock either side of the course, far out in the dark
	var placed: int = 0
	var tries: int = 0
	while placed < 46 and tries < 700:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 70.0, hi.x + 70.0), 0, rng.randf_range(lo.z - 70.0, hi.z + 70.0))
		var w: float = rng.randf_range(10.0, 26.0)
		var d: float = rng.randf_range(10.0, 26.0)
		if not _clear_of(p, pts, maxf(w, d) * 0.5 + 14.0):
			continue
		var h: float = rng.randf_range(hi.y + 10.0, hi.y + 60.0) - FLOOR_Y
		deco.rock(Vector3(p.x, FLOOR_Y + h * 0.5, p.z), Vector3(w, h, d), rng.randf() * TAU, 0.7)
		if rng.randf() < 0.4:
			deco.kelp(Vector3(p.x + w * 0.3, FLOOR_Y + h, p.z), rng.randf_range(4.0, 9.0), deco.pick_glow())
		_keep_out.append(Vector4(p.x, 0, p.z, maxf(w, d) * 0.6))
		placed += 1
	# far spires and drifting jellyfish out in the dark
	var r0: float = maxf(span.x, span.z) * 0.5 + 90.0
	for i: int in 14:
		var a: float = TAU * float(i) / 14.0 + rng.randf_range(-0.15, 0.15)
		var rr: float = r0 + rng.randf_range(0.0, 80.0)
		deco.spire(Vector3(mid.x + cos(a) * rr, FLOOR_Y, mid.z + sin(a) * rr), rng.randf_range(60.0, 120.0), rng.randf_range(8.0, 16.0))
	var jel: int = 0
	var jt: int = 0
	while jel < 22 and jt < 400:
		jt += 1
		var q := Vector3(rng.randf_range(lo.x - 40.0, hi.x + 40.0), rng.randf_range(lo.y - 6.0, hi.y + 14.0), rng.randf_range(lo.z - 40.0, hi.z + 40.0))
		if not _clear_of(q, pts, 12.0):
			continue
		deco.jelly(q, rng.randf_range(0.6, 1.6), deco.pick_glow())
		jel += 1
	# light shafts from the far-off surface, dying long before the bottom
	for i: int in 7:
		var sx: float = rng.randf_range(lo.x - 20.0, hi.x + 20.0)
		var sz: float = rng.randf_range(lo.z - 20.0, hi.z + 20.0)
		deco.shaft(Vector3(sx, hi.y + 70.0, sz), rng.randf_range(4.0, 9.0), 90.0, Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)), 0.18)
	# ambient life along the whole route: marine snow and plankton between checkpoints
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 3.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 10.0, 8.0, absf(here.z - prev.z) * 0.5 + 10.0)
		AbyssFx.snow(self, c3, ext, 120)
		AbyssFx.plankton(self, c3, ext * 0.8, 40)


# ---- live effects -----------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null:
		return
	if _lamp_light == null:
		# the diver's own lamp: a warm glow that travels with you
		_lamp_light = OmniLight3D.new()
		_lamp_light.light_color = Color(1.0, 0.88, 0.7)
		_lamp_light.light_energy = 1.6
		_lamp_light.omni_range = 9.0
		_lamp_light.omni_attenuation = 1.2
		_lamp_light.shadow_enabled = false
		_lamp_light.position = Vector3(0, 1.6, 0)
		player.add_child(_lamp_light)
	for e: Dictionary in _arrivals:
		e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
		if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
			e["cool"] = 3.0
			for p: GPUParticles3D in e["p"]:
				p.restart()
				p.emitting = true


## The finish: the conning tower's lights blaze on and a great bloom of light pours out of the dark.
func _finish_sequence() -> void:
	var cols: Array[Color] = [CYAN, GREEN, VIOLET, PINK]
	for i: int in 4:
		var fw: GPUParticles3D = AbyssFx.finish_bloom(cols[i], 70)
		fw.position = _finish_pos + Vector3(-6.0 + 4.0 * float(i), 6.0 + float(i % 2) * 3.0, -4.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	# SOUND: abyss_finish - the submarine's horn booming through the deep and a swell of shimmering light
	WorldAudio.at(self, "abyss_finish", _finish_pos + Vector3(0, 6.0, 0), 1.0, 120.0)
	await get_tree().create_timer(0.9).timeout
