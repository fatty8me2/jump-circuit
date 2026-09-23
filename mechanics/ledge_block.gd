class_name LedgeBlock
extends StaticBody3D
## A block whose top edge can be grabbed. Jump at any side and, if the top is
## within mantle_reach of your feet, the player catches the lip and climbs on.
## Only ledge blocks allow it, so they wear a bright gold lip around the top
## and vertical grip rungs on every face. Too tall to jump onto (3-4.2 m above
## the approach) = a mantle wall; the top is ordinary walkable ground.

const LIP_COLOR: Color = Color(1.0, 0.82, 0.22)

@export var size: Vector3 = Vector3(4, 3.6, 4)
@export var style: String = "main"


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	add_child(Look.platform_box(size, style))
	var lip: StandardMaterial3D = Look.flat(LIP_COLOR, 0.35, 0.2, 1.6)
	var rung: StandardMaterial3D = Look.flat(LIP_COLOR.darkened(0.25), 0.5, 0.3, 0.5)
	var y_lip: float = size.y * 0.5 - 0.09
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.08, 0.16, size.z + 0.16), lip, Vector3(sx * (size.x * 0.5 + 0.04), y_lip, 0)))
	for sz: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(size.x + 0.16, 0.16, 0.08), lip, Vector3(0, y_lip, sz * (size.z * 0.5 + 0.04))))
	# grip rungs: short vertical bars under the lip, on every face
	var rung_h: float = minf(1.4, size.y * 0.5)
	var y_rung: float = size.y * 0.5 - 0.2 - rung_h * 0.5
	for face: int in 4:
		var along_x: bool = face < 2
		var span: float = size.x if along_x else size.z
		var n: int = maxi(int(span / 1.2), 1)
		for i: int in n:
			var u: float = -span * 0.5 + (float(i) + 0.5) * span / float(n)
			var s: float = -1.0 if face % 2 == 0 else 1.0
			var pos := Vector3(u, y_rung, s * (size.z * 0.5 + 0.03)) if along_x else Vector3(s * (size.x * 0.5 + 0.03), y_rung, u)
			add_child(Look.box(Vector3(0.1, rung_h, 0.06) if along_x else Vector3(0.06, rung_h, 0.1), rung, pos))


func is_ledge() -> bool:
	return true
