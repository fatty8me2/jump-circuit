class_name SiegeDecor
extends RefCounted
## Castle Siege's set dressing: a medieval castle at dusk under siege. Grey ashlar towers with conical
## slate roofs and glowing arrow-slits, crenellated curtain walls, a gatehouse, the great keep, tents
## and palisades of the besiegers' camp, trebuchets and siege towers, braziers and campfires, and
## banners of crimson and gold rippling in the smoke-wind. All visual (no collision), built from
## shared Look meshes, a handful of materials and MultiMeshes for the merlons and windows.

const STONE := Color(0.46, 0.43, 0.41)
const STONE_DARK := Color(0.27, 0.25, 0.25)
const TIMBER := Color(0.34, 0.23, 0.15)
const SLATE := Color(0.22, 0.2, 0.26)
const CRIMSON := Color(0.74, 0.1, 0.12)
const GOLD := Color(0.95, 0.72, 0.2)
const IRON := Color(0.16, 0.16, 0.18)
const WINDOW := Color(1.0, 0.62, 0.2)

var root: Node3D
var rng: RandomNumberGenerator

static var _banner_shader: Shader
static var _merlon_mesh: BoxMesh
static var _slit_mesh: BoxMesh


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


static func turn(yaw: float, pitch: float = 0.0, roll: float = 0.0) -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, roll))


func _stone() -> StandardMaterial3D:
	return Look.flat(STONE, 0.92)


func _dark() -> StandardMaterial3D:
	return Look.flat(STONE_DARK, 0.92)


func _wood() -> StandardMaterial3D:
	return Look.flat(TIMBER, 0.9)


func _iron() -> StandardMaterial3D:
	return Look.flat(IRON, 0.45, 0.7)


func _glow(col: Color, e: float = 2.4) -> StandardMaterial3D:
	return Look.flat(col, 0.4, 0.0, e)


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


## A MultiMesh of one mesh at many transforms (merlons, slits).
func _multi(parent: Node3D, mesh: Mesh, mat: Material, xf: Array[Transform3D], shadow: bool = true) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i: int in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


func _merlon() -> BoxMesh:
	if _merlon_mesh == null:
		_merlon_mesh = BoxMesh.new()
		_merlon_mesh.size = Vector3(0.9, 0.9, 0.7)
	return _merlon_mesh


func _slit() -> BoxMesh:
	if _slit_mesh == null:
		_slit_mesh = BoxMesh.new()
		_slit_mesh.size = Vector3(0.22, 0.9, 0.08)
	return _slit_mesh


# ---- supports under the walkable pieces -----------------------------------------------------------

## A stone shaft hanging under a small floor (a pier of masonry running down into the smoke).
func column(under: Vector3, radius: float, length: float) -> void:
	var n: Node3D = _node(under)
	var r: float = maxf(radius, 0.28)
	_put(n, Look.cylinder(r * 1.5, 0.5, _dark(), Vector3(0, -0.25, 0), r * 1.1, 8))
	_put(n, Look.cylinder(r * 1.0, length, _stone(), Vector3(0, -0.5 - length * 0.5, 0), r * 0.82, 8))
	for k: int in int(length / 3.2):
		_put(n, Look.cylinder(r * 1.1, 0.14, _dark(), Vector3(0, -1.6 - 3.2 * float(k), 0), -1.0, 8))


## A masonry body hanging under a large floor, stepped in like a corbelled tower base.
func keel(under: Vector3, sx: float, sz: float, depth: float) -> void:
	var n: Node3D = _node(under)
	var stone: StandardMaterial3D = _stone()
	var steps: int = 3
	for i: int in steps:
		var k: float = 1.0 - 0.2 * float(i)
		var h: float = depth / float(steps)
		_put(n, Look.box(Vector3(sx * k, h, sz * k), stone if i % 2 == 0 else _dark(), Vector3(0, -h * (float(i) + 0.5), 0)))


# ---- banners, fires, small props ----------------------------------------------------------------------

func _cloth_mat(col: Color, seed_v: float, wave: float = 0.14) -> ShaderMaterial:
	if _banner_shader == null:
		_banner_shader = preload("res://visual/siege_banner.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _banner_shader
	m.set_shader_parameter("field", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("seed", seed_v)
	m.set_shader_parameter("wave", wave)
	return m


## A banner on a pole: `base` is the pole's foot, the cloth hangs from a crossbar near the top.
func banner(base: Vector3, height: float, yaw: float, col: Color = CRIMSON, w: float = 1.3, h: float = 2.8) -> Node3D:
	var n: Node3D = _node(base, turn(yaw))
	_put(n, Look.cylinder(0.09, height, _wood(), Vector3(0, height * 0.5, 0), 0.07, 6))
	_put(n, Look.sphere(0.14, _glow(GOLD, 1.2), Vector3(0, height + 0.05, 0)), true)
	_put(n, Look.box(Vector3(w + 0.3, 0.1, 0.1), _wood(), Vector3(w * 0.5 + 0.1, height - 0.3, 0)))
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.subdivide_width = 3
	q.subdivide_depth = 8
	var cloth := Look.mesh_node(q, _cloth_mat(col, rng.randf() * 6.0), Vector3(w * 0.5 + 0.1, height - 0.35 - h * 0.5, 0))
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(cloth)
	return n


## A banner hung flat down a wall face (the cloth faces local +Z of `b`).
func wall_banner(pos: Vector3, b: Basis, col: Color, w: float = 2.2, h: float = 6.0) -> void:
	var n: Node3D = _node(pos, b)
	_put(n, Look.cylinder(0.08, w + 0.5, _iron(), Vector3(0, 0, 0), -1.0, 6)).rotation.z = PI * 0.5
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.subdivide_width = 3
	q.subdivide_depth = 8
	var cloth := Look.mesh_node(q, _cloth_mat(col, rng.randf() * 6.0, 0.18), Vector3(0, -h * 0.5 - 0.05, 0.1))
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(cloth)


## An iron fire basket on a tripod standing on a floor point, burning (a flame, no light).
func brazier(foot: Vector3, size: float = 1.0, light: bool = false) -> Node3D:
	var n: Node3D = _node(foot)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var leg := Look.box(Vector3(0.06, 0.9 * size, 0.06), _iron(), Vector3(cos(a) * 0.2 * size, 0.42 * size, sin(a) * 0.2 * size))
		leg.rotation = Vector3(sin(a) * 0.22, 0, -cos(a) * 0.22)
		n.add_child(leg)
	n.add_child(Look.cylinder(0.34 * size, 0.2 * size, _iron(), Vector3(0, 0.95 * size, 0), 0.2 * size, 10))
	var coals := Look.sphere(0.25 * size, _glow(Color(1.0, 0.45, 0.1), 3.0), Vector3(0, 1.08 * size, 0))
	coals.scale = Vector3(1, 0.5, 1)
	coals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(coals)
	SiegeFx.flicker(n, Vector3(0, 1.15 * size, 0))
	if light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.2)
		l.light_energy = 1.4
		l.omni_range = 8.0
		l.shadow_enabled = false
		l.position = Vector3(0, 1.6 * size, 0)
		n.add_child(l)
	return n


## A campfire on the ground with stones and logs (for the besiegers' camp).
func campfire(base: Vector3) -> void:
	var n: Node3D = _node(base)
	for i: int in 7:
		var a: float = TAU * float(i) / 7.0
		n.add_child(Look.sphere(0.16, _dark(), Vector3(cos(a) * 0.65, 0.1, sin(a) * 0.65)))
	for i: int in 3:
		var log := Look.cylinder(0.08, 0.9, _wood(), Vector3.ZERO, -1.0, 6)
		log.position = Vector3(0, 0.14, 0)
		log.rotation = Vector3(PI * 0.5, 0, TAU * float(i) / 3.0)
		n.add_child(log)
	SiegeFx.fire(n, Vector3(0, 0.3, 0), 1.3)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.18)
	l.light_energy = 1.6
	l.omni_range = 11.0
	l.shadow_enabled = false
	l.position = Vector3(0, 1.4, 0)
	n.add_child(l)


## A stack of barrels and crates.
func supplies(base: Vector3, yaw: float) -> void:
	var n: Node3D = _node(base, turn(yaw))
	var barrel_m: StandardMaterial3D = _wood()
	for i: int in 3:
		var b := Look.cylinder(0.42, 0.95, barrel_m, Vector3(float(i) * 0.9, 0.48, 0), 0.36, 10)
		n.add_child(b)
		n.add_child(Look.cylinder(0.43, 0.08, _iron(), Vector3(float(i) * 0.9, 0.3, 0), -1.0, 10))
		n.add_child(Look.cylinder(0.43, 0.08, _iron(), Vector3(float(i) * 0.9, 0.7, 0), -1.0, 10))
	n.add_child(Look.box(Vector3(0.9, 0.8, 0.9), Look.flat(Color(0.45, 0.32, 0.2), 0.9), Vector3(0.4, 0.4, 1.0)))
	n.add_child(Look.box(Vector3(0.7, 0.7, 0.7), Look.flat(Color(0.4, 0.28, 0.18), 0.9), Vector3(0.5, 1.15, 1.0)))


## Sharpened stakes in a row (a besiegers' palisade / defensive line), along local X.
func stakes(base: Vector3, yaw: float, count: int, spacing: float = 0.7, height: float = 2.0) -> void:
	var n: Node3D = _node(base, turn(yaw))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.7
	cone.radial_segments = 6
	for i: int in count:
		var x: float = (float(i) - float(count - 1) * 0.5) * spacing
		var h: float = height * rng.randf_range(0.85, 1.15)
		n.add_child(Look.cylinder(0.14, h, _wood(), Vector3(x, h * 0.5, 0), 0.12, 6))
		var tip := Look.mesh_node(cone, _wood(), Vector3(x, h + 0.3, 0))
		n.add_child(tip)


# ---- towers, walls, gatehouse, keep ------------------------------------------------------------------------

## A round tower from `base` (foot centre): crenellated top or a conical slate roof, glowing slits.
func tower(base: Vector3, r: float, h: float, roof: bool = true, flag: Color = CRIMSON) -> Node3D:
	var n: Node3D = _node(base)
	_put(n, Look.cylinder(r * 1.12, 1.2, _dark(), Vector3(0, 0.6, 0), r * 1.04, 16))
	_put(n, Look.cylinder(r, h, _stone(), Vector3(0, h * 0.5, 0), r * 0.94, 16))
	# corbel ring under the parapet
	_put(n, Look.cylinder(r * 1.2, 0.5, _dark(), Vector3(0, h - 0.1, 0), r * 1.0, 16))
	var xf: Array[Transform3D] = []
	var slits: Array[Transform3D] = []
	var merl_n: int = maxi(int(TAU * r * 1.2 / 1.7), 6)
	for i: int in merl_n:
		var a: float = TAU * float(i) / float(merl_n)
		xf.append(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a) * (r * 1.12), h + 0.65, sin(a) * (r * 1.12))))
	var levels: int = maxi(int(h / 9.0), 1)
	for lv: int in levels:
		var y: float = h * (0.3 + 0.55 * float(lv) / float(maxi(levels, 1)))
		for k: int in 3:
			var a2: float = TAU * (float(k) / 3.0 + float(lv) * 0.17) + 0.4
			slits.append(Transform3D(Basis(Vector3.UP, -a2 + PI * 0.5), Vector3(cos(a2) * r * 0.97, y, sin(a2) * r * 0.97)))
	_multi(n, _merlon(), _stone(), xf)
	_multi(n, _slit(), _glow(WINDOW, 2.6), slits, false)
	_put(n, Look.cylinder(r * 1.12, 0.3, _dark(), Vector3(0, h + 0.1, 0), r * 1.12, 16))
	if roof:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = r * 1.3
		cone.height = r * 2.4
		cone.radial_segments = 16
		_put(n, Look.mesh_node(cone, Look.flat(SLATE, 0.6, 0.1), Vector3(0, h + 0.3 + r * 1.2, 0)))
		var ring := Look.cylinder(r * 1.31, 0.18, _glow(CRIMSON, 0.8), Vector3(0, h + 0.5, 0), -1.0, 16)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_put(n, ring)
		_put(n, Look.cylinder(0.05, 2.0, _iron(), Vector3(0, h + 0.3 + r * 2.4 + 0.8, 0), -1.0, 5))
		var q := QuadMesh.new()
		q.size = Vector2(1.6, 0.9)
		q.subdivide_width = 4
		q.subdivide_depth = 1
		var fl := Look.mesh_node(q, _cloth_mat(flag, rng.randf() * 6.0, 0.25), Vector3(0.85, h + 0.3 + r * 2.4 + 1.4, 0))
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(fl)
	return n


## A curtain wall along local X (length), `h` tall, `thick` deep, crenellated on both edges, with slits
## and a few torches. `base` = middle of the foot.
func wall(base: Vector3, yaw: float, length: float, h: float, thick: float = 3.2) -> Node3D:
	var n: Node3D = _node(base, turn(yaw))
	_put(n, Look.box(Vector3(length, h, thick), _stone(), Vector3(0, h * 0.5, 0)))
	_put(n, Look.box(Vector3(length + 0.4, 0.7, thick + 0.5), _dark(), Vector3(0, h - 0.1, 0)))
	_put(n, Look.box(Vector3(length + 0.4, 1.4, thick + 0.4), _dark(), Vector3(0, 0.7, 0)))
	var xf: Array[Transform3D] = []
	var slits: Array[Transform3D] = []
	var count: int = int(length / 1.9)
	for i: int in count:
		var x: float = (float(i) + 0.5) / float(count) * length - length * 0.5
		for sz: float in [-1.0, 1.0]:
			xf.append(Transform3D(Basis.IDENTITY, Vector3(x, h + 0.65, sz * (thick * 0.5 + 0.1))))
		if i % 3 == 1:
			slits.append(Transform3D(Basis.IDENTITY, Vector3(x, h * 0.62, thick * 0.5 + 0.03)))
	_multi(n, _merlon(), _stone(), xf)
	_multi(n, _slit(), _glow(WINDOW, 2.4), slits, false)
	return n


## A twin-towered gatehouse (a gate arch between two round towers) facing local +Z. `base` = foot centre.
func gatehouse(base: Vector3, yaw: float, w: float = 12.0, h: float = 26.0) -> Node3D:
	var n: Node3D = _node(base, turn(yaw))
	_put(n, Look.box(Vector3(w, h * 0.78, 6.0), _stone(), Vector3(0, h * 0.39, 0)))
	# the gate: a dark arch with a raised portcullis and a lit slit above
	_put(n, Look.box(Vector3(w * 0.32, h * 0.34, 0.5), Look.flat(Color(0.03, 0.02, 0.02), 1.0), Vector3(0, h * 0.17, 3.0)), true)
	_put(n, Look.cylinder(w * 0.16, 0.5, Look.flat(Color(0.03, 0.02, 0.02), 1.0), Vector3(0, h * 0.34, 3.0), -1.0, 14), true).rotation.x = PI * 0.5
	var teeth: float = w * 0.32
	for i: int in 6:
		_put(n, Look.box(Vector3(0.1, 2.4, 0.12), _iron(), Vector3(-teeth * 0.5 + teeth * (float(i) + 0.5) / 6.0, h * 0.34 + 1.2, 3.1)), true)
	for sx: float in [-1.0, 1.0]:
		tower_in(n, Vector3(sx * (w * 0.5 + 1.5), 0, 0), 3.6, h * 1.08)
	var xf: Array[Transform3D] = []
	for i: int in int(w / 1.9):
		var x: float = (float(i) + 0.5) / float(int(w / 1.9)) * w - w * 0.5
		xf.append(Transform3D(Basis.IDENTITY, Vector3(x, h * 0.78 + 0.45, 2.8)))
	_multi(n, _merlon(), _stone(), xf)
	wall_banner_in(n, Vector3(0, h * 0.62, 3.1), CRIMSON, 3.2, 7.0)
	return n


func tower_in(parent: Node3D, off: Vector3, r: float, h: float) -> void:
	var keep_root: Node3D = root
	root = parent
	tower(off, r, h, true, CRIMSON)
	root = keep_root


func wall_banner_in(parent: Node3D, off: Vector3, col: Color, w: float, h: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.subdivide_width = 3
	q.subdivide_depth = 8
	var cloth := Look.mesh_node(q, _cloth_mat(col, rng.randf() * 6.0, 0.18), off + Vector3(0, -h * 0.5, 0.1))
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cloth)


## The great keep: a tall square tower with corner turrets, a stepped roofline, many lit slits and big
## banners. `base` = foot centre, w = width, h = height.
func keep(base: Vector3, yaw: float, w: float, h: float) -> Node3D:
	var n: Node3D = _node(base, turn(yaw))
	_put(n, Look.box(Vector3(w, h, w), _stone(), Vector3(0, h * 0.5, 0)))
	for i: int in 4:
		var y: float = h * (0.25 + 0.2 * float(i))
		_put(n, Look.box(Vector3(w + 0.8, 0.8, w + 0.8), _dark(), Vector3(0, y, 0)))
	_put(n, Look.box(Vector3(w + 2.0, 1.4, w + 2.0), _dark(), Vector3(0, h + 0.3, 0)))
	var xf: Array[Transform3D] = []
	var slits: Array[Transform3D] = []
	var per: int = int((w + 2.0) / 1.9)
	for i: int in per:
		var x: float = (float(i) + 0.5) / float(per) * (w + 2.0) - (w + 2.0) * 0.5
		for s: float in [-1.0, 1.0]:
			xf.append(Transform3D(Basis.IDENTITY, Vector3(x, h + 1.45, s * (w * 0.5 + 1.0))))
			xf.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(s * (w * 0.5 + 1.0), h + 1.45, x)))
	for lv: int in 6:
		var y2: float = h * (0.1 + 0.15 * float(lv))
		for k: int in 3:
			var x2: float = (float(k) - 1.0) * w * 0.28
			slits.append(Transform3D(Basis.IDENTITY, Vector3(x2, y2, w * 0.5 + 0.03)))
			slits.append(Transform3D(Basis.IDENTITY, Vector3(x2, y2 + 1.0, -w * 0.5 - 0.03)))
			slits.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5 + 0.03, y2 + 0.5, x2)))
			slits.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-w * 0.5 - 0.03, y2 + 0.5, x2)))
	_multi(n, _merlon(), _stone(), xf)
	_multi(n, _slit(), _glow(WINDOW, 2.6), slits, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			tower_in(n, Vector3(sx * (w * 0.5 + 0.2), 0, sz * (w * 0.5 + 0.2)), 2.6, h * 1.08)
	return n


# ---- the besiegers: tents, siege engines ---------------------------------------------------------------------

## A canvas tent (a ridge tent) with a pennant. `base` = foot centre.
func tent(base: Vector3, yaw: float, size: Vector3, col: Color) -> Node3D:
	var n: Node3D = _node(base, turn(yaw))
	var prism := PrismMesh.new()
	prism.size = size
	var canvas := StandardMaterial3D.new()
	canvas.albedo_color = col
	canvas.roughness = 0.95
	canvas.emission_enabled = true
	canvas.emission = Color(1.0, 0.5, 0.2)
	canvas.emission_energy_multiplier = 0.25
	_put(n, Look.mesh_node(prism, canvas, Vector3(0, size.y * 0.5, 0)))
	_put(n, Look.cylinder(0.04, size.y * 0.6, _wood(), Vector3(0, size.y * 1.15, 0), -1.0, 4))
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.5)
	q.subdivide_width = 3
	q.subdivide_depth = 1
	var fl := Look.mesh_node(q, _cloth_mat(CRIMSON, rng.randf() * 6.0, 0.2), Vector3(0.5, size.y * 1.35, 0))
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(fl)
	return n


## A working trebuchet (a SiegeTrebuchet), `sc` times its normal size, firing along local -Z of `yaw`.
func trebuchet(base: Vector3, yaw: float, sc: float = 1.0) -> SiegeTrebuchet:
	var t := SiegeTrebuchet.new()
	t.transform = Transform3D(turn(yaw).scaled(Vector3.ONE * sc), base)
	root.add_child(t)
	return t


## A tall siege tower on wheels (scenery): a stepped timber box with a drop-bridge and a hide skin.
func siege_tower_prop(base: Vector3, yaw: float, h: float = 18.0) -> Node3D:
	var n: Node3D = _node(base, turn(yaw))
	var hide := Look.flat(Color(0.42, 0.3, 0.2), 0.95)
	_put(n, Look.box(Vector3(6.0, h, 6.0), _wood(), Vector3(0, h * 0.5 + 0.8, 0)))
	for i: int in 4:
		_put(n, Look.box(Vector3(6.4, 0.35, 6.4), Look.flat(Color(0.2, 0.14, 0.1), 0.9), Vector3(0, 1.0 + (h / 4.0) * float(i + 1), 0)))
	_put(n, Look.box(Vector3(5.2, h * 0.5, 0.2), hide, Vector3(0, h * 0.72, 3.05)), true)
	_put(n, Look.box(Vector3(2.6, 0.2, 5.0), _wood(), Vector3(0, h * 0.86, 5.4))).rotation.x = -0.12
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var wheel := Look.cylinder(0.9, 0.45, _wood(), Vector3(sx * 3.2, 0.9, sz * 2.4), -1.0, 12)
			wheel.rotation.z = PI * 0.5
			_put(n, wheel)
	var slits: Array[Transform3D] = []
	for i: int in 3:
		slits.append(Transform3D(Basis.IDENTITY, Vector3((float(i) - 1.0) * 1.6, h * 0.55, 3.15)))
	_multi(n, _slit(), _glow(WINDOW, 1.8), slits, false)
	return n


## Heaped rubble: a few broken blocks.
func rubble(base: Vector3, count: int = 6) -> void:
	var n: Node3D = _node(base)
	for i: int in count:
		var s: float = rng.randf_range(0.3, 0.9)
		var b := Look.box(Vector3(s * 1.3, s, s), _stone() if i % 2 == 0 else _dark(), Vector3(rng.randf_range(-1.5, 1.5), s * 0.45, rng.randf_range(-1.5, 1.5)))
		b.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		n.add_child(b)


## A distant castle: a curtain wall with towers, a gatehouse on one side and a keep behind (far scenery).
func castle(base: Vector3, yaw: float, scale_k: float = 1.0) -> Node3D:
	var n: Node3D = _node(base, turn(yaw))
	var s: float = scale_k
	var sub := SiegeDecor.new(n, rng)
	sub.wall(Vector3(0, 0, 0), 0.0, 60.0 * s, 16.0 * s)
	sub.wall(Vector3(0, 0, -50.0 * s), 0.0, 60.0 * s, 16.0 * s)
	sub.wall(Vector3(-30.0 * s, 0, -25.0 * s), PI * 0.5, 50.0 * s, 16.0 * s)
	sub.wall(Vector3(30.0 * s, 0, -25.0 * s), PI * 0.5, 50.0 * s, 16.0 * s)
	for c: Vector2 in [Vector2(-30, 0), Vector2(30, 0), Vector2(-30, -50), Vector2(30, -50)]:
		sub.tower(Vector3(c.x * s, 0, c.y * s), 5.0 * s, 24.0 * s, true)
	sub.gatehouse(Vector3(0, 0, 2.0 * s), 0.0, 10.0 * s, 22.0 * s)
	sub.keep(Vector3(6.0 * s, 0, -30.0 * s), 0.0, 14.0 * s, 44.0 * s)
	return n


## A scorched, leafless tree (stumps and bare limbs) for the ground between the camps.
func dead_tree(base: Vector3, h: float = 7.0) -> void:
	var n: Node3D = _node(base, turn(rng.randf() * TAU))
	var bark := Look.flat(Color(0.12, 0.09, 0.08), 0.95)
	n.add_child(Look.cylinder(0.4, h, bark, Vector3(0, h * 0.5, 0), 0.14, 6))
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + rng.randf()
		var limb := Look.cylinder(0.12, h * 0.45, bark, Vector3(cos(a) * h * 0.1, h * (0.55 + 0.1 * float(i)), sin(a) * h * 0.1), 0.04, 5)
		limb.rotation = Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9)
		n.add_child(limb)
