class_name BalanceCounterweight
extends Node3D
## Balance Works' counterweight lift: two cages hung from one cable over a pair of
## pulley wheels. Your weight is the only thing that moves it - stand on cage A and it
## sinks while cage B climbs; step across onto B and B sinks while A climbs. Left alone
## it holds for a moment, then eases back to level. Both cages have gold mantle lips, so
## the move is: ride A down until B towers over you, mantle up onto B, then get off B
## (another mantle) before it sinks away.
## The node sits at cage A's top centre (level position); cage B's top is at b_offset.
## Balance s: +1 = A fully down / B fully up, -1 = the other way round.

@export var car_size: Vector3 = Vector3(3.0, 1.0, 3.0)
## World offset from cage A's top centre to cage B's (level position).
@export var b_offset: Vector3 = Vector3(0, 0, -6)
## Metres each cage moves at full swing.
@export var travel: float = 1.8
## Balance units per second while someone stands on a cage.
@export var rate: float = 0.85
## Balance units per second it eases back to level once left alone.
@export var return_rate: float = 0.3
## Seconds it holds its position after the last touch before easing back.
@export var hold_time: float = 1.0
## Pulley axle height above the level position.
@export var gantry_height: float = 8.5

const ACCEL: float = 5.0

var car_a: Car
var car_b: Car
var _s: float = 0.0
var _v: float = 0.0
var _idle: float = 99.0
var _wheels: Array[Node3D] = []
var _cables: Array[MeshInstance3D] = []
var _wheel_sparks: Array[GPUParticles3D] = []
var _thud: Array[GPUParticles3D] = []
var _was_at_stop: bool = true
# sound (side effect only): chain over the pulleys while it moves, a thud at the end stops
var _chain: AudioStreamPlayer3D


class Car extends AnimatableBody3D:
	var loaded_frame: int = -100
	var glow: StandardMaterial3D

	func apply_rider_load(_point: Vector3, _force: float) -> void:
		loaded_frame = Engine.get_physics_frames()

	func is_loaded() -> bool:
		return Engine.get_physics_frames() - loaded_frame <= 2

	func is_ledge() -> bool:
		return true


func _ready() -> void:
	add_to_group("resettable")
	var perp: Vector3 = b_offset.normalized().cross(Vector3.UP).normalized()
	car_a = _make_car(Vector3.ZERO, perp)
	car_b = _make_car(b_offset, perp)
	# gantry: a beam over both cages on two lattice legs outside the walkway, pulley wheels
	var teal := Look.flat(Color(0.20, 0.52, 0.56), 0.6, 0.3)
	var white := Look.flat(Color(0.92, 0.94, 0.92), 0.6, 0.2)
	var steel := Look.flat(Color(0.14, 0.15, 0.18), 0.5, 0.6)
	var mid: Vector3 = b_offset * 0.5
	var span: float = b_offset.length() + 2.0
	var beam := Look.box(Vector3(0.6, 0.6, span), teal, mid + Vector3(0, gantry_height + 1.0, 0))
	beam.basis = Basis.looking_at(b_offset.normalized(), Vector3.UP)
	add_child(beam)
	var leg_off: float = car_size.x * 0.5 + 1.1
	for side: float in [-1.0, 1.0]:
		for end: Vector3 in [Vector3.ZERO, b_offset]:
			var foot: Vector3 = end + perp * side * leg_off
			add_child(Look.box(Vector3(0.3, gantry_height + 16.0, 0.3), white, foot + Vector3(0, gantry_height + 1.0 - (gantry_height + 16.0) * 0.5, 0)))
			var arm := Look.box(Vector3(0.25, 0.25, leg_off), teal, end + perp * side * leg_off * 0.5 + Vector3(0, gantry_height + 1.0, 0))
			arm.basis = Basis.looking_at(perp, Vector3.UP)
			add_child(arm)
	var wheel_r: float = 0.9
	for end: Vector3 in [Vector3.ZERO, b_offset]:
		var holder := Node3D.new()
		holder.position = end + Vector3(0, gantry_height, 0)
		holder.basis = Basis.looking_at(perp, Vector3.UP)
		add_child(holder)
		var wheel := Node3D.new()
		holder.add_child(wheel)
		var w := Look.cylinder(wheel_r, 0.28, Look.flat(Color(0.98, 0.78, 0.25), 0.4, 0.5, 0.3), Vector3.ZERO, -1.0, 24)
		w.rotation.x = PI * 0.5
		wheel.add_child(w)
		for i: int in 3:
			var spoke := Look.box(Vector3(wheel_r * 1.9, 0.14, 0.34), steel)
			spoke.rotation.z = TAU * float(i) / 6.0
			wheel.add_child(spoke)
		_wheels.append(wheel)
		var sp: GPUParticles3D = BalanceFx.sparks(Color(1.0, 0.8, 0.4), 18, 3.0, 0.6, Vector3(0, -1, 0), 55.0)
		sp.position = end + Vector3(0, gantry_height - wheel_r, 0)
		sp.emitting = false
		add_child(sp)
		_wheel_sparks.append(sp)
		# thud puff when a cage bottoms out
		var th: GPUParticles3D = BalanceFx.burst(Color(0.9, 1.0, 0.98, 0.7), 26, 3.5, 0.9, 0.85, 1.0, 0.5)
		add_child(th)
		_thud.append(th)
	# cable across the top of the wheels
	var top_cable := Look.box(Vector3(0.07, 0.07, b_offset.length()), steel, mid + Vector3(0, gantry_height + wheel_r, 0))
	top_cable.basis = Basis.looking_at(b_offset.normalized(), Vector3.UP)
	add_child(top_cable)
	for i: int in 2:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 1.0
		cm.radial_segments = 6
		var c := Look.mesh_node(cm, steel)
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(c)
		_cables.append(c)
	_apply()
	_chain = WorldAudio.loop("pulley_rattle", self, -40.0, 26.0, 5.0, false)
	if _chain != null:
		_chain.position = mid + Vector3(0, gantry_height * 0.6, 0)


func _make_car(top: Vector3, perp: Vector3) -> Car:
	var car := Car.new()
	car.sync_to_physics = false
	car.collision_layer = 1
	car.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = car_size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	car.add_child(cs)
	car.add_child(Look.platform_box(car_size, "tilt"))
	var hx: float = car_size.x * 0.5
	var hy: float = car_size.y * 0.5
	var hz: float = car_size.z * 0.5
	var lip: StandardMaterial3D = Look.flat(LedgeBlock.LIP_COLOR, 0.35, 0.2, 1.6)
	for sx: float in [-1.0, 1.0]:
		car.add_child(Look.box(Vector3(0.08, 0.16, car_size.z + 0.16), lip, Vector3(sx * (hx + 0.04), hy - 0.09, 0)))
	for sz: float in [-1.0, 1.0]:
		car.add_child(Look.box(Vector3(car_size.x + 0.16, 0.16, 0.08), lip, Vector3(0, hy - 0.09, sz * (hz + 0.04))))
	# weight-plate glow band round the cage: lights up while it carries someone
	car.glow = Look.flat(Color(0.3, 0.95, 0.85), 0.4, 0.0, 0.3).duplicate() as StandardMaterial3D
	car.add_child(Look.box(Vector3(car_size.x + 0.1, 0.14, car_size.z + 0.1), car.glow, Vector3(0, -hy + 0.2, 0)))
	# the yoke: rods up the cage sides to a crossbar the cable hangs from (clear of the walkway)
	var steel := Look.flat(Color(0.14, 0.15, 0.18), 0.5, 0.6)
	var bar_y: float = hy + 3.0
	for side: float in [-1.0, 1.0]:
		var p: Vector3 = perp * side * (hx + 0.12)
		car.add_child(Look.box(Vector3(0.12, 3.2, 0.12), steel, p + Vector3(0, hy + 1.5, 0)))
	var cross := Look.box(Vector3(0.18, 0.18, car_size.x + 0.4), Look.flat(Color(0.20, 0.52, 0.56), 0.6, 0.3), Vector3(0, bar_y, 0))
	cross.basis = Basis.looking_at(perp, Vector3.UP)
	car.add_child(cross)
	# counterweight plates slung under the cage
	car.add_child(Look.box(Vector3(car_size.x * 0.6, 0.7, car_size.z * 0.6), Look.flat(Color(0.98, 0.78, 0.25).darkened(0.2), 0.6, 0.3), Vector3(0, -hy - 0.4, 0)))
	car.position = top - Vector3(0, hy, 0)
	add_child(car)
	return car


## Current balance (+1: A down / B up).
func balance() -> float:
	return _s


## Top-centre of cage A / B right now (world).
func top_a() -> Vector3:
	return car_a.global_position + Vector3(0, car_size.y * 0.5, 0)


func top_b() -> Vector3:
	return car_b.global_position + Vector3(0, car_size.y * 0.5, 0)


func _apply() -> void:
	var hy: float = car_size.y * 0.5
	car_a.position = Vector3(0, -travel * _s - hy, 0)
	car_b.position = b_offset + Vector3(0, travel * _s - hy, 0)
	for i: int in 2:
		_wheels[i].rotation.z = _s * travel / 0.9 * (1.0 if i == 0 else -1.0)
		var car: Car = car_a if i == 0 else car_b
		var a: Vector3 = car.position + Vector3(0, hy + 3.0, 0)
		var b: Vector3 = (Vector3.ZERO if i == 0 else b_offset) + Vector3(0, gantry_height, 0)
		var d: Vector3 = b - a
		_cables[i].transform = Transform3D(Basis(Vector3.RIGHT, Vector3.UP * d.length(), Vector3.BACK), (a + b) * 0.5)


## Sound only: the chain running over the pulleys, and a cage bottoming out.
func _sound(moving: bool, stopped_car: Car) -> void:
	if stopped_car != null:
		WorldAudio.at(self, "counterweight_thud", stopped_car.global_position, 0.7, 35.0)
	if _chain != null:
		var k: float = clampf(absf(_v) / rate, 0.0, 1.0)
		WorldAudio.set_active(_chain, moving)
		_chain.volume_db = -10.0 + linear_to_db(maxf(k, 0.05))
		_chain.pitch_scale = 0.8 + 0.3 * k


func _physics_process(dt: float) -> void:
	var la: bool = car_a.is_loaded()
	var lb: bool = car_b.is_loaded()
	var want: float = 0.0
	if la or lb:
		_idle = 0.0
		var target: float = 1.0 if la and not lb else (-1.0 if lb and not la else _s)
		want = clampf((target - _s) * 6.0, -rate, rate)
	else:
		_idle += dt
		if _idle > hold_time:
			want = clampf(-_s * 3.0, -return_rate, return_rate)
	_v = move_toward(_v, want, ACCEL * dt)
	_s = clampf(_s + _v * dt, -1.0, 1.0)
	if absf(_s) >= 1.0:
		_v = 0.0
	var at_stop: bool = absf(_s) > 0.985
	var stopped: Car = null
	if at_stop and not _was_at_stop:
		var car: Car = car_a if _s > 0.0 else car_b
		_thud[0 if _s > 0.0 else 1].global_position = car.global_position - Vector3(0, car_size.y * 0.5 + 0.8, 0)
		_thud[0 if _s > 0.0 else 1].restart()
		stopped = car
	_was_at_stop = at_stop
	var moving: bool = absf(_v) > 0.2
	_sound(absf(_v) > 0.05, stopped)
	for sp: GPUParticles3D in _wheel_sparks:
		if sp.emitting != moving:
			sp.emitting = moving
	car_a.glow.emission_energy_multiplier = 2.6 if la else 0.3
	car_b.glow.emission_energy_multiplier = 2.6 if lb else 0.3
	_apply()


func reset_state() -> void:
	_s = 0.0
	_v = 0.0
	_idle = 99.0
	_apply()
	car_a.reset_physics_interpolation()
	car_b.reset_physics_interpolation()
