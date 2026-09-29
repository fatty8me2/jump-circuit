class_name Cosmetics
extends RefCounted
## Unlockable cosmetics: movement trails and finish celebrations.
##
## Static (no autoload): the catalogue is data, unlocks are derived from SaveData's
## completion records every time they are asked for, so an old save unlocks everything it
## has earned the moment it is loaded. The only stored state is SaveData's
## "cosmetics_seen" list (so each "Unlocked: ..." toast shows once) and the equipped ids
## in Settings (trail_id / finish_id).
##
## Unlock rules ("rule" in an item):
##   {"type": "default"}               always owned
##   {"type": "level", "id": <id>}     beat that course
##   {"type": "levels", "n": N}        beat N different courses
##   {"type": "all"}                   beat every course
##   {"type": "runs", "n": N}          N finished runs in total (all courses)
##   {"type": "flawless"}              finish any course without a single fall

const DEFAULT_TRAIL: String = "classic"
const DEFAULT_FINISH: String = "cheer"

## id -> {name, rule}. Order is the Locker's order. The look lives in PlayerVisual.
const TRAILS: Dictionary = {
	"classic": {"name": "Classic", "rule": {"type": "default"}},
	"sparkle": {"name": "Sparkle", "rule": {"type": "default"}},
	"flame": {"name": "Flame", "rule": {"type": "level", "id": "volcano"}},
	"bubbles": {"name": "Bubbles", "rule": {"type": "level", "id": "reef"}},
	"frost": {"name": "Frost", "rule": {"type": "level", "id": "glacier"}},
	"sand": {"name": "Sandstorm", "rule": {"type": "level", "id": "desert"}},
	"wisps": {"name": "Ghostly Wisps", "rule": {"type": "level", "id": "manor"}},
	"sprinkles": {"name": "Sprinkles", "rule": {"type": "level", "id": "candy"}},
	"contrail": {"name": "Jet Contrail", "rule": {"type": "level", "id": "carrier"}},
	"rainbow": {"name": "Rainbow", "rule": {"type": "all"}},
}

const FINISHES: Dictionary = {
	"cheer": {"name": "Cheer", "rule": {"type": "default"}},
	"fireworks": {"name": "Fireworks", "rule": {"type": "levels", "n": 5}},
	"confetti": {"name": "Confetti Cannon", "rule": {"type": "runs", "n": 25}},
	"lightning": {"name": "Lightning Bolt", "rule": {"type": "level", "id": "armada"}},
	"ghost": {"name": "Ghost Spin", "rule": {"type": "flawless"}},
	"jet": {"name": "Jet Flyover", "rule": {"type": "levels", "n": 10}},
}


static func catalogue(kind: String) -> Dictionary:
	return TRAILS if kind == "trail" else FINISHES


static func ids(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in catalogue(kind):
		out.append(str(id))
	return out


static func has_item(kind: String, id: String) -> bool:
	return catalogue(kind).has(id)


static func default_id(kind: String) -> String:
	return DEFAULT_TRAIL if kind == "trail" else DEFAULT_FINISH


## "Flame trail", "Fireworks finish".
static func display_name(kind: String, id: String) -> String:
	var item: Dictionary = catalogue(kind).get(id, {})
	return "%s %s" % [str(item.get("name", id)), "trail" if kind == "trail" else "finish"]


## A known id, else the default (for ids read from settings or sent by other racers).
static func clean(kind: String, id: Variant) -> String:
	var s: String = str(id) if id is String or id is StringName else ""
	return s if has_item(kind, s) else default_id(kind)


# ---- unlock rules ----------------------------------------------------------------------------

## `levels` is SaveData.data["levels"] (tests pass their own).
static func rule_met(rule: Dictionary, levels: Dictionary) -> bool:
	match str(rule.get("type", "default")):
		"default":
			return true
		"level":
			return _completed(levels, str(rule.get("id", "")))
		"levels":
			return completed_count(levels) >= int(rule.get("n", 1))
		"all":
			for info: Dictionary in Game.LEVELS:
				if not _completed(levels, str(info["id"])):
					return false
			return true
		"runs":
			return total_runs(levels) >= int(rule.get("n", 1))
		"flawless":
			for id: Variant in levels:
				var e: Variant = levels[id]
				if e is Dictionary and ((e as Dictionary).get("fewest_falls", -1) == 0 or (e as Dictionary).get("legacy_fewest_falls", -1) == 0):
					return true
			return false
	return false


static func _completed(levels: Dictionary, id: String) -> bool:
	var e: Variant = levels.get(id)
	return e is Dictionary and bool((e as Dictionary).get("completed", false))


## Courses of the circuit beaten (the playground doesn't count).
static func completed_count(levels: Dictionary) -> int:
	var n: int = 0
	for info: Dictionary in Game.LEVELS:
		if _completed(levels, str(info["id"])):
			n += 1
	return n


static func total_runs(levels: Dictionary) -> int:
	var n: int = 0
	for info: Dictionary in Game.LEVELS:
		var e: Variant = levels.get(info["id"])
		if e is Dictionary:
			n += maxi(int((e as Dictionary).get("runs", 0)), 0)
	return n


static func is_unlocked(kind: String, id: String, levels: Variant = null) -> bool:
	if not has_item(kind, id):
		return false
	var lv: Dictionary = levels if levels is Dictionary else SaveData.data.get("levels", {})
	return rule_met(catalogue(kind)[id]["rule"], lv)


## The Locker's hint under a locked item.
static func hint(kind: String, id: String) -> String:
	var rule: Dictionary = catalogue(kind).get(id, {}).get("rule", {})
	match str(rule.get("type", "default")):
		"level":
			for info: Dictionary in Game.LEVELS:
				if info["id"] == rule.get("id"):
					return "Beat %s" % info["name"]
			return "Beat a course"
		"levels":
			return "Beat %d different courses" % int(rule.get("n", 1))
		"all":
			return "Beat all %d courses" % Game.LEVELS.size()
		"runs":
			return "Finish %d runs" % int(rule.get("n", 1))
		"flawless":
			return "Finish any course without a fall"
	return ""


## Progress towards a counted rule ("3/5"), "" for the others.
static func progress(kind: String, id: String, levels: Variant = null) -> String:
	var lv: Dictionary = levels if levels is Dictionary else SaveData.data.get("levels", {})
	var rule: Dictionary = catalogue(kind).get(id, {}).get("rule", {})
	match str(rule.get("type", "")):
		"levels":
			return "%d/%d" % [mini(completed_count(lv), int(rule["n"])), int(rule["n"])]
		"all":
			return "%d/%d" % [completed_count(lv), Game.LEVELS.size()]
		"runs":
			return "%d/%d" % [mini(total_runs(lv), int(rule["n"])), int(rule["n"])]
	return ""


# ---- equipped (a locked pick falls back to the default) ----------------------------------------

static func equipped_trail() -> String:
	var id: String = clean("trail", Settings.trail_id)
	return id if is_unlocked("trail", id) else DEFAULT_TRAIL


static func equipped_finish() -> String:
	var id: String = clean("finish", Settings.finish_id)
	return id if is_unlocked("finish", id) else DEFAULT_FINISH


# ---- "Unlocked: ..." announcements --------------------------------------------------------------

## Unlocked items not yet announced, as [kind, id] pairs, in catalogue order. Defaults are
## never announced. `mark` records them as seen (and saves) so each shows exactly once.
static func check_unlocks(mark: bool = true) -> Array[Array]:
	var seen: Array = SaveData.cosmetics_seen()
	var fresh: Array[Array] = []
	for kind: String in ["trail", "finish"]:
		for id: String in ids(kind):
			var key: String = "%s:%s" % [kind, id]
			if catalogue(kind)[id]["rule"]["type"] == "default" or seen.has(key):
				continue
			if is_unlocked(kind, id):
				fresh.append([kind, id])
	if mark and not fresh.is_empty():
		var keys: Array[String] = []
		for f: Array in fresh:
			keys.append("%s:%s" % [f[0], f[1]])
		SaveData.mark_cosmetics_seen(keys)
	return fresh


## "Unlocked: Flame trail!"
static func unlock_text(kind: String, id: String) -> String:
	return "Unlocked: %s!" % display_name(kind, id)
