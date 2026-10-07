class_name BodiesExt
extends RefCounted
## Characters added in the v2.0 update. PlayerVisual._build_body() calls build() for any id it
## doesn't know; return true when the id was built here. A body must provide every standard
## part the built-in bodies do (body, belt, pack, eyes, antenna / bulb, feet, hands, head anchor
## position via HEADS) - use v._stub(...) for parts it doesn't have. See _body_knight() etc. in
## player/player_visual.gd for the pattern.

## Hat mount per character: [crown position (feet-relative), hat scale], like PlayerVisual.HEADS.
const HEADS: Dictionary = {}


static func build(v: PlayerVisual, id: String) -> bool:
	match id:
		_:
			return false
