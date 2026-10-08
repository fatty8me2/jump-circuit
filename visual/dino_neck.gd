class_name DinoNeckDress
extends Node3D
## Dino Valley: a brontosaurus's neck, drawn live. The great body (a DinoCreature "bronto") stands beside
## the course; its neck is a chain of tapering cylinders that follows a curve from the shoulder up and
## over to the head - and the head is the moving platform you ride (`mount_head` swaps a mover's looks
## for a flat-topped bronto head). Because the platform moves on the course clock, so does the neck.
## Visual only.

const SKIN := Color(0.55, 0.62, 0.5)

var shoulder: Vector3 = Vector3.ZERO
var target: Node3D
var segments: int = 10
## Where on the target (local) the neck meets the head.
var attach: Vector3 = Vector3(0, -0.2, 1.0)

var _segs: Array[MeshInstance3D] = []
var _joints: Array[MeshInstance3D] = []


## Build a neck from world point `from` to the `head` node.
static func make(parent: Node3D, from: Vector3, head: Node3D, segs: int = 10) -> DinoNeckDress:
	var n := DinoNeckDress.new()
	n.shoulder = from
	n.target = head
	n.segments = segs
	n.top_level = true
	parent.add_child(n)
	n.global_transform = Transform3D.IDENTITY
	n._build()
	return n


func _build() -> void:
	var skin: StandardMaterial3D = Look.flat(SKIN, 0.9)
	for i: int in segments:
		var k0: float = float(i) / float(segments)
		var k1: float = float(i + 1) / float(segments)
		var r0: float = lerpf(1.0, 0.55, k0)
		var r1: float = lerpf(1.0, 0.55, k1)
		var cm := CylinderMesh.new()
		cm.bottom_radius = r0
		cm.top_radius = r1
		cm.height = 1.0
		cm.radial_segments = 12
		cm.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = skin
		add_child(mi)
		_segs.append(mi)
		var jo: MeshInstance3D = Look.sphere(r1, skin)
		add_child(jo)
		_joints.append(jo)
	_update()


func _curve(k: float, p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	var a: Vector3 = p0.lerp(p1, k)
	var b: Vector3 = p1.lerp(p2, k)
	return a.lerp(b, k)


func _update() -> void:
	if target == null or not is_instance_valid(target):
		return
	var p0: Vector3 = shoulder
	var p2: Vector3 = target.global_transform * attach
	var reach: float = Vector2(p2.x - p0.x, p2.z - p0.z).length()
	var p1: Vector3 = p0 + Vector3(0, 3.5 + reach * 0.35 + maxf(p2.y - p0.y, 0.0) * 0.4, 0) + (p2 - p0) * Vector3(0.28, 0.0, 0.28)
	var prev: Vector3 = p0
	for i: int in segments:
		var nxt: Vector3 = _curve(float(i + 1) / float(segments), p0, p1, p2)
		var d: Vector3 = nxt - prev
		var len: float = maxf(d.length(), 0.01)
		_segs[i].transform = Transform3D(Basis(Quaternion(Vector3.UP, d / len)) * Basis.from_scale(Vector3(1, len, 1)), (prev + nxt) * 0.5)
		_joints[i].position = nxt
		prev = nxt


func _process(_dt: float) -> void:
	_update()


## Swap a mover's looks for a brontosaurus head: a flat scaly crown to stand on, the skull and snout
## in front, eyes on the sides, nostrils on the ridge.
static func mount_head(m: MovingPlatform) -> void:
	for ch: Node in m.get_children():
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).visible = false
	var skin: StandardMaterial3D = Look.flat(SKIN, 0.9)
	var dark: StandardMaterial3D = Look.flat(SKIN.darkened(0.35), 0.9)
	var s: Vector3 = m.size
	m.add_child(Look.box(Vector3(s.x, s.y, s.z), skin, Vector3.ZERO))
	var skull: MeshInstance3D = Look.sphere(1.0, skin, Vector3(0, -s.y * 0.5 - 0.35, 0.0))
	skull.scale = Vector3(s.x * 0.5, 0.75, s.z * 0.5)
	m.add_child(skull)
	var snout: MeshInstance3D = Look.sphere(1.0, skin, Vector3(0, -s.y * 0.5 - 0.3, -s.z * 0.5))
	snout.scale = Vector3(s.x * 0.34, 0.55, 0.9)
	m.add_child(snout)
	for sx: float in [-1.0, 1.0]:
		m.add_child(Look.sphere(0.2, Look.flat(Color(0.98, 0.95, 0.8), 0.4), Vector3(sx * s.x * 0.5, -0.05, -s.z * 0.1)))
		m.add_child(Look.sphere(0.1, Look.flat(Color(0.05, 0.04, 0.04), 0.3), Vector3(sx * s.x * 0.55, -0.05, -s.z * 0.14)))
		m.add_child(Look.sphere(0.09, dark, Vector3(sx * 0.18, s.y * 0.5 + 0.02, -s.z * 0.45)))
	for k: int in 4:
		m.add_child(Look.box(Vector3(s.x * 0.85, 0.04, 0.08), dark, Vector3(0, s.y * 0.5 + 0.02, -s.z * 0.2 + float(k) * s.z * 0.18)))
