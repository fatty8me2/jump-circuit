class_name PartyItems
extends RefCounted
## The item catalogue: which power-ups exist, how often each rolls, and the script behind it.
## Rolls are weighted by race position: `place_frac` 0.0 = leading, 1.0 = last. The leader
## mostly gets small / defensive things, the back of the pack gets the wild transformations.
## Display names live in PartyNames.

## id -> [weight when leading, weight when last]. Weights blend linearly in between.
const WEIGHTS: Dictionary = {
	"balloon": [5.0, 1.0],
	"slick": [5.0, 1.5],
	"glove": [4.0, 2.0],
	"jetpack": [3.0, 2.0],
	"ice": [2.0, 2.5],
	"gravity": [2.0, 2.5],
	"magnet": [1.5, 2.5],
	"shrink": [1.2, 2.5],
	"tornado": [1.0, 2.5],
	"thunder": [0.0, 3.0],
	"swap": [0.0, 3.0],
	"fox": [0.3, 3.5],
	"tunic": [0.3, 3.5],
	"surge": [0.3, 3.5],
}

## Order Party Practice hands items out in (every box gives the next one), transformations first.
const PRACTICE_ORDER: Array[String] = ["fox", "tunic", "surge", "thunder", "slick", "glove", "magnet",
	"shrink", "swap", "balloon", "jetpack", "tornado", "gravity", "ice"]

## Transformations take over the Attack button and run on a HUD timer.
const TRANSFORMATIONS: Array[String] = ["fox", "tunic", "surge"]

const SCRIPTS: Dictionary = {
	"fox": preload("res://party/powerups/fox.gd"),
	"tunic": preload("res://party/powerups/tunic.gd"),
	"surge": preload("res://party/powerups/surge.gd"),
	"thunder": preload("res://party/powerups/thunder.gd"),
	"slick": preload("res://party/powerups/slick.gd"),
	"glove": preload("res://party/powerups/glove.gd"),
	"magnet": preload("res://party/powerups/magnet.gd"),
	"shrink": preload("res://party/powerups/shrink.gd"),
	"swap": preload("res://party/powerups/swap.gd"),
	"balloon": preload("res://party/powerups/balloon.gd"),
	"jetpack": preload("res://party/powerups/jetpack.gd"),
	"tornado": preload("res://party/powerups/tornado.gd"),
	"gravity": preload("res://party/powerups/gravity_bomb.gd"),
	"ice": preload("res://party/powerups/ice.gd"),
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in PRACTICE_ORDER:
		out.append(id)
	return out


static func weight(id: String, place_frac: float) -> float:
	var w: Array = WEIGHTS.get(id, [0.0, 0.0])
	return lerpf(float(w[0]), float(w[1]), clampf(place_frac, 0.0, 1.0))


## Deterministic weighted pick: `r` in [0, 1) (the caller owns the randomness).
static func roll(place_frac: float, r: float) -> String:
	var total: float = 0.0
	for id: String in PRACTICE_ORDER:
		total += weight(id, place_frac)
	var x: float = clampf(r, 0.0, 0.999999) * total
	for id: String in PRACTICE_ORDER:
		x -= weight(id, place_frac)
		if x < 0.0:
			return id
	return PRACTICE_ORDER[PRACTICE_ORDER.size() - 1]


## Race position -> place_frac: 0 for the leader, 1 for the last of `count` racers.
static func place_fraction(place: int, count: int) -> float:
	if count <= 1:
		return 0.5
	return clampf(float(place - 1) / float(count - 1), 0.0, 1.0)


static func is_transformation(id: String) -> bool:
	return TRANSFORMATIONS.has(id)


static func script_for(id: String) -> GDScript:
	return SCRIPTS.get(id, null) as GDScript


static var _remote_fx_cache: Dictionary = {}


## Does the item script define a static `remote_fx` (replays its effects with no mirror)?
static func has_remote_fx(id: String) -> bool:
	if not _remote_fx_cache.has(id):
		var found: bool = false
		var scr: GDScript = script_for(id)
		if scr != null:
			for m: Dictionary in scr.get_script_method_list():
				if str(m.get("name", "")) == "remote_fx":
					found = true
					break
		_remote_fx_cache[id] = found
	return bool(_remote_fx_cache[id])
