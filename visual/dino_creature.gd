class_name DinoCreature
extends Node3D
## Dino Valley's cast, built from primitives (visual only: nothing here collides or times anything).
## One script builds every animal: a RAPTOR (a fast two-legged runner, the stampede), the T-REX (the
## chase), a STEGO and an ANKY (plates, spikes, a club tail), a TRIKE, a BRONTO (the great body of the
## neck ride; its neck is a DinoNeckDress) and a PTERO (flapping wings). Forward is local -Z.
## The owner drives the animation: `gait` (radians, advance it with distance walked), `amount`
## (0 still .. 1 full stride), `jaw` (0 shut .. 1 wide open) and `flap` (wing phase). `lod` 1 builds a
## cheap silhouette for far-off herds.

const SKIN_RAPTOR := Color(0.78, 0.56, 0.22)
const BELLY := Color(0.93, 0.84, 0.6)
const SKIN_REX := Color(0.42, 0.5, 0.2)
const SKIN_BRONTO := Color(0.55, 0.62, 0.5)
const SKIN_STEGO := Color(0.5, 0.42, 0.3)
const PLATE := Color(0.95, 0.5, 0.15)
const SKIN_TRIKE := Color(0.5, 0.45, 0.62)
const SKIN_PTERO := Color(0.68, 0.38, 0.28)
const MEMBRANE := Color(0.95, 0.62, 0.3)
const BONE := Color(0.95, 0.92, 0.8)
const DARK := Color(0.07, 0.06, 0.05)

var kind: String = "raptor"
var gait: float = 0.0
var amount: float = 1.0
var jaw: float = 0.0
var flap: float = 0.0
var lod: int = 0
## Extra head-bob and body sway (the rex's heavy tread).
var heavy: float = 0.0
## Radians per second the gait / wing phase advance on their own (0 = the owner drives them).
var auto_gait: float = 0.0
var auto_flap: float = 0.0

var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _tail: Array[Node3D] = []
var _head: Node3D
var _jaw_node: Node3D
var _body: Node3D
var _wings: Array[Node3D] = []
var _tips: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _base_y: float = 0.0
var _anim: bool = true

static var _wing_cache: ArrayMesh


## Build one of the cast. `scale` is applied to the whole creature; `tint` shifts the skin colour.
static func make(kind_id: String, scale: float = 1.0, tint: Color = Color(0, 0, 0, 0), detail: int = 0) -> DinoCreature:
	var d := DinoCreature.new()
	d.kind = kind_id
	d.lod = detail
	d.scale = Vector3.ONE * scale
	match kind_id:
		"rex": d._build_rex(tint)
		"bronto": d._build_bronto(tint)
		"stego": d._build_stego(tint)
		"anky": d._build_anky(tint)
		"trike": d._build_trike(tint)
		"ptero": d._build_ptero(tint)
		_: d._build_raptor(tint)
	return d


# ---- primitives -------------------------------------------------------------------------------

static func _skin(c: Color, rough: float = 0.82) -> StandardMaterial3D:
	return Look.flat(c, rough)


## A shared unit-sphere ellipsoid of radii `r` at `pos` under `parent`.
func _ell(parent: Node3D, r: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var s: MeshInstance3D = Look.sphere(1.0, mat, pos)
	s.scale = r
	parent.add_child(s)
	return s


## A tapered rod from `a` to `b` (radius r0 at a, r1 at b).
func _rod(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, seg: int = 8) -> MeshInstance3D:
	var d: Vector3 = b - a
	var len: float = maxf(d.length(), 0.001)
	var m: MeshInstance3D = Look.cylinder(r0, len, mat, (a + b) * 0.5, r1, seg)
	m.basis = Basis(Quaternion(Vector3.UP, d / len))
	parent.add_child(m)
	return m


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _eye(parent: Node3D, pos: Vector3, r: float) -> void:
	var white: MeshInstance3D = Look.sphere(r, Look.flat(Color(0.98, 0.95, 0.8), 0.4), pos)
	parent.add_child(white)
	var pupil: MeshInstance3D = Look.sphere(r * 0.55, Look.flat(DARK, 0.3), pos + Vector3(signf(pos.x) * r * 0.25, 0, -r * 0.5))
	parent.add_child(pupil)


func _tooth_row(parent: Node3D, z0: float, z1: float, x: float, y: float, up: bool, size: float) -> void:
	var white: StandardMaterial3D = Look.flat(BONE, 0.5)
	var n: int = 5
	for i: int in n:
		var z: float = lerpf(z0, z1, float(i) / float(n - 1))
		for sx: float in [-1.0, 1.0]:
			var t: MeshInstance3D = Look.cylinder(size, size * 3.2, white, Vector3(sx * x, y, z), 0.0, 5)
			if not up:
				t.rotation.x = PI
			parent.add_child(t)


# ---- raptor: the fast runner of the stampede ---------------------------------------------------

func _build_raptor(tint: Color) -> void:
	var col: Color = SKIN_RAPTOR if tint.a == 0.0 else tint
	var skin: StandardMaterial3D = _skin(col)
	var belly: StandardMaterial3D = _skin(BELLY)
	var stripe: StandardMaterial3D = _skin(col.darkened(0.45))
	_body = _node(self, Vector3(0, 1.0, 0))
	_base_y = 1.0
	_ell(_body, Vector3(0.3, 0.34, 0.66), Vector3(0, 0, 0), skin)
	_ell(_body, Vector3(0.24, 0.2, 0.55), Vector3(0, -0.14, -0.05), belly)
	_ell(_body, Vector3(0.24, 0.28, 0.36), Vector3(0, 0.1, -0.46), skin)
	# a dark stripe down the back
	for i: int in 4:
		_ell(_body, Vector3(0.1, 0.05, 0.16), Vector3(0, 0.33 - float(i) * 0.012, -0.1 + float(i) * 0.3), stripe)
	_rod(_body, Vector3(0, 0.2, -0.6), Vector3(0, 0.74, -0.95), 0.11, 0.07, skin)
	_head = _node(_body, Vector3(0, 0.8, -1.02))
	_ell(_head, Vector3(0.12, 0.11, 0.21), Vector3(0, 0, -0.05), skin)
	_ell(_head, Vector3(0.07, 0.06, 0.15), Vector3(0, -0.02, -0.24), belly)
	_eye(_head, Vector3(0.095, 0.045, -0.1), 0.035)
	_eye(_head, Vector3(-0.095, 0.045, -0.1), 0.035)
	var prev: Vector3 = Vector3(0, 0.0, 0.5)
	for i: int in 3:
		var nxt: Vector3 = prev + Vector3(0, -0.06 - 0.02 * float(i), 0.7)
		var seg: Node3D = _node(_body, prev)
		_rod(seg, Vector3.ZERO, nxt - prev, 0.2 - 0.06 * float(i), 0.15 - 0.06 * float(i), skin)
		_tail.append(seg)
		prev = nxt
	if lod == 0:
		for sx: float in [-1.0, 1.0]:
			var arm: Node3D = _node(_body, Vector3(sx * 0.22, 0.02, -0.58))
			_rod(arm, Vector3.ZERO, Vector3(sx * 0.04, -0.26, -0.16), 0.045, 0.03, skin, 5)
			_arms.append(arm)
	for sx: float in [-1.0, 1.0]:
		_leg(self, Vector3(sx * 0.2, 1.0, 0.05), 0.5, 0.5, 0.09, skin, belly, sx)


## A jointed leg: thigh to the knee, shin to the ankle, a foot with three toes. Hangs from `hip`.
func _leg(parent: Node3D, hip: Vector3, thigh: float, shin: float, r: float, mat: Material, foot_mat: Material, side: float) -> void:
	var h: Node3D = _node(parent, hip)
	_rod(h, Vector3.ZERO, Vector3(0, -thigh, -thigh * 0.18), r * 1.25, r, mat, 7)
	var k: Node3D = _node(h, Vector3(0, -thigh, -thigh * 0.18))
	_rod(k, Vector3.ZERO, Vector3(0, -shin * 0.95, shin * 0.25), r, r * 0.7, mat, 7)
	var f: Node3D = _node(k, Vector3(0, -shin * 0.95, shin * 0.25))
	if lod == 0:
		for i: int in 3:
			var a: float = (float(i) - 1.0) * 0.28
			var toe: MeshInstance3D = Look.box(Vector3(r * 0.5, r * 0.5, r * 2.6), foot_mat, Vector3(sin(a) * r * 1.2, -r * 0.2, -r * 1.2))
			toe.rotation.y = a
			f.add_child(toe)
	else:
		f.add_child(Look.box(Vector3(r * 1.4, r * 0.6, r * 2.6), foot_mat, Vector3(0, -r * 0.2, -r * 1.0)))
	_legs.append(h)
	_knees.append(k)
	h.set_meta("side", side)


# ---- t-rex ---------------------------------------------------------------------------------------

func _build_rex(tint: Color) -> void:
	var col: Color = SKIN_REX if tint.a == 0.0 else tint
	var skin: StandardMaterial3D = _skin(col, 0.88)
	var belly: StandardMaterial3D = _skin(col.lightened(0.38).lerp(BELLY, 0.4))
	var dark: StandardMaterial3D = _skin(col.darkened(0.4))
	_body = _node(self, Vector3(0, 2.1, 0))
	_base_y = 2.1
	_ell(_body, Vector3(0.66, 0.72, 1.3), Vector3.ZERO, skin)
	_ell(_body, Vector3(0.5, 0.45, 1.1), Vector3(0, -0.28, -0.05), belly)
	_ell(_body, Vector3(0.56, 0.64, 0.74), Vector3(0, 0.22, -0.95), skin)
	# bumpy dark spine and flank spots
	for i: int in 7:
		_ell(_body, Vector3(0.13, 0.07, 0.2), Vector3(0, 0.7 - absf(float(i) - 3.0) * 0.05, 0.75 - float(i) * 0.3), dark)
	for i: int in 5:
		_ell(_body, Vector3(0.04, 0.16, 0.2), Vector3(0.64 - float(i % 2) * 0.03, 0.2 - float(i) * 0.04, 0.5 - float(i) * 0.28), dark)
		_ell(_body, Vector3(0.04, 0.16, 0.2), Vector3(-0.64 + float(i % 2) * 0.03, 0.2 - float(i) * 0.04, 0.5 - float(i) * 0.28), dark)
	_rod(_body, Vector3(0, 0.4, -1.2), Vector3(0, 0.95, -1.75), 0.44, 0.34, skin, 10)
	# the head: skull, snout, brow, the hinged lower jaw and rows of teeth
	_head = _node(_body, Vector3(0, 0.98, -1.8))
	_ell(_head, Vector3(0.42, 0.36, 0.62), Vector3(0, 0, -0.18), skin)
	var snout: MeshInstance3D = Look.box(Vector3(0.5, 0.3, 0.7), skin, Vector3(0, -0.06, -0.78))
	_head.add_child(snout)
	_ell(_head, Vector3(0.24, 0.12, 0.28), Vector3(0, 0.02, -1.08), skin)
	for sx: float in [-1.0, 1.0]:
		_ell(_head, Vector3(0.11, 0.09, 0.2), Vector3(sx * 0.3, 0.27, -0.28), dark)
		_eye(_head, Vector3(sx * 0.33, 0.18, -0.3), 0.065)
		_ell(_head, Vector3(0.04, 0.03, 0.04), Vector3(sx * 0.12, 0.1, -1.1), dark)
	_tooth_row(_head, -1.08, -0.5, 0.2, -0.24, false, 0.045)
	_jaw_node = _node(_head, Vector3(0, -0.2, -0.34))
	_jaw_node.add_child(Look.box(Vector3(0.44, 0.15, 0.9), belly, Vector3(0, -0.04, -0.4)))
	_ell(_jaw_node, Vector3(0.18, 0.07, 0.14), Vector3(0, -0.04, -0.86), belly)
	_tooth_row(_jaw_node, -0.8, -0.2, 0.17, 0.05, true, 0.04)
	# the useless little arms
	for sx: float in [-1.0, 1.0]:
		var arm: Node3D = _node(_body, Vector3(sx * 0.5, -0.22, -1.1))
		_rod(arm, Vector3.ZERO, Vector3(sx * 0.06, -0.38, -0.32), 0.1, 0.07, skin, 6)
		for i: int in 2:
			arm.add_child(Look.cylinder(0.025, 0.14, Look.flat(BONE, 0.5), Vector3(sx * 0.06 + (float(i) - 0.5) * 0.07, -0.45, -0.42), 0.0, 5))
		_arms.append(arm)
	var prev: Vector3 = Vector3(0, 0.1, 1.0)
	for i: int in 5:
		var nxt: Vector3 = prev + Vector3(0, -0.12 - 0.03 * float(i), 0.95)
		var seg: Node3D = _node(_body, prev)
		_rod(seg, Vector3.ZERO, nxt - prev, 0.5 - 0.09 * float(i), 0.41 - 0.09 * float(i), skin, 9)
		_tail.append(seg)
		prev = nxt
	for sx: float in [-1.0, 1.0]:
		var thigh: MeshInstance3D = _ell(_body, Vector3(0.34, 0.6, 0.55), Vector3(sx * 0.55, -0.2, 0.38), skin)
		thigh.rotation.x = 0.2
		_leg(self, Vector3(sx * 0.55, 1.95, 0.4), 1.0, 0.95, 0.24, skin, dark, sx)


# ---- bronto: the great body (its neck is a DinoNeckDress) ---------------------------------------

func _build_bronto(tint: Color) -> void:
	var col: Color = SKIN_BRONTO if tint.a == 0.0 else tint
	var skin: StandardMaterial3D = _skin(col, 0.9)
	var belly: StandardMaterial3D = _skin(col.lightened(0.25))
	var dark: StandardMaterial3D = _skin(col.darkened(0.35))
	_body = _node(self, Vector3(0, 3.4, 0))
	_base_y = 3.4
	_ell(_body, Vector3(1.7, 1.45, 3.1), Vector3.ZERO, skin)
	_ell(_body, Vector3(1.4, 0.9, 2.6), Vector3(0, -0.6, 0), belly)
	for i: int in 6:
		_ell(_body, Vector3(0.5, 0.18, 0.5), Vector3((float(i % 2) - 0.5) * 0.9, 1.35, -1.6 + float(i) * 0.65), dark)
	# the neck stub rises from the shoulders (the DinoNeckDress continues it)
	_rod(_body, Vector3(0, 0.6, -2.4), Vector3(0, 1.4, -3.3), 0.9, 0.7, skin, 12)
	var prev: Vector3 = Vector3(0, 0.1, 2.8)
	for i: int in 6:
		var nxt: Vector3 = prev + Vector3(0, -0.28 - 0.08 * float(i), 1.5)
		var seg: Node3D = _node(_body, prev)
		_rod(seg, Vector3.ZERO, nxt - prev, 1.0 - 0.15 * float(i), 0.85 - 0.15 * float(i), skin, 10)
		_tail.append(seg)
		prev = nxt
	# four pillar legs with round feet
	for sz: float in [-1.7, 1.9]:
		for sx: float in [-1.0, 1.0]:
			var h: Node3D = _node(self, Vector3(sx * 1.25, 3.0, sz))
			_rod(h, Vector3.ZERO, Vector3(0, -2.9, 0), 0.62, 0.52, skin, 10)
			var foot: MeshInstance3D = Look.cylinder(0.78, 0.4, dark, Vector3(0, -3.0, 0), 0.7, 10)
			h.add_child(foot)
			_legs.append(h)
			h.set_meta("side", sx * (1.0 if sz < 0.0 else -1.0))
	_anim = false


# ---- stego / anky / trike ---------------------------------------------------------------------------

func _build_stego(tint: Color) -> void:
	var col: Color = SKIN_STEGO if tint.a == 0.0 else tint
	var skin: StandardMaterial3D = _skin(col, 0.9)
	var plate: StandardMaterial3D = _skin(PLATE, 0.6)
	_body = _node(self, Vector3(0, 1.4, 0))
	_base_y = 1.4
	_ell(_body, Vector3(0.75, 0.8, 1.7), Vector3.ZERO, skin)
	for i: int in 7:
		var h: float = 0.55 + 0.35 * sin(float(i) / 6.0 * PI)
		var pl: MeshInstance3D = Look.box(Vector3(0.1, h, 0.42), plate, Vector3((float(i % 2) - 0.5) * 0.28, 0.75 + h * 0.4, -1.1 + float(i) * 0.38))
		pl.rotation.z = (float(i % 2) - 0.5) * 0.35
		_body.add_child(pl)
	_rod(_body, Vector3(0, 0.0, -1.5), Vector3(0, -0.15, -2.2), 0.3, 0.22, skin, 8)
	_head = _node(_body, Vector3(0, -0.2, -2.25))
	_ell(_head, Vector3(0.2, 0.17, 0.32), Vector3(0, 0, -0.1), skin)
	_eye(_head, Vector3(0.15, 0.05, -0.15), 0.04)
	_eye(_head, Vector3(-0.15, 0.05, -0.15), 0.04)
	var prev: Vector3 = Vector3(0, 0.1, 1.5)
	for i: int in 3:
		var nxt: Vector3 = prev + Vector3(0, 0.02, 1.0)
		var seg: Node3D = _node(_body, prev)
		_rod(seg, Vector3.ZERO, nxt - prev, 0.4 - 0.1 * float(i), 0.3 - 0.1 * float(i), skin)
		for sx: float in [-1.0, 1.0]:
			seg.add_child(Look.cylinder(0.07, 0.6, Look.flat(BONE, 0.5), Vector3(sx * 0.25, 0.0, 0.5), 0.0, 5))
			(seg.get_child(seg.get_child_count() - 1) as Node3D).rotation.z = -sx * 1.2
		_tail.append(seg)
		prev = nxt
	for sz: float in [-1.0, 1.2]:
		for sx: float in [-1.0, 1.0]:
			_leg(self, Vector3(sx * 0.55, 1.1, sz), 0.55, 0.5, 0.17, skin, skin, sx)


func _build_anky(tint: Color) -> void:
	var col: Color = Color(0.45, 0.4, 0.28) if tint.a == 0.0 else tint
	var skin: StandardMaterial3D = _skin(col, 0.92)
	var spike: StandardMaterial3D = _skin(BONE, 0.5)
	_body = _node(self, Vector3(0, 0.9, 0))
	_base_y = 0.9
	_ell(_body, Vector3(1.0, 0.6, 1.5), Vector3.ZERO, skin)
	for i: int in 9:
		var a: float = float(i) / 8.0
		for sx: float in [-1.0, 1.0]:
			var sp: MeshInstance3D = Look.cylinder(0.12, 0.45, spike, Vector3(sx * (0.95 - 0.35 * sin(a * PI)), 0.15 + 0.4 * sin(a * PI), -1.1 + 2.2 * a), 0.0, 6)
			sp.rotation.z = -sx * (0.9 - 0.5 * sin(a * PI))
			_body.add_child(sp)
	_head = _node(_body, Vector3(0, -0.15, -1.55))
	_ell(_head, Vector3(0.38, 0.26, 0.4), Vector3(0, 0, -0.15), skin)
	_eye(_head, Vector3(0.22, 0.1, -0.3), 0.05)
	_eye(_head, Vector3(-0.22, 0.1, -0.3), 0.05)
	var prev: Vector3 = Vector3(0, 0.0, 1.3)
	for i: int in 3:
		var nxt: Vector3 = prev + Vector3(0, 0.0, 0.9)
		var seg: Node3D = _node(_body, prev)
		_rod(seg, Vector3.ZERO, nxt - prev, 0.5 - 0.12 * float(i), 0.38 - 0.12 * float(i), skin)
		_tail.append(seg)
		prev = nxt
	_ell(_body, Vector3(0.5, 0.42, 0.5), prev + Vector3(0, 0.0, 0.3), skin)
	for sx: float in [-1.0, 1.0]:
		var sp2: MeshInstance3D = Look.cylinder(0.14, 0.5, spike, prev + Vector3(sx * 0.5, 0.0, 0.3), 0.0, 6)
		sp2.rotation.z = -sx * PI * 0.5
		_body.add_child(sp2)
	for sz: float in [-0.9, 0.9]:
		for sx: float in [-1.0, 1.0]:
			_leg(self, Vector3(sx * 0.7, 0.55, sz), 0.28, 0.3, 0.16, skin, skin, sx)


func _build_trike(tint: Color) -> void:
	var col: Color = SKIN_TRIKE if tint.a == 0.0 else tint
	var skin: StandardMaterial3D = _skin(col, 0.88)
	var frill: StandardMaterial3D = _skin(col.lightened(0.18).lerp(PLATE, 0.3), 0.7)
	var horn: StandardMaterial3D = _skin(BONE, 0.4)
	_body = _node(self, Vector3(0, 1.3, 0))
	_base_y = 1.3
	_ell(_body, Vector3(0.9, 0.85, 1.7), Vector3.ZERO, skin)
	_head = _node(_body, Vector3(0, 0.0, -1.7))
	_ell(_head, Vector3(0.5, 0.45, 0.8), Vector3(0, -0.05, -0.35), skin)
	_ell(_head, Vector3(0.22, 0.2, 0.3), Vector3(0, -0.12, -1.0), skin)
	var shield: MeshInstance3D = Look.cylinder(1.0, 0.14, frill, Vector3(0, 0.35, 0.18), 0.85, 18)
	shield.rotation.x = PI * 0.5 - 0.5
	shield.scale = Vector3(1.0, 1.0, 0.85)
	_head.add_child(shield)
	for sx: float in [-1.0, 1.0]:
		var h: MeshInstance3D = Look.cylinder(0.1, 1.0, horn, Vector3(sx * 0.36, 0.42, -0.9), 0.0, 6)
		h.rotation.x = -1.15
		_head.add_child(h)
		_eye(_head, Vector3(sx * 0.42, 0.1, -0.55), 0.06)
	var nose: MeshInstance3D = Look.cylinder(0.08, 0.36, horn, Vector3(0, 0.1, -1.3), 0.0, 6)
	nose.rotation.x = -0.9
	_head.add_child(nose)
	var prev: Vector3 = Vector3(0, 0.0, 1.5)
	for i: int in 2:
		var nxt: Vector3 = prev + Vector3(0, -0.1, 0.9)
		var seg: Node3D = _node(_body, prev)
		_rod(seg, Vector3.ZERO, nxt - prev, 0.45 - 0.14 * float(i), 0.3 - 0.14 * float(i), skin)
		_tail.append(seg)
		prev = nxt
	for sz: float in [-1.0, 1.1]:
		for sx: float in [-1.0, 1.0]:
			_leg(self, Vector3(sx * 0.7, 1.0, sz), 0.5, 0.5, 0.2, skin, skin, sx)


# ---- ptero ------------------------------------------------------------------------------------------

static func _wing_mesh() -> ArrayMesh:
	if _wing_cache != null:
		return _wing_cache
	# a leathery wing in the local +X direction: shoulder, wrist, tip and the trailing edge back to the body
	var pts: Array[Vector3] = [Vector3(0, 0, -0.35), Vector3(1.5, 0.12, -0.2), Vector3(3.3, 0.05, 0.55), Vector3(2.4, 0, 0.9),
		Vector3(1.4, 0, 0.75), Vector3(0.0, 0, 0.7)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris: Array = [[0, 1, 5], [1, 4, 5], [1, 2, 4], [2, 3, 4]]
	for t: Array in tris:
		for k: int in 3:
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[int(t[k])])
	_wing_cache = st.commit()
	return _wing_cache


func _build_ptero(tint: Color) -> void:
	var col: Color = SKIN_PTERO if tint.a == 0.0 else tint
	var skin: StandardMaterial3D = _skin(col, 0.8)
	var mem := StandardMaterial3D.new()
	mem.albedo_color = MEMBRANE if tint.a == 0.0 else tint.lightened(0.3)
	mem.roughness = 0.7
	mem.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body = _node(self, Vector3.ZERO)
	_ell(_body, Vector3(0.28, 0.24, 0.75), Vector3.ZERO, skin)
	_ell(_body, Vector3(0.2, 0.15, 0.5), Vector3(0, -0.12, -0.05), _skin(BELLY))
	_rod(_body, Vector3(0, 0.05, -0.55), Vector3(0, 0.25, -0.95), 0.12, 0.09, skin, 6)
	_head = _node(_body, Vector3(0, 0.27, -1.0))
	_ell(_head, Vector3(0.13, 0.12, 0.22), Vector3(0, 0, -0.05), skin)
	_rod(_head, Vector3(0, -0.02, -0.15), Vector3(0, -0.05, -1.05), 0.07, 0.025, _skin(BONE.darkened(0.3), 0.5), 6)
	var crest: MeshInstance3D = Look.box(Vector3(0.04, 0.2, 0.7), skin, Vector3(0, 0.12, 0.38))
	crest.rotation.x = 0.35
	_head.add_child(crest)
	_eye(_head, Vector3(0.1, 0.04, -0.1), 0.03)
	_eye(_head, Vector3(-0.1, 0.04, -0.1), 0.03)
	for sx: float in [-1.0, 1.0]:
		var w: Node3D = _node(_body, Vector3(sx * 0.18, 0.12, -0.1))
		var wm := MeshInstance3D.new()
		wm.mesh = _wing_mesh()
		wm.material_override = mem
		var side: Node3D = _node(w, Vector3.ZERO)
		side.scale = Vector3(sx, 1.0, 1.0)
		side.add_child(wm)
		_rod(side, Vector3(0, 0, -0.35), Vector3(1.5, 0.12, -0.2), 0.05, 0.04, skin, 5)
		_rod(side, Vector3(1.5, 0.12, -0.2), Vector3(3.3, 0.05, 0.55), 0.04, 0.02, skin, 5)
		_wings.append(w)
	_tail.append(_node(_body, Vector3(0, 0, 0.65)))
	_rod(_tail[0], Vector3.ZERO, Vector3(0, -0.03, 0.55), 0.06, 0.02, skin, 5)
	flap = randf() * TAU


# ---- animation --------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if not _anim:
		return
	gait += auto_gait * dt
	flap += auto_flap * dt
	pose()


## Set every joint for the current gait / jaw / flap values (also callable by the owner).
func pose() -> void:
	if kind == "ptero":
		for i: int in _wings.size():
			var s: float = 1.0 if i == 0 else -1.0
			_wings[i].rotation.z = -s * sin(flap) * 0.6
		if _head != null:
			_head.rotation.x = sin(flap + 1.0) * 0.06
		return
	var a: float = clampf(amount, 0.0, 1.0)
	for i: int in _legs.size():
		var h: Node3D = _legs[i]
		var side: float = float(h.get_meta("side", 1.0))
		var off: float = 0.0 if side > 0.0 else PI
		if kind == "stego" or kind == "trike" or kind == "anky":
			off += PI * 0.5 if (i >= 2) else 0.0
		var sw: float = sin(gait + off)
		h.rotation.x = sw * 0.55 * a
		if i < _knees.size():
			_knees[i].rotation.x = maxf(0.0, -cos(gait + off)) * 0.95 * a
	if _body != null and kind != "bronto":
		_body.position.y = _base_y + (absf(sin(gait)) * 0.07 * a if kind == "rex" or kind == "raptor" else 0.0)
		_body.rotation.z = sin(gait) * 0.035 * heavy * a
	for i: int in _tail.size():
		_tail[i].rotation.y = sin(gait * 0.5 + float(i) * 0.7) * 0.12 * a * (1.0 + heavy)
	if _head != null and kind == "raptor":
		_head.rotation.x = sin(gait * 2.0) * 0.08 * a
	if _head != null and kind == "rex":
		_head.rotation.x = -jaw * 0.1 + sin(gait * 2.0) * 0.04 * a
	if _jaw_node != null:
		_jaw_node.rotation.x = -jaw * 0.62
	for i: int in _arms.size():
		_arms[i].rotation.x = sin(gait * 2.0 + float(i)) * 0.15 * a
