class_name SakuraKoi
extends AnimatableBody3D
## Sakura Peaks: a KOI STEPPING STONE. A flat-topped river stone floating in the koi pond that
## bobs up and down on the course clock (a gentle, readable rhythm), with lily pads at its foot and
## ripples spreading round it every time it dips. A ride, never a hazard on its own - the pond is.
## A pure function of Game.course_time. Positioned at the centre of its TOP surface at the top of
## its bob; it dips `depth` below that.

@export var radius: float = 1.2
@export var depth: float = 0.6
@export var period: float = 3.0
@export var phase: float = 0.0
## How far the stone reaches down (into the water, for the look).
@export var column: float = 2.2

var _origin: Vector3
var _ripple: GPUParticles3D
var _dipped: int = -1


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.6
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.3, 0)
	add_child(cs)
	_build_visual()
	add_to_group("course_clock")
	position = _origin + Vector3(0, offset_at(Game.course_time), 0)
	reset_physics_interpolation()


## Height of the top relative to its highest point at `time` (0 .. -depth).
func offset_at(time: float) -> float:
	var u: float = fposmod(time / maxf(period, 0.01) + phase, 1.0)
	return -depth * (0.5 - 0.5 * cos(TAU * u))


func snap_to_clock() -> void:
	position = _origin + Vector3(0, offset_at(Game.course_time), 0)
	reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	position = _origin + Vector3(0, offset_at(Game.course_time), 0)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var cycle: int = int(floor(t / maxf(period, 0.01) + phase + 0.5))
	if cycle != _dipped:
		_dipped = cycle
		_ripple.restart()
		_ripple.emitting = true


func _build_visual() -> void:
	var stone: StandardMaterial3D = SakuraDecor.mat(Color(0.5, 0.49, 0.47), 0.9)
	var top := Look.cylinder(radius, 0.6, stone, Vector3(0, -0.3, 0), radius * 0.96, 10)
	add_child(top)
	add_child(Look.cylinder(radius * 0.96, column, SakuraDecor.mat(Color(0.36, 0.36, 0.34), 0.95), Vector3(0, -0.6 - column * 0.5, 0), radius * 0.7, 10))
	add_child(Look.cylinder(radius * 0.7, 0.04, SakuraDecor.mat(SakuraDecor.MOSS, 0.95), Vector3(radius * 0.15, 0.01, radius * 0.1), radius * 0.55, 10))
	# lily pads at its foot
	var pad: StandardMaterial3D = SakuraDecor.mat(Color(0.26, 0.46, 0.22), 0.8)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0 + 0.4
		var lp := Look.cylinder(0.32, 0.03, pad, Vector3(cos(a) * (radius + 0.35), -0.62, sin(a) * (radius + 0.35)), -1.0, 10)
		add_child(lp)
	add_child(Look.sphere(0.12, SakuraDecor.blossom(Color(1.0, 0.82, 0.9)), Vector3(cos(0.4) * (radius + 0.35), -0.55, sin(0.4) * (radius + 0.35))))
	# a ring of ripples each time it dips into the water
	_ripple = Fx.shockwave(radius + 1.4, {"lifetime": 1.2, "color": Color(1.2, 1.3, 1.4, 0.45),
		"aabb": AABB(Vector3(-4, -2, -4), Vector3(8, 4, 8))})
	_ripple.position = Vector3(0, -0.6, 0)
	add_child(_ripple)
