class_name TempestLoad
extends MovingPlatform
## Tempest Tower: a CRANE LOAD - a steel girder slung from a crane trolley, carried back and forth
## across a gap on the course clock. Ride it: it holds still at each end while the crew hooks the
## next lift (its amber beacon blinks and the hook bell rings `warn` seconds before it moves off),
## then the trolley runs it across. The girder hangs level from a spreader bar on two slings;
## cables run up out of sight to the trolley. Pure function of the clock (a MovingPlatform PATH with
## long dwells), so the bot can ask where it will be.

## How far above the girder the trolley runs (the cables reach up this far).
@export var cable_len: float = 10.0
## Seconds before each departure that the beacon blinks and the bell rings.
@export var warn: float = 1.0

var _beacon_mat: StandardMaterial3D
var _was_warn: bool = false
var _loop: AudioStreamPlayer3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	_build()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	# SOUND: the trolley's winch whining while the load travels
	_loop = WorldAudio.loop("tempest_trolley", self, -18.0, 22.0, 4.0, false)


func _hums() -> bool:
	return false


## Seconds of the current hold left at an end (0 while travelling).
func hold_left(time: float) -> float:
	var s: float = 0.0
	while s < period:
		if offset_at(time + s).distance_to(offset_at(time)) > 0.02:
			return s
		s += 0.05
	return period


func is_travelling_at(time: float) -> bool:
	return offset_at(time + 0.05).distance_to(offset_at(time)) > 0.001


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var moving: bool = is_travelling_at(t)
	var left: float = 0.0 if moving else hold_left(t)
	var warning: bool = not moving and left < warn
	_beacon_mat.emission_energy_multiplier = (4.0 if fmod(t, 0.24) < 0.12 else 0.3) if warning else (1.6 if moving else 0.25)
	if warning and not _was_warn:
		# SOUND: the hook bell before the load moves off (the tell)
		WorldAudio.at(self, "tempest_load_bell", global_position + Vector3(0, 2.0, 0), 0.8, 30.0)
	_was_warn = warning
	if _loop != null:
		WorldAudio.set_active(_loop, moving)


func _build() -> void:
	var steel: StandardMaterial3D = Look.flat(Color(0.86, 0.42, 0.12), 0.55, 0.5)
	var dark: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.15), 0.5, 0.7)
	var cable: StandardMaterial3D = Look.flat(Color(0.1, 0.1, 0.11), 0.4, 0.8)
	# the girder: its top flange is the walking surface (platform look), red-oxide web and lower flange
	add_child(Look.platform_box(size, "mover"))
	var web_h: float = 0.7
	add_child(Look.box(Vector3(size.x * 0.18, web_h, size.z), steel, Vector3(0, -size.y * 0.5 - web_h * 0.5, 0)))
	add_child(Look.box(Vector3(size.x * 0.9, 0.12, size.z), steel, Vector3(0, -size.y * 0.5 - web_h - 0.06, 0)))
	# the beacon on the girder's end (blinks before it moves)
	_beacon_mat = Look.flat(Color(1.0, 0.62, 0.12), 0.3, 0.0, 0.3).duplicate() as StandardMaterial3D
	for sz: float in [-1.0, 1.0]:
		add_child(Look.sphere(0.12, _beacon_mat, Vector3(size.x * 0.5 - 0.15, -size.y * 0.5 - 0.2, sz * (size.z * 0.5 - 0.15))))
	# two slings from the girder's ends up to a spreader bar, a single fall of cable to the hook block
	var top_y: float = size.y * 0.5
	var bar_y: float = top_y + 3.2
	var long_axis: Vector3 = Vector3(0, 0, 1) if size.z >= size.x else Vector3(1, 0, 0)
	var half_len: float = maxf(size.x, size.z) * 0.5 - 0.3
	for s: float in [-1.0, 1.0]:
		var a: Vector3 = long_axis * s * half_len + Vector3(0, top_y, 0)
		var b: Vector3 = long_axis * s * 0.9 + Vector3(0, bar_y, 0)
		add_child(_rod(a, b, 0.03, cable))
	add_child(Look.box(long_axis * 2.0 + Vector3(0.18, 0.18, 0.18), dark, Vector3(0, bar_y, 0)))
	add_child(Look.box(Vector3(0.5, 0.7, 0.5), Look.flat(Color(0.95, 0.75, 0.1), 0.5, 0.3), Vector3(0, bar_y + 0.6, 0)))
	for s: float in [-0.12, 0.12]:
		var up := Look.cylinder(0.025, cable_len - 3.6, cable, Vector3(s, bar_y + 1.0 + (cable_len - 3.6) * 0.5, 0), -1.0, 5)
		add_child(up)
	# the trolley it hangs from (rides along with it under the jib)
	add_child(Look.box(Vector3(1.4, 0.6, 1.8), dark, Vector3(0, top_y + cable_len, 0)))


static func _rod(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var dir: Vector3 = b - a
	var n := Look.cylinder(r, dir.length(), mat, (a + b) * 0.5, -1.0, 5)
	var up: Vector3 = dir.normalized()
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9)).normalized()
	n.basis = Basis(side, up, side.cross(up))
	return n
