class_name CarnivalDecor
extends RefCounted
## Carnival Chaos set dressing: striped tents and the big top, swags of string lights, bunting, balloon
## bunches, kiosks, striped poles, direction signs, a far-off turning Ferris wheel and roller-coaster
## skeleton, searchlights and the fairground floor far below. Everything is built from shared meshes and
## materials (Look caches them) and bulk items go through MultiMesh. Purely visual: no colliders.

const RED := Color(0.93, 0.2, 0.26)
const CREAM := Color(0.99, 0.94, 0.82)
const GOLD := Color(1.0, 0.8, 0.25)
const TEAL := Color(0.2, 0.75, 0.8)
const PINK := Color(1.0, 0.42, 0.62)
const PURPLE := Color(0.55, 0.3, 0.8)

var parent: Node3D
var rng: RandomNumberGenerator
var _bulb_mat: StandardMaterial3D
var _flag_mat: StandardMaterial3D


func _init(p: Node3D, r: RandomNumberGenerator) -> void:
	parent = p
	rng = r
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bulb_mat.vertex_color_use_as_albedo = true
	_bulb_mat.albedo_color = Color(1, 1, 1)
	_flag_mat = StandardMaterial3D.new()
	_flag_mat.vertex_color_use_as_albedo = true
	_flag_mat.roughness = 0.8
	_flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


static func stripe_mat(a: Color, b: Color, stripes: float = 12.0, glow: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/carnival_stripe.gdshader")
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("stripes", stripes)
	m.set_shader_parameter("glow", glow)
	return m


## A MultiMeshInstance3D of `xfs` with per-instance colours (HDR ok when the material is unshaded).
func _multi(mesh: Mesh, mat: Material, xfs: Array[Transform3D], cols: PackedColorArray) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i % cols.size()])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ---- tents ----------------------------------------------------------------------------------------

## A striped tent: a drum wall under a cone roof, a pennant and a glowing door. `pos` is the ground centre.
func tent(pos: Vector3, radius: float, wall_h: float, roof_h: float, yaw: float, a: Color = RED, b: Color = CREAM) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	var mat: ShaderMaterial = stripe_mat(a, b, 14.0)
	n.add_child(Look.cylinder(radius, wall_h, mat, Vector3(0, wall_h * 0.5, 0), -1.0, 24))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.12
	roof.bottom_radius = radius * 1.12
	roof.height = roof_h
	roof.radial_segments = 24
	n.add_child(Look.mesh_node(roof, mat, Vector3(0, wall_h + roof_h * 0.5, 0)))
	# scalloped valance round the eaves
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.4, 0.5, 0.15)
	n.add_child(Look.cylinder(radius * 1.12, 0.25, gold, Vector3(0, wall_h + 0.05, 0), -1.0, 24))
	n.add_child(Look.cylinder(0.05, 2.6, gold, Vector3(0, wall_h + roof_h + 1.1, 0), -1.0, 6))
	var flag := Look.box(Vector3(1.4, 0.8, 0.04), Look.flat(a, 0.6), Vector3(0.7, wall_h + roof_h + 2.0, 0))
	n.add_child(flag)
	# a warm doorway
	var door := Look.box(Vector3(radius * 0.5, wall_h * 0.7, 0.2), Look.flat(Color(1.0, 0.7, 0.3), 0.4, 0.0, 1.6), Vector3(0, wall_h * 0.35, -radius * 0.97))
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(door)
	return n


## The big top: a huge striped tent with a high centre peak and four lower side peaks, pennants, a lit
## entrance arch. `pos` is the ground centre; `s` scales it (1 = 18 m radius).
func big_top(pos: Vector3, s: float, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	var mat: ShaderMaterial = stripe_mat(RED, CREAM, 16.0)
	var mat2: ShaderMaterial = stripe_mat(Color(0.2, 0.35, 0.8), CREAM, 16.0)
	var wall_h: float = 7.0
	n.add_child(Look.cylinder(18.0, wall_h, mat, Vector3(0, wall_h * 0.5, 0), -1.0, 32))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.3
	roof.bottom_radius = 19.5
	roof.height = 15.0
	roof.radial_segments = 32
	n.add_child(Look.mesh_node(roof, mat, Vector3(0, wall_h + 7.5, 0)))
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.35, 0.6, 0.25)
	n.add_child(Look.cylinder(19.6, 0.7, gold, Vector3(0, wall_h + 0.05, 0), -1.0, 32))
	n.add_child(Look.cylinder(0.18, 7.0, gold, Vector3(0, wall_h + 15.0 + 3.2, 0), -1.0, 8))
	var flag := Look.box(Vector3(4.0, 2.2, 0.1), Look.flat(RED, 0.6), Vector3(2.0, wall_h + 15.0 + 5.2, 0))
	n.add_child(flag)
	# four lower side peaks
	for k: int in 4:
		var a: float = TAU * (float(k) + 0.5) / 4.0
		var p := Node3D.new()
		p.position = Vector3(cos(a) * 17.0, 0, sin(a) * 17.0)
		n.add_child(p)
		p.add_child(Look.cylinder(5.0, 6.0, mat2, Vector3(0, 3.0, 0), -1.0, 20))
		var rf := CylinderMesh.new()
		rf.top_radius = 0.15
		rf.bottom_radius = 5.6
		rf.height = 6.5
		rf.radial_segments = 20
		p.add_child(Look.mesh_node(rf, mat2, Vector3(0, 6.0 + 3.25, 0)))
		p.add_child(Look.cylinder(0.08, 2.4, gold, Vector3(0, 6.0 + 6.5 + 1.1, 0), -1.0, 6))
	return n


# ---- lights and flags -----------------------------------------------------------------------------------

## A swag of string lights from `a` to `b` (world), sagging `sag` m, bulbs `spacing` m apart.
func string_lights(a: Vector3, b: Vector3, sag: float = 1.2, spacing: float = 0.9, warm: bool = false) -> void:
	var dist: float = a.distance_to(b)
	var n: int = maxi(int(dist / spacing), 2)
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.22
	mesh.radial_segments = 8
	mesh.rings = 4
	var xfs: Array[Transform3D] = []
	var cols := PackedColorArray()
	var palette: PackedColorArray = PackedColorArray([Color(2.6, 1.9, 0.7), Color(2.6, 0.8, 1.1), Color(0.9, 2.0, 2.6), Color(1.0, 2.4, 1.0)]) if not warm else PackedColorArray([Color(2.6, 1.9, 0.7), Color(2.4, 1.3, 0.5)])
	for i: int in n + 1:
		var u: float = float(i) / float(n)
		var p: Vector3 = a.lerp(b, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0)
		xfs.append(Transform3D(Basis.IDENTITY, p))
		cols.append(palette[i % palette.size()])
	_multi(mesh, _bulb_mat, xfs, cols)
	# the wire
	var steps: int = 6
	for i2: int in steps:
		var u0: float = float(i2) / float(steps)
		var u1: float = float(i2 + 1) / float(steps)
		var p0: Vector3 = a.lerp(b, u0) - Vector3(0, sag * 4.0 * u0 * (1.0 - u0), 0)
		var p1: Vector3 = a.lerp(b, u1) - Vector3(0, sag * 4.0 * u1 * (1.0 - u1), 0)
		var l: float = p0.distance_to(p1)
		if l < 0.01:
			continue
		var w := Look.box(Vector3(0.03, 0.03, l), Look.flat(Color(0.15, 0.1, 0.12), 0.8), Vector3.ZERO)
		var d: Vector3 = (p1 - p0).normalized()
		w.transform = Transform3D(Basis.looking_at(d, Vector3.UP), (p0 + p1) * 0.5)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(w)


## Triangular bunting hanging from a swag between `a` and `b`.
func bunting(a: Vector3, b: Vector3, sag: float = 1.0, flags: int = 12) -> void:
	var tri := PrismMesh.new()
	tri.size = Vector3(0.55, 0.7, 0.03)
	var xfs: Array[Transform3D] = []
	var cols := PackedColorArray()
	var palette: PackedColorArray = PackedColorArray([RED, CREAM, GOLD, TEAL, PINK])
	var yaw: float = atan2(-(b - a).x, -(b - a).z)
	for i: int in flags:
		var u: float = (float(i) + 0.5) / float(flags)
		var p: Vector3 = a.lerp(b, u) - Vector3(0, sag * 4.0 * u * (1.0 - u) + 0.3, 0)
		xfs.append(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI), p))
		cols.append(palette[i % palette.size()])
	_multi(tri, _flag_mat, xfs, cols)


## A bunch of balloons on strings tied to `pos` (world), floating `height` m up.
func balloons(pos: Vector3, count: int = 5, height: float = 3.5) -> void:
	var cols: Array[Color] = [RED, GOLD, TEAL, PINK, PURPLE, Color(0.4, 0.9, 0.5)]
	for i: int in count:
		var off := Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.0, 1.0), rng.randf_range(-0.7, 0.7))
		var top: Vector3 = pos + Vector3(0, height, 0) + off
		var col: Color = cols[rng.randi() % cols.size()]
		var bal := Look.sphere(0.55, Look.flat(col, 0.25, 0.1, 0.12), top)
		bal.scale = Vector3(0.85, 1.1, 0.85)
		parent.add_child(bal)
		var l: float = top.y - pos.y - 0.55
		var s := Look.box(Vector3(0.02, l, 0.02), Look.flat(Color(0.9, 0.9, 0.95), 0.8), Vector3((pos.x + top.x) * 0.5, pos.y + l * 0.5, (pos.z + top.z) * 0.5))
		parent.add_child(s)


## A striped pole with a ball on top (a lamp post for the midway): `pos` is the foot.
func pole(pos: Vector3, h: float = 5.0, col: Color = RED, lamp: bool = true) -> void:
	var m: ShaderMaterial = stripe_mat(col, CREAM, 6.0)
	parent.add_child(Look.cylinder(0.14, h, m, pos + Vector3(0, h * 0.5, 0), -1.0, 10))
	if lamp:
		var bulb := Look.sphere(0.3, Look.flat(Color(1.0, 0.85, 0.5), 0.3, 0.0, 2.6), pos + Vector3(0, h + 0.2, 0))
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(bulb)


## A little kiosk: a counter, a striped awning and a lit sign board. `pos` is the ground centre.
func kiosk(pos: Vector3, yaw: float, col: Color = RED) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	n.add_child(Look.box(Vector3(3.2, 2.0, 2.0), Look.flat(Color(0.9, 0.82, 0.68), 0.7), Vector3(0, 1.0, 0)))
	n.add_child(Look.box(Vector3(3.4, 0.12, 2.6), Look.flat(col, 0.5), Vector3(0, 3.0, -0.2)))
	var aw := stripe_mat(col, CREAM, 8.0)
	var awning := Look.box(Vector3(3.5, 0.1, 1.2), aw, Vector3(0, 2.7, -1.5))
	awning.rotation.x = 0.25
	n.add_child(awning)
	n.add_child(Look.box(Vector3(2.6, 0.5, 0.1), Look.flat(Color(1.0, 0.85, 0.5), 0.4, 0.0, 1.6), Vector3(0, 3.5, -0.8)))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.1, 2.2, 0.1), Look.flat(CREAM, 0.6), Vector3(sx * 1.65, 1.1, -1.2)))


## An arrow board on a post pointing local left (-1) or right (+1) (for branches), or ahead (0). `pos` is the foot.
func arrow_sign(pos: Vector3, yaw: float, dir: float, col: Color) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	n.add_child(Look.box(Vector3(0.14, 2.6, 0.14), Look.flat(CREAM, 0.6), Vector3(0, 1.3, 0)))
	var board := Look.box(Vector3(1.5, 0.8, 0.12), Look.flat(col, 0.45, 0.0, 0.4), Vector3(0, 2.7, 0))
	n.add_child(board)
	var head := PrismMesh.new()
	head.size = Vector3(0.9, 0.9, 0.14)
	var tip := Look.mesh_node(head, Look.flat(col, 0.45, 0.0, 0.4), Vector3(dir * 1.1, 2.7, 0))
	tip.rotation.z = -PI * 0.5 * dir if dir != 0.0 else 0.0
	n.add_child(tip)
	var lamp := Look.sphere(0.2, Look.flat(Color(1.0, 0.85, 0.4), 0.3, 0.0, 2.6), Vector3(0, 3.35, 0))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(lamp)


# ---- far scenery ---------------------------------------------------------------------------------------

## A turning Ferris wheel far off, lit (scenery only). `pos` is its hub; `radius` the rim.
func far_wheel(pos: Vector3, radius: float, yaw: float) -> Node3D:
	var w := FarWheel.new()
	w.position = pos
	w.rotation.y = yaw
	w.radius = radius
	parent.add_child(w)
	return w


## A roller-coaster skeleton: a lattice of posts under a hilly rail, lit with bulbs. `pos` is the start on
## the ground-level line, running along local -Z for `length` m with hills `hill` m tall.
func far_coaster(pos: Vector3, yaw: float, length: float, hill: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var red: StandardMaterial3D = Look.flat(RED, 0.5, 0.2)
	var post_xfs: Array[Transform3D] = []
	var cols := PackedColorArray([Color.WHITE])
	var step: float = 6.0
	var n: int = int(length / step)
	var prev: Vector3 = Vector3.ZERO
	for i: int in n + 1:
		var z: float = -float(i) * step
		var u: float = float(i) / float(maxi(n, 1))
		var y: float = hill * (0.55 + 0.45 * sin(u * TAU * 2.2) * sin(u * PI)) + 6.0 * sin(u * PI)
		var top := Vector3(sin(u * TAU * 1.5) * 8.0, y, z)
		var p: Vector3 = pos + b * top
		var h: float = y + 40.0
		post_xfs.append(Transform3D(b, p - Vector3(0, h * 0.5 - 0.0, 0)).scaled_local(Vector3(0.7, h, 0.7)))
		if i > 0:
			var a: Vector3 = pos + b * prev
			var d: Vector3 = p - a
			var l: float = d.length()
			if l > 0.1:
				for sx: float in [-1.0, 1.0]:
					var rail := Look.box(Vector3(0.28, 0.28, l), red, Vector3.ZERO)
					var bb := Basis.looking_at(d.normalized(), Vector3.UP)
					rail.transform = Transform3D(bb, (a + p) * 0.5 + bb * Vector3(sx * 1.2, 0, 0))
					parent.add_child(rail)
		prev = top
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	_multi(unit, Look.flat(Color(1, 1, 1), 0.6), post_xfs, cols)


## Sweeping searchlight beams from `pos`: a few pale cones fanning slowly over the sky.
func searchlights(pos: Vector3, count: int = 3) -> void:
	for i: int in count:
		var beam := Beam.new()
		beam.position = pos + Vector3(float(i) * 3.0, 0, 0)
		beam.sweep_phase = float(i) * 2.1
		beam.speed = 0.35 + 0.1 * float(i)
		parent.add_child(beam)


## The fairground far below: a plane with the lit-lane shader.
func ground(center: Vector3, size: float) -> void:
	var board := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	board.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/carnival_ground.gdshader")
	board.material_override = m
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.position = center
	parent.add_child(board)


# ---- animated bits ------------------------------------------------------------------------------------------

class FarWheel extends Node3D:
	var radius: float = 30.0
	var _spin: Node3D

	func _ready() -> void:
		_spin = Node3D.new()
		add_child(_spin)
		var white: StandardMaterial3D = Look.flat(Color(0.95, 0.93, 0.92), 0.6)
		var bulb_mat := StandardMaterial3D.new()
		bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bulb_mat.vertex_color_use_as_albedo = true
		var segs: int = 32
		for i: int in segs:
			var a0: float = TAU * float(i) / float(segs)
			var a1: float = TAU * float(i + 1) / float(segs)
			var p0 := Vector3(0, sin(a0) * radius, cos(a0) * radius)
			var p1 := Vector3(0, sin(a1) * radius, cos(a1) * radius)
			var l: float = p0.distance_to(p1)
			var m := Look.box(Vector3(0.9, 0.9, l + 0.5), white, Vector3.ZERO)
			m.transform = Transform3D(Basis.looking_at((p1 - p0).normalized(), Vector3.UP), (p0 + p1) * 0.5)
			_spin.add_child(m)
		for i2: int in 12:
			var a: float = TAU * float(i2) / 12.0
			var tip := Vector3(0, sin(a) * radius, cos(a) * radius)
			var m2 := Look.box(Vector3(0.5, 0.5, radius), white, Vector3.ZERO)
			m2.transform = Transform3D(Basis.looking_at(tip.normalized(), Vector3.UP if absf(tip.normalized().y) < 0.99 else Vector3.RIGHT), tip * 0.5)
			_spin.add_child(m2)
			# a gondola hanging at the rim
			var gon := Look.box(Vector3(3.0, 2.4, 3.6), Look.flat(Color.from_hsv(float(i2) / 12.0, 0.6, 0.95), 0.5, 0.0, 0.25), tip)
			gon.set_meta("home", tip)
			_spin.add_child(gon)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var sph := SphereMesh.new()
		sph.radius = 0.5
		sph.height = 1.0
		sph.radial_segments = 6
		sph.rings = 3
		mm.mesh = sph
		mm.instance_count = 48
		for i3: int in 48:
			var ak: float = TAU * float(i3) / 48.0
			mm.set_instance_transform(i3, Transform3D(Basis.IDENTITY, Vector3(1.0, sin(ak) * (radius + 0.6), cos(ak) * (radius + 0.6))))
			mm.set_instance_color(i3, Color(2.6, 1.9, 0.7) if i3 % 2 == 0 else Color(2.6, 0.8, 1.1))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = bulb_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spin.add_child(mi)
		# the A-frame legs
		for sz: float in [-1.0, 1.0]:
			var leg := Look.box(Vector3(1.2, radius * 1.6, 1.2), white, Vector3(0, -radius * 0.55, sz * radius * 0.35))
			leg.rotation.x = sz * 0.22
			add_child(leg)

	func _process(dt: float) -> void:
		_spin.rotation.x += dt * 0.07
		# gondolas stay upright (counter-rotate about their own centres is unnecessary at this distance)


class Beam extends Node3D:
	var sweep_phase: float = 0.0
	var speed: float = 0.4

	func _ready() -> void:
		var cone := CylinderMesh.new()
		cone.top_radius = 6.0
		cone.bottom_radius = 0.2
		cone.height = 140.0
		cone.radial_segments = 14
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.85, 0.6, 0.07)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		var mi := Look.mesh_node(cone, m, Vector3(0, 70.0, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

	func _process(_dt: float) -> void:
		var t: float = Time.get_ticks_msec() * 0.001 * speed + sweep_phase
		var tilt: float = 0.3 + 0.2 * sin(t * 0.7)
		basis = Basis(Vector3.UP, sin(t) * 1.1) * Basis(Vector3.RIGHT, tilt)
