class_name GardensSails
extends Node3D
## Windmill sails of Launch Gardens, turned by the course clock so they stay locked to the
## orbiting seed trays hung on their tips (same axis, period and phase). Visual only.

## World-space axis the sails turn about (same as the trays' MovingPlatform.orbit_axis).
var axis: Vector3 = Vector3.LEFT
var period: float = 8.0
var phase: float = 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_apply()


func _apply() -> void:
	var u: float = fposmod(Game.course_time / maxf(period, 0.01) + phase, 1.0)
	basis = Basis(axis.normalized(), u * TAU)


func _process(_dt: float) -> void:
	_apply()
