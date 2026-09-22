class_name RemoteRacer
extends Node3D
## Another player in a race: the same Volt model, tinted, with a name tag.
## Pose snapshots arrive ~30 Hz; we extrapolate briefly along the reported
## velocity and ease toward it so motion stays smooth under jitter.
## No collider - racers never block each other.

var _visual: PlayerVisual
var _label: Label3D
var _pos: Vector3
var _vel: Vector3
var _grounded: bool = true
var _age: float = 0.0
var _has_state: bool = false
var _facing: Vector3 = Vector3.FORWARD


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_visual = PlayerVisual.new()
	add_child(_visual)
	add_child(BlobShadow.make())
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 34
	_label.outline_size = 10
	_label.position = Vector3(0, 1.75, 0)
	add_child(_label)


func setup(racer_name: String, color: Color) -> void:
	_visual.set_accent(color)
	_label.text = racer_name
	_label.modulate = color.lerp(Color.WHITE, 0.4)


func push_state(pos: Vector3, vel: Vector3, grounded: bool) -> void:
	if not _has_state or pos.distance_to(global_position) > 12.0:
		global_position = pos      # first packet or a respawn: snap
	if grounded and not _grounded:
		_visual.on_land(absf(_vel.y))
	elif not grounded and _grounded and vel.y > 6.0:
		if vel.y > 14.0:
			_visual.on_bounce(vel.length())
		else:
			_visual.on_jump()
	_pos = pos
	_vel = vel
	_grounded = grounded
	_age = 0.0
	_has_state = true


func _process(dt: float) -> void:
	if not _has_state:
		return
	_age += dt
	var predicted: Vector3 = _pos + _vel * minf(_age, 0.2)
	global_position = global_position.lerp(predicted, 1.0 - exp(-16.0 * dt))
	var flat := Vector3(_vel.x, 0, _vel.z)
	if flat.length() > 0.5:
		_facing = flat.normalized()
	_visual.animate(dt, _vel, _grounded, _facing)
