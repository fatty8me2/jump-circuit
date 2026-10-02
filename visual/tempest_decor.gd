class_name TempestDecor
extends RefCounted
## Tempest Tower set dressing, all built from primitives: the two towers (storm-grey glass curtain wall
## on the finished floors, the bare red-oxide steel skeleton above with its concrete slabs), I-beam
## webs under every steel walkway, the external climbing crane's mast, torn tarps snapping in the wind,
## scaffold towers, aircraft-warning lights, floodlights, the far skyline of glass towers (one
## MultiMesh) with their own cranes, and the city far below. Nothing here collides unless it says so.
## Materials are cached.

const GLASS: Shader = preload("res://visual/tempest_glass.gdshader")
const FRAME: Shader = preload("res://visual/tempest_frame.gdshader")
const TARP: Shader = preload("res://visual/tempest_tarp.gdshader")
const CITY: Shader = preload("res://visual/tempest_city.gdshader")

const STEEL := Color(0.42, 0.44, 0.47)
const PRIMER := Color(0.5, 0.2, 0.13)
const YELLOW := Color(0.95, 0.72, 0.1)
const CONCRETE := Color(0.5, 0.5, 0.49)
const WARN_RED := Color(1.0, 0.12, 0.08)

static var _mats: Dictionary = {}

var root: Node3D
var rng: RandomNumberGenerator
## Blinking aircraft-warning lamps: the level drives their materials from the clock.
var warn_mats: Array[StandardMaterial3D] = []


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r
	_mats.clear()


static func reset() -> void:
	_mats.clear()


static func _ns(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _add(n: Node3D) -> Node3D:
	root.add_child(n)
	return n


# ---- materials ----------------------------------------------------------------------------

static func glass(lit: float = 0.18) -> ShaderMaterial:
	var key: String = "gl|%.2f" % lit
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = GLASS
	m.set_shader_parameter("lit_share", lit)
	_mats[key] = m
	return m


static func frame() -> ShaderMaterial:
	if _mats.has("frame"):
		return _mats["frame"]
	var m := ShaderMaterial.new()
	m.shader = FRAME
	_mats["frame"] = m
	return m


static func tarp_material(tint: Color, seed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TARP
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("amp", 0.5)
	m.set_shader_parameter("speed", 6.0 + seed * 3.0)
	return m


static func mat(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var key: String = "m|%s|%.2f|%.2f" % [c.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


static func glow(c: Color, energy: float) -> StandardMaterial3D:
	var key: String = "g|%s|%.2f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	_mats[key] = m
	return m


# ---- the towers -----------------------------------------------------------------------------

## A tower body between world corners `lo` and `hi`: glass curtain wall up to `glass_top`, the bare
## steel frame (with its slabs and the concrete core) from there up to hi.y, a roof slab on top.
func tower(lo: Vector3, hi: Vector3, glass_top: float, lit: float = 0.18) -> void:
	var size := Vector3(hi.x - lo.x, glass_top - lo.y, hi.z - lo.z)
	var c := Vector3((lo.x + hi.x) * 0.5, (lo.y + glass_top) * 0.5, (lo.z + hi.z) * 0.5)
	_add(Look.box(size, glass(lit), c))
	if hi.y > glass_top + 0.5:
		var fh: float = hi.y - glass_top
		var fc := Vector3(c.x, glass_top + fh * 0.5, c.z)
		_add(_ns(Look.box(Vector3(size.x, fh, size.z), frame(), fc)))
		# the slabs at each floor (inset a little so the edge beams read), and the concrete core
		var slab: StandardMaterial3D = mat(CONCRETE, 0.85)
		var y: float = glass_top + 4.0
		while y <= hi.y + 0.01:
			_add(Look.box(Vector3(size.x - 1.2, 0.3, size.z - 1.2), slab, Vector3(c.x, y - 0.15, c.z)))
			y += 4.0
		var core := Vector3(minf(size.x * 0.3, 28.0), fh + 6.0, minf(size.z * 0.3, 28.0))
		_add(Look.box(core, mat(CONCRETE.darkened(0.1), 0.9), Vector3(c.x, glass_top + core.y * 0.5, c.z)))
	# aircraft-warning lamps on the corners of the top
	for sx: float in [lo.x, hi.x]:
		for sz: float in [lo.z, hi.z]:
			warning_light(Vector3(sx, hi.y + 0.6, sz), 0.35)


## A blinking red aircraft-warning lamp (the level blinks it on the clock).
func warning_light(pos: Vector3, r: float = 0.25) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = WARN_RED
	m.emission_enabled = true
	m.emission = WARN_RED
	m.emission_energy_multiplier = 2.0
	warn_mats.append(m)
	_add(_ns(Look.sphere(r, m, pos)))
	_add(_ns(Look.cylinder(r * 0.7, r * 1.2, mat(STEEL, 0.4, 0.6), pos - Vector3(0, r * 1.1, 0), -1.0, 8)))


## An I-beam's web and bottom flange hung under a walkway whose top-centre is `top` (world), `size`
## its (x, thick, z) and `yaw` its turn (degrees).
func ibeam(top: Vector3, size: Vector3, yaw: float, depth: float = 0.55) -> void:
	var n := Node3D.new()
	n.position = top - Vector3(0, size.y, 0)
	n.rotation.y = deg_to_rad(yaw)
	var steel: StandardMaterial3D = mat(PRIMER, 0.55, 0.45)
	var along_x: bool = size.x >= size.z
	var length: float = maxf(size.x, size.z) - 0.1
	var width: float = minf(size.x, size.z)
	var web_w: float = clampf(width * 0.14, 0.1, 0.3)
	if along_x:
		n.add_child(Look.box(Vector3(length, depth, web_w), steel, Vector3(0, -depth * 0.5, 0)))
		n.add_child(Look.box(Vector3(length, 0.1, width * 0.85), steel, Vector3(0, -depth - 0.05, 0)))
	else:
		n.add_child(Look.box(Vector3(web_w, depth, length), steel, Vector3(0, -depth * 0.5, 0)))
		n.add_child(Look.box(Vector3(width * 0.85, 0.1, length), steel, Vector3(0, -depth - 0.05, 0)))
	_add(n)


## A deck's underside: a grid of steel joists under a slab whose top-centre is `top`.
func deck_under(top: Vector3, size: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.position = top - Vector3(0, size.y, 0)
	n.rotation.y = deg_to_rad(yaw)
	var steel: StandardMaterial3D = mat(PRIMER, 0.55, 0.45)
	var k: int = maxi(int(size.x / 1.6), 2)
	for i: int in k:
		var x: float = -size.x * 0.5 + (float(i) + 0.5) * size.x / float(k)
		n.add_child(Look.box(Vector3(0.14, 0.45, size.z - 0.2), steel, Vector3(x, -0.225, 0)))
	n.add_child(Look.box(Vector3(size.x - 0.2, 0.3, 0.16), steel, Vector3(0, -0.3, 0)))
	_add(n)


## A tall column from `top` down to `bottom_y` (a mast leg, a support under a deck).
func column(top: Vector3, bottom_y: float, w: float = 0.5, c: Color = PRIMER) -> void:
	var h: float = top.y - bottom_y
	if h <= 0.1:
		return
	_add(Look.box(Vector3(w, h, w), mat(c, 0.55, 0.45), Vector3(top.x, bottom_y + h * 0.5, top.z)))


## The external climbing crane's mast: a square lattice tower from far below up to `top`
## (its top centre), tied back to the facade every 12 m toward `tie_dir` (world, flat).
func crane_mast(top: Vector3, bottom_y: float, tie_dir: Vector3, tie_len: float) -> void:
	var w: float = 2.2
	var h: float = top.y - bottom_y
	var y_mat: StandardMaterial3D = mat(YELLOW, 0.5, 0.35)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add(Look.box(Vector3(0.22, h, 0.22), y_mat, Vector3(top.x + sx * w * 0.5, bottom_y + h * 0.5, top.z + sz * w * 0.5)))
	var y: float = top.y - 0.6
	var i: int = 0
	while y > maxf(bottom_y, top.y - 140.0):
		for face: int in 4:
			var a := Vector3(-w * 0.5, 0, -w * 0.5)
			var b := Vector3(w * 0.5, 0, -w * 0.5)
			match face:
				1:
					a = Vector3(w * 0.5, 0, -w * 0.5)
					b = Vector3(w * 0.5, 0, w * 0.5)
				2:
					a = Vector3(w * 0.5, 0, w * 0.5)
					b = Vector3(-w * 0.5, 0, w * 0.5)
				3:
					a = Vector3(-w * 0.5, 0, w * 0.5)
					b = Vector3(-w * 0.5, 0, -w * 0.5)
			var lo: Vector3 = top + (a if i % 2 == 0 else b) + Vector3(0, y - top.y - 2.4, 0)
			var hi: Vector3 = top + (b if i % 2 == 0 else a) + Vector3(0, y - top.y, 0)
			_add(TempestLoad._rod(lo, hi, 0.06, y_mat))
		if i % 5 == 0 and tie_len > 0.0:
			var tie_a: Vector3 = Vector3(top.x, y, top.z)
			_add(TempestLoad._rod(tie_a, tie_a + tie_dir * tie_len, 0.1, mat(STEEL, 0.4, 0.6)))
		y -= 2.4
		i += 1
	# the climbing frame and the slewing ring under the turntable
	_add(Look.box(Vector3(w + 0.8, 1.2, w + 0.8), y_mat, top - Vector3(0, 1.4, 0)))
	_add(Look.cylinder(1.4, 0.5, mat(STEEL.darkened(0.3), 0.4, 0.7), top - Vector3(0, 0.55, 0), -1.0, 20))


## A torn tarp tied along one edge at `tie` (world), streaming downwind `length` metres, `width` wide,
## turned to `yaw` (degrees: 0 streams along +X).
func tarp(tie: Vector3, length: float, width: float, yaw: float, tint: Color) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(length, width)
	pm.subdivide_width = 14
	pm.subdivide_depth = 5
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = tarp_material(tint, rng.randf())
	mi.position = Vector3(length * 0.5, 0, 0)
	mi.rotation.x = PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	var holder := Node3D.new()
	holder.position = tie
	holder.rotation.y = deg_to_rad(yaw)
	holder.add_child(mi)
	_add(holder)


## A scaffold tower standing against a facade: tubes and boards, `w` wide, from bottom_y up to top_y.
func scaffold_tower(base: Vector3, top_y: float, w: float, yaw: float) -> void:
	var n := Node3D.new()
	n.position = base
	n.rotation.y = deg_to_rad(yaw)
	var tube: StandardMaterial3D = mat(Color(0.7, 0.72, 0.75), 0.35, 0.85)
	var board: StandardMaterial3D = mat(Color(0.6, 0.47, 0.3), 0.9)
	var h: float = top_y - base.y
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			n.add_child(Look.cylinder(0.05, h, tube, Vector3(sx * w * 0.5, h * 0.5, sz * 0.7), -1.0, 6))
	var y: float = 2.0
	while y < h:
		n.add_child(Look.box(Vector3(w, 0.06, 1.4), board, Vector3(0, y, 0)))
		n.add_child(Look.box(Vector3(w, 0.05, 0.05), tube, Vector3(0, y + 1.0, 0.7)))
		y += 2.0
	_add(n)


## A floodlight on a short mast pointing at `aim` (world): a lamp head that glows. No real light.
func floodlight(pos: Vector3, aim: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	n.add_child(Look.cylinder(0.06, 2.4, mat(STEEL, 0.4, 0.6), Vector3(0, 1.2, 0), -1.0, 6))
	var head := Node3D.new()
	head.position = Vector3(0, 2.5, 0)
	n.add_child(head)
	_add(n)
	head.look_at(aim, Vector3.UP)
	head.add_child(Look.box(Vector3(0.7, 0.45, 0.25), mat(Color(0.15, 0.15, 0.16), 0.5, 0.5)))
	head.add_child(_ns(Look.box(Vector3(0.6, 0.36, 0.03), glow(Color(1.0, 0.95, 0.85), 3.0), Vector3(0, 0, -0.14))))


## Junction boxes and conduit at the ends of an arcing cable (dresses a LaserGate's posts).
func arc_posts(center: Vector3, width: float, height: float, yaw: float) -> void:
	var n := Node3D.new()
	n.position = center
	n.rotation.y = deg_to_rad(yaw)
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.5, 0.7, 0.4), mat(Color(0.2, 0.22, 0.25), 0.5, 0.5), Vector3(sx * (width * 0.5 + 0.35), height * 0.5 + 0.2, 0)))
		n.add_child(_ns(Look.box(Vector3(0.36, 0.08, 0.42), glow(YELLOW, 1.2), Vector3(sx * (width * 0.5 + 0.35), height * 0.5 - 0.2, 0))))
	_add(n)


## The express hoist's cage round a warp ring (floor point, facing yaw): mesh-panel sides, a roof,
## a hazard-striped threshold.
func hoist_cage(floor_pos: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.position = floor_pos
	n.rotation.y = deg_to_rad(yaw)
	var y_mat: StandardMaterial3D = mat(YELLOW, 0.5, 0.35)
	var mesh_mat: StandardMaterial3D = mat(Color(0.3, 0.32, 0.35, 0.5), 0.4, 0.6)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var r: float = WarpPortal.RING_RADIUS + 0.6
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.12, r * 2.0 + 0.6, 0.12), y_mat, Vector3(sx * r, r + 0.3, 0)))
		n.add_child(_ns(Look.box(Vector3(0.04, r * 2.0, 1.4), mesh_mat, Vector3(sx * r, r + 0.2, 0.7))))
	n.add_child(Look.box(Vector3(r * 2.0 + 0.3, 0.2, 1.6), y_mat, Vector3(0, r * 2.0 + 0.7, 0.6)))
	_add(n)


## The aircraft-warning beacon at the very top: a mast and a big red lens. Returns the lens material.
func beacon(base: Vector3, height: float) -> StandardMaterial3D:
	var steel: StandardMaterial3D = mat(STEEL, 0.4, 0.7)
	_add(Look.cylinder(0.35, height, steel, base + Vector3(0, height * 0.5, 0), 0.18, 10))
	for i: int in 4:
		_add(_ns(Look.box(Vector3(0.05, 0.05, 1.6), mat(YELLOW, 0.5, 0.3), base + Vector3(0, height * (0.25 + 0.2 * float(i)), 0))))
	var lens := StandardMaterial3D.new()
	lens.albedo_color = WARN_RED
	lens.emission_enabled = true
	lens.emission = WARN_RED
	lens.emission_energy_multiplier = 2.0
	_add(Look.cylinder(0.55, 0.9, lens, base + Vector3(0, height + 0.45, 0), 0.45, 16))
	_add(Look.cylinder(0.6, 0.12, steel, base + Vector3(0, height + 0.96, 0), -1.0, 16))
	_add(Look.cylinder(0.06, 2.6, steel, base + Vector3(0, height + 2.3, 0), 0.02, 6))
	return lens


# ---- far away -------------------------------------------------------------------------------

## The far skyline: glass towers in a ring round `center`, from the city floor (street_y) up to their
## tops, one MultiMesh sharing the curtain-wall material, with `keep` (Callable(Vector3)->bool)
## rejecting spots too close to the course. A few carry a tower crane of their own.
func skyline(center: Vector3, r0: float, r1: float, count: int, street_y: float, keep: Callable) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	var xforms: Array[Transform3D] = []
	var tries: int = 0
	while xforms.size() < count and tries < count * 12:
		tries += 1
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(r0, r1)
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		if not keep.call(p):
			continue
		var w: float = rng.randf_range(24.0, 60.0)
		var d: float = rng.randf_range(24.0, 60.0)
		var top: float = center.y + rng.randf_range(-120.0, 90.0) * (0.4 + 0.6 * clampf((r - r0) / (r1 - r0), 0.0, 1.0)) + 40.0
		var h: float = top - street_y
		var b := Basis.from_scale(Vector3(w, h, d)).rotated(Vector3.UP, rng.randf_range(-0.2, 0.2))
		xforms.append(Transform3D(b, Vector3(p.x, street_y + h * 0.5, p.z)))
		if rng.randf() < 0.18:
			_far_crane(Vector3(p.x, top, p.z), rng.randf() * TAU)
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = glass(0.12)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mmi)


func _far_crane(top: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.position = top
	n.rotation.y = yaw
	var y_mat: StandardMaterial3D = mat(YELLOW.darkened(0.2), 0.6, 0.3)
	n.add_child(Look.box(Vector3(2.0, 26.0, 2.0), y_mat, Vector3(0, 13.0, 0)))
	n.add_child(Look.box(Vector3(46.0, 1.4, 1.6), y_mat, Vector3(14.0, 26.6, 0)))
	n.add_child(Look.box(Vector3(5.0, 3.0, 2.2), mat(CONCRETE, 0.9), Vector3(-10.0, 25.0, 0)))
	n.add_child(_ns(Look.sphere(0.6, glow(WARN_RED, 3.0), Vector3(37.0, 27.6, 0))))
	_add(n)


## The city far below: one huge plane with the street-grid shader.
func city(center: Vector3, y: float) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(5000, 5000)
	var m := ShaderMaterial.new()
	m.shader = CITY
	var mi := Look.mesh_node(pm, m, Vector3(center.x, y, center.z))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi)
