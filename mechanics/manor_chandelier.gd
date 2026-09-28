class_name ManorChandelier
extends MovingPlatform
## Phantom Manor: a swinging chandelier (or a gibbet cage on a dead tree) you ride like a
## pendulum. Hung from a pivot `length` metres above its tray, it swings along its local X by
## +-`swing_deg` on a fixed rhythm (Game.course_time). The tray stays level, so you can stand
## on it: board it where it hangs still at one end of its swing, ride it through the dip and
## jump off at the other end. Built on MovingPlatform, so the route bot can ask where it WILL
## be (offset_at). Positioned by its tray's centre at the bottom of the swing.

## "chandelier" (a great brass ring of candles), "cage" (a rusted iron gibbet cage)
@export var kind: String = "chandelier"
@export var length: float = 9.0
@export var swing_deg: float = 38.0
@export var radius: float = 1.6

const BRASS := Color(0.72, 0.54, 0.24)
const IRON := Color(0.12, 0.1, 0.1)

var _rig: Node3D
var _flames: Array[Node3D] = []
var _creak_eta: float = -1.0


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	size = Vector3(radius * 2.0, 0.4, radius * 2.0)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = size.y
	cs.shape = cyl
	add_child(cs)
	_rig = Node3D.new()
	add_child(_rig)
	if kind == "cage":
		_build_cage()
	else:
		_build_chandelier()
	position = _origin + offset_at(Game.course_time)
	_rig.rotation.z = angle_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func _build_chandelier() -> void:
	var brass: StandardMaterial3D = Look.flat(BRASS, 0.3, 0.9)
	var dark: StandardMaterial3D = Look.flat(BRASS.darkened(0.5), 0.45, 0.8)
	# the tray you stand on: a brass disc with a filigree rim
	add_child(Look.cylinder(radius, size.y, dark, Vector3.ZERO, -1.0, 32))
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.08
	tm.outer_radius = radius + 0.1
	tm.rings = 40
	tm.ring_segments = 8
	add_child(Look.mesh_node(tm, brass, Vector3(0, size.y * 0.5, 0)))
	add_child(Look.cylinder(radius * 0.55, 0.9, brass, Vector3(0, -0.6, 0), 0.12, 16))
	add_child(Look.sphere(0.3, brass, Vector3(0, -1.15, 0)))
	# candles round the rim, just outside the tray, and crystal drops hanging below
	var wax: StandardMaterial3D = Look.flat(Color(0.9, 0.88, 0.8), 0.6)
	var n: int = 10
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		var p := Vector3(cos(a), 0, sin(a)) * (radius + 0.28)
		add_child(Look.cylinder(0.12, 0.08, brass, p + Vector3(0, 0.1, 0), -1.0, 8))
		add_child(Look.cylinder(0.05, 0.36, wax, p + Vector3(0, 0.32, 0), -1.0, 6))
		var f := Fx.sprite(Color(2.4, 1.5, 0.6), 0.3, Fx.Tex.DOT)
		f.position = p + Vector3(0, 0.58, 0)
		add_child(f)
		_flames.append(f)
		var drop := Look.sphere(0.07, Look.flat(Color(0.8, 0.9, 1.0), 0.05, 0.3, 0.4), Vector3(cos(a), 0, sin(a)) * radius * 0.8 + Vector3(0, -0.5, 0))
		drop.scale = Vector3(0.7, 1.6, 0.7)
		add_child(drop)
	var o := OmniLight3D.new()
	o.light_color = Color(1.0, 0.7, 0.4)
	o.light_energy = 1.6
	o.omni_range = 9.0
	o.position = Vector3(0, 0.8, 0)
	add_child(o)
	_chain(brass)


func _build_cage() -> void:
	var iron: StandardMaterial3D = Look.flat(IRON, 0.7, 0.6)
	var rust: StandardMaterial3D = Look.flat(Color(0.32, 0.14, 0.08), 0.85, 0.3)
	add_child(Look.cylinder(radius, size.y, rust, Vector3.ZERO, -1.0, 16))
	# bars rising from the rim to a dome (the front ones broken off, so you can get in)
	var n: int = 10
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		if i % 5 == 0:
			continue
		var p := Vector3(cos(a), 0, sin(a)) * (radius - 0.05)
		var bar_h: float = 0.35 if i % 3 == 0 else 0.6
		add_child(Look.cylinder(0.04, bar_h, iron, p + Vector3(0, size.y * 0.5 + bar_h * 0.5, 0), -1.0, 5))
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.1
	tm.outer_radius = radius + 0.04
	tm.rings = 24
	tm.ring_segments = 6
	add_child(Look.mesh_node(tm, iron, Vector3(0, size.y * 0.5, 0)))
	# a green lantern swinging under it
	var glow := Fx.sprite(Color(0.8, 2.4, 1.1), 0.9, Fx.Tex.DOT)
	glow.position = Vector3(0, -0.9, 0)
	add_child(glow)
	add_child(Look.sphere(0.18, Look.flat(Color(0.5, 1.0, 0.6), 0.4, 0.0, 2.0), Vector3(0, -0.9, 0)))
	var o := OmniLight3D.new()
	o.light_color = Color(0.5, 1.0, 0.6)
	o.light_energy = 1.3
	o.omni_range = 7.0
	o.position = Vector3(0, -0.6, 0)
	add_child(o)
	_chain(iron)


## The chain up to the pivot, on a rig that tilts with the swing (the tray stays level).
func _chain(m: StandardMaterial3D) -> void:
	var links: int = int(length / 0.45)
	for i: int in links:
		var y: float = size.y * 0.5 + 0.2 + float(i) * 0.45
		if y > length:
			break
		var tm := TorusMesh.new()
		tm.inner_radius = 0.07
		tm.outer_radius = 0.12
		tm.rings = 8
		tm.ring_segments = 5
		var l := Look.mesh_node(tm, m, Vector3(0, y, 0))
		l.rotation = Vector3(PI * 0.5, float(i % 2) * PI * 0.5, 0)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rig.add_child(l)
	# four short chains from the tray rim up to the ring on the main chain
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + PI * 0.25
		var foot := Vector3(cos(a), 0, sin(a)) * radius * 0.85 + Vector3(0, size.y * 0.5, 0)
		var head := Vector3(0, 1.8, 0)
		var d: Vector3 = head - foot
		var c := Look.cylinder(0.03, d.length(), m, (foot + head) * 0.5, -1.0, 4)
		var up: Vector3 = d.normalized()
		var side: Vector3 = up.cross(Vector3(0.3, 0.1, 0.9)).normalized()
		c.basis = Basis(side, up, side.cross(up))
		add_child(c)


func angle_at(time: float) -> float:
	return deg_to_rad(swing_deg) * sin(TAU * (time / maxf(period, 0.01) + phase))


func offset_at(time: float) -> Vector3:
	var a: float = angle_at(time)
	return transform.basis * Vector3(length * sin(a), length * (1.0 - cos(a)), 0.0)


## World position of the body's origin (the tray's centre) at the end of its swing: side +1 is
## the end its positive angles swing to (local +X), -1 the other end.
func end_origin(side: float) -> Vector3:
	var a: float = deg_to_rad(swing_deg) * signf(side)
	var base: Vector3 = _origin + transform.basis * Vector3(length * sin(a), length * (1.0 - cos(a)), 0.0)
	var p: Node3D = get_parent() as Node3D
	return p.global_transform * base if p != null else base


## World position of the tray's top centre at `time` (for level scripts).
func tray_at(time: float) -> Vector3:
	var p: Node3D = get_parent() as Node3D
	var base: Vector3 = _origin + offset_at(time) + Vector3(0, size.y * 0.5, 0)
	return p.global_transform * base if p != null else base


func snap_to_clock() -> void:
	super.snap_to_clock()
	_rig.rotation.z = angle_at(Game.course_time)


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	_rig.rotation.z = angle_at(Game.course_time)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	for i: int in _flames.size():
		var k: float = 0.85 + 0.15 * sin(t * 13.0 + float(i) * 1.7)
		_flames[i].scale = Vector3(k, k * 1.3, k)
	if WorldAudio.enabled():
		# a creak of the chain as it turns at each end of the swing
		var half: float = period * 0.5
		var eta: float = half - fposmod(t + (phase + 0.25) * period, half)
		if _creak_eta >= 0.0 and eta > _creak_eta + 0.5:
			WorldAudio.at(self, "manor_chain_creak", global_position + Vector3(0, length * 0.5, 0), 0.7, 32.0)
		_creak_eta = eta
