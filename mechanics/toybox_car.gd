class_name ToyboxCar
extends MovingPlatform
## Toybox Tumble: a WIND-UP CAR you ride. A tin toy bus whose flat roof is the platform. It sits
## at one end with its big brass key winding down, then (after a visible shudder and a flurry of
## key-turns, `shiver` s before it moves) rattles across to the other end on the course clock and
## waits there. Ping-pong like a MovingPlatform (same offset_at / `points` / `period` / `dwell`
## contract, so the route bot's mover steps work on it) but dressed as a toy car: wheels that turn
## with the ground speed, headlights, a key that spins while it drives. Visual and sound only on
## top of the deterministic motion. The car faces its travel direction on the first leg
## (`heading_deg` = the node's yaw; 0 faces -Z).

@export var tint: Color = Color(0.95, 0.28, 0.25)
@export var heading_deg: float = 0.0
## Seconds of shudder before it sets off (the tell for a rider who is not aboard yet).
@export var shiver: float = 1.0

var _body: Node3D
var _wheels: Array[Node3D] = []
var _key: Node3D
var _prev_offset: Vector3 = Vector3.ZERO
var _loop: AudioStreamPlayer3D
var _dust: GPUParticles3D
var _was_moving: bool = false
var _was_shiver: bool = false
var _key_angle: float = 0.0


func _hums() -> bool:
	return false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	rotation_degrees.y = heading_deg
	_origin = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	add_child(Look.platform_box(size, style))
	_build_car()
	position = _origin + offset_at(Game.course_time)
	_prev_offset = offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	# SOUND: toybox_car_whirr (loop) - the clockwork spring whirring while the car drives
	_loop = WorldAudio.loop("toybox_car_whirr", self, -17.0, 22.0, 4.0, false)


func snap_to_clock() -> void:
	super.snap_to_clock()
	_prev_offset = offset_at(Game.course_time)


func _build_car() -> void:
	_body = Node3D.new()
	add_child(_body)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var shell: StandardMaterial3D = Look.flat(tint, 0.4, 0.15)
	var dark: StandardMaterial3D = Look.flat(Color(0.12, 0.13, 0.2), 0.3, 0.2)
	var cream: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.82), 0.5)
	var chrome: StandardMaterial3D = Look.flat(Color(0.85, 0.87, 0.92), 0.2, 0.9)
	var h: float = 1.15
	var yc: float = -size.y * 0.5 - h * 0.5
	_body.add_child(Look.box(Vector3(size.x - 0.1, h, size.z - 0.2), shell, Vector3(0, yc, 0)))
	# a cream stripe round the middle and lit windows along both flanks
	_body.add_child(Look.box(Vector3(size.x + 0.02, 0.14, size.z - 0.1), cream, Vector3(0, yc - 0.35, 0)))
	var n_win: int = maxi(int(size.z / 1.3), 2)
	for sx: float in [-1.0, 1.0]:
		for i: int in n_win:
			var z: float = -hz + 0.85 + (size.z - 1.7) * (float(i) + 0.5) / float(n_win)
			_body.add_child(Look.box(Vector3(0.05, 0.42, (size.z - 1.7) / float(n_win) - 0.22), dark, Vector3(sx * (hx - 0.03), yc + 0.2, z)))
	# bumpers and the two big headlights (front is local -Z)
	_body.add_child(Look.box(Vector3(size.x, 0.2, 0.22), chrome, Vector3(0, yc - 0.3, -hz + 0.02)))
	_body.add_child(Look.box(Vector3(size.x, 0.2, 0.22), chrome, Vector3(0, yc - 0.3, hz - 0.02)))
	for sx: float in [-1.0, 1.0]:
		_body.add_child(Look.sphere(0.22, Look.flat(Color(1.0, 0.95, 0.7), 0.3, 0.0, 2.2), Vector3(sx * (hx - 0.5), yc + 0.12, -hz + 0.06)))
		_body.add_child(Look.sphere(0.14, Look.flat(Color(1.0, 0.2, 0.15), 0.3, 0.0, 1.6), Vector3(sx * (hx - 0.5), yc + 0.12, hz - 0.06)))
	# four wheels (axle along x), they turn with the ground speed
	var wheel_mat: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.17), 0.8)
	var hub_mat: StandardMaterial3D = Look.flat(Color(1.0, 0.82, 0.25), 0.35, 0.5)
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var w := Node3D.new()
			w.position = Vector3(sx * (hx - 0.05), yc - h * 0.5 + 0.12, sz * (hz - 1.05))
			_body.add_child(w)
			var tire := Look.cylinder(0.62, 0.42, wheel_mat, Vector3.ZERO, -1.0, 20)
			tire.rotation.z = PI * 0.5
			w.add_child(tire)
			var hub := Look.cylinder(0.3, 0.46, hub_mat, Vector3.ZERO, -1.0, 12)
			hub.rotation.z = PI * 0.5
			w.add_child(hub)
			# a spoke so the turning is readable
			w.add_child(Look.box(Vector3(0.5, 0.1, 0.5), dark, Vector3(sx * 0.2, 0, 0)))
			_wheels.append(w)
	# the brass wind-up key at the back: stem and two round ears, spinning
	_key = Node3D.new()
	_key.position = Vector3(0, yc + 0.15, hz + 0.05)
	_body.add_child(_key)
	var brass: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.28), 0.3, 0.85)
	var stem := Look.cylinder(0.08, 0.7, brass, Vector3(0, 0, 0.3), -1.0, 8)
	stem.rotation.x = PI * 0.5
	_key.add_child(stem)
	for s: float in [-1.0, 1.0]:
		var ear := Look.sphere(0.34, brass, Vector3(s * 0.34, 0, 0.7))
		ear.scale = Vector3(1.0, 1.0, 0.22)
		_key.add_child(ear)
	# a puff of dust behind the wheels while it drives
	_dust = Fx.emitter({"amount": 14, "lifetime": 0.7, "local": false, "shape": "box", "extents": Vector3(hx, 0.05, 0.3),
		"dir": Vector3.UP, "spread": 40.0, "speed": Vector2(0.4, 1.2), "gravity": Vector3(0, 0.6, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.7, "color": Color(0.95, 0.88, 0.75, 0.5), "scale": Vector2(0.6, 1.1),
		"curve": "puff", "emitting": false, "aabb": AABB(Vector3(-8, -4, -8), Vector3(16, 8, 16))})
	_dust.position = Vector3(0, yc - h * 0.5 - 0.35, hz - 0.2)
	add_child(_dust)


## True when the car is parked at `time` and stays parked for `hold` more seconds.
func parked_over(time: float, a: float, b: float) -> bool:
	var base: Vector3 = offset_at(time + a)
	var s: float = a
	while s <= b:
		if offset_at(time + s).distance_to(base) > 0.02:
			return false
		s += 0.05
	return offset_at(time + b).distance_to(base) <= 0.02


## Seconds until the car next starts moving from where it sits (0 while moving).
func time_to_depart(time: float) -> float:
	if offset_at(time).distance_to(offset_at(time + 0.05)) > 0.0008:
		return 0.0
	var s: float = 0.05
	while s < shiver + 0.3:
		if offset_at(time + s).distance_to(offset_at(time)) > 0.02:
			return s
		s += 0.05
	return period


func _physics_process(_dt: float) -> void:
	position = _origin + offset_at(Game.course_time)


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var off: Vector3 = offset_at(t)
	var vel: Vector3 = (off - _prev_offset) / maxf(dt, 0.0001) if dt > 0.0 else Vector3.ZERO
	_prev_offset = off
	var speed: float = vel.length()
	var forward: Vector3 = -global_basis.z
	var along: float = vel.dot(forward)
	var moving: bool = speed > 0.3
	for w: Node3D in _wheels:
		w.rotation.x -= along / 0.62 * dt
	var depart: float = time_to_depart(t)
	var shiv: bool = not moving and depart < shiver
	# the key spins while it drives, flurries just before it sets off, creeps backwards at rest
	var rate: float = 4.0 + speed * 0.9 if moving else (9.0 if shiv else -0.35)
	_key_angle += rate * dt
	_key.rotation.z = _key_angle
	if shiv:
		var k: float = clampf(1.0 - depart / maxf(shiver, 0.1), 0.0, 1.0)
		_body.position = Vector3(sin(t * 70.0) * 0.025 * (0.4 + k), 0.0, cos(t * 61.0) * 0.02 * k)
	elif _body.position != Vector3.ZERO:
		_body.position = Vector3.ZERO
	if shiv != _was_shiver:
		_was_shiver = shiv
		if shiv:
			# SOUND: toybox_car_wind - ratcheting key turns, a second before the car rattles off
			WorldAudio.at(self, "toybox_car_wind", global_position, 0.7, 30.0)
	if moving != _was_moving:
		_was_moving = moving
		_dust.emitting = moving
		WorldAudio.set_active(_loop, moving)
		if not moving:
			# SOUND: toybox_car_stop - a little tin clunk as it runs down
			WorldAudio.at(self, "toybox_car_stop", global_position, 0.6, 28.0)
	if moving:
		_dust.global_position = global_position + Vector3(0, -size.y * 0.5 - 1.5, 0) - forward * (signf(along) * size.z * 0.5)
