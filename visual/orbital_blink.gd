extends MeshInstance3D
## Orbital Drift nav light: a short flash every `period` seconds (course clock, so
## every beacon on the station keeps its own steady rhythm).

@export var period: float = 1.5
@export var on_time: float = 0.18
@export var offset: float = 0.0


func _process(_dt: float) -> void:
	visible = fposmod(Game.course_time + offset, period) < on_time or period <= 0.0
