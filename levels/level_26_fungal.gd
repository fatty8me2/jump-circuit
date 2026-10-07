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

## The forest floor, far below the course (a fall is called well before the player reaches it).
const GROUND_Y: float = -13.0

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 0

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
