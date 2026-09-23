extends Node3D
## Coral Depths, visual only: a gentle current sway about the node's own origin
## (tentacles, kelp heads, sea fans). Put the pivot where the thing is anchored.

@export var amount: float = 0.1
@export var speed: float = 1.0
@export var offset: float = 0.0

var _base: Vector3


func _ready() -> void:
	_base = rotation


func _process(_dt: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001 * speed + offset
	rotation = _base + Vector3(sin(t) * amount, 0.0, cos(t * 0.83) * amount * 0.7)
