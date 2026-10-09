class_name DinoDecor
extends RefCounted
## Dino Valley set dressing (visual only: nothing here collides or times anything): sandstone stacks
## under every landing, tall mesas capped with forest, conifers, tree ferns, cycads and ground ferns,
## fossil bones in the tar fields, boulders, rock arches, waterfalls, the nest, and the valley floor with
## its river and forests (MultiMesh, so a thousand trees cost a handful of draw calls).
## Shared materials come from Look.flat's cache, so identical pieces batch.

const STRATA: Array = [Color(0.72, 0.52, 0.32), Color(0.62, 0.4, 0.26), Color(0.82, 0.68, 0.46), Color(0.55, 0.36, 0.24), Color(0.76, 0.58, 0.38)]
const BARK := Color(0.4, 0.28, 0.17)
const GREENS: Array = [Color(0.2, 0.42, 0.14), Color(0.28, 0.5, 0.16), Color(0.16, 0.36, 0.14), Color(0.34, 0.54, 0.18)]
const BONE := Color(0.93, 0.9, 0.78)

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, random: RandomNumberGenerator) -> void:
	root = level_root
	rng = random


func _green() -> Color:
	return GREENS[rng.randi() % GREENS.size()]


func _add(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	root.add_child(n)
	return n


## A tapered rod between two points under `parent`.
func _rod(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, seg: int = 7) -> void:
	var d: Vector3 = b - a
	var len: float = maxf(d.length(), 0.001)
	var m: MeshInstance3D = Look.cylinder(r0, len, mat, (a + b) * 0.5, r1, seg)
	m.basis = Basis(Quaternion(Vector3.UP, d / len))
	parent.add_child(m)


# ---- stone -------------------------------------------------------------------------------------------

## A stack of rock strata from `top` (the underside of a landing) down `depth` metres, `half` (x, z) wide
## at the top and narrowing: bands of ochre, rust and cream. Visual only.
func pillar(top: Vector3, half: Vector2, depth: float, tint: float = 0.0) -> void:
	var n := Node3D.new()
	_add(n, top)
	var bands: int = clampi(int(depth / 3.2), 1, 14)
	var y: float = 0.0
	var r0: float = maxf(half.x, half.y) * 0.9
	for i: int in bands:
		var h: float = depth / float(bands)
		var r1: float = r0 * rng.randf_range(0.86, 0.98)
		var c: Color = (STRATA[(i + rng.randi() % 2) % STRATA.size()] as Color).lerp(Color(0.4, 0.34, 0.26), tint)
		var seg: MeshInstance3D = Look.cylinder(r0, h, Look.flat(c, 0.95), Vector3(0, y - h * 0.5, 0), r1, 8)
		seg.rotation.y = rng.randf() * TAU
		n.add_child(seg)
		y -= h
		r0 = r1


## A big mesa rising from the valley floor: strata walls, a grassy cap with a grove on it. `base` is the
## floor point, `r` its radius, `h` its height.
func mesa(base: Vector3, r: float, h: float, trees: int = 6) -> void:
	var n := Node3D.new()
	_add(n, base)
	var bands: int = clampi(int(h / 6.0), 2, 12)
	var y: float = 0.0
	var rr: float = r
	for i: int in bands:
		var bh: float = h / float(bands)
		var r1: float = rr * (1.0 if i < bands - 1 else 0.96) * rng.randf_range(0.92, 1.04)
		var c: Color = STRATA[i % STRATA.size()]
		var seg: MeshInstance3D = Look.cylinder(r1, bh, Look.flat(c, 0.95), Vector3(0, y + bh * 0.5, 0), rr, 10)
		seg.rotation.y = rng.randf() * TAU
		n.add_child(seg)
		y += bh
		rr = r1
	n.add_child(Look.cylinder(rr * 1.02, 0.8, Look.flat(Color(0.34, 0.54, 0.2), 0.9), Vector3(0, h + 0.2, 0), rr * 0.96, 10))
	for k: int in trees:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.0, rr * 0.8)
		var p := Vector3(cos(a) * d, h + 0.5, sin(a) * d)
		var roll: float = rng.randf()
		if roll < 0.4:
			_conifer_into(n, p, rng.randf_range(10.0, 20.0))
		elif roll < 0.75:
			_tree_fern_into(n, p, rng.randf_range(6.0, 10.0))
		else:
			_cycad_into(n, p, rng.randf_range(2.5, 4.0))


## A block of canyon wall: a big box in the grass-and-strata shader (its sides are the strata).
func cliff(center: Vector3, size: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/dino_ground.gdshader")
	m.set_shader_parameter("half_size", size * 0.5)
	m.set_shader_parameter("top_color", Color(0.4, 0.58, 0.2))
	m.set_shader_parameter("side_color", Color(0.66, 0.46, 0.28))
	m.set_shader_parameter("trim_color", Color(1.0, 0.74, 0.28))
	mi.material_override = m
	mi.position = center
	root.add_child(mi)
	for k: int in 3:
		_conifer_into(root, center + Vector3(rng.randf_range(-size.x, size.x) * 0.35, size.y * 0.5, rng.randf_range(-size.z, size.z) * 0.4), rng.randf_range(8.0, 14.0))


## A natural rock arch: two strata legs and a lintel (`w` wide, `h` tall).
func arch(base: Vector3, yaw: float, w: float, h: float) -> void:
	var n := Node3D.new()
	_add(n, base)
	n.rotation.y = yaw
	for sx: float in [-1.0, 1.0]:
		for i: int in 4:
			var c: Color = STRATA[(i + (1 if sx < 0.0 else 0)) % STRATA.size()]
			n.add_child(Look.cylinder(2.4 - 0.2 * float(i), h / 4.0, Look.flat(c, 0.95), Vector3(sx * w * 0.5, h / 8.0 + float(i) * h / 4.0, 0), 2.6 - 0.2 * float(i), 8))
	for i2: int in 3:
		n.add_child(Look.box(Vector3(w + 4.0 - 0.8 * float(i2), h * 0.12, 4.2 - 0.6 * float(i2)), Look.flat(STRATA[(i2 + 2) % STRATA.size()], 0.95), Vector3(0, h + float(i2) * h * 0.12, 0)))


func boulder(pos: Vector3, r: float) -> void:
	var n := Node3D.new()
	_add(n, pos)
	var rock: StandardMaterial3D = Look.flat(Color(0.5, 0.46, 0.4), 0.95)
	for i: int in 3:
		var s: MeshInstance3D = Look.sphere(1.0, rock if i != 1 else Look.flat(Color(0.42, 0.4, 0.35), 0.95), Vector3(rng.randf_range(-0.5, 0.5) * r, r * 0.1 * float(i), rng.randf_range(-0.5, 0.5) * r))
		s.scale = Vector3(r * rng.randf_range(0.6, 1.0), r * rng.randf_range(0.5, 0.8), r * rng.randf_range(0.6, 1.0))
		n.add_child(s)


# ---- plants ----------------------------------------------------------------------------------------------

func _conifer_into(parent: Node3D, base: Vector3, h: float) -> void:
	var bark: StandardMaterial3D = Look.flat(BARK, 0.95)
	parent.add_child(Look.cylinder(h * 0.035, h * 0.45, bark, base + Vector3(0, h * 0.22, 0), h * 0.025, 6))
	var col: Color = _green()
	var tiers: int = 4
	for i: int in tiers:
		var k: float = float(i) / float(tiers)
		var cone: MeshInstance3D = Look.cylinder(h * 0.2 * (1.0 - k * 0.55), h * 0.34, Look.flat(col.lightened(0.04 * float(i)), 0.9), base + Vector3(0, h * (0.3 + 0.19 * float(i)), 0), 0.02, 8)
		parent.add_child(cone)


func conifer(base: Vector3, h: float) -> void:
	var n := Node3D.new()
	_add(n, base)
	_conifer_into(n, Vector3.ZERO, h)


func _tree_fern_into(parent: Node3D, base: Vector3, h: float) -> void:
	var bark: StandardMaterial3D = Look.flat(BARK.lightened(0.05), 0.95)
	_rod(parent, base, base + Vector3(rng.randf_range(-0.5, 0.5), h, rng.randf_range(-0.5, 0.5)), h * 0.05, h * 0.035, bark, 6)
	var top: Vector3 = base + Vector3(0, h, 0)
	var leaf: StandardMaterial3D = Look.flat(_green(), 0.8)
	for i: int in 9:
		var a: float = TAU * float(i) / 9.0
		var len: float = h * 0.55
		var frond: MeshInstance3D = Look.box(Vector3(len * 0.42, 0.04, len), leaf, top + Vector3(cos(a), 0.0, sin(a)) * len * 0.45 + Vector3(0, -len * 0.12, 0))
		frond.rotation = Vector3(0.0, -a + PI * 0.5, 0.0)
		frond.rotate_object_local(Vector3.RIGHT, 0.45)
		parent.add_child(frond)


func tree_fern(base: Vector3, h: float) -> void:
	var n := Node3D.new()
	_add(n, base)
	_tree_fern_into(n, Vector3.ZERO, h)


func _cycad_into(parent: Node3D, base: Vector3, h: float) -> void:
	var trunk: StandardMaterial3D = Look.flat(Color(0.34, 0.26, 0.18), 0.95)
	parent.add_child(Look.cylinder(h * 0.2, h * 0.7, trunk, base + Vector3(0, h * 0.35, 0), h * 0.16, 8))
	for k: int in 3:
		parent.add_child(Look.cylinder(h * 0.22, 0.12, Look.flat(Color(0.26, 0.2, 0.14), 0.95), base + Vector3(0, h * (0.15 + 0.2 * float(k)), 0), -1.0, 8))
	var leaf: StandardMaterial3D = Look.flat(_green().darkened(0.05), 0.8)
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0
		var fr: MeshInstance3D = Look.box(Vector3(0.16 * h, 0.03, h * 0.9), leaf, base + Vector3(cos(a) * h * 0.35, h * 0.78, sin(a) * h * 0.35))
		fr.rotation = Vector3(0.0, -a + PI * 0.5, 0.0)
		fr.rotate_object_local(Vector3.RIGHT, 0.7)
		parent.add_child(fr)


func cycad(base: Vector3, h: float) -> void:
	var n := Node3D.new()
	_add(n, base)
	_cycad_into(n, Vector3.ZERO, h)


func fern(base: Vector3, s: float = 1.0) -> void:
	var n := Node3D.new()
	_add(n, base)
	var leaf: StandardMaterial3D = Look.flat(_green(), 0.8)
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + rng.randf() * 0.4
		var fr: MeshInstance3D = Look.box(Vector3(0.28 * s, 0.025, 1.6 * s), leaf, Vector3(cos(a), 0.3 * s, sin(a)) * 0.6 * s)
		fr.rotation = Vector3(0.0, -a + PI * 0.5, 0.0)
		fr.rotate_object_local(Vector3.RIGHT, 0.6)
		n.add_child(fr)


## Horsetails: clumps of tall segmented green stalks.
func horsetail(base: Vector3, h: float) -> void:
	var n := Node3D.new()
	_add(n, base)
	var mat: StandardMaterial3D = Look.flat(Color(0.4, 0.55, 0.22), 0.85)
	var ring: StandardMaterial3D = Look.flat(Color(0.28, 0.4, 0.16), 0.9)
	for i: int in 7:
		var p := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		var hh: float = h * rng.randf_range(0.6, 1.0)
		n.add_child(Look.cylinder(0.05, hh, mat, p + Vector3(0, hh * 0.5, 0), 0.03, 5))
		for k: int in 4:
			n.add_child(Look.cylinder(0.075, 0.05, ring, p + Vector3(0, hh * (0.2 + 0.2 * float(k)), 0), -1.0, 6))


# ---- bones, eggs, the nest -----------------------------------------------------------------------------------

## A mammoth-sized rib cage arching out of the ground (dressing for the wall-run panels and the tar).
func ribs(base: Vector3, yaw: float, s: float = 1.0, count: int = 6) -> void:
	var n := Node3D.new()
	_add(n, base)
	n.rotation.y = yaw
	var bone: StandardMaterial3D = Look.flat(BONE, 0.7)
	for i: int in count:
		var z: float = (float(i) - float(count - 1) * 0.5) * 1.1 * s
		var h: float = (2.6 - absf(float(i) - float(count - 1) * 0.5) * 0.35) * s
		for sx: float in [-1.0, 1.0]:
			var prev := Vector3(sx * 0.2 * s, 0.0, z)
			for j: int in 5:
				var t: float = float(j + 1) / 5.0
				var nxt := Vector3(sx * (0.2 + sin(t * PI * 0.5) * 1.4) * s, sin(t * PI * 0.9) * h, z)
				_rod(n, prev, nxt, 0.11 * s, 0.09 * s, bone, 6)
				prev = nxt
	n.add_child(Look.cylinder(0.14 * s, count * 1.1 * s, bone, Vector3(0, 0.1, 0), -1.0, 6))
	n.get_child(n.get_child_count() - 1).rotation.x = PI * 0.5


## A dinosaur skull half sunk in the ground, jaws open.
func skull(base: Vector3, yaw: float, s: float = 1.0) -> void:
	var n := Node3D.new()
	_add(n, base)
	n.rotation.y = yaw
	var bone: StandardMaterial3D = Look.flat(BONE, 0.65)
	var dark: StandardMaterial3D = Look.flat(Color(0.12, 0.1, 0.08), 0.9)
	var cr: MeshInstance3D = Look.sphere(1.0, bone, Vector3(0, 0.7 * s, 0.4 * s))
	cr.scale = Vector3(0.8, 0.7, 1.1) * s
	n.add_child(cr)
	var sn: MeshInstance3D = Look.box(Vector3(0.85, 0.55, 1.6) * s, bone, Vector3(0, 0.55 * s, -1.0 * s))
	n.add_child(sn)
	for sx: float in [-1.0, 1.0]:
		var eye: MeshInstance3D = Look.sphere(0.22 * s, dark, Vector3(sx * 0.5 * s, 0.9 * s, 0.1 * s))
		n.add_child(eye)
	for i: int in 6:
		var tooth: MeshInstance3D = Look.cylinder(0.07 * s, 0.4 * s, bone, Vector3(0.38 * s * (1.0 if i % 2 == 0 else -1.0), 0.22 * s, (-0.4 - 0.25 * float(i)) * s), 0.0, 5)
		tooth.rotation.x = PI
		n.add_child(tooth)


func egg(pos: Vector3, r: float) -> void:
	var e: MeshInstance3D = Look.sphere(r, Look.flat(Color(0.94, 0.92, 0.8), 0.5), pos)
	e.scale = Vector3(0.8, 1.15, 0.8)
	root.add_child(e)


# ---- water ------------------------------------------------------------------------------------------------------

## A waterfall pouring down a mesa face: a pale streaming sheet, a splash pool and mist at the foot.
func waterfall(top: Vector3, face: Vector3, h: float, w: float) -> void:
	var n := Node3D.new()
	_add(n, top)
	n.rotation.y = atan2(-face.x, -face.z) + PI
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://visual/dino_falls.gdshader")
	var sheet: MeshInstance3D = Look.box(Vector3(w, h, 0.5), mat, Vector3(0, -h * 0.5, 0.3))
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(sheet)
	var foot: Vector3 = n.global_position + Vector3(0, -h, 0.6)
	DinoFx.mist(root, foot + Vector3(0, 1.5, 3.0), Vector3(w * 0.7, 1.5, 4.0), 6)
	var spray: GPUParticles3D = Fx.smoke({"amount": 18, "lifetime": 2.0, "shape": "box", "extents": Vector3(w * 0.4, 0.3, 0.6), "dir": Vector3.UP,
		"spread": 40.0, "speed": Vector2(1.0, 3.0), "size": 3.0, "color": Color(0.96, 0.98, 1.0, 0.5), "aabb": AABB(Vector3(-30, -5, -30), Vector3(60, 40, 60))})
	spray.position = foot
	root.add_child(spray)


# ---- the valley floor -------------------------------------------------------------------------------------------

## The valley floor plane (meadow, forest patches, a river) centred on `center` at height `y`.
func valley(center: Vector3, size: float, y: float) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/dino_valley.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(center.x, y, center.z)
	root.add_child(mi)


## `count` trees scattered over a square on the valley floor as two MultiMeshes (cones and round crowns).
func forest(center: Vector3, half: float, count: int, y: float) -> void:
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = 0.0
	cmesh.bottom_radius = 2.2
	cmesh.height = 9.0
	cmesh.radial_segments = 6
	cmesh.rings = 1
	var smesh := SphereMesh.new()
	smesh.radius = 3.4
	smesh.height = 6.0
	smesh.radial_segments = 8
	smesh.rings = 4
	var cmat: StandardMaterial3D = Look.flat(Color(0.14, 0.32, 0.14), 0.95)
	var smat: StandardMaterial3D = Look.flat(Color(0.26, 0.48, 0.16), 0.95)
	var mm1 := MultiMesh.new()
	mm1.transform_format = MultiMesh.TRANSFORM_3D
	mm1.mesh = cmesh
	mm1.instance_count = count
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = smesh
	mm2.instance_count = count / 2
	for i: int in count:
		var p := Vector3(center.x + rng.randf_range(-half, half), y + 4.5, center.z + rng.randf_range(-half, half))
		var s: float = rng.randf_range(0.7, 1.6)
		mm1.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), p))
	for j: int in count / 2:
		var p2 := Vector3(center.x + rng.randf_range(-half, half), y + 3.0, center.z + rng.randf_range(-half, half))
		var s2: float = rng.randf_range(0.7, 1.5)
		mm2.set_instance_transform(j, Transform3D(Basis.from_scale(Vector3(s2, s2, s2)), p2))
	var a := MultiMeshInstance3D.new()
	a.multimesh = mm1
	a.material_override = cmat
	a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(a)
	var b := MultiMeshInstance3D.new()
	b.multimesh = mm2
	b.material_override = smat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(b)
