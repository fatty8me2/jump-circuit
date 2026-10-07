class_name PartyStandings
extends VBoxContainer
## The live standings strip (top right): a big "your place" readout that pops when it changes,
## team totals in Team Party, and one row per racer in race order (name, progress or FIN, the
## round points they hold). Fed PartyBoard entries by the PartyHud a few times a second.

const MAX_ROWS: int = 8

## Our place changed (old place, new place), after the first reading.
signal place_changed(old: int, now: int)

var place_label: Label
var suffix_label: Label
var of_label: Label
var delta_label: Label
var team_label: Label
var cup_label: Label
var rows: Array[Dictionary] = []
## Last shown place of each racer, to flash overtakes.
var _last_place: Dictionary = {}
var _my_place: int = 0
var _pop_tw: Tween
var _delta_tw: Tween
## Racer ids in the order the rows are shown (tests read this).
var shown_order: Array[int] = []


func _init() -> void:
	add_theme_constant_override("separation", 3)
	custom_minimum_size = Vector2(300, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head: HBoxContainer = UiKit.hbox(8)
	head.alignment = BoxContainer.ALIGNMENT_END
	add_child(head)
	delta_label = UiKit.shadowed(UiKit.label("", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT), 7)
	delta_label.modulate.a = 0.0
	head.add_child(delta_label)
	place_label = UiKit.shadowed(UiKit.label("-", 92, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT), 14)
	head.add_child(place_label)
	var side: VBoxContainer = UiKit.vbox(0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(side)
	suffix_label = UiKit.shadowed(UiKit.label("", 36, UiKit.GOLD), 9)
	side.add_child(suffix_label)
	of_label = UiKit.shadowed(UiKit.label("", 20, UiKit.SOFT), 6)
	side.add_child(of_label)
	team_label = UiKit.shadowed(UiKit.label("", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT), 6)
	team_label.visible = false
	add_child(team_label)
	cup_label = UiKit.shadowed(UiKit.label("", 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_RIGHT), 5)
	cup_label.visible = false
	add_child(cup_label)
	for i: int in MAX_ROWS:
		rows.append(_make_row())


func _make_row() -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.55)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	var h: HBoxContainer = UiKit.hbox(8)
	panel.add_child(h)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(6, 22)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(swatch)
	var pl: Label = UiKit.shadowed(UiKit.label("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), 4)
	pl.custom_minimum_size = Vector2(24, 0)
	h.add_child(pl)
	var nm: Label = UiKit.shadowed(UiKit.label("", 20), 4)
	nm.custom_minimum_size = Vector2(130, 0)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	h.add_child(nm)
	var st: Label = UiKit.shadowed(UiKit.label("", 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_RIGHT), 4)
	st.custom_minimum_size = Vector2(52, 0)
	h.add_child(st)
	var pts: Label = UiKit.shadowed(UiKit.label("", 20, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT), 4)
	pts.custom_minimum_size = Vector2(40, 0)
	h.add_child(pts)
	add_child(panel)
	panel.visible = false
	return {"panel": panel, "box": sb, "swatch": swatch, "place": pl, "name": nm, "status": st, "pts": pts}


## Shows `list` (PartyBoard.entries). total_cp: checkpoints + finish for the "3/9" progress.
## In team mode `team_round` / `team_cup` are the [blaze, tide] sums.
func update(list: Array[Dictionary], total_cp: int, is_team: bool, team_round: Array[int], team_cup: Array[int]) -> void:
	shown_order.clear()
	for i: int in MAX_ROWS:
		var r: Dictionary = rows[i]
		var panel: PanelContainer = r["panel"]
		if i >= list.size():
			panel.visible = false
			continue
		var e: Dictionary = list[i]
		shown_order.append(int(e["id"]))
		panel.visible = true
		var col: Color = _racer_color(e, is_team)
		(r["swatch"] as ColorRect).color = col
		(r["place"] as Label).text = str(int(e["place"]))
		var nm: Label = r["name"]
		nm.text = str(e["name"])
		nm.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.45))
		var st: Label = r["status"]
		if bool(e["finished"]):
			st.text = "FIN"
			st.add_theme_color_override("font_color", UiKit.TEAL)
		else:
			st.text = "%d/%d" % [int(e["cp"]), total_cp]
			st.add_theme_color_override("font_color", UiKit.SOFT)
		(r["pts"] as Label).text = ("+%d" % int(e["pts"])) if int(e["pts"]) > 0 else ""
		var sb: StyleBoxFlat = r["box"]
		var you: bool = bool(e["you"])
		sb.bg_color = Color(0.32, 0.26, 0.08, 0.85) if you else Color(0.05, 0.07, 0.12, 0.55)
		sb.set_border_width_all(2 if you else 0)
		sb.border_color = UiKit.GOLD
		# somebody passed somebody: the row that gained flashes
		var was: int = int(_last_place.get(int(e["id"]), int(e["place"])))
		if was > int(e["place"]) and not you:
			_flash_row(panel)
		_last_place[int(e["id"])] = int(e["place"])
		if you:
			_set_my_place(int(e["place"]), list.size())
	team_label.visible = is_team
	cup_label.visible = is_team
	if is_team:
		team_label.text = "%s %d  :  %d %s" % [PartyNames.team_name(0), team_round[0], team_round[1], PartyNames.team_name(1)]
		team_label.add_theme_color_override("font_color", Color.WHITE)
		cup_label.text = "Cup  %d  :  %d" % [team_cup[0], team_cup[1]]


func _racer_color(e: Dictionary, is_team: bool) -> Color:
	if is_team:
		return PartyNames.team_color(int(e["team"]))
	return Settings.RACER_COLORS[int(e["color"]) % Settings.RACER_COLORS.size()]


func _flash_row(panel: Control) -> void:
	panel.modulate = Color(1.9, 1.9, 1.5)
	create_tween().tween_property(panel, "modulate", Color.WHITE, 0.5)


## The big readout: the number, its suffix and "of N". A change pops it and shows +n / -n.
func _set_my_place(place: int, count: int) -> void:
	if place == _my_place:
		return
	var old: int = _my_place
	_my_place = place
	place_label.text = str(place)
	suffix_label.text = PartyBoard.suffix(place).to_upper()
	of_label.text = "of %d" % count
	var col: Color = UiKit.GOLD if place == 1 else (Color(0.8, 0.88, 1.0) if place <= 3 else Color(1, 1, 1, 0.92))
	place_label.add_theme_color_override("font_color", col)
	suffix_label.add_theme_color_override("font_color", col)
	if old == 0:
		return
	place_changed.emit(old, place)
	var up: bool = place < old
	place_label.pivot_offset = place_label.size * 0.5
	place_label.scale = Vector2.ONE * (1.45 if up else 0.7)
	if _pop_tw != null and _pop_tw.is_valid():
		_pop_tw.kill()
	_pop_tw = create_tween()
	_pop_tw.tween_property(place_label, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	delta_label.text = ("+%d" if up else "-%d") % absi(old - place)
	delta_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if up else Color(1.0, 0.4, 0.35))
	delta_label.modulate.a = 1.0
	if _delta_tw != null and _delta_tw.is_valid():
		_delta_tw.kill()
	_delta_tw = create_tween()
	_delta_tw.tween_interval(1.2)
	_delta_tw.tween_property(delta_label, "modulate:a", 0.0, 0.5)


## Our current place as shown (0 until the first update).
func my_place() -> int:
	return _my_place
