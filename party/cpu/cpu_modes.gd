class_name CpuModes
extends RefCounted
## How CPU racers play the party game types (party/modes/). A CPU still drives the course's own route; these
## heuristics only shade its pace and its shoving:
##  * King of the Hill: run to the lawn the zone sits on, then stand in it for a spell and shove whoever else is in it;
##  * Elimination: the rearmost racer still in runs flat out (a bit faster than normal) and shoves the racer ahead;
##  * Coin Rush: coins sit on the route, so running the line collects them; a CPU that has just been KO'd
##    keeps to the line to pick up the coins it dropped;
##  * Hot Potato: the holder slows to let rivals catch up and shoves anyone in reach at once (passing the bomb);
##    everyone else runs from the holder.
## Every function is a pure read of the mode and the CPU, so it is unit-testable without a round.

const IDLE_PACE: float = 0.02


## Multiplier on the CPU's run pace.
static func pace_mult(r: CpuRacer, f: CpuField, dt: float) -> float:
	var m: PartyMode = f.layer.mode
	if m == null or r.finished:
		return 1.0
	if m is PartyModeHill:
		return _hill_pace(r, m as PartyModeHill, dt)
	if m is PartyModeElim:
		var e: PartyModeElim = m
		return 1.18 if e.is_last(r.id) else 1.0
	if m is PartyModePotato:
		var pt: PartyModePotato = m
		if pt.holder == 0:
			return 1.0
		if pt.holder == r.id:
			return 0.8   # let the others catch up: a bomb needs someone to give it to
		if _near_holder(r, pt, f) < 7.0:
			return 1.2
	return 1.0


static func _hill_pace(r: CpuRacer, z: PartyModeHill, dt: float) -> float:
	var st: Dictionary = r.mode_state
	if int(st.get("zone", -1)) != z.zone_i:
		st["zone"] = z.zone_i
		st["linger"] = 0.0
		st["max"] = r.rng.randf_range(7.0, 15.0)
	if z.contains(r.walker.pos):
		# in the zone: hold it while it lasts (for a while), alone or not
		if z._left > 1.5 and float(st["linger"]) < float(st["max"]):
			st["linger"] = float(st["linger"]) + dt
			return IDLE_PACE
		return 1.0
	# still short of the zone's lawn: hurry
	if r.walker.cp < z.zone_i:
		return 1.1
	return 1.0


static func _near_holder(r: CpuRacer, pt: PartyModePotato, f: CpuField) -> float:
	var p: Vector3 = f.layer.racer_pos(pt.holder)
	return INF if p == Vector3.INF else RouteMath.flat(p - r.walker.pos).length()


## Does this CPU shove a rival in reach regardless of its usual encounter cooldown?
static func eager(r: CpuRacer, f: CpuField) -> bool:
	var m: PartyMode = f.layer.mode
	if m is PartyModePotato:
		return (m as PartyModePotato).holder == r.id
	return false


## The chance to shove `rival` (a CpuField.rivals_of entry), given the usual chance.
static func melee_chance(r: CpuRacer, f: CpuField, chance: float, rival: Dictionary) -> float:
	var m: PartyMode = f.layer.mode
	if m == null:
		return chance
	if m is PartyModePotato:
		var pt: PartyModePotato = m
		if pt.holder == r.id:
			return 1.0
		return chance * 0.3
	if m is PartyModeHill:
		var z: PartyModeHill = m
		if z.contains(r.walker.pos) and z.contains(rival["pos"] as Vector3):
			return maxf(chance, 0.8)
	if m is PartyModeElim:
		if (m as PartyModeElim).is_last(r.id):
			return maxf(chance, 0.7)
	return chance
