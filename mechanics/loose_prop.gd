extends RigidBody3D
## Shovable rigid prop that returns home on respawn or if it falls away.
var _home: Transform3D

func _ready() -> void:
	_home = global_transform

func reset_state() -> void:
	# move the node too (not just the body) so the interpolation reset below
	# captures the home pose instead of drawing a one-frame streak back home
	global_transform = _home
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _home)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()

func _physics_process(_dt: float) -> void:
	if global_position.y < _home.origin.y - 40.0:
		reset_state()
