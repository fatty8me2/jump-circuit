extends OmniLight3D
## Scarab Sands, visual only: a torch or brazier light that flickers like a flame.

@export var base_energy: float = 1.6
@export var amount: float = 0.35

var _seed: float = 0.0


func _ready() -> void:
	_seed = randf() * 100.0


func _process(_dt: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001 + _seed
	var f: float = sin(t * 11.0) * 0.5 + sin(t * 17.3 + 1.3) * 0.3 + sin(t * 29.1 + 0.7) * 0.2
	light_energy = base_energy * (1.0 + amount * f * 0.5)
