class_name OlympusDecor
extends RefCounted
## Sky Citadel's set dressing: a marble city of the gods adrift on golden-hour cloud. Temples with
## fluted colonnades and gilded pediments, round tholoi under domes, aqueduct arches, giant
## statues, floating rock islands carrying ruins and pouring cloud-falls, braziers, urns and
## laurels, and the great sun disc over the finish. All visual (no collision), built from shared
## Look meshes and a handful of materials. Palette: cream marble, warm travertine, gold, lapis
## blue and a little terracotta.

const MARBLE := Color(0.95, 0.92, 0.84)
const STONE := Color(0.84, 0.76, 0.64)
const SHADE := Color(0.72, 0.66, 0.6)
const GOLD := Color(1.0, 0.78, 0.28)
const LAPIS := Color(0.28, 0.5, 0.86)
const TERRA := Color(0.80, 0.42, 0.26)
const ROCK := Color(0.62, 0.52, 0.44)
const LAUREL := Color(0.38, 0.62, 0.30)

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


func _marble() -> StandardMaterial3D:
	return Look.flat(MARBLE, 0.5)


func _stone() -> StandardMaterial3D:
	return Look.flat(STONE, 0.7)


func _gold(e: float = 0.35) -> StandardMaterial3D:
	return Look.flat(GOLD, 0.35, 0.6, e)


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


# ---- columns, colonnades, temples ----------------------------------------------------------------

## A fluted Doric column standing on `pos` (the middle of its foot). `broken` snaps it partway
## with a jagged top and a fallen drum beside it.
func column(pos: Vector3, h: float, r: float, b: Basis = Basis.IDENTITY, broken: bool = false) -> Node3D:
	var n: Node3D = _node(pos, b)
	var m: StandardMaterial3D = _marble()
	var top_h: float = h * (0.62 if broken else 1.0)
	_put(n, Look.box(Vector3(r * 2.6, 0.18, r * 2.6), m, Vector3(0, 0.09, 0)))
	_put(n, Look.cylinder(r, top_h - 0.5, m, Vector3(0, 0.18 + (top_h - 0.5) * 0.5, 0), r * 0.8, 14))
	# flutes: thin shaded grooves
	var groove: StandardMaterial3D = Look.flat(SHADE, 0.8)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var rr: float = r * 0.9
		var fl := Look.box(Vector3(r * 0.08, top_h - 0.7, r * 0.06), groove, Vector3(cos(a) * rr, 0.18 + (top_h - 0.5) * 0.5, sin(a) * rr))
		fl.rotation.y = -a + PI * 0.5
		_put(n, fl, true)
	if broken:
		for k: int in 3:
			var c := Look.box(Vector3(r * rng.randf_range(0.5, 0.9), r * rng.randf_range(0.4, 0.8), r * rng.randf_range(0.5, 0.9)), m,
					Vector3(rng.randf_range(-0.6, 0.6) * r, top_h - 0.3 + float(k) * 0.1, rng.randf_range(-0.6, 0.6) * r))
			c.rotation = Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)
			_put(n, c)
		var drum := Look.cylinder(r * 0.9, r * 1.4, m, Vector3(r * 2.4, r * 0.5, r * 0.8), r * 0.85, 12)
		drum.rotation.z = PI * 0.5
		_put(n, drum)
	else:
		_put(n, Look.cylinder(r * 1.25, 0.2, m, Vector3(0, top_h - 0.4, 0), r * 0.85, 14))
		_put(n, Look.box(Vector3(r * 2.7, 0.22, r * 2.7), m, Vector3(0, top_h - 0.19, 0)))
	return n


## A row of columns with an architrave across the top: `pos` = the middle of the foot line, the row
## runs along local X.
func colonnade(pos: Vector3, b: Basis, n: int, spacing: float, h: float, r: float) -> Node3D:
	var node: Node3D = _node(pos, b)
	for i: int in n:
		var x: float = (float(i) - float(n - 1) * 0.5) * spacing
		var c: Node3D = column(Vector3.ZERO, h, r)
		root.remove_child(c)
		c.position = Vector3(x, 0, 0)
		node.add_child(c)
	var w: float = float(n - 1) * spacing + r * 3.0
	_put(node, Look.box(Vector3(w, 0.5, r * 2.6), _marble(), Vector3(0, h + 0.25, 0)))
	_put(node, Look.box(Vector3(w + 0.1, 0.1, r * 2.7), _gold(), Vector3(0, h + 0.52, 0)))
	return node


## A temple: a three-step stylobate, a front and back colonnade, a cella wall with a lit doorway, an
## entablature with a lapis-and-terracotta frieze and a gilded pediment at each end. `pos` = the
## middle of the lowest step's foot; the front faces local -Z. `cols` across the front, `bays` deep.
func temple(pos: Vector3, b: Basis, cols: int = 6, bays: int = 9, h: float = 5.0, with_light: bool = false) -> Node3D:
	var n: Node3D = _node(pos, b)
	var sp: float = 2.4
	var w: float = float(cols - 1) * sp + 2.0
	var d: float = float(bays - 1) * sp + 2.0
	for i: int in 3:
		var k: float = float(2 - i) * 0.6
		_put(n, Look.box(Vector3(w + 2.0 + k * 2.0, 0.34, d + 2.0 + k * 2.0), _marble() if i % 2 == 0 else _stone(), Vector3(0, 0.17 + 0.34 * float(i), 0)))
	var base: float = 1.02
	# the colonnade: all four sides
	for i2: int in cols:
		var x: float = (float(i2) - float(cols - 1) * 0.5) * sp
		for sz: float in [-1.0, 1.0]:
			var c: Node3D = column(Vector3.ZERO, h, 0.42)
			root.remove_child(c)
			c.position = Vector3(x, base, sz * d * 0.5)
			n.add_child(c)
	for j: int in range(1, bays - 1):
		var z: float = (float(j) - float(bays - 1) * 0.5) * sp
		for sx: float in [-1.0, 1.0]:
			var c2: Node3D = column(Vector3.ZERO, h, 0.42)
			root.remove_child(c2)
			c2.position = Vector3(sx * w * 0.5, base, z)
			n.add_child(c2)
	# the cella: a solid inner block with a glowing doorway on the front
	_put(n, Look.box(Vector3(w - 2.6, h, d - 2.6), _stone(), Vector3(0, base + h * 0.5, 0)))
	_put(n, Look.box(Vector3(1.6, 2.6, 0.12), _glow(Color(1.0, 0.82, 0.5), 1.5), Vector3(0, base + 1.3, -(d - 2.6) * 0.5 - 0.04)), true)
	# entablature: architrave, frieze (lapis and terracotta panels), cornice
	var ey: float = base + h
	_put(n, Look.box(Vector3(w + 0.8, 0.5, d + 0.8), _marble(), Vector3(0, ey + 0.25, 0)))
	var panels: int = cols * 2
	for i3: int in panels:
		var px: float = (float(i3) + 0.5) / float(panels) * (w + 0.4) - (w + 0.4) * 0.5
		var col: Color = LAPIS if i3 % 2 == 0 else TERRA
		for sz2: float in [-1.0, 1.0]:
			_put(n, Look.box(Vector3((w + 0.4) / float(panels) * 0.82, 0.34, 0.06), Look.flat(col, 0.7), Vector3(px, ey + 0.55, sz2 * (d * 0.5 + 0.43))), true)
	_put(n, Look.box(Vector3(w + 1.2, 0.18, d + 1.2), _gold(0.2), Vector3(0, ey + 0.9, 0)))
	# the roof: two slabs meeting at a ridge, and a triangular pediment at each end
	var rise: float = w * 0.17
	for sx2: float in [-1.0, 1.0]:
		var slab := Look.box(Vector3(sqrt(pow(w * 0.5 + 0.6, 2.0) + rise * rise) + 0.2, 0.3, d + 1.4), Look.flat(TERRA.lightened(0.1), 0.75), Vector3(sx2 * (w * 0.25 + 0.3), ey + 1.1 + rise * 0.5, 0))
		slab.rotation.z = -sx2 * atan2(rise, w * 0.5 + 0.6)
		_put(n, slab)
	for sz3: float in [-1.0, 1.0]:
		var pm := PrismMesh.new()
		pm.size = Vector3(w + 1.0, rise, 0.3)
		var ped := Look.mesh_node(pm, _marble(), Vector3(0, ey + 1.05 + rise * 0.5, sz3 * (d * 0.5 + 0.62)))
		_put(n, ped)
		var pm2 := PrismMesh.new()
		pm2.size = Vector3(w * 0.7, rise * 0.62, 0.06)
		_put(n, Look.mesh_node(pm2, Look.flat(LAPIS, 0.6), Vector3(0, ey + 1.0 + rise * 0.36, sz3 * (d * 0.5 + 0.8))), true)
		_put(n, Look.sphere(0.34, _glow(GOLD, 2.0), Vector3(0, ey + 1.2 + rise * 0.92, sz3 * (d * 0.5 + 0.62))), true)
	if with_light:
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.82, 0.5)
		o.light_energy = 1.4
		o.omni_range = 14.0
		o.position = Vector3(0, base + 2.0, -d * 0.5 - 2.0)
		n.add_child(o)
	return n


## A round temple: a ring of columns under a shallow dome with a golden finial.
func tholos(pos: Vector3, r: float = 4.5, cols: int = 10, h: float = 4.6) -> Node3D:
	var n: Node3D = _node(pos)
	_put(n, Look.cylinder(r + 1.4, 0.4, _stone(), Vector3(0, 0.2, 0), -1.0, 28))
	_put(n, Look.cylinder(r + 0.8, 0.34, _marble(), Vector3(0, 0.57, 0), -1.0, 28))
	for i: int in cols:
		var a: float = TAU * float(i) / float(cols)
		var c: Node3D = column(Vector3.ZERO, h, 0.36)
		root.remove_child(c)
		c.position = Vector3(cos(a) * r, 0.74, sin(a) * r)
		n.add_child(c)
	_put(n, Look.cylinder(r + 0.5, 0.5, _marble(), Vector3(0, 0.74 + h + 0.25, 0), -1.0, 28))
	_put(n, Look.cylinder(r + 0.6, 0.1, _gold(0.2), Vector3(0, 0.74 + h + 0.55, 0), -1.0, 28))
	var dome := SphereMesh.new()
	dome.radius = r * 0.92
	dome.height = r * 0.92
	dome.is_hemisphere = true
	_put(n, Look.mesh_node(dome, Look.flat(Color(0.9, 0.78, 0.5), 0.35, 0.5, 0.15), Vector3(0, 0.74 + h + 0.55, 0)))
	_put(n, Look.sphere(0.3, _glow(GOLD, 2.2), Vector3(0, 0.74 + h + 0.55 + r * 0.92 + 0.15, 0)), true)
	_put(n, Look.cylinder(r * 0.55, h, Look.flat(Color(1.0, 0.82, 0.55), 0.8, 0.0, 0.25), Vector3(0, 0.74 + h * 0.5, 0), -1.0, 16))
	return n


## A run of aqueduct arches: piers and round arches carrying a channel. `pos` = the middle of the
## foot line, running along local X.
func aqueduct(pos: Vector3, b: Basis, arches: int = 5, span: float = 5.0, h: float = 9.0) -> Node3D:
	var n: Node3D = _node(pos, b)
	var m: StandardMaterial3D = _stone()
	var pier: float = 1.2
	var total: float = float(arches) * (span + pier) + pier
	var r: float = span * 0.5
	var leg: float = h - r
	for i: int in arches + 1:
		var x: float = -total * 0.5 + pier * 0.5 + float(i) * (span + pier)
		_put(n, Look.box(Vector3(pier, h, 2.0), m, Vector3(x, h * 0.5, 0)))
	for i2: int in arches:
		var cx: float = -total * 0.5 + pier + r + float(i2) * (span + pier)
		var k: int = 9
		for j: int in k:
			var a: float = PI * (float(j) + 0.5) / float(k)
			var v := Look.box(Vector3(0.62, r * PI / float(k) + 0.05, 2.04), _marble(), Vector3(cx + cos(a) * r, leg + sin(a) * r, 0))
			v.rotation.z = a
			_put(n, v)
	_put(n, Look.box(Vector3(total + 0.6, 0.5, 2.6), _marble(), Vector3(0, h + 0.25, 0)))
	_put(n, Look.box(Vector3(total, 0.1, 1.9), _glow(Color(0.5, 0.82, 1.0), 0.9), Vector3(0, h + 0.52, 0)), true)
	return n


# ---- statues -----------------------------------------------------------------------------------

## A giant marble figure on a plinth: robed legs, chest, head with a gilded helm. `pos` = the middle
## of the plinth's foot, the figure faces local -Z. `arm_up`: 0 both arms down, 1 right arm raised
## holding a spear, 2 both arms out to the sides.
func statue(pos: Vector3, b: Basis, h: float = 9.0, arm_up: int = 1) -> Node3D:
	var n: Node3D = _node(pos, b)
	var m: StandardMaterial3D = _marble()
	var ph: float = h * 0.16
	_put(n, Look.box(Vector3(h * 0.4, ph, h * 0.4), _stone(), Vector3(0, ph * 0.5, 0)))
	_put(n, Look.box(Vector3(h * 0.44, ph * 0.18, h * 0.44), _gold(0.2), Vector3(0, ph + 0.05, 0)), true)
	var by: float = ph
	var body_h: float = h - ph
	# robe: a tapering cylinder, with hanging folds
	_put(n, Look.cylinder(body_h * 0.2, body_h * 0.55, m, Vector3(0, by + body_h * 0.275, 0), body_h * 0.13, 14))
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var fold := Look.box(Vector3(body_h * 0.03, body_h * 0.5, body_h * 0.03), Look.flat(SHADE, 0.8), Vector3(cos(a), 0, sin(a)) * body_h * 0.17 + Vector3(0, by + body_h * 0.28, 0))
		fold.rotation.y = -a
		_put(n, fold, true)
	_put(n, Look.cylinder(body_h * 0.14, body_h * 0.27, m, Vector3(0, by + body_h * 0.68, 0), body_h * 0.17, 12))
	_put(n, Look.cylinder(body_h * 0.045, body_h * 0.08, m, Vector3(0, by + body_h * 0.84, 0), -1.0, 10))
	_put(n, Look.sphere(body_h * 0.075, m, Vector3(0, by + body_h * 0.93, 0)))
	# the helm and its crest
	var helm := Look.cylinder(body_h * 0.085, body_h * 0.05, _gold(0.3), Vector3(0, by + body_h * 0.985, 0), body_h * 0.078, 12)
	_put(n, helm)
	_put(n, Look.box(Vector3(body_h * 0.025, body_h * 0.07, body_h * 0.16), _gold(0.3), Vector3(0, by + body_h * 1.03, 0)))
	# arms
	var sh: float = body_h * 0.18
	var sy: float = by + body_h * 0.76
	for side: float in [-1.0, 1.0]:
		var raised: bool = (arm_up == 1 and side > 0.0) or arm_up == 2
		var arm := Look.cylinder(body_h * 0.036, body_h * 0.3, m, Vector3(side * (sh + body_h * 0.05), sy - (0.0 if raised else body_h * 0.14), 0), body_h * 0.03, 8)
		if raised:
			arm.position = Vector3(side * (sh + body_h * 0.1), sy + body_h * 0.1, 0)
			arm.rotation.z = -side * 0.5
		_put(n, arm)
	if arm_up == 1:
		_put(n, Look.cylinder(body_h * 0.012, body_h * 0.85, _gold(0.25), Vector3(sh + body_h * 0.2, sy + body_h * 0.18, 0), -1.0, 6))
		var tip := PrismMesh.new()
		tip.size = Vector3(body_h * 0.05, body_h * 0.1, body_h * 0.02)
		_put(n, Look.mesh_node(tip, _gold(0.5), Vector3(sh + body_h * 0.2, sy + body_h * 0.18 + body_h * 0.47, 0)))
	return n


# ---- floating islands, sun and sky dressing -------------------------------------------------------

## A floating island of warm rock: a flat marble-grey top, an upturned rock cone below with a few
## lumps, optionally a ruin on top and a cloud-fall pouring off one edge. `pos` = the middle of its top.
func island(pos: Vector3, r: float, depth: float, ruin: bool = true, fall: bool = false) -> Node3D:
	var n: Node3D = _node(pos)
	var rock: StandardMaterial3D = Look.flat(ROCK, 0.95)
	_put(n, Look.cylinder(r, 0.6, Look.flat(Color(0.74, 0.72, 0.6), 0.9), Vector3(0, -0.3, 0), r * 0.97, 18))
	_put(n, Look.cylinder(r * 0.97, depth, rock, Vector3(0, -0.6 - depth * 0.5, 0), r * 0.12, 12))
	for i: int in 4:
		var a: float = rng.randf() * TAU
		var lump := Look.sphere(r * rng.randf_range(0.14, 0.24), rock, Vector3(cos(a) * r * 0.55, -0.6 - depth * rng.randf_range(0.25, 0.7), sin(a) * r * 0.55))
		_put(n, lump)
	# grass tuft on the rim and a couple of small trees
	_put(n, Look.cylinder(r * 0.99, 0.08, Look.flat(Color(0.5, 0.68, 0.34), 0.9), Vector3(0, 0.02, 0), -1.0, 18), true)
	if ruin and r > 5.0:
		var ccount: int = 3
		for i2: int in ccount:
			var ang: float = rng.randf() * TAU
			var rad: float = rng.randf_range(0.2, 0.55) * r
			var c: Node3D = column(Vector3.ZERO, rng.randf_range(3.0, 5.0), 0.36, Basis.IDENTITY, rng.randf() < 0.5)
			root.remove_child(c)
			c.position = Vector3(cos(ang) * rad, 0.05, sin(ang) * rad)
			n.add_child(c)
	if fall:
		OlympusFx.cloudfall(n, Vector3(r * 0.9, -0.5, 0), 3.0, depth * 1.4, 26)
	return n


## The great sun disc: a gold ring and boss with `rays` spokes, facing local -Z (towards the
## player coming up the stair). Emissive but bounded.
func sun_disc(pos: Vector3, b: Basis, r: float = 9.0, rays: int = 24) -> Node3D:
	var n: Node3D = _node(pos, b)
	var disc_mat: StandardMaterial3D = Look.flat(Color(1.0, 0.84, 0.4), 0.35, 0.3, 1.1)
	var ring_mat: StandardMaterial3D = _glow(Color(1.0, 0.8, 0.32), 1.8)
	var disc := Look.cylinder(r, 0.5, disc_mat, Vector3.ZERO, -1.0, 48)
	disc.rotation.x = PI * 0.5
	_put(n, disc)
	var rim := TorusMesh.new()
	rim.inner_radius = r * 0.96
	rim.outer_radius = r * 1.04
	rim.rings = 56
	rim.ring_segments = 8
	var rim_n := Look.mesh_node(rim, ring_mat)
	rim_n.rotation.x = PI * 0.5
	_put(n, rim_n, true)
	var boss := Look.cylinder(r * 0.34, 0.8, Look.flat(Color(1.0, 0.92, 0.6), 0.3, 0.2, 1.6), Vector3(0, 0, -0.1), -1.0, 36)
	boss.rotation.x = PI * 0.5
	_put(n, boss, true)
	for i: int in rays:
		var a: float = TAU * float(i) / float(rays)
		var long: bool = i % 2 == 0
		var rl: float = r * (0.45 if long else 0.28)
		var spoke := Look.box(Vector3(r * (0.075 if long else 0.05), rl, 0.5), ring_mat if long else disc_mat, Vector3(cos(a), sin(a), 0) * (r * 1.04 + rl * 0.5))
		spoke.rotation.z = a - PI * 0.5
		_put(n, spoke, true)
	return n


## A flight of broad marble steps going up (decorative): `pos` = the foot of the flight, rising
## towards local -Z.
func stair(pos: Vector3, b: Basis, steps: int, w: float, rise: float, run: float) -> Node3D:
	var n: Node3D = _node(pos, b)
	for i: int in steps:
		_put(n, Look.box(Vector3(w, rise * (float(i) + 1.0), run), _marble() if i % 2 == 0 else _stone(), Vector3(0, rise * (float(i) + 1.0) * 0.5, -run * (float(i) + 0.5))))
	return n


## A standing brazier with a flame light (no real light; the flame is an emissive cone).
func brazier(pos: Vector3, scale: float = 1.0) -> Node3D:
	var n: Node3D = _node(pos)
	_put(n, Look.cylinder(0.32 * scale, 0.9 * scale, _marble(), Vector3(0, 0.45 * scale, 0), 0.18 * scale, 10))
	_put(n, Look.cylinder(0.55 * scale, 0.28 * scale, _gold(0.3), Vector3(0, 1.05 * scale, 0), 0.34 * scale, 14))
	var flame := Look.cylinder(0.0, 0.7 * scale, _glow(Color(1.0, 0.62, 0.2), 2.4), Vector3(0, 1.5 * scale, 0), 0.3 * scale, 8)
	_put(n, flame, true)
	return n


## A laurel wreath ring (flat in local XY), `pos` = its centre.
func laurel(pos: Vector3, b: Basis, r: float = 1.4) -> Node3D:
	var n: Node3D = _node(pos, b)
	var leaf_mat: StandardMaterial3D = Look.flat(LAUREL, 0.7)
	for i: int in 22:
		var a: float = TAU * float(i) / 22.0
		var leaf := Look.box(Vector3(r * 0.2, r * 0.07, r * 0.03), leaf_mat, Vector3(cos(a), sin(a), 0) * r)
		leaf.rotation = Vector3(0, 0, a + PI * 0.5 + (0.5 if i % 2 == 0 else -0.5))
		_put(n, leaf, true)
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.97
	tm.outer_radius = r * 1.03
	tm.rings = 32
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, _gold(0.3))
	ring.rotation.x = PI * 0.5
	_put(n, ring, true)
	return n


## A wide faint shaft of sunlight slanting down (additive quad pair), `pos` = its top.
func god_ray(pos: Vector3, b: Basis, w: float, h: float, alpha: float = 0.07) -> Node3D:
	var n: Node3D = _node(pos, b)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.86, 0.55, alpha)
	mat.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	_put(n, Look.mesh_node(q, mat, Vector3(0, -h * 0.5, 0)), true)
	var q2 := Look.mesh_node(q, mat, Vector3(0, -h * 0.5, 0))
	q2.rotation.y = PI * 0.5
	_put(n, q2, true)
	return n


## A little cumulus puffed round a bounce pad (decor): `pos` = the pad's underside.
func cloud_puff(pos: Vector3) -> void:
	var n: Node3D = _node(pos)
	var cm: ShaderMaterial = Look.cloud_material()
	for i: int in 7:
		var a: float = TAU * float(i) / 7.0
		var r: float = rng.randf_range(0.65, 0.9)
		var puff := Look.sphere(rng.randf_range(0.35, 0.55), cm, Vector3(cos(a) * r, rng.randf_range(-0.1, 0.05), sin(a) * r))
		_put(n, puff, true)
	_put(n, Look.sphere(0.7, cm, Vector3(0, -0.25, 0)), true)


# ---- under the route ------------------------------------------------------------------------------

## A broken fluted column dangling under a small floating post (`top` = the post's underside).
func hang_column(top: Vector3, r: float, length: float) -> void:
	var n: Node3D = _node(top)
	_put(n, Look.box(Vector3(r * 2.6, 0.16, r * 2.6), _marble(), Vector3(0, -0.08, 0)))
	_put(n, Look.cylinder(r * 0.82, length, _marble(), Vector3(0, -length * 0.5 - 0.16, 0), r, 10))
	for i: int in 3:
		var c := Look.box(Vector3.ONE * r * rng.randf_range(0.6, 1.1), _stone(), Vector3(rng.randf_range(-0.3, 0.3), -length - 0.5 - 0.8 * float(i), rng.randf_range(-0.3, 0.3)))
		c.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		_put(n, c)


## A stepped inverted pyramid of travertine under a big slab (`top` = the slab's underside).
func keel(top: Vector3, sx: float, sz: float, depth: float) -> void:
	var n: Node3D = _node(top)
	var steps: int = 4
	for i: int in steps:
		var k: float = 1.0 - float(i + 1) / float(steps + 1)
		_put(n, Look.box(Vector3(sx * k, depth / float(steps), sz * k), _marble() if i % 2 == 0 else _stone(), Vector3(0, -depth / float(steps) * (float(i) + 0.5), 0)))
	_put(n, Look.box(Vector3(sx * 0.16, 0.05, sz * 0.16), _glow(GOLD, 1.6), Vector3(0, -depth - 0.03, 0)), true)
