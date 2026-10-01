class_name SakuraShuriken
extends Node3D
## Sakura Peaks: a NINJA SHURIKEN on a rail. A giant four-pointed steel star stands on edge in a
## lacquered groove and whirls along it from one end to the other and back, on the course clock.
## At each end it waits in its socket for `dwell` of the leg, spinning up: the groove lights in a
## running chase toward the far end and the star glows hotter - then it flies down the rail.
## Touching it sends you back to the checkpoint. Cross its lane while it waits at the far end.
## A pure function of Game.course_time.
## Node origin = the floor point at the rail's start; `to` is the rail's end (local offset, level).

@export var to: Vector3 = Vector3(8, 0, 0)
@export var period: float = 4.0
@export var phase: float = 0.0
## Fraction of each leg spent waiting in the socket (the tell).
@export var dwell: float = 0.4
@export var radius: float = 0.8

var _star: Node3D
var _spinner: Node3D
var _glow_mat: StandardMaterial3D
var _chase: Array[MeshInstance3D] = []
var _chase_mats: Array[StandardMaterial3D] = []
var _sparks: GPUParticles3D
var _whir: AudioStreamPlayer3D
var _launched: int = -1


func _ready() -> void:
	_build()
	_apply(Game.course_time)
	add_to_group("course_clock")


func _u(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0)


## 0 (start) .. 1 (end) along the rail at `time`.
func travel_at(time: float) -> float:
	var u: float = _u(time)
	var leg: float = fmod(u * 2.0, 1.0)
	var k: float = clampf((leg - dwell) / maxf(1.0 - dwell, 0.01), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return k if u < 0.5 else 1.0 - k


## True while it waits in a socket (charging) at `time`.
func is_waiting_at(time: float) -> bool:
	return fmod(_u(time) * 2.0, 1.0) < dwell


## World position of the star's centre at `time`.
func star_at(time: float) -> Vector3:
	return global_transform * (to * travel_at(time) + Vector3(0, radius + 0.05, 0))


## The star stays more than `clearance` (flat distance) from world point `p` over [now + a, now + b].
func lane_clear(p: Vector3, clearance: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		var q: Vector3 = star_at(Game.course_time + s)
		if Vector2(q.x - p.x, q.z - p.z).length() < clearance:
			return false
		s += 0.03
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)
	_star.reset_physics_interpolation()


func _apply(time: float) -> void:
	_star.position = to * travel_at(time) + Vector3(0, radius + 0.05, 0)


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var u: float = _u(t)
	var leg: float = fmod(u * 2.0, 1.0)
	var waiting: bool = leg < dwell
	var charge: float = clampf(leg / maxf(dwell, 0.01), 0.0, 1.0) if waiting else 1.0
	_spinner.rotation.z -= dt * TAU * (1.0 + 3.0 * charge)
	_glow_mat.emission_energy_multiplier = 0.4 + (2.6 * charge if waiting else 1.6)
	# the chase: the groove lights toward where it is about to fly
	var going_out: bool = u < 0.5
	var n: int = _chase.size()
	for i: int in n:
		var k: float = float(i) / float(maxi(n - 1, 1))
		var along: float = k if going_out else 1.0 - k
		var lit: float = 0.0
		if waiting and leg > dwell * 0.25:
			var front: float = (leg - dwell * 0.25) / (dwell * 0.75)
			lit = clampf(1.0 - absf(along - front) * 4.0, 0.0, 1.0) + 0.25
		_chase_mats[i].emission_energy_multiplier = 0.2 + 2.4 * lit
	var cycle: int = int(floor((t / maxf(period, 0.01) + phase) * 2.0))
	if not waiting and cycle != _launched:
		_launched = cycle
		_sparks.restart()
		_sparks.emitting = true
		# SOUND: the star ringing off its socket as it flies
		WorldAudio.at(self, "sakura_shuriken_ring", _star.global_position, 0.9, 40.0)
	if _whir != null:
		WorldAudio.set_active(_whir, not waiting)


func _build() -> void:
	var dir: Vector3 = to.normalized() if to.length() > 0.01 else Vector3.RIGHT
	var len: float = to.length()
	var yaw: float = atan2(-dir.z, dir.x)
	# the rail: a lacquered black groove with a vermilion lip, sockets at both ends
	var rail := Node3D.new()
	rail.rotation.y = yaw
	add_child(rail)
	rail.add_child(Look.box(Vector3(len + 1.6, 0.06, 0.5), SakuraDecor.mat(SakuraDecor.LACQUER, 0.4), Vector3(len * 0.5, 0.03, 0)))
	for sz: float in [-1.0, 1.0]:
		rail.add_child(Look.box(Vector3(len + 1.6, 0.08, 0.08), SakuraDecor.mat(SakuraDecor.VERMILION, 0.5), Vector3(len * 0.5, 0.05, sz * 0.27)))
	for sx: float in [0.0, 1.0]:
		var sock := Look.box(Vector3(0.6, 0.5, 0.9), SakuraDecor.mat(SakuraDecor.DARK_WOOD, 0.7), Vector3(sx * len + (0.9 if sx > 0.5 else -0.9), 0.25, 0))
		rail.add_child(sock)
	var n: int = maxi(int(len / 0.8), 4)
	for i: int in n:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.15, 0.08)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.12)
		m.emission_energy_multiplier = 0.2
		var dash := Look.box(Vector3(0.4, 0.04, 0.12), m, Vector3((float(i) + 0.5) * len / float(n), 0.07, 0))
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rail.add_child(dash)
		_chase.append(dash)
		_chase_mats.append(m)
	# the star: stands on edge in the groove, spinning in the plane of the rail
	_star = Node3D.new()
	_star.rotation.y = yaw
	add_child(_star)
	_spinner = Node3D.new()
	_star.add_child(_spinner)
	var steel: StandardMaterial3D = SakuraDecor.mat(Color(0.62, 0.64, 0.7), 0.25, 0.9)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.9, 0.3, 0.2)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.3, 0.15)
	_glow_mat.emission_energy_multiplier = 0.4
	for i: int in 4:
		var blade := Node3D.new()
		blade.rotation.z = float(i) * PI * 0.5
		_spinner.add_child(blade)
		var pm := PrismMesh.new()
		pm.size = Vector3(radius * 0.7, radius, 0.08)
		var b := Look.mesh_node(pm, steel, Vector3(0, radius * 0.5, 0))
		blade.add_child(b)
		var edge := Look.box(Vector3(0.05, radius * 0.7, 0.1), _glow_mat, Vector3(radius * 0.14, radius * 0.5, 0))
		edge.rotation.z = -0.33
		blade.add_child(edge)
	var hub := Look.cylinder(radius * 0.26, 0.16, SakuraDecor.mat(SakuraDecor.LACQUER, 0.4, 0.4), Vector3.ZERO, -1.0, 16)
	hub.rotation.x = PI * 0.5
	_spinner.add_child(hub)
	var ring := Look.cylinder(radius * 0.12, 0.2, _glow_mat, Vector3.ZERO, -1.0, 12)
	ring.rotation.x = PI * 0.5
	_spinner.add_child(ring)
	var kill := KillZone.new()
	kill.show_mesh = false
	kill.size = Vector3(radius * 1.7, radius * 1.7, 0.5)
	_star.add_child(kill)
	_sparks = Fx.sparks({"amount": 26, "lifetime": 0.45, "shape": "sphere", "radius": 0.2, "dir": Vector3.UP, "spread": 60.0,
		"speed": Vector2(3.0, 7.0), "color": Color(2.6, 1.4, 0.6), "aabb": AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))})
	_sparks.position = Vector3(0, -radius * 0.8, 0)
	_star.add_child(_sparks)
	var trail: GPUParticles3D = Fx.trail({"amount": 30, "lifetime": 0.25, "size": radius * 0.5, "curve": "shrink",
		"color": Color(1.6, 0.6, 0.35, 0.35), "fade": PackedFloat32Array([0.7, 0.0]),
		"aabb": AABB(Vector3(-len - 4.0, -3, -len - 4.0), Vector3(len * 2.0 + 8.0, 6, len * 2.0 + 8.0))})
	_star.add_child(trail)
	_whir = WorldAudio.loop("sakura_shuriken_whir", _star, -14.0, 18.0, 4.0, false)
