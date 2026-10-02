extends LevelBase
## 16. SAKURA PEAKS - a storybook mountain of old Japan at dusk. Eighteen stages, each ending on a
## checkpoint, climbing from a village by a koi pond, through a tea garden and a bamboo forest, up
## the temple stairs and the bell tower, round a pagoda, along a lantern-lit ravine and a cliff
## shrine, across two long swaying rope bridges between the peaks, over the castle moat and the
## ramparts, and up the keep to the top of its roof under the first stars. Cherry trees in full
## blossom everywhere (drifting petals are the level's signature), pagodas with tiered upturned
## roofs, torii tunnels, stone and paper lanterns glowing as the light fails, a misty valley far
## below, distant peaks and a huge low sun.
##
##  1 Koi Pond          hop the bobbing KOI STONES across the village pond, MANTLE onto the tea deck
##  2 Tea Garden        three sinking BLOSSOM PETALS over the stream, WALL RUN the garden wall
##  3 Torii Tunnel      BRANCH: walk the tunnel through the spirit-fire ropes (LASERS) | MANTLE up and
##                      hop along the tops of the gates
##  4 Bamboo Grove      two BAMBOO SPRINGS flick you up the grove's shelves
##  5 Shuriken Walk     cross three SHURIKEN rails on the bamboo boardwalk, MANTLE out
##  6 Moon Gate         BRANCH: a rising chain of six sinking petals | MANTLE, WALL RUN the temple wall
##                      and take the MOON GATE (PORTAL) over the chasm
##  7 Mochi Mill        up the mill race against the water under the two rice mallets (CRUSHERS),
##                      MANTLE out [shortcut: WALL RUN the mill wall past both mallets]
##  8 Temple Stairs     climb three flights past three swinging TEMPLE-BELL LOGS
##  9 Bell Tower        a bamboo spring into the belfry, three WALL RUNS up its chimney, MANTLE out
## 10 Pagoda Eaves      BRANCH: two bamboo springs up the side | three MANTLES up the eaves
## 11 Lantern Ravine    a wave of lantern lights (blinks), the ferry basket across the ravine
##                      [shortcut: leap through the floating moon gate (PORTAL) to the far side]
## 12 Cliff Shrine      three PAPER SLIDING DOORS and a shuriken rail along the cliff veranda
##                      [shortcut: WALL RUN the shrine's outer screen round the last door]
## 13 Rope Bridge       SET PIECE: the long swaying rope bridge between the peaks, its broken spans
##                      jumped between the GUSTS (see the wave of blossom coming)
## 14 High Bridge       SET PIECE: the second, longer bridge - broken spans, a long break crossed on
##                      two sinking petals, the gusts
## 15 Castle Moat       the moat's koi stones, WALL RUN the curved castle wall, MANTLE the rampart
## 16 Ramparts          past the gate rams (PISTONS) and a shuriken rail, a bamboo spring up to the
##                      gatehouse [shortcut: a 90% leap to the bastion's spring, thrown over it all]
## 17 The Keep          two MANTLES up the keep, a bell log on the gallery, WALL RUN round its corner,
##                      MANTLE onto the upper gallery
## 18 Keep Roof         the ridge and its shuriken, two petals, the last bamboo spring up onto the
##                      roof's crown: the finish by the golden roof fish under the first stars
##
## Sakura mechanics (own scripts): SakuraKoi (bobbing stepping stones), SakuraPetal (blossom
## platforms that sink under you), SakuraBamboo (bamboo spring launchers on the clock), SakuraBell
## (swinging bell-log rams), SakuraShuriken (spinning stars on rails), SakuraShoji (sliding paper
## doors), SakuraBridge + SakuraGust (the swaying rope bridges and the gusts that sweep them).
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every
## shortcut.

const VERMILION := Color(0.86, 0.2, 0.12)
const BLOSSOM := Color(1.0, 0.7, 0.8)
const BLOSSOM_PALE := Color(1.0, 0.86, 0.9)
const LANTERN := Color(1.0, 0.6, 0.28)
const JADE := Color(0.45, 0.9, 0.7)
const GOLD := Color(1.0, 0.76, 0.3)
const VALLEY_Y: float = -34.0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: SakuraDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
var _arrivals: Array[Dictionary] = []
## Places set dressing keeps clear of (world x, y, z, flat radius).
var _keep_out: Array[Vector4] = []


func _configure() -> void:
	theme_id = "sakura"
	music_track = "sakura"
	kill_y = VALLEY_Y - 6.0
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


func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, -1.0, _yaw)
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


func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Stand on a launcher at local `from` until it throws us, then steer to local `to`.
func _kick(from: Vector3, to: Vector3) -> void:
	route.append({"kind": "kick", "from": _w(from), "to": _w(to)})


# ---- mechanic builders (local frame) --------------------------------------------------------------

func _koi(c: Vector3, depth: float = 0.6, period: float = 3.0, phase: float = 0.0, r: float = 1.2) -> Dictionary:
	var k := SakuraKoi.new()
	k.radius = r
	k.depth = depth
	k.period = period
	k.phase = phase
	k.position = _w(c)
	add_child(k)
	return {"c": c, "r": r, "node": k}


func _petal(c: Vector3, r: float = 1.3, tint: Color = BLOSSOM) -> Dictionary:
	var p := SakuraPetal.new()
	p.radius = r
	p.tint = tint
	p.bob_phase = kit.rng.randf()
	p.turn = deg_to_rad(_yaw) + kit.rng.randf_range(-0.6, 0.6)
	p.position = _w(c)
	add_child(p)
	return {"c": c, "r": r, "node": p}


## A bamboo spring whose mat (at rest) is at local `c`; its stone base stands on the floor below.
func _bamboo(c: Vector3, period: float, phase: float, launch: Vector3 = Vector3(0, 19, -2.5), base: float = 1.2) -> SakuraBamboo:
	var s := SakuraBamboo.new()
	s.period = period
	s.phase = phase
	s.launch = launch
	s.base_height = base
	s.rotation.y = deg_to_rad(_yaw)
	s.position = _w(c)
	add_child(s)
	return s


## A bell log swinging across the path at local floor point `floor_c` (the path runs along local Z
## at x = floor_c.x). side -1: the frame stands to the left and the log swings out to the right
## (toward its bell); side +1: mirrored.
func _bell(floor_c: Vector3, side: float, period: float, phase: float) -> SakuraBell:
	var b := SakuraBell.new()
	b.period = period
	b.phase = phase
	var h: float = SakuraBell.pivot_height(b.rope_length, b.log_radius)
	b.position = _w(floor_c + Vector3(side * 3.0, h, 0))
	b.rotation.y = deg_to_rad(_yaw + (0.0 if side < 0.0 else 180.0))
	add_child(b)
	return b


func _star(from: Vector3, to_local: Vector3, period: float, phase: float) -> SakuraShuriken:
	var s := SakuraShuriken.new()
	s.to = _d(to_local)
	s.period = period
	s.phase = phase
	s.position = _w(from)
	add_child(s)
	# planks under the rail where it runs out over the drop
	deco.slab(_w(from + to_local * 0.5 + Vector3(0, -0.16, 0)), _sz(Vector3(absf(to_local.x) + 2.2, 0.2, maxf(absf(to_local.z), 0.0) + 1.0)), SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.85))
	return s


func _door(floor_c: Vector3, period: float, phase: float, open_fraction: float = 0.55, wing: float = 3.2) -> SakuraShoji:
	var d := SakuraShoji.new()
	d.wing = wing
	d.period = period
	d.phase = phase
	d.open_fraction = open_fraction
	d.rotation.y = deg_to_rad(_yaw)
	d.position = _w(floor_c)
	add_child(d)
	return d


## A spirit-fire rope (the laser) across the route at local floor point `c` between two torii posts.
func _fire(c: Vector3, width: float, period: float, on: float, phase: float, height: float = 2.4) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.2), period, on, phase, _yaw)
	# a longer flicker before the rope catches fire (the tell reads from well back)
	g.warn = 0.85
	deco.torii(_w(c), width + 0.9, height + 1.6, deg_to_rad(_yaw))
	return g


## A rice mallet (the crusher) dressed as a great wooden pestle.
func _mallet(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	var wood: StandardMaterial3D = SakuraDecor.mat(Color(0.5, 0.35, 0.22), 0.85)
	var r: float = minf(size.x, size.z) * 0.5 + 0.06
	cr.add_child(Look.cylinder(r, size.y + 0.05, wood, Vector3.ZERO, -1.0, 18))
	var band := _tell_material()
	for sy: float in [-1.0, 1.0]:
		cr.add_child(Look.cylinder(r + 0.05, 0.14, band, Vector3(0, sy * (size.y * 0.5 - 0.2), 0), -1.0, 18))
	_tells.append({"node": cr, "period": period, "phase": phase, "at": Crusher.SLAM, "mat": band, "clip": "sakura_mallet_creak", "last": -1})
	cr.add_child(Look.cylinder(0.22, 4.0, wood, Vector3(0, size.y * 0.5 + 2.0, 0), -1.0, 8))
	return cr


## A gate ram (the piston) dressed as a lacquered beam with a bronze cap.
func _ram(top: Vector3, yaw_extra: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.8, 1.3, 1.4)
	var p: Piston = kit.piston(_w(top), size, _yaw + yaw_extra, stroke, period, phase, 8.0)
	var cap := _tell_material()
	p.add_child(Look.box(Vector3(size.x + 0.06, size.y + 0.06, 0.25), cap, Vector3(0, 0, -size.z * 0.5 - 0.1)))
	_tells.append({"node": p, "period": period, "phase": phase, "at": Piston.PUNCH_START, "mat": cap, "clip": "sakura_ram_creak", "last": -1})
	p.add_child(Look.sphere(0.22, SakuraDecor.mat(GOLD, 0.3, 0.8), Vector3(0, 0, -size.z * 0.5 - 0.3)))
	return p


## Timed machines whose shared tell is short get a longer one of our own: a bronze band that glows
## and flashes for TELL seconds before they strike, with a creak. {node, period, phase, at, mat, clip, last}
var _tells: Array[Dictionary] = []
const TELL: float = 0.95


func _tell_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = SakuraDecor.BRONZE
	m.metallic = 0.7
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = Color(1.0, 0.4, 0.15)
	m.emission_energy_multiplier = 0.0
	return m


## Checkpoint landing facing the next stage's heading (_next_yaw), with its lanterns.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var h: float = size * 0.5 - 0.45
	for s: float in [-1.0, 1.0]:
		deco.stone_lantern(_w(c + Vector3(s * h, 0, h)), 0.75, s > 0.0)
	var burst: GPUParticles3D = SakuraFx.petal_pop(1.6, 70, 7.0)
	burst.position = _w(c) + Vector3(0, 0.6, 0)
	add_child(burst)
	var glint: GPUParticles3D = SakuraFx.glints(40)
	glint.position = _w(c) + Vector3(0, 1.4, 0)
	add_child(glint)
	_cp_bursts[cp] = [burst, glint]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: a wind chime and a soft temple bell as a stage is banked
			WorldAudio.at(self, "sakura_chime", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	_rock(c, size * 0.5, 14.0)
	return d


## Fork signpost: two paper lanterns on posts and a floor strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.3, 1.3]:
		var post: Vector3 = _w(p + Vector3(sx, 0, 0))
		add_child(Look.cylinder(0.07, 2.4, SakuraDecor.mat(SakuraDecor.LACQUER, 0.5), post + Vector3(0, 1.2, 0), -1.0, 6))
		deco.paper_lantern(post + Vector3(0, 2.7, 0), 0.32, col)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.6)), _sz(Vector3(1.4, 0.05, 0.3)), col)


## A rocky crag under a landing reaching down into the mist (looks only).
func _rock(c: Vector3, r: float, depth: float) -> void:
	var rk := Look.cylinder(r * 0.9, depth, _rock_mat(), _w(c) - Vector3(0, depth * 0.5 + 1.2, 0), r * 0.35, 7)
	rk.rotation.y = kit.rng.randf() * TAU
	add_child(rk)


var _rock_m: StandardMaterial3D

func _rock_mat() -> StandardMaterial3D:
	if _rock_m == null:
		_rock_m = StandardMaterial3D.new()
		_rock_m.albedo_color = Color(0.3, 0.27, 0.27)
		_rock_m.roughness = 0.95
	return _rock_m


## Still water (a pond or a moat) at local `c` (surface), size x across / z along, and a hidden
## net just under the surface (a fall in is a fall).
func _water(c: Vector3, sx: float, sz: float) -> void:
	var pm := PlaneMesh.new()
	var s: Vector3 = _sz(Vector3(sx, 0, sz))
	pm.size = Vector2(s.x, s.z)
	var w := Look.mesh_node(pm, SakuraDecor.water(), _w(c))
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)
	var k := KillZone.new()
	k.show_mesh = false
	k.size = _sz(Vector3(sx, 1.0, sz))
	k.position = _w(c + Vector3(0, -0.6, 0))
	add_child(k)
	SakuraFx.mist(self, _w(c + Vector3(0, 0.6, 0)), _sz(Vector3(sx * 0.45, 0.3, sz * 0.45)), clampi(int(sx * sz * 0.012), 4, 18), Color(1.0, 0.9, 0.92, 0.16))


## A school of koi circling in the water at world `c` (looks only).
func _koi_school(c: Vector3, radius: float, count: int) -> void:
	var cols: Array[Color] = [Color(1.0, 0.45, 0.15), Color(1.0, 0.95, 0.9), Color(0.95, 0.3, 0.1), Color(1.0, 0.75, 0.3)]
	for i: int in count:
		var holder := Node3D.new()
		holder.set_script(preload("res://visual/spin.gd"))
		holder.set("period", kit.rng.randf_range(9.0, 16.0) * (1.0 if i % 2 == 0 else -1.0))
		holder.position = c + Vector3(kit.rng.randf_range(-1.5, 1.5), -0.25 - kit.rng.randf() * 0.2, kit.rng.randf_range(-1.5, 1.5))
		holder.rotation.y = kit.rng.randf() * TAU
		add_child(holder)
		var r: float = radius * kit.rng.randf_range(0.4, 1.0)
		var body := Look.sphere(0.25, SakuraDecor.mat(cols[i % cols.size()], 0.5), Vector3(r, 0, 0))
		body.scale = Vector3(0.6, 0.45, 1.7)
		holder.add_child(body)
		var tail := Look.sphere(0.18, SakuraDecor.mat(cols[(i + 1) % cols.size()], 0.5), Vector3(r, 0, 0.5 * (1.0 if i % 2 == 0 else -1.0)))
		tail.scale = Vector3(0.3, 0.6, 0.9)
		holder.add_child(tail)


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

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
		if c.gap_at(Game.course_time + s) < 2.0 or not c.is_clear_for(Game.course_time + s, 0.0):
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


## The spring's mat stays down (safe to step onto) over [now + a, now + b].
static func _resting(j: SakuraBamboo, a: float, b: float) -> bool:
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


## The mover stays within r of its spot `at` (world) over [now + a, now + b].
static func _mover_at(m: MovingPlatform, at: Vector3, r: float, a: float, b: float) -> bool:
	var home: Vector3 = m.global_position - m.offset_at(Game.course_time)
	var s: float = a
	while s <= b:
		if (home + m.offset_at(Game.course_time + s)).distance_to(at) > r:
			return false
		s += 0.05
	return true


## The bell log keeps clear of the walking line (world point `p`) over [now + a, now + b].
static func _log_clear(bl: SakuraBell, p: Vector3, a: float, b: float) -> bool:
	var lx: float = bl.to_local(p).x
	return bl.clear_between(lx - 0.4, lx + 0.4, a, b)


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	SakuraDecor.reset()
	add_child(Ambience.make(theme_id))
	deco = SakuraDecor.new(self, kit.rng)
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
	_sakura_materials()


# ---- stage 1: Koi Pond - the bobbing stones across the village pond, mantle onto the tea deck -------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", -1.0, _yaw)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	var k1: Dictionary = _koi(Vector3(0, 0, -11.5), 0.6, 3.0, 0.0)
	var k2: Dictionary = _koi(Vector3(2.2, 0.3, -16.8), 0.6, 3.0, 0.33)
	var k3: Dictionary = _koi(Vector3(-0.6, 0.6, -22.0), 0.6, 3.0, 0.66)
	var d1: Dictionary = _blk(Vector3(0, 0.6, -27.6), 3.0, 3.0, "alt")
	var m1: Dictionary = _ledge(Vector3(0, 3.9, -33.2), Vector3(5.0, 7.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.9, -41.0))
	_hop(start, k1)
	_hop(k1, k2)
	_hop(k2, k3)
	_hop(k3, d1)
	r_mantle(_w(Vector3(0, 0.6, -28.75)), _w(Vector3(0, 3.9, -32.9)))
	_hop(m1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the pond and its koi
	_water(Vector3(0, -1.0, -20.0), 20.0, 26.0)
	_koi_school(_w(Vector3(0, -1.0, -18.0)), 6.0, 10)
	# the village round the plaza: houses, a torii over the start, lanterns strung over the pond
	deco.torii(_w(Vector3(0, 0, 5.0)), 6.0, 5.5, deg_to_rad(_yaw))
	for sx: float in [-1.0, 1.0]:
		deco.house(_w(Vector3(sx * 11.5, 0, 1.0)), 6.0, 5.0, 3.2, deg_to_rad(_yaw) + PI * 0.5)
		deco.house(_w(Vector3(sx * 12.5, 0, -8.0)), 5.0, 6.0, 2.8, deg_to_rad(_yaw))
		kit.plat(_w(Vector3(sx * 12.0, 0, -3.5)), _sz(Vector3(9.0, 2.0, 22.0)), "main", -1.0, _yaw)
		deco.stone_lantern(_w(Vector3(sx * 5.8, 0, -5.8)), 1.0, true)
		deco.cherry_tree(_w(Vector3(sx * 9.0, 0, -6.0)), 1.3)
		deco.lantern_string(_w(Vector3(sx * 5.5, 4.2, -6.0)), _w(Vector3(sx * 5.5, 4.6, -30.0)), 6, 0.9)
	SakuraFx.petals(self, _w(Vector3(0, 5.0, -18.0)), _sz(Vector3(9.0, 4.0, 14.0)), 70)
	SakuraFx.fireflies(self, _w(Vector3(0, 0.8, -18.0)), _sz(Vector3(8.0, 1.2, 12.0)), 30)
	_rock(Vector3(0, 0, 0), 7.0, 20.0)
	return cp["c"]


# ---- stage 2: Tea Garden - sinking petals over the stream, run the garden wall ---------------------

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var p1: Dictionary = _petal(Vector3(0, 0.3, -8.9))
	var p2: Dictionary = _petal(Vector3(1.8, 1.2, -15.6), 1.3, BLOSSOM_PALE)
	var p3: Dictionary = _petal(Vector3(-0.6, 2.0, -21.9))
	var l1: Dictionary = _blk(Vector3(0, 2.4, -28.6), 3.0, 3.0, "alt")
	kit.wallrun(_w(Vector3(2.5, 3.6, -39.6)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(-0.2, 2.4, -52.6), 3.6, 5.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 2.4, -62.0))
	_hop(cp0, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, l1)
	r_wallrun(_w(Vector3(0.5, 2.4, -29.75)), _w(Vector3(2.0, 3.8, -33.7)), _w(Vector3(2.0, 3.8, -44.6)), _w(Vector3(-0.2, 2.4, -51.9)))
	_hop(l2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the garden wall the panel is set in: white plaster under a little tiled coping
	deco.slab(_w(Vector3(3.3, 3.1, -39.6)), _sz(Vector3(0.9, 9.0, 17.0)), SakuraDecor.mat(SakuraDecor.PLASTER, 0.9))
	deco.slab(_w(Vector3(3.3, 7.75, -39.6)), _sz(Vector3(1.6, 0.3, 17.6)), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15))
	# the stream below, a tea house beyond the wall, maples and blossom round the garden
	_water(Vector3(0, -5.0, -32.0), 12.0, 54.0)
	deco.house(_w(Vector3(10.0, 0.0, -39.6)), 7.0, 6.0, 3.0, deg_to_rad(_yaw))
	kit.plat(_w(Vector3(10.0, 0.0, -39.6)), _sz(Vector3(11.0, 1.0, 10.0)), "main", -1.0, _yaw)
	for z: float in [-12.0, -24.0]:
		deco.cherry_tree(_w(Vector3(-7.0, -5.0, z)), 1.6)
		SakuraFx.shed(self, _w(Vector3(-7.0, 0.5, z)), 2.6, 9.0, 16)
	SakuraFx.petals(self, _w(Vector3(0, 5.0, -16.0)), _sz(Vector3(6.0, 4.0, 10.0)), 60)
	cp0.clear()
	return cp["c"]


# ---- stage 3: Torii Tunnel (BRANCH) - walk through the spirit fire, or hop along the gate tops ----

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (lantern): the tunnel floor and its three spirit-fire ropes
	_blk(Vector3(-3.5, 0, -14.5), 2.2, 9.0, "alt")
	_blk(Vector3(-3.5, 0, -25.5), 2.2, 6.0, "alt")
	_blk(Vector3(-3.5, 0, -35.25), 2.2, 9.5, "alt")
	var f1: LaserGate = _fire(Vector3(-3.5, 0, -14.0), 2.2, 3.0, 0.35, 0.0)
	var f2: LaserGate = _fire(Vector3(-3.5, 0, -25.6), 2.2, 3.0, 0.35, 0.3)
	var f3: LaserGate = _fire(Vector3(-3.5, 0, -33.4), 2.2, 3.0, 0.35, 0.6)
	# the rest of the tunnel: closely spaced gates over the walk
	for z: float in [-11.0, -17.5, -23.3, -28.0, -31.2, -36.4, -39.4]:
		deco.torii(_w(Vector3(-3.5, 0, z)), 3.1, 4.0, deg_to_rad(_yaw))
	# RIGHT (jade): mantle the first great gate's plinth, then hop along the tops of the gates
	var m: Dictionary = _ledge(Vector3(3.5, 3.4, -12.4), Vector3(3.0, 7.4, 3.0), "alt")
	var beams: Array[Dictionary] = []
	for z: float in [-17.6, -23.6, -29.6, -35.6]:
		beams.append(_blk(Vector3(3.5, 3.4, z), 3.4, 1.4, "accent", 0.7))
		deco.torii(_w(Vector3(3.5, -6.0, z)), 2.6, 8.8, deg_to_rad(_yaw))
	var merge: Dictionary = _blk(Vector3(0, 0, -42.0), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 0, -50.5))
	_sign(Vector3(-3.5, 0, -6.6), LANTERN)
	_sign(Vector3(3.5, 0, -6.6), JADE)
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -9.6)))
		r_walk(_w(Vector3(-3.5, 0, -12.4)))
		_wait(func() -> bool: return _dark(f1, 0.0, 1.5))
		r_walk(_w(Vector3(-3.5, 0, -18.4)))
		r_jump(_w(Vector3(-3.5, 0, -18.65)), _w(Vector3(-3.5, 0, -23.6)))
		r_walk(_w(Vector3(-3.5, 0, -24.0)))
		_wait(func() -> bool: return _dark(f2, 0.0, 1.5))
		r_walk(_w(Vector3(-3.5, 0, -28.0)))
		r_jump(_w(Vector3(-3.5, 0, -28.15)), _w(Vector3(-3.5, 0, -31.4)))
		r_walk(_w(Vector3(-3.5, 0, -31.8)))
		_wait(func() -> bool: return _dark(f3, 0.0, 1.5))
		r_walk(_w(Vector3(-3.5, 0, -39.4)))
		r_walk(_w(Vector3(-1.0, 0, -41.0)))
	else:
		r_walk(_w(Vector3(3.5, 0, -8.6)))
		r_mantle(_w(Vector3(3.5, 0, -9.65)), _w(Vector3(3.5, 3.4, -12.2)))
		var prev: Dictionary = m
		for bm: Dictionary in beams:
			_hop(prev, bm)
			prev = bm
		_hop(prev, merge, Vector3(2.0, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the ravine under the tunnel, blossom trees on its far bank
	for z: float in [-14.0, -30.0]:
		deco.cherry_tree(_w(Vector3(-10.0, -4.0, z)), 1.5)
		deco.cherry_tree(_w(Vector3(10.0, -3.0, z - 4.0)), 1.4, BLOSSOM_PALE)
		kit.plat(_w(Vector3(-10.0, -4.0, z)), _sz(Vector3(6.0, 1.0, 6.0)), "main", -1.0, _yaw)
		kit.plat(_w(Vector3(10.0, -3.0, z - 4.0)), _sz(Vector3(6.0, 1.0, 6.0)), "main", -1.0, _yaw)
	SakuraFx.fireflies(self, _w(Vector3(-3.5, 1.5, -24.0)), _sz(Vector3(1.4, 1.0, 12.0)), 30)
	SakuraFx.petals(self, _w(Vector3(0, 6.0, -24.0)), _sz(Vector3(8.0, 4.0, 14.0)), 60)
	return cp["c"]


# ---- stage 4: Bamboo Grove - two bamboo springs up the grove's shelves -----------------------------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f0: Dictionary = _blk(Vector3(0, 0, -8.5), 6.0, 5.0)
	var ba: SakuraBamboo = _bamboo(Vector3(0, 1.2, -9.6), 3.2, 0.0)
	_blk(Vector3(0, 5.8, -16.5), 5.0, 6.0, "alt")
	var bb: SakuraBamboo = _bamboo(Vector3(0, 7.0, -18.0), 3.2, 0.5)
	var sh2: Dictionary = _blk(Vector3(0, 12.0, -24.8), 4.0, 5.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 12.0, -34.8))
	_hop(cp0, f0, Vector3(0, 0, 0.8))
	_wait(func() -> bool: return _resting(ba, 0.0, 1.8))
	r_jump(_w(Vector3(0, 0, -7.3)), _w(Vector3(0, 1.2, -9.6)))
	_kick(Vector3(0, 1.2, -9.6), Vector3(0, 5.8, -15.0))
	_wait(func() -> bool: return _resting(bb, 0.0, 1.8))
	r_jump(_w(Vector3(0, 5.8, -15.4)), _w(Vector3(0, 7.0, -18.0)))
	_kick(Vector3(0, 7.0, -18.0), Vector3(0, 12.0, -24.4))
	_hop(sh2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the grove: walls of bamboo either side, a little shrine on the top shelf
	for sx: float in [-1.0, 1.0]:
		for z: float in [-6.0, -13.0, -20.0, -27.0]:
			deco.bamboo_clump(_w(Vector3(sx * (6.5 + kit.rng.randf() * 1.5), -3.0, z)), 7, 18.0, 1.6)
	deco.stone_lantern(_w(Vector3(-1.6, 12.0, -26.6)), 0.7, true)
	SakuraFx.fireflies(self, _w(Vector3(0, 7.0, -17.0)), _sz(Vector3(4.0, 7.0, 10.0)), 40)
	SakuraFx.petals(self, _w(Vector3(0, 12.0, -18.0)), _sz(Vector3(5.0, 6.0, 10.0)), 40)
	_rock(Vector3(0, 0, -8.5), 3.0, 16.0)
	return cp["c"]


# ---- stage 5: Shuriken Walk - three spinning stars across the bamboo boardwalk, mantle out ---------

func _stage_5() -> Vector3:
	var a: Dictionary = _blk(Vector3(0, 0, -7.5), 2.4, 9.0, "alt")
	var b: Dictionary = _blk(Vector3(0, 0.6, -21.0), 2.4, 9.0, "alt")
	var c: Dictionary = _blk(Vector3(0, 1.2, -34.5), 2.4, 9.0, "alt")
	var m: Dictionary = _ledge(Vector3(0, 4.6, -43.2), Vector3(3.4, 8.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 4.6, -51.5))
	var s1: SakuraShuriken = _star(Vector3(-5.0, 0, -8.0), Vector3(10.0, 0, 0), 5.2, 0.0)
	var s2: SakuraShuriken = _star(Vector3(5.0, 0.6, -21.0), Vector3(-10.0, 0, 0), 5.2, 0.33)
	var s3: SakuraShuriken = _star(Vector3(-5.0, 1.2, -34.5), Vector3(10.0, 0, 0), 5.2, 0.66)
	var x1: Vector3 = _w(Vector3(0, 0, -8.0))
	var x2: Vector3 = _w(Vector3(0, 0.6, -21.0))
	var x3: Vector3 = _w(Vector3(0, 1.2, -34.5))
	r_walk(_w(Vector3(0, 0, -5.8)))
	_wait(func() -> bool: return s1.lane_clear(x1, 1.8, 0.0, 1.7))
	r_walk(_w(Vector3(0, 0, -11.3)))
	_hop(a, b, Vector3(0, 0, 2.6))
	r_walk(_w(Vector3(0, 0.6, -18.8)))
	_wait(func() -> bool: return s2.lane_clear(x2, 1.8, 0.0, 1.7))
	r_walk(_w(Vector3(0, 0.6, -24.8)))
	_hop(b, c, Vector3(0, 0, 2.6))
	r_walk(_w(Vector3(0, 1.2, -32.3)))
	_wait(func() -> bool: return s3.lane_clear(x3, 1.8, 0.0, 1.7))
	r_walk(_w(Vector3(0, 1.2, -38.0)))
	r_mantle(_w(Vector3(0, 1.2, -38.65)), _w(Vector3(0, 4.6, -43.0)))
	_hop(m, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	c.clear()
	# bamboo crowding the boardwalk, lanterns on posts
	for sx: float in [-1.0, 1.0]:
		for z: float in [-3.0, -14.0, -26.0, -38.0]:
			deco.bamboo_clump(_w(Vector3(sx * (8.5 + kit.rng.randf() * 2.0), -4.0, z)), 6, 20.0, 1.8)
	for z: float in [-14.2, -27.8]:
		var lp: Vector3 = _w(Vector3(-1.8, 3.4 + (0.6 if z < -20.0 else 0.0), z))
		deco.paper_lantern(lp, 0.3, LANTERN)
		deco.rope(lp + Vector3(0, 0.4, 0), lp + Vector3(0, 7.0, 0), 0.0, 0.02, Color(0.3, 0.22, 0.16))
	SakuraFx.fireflies(self, _w(Vector3(0, 2.0, -20.0)), _sz(Vector3(3.0, 1.5, 16.0)), 36)
	SakuraFx.mist(self, _w(Vector3(0, -6.0, -22.0)), _sz(Vector3(10.0, 2.0, 20.0)), 14)
	return cp["c"]


# ---- stage 6: Moon Gate (BRANCH) - the rising petals, or the temple wall and the moon gate --------

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (blossom): six petals climbing over the chasm
	var pz: Array[Vector3] = [Vector3(-3.5, 0, -14.5), Vector3(-3.5, 1.1, -21.3), Vector3(-2.5, 2.1, -27.9),
			Vector3(-3.5, 3.1, -34.4), Vector3(-2.5, 4.0, -41.0), Vector3(-3.5, 4.4, -47.6)]
	var petals: Array[Dictionary] = []
	for i: int in pz.size():
		petals.append(_petal(pz[i], 1.3, BLOSSOM if i % 2 == 0 else BLOSSOM_PALE))
	# RIGHT (jade): mantle the temple wall's buttress, run the wall, the moon gate on the terrace
	_ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 7.3, 3.2), "alt")
	kit.wallrun(_w(Vector3(6.5, 4.5, -24.7)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	_blk(Vector3(3.8, 4.4, -36.0), 3.6, 4.0, "alt")
	var portal: WarpPortal = kit.portal(_w(Vector3(3.8, 4.4, -37.4)), _yaw, _w(Vector3(2.0, 4.4, -54.6)), _yaw, 7.0)
	_moon_gate(Vector3(3.8, 4.4, -37.4))
	_arrival(Vector3(2.0, 4.4, -55.2))
	var merge: Dictionary = _blk(Vector3(0, 4.4, -55.4), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 4.4, -64.0))
	deco.slab(_w(Vector3(7.3, 3.5, -24.7)), _sz(Vector3(0.9, 12.0, 17.0)), SakuraDecor.mat(SakuraDecor.PLASTER, 0.9))
	deco.slab(_w(Vector3(7.3, 9.6, -24.7)), _sz(Vector3(1.8, 0.3, 17.6)), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15))
	_sign(Vector3(-3.5, 0, -6.6), BLOSSOM)
	_sign(Vector3(4.0, 0, -6.6), JADE)
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.6)))
		var prev: Dictionary = _area(Vector3(-3.5, 0, -8.0), 1.5, 2.0)
		for p: Dictionary in petals:
			_hop(prev, p)
			prev = p
		_hop(prev, merge, Vector3(-3.0, 0, 0.8))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(4.3, 3.3, -14.85)), _w(Vector3(6.0, 4.7, -18.8)), _w(Vector3(6.0, 4.7, -29.7)), _w(Vector3(3.8, 4.4, -35.3)))
		r_portal(_w(Vector3(3.8, 4.4, -37.6)), portal.exit_point())
		r_walk(_w(Vector3(1.0, 4.4, -56.0)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the chasm: mist far below, a waterfall off the temple terrace, blossom over the petals
	SakuraFx.mist(self, _w(Vector3(0, -8.0, -30.0)), _sz(Vector3(12.0, 2.0, 22.0)), 16)
	SakuraFx.petals(self, _w(Vector3(-3.0, 6.0, -28.0)), _sz(Vector3(4.0, 4.0, 16.0)), 70)
	deco.cherry_tree(_w(Vector3(-9.0, -2.0, -22.0)), 1.6)
	deco.cherry_tree(_w(Vector3(-10.0, 0.0, -42.0)), 1.4, BLOSSOM_PALE)
	kit.plat(_w(Vector3(-9.0, -2.0, -22.0)), _sz(Vector3(5.0, 1.0, 5.0)), "main", -1.0, _yaw)
	kit.plat(_w(Vector3(-10.0, 0.0, -42.0)), _sz(Vector3(5.0, 1.0, 5.0)), "main", -1.0, _yaw)
	SakuraFx.shed(self, _w(Vector3(-9.0, 3.0, -22.0)), 2.6, 10.0, 16)
	SakuraFx.waterfall(self, _w(Vector3(-13.5, 9.0, -31.0)), 3.0, 24.0, deg_to_rad(_yaw + 90.0))
	deco.slab(_w(Vector3(-15.2, -4.0, -31.0)), _sz(Vector3(3.0, 30.0, 12.0)), _rock_mat())
	deco.pagoda(_w(Vector3(14.0, -6.0, -30.0)), 3, 1.0, deg_to_rad(_yaw))
	return cp["c"]


## The moon gate: a round opening in a short plaster wall, framed in dark wood, round the portal.
func _moon_gate(floor_c: Vector3) -> void:
	var c: Vector3 = floor_c + Vector3(0, WarpPortal.RING_RADIUS, 0)
	var tm := TorusMesh.new()
	tm.inner_radius = WarpPortal.RING_RADIUS + 0.25
	tm.outer_radius = WarpPortal.RING_RADIUS + 0.55
	tm.rings = 40
	tm.ring_segments = 8
	var ring := Look.mesh_node(tm, SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.6), _w(c))
	ring.rotation = Vector3(PI * 0.5, deg_to_rad(_yaw), 0)
	add_child(ring)
	for sx: float in [-1.0, 1.0]:
		deco.slab(_w(c + Vector3(sx * (WarpPortal.RING_RADIUS + 1.4), -0.1, 0)), _sz(Vector3(1.8, 3.4, 0.4)), SakuraDecor.mat(SakuraDecor.PLASTER, 0.9))
	deco.slab(_w(c + Vector3(0, 2.1, 0)), _sz(Vector3(6.6, 0.3, 1.0)), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15))


## A burst of blossom and glints where a portal lets you out (fired when you arrive).
func _arrival(at: Vector3) -> void:
	var p: GPUParticles3D = SakuraFx.petal_pop(1.0, 40, 6.0)
	p.position = _w(at + Vector3(0, 0.6, 0))
	add_child(p)
	var g: GPUParticles3D = SakuraFx.glints(30, Fx.hot(JADE, 2.2))
	g.position = _w(at + Vector3(0, 1.0, 0))
	add_child(g)
	_arrivals.append({"at": _w(at), "p": [p, g], "cool": 0.0})


# ---- stage 7: Mochi Mill - up the mill race under the two rice mallets ------------------------------

func _stage_7() -> Vector3:
	kit.conveyor(_w(Vector3(0, 0, -16.0)), Vector3(2.8, 0.4, 20.0), _yaw + 180.0, 2.5)
	kit.block(_w(Vector3(0, -1.0, -16.0)), _sz(Vector3(2.4, 1.6, 19.6)), Color(0.3, 0.22, 0.16), false)
	var p1: Crusher = _mallet(Vector3(0, 0, -12.0), Vector3(3.2, 1.4, 3.0), 3.4, 4.4, 0.0)
	var p2: Crusher = _mallet(Vector3(0, 0, -20.0), Vector3(3.2, 1.4, 3.0), 3.4, 4.4, 0.72)
	var top: Dictionary = _ledge(Vector3(0, 3.3, -30.5), Vector3(4.0, 7.3, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -40.0))
	# SHORTCUT: the mill wall - a wall-run panel along the race's left, clear of the mallets' frames
	kit.wallrun(_w(Vector3(-3.6, 2.0, -18.0)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	deco.slab(_w(Vector3(-4.3, 2.0, -18.0)), _sz(Vector3(0.8, 9.0, 17.0)), SakuraDecor.mat(SakuraDecor.PLASTER, 0.9))
	deco.slab(_w(Vector3(-4.3, 6.6, -18.0)), _sz(Vector3(1.5, 0.3, 17.6)), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15))
	if route_variant == 2:
		r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -6.6)))
		r_wallrun(_w(Vector3(-0.6, 0, -7.6)), _w(Vector3(-3.0, 1.4, -12.6)), _w(Vector3(-3.0, 1.4, -23.4)), _w(Vector3(0, 3.3, -30.0)))
	else:
		r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -7.0)))
		_wait(func() -> bool: return _press_ok(p1, 0.0, 2.4) and _press_ok(p2, 1.1, 3.6), _w(Vector3(0, 0, -7.4)))
		r_walk(_w(Vector3(0, 0, -25.0)))
		r_mantle(_w(Vector3(0, 0, -25.6)), _w(Vector3(0, 3.3, -30.1)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the mill: a great water wheel turning beside the race, the mortar troughs, spray
	kit.gear(_w(Vector3(3.6, 2.5, -16.0)), 4.0, 12, 0.8, -8.0, Vector3(0, deg_to_rad(_yaw), 90), Color(0.45, 0.32, 0.2))
	SakuraFx.spray(self, _w(Vector3(3.6, -1.0, -16.0)), _sz(Vector3(0.6, 0.3, 3.0)), 24)
	SakuraFx.waterfall(self, _w(Vector3(3.6, 9.5, -16.0)), 1.2, 3.2, deg_to_rad(_yaw + 90.0))
	deco.slab(_w(Vector3(3.6, 9.7, -16.0)), _sz(Vector3(0.6, 0.4, 3.0)), SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.8))
	SakuraFx.spray(self, _w(Vector3(0, 0.1, -24.0)), _sz(Vector3(1.2, 0.1, 2.0)), 16)
	_water(Vector3(0, -4.0, -18.0), 12.0, 30.0)
	deco.house(_w(Vector3(8.0, -1.0, -10.0)), 5.0, 6.0, 3.6, deg_to_rad(_yaw))
	return cp["c"]


# ---- stage 8: Temple Stairs - three flights, three swinging bell logs -------------------------------

func _stage_8() -> Vector3:
	kit.ramp(_w(Vector3(0, 2.0, -9.0)), Vector3(3.4, 0.6, sqrt(12.0 * 12.0 + 4.0 * 4.0)), rad_to_deg(atan(4.0 / 12.0)), _yaw, "main")
	_blk(Vector3(0, 4.0, -18.0), 3.4, 6.0)
	var g1: SakuraBell = _bell(Vector3(0, 4.0, -18.0), -1.0, 4.8, 0.0)
	kit.ramp(_w(Vector3(0, 5.5, -26.0)), Vector3(3.4, 0.6, sqrt(10.0 * 10.0 + 3.0 * 3.0)), rad_to_deg(atan(3.0 / 10.0)), _yaw, "main")
	var l2: Dictionary = _blk(Vector3(0, 7.0, -34.0), 3.4, 6.0)
	var g2: SakuraBell = _bell(Vector3(0, 7.0, -34.0), 1.0, 4.8, 0.4)
	var l3: Dictionary = _blk(Vector3(0, 8.2, -43.3), 3.4, 4.0)
	kit.ramp(_w(Vector3(0, 9.7, -50.3)), Vector3(3.4, 0.6, sqrt(10.0 * 10.0 + 3.0 * 3.0)), rad_to_deg(atan(3.0 / 10.0)), _yaw, "main")
	var l4: Dictionary = _blk(Vector3(0, 11.2, -58.3), 3.4, 6.0)
	var g3: SakuraBell = _bell(Vector3(0, 11.2, -58.3), -1.0, 4.8, 0.75)
	var cp: Dictionary = _cp(Vector3(0, 11.2, -67.8))
	var x1: Vector3 = _w(Vector3(0, 4.0, -18.0))
	var x2: Vector3 = _w(Vector3(0, 7.0, -34.0))
	var x3: Vector3 = _w(Vector3(0, 11.2, -58.3))
	r_walk(_w(Vector3(0, 4.0, -15.6)))
	_wait(func() -> bool: return _log_clear(g1, x1, 0.0, 1.9))
	r_walk(_w(Vector3(0, 4.0, -21.0)))
	r_walk(_w(Vector3(0, 7.0, -31.6)))
	_wait(func() -> bool: return _log_clear(g2, x2, 0.0, 1.9))
	r_walk(_w(Vector3(0, 7.0, -36.6)))
	_hop(l2, l3, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(0, 11.2, -55.9)))
	_wait(func() -> bool: return _log_clear(g3, x3, 0.0, 1.9))
	r_walk(_w(Vector3(0, 11.2, -60.4)))
	_hop(l4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# stone lanterns lining the flights, blossom trees on the hillside, the temple gate at the top
	for z: float in [-5.0, -11.0, -24.0, -29.0, -48.0, -53.0]:
		var y: float = (-3.0 - z) / 3.0
		if z < -16.0:
			y = 4.0 + (-21.0 - z) * 0.3 if z > -32.0 else 8.2 + (-45.3 - z) * 0.3
		for sx: float in [-1.0, 1.0]:
			deco.stone_lantern(_w(Vector3(sx * 2.3, y - 0.3, z)), 0.7)
	for z: float in [-12.0, -40.0, -52.0]:
		for sx: float in [-1.0, 1.0]:
			deco.cherry_tree(_w(Vector3(sx * 8.0, (4.0 if z > -30.0 else 8.0) - 4.0, z)), 1.5, BLOSSOM if sx < 0.0 else BLOSSOM_PALE)
	SakuraFx.petals(self, _w(Vector3(0, 9.0, -35.0)), _sz(Vector3(6.0, 6.0, 26.0)), 90)
	SakuraFx.fireflies(self, _w(Vector3(0, 6.0, -35.0)), _sz(Vector3(5.0, 4.0, 24.0)), 30)
	_rock(Vector3(0, 7.0, -34.0), 2.5, 18.0)
	_rock(Vector3(0, 11.2, -58.3), 2.5, 20.0)
	return cp["c"]


# ---- stage 9: Bell Tower - a bamboo spring into the belfry, three wall runs up the chimney ---------

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var f: Dictionary = _blk(Vector3(0, 0, -9.6), 5.0, 6.0, "alt", 1.2)
	var ja: SakuraBamboo = _bamboo(Vector3(0, 1.2, -9.8), 3.2, 0.3)
	_blk(Vector3(0, 6.0, -15.2), 3.0, 3.0, "main", 1.2)
	_chimney_panel(2.3, 7.2, -19.5, -26.0)
	_chimney_panel(-2.3, 12.0, -24.5, -32.5)
	_chimney_panel(2.3, 15.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 17.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 17.9, -51.2))
	_hop(cp0, f, Vector3(0, 0, 1.6))
	_wait(func() -> bool: return _resting(ja, 0.0, 1.8))
	r_jump(_w(Vector3(0, 0, -8.0)), _w(Vector3(0, 1.2, -9.8)))
	_kick(Vector3(0, 1.2, -9.8), Vector3(0, 6.0, -14.8))
	r_walk(_w(Vector3(0, 6.0, -13.9)))
	r_wallrun(_w(Vector3(0.5, 6.0, -15.85)), _w(Vector3(1.7, 7.4, -20.6)), _w(Vector3(1.7, 7.4, -23.5)), _w(Vector3(-1.7, 11.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 11.5, -27.4)), _w(Vector3(-1.7, 11.5, -30.4)), _w(Vector3(1.7, 14.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 14.5, -34.0)), _w(Vector3(1.7, 14.5, -35.4)), _w(Vector3(-0.75, 17.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the belfry roof over the top and the great bell hanging in it (clear above the landing)
	deco.roof(_w(Vector3(0, 29.0, -51.2)), 9.0, 9.0, 3.0, deg_to_rad(_yaw))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.4, 11.1, 0.4), SakuraDecor.mat(VERMILION, 0.55), _w(Vector3(sx * 3.6, 23.45, -51.2 + sz * 3.6))))
	deco.temple_bell(_w(Vector3(0, 28.6, -51.2)), 1.3)
	SakuraFx.fireflies(self, _w(Vector3(0, 12.0, -28.0)), _sz(Vector3(2.0, 8.0, 10.0)), 30)
	SakuraFx.petals(self, _w(Vector3(0, 14.0, -30.0)), _sz(Vector3(4.0, 8.0, 12.0)), 50)
	_rock(Vector3(0, 0, -9.6), 2.6, 16.0)
	return cp["c"]


## A chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by a belfry wall.
func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	deco.slab(_w(Vector3(x + signf(x) * 0.55, y, (z0 + z1) * 0.5)), _sz(Vector3(0.6, height + 2.0, absf(z0 - z1) + 1.0)), SakuraDecor.mat(VERMILION.darkened(0.25), 0.7))


# ---- stage 10: Pagoda Eaves (BRANCH) - two springs up the side, or three mantles up the eaves ------

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (bamboo): two springs
	_blk(Vector3(-3.5, 0, -12.6), 4.0, 5.0, "alt")
	var ba: SakuraBamboo = _bamboo(Vector3(-3.5, 1.2, -12.8), 3.2, 0.0)
	_blk(Vector3(-3.5, 5.0, -19.5), 4.0, 5.0, "alt")
	var bb: SakuraBamboo = _bamboo(Vector3(-3.5, 6.2, -20.0), 3.2, 0.5)
	# RIGHT (vermilion): three eaves, mantled one after another
	var m3: Dictionary = {}
	for i: int in 3:
		m3 = _ledge(Vector3(3.5, 3.3 * float(i + 1), -12.2 - 3.4 * float(i)), Vector3(3.4, 7.3 + 3.3 * float(i), 3.4), "alt")
		deco.roof(_w(Vector3(6.4, 3.3 * float(i + 1) - 1.0, -15.6)), 2.4, 12.0, 1.0, deg_to_rad(_yaw))
	var merge: Dictionary = _blk(Vector3(0, 9.9, -26.5), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 9.9, -35.5))
	_sign(Vector3(-3.5, 0, -6.6), Color(0.6, 0.95, 0.5))
	_sign(Vector3(3.5, 0, -6.6), VERMILION)
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -9.6)))
		_wait(func() -> bool: return _resting(ba, 0.0, 1.8))
		r_jump(_w(Vector3(-3.5, 0, -10.6)), _w(Vector3(-3.5, 1.2, -12.8)))
		_kick(Vector3(-3.5, 1.2, -12.8), Vector3(-3.5, 5.0, -18.6))
		_wait(func() -> bool: return _resting(bb, 0.0, 1.8))
		r_jump(_w(Vector3(-3.5, 5.0, -17.7)), _w(Vector3(-3.5, 6.2, -20.0)))
		_kick(Vector3(-3.5, 6.2, -20.0), Vector3(-2.5, 9.9, -25.8))
	else:
		r_walk(_w(Vector3(3.5, 0, -9.0)))
		r_mantle(_w(Vector3(3.5, 0, -9.85)), _w(Vector3(3.5, 3.3, -11.8)))
		r_mantle(_w(Vector3(3.5, 3.3, -13.55)), _w(Vector3(3.5, 6.6, -15.4)))
		r_mantle(_w(Vector3(3.5, 6.6, -16.95)), _w(Vector3(3.5, 9.9, -18.8)))
		_hop(m3, merge, Vector3(2.5, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the pagoda itself towering beside the eaves, bamboo up the far side
	deco.pagoda(_w(Vector3(14.5, -8.0, -18.0)), 5, 1.2, deg_to_rad(_yaw))
	for z: float in [-8.0, -16.0, -24.0]:
		deco.bamboo_clump(_w(Vector3(-9.5, -6.0, z)), 6, 20.0, 1.5)
	SakuraFx.petals(self, _w(Vector3(0, 8.0, -18.0)), _sz(Vector3(8.0, 6.0, 10.0)), 70)
	SakuraFx.fireflies(self, _w(Vector3(-3.5, 6.0, -16.0)), _sz(Vector3(2.0, 6.0, 6.0)), 24)
	return cp["c"]


# ---- stage 11: Lantern Ravine - a wave of lantern lights, the ferry basket -------------------------

var _ferry: MovingPlatform


func _stage_11() -> Vector3:
	var mz: Array[Vector3] = [Vector3(0, 0, -8.6), Vector3(0, 0.6, -14.65), Vector3(1.1, 1.2, -20.55), Vector3(0.1, 1.2, -27.6)]
	var lights: Array[BlinkPlatform] = []
	for i: int in mz.size():
		lights.append(kit.blink(_w(mz[i]), _sz(Vector3(2.1, 0.5, 2.1)), 4.0, 0.6, fposmod(-0.2125 * float(i), 1.0)))
		lights[i].warn = 0.8
		var top: Vector3 = _w(mz[i] + Vector3(0, 3.6, 0))
		deco.paper_lantern(top, 0.42, [LANTERN, Color(1.0, 0.4, 0.3), Color(1.0, 0.8, 0.45)][i % 3])
		deco.rope(top + Vector3(0, 0.5, 0), top + Vector3(0, 6.0, 0), 0.0, 0.025, Color(0.3, 0.22, 0.16))
	var st: Dictionary = _blk(Vector3(0, 1.2, -34.6), 4.0, 4.0, "alt")
	_ferry = kit.mover(_w(Vector3(0, 1.2, -39.6)), Vector3(2.6, 0.5, 2.6), [Vector3.ZERO, _d(Vector3(0, 0, -12.0))], 8.0, 0.0)
	_ferry.dwell = 0.3
	_basket(_ferry)
	var e: Dictionary = _blk(Vector3(0, 1.2, -57.6), 4.0, 4.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 1.2, -67.0))
	# SHORTCUT: the floating moon gate off the checkpoint's left corner - leap through it and you come
	# out on the far landing, past the lights and the ferry
	kit.portal(_w(Vector3(-4.6, -0.6, -9.2)), _yaw + 16.6, _w(Vector3(0, 1.2, -56.0)), _yaw, 6.0)
	_moon_ring(Vector3(-4.6, -0.6, -9.2), 16.6)
	_arrival(Vector3(0, 1.2, -57.6))
	if route_variant == 2:
		r_walk(_w(Vector3(-1.9, 0, -1.9)))
		route.append({"kind": "b_jump", "from": _w(Vector3(-2.65, 0, -2.65)), "to": _w(Vector3(-4.6, 0.6, -9.2)), "hold": true})
		r_walk(_w(Vector3(0, 1.2, -58.4)))
	else:
		# when the bot lands on each light (from the checkpoint's edge, at its pace of a hop every 0.85 s)
		var starts: Array[float] = [1.1, 1.95, 2.8, 3.65]
		_wait(func() -> bool:
			for i: int in lights.size():
				if not _blink_ok(lights[i], starts[i] - 0.25, starts[i] + 1.5):
					return false
			return true)
		var prev: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
		for i: int in mz.size():
			var mm: Dictionary = _area(mz[i], 1.05, 1.05)
			_hop(prev, mm)
			prev = mm
		_hop(prev, st, Vector3(0, 0, 1.0))
		var home: Vector3 = _w(Vector3(0, 0.95, -39.6))
		var far: Vector3 = _w(Vector3(0, 0.95, -51.6))
		var ferry: MovingPlatform = _ferry
		r_walk(_w(Vector3(0, 1.2, -36.0)))
		_wait(func() -> bool: return _mover_at(ferry, home, 0.3, 0.0, 1.7))
		r_jump_onto(_w(Vector3(0, 1.2, -36.3)), _ferry, Vector3(0, 0.25, 0))
		r_jump_from_ride(_ferry, far, 0.3, _w(Vector3(0, 1.2, -57.0)))
	_hop(e, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the ravine: cliffs either side, a waterfall, lanterns on the ferry cable, mist below
	for sx: float in [-1.0, 1.0]:
		var wall := Look.box(_sz(Vector3(6.0, 40.0, 70.0)), _rock_mat(), _w(Vector3(sx * 12.0, -14.0, -32.0)))
		add_child(wall)
	deco.rope(_w(Vector3(1.6, 5.2, -34.6)), _w(Vector3(1.6, 5.2, -57.6)), 1.2, 0.05, Color(0.45, 0.36, 0.24))
	for z: float in [-34.6, -57.6]:
		add_child(Look.box(Vector3(0.3, 4.4, 0.3), SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.8), _w(Vector3(1.6, 3.4, z))))
	deco.lantern_string(_w(Vector3(-1.8, 5.0, -2.0)), _w(Vector3(-1.8, 5.0, -30.0)), 7, 1.0)
	SakuraFx.fireflies(self, _w(Vector3(0, 2.0, -30.0)), _sz(Vector3(5.0, 3.0, 26.0)), 60)
	SakuraFx.mist(self, _w(Vector3(0, -10.0, -32.0)), _sz(Vector3(8.0, 2.0, 28.0)), 18)
	SakuraFx.spray(self, _w(Vector3(-8.6, -12.0, -44.0)), _sz(Vector3(1.5, 0.5, 3.0)), 20)
	SakuraFx.waterfall(self, _w(Vector3(-8.7, 6.0, -44.0)), 3.0, 18.0, deg_to_rad(_yaw + 90.0))
	return cp["c"]


## The ferry basket: woven sides on the mover and the hangers up to the cable (they ride with it).
func _basket(m: MovingPlatform) -> void:
	var weave: StandardMaterial3D = SakuraDecor.mat(Color(0.7, 0.55, 0.32), 0.9)
	for sx: float in [-1.0, 1.0]:
		var side := Look.box(Vector3(0.12, 0.5, 2.6), weave, Vector3(sx * 1.3, -0.3, 0))
		m.add_child(side)
		var hanger := Look.cylinder(0.03, 3.6, SakuraDecor.mat(Color(0.45, 0.36, 0.24), 0.9), Vector3(sx * 1.1, 1.8, 0), -1.0, 5)
		hanger.rotation.z = -sx * 0.14
		m.add_child(hanger)
	m.add_child(Look.box(Vector3(2.6, 0.5, 0.12), weave, Vector3(0, -0.3, 1.3)))
	m.add_child(Look.box(Vector3(2.6, 0.5, 0.12), weave, Vector3(0, -0.3, -1.3)))
	deco.paper_lantern(Vector3(0, 3.0, 0), 0.3, LANTERN, m)


## A free-standing moon-gate ring hanging in the air (the shortcut's frame), round a portal ring.
func _moon_ring(floor_c: Vector3, yaw_extra: float) -> void:
	var c: Vector3 = floor_c + Vector3(0, WarpPortal.RING_RADIUS, 0)
	var tm := TorusMesh.new()
	tm.inner_radius = WarpPortal.RING_RADIUS + 0.2
	tm.outer_radius = WarpPortal.RING_RADIUS + 0.5
	tm.rings = 40
	tm.ring_segments = 8
	var ring := Look.mesh_node(tm, SakuraDecor.mat(VERMILION, 0.5), _w(c))
	ring.rotation = Vector3(PI * 0.5, deg_to_rad(_yaw + yaw_extra), 0)
	add_child(ring)
	deco.paper_lantern(_w(c) + Vector3(0, -WarpPortal.RING_RADIUS - 0.8, 0), 0.22, LANTERN)


# ---- stage 12: Cliff Shrine - three paper doors and a shuriken rail along the veranda --------------

func _stage_12() -> Vector3:
	var a: Dictionary = _blk(Vector3(0, 0, -8.5), 3.2, 11.0, "alt")
	var d1: SakuraShoji = _door(Vector3(0, 0, -8.5), 4.0, 0.0)
	var b: Dictionary = _blk(Vector3(0, 0.6, -23.2), 3.2, 12.0, "alt")
	var s1: SakuraShuriken = _star(Vector3(-5.0, 0.6, -20.6), Vector3(10.0, 0, 0), 5.2, 0.2)
	var d2: SakuraShoji = _door(Vector3(0, 0.6, -26.2), 4.0, 0.35)
	var c: Dictionary = _blk(Vector3(0, 1.2, -37.4), 3.2, 10.0, "alt")
	var d3: SakuraShoji = _door(Vector3(0, 1.2, -37.4), 4.0, 0.7, 0.55, 1.6)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -49.4))
	var x1: Vector3 = _w(Vector3(0, 0.6, -20.6))
	# SHORTCUT: the shrine's outer screen out over the drop - run it round the last door and wall-jump
	# straight onto the checkpoint
	kit.wallrun(_w(Vector3(4.4, 1.8, -37.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	deco.slab(_w(Vector3(5.1, 1.8, -37.5)), _sz(Vector3(0.7, 8.0, 16.6)), SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.8))
	r_walk(_w(Vector3(0, 0, -6.6)))
	_wait(func() -> bool: return d1.open_between(0.0, 1.7))
	r_walk(_w(Vector3(0, 0, -13.6)))
	_hop(a, b, Vector3(0, 0, 4.6))
	r_walk(_w(Vector3(0, 0.6, -18.6)))
	_wait(func() -> bool: return s1.lane_clear(x1, 1.8, 0.0, 1.6))
	r_walk(_w(Vector3(0, 0.6, -24.3)))
	_wait(func() -> bool: return d2.open_between(0.0, 1.7))
	if route_variant == 2:
		r_walk(_w(Vector3(1.3, 0.6, -28.0)))
		r_wallrun(_w(Vector3(1.3, 0.6, -28.85)), _w(Vector3(3.9, 2.0, -33.5)), _w(Vector3(3.9, 2.0, -43.0)), _w(Vector3(0.4, 1.2, -48.4)))
	else:
		r_walk(_w(Vector3(0, 0.6, -28.8)))
		_hop(b, c, Vector3(0, 0, 3.6))
		r_walk(_w(Vector3(0, 1.2, -35.5)))
		_wait(func() -> bool: return d3.open_between(0.0, 1.7))
		r_walk(_w(Vector3(0, 1.2, -41.6)))
		_hop(c, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the shrine: the cliff face behind the veranda, a red railing on the drop side, lanterns
	deco.slab(_w(Vector3(-9.0, 8.0, -26.0)), _sz(Vector3(4.0, 30.0, 50.0)), _rock_mat())
	for z: float in [-12.0, -31.0, -44.0]:
		deco.paper_lantern(_w(Vector3(-1.4, 3.6 + (0.6 if z < -20.0 else 0.0) + (0.6 if z < -32.0 else 0.0), z)), 0.3, LANTERN, null, z > -20.0)
	deco.pagoda(_w(Vector3(-15.0, 2.0, -30.0)), 2, 0.8, deg_to_rad(_yaw))
	SakuraFx.fireflies(self, _w(Vector3(0, 2.0, -24.0)), _sz(Vector3(3.0, 1.5, 20.0)), 30)
	SakuraFx.petals(self, _w(Vector3(2.0, 6.0, -24.0)), _sz(Vector3(5.0, 4.0, 20.0)), 60)
	SakuraFx.mist(self, _w(Vector3(6.0, -10.0, -24.0)), _sz(Vector3(8.0, 2.0, 22.0)), 14)
	_rock(Vector3(0, 0.6, -23.2), 1.6, 18.0)
	return cp["c"]


# ---- stage 13: Rope Bridge - the long swaying bridge, its broken spans and the gusts ---------------

var _bridges: Array[SakuraBridge] = []


func _stage_13() -> Vector3:
	var gaps: Array[int] = [5, 12]
	var br: SakuraBridge = _bridge(Vector3(0, 0, -3.0), 54.0, 1.5, 3.5, gaps)
	var g: SakuraGust = _gust(Vector3(0, 0, -30.0), Vector3(18.0, 9.0, 50.0), 6.5, 0.0)
	var e: Dictionary = _blk(Vector3(0, 1.5, -59.5), 5.0, 5.0)
	var cp: Dictionary = _cp(Vector3(0, 1.5, -68.0))
	_bridge_route(br, g)
	_hop(e, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_anchor(Vector3(0, 0, -2.6))
	_anchor(Vector3(0, 1.5, -57.4))
	_peak(Vector3(0, 0, 0))
	_peak(Vector3(0, 1.5, -61.0))
	SakuraFx.mist(self, _w(Vector3(0, -14.0, -30.0)), _sz(Vector3(14.0, 3.0, 26.0)), 18)
	return cp["c"]


func _stage_14() -> Vector3:
	var gaps: Array[int] = [4, 10, 11, 12, 13, 18]
	var br: SakuraBridge = _bridge(Vector3(0, 0, -3.0), 66.0, 2.0, 4.0, gaps)
	var g: SakuraGust = _gust(Vector3(0, 0, -36.0), Vector3(18.0, 10.0, 62.0), 7.0, 0.3)
	# the long break mid-span is crossed on two sinking petals (spans 10-13 are gone)
	var k0: float = 10.0 / 22.0
	var k1: float = 14.0 / 22.0
	var pa: Dictionary = _petal(_bridge_local(br, lerpf(k0, k1, 0.3)) + Vector3(0, 0.4, 0), 1.2)
	var pb: Dictionary = _petal(_bridge_local(br, lerpf(k0, k1, 0.72)) + Vector3(0, 0.6, 0), 1.2, BLOSSOM_PALE)
	var e: Dictionary = _blk(Vector3(0, 2.0, -71.5), 5.0, 5.0)
	var cp: Dictionary = _cp(Vector3(0, 2.0, -80.0))
	_bridge_route(br, g, pa, pb)
	_hop(e, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_anchor(Vector3(0, 0, -2.6))
	_anchor(Vector3(0, 2.0, -69.4))
	_peak(Vector3(0, 2.0, -73.0))
	SakuraFx.mist(self, _w(Vector3(0, -16.0, -36.0)), _sz(Vector3(14.0, 3.0, 32.0)), 22)
	return cp["c"]


func _bridge(start: Vector3, length: float, rise: float, sag: float, gaps: Array[int]) -> SakuraBridge:
	var br := SakuraBridge.new()
	br.length = length
	br.rise = rise
	br.sag = sag
	br.gaps = gaps
	br.rotation.y = deg_to_rad(_yaw)
	br.position = _w(start)
	add_child(br)
	_bridges.append(br)
	return br


## Local (stage frame) point on the bridge deck at fraction k (the bridge starts at local z -3).
func _bridge_local(br: SakuraBridge, k: float) -> Vector3:
	return Vector3(0, br.deck_y(k), -3.0 - br.length * k)


func _gust(c: Vector3, size: Vector3, period: float, phase: float) -> SakuraGust:
	var g := SakuraGust.new()
	g.size = _sz(size)
	g.push = _d(Vector3(30.0, 0, 0))
	g.period = period
	g.phase = phase
	g.position = _w(c)
	add_child(g)
	return g


## Walk the bridge, waiting for a calm at each broken span and jumping it (and, with the petals, the
## long break hop by hop).
func _bridge_route(br: SakuraBridge, g: SakuraGust, pa: Dictionary = {}, pb: Dictionary = {}) -> void:
	var n: int = br.span_count()
	var gaps: Array[int] = br.gaps
	var i: int = 0
	var gust: SakuraGust = g
	while i < n:
		if not gaps.has(i):
			i += 1
			continue
		var j: int = i
		while j + 1 < n and gaps.has(j + 1):
			j += 1
		var k_a: float = float(i) / float(n)
		var k_b: float = float(j + 1) / float(n)
		var stand: Vector3 = _bridge_local(br, k_a - 0.9 / br.length)
		var take: Vector3 = _bridge_local(br, k_a - 0.35 / br.length)
		r_walk(_w(stand))
		if j == i:
			_wait(func() -> bool: return gust.is_calm_for(Game.course_time, 2.3))
			r_jump(_w(take), _w(_bridge_local(br, k_b + 0.9 / br.length)))
		else:
			_wait(func() -> bool: return gust.is_calm_for(Game.course_time, 3.9))
			var a_c: Vector3 = pa["c"]
			var b_c: Vector3 = pb["c"]
			r_jump(_w(take), _w(a_c))
			_hop(pa, pb)
			r_jump(_w(_edge(pb, _bridge_local(br, k_b))), _w(_bridge_local(br, k_b + 1.1 / br.length)))
		i = j + 1
	r_walk(_w(_bridge_local(br, 1.0) + Vector3(0, 0, -1.6)))


## A mountain peak under a bridgehead: a great crag falling away into the mist, cherry trees on its
## shoulders (on rock shelves either side, off the path).
func _peak(c: Vector3) -> void:
	_rock(c, 16.0, 46.0)
	for sx: float in [-1.0, 1.0]:
		var at: Vector3 = c + Vector3(sx * 7.0, -2.6, 1.0)
		kit.plat(_w(at), _sz(Vector3(4.5, 1.2, 4.5)), "main", -1.0, _yaw)
		deco.cherry_tree(_w(at), 1.5, BLOSSOM if sx < 0.0 else BLOSSOM_PALE)
		SakuraFx.shed(self, _w(at + Vector3(0, 4.0, 0)), 2.4, 10.0, 18)
		deco.stone_lantern(_w(at + Vector3(-sx * 1.6, 0, -1.4)), 0.8, true)


## The bridge anchor at a local deck point: two posts and a crossbeam like a gate, on a rocky lip.
func _anchor(at: Vector3) -> void:
	deco.torii(_w(at), 3.4, 3.6, deg_to_rad(_yaw), SakuraDecor.DARK_WOOD.lightened(0.15))
	for sx: float in [-1.0, 1.0]:
		deco.paper_lantern(_w(at + Vector3(sx * 1.9, 3.1, 0)), 0.28, LANTERN, null, sx > 0.0)


# ---- stage 15: Castle Moat - the moat's stones, the curved castle wall, the rampart ----------------

func _stage_15() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var k1: Dictionary = _koi(Vector3(0, 0, -8.9), 0.9, 2.6, 0.0)
	var k2: Dictionary = _koi(Vector3(-1.8, 0.4, -15.6), 0.9, 2.6, 0.4)
	var k3: Dictionary = _koi(Vector3(0.6, 0.8, -22.2), 0.9, 2.6, 0.75)
	var l1: Dictionary = _blk(Vector3(0, 1.2, -28.4), 3.0, 3.0, "alt")
	kit.wallrun(_w(Vector3(2.5, 2.4, -39.4)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(-0.2, 1.2, -52.4), 3.6, 5.0, "alt")
	var m: Dictionary = _ledge(Vector3(0, 4.5, -59.4), Vector3(4.0, 8.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 4.5, -67.6))
	_hop(cp0, k1)
	_hop(k1, k2)
	_hop(k2, k3)
	_hop(k3, l1)
	r_wallrun(_w(Vector3(0.5, 1.2, -29.55)), _w(Vector3(2.0, 2.6, -33.5)), _w(Vector3(2.0, 2.6, -44.4)), _w(Vector3(-0.2, 1.2, -51.7)))
	r_mantle(_w(Vector3(0, 1.2, -54.55)), _w(Vector3(0, 4.5, -59.2)))
	_hop(m, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	l2.clear()
	# the moat, the curved stone base of the castle wall behind the panel, white walls above it
	_water(Vector3(0, -1.6, -32.0), 16.0, 56.0)
	_koi_school(_w(Vector3(-2.0, -1.6, -18.0)), 5.0, 8)
	var wall := Look.box(_sz(Vector3(3.0, 10.0, 24.0)), SakuraDecor.mat(SakuraDecor.STONE.darkened(0.1), 0.95), _w(Vector3(4.4, 1.0, -39.4)))
	add_child(wall)
	deco.slab(_w(Vector3(4.4, 7.4, -39.4)), _sz(Vector3(2.6, 2.8, 24.0)), SakuraDecor.mat(SakuraDecor.PLASTER, 0.9))
	deco.slab(_w(Vector3(4.4, 9.0, -39.4)), _sz(Vector3(3.6, 0.4, 25.0)), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15))
	for z: float in [-10.0, -24.0]:
		deco.cherry_tree(_w(Vector3(-8.0, -1.6, z)), 1.5)
		SakuraFx.shed(self, _w(Vector3(-8.0, 3.5, z)), 2.6, 7.0, 14)
	SakuraFx.petals(self, _w(Vector3(0, 4.0, -30.0)), _sz(Vector3(6.0, 4.0, 24.0)), 70)
	return cp["c"]


# ---- stage 16: Ramparts - the gate rams, a shuriken rail, a bamboo spring up to the gatehouse ------

func _stage_16() -> Vector3:
	_blk(Vector3(0, 0, -12.0), 2.6, 18.0, "alt")
	# the rams sit in bays in the parapet either side of the wall walk
	var r1: Piston = _ram(Vector3(-3.3, 1.3, -8.0), -90.0, 3.0, 6.0, 0.0)
	var r2: Piston = _ram(Vector3(3.3, 1.3, -14.0), 90.0, 3.0, 6.0, 0.4)
	for bay: Vector3 in [Vector3(-5.4, 0, -8.0), Vector3(5.4, 0, -14.0)]:
		kit.plat(_w(bay), _sz(Vector3(5.4, 1.0, 2.6)), "main", -1.0, _yaw)
	var s1: SakuraShuriken = _star(Vector3(-5.0, 0, -18.6), Vector3(10.0, 0, 0), 5.2, 0.1)
	_blk(Vector3(0, 0, -24.0), 4.0, 6.0, "main")
	var ba: SakuraBamboo = _bamboo(Vector3(0, 1.2, -24.6), 3.2, 0.2)
	var t: Dictionary = _blk(Vector3(0, 6.0, -31.5), 7.0, 7.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 6.0, -41.0))
	# SHORTCUT: the bastion's spring off the checkpoint's right corner (a 90% leap to reach it): it
	# throws you clean over the rams and the rail, down onto the spring at the walk's end
	_blk(Vector3(6.0, 0.0, -7.8), 2.4, 2.4, "accent")
	var bs: SakuraBamboo = _bamboo(Vector3(6.0, 1.2, -7.8), 3.2, 0.6, Vector3(-5.2, 18.0, -14.0))
	var x3: Vector3 = _w(Vector3(0, 0, -18.6))
	if route_variant == 2:
		r_walk(_w(Vector3(0.4, 0, -0.4)))
		_wait(func() -> bool: return _resting(bs, 0.0, 2.0))
		r_jump(_w(Vector3(2.65, 0, -2.65)), _w(Vector3(6.0, 1.2, -7.8)))
		_kick(Vector3(6.0, 1.2, -7.8), Vector3(1.2, 0, -22.0))
	else:
		r_walk(_w(Vector3(0, 0, -5.4)))
		_wait(func() -> bool: return _ram_clear(r1, 0.0, 2.0), _w(Vector3(0, 0, -5.4)))
		r_walk(_w(Vector3(0, 0, -11.4)))
		_wait(func() -> bool: return _ram_clear(r2, 0.0, 2.0), _w(Vector3(0, 0, -11.4)))
		r_walk(_w(Vector3(0, 0, -16.6)))
		_wait(func() -> bool: return s1.lane_clear(x3, 1.8, 0.0, 1.6))
		r_walk(_w(Vector3(0, 0, -22.0)))
	_wait(func() -> bool: return _resting(ba, 0.0, 1.8))
	r_jump(_w(Vector3(0.6, 0, -22.2)), _w(Vector3(0, 1.2, -24.6)))
	_kick(Vector3(0, 1.2, -24.6), Vector3(0, 6.0, -30.6))
	_hop(t, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the parapets: white walls with dark tile copings both sides, the gatehouse roof
	for sx: float in [-1.0, 1.0]:
		deco.slab(_w(Vector3(sx * 8.4, 0.6, -14.0)), _sz(Vector3(0.6, 3.6, 22.0)), SakuraDecor.mat(SakuraDecor.PLASTER, 0.9))
		deco.slab(_w(Vector3(sx * 8.4, 2.5, -14.0)), _sz(Vector3(1.2, 0.25, 22.4)), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15))
	deco.roof(_w(Vector3(0, 11.0, -31.5)), 9.0, 10.0, 3.2, deg_to_rad(_yaw))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.4, 5.0, 0.4), SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.7), _w(Vector3(sx * 3.4, 8.5, -31.5 + sz * 3.4))))
	SakuraFx.petals(self, _w(Vector3(0, 5.0, -18.0)), _sz(Vector3(6.0, 4.0, 14.0)), 60)
	_rock(Vector3(0, 0, -14.0), 3.0, 22.0)
	return cp["c"]


# ---- stage 17: The Keep - mantles up the keep, a bell log, the corner wall run ---------------------

func _stage_17() -> Vector3:
	_ledge(Vector3(0, 3.3, -7.2), Vector3(5.0, 7.3, 3.4))
	_ledge(Vector3(0, 6.6, -10.6), Vector3(4.5, 10.6, 3.4), "alt")
	_blk(Vector3(0, 6.6, -17.3), 3.4, 10.0)
	var g: SakuraBell = _bell(Vector3(0, 6.6, -17.5), -1.0, 4.8, 0.2)
	kit.wallrun(_w(Vector3(2.5, 7.8, -31.8)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(-0.2, 6.6, -44.8), 3.6, 5.0, "alt")
	var m3: Dictionary = _ledge(Vector3(0, 9.9, -51.5), Vector3(4.0, 9.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 9.9, -60.2))
	var x1: Vector3 = _w(Vector3(0, 6.6, -17.5))
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -7.4)))
	r_mantle(_w(Vector3(0, 3.3, -8.55)), _w(Vector3(0, 6.6, -10.8)))
	r_walk(_w(Vector3(0, 6.6, -15.1)))
	_wait(func() -> bool: return _log_clear(g, x1, 0.0, 1.9))
	r_walk(_w(Vector3(0, 6.6, -20.6)))
	r_wallrun(_w(Vector3(0.5, 6.6, -21.95)), _w(Vector3(2.0, 8.0, -25.9)), _w(Vector3(2.0, 8.0, -36.8)), _w(Vector3(-0.2, 6.6, -44.1)))
	r_mantle(_w(Vector3(0, 6.6, -46.95)), _w(Vector3(0, 9.9, -51.3)))
	_hop(m3, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	l2.clear()
	# the keep's white walls and black-tiled eaves round the climb
	deco.slab(_w(Vector3(3.6, 4.0, -31.8)), _sz(Vector3(1.4, 18.0, 17.0)), SakuraDecor.mat(SakuraDecor.PLASTER, 0.9))
	deco.roof(_w(Vector3(6.0, 13.0, -31.8)), 6.0, 20.0, 2.0, deg_to_rad(_yaw))
	deco.slab(_w(Vector3(-7.0, 2.0, -12.0)), _sz(Vector3(4.0, 12.0, 16.0)), SakuraDecor.mat(SakuraDecor.PLASTER, 0.9))
	deco.roof(_w(Vector3(-7.0, 8.0, -12.0)), 6.0, 18.0, 1.6, deg_to_rad(_yaw))
	SakuraFx.petals(self, _w(Vector3(0, 10.0, -30.0)), _sz(Vector3(6.0, 6.0, 24.0)), 60)
	SakuraFx.fireflies(self, _w(Vector3(0, 8.0, -30.0)), _sz(Vector3(4.0, 3.0, 20.0)), 30)
	return cp["c"]


# ---- stage 18: Keep Roof - the ridge, the petals, the last spring, the finish -----------------------

var _crown: Node3D


func _stage_18() -> void:
	var ridge: Dictionary = _blk(Vector3(0, 0, -10.0), 1.8, 14.0, "alt")
	var s1: SakuraShuriken = _star(Vector3(-5.0, 0, -11.0), Vector3(10.0, 0, 0), 5.2, 0.5)
	var p1: Dictionary = _petal(Vector3(0, 0.9, -22.4))
	var p2: Dictionary = _petal(Vector3(1.2, 2.0, -28.9), 1.3, BLOSSOM_PALE)
	var f: Dictionary = _blk(Vector3(0, 3.0, -35.7), 4.0, 4.0)
	var ba: SakuraBamboo = _bamboo(Vector3(0, 4.2, -36.1), 3.2, 0.4)
	var summit_body: StaticBody3D = kit.disc(_w(Vector3(0, 9.0, -43.7)), 4.0, 1.2, "main")
	kit.finish(_w(Vector3(0, 9.0, -44.7)), _yaw)
	_finish_pos = _w(Vector3(0, 9.0, -44.7))
	var x1: Vector3 = _w(Vector3(0, 0, -11.0))
	r_walk(_w(Vector3(0, 0, -8.6)))
	_wait(func() -> bool: return s1.lane_clear(x1, 1.8, 0.0, 1.6))
	r_walk(_w(Vector3(0, 0, -16.2)))
	_hop(ridge, p1)
	_hop(p1, p2)
	_hop(p2, f, Vector3(0, 0, 1.2))
	_wait(func() -> bool: return _resting(ba, 0.0, 1.8))
	r_jump(_w(Vector3(0, 3.0, -34.1)), _w(Vector3(0, 4.2, -36.1)))
	_kick(Vector3(0, 4.2, -36.1), Vector3(0, 9.0, -42.7))
	r_walk(_w(Vector3(0, 9.0, -45.1)))
	summit_body.name = "Summit"
	# the roof: tiled slopes falling away from the ridge, the golden roof fish at both ends of the
	# crown, a ring of lanterns, the sky full of stars
	for sx: float in [-1.0, 1.0]:
		var slope := Look.box(Vector3(7.0, 0.5, 18.0), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15), _w(Vector3(sx * 4.2, -2.2, -10.0)))
		slope.rotation = Vector3(0, deg_to_rad(_yaw), 0)
		slope.rotate_object_local(Vector3(0, 0, 1), -sx * 0.55)
		add_child(slope)
	_keep_body()
	_crown = Node3D.new()
	_crown.position = _w(Vector3(0, 9.0, -43.7))
	add_child(_crown)
	for sx: float in [-1.0, 1.0]:
		var fish := Node3D.new()
		fish.position = Vector3(sx * 3.2, 0.0, -2.4)
		_crown.add_child(fish)
		var body := Look.sphere(0.6, SakuraDecor.mat(GOLD, 0.25, 0.9), Vector3(0, 1.2, 0))
		body.scale = Vector3(0.7, 1.6, 0.9)
		fish.add_child(body)
		var tail := Look.sphere(0.45, SakuraDecor.mat(GOLD, 0.25, 0.9), Vector3(0, 2.4, 0.4))
		tail.scale = Vector3(0.4, 0.9, 1.3)
		fish.add_child(tail)
		fish.add_child(Look.box(Vector3(1.2, 0.4, 1.2), SakuraDecor.mat(SakuraDecor.TILE, 0.55, 0.15), Vector3(0, 0.2, 0)))
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		deco.paper_lantern(_w(Vector3(0, 9.0, -43.7)) + Vector3(cos(a) * 4.6, 0.6, sin(a) * 4.6), 0.3, [LANTERN, Color(1.0, 0.4, 0.3)][i % 2], null, i % 4 == 0)
	SakuraFx.petals(self, _w(Vector3(0, 6.0, -24.0)), _sz(Vector3(6.0, 6.0, 16.0)), 70)
	SakuraFx.fireflies(self, _w(Vector3(0, 10.0, -43.7)), Vector3(5.0, 3.0, 5.0), 40)
	_keep_out.append(Vector4(_w(Vector3(0, 0, -20.0)).x, 0.0, _w(Vector3(0, 0, -20.0)).z, 40.0))
	ridge.clear()
	p1.clear()


## The keep under the last stages: white walls rising out of the castle hill, tiers of dark roofs.
func _keep_body() -> void:
	var white: StandardMaterial3D = SakuraDecor.mat(SakuraDecor.PLASTER, 0.9)
	deco.slab(_w(Vector3(0, -12.0, -20.0)), _sz(Vector3(9.0, 18.0, 30.0)), white)
	deco.slab(_w(Vector3(0, -30.0, -22.0)), _sz(Vector3(16.0, 18.0, 36.0)), white)
	deco.roof(_w(Vector3(0, -21.5, -21.0)), 14.0, 36.0, 3.5, deg_to_rad(_yaw))
	deco.slab(_w(Vector3(0, -48.0, -24.0)), _sz(Vector3(30.0, 18.0, 46.0)), SakuraDecor.mat(SakuraDecor.STONE.darkened(0.1), 0.95))
	# the top storey under the crown: white walls and the last roof, the summit sitting on its peak
	deco.slab(_w(Vector3(0, 0.5, -43.7)), _sz(Vector3(7.0, 7.0, 7.0)), white)
	deco.roof(_w(Vector3(0, 4.0, -43.7)), 9.0, 9.0, 3.5, deg_to_rad(_yaw))
	for sx: float in [-1.0, 1.0]:
		deco.slab(_w(Vector3(sx * 3.52, 1.0, -43.7)), _sz(Vector3(0.06, 1.4, 3.0)), SakuraDecor.paper(1.4))
	for i: int in 6:
		var z: float = -8.0 - 4.0 * float(i)
		for sx: float in [-1.0, 1.0]:
			deco.slab(_w(Vector3(sx * 4.52, -6.0, z)), _sz(Vector3(0.06, 1.0, 1.4)), SakuraDecor.paper(1.2))


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
	_env.sky = SakuraSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.82, 0.66, 0.8)
	_env.ambient_light_energy = 0.62
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.9, 0.64, 0.66)
	_env.fog_density = 0.0014
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.12
	_env.fog_sun_scatter = 0.1
	_env.fog_height = VALLEY_Y + 18.0
	_env.fog_height_density = 0.03
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.15
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.15
	_env.adjustment_contrast = 1.1
	# the big low sun off to the west-north-west, warm and raking
	_sun.light_color = Color(1.0, 0.7, 0.5)
	_sun.light_energy = 1.55
	_sun.rotation_degrees = Vector3(-11, 115, 0)
	_sun.shadow_blur = 1.4
	# the fill: a cool violet dusk from the other side
	_fill.light_color = Color(0.62, 0.55, 0.9)
	_fill.light_energy = 0.42
	_fill.rotation_degrees = Vector3(-50, -65, 0)


## Swap the islands' keels for weathered mountain rock.
func _sakura_materials() -> void:
	var keel: StandardMaterial3D = Look.flat(Look.c("side").darkened(0.18), 0.9)
	var rock: StandardMaterial3D = _rock_mat()
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		if m.material_override == keel:
			m.material_override = rock


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
	# keep the scenery off the bridges
	for br: SakuraBridge in _bridges:
		for i: int in 7:
			var q: Vector3 = br.deck_point(float(i) / 6.0)
			_keep_out.append(Vector4(q.x, q.y, q.z, 8.0))
	# crags and blossom islands round the course, rising out of the mist
	var placed: int = 0
	var tries: int = 0
	while placed < 46 and tries < 900:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 90.0, hi.x + 90.0), 0.0, rng.randf_range(lo.z - 90.0, hi.z + 90.0))
		var kind: int = rng.randi() % 4
		var clear: float = [26.0, 22.0, 30.0, 20.0][kind]
		if not _clear_of(p, pts, clear):
			continue
		var y: float = rng.randf_range(lo.y - 10.0, hi.y - 10.0)
		var top := Vector3(p.x, y, p.z)
		match kind:
			0:
				# a crag with a cherry tree on top
				add_child(Look.cylinder(rng.randf_range(4.0, 7.0), y - VALLEY_Y + 6.0, _rock_mat(), Vector3(p.x, (y + VALLEY_Y - 6.0) * 0.5, p.z), rng.randf_range(2.0, 3.5), 7))
				deco.cherry_tree(top, rng.randf_range(1.4, 2.2), [BLOSSOM, BLOSSOM_PALE, SakuraDecor.BLOSSOM_DEEP][rng.randi() % 3])
			1:
				# a crag with a little shrine
				add_child(Look.cylinder(rng.randf_range(4.0, 6.0), y - VALLEY_Y + 6.0, _rock_mat(), Vector3(p.x, (y + VALLEY_Y - 6.0) * 0.5, p.z), rng.randf_range(2.5, 3.5), 7))
				deco.house(top, 4.0, 4.0, 2.6, rng.randf() * TAU)
			2:
				# a pagoda on a crag
				add_child(Look.cylinder(rng.randf_range(6.0, 8.0), y - VALLEY_Y + 6.0, _rock_mat(), Vector3(p.x, (y + VALLEY_Y - 6.0) * 0.5, p.z), rng.randf_range(4.0, 5.0), 7))
				deco.pagoda(top, rng.randi_range(3, 5), rng.randf_range(0.8, 1.1), rng.randf() * TAU)
			3:
				# bamboo on a rocky knoll
				add_child(Look.cylinder(rng.randf_range(3.0, 5.0), y - VALLEY_Y + 6.0, _rock_mat(), Vector3(p.x, (y + VALLEY_Y - 6.0) * 0.5, p.z), rng.randf_range(2.0, 3.0), 7))
				deco.bamboo_clump(top, 7, rng.randf_range(10.0, 16.0), 1.6)
		placed += 1
	# the misty valley floor: a deck of pink cloud far below, wisps over it
	kit.cloud_field(Vector3(mid.x, VALLEY_Y + 4.0, mid.z), Vector3(span.x * 0.5 + 200.0, 3.0, span.z * 0.5 + 200.0), 34)
	kit.cloud_field(Vector3(mid.x, hi.y + 60.0, mid.z), Vector3(span.x * 0.5 + 220.0, 10.0, span.z * 0.5 + 220.0), 14)
	var valley := PlaneMesh.new()
	valley.size = Vector2(3000, 3000)
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(0.62, 0.46, 0.55)
	vm.roughness = 1.0
	var vplane := Look.mesh_node(valley, vm, Vector3(mid.x, VALLEY_Y - 4.0, mid.z))
	vplane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vplane)
	# far ridges: rings of misty peaks, the nearest darkest, a great snow-capped cone far off
	var far: float = maxf(span.x, span.z) * 0.5 + 200.0
	var cols: Array[Color] = [Color(0.36, 0.28, 0.4), Color(0.5, 0.38, 0.52), Color(0.66, 0.5, 0.62)]
	for ring: int in 3:
		var n: int = 14 + ring * 4
		for i: int in n:
			var a: float = TAU * float(i) / float(n) + rng.randf_range(-0.1, 0.1)
			var r: float = far + float(ring) * 160.0 + rng.randf_range(0.0, 80.0)
			var h: float = rng.randf_range(90.0, 170.0) + float(ring) * 40.0
			deco.mountain(Vector3(mid.x + cos(a) * r, VALLEY_Y - 6.0, mid.z + sin(a) * r), h * 0.75, h, cols[ring], ring == 2 and i % 3 == 0)
	deco.mountain(Vector3(mid.x - far * 1.4, VALLEY_Y - 10.0, mid.z - far * 1.2), 360.0, 420.0, Color(0.52, 0.42, 0.6), true)
	# the castle and a pagoda town far off across the valley
	deco.keep(Vector3(mid.x + far * 0.8, VALLEY_Y + 30.0, mid.z - far * 0.6), 2.0, 0.6)
	for i: int in 4:
		deco.pagoda(Vector3(mid.x - far * 0.6 + float(i) * 30.0, VALLEY_Y + 10.0, mid.z + far * 0.7), 5, 2.0, rng.randf() * TAU)
	# ambient life along the whole route: drifting blossom, lantern motes, fireflies and mist
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c2: Vector3 = (here + prev) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 6.0, absf(here.z - prev.z) * 0.5 + 12.0)
		SakuraFx.petals(self, c2 + Vector3(0, 3.0, 0), ext, 60)
		SakuraFx.fireflies(self, c2, ext * 0.8, 24)
		SakuraFx.mist(self, c2 + Vector3(0, -16.0, 0), ext + Vector3(20, 3, 20), 8)


# ---- live effects -----------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null:
		return
	var t: float = Game.course_time
	for tl: Dictionary in _tells:
		var per: float = float(tl["period"])
		var u: float = fposmod(t / per + float(tl["phase"]), 1.0)
		var before: float = (float(tl["at"]) - u) * per
		var warn: bool = before > 0.0 and before < TELL
		(tl["mat"] as StandardMaterial3D).emission_energy_multiplier = (3.2 if fmod(t, 0.18) < 0.09 else 1.2) if warn else 0.0
		var cycle: int = int(floor(t / per + float(tl["phase"])))
		if warn and cycle != int(tl["last"]):
			tl["last"] = cycle
			# SOUND: the machine's tell, about a second before it strikes
			WorldAudio.at(self, str(tl["clip"]), (tl["node"] as Node3D).global_position, 0.7, 35.0)
	for e: Dictionary in _arrivals:
		e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
		if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
			e["cool"] = 3.0
			for p: GPUParticles3D in e["p"]:
				p.restart()
				p.emitting = true


## The summit goes off: fireworks over the keep, a storm of blossom off the crown, the great bell.
func _finish_sequence() -> void:
	var cols: Array[Color] = [Color(2.6, 1.2, 0.5), Color(2.4, 1.0, 1.6), Color(2.6, 2.0, 0.9), Color(1.6, 1.2, 2.6), Color(2.6, 0.8, 0.6)]
	for i: int in 5:
		var fw: GPUParticles3D = SakuraFx.firework(cols[i], 80)
		fw.position = _finish_pos + Vector3(-8.0 + 4.0 * float(i), 12.0 + float(i % 2) * 4.0, -8.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	var c: GPUParticles3D = SakuraFx.petal_pop(2.5, 140, 10.0)
	c.position = _finish_pos + Vector3(0, 0.6, 0)
	add_child(c)
	c.restart()
	c.emitting = true
	# SOUND: fireworks over the keep and the great temple bell tolling from the valley
	WorldAudio.at(self, "sakura_fireworks", _finish_pos + Vector3(0, 10.0, -8.0), 1.0, 120.0)
	WorldAudio.at(self, "sakura_finish_bell", _finish_pos, 1.0, 120.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.6)
	flash.light_energy = 6.0
	flash.omni_range = 24.0
	flash.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.4)
	if _crown != null:
		var tw2: Tween = create_tween()
		tw2.tween_property(_crown, "scale", Vector3.ONE * 1.06, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_crown, "scale", Vector3.ONE, 0.5)
	await get_tree().create_timer(0.9).timeout
