class_name ToyboxJack
extends Node3D
## Toybox Tumble: a JACK-IN-THE-BOX spring. A painted wooden toy chest whose lid is the platform:
## a padded round cushion flush with the rim. Stand on it. For the last `tell` s before it fires
## the chest shivers, the crank whirls and a music-box tune plays faster and faster, the clown's
## star flashes - then SPROING: the jack shoots out of the chest on its coil and throws whoever is
## standing on the cushion by `launch` (in the chest's own frame, local -Z = forward). The cushion
## holds up for a beat, then sinks back into the chest, and the cycle repeats. A pure function of
## Game.course_time (identical for every racer). The node sits at the centre of the cushion's top.

@export var size: Vector3 = Vector3(2.6, 1.6, 2.6)
@export var period: float = 4.5
@export var phase: float = 0.0
@export var launch: Vector3 = Vector3(0, 19, -2.5)
@export var rise: float = 1.6
@export var tell: float = 1.1
@export var tint: Color = Color(0.3, 0.6, 0.95)

const OUT: float = 0.12
const HOLD: float = 0.35
const SINK: float = 0.6

var _lid: AnimatableBody3D
var _area: Area3D
var _coil: Node3D
var _crank: Node3D
var _chest: Node3D
var _flaps: Array[Node3D] = []
var _star_mat: StandardMaterial3D
var _burst: GPUParticles3D
var _confetti: GPUParticles3D
var _cool: float = 0.0
var _cycle_fx: int = -1
var _cycle_tell: int = -1
var _rest: Vector3 = Vector3.ZERO


func _ready() -> void:
	_build()
	_pose(Game.course_time)
	add_to_group("course_clock")


func _pop_s() -> float:
	return period - OUT - HOLD - SINK - 0.2


func _tm(time: float) -> float:
	return fposmod(time + phase * period, period)


## 0 (in the chest) .. 1 (sprung out) at `time`.
func extension_at(time: float) -> float:
	var tm: float = _tm(time)
	var p: float = _pop_s()
	if tm < p:
		return 0.0
	if tm < p + OUT:
		var k: float = (tm - p) / OUT
		return 1.0 - (1.0 - k) * (1.0 - k)
	if tm < p + OUT + HOLD:
		return 1.0
	if tm < p + OUT + HOLD + SINK:
		var r: float = (tm - p - OUT - HOLD) / SINK
		return 1.0 - r * r * (3.0 - 2.0 * r)
	return 0.0


## Seconds from `time` until the next pop.
func time_until_pop(time: float) -> float:
	return fposmod(_pop_s() - _tm(time), period)


## True while the cushion is down and still (it is safe and calm to step onto it).
func is_resting_at(time: float) -> bool:
	return _tm(time) < _pop_s()


func launch_velocity() -> Vector3:
	return global_basis.orthonormalized() * launch


func snap_to_clock() -> void:
	_pose(Game.course_time)
	if _lid != null:
		_lid.reset_physics_interpolation()


func _pose(t: float) -> void:
	if _lid != null:
		_lid.position = _rest + Vector3(0, rise * extension_at(t), 0)


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_pose(t)
	_cool = maxf(_cool - dt, 0.0)
	var tm: float = _tm(t)
	var p: float = _pop_s()
	if tm >= p and tm < p + OUT and _cool <= 0.0:
		for body: Node3D in _area.get_overlapping_bodies():
			if body is Player:
				(body as Player).knockback(launch_velocity())
				_cool = OUT + 0.15


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var tm: float = _tm(t)
	var p: float = _pop_s()
	var e: float = extension_at(t)
	var telling: bool = tm >= p - tell and tm < p
	var k: float = clampf((tm - (p - tell)) / maxf(tell, 0.01), 0.0, 1.0) if telling else 0.0
	_crank.rotation.z -= dt * (TAU * (0.7 + 4.0 * k))
	if telling:
		var amp: float = 0.02 + 0.045 * k
		_chest.position = Vector3(sin(t * 77.0) * amp, 0.0, cos(t * 63.0) * amp)
	elif _chest.position != Vector3.ZERO:
		_chest.position = Vector3.ZERO
	_coil.scale = Vector3(1.0, 0.1 + e * rise, 1.0)
	_coil.visible = e > 0.02
	_star_mat.emission_energy_multiplier = (4.0 if fmod(t, 0.18) < 0.09 else 1.0) if telling else 1.2 + 2.2 * e
	# the two lid flaps hinge open as the jack springs out
	var open: float = clampf(e * 1.4, 0.0, 1.0)
	for i: int in _flaps.size():
		_flaps[i].rotation.z = (-1.0 if i == 0 else 1.0) * (0.15 + 1.6 * open)
	var cycle: int = int(floor((t + phase * period) / period))
	if telling and cycle != _cycle_tell:
		_cycle_tell = cycle
		# SOUND: toybox_jack_tune - a wobbling music-box tune winding up faster (about 1.1 s, ends on the pop)
		WorldAudio.at(self, "toybox_jack_tune", global_position, 0.8, 32.0)
	if tm >= p and tm < p + OUT + HOLD and cycle != _cycle_fx:
		_cycle_fx = cycle
		_burst.restart()
		_confetti.restart()
		# SOUND: toybox_jack_pop - SPROING: the spring releases and the clown head bangs out of the box
		WorldAudio.at(self, "toybox_jack_pop", global_position, 1.0, 42.0)


func _build() -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var body_h: float = size.y
	var wood: StandardMaterial3D = Look.flat(tint, 0.55)
	var trim: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.25), 0.45)
	var red: StandardMaterial3D = Look.flat(Color(0.95, 0.28, 0.28), 0.5)
	_chest = Node3D.new()
	add_child(_chest)
	# the chest: a solid painted block under the cushion (static, solid)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, body_h - 0.3, size.z)
	var bcs := CollisionShape3D.new()
	bcs.shape = bs
	bcs.position = Vector3(0, -0.3 - (body_h - 0.3) * 0.5, 0)
	body.add_child(bcs)
	add_child(body)
	var cy: float = -0.3 - (body_h - 0.3) * 0.5
	_chest.add_child(Look.box(Vector3(size.x, body_h - 0.3, size.z), wood, Vector3(0, cy, 0)))
	# painted stars on the four faces, a yellow band round the foot and under the lip, brass corners
	for f: int in 4:
		var a: float = float(f) * PI * 0.5
		var n := Vector3(sin(a), 0, cos(a))
		var ext: float = hz if f % 2 == 0 else hx
		var face_star := Look.box(Vector3(size.x * 0.4, (body_h - 0.3) * 0.5, 0.04), trim if f % 2 == 0 else red, n * (ext + 0.012) + Vector3(0, cy, 0))
		face_star.rotation.y = a
		_chest.add_child(face_star)
	_chest.add_child(Look.box(Vector3(size.x + 0.12, 0.16, size.z + 0.12), red, Vector3(0, -0.36, 0)))
	_chest.add_child(Look.box(Vector3(size.x + 0.12, 0.16, size.z + 0.12), red, Vector3(0, -body_h + 0.08, 0)))
	# the lid flaps: two hinged boards on the sides, open when the jack is out
	var flap_mat: StandardMaterial3D = Look.flat(tint.lightened(0.25), 0.55)
	for i: int in 2:
		var s: float = -1.0 if i == 0 else 1.0
		var hinge := Node3D.new()
		hinge.position = Vector3(s * hx, -0.32, 0)
		_chest.add_child(hinge)
		var flap := Look.box(Vector3(size.x * 0.5, 0.08, size.z), flap_mat, Vector3(s * size.x * 0.25, 0, 0))
		hinge.add_child(flap)
		_flaps.append(hinge)
	# the crank on the +X side
	_crank = Node3D.new()
	_crank.position = Vector3(hx + 0.12, cy, 0)
	_crank.rotation.y = PI * 0.5
	_chest.add_child(_crank)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.3), 0.3, 0.8)
	_crank.add_child(Look.box(Vector3(0.12, 0.6, 0.08), gold, Vector3(0, 0.25, 0.05)))
	var knob := Look.cylinder(0.09, 0.3, red, Vector3(0, 0.52, 0.2))
	knob.rotation.x = PI * 0.5
	_crank.add_child(knob)
	# the cushion (the platform you stand on): kinematic, flush with the rim at rest
	_lid = AnimatableBody3D.new()
	_lid.sync_to_physics = false
	_lid.collision_layer = 1
	_lid.collision_mask = 0
	var ls := BoxShape3D.new()
	ls.size = Vector3(size.x - 0.3, 0.3, size.z - 0.3)
	var lcs := CollisionShape3D.new()
	lcs.shape = ls
	lcs.position = Vector3(0, -0.15, 0)
	_lid.add_child(lcs)
	add_child(_lid)
	var r: float = minf(hx, hz) - 0.18
	_lid.add_child(Look.cylinder(r, 0.3, Look.flat(Color(0.25, 0.12, 0.45), 0.6), Vector3(0, -0.15, 0), -1.0, 28))
	_lid.add_child(Look.cylinder(r - 0.18, 0.04, Look.flat(Color(1.0, 0.96, 0.88), 0.5), Vector3(0, 0.005, 0), -1.0, 28))
	_star_mat = StandardMaterial3D.new()
	_star_mat.albedo_color = Color(1.0, 0.85, 0.2)
	_star_mat.emission_enabled = true
	_star_mat.emission = Color(1.0, 0.8, 0.2)
	_star_mat.emission_energy_multiplier = 1.2
	var star_mesh := CylinderMesh.new()
	star_mesh.top_radius = 0.5
	star_mesh.bottom_radius = 0.5
	star_mesh.height = 0.05
	star_mesh.radial_segments = 5
	star_mesh.rings = 1
	_lid.add_child(Look.mesh_node(star_mesh, _star_mat, Vector3(0, 0.03, 0)))
	# the clown under the cushion: a round face with a red nose, ruff and hat
	_lid.add_child(Look.sphere(0.6, Look.flat(Color(1.0, 0.92, 0.85), 0.6), Vector3(0, -0.85, 0)))
	_lid.add_child(Look.sphere(0.15, Look.flat(Color(1.0, 0.15, 0.2), 0.3, 0.0, 0.6), Vector3(0, -0.85, -0.6)))
	for sx: float in [-1.0, 1.0]:
		_lid.add_child(Look.sphere(0.07, Look.flat(Color(0.1, 0.1, 0.15), 0.4), Vector3(sx * 0.22, -0.7, -0.55)))
		_lid.add_child(Look.sphere(0.22, Look.flat(Color(1.0, 0.45, 0.2), 0.8), Vector3(sx * 0.55, -0.6, 0)))
	_lid.add_child(Look.cylinder(0.8, 0.16, Look.flat(Color(1.0, 0.95, 0.4), 0.6), Vector3(0, -1.4, 0), 0.55, 16))
	# the coil below the clown, stretching with the jack
	_coil = Node3D.new()
	_coil.position = Vector3(0, -1.5, 0)
	add_child(_coil)
	var coil_mat: StandardMaterial3D = Look.flat(Color(0.85, 0.87, 0.92), 0.25, 0.9)
	for i: int in 6:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.28
		tm.outer_radius = 0.37
		tm.rings = 16
		tm.ring_segments = 6
		var ring := Look.mesh_node(tm, coil_mat, Vector3(0, float(i) / 5.0, 0))
		ring.rotation.x = 0.12
		_coil.add_child(ring)
	# the launch detector over the cushion
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var as_ := BoxShape3D.new()
	as_.size = Vector3(size.x - 0.2, 0.9, size.z - 0.2)
	var acs := CollisionShape3D.new()
	acs.shape = as_
	acs.position = Vector3(0, 0.45, 0)
	_area.add_child(acs)
	_lid.add_child(_area)
	var vis := AABB(Vector3(-6, -4, -6), Vector3(12, 18, 12))
	_burst = Fx.sparks({"amount": 34, "lifetime": 0.6, "shape": "ring", "ring_radius": r * 0.9, "dir": Vector3.UP,
		"spread": 25.0, "speed": Vector2(6.0, 13.0), "gravity": Vector3(0, -12, 0),
		"color": Fx.hot(Color(1.0, 0.85, 0.35), 2.2), "aabb": vis})
	_burst.position = Vector3(0, 0.1, 0)
	add_child(_burst)
	_confetti = Fx.burst({"amount": 40, "lifetime": 1.3, "shape": "ring", "ring_radius": r * 0.7, "dir": Vector3.UP,
		"spread": 40.0, "speed": Vector2(3.0, 8.0), "gravity": Vector3(0, -7.0, 0), "damping": Vector2(0.3, 0.8),
		"facing": "mesh", "mesh": Fx.chunk_mesh(0.12), "angle": Vector2(0, 360), "spin": Vector2(-300, 300),
		"pick": PackedColorArray([Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.3, 0.6, 1.0), Color(0.35, 0.85, 0.45), Color(1.0, 0.5, 0.8)]),
		"curve": "shrink", "aabb": vis})
	_confetti.position = Vector3(0, 0.3, 0)
	add_child(_confetti)
