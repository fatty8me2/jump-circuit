class_name DesertDecor
extends RefCounted
## Scarab Sands set dressing: dunes, pyramids, colossal statues, obelisks, columns, palms,
## oases, braziers, sunbeams, the sun disc and the sandstorm wall. Decoration only (no
## collision); the level composes these around (never on) its route. Materials are shared.

const WALL_SHADER: Shader = preload("res://visual/desert_wall.gdshader")
const DUNE_SHADER: Shader = preload("res://visual/desert_dune.gdshader")
const WATER_SHADER: Shader = preload("res://visual/desert_water.gdshader")
const STORM_SHADER: Shader = preload("res://visual/desert_storm.gdshader")
const BEAM_SHADER: Shader = preload("res://visual/desert_beam.gdshader")
const HAZE_SHADER: Shader = preload("res://visual/desert_haze.gdshader")
const GLYPH_SHADER: Shader = preload("res://visual/desert_glyph.gdshader")
const SWAY: Script = preload("res://visual/reef_sway.gd")
const SPIN: Script = preload("res://visual/spin.gd")
const FLICKER: Script = preload("res://visual/desert_flicker.gd")

const SANDSTONE := Color(0.8, 0.6, 0.38)
const PALE := Color(0.9, 0.76, 0.54)
const GOLD := Color(1.0, 0.72, 0.22)
const TURQUOISE := Color(0.15, 0.8, 0.78)
const LAPIS := Color(0.12, 0.25, 0.7)
const PALM := Color(0.28, 0.5, 0.2)

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


# ---- materials ------------------------------------------------------------------------------

## Carved sandstone (desert_wall.gdshader). Glyph columns between local heights lo..hi (lo > hi = none).
func stone(color: Color = SANDSTONE, lo: float = 1.0, hi: float = -1.0, cell: float = 0.9, block: Vector2 = Vector2(2.2, 1.1)) -> ShaderMaterial:
	var key: String = "w|%s|%.2f|%.2f|%.2f|%s" % [color.to_html(), lo, hi, cell, block]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = WALL_SHADER
	m.set_shader_parameter("stone", color)
	m.set_shader_parameter("glyph_lo", lo)
	m.set_shader_parameter("glyph_hi", hi)
	m.set_shader_parameter("glyph_cell", cell)
	m.set_shader_parameter("block", block)
	_mats[key] = m
	return m


func dune_mat() -> ShaderMaterial:
	if not _mats.has("dune"):
		var m := ShaderMaterial.new()
		m.shader = DUNE_SHADER
		_mats["dune"] = m
	return _mats["dune"]


func glyph_mat(kind: float, color: Color = GOLD, glow: float = 1.2, framed: bool = false) -> ShaderMaterial:
	var key: String = "g|%.2f|%s|%.2f|%s" % [kind, color.to_html(), glow, framed]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = GLYPH_SHADER
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("framed", framed)
	_mats[key] = m
	return m


static func _no_shadow(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---- landscape ------------------------------------------------------------------------------

## A dune: a squashed sphere of rippled sand (its crest `size.y` above `pos`).
func dune(pos: Vector3, size: Vector3, yaw: float = 0.0, spray: bool = false) -> void:
	var d := Look.sphere(1.0, dune_mat())
	d.scale = size
	d.rotation.y = yaw
	_no_shadow(d)
	_put(d, pos)
	if spray:
		DesertFx.crest_spray(root, pos + Vector3(0, size.y * 0.97, 0), maxf(size.x, size.z) * 0.6, 26)


## The endless sand sea far below the course.
func sand_sea(center: Vector3, size: float) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var mi := Look.mesh_node(pm, dune_mat(), center)
	_no_shadow(mi)
	root.add_child(mi)


## A pyramid (four faces of coursed stone and a gilded capstone).
func pyramid(base: Vector3, width: float, height: float, yaw: float = 0.0, color: Color = PALE) -> void:
	var n := Node3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = width * 0.7071
	cm.height = height
	cm.radial_segments = 4
	cm.rings = 1
	var body := Look.mesh_node(cm, stone(color, 1.0, -1.0, 0.9, Vector2(9.0, 4.5)), Vector3(0, height * 0.5, 0))
	body.rotation.y = PI * 0.25
	_no_shadow(body)
	n.add_child(body)
	var cap_h: float = height * 0.07
	var cc := CylinderMesh.new()
	cc.top_radius = 0.0
	cc.bottom_radius = cap_h * 0.7071 * width / height * 1.02
	cc.height = cap_h
	cc.radial_segments = 4
	cc.rings = 1
	var cap := Look.mesh_node(cc, Look.flat(GOLD, 0.25, 0.8, 1.2), Vector3(0, height - cap_h * 0.5 + 0.2, 0))
	cap.rotation.y = PI * 0.25
	n.add_child(cap)
	n.rotation.y = yaw
	_put(n, base)


## An obelisk: a tapering shaft carved with glyphs, a golden pyramidion on top.
func obelisk(base: Vector3, height: float, width: float = 1.6, yaw: float = 0.0) -> void:
	var n := Node3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = width * 0.7071 * 0.7
	cm.bottom_radius = width * 0.7071
	cm.height = height
	cm.radial_segments = 4
	cm.rings = 1
	var shaft := Look.mesh_node(cm, stone(PALE, -height * 0.4, height * 0.42, width * 0.45, Vector2(3.0, 1.5)), Vector3(0, height * 0.5, 0))
	shaft.rotation.y = PI * 0.25
	n.add_child(shaft)
	var pc := CylinderMesh.new()
	pc.top_radius = 0.0
	pc.bottom_radius = width * 0.7071 * 0.7
	pc.height = width * 0.9
	pc.radial_segments = 4
	pc.rings = 1
	var tip := Look.mesh_node(pc, Look.flat(GOLD, 0.25, 0.85, 1.4), Vector3(0, height + width * 0.45, 0))
	tip.rotation.y = PI * 0.25
	n.add_child(tip)
	n.rotation.y = yaw
	_put(n, base)


## A lotus column: drum shaft, glyph band, flared capital. `broken` snaps it off short.
func column(base: Vector3, height: float, radius: float = 0.8, broken: bool = false) -> void:
	var n := Node3D.new()
	var h: float = height * (rng.randf_range(0.45, 0.75) if broken else 1.0)
	n.add_child(Look.cylinder(radius, h, stone(SANDSTONE, h * 0.35, h * 0.8, radius * 0.9, Vector2(3.0, 1.2)), Vector3(0, h * 0.5, 0), radius * 0.92, 14))
	n.add_child(Look.cylinder(radius * 1.2, 0.35, stone(PALE), Vector3(0, 0.17, 0), -1.0, 14))
	if broken:
		var drum := Look.cylinder(radius * 0.95, radius * 1.2, stone(SANDSTONE), Vector3(radius * 1.4, radius * 0.6, rng.randf_range(-1.0, 1.0)), -1.0, 14)
		drum.rotation = Vector3(PI * 0.5, rng.randf() * TAU, 0)
		n.add_child(drum)
	else:
		n.add_child(Look.cylinder(radius * 1.55, radius * 1.1, stone(PALE), Vector3(0, h + radius * 0.55, 0), radius * 0.95, 14))
		n.add_child(Look.box(Vector3(radius * 3.2, radius * 0.5, radius * 3.2), stone(PALE), Vector3(0, h + radius * 1.35, 0)))
		n.add_child(Look.cylinder(radius * 0.98, 0.25, Look.flat(TURQUOISE, 0.4, 0.0, 0.5), Vector3(0, h * 0.28, 0), -1.0, 14))
	_put(n, base)


## A colossal seated pharaoh, sunk to the waist in a dune (far scenery).
func colossus(base: Vector3, s: float, yaw: float = 0.0) -> void:
	var n := Node3D.new()
	var st: ShaderMaterial = stone(SANDSTONE, 1.0, -1.0, 0.9, Vector2(4.0, 2.0))
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.3, 0.8, 0.6)
	var blue: StandardMaterial3D = Look.flat(LAPIS, 0.5, 0.2, 0.2)
	# knees and forearms resting on them, the torso, the shoulders
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(3.2, 3.0, 7.0) * s, st, Vector3(sx * 2.3, 1.5, -2.0) * s))
		n.add_child(Look.box(Vector3(2.0, 1.6, 5.5) * s, st, Vector3(sx * 2.3, 3.6, -1.6) * s))
		n.add_child(Look.box(Vector3(2.2, 5.5, 2.4) * s, st, Vector3(sx * 3.4, 6.2, 1.2) * s))
	n.add_child(Look.box(Vector3(6.4, 9.0, 4.4) * s, st, Vector3(0, 7.5, 1.6) * s))
	n.add_child(Look.box(Vector3(9.2, 2.2, 4.2) * s, st, Vector3(0, 11.5, 1.6) * s))
	_head(n, Vector3(0, 14.6, 1.2) * s, s, st, gold, blue)
	# the throne behind
	n.add_child(Look.box(Vector3(10.0, 16.0, 3.0) * s, stone(PALE, 3.0 * s, 13.0 * s, 1.4 * s), Vector3(0, 8.0, 4.8) * s))
	n.rotation.y = yaw
	_put(n, base)


## A colossal pharaoh head (nemes headdress with gold and lapis stripes, the uraeus).
func _head(parent: Node3D, c: Vector3, s: float, st: Material, gold: Material, blue: Material) -> void:
	# headdress: a flared trapezoid behind and to the sides of the face, striped
	var nm := CylinderMesh.new()
	nm.top_radius = 2.3 * s
	nm.bottom_radius = 4.0 * s
	nm.height = 6.0 * s
	nm.radial_segments = 4
	nm.rings = 1
	var nemes := Look.mesh_node(nm, gold, c + Vector3(0, -0.2, 0.7) * s)
	nemes.rotation.y = PI * 0.25
	nemes.scale = Vector3(1.0, 1.0, 0.6)
	parent.add_child(nemes)
	for i: int in 6:
		var y: float = -2.4 + float(i) * 0.95
		parent.add_child(Look.box(Vector3(5.6 - float(i) * 0.3, 0.35, 3.6) * s, blue, c + Vector3(0, y, 0.75) * s))
	# the face, a nose ridge, dark eyes, the beard and the cobra on the brow
	parent.add_child(Look.box(Vector3(3.2, 4.0, 2.8) * s, st, c + Vector3(0, -0.2, -0.9) * s))
	parent.add_child(Look.box(Vector3(0.5, 1.4, 0.6) * s, st, c + Vector3(0, -0.2, -2.45) * s))
	for sx: float in [-1.0, 1.0]:
		parent.add_child(Look.box(Vector3(0.8, 0.3, 0.2) * s, Look.flat(Color(0.1, 0.08, 0.1), 0.6), c + Vector3(sx * 0.8, 0.6, -2.3) * s))
	parent.add_child(Look.box(Vector3(0.7, 1.8, 0.7) * s, blue, c + Vector3(0, -3.0, -1.8) * s))
	parent.add_child(Look.box(Vector3(0.35, 1.0, 0.35) * s, gold, c + Vector3(0, 2.3, -2.2) * s))


## A colossal head rising out of the sand, like a buried sphinx (far scenery).
func buried_head(base: Vector3, s: float, yaw: float = 0.0) -> void:
	var n := Node3D.new()
	_head(n, Vector3(0, 3.5, 0) * s, s, stone(SANDSTONE, 1.0, -1.0, 0.9, Vector2(3.0, 1.5)), Look.flat(GOLD, 0.3, 0.8, 0.5), Look.flat(LAPIS, 0.5, 0.2, 0.2))
	n.rotation = Vector3(0.12, yaw, 0.08)
	_put(n, base)
	dune(base + Vector3(0, -1.0 * s, 0), Vector3(9.0, 3.0, 8.0) * s, yaw)


## A tall standing statue of a god (straight, arms at sides, a sun crown), on a plinth.
func statue(base: Vector3, s: float, yaw: float = 0.0) -> void:
	var n := Node3D.new()
	var st: ShaderMaterial = stone(SANDSTONE, 1.0, -1.0, 0.9, Vector2(2.0, 1.0))
	n.add_child(Look.box(Vector3(3.0, 1.6, 3.0) * s, stone(PALE, 0.2 * s, 1.4 * s, 0.5 * s), Vector3(0, 0.8, 0) * s))
	n.add_child(Look.box(Vector3(1.8, 5.0, 1.2) * s, st, Vector3(0, 4.1, 0) * s))
	n.add_child(Look.box(Vector3(2.2, 2.6, 1.3) * s, st, Vector3(0, 7.9, 0) * s))
	for sx: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.5, 3.6, 0.6) * s, st, Vector3(sx * 1.35, 7.2, 0) * s))
	n.add_child(Look.box(Vector3(1.1, 1.4, 1.1) * s, st, Vector3(0, 9.9, 0) * s))
	# a falcon-ish beak and the sun disc crown
	n.add_child(Look.box(Vector3(0.35, 0.35, 0.7) * s, st, Vector3(0, 9.8, -0.75) * s))
	var disc := Look.cylinder(0.9 * s, 0.25 * s, Look.flat(GOLD, 0.25, 0.8, 1.6), Vector3(0, 11.6, 0) * s, -1.0, 24)
	disc.rotation.x = PI * 0.5
	n.add_child(disc)
	n.rotation.y = yaw
	_put(n, base)


# ---- life ------------------------------------------------------------------------------------

## A date palm: a gently curved trunk and a crown of swaying fronds.
func palm(base: Vector3, height: float = 6.0, lean: float = 0.15) -> void:
	var n := Node3D.new()
	var bark: StandardMaterial3D = Look.flat(Color(0.5, 0.38, 0.24), 0.9)
	var ring: StandardMaterial3D = Look.flat(Color(0.4, 0.3, 0.2), 0.9)
	var segs: int = 6
	var p := Vector3.ZERO
	var dir := Vector3(0, 1, 0)
	var a: float = rng.randf() * TAU
	var bend := Vector3(cos(a), 0, sin(a)) * lean
	for i: int in segs:
		dir = (dir + bend * 0.35).normalized()
		var l: float = height / float(segs)
		var seg := Look.cylinder(0.2 - 0.015 * float(i), l, bark, p + dir * l * 0.5, 0.18 - 0.015 * float(i), 8)
		var sx: Vector3 = dir.cross(Vector3(0.3, 0.1, 0.9)).normalized()
		seg.basis = Basis(sx, dir, sx.cross(dir)).orthonormalized()
		n.add_child(seg)
		n.add_child(Look.cylinder(0.23 - 0.015 * float(i), 0.08, ring, p + dir * l * 0.95, -1.0, 8))
		p += dir * l
	var crown := Node3D.new()
	crown.position = p
	crown.set_script(SWAY)
	crown.set("amount", 0.05)
	crown.set("speed", rng.randf_range(0.6, 1.0))
	crown.set("offset", rng.randf() * 10.0)
	var leaf: StandardMaterial3D = Look.flat(PALM, 0.8)
	var leaf2: StandardMaterial3D = Look.flat(PALM.lightened(0.15), 0.8)
	var fronds: int = 9
	for i: int in fronds:
		var fa: float = TAU * float(i) / float(fronds) + rng.randf_range(-0.2, 0.2)
		var arm := Node3D.new()
		arm.rotation = Vector3(0, fa, 0)
		var f := Look.box(Vector3(0.55, 0.05, 3.2), leaf if i % 2 == 0 else leaf2, Vector3(0, 0, -1.5))
		var droop := Node3D.new()
		droop.rotation.x = rng.randf_range(0.25, 0.6)
		droop.add_child(f)
		var tip := Look.box(Vector3(0.4, 0.05, 1.6), leaf2, Vector3(0, -0.45, -3.6))
		tip.rotation.x = 0.5
		droop.add_child(tip)
		arm.add_child(droop)
		crown.add_child(arm)
	for i: int in 3:
		var da: float = TAU * float(i) / 3.0
		crown.add_child(Look.sphere(0.22, Look.flat(Color(0.75, 0.42, 0.12), 0.6), Vector3(cos(da) * 0.35, -0.35, sin(da) * 0.35)))
	n.add_child(crown)
	_put(n, base)


## An oasis pool: turquoise water ringed by sand, reeds and lotus pads, dragonflies, glints.
func oasis(center: Vector3, radius: float, palms: int = 3) -> void:
	var water := CylinderMesh.new()
	water.top_radius = radius
	water.bottom_radius = radius * 0.8
	water.height = 0.3
	water.radial_segments = 32
	water.rings = 1
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	wm.set_shader_parameter("radius", radius)
	var w := Look.mesh_node(water, wm, center + Vector3(0, -0.15, 0))
	_no_shadow(w)
	root.add_child(w)
	var rim := Look.cylinder(radius + 0.8, 0.7, Look.flat(Color(0.93, 0.78, 0.52), 0.95), center + Vector3(0, -0.5, 0), radius + 1.6, 32)
	root.add_child(rim)
	var reed: StandardMaterial3D = Look.flat(Color(0.35, 0.55, 0.22), 0.8)
	for i: int in 14:
		var a: float = rng.randf() * TAU
		var r: float = radius * rng.randf_range(0.85, 1.05)
		var h: float = rng.randf_range(0.8, 1.6)
		var rd := Look.cylinder(0.03, h, reed, center + Vector3(cos(a) * r, h * 0.5 - 0.1, sin(a) * r), 0.015, 5)
		rd.rotation = Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		root.add_child(rd)
	var pad: StandardMaterial3D = Look.flat(Color(0.3, 0.6, 0.3), 0.7)
	var bloom: StandardMaterial3D = Look.flat(Color(1.0, 0.75, 0.9), 0.5, 0.0, 0.5)
	for i: int in 5:
		var a2: float = rng.randf() * TAU
		var r2: float = radius * rng.randf_range(0.3, 0.75)
		var pp: Vector3 = center + Vector3(cos(a2) * r2, 0.02, sin(a2) * r2)
		root.add_child(Look.cylinder(0.35, 0.02, pad, pp, -1.0, 10))
		if i % 2 == 0:
			root.add_child(Look.sphere(0.12, bloom, pp + Vector3(0, 0.08, 0)))
	for i: int in palms:
		var a3: float = TAU * float(i) / float(maxi(palms, 1)) + rng.randf_range(-0.4, 0.4)
		palm(center + Vector3(cos(a3), 0, sin(a3)) * (radius + 0.6) + Vector3(0, -0.2, 0), rng.randf_range(5.0, 7.5), rng.randf_range(0.1, 0.25))
	DesertFx.dragonflies(root, center + Vector3(0, 0.8, 0), Vector3(radius, 0.5, radius), 6)
	DesertFx.rising_glints(root, center, radius * 0.8, 3.0, DesertFx.TURQUOISE, 14)


## A bronze brazier on a stand, burning, with a flickering light.
func brazier(base: Vector3, height: float = 1.6, light: bool = true, scale: float = 1.0) -> void:
	var n := Node3D.new()
	var bronze: StandardMaterial3D = Look.flat(Color(0.7, 0.45, 0.2), 0.35, 0.8)
	n.add_child(Look.cylinder(0.12 * scale, height, bronze, Vector3(0, height * 0.5, 0), 0.08 * scale, 8))
	n.add_child(Look.cylinder(0.4 * scale, 0.1, bronze, Vector3(0, 0.05, 0), -1.0, 10))
	n.add_child(Look.cylinder(0.3 * scale, 0.35 * scale, bronze, Vector3(0, height + 0.12 * scale, 0), 0.5 * scale, 12))
	n.add_child(Look.cylinder(0.42 * scale, 0.06, Look.flat(Color(1.0, 0.55, 0.15), 0.4, 0.0, 3.0), Vector3(0, height + 0.3 * scale, 0), -1.0, 12))
	_put(n, base)
	DesertFx.fire(n, Vector3(0, height + 0.35 * scale, 0), scale * 1.2)
	if light:
		var l := OmniLight3D.new()
		l.set_script(FLICKER)
		l.light_color = Color(1.0, 0.62, 0.3)
		l.set("base_energy", 1.8)
		l.omni_range = 7.0 * scale
		l.shadow_enabled = false
		l.position = Vector3(0, height + 0.8 * scale, 0)
		n.add_child(l)


## A dusty sunbeam slanting down from `top` along `dir`.
func beam(top: Vector3, dir: Vector3, length: float, r_top: float, r_bottom: float, intensity: float = 0.16) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = length
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var key: String = "beam|%.2f" % intensity
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = BEAM_SHADER
		m.set_shader_parameter("intensity", intensity)
		_mats[key] = m
	var mi := Look.mesh_node(cm, _mats[key])
	_no_shadow(mi)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var down: Vector3 = dir.normalized()
	var x: Vector3 = down.cross(Vector3(0.31, 0.2, 0.93)).normalized()
	# the mesh's +Y is its top: point it back up the beam
	mi.basis = Basis(x, -down, x.cross(-down)).orthonormalized()
	mi.position = top + down * length * 0.5
	root.add_child(mi)


## The great sun disc: a gilded disc ringed with rays, turning slowly, blazing with light.
func sun_disc(center: Vector3, radius: float, yaw: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.rotation.y = yaw
	var spin := Node3D.new()
	spin.set_script(SPIN)
	spin.set("period", 40.0)
	spin.set("axis", Vector3(0, 0, 1))
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.2, 0.9, 1.8)
	var hot: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.5), 0.2, 0.3, 4.0)
	var disc := Look.cylinder(radius, 0.8, gold, Vector3.ZERO, -1.0, 48)
	disc.rotation.x = PI * 0.5
	spin.add_child(disc)
	var face := Look.cylinder(radius * 0.72, 0.9, hot, Vector3.ZERO, -1.0, 48)
	face.rotation.x = PI * 0.5
	spin.add_child(face)
	var rays: int = 16
	for i: int in rays:
		var a: float = TAU * float(i) / float(rays)
		var len: float = radius * (0.7 if i % 2 == 0 else 0.45)
		var r := Look.box(Vector3(radius * 0.12, len, 0.5), gold, Vector3(cos(a), sin(a), 0) * (radius + len * 0.5 + 0.2))
		r.rotation.z = a - PI * 0.5
		spin.add_child(r)
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 1.02
	ring.outer_radius = radius * 1.1
	ring.rings = 48
	ring.ring_segments = 8
	var rm := Look.mesh_node(ring, Look.flat(TURQUOISE, 0.3, 0.2, 2.0))
	rm.rotation.x = PI * 0.5
	spin.add_child(rm)
	holder.add_child(spin)
	var halo: MeshInstance3D = Fx.sprite(Color(1.0, 0.75, 0.35, 0.55), radius * 5.0, Fx.Tex.DOT)
	holder.add_child(halo)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.45)
	l.light_energy = 3.0
	l.omni_range = radius * 7.0
	l.position = Vector3(0, 0, -radius * 0.6)
	holder.add_child(l)
	_put(holder, center)
	DesertFx.rising_glints(root, center + Vector3(0, -radius, 0), radius * 0.9, radius * 2.2, DesertFx.GOLD, 40)
	return holder


## The sandstorm wall on the horizon: an open cylinder round the course, storm on one arc.
func storm_wall(center: Vector3, radius: float, height: float, arc_center: float, arc_width: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 64
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = STORM_SHADER
	m.set_shader_parameter("arc_center", arc_center)
	m.set_shader_parameter("arc_width", arc_width)
	var mi := Look.mesh_node(cm, m, center + Vector3(0, height * 0.5 - 20.0, 0))
	_no_shadow(mi)
	mi.extra_cull_margin = 50.0
	root.add_child(mi)


## A patch of heat shimmer over hot sand (a billboarded refraction quad).
func haze(pos: Vector3, width: float, height: float, strength: float = 0.004) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.center_offset = Vector3(0, 0.5, 0)
	var key: String = "haze|%.4f" % strength
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = HAZE_SHADER
		m.set_shader_parameter("strength", strength)
		_mats[key] = m
	var mi := Look.mesh_node(q, _mats[key], pos)
	mi.scale = Vector3(width, height, 1.0)
	mi.extra_cull_margin = maxf(width, height)
	_no_shadow(mi)
	root.add_child(mi)


## A glowing hieroglyph decal (a flat quad) facing along `normal`.
func glyph(pos: Vector3, normal: Vector3, size: float, kind: float, color: Color = GOLD, glow: float = 1.2, framed: bool = false) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := Look.mesh_node(q, glyph_mat(kind, color, glow, framed))
	var z: Vector3 = normal.normalized()
	var up: Vector3 = Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3(0, 0, -1)
	var x: Vector3 = up.cross(z).normalized()
	mi.basis = Basis(x, z.cross(x), z)
	mi.position = pos + z * 0.02
	_no_shadow(mi)
	root.add_child(mi)
	return mi


## Tumbled blocks of fallen masonry round a point (decor).
func rubble(center: Vector3, spread: float, count: int = 5) -> void:
	for i: int in count:
		var s := Vector3(rng.randf_range(0.6, 1.6), rng.randf_range(0.4, 1.0), rng.randf_range(0.6, 1.4))
		var b := Look.box(s, stone(SANDSTONE, 1.0, -1.0, 0.9, Vector2(1.6, 0.8)), center + Vector3(rng.randf_range(-spread, spread), s.y * 0.4, rng.randf_range(-spread, spread)))
		b.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		root.add_child(b)
