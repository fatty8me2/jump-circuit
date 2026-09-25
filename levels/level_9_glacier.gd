extends LevelBase
## 9. FROSTBITE PASS - (work in progress: stage list at the end of the build)

const BLOCK_SHADER: Shader = preload("res://visual/glacier_block.gdshader")
const SKY_SHADER: Shader = preload("res://visual/glacier_sky.gdshader")
const AURORA_SHADER: Shader = preload("res://visual/glacier_aurora.gdshader")

## Stages built so far (development: the last one ends at a temporary finish).
const STAGES_BUILT: int = 16

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: GlacierDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (for set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO


func _configure() -> void:
	theme_id = "glacier"
	music_track = "glacier"
	kill_y = -90.0
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


## Snow block on a column of glacier ice reaching down into the valley haze.
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, column: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if column:
		deco.serac(_w(c - Vector3(0, thick, 0)), clampf(minf(sx, sz) * 0.32, 0.35, 1.8), kit.rng.randf_range(30.0, 44.0))
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.8, column: bool = true) -> Dictionary:
	var body: StaticBody3D = kit.disc(_w(c), r, thick, style, 0.0)
	if column:
		deco.serac(_w(c - Vector3(0, thick, 0)), clampf(r * 0.5, 0.4, 1.8), kit.rng.randf_range(30.0, 44.0))
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


## Kill brick dressed as a bed of cursed red ice spikes.
func _haz(c: Vector3, size: Vector3, yaw_extra: float = 0.0) -> void:
	kit.hazard(_w(c), size, _yaw + yaw_extra)
	var n: int = maxi(int(maxf(size.x, size.z) / 0.7), 1)
	var along: Vector3 = _b * Basis(Vector3.UP, deg_to_rad(yaw_extra)) * (Vector3(1, 0, 0) if size.x >= size.z else Vector3(0, 0, 1))
	var m: StandardMaterial3D = GlacierFx.ice_mat(Color(1.0, 0.3, 0.35), 1.4, 0.9)
	for i: int in n:
		var f: float = (float(i) + 0.5) / float(n) - 0.5
		var h: float = kit.rng.randf_range(0.5, 0.9)
		var sp := Look.cylinder(0.14, h, m, _w(c) + along * f * maxf(size.x, size.z) + Vector3(0, size.y * 0.5 + h * 0.5 - 0.05, 0), 0.0, 5)
		sp.rotation = Vector3(kit.rng.randf_range(-0.25, 0.25), 0, kit.rng.randf_range(-0.25, 0.25))
		add_child(sp)


## Kill brick just past block `b`, square to the arrival direction from `a` (punishes overshoot).
func _spikes_behind(a: Dictionary, b: Dictionary, width: float = 1.6) -> void:
	var ca: Vector3 = a["c"]
	var cb: Vector3 = b["c"]
	var d := Vector3(cb.x - ca.x, 0, cb.z - ca.z).normalized()
	var half: float = minf(float(b["hx"]) / maxf(absf(d.x), 0.001), float(b["hz"]) / maxf(absf(d.z), 0.001))
	var yaw_local: float = rad_to_deg(atan2(-d.x, -d.z))
	_haz(cb + d * (half + 0.55) + Vector3(0, 0.55, 0), Vector3(width, 1.5, 0.5), yaw_local)


## Checkpoint platform facing the next stage's heading (_next_yaw): a snow plaza with lanterns
## and a cairn; a fountain of glitter and powder when the stage is banked.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var h: float = size * 0.5 - 0.45
	deco.lantern(_w(c + Vector3(-h, 0, h)), 2.2)
	deco.lantern(_w(c + Vector3(h, 0, -h)), 2.2, false)
	deco.cairn(_w(c + Vector3(h, 0, h)), 0.9)
	deco.crystals(_w(c + Vector3(-h, 0, -h)), 0.6)
	for side: float in [-1.0, 1.0]:
		deco.drift(_w(c + Vector3(side * (size * 0.5 + 0.1), -0.5, kit.rng.randf_range(-h, h))), Vector3(1.4, 0.8, 2.2))
	var burst: GPUParticles3D = GlacierFx.frost_burst(GlacierFx.GLOW, 50, 8.0)
	burst.position = _w(c) + Vector3(0, 0.6, 0)
	add_child(burst)
	var puff: GPUParticles3D = GlacierFx.powder(1.4, 16, 1.8)
	puff.position = _w(c) + Vector3(0, 0.3, 0)
	add_child(puff)
	var motes: GPUParticles3D = GlacierFx.aurora_motes(Vector3(3, 1, 3), 26)
	motes.emitting = false
	motes.one_shot = true
	motes.explosiveness = 0.8
	motes.position = _w(c) + Vector3(0, 0.5, 0)
	add_child(motes)
	_cp_bursts[cp] = [burst, puff, motes]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


## A falling icicle over floor point `c` (local), hung from an overhang the caller builds.
func _icicle(c: Vector3, drop: float, period: float, phase: float, splash: float = 1.0, length: float = 1.7) -> GlacierIcicle:
	var ic := GlacierIcicle.new()
	ic.drop = drop
	ic.length = length
	ic.period = period
	ic.phase = phase
	ic.splash = splash
	ic.position = _w(c)
	add_child(ic)
	return ic


## Thin ice pane: `c` = centre of its top (local), local size.
func _thin(c: Vector3, sx: float, sz: float, delay: float = 0.6, respawn: float = 2.6) -> Dictionary:
	var t := GlacierThinIce.new()
	t.size = _sz(Vector3(sx, 0.3, sz))
	t.delay = delay
	t.respawn = respawn
	t.position = _w(c) - Vector3(0, 0.15, 0)
	add_child(t)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5, "node": t}


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## None of the icicles comes down on its ring during [now + a, now + b].
static func _ice_ok(ics: Array, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		for ic: GlacierIcicle in ics:
			if ic.is_deadly_at(Game.course_time + s):
				return false
		s += 0.03
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = GlacierDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9,
			_stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in mini(stages.size(), STAGES_BUILT):
		_next_yaw = yaws[i + 1]
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	if STAGES_BUILT < 18:
		# development: a temporary finish just past the last built stage
		kit.plat(_w(Vector3(0, 0, -6.5)), Vector3(6, 1, 7), "main", 0.0, _yaw)
		kit.finish(_w(Vector3(0, 0, -8.0)), _yaw)
		_finish_pos = _w(Vector3(0, 0, -8.0))
		r_walk(_w(Vector3(0, 0, -8.0)))
	_surroundings()
	_glacier_materials()


# ---- stage 1: Trailhead - warm-up hops over snowy boulders, the first icicle gate ---------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	deco.serac(_w(Vector3(0, -2, 0)), 4.0, 42.0)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	for p: Vector3 in [Vector3(-5.8, 0, 5.4), Vector3(5.6, 0, 4.8), Vector3(-6.0, 0, -4.6)]:
		deco.pine(_w(p), kit.rng.randf_range(0.9, 1.2))
	deco.boulder(_w(Vector3(5.8, 0.2, -4.8)), 1.1)
	deco.boulder(_w(Vector3(-6.2, 0.2, 0.6)), 0.8)
	deco.lantern(_w(Vector3(-2.2, 0, -6.2)))
	deco.lantern(_w(Vector3(2.2, 0, -6.2)))
	deco.cairn(_w(Vector3(4.8, 0, 1.0)), 1.2)
	deco.flags(_w(Vector3(-2.2, 2.5, -6.2)), _w(Vector3(2.2, 2.5, -6.2)), 7)
	var a1: Dictionary = _blk(Vector3(0, 0, -11.4), 3.0, 3.0)
	var a2: Dictionary = _blk(Vector3(3.2, 1.0, -17.0), 2.4, 2.4, "alt")
	var a3: Dictionary = _blk(Vector3(0.4, 2.0, -22.6), 2.2, 2.2)
	# the icicle gate: a rock arch over a long landing, two icicles dropping one after the other
	var l1: Dictionary = _blk(Vector3(0.4, 2.0, -30.5), 3.6, 6.0)
	var drop: float = 5.2
	var ic1: GlacierIcicle = _icicle(Vector3(0.4, 2.0, -30.0), drop, 3.2, 0.0)
	var ic2: GlacierIcicle = _icicle(Vector3(0.4, 2.0, -32.2), drop, 3.2, -0.16)
	var roof_y: float = 2.0 + drop + 1.7 + 0.1
	for sx: float in [-1.0, 1.0]:
		var px: float = 0.4 + sx * (4.6 if sx < 0.0 else 3.2)
		kit.block(_w(Vector3(px, (roof_y - 34.0) * 0.5, -31.1)), Vector3(1.2, roof_y + 34.0, 1.4), GlacierFx.ROCK, false, _yaw)
	deco.overhang(_w(Vector3(-0.3, roof_y + 0.05, -31.1)), Vector3(9.4, 1.2, 4.4), _yaw)
	var l2: Dictionary = _blk(Vector3(0.4, 2.8, -38.8), 2.4, 2.4, "alt")
	var cp: Dictionary = _cp(Vector3(0.4, 2.8, -47.4))
	_hop(start, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	# SHORTCUT: two 1 m ice pinnacles left of the gate - no waiting on the icicles
	var k1: Dictionary = _blk(Vector3(-2.6, 2.6, -28.0), 1.0, 1.0, "accent", 0.6)
	var k2: Dictionary = _blk(Vector3(-2.2, 2.8, -33.8), 1.0, 1.0, "accent", 0.6)
	if route_variant == 2:
		_hop(a3, k1)
		_hop(k1, k2)
		_hop(k2, l2)
	else:
		_hop(a3, l1, Vector3(0, 0, 2.2))
		_wait(func() -> bool: return _ice_ok([ic1, ic2], 0.0, 1.3))
		_hop(l1, l2)
	_hop(l2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Crevasse Field - thin ice over the crevasses, an ice bridge, mantle a serac --------------

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_crevasse(Vector3(0, -1.5, -8.8), 12.0, 3.4)
	var t1: Dictionary = _thin(Vector3(0, 0, -8.8), 2.6, 2.6)
	var b1: Dictionary = _blk(Vector3(-1.6, 0.6, -14.8), 2.0, 2.0, "alt")
	_crevasse(Vector3(-1.6, -0.9, -22.0), 14.0, 9.2)
	var p1: Dictionary = _thin(Vector3(-1.6, 0.6, -19.0), 2.0, 3.0)
	_thin(Vector3(-1.6, 0.6, -22.0), 2.0, 3.0)
	var p3: Dictionary = _thin(Vector3(-1.6, 0.6, -25.0), 2.0, 3.0)
	var b2: Dictionary = _blk(Vector3(-1.6, 0.6, -32.6), 3.0, 3.0)
	var m1: Dictionary = _ledge(Vector3(0.4, 3.9, -38.6), Vector3(4.0, 7.0, 3.4))
	var cp: Dictionary = _cp(Vector3(0.4, 3.9, -47.6))
	_hop(cp0, t1)
	_hop(t1, b1)
	_hop(b1, p1, Vector3(0, 0, 0.4))
	# run the whole bridge in one go: each pane cracks under you and goes a moment later
	_hop(p3, b2)
	r_mantle(_w(_edge(b2, m1["c"])), _w((m1["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(m1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## A crevasse (decor): two walls of blue glacier ice dropping into the dark, glowing deeper down.
func _crevasse(c: Vector3, width: float, length: float) -> void:
	var m: ShaderMaterial = GlacierFx.glass_mat(0.9, 0.0, 0.95)
	for sz: float in [-1.0, 1.0]:
		var wall := Look.box(_sz(Vector3(width, 18.0, 1.2)), m, _w(c + Vector3(0, -9.0, sz * (length * 0.5 + 0.6))))
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wall)
	var glow := Look.box(_sz(Vector3(width, 0.2, length)), Look.flat(GlacierFx.GLOW, 0.3, 0.0, 1.4), _w(c + Vector3(0, -16.0, 0)))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


# ---- stage 3: Icicle Gallery - a cascade of icicles under the ice cliff, mantle out under the last ------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var blocks: Array[Dictionary] = [
		_blk(Vector3(0, 0, -8.6), 2.0, 2.0),
		_blk(Vector3(1.8, 0.6, -14.4), 1.8, 1.8, "alt"),
		_blk(Vector3(-0.2, 1.2, -20.0), 1.8, 1.8),
		_blk(Vector3(1.6, 1.8, -25.8), 2.0, 2.0, "alt"),
	]
	var drop: float = 5.2
	var ics: Array[GlacierIcicle] = []
	for i: int in blocks.size():
		var bc: Vector3 = blocks[i]["c"]
		ics.append(_icicle(bc, drop, 3.0, -0.3 * float(i), 1.0))
		deco.overhang(_w(bc + Vector3(2.4 - bc.x * 0.5, drop + 1.8, 0)), Vector3(7.2 - bc.x, 1.4, 3.6), _yaw)
	var m1: Dictionary = _ledge(Vector3(1.6, 5.1, -31.8), Vector3(3.2, 7.0, 3.2), "alt")
	var ic5: GlacierIcicle = _icicle(Vector3(1.6, 5.1, -31.2), drop, 3.0, -1.2, 1.0)
	deco.overhang(_w(Vector3(3.2, 5.1 + drop + 1.8, -31.6)), Vector3(5.6, 1.4, 4.0), _yaw)
	# the ice cliff the overhangs grow from
	var cliff := Look.box(_sz(Vector3(3.0, 40.0, 34.0)), GlacierFx.glass_mat(0.8, 0.5, 0.95), _w(Vector3(6.0, -8.0, -20.0)))
	add_child(cliff)
	var cp: Dictionary = _cp(Vector3(1.0, 5.1, -41.0))
	var prev: Dictionary = cp0
	for i: int in blocks.size():
		var ic: GlacierIcicle = ics[i]
		r_walk(_w(_edge(prev, blocks[i]["c"], 0.9)))
		_wait(func() -> bool: return _ice_ok([ic], 0.3, 1.9))
		_hop(prev, blocks[i])
		prev = blocks[i]
	_wait(func() -> bool: return _ice_ok([ic5], 0.3, 1.9))
	r_mantle(_w(_edge(prev, m1["c"])), _w((m1["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(m1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Ice Chutes - down a glassy chute and off the lip over a crevasse, a second chute into a pad ----

func _stage_4() -> Vector3:
	_slide(Vector3(0, 0.0, -2.9), 14.0, 22.0, 3.2)
	var lip1: Vector3 = _slide_end(Vector3(0, 0.0, -2.9), 14.0, 22.0)
	var near1: float = lip1.z - 13.4
	var l1: Dictionary = _blk(Vector3(0, -7.4, near1 - 3.0), 4.0, 6.0)
	# a snow bridge over the landing, dripping two icicles: pick your moment to drop in
	var ic1: GlacierIcicle = _icicle(Vector3(0.6, -7.4, near1 - 1.6), 6.2, 3.4, 0.0, 1.1)
	var ic2: GlacierIcicle = _icicle(Vector3(-0.7, -7.4, near1 - 3.9), 6.2, 3.4, -0.12, 1.1)
	_snow_bridge(Vector3(0, -7.4 + 6.2 + 1.8, near1 - 2.8), 16.0, 5.2)
	var s2_top := Vector3(0, -7.4, near1 - 5.9)
	_slide(s2_top, 10.0, 25.0, 3.2)
	var s2_end: Vector3 = _slide_end(s2_top, 10.0, 25.0)
	_blk(Vector3(0, s2_end.y, s2_end.z - 2.0), 3.6, 4.2, "alt")
	var pad_c := Vector3(0, s2_end.y, s2_end.z - 2.3)
	kit.pad(_w(pad_c), 20.0, 0.0, _yaw, 1.4)
	var cp: Dictionary = _cp(Vector3(0, s2_end.y + 3.2, pad_c.z - 19.5))
	_crevasse(Vector3(0, lip1.y - 3.0, (lip1.z + near1) * 0.5), 14.0, absf(near1 - lip1.z) - 0.6)
	r_walk(_w(Vector3(0, 0, -2.0)))
	_wait(func() -> bool: return _ice_ok([ic1, ic2], 1.2, 2.6))
	r_jump(_w(lip1 + Vector3(0, 0, 0.6)), _w((l1["c"] as Vector3) + Vector3(0, 0, 1.0)))
	route[route.size() - 1]["speed"] = 20.0
	r_pad(_w(pad_c), _w((cp["c"] as Vector3) + Vector3(0, 0, 0.8)))
	r_walk(_w(cp["c"]))
	r_checkpoint()
	return cp["c"]


## A natural bridge of snow and ice spanning a gap overhead (decor): an arch of packed snow
## with a blue ice underside. `c` = centre of its underside (local), spanning `span` across.
func _snow_bridge(c: Vector3, span: float, depth: float) -> void:
	deco.overhang(_w(c), Vector3(span, 1.4, depth), _yaw)
	for sx: float in [-1.0, 1.0]:
		kit.block(_w(c + Vector3(sx * (span * 0.5 + 0.6), -20.0, 0)), Vector3(2.0, 40.0, depth * 0.8), GlacierFx.ROCK, false, _yaw)


# ---- stage 5: Blizzard Ridge (BRANCH) - the knife-edge ridge between gusts, or the lee-side cornice ----

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -7.0), 11.0, 2.6, "main", 1.0, false)
	deco.serac(_w(Vector3(-3.0, -1.0, -7.0)), 1.1, 36.0)
	deco.serac(_w(Vector3(3.0, -1.0, -7.0)), 1.1, 32.0)
	# the ridge: two beams and two small blocks along the crest, swept by the gusts
	_blk(Vector3(1.6, 0.5, -15.0), 1.0, 5.0, "accent", 0.6)
	var r2: Dictionary = _blk(Vector3(0.4, 1.2, -22.2), 1.4, 1.4)
	_blk(Vector3(1.8, 1.8, -30.0), 1.0, 6.0, "accent", 0.6)
	var r4: Dictionary = _blk(Vector3(0.6, 2.4, -38.2), 1.4, 1.4, "alt")
	var merge: Dictionary = _blk(Vector3(-1.0, 3.2, -44.0), 7.0, 3.0)
	var cp: Dictionary = _cp(Vector3(-1.0, 3.2, -53.0))
	var gust: GlacierGust = _gust(Vector3(3.75, 3.0, -25.5), Vector3(10.5, 12.0, 32.0), Vector3(30, 0, 0), 3.2, 0.0, 0.8, 0.4)
	# the lee: a cornice wall to run, a shelf, a mantle up the crest's shoulder
	_panel(-6.6, 1.2, -10.5, -26.5, 6.5)
	var l1: Dictionary = _blk(Vector3(-4.2, 0, -32.0), 3.6, 5.0, "alt")
	var ml: Dictionary = _ledge(Vector3(-4.0, 3.2, -38.5), Vector3(4.0, 6.0, 3.5), "alt")
	deco.overhang(_w(Vector3(-7.4, 7.0, -18.5)), Vector3(3.0, 1.6, 17.0), _yaw)
	# signposts at the fork: pale blue flags for the ridge, gold for the lee climb
	kit.banner(_w(Vector3(2.8, 0, -7.6)), 3.4, GlacierFx.GLOW, _yaw)
	kit.banner(_w(Vector3(-3.0, 0, -7.6)), 3.4, LedgeBlock.LIP_COLOR, _yaw)
	kit.glow_strip(_w(Vector3(1.6, 0.03, -7.9)), _sz(Vector3(1.0, 0.05, 0.6)), GlacierFx.GLOW)
	kit.glow_strip(_w(Vector3(-4.3, 0.03, -7.9)), _sz(Vector3(1.0, 0.05, 0.6)), LedgeBlock.LIP_COLOR)
	_hop(cp0, fork, Vector3(1.4 if route_variant != 1 else -4.3, 0, 0.3))
	if route_variant != 1:
		var hops: Array = [
			[Vector3(1.6, 0, -7.95), Vector3(1.6, 0.5, -13.6)],
			[Vector3(1.6, 0.5, -17.15), Vector3(0.4, 1.2, -22.2)],
			[_edge(r2, Vector3(1.8, 1.8, -27.8)), Vector3(1.8, 1.8, -27.8)],
			[Vector3(1.8, 1.8, -32.65), Vector3(0.6, 2.4, -38.2)],
			[_edge(r4, Vector3(0.2, 3.2, -43.6)), Vector3(0.2, 3.2, -43.6)],
		]
		for h: Array in hops:
			r_walk(_w(h[0] as Vector3) + _d(Vector3(0, 0, 1.0)))
			_wait(func() -> bool: return gust.is_calm_for(Game.course_time, 1.0))
			r_jump(_w(h[0]), _w(h[1]))
	else:
		r_wallrun(_w(Vector3(-4.3, 0, -7.95)), _w(Vector3(-6.1, 1.4, -12.4)), _w(Vector3(-6.1, 1.4, -23.3)), _w(Vector3(-4.2, 0, -31.3)))
		r_mantle(_w(_edge(l1, ml["c"])), _w((ml["c"] as Vector3) + Vector3(0, 0, 0.3)))
		_hop(ml, merge, Vector3(0, 0, 0.3))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Cathedral Falls - glare-ice stepping stones at the foot of the frozen waterfall, then a
# chimney of three wall runs up the cleft in the ice and a mantle out onto the first tier ------------------

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var p1: Dictionary = _ice_blk(Vector3(0, 0, -8.8), 2.4, 2.4)
	var p2: Dictionary = _ice_blk(Vector3(-0.2, 0.6, -15.2), 2.2, 2.2)
	var p3: Dictionary = _blk(Vector3(0.4, 1.2, -21.0), 3.0, 4.0, "alt")
	# the chimney (a cleft in the frozen falls): run, kick across, run, kick, run, mantle
	var o := Vector3(0.4, 1.2, -20.0)
	_panel(o.x + 2.3, o.y + 1.2, o.z - 6.0, o.z - 12.5)
	_panel(o.x - 2.3, o.y + 6.0, o.z - 11.0, o.z - 19.0)
	_panel(o.x + 2.3, o.y + 9.0, o.z - 17.0, o.z - 25.0)
	var top: Dictionary = _ledge(o + Vector3(-0.75, 11.9, -28.5), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(o + Vector3(0, 11.9, -38.0))
	_frozen_falls(o)
	_hop(cp0, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	r_wallrun(_w(o + Vector3(0.5, 0, -2.6)), _w(o + Vector3(1.7, 1.4, -7.1)), _w(o + Vector3(1.7, 1.4, -10.0)), _w(o + Vector3(-1.7, 5.5, -13.9)))
	r_wallrun(Vector3.ZERO, _w(o + Vector3(-1.7, 5.5, -13.9)), _w(o + Vector3(-1.7, 5.5, -16.9)), _w(o + Vector3(1.7, 8.5, -20.5)), true, true)
	r_wallrun(Vector3.ZERO, _w(o + Vector3(1.7, 8.5, -20.5)), _w(o + Vector3(1.7, 8.5, -21.9)), _w(o + Vector3(-0.75, 11.9, -27.1)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 7: Crystal Grotto - a beam under two frost beams, two aurora-crystal blinks, a mantle -------

func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var b1: Dictionary = _blk(Vector3(0, 0, -8.6), 2.0, 2.0)
	_blk(Vector3(0, 0.8, -17.6), 1.2, 8.0, "accent", 0.6)
	var beams: Array[LaserGate] = []
	for z: float in [-15.4, -19.8]:
		beams.append(_frost_beam(Vector3(0, 0.8, z), 2.8, 2.4, 0.5, 0.0))
	var bl1: BlinkPlatform = kit.blink(_w(Vector3(1.6, 1.8, -26.4)), _sz(Vector3(2.0, 0.4, 2.0)), 3.0, 0.6, 0.0)
	var bl2: BlinkPlatform = kit.blink(_w(Vector3(-0.6, 2.6, -32.0)), _sz(Vector3(2.0, 0.4, 2.0)), 3.0, 0.6, -0.3)
	var m1: Dictionary = _ledge(Vector3(0, 5.9, -38.4), Vector3(4.0, 7.0, 3.2), "alt")
	var cp: Dictionary = _cp(Vector3(0, 5.9, -48.0))
	_grotto(Vector3(0, 0, -24.0), 44.0)
	_hop(cp0, b1)
	r_jump(_w(_edge(b1, Vector3(0, 0.8, -14.6))), _w(Vector3(0, 0.8, -14.2)))
	r_walk(_w(Vector3(0, 0.8, -14.0)))
	_wait(func() -> bool: return _laser_off(beams, 0.0, 1.0))
	r_walk(_w(Vector3(0, 0.8, -20.9)))
	_wait(func() -> bool: return _blink_on(bl1, 0.5, 1.4) and _blink_on(bl2, 1.6, 2.4))
	r_jump(_w(Vector3(0, 0.8, -21.25)), _w(Vector3(1.6, 1.8, -26.4)))
	r_jump(_w(Vector3(1.3, 1.8, -27.1)), _w(Vector3(-0.6, 2.6, -32.0)))
	r_mantle(_w(Vector3(-0.4, 2.6, -32.65)), _w(Vector3(0, 5.9, -37.6)))
	_hop(m1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## A frost beam across the path: a laser between two glowing crystal pylons. `c` = floor centre
## (local), `w` = width between the pylons; full-height (you cannot jump it).
func _frost_beam(c: Vector3, w: float, period: float, on: float, phase: float) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c + Vector3(0, 1.6, 0)), Vector3(w, 3.2, 0.2), period, on, phase, _yaw)
	for sx: float in [-1.0, 1.0]:
		deco.crystals(_w(c + Vector3(sx * (w * 0.5 + 0.55), -0.3, 0)), 0.9, GlacierFx.GLOW)
	return g


## The grotto: a hollow in the glacier - walls of glowing ice either side, crystal arches overhead,
## crystal clusters and cold light. `c` = local centre at path level, `length` along the stage.
func _grotto(c: Vector3, length: float) -> void:
	var wall: ShaderMaterial = GlacierFx.glass_mat(1.1, 0.3, 0.92, Color(0.1, 0.2, 0.55), Color(0.55, 0.8, 1.0))
	for side: float in [-1.0, 1.0]:
		var slab := Look.box(_sz(Vector3(3.0, 40.0, length)), wall, _w(c + Vector3(side * 8.5, -8.0, 0)))
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slab)
		for i: int in 6:
			var z: float = c.z + length * 0.5 - 3.0 - float(i) * (length - 6.0) / 5.0
			deco.crystals(_w(Vector3(c.x + side * 6.6, c.y + kit.rng.randf_range(-1.0, 4.0), z)), kit.rng.randf_range(1.2, 2.2),
				[GlacierFx.GLOW, GlacierFx.AURORA_V, GlacierFx.AURORA_G][i % 3])
	# arches of ice overhead
	for i: int in 4:
		var z2: float = c.z + length * 0.5 - 6.0 - float(i) * (length - 12.0) / 3.0
		var arch := Look.box(_sz(Vector3(19.0, 1.6, 2.2)), wall, _w(Vector3(c.x, c.y + 11.0 + float(i) * 0.8, z2)))
		arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arch)
		for k: int in 5:
			var ic := Look.cylinder(0.02, kit.rng.randf_range(0.8, 2.2), GlacierFx.ice_mat(GlacierFx.ICE, 0.7, 0.85),
				_w(Vector3(c.x - 7.0 + float(k) * 3.5, c.y + 9.6 + float(i) * 0.8, z2)), 0.18, 6)
			add_child(ic)
	for i: int in 3:
		var l := OmniLight3D.new()
		l.light_color = [GlacierFx.GLOW, GlacierFx.AURORA_V, GlacierFx.AURORA_G][i]
		l.light_energy = 1.8
		l.omni_range = 14.0
		l.position = _w(Vector3(c.x + (-5.0 if i % 2 == 0 else 5.0), c.y + 3.0, c.z + length * 0.3 - float(i) * length * 0.3))
		add_child(l)
	var dust: GPUParticles3D = GlacierFx.glitter(_sz(Vector3(14.0, 10.0, length)), 70)
	dust.position = _w(c + Vector3(0, 4.0, 0))
	add_child(dust)
	var motes: GPUParticles3D = GlacierFx.aurora_motes(_sz(Vector3(12.0, 6.0, length)), 36)
	motes.position = _w(c + Vector3(0, 1.0, 0))
	add_child(motes)


static func _laser_off(gs: Array, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		for g: LaserGate in gs:
			if g.is_on_at(Game.course_time + s):
				return false
		s += 0.04
	return true


static func _blink_on(bp: BlinkPlatform, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if not bp.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


# ---- stage 8: Frozen Lake (BRANCH) - hop the drifting floes, or boost across the glare ice into a pad ----

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_lake(Vector3(0, -3.0, -24.0), Vector2(46.0, 52.0))
	var fork: Dictionary = _blk(Vector3(0, 0, -7.2), 11.0, 2.6, "main", 1.0, false)
	# LEFT: ride two drifting floes across the black water, a pack-ice block between them
	var fs := Vector3(2.2, 0.5, 2.2)
	var f1: MovingPlatform = kit.mover(_w(Vector3(-3.2, 0, -13.2)), _sz(fs), [Vector3.ZERO, _d(Vector3(0, 0, -6.0))], 5.0, 0.0)
	var b1: Dictionary = _blk(Vector3(-3.2, 0.4, -25.8), 2.2, 2.2, "alt")
	var f2: MovingPlatform = kit.mover(_w(Vector3(-2.2, 0.8, -31.4)), _sz(fs), [Vector3.ZERO, _d(Vector3(0, 0, -4.0))], 4.0, 0.25)
	var merge: Dictionary = _blk(Vector3(-1.0, 1.2, -41.5), 9.0, 3.0, "main", 1.0, false)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -50.5))
	# RIGHT: a boost strip onto a sheet of glare ice, a pad at its end: bounce at speed straight to the shore
	kit.boost(_w(Vector3(3.2, 0, -11.7)), _sz(Vector3(2.4, 0.4, 6.4)), _yaw, 18.0)
	kit.slick(_w(Vector3(3.2, 0, -20.5)), _sz(Vector3(3.0, 0.5, 11.0)), _yaw, 0.0)
	_blk(Vector3(3.2, 0, -27.3), 2.8, 2.0, "alt", 0.6)
	kit.pad(_w(Vector3(3.2, 0, -27.3)), 20.0, 0.0, _yaw, 1.3)
	deco.serac(_w(Vector3(3.2, -0.5, -20.0)), 1.2, 36.0)
	for z: float in [-10.0, -17.0, -24.0]:
		deco.crystals(_w(Vector3(5.2, 0.0, z)), 0.5, GlacierFx.GLOW)
	kit.banner(_w(Vector3(-5.0, 0, -7.6)), 3.4, GlacierFx.GLOW, _yaw)
	kit.banner(_w(Vector3(5.0, 0, -7.6)), 3.4, Color(0.15, 1.0, 0.85), _yaw)
	_hop(cp0, fork, Vector3(-3.2 if route_variant != 1 else 3.2, 0, 0.3))
	if route_variant != 1:
		var up := Vector3(0, 0.25, 0)
		r_wait(f1, _w(Vector3(-3.2, -0.25, -13.2)), 0.35)
		r_jump_onto(_w(Vector3(-3.2, 0, -8.15)), f1, up)
		r_jump_from_ride(f1, _w(Vector3(-3.2, -0.25, -19.2)), 0.35, _w(b1["c"]), true, up)
		r_walk(_w(Vector3(-3.2, 0.4, -25.6)))
		r_wait(f2, _w(Vector3(-2.2, 0.55, -31.4)), 0.35)
		r_jump_onto(_w(_edge(b1, Vector3(-2.2, 0.8, -31.4))), f2, up)
		r_jump_from_ride(f2, _w(Vector3(-2.2, 0.55, -35.4)), 0.35, _w(Vector3(-1.6, 1.2, -41.2)), true, up)
		_hop(merge, cp, Vector3(0, 0, 1.5))
	else:
		r_walk(_w(Vector3(3.2, 0, -8.2)))
		r_pad(_w(Vector3(3.2, 0, -27.3)), _w((cp["c"] as Vector3) + Vector3(0, 0, 0.5)))
		r_walk(_w(cp["c"]))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Aurora Steps - four aurora panes that come and go on a rising wave, then the ice-blade
# windmill on a disc                                  [shortcut: a hidden aurora gate on a knob below] ----

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var panes: Array[BlinkPlatform] = []
	var pc: Array[Vector3] = [Vector3(0, 0.8, -8.4), Vector3(1.8, 1.8, -14.2), Vector3(-0.2, 2.8, -19.8), Vector3(1.4, 3.8, -25.6)]
	var ps: Array[float] = [2.0, 1.8, 1.8, 2.0]
	for i: int in pc.size():
		panes.append(kit.blink(_w(pc[i]), _sz(Vector3(ps[i], 0.4, ps[i])), 2.8, 0.62, -0.3 * float(i)))
		var halo: GPUParticles3D = GlacierFx.aurora_motes(_sz(Vector3(ps[i], 0.5, ps[i])), 10)
		halo.position = _w(pc[i] + Vector3(0, -0.5, 0))
		add_child(halo)
	var land: Dictionary = _blk(Vector3(0.4, 3.8, -31.4), 2.6, 4.0, "alt")
	var dc := Vector3(0.4, 3.8, -42.2)
	var disc: Dictionary = _disc(dc, 4.2, "alt")
	var sw: Sweeper = _ice_sweeper(dc, 3.9, 2, 3.6, 0.0)
	var cp: Dictionary = _cp(Vector3(0.4, 3.8, -54.2))
	# SHORTCUT: a hidden aurora gate on a 1 m knob tucked below the checkpoint's corner (a 90% leap),
	# out onto the landing past the last pane
	var hk := Vector3(5.6, -1.0, -9.0)
	_blk(hk, 1.0, 1.0, "accent", 0.6)
	var exit_c := Vector3(0.4, 3.8, -29.9)
	kit.portal(_w(hk), _yaw, _w(exit_c), _yaw, 4.0)
	_gate_dressing(hk, exit_c)
	disc.clear()
	if route_variant == 2:
		r_jump(_w(Vector3(2.6, 0, -2.65)), _w(hk + Vector3(0, 0.3, 0)))
		r_portal(_w(hk), _w(exit_c))
		r_walk(_w(exit_c + Vector3(0, 0, -1.2)))
	else:
		var prev: Dictionary = cp0
		for i: int in panes.size():
			var bp: BlinkPlatform = panes[i]
			r_walk(_w(_edge(prev, pc[i], 0.9)))
			_wait(func() -> bool: return _blink_on(bp, 0.4, 1.4))
			var tgt: Dictionary = _area(pc[i], ps[i] * 0.5, ps[i] * 0.5)
			_hop(prev, tgt)
			prev = tgt
		_hop(prev, land)
	var land1: Vector3 = _w(dc + Vector3(1.4, 0, 2.8))
	r_until(func() -> bool: return _bar_far(sw, land1, 0.4, 0.95, 0.8))
	r_jump(_w(_edge(land, dc + Vector3(1.4, 0, 2.8))), land1)
	route.append({"kind": "b_sweep", "to": _w(dc + Vector3(1.4, 0, -3.0)), "sweeper": sw, "tol": 0.5})
	r_jump(_w(dc + Vector3(1.2, 0, -3.6)), _w((cp["c"] as Vector3) + Vector3(0.6, 0, 1.5)))
	r_checkpoint()
	return cp["c"]


# ---- stage 10: Fortress Causeway - the broken causeway under the snow cannons, the drawbridge lift -----

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_moat(Vector3(0, -2.0, -20.0), 40.0)
	var c0: Dictionary = _blk(Vector3(0, 0, -7.6), 2.0, 2.0)
	var c1: Dictionary = _blk(Vector3(0, 0.6, -15.8), 2.2, 5.6, "main", 1.0)
	_blk(Vector3(0, 0.6, -25.0), 2.2, 5.0, "main", 1.0)
	var cannons: Array[Piston] = []
	for z: float in [-16.2, -25.4]:
		cannons.append(_snow_cannon(Vector3(3.3, 0.6, z), 2.6, 0.62 if z > -20.0 else 0.2))
	# the drawbridge: it sinks to the causeway, you step on, it hauls you up to the gate
	var lift: MovingPlatform = kit.mover(_w(Vector3(0, 0.6, -30.3)), _sz(Vector3(2.6, 0.5, 3.4)), [Vector3.ZERO, Vector3(0, 4.8, 0)], 5.0, 0.0)
	_drawbridge_chains(lift)
	var cp: Dictionary = _cp(Vector3(0, 5.4, -38.6))
	_hop(cp0, c0)
	_hop(c0, c1, Vector3(0, 0, 2.0))
	r_walk(_w(Vector3(0, 0.6, -14.1)))
	var p1: Piston = cannons[0]
	var p2: Piston = cannons[1]
	_wait(func() -> bool: return _piston_clear(p1, 0.0, 0.7))
	r_walk(_w(Vector3(0, 0.6, -18.0)))
	r_jump(_w(Vector3(0, 0.6, -18.25)), _w(Vector3(0, 0.6, -23.0)))
	_wait(func() -> bool: return _piston_clear(p2, 0.0, 0.7))
	r_walk(_w(Vector3(0, 0.6, -27.0)))
	r_wait(lift, _w(Vector3(0, 0.35, -30.3)), 0.25)
	r_jump_onto(_w(Vector3(0, 0.6, -27.15)), lift, Vector3(0, 0.25, 0.6))
	r_jump_from_ride(lift, _w(Vector3(0, 5.15, -30.3)), 0.25, _w((cp["c"] as Vector3) + Vector3(0, 0, 1.5)), true, Vector3(0, 0.25, -1.2))
	r_checkpoint()
	c1.clear()
	return cp["c"]


# ---- stage 11: The Gatehouse (BRANCH) - dash the passage under three falling portcullis blocks and
# mantle out under a fourth | run the gate tower's flank outside and mantle onto the inner wall ---------

func _stage_11() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	# the passage (route 0)
	_blk(Vector3(0, 0, -16.5), 3.0, 27.0, "main", 1.0, false)
	var gates: Array[Crusher] = []
	var gz: Array[float] = [-8.0, -13.6, -19.2]
	for i: int in gz.size():
		gates.append(_portcullis(Vector3(0, 0, gz[i]), Vector3(3.0, 1.6, 2.4), 3.2, 2.4, 0.33 * float(i)))
	var ml: Dictionary = _ledge(Vector3(0, 3.3, -31.6), Vector3(3.4, 7.0, 3.2), "alt")
	var top_gate: Crusher = _portcullis(Vector3(0, 3.3, -30.9), Vector3(3.2, 1.6, 2.2), 3.0, 2.4, 0.5)
	var merge: Dictionary = _ledge(Vector3(1.5, 3.3, -38.8), Vector3(9.0, 7.0, 3.0))
	var cp: Dictionary = _cp(Vector3(1.5, 3.3, -48.3))
	# the gate tower's flank (route 1): a ledge outside the breach, the tower wall, a shelf, a mantle
	var s: Dictionary = _blk(Vector3(6.0, 0, -7.0), 3.0, 5.0, "alt")
	_panel(3.7, 1.2, -11.0, -27.0, 6.5)
	var t: Dictionary = _blk(Vector3(6.4, 0, -32.0), 3.6, 5.0, "alt")
	_gatehouse()
	kit.banner(_w(Vector3(-1.2, 0, -2.4)), 3.4, Color(1.0, 0.35, 0.3), _yaw)
	kit.banner(_w(Vector3(4.4, 0, -4.6)), 3.4, LedgeBlock.LIP_COLOR, _yaw)
	if route_variant != 1:
		var stops: Array[float] = [-5.6, -11.0, -16.4, -22.0]
		for i: int in gates.size():
			var g: Crusher = gates[i]
			r_walk(_w(Vector3(0, 0, stops[i])))
			_wait(func() -> bool: return _open(g, 0.0, 0.75))
		r_walk(_w(Vector3(0, 0, -27.8)))
		_wait(func() -> bool: return _open(top_gate, 0.15, 1.3))
		r_mantle(_w(Vector3(0, 0, -28.1)), _w(Vector3(0, 3.3, -30.8)))
		r_walk(_w(Vector3(0, 3.3, -32.6)))
		_hop(ml, merge, Vector3(0, 0, 0.4))
	else:
		_hop(cp0, s, Vector3(0, 0, 0.8))
		r_wallrun(_w(Vector3(5.7, 0, -9.15)), _w(Vector3(4.2, 1.4, -13.1)), _w(Vector3(4.2, 1.4, -24.0)), _w(Vector3(6.4, 0, -31.3)))
		r_mantle(_w(_edge(t, Vector3(5.0, 3.3, -37.8))), _w(Vector3(5.0, 3.3, -38.4)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 12: Battlements - the wall-walk under a tower's dripping eave, the breach crossed along
# the next tower's wall, two frost beams on the walk, mantle the tower     [shortcut: the merlons] -----

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var w1: Dictionary = _blk(Vector3(0, 0, -9.5), 2.4, 7.0, "main", 1.0, false)
	var drop: float = 5.4
	var eave: Array[GlacierIcicle] = [_icicle(Vector3(0, 0, -8.0), drop, 3.2, 0.0, 1.0), _icicle(Vector3(0, 0, -11.0), drop, 3.2, -0.14, 1.0)]
	deco.overhang(_w(Vector3(-1.4, drop + 1.8, -9.5)), Vector3(5.4, 1.2, 6.0), _yaw)
	# the breach: the wall is down for 20 m - run the next tower's flank across it
	_panel(-2.3, 1.2, -14.5, -30.5, 6.5)
	var w2: Dictionary = _blk(Vector3(0.4, 0, -35.5), 3.6, 5.0, "main", 1.0, false)
	var w3: Dictionary = _blk(Vector3(0.4, 0.5, -45.0), 2.4, 10.0, "main", 1.0, false)
	var beams: Array[LaserGate] = [_frost_beam(Vector3(0.4, 0.5, -43.0), 2.8, 2.6, 0.5, 0.0), _frost_beam(Vector3(0.4, 0.5, -47.0), 2.8, 2.6, 0.5, 0.0)]
	var tower: Dictionary = _ledge(Vector3(0.4, 3.8, -53.6), Vector3(4.0, 7.0, 3.2), "alt")
	var cp: Dictionary = _cp(Vector3(0.4, 3.8, -62.7))
	_curtain_wall(Vector3(0, 0, -30.0))
	# SHORTCUT: two 1 m merlons on the outer parapet - past both beams without waiting
	var m1: Dictionary = _blk(Vector3(3.0, 1.0, -42.6), 1.0, 1.0, "accent", 1.0, false)
	var m2: Dictionary = _blk(Vector3(3.0, 1.6, -48.4), 1.0, 1.0, "accent", 1.0, false)
	_hop(cp0, w1, Vector3(0, 0, 2.2))
	r_walk(_w(Vector3(0, 0, -6.4)))
	_wait(func() -> bool: return _ice_ok(eave, 0.0, 1.2))
	r_wallrun(_w(Vector3(-0.3, 0, -12.65)), _w(Vector3(-1.8, 1.4, -16.6)), _w(Vector3(-1.8, 1.4, -27.5)), _w(Vector3(0.4, 0, -34.8)))
	if route_variant == 2:
		_hop(w2, m1)
		_hop(m1, m2)
		r_mantle(_w(_edge(m2, tower["c"])), _w((tower["c"] as Vector3) + Vector3(0.6, 0, 0.3)))
	else:
		_hop(w2, w3, Vector3(0, 0, 3.8))
		r_walk(_w(Vector3(0.4, 0.5, -41.4)))
		_wait(func() -> bool: return _laser_off(beams, 0.0, 1.0))
		r_walk(_w(Vector3(0.4, 0.5, -49.0)))
		r_mantle(_w(Vector3(0.4, 0.5, -49.65)), _w((tower["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(tower, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	w3.clear()
	return cp["c"]


## The curtain wall under the wall-walk (decor): a long mass of blue ice below the walk's line,
## crenellated parapets along its outer side, towers at the breach and at the end.
func _curtain_wall(c: Vector3) -> void:
	var ice: ShaderMaterial = GlacierFx.glass_mat(0.8, 0.0, 0.94, Color(0.12, 0.28, 0.6), Color(0.6, 0.85, 1.0))
	var stone: StandardMaterial3D = Look.flat(Color(0.34, 0.4, 0.5), 0.85)
	# the wall body under the walk, broken by the breach (local z -13..-33)
	for seg: Vector2 in [Vector2(-3.0, -13.0), Vector2(-33.0, -58.0)]:
		var l: float = absf(seg.y - seg.x)
		add_child(Look.box(_sz(Vector3(3.0, 30.0, l)), ice, _w(Vector3(c.x + 0.2, -16.2, (seg.x + seg.y) * 0.5))))
	# rubble of the breach far below
	for i: int in 5:
		deco.boulder(_w(Vector3(kit.rng.randf_range(-2.0, 2.0), -18.0 + kit.rng.randf_range(-2.0, 2.0), kit.rng.randf_range(-30.0, -16.0))), kit.rng.randf_range(1.2, 2.2))
	# inner-side crenellations along the walk (the outer side is open to the valley)
	for z: float in [-7.0, -10.0, -38.0, -41.0, -44.0, -47.0, -50.0]:
		add_child(Look.box(_sz(Vector3(0.8, 1.2, 1.2)), stone, _w(Vector3(-1.7, 0.1 if z > -30.0 else 0.6, z))))
	# the breach tower whose flank you run, and the end tower you climb
	add_child(Look.cylinder(3.4, 44.0, ice, _w(Vector3(-5.4, -8.0, -22.5)), 3.0, 14))
	add_child(Look.cylinder(3.8, 9.0, GlacierFx.glass_mat(1.3, 0.0, 0.9), _w(Vector3(-5.4, 18.5, -22.5)), 0.1, 14))
	add_child(Look.box(_sz(Vector3(1.2, 8.0, 18.0)), ice, _w(Vector3(-3.1, 1.2, -22.5))))
	add_child(Look.box(_sz(Vector3(4.0, 34.0, 3.2)), ice, _w(Vector3(0.4, -20.2, -53.6))))
	for k: int in 8:
		var a: float = TAU * float(k) / 8.0
		add_child(Look.box(Vector3(1.0, 1.0, 1.0), stone, _w(Vector3(0.4 + cos(a) * 2.4, 4.3, -53.6 + sin(a) * 1.3))))
	var snow: GPUParticles3D = GlacierFx.spindrift(_sz(Vector3(8.0, 3.0, 50.0)), _d(Vector3(1, 0.1, 0)), 14, 3.0)
	snow.position = _w(c + Vector3(-2.0, 2.0, 0))
	add_child(snow)


# ---- stage 13: Courtyard of Winds - blocks across the courtyard between gusts, then stand under the
# great bell on purpose: it hurls you over the well to the far deck; boost off it to the keep steps -----

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var b1: Dictionary = _blk(Vector3(0, 0.6, -8.8), 2.0, 2.0)
	var b2: Dictionary = _blk(Vector3(-1.6, 1.2, -14.6), 1.8, 1.8, "alt")
	var b3: Dictionary = _blk(Vector3(0.2, 1.8, -20.4), 2.0, 2.0)
	# the bell's side step: you board the plate from the side, out of the bell's swing
	var b4: Dictionary = _blk(Vector3(-3.4, 1.8, -25.8), 1.8, 1.8, "alt")
	var gust: GlacierGust = _gust(Vector3(-0.5, 3.5, -12.3), Vector3(14.0, 10.0, 14.6), Vector3(28, 0, 0), 3.4, 0.0, 0.8, 0.45)
	var plate := Vector3(0.2, 1.8, -26.6)
	_blk(plate, 1.8, 1.8, "accent", 0.8)
	var bell: Pendulum = kit.pendulum(_w(plate + Vector3(0, 1.25 + 9.0, 0)), 9.0, 3.2, 0.0, _yaw + 90.0, 60.0)
	_bell_dressing(bell, plate)
	var deck_c := Vector3(0.2, -0.7, -43.0)
	_blk(deck_c, 3.4, 10.0, "main", 1.0)
	kit.boost(_w(Vector3(0.2, -0.7, -46.0)), _sz(Vector3(3.2, 0.4, 4.0)), _yaw, 20.0)
	var cp: Dictionary = _cp(Vector3(0.2, 0.0, -61.0))
	_courtyard(Vector3(0, 0, -30.0))
	var prev: Dictionary = cp0
	for b: Dictionary in [b1, b2, b3]:
		r_walk(_w(_edge(prev, b["c"], 0.9)))
		_wait(func() -> bool: return gust.is_calm_for(Game.course_time, 1.0))
		_hop(prev, b)
		prev = b
	_hop(b3, b4)
	# step on right after the bell has swept back over the plate; it returns and hurls us forward
	var fwd: Vector3 = _d(Vector3.FORWARD)
	_wait(func() -> bool:
		var t: float = Game.course_time + 0.6
		var w: float = bell.angle_at(t + 0.02) - bell.angle_at(t)
		var along: float = (bell.global_basis * Vector3.RIGHT).dot(fwd)
		return w * along < 0.0 and bell.angle_at(t) * along < -0.3)
	_hop(b4, _area(plate, 0.9, 0.9))
	route.append({"kind": "kick", "from": _w(plate), "to": _w(deck_c + Vector3(0, 0, 1.0))})
	r_jump(_w(Vector3(0.2, -0.7, -47.6)), _w((cp["c"] as Vector3) + Vector3(0, 0, 1.0)))
	route[route.size() - 1]["speed"] = 20.0
	r_checkpoint()
	return cp["c"]


## The great bell: the hammer is a bronze bell rimed with ice, hung from a frost-bound gantry.
func _bell_dressing(bell: Pendulum, plate: Vector3) -> void:
	var arm: Node3D = bell.get_child(0) as Node3D
	var bronze: StandardMaterial3D = Look.flat(Color(0.62, 0.45, 0.25), 0.35, 0.8)
	var bell_body := Look.cylinder(1.25, 1.8, bronze, Vector3(0, -9.0 + 0.4, 0), 0.7, 16)
	arm.add_child(bell_body)
	arm.add_child(Look.cylinder(1.35, 0.3, GlacierFx.snow_mat(), Vector3(0, -9.0 + 1.35, 0), 0.75, 16))
	kit.arch(_w(plate + Vector3(0, -12.0, 0)), 9.0, 23.0, _yaw, Color(0.4, 0.5, 0.65))
	kit.glow_strip(_w(plate + Vector3(0, 0.03, 0)), Vector3(1.2, 0.05, 1.2), LedgeBlock.LIP_COLOR)


## The courtyard: flagstones of snow far below the rooftops you cross, the keep's wall ahead with its
## glowing windows, a frozen well, towers at the corners. `c` = local centre at path level.
func _courtyard(c: Vector3) -> void:
	var ice: ShaderMaterial = GlacierFx.glass_mat(0.9, 0.0, 0.94, Color(0.12, 0.28, 0.6), Color(0.6, 0.85, 1.0))
	var stone: StandardMaterial3D = Look.flat(Color(0.34, 0.4, 0.5), 0.85)
	var yard := Look.box(_sz(Vector3(40.0, 1.0, 70.0)), GlacierFx.snow_mat(0.05), _w(c + Vector3(0, -12.5, 0)))
	add_child(yard)
	# the frozen well under the bell's throw
	add_child(Look.cylinder(3.5, 1.4, stone, _w(Vector3(0.2, -11.5, -34.0)), 3.5, 20))
	add_child(Look.cylinder(3.0, 0.3, GlacierFx.glass_mat(1.6, 0.0, 0.9), _w(Vector3(0.2, -10.7, -34.0)), 3.0, 20))
	for p: Vector3 in [Vector3(-16.0, 0, -8.0), Vector3(16.0, 0, -8.0), Vector3(-16.0, 0, -52.0), Vector3(16.0, 0, -52.0)]:
		add_child(Look.cylinder(3.0, 40.0, ice, _w(c + p + Vector3(0, -2.0, 0)), 2.8, 14))
		add_child(Look.cylinder(3.4, 8.0, GlacierFx.glass_mat(1.3, 0.0, 0.9), _w(c + p + Vector3(0, 22.0, 0)), 0.1, 14))
	# the keep's front wall behind the last deck, windows glowing warm
	# (a tall doorway where the route runs in: the Hall of Ice lies behind it)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(_sz(Vector3(15.0, 40.0, 6.0)), ice, _w(c + Vector3(sx * 11.5, 6.0, -40.0))))
	add_child(Look.box(_sz(Vector3(8.2, 26.0, 6.0)), ice, _w(c + Vector3(0, 19.0 + 0.5, -40.0))))
	add_child(Look.box(_sz(Vector3(8.6, 0.6, 6.4)), Look.flat(GlacierFx.GLOW, 0.3, 0.0, 2.0), _w(c + Vector3(0, 6.6, -40.0))))
	for i: int in 5:
		for j: int in 2:
			add_child(Look.box(_sz(Vector3(1.4, 2.6, 0.3)), Look.flat(GlacierFx.WARM, 0.3, 0.0, 2.4), _w(c + Vector3(-12.0 + float(i) * 6.0, 10.0 + float(j) * 7.0, -36.8))))
	var gusts: GPUParticles3D = GlacierFx.blizzard(_sz(Vector3(40.0, 16.0, 50.0)), _d(Vector3(1, 0, 0)), 60, 12.0)
	gusts.position = _w(c + Vector3(0, 2.0, 0))
	add_child(gusts)


# ---- stage 14: The Hall of Ice - five panes of thin ice over the undercroft (never stop), a beam
# under two frost beams, and the aurora gate up to the tower -------------------------------------------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var pc: Array[Vector3] = [Vector3(0, 0, -8.2), Vector3(1.6, 0.3, -13.9), Vector3(-0.2, 0.6, -19.6), Vector3(1.4, 0.9, -25.3), Vector3(0, 1.2, -31.0)]
	var panes: Array[Dictionary] = []
	for p: Vector3 in pc:
		panes.append(_thin(p, 2.0, 2.0, 0.55, 2.4))
	_crevasse(Vector3(0.6, -1.0, -19.5), 12.0, 27.0)
	_blk(Vector3(0, 1.2, -40.2), 1.2, 9.0, "accent", 0.6)
	var beams: Array[LaserGate] = [_frost_beam(Vector3(0, 1.2, -38.0), 2.8, 2.2, 0.5, 0.0), _frost_beam(Vector3(0, 1.2, -42.4), 2.8, 2.2, 0.5, -0.22)]
	var gate_floor: Dictionary = _blk(Vector3(0, 1.2, -48.6), 4.0, 4.0, "alt", 1.0)
	var cp_c := Vector3(0, 9.2, -60.0)
	var cp: Dictionary = _cp(cp_c)
	var entry := Vector3(0, 1.2, -49.4)
	var exit_c := cp_c + Vector3(0, 0, 2.2)
	kit.portal(_w(entry), _yaw, _w(exit_c), _yaw, 3.0)
	_gate_dressing(entry, exit_c)
	_hall(Vector3(0, 1.2, -27.0), 58.0)
	var prev: Dictionary = cp0
	for i: int in panes.size():
		_hop(prev, panes[i])
		prev = panes[i]
	r_jump(_w(_edge(prev, Vector3(0, 1.2, -35.7))), _w(Vector3(0, 1.2, -36.2)))
	r_walk(_w(Vector3(0, 1.2, -36.4)))
	_wait(func() -> bool: return _beams_pass(beams, [0.25, 0.75], 0.3))
	r_walk(_w(Vector3(0, 1.2, -44.5)))
	r_jump(_w(Vector3(0, 1.2, -44.4)), _w(Vector3(0, 1.2, -47.0)))
	r_portal(_w(entry), _w(exit_c))
	r_walk(_w(cp_c))
	r_checkpoint()
	gate_floor.clear()
	return cp_c


## Every beam in `gs` is dark when a runner leaving now passes it `leads[i]` s from now (+- m).
static func _beams_pass(gs: Array, leads: Array, m: float) -> bool:
	for i: int in gs.size():
		var a: float = float(leads[i])
		var s: float = a - m
		while s <= a + m:
			if (gs[i] as LaserGate).is_on_at(Game.course_time + s):
				return false
			s += 0.04
	return true


## The Hall of Ice: the keep's great hall - pillars of glowing ice either side, a vaulted ceiling far
## overhead with chandeliers of icicles, banners, warm lamps, frost drifting in the air.
func _hall(c: Vector3, length: float) -> void:
	var ice: ShaderMaterial = GlacierFx.glass_mat(1.1, 0.4, 0.9, Color(0.1, 0.24, 0.58), Color(0.62, 0.86, 1.0))
	for side: float in [-1.0, 1.0]:
		add_child(Look.box(_sz(Vector3(2.0, 36.0, length)), ice, _w(c + Vector3(side * 9.0, 4.0, 0))))
		for i: int in 6:
			var z: float = c.z + length * 0.5 - 4.0 - float(i) * (length - 8.0) / 5.0
			add_child(Look.cylinder(0.9, 30.0, ice, _w(Vector3(c.x + side * 6.4, c.y + 1.0, z)), 0.7, 10))
			kit.banner(_w(Vector3(c.x + side * 7.6, c.y + 4.0, z + 2.0)), 5.0, GlacierFx.AURORA_V if i % 2 == 0 else GlacierFx.GLOW, _yaw)
			deco.lantern(_w(Vector3(c.x + side * 5.6, c.y + 6.0, z - 2.0)), 0.5, i % 2 == 0)
	# vaults and chandeliers overhead
	for i: int in 4:
		var z2: float = c.z + length * 0.5 - 8.0 - float(i) * (length - 16.0) / 3.0
		add_child(Look.box(_sz(Vector3(18.0, 1.4, 1.6)), ice, _w(Vector3(c.x, c.y + 14.0, z2))))
		var ch := Node3D.new()
		for k: int in 10:
			var a: float = TAU * float(k) / 10.0
			var l: float = kit.rng.randf_range(0.8, 2.2)
			ch.add_child(Look.cylinder(0.02, l, GlacierFx.ice_mat(GlacierFx.ICE, 0.9, 0.85), Vector3(cos(a) * 1.4, -l * 0.5, sin(a) * 1.4), 0.14, 6))
		ch.add_child(Look.cylinder(1.6, 0.2, Look.flat(Color(0.25, 0.25, 0.3), 0.5, 0.7), Vector3.ZERO, 1.6, 16))
		var l2 := OmniLight3D.new()
		l2.light_color = GlacierFx.GLOW
		l2.light_energy = 1.6
		l2.omni_range = 12.0
		l2.position = Vector3(0, -1.0, 0)
		ch.add_child(l2)
		ch.position = _w(Vector3(c.x, c.y + 12.0, z2))
		add_child(ch)
	var dust: GPUParticles3D = GlacierFx.glitter(_sz(Vector3(14.0, 10.0, length)), 70)
	dust.position = _w(c + Vector3(0, 3.0, 0))
	add_child(dust)


# ---- stage 15: Tower of Rime - mantle up the tower's rime-crusted shoulders under falling icicles,
# run the tower wall, a last mantle to the top ----------------------------------------------------------

func _stage_15() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var l1: Dictionary = _ledge(Vector3(0, 3.3, -7.0), Vector3(3.4, 7.0, 3.0))
	var ic1: GlacierIcicle = _icicle(Vector3(0, 3.3, -6.4), 5.2, 3.0, 0.0, 1.0)
	var l2: Dictionary = _ledge(Vector3(-0.6, 6.6, -12.6), Vector3(3.0, 10.0, 3.0), "alt")
	_panel(-2.3, 7.8, -15.5, -31.5, 6.5)
	var l3: Dictionary = _blk(Vector3(-0.2, 6.6, -36.6), 3.6, 5.0, "alt")
	var l4: Dictionary = _ledge(Vector3(-0.2, 9.9, -43.4), Vector3(4.0, 7.0, 3.2))
	var ic2: GlacierIcicle = _icicle(Vector3(-0.2, 9.9, -42.8), 5.2, 3.0, -0.5, 1.0)
	var cp: Dictionary = _cp(Vector3(-0.2, 9.9, -52.4))
	_tower_body(Vector3(0, 0, -24.0))
	for ic: GlacierIcicle in [ic1, ic2]:
		deco.overhang(ic.position + Vector3(0, 5.2 + 1.8, 0), Vector3(4.6, 1.2, 3.6), _yaw)
	_wait(func() -> bool: return _ice_ok([ic1], 0.3, 1.6))
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -6.3)))
	r_mantle(_w(_edge(l1, l2["c"])), _w((l2["c"] as Vector3) + Vector3(0, 0, 0.3)))
	r_wallrun(_w(Vector3(-0.5, 6.6, -13.75)), _w(Vector3(-1.8, 8.0, -17.4)), _w(Vector3(-1.8, 8.0, -29.4)), _w(Vector3(0.0, 6.6, -35.9)))
	_wait(func() -> bool: return _ice_ok([ic2], 0.3, 1.8))
	r_mantle(_w(_edge(l3, l4["c"])), _w((l4["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(l4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## The tower the stage climbs: a great drum of blue ice with rime bands, arrow slits glowing, a
## spire above. `c` = local centre at the stage's base level.
func _tower_body(c: Vector3) -> void:
	var ice: ShaderMaterial = GlacierFx.glass_mat(0.9, 0.2, 0.94, Color(0.12, 0.28, 0.6), Color(0.6, 0.85, 1.0))
	var tc: Vector3 = c + Vector3(-9.5, 0, 0)
	add_child(Look.cylinder(7.0, 70.0, ice, _w(tc + Vector3(0, -15.0, 0)), 6.4, 20))
	add_child(Look.cylinder(7.6, 14.0, GlacierFx.glass_mat(1.4, 0.0, 0.9), _w(tc + Vector3(0, 27.0, 0)), 0.2, 20))
	for i: int in 4:
		add_child(Look.cylinder(7.1, 0.6, GlacierFx.snow_mat(), _w(tc + Vector3(0, -2.0 + float(i) * 5.5, 0)), 7.1, 20))
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		add_child(Look.box(Vector3(0.5, 1.8, 0.3), Look.flat(GlacierFx.WARM, 0.3, 0.0, 2.6), _w(tc + Vector3(cos(a) * 7.05, 4.0 + float(i % 3) * 5.0, sin(a) * 7.05))))


# ---- stage 16: Avalanche Couloirs - off the tower down an ice chute, then across three avalanche
# gullies on rock stepping stones, sheltering on the ridges between the slides (and in the ice cave in
# the middle of the widest) --------------------------------------------------------------------------------

func _stage_16() -> Vector3:
	_slide(Vector3(0, 0.0, -2.9), 13.0, 21.0, 3.2)
	var lip: Vector3 = _slide_end(Vector3(0, 0.0, -2.9), 13.0, 21.0)
	var y: float = -7.0
	var a: Dictionary = _ridge_block(Vector3(0, y, -31.0), 5.0, 6.0)
	# gully 1
	var g1: GlacierAvalanche = _couloir(-42.1, 16.0, y, 4.2, 0.0)
	var k1: Dictionary = _stone(Vector3(0.4, y, -39.4), 2.0)
	var k2: Dictionary = _stone(Vector3(-0.4, y, -45.8), 2.0)
	var b: Dictionary = _ridge_block(Vector3(0, y, -54.2), 4.0, 6.0)
	# gully 2
	var g2: GlacierAvalanche = _couloir(-65.3, 16.0, y, 4.2, 0.45)
	var k3: Dictionary = _stone(Vector3(0.5, y, -62.6), 2.0)
	var k4: Dictionary = _stone(Vector3(-0.3, y, -69.0), 1.8)
	var c: Dictionary = _ridge_block(Vector3(0, y, -77.4), 4.0, 6.0)
	# gully 3: the widest - an ice cave in the middle to duck into while a slide goes over
	var g3: GlacierAvalanche = _couloir(-92.4, 24.0, y, 3.4, 0.2)
	var k5: Dictionary = _stone(Vector3(0.4, y, -85.8), 2.0)
	var cave: Dictionary = _stone(Vector3(0, y, -92.4), 4.0)
	_ice_cave(g3, Vector3(0, y, -92.4))
	var k6: Dictionary = _stone(Vector3(-0.4, y, -99.0), 2.0)
	var cp: Dictionary = _cp(Vector3(0, y, -107.4))
	# down the chute and off the lip onto the first ridge
	r_walk(_w(Vector3(0, 0, -2.2)))
	r_jump(_w(lip + Vector3(0, 0, 0.6)), _w((a["c"] as Vector3) + Vector3(0, 0, 0.8)))
	route[route.size() - 1]["speed"] = 19.0
	# each gully: wait on the ridge for the slide to pass, then cross before the next
	var gullies: Array = [[g1, k1, k2, b, a], [g2, k3, k4, c, b]]
	for gv: Array in gullies:
		var ga: GlacierAvalanche = gv[0]
		var from_d: Dictionary = gv[4]
		r_walk(_w(_edge(from_d, gv[1]["c"], 0.9)))
		_wait(func() -> bool: return _gully_clear(ga, 0.0, 3.2))
		_hop(from_d, gv[1])
		_hop(gv[1], gv[2])
		_hop(gv[2], gv[3], Vector3(0, 0, 1.2))
	r_walk(_w(_edge(c, k5["c"], 0.9)))
	_wait(func() -> bool: return _gully_clear(g3, 0.0, 1.9))
	_hop(c, k5)
	_hop(k5, cave)
	# in the cave: let the next slide go over, then out
	_wait(func() -> bool: return _gully_clear(g3, 0.0, 1.9))
	_hop(cave, k6)
	_hop(k6, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## No avalanche front crosses the path line of this gully during [now + a, now + b].
static func _gully_clear(g: GlacierAvalanche, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		var z: float = g.front_z_at(Game.course_time + s)
		if not is_nan(z) and absf(z - g.path_lz) < 5.0:
			return false
		s += 0.05
	return true


## An avalanche gully crossing the path at local z `zc`: the slope comes down from the right
## (+X local) and drops away to the left under the path. Returns its avalanche.
func _couloir(zc: float, width: float, path_y: float, period: float, phase: float) -> GlacierAvalanche:
	var grade: float = 0.5
	var up: float = 20.0
	var g := GlacierAvalanche.new()
	g.length = 48.0
	g.drop = 48.0 * grade
	g.width = width
	g.height = 9.0
	g.depth = 6.0
	g.period = period
	g.phase = phase
	g.run_time = minf(3.4, period - 1.3)
	g.warn = minf(1.3, period - g.run_time)
	# the slope surface runs 3 m under the stepping stones where the path crosses
	g.position = _w(Vector3(up, path_y - 3.0 + up * grade, zc))
	g.rotation_degrees.y = _yaw + 90.0
	g.path_lz = -up
	add_child(g)
	# the gully: a snow slope between two rock fins, a cornice at the top
	var slope_len: float = sqrt(g.length * g.length + g.drop * g.drop)
	var sn := Look.box(Vector3(width, 1.0, slope_len), GlacierFx.snow_mat(0.04), Vector3(0, -g.drop * 0.5 - 0.5, -g.length * 0.5))
	sn.rotation.x = -atan(grade)
	g.add_child(sn)
	for sx: float in [-1.0, 1.0]:
		var fin := Look.box(Vector3(3.0, 7.0, slope_len), GlacierFx.rock_mat(0.05), Vector3(sx * (width * 0.5 + 1.5), -g.drop * 0.5 + 1.5, -g.length * 0.5))
		fin.rotation.x = -atan(grade)
		g.add_child(fin)
		var cap := Look.box(Vector3(3.4, 0.6, slope_len), GlacierFx.snow_mat(), Vector3(sx * (width * 0.5 + 1.5), -g.drop * 0.5 + 5.2, -g.length * 0.5))
		cap.rotation.x = -atan(grade)
		g.add_child(cap)
	var cornice := Look.box(Vector3(width + 4.0, 3.0, 4.0), GlacierFx.snow_mat(), Vector3(0, 1.0, 2.2))
	g.add_child(cornice)
	g.add_child(Look.box(Vector3(width + 3.0, 1.2, 2.0), GlacierFx.glass_mat(0.9, 0.3, 0.9), Vector3(0, 0.0, 0.9)))
	return g


## A rock stepping stone in a gully (a snow-capped boulder top, 2 m on a rock stack).
func _stone(c: Vector3, s: float) -> Dictionary:
	kit.plat(_w(c), Vector3(s, 0.8, s), "alt", 0.0, _yaw)
	var stack := Look.box(Vector3(s * 0.9, 12.0, s * 0.9), GlacierFx.rock_mat(0.1), _w(c + Vector3(0, -6.8, 0)))
	stack.rotation.y = deg_to_rad(_yaw + kit.rng.randf_range(-8.0, 8.0))
	add_child(stack)
	return {"c": c, "hx": s * 0.5, "hz": s * 0.5}


## A ridge between gullies: a broad rock shelf the avalanches never reach.
func _ridge_block(c: Vector3, sx: float, sz: float) -> Dictionary:
	var d: Dictionary = _blk(c, sx, sz, "main", 1.2, false)
	add_child(Look.box(_sz(Vector3(sx + 1.0, 30.0, sz * 0.8)), GlacierFx.rock_mat(0.05), _w(c + Vector3(0, -16.2, 0))))
	deco.boulder(_w(c + Vector3(sx * 0.5 + 0.6, 0.2, 0)), 1.2)
	return d


## The ice cave in the middle of a gully: a thick lip of glacier ice arching over the stepping stone,
## registered as a shelter with the avalanche (the slide goes over it).
func _ice_cave(g: GlacierAvalanche, c: Vector3) -> void:
	var ice: ShaderMaterial = GlacierFx.glass_mat(1.0, 0.3, 0.92)
	# a roof of ice over the stone, walled on the uphill side only (the path runs through it)
	add_child(Look.box(_sz(Vector3(7.0, 1.6, 5.4)), ice, _w(c + Vector3(0.8, 4.8, 0))))
	add_child(Look.box(_sz(Vector3(1.4, 6.0, 5.4)), ice, _w(c + Vector3(3.6, 1.8, 0))))
	for sz: float in [-1.0, 1.0]:
		add_child(Look.cylinder(0.5, 6.0, ice, _w(c + Vector3(-2.4, 1.2, sz * 2.3)), 0.4, 8))
	for k: int in 6:
		add_child(Look.cylinder(0.02, kit.rng.randf_range(0.5, 1.2), GlacierFx.ice_mat(GlacierFx.ICE, 0.7, 0.85),
			_w(c + Vector3(-2.3 + float(k) * 0.9, 3.7, kit.rng.randf_range(-2.4, 2.4))), 0.12, 6))
	var l := OmniLight3D.new()
	l.light_color = GlacierFx.GLOW
	l.light_energy = 1.4
	l.omni_range = 6.0
	l.position = _w(c + Vector3(0, 2.0, 0))
	add_child(l)
	var lc: Vector3 = g.to_local(_w(c + Vector3(0, 1.6, 0)))
	g.add_shelter(lc, Vector3(4.6, 3.4, 4.6))


## A portcullis block: a crusher dressed as a slab of iron-banded ice dropping in the gate
## passage (its guide columns flank the passage). `c` = floor centre (local).
func _portcullis(c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(c), size, lift, period, phase, _yaw)
	var iron: StandardMaterial3D = Look.flat(Color(0.2, 0.21, 0.25), 0.5, 0.7)
	for k: int in 3:
		cr.add_child(Look.box(Vector3(size.x + 0.08, 0.14, size.z + 0.08), iron, Vector3(0, -size.y * 0.5 + 0.35 + float(k) * 0.5, 0)))
	for sx: float in [-0.35, 0.0, 0.35]:
		cr.add_child(Look.cylinder(0.07, 0.5, iron, Vector3(sx * size.x, -size.y * 0.5 - 0.25, 0), 0.02, 6))
	var puff: GPUParticles3D = GlacierFx.powder(maxf(size.x, size.z) * 0.4, 12, 1.3)
	puff.position = _w(c + Vector3(0, 0.2, 0))
	add_child(puff)
	_slam_puffs.append([cr, puff, false])
	return cr


## The press is up (gap >= `head` m) over the whole window [now + a, now + b].
static func _open(cr: Crusher, a: float, b: float, head: float = 2.3) -> bool:
	var s: float = a
	while s <= b:
		if cr.gap_at(Game.course_time + s) < head or not cr.is_clear_for(Game.course_time + s, 0.0):
			return false
		s += 0.04
	return true


## The gatehouse around stage 11's frame: ice walls either side of the passage (the right one's
## outer face is the tower wall you can run), drum towers either side of the mouth, the front
## curtain wall running off both ways, a lintel over the mouth.
func _gatehouse() -> void:
	var ice: ShaderMaterial = GlacierFx.glass_mat(0.8, 0.0, 0.94, Color(0.12, 0.28, 0.6), Color(0.6, 0.85, 1.0))
	var cap: ShaderMaterial = GlacierFx.glass_mat(1.3, 0.0, 0.9)
	var stone: StandardMaterial3D = Look.flat(Color(0.34, 0.4, 0.5), 0.85)
	add_child(Look.box(_sz(Vector3(2.0, 12.0, 28.5)), ice, _w(Vector3(-3.2, 3.0, -17.0))))
	add_child(Look.box(_sz(Vector3(1.25, 12.0, 28.5)), ice, _w(Vector3(2.83, 3.0, -17.0))))
	add_child(Look.box(_sz(Vector3(7.8, 2.4, 3.0)), ice, _w(Vector3(-0.4, 8.0, -4.0))))
	for p: Vector3 in [Vector3(-6.8, 0, -3.6), Vector3(12.2, 0, -3.6)]:
		add_child(Look.cylinder(3.0, 40.0, ice, _w(p + Vector3(0, -6.0, 0)), 2.8, 14))
		add_child(Look.cylinder(3.4, 8.0, cap, _w(p + Vector3(0, 18.0, 0)), 0.1, 14))
		for k: int in 8:
			var a: float = TAU * float(k) / 8.0
			add_child(Look.box(Vector3(1.0, 1.1, 1.0), stone, _w(p + Vector3(cos(a) * 3.0, 14.4, sin(a) * 3.0))))
		deco.lantern(_w(p + Vector3(0, 14.0, 0)), 0.6)
	for side: float in [-1.0, 1.0]:
		var x0: float = -9.8 if side < 0.0 else 15.2
		var w := Look.box(_sz(Vector3(30.0, 30.0, 3.0)), ice, _w(Vector3(x0 + side * 15.0, -3.0, -2.0)))
		add_child(w)
		for k: int in 10:
			add_child(Look.box(_sz(Vector3(1.4, 1.2, 3.2)), stone, _w(Vector3(x0 + side * (1.5 + float(k) * 3.0), 12.6, -2.0))))
	for z: float in [-9.0, -16.0, -23.0]:
		kit.banner(_w(Vector3(-2.2, 4.5, z)), 3.2, GlacierFx.AURORA_V, _yaw + 90.0)
	var frost: GPUParticles3D = GlacierFx.glitter(_sz(Vector3(4.0, 6.0, 26.0)), 40)
	frost.position = _w(Vector3(0, 3.0, -16.0))
	add_child(frost)


## A snow cannon on the parapet: a piston dressed as a frost-rimed iron cannon that punches a ram
## of packed snow across the causeway. `floor_c` = the walkway floor beside it (local).
func _snow_cannon(floor_c: Vector3, period: float, phase: float) -> Piston:
	var p: Piston = kit.piston(_w(floor_c + Vector3(0, 1.3, 0)), Vector3(2.0, 1.3, 1.6), _yaw + 90.0, 3.4, period, phase, 8.0)
	var iron: StandardMaterial3D = Look.flat(Color(0.22, 0.24, 0.3), 0.5, 0.7)
	var barrel := Look.cylinder(0.75, 2.6, iron, _w(floor_c + Vector3(2.9, 1.9, 0)), 0.9, 12)
	barrel.rotation = Vector3(0, 0, PI * 0.5) if absf(fmod(absf(_yaw), 180.0)) < 1.0 else Vector3(PI * 0.5, 0, 0)
	add_child(barrel)
	add_child(Look.box(_sz(Vector3(2.4, 1.2, 2.2)), GlacierFx.rock_mat(0.1), _w(floor_c + Vector3(3.6, 0.6, 0))))
	var puff: GPUParticles3D = GlacierFx.powder(0.5, 8, 1.0)
	puff.position = _w(floor_c + Vector3(1.4, 1.2, 0))
	add_child(puff)
	_cannon_puffs.append([p, puff, false])
	_brazier(floor_c + Vector3(3.6, 1.2, 1.5))
	return p


static func _piston_clear(p: Piston, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


## The moat: a deep crevasse under the causeway, blue-lit far below.
func _moat(c: Vector3, length: float) -> void:
	_crevasse(c, 26.0, length)


## Chains running up from the drawbridge into the gatehouse (decor, ride with it).
func _drawbridge_chains(lift: MovingPlatform) -> void:
	var iron: StandardMaterial3D = Look.flat(Color(0.25, 0.26, 0.3), 0.5, 0.7)
	for sx: float in [-1.0, 1.0]:
		var ch := Look.box(Vector3(0.12, 9.0, 0.12), iron, _d(Vector3(sx * 1.2, 4.6, -1.5)))
		lift.add_child(ch)
	lift.add_child(Look.box(_sz(Vector3(2.7, 0.14, 3.5)), Look.flat(Color(0.35, 0.26, 0.2), 0.8), Vector3(0, 0.3, 0)))


## A brazier on the parapet: an iron bowl of blue-white frost fire (warm light, cold flame).
func _brazier(floor_c: Vector3) -> void:
	var iron: StandardMaterial3D = Look.flat(Color(0.22, 0.22, 0.26), 0.5, 0.7)
	var n := Node3D.new()
	n.add_child(Look.cylinder(0.08, 1.1, iron, Vector3(0, 0.55, 0), 0.06, 6))
	n.add_child(Look.cylinder(0.35, 0.3, iron, Vector3(0, 1.2, 0), 0.22, 10))
	n.add_child(Look.sphere(0.2, Look.flat(GlacierFx.WARM, 0.3, 0.0, 3.0), Vector3(0, 1.35, 0)))
	var fire: GPUParticles3D = Fx.embers({"amount": 12, "lifetime": 0.8, "extents": Vector3(0.18, 0.05, 0.18),
		"speed": Vector2(0.8, 1.8), "size": 0.2, "color": Fx.hot(GlacierFx.WARM, 2.4), "curve": "shrink",
		"aabb": AABB(Vector3(-1, -0.5, -1), Vector3(2, 3.5, 2))})
	fire.position = Vector3(0, 1.35, 0)
	n.add_child(fire)
	var o := OmniLight3D.new()
	o.light_color = GlacierFx.WARM
	o.light_energy = 1.4
	o.omni_range = 6.0
	o.position = Vector3(0, 1.8, 0)
	n.add_child(o)
	n.position = _w(floor_c)
	add_child(n)


## Spinning ice blades: sweeper bars dressed as the frozen sails of a windmill of ice.
func _ice_sweeper(floor_c: Vector3, arm: float, bars: int, period: float, phase: float) -> Sweeper:
	var sw: Sweeper = kit.sweeper(_w(floor_c), arm, bars, period, phase)
	var pivot: Node3D = sw.get_child(0) as Node3D
	var blade: StandardMaterial3D = GlacierFx.ice_mat(Color(1.0, 0.45, 0.5), 1.2, 0.9)
	for holder: Node in pivot.get_children():
		var h := holder as Node3D
		var n: int = int(arm / 0.6)
		for i: int in n:
			var x: float = 0.5 + float(i) * arm / float(n)
			var sp := Look.cylinder(0.1, 0.5, blade, Vector3(x, 0.72, 0), 0.0, 5)
			h.add_child(sp)
	deco.crystals(_w(floor_c), 0.8, GlacierFx.DANGER)
	return sw


## No sweeper bar comes within `min_ang` (rad) of world point `p` during [now + a, now + b].
static func _bar_far(sw: Sweeper, p: Vector3, a: float, b: float, min_ang: float) -> bool:
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


## An aurora gate's dressing: a frozen arch round the entry ring, motes swirling at both rings,
## and a burst of aurora light when you come out (fired on teleport).
func _gate_dressing(entry: Vector3, exit_c: Vector3) -> void:
	kit.arch(_w(entry), 3.4, 3.4, _yaw, Color(0.55, 0.75, 0.95))
	for at: Vector3 in [entry, exit_c]:
		var m: GPUParticles3D = GlacierFx.aurora_motes(Vector3(2.4, 2.4, 2.4), 22)
		m.position = _w(at + Vector3(0, 1.4, 0))
		add_child(m)
	var b: GPUParticles3D = GlacierFx.frost_burst(GlacierFx.AURORA_G, 44, 7.0)
	b.position = _w(exit_c + Vector3(0, 1.2, 0))
	add_child(b)
	_portal_bursts.append([_w(exit_c), [b]])


## The frozen lake: black open water between the floes (catches you: a fall), rimmed with shelf ice.
func _lake(c: Vector3, size: Vector2) -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.01, 0.03, 0.07)
	water.roughness = 0.04
	water.metallic = 0.6
	water.metallic_specular = 0.9
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, size.y)
	var mi := Look.mesh_node(pm, water, _w(c))
	mi.rotation.y = deg_to_rad(_yaw)
	add_child(mi)
	var net := KillZone.new()
	net.show_mesh = false
	net.size = _sz(Vector3(size.x, 1.0, size.y))
	net.position = _w(c) - Vector3(0, 0.6, 0)
	add_child(net)
	# pack ice drifting in the dark water (decor)
	var ice: StandardMaterial3D = GlacierFx.ice_mat(GlacierFx.SNOW, 0.15, 0.97)
	for i: int in 26:
		var p := Vector3(kit.rng.randf_range(-size.x * 0.5, size.x * 0.5), 0.05, kit.rng.randf_range(-size.y * 0.5, size.y * 0.5))
		if absf(p.x) < 8.0 and absf(p.z) < size.y * 0.45:
			p.x = signf(p.x + 0.01) * kit.rng.randf_range(8.0, size.x * 0.5)
		var s := Look.cylinder(kit.rng.randf_range(0.6, 2.2), 0.3, ice, _w(c + p), -1.0, 7)
		s.rotation.y = kit.rng.randf() * TAU
		add_child(s)
	# mist creeping over the water
	var mist: GPUParticles3D = GlacierFx.spindrift(_sz(Vector3(size.x, 1.5, size.y)), _d(Vector3(1, 0, 0.2)), 18, 4.0)
	mist.position = _w(c + Vector3(0, 0.8, 0))
	add_child(mist)


## Glare-ice block: a flat slick top (no grip - you land sliding) on a column of ice.
func _ice_blk(c: Vector3, sx: float, sz: float) -> Dictionary:
	kit.slick(_w(c), Vector3(sx, 0.5, sz), _yaw, 0.0)
	deco.serac(_w(c - Vector3(0, 0.5, 0)), clampf(minf(sx, sz) * 0.32, 0.35, 1.8), kit.rng.randf_range(30.0, 44.0))
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## The frozen waterfall: a cathedral of streaked blue ice spilling from the crest far above down
## into the valley haze, split by the chimney cleft (`o` = the chimney's base frame, local).
func _frozen_falls(o: Vector3) -> void:
	var falls: ShaderMaterial = GlacierFx.glass_mat(1.0, 1.0, 0.9)
	var deep: ShaderMaterial = GlacierFx.glass_mat(0.7, 0.8, 0.96, Color(0.08, 0.22, 0.5), Color(0.5, 0.78, 1.0))
	var bot: float = -46.0
	# the two flanks of the cleft (the lower tier, up to the ledge the chimney climbs to)
	for side: float in [-1.0, 1.0]:
		var x0: float = o.x + (3.1 if side > 0.0 else -2.9)
		var w: float = 26.0
		var top_y: float = o.y + 11.9 + (2.0 if side > 0.0 else 0.5)
		var c := Vector3(x0 + side * w * 0.5, (bot + top_y) * 0.5, o.z - 16.0)
		var slab := Look.box(_sz(Vector3(w, top_y - bot, 22.0)), falls, _w(c))
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slab)
		# bulging frozen columns down the face
		for i: int in 5:
			var cx: float = x0 + side * (2.5 + float(i) * 4.8)
			var r: float = kit.rng.randf_range(1.6, 2.6)
			var col := Look.cylinder(r, top_y - bot, deep, _w(Vector3(cx, (bot + top_y) * 0.5, o.z - 4.6)), r * 0.8, 10)
			col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(col)
			# an icicle fringe where each column spills over the tier
			for k: int in 3:
				var ic := Look.cylinder(0.02, kit.rng.randf_range(1.2, 3.0), GlacierFx.ice_mat(GlacierFx.ICE, 0.6, 0.85), _w(Vector3(cx + kit.rng.randf_range(-r, r), top_y - 1.5, o.z - 3.4 + kit.rng.randf_range(-0.5, 0.5))), 0.25, 6)
				add_child(ic)
		deco.drift(_w(Vector3(x0 + side * w * 0.5, top_y, o.z - 16.0)), _sz(Vector3(w * 0.55, 1.2, 11.0)))
	# the upper falls: the cathedral wall behind the tier, rising far above the course
	var up_c := Vector3(o.x, 30.0, o.z - 62.0)
	var upper := Look.box(_sz(Vector3(70.0, 150.0, 14.0)), falls, _w(up_c + Vector3(0, -30.0, 0)))
	upper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(upper)
	for i: int in 9:
		var cx2: float = o.x - 32.0 + float(i) * 8.0
		var r2: float = kit.rng.randf_range(2.4, 4.2)
		var h2: float = kit.rng.randf_range(90.0, 140.0)
		var col2 := Look.cylinder(r2, h2, deep, _w(Vector3(cx2, bot + h2 * 0.5, o.z - 54.5)), r2 * 0.7, 10)
		col2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(col2)
	# light and life: a cold glow inside the ice, frozen spray at the foot, glitter on the face,
	# spindrift pouring off the crest
	for k2: int in 3:
		var l := OmniLight3D.new()
		l.light_color = GlacierFx.GLOW
		l.light_energy = 2.2
		l.omni_range = 18.0
		l.position = _w(Vector3(o.x + (-8.0 + float(k2) * 8.0), o.y + 2.0 + float(k2) * 5.0, o.z - 8.0))
		add_child(l)
	var spray: GPUParticles3D = GlacierFx.spindrift(_sz(Vector3(40.0, 8.0, 10.0)), Vector3(0, 0.4, 1), 18, 5.0)
	spray.position = _w(Vector3(o.x, bot + 6.0, o.z - 10.0))
	add_child(spray)
	var face: GPUParticles3D = GlacierFx.glitter(_sz(Vector3(30.0, 22.0, 6.0)), 60)
	face.position = _w(Vector3(o.x, o.y + 4.0, o.z - 6.0))
	add_child(face)
	var crest: GPUParticles3D = GlacierFx.spindrift(_sz(Vector3(60.0, 6.0, 8.0)), _d(Vector3(0, -0.6, 1)), 16, 6.0)
	crest.position = _w(Vector3(o.x, 88.0, o.z - 58.0))
	add_child(crest)


## Blizzard gust over a stage (centre, local size, local peak push). Turned with the stage.
func _gust(c: Vector3, size: Vector3, push: Vector3, period: float, phase: float, hold: float = 1.0, travel: float = 0.5) -> GlacierGust:
	var g := GlacierGust.new()
	g.size = size
	g.push = push
	g.period = period
	g.phase = phase
	g.hold = hold
	g.travel = travel
	g.rotation_degrees.y = _yaw
	g.position = _w(c)
	add_child(g)
	return g


## Wall-run panel along the stage heading at local x, from z0 to z1 (z0 > z1), centred at height y.
func _panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> WallRunPanel:
	return kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)


## Ice slide down the stage heading from `top` (local, the upper edge of its surface): `length`
## along the slope, `pitch` degrees down. Rime rails along both sides.
func _slide(top: Vector3, length: float, pitch: float, width: float) -> SurfacePlatform:
	var r: float = deg_to_rad(pitch)
	var c: Vector3 = top + Vector3(0, -sin(r) * length * 0.5, -cos(r) * length * 0.5)
	var s: SurfacePlatform = kit.slick(_w(c), Vector3(width, 0.4, length), _yaw, -pitch)
	# frosted rails and a keel of blue ice under the chute
	var rail: StandardMaterial3D = GlacierFx.ice_mat(GlacierFx.SNOW, 0.3, 0.95)
	for sx: float in [-1.0, 1.0]:
		var rl := Look.box(Vector3(0.3, 0.35, length), rail, Vector3(sx * (width * 0.5 + 0.1), 0.05, 0))
		rl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.add_child(rl)
	var keel := Look.box(Vector3(width * 0.8, 1.6, length), GlacierFx.glass_mat(0.8, 0.0, 0.95), Vector3(0, -1.0, 0))
	s.add_child(keel)
	for k: int in 3:
		var sp: GPUParticles3D = GlacierFx.glitter(Vector3(width, 0.6, length * 0.3), 10)
		sp.position = Vector3(0, 0.4, -length * 0.35 + float(k) * length * 0.35)
		sp.local_coords = true
		s.add_child(sp)
	return s


## Lower end (lip) of a `_slide` from `top`.
func _slide_end(top: Vector3, length: float, pitch: float) -> Vector3:
	var r: float = deg_to_rad(pitch)
	return top + Vector3(0, -sin(r) * length, -cos(r) * length)


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
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	_env.sky.sky_material = sky_mat
	_env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	_env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_env.ambient_light_color = Color(0.46, 0.6, 0.88)
	_env.ambient_light_energy = 0.8
	_env.fog_light_color = Color(0.32, 0.42, 0.58)
	_env.fog_density = 0.0045
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.15
	_env.fog_sun_scatter = 0.2
	_env.fog_height = -14.0
	_env.fog_height_density = 0.02
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_saturation = 1.1
	_env.adjustment_contrast = 1.08
	# moonlight: cold, low and hard, from the moon's side of the sky
	_sun.light_color = Color(0.72, 0.84, 1.0)
	_sun.light_energy = 1.25
	_sun.rotation_degrees = Vector3(-34, 158, 0)
	# the fill becomes the aurora's green wash from the other side
	_fill.light_color = Color(0.45, 1.0, 0.72)
	_fill.light_energy = 0.28
	_fill.rotation_degrees = Vector3(-30, -20, 0)


# ---- live effects -------------------------------------------------------------------------------------

## [exit point, [bursts]] for every aurora gate: fired when the player comes out of it.
var _portal_bursts: Array[Array] = []
## [crusher, powder puff, was_down] for every portcullis: a puff of powder each time it slams.
var _slam_puffs: Array[Array] = []
## [piston, puff, was_punching] for every snow cannon: a blast of powder with every shot.
var _cannon_puffs: Array[Array] = []


func _ready() -> void:
	super()
	player.teleported.connect(_on_teleported)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	for rec: Array in _slam_puffs:
		var down: bool = (rec[0] as Crusher).gap_at(t) < 0.15
		if down and not bool(rec[2]):
			(rec[1] as GPUParticles3D).restart()
		rec[2] = down
	for rec2: Array in _cannon_puffs:
		var punching: bool = (rec2[0] as Piston).is_punching_at(t)
		if punching and not bool(rec2[2]):
			(rec2[1] as GPUParticles3D).restart()
		rec2[2] = punching


func _on_teleported() -> void:
	for rec: Array in _portal_bursts:
		var at: Vector3 = rec[0]
		if player.global_position.distance_to(at) < 4.0:
			for b: GPUParticles3D in rec[1]:
				b.restart()
				b.emitting = true


## Swap every walkable surface to the glacier shader (same colours, snow over blue ice).
func _glacier_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = BLOCK_SHADER
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


func _surroundings() -> void:
	# aurora curtains far out over the pass
	var span_c: Vector3 = Vector3(0, 0, -60)
	for i: int in 3:
		var q := QuadMesh.new()
		q.size = Vector2(700.0, 170.0)
		q.subdivide_width = 96
		q.subdivide_depth = 4
		var m := ShaderMaterial.new()
		m.shader = AURORA_SHADER
		m.set_shader_parameter("seed", float(i) * 3.7)
		m.set_shader_parameter("intensity", 1.0 - float(i) * 0.2)
		var mi := Look.mesh_node(q, m, span_c + Vector3(-120.0 + float(i) * 160.0, 150.0 + float(i) * 25.0, -420.0 + float(i) * 60.0))
		mi.rotation.y = deg_to_rad(-15.0 + float(i) * 22.0)
		mi.rotation.x = deg_to_rad(-12.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 200.0
		add_child(mi)
	# valley floor far below
	var floor_mi := Look.mesh_node(PlaneMesh.new(), GlacierFx.snow_mat(0.25), Vector3(0, -46.0, -120.0))
	(floor_mi.mesh as PlaneMesh).size = Vector2(1400, 1400)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mi)
