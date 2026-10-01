extends Node3D
## Neon City, visual only: an aircraft-warning lamp (or any small light mesh) that blinks on a slow
## rhythm - visible for `on` of every `period` seconds.

var period: float = 1.6
var on: float = 0.25

var _seed: float = 0.0


func _ready() -> void:
	_seed = randf() * period


func _process(_dt: float) -> void:
	visible = fposmod(Time.get_ticks_msec() * 0.001 + _seed, period) < period * on
