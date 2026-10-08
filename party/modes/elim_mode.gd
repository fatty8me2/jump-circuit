class_name PartyModeElim
extends PartyMode
## Elimination: the last racer through each checkpoint is out. They spectate; the last one standing wins.
## The finish gate counts as the last checkpoint. If no gate has dropped anyone for CREEP seconds, whoever is
## last in the standings goes anyway, so a round always ends. Placement points follow the elimination order
## (the survivor 1st, the first one out last) instead of finishing times.

const CREEP: float = 40.0

## racer id -> elimination number (1 = first out).
var out: Dictionary = {}
var _resolved: Dictionary = {}
var _last_drop: float = 0.0


func _init() -> void:
	id = "elim"


func is_out(rid: int) -> bool:
	return out.has(rid)


## Racers still in the round (finished ones included: they are through).
func alive() -> Array[int]:
	var res: Array[int] = []
	for rid: int in Net.roster:
		if not out.has(rid):
			res.append(rid)
	res.sort()
	return res


# ---- host rules ---------------------------------------------------------------------------------------

func on_checkpoint(_rid: int, index: int) -> void:
	if not is_host() or _resolved.has(index) or index < 1:
		return
	var live: Array[int] = alive()
	if live.size() < 2:
		return
	var behind: Array[int] = []
	for rid: int in live:
		var e: Dictionary = Net.roster[rid]
		if int(e.get("cp", 0)) < index and float(e.get("finished", -1.0)) < 0.0:
			behind.append(rid)
	if behind.size() == 1:
		_resolved[index] = true
		_drop(behind[0], "last through checkpoint %d" % index if index <= layer.level.checkpoints.size() else "last to the finish")


func host_tick(_dt: float) -> void:
	if Game.course_time < 0.0:
		return
	if Game.course_time - _last_drop >= CREEP + (10.0 if out.is_empty() else 0.0):
		var live: Array[int] = alive()
		if live.size() < 2:
			return
		# the creep takes whoever is last among the racers who have not finished
		var order: Array[int] = Net.standings()
		order.reverse()
		for rid: int in order:
			if live.has(rid) and float(Net.roster[rid].get("finished", -1.0)) < 0.0:
				_drop(rid, "too slow")
				return


## Host: `rid` is out.
func _drop(rid: int, why: String) -> void:
	if out.has(rid):
		return
	_last_drop = Game.course_time
	var n: int = out.size() + 1
	_apply_out(rid, n, why)
	send({"m": "out", "id": rid, "n": n, "why": why})


func on_message(_from_id: int, m: Dictionary) -> void:
	if str(m.get("m", "")) == "out":
		_apply_out(int(m.get("id", 0)), int(m.get("n", out.size() + 1)), str(m.get("why", "")))


func _apply_out(rid: int, n: int, why: String) -> void:
	if out.has(rid) or not Net.roster.has(rid):
		return
	out[rid] = n
	_last_drop = Game.course_time
	var me: bool = rid == Net.my_id()
	var g: RemoteRacer = layer.ghost(rid)
	var at: Vector3 = layer.player.global_position if me else (g.global_position if g != null else Vector3.INF)
	if at != Vector3.INF:
		PartyFx.ko_burst(layer, at + Vector3(0, 0.8, 0), Color(1.0, 0.3, 0.3))
		PartyFx.explosion(layer, at + Vector3(0, 0.8, 0), Color(1.0, 0.4, 0.2), Color(1.0, 0.8, 0.3), 1.6)
		layer.sfx.play_at("elim", at, 1.0)
	if g != null and not me:
		g.visible = false
	# a CPU that is out stops running
	var f: CpuField = CpuField.current
	if f != null and is_instance_valid(f) and f.racers.has(rid):
		(f.racers[rid] as CpuRacer).finished = true
	feed("%s is OUT  (%s)" % [name_of(rid), why], Color(1.0, 0.45, 0.4))
	if me:
		announce("ELIMINATED", Color(1.0, 0.35, 0.3))
		layer.sfx.play("elim", 1.0)
		layer.go_spectator()
	elif alive().size() > 1:
		announce("%s is out!" % name_of(rid), Color(1.0, 0.6, 0.4))


func round_over(_course_time: float) -> bool:
	var live: Array[int] = alive()
	if live.size() <= 1 and not out.is_empty():
		return true
	# everyone still in has finished
	for rid: int in live:
		if float(Net.roster[rid].get("finished", -1.0)) < 0.0:
			return false
	return not live.is_empty() and not out.is_empty()


## Survivors in the standings' order first, then the eliminated, latest out first.
func finish_order(_default_order: Array) -> Array:
	var res: Array = []
	for rid: int in Net.standings():
		if not out.has(rid):
			res.append(rid)
	var gone: Array = out.keys()
	gone.sort_custom(func(a: int, b: int) -> bool: return int(out[a]) > int(out[b]))
	res.append_array(gone)
	return res


func state() -> Dictionary:
	return {"out": out.duplicate()}


func round_note() -> String:
	var live: Array[int] = alive()
	if live.size() == 1:
		return "%s is the last one standing" % name_of(live[0])
	return ""


func points_label() -> String:
	return "Out"


func hud_lines() -> Array[String]:
	var live: Array[int] = alive()
	var lines: Array[String] = ["ELIMINATION", "Racers left: %d of %d" % [live.size(), Net.roster.size()]]
	if out.has(Net.my_id()):
		lines.append("You are out - spectating")
	else:
		var order: Array[int] = []
		for rid: int in Net.standings():
			if live.has(rid):
				order.append(rid)
		lines.append("Your place: %d of %d" % [order.find(Net.my_id()) + 1, order.size()])
		if order.size() > 1 and order.back() == Net.my_id():
			lines.append("YOU ARE LAST!  Reach the next checkpoint!")
	return lines


func hud_color() -> Color:
	var live: Array[int] = alive()
	var order: Array[int] = []
	for rid: int in Net.standings():
		if live.has(rid):
			order.append(rid)
	return Color(1.0, 0.35, 0.3) if order.size() > 1 and order.back() == Net.my_id() and not out.has(Net.my_id()) else Color(1.0, 0.7, 0.35)


## Is `rid` the rearmost racer still in (the CPU heuristic "avoid being last")?
func is_last(rid: int) -> bool:
	var live: Array[int] = alive()
	var order: Array[int] = []
	for r2: int in Net.standings():
		if live.has(r2) and float(Net.roster[r2].get("finished", -1.0)) < 0.0:
			order.append(r2)
	return order.size() > 1 and order.back() == rid
