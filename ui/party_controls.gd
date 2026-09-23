class_name PartyControls
extends VBoxContainer
## Party Mode controls inside the Settings panel: one button per party action showing its
## keyboard / mouse and pad bindings. Press one (A / Enter / click), then press the new key,
## mouse button or pad button: a keyboard or mouse input replaces that half of the binding, a pad
## button the pad half. Esc / Start cancels. Inputs the game already uses (jump, retry, pause,
## movement, camera...) are refused; an input another party action had moves over to this one.
## "Reset" restores the defaults. Changes land in Settings.party_binds (saved with the panel).

signal changed

const LABELS: Dictionary = {"attack": "Attack", "use_item": "Use item", "shove": "Shove", "cycle_item": "Next tool"}

var _buttons: Dictionary = {}
## The action waiting for an input ("" = none).
var capturing: String = ""
var _note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	for action: String in Game.PARTY_ACTIONS:
		var b: Button = UiKit.button("", func() -> void: _begin(action), 290)
		b.custom_minimum_size.y = 40
		b.add_theme_font_size_override("font_size", 16)
		b.name = "Bind_" + action
		grid.add_child(b)
		_buttons[action] = b
	var row: HBoxContainer = UiKit.hbox(12)
	_note = UiKit.label("", 14, UiKit.SOFT)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_note)
	var reset: Button = UiKit.button("Reset", func() -> void:
		Settings.party_binds = {}
		Game.apply_party_binds()
		_note.text = "Party controls reset to the defaults."
		_refresh()
		changed.emit(), 120)
	reset.custom_minimum_size.y = 36
	reset.name = "ResetBinds"
	row.add_child(reset)
	add_child(row)
	_refresh()
	Game.input_device_changed.connect(func(_pad: bool) -> void: _refresh())


func _refresh() -> void:
	for action: String in _buttons:
		var b: Button = _buttons[action]
		if action == capturing:
			b.text = "%s:  press a key / button..." % LABELS[action]
		else:
			b.text = "%s:  %s   |   %s" % [LABELS[action], Game.bind_text(action, false), Game.bind_text(action, true)]
	if capturing == "" and _note.text == "":
		_note.text = "Party Mode only. Pick one, then press the new key, mouse or pad button."


func _begin(action: String) -> void:
	# start listening next frame, so the press that opened the capture can't bind itself
	await get_tree().process_frame
	capturing = action
	_note.text = "Esc / Start cancels."
	_refresh()


func _input(event: InputEvent) -> void:
	if capturing == "":
		return
	var pressed: bool = false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton or event is InputEventJoypadButton:
		pressed = event.is_pressed()
	if not pressed:
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	var action: String = capturing
	if (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START):
		_stop("Cancelled.")
		return
	var taken: String = Game.fixed_action_for(event)
	if taken != "":
		_note.text = "That input is already %s - pick another (Esc / Start cancels)." % taken.replace("_", " ")
		return
	var field: String = ""
	var value: int = 0
	if event is InputEventKey:
		field = "key"
		value = int((event as InputEventKey).physical_keycode)
		if value == 0:
			value = int((event as InputEventKey).keycode)
	elif event is InputEventMouseButton:
		field = "mouse"
		value = int((event as InputEventMouseButton).button_index)
	else:
		field = "pad"
		value = int((event as InputEventJoypadButton).button_index)
	set_bind(action, field, value)
	_stop("%s is now %s." % [LABELS[action], Game.bind_text(action, field == "pad")])


## Binds one half of an action and frees that input from any other party action.
func set_bind(action: String, field: String, value: int) -> void:
	var binds: Dictionary = Settings.party_binds.duplicate(true)
	for other: String in Game.PARTY_ACTIONS:
		if other != action and int(Game.party_bind(other).get(field, -1)) == value:
			var o: Dictionary = (binds.get(other, {}) as Dictionary).duplicate()
			o[field] = -1 if field == "pad" else 0
			binds[other] = o
	var mine: Dictionary = (binds.get(action, {}) as Dictionary).duplicate()
	mine[field] = value
	binds[action] = mine
	Settings.party_binds = binds
	Game.apply_party_binds()
	changed.emit()


func _stop(note: String) -> void:
	var was: String = capturing
	capturing = ""
	_note.text = note
	_refresh()
	if _buttons.has(was):
		(_buttons[was] as Button).grab_focus()
