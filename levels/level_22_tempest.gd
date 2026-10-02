extends LevelBase
## 22. TEMPEST TOWER - the outside of a mile-high skyscraper under construction, in a hurricane, in
## broad daylight. Fifteen stages (fourteen checkpoints) climbing round three faces of the main tower -
## past its storm-grey glass curtain wall and up into the bare red-oxide steel of the floors still being
## built - then across the gap on the tower crane's slewing jib to the spire tower, and up its exposed
## spire to the aircraft-warning beacon at the very top. Sheets of rain, squall lines full of roofing
## scraps and torn tarps, lightning in the storm wall, the city far below through the cloud.
## VERY HARD: long leaps onto 1.2 m beam ends (the hardest 94% of reach), hazards threaded on the move,
## two or three demands chained in every stage.
##
##  1 Hoist Deck        three beam ends across a SQUALL LINE (wait for the lull), MANTLE the slab edge
##  2 Curtain Wall      a 91% leap, WALL RUN the glass, the WINDOW-WASHER CRADLE up, hop past the ARCING
##                      CABLE (laser)  [shortcut: a diagonal hop onto the hoist airbag (pad) past the cradle]
##  3 Scaffold Run      BRANCH: four bays of FAILING SCAFFOLDING - keep moving | ride a CRANE LOAD across,
##                      MANTLE the slab from the girder
##  4 Ram Walk          the catwalk past two glazing RAMS (pistons) on the move, a long hop, MANTLE under
##                      the PILE DRIVER (crusher)  [shortcut: WALL RUN the safety screen past both rams]
##  5 Lightning Gallery three beam ends struck by LIGHTNING RODS in a wave - ride the wave - WALL RUN
##  6 Express Hoist     BRANCH: two WINDOW-WASHER CRADLES up the glass, cradle to cradle | a post, WALL RUN
##                      the outrigger screen, the EXPRESS HOIST (portal) up to the slab
##  7 Glazing Line      ride a CRANE LOAD into the squall, change girders in the lull, ride the second
##  8 Core Chimney      a long hop, MANTLE into the lift core, three WALL RUNS up it, the ARCING CABLE
##  9 Storm Floor       BRANCH: failing scaffold, a ROD beam, failing scaffold | MANTLE, the catwalk past
##                      a RAM, a post down
## 10 Broken Beam       the longest leap on the tower (94%) in the lull between SQUALLS, a ROD beam
## 11 Formwork          under two PILE DRIVERS on the move, a long hop, WALL RUN, MANTLE
##                      [shortcut: WALL RUN the formwork's outer shutter past both drivers]
## 12 Crane Mast        a long hop, three MANTLES up the mast, the second under a RAM
##                      [shortcut: the mast's airbag (pad) throws you past the ram onto the top]
## 13 THE JIB           SET PIECE: board the tower crane's jib while it rests over the roof, ride it as it
##                      SLEWS across the gap through two squalls, run out along it and jump off its tip
##                      onto the spire tower
## 14 Spire Base        posts in the lull, a ROD beam, a 91% leap, WALL RUN round the spire
## 15 The Beacon        MANTLE onto the spire, two posts in the lull past the last ROD, MANTLE the last
##                      ledge: the finish under the aircraft-warning beacon at the very top
##
## Tempest mechanics (own scripts): TempestGust (squall lines you see coming 1.2 s ahead), TempestRod
## (lightning rods that electrify a beam span), TempestScaffold (failing scaffolding), TempestLoad
## (crane loads on trolleys you ride), TempestGondola (window-washer cradles), TempestCrane (the slewing
## tower-crane jib). Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main
## line + every shortcut.

const SAFETY := Color(1.0, 0.72, 0.1)
const ALT := Color(0.35, 0.75, 1.0)
const WARN := Color(1.0, 0.25, 0.12)
## The city far below (visual only) and the cloud deck between it and the course.
const CITY_Y: float = -420.0
const CLOUD_Y: float = -55.0
## The two towers' footprints (world) and heights: the main tower the course climbs round, and the
## spire tower across the gap that the crane jib swings you over to.
const TOWER_A_LO := Vector3(-168.0, -440.0, -171.0)
const TOWER_A_HI := Vector3(-9.0, 52.0, -13.0)
const TOWER_A_GLASS: float = 26.0
const TOWER_B_LO := Vector3(-196.0, -440.0, 20.0)
const TOWER_B_HI := Vector3(-166.6, 62.0, 116.0)
const TOWER_B_GLASS: float = 38.0
## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
## Where the tower face is in the current stage frame (local x; 0 = no tower beside this stage).
var _face_x: float = -9.0
var deco: TempestDecor
var storm: TempestStorm
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
var _beacon_lens: StandardMaterial3D
## Bursts that fire when the player arrives at a spot (the hoist's exit): {"at", "p", "cool"}
var _arrivals: Array[Dictionary] = []
## Places set dressing keeps clear of (world x, y, z, flat radius).
var _keep_out: Array[Vector4] = []
var _rods: Array[TempestRod] = []
## Timed machines whose shared tell is short get a longer one of our own: a safety-yellow band that
## glows and flashes for TELL seconds before they strike, with a hiss. {node, period, phase, at, mat, clip, last}
var _tells: Array[Dictionary] = []
const TELL: float = 1.0


func _configure() -> void:
	theme_id = "tempest"
	music_track = "tempest"
	kill_y = -45.0
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


func _sz(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0 else size


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## A steel deck / beam end: top centre `c` (local), sx across, sz along. Narrow pieces get an I-beam
## under them and, when they sit off the tower face, an outrigger strut back to it; wide decks get
## their joists.
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.6) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if minf(sx, sz) <= 3.2:
		deco.ibeam(_w(c), Vector3(sx, thick, sz), _yaw)
		if maxf(sx, sz) <= 3.2 and _face_x != 0.0 and absf(c.x) < 2.6:
			_strut(c + Vector3(signf(_face_x) * sx * 0.5, -thick - 0.3, 0), _face_x)
		elif maxf(sx, sz) <= 3.2:
			# out on the drop side: a shore post falling away into the cloud
			deco.column(_w(c - Vector3(0, thick + 0.55, 0)), _w(c).y - 45.0, 0.3)
	else:
		deco.deck_under(_w(c), Vector3(sx, thick, sz), _yaw)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## An outrigger strut from local point `a` straight across to the tower face at local x = face_x.
func _strut(a: Vector3, face_x: float) -> void:
	var b := Vector3(face_x, a.y - 1.2, a.z)
	add_child(TempestLoad._rod(_w(a), _w(b), 0.13, TempestDecor.mat(TempestDecor.PRIMER, 0.55, 0.45)))
	add_child(Look.box(Vector3(0.5, 0.7, 0.5), TempestDecor.mat(TempestDecor.STEEL, 0.5, 0.5), _w(b)))


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	return {"c": top, "hx": size.x * 0.5, "hz": size.z * 0.5}


func _edge(a: Dictionary, toward: Vector3, inset: float = 0.35) -> Vector3:
	var c: Vector3 = a["c"]
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	var tx: float = INF if absf(d.x) < 0.001 else (float(a["hx"]) - inset) / absf(d.x)
	var tz: float = INF if absf(d.z) < 0.001 else (float(a["hz"]) - inset) / absf(d.z)
	return c + d * minf(tx, tz)


func _hop(a: Dictionary, b: Dictionary, off: Vector3 = Vector3.ZERO, hold: bool = true) -> void:
	var to: Vector3 = (b["c"] as Vector3) + off
	r_jump(_w(_edge(a, to)), _w(to), hold)


func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


# ---- mechanic builders (local frame) ----------------------------------------------------------

func _gust(c: Vector3, size: Vector3, period: float, phase: float, push: float = 32.0) -> TempestGust:
	var g := TempestGust.new()
	g.size = _sz(size)
	# the squalls come in off the open side and drive at the tower (their front is seen over the void)
	var toward: float = signf(_face_x) if _face_x != 0.0 else -1.0
	g.push = _d(Vector3(toward * push, 0, 0))
	g.period = period
	g.phase = phase
	g.position = _w(c)
	add_child(g)
	return g


func _rod(floor_c: Vector3, zone: Vector3, period: float, phase: float, side: float = 1.0) -> TempestRod:
	var r := TempestRod.new()
	r.zone = zone
	r.period = period
	r.phase = phase
	r.rod_offset = Vector3(side * (zone.x * 0.5 + 0.15), 0, 0)
	r.rotation.y = deg_to_rad(_yaw)
	r.position = _w(floor_c)
	add_child(r)
	_rods.append(r)
	return r


func _scaffold(c: Vector3, sx: float, sz: float, delay: float = 1.0) -> Dictionary:
	var s := TempestScaffold.new()
	s.size = Vector3(sx, 0.3, sz)
	s.delay = delay
	s.rotation.y = deg_to_rad(_yaw)
	s.position = _w(c) - Vector3(0, 0.15, 0)
	add_child(s)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5, "node": s}


func _load(c: Vector3, size: Vector3, travel: Vector3, period: float, phase: float, dwell: float = 0.25, cable: float = 10.0) -> TempestLoad:
	var m := TempestLoad.new()
	m.cable_len = cable
	m.size = _sz(size)
	m.points = [Vector3.ZERO, _d(travel)]
	m.period = period
	m.phase = phase
	m.dwell = dwell
	m.position = _w(c) - Vector3(0, size.y * 0.5, 0)
	add_child(m)
	return m


## A window-washer cradle at local `c` (its floor at rest) rising `rise`, hung from a davit arm reaching
## out from the tower face `davit` metres above its floor.
func _gondola(c: Vector3, size: Vector3, rise: float, period: float, phase: float, dwell: float = 0.3, davit: float = 22.0) -> TempestGondola:
	var m := TempestGondola.new()
	m.size = size
	m.points = [Vector3.ZERO, Vector3(0, rise, 0)]
	m.period = period
	m.phase = phase
	m.dwell = dwell
	m.davit_y = _w(c).y + davit
	m.rotation.y = deg_to_rad(_yaw)
	m.position = _w(c) - Vector3(0, size.y * 0.5, 0)
	add_child(m)
	# the davit: an arm out of the facade over the cradle, its cross-head carrying the four cables
	var top: Vector3 = c + Vector3(0, davit, 0)
	var arm_from := Vector3(_face_x, top.y, c.z)
	add_child(TempestLoad._rod(_w(arm_from), _w(top + Vector3(0.3 * signf(-_face_x), 0, 0)), 0.18, TempestDecor.mat(TempestDecor.STEEL, 0.4, 0.6)))
	add_child(TempestLoad._rod(_w(arm_from + Vector3(0, -2.5, 0)), _w(top), 0.1, TempestDecor.mat(TempestDecor.STEEL, 0.4, 0.6)))
	var head := Look.box(_sz(Vector3(size.x + 0.2, 0.3, size.z + 0.2)), TempestDecor.mat(TempestDecor.YELLOW, 0.5, 0.3), _w(top) + Vector3(0, 0.15, 0))
	add_child(head)
	return m


## A fork signpost: two lamp posts in the route's colour and a glowing floor strip.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.2, 1.2]:
		var post: Vector3 = _w(p + Vector3(sx, 0, 0))
		add_child(Look.cylinder(0.07, 2.2, TempestDecor.mat(TempestDecor.STEEL, 0.4, 0.6), post + Vector3(0, 1.1, 0), -1.0, 6))
		add_child(Look.sphere(0.2, TempestDecor.glow(col, 2.6), post + Vector3(0, 2.35, 0)))
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.6)), _sz(Vector3(1.4, 0.05, 0.3)), col)


## The steel rig a tower-side wall-run panel is mounted on (a frame behind it, struts to the facade).
func _panel_rig(center: Vector3, length: float, height: float) -> void:
	var side: float = signf(center.x - _face_x) if _face_x != 0.0 else 1.0
	var back := Vector3(center.x - side * 0.55, center.y, center.z)
	var steel: StandardMaterial3D = TempestDecor.mat(TempestDecor.PRIMER, 0.55, 0.45)
	add_child(Look.box(_sz(Vector3(0.25, height + 0.6, 0.25)), steel, _w(back + Vector3(0, 0, length * 0.5))))
	add_child(Look.box(_sz(Vector3(0.25, height + 0.6, 0.25)), steel, _w(back + Vector3(0, 0, -length * 0.5))))
	add_child(Look.box(_sz(Vector3(0.25, 0.25, length)), steel, _w(back + Vector3(0, height * 0.5 + 0.2, 0))))
	add_child(Look.box(_sz(Vector3(0.25, 0.25, length)), steel, _w(back + Vector3(0, -height * 0.5 - 0.2, 0))))
	if _face_x != 0.0 and absf(back.x - _face_x) > 1.0:
		for dz: float in [-length * 0.35, length * 0.35]:
			for dy: float in [height * 0.5, -height * 0.5]:
				add_child(TempestLoad._rod(_w(back + Vector3(0, dy, dz)), _w(Vector3(_face_x, back.y + dy, back.z + dz)), 0.09, steel))
	TempestFx.drips(self, _w(back + Vector3(0, height * 0.5 + 0.3, -length * 0.45)), _w(back + Vector3(0, height * 0.5 + 0.3, length * 0.45)), 12)


## A wall-run panel on the drop side, held up by two posts dropping away into the cloud.
func _screen_posts(center: Vector3, length: float, height: float) -> void:
	var steel: StandardMaterial3D = TempestDecor.mat(TempestDecor.STEEL, 0.45, 0.55)
	for dz: float in [length * 0.5 - 0.3, -length * 0.5 + 0.3]:
		var p: Vector3 = _w(center + Vector3(signf(center.x) * 0.55, height * 0.5 + 0.3, dz))
		deco.column(p, p.y - 40.0, 0.3, TempestDecor.STEEL)
		add_child(Look.sphere(0.12, TempestDecor.glow(SAFETY, 2.0), p + Vector3(0, 0.25, 0)))


## A hydraulic ram (the piston) punching out of the tower across the walk, with our own longer tell.
func _ram(top: Vector3, yaw_extra: float, stroke: float, period: float, phase: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.4)
	var p: Piston = kit.piston(_w(top), size, _yaw + yaw_extra, stroke, period, phase, 8.0)
	var cap := _tell_material()
	p.add_child(Look.box(Vector3(size.x + 0.06, size.y + 0.06, 0.25), cap, Vector3(0, 0, -size.z * 0.5 - 0.1)))
	_tells.append({"node": p, "period": period, "phase": phase, "at": Piston.PUNCH_START, "mat": cap, "clip": "tempest_ram_hiss", "last": -1})
	return p


## A pile driver (the crusher) with our own longer tell.
func _driver(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	var band := _tell_material()
	cr.add_child(Look.box(Vector3(size.x + 0.08, 0.2, size.z + 0.08), band, Vector3(0, size.y * 0.5 - 0.25, 0)))
	_tells.append({"node": cr, "period": period, "phase": phase, "at": Crusher.SLAM, "mat": band, "clip": "tempest_driver_hiss", "last": -1})
	return cr


func _tell_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.72, 0.1)
	m.metallic = 0.4
	m.roughness = 0.45
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.1)
	m.emission_energy_multiplier = 0.0
	return m


## Checkpoint deck facing the next stage's heading (_next_yaw): hazard bollards, a floodlight, and a
## burst of blue-white sparks and spray when it is banked.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.0)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var h: float = size * 0.5 - 0.35
	for s: float in [-1.0, 1.0]:
		var at: Vector3 = _w(c + Vector3(s * h, 0, h))
		add_child(Look.cylinder(0.14, 1.0, TempestDecor.mat(TempestDecor.YELLOW, 0.5, 0.3), at + Vector3(0, 0.5, 0), -1.0, 10))
		add_child(Look.cylinder(0.15, 0.12, TempestDecor.mat(Color(0.1, 0.1, 0.11), 0.6), at + Vector3(0, 0.7, 0), -1.0, 10))
	deco.floodlight(_w(c + Vector3(-h, 0, -h)), _w(c + Vector3(0, 0, 0)))
	var burst: Array[GPUParticles3D] = TempestFx.cp_burst()
	for p: GPUParticles3D in burst:
		p.position = _w(c) + Vector3(0, 0.3, 0)
		add_child(p)
	_cp_bursts[cp] = burst
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: a site horn and a clank of steel as a stage is banked
			WorldAudio.at(self, "tempest_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


# ---- bot helpers (deterministic, from the course clock) ------------------------------------

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


static func _rod_ok(r: TempestRod, a: float, b: float) -> bool:
	return r.is_safe_for(Game.course_time, a, b)


static func _calm(g: TempestGust, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_active_at(Game.course_time + s):
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


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	TempestDecor.reset()
	add_child(Ambience.make(theme_id))
	deco = TempestDecor.new(self, kit.rng)
	_restyle_environment()
	storm = TempestStorm.new()
	add_child(storm)
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, 0.0, 90.0, 90.0, 90.0, 90.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0]
	# where the tower face is in each stage's frame (local x): the main tower on the left round the
	# first twelve, nothing beside the jib, the spire tower on the right for the last two
	var faces: Array[float] = [-9.0, -9.0, -9.0, -9.0, -8.9, -8.9, -8.9, -8.9, -9.5, -9.5, -9.5, -9.5, 0.0, 3.1, 3.1]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14]
	_frame(Vector3.ZERO, yaws[0])
	var origins: Array[Vector3] = [Vector3.ZERO]
	var starts: Array[int] = [0]
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		_face_x = faces[i]
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
		origins.append(_o)
		starts.append(route.size())
	_face_x = faces[14]
	_stage_15()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])
	_surroundings()
	for r: TempestRod in _rods:
		r.struck.connect(storm.local_flash)


# ---- stage 1: Hoist Deck - beam ends across the squall line, mantle the slab edge -------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	var b1: Dictionary = _blk(Vector3(0, 0, -12.1), 3.0, 1.2)
	var b2: Dictionary = _blk(Vector3(0, 0.5, -17.9), 3.0, 1.2)
	var b3: Dictionary = _blk(Vector3(0, 0.5, -24.1), 3.0, 1.2)
	var d1: Dictionary = _blk(Vector3(0, 0.5, -30.0), 2.6, 2.6)
	var m1: Dictionary = _ledge(Vector3(0, 3.8, -35.4), Vector3(5.0, 7.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.8, -43.2))
	var g: TempestGust = _gust(Vector3(0, 3.0, -18.0), Vector3(16.0, 10.0, 18.0), 7.5, 0.0)
	r_walk(_w(Vector3(0, 0, -4.6)))
	_wait(func() -> bool: return _calm(g, 0.0, 4.5))
	_hop(start, b1)
	_hop(b1, b2)
	_hop(b2, b3)
	_hop(b3, d1)
	r_mantle(_w(Vector3(0, 0.5, -30.95)), _w(Vector3(0, 3.8, -35.0)))
	_hop(m1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the hoist deck: its joists, the construction hoist's mast and car beside it, floodlights, a tarp
	deco.deck_under(_w(Vector3.ZERO), Vector3(14, 2, 14), _yaw)
	deco.crane_mast(_w(Vector3(9.2, 9.0, 2.0)), -440.0, _d(Vector3(-1, 0, 0)), 0.0)
	add_child(Look.box(_sz(Vector3(2.6, 2.6, 3.2)), TempestDecor.mat(TempestDecor.YELLOW, 0.5, 0.35), _w(Vector3(9.2, -6.0, 2.0))))
	add_child(Look.box(_sz(Vector3(2.0, 1.2, 0.05)), TempestDecor.mat(Color(0.3, 0.42, 0.55, 0.7), 0.1, 0.3), _w(Vector3(9.2, -5.6, 3.62))))
	deco.floodlight(_w(Vector3(-6.4, 0, 6.4)), _w(Vector3(0, 0, -12.0)))
	deco.floodlight(_w(Vector3(6.4, 0, 6.4)), _w(Vector3(0, 0, -12.0)))
	deco.tarp(_w(Vector3(10.4, 4.0, 2.0)), 3.6, 1.6, _yaw + 20.0, Color(0.85, 0.42, 0.12))
	for b: Dictionary in [b1, b2, b3]:
		TempestFx.spray(self, _w((b["c"] as Vector3) + Vector3(1.4, -0.2, 0)), _sz(Vector3(0.2, 0.2, 0.5)), 10)
	TempestFx.weld(self, _w(Vector3(-8.6, -1.4, -24.1)))
	return cp["c"]


# ---- stage 2: Curtain Wall - a long leap, the glass wall run, the window-washer cradle, the arc -----

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var l1: Dictionary = _blk(Vector3(-0.5, 0, -8.8), 2.0, 1.4)
	kit.wallrun(_w(Vector3(-2.5, 1.2, -19.0)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(0, 0, -31.8), 2.4, 3.0)
	var gd: TempestGondola = _gondola(Vector3(0, 0, -36.5), Vector3(2.2, 0.4, 2.4), 7.0, 12.0, 0.0)
	var b1: Dictionary = _blk(Vector3(0, 7.0, -41.0), 3.0, 1.2)
	var b2: Dictionary = _blk(Vector3(0, 7.0, -46.6), 3.0, 1.2)
	var arc: LaserGate = kit.laser(_w(Vector3(0, 8.4, -43.8)), Vector3(3.6, 2.8, 0.2), 4.0, 0.3, 0.0, _yaw)
	arc.warn = 0.85
	var cp: Dictionary = _cp(Vector3(0, 7.0, -52.2))
	# SHORTCUT: the hoist airbag - a long diagonal hop from the landing onto the bounce pad on the
	# outrigger post, and it throws you straight up onto the beam past the cradle
	var sp: Dictionary = _blk(Vector3(3.2, 0, -39.0), 2.0, 2.0, "accent")
	var pad: BouncePad = kit.pad(_w(Vector3(3.2, 0, -39.0)), 21.0, 0.0, _yaw, 0.85)
	_hop(cp0, l1)
	r_wallrun(_w(Vector3(-0.5, 0, -9.15)), _w(Vector3(-2.0, 1.4, -13.1)), _w(Vector3(-2.0, 1.4, -24.0)), _w(Vector3(0, 0, -31.3)))
	if route_variant == 2:
		_hop(l2, sp)
		r_pad(pad.global_position, _w(Vector3(0, 7.0, -41.0)))
	else:
		var low: Vector3 = gd.global_position
		var high: Vector3 = low + Vector3(0, 7.0, 0)
		var gond: TempestGondola = gd
		r_walk(_w(Vector3(0, 0, -32.6)))
		_wait(func() -> bool: return _mover_at(gond, low, 0.05, 0.0, 2.6))
		_hop(l2, _area(Vector3(0, 0, -36.5), 1.1, 1.2))
		route.append({"kind": "ride_jump", "node": gd, "point": high, "radius": 0.05, "to": _w(Vector3(0, 7.0, -41.0)), "hold": true, "stand": Vector3(0, 0.2, -0.8)})
	_wait(func() -> bool: return _dark(arc, 0.0, 2.3))
	_hop(b1, b2)
	_hop(b2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the glazing rig the wall-run panel hangs on, the arcing cable's junction boxes, the airbag post
	_panel_rig(Vector3(-2.5, 1.2, -19.0), 16.0, 6.5)
	deco.arc_posts(_w(Vector3(0, 7.0, -43.8)), 3.6, 2.8, _yaw)
	TempestFx.weld(self, _w(Vector3(-1.8, 9.2, -43.8)), 10)
	TempestFx.spray(self, _w(Vector3(1.4, 6.8, -46.6)), _sz(Vector3(0.2, 0.2, 0.5)), 10)
	return cp["c"]


# ---- stage 3: Scaffold Run (BRANCH) - the failing scaffold bays | ride the crane load, mantle out ----

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (tower side): five bays of failing scaffolding - keep moving
	var s1: Dictionary = _scaffold(Vector3(-3.5, 0, -15.6), 2.0, 1.2)
	var s2: Dictionary = _scaffold(Vector3(-3.5, 0.5, -21.4), 2.0, 1.2)
	var s3: Dictionary = _scaffold(Vector3(-3.5, 0.5, -27.6), 2.0, 1.2)
	var s4: Dictionary = _scaffold(Vector3(-3.5, 1.0, -33.4), 2.0, 1.2)
	# RIGHT (the drop side): ride the girder across on the crane, mantle the slab edge
	var ld: TempestLoad = _load(Vector3(3.5, -1.5, -12.6), Vector3(1.4, 0.4, 4.0), Vector3(0, 0, -21.5), 14.0, 0.0)
	var merge: Dictionary = _ledge(Vector3(0, 1.0, -40.0), Vector3(12.0, 6.0, 4.0))
	var cp: Dictionary = _cp(Vector3(0, 1.0, -48.5))
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -9.0)))
		var prev: Dictionary = _area(Vector3(-3.5, 0, -8.0), 1.5, 2.0)
		for s: Dictionary in [s1, s2, s3, s4]:
			_hop(prev, s)
			prev = s
		_hop(prev, merge, Vector3(-3.0, 0, 0.8))
	else:
		var near: Vector3 = ld.global_position
		var far: Vector3 = near + _d(Vector3(0, 0, -21.5))
		var load: TempestLoad = ld
		r_walk(_w(Vector3(3.5, 0, -9.3)))
		_wait(func() -> bool: return _mover_at(load, near, 0.05, 0.0, 2.6))
		r_jump(_w(Vector3(3.5, 0, -9.65)), _w(Vector3(3.5, -1.5, -12.6)))
		_wait(func() -> bool: return _mover_at(load, far, 0.05, 0.0, 2.4))
		r_mantle(_w(Vector3(3.5, -1.5, -35.65)), _w(Vector3(3.5, 1.0, -38.6)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the forks' signs, the crane's jib the girder's trolley runs under, and its mast past the slab
	_sign(Vector3(-3.5, 0, -6.6), SAFETY)
	_sign(Vector3(3.5, 0, -6.6), ALT)
	var jy: float = -1.5 + ld.cable_len + 0.9
	add_child(Look.box(_sz(Vector3(1.4, 1.2, 36.0)), TempestDecor.mat(TempestDecor.YELLOW, 0.5, 0.35), _w(Vector3(3.5, jy, -25.0))))
	for z: float in [-10.0, -18.0, -26.0, -34.0]:
		add_child(TempestLoad._rod(_w(Vector3(3.5, jy - 0.6, z)), _w(Vector3(3.5, jy + 0.6, z - 4.0)), 0.07, TempestDecor.mat(TempestDecor.YELLOW, 0.5, 0.35)))
	deco.crane_mast(_w(Vector3(3.5, jy - 0.6, -44.0)), -440.0, _d(Vector3(-1, 0, 0)), 0.0)
	TempestFx.drips(self, _w(Vector3(3.5, jy - 0.6, -9.0)), _w(Vector3(3.5, jy - 0.6, -40.0)), 16)
	return cp["c"]


# ---- stage 4: Ram Walk - the catwalk past the glazing rams, a long hop, mantle under the pile driver -

func _stage_4() -> Vector3:
	var walk: Dictionary = _blk(Vector3(0, 0, -10.5), 1.4, 15.0)
	var r1: Piston = _ram(Vector3(-3.0, 1.3, -7.5), -90.0, 3.0, 8.0, 0.0)
	var r2: Piston = _ram(Vector3(-3.0, 1.3, -13.5), -90.0, 3.0, 8.0, 0.9)
	var p1: Dictionary = _blk(Vector3(0, 0, -23.5), 1.2, 1.2)
	var m: Dictionary = _ledge(Vector3(0, 3.3, -27.8), Vector3(4.0, 7.3, 3.4))
	var pd: Crusher = _driver(Vector3(0, 3.3, -27.4), Vector3(2.6, 1.4, 2.4), 3.4, 6.0, 0.0)
	var cp: Dictionary = _cp(Vector3(0, 3.3, -36.0))
	# SHORTCUT: the safety screen on the drop side - wall run it clear of both rams and wall-jump
	# straight onto the post
	kit.wallrun(_w(Vector3(2.5, 1.2, -12.5)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	if route_variant == 2:
		r_wallrun(_w(Vector3(0.5, 0, -2.65)), _w(Vector3(2.0, 1.4, -6.6)), _w(Vector3(2.0, 1.4, -16.2)), _w(Vector3(0, 0, -23.5)))
	else:
		r_walk(_w(Vector3(0, 0, -4.4)))
		_wait(func() -> bool: return _ram_clear(r1, 0.0, 2.6) and _ram_clear(r2, 0.6, 3.4), _w(Vector3(0, 0, -4.4)))
		r_walk(_w(Vector3(0, 0, -16.0)))
		_hop(walk, p1)
	_wait(func() -> bool: return _press_ok(pd, 0.0, 3.4))
	r_mantle(_w(Vector3(0, 0, -23.75)), _w(Vector3(0, 3.3, -27.6)))
	r_walk(_w(Vector3(0, 3.3, -29.1)))
	_hop(m, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the safety screen's posts, the catwalk's hangers up to the slab above, tarps on the rams' bays
	_screen_posts(Vector3(2.5, 1.2, -12.5), 16.0, 6.5)
	for z: float in [-4.5, -10.5, -16.5]:
		add_child(TempestLoad._rod(_w(Vector3(-0.7, -0.1, z)), _w(Vector3(-9.0, 7.0, z)), 0.06, TempestDecor.mat(TempestDecor.STEEL, 0.4, 0.6)))
	deco.tarp(_w(Vector3(-8.8, 6.5, -10.5)), 3.0, 1.8, _yaw + 70.0, Color(0.18, 0.36, 0.62))
	TempestFx.weld(self, _w(Vector3(-1.2, 5.2, -27.4)), 10)
	return cp["c"]


# ---- stage 5: Lightning Gallery - three rod beams struck in a wave, the glass wall run -----------------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var zone := Vector3(2.4, 3.2, 1.3)
	var b1: Dictionary = _blk(Vector3(0, 0, -8.65), 2.4, 1.3)
	var b2: Dictionary = _blk(Vector3(0, 0.5, -14.55), 2.4, 1.3)
	var b3: Dictionary = _blk(Vector3(0, 0.5, -20.85), 2.4, 1.3)
	var rods: Array[TempestRod] = []
	var cs: Array[Vector3] = [Vector3(0, 0, -8.65), Vector3(0, 0.5, -14.55), Vector3(0, 0.5, -20.85)]
	for i: int in 3:
		rods.append(_rod(cs[i], zone, 4.5, fposmod(-0.75 * float(i) / 4.5, 1.0)))
	kit.wallrun(_w(Vector3(-2.5, 1.7, -31.0)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var l1: Dictionary = _blk(Vector3(0, 0.5, -44.0), 2.4, 3.0)
	var cp: Dictionary = _cp(Vector3(0, 0.5, -51.5))
	r_walk(_w(Vector3(0, 0, -1.0)))
	_wait(func() -> bool:
		for i: int in 3:
			if not _rod_ok(rods[i], 0.75 * float(i + 1) - 0.6, 0.75 * float(i + 1) + 2.1):
				return false
		return true)
	_hop(cp0, b1)
	_hop(b1, b2)
	_hop(b2, b3)
	r_wallrun(_w(Vector3(-0.5, 0.5, -21.15)), _w(Vector3(-2.0, 1.9, -25.1)), _w(Vector3(-2.0, 1.9, -36.0)), _w(Vector3(0, 0.5, -43.3)))
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_panel_rig(Vector3(-2.5, 1.7, -31.0), 16.0, 6.5)
	deco.floodlight(_w(Vector3(2.6, 0, 2.6)), _w(Vector3(0, 0.5, -14.0)))
	deco.tarp(_w(Vector3(-8.7, 8.5, -14.0)), 4.0, 2.2, _yaw + 60.0, Color(0.6, 0.62, 0.6))
	return cp["c"]


# ---- stage 6: Express Hoist (BRANCH) - two window-washer cradles up the glass | a post, the outrigger
# wall run and the express hoist (PORTAL) up to the slab ------------------------------------------

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (the glass): two cradles, the second waiting where the first stops
	var g1: TempestGondola = _gondola(Vector3(-3.5, 0, -11.4), Vector3(2.2, 0.4, 2.4), 5.0, 12.0, 0.0)
	var g2: TempestGondola = _gondola(Vector3(-3.5, 5.0, -15.8), Vector3(2.2, 0.4, 2.4), 5.0, 12.0, 0.5)
	# RIGHT (the drop): a post, the outrigger wall run, the hoist cage
	var p1: Dictionary = _blk(Vector3(3.5, 0, -15.6), 1.2, 1.2)
	kit.wallrun(_w(Vector3(6.0, 1.2, -25.7)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	_blk(Vector3(3.3, 0, -38.5), 2.4, 3.0)
	var hoist: WarpPortal = kit.portal(_w(Vector3(3.3, 0, -39.6)), _yaw, _w(Vector3(0, 10.0, -20.2)), _yaw, 6.0)
	var merge: Dictionary = _blk(Vector3(0, 10.0, -21.0), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 10.0, -29.5))
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		var a: TempestGondola = g1
		var b: TempestGondola = g2
		var a_low: Vector3 = g1.global_position
		var b_low: Vector3 = g2.global_position - g2.offset_at(Game.course_time)
		r_walk(_w(Vector3(-3.5, 0, -9.3)))
		_wait(func() -> bool: return _mover_at(a, a_low, 0.05, 0.0, 2.6))
		_hop(_area(Vector3(-3.5, 0, -8.0), 1.5, 2.0), _area(Vector3(-3.5, 0, -11.4), 1.1, 1.2))
		route.append({"kind": "ride_jump", "node": a, "point": a_low + Vector3(0, 5.0, 0), "radius": 0.05, "to": _w(Vector3(-3.5, 5.0, -15.8)), "hold": true, "stand": Vector3(0, 0.2, -0.8)})
		route.append({"kind": "ride_jump", "node": b, "point": b_low + Vector3(0, 5.0, 0), "radius": 0.05, "to": _w(Vector3(-3.0, 10.0, -19.8)), "hold": true, "stand": Vector3(0, 0.2, -0.8)})
	else:
		r_walk(_w(Vector3(3.5, 0, -9.3)))
		_hop(_area(Vector3(3.5, 0, -8.0), 1.5, 2.0), p1)
		r_wallrun(_w(Vector3(4.0, 0, -15.85)), _w(Vector3(5.5, 1.4, -19.8)), _w(Vector3(5.5, 1.4, -30.7)), _w(Vector3(3.3, 0, -38.0)))
		r_portal(_w(Vector3(3.3, 0, -39.8)), hoist.exit_point())
		r_walk(_w(Vector3(0, 10.0, -21.4)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, -6.6), SAFETY)
	_sign(Vector3(3.5, 0, -6.6), ALT)
	_screen_posts(Vector3(6.0, 1.2, -25.7), 16.0, 6.5)
	deco.hoist_cage(_w(Vector3(3.3, 0, -39.6)), _yaw)
	deco.hoist_cage(_w(Vector3(0, 10.0, -20.2)), _yaw)
	_arrival(Vector3(0, 10.0, -20.6))
	# the hoist's mast from the cage up to the slab it lets you out on
	deco.column(_w(Vector3(3.3, 10.0, -41.2)), -40.0, 0.5, TempestDecor.YELLOW)
	return cp["c"]


# ---- stage 7: Glazing Line - ride one crane load into the squall, change girders in the lull ---------

func _stage_7() -> Vector3:
	var l1: TempestLoad = _load(Vector3(0, 0, -6.0), Vector3(1.4, 0.4, 4.0), Vector3(0, 0, -12.0), 14.0, 0.0)
	var l2: TempestLoad = _load(Vector3(0, 1.0, -24.5), Vector3(1.4, 0.4, 4.0), Vector3(0, 0, -12.0), 14.0, 0.5, 0.25, 9.0)
	var b1: Dictionary = _blk(Vector3(0, 1.0, -41.3), 3.0, 1.2)
	var cp: Dictionary = _cp(Vector3(0, 1.0, -47.0))
	var g: TempestGust = _gust(Vector3(0, 4.0, -22.0), Vector3(16.0, 10.0, 30.0), 7.0, 0.58)
	var a_near: Vector3 = l1.global_position
	var a_far: Vector3 = a_near + _d(Vector3(0, 0, -12.0))
	var b_near: Vector3 = l2.global_position - l2.offset_at(Game.course_time)
	var b_far: Vector3 = b_near + _d(Vector3(0, 0, -12.0))
	var la: TempestLoad = l1
	var lb: TempestLoad = l2
	r_walk(_w(Vector3(0, 0, -2.4)))
	_wait(func() -> bool: return _mover_at(la, a_near, 0.05, 0.0, 2.6))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -6.0)))
	_wait(func() -> bool: return _mover_at(la, a_far, 0.05, 0.0, 2.4) and _mover_at(lb, b_near, 0.05, 0.0, 2.4) and _calm(g, 0.0, 2.4))
	route.append({"kind": "b_jump", "from": _w(Vector3(0, 0, -19.6)), "to": _w(Vector3(0, 1.0, -24.5)), "hold": true})
	_wait(func() -> bool: return _mover_at(lb, b_far, 0.05, 0.0, 2.4) and _calm(g, 0.0, 2.4))
	route.append({"kind": "b_jump", "from": _w(Vector3(0, 1.0, -38.1)), "to": _w(Vector3(0, 1.0, -41.3)), "hold": true})
	_hop(b1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the glazing crane's jib both trolleys run under, its mast behind the start
	var yel: StandardMaterial3D = TempestDecor.mat(TempestDecor.YELLOW, 0.5, 0.35)
	add_child(Look.box(_sz(Vector3(1.4, 1.2, 46.0)), yel, _w(Vector3(0, 10.9, -17.0))))
	for z: float in [-2.0, -10.0, -18.0, -26.0, -34.0]:
		add_child(TempestLoad._rod(_w(Vector3(0, 10.3, z)), _w(Vector3(0, 11.5, z - 4.0)), 0.07, yel))
	deco.crane_mast(_w(Vector3(3.4, 10.3, -20.0)), -440.0, _d(Vector3(-1, 0, 0)), 0.0)
	add_child(Look.box(_sz(Vector3(3.4, 0.8, 2.0)), yel, _w(Vector3(1.7, 10.9, -20.0))))
	TempestFx.drips(self, _w(Vector3(0, 10.2, -2.0)), _w(Vector3(0, 10.2, -38.0)), 18)
	deco.tarp(_w(Vector3(-8.6, 14.0, -30.0)), 4.5, 2.4, _yaw + 50.0, Color(0.85, 0.42, 0.12))
	return cp["c"]


# ---- stage 8: Core Chimney - a long hop, MANTLE into the lift core, three WALL RUNS up it, the arc ---

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var p1: Dictionary = _blk(Vector3(0, 0, -8.6), 1.2, 1.2)
	_ledge(Vector3(0, 3.3, -13.3), Vector3(3.4, 7.3, 3.4))
	_chimney_panel(2.3, 4.5, -17.8, -24.3)
	_chimney_panel(-2.3, 9.3, -22.8, -30.8)
	_chimney_panel(2.3, 12.3, -28.8, -36.8)
	var top: Dictionary = _ledge(Vector3(-0.75, 15.2, -40.3), Vector3(4.5, 14.0, 4.0))
	var arc: LaserGate = kit.laser(_w(Vector3(0, 16.6, -44.4)), Vector3(3.6, 2.8, 0.2), 4.0, 0.3, 0.5, _yaw)
	arc.warn = 0.85
	var cp: Dictionary = _cp(Vector3(0, 15.2, -49.5))
	_hop(cp0, p1)
	r_mantle(_w(Vector3(0, 0, -8.85)), _w(Vector3(0, 3.3, -12.0)))
	r_walk(_w(Vector3(0, 3.3, -12.2)))
	r_wallrun(_w(Vector3(0.5, 3.3, -14.15)), _w(Vector3(1.7, 4.7, -18.9)), _w(Vector3(1.7, 4.7, -21.8)), _w(Vector3(-1.7, 8.8, -25.7)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 8.8, -25.7)), _w(Vector3(-1.7, 8.8, -28.7)), _w(Vector3(1.7, 11.8, -32.3)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 11.8, -32.3)), _w(Vector3(1.7, 11.8, -33.7)), _w(Vector3(-0.75, 15.2, -38.9)), true, true)
	r_walk(_w(Vector3(0, 15.2, -41.6)))
	_wait(func() -> bool: return _dark(arc, 0.0, 2.3))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	deco.arc_posts(_w(Vector3(0, 15.2, -44.4)), 3.6, 2.8, _yaw)
	TempestFx.weld(self, _w(Vector3(1.8, 17.4, -44.4)), 10)
	TempestFx.drips(self, _w(Vector3(-2.6, 16.0, -18.0)), _w(Vector3(-2.6, 16.0, -36.0)), 14)
	return cp["c"]


## A chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by the lift core's concrete wall.
func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	add_child(Look.box(_sz(Vector3(0.6, height + 2.0, absf(z0 - z1) + 1.0)), TempestDecor.mat(TempestDecor.CONCRETE.darkened(0.12), 0.9), _w(Vector3(x + signf(x) * 0.6, y, (z0 + z1) * 0.5))))


# ---- stage 9: Storm Floor (BRANCH) - scaffold, a rod beam, scaffold | MANTLE, the ram walk, a post ---

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0)
	# LEFT (the glass): failing scaffold, a struck beam, failing scaffold - no stopping
	var s1: Dictionary = _scaffold(Vector3(-3.5, 0, -15.6), 2.0, 1.2)
	var rb: Dictionary = _blk(Vector3(-3.5, 0.5, -21.4), 2.4, 1.2)
	var rod: TempestRod = _rod(Vector3(-3.5, 0.5, -21.4), Vector3(2.4, 3.2, 1.2), 4.8, 0.0, -1.0)
	var s2: Dictionary = _scaffold(Vector3(-3.5, 0.5, -27.6), 2.0, 1.2)
	# RIGHT (the drop): MANTLE the slab, the catwalk past the glazing ram, a post down to the merge
	_ledge(Vector3(3.5, 3.3, -13.3), Vector3(3.4, 7.3, 3.4))
	var walk: Dictionary = _blk(Vector3(3.5, 3.3, -20.0), 1.4, 10.0)
	var ram: Piston = _ram(Vector3(6.7, 4.6, -20.0), 90.0, 3.6, 8.0, 0.3)
	var p: Dictionary = _blk(Vector3(3.5, 1.5, -28.6), 1.2, 1.2)
	var merge: Dictionary = _blk(Vector3(0, 0.5, -34.0), 12.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 0.5, -42.5))
	_hop(cp0, fork, Vector3(0, 0, 0.6))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -9.3)))
		_wait(func() -> bool: return _rod_ok(rod, 0.9, 3.6))
		var prev: Dictionary = _area(Vector3(-3.5, 0, -8.0), 1.5, 2.0)
		for s: Dictionary in [s1, rb, s2]:
			_hop(prev, s)
			prev = s
		_hop(prev, merge, Vector3(-3.0, 0, 0.8))
	else:
		r_walk(_w(Vector3(3.5, 0, -9.3)))
		r_mantle(_w(Vector3(3.5, 0, -9.65)), _w(Vector3(3.5, 3.3, -12.0)))
		r_walk(_w(Vector3(3.5, 3.3, -14.0)))
		_wait(func() -> bool: return _ram_clear(ram, 0.0, 2.6), _w(Vector3(3.5, 3.3, -14.0)))
		r_walk(_w(Vector3(3.5, 3.3, -24.4)))
		_hop(walk, p)
		_hop(p, merge, Vector3(3.0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, -6.6), SAFETY)
	_sign(Vector3(3.5, 0, -6.6), ALT)
	for z: float in [-16.0, -24.0]:
		deco.column(_w(Vector3(3.5, 2.7, z)), -40.0, 0.35)
	deco.tarp(_w(Vector3(-9.2, 7.0, -24.0)), 4.0, 2.0, _yaw + 70.0, Color(0.2, 0.45, 0.3))
	deco.floodlight(_w(Vector3(5.4, 0, -6.6)), _w(Vector3(3.5, 3.3, -20.0)))
	return cp["c"]


# ---- stage 10: Broken Beam - the longest leap on the tower, in the lull between squalls; a rod beam ---

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var b1: Dictionary = _blk(Vector3(0, 0, -9.0), 2.4, 1.2)
	var b2: Dictionary = _blk(Vector3(0, 0.5, -14.8), 2.4, 1.2)
	var rod: TempestRod = _rod(Vector3(0, 0.5, -14.8), Vector3(2.4, 3.2, 1.2), 3.75, 0.2133)
	var b3: Dictionary = _blk(Vector3(0, 0.5, -21.0), 2.4, 1.2)
	var l1: Dictionary = _blk(Vector3(0, 0.5, -27.0), 2.4, 3.0)
	var cp: Dictionary = _cp(Vector3(0, 0.5, -34.0))
	var g: TempestGust = _gust(Vector3(0, 3.0, -15.0), Vector3(16.0, 10.0, 16.0), 7.5, 0.0)
	r_walk(_w(Vector3(0, 0, -0.6)))
	_wait(func() -> bool: return _calm(g, 0.0, 4.2) and _rod_ok(rod, 0.9, 3.6))
	_hop(cp0, b1)
	_hop(b1, b2)
	_hop(b2, b3)
	_hop(b3, l1)
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the broken beam: the rest of the girder that should bridge the gap, snapped and hanging off the
	# tower by one end, swinging a little in the storm (looks only, well below the leap)
	var snapped := Node3D.new()
	snapped.position = _w(Vector3(-8.6, -3.0, -6.0))
	snapped.rotation = Vector3(0, deg_to_rad(_yaw), 0)
	add_child(snapped)
	var g2 := Look.box(Vector3(9.0, 0.5, 0.9), TempestDecor.mat(TempestDecor.PRIMER, 0.55, 0.45), Vector3(4.2, -2.6, 0))
	g2.rotation.z = -0.62
	snapped.add_child(g2)
	TempestFx.spray(self, _w(Vector3(-1.5, -6.2, -6.0)), _sz(Vector3(0.3, 0.2, 0.4)), 10)
	TempestFx.weld(self, _w(Vector3(-8.7, -3.0, -6.0)), 12)
	deco.floodlight(_w(Vector3(-2.6, 0, 2.6)), _w(Vector3(0, 0, -9.0)))
	return cp["c"]


# ---- stage 11: Formwork - under two pile drivers on the move, a long hop, WALL RUN, MANTLE ---------

func _stage_11() -> Vector3:
	var walk: Dictionary = _blk(Vector3(0, 0, -10.5), 2.0, 15.0)
	var d1: Crusher = _driver(Vector3(0, 0, -7.5), Vector3(2.6, 1.4, 2.4), 3.4, 6.0, 0.0)
	var d2: Crusher = _driver(Vector3(0, 0, -13.5), Vector3(2.6, 1.4, 2.4), 3.4, 6.0, 0.867)
	var p1: Dictionary = _blk(Vector3(0, 0, -23.5), 1.4, 1.2)
	kit.wallrun(_w(Vector3(-2.5, 1.2, -33.6)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var l1: Dictionary = _blk(Vector3(0, 0, -46.6), 2.4, 3.0)
	var m: Dictionary = _ledge(Vector3(0, 3.3, -52.2), Vector3(4.0, 7.3, 3.4))
	var cp: Dictionary = _cp(Vector3(0, 3.3, -60.0))
	# SHORTCUT: the formwork's outer shutter - wall run it past both drivers onto the post
	kit.wallrun(_w(Vector3(3.0, 1.2, -12.5)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	if route_variant == 2:
		r_wallrun(_w(Vector3(0.6, 0, -2.65)), _w(Vector3(2.5, 1.4, -6.6)), _w(Vector3(2.5, 1.4, -16.2)), _w(Vector3(0, 0, -23.5)))
	else:
		r_walk(_w(Vector3(0, 0, -3.6)))
		_wait(func() -> bool: return _press_ok(d1, 0.0, 2.4) and _press_ok(d2, 0.6, 3.2), _w(Vector3(0, 0, -3.6)))
		r_walk(_w(Vector3(0, 0, -16.0)))
		_hop(walk, p1)
	r_wallrun(_w(Vector3(-0.5, 0, -23.75)), _w(Vector3(-2.0, 1.4, -27.7)), _w(Vector3(-2.0, 1.4, -38.6)), _w(Vector3(0, 0, -45.9)))
	r_mantle(_w(Vector3(0, 0, -47.75)), _w(Vector3(0, 3.3, -50.9)))
	_hop(m, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	_panel_rig(Vector3(-2.5, 1.2, -33.6), 16.0, 6.5)
	_screen_posts(Vector3(3.0, 1.2, -12.5), 16.0, 6.5)
	for z: float in [-4.0, -17.0]:
		add_child(TempestLoad._rod(_w(Vector3(-1.0, -0.1, z)), _w(Vector3(-9.5, 7.0, z)), 0.06, TempestDecor.mat(TempestDecor.STEEL, 0.4, 0.6)))
	deco.tarp(_w(Vector3(-9.3, 9.5, -46.0)), 4.5, 2.4, _yaw + 60.0, Color(0.18, 0.36, 0.62))
	TempestFx.weld(self, _w(Vector3(1.5, 5.6, -13.5)), 10)
	return cp["c"]


# ---- stage 12: Crane Mast - a long hop, three MANTLES up the mast, the second under a glazing ram ----

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var p1: Dictionary = _blk(Vector3(0, 0, -8.6), 1.2, 1.2)
	_ledge(Vector3(0.8, 3.3, -13.3), Vector3(5.0, 7.3, 3.4))
	_ledge(Vector3(0, 6.6, -16.7), Vector3(3.4, 10.6, 3.4))
	var top: Dictionary = _ledge(Vector3(0, 9.9, -20.1), Vector3(3.4, 13.9, 3.4))
	var ram: Piston = _ram(Vector3(-3.6, 7.9, -16.7), -90.0, 4.0, 10.0, 0.0)
	var cp: Dictionary = _cp(Vector3(0, 9.9, -27.8))
	# SHORTCUT: the mast's hoist airbag on the first section - it throws you up past the ram onto the top
	var pad: BouncePad = kit.pad(_w(Vector3(2.1, 3.3, -13.5)), 22.0, 0.0, _yaw, 0.7)
	_hop(cp0, p1)
	r_mantle(_w(Vector3(0, 0, -8.85)), _w(Vector3(0, 3.3, -12.0)))
	if route_variant == 2:
		r_walk(_w(Vector3(0.6, 3.3, -12.6)))
		r_pad(pad.global_position, _w(Vector3(0, 9.9, -19.6)))
	else:
		r_walk(_w(Vector3(0, 3.3, -14.0)))
		_wait(func() -> bool: return _ram_clear(ram, 0.0, 3.6), _w(Vector3(0, 3.3, -14.0)))
		r_mantle(_w(Vector3(0, 3.3, -14.65)), _w(Vector3(0, 6.6, -15.4)))
		r_mantle(_w(Vector3(0, 6.6, -18.05)), _w(Vector3(0, 9.9, -18.8)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	deco.floodlight(_w(Vector3(2.6, 0, 2.6)), _w(Vector3(0, 6.6, -16.7)))
	deco.tarp(_w(Vector3(-9.6, 14.0, -12.0)), 4.0, 2.2, _yaw + 70.0, Color(0.6, 0.62, 0.6))
	TempestFx.drips(self, _w(Vector3(-1.7, 9.8, -18.6)), _w(Vector3(1.7, 9.8, -18.6)), 10)
	return cp["c"]


# ---- stage 13: THE JIB - SET PIECE: board the tower crane's jib, ride it as it slews across the gap
# through the squalls, run out along it and jump off its tip onto the spire tower -----------------

var _crane: TempestCrane


func _stage_13() -> Vector3:
	var hub: Vector3 = Vector3(-14.0, 0, -6.0)
	_crane = TempestCrane.new()
	_crane.a0_deg = _yaw
	_crane.a1_deg = _yaw + 90.0
	# a 26 s cycle: four of the squall's 6.5 s beats, so the squalls always hit the jib mid-slew
	_crane.dwell = 5.0
	_crane.slew = 8.0
	_crane.position = _w(hub) - Vector3(0, _crane.jib_thick * 0.5, 0)
	add_child(_crane)
	var g: TempestGust = _gust(Vector3(-1.0, 2.0, -19.0), Vector3(30.0, 8.0, 30.0), 6.5, 0.357)
	var l1: Dictionary = _blk(Vector3(-14.0, 0, -34.2), 1.4, 1.2)
	var cp: Dictionary = _cp(Vector3(-14.0, 0, -40.3))
	var crane: TempestCrane = _crane
	var tip_far: Vector3 = _w(hub + Vector3(0, 0, -24.6))
	r_walk(_w(Vector3(1.2, 0, -2.0)))
	# (two waits, each under the bot's 14 s step limit: board at once if there is time, else wait for
	# the jib to reach the far end, then for it to come back and settle)
	_wait(func() -> bool: return crane.past_far_end(Game.course_time) or (crane.resting_for(Game.course_time, 0, 4.2) and _calm(g, 0.0, 3.6)))
	_wait(func() -> bool: return crane.resting_for(Game.course_time, 0, 3.0) and _calm(g, 0.0, 2.4))
	r_jump(_w(Vector3(2.0, 0, -2.65)), _w(Vector3(2.0, 0, -6.0)))
	_wait(func() -> bool: return crane.resting_for(Game.course_time, 1, 3.6) and _calm(g, 0.0, 3.2))
	r_walk(tip_far)
	route.append({"kind": "b_jump", "from": _w(hub + Vector3(0, 0, -25.4)), "to": _w(Vector3(-14.0, 0, -34.2)), "hold": true})
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 14: Spire Base - posts in the lull, a struck beam, a long leap, WALL RUN round the spire ---

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var p1: Dictionary = _blk(Vector3(0, 0, -8.6), 1.2, 1.2)
	var p2: Dictionary = _blk(Vector3(0, 0.5, -14.4), 2.4, 1.2)
	var rod: TempestRod = _rod(Vector3(0, 0.5, -14.4), Vector3(2.4, 3.2, 1.2), 7.0, 0.5714, -1.0)
	var p3: Dictionary = _blk(Vector3(0, 0.5, -20.8), 1.4, 1.2)
	kit.wallrun(_w(Vector3(2.5, 1.7, -30.9)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var l1: Dictionary = _blk(Vector3(-0.2, 0.5, -43.9), 2.4, 3.0)
	var cp: Dictionary = _cp(Vector3(0, 0.5, -51.4))
	var g: TempestGust = _gust(Vector3(0, 3.0, -14.0), Vector3(16.0, 10.0, 16.0), 7.0, 0.0)
	r_walk(_w(Vector3(0, 0, -0.6)))
	_wait(func() -> bool: return _calm(g, 0.0, 4.3) and _rod_ok(rod, 1.2, 3.9))
	_hop(cp0, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	r_wallrun(_w(Vector3(0.5, 0.5, -21.05)), _w(Vector3(2.0, 1.9, -25.0)), _w(Vector3(2.0, 1.9, -35.9)), _w(Vector3(-0.2, 0.5, -43.2)))
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 15: The Beacon - MANTLE onto the spire, two posts in the lull (the last rod), MANTLE the
# last ledge, the aircraft-warning beacon at the very top -------------------------------------------

func _stage_15() -> void:
	_ledge(Vector3(0, 3.3, -6.6), Vector3(3.4, 7.3, 3.4))
	var m1: Dictionary = _area(Vector3(0, 3.3, -6.6), 1.7, 1.7)
	var q1: Dictionary = _blk(Vector3(0, 3.8, -13.5), 1.2, 1.2)
	var q2: Dictionary = _blk(Vector3(0, 3.8, -19.7), 1.2, 1.2)
	var rod: TempestRod = _rod(Vector3(0, 3.8, -19.7), Vector3(1.2, 3.2, 1.2), 7.0, 0.5714)
	_ledge(Vector3(0, 7.1, -24.4), Vector3(3.4, 9.0, 3.4))
	var summit: StaticBody3D = kit.disc(_w(Vector3(0, 7.1, -29.6)), 3.5, 1.0, "main", 0.0)
	summit.name = "Summit"
	kit.finish(_w(Vector3(0, 7.1, -30.0)), _yaw)
	_finish_pos = _w(Vector3(0, 7.1, -30.0))
	var g: TempestGust = _gust(Vector3(0, 6.0, -16.0), Vector3(14.0, 10.0, 12.0), 7.0, 0.0)
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -5.3)))
	r_walk(_w(Vector3(0, 3.3, -6.0)))
	_wait(func() -> bool: return _calm(g, 0.0, 3.8) and _rod_ok(rod, 1.0, 3.7))
	_hop(m1, q1)
	_hop(q1, q2)
	r_mantle(_w(Vector3(0, 3.8, -20.05)), _w(Vector3(0, 7.1, -23.0)))
	r_walk(_w(Vector3(0, 7.1, -30.4)))
	# the summit: the aircraft-warning beacon on its mast behind the gate, the spire's piers under it
	_beacon_lens = deco.beacon(_w(Vector3(0, 7.1, -32.6)), 9.0)
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = TempestDecor.WARN_RED
	_beacon_light.omni_range = 26.0
	_beacon_light.light_energy = 0.0
	_beacon_light.shadow_enabled = false
	_beacon_light.position = _w(Vector3(0, 7.1 + 9.5, -32.6))
	add_child(_beacon_light)
	for c: Vector3 in [Vector3(0, 6.6, -29.6), Vector3(0, -4.0, -24.4), Vector3(0, -4.0, -6.6)]:
		deco.column(_w(c), -60.0, 1.6, TempestDecor.CONCRETE.darkened(0.15))
	_keep_out.append(Vector4(_finish_pos.x, _finish_pos.y, _finish_pos.z, 10.0))


var _beacon_light: OmniLight3D


# ---- environment and surroundings ---------------------------------------------------------------

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
	_env.sky = TempestSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.62, 0.66, 0.73)
	_env.ambient_light_energy = 0.8
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.5, 0.54, 0.6)
	_env.fog_density = 0.0017
	_env.fog_aerial_perspective = 0.45
	_env.fog_sky_affect = 0.2
	_env.fog_sun_scatter = 0.0
	_env.fog_height = CLOUD_Y + 25.0
	_env.fog_height_density = 0.025
	_env.glow_enabled = true
	_env.glow_intensity = 0.45
	_env.glow_bloom = 0.03
	_env.glow_hdr_threshold = 1.2
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 0.82
	_env.adjustment_contrast = 1.12
	# flat storm daylight from the pale break in the clouds, soft-edged shadows
	if _sun != null:
		_sun.light_color = Color(0.86, 0.89, 0.96)
		_sun.light_energy = 0.8
		_sun.rotation_degrees = Vector3(-38, 130, 0)
		_sun.shadow_blur = 2.2
	if _fill != null:
		_fill.light_color = Color(0.5, 0.56, 0.66)
		_fill.light_energy = 0.35
		_fill.rotation_degrees = Vector3(-55, -50, 0)


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


func _in_tower(p: Vector3, margin: float) -> bool:
	for t: Array in [[TOWER_A_LO, TOWER_A_HI], [TOWER_B_LO, TOWER_B_HI]]:
		var lo: Vector3 = t[0]
		var hi: Vector3 = t[1]
		if p.x > lo.x - margin and p.x < hi.x + margin and p.z > lo.z - margin and p.z < hi.z + margin:
			return true
	return false


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
	# the two towers and the climbing crane's mast down the main tower's south face
	deco.tower(TOWER_A_LO, TOWER_A_HI, TOWER_A_GLASS)
	deco.tower(TOWER_B_LO, TOWER_B_HI, TOWER_B_GLASS, 0.24)
	if _crane != null:
		var hub: Vector3 = _crane.global_position
		deco.crane_mast(Vector3(hub.x, hub.y - 0.6, hub.z), CITY_Y, Vector3(0, 0, -1), hub.z - TOWER_A_HI.z)
	# the skyline: glass towers all round, a few with cranes of their own, the city far below
	deco.skyline(Vector3(mid.x, mid.y, mid.z), 300.0, 780.0, 80, CITY_Y, func(p: Vector3) -> bool:
		return _clear_of(p, pts, 140.0) and not _in_tower(p, 60.0))
	deco.city(mid, CITY_Y)
	# the cloud deck between the course and the city, and the ragged ceiling overhead
	kit.cloud_field(Vector3(mid.x, CLOUD_Y, mid.z), Vector3(span.x * 0.5 + 300.0, 8.0, span.z * 0.5 + 300.0), 46)
	kit.cloud_field(Vector3(mid.x, hi.y + 75.0, mid.z), Vector3(span.x * 0.5 + 320.0, 12.0, span.z * 0.5 + 320.0), 22)
	storm.center = mid
	storm.top_y = hi.y + 80.0
	storm.bottom_y = CITY_Y
	# torn tarps snapping off the open floors of both towers, high above or well below the course
	var wind_yaw: float = -atan2(TempestFx.WIND.z, TempestFx.WIND.x)
	var tints: Array[Color] = [Color(0.18, 0.36, 0.62), Color(0.85, 0.42, 0.12), Color(0.6, 0.62, 0.6), Color(0.2, 0.45, 0.3)]
	var placed: int = 0
	var tries: int = 0
	while placed < 30 and tries < 600:
		tries += 1
		var t: Array = [[TOWER_A_LO, TOWER_A_HI, TOWER_A_GLASS], [TOWER_B_LO, TOWER_B_HI, TOWER_B_GLASS]][rng.randi() % 2]
		var tlo: Vector3 = t[0]
		var thi: Vector3 = t[1]
		var face: int = rng.randi() % 4
		var u: float = rng.randf()
		var p := Vector3(lerpf(tlo.x, thi.x, u), rng.randf_range(float(t[2]) - 20.0, thi.y - 2.0), lerpf(tlo.z, thi.z, u))
		match face:
			0:
				p.x = tlo.x - 0.2
			1:
				p.x = thi.x + 0.2
			2:
				p.z = tlo.z - 0.2
			3:
				p.z = thi.z + 0.2
		if not _clear_of(p, pts, 12.0):
			continue
		deco.tarp(p, rng.randf_range(3.0, 5.0), rng.randf_range(1.6, 2.8), rad_to_deg(wind_yaw) + rng.randf_range(-20.0, 20.0), tints[rng.randi() % tints.size()])
		placed += 1
	# ambient life along the whole route: driven rain, flying scraps, scud racing past below
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3(0, 0, 4)
		var c2: Vector3 = (here + prev) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 10.0, 7.0, absf(here.z - prev.z) * 0.5 + 10.0)
		TempestFx.rain(self, c2 + Vector3(0, 3.0, 0), ext, 110)
		TempestFx.debris(self, c2, ext, 22)
		TempestFx.scud(self, c2 + Vector3(0, -22.0, 0), ext + Vector3(20, 4, 20), 9)
	var last: Vector3 = _finish_pos
	TempestFx.rain(self, (last + _cp_world[_cp_world.size() - 1]) * 0.5 + Vector3(0, 7.0, 0), Vector3(12, 8, 22), 110)
	TempestFx.debris(self, last + Vector3(0, 3.0, 0), Vector3(12, 6, 12), 22)


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
		(tl["mat"] as StandardMaterial3D).emission_energy_multiplier = (3.4 if fmod(t, 0.18) < 0.09 else 1.2) if warn else 0.0
		var cycle: int = int(floor(t / per + float(tl["phase"])))
		if warn and cycle != int(tl["last"]):
			tl["last"] = cycle
			# SOUND: the machine's tell, a second before it strikes (a hydraulic hiss)
			WorldAudio.at(self, str(tl["clip"]), (tl["node"] as Node3D).global_position, 0.7, 35.0)
	# the aircraft-warning lamps: a slow red blink, all in step (like the real thing)
	var on: bool = fposmod(t, 1.5) < 0.3
	for m: StandardMaterial3D in deco.warn_mats:
		m.emission_energy_multiplier = 3.2 if on else 0.15
	if _beacon_lens != null and not finished:
		var b: float = 0.5 + 0.5 * sin(t * 4.2)
		_beacon_lens.emission_energy_multiplier = 1.0 + 3.0 * b * b
		_beacon_light.light_energy = 0.6 + 1.6 * b * b
	for e: Dictionary in _arrivals:
		e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
		if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
			e["cool"] = 3.0
			for p: GPUParticles3D in e["p"]:
				p.restart()
				p.emitting = true


## A burst of spray and sparks where the express hoist lets you out (fired when you arrive).
func _arrival(at: Vector3) -> void:
	var burst: Array[GPUParticles3D] = TempestFx.cp_burst()
	for p: GPUParticles3D in burst:
		p.position = _w(at) + Vector3(0, 0.4, 0)
		add_child(p)
	_arrivals.append({"at": _w(at), "p": burst, "cool": 0.0})


## The summit goes off: lightning strikes the beacon mast, signal flares burst over the spire, the
## beacon blazes.
func _finish_sequence() -> void:
	var top: Vector3 = _beacon_light.position
	storm.local_flash(top)
	var bolt := MeshInstance3D.new()
	bolt.mesh = ArmadaLightning.bolt_mesh(90.0, 14, 0.45, 77)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(2.0, 2.4, 3.4, 1.0)
	bm.disable_fog = true
	bolt.material_override = bm
	bolt.position = top + Vector3(0, 91.5, 0)
	bolt.extra_cull_margin = 100.0
	add_child(bolt)
	var tw0: Tween = create_tween()
	tw0.tween_interval(0.35)
	tw0.tween_callback(bolt.queue_free)
	var cols: Array[Color] = [Color(2.8, 0.5, 0.4), Color(2.6, 2.4, 2.2), Color(2.8, 1.8, 0.4), Color(1.6, 2.0, 2.8), Color(2.8, 0.5, 0.4)]
	for i: int in 5:
		var fw: GPUParticles3D = TempestFx.flare(cols[i], 70)
		fw.position = _finish_pos + Vector3(-8.0 + 4.0 * float(i), 10.0 + float(i % 2) * 4.0, 0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	# SOUND: the strike on the beacon mast and the site's all-clear horn
	WorldAudio.at(self, "tempest_finish_strike", top, 1.0, 120.0)
	WorldAudio.at(self, "tempest_beacon", _finish_pos, 1.0, 120.0)
	var tw: Tween = create_tween()
	tw.tween_property(_beacon_light, "light_energy", 9.0, 0.08)
	tw.tween_property(_beacon_light, "light_energy", 1.2, 1.2)
	await get_tree().create_timer(0.9).timeout
