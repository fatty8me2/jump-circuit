extends LevelBase
## 25. TOYBOX TUMBLE - the MEDIUM tier of the big update (campaign index 5). A giant kid's bedroom in
## the afternoon sun: a play rug with roads printed on it, alphabet blocks, bricks, crayons, tin cars,
## a train set, a dollhouse, a bed, a night-light - and, standing against the far wall, the great
## bookshelf with the toy rocket on its top. Everything is toy-sized for you: platforms are painted
## blocks, rides are tin cars. Eighteen stages, seventeen checkpoints; the hardest main-path jump is
## 82-86% of max reach onto landings of 1.4 m and more, so it is a friendly, playful second taste of
## the game rather than a test.
##
##  1 ABC Steps          three lettered blocks and a crayon beam, MANTLE up the toy chest
##  2 Wind-Up Run        two tin cars shuttle across the rug: hop on whichever is waiting and ride
##  3 Xylophone Bridge   five xylophone KEYS, each one rings and bounces you on to the next
##  4 Tower Bridge       BRANCH: the block TOWER topples across the gap | WALL RUN the bed rail, MANTLE
##                       [shortcut: a hidden stepping block in the middle of the gap]
##  5 Crayon Beams       two crayon beams under a toy LASER pointer
##  6 Spinning Tops      ride two big tops and leap between them [shortcut: skip the second top]
##  7 Jack Shelf         a JACK-IN-THE-BOX throws you onto the dollhouse floor, MANTLE the roof
##  8 Glove Alley        BRANCH: the boxing-glove PISTONS over the beam | the cardboard-tube PORTAL
##  9 Train Set          ride the train, then WALL RUN the brick wall
## 10 Block Press        a giant dice slams the beam (CRUSHER), MANTLE the shelf [shortcut: hop the dice]
## 11 Teddy Terrace      BRANCH: jack-in-the-box up | xylophone keys [shortcut: a long leap over the bear]
## 12 Tumbling Towers    two towers that topple one after the other, a xylophone key between them
## 13 Seesaw Park        a SEESAW plank, a toy PORTAL [shortcut: the net swing]
## 14 Bedpost Chimney    WALL RUN up the bed post, MANTLE onto the pillow
## 15 Top Spin           three tops in a row [shortcut: the middle hop]
## 16 Toy Parade         BRANCH: the tin cars shuttle sideways | the block bridge
## 17 Shelf Foot         jack-in-the-box, the last LASER, the foot of the bookshelf
## 18 THE BOOKSHELF      SET PIECE: climb four shelves of books to the toy rocket on top
##
## Toybox mechanics (own scripts): ToyboxCar (wind-up cars you ride), ToyboxTower (toppling block
## towers), ToyboxJack (jack-in-the-box springs), ToyboxKey (xylophone keys), ToyboxTell (toy warning
## lamp). Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line +
## every shortcut. Every wait the bot makes holds for 1.5 s more.

const RED := Color(0.93, 0.27, 0.25)
const BLUE := Color(0.2, 0.5, 0.93)
const YELLOW := Color(1.0, 0.8, 0.15)
const GREEN := Color(0.25, 0.75, 0.4)
const ORANGE := Color(1.0, 0.55, 0.15)
const PURPLE := Color(0.62, 0.4, 0.88)
const CREAM := Color(1.0, 0.94, 0.8)
const PINK := Color(1.0, 0.55, 0.75)

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 0

const KEY_STRENGTH: float = 16.0
const KEY_PITCH: float = 55.0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: ToyboxDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable surface (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float}
var _floors: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "toybox"
	music_track = "toybox"
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


## A walkable block (local top centre `c`, sx across, sz along).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, keel: float = 0.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw)
	_floors.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": thick})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A small floating block (a landing 1.6 m across or more).
func _post(c: Vector3, sx: float = 1.8, sz: float = 1.8, style: String = "accent") -> Dictionary:
	return _blk(c, sx, sz, style, 0.6)


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	_floors.append({"top": _w(top), "size": _sz(Vector3(size.x, 0, size.z)), "drop": size.y})
	return {"c": top, "hx": size.x * 0.5, "hz": size.z * 0.5}


## Takeoff spot on `a`: on the line toward `toward`, `inset` metres inside the edge.
func _edge(a: Dictionary, toward: Vector3, inset: float = 0.35) -> Vector3:
	var c: Vector3 = a["c"]
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	var tx: float = INF if absf(d.x) < 0.001 else (float(a["hx"]) - inset) / absf(d.x)
	var tz: float = INF if absf(d.z) < 0.001 else (float(a["hz"]) - inset) / absf(d.z)
	return c + d * minf(tx, tz)


## Route a jump from the edge of `a` to the middle of `b` (+ offset). speed > 0 marks a momentum jump.
func _hop(a: Dictionary, b: Dictionary, off: Vector3 = Vector3.ZERO, hold: bool = true, speed: float = 0.0) -> void:
	var to: Vector3 = (b["c"] as Vector3) + off
	r_jump(_w(_edge(a, to)), _w(to), hold)
	if speed > 0.0:
		route[route.size() - 1]["speed"] = speed


## The validator's max reach (m) for a plain running jump that lands `dy` higher (test_m's measure).
func _reach(dy: float) -> float:
	var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, _tuning.jump_velocity, -_tuning.max_speed), dy)
	return absf(land.z)


## How far the near edge of a landing lies past the takeoff's front edge (less the 0.35 m inset) when
## the jump needs `pct` of max reach by test_m's measure (to 0.4 m past the near edge, scanned in
## 0.2 m steps: rounded up, so it needs `pct` to `pct` + 3%).
func _e(pct: float, dy: float) -> float:
	var m: float = pct * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	return float(k) * 0.2 - 0.03


## Local top centre of a landing `sz` deep straight ahead (-z) of `a`, placed so that the jump from
## 0.35 m inside a's front edge needs `pct` of max reach (see _e).
func _ahead(a: Dictionary, pct: float, dy: float, sz: float, dx: float = 0.0) -> Vector3:
	var ac: Vector3 = a["c"]
	var front: float = ac.z - float(a["hz"])
	return Vector3(ac.x + dx, ac.y + dy, front + 0.35 - _e(pct, dy) - sz * 0.5)


## The mirror image of _ahead: the z of the centre of a block `depth` deep whose front edge sits so that
## the jump from it onto a landing whose near edge is at z `near_z` (landing `dy` higher) needs `pct`.
func _behind(near_z: float, pct: float, dy: float, depth: float) -> float:
	return near_z - 0.35 + _e(pct, dy) + depth * 0.5


## Checkpoint slab facing the next stage's heading (_next_yaw).
func _cp(c: Vector3, size: float = 5.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "goal", 1.0)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var fx: Array[GPUParticles3D] = ToyboxFx.cp_burst(palette_col(_cp_world.size()))
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: toybox_checkpoint - a music-box flourish: a short run of bright bell notes
			WorldAudio.at(self, "toybox_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in (_cp_bursts[which] as Array):
				p.restart()
				p.emitting = true)
	return d


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

## Stand still until test() is true (a wait: the 1.0 s human-pause check applies after it).
func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Run to `from`, jump, and fly (position-hold steering) to `to`.
func _fly(from: Vector3, to: Vector3, gain: float = 1.6, damp: float = 0.45) -> void:
	route.append({"kind": "desert_fly", "jump_from": from, "to": to, "gain": gain, "damp": damp})


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


static func _ram_clear(p: Piston, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if p.extension_at(Game.course_time + s) > 0.02:
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


## The jack's cushion stays down (calm to step onto) over [now + a, now + b].
static func _resting(j: ToyboxJack, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not j.is_resting_at(Game.course_time + s):
			return false
		s += 0.05
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	deco = ToyboxDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	var last: int = stages.size() if DEV_LAST <= 0 else mini(DEV_LAST, stages.size())
	var starts: Array[int] = []
	var origins: Array[Vector3] = []
	_frame(Vector3.ZERO, yaws[0])
	for i: int in last:
		_next_yaw = yaws[i + 1]
		starts.append(route.size())
		origins.append(_o)
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	starts.append(route.size())
	origins.append(_o)
	if last == stages.size() and last >= 17:
		_stage_18()
	else:
		# (dev) the finish right after the last stage built
		var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
		var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "goal", 1.0)
		kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
		_finish_pos = _w(Vector3(0, 0, -9.5))
		_hop(cp0, fin)
		r_walk(_w(Vector3(0, 0, -9.8)))
	_surroundings()
	_toy_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


# ---- stage 1: ABC Steps - lettered blocks, a crayon beam, mantle the toy chest ----------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(12, 2, 12), "main", 0.0, _yaw)
	_floors.append({"top": _w(Vector3.ZERO), "size": Vector3(12, 0, 12), "drop": 2.0})
	var start: Dictionary = _area(Vector3(0, 0, 0), 6.0, 6.0)
	var p1: Dictionary = _post(_ahead(start, 0.74, 0.0, 2.0), 2.0, 2.0)
	var p2: Dictionary = _post(_ahead(p1, 0.76, 0.6, 1.8, -0.5), 1.8, 1.8)
	var p3: Dictionary = _post(_ahead(p2, 0.78, 0.6, 1.8, 0.5), 1.8, 1.8)
	var beam: Dictionary = _blk(_ahead(p3, 0.78, 0.0, 3.2, -0.5), 1.6, 3.2, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var front: float = bc.z - 1.6
	# the toy chest: a mantle wall across a 1.6 m gap, its top 3.3 m above the beam
	var chest_top := Vector3(bc.x, bc.y + 3.3, front - 1.6 - 0.8)
	var chest: Dictionary = _ledge(chest_top, Vector3(3.0, 9.0, 1.6))
	var cp: Dictionary = _cp(_ahead(chest, 0.80, 0.0, 5.0, -bc.x))
	_hop(start, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, beam, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(bc.x, bc.y, front + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, front + 0.35)), _w(chest_top + Vector3(0, 0, 0.2)))
	_hop(chest, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Wind-Up Run - two tin cars shuttle across the rug -------------------------------------

## A tin car whose parked pose at the near end has its deck top at local `top` (world: the node sits
## at the deck's centre); it shuttles `travel` (local offset) and back.
func _car(top: Vector3, travel: Vector3, period: float, phase: float, tint: Color, dwell: float = 0.36, length: float = 5.0) -> ToyboxCar:
	var car := ToyboxCar.new()
	car.size = Vector3(2.4, 0.5, length)
	car.points = [Vector3.ZERO, _d(travel)]
	car.period = period
	car.phase = phase
	car.dwell = dwell
	car.tint = tint
	car.heading_deg = _yaw
	car.position = _w(top) - Vector3(0, 0.25, 0)
	add_child(car)
	return car


## The bot's boarding of a pair of shuttle cars: wait for whichever one is parked at the near end,
## hop on, ride, and hop off at the far end. `froms` / `exits` / `poses` are one world point per car
## (where it takes off from, where it lands, the car's centre when parked at the far end).
func _ferry(cars: Array[ToyboxCar], froms: Array[Vector3], exits: Array[Vector3], poses: Array[Vector3], window: float = 3.4) -> void:
	var jump_step: Dictionary = {"kind": "jump", "from": froms[0], "to_node": cars[0], "to_local": Vector3(0, 0.25, 0), "to": froms[0], "hold": true}
	var ride_step: Dictionary = {"kind": "ride_jump", "node": cars[0], "point": poses[0], "radius": 0.6, "to": exits[0], "hold": true, "stand": Vector3.ZERO}
	route.append({"kind": "toybox_pick", "cars": cars, "window": window, "froms": froms, "exits": exits, "poses": poses, "jump": jump_step, "ride": ride_step})
	route.append(jump_step)
	route.append(ride_step)


func _stage_2() -> Vector3:
	var ride: float = 14.0
	var near_z: float = -2.5 - 0.8 - 2.5
	var far_z: float = near_z - ride - 2.5 - 0.8 - 2.5
	var cars: Array[ToyboxCar] = []
	cars.append(_car(Vector3(-1.9, 0, near_z), Vector3(0, 0, -ride), 16.0, 0.0, RED))
	cars.append(_car(Vector3(1.9, 0, near_z), Vector3(0, 0, -ride), 16.0, 0.5, BLUE))
	var far: Dictionary = _cp(Vector3(0, 0, far_z))
	var froms: Array[Vector3] = [_w(Vector3(-1.9, 0, -2.15)), _w(Vector3(1.9, 0, -2.15))]
	var exits: Array[Vector3] = [_w(Vector3(-1.9, 0, far_z + 1.0)), _w(Vector3(1.9, 0, far_z + 1.0))]
	var poses: Array[Vector3] = [_w(Vector3(-1.9, -0.25, near_z - ride)), _w(Vector3(1.9, -0.25, near_z - ride))]
	_ferry(cars, froms, exits, poses)
	r_checkpoint()
	return far["c"]


# ---- stage 3: Xylophone Bridge - five keys that ring and bounce you along --------------------------

func _key(c: Vector3, note: int, col: Color) -> ToyboxKey:
	var k := ToyboxKey.new()
	k.bar = Vector3(3.4, 0.4, 2.2)
	k.strength = KEY_STRENGTH
	k.pitch_deg = KEY_PITCH
	k.note = note
	k.color = col
	k.rotation.y = deg_to_rad(_yaw)
	k.position = _w(c)
	add_child(k)
	_floors.append({"top": _w(c), "size": _sz(Vector3(3.4, 0, 2.2)), "drop": 0.4, "key": true})
	return k


## Where a key at local `c` flings you down to height `y` (local).
func _key_landing(c: Vector3, y: float) -> Vector3:
	var p: float = deg_to_rad(KEY_PITCH)
	var v := Vector3(0, cos(p), -sin(p)) * KEY_STRENGTH
	return Ballistics.landing_point(_tuning, c + Vector3(0, 0.1, 0), v, y)


func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var cols: Array[Color] = [RED, ORANGE, YELLOW, GREEN, BLUE]
	var c: Vector3 = _ahead(cp0, 0.78, 0.0, 2.2)
	var keys: Array[Vector3] = []
	for i: int in 5:
		_key(c, i, cols[i])
		keys.append(c)
		var ny: float = c.y + 0.4
		var land: Vector3 = _key_landing(c, ny)
		c = Vector3(c.x, ny, land.z)
	# the last flight lands on the checkpoint slab
	var cp: Dictionary = _cp(c, 5.0)
	_hop(cp0, _area(keys[0], 1.7, 1.1))
	for i: int in 5:
		r_pad(_w(keys[i]), _w(keys[i + 1] if i < 4 else c))
	r_checkpoint()
	return cp["c"]


# ---- machine helpers --------------------------------------------------------------------------------

## Seconds until a piston next starts to punch (its ram is out from 0.45 of the cycle).
static func _until_punch(p: Piston, t: float) -> float:
	return fposmod(0.45 - fposmod(t / p.period + p.phase, 1.0), 1.0) * p.period


## Seconds until a press next slams (it falls at 0.5 of the cycle).
static func _until_slam(c: Crusher, t: float) -> float:
	return fposmod(0.50 - fposmod(t / c.period + c.phase, 1.0), 1.0) * c.period


## A toy warning lamp at local `at` that counts down `left(course_time)` (seconds to the hazard).
func _tell(at: Vector3, left: Callable, stem: float = 0.0) -> void:
	var t := ToyboxTell.new()
	t.left = left
	t.stem = stem
	t.position = _w(at)
	add_child(t)


## A toy laser pointer beam across local x between two posts (centre `c`), with a 1.0 s guide flicker
## before it fires and a warning lamp beside the left post.
func _laser(c: Vector3, period: float, on: float, phase: float) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c), Vector3(3.2, 2.4, 0.2), period, on, phase, _yaw)
	g.warn = 1.0
	_dress_laser(g)
	_tell(c + Vector3(-2.6, 1.0, 0.0), func(tm: float) -> float: return g.time_until_on(tm), 1.0)
	return g


## A boxing glove on a spring: the piston, dressed. `top` is the ram's top centre when shut; it punches
## toward local +x (across a beam to its right).
func _glove(top: Vector3, period: float, phase: float) -> Piston:
	var size := Vector3(1.6, 1.3, 1.2)
	var p: Piston = kit.piston(_w(top), size, _yaw - 90.0, 2.6, period, phase, 10.0)
	_dress_glove(_w(top), size, 2.6, _yaw - 90.0)
	_glove_visual(p)
	_tell(top + Vector3(-1.1, 1.9, 0.0), func(tm: float) -> float: return _until_punch(p, tm), 0.9)
	return p


## A giant dice that slams down: the crusher, dressed.
func _die(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var c: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	_dress_die(c)
	_tell(floor_c + Vector3(size.x * 0.5 + 0.9, lift + size.y + 0.4, 0.0), func(tm: float) -> float: return _until_slam(c, tm), 0.8)
	return c


# ---- stage 4: Tower Bridge (BRANCH) - the block tower topples across the gap | wall run and mantle ----
# [shortcut: a stepping block in the middle of the gap]

## A block tower hinged at local `hinge` (the top edge of the platform you cross from); flat, it
## bridges `length` m toward local -Z.
func _tower(hinge: Vector3, length: float, phase_s: float) -> ToyboxTower:
	var t := ToyboxTower.new()
	t.length = length
	t.phase = phase_s
	t.rotation.y = deg_to_rad(_yaw)
	t.position = _w(hinge)
	add_child(t)
	_floors.append({"top": _w(hinge + Vector3(0, 0, -length * 0.5)), "size": _sz(Vector3(t.width, 0, length)), "drop": t.thickness, "tower": true})
	return t


## True when the tower lies flat as a bridge over all of [now + a, now + b].
static func _bridge_ok(t: ToyboxTower, a: float, b: float) -> bool:
	return t.flat_over(Game.course_time, a, b)


func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.78, 0.0, 3.2), 11.0, 3.2)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.6
	var fork_area: Dictionary = _area(fc, 5.5, 1.6)
	# LEFT (blue): the block tower topples across a 9 m gap to a dock, then two blocks, then the merge
	var tlen: float = 9.0
	var tower: ToyboxTower = _tower(Vector3(-3.5, 0, f0), tlen, 0.0)
	var dock: Dictionary = _blk(Vector3(-3.5, 0, f0 - tlen - 1.4), 2.8, 2.8, "main", 0.8)
	var q1: Dictionary = _post(_ahead(dock, 0.80, 0.0, 2.0, 0.4), 2.0, 2.0)
	var q2: Dictionary = _post(_ahead(q1, 0.82, 0.6, 2.0, -0.4), 2.0, 2.0)
	var q2c: Vector3 = q2["c"]
	var mc: Vector3 = _ahead(q2, 0.82, 0.0, 3.2, -q2c.x)
	var merge: Dictionary = _blk(Vector3(0, mc.y, mc.z), 11.0, 3.2)
	# RIGHT (yellow): wall run the bed rail over the void, a block, MANTLE the pillow stack, drop to the merge
	kit.wallrun(_w(Vector3(5.7, 1.2, f0 - 9.0)), Vector3(15.0, 6.5, 0.6), _yaw + 90.0)
	_post(Vector3(3.6, 0.0, f0 - 19.6), 2.0, 2.0)
	var case_top := Vector3(3.6, 3.3, f0 - 19.6 - 1.0 - 1.6 - 0.8)
	var pillow: Dictionary = _ledge(case_top, Vector3(2.6, 9.0, 1.6))
	# SHORTCUT: a stepping block in the middle of the gap - one 92% leap, then an easy hop to the dock
	var b1: Dictionary = _post(_ahead(_area(Vector3(0.2, 0, fc.z), 1.5, 1.6), 0.92, 0.0, 1.8), 1.8, 1.8, "accent")
	var cp: Dictionary = _cp(_ahead(merge, 0.82, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant != 1:
		if route_variant == 2:
			r_walk(_w(Vector3(0.2, 0, fc.z)))
			_hop(fork_area, b1)
			_hop(b1, dock)
		else:
			r_walk(_w(Vector3(-3.5, 0, f0 + 0.6)))
			_wait(func() -> bool: return _bridge_ok(tower, 0.0, 3.6), _w(Vector3(-3.5, 0, f0 + 0.6)))
			r_walk(_w(Vector3(-3.5, 0, f0 - tlen - 0.9)))
		_hop(dock, q1)
		_hop(q1, q2)
		_hop(q2, merge, Vector3(q2c.x, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.0, 0, f0 + 0.35)), _w(Vector3(5.2, 1.4, f0 - 3.4)), _w(Vector3(5.2, 1.4, f0 - 12.6)), _w(Vector3(3.6, 0, f0 - 19.4)))
		r_mantle(_w(Vector3(3.6, 0, f0 - 19.6 - 0.65)), _w(case_top + Vector3(0, 0, 0.2)))
		_hop(pillow, merge, Vector3(3.6, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Crayon Beams - a long crayon under two toy laser pointers --------------------------------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.80, 0.0, 2.0), 2.0, 2.0)
	var blen: float = 14.0
	var beam: Dictionary = _blk(_ahead(p1, 0.82, 0.0, blen), 1.6, blen, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var near: float = bc.z + blen * 0.5
	var l1: LaserGate = _laser(Vector3(bc.x, bc.y + 1.2, near - 5.0), 6.0, 0.25, 0.0)
	var l2: LaserGate = _laser(Vector3(bc.x, bc.y + 1.2, near - 8.0), 6.0, 0.25, 0.0)
	var p2: Dictionary = _post(_ahead(beam, 0.84, 0.6, 2.0), 2.0, 2.0)
	var cp: Dictionary = _cp(_ahead(p2, 0.82, 0.0, 5.0))
	# SHORTCUT: two little blocks beside the beam carry you past both lasers
	var sc: Array[Dictionary] = _side_chain(p1, 2, 3.6, 0.84)
	_hop(cp0, p1)
	if route_variant == 2:
		_hop(p1, sc[0])
		_hop(sc[0], sc[1])
		r_jump(_w(_edge(sc[1], Vector3(bc.x, 0, near - 10.5))), _w(Vector3(bc.x, bc.y, near - 10.5)))
	else:
		_hop(p1, beam, Vector3(0, 0, blen * 0.5 - 0.8))
		var hold: Vector3 = _w(Vector3(bc.x, bc.y, near - 2.4))
		r_walk(hold)
		_wait(func() -> bool: return _dark(l1, 0.1, 0.9 + 1.5) and _dark(l2, 0.8, 1.5 + 1.5), hold)
	r_walk(_w(Vector3(bc.x, bc.y, bc.z - blen * 0.5 + 0.9)))
	_hop(beam, p2)
	_hop(p2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Spinning Tops - ride two big tops across the rug ----------------------------------------

## A spinning top you stand on: a round disc turning about its centre (top surface at local `c`).
func _top(c: Vector3, radius: float, period: float, phase_t: float) -> RotatingPlatform:
	var arms: Array[Dictionary] = []
	var r: RotatingPlatform = kit.spinner(_w(c), period, arms, radius, phase_t, 0.5)
	return r


func _stage_6() -> Vector3:
	var rad: float = 3.0
	var t1c: Vector3 = Vector3(0, 0, -2.5 - 3.4 - rad)
	_top(t1c, rad, 8.0, 0.0)
	var mid: Dictionary = _blk(Vector3(0, 0, t1c.z - rad - 3.2 - 1.4), 2.8, 2.8, "main", 0.8)
	var mcz: float = (mid["c"] as Vector3).z
	var t2c: Vector3 = Vector3(0, 0, mcz - 1.4 - 3.2 - rad)
	_top(t2c, rad, -8.0, 0.5)
	var cp: Dictionary = _cp(Vector3(0, 0, t2c.z - rad - 3.2 - 2.5))
	# onto the first top (a metre inside its rim), walk to its far rim, jump to the block; again for the second
	r_jump(_w(Vector3(0, 0, -2.15)), _w(t1c + Vector3(0, 0, 2.0)))
	r_walk(_w(t1c + Vector3(0, 0, -2.3)))
	r_jump(_w(t1c + Vector3(0, 0, -2.3)), _w(Vector3(0, 0, mcz)))
	r_jump(_w(Vector3(0, 0, mcz - 1.05)), _w(t2c + Vector3(0, 0, 2.0)))
	r_walk(_w(t2c + Vector3(0, 0, -2.3)))
	r_jump(_w(t2c + Vector3(0, 0, -2.3)), _w((cp["c"] as Vector3) + Vector3(0, 0, 1.5)))
	r_checkpoint()
	return cp["c"]


# ---- stage 7: Jack Shelf - a jack-in-the-box throws you up onto the dollhouse, mantle its roof -----------

## A jack-in-the-box whose cushion (at rest) is at local `c`; `launch` is in the stage's frame.
func _jack(c: Vector3, period: float, phase_t: float, launch: Vector3, tint: Color) -> ToyboxJack:
	var j := ToyboxJack.new()
	j.period = period
	j.phase = phase_t
	j.launch = launch
	j.tint = tint
	j.rotation.y = deg_to_rad(_yaw)
	j.position = _w(c)
	add_child(j)
	_floors.append({"top": _w(c), "size": _sz(Vector3(2.6, 0, 2.6)), "drop": 1.6})
	return j


func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var jc: Vector3 = _ahead(cp0, 0.78, 0.0, 2.6)
	var jack: ToyboxJack = _jack(jc, 4.5, 0.0, Vector3(0, 20.5, -3.0), BLUE)
	var ja: Dictionary = _area(jc, 1.3, 1.3)
	var shelf: Dictionary = _blk(Vector3(jc.x, 5.0, jc.z - 1.3 - 2.0 - 2.5), 5.0, 5.0, "main", 1.0)
	var sc: Vector3 = shelf["c"]
	var roof_top := Vector3(sc.x, 5.0 + 3.3, sc.z - 2.5 - 1.6 - 0.8)
	var roof: Dictionary = _ledge(roof_top, Vector3(3.4, 9.0, 1.6))
	var cp: Dictionary = _cp(_ahead(roof, 0.80, 0.0, 5.0, -jc.x))
	_wait(func() -> bool: return _resting(jack, 0.0, 2.0))
	_hop(cp0, ja)
	_kick(jc, Vector3(sc.x, 5.0, sc.z + 1.2))
	r_walk(_w(Vector3(sc.x, 5.0, sc.z - 1.6)))
	r_mantle(_w(Vector3(sc.x, 5.0, sc.z - 2.5 + 0.35)), _w(roof_top + Vector3(0, 0, 0.2)))
	_hop(roof, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 8: Glove Alley (BRANCH) - boxing gloves over the beam | the cardboard-tube portal ---------------

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.78, 0.0, 3.2), 11.0, 3.2)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.6
	# RIGHT (yellow): the tube sends you up to a lintel beam, then two blocks down to the merge
	var hi: Dictionary = _blk(Vector3(3.5, 4.5, f0 - 9.0), 1.6, 5.0, "alt", 0.6)
	var door: WarpPortal = kit.portal(_w(Vector3(3.5, 0, fc.z - 0.6)), _yaw, _w(Vector3(3.5, 4.5, f0 - 7.2)), _yaw, 7.0)
	_dress_portal(_w(Vector3(3.5, 0, fc.z - 0.6)), _yaw, ORANGE)
	_dress_portal(_w(Vector3(3.5, 4.5, f0 - 7.2)), _yaw, BLUE)
	var la: Dictionary = _post(_ahead(hi, 0.80, -1.5, 2.0, 0.3), 2.0, 2.0)
	var la2: Dictionary = _post(_ahead(la, 0.80, -1.5, 2.0, -0.3), 2.0, 2.0)
	var mc: Vector3 = _ahead(la2, 0.80, -1.5, 3.2, -((la2["c"] as Vector3).x))
	var merge: Dictionary = _blk(Vector3(0, mc.y, mc.z), 11.0, 3.2)
	# LEFT (red): a long crayon past two boxing gloves, a block, the merge
	var left: Dictionary = _area(Vector3(-3.5, 0, fc.z), 1.5, 1.6)
	var beam_near: float = f0 + 0.35 - _e(0.84, 0.0)
	var pa_c: float = _behind(mc.z + 1.6, 0.80, 0.0, 2.0)
	var pa: Dictionary = _post(Vector3(-3.5, 0, pa_c), 2.0, 2.0)
	var beam_far: float = (pa_c + 1.0) - 0.35 + _e(0.84, 0.0)
	var blen: float = beam_near - beam_far
	var beam: Dictionary = _blk(Vector3(-3.5, 0, (beam_near + beam_far) * 0.5), 1.6, blen, "alt", 0.6)
	var g1z: float = beam_near - 4.0
	var g2z: float = beam_near - 7.0
	var gl1: Piston = _glove(Vector3(-4.85, 1.35, g1z), 8.0, 0.0)
	var gl2: Piston = _glove(Vector3(-4.85, 1.35, g2z), 8.0, 0.0)
	var cp: Dictionary = _cp(_ahead(merge, 0.82, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant != 1:
		var hold: Vector3 = _w(Vector3(-3.5, 0, beam_near - 1.7))
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_hop(left, beam, Vector3(0, 0, (blen * 0.5) - 0.9 + 0.0))
		r_walk(hold)
		_wait(func() -> bool: return _ram_clear(gl1, 0.0, 0.6 + 1.5) and _ram_clear(gl2, 0.2, 0.9 + 1.5), hold)
		r_walk(_w(Vector3(-3.5, 0, beam_far + 0.9)))
		_hop(beam, pa)
		_hop(pa, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.5, 0, fc.z + 0.6)))
		r_portal(_w(Vector3(3.5, 0, fc.z - 0.9)), door.exit_point())
		r_walk(_w(Vector3(3.5, 4.5, f0 - 10.0)))
		_hop(hi, la)
		_hop(la, la2)
		_hop(la2, merge, Vector3(3.5, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Train Set - ride the train across the rug, then wall run the brick wall ----------------

## A chain of `n` little blocks hopped at ~`pct`, to the side (`dx`) of the line they bypass.
func _side_chain(from: Dictionary, n: int, dx: float, pct: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var prev: Dictionary = from
	for i: int in n:
		prev = _post(_ahead(prev, pct - (0.08 if i == 0 else 0.0), 0.0, 1.8, dx if i == 0 else 0.0), 1.8, 1.8, "accent")
		out.append(prev)
	return out


func _stage_9() -> Vector3:
	var clen: float = 6.5
	var ride: float = 16.0
	var near_z: float = -2.5 - 0.8 - clen * 0.5
	var cars: Array[ToyboxCar] = []
	cars.append(_car(Vector3(-1.9, 0, near_z), Vector3(0, 0, -ride), 18.0, 0.0, GREEN, 0.36, clen))
	cars.append(_car(Vector3(1.9, 0, near_z), Vector3(0, 0, -ride), 18.0, 0.5, YELLOW, 0.36, clen))
	var fz: float = near_z - ride - clen * 0.5 - 0.8 - 1.75
	_blk(Vector3(0, 0, fz), 3.5, 3.5, "main", 0.8)
	var froms: Array[Vector3] = [_w(Vector3(-1.9, 0, -2.15)), _w(Vector3(1.9, 0, -2.15))]
	var exits: Array[Vector3] = [_w(Vector3(-1.0, 0, fz + 0.5)), _w(Vector3(1.0, 0, fz + 0.5))]
	var poses: Array[Vector3] = [_w(Vector3(-1.9, -0.25, near_z - ride)), _w(Vector3(1.9, -0.25, near_z - ride))]
	_ferry(cars, froms, exits, poses)
	# the brick wall: a wall-run panel along the right, over the void, to a post
	var f: float = fz - 1.75
	kit.wallrun(_w(Vector3(2.3, 1.2, f - 9.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var post: Dictionary = _post(Vector3(-0.6, 0, f - 22.5), 2.4, 2.8)
	var cp: Dictionary = _cp(_ahead(post, 0.80, 0.0, 5.0, 0.6))
	r_walk(_w(Vector3(0.3, 0, fz - 0.6)))
	r_wallrun(_w(Vector3(0.3, 0, f + 0.35)), _w(Vector3(1.8, 1.4, f - 3.6)), _w(Vector3(1.8, 1.4, f - 14.5)), _w(Vector3(-0.6, 0, f - 22.2)))
	_hop(post, cp, Vector3(0.6, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 10: Block Press - a giant dice slams the crayon [shortcut: a side path of blocks] ------------

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.78, 0.0, 2.0), 2.0, 2.0)
	var blen: float = 18.0
	var beam: Dictionary = _blk(_ahead(p1, 0.80, 0.0, blen), 1.6, blen, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var near: float = bc.z + blen * 0.5
	var far: float = bc.z - blen * 0.5
	var d1: Crusher = _die(Vector3(bc.x, bc.y, near - 4.5), Vector3(2.2, 1.2, 2.0), 3.2, 7.0, 0.0)
	var d2: Crusher = _die(Vector3(bc.x, bc.y, near - 8.5), Vector3(2.2, 1.2, 2.0), 3.2, 7.0, 0.0)
	var shelf_top := Vector3(bc.x, bc.y + 3.3, far - 1.6 - 0.8)
	var shelf: Dictionary = _ledge(shelf_top, Vector3(3.0, 9.0, 1.6))
	var cp: Dictionary = _cp(_ahead(shelf, 0.80, 0.0, 5.0, -bc.x))
	var sc: Array[Dictionary] = _side_chain(p1, 2, 3.6, 0.84)
	_hop(cp0, p1)
	if route_variant == 2:
		_hop(p1, sc[0])
		_hop(sc[0], sc[1])
		r_jump(_w(_edge(sc[1], Vector3(bc.x, 0, near - 11.5))), _w(Vector3(bc.x, bc.y, near - 11.5)))
	else:
		_hop(p1, beam, Vector3(0, 0, blen * 0.5 - 0.8))
		var hold: Vector3 = _w(Vector3(bc.x, bc.y, near - 1.8))
		r_walk(hold)
		_wait(func() -> bool: return _press_ok(d1, 0.0, 0.6 + 1.5) and _press_ok(d2, 0.3, 1.0 + 1.5), hold)
	r_walk(_w(Vector3(bc.x, bc.y, far + 0.9)))
	r_mantle(_w(Vector3(bc.x, bc.y, far + 0.35)), _w(shelf_top + Vector3(0, 0, 0.3)))
	_hop(shelf, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 11: Teddy Terrace (BRANCH) - the jack-in-the-box up | the xylophone keys up ----------------

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.78, 0.0, 3.2), 11.0, 3.2)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.6
	var top_y: float = 4.8
	# RIGHT (yellow): three keys climbing, the last flight lands on the terrace
	var right: Dictionary = _area(Vector3(3.5, 0, fc.z), 1.5, 1.6)
	var k: Vector3 = _ahead(right, 0.78, 0.0, 2.2)
	var cols: Array[Color] = [ORANGE, GREEN, PURPLE, RED]
	var keys: Array[Vector3] = []
	for i: int in 4:
		_key(k, i + 1, cols[i])
		keys.append(k)
		var ny: float = k.y + 1.2 if i < 3 else top_y
		var land: Vector3 = _key_landing(k, ny)
		k = Vector3(k.x, ny, land.z)
	var mz: float = k.z
	var merge: Dictionary = _blk(Vector3(0, top_y, mz), 11.0, 7.0, "main", 1.0)
	# LEFT (blue): a jack throws you onto a long terrace
	var jc: Vector3 = _ahead(_area(Vector3(-3.5, 0, fc.z), 1.5, 1.6), 0.78, 0.0, 2.6)
	var jack: ToyboxJack = _jack(jc, 4.5, 0.0, Vector3(0, 20.5, -3.0), BLUE)
	var t_near: float = jc.z - 1.3 - 2.0
	var t_far: float = (mz + 3.5) - 0.35 + _e(0.80, 0.0)
	var terrace: Dictionary = _blk(Vector3(-3.5, top_y, (t_near + t_far) * 0.5), 3.2, t_near - t_far, "alt", 0.8)
	var cp: Dictionary = _cp(_ahead(merge, 0.80, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		_wait(func() -> bool: return _resting(jack, 0.0, 2.0))
		_hop(_area(Vector3(-3.5, 0, fc.z), 1.5, 1.6), _area(jc, 1.3, 1.3))
		_kick(jc, Vector3(-3.5, top_y, t_near - 1.5))
		r_walk(_w(Vector3(-3.5, top_y, t_far + 0.9)))
		_hop(terrace, merge, Vector3(-3.5, 0, 2.5))
	else:
		r_walk(_w(Vector3(3.5, 0, fc.z + 0.6)))
		_hop(right, _area(keys[0], 1.7, 1.1))
		for i: int in 4:
			r_pad(_w(keys[i]), _w(keys[i + 1] if i < 3 else k))
	var mg: Dictionary = _area(Vector3(0, top_y, mz), 5.5, 3.5)
	_hop(mg, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 12: Tumbling Towers - two block towers topple one after the other ---------------------------

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var len_a: float = 8.0
	var tower_a: ToyboxTower = _tower(Vector3(0, 0, -2.5), len_a, 0.0)
	var dock: Dictionary = _blk(Vector3(1.0, 0, -2.5 - len_a - 1.5), 3.0, 3.0, "main", 0.8)
	var dz: float = (dock["c"] as Vector3).z
	var tower_b: ToyboxTower = _tower(Vector3(1.0, 0, dz - 1.5), len_a, 0.0)
	tower_b.phase = -2.2
	var dock2: Dictionary = _blk(Vector3(1.0, 0, dz - 1.5 - len_a - 1.5), 3.0, 3.0, "main", 0.8)
	var p1: Dictionary = _post(_ahead(dock2, 0.80, 0.6, 2.0, -1.0), 2.0, 2.0)
	var cp: Dictionary = _cp(_ahead(p1, 0.80, 0.0, 5.0))
	var hold_a: Vector3 = _w(Vector3(0, 0, -2.0))
	r_walk(hold_a)
	_wait(func() -> bool: return _bridge_ok(tower_a, 0.0, 3.6), hold_a)
	r_walk(_w(Vector3(1.0, 0, dz + 0.4)))
	var hold_b: Vector3 = _w(Vector3(1.0, 0, dz - 0.6))
	r_walk(hold_b)
	_wait(func() -> bool: return _bridge_ok(tower_b, 0.0, 3.6), hold_b)
	r_walk(_w(Vector3(1.0, 0, dz - 1.5 - len_a - 0.9)))
	_hop(dock2, p1)
	_hop(p1, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 13: Seesaw Park - two seesaw planks, a runway, the cardboard tube over the chasm -------------

func _stage_13() -> Vector3:
	var along_x: bool = absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0
	var opts: Dictionary = {"tilt_about_x": along_x, "tilt_about_z": not along_x, "edge_tilt_deg": 9.0, "max_tilt_deg": 14.0, "sink_depth": 0.35}
	kit.tilt(_w(Vector3(0, 0, -9.5)), _sz(Vector3(2.4, 0.4, 7.0)), opts)
	kit.tilt(_w(Vector3(0, 0.4, -19.5)), _sz(Vector3(2.4, 0.4, 7.0)), opts)
	_blk(Vector3(0, 0.8, -31.0), 3.4, 10.0, "alt", 0.8)
	var exit_c: Vector3 = Vector3(0, 0.8, -31.0 - 5.0 - 14.0 - 2.5)
	var cp: Dictionary = _cp(exit_c)
	var door: WarpPortal = kit.portal(_w(Vector3(0, 0.8, -34.2)), _yaw, _w(exit_c + Vector3(0, 0, 1.2)), _yaw, 7.0)
	_dress_portal(_w(Vector3(0, 0.8, -34.2)), _yaw, ORANGE)
	_dress_portal(_w(exit_c + Vector3(0, 0, 1.2)), _yaw, BLUE)
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -7.2)))
	r_walk(_w(Vector3(0, 0, -12.4)))
	r_jump(_w(Vector3(0, 0, -12.6)), _w(Vector3(0, 0.4, -17.2)))
	r_walk(_w(Vector3(0, 0.4, -22.4)))
	r_jump(_w(Vector3(0, 0.4, -22.6)), _w(Vector3(0, 0.8, -27.0)))
	r_walk(_w(Vector3(0, 0.8, -31.5)))
	r_portal(_w(Vector3(0, 0.8, -34.5)), door.exit_point())
	r_checkpoint()
	return cp["c"]


# ---- stage 14: Bedpost Chimney - a jack throws you up, three wall runs up the bed post ---------------

func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)


func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var jc: Vector3 = _ahead(cp0, 0.78, 0.0, 2.6)
	var jack: ToyboxJack = _jack(jc, 4.5, 0.0, Vector3(0, 22.0, -4.5), RED)
	_blk(Vector3(0, 6.0, -15.2), 2.4, 2.4, "main", 0.8)
	_chimney_panel(2.3, 7.2, -19.5, -26.0)
	_chimney_panel(-2.3, 12.0, -24.5, -32.5)
	_chimney_panel(2.3, 15.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 17.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(_ahead(top, 0.80, 0.0, 5.0, 0.75))
	_wait(func() -> bool: return _resting(jack, 0.0, 2.0))
	_hop(cp0, _area(jc, 1.3, 1.3))
	_kick(jc, Vector3(0, 6.0, -14.8))
	r_walk(_w(Vector3(0, 6.0, -14.4)))
	r_wallrun(_w(Vector3(0.5, 6.0, -15.95)), _w(Vector3(1.7, 7.4, -20.6)), _w(Vector3(1.7, 7.4, -23.5)), _w(Vector3(-1.7, 11.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 11.5, -27.4)), _w(Vector3(-1.7, 11.5, -30.4)), _w(Vector3(1.7, 14.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 14.5, -34.0)), _w(Vector3(1.7, 14.5, -35.4)), _w(Vector3(-0.75, 17.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 15: Top Spin - three tops in a row, each turning the other way -------------------------------

func _stage_15() -> Vector3:
	var rad: float = 2.4
	var step: float = rad * 2.0 + 3.2
	var cs: Array[Vector3] = []
	for i: int in 3:
		cs.append(Vector3(0, 0.4 * float(i), -2.5 - 3.2 - rad - step * float(i)))
		_top(cs[i], rad, 7.0 if i % 2 == 0 else -7.0, 0.3 * float(i))
	var cp: Dictionary = _cp(Vector3(0, 0.8, cs[2].z - rad - 3.2 - 2.5))
	r_jump(_w(Vector3(0, 0, -2.15)), _w(cs[0] + Vector3(0, 0, 1.8)))
	for i: int in 3:
		r_walk(_w(cs[i] + Vector3(0, 0, -1.9)))
		var to: Vector3 = (cs[i + 1] + Vector3(0, 0, 1.8)) if i < 2 else ((cp["c"] as Vector3) + Vector3(0, 0, 1.5))
		r_jump(_w(cs[i] + Vector3(0, 0, -1.9)), _w(to))
	r_checkpoint()
	return cp["c"]


# ---- stage 16: Toy Parade (BRANCH) - the tin cars shuttle you across | the block bridge ------------------

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.78, 0.0, 3.2), 11.0, 3.2)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.6
	# RIGHT (yellow): two blocks over the gap
	var right: Dictionary = _area(Vector3(3.5, 0, fc.z), 1.5, 1.6)
	var b1: Dictionary = _post(_ahead(right, 0.80, 0.0, 2.0), 2.0, 2.0)
	var b2: Dictionary = _post(_ahead(b1, 0.82, 0.0, 2.0), 2.0, 2.0)
	var mn: float = (b2["c"] as Vector3).z - 1.0 + 0.35 - _e(0.82, 0.0)
	var merge: Dictionary = _blk(Vector3(0, 0, mn - 1.6), 11.0, 3.2)
	# LEFT (red): two tin cars shuttle between the fork and the merge
	var clen: float = 5.0
	var ride: float = f0 - 1.6 - clen - mn
	var near_z: float = f0 - 0.8 - clen * 0.5
	var lanes: Array[float] = [-4.2, -1.0]
	var cars: Array[ToyboxCar] = []
	cars.append(_car(Vector3(lanes[0], 0, near_z), Vector3(0, 0, -ride), 16.0, 0.0, PURPLE))
	cars.append(_car(Vector3(lanes[1], 0, near_z), Vector3(0, 0, -ride), 16.0, 0.5, ORANGE))
	var cp: Dictionary = _cp(_ahead(merge, 0.80, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant != 1:
		var froms: Array[Vector3] = [_w(Vector3(lanes[0], 0, f0 + 0.35)), _w(Vector3(lanes[1], 0, f0 + 0.35))]
		var exits: Array[Vector3] = [_w(Vector3(lanes[0], 0, mn - 1.2)), _w(Vector3(lanes[1], 0, mn - 1.2))]
		var poses: Array[Vector3] = [_w(Vector3(lanes[0], -0.25, near_z - ride)), _w(Vector3(lanes[1], -0.25, near_z - ride))]
		_ferry(cars, froms, exits, poses)
	else:
		r_walk(_w(Vector3(3.5, 0, fc.z + 0.6)))
		_hop(right, b1)
		_hop(b1, b2)
		_hop(b2, merge, Vector3(3.5, 0, 0.4))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 17: Shelf Foot - a toy laser, then a jack-in-the-box up onto the bookshelf's first board -------
# [shortcut: a side path of blocks to the jack]

func _stage_17() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _post(_ahead(cp0, 0.78, 0.0, 2.0), 2.0, 2.0)
	var blen: float = 12.0
	var beam: Dictionary = _blk(_ahead(p1, 0.80, 0.0, blen), 1.6, blen, "alt", 0.6)
	var bc: Vector3 = beam["c"]
	var near: float = bc.z + blen * 0.5
	var far: float = bc.z - blen * 0.5
	var laser: LaserGate = _laser(Vector3(bc.x, bc.y + 1.2, near - 6.0), 6.0, 0.25, 0.0)
	var jc: Vector3 = _ahead(beam, 0.80, 0.0, 2.6)
	var jack: ToyboxJack = _jack(jc, 4.5, 0.0, Vector3(0, 20.5, -3.0), YELLOW)
	var ja: Dictionary = _area(jc, 1.3, 1.3)
	var cp: Dictionary = _cp(Vector3(jc.x, 5.0, jc.z - 1.3 - 2.0 - 2.5))
	var sc: Array[Dictionary] = _side_chain(p1, 3, 3.6, 0.84)
	_hop(cp0, p1)
	if route_variant == 2:
		_hop(p1, sc[0])
		_hop(sc[0], sc[1])
		_hop(sc[1], sc[2])
		_hop(sc[2], ja)
	else:
		_hop(p1, beam, Vector3(0, 0, blen * 0.5 - 0.8))
		var hold: Vector3 = _w(Vector3(bc.x, bc.y, near - 2.4))
		r_walk(hold)
		_wait(func() -> bool: return _dark(laser, 0.1, 0.9 + 1.5), hold)
		r_walk(_w(Vector3(bc.x, bc.y, far + 0.9)))
		_wait(func() -> bool: return _resting(jack, 0.0, 2.0))
		_hop(beam, ja)
	_kick(jc, Vector3(jc.x, 5.0, (cp["c"] as Vector3).z + 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 18: THE BOOKSHELF - climb the books to the toy rocket on top -----------------------------------

var _rocket: Node3D
var _rocket_flame: GPUParticles3D
var _finish_light: OmniLight3D


func _stage_18() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	# A: three book spines, then MANTLE the bookend
	var pa: Dictionary = _post(_ahead(cp0, 0.78, 0.0, 2.0), 2.0, 2.0)
	var pb: Dictionary = _post(_ahead(pa, 0.80, 0.6, 2.0, -0.4), 2.0, 2.0)
	var pc: Dictionary = _post(_ahead(pb, 0.80, 0.6, 2.0, 0.4), 2.0, 2.0)
	var pcc: Vector3 = pc["c"]
	var be_top := Vector3(pcc.x, pcc.y + 3.3, pcc.z - 1.0 - 1.6 - 0.8)
	var bookend: Dictionary = _ledge(be_top, Vector3(3.0, 9.0, 1.6))
	# B: the second board, a tumbling stack of books across a gap
	var s2: Dictionary = _blk(_ahead(bookend, 0.78, 0.0, 6.0, -pcc.x), 6.0, 6.0, "main", 1.0)
	var s2c: Vector3 = s2["c"]
	var tfront: float = s2c.z - 3.0
	var tlen: float = 9.0
	var tower: ToyboxTower = _tower(Vector3(0, s2c.y, tfront), tlen, 1.5)
	var dock: Dictionary = _blk(Vector3(0, s2c.y, tfront - tlen - 1.5), 3.0, 3.0, "main", 0.8)
	# C: a jack throws you up to the third board
	var jc: Vector3 = _ahead(dock, 0.78, 0.0, 2.6)
	var jack: ToyboxJack = _jack(jc, 4.5, 0.0, Vector3(0, 20.5, -3.0), PURPLE)
	var y3: float = s2c.y + 5.0
	var s3: Dictionary = _blk(Vector3(jc.x, y3, jc.z - 1.3 - 2.0 - 2.5), 5.0, 5.0, "main", 1.0)
	var s3c: Vector3 = s3["c"]
	# D: wall run a tall book spine, then MANTLE the top board's lip
	var f: float = s3c.z - 2.5
	kit.wallrun(_w(Vector3(s3c.x + 2.3, y3 + 1.2, f - 9.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var post: Dictionary = _post(Vector3(s3c.x - 0.6, y3, f - 22.5), 2.4, 2.8)
	var lip_top := Vector3(s3c.x - 0.6, y3 + 3.3, f - 22.5 - 1.4 - 1.6 - 0.8)
	var lip: Dictionary = _ledge(lip_top, Vector3(3.0, 9.0, 1.6))
	var top: Dictionary = _blk(_ahead(lip, 0.78, 0.0, 6.0, -(s3c.x - 0.6)), 6.0, 6.0, "main", 1.0)
	var topc: Vector3 = top["c"]
	# E: the last crossing, a plank under a giant dice, to the rocket's launch pad
	var plen: float = 12.0
	var plank: Dictionary = _blk(_ahead(top, 0.80, 0.0, plen), 1.6, plen, "alt", 0.6)
	var pc2: Vector3 = plank["c"]
	var pnear: float = pc2.z + plen * 0.5
	var pfar: float = pc2.z - plen * 0.5
	var die: Crusher = _die(Vector3(pc2.x, pc2.y, pnear - 5.0), Vector3(2.2, 1.2, 2.0), 3.2, 7.0, 0.0)
	var pad: Dictionary = _blk(_ahead(plank, 0.80, 0.0, 10.0), 10.0, 10.0, "goal", 1.2)
	var padc: Vector3 = pad["c"]
	var fin_at: Vector3 = padc + Vector3(0, 0, -1.0)
	kit.finish(_w(fin_at), _yaw)
	_finish_pos = _w(fin_at)
	_build_rocket(padc)
	# the route
	_hop(cp0, pa)
	_hop(pa, pb)
	_hop(pb, pc)
	r_walk(_w(Vector3(pcc.x, pcc.y, pcc.z - 0.6)))
	r_mantle(_w(Vector3(pcc.x, pcc.y, pcc.z - 1.0 + 0.35)), _w(be_top + Vector3(0, 0, 0.2)))
	_hop(bookend, s2, Vector3(0, 0, 1.2))
	var hold_a: Vector3 = _w(Vector3(0, s2c.y, tfront + 0.4))
	r_walk(hold_a)
	_wait(func() -> bool: return _bridge_ok(tower, 0.0, 3.6), hold_a)
	r_walk(_w(Vector3(0, s2c.y, tfront - tlen - 0.9)))
	_wait(func() -> bool: return _resting(jack, 0.0, 2.0))
	_hop(dock, _area(jc, 1.3, 1.3))
	_kick(jc, Vector3(s3c.x, y3, s3c.z + 1.2))
	r_walk(_w(Vector3(s3c.x + 0.3, y3, f + 1.0)))
	r_wallrun(_w(Vector3(s3c.x + 0.3, y3, f + 0.35)), _w(Vector3(s3c.x + 1.8, y3 + 1.4, f - 3.6)), _w(Vector3(s3c.x + 1.8, y3 + 1.4, f - 14.5)), _w(Vector3(s3c.x - 0.6, y3, f - 22.2)))
	r_walk(_w(Vector3(s3c.x - 0.6, y3, f - 22.5 - 0.6)))
	r_mantle(_w(Vector3(s3c.x - 0.6, y3, f - 22.5 - 1.4 + 0.35)), _w(lip_top + Vector3(0, 0, 0.2)))
	_hop(lip, top, Vector3(0, 0, 1.2))
	_hop(top, plank, Vector3(0, 0, plen * 0.5 - 0.8))
	var hold_b: Vector3 = _w(Vector3(pc2.x, pc2.y, pnear - 1.8))
	r_walk(hold_b)
	_wait(func() -> bool: return _press_ok(die, 0.0, 0.9 + 1.5), hold_b)
	r_walk(_w(Vector3(pc2.x, pc2.y, pfar + 0.9)))
	_hop(plank, pad, Vector3(0, 0, 3.0))
	r_walk(_w(fin_at + Vector3(0, 0, -0.3)))
	# the bookshelf itself: a towering wall of books down the left of the whole climb, its great
	# boards jutting out at the level of each tier, and a back panel behind the rocket
	var base_y: float = -26.0
	var wall_len: float = absf(padc.z) + 30.0
	deco.book_wall(_w(Vector3(-13.0, base_y, -wall_len * 0.5 + 12.0)), deg_to_rad(_yaw), wall_len, padc.y - base_y + 30.0, Vector2(3.0, 6.0))
	var wood: StandardMaterial3D = Look.flat(Color(0.62, 0.42, 0.25), 0.75)
	for ty: float in [0.0, s2c.y, y3, lip_top.y]:
		add_child(Look.box(_sz(Vector3(7.0, 1.4, wall_len)), wood, _w(Vector3(-10.5, ty - 2.0, -wall_len * 0.5 + 12.0))))
	add_child(Look.box(_sz(Vector3(40.0, padc.y - base_y + 40.0, 1.6)), wood, _w(Vector3(0, (padc.y + base_y) * 0.5 + 10.0, padc.z - 14.0))))


## The toy rocket standing on its launch pad behind the finish gate (local pad centre): a red-and-white
## body, a nose cone, a porthole, three fins, and a flame that roars up when you finish.
func _build_rocket(padc: Vector3) -> void:
	_rocket = Node3D.new()
	_rocket.transform = Transform3D(_b, _w(padc + Vector3(0, 0.0, -3.0)))
	add_child(_rocket)
	var white: StandardMaterial3D = Look.flat(CREAM, 0.4)
	var red: StandardMaterial3D = Look.flat(RED, 0.35)
	var blue: StandardMaterial3D = Look.flat(BLUE, 0.4)
	var h: float = 22.0
	_rocket.add_child(Look.cylinder(2.6, h, white, Vector3(0, h * 0.5 + 1.5, -2.0), 2.6, 28))
	_rocket.add_child(Look.cylinder(2.64, 1.6, red, Vector3(0, 5.0, -2.0), -1.0, 28))
	_rocket.add_child(Look.cylinder(2.64, 1.6, red, Vector3(0, 14.0, -2.0), -1.0, 28))
	_rocket.add_child(Look.cylinder(0.05, 7.0, red, Vector3(0, h + 1.5 + 3.5, -2.0), 2.6, 28))
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var fin := Look.box(Vector3(0.5, 6.0, 3.6), blue, Vector3(sin(a) * 3.2, 4.0, -2.0 + cos(a) * 3.2))
		fin.rotation.y = a
		_rocket.add_child(fin)
	var win := Look.sphere(1.0, Look.flat(Color(0.5, 0.85, 1.0), 0.2, 0.0, 1.4), Vector3(0, 17.0, -2.0 + 2.2))
	win.scale = Vector3(1.0, 1.0, 0.4)
	_rocket.add_child(win)
	_rocket.add_child(Look.cylinder(1.5, 1.2, Look.flat(Color(0.3, 0.3, 0.36), 0.4, 0.7), Vector3(0, 1.0, -2.0), 2.0, 16))
	_rocket_flame = Fx.emitter({"amount": 90, "lifetime": 1.0, "shape": "sphere", "radius": 0.9, "dir": Vector3.DOWN,
		"spread": 18.0, "speed": Vector2(8.0, 16.0), "gravity": Vector3(0, -2.0, 0), "tex": Fx.Tex.SMOKE, "size": 2.0,
		"colors": PackedColorArray([Color(3.0, 2.2, 0.8, 0.9), Color(2.4, 0.8, 0.2, 0.7), Color(0.5, 0.3, 0.2, 0.0)]),
		"curve": "puff", "emitting": false, "aabb": AABB(Vector3(-20, -40, -20), Vector3(40, 60, 40))})
	_rocket_flame.position = Vector3(0, 0.6, -2.0)
	_rocket.add_child(_rocket_flame)
	_finish_light = OmniLight3D.new()
	_finish_light.light_color = Color(1.0, 0.7, 0.35)
	_finish_light.light_energy = 0.0
	_finish_light.omni_range = 30.0
	_finish_light.position = Vector3(0, 2.0, -2.0)
	_rocket.add_child(_finish_light)


## The rocket fires: flame and smoke roar out of its engine, the pad glows, the toybox cheers.
func _finish_sequence() -> void:
	if _rocket_flame != null:
		_rocket_flame.emitting = true
		_finish_light.light_energy = 6.0
		# SOUND: toybox_finish - the toy rocket's engine roars up under a music-box fanfare
		WorldAudio.at(self, "toybox_finish", _finish_pos + Vector3(0, 6.0, 0), 1.0, 120.0)
		var tw: Tween = create_tween()
		tw.tween_property(_rocket, "position:y", _rocket.position.y + 3.5, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(1.1).timeout


# ---- environment ----------------------------------------------------------------------------------

func palette_col(i: int) -> Color:
	return deco.palette(i)


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
	_env.sky = ToyboxSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(1.0, 0.9, 0.78)
	_env.ambient_light_energy = 0.62
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(1.0, 0.88, 0.68)
	_env.fog_density = 0.0021
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.3
	_env.fog_sun_scatter = 0.25
	_env.glow_enabled = true
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 1.2
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.15
	_env.adjustment_contrast = 1.06
	# the afternoon sun through the window: low, golden, long shadows; a cool fill from the room
	_sun.light_color = Color(1.0, 0.88, 0.65)
	_sun.light_energy = 1.7
	_sun.rotation_degrees = Vector3(-30, 36, 0)
	_fill.light_color = Color(0.72, 0.82, 1.0)
	_fill.light_energy = 0.3
	_fill.rotation_degrees = Vector3(-20, 216, 0)


## Swap every walkable surface to the plastic-block shader: main blocks take a toy colour from a
## six-colour palette by where they stand, everything else keeps its colours.
func _toy_materials() -> void:
	var shader: Shader = preload("res://visual/toybox_block.gdshader")
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = shader
		var top: Color = sm.get_shader_parameter("top_color")
		var side: Color = sm.get_shader_parameter("side_color")
		var trim: Color = sm.get_shader_parameter("trim_color")
		if top.is_equal_approx(Look.c("top")):
			var gp: Vector3 = m.global_position
			var idx: int = int(floor(gp.x / 3.0)) * 3 + int(floor(gp.z / 3.0)) * 5 + int(floor(gp.y / 1.5)) * 7
			top = deco.palette(idx)
			side = top.darkened(0.35)
		r.set_shader_parameter("top_color", top)
		r.set_shader_parameter("side_color", side)
		r.set_shader_parameter("trim_color", trim)
		for key: String in ["half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


# ---- the room ---------------------------------------------------------------------------------------

func _route_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for st: Dictionary in route:
		for key: String in ["from", "to", "entry", "exit", "top", "jump_from"]:
			if st.has(key) and st[key] is Vector3 and (st[key] as Vector3) != Vector3.ZERO:
				pts.append(st[key])
	for p: Vector3 in _cp_world:
		pts.append(p)
	for f: Dictionary in _floors:
		pts.append(f["top"])
	return pts


func _clear_of(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist and absf(p.y - q.y) < dist + 30.0:
			return false
	return true


## True when nothing walkable sits inside the box (world centre, half extents).
func _box_free(c: Vector3, h: Vector3, skip: Dictionary = {}) -> bool:
	for f: Dictionary in _floors:
		if f == skip:
			continue
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		if absf(t.x - c.x) < h.x + s.x * 0.5 and absf(t.z - c.z) < h.z + s.z * 0.5 and t.y > c.y - h.y - 0.5 and t.y - float(f["drop"]) < c.y + h.y:
			return false
	return true


## A window in a wall: frame, cross and a glowing pane (world centre, yaw so its front faces the room).
func _window(c: Vector3, yaw: float, w: float, h: float) -> void:
	var n := Node3D.new()
	n.position = c
	n.rotation.y = yaw
	add_child(n)
	var pane: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.75), 0.3, 0.0, 1.5)
	n.add_child(Look.box(Vector3(w, h, 0.4), pane, Vector3.ZERO))
	var white: StandardMaterial3D = Look.flat(CREAM, 0.6)
	n.add_child(Look.box(Vector3(w + 3.0, 1.6, 1.4), white, Vector3(0, h * 0.5 + 0.8, 0.5)))
	n.add_child(Look.box(Vector3(w + 3.0, 1.6, 1.4), white, Vector3(0, -h * 0.5 - 0.8, 0.5)))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(1.6, h + 3.2, 1.4), white, Vector3(sx * (w * 0.5 + 0.8), 0, 0.5)))
	n.add_child(Look.box(Vector3(w, 1.0, 1.0), white, Vector3(0, 0, 0.4)))
	n.add_child(Look.box(Vector3(1.0, h, 1.0), white, Vector3(0, 0, 0.4)))


func _surroundings() -> void:
	var rng: RandomNumberGenerator = kit.rng
	var pts: Array[Vector3] = _route_points()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p: Vector3 in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid: Vector3 = (lo + hi) * 0.5
	var span: Vector3 = hi - lo
	var floor_y: float = lo.y - 18.0
	# crayon and pencil pillars from the floor up under every block that floats high enough
	var crayon_cols: Array[Color] = [ToyboxDecor.RED, ToyboxDecor.BLUE, ToyboxDecor.YELLOW, ToyboxDecor.GREEN, ToyboxDecor.ORANGE, ToyboxDecor.PURPLE]
	var n_pillars: int = 0
	for f: Dictionary in _floors:
		if f.has("key") or f.has("tower"):
			continue
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		var under: float = t.y - float(f["drop"])
		if under - floor_y < 5.0 or n_pillars > 150:
			continue
		var h: float = under - floor_y
		var rad: float = clampf(minf(s.x, s.z) * 0.14, 0.35, 1.1)
		if _box_free(Vector3(t.x, floor_y + h * 0.5, t.z), Vector3(rad, h * 0.5, rad), f):
			deco.crayon_pillar(Vector3(t.x, floor_y, t.z), h - 0.05, rad, crayon_cols[n_pillars % crayon_cols.size()])
			n_pillars += 1
	# the floor: planks and the play rug, far below
	var board := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1500, 1500)
	board.mesh = pm
	var bmat := ShaderMaterial.new()
	bmat.shader = preload("res://visual/toybox_floor.gdshader")
	bmat.set_shader_parameter("rug_center", Vector2(mid.x, mid.z))
	bmat.set_shader_parameter("rug_half", Vector2(span.x * 0.5 + 150.0, span.z * 0.5 + 150.0))
	board.material_override = bmat
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.position = Vector3(mid.x, floor_y, mid.z)
	add_child(board)
	# four wallpapered walls round the room, windows on the two the sun comes through
	var wall_shader: Shader = preload("res://visual/toybox_wall.gdshader")
	var wmat := ShaderMaterial.new()
	wmat.shader = wall_shader
	wmat.set_shader_parameter("floor_y", floor_y)
	var half: float = maxf(span.x, span.z) * 0.5 + 330.0
	var wh: float = 320.0
	var walls: Array[Dictionary] = [
		{"c": Vector3(mid.x, floor_y + wh * 0.5, mid.z - half), "s": Vector3(half * 2.0, wh, 2.0)},
		{"c": Vector3(mid.x, floor_y + wh * 0.5, mid.z + half), "s": Vector3(half * 2.0, wh, 2.0)},
		{"c": Vector3(mid.x - half, floor_y + wh * 0.5, mid.z), "s": Vector3(2.0, wh, half * 2.0)},
		{"c": Vector3(mid.x + half, floor_y + wh * 0.5, mid.z), "s": Vector3(2.0, wh, half * 2.0)},
	]
	for w: Dictionary in walls:
		var wm := Look.box(w["s"], wmat, w["c"])
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wm)
	_window(Vector3(mid.x + half - 2.0, floor_y + 150.0, mid.z - half * 0.35), -PI * 0.5, 90.0, 110.0)
	_window(Vector3(mid.x + half - 2.0, floor_y + 150.0, mid.z + half * 0.45), -PI * 0.5, 90.0, 110.0)
	_window(Vector3(mid.x - half * 0.4, floor_y + 150.0, mid.z + half - 2.0), PI, 90.0, 110.0)
	# big furniture and toys round the edges of the room, clear of the route
	deco.bed(Vector3(mid.x - half + 60.0, floor_y, mid.z - half * 0.4), PI * 0.5)
	deco.dollhouse(Vector3(mid.x + half - 90.0, floor_y, mid.z + half * 0.5), -PI * 0.5, 4.0)
	deco.nightlight(Vector3(mid.x - half + 25.0, floor_y, mid.z + half * 0.3), 8.0)
	deco.track(Vector3(mid.x + span.x * 0.5 + 90.0, floor_y + 0.2, mid.z), 0.0, 400.0)
	deco.track(Vector3(mid.x + span.x * 0.5 + 96.0, floor_y + 0.2, mid.z), 0.0, 400.0)
	var placed: int = 0
	var tries: int = 0
	while placed < 70 and tries < 900:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 200.0, hi.x + 200.0), floor_y, rng.randf_range(lo.z - 200.0, hi.z + 200.0))
		if not _clear_of(Vector3(p.x, lo.y, p.z), pts, 26.0):
			continue
		var roll: float = rng.randf()
		var yaw: float = rng.randf() * TAU
		if roll < 0.34:
			var sz: float = rng.randf_range(6.0, 16.0)
			deco.abc_block(p + Vector3(0, sz * 0.5, 0), sz, deco.palette(rng.randi()), yaw, rng.randf_range(-0.08, 0.08))
		elif roll < 0.5:
			deco.brick(p, rng.randi_range(2, 4), rng.randi_range(2, 3), deco.palette(rng.randi()), yaw, rng.randf_range(3.0, 5.0))
		elif roll < 0.62:
			deco.ball(p + Vector3(0, 6.0, 0), rng.randf_range(4.0, 8.0), deco.palette(rng.randi()))
		elif roll < 0.72:
			deco.teddy(p, yaw, rng.randf_range(2.5, 5.0))
		elif roll < 0.8:
			deco.duck(p, yaw, rng.randf_range(2.0, 4.0))
		elif roll < 0.9:
			deco.crayon(p + Vector3(0, 1.4, 0), rng.randf_range(18.0, 36.0), 1.4, deco.palette(rng.randi()), yaw)
		else:
			deco.balloon(p, rng.randf_range(20.0, 70.0), deco.palette(rng.randi()))
		placed += 1
	# the air: golden dust in the sun beams and paper confetti, along the whole course
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 14.0, 9.0, absf(here.z - prev.z) * 0.5 + 14.0)
		ToyboxFx.dust(self, c3, ext, 60)
		if i % 2 == 0:
			ToyboxFx.flutter(self, c3 + Vector3(0, 6.0, 0), ext, 24)
		# toys hanging on strings and balloons rising past the course, kept well clear of every floor
		var made: int = 0
		var tr: int = 0
		while made < 7 and tr < 60:
			tr += 1
			var q := Vector3(c3.x + rng.randf_range(-ext.x - 6.0, ext.x + 6.0), c3.y + rng.randf_range(-6.0, 12.0), c3.z + rng.randf_range(-ext.z - 6.0, ext.z + 6.0))
			if not _clear_of(q, pts, 8.0):
				continue
			if rng.randf() < 0.55:
				deco.hanging(q, rng.randi(), rng.randf_range(1.0, 1.8), 70.0)
			else:
				deco.balloon(q - Vector3(0, 14.0, 0), 14.0, deco.palette(rng.randi()))
			made += 1


# ---- machine dressing ---------------------------------------------------------------------------

## A toy flashlight cap and a glowing bead on each post of a laser pointer beam.
func _dress_laser(g: LaserGate) -> void:
	var post_h: float = maxf(g.size.y + 0.8, 1.2)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (g.size.x * 0.5 + 0.18)
		g.add_child(Look.cylinder(0.42, 0.4, Look.flat(YELLOW, 0.4), Vector3(x, post_h * 0.5 + 0.2, 0), 0.26, 12))
		g.add_child(Look.sphere(0.16, Look.flat(RED, 0.3, 0.0, 2.0), Vector3(x, post_h * 0.5 + 0.55, 0)))


## The boxing glove's housing: a painted toy chest round the ram's rod (the glove slides out of its
## face) with a lid stripe and brass corners. `top` / `yaw_deg` as given to kit.piston (world).
func _dress_glove(top: Vector3, size: Vector3, stroke: float, yaw_deg: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var depth: float = stroke + 0.45
	var c: Vector3 = top - Vector3(0, size.y * 0.5, 0) + b * Vector3(0, 0, size.z * 0.5 + depth * 0.5 + 0.02)
	var n := Node3D.new()
	n.transform = Transform3D(b, c)
	add_child(n)
	var red: StandardMaterial3D = Look.flat(RED, 0.5)
	var yellow: StandardMaterial3D = Look.flat(YELLOW, 0.45)
	var h: float = size.y + 1.6
	var w: float = size.x + 0.8
	n.add_child(Look.box(Vector3(0.4, h, depth), red, Vector3(-w * 0.5 + 0.2, 0, 0)))
	n.add_child(Look.box(Vector3(0.4, h, depth), red, Vector3(w * 0.5 - 0.2, 0, 0)))
	n.add_child(Look.box(Vector3(w - 0.8, 0.78, depth), red, Vector3(0, h * 0.5 - 0.39, 0)))
	n.add_child(Look.box(Vector3(w - 0.8, 0.78, depth), red, Vector3(0, -h * 0.5 + 0.39, 0)))
	n.add_child(Look.box(Vector3(w + 0.12, 0.12, depth + 0.12), yellow, Vector3(0, h * 0.5 + 0.06, 0)))
	for sy: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(w - 0.9, 0.16, 0.05), yellow, Vector3(0, sy * (h * 0.5 - 0.39), -depth * 0.5 - 0.03)))
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			n.add_child(Look.sphere(0.12, Look.flat(Color(1.0, 0.85, 0.4), 0.3, 0.8), Vector3(sx * (w * 0.5 - 0.05), sy * (h * 0.5 - 0.05), -depth * 0.5)))


## A red boxing glove on the ram of a piston (moves with it): fist, thumb and cuff.
func _glove_visual(p: Piston) -> void:
	var z: float = -p.size.z * 0.5
	var red: StandardMaterial3D = Look.flat(RED, 0.4)
	var fist := Look.sphere(0.62, red, Vector3(0, 0.05, z - 0.55))
	fist.scale = Vector3(1.05, 0.95, 1.1)
	p.add_child(fist)
	p.add_child(Look.sphere(0.24, red, Vector3(0.56, -0.1, z - 0.4)))
	var cuff := Look.cylinder(0.5, 0.34, Look.flat(CREAM, 0.6), Vector3(0, 0, z + 0.05), -1.0, 14)
	cuff.rotation.x = PI * 0.5
	p.add_child(cuff)


## A giant dice: pips on the four sides of the press (it moves with the press).
func _dress_die(c: Crusher) -> void:
	var s: Vector3 = c.size
	var pip: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.18), 0.4)
	var layouts: Array = [[Vector2(0, 0)], [Vector2(-0.3, -0.25), Vector2(0.3, 0.25)],
		[Vector2(-0.3, -0.25), Vector2(0, 0), Vector2(0.3, 0.25)], [Vector2(-0.3, -0.25), Vector2(0.3, -0.25), Vector2(-0.3, 0.25), Vector2(0.3, 0.25)]]
	for f: int in 4:
		var sx: float = 1.0 if f % 2 == 0 else -1.0
		var on_x: bool = f < 2
		for q: Vector2 in (layouts[f] as Array):
			var d: float = (s.x if on_x else s.z) * 0.5 + 0.02
			var at: Vector3 = Vector3(sx * d, q.y * s.y * 0.8, q.x * s.z * 0.6) if on_x else Vector3(q.x * s.x * 0.6, q.y * s.y * 0.8, sx * d)
			var dot := Look.cylinder(0.17, 0.05, pip, at, -1.0, 12)
			dot.rotation = Vector3(0, 0, PI * 0.5) if on_x else Vector3(PI * 0.5, 0, 0)
			c.add_child(dot)


## A doorway for a warp ring: a stack of three painted blocks each side and a lintel block across.
## `floor_pos` / yaw as given to kit.portal (world).
func _dress_portal(floor_pos: Vector3, yaw_deg: float, col: Color) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), floor_pos)
	add_child(n)
	var cols: Array[Color] = [RED, YELLOW, BLUE]
	for sx: float in [-1.0, 1.0]:
		for i: int in 3:
			n.add_child(Look.box(Vector3(0.7, 1.1, 0.7), Look.flat(cols[(i + (0 if sx < 0.0 else 1)) % 3], 0.45), Vector3(sx * 1.85, 0.55 + 1.1 * float(i), 0)))
	n.add_child(Look.box(Vector3(4.5, 0.6, 0.8), Look.flat(GREEN, 0.45), Vector3(0, 3.6, 0)))
	n.add_child(Look.box(Vector3(3.2, 0.08, 0.08), Look.flat(col, 0.3, 0.0, 2.4), Vector3(0, 3.28, -0.3)))
