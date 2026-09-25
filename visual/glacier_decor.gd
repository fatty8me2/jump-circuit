class_name GlacierDecor
extends RefCounted
## Frostbite Pass set dressing: seracs and ice columns, snowy boulders, crystal clusters,
## snow-laden pines, warm lanterns, cairns, prayer-flag lines, overhangs dripping icicles.
## Decoration only (no collision). The level composes these around (never on) its route.

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, random: RandomNumberGenerator) -> void:
	root = level_root
	rng = random


func _put(n: Node3D, pos: Vector3, parent: Node3D = null) -> Node3D:
	n.position = pos
	(parent if parent != null else root).add_child(n)
	return n


static func _no_shadow(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A column of glacier ice / rock under a floating block, reaching down into the valley haze.
## `top` is where it meets the block's underside.
func serac(top: Vector3, r: float, h: float) -> void:
	var n := Node3D.new()
	var body: StandardMaterial3D = Look.flat(Color(0.3, 0.46, 0.66), 0.35, 0.05, 0.12)
	var dark: StandardMaterial3D = Look.flat(Color(0.2, 0.28, 0.4), 0.8)
	var seg: int = 7
	n.add_child(Look.cylinder(r * 1.25, h, body, Vector3(0, -h * 0.5, 0), r, seg))
	# a band of dark rock where the ice meets the old moraine, and a wider foot far below
	n.add_child(Look.cylinder(r * 1.5, h * 0.35, dark, Vector3(0, -h * 0.82, 0), r * 1.22, seg))
	# rime crust just under the block
	n.add_child(Look.cylinder(r * 1.08, 0.5, Look.flat(GlacierFx.SNOW, 0.9), Vector3(0, -0.25, 0), r * 1.02, seg))
	n.rotation.y = rng.randf() * TAU
	_put(n, top)


## Snow-capped boulder (decor).
func boulder(pos: Vector3, s: float = 1.0) -> void:
	var n := Node3D.new()
	var rock := Look.sphere(1.0, GlacierFx.rock_mat(rng.randf_range(0.0, 0.2)))
	rock.scale = Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.6, 0.8), rng.randf_range(0.9, 1.2)) * s
	n.add_child(rock)
	var cap := Look.sphere(1.0, GlacierFx.snow_mat(), Vector3(0, 0.42 * s, 0))
	cap.scale = Vector3(rock.scale.x * 0.92, 0.35 * s, rock.scale.z * 0.92)
	n.add_child(cap)
	n.rotation.y = rng.randf() * TAU
	_put(n, pos)


## A cluster of glowing ice crystals (hexagonal prisms) fanning out of the snow.
func crystals(pos: Vector3, s: float = 1.0, tint: Color = GlacierFx.GLOW) -> Node3D:
	var n := Node3D.new()
	var m: StandardMaterial3D = GlacierFx.ice_mat(tint, 1.1, 0.85)
	for i: int in rng.randi_range(4, 6):
		var h: float = rng.randf_range(0.8, 2.0) * s
		var c := Node3D.new()
		c.add_child(Look.cylinder(0.16 * s, h, m, Vector3(0, h * 0.5, 0), 0.16 * s, 6))
		c.add_child(Look.cylinder(0.16 * s, 0.35 * s, m, Vector3(0, h + 0.17 * s, 0), 0.0, 6))
		var a: float = rng.randf() * TAU
		var tiltv: float = rng.randf_range(0.0, 0.55) if i > 0 else 0.05
		c.rotation = Vector3(cos(a) * tiltv, rng.randf() * TAU, sin(a) * tiltv)
		n.add_child(c)
	return _put(n, pos)


## Snow-laden pine (decor).
func pine(pos: Vector3, s: float = 1.0) -> void:
	var t := Node3D.new()
	var trunk_h: float = 1.4 * s
	t.add_child(Look.cylinder(0.18 * s, trunk_h, Look.flat(Color(0.28, 0.2, 0.17), 0.9), Vector3(0, trunk_h * 0.5, 0), 0.12 * s, 7))
	var needle: StandardMaterial3D = Look.flat(Color(0.12, 0.26, 0.24), 0.9)
	var snow: StandardMaterial3D = GlacierFx.snow_mat()
	for i: int in 4:
		var r: float = (1.4 - float(i) * 0.3) * s
		var h: float = 1.3 * s
		var y: float = trunk_h + float(i) * 0.8 * s + h * 0.35
		t.add_child(Look.cylinder(r, h, needle, Vector3(0, y, 0), 0.0, 8))
		t.add_child(Look.cylinder(r * 0.85, h * 0.4, snow, Vector3(0, y + h * 0.18, 0), 0.0, 8))
	t.rotation.y = rng.randf() * TAU
	_put(t, pos)


## A warm lantern on a post: the one warm colour in the cold, lighting the way.
func lantern(pos: Vector3, h: float = 2.4, light: bool = true) -> void:
	var l := Node3D.new()
	l.add_child(Look.cylinder(0.07, h, Look.flat(Color(0.2, 0.18, 0.2), 0.6, 0.5), Vector3(0, h * 0.5, 0), 0.05, 6))
	l.add_child(Look.box(Vector3(0.34, 0.4, 0.34), Look.flat(GlacierFx.WARM, 0.3, 0.0, 3.2), Vector3(0, h + 0.1, 0)))
	l.add_child(Look.box(Vector3(0.44, 0.08, 0.44), Look.flat(Color(0.2, 0.18, 0.2), 0.6, 0.5), Vector3(0, h + 0.34, 0)))
	l.add_child(Look.box(Vector3(0.4, 0.14, 0.4), GlacierFx.snow_mat(), Vector3(0, h + 0.44, 0)))
	if light:
		var o := OmniLight3D.new()
		o.light_color = GlacierFx.WARM
		o.light_energy = 1.8
		o.omni_range = 7.0
		o.position = Vector3(0, h + 0.1, 0)
		l.add_child(o)
	_put(l, pos)


## A stacked-stone cairn with a snow cap.
func cairn(pos: Vector3, s: float = 1.0) -> void:
	var n := Node3D.new()
	var y: float = 0.0
	for i: int in 4:
		var r: float = (0.5 - float(i) * 0.09) * s
		var st := Look.sphere(1.0, GlacierFx.rock_mat(0.1 * float(i % 2)), Vector3(rng.randf_range(-0.05, 0.05), y + r * 0.5, 0))
		st.scale = Vector3(r, r * 0.55, r * 0.9)
		n.add_child(st)
		y += r * 0.9
	var cap := Look.sphere(1.0, GlacierFx.snow_mat(), Vector3(0, y + 0.05, 0))
	cap.scale = Vector3(0.22, 0.12, 0.2) * s
	n.add_child(cap)
	_put(n, pos)


## A line of prayer flags strung between two points, sagging a little.
func flags(a: Vector3, b: Vector3, count: int = 9) -> void:
	var cols: Array[Color] = [Color(0.25, 0.45, 1.0), Color(0.95, 0.95, 0.95), Color(1.0, 0.3, 0.3), Color(0.3, 0.85, 0.4), Color(1.0, 0.85, 0.2)]
	var n := Node3D.new()
	var d: Vector3 = b - a
	var yaw: float = atan2(-d.x, -d.z)
	for i: int in count:
		var f: float = (float(i) + 0.5) / float(count)
		var p: Vector3 = a + d * f + Vector3(0, -sin(f * PI) * d.length() * 0.06, 0)
		var m: StandardMaterial3D = Look.flat(cols[i % cols.size()], 0.8, 0.0, 0.25)
		var fl := Look.box(Vector3(0.36, 0.44, 0.02), m, p - Vector3(0, 0.24, 0))
		fl.rotation.y = yaw + PI * 0.5
		fl.rotation.z = rng.randf_range(-0.2, 0.2)
		n.add_child(fl)
	root.add_child(n)
	root.add_child(_line(a, b, 0.02, Look.flat(Color(0.2, 0.2, 0.22), 0.7)))


func _line(a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var d: Vector3 = b - a
	var mi := Look.cylinder(r, d.length(), m, (a + b) * 0.5, -1.0, 4)
	var up: Vector3 = d.normalized()
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9)).normalized()
	mi.basis = Basis(side, up, side.cross(up))
	return mi


## An overhanging lip of rock and ice (decor, no collision) with small icicles dripping off
## its edge. `c` is the centre of its underside, `size` its footprint (x, thickness, z) and
## `yaw` turns it. The level hangs GlacierIcicles under it.
func overhang(c: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var n := Node3D.new()
	var rock: StandardMaterial3D = GlacierFx.rock_mat(0.1)
	var slab := Look.box(size, rock, Vector3(0, size.y * 0.5, 0))
	n.add_child(slab)
	n.add_child(Look.box(Vector3(size.x + 0.4, 0.5, size.z + 0.4), GlacierFx.snow_mat(), Vector3(0, size.y + 0.2, 0)))
	var ice: ShaderMaterial = GlacierFx.glass_mat(0.6, 0.6, 0.85)
	n.add_child(Look.box(Vector3(size.x - 0.2, 0.35, size.z - 0.2), ice, Vector3(0, 0.1, 0)))
	var small: StandardMaterial3D = GlacierFx.ice_mat(GlacierFx.ICE, 0.45, 0.85)
	var k: int = int((size.x + size.z) * 0.9)
	for i: int in k:
		var along_x: bool = i % 2 == 0
		var u: float = rng.randf_range(-0.48, 0.48)
		var p: Vector3
		if along_x:
			p = Vector3(u * size.x, 0, (1.0 if rng.randf() < 0.5 else -1.0) * size.z * 0.5)
		else:
			p = Vector3((1.0 if rng.randf() < 0.5 else -1.0) * size.x * 0.5, 0, u * size.z)
		var l: float = rng.randf_range(0.4, 1.3)
		n.add_child(_no_shadow(Look.cylinder(0.01, l, small, p + Vector3(0, -l * 0.5, 0), rng.randf_range(0.08, 0.16), 6)) as Node3D)
	n.rotation.y = deg_to_rad(yaw)
	_put(n, c)


## A snow drift mound (flattened sphere) - softens the base of walls and the edges of plazas.
func drift(pos: Vector3, s: Vector3) -> void:
	var d := Look.sphere(1.0, GlacierFx.snow_mat(0.03))
	d.scale = s
	_put(d, pos)


## A tall spire of glowing ice, for skylines and landmarks.
func spire(base: Vector3, r: float, h: float, glow: float = 0.8) -> void:
	var n := Node3D.new()
	var m: ShaderMaterial = GlacierFx.glass_mat(glow, 0.4, 0.88)
	n.add_child(_no_shadow(Look.cylinder(r, h, m, Vector3(0, h * 0.5, 0), r * 0.12, 6)) as Node3D)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0 + rng.randf()
		var h2: float = h * rng.randf_range(0.3, 0.55)
		var s := _no_shadow(Look.cylinder(r * 0.45, h2, m, Vector3(cos(a) * r * 0.9, h2 * 0.5, sin(a) * r * 0.9), r * 0.05, 6)) as Node3D
		s.rotation = Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25)
		n.add_child(s)
	_put(n, base)
