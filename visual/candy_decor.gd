class_name CandyDecor
extends RefCounted
## Sugar Rush set dressing, all built from primitives: lollipops and lollipop trees, candy canes,
## gumdrops, cupcakes, doughnuts, ice-cream cones and ice-cream mountains, toy blocks, layer cakes,
## a cake castle, a 3D rainbow, the chocolate sea, rivers and falls, wafer walls, chocolate bars
## and the great gumball machine. Nothing here collides unless it says so. Materials are cached.

const STRIPE: Shader = preload("res://visual/candy_stripe.gdshader")
const SWIRL: Shader = preload("res://visual/candy_swirl.gdshader")
const CHOCO: Shader = preload("res://visual/candy_choco.gdshader")
const WAFFLE: Shader = preload("res://visual/candy_waffle.gdshader")

const PINK := Color(1.0, 0.45, 0.65)
const MINT := Color(0.5, 0.95, 0.78)
const LEMON := Color(1.0, 0.9, 0.4)
const SKY := Color(0.5, 0.78, 1.0)
const GRAPE := Color(0.72, 0.52, 1.0)
const ORANGE := Color(1.0, 0.62, 0.3)
const CREAM := Color(1.0, 0.96, 0.9)
const CHERRY := Color(1.0, 0.15, 0.25)
const COCOA := Color(0.36, 0.2, 0.12)

static var _mats: Dictionary = {}

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r
	_mats.clear()


func _add(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	root.add_child(n)
	return n


# ---- materials ------------------------------------------------------------------------------

static func stripe_material(a: Color, b: Color, stripes: float = 3.0, twist: float = 1.0, world: bool = false, glow: float = 0.0) -> ShaderMaterial:
	var key: String = "st|%s|%s|%.2f|%.2f|%s|%.2f" % [a.to_html(), b.to_html(), stripes, twist, world, glow]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = STRIPE
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("stripes", stripes)
	m.set_shader_parameter("twist", twist)
	m.set_shader_parameter("world_twist", world)
	m.set_shader_parameter("glow", glow)
	_mats[key] = m
	return m


static func swirl_material(a: Color, b: Color, arms: float = 3.0, radius: float = 1.0, glow: float = 0.0) -> ShaderMaterial:
	var key: String = "sw|%s|%s|%.2f|%.2f|%.2f" % [a.to_html(), b.to_html(), arms, radius, glow]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SWIRL
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("arms", arms)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("glow", glow)
	_mats[key] = m
	return m


static func choco_material(flow: Vector2 = Vector2(0, 0.4), falling: bool = false, cream: float = 0.25) -> ShaderMaterial:
	var key: String = "ch|%s|%s|%.2f" % [flow, falling, cream]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = CHOCO
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("falling", falling)
	m.set_shader_parameter("cream_amount", cream)
	_mats[key] = m
	return m


static func waffle_material(square: bool = false, base: Color = Color(0.9, 0.64, 0.34), cell: float = 0.55) -> ShaderMaterial:
	var key: String = "wf|%s|%s|%.2f" % [square, base.to_html(), cell]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = WAFFLE
	m.set_shader_parameter("square", square)
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("ridge_color", base.darkened(0.35))
	m.set_shader_parameter("cell", cell)
	_mats[key] = m
	return m


## Sugar-coated soft candy (gumdrops): matte with a faint sparkle sheen.
static func sugar(c: Color) -> StandardMaterial3D:
	var key: String = "sg|%s" % c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.6
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.12
	_mats[key] = m
	return m


## Hard glossy candy.
static func gloss(c: Color, emit: float = 0.0) -> StandardMaterial3D:
	var key: String = "gl|%s|%.2f" % [c.to_html(), emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.12
	m.metallic_specular = 0.8
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


func pick_pastel() -> Color:
	return [PINK, MINT, LEMON, SKY, GRAPE, ORANGE][rng.randi() % 6]


# ---- sweets ---------------------------------------------------------------------------------

## A lollipop standing on its stick; the disc faces along `yaw` (radians).
func lollipop(pos: Vector3, height: float, r: float, a: Color = PINK, b: Color = CREAM, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.add_child(Look.cylinder(r * 0.08, height, Look.flat(CREAM, 0.5), Vector3(0, height * 0.5, 0), -1.0, 8))
	var disc := Look.cylinder(r, r * 0.3, swirl_material(a, b, 3.0, r), Vector3(0, height + r * 0.85, 0), -1.0, 32)
	disc.rotation.x = PI * 0.5
	n.add_child(disc)
	# a ribbon bow at the neck
	for s: float in [-1.0, 1.0]:
		var bow := Look.sphere(r * 0.18, gloss(a.lightened(0.2)), Vector3(s * r * 0.2, height - r * 0.05, 0))
		bow.scale = Vector3(1.3, 0.6, 0.5)
		n.add_child(bow)
	n.rotation.y = yaw
	return _add(n, pos)


## A lollipop tree: a thick striped trunk and a big round swirled sucker.
func lollipop_tree(pos: Vector3, height: float, r: float, a: Color = PINK) -> Node3D:
	var n := Node3D.new()
	n.add_child(Look.cylinder(r * 0.12, height, stripe_material(CREAM, a.lightened(0.3), 2.0, 0.5, true), Vector3(0, height * 0.5, 0), r * 0.1, 10))
	var ball := Look.sphere(r, swirl_material(a, CREAM, 4.0, r), Vector3(0, height + r * 0.9, 0))
	ball.rotation.x = rng.randf_range(-0.3, 0.3)
	n.add_child(ball)
	n.rotation.y = rng.randf() * TAU
	return _add(n, pos)


## A candy cane standing up with its hook at the top.
func candy_cane(pos: Vector3, height: float, r: float, yaw: float = 0.0, a: Color = CHERRY) -> Node3D:
	var n := Node3D.new()
	var mat: ShaderMaterial = stripe_material(a, CREAM, 3.0, 0.6, true)
	n.add_child(Look.cylinder(r, height, mat, Vector3(0, height * 0.5, 0), -1.0, 14))
	var hook_r: float = r * 3.2
	var segs: int = 8
	for i: int in segs:
		var a0: float = PI * float(i) / float(segs)
		var a1: float = PI * float(i + 1) / float(segs)
		var p0 := Vector3(hook_r - hook_r * cos(a0), height + hook_r * sin(a0), 0)
		var p1 := Vector3(hook_r - hook_r * cos(a1), height + hook_r * sin(a1), 0)
		var seg := Look.cylinder(r, p0.distance_to(p1) + r * 0.4, mat, (p0 + p1) * 0.5, -1.0, 14)
		var up: Vector3 = (p1 - p0).normalized()
		seg.basis = Basis(up.cross(Vector3.BACK).normalized(), up, Vector3.BACK).orthonormalized()
		n.add_child(seg)
	n.rotation.y = yaw
	return _add(n, pos)


## A sugared gumdrop hill (or a small gumdrop).
func gumdrop(pos: Vector3, r: float, c: Color) -> Node3D:
	var n := Node3D.new()
	var mat: StandardMaterial3D = sugar(c)
	n.add_child(Look.cylinder(r, r * 0.9, mat, Vector3(0, r * 0.45, 0), r * 0.62, 24))
	var cap := Look.sphere(r * 0.62, mat, Vector3(0, r * 0.9, 0))
	cap.scale = Vector3(1.0, 0.7, 1.0)
	n.add_child(cap)
	return _add(n, pos)


## A cupcake: a ribbed paper liner, a piped swirl of frosting and a cherry.
func cupcake(pos: Vector3, r: float, frost: Color = PINK, liner: Color = SKY) -> Node3D:
	var n := Node3D.new()
	var h: float = r * 1.1
	n.add_child(Look.cylinder(r * 0.8, h, Look.flat(liner, 0.7), Vector3(0, h * 0.5, 0), r, 18))
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0
		var rib := Look.box(Vector3(r * 0.08, h * 0.98, r * 0.08), Look.flat(liner.darkened(0.15), 0.7), Vector3(cos(a), 0, sin(a)) * r * 0.9 + Vector3(0, h * 0.5, 0))
		rib.rotation.y = -a
		rib.rotation.z = 0.18 * 0.0
		n.add_child(rib)
	var fm: StandardMaterial3D = Look.flat(frost, 0.55)
	for i: int in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = r * (0.55 - 0.18 * float(i))
		tm.outer_radius = r * (1.05 - 0.28 * float(i))
		tm.rings = 24
		tm.ring_segments = 12
		n.add_child(Look.mesh_node(tm, fm, Vector3(0, h + r * (0.18 + 0.3 * float(i)), 0)))
	n.add_child(Look.sphere(r * 0.2, gloss(CHERRY, 0.1), Vector3(0, h + r * 1.05, 0)))
	return _add(n, pos)


## A glazed doughnut with sprinkles, turned by `rot` (radians, Euler).
func donut(pos: Vector3, r: float, rot: Vector3, icing: Color = PINK) -> Node3D:
	var n := Node3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.45
	tm.outer_radius = r
	tm.rings = 32
	tm.ring_segments = 16
	n.add_child(Look.mesh_node(tm, Look.flat(Color(0.88, 0.6, 0.32), 0.8)))
	var ic := TorusMesh.new()
	ic.inner_radius = r * 0.47
	ic.outer_radius = r * 0.98
	ic.rings = 32
	ic.ring_segments = 16
	var icing_n := Look.mesh_node(ic, gloss(icing), Vector3(0, r * 0.08, 0))
	icing_n.scale = Vector3(1.0, 0.8, 1.0)
	n.add_child(icing_n)
	for i: int in 14:
		var a: float = rng.randf() * TAU
		var rr: float = rng.randf_range(0.55, 0.9) * r
		var sp := Look.box(Vector3(r * 0.14, r * 0.04, r * 0.04), Look.flat(pick_pastel(), 0.5), Vector3(cos(a) * rr, r * 0.3, sin(a) * rr))
		sp.rotation.y = rng.randf() * TAU
		n.add_child(sp)
	n.rotation = rot
	return _add(n, pos)


## An ice-cream cone (point down) with two scoops.
func ice_cream(pos: Vector3, h: float, a: Color = PINK, b: Color = MINT) -> Node3D:
	var n := Node3D.new()
	var r: float = h * 0.3
	n.add_child(Look.cylinder(0.02, h, waffle_material(false, Color(0.9, 0.64, 0.34), h * 0.12), Vector3(0, h * 0.5, 0), r, 16))
	n.add_child(Look.sphere(r * 1.05, Look.flat(a, 0.6), Vector3(0, h + r * 0.5, 0)))
	n.add_child(Look.sphere(r * 0.9, Look.flat(b, 0.6), Vector3(0, h + r * 1.5, 0)))
	n.add_child(Look.sphere(r * 0.18, gloss(CHERRY), Vector3(0, h + r * 2.4, 0)))
	return _add(n, pos)


## A painted wooden toy block (yaw in radians).
func toy_block(pos: Vector3, s: float, c: Color, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.add_child(Look.box(Vector3.ONE * s, Look.flat(c, 0.55)))
	var face: StandardMaterial3D = Look.flat(c.lightened(0.35), 0.55)
	for f: int in 6:
		var nrm: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD][f]
		var sz := Vector3(s * 0.7, s * 0.7, s * 0.7)
		sz = sz * (Vector3.ONE - nrm.abs()) + nrm.abs() * 0.04
		n.add_child(Look.box(sz, face, nrm * (s * 0.5 + 0.01)))
	n.rotation.y = yaw
	return _add(n, pos + Vector3(0, s * 0.5, 0))


## A layer cake with drips and candles (static decor).
func cake(pos: Vector3, r: float, tiers: int, c: Color = PINK) -> Node3D:
	var n := Node3D.new()
	var y: float = 0.0
	for i: int in tiers:
		var rr: float = r * (1.0 - 0.22 * float(i))
		var h: float = r * 0.55
		n.add_child(Look.cylinder(rr, h, Look.flat(CREAM if i % 2 == 0 else c.lightened(0.3), 0.7), Vector3(0, y + h * 0.5, 0), -1.0, 28))
		n.add_child(Look.cylinder(rr * 1.02, h * 0.18, Look.flat(c, 0.5), Vector3(0, y + h * 0.95, 0), -1.0, 28))
		for k: int in 8:
			var a: float = TAU * float(k) / 8.0 + 0.2 * float(i)
			var drip := Look.sphere(rr * 0.09, Look.flat(c, 0.5), Vector3(cos(a) * rr * 1.0, y + h * 0.78, sin(a) * rr * 1.0))
			drip.scale = Vector3(0.8, 2.2, 0.8)
			n.add_child(drip)
		y += h
	for k: int in 5:
		var a2: float = TAU * float(k) / 5.0
		var cp := Vector3(cos(a2), 0, sin(a2)) * r * 0.4 + Vector3(0, y, 0)
		n.add_child(Look.cylinder(r * 0.03, r * 0.3, stripe_material(SKY, CREAM, 2.0, 2.0), cp + Vector3(0, r * 0.15, 0), -1.0, 8))
		var flame := Fx.sprite(Color(2.4, 1.6, 0.6), r * 0.18, Fx.Tex.DOT)
		flame.position = cp + Vector3(0, r * 0.36, 0)
		n.add_child(flame)
	return _add(n, pos)


## Far scenery: a castle of cake - tiered keep, candy towers with cone roofs, flags.
func castle(pos: Vector3, k: float) -> Node3D:
	var n := Node3D.new()
	var walls: StandardMaterial3D = Look.flat(Color(1.0, 0.9, 0.93), 0.8)
	var roof_a: StandardMaterial3D = gloss(PINK)
	var roof_b: StandardMaterial3D = gloss(SKY)
	n.add_child(Look.cylinder(26.0 * k, 16.0 * k, walls, Vector3(0, 8.0 * k, 0), 24.0 * k, 32))
	n.add_child(Look.cylinder(26.6 * k, 2.0 * k, Look.flat(PINK, 0.5), Vector3(0, 15.5 * k, 0), -1.0, 32))
	n.add_child(Look.cylinder(17.0 * k, 16.0 * k, Look.flat(Color(0.8, 0.92, 1.0), 0.8), Vector3(0, 24.0 * k, 0), 15.0 * k, 32))
	n.add_child(Look.cylinder(17.5 * k, 1.8 * k, Look.flat(MINT, 0.5), Vector3(0, 31.5 * k, 0), -1.0, 32))
	n.add_child(Look.cylinder(9.0 * k, 14.0 * k, walls, Vector3(0, 39.0 * k, 0), 8.0 * k, 24))
	n.add_child(Look.cylinder(9.5 * k, 16.0 * k, roof_a, Vector3(0, 54.0 * k, 0), 0.0, 24))
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var tp := Vector3(cos(a), 0, sin(a)) * 25.0 * k
		var th: float = (24.0 + 8.0 * float(i % 2)) * k
		n.add_child(Look.cylinder(3.6 * k, th, stripe_material(PINK.lightened(0.3), CREAM, 2.0, 0.08 / k, true), tp + Vector3(0, th * 0.5, 0), -1.0, 16))
		n.add_child(Look.cylinder(4.4 * k, 9.0 * k, roof_a if i % 2 == 0 else roof_b, tp + Vector3(0, th + 4.5 * k, 0), 0.0, 16))
		n.add_child(Look.sphere(0.9 * k, gloss(LEMON, 0.6), tp + Vector3(0, th + 9.4 * k, 0)))
	return _add(n, pos)


## Far scenery: a mountain of ice cream - a scooped cone of strawberry, a snowcap of whipped
## cream and chocolate sauce running down.
func mountain(pos: Vector3, r: float, h: float, c: Color = PINK) -> Node3D:
	var n := Node3D.new()
	n.add_child(Look.cylinder(r, h, Look.flat(c, 0.85), Vector3(0, h * 0.5, 0), r * 0.18, 20))
	var cap := Look.sphere(r * 0.34, Look.flat(CREAM, 0.9), Vector3(0, h * 0.97, 0))
	cap.scale = Vector3(1.0, 0.55, 1.0)
	n.add_child(cap)
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + rng.randf() * 0.4
		var run := Look.cylinder(r * 0.07, h * 0.45, choco_material(Vector2.ZERO, true, 0.1), Vector3(cos(a) * r * 0.36, h * 0.74, sin(a) * r * 0.36), r * 0.05, 8)
		run.rotation = Vector3(sin(a) * 0.22, 0, -cos(a) * 0.22)
		n.add_child(run)
	n.add_child(Look.sphere(r * 0.1, gloss(CHERRY, 0.15), Vector3(0, h * 1.1, 0)))
	n.rotation.y = rng.randf() * TAU
	return _add(n, pos)


## A 3D rainbow arch: six coloured bands, centred on `pos` (half of it is under the sea), facing yaw.
func rainbow(pos: Vector3, radius: float, width: float, yaw: float) -> Node3D:
	var n := Node3D.new()
	var cols: Array[Color] = [Color(1.0, 0.3, 0.35), Color(1.0, 0.6, 0.25), Color(1.0, 0.92, 0.35),
			Color(0.45, 0.9, 0.45), Color(0.4, 0.7, 1.0), Color(0.7, 0.45, 1.0)]
	for i: int in cols.size():
		var tm := TorusMesh.new()
		var ro: float = radius - float(i) * width
		tm.inner_radius = ro - width
		tm.outer_radius = ro
		tm.rings = 96
		tm.ring_segments = 8
		var band := Look.mesh_node(tm, Look.flat(cols[i], 0.5, 0.0, 0.6))
		band.rotation.x = PI * 0.5
		band.scale = Vector3(1.0, 0.35, 1.0)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(band)
	n.rotation.y = yaw
	return _add(n, pos)


## A flat of molten chocolate (visual only) centred at `c`, size (x, z), turned by yaw (radians).
func choco_plane(c: Vector3, size: Vector2, yaw: float = 0.0, flow: Vector2 = Vector2(0, 0.4)) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var mi := Look.mesh_node(pm, choco_material(flow, false, 0.25), c)
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


## A chocolate fall pouring down from `top` (width across, height down), facing yaw (radians).
func choco_fall(top: Vector3, width: float, height: float, yaw: float) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(width, height, 0.4)
	var mi := Look.mesh_node(b, choco_material(Vector2.ZERO, true, 0.12), top - Vector3(0, height * 0.5, 0))
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


## A wafer slab (visual; walls behind the wall runs).
func wafer(c: Vector3, size: Vector3, yaw: float) -> MeshInstance3D:
	var mi := Look.box(size, waffle_material(true, Color(0.95, 0.78, 0.5), 0.35), c)
	mi.rotation.y = yaw
	root.add_child(mi)
	# a cream filling seam along the top
	var top := Look.box(Vector3(size.x * 1.01, 0.14, size.z * 0.7), Look.flat(CREAM, 0.7), c + Vector3(0, size.y * 0.5 + 0.02, 0))
	top.rotation.y = yaw
	root.add_child(top)
	return mi


## A chocolate bar: a slab with raised squares on its face (+Z face local, turned by yaw).
func choco_bar(c: Vector3, size: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	var dark: StandardMaterial3D = Look.flat(Color(0.3, 0.16, 0.09), 0.35)
	var lite: StandardMaterial3D = Look.flat(Color(0.38, 0.21, 0.12), 0.3)
	n.add_child(Look.box(size, dark))
	var nx: int = maxi(int(size.x / 1.6), 1)
	var ny: int = maxi(int(size.y / 1.6), 1)
	for i: int in nx:
		for j: int in ny:
			var p := Vector3(-size.x * 0.5 + (float(i) + 0.5) * size.x / float(nx), -size.y * 0.5 + (float(j) + 0.5) * size.y / float(ny), 0)
			for s: float in [-1.0, 1.0]:
				n.add_child(Look.box(Vector3(size.x / float(nx) - 0.2, size.y / float(ny) - 0.2, 0.12), lite, p + Vector3(0, 0, s * (size.z * 0.5 + 0.05))))
	n.rotation.y = yaw
	return _add(n, c)


## The great gumball machine: a glass globe full of gumballs on a red stand with a brass coin
## plate. `pos` is the foot of the stand; returns the node (the globe's centre is at y = 5.2k + r).
func gumball_machine(pos: Vector3, k: float, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	var red: StandardMaterial3D = gloss(Color(0.95, 0.12, 0.2))
	var brass: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.35), 0.25, 0.9)
	n.add_child(Look.cylinder(3.0 * k, 5.2 * k, red, Vector3(0, 2.6 * k, 0), 3.8 * k, 24))
	n.add_child(Look.cylinder(3.3 * k, 0.5 * k, brass, Vector3(0, 5.3 * k, 0), -1.0, 24))
	n.add_child(Look.cylinder(1.2 * k, 0.3 * k, brass, Vector3(0, 3.2 * k, -3.2 * k), -1.0, 20))
	var r: float = 4.6 * k
	var cy: float = 5.2 * k + r
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.85, 0.95, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.03
	glass.metallic_specular = 1.0
	glass.rim_enabled = true
	glass.rim = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_BACK
	var globe := Look.sphere(r, glass, Vector3(0, cy, 0))
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(globe)
	n.add_child(Look.cylinder(1.4 * k, 0.8 * k, red, Vector3(0, cy + r * 0.98, 0), 1.6 * k, 20))
	# the gumballs inside (one multimesh with per-ball colours)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.55 * k
	sm.height = 1.1 * k
	sm.radial_segments = 12
	sm.rings = 6
	mm.mesh = sm
	var pts: Array[Vector3] = []
	var tries: int = 0
	while pts.size() < 150 and tries < 3000:
		tries += 1
		var p := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 0.45), rng.randf_range(-1, 1)) * (r - 0.6 * k)
		if p.length() > r - 0.6 * k:
			continue
		var ok: bool = true
		for q: Vector3 in pts:
			if q.distance_squared_to(p) < pow(1.0 * k, 2.0):
				ok = false
				break
		if ok:
			pts.append(p)
	mm.instance_count = pts.size()
	for i: int in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i] + Vector3(0, cy, 0)))
		mm.set_instance_color(i, [CHERRY, SKY, LEMON, MINT, GRAPE, ORANGE, PINK][i % 7])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.15
	bm.metallic_specular = 0.8
	mmi.material_override = bm
	n.add_child(mmi)
	n.rotation.y = yaw
	return _add(n, pos)
