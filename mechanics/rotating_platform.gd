class_name RotatingPlatform
extends AnimatableBody3D
## Kinematic spinner driven by Game.course_time. Spins about its local Y axis
## (turntables, clock hands you ride). Child collision is built from `arms`:
## each arm is a box placed relative to the hub.

@export var period: float = 8.0
@export var phase: float = 0.0
## Each entry: {"pos": Vector3, "size": Vector3} in hub space.
@export var arms: Array[Dictionary] = []
@export var hub_radius: float = 1.2
@export var hub_height: float = 0.5
@export var style: String = "mover"

var _base_basis: Basis


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_base_basis = basis
	if hub_radius > 0.0:
		var cyl := CylinderShape3D.new()
		cyl.radius = hub_radius
		cyl.height = hub_height
		var cs := CollisionShape3D.new()
		cs.shape = cyl
		add_child(cs)
		add_child(Look.platform_round(hub_radius, hub_height, style))
		add_child(Look.cylinder(hub_radius * 0.35, 0.12, Look.flat(Look.c("metal"), 0.35, 0.8), Vector3(0, hub_height * 0.5 + 0.06, 0)))
	for arm: Dictionary in arms:
		var sz: Vector3 = arm["size"]
		var box := BoxShape3D.new()
		box.size = sz
		var acs := CollisionShape3D.new()
		acs.shape = box
		acs.position = arm["pos"]
		add_child(acs)
		var vis: MeshInstance3D = Look.platform_box(sz, style)
		vis.position = arm["pos"]
		add_child(vis)
	_apply(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	# a low turntable motor under the hub (only heard close up)
	var hum: AudioStreamPlayer3D = WorldAudio.loop("motor_hum", self, -20.0, 12.0, 3.0)
	if hum != null:
		hum.pitch_scale = 0.8


## restart_run() winds the clock back in place: take the new pose now, without a streak.
func snap_to_clock() -> void:
	_apply(Game.course_time)
	reset_physics_interpolation()


func angle_at(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * TAU


func _apply(time: float) -> void:
	basis = _base_basis * Basis(Vector3.UP, angle_at(time))


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)
