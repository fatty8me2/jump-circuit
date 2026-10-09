class_name PartyFeedText
extends RefCounted
## Wording for the Party HUD's event feed ("Ana iced Bo!"): a verb for every move / item that
## can hit someone, and the item whose icon goes with it. Names of the moves themselves live in
## PartyNames; this is only the feed's phrasing.

## hit source -> past-tense verb.
const VERBS: Dictionary = {
	"shove": "shoved", "claw": "clawed", "beast_bomb": "blasted", "blade": "slashed", "spin": "spun",
	"boomerang": "bonked", "hookshot": "hooked", "bombs": "bombed", "dash_punch": "punched", "wave": "blasted",
	"thunder": "zapped", "slick": "slipped", "glove": "punched", "magnet": "pulled", "shrink": "shrank",
	"swap": "swapped with", "balloon": "bounced", "gravity": "floated", "ice": "iced", "tornado": "twirled",
	"homing": "shelled", "strike": "struck", "fakebox": "tricked", "ghost": "robbed", "shock": "blasted away",
}
## hit source -> item id (for the icon); sources that are an item themselves map to themselves.
const ITEM_OF: Dictionary = {
	"claw": "fox", "beast_bomb": "fox", "blade": "tunic", "spin": "tunic", "boomerang": "tunic",
	"hookshot": "tunic", "bombs": "tunic", "dash_punch": "surge", "wave": "surge",
}
## Items worth a "<name> used ..." line when activated (hits already get their own line).
const USE_LINES: Dictionary = {
	"fox": "turned into the %s!", "tunic": "put on the %s!", "surge": "went %s!", "jetpack": "strapped on the %s!",
	"tornado": "unleashed a %s!", "balloon": "popped up a %s!", "slick": "left a %s!", "magnet": "switched on the %s!",
	"swap": "fired the %s!", "thunder": "called the %s!",
	"homing": "fired a %s!", "strike": "called down a %s!", "fakebox": "planted a %s!", "turbo": "lit the %s!",
	"ghost": "became a %s!", "decoy": "dropped a %s!", "shock": "slammed a %s!",
}


static func verb(src: String) -> String:
	return str(VERBS.get(src, "hit"))


static func item_for(src: String) -> String:
	if ITEM_OF.has(src):
		return str(ITEM_OF[src])
	return src if PartyNames.ITEMS.has(src) else ""


## "Ana iced Bo!" / "Ana zapped Bo, Cy!".
static func hit_line(attacker: String, victims: Array, src: String) -> String:
	return "%s %s %s!" % [attacker, verb(src), ", ".join(victims)]


## "Ana called the Thunder Cloud!" ("" for items whose hits speak for themselves).
static func use_line(who: String, item: String) -> String:
	if not USE_LINES.has(item):
		return ""
	return "%s %s" % [who, str(USE_LINES[item]) % PartyNames.item_name(item)]
