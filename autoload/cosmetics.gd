class_name Cosmetics
extends RefCounted
## Unlockable cosmetics: characters, hats, paint jobs, movement trails, finish celebrations
## and titles.
##
## Static (no autoload): the catalogue is data, unlocks are derived from SaveData's
## completion records (and its small "stats" counters) every time they are asked for, so an
## old save unlocks everything it has earned the moment it is loaded. The only stored state
## is SaveData's "cosmetics_seen" list (so each "Unlocked: ..." toast shows once) and the
## equipped ids in Settings (see KINDS: character_id, hat_id, paint_id, trail_id, finish_id,
## title_id).
##
## Unlock rules ("rule" in an item):
##   {"type": "default"}                    always owned
##   {"type": "level", "id": <id>}          beat that course
##   {"type": "levels", "n": N}             beat N different courses
##   {"type": "all"}                        beat every course
##   {"type": "runs", "n": N}               N finished runs in total (all courses)
##   {"type": "flawless"}                   finish any course without a single fall
##   {"type": "medal", "level": <id>, "tier": T}   a medal of tier T (1 bronze, 2 silver, 3 gold)
##                                          or better on that course
##   {"type": "medals", "tier": T, "n": N}  tier T or better on N different courses
##   {"type": "all_medals", "tier": T}      tier T or better on every course
##   {"type": "stat", "key": <k>, "n": N}   SaveData stats[k] >= N ("runs" is the total run count)
## Medals are derived from min(best, legacy_best) (Game.medal_for), so a layout rebuild never
## takes one away and old saves earn them retroactively.

const DEFAULT_TRAIL: String = "classic"
const DEFAULT_FINISH: String = "cheer"

## id -> {name, rule}. Order is the Locker's order. The look lives in PlayerVisual.
const CHARACTERS: Dictionary = {
	"volt": {"name": "Volt", "rule": {"type": "default"}},
	"knight": {"name": "Knight", "rule": {"type": "medals", "tier": 1, "n": 10}},
	"ninja": {"name": "Ninja", "rule": {"type": "medal", "level": "sakura", "tier": 3}},
	"astronaut": {"name": "Astronaut", "rule": {"type": "medal", "level": "orbital", "tier": 3}},
	"dino": {"name": "Explorer Dino", "rule": {"type": "medal", "level": "jungle", "tier": 3}},
	"skeleton": {"name": "Skeleton", "rule": {"type": "medal", "level": "manor", "tier": 3}},
	"catbot": {"name": "Cat-bot", "rule": {"type": "medals", "tier": 2, "n": 10}},
	"outlaw": {"name": "Outlaw", "rule": {"type": "medal", "level": "frontier", "tier": 3}},
	"cyber": {"name": "Cyber Volt", "rule": {"type": "medal", "level": "neon", "tier": 3}},
	"golden": {"name": "Golden Volt", "rule": {"type": "all_medals", "tier": 3}},
}

## One hat per world for Silver on it, plus three specials.
const HATS: Dictionary = {
	"none": {"name": "No Hat", "rule": {"type": "default"}},
	"sunhat": {"name": "Gardener's Sun Hat", "rule": {"type": "medal", "level": "gardens", "tier": 2}},
	"hardhat": {"name": "Hard Hat", "rule": {"type": "medal", "level": "foundry", "tier": 2}},
	"propeller": {"name": "Propeller Cap", "rule": {"type": "medal", "level": "balance", "tier": 2}},
	"tophat": {"name": "Clockwork Top Hat", "rule": {"type": "medal", "level": "clockwork", "tier": 2}},
	"snorkel": {"name": "Snorkel", "rule": {"type": "medal", "level": "reef", "tier": 2}},
	"bubble": {"name": "Bubble Helmet", "rule": {"type": "medal", "level": "orbital", "tier": 2}},
	"antennae": {"name": "Alien Antennae", "rule": {"type": "medal", "level": "xeno", "tier": 2}},
	"horns": {"name": "Ember Horns", "rule": {"type": "medal", "level": "volcano", "tier": 2}},
	"viking": {"name": "Viking Helmet", "rule": {"type": "medal", "level": "glacier", "tier": 2}},
	"pharaoh": {"name": "Pharaoh Headdress", "rule": {"type": "medal", "level": "desert", "tier": 2}},
	"witch": {"name": "Witch Hat", "rule": {"type": "medal", "level": "manor", "tier": 2}},
	"tricorn": {"name": "Pirate Tricorn", "rule": {"type": "medal", "level": "armada", "tier": 2}},
	"cupcake": {"name": "Cupcake Hat", "rule": {"type": "medal", "level": "candy", "tier": 2}},
	"pilot": {"name": "Pilot Helmet", "rule": {"type": "medal", "level": "carrier", "tier": 2}},
	"kasa": {"name": "Straw Kasa", "rule": {"type": "medal", "level": "sakura", "tier": 2}},
	"pith": {"name": "Pith Helmet", "rule": {"type": "medal", "level": "jungle", "tier": 2}},
	"cowboy": {"name": "Cowboy Hat", "rule": {"type": "medal", "level": "frontier", "tier": 2}},
	"headphones": {"name": "Neon Headphones", "rule": {"type": "medal", "level": "neon", "tier": 2}},
	"beanie": {"name": "Summit Beanie", "rule": {"type": "medal", "level": "ascent", "tier": 2}},
	"welder": {"name": "Welder's Mask", "rule": {"type": "medal", "level": "doom", "tier": 2}},
	"diver": {"name": "Diving Helmet", "rule": {"type": "medal", "level": "abyss", "tier": 2}},
	"souwester": {"name": "Storm Sou'wester", "rule": {"type": "medal", "level": "tempest", "tier": 2}},
	"dreamcap": {"name": "Dream Nightcap", "rule": {"type": "medal", "level": "void", "tier": 2}},
	"crown": {"name": "Crown", "rule": {"type": "medals", "tier": 3, "n": 10}},
	"halo": {"name": "Halo", "rule": {"type": "stat", "key": "flawless_golds", "n": 1}},
	"party": {"name": "Party Hat", "rule": {"type": "stat", "key": "laps_dealt", "n": 3}},
}

const PAINTS: Dictionary = {
	"white": {"name": "Factory White", "rule": {"type": "default"}},
	"chrome": {"name": "Chrome", "rule": {"type": "medals", "tier": 3, "n": 5}},
	"camo": {"name": "Camo", "rule": {"type": "medals", "tier": 2, "n": 5}},
	"lava": {"name": "Lava", "rule": {"type": "medal", "level": "volcano", "tier": 3}},
	"galaxy": {"name": "Galaxy", "rule": {"type": "medal", "level": "ascent", "tier": 3}},
	"candy": {"name": "Candy Stripe", "rule": {"type": "medal", "level": "candy", "tier": 3}},
	"ghost": {"name": "Ghost", "rule": {"type": "medal", "level": "manor", "tier": 2}},
	"neon": {"name": "Neon Glow", "rule": {"type": "medal", "level": "neon", "tier": 2}},
}

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

## Shown beside your name on the roster, the race board and your name tag.
const TITLES: Dictionary = {
	"rookie": {"name": "Rookie", "rule": {"type": "default"}},
	"globetrotter": {"name": "Globetrotter", "rule": {"type": "all"}},
	"speed_demon": {"name": "Speed Demon", "rule": {"type": "medals", "tier": 3, "n": 5}},
	"gold_rush": {"name": "Gold Rush", "rule": {"type": "all_medals", "tier": 3}},
	"flawless": {"name": "Flawless", "rule": {"type": "flawless"}},
	"lap_king": {"name": "Lap King", "rule": {"type": "stat", "key": "laps_dealt", "n": 10}},
	"marathoner": {"name": "Marathoner", "rule": {"type": "runs", "n": 100}},
}

## kind -> catalogue, default id, Locker tab label, Settings property, display-name suffix.
## Order is the Locker's tab order, the unlock announcement order and what registration sends.
const KINDS: Dictionary = {
	"character": {"items": CHARACTERS, "default": "volt", "label": "Character", "setting": "character_id", "suffix": ""},
	"hat": {"items": HATS, "default": "none", "label": "Hat", "setting": "hat_id", "suffix": ""},
	"paint": {"items": PAINTS, "default": "white", "label": "Paint", "setting": "paint_id", "suffix": " paint"},
	"trail": {"items": TRAILS, "default": DEFAULT_TRAIL, "label": "Trail", "setting": "trail_id", "suffix": " trail"},
	"finish": {"items": FINISHES, "default": DEFAULT_FINISH, "label": "Finish", "setting": "finish_id", "suffix": " finish"},
	"title": {"items": TITLES, "default": "rookie", "label": "Title", "setting": "title_id", "suffix": " title"},
}

const MEDAL_NAMES: Array[String] = ["", "Bronze", "Silver", "Gold"]


static func kinds() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in KINDS:
		out.append(str(k))
	return out


static func catalogue(kind: String) -> Dictionary:
	return (KINDS.get(kind, {}) as Dictionary).get("items", {})


static func ids(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in catalogue(kind):
		out.append(str(id))
	return out


static func has_item(kind: String, id: String) -> bool:
	return catalogue(kind).has(id)


static func default_id(kind: String) -> String:
	return str((KINDS.get(kind, {}) as Dictionary).get("default", ""))


static func kind_label(kind: String) -> String:
	return str((KINDS.get(kind, {}) as Dictionary).get("label", kind.capitalize()))


static func setting_key(kind: String) -> String:
	return str((KINDS.get(kind, {}) as Dictionary).get("setting", ""))


static func item_name(kind: String, id: String) -> String:
	return str((catalogue(kind).get(id, {}) as Dictionary).get("name", id))


## "Flame trail", "Fireworks finish", "Ninja", "Witch Hat", "Chrome paint".
static func display_name(kind: String, id: String) -> String:
	return item_name(kind, id) + str((KINDS.get(kind, {}) as Dictionary).get("suffix", ""))


## A known id, else the default (for ids read from settings or sent by other racers).
static func clean(kind: String, id: Variant) -> String:
	var s: String = str(id) if id is String or id is StringName else ""
	return s if has_item(kind, s) else default_id(kind)


## "Ada · Speed Demon": a racer's name with their title (unknown ids show the default title).
static func titled(player_name: String, title_id: Variant) -> String:
	return "%s · %s" % [player_name, item_name("title", clean("title", title_id))]


# ---- medals ----------------------------------------------------------------------------------

## The time medals count for a level's save entry: the faster of the current-layout best and
## a best set on an older layout (-1 when there is neither).
static func medal_time(levels: Dictionary, id: String) -> float:
	var e: Variant = levels.get(id)
	if not (e is Dictionary):
		return -1.0
	var t: float = -1.0
	for k: String in ["best", "legacy_best"]:
		var v: Variant = (e as Dictionary).get(k)
		if (v is float or v is int) and float(v) >= 0.0:
			t = float(v) if t < 0.0 else minf(t, float(v))
	return t


## 0 none, 1 bronze, 2 silver, 3 gold.
static func medal_of(levels: Dictionary, id: String) -> int:
	return Game.medal_for(id, medal_time(levels, id))


## Courses with tier `tier` or better.
static func medal_count(levels: Dictionary, tier: int) -> int:
	var n: int = 0
	for info: Dictionary in Game.LEVELS:
		if medal_of(levels, str(info["id"])) >= tier:
			n += 1
	return n


static func _level_name(id: String) -> String:
	for info: Dictionary in Game.LEVELS:
		if info["id"] == id:
			return str(info["name"])
	return "a course"


# ---- unlock rules ----------------------------------------------------------------------------

static func _levels_or_save(levels: Variant) -> Dictionary:
	return levels if levels is Dictionary else SaveData.data.get("levels", {})


static func _stats_or_save(stats: Variant) -> Dictionary:
	if stats is Dictionary:
		return stats
	var s: Variant = SaveData.data.get("stats", {})
	return s if s is Dictionary else {}


## A counter for "stat" rules: "runs" is derived from the levels, the rest come from stats.
static func stat_value(key: String, levels: Dictionary, stats: Dictionary) -> int:
	if key == "runs":
		return total_runs(levels)
	return maxi(int(stats.get(key, 0)), 0)


## `levels` is SaveData.data["levels"] and `stats` SaveData.data["stats"] (tests pass their own).
static func rule_met(rule: Dictionary, levels: Dictionary, stats: Variant = null) -> bool:
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
		"medal":
			return medal_of(levels, str(rule.get("level", ""))) >= int(rule.get("tier", 3))
		"medals":
			return medal_count(levels, int(rule.get("tier", 3))) >= int(rule.get("n", 1))
		"all_medals":
			return medal_count(levels, int(rule.get("tier", 3))) >= Game.LEVELS.size()
		"stat":
			return stat_value(str(rule.get("key", "")), levels, _stats_or_save(stats)) >= int(rule.get("n", 1))
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


static func is_unlocked(kind: String, id: String, levels: Variant = null, stats: Variant = null) -> bool:
	if not has_item(kind, id):
		return false
	# once earned, always earned: anything already announced stays unlocked even if its rule
	# stops holding (new courses would otherwise re-lock "beat every course" rewards)
	if levels == null and SaveData.cosmetics_seen().has("%s:%s" % [kind, id]):
		return true
	return rule_met(catalogue(kind)[id]["rule"], _levels_or_save(levels), stats)


static func _rule(kind: String, id: String) -> Dictionary:
	return (catalogue(kind).get(id, {}) as Dictionary).get("rule", {})


## The Locker's hint under a locked item.
static func hint(kind: String, id: String) -> String:
	var rule: Dictionary = _rule(kind, id)
	match str(rule.get("type", "default")):
		"level":
			return "Beat %s" % _level_name(str(rule.get("id", "")))
		"levels":
			return "Beat %d different courses" % int(rule.get("n", 1))
		"all":
			return "Beat all %d courses" % Game.LEVELS.size()
		"runs":
			return "Finish %d runs" % int(rule.get("n", 1))
		"flawless":
			return "Finish any course without a fall"
		"medal":
			return "%s on %s" % [_tier_name(int(rule.get("tier", 3))), _level_name(str(rule.get("level", "")))]
		"medals":
			return "%s on %d courses" % [_tier_name(int(rule.get("tier", 3))), int(rule.get("n", 1))]
		"all_medals":
			return "%s on every course" % _tier_name(int(rule.get("tier", 3)))
		"stat":
			var n: int = int(rule.get("n", 1))
			match str(rule.get("key", "")):
				"laps_dealt":
					return "Lap other racers %d time%s (Run It Again)" % [n, "" if n == 1 else "s"]
				"flawless_golds":
					return "Gold with no falls in the same run"
				"runs":
					return "Finish %d runs" % n
			return "%s %d" % [str(rule.get("key", "")).capitalize(), n]
	return ""


## "Gold" / "Silver or better" phrasing for hints.
static func _tier_name(tier: int) -> String:
	tier = clampi(tier, 1, 3)
	return MEDAL_NAMES[tier] if tier == 3 else "%s or better" % MEDAL_NAMES[tier]


## Progress towards a counted rule ("3/5"), "" for the others.
static func progress(kind: String, id: String, levels: Variant = null, stats: Variant = null) -> String:
	var lv: Dictionary = _levels_or_save(levels)
	var rule: Dictionary = _rule(kind, id)
	match str(rule.get("type", "")):
		"levels":
			return "%d/%d" % [mini(completed_count(lv), int(rule["n"])), int(rule["n"])]
		"all":
			return "%d/%d" % [completed_count(lv), Game.LEVELS.size()]
		"runs":
			return "%d/%d" % [mini(total_runs(lv), int(rule["n"])), int(rule["n"])]
		"medals":
			var tier: int = int(rule.get("tier", 3))
			return "%ss %d/%d" % [MEDAL_NAMES[clampi(tier, 1, 3)], mini(medal_count(lv, tier), int(rule["n"])), int(rule["n"])]
		"all_medals":
			var t: int = int(rule.get("tier", 3))
			return "%ss %d/%d" % [MEDAL_NAMES[clampi(t, 1, 3)], medal_count(lv, t), Game.LEVELS.size()]
		"medal":
			var have: int = medal_of(lv, str(rule.get("level", "")))
			return "best: %s" % (MEDAL_NAMES[have] if have > 0 else "no medal")
		"stat":
			var n: int = int(rule.get("n", 1))
			return "%d/%d" % [mini(stat_value(str(rule.get("key", "")), lv, _stats_or_save(stats)), n), n]
	return ""


# ---- equipped (a locked pick falls back to the default) ----------------------------------------

## The id worn for `kind`: the Settings pick if it is known and unlocked, else the default.
static func equipped(kind: String) -> String:
	var key: String = setting_key(kind)
	var id: String = clean(kind, Settings.get(key) if key != "" else null)
	return id if is_unlocked(kind, id) else default_id(kind)


static func equipped_trail() -> String:
	return equipped("trail")


static func equipped_finish() -> String:
	return equipped("finish")


## Every kind's worn id, {kind: id} (what registration sends to the other racers).
static func equipped_all() -> Dictionary:
	var out: Dictionary = {}
	for kind: String in kinds():
		out[kind] = equipped(kind)
	return out


# ---- "Unlocked: ..." announcements --------------------------------------------------------------

## Unlocked items not yet announced, as [kind, id] pairs, in catalogue order. Defaults are
## never announced. `mark` records them as seen (and saves) so each shows exactly once.
static func check_unlocks(mark: bool = true) -> Array[Array]:
	var seen: Array = SaveData.cosmetics_seen()
	var fresh: Array[Array] = []
	for kind: String in kinds():
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


## "GOLD! New reward: Ninja" (a run that earned a new medal and unlocked something with it).
static func medal_reward_text(tier: int, kind: String, id: String) -> String:
	return "%s! New reward: %s" % [MEDAL_NAMES[clampi(tier, 1, 3)].to_upper(), display_name(kind, id)]
