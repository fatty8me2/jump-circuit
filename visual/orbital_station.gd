class_name OrbitalStation
extends RefCounted
## Orbital Drift set dressing: the station's superstructure built from Look primitives -
## pressurised modules, truss booms, solar wings, radiator fins, a spinning habitat wheel,
## an antenna dish and a docked shuttle. All visual only (no collision): it is scenery that
## sits well off the course, so it never blocks a landing.

const SPIN: Script = preload("res://visual/spin.gd")


static func _hull() -> StandardMaterial3D:
	return Look.flat(Color(0.86, 0.87, 0.9), 0.5, 0.25)


static func _dark() -> StandardMaterial3D:
	return Look.flat(Color(0.16, 0.17, 0.2), 0.55, 0.6)


static func _add(parent: Node3D, n: Node3D) -> Node3D:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(n)
	return n


## Pressurised module: a hull cylinder along the local Z of `basis`, end cones, a docking collar
## at each end, lit window strips and a handful of hull panels.
static func module(parent: Node3D, pos: Vector3, basis: Basis, length: float, radius: float, lights: Color = Color(1.0, 0.82, 0.5)) -> Node3D:
	var n := Node3D.new()
	n.transform = Transform3D(basis, pos)
	parent.add_child(n)
	var hull: StandardMaterial3D = _hull()
	var body := Look.cylinder(radius, length, hull, Vector3.ZERO, -1.0, 20)
	body.rotation.x = PI * 0.5
	_add(n, body)
	var dark: StandardMaterial3D = _dark()
	var win: StandardMaterial3D = Look.flat(lights, 0.3, 0.0, 3.2)
	for s: float in [-1.0, 1.0]:
		var cone := Look.cylinder(radius, radius * 0.8, hull, Vector3(0, 0, s * (length * 0.5 + radius * 0.4)), radius * 0.45, 20)
		cone.rotation.x = s * PI * 0.5
		_add(n, cone)
		var collar := TorusMesh.new()
		collar.inner_radius = radius * 0.42
		collar.outer_radius = radius * 0.6
		var cm := Look.mesh_node(collar, dark, Vector3(0, 0, s * (length * 0.5 + radius * 0.8)))
		cm.rotation.x = PI * 0.5
		_add(n, cm)
		# ribs near each end
		var rib := TorusMesh.new()
		rib.inner_radius = radius * 0.98
		rib.outer_radius = radius * 1.08
		var rm := Look.mesh_node(rib, dark, Vector3(0, 0, s * length * 0.38))
		rm.rotation.x = PI * 0.5
		_add(n, rm)
	# window strips on both flanks
	for side: float in [-1.0, 1.0]:
		_add(n, Look.box(Vector3(0.08, radius * 0.22, length * 0.7), win, Vector3(side * radius * 1.0, radius * 0.25, 0)))
	# hull panels / greebles
	for i: int in 4:
		var z: float = -length * 0.3 + float(i) * length * 0.2
		_add(n, Look.box(Vector3(radius * 0.7, 0.18, length * 0.12), dark, Vector3(0, radius * 1.0, z)))
	return n


## Straight open truss boom between two world points (four rails + zig-zag braces).
static func truss(parent: Node3D, a: Vector3, b: Vector3, w: float = 1.4) -> Node3D:
	var n := Node3D.new()
	var d: Vector3 = b - a
	var len: float = d.length()
	var z: Vector3 = d / len
	var up: Vector3 = Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = up.cross(z).normalized()
	var y: Vector3 = z.cross(x)
	n.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	parent.add_child(n)
	var mat: StandardMaterial3D = Look.flat(Color(0.55, 0.57, 0.62), 0.45, 0.8)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_add(n, Look.box(Vector3(0.14, 0.14, len), mat, Vector3(sx * w * 0.5, sy * w * 0.5, 0)))
	var k: int = maxi(int(len / (w * 1.4)), 1)
	for i: int in k:
		var zz: float = -len * 0.5 + (float(i) + 0.5) * len / float(k)
		_add(n, Look.box(Vector3(w, 0.09, 0.09), mat, Vector3(0, w * 0.5 * (1.0 if i % 2 == 0 else -1.0), zz)))
		_add(n, Look.box(Vector3(0.09, w, 0.09), mat, Vector3(w * 0.5 * (1.0 if i % 2 == 0 else -1.0), 0, zz)))
	return n


## Solar wing: a big cell array (size.x by size.y) in the local XY plane of `basis`, gold frame,
## dark blue cells split by a silver grid; the boom runs along its long edge.
static func solar_wing(parent: Node3D, pos: Vector3, basis: Basis, size: Vector2) -> Node3D:
	var n := Node3D.new()
	n.transform = Transform3D(basis, pos)
	parent.add_child(n)
	var cells: StandardMaterial3D = Look.flat(Color(0.07, 0.13, 0.36), 0.12, 0.7)
	cells.emission_enabled = true
	cells.emission = Color(0.05, 0.1, 0.3)
	cells.emission_energy_multiplier = 0.4
	var grid: StandardMaterial3D = Look.flat(Color(0.7, 0.74, 0.82), 0.35, 0.9)
	var frame: StandardMaterial3D = Look.flat(Color(0.95, 0.72, 0.3), 0.35, 0.9)
	_add(n, Look.box(Vector3(size.x, size.y, 0.12), cells))
	var cols: int = int(size.x / 3.0)
	var rows: int = int(size.y / 3.0)
	for i: int in range(1, cols):
		_add(n, Look.box(Vector3(0.1, size.y, 0.16), grid, Vector3(-size.x * 0.5 + float(i) * size.x / float(cols), 0, 0)))
	for j: int in range(1, rows):
		_add(n, Look.box(Vector3(size.x, 0.1, 0.16), grid, Vector3(0, -size.y * 0.5 + float(j) * size.y / float(rows), 0)))
	for s: float in [-1.0, 1.0]:
		_add(n, Look.box(Vector3(size.x + 0.4, 0.3, 0.25), frame, Vector3(0, s * size.y * 0.5, 0)))
		_add(n, Look.box(Vector3(0.3, size.y, 0.25), frame, Vector3(s * size.x * 0.5, 0, 0)))
	return n


## Radiator: a stack of white fins with glowing coolant edges.
static func radiator(parent: Node3D, pos: Vector3, basis: Basis, size: Vector2, fins: int = 5) -> Node3D:
	var n := Node3D.new()
	n.transform = Transform3D(basis, pos)
	parent.add_child(n)
	var white: StandardMaterial3D = Look.flat(Color(0.93, 0.94, 0.96), 0.6, 0.0)
	var glow: StandardMaterial3D = Look.flat(Color(1.0, 0.45, 0.2), 0.4, 0.0, 2.2)
	for i: int in fins:
		var y: float = (float(i) - float(fins - 1) * 0.5) * 1.6
		_add(n, Look.box(Vector3(size.x, 0.1, size.y), white, Vector3(0, y, 0)))
		_add(n, Look.box(Vector3(size.x, 0.12, 0.1), glow, Vector3(0, y, size.y * 0.5)))
	_add(n, Look.box(Vector3(0.4, float(fins) * 1.6, 0.4), _dark(), Vector3(-size.x * 0.5, 0, 0)))
	return n


## The habitat wheel: a spinning torus with spokes to a hub and lit window bands, turning about
## local Y of `basis` every `period` seconds.
static func habitat_wheel(parent: Node3D, pos: Vector3, basis: Basis, radius: float, period: float) -> Node3D:
	var holder := Node3D.new()
	holder.transform = Transform3D(basis, pos)
	parent.add_child(holder)
	var n := Node3D.new()
	n.set_script(SPIN)
	n.set("period", period)
	holder.add_child(n)
	var hull: StandardMaterial3D = _hull()
	var tube := TorusMesh.new()
	tube.inner_radius = radius - 3.0
	tube.outer_radius = radius + 3.0
	tube.rings = 64
	tube.ring_segments = 16
	_add(n, Look.mesh_node(tube, hull))
	var win: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.55), 0.3, 0.0, 3.0)
	var band := TorusMesh.new()
	band.inner_radius = radius + 2.7
	band.outer_radius = radius + 3.15
	band.rings = 64
	band.ring_segments = 6
	var bm := Look.mesh_node(band, win)
	bm.scale = Vector3(1, 0.18, 1)
	_add(n, bm)
	var dark: StandardMaterial3D = _dark()
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var spoke := Look.box(Vector3(1.2, 1.2, radius - 3.0), dark, Vector3(sin(a), 0, cos(a)) * (radius - 3.0) * 0.5)
		spoke.rotation.y = a
		_add(n, spoke)
		# module pods on the rim
		var pod := Look.box(Vector3(4.5, 4.5, 7.0), hull, Vector3(sin(a + 0.5), 0, cos(a + 0.5)) * radius)
		pod.rotation.y = a + 0.5
		_add(n, pod)
	_add(n, Look.sphere(4.5, hull))
	var axle := Look.cylinder(1.2, 18.0, dark, Vector3.ZERO, -1.0, 12)
	_add(holder, axle)
	return holder


## Antenna dish on a mast, aimed along `aim`.
static func dish(parent: Node3D, pos: Vector3, aim: Vector3, radius: float = 4.0) -> Node3D:
	var n := Node3D.new()
	var z: Vector3 = aim.normalized()
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	n.transform = Transform3D(Basis(x, z.cross(x), z), pos)
	parent.add_child(n)
	var white: StandardMaterial3D = Look.flat(Color(0.9, 0.9, 0.92), 0.5, 0.2)
	var bowl := Look.cylinder(radius, radius * 0.35, white, Vector3(0, 0, 0), radius * 0.2, 28)
	bowl.rotation.x = -PI * 0.5
	_add(n, bowl)
	var feed := Look.cylinder(0.08, radius * 1.1, _dark(), Vector3(0, 0, radius * 0.55), -1.0, 6)
	feed.rotation.x = PI * 0.5
	_add(n, feed)
	_add(n, Look.sphere(0.3, Look.flat(Color(1.0, 0.3, 0.2), 0.3, 0.0, 3.0), Vector3(0, 0, radius * 1.1)))
	return n


## A docked shuttle: fuselage along local -Z (nose), delta wings, tail fin, engine bells that
## glow, and a slow idle exhaust.
static func shuttle(parent: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(n)
	var hull: StandardMaterial3D = _hull()
	var dark: StandardMaterial3D = _dark()
	var body := Look.cylinder(1.8, 16.0, hull, Vector3.ZERO, -1.0, 18)
	body.rotation.x = PI * 0.5
	_add(n, body)
	var nose := Look.cylinder(1.8, 4.0, hull, Vector3(0, 0, -10.0), 0.4, 18)
	nose.rotation.x = -PI * 0.5
	_add(n, nose)
	_add(n, Look.box(Vector3(2.2, 0.5, 1.2), Look.flat(Color(0.1, 0.12, 0.16), 0.1, 0.8), Vector3(0, 1.3, -9.4)))
	for s: float in [-1.0, 1.0]:
		var wing := Look.box(Vector3(7.0, 0.3, 7.0), hull, Vector3(s * 4.2, -0.8, 3.0))
		wing.rotation.y = s * 0.5
		_add(n, wing)
		_add(n, Look.box(Vector3(6.5, 0.32, 0.4), Look.flat(Look.c("accent"), 0.4, 0.0, 1.5), Vector3(s * 4.4, -0.62, 6.0)))
	_add(n, Look.box(Vector3(0.3, 4.0, 4.0), hull, Vector3(0, 3.2, 6.0)))
	var glow: StandardMaterial3D = Look.flat(Color(0.5, 0.75, 1.0), 0.3, 0.0, 4.0)
	for e: Vector2 in [Vector2(-0.8, 0.4), Vector2(0.8, 0.4), Vector2(0, -0.7)]:
		var bell := Look.cylinder(0.45, 1.2, dark, Vector3(e.x, e.y, 8.5), 0.7, 14)
		bell.rotation.x = PI * 0.5
		_add(n, bell)
		var disc := Look.cylinder(0.55, 0.05, glow, Vector3(e.x, e.y, 9.1), -1.0, 14)
		disc.rotation.x = PI * 0.5
		_add(n, disc)
		OrbitalFx.exhaust(n, Vector3(e.x, e.y, 9.3), Vector3(0, 0, 1), 2.5, 0.35, Color(0.55, 0.75, 1.0))
	return n
