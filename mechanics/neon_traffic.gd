class_name NeonTraffic
extends Node3D
## Neon City hover-car traffic: one lane of flying cars streaming round a closed loop on the
## course clock (arc distance = speed * t + offset), like Sugar Rush's toy trains. Every car is a
## pure function of Game.course_time, so a ride is identical every time and for every racer.
##  * Rideable lanes: each car's flat roof is a moving platform (a MovingPlatform, so a rider
##    keeps its full velocity); cars never pitch or roll, and they never teleport (the loop is
##    closed and seamless).
##  * Crossing lanes (`deadly`): the cars cut across the course and a car that touches you is a
##    hazard hit. Each crossing gets signal posts that flash red and a horn that sounds about a
##    second before the next car arrives (see add_crossing()).
## Build: set `path` (a closed polyline in WORLD space at ROOF-TOP height; see lane()), then add
## the node at the origin, unrotated.

@export var path: PackedVector3Array = PackedVector3Array()
@export var speed: float = 8.0
@export var cars: int = 4
## Arc distance of the first car at t = 0.
@export var offset: float = 0.0
@export var deadly: bool = false
@export var palette: PackedColorArray = PackedColorArray([Color(1.0, 0.2, 0.7), Color(0.1, 0.95, 0.85), Color(1.0, 0.62, 0.12)])
## Lane marker lights along the loop (the stretches where the lane is seen).
@export var markers: bool = true
## Hover trucks instead of cars: a hull 2.4 m deep (crossing traffic you cannot hop over).
@export var tall: bool = false

const CAR_LEN: float = 4.6
const CAR_W: float = 2.5
## Roof slab thickness; the hull hangs below it.
const ROOF_T: float = 0.5
const HULL_H: float = 1.0

var _cum: PackedFloat32Array = PackedFloat32Array()
var _len: float = 0.0
var car_nodes: Array[Car] = []
## Crossings: {"s": arc distance, "p": world point, "lamps": [MeshInstance3D], "light": OmniLight3D, "warned": int}
var _crossings: Array[Dictionary] = []
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D


func _ready() -> void:
	_bake()
	if markers:
		_build_markers()
	for i: int in cars:
		var c := Car.new()
		c.lane = self
		c.base = offset + _len * float(i) / float(cars)
		c.tint = palette[i % palette.size()]
		add_child(c)
		car_nodes.append(c)
	_lamp_on = Look.flat(Color(1.0, 0.12, 0.1), 0.3, 0.0, 4.0)
	_lamp_off = Look.flat(Color(0.25, 0.05, 0.05), 0.5)


func length() -> float:
	return _len


## Depth of a car's hull under its roof slab.
func hull() -> float:
	return 2.4 if tall else HULL_H


func _bake() -> void:
	_cum.resize(path.size() + 1)
	_cum[0] = 0.0
	var total: float = 0.0
	for i: int in path.size():
		total += path[i].distance_to(path[(i + 1) % path.size()])
		_cum[i + 1] = total
	_len = maxf(total, 0.01)


## Position on the loop (world) at arc distance `s`.
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


## Unit flat heading of the loop at arc distance `s`.
func heading_at(s: float) -> Vector3:
	var d: Vector3 = point_at(s + 1.0) - point_at(s - 1.0)
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## Arc distance of the loop point nearest to world point `p` (coarse, for set-up).
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


## Seconds until the nose of the next car reaches arc distance `s` (from course time `t`).
func time_to_arrive(s: float, t: float) -> float:
	var best: float = INF
	for c: Car in car_nodes:
		var gap: float = fposmod(s - (c.arc_at(t) + CAR_LEN * 0.5), _len)
		best = minf(best, gap / speed)
	return best


## No car comes within `radius` (flat, plus its own half length) of world point `p` at any
## time in [now + t0, now + t1]. For the bot (crossing lanes).
func clear_at(p: Vector3, radius: float, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		var t: float = Game.course_time + s
		for c: Car in car_nodes:
			var q: Vector3 = c.offset_at(t)
			if absf(q.y - p.y) < 3.5 and Vector2(q.x - p.x, q.z - p.z).length() < radius + CAR_LEN * 0.5:
				return false
		s += 0.05
	return true


## A crossing where the course meets this (deadly) lane at world point `p`: two signal posts
## either side of the lane (`across` = unit vector across the lane, `half` = how far out, `aside` =
## how far to the side of the walkway they stand) that flash red, and a horn, about a second
## before every car.
func add_crossing(p: Vector3, across: Vector3, half: float, post_floor_y: float, aside: float = 1.7) -> void:
	var lamps: Array[MeshInstance3D] = []
	var pole_mat: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.16), 0.4, 0.6)
	var side: Vector3 = across.cross(Vector3.UP).normalized()
	for sx: float in [-1.0, 1.0]:
		var base: Vector3 = Vector3(p.x, post_floor_y, p.z) + across * sx * half + side * aside * sx
		var h: float = p.y - post_floor_y + 1.6
		var pole := Look.cylinder(0.08, h, pole_mat, base + Vector3(0, h * 0.5, 0), -1.0, 8)
		add_child(pole)
		for k: int in 2:
			var lamp := Look.sphere(0.2, _lamp_off_mat(), base + Vector3(0, h - 0.25 - 0.5 * float(k), 0))
			add_child(lamp)
			lamps.append(lamp)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.15, 0.1)
	light.light_energy = 0.0
	light.omni_range = 9.0
	light.position = p + Vector3(0, 1.0, 0)
	add_child(light)
	_crossings.append({"s": nearest_s(p), "p": p, "lamps": lamps, "light": light, "warned": -1})


func _lamp_off_mat() -> StandardMaterial3D:
	if _lamp_off == null:
		_lamp_off = Look.flat(Color(0.25, 0.05, 0.05), 0.5)
	return _lamp_off


func _process(_dt: float) -> void:
	if _crossings.is_empty():
		return
	var t: float = Game.course_time
	for x: Dictionary in _crossings:
		var eta: float = time_to_arrive(float(x["s"]), t)
		# the lane's signal: red and flashing from 1.4 s out until the car is through
		var through: float = (CAR_LEN + 2.0) / speed
		var gap_after: float = fposmod(-eta, _len / speed / float(cars))
		var hot: bool = eta < 1.4 or gap_after < through
		var on: bool = hot and fmod(t, 0.24) < 0.14
		for lamp: MeshInstance3D in x["lamps"]:
			lamp.material_override = _lamp_on if on else _lamp_off
		(x["light"] as OmniLight3D).light_energy = 2.2 if on else 0.0
		# SOUND: neon_car_horn about a second before each car crosses
		var k: int = int(floor((t + eta) * 10.0))
		if eta < 1.05 and k != int(x["warned"]):
			x["warned"] = k
			WorldAudio.at(self, "neon_car_horn", x["p"], 0.9, 60.0)


func _build_markers() -> void:
	# little lane lights every 3 m, alternating amber and white, on the outer edges of the lane
	var a: Array[Transform3D] = []
	var b: Array[Transform3D] = []
	var s: float = 0.0
	var i: int = 0
	while s < _len:
		var p: Vector3 = point_at(s)
		var f: Vector3 = heading_at(s)
		var side := Vector3(-f.z, 0, f.x)
		for sx: float in [-1.0, 1.0]:
			var xf := Transform3D(Basis(), p + side * sx * (CAR_W * 0.5 + 0.6) - Vector3(0, hull() + 0.3, 0))
			if i % 2 == 0:
				a.append(xf)
			else:
				b.append(xf)
		s += 3.0
		i += 1
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 6
	mesh.rings = 3
	_multi(mesh, Look.flat(Color(1.0, 0.6, 0.15), 0.4, 0.0, 4.0), a)
	_multi(mesh, Look.flat(Color(0.9, 0.95, 1.0), 0.4, 0.0, 3.0), b)


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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A loop for a lane: the stretch from `a` to `b` (the part the course uses: ridden or crossed),
## a half-turn of `radius` toward `side` (+1 = right of the a->b heading), the return stretch
## `drop` m lower (with smooth ramps, so returning traffic streams past below), and the half-turn
## back to `a`. World space, at roof-top height.
static func lane(a: Vector3, b: Vector3, side: float, radius: float, drop: float = 0.0, step: float = 0.5) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var f: Vector3 = Vector3(b.x - a.x, 0, b.z - a.z)
	var l: float = f.length()
	f = f.normalized()
	var r: Vector3 = Vector3(-f.z, 0, f.x) * side
	var n: int = maxi(int(l / step), 1)
	for i: int in n:
		pts.append(a.lerp(b, float(i) / float(n)))
	var c1: Vector3 = b + r * radius
	var na: int = maxi(int(PI * radius / step), 8)
	for i: int in na:
		var ang: float = PI * float(i) / float(na)
		pts.append(c1 - r * radius * cos(ang) + f * radius * sin(ang))
	var rb: Vector3 = b + r * radius * 2.0
	var ra: Vector3 = a + r * radius * 2.0
	for i: int in n:
		var k: float = float(i) / float(n)
		var dip: float = sin(PI * k)
		pts.append(rb.lerp(ra, k) - Vector3(0, drop * dip * dip, 0))
	var c2: Vector3 = a + r * radius
	for i: int in na:
		var ang2: float = PI * float(i) / float(na)
		pts.append(c2 + r * radius * cos(ang2) - f * radius * sin(ang2))
	return pts


## A rounded-rectangle loop: the ride straight from `a` along `f` for `ride` m, a quarter-turn of
## radius `r` toward `side` (+1 = right of `f`), across the far end, back along the return edge
## (`width` m to that side, `drop` m lower in its middle) and round to `a`. Every such loop with the
## same ride / width / r has the same length, so lanes built from it can run in step.
static func rect(a: Vector3, f: Vector3, ride: float, width: float, side: float, r: float, drop: float = 0.0, step: float = 0.5) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var fw: Vector3 = Vector3(f.x, 0, f.z).normalized()
	var rt: Vector3 = Vector3(-fw.z, 0, fw.x) * side
	var cross: float = maxf(width - 2.0 * r, 0.0)
	var na: int = maxi(int(PI * 0.5 * r / step), 6)
	var nl: int = maxi(int(ride / step), 1)
	var nc: int = maxi(int(cross / step), 1)
	for i: int in nl:
		pts.append(a + fw * ride * float(i) / float(nl))
	var e1: Vector3 = a + fw * ride
	var c2: Vector3 = e1 + rt * r
	for i: int in na:
		var g: float = PI * 0.5 * float(i) / float(na)
		pts.append(c2 - rt * r * cos(g) + fw * r * sin(g))
	var s3: Vector3 = c2 + fw * r
	for i: int in nc:
		pts.append(s3 + rt * cross * float(i) / float(nc))
	var e3: Vector3 = s3 + rt * cross
	var c4: Vector3 = e3 - fw * r
	for i: int in na:
		var g2: float = PI * 0.5 * float(i) / float(na)
		pts.append(c4 + fw * r * cos(g2) + rt * r * sin(g2))
	var s5: Vector3 = c4 + rt * r
	for i: int in nl:
		var k: float = float(i) / float(nl)
		var dip: float = sin(PI * k)
		pts.append(s5 - fw * ride * k - Vector3(0, drop * dip * dip, 0))
	var e5: Vector3 = s5 - fw * ride
	var c6: Vector3 = e5 - rt * r
	for i: int in na:
		var g3: float = PI * 0.5 * float(i) / float(na)
		pts.append(c6 + rt * r * cos(g3) - fw * r * sin(g3))
	var s7: Vector3 = c6 - fw * r
	for i: int in nc:
		pts.append(s7 - rt * cross * float(i) / float(nc))
	var e7: Vector3 = s7 - rt * cross
	var c8: Vector3 = e7 + fw * r
	for i: int in na:
		var g4: float = PI * 0.5 * float(i) / float(na)
		pts.append(c8 - fw * r * cos(g4) - rt * r * sin(g4))
	return pts


# ---- a hover car ------------------------------------------------------------------------------

class Car extends MovingPlatform:
	var lane: NeonTraffic
	## Arc distance of this car at t = 0.
	var base: float = 0.0
	var tint: Color = Color.WHITE
	var _hum: AudioStreamPlayer3D
	var _hit_tick: int = -100
	var _h: float = HULL_H

	func _ready() -> void:
		_h = lane.hull()
		sync_to_physics = false
		collision_layer = 1
		collision_mask = 0
		_origin = Vector3.ZERO
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		if lane.deadly:
			# crossing traffic: the whole car is solid (you can still bounce off its roof)
			box.size = Vector3(CAR_W, ROOF_T + _h, CAR_LEN)
			cs.position = Vector3(0, -(ROOF_T + _h) * 0.5, 0)
		else:
			box.size = Vector3(CAR_W, ROOF_T, CAR_LEN)
			cs.position = Vector3(0, -ROOF_T * 0.5, 0)
		cs.shape = box
		add_child(cs)
		_build()
		_pose(Game.course_time)
		reset_physics_interpolation()
		add_to_group("course_clock")
		# SOUND: neon_car_hum - the hover thrusters' drone as a car streams past
		_hum = WorldAudio.loop("neon_car_hum", self, -8.0, 28.0, 4.0)

	func _hums() -> bool:
		return false

	func arc_at(time: float) -> float:
		return lane.speed * time + base

	func offset_at(time: float) -> Vector3:
		return lane.point_at(arc_at(time))

	func snap_to_clock() -> void:
		_pose(Game.course_time)
		reset_physics_interpolation()

	func _physics_process(_dt: float) -> void:
		_pose(Game.course_time)
		if lane.deadly:
			_check_hit()

	func _pose(time: float) -> void:
		var f: Vector3 = lane.heading_at(arc_at(time))
		transform = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), offset_at(time))

	## Crossing traffic: a car that runs into you is a hazard hit (pure geometry, every tick).
	func _check_hit() -> void:
		var pl: Node3D = WorldAudio.local_player(self)
		if pl == null:
			return
		var lp: Vector3 = global_transform.affine_inverse() * pl.global_position
		if absf(lp.x) < CAR_W * 0.5 + 0.3 and absf(lp.z) < CAR_LEN * 0.5 + 0.3 and lp.y < -0.15 and lp.y > -(ROOF_T + _h) - 1.7:
			var tick: int = Engine.get_physics_frames()
			if tick - _hit_tick > 30:
				_hit_tick = tick
				var n: Node = self
				while n != null and not n.has_method("fail"):
					n = n.get_parent()
				if n != null:
					n.call_deferred("fail", "hazard")

	func _build() -> void:
		var body: StandardMaterial3D = Look.flat(tint.darkened(0.55), 0.25, 0.6)
		var dark: StandardMaterial3D = Look.flat(Color(0.05, 0.05, 0.07), 0.3, 0.5)
		var glass: StandardMaterial3D = Look.flat(Color(0.35, 0.55, 0.75, 0.85), 0.05, 0.3, 0.6)
		# the roof you ride: a dark slab with a glowing rim in the car's colour
		var roof := Look.platform_box(Vector3(CAR_W, ROOF_T, CAR_LEN), "mover")
		roof.position = Vector3(0, -ROOF_T * 0.5, 0)
		add_child(roof)
		# hull: a wedge-nosed body under the roof, tinted glass all round its upper half
		add_child(Look.box(Vector3(CAR_W + 0.1, _h * 0.55, CAR_LEN + 0.2), body, Vector3(0, -ROOF_T - _h * 0.6, 0)))
		add_child(Look.box(Vector3(CAR_W - 0.05, _h * 0.4, CAR_LEN - 0.4), glass, Vector3(0, -ROOF_T - _h * 0.15, 0)))
		var nose := Look.box(Vector3(CAR_W, 0.35, 0.9), body, Vector3(0, -ROOF_T - _h * 0.7, -CAR_LEN * 0.5 - 0.3))
		nose.rotation.x = -0.35
		add_child(nose)
		# underglow strip and thruster pods
		var glow: Color = Fx.hot(tint, 2.6)
		add_child(Look.box(Vector3(CAR_W - 0.4, 0.06, CAR_LEN - 0.6), Look.flat(tint, 0.4, 0.0, 3.0), Vector3(0, -ROOF_T - _h - 0.02, 0)))
		for sx: float in [-1.0, 1.0]:
			for z: float in [-CAR_LEN * 0.33, CAR_LEN * 0.33]:
				add_child(Look.cylinder(0.32, 0.3, dark, Vector3(sx * (CAR_W * 0.5 + 0.12), -ROOF_T - _h + 0.05, z), 0.24, 12))
				add_child(Look.cylinder(0.2, 0.04, Look.flat(Color(0.4, 0.9, 1.0), 0.3, 0.0, 4.0), Vector3(sx * (CAR_W * 0.5 + 0.12), -ROOF_T - _h - 0.12, z), -1.0, 12))
		# head and tail lights (forward is local -Z)
		for sx2: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.5, 0.12, 0.08), Look.flat(Color(1.0, 0.95, 0.85), 0.2, 0.0, 6.0), Vector3(sx2 * 0.8, -ROOF_T - 0.35, -CAR_LEN * 0.5 - 0.11)))
			add_child(Look.box(Vector3(0.7, 0.1, 0.08), Look.flat(Color(1.0, 0.08, 0.12), 0.2, 0.0, 5.0), Vector3(sx2 * 0.75, -ROOF_T - 0.35, CAR_LEN * 0.5 + 0.11)))
		# headlight beams cutting through the rain (crossing traffic only: they are the tell)
		if lane.deadly:
			var beam := Look.cylinder(1.6, 9.0, _beam_mat(), Vector3(0, -ROOF_T - 0.4, -CAR_LEN * 0.5 - 4.6), 0.25, 14)
			beam.rotation.x = -PI * 0.5
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(beam)
		# thruster shimmer trailing behind (world space)
		var trail: GPUParticles3D = Fx.emitter({"amount": 18, "lifetime": 0.6, "fixed_fps": 0, "shape": "box",
			"extents": Vector3(CAR_W * 0.4, 0.05, 0.2), "speed": Vector2(0.0, 0.4), "spread": 180.0,
			"gravity": Vector3(0, -1.0, 0), "tex": Fx.Tex.DOT, "size": 0.22, "curve": "shrink", "color": glow,
			"aabb": AABB(Vector3(-600, -200, -600), Vector3(1200, 400, 1200))})
		trail.position = Vector3(0, -ROOF_T - _h, CAR_LEN * 0.5)
		add_child(trail)
		var under := OmniLight3D.new()
		under.light_color = tint
		under.light_energy = 1.4
		under.omni_range = 5.0
		under.position = Vector3(0, -ROOF_T - _h - 0.6, 0)
		add_child(under)

	static var _bm: StandardMaterial3D

	static func _beam_mat() -> StandardMaterial3D:
		if _bm == null:
			_bm = StandardMaterial3D.new()
			_bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			_bm.albedo_color = Color(1.0, 0.92, 0.75, 0.07)
			_bm.disable_receive_shadows = true
		return _bm
