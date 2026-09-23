class_name BalanceScanner
extends Node3D
## Balance Works' sweeping laser scanner: an always-on kill beam slung under a gantry
## carriage that runs back and forth along the yard (pure function of Game.course_time,
## pausing `dwell` at each end, like a MovingPlatform). The beam spans `width` across
## (local X, turned with the node) at `beam_height` above the node's floor point; you
## hop it, or chase it and leap it while it is parked at the far end.

@export var width: float = 2.6
@export var beam_height: float = 0.9
@export var points: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, -6)]
@export var period: float = 3.2
@export var phase: float = 0.0
@export var dwell: float = 0.15
## Carriage height above the floor point.
@export var rail_height: float = 4.2

var gate: LaserGate
var _origin: Vector3


func _ready() -> void:
	_origin = position
	gate = LaserGate.new()
	gate.size = Vector3(width, 0.22, 0.22)
	gate.period = 1.0
	gate.on_fraction = 1.0
	gate.position = Vector3(0, beam_height, 0)
	add_child(gate)
	var steel: StandardMaterial3D = Look.flat(Color(0.14, 0.15, 0.18), 0.5, 0.6)
	var red: StandardMaterial3D = Look.flat(Color(1.0, 0.22, 0.14), 0.3, 0.0, 3.0)
	var hx: float = width * 0.5 + 0.18
	# hangers from the emitter posts up to the carriage
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.12, rail_height - beam_height - 0.5, 0.12), steel, Vector3(sx * hx, (rail_height + beam_height + 0.5) * 0.5, 0)))
	add_child(Look.box(Vector3(width + 1.2, 0.45, 0.8), Look.flat(Color(0.92, 0.94, 0.92), 0.5, 0.3), Vector3(0, rail_height, 0)))
	add_child(Look.box(Vector3(width + 0.4, 0.12, 0.84), red, Vector3(0, rail_height - 0.2, 0)))
	# the scan fan: a faint red sheet from the carriage lamp down to the beam
	var fan_mat := StandardMaterial3D.new()
	fan_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fan_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fan_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fan_mat.albedo_color = Color(1.0, 0.25, 0.15, 0.09)
	var fan := Look.box(Vector3(width, rail_height - beam_height - 0.3, 0.02), fan_mat, Vector3(0, (rail_height + beam_height) * 0.5, 0))
	fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fan)
	# emitter sparks spitting off both posts
	for sx: float in [-1.0, 1.0]:
		var sp: GPUParticles3D = BalanceFx.sparks(Color(1.0, 0.35, 0.2), 10, 2.2, 0.5, Vector3(sx, 0.6, 0), 35.0)
		sp.position = Vector3(sx * hx, beam_height, 0)
		add_child(sp)
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func snap_to_clock() -> void:
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()


## Same ping-pong-with-dwell curve as MovingPlatform.PATH.
func offset_at(time: float) -> Vector3:
	var u: float = fposmod(time / maxf(period, 0.01) + phase, 1.0)
	if points.size() < 2:
		return Vector3.ZERO
	var legs: int = points.size() - 1
	var tri: float = 1.0 - absf(u * 2.0 - 1.0)
	var f: float = tri * float(legs)
	var leg: int = mini(int(f), legs - 1)
	var k: float = f - float(leg)
	k = clampf((k - dwell) / maxf(1.0 - 2.0 * dwell, 0.01), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return points[leg].lerp(points[leg + 1], k)


## World position of the beam's centre at `time`.
func beam_at(time: float) -> Vector3:
	var parent_xf: Transform3D = (get_parent() as Node3D).global_transform if get_parent() is Node3D else Transform3D.IDENTITY
	return parent_xf * (_origin + offset_at(time) + Vector3(0, beam_height, 0))


func _physics_process(_dt: float) -> void:
	position = _origin + offset_at(Game.course_time)
