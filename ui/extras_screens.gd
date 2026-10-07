class_name ExtraScreens
extends RefCounted
## The Challenges and Stats screens of the main menu (built here, hosted by ui/title.gd, which
## wraps each in its left column and gives the returned `focus` control the first pad focus).
## Both are fully pad navigable: the challenges list is a column of focusable course rows in a
## scroll box that follows focus, the stats page is read-only with Back focused; B backs out
## through Title's ui_cancel handling.

const WIDTH: float = 760.0
const DONE_COLOR := Color(1.0, 0.79, 0.3)


## {"root": Control, "focus": Control}
static func challenges_screen(on_back: Callable, on_play: Callable) -> Dictionary:
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.shadowed(UiKit.label("CHALLENGES", 40, Color.WHITE), 8))
	var done: int = Challenges.count()
	var summary: Label = UiKit.label("%d / %d complete" % [done, Challenges.total()], 20, UiKit.GOLD)
	summary.name = "Summary"
	box.add_child(summary)
	var nxt: Array = Challenges.next_reward()
	var reward: Label = UiKit.label("All challenge rewards earned!" if nxt.is_empty() else "Next reward: %s  -  %d more (at %d)" % [nxt[0], nxt[1], nxt[2]], 17, UiKit.SOFT)
	reward.name = "NextReward"
	box.add_child(reward)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var list: VBoxContainer = UiKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	scroll.custom_minimum_size = Vector2(WIDTH - 20.0, 400)
	box.add_child(scroll)
	var first_open: Button = null
	var first: Button = null
	for i: int in Game.LEVELS.size():
		var id: String = str(Game.LEVELS[i]["id"])
		var n: int = Challenges.level_count(id)
		var lines: PackedStringArray = ["%s     %d/%d" % [Game.LEVELS[i]["name"], n, Challenges.KINDS.size()]]
		for k: String in Challenges.KINDS:
			lines.append("   [%s]  %s  -  %s" % ["x" if Challenges.done(id, k) else " ", Challenges.title(id, k), Challenges.description(id, k)])
		var b: Button = UiKit.button("\n".join(lines), func() -> void: on_play.call(i), WIDTH - 24.0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		b.set_meta("level", id)
		b.set_meta("done", n)
		if n == Challenges.KINDS.size():
			b.add_theme_color_override("font_color", DONE_COLOR)
		b.disabled = not Game.is_level_unlocked(i)
		list.add_child(b)
		if first == null and not b.disabled:
			first = b
		if first_open == null and not b.disabled and n < Challenges.KINDS.size():
			first_open = b
	var back: Button = UiKit.button("Back", on_back, WIDTH - 24.0)
	back.name = "Back"
	box.add_child(back)
	var p: PanelContainer = UiKit.panel(Vector2(WIDTH, 0))
	p.add_child(box)
	return {"root": p, "focus": first_open if first_open != null else (first if first != null else back)}


## "3h 05m" / "12m 30s" / "45s".
@warning_ignore("integer_division")
static func play_time_text(secs: int) -> String:
	secs = maxi(secs, 0)
	if secs >= 3600:
		return "%dh %02dm" % [secs / 3600, (secs / 60) % 60]
	if secs >= 60:
		return "%dm %02ds" % [secs / 60, secs % 60]
	return "%ds" % secs


## The favourite course (most runs) as [name, runs], or [] with no runs yet.
static func favourite_course(levels: Dictionary) -> Array:
	var best_runs: int = 0
	var best_name: String = ""
	for info: Dictionary in Game.LEVELS:
		var e: Variant = levels.get(info["id"])
		var r: int = maxi(int((e as Dictionary).get("runs", 0)), 0) if e is Dictionary else 0
		if r > best_runs:
			best_runs = r
			best_name = str(info["name"])
	return [] if best_runs == 0 else [best_name, best_runs]


## The Stats rows as [label, value] pairs (tests read these too).
static func stats_rows() -> Array[PackedStringArray]:
	var levels: Dictionary = SaveData.data.get("levels", {})
	var rows: Array[PackedStringArray] = []
	rows.append(PackedStringArray(["Courses beaten", "%d / %d" % [Cosmetics.completed_count(levels), Game.LEVELS.size()]]))
	rows.append(PackedStringArray(["Total runs", str(Cosmetics.total_runs(levels))]))
	rows.append(PackedStringArray(["Total falls", str(SaveData.stat("falls_total"))]))
	rows.append(PackedStringArray(["Time played", play_time_text(SaveData.stat("play_secs"))]))
	var gold: int = Cosmetics.medal_count(levels, 3)
	var silver: int = Cosmetics.medal_count(levels, 2) - gold
	var bronze: int = Cosmetics.medal_count(levels, 1) - gold - silver
	rows.append(PackedStringArray(["Medals", "Gold %d   Silver %d   Bronze %d" % [gold, silver, bronze]]))
	rows.append(PackedStringArray(["Challenges done", "%d / %d" % [Challenges.count(), Challenges.total()]]))
	rows.append(PackedStringArray(["Flawless golds", str(SaveData.stat("flawless_golds"))]))
	var fav: Array = favourite_course(levels)
	rows.append(PackedStringArray(["Favourite course", "None yet" if fav.is_empty() else "%s  (%d runs)" % [fav[0], fav[1]]]))
	return rows


static func stats_screen(on_back: Callable) -> Dictionary:
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.shadowed(UiKit.label("STATS", 40, Color.WHITE), 8))
	var grid := GridContainer.new()
	grid.name = "Rows"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	for r: PackedStringArray in stats_rows():
		grid.add_child(UiKit.label(r[0], 22, UiKit.SOFT))
		grid.add_child(UiKit.label(r[1], 22, UiKit.GOLD))
	box.add_child(grid)
	var back: Button = UiKit.button("Back", on_back, WIDTH - 24.0)
	back.name = "Back"
	box.add_child(back)
	var p: PanelContainer = UiKit.panel(Vector2(WIDTH, 0))
	p.add_child(box)
	return {"root": p, "focus": back}
