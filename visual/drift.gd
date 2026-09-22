extends Node3D
## Slow cloud drift with wrap-around.
var speed: float = 0.5
var _x0: float

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_x0 = position.x

func _process(dt: float) -> void:
	position.x += speed * dt
	if position.x > _x0 + 160.0:
		position.x -= 320.0
