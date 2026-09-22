class_name SettingsPanel
extends PanelContainer
## Camera, audio and graphics options. Used from the title and the pause menu.

signal closed


func _ready() -> void:
	custom_minimum_size = Vector2(620, 0)
	var box: VBoxContainer = UiKit.vbox(10)
	add_child(box)
	box.add_child(UiKit.label("SETTINGS", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))

	_section(box, "Camera")
	_slider_row(box, "Mouse sensitivity", 0.2, 3.0, Settings.mouse_sensitivity, func(v: float) -> void: Settings.mouse_sensitivity = v)
	_slider_row(box, "Field of view", 55.0, 100.0, Settings.fov, func(v: float) -> void: Settings.fov = v, 1.0)
	_check_row(box, "Invert vertical look", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on)

	_section(box, "Audio")
	_slider_row(box, "Master volume", 0.0, 1.0, Settings.master_volume, func(v: float) -> void: Settings.master_volume = v)
	_slider_row(box, "Effects", 0.0, 1.0, Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v)
	_slider_row(box, "Music", 0.0, 1.0, Settings.music_volume, func(v: float) -> void: Settings.music_volume = v)

	_section(box, "Graphics & HUD")
	_option_row(box, "Quality", ["Low", "Medium", "High"], Settings.quality, func(i: int) -> void: Settings.quality = i)
	_check_row(box, "Fullscreen", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on)
	_check_row(box, "V-Sync", Settings.vsync, func(on: bool) -> void: Settings.vsync = on)
	var modes: Array[String] = ["auto", "on", "off"]
	_option_row(box, "Run timer", ["After first clear", "Always", "Never"], modes.find(Settings.timer_mode), func(i: int) -> void: Settings.timer_mode = modes[i])

	box.add_child(UiKit.button("Done", func() -> void:
		Settings.save_settings()
		closed.emit()))


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


func _slider_row(box: VBoxContainer, text: String, lo: float, hi: float, value: float, setter: Callable, step: float = 0.01) -> void:
	_row(box, text, UiKit.slider(lo, hi, value, func(v: float) -> void:
		setter.call(v)
		Settings.apply(), step))


func _check_row(box: VBoxContainer, text: String, value: bool, setter: Callable) -> void:
	var cb := CheckButton.new()
	cb.button_pressed = value
	cb.toggled.connect(func(on: bool) -> void:
		setter.call(on)
		Settings.apply())
	_row(box, text, cb)


func _option_row(box: VBoxContainer, text: String, options: Array, selected: int, setter: Callable) -> void:
	var ob := OptionButton.new()
	for o: String in options:
		ob.add_item(o)
	ob.selected = maxi(selected, 0)
	ob.item_selected.connect(func(i: int) -> void:
		setter.call(i)
		Settings.apply())
	_row(box, text, ob)
