class_name ArmadaPropeller
extends Node3D
## Storm Armada: a lift propeller - a great brass fan lying on its back in a caged ring, blowing
## straight up. While it runs flat out its column is an updraft (like WindZone) that carries you
## up; a pulsing one spins down and back up on the course clock and, for `warn` seconds before it
## catches again, coughs steam and its ring lights up - step in then. `on_fraction` 1 = it never
## stops. Positioned at the floor point at the centre of the fan (the fan sits just below it, under
## a grille you can stand on - the level's own platform).

@export var size: Vector3 = Vector3(2.6, 10.0, 2.6)
## Upward acceleration while running (gravity is 30 rising / 42 falling).
@export var push: float = 80.0
@export var max_rise: float = 12.0
@export var period: float = 5.0
@export var on_fraction: float = 1.0
@export var phase: float = 0.0
@export var warn: float = 0.9

const BRASS := Color(0.86, 0.63, 0.3)

var _area: Area3D
var _rotor: Node3D
var _spin: float = 0.0
var _speed: float = 0.0
var _ring_mat: StandardMaterial3D
var _streaks: GPUParticles3D
var _mist: GPUParticles3D
var _cough: GPUParticles3D
var _loop: AudioStreamPlayer3D
var _was_on: bool = false


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	_area.position = Vector3(0, size.y * 0.5, 0)
	add_child(_area)
	_build_visual()
	_loop = WorldAudio.loop("armada_prop_loop", self, -7.0, 26.0, 5.0, is_on_at(Game.course_time))
	_was_on = is_on_at(Game.course_time)
	_speed = 1.0 if _was_on else 0.0
	_apply(Game.course_time)


func is_on_at(time: float) -> bool:
	return on_fraction >= 1.0 or fposmod(time / period + phase, 1.0) < on_fraction


## Seconds until it next catches (0 while running).
func time_until_on(time: float) -> float:
	if is_on_at(time):
		return 0.0
	return (1.0 - fposmod(time / period + phase, 1.0)) * period


## Seconds of lift left (INF for a steady fan, 0 while stopped).
func on_left(time: float) -> float:
	if on_fraction >= 1.0:
		return INF
	var u: float = fposmod(time / period + phase, 1.0)
	return (on_fraction - u) * period if u < on_fraction else 0.0


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	if not is_on_at(t):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var dv := Vector3(0, push * dt, 0)
			if p.velocity.y > max_rise:
				dv.y = 0.0
			p.add_impulse(dv)


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var on: bool = is_on_at(t)
	var target: float = 1.0 if on else (0.25 if time_until_on(t) < warn else 0.0)
	_speed = move_toward(_speed, target, dt * (3.0 if on else 0.8))
	_spin += dt * TAU * 5.0 * _speed
	_rotor.rotation.y = fposmod(_spin, TAU)
	_apply(t)


func _apply(t: float) -> void:
	var on: bool = is_on_at(t)
	var warning: bool = not on and time_until_on(t) < warn
	if _streaks.emitting != on:
		_streaks.emitting = on
		_mist.emitting = on
	if _cough.emitting != warning:
		_cough.emitting = warning
	WorldAudio.set_active(_loop, on)
	if on and not _was_on and on_fraction < 1.0:
		WorldAudio.at(self, "armada_prop_spinup", global_position, 0.8, 30.0)
	_was_on = on
	var glow: float = 0.4
	if on:
		glow = 1.8
	elif warning:
		glow = 0.6 + 2.2 * (1.0 - time_until_on(t) / warn) * (0.7 + 0.3 * sin(t * 30.0))
	_ring_mat.emission_energy_multiplier = glow


func _build_visual() -> void:
	var r: float = minf(size.x, size.z) * 0.5
	var brass: StandardMaterial3D = Look.flat(BRASS, 0.3, 0.9)
	var iron: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.22), 0.45, 0.8)
	# the shroud ring below the grille and the fan hub (all below the floor line)
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.92
	tm.outer_radius = r * 1.08
	tm.rings = 40
	tm.ring_segments = 10
	add_child(Look.mesh_node(tm, brass, Vector3(0, -0.45, 0)))
	_ring_mat = Look.flat(Color(1.0, 0.72, 0.35), 0.4, 0.0, 0.4).duplicate() as StandardMaterial3D
	var glow_ring := TorusMesh.new()
	glow_ring.inner_radius = r * 0.86
	glow_ring.outer_radius = r * 0.92
	glow_ring.rings = 40
	glow_ring.ring_segments = 6
	add_child(Look.mesh_node(glow_ring, _ring_mat, Vector3(0, -0.3, 0)))
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, -0.75, 0)
	add_child(_rotor)
	_rotor.add_child(Look.cylinder(r * 0.18, 0.4, brass, Vector3.ZERO, -1.0, 16))
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0
		var blade := Look.box(Vector3(r * 0.8, 0.05, r * 0.26), brass, Vector3(cos(a), 0, -sin(a)) * r * 0.52)
		blade.rotation = Vector3(0, a, 0.35)
		_rotor.add_child(blade)
	# struts from the ring down to the motor housing
	add_child(Look.cylinder(r * 0.25, 1.2, iron, Vector3(0, -1.5, 0), r * 0.18, 12))
	for i: int in 3:
		var a2: float = TAU * float(i) / 3.0 + 0.4
		var strut := Look.box(Vector3(0.1, 0.1, r * 0.95), iron, Vector3(cos(a2), 0, -sin(a2)) * r * 0.5 + Vector3(0, -1.0, 0))
		strut.rotation.y = a2 + PI * 0.5
		add_child(strut)
	var vis := AABB(Vector3(-r - 5.0, -2.0, -r - 5.0), Vector3(r * 2.0 + 10.0, size.y + 8.0, r * 2.0 + 10.0))
	var life: float = size.y / 11.0 + 0.3
	_streaks = Fx.emitter({"amount": 50, "lifetime": life, "emitting": false, "shape": "ring", "ring_radius": r * 0.85,
		"ring_inner": r * 0.2, "ring_height": 0.1, "dir": Vector3.UP, "spread": 4.0, "speed": Vector2(10.0, 13.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.05, 1.2),
		"color": Color(0.9, 0.95, 1.0, 0.45), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	_streaks.position = Vector3(0, 0.1, 0)
	add_child(_streaks)
	_mist = Fx.emitter({"amount": 26, "lifetime": life * 1.3, "emitting": false, "shape": "ring", "ring_radius": r * 0.7,
		"ring_inner": 0.0, "ring_height": 0.1, "dir": Vector3.UP, "spread": 12.0, "speed": Vector2(6.0, 9.0),
		"damping": Vector2(1.0, 2.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.3, "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-90, 90), "color": Color(0.82, 0.86, 0.92, 0.35),
		"fade": PackedFloat32Array([0.0, 0.9, 0.0]), "aabb": vis})
	_mist.position = Vector3(0, 0.1, 0)
	add_child(_mist)
	_cough = Fx.emitter({"amount": 14, "lifetime": 0.9, "emitting": false, "shape": "ring", "ring_radius": r * 0.8,
		"ring_inner": r * 0.3, "dir": Vector3.UP, "spread": 40.0, "speed": Vector2(1.2, 2.8), "gravity": Vector3(0, -0.5, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.8, "curve": "puff", "color": Color(0.9, 0.9, 0.92, 0.55),
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	_cough.position = Vector3(0, 0.1, 0)
	add_child(_cough)
