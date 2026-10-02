class_name VoidDecor
extends RefCounted
## The Void's set dressing: impossible dream architecture in clean white against the violet dark,
## picked out in pink and cyan. Floating doors (some ajar, light spilling out), classical arches,
## Escher flights of stairs at every angle, giant clocks with no hands, rooms hanging upside down
## with their furniture, mirrors, chess pieces and slivers of the broken sky. All visual (no
## collision), built from shared Look meshes and a handful of materials.

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.32, 0.9, 1.0)
const WHITE := Color(0.92, 0.9, 0.97)
const BONE := Color(0.82, 0.79, 0.88)
const INK := Color(0.12, 0.09, 0.18)

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


func _white() -> StandardMaterial3D:
	return Look.flat(WHITE, 0.45)


func _bone() -> StandardMaterial3D:
	return Look.flat(BONE, 0.6)


func _ink() -> StandardMaterial3D:
	return Look.flat(INK, 0.5)


func _glow(col: Color, e: float = 2.6) -> StandardMaterial3D:
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


# ---- doors, arches, stairs -----------------------------------------------------------------------

## A free-standing door in its frame, floating in the dark: the door swung open `open` radians,
## light of `col` spilling through the gap. `pos` is the middle of the threshold.
func door(pos: Vector3, b: Basis, w: float = 1.6, h: float = 2.9, col: Color = PINK, open: float = 0.6) -> Node3D:
	var n: Node3D = _node(pos, b)
	var fm: StandardMaterial3D = _white()
	_put(n, Look.box(Vector3(0.18, h + 0.18, 0.3), fm, Vector3(-w * 0.5 - 0.09, h * 0.5, 0)))
	_put(n, Look.box(Vector3(0.18, h + 0.18, 0.3), fm, Vector3(w * 0.5 + 0.09, h * 0.5, 0)))
	_put(n, Look.box(Vector3(w + 0.54, 0.22, 0.34), fm, Vector3(0, h + 0.1, 0)))
	_put(n, Look.box(Vector3(w + 0.3, 0.08, 0.4), fm, Vector3(0, 0.0, 0)))
	# the light in the doorway (a soft glowing sheet just behind the door's plane)
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.albedo_color = Color(col.r, col.g, col.b, 0.55)
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	_put(n, Look.mesh_node(q, lm, Vector3(0, h * 0.5, 0.02)), true)
	# the door on its hinge (left post), with a knob
	var hinge := Node3D.new()
	hinge.position = Vector3(-w * 0.5, 0, 0)
	hinge.rotation.y = -open
	n.add_child(hinge)
	_put(hinge, Look.box(Vector3(w, h - 0.04, 0.08), _bone(), Vector3(w * 0.5, h * 0.5, 0)))
	for i: int in 2:
		_put(hinge, Look.box(Vector3(w * 0.72, h * 0.32, 0.02), Look.flat(WHITE.darkened(0.08), 0.5), Vector3(w * 0.5, h * (0.28 + 0.42 * float(i)), 0.05)))
	_put(hinge, Look.sphere(0.06, _glow(col, 2.0), Vector3(w * 0.88, h * 0.48, 0.08)))
	return n


## A classical arch: two columns and a round head of voussoirs. `pos` = the middle of its base.
func arch(pos: Vector3, b: Basis, w: float = 3.0, h: float = 4.0, col: Color = CYAN) -> Node3D:
	var n: Node3D = _node(pos, b)
	var m: StandardMaterial3D = _white()
	var r: float = w * 0.5
	var leg: float = maxf(h - r, 0.5)
	for sx: float in [-1.0, 1.0]:
		_put(n, Look.cylinder(0.24, leg, m, Vector3(sx * r, leg * 0.5, 0), 0.2, 12))
		_put(n, Look.box(Vector3(0.62, 0.18, 0.62), m, Vector3(sx * r, 0.09, 0)))
		_put(n, Look.box(Vector3(0.6, 0.16, 0.6), m, Vector3(sx * r, leg + 0.08, 0)))
	var k: int = 9
	for i: int in k:
		var a: float = PI * (float(i) + 0.5) / float(k)
		var v := Look.box(Vector3(0.5, r * PI / float(k) + 0.04, 0.5), m, Vector3(cos(a) * r, leg + sin(a) * r, 0))
		v.rotation.z = a
		_put(n, v)
	_put(n, Look.box(Vector3(0.3, 0.3, 0.52), _glow(col, 2.4), Vector3(0, leg + r + 0.05, 0)), true)
	return n


## A flight of stairs going nowhere, at any angle. `pos` = the foot of the flight.
func stairs(pos: Vector3, b: Basis, steps: int = 8, w: float = 1.6, rise: float = 0.3, run: float = 0.45) -> Node3D:
	var n: Node3D = _node(pos, b)
	var m: StandardMaterial3D = _white()
	var side: StandardMaterial3D = _bone()
	for i: int in steps:
		_put(n, Look.box(Vector3(w, rise, run), m, Vector3(0, rise * (float(i) + 0.5), -run * (float(i) + 0.5))))
	# the stringer underneath, a slanted slab
	var slen: float = sqrt(pow(rise * float(steps), 2.0) + pow(run * float(steps), 2.0))
	var s := Look.box(Vector3(w * 0.96, 0.22, slen), side, Vector3(0, rise * float(steps) * 0.5 - 0.2, -run * float(steps) * 0.5))
	s.rotation.x = atan2(rise, run)
	_put(n, s)
	# a thin glowing edge on every tread nose
	var g: StandardMaterial3D = _glow(PINK if rng.randf() < 0.5 else CYAN, 2.0)
	for i2: int in steps:
		_put(n, Look.box(Vector3(w, 0.03, 0.03), g, Vector3(0, rise * float(i2 + 1) + 0.005, -run * float(i2))), true)
	return n


# ---- clocks, rooms, mirrors, chess ---------------------------------------------------------------

## A giant clock with no hands: a pale face, a dark rim, twelve marks. Lying at any angle (local Y
## is the face's normal). `melt` > 0 droops it like wax over an edge.
func clock(pos: Vector3, b: Basis, r: float = 2.5, melt: float = 0.0) -> Node3D:
	var n: Node3D = _node(pos, b)
	var body := Node3D.new()
	body.scale = Vector3(1.0, 1.0, 1.0 + melt)
	body.position = Vector3(0, 0, r * melt * 0.5)
	n.add_child(body)
	_put(body, Look.cylinder(r, 0.18, Look.flat(Color(0.95, 0.93, 0.88), 0.55), Vector3.ZERO, -1.0, 40))
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.94
	tm.outer_radius = r * 1.06
	tm.rings = 40
	tm.ring_segments = 8
	var rim := Look.mesh_node(tm, Look.flat(Color(0.2, 0.16, 0.3), 0.35, 0.4))
	rim.scale = Vector3(1, 1.8, 1)
	_put(body, rim)
	var mk: StandardMaterial3D = _ink()
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0
		var big: bool = i % 3 == 0
		var t := Look.box(Vector3(0.08 if not big else 0.16, 0.04, r * (0.12 if not big else 0.2)), mk, Vector3(cos(a), 0, sin(a)) * r * 0.8 + Vector3(0, 0.1, 0))
		t.rotation.y = -a + PI * 0.5
		_put(body, t)
	# the empty spindle where the hands should be
	_put(body, Look.cylinder(r * 0.05, 0.3, _glow(PINK, 2.2), Vector3(0, 0.12, 0), -1.0, 12), true)
	return n


## A room hanging upside down in the void: its floor (a chessboard, facing down) on top, two walls
## hanging from it - one with a lit window - and its furniture dangling from the floor.
func upside_room(pos: Vector3, yaw: float, w: float = 6.0, d: float = 5.0, h: float = 3.2) -> Node3D:
	var n: Node3D = _node(pos, turn(yaw))
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = preload("res://visual/void_tile.gdshader")
	floor_mat.set_shader_parameter("half_size", Vector3(w * 0.5, 0.2, d * 0.5))
	floor_mat.set_shader_parameter("top_color", WHITE)
	floor_mat.set_shader_parameter("side_color", BONE)
	floor_mat.set_shader_parameter("trim_color", PINK)
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.4, d)
	var fl := Look.mesh_node(bm, floor_mat, Vector3(0, 0, 0))
	fl.rotation.x = PI
	_put(n, fl)
	var wall: StandardMaterial3D = Look.flat(Color(0.86, 0.8, 0.9), 0.7)
	_put(n, Look.box(Vector3(w, h, 0.16), wall, Vector3(0, -h * 0.5 - 0.2, -d * 0.5 + 0.08)))
	_put(n, Look.box(Vector3(0.16, h, d), wall, Vector3(-w * 0.5 + 0.08, -h * 0.5 - 0.2, 0)))
	# a skirting board along the top (it is the floor's edge, upside down) and the window
	_put(n, Look.box(Vector3(w, 0.14, 0.2), _glow(CYAN, 1.4), Vector3(0, -0.3, -d * 0.5 + 0.18)), true)
	_put(n, Look.box(Vector3(1.4, 1.1, 0.06), _glow(Color(1.0, 0.82, 0.6), 1.8), Vector3(w * 0.15, -h * 0.55, -d * 0.5 + 0.18)), true)
	_put(n, Look.box(Vector3(0.06, 1.1, 0.1), _white(), Vector3(w * 0.15, -h * 0.55, -d * 0.5 + 0.2)))
	# the table and chair hanging from the floor
	var tb := Vector3(w * 0.1, -0.2, d * 0.1)
	_put(n, Look.box(Vector3(1.4, 0.08, 0.9), _bone(), tb + Vector3(0, -0.8, 0)))
	for sx: float in [-0.6, 0.6]:
		for sz: float in [-0.35, 0.35]:
			_put(n, Look.box(Vector3(0.06, 0.76, 0.06), _bone(), tb + Vector3(sx, -0.38, sz)))
	var ch := tb + Vector3(-1.4, 0, 0.3)
	_put(n, Look.box(Vector3(0.5, 0.06, 0.5), _bone(), ch + Vector3(0, -0.5, 0)))
	for sx2: float in [-0.2, 0.2]:
		for sz2: float in [-0.2, 0.2]:
			_put(n, Look.box(Vector3(0.05, 0.48, 0.05), _bone(), ch + Vector3(sx2, -0.24, sz2)))
	_put(n, Look.box(Vector3(0.5, 0.6, 0.05), _bone(), ch + Vector3(0, -0.85, 0.22)))
	# a lamp standing on the floor, i.e. pointing down, still lit
	_put(n, Look.cylinder(0.03, 1.2, _ink(), Vector3(w * 0.32, -0.8, d * 0.25), -1.0, 6))
	_put(n, Look.cylinder(0.3, 0.35, _glow(Color(1.0, 0.85, 0.6), 2.2), Vector3(w * 0.32, -1.5, d * 0.25), 0.15, 12), true)
	return n


## A tall standing mirror in a white frame (local -Z is its face).
func mirror(pos: Vector3, b: Basis, w: float = 2.0, h: float = 3.4) -> Node3D:
	var n: Node3D = _node(pos, b)
	_put(n, Look.box(Vector3(w + 0.3, h + 0.3, 0.16), _white(), Vector3(0, 0, 0.06)))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.82, 0.84, 0.95)
	glass.metallic = 1.0
	glass.roughness = 0.04
	_put(n, Look.box(Vector3(w, h, 0.04), glass, Vector3(0, 0, -0.04)))
	_put(n, Look.box(Vector3(w + 0.36, 0.06, 0.06), _glow(CYAN, 2.0), Vector3(0, h * 0.5 + 0.18, -0.06)), true)
	return n


## A chess piece (pawn or rook), white or black, `s` m tall-ish.
func chess(pos: Vector3, s: float = 2.0, white: bool = true, rook: bool = false) -> Node3D:
	var n: Node3D = _node(pos)
	var m: StandardMaterial3D = Look.flat(WHITE if white else Color(0.16, 0.12, 0.22), 0.35, 0.1)
	_put(n, Look.cylinder(0.42 * s, 0.14 * s, m, Vector3(0, 0.07 * s, 0), 0.38 * s, 20))
	_put(n, Look.cylinder(0.3 * s, 0.1 * s, m, Vector3(0, 0.19 * s, 0), 0.3 * s, 20))
	if rook:
		_put(n, Look.cylinder(0.24 * s, 0.7 * s, m, Vector3(0, 0.59 * s, 0), 0.2 * s, 16))
		_put(n, Look.cylinder(0.3 * s, 0.22 * s, m, Vector3(0, 1.04 * s, 0), -1.0, 16))
		for i: int in 4:
			var a: float = TAU * float(i) / 4.0
			_put(n, Look.box(Vector3(0.14, 0.14, 0.14) * s, m, Vector3(cos(a), 0, sin(a)) * 0.22 * s + Vector3(0, 1.2 * s, 0)))
	else:
		_put(n, Look.cylinder(0.2 * s, 0.6 * s, m, Vector3(0, 0.54 * s, 0), 0.1 * s, 16))
		_put(n, Look.cylinder(0.22 * s, 0.06 * s, m, Vector3(0, 0.86 * s, 0), -1.0, 16))
		_put(n, Look.sphere(0.2 * s, m, Vector3(0, 1.04 * s, 0)))
	return n


## A sliver of the broken sky drifting in the dark: a thin pale shard with a glowing seam.
func sky_shard(pos: Vector3, size: float, b: Basis) -> Node3D:
	var n: Node3D = _node(pos, b)
	var pm := PrismMesh.new()
	pm.size = Vector3(size, size * 1.6, 0.08)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.36, 0.22, 0.5)
	glass.metallic = 0.6
	glass.roughness = 0.1
	glass.emission_enabled = true
	glass.emission = Color(0.5, 0.3, 0.7)
	glass.emission_energy_multiplier = 0.4
	_put(n, Look.mesh_node(pm, glass), true)
	_put(n, Look.box(Vector3(size, 0.05, 0.1), _glow(PINK if rng.randf() < 0.5 else CYAN, 2.2), Vector3(0, -size * 0.8, 0)), true)
	n.set_script(preload("res://visual/spin.gd"))
	n.set("period", rng.randf_range(30.0, 70.0) * (1.0 if rng.randf() < 0.5 else -1.0))
	n.set("axis", Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized())
	return n


## A slim white column under a landing, broken off below (the posts' support). `top` = under the slab.
func column(top: Vector3, r: float, length: float) -> void:
	var n: Node3D = _node(top)
	_put(n, Look.box(Vector3(r * 2.6, 0.16, r * 2.6), _white(), Vector3(0, -0.08, 0)))
	_put(n, Look.cylinder(r * 0.8, length, _white(), Vector3(0, -length * 0.5 - 0.16, 0), r, 10))
	# the broken end: a few chunks drifting loose beneath it
	for i: int in 3:
		var c := Look.box(Vector3.ONE * r * rng.randf_range(0.7, 1.2), _bone(), Vector3(rng.randf_range(-0.3, 0.3), -length - 0.6 - 0.9 * float(i), rng.randf_range(-0.3, 0.3)))
		c.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		_put(n, c)


## A tapering white keel under a big slab: an upturned stepped pyramid, the floor of a lost room.
func keel(top: Vector3, sx: float, sz: float, depth: float) -> void:
	var n: Node3D = _node(top)
	var steps: int = 4
	for i: int in steps:
		var k: float = 1.0 - float(i + 1) / float(steps + 1)
		_put(n, Look.box(Vector3(sx * k, depth / float(steps), sz * k), _white() if i % 2 == 0 else _bone(), Vector3(0, -depth / float(steps) * (float(i) + 0.5), 0)))
	_put(n, Look.box(Vector3(sx * 0.18, 0.05, sz * 0.18), _glow(PINK, 2.0), Vector3(0, -depth - 0.03, 0)), true)


# ---- far scenery ---------------------------------------------------------------------------------

## A colossal Escher knot of stairs: four flights joined at right angles, each turned so that up
## and down disagree. Far scenery.
func escher(pos: Vector3, s: float) -> Node3D:
	var n: Node3D = _node(pos, turn(rng.randf() * TAU, rng.randf_range(-0.4, 0.4), rng.randf_range(-0.3, 0.3)))
	var m: StandardMaterial3D = _white()
	var steps: int = 6
	var rise: float = 0.5 * s
	var run: float = 0.7 * s
	var w: float = 2.2 * s
	var corners: Array[Vector3] = [Vector3(0, 0, 0), Vector3(-w * 3.0, 0, 0), Vector3(-w * 3.0, 0, w * 3.0), Vector3(0, 0, w * 3.0)]
	for f: int in 4:
		var flight := Node3D.new()
		flight.position = corners[f]
		flight.rotation = Vector3(0, PI * 0.5 * float(f), PI * 0.5 * float(f % 2))
		n.add_child(flight)
		for i: int in steps:
			_put(flight, Look.box(Vector3(w, rise, run), m, Vector3(0, rise * (float(i) + 0.5), -run * (float(i) + 0.5))))
		_put(flight, Look.box(Vector3(w, 0.06 * s, 0.06 * s), _glow(PINK if f % 2 == 0 else CYAN, 1.6), Vector3(0, rise * float(steps), -run * float(steps - 1))), true)
	return n


## A great floating door far off, ajar onto a pale glow (far scenery).
func giant_door(pos: Vector3, yaw: float, s: float) -> void:
	var d: Node3D = door(pos, turn(yaw), 1.6 * s, 3.0 * s, PINK if rng.randf() < 0.5 else CYAN, rng.randf_range(0.3, 1.1))
	d.rotation.z = rng.randf_range(-0.25, 0.25)
