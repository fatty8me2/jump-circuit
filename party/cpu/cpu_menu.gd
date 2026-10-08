class_name CpuMenu
extends RefCounted
## The menus for CPU racers: the "Party vs CPU" setup screen (title screen id "partycpu") and the
## lobby's CPU options. Everything is a plain button, so a pad needs nothing else: D-pad / stick
## move between rows, A (or D-pad left / right) cycles the value on the focused row, B backs out.

const MODES: Array[String] = ["party", "team"]

static var mode_i: int = 0
static var diff_i: int = 1
static var course_i: int = 0
static var count_n: int = 3


## A row that shows "Label:  value" and cycles through `values` on A / click (D-pad left / right
## step back and forth). `on_change(index)` runs after each change.
static func cycler(label: String, values: Array, index: int, on_change: Callable, width: float = 440.0) -> Button:
	var state: Array[int] = [clampi(index, 0, maxi(values.size() - 1, 0))]
	var holder: Array[Button] = [null]   # (lambdas capture locals by value: the button goes in a box)
	var refresh := func() -> void:
		if is_instance_valid(holder[0]):
			holder[0].text = "%s:  %s" % [label, str(values[state[0]])]
	var step := func(d: int) -> void:
		state[0] = posmod(state[0] + d, values.size())
		refresh.call()
		on_change.call(state[0])
	var b: Button = UiKit.button("", func() -> void: step.call(1), width)
	holder[0] = b
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev.is_action_pressed("ui_left"):
			step.call(-1)
			Sfx.play("ui", 0.05, 0.8)
			b.accept_event()
		elif ev.is_action_pressed("ui_right"):
			step.call(1)
			Sfx.play("ui", 0.05, 0.8)
			b.accept_event())
	b.set_meta("cycle", step)
	refresh.call()
	return b


static func difficulty_names() -> Array:
	var out: Array = []
	for d: String in CpuSkill.LEVELS:
		out.append(CpuSkill.label(d))
	return out


static func unlocked_courses() -> Array[int]:
	var out: Array[int] = []
	for i: int in Game.LEVELS.size():
		if Game.is_level_unlocked(i):
			out.append(i)
	return out


## The setup screen's content: {"content": Control, "focus": Control}. `title` is the title scene
## (Back returns to its main screen).
static func build_screen(title: Node) -> Dictionary:
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.label("PARTY VS CPU", 36, Color.WHITE))
	var blurb: Label = UiKit.label("A solo Party Cup against CPU racers: item boxes, power-ups, shoves, KOs and points. No network needed.", 16, UiKit.SOFT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(500, 0)
	box.add_child(blurb)
	var mode_names: Array = []
	for m: String in MODES:
		mode_names.append(PartyNames.mode_name(m))
	var counts: Array = []
	for n: int in range(1, CpuField.MAX_RACERS):
		counts.append(str(n))
	var courses: Array[int] = unlocked_courses()
	var course_names: Array = []
	for i: int in courses:
		course_names.append("%d  %s" % [i + 1, Game.LEVELS[i]["name"]])
	course_i = clampi(course_i, 0, maxi(courses.size() - 1, 0))
	# the Party Cup rules that matter most sit above the rest: game type, cup length, and the rest on their own screen
	var variants: Array = []
	for v: String in PartyRuleset.VARIANTS:
		variants.append(PartyNames.variant_name(v))
	var cups: Array = []
	for n: int in PartyRuleset.CUPS:
		cups.append(PartyRuleset.cup_label(n))
	var type_row: Button = cycler("Game type", variants, maxi(PartyRuleset.VARIANTS.find(PartyRuleset.variant()), 0), func(i: int) -> void:
		PartyRuleset.set_value("variant", PartyRuleset.VARIANTS[i]))
	type_row.name = "GameType"
	box.add_child(type_row)
	var cup_row: Button = cycler("Cup length", cups, PartyRuleset.index_of_int(PartyRuleset.CUPS, PartyRuleset.cup_rounds()), func(i: int) -> void:
		PartyRuleset.set_value("cup", PartyRuleset.CUPS[i]))
	cup_row.name = "CupLength"
	box.add_child(cup_row)
	var rules_btn: Button = UiKit.button("More rules  ...", func() -> void:
		PartyRulesMenu.back_to = "partycpu"
		title.call("show_screen", "partyrules"), 440)
	rules_btn.name = "MoreRules"
	box.add_child(rules_btn)
	var mode_row: Button = cycler("Mode", mode_names, mode_i, func(i: int) -> void: mode_i = i)
	box.add_child(mode_row)
	box.add_child(cycler("CPU racers", counts, count_n - 1, func(i: int) -> void: count_n = i + 1))
	box.add_child(cycler("Difficulty", difficulty_names(), diff_i, func(i: int) -> void: diff_i = i))
	var course_row: Button = cycler("Course", course_names, course_i, func(i: int) -> void: course_i = i)
	box.add_child(course_row)
	var play: Button = UiKit.button("Start the Cup", func() -> void:
		Game.play_party_cpu(courses[course_i], MODES[mode_i], count_n, CpuSkill.LEVELS[diff_i]), 440)
	play.name = "StartCup"
	box.add_child(play)
	box.add_child(UiKit.button("Back", func() -> void: title.call("show_screen", "main"), 440))
	var hint: Label = UiKit.label("A / click changes a row   D-pad left / right steps back   B back", 14, UiKit.SOFT)
	hint.name = "Hint"
	box.add_child(hint)
	var p: PanelContainer = UiKit.panel(Vector2(540, 0))
	p.add_child(box)
	return {"content": p, "focus": play}


## The lobby host's CPU options (below the mode picker). Solo: how many and how good; online:
## "Fill with CPUs" + their level - the CPUs join when the round starts.
static func add_lobby_controls(box: VBoxContainer) -> void:
	if Net.local_session:
		var counts: Array = []
		for n: int in range(1, CpuField.MAX_RACERS):
			counts.append(str(n))
		box.add_child(cycler("CPU racers", counts, CpuField.local_count - 1, func(i: int) -> void:
			CpuField.configure_local(i + 1, CpuField.difficulty)
			CpuField.sync_roster()))
		box.add_child(cycler("CPU level", difficulty_names(), CpuSkill.LEVELS.find(CpuField.difficulty), func(i: int) -> void:
			CpuField.configure_local(CpuField.local_count, CpuSkill.LEVELS[i])
			CpuField.sync_roster()))
		return
	CpuField.apply_ruleset()   # the saved CPU-fill rule is what the row shows
	var fills: Array = []
	for n: int in PartyRuleset.FILLS:
		fills.append(PartyRuleset.fill_label(n))
	var fill: Button = cycler("Fill with CPUs", fills, PartyRuleset.index_of_int(PartyRuleset.FILLS, int(PartyRuleset.cur()["cpu"])), func(i: int) -> void:
		PartyRuleset.set_value("cpu", PartyRuleset.FILLS[i])
		CpuField.apply_ruleset())
	fill.name = "FillCpus"
	box.add_child(fill)
	box.add_child(cycler("CPU level", difficulty_names(), CpuSkill.LEVELS.find(CpuField.difficulty), func(i: int) -> void:
		CpuField.difficulty = CpuSkill.LEVELS[i]))
	var note: Label = UiKit.label("Party modes only. Empty seats (up to 8 racers) are filled with CPUs when a round starts.", 13, UiKit.SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(520, 0)
	box.add_child(note)
