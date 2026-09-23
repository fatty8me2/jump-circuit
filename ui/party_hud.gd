class_name PartyHud
extends CanvasLayer
## Party Mode overlay, on top of the level HUD: the item slot (icon, name, button prompt),
## the active power-up's timer / charge meter, Shove readiness, round banner and the
## end-of-round countdown, this round's KO / bonus tally (team totals in Team Party), a
## kill feed, big announcements, and a host for the results panels.

var party: PartyLayer

var _root: Control
var _slot_icon: PartyIcon
var _slot_name: Label
var _slot_hint: Label
var _shove: Label
var _power_box: VBoxContainer
var _power_name: Label
var _power_bar: ColorRect
var _power_fill: ColorRect
var _power_status: Label
var _charge_bar: ColorRect
var _charge_fill: ColorRect
var _round: Label
var _count: Label
var _score: Label
var _feed: VBoxContainer
var _announce: Label
var _announce_tw: Tween
var _panel_host: Control
var _hint: Label
var _last_count: int = -1
var _finish_bar: PanelContainer


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	# item slot, top left under the stage / falls line (the bottom left belongs to the level intro)
	var slot: PanelContainer = UiKit.panel()
	slot.set_anchors_preset(Control.PRESET_TOP_LEFT)
	slot.position = Vector2(24, 86)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = UiKit.hbox(12)
	slot.add_child(row)
	_slot_icon = PartyIcon.new()
	row.add_child(_slot_icon)
	var col: VBoxContainer = UiKit.vbox(2)
	row.add_child(col)
	_slot_name = UiKit.label("", 22, Color.WHITE)
	col.add_child(_slot_name)
	_slot_hint = UiKit.label("", 16, UiKit.SOFT)
	col.add_child(_slot_hint)
	_shove = UiKit.label("", 15, UiKit.TEAL)
	col.add_child(_shove)
	_root.add_child(slot)

	# active power-up, bottom centre
	_power_box = UiKit.vbox(4)
	_power_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_power_box.position = Vector2(-200, -150)
	_power_box.custom_minimum_size = Vector2(400, 0)
	_power_box.visible = false
	_root.add_child(_power_box)
	_power_name = UiKit.shadowed(UiKit.label("", 24, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER), 6)
	_power_box.add_child(_power_name)
	var bars: Array = _bar(Color(1, 1, 1, 0.18), UiKit.GOLD, 10)
	_power_bar = bars[0]
	_power_fill = bars[1]
	_power_box.add_child(_power_bar)
	_power_status = UiKit.shadowed(UiKit.label("", 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER), 5)
	_power_box.add_child(_power_status)
	var cbars: Array = _bar(Color(1, 1, 1, 0.12), Color(0.7, 0.4, 1.0), 14)
	_charge_bar = cbars[0]
	_charge_fill = cbars[1]
	_power_box.add_child(_charge_bar)

	_round = UiKit.shadowed(UiKit.label("", 22, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER), 6)
	_round.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round.position = Vector2(-300, 52)
	_round.custom_minimum_size = Vector2(600, 0)
	_root.add_child(_round)
	_count = UiKit.shadowed(UiKit.label("", 30, Color(1.0, 0.55, 0.45), HORIZONTAL_ALIGNMENT_CENTER), 7)
	_count.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_count.position = Vector2(-300, 48)
	_count.custom_minimum_size = Vector2(600, 0)
	_root.add_child(_count)

	_score = UiKit.shadowed(UiKit.label("", 19, Color(1, 1, 1, 0.9)), 5)
	_score.position = Vector2(24, 50)
	_root.add_child(_score)

	_feed = UiKit.vbox(2)
	_feed.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position = Vector2(-24, 0)
	_feed.custom_minimum_size = Vector2(380, 0)
	_root.add_child(_feed)

	_announce = UiKit.shadowed(UiKit.label("", 46, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER), 10)
	_announce.set_anchors_preset(Control.PRESET_CENTER)
	_announce.position = Vector2(-400, -150)
	_announce.custom_minimum_size = Vector2(800, 0)
	_announce.modulate.a = 0.0
	_root.add_child(_announce)

	_hint = UiKit.shadowed(UiKit.label("", 17, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER), 5)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-400, -42)
	_hint.custom_minimum_size = Vector2(800, 0)
	_root.add_child(_hint)

	_panel_host = Control.new()
	_panel_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel_host)

	if party != null and party.rules != null:
		var mode_name: String = PartyNames.mode_name(party.rules.mode)
		if party.practice:
			_round.text = mode_name.to_upper()
			_hint.text = "Every ? box gives the next power-up. Practice dummies wait on the checkpoint lawns."
			_fade_later(_hint, 9.0)
		else:
			_round.text = "ROUND %d  -  %s  -  %s" % [party.rules.round_no, mode_name.to_upper(), PartyNames.CUP.to_upper()]
		_fade_later(_round, 6.0, 0.55)


func _bar(bg: Color, fg: Color, h: float) -> Array:
	var back := ColorRect.new()
	back.color = bg
	back.custom_minimum_size = Vector2(400, h)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = fg
	fill.size = Vector2(400, h)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return [back, fill]


func _fade_later(c: CanvasItem, after: float, to_alpha: float = 0.0) -> void:
	var tw: Tween = create_tween()
	tw.tween_interval(after)
	tw.tween_property(c, "modulate:a", to_alpha, 1.0)


func _process(_dt: float) -> void:
	if party == null:
		return
	var pad: bool = Game.using_pad
	# item slot
	_slot_icon.item_id = party.item
	if party.item != "":
		_slot_name.text = PartyNames.item_name(party.item)
		_slot_name.add_theme_color_override("font_color", PartyNames.item_color(party.item).lightened(0.3))
		_slot_hint.text = "%s  use" % Game.prompt("use_item")
	else:
		_slot_name.text = "No item"
		_slot_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		_slot_hint.text = "Grab a ? box"
	var pw: PowerUp = party.transformation()
	var shove_key: String = Game.prompt("shove")
	if pw == null:
		shove_key += " / " + Game.prompt("attack")
	_shove.text = ("%s  %s" % [shove_key, PartyNames.move_name("shove")]) if party.shove_cd <= 0.0 else "%s  ..." % PartyNames.move_name("shove")
	_shove.modulate.a = 1.0 if party.shove_cd <= 0.0 else 0.45
	# active power-up (the transformation first, else the latest gadget)
	var show: PowerUp = pw
	if show == null:
		for a: PowerUp in party.actives:
			if not a.ended:
				show = a
	_power_box.visible = show != null
	if show != null:
		_power_name.text = PartyNames.item_name(show.item_id).to_upper()
		_power_name.add_theme_color_override("font_color", PartyNames.item_color(show.item_id).lightened(0.25))
		var frac: float = clampf(show.time_left / maxf(show.duration, 0.01), 0.0, 1.0)
		_power_fill.size.x = 400.0 * frac
		_power_fill.color = PartyNames.item_color(show.item_id).lerp(Color(1, 0.3, 0.3), 1.0 - frac if frac < 0.3 else 0.0)
		var status: String = show.hud_status()
		if show.takes_attack and status == "":
			status = "%s attack" % Game.prompt("attack")
		_power_status.text = status
		var ch: float = show.charge_frac()
		_charge_bar.visible = ch >= 0.0
		_charge_fill.size.x = 400.0 * maxf(ch, 0.0)
		_charge_fill.color = Color(0.7, 0.4, 1.0).lerp(Color(1.0, 0.95, 0.6), ch)
	# score line
	if not party.practice:
		var me: int = Net.my_id()
		var line: String = "KOs %d    Bonus %d" % [int(party.kos.get(me, 0)), int(party.bonus.get(me, 0))]
		if party.rules.is_team():
			var tot: Array[int] = PartyRules.team_totals(party.rules.cup, _cup_teams())
			line = "%s  -  %s %d  :  %d %s" % [line, PartyNames.team_name(0), tot[0], tot[1], PartyNames.team_name(1)]
		elif party.rules.cup.has(me):
			line += "    Cup %d" % int(party.rules.cup[me])
		_score.text = line
		# end-of-round countdown
		var left: float = PartyRules.time_left(party.finish_times(), Game.course_time)
		if left >= 0.0 and not party.round_over:
			var n: int = int(ceil(left))
			_count.text = "Round ends in %d" % n
			_count.visible = true
			_round.visible = false   # the countdown takes the round banner's place
			if n != _last_count and n <= 10:
				Sfx.play("tick", 0.0, 0.6)
			_last_count = n
		else:
			_count.visible = false
	else:
		_score.text = ""
		_count.visible = false
	if pad != Game.using_pad:
		pass


func _cup_teams() -> Dictionary:
	var t: Dictionary = party.rules.teams.duplicate()
	for id: Variant in Net.teams:
		t[int(id)] = int(Net.teams[id])
	return t


## Big centre call-out ("NINE-TAILED FOX!", "KO! +3").
func announce(text: String, color: Color = UiKit.GOLD) -> void:
	_announce.text = text
	_announce.add_theme_color_override("font_color", color)
	if _announce_tw != null and _announce_tw.is_valid():
		_announce_tw.kill()
	_announce.pivot_offset = _announce.size * 0.5
	_announce.scale = Vector2.ONE * 1.5
	_announce.modulate.a = 0.0
	_announce_tw = create_tween()
	_announce_tw.tween_property(_announce, "modulate:a", 1.0, 0.1)
	_announce_tw.parallel().tween_property(_announce, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tw.tween_interval(1.1)
	_announce_tw.tween_property(_announce, "modulate:a", 0.0, 0.4)


## The slot filled: the icon pops.
func item_rolled(id: String) -> void:
	_slot_icon.pivot_offset = _slot_icon.size * 0.5
	_slot_icon.scale = Vector2.ONE * 1.6
	create_tween().tween_property(_slot_icon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if party != null and party.practice:
		_hint.text = "%s  -  %s" % [PartyNames.item_name(id), PartyNames.item_desc(id)]
		_hint.modulate.a = 1.0
		_fade_later(_hint, 5.0)


## Kill feed line (fades after a few seconds; newest at the bottom, 5 kept).
func feed(text: String, color: Color = UiKit.SOFT) -> void:
	var l: Label = UiKit.shadowed(UiKit.label(text, 19, color.lerp(Color.WHITE, 0.25), HORIZONTAL_ALIGNMENT_RIGHT), 5)
	_feed.add_child(l)
	while _feed.get_child_count() > 5:
		var old: Node = _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tw: Tween = l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func show_round_over() -> void:
	_count.visible = false
	hide_finished()
	announce("ROUND OVER", Color.WHITE)


## We finished but the round runs on: a small bottom bar ("Finished 2nd - waiting for the
## others") with a Spectate button (focused, for the pad) when the level can follow a rival.
func show_finished(place: int, can_spectate: bool, on_spectate: Callable) -> void:
	hide_finished()
	_finish_bar = UiKit.panel()
	_finish_bar.name = "FinishBar"
	_finish_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_finish_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_finish_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_finish_bar.position.y -= 190.0
	var row: HBoxContainer = UiKit.hbox(16)
	_finish_bar.add_child(row)
	var what: String = "Finished %d%s" % [place, Hud._ordinal(place)] if place > 0 else "Finished"
	row.add_child(UiKit.label("%s - waiting for the others" % what, 20, UiKit.GOLD))
	if can_spectate:
		var b: Button = UiKit.button("Spectate", func() -> void: on_spectate.call(), 180)
		b.name = "Spectate"
		row.add_child(b)
		b.grab_focus.call_deferred()
	_root.add_child(_finish_bar)


## While spectating the waiting bar steps aside (the spectate bar shows the controls);
## back from watching, it returns with Spectate focused again.
func on_spectating(on: bool) -> void:
	if _finish_bar == null or not is_instance_valid(_finish_bar):
		return
	_finish_bar.visible = not on
	if not on:
		UiKit.focus_first(_finish_bar)


func hide_finished() -> void:
	if _finish_bar != null and is_instance_valid(_finish_bar):
		_finish_bar.queue_free()
	_finish_bar = null


## A results panel (centred, dimmed background, takes mouse + pad input).
func add_panel(panel: Control) -> void:
	for c: Node in _panel_host.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_host.add_child(dim)
	var centre: CenterContainer = UiKit.centered(panel)
	_panel_host.add_child(centre)
	_panel_host.modulate.a = 0.0
	create_tween().tween_property(_panel_host, "modulate:a", 1.0, 0.3)


func has_panel() -> bool:
	return _panel_host.get_child_count() > 0


## Results panels: nothing focused (a stray mouse click) -> the first pad / arrow press
## finds the panel's first button again.
func _unhandled_input(event: InputEvent) -> void:
	if has_panel() and Game.is_menu_nav(event) and get_viewport().gui_get_focus_owner() == null:
		UiKit.focus_first(_panel_host)
		get_viewport().set_input_as_handled()
