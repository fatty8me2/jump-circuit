extends Node3D
## Constant decorative rotation.
var period: float = 8.0
var axis: Vector3 = Vector3.UP

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _process(dt: float) -> void:
	if period != 0.0:
		rotate_object_local(axis, dt * TAU / period)
