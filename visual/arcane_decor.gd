class_name ArcaneDecor
extends RefCounted
## The Arcane Library's set dressing: towering bookcases (procedural spines on a shader), candelabras
## and chandeliers burning with warm flames, floating oak staircases, gothic arches, lecterns, desks,
## globes, stacks of tomes, giant quills in inkwells and armillary spheres turning in the dark. Also
## the reskins of the generic kit obstacles (sliding bookshelves, falling tomes, candle-beam posts,
## lectern rams, book presses, quill sweepers). All visual (no collision), built from shared Look
## meshes and a handful of materials; flames are emissive meshes (a few real lights only where asked).

const GOLD := Color(1.0, 0.78, 0.35)
const VIOLET := Color(0.62, 0.4, 1.0)
const OAK := Color(0.36, 0.2, 0.11)
const DARK_OAK := Color(0.2, 0.1, 0.06)
const LEATHER := Color(0.46, 0.09, 0.16)
const BRASS := Color(0.78, 0.6, 0.28)
const PARCHMENT := Color(0.95, 0.88, 0.7)
const FLAME := Color(1.0, 0.62, 0.2)

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


func _oak() -> StandardMaterial3D:
	return Look.flat(OAK, 0.6)


func _dark() -> StandardMaterial3D:
	return Look.flat(DARK_OAK, 0.65)


func _brass() -> StandardMaterial3D:
	return Look.flat(BRASS, 0.3, 0.8, 0.15)


func _glow(col: Color, e: float = 2.4) -> StandardMaterial3D:
	return Look.flat(col, 0.3, 0.0, e)


func _node(pos: Vector3, b: Basis = Basis.IDENTITY) -> Node3D:
	var n := Node3D.new()
	n.transform = Transform3D(b, pos)
	root.add_child(n)
	return n


func _put(parent: Node3D, mi: MeshInstance3D, no_shadow: bool = false) -> MeshInstance3D:
	if no_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func turn(yaw: float, pitch: float = 0.0, roll: float = 0.0) -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, roll))


## Bookshelf face material for a box of `size`.
func books_material(size: Vector3, tone: float = 0.0, row_h: float = 0.85) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/arcane_books.gdshader")
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("tone", tone)
	m.set_shader_parameter("row_h", row_h)
	return m


# ---- shelves, candles, furniture -----------------------------------------------------------------

## A tall bookcase (no collision): `pos` = the middle of its base; w across (x), h tall, d deep (z).
func shelf(pos: Vector3, b: Basis, w: float, h: float, d: float, tone: float = 0.0) -> Node3D:
	var n: Node3D = _node(pos, b)
	_put(n, Look.mesh_node(_box_mesh(Vector3(w, h, d)), books_material(Vector3(w, h, d), tone)), false).position = Vector3(0, h * 0.5, 0)
	_put(n, Look.box(Vector3(w + 0.3, 0.3, d + 0.3), _dark(), Vector3(0, h + 0.15, 0)))
	_put(n, Look.box(Vector3(w + 0.2, 0.25, d + 0.2), _dark(), Vector3(0, 0.12, 0)))
	return n


var _box_cache: Dictionary = {}


func _box_mesh(size: Vector3) -> BoxMesh:
	if not _box_cache.has(size):
		var bm := BoxMesh.new()
		bm.size = size
		_box_cache[size] = bm
	return _box_cache[size]


## A brass candelabra with `flames` candles. `pos` = its foot.
func candelabra(pos: Vector3, h: float = 1.5, flames: int = 3, with_light: bool = false) -> Node3D:
	var n: Node3D = _node(pos)
	var brass: StandardMaterial3D = _brass()
	_put(n, Look.cylinder(0.28, 0.1, brass, Vector3(0, 0.05, 0), 0.2, 12))
	_put(n, Look.cylinder(0.05, h, brass, Vector3(0, h * 0.5, 0), 0.04, 8))
	var wax: StandardMaterial3D = Look.flat(PARCHMENT, 0.8)
	for i: int in flames:
		var a: float = TAU * float(i) / float(maxi(flames, 1)) + 0.5
		var arm: float = 0.0 if flames == 1 else 0.38
		var p := Vector3(cos(a) * arm, h + 0.05, sin(a) * arm)
		if arm > 0.0:
			var link := Look.box(Vector3(arm, 0.04, 0.04), brass, Vector3(cos(a) * arm * 0.5, h - 0.05, sin(a) * arm * 0.5))
			link.rotation.y = -a
			_put(n, link)
		_put(n, Look.cylinder(0.05, 0.22, wax, p + Vector3(0, 0.11, 0), -1.0, 8))
		_put(n, Look.sphere(0.07, _glow(FLAME, 3.2), p + Vector3(0, 0.3, 0)), true)
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 0.9
		l.omni_range = 7.0
		l.position = Vector3(0, h + 0.4, 0)
		n.add_child(l)
	return n


## A hanging ring of candles on three chains (hung from `pos`, the top of the chains).
func chandelier(pos: Vector3, r: float = 1.6, drop: float = 3.0) -> Node3D:
	var n: Node3D = _node(pos)
	var brass: StandardMaterial3D = _brass()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.07
	tm.outer_radius = r + 0.07
	tm.rings = 28
	tm.ring_segments = 6
	_put(n, Look.mesh_node(tm, brass, Vector3(0, -drop, 0)))
	var wax: StandardMaterial3D = Look.flat(PARCHMENT, 0.8)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var p := Vector3(cos(a) * r, -drop, sin(a) * r)
		_put(n, Look.cylinder(0.05, 0.25, wax, p + Vector3(0, 0.15, 0), -1.0, 8))
		_put(n, Look.sphere(0.07, _glow(FLAME, 3.0), p + Vector3(0, 0.35, 0)), true)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var link := Look.box(Vector3(0.03, drop + 0.2, 0.03), brass, Vector3(cos(a) * r * 0.5, -drop * 0.5, sin(a) * r * 0.5))
		link.rotation = Vector3(sin(a) * 0.12, 0, -cos(a) * 0.12)
		_put(n, link)
	_put(n, Look.sphere(0.2, brass, Vector3(0, 0, 0)))
	return n


## A reading desk (slanted top, a drawer) - `pos` = floor.
func desk(pos: Vector3, b: Basis, w: float = 2.4) -> Node3D:
	var n: Node3D = _node(pos, b)
	_put(n, Look.box(Vector3(w, 0.14, 1.1), _oak(), Vector3(0, 0.95, 0)))
	for sx: float in [-1.0, 1.0]:
		_put(n, Look.box(Vector3(0.12, 0.95, 0.9), _dark(), Vector3(sx * (w * 0.5 - 0.1), 0.47, 0)))
	_put(n, Look.box(Vector3(w - 0.3, 0.35, 0.9), _dark(), Vector3(0, 0.78, 0)))
	_put(n, Look.box(Vector3(0.5, 0.04, 0.36), Look.flat(PARCHMENT, 0.9), Vector3(-w * 0.2, 1.04, 0.1)))
	_put(n, Look.sphere(0.08, _glow(FLAME, 3.0), Vector3(w * 0.3, 1.25, -0.1)), true)
	_put(n, Look.cylinder(0.04, 0.18, Look.flat(PARCHMENT, 0.8), Vector3(w * 0.3, 1.11, -0.1), -1.0, 6))
	return n


## A lectern with an open book on it - `pos` = floor.
func lectern(pos: Vector3, b: Basis, s: float = 1.0) -> Node3D:
	var n: Node3D = _node(pos, b)
	_put(n, Look.cylinder(0.4 * s, 0.14, _dark(), Vector3(0, 0.07 * s, 0), -1.0, 10))
	_put(n, Look.cylinder(0.09 * s, 1.1 * s, _oak(), Vector3(0, 0.62 * s, 0), 0.12 * s, 8))
	var top := Look.box(Vector3(1.0, 0.07, 0.75) * s, _oak(), Vector3(0, 1.22 * s, 0))
	top.rotation.x = -0.35
	_put(n, top)
	var bk := Look.box(Vector3(0.86, 0.05, 0.6) * s, Look.flat(PARCHMENT, 0.85), Vector3(0, 1.28 * s, -0.02))
	bk.rotation.x = -0.35
	_put(n, bk)
	return n


func globe(pos: Vector3, r: float = 0.9) -> Node3D:
	var n: Node3D = _node(pos)
	_put(n, Look.cylinder(r * 0.4, 0.1, _dark(), Vector3(0, 0.05, 0), -1.0, 10))
	_put(n, Look.cylinder(0.05, r * 1.2, _brass(), Vector3(0, r * 0.6, 0), -1.0, 6))
	var sm := Look.sphere(r, Look.flat(Color(0.2, 0.3, 0.5), 0.4, 0.2, 0.15), Vector3(0, r * 1.5, 0))
	_put(n, sm)
	var tm := TorusMesh.new()
	tm.inner_radius = r * 1.1
	tm.outer_radius = r * 1.14
	tm.rings = 32
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, _brass(), Vector3(0, r * 1.5, 0))
	ring.rotation = Vector3(0.5, 0, 0.4)
	_put(n, ring)
	return n


## A stack of closed tomes, leaning.
func book_pile(pos: Vector3, count: int = 4) -> Node3D:
	var n: Node3D = _node(pos)
	var cols: Array[Color] = [LEATHER, Color(0.1, 0.14, 0.4), Color(0.1, 0.3, 0.18), Color(0.45, 0.3, 0.1), Color(0.34, 0.12, 0.38)]
	var y: float = 0.0
	for i: int in count:
		var sz := Vector3(rng.randf_range(0.7, 1.2), rng.randf_range(0.14, 0.26), rng.randf_range(0.5, 0.8))
		var bk := Look.box(sz, Look.flat(cols[rng.randi() % cols.size()], 0.6), Vector3(rng.randf_range(-0.06, 0.06), y + sz.y * 0.5, rng.randf_range(-0.06, 0.06)))
		bk.rotation.y = rng.randf_range(-0.5, 0.5)
		_put(n, bk)
		_put(n, Look.box(Vector3(sz.x - 0.08, sz.y * 0.5, sz.z + 0.02), Look.flat(PARCHMENT, 0.9), bk.position + Vector3(0.04, 0, 0)))
		y += sz.y
	return n


# ---- architecture ----------------------------------------------------------------------------------

## A gothic arch: two columns and a pointed head. `pos` = the middle of its base.
func arch(pos: Vector3, b: Basis, w: float = 3.0, h: float = 5.0, col: Color = GOLD) -> Node3D:
	var n: Node3D = _node(pos, b)
	var stone: StandardMaterial3D = Look.flat(Color(0.34, 0.27, 0.3), 0.75)
	var r: float = w * 0.5
	var leg: float = maxf(h - r, 0.5)
	for sx: float in [-1.0, 1.0]:
		_put(n, Look.cylinder(0.3, leg, stone, Vector3(sx * r, leg * 0.5, 0), 0.26, 10))
		_put(n, Look.box(Vector3(0.8, 0.22, 0.8), stone, Vector3(sx * r, 0.11, 0)))
		_put(n, Look.box(Vector3(0.74, 0.2, 0.74), stone, Vector3(sx * r, leg + 0.1, 0)))
	var k: int = 9
	for i: int in k:
		var a: float = PI * (float(i) + 0.5) / float(k)
		var v := Look.box(Vector3(0.5, r * PI / float(k) + 0.04, 0.55), stone, Vector3(cos(a) * r, leg + sin(a) * r, 0))
		v.rotation.z = a
		_put(n, v)
	_put(n, Look.box(Vector3(0.28, 0.28, 0.58), _glow(col, 2.4), Vector3(0, leg + r + 0.05, 0)), true)
	return n


## A flight of floating oak stairs going nowhere. `pos` = the foot.
func stairs(pos: Vector3, b: Basis, steps: int = 8, w: float = 1.8, rise: float = 0.3, run: float = 0.5) -> Node3D:
	var n: Node3D = _node(pos, b)
	var tread: StandardMaterial3D = _oak()
	var nose: StandardMaterial3D = _glow(GOLD, 1.5)
	for i: int in steps:
		_put(n, Look.box(Vector3(w, rise * 0.5, run), tread, Vector3(0, rise * (float(i) + 0.75), -run * (float(i) + 0.5))))
		_put(n, Look.box(Vector3(w, 0.03, 0.04), nose, Vector3(0, rise * (float(i) + 1.0) + 0.005, -run * float(i))), true)
	var slen: float = sqrt(pow(rise * float(steps), 2.0) + pow(run * float(steps), 2.0))
	var s := Look.box(Vector3(0.12, 0.3, slen), _dark(), Vector3(-w * 0.5, rise * float(steps) * 0.5 + 0.1, -run * float(steps) * 0.5))
	s.rotation.x = atan2(rise, run)
	_put(n, s)
	var s2 := Look.box(Vector3(0.12, 0.3, slen), _dark(), Vector3(w * 0.5, rise * float(steps) * 0.5 + 0.1, -run * float(steps) * 0.5))
	s2.rotation.x = atan2(rise, run)
	_put(n, s2)
	return n


## A slim stone column under a landing, broken off below. `top` = under the slab.
func column(top: Vector3, r: float, length: float) -> void:
	var n: Node3D = _node(top)
	var stone: StandardMaterial3D = Look.flat(Color(0.34, 0.27, 0.3), 0.75)
	_put(n, Look.box(Vector3(r * 2.6, 0.16, r * 2.6), stone, Vector3(0, -0.08, 0)))
	_put(n, Look.cylinder(r * 0.8, length, stone, Vector3(0, -length * 0.5 - 0.16, 0), r, 10))
	for i: int in 3:
		var c := Look.box(Vector3.ONE * r * rng.randf_range(0.7, 1.2), stone, Vector3(rng.randf_range(-0.3, 0.3), -length - 0.6 - 0.9 * float(i), rng.randf_range(-0.3, 0.3)))
		c.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		_put(n, c)


## A tapering stepped keel of oak and brass under a big slab (the underside of a floating reading room).
func keel(top: Vector3, sx: float, sz: float, depth: float) -> void:
	var n: Node3D = _node(top)
	var steps: int = 4
	for i: int in steps:
		var k: float = 1.0 - float(i + 1) / float(steps + 1)
		_put(n, Look.box(Vector3(sx * k, depth / float(steps), sz * k), _dark() if i % 2 == 0 else _oak(), Vector3(0, -depth / float(steps) * (float(i) + 0.5), 0)))
	_put(n, _flame_orb(Vector3(0, -depth - 0.2, 0), 0.12), true)


func _flame_orb(at: Vector3, r: float) -> MeshInstance3D:
	return Look.sphere(r, _glow(FLAME, 3.0), at)


# ---- things in the air -------------------------------------------------------------------------------

## An open book hovering and slowly turning (`s` metres wide).
func floating_book(pos: Vector3, b: Basis, s: float = 1.4) -> Node3D:
	var n: Node3D = _node(pos, b)
	var lm: StandardMaterial3D = Look.flat(LEATHER, 0.6)
	var pm: StandardMaterial3D = Look.flat(PARCHMENT, 0.9, 0.0, 0.3)
	for sgn: float in [-1.0, 1.0]:
		var half := Node3D.new()
		half.rotation.z = sgn * 0.25
		n.add_child(half)
		_put(half, Look.box(Vector3(s * 0.5, 0.05, s * 0.7), lm, Vector3(sgn * s * 0.25, 0, 0)))
		_put(half, Look.box(Vector3(s * 0.46, 0.06, s * 0.64), pm, Vector3(sgn * s * 0.25, 0.04, 0)))
	_put(n, Look.box(Vector3(s * 0.08, 0.02, s * 0.5), _glow(GOLD, 1.8), Vector3(0, 0.08, 0)), true)
	n.set_script(preload("res://visual/spin.gd"))
	n.set("period", rng.randf_range(24.0, 50.0) * (1.0 if rng.randf() < 0.5 else -1.0))
	return n


## A giant quill standing in an inkwell (far scenery; `s` scales it).
func quill(pos: Vector3, b: Basis, s: float = 1.0) -> Node3D:
	var n: Node3D = _node(pos, b)
	_put(n, Look.cylinder(0.9 * s, 1.1 * s, Look.flat(Color(0.05, 0.04, 0.12), 0.1, 0.4), Vector3(0, 0.55 * s, 0), 0.7 * s, 16))
	_put(n, Look.cylinder(0.9 * s, 0.14 * s, _brass(), Vector3(0, 0.07 * s, 0), -1.0, 16))
	var shaft := Look.cylinder(0.05 * s, 8.0 * s, Look.flat(PARCHMENT, 0.5), Vector3(0.6 * s, 4.6 * s, 0), 0.03 * s, 6)
	shaft.rotation.z = -0.18
	_put(n, shaft)
	var vane := Look.sphere(1.0, Look.flat(Color(0.85, 0.8, 0.95), 0.7, 0.0, 0.2), Vector3(1.3 * s, 6.2 * s, 0))
	vane.scale = Vector3(0.9 * s, 3.4 * s, 0.12 * s)
	vane.rotation.z = -0.18
	_put(n, vane)
	return n


## An armillary sphere: three brass rings gimballed and turning, a glowing core (far scenery).
func armillary(pos: Vector3, r: float = 6.0) -> Node3D:
	var n: Node3D = _node(pos)
	var brass: StandardMaterial3D = _brass()
	for i: int in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = r * (0.98 - 0.12 * float(i))
		tm.outer_radius = r * (1.0 - 0.12 * float(i)) + 0.05 * r * 0.1
		tm.rings = 48
		tm.ring_segments = 6
		var holder := Node3D.new()
		holder.rotation = Vector3(float(i) * 0.9, float(i) * 0.5, float(i) * 0.7)
		n.add_child(holder)
		_put(holder, Look.mesh_node(tm, brass))
		holder.set_script(preload("res://visual/spin.gd"))
		holder.set("period", (26.0 + 11.0 * float(i)) * (1.0 if i % 2 == 0 else -1.0))
		holder.set("axis", Vector3(0.3, 1.0, 0.2).normalized())
	_put(n, Look.sphere(r * 0.18, _glow(GOLD, 3.0), Vector3.ZERO), true)
	return n


## A planet on the orrery: a lit sphere `r` across with a thin ring option.
func planet(pos: Vector3, r: float, col: Color, ringed: bool = false) -> Node3D:
	var n: Node3D = _node(pos)
	_put(n, Look.sphere(r, Look.flat(col, 0.45, 0.1, 0.35), Vector3.ZERO))
	if ringed:
		var tm := TorusMesh.new()
		tm.inner_radius = r * 1.5
		tm.outer_radius = r * 1.9
		tm.rings = 32
		tm.ring_segments = 3
		var ring := Look.mesh_node(tm, Look.flat(col.lightened(0.2), 0.6, 0.0, 0.2))
		ring.scale = Vector3(1, 0.05, 1)
		ring.rotation.z = 0.3
		_put(n, ring)
	return n


# ---- reskins of the kit obstacles and machines ---------------------------------------------------------------

## The gap wall becomes a sliding bookcase: its stock panels give way to shelves of spines (they move
## with it) between brass-bound jambs.
func dress_gap_wall(gw: GapWall) -> void:
	var wall: Node3D = gw.get_child(0) as Node3D
	var pieces: Array[Vector3] = []
	for c: Node in wall.get_children():
		if c is CollisionShape3D:
			pieces.append((c as CollisionShape3D).position)
	for c: Node in wall.get_children():
		if c is MeshInstance3D and absf((c as Node3D).position.x) > 0.01:
			(c as MeshInstance3D).visible = false
	for p: Vector3 in pieces:
		var piece_w: float = gw.slide + gw.gap * 0.5 + 2.5
		var m := Look.mesh_node(_box_mesh(Vector3(piece_w, gw.height, gw.thick)), books_material(Vector3(piece_w, gw.height, gw.thick), 3.0 + signf(p.x)), p)
		wall.add_child(m)
		var sgn: float = signf(p.x)
		wall.add_child(Look.box(Vector3(0.34, gw.height, gw.thick + 0.1), _brass(), Vector3(sgn * (gw.gap * 0.5 + 0.17), gw.height * 0.5, 0)))
		wall.add_child(Look.box(Vector3(piece_w + 0.2, 0.3, gw.thick + 0.2), _dark(), Vector3(p.x, gw.height + 0.15, 0)))


## The falling block becomes a huge tome: leather cover, cream page edges, a gilt clasp.
func dress_falling_block(fb: FallingBlock) -> void:
	var s: Vector3 = fb.size
	for c: Node in fb.get_children():
		if c is MeshInstance3D:
			var mesh: Mesh = (c as MeshInstance3D).mesh
			if mesh is CylinderMesh or (mesh is BoxMesh and (mesh as BoxMesh).size.is_equal_approx(s)):
				(c as MeshInstance3D).visible = false
	var leather: StandardMaterial3D = Look.flat(LEATHER, 0.55, 0.05)
	fb.add_child(Look.box(Vector3(s.x, s.y * 0.2, s.z), leather, Vector3(0, s.y * 0.4, 0)))
	fb.add_child(Look.box(Vector3(s.x, s.y * 0.2, s.z), leather, Vector3(0, -s.y * 0.4, 0)))
	fb.add_child(Look.box(Vector3(s.x - 0.16, s.y * 0.62, s.z - 0.14), Look.flat(PARCHMENT, 0.85), Vector3(0.04, 0, 0)))
	fb.add_child(Look.box(Vector3(0.18, s.y, s.z), leather, Vector3(-s.x * 0.5 + 0.09, 0, 0)))
	fb.add_child(Look.box(Vector3(s.x * 0.5, 0.05, s.z * 0.5), _brass(), Vector3(0, s.y * 0.5 + 0.01, 0)))
	fb.add_child(Look.box(Vector3(0.1, s.y * 0.5, 0.4), _brass(), Vector3(s.x * 0.5 - 0.03, 0, 0)))


## Crystal prisms on a laser's posts: a candle beam / spell beam.
func dress_laser(g: LaserGate) -> void:
	var post_h: float = maxf(g.size.y + 0.8, 1.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.55, 1.0, 0.7)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.emission_enabled = true
	glass.emission = VIOLET
	glass.emission_energy_multiplier = 0.8
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (g.size.x * 0.5 + 0.18)
		g.add_child(Look.box(Vector3(0.5, 0.12, 0.5), _brass(), Vector3(x, post_h * 0.5 + 0.06, 0)))
		var m := Look.box(Vector3(0.2, 0.6, 0.2), glass, Vector3(x, post_h * 0.5 + 0.45, 0))
		m.rotation = Vector3(0.0, 0.7, 0.4)
		g.add_child(m)


## A lectern ram's housing: an oak cabinet round the piston with drawer fronts and brass pulls. `top`
## / `yaw` as given to kit.piston (world).
func dress_ram(top: Vector3, size: Vector3, stroke: float, yaw_deg: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var depth: float = stroke + 0.45
	var c: Vector3 = top - Vector3(0, size.y * 0.5, 0) + b * Vector3(0, 0, size.z * 0.5 + depth * 0.5 + 0.02)
	var n: Node3D = _node(c, b)
	var h: float = size.y + 1.6
	var w: float = size.x + 0.8
	_put(n, Look.box(Vector3(0.4, h, depth), _oak(), Vector3(-w * 0.5 + 0.2, 0, 0)))
	_put(n, Look.box(Vector3(0.4, h, depth), _oak(), Vector3(w * 0.5 - 0.2, 0, 0)))
	_put(n, Look.box(Vector3(w - 0.8, 0.78, depth), _oak(), Vector3(0, h * 0.5 - 0.39, 0)))
	_put(n, Look.box(Vector3(w - 0.8, 0.78, depth), _oak(), Vector3(0, -h * 0.5 + 0.39, 0)))
	_put(n, Look.box(Vector3(w + 0.12, 0.1, depth + 0.12), _dark(), Vector3(0, h * 0.5 + 0.05, 0)))
	for sy: float in [-1.0, 1.0]:
		_put(n, Look.box(Vector3(w - 0.9, 0.6, 0.05), _dark(), Vector3(0, sy * (h * 0.5 - 0.39), -depth * 0.5 - 0.03)))
		_put(n, Look.sphere(0.07, _brass(), Vector3(0, sy * (h * 0.5 - 0.39), -depth * 0.5 - 0.1)))


## A book press: the crusher's plate carries a stack of tomes on its face and gilt corners.
func dress_crusher(c: Crusher) -> void:
	var s: Vector3 = c.size
	for sz: float in [-1.0, 1.0]:
		var face := Look.mesh_node(_box_mesh(Vector3(s.x * 0.9, s.y * 0.8, 0.1)), books_material(Vector3(s.x * 0.9, s.y * 0.8, 0.1), 5.0, 0.5), Vector3(0, 0.0, sz * (s.z * 0.5 + 0.06)))
		c.add_child(face)
	for sx: float in [-1.0, 1.0]:
		c.add_child(Look.box(Vector3(0.14, s.y + 0.1, s.z + 0.1), _brass(), Vector3(sx * (s.x * 0.5 + 0.02), 0, 0)))


## A quill sweeper: the kill bar becomes a long feather (shaft, vane, a gold nib at the tip).
func dress_sweeper(sw: Sweeper) -> void:
	var pivot: Node3D = sw.get_child(0) as Node3D
	for holder: Node in pivot.get_children():
		for c: Node in holder.get_children():
			if c is KillZone:
				for m: Node in c.get_children():
					if m is MeshInstance3D:
						(m as MeshInstance3D).visible = false
				var kz := c as KillZone
				var len: float = kz.size.x
				var shaft := Look.box(Vector3(len, 0.07, 0.07), Look.flat(PARCHMENT, 0.5), Vector3.ZERO)
				kz.add_child(shaft)
				var vane := Look.sphere(1.0, Look.flat(Color(0.88, 0.82, 0.96), 0.7, 0.0, 0.3), Vector3(-len * 0.05, 0.02, 0))
				vane.scale = Vector3(len * 0.45, 0.04, 0.3)
				kz.add_child(vane)
				kz.add_child(Look.cylinder(0.01, 0.4, _brass(), Vector3(len * 0.5 + 0.1, 0, 0), 0.07, 6))
				(kz.get_child(kz.get_child_count() - 1) as Node3D).rotation.z = -PI * 0.5


## A white-gold doorway frame round a warp ring: the spell door. `floor_pos` / yaw as given to kit.portal.
func dress_portal(floor_pos: Vector3, yaw_deg: float, col: Color) -> void:
	var n: Node3D = _node(floor_pos, Basis(Vector3.UP, deg_to_rad(yaw_deg)))
	for sx: float in [-1.0, 1.0]:
		_put(n, Look.box(Vector3(0.24, 3.2, 0.34), _oak(), Vector3(sx * 1.78, 1.6, 0)))
		_put(n, Look.box(Vector3(0.3, 0.1, 0.4), _brass(), Vector3(sx * 1.78, 0.05, 0)))
	_put(n, Look.box(Vector3(3.9, 0.28, 0.4), _oak(), Vector3(0, 3.34, 0)))
	_put(n, Look.box(Vector3(3.6, 0.06, 0.06), _glow(col, 2.4), Vector3(0, 3.2, -0.2)), true)
	_put(n, Look.sphere(0.12, _glow(col, 3.0), Vector3(0, 3.62, 0)), true)
