class_name ArmadaDecor
extends RefCounted
## Storm Armada set dressing: airship hulls (lofted, clinker-built, copper-bottomed, gun ports
## glowing), gas envelopes with gores and rope nets, masts, yards and bellying sails, brass
## propellers, lanterns, pennants, crates and barrels, rigging lines, the far fleet, storm towers
## and the sea of storm clouds below. Decoration only unless a function says it collides; the level
## composes these around (never on) its route. Meshes and materials are shared.

const HULL_SHADER: Shader = preload("res://visual/armada_hull.gdshader")
const BALLOON_SHADER: Shader = preload("res://visual/armada_balloon.gdshader")
const CLOUD_SHADER: Shader = preload("res://visual/armada_clouds.gdshader")
const WOOD_SHADER: Shader = preload("res://visual/armada_wood.gdshader")
const SPIN: Script = preload("res://visual/spin.gd")
const DRIFT: Script = preload("res://visual/armada_drift.gd")

const OAK := Color(0.3, 0.19, 0.11)
const DECK := Color(0.62, 0.45, 0.3)
const BRASS := Color(0.88, 0.64, 0.3)
const CANVAS := Color(0.86, 0.8, 0.66)
const ROPE := Color(0.55, 0.44, 0.3)
const IRON := Color(0.18, 0.18, 0.2)
const LAMP := Color(1.0, 0.7, 0.32)

## Hull paints and envelope colour pairs (one per ship "house").
const PAINTS: Array[Color] = [Color(0.1, 0.2, 0.3), Color(0.35, 0.08, 0.07), Color(0.12, 0.26, 0.18), Color(0.2, 0.14, 0.26)]
const ENVELOPES: Array[Array] = [
	[Color(0.62, 0.2, 0.16), Color(0.86, 0.78, 0.6)],
	[Color(0.16, 0.3, 0.46), Color(0.82, 0.76, 0.6)],
	[Color(0.2, 0.2, 0.22), Color(0.72, 0.18, 0.14)],
	[Color(0.5, 0.36, 0.18), Color(0.85, 0.8, 0.66)],
]

var root: Node3D
var rng: RandomNumberGenerator
var _mats: Dictionary = {}
var _meshes: Dictionary = {}
## Every envelope material (the storm flashes them when lightning strikes).
var balloon_mats: Array[ShaderMaterial] = []


func _init(level_root: Node3D, random: RandomNumberGenerator) -> void:
	root = level_root
	rng = random


func _put(n: Node3D, pos: Vector3, parent: Node3D = null) -> Node3D:
	n.position = pos
	(parent if parent != null else root).add_child(n)
	return n


## A static body with one box collider (props that should not be walked through).
func _solid(size: Vector3, offset: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	body.add_child(cs)
	return body


# ---- materials ------------------------------------------------------------------------------

func hull_mat(paint: Color, depth: float, lit: float = 0.35) -> ShaderMaterial:
	var key: String = "hull|%s|%.2f|%.2f" % [paint.to_html(), depth, lit]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = HULL_SHADER
	m.set_shader_parameter("paint", paint)
	m.set_shader_parameter("depth", depth)
	m.set_shader_parameter("lit_ports", lit)
	_mats[key] = m
	return m


func balloon_mat(a: Color, b: Color, gores: float = 12.0) -> ShaderMaterial:
	var key: String = "bal|%s|%s|%.1f" % [a.to_html(), b.to_html(), gores]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = BALLOON_SHADER
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("gores", gores)
	_mats[key] = m
	balloon_mats.append(m)
	return m


## Plank decking for walkable shapes that are not kit boxes (the bows).
func deck_mat(half: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WOOD_SHADER
	m.set_shader_parameter("top_color", Look.c("top"))
	m.set_shader_parameter("side_color", Look.c("side"))
	m.set_shader_parameter("trim_color", Look.c("trim"))
	m.set_shader_parameter("half_size", half)
	return m


func canvas_mat(col: Color = CANVAS) -> StandardMaterial3D:
	var key: String = "canvas|%s" % col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := Look.flat(col, 0.85).duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


# ---- hulls ------------------------------------------------------------------------------------

## Half-width fraction of the hull at t (0 stern .. 1 bow): a square transom, full amidships, a
## rounded bow tapering to the stem from t = BOW.
const BOW: float = 0.62


static func hull_width(t: float) -> float:
	if t <= BOW:
		return 1.0
	var k: float = (t - BOW) / (1.0 - BOW)
	return sqrt(maxf(1.0 - k * k, 0.0))


## Lofted hull mesh: stern at local +Z, bow at -Z, the deck line at y = 0; UV = (metres from the
## stern, metres below the deck line) for the hull shader.
func hull_mesh(length: float, beam: float, depth: float) -> ArrayMesh:
	var key: Array = ["hull", length, beam, depth]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_st: int = 28
	var n_k: int = 12
	var rows: Array = []
	for i: int in n_st + 1:
		var t: float = float(i) / float(n_st)
		var w: float = beam * 0.5 * hull_width(t)
		var d: float = depth * (1.0 - 0.45 * pow(maxf(t - BOW, 0.0) / (1.0 - BOW), 2.0))
		var z: float = length * (0.5 - t)
		var row: Array = []
		for k: int in n_k + 1:
			var th: float = PI * float(k) / float(n_k)
			var s: float = sin(th)
			var y: float = -d * pow(s, 0.65)
			var p := Vector3(w * cos(th), y, z)
			var nrm := Vector3(cos(th) / maxf(w, 0.3), -s / maxf(d, 0.3), 0.0)
			if nrm.length() < 0.0001:
				nrm = Vector3.DOWN
			row.append([p, nrm.normalized(), Vector2(length * t, -y)])
		rows.append(row)
	for i: int in n_st:
		for k: int in n_k:
			var a: Array = rows[i][k]
			var b: Array = rows[i][k + 1]
			var c: Array = rows[i + 1][k + 1]
			var e: Array = rows[i + 1][k]
			for v: Array in [a, b, c, a, c, e]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	# the transom: a flat stern face
	var stern: Array = rows[0]
	var mid := Vector3(0, -depth * 0.5, length * 0.5)
	for k: int in n_k:
		for v: Array in [[mid, Vector2(0.0, depth * 0.5)], [stern[k][0], stern[k][2]], [stern[k + 1][0], stern[k + 1][2]]]:
			st.set_normal(Vector3.BACK)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mesh: ArrayMesh = st.commit()
	_meshes[key] = mesh
	return mesh


## A ship's hull under a deck: `top` is the deck line's centre (the middle of the full hull,
## stern to stem), `yaw_deg` turns the bow (local -Z). The walkable deck itself is the level's
## (a kit.plat over the square part: t 0..BOW); with `bow_walk` the rounded bow gets a walkable
## plank cap of its own. Adds a stern castle (decor), a bowsprit, a figurehead and rails.
func hull(top: Vector3, yaw_deg: float, length: float, beam: float, depth: float, paint: Color, opts: Dictionary = {}) -> Node3D:
	var n := Node3D.new()
	n.rotation.y = deg_to_rad(yaw_deg)
	_put(n, top)
	var mi := Look.mesh_node(hull_mesh(length, beam, depth), hull_mat(paint, depth, float(opts.get("lit", 0.35))))
	mi.position = Vector3(0, -0.02, 0)
	n.add_child(mi)
	var gilt: StandardMaterial3D = Look.flat(BRASS, 0.3, 0.85)
	var oak: StandardMaterial3D = Look.flat(OAK, 0.8)
	var bow_z: float = length * (0.5 - BOW)
	if bool(opts.get("bow_walk", true)):
		_bow_cap(n, length, beam, bow_z)
	# the bowsprit and a gilded figurehead under it
	var sprit := Look.cylinder(0.22, length * 0.3, oak, Vector3(0, 0.6, -length * 0.5 - length * 0.1), 0.1, 8)
	sprit.rotation.x = deg_to_rad(-72.0)
	n.add_child(sprit)
	var fig := Look.sphere(0.5, gilt, Vector3(0, -0.8, -length * 0.5 + 0.2))
	fig.scale = Vector3(0.6, 1.2, 1.0)
	n.add_child(fig)
	# gilded rail along the sheer, just outside the deck edges
	if bool(opts.get("rails", true)):
		for sx: float in [-1.0, 1.0]:
			n.add_child(Look.box(Vector3(0.18, 0.18, length * BOW), gilt, Vector3(sx * (beam * 0.5 + 0.09), 0.02, length * (0.5 - BOW * 0.5))))
	# the stern castle: a raised poop with lit windows (decor, behind the deck's stern end)
	if bool(opts.get("castle", true)):
		var ch: float = float(opts.get("castle_h", 2.8))
		var castle := Look.box(Vector3(beam + 0.4, ch, 2.4), Look.flat(paint.lerp(OAK, 0.4), 0.7), Vector3(0, ch * 0.5 - 0.02, length * 0.5 + 1.2))
		n.add_child(castle)
		var win: StandardMaterial3D = Look.flat(LAMP, 0.4, 0.0, 2.4)
		for i: int in 4:
			var wx: float = (float(i) - 1.5) * beam * 0.22
			n.add_child(Look.box(Vector3(beam * 0.12, 0.9, 0.06), win, Vector3(wx, ch * 0.45, length * 0.5 + 2.43)))
		n.add_child(Look.box(Vector3(beam + 0.7, 0.3, 2.8), gilt, Vector3(0, ch, length * 0.5 + 1.2)))
		# stern lantern
		n.add_child(Look.sphere(0.35, Look.flat(LAMP, 0.4, 0.0, 3.0), Vector3(0, ch + 0.8, length * 0.5 + 2.2)))
	return n


func _bow_cap(n: Node3D, length: float, beam: float, bow_z: float) -> void:
	# a fan of triangles over the rounded bow, at the deck line, walkable
	var pts: Array[Vector3] = []
	var steps: int = 10
	for i: int in steps + 1:
		var t: float = BOW + (1.0 - BOW) * float(i) / float(steps)
		pts.append(Vector3(beam * 0.5 * hull_width(t), 0, length * (0.5 - t)))
	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in steps:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var quad: Array[Vector3] = [Vector3(-a.x, 0, a.z), Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z), Vector3(-a.x, 0, a.z), Vector3(b.x, 0, b.z), Vector3(-b.x, 0, b.z)]
		for v: Vector3 in quad:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
			faces.append(v)
	var cap := MeshInstance3D.new()
	cap.mesh = st.commit()
	var m: ShaderMaterial = deck_mat(Vector3(beam * 0.5 + 3.0, 0.25, length))
	m.set_shader_parameter("trim_width", 0.0)
	cap.material_override = m
	cap.position = Vector3(0, -0.005, 0)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	# both windings, so the player is held from above whichever way the triangles face
	var both := PackedVector3Array(faces)
	for i: int in range(0, faces.size(), 3):
		both.append(faces[i])
		both.append(faces[i + 2])
		both.append(faces[i + 1])
	shape.set_faces(both)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(cap)
	body.position = Vector3(0, 0, 0)
	n.add_child(body)
	# a gilded capping rail round the bow
	var gilt: StandardMaterial3D = Look.flat(BRASS, 0.3, 0.85)
	for i: int in steps:
		for sx: float in [-1.0, 1.0]:
			var a2 := Vector3(sx * (pts[i].x + 0.09), 0.02, pts[i].z)
			var b2 := Vector3(sx * (pts[i + 1].x + 0.09), 0.02, pts[i + 1].z)
			n.add_child(line(a2, b2, 0.09, gilt))


# ---- envelopes, rigging, masts, props ------------------------------------------------------

## A gas envelope: an ellipsoid `length` long (local -Z = nose), `radius` round, with brass
## bands, tail fins, a brass nose cap. Returns the holder.
func envelope(center: Vector3, yaw_deg: float, length: float, radius: float, colors: Array, fins: bool = true) -> Node3D:
	var n := Node3D.new()
	n.rotation.y = deg_to_rad(yaw_deg)
	_put(n, center)
	var key: Array = ["env"]
	if not _meshes.has(key):
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 36
		sm.rings = 18
		_meshes[key] = sm
	var bag := Look.mesh_node(_meshes[key], balloon_mat(colors[0], colors[1]))
	bag.rotation.x = PI * 0.5
	bag.scale = Vector3(radius, length * 0.5, radius)
	bag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	n.add_child(bag)
	var gilt: StandardMaterial3D = Look.flat(BRASS, 0.3, 0.85)
	for f: float in [-0.55, 0.0, 0.55]:
		var rr: float = radius * sqrt(maxf(1.0 - f * f, 0.05)) * 1.015
		var tm := TorusMesh.new()
		tm.inner_radius = rr - 0.12
		tm.outer_radius = rr + 0.06
		tm.rings = 40
		tm.ring_segments = 6
		var band := Look.mesh_node(tm, gilt, Vector3(0, 0, f * length * 0.5))
		band.rotation.x = PI * 0.5
		n.add_child(band)
	var cap := Look.sphere(radius * 0.18, gilt, Vector3(0, 0, -length * 0.5 + radius * 0.05))
	n.add_child(cap)
	if fins:
		var fin_mat: StandardMaterial3D = canvas_mat(colors[1])
		for i: int in 4:
			var a: float = TAU * float(i) / 4.0 + PI * 0.25
			var fin := Look.box(Vector3(0.12, radius * 0.9, length * 0.16), fin_mat, Vector3(cos(a), sin(a), 0) * radius * 0.55 + Vector3(0, 0, length * 0.42))
			fin.rotation.z = a - PI * 0.5
			n.add_child(fin)
	return n


## A straight rope / chain / spar between two points.
func line(a: Vector3, b: Vector3, r: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var d: Vector3 = b - a
	var ln: float = maxf(d.length(), 0.01)
	var mi := Look.cylinder(r, ln, mat, Vector3.ZERO, -1.0, 6)
	var up: Vector3 = d / ln
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9))
	if side.length() < 0.001:
		side = up.cross(Vector3(0.9, 0.1, 0.2))
	side = side.normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	if parent != null:
		parent.add_child(mi)
	return mi


## A rope in the world (parented to the level).
func rope(a: Vector3, b: Vector3, r: float = 0.05) -> void:
	root.add_child(line(a, b, r, Look.flat(ROPE, 0.9)))


## A mast standing on a deck (collides): `base` on the deck, with two yards and bellying sails high
## above head height (sails from 5 m up), a fighting top and a pennant.
func mast(base: Vector3, height: float, yaw_deg: float, yard: float, sail: Color = CANVAS, collide: bool = true) -> Node3D:
	var n := Node3D.new()
	n.rotation.y = deg_to_rad(yaw_deg)
	_put(n, base)
	var oak: StandardMaterial3D = Look.flat(OAK.lightened(0.1), 0.8)
	var gilt: StandardMaterial3D = Look.flat(BRASS, 0.3, 0.85)
	n.add_child(Look.cylinder(0.32, height, oak, Vector3(0, height * 0.5, 0), 0.2, 12))
	for h: float in [0.3, 0.55, 0.8]:
		n.add_child(Look.cylinder(0.34 - h * 0.12, 0.2, gilt, Vector3(0, height * h, 0), -1.0, 12))
	var yards: Array[float] = [0.5, 0.8]
	for i: int in yards.size():
		var y: float = height * yards[i]
		var w: float = yard * (1.0 - 0.3 * float(i))
		n.add_child(Look.box(Vector3(w, 0.2, 0.2), oak, Vector3(0, y, 0)))
		var sh: float = height * 0.24
		n.add_child(sail_sheet(Vector3(0, y - sh * 0.5 - 0.1, -0.35), w * 0.92, sh, 0.9, canvas_mat(sail)))
	# the fighting top
	n.add_child(Look.cylinder(0.9, 0.18, oak, Vector3(0, height * 0.66, 0), -1.0, 14))
	# the pennant streaming downwind
	var pen := PrismMesh.new()
	pen.size = Vector3(0.7, 3.2, 0.03)
	var pm := Look.mesh_node(pen, canvas_mat(Look.c("accent")), Vector3(0, height + 0.1, 1.5))
	pm.basis = Basis(Vector3(0, 0, 1), PI * 0.5) * Basis(Vector3(1, 0, 0), PI * 0.5)
	n.add_child(pm)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.32
		cyl.height = height * 0.45
		var cs := CollisionShape3D.new()
		cs.shape = cyl
		cs.position = Vector3(0, height * 0.225, 0)
		body.add_child(cs)
		n.add_child(body)
	return n


## A bellying sail: a sheet `w` wide and `h` tall, curved `belly` metres forward (local -Z).
func sail_sheet(center: Vector3, w: float, h: float, belly: float, mat: Material) -> MeshInstance3D:
	var key: Array = ["sail", w, h, belly]
	if not _meshes.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var nx: int = 8
		var ny: int = 6
		var grid: Array = []
		for j: int in ny + 1:
			var row: Array = []
			for i: int in nx + 1:
				var u: float = float(i) / float(nx)
				var v: float = float(j) / float(ny)
				var bz: float = -belly * sin(u * PI) * sin(v * PI * 0.8 + 0.3)
				row.append(Vector3((u - 0.5) * w, (v - 0.5) * h, bz))
			grid.append(row)
		for j: int in ny:
			for i: int in nx:
				var a: Vector3 = grid[j][i]
				var b: Vector3 = grid[j][i + 1]
				var c: Vector3 = grid[j + 1][i + 1]
				var e: Vector3 = grid[j + 1][i]
				var nrm: Vector3 = (b - a).cross(e - a).normalized()
				for v3: Vector3 in [a, b, c, a, c, e]:
					st.set_normal(nrm)
					st.add_vertex(v3)
		_meshes[key] = st.commit()
	var mi := Look.mesh_node(_meshes[key], mat, center)
	return mi


## A brass propeller spinning about its local Z (turn it with `basis_rot`), `radius` long blades.
func propeller(pos: Vector3, radius: float, rot_deg: Vector3, period: float, blades: int = 3) -> Node3D:
	var holder := Node3D.new()
	holder.rotation_degrees = rot_deg
	_put(holder, pos)
	var gilt: StandardMaterial3D = Look.flat(BRASS, 0.28, 0.9)
	var rotor := Node3D.new()
	rotor.set_script(SPIN)
	rotor.set("period", period)
	rotor.set("axis", Vector3(0, 0, 1))
	holder.add_child(rotor)
	rotor.add_child(Look.sphere(radius * 0.16, gilt))
	for i: int in blades:
		var arm := Node3D.new()
		arm.rotation.z = TAU * float(i) / float(blades)
		var blade := Look.box(Vector3(radius * 0.22, radius, 0.05), gilt, Vector3(0, radius * 0.55, 0))
		blade.rotation.y = 0.35
		arm.add_child(blade)
		rotor.add_child(arm)
	var shaft := Look.cylinder(radius * 0.1, radius * 0.6, Look.flat(IRON, 0.4, 0.8), Vector3(0, 0, radius * 0.3), -1.0, 8)
	shaft.rotation.x = PI * 0.5
	holder.add_child(shaft)
	return holder


## A ship's lantern: a brass cage round a warm glow; `light` adds a small omni light.
func lantern(pos: Vector3, light: bool = false, scale: float = 1.0) -> Node3D:
	var n := Node3D.new()
	_put(n, pos)
	var gilt: StandardMaterial3D = Look.flat(BRASS, 0.3, 0.85)
	n.add_child(Look.sphere(0.16 * scale, Look.flat(LAMP, 0.4, 0.0, 3.2)))
	n.add_child(Look.cylinder(0.2 * scale, 0.06, gilt, Vector3(0, 0.22 * scale, 0), 0.08 * scale, 8))
	n.add_child(Look.cylinder(0.2 * scale, 0.06, gilt, Vector3(0, -0.2 * scale, 0), -1.0, 8))
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0
		n.add_child(Look.box(Vector3(0.03, 0.42 * scale, 0.03), gilt, Vector3(cos(a), 0, sin(a)) * 0.19 * scale))
	if light:
		var o := OmniLight3D.new()
		o.light_color = LAMP
		o.light_energy = 1.4
		o.omni_range = 7.0
		o.shadow_enabled = false
		n.add_child(o)
	return n


## A lamp post on a deck (collides like a thin post): a lantern hung from a crook.
func lamp_post(base: Vector3, height: float = 2.6, light: bool = true) -> void:
	var n: Node3D = _solid(Vector3(0.14, height, 0.14), Vector3(0, height * 0.5, 0))
	_put(n, base)
	var iron: StandardMaterial3D = Look.flat(IRON, 0.45, 0.8)
	n.add_child(Look.cylinder(0.06, height, iron, Vector3(0, height * 0.5, 0), 0.05, 8))
	n.add_child(Look.box(Vector3(0.5, 0.05, 0.05), iron, Vector3(0.25, height, 0)))
	var l: Node3D = lantern(base + Vector3(0.48, height - 0.35, 0), light, 0.9)
	l.reparent(n)


## A crate (decor, no collision): banded planks.
func crate(center: Vector3, s: float, yaw: float = 0.0) -> void:
	var n: Node3D = _solid(Vector3(s, s, s), Vector3.ZERO)
	n.rotation.y = yaw
	_put(n, center)
	n.add_child(Look.box(Vector3(s, s, s), Look.flat(Color(0.55, 0.4, 0.24), 0.85)))
	var band: StandardMaterial3D = Look.flat(IRON, 0.5, 0.7)
	for y: float in [-0.35, 0.35]:
		n.add_child(Look.box(Vector3(s + 0.03, 0.08, s + 0.03), band, Vector3(0, y * s, 0)))


func barrel(base: Vector3, r: float = 0.4) -> void:
	var n: Node3D = _solid(Vector3(r * 1.8, r * 2.4, r * 1.8), Vector3(0, r * 1.2, 0))
	_put(n, base)
	n.add_child(Look.cylinder(r, r * 2.4, Look.flat(Color(0.45, 0.3, 0.17), 0.8), Vector3(0, r * 1.2, 0), r * 0.9, 12))
	for y: float in [0.3, 2.1]:
		n.add_child(Look.cylinder(r * 1.02, 0.07, Look.flat(IRON, 0.5, 0.7), Vector3(0, r * y, 0), -1.0, 12))


## A pennant on a pole (decor).
func flag(base: Vector3, height: float, col: Color, yaw_deg: float = 0.0) -> void:
	var n: Node3D = _solid(Vector3(0.12, height, 0.12), Vector3(0, height * 0.5, 0))
	n.rotation.y = deg_to_rad(yaw_deg)
	_put(n, base)
	n.add_child(Look.cylinder(0.05, height, Look.flat(IRON, 0.45, 0.8), Vector3(0, height * 0.5, 0), -1.0, 6))
	var pen := PrismMesh.new()
	pen.size = Vector3(0.9, 2.2, 0.03)
	var pm := Look.mesh_node(pen, canvas_mat(col), Vector3(1.1, height - 0.45, 0))
	pm.rotation.z = -PI * 0.5
	n.add_child(pm)


# ---- whole ships, far away ------------------------------------------------------------------------

## A complete airship far off the route (no collision): hull, envelope overhead on struts,
## propellers, masts and sails; it drifts slowly along its heading and bobs.
func far_ship(pos: Vector3, yaw_deg: float, s: float, house: int, drift: float = 1.5) -> Node3D:
	var n := Node3D.new()
	n.set_script(DRIFT)
	n.set("speed", drift)
	n.set("bob", 0.6 * s)
	n.rotation.y = deg_to_rad(yaw_deg)
	_put(n, pos)
	var length: float = 34.0 * s
	var beam: float = 9.0 * s
	var depth: float = 5.5 * s
	var hm := Look.mesh_node(hull_mesh(length, beam, depth), hull_mat(PAINTS[house % PAINTS.size()], depth, 0.6))
	n.add_child(hm)
	n.add_child(Look.box(Vector3(beam, 0.3, length * BOW), Look.flat(DECK.darkened(0.2), 0.8), Vector3(0, -0.15, length * (0.5 - BOW * 0.5))))
	var env_y: float = 14.0 * s
	_env_child(n, Vector3(0, env_y, 0), length * 1.05, 6.5 * s, ENVELOPES[house % ENVELOPES.size()])
	var ropem: StandardMaterial3D = Look.flat(ROPE.darkened(0.2), 0.9)
	for sx: float in [-1.0, 1.0]:
		for z: float in [-0.25, 0.1, 0.35]:
			line(Vector3(sx * beam * 0.45, 0.1, z * length), Vector3(sx * 3.5 * s, env_y - 5.6 * s, z * length * 0.9), 0.08 * s, ropem, n)
	for sx: float in [-1.0, 1.0]:
		var prop: Node3D = Node3D.new()
		n.add_child(prop)
		prop.position = Vector3(sx * (beam * 0.5 + 1.2 * s), -1.0 * s, length * 0.42)
		var rotor := Node3D.new()
		rotor.set_script(SPIN)
		rotor.set("period", 0.3)
		rotor.set("axis", Vector3(0, 0, 1))
		prop.add_child(rotor)
		for i: int in 3:
			var arm := Node3D.new()
			arm.rotation.z = TAU * float(i) / 3.0
			arm.add_child(Look.box(Vector3(0.6 * s, 2.4 * s, 0.1), Look.flat(BRASS, 0.3, 0.85), Vector3(0, 1.3 * s, 0)))
			rotor.add_child(arm)
	var oak: StandardMaterial3D = Look.flat(OAK.lightened(0.1), 0.8)
	for z: float in [-0.2, 0.18]:
		n.add_child(Look.cylinder(0.3 * s, 9.0 * s, oak, Vector3(0, 4.5 * s, z * length), 0.2 * s, 8))
		n.add_child(sail_sheet(Vector3(0, 5.2 * s, z * length - 0.4 * s), 6.0 * s, 4.0 * s, 0.8 * s, canvas_mat(CANVAS.darkened(0.15))))
	# lamplit stern windows
	n.add_child(Look.box(Vector3(beam * 0.7, 1.0 * s, 0.1), Look.flat(LAMP, 0.4, 0.0, 2.2), Vector3(0, -1.4 * s, length * 0.5 + 0.05)))
	return n


func _env_child(parent: Node3D, pos: Vector3, length: float, radius: float, colors: Array) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var key: Array = ["env"]
	if not _meshes.has(key):
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 36
		sm.rings = 18
		_meshes[key] = sm
	var bag := Look.mesh_node(_meshes[key], balloon_mat(colors[0], colors[1]))
	bag.rotation.x = PI * 0.5
	bag.scale = Vector3(radius, length * 0.5, radius)
	n.add_child(bag)
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + PI * 0.25
		var fin := Look.box(Vector3(0.2, radius * 0.9, length * 0.16), canvas_mat(colors[1]), Vector3(cos(a), sin(a), 0) * radius * 0.55 + Vector3(0, 0, length * 0.42))
		fin.rotation.z = a - PI * 0.5
		n.add_child(fin)
	return n


# ---- the storm -------------------------------------------------------------------------------------

## The sea of storm clouds below the fleet: a huge sheet (returns its material, for flashes).
func cloud_sea(center: Vector3, size: float, sun_dir: Vector2) -> ShaderMaterial:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = CLOUD_SHADER
	m.set_shader_parameter("sun_dir", sun_dir)
	var mi := Look.mesh_node(pm, m, center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size
	root.add_child(mi)
	return m


## A towering thunderhead: a stack of soft cloud masses rising out of the cloud sea.
func storm_tower(base: Vector3, radius: float, height: float) -> void:
	var n := Node3D.new()
	_put(n, base)
	var mat: ShaderMaterial = Look.cloud_material()
	var layers: int = int(height / (radius * 0.7)) + 2
	for i: int in layers:
		var f: float = float(i) / float(maxi(layers - 1, 1))
		var r: float = radius * (1.0 - 0.35 * f) * rng.randf_range(0.85, 1.1)
		# the anvil spreads at the top
		if f > 0.85:
			r = radius * 1.6
		for k: int in 3:
			var off := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)) * radius
			var s := Look.sphere(1.0, mat, off + Vector3(0, f * height, 0))
			s.scale = Vector3(r, r * (0.45 if f > 0.85 else 0.75), r) * rng.randf_range(0.8, 1.1)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(s)
