extends LevelBase
## 18. WILD WEST HEIST - a canyon train robbery at sunset. A long freight-and-express train thunders
## across an endless timber trestle over a red-rock gorge, the river glinting far below, a huge sun
## sitting on the mesas ahead, and you run it car by car from the caboose to the locomotive's cab roof.
## Seventeen stages, each ending on a checkpoint.
##
## THE MOVING TRAIN: the train never moves - every car is ordinary static ground, so the run along it is
## as solid as any other level - and the WORLD scrolls past it instead (visual/frontier_scroll.gd): the
## sleepers and the tall trestle bents, telegraph poles, hoodoos, saguaros, rock fins, the river floor
## and the canyon walls' rock all slide back along +Z at the train's speed, the wheels and side rods turn
## to match, and the smoke, steam, dust and cinders all stream back toward the caboose. Trackside things
## that reach the roofs (the signal arms) come by the same way.
##
##  1 Caboose Getaway   MANTLE the caboose from its rear porch, over the cupola, leap to the crate stacks
##  2 Powder Flats      a chain of DYNAMITE going off down the powder flat - follow the blasts - and MANTLE
##                      the boxcar
##  3 Signal Row        three boxcar roofs while low SIGNAL ARMS sweep back over them: hop every arm
##  4 Lumber Yard       BRANCH: hop the log bundles across the skeleton log car | WALL RUN the circus
##                      billboard over them
##  5 Stamp Mill        under the ore car's two ore stamps (CRUSHERS), MANTLE the boxcar
##                      [shortcut: WALL RUN the mill's side past both stamps]
##  6 Express Car       BRANCH: MANTLE the express car and beat its roof DYNAMITE | time the vault door
##                      and dive into the vault (PORTAL) through to the coach
##  7 Saloon Car        BRANCH: through the saloon's swinging SALOON DOORS | over its roof past the stove-pipe
##                      STEAM JETS (lasers)
##  8 Tank Train        0.8 m catwalks on top of the tank cars, past the steam rams (PISTONS)
##  9 Ore Line          ride the MINE CARTS across the long couplings
##                      [shortcut: the greased plank (BOOST) into a long leap over the second cart's gap]
## 10 Low Bridge        three gondolas under tall LOW-BRIDGE boards (signal arms you cannot jump): duck
##                      into the coal pits as each one passes
## 11 Billboards        WALL RUN zig-zag: right billboard, wall jump, left billboard, over two bare log cars
## 12 THE TRESTLE GIVES WAY  SET PIECE: the trestle collapses under the lumber flats behind you - outrun
##                      the front as it chases you car by car [shortcut: WALL RUN the lumber sign]
## 13 Mail Car          MANTLE the mail car, past the mail-bag rams (PISTONS), over the mail crane's sweep
## 14 Cattle Run        the long fuse: a DYNAMITE chain lit behind you burns forward along the stock car
##                      roofs - outrun it (or let it pass and follow it)
## 15 Tender            the water tank's STEAM JETS, onto the coal [shortcut: WALL RUN the tender's side]
## 16 Running Board     the locomotive's 0.7 m running board: injector STEAM JETS and the air pump's ram
## 17 Whistle Stop      MANTLE the smokebox, back along the boiler top past the swinging bell and the
##                      safety valve, up the steam dome to the FINISH on the cab roof - and the whistle blows
##
## Frontier mechanics (own scripts): FrontierDynamite (fuse + blast), FrontierSignals (signal arms coming
## past on the scrolling world), FrontierCollapse (the set piece), FrontierDoors (saloon doors),
## FrontierCart (mine carts), FrontierSteam (steam-jet lasers), FrontierVault (the vault door).
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut.

const DECK: float = 1.5
const ROOF: float = 5.0
const TRIM := Color(0.95, 0.8, 0.3)
const DECK_TOP := Color(0.62, 0.47, 0.32)
const DECK_SIDE := Color(0.34, 0.22, 0.15)
const ROOF_TOP := Color(0.38, 0.32, 0.29)
const CRATE_TOP := Color(0.78, 0.62, 0.4)
const CRATE_SIDE := Color(0.64, 0.47, 0.28)
const LOG_TOP := Color(0.62, 0.44, 0.28)
const LOG_SIDE := Color(0.4, 0.27, 0.17)
const CABOOSE := Color(0.68, 0.15, 0.1)
const BOX_RED := Color(0.55, 0.17, 0.11)
const BOX_BROWN := Color(0.45, 0.28, 0.17)
const BOX_OCHRE := Color(0.78, 0.55, 0.24)
const EXPRESS := Color(0.12, 0.27, 0.2)
const COACH := Color(0.3, 0.12, 0.1)
const SALOON := Color(0.42, 0.24, 0.12)
const TANK_BLACK := Color(0.12, 0.11, 0.11)
const STOCK := Color(0.62, 0.3, 0.14)
const GONDOLA := Color(0.24, 0.26, 0.2)
const STEEL := Color(0.3, 0.3, 0.32)
const COAL := Color(0.1, 0.1, 0.11)

## World z of the current stage's origin (the previous checkpoint); the train runs toward -Z.
var _oz: float = 0.0
var deco: FrontierDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## Every car's world z extent (rear, front), in build order.
var _cars: Array[Vector2] = []
var _cp_world: Array[Vector3] = []
var _cp_fx: Dictionary = {}
var _arrivals: Array[Dictionary] = []
var _finish_pos: Vector3 = Vector3.ZERO
var _whistle_pos: Vector3 = Vector3.ZERO
var _rods: Array[Node3D] = []
var _rod_z: float = 0.0
var _drv_r: float = 1.0
var _signal_lines: Array[FrontierSignals] = []


func _configure() -> void:
	theme_id = "frontier"
	music_track = "frontier"
	kill_y = -24.0
	route_variants = 3


# ---- frame helpers (the train runs straight along -Z; frames only shift in z) ---------------------

func _w(l: Vector3) -> Vector3:
	return Vector3(l.x, l.y, l.z + _oz)


func _wz(z: float) -> float:
	return z + _oz


## A walkable timber slab (collision + the wood look), top centre at local `top`.
func _slab(top: Vector3, size: Vector3, top_col: Color, side_col: Color, kind: int = 0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.box(size, FrontierDecor.wood(top_col, side_col, TRIM, size * 0.5, kind)))
	body.position = _w(top) - Vector3(0, size.y * 0.5, 0)
	add_child(body)
	return body


## A solid block that is not meant to be stood on (walls, the cab): collision + a flat colour.
func _solid(center: Vector3, size: Vector3, col: Color, mat: Material = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.box(size, mat if mat != null else Look.flat(col, 0.8)))
	body.position = _w(center)
	add_child(body)
	return body


## Repaint a kit piece's platform-shader faces as timber in the given colours.
func _paint(n: Node, top_col: Color, side_col: Color, kind: int = 0) -> void:
	for c: Node in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var sm := mi.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		mi.material_override = FrontierDecor.wood(top_col, side_col, TRIM, sm.get_shader_parameter("half_size"), kind)


func _crate(top: Vector3, size: Vector3) -> StaticBody3D:
	return _slab(top, size, CRATE_TOP, CRATE_SIDE, 1)


## A stack of logs (walkable top) sitting on a log car's bolster, the log ends showing.
func _logs(top: Vector3, size: Vector3) -> void:
	_slab(top, size, LOG_TOP, LOG_SIDE, 3)
	var ends: StandardMaterial3D = Look.flat(Color(0.86, 0.68, 0.44), 0.85)
	var rings: int = maxi(int(size.x / 0.5), 2)
	for sz: float in [-1.0, 1.0]:
		for i: int in rings:
			for j: int in maxi(int((size.y - 0.3) / 0.5), 1):
				var p: Vector3 = _w(top) + Vector3(-size.x * 0.5 + (float(i) + 0.5) * size.x / float(rings), -0.35 - float(j) * 0.5, sz * (size.z * 0.5 + 0.02))
				var log_end := Look.cylinder(0.22, 0.06, ends, p, -1.0, 10)
				log_end.rotation.x = PI * 0.5
				add_child(log_end)


func _car(zr: float, zf: float, gear: bool = true) -> void:
	_cars.append(Vector2(_wz(zr), _wz(zf)))
	if gear:
		deco.running_gear(_wz(zr), _wz(zf), 1.25)


func _flatcar(zr: float, zf: float, deck: bool = true) -> void:
	_car(zr, zf)
	var mid: float = (zr + zf) * 0.5
	if deck:
		_slab(Vector3(0, DECK, mid), Vector3(4.0, 0.45, zr - zf), DECK_TOP, DECK_SIDE, 3)
		deco.stakes(_wz(zr), _wz(zf), DECK, 2.0, 0.6)
	else:
		# a bare log car: centre sill and bolsters only - nothing to stand on between the loads
		deco.box(_w(Vector3(0, 1.2, mid)), Vector3(0.6, 0.3, zr - zf - 0.4), Look.flat(Color(0.14, 0.12, 0.11), 0.6, 0.4))
		for z: float in [zr - 1.0, zf + 1.0]:
			deco.box(_w(Vector3(0, 1.3, z)), Vector3(3.6, 0.3, 0.4), Look.flat(Color(0.14, 0.12, 0.11), 0.6, 0.4))


func _boxcar(zr: float, zf: float, col: Color, ledge: bool = false) -> Node3D:
	_car(zr, zf)
	var mid: float = (zr + zf) * 0.5
	var size := Vector3(4.0, ROOF - 1.1, zr - zf)
	var n: Node3D
	if ledge:
		n = kit.ledge(_w(Vector3(0, ROOF, mid)), size)
		_paint(n, ROOF_TOP, col, 2)
	else:
		n = _slab(Vector3(0, ROOF, mid), size, ROOF_TOP, col, 2)
	deco.boxcar_dress(_wz(zr), _wz(zf), ROOF, col)
	return n


## Gondola: floor, side and end walls (tops walkable), from zr to zf.
func _gondola(zr: float, zf: float) -> void:
	_car(zr, zf)
	var mid: float = (zr + zf) * 0.5
	var len: float = zr - zf
	_slab(Vector3(0, DECK, mid), Vector3(4.0, 0.45, len), Color(0.24, 0.22, 0.2), GONDOLA, 3)
	for sx: float in [-1.0, 1.0]:
		_slab(Vector3(sx * 1.75, 3.3, mid), Vector3(0.5, 1.8, len), GONDOLA.lightened(0.15), GONDOLA, 3)
	for z: float in [zr - 0.25, zf + 0.25]:
		_slab(Vector3(0, 3.3, z), Vector3(3.0, 1.8, 0.5), GONDOLA.lightened(0.15), GONDOLA, 3)
	deco.gondola_ribs(_wz(zr), _wz(zf), 2.0, DECK - 0.2, 3.3)


func _cp(c: Vector3, yaw: float = 0.0) -> void:
	var cp: Checkpoint = kit.checkpoint(_w(c), yaw)
	var at: Vector3 = _w(c)
	_cp_world.append(at)
	# lanterns hung off the car sides beside it
	for sx: float in [-1.0, 1.0]:
		deco.lantern(at + Vector3(sx * 2.2, 0.9, 0), Color(1.0, 0.72, 0.36), sx < 0.0)
	# banked-stage feedback: a shower of gold coins and a ring of dust off the boards
	var coins: GPUParticles3D = FrontierFx.loot(1.6, 44)
	coins.position = at + Vector3(0, 0.8, 0)
	add_child(coins)
	var ring: GPUParticles3D = FrontierFx.dust_ring(1.8)
	ring.position = at + Vector3(0, 0.15, 0)
	add_child(ring)
	_cp_fx[cp] = [coins, ring]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: a jingle of coins as a stage of the heist is banked
			WorldAudio.at(self, "frontier_coins", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_fx[which]:
				p.restart())


## A pair of fork signs: a lamp post and a painted arrow board in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	var post: StandardMaterial3D = Look.flat(Color(0.3, 0.22, 0.15), 0.9)
	var at: Vector3 = _w(p)
	deco.box(at + Vector3(0, 0.9, 0), Vector3(0.12, 1.8, 0.12), post)
	deco.box(at + Vector3(0, 1.75, -0.1), Vector3(0.9, 0.35, 0.06), Look.flat(col, 0.5, 0.0, 0.8))
	kit.glow_strip(at + Vector3(0, 0.03, -0.6), Vector3(0.9, 0.04, 0.3), col)


# ---- bot helpers (all deterministic from the course clock) -----------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Walk to `to` across roofs swept by `sig`'s arms, hopping each one (route_bot's stream step).
func _stream(sig: FrontierSignals, to: Vector3) -> void:
	route.append({"kind": "ascent_stream", "to": to, "stream": sig, "lead": 0.12, "tol": 0.6})


static func _dyn_clear(d: FrontierDynamite, a: float, b: float) -> bool:
	return d.is_clear_for(Game.course_time, a, b)


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
		s += 0.05
	return true


static func _press_ok(c: Crusher, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if c.gap_at(Game.course_time + s) < 2.1 or not c.is_clear_for(Game.course_time + s, 0.0):
			return false
		s += 0.04
	return true


# ---- the course -------------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = FrontierDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, DECK + 0.1, 1.8), 0.0)
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16]
	_oz = 0.0
	for st: Callable in stages:
		var end: Vector3 = st.call()
		_oz += end.z
	_stage_17()
	_couplers()
	_surroundings()


# ---- stage 1: Caboose Getaway ------------------------------------------------------------------------

func _stage_1() -> Vector3:
	# the caboose: rear porch (the start), body (a mantle wall), cupola, front porch
	_car(3.6, -13.0)
	_slab(Vector3(0, DECK, 1.3), Vector3(4.0, 0.45, 4.6), DECK_TOP, CABOOSE, 3)
	var body: LedgeBlock = kit.ledge(_w(Vector3(0, ROOF, -6.0)), Vector3(4.0, ROOF - 1.1, 10.0))
	_paint(body, ROOF_TOP, CABOOSE, 2)
	_slab(Vector3(0, 6.3, -5.5), Vector3(2.6, 1.3, 3.0), ROOF_TOP, CABOOSE, 2)
	_slab(Vector3(0, DECK, -12.0), Vector3(4.0, 0.45, 2.0), DECK_TOP, CABOOSE, 3)
	deco.caboose_dress(_wz(-1.0), _wz(-11.0), ROOF, Vector2(_wz(-4.0), _wz(-7.0)), 6.3)
	deco.railing(DECK, _wz(3.5), _wz(-0.9), 1.95, 1.0)
	deco.railing(DECK, _wz(-11.1), _wz(-12.9), 1.95)
	# flatcar A: crate stacks climbing to the big stack at its front
	_flatcar(-16.4, -34.4)
	_crate(Vector3(0, 3.8, -17.6), Vector3(2.4, 2.3, 2.4))
	_crate(Vector3(0.9, 4.5, -22.2), Vector3(1.8, 3.0, 1.8))
	_crate(Vector3(-0.6, 5.1, -26.8), Vector3(1.8, 3.6, 1.8))
	_crate(Vector3(0, 4.4, -31.7), Vector3(4.0, 2.9, 5.4))
	_cp(Vector3(0, 4.4, -31.8))
	r_mantle(_w(Vector3(0, DECK, -0.35)), _w(Vector3(0, ROOF, -2.0)))
	r_jump(_w(Vector3(0, ROOF, -3.65)), _w(Vector3(0, 6.3, -5.0)))
	r_jump(_w(Vector3(0, 6.3, -6.65)), _w(Vector3(0, ROOF, -8.4)))
	r_jump(_w(Vector3(0, ROOF, -10.65)), _w(Vector3(0, 3.8, -17.4)))
	r_jump(_w(Vector3(0.3, 3.8, -18.45)), _w(Vector3(0.9, 4.5, -21.9)))
	r_jump(_w(Vector3(0.6, 4.5, -22.75)), _w(Vector3(-0.6, 5.1, -26.5)))
	r_jump(_w(Vector3(-0.4, 5.1, -27.35)), _w(Vector3(0, 4.4, -30.4)))
	r_walk(_w(Vector3(0, 4.4, -31.8)))
	r_checkpoint()
	FrontierFx.scraps(self, _w(Vector3(0, 7.0, -16.0)), Vector3(4.0, 3.0, 16.0), 14)
	return Vector3(0, 4.4, -31.8)


# ---- stage 2: Powder Flats - follow the blasts, mantle the boxcar ----------------------------------

func _stage_2() -> Vector3:
	_flatcar(-6.4, -26.4)
	# the powder kegs lining the flat (walkable, off the path)
	for z: float in [-9.0, -14.0, -19.5, -24.0]:
		for sx: float in [-1.0, 1.0]:
			var keg: StaticBody3D = kit.disc(_w(Vector3(sx * 1.55, DECK + 0.9, z)), 0.42, 0.9, "alt", 0.0)
			_paint(keg, Color(0.5, 0.34, 0.2), Color(0.42, 0.26, 0.15), 3)
	# the dynamite chain: three bundles on one fuse from the plunger box, blowing one after another
	# 0.6 s apart down the flat - follow the blasts
	var plunger: Vector3 = _w(Vector3(1.7, DECK, -7.2))
	_plunger(plunger)
	var zs: Array[float] = [-11.0, -16.5, -22.0]
	var dyn: Array[FrontierDynamite] = []
	var prev: Vector3 = plunger
	for i: int in zs.size():
		var at: Vector3 = _w(Vector3(0, DECK, zs[i]))
		var fuse := PackedVector3Array()
		if i == 0:
			fuse.append(prev - at + Vector3(0, 0.03, 0))
			fuse.append(Vector3(1.7, 0.03, 0))
		else:
			fuse.append(Vector3(1.5, 0.03, zs[i - 1] - zs[i] - 1.0))
			fuse.append(Vector3(1.5, 0.03, 0))
		fuse.append(Vector3(0.25, 0.03, 0))
		dyn.append(_dynamite(at, fuse, 3.0, fposmod(-0.1333 * float(i), 1.0), 2.0))
		prev = at
	var c: Node3D = _boxcar(-29.8, -41.8, BOX_RED, true)
	c.name = "PowderBoxcar"
	_cp(Vector3(0, ROOF, -39.2))
	r_jump(_w(Vector3(0, 4.4, -2.25)), _w(Vector3(0, DECK, -7.6)))
	_wait(func() -> bool: return _dyn_clear(dyn[0], 0.0, 1.9) and _dyn_clear(dyn[1], 0.5, 2.5) and _dyn_clear(dyn[2], 1.1, 3.1))
	r_walk(_w(Vector3(0, DECK, -25.6)))
	r_mantle(_w(Vector3(0, DECK, -26.0)), _w(Vector3(0, ROOF, -31.0)))
	r_walk(_w(Vector3(0, ROOF, -39.2)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 4.0, -16.0)), Vector3(4.0, 3.0, 10.0), 40)
	return Vector3(0, ROOF, -39.2)


## A bundle of dynamite on the floor at world `at` with a fuse (points relative to it).
func _dynamite(at: Vector3, fuse: PackedVector3Array, period: float, phase: float, burn: float) -> FrontierDynamite:
	var d := FrontierDynamite.new()
	d.position = at
	d.fuse = fuse
	d.period = period
	d.phase = phase
	d.burn = burn
	add_child(d)
	return d


## The plunger box the fuse starts from (dressing).
func _plunger(at: Vector3) -> void:
	deco.box(at + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.4), Look.flat(Color(0.45, 0.28, 0.15), 0.8))
	deco.box(at + Vector3(0, 0.75, 0), Vector3(0.06, 0.55, 0.06), Look.flat(Color(0.2, 0.2, 0.2), 0.5, 0.6))
	deco.box(at + Vector3(0, 1.02, 0), Vector3(0.5, 0.08, 0.08), Look.flat(Color(0.2, 0.2, 0.2), 0.5, 0.6))
	deco.box(at + Vector3(0, 0.3, -0.21), Vector3(0.4, 0.12, 0.02), Look.flat(Color(0.9, 0.2, 0.1), 0.6, 0.0, 0.6))


# ---- stage 3: Signal Row - low arms sweeping the boxcar roofs --------------------------------------------

func _stage_3() -> Vector3:
	_boxcar(-6.8, -20.8, BOX_BROWN)
	_boxcar(-25.4, -39.4, BOX_RED)
	_boxcar(-44.2, -58.2, BOX_OCHRE)
	var sig: FrontierSignals = _signals(-50.0, -6.0, ROOF + 0.35, 0.3, 26.0, 3.7, 0.0)
	_cp(Vector3(0, ROOF, -55.6))
	r_jump(_w(Vector3(0, ROOF, -2.25)), _w(Vector3(0, ROOF, -7.8)))
	_stream(sig, _w(Vector3(0, ROOF, -20.3)))
	r_jump(_w(Vector3(0, ROOF, -20.45)), _w(Vector3(0, ROOF, -26.4)))
	_stream(sig, _w(Vector3(0, ROOF, -39.0)))
	r_jump(_w(Vector3(0, ROOF, -39.05)), _w(Vector3(0, ROOF, -45.2)))
	_stream(sig, _w(Vector3(0, ROOF, -55.6)))
	r_checkpoint()
	FrontierFx.scraps(self, _w(Vector3(0, 7.0, -30.0)), Vector3(5.0, 2.0, 26.0), 20)
	return Vector3(0, ROOF, -55.6)


## A line of signal posts coming past on the right (or left) whose arms are down over the local z
## stretch [win_a, win_b] (win_a ahead, more negative).
func _signals(win_a: float, win_b: float, arm_y: float, arm_h: float, spacing: float, side: float, offset: float) -> FrontierSignals:
	var s := FrontierSignals.new()
	s.win_a = _wz(win_a)
	s.win_b = _wz(win_b)
	s.arm_y = arm_y
	s.arm_thick = arm_h
	s.spacing = spacing
	s.side_x = side
	s.offset = offset
	# added once the whole train is built: the posts run its full length (none ever pops up near you)
	_signal_lines.append(s)
	return s


# ---- stage 4: Lumber Yard (BRANCH) - log tops, or the billboard wall run -------------------------------

func _stage_4() -> Vector3:
	_flatcar(-6.6, -30.6, false)
	# LEFT (gold): the log bundles across the bare log car
	_logs(Vector3(-1.0, 4.0, -8.8), Vector3(2.0, 2.5, 2.4))
	_logs(Vector3(-1.1, 4.6, -14.8), Vector3(1.4, 3.1, 1.4))
	_logs(Vector3(-0.8, 4.0, -20.4), Vector3(1.4, 2.5, 1.4))
	_logs(Vector3(-1.1, 4.6, -25.6), Vector3(1.3, 3.1, 1.3))
	_logs(Vector3(-0.8, 3.8, -30.0), Vector3(1.8, 2.3, 1.8))
	# RIGHT (blue): the circus billboard on its posts - a wall run past the logs
	kit.wallrun(_w(Vector3(2.35, 5.6, -13.0)), Vector3(14.0, 8.2, 0.5), 90.0)
	for z: float in [-6.4, -13.0, -19.6]:
		deco.box(_w(Vector3(2.75, 5.2, z)), Vector3(0.24, 9.2, 0.24), Look.flat(Color(0.3, 0.22, 0.15), 0.9))
	_flatcar(-33.8, -49.8)
	_cp(Vector3(0, DECK, -47.2))
	_sign(Vector3(-1.75, ROOF, -1.6), Color(1.0, 0.75, 0.25))
	_sign(Vector3(1.75, ROOF, -1.6), Color(0.35, 0.8, 1.0))
	if route_variant != 1:
		r_jump(_w(Vector3(-0.4, ROOF, -2.25)), _w(Vector3(-1.0, 4.0, -8.6)))
		r_jump(_w(Vector3(-1.0, 4.0, -9.65)), _w(Vector3(-1.1, 4.6, -14.7)))
		r_jump(_w(Vector3(-1.1, 4.6, -15.15)), _w(Vector3(-0.8, 4.0, -20.3)))
		r_jump(_w(Vector3(-0.8, 4.0, -20.75)), _w(Vector3(-1.1, 4.6, -25.5)))
		r_jump(_w(Vector3(-1.1, 4.6, -25.9)), _w(Vector3(-0.8, 3.8, -29.9)))
	else:
		r_wallrun(_w(Vector3(0.6, ROOF, -2.25)), _w(Vector3(1.95, 5.4, -7.0)), _w(Vector3(1.95, 5.4, -16.5)), _w(Vector3(-1.1, 4.6, -25.5)))
		r_jump(_w(Vector3(-1.1, 4.6, -25.9)), _w(Vector3(-0.8, 3.8, -29.9)))
	r_jump(_w(Vector3(-0.8, 3.8, -30.55)), _w(Vector3(-0.4, DECK, -35.4)))
	r_walk(_w(Vector3(0, DECK, -47.2)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 4.0, -24.0)), Vector3(4.0, 3.0, 14.0), 40)
	return Vector3(0, DECK, -47.2)


# ---- stage 5: Stamp Mill - under the ore stamps (crushers), mantle out [shortcut: the mill wall] -------

func _stage_5() -> Vector3:
	_flatcar(-6.2, -28.2)
	var s1: Crusher = _stamp(Vector3(0, DECK, -12.0), 0.0)
	var s2: Crusher = _stamp(Vector3(0, DECK, -18.6), 0.806)
	# SHORTCUT: the mill's side wall is a wall run straight past both stamps
	kit.wallrun(_w(Vector3(-2.4, 3.3, -16.0)), Vector3(16.0, 5.4, 0.5), 90.0)
	_boxcar(-31.6, -43.6, BOX_RED, true)
	_cp(Vector3(0, ROOF, -41.0))
	r_jump(_w(Vector3(0, DECK, -2.25)), _w(Vector3(0, DECK, -7.4)))
	if route_variant == 2:
		r_wallrun(_w(Vector3(-0.3, DECK, -7.4)), _w(Vector3(-2.0, 2.6, -11.2)), _w(Vector3(-2.0, 2.8, -21.0)), _w(Vector3(-0.3, DECK, -26.4)))
	else:
		_wait(func() -> bool: return _press_ok(s1, 0.0, 1.7) and _press_ok(s2, 0.7, 2.5))
		r_walk(_w(Vector3(0, DECK, -26.4)))
	r_mantle(_w(Vector3(0, DECK, -27.6)), _w(Vector3(0, ROOF, -32.8)))
	r_walk(_w(Vector3(0, ROOF, -41.0)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 3.5, -16.0)), Vector3(3.0, 2.0, 9.0), 50)
	return Vector3(0, ROOF, -41.0)


## An ore stamp: the crusher dressed as a stamp-mill shoe on its timber stem, in a timber frame.
func _stamp(floor_c: Vector3, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(floor_c), Vector3(3.4, 1.2, 2.6), 3.0, 3.6, phase, 0.0)
	var iron: StandardMaterial3D = Look.flat(Color(0.2, 0.19, 0.19), 0.45, 0.7)
	cr.add_child(Look.box(Vector3(3.5, 0.5, 2.7), iron, Vector3(0, -0.35, 0)))
	cr.add_child(Look.box(Vector3(0.5, 3.0, 0.5), Look.flat(Color(0.32, 0.23, 0.16), 0.9), Vector3(0, 2.0, 0)))
	for sx: float in [-1.0, 1.0]:
		cr.add_child(Look.box(Vector3(0.2, 0.9, 2.75), Look.flat(Color(0.5, 0.36, 0.2), 0.8), Vector3(sx * 1.65, 0.1, 0)))
	return cr


# ---- stage 6: Express Car (BRANCH) - the roof's dynamite, or the vault --------------------------------

var _vault: FrontierVault


func _stage_6() -> Vector3:
	# the express car: an open end porch and the strong-room body (a mantle wall)
	_car(-5.8, -27.0)
	_slab(Vector3(0, DECK, -7.4), Vector3(4.0, 0.45, 3.2), DECK_TOP, EXPRESS, 3)
	var body: LedgeBlock = kit.ledge(_w(Vector3(0, ROOF, -18.0)), Vector3(4.0, ROOF - 1.1, 18.0))
	_paint(body, ROOF_TOP, EXPRESS, 2)
	deco.boxcar_dress(_wz(-9.0), _wz(-27.0), ROOF, EXPRESS)
	deco.railing(DECK, _wz(-5.9), _wz(-8.9), 1.95)
	# LEFT (red): the roof run past three bundles of dynamite blowing down the roof
	var dyn: Array[FrontierDynamite] = []
	var zs: Array[float] = [-13.0, -18.0, -23.0]
	var plunger: Vector3 = _w(Vector3(-1.7, ROOF, -10.4))
	_plunger(plunger)
	for i: int in zs.size():
		var at: Vector3 = _w(Vector3(0, ROOF, zs[i]))
		var fuse := PackedVector3Array()
		if i == 0:
			fuse.append(plunger - at + Vector3(0, 0.03, 0))
			fuse.append(Vector3(-1.7, 0.03, 0))
		else:
			fuse.append(Vector3(-1.5, 0.03, zs[i - 1] - zs[i] - 1.0))
			fuse.append(Vector3(-1.5, 0.03, 0))
		fuse.append(Vector3(-0.25, 0.03, 0))
		dyn.append(_dynamite(at, fuse, 3.0, fposmod(0.5 - 0.13 * float(i), 1.0), 2.0))
	# RIGHT (gold): the vault door, and behind it the vault (a warp) through to the coach
	_vault = FrontierVault.new()
	_vault.position = _w(Vector3(-0.1, DECK, -8.1))
	_vault.width = 2.6
	_vault.height = 2.8
	_vault.period = 4.6
	_vault.phase = 0.0
	add_child(_vault)
	var portal: WarpPortal = kit.portal(_w(Vector3(1.15, DECK, -8.6)), 0.0, _w(Vector3(0, ROOF, -34.8)), 0.0, 6.0)
	_arrival(_w(Vector3(0, ROOF, -35.6)))
	deco.box(_w(Vector3(1.15, DECK + 3.1, -8.75)), Vector3(3.1, 0.4, 0.3), Look.flat(Color(0.2, 0.2, 0.22), 0.4, 0.7))
	for sx: float in [-0.25, 2.55]:
		deco.box(_w(Vector3(sx, DECK + 1.5, -8.75)), Vector3(0.3, 3.0, 0.3), Look.flat(Color(0.2, 0.2, 0.22), 0.4, 0.7))
	# the coach beyond
	_car(-30.4, -48.4)
	var coach: StaticBody3D = _slab(Vector3(0, ROOF, -39.4), Vector3(4.0, ROOF - 1.1, 18.0), ROOF_TOP, COACH, 2)
	coach.name = "Coach"
	deco.coach_dress(_wz(-30.4), _wz(-48.4), ROOF, COACH)
	_cp(Vector3(0, ROOF, -45.8))
	_sign(Vector3(-1.75, ROOF, -1.6), Color(1.0, 0.4, 0.3))
	_sign(Vector3(1.75, ROOF, -1.6), Color(1.0, 0.8, 0.3))
	if route_variant != 1:
		r_jump(_w(Vector3(-1.0, ROOF, -2.25)), _w(Vector3(-1.4, DECK, -6.6)))
		r_mantle(_w(Vector3(-1.4, DECK, -8.3)), _w(Vector3(-1.4, ROOF, -10.2)))
		r_walk(_w(Vector3(0, ROOF, -10.4)))
		_wait(func() -> bool: return _dyn_clear(dyn[0], 0.0, 1.5) and _dyn_clear(dyn[1], 0.3, 2.3) and _dyn_clear(dyn[2], 0.8, 2.9))
		r_walk(_w(Vector3(0, ROOF, -26.6)))
		r_jump(_w(Vector3(0, ROOF, -26.65)), _w(Vector3(0, ROOF, -31.6)))
	else:
		r_jump(_w(Vector3(1.0, ROOF, -2.25)), _w(Vector3(1.15, DECK, -6.4)))
		var v: FrontierVault = _vault
		_wait(func() -> bool: return v.is_open_for(Game.course_time, 0.0, 1.6))
		r_portal(_w(Vector3(1.15, DECK, -8.8)), portal.exit_point())
	r_walk(_w(Vector3(0, ROOF, -45.8)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 7.0, -20.0)), Vector3(4.0, 3.0, 12.0), 40)
	return Vector3(0, ROOF, -45.8)


## A burst of coins and dust where a portal lets you out (fired when you arrive).
func _arrival(at: Vector3) -> void:
	var p: GPUParticles3D = FrontierFx.loot(1.0, 30)
	p.position = at + Vector3(0, 0.6, 0)
	add_child(p)
	var d: GPUParticles3D = FrontierFx.dust_ring(1.4)
	d.position = at + Vector3(0, 0.1, 0)
	add_child(d)
	_arrivals.append({"at": at, "p": [p, d], "cool": 0.0})


# ---- stage 7: Saloon Car (BRANCH) - the swinging doors, or the stove-pipe steam on the roof ------------

func _stage_7() -> Vector3:
	# the saloon car: one long floor, an open-sided body under a roof on posts, three partitions
	_car(-6.2, -33.2)
	_slab(Vector3(0, DECK, -19.7), Vector3(4.0, 0.45, 27.0), Color(0.5, 0.32, 0.18), SALOON, 3)
	_slab(Vector3(0, ROOF, -19.1), Vector3(4.2, 0.4, 21.0), ROOF_TOP, SALOON, 3)
	var post: StandardMaterial3D = Look.flat(SALOON.darkened(0.3), 0.8)
	for i: int in 8:
		var z: float = -8.8 - float(i) * 20.6 / 7.0
		for sx: float in [-1.0, 1.0]:
			deco.box(_w(Vector3(sx * 1.95, 3.05, z)), Vector3(0.14, 3.1, 0.14), post)
	deco.railing(DECK, _wz(-6.3), _wz(-8.6), 1.95)
	deco.railing(DECK, _wz(-29.7), _wz(-33.1), 1.95)
	# LEFT (red): through the bar - three partitions, each with a pair of batwing doors
	var doors: Array[FrontierDoors] = []
	var dz: Array[float] = [-12.5, -19.0, -25.5]
	for i: int in dz.size():
		for sx: float in [-1.0, 1.0]:
			_solid(Vector3(sx * 1.6, 3.05, dz[i]), Vector3(0.8, 3.1, 0.3), SALOON, FrontierDecor.wood(SALOON, SALOON, TRIM, Vector3(0.4, 1.55, 0.15), 2))
		_solid(Vector3(0, 4.15, dz[i]), Vector3(2.4, 0.9, 0.3), SALOON, FrontierDecor.wood(SALOON, SALOON, TRIM, Vector3(1.2, 0.45, 0.15), 3))
		var d := FrontierDoors.new()
		d.position = _w(Vector3(0, DECK, dz[i]))
		d.width = 2.4
		d.period = 3.4
		d.shut_time = 1.2
		d.phase = fposmod(-0.1 * float(i), 1.0)
		add_child(d)
		doors.append(d)
		deco.lantern(_w(Vector3(0, 4.2, dz[i] + 1.4)), Color(1.0, 0.7, 0.35), i == 1)
	# the bar along the left wall between the partitions, and a piano
	_solid(Vector3(-1.55, DECK + 0.55, -15.8), Vector3(0.6, 1.1, 4.5), Color(0.35, 0.18, 0.08))
	_solid(Vector3(1.5, DECK + 0.65, -22.2), Vector3(0.7, 1.3, 2.0), Color(0.12, 0.08, 0.06))
	# RIGHT (white): a water barrel up to the roof, three stove pipes jetting steam across it
	var barrel: StaticBody3D = kit.disc(_w(Vector3(1.2, 3.3, -7.2)), 0.75, 1.8, "alt", 0.0)
	_paint(barrel, Color(0.5, 0.34, 0.2), Color(0.45, 0.28, 0.16), 3)
	var jets: Array[FrontierSteam] = []
	var jz: Array[float] = [-13.0, -19.5, -26.0]
	for i: int in jz.size():
		jets.append(_steam(Vector3(0, ROOF + 0.9, jz[i]), Vector3(4.4, 1.8, 0.3), 0.0, 2.6, 0.36, fposmod(-0.22 * float(i), 1.0)))
		deco.box(_w(Vector3(-2.45, ROOF + 0.4, jz[i])), Vector3(0.4, 1.6, 0.4), Look.flat(Color(0.15, 0.14, 0.14), 0.5, 0.5))
	_cp(Vector3(0, DECK, -31.0))
	_sign(Vector3(-1.75, ROOF, -1.6), Color(1.0, 0.4, 0.3))
	_sign(Vector3(1.75, ROOF, -1.6), Color(0.9, 0.95, 1.0))
	if route_variant != 1:
		r_jump(_w(Vector3(-0.9, ROOF, -2.25)), _w(Vector3(-0.6, DECK, -7.4)))
		var ws: Array[float] = [-10.8, -17.3, -23.8]
		for i: int in doors.size():
			var dd: FrontierDoors = doors[i]
			r_walk(_w(Vector3(0, DECK, ws[i])))
			_wait(func() -> bool: return dd.is_open_for(Game.course_time, 0.0, 1.6))
		r_walk(_w(Vector3(0, DECK, -31.0)))
	else:
		r_jump(_w(Vector3(1.0, ROOF, -2.25)), _w(Vector3(1.2, 3.3, -6.9)))
		r_jump(_w(Vector3(1.0, 3.3, -7.75)), _w(Vector3(0.6, ROOF, -10.0)))
		var hs: Array[float] = [-11.6, -18.1, -24.6]
		for i: int in jets.size():
			var j: FrontierSteam = jets[i]
			r_walk(_w(Vector3(0, ROOF, hs[i])))
			_wait(func() -> bool: return _dark(j, 0.1, 1.5))
		r_walk(_w(Vector3(0, ROOF, -29.2)))
		r_jump(_w(Vector3(0, ROOF, -29.25)), _w(Vector3(0, DECK, -31.0)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 3.0, -19.0)), Vector3(1.6, 1.0, 10.0), 30)
	return Vector3(0, DECK, -31.0)


## A steam jet (the level's laser): centre and size in local frame, turned by yaw.
func _steam(center: Vector3, size: Vector3, yaw: float, period: float, on: float, phase: float) -> FrontierSteam:
	var g := FrontierSteam.new()
	g.size = size
	g.period = period
	g.on_fraction = on
	g.phase = phase
	g.rotation_degrees.y = yaw
	g.position = _w(center)
	add_child(g)
	return g


# ---- stage 8: Tank Train - catwalks on the tanks, the steam rams ----------------------------------------

func _stage_8() -> Vector3:
	var tanks: Array[Vector2] = [Vector2(-5.8, -18.8), Vector2(-21.8, -34.8), Vector2(-37.8, -52.8)]
	var cols: Array[Color] = [TANK_BLACK, Color(0.5, 0.48, 0.44), TANK_BLACK]
	for i: int in tanks.size():
		var t: Vector2 = tanks[i]
		_car(t.x, t.y)
		deco.tank_dress(_wz(t.x), _wz(t.y), 3.0, 1.4, cols[i])
		# the tank itself is solid; only its catwalk is a landing
		var tank := StaticBody3D.new()
		tank.collision_layer = 1
		tank.collision_mask = 0
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.4
		cyl.height = t.x - t.y - 0.6
		var cs := CollisionShape3D.new()
		cs.shape = cyl
		cs.rotation.x = PI * 0.5
		tank.add_child(cs)
		tank.position = _w(Vector3(0, 3.0, (t.x + t.y) * 0.5))
		add_child(tank)
		_slab(Vector3(0, 4.55, (t.x + t.y) * 0.5), Vector3(0.8, 0.15, t.x - t.y - 1.2), Color(0.55, 0.42, 0.3), Color(0.25, 0.2, 0.16), 3)
		for sx: float in [-1.0, 1.0]:
			deco.box(_w(Vector3(sx * 0.55, 5.1, (t.x + t.y) * 0.5)), Vector3(0.05, 0.05, t.x - t.y - 2.0), Look.flat(Color(0.15, 0.14, 0.14), 0.5, 0.6))
	_slab(Vector3(0, 3.0, -5.3), Vector3(1.6, 0.25, 1.0), Color(0.55, 0.42, 0.3), Color(0.25, 0.2, 0.16), 3)
	_slab(Vector3(0, 4.55, -51.7), Vector3(3.0, 0.3, 4.2), Color(0.55, 0.42, 0.3), Color(0.25, 0.2, 0.16), 3)
	var p1: Piston = _ram(Vector3(1.2, 5.75, -28.0), 90.0, 0.0)
	var p2: Piston = _ram(Vector3(-1.2, 5.75, -45.5), -90.0, 0.5)
	_cp(Vector3(0, 4.55, -51.2))
	r_jump(_w(Vector3(0, DECK, -1.85)), _w(Vector3(0, 3.0, -5.3)))
	r_jump(_w(Vector3(0, 3.0, -5.6)), _w(Vector3(0, 4.55, -7.6)))
	r_walk(_w(Vector3(0, 4.55, -17.85)))
	r_jump(_w(Vector3(0, 4.55, -17.85)), _w(Vector3(0, 4.55, -23.2)))
	_wait(func() -> bool: return _ram_clear(p1, 0.25, 1.75), _w(Vector3(0, 4.55, -23.2)))
	r_walk(_w(Vector3(0, 4.55, -33.85)))
	r_jump(_w(Vector3(0, 4.55, -33.85)), _w(Vector3(0, 4.55, -39.2)))
	_wait(func() -> bool: return _ram_clear(p2, 0.3, 1.9), _w(Vector3(0, 4.55, -39.2)))
	r_walk(_w(Vector3(0, 4.55, -51.2)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 6.0, -28.0)), Vector3(3.0, 2.0, 22.0), 40)
	FrontierFx.cinders(self, _w(Vector3(0, 8.0, -28.0)), Vector3(4.0, 2.0, 20.0), 30)
	return Vector3(0, 4.55, -51.2)


## A steam ram on its strut beside a catwalk, punching across it (yaw 90 punches toward -X).
func _ram(top: Vector3, yaw: float, phase: float, stroke: float = 2.2) -> Piston:
	var p: Piston = kit.piston(_w(top), Vector3(1.2, 1.2, 1.2), yaw, stroke, 4.0, phase, 12.0)
	var brass: StandardMaterial3D = Look.flat(Color(0.9, 0.68, 0.3), 0.3, 0.85, 0.15)
	p.add_child(Look.box(Vector3(1.3, 0.12, 0.12), brass, Vector3(0, 0.3, -0.72)))
	var side: float = signf(top.x)
	# the housing's strut down to the car frame
	var hx: float = top.x + side * (0.6 + stroke + 0.45)
	kit.pipe(_w(Vector3(hx, top.y - 1.0, top.z)), _w(Vector3(side * 1.9, 1.3, top.z)), 0.14, Color(0.15, 0.14, 0.14))
	FrontierFx.steam_leak(self, _w(Vector3(hx, top.y, top.z)), Vector3(side, 0.6, 0), 10)
	return p


# ---- stage 9: Ore Line - ride the mine carts [shortcut: the greased plank] -------------------------------

func _stage_9() -> Vector3:
	_flatcar(-6.0, -17.0)
	_flatcar(-26.6, -40.6)
	_flatcar(-49.2, -61.2)
	var cart1: FrontierCart = _cart(Vector3(0, 2.3, -15.4), -12.6, 9.0, 0.0)
	var cart2: FrontierCart = _cart(Vector3(0, 2.3, -38.8), -11.4, 8.4, 0.5)
	# the narrow-gauge rails the carts run on, across the long couplings
	var rail: StandardMaterial3D = Look.flat(Color(0.45, 0.42, 0.4), 0.3, 0.9)
	for seg: Vector2 in [Vector2(-13.0, -30.0), Vector2(-36.4, -52.0)]:
		for sx: float in [-0.55, 0.55]:
			deco.box(_w(Vector3(sx, DECK + 0.07, (seg.x + seg.y) * 0.5)), Vector3(0.1, 0.14, seg.x - seg.y), rail)
		# trestle-like timber supports under the rails across the gap
		deco.box(_w(Vector3(0, DECK - 0.1, (seg.x + seg.y) * 0.5)), Vector3(1.6, 0.16, seg.x - seg.y), Look.flat(Color(0.3, 0.22, 0.15), 0.9))
	# SHORTCUT: a greased plank down the left of the second ore car - a boost into a leap over the gap
	kit.boost(_w(Vector3(-1.25, DECK, -33.6)), Vector3(1.3, 0.3, 9.0), 0.0, 17.0)
	_cp(Vector3(0, DECK, -58.6))
	r_jump(_w(Vector3(0, 4.55, -2.25)), _w(Vector3(0, DECK, -7.4)))
	r_walk(_w(Vector3(0, DECK, -13.3)))
	var home1: Vector3 = _w(Vector3(0, 2.3, -15.4)) - Vector3(0, 0.4, 0)
	r_wait(cart1, home1, 0.3)
	r_jump_onto(_w(Vector3(0, DECK, -13.5)), cart1, Vector3(0, 0.45, 0))
	r_jump_from_ride(cart1, home1 + Vector3(0, 0, -12.6), 0.3, _w(Vector3(0, DECK, -31.2)))
	if route_variant == 2:
		r_walk(_w(Vector3(-1.25, DECK, -31.0)))
		r_jump(_w(Vector3(-1.25, DECK, -40.25)), _w(Vector3(-0.6, DECK, -52.4)))
		route[route.size() - 1]["speed"] = 17.0
	else:
		r_walk(_w(Vector3(0, DECK, -36.7)))
		var home2: Vector3 = _w(Vector3(0, 2.3, -38.8)) - Vector3(0, 0.4, 0)
		r_wait(cart2, home2, 0.3)
		r_jump_onto(_w(Vector3(0, DECK, -36.9)), cart2, Vector3(0, 0.45, 0))
		r_jump_from_ride(cart2, home2 + Vector3(0, 0, -11.4), 0.3, _w(Vector3(0, DECK, -53.0)))
	r_walk(_w(Vector3(0, DECK, -58.6)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 3.0, -30.0)), Vector3(4.0, 2.0, 26.0), 50)
	return Vector3(0, DECK, -58.6)


func _cart(top: Vector3, travel: float, period: float, phase: float) -> FrontierCart:
	var c := FrontierCart.new()
	c.size = Vector3(2.2, 0.8, 2.4)
	c.points = [Vector3.ZERO, Vector3(0, 0, travel)]
	c.period = period
	c.phase = phase
	c.dwell = 0.14
	c.position = _w(top) - Vector3(0, 0.4, 0)
	add_child(c)
	return c


# ---- stage 10: Low Bridge - duck into the coal pits under the tall boards ---------------------------------

func _stage_10() -> Vector3:
	var gons: Array[Vector2] = [Vector2(-5.6, -19.6), Vector2(-23.8, -37.8), Vector2(-42.0, -56.0)]
	for g: Vector2 in gons:
		_gondola(g.x, g.y)
		# coal heaps fore and aft, a pit between them
		_slab(Vector3(0, 3.3, g.x - 2.25), Vector3(3.0, 1.8, 3.5), COAL.lightened(0.15), COAL, 3)
		_slab(Vector3(0, 3.3, g.y + 2.25), Vector3(3.0, 1.8, 3.5), COAL.lightened(0.15), COAL, 3)
	_flatcar(-59.6, -73.6)
	var sig: FrontierSignals = _signals(-56.5, -5.6, 5.5, 2.4, 60.0, -3.7, 0.0)
	sig.arm_depth = 0.4
	_cp(Vector3(0, DECK, -71.0))
	r_jump(_w(Vector3(0, DECK, -2.25)), _w(Vector3(0, 3.3, -6.8)))
	var feet: float = 3.3
	for i: int in gons.size():
		var g: Vector2 = gons[i]
		var pit: Vector3 = Vector3(0, DECK, (g.x + g.y) * 0.5)
		r_walk(_w(Vector3(0, 3.3, g.x - 3.6)))
		r_walk(_w(pit + Vector3(0, 0, 1.0)))
		# from the pit: up the front heap, over the coupling and into the next pit (or off to the flat)
		var z0: float = _wz(g.y + 4.0)
		var z1: float = _wz(gons[i + 1].x - 4.0) if i + 1 < gons.size() else _wz(-60.0)
		var s: FrontierSignals = sig
		var a: float = minf(z0, z1)
		var b: float = maxf(z0, z1)
		_wait(func() -> bool: return s.clear_for(a - 1.0, b + 1.0, feet, 0.0, 3.6), _w(pit))
		r_jump(_w(pit + Vector3(0, 0, -1.1)), _w(Vector3(0, 3.3, g.y + 3.0)))
		if i + 1 < gons.size():
			r_jump(_w(Vector3(0, 3.3, g.y + 0.35)), _w(Vector3(0, 3.3, gons[i + 1].x - 1.2)))
		else:
			r_jump(_w(Vector3(0, 3.3, g.y + 0.35)), _w(Vector3(0, DECK, -61.2)))
	r_walk(_w(Vector3(0, DECK, -71.0)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 5.0, -30.0)), Vector3(4.0, 2.0, 24.0), 50)
	return Vector3(0, DECK, -71.0)


# ---- stage 11: Billboards - wall run zig-zag over two bare log cars -------------------------------------

func _stage_11() -> Vector3:
	_flatcar(-6.2, -22.2, false)
	_flatcar(-25.0, -37.5, false)
	_flatcar(-40.5, -56.5)
	kit.wallrun(_w(Vector3(2.35, 2.8, -14.5)), Vector3(14.0, 5.0, 0.5), 90.0)
	kit.wallrun(_w(Vector3(-2.35, 4.8, -26.0)), Vector3(16.0, 5.4, 0.5), 90.0)
	var post: StandardMaterial3D = Look.flat(Color(0.3, 0.22, 0.15), 0.9)
	for z: float in [-8.0, -14.5, -21.0]:
		deco.box(_w(Vector3(2.75, 2.6, z)), Vector3(0.24, 5.4, 0.24), post)
	for z2: float in [-18.6, -26.0, -33.4]:
		deco.box(_w(Vector3(-2.75, 4.4, z2)), Vector3(0.24, 7.0, 0.24), post)
	_cp(Vector3(0, DECK, -53.9))
	r_wallrun(_w(Vector3(0.4, DECK, -2.25)), _w(Vector3(1.95, 2.6, -8.6)), _w(Vector3(1.95, 2.8, -15.6)), _w(Vector3(-1.95, 4.4, -20.8)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.95, 4.4, -20.8)), _w(Vector3(-1.95, 4.4, -31.6)), _w(Vector3(0, DECK, -42.6)), true, true)
	r_walk(_w(Vector3(0, DECK, -53.9)))
	r_checkpoint()
	FrontierFx.scraps(self, _w(Vector3(0, 5.0, -28.0)), Vector3(4.0, 3.0, 16.0), 20)
	return Vector3(0, DECK, -53.9)


# ---- stage 12: THE TRESTLE GIVES WAY - outrun the collapse [shortcut: the lumber sign] -----------------------

var _collapse: FrontierCollapse


func _stage_12() -> Vector3:
	var col := FrontierCollapse.new()
	col.position = _w(Vector3(0, 0, -2.6))
	col.period = 15.0
	col.warn = 2.5
	col.wave_speed = 5.0
	var tops: Array[float] = [1.5, 2.3, 1.5, 2.6, 3.2, 2.2, 1.5]
	var z: float = -1.6
	var secs: Array[Vector3] = []
	for i: int in tops.size():
		var len: float = 4.4
		var c := Vector3(0, tops[i], z - len * 0.5)
		var body: AnimatableBody3D = col.add_section(c, Vector3(4.0, 0.6, len))
		_dress_section(body, len, tops[i])
		secs.append(Vector3(0, tops[i], _wz(-2.6) + c.z))
		z -= len + 2.6
	add_child(col)
	_collapse = col
	_paint_collapse(col)
	var v_rear: float = -2.6 + z + 2.6 - 1.4
	# beyond: a steel flat, solid
	_car(v_rear, v_rear - 14.0)
	_slab(Vector3(0, DECK, v_rear - 7.0), Vector3(4.0, 0.45, 14.0), Color(0.42, 0.4, 0.38), STEEL, 3)
	var cp_z: float = v_rear - 11.4
	# SHORTCUT: the lumber company's sign along the right of the middle flats - a wall run past three of them
	kit.wallrun(_w(Vector3(2.35, 4.4, -26.0)), Vector3(16.0, 5.6, 0.5), 90.0)
	for zz: float in [-18.4, -26.0, -33.6]:
		deco.box(_w(Vector3(2.75, 3.6, zz)), Vector3(0.24, 7.0, 0.24), Look.flat(Color(0.3, 0.22, 0.15), 0.9))
	_cp(Vector3(0, DECK, cp_z))
	var cc: FrontierCollapse = col
	_wait(func() -> bool: return cc.run_open(Game.course_time, -1.2))
	r_jump(_w(Vector3(0, DECK, -2.25)), Vector3(0, secs[0].y, secs[0].z + 0.8))
	var skip_from: int = 1 if route_variant == 2 else -1
	var i2: int = 0
	while i2 < secs.size() - 1:
		var a: Vector3 = secs[i2]
		var b: Vector3 = secs[i2 + 1]
		if i2 == skip_from:
			# off the second flat onto the sign, along it, and down onto the sixth flat
			r_wallrun(Vector3(0.2, a.y, a.z - 1.85), _w(Vector3(1.95, 4.4, -19.4)), _w(Vector3(1.95, 4.4, -30.0)), Vector3(0, secs[5].y, secs[5].z + 0.4))
			i2 = 5
			continue
		r_jump(Vector3(0, a.y, a.z - 1.85), Vector3(0, b.y, b.z + 0.6))
		i2 += 1
	var last: Vector3 = secs[secs.size() - 1]
	r_jump(Vector3(0, last.y, last.z - 1.85), _w(Vector3(0, DECK, v_rear - 1.2)))
	r_walk(_w(Vector3(0, DECK, cp_z)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 4.0, -24.0)), Vector3(4.0, 3.0, 20.0), 50)
	return Vector3(0, DECK, cp_z)


## Lumber on a collapsing flat: a frame under the deck and a few lashed timbers (they fall with it).
func _dress_section(body: AnimatableBody3D, len: float, _top: float) -> void:
	var iron: StandardMaterial3D = Look.flat(Color(0.14, 0.12, 0.11), 0.6, 0.4)
	body.add_child(Look.box(Vector3(3.0, 0.3, len - 0.4), iron, Vector3(0, -0.75, 0)))
	for sz: float in [-1.0, 1.0]:
		var w := Look.cylinder(0.42, 2.0, iron, Vector3(0, -1.1, sz * (len * 0.5 - 1.0)), -1.0, 12)
		w.rotation.z = PI * 0.5
		body.add_child(w)
	for sx: float in [-1.0, 1.0]:
		body.add_child(Look.box(Vector3(0.14, 0.9, 0.14), Look.flat(Color(0.3, 0.22, 0.15), 0.9), Vector3(sx * 1.92, 0.45, len * 0.3)))
		body.add_child(Look.box(Vector3(0.14, 0.9, 0.14), Look.flat(Color(0.3, 0.22, 0.15), 0.9), Vector3(sx * 1.92, 0.45, -len * 0.3)))


func _paint_collapse(col: FrontierCollapse) -> void:
	for c: Node in col.get_children():
		if c is AnimatableBody3D:
			_paint(c, LOG_TOP, Color(0.36, 0.25, 0.16), 3)


# ---- stage 13: Mail Car - mantle up, the mail-bag rams, the mail crane's sweep --------------------------

func _stage_13() -> Vector3:
	_boxcar(-6.4, -24.4, Color(0.22, 0.3, 0.42), true)
	var r1: Piston = _ram(Vector3(1.7, ROOF + 1.2, -12.0), 90.0, 0.0, 3.4)
	var r2: Piston = _ram(Vector3(1.7, ROOF + 1.2, -18.4), 90.0, 0.5, 3.4)
	_boxcar(-28.4, -44.4, BOX_BROWN)
	# the mail crane on the second car: a swinging crane arm sweeping the roof (hop it)
	var sw: Sweeper = kit.sweeper(_w(Vector3(-1.6, ROOF, -36.4)), 3.6, 1, 3.4, 0.0, 0.45)
	_cp(Vector3(0, ROOF, -41.8))
	r_mantle(_w(Vector3(0, DECK, -2.25)), _w(Vector3(0, ROOF, -7.6)))
	r_walk(_w(Vector3(0, ROOF, -9.0)))
	_wait(func() -> bool: return _ram_clear(r1, 0.2, 1.7), _w(Vector3(0, ROOF, -9.0)))
	r_walk(_w(Vector3(0, ROOF, -15.2)))
	_wait(func() -> bool: return _ram_clear(r2, 0.2, 1.7), _w(Vector3(0, ROOF, -15.2)))
	r_walk(_w(Vector3(0, ROOF, -23.9)))
	r_jump(_w(Vector3(0, ROOF, -24.05)), _w(Vector3(0.6, ROOF, -29.6)))
	route.append({"kind": "b_sweep", "to": _w(Vector3(0.6, ROOF, -41.4)), "sweeper": sw, "tol": 0.5})
	r_walk(_w(Vector3(0, ROOF, -41.8)))
	r_checkpoint()
	FrontierFx.scraps(self, _w(Vector3(0, 7.0, -24.0)), Vector3(4.0, 2.0, 18.0), 18)
	return Vector3(0, ROOF, -41.8)


# ---- stage 14: Cattle Run - the long fuse burning forward along the roofs ----------------------------------

func _stage_14() -> Vector3:
	_boxcar(-6.4, -21.4, STOCK)
	_boxcar(-25.6, -40.6, STOCK.darkened(0.15))
	_boxcar(-45.0, -60.0, STOCK)
	# slats on the stock cars' sides
	for zz: Vector2 in [Vector2(-6.4, -21.4), Vector2(-25.6, -40.6), Vector2(-45.0, -60.0)]:
		for sx: float in [-1.0, 1.0]:
			for k: int in 4:
				deco.box(_w(Vector3(sx * 2.04, 2.0 + float(k) * 0.65, (zz.x + zz.y) * 0.5)), Vector3(0.05, 0.12, zz.x - zz.y - 0.6), Look.flat(Color(0.1, 0.08, 0.06), 0.9))
	# the chain: a plunger behind the checkpoint and seven bundles along the roofs, the spark burning
	# forward at 4.5 m/s - each bundle blows as the spark reaches it
	var speed: float = 4.5
	var period: float = 18.0
	var plunger: Vector3 = _w(Vector3(1.7, ROOF, 8.0))
	_plunger(plunger)
	var zs: Array[float] = [-9.0, -15.0, -20.0, -29.0, -35.0, -48.5, -53.5]
	var t_lit: float = 0.0
	var prev: Vector3 = plunger
	var chain: Array[FrontierDynamite] = []
	for i: int in zs.size():
		var at: Vector3 = _w(Vector3(0, ROOF, zs[i]))
		var pts := PackedVector3Array()
		pts.append(prev - at + Vector3(0, 0.03, 0))
		if i == 0:
			pts.append(Vector3(1.7, 0.03, 0))
		else:
			pts.append(Vector3(1.4, 0.03, (prev.z - at.z) * 0.5))
			pts.append(Vector3(1.4, 0.03, 0))
		pts.append(Vector3(0.25, 0.03, 0))
		var flen: float = 0.0
		for k: int in pts.size() - 1:
			flen += pts[k].distance_to(pts[k + 1])
		var burn: float = flen / speed
		var d: FrontierDynamite = _dynamite(at, pts, period, fposmod(-t_lit / period, 1.0), burn)
		d.regrow = 1.5
		chain.append(d)
		t_lit += burn
		prev = at
	_cp(Vector3(0, ROOF, -57.4))
	var first: FrontierDynamite = chain[0]
	_wait(func() -> bool: return first.is_lit_at(Game.course_time) and first.burn_at(Game.course_time) < 0.12)
	r_jump(_w(Vector3(0, ROOF, -2.25)), _w(Vector3(0, ROOF, -7.4)))
	r_walk(_w(Vector3(0, ROOF, -21.0)))
	r_jump(_w(Vector3(0, ROOF, -21.05)), _w(Vector3(0, ROOF, -26.6)))
	r_walk(_w(Vector3(0, ROOF, -40.2)))
	r_jump(_w(Vector3(0, ROOF, -40.25)), _w(Vector3(0, ROOF, -46.0)))
	r_walk(_w(Vector3(0, ROOF, -57.4)))
	r_checkpoint()
	FrontierFx.dust(self, _w(Vector3(0, 7.0, -30.0)), Vector3(4.0, 2.0, 26.0), 40)
	FrontierFx.scraps(self, _w(Vector3(0, 7.0, -30.0)), Vector3(4.0, 2.0, 26.0), 20)
	return Vector3(0, ROOF, -57.4)


# ---- stage 15: Tender - the water tank's steam jets, onto the coal [shortcut: the tender's side] ----------

var _tender_front: float = 0.0


func _stage_15() -> Vector3:
	_car(-6.4, -18.4)
	_slab(Vector3(0, 4.6, -9.2), Vector3(3.6, 3.5, 5.6), Color(0.2, 0.2, 0.21), TANK_BLACK, 3)
	_slab(Vector3(0, 4.6, -15.2), Vector3(3.6, 3.5, 6.4), COAL.lightened(0.12), TANK_BLACK, 3)
	var j1: FrontierSteam = _steam(Vector3(0, 4.6 + 0.9, -8.0), Vector3(3.8, 1.8, 0.3), 180.0, 2.4, 0.34, 0.0)
	var j2: FrontierSteam = _steam(Vector3(0, 4.6 + 0.9, -10.6), Vector3(3.8, 1.8, 0.3), 0.0, 2.4, 0.34, 0.9)
	deco.lantern(_w(Vector3(0, 5.0, -6.2)), Color(1.0, 0.7, 0.35))
	# SHORTCUT: a wall run along the tender's right side, past both jets, kicking back onto the coal
	kit.wallrun(_w(Vector3(2.15, 5.5, -11.0)), Vector3(10.0, 7.6, 0.4), 90.0)
	_tender_front = _wz(-18.4)
	_cp(Vector3(0, 4.6, -15.8))
	if route_variant == 2:
		r_wallrun(_w(Vector3(0.6, ROOF, -2.25)), _w(Vector3(1.8, 4.9, -7.2)), _w(Vector3(1.8, 4.9, -9.4)), _w(Vector3(0, 4.6, -15.6)))
	else:
		r_jump(_w(Vector3(0, ROOF, -2.25)), _w(Vector3(0, 4.6, -6.8)))
		_wait(func() -> bool: return _dark(j1, 0.05, 1.45) and _dark(j2, 0.3, 1.75), _w(Vector3(0, 4.6, -6.8)))
	r_walk(_w(Vector3(0, 4.6, -15.8)))
	r_checkpoint()
	return Vector3(0, 4.6, -15.8)


# ---- stage 16: Running Board - along the locomotive's side ---------------------------------------------

## The cab's rear face and the length of the cab / boiler (world z), set in stage 16.
var _cab_rear: float = 0.0
const CAB_LEN: float = 3.4
const BOILER_LEN: float = 11.4
const BOILER_Y: float = 3.2
const BOILER_R: float = 1.45
const CAB_TOP: float = 7.2


func _stage_16() -> Vector3:
	# the locomotive: cab (a tall wall from the coal), boiler, running boards, the front deck
	_cab_rear = _wz(-4.6)
	_car(-4.6, -22.4, false)
	var cab_f: float = -4.6 - CAB_LEN
	var boiler_f: float = cab_f - BOILER_LEN
	_solid(Vector3(0, (CAB_TOP + 2.4) * 0.5, -4.6 - CAB_LEN * 0.5), Vector3(3.0, CAB_TOP - 2.4, CAB_LEN), Color(0.6, 0.1, 0.07),
			FrontierDecor.wood(ROOF_TOP, Color(0.6, 0.1, 0.07), TRIM, Vector3(1.5, (CAB_TOP - 2.4) * 0.5, CAB_LEN * 0.5), 2))
	_slab(Vector3(0, CAB_TOP, -4.6 - CAB_LEN * 0.5), Vector3(3.4, 0.25, CAB_LEN + 0.4), Color(0.16, 0.15, 0.15), Color(0.1, 0.1, 0.1), 3)
	var boiler := StaticBody3D.new()
	boiler.collision_layer = 1
	boiler.collision_mask = 0
	var cyl := CylinderShape3D.new()
	cyl.radius = BOILER_R
	cyl.height = BOILER_LEN
	var bcs := CollisionShape3D.new()
	bcs.shape = cyl
	bcs.rotation.x = PI * 0.5
	boiler.add_child(bcs)
	boiler.position = _w(Vector3(0, BOILER_Y, cab_f - BOILER_LEN * 0.5))
	add_child(boiler)
	for sx: float in [-1.0, 1.0]:
		_slab(Vector3(sx * 1.9, 2.4, (-3.4 + boiler_f) * 0.5), Vector3(0.7, 0.2, -3.4 - boiler_f), Color(0.3, 0.28, 0.27), Color(0.12, 0.12, 0.12), 3)
	_slab(Vector3(0, 1.7, boiler_f - 1.5), Vector3(3.6, 0.4, 3.0), Color(0.3, 0.28, 0.27), Color(0.55, 0.1, 0.07), 3)
	# the frame under it all (solid down to the rails, so nothing slips under the boiler)
	_solid(Vector3(0, 1.4, (cab_f + boiler_f) * 0.5), Vector3(1.4, 1.2, BOILER_LEN), Color(0.08, 0.08, 0.09))
	var cab_fw: float = _wz(cab_f)
	var spots: Dictionary = {"stack": _wz(boiler_f) + 0.9, "bell": cab_fw - 7.0, "sand": cab_fw - 5.2, "dome": cab_fw - 2.0}
	var info: Dictionary = deco.locomotive(_wz(-4.6), CAB_LEN, BOILER_LEN, BOILER_Y, BOILER_R, CAB_TOP, spots)
	_whistle_pos = info["whistle"]
	_drv_r = float(info["drv_r"])
	_rod_z = float(info["drivers_z"])
	_rods = deco.side_rods(_rod_z, 2.15, _drv_r)
	FrontierFx.smoke_plume(self, info["stack"], 70)
	FrontierFx.cinders(self, (info["stack"] as Vector3) + Vector3(0, 2.0, 12.0), Vector3(3.0, 3.0, 14.0), 50)
	for cy: Vector3 in info["cylinders"]:
		FrontierFx.steam_leak(self, cy, Vector3(signf(cy.x), -0.2, 0.3), 14)
	# the hazards along the left running board
	var j1: FrontierSteam = _steam(Vector3(-1.9, 3.3, -10.6), Vector3(1.6, 1.8, 0.3), 180.0, 2.6, 0.4, 0.0)
	var pump: Piston = kit.piston(_w(Vector3(-0.85, 3.6, -13.4)), Vector3(1.0, 1.2, 1.0), 90.0, 1.4, 4.0, 0.35, 12.0)
	var air: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.22), 0.4, 0.7)
	deco.cyl_x(_w(Vector3(-0.9, 3.0, -13.4)), 0.55, 0.8, air)
	var j2: FrontierSteam = _steam(Vector3(-1.9, 3.3, -16.2), Vector3(1.6, 1.8, 0.3), 180.0, 2.6, 0.4, 0.5)
	_cp(Vector3(0, 1.7, boiler_f - 1.6), 180.0)
	r_jump(_w(Vector3(-0.9, 4.6, -2.25)), _w(Vector3(-1.9, 2.4, -6.0)))
	r_walk(_w(Vector3(-1.9, 2.4, -9.2)))
	_wait(func() -> bool: return _dark(j1, 0.0, 1.3), _w(Vector3(-1.9, 2.4, -9.2)))
	r_walk(_w(Vector3(-1.9, 2.4, -12.0)))
	_wait(func() -> bool: return _ram_clear(pump, 0.2, 1.6), _w(Vector3(-1.9, 2.4, -12.0)))
	r_walk(_w(Vector3(-1.9, 2.4, -14.8)))
	_wait(func() -> bool: return _dark(j2, 0.0, 1.3), _w(Vector3(-1.9, 2.4, -14.8)))
	r_walk(_w(Vector3(-1.9, 2.4, boiler_f + 0.4)))
	r_walk(_w(Vector3(-0.6, 1.7, boiler_f - 1.0)))
	r_walk(_w(Vector3(0, 1.7, boiler_f - 1.6)))
	r_checkpoint()
	return Vector3(0, 1.7, boiler_f - 1.6)


# ---- stage 17: Whistle Stop - up the smokebox, back along the boiler to the cab roof ---------------------

func _stage_17() -> void:
	# (local origin: the front deck checkpoint; the boiler front is 1.6 behind us, +Z)
	var zf: float = 1.6
	var cab_f: float = _cab_rear - CAB_LEN - _oz
	# the smokebox top: a mantle block round the stack's foot
	var sb: LedgeBlock = kit.ledge(_w(Vector3(0, 4.7, zf + 1.5)), Vector3(3.0, 3.0, 3.0))
	_paint(sb, Color(0.2, 0.2, 0.21), Color(0.08, 0.08, 0.09), 3)
	# the stack is solid (walk round it; its flare is above your head)
	var stack := StaticBody3D.new()
	stack.collision_layer = 1
	stack.collision_mask = 0
	var sc := CylinderShape3D.new()
	sc.radius = 0.6
	sc.height = 4.0
	var scs := CollisionShape3D.new()
	scs.shape = sc
	stack.add_child(scs)
	stack.position = _w(Vector3(0, 6.7, zf + 0.9))
	add_child(stack)
	# the boiler-top walkway, the sand dome (a hop), the steam dome (the step to the cab)
	_slab(Vector3(0, 4.7, (zf + 3.0 + cab_f) * 0.5), Vector3(0.9, 0.15, cab_f - zf - 3.0), Color(0.3, 0.28, 0.27), Color(0.1, 0.1, 0.1), 3)
	var bell_z: float = cab_f - 7.0
	var sand_z: float = cab_f - 5.2
	var valve_z: float = cab_f - 3.6
	var dome_z: float = cab_f - 2.0
	_slab(Vector3(0, 5.35, sand_z), Vector3(1.2, 0.6, 1.3), Color(0.95, 0.72, 0.32), Color(0.8, 0.58, 0.25), 3)
	_slab(Vector3(0, 5.6, dome_z), Vector3(1.4, 0.85, 1.6), Color(0.95, 0.72, 0.32), Color(0.8, 0.58, 0.25), 3)
	# the bell swinging across the walkway on its yoke (it knocks you off)
	var bell: Pendulum = kit.pendulum(_w(Vector3(0, 7.9, bell_z)), 2.4, 2.0, 0.0, 0.0, 75.0)
	_dress_bell(bell)
	for sx: float in [-1.0, 1.0]:
		deco.box(_w(Vector3(sx * 1.55, 6.4, bell_z)), Vector3(0.2, 3.0, 0.2), Look.flat(Color(0.12, 0.12, 0.12), 0.5, 0.6))
	deco.box(_w(Vector3(0, 8.0, bell_z)), Vector3(3.3, 0.2, 0.2), Look.flat(Color(0.12, 0.12, 0.12), 0.5, 0.6))
	# the safety valve blowing off across the walkway
	var jet: FrontierSteam = _steam(Vector3(0, 5.65, valve_z), Vector3(2.6, 1.8, 0.3), 0.0, 2.8, 0.36, 0.25)
	deco.box(_w(Vector3(-1.5, 5.0, valve_z)), Vector3(0.3, 0.6, 0.3), Look.flat(Color(0.95, 0.72, 0.32), 0.3, 0.8))
	# the finish on the cab roof
	_finish_pos = _w(Vector3(0, CAB_TOP, cab_f + CAB_LEN * 0.55))
	kit.finish(_finish_pos, 180.0)
	r_mantle(_w(Vector3(1.1, 1.7, zf - 0.75)), _w(Vector3(1.1, 4.7, zf + 1.0)))
	r_walk(_w(Vector3(1.1, 4.7, zf + 2.2)))
	r_walk(_w(Vector3(0, 4.7, zf + 2.6)))
	var b: Pendulum = bell
	_wait(func() -> bool: return _bell_clear(b, 0.05, 0.6), _w(Vector3(0, 4.7, zf + 2.6)))
	r_walk(_w(Vector3(0, 4.7, sand_z - 1.1)))
	r_jump(_w(Vector3(0, 4.7, sand_z - 1.0)), _w(Vector3(0, 5.35, sand_z + 0.1)))
	var j: FrontierSteam = jet
	_wait(func() -> bool: return _dark(j, 0.05, 1.5), _w(Vector3(0, 5.35, sand_z + 0.1)))
	r_jump(_w(Vector3(0, 5.35, sand_z + 0.3)), _w(Vector3(0, 5.6, dome_z - 0.2)))
	r_jump(_w(Vector3(0, 5.6, dome_z + 0.45)), _w(Vector3(0, CAB_TOP, cab_f + 1.2)))
	r_walk(_finish_pos + Vector3(0, 0, 0.6))
	FrontierFx.cinders(self, _w(Vector3(0, 8.0, -4.0)), Vector3(3.0, 3.0, 8.0), 30)


## The bell's head stays out to the side (clear of the walkway) over [now + a, now + b].
static func _bell_clear(p: Pendulum, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if absf(sin(p.angle_at(Game.course_time + s))) * p.length < 1.6:
			return false
		s += 0.03
	return true


## Swap the pendulum's hammer for a brass bell.
func _dress_bell(p: Pendulum) -> void:
	var arm := p.get_child(0) as Node3D
	(arm.get_child(0) as Node3D).visible = false
	(arm.get_child(1) as Node3D).visible = false
	var brass: StandardMaterial3D = Look.flat(Color(0.95, 0.74, 0.32), 0.25, 0.9, 0.2)
	arm.add_child(Look.cylinder(0.08, p.length, Look.flat(Color(0.12, 0.12, 0.12), 0.5, 0.6), Vector3(0, -p.length * 0.5, 0), -1.0, 8))
	arm.add_child(Look.cylinder(0.45, 1.1, brass, Vector3(0, -p.length + 0.1, 0), 1.0, 20))
	arm.add_child(Look.sphere(0.2, brass, Vector3(0, -p.length - 0.55, 0)))


# ---- couplers, trestle, canyon ----------------------------------------------------------------------------

func _couplers() -> void:
	var cars: Array[Vector2] = _cars.duplicate()
	cars.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	for i: int in cars.size() - 1:
		var front: float = cars[i].y
		var next_rear: float = cars[i + 1].x
		if front - next_rear > 0.1 and front - next_rear < 14.0:
			deco.coupler(front, next_rear)


func _surroundings() -> void:
	var z_back: float = -INF
	var z_front: float = INF
	for c: Vector2 in _cars:
		z_back = maxf(z_back, c.x)
		z_front = minf(z_front, c.y)
	var mid: float = (z_back + z_front) * 0.5
	var half: float = (z_back - z_front) * 0.5
	for s: FrontierSignals in _signal_lines:
		s.z_front = z_front - 110.0
		s.z_back = z_back + 110.0
		add_child(s)
	# under the wheels: anything that falls between or off the cars is gone
	var k := KillZone.new()
	k.show_mesh = false
	k.size = Vector3(9.0, 1.6, z_back - z_front + 120.0)
	k.position = Vector3(0, 0.2, mid)
	add_child(k)
	deco.trestle(z_front - 140.0, z_back + 140.0)
	deco.telegraph(z_front - 160.0, z_back + 160.0, -5.4)
	deco.canyon(mid, half + 200.0)
	# distant water towers and a windmill on the rims, sliding by
	var rims := FrontierScroll.make(420.0)
	add_child(rims)
	for i: int in int((half * 2.0 + 900.0) / 420.0) + 1:
		var zz: float = z_front - 450.0 + float(i) * 420.0
		deco.water_tower(rims, Vector3(-96.0, FrontierDecor.CANYON_FLOOR + 68.0, zz + 60.0), 1.6)
		deco.water_tower(rims, Vector3(88.0, FrontierDecor.CANYON_FLOOR, zz + 260.0), 1.3)
	# ambient life all along the train: dust in the low sun, scraps blowing back, veils of dust far below
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3(0, DECK, 0)
		var c2: Vector3 = (here + prev) * 0.5 + Vector3(0, 3.5, 0)
		var ext := Vector3(5.0, 3.5, absf(here.z - prev.z) * 0.5 + 6.0)
		FrontierFx.dust(self, c2, ext, 40)
		FrontierFx.scraps(self, c2 + Vector3(0, 1.0, 0), ext, 12)
		if i % 2 == 0:
			FrontierFx.veils(self, Vector3(0, FrontierDecor.CANYON_FLOOR + 12.0, c2.z), Vector3(60.0, 6.0, ext.z + 20.0), 8)
	# sparks off the wheels of every third car
	for i: int in _cars.size():
		if i % 3 == 1:
			var c: Vector2 = _cars[i]
			FrontierFx.wheel_sparks(self, Vector3(0, 0.15, c.y + 2.4), 12)


# ---- environment ------------------------------------------------------------------------------------------

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
	_env.sky = FrontierSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.95, 0.7, 0.55)
	_env.ambient_light_energy = 0.62
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.95, 0.62, 0.42)
	_env.fog_density = 0.0016
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.12
	_env.fog_sun_scatter = 0.35
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.2
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.15
	_env.adjustment_contrast = 1.06
	# a low, hot sun ahead and to the left, raking long shadows across the cars
	_sun.light_color = Color(1.0, 0.66, 0.4)
	_sun.light_energy = 2.2
	_sun.rotation_degrees = Vector3(-11, 228, 0)
	_sun.shadow_blur = 1.4
	_sun.directional_shadow_max_distance = 160.0
	# the fill: dusky violet sky light from the other side
	_fill.light_color = Color(0.62, 0.55, 0.9)
	_fill.light_energy = 0.42
	_fill.rotation_degrees = Vector3(-35, 48, 0)


# ---- live effects -------------------------------------------------------------------------------------------



func _process(dt: float) -> void:
	var t: float = Game.course_time
	var travelled: float = t * FrontierScroll.SPEED
	for d: Dictionary in deco.scroll_mats:
		var period: float = float(d["period"])
		var v: float = travelled if period <= 0.0 else fposmod(travelled, period)
		(d["mat"] as ShaderMaterial).set_shader_parameter("scroll", v)
	# the wheels turn with the scenery, the side rods ride round on the drivers
	for ws: Node3D in deco.spinners:
		ws.rotation.x = -travelled / float(ws.get_meta("r"))
	var ang: float = -travelled / _drv_r
	for rod: Node3D in _rods:
		var ph: float = ang + (0.0 if float(rod.get_meta("side")) < 0.0 else PI * 0.5)
		rod.position = Vector3(rod.position.x, _drv_r + sin(ph) * _drv_r * 0.45, _rod_z + 2.15 + cos(ph) * _drv_r * 0.45)
	if player == null:
		return
	for e: Dictionary in _arrivals:
		e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
		if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
			e["cool"] = 3.0
			for p: GPUParticles3D in e["p"]:
				p.restart()


## The finish: the whistle shrieks and steams, fireworks of gold over the cab, coins everywhere.
func _finish_sequence() -> void:
	var steam: GPUParticles3D = FrontierFx.whistle_steam(60)
	steam.position = _whistle_pos
	add_child(steam)
	steam.restart()
	# SOUND: the locomotive's whistle, long and loud
	WorldAudio.at(self, "frontier_whistle", _whistle_pos, 1.0, 150.0, 0.0)
	var cols: Array[Color] = [Color(2.6, 1.9, 0.6), Color(2.6, 0.7, 0.4), Color(2.4, 2.2, 1.6)]
	for i: int in 5:
		var fw: GPUParticles3D = FrontierFx.firework(cols[i % cols.size()], 80)
		fw.position = _finish_pos + Vector3(-8.0 + 4.0 * float(i), 12.0 + float(i % 2) * 4.0, -6.0)
		add_child(fw)
		fw.restart()
	var coins: GPUParticles3D = FrontierFx.loot(2.5, 120)
	coins.position = _finish_pos + Vector3(0, 0.8, 0)
	add_child(coins)
	coins.restart()
	# SOUND: fireworks over the cab
	WorldAudio.at(self, "frontier_fireworks", _finish_pos + Vector3(0, 12.0, -6.0), 1.0, 120.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.5)
	flash.light_energy = 6.0
	flash.omni_range = 24.0
	flash.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.4)
	await get_tree().create_timer(0.9).timeout
