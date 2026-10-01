class_name JungleDecor
extends RefCounted
## Jungle Temple set dressing (visual only: nothing here collides or times anything). Rock pillars
## under the ruins, the river, giant trees with buttress roots and lumpy canopies, hanging vines,
## waterfalls with mist and a rainbow, carved stone faces, jade glyph stelae, broken stairways,
## the pyramid's carved bands and summit temple, god rays, toucans, and the far scenery.
## Everything placed near the course checks `clear()` against the course's solids and route so no
## decoration ever pokes through a landing or sits in a jump.

const STONE := Color(0.46, 0.47, 0.38)
const STONE_DARK := Color(0.3, 0.31, 0.25)
const ROCK := Color(0.33, 0.33, 0.28)
const BARK := Color(0.36, 0.27, 0.19)
const BARK_PALE := Color(0.55, 0.5, 0.42)
const MOSS := Color(0.24, 0.42, 0.14)
const LIANA := Color(0.22, 0.3, 0.13)
const JADE := Color(0.25, 0.95, 0.65)
const GOLD := Color(1.0, 0.76, 0.28)

const STONE_SHADER: Shader = preload("res://visual/jungle_stone.gdshader")
const LEAF_SHADER: Shader = preload("res://visual/jungle_leaf.gdshader")
const WATER_SHADER: Shader = preload("res://visual/jungle_water.gdshader")
const FALLS_SHADER: Shader = preload("res://visual/jungle_falls.gdshader")
const BEAM_SHADER: Shader = preload("res://visual/jungle_beam.gdshader")
const RAINBOW_SHADER: Shader = preload("res://visual/jungle_rainbow.gdshader")

var root: Node3D
var rng: RandomNumberGenerator
## The course's solid boxes (world) and its route polyline: decor keeps clear of both.
var solids: Array[AABB] = []
var path: PackedVector3Array = PackedVector3Array()

var _mats: Dictionary = {}


func _init(level_root: Node3D, random: RandomNumberGenerator) -> void:
	root = level_root
	rng = random


# ---- clearance --------------------------------------------------------------------------------

## True when `box` (world) keeps `margin` m from every course solid and `path_margin` m (horizontally,
## within the box's height range +- 4 m) from the route.
func clear(box: AABB, margin: float = 0.6, path_margin: float = 3.0) -> bool:
	var grown: AABB = box.grow(margin)
	for s: AABB in solids:
		if grown.intersects(s):
			return false
	if path_margin <= 0.0:
		return true
	var lo: float = box.position.y - 4.0
	var hi: float = box.end.y + 4.0
	var c := Vector2(box.get_center().x, box.get_center().z)
	var r: float = Vector2(box.size.x, box.size.z).length() * 0.5 + path_margin
	for i: int in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		if maxf(a.y, b.y) < lo or minf(a.y, b.y) > hi:
			continue
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var ab: Vector2 = b2 - a2
		var k: float = clampf((c - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a2 + ab * k).distance_to(c) < r:
			return false
	return true


# ---- materials ---------------------------------------------------------------------------------

func stone(color: Color = STONE, mossy: float = 0.55, half: Vector3 = Vector3(1, 1, 1)) -> ShaderMaterial:
	var key: String = "st:%s:%.2f:%.1f:%.1f:%.1f" % [color.to_html(), mossy, half.x, half.y, half.z]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = STONE_SHADER
	m.set_shader_parameter("top_color", color.lightened(0.12))
	m.set_shader_parameter("side_color", color)
	m.set_shader_parameter("trim_color", JADE)
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("trim_glow", 0.0)
	m.set_shader_parameter("trim_width", 0.0)
	m.set_shader_parameter("mossy", mossy)
	_mats[key] = m
	return m


func leaf(shade: float = 0.0) -> ShaderMaterial:
	var key: String = "leaf:%.2f" % shade
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = LEAF_SHADER
	m.set_shader_parameter("leaf_dark", Color(0.07, 0.17, 0.06).lerp(Color(0.1, 0.2, 0.12), shade))
	m.set_shader_parameter("leaf", Color(0.18, 0.38, 0.11).lerp(Color(0.24, 0.4, 0.2), shade))
	m.set_shader_parameter("leaf_light", Color(0.44, 0.62, 0.2).lerp(Color(0.5, 0.66, 0.36), shade))
	_mats[key] = m
	return m


func _add(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	root.add_child(n)
	return n


func _box(size: Vector3, mat: Material, pos: Vector3, yaw: float = 0.0) -> MeshInstance3D:
	var b := Look.box(size, mat, pos)
	b.rotation.y = yaw
	root.add_child(b)
	return b


# ---- rock pillars under the ruins ----------------------------------------------------------------

## A karst rock pillar under every raised platform, down into the water: tapered, mossy-topped, with
## roots and lianas hanging off it.
func build_piers(piers: Array, water_y: float) -> void:
	var rock: StandardMaterial3D = Look.flat(ROCK, 0.95)
	var moss: StandardMaterial3D = Look.flat(MOSS, 0.95)
	var vine: StandardMaterial3D = Look.flat(LIANA, 0.9)
	for p: Array in piers:
		var top: Vector3 = p[0]
		var size: Vector3 = p[1]
		var h: float = top.y - water_y + 1.5
		if h <= 0.3:
			continue
		var big: bool = size.x > 30.0
		var w: Vector3 = Vector3(size.x * 0.82, h, size.z * 0.82)
		# a tapered pillar (wider at the water), a little irregular
		var cm := CylinderMesh.new()
		cm.radial_segments = 6 if not big else 8
		cm.rings = 2
		cm.height = h
		cm.top_radius = 0.7071
		cm.bottom_radius = 0.7071 * (1.25 if not big else 1.15)
		var mi := Look.mesh_node(cm, rock, top - Vector3(0, h * 0.5 + 0.02, 0))
		mi.scale = Vector3(w.x, 1.0, w.z)
		mi.rotation.y = PI / 4.0 + rng.randf_range(-0.06, 0.06) if not big else PI / 8.0
		root.add_child(mi)
		if big:
			continue
		# a skirt of moss under the lip, a few roots and lianas trailing down
		root.add_child(Look.box(Vector3(size.x * 0.84, 0.35, size.z * 0.84), moss, top - Vector3(0, 0.25, 0)))
		var n: int = clampi(int((size.x + size.z) * 0.6), 2, 7)
		for i: int in n:
			var side: float = rng.randf() * TAU
			var at: Vector3 = top + Vector3(cos(side) * size.x * 0.42, -0.2, sin(side) * size.z * 0.42)
			var ln: float = rng.randf_range(1.5, minf(h * 0.6, 7.0))
			root.add_child(Look.cylinder(0.05, ln, vine, at - Vector3(0, ln * 0.5, 0), 0.03, 5))


# ---- the river --------------------------------------------------------------------------------------

func water(center: Vector3, size: Vector2, flow: Vector2) -> void:
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("flow", flow)
	var mi := Look.mesh_node(pm, m, center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Lily pads and reed clumps scattered on the water round `center` (kept off the route).
func lilies(center: Vector3, extent: Vector2, count: int, water_y: float) -> void:
	var pad_mat: StandardMaterial3D = Look.flat(Color(0.2, 0.45, 0.16), 0.6)
	var flower: StandardMaterial3D = Look.flat(Color(1.0, 0.6, 0.8), 0.5, 0.0, 0.3)
	var reed: StandardMaterial3D = Look.flat(Color(0.35, 0.5, 0.18), 0.8)
	for i: int in count:
		var p := Vector3(center.x + rng.randf_range(-extent.x, extent.x), water_y + 0.03, center.z + rng.randf_range(-extent.y, extent.y))
		if not clear(AABB(p - Vector3(1.5, 0.5, 1.5), Vector3(3, 2, 3)), 0.5, 1.5):
			continue
		if rng.randf() < 0.6:
			for j: int in rng.randi_range(2, 5):
				var r: float = rng.randf_range(0.3, 0.7)
				var pad := Look.cylinder(r, 0.03, pad_mat, p + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2)), -1.0, 10)
				root.add_child(pad)
				if rng.randf() < 0.3:
					root.add_child(Look.sphere(0.12, flower, pad.position + Vector3(0, 0.08, 0)))
		else:
			for j: int in rng.randi_range(5, 9):
				var hgt: float = rng.randf_range(1.0, 2.2)
				var rd := Look.cylinder(0.03, hgt, reed, p + Vector3(rng.randf_range(-0.6, 0.6), hgt * 0.5, rng.randf_range(-0.6, 0.6)), 0.01, 4)
				rd.rotation = Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
				root.add_child(rd)


# ---- giant trees -------------------------------------------------------------------------------------

## A rainforest giant: a tall pale trunk flaring into buttress roots, a few limbs, a lumpy canopy, and
## lianas hanging from it. Returns false if it does not fit there.
func giant_tree(base: Vector3, height: float, radius: float, check: bool = true) -> bool:
	var crown_r: float = height * 0.32
	var box := AABB(base - Vector3(radius * 2.5, 0, radius * 2.5), Vector3(radius * 5.0, height, radius * 5.0))
	if check and not clear(box, 1.0, 4.0):
		return false
	var crown := AABB(base + Vector3(-crown_r, height * 0.78, -crown_r), Vector3(crown_r * 2.0, crown_r * 1.2, crown_r * 2.0))
	if check and not clear(crown, 1.0, 3.0):
		crown_r *= 0.55
	var t := Node3D.new()
	t.position = base
	t.rotation.y = rng.randf() * TAU
	root.add_child(t)
	var bark: StandardMaterial3D = Look.flat(BARK_PALE.lerp(BARK, rng.randf_range(0.2, 0.6)), 0.92)
	t.add_child(Look.cylinder(radius, height, bark, Vector3(0, height * 0.5, 0), radius * 0.55, 10))
	# buttress roots: thin tall fins flaring out from the trunk's foot
	for i: int in 5:
		var a: float = float(i) / 5.0 * TAU + rng.randf_range(-0.2, 0.2)
		var fin_h: float = radius * rng.randf_range(2.2, 3.4)
		var fin_l: float = radius * rng.randf_range(1.8, 2.6)
		var fin := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(fin_l * 2.0, fin_h, 0.35 * radius)
		pm.left_to_right = 0.5
		fin.mesh = pm
		fin.material_override = bark
		fin.position = Vector3(cos(a), 0, sin(a)) * 0.0 + Vector3(0, fin_h * 0.5, 0)
		fin.rotation.y = -a
		t.add_child(fin)
	# limbs and the canopy: big lumpy leaf masses
	var lm: ShaderMaterial = leaf(rng.randf() * 0.4)
	var top: float = height * 0.9
	for i: int in 4:
		var a: float = float(i) / 4.0 * TAU + rng.randf_range(-0.4, 0.4)
		var out: float = crown_r * rng.randf_range(0.45, 0.7)
		var limb_to := Vector3(cos(a) * out, top + rng.randf_range(-2.0, 1.0), sin(a) * out)
		var limb_from := Vector3(0, height * 0.72, 0)
		var d: Vector3 = limb_to - limb_from
		var limb := Look.cylinder(radius * 0.35, d.length(), bark, (limb_from + limb_to) * 0.5, radius * 0.2, 6)
		limb.basis = _along(d)
		t.add_child(limb)
		var blob := Look.sphere(1.0, lm, limb_to + Vector3(0, crown_r * 0.12, 0))
		blob.scale = Vector3(crown_r * rng.randf_range(0.55, 0.75), crown_r * rng.randf_range(0.3, 0.42), crown_r * rng.randf_range(0.55, 0.75))
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		t.add_child(blob)
	var cap := Look.sphere(1.0, lm, Vector3(0, top + crown_r * 0.25, 0))
	cap.scale = Vector3(crown_r * 0.8, crown_r * 0.4, crown_r * 0.8)
	t.add_child(cap)
	# lianas hanging from the crown
	var vine: StandardMaterial3D = Look.flat(LIANA, 0.9)
	for i: int in rng.randi_range(4, 8):
		var a: float = rng.randf() * TAU
		var r: float = crown_r * rng.randf_range(0.2, 0.75)
		var ln: float = rng.randf_range(height * 0.25, height * 0.6)
		var at := Vector3(cos(a) * r, top - 1.0 - ln * 0.5, sin(a) * r)
		t.add_child(Look.cylinder(0.07, ln, vine, at, 0.05, 5))
	return true


static func _along(d: Vector3) -> Basis:
	var y: Vector3 = d.normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


## A smaller understorey palm: a curved trunk and a burst of fronds.
func palm(base: Vector3, height: float) -> bool:
	if not clear(AABB(base - Vector3(2.5, 0, 2.5), Vector3(5, height + 1.5, 5)), 0.6, 2.5):
		return false
	var t := Node3D.new()
	t.position = base
	t.rotation.y = rng.randf() * TAU
	root.add_child(t)
	var bark: StandardMaterial3D = Look.flat(Color(0.48, 0.4, 0.3), 0.9)
	var lean: float = rng.randf_range(0.05, 0.25)
	var trunk := Look.cylinder(0.2, height, bark, Vector3(height * lean * 0.5, height * 0.5, 0), 0.14, 7)
	trunk.rotation.z = -lean
	t.add_child(trunk)
	var frond: StandardMaterial3D = Look.flat(Color(0.2, 0.44, 0.14), 0.8)
	var crown := Vector3(height * lean, height, 0)
	for i: int in 7:
		var a: float = float(i) / 7.0 * TAU
		var f := Look.box(Vector3(2.6, 0.04, 0.5), frond, crown + Vector3(cos(a), -0.3, sin(a)) * 1.2)
		f.rotation = Vector3(0, -a, -0.45)
		t.add_child(f)
	return true


## A fern clump on the ground.
func fern(base: Vector3, size: float = 1.0) -> void:
	var m: StandardMaterial3D = Look.flat(Color(0.18, 0.4, 0.12).lightened(rng.randf_range(0.0, 0.15)), 0.85)
	var t := Node3D.new()
	t.position = base
	root.add_child(t)
	for i: int in 6:
		var a: float = float(i) / 6.0 * TAU + rng.randf_range(-0.2, 0.2)
		var f := Look.box(Vector3(1.4, 0.03, 0.34) * size, m, Vector3(cos(a), 0.35, sin(a)) * 0.6 * size)
		f.rotation = Vector3(0, -a, 0.5)
		t.add_child(f)


## A curtain of lianas hanging from `top` (a line from a to b), down `length` m (visual only).
func vine_curtain(a: Vector3, b: Vector3, length: float, count: int) -> void:
	var vine: StandardMaterial3D = Look.flat(LIANA, 0.9)
	var leaf_m: StandardMaterial3D = Look.flat(Color(0.22, 0.46, 0.15), 0.85)
	for i: int in count:
		var p: Vector3 = a.lerp(b, rng.randf())
		var ln: float = length * rng.randf_range(0.5, 1.0)
		if not clear(AABB(p - Vector3(0.2, ln, 0.2), Vector3(0.4, ln, 0.4)), 0.3, 1.8):
			continue
		root.add_child(Look.cylinder(0.04, ln, vine, p - Vector3(0, ln * 0.5, 0), 0.03, 4))
		for j: int in int(ln / 1.4):
			var lf := Look.box(Vector3(0.3, 0.02, 0.16), leaf_m, p - Vector3(0, 0.6 + float(j) * 1.4, 0))
			lf.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, 0.4)
			root.add_child(lf)


# ---- ruins -------------------------------------------------------------------------------------------

## A colossal carved stone head (Olmec / Maya style): brow, jade eyes, broad nose, open mouth, ear
## spools, a headdress. Facing `dir` (world, horizontal). `s` = its height in metres.
func stone_face(at: Vector3, dir: Vector3, s: float, check: bool = true) -> bool:
	var f: Vector3 = Vector3(dir.x, 0, dir.z).normalized()
	var yaw: float = atan2(f.x, f.z)
	var box := AABB(at - Vector3(s * 0.6, 0, s * 0.6), Vector3(s * 1.2, s * 1.3, s * 1.2))
	if check and not clear(box, 0.5, 2.0):
		return false
	var h := Node3D.new()
	h.position = at
	h.rotation.y = yaw
	root.add_child(h)
	var st: ShaderMaterial = stone(STONE.darkened(0.05), 0.7, Vector3(s * 0.5, s * 0.5, s * 0.4))
	var dark: StandardMaterial3D = Look.flat(STONE_DARK, 0.95)
	var jade: StandardMaterial3D = Look.flat(JADE, 0.3, 0.0, 1.8)
	h.add_child(Look.box(Vector3(s, s, s * 0.8), st, Vector3(0, s * 0.5, 0)))
	h.add_child(Look.box(Vector3(s * 1.1, s * 0.16, s * 0.9), dark, Vector3(0, s * 0.72, s * 0.08)))       # brow
	for sx: float in [-1.0, 1.0]:
		h.add_child(Look.box(Vector3(s * 0.22, s * 0.1, s * 0.05), jade, Vector3(sx * s * 0.22, s * 0.6, s * 0.41)))
		h.add_child(Look.cylinder(s * 0.12, s * 0.12, dark, Vector3(sx * s * 0.55, s * 0.5, 0), -1.0, 10))  # ear spools
	h.add_child(Look.box(Vector3(s * 0.2, s * 0.3, s * 0.12), st, Vector3(0, s * 0.42, s * 0.44)))          # nose
	h.add_child(Look.box(Vector3(s * 0.46, s * 0.14, s * 0.06), Look.flat(Color(0.08, 0.09, 0.07), 0.95), Vector3(0, s * 0.2, s * 0.41)))
	h.add_child(Look.box(Vector3(s * 1.2, s * 0.22, s * 0.95), st, Vector3(0, s * 1.08, 0)))               # headdress
	for i: int in 5:
		h.add_child(Look.box(Vector3(s * 0.12, s * 0.24, s * 0.06), jade, Vector3((float(i) - 2.0) * s * 0.22, s * 1.08, s * 0.49)))
	return true


## A jade glyph stela: a carved stone slab with glowing inlay, a little moss at its foot.
func stela(at: Vector3, yaw: float, h: float = 3.2) -> bool:
	if not clear(AABB(at - Vector3(1.0, 0, 1.0), Vector3(2.0, h, 2.0)), 0.4, 1.6):
		return false
	var n := Node3D.new()
	n.position = at
	n.rotation.y = yaw
	root.add_child(n)
	n.add_child(Look.box(Vector3(1.2, h, 0.45), stone(STONE, 0.6, Vector3(0.6, h * 0.5, 0.25)), Vector3(0, h * 0.5, 0)))
	var jade: StandardMaterial3D = Look.flat(JADE, 0.3, 0.0, 1.6)
	for s: float in [-1.0, 1.0]:
		for i: int in 3:
			n.add_child(Look.box(Vector3(0.6, 0.08, 0.03), jade, Vector3(0, h * (0.35 + 0.18 * float(i)), s * 0.235)))
		var tm := TorusMesh.new()
		tm.inner_radius = 0.18
		tm.outer_radius = 0.25
		tm.rings = 14
		tm.ring_segments = 5
		var ring := Look.mesh_node(tm, jade, Vector3(0, h * 0.85, s * 0.24))
		ring.rotation.x = PI * 0.5
		n.add_child(ring)
	return true


## A broken stairway fragment: a few steps rising and stopping in mid-air (ruins scenery).
func broken_stair(at: Vector3, yaw: float, steps: int = 5) -> bool:
	var run: float = float(steps) * 0.8
	if not clear(AABB(at - Vector3(run, 0, run), Vector3(run * 2.0, float(steps) * 0.5 + 1.0, run * 2.0)), 0.6, 2.5):
		return false
	var n := Node3D.new()
	n.position = at
	n.rotation.y = yaw
	root.add_child(n)
	var st: ShaderMaterial = stone(STONE, 0.75, Vector3(1.5, 1.0, 1.0))
	for i: int in steps:
		if rng.randf() < 0.15 and i > 1:
			continue
		var hh: float = 0.5 * float(i + 1)
		n.add_child(Look.box(Vector3(3.0 - rng.randf_range(0.0, 0.6), hh, 0.8), st, Vector3(rng.randf_range(-0.2, 0.2), hh * 0.5, -0.8 * float(i))))
	return true


## A brazier on a stone post with a jade fire.
func brazier(at: Vector3, scale: float = 1.0) -> void:
	root.add_child(Look.cylinder(0.3 * scale, 1.2 * scale, stone(STONE, 0.5, Vector3(0.3, 0.6, 0.3)), at + Vector3(0, 0.6 * scale, 0), 0.4 * scale, 8))
	root.add_child(Look.cylinder(0.55 * scale, 0.3 * scale, Look.flat(STONE_DARK, 0.9), at + Vector3(0, 1.35 * scale, 0), 0.4 * scale, 10))
	JungleFx.jade_fire(root, at + Vector3(0, 1.5 * scale, 0), scale)


# ---- waterfalls --------------------------------------------------------------------------------------

## A waterfall pouring off a mossy cliff into a pool: the cliff block, the curtain, spray and mist at
## its foot, a rainbow arc in the mist. `at` is the curtain's foot (on the water), `face` the
## direction the falling water faces (toward the viewer).
func falls(at: Vector3, face: Vector3, height: float, width: float, rainbow: bool = true) -> void:
	var f: Vector3 = Vector3(face.x, 0, face.z).normalized()
	var yaw: float = atan2(f.x, f.z)
	var cliff_depth: float = 10.0
	var cliff_c: Vector3 = at - f * (cliff_depth * 0.5 + 0.6) + Vector3(0, height * 0.5, 0)
	var cliff := _box(Vector3(width + 12.0, height + 2.0, cliff_depth), stone(ROCK, 0.85, Vector3((width + 12.0) * 0.5, (height + 2.0) * 0.5, cliff_depth * 0.5)), cliff_c, yaw)
	cliff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# the curtain
	var qm := QuadMesh.new()
	qm.size = Vector2(width, height)
	var m := ShaderMaterial.new()
	m.shader = FALLS_SHADER
	var q := Look.mesh_node(qm, m, at - f * 0.3 + Vector3(0, height * 0.5, 0))
	q.rotation.y = yaw
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(q)
	# a second, fainter sheet in front for depth
	var q2 := Look.mesh_node(qm, m, at + Vector3(0, height * 0.5, 0))
	q2.rotation.y = yaw
	q2.scale = Vector3(0.85, 1.0, 1.0)
	q2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(q2)
	JungleFx.falls_spray(root, at + f * 0.8, width, int(width * 4.0))
	JungleFx.mist(root, at + f * 4.0 + Vector3(0, 2.0, 0), Vector3(width * 0.6, 1.5, 3.0), 8)
	# moss and lianas on the cliff's face either side
	vine_curtain(cliff_c + f * (cliff_depth * 0.5 + 0.1) + Vector3(0, height * 0.5, 0) - f.cross(Vector3.UP) * (width * 0.5 + 1.0),
		cliff_c + f * (cliff_depth * 0.5 + 0.1) + Vector3(0, height * 0.5, 0) - f.cross(Vector3.UP) * (width * 0.5 + 6.0), height * 0.5, 6)
	if rainbow:
		var rq := QuadMesh.new()
		rq.size = Vector2(width * 2.6, width * 1.3)
		var rm := ShaderMaterial.new()
		rm.shader = RAINBOW_SHADER
		var r := Look.mesh_node(rq, rm, at + f * 6.0 + Vector3(0, width * 0.2, 0))
		r.rotation.y = yaw
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(r)
	var snd := Node3D.new()
	snd.position = at + Vector3(0, 2.0, 0)
	root.add_child(snd)
	WorldAudio.loop("jungle_waterfall", snd, -4.0, 45.0, 10.0)


# ---- light ---------------------------------------------------------------------------------------------

## A god ray falling through the canopy: a tall faint cone of light, slanted with the sun.
func god_ray(foot: Vector3, height: float, radius: float, sun_dir: Vector3) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.7
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	m.set_shader_parameter("strength", 0.14)
	var mi := Look.mesh_node(cm, m)
	var up: Vector3 = (-sun_dir).normalized()
	if up.y < 0.2:
		up = Vector3(up.x, 0.2, up.z).normalized()
	mi.basis = _along(up)
	mi.position = foot + up * height * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	JungleFx.motes(root, foot + up * height * 0.3, Vector3(radius, height * 0.25, radius), 24)


# ---- birds --------------------------------------------------------------------------------------------

## A few toucans circling over the canopy round `center`.
func toucans(center: Vector3, radius: float, count: int, speed: float = 7.0) -> void:
	var flock := Node3D.new()
	flock.set_script(preload("res://visual/jungle_birds.gd"))
	flock.set("radius", radius)
	flock.set("speed", speed)
	flock.position = center
	root.add_child(flock)
	var body: StandardMaterial3D = Look.flat(Color(0.06, 0.06, 0.07), 0.6)
	var chest: StandardMaterial3D = Look.flat(Color(1.0, 0.9, 0.4), 0.6)
	var beak: StandardMaterial3D = Look.flat(Color(1.0, 0.52, 0.1), 0.5, 0.0, 0.2)
	for i: int in count:
		var b := Node3D.new()
		var s: float = rng.randf_range(0.9, 1.2)
		b.scale = Vector3.ONE * s
		var torso := Look.sphere(0.28, body, Vector3.ZERO)
		torso.scale = Vector3(0.8, 0.8, 1.6)
		b.add_child(torso)
		b.add_child(Look.sphere(0.16, chest, Vector3(0, -0.05, -0.28)))
		var bk := Look.cylinder(0.1, 0.5, beak, Vector3(0, 0.02, -0.62), 0.02, 6)
		bk.rotation.x = -PI * 0.5
		b.add_child(bk)
		for sx: float in [-1.0, 1.0]:
			var wing := Look.box(Vector3(0.7, 0.03, 0.3), body, Vector3(sx * 0.42, 0.05, 0.0))
			wing.name = "WingL" if sx < 0.0 else "WingR"
			b.add_child(wing)
		flock.add_child(b)
		b.set_meta("phase", float(i) / float(count) * TAU + rng.randf_range(-0.3, 0.3))
		b.set_meta("alt", rng.randf_range(-3.0, 3.0))


# ---- the pyramid ---------------------------------------------------------------------------------------

## Dress the pyramid's tiers: a recessed panel band and a jade frieze along each tier face (only where
## the face is clear of buttresses and panels), carved masks at the corners, and the summit temple's
## roof comb and braziers. `center` is the pyramid's base centre (world), `yaw` its frame.
func pyramid(center: Vector3, yaw: float, tiers: int, tier_h: float, half0: float, step: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var dark: StandardMaterial3D = Look.flat(STONE_DARK.lerp(STONE, 0.3), 0.95)
	var jade: StandardMaterial3D = Look.flat(JADE, 0.35, 0.0, 1.0)
	var red: StandardMaterial3D = Look.flat(Color(0.62, 0.22, 0.16), 0.9)
	for i: int in tiers:
		var half: float = half0 - step * float(i)
		var y0: float = tier_h * float(i)
		for side: int in 4:
			var n: Vector3 = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][side]
			var along: Vector3 = Vector3(-n.z, 0, n.x)
			# segments of band, skipping anything standing against the face
			var seg: float = 6.0
			var x: float = -half + 1.0
			while x < half - 1.0:
				var ln: float = minf(seg, half - 1.0 - x)
				var mid: Vector3 = center + b * (n * (half + 0.12) + along * (x + ln * 0.5)) + Vector3(0, y0 + tier_h * 0.45, 0)
				var size: Vector3 = (b * (along * ln + n * 0.24)).abs() + Vector3(0, tier_h * 0.42, 0)
				var bb := AABB(mid - size * 0.5, size)
				if clear(bb, 0.15, 0.0):
					root.add_child(Look.box(size, dark, mid))
					var fr: Vector3 = (b * (along * ln + n * 0.3)).abs() + Vector3(0, 0.12, 0)
					root.add_child(Look.box(fr, jade, mid + Vector3(0, tier_h * 0.22, 0) + b * n * 0.03))
					root.add_child(Look.box(fr, red, mid - Vector3(0, tier_h * 0.2, 0) + b * n * 0.03))
				x += seg
		# carved masks at the four corners of each tier (decor only, set back into the corner)
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var corner: Vector3 = center + b * Vector3(cx * (half - 0.6), 0, cz * (half - 0.6)) + Vector3(0, y0 + tier_h * 0.5, 0)
				var m := Look.box(Vector3(1.6, 1.6, 1.6), dark, corner)
				m.rotation.y = deg_to_rad(yaw) + PI * 0.25
				if clear(AABB(corner - Vector3(1.2, 0.8, 1.2), Vector3(2.4, 1.6, 2.4)), 0.1, 0.0):
					root.add_child(m)
					root.add_child(Look.box(Vector3(0.3, 0.2, 0.05), jade, corner + b * Vector3(cx * 1.15, 0.2, cz * 1.15)))
	# the summit temple: a roof comb behind the altar, columns, braziers at the corners
	var top_y: float = tier_h * float(tiers)
	var half_t: float = half0 - step * float(tiers - 1)
	var comb_c: Vector3 = center + b * Vector3(0, 0, half_t - 0.8) + Vector3(0, top_y + 5.0, 0)
	var comb_size: Vector3 = (b * Vector3(half_t * 1.6, 0, 1.0)).abs() + Vector3(0, 10.0, 0)
	if clear(AABB(comb_c - comb_size * 0.5, comb_size), 0.2, 0.0):
		root.add_child(Look.box(comb_size, stone(STONE, 0.4, comb_size * 0.5), comb_c))
		for i: int in 5:
			var off: Vector3 = b * Vector3((float(i) - 2.0) * half_t * 0.3, 0, -0.55) + Vector3(0, -2.0 + float(i % 2) * 2.5, 0)
			var win := Look.box((b * Vector3(0.9, 0, 0.1)).abs() + Vector3(0, 1.4, 0), Look.flat(Color(0.05, 0.06, 0.05), 0.95), comb_c + off)
			root.add_child(win)
		root.add_child(Look.box((b * Vector3(half_t * 1.4, 0, 1.06)).abs() + Vector3(0, 0.3, 0), jade, comb_c + Vector3(0, 3.0, 0)))
		root.add_child(Look.box((b * Vector3(half_t * 1.4, 0, 1.06)).abs() + Vector3(0, 0.3, 0), jade, comb_c + Vector3(0, -3.5, 0)))
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var at: Vector3 = center + b * Vector3(cx * (half_t - 0.9), 0, cz * (half_t - 0.9)) + Vector3(0, top_y, 0)
			if clear(AABB(at - Vector3(0.7, 0, 0.7), Vector3(1.4, 2.0, 1.4)), 0.2, 0.0):
				brazier(at, 0.9)


# ---- far scenery ---------------------------------------------------------------------------------------

## Round the whole course: a carpet of canopy hills to the horizon, distant pyramids poking out of it,
## blue mountains with thin waterfalls, and mist banks lying in the valleys.
func far_scenery(center: Vector3, water_y: float) -> void:
	var hill_mats: Array[ShaderMaterial] = [leaf(0.0), leaf(0.3), leaf(0.6)]
	# the canopy carpet: a ring of big flattened lumpy domes
	for i: int in 70:
		var a: float = float(i) / 70.0 * TAU + rng.randf_range(-0.04, 0.04)
		var r: float = rng.randf_range(260.0, 520.0)
		var p: Vector3 = center + Vector3(cos(a) * r, water_y + rng.randf_range(-6.0, 4.0), sin(a) * r)
		var dome := Look.sphere(1.0, hill_mats[i % 3], p)
		dome.scale = Vector3(rng.randf_range(40.0, 70.0), rng.randf_range(18.0, 34.0), rng.randf_range(40.0, 70.0))
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(dome)
	# distant pyramids rising out of the canopy
	var st: ShaderMaterial = stone(Color(0.5, 0.52, 0.46), 0.5, Vector3(20, 10, 20))
	for k: int in 4:
		var a: float = float(k) / 4.0 * TAU + 0.6
		var r: float = rng.randf_range(330.0, 450.0)
		var base: Vector3 = center + Vector3(cos(a) * r, water_y + 10.0, sin(a) * r)
		var hw: float = rng.randf_range(26.0, 40.0)
		for t: int in 6:
			var h2: float = hw * (1.0 - float(t) * 0.14)
			var blk := Look.box(Vector3(h2 * 2.0, 8.0, h2 * 2.0), st, base + Vector3(0, 4.0 + 8.0 * float(t), 0))
			blk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(blk)
		var tmp := Look.box(Vector3(hw * 0.5, 10.0, hw * 0.4), st, base + Vector3(0, 53.0, 0))
		tmp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tmp)
	# blue mountains far out, with thin white waterfalls down their faces
	var mtn: StandardMaterial3D = Look.flat(Color(0.42, 0.52, 0.56), 0.95)
	for k: int in 9:
		var a: float = float(k) / 9.0 * TAU + rng.randf_range(-0.15, 0.15)
		var r: float = rng.randf_range(720.0, 900.0)
		var p: Vector3 = center + Vector3(cos(a) * r, water_y - 10.0, sin(a) * r)
		var h: float = rng.randf_range(140.0, 260.0)
		var cone := Look.cylinder(rng.randf_range(120.0, 190.0), h, mtn, p + Vector3(0, h * 0.5, 0), rng.randf_range(10.0, 30.0), 7)
		cone.rotation.y = rng.randf() * TAU
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(cone)
		if k % 3 == 0:
			var qm := QuadMesh.new()
			qm.size = Vector2(8.0, h * 0.55)
			var m := ShaderMaterial.new()
			m.shader = FALLS_SHADER
			m.set_shader_parameter("speed", 0.4)
			m.set_shader_parameter("opacity", 0.55)
			var to_c: Vector3 = (center - p)
			to_c.y = 0.0
			var q := Look.mesh_node(qm, m, p + to_c.normalized() * 95.0 + Vector3(0, h * 0.42, 0))
			q.rotation.y = atan2(to_c.x, to_c.z)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(q)
	# mist banks lying over the far canopy
	for k: int in 10:
		var a: float = float(k) / 10.0 * TAU
		var r: float = rng.randf_range(200.0, 360.0)
		JungleFx.mist(root, center + Vector3(cos(a) * r, water_y + 14.0, sin(a) * r), Vector3(60.0, 6.0, 60.0), 8)
