class_name PartyRules
extends RefCounted
## Party Mode rules and the Party Cup scoreboard. `Game.party` holds one of these while a
## party session (or Party Practice) is on and is null in the main mode - that null is the
## single switch that keeps solo Race / multiplayer Race untouched.
## Everything here is pure bookkeeping (no nodes, no networking), so it is unit-tested directly.

## Placement points by finishing place (1st..8th); unfinished racers get 0.
const PLACE_POINTS: Array[int] = [10, 8, 6, 5, 4, 3, 2, 1]
const KO_POINTS: int = 3
## First racer through each checkpoint.
const BONUS_POINTS: int = 2
## A rival who falls or dies within this many seconds of your last hit on them is your KO.
const KO_WINDOW: float = 4.0
## The round ends this long after the first finisher (or when everyone is home).
const ROUND_GRACE: float = 45.0

## "party" (free-for-all), "team" (two teams) or "practice" (solo, no scoring).
var mode: String = "party"
## Rounds started in this cup (the round being played, once a race has started).
var round_no: int = 0
## Cup totals: peer id -> points over all rounds so far.
var cup: Dictionary = {}
## Last known name / team of everyone who scored, so standings survive someone leaving.
var names: Dictionary = {}
var teams: Dictionary = {}


func _init(p_mode: String = "party") -> void:
	mode = p_mode


func is_team() -> bool:
	return mode == "team"


func is_practice() -> bool:
	return mode == "practice"


## 1-based place -> points (0 for no place / beyond 8th).
static func placement_points(place: int) -> int:
	if place < 1 or place > PLACE_POINTS.size():
		return 0
	return PLACE_POINTS[place - 1]


## The round is over once everyone finished, or ROUND_GRACE seconds (course time) after the
## first finish. `finish_times` holds each racer's finish course-time, -1 if still racing.
static func round_over(finish_times: Array, course_time: float) -> bool:
	if finish_times.is_empty():
		return false
	var first: float = first_finish(finish_times)
	if first < 0.0:
		return false
	for t: Variant in finish_times:
		if float(t) < 0.0:
			return course_time >= first + ROUND_GRACE
	return true


static func first_finish(finish_times: Array) -> float:
	var first: float = -1.0
	for t: Variant in finish_times:
		if float(t) >= 0.0 and (first < 0.0 or float(t) < first):
			first = float(t)
	return first


## Seconds left before the round is forced to end (-1 = no finisher yet).
static func time_left(finish_times: Array, course_time: float) -> float:
	var first: float = first_finish(finish_times)
	if first < 0.0:
		return -1.0
	return maxf(first + ROUND_GRACE - course_time, 0.0)


## Who gets the KO for a fall / death at `now`: the last attacker if the hit was recent enough.
static func ko_credit(last_hit_by: int, last_hit_at: float, now: float) -> int:
	if last_hit_by == 0 or now - last_hit_at > KO_WINDOW or now < last_hit_at:
		return 0
	return last_hit_by


## Two teams as even as possible: ids in order, alternating (sizes differ by at most one).
static func balance_teams(ids: Array) -> Dictionary:
	var sorted: Array = ids.duplicate()
	sorted.sort()
	var out: Dictionary = {}
	for i: int in sorted.size():
		out[int(sorted[i])] = i % 2
	return out


## The team a newcomer joins: the smaller one (ties: team 0).
static func smaller_team(teams_now: Dictionary) -> int:
	var n: Array[int] = [0, 0]
	for id: Variant in teams_now:
		n[clampi(int(teams_now[id]), 0, 1)] += 1
	return 1 if n[1] < n[0] else 0


## One round's scoreboard rows, best total first.
## finish_order: ids that finished, in finishing order. all_ids: everyone in the round.
## kos / bonus: id -> count (KOs scored, checkpoints taken first).
static func score_round(finish_order: Array, all_ids: Array, kos: Dictionary, bonus: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: Variant in all_ids:
		var pid: int = int(id)
		var place: int = finish_order.find(pid) + 1
		var k: int = int(kos.get(pid, 0))
		var b: int = int(bonus.get(pid, 0))
		var pp: int = placement_points(place)
		rows.append({"id": pid, "place": place, "place_pts": pp, "kos": k, "ko_pts": k * KO_POINTS,
			"bonus": b, "bonus_pts": b * BONUS_POINTS, "total": pp + k * KO_POINTS + b * BONUS_POINTS})
	rows.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		if int(a["total"]) != int(c["total"]):
			return int(a["total"]) > int(c["total"])
		var pa: int = int(a["place"]) if int(a["place"]) > 0 else 99
		var pc: int = int(c["place"]) if int(c["place"]) > 0 else 99
		if pa != pc:
			return pa < pc
		return int(a["id"]) < int(c["id"]))
	return rows


## Per-team sums of `points` (id -> points): [team 0, team 1].
static func team_totals(points: Dictionary, team_of: Dictionary) -> Array[int]:
	var t: Array[int] = [0, 0]
	for id: Variant in points:
		if team_of.has(int(id)):
			t[clampi(int(team_of[int(id)]), 0, 1)] += int(points[id])
	return t


## Winning team of a points table: 0 / 1, or -1 for a tie.
static func winning_team(points: Dictionary, team_of: Dictionary) -> int:
	var t: Array[int] = team_totals(points, team_of)
	if t[0] == t[1]:
		return -1
	return 0 if t[0] > t[1] else 1


## Adds a scored round to the cup totals.
func add_round(rows: Array) -> void:
	for r: Variant in rows:
		var row: Dictionary = r
		var id: int = int(row["id"])
		cup[id] = int(cup.get(id, 0)) + int(row["total"])


## Cup standings: [[id, points], ...] best first (ties: lower id).
func cup_standings() -> Array:
	var out: Array = []
	for id: Variant in cup:
		out.append([int(id), int(cup[id])])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[1]) != int(b[1]):
			return int(a[1]) > int(b[1])
		return int(a[0]) < int(b[0]))
	return out


func round_points(rows: Array) -> Dictionary:
	var pts: Dictionary = {}
	for r: Variant in rows:
		pts[int((r as Dictionary)["id"])] = int((r as Dictionary)["total"])
	return pts


# ---- wire format (JSON-safe: int keys become [key, value] pairs) -----------------

func cup_to_wire() -> Array:
	var out: Array = []
	for id: Variant in cup:
		out.append([int(id), int(cup[id]), str(names.get(int(id), "")), int(teams.get(int(id), 0))])
	return out


func cup_from_wire(raw: Variant) -> void:
	cup.clear()
	if typeof(raw) != TYPE_ARRAY:
		return
	for e: Variant in raw:
		if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 2:
			var a: Array = e
			cup[int(a[0])] = int(a[1])
			if a.size() >= 3 and str(a[2]) != "":
				names[int(a[0])] = str(a[2])
			if a.size() >= 4:
				teams[int(a[0])] = int(a[3])


static func rows_from_wire(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for e: Variant in raw:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var row: Dictionary = {}
		for k: String in ["id", "place", "place_pts", "kos", "ko_pts", "bonus", "bonus_pts", "total"]:
			row[k] = int(d.get(k, 0))
		out.append(row)
	return out
