class_name PartyModes
extends RefCounted
## The game types behind PartyRuleset's "variant": id -> script. "classic" has none (today's round).

const SCRIPTS: Dictionary = {
	"hill": preload("res://party/modes/hill_mode.gd"),
	"elim": preload("res://party/modes/elim_mode.gd"),
	"coins": preload("res://party/modes/coin_mode.gd"),
	"potato": preload("res://party/modes/potato_mode.gd"),
}


## A fresh mode object for `id`, or null for the classic race (and unknown ids).
static func create(id: String) -> PartyMode:
	var scr: GDScript = SCRIPTS.get(id, null) as GDScript
	return null if scr == null else scr.new() as PartyMode
