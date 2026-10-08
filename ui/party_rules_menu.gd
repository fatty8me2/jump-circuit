class_name PartyRulesMenu
extends RefCounted
## The host's Party Cup rules screens (title screens "partyrules" and "partyitems"), reached from the online
## lobby and from Party vs CPU. Every row is a plain button, so a pad needs nothing else: D-pad / stick move
## between rows, A (or D-pad left / right) changes the focused row, B backs out. Edits go through
## PartyRuleset.set_value: saved to Settings and (online) pushed to every guest with the next roster snapshot.

## The title screen Back / Done returns to ("lobby" or "partycpu").
static var back_to: String = "lobby"


## Rows for the screen: [label, values (display strings), current index, key, table].
static func _rows(online_host: bool) -> Array[Dictionary]:
	var rs: Dictionary = PartyRuleset.cur()
	var variants: Array = []
	for v: String in PartyRuleset.VARIANTS:
		variants.append(PartyNames.variant_name(v))
	var cups: Array = []
	for n: int in PartyRuleset.CUPS:
		cups.append(PartyRuleset.cup_label(n))
	var freqs: Array = []
	for f: String in PartyRuleset.FREQ:
		freqs.append(PartyRuleset.freq_label(f))
	var kos: Array = []
	for n: int in PartyRuleset.KO_VALUES:
		kos.append("%d point%s" % [n, "" if n == 1 else "s"])
	var times: Array = []
	for n: int in PartyRuleset.TIMES:
		times.append(PartyRuleset.time_label(n))
	var rows: Array[Dictionary] = [
		{"label": "Game type", "values": variants, "index": maxi(PartyRuleset.VARIANTS.find(str(rs["variant"])), 0), "key": "variant", "table": PartyRuleset.VARIANTS},
		{"label": "Cup length", "values": cups, "index": PartyRuleset.index_of_int(PartyRuleset.CUPS, int(rs["cup"])), "key": "cup", "table": PartyRuleset.CUPS},
		{"label": "Item boxes", "values": freqs, "index": maxi(PartyRuleset.FREQ.find(str(rs["freq"])), 0), "key": "freq", "table": PartyRuleset.FREQ},
	]
	rows.append({"label": "KO value", "values": kos, "index": PartyRuleset.index_of_int(PartyRuleset.KO_VALUES, int(rs["ko"])), "key": "ko", "table": PartyRuleset.KO_VALUES})
	rows.append({"label": "Round time limit", "values": times, "index": PartyRuleset.index_of_int(PartyRuleset.TIMES, int(rs["time"])), "key": "time", "table": PartyRuleset.TIMES})
	if online_host:
		var fills: Array = []
		for n: int in PartyRuleset.FILLS:
			fills.append(PartyRuleset.fill_label(n))
		rows.append({"label": "Fill with CPUs", "values": fills, "index": PartyRuleset.index_of_int(PartyRuleset.FILLS, int(rs["cpu"])), "key": "cpu", "table": PartyRuleset.FILLS})
	return rows


## The rules screen's content: {"content": Control, "focus": Control}. `title` is the title scene.
static func build_screen(title: Node) -> Dictionary:
	var box: VBoxContainer = UiKit.vbox(8)
	box.add_child(UiKit.label("CUP RULES", 36, Color.WHITE))
	var blurb: Label = UiKit.label("", 16, UiKit.SOFT)
	blurb.name = "VariantBlurb"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(500, 44)
	box.add_child(blurb)
	var first: Control = null
	var online_host: bool = Net.active and not Net.local_session and Net.is_host()
	for row: Dictionary in _rows(online_host):
		var table: Array = row["table"]
		var key: String = str(row["key"])
		var b: Button = CpuMenu.cycler(str(row["label"]), row["values"], int(row["index"]), func(i: int) -> void:
			PartyRuleset.set_value(key, table[i])
			if key == "variant":
				blurb.text = PartyNames.variant_blurb(str(table[i])), 460)
		b.name = "Rule_" + key
		box.add_child(b)
		if first == null:
			first = b
	blurb.text = PartyNames.variant_blurb(PartyRuleset.variant())
	var items: Button = UiKit.button(items_label(), func() -> void: title.call("show_screen", "partyitems"), 460)
	items.name = "ItemToggles"
	box.add_child(items)
	var done: Button = UiKit.button("Done", func() -> void: title.call("show_screen", back_to), 460)
	done.name = "RulesDone"
	box.add_child(done)
	var hint: Label = UiKit.label("A / click changes a row   D-pad left / right steps back   B back", 14, UiKit.SOFT)
	box.add_child(hint)
	var p: PanelContainer = UiKit.panel(Vector2(540, 0))
	p.add_child(box)
	return {"content": p, "focus": first}


static func items_label() -> String:
	var on: int = PartyRuleset.enabled_items().size()
	var all: int = PartyItems.ids().size()
	return "Power-ups:  %d of %d on  ..." % [on, all]


## The per-item toggles: one button per catalogue item (built from PartyItems, so new items appear by themselves).
static func build_items_screen(title: Node) -> Dictionary:
	var box: VBoxContainer = UiKit.vbox(8)
	box.add_child(UiKit.label("POWER-UPS", 36, Color.WHITE))
	var note: Label = UiKit.label("A switches a power-up on or off for the whole cup.", 16, UiKit.SOFT)
	box.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	var first: Control = null
	var buttons: Dictionary = {}
	for id: String in PartyItems.ids():
		var b: Button = UiKit.button(toggle_text(id), func() -> void:
			PartyRuleset.toggle_item(id)
			(buttons[id] as Button).text = toggle_text(id), 300)
		b.name = "Item_" + id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(b)
		buttons[id] = b
		if first == null:
			first = b
	box.add_child(grid)
	var row: HBoxContainer = UiKit.hbox(10)
	var all_on: Button = UiKit.button("All on", func() -> void:
		PartyRuleset.set_value("off", [])
		_refresh(buttons), 200)
	all_on.name = "ItemsAllOn"
	row.add_child(all_on)
	var all_off: Button = UiKit.button("All off", func() -> void:
		PartyRuleset.set_value("off", PartyItems.ids())
		_refresh(buttons), 200)
	all_off.name = "ItemsAllOff"
	row.add_child(all_off)
	box.add_child(row)
	var done: Button = UiKit.button("Done", func() -> void: title.call("show_screen", "partyrules"), 410)
	done.name = "ItemsDone"
	box.add_child(done)
	var p: PanelContainer = UiKit.panel(Vector2(660, 0))
	p.add_child(box)
	return {"content": p, "focus": first}


static func toggle_text(id: String) -> String:
	return "%s  %s" % ["[x]" if PartyRuleset.item_enabled(id) else "[  ]", PartyNames.item_name(id)]


static func _refresh(buttons: Dictionary) -> void:
	for id: Variant in buttons:
		(buttons[id] as Button).text = toggle_text(str(id))


## The lobby host's button into the rules (below the mode picker).
static func add_lobby_button(box: VBoxContainer, title: Node) -> void:
	var b: Button = UiKit.button("Cup & Rules  ...", func() -> void:
		back_to = "lobby"
		title.call("show_screen", "partyrules"), 520)
	b.name = "RulesButton"
	box.add_child(b)
