class_name FungalDecor
extends RefCounted
## Mushroom Hollow's set dressing: a sunny forest floor at beetle size. Spotted toadstools with
## ruffled gills, daisies tall as trees, towering grass and fern fronds, fallen logs and stumps,
## acorns, mossy boulders, ladybirds and butterflies, giant tree trunks on the skyline, shafts of
## golden light, a stream, and the GREAT TOADSTOOL. All visual (no collision), built from shared Look
## meshes and a handful of materials. Pieces take a world position, and a yaw / basis where it
## matters.

const CREAM := Color(0.97, 0.92, 0.8)
const RED := Color(0.9, 0.22, 0.18)
const ORANGE := Color(0.96, 0.6, 0.22)
const GOLD := Color(1.0, 0.82, 0.3)
const LEAF := Color(0.36, 0.62, 0.22)
const LEAF_LIGHT := Color(0.55, 0.78, 0.3)
const BARK := Color(0.42, 0.29, 0.18)
const MOSS := Color(0.38, 0.6, 0.24)
const STONE := Color(0.6, 0.58, 0.52)

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


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


func _glow(col: Color, e: float = 1.4) -> StandardMaterial3D:
	return Look.flat(col, 0.4, 0.0, e)


# ---- mushrooms -------------------------------------------------------------------------------------

## A spotted toadstool: tapered cream stem, ruffled gills, a domed cap with cream spots.
## `pos` = the foot of the stem. `lean` tilts the whole thing (radians, round X).
func toadstool(pos: Vector3, h: float, r: float, col: Color = RED, spots: bool = true, lean: float = 0.0) -> Node3D:
	var n: Node3D = _node(pos, turn(rng.randf() * TAU, lean, 0.0))
	var stem: StandardMaterial3D = Look.flat(CREAM, 0.85)
	_put(n, Look.cylinder(r * 0.34, h, stem, Vector3(0, h * 0.5, 0), r * 0.22, 14))
	# the skirt ring on the stem
	_put(n, Look.cylinder(r * 0.42, 0.08 * maxf(r, 1.0), Look.flat(CREAM.darkened(0.06), 0.8), Vector3(0, h * 0.62, 0), r * 0.3, 14))
	var cap_mat: StandardMaterial3D = Look.flat(col, 0.55)
	var dome := Look.sphere(r, cap_mat, Vector3(0, h, 0))
	dome.scale = Vector3(1.0, 0.55, 1.0)
	_put(n, dome)
	_put(n, Look.cylinder(r * 0.98, 0.06 * maxf(r, 1.0), Look.flat(Color(0.93, 0.82, 0.6), 0.9), Vector3(0, h - 0.02, 0), r * 0.4, 20))
	if spots:
		var spot: StandardMaterial3D = Look.flat(Color(1.0, 0.96, 0.88), 0.6)
		var k: int = 7
		for i: int in k:
			var a: float = TAU * float(i) / float(k) + rng.randf() * 0.5
			var e: float = rng.randf_range(0.25, 1.2)
			var sp := Look.sphere(r * rng.randf_range(0.1, 0.17), spot,
				Vector3(cos(a) * cos(e) * r * 0.97, h + sin(e) * r * 0.55 * 0.97, sin(a) * cos(e) * r * 0.97))
			sp.scale = Vector3(1.0, 0.4, 1.0)
			_put(n, sp)
	return n


## A small cluster of toadstools of mixed sizes (a patch of the forest floor).
func patch(pos: Vector3, count: int, spread: float, size: float = 1.0) -> void:
	for i: int in count:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.0, spread)
		var h: float = rng.randf_range(0.8, 1.6) * size
		var col: Color = [RED, RED, ORANGE, Color(0.85, 0.5, 0.65), Color(0.9, 0.75, 0.35)][rng.randi() % 5]
		toadstool(pos + Vector3(cos(a) * d, 0, sin(a) * d), h, rng.randf_range(0.45, 0.8) * size, col, true, rng.randf_range(-0.15, 0.15))


## A fairy ring: toadstools in a circle on the grass (`pos` = centre).
func fairy_ring(pos: Vector3, radius: float, n: int = 14) -> void:
	for i: int in n:
		var a: float = TAU * float(i) / float(n) + 0.2
		toadstool(pos + Vector3(cos(a), 0, sin(a)) * radius, rng.randf_range(0.55, 0.9), rng.randf_range(0.28, 0.42), Color(0.97, 0.92, 0.84), false, 0.0)


## A bracket (shelf) fungus stuck to something: a half disc of layered bands. `pos` = its top edge.
func bracket(pos: Vector3, r: float, yaw: float, col: Color = ORANGE) -> void:
	var n: Node3D = _node(pos, turn(yaw))
	for i: int in 3:
		var k: float = 1.0 - 0.28 * float(i)
		_put(n, Look.cylinder(r * k, 0.1, Look.flat(col.lerp(CREAM, 0.25 * float(i)), 0.7), Vector3(0, -0.1 * float(i), -r * k * 0.5), r * k * 0.95, 16))


# ---- plants ---------------------------------------------------------------------------------------------

## A daisy as tall as a tree: a green stem, two leaves, a head of white petals round a gold heart.
## `pos` = the foot of the stem, `h` its height, `s` the head's radius.
func daisy(pos: Vector3, h: float, s: float, facing: float = 0.0, col: Color = Color(0.99, 0.98, 0.94)) -> Node3D:
	var n: Node3D = _node(pos)
	var stem: StandardMaterial3D = Look.flat(Color(0.36, 0.6, 0.24), 0.8)
	_put(n, Look.cylinder(maxf(s * 0.07, 0.06), h, stem, Vector3(0, h * 0.5, 0), maxf(s * 0.05, 0.05), 10))
	var lf := Look.sphere(1.0, Look.flat(LEAF, 0.7), Vector3(s * 0.7, h * 0.3, 0))
	lf.scale = Vector3(s * 0.8, 0.05 * s + 0.04, s * 0.28)
	lf.rotation.z = 0.5
	_put(n, lf)
	var head := Node3D.new()
	head.position = Vector3(0, h, 0)
	head.rotation = Vector3(-0.9, facing, 0)
	n.add_child(head)
	var petal: StandardMaterial3D = Look.flat(col, 0.7)
	var k: int = 14
	for i: int in k:
		var a: float = TAU * float(i) / float(k)
		var p := Look.sphere(1.0, petal, Vector3(cos(a), 0.0, sin(a)) * s * 0.62)
		p.scale = Vector3(s * 0.4, s * 0.06 + 0.02, s * 0.14)
		p.rotation.y = -a
		_put(head, p)
	var heart := Look.sphere(s * 0.26, Look.flat(GOLD, 0.6, 0.0, 0.25), Vector3(0, s * 0.05, 0))
	heart.scale = Vector3(1.0, 0.6, 1.0)
	_put(head, heart)
	var sw := FungalSway.new()
	sw.mode = "sway"
	sw.amount = 0.025
	sw.speed = rng.randf_range(0.6, 1.0)
	sw.offset = rng.randf() * 6.0
	n.add_child(sw)
	return n


## A harebell: a thin curved stem and a hanging blue bell.
func harebell(pos: Vector3, h: float, col: Color = Color(0.5, 0.58, 0.95)) -> void:
	var n: Node3D = _node(pos, turn(rng.randf() * TAU))
	_put(n, Look.cylinder(0.05 * h * 0.2 + 0.03, h, Look.flat(Color(0.4, 0.62, 0.28), 0.8), Vector3(0, h * 0.5, 0), 0.03, 8))
	var bell := Look.cylinder(0.04 * h, 0.5 * h * 0.18 + 0.1, Look.flat(col, 0.5, 0.0, 0.2), Vector3(0.2 * h * 0.25, h - 0.1, 0), 0.22 * h * 0.3 + 0.06, 12)
	bell.rotation.z = 0.3
	_put(n, bell)


## A tuft of grass blades: thin cones leaning out, swaying.
func blades(pos: Vector3, count: int, h: float, spread: float = 0.6) -> Node3D:
	var n: Node3D = _node(pos)
	var mats: Array[StandardMaterial3D] = [Look.flat(Color(0.42, 0.68, 0.24), 0.8), Look.flat(Color(0.34, 0.58, 0.2), 0.8), Look.flat(Color(0.56, 0.76, 0.3), 0.8)]
	for i: int in count:
		var hh: float = h * rng.randf_range(0.6, 1.0)
		var a: float = rng.randf() * TAU
		var blade := Look.cylinder(h * 0.035 + 0.02, hh, mats[i % 3], Vector3(0, hh * 0.5, 0), 0.0, 5)
		var pivot := Node3D.new()
		pivot.position = Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, spread)
		pivot.rotation = Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		pivot.add_child(blade)
		n.add_child(pivot)
	var sw := FungalSway.new()
	sw.mode = "sway"
	sw.amount = 0.04
	sw.speed = rng.randf_range(0.7, 1.2)
	sw.offset = rng.randf() * 6.0
	n.add_child(sw)
	return n


## A broad leaf: a flat ellipse with a pale midrib, tilted. `pos` = the stalk end.
func leaf(pos: Vector3, length: float, width: float, yaw: float, tilt: float = 0.3, col: Color = LEAF) -> Node3D:
	var n: Node3D = _node(pos, turn(yaw, -tilt))
	var blade := Look.sphere(1.0, Look.flat(col, 0.7), Vector3(0, 0, -length * 0.5))
	blade.scale = Vector3(width * 0.5, 0.05 + width * 0.02, length * 0.5)
	_put(n, blade)
	_put(n, Look.box(Vector3(0.06, 0.04, length * 0.95), Look.flat(col.lightened(0.28), 0.7), Vector3(0, 0.06 + width * 0.02, -length * 0.5)), true)
	return n


## A fern: fronds fanning out from a crown.
func fern(pos: Vector3, s: float, yaw: float = 0.0) -> Node3D:
	var n: Node3D = _node(pos, turn(yaw))
	var fronds: int = 8
	for i: int in fronds:
		var a: float = TAU * float(i) / float(fronds) + rng.randf() * 0.3
		var fr := Node3D.new()
		fr.rotation = Vector3(-rng.randf_range(0.7, 1.1), a, 0)
		n.add_child(fr)
		var flen: float = rng.randf_range(2.2, 3.4) * s
		var spine := Look.cylinder(0.03 * s + 0.02, flen, Look.flat(Color(0.3, 0.52, 0.2), 0.8), Vector3(0, 0, 0), 0.01, 5)
		spine.rotation.x = PI * 0.5
		spine.position = Vector3(0, 0, -flen * 0.5)
		fr.add_child(spine)
		for j: int in 6:
			var z: float = -flen * (0.2 + 0.14 * float(j))
			var w: float = (0.62 - 0.07 * float(j)) * s
			for sx: float in [-1.0, 1.0]:
				var lf := Look.sphere(1.0, Look.flat(LEAF.lightened(0.04 * float(j)), 0.75), Vector3(sx * w * 0.5, 0, z))
				lf.scale = Vector3(w * 0.5, 0.025 * s + 0.01, 0.16 * s)
				lf.rotation.y = sx * 0.5
				fr.add_child(lf)
	var sw := FungalSway.new()
	sw.mode = "sway"
	sw.amount = 0.03
	sw.speed = rng.randf_range(0.6, 1.0)
	sw.offset = rng.randf() * 6.0
	n.add_child(sw)
	return n


# ---- wood and stone ---------------------------------------------------------------------------------------

## A fallen log along its yaw: bark cylinder, pale rings at the ends, moss on top, shelf fungi.
func fallen_log(pos: Vector3, length: float, r: float, yaw: float = 0.0, hollow: bool = false) -> Node3D:
	var n: Node3D = _node(pos, turn(yaw))
	var bark: StandardMaterial3D = Look.flat(BARK, 0.95)
	var body := Look.cylinder(r, length, bark, Vector3(0, r, 0), r * 0.97, 18)
	body.rotation.z = PI * 0.5
	_put(n, body)
	for sx: float in [-1.0, 1.0]:
		var end := Look.cylinder(r * 0.94, 0.06, Look.flat(Color(0.78, 0.6, 0.38) if not hollow else Color(0.16, 0.1, 0.06), 0.85), Vector3(sx * (length * 0.5 + 0.02), r, 0), -1.0, 18)
		end.rotation.z = PI * 0.5
		_put(n, end)
		if not hollow:
			var tm := TorusMesh.new()
			tm.inner_radius = r * 0.5
			tm.outer_radius = r * 0.55
			tm.rings = 20
			tm.ring_segments = 4
			var rn := Look.mesh_node(tm, Look.flat(Color(0.6, 0.42, 0.24), 0.9), Vector3(sx * (length * 0.5 + 0.06), r, 0))
			rn.rotation.z = PI * 0.5
			rn.scale = Vector3(1, 0.5, 1)
			_put(n, rn, true)
	for i: int in 4:
		var m := Look.sphere(1.0, Look.flat(MOSS, 0.9), Vector3(rng.randf_range(-0.4, 0.4) * length, r * 1.9 - 0.05, rng.randf_range(-0.3, 0.3) * r))
		m.scale = Vector3(rng.randf_range(0.8, 1.8), 0.22, rng.randf_range(0.5, 0.9) * r * 0.5)
		_put(n, m)
	for i2: int in 2:
		bracket(pos + turn(yaw) * Vector3(rng.randf_range(-0.35, 0.35) * length, r * 1.2, r * 0.95), r * 0.5, yaw + PI * 0.5 + rng.randf_range(-0.3, 0.3))
	return n


## A cut stump: bark sides, a pale top with growth rings, moss at the foot. `pos` = its foot.
func stump(pos: Vector3, r: float, h: float) -> void:
	var n: Node3D = _node(pos, turn(rng.randf() * TAU))
	_put(n, Look.cylinder(r * 1.1, h, Look.flat(BARK, 0.95), Vector3(0, h * 0.5, 0), r, 18))
	_put(n, Look.cylinder(r * 0.98, 0.05, Look.flat(Color(0.8, 0.62, 0.4), 0.85), Vector3(0, h + 0.01, 0), -1.0, 18))
	for k: float in [0.3, 0.55, 0.78]:
		var tm := TorusMesh.new()
		tm.inner_radius = r * k - 0.03
		tm.outer_radius = r * k + 0.03
		tm.rings = 24
		tm.ring_segments = 4
		var rn := Look.mesh_node(tm, Look.flat(Color(0.58, 0.4, 0.22), 0.9), Vector3(0, h + 0.05, 0))
		rn.scale = Vector3(1, 0.2, 1)
		_put(n, rn, true)
	var m := Look.sphere(r * 0.5, Look.flat(MOSS, 0.9), Vector3(r * 0.9, 0.1, 0))
	m.scale = Vector3(1.0, 0.45, 1.0)
	_put(n, m)


## A mossy boulder: a few lumpy spheres with a cap of moss.
func rock(pos: Vector3, s: float, yaw: float = 0.0) -> void:
	var n: Node3D = _node(pos, turn(yaw))
	var stone: StandardMaterial3D = Look.flat(STONE.darkened(rng.randf_range(0.0, 0.2)), 0.95)
	for i: int in 3:
		var b := Look.sphere(1.0, stone, Vector3(rng.randf_range(-0.5, 0.5), 0.3, rng.randf_range(-0.5, 0.5)) * s)
		b.scale = Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.6, 0.9), rng.randf_range(0.8, 1.2)) * s
		_put(n, b)
	var cap := Look.sphere(1.0, Look.flat(MOSS, 0.9), Vector3(0, 0.75 * s, 0))
	cap.scale = Vector3(0.8, 0.25, 0.75) * s
	_put(n, cap)


## An acorn: a glossy brown nut in a scaly cap. `pos` = its centre; `s` ~ radius.
func acorn(pos: Vector3, s: float, tilt: float = 0.0) -> Node3D:
	var n: Node3D = _node(pos, turn(0.0, 0.0, tilt))
	var nut := Look.sphere(s, Look.flat(Color(0.72, 0.5, 0.24), 0.35), Vector3(0, -s * 0.25, 0))
	nut.scale = Vector3(0.85, 1.15, 0.85)
	_put(n, nut)
	var cap := Look.sphere(s * 0.98, Look.flat(Color(0.5, 0.36, 0.2), 0.85), Vector3(0, s * 0.45, 0))
	cap.scale = Vector3(1.0, 0.6, 1.0)
	_put(n, cap)
	_put(n, Look.cylinder(s * 0.1, s * 0.4, Look.flat(Color(0.4, 0.3, 0.16), 0.85), Vector3(0, s * 0.95, 0), s * 0.08, 6))
	return n


## A ladybird: red shell with black spots, a dark head, little legs. `pos` = its feet.
func ladybird(pos: Vector3, s: float, yaw: float = 0.0, bob: bool = true) -> Node3D:
	var n: Node3D = _node(pos, turn(yaw))
	var shell := Look.sphere(s, Look.flat(Color(0.9, 0.16, 0.12), 0.25), Vector3(0, s * 0.55, 0))
	shell.scale = Vector3(1.0, 0.7, 1.25)
	_put(n, shell)
	var ink: StandardMaterial3D = Look.flat(Color(0.09, 0.08, 0.1), 0.4)
	_put(n, Look.box(Vector3(0.03 * s, 0.02 * s, 2.4 * s), ink, Vector3(0, s * 1.2, 0)), true)
	for p: Vector3 in [Vector3(-0.5, 0.95, -0.4), Vector3(0.5, 0.95, -0.4), Vector3(-0.55, 0.85, 0.35), Vector3(0.55, 0.85, 0.35), Vector3(0.0, 1.1, 0.7)]:
		var sp := Look.sphere(0.17 * s, ink, Vector3(p.x, p.y * 0.72 + 0.1, p.z) * s)
		sp.scale = Vector3(1.0, 0.5, 1.0)
		_put(n, sp)
	_put(n, Look.sphere(0.42 * s, ink, Vector3(0, s * 0.5, -s * 1.15)))
	for i: int in 3:
		for sx: float in [-1.0, 1.0]:
			var leg := Look.cylinder(0.03 * s, 0.7 * s, ink, Vector3(sx * s * 0.75, s * 0.2, (float(i) - 1.0) * s * 0.55), 0.02 * s, 5)
			leg.rotation.z = sx * 0.9
			_put(n, leg)
	if bob:
		var sw := FungalSway.new()
		sw.mode = "bob"
		sw.amount = 0.05 * s
		sw.speed = 1.4
		sw.offset = rng.randf() * 6.0
		n.add_child(sw)
	return n


## A butterfly circling a point: two coloured wings beating, a dark body.
func butterfly(pos: Vector3, s: float, col: Color, circle: float = 3.0) -> Node3D:
	var n: Node3D = _node(pos)
	n.add_child(Look.cylinder(0.04 * s, 0.5 * s, Look.flat(Color(0.2, 0.15, 0.1), 0.6), Vector3.ZERO, 0.03 * s, 5))
	(n.get_child(0) as Node3D).rotation.x = PI * 0.5
	var wm: StandardMaterial3D = Look.flat(col, 0.5, 0.0, 0.25)
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i: int in 2:
		var w := Node3D.new()
		w.name = "Wing%d" % i
		var sx: float = 1.0 if i == 0 else -1.0
		var wing := Look.sphere(1.0, wm, Vector3(sx * 0.4 * s, 0.0, 0.0))
		wing.scale = Vector3(0.45 * s, 0.015 * s + 0.005, 0.38 * s)
		w.add_child(wing)
		n.add_child(w)
	var sw := FungalSway.new()
	sw.mode = "flap"
	sw.radius = circle
	sw.speed = rng.randf_range(0.8, 1.3)
	sw.offset = rng.randf() * 6.0
	n.add_child(sw)
	return n


# ---- supports and giants -------------------------------------------------------------------------------------

## A support under a platform, down to the forest floor: kind 0 = a pale toadstool stem with a
## ruffled skirt, 1 = a green stalk with a leaf, 2 = a bark-brown branch stub. `top` is the point
## under the platform's middle, `length` how far down it goes.
func support(top: Vector3, r: float, length: float, kind: int = 0) -> void:
	var n: Node3D = _node(top)
	if length < 0.5:
		return
	match kind:
		0:
			_put(n, Look.cylinder(r * 0.8, length, Look.flat(CREAM, 0.85), Vector3(0, -length * 0.5, 0), r * 0.5, 14))
			_put(n, Look.cylinder(r * 1.3, 0.12, Look.flat(CREAM.darkened(0.08), 0.85), Vector3(0, -0.5 - 0.0, 0), r * 0.85, 14))
			_put(n, Look.cylinder(r * 1.1, 0.4, Look.flat(Color(0.93, 0.82, 0.6), 0.9), Vector3(0, -0.15, 0), r * 0.7, 14))
		1:
			_put(n, Look.cylinder(r * 0.6, length, Look.flat(Color(0.36, 0.6, 0.24), 0.8), Vector3(0, -length * 0.5, 0), r * 0.5, 10))
			var lf := Look.sphere(1.0, Look.flat(LEAF, 0.7), Vector3(r * 3.0, -length * 0.35, 0))
			lf.scale = Vector3(r * 3.2, 0.06, r * 1.0)
			lf.rotation.z = 0.4
			_put(n, lf)
		_:
			_put(n, Look.cylinder(r * 0.95, length, Look.flat(BARK, 0.95), Vector3(0, -length * 0.5, 0), r * 0.65, 12))
			_put(n, Look.sphere(r * 0.9, Look.flat(MOSS, 0.9), Vector3(r * 0.4, -0.3, 0)))


## A giant tree trunk on the skyline (bark, buttress roots, moss band). `pos` = its foot.
func trunk(pos: Vector3, r: float, h: float) -> void:
	var n: Node3D = _node(pos, turn(rng.randf() * TAU))
	var bark: StandardMaterial3D = Look.flat(BARK.darkened(0.15), 0.95)
	_put(n, Look.cylinder(r, h, bark, Vector3(0, h * 0.5, 0), r * 0.82, 18))
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0 + 0.3
		var root_n := Look.cylinder(r * 0.34, r * 1.6, bark, Vector3(cos(a), 0.0, sin(a)) * r * 0.95 + Vector3(0, r * 0.4, 0), r * 0.04, 8)
		root_n.rotation = Vector3(sin(a) * 1.0, 0, -cos(a) * 1.0)
		_put(n, root_n)
	var mm := Look.cylinder(r * 1.02, h * 0.18, Look.flat(MOSS.darkened(0.1), 0.95), Vector3(0, h * 0.09, 0), r * 0.98, 18)
	_put(n, mm)
	# a couple of bracket fungi stuck to the trunk
	for i2: int in 3:
		var a2: float = rng.randf() * TAU
		bracket(pos + Vector3(cos(a2), 0, sin(a2)) * r * 0.98 + Vector3(0, rng.randf_range(0.2, 0.6) * h, 0), r * 0.35, -a2 + PI * 0.5, ORANGE)


## A far hill of moss: a squashed sphere half sunk into the floor.
func hill(pos: Vector3, r: float, h: float) -> void:
	var m := Look.sphere(1.0, Look.flat(Color(0.34, 0.54, 0.2).lerp(Color(0.74, 0.84, 0.6), 0.25), 0.95), pos)
	m.scale = Vector3(r, h, r)
	root.add_child(m)


## A shaft of golden light slanting down through the leaves (a tall open cylinder). `top` is its upper end.
func ray(top: Vector3, length: float, r: float, yaw: float = 0.0, lean: float = 0.35, strength: float = 0.2) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.6
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 16
	cm.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://visual/fungal_ray.gdshader")
	mat.set_shader_parameter("strength", strength)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b: Basis = turn(yaw, 0.0, lean)
	mi.transform = Transform3D(b, top - b * Vector3(0, length * 0.5, 0))
	root.add_child(mi)


## The forest floor: one huge mossy plane far below the course.
func ground(y: float, center: Vector3 = Vector3.ZERO) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(3200, 3200)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://visual/fungal_ground.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(center.x, y, center.z)
	root.add_child(mi)


## A ribbon of stream (flows along its yaw), `flen` long and `wid` wide, at height y.
func stream(pos: Vector3, flen: float, wid: float, yaw: float = 0.0) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(flen, wid)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://visual/fungal_water.gdshader")
	mat.set_shader_parameter("tiles", maxf(flen / 8.0, 4.0))
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(turn(yaw), pos)
	root.add_child(mi)


## A round pond (a disc of stream) with a few lily pads floating on it.
func pond(pos: Vector3, r: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.2
	cm.radial_segments = 36
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://visual/fungal_water.gdshader")
	mat.set_shader_parameter("tiles", maxf(r / 4.0, 4.0))
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	root.add_child(mi)


## A lily pad lying on water: a round green disc with a notch and a pink flower sometimes. Visual.
func lily(pos: Vector3, r: float, flower: bool = false) -> void:
	var n: Node3D = _node(pos, turn(rng.randf() * TAU))
	_put(n, Look.cylinder(r, 0.08, Look.flat(Color(0.3, 0.58, 0.22), 0.6), Vector3.ZERO, r * 0.98, 24))
	_put(n, Look.box(Vector3(r * 0.5, 0.09, r * 0.12), Look.flat(Color(0.6, 0.85, 0.95), 0.4), Vector3(0, 0.0, -r * 0.5)), true)
	if flower:
		for i: int in 8:
			var a: float = TAU * float(i) / 8.0
			var p := Look.sphere(1.0, Look.flat(Color(1.0, 0.7, 0.82), 0.5, 0.0, 0.15), Vector3(cos(a), 0.25, sin(a)) * r * 0.22)
			p.scale = Vector3(r * 0.2, r * 0.07, r * 0.09)
			p.rotation.y = -a
			_put(n, p)
		_put(n, Look.sphere(r * 0.1, Look.flat(GOLD, 0.5, 0.0, 0.5), Vector3(0, 0.15, 0)))


# ---- the great toadstool ----------------------------------------------------------------------------------------

## THE GREAT TOADSTOOL: a vast stalk with a hanging skirt (annulus), a huge domed cap of red with
## cream spots, and gills fanning underneath. `pos` = the foot of the stalk. The spiral of gill
## ledges the course climbs is built by the level around the stalk.
func great_toadstool(pos: Vector3, stalk_r: float, stalk_h: float, cap_r: float, cap_h: float) -> Node3D:
	var n: Node3D = _node(pos)
	var stem: StandardMaterial3D = Look.flat(CREAM, 0.88)
	_put(n, Look.cylinder(stalk_r * 1.6, stalk_h * 0.1, stem, Vector3(0, stalk_h * 0.05, 0), stalk_r * 1.05, 28))
	_put(n, Look.cylinder(stalk_r * 1.05, stalk_h, stem, Vector3(0, stalk_h * 0.5, 0), stalk_r * 0.84, 28))
	# ribs up the stalk
	var rib: StandardMaterial3D = Look.flat(CREAM.darkened(0.08), 0.9)
	for i: int in 10:
		var a: float = TAU * float(i) / 10.0
		var rb := Look.box(Vector3(stalk_r * 0.06, stalk_h * 0.96, stalk_r * 0.1), rib, Vector3(cos(a), 0, sin(a)) * stalk_r * 0.97 + Vector3(0, stalk_h * 0.5, 0))
		rb.rotation.y = -a
		_put(n, rb, true)
	# the skirt (annulus) hanging off the stalk
	var skirt := Look.cylinder(stalk_r * 1.75, stalk_h * 0.04, Look.flat(CREAM.darkened(0.04), 0.85), Vector3(0, stalk_h * 0.74, 0), stalk_r * 1.15, 32)
	_put(n, skirt)
	# the cap: a dome, red, with cream warts; gills fan on its underside
	var cap_y: float = stalk_h
	var dome := Look.sphere(cap_r, Look.flat(RED, 0.55), Vector3(0, cap_y, 0))
	dome.scale = Vector3(1.0, cap_h / cap_r, 1.0)
	_put(n, dome)
	_put(n, Look.cylinder(cap_r * 0.99, cap_h * 0.05, Look.flat(Color(0.94, 0.84, 0.62), 0.9), Vector3(0, cap_y - cap_h * 0.02, 0), stalk_r * 1.1, 36))
	var wart: StandardMaterial3D = Look.flat(Color(1.0, 0.96, 0.88), 0.6)
	for i2: int in 26:
		var a2: float = rng.randf() * TAU
		var e: float = rng.randf_range(0.2, 1.3)
		var wr: float = cap_r * rng.randf_range(0.05, 0.11)
		var wp := Vector3(cos(a2) * cos(e) * cap_r, sin(e) * cap_h, sin(a2) * cos(e) * cap_r) * 0.985 + Vector3(0, cap_y, 0)
		var wsp := Look.sphere(wr, wart, wp)
		wsp.scale = Vector3(1.0, 0.35, 1.0)
		_put(n, wsp)
	# gills: thin radial blades under the cap
	var gill: StandardMaterial3D = Look.flat(Color(0.96, 0.88, 0.72), 0.9)
	for i3: int in 44:
		var a3: float = TAU * float(i3) / 44.0
		var g := Look.box(Vector3(cap_r * 0.72, cap_h * 0.1, 0.1), gill, Vector3(cos(a3), 0, sin(a3)) * (stalk_r * 1.2 + cap_r * 0.36) + Vector3(0, cap_y - cap_h * 0.07, 0))
		g.rotation.y = -a3
		_put(n, g, true)
	return n


## THE GREAT TOADSTOOL, mature: a vast stalk flaring at the foot with ribs and a ruffled skirt, topped by a
## FLAT red cap (a drum whose top face is the walkable summit at y = pos.y + stalk_h + cap_h), cream warts
## flat on top, a cream rolled rim and a fan of gills under it. `pos` = the foot on the forest floor.
func great_toadstool_flat(pos: Vector3, stalk_r: float, stalk_h: float, cap_r: float, cap_h: float) -> Node3D:
	var n: Node3D = _node(pos)
	var stem: StandardMaterial3D = Look.flat(CREAM, 0.88)
	var top_y: float = stalk_h + cap_h
	_put(n, Look.cylinder(stalk_r * 2.2, stalk_h * 0.06, stem, Vector3(0, stalk_h * 0.03, 0), stalk_r * 1.2, 32))
	_put(n, Look.cylinder(stalk_r * 1.05, stalk_h, stem, Vector3(0, stalk_h * 0.5, 0), stalk_r * 0.9, 32))
	var rib: StandardMaterial3D = Look.flat(CREAM.darkened(0.08), 0.9)
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0
		var rb := Look.box(Vector3(stalk_r * 0.07, stalk_h * 0.96, stalk_r * 0.1), rib, Vector3(cos(a), 0, sin(a)) * stalk_r * 0.99 + Vector3(0, stalk_h * 0.5, 0))
		rb.rotation.y = -a
		_put(n, rb, true)
	# the ruffled skirt hanging a third of the way down
	_put(n, Look.cylinder(stalk_r * 1.8, stalk_h * 0.025, Look.flat(CREAM.darkened(0.05), 0.85), Vector3(0, stalk_h * 0.55, 0), stalk_r * 1.1, 36))
	# the cap: a flat-topped red drum with a cream rim
	var red: StandardMaterial3D = Look.flat(RED, 0.5)
	_put(n, Look.cylinder(cap_r * 0.6, cap_h, red, Vector3(0, stalk_h + cap_h * 0.5, 0), cap_r, 40))
	var rim := TorusMesh.new()
	rim.inner_radius = cap_r - 0.35
	rim.outer_radius = cap_r + 0.15
	rim.rings = 48
	rim.ring_segments = 6
	var rim_n := Look.mesh_node(rim, Look.flat(Color(1.0, 0.94, 0.8), 0.6), Vector3(0, top_y - 0.1, 0))
	rim_n.scale = Vector3(1, 0.5, 1)
	_put(n, rim_n, true)
	# warts lying flat on the top (none near the middle, where the finish stands)
	var wart: StandardMaterial3D = Look.flat(Color(1.0, 0.96, 0.88), 0.6)
	for i2: int in 30:
		var a2: float = rng.randf() * TAU
		var d: float = rng.randf_range(4.5, cap_r - 2.0)
		var wr: float = rng.randf_range(0.5, 1.5)
		var wsp := Look.cylinder(wr, 0.05, wart, Vector3(cos(a2) * d, top_y + 0.03, sin(a2) * d), -1.0, 14)
		_put(n, wsp, true)
	# gills: thin radial blades under the cap
	var gill: StandardMaterial3D = Look.flat(Color(0.96, 0.88, 0.72), 0.9)
	for i3: int in 56:
		var a3: float = TAU * float(i3) / 56.0
		var g := Look.box(Vector3(cap_r * 0.55, cap_h * 0.5, 0.08), gill, Vector3(cos(a3), 0, sin(a3)) * (cap_r * 0.58 + stalk_r * 0.3) + Vector3(0, stalk_h - cap_h * 0.05, 0))
		g.rotation.y = -a3
		_put(n, g, true)
	return n
