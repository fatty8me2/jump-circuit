class_name Hud
extends CanvasLayer
## In-level overlay: unobtrusive timer, toasts, countdown, race board, results,
## and the F3 developer readout.

var level: LevelBase

var _root: Control
var _timer: Label
var _intro: VBoxContainer
var _toast: Label
## Second line under the toast (split time vs best); a child, so it fades with it.
var _toast_sub: Label
var _toast_tw: Tween
var _count: Label
var _board: VBoxContainer
var _flash: ColorRect
var _flash_tw: Tween
var _debug: Label
var _results: Control
var _results_ready: bool = false
## "2nd place of 4" on the race results panel; follows the live standings.
var _race_place: Label
var _board_refresh: float = 0.0
var _last_count: int = 99
var _peak_speed: float = 0.0
var _stage: Label
var _stage_tw: Tween
var _speed: Label
## Race results: "Spectate" button, shown while someone is still on the course.
var _spectate_btn: Button
## Bottom bar while spectating: who you are watching and the controls.
var _spec_bar: VBoxContainer
var _spec_name: Label
var _spec_hint: Label


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	_timer = UiKit.shadowed(UiKit.label("0:00.00", 26, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER))
	_timer.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer.position = Vector2(-80, 14)
	_timer.custom_minimum_size = Vector2(160, 0)
	_root.add_child(_timer)

	_stage = UiKit.shadowed(UiKit.label("", 22, Color(1, 1, 1, 0.9)), 5)
	_stage.position = Vector2(24, 16)
	_root.add_child(_stage)
	_speed = UiKit.shadowed(UiKit.label("", 20, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER), 5)
	_speed.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speed.position = Vector2(-100, -60)
	_speed.custom_minimum_size = Vector2(200, 0)
	_root.add_child(_speed)

	_intro = UiKit.vbox(2)
	_intro.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_intro.position = Vector2(48, -150)
	_intro.modulate.a = 0.0
	_root.add_child(_intro)

	_toast = UiKit.shadowed(UiKit.label("", 30, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-300, 110)
	_toast.custom_minimum_size = Vector2(600, 0)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_toast_sub = UiKit.shadowed(UiKit.label("", 24, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER), 5)
	_toast_sub.position = Vector2(0, 40)
	_toast_sub.custom_minimum_size = Vector2(600, 0)
	_toast.add_child(_toast_sub)

	_count = UiKit.shadowed(UiKit.label("", 150, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), 14)
	_count.set_anchors_preset(Control.PRESET_CENTER)
	_count.position = Vector2(-300, -190)
	_count.custom_minimum_size = Vector2(600, 0)
	_count.visible = false
	_root.add_child(_count)

	_board = UiKit.vbox(3)
	_board.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# right edge pinned 20 px in: long names widen the board leftwards, not off-screen
	_board.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_board.position = Vector2(-20, 16)
	_board.custom_minimum_size = Vector2(270, 0)
	_board.visible = Game.race_mode
	_root.add_child(_board)

	_spec_bar = UiKit.vbox(2)
	_spec_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spec_bar.position = Vector2(-300, -118)
	_spec_bar.custom_minimum_size = Vector2(600, 0)
	_spec_bar.visible = false
	_spec_bar.add_child(UiKit.shadowed(UiKit.label("SPECTATING", 18, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER), 5))
	_spec_name = UiKit.shadowed(UiKit.label("", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), 8)
	_spec_bar.add_child(_spec_name)
	_spec_hint = UiKit.shadowed(UiKit.label("", 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER), 5)
	_spec_bar.add_child(_spec_hint)
	_root.add_child(_spec_bar)

	_debug = UiKit.shadowed(UiKit.label("", 15, Color(0.7, 1.0, 0.8)), 4)
	_debug.position = Vector2(16, 60)
	_debug.visible = Game.dev_mode
	_root.add_child(_debug)
	Net.roster_changed.connect(_rebuild_board)


## Results panels: if focus got lost (a mouse click on the backdrop), the first pad /
## arrow press lands on the panel's first live button.
func _unhandled_input(event: InputEvent) -> void:
	if _results != null and _results.visible and Game.is_menu_nav(event) and get_viewport().gui_get_focus_owner() == null:
		UiKit.focus_first(_results)
		get_viewport().set_input_as_handled()


func _timer_visible() -> bool:
	if Game.race_mode or Settings.timer_mode == "on":
		return true
	if Settings.timer_mode == "off":
		return false
	# "auto": once this course layout has a best time (an old layout's clear doesn't count)
	return level != null and SaveData.best_time(level.level_id) >= 0.0


func show_intro(title: String, blurb: String) -> void:
	for c: Node in _intro.get_children():
		c.queue_free()
	_intro.add_child(UiKit.shadowed(UiKit.label(title, 44, Color.WHITE)))
	_intro.add_child(UiKit.shadowed(UiKit.label(blurb, 20, UiKit.SOFT)))
	var tw: Tween = create_tween()
	tw.tween_property(_intro, "modulate:a", 1.0, 0.5)
	tw.tween_interval(3.0)
	tw.tween_property(_intro, "modulate:a", 0.0, 1.0)


## `pop` springs the headline in from a larger size (checkpoints).
func toast(text: String, sub: String = "", sub_color: Color = UiKit.SOFT, pop: bool = false) -> void:
	_toast.text = text
	_toast_sub.text = sub
	_toast_sub.add_theme_color_override("font_color", sub_color)
	# the previous toast's fade-out would otherwise cut this one short
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2.ONE * (1.3 if pop else 1.0)
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.12)
	if pop:
		_toast_tw.parallel().tween_property(_toast, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tw.tween_interval(1.3)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


## Checkpoint banner: "STAGE n / N" (the stage you are now on, as the corner label
## counts it) over the split against your best run when the timer is shown.
func checkpoint_reached(index: int, time: float) -> void:
	var sub: String = ""
	var col: Color = UiKit.SOFT
	if not Game.race_mode and _timer_visible():
		var best: Array = SaveData.best_splits(level.level_id)
		# a best from another checkpoint layout, or a skipped checkpoint, has no split
		if best.size() == level.checkpoints.size() and index >= 1 and index <= best.size() and float(best[index - 1]) >= 0.0:
			sub = _delta_text(time, float(best[index - 1]))
			col = _delta_color(time, float(best[index - 1]))
	toast(stage_text(index + 1, level.checkpoints.size() + 1), sub, col, true)
	# the corner counter ticks over in gold, then settles
	if _stage_tw != null and _stage_tw.is_valid():
		_stage_tw.kill()
	_stage.modulate = UiKit.GOLD
	_stage_tw = create_tween()
	_stage_tw.tween_property(_stage, "modulate", Color.WHITE, 0.8)


## An in-place restart (LevelBase.restart_run) drops the last run's stage banner.
func clear_banner() -> void:
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	if _stage_tw != null and _stage_tw.is_valid():
		_stage_tw.kill()
	_toast.modulate.a = 0.0
	_toast.scale = Vector2.ONE
	_toast_sub.text = ""
	_stage.modulate = Color.WHITE


## Banner line for arriving on `stage` of `total` ("FINAL STAGE" for the last one).
static func stage_text(stage: int, total: int) -> String:
	return "FINAL STAGE" if stage >= total else "STAGE %d / %d" % [stage, total]


## "-1.84" / "+0.62" against `ref`, at the resolution the times are shown.
static func _delta_text(time: float, ref: float) -> String:
	return "%+.2f" % (float(SaveData.centiseconds(time) - SaveData.centiseconds(ref)) / 100.0)


## Teal when ahead of `ref`, soft red when behind.
static func _delta_color(time: float, ref: float) -> Color:
	var d: int = SaveData.centiseconds(time) - SaveData.centiseconds(ref)
	return UiKit.TEAL if d < 0 else (Color(1.0, 0.5, 0.45) if d > 0 else UiKit.SOFT)


## Respawn veil, drawn over the already-completed respawn (it never delays control):
## a dark dip that hides the camera cut, tinted red for a hazard, lighter for R / menu.
func flash(cause: String = "") -> void:
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	match cause:
		"hazard":
			_flash.color = Color(0.45, 0.03, 0.06, 0.5)
		"fall":
			_flash.color = Color(0.02, 0.03, 0.07, 0.55)
		_:
			_flash.color = Color(0.02, 0.03, 0.07, 0.3)
	_flash_tw = create_tween()
	_flash_tw.tween_property(_flash, "color:a", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func start_countdown() -> void:
	_count.visible = true
	_last_count = 99


func go() -> void:
	_count.text = "GO!"
	_count.add_theme_color_override("font_color", UiKit.TEAL)
	Sfx.play("go")
	var tw: Tween = create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_count, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: _count.visible = false)


func _process(dt: float) -> void:
	if level == null:
		return
	_timer.visible = _timer_visible() and _results == null
	_timer.text = SaveData.format_time(maxf(level.run_time, 0.0))
	# past your personal best the timer turns red: this run won't be a PB
	var pb: float = SaveData.best_time(level.level_id)
	_timer.self_modulate = Color(1.0, 0.6, 0.55) if not Game.race_mode and pb >= 0.0 and level.run_time > pb else Color.WHITE
	_stage.text = "Stage %d / %d     Falls %d" % [level.current_checkpoint + 1, level.checkpoints.size() + 1, level.deaths]
	_stage.visible = _results == null
	var hs: float = level.player.horizontal_speed()
	_speed.visible = hs > 11.0 and _results == null
	_speed.text = "%d m/s" % int(hs)
	_speed.add_theme_font_size_override("font_size", int(clampf(18.0 + (hs - 11.0) * 0.9, 18.0, 38.0)))
	if _count.visible and Game.course_time < 0.0:
		var n: int = int(ceil(-Game.course_time))
		if n != _last_count and n <= 3:
			_last_count = n
			_count.text = str(n)
			Sfx.play("tick")
		elif n > 3:
			_count.text = "READY"
	if _spec_bar.visible:
		_update_spectate_bar()
	if Game.race_mode:
		_board_refresh -= dt
		if _board_refresh <= 0.0:
			_board_refresh = 0.5
			_rebuild_board()
	if Input.is_action_just_pressed("debug_overlay"):
		_debug.visible = not _debug.visible
	if _debug.visible:
		_update_debug()


func _rebuild_board() -> void:
	if not Game.race_mode or _board == null:
		return
	for c: Node in _board.get_children():
		c.queue_free()
	var place: int = 1
	var total: int = level.checkpoints.size() + 1 if level != null else 1
	for id: int in Net.standings():
		var e: Dictionary = Net.roster[id]
		var col: Color = Settings.RACER_COLORS[int(e["color"]) % Settings.RACER_COLORS.size()]
		var status: String = SaveData.format_time(float(e["finished"])) if float(e["finished"]) >= 0.0 else "%d/%d" % [int(e["cp"]), total]
		var me: String = "  <" if id == Net.my_id() else ("  - watching" if level != null and id == level.spectating_id else "")
		var l: Label = UiKit.shadowed(UiKit.label("%d  %s   %s%s" % [place, e["name"], status, me], 20, col.lerp(Color.WHITE, 0.35)), 5)
		_board.add_child(l)
		if id == Net.my_id() and is_instance_valid(_race_place) and float(e["finished"]) >= 0.0:
			_race_place.text = "%d%s place of %d" % [place, _ordinal(place), Net.roster.size()] if Net.roster.size() > 1 else ""
		place += 1
	if is_instance_valid(_spectate_btn) and level != null:
		var can: bool = not level.spectate_candidates().is_empty()
		if _spectate_btn.visible != can:
			var had_focus: bool = _spectate_btn.has_focus()
			_spectate_btn.visible = can
			if had_focus and _results.visible:
				UiKit.focus_first(_results)


func _update_debug() -> void:
	var p: Player = level.player
	var hs: float = p.horizontal_speed()
	_peak_speed = maxf(_peak_speed * 0.999, hs)
	var floor_name: String = "-"
	if p.floor_body != null and p.floor_body is Node:
		var fb := p.floor_body as Node
		floor_name = "%s (%s)" % [fb.name, fb.get_class()]
		var par: Node = fb.get_parent()
		if par is TiltPlatform:
			var td: Vector2 = (par as TiltPlatform).tilt_degrees()
			floor_name += "  tilt x%.1f z%.1f" % [td.x, td.y]
	_debug.text = "fps %d   physics %d Hz\npos %.1f %.1f %.1f\nspeed %.2f (peak %.1f)   vy %.2f\ngrounded %s   air %.2fs\nfloor %s\nplatform vel %.2f %.2f %.2f\nlast jump: height %.2f  dist %.2f\ncourse t %.2f   checkpoint %d" % [
		Engine.get_frames_per_second(), Engine.physics_ticks_per_second,
		p.global_position.x, p.global_position.y, p.global_position.z,
		hs, _peak_speed, p.velocity.y, str(p.grounded), p.air_time, floor_name,
		p.platform_velocity.x, p.platform_velocity.y, p.platform_velocity.z,
		p.last_jump_height, p.last_jump_distance, Game.course_time, level.current_checkpoint]


# ---- end of level -------------------------------------------------------------------------

## `prev_best` / `prev_ff` are the records from before this run (-1 = none), so a
## new best time or fewest-falls record can be called out.
func show_results(time: float, prev_best: float, is_best: bool, deaths: int, prev_ff: int = -1) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label("COURSE CLEAR", 22, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(str(Game.level_info()["name"]), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(SaveData.format_time(time), 64, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var sub: String = "First clear!" if prev_best < 0.0 else ("New personal best!  (was %s)" % SaveData.format_time(prev_best) if is_best else "Personal best  %s" % SaveData.format_time(prev_best))
	box.add_child(UiKit.label(sub, 22, UiKit.GOLD if is_best and prev_best >= 0.0 else UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	if prev_best >= 0.0:
		box.add_child(UiKit.label(_delta_text(time, prev_best) + " s", 20, _delta_color(time, prev_best), HORIZONTAL_ALIGNMENT_CENTER))
	var falls_text: String = "Falls: %d" % deaths
	var falls_record: bool = deaths == 0 or (prev_ff >= 0 and deaths < prev_ff)
	if deaths == 0:
		falls_text = "FLAWLESS - no falls!"
	elif prev_ff >= 0 and deaths < prev_ff:
		falls_text += "  - fewest yet!  (was %d)" % prev_ff
	elif prev_ff >= 0:
		falls_text += "   (fewest ever: %d)" % prev_ff
	box.add_child(UiKit.label(falls_text, 18, UiKit.GOLD if falls_record else Color(0.7, 0.74, 0.85), HORIZONTAL_ALIGNMENT_CENTER))
	var last: bool = Game.level_index == Game.LEVELS.size() - 1
	var next: Button = UiKit.button("Finale" if last else "Next Level", func() -> void: Game.next_level())
	var buttons: Array[Button] = [next,
		UiKit.button("Run It Again  (%s)" % Game.prompt("restart"), func() -> void: Game.restart_level()),
		UiKit.button("Level Select", func() -> void: Game.goto_title("levels"))]
	for b: Button in buttons:
		b.disabled = true      # live once readable, so a jump mashed into the gate can't skip it
		box.add_child(b)
	var p: PanelContainer = UiKit.panel(Vector2(460, 0))
	p.add_child(box)
	_results = UiKit.centered(p)
	_results.modulate.a = 0.0
	_root.add_child(_results)
	var tw: Tween = create_tween()
	tw.tween_property(_results, "modulate:a", 1.0, 0.35)
	tw.tween_interval(0.35)
	tw.tween_callback(func() -> void:
		for b: Button in buttons:
			b.disabled = false
		_results_ready = true
		next.grab_focus())


## True once the results panel takes input (R / Y retries from then on).
func results_ready() -> bool:
	return _results_ready


func show_race_results(time: float) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label("FINISHED!", 40, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(SaveData.format_time(time), 56, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_race_place = UiKit.label("", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_race_place)
	_rebuild_board()   # our own finish is already in the roster (call_local)
	box.add_child(UiKit.label("Live standings are on the right.", 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var leave_race := func() -> void:
		Net.leave()
		Game.goto_title("main")
	var first: Button
	var leave: Button
	# watching the racers still out there never ends anything, so it can be the first focus
	_spectate_btn = UiKit.button("Spectate Racers  (%s / %s)" % [Game.prompt("spectate_prev"), Game.prompt("spectate_next")],
		func() -> void: level.spectate(1))
	_spectate_btn.visible = not level.spectate_candidates().is_empty()
	box.add_child(_spectate_btn)
	# these buttons get focus, and Space / A are also the jump inputs: anything that
	# ends the race for someone still running takes two presses
	if Net.is_host():
		var to_lobby := func() -> void: Net.host_return_to_lobby()
		if Net.all_finished():
			first = UiKit.button("Back to Lobby (everyone)", to_lobby)
		else:
			first = UiKit.confirm_button("Back to Lobby (everyone)", "Press again to end the race", to_lobby)
		box.add_child(first)
		# for the host, leaving closes the session on everyone
		leave = UiKit.confirm_button("Close Session (disconnects all)", "Press again to disconnect all", leave_race)
	else:
		box.add_child(UiKit.label("Waiting for the host to continue...", 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
		leave = UiKit.confirm_button("Leave Race", "Press again to leave", leave_race)
		first = leave
	box.add_child(leave)
	var p: PanelContainer = UiKit.panel(Vector2(440, 0))
	p.add_child(box)
	_results = UiKit.centered(p)
	_results.modulate.a = 0.0
	_root.add_child(_results)
	# focus (for keyboard / pad) only after a beat, so a jump mashed across the line
	# can't press a button that ends the race; keeps focus the player already moved
	var tw: Tween = create_tween()
	tw.tween_property(_results, "modulate:a", 1.0, 0.35)
	tw.tween_interval(0.65)
	tw.tween_callback(func() -> void:
		_results_ready = true
		if not _results.visible:
			return      # already spectating (LB / RB); focus waits for the panel
		if _spectate_btn.visible and get_viewport().gui_get_focus_owner() == null:
			_spectate_btn.grab_focus()
		elif is_instance_valid(first) and get_viewport().gui_get_focus_owner() == null:
			first.grab_focus())


## Spectating hides the results panel (the race board stays) and shows who you are watching.
func set_spectating(on: bool) -> void:
	_spec_bar.visible = on
	if _results != null:
		_results.visible = not on
		if not on:
			UiKit.focus_first(_results, _spectate_btn)
	if on:
		_update_spectate_bar()
	_rebuild_board()


func _update_spectate_bar() -> void:
	var id: int = level.spectating_id
	if not Net.roster.has(id):
		return
	var e: Dictionary = Net.roster[id]
	var col: Color = Settings.RACER_COLORS[int(e["color"]) % Settings.RACER_COLORS.size()]
	_spec_name.text = str(e["name"])
	_spec_name.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
	var n: int = level.spectate_candidates().size()
	var cycle: String = "%s / %s  switch racer (%d racing)" % [Game.prompt("spectate_prev"), Game.prompt("spectate_next"), n] if n > 1 else "the last racer on the course"
	_spec_hint.text = "Stage %d / %d      %s      %s  results" % [
		mini(int(e["cp"]) + 1, level.checkpoints.size() + 1), level.checkpoints.size() + 1, cycle, Game.prompt("back")]


## "st" / "nd" / "rd" / "th" for a place number.
static func _ordinal(n: int) -> String:
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
