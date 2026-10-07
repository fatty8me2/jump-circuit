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


## Local top centre of a landing `sz` deep straight ahead (-z) of `a`, placed so that the jump from
## 0.35 m inside a's front edge needs `pct` of max reach by test_m's measure (to 0.4 m past the near
## edge, scanned in 0.2 m steps: rounded up, so it needs `pct` to `pct` + 3%).
func _ahead(a: Dictionary, pct: float, dy: float, sz: float, dx: float = 0.0) -> Vector3:
	var ac: Vector3 = a["c"]
	var front: float = ac.z - float(a["hz"])
	var m: float = pct * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	var e: float = float(k) * 0.2 - 0.03
	return Vector3(ac.x + dx, ac.y + dy, front + 0.35 - e - sz * 0.5)


## Checkpoint slab facing the next stage's heading (_next_yaw).
func _cp(c: Vector3, size: float = 5.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "goal", 1.0)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	_cp_bursts[cp] = []
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
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3]
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


func _toy_materials() -> void:
	pass


func _stage_18() -> void:
	pass
