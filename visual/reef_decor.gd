class_name ReefDecor
extends RefCounted
## Coral Depths set dressing: bioluminescent coral, anemones, sea fans, sponges, kelp,
## rock pinnacles, god rays and the sea surface overhead. Decoration only (no collision).
## The level composes these around (never on) its route.

const KELP_SHADER: Shader = preload("res://visual/reef_kelp.gdshader")
const SHAFT_SHADER: Shader = preload("res://visual/reef_shaft.gdshader")
const SURFACE_SHADER: Shader = preload("res://visual/reef_surface.gdshader")
const SWAY: Script = preload("res://visual/reef_sway.gd")

const PINK := Color(1.0, 0.42, 0.7)
const CYAN := Color(0.3, 1.0, 0.92)
const VIOLET := Color(0.7, 0.45, 1.0)
const ORANGE := Color(1.0, 0.58, 0.3)
const LIME := Color(0.7, 1.0, 0.4)
const GLOWS: Array[Color] = [PINK, CYAN, VIOLET, ORANGE, LIME]

var root: Node3D
var rng: RandomNumberGenerator
var _kelp_mat: ShaderMaterial
var _shaft_mat: ShaderMaterial


func _init(level_root: Node3D, random: RandomNumberGenerator) -> void:
	root = level_root
	rng = random


func _put(n: Node3D, pos: Vector3, parent: Node3D = null) -> Node3D:
	n.position = pos
	(parent if parent != null else root).add_child(n)
	return n


func glow_color() -> Color:
	return GLOWS[rng.randi() % GLOWS.size()]


static func rock_mat(shade: float = 0.0) -> StandardMaterial3D:
	return Look.flat(Look.c("side").darkened(0.25 + shade), 0.95)


# ---- coral --------------------------------------------------------------------------------

## Staghorn coral: a few tapered branches with glowing tips.
func staghorn(pos: Vector3, scale: float = 1.0, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	var body: StandardMaterial3D = Look.flat(col.darkened(0.35), 0.7, 0.0, 0.35)
	var tip: StandardMaterial3D = Look.flat(col.lightened(0.2), 0.4, 0.0, 2.2)
	for i: int in rng.randi_range(3, 5):
		var a: float = rng.randf() * TAU
		var tiltv: float = rng.randf_range(0.2, 0.7)
		var h: float = rng.randf_range(0.8, 1.5) * scale
		var arm := Node3D.new()
		arm.rotation = Vector3(cos(a) * tiltv, 0, sin(a) * tiltv)
		arm.add_child(Look.cylinder(0.09 * scale, h, body, Vector3(0, h * 0.5, 0), 0.05 * scale, 6))
		arm.add_child(Look.sphere(0.08 * scale, tip, Vector3(0, h, 0)))
		if rng.randf() < 0.7:
			var sub := Node3D.new()
			sub.position = Vector3(0, h * 0.55, 0)
			sub.rotation = Vector3(0, 0, rng.randf_range(0.5, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0))
			var h2: float = h * 0.55
			sub.add_child(Look.cylinder(0.06 * scale, h2, body, Vector3(0, h2 * 0.5, 0), 0.035 * scale, 6))
			sub.add_child(Look.sphere(0.065 * scale, tip, Vector3(0, h2, 0)))
			arm.add_child(sub)
		n.add_child(arm)
	n.rotation.y = rng.randf() * TAU
	return _put(n, pos, parent)


## Brain coral: a squashed mound with a glowing groove band.
func brain(pos: Vector3, r: float = 0.8, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	var s := Look.sphere(r, Look.flat(col.darkened(0.45).lerp(Color(0.8, 0.7, 0.55), 0.3), 0.9))
	s.scale = Vector3(1.0, 0.62, 1.0)
	n.add_child(s)
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.62
	tm.outer_radius = r * 0.7
	tm.rings = 24
	tm.ring_segments = 6
	var band := Look.mesh_node(tm, Look.flat(col, 0.4, 0.0, 1.6), Vector3(0, r * 0.35, 0))
	band.scale = Vector3(1, 0.6, 1)
	n.add_child(band)
	return _put(n, pos, parent)


## Sea fan: a flat lacy fan on a short stalk, swaying.
func sea_fan(pos: Vector3, h: float = 2.2, color: Color = Color(0, 0, 0, 0), yaw: float = -1.0, parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	n.set_script(SWAY)
	n.set("amount", 0.08)
	n.set("speed", rng.randf_range(0.6, 1.0))
	n.set("offset", rng.randf() * 10.0)
	var mat: StandardMaterial3D = Look.flat(Color(col.r, col.g, col.b, 0.85), 0.6, 0.0, 0.9)
	var fan := Look.cylinder(h * 0.5, 0.04, mat, Vector3(0, h * 0.55, 0), -1.0, 18)
	fan.rotation.x = PI * 0.5
	fan.scale = Vector3(1.0, 1.0, 0.8)
	fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(fan)
	var rib: StandardMaterial3D = Look.flat(col.lightened(0.3), 0.4, 0.0, 2.0)
	for i: int in 5:
		var a: float = lerpf(-1.1, 1.1, float(i) / 4.0)
		var r := Look.box(Vector3(0.04, h * 0.5, 0.05), rib, Vector3(sin(a) * h * 0.24, h * 0.3 + cos(a) * h * 0.24, 0.02))
		r.rotation.z = -a
		n.add_child(r)
	n.add_child(Look.cylinder(0.06, h * 0.3, Look.flat(col.darkened(0.5), 0.8), Vector3(0, h * 0.15, 0), 0.04, 6))
	n.rotation.y = yaw if yaw >= 0.0 else rng.randf() * TAU
	return _put(n, pos, parent)


## Anemone: a squat column crowned with swaying glowing tentacles.
func anemone(pos: Vector3, r: float = 0.45, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	n.add_child(Look.cylinder(r, r * 1.1, Look.flat(col.darkened(0.55), 0.8), Vector3(0, r * 0.55, 0), r * 0.85, 12))
	var crown := Node3D.new()
	crown.position = Vector3(0, r * 1.1, 0)
	crown.set_script(SWAY)
	crown.set("amount", 0.18)
	crown.set("speed", rng.randf_range(0.8, 1.4))
	crown.set("offset", rng.randf() * 10.0)
	var tmat: StandardMaterial3D = Look.flat(col, 0.4, 0.0, 1.8)
	var cnt: int = 9
	for i: int in cnt:
		var a: float = TAU * float(i) / float(cnt)
		var arm := Node3D.new()
		arm.rotation = Vector3(sin(a) * 0.55, 0, -cos(a) * 0.55)
		arm.add_child(Look.cylinder(r * 0.12, r * 1.3, tmat, Vector3(0, r * 0.65, 0), r * 0.05, 5))
		arm.position = Vector3(cos(a), 0, sin(a)) * r * 0.55
		crown.add_child(arm)
	n.add_child(crown)
	return _put(n, pos, parent)


## Tube sponges: a cluster of open tubes.
func sponge(pos: Vector3, h: float = 1.4, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	var m: StandardMaterial3D = Look.flat(col.darkened(0.3), 0.85, 0.0, 0.3)
	var lip: StandardMaterial3D = Look.flat(col.lightened(0.25), 0.5, 0.0, 1.5)
	for i: int in rng.randi_range(3, 5):
		var hh: float = h * rng.randf_range(0.5, 1.0)
		var off := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35)) * h
		n.add_child(Look.cylinder(0.14 * h, hh, m, off + Vector3(0, hh * 0.5, 0), 0.19 * h, 10))
		var tm := TorusMesh.new()
		tm.inner_radius = 0.14 * h
		tm.outer_radius = 0.2 * h
		tm.rings = 14
		tm.ring_segments = 5
		n.add_child(Look.mesh_node(tm, lip, off + Vector3(0, hh, 0)))
	return _put(n, pos, parent)


## A mixed coral clump for a platform corner or a rock face.
func clump(pos: Vector3, scale: float = 1.0, parent: Node3D = null) -> void:
	var k: int = rng.randi() % 4
	match k:
		0: staghorn(pos, scale, Color(0, 0, 0, 0), parent)
		1: brain(pos, 0.5 * scale, Color(0, 0, 0, 0), parent)
		2: anemone(pos, 0.32 * scale, Color(0, 0, 0, 0), parent)
		3: sponge(pos, 1.0 * scale, Color(0, 0, 0, 0), parent)


# ---- rock and kelp ---------------------------------------------------------------------------

## Lumpy boulder.
func boulder(pos: Vector3, size: float = 1.5, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	var m: StandardMaterial3D = rock_mat(rng.randf_range(0.0, 0.15))
	for i: int in rng.randi_range(2, 4):
		var s := Look.sphere(size * rng.randf_range(0.45, 0.7), m, Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, 0.3), rng.randf_range(-0.4, 0.4)) * size)
		s.scale = Vector3(1.0, rng.randf_range(0.55, 0.85), 1.0)
		n.add_child(s)
	return _put(n, pos, parent)


## A coral-crusted rock pinnacle rising out of the deep to hold up a platform (top at `top`).
func pinnacle(top: Vector3, r: float, length: float = 40.0, parent: Node3D = null) -> void:
	var n := Node3D.new()
	var m: StandardMaterial3D = rock_mat(0.05)
	n.add_child(Look.cylinder(r * 1.6, length, m, Vector3(0, -length * 0.5, 0), r * 0.9, 9))
	for i: int in 3:
		var y: float = -rng.randf_range(1.5, length * 0.4)
		var a: float = rng.randf() * TAU
		var rr: float = lerpf(r * 0.9, r * 1.6, -y / length)
		var s := Look.sphere(r * rng.randf_range(0.5, 0.8), m, Vector3(cos(a) * rr, y, sin(a) * rr))
		n.add_child(s)
		if rng.randf() < 0.8:
			var c: Vector3 = Vector3(cos(a) * (rr + r * 0.4), y + r * 0.3, sin(a) * (rr + r * 0.4))
			clump(top + c, rng.randf_range(0.7, 1.1), null)
	_put(n, top, parent)


func _kelp_material() -> ShaderMaterial:
	if _kelp_mat == null:
		_kelp_mat = ShaderMaterial.new()
		_kelp_mat.shader = KELP_SHADER
	return _kelp_mat


## A forest of swaying kelp ribbons (one MultiMesh) rooted on y=base_y over a rectangle.
func kelp_forest(center: Vector3, extent: Vector2, count: int, h_min: float = 8.0, h_max: float = 18.0, avoid: Array[AABB] = []) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 1.0)
	q.center_offset = Vector3(0, 0.5, 0)
	q.subdivide_depth = 14
	q.material = _kelp_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	var xs: Array[Transform3D] = []
	var tries: int = 0
	while xs.size() < count * 2 and tries < count * 6:
		tries += 1
		var p := center + Vector3(rng.randf_range(-extent.x, extent.x), 0, rng.randf_range(-extent.y, extent.y))
		var blocked: bool = false
		for box: AABB in avoid:
			if box.has_point(Vector3(p.x, box.position.y + box.size.y * 0.5, p.z)):
				blocked = true
				break
		if blocked:
			continue
		var h: float = rng.randf_range(h_min, h_max)
		var yaw: float = rng.randf() * PI
		for k: int in 2:
			var b := Basis(Vector3.UP, yaw + float(k) * PI * 0.5).scaled(Vector3(1.0, h, 1.0))
			xs.append(Transform3D(b, p))
	mm.instance_count = xs.size()
	for i: int in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-extent.x - 8, -2, -extent.y - 8), Vector3(extent.x * 2 + 16, h_max + 8, extent.y * 2 + 16))
	_put(mmi, Vector3.ZERO)
	mmi.global_position = Vector3.ZERO
	# instance transforms are relative to the node at the origin: already world positions


# ---- light and water ----------------------------------------------------------------------------

func _shaft_material() -> ShaderMaterial:
	if _shaft_mat == null:
		_shaft_mat = ShaderMaterial.new()
		_shaft_mat.shader = SHAFT_SHADER
	return _shaft_mat


## A god ray from the surface: an open cone whose top is at `top`, slowly swaying.
func light_shaft(top: Vector3, length: float, r_top: float, r_bottom: float, tilt: Vector3 = Vector3(0.12, 0, 0.06)) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = length
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var holder := Node3D.new()
	holder.rotation = tilt
	holder.set_script(SWAY)
	holder.set("amount", 0.025)
	holder.set("speed", rng.randf_range(0.15, 0.3))
	holder.set("offset", rng.randf() * 10.0)
	var mi := Look.mesh_node(cm, _shaft_material(), Vector3(0, -length * 0.5, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	holder.add_child(mi)
	_put(holder, top)


## The rippling sheet of light far overhead.
func surface(center: Vector3, size: float) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	var mi := Look.mesh_node(pm, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_put(mi, center)
