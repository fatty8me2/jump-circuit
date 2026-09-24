class_name SettingsPanel
extends PanelContainer
## Camera, audio and graphics options. Used from the title and the pause menu.

signal closed

## Something changed since the last save: saved on Done, when the panel leaves the tree
## (pause menu Esc, scene change) or when the window is closed.
var _dirty: bool = false
var _fullscreen_check: CheckButton
var _scroll: ScrollContainer


func _ready() -> void:
	custom_minimum_size = Vector2(620, 0)
	# scrolls when the rows outgrow the screen (focus follows the pad, the wheel scrolls)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	var gutter := MarginContainer.new()   # room for the scrollbar
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 16)
	_scroll.add_child(gutter)
	var box: VBoxContainer = UiKit.vbox(10)
	gutter.add_child(box)
	box.add_child(UiKit.label("SETTINGS", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))

	_section(box, "Camera")
	_slider_row(box, "Mouse sensitivity", 0.2, 3.0, Settings.mouse_sensitivity, func(v: float) -> void: Settings.mouse_sensitivity = v,
		func(v: float) -> String: return "%.2fx" % v)
	_slider_row(box, "Field of view", 55.0, 100.0, Settings.fov, func(v: float) -> void: Settings.fov = v,
		func(v: float) -> String: return "%d°" % roundi(v), 1.0)
	_check_row(box, "Invert vertical look", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on)

	_section(box, "Audio")
	var pct := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	_slider_row(box, "Master volume", 0.0, 1.0, Settings.master_volume, func(v: float) -> void: Settings.master_volume = v, pct)
	_slider_row(box, "Effects", 0.0, 1.0, Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v, pct)
	_slider_row(box, "Music", 0.0, 1.0, Settings.music_volume, func(v: float) -> void: Settings.music_volume = v, pct)

	_section(box, "Graphics & HUD")
	_option_row(box, "Quality", Settings.QUALITY_NAMES, Settings.quality, func(i: int) -> void: Settings.quality = i)
	_fullscreen_check = _check_row(box, "Fullscreen", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on)
	_check_row(box, "V-Sync", Settings.vsync, func(on: bool) -> void: Settings.vsync = on)
	var modes: Array[String] = ["auto", "on", "off"]
	_option_row(box, "Run timer", ["After first clear", "Always", "Never"], modes.find(Settings.timer_mode), func(i: int) -> void: Settings.timer_mode = modes[i])

	_section(box, "Party Mode controls")
	var pc := PartyControls.new()
	pc.changed.connect(func() -> void: _dirty = true)
	box.add_child(pc)

	box.add_child(UiKit.button("Done", func() -> void:
		Settings.save_settings()
		_dirty = false
		closed.emit()))
	Settings.changed.connect(_sync_from_settings)
	UiKit.focus_first(self)
	_fit.call_deferred()
	get_viewport().size_changed.connect(_fit)


## Tall as its rows, but never taller than the screen (minus a margin): then it scrolls.
func _fit() -> void:
	if not is_inside_tree() or _scroll.get_child_count() == 0:
		return
	var want: float = (_scroll.get_child(0) as Control).get_combined_minimum_size().y
	var room: float = get_viewport_rect().size.y - 90.0
	_scroll.custom_minimum_size = Vector2(0, clampf(want, 200.0, maxf(room, 200.0)))
	# start at the top (focus-follow may have scrolled the not-yet-sized container)
	_scroll.set_deferred("scroll_vertical", 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_if_dirty()


func save_if_dirty() -> void:
	if _dirty:
		Settings.save_settings()
		_dirty = false


## F11 / Alt+Enter can flip fullscreen while the panel is open.
func _sync_from_settings() -> void:
	if _fullscreen_check != null and _fullscreen_check.button_pressed != Settings.fullscreen:
		_fullscreen_check.set_pressed_no_signal(Settings.fullscreen)
		_fullscreen_check.text = "On" if Settings.fullscreen else "Off"


func _section(box: VBoxContainer, text: String) -> void:
	box.add_child(UiKit.label(text.to_upper(), 16, UiKit.TEAL))


func _row(box: VBoxContainer, text: String, control: Control) -> void:
	var h: HBoxContainer = UiKit.hbox(16)
	var l: Label = UiKit.label(text, 19)
	l.custom_minimum_size = Vector2(260, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	box.add_child(h)


## `fmt` turns the value into the readout shown right of the slider.
func _slider_row(box: VBoxContainer, text: String, lo: float, hi: float, value: float, setter: Callable, fmt: Callable, step: float = 0.01) -> void:
	var readout: Label = UiKit.label(fmt.call(value), 19, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	readout.custom_minimum_size = Vector2(70, 0)
	var s: HSlider = UiKit.slider(lo, hi, value, func(v: float) -> void:
		setter.call(v)
		readout.text = fmt.call(v)
		_dirty = true
		Settings.apply(), step)
	s.custom_minimum_size.x = 200.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h: HBoxContainer = UiKit.hbox(10)
	h.add_child(s)
	h.add_child(readout)
	_row(box, text, h)


func _check_row(box: VBoxContainer, text: String, value: bool, setter: Callable) -> CheckButton:
	var cb := CheckButton.new()
	cb.button_pressed = value
	cb.text = "On" if value else "Off"
	cb.toggled.connect(func(on: bool) -> void:
		cb.text = "On" if on else "Off"
		setter.call(on)
		_dirty = true
		Settings.apply())
	_row(box, text, cb)
	return cb


func _option_row(box: VBoxContainer, text: String, options: Array, selected: int, setter: Callable) -> void:
	var ob := OptionButton.new()
	for o: String in options:
		ob.add_item(o)
	ob.selected = maxi(selected, 0)
	ob.item_selected.connect(func(i: int) -> void:
		setter.call(i)
		_dirty = true
		Settings.apply())
	_row(box, text, ob)
