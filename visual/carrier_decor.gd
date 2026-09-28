class_name CarrierDecor
extends RefCounted
## Super Carrier set dressing: the ship itself (hull, hangar, flight deck markings, the refit
## girders, the island and its mast), its aircraft, the sea, the escorts on the horizon, gulls and a
## plane-guard helicopter. Decoration only - the few solids here are walls the player can never reach
## but the camera should lean on. Everything is plain haze grey with no names, numbers or insignia.
## Materials are shared (Look's cache, or cached here).

const SEA_SHADER: Shader = preload("res://visual/carrier_sea.gdshader")
const FOAM_SHADER: Shader = preload("res://visual/carrier_foam.gdshader")
const STEEL_SHADER: Shader = preload("res://visual/carrier_steel.gdshader")
const SPIN: Script = preload("res://visual/spin.gd")

const HAZE := Color(0.53, 0.56, 0.59)
const HAZE_DARK := Color(0.4, 0.43, 0.46)
const DECK := Color(0.3, 0.32, 0.34)
const INTERIOR := Color(0.46, 0.48, 0.47)
const YELLOW := Color(1.0, 0.8, 0.12)
const WHITE := Color(0.9, 0.91, 0.9)
const RED := Color(0.85, 0.16, 0.12)
const GLASS := Color(0.08, 0.12, 0.16)

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


static func _no_shadow(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A box between two corners (world), with a material.
func slab(a: Vector3, b: Vector3, mat: Material, shadow: bool = true) -> MeshInstance3D:
	var lo: Vector3 = a.min(b)
	var hi: Vector3 = a.max(b)
	var mi := Look.box(hi - lo, mat)
	if not shadow:
		_no_shadow(mi)
	return _put(mi, (lo + hi) * 0.5) as MeshInstance3D


## A solid box between two corners (a wall the camera leans on), dressed with `mat`.
func wall(a: Vector3, b: Vector3, mat: Material) -> void:
	var lo: Vector3 = a.min(b)
	var hi: Vector3 = a.max(b)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = hi - lo
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.box(hi - lo, mat))
	_put(body, (lo + hi) * 0.5)


## Painted steel with the level's plating shader (per size, so the trim band lands on the lip).
func steel(size: Vector3, side: Color = HAZE, top: Color = DECK, trim: Color = YELLOW) -> ShaderMaterial:
	var key: String = "steel|%s|%s|%s|%s" % [size.snapped(Vector3.ONE * 0.1), side.to_html(), top.to_html(), trim.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = STEEL_SHADER
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("side_color", side)
	m.set_shader_parameter("trim_color", trim)
	m.set_shader_parameter("half_size", size * 0.5)
	_mats[key] = m
	return m


func steel_box(a: Vector3, b: Vector3, side: Color = HAZE, top: Color = DECK, solid: bool = false) -> void:
	var lo: Vector3 = a.min(b)
	var hi: Vector3 = a.max(b)
	var m: ShaderMaterial = steel(hi - lo, side, top, side.darkened(0.15))
	if solid:
		wall(lo, hi, m)
	else:
		slab(lo, hi, m)


# ---- the sea ------------------------------------------------------------------------------------

func sea(y: float, stern_z: float, bow_z: float, beam: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = SEA_SHADER
	m.set_shader_parameter("stern_z", stern_z)
	m.set_shader_parameter("bow_z", bow_z)
	m.set_shader_parameter("beam", beam)
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000.0, 9000.0)
	var mi := Look.mesh_node(pm, m)
	_no_shadow(mi)
	_put(mi, Vector3(0, y, (stern_z + bow_z) * 0.5))


# ---- the hull -------------------------------------------------------------------------------------

## The hull from the waterline up to the flight deck: straight sides, a flared bow, the open fantail
## at the stern, the hangar's walls inside (solid), hawse pipes and anchors, a waterline band.
func hull(sea_y: float, hangar_floor: float, deck_under: float, stern_z: float, hangar_fwd_z: float, bow_z: float,
		elev_z0: float, elev_z1: float) -> void:
	var hx: float = 19.0
	var side: Color = HAZE
	var inner_mat: ShaderMaterial = steel(Vector3(1.5, deck_under - hangar_floor, 60.0), INTERIOR, DECK, YELLOW)
	var outer: ShaderMaterial = steel(Vector3(2.0, deck_under - sea_y, 80.0), side, DECK, side.darkened(0.2))
	var bow_start: float = bow_z + 55.0
	# below the hangar floor: the hull down past the waterline
	slab(Vector3(-hx, sea_y - 6.0, stern_z), Vector3(hx, hangar_floor, bow_start), outer)
	# the hangar walls (solid; the camera leans on them), port broken by the elevator's door
	for sx: float in [-1.0, 1.0]:
		var x0: float = sx * hx
		var x1: float = sx * (hx - 1.5)
		if sx < 0.0:
			wall(Vector3(x0, hangar_floor, stern_z - 6.0), Vector3(x1, deck_under, elev_z0), inner_mat)
			wall(Vector3(x0, hangar_floor, elev_z1), Vector3(x1, deck_under, bow_start), inner_mat)
			# the door's frame and its rolled-up shutter
			slab(Vector3(x0, deck_under - 1.2, elev_z0), Vector3(x1, deck_under, elev_z1), steel(Vector3(1.5, 1.2, 14.0), HAZE_DARK))
		else:
			wall(Vector3(x0, hangar_floor, stern_z - 6.0), Vector3(x1, deck_under, bow_start), inner_mat)
	# the transom under the fantail, the fantail's side bulwarks
	slab(Vector3(-hx, sea_y - 6.0, stern_z - 1.5), Vector3(hx, -12.6, stern_z), outer)
	# the bow: two flared wedges closing to the stem, and the forecastle under the deck
	var bow_len: float = bow_start - bow_z
	for sx: float in [-1.0, 1.0]:
		var ang: float = atan2(hx, bow_len)
		var ln: float = sqrt(hx * hx + bow_len * bow_len)
		var b := Look.box(Vector3(2.0, deck_under - sea_y + 6.0, ln), outer)
		b.rotation.y = sx * ang
		_put(b, Vector3(sx * hx * 0.5, (deck_under + sea_y - 6.0) * 0.5, (bow_start + bow_z) * 0.5))
	var fill := Look.box(Vector3(hx * 1.2, deck_under - sea_y + 6.0, bow_len * 0.6), outer)
	_put(fill, Vector3(0, (deck_under + sea_y - 6.0) * 0.5, bow_start - bow_len * 0.3))
	# the forecastle's dark insides, seen through the torn-up deck
	slab(Vector3(-hx + 1.5, hangar_floor - 0.2, hangar_fwd_z), Vector3(hx - 1.5, hangar_floor, bow_start), Look.flat(Color(0.12, 0.13, 0.14), 0.9))
	# a black waterline band, anchors in their hawse pipes at the bow
	var band: StandardMaterial3D = Look.flat(Color(0.06, 0.06, 0.07), 0.8)
	for sx: float in [-1.0, 1.0]:
		slab(Vector3(sx * (hx + 0.05), sea_y - 0.3, stern_z), Vector3(sx * (hx + 0.12), sea_y + 1.2, bow_start), band, false)
		var hawse := Look.cylinder(1.1, 0.6, Look.flat(Color(0.08, 0.08, 0.09), 0.8), Vector3.ZERO, -1.0, 16)
		hawse.rotation.z = PI * 0.5
		_put(hawse, Vector3(sx * 12.5, deck_under - 7.0, bow_z + 26.0))
		var anchor := Node3D.new()
		var am: StandardMaterial3D = Look.flat(Color(0.18, 0.18, 0.2), 0.6, 0.6)
		anchor.add_child(Look.box(Vector3(0.5, 3.2, 0.5), am, Vector3(0, -1.6, 0)))
		anchor.add_child(Look.box(Vector3(2.6, 0.6, 0.6), am, Vector3(0, -3.2, 0)))
		_put(anchor, Vector3(sx * 13.2, deck_under - 7.6, bow_z + 26.0))
	# the starboard sponson under the deck overhang (a gallery of catwalks and boxes)
	slab(Vector3(hx, deck_under - 5.0, stern_z - 4.0), Vector3(hx + 6.8, deck_under, -140.0), steel(Vector3(6.8, 5.0, 100.0), HAZE_DARK))
	# a row of scuttles along both sides at the gallery deck
	var port_mat: StandardMaterial3D = Look.flat(Color(0.1, 0.12, 0.14), 0.3, 0.4)
	var z: float = stern_z - 8.0
	while z > bow_start + 10.0:
		for sx: float in [-1.0, 1.0]:
			if sx < 0.0 and z < elev_z0 + 2.0 and z > elev_z1 - 2.0:
				continue
			var p := Look.cylinder(0.28, 0.1, port_mat, Vector3.ZERO, -1.0, 10)
			p.rotation.z = PI * 0.5
			_put(_no_shadow(p), Vector3(sx * (hx + 0.06), deck_under - 3.2, z))
		z -= 5.0


## The angled deck's sponson under its overhang (a big wedge of supports) and the deck-edge
## catwalks with their safety nets.
func angled_sponson(x0: float, x1: float, z0: float, z1: float, deck_under: float) -> void:
	slab(Vector3(x0, deck_under - 4.0, z0), Vector3(x1, deck_under, z1), steel(Vector3(absf(x1 - x0), 4.0, absf(z1 - z0)), HAZE_DARK))
	var strut: StandardMaterial3D = Look.flat(HAZE_DARK.darkened(0.2), 0.7, 0.3)
	var z: float = z0
	while z > z1:
		var s := Look.box(Vector3(0.6, 12.0, 0.6), strut)
		s.rotation.z = -0.7
		_put(s, Vector3((x0 + x1) * 0.5 + 2.0, deck_under - 8.0, z))
		z -= 12.0


## Deck-edge catwalk with a safety net sloping out below the deck edge (visual).
func safety_net(x: float, z0: float, z1: float, out: float, deck_y: float) -> void:
	var net: StandardMaterial3D = Look.flat(Color(0.25, 0.27, 0.28, 0.75), 0.9)
	var frame: StandardMaterial3D = Look.flat(HAZE_DARK, 0.6, 0.4)
	var n := Look.box(Vector3(2.4, 0.05, absf(z1 - z0)), net)
	n.rotation.z = -0.25 * out
	_put(_no_shadow(n), Vector3(x + out * 1.3, deck_y - 1.1, (z0 + z1) * 0.5))
	var z: float = z0
	while z > z1:
		_put(Look.box(Vector3(2.6, 0.12, 0.12), frame), Vector3(x + out * 1.3, deck_y - 1.1, z))
		z -= 3.0


# ---- the hangar --------------------------------------------------------------------------------------

## The hangar bays: the foam flooding the deck, the overhead (beams, light rows, sprinkler pipes)
## under the intact deck, beacons, fire stations and pipe runs on the walls, divisional door frames.
func hangar(floor_y: float, foam_y: float, ceil_y: float, hw: float, z0: float, z1: float, roof_z: float, door_z: Array) -> void:
	# the foam
	var fm := ShaderMaterial.new()
	fm.shader = FOAM_SHADER
	var pm := PlaneMesh.new()
	pm.size = Vector2(hw * 2.0, absf(z0 - z1))
	var foam := Look.mesh_node(pm, fm)
	_no_shadow(foam)
	_put(foam, Vector3(0, foam_y, (z0 + z1) * 0.5))
	slab(Vector3(-hw, floor_y - 0.3, z0), Vector3(hw, floor_y, z1), Look.flat(Color(0.3, 0.31, 0.3), 0.9), false)
	# the overhead under the intact deck: frames across, light rows, sprinkler mains
	var beam: StandardMaterial3D = Look.flat(INTERIOR.darkened(0.15), 0.7, 0.4)
	var lamp: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.82), 0.4, 0.0, 2.6)
	var pipe: StandardMaterial3D = Look.flat(RED.darkened(0.25), 0.5, 0.3)
	var z: float = z0 - 2.0
	var k: int = 0
	while z > roof_z:
		_put(Look.box(Vector3(hw * 2.0, 0.9, 0.5), beam), Vector3(0, ceil_y - 0.45, z))
		if k % 2 == 0:
			for sx: float in [-1.0, 1.0]:
				_put(_no_shadow(Look.box(Vector3(2.4, 0.12, 0.6), lamp)), Vector3(sx * hw * 0.45, ceil_y - 1.0, z - 2.0))
		if k % 4 == 0:
			var o := OmniLight3D.new()
			o.light_color = Color(1.0, 0.93, 0.8)
			o.light_energy = 2.2
			o.omni_range = 22.0
			o.shadow_enabled = false
			_put(o, Vector3(0, ceil_y - 2.0, z - 2.0))
		z -= 4.0
		k += 1
	for sx: float in [-1.0, 1.0]:
		var run := Look.cylinder(0.18, absf(roof_z - z0), pipe, Vector3.ZERO, -1.0, 8)
		run.rotation.x = PI * 0.5
		_put(run, Vector3(sx * hw * 0.25, ceil_y - 1.3, (z0 + roof_z) * 0.5))
	# pipe runs, a yellow tide line and red fire stations along both walls
	var wallpipe: StandardMaterial3D = Look.flat(Color(0.34, 0.36, 0.38), 0.5, 0.6)
	var tide: StandardMaterial3D = Look.flat(YELLOW, 0.6, 0.0, 0.2)
	for sx: float in [-1.0, 1.0]:
		for h: float in [3.0, 4.2, 9.5]:
			var r := Look.cylinder(0.14, absf(z1 - z0), wallpipe, Vector3.ZERO, -1.0, 8)
			r.rotation.x = PI * 0.5
			_put(r, Vector3(sx * (hw - 0.3), floor_y + h, (z0 + z1) * 0.5))
		_put(_no_shadow(Look.box(Vector3(0.06, 0.4, absf(z1 - z0)), tide)), Vector3(sx * (hw - 0.04), foam_y + 1.2, (z0 + z1) * 0.5))
		var fz: float = z0 - 10.0
		while fz > z1:
			_put(Look.box(Vector3(0.4, 1.2, 0.9), Look.flat(RED, 0.5, 0.1, 0.2)), Vector3(sx * (hw - 0.25), foam_y + 3.2, fz))
			fz -= 24.0
	# the divisional doors' frames (open doors folded into the walls)
	var frame: ShaderMaterial = steel(Vector3(3.0, ceil_y - floor_y, 2.0), HAZE_DARK)
	for dz: float in door_z:
		for sx: float in [-1.0, 1.0]:
			slab(Vector3(sx * hw, floor_y, dz - 1.0), Vector3(sx * (hw - 3.0), ceil_y, dz + 1.0), frame)
		slab(Vector3(-hw, ceil_y - 1.4, dz - 1.0), Vector3(hw, ceil_y, dz + 1.0), frame)


## A red rotating warning beacon on a wall bracket.
func beacon(pos: Vector3, color: Color = Color(1.0, 0.2, 0.1)) -> void:
	var n := Node3D.new()
	n.add_child(Look.cylinder(0.18, 0.12, Look.flat(Color(0.2, 0.2, 0.2), 0.5, 0.5), Vector3(0, -0.2, 0)))
	var head := Node3D.new()
	head.set_script(SPIN)
	head.set("period", 1.2)
	head.add_child(Look.cylinder(0.16, 0.3, Look.flat(color, 0.3, 0.0, 2.5)))
	head.add_child(Look.box(Vector3(0.05, 0.26, 0.34), Look.flat(Color(0.1, 0.1, 0.1), 0.6)))
	n.add_child(head)
	_put(n, pos)


## An overhead bridge crane spanning the bay (rails along the walls, the bridge girder across).
func crane_bridge(z: float, y: float, hw: float) -> void:
	var yel: StandardMaterial3D = Look.flat(YELLOW.darkened(0.1), 0.55, 0.3)
	_put(Look.box(Vector3(hw * 2.0, 0.9, 1.2), yel), Vector3(0, y, z))
	_put(Look.box(Vector3(2.0, 1.2, 2.2), Look.flat(Color(0.25, 0.25, 0.27), 0.6, 0.4)), Vector3(0, y - 0.9, z))
	for sx: float in [-1.0, 1.0]:
		_put(Look.box(Vector3(0.6, 0.6, 30.0), yel), Vector3(sx * (hw - 0.5), y + 0.2, z))


# ---- the flight deck ------------------------------------------------------------------------------------

func _mark(a: Vector3, b: Vector3, color: Color, y: float) -> void:
	var lo: Vector3 = a.min(b)
	var hi: Vector3 = a.max(b)
	var m: StandardMaterial3D = Look.flat(color, 0.75)
	var mi := Look.box(Vector3(hi.x - lo.x, 0.03, hi.z - lo.z), m)
	_no_shadow(mi)
	_put(mi, Vector3((lo.x + hi.x) * 0.5, y + 0.015, (lo.z + hi.z) * 0.5))


## A dashed line along z at x.
func dashes(x: float, z0: float, z1: float, y: float, color: Color, dash: float = 3.0, gap: float = 3.0, w: float = 0.3) -> void:
	var z: float = z0
	while z - dash > z1:
		_mark(Vector3(x - w * 0.5, 0, z), Vector3(x + w * 0.5, 0, z - dash), color, y)
		z -= dash + gap


## A line from `a` to `b` (world xz), `w` wide, at deck height y.
func line(a: Vector2, b: Vector2, y: float, color: Color, w: float = 0.35, dashed: bool = false) -> void:
	var d: Vector2 = b - a
	var ln: float = d.length()
	if ln < 0.01:
		return
	var m: StandardMaterial3D = Look.flat(color, 0.75)
	var step: float = 6.0 if dashed else ln
	var t: float = 0.0
	while t < ln - 0.01:
		var seg: float = minf(step * (0.5 if dashed else 1.0), ln - t)
		var c: Vector2 = a + d / ln * (t + seg * 0.5)
		var mi := Look.box(Vector3(w, 0.03, seg), m)
		mi.rotation.y = atan2(-d.x, -d.y)
		_no_shadow(mi)
		_put(mi, Vector3(c.x, y + 0.016, c.y))
		t += step


## The painted deck of the aft flight deck: the angled landing area (edge lines, centreline, foul
## lines), the ship's centreline, the deck-edge line, elevator outlines and the landing lights.
func aft_markings(y: float, stern_z: float, island_z: float) -> void:
	# the landing area runs up and to port at ~9 degrees from the stern
	var a0 := Vector2(-4.0, stern_z - 2.0)
	var dir := Vector2(-sin(deg_to_rad(9.0)), -cos(deg_to_rad(9.0)))
	var side := Vector2(dir.y, -dir.x)
	var ln: float = 106.0
	for s: float in [-1.0, 1.0]:
		line(a0 + side * s * 12.0, a0 + side * s * 12.0 + dir * ln, y, WHITE, 0.4)
	line(a0, a0 + dir * ln, y, WHITE, 0.45, true)
	# red-and-white foul line along the landing area's starboard side
	var f0: Vector2 = a0 - side * 14.5
	var steps: int = int(ln / 3.0)
	for i: int in steps:
		var p0: Vector2 = f0 + dir * (float(i) * 3.0)
		line(p0, p0 + dir * 3.0, y, RED if i % 2 == 0 else WHITE, 0.35)
	# ship's centreline and the deck-edge line on the starboard side
	dashes(8.0, stern_z - 4.0, island_z - 10.0, y, YELLOW, 4.0, 4.0, 0.3)
	# landing area edge lights (flush, glowing)
	var lamp: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.8), 0.3, 0.0, 2.0)
	for i: int in int(ln / 10.0):
		for s: float in [-1.0, 1.0]:
			var p: Vector2 = a0 + side * s * 12.6 + dir * (float(i) * 10.0 + 5.0)
			_put(_no_shadow(Look.box(Vector3(0.3, 0.06, 0.3), lamp)), Vector3(p.x, y + 0.03, p.y))


## Lane markings for a catapult lane on the bow (edge lines in yellow, hatched run-up).
func lane_marks(x: float, z0: float, z1: float, y: float, half: float) -> void:
	for s: float in [-1.0, 1.0]:
		dashes(x + s * half, z0, z1, y, YELLOW, 5.0, 2.0, 0.25)


## Girders of the torn-up deck: I-beams across (x) and along (z) the open region, below deck level.
func refit_girders(x0: float, x1: float, z0: float, z1: float, y: float, holes: Array[Rect2] = []) -> void:
	var m: StandardMaterial3D = Look.flat(Color(0.5, 0.36, 0.26), 0.7, 0.4)
	var dark: StandardMaterial3D = Look.flat(Color(0.3, 0.26, 0.22), 0.8, 0.3)
	# girders across (x): split round the holes they would cross
	var z: float = z0
	while z >= z1:
		for seg: Vector2 in _spans(x0, x1, z, holes, true):
			_put(Look.box(Vector3(seg.y - seg.x, 0.9, 0.35), m), Vector3((seg.x + seg.y) * 0.5, y, z))
			_put(_no_shadow(Look.box(Vector3(seg.y - seg.x, 0.08, 0.7), dark)), Vector3((seg.x + seg.y) * 0.5, y + 0.45, z))
		z -= 6.0
	# stringers along (z)
	var x: float = x0
	while x <= x1:
		for seg: Vector2 in _spans(z1, z0, x, holes, false):
			_put(Look.box(Vector3(0.3, 0.7, seg.y - seg.x), m), Vector3(x, y - 0.1, (seg.x + seg.y) * 0.5))
		x += 9.0


## The pieces of the line a..b (at the fixed other coordinate `at`) that stay out of the holes
## (Rect2 in x, z). across = the line runs along x.
func _spans(a: float, b: float, at: float, holes: Array[Rect2], across: bool) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(a, b)]
	for h: Rect2 in holes:
		var lo: float = h.position.x if across else h.position.y
		var hi: float = lo + (h.size.x if across else h.size.y)
		var olo: float = h.position.y if across else h.position.x
		var ohi: float = olo + (h.size.y if across else h.size.x)
		if at < olo or at > ohi:
			continue
		var next: Array[Vector2] = []
		for sg: Vector2 in out:
			if sg.y <= lo or sg.x >= hi:
				next.append(sg)
				continue
			if sg.x < lo:
				next.append(Vector2(sg.x, lo))
			if sg.y > hi:
				next.append(Vector2(hi, sg.y))
		out = next
	return out


## A scaffolding tower (tubes and boards) from y0 up to y1.
func scaffold(pos: Vector3, y0: float, y1: float, w: float = 2.0) -> void:
	var tube: StandardMaterial3D = Look.flat(Color(0.7, 0.72, 0.74), 0.4, 0.8)
	var board: StandardMaterial3D = Look.flat(Color(0.65, 0.5, 0.3), 0.8)
	var h: float = y1 - y0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_put(Look.cylinder(0.05, h, tube, Vector3.ZERO, -1.0, 6), pos + Vector3(sx * w * 0.5, y0 + h * 0.5, sz * w * 0.5))
	var y: float = y0 + 1.8
	while y < y1:
		_put(Look.box(Vector3(w + 0.2, 0.06, w + 0.2), board), pos + Vector3(0, y, 0))
		var br := Look.cylinder(0.04, sqrt(w * w + 3.24), tube, Vector3.ZERO, -1.0, 6)
		br.rotation.z = atan2(w, 1.8)
		_put(br, pos + Vector3(0, y - 0.9, w * 0.5))
		y += 1.8


## A work light on a stand (a warm lamp head, a small light).
func work_light(pos: Vector3, aim: Vector3) -> void:
	var n := Node3D.new()
	n.add_child(Look.cylinder(0.05, 2.2, Look.flat(Color(0.2, 0.2, 0.2), 0.5, 0.5), Vector3(0, 1.1, 0)))
	var head := Look.box(Vector3(0.6, 0.4, 0.2), Look.flat(Color(1.0, 0.92, 0.7), 0.3, 0.0, 3.0), Vector3(0, 2.3, 0))
	head.look_at_from_position(Vector3(0, 2.3, 0), Vector3(0, 2.3, 0) + aim, Vector3.UP)
	n.add_child(head)
	_put(n, pos)


## A deck-edge gun mount: a white radome on a pedestal over a stubby barrel housing.
func ciws(pos: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	var white: StandardMaterial3D = Look.flat(Color(0.88, 0.9, 0.9), 0.5, 0.1)
	n.add_child(Look.cylinder(1.3, 1.4, Look.flat(HAZE, 0.6, 0.3), Vector3(0, 0.7, 0)))
	n.add_child(Look.box(Vector3(1.8, 1.6, 2.0), Look.flat(HAZE_DARK, 0.6, 0.3), Vector3(0, 2.2, 0)))
	var dome := Look.cylinder(0.9, 2.2, white, Vector3(0, 4.1, 0), 0.9, 16)
	n.add_child(dome)
	n.add_child(Look.sphere(0.9, white, Vector3(0, 5.2, 0)))
	var barrel := Look.cylinder(0.25, 2.2, Look.flat(Color(0.2, 0.2, 0.22), 0.5, 0.6), Vector3(0, 2.3, -1.6))
	barrel.rotation.x = PI * 0.5
	n.add_child(barrel)
	n.rotation.y = deg_to_rad(yaw)
	_put(n, pos)


## A missile launcher box on a sponson (angled canister box).
func launcher(pos: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.add_child(Look.cylinder(1.0, 0.8, Look.flat(HAZE_DARK, 0.6, 0.3), Vector3(0, 0.4, 0)))
	var box := Look.box(Vector3(2.4, 1.6, 3.4), Look.flat(HAZE, 0.6, 0.2), Vector3(0, 1.8, 0))
	box.rotation.x = -0.35
	n.add_child(box)
	n.rotation.y = deg_to_rad(yaw)
	_put(n, pos)


## Tall whip antennas along a deck edge (folded out at an angle).
func whips(x: float, z0: float, z1: float, y: float, out: float, spacing: float = 14.0) -> void:
	var m: StandardMaterial3D = Look.flat(Color(0.85, 0.86, 0.86), 0.5, 0.3)
	var z: float = z0
	while z > z1:
		var a := Look.cylinder(0.05, 9.0, m, Vector3.ZERO, 0.03, 6)
		a.rotation.z = -out * 0.35
		_put(a, Vector3(x + out * 1.5, y + 4.3, z))
		z -= spacing


## The optical landing aid on the port deck edge: a box of amber lights between green datum bars.
func landing_lens(pos: Vector3) -> void:
	var n := Node3D.new()
	n.add_child(Look.box(Vector3(1.4, 3.0, 1.0), Look.flat(Color(0.15, 0.15, 0.16), 0.6, 0.3), Vector3(0, 1.5, 0)))
	for i: int in 5:
		n.add_child(_no_shadow(Look.box(Vector3(1.0, 0.4, 0.08), Look.flat(Color(1.0, 0.6, 0.1) if i == 2 else Color(0.25, 0.15, 0.05), 0.3, 0.0, 3.0 if i == 2 else 0.2), Vector3(0, 0.6 + float(i) * 0.5, 0.52))))
	for sx: float in [-1.0, 1.0]:
		for i: int in 4:
			n.add_child(_no_shadow(Look.box(Vector3(0.5, 0.2, 0.2), Look.flat(Color(0.2, 1.0, 0.35), 0.3, 0.0, 2.8), Vector3(sx * (1.2 + float(i) * 0.7), 1.6, 0.2))))
	n.rotation.y = PI * 0.5
	_put(n, pos)


# ---- the island ------------------------------------------------------------------------------------------

## Dresses the island's solid blocks: plated walls with window bands, the bridge's wraparound glass,
## pri-fly's raked windows overhanging the deck, doors, ladders, antennas, flat radar arrays, a crane.
func island(x0: float, x1: float, z0: float, z1: float, levels: Array) -> void:
	var side: Color = HAZE
	var glass: StandardMaterial3D = Look.flat(GLASS, 0.05, 0.7, 0.2)
	var frame: StandardMaterial3D = Look.flat(HAZE_DARK, 0.6, 0.3)
	for lv: Dictionary in levels:
		var a: Vector3 = lv["a"]
		var b: Vector3 = lv["b"]
		steel_box(a, b, side, HAZE_DARK)
		# a window band on every face near the top of the block
		var wy: float = b.y - float(lv.get("win", 1.6))
		var wh: float = float(lv.get("wh", 1.0))
		var sx: float = b.x - a.x
		var sz: float = b.z - a.z
		for f: int in 4:
			var c := Vector3((a.x + b.x) * 0.5, wy, (a.z + b.z) * 0.5)
			var size := Vector3(sx + 0.06, wh, 0.08) if f < 2 else Vector3(0.08, wh, sz + 0.06)
			if f == 0:
				c.z = a.z - 0.02
			elif f == 1:
				c.z = b.z + 0.02
			elif f == 2:
				c.x = a.x - 0.02
			else:
				c.x = b.x + 0.02
			_put(_no_shadow(Look.box(size, glass)), c)
			# mullions
			var along: float = sx if f < 2 else sz
			var n: int = int(along / 1.6)
			for i: int in n:
				var t: float = -along * 0.5 + (float(i) + 0.5) * along / float(n)
				var mp: Vector3 = c + (Vector3(t, 0, 0) if f < 2 else Vector3(0, 0, t))
				_put(_no_shadow(Look.box(Vector3(0.12, wh + 0.1, 0.12), frame)), mp)
	# watertight doors at deck level on the inboard face
	var door: StandardMaterial3D = Look.flat(HAZE_DARK.darkened(0.1), 0.6, 0.3)
	for z: float in [z0 + 6.0, z0 + 20.0, z1 - 6.0]:
		_put(Look.box(Vector3(0.12, 2.0, 1.0), door), Vector3(x0 - 0.06, 1.0, z))


## Flat phased-array radar faces on the island (big octagonal panels).
func array_face(pos: Vector3, normal_yaw: float, size: float = 3.6) -> void:
	var n := Node3D.new()
	var face := Look.cylinder(size * 0.5, 0.25, Look.flat(Color(0.38, 0.4, 0.42), 0.5, 0.4), Vector3.ZERO, -1.0, 8)
	face.rotation.x = PI * 0.5
	n.add_child(face)
	var rim := Look.cylinder(size * 0.52, 0.18, Look.flat(HAZE_DARK, 0.6, 0.3), Vector3(0, 0, -0.1), -1.0, 8)
	rim.rotation.x = PI * 0.5
	n.add_child(rim)
	n.rotation.y = normal_yaw
	_put(n, pos)


## A lattice mast from y0 to y1 round (x, z): corner posts, cross braces, yardarms with dangling
## signal flags, antennas, and a spinning radar at the top.
func mast(x: float, z: float, y0: float, y1: float, w: float, yardarms: Array, crown: bool = true) -> Node3D:
	var post: StandardMaterial3D = Look.flat(Color(0.62, 0.64, 0.66), 0.5, 0.5)
	var h: float = y1 - y0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_put(Look.box(Vector3(0.25, h, 0.25), post), Vector3(x + sx * w * 0.5, y0 + h * 0.5, z + sz * w * 0.5))
	var y: float = y0 + 1.5
	while y < y1 - 0.5:
		for f: int in 4:
			var diag := Node3D.new()
			diag.rotation.y = float(f) * PI * 0.5
			var d := Look.box(Vector3(w * 1.42, 0.12, 0.12), post)
			d.rotation.z = 0.785 if (f + int(y)) % 2 == 0 else -0.785
			d.position = Vector3(0, 0, w * 0.5)
			diag.add_child(d)
			_put(diag, Vector3(x, y, z))
		y += 1.5
	var flagcols: Array[Color] = [Color(1.0, 0.85, 0.1), Color(0.15, 0.3, 0.8), Color(0.9, 0.15, 0.1), Color(0.95, 0.95, 0.95), Color(0.1, 0.55, 0.25)]
	for ya: Dictionary in yardarms:
		var yy: float = ya["y"]
		var span: float = ya["span"]
		_put(Look.box(Vector3(span, 0.2, 0.2), post), Vector3(x, yy, z))
		# a hoist of signal flags off each end
		for sx: float in [-1.0, 1.0]:
			for i: int in 4:
				var fm: StandardMaterial3D = Look.flat(flagcols[(i + int(yy)) % flagcols.size()], 0.8)
				var fl := Look.box(Vector3(0.05, 0.55, 0.7), fm)
				_put(fl, Vector3(x + sx * (span * 0.5 - 0.2), yy - 0.5 - float(i) * 0.7, z + 0.35))
	if not crown:
		return null
	# the spinning radar at the top
	var top := Node3D.new()
	top.set_script(SPIN)
	top.set("period", 4.0)
	top.add_child(Look.box(Vector3(5.5, 1.1, 0.3), Look.flat(Color(0.7, 0.72, 0.74), 0.5, 0.4), Vector3(0, 0.9, 0)))
	top.add_child(Look.cylinder(0.25, 0.8, post, Vector3(0, 0.3, 0)))
	_put(top, Vector3(x, y1 + 0.2, z))
	# whip antennas off the masthead
	for i: int in 3:
		var a := Look.cylinder(0.04, 5.0 + float(i), Look.flat(Color(0.85, 0.85, 0.85), 0.5, 0.3), Vector3.ZERO, 0.02, 6)
		a.rotation.z = (float(i) - 1.0) * 0.25
		_put(a, Vector3(x + (float(i) - 1.0) * 0.8, y1 + 3.0 + float(i) * 0.5, z - 0.8))
	return top


# ---- far away -----------------------------------------------------------------------------------------------

## An escort warship on the horizon steaming alongside (hull, superstructure, mast, a white wake).
func escort(pos: Vector3, length: float, yaw: float = 0.0) -> void:
	var n := Node3D.new()
	var hull_m: StandardMaterial3D = Look.flat(HAZE.darkened(0.05), 0.7, 0.2)
	var sup: StandardMaterial3D = Look.flat(HAZE.lightened(0.05), 0.65, 0.2)
	var w: float = length * 0.12
	n.add_child(Look.box(Vector3(w, 4.0, length * 0.8), hull_m, Vector3(0, 2.0, length * 0.1)))
	var bow := Look.box(Vector3(w * 0.72, 4.0, length * 0.28), hull_m, Vector3(0, 2.0, -length * 0.38))
	bow.rotation.y = PI * 0.25
	bow.scale = Vector3(1.0, 1.0, 1.0)
	n.add_child(bow)
	n.add_child(Look.box(Vector3(w * 0.7, 4.0, length * 0.22), sup, Vector3(0, 6.0, -length * 0.05)))
	n.add_child(Look.box(Vector3(w * 0.55, 3.0, length * 0.12), sup, Vector3(0, 9.0, -length * 0.08)))
	n.add_child(Look.box(Vector3(w * 0.6, 3.0, length * 0.14), sup, Vector3(0, 5.5, length * 0.22)))
	n.add_child(Look.cylinder(0.4, 9.0, sup, Vector3(0, 14.0, -length * 0.06), 0.2, 8))
	n.add_child(Look.box(Vector3(w * 0.3, 1.2, w * 0.3), sup, Vector3(0, 5.0, -length * 0.28)))
	# its wake
	var wake := Look.box(Vector3(w * 1.6, 0.05, length * 1.8), Look.flat(Color(0.9, 0.93, 0.95), 0.9))
	wake.position = Vector3(0, 0.1, length * 1.35)
	n.add_child(_no_shadow(wake))
	var bw := Look.box(Vector3(w * 2.4, 0.05, length * 0.2), Look.flat(Color(0.92, 0.95, 0.97), 0.9))
	bw.position = Vector3(0, 0.1, -length * 0.5)
	n.add_child(_no_shadow(bw))
	n.rotation.y = deg_to_rad(yaw)
	for c: Node in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_put(n, pos)


## A flock of gulls wheeling round `center` (V-winged, circling on a spin holder).
func gulls(center: Vector3, radius: float, count: int, period: float) -> void:
	var holder := Node3D.new()
	holder.set_script(SPIN)
	holder.set("period", period)
	var m: StandardMaterial3D = Look.flat(Color(0.95, 0.95, 0.94), 0.8)
	var tip: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.22), 0.8)
	for i: int in count:
		var a: float = float(i) / float(count) * TAU + rng.randf_range(-0.3, 0.3)
		var g := Node3D.new()
		g.position = Vector3(cos(a), rng.randf_range(-0.2, 0.2), sin(a)) * radius + Vector3(0, rng.randf_range(-2.0, 2.0), 0)
		g.rotation.y = -a
		for sx: float in [-1.0, 1.0]:
			var wing := Look.box(Vector3(0.7, 0.03, 0.22), m, Vector3(sx * 0.35, 0.08, 0))
			wing.rotation.z = sx * 0.3
			g.add_child(wing)
			g.add_child(Look.box(Vector3(0.18, 0.031, 0.2), tip, Vector3(sx * 0.72, 0.19, 0)))
		g.add_child(Look.box(Vector3(0.12, 0.1, 0.45), m))
		holder.add_child(g)
	_put(holder, center)


## A plane-guard helicopter circling off the ship (spinning rotor, slow circuit).
func plane_guard(center: Vector3, radius: float, period: float) -> void:
	var holder := Node3D.new()
	holder.set_script(SPIN)
	holder.set("period", period)
	var h: Node3D = CarrierCraft.helo(false)
	h.position = Vector3(radius, 0, 0)
	h.rotation.y = PI
	var rotor: Node3D = h.get_node("Rotor")
	rotor.set_script(SPIN)
	rotor.set("period", 0.22)
	holder.add_child(h)
	_put(holder, center)


## A pair of jets flying a wide racetrack high overhead (the combat air patrol).
func patrol(center: Vector3, radius: float, period: float) -> void:
	var holder := Node3D.new()
	holder.set_script(SPIN)
	holder.set("period", period)
	for i: int in 2:
		var j: Node3D = CarrierCraft.jet(false)
		j.position = Vector3(radius, float(i) * 3.0, float(i) * 22.0)
		j.rotation = Vector3(0, PI, 0.5)
		j.scale = Vector3.ONE * 1.0
		holder.add_child(j)
	_put(holder, center)
