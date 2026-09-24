extends RigidBody3D
## Shovable rigid prop that returns home on respawn or if it falls away.
var _home: Transform3D
# sound (side effect only): a bonk when its velocity changes sharply (a bounce, a kick)
var _audio: bool = false
var _prev_v: Vector3 = Vector3.ZERO
var _bonk_cool: float = 0.0

func _ready() -> void:
	_home = global_transform
	_audio = WorldAudio.enabled()

func reset_state() -> void:
	# move the node too (not just the body) so the interpolation reset below
	# captures the home pose instead of drawing a one-frame streak back home
	global_transform = _home
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _home)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
	_prev_v = Vector3.ZERO
	_bonk_cool = 0.3

func _physics_process(dt: float) -> void:
	if global_position.y < _home.origin.y - 40.0:
		reset_state()
	if _audio:
		_bonk(dt)

## Reads the body's velocity only (after the step) - never touches the simulation.
func _bonk(dt: float) -> void:
	var v: Vector3 = linear_velocity
	var dv: float = (v - _prev_v - get_gravity() * dt).length()
	_prev_v = v
	_bonk_cool = maxf(_bonk_cool - dt, 0.0)
	if dv > 3.0 and _bonk_cool <= 0.0:
		_bonk_cool = 0.18
		WorldAudio.at(self, "prop_bonk", global_position, clampf(dv / 12.0, 0.2, 1.0), 30.0, 0.08)
