class_name PauseMenu
extends CanvasLayer
## Escape menu. Solo play freezes the world; in a race the world keeps running
## (it is shared) and the menu is just an overlay. A solo run also pauses itself
## when the game window loses focus.

var level: LevelBase

var _root: Control
var _menu: Control
var _settings: Control
## The menu's Settings button, focused again when coming back from the settings.
var _settings_btn: Button
var open: bool = false
## Mouse buttons are swallowed until this time (msec), so the click that refocuses
## the window can't land on a menu button.
var _click_guard_until: int = 0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.08, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)


## Leaving the level from the menu (restart, title) must not leave the score muffled.
func _exit_tree() -> void:
	Sfx.muffle(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# solo only: a race clock is shared and can't pause
		if level != null and not open and not level.finished and not Game.race_mode \
				and not Game.shot_mode and not level.headless_mode:
			set_open(true)
		if open:
			_click_guard_until = 1 << 62  # until focus comes back
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _click_guard_until > Time.get_ticks_msec():
		_click_guard_until = Time.get_ticks_msec() + 300


func _input(event: InputEvent) -> void:
	# runs before the GUI, so the refocus click never reaches a button
	if open and event is InputEventMouseButton and Time.get_ticks_msec() < _click_guard_until:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	var back: bool = event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")
	if open and _settings != null and back:
		# Esc / B / Start in Settings goes back to the menu and keeps the changes
		Settings.save_settings()
		_show_menu(true)
		get_viewport().set_input_as_handled()
		return
	if open and Game.is_menu_nav(event) and get_viewport().gui_get_focus_owner() == null:
		# lost focus (a mouse click elsewhere): the first pad / arrow press finds the menu again
		UiKit.focus_first(_settings if _settings != null else _menu)
		get_viewport().set_input_as_handled()
		return
	if level == null or level.finished:
		return
	# one chain: Esc is both "pause" and ui_cancel; B (ui_cancel) never opens the menu
	if event.is_action_pressed("pause"):
		set_open(not open)
		get_viewport().set_input_as_handled()
	elif open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func set_open(on: bool) -> void:
	if not on and _settings != null:
		Settings.save_settings()   # closed straight from Settings: only "Done" saved before
	open = on
	_root.visible = on
	if not on:
		_click_guard_until = 0
	if not Game.race_mode:
		get_tree().paused = on
		Sfx.muffle(on)
	level.player.control_enabled = (not on) and (not level.finished) and (not Game.race_mode or Game.course_time >= 0.0)
	level.camera.mouse_enabled = not on
	# a finished run keeps the cursor for its results panel
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (on or level.finished) else Input.MOUSE_MODE_CAPTURED
	if on:
		_show_menu()


func _clear() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _settings != null:
		_settings.queue_free()
		_settings = null


func _show_menu(focus_settings: bool = false) -> void:
	_clear()
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.label("PAUSED" if not Game.race_mode else "MENU (race continues)", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(str(Game.level_info()["name"]), 18, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	var resume: Button = UiKit.button("Resume", func() -> void: set_open(false))
	box.add_child(resume)
	box.add_child(UiKit.button("Back to Checkpoint  (%s)" % Game.prompt("restart"), func() -> void:
		set_open(false)
		level.manual_respawn()))
	if not Game.race_mode:
		box.add_child(_risky("Restart Level", "restart", func() -> void:
			set_open(false)
			level.restart_run()))
	_settings_btn = UiKit.button("Settings", func() -> void: _show_settings())
	box.add_child(_settings_btn)
	if Game.race_mode:
		if Net.is_host():
			# the host can end the race for everyone without finishing it first
			box.add_child(UiKit.confirm_button("End Race - Everyone to Lobby", "Press again to end the race", func() -> void: Net.host_return_to_lobby()))
			box.add_child(UiKit.confirm_button("Close Session (disconnects all)", "Press again to disconnect all", func() -> void:
				Net.leave()
				Game.goto_title("main")))
		else:
			box.add_child(UiKit.button("Leave Race", func() -> void:
				Net.leave()
				Game.goto_title("main")))
	else:
		# Party Practice goes back to its own course list
		box.add_child(_risky("Level Select", "leave", func() -> void: Game.goto_title("practice" if Game.party != null else "levels")))
		box.add_child(_risky("Quit to Title", "quit", func() -> void: Game.goto_title("main")))
	var p: PanelContainer = UiKit.panel(Vector2(400, 0))
	p.add_child(box)
	_menu = UiKit.centered(p)
	_root.add_child(_menu)
	if focus_settings:
		_settings_btn.grab_focus()
	else:
		resume.grab_focus()


## A run-ending button: two presses once a checkpoint is banked (before that, R
## restarts instantly anyway, so one press is enough).
func _risky(text: String, verb: String, action: Callable) -> Button:
	if level.current_checkpoint <= 0:
		return UiKit.button(text, action)
	return UiKit.confirm_button(text, "Press again to %s" % verb, action)


func _show_settings() -> void:
	_clear()
	var sp := SettingsPanel.new()
	sp.closed.connect(_show_menu.bind(true))
	_settings = UiKit.centered(sp)
	_root.add_child(_settings)
