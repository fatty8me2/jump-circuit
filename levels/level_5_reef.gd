extends LevelBase
## 5. CORAL DEPTHS - a dive through a sunken reef, from the sunlit crest down to a glowing
## temple in the deep. (Stage list: see the header block below _build.)

const ROCK_SHADER: Shader = preload("res://visual/reef_rock.gdshader")
const SKY_SHADER: Shader = preload("res://visual/reef_sky.gdshader")

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: ReefDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (for set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}


func _configure() -> void:
	theme_id = "reef"
	music_track = "a"
	kill_y = -90.0
	route_variants = 2


# ---- local-frame helpers --------------------------------------------------------------------

func _frame(origin: Vector3, yaw_deg: float) -> void:
	_o = origin
	_yaw = yaw_deg
	_b = Basis(Vector3.UP, deg_to_rad(yaw_deg))


func _w(l: Vector3) -> Vector3:
	return _o + _b * l


## A local size (x across, z along) turned into world axes (frames only turn in 90 degree steps).
func _sz(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0 else size


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, stalk: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if stalk:
		deco.pinnacle(_w(c - Vector3(0, thick, 0)), clampf(minf(sx, sz) * 0.3, 0.35, 1.6), kit.rng.randf_range(26.0, 40.0))
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.8, stalk: bool = true) -> Dictionary:
	kit.disc(_w(c), r, thick, style, 0.0)
	if stalk:
		deco.pinnacle(_w(c - Vector3(0, thick, 0)), clampf(r * 0.45, 0.4, 1.8), kit.rng.randf_range(26.0, 40.0))
	return {"c": c, "r": r}


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


func _haz(c: Vector3, size: Vector3, yaw_extra: float = 0.0) -> void:
	kit.hazard(_w(c), size, _yaw + yaw_extra)
	# fire coral: red spiky growth on the kill brick so it reads as part of the reef
	var n: int = maxi(int(maxf(size.x, size.z) / 0.9), 1)
	var along: Vector3 = _b * Basis(Vector3.UP, deg_to_rad(yaw_extra)) * Vector3(1, 0, 0)
	if size.z > size.x:
		along = _b * Basis(Vector3.UP, deg_to_rad(yaw_extra)) * Vector3(0, 0, 1)
	for i: int in n:
		var f: float = (float(i) + 0.5) / float(n) - 0.5
		deco.staghorn(_w(c) + along * f * maxf(size.x, size.z) + Vector3(0, size.y * 0.5 - 0.1, 0), 0.45, Color(1.0, 0.25, 0.15))


## Kill brick just past block `b`, square to the arrival direction from `a` (punishes overshoot).
func _urchin_behind(a: Dictionary, b: Dictionary, width: float = 1.6) -> void:
	var ca: Vector3 = a["c"]
	var cb: Vector3 = b["c"]
	var d := Vector3(cb.x - ca.x, 0, cb.z - ca.z).normalized()
	var half: float = minf(float(b["hx"]) / maxf(absf(d.x), 0.001), float(b["hz"]) / maxf(absf(d.z), 0.001))
	var yaw_local: float = rad_to_deg(atan2(-d.x, -d.z))
	_haz(cb + d * (half + 0.55) + Vector3(0, 0.55, 0), Vector3(width, 1.5, 0.5), yaw_local)


func _wind(c: Vector3, size: Vector3, push: Vector3, max_rise: float = 14.0) -> WindZone:
	return kit.wind(_w(c), _sz(size), _b * push, max_rise)


func _jelly(c: Vector3, strength: float, r: float = 1.25, pts: Array[Vector3] = [], period: float = 5.0, phase: float = 0.0, bob: float = 0.0, bob_period: float = 3.0, tint: Color = Color(0, 0, 0, 0)) -> ReefJelly:
	var j := ReefJelly.new()
	j.strength = strength
	j.radius = r
	var wp: Array[Vector3] = []
	for p: Vector3 in pts:
		wp.append(_b * p)
	j.points = wp
	j.period = period
	j.phase = phase
	j.bob = bob
	j.bob_period = bob_period
	j.tint = tint if tint.a > 0.0 else [ReefDecor.PINK, ReefDecor.VIOLET, ReefDecor.CYAN][kit.rng.randi() % 3]
	j.position = _w(c)
	add_child(j)
	return j


## Checkpoint platform facing the next stage's heading (_next_yaw), dressed with anemones.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var h: float = size * 0.5 - 0.55
	deco.anemone(_w(c + Vector3(-h, 0, h)), 0.42)
	deco.anemone(_w(c + Vector3(h, 0, h)), 0.36)
	deco.sea_fan(_w(c + Vector3(-h, 0, -h)) , 2.4)
	deco.sea_fan(_w(c + Vector3(h, 0, -h)), 2.0)
	for side: float in [-1.0, 1.0]:
		deco.clump(_w(c + Vector3(side * (size * 0.5 + 0.2), -0.7, kit.rng.randf_range(-h, h))), 1.2)
	# banked-stage feedback: a fountain of bubbles and glints
	var burst: GPUParticles3D = ReefFx.burst(Color(0.7, 1.0, 1.0), 40, 6.0, true, 0.35, 1.6)
	burst.position = _w(c) + Vector3(0, 0.3, 0)
	add_child(burst)
	var glints: GPUParticles3D = ReefFx.burst(ReefDecor.CYAN, 30, 7.0, false, 0.25, 1.2)
	glints.position = _w(c) + Vector3(0, 0.5, 0)
	add_child(glints)
	_cp_bursts[cp] = [burst, glints]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


static func _laser_off(g: LaserGate, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


static func _piston_clear(p: Piston, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


static func _blink_on(bp: BlinkPlatform, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if not bp.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	deco = ReefDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, -90.0, -90.0, -90.0, -90.0, 0.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	# TEMP finish while the course is being built
	kit.plat(_w(Vector3(0, 0, -10)), Vector3(10, 1, 10))
	kit.finish(_w(Vector3(0, 0, -10)), _yaw)
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -8)))
	r_walk(_w(Vector3(0, 0, -10)))
	_surroundings()
	_reef_materials()


# ---- stage 1: Reef Crest - warm-up hops over coral heads, the first jellyfish ---------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	deco.pinnacle(_w(Vector3(0, -2, 0)), 3.5, 40.0)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	for p: Vector3 in [Vector3(-5.6, 0, 5.2), Vector3(5.8, 0, 4.6), Vector3(-5.9, 0, -4.8), Vector3(5.5, 0, -5.4)]:
		deco.brain(_w(p), kit.rng.randf_range(0.7, 1.1))
	for p: Vector3 in [Vector3(-4.2, 0, 6.0), Vector3(6.1, 0, 0.8), Vector3(-6.2, 0, 0.2), Vector3(3.6, 0, 6.2)]:
		deco.staghorn(_w(p), kit.rng.randf_range(0.9, 1.3))
	deco.sea_fan(_w(Vector3(-6.3, 0, -2.4)), 3.0, ReefDecor.VIOLET)
	deco.sea_fan(_w(Vector3(6.4, 0, -2.0)), 2.6, ReefDecor.PINK)
	kit.arch(_w(Vector3(0, 0, -6.6)), 5.0, 4.4, _yaw, ReefDecor.VIOLET.darkened(0.3))
	var a1: Dictionary = _blk(Vector3(0, 0, -12.2), 3.0, 3.0)
	var a2: Dictionary = _blk(Vector3(3.4, 1.0, -17.6), 2.6, 2.6, "alt")
	var a3: Dictionary = _blk(Vector3(0.6, 2.0, -23.0), 2.2, 2.2)
	var jc := Vector3(0.6, 1.0, -29.4)
	_jelly(jc, 17.0, 1.3, [], 5.0, 0.0, 0.0, 3.0, ReefDecor.PINK)
	var l1: Dictionary = _blk(Vector3(0.6, 4.6, -36.2), 3.4, 3.4, "alt")
	var cp: Dictionary = _cp(Vector3(0.6, 4.6, -45.0))
	_hop(start, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	r_jump(_w(_edge(a3, jc)), _w(jc))
	r_pad(_w(jc), _w((l1["c"] as Vector3) + Vector3(0, 0, 0.5)))
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Anemone Shelf - mantle up a coral wall, urchin-ringed stepping stones, a taller mantle ----

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var m1: Dictionary = _ledge(Vector3(0, 3.3, -7.2), Vector3(5.0, 5.3, 3.4))
	var u1: Dictionary = _blk(Vector3(-2.2, 3.3, -13.4), 1.8, 1.8)
	var u2: Dictionary = _blk(Vector3(1.8, 4.3, -17.6), 1.8, 1.8, "alt")
	var u3: Dictionary = _blk(Vector3(1.8, 4.3, -23.9), 1.6, 1.6)
	var u4: Dictionary = _blk(Vector3(-1.8, 5.3, -28.4), 1.8, 1.8, "alt")
	var m2: Dictionary = _ledge(Vector3(-1.8, 8.9, -34.2), Vector3(3.2, 5.0, 3.2))
	var cp: Dictionary = _cp(Vector3(-1.8, 8.9, -43.0))
	_urchin_behind(u1, u2)
	_urchin_behind(u2, u3)
	_haz(Vector3(0, 2.6, -15.6), Vector3(1.0, 0.9, 1.0))
	for p: Vector3 in [Vector3(-1.6, 3.3, -8.4), Vector3(1.9, 3.3, -6.0)]:
		deco.anemone(_w(p), 0.38)
	r_mantle(_w(Vector3(0, 0, -2.5)), _w(Vector3(0, 3.3, -7.4)))
	_hop(m1, u1)
	_hop(u1, u2)
	_hop(u2, u3)
	_hop(u3, u4)
	r_mantle(_w(_edge(u4, m2["c"])), _w((m2["c"] as Vector3) + Vector3(0, 0, 0.2)))
	_hop(m2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Kelp Current - narrow beams and small blocks in a steady cross-current ----------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var k1: Dictionary = _blk(Vector3(-1.0, 0, -9.0), 0.9, 6.0, "accent", 0.7)
	var k2: Dictionary = _blk(Vector3(-3.4, 1.0, -16.6), 1.6, 1.6)
	var k3: Dictionary = _blk(Vector3(-3.4, 1.0, -23.0), 0.8, 5.0, "accent", 0.7)
	var k4: Dictionary = _blk(Vector3(-0.6, 2.0, -29.0), 1.6, 1.6, "alt")
	var k5: Dictionary = _blk(Vector3(-2.8, 3.0, -34.0), 1.6, 1.6)
	var cp: Dictionary = _cp(Vector3(-1.4, 3.0, -42.2))
	_wind(Vector3(-1.0, 2.0, -21.5), Vector3(22, 12, 32), Vector3(13, 0, 0))
	_hop(cp0, k1, Vector3(0, 0, 1.2))
	r_walk(_w(Vector3(-1.0, 0, -10.8)))
	r_jump(_w(Vector3(-1.0, 0, -11.65)), _w(k2["c"]))
	_hop(k2, k3, Vector3(0, 0, 1.0))
	r_walk(_w(Vector3(-3.4, 1.0, -24.6)))
	r_jump(_w(Vector3(-3.4, 1.0, -25.15)), _w(k4["c"]))
	_hop(k4, k5)
	_hop(k5, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Jelly Drift - bounce across a chasm on drifting jellyfish -----------------------------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var j1c := Vector3(0, -1.5, -8.5)
	var j2c := Vector3(0, -0.5, -16.5)
	var j3c := Vector3(2.4, 0.5, -24.2)
	var j1: ReefJelly = _jelly(j1c, 18.0, 1.3, [Vector3(-2.2, 0, 0), Vector3(2.2, 0, 0)], 4.8, 0.0)
	var j2: ReefJelly = _jelly(j2c, 18.0, 1.3, [], 5.0, 0.0, 0.7, 3.2)
	var j3: ReefJelly = _jelly(j3c, 18.0, 1.3, [Vector3(0, 0, 1.8), Vector3(0, 0, -1.8)], 4.0, 0.25)
	var l4: Dictionary = _blk(Vector3(2.4, 3.5, -32.0), 2.4, 2.4, "alt")
	var cp: Dictionary = _cp(Vector3(0, 3.5, -40.0))
	r_jump_onto(_w(Vector3(0, 0, -2.65)), j1)
	route.append({"kind": "pad", "from": _w(j1c), "to_node": j2, "to_local": Vector3.ZERO, "to": Vector3.ZERO})
	route.append({"kind": "pad", "from": _w(j2c), "to_node": j3, "to_local": Vector3.ZERO, "to": Vector3.ZERO})
	r_pad(_w(j3c), _w(l4["c"]))
	_hop(l4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Hull Run - wall-run the broken stern across a gap, mantle up onto the wreck ------------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var r1: Dictionary = _blk(Vector3(0, 0, -8.0), 3.0, 4.0, "alt")
	kit.wallrun(_w(Vector3(2.3, 1.2, -19.5)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var r2: Dictionary = _blk(Vector3(-0.4, 0, -32.5), 3.6, 5.0, "alt")
	_ledge(Vector3(0, 3.5, -40.0), Vector3(8.0, 6.0, 3.5))
	_blk(Vector3(0, 3.5, -47.0), 8.0, 10.5, "alt", 1.0, false)
	_hop(cp0, r1, Vector3(0, 0, 0.8))
	r_wallrun(_w(Vector3(0.3, 0, -9.65)), _w(Vector3(1.8, 1.4, -13.6)), _w(Vector3(1.8, 1.4, -24.5)), _w(Vector3(-0.4, 0, -31.8)))
	r_mantle(_w(Vector3(-0.2, 0, -34.6)), _w(Vector3(-0.2, 3.5, -40.2)))
	var cp: Vector3 = Vector3(0, 3.5, -46.5)
	kit.checkpoint(_w(cp), _next_yaw)
	_cp_world.append(_w(cp))
	r_walk(_w(cp))
	r_checkpoint()
	return cp


# ---- stage 6: Cannon Deck (BRANCH) - run the gangway past the deck rams, or climb the fallen mast -----

func _stage_6() -> Vector3:
	# deck continues from stage 5's deck (which reaches local z = -5.75 here)
	var seg_a: Dictionary = _blk(Vector3(0, 0, -9.0), 3.0, 6.5, "alt", 1.0, false)
	var seg_b: Dictionary = _blk(Vector3(0, 0, -19.0), 3.0, 9.0, "alt", 1.0, false)
	var seg_c: Dictionary = _blk(Vector3(0, 0, -30.0), 3.0, 8.0, "alt", 1.0, false)
	var rams: Array[Piston] = []
	var zs: Array[float] = [-9.5, -19.5, -29.5]
	for i: int in zs.size():
		# rams punch from the starboard rail across the gangway (arrow = local -X)
		var p: Piston = kit.piston(_w(Vector3(3.3, 1.3, zs[i])), Vector3(2.0, 1.3, 1.6), _yaw + 90.0, 3.4, 3.0, 0.62 - 0.26 * float(i), 8.0)
		rams.append(p)
	var cp: Dictionary = _cp(Vector3(0, 0, -38.0))
	if route_variant == 0:
		# main: run the gangway, slipping past each ram between shots, hop the two broken planks
		for i: int in rams.size():
			var p: Piston = rams[i]
			var stop: Vector3 = Vector3(0, 0, zs[i] + 2.4)
			if i == 1:
				stop = Vector3(0, 0, -16.2)
				r_jump(_w(Vector3(0, 0, -12.0)), _w(stop))
			elif i == 2:
				stop = Vector3(0, 0, -27.2)
				r_jump(_w(Vector3(0, 0, -23.2)), _w(stop))
			else:
				r_walk(_w(stop))
			_wait(func() -> bool: return _piston_clear(p, 0.0, 0.75))
		_hop(seg_c, cp, Vector3(0, 0, 1.5))
	else:
		# alt: mantle the cargo stack, run the fallen mast, drop from the crow's nest to the bow
		pass
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
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	_env.sky.sky_material = sky_mat
	_env.fog_light_color = Color(0.05, 0.36, 0.46)
	_env.fog_density = 0.016
	_env.fog_aerial_perspective = 0.45
	_env.fog_sky_affect = 0.6
	_env.fog_sun_scatter = 0.0
	_env.fog_height = -18.0
	_env.fog_height_density = 0.012
	_env.ambient_light_color = Color(0.32, 0.72, 0.82)
	_env.ambient_light_energy = 0.78
	_env.glow_intensity = 0.85
	_env.glow_bloom = 0.12
	_env.glow_hdr_threshold = 1.05
	_env.adjustment_saturation = 1.22
	_env.adjustment_contrast = 1.06
	_sun.light_color = Color(0.72, 0.96, 1.0)
	_sun.light_energy = 1.15
	_sun.rotation_degrees = Vector3(-74, 25, 0)
	# the "fill" becomes a faint violet glow welling up from the abyss
	_fill.light_color = Color(0.45, 0.35, 0.9)
	_fill.light_energy = 0.3
	_fill.rotation_degrees = Vector3(62, 200, 0)


## Swap every walkable surface to the reef shader (same colours, sand and caustic light).
func _reef_materials() -> void:
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


func _surroundings() -> void:
	pass
