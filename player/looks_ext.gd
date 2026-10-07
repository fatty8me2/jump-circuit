class_name LooksExt
extends RefCounted
## Paints, trails and finish celebrations added in the v2.0 update. The original dispatchers
## (CosmeticArt.paint_material, PlayerVisual.trail_layers, PlayerVisual.play_finish) fall
## through to these for any id they don't know, so new items never touch their match blocks.


## The paint's material for the body shell, or null (falls back to the factory finish).
static func paint_material(id: String) -> Material:
	match id:
		_:
			return null


## Trail emitter layers (same dictionary format as PlayerVisual.trail_layers).
static func trail_layers(id: String, tint: Color) -> Array[Dictionary]:
	match id:
		_:
			return []


## Finish celebration `id` at `at` for visual `v` (the "fin_<id>" sound is played by the caller).
## Every emitter must be a self-freeing Fx.spawn scaled by the Particles slider.
static func play_finish(v: PlayerVisual, id: String, at: Vector3) -> void:
	match id:
		_:
			pass
