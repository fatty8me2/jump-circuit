class_name XenoFlora
extends RefCounted
## Xeno Wilds set dressing: bioluminescent alien flora and geology - glowing mushrooms (from
## knee-high to mountain-sized), crystal clusters, swaying tentacle vines, fractal fern trees, spore
## pods, fields of glowing reeds, the bones of something enormous, fungal stalks and floating rock
## keels with dangling luminous roots, rock arches. Decoration only (no collision): the level
## composes these around (never on) its route.

const SWAY: Script = preload("res://visual/reef_sway.gd")
const SPIN: Script = preload("res://visual/spin.gd")

const MAGENTA := Color(1.0, 0.35, 0.85)
const TEAL := Color(0.3, 1.0, 0.88)
const LIME := Color(0.75, 1.0, 0.3)
const VIOLET := Color(0.66, 0.42, 1.0)
const AMBER := Color(1.0, 0.66, 0.28)
const CYAN := Color(0.4, 0.85, 1.0)
const GLOWS: Array[Color] = [MAGENTA, TEAL, LIME, VIOLET, CYAN]

var root: Node3D
var rng: RandomNumberGenerator


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
	return Look.flat(Look.c("side").darkened(0.2 + shade), 0.95)


static func _no_shadow(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---- fungi ---------------------------------------------------------------------------------

## A glowing mushroom: pale stalk, domed cap with light spots, luminous gills. `h` = stalk height.
func mushroom(pos: Vector3, h: float, cap_r: float, color: Color = Color(0, 0, 0, 0), lean: float = -1.0, parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	var stem: StandardMaterial3D = Look.flat(Color(0.78, 0.72, 0.9), 0.85)
	var cap: StandardMaterial3D = Look.flat(col.darkened(0.45), 0.5, 0.0, 0.35)
	var gill: StandardMaterial3D = Look.flat(col.lightened(0.2), 0.4, 0.0, 2.2)
	var spot: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.85), 0.3, 0.0, 1.8)
	var sr: float = maxf(cap_r * 0.16, 0.06)
	n.add_child(Look.cylinder(sr * 1.3, h, stem, Vector3(0, h * 0.5, 0), sr * 0.8, 10))
	var dome := Look.sphere(cap_r, cap, Vector3(0, h, 0))
	dome.scale = Vector3(1.0, 0.5, 1.0)
	n.add_child(dome)
	n.add_child(_no_shadow(Look.cylinder(cap_r * 0.96, maxf(cap_r * 0.06, 0.05), gill, Vector3(0, h - 0.02, 0), cap_r * 0.3, 20)))
	# light spots only where they read: none on the knee-high ones, a ring on the giants
	var spots: int = 0 if cap_r < 0.5 else (3 if cap_r < 3.0 else 6)
	for i: int in spots:
		var a: float = TAU * float(i) / float(spots) + rng.randf() * 0.4
		var e: float = rng.randf_range(0.3, 0.9)
		var sp := Look.sphere(cap_r * 0.08, spot, Vector3(cos(e) * cos(a) * cap_r * 0.97, h + sin(e) * cap_r * 0.5 * 0.97, cos(e) * sin(a) * cap_r * 0.97))
		sp.scale = Vector3(1.0, 0.5, 1.0)
		n.add_child(_no_shadow(sp))
	var tilt: float = lean if lean >= 0.0 else rng.randf_range(0.0, 0.12)
	n.rotation = Vector3(tilt * cos(rng.randf() * TAU), rng.randf() * TAU, tilt * sin(rng.randf() * TAU))
	return _put(n, pos, parent)


## A small cluster of little glowing mushrooms (ground cover).
func shroom_patch(pos: Vector3, scale: float = 1.0, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> void:
	var col: Color = color if color.a > 0.0 else glow_color()
	for i: int in rng.randi_range(2, 4):
		var off := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5)) * scale
		mushroom(pos + off, rng.randf_range(0.25, 0.6) * scale, rng.randf_range(0.18, 0.34) * scale, col, 0.2, parent)


# ---- crystals ------------------------------------------------------------------------------

## A cluster of glowing hexagonal crystal shards fanning out of a rock.
func crystals(pos: Vector3, scale: float = 1.0, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	var body: StandardMaterial3D = Look.flat(Color(col.r, col.g, col.b, 0.85).lightened(0.1), 0.1, 0.2, 1.4)
	var core: StandardMaterial3D = Look.flat(col.lightened(0.5), 0.2, 0.0, 3.0)
	n.add_child(Look.sphere(0.5 * scale, rock_mat(0.1)))
	for i: int in rng.randi_range(4, 7):
		var a: float = rng.randf() * TAU
		var tl: float = rng.randf_range(0.15, 0.7)
		var h: float = rng.randf_range(0.9, 2.4) * scale
		var r: float = rng.randf_range(0.12, 0.26) * scale
		var arm := Node3D.new()
		arm.rotation = Vector3(cos(a) * tl, 0, sin(a) * tl)
		arm.add_child(Look.cylinder(r, h, body, Vector3(0, h * 0.5, 0), r, 6))
		arm.add_child(Look.cylinder(r, r * 2.2, core if i % 2 == 0 else body, Vector3(0, h + r * 1.1, 0), 0.0, 6))
		n.add_child(arm)
	n.rotation.y = rng.randf() * TAU
	return _put(n, pos, parent)


## A lone tall crystal spire (far scenery): a hexagonal column with a pointed tip and a glowing seam.
func spire(pos: Vector3, h: float, r: float, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	var body: StandardMaterial3D = Look.flat(col.darkened(0.55), 0.15, 0.4, 0.5)
	var seam: StandardMaterial3D = Look.flat(col, 0.3, 0.0, 2.4)
	n.add_child(Look.cylinder(r, h, body, Vector3(0, h * 0.5, 0), r * 0.75, 6))
	n.add_child(Look.cylinder(r * 0.75, r * 2.5, body, Vector3(0, h + r * 1.25, 0), 0.0, 6))
	n.add_child(_no_shadow(Look.cylinder(r * 0.78, h * 0.02 + 0.2, seam, Vector3(0, h * 0.82, 0), -1.0, 6)))
	n.add_child(_no_shadow(Look.cylinder(r * 0.9, h * 0.015 + 0.2, seam, Vector3(0, h * 0.4, 0), -1.0, 6)))
	n.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
	return _put(n, pos, parent)


# ---- swaying things ------------------------------------------------------------------------

## A tentacle vine: a curling chain of segments rising from the ground, swaying, glowing tip.
func tendril(pos: Vector3, h: float = 3.0, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var skin: StandardMaterial3D = Look.flat(Color(0.22, 0.14, 0.3), 0.6)
	var ring: StandardMaterial3D = Look.flat(col, 0.3, 0.0, 2.0)
	var base := Node3D.new()
	var node: Node3D = base
	var segs: int = 4
	var sl: float = h / float(segs)
	for i: int in segs:
		var f: float = float(i) / float(segs)
		var seg := Node3D.new()
		seg.position = Vector3(0, 0 if i == 0 else sl, 0)
		seg.set_script(SWAY)
		seg.set("amount", 0.12 + 0.06 * f)
		seg.set("speed", 0.7 + 0.2 * f + rng.randf() * 0.2)
		seg.set("offset", rng.randf() * TAU)
		var r0: float = h * 0.07 * (1.0 - f * 0.7)
		seg.add_child(Look.cylinder(r0, sl, skin, Vector3(0, sl * 0.5, 0), r0 * 0.8, 8))
		seg.add_child(_no_shadow(Look.cylinder(r0 * 1.08, sl * 0.08, ring, Vector3(0, sl * 0.6, 0), -1.0, 8)))
		node.add_child(seg)
		node = seg
	node.add_child(_no_shadow(Look.sphere(h * 0.045, ring, Vector3(0, sl, 0))))
	base.rotation.y = rng.randf() * TAU
	return _put(base, pos, parent)


## A fractal fern tree: a slim trunk with tiers of drooping glowing fronds.
func fern(pos: Vector3, h: float = 4.0, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	var trunk: StandardMaterial3D = Look.flat(Color(0.3, 0.2, 0.36), 0.8)
	var frond: StandardMaterial3D = Look.flat(col.darkened(0.3), 0.6, 0.0, 0.6)
	var rib: StandardMaterial3D = Look.flat(col.lightened(0.2), 0.4, 0.0, 1.8)
	n.add_child(Look.cylinder(h * 0.035, h, trunk, Vector3(0, h * 0.5, 0), h * 0.02, 6))
	for tier: int in 3:
		var y: float = h * (0.55 + 0.2 * float(tier))
		var len: float = h * (0.45 - 0.1 * float(tier))
		var count: int = 5 - tier
		for i: int in count:
			var a: float = TAU * float(i) / float(count) + float(tier) * 0.6
			var arm := Node3D.new()
			arm.position = Vector3(0, y, 0)
			arm.rotation = Vector3(0, a, 0)
			var tilt := Node3D.new()
			tilt.rotation.z = -0.9 + 0.2 * float(tier)
			var leaf := Look.box(Vector3(len, 0.04, len * 0.22), frond, Vector3(len * 0.5, 0, 0))
			tilt.add_child(leaf)
			tilt.add_child(_no_shadow(Look.box(Vector3(len, 0.06, 0.05), rib, Vector3(len * 0.5, 0.03, 0))))
			arm.add_child(tilt)
			n.add_child(arm)
	n.add_child(_no_shadow(Look.sphere(h * 0.05, rib, Vector3(0, h, 0))))
	n.rotation.y = rng.randf() * TAU
	return _put(n, pos, parent)


## A clutch of bulbous translucent spore pods with glowing cores.
func pods(pos: Vector3, scale: float = 1.0, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> Node3D:
	var col: Color = color if color.a > 0.0 else glow_color()
	var n := Node3D.new()
	var skin: StandardMaterial3D = Look.flat(Color(col.r, col.g, col.b, 0.55), 0.2, 0.0, 0.8)
	var core: StandardMaterial3D = Look.flat(col.lightened(0.4), 0.3, 0.0, 3.0)
	for i: int in rng.randi_range(3, 5):
		var r: float = rng.randf_range(0.3, 0.6) * scale
		var p := Vector3(rng.randf_range(-0.6, 0.6), r * 0.8, rng.randf_range(-0.6, 0.6)) * Vector3(scale, 1.0, scale)
		var pod := Look.sphere(r, skin, p)
		pod.scale = Vector3(1.0, 1.35, 1.0)
		n.add_child(_no_shadow(pod))
		n.add_child(_no_shadow(Look.sphere(r * 0.35, core, p)))
	return _put(n, pos, parent)


## A field of glowing reeds: one MultiMesh of thin stems with lit tips (one draw call).
func reeds(center: Vector3, extent: Vector2, count: int, h: float = 1.6, color: Color = Color(0, 0, 0, 0), parent: Node3D = null) -> void:
	var col: Color = color if color.a > 0.0 else glow_color()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.045
	cm.height = 1.0
	cm.radial_segments = 4
	cm.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = count
	for i: int in count:
		var hh: float = h * rng.randf_range(0.6, 1.3)
		var b := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25)).scaled(Vector3(1.0, hh, 1.0))
		var p := Vector3(rng.randf_range(-extent.x, extent.x), hh * 0.5, rng.randf_range(-extent.y, extent.y))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col.darkened(0.4)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.3
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_put(mmi, center, parent)


# ---- rock, bone and island ---------------------------------------------------------------

## A tapering fungal stalk / rock column hanging from under a platform down toward the jungle floor.
func stalk(top: Vector3, r: float, length: float = 34.0, parent: Node3D = null) -> void:
	var n := Node3D.new()
	var mat: StandardMaterial3D = rock_mat(rng.randf_range(0.0, 0.15))
	n.add_child(Look.cylinder(r * 0.55, length, mat, Vector3(0, -length * 0.5, 0), r, 7))
	# a couple of glowing root strands wrapping it
	var root_mat: StandardMaterial3D = Look.flat(glow_color(), 0.4, 0.0, 1.6)
	for i: int in 2:
		var a: float = rng.randf() * TAU
		var strand := Look.cylinder(0.05 + r * 0.03, length * 0.35, root_mat, Vector3(cos(a) * r * 0.9, -length * 0.2 - float(i) * 3.0, sin(a) * r * 0.9), 0.02, 4)
		strand.rotation = Vector3(sin(a) * 0.08, 0, -cos(a) * 0.08)
		n.add_child(_no_shadow(strand))
	_put(n, top, parent)


## Hanging roots under a floating block: a few glowing strands of different lengths.
func roots(top: Vector3, spread: float, count: int = 5, parent: Node3D = null) -> void:
	var col: Color = glow_color()
	var mat: StandardMaterial3D = Look.flat(Color(0.3, 0.22, 0.34), 0.8)
	var tip: StandardMaterial3D = Look.flat(col, 0.3, 0.0, 2.4)
	for i: int in count:
		var p := top + Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		var hl: float = rng.randf_range(1.5, 5.0)
		var holder := Node3D.new()
		holder.set_script(SWAY)
		holder.set("amount", 0.06)
		holder.set("speed", 0.6 + rng.randf() * 0.4)
		holder.set("offset", rng.randf() * TAU)
		holder.add_child(_no_shadow(Look.cylinder(0.05, hl, mat, Vector3(0, -hl * 0.5, 0), 0.02, 4)))
		holder.add_child(_no_shadow(Look.sphere(0.07, tip, Vector3(0, -hl, 0))))
		_put(holder, p, parent)


## A great curved rib (a bone of something enormous): a chain of cylinders along an arc.
## `a` and `b` are the two feet, `h` the height of the arc above them.
func rib(a: Vector3, b: Vector3, h: float, r: float, parent: Node3D = null) -> void:
	var bone: StandardMaterial3D = Look.flat(Color(0.86, 0.82, 0.72), 0.7)
	var segs: int = 10
	var prev: Vector3 = a
	for i: int in range(1, segs + 1):
		var f: float = float(i) / float(segs)
		var p: Vector3 = a.lerp(b, f) + Vector3.UP * h * sin(PI * f)
		var d: Vector3 = p - prev
		var rr: float = r * (1.0 - 0.35 * sin(PI * f))
		var seg := Look.cylinder(rr, d.length() + rr * 0.6, bone, (p + prev) * 0.5, rr, 8)
		var up: Vector3 = d.normalized()
		var side: Vector3 = up.cross(Vector3(0.3, 0.1, 0.95)).normalized()
		seg.basis = Basis(side, up, side.cross(up))
		if parent != null:
			parent.add_child(seg)
		else:
			root.add_child(seg)
		prev = p


## A floating island: a rock keel tapering down, a mossy top, dangling glowing roots, a mushroom or
## crystal crown, and a glowing waterfall that falls UP off its lip and dissolves into motes.
func island(center: Vector3, r: float, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	var col: Color = glow_color()
	var rock: StandardMaterial3D = rock_mat(0.05)
	var moss: StandardMaterial3D = Look.flat(Look.c("top").darkened(0.25), 0.9)
	var top := Look.cylinder(r, r * 0.35, moss, Vector3(0, -r * 0.17, 0), r * 0.92, 10)
	n.add_child(top)
	var keel := Look.cylinder(r * 0.9, r * 1.6, rock, Vector3(0, -r * 0.35 - r * 0.8, 0), r * 0.12, 9)
	n.add_child(keel)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0 + rng.randf()
		var lump := Look.sphere(r * 0.4, rock, Vector3(cos(a) * r * 0.55, -r * 0.6, sin(a) * r * 0.55))
		lump.scale = Vector3(1.0, 1.4, 1.0)
		n.add_child(lump)
	var rs: float = r * 0.35
	for i: int in 5:
		var p := Vector3(rng.randf_range(-rs, rs), -r * 1.4, rng.randf_range(-rs, rs))
		var hl: float = rng.randf_range(r * 0.8, r * 2.2)
		n.add_child(_no_shadow(Look.cylinder(r * 0.03, hl, Look.flat(Color(0.3, 0.22, 0.34), 0.8), p + Vector3(0, -hl * 0.5, 0), r * 0.01, 4)))
		n.add_child(_no_shadow(Look.sphere(r * 0.05, Look.flat(col, 0.3, 0.0, 2.4), p + Vector3(0, -hl, 0))))
	if rng.randf() < 0.55:
		mushroom(Vector3(rng.randf_range(-r, r) * 0.3, 0, rng.randf_range(-r, r) * 0.3), r * rng.randf_range(0.6, 1.1), r * rng.randf_range(0.35, 0.6), col, 0.1, n)
	else:
		crystals(Vector3(0, 0, 0), r * 0.35, col, n)
	# the up-fall: glowing liquid spilling off the lip and streaming UP into the sky
	var a2: float = rng.randf() * TAU
	var lip := Vector3(cos(a2), 0, sin(a2)) * r * 0.95
	var fall: GPUParticles3D = Fx.emitter({"amount": int(clampf(r * 6.0, 16, 70)), "lifetime": 3.5, "shape": "box",
		"extents": Vector3(r * 0.15, 0.1, r * 0.15), "dir": Vector3.UP, "spread": 6.0, "speed": Vector2(1.2, 2.4),
		"gravity": Vector3(0, 0.8, 0), "tex": Fx.Tex.DOT, "size": clampf(r * 0.08, 0.2, 0.8), "curve": "shrink",
		"color": Fx.hot(col, 1.8), "fade": PackedFloat32Array([0.0, 1.0, 0.7, 0.0]),
		"aabb": AABB(Vector3(-r * 2.0, -r * 2.0, -r * 2.0), Vector3(r * 4.0, r * 8.0 + 20.0, r * 4.0)), "preprocess": 3.5, "local": true})
	fall.position = lip + Vector3(0, -r * 0.2, 0)
	n.add_child(fall)
	n.rotation.y = rng.randf() * TAU
	return _put(n, center, parent)


## A great natural rock arch between two feet, `h` high at the crown (far scenery).
func arch(a: Vector3, b: Vector3, h: float, thick: float, parent: Node3D = null) -> void:
	var mat: StandardMaterial3D = rock_mat(0.1)
	var vein: StandardMaterial3D = Look.flat(glow_color(), 0.4, 0.0, 1.6)
	var segs: int = 12
	var prev: Vector3 = a
	for i: int in range(1, segs + 1):
		var f: float = float(i) / float(segs)
		var p: Vector3 = a.lerp(b, f) + Vector3.UP * h * sin(PI * f)
		var d: Vector3 = p - prev
		var th: float = thick * (1.2 - 0.5 * sin(PI * f))
		var seg := Look.box(Vector3(th, d.length() + th * 0.5, th * 0.8), mat, (p + prev) * 0.5)
		var up: Vector3 = d.normalized()
		var side: Vector3 = up.cross(Vector3(0.0, 0.0, 1.0) if absf(up.z) < 0.9 else Vector3(1.0, 0.0, 0.0)).normalized()
		seg.basis = Basis(side, up, side.cross(up))
		(parent if parent != null else root).add_child(seg)
		if i % 3 == 0:
			var v := Look.box(Vector3(th * 1.02, th * 0.12, th * 0.82), vein, (p + prev) * 0.5)
			v.basis = seg.basis
			(parent if parent != null else root).add_child(_no_shadow(v))
		prev = p
