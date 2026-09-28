class_name ManorDecor
extends RefCounted
## Phantom Manor set dressing: leaning tombstones, crosses and obelisks, mausoleums, dead trees,
## iron railings, hedges, gas lamps with ghost flames, gothic stained-glass windows, candelabras,
## gargoyles, the great bronze bell, cliffs and the far silhouette of the manor's towers.
## Decoration only (no collision unless a caller asks); the level composes these around (never
## on) its route. Materials are shared.

const SURFACE: Shader = preload("res://visual/manor_stone.gdshader")
const GLASS: Shader = preload("res://visual/manor_glass.gdshader")

const STONE := Color(0.34, 0.31, 0.37)
const STONE_DARK := Color(0.16, 0.14, 0.18)
const WALL := Color(0.26, 0.22, 0.29)
const BARK := Color(0.11, 0.09, 0.09)
const IRON := Color(0.06, 0.05, 0.07)
const HEDGE := Color(0.07, 0.13, 0.08)
const BRASS := Color(0.7, 0.52, 0.24)
const BONE := Color(0.78, 0.74, 0.66)
const ROOF := Color(0.1, 0.09, 0.13)
const ECTO := Color(0.55, 1.0, 0.6)

var root: Node3D
var rng: RandomNumberGenerator
var _mats: Dictionary = {}


func _init(level_root: Node3D, random: RandomNumberGenerator) -> void:
	root = level_root
	rng = random


func _put(n: Node3D, pos: Vector3, parent: Node3D = null) -> Node3D:
	n.position = pos
	(parent if parent != null else root).add_child(n)
	return n


static func _ns(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---- materials ------------------------------------------------------------------------------

func stone(col: Color = STONE, rough: float = 0.92) -> StandardMaterial3D:
	return Look.flat(col, rough)


## Masonry in the manor's surface shader, for a box of `size` (courses, moulding, tracery).
func wall_mat(size: Vector3, col: Color = WALL, wood: float = 0.0) -> ShaderMaterial:
	var key: String = "wall|%s|%s|%.1f" % [str(size.snapped(Vector3.ONE * 0.1)), col.to_html(), wood]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter("top_color", col.lightened(0.25))
	m.set_shader_parameter("side_color", col)
	m.set_shader_parameter("trim_color", col.darkened(0.4))
	m.set_shader_parameter("half_size", size * 0.5)
	m.set_shader_parameter("trim_glow", 0.0)
	m.set_shader_parameter("wood", wood)
	_mats[key] = m
	return m


func glass_mat(seed_v: int, glow: float = 1.5) -> ShaderMaterial:
	var key: String = "glass|%d|%.1f" % [seed_v % 6, glow]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = GLASS
	m.set_shader_parameter("seed", float(seed_v % 6) * 1.37)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("broken", 0.12 + 0.05 * float(seed_v % 3))
	_mats[key] = m
	return m


## A solid block of masonry (walls the camera can lean on), turned by `yaw` (radians).
func wall(center: Vector3, size: Vector3, yaw: float = 0.0, col: Color = WALL, collide: bool = true) -> Node3D:
	var n: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		n = body
	else:
		n = Node3D.new()
	n.add_child(Look.box(size, wall_mat(size, col)))
	n.rotation.y = yaw
	return _put(n, center)


# ---- the graveyard --------------------------------------------------------------------------

## A gravestone on `base`: 0 round-topped slab, 1 cross, 2 obelisk, 3 a squat chest tomb. Leans.
func tombstone(base: Vector3, yaw: float, kind: int = -1, s: float = 1.0) -> Node3D:
	var k: int = kind if kind >= 0 else rng.randi_range(0, 3)
	var t := Node3D.new()
	var col: Color = STONE.lerp(STONE_DARK, rng.randf_range(0.0, 0.5))
	var m: StandardMaterial3D = stone(col)
	var moss: StandardMaterial3D = stone(Color(0.2, 0.26, 0.16))
	match k:
		0:
			t.add_child(Look.box(Vector3(0.9, 1.1, 0.2) * s, m, Vector3(0, 0.55, 0) * s))
			var cap := Look.cylinder(0.45 * s, 0.2 * s, m, Vector3(0, 1.1 * s, 0), -1.0, 14)
			cap.rotation.x = PI * 0.5
			t.add_child(cap)
			t.add_child(Look.box(Vector3(1.0, 0.12, 0.3) * s, moss, Vector3(0, 0.06, 0) * s))
		1:
			t.add_child(Look.box(Vector3(0.22, 1.7, 0.2) * s, m, Vector3(0, 0.85, 0) * s))
			t.add_child(Look.box(Vector3(0.9, 0.2, 0.2) * s, m, Vector3(0, 1.25, 0) * s))
			t.add_child(Look.box(Vector3(0.6, 0.3, 0.5) * s, moss, Vector3(0, 0.15, 0) * s))
		2:
			t.add_child(Look.box(Vector3(0.7, 0.5, 0.7) * s, m, Vector3(0, 0.25, 0) * s))
			var ob := Look.cylinder(0.3 * s, 2.2 * s, m, Vector3(0, 1.6, 0) * s, 0.12 * s, 4)
			ob.rotation.y = PI * 0.25
			t.add_child(ob)
		_:
			t.add_child(Look.box(Vector3(1.0, 0.7, 2.0) * s, m, Vector3(0, 0.35, 0) * s))
			t.add_child(Look.box(Vector3(1.15, 0.12, 2.15) * s, moss, Vector3(0, 0.76, 0) * s))
	t.rotation = Vector3(rng.randf_range(-0.14, 0.14), yaw, rng.randf_range(-0.16, 0.16))
	return _put(t, base)


## A mausoleum: a stone house of the dead with a pediment, two columns, a bronze door with green
## light leaking round it. Facing local +Z (turned by `yaw` rad). `collide` makes its body solid.
func mausoleum(base: Vector3, yaw: float, w: float = 4.0, d: float = 5.0, h: float = 4.0, collide: bool = false, pediment: bool = true) -> Node3D:
	var n := Node3D.new()
	var body_size := Vector3(w, h, d)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = body_size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, h * 0.5, 0)
		sb.add_child(cs)
		n.add_child(sb)
	n.add_child(Look.box(body_size, wall_mat(body_size, STONE.darkened(0.2)), Vector3(0, h * 0.5, 0)))
	if pediment:
		var pm := PrismMesh.new()
		pm.size = Vector3(w + 0.6, 1.4, d + 0.6)
		n.add_child(Look.mesh_node(pm, stone(STONE_DARK), Vector3(0, h + 0.7, 0)))
		n.add_child(Look.box(Vector3(w + 0.5, 0.3, d + 0.5), stone(STONE), Vector3(0, h + 0.05, 0)))
		n.add_child(Look.cylinder(0.14, 0.5, stone(STONE), Vector3(0, h + 1.65, d * 0.5 + 0.2), 0.02, 6))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.cylinder(0.22, h - 0.3, stone(BONE.darkened(0.3)), Vector3(sx * (w * 0.5 - 0.35), (h - 0.3) * 0.5, d * 0.5 + 0.35), 0.2, 10))
	var door := Look.box(Vector3(w * 0.36, h * 0.6, 0.12), Look.flat(Color(0.2, 0.16, 0.08), 0.5, 0.7), Vector3(0, h * 0.3, d * 0.5 + 0.02))
	n.add_child(door)
	var leak := Look.box(Vector3(w * 0.4, h * 0.64, 0.05), Look.flat(ECTO, 0.4, 0.0, 1.6), Vector3(0, h * 0.31, d * 0.5 - 0.02))
	n.add_child(_ns(leak))
	n.rotation.y = yaw
	return _put(n, base)


## A dead tree: a gnarled trunk splitting into bare, crooked limbs. `height` in metres.
func dead_tree(base: Vector3, height: float, yaw: float = 0.0) -> Node3D:
	var t := Node3D.new()
	var m: StandardMaterial3D = stone(BARK, 0.95)
	var trunk_r: float = height * 0.055
	t.add_child(Look.cylinder(trunk_r, height * 0.6, m, Vector3(0, height * 0.3, 0), trunk_r * 0.6, 7))
	# roots
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + rng.randf() * 0.5
		var r := Look.cylinder(trunk_r * 0.5, height * 0.2, m, Vector3(cos(a), 0, sin(a)) * trunk_r * 1.2, 0.02, 5)
		r.rotation = Vector3(0, -a, 1.1)
		r.rotation = Vector3(sin(a) * 1.1, 0, -cos(a) * 1.1)
		t.add_child(r)
	_limbs(t, Vector3(0, height * 0.55, 0), Vector3.UP, height * 0.45, trunk_r * 0.6, 3, m)
	t.rotation.y = yaw
	return _put(t, base)


func _limbs(parent: Node3D, from: Vector3, dir: Vector3, length: float, r: float, depth: int, m: Material) -> void:
	var n: int = 3 if depth >= 2 else 2
	for i: int in n:
		var a: float = TAU * float(i) / float(n) + rng.randf_range(-0.5, 0.5)
		var d: Vector3 = (dir + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, 1.1)).normalized()
		var l: float = length * rng.randf_range(0.6, 0.9)
		var to: Vector3 = from + d * l
		var c := Look.cylinder(r, l, m, (from + to) * 0.5, r * 0.45, 5)
		var side: Vector3 = d.cross(Vector3(0.3, 0.2, 0.9)).normalized()
		c.basis = Basis(side, d, side.cross(d))
		parent.add_child(c)
		if depth > 1:
			_limbs(parent, to, (d + Vector3(0, 0.4, 0)).normalized(), l * 0.7, r * 0.5, depth - 1, m)


## An iron railing between two floor points, with spear-headed posts.
func fence(a: Vector3, b: Vector3, height: float = 1.6) -> void:
	var m: StandardMaterial3D = Look.flat(IRON, 0.5, 0.7)
	var d: Vector3 = b - a
	var n: int = maxi(int(d.length() / 0.35), 2)
	var holder := Node3D.new()
	_put(holder, a)
	var dir: Vector3 = d.normalized()
	var yaw: float = atan2(-dir.x, -dir.z)
	for i: int in n + 1:
		var p: Vector3 = d * float(i) / float(n)
		holder.add_child(Look.cylinder(0.025, height, m, p + Vector3(0, height * 0.5, 0), -1.0, 4))
		holder.add_child(Look.cylinder(0.05, 0.16, m, p + Vector3(0, height + 0.08, 0), 0.0, 4))
	for y: float in [0.3, height - 0.2]:
		var rail := Look.box(Vector3(0.05, 0.05, d.length()), m, d * 0.5 + Vector3(0, y, 0))
		rail.rotation.y = yaw
		holder.add_child(rail)


## A clipped hedge block (the maze walls), dark and shaggy.
func hedge(center: Vector3, size: Vector3, yaw: float = 0.0, collide: bool = false) -> Node3D:
	var n: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		n = body
	else:
		n = Node3D.new()
	var leaf: StandardMaterial3D = Look.flat(HEDGE, 0.95)
	n.add_child(Look.box(size, leaf))
	# lumps along the top
	var k: int = maxi(int(maxf(size.x, size.z) / 1.2), 2)
	var along_x: bool = size.x >= size.z
	for i: int in k:
		var f: float = (float(i) + 0.5) / float(k) - 0.5
		var p := Vector3(f * size.x, size.y * 0.5, 0) if along_x else Vector3(0, size.y * 0.5, f * size.z)
		var s := Look.sphere(0.5, Look.flat(HEDGE.lightened(rng.randf_range(0.0, 0.12)), 0.95), p)
		s.scale = Vector3(1.3, 0.6, 1.3) * minf(minf(size.x, size.z), 1.4)
		n.add_child(s)
	n.rotation.y = yaw
	return _put(n, center)


## A gas lamp on an iron post with a ghostly green flame (light optional).
func lamp_post(base: Vector3, height: float = 3.4, light: bool = true, col: Color = ECTO) -> Node3D:
	var n := Node3D.new()
	var iron: StandardMaterial3D = Look.flat(IRON, 0.5, 0.7)
	n.add_child(Look.cylinder(0.07, height, iron, Vector3(0, height * 0.5, 0), 0.05, 6))
	n.add_child(Look.box(Vector3(0.38, 0.06, 0.38), iron, Vector3(0, height + 0.02, 0)))
	n.add_child(Look.cylinder(0.26, 0.3, iron, Vector3(0, height + 0.7, 0), 0.02, 4))
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			n.add_child(Look.box(Vector3(0.03, 0.5, 0.03), iron, Vector3(x * 0.16, height + 0.3, z * 0.16)))
	var glow := Fx.sprite(Fx.hot(col, 1.3), 0.9, Fx.Tex.DOT)
	glow.position = Vector3(0, height + 0.3, 0)
	n.add_child(glow)
	ManorFx.flame(n, Vector3(0, height + 0.15, 0), 0.7, col)
	if light:
		var o := OmniLight3D.new()
		o.light_color = col
		o.light_energy = 1.4
		o.omni_range = 9.0
		o.shadow_enabled = false
		o.position = Vector3(0, height + 0.3, 0)
		n.add_child(o)
	return _put(n, base)


## A weeping angel on a plinth (a grave monument), facing local +Z turned by `yaw`.
func angel(base: Vector3, yaw: float, s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	var m: StandardMaterial3D = stone(STONE.lightened(0.1))
	n.add_child(Look.box(Vector3(1.2, 1.0, 1.2) * s, stone(STONE_DARK), Vector3(0, 0.5, 0) * s))
	n.add_child(Look.cylinder(0.45 * s, 1.8 * s, m, Vector3(0, 1.9 * s, 0), 0.25 * s, 10))
	var head := Look.sphere(0.24 * s, m, Vector3(0, 3.0 * s, 0.12 * s))
	n.add_child(head)
	for sx: float in [-1.0, 1.0]:
		var wing := Look.box(Vector3(0.12, 1.8, 0.8) * s, m, Vector3(sx * 0.42, 2.4, -0.35) * s)
		wing.rotation = Vector3(0.3, sx * 0.5, sx * 0.25)
		n.add_child(wing)
		var arm := Look.cylinder(0.08 * s, 0.8 * s, m, Vector3(sx * 0.14, 2.75, 0.3) * s, -1.0, 6)
		arm.rotation.x = 1.0
		n.add_child(arm)
	n.rotation.y = yaw
	return _put(n, base)


# ---- the house ------------------------------------------------------------------------------

## A lancet window of glowing stained glass in a stone surround, on a wall facing `yaw` (the
## glass faces local +Z). `light` adds a coloured glow spilling out.
func window(center: Vector3, yaw: float, w: float = 1.6, h: float = 3.6, seed_v: int = 0, light: bool = false) -> Node3D:
	var n := Node3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	n.add_child(_ns(Look.mesh_node(q, glass_mat(seed_v), Vector3(0, 0, 0.02))))
	var m: StandardMaterial3D = stone(STONE.darkened(0.1))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.22, h + 0.2, 0.3), m, Vector3(sx * (w * 0.5 + 0.11), 0, 0)))
	n.add_child(Look.box(Vector3(w + 0.6, 0.22, 0.4), m, Vector3(0, -h * 0.5 - 0.11, 0.05)))
	var cap := Look.cylinder(0.14, 0.34, m, Vector3(0, h * 0.5 + 0.12, 0.0), 0.02, 4)
	n.add_child(cap)
	if light:
		var o := OmniLight3D.new()
		o.light_color = [Color(0.7, 0.4, 1.0), Color(1.0, 0.35, 0.3), Color(0.5, 1.0, 0.6)][seed_v % 3]
		o.light_energy = 1.1
		o.omni_range = 7.0
		o.shadow_enabled = false
		o.position = Vector3(0, 0, 1.2)
		n.add_child(o)
	n.rotation.y = yaw
	return _put(n, center)


## A tall iron candelabra with `arms` candles (ghost-green or warm), optional light.
func candelabra(base: Vector3, height: float = 2.2, light: bool = false, col: Color = ManorFx.CANDLE) -> Node3D:
	var n := Node3D.new()
	var m: StandardMaterial3D = Look.flat(BRASS.darkened(0.3), 0.4, 0.8)
	var wax: StandardMaterial3D = Look.flat(Color(0.88, 0.86, 0.78), 0.6)
	n.add_child(Look.cylinder(0.3, 0.1, m, Vector3(0, 0.05, 0), 0.2, 10))
	n.add_child(Look.cylinder(0.05, height, m, Vector3(0, height * 0.5, 0), 0.04, 6))
	var bar := Look.box(Vector3(1.0, 0.05, 0.05), m, Vector3(0, height - 0.05, 0))
	n.add_child(bar)
	for x: float in [-0.5, 0.0, 0.5]:
		var y: float = height + (0.15 if x == 0.0 else 0.0)
		n.add_child(Look.cylinder(0.06, 0.08, m, Vector3(x, y, 0), -1.0, 6))
		n.add_child(Look.cylinder(0.04, 0.3, wax, Vector3(x, y + 0.18, 0), -1.0, 6))
		var f := Fx.sprite(Fx.hot(col, 1.4), 0.26, Fx.Tex.DOT)
		f.position = Vector3(x, y + 0.42, 0)
		n.add_child(f)
	if light:
		var o := OmniLight3D.new()
		o.light_color = col
		o.light_energy = 1.3
		o.omni_range = 7.0
		o.shadow_enabled = false
		o.position = Vector3(0, height + 0.5, 0)
		n.add_child(o)
	return _put(n, base)


## A gargoyle crouched on a ledge (facing local +Z turned by yaw), eyes glowing.
func gargoyle(base: Vector3, yaw: float, s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	var m: StandardMaterial3D = stone(STONE_DARK.lightened(0.05))
	var body := Look.sphere(0.5 * s, m, Vector3(0, 0.5, 0) * s)
	body.scale = Vector3(1.0, 1.1, 1.3)
	n.add_child(body)
	var head := Look.sphere(0.3 * s, m, Vector3(0, 1.0, 0.45) * s)
	n.add_child(head)
	for sx: float in [-1.0, 1.0]:
		var wing := Look.box(Vector3(0.08, 0.9, 0.7) * s, m, Vector3(sx * 0.55, 0.9, -0.2) * s)
		wing.rotation = Vector3(-0.3, sx * 0.4, sx * 0.5)
		n.add_child(wing)
		var horn := Look.cylinder(0.06 * s, 0.35 * s, m, Vector3(sx * 0.15, 1.3, 0.4) * s, 0.0, 5)
		horn.rotation.z = -sx * 0.4
		n.add_child(horn)
		n.add_child(_ns(Look.sphere(0.05 * s, Look.flat(Color(1.0, 0.25, 0.2), 0.4, 0.0, 2.5), Vector3(sx * 0.1, 1.05, 0.72) * s)))
	n.rotation.y = yaw
	return _put(n, base)


## The great bronze bell (hanging from its top at `pos`), returned so the level can swing it.
func bell(pos: Vector3, r: float = 1.6) -> Node3D:
	var n := Node3D.new()
	var bronze: StandardMaterial3D = Look.flat(Color(0.5, 0.36, 0.2), 0.35, 0.85)
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.5
	cm.bottom_radius = r
	cm.height = r * 1.5
	cm.radial_segments = 28
	n.add_child(Look.mesh_node(cm, bronze, Vector3(0, -r * 0.75 - 0.3, 0)))
	n.add_child(Look.sphere(r * 0.5, bronze, Vector3(0, -0.3, 0)))
	var lip := Look.cylinder(r * 1.06, 0.18, bronze, Vector3(0, -r * 1.5 - 0.3, 0), -1.0, 28)
	n.add_child(lip)
	n.add_child(Look.sphere(r * 0.22, Look.flat(Color(0.2, 0.16, 0.12), 0.5, 0.8), Vector3(0, -r * 1.55 - 0.3, 0)))
	n.add_child(Look.box(Vector3(0.3, 0.5, 0.3), Look.flat(IRON, 0.5, 0.7), Vector3(0, 0.1, 0)))
	return _put(n, pos)


# ---- landscape and far scenery ----------------------------------------------------------------

## A mass of dark cliff rock (no collision): a few lumpy stacked boxes and boulders.
func cliff(center: Vector3, size: Vector3, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	var m: StandardMaterial3D = stone(Color(0.13, 0.12, 0.15), 0.95)
	var m2: StandardMaterial3D = stone(Color(0.18, 0.16, 0.2), 0.95)
	n.add_child(Look.box(size, m))
	for i: int in 5:
		var s := Vector3(size.x * rng.randf_range(0.35, 0.6), size.y * rng.randf_range(0.3, 0.7), size.z * rng.randf_range(0.35, 0.6))
		var p := Vector3(rng.randf_range(-0.5, 0.5) * size.x, rng.randf_range(-0.3, 0.2) * size.y, rng.randf_range(-0.5, 0.5) * size.z)
		var b := Look.box(s, m2 if i % 2 == 0 else m, p)
		b.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))
		n.add_child(b)
	n.rotation.y = yaw
	return _put(n, center)


## A round gothic tower with a conical slate roof, a finial, and lit slit windows.
func tower(base: Vector3, r: float, h: float, roof_h: float, windows: int = 3, lean: float = 0.0) -> Node3D:
	var n := Node3D.new()
	var body_m: StandardMaterial3D = stone(WALL.darkened(0.25))
	n.add_child(Look.cylinder(r, h, body_m, Vector3(0, h * 0.5, 0), r * 0.92, 14))
	n.add_child(Look.cylinder(r * 1.12, 0.6, stone(STONE_DARK), Vector3(0, h, 0), -1.0, 14))
	n.add_child(Look.cylinder(r * 1.18, roof_h, Look.flat(ROOF, 0.6, 0.3), Vector3(0, h + roof_h * 0.5 + 0.3, 0), 0.0, 14))
	n.add_child(Look.cylinder(0.08 * r, roof_h * 0.35, Look.flat(IRON, 0.5, 0.7), Vector3(0, h + roof_h + 0.3 + roof_h * 0.17, 0), 0.0, 4))
	for i: int in windows:
		var a: float = rng.randf() * TAU
		var y: float = h * (0.35 + 0.5 * float(i) / float(maxi(windows, 1)))
		var q := QuadMesh.new()
		q.size = Vector2(r * 0.35, r * 0.9)
		var w := Look.mesh_node(q, glass_mat(i + int(absf(base.x))), Vector3(sin(a), 0, cos(a)) * (r * 0.97) + Vector3(0, y, 0))
		w.rotation.y = a
		n.add_child(_ns(w))
	n.rotation.z = lean
	return _put(n, base)


## The manor seen from afar: a crooked pile of gables, wings and towers on its hill, dozens of
## windows glowing, chimneys smoking. Facing local +Z turned by `yaw`. Cheap: boxes and cones.
func manor(center: Vector3, yaw: float, s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	_put(n, center)
	n.rotation.y = yaw
	var body: StandardMaterial3D = stone(WALL.darkened(0.3))
	var roof: StandardMaterial3D = Look.flat(ROOF, 0.6, 0.3)
	var blocks: Array = [
		[Vector3(0, 0, 0), Vector3(40, 22, 18)], [Vector3(-30, 0, 4), Vector3(22, 16, 14)],
		[Vector3(30, 0, 2), Vector3(22, 18, 14)], [Vector3(-8, 22, -2), Vector3(16, 10, 10)],
	]
	for b: Array in blocks:
		var p: Vector3 = (b[0] as Vector3) * s
		var sz: Vector3 = (b[1] as Vector3) * s
		n.add_child(Look.box(sz, body, p + Vector3(0, sz.y * 0.5, 0)))
		var pm := PrismMesh.new()
		pm.size = Vector3(sz.x + 1.0 * s, sz.y * 0.5, sz.z + 1.0 * s)
		n.add_child(Look.mesh_node(pm, roof, p + Vector3(0, sz.y + sz.y * 0.25, 0)))
		# rows of lit windows on the front
		var cols: int = int(sz.x / (4.0 * s))
		var rows: int = int(sz.y / (6.0 * s))
		for i: int in cols:
			for j: int in rows:
				if rng.randf() < 0.35:
					continue
				var q := QuadMesh.new()
				q.size = Vector2(1.4, 2.8) * s
				var w := Look.mesh_node(q, glass_mat(i * 3 + j, 1.8), p + Vector3(-sz.x * 0.5 + (float(i) + 0.5) * sz.x / float(cols), (float(j) + 0.55) * sz.y / float(rows), sz.z * 0.5 + 0.05))
				n.add_child(_ns(w))
	var towers: Array = [[Vector3(-44, 0, 0), 5.0, 40.0, 16.0], [Vector3(20, 0, -6), 4.0, 48.0, 18.0], [Vector3(-16, 30, -2), 3.0, 18.0, 12.0], [Vector3(44, 0, 6), 4.5, 34.0, 14.0]]
	for t: Array in towers:
		var tn: Node3D = tower(Vector3.ZERO, float(t[1]) * s, float(t[2]) * s, float(t[3]) * s, 4, rng.randf_range(-0.04, 0.04))
		tn.get_parent().remove_child(tn)
		tn.position = (t[0] as Vector3) * s
		n.add_child(tn)
	for i: int in 5:
		var cp := Vector3(rng.randf_range(-40, 40), 26, rng.randf_range(-6, 6)) * s
		n.add_child(Look.box(Vector3(2.0, 8.0, 2.0) * s, body, cp))
	return n
