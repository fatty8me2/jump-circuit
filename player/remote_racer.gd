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
## Teleport sequence of the last packet (a change means the racer respawned).
var _seq: int = -1
var racer_name: String = ""
var _shadow: Decal


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_visual = PlayerVisual.new()
	add_child(_visual)
	_shadow = BlobShadow.make()
	add_child(_shadow)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 34
	_label.outline_size = 10
	_label.position = Vector3(0, 1.75, 0)
	add_child(_label)


func setup(p_name: String, color: Color) -> void:
	racer_name = p_name
	_visual.set_accent(color)
	_label.text = p_name
	_label.modulate = color.lerp(Color.WHITE, 0.4)


# ---- Party Mode accessors (read-only views; party attachments hang off visual()) -------

## The Volt model (party costumes and status effects are added as its children).
func visual() -> PlayerVisual:
	return _visual


## Last reported velocity / grounded flag (hit checks: "from behind", "in the air").
func velocity() -> Vector3:
	return _vel


func is_grounded() -> bool:
	return _grounded


## Team Party: the name tag shows the team colour and name.
func set_team(team_name: String, color: Color) -> void:
	_label.text = "%s  [%s]" % [racer_name, team_name]
	_label.modulate = color.lerp(Color.WHITE, 0.25)
	_visual.set_accent(color)


## Cosmetic flinch the moment a local attack connects (the real knockback arrives with
## the victim's next poses).
func flinch() -> void:
	_visual.on_bounce(12.0)


func push_state(pos: Vector3, vel: Vector3, grounded: bool, seq: int) -> void:
	if not _has_state or seq != _seq or pos.distance_to(global_position) > 12.0:
		# first packet, a respawn / teleport, or a long packet gap: snap, don't slide
		if _has_state and seq != _seq:
			_visual.on_respawn()     # drop the death-pose lean, same arrival glow as ours
		global_position = pos
		var flat := Vector3(vel.x, 0, vel.z)
		if flat.length() > 0.5:
			_facing = flat.normalized()
		_visual.snap_facing(_facing)
	elif grounded and not _grounded:
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
	_seq = seq


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
	BlobShadow.fit(_shadow, get_world_3d().direct_space_state, global_position, 1 | 8)
