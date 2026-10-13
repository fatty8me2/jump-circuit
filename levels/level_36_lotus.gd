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


func _note_floor(top: Vector3, size: Vector3, yaw: float) -> void:
	_floors.append({"top": top, "r": maxf(size.x, size.z) * 0.5, "yaw": yaw, "size": size})


## A straight slab from the cursor along the heading: `len` long, `w` wide, flush with the last.
func _slab(len: float, w: float = 3.6, kind: int = 0, thick: float = 0.8) -> void:
	var f: Vector3 = _fwd(_yaw)
	var start: Vector3 = _pos + f * _edge_r
	var c: Vector3 = start + f * (len * 0.5)
	var size := Vector3(w, thick, len)
	var body: StaticBody3D = kit.plat(c, size, "main", 0.0, _yaw)
	_restyle(body, kind)
	_note_floor(c, size, _yaw)
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
		_note_floor(c, Vector3(r * 2.0, 0.5, r * 2.0), _yaw)
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
	if with_cp:
		var cp: Checkpoint = kit.checkpoint(c, next_yaw)
		_cp_world.append(c)
		_cp_nodes.append(cp)
		r_checkpoint()
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


# ---- dressing (filled in below) -------------------------------------------------------------------

func _deck_dress(a: Vector3, b: Vector3, w: float) -> void:
	pass


func _arch_dress(a: Vector3, b: Vector3, rise: float) -> void:
	pass


func _dress() -> void:
	pass


func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_sun = n as DirectionalLight3D
			else:
				_fill = n as DirectionalLight3D
