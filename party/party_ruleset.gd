class_name PartyRuleset
extends RefCounted
## The host-chosen rules of a Party Cup: game type, cup length, item frequency, per-item toggles, KO
## value, round time limit and CPU fill. Plain data (a Dictionary of JSON-safe values):
##  * the host (and a Party vs CPU session) reads it from Settings.party_ruleset, which the lobby / Party vs CPU
##    screens edit and save;
##  * everyone else gets the host's copy with every roster snapshot (Net._party_cfg), on a direct
##    connection and over the relay alike - so `cur()` is the one place the game reads rules from.
## Everything is sanitised on the way in, so a hand-edited settings file or a bad packet cannot break a round.

## Game types: "classic" is today's Party / Team Party round; the others live in party/modes/.
const VARIANTS: Array[String] = ["classic", "hill", "elim", "coins", "potato"]
## Cup lengths in rounds (0 = Endless, the old behaviour).
const CUPS: Array[int] = [3, 5, 8, 0]
const FREQ: Array[String] = ["off", "low", "normal", "chaos"]
const KO_VALUES: Array[int] = [1, 2, 3, 4, 5, 6, 8, 10]
## Round time limits in seconds.
const TIMES: Array[int] = [90, 120, 180, 240, 300, 480]
## CPU fill (online): 0 off, else the racer count the roster is topped up to.
const FILLS: Array[int] = [0, 8, 6, 4]

## Tests switch this off so editing a rule never rewrites the real settings file.
static var persist: bool = true

const DEFAULTS: Dictionary = {"variant": "classic", "cup": 0, "freq": "normal", "off": [], "ko": 3, "time": 240, "cpu": 0}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## A clean ruleset from anything (missing keys take defaults; numbers may arrive as floats from JSON).
static func sanitize(raw: Variant) -> Dictionary:
	var out: Dictionary = defaults()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	var v: String = str(d.get("variant", "classic"))
	out["variant"] = v if VARIANTS.has(v) else "classic"
	out["cup"] = _pick_int(d.get("cup", 0), CUPS, 0)
	var f: String = str(d.get("freq", "normal"))
	out["freq"] = f if FREQ.has(f) else "normal"
	out["ko"] = _pick_int(d.get("ko", 3), KO_VALUES, 3)
	out["time"] = _pick_int(d.get("time", 240), TIMES, 240)
	out["cpu"] = _pick_int(d.get("cpu", 0), FILLS, 0)
	var off: Array = []
	var raw_off: Variant = d.get("off", [])
	if typeof(raw_off) == TYPE_ARRAY:
		for e: Variant in raw_off:
			var id: String = str(e)
			if id != "" and id.length() <= 24 and not off.has(id) and off.size() < 64:
				off.append(id)
		off.sort()
	out["off"] = off
	return out


## `x` as the nearest allowed value (ints, or floats that are whole numbers).
static func _pick_int(x: Variant, allowed: Array[int], fallback: int) -> int:
	if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
		return fallback
	if typeof(x) == TYPE_FLOAT and not is_finite(float(x)):
		return fallback
	var n: int = int(x)
	return n if allowed.has(n) else fallback


## The rules in force: the host's synced copy on a guest, else our own saved choice.
static func cur() -> Dictionary:
	if Net.active and not Net.is_host():
		return sanitize(Net.synced_ruleset)
	return sanitize(Settings.party_ruleset)


static func variant() -> String:
	return str(cur()["variant"])


static func cup_rounds() -> int:
	return int(cur()["cup"])


static func ko() -> int:
	return int(cur()["ko"])


static func time_limit() -> float:
	return float(cur()["time"])


static func freq() -> String:
	return str(cur()["freq"])


static func item_enabled(id: String) -> bool:
	return not (cur()["off"] as Array).has(id)


## The items a roll may hand out (everything in the catalogue minus the host's toggles).
static func enabled_items() -> Array[String]:
	var out: Array[String] = []
	var off: Array = cur()["off"]
	for id: String in PartyItems.ids():
		if not off.has(id):
			out.append(id)
	return out


## Are item boxes on at all (frequency not Off, and at least one item enabled)?
static func boxes_on() -> bool:
	return freq() != "off" and not enabled_items().is_empty()


## Seconds an item box stays empty after a pickup.
static func box_respawn() -> float:
	match freq():
		"low":
			return 9.0
		"chaos":
			return 1.5
	return PartyLayer.BOX_RESPAWN


## Share of the placed item boxes that exist (Low thins them out).
static func box_share() -> float:
	return 0.5 if freq() == "low" else 1.0


## The host edits one rule: saved to Settings, and (online) broadcast with the next roster snapshot.
static func set_value(key: String, value: Variant) -> void:
	var rs: Dictionary = sanitize(Settings.party_ruleset)
	rs[key] = value
	Settings.party_ruleset = sanitize(rs)
	if persist:
		Settings.save_settings()
	if Net.active and Net.is_host():
		Net.publish_ruleset()


static func toggle_item(id: String) -> void:
	var off: Array = (cur()["off"] as Array).duplicate()
	if off.has(id):
		off.erase(id)
	else:
		off.append(id)
	set_value("off", off)


## Index of a cup length / etc. inside its table (for the cycler rows).
static func index_of_int(allowed: Array[int], value: int) -> int:
	return maxi(allowed.find(value), 0)


# ---- display ----------------------------------------------------------------------------------

static func cup_label(n: int) -> String:
	return "Endless" if n <= 0 else "%d rounds" % n


static func time_label(s: int) -> String:
	return "%d s" % s if s < 120 else "%d min" % (s / 60) if s % 60 == 0 else "%d:%02d" % [s / 60, s % 60]


static func fill_label(n: int) -> String:
	return "Off" if n <= 0 else "Fill to %d" % n


static func freq_label(f: String) -> String:
	return f.capitalize()


## A one-line summary for the lobby (what guests see of the host's choices).
static func summary(rs: Dictionary = {}) -> String:
	var r: Dictionary = cur() if rs.is_empty() else sanitize(rs)
	var parts: Array[String] = [PartyNames.variant_name(str(r["variant"])), "cup: " + cup_label(int(r["cup"])),
		"items: " + freq_label(str(r["freq"])) , "KO %d" % int(r["ko"]), "round " + time_label(int(r["time"]))]
	if (r["off"] as Array).size() > 0:
		parts.append("%d item%s off" % [(r["off"] as Array).size(), "" if (r["off"] as Array).size() == 1 else "s"])
	if int(r["cpu"]) > 0:
		parts.append("CPUs fill to %d" % int(r["cpu"]))
	return "   |   ".join(parts)


## True once the cup is complete (the round just played was the last one of a finite cup).
static func cup_done(round_no: int) -> bool:
	var n: int = cup_rounds()
	return n > 0 and round_no >= n
