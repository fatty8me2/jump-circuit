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
	"jetpack": [0.0, 2.0],   # never for the leader: a free skip is the last thing they need
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
	# the second wave: catch-up tools for the back of the pack...
	"homing": [0.0, 3.0],    # needs somebody ahead to chase
	"strike": [0.0, 3.0],    # hits whoever is in front
	"turbo": [0.0, 3.5],     # a burst of speed: the leader does not need one
	# ...a little for the middle...
	"ghost": [0.6, 2.5],
	# ...and tools for the racer in front to defend their place
	"fakebox": [3.0, 1.0],
	"decoy": [3.0, 1.0],
	"shock": [3.0, 1.0],
}

## Items only worth having when somebody is ahead of you (or you are behind): the leader never rolls them.
const CATCH_UP: Array[String] = ["thunder", "swap", "jetpack", "homing", "strike", "turbo"]
## Items that protect a lead: they weigh most for the racer in front and least at the back.
const LEADER_SAFE: Array[String] = ["balloon", "slick", "fakebox", "decoy", "shock"]

## Order Party Practice hands items out in (every box gives the next one), transformations first.
const PRACTICE_ORDER: Array[String] = ["fox", "tunic", "surge", "thunder", "slick", "glove", "magnet",
	"shrink", "swap", "balloon", "jetpack", "tornado", "gravity", "ice",
	"homing", "strike", "fakebox", "turbo", "ghost", "decoy", "shock"]

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
	"homing": preload("res://party/powerups/homing.gd"),
	"strike": preload("res://party/powerups/strike.gd"),
	"fakebox": preload("res://party/powerups/fakebox.gd"),
	"turbo": preload("res://party/powerups/turbo.gd"),
	"ghost": preload("res://party/powerups/ghost.gd"),
	"decoy": preload("res://party/powerups/decoy.gd"),
	"shock": preload("res://party/powerups/shock.gd"),
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
