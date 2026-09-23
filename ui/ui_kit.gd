class_name UiKit
extends RefCounted
## Small shared UI vocabulary so every screen looks like the same game.

const INK := Color(0.07, 0.09, 0.14)
const PANEL := Color(0.09, 0.11, 0.18, 0.92)
const GOLD := Color(1.0, 0.79, 0.3)
const TEAL := Color(0.22, 0.84, 0.75)
const SOFT := Color(0.85, 0.88, 0.95)

static var _theme: Theme


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20
	var normal := _box(Color(0.16, 0.19, 0.29), 10)
	var hover := _box(Color(0.22, 0.27, 0.42), 10)
	hover.border_color = GOLD
	hover.set_border_width_all(2)
	var pressed := _box(GOLD.darkened(0.2), 10)
	var disabled := _box(Color(0.12, 0.13, 0.18, 0.7), 10)
	# a ring just outside the button: easy to follow with a pad, even over a hovered button
	var focus := _box(Color(0, 0, 0, 0), 12)
	focus.border_color = GOLD
	focus.set_border_width_all(3)
	focus.set_expand_margin_all(3)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", SOFT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.6))
	# Toggles read like the dropdown slabs next to them ("On" in teal), not like a
	# pressed action button; disabled/focus still inherit from Button.
	t.set_stylebox("normal", "CheckButton", normal)
	t.set_stylebox("pressed", "CheckButton", normal)
	t.set_stylebox("hover", "CheckButton", hover)
	t.set_stylebox("hover_pressed", "CheckButton", hover)
	t.set_color("font_pressed_color", "CheckButton", TEAL)
	t.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	# Dropdown lists (OptionButton, LineEdit context menu) instead of the engine's grey popup.
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.1, 0.12, 0.19, 0.98), 10, 6))
	t.set_stylebox("hover", "PopupMenu", _box(Color(0.22, 0.27, 0.42), 8, 4))
	t.set_color("font_color", "PopupMenu", SOFT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	# a focused (or hovered) slider fills gold, so keyboard / pad users can see where they are
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(GOLD, 3, 0))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 18, 22))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.05, 0.06, 0.1), 8, 8))
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "Label", SOFT)
	_theme = t
	return t


static func _box(color: Color, radius: int, margin: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin + 6
	sb.content_margin_right = margin + 6
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


static func label(text: String, size: int = 20, color: Color = SOFT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func shadowed(l: Label, outline: int = 6) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", outline)
	return l


static func button(text: String, on_press: Callable, min_width: float = 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 48)
	b.pressed.connect(func() -> void:
		Sfx.play("ui", 0.05, 0.6)
		on_press.call())
	return b


## A destructive action. The first press arms it (`armed_text` in gold) and a second
## press within 3 s runs it. Moving focus away or waiting disarms it. Works while paused.
static func confirm_button(text: String, armed_text: String, on_press: Callable, min_width: float = 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 48)
	var armed_at: Array[int] = [-1]   # boxed: lambdas capture locals by value
	var colors: Array[String] = ["font_color", "font_focus_color", "font_hover_color"]
	var disarm := func() -> void:
		armed_at[0] = -1
		if is_instance_valid(b):
			b.text = text
			for c: String in colors:
				b.remove_theme_color_override(c)
	b.pressed.connect(func() -> void:
		Sfx.play("ui", 0.05, 0.6)
		var now: int = Time.get_ticks_msec()
		if armed_at[0] >= 0:
			if now - armed_at[0] >= 250:   # not a double-click or key bounce
				on_press.call()
			return
		armed_at[0] = now
		b.text = armed_text
		for c: String in colors:
			b.add_theme_color_override(c, GOLD)
		b.get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if armed_at[0] == now:
				disarm.call()))
	b.focus_exited.connect(disarm)
	return b


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


static func slider(min_v: float, max_v: float, value: float, on_change: Callable, step: float = 0.01) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(240, 24)
	s.value_changed.connect(on_change)
	return s


## Gives keyboard/gamepad navigation a starting point: Godot won't begin focus
## navigation from nothing. Deferred so `root` can be added to the tree first; keeps
## focus that already sits inside `root`. `prefer` wins when it is visible and enabled,
## otherwise the first visible, enabled button or slider under `root` gets focus.
static func focus_first(root: Control, prefer: Control = null) -> void:
	var grab := func() -> void:
		if not is_instance_valid(root) or not root.is_inside_tree():
			return
		var cur: Control = root.get_viewport().gui_get_focus_owner()
		if cur != null and root.is_ancestor_of(cur):
			return
		if is_instance_valid(prefer) and _focusable(prefer):
			prefer.grab_focus()
			return
		for n: Node in root.find_children("*", "Control", true, false):
			var c := n as Control
			if (c is BaseButton or c is Range) and _focusable(c):
				c.grab_focus()
				return
	grab.call_deferred()


static func _focusable(c: Control) -> bool:
	if not c.is_inside_tree() or not c.is_visible_in_tree() or c.focus_mode == Control.FOCUS_NONE:
		return false
	return not (c is BaseButton and (c as BaseButton).disabled)
