class_name NeonDecor
extends RefCounted
## Neon City set dressing, all built from primitives: the towers under every rooftop (one shared
## lit-window facade material in world space), rooftop clutter (water tanks on stilts, AC units with
## spinning fans, steam vents, antennas with aircraft-warning lights, pipe runs, satellite dishes),
## neon blade signs and shop strips (abstract glyphs only - no words, no brands), holographic
## billboards, the far skyline as one MultiMesh, the street canyon far below, and far-off traffic.
## Nothing here collides unless it says so. Materials are cached.

const FACADE: Shader = preload("res://visual/neon_facade.gdshader")
const SIGN: Shader = preload("res://visual/neon_sign.gdshader")

const MAGENTA := Color(1.0, 0.2, 0.7)
const AMBER := Color(1.0, 0.62, 0.15)
const TEAL := Color(0.1, 0.95, 0.85)
const VIOLET := Color(0.62, 0.3, 1.0)
const RED := Color(1.0, 0.15, 0.2)

static var _mats: Dictionary = {}

var root: Node3D
var rng: RandomNumberGenerator
var _spinners: Array[Node3D] = []


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r
	_mats.clear()


func _add(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	root.add_child(n)
	return n


static func _ns(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func pick_neon() -> Color:
	return [MAGENTA, AMBER, TEAL, VIOLET][rng.randi() % 4]


# ---- materials ----------------------------------------------------------------------------

static func facade(lit: float = 0.38, glow: float = 1.6) -> ShaderMaterial:
	var key: String = "fa|%.2f|%.2f" % [lit, glow]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = FACADE
	m.set_shader_parameter("lit_share", lit)
	m.set_shader_parameter("glow", glow)
	_mats[key] = m
	return m


static func sign_material(mode: int, a: Color, b: Color, seed: float, cells: float = 5.0, bright: float = 2.4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SIGN
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("cells", cells)
	m.set_shader_parameter("bright", bright)
	return m


static func metal(c: Color = Color(0.2, 0.2, 0.24)) -> StandardMaterial3D:
	return Look.flat(c, 0.35, 0.7)


# ---- towers --------------------------------------------------------------------------------

## A tower block under a rooftop: footprint `size` (x, z) centred under `top` (the roof's top
## surface), running down to `bottom_y`. `drop` leaves that much of the roof slab's own side showing.
func tower(top: Vector3, size: Vector2, bottom_y: float, yaw: float = 0.0, drop: float = 1.0) -> MeshInstance3D:
	var h: float = top.y - drop - bottom_y
	if h <= 0.5:
		return null
	var mi := Look.box(Vector3(size.x, h, size.y), facade())
	mi.rotation.y = yaw
	_add(mi, Vector3(top.x, bottom_y + h * 0.5, top.z))
	# a lit setback band near the top in a neon colour
	var band := _ns(Look.box(Vector3(size.x + 0.08, 0.18, size.y + 0.08), Look.flat(pick_neon(), 0.4, 0.0, 2.2))) as MeshInstance3D
	band.rotation.y = yaw
	_add(band, Vector3(top.x, top.y - drop - 1.2, top.z))
	return mi


# ---- rooftop clutter -------------------------------------------------------------------------

## A wooden water tank on steel stilts (`pos` = the roof it stands on).
func water_tank(pos: Vector3, r: float = 1.3, h: float = 2.4, legs: float = 1.8) -> void:
	var n := Node3D.new()
	var wood: StandardMaterial3D = Look.flat(Color(0.22, 0.15, 0.12), 0.45)
	var steel: StandardMaterial3D = metal()
	for i: int in 4:
		var a: float = PI * 0.25 + PI * 0.5 * float(i)
		n.add_child(Look.cylinder(0.08, legs, steel, Vector3(cos(a) * r * 0.7, legs * 0.5, sin(a) * r * 0.7), -1.0, 6))
	n.add_child(Look.cylinder(r, h, wood, Vector3(0, legs + h * 0.5, 0), r * 0.97, 18))
	for k: int in 3:
		n.add_child(Look.cylinder(r * 1.02, 0.07, steel, Vector3(0, legs + 0.3 + float(k) * (h - 0.6) * 0.5, 0), -1.0, 18))
	n.add_child(Look.cylinder(r * 1.05, r * 0.6, Look.flat(Color(0.12, 0.1, 0.1), 0.5), Vector3(0, legs + h + r * 0.3, 0), 0.05, 18))
	_add(n, pos)


## An AC unit with a fan spinning in its top grille.
func ac_unit(pos: Vector3, size: Vector3 = Vector3(1.6, 1.0, 1.4), yaw: float = 0.0) -> void:
	var n := Node3D.new()
	n.add_child(Look.box(size, Look.flat(Color(0.55, 0.55, 0.58), 0.4, 0.4), Vector3(0, size.y * 0.5, 0)))
	n.add_child(Look.box(Vector3(size.x * 0.9, 0.04, 0.05), Look.flat(Color(0.2, 0.2, 0.22), 0.5), Vector3(0, size.y * 0.5, size.z * 0.5 + 0.01)))
	var r: float = minf(size.x, size.z) * 0.36
	n.add_child(Look.cylinder(r, 0.06, Look.flat(Color(0.08, 0.08, 0.1), 0.5), Vector3(0, size.y + 0.02, 0), -1.0, 16))
	var fan := Node3D.new()
	fan.set_script(preload("res://visual/spin.gd"))
	fan.set("period", 0.5 + rng.randf() * 0.4)
	fan.position = Vector3(0, size.y + 0.06, 0)
	for b: int in 3:
		var blade := Look.box(Vector3(r * 1.7, 0.02, r * 0.35), Look.flat(Color(0.4, 0.4, 0.44), 0.4, 0.5))
		blade.rotation.y = float(b) * TAU / 3.0
		fan.add_child(blade)
	n.add_child(fan)
	n.rotation.y = yaw
	_add(n, pos)


## A steam vent: a capped pipe stack with steam hissing out of it.
func vent(pos: Vector3, height: float = 1.4, steam_h: float = 5.0, sound: bool = true) -> void:
	var n := Node3D.new()
	var steel: StandardMaterial3D = metal(Color(0.3, 0.28, 0.3))
	n.add_child(Look.cylinder(0.32, height, steel, Vector3(0, height * 0.5, 0), -1.0, 12))
	n.add_child(Look.cylinder(0.45, 0.12, steel, Vector3(0, height + 0.25, 0), -1.0, 12))
	_add(n, pos)
	NeonFx.steam(root, pos + Vector3(0, height + 0.1, 0), steam_h, 18)
	if sound:
		# SOUND: neon_steam_hiss - a rooftop vent hissing (loop)
		WorldAudio.loop("neon_steam_hiss", n, -12.0, 14.0, 3.0)


## A radio mast with a blinking red aircraft-warning light on top.
func antenna(pos: Vector3, h: float = 6.0) -> void:
	var n := Node3D.new()
	var steel: StandardMaterial3D = metal(Color(0.35, 0.35, 0.4))
	n.add_child(Look.cylinder(0.07, h, steel, Vector3(0, h * 0.5, 0), 0.03, 6))
	for k: int in 3:
		var y: float = h * (0.35 + 0.22 * float(k))
		n.add_child(Look.box(Vector3(0.9 - 0.2 * float(k), 0.04, 0.04), steel, Vector3(0, y, 0)))
	var lamp := Look.sphere(0.12, Look.flat(RED, 0.3, 0.0, 6.0), Vector3(0, h + 0.1, 0))
	lamp.set_script(preload("res://visual/neon_blink.gd"))
	lamp.set("period", 1.4 + rng.randf() * 0.8)
	n.add_child(lamp)
	_add(n, pos)


## A satellite dish on a stub, tilted at the sky.
func dish(pos: Vector3, r: float = 0.8, yaw: float = 0.0) -> void:
	var n := Node3D.new()
	n.add_child(Look.cylinder(0.08, 0.8, metal(), Vector3(0, 0.4, 0), -1.0, 6))
	var d := Look.cylinder(r, 0.18, Look.flat(Color(0.75, 0.75, 0.78), 0.4, 0.3), Vector3(0, 0.95, 0), r * 0.25, 18)
	d.rotation.x = -0.9
	n.add_child(d)
	n.rotation.y = yaw
	_add(n, pos)


## A pipe run between two points (no collision).
func pipe(a: Vector3, b: Vector3, r: float = 0.14, c: Color = Color(0.3, 0.3, 0.34)) -> void:
	var d: Vector3 = b - a
	var l: float = d.length()
	if l < 0.05:
		return
	var n := Look.cylinder(r, l, Look.flat(c, 0.35, 0.6), Vector3.ZERO, -1.0, 8)
	var up: Vector3 = d / l
	var ref: Vector3 = Vector3(0.123, 0.4, 0.9) if absf(up.dot(Vector3(0.123, 0.4, 0.9).normalized())) < 0.95 else Vector3.RIGHT
	var side: Vector3 = up.cross(ref).normalized()
	n.basis = Basis(side, up, side.cross(up))
	_add(n, (a + b) * 0.5)


# ---- signs -------------------------------------------------------------------------------------

## A tall blade sign standing off a wall (or on a rooftop): glyphs stacked down a lit panel on a
## dark frame, both faces. `pos` = its bottom centre, `yaw` turns the face (faces local +Z / -Z).
func blade_sign(pos: Vector3, w: float, h: float, yaw: float, a: Color, b: Color, buzz: bool = true) -> Node3D:
	var n := Node3D.new()
	var frame: StandardMaterial3D = Look.flat(Color(0.05, 0.05, 0.07), 0.4, 0.6)
	n.add_child(Look.box(Vector3(w + 0.2, h + 0.2, 0.3), frame, Vector3(0, h * 0.5, 0)))
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mat: ShaderMaterial = sign_material(0, a, b, rng.randf() * 50.0, maxf(2.0, roundf(h / w * 1.1)))
	for s: float in [-1.0, 1.0]:
		var face := _ns(Look.mesh_node(q, mat, Vector3(0, h * 0.5, s * 0.16))) as MeshInstance3D
		face.rotation.y = 0.0 if s > 0.0 else PI
		n.add_child(face)
	var light := OmniLight3D.new()
	light.light_color = a
	light.light_energy = 1.6
	light.omni_range = maxf(h * 0.9, 6.0)
	light.position = Vector3(0, h * 0.5, 1.2)
	n.add_child(light)
	n.rotation.y = yaw
	_add(n, pos)
	if buzz:
		# SOUND: neon_sign_buzz - a big neon sign's tubes buzzing (loop)
		WorldAudio.loop("neon_sign_buzz", n, -16.0, 12.0, 3.0)
	return n


## A wide shop-front strip of glyphs (one face toward local +Z), e.g. along a parapet.
func strip_sign(pos: Vector3, w: float, h: float, yaw: float, a: Color, b: Color) -> void:
	var n := Node3D.new()
	n.add_child(Look.box(Vector3(w + 0.15, h + 0.15, 0.2), Look.flat(Color(0.04, 0.04, 0.06), 0.4, 0.5)))
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	n.add_child(_ns(Look.mesh_node(q, sign_material(2, a, b, rng.randf() * 50.0, maxf(3.0, roundf(w / h))), Vector3(0, 0, 0.11))))
	n.rotation.y = yaw
	_add(n, pos)


## A holographic billboard hanging off a tower: a frame of struts and the additive hologram.
func billboard(pos: Vector3, w: float, h: float, yaw: float, a: Color, b: Color, light: bool = true) -> Node3D:
	var n := Node3D.new()
	var steel: StandardMaterial3D = metal(Color(0.12, 0.12, 0.15))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.18, h + 1.0, 0.18), steel, Vector3(sx * (w * 0.5 + 0.15), 0, -0.4)))
	n.add_child(Look.box(Vector3(w + 0.6, 0.15, 0.15), steel, Vector3(0, -h * 0.5 - 0.3, -0.4)))
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mat: ShaderMaterial = sign_material(1, a, b, rng.randf() * 50.0, 1.0, 2.0)
	n.add_child(_ns(Look.mesh_node(q, mat)))
	if light:
		var o := OmniLight3D.new()
		o.light_color = a.lerp(b, 0.4)
		o.light_energy = 2.0
		o.omni_range = maxf(w, h) * 1.2
		o.position = Vector3(0, 0, 2.0)
		n.add_child(o)
	n.rotation.y = yaw
	_add(n, pos)
	return n


# ---- far city ------------------------------------------------------------------------------------

## The far skyline: `count` towers scattered in a ring between radius r0 and r1 round `center`
## (skipping anything `keep` says is too close to the course), as one MultiMesh, with a sprinkle of
## big billboards and blade signs on the nearer ones and blinking red lights on the tall ones.
func skyline(center: Vector3, r0: float, r1: float, count: int, street_y: float, keep: Callable) -> void:
	var xfs: Array[Transform3D] = []
	var tops: Array[Vector3] = []
	var tries: int = 0
	while xfs.size() < count and tries < count * 8:
		tries += 1
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(r0, r1)
		var p := Vector3(center.x + cos(a) * r, street_y, center.z + sin(a) * r)
		var w: float = rng.randf_range(14.0, 34.0)
		var d: float = rng.randf_range(14.0, 34.0)
		var h: float = rng.randf_range(60.0, 210.0) * (0.6 + 0.6 * clampf((r1 - r) / (r1 - r0), 0.0, 1.0))
		if not bool(keep.call(p, maxf(w, d) * 0.75)):
			continue
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)).scaled(Vector3(w, h, d)), p + Vector3(0, h * 0.5, 0)))
		tops.append(p + Vector3(0, h, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = facade(0.3, 1.8)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	# warning lights on the tall ones, a crown of neon on some
	for i: int in tops.size():
		var tp: Vector3 = tops[i]
		var s: Vector3 = xfs[i].basis.get_scale()
		if tp.y - street_y > 120.0 and rng.randf() < 0.7:
			antenna(tp, rng.randf_range(8.0, 18.0))
		if rng.randf() < 0.45:
			var crown := _ns(Look.box(Vector3(s.x + 0.4, 0.6, s.z + 0.4), Look.flat(pick_neon(), 0.4, 0.0, 2.6))) as MeshInstance3D
			crown.basis = Basis(Vector3.UP, xfs[i].basis.get_euler().y)
			_add(crown, tp - Vector3(0, rng.randf_range(2.0, 8.0), 0))


## The street canyon far below: a dark wet ground plane with glowing lane lines and crossings,
## and haze drifting over it.
func street(center: Vector3, extent: float, y: float) -> void:
	var g := Look.box(Vector3(extent * 2.0, 1.0, extent * 2.0), Look.flat(Color(0.03, 0.025, 0.035), 0.15, 0.3))
	_ns(g)
	_add(g, Vector3(center.x, y - 0.5, center.z))
	var lane_mat: StandardMaterial3D = Look.flat(AMBER, 0.4, 0.0, 2.0)
	var lane_mat2: StandardMaterial3D = Look.flat(Color(0.9, 0.9, 1.0), 0.4, 0.0, 1.5)
	var step: float = 70.0
	var k: int = int(extent / step)
	for i: int in range(-k, k + 1):
		var off: float = float(i) * step
		_add(_ns(Look.box(Vector3(0.4, 0.06, extent * 2.0), lane_mat if i % 2 == 0 else lane_mat2)), Vector3(center.x + off, y + 0.03, center.z))
		_add(_ns(Look.box(Vector3(extent * 2.0, 0.06, 0.4), lane_mat2 if i % 2 == 0 else lane_mat)), Vector3(center.x, y + 0.03, center.z + off))


## A holographic giant: a huge additive billboard floating between far towers.
func mega_billboard(pos: Vector3, w: float, h: float, yaw: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var n := _ns(Look.mesh_node(q, sign_material(1, pick_neon(), pick_neon(), rng.randf() * 50.0, 1.0, 1.6))) as MeshInstance3D
	n.rotation.y = yaw
	_add(n, pos)
