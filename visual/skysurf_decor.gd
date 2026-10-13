class_name SkysurfDecor
extends RefCounted
## Sky Surf's set dressing: kites with tails of bows, hot-air balloons, far floating isles with
## waterfalls, cloud mounds and towers rising from the cloud sea, spinning pinwheels, strings of bunting
## and the rainbow. Everything is a handful of shared meshes and shaders; the animation lives in the
## shaders (TIME), nothing here runs per frame. Visual only, no collision.

const KITE_SHADER: Shader = preload("res://visual/skysurf_kite.gdshader")

## The pastel paint box.
const ROSE := Color(1.0, 0.55, 0.62)
const PEACH := Color(1.0, 0.76, 0.58)
const BUTTER := Color(1.0, 0.9, 0.55)
const MINT := Color(0.62, 0.9, 0.76)
const AQUA := Color(0.5, 0.88, 0.94)
const SKY := Color(0.62, 0.74, 1.0)
const LILAC := Color(0.78, 0.66, 0.96)
const CREAM := Color(1.0, 0.95, 0.88)

var root: Node3D
var rng: RandomNumberGenerator
var _kite_mat: ShaderMaterial
var _kite_mats: Dictionary = {}


func _init(level_root: Node3D, rng_in: RandomNumberGenerator) -> void:
	root = level_root
	rng = rng_in
	_kite_mat = ShaderMaterial.new()
	_kite_mat.shader = KITE_SHADER


func palette(i: int) -> Color:
	var cols: Array[Color] = [ROSE, PEACH, BUTTER, MINT, AQUA, SKY, LILAC]
	return cols[absi(i) % cols.size()]


func _place(n: Node3D, pos: Vector3, parent: Node3D = null) -> void:
	n.position = pos
	(parent if parent != null else root).add_child(n)


## One kite material per seed (the shader's flutter phase), shared by all kites of that seed.
func _kmat(seed_v: float) -> ShaderMaterial:
	var key: int = int(seed_v * 10.0) % 8
	if not _kite_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = KITE_SHADER
		m.set_shader_parameter("seed", float(key) * 0.8)
		_kite_mats[key] = m
	return _kite_mats[key]


func _mesh_from(verts: PackedVector3Array, cols: PackedColorArray) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var normals := PackedVector3Array()
	for i: int in verts.size():
		normals.append(Vector3(0, 0, 1))
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---- kites -----------------------------------------------------------------------------------

## A diamond kite facing +Z, two-tone, with a tail of `bows` little bows hanging below it. `size` is the
## kite's height in metres. Returns the node (origin = the kite's centre).
func kite(pos: Vector3, size: float, c1: Color, c2: Color, yaw_deg: float = 0.0, bows: int = 7) -> Node3D:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var top := Vector3(0, 1.5, 0)
	var left := Vector3(-1.0, 0.35, 0)
	var bottom := Vector3(0, -1.2, 0)
	var right := Vector3(1.0, 0.35, 0)
	var spine := Vector3(0, 0.35, 0.22)
	var tris: Array = [[top, left, spine, c1], [top, spine, right, c2], [left, bottom, spine, c2], [spine, bottom, right, c1]]
	for t: Array in tris:
		for k: int in 3:
			v.append(t[k])
			var col: Color = t[3]
			c.append(Color(col.r, col.g, col.b, 0.0))
	# the cross spars, as two thin pale strips on the front
	var pale := Color(1.0, 0.97, 0.92, 0.0)
	_strip(v, c, Vector3(0, 1.5, 0.23), Vector3(0, -1.2, 0.23), 0.045, pale)
	_strip(v, c, Vector3(-1.0, 0.35, 0.23), Vector3(1.0, 0.35, 0.23), 0.045, pale)
	# the tail: a string with a bow every metre, streaming from the bottom point
	var y: float = -1.2
	var prev := Vector3(0, y, 0)
	for k: int in bows:
		var nxt := Vector3(0, y - 1.05, 0)
		_strip(v, c, prev, nxt, 0.04, Color(1.0, 0.97, 0.92, 1.0))
		var bc: Color = c1 if k % 2 == 0 else c2
		var mid := (prev + nxt) * 0.5
		var bow_c := Color(bc.r, bc.g, bc.b, 1.0)
		# a bow: two small triangles meeting at the string
		v.append_array(PackedVector3Array([mid, mid + Vector3(-0.3, 0.2, 0), mid + Vector3(-0.3, -0.2, 0),
			mid, mid + Vector3(0.3, 0.2, 0), mid + Vector3(0.3, -0.2, 0)]))
		for q: int in 6:
			c.append(bow_c)
		prev = nxt
		y -= 1.05
	var n := MeshInstance3D.new()
	n.mesh = _mesh_from(v, c)
	n.material_override = _kmat(pos.x * 0.37 + pos.z * 0.19)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.scale = Vector3.ONE * size / 2.7
	n.rotation_degrees.y = yaw_deg
	_place(n, pos)
	return n


## A thin vertical-ish quad strip between two points in the kite's plane.
func _strip(v: PackedVector3Array, c: PackedColorArray, a: Vector3, b: Vector3, half: float, col: Color) -> void:
	var d: Vector3 = b - a
	var side := Vector3(d.y, -d.x, 0.0)
	side = side.normalized() * half if side.length() > 0.0001 else Vector3(half, 0, 0)
	v.append_array(PackedVector3Array([a - side, a + side, b - side, a + side, b + side, b - side]))
	for i: int in 6:
		c.append(col)


## A line from a kite down to a point (its tether), thin and pale.
func tether(from: Vector3, to: Vector3) -> void:
	var d: Vector3 = to - from
	if d.length() < 0.5:
		return
	var n := Look.cylinder(0.025, d.length(), Look.flat(Color(1.0, 0.96, 0.92, 1.0), 0.8), Vector3.ZERO, -1.0, 4)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up: Vector3 = d.normalized()
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9)).normalized()
	n.basis = Basis(side, up, side.cross(up))
	_place(n, (from + to) * 0.5)


# ---- balloons --------------------------------------------------------------------------------

## A hot-air balloon with striped gores; `size` is the envelope's diameter in metres.
func balloon(pos: Vector3, size: float, c1: Color, c2: Color) -> Node3D:
	var holder := Node3D.new()
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var lon: int = 12
	var lat: int = 9
	for j: int in lat:
		var t0: float = float(j) / float(lat)
		var t1: float = float(j + 1) / float(lat)
		for i: int in lon:
			var a0: float = float(i) / float(lon) * TAU
			var a1: float = float(i + 1) / float(lon) * TAU
			var col: Color = c1 if i % 2 == 0 else c2
			var q: Array[Vector3] = [_bal(t0, a0), _bal(t0, a1), _bal(t1, a0), _bal(t1, a1)]
			v.append_array(PackedVector3Array([q[0], q[2], q[1], q[1], q[2], q[3]]))
			for k: int in 6:
				c.append(Color(col.r, col.g, col.b, 0.0))
	var env := MeshInstance3D.new()
	env.mesh = _mesh_from(v, c)
	env.material_override = _kmat(pos.x * 0.21 + pos.z * 0.33)
	env.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(env)
	holder.add_child(Look.box(Vector3(0.9, 0.7, 0.9), Look.flat(Color(0.72, 0.5, 0.36), 0.9), Vector3(0, -1.9, 0)))
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			var rope := Look.cylinder(0.02, 1.0, Look.flat(Color(0.9, 0.85, 0.8), 0.9), Vector3(sx * 0.28, -1.05, sz * 0.28), -1.0, 4)
			holder.add_child(rope)
	holder.scale = Vector3.ONE * size / 2.0
	holder.rotation_degrees.y = rng.randf() * 360.0
	_place(holder, pos)
	return holder


## A point on the balloon envelope: t 0 = crown, 1 = the mouth.
func _bal(t: float, a: float) -> Vector3:
	var phi: float = t * PI * 0.88
	var r: float = sin(phi)
	if t > 0.65:
		r *= lerpf(1.0, 0.45, (t - 0.65) / 0.35)
	return Vector3(cos(a) * r, 0.2 + cos(phi) * 1.1, sin(a) * r)


# ---- cloud sea -------------------------------------------------------------------------------

## A heap of cumulus (shaded with the theme's cloud material) rising from the cloud sea.
func mound(pos: Vector3, scale: float) -> void:
	var cl := Node3D.new()
	var mat: ShaderMaterial = Look.cloud_material()
	var n: int = rng.randi_range(5, 8)
	for i: int in n:
		var a: float = float(i) / float(n) * TAU
		var r: float = rng.randf_range(0.0, 1.0) * 4.0
		var s := Look.sphere(1.0, mat, Vector3(cos(a) * r, rng.randf_range(-0.2, 1.8), sin(a) * r) * scale)
		s.scale = Vector3(rng.randf_range(2.8, 4.6), rng.randf_range(2.0, 3.4), rng.randf_range(2.8, 4.6)) * scale
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cl.add_child(s)
	_place(cl, pos)


## A tall column of cumulus: a stack of shrinking puffs.
func tower(pos: Vector3, height: float, radius: float) -> void:
	var cl := Node3D.new()
	var mat: ShaderMaterial = Look.cloud_material()
	var y: float = 0.0
	var r: float = radius
	while y < height:
		var s := Look.sphere(1.0, mat, Vector3(rng.randf_range(-0.3, 0.3) * r, y, rng.randf_range(-0.3, 0.3) * r))
		s.scale = Vector3(r * rng.randf_range(0.9, 1.3), r * 0.75, r * rng.randf_range(0.9, 1.3))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cl.add_child(s)
		y += r * 0.8
		r = maxf(r * lerpf(0.93, 1.02, rng.randf()), radius * 0.45)
	_place(cl, pos)


# ---- far floating isles ----------------------------------------------------------------------

## A little floating isle for the distance: a rose-lilac keel, a mint meadow, a few pastel trees and,
## now and then, a cottage and a waterfall spilling off the rim into the cloud. `r` is its radius.
func far_isle(pos: Vector3, r: float, falls: bool = true) -> void:
	var holder := Node3D.new()
	var keel_h: float = r * rng.randf_range(0.9, 1.5)
	var keel := Look.cylinder(r * 0.12, keel_h, Look.flat(Look.c("side").darkened(0.05), 0.9), Vector3(0, -keel_h * 0.5 - 0.4, 0), r * 0.95, 14)
	holder.add_child(keel)
	holder.add_child(Look.cylinder(r, 0.9, Look.flat(Look.c("decor"), 0.85), Vector3(0, 0.0, 0), r * 0.97, 24))
	holder.add_child(Look.cylinder(r * 1.02, 0.35, Look.flat(Look.c("top"), 0.85), Vector3(0, -0.55, 0), r * 1.0, 24))
	# trees and bushes
	var trees: int = rng.randi_range(2, 6)
	for i: int in trees:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.15, 0.75) * r
		var s: float = clampf(r * rng.randf_range(0.08, 0.15), 0.8, 3.2)
		var tc: Color = palette(rng.randi())
		holder.add_child(Look.cylinder(s * 0.1, s * 1.1, Look.flat(Color(0.6, 0.45, 0.4), 0.9), Vector3(cos(a) * d, 0.45 + s * 0.55, sin(a) * d), -1.0, 6))
		holder.add_child(Look.sphere(s * 0.62, Look.flat(tc.lerp(Look.c("decor"), 0.4), 0.9), Vector3(cos(a) * d, 0.45 + s * 1.3, sin(a) * d)))
	if r > 9.0 and rng.randf() < 0.6:
		# a cottage with a coloured roof
		var hs: float = r * 0.12
		var hc: Vector3 = Vector3(rng.randf_range(-0.3, 0.3) * r, 0.45 + hs * 0.5, rng.randf_range(-0.3, 0.3) * r)
		holder.add_child(Look.box(Vector3(hs * 1.4, hs, hs * 1.2), Look.flat(CREAM, 0.9), hc))
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(hs * 1.7, hs * 0.7, hs * 1.4)
		roof.mesh = pm
		roof.material_override = Look.flat(palette(rng.randi()), 0.8)
		roof.position = hc + Vector3(0, hs * 0.85, 0)
		holder.add_child(roof)
	holder.rotation.y = rng.randf() * TAU
	_place(holder, pos)
	if falls and r > 7.0 and rng.randf() < 0.7:
		var a2: float = rng.randf() * TAU
		var top := pos + Vector3(cos(a2), 0.0, sin(a2)) * r * 0.96 + Vector3(0, 0.3, 0)
		waterfall(top, rng.randf_range(24.0, 60.0), clampf(r * 0.12, 1.2, 3.5))


## A waterfall: a pale ribbon falling `length` m from `top`, pulses running down it.
func waterfall(top: Vector3, length: float, width: float) -> void:
	var rb := SkysurfRibbon.new()
	rb.points = PackedVector3Array([top, top + Vector3(0, -length * 0.5, 0.2), top + Vector3(0.2, -length, 0)])
	rb.width = width
	rb.color_a = Color(0.82, 0.94, 1.0)
	rb.color_b = Color(1.0, 1.0, 1.0)
	rb.speed = 7.0
	rb.wave = 0.08
	rb.strength = 0.8
	rb.twist = 0.0
	rb.up_hint = Vector3(1, 0, 0.2)
	rb.build()
	root.add_child(rb)


# ---- small things ----------------------------------------------------------------------------

## A pinwheel on a post, its four vanes spinning.
func pinwheel(pos: Vector3, scale: float, c1: Color, c2: Color, period: float = 3.0) -> void:
	var n := Node3D.new()
	n.add_child(Look.cylinder(0.05 * scale, 2.2 * scale, Look.flat(CREAM, 0.8), Vector3(0, 1.1 * scale, 0), -1.0, 6))
	var wheel := Node3D.new()
	wheel.set_script(preload("res://visual/spin.gd"))
	wheel.set("period", period)
	wheel.set("axis", Vector3(0, 0, 1))
	wheel.position = Vector3(0, 2.25 * scale, 0.1 * scale)
	for i: int in 4:
		var vane := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.7 * scale, 0.7 * scale, 0.03)
		vane.mesh = pm
		var mat: StandardMaterial3D = Look.flat(c1 if i % 2 == 0 else c2, 0.8).duplicate()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		vane.material_override = mat
		vane.position = Vector3(0.25, 0.25, 0) * scale
		var holder := Node3D.new()
		holder.rotation.z = float(i) * PI * 0.5
		holder.add_child(vane)
		wheel.add_child(holder)
	n.add_child(wheel)
	n.add_child(Look.sphere(0.09 * scale, Look.flat(BUTTER, 0.5, 0.0, 1.0), Vector3(0, 2.25 * scale, 0.14 * scale)))
	n.rotation.y = rng.randf() * TAU
	_place(n, pos)


## A string of bunting between two points, sagging, with `count` pennants fluttering.
func bunting(a: Vector3, b: Vector3, count: int = 9) -> void:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var dir: Vector3 = b - a
	var len: float = dir.length()
	if len < 1.0:
		return
	var side: Vector3 = dir.cross(Vector3.UP)
	side = side.normalized() * 0.05 if side.length() > 0.001 else Vector3(0.05, 0, 0)
	var prev: Vector3 = a
	for i: int in count + 1:
		var t: float = float(i) / float(count)
		var p: Vector3 = a.lerp(b, t) + Vector3(0, -sin(t * PI) * len * 0.07, 0)
		if i > 0:
			v.append_array(PackedVector3Array([prev - side, prev + side, p - side, prev + side, p + side, p - side]))
			for k: int in 6:
				c.append(Color(1.0, 0.97, 0.92, 0.0))
			var pc: Color = palette(i)
			var m: Vector3 = (prev + p) * 0.5
			var fl: float = len / float(count) * 0.32
			var along: Vector3 = dir.normalized() * fl
			v.append_array(PackedVector3Array([m + along, m - along, m + Vector3(0, -fl * 1.5, 0)]))
			for k: int in 3:
				c.append(Color(pc.r, pc.g, pc.b, 0.35))
		prev = p
	var n := MeshInstance3D.new()
	n.mesh = _mesh_from(v, c)
	n.material_override = _kmat(a.x * 0.3 + a.z * 0.2)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(n)


## A rainbow arch standing on its two ends in the vertical plane of `yaw_deg` (arch spans local X).
## `radius` is the arch's inner radius; seven bands are laid outward from it.
func rainbow(base: Vector3, radius: float, yaw_deg: float) -> void:
	var cols: Array[Color] = [Color(1.0, 0.45, 0.5), Color(1.0, 0.68, 0.45), Color(1.0, 0.92, 0.5), Color(0.6, 0.92, 0.6),
		Color(0.5, 0.85, 1.0), Color(0.6, 0.62, 1.0), Color(0.82, 0.6, 1.0)]
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var normal: Vector3 = basis * Vector3(0, 0, 1)
	var bw: float = 1.5
	for k: int in cols.size():
		var rr: float = radius + float(k) * bw
		var pts := PackedVector3Array()
		for j: int in 25:
			var a: float = PI * float(j) / 24.0
			pts.append(base + basis * Vector3(cos(a) * rr, sin(a) * rr, 0.0))
		var rb := SkysurfRibbon.new()
		rb.points = pts
		rb.width = bw * 0.98
		rb.color_a = cols[k]
		rb.color_b = cols[k].lightened(0.35)
		rb.speed = 2.0
		rb.wave = 0.0
		rb.strength = 0.8
		rb.twist = 0.0
		rb.phase = float(k) * 0.4
		rb.up_hint = normal
		rb.step = 2.5
		rb.build()
		root.add_child(rb)
