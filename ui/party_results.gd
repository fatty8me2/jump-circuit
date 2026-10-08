class_name PartyResults
extends PanelContainer
## Party Mode results panels (shown by the PartyHud):
##  * a round: this round's points counting up racer by racer (finish place, KOs, first-through
##    bonuses), the Party Cup standings with a per-round breakdown (team totals in Team Party), and
##    MVP callouts (round MVP, most KOs, checkpoint hunter, biggest comeback). The host picks the
##    next course and continues (or ends the cup back in the lobby); everyone else waits or leaves.
##  * a Party Practice clear: time, dummy hits, run again / next level / practice menu.
## Fully pad-navigable: starts focused on its main button, A confirms; D-pad / B / a click also
## skips the counting animation.

const ROW_STEP: float = 0.22
const COUNT_TIME: float = 0.7

## Cup history this session: round number -> {racer id -> that round's points}. Reset on round 1.
static var history: Dictionary = {}

var party: PartyLayer
## The button focused first.
var first: Control
## True once the tallies finished counting (or were skipped).
var done: bool = false
## The callouts of the round: [{key, title, id, detail}].
var callout_list: Array[Dictionary] = []
var _level_pick: OptionButton
## A game type adds its own column (Hill / Coins / Bomb / Out) to the round table.
var _mode_col: bool = false
## The last round of a finite cup: the buttons lead to the podium instead of another round.
var final_round: bool = false
var _t: float = 0.0
var _tally: Array[Dictionary] = []
var _cup: Array[Dictionary] = []
var _chips: Array[Control] = []
var _cup_at: float = 0.0
var _chips_at: float = 0.0
var _end_at: float = 0.0
var _chips_up: int = 0
var _last_sum: int = -1
var _tick_cool: float = 0.0


func setup_round(p: PartyLayer, rows: Array[Dictionary]) -> void:
	party = p
	var rules: PartyRules = p.rules
	_record_history(rules, rows)
	var n: int = rows.size()
	custom_minimum_size = Vector2(1180 if n > 4 else 860, 0)
	var box: VBoxContainer = UiKit.vbox(8)
	add_child(box)
	_mode_col = p.mode != null
	final_round = PartyRuleset.cup_done(rules.round_no)
	var cup_n: int = PartyRuleset.cup_rounds()
	box.add_child(UiKit.label("%s  -  ROUND %d%s" % [PartyNames.CUP.to_upper(), rules.round_no, (" OF %d" % cup_n) if cup_n > 0 else ""], 20, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("Final Round Results" if final_round else "Round Results", 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var sub: String = str(Game.level_info()["name"])
	if p.mode != null:
		sub += "   -   " + PartyNames.variant_name(p.mode.id)
	box.add_child(UiKit.label(sub, 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	if p.last_note != "":
		box.add_child(UiKit.label(p.last_note, 20, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var team_of: Dictionary = rules.teams.duplicate()
	if rules.is_team():
		var round_pts: Dictionary = rules.round_points(rows)
		var rt: Array[int] = PartyRules.team_totals(round_pts, team_of)
		var win: int = PartyRules.winning_team(round_pts, team_of)
		box.add_child(_team_line(rt, 28))
		box.add_child(UiKit.label("Round drawn!" if win < 0 else "Team %s takes the round!" % PartyNames.team_name(win), 22,
			Color.WHITE if win < 0 else PartyNames.team_color(win), HORIZONTAL_ALIGNMENT_CENTER))
	var cols: HBoxContainer = UiKit.hbox(36)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cols)
	cols.add_child(_round_table(rows))
	cols.add_child(_cup_table(rules, rows, team_of))
	# callouts
	var has_prev: bool = history.size() > 1
	callout_list = PartyBoard.callouts(rows, rules.cup, has_prev)
	var crow: HBoxContainer = UiKit.hbox(14)
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	for c: Dictionary in callout_list:
		var chip: Control = _chip(c)
		chip.modulate.a = 0.0
		crow.add_child(chip)
		_chips.append(chip)
	box.add_child(crow)
	_cup_at = 0.3 + ROW_STEP * float(rows.size()) + COUNT_TIME * 0.6
	_chips_at = _cup_at + 0.1 * float(_cup.size()) + COUNT_TIME
	_end_at = _chips_at + 0.4 * float(_chips.size())
	# controls
	if final_round:
		var crown: Button = UiKit.button("See the Champion!", func() -> void: party.show_podium(), 420)
		crown.name = "CrownChampion"
		box.add_child(crown)
		first = crown
		if Net.is_host():
			box.add_child(UiKit.button("End Cup - Back to Lobby", func() -> void:
				Net.host_reset_cup()
				Net.host_return_to_lobby(), 420))
		box.add_child(UiKit.confirm_button("Close Session" if Net.is_host() else "Leave Party", "Press again to disconnect" if Net.is_host() else "Press again to leave", func() -> void:
			Net.leave()
			Game.goto_title("main"), 420))
	elif Net.is_host():
		_level_pick = OptionButton.new()
		_level_pick.custom_minimum_size = Vector2(0, 46)
		for info: Dictionary in Game.LEVELS:
			_level_pick.add_item("Next course:  %s" % str(info["name"]))
		_level_pick.selected = (Game.level_index + 1) % Game.LEVELS.size()
		var next: Button = UiKit.button("Next Round  (Round %d%s)" % [rules.round_no + 1, (" of %d" % cup_n) if cup_n > 0 else ""], func() -> void:
			Net.host_start_race(_level_pick.selected), 330)
		# two rows of two, so a full lobby's results still fit on screen
		var row1: HBoxContainer = UiKit.hbox(12)
		row1.alignment = BoxContainer.ALIGNMENT_CENTER
		row1.add_child(next)
		_level_pick.custom_minimum_size.x = 360
		row1.add_child(_level_pick)
		box.add_child(row1)
		var row2: HBoxContainer = UiKit.hbox(12)
		row2.alignment = BoxContainer.ALIGNMENT_CENTER
		row2.add_child(UiKit.button("End Cup - Back to Lobby", func() -> void: Net.host_return_to_lobby(), 330))
		row2.add_child(UiKit.confirm_button("Close Session", "Press again to disconnect all", func() -> void:
			Net.leave()
			Game.goto_title("main"), 360))
		box.add_child(row2)
		first = next
	else:
		box.add_child(UiKit.label("Waiting for the host to pick the next round...", 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
		var leave: Button = UiKit.confirm_button("Leave Party", "Press again to leave", func() -> void:
			Net.leave()
			Game.goto_title("main"), 520)
		box.add_child(leave)
		first = leave
	_update_anim(0.0)
	_focus_soon()


## Remembers this round's points for the per-round breakdown (round 1 starts a fresh cup).
func _record_history(rules: PartyRules, rows: Array[Dictionary]) -> void:
	if rules.round_no <= 1:
		history.clear()
	for r: Variant in history.keys():
		if int(r) > rules.round_no:
			history.erase(r)
	var pts: Dictionary = {}
	for row: Dictionary in rows:
		pts[int(row["id"])] = int(row["total"])
	history[rules.round_no] = pts


func _cell(text: String, size: int, color: Color = Color.WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, min_w: float = 0.0) -> Label:
	var l: Label = UiKit.label(text, size, color, align)
	if min_w > 0.0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l


## This round: a row per racer; the points count up one racer after another.
func _round_table(rows: Array[Dictionary]) -> Control:
	var col: VBoxContainer = UiKit.vbox(4)
	col.add_child(UiKit.label("THIS ROUND", 17, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 7 if _mode_col else 6
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	var heads: Array = [["Place", 56.0], ["Racer", 170.0], ["Finish", 64.0], ["KOs", 92.0], ["Bonus", 92.0], ["Round", 64.0]]
	if _mode_col:
		heads.insert(5, [party.mode.points_label(), 70.0])
	for h: Array in heads:
		grid.add_child(_cell(str(h[0]), 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_LEFT, float(h[1])))
	var fs: int = 21 if rows.size() <= 4 else 19
	var i: int = 0
	for r: Dictionary in rows:
		var id: int = int(r["id"])
		var c: Color = party.team_color_of(id).lerp(Color.WHITE, 0.3)
		var place: int = int(r["place"])
		var cells: Array[Label] = []
		cells.append(_cell("%d%s" % [place, Hud._ordinal(place)] if place > 0 else "DNF", fs, UiKit.GOLD if place == 1 else Color.WHITE))
		cells.append(_cell(party.racer_name(id) + ("  (you)" if id == Net.my_id() else ""), fs, c))
		cells.append(_cell("", fs))
		cells.append(_cell("", fs))
		cells.append(_cell("", fs))
		if _mode_col:
			cells.append(_cell("", fs))
		cells.append(_cell("", fs + 2, UiKit.GOLD))
		for cl: Label in cells:
			grid.add_child(cl)
		_tally.append({"cells": cells, "start": 0.3 + ROW_STEP * float(i), "place_pts": int(r["place_pts"]), "kos": int(r["kos"]),
			"ko_pts": int(r["ko_pts"]), "bonus": int(r["bonus"]), "bonus_pts": int(r["bonus_pts"]), "mode_pts": int(r.get("mode_pts", 0)),
			"total": int(r["total"])})
		i += 1
	col.add_child(grid)
	return col


## The cup: totals (counting up from before this round) with each round's points beside them.
func _cup_table(rules: PartyRules, rows: Array[Dictionary], team_of: Dictionary) -> Control:
	var col: VBoxContainer = UiKit.vbox(4)
	col.add_child(UiKit.label("%s STANDINGS" % PartyNames.CUP.to_upper(), 17, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	if rules.is_team():
		col.add_child(_team_line(PartyRules.team_totals(rules.cup, team_of), 26))
	var round_ids: Array = history.keys()
	round_ids.sort()
	if round_ids.size() > 5:
		round_ids = round_ids.slice(round_ids.size() - 5)
	var grid := GridContainer.new()
	grid.columns = 3 + round_ids.size() + 1
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	grid.add_child(_cell("#", 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_LEFT, 28.0))
	grid.add_child(_cell("Racer", 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_LEFT, 150.0))
	for rn: Variant in round_ids:
		grid.add_child(_cell("R%d" % int(rn), 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_RIGHT, 36.0))
	grid.add_child(_cell("Total", 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_RIGHT, 56.0))
	grid.add_child(_cell("", 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_RIGHT, 48.0))
	var round_total: Dictionary = {}
	for row: Dictionary in rows:
		round_total[int(row["id"])] = int(row["total"])
	var fs: int = 21 if rules.cup.size() <= 4 else 19
	var rank: int = 0
	for e: Variant in rules.cup_standings():
		rank += 1
		var id: int = int((e as Array)[0])
		var total: int = int((e as Array)[1])
		var gain: int = int(round_total.get(id, 0))
		var cells: Array[Label] = []
		cells.append(_cell(str(rank), fs, UiKit.GOLD if rank == 1 else Color.WHITE))
		cells.append(_cell(party.racer_name(id), fs, party.team_color_of(id).lerp(Color.WHITE, 0.35)))
		for rn: Variant in round_ids:
			var v: Variant = (history[rn] as Dictionary).get(id, null)
			cells.append(_cell("-" if v == null else str(int(v)), fs - 3, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT))
		cells.append(_cell("", fs + 2, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT))
		cells.append(_cell("", fs - 2, Color(0.5, 1.0, 0.6), HORIZONTAL_ALIGNMENT_RIGHT))
		for cl: Label in cells:
			grid.add_child(cl)
		_cup.append({"cells": cells, "total": total, "gain": gain, "start": 0.0, "n": round_ids.size()})
	for i: int in _cup.size():
		_cup[i]["start"] = 0.3 + ROW_STEP * float(rows.size()) + COUNT_TIME * 0.6 + 0.1 * float(i)
	col.add_child(grid)
	return col


func _chip(c: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.12, 0.05, 0.9) if str(c["key"]) == "mvp" else Color(0.1, 0.13, 0.2, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = UiKit.GOLD if str(c["key"]) == "mvp" else UiKit.TEAL
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	var v: VBoxContainer = UiKit.vbox(0)
	panel.add_child(v)
	v.add_child(UiKit.label(str(c["title"]).to_upper(), 16, UiKit.GOLD if str(c["key"]) == "mvp" else UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	var id: int = int(c["id"])
	v.add_child(UiKit.label(party.racer_name(id), 24, party.team_color_of(id).lerp(Color.WHITE, 0.3), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(str(c["detail"]), 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	return panel


func _team_line(t: Array[int], size: int) -> Control:
	var h: HBoxContainer = UiKit.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UiKit.label("%s  %d" % [PartyNames.team_name(0), t[0]], size, PartyNames.team_color(0)))
	h.add_child(UiKit.label(":", size, Color.WHITE))
	h.add_child(UiKit.label("%d  %s" % [t[1], PartyNames.team_name(1)], size, PartyNames.team_color(1)))
	return h


# ---- the counting animation ----------------------------------------------------------------------

func _process(dt: float) -> void:
	if done:
		return
	_t += dt
	_tick_cool -= dt
	_update_anim(dt)


## Any nav press (D-pad, B, a click) jumps the animation to its end; the press still navigates.
func _input(event: InputEvent) -> void:
	if done or _t < 0.3:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
			or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		skip()


func skip() -> void:
	_t = _end_at + 1.0
	_update_anim(0.0)


static func _ease(f: float) -> float:
	return 1.0 - pow(1.0 - clampf(f, 0.0, 1.0), 3.0)


func _update_anim(_dt: float) -> void:
	var sum: int = 0
	for r: Dictionary in _tally:
		var raw: float = (_t - float(r["start"])) / COUNT_TIME
		var f: float = _ease(raw)
		var cells: Array[Label] = r["cells"]
		var a: float = clampf((_t - float(r["start"])) / 0.15, 0.0, 1.0)
		for c: Label in cells:
			c.modulate.a = a
		var pp: int = roundi(float(r["place_pts"]) * f)
		var kp: int = roundi(float(r["ko_pts"]) * f)
		var bp: int = roundi(float(r["bonus_pts"]) * f)
		var mp: int = roundi(float(r["mode_pts"]) * f)
		cells[2].text = "+%d" % pp
		cells[3].text = "%d  (+%d)" % [int(r["kos"]), kp]
		cells[4].text = "%d  (+%d)" % [int(r["bonus"]), bp]
		if _mode_col:
			cells[5].text = "%+d" % mp
			cells[6].text = "%d" % maxi(pp + kp + bp + mp, 0)
		else:
			cells[5].text = "%d" % (pp + kp + bp)
		sum += pp + kp + bp + mp
	for r: Dictionary in _cup:
		var f: float = _ease((_t - float(r["start"])) / COUNT_TIME)
		var cells: Array[Label] = r["cells"]
		var a: float = clampf((_t - float(r["start"]) + 0.3) / 0.2, 0.0, 1.0)
		for c: Label in cells:
			c.modulate.a = a
		var gain: int = int(r["gain"])
		var shown: int = int(r["total"]) - gain + roundi(float(gain) * f)
		var n: int = int(r["n"])
		cells[2 + n].text = str(shown)
		cells[3 + n].text = ("+%d" % roundi(float(gain) * f)) if gain > 0 else ""
		sum += roundi(float(gain) * f)
	if sum != _last_sum:
		if _last_sum >= 0 and _tick_cool <= 0.0 and not done and party != null and party.sfx != null:
			party.sfx.play("tally", 0.5, 0.9 + minf(float(sum) / 80.0, 0.7), 0.0)
			_tick_cool = 0.045
		_last_sum = sum
	for i: int in _chips.size():
		var chip: Control = _chips[i]
		if _t >= _chips_at + 0.4 * float(i) and i >= _chips_up:
			_chips_up = i + 1
			chip.pivot_offset = chip.size * 0.5
			chip.scale = Vector2.ONE * 1.5
			chip.modulate.a = 1.0
			create_tween().tween_property(chip, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if party != null and party.sfx != null and not _skipping():
				party.sfx.play("fanfare" if i == 0 else "chime", 0.7 if i == 0 else 0.5)
	if _t >= _end_at:
		done = true


func _skipping() -> bool:
	return _t > _end_at + 0.5


func setup_practice(p: PartyLayer, time: float) -> void:
	party = p
	done = true
	custom_minimum_size = Vector2(480, 0)
	var box: VBoxContainer = UiKit.vbox(12)
	add_child(box)
	box.add_child(UiKit.label("%s  -  COURSE CLEAR" % PartyNames.mode_name("practice").to_upper(), 20, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(str(Game.level_info()["name"]), 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(SaveData.format_time(time), 54, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var hits: int = 0
	for d: PracticeDummy in p.dummies:
		if is_instance_valid(d):
			hits += d.hits
	box.add_child(UiKit.label("Dummy hits: %d     (practice runs are not saved)" % hits, 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var again: Button = UiKit.button("Run It Again", func() -> void: Game.restart_level(), 420)
	box.add_child(again)
	box.add_child(UiKit.button("Next Course", func() -> void: Game.next_level(), 420))
	box.add_child(UiKit.button(PartyNames.mode_name("practice"), func() -> void: Game.goto_title("practice"), 420))
	box.add_child(UiKit.button("Title", func() -> void: Game.goto_title("main"), 420))
	first = again
	_focus_soon()


## Focus after a beat, so a jump / attack mashed into the finish can't press a button.
func _focus_soon() -> void:
	var buttons: Array[Node] = find_children("*", "BaseButton", true, false)
	for b: Node in buttons:
		(b as BaseButton).disabled = true
	if not is_inside_tree():
		await tree_entered
	await get_tree().create_timer(0.6, false).timeout
	for b: Node in buttons:
		if is_instance_valid(b):
			(b as BaseButton).disabled = false
	if is_instance_valid(first) and first.is_inside_tree():
		first.grab_focus()
