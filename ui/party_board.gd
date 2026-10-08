class_name PartyBoard
extends RefCounted
## Pure helpers behind the Party HUD (no nodes, no networking, so they are unit-tested directly):
## the live standings entries, team totals, round-end callouts (MVP, most KOs, comeback ...) and
## the screen-edge maths for the off-screen rival arrows.


## One entry per racer in race order (best first). `order` is Net.standings(); `roster` is
## Net.roster (name / color / cp / finished); kos + bonus are the round's live tallies; cup the
## cup totals before this round ends; team_of: id -> 0 / 1.
static func entries(order: Array, roster: Dictionary, kos: Dictionary, bonus: Dictionary,
		cup: Dictionary, team_of: Dictionary, my_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var place: int = 0
	for id_v: Variant in order:
		var id: int = int(id_v)
		if not roster.has(id):
			continue
		place += 1
		var e: Dictionary = roster[id]
		var k: int = int(kos.get(id, 0))
		var b: int = int(bonus.get(id, 0))
		out.append({"id": id, "name": str(e.get("name", "?")), "color": int(e.get("color", 0)), "place": place,
			"cp": int(e.get("cp", 0)), "finished": float(e.get("finished", -1.0)) >= 0.0,
			"fin_time": float(e.get("finished", -1.0)), "kos": k, "bonus": b, "pts": live_points(k, b),
			"cup": int(cup.get(id, 0)), "team": int(team_of.get(id, 0)), "you": id == my_id})
	return out


## Points a racer has banked this round before the placement points (KOs + first-through).
static func live_points(kos: int, bonus: int) -> int:
	return kos * PartyRules.ko_value() + bonus * PartyRules.BONUS_POINTS


## [team 0, team 1] sums of the entries' round points (live).
static func team_live(list: Array[Dictionary]) -> Array[int]:
	var t: Array[int] = [0, 0]
	for e: Dictionary in list:
		t[clampi(int(e["team"]), 0, 1)] += int(e["pts"])
	return t


## [team 0, team 1] sums of the entries' cup totals.
static func team_cup(list: Array[Dictionary]) -> Array[int]:
	var t: Array[int] = [0, 0]
	for e: Dictionary in list:
		t[clampi(int(e["team"]), 0, 1)] += int(e["cup"])
	return t


static func place_of(list: Array[Dictionary], id: int) -> int:
	for e: Dictionary in list:
		if int(e["id"]) == id:
			return int(e["place"])
	return 0


static func suffix(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return "th"
	match n % 10:
		1:
			return "st"
		2:
			return "nd"
		3:
			return "rd"
	return "th"


## Round-end callouts: [{key, title, id, detail}], best story first. `rows` are the scored rows
## (PartyRules.score_round), `cup_after` the cup totals including this round. A comeback needs
## a previous round (`has_prev`): the racer who climbed the most places in the cup table.
static func callouts(rows: Array, cup_after: Dictionary, has_prev: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if rows.is_empty():
		return out
	var best: Dictionary = rows[0]
	for r: Variant in rows:
		var row: Dictionary = r
		if int(row["total"]) > int(best["total"]) or (int(row["total"]) == int(best["total"]) and _place_key(row) < _place_key(best)):
			best = row
	out.append({"key": "mvp", "title": "Round MVP", "id": int(best["id"]), "detail": "%d points" % int(best["total"])})
	var ko_row: Dictionary = {}
	var bonus_row: Dictionary = {}
	for r: Variant in rows:
		var row: Dictionary = r
		if int(row["kos"]) > 0 and (ko_row.is_empty() or int(row["kos"]) > int(ko_row["kos"])):
			ko_row = row
		if int(row["bonus"]) > 0 and (bonus_row.is_empty() or int(row["bonus"]) > int(bonus_row["bonus"])):
			bonus_row = row
	if not ko_row.is_empty():
		out.append({"key": "kos", "title": "Most KOs", "id": int(ko_row["id"]),
			"detail": "%d KO%s" % [int(ko_row["kos"]), "" if int(ko_row["kos"]) == 1 else "s"]})
	if not bonus_row.is_empty():
		out.append({"key": "bonus", "title": "Checkpoint Hunter", "id": int(bonus_row["id"]),
			"detail": "first through %d" % int(bonus_row["bonus"])})
	if has_prev:
		var before: Dictionary = {}
		for r: Variant in rows:
			var row: Dictionary = r
			before[int(row["id"])] = int(cup_after.get(int(row["id"]), 0)) - int(row["total"])
		var climb_id: int = 0
		var climb: int = 0
		var now_rank: Dictionary = _ranks(cup_after)
		var was_rank: Dictionary = _ranks(before)
		for id: Variant in now_rank:
			var gain: int = int(was_rank.get(id, now_rank[id])) - int(now_rank[id])
			if gain > climb:
				climb = gain
				climb_id = int(id)
		if climb >= 1:
			out.append({"key": "comeback", "title": "Biggest Comeback", "id": climb_id,
				"detail": "up %d place%s to %d%s" % [climb, "" if climb == 1 else "s", int(now_rank[climb_id]), suffix(int(now_rank[climb_id]))]})
	return out


static func _place_key(row: Dictionary) -> int:
	return int(row["place"]) if int(row["place"]) > 0 else 99


## id -> 1-based rank in a points table (best first, ties: lower id).
static func _ranks(points: Dictionary) -> Dictionary:
	var ids: Array = points.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		if int(points[a]) != int(points[b]):
			return int(points[a]) > int(points[b])
		return int(a) < int(b))
	var out: Dictionary = {}
	for i: int in ids.size():
		out[int(ids[i])] = i + 1
	return out


## Where a rival's screen position sits relative to the screen edge, for an arrow.
## `behind`: the point is behind the camera. Returns {on_screen, pos (clamped inside the margin),
## angle (radians, pointing from the centre toward the rival)}.
static func edge_point(p: Vector2, behind: bool, size: Vector2, margin: float) -> Dictionary:
	var c: Vector2 = size * 0.5
	var d: Vector2 = p - c
	if behind:
		d = -d
		if d.length() < 1.0:
			d = Vector2(0, 1)
	var inner: Vector2 = c - Vector2(margin, margin)
	if not behind and absf(d.x) <= inner.x and absf(d.y) <= inner.y:
		return {"on_screen": true, "pos": p, "angle": d.angle()}
	var t: float = INF
	if absf(d.x) > 0.001:
		t = minf(t, inner.x / absf(d.x))
	if absf(d.y) > 0.001:
		t = minf(t, inner.y / absf(d.y))
	return {"on_screen": false, "pos": c + d * t, "angle": d.angle()}
