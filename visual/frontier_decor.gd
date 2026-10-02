class_name FrontierDecor
extends RefCounted
## Wild West Heist set dressing, built from primitives: the train (underframes, trucks and spinning
## wheelsets, couplers, car bodies' doors, ladders and windows, the caboose, the tender and the big
## steam locomotive with its working rods), the trestle it stands on, and the canyon sliding past
## (scrolled with FrontierScroll: sleepers, bents, telegraph poles, hoodoos, cacti, the river floor,
## the red-rock walls). Nothing here collides: the level builds every walkable surface itself.
## The track runs along Z (the locomotive at -Z); rails top at y = 0.

const WOOD_SHADER: Shader = preload("res://visual/frontier_wood.gdshader")
const ROCK_SHADER: Shader = preload("res://visual/frontier_rock.gdshader")
const GROUND_SHADER: Shader = preload("res://visual/frontier_ground.gdshader")

const IRON := Color(0.13, 0.12, 0.12)
const RUST := Color(0.42, 0.22, 0.14)
const BRASS := Color(0.95, 0.72, 0.32)
const TIMBER := Color(0.36, 0.25, 0.17)
const WHEEL_R: float = 0.42
const CANYON_FLOOR: float = -62.0

var root: Node3D
var rng: RandomNumberGenerator
## Materials whose `scroll` uniform the level drives every frame: {"mat": ShaderMaterial, "period": float}
## (period <= 0: scroll continuously).
var scroll_mats: Array[Dictionary] = []
## Spinning wheelsets / drive wheels (driven by the level so they turn with the scenery).
var spinners: Array[Node3D] = []
var _iron: StandardMaterial3D
var _rust: StandardMaterial3D
var _brass: StandardMaterial3D
var _timber: StandardMaterial3D


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r
	_iron = Look.flat(IRON, 0.5, 0.6)
	_rust = Look.flat(RUST, 0.85, 0.2)
	_brass = Look.flat(BRASS, 0.28, 0.85, 0.15)
	_timber = Look.flat(TIMBER, 0.92)


# ---- materials ---------------------------------------------------------------------------------------

## Railroad timber with the platform shader's layout (see visual/frontier_wood.gdshader).
static func wood(top: Color, side: Color, trim: Color, half: Vector3, kind: int = 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WOOD_SHADER
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("side_color", side)
	m.set_shader_parameter("trim_color", trim)
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("kind", kind)
	return m


func rock(period: float = 0.0, strata: float = 0.11) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("strata", strata)
	scroll_mats.append({"mat": m, "period": period})
	return m


func _add(n: Node3D, parent: Node3D = null) -> Node3D:
	(parent if parent != null else root).add_child(n)
	return n


func box(center: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := Look.box(size, mat, center)
	_add(mi, parent)
	return mi


func cyl_z(center: Vector3, radius: float, length: float, mat: Material, parent: Node3D = null, seg: int = 20) -> MeshInstance3D:
	var mi := Look.cylinder(radius, length, mat, center, -1.0, seg)
	mi.rotation.x = PI * 0.5
	_add(mi, parent)
	return mi


func cyl_x(center: Vector3, radius: float, length: float, mat: Material, parent: Node3D = null, seg: int = 16) -> MeshInstance3D:
	var mi := Look.cylinder(radius, length, mat, center, -1.0, seg)
	mi.rotation.z = PI * 0.5
	_add(mi, parent)
	return mi


# ---- running gear --------------------------------------------------------------------------------------

## A wheelset (axle + two wheels) that turns as the scenery slides past.
func wheelset(at: Vector3, r: float = WHEEL_R, gauge: float = 1.5) -> Node3D:
	var ws := Node3D.new()
	ws.position = at
	ws.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_add(ws)
	for sx: float in [-1.0, 1.0]:
		var w := Look.cylinder(r, 0.14, _iron, Vector3(sx * gauge * 0.5, 0, 0), -1.0, 16)
		w.rotation.z = PI * 0.5
		ws.add_child(w)
		# a red-painted spoke bar so the spin reads
		ws.add_child(Look.box(Vector3(0.04, r * 1.7, 0.12), Look.flat(Color(0.6, 0.12, 0.08), 0.6), Vector3(sx * (gauge * 0.5 + 0.08), 0, 0)))
	ws.add_child(Look.cylinder(0.07, gauge + 0.1, _iron, Vector3.ZERO, -1.0, 8))
	(ws.get_child(ws.get_child_count() - 1) as Node3D).rotation.z = PI * 0.5
	ws.set_meta("r", r)
	spinners.append(ws)
	return ws


## A four-wheel truck centred at z.
func truck(z: float) -> void:
	for dz: float in [-0.85, 0.85]:
		wheelset(Vector3(0, WHEEL_R, z + dz))
	for sx: float in [-1.0, 1.0]:
		box(Vector3(sx * 0.98, 0.55, z), Vector3(0.14, 0.34, 2.5), _iron)
		box(Vector3(sx * 0.98, 0.42, z), Vector3(0.2, 0.2, 0.6), _rust)
	box(Vector3(0, 0.78, z), Vector3(2.0, 0.22, 0.5), _iron)


## Underframe, two trucks and coupler heads for a car from z_rear (+) to z_front (-), deck bottom at y.
func running_gear(z_rear: float, z_front: float, deck_bottom: float = 1.25) -> void:
	var len: float = z_rear - z_front
	var zc: float = (z_rear + z_front) * 0.5
	box(Vector3(0, deck_bottom - 0.2, zc), Vector3(0.8, 0.4, len - 0.4), _iron)
	for sx: float in [-1.0, 1.0]:
		box(Vector3(sx * 1.3, deck_bottom - 0.12, zc), Vector3(0.12, 0.24, len - 1.0), _iron)
	truck(z_rear - minf(2.4, len * 0.2))
	truck(z_front + minf(2.4, len * 0.2))
	for e: float in [z_rear, z_front]:
		var s: float = 1.0 if e == z_rear else -1.0
		box(Vector3(0, deck_bottom - 0.25, e + s * 0.3), Vector3(0.36, 0.3, 0.6), _iron)


## The drawbar between two cars across a gap (visual only).
func coupler(z_a: float, z_b: float, y: float = 1.0) -> void:
	box(Vector3(0, y, (z_a + z_b) * 0.5), Vector3(0.22, 0.2, absf(z_a - z_b) + 0.6), _iron)
	# the air hose sagging under it
	box(Vector3(0.35, y - 0.25, (z_a + z_b) * 0.5), Vector3(0.08, 0.08, absf(z_a - z_b) * 0.9), Look.flat(Color(0.08, 0.08, 0.08), 0.8))


## Grab-iron ladder up a car face.
func ladder(base: Vector3, height: float, across_x: bool = true, parent: Node3D = null) -> void:
	var rungs: int = int(height / 0.4)
	for i: int in rungs:
		var y: float = base.y + 0.3 + float(i) * height / float(rungs)
		box(Vector3(base.x, y, base.z), Vector3(0.55, 0.05, 0.05) if across_x else Vector3(0.05, 0.05, 0.55), _iron, parent)


# ---- car bodies (dressing only; the level gives each its collision) ---------------------------------

## Boxcar dressing on a body from z_rear to z_front, body side faces at x = +-hw, roof at y_top.
func boxcar_dress(z_rear: float, z_front: float, y_top: float, color: Color, hw: float = 2.0) -> void:
	var zc: float = (z_rear + z_front) * 0.5
	var len: float = z_rear - z_front
	var door_mat: StandardMaterial3D = Look.flat(color.darkened(0.25), 0.85)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (hw + 0.03)
		# the sliding door, its track and handle
		box(Vector3(x, 2.9, zc), Vector3(0.06, 2.6, minf(3.0, len * 0.3)), door_mat)
		box(Vector3(x + sx * 0.04, 4.3, zc), Vector3(0.06, 0.12, minf(3.0, len * 0.3) * 2.0), _iron)
		box(Vector3(x + sx * 0.05, 2.9, zc - minf(1.4, len * 0.14)), Vector3(0.05, 0.6, 0.06), _iron)
		# corner ladders and a stencilled band
		ladder(Vector3(x + sx * 0.03, 1.4, z_rear - 0.45), y_top - 1.8, false)
		ladder(Vector3(x + sx * 0.03, 1.4, z_front + 0.45), y_top - 1.8, false)
		box(Vector3(x, y_top - 0.75, zc), Vector3(0.05, 0.25, len * 0.55), Look.flat(Color(0.92, 0.88, 0.76), 0.8))
	# the brake wheel on the rear end
	var bw := Look.cylinder(0.32, 0.05, _iron, Vector3(0, y_top - 0.6, z_rear + 0.06), -1.0, 12)
	bw.rotation.x = PI * 0.5
	_add(bw)


## Passenger coach dressing: windows glowing in the dusk, panel lines, end vestibules.
func coach_dress(z_rear: float, z_front: float, y_top: float, color: Color, hw: float = 2.0) -> void:
	var len: float = z_rear - z_front
	var glass: StandardMaterial3D = Look.flat(Color(1.0, 0.78, 0.42), 0.3, 0.0, 1.6)
	var frame: StandardMaterial3D = Look.flat(color.darkened(0.45), 0.7)
	var cream: StandardMaterial3D = Look.flat(Color(0.95, 0.86, 0.66), 0.7)
	var n: int = int((len - 2.0) / 1.6)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (hw + 0.03)
		box(Vector3(x, 3.4, (z_rear + z_front) * 0.5), Vector3(0.05, 1.5, len - 1.2), frame)
		box(Vector3(x, 2.35, (z_rear + z_front) * 0.5), Vector3(0.05, 0.1, len - 0.6), cream)
		box(Vector3(x, y_top - 0.5, (z_rear + z_front) * 0.5), Vector3(0.05, 0.1, len - 0.6), cream)
		for i: int in n:
			var z: float = z_rear - 1.4 - float(i) * (len - 2.8) / float(maxi(n - 1, 1))
			box(Vector3(x + sx * 0.01, 3.45, z), Vector3(0.05, 1.1, 0.95), glass)


## Caboose dressing: bay windows, the cupola's windows, a lantern at each end, end railings.
func caboose_dress(z_rear: float, z_front: float, y_top: float, cupola_z: Vector2, cupola_top: float) -> void:
	var glass: StandardMaterial3D = Look.flat(Color(1.0, 0.75, 0.4), 0.3, 0.0, 1.8)
	for sx: float in [-1.0, 1.0]:
		for z: float in [z_rear - 1.6, (z_rear + z_front) * 0.5, z_front + 1.6]:
			box(Vector3(sx * 2.03, 3.4, z), Vector3(0.05, 0.9, 0.8), glass)
		for z2: float in [cupola_z.x - 0.6, cupola_z.y + 0.6]:
			box(Vector3(sx * 1.33, cupola_top - 0.7, z2), Vector3(0.05, 0.6, 0.8), glass)
	# the red marker lamps on the rear end
	for sx2: float in [-1.0, 1.0]:
		lantern(Vector3(sx2 * 1.7, y_top - 0.8, z_rear + 0.2), Color(1.0, 0.18, 0.1), sx2 < 0.0)


## Railing round a porch deck (an open end platform) at deck height y between z_a and z_b.
func railing(y: float, z_a: float, z_b: float, hw: float = 1.95, open_end: float = 0.0) -> void:
	var post_mat: StandardMaterial3D = Look.flat(Color(0.14, 0.13, 0.12), 0.5, 0.5)
	for sx: float in [-1.0, 1.0]:
		for z: float in [z_a, z_b, (z_a + z_b) * 0.5]:
			box(Vector3(sx * hw, y + 0.55, z), Vector3(0.07, 1.1, 0.07), post_mat)
		box(Vector3(sx * hw, y + 1.08, (z_a + z_b) * 0.5), Vector3(0.06, 0.06, absf(z_a - z_b)), post_mat)
	if open_end != 0.0:
		var z_end: float = z_a if open_end > 0.0 else z_b
		for sx: float in [-1.0, 1.0]:
			box(Vector3(sx * hw * 0.62, y + 1.08, z_end), Vector3(hw * 0.75, 0.06, 0.06), post_mat)


## A kerosene lantern hung on a bracket (a warm glow; `light` adds a real lamp).
func lantern(at: Vector3, color: Color = Color(1.0, 0.7, 0.35), light: bool = false) -> void:
	var n := Node3D.new()
	n.position = at
	_add(n)
	n.add_child(Look.box(Vector3(0.3, 0.06, 0.3), _iron, Vector3(0, 0.26, 0)))
	n.add_child(Look.cylinder(0.12, 0.34, Look.flat(color, 0.2, 0.0, 3.0), Vector3(0, 0.05, 0), 0.1, 10))
	n.add_child(Look.box(Vector3(0.28, 0.05, 0.28), _iron, Vector3(0, -0.15, 0)))
	n.add_child(Fx.sprite(Color(color.r * 2.0, color.g * 1.6, color.b * 1.2, 0.6), 1.2, Fx.Tex.DOT))
	if light:
		var o := OmniLight3D.new()
		o.light_color = color
		o.light_energy = 1.2
		o.omni_range = 6.0
		n.add_child(o)


## Tank car dressing: the barrel, its bands, dome and walkway handrails (tank axis along z).
func tank_dress(z_rear: float, z_front: float, cy: float, r: float, color: Color) -> void:
	var len: float = z_rear - z_front
	var zc: float = (z_rear + z_front) * 0.5
	var shell: StandardMaterial3D = Look.flat(color, 0.55, 0.3)
	cyl_z(Vector3(0, cy, zc), r, len - 0.6, shell, null, 28)
	for e: float in [z_rear - 0.3, z_front + 0.3]:
		var cap := Look.sphere(r, shell, Vector3(0, cy, e))
		cap.scale = Vector3(1.0, 1.0, 0.25)
		_add(cap)
	for i: int in 5:
		var z: float = z_rear - 0.8 - float(i) * (len - 1.6) / 4.0
		cyl_z(Vector3(0, cy, z), r + 0.03, 0.12, _iron, null, 28)
	box(Vector3(0, cy - r - 0.15, zc), Vector3(1.6, 0.3, len - 1.0), _iron)


## Gondola dressing: ribs on the outside of the walls.
func gondola_ribs(z_rear: float, z_front: float, x_out: float, y0: float, y1: float) -> void:
	var len: float = z_rear - z_front
	var n: int = int(len / 1.6)
	for sx: float in [-1.0, 1.0]:
		for i: int in n + 1:
			var z: float = z_rear - float(i) * len / float(n)
			box(Vector3(sx * (x_out + 0.04), (y0 + y1) * 0.5, z), Vector3(0.08, y1 - y0, 0.12), _iron)


## Cargo dressing on a flatcar deck (never on a landing): stake pockets and chained loads.
func stakes(z_rear: float, z_front: float, y: float, hw: float = 2.0, height: float = 1.2) -> void:
	var len: float = z_rear - z_front
	var n: int = int(len / 2.5)
	for sx: float in [-1.0, 1.0]:
		for i: int in n + 1:
			var z: float = z_rear - 0.4 - float(i) * (len - 0.8) / float(n)
			box(Vector3(sx * (hw + 0.08), y + height * 0.5 - 0.25, z), Vector3(0.14, height + 0.5, 0.14), _timber)


# ---- the locomotive and tender -------------------------------------------------------------------------

## The big 4-6-0 steam locomotive, cab at z_cab_rear going forward. Returns key world points
## {"stack": smokestack top, "whistle": whistle, "cylinders": [left, right] cylinder fronts, "lamp": headlamp}.
## The level builds the collision (running boards, the boiler top, the cab roof).
func locomotive(z_cab_rear: float, cab_len: float, boiler_len: float, boiler_y: float, boiler_r: float, cab_top: float, spots: Dictionary = {}) -> Dictionary:
	var black: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.09), 0.4, 0.5)
	var red: StandardMaterial3D = Look.flat(Color(0.62, 0.1, 0.07), 0.55, 0.2)
	var green: StandardMaterial3D = Look.flat(Color(0.12, 0.3, 0.2), 0.5, 0.3)
	var z_cab_front: float = z_cab_rear - cab_len
	var z_boiler_front: float = z_cab_front - boiler_len
	# the boiler (green with brass bands), smokebox (black) and its round door
	cyl_z(Vector3(0, boiler_y, z_cab_front - boiler_len * 0.42), boiler_r, boiler_len * 0.84, green, null, 28)
	cyl_z(Vector3(0, boiler_y, z_boiler_front + boiler_len * 0.08), boiler_r + 0.06, boiler_len * 0.16, black, null, 28)
	for i: int in 4:
		cyl_z(Vector3(0, boiler_y, z_cab_front - 0.6 - float(i) * boiler_len * 0.24), boiler_r + 0.03, 0.12, _brass, null, 28)
	var door := Look.cylinder(boiler_r * 0.8, 0.12, black, Vector3(0, boiler_y, z_boiler_front - 0.02), -1.0, 24)
	door.rotation.x = PI * 0.5
	_add(door)
	box(Vector3(0, boiler_y, z_boiler_front - 0.1), Vector3(0.12, boiler_r * 1.4, 0.06), _brass)
	# smokestack (a flared balloon stack), sand dome, steam dome, bell, whistle
	var stack_z: float = float(spots.get("stack", z_boiler_front + boiler_len * 0.1))
	var stack_base: float = boiler_y + boiler_r - 0.1
	_add(Look.cylinder(0.45, 2.0, black, Vector3(0, stack_base + 1.0, stack_z), 0.5, 16))
	_add(Look.cylinder(0.55, 1.1, black, Vector3(0, stack_base + 2.55, stack_z), 1.05, 16))
	_add(Look.cylinder(1.08, 0.18, black, Vector3(0, stack_base + 3.15, stack_z), -1.0, 16))
	var sand_z: float = float(spots.get("sand", z_cab_front - boiler_len * 0.55))
	_add(Look.cylinder(0.5, 0.55, _brass, Vector3(0, boiler_y + boiler_r + 0.2, sand_z), 0.42, 16))
	_add(Look.sphere(0.42, _brass, Vector3(0, boiler_y + boiler_r + 0.48, sand_z)))
	var dome_z: float = float(spots.get("dome", z_cab_front - boiler_len * 0.28))
	_add(Look.cylinder(0.5, 0.5, _brass, Vector3(0, boiler_y + boiler_r + 0.18, dome_z), 0.44, 16))
	_add(Look.sphere(0.44, _brass, Vector3(0, boiler_y + boiler_r + 0.43, dome_z)))
	var bell_z: float = float(spots.get("bell", z_cab_front - boiler_len * 0.4))
	if not spots.has("bell"):
		_add(Look.cylinder(0.12, 0.5, _iron, Vector3(0, boiler_y + boiler_r + 0.25, bell_z), -1.0, 8))
		_add(Look.cylinder(0.18, 0.36, _brass, Vector3(0, boiler_y + boiler_r + 0.62, bell_z), 0.3, 14))
	var whistle := Vector3(0.35, boiler_y + boiler_r + 0.5, z_cab_front - 0.5)
	_add(Look.cylinder(0.09, 0.6, _brass, whistle, -1.0, 10))
	# the headlamp box on the smokebox, glowing
	var lamp := Vector3(0, boiler_y + boiler_r + 0.45, z_boiler_front + 0.2)
	box(lamp, Vector3(0.8, 0.75, 0.8), black)
	var glow := Look.cylinder(0.3, 0.06, Look.flat(Color(1.0, 0.9, 0.6), 0.2, 0.0, 4.0), lamp + Vector3(0, 0, -0.42), -1.0, 16)
	glow.rotation.x = PI * 0.5
	_add(glow)
	# the cab: red with black roof edge and glowing windows
	var cab_c := Vector3(0, (cab_top + 1.6) * 0.5, z_cab_rear - cab_len * 0.5)
	for sx: float in [-1.0, 1.0]:
		box(Vector3(sx * 1.62, 3.55, cab_c.z), Vector3(0.05, 1.0, cab_len * 0.55), Look.flat(Color(1.0, 0.75, 0.42), 0.3, 0.0, 1.4))
		box(Vector3(sx * 1.62, 2.4, cab_c.z), Vector3(0.05, 0.12, cab_len), _brass)
	# the pilot (cowcatcher): a wedge of slats
	var cow := CylinderMesh.new()
	cow.top_radius = 0.0
	cow.bottom_radius = 1.5
	cow.height = 1.2
	cow.radial_segments = 3
	cow.rings = 1
	var cw := Look.mesh_node(cow, red, Vector3(0, 0.55, z_boiler_front - 1.6))
	cw.rotation = Vector3(-PI * 0.5, 0, 0)
	cw.scale = Vector3(1.0, 1.0, 0.55)
	_add(cw)
	box(Vector3(0, 1.1, z_boiler_front - 0.7), Vector3(3.0, 0.35, 0.4), red)
	# cylinders and steam chests either side at the front, drive wheels and rods
	var cyl_z0: float = z_boiler_front + 1.0
	var cyls: Array[Vector3] = []
	for sx: float in [-1.0, 1.0]:
		cyl_z(Vector3(sx * 1.25, 1.1, cyl_z0), 0.5, 1.6, black, null, 16)
		box(Vector3(sx * 1.25, 1.75, cyl_z0), Vector3(0.7, 0.5, 1.4), black)
		cyls.append(Vector3(sx * 1.25, 0.8, cyl_z0 - 0.85))
	# pilot truck (small wheels) and three big drivers each side
	for dz: float in [-0.9, 0.0]:
		wheelset(Vector3(0, 0.45, cyl_z0 + dz - 0.2), 0.45, 1.5)
	var drv_r: float = 0.95
	var d0: float = cyl_z0 + 2.2
	for i: int in 3:
		var ws: Node3D = wheelset(Vector3(0, drv_r, d0 + float(i) * 2.15), drv_r, 2.2)
		# red driver centres, counterweights
		for sx: float in [-1.0, 1.0]:
			var hub := Look.cylinder(drv_r * 0.82, 0.16, red, Vector3(sx * 1.1, 0, 0), -1.0, 20)
			hub.rotation.z = PI * 0.5
			ws.add_child(hub)
			ws.add_child(Look.box(Vector3(0.18, drv_r * 0.5, drv_r * 0.7), black, Vector3(sx * 1.2, drv_r * 0.45, 0)))
	box(Vector3(0, 1.35, (d0 + z_cab_rear) * 0.5), Vector3(1.2, 0.5, absf(z_cab_rear - cyl_z0)), black)
	# the tender truck wheels under the cab end
	return {"stack": Vector3(0, stack_base + 3.3, stack_z), "whistle": whistle + Vector3(0, 0.35, 0),
		"cylinders": cyls, "lamp": lamp, "drivers_z": d0, "drv_r": drv_r}


## The side rods that link the drive wheels (parented under `node`, animated by the level).
func side_rods(z0: float, spacing: float, drv_r: float) -> Array[Node3D]:
	var rods: Array[Node3D] = []
	var red_rod: StandardMaterial3D = Look.flat(Color(0.75, 0.72, 0.7), 0.25, 0.9)
	for sx: float in [-1.0, 1.0]:
		var rod := Node3D.new()
		rod.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		rod.position = Vector3(sx * 1.32, drv_r, z0 + spacing)
		_add(rod)
		rod.add_child(Look.box(Vector3(0.1, 0.16, spacing * 2.0 + 0.4), red_rod))
		rod.set_meta("side", sx)
		rods.append(rod)
	return rods


# ---- the trestle and the moving canyon ---------------------------------------------------------------

## The trestle under the whole train from z_front (-) to z_back (+): deck, rails and guard timbers
## (static: they look the same wherever you are), with sleepers and the tall timber bents sliding
## back under it.
func trestle(z_front: float, z_back: float) -> void:
	var len: float = z_back - z_front
	var zc: float = (z_front + z_back) * 0.5
	var steel: StandardMaterial3D = Look.flat(Color(0.5, 0.48, 0.46), 0.3, 0.9)
	for sx: float in [-1.0, 1.0]:
		box(Vector3(sx * 0.75, 0.08, zc), Vector3(0.12, 0.16, len), steel)
		box(Vector3(sx * 2.6, -0.1, zc), Vector3(0.3, 0.3, len), _timber)
	box(Vector3(0, -0.5, zc), Vector3(5.6, 0.4, len), Look.flat(TIMBER.darkened(0.25), 0.95))
	# sleepers: one multimesh repeating every 0.8 m, slid back
	var ties := FrontierScroll.make(0.8)
	_add(ties)
	var tm := BoxMesh.new()
	tm.size = Vector3(3.0, 0.2, 0.32)
	var n: int = int(len / 0.8) + 2
	var xfs: Array[Transform3D] = []
	for i: int in n:
		xfs.append(Transform3D(Basis.IDENTITY, Vector3(0, -0.1, z_front - 0.8 + float(i) * 0.8)))
	_multi(ties, tm, Look.flat(Color(0.26, 0.19, 0.13), 0.95), xfs)
	# bents: battered timber towers every 7.5 m down to the canyon floor
	var bents := FrontierScroll.make(7.5)
	_add(bents)
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var bx: Array[Transform3D] = []
	var depth: float = -CANYON_FLOOR
	var nb: int = int(len / 7.5) + 2
	for i: int in nb:
		var z: float = z_front - 7.5 + float(i) * 7.5
		# cap timber
		bx.append(Transform3D(Basis.IDENTITY.scaled(Vector3(6.0, 0.5, 0.6)), Vector3(0, -0.95, z)))
		# four posts: two plumb, two battered outward
		for sx: float in [-1.0, 1.0]:
			bx.append(_beam(Vector3(sx * 1.0, -1.2, z), Vector3(sx * 1.6, CANYON_FLOOR, z), 0.45))
			bx.append(_beam(Vector3(sx * 2.7, -1.2, z), Vector3(sx * 9.0, CANYON_FLOOR, z), 0.45))
		# girts and X-braces between them, every 10 m down
		var y: float = -10.0
		while y > CANYON_FLOOR + 4.0:
			var spread: float = 2.7 + (6.3 * (-y / depth))
			bx.append(Transform3D(Basis.IDENTITY.scaled(Vector3(spread * 2.0 + 0.6, 0.35, 0.35)), Vector3(0, y, z)))
			var y2: float = y + 10.0 if y + 10.0 < -1.5 else -1.5
			var sp2: float = 2.7 + (6.3 * (-y2 / depth))
			bx.append(_beam(Vector3(-spread, y, z), Vector3(sp2, y2, z), 0.25))
			bx.append(_beam(Vector3(spread, y, z), Vector3(-sp2, y2, z), 0.25))
			y -= 10.0
	_multi(bents, unit, Look.flat(TIMBER.darkened(0.1), 0.95), bx)


## A unit-cube transform stretched into a square beam from a to b.
func _beam(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var d: Vector3 = b - a
	var l: float = d.length()
	var up: Vector3 = d / maxf(l, 0.001)
	var side: Vector3 = up.cross(Vector3(0, 0, 1))
	if side.length() < 0.001:
		side = up.cross(Vector3(1, 0, 0))
	side = side.normalized()
	var fwd: Vector3 = side.cross(up)
	return Transform3D(Basis(side * thick, up * l, fwd * thick), (a + b) * 0.5)


func _multi(parent: Node3D, mesh: Mesh, mat: Material, xfs: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


## Telegraph poles along the left edge of the trestle with their wires (wires static: they look the
## same all along), the poles sliding back every `spacing` metres.
func telegraph(z_front: float, z_back: float, x: float = -3.9, spacing: float = 40.0) -> void:
	var line := FrontierScroll.make(spacing)
	_add(line)
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var xfs: Array[Transform3D] = []
	var n: int = int((z_back - z_front) / spacing) + 3
	for i: int in n:
		var z: float = z_front - spacing + float(i) * spacing
		xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.28, 22.0, 0.28)), Vector3(x, -1.0, z)))
		xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.2, 0.16, 0.16)), Vector3(x, 9.4, z)))
		xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.6, 0.14, 0.14)), Vector3(x, 8.6, z)))
	_multi(line, unit, Look.flat(Color(0.3, 0.22, 0.16), 0.9), xfs)
	var wire: StandardMaterial3D = Look.flat(Color(0.1, 0.1, 0.1), 0.6)
	for dx: float in [-0.95, -0.35, 0.35, 0.95]:
		box(Vector3(x + dx, 9.55, (z_front + z_back) * 0.5), Vector3(0.03, 0.03, z_back - z_front + spacing * 2.0), wire)
	for dx2: float in [-0.7, 0.7]:
		box(Vector3(x + dx2, 8.72, (z_front + z_back) * 0.5), Vector3(0.03, 0.03, z_back - z_front + spacing * 2.0), wire)


## The gorge the trestle crosses: the river floor far below, red-rock walls either side (their rock
## sliding back), and fields of hoodoos, buttes, boulders and saguaros sliding past on the floor and
## along the rims. `mid` is the middle of the train; `half` how far either way to build.
func canyon(mid: float, half: float) -> void:
	var len: float = half * 2.0 + 400.0
	# the river floor
	var gm := ShaderMaterial.new()
	gm.shader = GROUND_SHADER
	scroll_mats.append({"mat": gm, "period": 0.0})
	var plane := PlaneMesh.new()
	plane.size = Vector2(700.0, len)
	plane.subdivide_depth = 0
	var floor_mi := Look.mesh_node(plane, gm, Vector3(0, CANYON_FLOOR, mid))
	_add(floor_mi)
	# the walls: the near (sunward) rim low enough to let the low sun in, the far wall towering and lit
	var wall_mat: ShaderMaterial = rock(0.0)
	box(Vector3(-118.0, CANYON_FLOOR + 34.0, mid), Vector3(80.0, 68.0, len), wall_mat)
	box(Vector3(-190.0, CANYON_FLOOR + 50.0, mid), Vector3(80.0, 100.0, len), wall_mat)
	box(Vector3(120.0, CANYON_FLOOR + 55.0, mid), Vector3(80.0, 110.0, len), wall_mat)
	box(Vector3(190.0, CANYON_FLOOR + 85.0, mid), Vector3(80.0, 170.0, len), wall_mat)
	# a ledge of scree along the foot of each wall
	box(Vector3(-74.0, CANYON_FLOOR + 3.0, mid), Vector3(14.0, 6.0, len), wall_mat)
	box(Vector3(76.0, CANYON_FLOOR + 4.0, mid), Vector3(16.0, 8.0, len), wall_mat)
	# buttresses and fins jutting out of the walls, sliding past (repeat every 150 m)
	var fins := FrontierScroll.make(150.0)
	_add(fins)
	var fin_mat: ShaderMaterial = rock(150.0)
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var fx: Array[Transform3D] = []
	var reps: int = int(len / 150.0) + 2
	var pattern: Array[Vector4] = []
	for k: int in 7:
		var sx: float = -1.0 if k % 2 == 0 else 1.0
		pattern.append(Vector4(sx * rng.randf_range(66.0, 80.0), rng.randf_range(0.0, 150.0), rng.randf_range(14.0, 26.0), rng.randf_range(30.0, 90.0)))
	for r: int in reps:
		for p: Vector4 in pattern:
			var z: float = mid - len * 0.5 + float(r) * 150.0 + p.y
			var top: float = CANYON_FLOOR + p.w
			if p.x < 0.0:
				top = minf(top, CANYON_FLOOR + 66.0)
			fx.append(Transform3D(Basis.IDENTITY.scaled(Vector3(p.z, top - CANYON_FLOOR, p.z * 1.4)), Vector3(p.x, (top + CANYON_FLOOR) * 0.5, z)))
	_multi(fins, unit, fin_mat, fx)
	# hoodoos and boulders on the floor, saguaros along the rims (repeat every 200 m)
	var field := FrontierScroll.make(200.0)
	_add(field)
	var hood_mat: ShaderMaterial = rock(200.0, 0.3)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.55
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 9
	cone.rings = 1
	var cap := SphereMesh.new()
	cap.radius = 0.5
	cap.height = 0.6
	cap.radial_segments = 10
	cap.rings = 5
	var hx: Array[Transform3D] = []
	var hc: Array[Transform3D] = []
	var boulders: Array[Transform3D] = []
	var reps2: int = int(len / 200.0) + 2
	var spots: Array[Vector4] = []
	for k: int in 26:
		var sx: float = -1.0 if rng.randf() < 0.5 else 1.0
		spots.append(Vector4(sx * rng.randf_range(18.0, 64.0), rng.randf_range(0.0, 200.0), rng.randf_range(4.0, 9.0), rng.randf_range(10.0, 34.0)))
	for r: int in reps2:
		for s: Vector4 in spots:
			var z: float = mid - len * 0.5 + float(r) * 200.0 + s.y
			var h: float = s.w
			hx.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s.z, h, s.z)), Vector3(s.x, CANYON_FLOOR + h * 0.5, z)))
			# a balanced cap rock on top
			hc.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s.z * 1.5, s.z * 0.9, s.z * 1.5)), Vector3(s.x, CANYON_FLOOR + h + s.z * 0.15, z)))
			boulders.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s.z * 0.7, s.z * 0.4, s.z * 0.6)), Vector3(s.x + s.z * 1.6, CANYON_FLOOR + s.z * 0.15, z + s.z)))
	_multi(field, cone, hood_mat, hx)
	_multi(field, cap, Look.flat(Color(0.5, 0.26, 0.16), 0.95), hc)
	_multi(field, unit, hood_mat, boulders)
	_saguaros(field, mid, len, reps2)


func _saguaros(field: Node3D, mid: float, len: float, reps: int) -> void:
	var green: StandardMaterial3D = Look.flat(Color(0.26, 0.4, 0.2), 0.85)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	var xs: Array[Transform3D] = []
	var spots: Array[Vector3] = []
	for k: int in 12:
		var sx: float = -1.0 if rng.randf() < 0.65 else 1.0
		var x: float = sx * rng.randf_range(78.0, 150.0) if sx < 0.0 else rng.randf_range(20.0, 60.0)
		var y: float = CANYON_FLOOR + 68.0 if sx < 0.0 else CANYON_FLOOR
		if sx < 0.0 and x < -158.0:
			y = CANYON_FLOOR + 100.0
		spots.append(Vector3(x, y, rng.randf_range(0.0, 200.0)))
	for r: int in reps:
		for s: Vector3 in spots:
			var z: float = mid - len * 0.5 + float(r) * 200.0 + s.z
			var h: float = 7.0
			xs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, h, 1.0)), Vector3(s.x, s.y + h * 0.5, z)))
			# two arms: out then up
			for side: float in [-1.0, 1.0]:
				var ay: float = s.y + h * (0.45 if side < 0.0 else 0.6)
				xs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 0.7, 0.7)), Vector3(s.x + side * 0.9, ay, z)))
				xs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.75, 2.4, 0.75)), Vector3(s.x + side * 1.45, ay + 1.15, z)))
	_multi(field, cyl, green, xs)


## A distant water tower on the rim (a cartoon landmark) at a fixed spot in a scrolling field.
func water_tower(parent: Node3D, at: Vector3, s: float = 1.0) -> void:
	var t := Node3D.new()
	t.position = at
	parent.add_child(t)
	var leg: StandardMaterial3D = Look.flat(Color(0.3, 0.22, 0.15), 0.9)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			t.add_child(Look.box(Vector3(0.4, 9.0, 0.4) * s, leg, Vector3(sx * 2.2, 4.5, sz * 2.2) * s))
	t.add_child(Look.cylinder(3.2 * s, 5.0 * s, Look.flat(Color(0.55, 0.36, 0.22), 0.85), Vector3(0, 11.5, 0) * s, -1.0, 16))
	t.add_child(Look.cylinder(3.5 * s, 2.0 * s, Look.flat(Color(0.24, 0.2, 0.18), 0.8), Vector3(0, 15.0, 0) * s, 0.3 * s, 16))
	for y: float in [9.8, 11.5, 13.2]:
		t.add_child(Look.cylinder(3.25 * s, 0.14 * s, _iron, Vector3(0, y, 0) * s, -1.0, 16))
