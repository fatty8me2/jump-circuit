extends Node3D
## Storm Armada: a far-off airship (decor) steaming slowly along its heading (local -Z), gently
## bobbing and rolling in the storm. Wraps back after `range` metres so the fleet never thins out.

var speed: float = 1.5
var bob: float = 0.6
var range_m: float = 600.0

var _start: Vector3
var _base: Basis
var _t0: float


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_start = position
	_base = basis
	_t0 = fposmod(position.x * 0.13 + position.z * 0.07, 50.0)


func _process(_dt: float) -> void:
	var t: float = Game.course_time + _t0
	var fwd: Vector3 = -_base.z
	var s: float = fposmod(t * speed + range_m * 0.5, range_m) - range_m * 0.5
	position = _start + fwd * s + Vector3(0, sin(t * 0.5) * bob, 0)
	basis = _base * Basis.from_euler(Vector3(sin(t * 0.37) * 0.02, 0.0, sin(t * 0.43 + 1.0) * 0.035))
