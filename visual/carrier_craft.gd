class_name CarrierCraft
extends RefCounted
## Super Carrier: the aircraft and deck vehicles, built from primitives (decoration only - no
## collision, no markings beyond plain modex-free greys). A generic twin-tail strike fighter (wings
## spread or folded), a utility helicopter (rotor spread or folded), a low deck tractor and a
## yellow tow tug. Every builder returns a Node3D whose origin sits on the deck under the craft's
## middle, nose / front toward local -Z. Materials come from Look's cache, meshes are shared.

const HAZE := Color(0.56, 0.59, 0.63)
const HAZE_DARK := Color(0.42, 0.45, 0.49)
const HAZE_LIGHT := Color(0.66, 0.69, 0.72)
const GLASS := Color(0.16, 0.2, 0.22)
const RUBBER := Color(0.07, 0.07, 0.08)
const TUG_YELLOW := Color(0.95, 0.74, 0.12)
const DECK_WHITE := Color(0.88, 0.89, 0.9)


static func _no_shadow(n: GeometryInstance3D) -> GeometryInstance3D:
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


static func _part(parent: Node3D, n: Node3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


## A cylinder lying along Z (radius r0 at +Z end, r1 at -Z end).
static func _tube(parent: Node3D, r_back: float, r_front: float, length: float, mat: Material, pos: Vector3, segs: int = 14) -> MeshInstance3D:
	var c := Look.cylinder(r_back, length, mat, Vector3.ZERO, r_front, segs)
	_part(parent, c, pos, Vector3(-PI * 0.5, 0, 0))
	return c


## A generic twin-engine, twin-tail carrier fighter (about 17 m long). `folded` tilts the outer
## wings up. Returns the root; its child "Nozzles" marks the exhaust (for blast effects).
static func jet(folded: bool = false) -> Node3D:
	var root := Node3D.new()
	var body: StandardMaterial3D = Look.flat(HAZE, 0.62, 0.25)
	var dark: StandardMaterial3D = Look.flat(HAZE_DARK, 0.66, 0.25)
	var light: StandardMaterial3D = Look.flat(HAZE_LIGHT, 0.6, 0.2)
	var glass: StandardMaterial3D = Look.flat(GLASS, 0.08, 0.6)
	var black: StandardMaterial3D = Look.flat(RUBBER, 0.8)
	var y: float = 2.1
	# fuselage: centre body, a long tapered nose, the radome, the tapering tail cone
	_tube(root, 1.05, 1.0, 8.0, body, Vector3(0, y, 0.6))
	_tube(root, 1.0, 0.45, 4.2, body, Vector3(0, y + 0.05, -5.5))
	_tube(root, 0.45, 0.06, 1.7, dark, Vector3(0, y + 0.05, -8.45), 12)
	var spine := Look.box(Vector3(1.5, 0.5, 7.5), light, Vector3.ZERO)
	_part(root, spine, Vector3(0, y + 0.85, 0.8))
	# canopy
	var can := Look.sphere(0.62, glass)
	can.scale = Vector3(0.85, 0.72, 2.3)
	_part(root, can, Vector3(0, y + 0.9, -3.6))
	# intakes either side under the canopy rails
	for sx: float in [-1.0, 1.0]:
		_part(root, Look.box(Vector3(0.9, 1.2, 4.0), body, Vector3.ZERO), Vector3(sx * 1.25, y - 0.2, -0.8))
		_part(root, Look.box(Vector3(0.75, 1.0, 0.1), black, Vector3.ZERO), Vector3(sx * 1.25, y - 0.2, -2.82))
	# engines and nozzles
	var noz := Node3D.new()
	noz.name = "Nozzles"
	_part(root, noz, Vector3(0, y - 0.1, 6.8))
	for sx: float in [-1.0, 1.0]:
		_tube(root, 0.62, 0.72, 2.6, dark, Vector3(sx * 0.62, y - 0.1, 5.2))
		_tube(root, 0.56, 0.62, 0.9, Look.flat(Color(0.25, 0.24, 0.23), 0.5, 0.7), Vector3(sx * 0.62, y - 0.1, 6.9))
		var inner := Look.cylinder(0.42, 0.05, Look.flat(Color(0.9, 0.45, 0.2), 0.5, 0.0, 0.8), Vector3.ZERO)
		_part(root, inner, Vector3(sx * 0.62, y - 0.1, 7.3), Vector3(PI * 0.5, 0, 0))
	# wings: swept, with the outer panels folded up when parked
	for sx: float in [-1.0, 1.0]:
		var w := Node3D.new()
		_part(root, w, Vector3(sx * 1.0, y - 0.05, 1.2), Vector3(0, sx * -0.42, 0))
		w.add_child(Look.box(Vector3(3.0, 0.16, 3.6), body, Vector3(sx * 1.5, 0, 0)))
		var outer := Node3D.new()
		outer.position = Vector3(sx * 3.0, 0, 0)
		outer.rotation.z = sx * (1.35 if folded else 0.0)
		w.add_child(outer)
		outer.add_child(Look.box(Vector3(2.4, 0.13, 2.6), body, Vector3(sx * 1.2, 0, 0.3)))
		outer.add_child(Look.box(Vector3(0.12, 0.12, 1.9), dark, Vector3(sx * 2.4, 0.02, 0.4)))
		# leading-edge extension
		_part(root, Look.box(Vector3(0.6, 0.12, 3.0), body, Vector3.ZERO), Vector3(sx * 1.35, y + 0.05, -2.2), Vector3(0, sx * -0.25, 0))
	# twin fins canted outward, and the tailplanes
	for sx: float in [-1.0, 1.0]:
		var fin := Look.box(Vector3(0.14, 2.3, 2.3), light, Vector3.ZERO)
		_part(root, fin, Vector3(sx * 1.05, y + 1.8, 4.9), Vector3(0, 0, sx * -0.35))
		_part(root, Look.box(Vector3(2.5, 0.12, 1.9), body, Vector3.ZERO), Vector3(sx * 2.2, y - 0.1, 6.0), Vector3(0, sx * -0.3, 0))
	# landing gear
	var strut: StandardMaterial3D = Look.flat(Color(0.8, 0.8, 0.82), 0.4, 0.6)
	var gear: Array[Vector3] = [Vector3(0, 0, -5.4), Vector3(-1.5, 0, 1.6), Vector3(1.5, 0, 1.6)]
	for g: Vector3 in gear:
		_part(root, Look.cylinder(0.08, 1.4, strut, Vector3.ZERO), g + Vector3(0, 0.85, 0))
		var wheel := Look.cylinder(0.42 if g.x != 0.0 else 0.32, 0.3, black, Vector3.ZERO, -1.0, 14)
		_part(root, wheel, g + Vector3(0, 0.4 if g.x != 0.0 else 0.32, 0), Vector3(0, 0, PI * 0.5))
	for c: Node in root.get_children():
		if c is GeometryInstance3D and (c as Node3D).position.y < 0.9:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## A utility helicopter (about 15 m long with the tail). `folded` swings the blades back along the
## tail; otherwise returns with a child "Rotor" (spin it about Y) spread.
static func helo(folded: bool = true) -> Node3D:
	var root := Node3D.new()
	var body: StandardMaterial3D = Look.flat(HAZE, 0.6, 0.2)
	var dark: StandardMaterial3D = Look.flat(HAZE_DARK, 0.65, 0.2)
	var glass: StandardMaterial3D = Look.flat(GLASS, 0.08, 0.6)
	var black: StandardMaterial3D = Look.flat(RUBBER, 0.8)
	var y: float = 1.9
	var cab := Look.box(Vector3(2.4, 2.1, 5.2), body, Vector3.ZERO)
	_part(root, cab, Vector3(0, y, 0))
	var nose := Look.sphere(1.15, body)
	nose.scale = Vector3(1.0, 0.9, 1.3)
	_part(root, nose, Vector3(0, y - 0.1, -2.6))
	var wind := Look.sphere(1.0, glass)
	wind.scale = Vector3(1.05, 0.7, 0.9)
	_part(root, wind, Vector3(0, y + 0.35, -2.75))
	_part(root, Look.box(Vector3(1.8, 0.9, 3.0), dark, Vector3.ZERO), Vector3(0, y + 1.45, 0.3))
	_tube(root, 0.55, 0.35, 7.5, body, Vector3(0, y + 0.55, 6.0))
	_part(root, Look.box(Vector3(0.18, 2.2, 1.4), body, Vector3.ZERO), Vector3(0, y + 1.5, 9.6), Vector3(-0.3, 0, 0))
	_part(root, Look.box(Vector3(2.2, 0.12, 0.8), body, Vector3.ZERO), Vector3(0, y + 0.7, 8.6))
	var tr := Look.cylinder(0.9, 0.06, dark, Vector3.ZERO, -1.0, 10)
	_part(root, tr, Vector3(0.2, y + 1.9, 9.8), Vector3(0, 0, PI * 0.5))
	for g: Vector3 in [Vector3(-1.2, 0, -1.6), Vector3(1.2, 0, -1.6), Vector3(0, 0, 7.8)]:
		var wheel := Look.cylinder(0.36, 0.26, black, Vector3.ZERO, -1.0, 12)
		_part(root, wheel, g + Vector3(0, 0.36, 0), Vector3(0, 0, PI * 0.5))
		_part(root, Look.cylinder(0.07, 0.9, Look.flat(Color(0.75, 0.75, 0.77), 0.4, 0.6), Vector3.ZERO), g + Vector3(0, 0.7, 0))
	var hub := Node3D.new()
	hub.name = "Rotor"
	_part(root, hub, Vector3(0, y + 2.05, 0.2))
	hub.add_child(Look.cylinder(0.35, 0.4, dark, Vector3.ZERO))
	var blade: StandardMaterial3D = Look.flat(Color(0.2, 0.21, 0.22), 0.6, 0.3)
	for i: int in 4:
		var a: float = float(i) / 4.0 * TAU
		var arm := Node3D.new()
		arm.rotation.y = (PI + (float(i) - 1.5) * 0.12) if folded else a
		hub.add_child(arm)
		arm.add_child(Look.box(Vector3(0.45, 0.08, 7.6), blade, Vector3(0, 0.05, 3.9)))
	return root


## A low flight-deck tractor (the white spotting dolly). About 3.6 x 2.2 m.
static func tractor() -> Node3D:
	var root := Node3D.new()
	var paint: StandardMaterial3D = Look.flat(DECK_WHITE, 0.6, 0.1)
	var black: StandardMaterial3D = Look.flat(RUBBER, 0.8)
	_part(root, Look.box(Vector3(2.2, 0.8, 3.6), paint, Vector3.ZERO), Vector3(0, 0.75, 0))
	_part(root, Look.box(Vector3(1.9, 0.5, 1.2), Look.flat(Color(0.2, 0.2, 0.22), 0.5), Vector3.ZERO), Vector3(0, 1.35, 0.9))
	_part(root, Look.box(Vector3(1.3, 0.25, 0.9), Look.flat(Color(0.12, 0.12, 0.12), 0.7), Vector3.ZERO), Vector3(0, 1.28, -0.9))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var wheel := Look.cylinder(0.4, 0.34, black, Vector3.ZERO, -1.0, 12)
			_part(root, wheel, Vector3(sx * 1.05, 0.4, sz * 1.15), Vector3(0, 0, PI * 0.5))
	_part(root, Look.box(Vector3(0.2, 0.2, 1.8), Look.flat(Color(0.3, 0.3, 0.3), 0.5, 0.6), Vector3.ZERO), Vector3(0, 0.55, -2.6))
	return root


## A yellow tow tug with a cab and a flashing amber light on top (4.6 x 2.4 m, 2.3 m tall).
## Returns the root; its child "Beacon" can be spun.
static func tug() -> Node3D:
	var root := Node3D.new()
	var paint: StandardMaterial3D = Look.flat(TUG_YELLOW, 0.55, 0.1)
	var dark: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.15), 0.6, 0.3)
	var black: StandardMaterial3D = Look.flat(RUBBER, 0.8)
	var glass: StandardMaterial3D = Look.flat(GLASS, 0.1, 0.5)
	_part(root, Look.box(Vector3(2.4, 1.0, 4.6), paint, Vector3.ZERO), Vector3(0, 0.9, 0))
	_part(root, Look.box(Vector3(2.0, 1.0, 1.8), paint, Vector3.ZERO), Vector3(0, 1.9, 0.9))
	_part(root, Look.box(Vector3(2.02, 0.6, 1.2), glass, Vector3.ZERO), Vector3(0, 2.0, 0.8))
	_part(root, Look.box(Vector3(2.5, 0.25, 0.4), dark, Vector3.ZERO), Vector3(0, 0.55, -2.4))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var wheel := Look.cylinder(0.48, 0.4, black, Vector3.ZERO, -1.0, 12)
			_part(root, wheel, Vector3(sx * 1.2, 0.48, sz * 1.5), Vector3(0, 0, PI * 0.5))
	var bea := Node3D.new()
	bea.name = "Beacon"
	_part(root, bea, Vector3(0, 2.55, 0.9))
	bea.add_child(Look.cylinder(0.14, 0.2, Look.flat(Color(1.0, 0.5, 0.1), 0.3, 0.0, 2.2), Vector3.ZERO))
	return root
