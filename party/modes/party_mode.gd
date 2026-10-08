class_name PartyMode
extends Node3D
## One Party game type (King of the Hill, Elimination, Coin Rush, Hot Potato), a child of the
## PartyLayer for the round. The layer talks to every type through this one interface, so a new type
## is one file under party/modes/ plus a line in PartyModes.
##
## Authority: the HOST decides scoring and state; every peer shows it.
##  * host_tick / on_checkpoint / on_ko / on_request run the rules (host only: PartyLayer calls them there);
##  * send() broadcasts a host decision as a "md" party packet; on_message() applies it on every other peer
##    (the host applies its own decisions directly before sending);
##  * ask() sends a client's request to the host ("mq"); the host handles it in on_request().
## The packets ride Net.send_party, so they cross a direct connection and the room relay alike.
##
## Scoring hooks: mode_points() (extra round points, added to placement / KO / bonus points) and finish_order()
## (who placed where). End condition: round_over() (the layer also ends the round on its normal conditions:
## everyone home, 45 s after the first finisher, or the time limit). HUD widget: hud_lines().

var layer: PartyLayer
var id: String = "classic"
## Seconds of round clock this mode has run (ticks only while racing).
var clock: float = 0.0


func setup(p_layer: PartyLayer) -> void:
	layer = p_layer
	name = "PartyMode_%s" % id
	_setup()


func _setup() -> void:
	pass


func is_host() -> bool:
	return Net.is_host()


# ---- hooks (override) ----------------------------------------------------------------------------

## Every peer, every physics frame while the round runs: visuals and local pickups.
func tick(_dt: float) -> void:
	pass


## Host only: the rules.
func host_tick(_dt: float) -> void:
	pass


## A host broadcast ("md") arrived: `m` is its payload.
func on_message(_from_id: int, _m: Dictionary) -> void:
	pass


## Host: a peer's request ("mq") arrived.
func on_request(_from_id: int, _m: Dictionary) -> void:
	pass


## Host: racer `id` banked checkpoint `index` (1-based; checkpoints + 1 = the finish).
func on_checkpoint(_id: int, _index: int) -> void:
	pass


## Every peer: `by` knocked `victim` off the course (a KO).
func on_ko(_by: int, _victim: int) -> void:
	pass


## Our own attack landed on `victim_id` (a racer id, or a negative dummy id). Host-side for CPUs.
func on_hit(_by: int, _victim: int, _src: String) -> void:
	pass


## Every peer: a racer fell or died (a KO or not).
func on_fail(_id: int) -> void:
	pass


## Is this racer out of the round (spectating, untargetable, no more scoring)?
func is_out(_id: int) -> bool:
	return false


## Host: should the round end now, besides its normal conditions?
func round_over(_course_time: float) -> bool:
	return false


## Placement order (best first) given the default one (finishers in finishing order).
func finish_order(default_order: Array) -> Array:
	return default_order


## Extra round points: racer id -> points (may be negative).
func mode_points() -> Dictionary:
	return {}


## The HUD widget: a few lines of text (empty = hidden).
func hud_lines() -> Array[String]:
	return []


func hud_color() -> Color:
	return UiKit.GOLD


## The headline of a finished round for the results screen ("X held the hill longest").
func round_note() -> String:
	return ""


## What the extra column of the results screen is called.
func points_label() -> String:
	return "Mode"


## A snapshot others can restore (late packets, tests).
func state() -> Dictionary:
	return {}


# ---- helpers ----------------------------------------------------------------------------------------

## Host: broadcast a decision to everyone else.
func send(m: Dictionary) -> void:
	var out: Dictionary = m.duplicate()
	out["k"] = "md"
	out["v"] = id
	Net.send_party(out)


## Anyone: ask the host to do something (the host just does it).
func ask(m: Dictionary) -> void:
	if is_host():
		on_request(Net.my_id(), m)
		return
	var out: Dictionary = m.duplicate()
	out["k"] = "mq"
	out["v"] = id
	Net.send_party(out, 1)


## Racers in play: everyone on the roster who has not finished and is not out.
func active_ids() -> Array[int]:
	var out: Array[int] = []
	for rid: int in Net.roster:
		if float(Net.roster[rid].get("finished", -1.0)) < 0.0 and not is_out(rid):
			out.append(rid)
	out.sort()
	return out


func name_of(rid: int) -> String:
	return layer.racer_name(rid)


## Median checkpoint count of the racers still in play (the pack), 0 when nobody is.
func pack_checkpoint() -> int:
	var cps: Array[int] = []
	for rid: int in active_ids():
		cps.append(int(Net.roster[rid].get("cp", 0)))
	if cps.is_empty():
		return 0
	cps.sort()
	return cps[cps.size() / 2]


func announce(text: String, color: Color = UiKit.GOLD) -> void:
	layer.hud.announce(text, color)


func feed(text: String, color: Color = UiKit.SOFT) -> void:
	layer.hud.feed(text, color)
