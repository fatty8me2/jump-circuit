class_name PauseMenu
extends CanvasLayer
## Escape menu. Solo play freezes the world; in a race the world keeps running
## (it is shared) and the menu is just an overlay.

var level: LevelBase

var _root: Control
var _menu: Control
var _settings: Control
var open: bool = false


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and level != null and not level.finished:
		set_open(not open)
		get_viewport().set_input_as_handled()


func set_open(on: bool) -> void:
	open = on
	_root.visible = on
	if not Game.race_mode:
		get_tree().paused = on
	level.player.control_enabled = (not on) and (not level.finished) and (not Game.race_mode or Game.course_time >= 0.0)
	level.camera.mouse_enabled = not on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if on:
		_show_menu()


func _clear() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _settings != null:
		_settings.queue_free()
		_settings = null


func _show_menu() -> void:
	_clear()
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.label("PAUSED" if not Game.race_mode else "MENU (race continues)", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(str(Game.level_info()["name"]), 18, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	var resume: Button = UiKit.button("Resume", func() -> void: set_open(false))
	box.add_child(resume)
	box.add_child(UiKit.button("Back to Checkpoint  (R)", func() -> void:
		set_open(false)
		level.respawn()))
	if not Game.race_mode:
		box.add_child(UiKit.button("Restart Level", func() -> void: Game.restart_level()))
	box.add_child(UiKit.button("Settings", func() -> void: _show_settings()))
	if Game.race_mode:
		box.add_child(UiKit.button("Leave Race", func() -> void:
			Net.leave()
			Game.goto_title("main")))
	else:
		box.add_child(UiKit.button("Level Select", func() -> void: Game.goto_title("levels")))
		box.add_child(UiKit.button("Quit to Title", func() -> void: Game.goto_title("main")))
	var p: PanelContainer = UiKit.panel(Vector2(400, 0))
	p.add_child(box)
	_menu = UiKit.centered(p)
	_root.add_child(_menu)
	resume.grab_focus()


func _show_settings() -> void:
	_clear()
	var sp := SettingsPanel.new()
	sp.closed.connect(_show_menu)
	_settings = UiKit.centered(sp)
	_root.add_child(_settings)
