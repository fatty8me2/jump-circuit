extends LevelBase
## 36. LOTUS DRIFT - the most meditative of the four FLOW levels (docs/FLOW_BRIEF.md). A misty
## water garden at dusk, terraced down a hillside round a still lake: lily pads and stone causeways
## on a staircase of ponds, each pond spilling into the next over a weir. Paper lanterns glow on
## strings and in stone toro, willows trail their branches in the water, koi turn under the pads,
## wind chimes ring as you pass, and the first stars come out over a ring of far ridges.
## Easy to finish, hard to master: the SAFE LINE (route 0) is a calm walk and hop down the garden
## (hops 55-80 % of reach onto 2.6 m pads, no hazards, nothing to wait for); the FLOW LINE
## (route 1) strings the stream slides, lantern rings, lily-stem rails and half-pipes into one long
## breath at 18-30 m/s.
##
## Ten stages, nine checkpoints (each a round isle with a lotus bud that opens when you wake it);
## every stage is "isle -> cascade down a weir -> a pond tier -> isle", the path spiralling 30 degrees
## to the left per stage round a central lake:
##
##  1 Moon Gate        a stone path from the moon gate, a zig-zag boardwalk over the lilies
##  2 Lily Reach       seven lily pads in an S-bend, a stone landing, four more pads
##  3 Willow Walk      a long causeway, the moon bridge, a willow pavilion isle, three pads
##  4 Chime Terrace    a boardwalk with wind chimes, six pads, a long deck
##  5 Koi Garden       eight stepping stones over the koi, a causeway, pads
##  6 Lantern Reach    a lantern-strung bridge, a second moon bridge, an isle, five pads
##  7 Mist Falls       a boardwalk zig-zag, eight pads, a narrow deck
##  8 Pagoda Isle      stone path, pads, the pagoda isle, bamboo
##  9 Moonlit Pools    ten pads under the rising moon
## 10 The Great Lotus  the serene finale: a procession of pads to the giant lotus on the lake
##
## Own mechanics: LotusPad (lily pads that give under your feet), LotusChime (wind chimes ringing for
## your speed), LotusKoi (koi under the pads, leaping), LotusBloom (the checkpoint lotus). Visuals:
## visual/lotus_{sky,decor,fx}.gd, lotus_{tile,water,stream}.gdshader. Route variants for the bot:
## 0 = the safe line, 1 = the flow line. Every wait the bot makes holds for 1.5 s more.

const GOLD := Color(1.0, 0.68, 0.28)
const PINK := Color(1.0, 0.5, 0.7)
const JADE := Color(0.35, 0.82, 0.68)
const TILE_SHADER: Shader = preload("res://visual/lotus_tile.gdshader")

## Slope of the cascade walkways (degrees below horizontal).
const CASCADE_DEG: float = 12.0
## Water sits this far under the path level of its tier.
const WATER_DROP: float = 0.2
## Hubs (isles) stand this much proud of the paths that run into them.
const HUB_RISE: float = 0.04

var _tuning: MovementTuning
var deco: LotusDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D

# ---- the path cursor (world) ---------------------------------------------------------------------
## Where the last element ended: for a slab, the middle of its far edge (on its top); for a round
## pad, its centre (the edge is `_edge_r` further on).
var _pos: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _edge_r: float = 0.0
## True when the last element is contiguous with where the next one starts (no gap to jump).
var _flush: bool = true
var _have_jump: bool = false
var _jump_from: Vector3 = Vector3.ZERO

## World-space checkpoint centres in build order (the isles' tops).
var _cp_world: Array[Vector3] = []
var _cp_nodes: Array[Checkpoint] = []
var _finish_pos: Vector3 = Vector3.ZERO
## Every walkable piece: {"top", "r" (half the longer side), "yaw", "size"} for the scenery to keep clear.
var _floors: Array[Dictionary] = []
## One entry per pond tier: {"y": path level, "pts": PackedVector3Array of path points, "half": Vector2 margins}
var _tiers: Array[Dictionary] = []
## One entry per cascade: {"a": top end, "b": bottom end, "yaw", "w"}
var _cascades: Array[Dictionary] = []
var _tile_mats: Dictionary = {}


func _configure() -> void:
	theme_id = "lotus"
	music_track = "lotus"
	kill_y = -240.0
	# 0 = the safe line, 1 = the flow line
	route_variants = 1


# ---- path helpers --------------------------------------------------------------------------------

func _fwd(yaw: float) -> Vector3:
	var r: float = deg_to_rad(yaw)
	return Vector3(-sin(r), 0.0, -cos(r))


func _right(yaw: float) -> Vector3:
	var r: float = deg_to_rad(yaw)
	return Vector3(cos(r), 0.0, -sin(r))


## The validator's max reach (m) for a plain running jump that lands `dy` higher (test_m's measure).
func _reach(dy: float) -> float:
	var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, _tuning.jump_velocity, -_tuning.max_speed), dy)
	return absf(land.z)


func _tile_mat(kind: int, half: Vector3, round_: bool) -> ShaderMaterial:
	var key: String = "%d|%.2f|%.2f|%.2f|%s" % [kind, half.x, half.y, half.z, str(round_)]
	if _tile_mats.has(key):
		return _tile_mats[key]
	var m := ShaderMaterial.new()
	m.shader = TILE_SHADER
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("is_round", round_)
	m.set_shader_parameter("top_color", Look.c("alt_top") if kind == 3 else Look.c("top"))
	m.set_shader_parameter("side_color", Look.c("side"))
	m.set_shader_parameter("trim_color", Look.c("trim"))
	m.set_shader_parameter("trim_glow", 0.5)
	_tile_mats[key] = m
	return m


## Swap a kit platform's material for the lotus tile (kind 0 flagstone, 1 pad, 2 deck, 3 isle).
func _restyle(body: Node, kind: int) -> void:
	for ch: Node in body.get_children():
		if ch is MeshInstance3D:
			var old: ShaderMaterial = (ch as MeshInstance3D).material_override as ShaderMaterial
			if old != null and old.shader == Look.PLATFORM_SHADER:
				var half: Vector3 = old.get_shader_parameter("half_size")
				(ch as MeshInstance3D).material_override = _tile_mat(kind, half, bool(old.get_shader_parameter("is_round")))


func _note_floor(top: Vector3, size: Vector3, yaw: float, kind: int = -1) -> void:
	_floors.append({"top": top, "r": maxf(size.x, size.z) * 0.5, "yaw": yaw, "size": size, "kind": kind})


## A straight slab from the cursor along the heading: `len` long, `w` wide, flush with the last.
func _slab(len: float, w: float = 3.6, kind: int = 0, thick: float = 0.8) -> void:
	var f: Vector3 = _fwd(_yaw)
	var start: Vector3 = _pos + f * _edge_r
	var c: Vector3 = start + f * (len * 0.5)
	var size := Vector3(w, thick, len)
	var body: StaticBody3D = kit.plat(c, size, "main", 0.0, _yaw)
	_restyle(body, kind)
	_note_floor(c, size, _yaw, kind)
	var end: Vector3 = start + f * len
	if _have_jump:
		_go(start + f * minf(1.2, len * 0.5))
	r_walk(end - f * 0.2)
	_tier_note(end)
	_pos = end
	_edge_r = 0.0
	_flush = true


## Walk `len` of stone path.
func _walk(len: float, w: float = 3.6) -> void:
	_slab(len, w, 0)


## Walk `len` of wooden deck (a boardwalk).
func _deck(len: float, w: float = 3.0) -> void:
	var f: Vector3 = _fwd(_yaw)
	_slab(len, w, 2, 0.5)
	_deck_dress(_pos - f * len, _pos, w)


## A square corner slab, then turn `deg` (positive = left). `kind`/`w` as the path it joins.
func _turn(deg: float, w: float = 3.6, kind: int = 0) -> void:
	var f: Vector3 = _fwd(_yaw)
	var start: Vector3 = _pos + f * _edge_r
	var c: Vector3 = start + f * (w * 0.5)
	var size := Vector3(w, 0.8 if kind != 2 else 0.5, w)
	var body: StaticBody3D = kit.plat(c, size, "main", 0.0, _yaw)
	_restyle(body, kind)
	_note_floor(c, size, _yaw)
	if _have_jump:
		_go(c)
	else:
		r_walk(c)
	_tier_note(c)
	_yaw += deg
	_pos = c + _fwd(_yaw) * (w * 0.5)
	_edge_r = 0.0
	_flush = true


## Open a gap of `pct` of the max jump reach (test_m's measure) and remember the takeoff spot.
func _gap(pct: float, dy: float = 0.0) -> float:
	var f: Vector3 = _fwd(_yaw)
	var g: float = maxf(pct * _reach(dy) - 0.75, 0.5)
	_jump_from = _pos + f * (_edge_r - 0.35)
	_have_jump = true
	_pos = _pos + f * (_edge_r + g)
	_edge_r = 0.0
	_flush = false
	return g


## Walk or jump (if a gap is open) to `p`.
func _go(p: Vector3) -> void:
	if _have_jump:
		r_jump(_jump_from, p, true)
		_have_jump = false
	else:
		r_walk(p)


func _tier_note(p: Vector3) -> void:
	if not _tiers.is_empty():
		(_tiers[_tiers.size() - 1]["pts"] as PackedVector3Array).append(p)


## A line of `n` lily pads: gap `pct` of reach, radius `r`, heading swung `curve` degrees before each
## hop (alternating sign when `s_bend`).
func _pads(n: int, pct: float, r: float = 1.3, curve: float = 0.0, s_bend: bool = true) -> void:
	var base: float = _yaw
	for i: int in n:
		var sgn: float = 1.0
		if s_bend:
			sgn = 1.0 if (i / 2) % 2 == 0 else -1.0
		_yaw = base + curve * sgn
		_gap(pct)
		var f: Vector3 = _fwd(_yaw)
		var c: Vector3 = _pos + f * r
		var pad := LotusPad.new()
		pad.radius = r
		pad.position = c
		add_child(pad)
		_note_floor(c, Vector3(r * 2.0, 0.5, r * 2.0), _yaw, 1)
		_go(c)
		_tier_note(c)
		_pos = c
		_edge_r = r
		_flush = false
	_yaw = base


## A line of `n` square stepping stones, zig-zagging `zig` degrees either side of the heading.
func _stones(n: int, pct: float, size: float = 2.0, zig: float = 22.0) -> void:
	var base: float = _yaw
	for i: int in n:
		_yaw = base + (zig if i % 2 == 0 else -zig)
		_gap(pct)
		var f: Vector3 = _fwd(_yaw)
		var c: Vector3 = _pos + f * (size * 0.5)
		var sz := Vector3(size, 0.8, size)
		var body: StaticBody3D = kit.plat(c, sz, "main", 0.0, _yaw)
		_restyle(body, 0)
		_note_floor(c, sz, _yaw)
		_go(c)
		_tier_note(c)
		_pos = c
		_edge_r = size * 0.5
		_flush = false
	_yaw = base


## A hop to a slab and a walk on it: `len` long.
func _land(pct: float, len: float, w: float = 3.6, kind: int = 0) -> void:
	_gap(pct)
	_slab(len, w, kind, 0.8 if kind != 2 else 0.5)


## A moon bridge: a ramp up `rise`, a short flat top, a ramp down (all deck).
func _moon_bridge(run: float = 9.0, top: float = 4.0, rise: float = 1.7, w: float = 3.2) -> void:
	var f: Vector3 = _fwd(_yaw)
	var a: Vector3 = _pos + f * _edge_r
	var up_end: Vector3 = a + f * run + Vector3(0, rise, 0)
	var flat_end: Vector3 = up_end + f * top
	var down_end: Vector3 = flat_end + f * run - Vector3(0, rise, 0)
	_ramp_between(a, up_end, w, 2)
	var c: Vector3 = (up_end + flat_end) * 0.5
	var size := Vector3(w, 0.5, top)
	var body: StaticBody3D = kit.plat(c, size, "main", 0.0, _yaw)
	_restyle(body, 2)
	_note_floor(c, size, _yaw)
	_ramp_between(flat_end, down_end, w, 2)
	r_walk(up_end)
	r_walk(flat_end)
	r_walk(down_end)
	_tier_note(a)
	_tier_note(down_end)
	_deck_dress(a, up_end, w)
	_deck_dress(up_end, flat_end, w)
	_deck_dress(flat_end, down_end, w)
	_arch_dress(up_end, flat_end, rise)
	_pos = down_end
	_edge_r = 0.0
	_flush = true


## A sloped slab from `a` to `b` (top-surface end midpoints), `w` wide.
func _ramp_between(a: Vector3, b: Vector3, w: float, kind: int = 0) -> StaticBody3D:
	var d: Vector3 = b - a
	var run: float = Vector2(d.x, d.z).length()
	var len: float = d.length()
	var pitch: float = rad_to_deg(atan2(d.y, run))
	var c: Vector3 = (a + b) * 0.5
	var size := Vector3(w, 0.6, len)
	var body: StaticBody3D = kit.ramp(c, size, pitch, _yaw, "main")
	_restyle(body, kind)
	_note_floor(c, Vector3(w, 0.6, run), _yaw)
	return body


## A cascade: the walkway runs down a weir `drop` m, a 12-degree ramp. Opens a new tier at its foot.
func _cascade(drop: float, w: float = 3.6) -> void:
	var f: Vector3 = _fwd(_yaw)
	var run: float = drop / tan(deg_to_rad(CASCADE_DEG))
	var a: Vector3 = _pos + f * _edge_r
	var b: Vector3 = a + f * run - Vector3(0, drop, 0)
	_ramp_between(a, b, w, 0)
	_cascades.append({"a": a, "b": b, "yaw": _yaw, "w": w})
	r_walk(a + f * 0.6)
	r_walk(b)
	# the next tier begins at the foot
	_pos = b
	_edge_r = 0.0
	_flush = true
	_tier_open(b.y)
	_tier_note(b)


func _tier_open(y: float) -> void:
	_tiers.append({"y": y, "pts": PackedVector3Array()})


## A round isle (a checkpoint): `radius`, the path leaving it at `next_yaw`.
func _isle(radius: float, next_yaw: float, with_cp: bool = true, shrine: bool = true) -> Vector3:
	var f: Vector3 = _fwd(_yaw)
	var lead: float = (radius - 0.6) if _flush else radius
	var c: Vector3 = _pos + f * (_edge_r + lead)
	c.y += HUB_RISE
	var body: StaticBody3D = kit.disc(c, radius, 0.8, "main", 0.0)
	_restyle(body, 3)
	_note_floor(c, Vector3(radius * 2.0, 0.8, radius * 2.0), _yaw)
	if _have_jump:
		r_jump(_jump_from, c - f * (radius * 0.45), true)
		_have_jump = false
		r_walk(c)
	else:
		r_walk(c)
	_tier_note(c)
	var cp: Checkpoint = null
	if with_cp:
		cp = kit.checkpoint(c, next_yaw)
		_cp_world.append(c)
		_cp_nodes.append(cp)
		r_checkpoint()
	_isles.append({"c": c, "r": radius, "yaw_in": _yaw, "yaw_out": next_yaw, "cp": with_cp, "node": cp})
	_yaw = next_yaw
	_pos = c + _fwd(_yaw) * (radius - 0.6) - Vector3(0, HUB_RISE, 0)
	_edge_r = 0.0
	_flush = true
	return c


# ---- the course -----------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	LotusDecor.reset()
	deco = LotusDecor.new(self, kit.rng)
	add_child(Ambience.make(theme_id))
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 0), 0.0)
	_build_course()
	_dress()


func _build_course() -> void:
	# the start isle (no checkpoint), the first tier opens at the gate
	_pos = Vector3(0, -HUB_RISE, 0)
	_yaw = 0.0
	_tier_open(0.0)
	var start := kit.disc(Vector3(0, 0, 0), 6.5, 0.8, "main", 0.0)
	_restyle(start, 3)
	_note_floor(Vector3(0, 0, 0), Vector3(13, 0.8, 13), 0.0)
	_tier_note(Vector3(0, 0, 0))
	_pos = _fwd(_yaw) * (6.5 - 0.6) - Vector3(0, HUB_RISE, 0)
	_edge_r = 0.0
	_flush = true
	_stage_1()
	_stage_2()
	_stage_3()
	_stage_4()
	_stage_5()
	_stage_6()
	_stage_7()
	_stage_8()
	_stage_9()
	_stage_10()


## Stage 1 - Moon Gate: a stone path, then a zig-zag boardwalk over the lilies.
func _stage_1() -> void:
	_walk(26.0)
	_turn(90.0)
	_deck(10.0)
	_turn(-90.0, 3.0, 2)
	_deck(12.0)
	_turn(-90.0, 3.0, 2)
	_deck(10.0)
	_turn(90.0, 3.0, 2)
	_walk(14.0)
	_isle(5.2, _yaw + 30.0)
	_cascade(5.4)


func _stage_2() -> void:
	_walk(8.0)
	_pads(7, 0.62, 1.3, 14.0)
	_land(0.66, 10.0)
	_pads(4, 0.7, 1.3, 12.0)
	_gap(0.6)
	_isle(5.2, _yaw + 30.0)
	_cascade(5.6)


func _stage_3() -> void:
	_walk(30.0)
	_moon_bridge()
	_walk(10.0)
	_isle(4.6, _yaw, false)
	_pads(3, 0.66, 1.4, 10.0)
	_gap(0.6)
	_isle(5.2, _yaw + 30.0)
	_cascade(5.8)


func _stage_4() -> void:
	_deck(14.0)
	_turn(-90.0, 3.0, 2)
	_deck(10.0)
	_turn(90.0, 3.0, 2)
	_deck(8.0)
	_pads(6, 0.68, 1.3, 14.0)
	_land(0.62, 22.0, 3.0, 2)
	_isle(5.2, _yaw + 30.0)
	_cascade(6.0)


func _stage_5() -> void:
	_walk(6.0)
	_stones(8, 0.68, 2.0, 24.0)
	_land(0.62, 14.0)
	_pads(4, 0.7, 1.3, 14.0)
	_gap(0.6)
	_isle(5.2, _yaw + 30.0)
	_cascade(6.2)


func _stage_6() -> void:
	_deck(38.0, 3.2)
	_moon_bridge(9.0, 3.0, 1.9)
	_walk(8.0)
	_isle(4.6, _yaw, false)
	_pads(5, 0.7, 1.3, 12.0)
	_gap(0.6)
	_isle(5.2, _yaw + 30.0)
	_cascade(6.4)


func _stage_7() -> void:
	_deck(10.0)
	_turn(90.0, 3.0, 2)
	_deck(12.0)
	_turn(-90.0, 3.0, 2)
	_deck(10.0)
	_pads(8, 0.72, 1.25, 12.0)
	_land(0.66, 16.0, 2.6, 2)
	_isle(5.2, _yaw + 30.0)
	_cascade(6.6)


func _stage_8() -> void:
	_walk(20.0)
	_pads(4, 0.7, 1.3, 14.0)
	_land(0.64, 8.0)
	_isle(4.8, _yaw, false)
	_walk(18.0)
	_pads(3, 0.72, 1.3, 10.0)
	_gap(0.6)
	_isle(5.2, _yaw + 30.0)
	_cascade(6.8)


func _stage_9() -> void:
	_walk(8.0)
	_pads(10, 0.74, 1.25, 10.0)
	_land(0.66, 12.0)
	_gap(0.6)
	_isle(5.2, _yaw + 30.0)
	_cascade(7.0)


## Stage 10 - The Great Lotus: a long serene procession of pads and causeway to the giant lotus.
func _stage_10() -> void:
	_walk(14.0)
	_pads(6, 0.7, 1.4, 10.0)
	_land(0.62, 16.0)
	_pads(4, 0.7, 1.4, 10.0)
	_gap(0.6)
	# the great lotus: a wide round dais with the finish gate
	var f: Vector3 = _fwd(_yaw)
	var c: Vector3 = _pos + f * (_edge_r + 7.0)
	c.y += HUB_RISE
	var body: StaticBody3D = kit.disc(c, 7.0, 0.8, "main", 0.0)
	_restyle(body, 3)
	_note_floor(c, Vector3(14, 0.8, 14), _yaw)
	r_jump(_jump_from, c - f * 3.0, true)
	_have_jump = false
	_tier_note(c)
	var fin: Vector3 = c + f * 1.5
	kit.finish(fin, _yaw)
	_finish_pos = fin
	r_walk(fin + f * 0.2)




# ---- environment --------------------------------------------------------------------------------

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
	_env.sky = LotusSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.56, 0.5, 0.78)
	_env.ambient_light_energy = 0.66
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.66, 0.46, 0.56)
	_env.fog_density = 0.0036
	_env.fog_aerial_perspective = 0.55
	_env.fog_sky_affect = 0.1
	_env.fog_sun_scatter = 0.35
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.1
	_env.glow_hdr_threshold = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.06
	# a low, warm key light from the glowing horizon, and a cool violet fill from the dark side
	_sun.light_color = Color(1.0, 0.72, 0.54)
	_sun.light_energy = 1.05
	_sun.rotation_degrees = Vector3(-17, 160, 0)
	_fill.light_color = Color(0.5, 0.5, 0.95)
	_fill.light_energy = 0.34
	_fill.rotation_degrees = Vector3(-30, -20, 0)


# ---- dressing -------------------------------------------------------------------------------------

## Width either side of a tier's path that is pond.
const POND_M: float = 13.0

var _spiral_center: Vector3 = Vector3.ZERO
var _isles: Array[Dictionary] = []


func _dress() -> void:
	_isles_from_cps()
	_build_water()
	_dress_cascades()
	_dress_path()
	_dress_isles()
	_dress_start_and_finish()
	_dress_banks()
	_dress_life()
	_dress_far()
	_kill_nets()


func _isles_from_cps() -> void:
	var sum := Vector3.ZERO
	for p: Vector3 in _cp_world:
		sum += p
	_spiral_center = sum / maxf(float(_cp_world.size()), 1.0)


## A stone deck rail (railing posts, lanterns) along a boardwalk segment.
func _deck_dress(a: Vector3, b: Vector3, w: float) -> void:
	deco.bridge_rails(a, b, w * 0.5 - 0.05, true)


## The ring of the moon bridge under the flat top (two stone rings, one each side of the deck).
func _arch_dress(a: Vector3, b: Vector3, rise: float) -> void:
	var mid: Vector3 = (a + b) * 0.5
	var r: float = rise + 0.5 + 0.6
	var n := Node3D.new()
	n.position = Vector3(mid.x, mid.y - 0.5 - r + 0.12, mid.z)
	n.rotation.y = deg_to_rad(_yaw)
	add_child(n)
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.2
	tm.outer_radius = r
	tm.rings = 36
	tm.ring_segments = 8
	var stone := Look.flat(Color(0.52, 0.5, 0.56), 0.9)
	for sx: float in [-1.0, 1.0]:
		var ring := Look.mesh_node(tm, stone, Vector3(sx * 1.45, 0, 0))
		ring.rotation.z = PI * 0.5
		n.add_child(ring)
	# a dark band of stone under the deck between the rings
	n.add_child(Look.box(Vector3(3.0, 0.3, 4.6), Look.flat(Color(0.34, 0.33, 0.4), 0.9), Vector3(0, r - 0.12, 0)))


# ---- the water ----------------------------------------------------------------------------------

func _patch(c: Vector3, yaw: float, lat: float, half_len: float, y: float, skirt: float) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(lat * 2.0, half_len * 2.0)
	var mi := Look.mesh_node(pm, LotusDecor.water_material(), Vector3(c.x, y, c.z))
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if skirt > 0.0:
		var sk := Look.box(Vector3(lat * 2.0 - 0.4, skirt, half_len * 2.0 - 0.4), Look.flat(Color(0.12, 0.13, 0.17), 0.95), Vector3(c.x, y - 0.15 - skirt * 0.5, c.z))
		sk.rotation.y = yaw
		sk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sk)


func _build_water() -> void:
	var lowest: float = INF
	for ti: int in _tiers.size():
		var t: Dictionary = _tiers[ti]
		var pts: PackedVector3Array = t["pts"]
		var y: float = float(t["y"]) - WATER_DROP
		var next_y: float = (float(_tiers[ti + 1]["y"]) - WATER_DROP) if ti + 1 < _tiers.size() else y - 24.0
		var skirt: float = y - next_y + 3.0
		lowest = minf(lowest, y)
		if pts.size() < 2:
			continue
		for i: int in range(pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
			var len: float = d.length()
			if len < 0.6:
				continue
			var yaw: float = atan2(-d.x, -d.z)
			_patch((a + b) * 0.5, yaw, POND_M, len * 0.5, y, skirt)
			if i > 0:
				_patch(a, 0.0, POND_M, POND_M, y, skirt)
		# the first tier also reaches back behind the start isle
		if ti == 0:
			_patch(pts[0] + Vector3(0, 0, 4.0), 0.0, POND_M + 4.0, POND_M + 6.0, y, skirt)
		# and the last one all round the great lotus
		if ti == _tiers.size() - 1:
			_patch(pts[pts.size() - 1], 0.0, POND_M + 6.0, POND_M + 8.0, y, skirt)
	# the lake: one great sheet far below everything, reaching the horizon
	var lake := PlaneMesh.new()
	lake.size = Vector2(4000, 4000)
	var lm := Look.mesh_node(lake, LotusDecor.water_material(), Vector3(_spiral_center.x, lowest - 3.5, _spiral_center.z))
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lm)


## Catch nets: invisible kill boxes just under each pond's water, wherever the pond surface is.
func _kill_nets() -> void:
	for ti: int in _tiers.size():
		var t: Dictionary = _tiers[ti]
		var pts: PackedVector3Array = t["pts"]
		var y: float = float(t["y"]) - 0.55
		for i: int in range(pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
			var len: float = d.length()
			if len < 0.6:
				continue
			var k := KillZone.new()
			k.size = Vector3(POND_M * 2.0 - 1.0, 0.8, len)
			k.show_mesh = false
			k.rotation.y = atan2(-d.x, -d.z)
			k.position = Vector3((a.x + b.x) * 0.5, y - 0.4, (a.z + b.z) * 0.5)
			add_child(k)
			if i > 0:
				var k2 := KillZone.new()
				k2.size = Vector3(POND_M * 2.0 - 1.0, 0.8, POND_M * 2.0 - 1.0)
				k2.show_mesh = false
				k2.position = Vector3(a.x, y - 0.4, a.z)
				add_child(k2)


# ---- cascades: weirs, waterfalls, the ramp's stone bank ------------------------------------------------

func _dress_cascades() -> void:
	var stone := Look.flat(Color(0.42, 0.42, 0.5), 0.95)
	var cap := Look.flat(Color(0.6, 0.58, 0.62), 0.85)
	for c: Dictionary in _cascades:
		var a: Vector3 = c["a"]
		var b: Vector3 = c["b"]
		var yaw: float = float(c["yaw"])
		var w: float = float(c["w"])
		var f: Vector3 = _fwd(yaw)
		var r: Vector3 = _right(yaw)
		var y_u: float = a.y - WATER_DROP
		var y_l: float = b.y - WATER_DROP
		var gap_half: float = w * 0.5 + 0.9
		var outer: float = POND_M
		var wall_len: float = (outer - gap_half)
		var wall_h: float = (y_u + 0.3) - (y_l - 1.2)
		for sgn: float in [-1.0, 1.0]:
			var lat: float = sgn * (gap_half + wall_len * 0.5)
			var wc: Vector3 = a + f * 1.6 + r * lat
			var wall := Look.box(Vector3(wall_len, wall_h, 3.2), stone, Vector3(wc.x, (y_u + 0.3 + y_l - 1.2) * 0.5, wc.z))
			wall.rotation.y = deg_to_rad(yaw)
			add_child(wall)
			var topc := Look.box(Vector3(wall_len + 0.2, 0.22, 3.6), cap, Vector3(wc.x, y_u + 0.3 - 0.0, wc.z))
			topc.rotation.y = deg_to_rad(yaw)
			add_child(topc)
			# a waterfall curtain on the front face, off to each side of the walkway
			var off: float = sgn * (gap_half + 3.4)
			var fall_top: Vector3 = a + f * 3.15 + r * off
			deco.waterfall(Vector3(fall_top.x, y_u + 0.1, fall_top.z), 3.6, y_u - y_l + 0.2, yaw + 180.0)
			LotusFx.spray(self, Vector3(fall_top.x, y_l + 0.25, fall_top.z) + f * 0.8, Vector3(1.8, 0.2, 0.7), 26)
		# the stepped stone bank under the ramp, and a low parapet along both sides
		var run: float = Vector2(b.x - a.x, b.z - a.z).length()
		var n_steps: int = maxi(int(run / 1.8), 2)
		var dx: float = run / float(n_steps)
		for i: int in n_steps:
			var s0: float = float(i) * dx
			var surf_far_y: float = a.y - (float(i + 1) * dx) * tan(deg_to_rad(CASCADE_DEG))
			var top_y: float = surf_far_y - 0.62
			var bot_y: float = y_l - 1.2
			if top_y <= bot_y + 0.2:
				continue
			var ctr: Vector3 = a + f * (s0 + dx * 0.5)
			var blk := Look.box(Vector3(w + 0.5, top_y - bot_y, dx), stone, Vector3(ctr.x, (top_y + bot_y) * 0.5, ctr.z))
			blk.rotation.y = deg_to_rad(yaw)
			add_child(blk)
		for sgn2: float in [-1.0, 1.0]:
			var side: Vector3 = r * sgn2 * (w * 0.5 + 0.2)
			deco.rod(a + side + Vector3(0, 0.3, 0), b + side + Vector3(0, 0.3, 0), 0.17, cap, null, 6)
			deco.stone_lantern(a + side * 1.5 + f * 0.8 + Vector3(0, 0.0, 0), 1.0, true)
			deco.stone_lantern(b + side * 1.5 - f * 0.6, 1.0, true)


# ---- the path: lanterns, chimes, flowers --------------------------------------------------------------

func _dress_path() -> void:
	var rng: RandomNumberGenerator = kit.rng
	var chime_i: int = 0
	for fl: Dictionary in _floors:
		var kind: int = int(fl.get("kind", -1))
		var size: Vector3 = fl["size"]
		var top: Vector3 = fl["top"]
		var yaw: float = float(fl["yaw"])
		var f: Vector3 = _fwd(yaw)
		var r: Vector3 = _right(yaw)
		if kind == 0 and size.z >= 9.0 and size.x < 5.0:
			# a stone lantern in the water beside every ~11 m of path, alternating sides
			var count: int = int(size.z / 11.0)
			for i: int in count:
				var along: float = (-0.5 + (float(i) + 0.5) / float(maxi(count, 1))) * size.z
				var sgn: float = 1.0 if (i + int(top.x)) % 2 == 0 else -1.0
				var p: Vector3 = top + f * along + r * sgn * (size.x * 0.5 + 0.9)
				deco.stone_lantern(Vector3(p.x, top.y - 0.15, p.z), 1.0, true)
				deco.slab(Vector3(p.x, top.y - 0.9, p.z), Vector3(0.9, 1.5, 0.9), Look.flat(Color(0.34, 0.34, 0.4), 0.95))
			if size.z >= 20.0 and chime_i < 40:
				_chime(top + r * (size.x * 0.5 + 0.7) + f * size.z * 0.15, chime_i)
				chime_i += 1
		elif kind == 2 and size.z >= 12.0 and chime_i < 40:
			_chime(top + r * (size.x * 0.5 + 0.5) - f * size.z * 0.2, chime_i)
			chime_i += 1
		elif kind == 1:
			# some pads carry a lotus flower at their edge
			if rng.randf() < 0.28:
				var side_dir: Vector3 = r * (1.0 if rng.randf() < 0.5 else -1.0)
				var rr: float = float(fl["r"])
				deco.lotus_flower(Vector3(top.x, top.y - 0.35, top.z) + side_dir * (rr + 0.9), rng.randf_range(0.8, 1.3), 1.0 if rng.randf() < 0.8 else 0.0, 0.7)


## A chime on a post: a short post with an arm, the LotusChime hanging from its end.
func _chime(pos: Vector3, idx: int) -> void:
	var wood := Look.flat(Color(0.26, 0.16, 0.12), 0.8)
	var h: float = 3.2
	var post := Look.cylinder(0.09, h + 1.0, wood, Vector3(pos.x, pos.y + (h - 1.0) * 0.5, pos.z), 0.07, 6)
	add_child(post)
	var arm_end := Vector3(pos.x + 0.9, pos.y + h, pos.z)
	deco.rod(Vector3(pos.x, pos.y + h, pos.z), arm_end, 0.05, wood, null, 5)
	var ch := LotusChime.new()
	ch.note = idx % 5
	ch.height = 1.5
	ch.position = arm_end
	add_child(ch)


# ---- isles: lotus, lanterns, rocks, a tree ------------------------------------------------------------

func _dress_isles() -> void:
	var rng: RandomNumberGenerator = kit.rng
	for i: int in _isles.size():
		var d: Dictionary = _isles[i]
		var c: Vector3 = d["c"]
		var rad: float = float(d["r"])
		var yin: float = float(d["yaw_in"])
		var yout: float = float(d["yaw_out"])
		var fin: Vector3 = _fwd(yin)
		var rin: Vector3 = _right(yin)
		var fout: Vector3 = _fwd(yout)
		var is_cp: bool = bool(d["cp"])
		if is_cp:
			# the lotus bud in its basin on the left-hand rim, a pair of toro at the entrance
			var bloom := LotusBloom.new()
			bloom.scale_k = 2.2
			var bp: Vector3 = c + (-fin * 0.45 - rin * 0.9).normalized() * (rad - 1.3)
			bloom.position = Vector3(bp.x, c.y, bp.z)
			add_child(bloom)
			bloom.bind(d["node"], self)
			for sgn: float in [-1.0, 1.0]:
				var lp: Vector3 = c - fin * (rad - 0.9) + rin * sgn * 2.4
				deco.stone_lantern(Vector3(lp.x, c.y, lp.z), 1.1, true)
		# rocks and reeds at the water's edge, away from the entrance and exit
		for k: int in 5:
			var ang: float = rng.randf() * TAU
			var dir := Vector3(cos(ang), 0, sin(ang))
			if dir.dot(fin) < -0.6 or dir.dot(fout) > 0.6:
				continue
			var p: Vector3 = c + dir * (rad + rng.randf_range(0.2, 1.2))
			deco.rock(Vector3(p.x, c.y - 0.5, p.z), rng.randf_range(0.7, 1.4))
			deco.reeds(Vector3(p.x, c.y - 0.5, p.z) + dir * 0.9, 7, 0.9, 2.0)
		# a tree on the isle's far side
		var back: Vector3 = c - fout * (rad * 0.55) + (rin * (1.0 if i % 2 == 0 else -1.0)) * (rad * 0.4)
		match i % 3:
			0: deco.maple(Vector3(back.x, c.y, back.z), 1.2)
			1: deco.pine(Vector3(back.x, c.y, back.z), 1.1)
			2: deco.willow(Vector3(back.x, c.y, back.z), 1.0)


func _dress_start_and_finish() -> void:
	# the moon gate across the first stone path
	deco.moon_gate(Vector3(0, 0, -11.5), 3.7, 0.0, 8.0)
	deco.lantern_string(Vector3(-6.5, 5.8, -3.0), Vector3(6.5, 5.9, -3.0), 9, 1.1)
	# the great lotus round the finish dais
	var f: Vector3 = _fwd(_yaw)
	var c: Vector3 = _finish_pos - f * 1.5
	var big := MeshInstance3D.new()
	big.mesh = LotusDecor.flower_mesh(1.0)
	big.scale = Vector3.ONE * 15.0
	big.position = Vector3(c.x, c.y - 1.0, c.z)
	big.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(big)
	# lanterns round the dais rim
	for i: int in 10:
		var a: float = TAU * float(i) / 10.0
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * 6.4
		if Vector3(cos(a), 0, sin(a)).dot(f) < -0.8:
			continue
		deco.stone_lantern(Vector3(p.x, c.y, p.z), 1.15, true)


# ---- banks, trees, far scenery ----------------------------------------------------------------------

## Clear of the walkable path by more than `dist` in plan.
func _clear_of_path(p: Vector3, dist: float) -> bool:
	for fl: Dictionary in _floors:
		var t: Vector3 = fl["top"]
		if Vector2(p.x - t.x, p.z - t.z).length() < dist + float(fl["r"]):
			return false
	return true


func _dress_banks() -> void:
	var rng: RandomNumberGenerator = kit.rng
	for ti: int in _tiers.size():
		var t: Dictionary = _tiers[ti]
		var pts: PackedVector3Array = t["pts"]
		var y: float = float(t["y"]) - WATER_DROP
		var last_pt := Vector3.INF
		for i: int in range(pts.size()):
			var p: Vector3 = pts[i]
			if last_pt != Vector3.INF and Vector2(p.x - last_pt.x, p.z - last_pt.z).length() < 16.0:
				continue
			last_pt = p
			var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
			var d := Vector3(nxt.x - p.x, 0, nxt.z - p.z)
			if d.length() < 0.5:
				d = Vector3(p.x - pts[maxi(i - 1, 0)].x, 0, p.z - pts[maxi(i - 1, 0)].z)
			if d.length() < 0.5:
				continue
			d = d.normalized()
			var side := Vector3(-d.z, 0, d.x)
			for sgn: float in [-1.0, 1.0]:
				var bp: Vector3 = p + side * sgn * (POND_M - 1.0 + rng.randf_range(-1.5, 1.5)) + d * rng.randf_range(-4.0, 4.0)
				if not _clear_of_path(bp, 7.0):
					continue
				var rad: float = rng.randf_range(4.0, 7.5)
				deco.mound(Vector3(bp.x, y - 0.3, bp.z), rad, rng.randf_range(2.0, 3.6), rad * rng.randf_range(0.8, 1.2))
				var top := Vector3(bp.x, y + 2.0, bp.z)
				match rng.randi_range(0, 4):
					0: deco.willow(top, rng.randf_range(1.0, 1.5))
					1: deco.maple(top, rng.randf_range(1.2, 1.9))
					2: deco.pine(top, rng.randf_range(1.2, 1.7))
					3: deco.bamboo(top, 9, 7.0, 1.6)
					4:
						deco.maple(top, 1.4)
						deco.stone_lantern(top + side * sgn * -2.5, 1.2, true)


func _dress_far() -> void:
	var rng: RandomNumberGenerator = kit.rng
	var lowest: float = INF
	for t: Dictionary in _tiers:
		lowest = minf(lowest, float(t["y"]))
	# the central isle in the lake: the tall pagoda
	var cc := Vector3(_spiral_center.x, lowest - 4.0, _spiral_center.z)
	deco.mound(cc, 34.0, 14.0, 34.0, Color(0.14, 0.3, 0.2))
	deco.pagoda(cc + Vector3(0, 12.0, 0), 7, 2.0, 0.4, true)
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + 0.3
		deco.pine(cc + Vector3(cos(a) * 22.0, 11.0, sin(a) * 22.0), 2.2)
	# a ring of dark wooded hills round the whole garden, each with a lit pagoda or a torii
	for i: int in 16:
		var a2: float = TAU * (float(i) + rng.randf() * 0.5) / 16.0
		var rr: float = rng.randf_range(420.0, 640.0)
		var base := Vector3(_spiral_center.x + cos(a2) * rr, lowest - 6.0 + rng.randf_range(-4.0, 8.0), _spiral_center.z + sin(a2) * rr)
		var hr: float = rng.randf_range(60.0, 120.0)
		deco.mound(base, hr, rng.randf_range(40.0, 90.0), hr * rng.randf_range(0.7, 1.2), Color(0.1, 0.22, 0.2))
		if i % 2 == 0:
			deco.pagoda(base + Vector3(0, rng.randf_range(30.0, 50.0), 0), rng.randi_range(3, 5), rng.randf_range(2.5, 4.0), rng.randf() * TAU, true)


# ---- life: koi, fireflies, mist, lanterns --------------------------------------------------------------

func _dress_life() -> void:
	var rng: RandomNumberGenerator = kit.rng
	for ti: int in _tiers.size():
		var t: Dictionary = _tiers[ti]
		var pts: PackedVector3Array = t["pts"]
		if pts.size() < 2:
			continue
		var y: float = float(t["y"]) - WATER_DROP
		var mid: Vector3 = pts[pts.size() / 2]
		# koi round the middle of the tier, and a drift of fireflies, mist and petals above it
		var koi := LotusKoi.new()
		koi.count = 4 + ti % 3
		koi.extent = Vector2(9.0, 5.0)
		koi.position = Vector3(mid.x, y, mid.z)
		koi.rotation.y = rng.randf() * TAU
		add_child(koi)
		for k: int in 5:
			var p: Vector3 = pts[rng.randi_range(0, pts.size() - 1)]
			var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			var cp: Vector3 = Vector3(p.x, y, p.z) + dir * rng.randf_range(5.0, 11.0)
			if _clear_of_path(cp, 3.0):
				deco.lily_cluster(cp, rng.randi_range(4, 7), 2.2, rng.randi_range(0, 2))
		LotusFx.fireflies(self, Vector3(mid.x, y + 1.6, mid.z), Vector3(26.0, 1.6, 26.0), 40)
		LotusFx.mist(self, Vector3(mid.x, y + 0.9, mid.z), Vector3(30.0, 0.5, 30.0), 10)
		LotusFx.petals(self, Vector3(mid.x, y + 4.0, mid.z), Vector3(28.0, 3.0, 28.0), 14)
	# sky lanterns lifting off at the start and round the great lotus
	LotusFx.sky_lanterns(self, Vector3(0, 6, -8), Vector3(18, 2, 18), 10)
	LotusFx.sky_lanterns(self, _finish_pos + Vector3(0, 4, 0), Vector3(22, 2, 22), 24)
