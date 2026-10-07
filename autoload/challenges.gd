class_name Challenges
extends RefCounted
## Three challenges per course, generated from Game.LEVELS (so new courses are covered at once):
##   flawless  finish the course without a fall
##   silver    earn Silver or better
##   speed     finish under a target between Silver and Gold
## Everything is derived from the save's level records (best / legacy_best / fewest_falls), so
## old saves earn challenges retroactively. SaveData.data["challenges"] additionally remembers
## ("id:kind") what was ever done, so a layout rebuild never takes one away.

const KINDS: Array[String] = ["flawless", "silver", "speed"]
const GENERIC: Dictionary = {"flawless": "Flawless", "silver": "Silver Standard", "speed": "Speedrunner"}

## Hand-picked flavour names per course (any gap falls back to GENERIC).
const FLAVOUR: Dictionary = {
	"gardens": {"flawless": "Green Thumb", "speed": "Garden Dash"},
	"foundry": {"flawless": "Fireproof", "speed": "Hot Rod"},
	"balance": {"flawless": "Steady Hands", "speed": "Tightrope Sprint"},
	"clockwork": {"flawless": "Perfect Timing", "speed": "Ahead of the Clock"},
	"reef": {"flawless": "Never Surfaced", "speed": "Current Rider"},
	"orbital": {"flawless": "Zero-G Grace", "speed": "Escape Velocity"},
	"volcano": {"flawless": "Cool Under Fire", "speed": "Outrun the Lava"},
	"glacier": {"flawless": "Sure-Footed", "speed": "Avalanche Chaser"},
	"desert": {"flawless": "Light Sand-Walker", "speed": "Mirage Chaser"},
	"manor": {"flawless": "Unhaunted", "speed": "Ghost Train"},
	"neon": {"flawless": "Lane Discipline", "speed": "Rush Hour"},
	"ascent": {"flawless": "Untouchable Summit", "speed": "Beacon Sprint"},
}


## Keys of every challenge, "id:kind", in course order.
static func all_keys() -> Array[String]:
	var out: Array[String] = []
	for info: Dictionary in Game.LEVELS:
		for k: String in KINDS:
			out.append("%s:%s" % [info["id"], k])
	return out


static func total() -> int:
	return Game.LEVELS.size() * KINDS.size()


## Seconds the Speedrunner challenge asks for: halfway from Silver to Gold, whole seconds
## (-1 for a course without medal targets).
static func speed_target(level_id: String) -> float:
	var g: float = Game.medal_target(level_id, 3)
	var s: float = Game.medal_target(level_id, 2)
	if g <= 0.0 or s <= 0.0:
		return -1.0
	return roundf(lerpf(s, g, 0.5))


static func title(level_id: String, kind: String) -> String:
	var f: Variant = FLAVOUR.get(level_id)
	if f is Dictionary and (f as Dictionary).has(kind):
		return str((f as Dictionary)[kind])
	return str(GENERIC.get(kind, kind))


static func description(level_id: String, kind: String) -> String:
	match kind:
		"flawless":
			return "Finish without a single fall"
		"silver":
			return "Earn a Silver medal or better"
		"speed":
			var t: float = speed_target(level_id)
			return "Finish in under %s" % (SaveData.format_time(t).trim_suffix(".00") if t >= 0.0 else "the target")
	return ""


## Is the challenge met by these level records (no stored memory)?
static func met(levels: Dictionary, level_id: String, kind: String) -> bool:
	var e: Variant = levels.get(level_id)
	if not (e is Dictionary):
		return false
	var d: Dictionary = e
	match kind:
		"flawless":
			return int(d.get("fewest_falls", -1)) == 0 or int(d.get("legacy_fewest_falls", -1)) == 0
		"silver":
			return Cosmetics.medal_of(levels, level_id) >= 2
		"speed":
			var t: float = speed_target(level_id)
			var best: float = Cosmetics.medal_time(levels, level_id)
			return t >= 0.0 and best >= 0.0 and SaveData.centiseconds(best) < SaveData.centiseconds(t)
	return false


static func stored() -> Array:
	var s: Variant = SaveData.data.get("challenges", [])
	return s if s is Array else []


## Done now, or remembered as done. `levels` defaults to the save's records.
static func done(level_id: String, kind: String, levels: Variant = null) -> bool:
	var lv: Dictionary = levels if levels is Dictionary else SaveData.data.get("levels", {})
	if is_same(lv, SaveData.data.get("levels")) and stored().has("%s:%s" % [level_id, kind]):
		return true
	return met(lv, level_id, kind)


## Challenges done on one course (0-3).
static func level_count(level_id: String, levels: Variant = null) -> int:
	var n: int = 0
	for k: String in KINDS:
		if done(level_id, k, levels):
			n += 1
	return n


## Challenges done across the circuit.
static func count(levels: Variant = null) -> int:
	var n: int = 0
	for info: Dictionary in Game.LEVELS:
		n += level_count(str(info["id"]), levels)
	return n


## Keys ("id:kind") done right now (what a finish compares before and after).
static func done_keys() -> Array[String]:
	var out: Array[String] = []
	for key: String in all_keys():
		var p: PackedStringArray = key.split(":")
		if done(p[0], p[1]):
			out.append(key)
	return out


## Remembers every challenge now done (saves when something is new) and returns the keys
## that were not in `before` (a done_keys() taken ahead of the run).
static func sync(before: Array[String] = []) -> Array[String]:
	var now: Array[String] = done_keys()
	var fresh: Array[String] = []
	for k: String in now:
		if not before.has(k):
			fresh.append(k)
	var have: Array = stored()
	var changed: bool = false
	for k: String in now:
		if not have.has(k):
			have.append(k)
			changed = true
	if changed:
		SaveData.data["challenges"] = have
		SaveData.save_data()
	return fresh


## A save's "challenges" value reduced to known "id:kind" strings, each once.
static func sanitize(v: Variant) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	var known: Array[String] = all_keys()
	for k: Variant in (v as Array):
		if k is String and known.has(k) and not out.has(k):
			out.append(k)
	return out


## The "Challenge complete!" note for a key: [headline, second line].
static func note_text(key: String) -> PackedStringArray:
	var p: PackedStringArray = key.split(":")
	return PackedStringArray(["Challenge complete!  %s" % title(p[0], p[1]), "%s  -  %s" % [Cosmetics._level_name(p[0]), description(p[0], p[1])]])


## The nearest unowned `challenges` reward as [name, challenges still needed, n], or [].
static func next_reward() -> Array:
	var have: int = count()
	var best: Array = []
	for kind: String in Cosmetics.kinds():
		for id: String in Cosmetics.ids(kind):
			var rule: Dictionary = Cosmetics._rule(kind, id)
			if str(rule.get("type")) != "challenges":
				continue
			var n: int = int(rule.get("n", 1))
			if have < n and (best.is_empty() or n < int(best[2])):
				best = [Cosmetics.display_name(kind, id), n - have, n]
	return best
