class_name FungalTongue
extends Node3D
## Mushroom Hollow: the stretching tongue of a frog (visual only). It joins a fixed `mouth` point to the
## rear of a Piston's ram: a long pink cylinder re-aimed and re-sized every frame, so the tongue
## stays attached to the frog's mouth however far the ram has punched out. The ram itself is the
## sticky tip of the tongue (the Piston's own collision does the shoving; this is only the look).

var piston: Piston
## World position of the frog's mouth.
var mouth: Vector3 = Vector3.ZERO
@export var thickness: float = 0.22

var _tongue: MeshInstance3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mat: StandardMaterial3D = Look.flat(Color(0.95, 0.45, 0.55), 0.35)
	_tongue = Look.cylinder(thickness, 1.0, mat, Vector3.ZERO, thickness * 0.85, 10)
	add_child(_tongue)
	global_transform = Transform3D.IDENTITY


func _process(_dt: float) -> void:
	if piston == null or not is_instance_valid(piston):
		return
	var rear: Vector3 = piston.global_position + piston.global_basis * Vector3(0, 0, piston.size.z * 0.5)
	var d: Vector3 = rear - mouth
	var l: float = d.length()
	if l < 0.05:
		_tongue.visible = false
		return
	_tongue.visible = true
	var up: Vector3 = d / l
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9))
	var sl: float = side.length()
	side = side / sl if sl > 0.0001 else Vector3.RIGHT
	_tongue.global_transform = Transform3D(Basis(side, up * l, side.cross(up)), (mouth + rear) * 0.5)
