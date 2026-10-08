class_name ToyboxDecor
extends RefCounted
## Toybox Tumble's scenery: the toys of a giant bedroom, built from primitives with shared Look
## materials. Everything takes a world position (and a yaw where it matters) and returns the node it
## made. None of it collides; the level keeps it clear of the route.

const RED := Color(0.93, 0.27, 0.25)
const BLUE := Color(0.2, 0.5, 0.93)
const YELLOW := Color(1.0, 0.8, 0.15)
const GREEN := Color(0.25, 0.75, 0.4)
const ORANGE := Color(1.0, 0.55, 0.15)
const PURPLE := Color(0.62, 0.4, 0.88)
const CREAM := Color(1.0, 0.94, 0.8)
const PINK := Color(1.0, 0.55, 0.75)
const WOOD := Color(0.72, 0.5, 0.3)

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


func _node(pos: Vector3, yaw: float = 0.0, scale: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	root.add_child(n)
	return n


func palette(i: int) -> Color:
	var cols: Array[Color] = [RED, BLUE, YELLOW, GREEN, ORANGE, PURPLE]
	return cols[posmod(i, cols.size())]


## An alphabet block (its centre at `pos`): painted cube, a cream disc and a bar on each side.
func abc_block(pos: Vector3, size: float, col: Color, yaw: float = 0.0, tilt: float = 0.0) -> Node3D:
	var n: Node3D = _node(pos, yaw)
	n.rotation.z = tilt
	n.add_child(Look.box(Vector3.ONE * size, Look.flat(col, 0.45), Vector3.ZERO))
	var cream: StandardMaterial3D = Look.flat(CREAM, 0.5)
	var ink: StandardMaterial3D = Look.flat(col.darkened(0.45), 0.5)
	for f: int in 4:
		var a: float = float(f) * PI * 0.5
		var out := Vector3(sin(a), 0, cos(a)) * (size * 0.5 + 0.01)
		var disc := Look.cylinder(size * 0.32, 0.03, cream, out, -1.0, 16)
		disc.rotation = Vector3(PI * 0.5, 0, 0)
		disc.rotation.y = a
		disc.basis = Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI * 0.5)
		n.add_child(disc)
		var bar := Look.box(Vector3(size * 0.1, size * 0.36, 0.04), ink, out * 1.002)
		bar.rotation.y = a
		n.add_child(bar)
	return n


## A LEGO-style brick: a body and a grid of studs on top.
func brick(pos: Vector3, nx: int, nz: int, col: Color, yaw: float = 0.0, unit: float = 1.4) -> Node3D:
	var n: Node3D = _node(pos, yaw)
	var h: float = unit * 0.9
	var mat: StandardMaterial3D = Look.flat(col, 0.35)
	n.add_child(Look.box(Vector3(nx * unit, h, nz * unit), mat, Vector3(0, h * 0.5, 0)))
	for ix: int in nx:
		for iz: int in nz:
			n.add_child(Look.cylinder(unit * 0.3, unit * 0.2, mat, Vector3((float(ix) - float(nx - 1) * 0.5) * unit, h + unit * 0.1, (float(iz) - float(nz - 1) * 0.5) * unit), -1.0, 12))
	return n


## A crayon lying along local z (centre at `pos`): paper wrap, a conical tip, a flat end.
func crayon(pos: Vector3, length: float, radius: float, col: Color, yaw: float = 0.0) -> Node3D:
	var n: Node3D = _node(pos, yaw)
	var body := Look.cylinder(radius, length * 0.82, Look.flat(col.lightened(0.1), 0.6), Vector3(0, 0, length * 0.09), -1.0, 12)
	body.rotation.x = PI * 0.5
	n.add_child(body)
	var wrap := Look.cylinder(radius * 1.03, length * 0.4, Look.flat(CREAM, 0.7), Vector3(0, 0, length * 0.18), -1.0, 12)
	wrap.rotation.x = PI * 0.5
	n.add_child(wrap)
	var band := Look.cylinder(radius * 1.05, length * 0.05, Look.flat(col.darkened(0.2), 0.5), Vector3(0, 0, length * 0.18), -1.0, 12)
	band.rotation.x = PI * 0.5
	n.add_child(band)
	var tip := Look.cylinder(radius, length * 0.18, Look.flat(col, 0.5), Vector3(0, 0, -length * 0.41), 0.05, 12)
	tip.rotation.x = -PI * 0.5
	n.add_child(tip)
	return n


## A crayon standing on end (base at `pos`): used as a pillar under a floating block.
func crayon_pillar(base: Vector3, height: float, radius: float, col: Color) -> Node3D:
	var n: Node3D = _node(base)
	n.add_child(Look.cylinder(radius, height, Look.flat(col, 0.55), Vector3(0, height * 0.5, 0), -1.0, 10))
	n.add_child(Look.cylinder(radius * 1.03, height * 0.3, Look.flat(CREAM, 0.7), Vector3(0, height * 0.5, 0), -1.0, 10))
	return n


## A striped beach ball.
func ball(pos: Vector3, radius: float, col: Color) -> Node3D:
	var n: Node3D = _node(pos)
	n.add_child(Look.sphere(radius, Look.flat(CREAM, 0.4), Vector3.ZERO))
	for i: int in 3:
		var band := Look.cylinder(radius * 1.005, radius * 0.5, Look.flat(palette(i + int(col.r * 5.0)), 0.4), Vector3.ZERO, radius * 0.7, 18)
		band.rotation = Vector3(0, float(i) * 1.0, float(i) * 1.1)
		n.add_child(band)
	return n


## A teddy bear sitting (base of its seat at `pos`), `s` times a 4 m bear.
func teddy(pos: Vector3, yaw: float, s: float, fur: Color = Color(0.78, 0.55, 0.32)) -> Node3D:
	var n: Node3D = _node(pos, yaw, s)
	var f: StandardMaterial3D = Look.flat(fur, 0.9)
	var light: StandardMaterial3D = Look.flat(fur.lightened(0.35), 0.9)
	var dark: StandardMaterial3D = Look.flat(Color(0.12, 0.08, 0.06), 0.5)
	n.add_child(Look.sphere(1.5, f, Vector3(0, 1.5, 0)))
	n.add_child(Look.sphere(0.95, light, Vector3(0, 1.4, -1.1)))
	n.add_child(Look.sphere(1.05, f, Vector3(0, 3.7, 0)))
	n.add_child(Look.sphere(0.45, light, Vector3(0, 3.5, -0.95)))
	n.add_child(Look.sphere(0.16, dark, Vector3(0, 3.6, -1.35)))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.sphere(0.4, f, Vector3(sx * 0.8, 4.5, 0.0)))
		n.add_child(Look.sphere(0.1, dark, Vector3(sx * 0.35, 3.95, -0.95)))
		n.add_child(Look.sphere(0.55, f, Vector3(sx * 1.55, 2.3, -0.4)))
		n.add_child(Look.sphere(0.6, f, Vector3(sx * 0.9, 0.5, -1.2)))
	n.add_child(Look.box(Vector3(2.4, 0.35, 0.2), Look.flat(RED, 0.5), Vector3(0, 2.7, -0.9)))
	return n


## A yellow rubber duck.
func duck(pos: Vector3, yaw: float, s: float) -> Node3D:
	var n: Node3D = _node(pos, yaw, s)
	var y: StandardMaterial3D = Look.flat(YELLOW, 0.35)
	n.add_child(Look.sphere(1.4, y, Vector3(0, 1.2, 0)))
	n.add_child(Look.sphere(0.9, y, Vector3(0, 2.7, -0.8)))
	n.add_child(Look.sphere(0.9, y, Vector3(0, 1.4, 1.2)))
	var beak := Look.box(Vector3(0.7, 0.2, 0.6), Look.flat(ORANGE, 0.4), Vector3(0, 2.6, -1.6))
	n.add_child(beak)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.sphere(0.1, Look.flat(Color(0.1, 0.1, 0.1), 0.4), Vector3(sx * 0.4, 2.95, -1.4)))
	return n


## A balloon on a string rising from `base`.
func balloon(base: Vector3, height: float, col: Color) -> Node3D:
	var n: Node3D = _node(base)
	n.add_child(Look.cylinder(0.02, height, Look.flat(Color(0.9, 0.9, 0.9), 0.6), Vector3(0, height * 0.5, 0), -1.0, 4))
	var b := Look.sphere(1.5, Look.flat(col, 0.2, 0.0, 0.25), Vector3(0, height + 1.4, 0))
	b.scale = Vector3(1.0, 1.2, 1.0)
	n.add_child(b)
	n.add_child(Look.cylinder(0.12, 0.2, Look.flat(col, 0.3), Vector3(0, height - 0.1, 0), 0.02, 6))
	return n


## A giant bed (foot toward local +z, headboard at -z): frame, mattress, quilt and pillow, 70 m long.
func bed(pos: Vector3, yaw: float) -> Node3D:
	var n: Node3D = _node(pos, yaw)
	var wood: StandardMaterial3D = Look.flat(WOOD, 0.7)
	n.add_child(Look.box(Vector3(46, 12, 76), wood, Vector3(0, 6, 0)))
	n.add_child(Look.box(Vector3(44, 8, 74), Look.flat(CREAM, 0.9), Vector3(0, 16, 0)))
	n.add_child(Look.box(Vector3(46.4, 5, 44), Look.flat(BLUE, 0.85), Vector3(0, 20.5, 14)))
	for i: int in 5:
		n.add_child(Look.box(Vector3(46.5, 5.1, 4), Look.flat(YELLOW if i % 2 == 0 else CREAM, 0.85), Vector3(0, 20.55, 28.0 - 8.0 * float(i))))
	var pillow := Look.box(Vector3(34, 8, 16), Look.flat(Color(1.0, 0.96, 0.9), 0.9), Vector3(0, 22, -28))
	n.add_child(pillow)
	n.add_child(Look.box(Vector3(48, 46, 4), wood, Vector3(0, 23, -39)))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.cylinder(2.4, 52, wood, Vector3(sx * 23.0, 26, -39), -1.0, 10))
		n.add_child(Look.sphere(3.0, Look.flat(YELLOW, 0.35, 0.3), Vector3(sx * 23.0, 53, -39)))
	return n


## A dollhouse facing local -z: two storeys, a pitched roof, windows with lit glass, a red door.
func dollhouse(pos: Vector3, yaw: float, s: float) -> Node3D:
	var n: Node3D = _node(pos, yaw, s)
	var wall: StandardMaterial3D = Look.flat(Color(1.0, 0.82, 0.86), 0.7)
	n.add_child(Look.box(Vector3(14, 12, 10), wall, Vector3(0, 6, 0)))
	var roof := Look.box(Vector3(15.5, 0.8, 11), Look.flat(RED, 0.6), Vector3(0, 12.8, 0))
	n.add_child(roof)
	var tri := PrismMesh.new()
	tri.size = Vector3(14.6, 5, 10.4)
	n.add_child(Look.mesh_node(tri, Look.flat(RED.darkened(0.1), 0.6), Vector3(0, 15.4, 0)))
	var glass: StandardMaterial3D = Look.flat(Color(1.0, 0.9, 0.55), 0.3, 0.0, 1.6)
	for sx: float in [-1.0, 1.0]:
		for y: float in [3.2, 9.0]:
			var w := Look.box(Vector3(2.4, 2.4, 0.2), glass, Vector3(sx * 4.2, y, -5.05))
			n.add_child(w)
			n.add_child(Look.box(Vector3(2.8, 0.25, 0.3), Look.flat(CREAM, 0.6), Vector3(sx * 4.2, y - 1.3, -5.1)))
	n.add_child(Look.box(Vector3(2.4, 4.2, 0.25), Look.flat(BLUE, 0.5), Vector3(0, 2.1, -5.05)))
	n.add_child(Look.sphere(0.2, Look.flat(YELLOW, 0.3, 0.8), Vector3(0.8, 2.1, -5.25)))
	return n


## A night-light: a glowing star-moon lamp on a small plug.
func nightlight(pos: Vector3, s: float) -> Node3D:
	var n: Node3D = _node(pos, 0.0, s)
	n.add_child(Look.box(Vector3(2.2, 3.0, 1.4), Look.flat(CREAM, 0.6), Vector3(0, 1.5, 0)))
	var g: StandardMaterial3D = Look.flat(Color(1.0, 0.9, 0.55), 0.3, 0.0, 2.2)
	n.add_child(Look.sphere(1.5, g, Vector3(0, 4.2, 0)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.5)
	l.light_energy = 1.2
	l.omni_range = 30.0
	l.position = Vector3(0, 4.2, 0)
	l.shadow_enabled = false
	n.add_child(l)
	return n


## A toy train track straight (along local z), sleepers and two rails.
func track(pos: Vector3, yaw: float, length: float) -> Node3D:
	var n: Node3D = _node(pos, yaw)
	var steel: StandardMaterial3D = Look.flat(Color(0.7, 0.72, 0.78), 0.3, 0.8)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.3, 0.3, length), steel, Vector3(sx * 1.2, 0.3, 0)))
	var count: int = int(length / 1.2)
	for i: int in count:
		n.add_child(Look.box(Vector3(3.4, 0.25, 0.6), Look.flat(WOOD, 0.8), Vector3(0, 0.1, -length * 0.5 + (float(i) + 0.5) * length / float(count))))
	return n


## A tall bookcase side (a wall of colourful book spines facing local +x), used round the finale.
func book_wall(pos: Vector3, yaw: float, length: float, height: float, bw: Vector2 = Vector2(0.4, 0.9)) -> Node3D:
	var n: Node3D = _node(pos, yaw)
	n.add_child(Look.box(Vector3(1.2, height, length), Look.flat(WOOD.darkened(0.2), 0.8), Vector3(-0.6, height * 0.5, 0)))
	var rows: int = int(height / 3.2)
	for r: int in rows:
		var y: float = 0.4 + 3.2 * float(r)
		n.add_child(Look.box(Vector3(2.4, 0.3, length), Look.flat(WOOD, 0.8), Vector3(0.6, y, 0)))
		var z: float = -length * 0.5 + 0.4
		while z < length * 0.5 - 0.6:
			var t: float = rng.randf_range(bw.x, bw.y)
			var bh: float = rng.randf_range(2.0, 2.9)
			n.add_child(Look.box(Vector3(1.8, bh, t), Look.flat(palette(rng.randi()), 0.6), Vector3(0.7, y + 0.15 + bh * 0.5, z + t * 0.5)))
			z += t + 0.04
	return n


## A toy hanging from a string that runs up out of sight (mobile-style): 0 star, 1 ball, 2 duck, 3 plane, 4 moon.
func hanging(pos: Vector3, kind: int, s: float, string_len: float = 60.0) -> Node3D:
	var n: Node3D = _node(pos, rng.randf() * TAU, s)
	n.add_child(Look.cylinder(0.04, string_len, Look.flat(Color(0.95, 0.95, 0.95), 0.6), Vector3(0, string_len * 0.5, 0), -1.0, 4))
	match posmod(kind, 5):
		0:
			var star := CylinderMesh.new()
			star.top_radius = 1.4
			star.bottom_radius = 1.4
			star.height = 0.5
			star.radial_segments = 5
			star.rings = 1
			var m := Look.mesh_node(star, Look.flat(YELLOW, 0.35, 0.0, 0.4), Vector3(0, -1.0, 0))
			m.rotation.x = PI * 0.5
			n.add_child(m)
		1:
			n.add_child(Look.sphere(1.3, Look.flat(palette(rng.randi()), 0.35), Vector3(0, -1.3, 0)))
		2:
			n.add_child(Look.sphere(1.0, Look.flat(YELLOW, 0.35), Vector3(0, -1.2, 0)))
			n.add_child(Look.sphere(0.65, Look.flat(YELLOW, 0.35), Vector3(0, -0.3, -0.5)))
			n.add_child(Look.box(Vector3(0.5, 0.15, 0.4), Look.flat(ORANGE, 0.4), Vector3(0, -0.3, -1.05)))
		3:
			n.add_child(Look.box(Vector3(0.7, 0.6, 3.2), Look.flat(CREAM, 0.5), Vector3(0, -1.0, 0)))
			n.add_child(Look.box(Vector3(4.2, 0.12, 1.1), Look.flat(RED, 0.5), Vector3(0, -0.9, -0.2)))
			n.add_child(Look.box(Vector3(1.6, 0.12, 0.7), Look.flat(RED, 0.5), Vector3(0, -0.8, 1.4)))
		_:
			n.add_child(Look.sphere(1.3, Look.flat(Color(1.0, 0.95, 0.7), 0.4, 0.0, 0.7), Vector3(0, -1.3, 0)))
	return n
