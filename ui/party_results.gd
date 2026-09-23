class_name PartyResults
extends PanelContainer
## Party Mode results panels (shown by the PartyHud):
##  * a round: the round's points breakdown (finish place, KOs, first-through bonuses) and the
##    cumulative Party Cup standings - team totals in Team Party. The host picks the next
##    course and continues (or ends the cup back in the lobby); everyone else waits or leaves.
##  * a Party Practice clear: time, dummy hits, run again / next level / practice menu.
## Fully pad-navigable: starts focused on its main button, A confirms.

var party: PartyLayer
## The button focused first.
var first: Control
var _level_pick: OptionButton


func setup_round(p: PartyLayer, rows: Array[Dictionary]) -> void:
	party = p
	custom_minimum_size = Vector2(760, 0)
	var box: VBoxContainer = UiKit.vbox(8)
	add_child(box)
	var rules: PartyRules = p.rules
	box.add_child(UiKit.label("%s  -  ROUND %d" % [PartyNames.CUP.to_upper(), rules.round_no], 20, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("Round Results", 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(str(Game.level_info()["name"]), 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	for h: String in ["Place", "Racer", "Finish", "KOs", "Bonus", "Round"]:
		grid.add_child(UiKit.label(h, 15, UiKit.SOFT))
	var fs: int = 20 if rows.size() <= 4 else 18
	for r: Dictionary in rows:
		var id: int = int(r["id"])
		var col: Color = p.team_color_of(id).lerp(Color.WHITE, 0.3)
		var place: int = int(r["place"])
		grid.add_child(UiKit.label("%d%s" % [place, Hud._ordinal(place)] if place > 0 else "DNF", fs, UiKit.GOLD if place == 1 else Color.WHITE))
		var nm: String = p.racer_name(id) + ("  (you)" if id == Net.my_id() else "")
		grid.add_child(UiKit.label(nm, fs, col))
		grid.add_child(UiKit.label("+%d" % int(r["place_pts"]), fs))
		grid.add_child(UiKit.label("%d  (+%d)" % [int(r["kos"]), int(r["ko_pts"])], fs))
		grid.add_child(UiKit.label("%d  (+%d)" % [int(r["bonus"]), int(r["bonus_pts"])], fs))
		grid.add_child(UiKit.label("%d" % int(r["total"]), fs + 2, UiKit.GOLD))
	var gc := CenterContainer.new()
	gc.add_child(grid)
	box.add_child(gc)
	var team_of: Dictionary = rules.teams.duplicate()
	if rules.is_team():
		var round_pts: Dictionary = rules.round_points(rows)
		var rt: Array[int] = PartyRules.team_totals(round_pts, team_of)
		var win: int = PartyRules.winning_team(round_pts, team_of)
		box.add_child(_team_line(rt, 26))
		box.add_child(UiKit.label("Round drawn!" if win < 0 else "Team %s takes the round!" % PartyNames.team_name(win), 22,
			Color.WHITE if win < 0 else PartyNames.team_color(win), HORIZONTAL_ALIGNMENT_CENTER))
	# cup standings
	box.add_child(UiKit.label("%s STANDINGS" % PartyNames.CUP.to_upper(), 17, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	if rules.is_team():
		box.add_child(_team_line(PartyRules.team_totals(rules.cup, team_of), 30))
	var stand: Array = rules.cup_standings()
	# two columns once there are more than four racers, so a full lobby of 8 still fits
	var sgrid := GridContainer.new()
	sgrid.columns = 2 if stand.size() > 4 else 1
	sgrid.add_theme_constant_override("h_separation", 48)
	sgrid.add_theme_constant_override("v_separation", 2)
	var n: int = 0
	for e: Variant in stand:
		n += 1
		var sid: int = int((e as Array)[0])
		var line: String = "%d.  %s   %d" % [n, p.racer_name(sid), int((e as Array)[1])]
		sgrid.add_child(UiKit.label(line, 19, p.team_color_of(sid).lerp(Color.WHITE, 0.35), HORIZONTAL_ALIGNMENT_CENTER))
	var sc := CenterContainer.new()
	sc.add_child(sgrid)
	box.add_child(sc)
	# controls
	if Net.is_host():
		_level_pick = OptionButton.new()
		_level_pick.custom_minimum_size = Vector2(0, 46)
		for info: Dictionary in Game.LEVELS:
			_level_pick.add_item("Next course:  %s" % str(info["name"]))
		_level_pick.selected = (Game.level_index + 1) % Game.LEVELS.size()
		var next: Button = UiKit.button("Next Round  (Round %d)" % (rules.round_no + 1), func() -> void:
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
	_focus_soon()


func _team_line(t: Array[int], size: int) -> Control:
	var h: HBoxContainer = UiKit.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UiKit.label("%s  %d" % [PartyNames.team_name(0), t[0]], size, PartyNames.team_color(0)))
	h.add_child(UiKit.label(":", size, Color.WHITE))
	h.add_child(UiKit.label("%d  %s" % [t[1], PartyNames.team_name(1)], size, PartyNames.team_color(1)))
	return h


func setup_practice(p: PartyLayer, time: float) -> void:
	party = p
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
