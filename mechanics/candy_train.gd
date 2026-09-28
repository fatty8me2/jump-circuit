class_name CandyTrain
extends Node3D
## Sugar Rush set piece: a toy railway. A closed loop of candy-cane rails on licorice sleepers,
## carried on striped trestles, with `trains` little trains running round it on the course clock:
## a steam engine puffing pink steam and `wagons` flat cake wagons behind it. The wagons' frosted
## decks are rideable moving platforms (level with the station platforms beside the track), so you
## step aboard as one rolls past, ride it, and hop off (or across to another train) further on.
## Every car is a pure function of Game.course_time (arc distance = speed * t + offset), like every
## mover: the ride is identical every time and for every racer.
## Build: set `path` (a closed polyline in this node's space, at DECK-TOP height; see stadium()),
## then add it. The node itself must not be rotated or scaled (cars report offsets in its space).

@export var path: PackedVector3Array = PackedVector3Array()
@export var speed: float = 7.0
@export var trains: int = 3
@export var wagons: int = 3
## Arc distance of the first train's engine at t = 0.
@export var offset: float = 0.0
@export var engine_color: Color = Color(1.0, 0.35, 0.55)
@export var wagon_colors: PackedColorArray = PackedColorArray([Color(0.45, 0.85, 1.0), Color(1.0, 0.85, 0.3), Color(0.6, 1.0, 0.7)])
## Height of the deck above the rails.
@export var deck: float = 1.25
## Sea / ground level the trestles stand in (world y).
@export var ground_y: float = -30.0
@export var trestles: bool = true

const CAR_LEN: float = 4.4
const ENGINE_LEN: float = 4.8
const GAP: float = 0.7
const DECK_W: float = 2.6

var _cum: PackedFloat32Array = PackedFloat32Array()
var _len: float = 0.0
var cars: Array[Car] = []
## Rideable wagons only (engines excluded), per train.
var wagons_by_train: Array = []
var _whistled: Array[int] = []
## Arc distance where the whistle blows (before the station), -1 = never.
var whistle_at: float = -1.0


func _ready() -> void:
	_bake()
	_build_track()
	for j: int in trains:
		var list: Array = []
		var s0: float = offset + _len * float(j) / float(trains)
		var e := Car.new()
		e.train = self
		e.back = 0.0
		e.base = s0
		e.is_engine = true
		e.tint = engine_color
		add_child(e)
		cars.append(e)
		var back: float = ENGINE_LEN * 0.5 + GAP + CAR_LEN * 0.5
		for i: int in wagons:
			var w := Car.new()
			w.train = self
			w.base = s0
			w.back = back
			w.tint = wagon_colors[(i + j) % wagon_colors.size()]
			add_child(w)
			cars.append(w)
			list.append(w)
			back += CAR_LEN + GAP
		wagons_by_train.append(list)
		_whistled.append(-999999)


## Total loop length (m).
func length() -> float:
	return _len


func _bake() -> void:
	_cum.resize(path.size() + 1)
	_cum[0] = 0.0
	var total: float = 0.0
	for i: int in path.size():
		var a: Vector3 = path[i]
		var b: Vector3 = path[(i + 1) % path.size()]
		total += a.distance_to(b)
		_cum[i + 1] = total
	_len = maxf(total, 0.01)


## Position on the loop (this node's space) at arc distance `s`.
func point_at(s: float) -> Vector3:
	var d: float = fposmod(s, _len)
	var lo: int = 0
	var hi: int = path.size()
	while hi - lo > 1:
		var mid: int = (lo + hi) >> 1
		if _cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg: float = _cum[lo + 1] - _cum[lo]
	var k: float = 0.0 if seg <= 0.0 else (d - _cum[lo]) / seg
	return path[lo].lerp(path[(lo + 1) % path.size()], k)


## Unit heading of the loop at arc distance `s`.
func heading_at(s: float) -> Vector3:
	var d: Vector3 = point_at(s + 0.8) - point_at(s - 0.8)
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## Arc distance of the point on the loop nearest to local point `p` (coarse, for set-up).
func nearest_s(p: Vector3) -> float:
	var best: float = 0.0
	var bd: float = INF
	var s: float = 0.0
	while s < _len:
		var d: float = point_at(s).distance_squared_to(p)
		if d < bd:
			bd = d
			best = s
		s += 0.25
	return best


func _process(_dt: float) -> void:
	if whistle_at < 0.0:
		return
	var t: float = Game.course_time
	for j: int in trains:
		var s: float = speed * t + offset + _len * float(j) / float(trains)
		var lap: int = int(floor((s - whistle_at) / _len))
		if lap != _whistled[j]:
			if _whistled[j] != -999999:
				var p: Vector3 = to_global(point_at(s))
				# SOUND: the engine's whistle as it runs into the station
				WorldAudio.at(self, "candy_train_whistle", p, 1.0, 90.0)
			_whistled[j] = lap


# ---- the railway ------------------------------------------------------------------------

func _build_track() -> void:
	var red: StandardMaterial3D = Look.flat(Color(1.0, 0.2, 0.3), 0.3, 0.1)
	var white: StandardMaterial3D = Look.flat(Color(1.0, 0.97, 0.95), 0.3, 0.1)
	var licorice: StandardMaterial3D = Look.flat(Color(0.12, 0.06, 0.1), 0.35)
	var rail_y: float = -deck
	var seg: float = 1.0
	var n: int = int(_len / seg)
	# rails: striped red and white (alternate metres), two per side of the gauge
	var rails_a: Array[Transform3D] = []
	var rails_b: Array[Transform3D] = []
	var sleepers: Array[Transform3D] = []
	var legs: Array[Transform3D] = []
	for i: int in n:
		var s: float = (float(i) + 0.5) * seg
		var c: Vector3 = point_at(s) + Vector3(0, rail_y, 0)
		var f: Vector3 = heading_at(s)
		var side: Vector3 = Vector3(-f.z, 0, f.x).normalized()
		var basis := Basis(side, Vector3.UP, -f).orthonormalized()
		# pitch the rail with the grade
		var up: Vector3 = side.cross(f).normalized() * -1.0
		if up.y < 0.0:
			up = -up
		basis = Basis(side, up, side.cross(up)).orthonormalized()
		for sx: float in [-0.75, 0.75]:
			var xf := Transform3D(basis, c + side * sx)
			if i % 2 == 0:
				rails_a.append(xf)
			else:
				rails_b.append(xf)
		if i % 1 == 0:
			sleepers.append(Transform3D(basis, c - up * 0.14))
		if trestles and i % 9 == 4:
			var top: Vector3 = c - Vector3(0, 0.3, 0)
			var h: float = top.y + global_position.y - ground_y
			if h > 1.0:
				legs.append(Transform3D(Basis().scaled(Vector3(1.0, h, 1.0)), top - Vector3(0, h * 0.5, 0)))
	_multi(_box(Vector3(0.14, 0.16, seg * 1.02)), red, rails_a)
	_multi(_box(Vector3(0.14, 0.16, seg * 1.02)), white, rails_b)
	_multi(_box(Vector3(2.3, 0.14, 0.42)), licorice, sleepers)
	if not legs.is_empty():
		var cm := CylinderMesh.new()
		cm.top_radius = 0.34
		cm.bottom_radius = 0.42
		cm.height = 1.0
		cm.radial_segments = 10
		cm.rings = 1
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://visual/candy_stripe.gdshader")
		sm.set_shader_parameter("color_a", Color(1.0, 0.25, 0.4))
		sm.set_shader_parameter("color_b", Color(1.0, 0.97, 0.95))
		sm.set_shader_parameter("stripes", 3.0)
		sm.set_shader_parameter("twist", 1.2)
		sm.set_shader_parameter("world_twist", true)
		_multi(cm, sm, legs)
		# a cross-beam of wafer under the sleepers at every trestle
		var beams: Array[Transform3D] = []
		for xf: Transform3D in legs:
			var top2: Vector3 = xf.origin + Vector3(0, xf.basis.get_scale().y * 0.5, 0)
			beams.append(Transform3D(Basis(), top2 + Vector3(0, 0.05, 0)))
		_multi(_box(Vector3(0.9, 0.2, 0.9)), Look.flat(Color(0.95, 0.75, 0.45), 0.8), beams)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _multi(mesh: Mesh, mat: Material, xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


## A rounded-rectangle loop at deck height: the ride straight from `a` along `f` for `ride` m (the
## part you ride), a quarter-turn of radius `r` toward `side` (+1 = right of `f`), across the far
## end, back along the return edge (`width` m to that side, lifted `hill` m in its middle with smooth
## ramps) and round to `a`. Every such loop with the same ride / width / r has the same length.
static func rect(a: Vector3, f: Vector3, ride: float, width: float, side: float, r: float, hill: float = 0.0, step: float = 0.5) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var fw: Vector3 = Vector3(f.x, 0, f.z).normalized()
	var rt: Vector3 = Vector3(-fw.z, 0, fw.x) * side
	var cross: float = maxf(width - 2.0 * r, 0.0)
	var na: int = maxi(int(PI * 0.5 * r / step), 6)
	var nl: int = maxi(int(ride / step), 1)
	var nc: int = maxi(int(cross / step), 1)
	# 1: the ride straight
	for i: int in nl:
		pts.append(a + fw * ride * float(i) / float(nl))
	var e1: Vector3 = a + fw * ride
	# 2: quarter-turn toward the side
	var c2: Vector3 = e1 + rt * r
	for i: int in na:
		var g: float = PI * 0.5 * float(i) / float(na)
		pts.append(c2 - rt * r * cos(g) + fw * r * sin(g))
	# 3: across the far end
	var s3: Vector3 = c2 + fw * r
	for i: int in nc:
		pts.append(s3 + rt * cross * float(i) / float(nc))
	var e3: Vector3 = s3 + rt * cross
	# 4: quarter-turn back
	var c4: Vector3 = e3 - fw * r
	for i: int in na:
		var g2: float = PI * 0.5 * float(i) / float(na)
		pts.append(c4 + fw * r * cos(g2) + rt * r * sin(g2))
	# 5: the return edge, with its hump
	var s5: Vector3 = c4 + rt * r
	for i: int in nl:
		var k: float = float(i) / float(nl)
		var hump: float = sin(PI * k)
		pts.append(s5 - fw * ride * k + Vector3(0, hill * hump * hump, 0))
	var e5: Vector3 = s5 - fw * ride
	# 6: quarter-turn toward the start
	var c6: Vector3 = e5 - rt * r
	for i: int in na:
		var g3: float = PI * 0.5 * float(i) / float(na)
		pts.append(c6 + rt * r * cos(g3) - fw * r * sin(g3))
	# 7: across the near end
	var s7: Vector3 = c6 - fw * r
	for i: int in nc:
		pts.append(s7 - rt * cross * float(i) / float(nc))
	var e7: Vector3 = s7 - rt * cross
	# 8: the last quarter-turn back onto the ride straight
	var c8: Vector3 = e7 + fw * r
	for i: int in na:
		var g4: float = PI * 0.5 * float(i) / float(na)
		pts.append(c8 - fw * r * cos(g4) - rt * r * sin(g4))
	return pts


## A stadium-shaped loop at deck height: the straight from `a` to `b` (the part you ride), a
## half-turn of `radius` toward `side` (+1 = right of the a->b heading), the return straight
## (lifted `hill` m in the middle with smooth ramps), and the half-turn back to `a`.
static func stadium(a: Vector3, b: Vector3, side: float, radius: float, hill: float = 0.0, step: float = 0.5) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var f: Vector3 = Vector3(b.x - a.x, 0, b.z - a.z)
	var l: float = f.length()
	f = f.normalized()
	var r: Vector3 = Vector3(-f.z, 0, f.x) * side
	var n: int = maxi(int(l / step), 1)
	for i: int in n:
		pts.append(a.lerp(b, float(i) / float(n)))
	# the far half-turn, round the centre b + r * radius
	var c1: Vector3 = b + r * radius
	var na: int = maxi(int(PI * radius / step), 8)
	for i: int in na:
		var ang: float = PI * float(i) / float(na)
		pts.append(c1 - r * radius * cos(ang) + f * radius * sin(ang))
	# the return straight (b + 2r .. a + 2r), with a hump
	var rb: Vector3 = b + r * radius * 2.0
	var ra: Vector3 = a + r * radius * 2.0
	for i: int in n:
		var k: float = float(i) / float(n)
		var hump: float = sin(PI * k)
		pts.append(rb.lerp(ra, k) + Vector3(0, hill * hump * hump, 0))
	var c2: Vector3 = a + r * radius
	for i: int in na:
		var ang2: float = PI * float(i) / float(na)
		pts.append(c2 + r * radius * cos(ang2) - f * radius * sin(ang2))
	return pts


# ---- a car ---------------------------------------------------------------------------------

class Car extends MovingPlatform:
	var train: CandyTrain
	## Arc distance of this train's engine at t = 0, and how far behind the engine this car rides.
	var base: float = 0.0
	var back: float = 0.0
	var is_engine: bool = false
	var tint: Color = Color.WHITE
	var _steam: GPUParticles3D
	var _sparkle: GPUParticles3D
	var _chug: AudioStreamPlayer3D

	func _ready() -> void:
		sync_to_physics = false
		collision_layer = 1
		collision_mask = 0
		_origin = Vector3.ZERO
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		if is_engine:
			box.size = Vector3(DECK_W - 0.2, 1.6, ENGINE_LEN)
			cs.position = Vector3(0, 0.55, 0)
		else:
			box.size = Vector3(DECK_W, 0.5, CAR_LEN)
			cs.position = Vector3(0, -0.25, 0)
		cs.shape = box
		add_child(cs)
		if is_engine:
			_build_engine()
		else:
			_build_wagon()
		_pose(Game.course_time)
		reset_physics_interpolation()
		add_to_group("course_clock")

	func _hums() -> bool:
		return false

	func arc_at(time: float) -> float:
		return train.speed * time + base - back

	func offset_at(time: float) -> Vector3:
		return train.point_at(arc_at(time))

	func snap_to_clock() -> void:
		_pose(Game.course_time)
		reset_physics_interpolation()

	func _physics_process(_dt: float) -> void:
		_pose(Game.course_time)

	func _pose(time: float) -> void:
		var s: float = arc_at(time)
		var f: Vector3 = train.heading_at(s)
		var flat := Vector3(f.x, 0, f.z)
		var yaw: float = atan2(-flat.x, -flat.z)
		var pitch: float = clampf(asin(clampf(f.y, -1.0, 1.0)), -0.4, 0.4)
		transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), offset_at(time))

	func _wheels(len: float) -> void:
		var disc: ShaderMaterial = CandyDecor.swirl_material(Color(1.0, 0.2, 0.3), Color(1.0, 0.97, 0.95), 4.0)
		for sx: float in [-1.0, 1.0]:
			for z: float in [-len * 0.3, len * 0.3]:
				var w := Look.cylinder(0.45, 0.16, disc, Vector3(sx * (DECK_W * 0.5 - 0.05), -train.deck + 0.45, z), -1.0, 20)
				w.rotation.z = PI * 0.5
				add_child(w)
		add_child(Look.box(Vector3(DECK_W - 0.6, 0.35, len - 0.6), Look.flat(Color(0.2, 0.12, 0.16), 0.5), Vector3(0, -0.72, 0)))

	func _build_wagon() -> void:
		var deck_box := Look.platform_box(Vector3(DECK_W, 0.5, CAR_LEN), "mover")
		deck_box.position = Vector3(0, -0.25, 0)
		add_child(deck_box)
		# painted side skirts in the wagon's colour with a frosting scallop along the top
		for sx: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.08, 0.42, CAR_LEN - 0.2), Look.flat(tint, 0.5), Vector3(sx * (DECK_W * 0.5 + 0.04), -0.62, 0)))
			for i: int in 6:
				var z: float = -CAR_LEN * 0.5 + 0.4 + float(i) * (CAR_LEN - 0.8) / 5.0
				var bead := Look.sphere(0.12, Look.flat(Color(1.0, 0.97, 0.98), 0.7), Vector3(sx * (DECK_W * 0.5 + 0.06), -0.45, z))
				bead.scale = Vector3(0.6, 1.0, 1.0)
				add_child(bead)
		_wheels(CAR_LEN)
		_sparkle = Fx.emitter({"amount": 16, "lifetime": 1.2, "fixed_fps": 0, "shape": "box", "extents": Vector3(1.2, 0.1, 0.2),
			"speed": Vector2(0.0, 0.4), "spread": 180.0, "gravity": Vector3(0, -0.8, 0), "tex": Fx.Tex.STAR, "size": 0.22,
			"curve": "pop", "color": Fx.hot(tint.lightened(0.3), 1.8), "aabb": AABB(Vector3(-400, -100, -400), Vector3(800, 200, 800))})
		_sparkle.position = Vector3(0, -0.9, CAR_LEN * 0.5)
		add_child(_sparkle)

	func _build_engine() -> void:
		var body: StandardMaterial3D = Look.flat(tint, 0.4, 0.1)
		var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.3), 0.25, 0.9, 0.2)
		var mint: StandardMaterial3D = Look.flat(Color(0.55, 0.95, 0.8), 0.5)
		var cream: StandardMaterial3D = Look.flat(Color(1.0, 0.96, 0.9), 0.6)
		# footplate
		add_child(Look.box(Vector3(DECK_W, 0.4, ENGINE_LEN), mint, Vector3(0, -0.2, 0)))
		# the boiler, front, and the cab at the back (its roof is the top of the collision box)
		var boiler := Look.cylinder(0.85, ENGINE_LEN * 0.62, body, Vector3(0, 0.8, -ENGINE_LEN * 0.14), -1.0, 20)
		boiler.rotation.x = PI * 0.5
		add_child(boiler)
		for i: int in 3:
			var band := Look.cylinder(0.88, 0.1, gold, Vector3(0, 0.8, -ENGINE_LEN * 0.4 + float(i) * 0.8), -1.0, 20)
			band.rotation.x = PI * 0.5
			add_child(band)
		var face := Look.cylinder(0.7, 0.08, cream, Vector3(0, 0.8, -ENGINE_LEN * 0.45 - 0.05), -1.0, 20)
		face.rotation.x = PI * 0.5
		add_child(face)
		add_child(Look.sphere(0.2, Look.flat(Color(1.0, 0.95, 0.6), 0.2, 0.0, 3.0), Vector3(0, 1.1, -ENGINE_LEN * 0.5 - 0.02)))
		add_child(Look.box(Vector3(DECK_W - 0.2, 1.6, 1.5), body, Vector3(0, 0.55, ENGINE_LEN * 0.5 - 0.75)))
		add_child(Look.box(Vector3(DECK_W + 0.1, 0.16, 1.8), cream, Vector3(0, 1.4, ENGINE_LEN * 0.5 - 0.8)))
		for sx: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.05, 0.6, 0.7), Look.flat(Color(0.7, 0.9, 1.0), 0.1, 0.3, 0.6), Vector3(sx * (DECK_W * 0.5 - 0.08), 0.8, ENGINE_LEN * 0.5 - 0.75)))
		# chimney (a striped candy stack) and a gold dome
		var stack := Look.cylinder(0.26, 0.9, gold, Vector3(0, 1.85, -ENGINE_LEN * 0.32), 0.4, 12)
		add_child(stack)
		add_child(Look.sphere(0.3, gold, Vector3(0, 1.62, -ENGINE_LEN * 0.02)))
		# the cowcatcher: a wedge of wafer
		var cow := CylinderMesh.new()
		cow.top_radius = 0.0
		cow.bottom_radius = 1.1
		cow.height = 0.8
		cow.radial_segments = 3
		cow.rings = 1
		var cw := Look.mesh_node(cow, Look.flat(Color(0.95, 0.75, 0.45), 0.8), Vector3(0, -0.45, -ENGINE_LEN * 0.5 - 0.2))
		cw.rotation = Vector3(-PI * 0.5, 0, 0)
		cw.scale = Vector3(1.0, 1.0, 0.5)
		add_child(cw)
		_wheels(ENGINE_LEN)
		# pink steam puffing from the stack (world space: it trails behind the train)
		_steam = Fx.emitter({"amount": 26, "lifetime": 2.2, "fixed_fps": 0, "shape": "sphere", "radius": 0.2,
			"dir": Vector3.UP, "spread": 15.0, "speed": Vector2(2.5, 4.0), "gravity": Vector3(0, 0.6, 0),
			"damping": Vector2(1.0, 1.6), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.3, "curve": "puff",
			"angle": Vector2(0, 360), "spin": Vector2(-40, 40),
			"pick": PackedColorArray([Color(1.0, 0.8, 0.9, 0.8), Color(1.0, 0.95, 1.0, 0.8), Color(0.85, 0.9, 1.0, 0.8)]),
			"fade": PackedFloat32Array([0.0, 0.8, 0.5, 0.0]), "aabb": AABB(Vector3(-400, -100, -400), Vector3(800, 200, 800))})
		_steam.position = Vector3(0, 2.4, -ENGINE_LEN * 0.32)
		add_child(_steam)
		_chug = WorldAudio.loop("candy_train_chug", self, -6.0, 30.0, 5.0)
