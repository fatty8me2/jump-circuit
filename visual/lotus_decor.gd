class_name LotusDecor
extends RefCounted
## Lotus Drift set dressing, all built from primitives: stone lanterns standing in the shallows,
## paper lanterns on strings, willows trailing their branches in the pond, maples, pines, bamboo,
## lotus flowers (one shared petal mesh) and lily pads, reeds and cattails, mossy rocks, moon gates,
## garden pavilions on stilts, far pagodas, waterfalls and the stream ribbons that dress the flow
## slopes. Nothing here collides. Materials are cached by Look (cleared per level load).

const GOLD := Color(1.0, 0.68, 0.28)
const LANTERN := Color(1.0, 0.56, 0.24)
const PINK := Color(1.0, 0.5, 0.7)
const PINK_PALE := Color(1.0, 0.82, 0.9)
const JADE := Color(0.35, 0.82, 0.68)
const STONE := Color(0.5, 0.5, 0.56)
const STONE_DARK := Color(0.28, 0.29, 0.36)
const MOSS := Color(0.22, 0.4, 0.22)
const WOOD := Color(0.34, 0.2, 0.14)
const DARK_WOOD := Color(0.2, 0.12, 0.1)
const LEAF := Color(0.2, 0.46, 0.3)
const WILLOW := Color(0.5, 0.68, 0.38)
const MAPLE := Color(0.86, 0.3, 0.16)
const TILE := Color(0.16, 0.2, 0.28)
const PAPER := Color(1.0, 0.92, 0.78)

const STREAM_SHADER: Shader = preload("res://visual/lotus_stream.gdshader")
const TILE_SHADER: Shader = preload("res://visual/lotus_tile.gdshader")
const WATER_SHADER: Shader = preload("res://visual/lotus_water.gdshader")

static var _flower_meshes: Dictionary = {}
static var _pad_mats: Dictionary = {}
static var _water_mat: ShaderMaterial

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


## Drop the cached materials and meshes (the level calls this once as it starts building).
static func reset() -> void:
	_flower_meshes.clear()
	_pad_mats.clear()
	_water_mat = null


func _add(n: Node3D, pos: Vector3, parent: Node3D = null) -> Node3D:
	n.position = pos
	(parent if parent != null else root).add_child(n)
	return n


static func _no_shadow(g: GeometryInstance3D) -> GeometryInstance3D:
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


# ---- materials ------------------------------------------------------------------------------

static func mat(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	return Look.flat(c, rough, metal)


## Warm glowing paper / flame (bounded emission).
static func glow(c: Color = LANTERN, energy: float = 2.0) -> StandardMaterial3D:
	return Look.flat(c, 0.6, 0.0, clampf(energy, 0.0, 4.0))


## The shared pond water material.
static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = WATER_SHADER
	return _water_mat


## A lotus-tile material for decorative (non-walkable) pads: kind 1 lily pad of this radius.
static func pad_material(radius: float) -> ShaderMaterial:
	var key: int = int(round(radius * 10.0))
	if not _pad_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = TILE_SHADER
		m.set_shader_parameter("kind", 1)
		m.set_shader_parameter("is_round", true)
		m.set_shader_parameter("half_size", Vector3(float(key) / 10.0, 0.04, float(key) / 10.0))
		m.set_shader_parameter("top_color", Color(0.2, 0.5, 0.3))
		m.set_shader_parameter("side_color", Color(0.1, 0.3, 0.2))
		_pad_mats[key] = m
	return _pad_mats[key]


# ---- small helpers ---------------------------------------------------------------------------

func slab(c: Vector3, size: Vector3, m: Material, yaw: float = 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := Look.box(size, m)
	mi.rotation.y = yaw
	_add(mi, c, parent)
	return mi


## A cylinder between two points (beams, cords, bamboo).
func rod(a: Vector3, b: Vector3, r: float, m: Material, parent: Node3D = null, segs: int = 8) -> MeshInstance3D:
	var d: Vector3 = b - a
	var len: float = d.length()
	var mi := Look.cylinder(r, maxf(len, 0.01), m, Vector3.ZERO, -1.0, segs)
	if len > 0.0001:
		var up: Vector3 = d / len
		var ref: Vector3 = Vector3(0.123, 0.4, 0.9).normalized()
		if absf(up.dot(ref)) > 0.95:
			ref = Vector3.RIGHT
		var side: Vector3 = up.cross(ref).normalized()
		mi.basis = Basis(side, up, side.cross(up))
	_add(mi, (a + b) * 0.5, parent)
	_no_shadow(mi)
	return mi


## A cord sagging from a to b (a few straight pieces); returns its points.
func cord(a: Vector3, b: Vector3, sag: float, r: float = 0.03, c: Color = Color(0.3, 0.2, 0.15), parent: Node3D = null) -> PackedVector3Array:
	var m: StandardMaterial3D = mat(c, 0.9)
	var n: int = 6
	var pts := PackedVector3Array()
	var prev: Vector3 = a
	pts.append(a)
	for i: int in range(1, n + 1):
		var k: float = float(i) / float(n)
		var p: Vector3 = a.lerp(b, k) - Vector3(0, sag * 4.0 * k * (1.0 - k), 0)
		rod(prev, p, r, m, parent, 4)
		pts.append(p)
		prev = p
	return pts


# ---- light and lanterns ------------------------------------------------------------------------

## A stone garden lantern (toro): base, post, a lit firebox, a hat roof and a jewel. `k` scales it.
func stone_lantern(pos: Vector3, k: float = 1.0, lit: bool = true) -> Node3D:
	var n := Node3D.new()
	_add(n, pos)
	var st: StandardMaterial3D = mat(STONE, 0.9)
	var dk: StandardMaterial3D = mat(STONE_DARK, 0.9)
	n.add_child(Look.cylinder(0.42 * k, 0.16 * k, dk, Vector3(0, 0.08 * k, 0), 0.34 * k, 8))
	n.add_child(Look.cylinder(0.13 * k, 0.9 * k, st, Vector3(0, 0.6 * k, 0), 0.11 * k, 8))
	n.add_child(Look.cylinder(0.36 * k, 0.12 * k, st, Vector3(0, 1.1 * k, 0), 0.28 * k, 8))
	n.add_child(Look.box(Vector3(0.42, 0.42, 0.42) * k, glow(LANTERN, 2.2) if lit else dk, Vector3(0, 1.38 * k, 0)))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.07, 0.46, 0.5) * k, st, Vector3(sx * 0.23 * k, 1.38 * k, 0)))
		n.add_child(Look.box(Vector3(0.5, 0.46, 0.07) * k, st, Vector3(0, 1.38 * k, sx * 0.23 * k)))
	n.add_child(Look.cylinder(0.62 * k, 0.34 * k, dk, Vector3(0, 1.76 * k, 0), 0.0, 8))
	n.add_child(Look.sphere(0.09 * k, st, Vector3(0, 1.98 * k, 0)))
	return n


## A hanging paper lantern: ribbed glowing barrel with dark caps. `drop` is the cord above it.
func paper_lantern(pos: Vector3, r: float = 0.4, col: Color = LANTERN, drop: float = 0.0, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	_add(n, pos, parent)
	var body := Look.sphere(r, glow(col, 2.0))
	body.scale = Vector3(1.0, 1.25, 1.0)
	_no_shadow(body)
	n.add_child(body)
	n.add_child(Look.cylinder(r * 0.5, r * 0.18, mat(DARK_WOOD, 0.8), Vector3(0, r * 1.2, 0), -1.0, 10))
	n.add_child(Look.cylinder(r * 0.5, r * 0.18, mat(DARK_WOOD, 0.8), Vector3(0, -r * 1.2, 0), -1.0, 10))
	n.add_child(Look.sphere(r * 0.12, glow(col.lightened(0.3), 2.4), Vector3(0, -r * 1.55, 0)))
	if drop > 0.0:
		var c := Look.cylinder(0.015, drop, mat(DARK_WOOD, 0.9), Vector3(0, r * 1.3 + drop * 0.5, 0), -1.0, 4)
		n.add_child(c)
	return n


## A string of paper lanterns between two points (sagging), warm and a little pink here and there.
func lantern_string(a: Vector3, b: Vector3, count: int, sag: float = 0.9, r: float = 0.32) -> void:
	cord(a, b, sag)
	for i: int in count:
		var k: float = (float(i) + 0.5) / float(count)
		var p: Vector3 = a.lerp(b, k) - Vector3(0, sag * 4.0 * k * (1.0 - k), 0)
		var col: Color = LANTERN if i % 3 != 2 else PINK.lerp(LANTERN, 0.35)
		paper_lantern(p - Vector3(0, r * 1.3, 0), r, col)


## A lamp post for a bridge or path: dark post, a glowing lantern on a short arm.
func lamp_post(pos: Vector3, height: float = 2.6, col: Color = LANTERN) -> void:
	var n := Node3D.new()
	_add(n, pos)
	n.add_child(Look.cylinder(0.07, height, mat(DARK_WOOD, 0.8), Vector3(0, height * 0.5, 0), 0.06, 6))
	n.add_child(Look.box(Vector3(0.5, 0.06, 0.06), mat(DARK_WOOD, 0.8), Vector3(0.22, height - 0.1, 0)))
	paper_lantern(Vector3(0.44, height - 0.5, 0), 0.22, col, 0.0, n)


# ---- trees and plants ----------------------------------------------------------------------------

## A weeping willow: a leaning trunk, a cloud of pale canopy and curtains of trailing strands.
func willow(pos: Vector3, k: float = 1.0) -> Node3D:
	var t := Node3D.new()
	_add(t, pos)
	var bark: StandardMaterial3D = mat(Color(0.26, 0.2, 0.17), 0.95)
	var lean := Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7)) * k
	var top: Vector3 = Vector3(0, 3.6 * k, 0) + lean
	rod(Vector3.ZERO, top * 0.55, 0.3 * k, bark, t, 7)
	rod(top * 0.55, top, 0.22 * k, bark, t, 7)
	var leaf: StandardMaterial3D = mat(WILLOW, 0.9)
	var leaf_dark: StandardMaterial3D = mat(WILLOW.darkened(0.25), 0.9)
	for i: int in 5:
		var off := Vector3(rng.randf_range(-1.3, 1.3), rng.randf_range(-0.2, 0.7), rng.randf_range(-1.3, 1.3)) * k
		var s := Look.sphere(rng.randf_range(1.0, 1.6) * k, leaf if i % 2 == 0 else leaf_dark, top + off)
		s.scale = Vector3(1.0, 0.62, 1.0)
		t.add_child(s)
	# the strands: thin tapered cords hanging off a ring of branch tips
	var strand_m: StandardMaterial3D = mat(WILLOW.lightened(0.05), 0.9)
	for i: int in 22:
		var a: float = TAU * (float(i) + rng.randf()) / 22.0
		var rr: float = rng.randf_range(1.0, 2.1) * k
		var len: float = [2.6, 3.4, 4.2][i % 3] * k
		var s2 := Look.cylinder(0.06 * k, len, strand_m, top + Vector3(cos(a) * rr, -0.1 * k - len * 0.5, sin(a) * rr), 0.0, 4)
		_no_shadow(s2)
		t.add_child(s2)
	return t


## A maple in autumn red: a slim trunk and a cloud of red and orange.
func maple(pos: Vector3, k: float = 1.0) -> Node3D:
	var t := Node3D.new()
	_add(t, pos)
	t.add_child(Look.cylinder(0.2 * k, 2.4 * k, mat(Color(0.28, 0.2, 0.17), 0.95), Vector3(0, 1.2 * k, 0), 0.13 * k, 7))
	var cols: Array[Color] = [MAPLE, MAPLE.lerp(Color(1.0, 0.6, 0.2), 0.45), MAPLE.darkened(0.2)]
	for i: int in 5:
		var off := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.0, 0.9), rng.randf_range(-0.9, 0.9)) * k
		var c: Color = cols[i % 3]
		var m := Look.flat(c, 0.9, 0.0, 0.25)
		t.add_child(Look.sphere(rng.randf_range(0.8, 1.25) * k, m, Vector3(0, 2.7 * k, 0) + off))
	return t


## A garden pine (matsu): a twisting trunk and flat cloud-pads of needles.
func pine(pos: Vector3, k: float = 1.0) -> Node3D:
	var t := Node3D.new()
	_add(t, pos)
	var bark: StandardMaterial3D = mat(Color(0.22, 0.16, 0.14), 0.95)
	var needle: StandardMaterial3D = mat(Color(0.14, 0.32, 0.2), 0.9)
	var p0 := Vector3.ZERO
	var p1 := Vector3(rng.randf_range(-0.5, 0.5), 2.0 * k, rng.randf_range(-0.5, 0.5))
	var p2 := p1 + Vector3(rng.randf_range(-0.8, 0.8), 1.8 * k, rng.randf_range(-0.8, 0.8))
	rod(p0, p1, 0.24 * k, bark, t, 6)
	rod(p1, p2, 0.17 * k, bark, t, 6)
	for i: int in 3:
		var base: Vector3 = [p1 + Vector3(1.4, 0.2, 0.2) * k, p2 + Vector3(-1.1, -0.2, 0.3) * k, p2 + Vector3(0.1, 0.7, -0.2) * k][i]
		rod(p1.lerp(p2, 0.3 + 0.3 * float(i)), base, 0.07 * k, bark, t, 5)
		var pad := Look.cylinder(1.3 * k, 0.5 * k, needle, base + Vector3(0, 0.2 * k, 0), 0.9 * k, 10)
		t.add_child(pad)
	return t


## A clump of bamboo.
func bamboo(pos: Vector3, count: int, height: float, spread: float = 1.3) -> Node3D:
	var n := Node3D.new()
	_add(n, pos)
	var cane: StandardMaterial3D = mat(Color(0.42, 0.62, 0.3), 0.7)
	var cane2: StandardMaterial3D = mat(Color(0.5, 0.68, 0.34), 0.7)
	var knot: StandardMaterial3D = mat(Color(0.3, 0.45, 0.2), 0.8)
	for i: int in count:
		var o := Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		var h: float = height * rng.randf_range(0.75, 1.15)
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		rod(o, o + lean + Vector3(0, h, 0), 0.07, cane if i % 2 == 0 else cane2, n, 6)
		for j: int in int(h / 1.6):
			var kp: Vector3 = o + lean * (float(j + 1) * 1.6 / h) + Vector3(0, 1.6 * float(j + 1), 0)
			n.add_child(Look.cylinder(0.09, 0.06, knot, kp, -1.0, 6))
		n.add_child(Look.sphere(0.5, mat(Color(0.3, 0.55, 0.28), 0.9), o + lean + Vector3(0.1, h, 0.0)))
	return n


## Reeds and cattails in a cluster at the water's edge.
func reeds(pos: Vector3, count: int, spread: float = 1.0, height: float = 1.8) -> Node3D:
	var n := Node3D.new()
	_add(n, pos)
	var stem: StandardMaterial3D = mat(Color(0.34, 0.5, 0.26), 0.85)
	var head: StandardMaterial3D = mat(Color(0.36, 0.22, 0.14), 0.9)
	for i: int in count:
		var o := Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		var h: float = height * rng.randf_range(0.7, 1.2)
		var lean := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var tip: Vector3 = o + lean + Vector3(0, h, 0)
		rod(o, tip, 0.025, stem, n, 4)
		if i % 3 == 0:
			n.add_child(Look.cylinder(0.055, 0.34, head, tip - Vector3(0, 0.2, 0), -1.0, 6))
	return n


## A shared lotus-flower mesh: two rings of cupped petals and a seed pod (vertex-coloured).
static func flower_mesh(open: float) -> ArrayMesh:
	var key: int = int(round(open * 10.0))
	if _flower_meshes.has(key):
		return _flower_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[Dictionary] = [
		{"n": 9, "len": 0.62, "wid": 0.2, "tilt": lerpf(0.15, 1.15, open), "lift": 0.0, "tip": Color(1.0, 0.86, 0.92), "base": Color(0.95, 0.4, 0.62)},
		{"n": 7, "len": 0.54, "wid": 0.19, "tilt": lerpf(0.1, 0.8, open), "lift": 0.07, "tip": Color(1.0, 0.92, 0.96), "base": Color(1.0, 0.55, 0.72)},
		{"n": 5, "len": 0.44, "wid": 0.17, "tilt": lerpf(0.05, 0.45, open), "lift": 0.14, "tip": Color(1.0, 0.95, 0.97), "base": Color(1.0, 0.68, 0.8)},
	]
	for rd: Dictionary in rings:
		var n: int = int(rd["n"])
		for i: int in n:
			var a: float = TAU * float(i) / float(n) + float(rd["lift"]) * 9.0
			var dir := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-sin(a), 0, cos(a))
			var tilt: float = float(rd["tilt"])
			var len: float = float(rd["len"])
			var wid: float = float(rd["wid"])
			# petal outline: base, two shoulders, tip (a cupped diamond) in a few strips
			var pts: Array[Vector3] = []
			for s: int in 5:
				var u: float = float(s) / 4.0
				var w: float = wid * sin(PI * clampf(u * 0.9 + 0.08, 0.0, 1.0)) * (1.0 - 0.25 * u)
				var out: float = len * u * sin(tilt + 0.3) * 1.0
				var up: float = float(rd["lift"]) + len * u * cos(tilt + 0.3) * 0.9 - 0.12 * sin(u * PI) * 0.0
				var cup: float = 0.06 * sin(u * PI)
				pts.append(dir * out + Vector3(0, up, 0) + side * (-w) + dir * cup)
				pts.append(dir * out + Vector3(0, up, 0) + side * w + dir * cup)
			for s: int in 4:
				var a0: Vector3 = pts[s * 2]
				var a1: Vector3 = pts[s * 2 + 1]
				var b0: Vector3 = pts[s * 2 + 2]
				var b1: Vector3 = pts[s * 2 + 3]
				var c0: Color = (rd["base"] as Color).lerp(rd["tip"] as Color, float(s) / 4.0)
				var c1: Color = (rd["base"] as Color).lerp(rd["tip"] as Color, float(s + 1) / 4.0)
				for tri: Array in [[a0, a1, b0, c0, c0, c1], [a1, b1, b0, c0, c1, c1]]:
					st.set_color(tri[3])
					st.add_vertex(tri[0])
					st.set_color(tri[4])
					st.add_vertex(tri[1])
					st.set_color(tri[5])
					st.add_vertex(tri[2])
	# the seed pod: a small gold disc
	var pod_c := Color(1.0, 0.82, 0.3)
	for i: int in 8:
		var a0: float = TAU * float(i) / 8.0
		var a1: float = TAU * float(i + 1) / 8.0
		st.set_color(pod_c)
		st.add_vertex(Vector3(0, 0.16, 0))
		st.add_vertex(Vector3(cos(a1) * 0.1, 0.12, sin(a1) * 0.1))
		st.add_vertex(Vector3(cos(a0) * 0.1, 0.12, sin(a0) * 0.1))
	var m := st.commit()
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.roughness = 0.6
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.55, 0.7)
	fm.emission_energy_multiplier = 0.22
	m.surface_set_material(0, fm)
	_flower_meshes[key] = m
	return m


## A lotus flower on a stem rising from the water at `pos` (world).
func lotus_flower(pos: Vector3, scale: float = 1.0, open: float = 1.0, stem_h: float = 0.7) -> Node3D:
	var n := Node3D.new()
	_add(n, pos)
	if stem_h > 0.05:
		n.add_child(Look.cylinder(0.035 * scale, stem_h, mat(Color(0.3, 0.5, 0.28), 0.8), Vector3(0, stem_h * 0.5, 0), -1.0, 5))
	var f := MeshInstance3D.new()
	f.mesh = flower_mesh(open)
	f.scale = Vector3.ONE * scale
	f.position = Vector3(0, stem_h, 0)
	f.rotation.y = rng.randf() * TAU
	_no_shadow(f)
	n.add_child(f)
	return n


## A cluster of floating lily pads (decoration) on the water at `pos`, some with flowers.
func lily_cluster(pos: Vector3, count: int, spread: float, flowers: int = 1) -> void:
	for i: int in count:
		var r: float = rng.randf_range(0.5, 1.15)
		var p := Vector3(rng.randf_range(-spread, spread), 0.03, rng.randf_range(-spread, spread))
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.08
		cm.radial_segments = 18
		cm.rings = 1
		var mi := Look.mesh_node(cm, pad_material(r), p)
		mi.rotation.y = rng.randf() * TAU
		_no_shadow(mi)
		_add(mi, pos + p)
	for i: int in flowers:
		var p2 := Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		lotus_flower(pos + p2, rng.randf_range(0.8, 1.3), 1.0 if rng.randf() < 0.75 else 0.0, rng.randf_range(0.5, 0.9))


## A mossy boulder.
func rock(pos: Vector3, k: float = 1.0) -> Node3D:
	var n := Node3D.new()
	_add(n, pos)
	var body := Look.sphere(1.0, mat(STONE_DARK.lerp(STONE, rng.randf()), 0.95))
	body.scale = Vector3(rng.randf_range(0.9, 1.5), rng.randf_range(0.6, 0.9), rng.randf_range(0.9, 1.4)) * k
	body.rotation.y = rng.randf() * TAU
	n.add_child(body)
	var cap := Look.sphere(1.0, mat(MOSS, 0.95), Vector3(0, 0.38 * k, 0))
	cap.scale = Vector3(body.scale.x * 0.8, 0.34 * k, body.scale.z * 0.8)
	cap.rotation.y = body.rotation.y
	n.add_child(cap)
	return n


## A grassy bank / islet mound with a dark earth skirt (a big flattened sphere pair).
func mound(pos: Vector3, rx: float, h: float, rz: float, col: Color = Color(0.16, 0.34, 0.2)) -> Node3D:
	var n := Node3D.new()
	_add(n, pos)
	var earth := Look.sphere(1.0, mat(Color(0.2, 0.16, 0.16), 0.95))
	earth.scale = Vector3(rx, h * 1.1, rz)
	n.add_child(earth)
	var grass := Look.sphere(1.0, mat(col, 0.95), Vector3(0, h * 0.18, 0))
	grass.scale = Vector3(rx * 0.97, h * 0.9, rz * 0.97)
	n.add_child(grass)
	return n


# ---- structures --------------------------------------------------------------------------------

## A moon gate: a great stone ring standing in a low wall (the way in). `r` is the ring's radius.
func moon_gate(pos: Vector3, r: float, yaw: float = 0.0, wall_len: float = 7.0) -> Node3D:
	var n := Node3D.new()
	n.rotation.y = yaw
	_add(n, pos)
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.9
	tm.outer_radius = r
	tm.rings = 40
	tm.ring_segments = 10
	var ring := Look.mesh_node(tm, mat(STONE, 0.85), Vector3(0, r, 0))
	ring.rotation.x = PI * 0.5
	ring.scale = Vector3(1.0, 1.0, 1.0)
	n.add_child(ring)
	# the wall either side, stepping down, with tiled caps
	for sx: float in [-1.0, 1.0]:
		var wx: float = sx * (r + wall_len * 0.5)
		n.add_child(Look.box(Vector3(wall_len, r * 1.1, 0.7), mat(Color(0.82, 0.8, 0.78), 0.9), Vector3(wx, r * 0.55, 0)))
		n.add_child(Look.box(Vector3(wall_len + 0.3, 0.16, 1.0), mat(TILE, 0.55, 0.15), Vector3(wx, r * 1.1 + 0.08, 0)))
	n.add_child(Look.box(Vector3(2.0 * r * 0.2, r * 0.45, 0.7), mat(Color(0.82, 0.8, 0.78), 0.9), Vector3(0, r * 2.0 - 0.1, 0)))
	n.add_child(Look.sphere(0.2, glow(GOLD, 2.2), Vector3(0, r * 2.0 + 0.35, 0)))
	return n


## A garden pavilion on stilts: four posts, a floor, a hip roof of dark tile, lanterns at the eaves.
func pavilion(pos: Vector3, w: float, d: float, yaw: float = 0.0, stilt: float = 2.0) -> Node3D:
	var n := Node3D.new()
	n.rotation.y = yaw
	_add(n, pos)
	var wood: StandardMaterial3D = mat(WOOD, 0.8)
	var dark: StandardMaterial3D = mat(DARK_WOOD, 0.8)
	var h: float = 3.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			n.add_child(Look.cylinder(0.14, h + stilt, dark, Vector3(sx * w * 0.45, (h - stilt) * 0.5, sz * d * 0.45), -1.0, 6))
	n.add_child(Look.box(Vector3(w, 0.2, d), wood, Vector3(0, -0.1, 0)))
	n.add_child(Look.box(Vector3(w + 0.4, 0.14, d + 0.4), dark, Vector3(0, h, 0)))
	var roof_c := Look.cylinder(0.7071, 1.5, mat(TILE, 0.5, 0.15), Vector3(0, h + 0.75, 0), 0.06, 4)
	roof_c.rotation.y = PI * 0.25
	roof_c.scale = Vector3(w + 1.2, 1.0, d + 1.2)
	n.add_child(roof_c)
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			paper_lantern(Vector3(sx2 * (w * 0.5 + 0.4), h - 0.65, sz2 * (d * 0.5 + 0.4)), 0.28, LANTERN, 0.4, n)
	return n


## A far pagoda silhouette of stacked tiers with a few lit windows.
func pagoda(pos: Vector3, tiers: int, k: float = 1.0, yaw: float = 0.0, lit: bool = true) -> Node3D:
	var n := Node3D.new()
	n.rotation.y = yaw
	_add(n, pos)
	var wall: StandardMaterial3D = mat(Color(0.34, 0.26, 0.3), 0.9)
	var roof: StandardMaterial3D = mat(TILE, 0.6, 0.1)
	var y: float = 0.0
	for i: int in tiers:
		var s: float = (1.0 - 0.14 * float(i)) * k
		n.add_child(Look.box(Vector3(3.6, 2.2, 3.6) * s, wall, Vector3(0, y + 1.1 * s, 0)))
		if lit:
			n.add_child(Look.box(Vector3(1.2, 0.9, 3.7) * s, glow(LANTERN, 1.4), Vector3(0, y + 1.2 * s, 0)))
			n.add_child(Look.box(Vector3(3.7, 0.9, 1.2) * s, glow(LANTERN, 1.4), Vector3(0, y + 1.2 * s, 0)))
		var rc := Look.cylinder(0.7071 * 6.2 * s, 1.1 * s, roof, Vector3(0, y + 2.75 * s, 0), 0.7071 * 1.6 * s, 4)
		rc.rotation.y = PI * 0.25
		n.add_child(rc)
		y += 2.6 * s
	n.add_child(Look.cylinder(0.08 * k, 3.0 * k, mat(Color(0.7, 0.55, 0.3), 0.4, 0.6), Vector3(0, y + 1.4 * k, 0), 0.04 * k, 6))
	return n


## Railings along both sides of a straight deck from `a` to `b` (the deck's top surface points):
## posts every ~2.2 m, a top rail, a glowing lantern on every third post.
func bridge_rails(a: Vector3, b: Vector3, half_width: float, lanterns: bool = true) -> void:
	var d: Vector3 = b - a
	var len: float = d.length()
	if len < 1.0:
		return
	var dir: Vector3 = d / len
	var side: Vector3 = Vector3(-dir.z, 0, dir.x)
	if side.length() < 0.01:
		return
	side = side.normalized()
	var post_m: StandardMaterial3D = mat(DARK_WOOD, 0.8)
	var rail_m: StandardMaterial3D = mat(WOOD.lightened(0.05), 0.75)
	var n: int = maxi(int(len / 2.2), 1)
	for s: float in [-1.0, 1.0]:
		var prev: Vector3 = Vector3.ZERO
		for i: int in n + 1:
			var p: Vector3 = a + d * (float(i) / float(n)) + side * (half_width * s) + Vector3(0, 0.9, 0)
			var post := Look.cylinder(0.07, 0.9, post_m, p - Vector3(0, 0.45, 0), -1.0, 6)
			_no_shadow(post)
			_add(post, post.position)
			if i > 0:
				rod(prev, p, 0.05, rail_m, null, 5)
			prev = p
			if lanterns and i % 3 == 0:
				paper_lantern(p + Vector3(0, 0.28, 0), 0.17, LANTERN)


# ---- water features ------------------------------------------------------------------------------

## A ribbon of moving water along a polyline (world points, head first). UV.y runs downstream.
## `lift` raises it off the surface it dresses. Returns the mesh instance.
func stream_ribbon(points: PackedVector3Array, width: float, speed: float = 7.0, lift: float = 0.07, fall: float = 0.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = points.size()
	var total: float = 0.0
	var dists := PackedFloat32Array()
	dists.append(0.0)
	for i: int in range(1, n):
		total += points[i].distance_to(points[i - 1])
		dists.append(total)
	var lefts := PackedVector3Array()
	var rights := PackedVector3Array()
	for i: int in n:
		var t: Vector3
		if i == 0:
			t = points[1] - points[0]
		elif i == n - 1:
			t = points[n - 1] - points[n - 2]
		else:
			t = points[i + 1] - points[i - 1]
		var flat := Vector3(t.x, 0, t.z)
		if flat.length() < 0.001:
			flat = Vector3(0, 0, -1)
		flat = flat.normalized()
		var side := Vector3(-flat.z, 0, flat.x)
		var up := Vector3(0, lift, 0)
		lefts.append(points[i] - side * width * 0.5 + up)
		rights.append(points[i] + side * width * 0.5 + up)
	for i: int in n - 1:
		var v0: float = dists[i] / maxf(total, 0.001)
		var v1: float = dists[i + 1] / maxf(total, 0.001)
		var tris: Array = [
			[lefts[i], Vector2(0, v0)], [rights[i], Vector2(1, v0)], [lefts[i + 1], Vector2(0, v1)],
			[rights[i], Vector2(1, v0)], [rights[i + 1], Vector2(1, v1)], [lefts[i + 1], Vector2(0, v1)],
		]
		for e: Array in tris:
			st.set_normal(Vector3.UP)
			st.set_uv(e[1])
			st.add_vertex(e[0])
	var mesh := st.commit()
	var sm := ShaderMaterial.new()
	sm.shader = STREAM_SHADER
	sm.set_shader_parameter("speed", speed)
	sm.set_shader_parameter("length_m", maxf(total, 1.0))
	sm.set_shader_parameter("width_m", width)
	sm.set_shader_parameter("fall", fall)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


## A waterfall curtain: top = centre of the lip, hanging `height` m, `width` wide, facing yaw
## (the water falls toward local -Z... it hangs flat in the plane of the node, front along +Z).
func waterfall(top: Vector3, width: float, height: float, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.rotation.y = yaw
	_add(n, top)
	var sm := ShaderMaterial.new()
	sm.shader = STREAM_SHADER
	sm.set_shader_parameter("speed", 9.0)
	sm.set_shader_parameter("length_m", height)
	sm.set_shader_parameter("width_m", width)
	sm.set_shader_parameter("fall", 1.0)
	sm.set_shader_parameter("alpha", 0.85)
	# a vertical quad whose UV.y runs from the lip down
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = width * 0.5
	var corners: Array = [
		[Vector3(-hw, 0, 0), Vector2(0, 0)], [Vector3(hw, 0, 0), Vector2(1, 0)], [Vector3(-hw, -height, 0.6), Vector2(0, 1)],
		[Vector3(hw, 0, 0), Vector2(1, 0)], [Vector3(hw, -height, 0.6), Vector2(1, 1)], [Vector3(-hw, -height, 0.6), Vector2(0, 1)],
	]
	for e: Array in corners:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(e[1])
		st.add_vertex(e[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	# the dark lip stones either side
	for sx: float in [-1.0, 1.0]:
		var r: Node3D = rock(top, 0.8)
		root.remove_child(r)
		n.add_child(r)
		r.position = Vector3(sx * (hw + 0.5), -0.3, -0.2)
	return n
