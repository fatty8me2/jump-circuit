class_name ArmadaMast
extends AnimatableBody3D
## Storm Armada: the toppling mast. A ship's topmast on a hinge at its foot, winched upright and let
## go on the course clock: it stands, creaks, topples over the gap and crashes down across it as a
## bridge to the next ship, lies there, then the winch hauls it back up. Its top is a plank catwalk,
## so while it lies across the gap you can run over it. Pure function of Game.course_time.
## Positioned at the hinge: the catwalk's top edge at the foot of the mast. Lying flat, the catwalk
## runs from the hinge along local -Z for `length` metres, its top at the hinge's height.
##   cycle (s): stand (upright) .. fall (drops, accelerating) .. lie (a bridge) .. raise (winched up)

@export var length: float = 14.0
@export var width: float = 1.6
@export var thick: float = 0.5
@export var stand: float = 1.6
@export var fall: float = 1.1
@export var lie: float = 5.2
@export var raise_time: float = 2.6
@export var phase: float = 0.0

var _base_basis: Basis
var _origin: Vector3
var _landed: int = -999999
var _dust: GPUParticles3D
var _splinters: GPUParticles3D
var _chain: MeshInstance3D
var _derrick_top: Vector3
var _winch: AudioStreamPlayer3D
var _creaked: int = -999999


func period() -> float:
	return stand + fall + lie + raise_time


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	_base_basis = basis
	var box := BoxShape3D.new()
	box.size = Vector3(width, thick, length)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, -thick * 0.5, -length * 0.5)
	add_child(cs)
	_build()
	_pose(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	_winch = WorldAudio.loop("armada_winch_loop", self, -10.0, 26.0, 5.0, false)


func _u(time: float) -> float:
	return fposmod(time / period() + phase, 1.0) * period()


## Mast angle above the horizontal (radians): PI/2 upright, 0 lying across the gap.
func angle_at(time: float) -> float:
	var s: float = _u(time)
	if s < stand:
		return PI * 0.5
	s -= stand
	if s < fall:
		var k: float = s / fall
		return PI * 0.5 * (1.0 - k * k)
	s -= fall
	if s < lie:
		return 0.0
	s -= lie
	var r: float = clampf(s / raise_time, 0.0, 1.0)
	return PI * 0.5 * r * r * (3.0 - 2.0 * r)


## The mast lies flat across the gap for the whole window [time + a, time + b].
func is_down_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if angle_at(time + s) > 0.001:
			return false
		s += 0.05
	return true


## Seconds until it next lands (0 while lying down).
func time_until_down(time: float) -> float:
	var s: float = _u(time)
	var land: float = stand + fall
	if s >= land and s < land + lie:
		return 0.0
	return fposmod(land - s, period())


func snap_to_clock() -> void:
	_pose(Game.course_time)
	reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	_pose(Game.course_time)


func _pose(t: float) -> void:
	basis = _base_basis * Basis(Vector3.RIGHT, angle_at(t))


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var s: float = _u(t)
	var cycle: int = int(floor(t / period() + phase))
	if s >= stand + fall and s < stand + fall + 0.3 and _landed != cycle:
		_landed = cycle
		_dust.restart()
		_dust.emitting = true
		_splinters.restart()
		_splinters.emitting = true
		WorldAudio.at(self, "armada_mast_crash", _tip_world(0.0), 1.0, 60.0)
	if s >= stand - 0.5 and s < stand and _creaked != cycle:
		_creaked = cycle
		WorldAudio.at(self, "armada_mast_creak", global_position + Vector3(0, length * 0.6, 0), 0.9, 50.0)
	WorldAudio.set_active(_winch, s >= stand + fall + lie)
	# the hauling chain from the derrick head to the masthead
	var tip: Vector3 = _tip_world(angle_at(t))
	var d: Vector3 = tip - _derrick_top
	var up: Vector3 = d.normalized()
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9)).normalized()
	_chain.global_transform = Transform3D(Basis(side, up * d.length(), side.cross(up)), (_derrick_top + tip) * 0.5)


func _tip_world(angle: float) -> Vector3:
	var local := Basis(Vector3.RIGHT, angle) * Vector3(width * 0.5 + 0.15, -thick * 0.5, -length * 0.8)
	return get_parent().global_transform * (_origin + _base_basis * local) if get_parent() is Node3D else _origin + _base_basis * local


func _build() -> void:
	var wood: StandardMaterial3D = Look.flat(Color(0.42, 0.27, 0.15), 0.8)
	var dark: StandardMaterial3D = Look.flat(Color(0.25, 0.16, 0.09), 0.85)
	var brass: StandardMaterial3D = Look.flat(Color(0.86, 0.63, 0.3), 0.3, 0.9)
	var iron: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.22), 0.45, 0.8)
	# the catwalk planks on top (walkable), the round spar under them, iron hoops
	var walk := Look.platform_box(Vector3(width, thick * 0.5, length), "alt")
	walk.position = Vector3(0, -thick * 0.25, -length * 0.5)
	add_child(walk)
	var spar := Look.cylinder(width * 0.42, length, wood, Vector3(0, -thick * 0.5 - width * 0.2, -length * 0.5), width * 0.3, 12)
	spar.rotation.x = PI * 0.5
	add_child(spar)
	var k: int = int(length / 2.5)
	for i: int in k:
		var hoop := Look.cylinder(width * 0.45, 0.14, iron, Vector3(0, -thick * 0.5 - width * 0.2, -1.2 - float(i) * 2.5), -1.0, 12)
		hoop.rotation.x = PI * 0.5
		add_child(hoop)
	# a furled yard across it (below the catwalk, so it never trips a runner) and the masthead flag
	add_child(Look.box(Vector3(width * 3.2, 0.22, 0.22), dark, Vector3(0, -thick - 0.35, -length * 0.62)))
	add_child(Look.cylinder(0.26, 0.4, brass, Vector3(0, -thick * 0.5 - width * 0.2, -length + 0.2), -1.0, 12))
	# the hinge: a brass trunnion at the foot
	var hinge := Look.cylinder(0.32, width + 0.5, brass, Vector3(0, -thick * 0.5, 0), -1.0, 14)
	hinge.rotation.z = PI * 0.5
	add_child(hinge)
	# derrick post behind the hinge (static decor on the parent) with its chain to the masthead
	var derrick := Node3D.new()
	derrick.top_level = true
	add_child(derrick)
	var foot: Vector3 = get_parent().global_transform * (_origin + _base_basis * Vector3(width * 0.5 + 0.6, 0, 1.4)) if get_parent() is Node3D else _origin
	var h: float = length * 0.75
	derrick.global_position = foot
	derrick.add_child(Look.box(Vector3(0.5, h, 0.5), dark, Vector3(0, h * 0.5, 0)))
	derrick.add_child(Look.box(Vector3(0.9, 0.3, 0.9), brass, Vector3(0, h, 0)))
	_derrick_top = foot + Vector3(0, h, 0)
	_chain = Look.cylinder(0.06, 1.0, iron, Vector3.ZERO, -1.0, 6)
	_chain.top_level = true
	add_child(_chain)
	var vis := AABB(Vector3(-6, -3, -length - 6), Vector3(12, 10, length + 12))
	_dust = Fx.smoke({"amount": 30, "lifetime": 1.4, "shape": "box", "extents": Vector3(width, 0.2, length * 0.45),
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(1.0, 4.0), "size": 1.3, "color": Color(0.7, 0.66, 0.6, 0.55), "aabb": vis})
	_dust.position = Vector3(0, 0.2, -length * 0.5)
	add_child(_dust)
	_splinters = Fx.debris({"amount": 24, "shape": "box", "extents": Vector3(width, 0.2, length * 0.4), "dir": Vector3.UP,
		"spread": 60.0, "speed": Vector2(3.0, 8.0), "color": Color(0.5, 0.33, 0.18), "aabb": vis})
	_splinters.position = Vector3(0, 0.2, -length * 0.55)
	add_child(_splinters)
