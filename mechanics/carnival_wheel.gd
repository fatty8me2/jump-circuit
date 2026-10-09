class_name CarnivalWheel
extends Node3D
## Carnival Chaos: a FERRIS WHEEL whose GONDOLAS you ride. The wheel stands in the vertical plane that
## holds the course (local -Z is forward, +Y up; it turns about the local X axis) and turns steadily on
## the course clock. Each gondola is a real kinematic platform (a CarnivalGondola, an upright MovingPlatform
## in ORBIT mode: its floor stays level and carries you with its full velocity as it goes round).
## The wheel itself - rim, spokes, lamps - is scenery; the gondolas are the only solid parts.
##
## Spin direction: seen from +X the gondolas go back (+Z) -> bottom -> front (-Z) -> top, i.e. they RISE on
## the front side. `radius` is the radius of the circle the gondolas' FLOORS follow; the wheel's centre is
## `hang` m above the floors' circle centre (the hangers), so `centre` here is the FLOOR circle's centre.

@export var radius: float = 8.0
@export var period: float = 28.0
@export var count: int = 6
@export var hang: float = 2.9
@export var phase: float = 0.0
@export var tint: Color = Color(0.95, 0.25, 0.3)

var gondolas: Array[Gondola] = []
var _spin: Node3D
var _lamps: Array[StandardMaterial3D] = []


func _ready() -> void:
	for i: int in count:
		var g := Gondola.new()
		g.mode = MovingPlatform.Mode.ORBIT
		g.orbit_radius = radius
		g.orbit_axis = Basis(Vector3.UP, rotation.y) * Vector3.RIGHT
		g.period = period
		g.phase = phase + float(i) / float(count)
		g.size = Vector3(3.2, 0.5, 3.8)
		g.is_round = false
		g.hang = hang
		g.position = position - Vector3(0, g.size.y * 0.5, 0)
		g.rotation.y = rotation.y
		g.tint = Color.from_hsv(fposmod(float(i) * 0.17, 1.0), 0.65, 0.98)
		gondolas.append(g)
		# the wheel's own node is a plain Node3D at the circle centre; gondolas are siblings so the
		# platform's absolute orbit centre is that point
		get_parent().add_child.call_deferred(g)
	_build()
	# SOUND: carnival_wheel_creak - a loop of slow iron creaking and a distant calliope, quiet, close up only
	WorldAudio.loop("carnival_wheel_creak", self, -18.0, 34.0, 6.0)


## Where gondola `i`'s floor centre (its top surface) is at course time `time`.
func gondola_top(i: int, time: float) -> Vector3:
	var g: Gondola = gondolas[i]
	return g.origin_world() + g.offset_at(time) + Vector3(0, g.size.y * 0.5, 0)


func _build() -> void:
	var cx: Vector3 = Vector3.ZERO
	var rim_r: float = radius
	_spin = Node3D.new()
	_spin.position = Vector3(0, hang, 0)
	add_child(_spin)
	var white: StandardMaterial3D = Look.flat(Color(0.97, 0.95, 0.92), 0.5, 0.2)
	var red: StandardMaterial3D = Look.flat(tint, 0.45, 0.2)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.25), 0.3, 0.8, 0.2)
	var segs: int = 40
	# two rims (front and back of the wheel), spokes between them
	for sx: float in [-1.0, 1.0]:
		var xoff: float = sx * 1.7
		for i: int in segs:
			var a0: float = TAU * float(i) / float(segs)
			var a1: float = TAU * float(i + 1) / float(segs)
			var p0 := Vector3(xoff, sin(a0) * rim_r, cos(a0) * rim_r)
			var p1 := Vector3(xoff, sin(a1) * rim_r, cos(a1) * rim_r)
			_beam(p0, p1, 0.18, white if i % 2 == 0 else red)
		for i2: int in 12:
			var a: float = TAU * float(i2) / 12.0
			_beam(Vector3(xoff, 0, 0), Vector3(xoff, sin(a) * rim_r, cos(a) * rim_r), 0.09, white)
		_spin.add_child(Look.cylinder(0.7, 0.3, gold, Vector3(xoff, 0, 0), -1.0, 20))
		_spin.get_child(_spin.get_child_count() - 1).rotation.z = PI * 0.5
		# lamps all round the rim
		for k: int in 28:
			var ak: float = TAU * (float(k) + 0.5) / 28.0
			var lm: StandardMaterial3D = Look.flat(Color(1.0, 0.86, 0.5) if k % 2 == 0 else Color(1.0, 0.5, 0.65), 0.3, 0.0, 2.0).duplicate() as StandardMaterial3D
			_lamps.append(lm)
			var bulb := Look.sphere(0.14, lm, Vector3(xoff + sx * 0.12, sin(ak) * (rim_r + 0.05), cos(ak) * (rim_r + 0.05)))
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_spin.add_child(bulb)
	_spin.add_child(Look.cylinder(0.3, 3.6, white, Vector3(0, 0, 0), -1.0, 12))
	_spin.get_child(_spin.get_child_count() - 1).rotation.z = PI * 0.5
	# the A-frame legs, planted down in the dark
	var leg_base: float = -(hang + radius) - 22.0
	for sx2: float in [-1.0, 1.0]:
		var top := Vector3(sx2 * 1.7, hang, 0)
		for sz: float in [-1.0, 1.0]:
			var foot := Vector3(sx2 * 3.4, leg_base, sz * (radius * 0.75))
			_beam_world(top, foot, 0.26, white)
	# and the cross-brace under the hub
	_beam_world(Vector3(-1.7, hang, 0), Vector3(1.7, hang, 0), 0.22, red)
	_spin.set_meta("cx", cx)


func _beam(a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var mid: Vector3 = (a + b) * 0.5
	var l: float = a.distance_to(b)
	if l < 0.01:
		return
	var m := Look.box(Vector3(thick, thick, l + thick * 0.4), mat, Vector3.ZERO)
	m.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT), mid)
	_spin.add_child(m)


func _beam_world(a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var mid: Vector3 = (a + b) * 0.5
	var l: float = a.distance_to(b)
	if l < 0.01:
		return
	var m := Look.box(Vector3(thick, thick, l), mat, Vector3.ZERO)
	var d: Vector3 = (b - a).normalized()
	m.transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT), mid)
	add_child(m)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	# the wheel turns with the gondolas: angle 0 = a point at +Z; rotation about +X by u * TAU sends +Z to -Y
	_spin.rotation.x = fposmod(t / period + phase, 1.0) * TAU
	for i: int in _lamps.size():
		_lamps[i].emission_energy_multiplier = 0.8 + 2.2 * (0.5 + 0.5 * sin(t * 4.0 - float(i) * 0.5))


# ---- a gondola ------------------------------------------------------------------------------

class Gondola extends MovingPlatform:
	var tint: Color = Color(0.95, 0.3, 0.3)
	var hang: float = 2.9

	func _ready() -> void:
		sync_to_physics = false
		collision_layer = 1
		collision_mask = 0
		_origin = position
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		add_child(cs)
		_build_cabin()
		position = _origin + offset_at(Game.course_time)
		reset_physics_interpolation()
		add_to_group("course_clock")

	func _hums() -> bool:
		return false

	func origin_world() -> Vector3:
		return _origin

	func _build_cabin() -> void:
		var hx: float = size.x * 0.5
		var hz: float = size.z * 0.5
		var body: StandardMaterial3D = Look.flat(tint, 0.4, 0.1)
		var cream: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.85), 0.5)
		var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.25), 0.3, 0.8, 0.15)
		add_child(Look.box(size, body, Vector3.ZERO))
		add_child(Look.box(Vector3(size.x - 0.4, 0.04, size.z - 0.4), cream, Vector3(0, size.y * 0.5 + 0.012, 0)))
		# low rails (visual only; the floor is the only solid thing) and a gold lip
		for sx: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.1, 0.5, size.z), body, Vector3(sx * hx, size.y * 0.5 + 0.22, 0)))
			add_child(Look.box(Vector3(0.14, 0.07, size.z + 0.06), gold, Vector3(sx * hx, size.y * 0.5 + 0.5, 0)))
		# hangers: two thin rods from the floor's long sides up to a pin under the rim
		var top_y: float = size.y * 0.5 + hang
		for sx2: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var a := Vector3(sx2 * hx, size.y * 0.5 + 0.4, sz * hz * 0.8)
				var b := Vector3(sx2 * hx * 0.2, top_y, 0)
				var m := Look.box(Vector3(0.07, 0.07, a.distance_to(b)), gold, Vector3.ZERO)
				var d: Vector3 = (b - a).normalized()
				m.transform = Transform3D(Basis.looking_at(d, Vector3.UP), (a + b) * 0.5)
				add_child(m)
		add_child(Look.sphere(0.2, gold, Vector3(0, top_y, 0)))
		# a little bunting across the top
		var flag: StandardMaterial3D = Look.flat(Color(1.0, 0.9, 0.4), 0.5)
		for i: int in 5:
			var fl := Look.box(Vector3(0.22, 0.28, 0.02), flag if i % 2 == 0 else Look.flat(Color(1.0, 0.45, 0.6), 0.5), Vector3(0, top_y - 0.35 - 0.12 * absf(float(i) - 2.0), (float(i) - 2.0) * 0.38))
			fl.rotation.x = 0.2
			add_child(fl)
