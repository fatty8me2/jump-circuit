class_name FungalSway
extends Node3D
## Mushroom Hollow, visual only: little life in the scenery. `mode`:
##   "sway"  - the node rocks gently about its own origin (grass, flower heads, ferns, hanging leaves);
##   "bob"   - it bobs up and down (lily pads, hovering beetles);
##   "flap"  - a butterfly: wings (children named "Wing*") beat and the body circles `radius` m.
## Put the pivot where the thing is anchored. Never collides.

@export var mode: String = "sway"
@export var amount: float = 0.08
@export var speed: float = 1.0
@export var offset: float = 0.0
@export var radius: float = 2.0

var _base: Vector3
var _base_pos: Vector3
var _wings: Array[Node3D] = []


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_base = rotation
	_base_pos = position
	for c: Node in get_children():
		if String(c.name).begins_with("Wing") and c is Node3D:
			_wings.append(c as Node3D)


func _process(_dt: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001 * speed + offset
	match mode:
		"sway":
			rotation = _base + Vector3(sin(t) * amount, 0.0, cos(t * 0.83) * amount * 0.7)
		"bob":
			position = _base_pos + Vector3(0.0, sin(t) * amount, 0.0)
		"flap":
			var a: float = t * 0.6
			position = _base_pos + Vector3(cos(a) * radius, sin(t * 1.3) * 0.6, sin(a) * radius)
			rotation.y = _base.y - a - PI * 0.5
			var f: float = sin(t * 22.0) * 0.9
			for i: int in _wings.size():
				_wings[i].rotation.z = f if i % 2 == 0 else -f
