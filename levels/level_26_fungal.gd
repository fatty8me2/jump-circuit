extends LevelBase
## 26. MUSHROOM HOLLOW (campaign index 8, MEDIUM tier) - a sunny storybook forest floor seen at beetle
## size: daisies tall as trees, toadstool caps to bounce on, a snail to ride, puffballs that lift you on
## a cloud of spores, a frog that flicks its tongue, acorns that drop, and at the end the GREAT TOADSTOOL.
## Warm golden daylight, mossy greens and toadstool red: nothing like Xeno Wilds' glowing alien night.
## Eighteen stages, seventeen checkpoints. It is a friendly course: the hardest main-path jump is about
## 85% of max reach and every main-path landing is 1.4 m or wider.
##
## PLACEHOLDER HEADER - the stage list is filled in as the stages are built.
##
## Fungal mechanics (own scripts): FungalCap (bullseye bounce caps), FungalPuff (spore-puff lifts),
## FungalSnail (a snail you ride), FungalDrip (falling dewdrops) and FungalTell (a warning toadstool
## for the timed machines). Visuals: visual/fungal_{sky,decor,fx,sway}.gd, fungal_{moss,water,ground,
## ray}.gdshader. Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main
## line + every shortcut. Every wait the bot makes holds for 1.5 s more.

const RED := Color(0.9, 0.22, 0.18)
const ORANGE := Color(0.96, 0.58, 0.2)
const PINKCAP := Color(0.92, 0.5, 0.66)
const YELLOW := Color(0.95, 0.78, 0.3)
const VIOLET := Color(0.66, 0.46, 0.84)
const LEAFG := Color(0.4, 0.66, 0.24)
const CREAM := Color(0.97, 0.92, 0.8)
const GOLD := Color(1.0, 0.82, 0.3)

## Speed (m/s) a runner carries off the end of the dew-leaf slide (measured with the bot).
const SLIDE_SPEED: float = 14.0

## The forest floor, far below the course (a fall is called well before the player reaches it).
const GROUND_Y: float = -13.0

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 16
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 16

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: FungalDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable surface (world): {"top": Vector3, "size": Vector3 (world x/z), "drop": float, "kind": int}
var _floors: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "fungal"
	music_track = "fungal"
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


func _d(v: Vector3) -> Vector3:
	return _b * v


## A local size (x across, z along) turned into world axes (frames only turn in 90 degree steps).
func _sz(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0 else size


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## A walkable moss-and-bark slab (local top centre `c`, sx across, sz along).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, keel: float = 0.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw)
	_floors.append({"top": _w(c), "size": _sz(Vector3(sx, 0, sz)), "drop": thick, "kind": 2})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A spotted toadstool CAP to stand on (round, a flat top painted with spots): local top centre `c`.
func _cap_plat(c: Vector3, r: float, col: Color = RED) -> Dictionary:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.cylinder(r * 0.84, 0.5, Look.flat(col, 0.5), Vector3.ZERO, r, 28))
	body.add_child(Look.cylinder(r * 0.8, 0.1, Look.flat(Color(0.95, 0.86, 0.66), 0.85), Vector3(0, -0.3, 0), r * 0.86, 28))
	var cream: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.82), 0.6)
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.13
	tm.outer_radius = r - 0.03
	tm.rings = 32
	tm.ring_segments = 4
	var rim := Look.mesh_node(tm, cream, Vector3(0, 0.25, 0))
	rim.scale = Vector3(1, 0.2, 1)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(rim)
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0 + float(int(r * 10.0) % 7)
		var sp := Look.cylinder(0.1 + 0.05 * float(i % 3), 0.02, cream, Vector3(cos(a), 0.0, sin(a)) * r * 0.5 + Vector3(0, 0.26, 0), -1.0, 12)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(sp)
	body.position = _w(c) - Vector3(0, 0.25, 0)
	add_child(body)
	_floors.append({"top": _w(c), "size": Vector3(r * 2.0, 0, r * 2.0), "drop": 0.5, "kind": 0})
	return {"c": c, "hx": r, "hz": r, "r": r}


## A broad LEAF to stand on (round, green, a pale midrib): local top centre `c`.
func _leaf_plat(c: Vector3, r: float, col: Color = LEAFG) -> Dictionary:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = 0.3
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.cylinder(r * 0.9, 0.3, Look.flat(col, 0.6), Vector3.ZERO, r, 28))
	var pale: StandardMaterial3D = Look.flat(col.lightened(0.3), 0.6)
	var rib := Look.box(Vector3(0.12, 0.02, r * 1.8), pale, Vector3(0, 0.16, 0))
	rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(rib)
	for sx: float in [-1.0, 1.0]:
		for k: float in [-0.35, 0.25]:
			var vein := Look.box(Vector3(0.07, 0.02, r * 0.8), pale, Vector3(sx * r * 0.28, 0.16, k * r))
			vein.rotation.y = sx * 0.9
			vein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(vein)
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.1
	tm.outer_radius = r - 0.02
	tm.rings = 32
	tm.ring_segments = 4
	var rim := Look.mesh_node(tm, Look.flat(col.lightened(0.18), 0.6), Vector3(0, 0.15, 0))
	rim.scale = Vector3(1, 0.2, 1)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(rim)
	body.position = _w(c) - Vector3(0, 0.15, 0)
	add_child(body)
	_floors.append({"top": _w(c), "size": Vector3(r * 2.0, 0, r * 2.0), "drop": 0.3, "kind": 1})
	return {"c": c, "hx": r, "hz": r, "r": r}


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	_floors.append({"top": _w(top), "size": _sz(Vector3(size.x, 0, size.z)), "drop": size.y, "kind": 2, "tall": true})
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


## The validator's max reach (m) for a plain running jump that lands `dy` higher (test_m's measure).
func _reach(dy: float) -> float:
	var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, _tuning.jump_velocity, -_tuning.max_speed), dy)
	return absf(land.z)


## How far ahead a bounce of launch speed `s` (run kept, 9 m/s) comes down on a surface `dy` higher.
func _pad_reach(s: float, dy: float) -> float:
	var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, s, -_tuning.max_speed), dy)
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
	var d: Dictionary = _blk(c, size, size, "main", 1.2)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var col: Color = GOLD if _cp_world.size() % 2 == 0 else Color(1.0, 0.62, 0.72)
	var fx: Array[GPUParticles3D] = FungalFx.cp_burst(col)
	for p: GPUParticles3D in fx:
		p.position = _w(c) + Vector3(0, 0.6, 0)
		add_child(p)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			# SOUND: fungal_checkpoint - a stage banked: a warm wooden chime and a shower of petals
			WorldAudio.at(self, "fungal_checkpoint", which.global_position, 0.9, 40.0)
			for p: GPUParticles3D in _cp_bursts[which]:
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


## Run to `from`, jump, and fly (position-hold steering) to `to`: for arcs a lift bends.
func _fly(from: Vector3, to: Vector3, gain: float = 1.6, damp: float = 0.45) -> void:
	route.append({"kind": "desert_fly", "jump_from": from, "to": to, "gain": gain, "damp": damp})


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


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	deco = FungalDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 3.0), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16]
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
	if last == stages.size() and false:
		pass
	else:
		# (dev) the finish right after the last stage built
		var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
		var fin: Dictionary = _blk(Vector3(0, 0, -9.0), 5.0, 5.0, "main", 1.2)
		kit.finish(_w(Vector3(0, 0, -9.5)), _yaw)
		_finish_pos = _w(Vector3(0, 0, -9.5))
		_hop(cp0, fin)
		r_walk(_w(Vector3(0, 0, -9.8)))
	_surroundings()
	_fungal_materials()
	if DEV_START > 1:
		set_spawn(origins[DEV_START - 1] + Vector3(0, 0.1, 0), yaws[DEV_START - 1])
		route = route.slice(starts[DEV_START - 1])


# ---- stage 1: Daisy Meadow - a gentle hop chain over caps and leaves -------------------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(12, 2, 12), "main", 0.0, _yaw)
	_floors.append({"top": _w(Vector3.ZERO), "size": Vector3(12, 0, 12), "drop": 2.0, "kind": 2})
	var start: Dictionary = _area(Vector3(0, 0, 0), 6.0, 6.0)
	var d1: Dictionary = _cap_plat(_ahead(start, 0.72, 0.0, 2.0), 1.0, RED)
	var d2: Dictionary = _leaf_plat(_ahead(d1, 0.74, 0.5, 2.0, 0.5), 1.0)
	var d3: Dictionary = _cap_plat(_ahead(d2, 0.76, 0.5, 2.0, -0.5), 1.0, ORANGE)
	var d4: Dictionary = _leaf_plat(_ahead(d3, 0.76, 0.0, 2.2, 0.5), 1.1)
	var cp: Dictionary = _cp(_ahead(d4, 0.76, 0.0, 5.0, -0.5))
	_hop(start, d1)
	_hop(d1, d2)
	_hop(d2, d3)
	_hop(d3, d4)
	_hop(d4, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Springcaps - bounce on the bullseye caps up the hill -----------------------------------

## A bouncy cap (FungalCap) at local top centre `c`.
func _spring_cap(c: Vector3, r: float = 1.6, col: Color = RED) -> FungalCap:
	var cap := FungalCap.new()
	cap.radius = r
	cap.tint = col
	cap.stalk = 0.0
	cap.position = _w(c)
	add_child(cap)
	_floors.append({"top": _w(c), "size": Vector3(r * 2.0, 0, r * 2.0), "drop": 0.6, "kind": 0})
	return cap


func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var s_hi: float = 21.0
	var dy1: float = 4.6
	var dy2: float = 4.2
	var cap1_c: Vector3 = _ahead(cp0, 0.70, 0.0, 3.2)
	var cap1: FungalCap = _spring_cap(cap1_c, 1.6, RED)
	var l1_c := Vector3(cap1_c.x, cap1_c.y + dy1, cap1_c.z - _pad_reach(s_hi, dy1))
	var l1: Dictionary = _blk(l1_c, 5.0, 5.0, "alt", 0.8)
	var cap2_c: Vector3 = _ahead(l1, 0.70, 0.0, 3.2)
	var cap2: FungalCap = _spring_cap(cap2_c, 1.6, ORANGE)
	var cp_c := Vector3(cap2_c.x, cap2_c.y + dy2, cap2_c.z - _pad_reach(s_hi, dy2))
	var cp: Dictionary = _cp(cp_c)
	_hop(cp0, _area(cap1_c, 1.6, 1.6))
	r_pad(_w(cap1_c), _w(l1_c))
	r_walk(_w(Vector3(l1_c.x, l1_c.y, l1_c.z - 1.0)))
	_hop(l1, _area(cap2_c, 1.6, 1.6))
	r_pad(_w(cap2_c), _w(cp_c))
	r_checkpoint()
	cap1.name = "CapA"
	cap2.name = "CapB"
	return cp["c"]


# ---- stage 3: Bark Run - wall-run the fallen bark, mantle the stump -------------------------------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _leaf_plat(_ahead(cp0, 0.74, 0.0, 2.2), 1.1)
	var w2: Dictionary = _blk(_ahead(p1, 0.76, 0.0, 2.4, 0.4), 2.4, 2.4, "alt", 0.8)
	var wc: Vector3 = w2["c"]
	var f: float = wc.z - 1.2
	kit.wallrun(_w(Vector3(wc.x + 2.3, wc.y + 1.2, f - 9.5)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var land: Dictionary = _blk(Vector3(wc.x - 0.6, wc.y, f - 22.9), 2.6, 3.2, "alt", 0.8)
	var lc: Vector3 = land["c"]
	var front: float = lc.z - 1.6
	var ledge_top := Vector3(lc.x, lc.y + 3.3, front - 1.6 - 1.2)
	var stump: Dictionary = _ledge(ledge_top, Vector3(3.0, 9.0, 2.4))
	var cp: Dictionary = _cp(_ahead(stump, 0.76, 0.0, 5.0, -lc.x))
	_hop(cp0, p1)
	_hop(p1, w2)
	r_wallrun(_w(Vector3(wc.x + 0.3, wc.y, f + 0.35)), _w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 3.6)),
		_w(Vector3(wc.x + 1.8, wc.y + 1.4, f - 14.5)), _w(Vector3(wc.x - 0.6, wc.y, f - 22.5)))
	r_walk(_w(Vector3(lc.x, lc.y, front + 0.9)))
	r_mantle(_w(Vector3(lc.x, lc.y, front + 0.35)), _w(ledge_top + Vector3(0, 0, 0.3)))
	_hop(stump, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- shared dressing and machine helpers --------------------------------------------------------------

## Fork signpost: two wooden posts with a glowing toadstool on each and a strip on the floor in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		add_child(Look.cylinder(0.07, 1.6, Look.flat(Color(0.5, 0.34, 0.2), 0.9), _w(p + Vector3(sx * 1.1, 0.8, 0)), 0.06, 8))
		var cap := Look.sphere(0.28, Look.flat(col, 0.5, 0.0, 0.6), _w(p + Vector3(sx * 1.1, 1.7, 0)))
		cap.scale = Vector3(1.0, 0.6, 1.0)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cap)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.5)), _sz(Vector3(1.2, 0.05, 0.25)), col)


## A dewdrop: hangs over local floor point `c`. `hit` = the course time (relative to the bot's start)
## at which the drop should become deadly; the phase is set from it.
func _drip(c: Vector3, height: float, period: float, hit: float) -> FungalDrip:
	var d := FungalDrip.new()
	d.drop_height = height
	d.period = period
	var c0: float = d.swell + d.fall_time() * 0.88
	d.phase = fposmod((c0 - hit) / period, 1.0)
	d.position = _w(c)
	add_child(d)
	return d


## True when none of the listed drops is deadly over its window: [[drip, from, to], ...] (seconds from now).
static func _drips_ok(spec: Array) -> bool:
	for e: Array in spec:
		if not (e[0] as FungalDrip).clear_over(Game.course_time, float(e[1]), float(e[2])):
			return false
	return true


## Re-skin a SurfacePlatform's slick sheet as a dew-covered leaf (glossy green, water sheen).
func _dew_leaf(sp: SurfacePlatform) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.74, 0.34)
	mat.roughness = 0.06
	mat.metallic = 0.1
	mat.metallic_specular = 0.9
	mat.rim_enabled = true
	mat.rim = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.9, 0.6)
	mat.emission_energy_multiplier = 0.15
	for c: Node in sp.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = mat
			break
	# a pale midrib down the sheet, and water beads
	var rib := Look.box(Vector3(0.1, 0.03, sp.size.z * 0.98), Look.flat(Color(0.75, 0.92, 0.6), 0.4), Vector3(0, sp.size.y * 0.5 + 0.02, 0))
	rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.add_child(rib)
	for i: int in 6:
		var bead := Look.sphere(0.12, Look.flat(Color(0.8, 0.95, 1.0, 0.8), 0.05, 0.0, 0.3), Vector3(kit.rng.randf_range(-1.0, 1.0), sp.size.y * 0.5 + 0.03, (float(i) / 5.0 - 0.5) * sp.size.z * 0.9))
		bead.scale = Vector3(1.0, 0.4, 1.0)
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.add_child(bead)


## Solve the launch speed (12..26) whose bounce comes down `dist` m ahead on a surface `dy` higher.
func _solve_strength(dy: float, dist: float) -> float:
	var lo: float = 12.0
	var hi: float = 26.0
	for i: int in 24:
		var mid: float = (lo + hi) * 0.5
		if _pad_reach(mid, dy) < dist:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


# ---- stage 4: Dewdrop Valley (BRANCH) - the dew-leaf slide | stepping leaves under dripping dew -------
# [shortcut: two springcaps down the middle]

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.78, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT: a slide down a wet leaf, a jump off its lip onto a plank, then up to the merge
	var pitch: float = -20.0
	var slide_len: float = 12.0
	var drop: float = slide_len * sin(deg_to_rad(-pitch))
	var run: float = slide_len * cos(deg_to_rad(-pitch))
	var sx: float = -3.5
	var dew: SurfacePlatform = kit.slick(_w(Vector3(sx, -0.05 - drop * 0.5, f0 - 0.1 - run * 0.5)), Vector3(2.8, 0.4, slide_len), _yaw, pitch)
	_dew_leaf(dew)
	var lip_y: float = -0.05 - drop
	var lip_z: float = f0 - 0.1 - run
	var v_lip: float = SLIDE_SPEED
	var lp: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, _tuning.jump_velocity, -v_lip), -0.6)
	var gap: float = 0.62 * absf(lp.z) - 0.75
	var plank_len: float = 5.0
	var plank: Dictionary = _blk(Vector3(sx, lip_y - 0.6, lip_z - gap - plank_len * 0.5), 3.0, plank_len, "alt", 0.8)
	var mc: Vector3 = _ahead(plank, 0.74, 1.25, 3.0, -sx)
	var merge: Dictionary = _blk(mc, 11.0, 3.0)
	# RIGHT: three stepping platforms (cap, leaf, cap) down to the merge, dew dripping on the last two
	var t_total: float = f0 - (mc.z + 1.5)
	var dia: Array[float] = [2.2, 2.6, 2.2]
	var gap_r: float = (t_total - 7.0) / 4.0
	var steps: Array[Dictionary] = []
	var zc: float = f0
	for i: int in 3:
		var cz: float = zc - gap_r - dia[i] * 0.5
		var cc := Vector3(3.5, -0.875 * float(i + 1), cz)
		match i:
			0:
				steps.append(_cap_plat(cc, dia[i] * 0.5, ORANGE))
			1:
				steps.append(_leaf_plat(cc, dia[i] * 0.5))
			_:
				steps.append(_cap_plat(cc, dia[i] * 0.5, PINKCAP))
		zc = cz - dia[i] * 0.5
	print("S4 t_total ", t_total, " gap_r ", gap_r, " pct ", (gap_r + 0.75) / _reach(-0.875), " slide gap ", gap, " mc ", mc)
	var arrive: Array[float] = [1.0, 1.9, 2.9]
	var d1: FungalDrip = _drip((steps[1]["c"] as Vector3), 7.0, 5.5, arrive[1] + 2.7)
	var d2: FungalDrip = _drip((steps[2]["c"] as Vector3), 7.0, 5.5, arrive[2] + 2.7)
	# SHORTCUT: springcap A on the fork's front, springcap B halfway, both bounce down the middle
	var a_c: Vector3 = _ahead(_area(fc, 5.5, 1.5), 0.74, 0.0, 3.2)
	var b_z: float = (a_c.z + mc.z) * 0.5
	var b_c := Vector3(0.0, a_c.y - 1.5, b_z)
	var s_ab: float = _solve_strength(-1.5, a_c.z - b_z)
	var s_bm: float = _solve_strength(mc.y - b_c.y, b_z - mc.z)
	var cap_a: FungalCap = _spring_cap(a_c, 1.6, RED)
	cap_a.high = s_ab
	cap_a.low = s_ab - 7.0
	var cap_b: FungalCap = _spring_cap(b_c, 1.6, YELLOW)
	cap_b.high = s_bm
	cap_b.low = s_bm - 7.0
	var cp: Dictionary = _cp(_ahead(merge, 0.76, 0.0, 5.0))
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z + 0.2)))
		_hop(_area(fc, 5.5, 1.5), _area(a_c, 1.6, 1.6))
		r_pad(_w(a_c), _w(b_c))
		r_pad(_w(b_c), _w(mc))
	elif route_variant == 1:
		r_walk(_w(Vector3(sx, 0, fc.z + 0.4)))
		r_walk(_w(Vector3(sx, 0, f0 - 1.2)))
		r_jump(_w(Vector3(sx, lip_y, lip_z + 0.35)), _w((plank["c"] as Vector3) + Vector3(0, 0, plank_len * 0.5 - 1.0)))
		route[route.size() - 1]["speed"] = v_lip
		r_walk(_w(Vector3(sx, lip_y - 0.6, (plank["c"] as Vector3).z - plank_len * 0.5 + 0.8)))
		_hop(plank, merge, Vector3(sx, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.5, 0, fc.z + 0.4)))
		_wait(func() -> bool: return _drips_ok([[d1, arrive[1] - 0.5, arrive[1] + 0.7 + 1.5], [d2, arrive[2] - 0.5, arrive[2] + 0.7 + 1.5]]),
			_w(Vector3(3.5, 0, fc.z + 0.4)))
		var prev: Dictionary = _area(Vector3(3.5, 0, fc.z), 1.5, 1.5)
		for st: Dictionary in steps:
			_hop(prev, st)
			prev = st
		_hop(prev, merge, Vector3(3.5, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_sign(Vector3(sx, 0, fc.z + 1.2), ORANGE)
	_sign(Vector3(3.5, 0, fc.z + 1.2), Color(0.5, 0.7, 1.0))
	_sign(Vector3(0, 0, fc.z + 1.2), GOLD)
	return cp["c"]


# ---- stage 5: Snail Ferry - ride the snail across the stream ------------------------------------------------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var d1: Dictionary = _blk(_ahead(cp0, 0.76, 0.0, 4.0), 4.0, 4.0, "alt", 0.8)
	var dc: Vector3 = d1["c"]
	var travel: float = 22.0
	var snail := FungalSnail.new()
	snail.size = Vector3(2.8, 0.4, 2.8)
	var pts: Array[Vector3] = [Vector3.ZERO, _d(Vector3(0, 0, -travel))]
	snail.points = pts
	snail.period = 16.0
	snail.dwell = 0.12
	var start := Vector3(dc.x, dc.y, dc.z - 2.0 - 1.4 - 1.4)
	snail.position = _w(start) - Vector3(0, 0.2, 0)
	add_child(snail)
	var d2c := Vector3(dc.x, dc.y, start.z - travel - 1.4 - 1.4 - 2.0)
	var d2: Dictionary = _blk(d2c, 4.0, 4.0, "alt", 0.8)
	var cp: Dictionary = _cp(_ahead(d2, 0.76, 0.0, 5.0))
	_hop(cp0, d1)
	r_walk(_w(Vector3(dc.x, dc.y, dc.z - 0.2)))
	route.append({"kind": "candy_board", "from": _w(Vector3(dc.x, dc.y, dc.z - 1.5)), "cars": [snail], "reach": 3.4, "lead": 0.45, "local": Vector3(0, 0.1, 0)})
	var end_w: Vector3 = _w(start + Vector3(0, 0, -travel))
	route.append({"kind": "candy_ride", "stand": Vector3(0, 0.1, 0), "to": _w(d2c), "until": func() -> bool:
		return Vector2(snail.global_position.x - end_w.x, snail.global_position.z - end_w.z).length() < 0.35})
	r_walk(_w(Vector3(d2c.x, d2c.y, d2c.z - 1.0)))
	_hop(d2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the twig the snail crawls along, over the stream
	var twig_len: float = travel + 8.0
	var twig_mid: Vector3 = _w(Vector3(dc.x, start.y - 2.4, start.z - travel * 0.5))
	deco.fallen_log(twig_mid - Vector3(0, 0.55, 0), twig_len, 0.55, deg_to_rad(_yaw) + PI * 0.5)
	return cp["c"]


# ---- stage 6: Spore Lift - the puffball lifts you on a cloud of spores, twice ---------------------------------

## A puffball shelf at local ground point `c` (its walkable top is at c): the column rises from its middle.
func _puff(c: Vector3, height: float = 9.0, period: float = 8.0, phase: float = 0.0) -> FungalPuff:
	var p := FungalPuff.new()
	p.height = height
	p.period = period
	p.phase = phase
	p.position = _w(c)
	add_child(p)
	var r: float = p.radius + p.shelf
	_floors.append({"top": _w(c), "size": Vector3(r * 2.0, 0, r * 2.0), "drop": 0.5, "kind": 0})
	return p


func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var pr: float = 3.0
	var pf1_c: Vector3 = _ahead(cp0, 0.74, 0.0, pr * 2.0)
	var pf1: FungalPuff = _puff(pf1_c, 9.0, 8.0, 0.0)
	var ledge_a: Dictionary = _blk(Vector3(pf1_c.x, pf1_c.y + 8.0, pf1_c.z - pr - 1.2 - 2.5), 5.0, 5.0, "alt", 0.8)
	var la: Vector3 = ledge_a["c"]
	var pf2_c: Vector3 = _ahead(ledge_a, 0.76, 0.0, pr * 2.0)
	var pf2: FungalPuff = _puff(pf2_c, 9.0, 8.0, 0.5)
	var cp_c := Vector3(pf2_c.x, pf2_c.y + 7.0, pf2_c.z - pr - 1.2 - 2.5)
	var cp: Dictionary = _cp(cp_c)
	_hop(cp0, _area(pf1_c, pr, pr))
	_lift(pf1, pf1_c, pr, la, 8.4)
	r_walk(_w(Vector3(la.x, la.y, la.z - 0.5)))
	_hop(ledge_a, _area(pf2_c, pr, pr))
	_lift(pf2, pf2_c, pr, cp_c, 7.4)
	r_checkpoint()
	return cp["c"]


## Bot: stand off to the side of the column on the shelf until the puffball will keep blowing long enough,
## step in, ride the spores up above `above` and fly onto the ledge centre `to`.
func _lift(pf: FungalPuff, c: Vector3, shelf_r: float, to: Vector3, above: float) -> void:
	var stand: Vector3 = _w(Vector3(c.x + (shelf_r - 0.5), c.y, c.z + 0.3))
	var mid: Vector3 = _w(c)
	r_walk(stand)
	_wait(func() -> bool: return pf.on_over(Game.course_time, 0.5, 4.0), stand)
	r_walk(mid)
	var top_y: float = _w(Vector3(0, c.y + above, 0)).y
	route.append({"kind": "desert_fly", "to": mid, "until": func() -> bool: return player.global_position.y > top_y})
	route.append({"kind": "desert_fly", "to": _w(to)})


# ---- stage 7: Fairy Ring (BRANCH) - run up the bark | step into the fairy ring and pop out on the branch -----
# [shortcut: a little ring on a cap by the fork]

## z of the centre of a landing `sz` deep reached from a platform whose far (front) edge is at z=`front`, by
## a jump needing `pct` of max reach (the same rule as _ahead).
func _adv_z(front: float, pct: float, dy: float, sz: float) -> float:
	var m: float = pct * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	var e: float = float(k) * 0.2 - 0.03
	return front + 0.35 - e - sz * 0.5


## A fairy ring round a warp ring: a glowing circle on the floor and a horseshoe of white toadstools behind.
## `floor_pos` / yaw as given to kit.portal (world).
func _dress_ring(floor_pos: Vector3, yaw_deg: float, col: Color) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 1.7
	tm.outer_radius = 1.82
	tm.rings = 40
	tm.ring_segments = 5
	var glow := Look.mesh_node(tm, Look.flat(col, 0.4, 0.0, 1.6), floor_pos + Vector3(0, 0.05, 0))
	glow.scale = Vector3(1, 0.2, 1)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	for i: int in 9:
		var a: float = deg_to_rad(15.0 + 150.0 * float(i) / 8.0)
		var p: Vector3 = floor_pos + basis * Vector3(cos(a) * 2.05, 0.0, sin(a) * 2.05 + 0.2)
		deco.toadstool(p, 0.55 + 0.25 * float(i % 3) / 2.0, 0.3 + 0.08 * float(i % 2), Color(0.97, 0.93, 0.85), false)


## A slab of pale birch bark behind a wall-run panel (visual only): local centre, size (along z, height, thick).
func _bark_slab(c: Vector3, size: Vector3, side: float) -> void:
	var bark: StandardMaterial3D = Look.flat(Color(0.88, 0.84, 0.76), 0.9)
	var n := Look.box(_sz(Vector3(size.z, size.y, size.x)), bark, _w(c + Vector3(side * (size.z * 0.5 + 0.35), 0, 0)))
	add_child(n)
	var dark: StandardMaterial3D = Look.flat(Color(0.2, 0.17, 0.15), 0.9)
	for i: int in 7:
		var z: float = c.z + (kit.rng.randf() - 0.5) * size.x * 0.9
		var y: float = c.y + (kit.rng.randf() - 0.5) * size.y * 0.8
		var mark := Look.box(_sz(Vector3(0.05, 0.2, 1.4)), dark, _w(Vector3(c.x + side * 0.0, y, z)) + _d(Vector3(-side * (-0.1), 0, 0)))
		mark.position = _w(Vector3(c.x - side * 0.3, y, z))
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)


func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# RIGHT: run the first bark, kick across to the second, run it, kick onto a cap, hop on to the merge
	kit.wallrun(_w(Vector3(6.1, 1.2, f0 - 7.0)), Vector3(12.0, 6.5, 0.6), _yaw + 90.0)
	kit.wallrun(_w(Vector3(1.5, 3.6, f0 - 17.5)), Vector3(9.0, 6.5, 0.6), _yaw + 90.0)
	var pb: Dictionary = _cap_plat(Vector3(3.6, 0.0, f0 - 27.6), 1.1, ORANGE)
	var pb2: Dictionary = _leaf_plat(Vector3(3.6, 0.0, _adv_z(f0 - 27.6 - 1.1, 0.78, 0.0, 2.2)), 1.1)
	var mz: float = _adv_z((pb2["c"] as Vector3).z - 1.1, 0.78, 0.0, 3.0)
	var merge: Dictionary = _blk(Vector3(0, 0, mz), 11.0, 3.0)
	# LEFT: the fairy ring on the fork sends you up onto a long branch, then three drops to the merge
	var f1: float = 0.0
	var z_a: float = _adv_z(f1, 0.78, -1.5, 2.2)
	var z_b: float = _adv_z(z_a - 1.1, 0.78, -1.5, 2.2)
	var z_m: float = _adv_z(z_b - 1.1, 0.78, -1.5, 3.0)
	var hi_end: float = mz - z_m
	var hi_len: float = maxf((f0 - 6.5) - hi_end, 5.0)
	var hi: Dictionary = _blk(Vector3(-3.5, 4.5, f0 - 6.5 - hi_len * 0.5), 2.2, hi_len, "alt", 0.6)
	var la: Dictionary = _leaf_plat(Vector3(-3.5, 3.0, hi_end + z_a), 1.1)
	var lb: Dictionary = _cap_plat(Vector3(-3.5, 1.5, hi_end + z_b), 1.1, PINKCAP)
	var door: WarpPortal = kit.portal(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, _w(Vector3(-3.5, 4.5, f0 - 7.2)), _yaw, 7.0)
	_dress_ring(_w(Vector3(-3.5, 0, fc.z - 0.6)), _yaw, Color(1.0, 0.7, 0.4))
	_dress_ring(_w(Vector3(-3.5, 4.5, f0 - 7.2)), _yaw, Color(0.5, 0.8, 1.0))
	# SHORTCUT: a little cap by the fork with its own ring, out at the merge
	var sp: Dictionary = _cap_plat(_ahead(_area(fc, 5.5, 1.5), 0.88, 0.0, 2.0), 1.0, VIOLET)
	var spc: Vector3 = sp["c"]
	var sdoor: WarpPortal = kit.portal(_w(spc + Vector3(0, 0, -0.1)), _yaw, _w(Vector3(0.0, 0, mz + 0.9)), _yaw, 6.0)
	_dress_ring(_w(Vector3(0.0, 0, mz + 0.9)), _yaw, Color(0.5, 0.8, 1.0))
	var cp: Dictionary = _cp(_ahead(merge, 0.78, 0.0, 5.0))
	print("S7 hi_len ", hi_len, " mz ", mz, " pct pb2 ", 0.78)
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z + 0.2)))
		_hop(_area(fc, 5.5, 1.5), sp, Vector3(0, 0, 0.35))
		r_portal(_w(spc + Vector3(0, 0, -0.5)), sdoor.exit_point())
	elif route_variant == 1:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.6)))
		r_portal(_w(Vector3(-3.5, 0, fc.z - 0.9)), door.exit_point())
		r_walk(_w(Vector3(-3.5, 4.5, hi_end + 0.9 + z_a * 0.0 + 0.0)))
		_hop(hi, la)
		_hop(la, lb)
		_hop(lb, merge, Vector3(-3.5, 0, 0.6))
	else:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.6)))
		r_wallrun(_w(Vector3(4.2, 0, f0 + 0.35)), _w(Vector3(5.6, 1.4, f0 - 3.2)), _w(Vector3(5.6, 1.4, f0 - 10.6)), _w(Vector3(2.0, 4.4, f0 - 14.4)))
		r_wallrun(Vector3.ZERO, _w(Vector3(2.0, 4.4, f0 - 14.4)), _w(Vector3(2.0, 4.4, f0 - 19.6)), _w(Vector3(3.6, 0.0, f0 - 27.4)), true, true)
		_hop(pb, pb2)
		_hop(pb2, merge, Vector3(3.6, 0, 0.6))
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, fc.z + 1.2), Color(1.0, 0.7, 0.4))
	_sign(Vector3(3.6, 0, fc.z + 1.2), Color(0.9, 0.9, 0.95))
	_bark_slab(Vector3(6.1, 1.2, f0 - 7.0), Vector3(12.0, 6.5, 0.6), 1.0)
	_bark_slab(Vector3(1.5, 3.6, f0 - 17.5), Vector3(9.0, 6.5, 0.6), -1.0)
	return cp["c"]


# ---- stage 8: Acorn Drop - walk the root under two falling acorns, mantle the stump ------------------------------

## A falling acorn: the crusher press, dressed (a glossy nut under a scaly cap) with a warning toadstool cluster
## on the top of its frame that blinks faster for the last 1.2 s before it drops.
func _acorn_press(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var c: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	for ch: Node in c.get_children():
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).visible = false
	var nut := Look.sphere(1.0, Look.flat(Color(0.72, 0.5, 0.24), 0.3), Vector3(0, -0.35, 0))
	nut.scale = Vector3(size.x * 0.46, 0.75, size.z * 0.5)
	c.add_child(nut)
	var cap_mat: StandardMaterial3D = Look.flat(Color(0.5, 0.36, 0.2), 0.85)
	c.add_child(Look.cylinder(size.x * 0.55, 0.42, cap_mat, Vector3(0, 0.4, 0), size.x * 0.5, 20))
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var scale_n := Look.box(Vector3(0.45, 0.1, 0.1), Look.flat(Color(0.4, 0.28, 0.15), 0.9), Vector3(cos(a), 0.62, sin(a)) * size.x * 0.42)
		scale_n.rotation.y = -a + PI * 0.5
		c.add_child(scale_n)
	c.add_child(Look.cylinder(0.1, 0.35, Look.flat(Color(0.35, 0.26, 0.14), 0.9), Vector3(0, 0.8, 0), 0.07, 6))
	var h: float = lift + size.y + 1.5
	var tell := FungalTell.new()
	tell.position = _w(floor_c) + Vector3(0, h + 0.4, 0)
	tell.left = func(t: float) -> float:
		var u: float = fposmod(t / c.period + c.phase, 1.0)
		return ((0.5 - u) if u < 0.5 else (1.5 - u)) * c.period
	add_child(tell)
	return c


func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _cap_plat(_ahead(cp0, 0.76, 0.0, 2.2), 1.1, YELLOW)
	var walk: Dictionary = _blk(_ahead(p1, 0.78, 0.0, 16.0, 0.0), 1.8, 16.0, "alt", 0.6)
	var wc: Vector3 = walk["c"]
	var w0: float = wc.z + 8.0
	var period: float = 6.0
	var t1: float = 2.4
	var t2: float = 3.0
	var c1: Crusher = _acorn_press(Vector3(wc.x, wc.y, w0 - 5.0), Vector3(2.2, 1.2, 2.0), 3.2, period, fposmod(0.92 - (t1 - 0.4) / period, 1.0))
	var c2: Crusher = _acorn_press(Vector3(wc.x, wc.y, w0 - 10.5), Vector3(2.2, 1.2, 2.0), 3.2, period, fposmod(0.92 - (t2 - 0.4) / period, 1.0))
	var ledge_top := Vector3(wc.x, wc.y + 3.3, w0 - 16.0 - 1.2 - 1.1)
	var ld: Dictionary = _ledge(ledge_top, Vector3(3.6, 9.0, 2.2))
	var cp: Dictionary = _cp(_ahead(ld, 0.78, 0.0, 5.0, -wc.x))
	_wait(func() -> bool: return _press_ok(c1, t1 - 0.3, t1 + 0.3 + 1.5) and _press_ok(c2, t2 - 0.3, t2 + 0.3 + 1.5))
	_hop(cp0, p1)
	_hop(p1, walk, Vector3(0, 0, 7.0))
	r_walk(_w(Vector3(wc.x, wc.y, w0 - 16.0 + 0.9)))
	r_mantle(_w(Vector3(wc.x, wc.y, w0 - 16.0 + 0.35)), _w(ledge_top + Vector3(0, 0, 0.5)))
	_hop(ld, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Frog Pond - hop the lily pads while the frogs flick their tongues --------------------------------------

## A frog on the left of lily pad `pad` (area dict, local) whose tongue flicks across the pad to the right.
## Returns the tongue's Piston. `hit_phase` offsets the cycle.
func _frog(pad: Dictionary, period: float, phase: float) -> Piston:
	var pc: Vector3 = pad["c"]
	var pr: float = float(pad["r"])
	var size := Vector3(1.6, 1.3, 1.2)
	var x_r: float = pc.x - pr - 0.3 - size.z * 0.5
	var p := Piston.new()
	p.size = size
	p.stroke = 3.0
	p.period = period
	p.phase = phase
	p.strength = 10.0
	p.rotation_degrees.y = _yaw - 90.0
	p.position = _w(Vector3(x_r, pc.y + 1.35 - size.y * 0.5, pc.z))
	add_child(p)
	for ch: Node in p.get_children():
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).visible = false
	# the sticky pink tip of the tongue
	var tip := Look.sphere(1.0, Look.flat(Color(0.95, 0.45, 0.55), 0.3), Vector3.ZERO)
	tip.scale = Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.6)
	p.add_child(tip)
	for sx: float in [-0.4, 0.3]:
		p.add_child(Look.sphere(0.12, Look.flat(Color(0.8, 0.28, 0.4), 0.4), Vector3(sx, 0.35, -0.45)))
	var mouth_l := Vector3(x_r - size.z * 0.5 - 1.0, pc.y + 0.65, pc.z)
	var tongue := FungalTongue.new()
	tongue.piston = p
	tongue.mouth = _w(mouth_l)
	add_child(tongue)
	_frog_body(_w(mouth_l + Vector3(-1.1, -0.65, 0)), _yaw - 90.0)
	var tell := FungalTell.new()
	tell.position = _w(mouth_l + Vector3(-1.1, 0.55, 1.3))
	tell.clip = "fungal_frog_croak"
	tell.left = func(t: float) -> float:
		var u: float = fposmod(t / p.period + p.phase, 1.0)
		return ((0.45 - u) if u < 0.45 else (1.45 - u)) * p.period
	add_child(tell)
	return p


## A cartoon frog sitting on the ground at world `pos`, facing along `yaw_deg` (its -Z), mouth open a little.
func _frog_body(pos: Vector3, yaw_deg: float) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	add_child(n)
	var green: StandardMaterial3D = Look.flat(Color(0.4, 0.72, 0.28), 0.5)
	var belly: StandardMaterial3D = Look.flat(Color(0.93, 0.95, 0.7), 0.6)
	var body := Look.sphere(1.0, green, Vector3(0, 0.75, 0.3))
	body.scale = Vector3(1.0, 0.75, 1.15)
	n.add_child(body)
	var chest := Look.sphere(1.0, belly, Vector3(0, 0.55, -0.35))
	chest.scale = Vector3(0.7, 0.5, 0.6)
	n.add_child(chest)
	var head := Look.sphere(0.62, green, Vector3(0, 0.95, -0.75))
	head.scale = Vector3(1.15, 0.8, 1.0)
	n.add_child(head)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.sphere(0.24, green, Vector3(sx * 0.42, 1.38, -0.7)))
		n.add_child(Look.sphere(0.15, Look.flat(Color(0.97, 0.97, 0.9), 0.3), Vector3(sx * 0.44, 1.42, -0.84)))
		n.add_child(Look.sphere(0.08, Look.flat(Color(0.05, 0.05, 0.06), 0.2), Vector3(sx * 0.45, 1.43, -0.95)))
		var leg := Look.sphere(1.0, green, Vector3(sx * 0.95, 0.4, 0.55))
		leg.scale = Vector3(0.28, 0.5, 0.7)
		n.add_child(leg)
	n.add_child(Look.box(Vector3(0.9, 0.05, 0.05), Look.flat(Color(0.2, 0.3, 0.12), 0.5), Vector3(0, 0.83, -1.3)))


func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var l1: Dictionary = _leaf_plat(_ahead(cp0, 0.74, 0.0, 2.8), 1.4)
	var l2: Dictionary = _leaf_plat(_ahead(l1, 0.76, 0.0, 2.8, 0.0), 1.4)
	var l3: Dictionary = _leaf_plat(_ahead(l2, 0.76, 0.5, 2.8, 0.0), 1.4)
	var l4: Dictionary = _leaf_plat(_ahead(l3, 0.76, 0.0, 2.8, 0.0), 1.4)
	var cp: Dictionary = _cp(_ahead(l4, 0.76, 0.0, 5.0))
	var period: float = 6.0
	var ph2: float = 0.0
	var r2: Piston = _frog(l2, period, ph2)
	var r3: Piston = _frog(l3, period, fposmod(ph2 - 1.0 / period, 1.0))
	var t2: float = 1.0
	var t3: float = 2.0
	_hop(cp0, l1)
	_wait(func() -> bool: return _ram_clear(r2, t2 - 0.3, t2 + 0.4 + 1.5) and _ram_clear(r3, t3 - 0.3, t3 + 0.4 + 1.5), _w((l1["c"] as Vector3) + Vector3(0, 0, 0.2)))
	_hop(l1, l2)
	_hop(l2, l3)
	_hop(l3, l4)
	_hop(l4, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the pond under the pads, with lilies floating on it
	var pc: Vector3 = _w((l2["c"] as Vector3) + Vector3(0, -7.5, 1.5))
	deco.pond(pc, 24.0)
	for i: int in 9:
		var a: float = kit.rng.randf() * TAU
		var d: float = kit.rng.randf_range(4.0, 20.0)
		deco.lily(pc + Vector3(cos(a) * d, 0.12, sin(a) * d), kit.rng.randf_range(1.4, 2.6), kit.rng.randf() < 0.4)
	return cp["c"]


# ---- stage 10: Hollow Log - the sunbeam on the plank, then wall-run up the inside of the hollow trunk -----------------

## Re-skin a laser gate as a SUNBEAM focused by two dew-lens flowers: a golden-white beam, a dewdrop bead on a
## stalk at each end instead of the dark posts. It still switches on and off on the clock with a long tell
## (the guide line flickers for `warn` s, and the hum winds up).
func _dress_sunbeam(g: LaserGate) -> void:
	g.warn = 0.95
	var beam: MeshInstance3D = g.get("_beam") as MeshInstance3D
	var guide: MeshInstance3D = g.get("_guide") as MeshInstance3D
	var haze: Variant = g.get("_haze")
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(1.0, 0.82, 0.3)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.75, 0.25)
	bm.emission_energy_multiplier = 3.0
	beam.material_override = bm
	if beam.get_child_count() >= 2:
		var core := beam.get_child(0) as MeshInstance3D
		var sleeve := beam.get_child(1) as MeshInstance3D
		var cm := StandardMaterial3D.new()
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.albedo_color = Color(1.0, 0.97, 0.85)
		cm.emission_enabled = true
		cm.emission = Color(1.0, 0.95, 0.8)
		cm.emission_energy_multiplier = 4.0
		core.material_override = cm
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.albedo_color = Color(1.0, 0.65, 0.15, 0.22)
		sleeve.material_override = sm
	var gm: StandardMaterial3D = g.get("_guide_mat") as StandardMaterial3D
	if gm != null:
		gm.albedo_color = Color(1.0, 0.8, 0.3, gm.albedo_color.a)
	var lamp: OmniLight3D = g.get("_lamp") as OmniLight3D
	if lamp != null:
		lamp.light_color = Color(1.0, 0.75, 0.3)
	for c: Node in g.get_children():
		if c is MeshInstance3D and c != beam and c != guide and c != haze:
			(c as MeshInstance3D).visible = false
	var green: StandardMaterial3D = Look.flat(Color(0.36, 0.62, 0.24), 0.8)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.92, 1.0, 0.6)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.rim_enabled = true
	glass.rim = 0.9
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.85, 0.5)
	glass.emission_energy_multiplier = 0.6
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (g.size.x * 0.5 + 0.35)
		g.add_child(Look.cylinder(0.08, 6.0, green, Vector3(x, -3.0 - 0.2, 0), 0.05, 8))
		var leaf := Look.sphere(1.0, green, Vector3(x + sx * 0.5, -1.2, 0))
		leaf.scale = Vector3(0.55, 0.05, 0.25)
		leaf.rotation.z = sx * 0.4
		g.add_child(leaf)
		var bead := Look.sphere(0.4, glass, Vector3(x, 0.0, 0))
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(bead)


func _chimney_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)


func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var plank: Dictionary = _blk(_ahead(cp0, 0.76, 0.0, 12.0), 1.8, 12.0, "alt", 0.6)
	var pc: Vector3 = plank["c"]
	var bz: float = pc.z + 0.5
	var beam: LaserGate = kit.laser(_w(Vector3(pc.x, pc.y + 1.2, bz)), Vector3(3.2, 2.4, 0.2), 5.0, 0.3, 0.0, _yaw)
	_dress_sunbeam(beam)
	var foot: Dictionary = _blk(_ahead(plank, 0.78, 0.0, 2.8), 2.8, 2.8, "main", 1.0)
	var fcen: Vector3 = foot["c"]
	# the chimney, in the proven geometry: three bark panels up the inside of the trunk
	var o := Vector3(fcen.x, fcen.y - 6.0, fcen.z + 15.2)
	_chimney_panel(o.x + 2.3, o.y + 7.2, o.z - 19.5, o.z - 26.0)
	_chimney_panel(o.x - 2.3, o.y + 12.0, o.z - 24.5, o.z - 32.5)
	_chimney_panel(o.x + 2.3, o.y + 15.0, o.z - 30.5, o.z - 38.5)
	var top: Dictionary = _ledge(Vector3(o.x - 0.75, o.y + 16.4, o.z - 42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(_ahead(top, 0.78, 0.0, 5.0, 0.75))
	_hop(cp0, plank, Vector3(0, 0, 5.0))
	var pre: Vector3 = _w(Vector3(pc.x, pc.y, bz + 1.6))
	r_walk(pre)
	_wait(func() -> bool: return _dark(beam, 0.0, 1.2 + 1.5), pre)
	r_walk(_w(Vector3(pc.x, pc.y, pc.z - 5.4)))
	_hop(plank, foot)
	r_walk(_w(o + Vector3(0, 6.0, -14.4)))
	r_wallrun(_w(o + Vector3(0.5, 6.0, -15.95)), _w(o + Vector3(1.7, 7.4, -20.6)), _w(o + Vector3(1.7, 7.4, -23.5)), _w(o + Vector3(-1.7, 11.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(o + Vector3(-1.7, 11.5, -27.4)), _w(o + Vector3(-1.7, 11.5, -30.4)), _w(o + Vector3(1.7, 14.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(o + Vector3(1.7, 14.5, -34.0)), _w(o + Vector3(1.7, 14.5, -35.4)), _w(o + Vector3(-0.75, 16.4, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	# the hollow trunk: dark bark walls behind the panels, knotholes with the sun pouring through
	var bark: StandardMaterial3D = Look.flat(Color(0.34, 0.23, 0.14), 0.95)
	add_child(Look.box(_sz(Vector3(0.6, 20.0, 22.0)), bark, _w(o + Vector3(3.1, 8.0 + 6.0 - 6.0 + 0.0, -29.0))))
	add_child(Look.box(_sz(Vector3(0.6, 18.0, 14.0)), bark, _w(o + Vector3(-3.1, 10.0, -29.0))))
	for w: Vector3 in [Vector3(2.78, 12.0, -28.2), Vector3(-2.78, 8.5, -34.0)]:
		var win := Look.box(_sz(Vector3(0.08, 2.2, 1.8)), Look.flat(Color(1.0, 0.88, 0.5), 0.3, 0.0, 1.6), _w(o + w))
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(win)
	return cp["c"]


# ---- stage 11: Ladybird Crossing (BRANCH) - ride the flying ladybird | bounce down the caps -------------------------
# [shortcut: mantle the stem and run the high branch]

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var fork: Dictionary = _blk(_ahead(cp0, 0.80, 0.0, 3.0), 11.0, 3.0)
	var fc: Vector3 = fork["c"]
	var f0: float = fc.z - 1.5
	# LEFT (main): a flying ladybird shuttles across the gap
	var travel: float = 24.0
	var lb := FungalSnail.new()
	lb.kind = "ladybird"
	lb.size = Vector3(3.0, 0.4, 3.0)
	var pts: Array[Vector3] = [Vector3.ZERO, _d(Vector3(0, 0, -travel))]
	lb.points = pts
	lb.period = 14.0
	lb.dwell = 0.25
	var start := Vector3(-3.5, 0.0, f0 - 1.2 - 1.5)
	lb.position = _w(start) - Vector3(0, 0.2, 0)
	add_child(lb)
	var mz: float = start.z - travel - 1.5 - 1.2 - 1.5
	var merge: Dictionary = _blk(Vector3(0, 0, mz), 11.0, 3.0)
	# RIGHT: two springcaps zigzag across to the merge
	var a_c: Vector3 = _ahead(_area(fc, 5.5, 1.5), 0.74, 0.0, 3.2, 3.6)
	var b_c := Vector3(6.6, a_c.y - 1.5, (a_c.z + mz) * 0.5)
	var m_t := Vector3(3.6, 0.0, mz)
	var s_ab: float = _solve_strength(-1.5, Vector2(a_c.x - b_c.x, a_c.z - b_c.z).length())
	var s_bm: float = _solve_strength(m_t.y - b_c.y, Vector2(b_c.x - m_t.x, b_c.z - m_t.z).length())
	var cap_a: FungalCap = _spring_cap(a_c, 1.6, RED)
	cap_a.high = s_ab
	cap_a.low = s_ab - 7.0
	var cap_b: FungalCap = _spring_cap(b_c, 1.6, ORANGE)
	cap_b.high = s_bm
	cap_b.low = s_bm - 7.0
	# SHORTCUT: a mantle up a tall stem, then a high branch and a drop to the merge
	var col_top := Vector3(0.0, 4.1, f0 - 1.0)
	var col: Dictionary = _ledge(col_top, Vector3(2.4, 12.0, 2.0), "accent")
	var m_k: int = ceili((0.85 * _reach(-4.1) - 0.4) / 0.2 - 0.001)
	var front_b: float = mz + (float(m_k) * 0.2 - 0.03) + 1.5 - 0.35
	var col_front: float = col_top.z - 1.0
	var br_len: float = col_front - front_b
	var branch: Dictionary = _blk(Vector3(0.0, 4.1, col_front - br_len * 0.5), 1.8, br_len, "alt", 0.6)
	var cp: Dictionary = _cp(_ahead(merge, 0.78, 0.0, 5.0))
	print("S11 br_len ", br_len, " mz ", mz, " s_ab ", s_ab, " s_bm ", s_bm)
	_hop(cp0, fork, Vector3(0, 0, 0.4))
	if route_variant == 2:
		r_walk(_w(Vector3(0, 0, fc.z + 0.9)))
		r_mantle(_w(Vector3(0, 0, fc.z + 0.65)), _w(col_top + Vector3(0, 0, 0.4)))
		r_walk(_w(Vector3(0.0, 4.1, front_b + 0.6)))
		_hop(branch, merge, Vector3(0, 0, 0.4))
	elif route_variant == 1:
		r_walk(_w(Vector3(3.6, 0, fc.z + 0.4)))
		_hop(_area(Vector3(3.6, 0, fc.z), 1.5, 1.5), _area(a_c, 1.6, 1.6))
		r_pad(_w(a_c), _w(b_c))
		r_pad(_w(b_c), _w(m_t))
	else:
		r_walk(_w(Vector3(-3.5, 0, fc.z + 0.4)))
		route.append({"kind": "candy_board", "from": _w(Vector3(-3.5, 0, f0 + 1.0)), "cars": [lb], "reach": 4.8, "lead": 0.45, "local": Vector3(0, 0.1, 0)})
		var end_w: Vector3 = _w(start + Vector3(0, 0, -travel))
		route.append({"kind": "candy_ride", "stand": Vector3(0, 0.1, 0), "to": _w(Vector3(-3.5, 0, mz + 0.6)), "until": func() -> bool:
			return Vector2(lb.global_position.x - end_w.x, lb.global_position.z - end_w.z).length() < 0.4})
	_hop(merge, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_sign(Vector3(-3.5, 0, fc.z + 1.2), Color(1.0, 0.3, 0.25))
	_sign(Vector3(3.6, 0, fc.z + 1.2), ORANGE)
	_sign(Vector3(0, 0, fc.z + 1.2), GOLD)
	return cp["c"]


# ---- stage 12: Falling Leaves - dry leaves that give way, one green one under a dewdrop ----------------------------

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var prev: Dictionary = cp0
	var areas: Array[Dictionary] = []
	var dxs: Array[float] = [0.0, 0.5, -0.5, 0.5, -0.5, 0.5]
	var drip: FungalDrip
	for i: int in 6:
		var c: Vector3 = _ahead(prev, 0.78, 0.5, 2.4, dxs[i])
		if i == 3:
			areas.append(_leaf_plat(c, 1.3))
			drip = _drip(c, 7.0, 5.5, 3.3 + 2.7)
		else:
			kit.collapse(_w(c), 2.4, 0.8, 3.0)
			_floors.append({"top": _w(c), "size": Vector3(2.4, 0, 2.4), "drop": 0.4, "kind": 1})
			areas.append({"c": c, "hx": 1.2, "hz": 1.2, "r": 1.2})
		prev = areas[i]
	var cp: Dictionary = _cp(_ahead(prev, 0.78, 0.0, 5.0, -(prev["c"] as Vector3).x))
	var arrive: float = 3.3
	_wait(func() -> bool: return drip.clear_over(Game.course_time, arrive - 0.5, arrive + 0.7 + 1.5))
	prev = cp0
	for a: Dictionary in areas:
		_hop(prev, a)
		prev = a
	_hop(prev, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 13: Ant Highway - stepping stones under two dewdrops | [shortcut: run the bark wall] ----------------------

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var prev: Dictionary = cp0
	var plats: Array[Dictionary] = []
	var dxs: Array[float] = [0.4, -0.4]
	for i: int in 2:
		var c: Vector3 = _ahead(prev, 0.78, 0.0, 2.4, dxs[i])
		plats.append(_cap_plat(c, 1.2, YELLOW) if i % 2 == 0 else _leaf_plat(c, 1.2))
		prev = plats[i]
	var cp: Dictionary = _cp(_ahead(prev, 0.78, 0.0, 5.0, -(prev["c"] as Vector3).x))
	var arrive: Array[float] = [1.0, 1.9]
	var d1: FungalDrip = _drip((plats[0]["c"] as Vector3), 7.0, 5.5, arrive[0] + 2.7)
	var d2: FungalDrip = _drip((plats[1]["c"] as Vector3), 7.0, 5.5, arrive[1] + 2.7)
	# SHORTCUT: a bark wall down the left side, kicked off onto the checkpoint
	var cpc: Vector3 = cp["c"]
	var wz0: float = -4.0
	var wz1: float = cpc.z + 6.0
	kit.wallrun(_w(Vector3(-3.4, 1.2, (wz0 + wz1) * 0.5)), Vector3(wz0 - wz1, 6.5, 0.6), _yaw + 90.0)
	if route_variant == 2:
		r_walk(_w(Vector3(-0.6, 0, -1.4)))
		r_wallrun(_w(Vector3(-0.6, 0, -2.15)), _w(Vector3(-2.9, 1.4, -7.0)), _w(Vector3(-2.9, 1.4, cpc.z + 8.0)), _w(cpc + Vector3(-0.5, 0, 0.2)))
	else:
		_wait(func() -> bool: return d1.clear_over(Game.course_time, arrive[0] - 0.5, arrive[0] + 0.7 + 1.5) 			and d2.clear_over(Game.course_time, arrive[1] - 0.5, arrive[1] + 0.7 + 1.5))
		prev = cp0
		for st: Dictionary in plats:
			_hop(prev, st)
			prev = st
		_hop(prev, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	_bark_slab(Vector3(-3.4, 1.2, (wz0 + wz1) * 0.5), Vector3(wz0 - wz1, 6.5, 0.6), -1.0)
	return cp["c"]


# ---- stage 14: Dew Garden - a spore lift, then leaves under a dewdrop ----------------------------------------------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var pr: float = 3.0
	var pf_c: Vector3 = _ahead(cp0, 0.74, 0.0, pr * 2.0)
	var pf: FungalPuff = _puff(pf_c, 9.0, 8.0, 0.25)
	var ledge: Dictionary = _blk(Vector3(pf_c.x, pf_c.y + 7.0, pf_c.z - pr - 1.2 - 2.5), 5.0, 5.0, "alt", 0.8)
	var lc: Vector3 = ledge["c"]
	var prev: Dictionary = ledge
	var plats: Array[Dictionary] = []
	var dxs: Array[float] = [0.4, -0.4, 0.4]
	for i: int in 3:
		var c: Vector3 = _ahead(prev, 0.78, 0.0, 2.6, dxs[i])
		plats.append(_leaf_plat(c, 1.3) if i != 1 else _cap_plat(c, 1.3, VIOLET))
		prev = plats[i]
	var cp: Dictionary = _cp(_ahead(prev, 0.78, 0.0, 5.0, -(prev["c"] as Vector3).x))
	var arrive: float = 2.0
	var drip: FungalDrip = _drip((plats[1]["c"] as Vector3), 7.0, 5.5, arrive + 2.7)
	_hop(cp0, _area(pf_c, pr, pr))
	_lift(pf, pf_c, pr, lc, 7.4)
	r_walk(_w(Vector3(lc.x, lc.y, lc.z - 0.5)))
	_wait(func() -> bool: return drip.clear_over(Game.course_time, arrive - 0.5, arrive + 0.7 + 1.5))
	prev = ledge
	for st: Dictionary in plats:
		_hop(prev, st)
		prev = st
	_hop(prev, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 15: Ladybird Lane - two ladybirds ferry you over the gaps ---------------------------------------------------

func _ladybird(start_top: Vector3, travel: float, period: float) -> FungalSnail:
	var lb := FungalSnail.new()
	lb.kind = "ladybird"
	lb.size = Vector3(3.0, 0.4, 3.0)
	var pts: Array[Vector3] = [Vector3.ZERO, _d(Vector3(0, 0, -travel))]
	lb.points = pts
	lb.period = period
	lb.dwell = 0.25
	lb.position = _w(start_top) - Vector3(0, 0.2, 0)
	add_child(lb)
	return lb


## Bot: board `lb` from `from` (local), ride until it is at its far end, then step off to `to` (local).
func _ride(lb: FungalSnail, from: Vector3, start_top: Vector3, travel: float, to: Vector3) -> void:
	route.append({"kind": "candy_board", "from": _w(from), "cars": [lb], "reach": 4.8, "lead": 0.45, "local": Vector3(0, 0.1, 0)})
	var end_w: Vector3 = _w(start_top + Vector3(0, 0, -travel))
	route.append({"kind": "candy_ride", "stand": Vector3(0, 0.1, 0), "to": _w(to), "until": func() -> bool:
		return Vector2(lb.global_position.x - end_w.x, lb.global_position.z - end_w.z).length() < 0.4})


func _stage_15() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var d1: Dictionary = _blk(_ahead(cp0, 0.76, 0.0, 4.0), 4.0, 4.0, "alt", 0.8)
	var dc: Vector3 = d1["c"]
	var travel: float = 16.0
	var s1 := Vector3(dc.x, dc.y, dc.z - 2.0 - 1.2 - 1.5)
	var lb1: FungalSnail = _ladybird(s1, travel, 10.0)
	var isl_c := Vector3(dc.x, dc.y, s1.z - travel - 1.5 - 1.2 - 2.0)
	var isl: Dictionary = _blk(isl_c, 4.0, 4.0, "alt", 0.8)
	var s2 := Vector3(dc.x, dc.y, isl_c.z - 2.0 - 1.2 - 1.5)
	var lb2: FungalSnail = _ladybird(s2, travel, 10.0)
	lb2.phase = 0.5
	var d2c := Vector3(dc.x, dc.y, s2.z - travel - 1.5 - 1.2 - 2.0)
	var d2: Dictionary = _blk(d2c, 4.0, 4.0, "alt", 0.8)
	var cp: Dictionary = _cp(_ahead(d2, 0.76, 0.0, 5.0))
	_hop(cp0, d1)
	r_walk(_w(Vector3(dc.x, dc.y, dc.z + 0.0)))
	_ride(lb1, Vector3(dc.x, dc.y, dc.z - 0.6), s1, travel, isl_c)
	r_walk(_w(Vector3(isl_c.x, isl_c.y, isl_c.z + 0.6)))
	_ride(lb2, Vector3(isl_c.x, isl_c.y, isl_c.z - 0.6), s2, travel, d2c)
	r_walk(_w(Vector3(d2c.x, d2c.y, d2c.z - 1.0)))
	_hop(d2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]


# ---- stage 16: Root Flare - two mantles up the roots at the foot of the great toadstool ----------------------------------

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 2.5, 2.5)
	var p1: Dictionary = _cap_plat(_ahead(cp0, 0.76, 0.0, 2.4), 1.2, ORANGE)
	var b1: Dictionary = _blk(_ahead(p1, 0.78, 0.0, 3.4, 0.0), 2.4, 3.4, "alt", 0.8)
	var b1c: Vector3 = b1["c"]
	var front1: float = b1c.z - 1.7
	var l1_top := Vector3(b1c.x, b1c.y + 3.3, front1 - 1.6 - 1.2)
	var l1: Dictionary = _ledge(l1_top, Vector3(3.0, 9.0, 2.4))
	var b2: Dictionary = _blk(_ahead(l1, 0.78, 0.0, 3.4, 0.0), 2.4, 3.4, "alt", 0.8)
	var b2c: Vector3 = b2["c"]
	var front2: float = b2c.z - 1.7
	var l2_top := Vector3(b2c.x, b2c.y + 3.3, front2 - 1.6 - 1.2)
	var l2: Dictionary = _ledge(l2_top, Vector3(3.0, 9.0, 2.4))
	var cp: Dictionary = _cp(_ahead(l2, 0.78, 0.0, 5.0))
	_hop(cp0, p1)
	_hop(p1, b1)
	r_walk(_w(Vector3(b1c.x, b1c.y, front1 + 0.9)))
	r_mantle(_w(Vector3(b1c.x, b1c.y, front1 + 0.35)), _w(l1_top + Vector3(0, 0, 0.3)))
	_hop(l1, b2)
	r_walk(_w(Vector3(b2c.x, b2c.y, front2 + 0.9)))
	r_mantle(_w(Vector3(b2c.x, b2c.y, front2 + 0.35)), _w(l2_top + Vector3(0, 0, 0.3)))
	_hop(l2, cp, Vector3(0, 0, 1.2))
	r_checkpoint()
	return cp["c"]

# @@STAGES@@


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
	_env.sky = FungalSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.82, 0.86, 0.7)
	_env.ambient_light_energy = 0.7
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.88, 0.9, 0.66)
	_env.fog_density = 0.0026
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.2
	_env.fog_sun_scatter = 0.25
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.14
	_env.adjustment_contrast = 1.06
	# warm gold sun low through the leaves, and a soft green-blue bounce light from below
	_sun.light_color = Color(1.0, 0.9, 0.68)
	_sun.light_energy = 1.4
	_sun.rotation_degrees = Vector3(-38, 128, 0)
	_fill.light_color = Color(0.7, 0.86, 0.78)
	_fill.light_energy = 0.3
	_fill.rotation_degrees = Vector3(-20, -52, 0)


## Every point the route passes (takeoffs, landings, walk targets) and every floor: the far
## scenery keeps clear of them.
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


## True when no route point or floor lies within `dist` (horizontally) of p, at any height.
func _clear_xz(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist:
			return false
	return true


## True when nothing walkable lies beneath `top` within `r` (so a support can run down to the floor).
func _column_free(top: Vector3, r: float, skip: Dictionary) -> bool:
	for f: Dictionary in _floors:
		if f == skip:
			continue
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		if t.y < top.y - float(skip["drop"]) + 0.5 and absf(t.x - top.x) < r + s.x * 0.5 + 0.3 and absf(t.z - top.z) < r + s.z * 0.5 + 0.3:
			return false
	return true


func _surroundings() -> void:
	var rng: RandomNumberGenerator = kit.rng
	var pts: Array[Vector3] = _route_points()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p: Vector3 in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid: Vector3 = (lo + hi) * 0.5
	# under every floor: a support running down to the forest floor (a toadstool stem under a cap, a
	# stalk under a leaf, a stub under a slab) - never where it would run through anything walkable
	for f: Dictionary in _floors:
		var t: Vector3 = f["top"]
		var s: Vector3 = f["size"]
		var under: Vector3 = t - Vector3(0, float(f["drop"]), 0)
		var r: float = clampf(minf(s.x, s.z) * 0.28, 0.35, 1.9)
		if bool(f.get("tall", false)):
			continue
		var length: float = under.y - GROUND_Y
		if length > 0.5 and _column_free(under, r, f):
			deco.support(under, r, length, int(f["kind"]))
	# the forest floor, far below
	deco.ground(GROUND_Y, mid)
	# far scenery on the forest floor round the course: toadstools, daisies, trunks, logs, ferns
	var placed: int = 0
	var tries: int = 0
	var gy: float = GROUND_Y
	while placed < 70 and tries < 900:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 120.0, hi.x + 120.0), gy, rng.randf_range(lo.z - 120.0, hi.z + 120.0))
		var roll: float = rng.randf()
		var yaw: float = rng.randf() * TAU
		if roll < 0.26:
			var cap_r: float = rng.randf_range(4.0, 12.0)
			if not _clear_xz(p, pts, cap_r * 1.2 + 6.0):
				continue
			var col: Color = [RED, RED, ORANGE, PINKCAP, YELLOW, VIOLET][rng.randi() % 6]
			deco.toadstool(p, rng.randf_range(10.0, 34.0), cap_r, col, true, rng.randf_range(-0.08, 0.08))
		elif roll < 0.46:
			var s: float = rng.randf_range(3.0, 6.5)
			if not _clear_xz(p, pts, s * 1.3 + 8.0):
				continue
			deco.daisy(p, rng.randf_range(16.0, 36.0), s, yaw)
		elif roll < 0.58:
			var tr: float = rng.randf_range(6.0, 12.0)
			if not _clear_xz(p, pts, tr + 14.0):
				continue
			deco.trunk(p, tr, rng.randf_range(70.0, 120.0))
		elif roll < 0.68:
			if not _clear_xz(p, pts, 16.0):
				continue
			deco.fallen_log(p, rng.randf_range(16.0, 36.0), rng.randf_range(2.0, 4.0), yaw, rng.randf() < 0.4)
		elif roll < 0.78:
			if not _clear_xz(p, pts, 12.0):
				continue
			deco.fern(p, rng.randf_range(2.5, 5.0), yaw)
		elif roll < 0.88:
			if not _clear_xz(p, pts, 8.0):
				continue
			deco.blades(p, rng.randi_range(6, 10), rng.randf_range(14.0, 30.0), 2.5)
		elif roll < 0.94:
			if not _clear_xz(p, pts, 14.0):
				continue
			deco.rock(p, rng.randf_range(2.5, 6.0), yaw)
		else:
			if not _clear_xz(p, pts, 10.0):
				continue
			deco.patch(p, rng.randi_range(5, 9), 5.0, rng.randf_range(1.5, 3.0))
		placed += 1
	# soft rolling hills of moss on the horizon
	for i: int in 14:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(maxf(hi.x - lo.x, hi.z - lo.z) * 0.5 + 90.0, maxf(hi.x - lo.x, hi.z - lo.z) * 0.5 + 300.0)
		deco.hill(Vector3(mid.x + cos(a) * d, gy - 4.0, mid.z + sin(a) * d), rng.randf_range(30.0, 80.0), rng.randf_range(12.0, 28.0))
	# ambient life along the route: pollen drifting, petals falling, seeds rising
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c3: Vector3 = (here + prev) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 12.0, 8.0, absf(here.z - prev.z) * 0.5 + 12.0)
		FungalFx.pollen(self, c3, ext, 60)
		FungalFx.petals(self, c3 + Vector3(0, 6.0, 0), ext, 18)
		FungalFx.seeds(self, c3 - Vector3(0, 2.0, 0), ext * Vector3(0.8, 1.0, 0.8), 14)


## Swap every walkable surface to the mossy bark shader (same colours and sizes). Branches and logs
## (the "alt" style) get pale wood tops.
func _fungal_materials() -> void:
	var wood_top: Color = Look.c("alt_top")
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = preload("res://visual/fungal_moss.gdshader")
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		var tc: Color = sm.get_shader_parameter("top_color")
		r.set_shader_parameter("wood", tc.is_equal_approx(wood_top))
		m.material_override = r


# ---- live effects -----------------------------------------------------------------------------------

## The great toadstool bursts into bloom: a fountain of petals and spores and golden stars.
func _finish_sequence() -> void:
	var cols: Array[Color] = [GOLD, Color(1.0, 0.62, 0.72), CREAM, GOLD, RED]
	for i: int in cols.size():
		var fw: GPUParticles3D = FungalFx.finale(cols[i], 80)
		fw.position = _finish_pos + Vector3(-6.0 + 3.0 * float(i), 4.0 + float(i % 2) * 3.0, -1.0)
		add_child(fw)
		fw.restart()
		fw.emitting = true
	var pf: GPUParticles3D = FungalFx.petal_fountain(90)
	pf.position = _finish_pos + Vector3(0, 1.0, 0)
	add_child(pf)
	pf.restart()
	pf.emitting = true
	# SOUND: fungal_finish - the great toadstool blooms: a rising chime and a puff of spores
	WorldAudio.at(self, "fungal_finish", _finish_pos + Vector3(0, 3.0, 0), 1.0, 120.0)
	await get_tree().create_timer(0.9).timeout


# ---- temporary debugging ----------------------------------------------------------------------------

const DEBUG_JUMPS: bool = true
var _dbg_connected: bool = false


func _process(_dt: float) -> void:
	if DEBUG_JUMPS and player != null and not _dbg_connected:
		_dbg_connected = true
		player_failed.connect(func(cause: String) -> void: print("FAIL ", cause, " t=", snappedf(Game.course_time, 0.01), " at ", player.global_position.snapped(Vector3.ONE * 0.01)))
		player.jumped.connect(func() -> void: print("JUMP t=", snappedf(Game.course_time, 0.01), " at ", player.global_position.snapped(Vector3.ONE * 0.01), " hspeed ", snappedf(player.horizontal_speed(), 0.01)))
var _dbg_acc: float = 0.0
func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	_dbg_acc += dt
	if DEBUG_JUMPS and player != null and _dbg_acc > 0.1 and Game.course_time > 0.0 and Game.course_time < 3.0:
		_dbg_acc = 0.0
		var lbn: Array = find_children("*", "FungalSnail", true, false); print("LB ", (lbn[lbn.size() - 1] as Node3D).global_position.snapped(Vector3.ONE * 0.01) if lbn.size() > 0 else "-"); print("TR t=", snappedf(Game.course_time, 0.1), " ", player.global_position.snapped(Vector3.ONE * 0.01), " v ", player.velocity.snapped(Vector3.ONE * 0.1), " wall ", player.is_wall_running(), " gr ", player.grounded)
