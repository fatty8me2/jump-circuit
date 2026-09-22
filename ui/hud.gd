class_name Hud
extends CanvasLayer
## In-level overlay: unobtrusive timer, toasts, countdown, race board, results,
## and the F3 developer readout.

var level: LevelBase

var _root: Control
var _timer: Label
var _intro: VBoxContainer
var _toast: Label
var _count: Label
var _board: VBoxContainer
var _flash: ColorRect
var _debug: Label
var _results: Control
var _board_refresh: float = 0.0
var _last_count: int = 99
var _peak_speed: float = 0.0
var _stage: Label
var _speed: Label


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

	_count = UiKit.shadowed(UiKit.label("", 150, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), 14)
	_count.set_anchors_preset(Control.PRESET_CENTER)
	_count.position = Vector2(-300, -190)
	_count.custom_minimum_size = Vector2(600, 0)
	_count.visible = false
	_root.add_child(_count)

	_board = UiKit.vbox(3)
	_board.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_board.position = Vector2(-290, 16)
	_board.custom_minimum_size = Vector2(270, 0)
	_board.visible = Game.race_mode
	_root.add_child(_board)

	_debug = UiKit.shadowed(UiKit.label("", 15, Color(0.7, 1.0, 0.8)), 4)
	_debug.position = Vector2(16, 60)
	_debug.visible = Game.dev_mode
	_root.add_child(_debug)
	Net.roster_changed.connect(_rebuild_board)


func _timer_visible() -> bool:
	if Game.race_mode or Settings.timer_mode == "on":
		return true
	if Settings.timer_mode == "off":
		return false
	return level != null and SaveData.is_completed(level.level_id)


func show_intro(title: String, blurb: String) -> void:
	for c: Node in _intro.get_children():
		c.queue_free()
	_intro.add_child(UiKit.shadowed(UiKit.label(title, 44, Color.WHITE)))
	_intro.add_child(UiKit.shadowed(UiKit.label(blurb, 20, UiKit.SOFT)))
	var tw: Tween = create_tween()
	tw.tween_property(_intro, "modulate:a", 1.0, 0.5)
	tw.tween_interval(3.0)
	tw.tween_property(_intro, "modulate:a", 0.0, 1.0)


func toast(text: String) -> void:
	_toast.text = text
	var tw: Tween = create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.12)
	tw.tween_interval(1.3)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func flash() -> void:
	_flash.color = Color(1, 1, 1, 0.55)
	var tw: Tween = create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.3)


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
		var me: String = "  <" if id == Net.my_id() else ""
		var l: Label = UiKit.shadowed(UiKit.label("%d  %s   %s%s" % [place, e["name"], status, me], 20, col.lerp(Color.WHITE, 0.35)), 5)
		_board.add_child(l)
		place += 1


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

func show_results(time: float, prev_best: float, is_best: bool, deaths: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label("COURSE CLEAR", 22, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(str(Game.level_info()["name"]), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(SaveData.format_time(time), 64, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var sub: String = "First clear!" if prev_best < 0.0 else ("New personal best!  (was %s)" % SaveData.format_time(prev_best) if is_best else "Personal best  %s" % SaveData.format_time(prev_best))
	box.add_child(UiKit.label(sub, 22, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var ff: int = SaveData.fewest_falls(level.level_id)
	var falls_text: String = "Falls: %d" % deaths
	if deaths == 0:
		falls_text = "FLAWLESS - no falls!"
	elif ff >= 0:
		falls_text += "   (fewest ever: %d)" % ff
	box.add_child(UiKit.label(falls_text, 18, UiKit.GOLD if deaths == 0 else Color(0.7, 0.74, 0.85), HORIZONTAL_ALIGNMENT_CENTER))
	var last: bool = Game.level_index == Game.LEVELS.size() - 1
	var next: Button = UiKit.button("Finale" if last else "Next Level", func() -> void: Game.next_level())
	box.add_child(next)
	box.add_child(UiKit.button("Run It Again", func() -> void: Game.restart_level()))
	box.add_child(UiKit.button("Level Select", func() -> void: Game.goto_title("levels")))
	var p: PanelContainer = UiKit.panel(Vector2(460, 0))
	p.add_child(box)
	_results = UiKit.centered(p)
	_results.modulate.a = 0.0
	_root.add_child(_results)
	create_tween().tween_property(_results, "modulate:a", 1.0, 0.35)
	next.grab_focus()


func show_race_results() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label("FINISHED!", 40, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("Live standings are on the right.", 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	if Net.is_host():
		box.add_child(UiKit.button("Back to Lobby (everyone)", func() -> void: Net.host_return_to_lobby()))
	else:
		box.add_child(UiKit.label("Waiting for the host to continue...", 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.button("Leave Race", func() -> void:
		Net.leave()
		Game.goto_title("main")))
	var p: PanelContainer = UiKit.panel(Vector2(440, 0))
	p.add_child(box)
	_results = UiKit.centered(p)
	_root.add_child(_results)
