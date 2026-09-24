class_name Sweeper
extends Node3D
## Rotating kill bars around a hub (the classic obby spinner). Angle is a pure
## function of Game.course_time. Low bars are jumped; `bar_count` sets how often
## one comes round.

@export var arm_length: float = 5.0
@export var bar_count: int = 2
@export var period: float = 4.0
@export var phase: float = 0.0
@export var bar_height: float = 0.45
@export var bar_thickness: float = 0.5

var _pivot: Node3D
var _tips: Array[Node3D] = []
var _swooshes: Array[Swoosh] = []


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	add_child(Look.cylinder(0.5, bar_height + 0.6, Look.flat(Color(0.14, 0.15, 0.2), 0.4, 0.7), Vector3(0, (bar_height + 0.6) * 0.5, 0), 0.4, 12))
	for i: int in bar_count:
		var holder := Node3D.new()
		holder.rotation.y = TAU * float(i) / float(bar_count)
		_pivot.add_child(holder)
		var kz := KillZone.new()
		kz.size = Vector3(arm_length, bar_thickness, bar_thickness)
		kz.position = Vector3(arm_length * 0.5 + 0.3, bar_height, 0)
		kz.embers = false        # the sweep trail below is its effect
		holder.add_child(kz)
		# a glowing wake swept out behind the bar (world-space dots left in its path)
		var wake: GPUParticles3D = Fx.trail({"amount": clampi(int(arm_length * 7.0), 14, 44), "lifetime": 0.32,
			"shape": "box", "extents": Vector3(arm_length * 0.5, bar_thickness * 0.3, bar_thickness * 0.3),
			"size": bar_thickness * 1.1, "color": Color(2.2, 0.55, 0.3, 0.6), "emitting": true,
			"fade": PackedFloat32Array([0.7, 0.0]),
			"aabb": AABB(Vector3(-arm_length - 2.0, -2.0, -arm_length - 2.0), Vector3(arm_length * 2.0 + 4.0, 4.0, arm_length * 2.0 + 4.0))})
		wake.position = kz.position
		holder.add_child(wake)
		# a hot ribbon traced by the bar's tip (the fastest, most dangerous point)
		var tip := Node3D.new()
		tip.position = Vector3(arm_length + 0.25, bar_height, 0)
		holder.add_child(tip)
		_tips.append(tip)
		var sw: Swoosh = Swoosh.make(Color(1.0, 0.2, 0.05, 0.9), bar_thickness * 0.6, 0.3, false)
		sw.spacing = 0.1
		add_child(sw)
		_swooshes.append(sw)
	_apply()
	add_to_group("course_clock")


## restart_run() winds the clock back in place: take the new pose now, without a streak.
func snap_to_clock() -> void:
	_apply()
	reset_physics_interpolation()
	for s: Swoosh in _swooshes:
		s.clear()


func _process(dt: float) -> void:
	for i: int in _tips.size():
		_swooshes[i].feed(_tips[i].global_position, true, dt)


func angle_at(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * TAU


func _apply() -> void:
	_pivot.rotation.y = angle_at(Game.course_time)


func _physics_process(_dt: float) -> void:
	_apply()
