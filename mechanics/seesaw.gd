class_name Seesaw
extends TiltPlatform
## Seesaw (kit obstacle): a long plank on a centre pivot that tips under the rider's weight. It
## is a TiltPlatform (same Jolt-driven spring/damper and kinematic top surface), tuned for a
## lively plank: stand on an end and that end sinks, walk to the middle to level it, walk on to
## the far end and it tips the other way. `bias_deg` adds a counterweight: with 0 the plank rests
## level; with 12 it rests tipped 12 degrees (read the sign off axis_degrees()).
## Size is (length, thickness, width) with the plank running along X when `along_x`, otherwise
## along Z (then `size` is still given as length/thickness/width and is swapped for you).
## `top` is the centre of the plank's top surface when level.

@export var bias_deg: float = 0.0
@export var along_x: bool = true

var _last_end: int = 0
var _hit_mat: StandardMaterial3D


func _ready() -> void:
	if not along_x:
		size = Vector3(size.z, size.y, size.x)
		tilt_about_x = true
		tilt_about_z = false
	else:
		tilt_about_x = false
		tilt_about_z = true
	support = "fulcrum"
	super._ready()
	_build_extras()


func _build_extras() -> void:
	# end caps that glow with how far the plank has tipped
	_hit_mat = Look.flat(Look.c("accent"), 0.4, 0.2, 0.5).duplicate() as StandardMaterial3D
	var half: float = (size.x if along_x else size.z) * 0.5
	for sgn: float in [-1.0, 1.0]:
		var cap: MeshInstance3D
		if along_x:
			cap = Look.box(Vector3(0.5, 0.2, size.z * 0.9), _hit_mat)
			cap.position = Vector3(sgn * (half - 0.35), size.y * 0.5 + 0.02, 0)
		else:
			cap = Look.box(Vector3(size.x * 0.9, 0.2, 0.5), _hit_mat)
			cap.position = Vector3(0, size.y * 0.5 + 0.02, sgn * (half - 0.35))
		_surface.add_child(cap)


## The plank's signed tilt about its axis in degrees (0 level).
func axis_degrees() -> float:
	var d: Vector2 = tilt_degrees()
	return d.y if along_x else d.x


## True when the plank is within `tol` degrees of level.
func is_level(tol: float = 4.0) -> bool:
	return absf(axis_degrees()) <= tol


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if bias_deg != 0.0:
		var b: float = deg_to_rad(bias_deg)
		if along_x:
			_sim.apply_torque(Vector3(0, 0, _k.z * b))
		else:
			_sim.apply_torque(Vector3(_k.x * b, 0, 0))


func _process(dt: float) -> void:
	super._process(dt)
	var a: float = axis_degrees()
	var end: int = 0
	if a > max_tilt_deg - 2.0:
		end = 1
	elif a < -max_tilt_deg + 2.0:
		end = -1
	if end != 0 and end != _last_end:
		WorldAudio.at(self, "kit_seesaw_thunk", global_position, 0.7, 35.0)
	_last_end = end
	if _hit_mat != null:
		KitUtil.glow(_hit_mat, 0.5 + clampf(absf(a) / maxf(max_tilt_deg, 1.0), 0.0, 1.0) * 1.5)
