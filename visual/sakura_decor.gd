class_name SakuraDecor
extends RefCounted
## Sakura Peaks set dressing, all built from primitives: cherry trees in full blossom, pagodas with
## tiered upturned roofs, torii gates, stone lanterns, paper lanterns on strings, bamboo clumps,
## village houses, temple bells, vermilion railings, distant mountain ridges and the castle keep's
## tiers. Nothing here collides unless it says so. Materials are cached (cleared per level load).

const VERMILION := Color(0.86, 0.2, 0.12)
const LACQUER := Color(0.12, 0.07, 0.06)
const DARK_WOOD := Color(0.26, 0.16, 0.11)
const WOOD := Color(0.52, 0.36, 0.23)
const PLASTER := Color(0.95, 0.92, 0.85)
const PAPER := Color(1.0, 0.94, 0.8)
const BLOSSOM := Color(1.0, 0.7, 0.8)
const BLOSSOM_PALE := Color(1.0, 0.86, 0.9)
const BLOSSOM_DEEP := Color(0.93, 0.46, 0.62)
const TILE := Color(0.2, 0.22, 0.28)
const STONE := Color(0.56, 0.54, 0.5)
const MOSS := Color(0.34, 0.42, 0.24)
const BAMBOO := Color(0.46, 0.62, 0.3)
const GOLD := Color(1.0, 0.76, 0.3)
const GLOW := Color(1.0, 0.6, 0.28)
const BRONZE := Color(0.42, 0.33, 0.2)

static var _mats: Dictionary = {}

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


## Drop the cached materials (the level calls this once as it starts building).
static func reset() -> void:
	_mats.clear()


func _add(n: Node3D, pos: Vector3, parent: Node3D = null) -> Node3D:
	n.position = pos
	(parent if parent != null else root).add_child(n)
	return n


static func _no_shadow(g: GeometryInstance3D) -> GeometryInstance3D:
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


# ---- materials ------------------------------------------------------------------------------

## Lacquer / wood / plaster: plain lit materials (cached by colour and finish).
static func mat(c: Color, rough: float = 0.7, metal: float = 0.0) -> StandardMaterial3D:
	return Look.flat(c, rough, metal)


## A warm glowing paper / flame material (bounded emission).
static func glow(c: Color = GLOW, energy: float = 2.2) -> StandardMaterial3D:
	return Look.flat(c, 0.6, 0.0, clampf(energy, 0.0, 4.0))


## Blossom: soft, slightly translucent-looking pink that catches the low sun (a touch of emission
## so the canopies read at dusk).
static func blossom(c: Color) -> StandardMaterial3D:
	var key: String = "bl|" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.28
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.4
	_mats[key] = m
	return m


## Two-sided paper (shoji panes, lantern skins): lit from behind by `energy`.
static func paper(energy: float = 0.6, c: Color = PAPER) -> StandardMaterial3D:
	var key: String = "pp|%s|%.2f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = energy > 0.0
	m.emission = Color(1.0, 0.78, 0.5)
	m.emission_energy_multiplier = clampf(energy, 0.0, 3.0)
	_mats[key] = m
	return m


## Still water (the koi pond, the mill race): dark glassy teal.
static func water(c: Color = Color(0.16, 0.34, 0.38, 0.82)) -> StandardMaterial3D:
	var key: String = "wa|" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.05
	m.metallic = 0.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


# ---- small helpers ---------------------------------------------------------------------------

## A box between two corners (world), with a material.
func slab(c: Vector3, size: Vector3, m: Material, yaw: float = 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := Look.box(size, m)
	mi.rotation.y = yaw
	_add(mi, c, parent)
	return mi


## A cylinder between two points (beams, ropes, bamboo).
func rod(a: Vector3, b: Vector3, r: float, m: Material, parent: Node3D = null, segs: int = 8) -> MeshInstance3D:
	var d: Vector3 = b - a
	var len: float = d.length()
	var mi := Look.cylinder(r, maxf(len, 0.01), m, Vector3.ZERO, -1.0, segs)
	if len > 0.0001:
		var up: Vector3 = d / len
		var ref: Vector3 = Vector3(0.123, 0.4, 0.9) if absf(up.dot(Vector3(0.123, 0.4, 0.9).normalized())) < 0.95 else Vector3.RIGHT
		var side: Vector3 = up.cross(ref).normalized()
		mi.basis = Basis(side, up, side.cross(up))
	_add(mi, (a + b) * 0.5, parent)
	_no_shadow(mi)
	return mi


## A sagging rope from a to b (a few straight pieces).
func rope(a: Vector3, b: Vector3, sag: float, r: float = 0.04, c: Color = Color(0.55, 0.45, 0.3), parent: Node3D = null) -> void:
	var m: StandardMaterial3D = mat(c, 0.9)
	var n: int = 6
	var prev: Vector3 = a
	for i: int in range(1, n + 1):
		var k: float = float(i) / float(n)
		var p: Vector3 = a.lerp(b, k) - Vector3(0, sag * 4.0 * k * (1.0 - k), 0)
		rod(prev, p, r, m, parent, 5)
		prev = p


# ---- the hip roof: the signature curved, upturned, tiered roof --------------------------------

## A tiled hip roof whose eave rim is `w` x `d` at height `y0` (local to `parent` or world), `h` tall.
## Two stacked frustums (a shallow skirt and a steeper cap) read as a curved roof, with upturned
## corner tips and a ridge.
func roof(c: Vector3, w: float, d: float, h: float, yaw: float = 0.0, parent: Node3D = null, col: Color = TILE) -> Node3D:
	var r := Node3D.new()
	r.rotation.y = yaw
	_add(r, c, parent)
	var tile: StandardMaterial3D = mat(col, 0.55, 0.15)
	var under: StandardMaterial3D = mat(DARK_WOOD, 0.8)
	# the skirt: a wide shallow frustum (4-sided cylinder turned 45 degrees, scaled to w x d)
	var skirt := _frustum(1.0, 0.72, h * 0.32, tile)
	skirt.scale = Vector3(w, 1.0, d)
	skirt.position = Vector3(0, h * 0.16, 0)
	r.add_child(skirt)
	var cap := _frustum(0.72, 0.12, h * 0.68, tile)
	cap.scale = Vector3(w, 1.0, d)
	cap.position = Vector3(0, h * 0.32 + h * 0.34, 0)
	r.add_child(cap)
	# the dark soffit under the eave
	r.add_child(Look.box(Vector3(w * 0.96, 0.12, d * 0.96), under, Vector3(0, -0.04, 0)))
	# the upturned corner tips (little swept beams) and a pale eave line
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var tip := Look.box(Vector3(0.22, 0.16, maxf(w, d) * 0.16), tile, Vector3(sx * w * 0.47, h * 0.06, sz * d * 0.47))
			tip.rotation = Vector3(-0.45, atan2(sx * w, sz * d), 0)
			r.add_child(tip)
	r.add_child(Look.box(Vector3(w * 0.12, h * 0.1, d * 0.12 + 0.2), tile, Vector3(0, h + h * 0.02, 0)))
	return r


func _frustum(bottom: float, top: float, h: float, m: Material) -> Node3D:
	var holder := Node3D.new()
	var cm := Look.cylinder(bottom * 0.7071, h, m, Vector3.ZERO, top * 0.7071, 4)
	cm.rotation.y = PI * 0.25
	holder.add_child(cm)
	return holder


# ---- landmarks ---------------------------------------------------------------------------------

## A cherry tree in full blossom: a dark twisting trunk, a few limbs and a cloud of pink canopy.
func cherry_tree(pos: Vector3, k: float = 1.0, tint: Color = BLOSSOM) -> Node3D:
	var t := Node3D.new()
	_add(t, pos)
	var bark: StandardMaterial3D = mat(Color(0.2, 0.13, 0.11), 0.9)
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) * k
	var base := Vector3.ZERO
	var mid := Vector3(0, 1.8 * k, 0) + lean * 0.5
	var crown := Vector3(0, 3.2 * k, 0) + lean
	rod(base + pos, mid + pos, 0.3 * k, bark, null, 7)
	rod(mid + pos, crown + pos, 0.22 * k, bark, null, 7)
	var cols: Array[Color] = [tint, tint.lightened(0.15), BLOSSOM_PALE, tint.darkened(0.06), BLOSSOM_DEEP]
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0 + rng.randf() * 0.6
		var reach: float = rng.randf_range(1.4, 2.3) * k
		var tip: Vector3 = crown + Vector3(cos(a) * reach, rng.randf_range(0.3, 1.2) * k, sin(a) * reach)
		rod(crown + pos, tip + pos, 0.1 * k, bark, null, 5)
		var s := Look.sphere(1.0, blossom(cols[i % cols.size()]), tip + Vector3(0, 0.25 * k, 0))
		s.scale = Vector3(1.5, 0.95, 1.5) * k * rng.randf_range(0.85, 1.15)
		t.add_child(s)
	var top := Look.sphere(1.0, blossom(cols[1]), crown + Vector3(0, 1.0 * k, 0))
	top.scale = Vector3(2.0, 1.2, 2.0) * k
	t.add_child(top)
	return t


## A pagoda: `tiers` storeys of dark-timbered vermilion walls, each under an upturned roof, with a
## bronze finial spire of rings on top. `k` scales the whole thing (k 1 = about 4 m per storey).
func pagoda(pos: Vector3, tiers: int, k: float = 1.0, yaw: float = 0.0) -> Node3D:
	var p := Node3D.new()
	p.rotation.y = yaw
	_add(p, pos)
	var wall: StandardMaterial3D = mat(VERMILION, 0.6)
	var post: StandardMaterial3D = mat(LACQUER, 0.5)
	var paper_m: StandardMaterial3D = paper(0.8)
	var y: float = 0.0
	p.add_child(Look.box(Vector3(9.0, 1.0, 9.0) * Vector3(k, 1.0, k), mat(STONE, 0.9), Vector3(0, 0.5, 0)))
	y = 1.0
	for i: int in tiers:
		var w: float = (6.5 - float(i) * 0.75) * k
		var h: float = 3.0 * k
		p.add_child(Look.box(Vector3(w, h, w), wall, Vector3(0, y + h * 0.5, 0)))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				p.add_child(Look.box(Vector3(0.3, h, 0.3) * Vector3(k, 1.0, k), post, Vector3(sx * w * 0.5, y + h * 0.5, sz * w * 0.5)))
		# a glowing paper window on every face
		for f: int in 4:
			var a: float = float(f) * PI * 0.5
			var win := Look.box(Vector3(w * 0.36, h * 0.42, 0.06), paper_m, Vector3(sin(a), 0, cos(a)) * (w * 0.5 + 0.02) + Vector3(0, y + h * 0.5, 0))
			win.rotation.y = a
			p.add_child(_no_shadow(win))
		y += h
		roof(Vector3(0, y, 0), w + 3.2 * k, w + 3.2 * k, 1.5 * k, 0.0, p)
		y += 1.0 * k
	# the finial: a spire of nine bronze rings
	var br: StandardMaterial3D = mat(BRONZE, 0.4, 0.7)
	p.add_child(Look.cylinder(0.12 * k, 5.0 * k, br, Vector3(0, y + 2.5 * k, 0), -1.0, 8))
	for i: int in 9:
		p.add_child(Look.cylinder((0.5 - float(i) * 0.03) * k, 0.12 * k, br, Vector3(0, y + 0.6 * k + float(i) * 0.42 * k, 0), -1.0, 12))
	p.add_child(Look.sphere(0.32 * k, mat(GOLD, 0.3, 0.8), Vector3(0, y + 5.1 * k, 0)))
	return p


## A torii gate: two vermilion posts, the tie beam and the black-capped top beam with upswept ends.
## `pos` is the floor point between the posts; the gate spans local X.
func torii(pos: Vector3, width: float, height: float, yaw: float = 0.0, col: Color = VERMILION) -> Node3D:
	var g := Node3D.new()
	g.rotation.y = yaw
	_add(g, pos)
	var red: StandardMaterial3D = mat(col, 0.55)
	var blk: StandardMaterial3D = mat(LACQUER, 0.5)
	var r: float = clampf(width * 0.045, 0.16, 0.5)
	for sx: float in [-1.0, 1.0]:
		g.add_child(Look.cylinder(r, height, red, Vector3(sx * width * 0.5, height * 0.5, 0), r * 0.85, 12))
		g.add_child(Look.cylinder(r * 1.25, 0.45, blk, Vector3(sx * width * 0.5, 0.22, 0), -1.0, 12))
	g.add_child(Look.box(Vector3(width + r * 3.0, r * 1.1, r * 1.1), red, Vector3(0, height * 0.78, 0)))
	var top := Look.box(Vector3(width + r * 8.0, r * 1.4, r * 1.9), red, Vector3(0, height + r * 0.3, 0))
	g.add_child(top)
	g.add_child(Look.box(Vector3(width + r * 9.0, r * 0.7, r * 2.1), blk, Vector3(0, height + r * 1.3, 0)))
	for sx: float in [-1.0, 1.0]:
		var end := Look.box(Vector3(r * 3.0, r * 0.7, r * 2.1), blk, Vector3(sx * (width * 0.5 + r * 5.0), height + r * 1.7, 0))
		end.rotation.z = sx * 0.28
		g.add_child(end)
	# the plaque between the beams (abstract gold border, no lettering)
	g.add_child(Look.box(Vector3(r * 2.4, height * 0.18, r * 0.5), blk, Vector3(0, height * 0.89, 0)))
	g.add_child(Look.box(Vector3(r * 1.8, height * 0.13, r * 0.55), mat(GOLD, 0.4, 0.6), Vector3(0, height * 0.89, 0)))
	return g


## A stone lantern (toro): plinth, shaft, a glowing firebox under a wide cap and a finial.
func stone_lantern(pos: Vector3, k: float = 1.0, light: bool = false) -> Node3D:
	var l := Node3D.new()
	_add(l, pos)
	var st: StandardMaterial3D = mat(STONE, 0.95)
	l.add_child(Look.cylinder(0.45 * k, 0.3 * k, st, Vector3(0, 0.15 * k, 0), 0.38 * k, 6))
	l.add_child(Look.cylinder(0.16 * k, 1.0 * k, st, Vector3(0, 0.8 * k, 0), 0.13 * k, 8))
	l.add_child(Look.cylinder(0.38 * k, 0.16 * k, st, Vector3(0, 1.36 * k, 0), 0.32 * k, 6))
	l.add_child(Look.box(Vector3(0.46, 0.42, 0.46) * k, st, Vector3(0, 1.66 * k, 0)))
	l.add_child(_no_shadow(Look.box(Vector3(0.48, 0.24, 0.3) * k, glow(GLOW, 2.6), Vector3(0, 1.66 * k, 0))))
	l.add_child(_no_shadow(Look.box(Vector3(0.3, 0.24, 0.48) * k, glow(GLOW, 2.6), Vector3(0, 1.66 * k, 0))))
	l.add_child(Look.cylinder(0.62 * k, 0.32 * k, st, Vector3(0, 2.02 * k, 0), 0.14 * k, 6))
	l.add_child(Look.sphere(0.12 * k, st, Vector3(0, 2.26 * k, 0)))
	l.add_child(Look.cylinder(0.5 * k, 0.04, mat(MOSS, 0.95), Vector3(0, 0.31 * k, 0), 0.4 * k, 6))
	if light:
		var o := OmniLight3D.new()
		o.light_color = GLOW
		o.light_energy = 1.2
		o.omni_range = 6.0 * k
		o.position = Vector3(0, 1.7 * k, 0)
		l.add_child(o)
	return l


## A round paper lantern (chochin): a glowing ribbed body with black caps.
func paper_lantern(pos: Vector3, r: float = 0.4, col: Color = Color(1.0, 0.55, 0.3), parent: Node3D = null, light: bool = false) -> Node3D:
	var l := Node3D.new()
	_add(l, pos, parent)
	var body := Look.sphere(1.0, glow(col, 2.0))
	body.scale = Vector3(r, r * 1.25, r)
	l.add_child(_no_shadow(body))
	for sy: float in [-1.0, 1.0]:
		l.add_child(_no_shadow(Look.cylinder(r * 0.55, r * 0.2, mat(LACQUER, 0.5), Vector3(0, sy * r * 1.2, 0), -1.0, 12)))
	if light:
		var o := OmniLight3D.new()
		o.light_color = col
		o.light_energy = 1.3
		o.omni_range = 7.0
		l.add_child(o)
	return l


## A string of paper lanterns hung between two points (rope sagging, lanterns along it).
func lantern_string(a: Vector3, b: Vector3, count: int, sag: float = 0.8) -> void:
	rope(a, b, sag, 0.025, Color(0.3, 0.22, 0.16))
	var cols: Array[Color] = [Color(1.0, 0.5, 0.25), Color(1.0, 0.75, 0.4), Color(1.0, 0.36, 0.3)]
	for i: int in count:
		var k: float = (float(i) + 0.5) / float(count)
		var p: Vector3 = a.lerp(b, k) - Vector3(0, sag * 4.0 * k * (1.0 - k) + 0.45, 0)
		paper_lantern(p, 0.26, cols[i % cols.size()])


## A clump of bamboo culms with ringed nodes and leafy tops.
func bamboo_clump(pos: Vector3, count: int, height: float, spread: float = 1.2) -> Node3D:
	var c := Node3D.new()
	_add(c, pos)
	var green: StandardMaterial3D = mat(BAMBOO, 0.55)
	var node_m: StandardMaterial3D = mat(BAMBOO.darkened(0.3), 0.6)
	var leaf: StandardMaterial3D = mat(Color(0.32, 0.5, 0.22), 0.8)
	for i: int in count:
		var off := Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		var h: float = height * rng.randf_range(0.8, 1.15)
		var r: float = rng.randf_range(0.09, 0.15)
		var tip: Vector3 = off + Vector3(rng.randf_range(-0.6, 0.6), h, rng.randf_range(-0.6, 0.6))
		rod(pos + off, pos + tip, r, green, null, 7)
		var nodes: int = int(h / 1.4)
		for j: int in range(1, nodes):
			var q: Vector3 = off.lerp(tip, float(j) / float(nodes))
			c.add_child(_no_shadow(Look.cylinder(r * 1.25, 0.08, node_m, q, -1.0, 8)))
		for j: int in 3:
			var lp: Vector3 = tip + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-1.2, 0.1), rng.randf_range(-0.8, 0.8))
			var lf := Look.sphere(1.0, leaf, lp)
			lf.scale = Vector3(0.9, 0.22, 0.4)
			lf.rotation.y = rng.randf() * TAU
			c.add_child(_no_shadow(lf))
	return c


## A village house: plaster walls in a dark timber frame, a glowing window, a hip roof.
func house(pos: Vector3, w: float, d: float, h: float, yaw: float = 0.0) -> Node3D:
	var hs := Node3D.new()
	hs.rotation.y = yaw
	_add(hs, pos)
	hs.add_child(Look.box(Vector3(w, h, d), mat(PLASTER, 0.9), Vector3(0, h * 0.5, 0)))
	var tim: StandardMaterial3D = mat(DARK_WOOD, 0.8)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			hs.add_child(Look.box(Vector3(0.25, h, 0.25), tim, Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5)))
	hs.add_child(Look.box(Vector3(w + 0.1, 0.22, d + 0.1), tim, Vector3(0, h * 0.62, 0)))
	hs.add_child(Look.box(Vector3(w + 0.1, 0.3, d + 0.1), mat(STONE, 0.9), Vector3(0, 0.15, 0)))
	for sz: float in [-1.0, 1.0]:
		hs.add_child(_no_shadow(Look.box(Vector3(w * 0.4, h * 0.3, 0.05), paper(1.2), Vector3(0, h * 0.4, sz * (d * 0.5 + 0.03)))))
	roof(Vector3(0, h, 0), w + 1.6, d + 1.6, minf(w, d) * 0.45, 0.0, hs)
	return hs


## A great bronze temple bell (bonsho) hanging from `top` (world).
func temple_bell(top: Vector3, r: float = 1.0, parent: Node3D = null) -> Node3D:
	var b := Node3D.new()
	_add(b, top, parent)
	var br: StandardMaterial3D = mat(BRONZE, 0.35, 0.8)
	b.add_child(Look.cylinder(r * 0.82, r * 2.0, br, Vector3(0, -r * 1.15, 0), r * 0.62, 20))
	b.add_child(Look.cylinder(r * 0.88, r * 0.2, br, Vector3(0, -r * 2.1, 0), -1.0, 20))
	b.add_child(Look.sphere(r * 0.62, br, Vector3(0, -r * 0.15, 0)))
	b.add_child(Look.cylinder(r * 0.12, r * 0.4, br, Vector3(0, 0.05, 0), -1.0, 8))
	# the boss bands (raised nipples in rows, abstract)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		b.add_child(Look.sphere(r * 0.07, br, Vector3(cos(a) * r * 0.74, -r * 0.6, sin(a) * r * 0.74)))
	return b


## A vermilion railing along a line (posts and two rails), visual only.
func railing(a: Vector3, b: Vector3, h: float = 0.9, posts: int = -1) -> void:
	var red: StandardMaterial3D = mat(VERMILION, 0.55)
	var n: int = posts if posts > 0 else maxi(int(a.distance_to(b) / 2.0), 1)
	for i: int in n + 1:
		var p: Vector3 = a.lerp(b, float(i) / float(n))
		root.add_child(_no_shadow(Look.cylinder(0.07, h, red, p + Vector3(0, h * 0.5, 0), -1.0, 6)))
		root.add_child(_no_shadow(Look.sphere(0.1, mat(GOLD, 0.4, 0.6), p + Vector3(0, h + 0.05, 0))))
	rod(a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.05, red)
	rod(a + Vector3(0, h * 0.5, 0), b + Vector3(0, h * 0.5, 0), 0.04, red)


## A misty mountain: a big cone with a pale shoulder (far scenery; cheap).
func mountain(pos: Vector3, r: float, h: float, c: Color, snow: bool = false) -> Node3D:
	var m := Node3D.new()
	_add(m, pos)
	var mm: StandardMaterial3D = mat(c, 1.0)
	var body := Look.cylinder(r, h, mm, Vector3(0, h * 0.5, 0), r * 0.08, 9)
	body.rotation.y = rng.randf() * TAU
	m.add_child(_no_shadow(body))
	var shoulder := Look.cylinder(r * 1.25, h * 0.35, mat(c.darkened(0.08), 1.0), Vector3(r * 0.35, h * 0.17, r * 0.2), r * 0.5, 9)
	m.add_child(_no_shadow(shoulder))
	if snow:
		m.add_child(_no_shadow(Look.cylinder(r * 0.27, h * 0.24, mat(Color(1.0, 0.86, 0.86), 0.9), Vector3(0, h * 0.86, 0), r * 0.07, 9)))
	return m


## A distant castle keep silhouette: stacked white tiers under dark roofs, on a stone base.
func keep(pos: Vector3, k: float, yaw: float = 0.0) -> Node3D:
	var c := Node3D.new()
	c.rotation.y = yaw
	_add(c, pos)
	c.add_child(Look.cylinder(14.0 * k, 8.0 * k, mat(STONE.darkened(0.15), 0.95), Vector3(0, 4.0 * k, 0), 10.0 * k, 4))
	var y: float = 8.0 * k
	for i: int in 4:
		var w: float = (14.0 - float(i) * 2.6) * k
		var h: float = 4.0 * k
		c.add_child(Look.box(Vector3(w, h, w * 0.8), mat(PLASTER, 0.9), Vector3(0, y + h * 0.5, 0)))
		y += h
		roof(Vector3(0, y, 0), w + 3.0 * k, w * 0.8 + 3.0 * k, 2.0 * k, 0.0, c)
		y += 1.2 * k
	return c
