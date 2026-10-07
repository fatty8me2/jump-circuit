class_name HatsExt
extends RefCounted
## Hats added in the v2.0 update (world Silver hats for the new courses and the extra Gold /
## stat hats). CosmeticArt.hat() falls through to build() for any id it doesn't know, so new
## hats live here and never touch the original match block. Build parts into `h` with the
## CosmeticArt helpers (part / pivot / std / sphere / cyl / box / torus / brim / shader); `sway`,
## `spin` and `bob` metas animate exactly as they do there.

## Hats that leave the crown open (the antenna / crown spike stays visible), like
## CosmeticArt.OPEN_HATS.
const OPEN_HATS: Array[String] = []


static func build(id: String, h: Node3D, v: PlayerVisual) -> void:
	match id:
		_:
			pass
