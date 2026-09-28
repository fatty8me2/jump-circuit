class_name CandyJack
extends Node3D
## Sugar Rush: a jack-in-the-box launcher. A painted toy box with a crank on its side; its top is
## the jack's flat, padded hat, flush with the rim. The crank turns on the course clock and the
## box plays its little tune; near the end of each turn the box shivers, the crank spins fast and
## the hat's star flashes - then POP: the jack springs out on its coil and anyone standing on the
## hat is flung up (and a little along the box's facing) by `launch`. The hat slowly sinks back
## into the box for the next turn. A pure function of Game.course_time: stand on the hat and wait.
##   u 0.00-POP resting (crank turning)   POP-POP+0.04 spring out   ..HOLD held up   ..1 sinking back
## Positioned by the centre of the hat's TOP at rest; the box stands on the floor below it.

@export var size: Vector3 = Vector3(2.4, 1.4, 2.4)
@export var period: float = 3.0
@export var phase: float = 0.0
## Launch velocity in the box's own frame (local -Z is "forward").
@export var launch: Vector3 = Vector3(0, 18, -2)
@export var rise: float = 1.5
@export var tint: Color = Color(0.35, 0.75, 1.0)

const POP: float = 0.8
const OUT: float = 0.04
const HOLD: float = 0.9
const WARN: float = 0.2

var _hat: AnimatableBody3D
var _area: Area3D
var _coil: Node3D
var _crank: Node3D
var _box: Node3D
var _star_mat: StandardMaterial3D
var _burst: GPUParticles3D
var _confetti: GPUParticles3D
var _cool: float = 0.0
var _popped: int = -1
var _hat_rest: Vector3


func _ready() -> void:
	_build()
	_pose(Game.course_time)
	add_to_group("course_clock")


func _u(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0)


## 0 (in the box) .. 1 (sprung out) at `time`.
func extension_at(time: float) -> float:
	var u: float = _u(time)
	if u < POP:
		return 0.0
	if u < POP + OUT:
		var k: float = (u - POP) / OUT
		return 1.0 - (1.0 - k) * (1.0 - k)
	if u < HOLD:
		return 1.0
	var r: float = (u - HOLD) / (1.0 - HOLD)
	return 1.0 - r * r * (3.0 - 2.0 * r)


## Seconds from `time` until the next pop.
func time_until_pop(time: float) -> float:
	return fposmod(POP - _u(time), 1.0) * period


## True while the hat is down and still (you can step onto it cleanly).
func is_resting_at(time: float) -> bool:
	return _u(time) < POP


## World velocity a rider is thrown with.
func launch_velocity() -> Vector3:
	return global_basis.orthonormalized() * launch


func snap_to_clock() -> void:
	_pose(Game.course_time)
	if _hat != null:
		_hat.reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_pose(t)
	_cool = maxf(_cool - dt, 0.0)
	var u: float = _u(t)
	if u >= POP and u < POP + OUT and _cool <= 0.0:
		for body: Node3D in _area.get_overlapping_bodies():
			if body is Player:
				(body as Player).knockback(launch_velocity())
				_cool = OUT * period + 0.1


func _pose(t: float) -> void:
	if _hat != null:
		_hat.position = _hat_rest + Vector3(0, rise * extension_at(t), 0)


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var u: float = _u(t)
	var e: float = extension_at(t)
	var warn: bool = u > POP - WARN and u < POP
	# the crank turns steadily, then spins up in the warning
	_crank.rotation.z -= dt * (TAU * (3.0 if warn else 0.8))
	# the box shivers in the warning; the coil stretches with the jack
	var sh: float = 0.03 * sin(t * 70.0) if warn else 0.0
	_box.position = Vector3(sh, 0, -sh)
	_coil.scale = Vector3(1.0, 0.1 + e * rise, 1.0)
	_coil.visible = e > 0.02
	_star_mat.emission_energy_multiplier = 3.5 if (warn and fmod(t, 0.2) < 0.1) else (1.2 + 2.0 * e)
	var cycle: int = int(floor(t / maxf(period, 0.01) + phase))
	if u >= POP and u < HOLD and cycle != _popped:
		_popped = cycle
		_burst.restart()
		_burst.emitting = true
		_confetti.restart()
		_confetti.emitting = true
		WorldAudio.at(self, "candy_jack_pop", global_position, 1.0, 40.0)
	if warn and cycle != _wound:
		_wound = cycle
		# SOUND: the tune's last few notes wound fast, just before the pop
		WorldAudio.at(self, "candy_jack_wind", global_position, 0.8, 30.0)


var _wound: int = -1


func _build() -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	_hat_rest = Vector3.ZERO
	# the box: its body stands on the floor below the hat (static, solid)
	_box = Node3D.new()
	add_child(_box)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, size.y - 0.3, size.z)
	var bcs := CollisionShape3D.new()
	bcs.shape = bs
	bcs.position = Vector3(0, -0.3 - (size.y - 0.3) * 0.5, 0)
	body.add_child(bcs)
	add_child(body)
	var side_a: StandardMaterial3D = Look.flat(tint, 0.55)
	var side_b: StandardMaterial3D = Look.flat(Color(1.0, 0.86, 0.3), 0.55)
	var trim: StandardMaterial3D = Look.flat(Color(1.0, 0.35, 0.5), 0.5)
	_box.add_child(Look.box(Vector3(size.x, size.y - 0.3, size.z), side_a, Vector3(0, -0.3 - (size.y - 0.3) * 0.5, 0)))
	# painted panels on the faces (a lighter square on each), a trim band round the top and foot
	for f: int in 4:
		var a: float = float(f) * PI * 0.5
		var n := Vector3(sin(a), 0, cos(a))
		var ext: float = hz if f % 2 == 0 else hx
		var panel := Look.box(Vector3(size.x * 0.62, (size.y - 0.3) * 0.6, 0.04), side_b if f % 2 == 0 else trim, n * (ext + 0.01) + Vector3(0, -0.3 - (size.y - 0.3) * 0.5, 0))
		panel.rotation.y = a
		_box.add_child(panel)
	_box.add_child(Look.box(Vector3(size.x + 0.12, 0.14, size.z + 0.12), trim, Vector3(0, -0.34, 0)))
	_box.add_child(Look.box(Vector3(size.x + 0.12, 0.14, size.z + 0.12), trim, Vector3(0, -size.y + 0.07, 0)))
	# the lid flaps, hinged open and lying back off two sides
	var lid: StandardMaterial3D = Look.flat(tint.lightened(0.2), 0.6)
	for sx: float in [-1.0, 1.0]:
		var flap := Look.box(Vector3(size.x * 0.5, 0.08, size.z), lid, Vector3(sx * (hx + size.x * 0.22), -0.42, 0))
		flap.rotation.z = sx * 0.35
		_box.add_child(flap)
	# the crank on the +X side
	_crank = Node3D.new()
	_crank.position = Vector3(hx + 0.12, -0.3 - (size.y - 0.3) * 0.5, 0)
	_crank.rotation.y = PI * 0.5
	_box.add_child(_crank)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.3), 0.3, 0.8)
	var arm := Look.box(Vector3(0.12, 0.6, 0.08), gold, Vector3(0, 0.25, 0.05))
	_crank.add_child(arm)
	var knob := Look.cylinder(0.08, 0.3, Look.flat(Color(1.0, 0.3, 0.4), 0.4), Vector3(0, 0.52, 0.2))
	knob.rotation.x = PI * 0.5
	_crank.add_child(knob)
	# the hat (the platform you ride): kinematic, sits flush with the rim at rest
	_hat = AnimatableBody3D.new()
	_hat.sync_to_physics = false
	_hat.collision_layer = 1
	_hat.collision_mask = 0
	var hs := BoxShape3D.new()
	hs.size = Vector3(size.x - 0.2, 0.3, size.z - 0.2)
	var hcs := CollisionShape3D.new()
	hcs.shape = hs
	hcs.position = Vector3(0, -0.15, 0)
	_hat.add_child(hcs)
	add_child(_hat)
	var pad := Look.cylinder(minf(hx, hz) - 0.12, 0.3, Look.flat(Color(0.25, 0.12, 0.4), 0.6), Vector3(0, -0.15, 0), -1.0, 28)
	_hat.add_child(pad)
	_hat.add_child(Look.cylinder(minf(hx, hz) - 0.3, 0.04, Look.flat(Color(1.0, 0.95, 0.9), 0.5), Vector3(0, 0.005, 0), -1.0, 28))
	_star_mat = StandardMaterial3D.new()
	_star_mat.albedo_color = Color(1.0, 0.85, 0.2)
	_star_mat.emission_enabled = true
	_star_mat.emission = Color(1.0, 0.8, 0.2)
	_star_mat.emission_energy_multiplier = 1.2
	var star := CylinderMesh.new()
	star.top_radius = 0.42
	star.bottom_radius = 0.42
	star.height = 0.05
	star.radial_segments = 5
	star.rings = 1
	_hat.add_child(Look.mesh_node(star, _star_mat, Vector3(0, 0.03, 0)))
	# the jack's face under the hat brim (seen when it springs out): a round clown face, red nose
	var face := Look.sphere(0.55, Look.flat(Color(1.0, 0.92, 0.85), 0.6), Vector3(0, -0.75, 0))
	_hat.add_child(face)
	_hat.add_child(Look.sphere(0.14, Look.flat(Color(1.0, 0.15, 0.2), 0.3, 0.0, 0.6), Vector3(0, -0.75, -0.55)))
	for sx: float in [-1.0, 1.0]:
		_hat.add_child(Look.sphere(0.07, Look.flat(Color(0.1, 0.1, 0.15), 0.4), Vector3(sx * 0.2, -0.6, -0.5)))
		_hat.add_child(Look.sphere(0.2, Look.flat(Color(1.0, 0.45, 0.2), 0.8), Vector3(sx * 0.5, -0.55, 0)))
	var ruff := Look.cylinder(0.75, 0.16, Look.flat(Color(1.0, 0.95, 0.4), 0.6), Vector3(0, -1.28, 0), 0.5, 16)
	_hat.add_child(ruff)
	# the coil below (scaled with the extension; hidden while at rest inside the box)
	_coil = Node3D.new()
	_coil.position = Vector3(0, -1.3, 0)
	add_child(_coil)
	var coil_mat: StandardMaterial3D = Look.flat(Color(0.85, 0.87, 0.92), 0.25, 0.9)
	for i: int in 6:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.26
		tm.outer_radius = 0.34
		tm.rings = 16
		tm.ring_segments = 6
		var ring := Look.mesh_node(tm, coil_mat, Vector3(0, float(i) / 5.0, 0))
		ring.rotation.x = 0.12
		_coil.add_child(ring)
	# a kick detector over the hat: anyone standing on it when it pops is launched
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
	_hat.add_child(_area)
	var vis := AABB(Vector3(-5, -3, -5), Vector3(10, 16, 10))
	_burst = Fx.sparks({"amount": 34, "lifetime": 0.6, "shape": "ring", "ring_radius": minf(hx, hz) * 0.9,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(6.0, 13.0), "gravity": Vector3(0, -12, 0),
		"color": Fx.hot(Color(1.0, 0.85, 0.35), 2.2), "aabb": vis})
	_burst.position = Vector3(0, 0.1, 0)
	add_child(_burst)
	_confetti = CandyFx.confetti(1.2, 40, 5.0)
	_confetti.position = Vector3(0, 0.3, 0)
	add_child(_confetti)
