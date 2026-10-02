extends Node3D
## The Abyss decoration: a slow bob and sway (drifting jellyfish, swaying kelp, hanging wreckage).
## Purely visual; never touches anything that collides.
var bob: float = 0.4
var sway_deg: float = 0.0
var period: float = 5.0
var drift: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _p0: Vector3
var _r0: Vector3


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_p0 = position
	_r0 = rotation
	_t = randf() * period


func _process(dt: float) -> void:
	_t += dt
	var k: float = sin(_t * TAU / maxf(period, 0.1))
	position = _p0 + Vector3(0, bob * k, 0) + drift * sin(_t * TAU / maxf(period * 2.7, 0.1))
	if sway_deg != 0.0:
		rotation = _r0 + Vector3(deg_to_rad(sway_deg) * k, 0, deg_to_rad(sway_deg) * 0.6 * cos(_t * TAU / maxf(period * 1.3, 0.1)))
