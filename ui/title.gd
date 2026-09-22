extends Node3D
## Title scene: a small living diorama behind the menus.
## Screens: main, level select, race lobby, settings, victory.

var _ui: Control
var _screen: Control
var _cam: Camera3D
var _t: float = 0.0
var _volt: PlayerVisual
var _volt_y: float = 0.0
var _volt_vy: float = 0.0
var _pad: BouncePad
var _status: Label
var _roster_box: VBoxContainer
var _lobby_level: int = 0
var _start_button: Button
var _upnp_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_diorama()
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiKit.theme()
	layer.add_child(_ui)
	Sfx.music("title")
	Net.roster_changed.connect(_refresh_lobby)
	Net.joined_lobby.connect(func() -> void: show_screen("lobby"))
	Net.connection_failed.connect(func(reason: String) -> void:
		Game.title_message = reason
		show_screen("race"))
	Net.upnp_result.connect(func(text: String) -> void:
		if _upnp_label != null and is_instance_valid(_upnp_label):
			_upnp_label.text = text)
	var want: String = Game.title_screen
	if want == "lobby" and not Net.active:
		want = "main"
	show_screen(want)


# ---- backdrop --------------------------------------------------------------------------------

func _build_diorama() -> void:
	Look.use_theme("gardens")
	Look.build_environment(self)
	var kit := LevelKit.new(self, 42)
	kit.plat(Vector3(0, 0, 0), Vector3(12, 2, 12))
	kit.plat(Vector3(9, 1.5, -8), Vector3(6, 2, 6), "alt")
	kit.disc(Vector3(-9, 2.5, -7), 2.6, 0.8, "accent")
	kit.disc(Vector3(-15, 5.0, -14), 2.2, 0.8)
	kit.plat(Vector3(4, 6, -22), Vector3(10, 2, 8))
	_pad = kit.pad(Vector3(1.5, 0, 0.5), 14.0, 0.0, 0.0, 1.4)
	kit.pad(Vector3(-9, 2.5, -7), 20.0, 35.0, -50.0, 1.2)
	kit.tree(Vector3(-4, 0, -3.5), 1.5)
	kit.tree(Vector3(4.5, 0, -4), 1.1)
	kit.round_tree(Vector3(10.5, 1.5, -9.5), 1.2)
	kit.bush(Vector3(-3.5, 0, 3))
	kit.arch(Vector3(4, 6, -20), 4.5, 4.0)
	kit.banner(Vector3(7.5, 6, -19.5), 4.5)
	kit.lamp(Vector3(4.5, 0, 4), 2.8, false)
	kit.cloud_field(Vector3(0, -14, -20), Vector3(90, 6, 90), 18)
	kit.cloud_field(Vector3(0, 30, -40), Vector3(120, 8, 120), 8)
	kit.monolith_ring(Vector3(0, 0, -20), 70.0, 120.0, 12, 20.0)
	_volt = PlayerVisual.new()
	add_child(_volt)
	_volt.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_volt.set_accent(Settings.my_color())
	_volt.position = Vector3(1.5, 0.2, 0.5)
	_volt.add_child(BlobShadow.make())
	_cam = Camera3D.new()
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam.fov = 58.0
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true


func _process(dt: float) -> void:
	_t += dt
	var a: float = 0.55 + sin(_t * 0.11) * 0.35
	_cam.position = Vector3(sin(a) * 15.0 - 2.0, 5.2 + sin(_t * 0.17) * 0.6, cos(a) * 15.0)
	_cam.look_at(Vector3(-3.5, 2.6, -5))
	# Volt idly bouncing on the pad
	_volt_vy -= (30.0 if _volt_vy > 0.0 else 42.0) * dt
	_volt_y += _volt_vy * dt
	if _volt_y <= 0.2:
		_volt_y = 0.2
		_volt_vy = 14.0
		_volt.on_bounce(14.0)
		_pad.on_bounced(null)
	_volt.position.y = _volt_y
	_volt.animate(dt, Vector3(0, _volt_vy, 0), false, Vector3(sin(_t * 0.4), 0, cos(_t * 0.4)))


# ---- screens ------------------------------------------------------------------------------------

func show_screen(id: String) -> void:
	if _screen != null:
		_screen.queue_free()
	_roster_box = null
	_status = null
	_start_button = null
	_upnp_label = null
	Game.title_screen = id
	match id:
		"levels":
			_screen = _levels_screen()
		"race":
			_screen = _race_screen()
		"lobby":
			_screen = _lobby_screen()
		"settings":
			_screen = _settings_screen()
		"victory":
			_screen = _victory_screen()
		_:
			_screen = _main_screen()
	_ui.add_child(_screen)


func _left_column(content: Control, width: float = 420.0) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	m.add_theme_constant_override("margin_left", 80)
	m.add_theme_constant_override("margin_top", 60)
	m.add_theme_constant_override("margin_bottom", 60)
	m.custom_minimum_size = Vector2(width + 80, 0)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(content)
	m.add_child(center)
	root.add_child(m)
	return root


func _logo() -> Control:
	var v: VBoxContainer = UiKit.vbox(0)
	var l1: Label = UiKit.shadowed(UiKit.label("JUMP", 96, Color.WHITE), 12)
	var l2: Label = UiKit.shadowed(UiKit.label("CIRCUIT", 96, UiKit.GOLD), 12)
	v.add_child(l1)
	v.add_child(l2)
	v.add_child(UiKit.shadowed(UiKit.label("read the course  -  build momentum  -  land it", 20, UiKit.SOFT), 6))
	return v


func _main_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(_logo())
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	box.add_child(spacer)
	var next_index: int = 0
	for i: int in Game.LEVELS.size():
		if SaveData.is_completed(Game.LEVELS[i]["id"]):
			next_index = mini(i + 1, Game.LEVELS.size() - 1)
	var play_text: String = "Play" if next_index == 0 and not SaveData.is_completed("gardens") else "Continue  -  %s" % Game.LEVELS[next_index]["name"]
	var play: Button = UiKit.button(play_text, func() -> void: Game.play_level(next_index), 380)
	box.add_child(play)
	box.add_child(UiKit.button("Level Select", func() -> void: show_screen("levels"), 380))
	box.add_child(UiKit.button("Race Friends", func() -> void: show_screen("race"), 380))
	box.add_child(UiKit.button("Settings", func() -> void: show_screen("settings"), 380))
	if Game.dev_mode:
		box.add_child(UiKit.button("Playground (dev)", func() -> void: Game.play_playground(), 380))
	box.add_child(UiKit.button("Quit", func() -> void: get_tree().quit(), 380))
	if Game.title_message != "":
		box.add_child(UiKit.shadowed(UiKit.label(Game.title_message, 18, Color(1, 0.6, 0.5))))
		Game.title_message = ""
	box.add_child(UiKit.shadowed(UiKit.label("WASD move   Space jump   Mouse look   R retry   Esc pause", 16, Color(1, 1, 1, 0.75)), 5))
	play.grab_focus.call_deferred()
	return _left_column(box)


func _levels_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.shadowed(UiKit.label("LEVEL SELECT", 40, Color.WHITE), 8))
	for i: int in Game.LEVELS.size():
		var info: Dictionary = Game.LEVELS[i]
		var unlocked: bool = Game.is_level_unlocked(i)
		var best: float = SaveData.best_time(info["id"])
		var text: String = "%d   %s" % [i + 1, info["name"]]
		if not unlocked:
			text += "     (locked)"
		elif best >= 0.0:
			text += "     best %s" % SaveData.format_time(best)
			var ff: int = SaveData.fewest_falls(info["id"])
			if ff >= 0:
				text += "   falls %d" % ff
		var b: Button = UiKit.button(text, func() -> void: Game.play_level(i), 520)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked
		b.tooltip_text = info["blurb"]
		box.add_child(b)
	box.add_child(UiKit.button("Back", func() -> void: show_screen("main"), 520))
	return _left_column(box, 540)


func _settings_screen() -> Control:
	var sp := SettingsPanel.new()
	sp.closed.connect(func() -> void: show_screen("main"))
	return UiKit.centered(sp)


func _victory_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.label("THE BEACON IS LIT", 22, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("Circuit Complete", 54, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var total: float = 0.0
	var all_done: bool = true
	for info: Dictionary in Game.LEVELS:
		var best: float = SaveData.best_time(info["id"])
		all_done = all_done and best >= 0.0
		total += maxf(best, 0.0)
		box.add_child(UiKit.label("%s     %s" % [info["name"], SaveData.format_time(best)], 22, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	if all_done:
		box.add_child(UiKit.label("Sum of bests   %s" % SaveData.format_time(total), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("Every course has a faster line. Go find it - or race your friends.", 18, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.button("Level Select", func() -> void: show_screen("levels")))
	box.add_child(UiKit.button("Title", func() -> void: show_screen("main")))
	var p: PanelContainer = UiKit.panel(Vector2(620, 0))
	p.add_child(box)
	return UiKit.centered(p)


# ---- multiplayer --------------------------------------------------------------------------------------

func _identity_row() -> Control:
	var row: HBoxContainer = UiKit.hbox(10)
	var name_edit := LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.max_length = 14
	name_edit.custom_minimum_size = Vector2(220, 44)
	name_edit.placeholder_text = "Your name"
	name_edit.text_changed.connect(func(t: String) -> void:
		Settings.player_name = t.strip_edges() if t.strip_edges() != "" else "Runner"
		Settings.save_settings()
		Net.update_identity())
	row.add_child(name_edit)
	for i: int in Settings.RACER_COLORS.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(36, 44)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Settings.RACER_COLORS[i]
		sb.set_corner_radius_all(8)
		if i == Settings.color_index:
			sb.border_color = Color.WHITE
			sb.set_border_width_all(3)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			sw.add_theme_stylebox_override(state, sb)
		sw.pressed.connect(func() -> void:
			Settings.color_index = i
			Settings.save_settings()
			_volt.set_accent(Settings.my_color())
			Net.update_identity()
			show_screen(Game.title_screen))
		row.add_child(sw)
	return row


func _race_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label("RACE FRIENDS", 36, Color.WHITE))
	box.add_child(UiKit.label("Up to 8 players. Everyone runs the same course at once;\nyou see each other live but never collide.", 17, UiKit.SOFT))
	box.add_child(_identity_row())
	box.add_child(UiKit.button("Host a Race", func() -> void:
		var err: Error = Net.host()
		if err != OK:
			_set_status("Could not open port %d (is another host running?)." % Net.PORT), 440))
	var join_row: HBoxContainer = UiKit.hbox(10)
	var ip := LineEdit.new()
	ip.text = Settings.last_ip
	ip.placeholder_text = "Host address"
	ip.custom_minimum_size = Vector2(250, 48)
	join_row.add_child(ip)
	join_row.add_child(UiKit.button("Join", func() -> void:
		Settings.last_ip = ip.text.strip_edges()
		Settings.save_settings()
		_set_status("Connecting to %s ..." % ip.text)
		var err: Error = Net.join(ip.text)
		if err != OK:
			_set_status("That address does not look right."), 180))
	box.add_child(join_row)
	_status = UiKit.label(Game.title_message, 17, Color(1, 0.7, 0.55))
	Game.title_message = ""
	box.add_child(_status)
	box.add_child(UiKit.button("Back", func() -> void:
		Net.leave()
		show_screen("main"), 440))
	var p: PanelContainer = UiKit.panel(Vector2(560, 0))
	p.add_child(box)
	return _left_column(p, 580)


func _set_status(text: String) -> void:
	if _status != null and is_instance_valid(_status):
		_status.text = text


func _lobby_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.label("RACE LOBBY", 36, Color.WHITE))
	if Net.is_host():
		var addrs: Array[String] = Net.local_addresses()
		box.add_child(UiKit.label("Friends on your network join:  %s" % ("  or  ".join(addrs) if not addrs.is_empty() else "(no LAN address found)"), 17, UiKit.TEAL))
		_upnp_label = UiKit.label("Checking for automatic internet port forwarding (UDP %d)..." % Net.PORT, 15, UiKit.SOFT)
		_upnp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_upnp_label.custom_minimum_size = Vector2(520, 0)
		box.add_child(_upnp_label)
		Net.try_upnp()
	else:
		box.add_child(UiKit.label("Connected. The host picks the course and starts the race.", 17, UiKit.TEAL))
	box.add_child(_identity_row())
	_roster_box = UiKit.vbox(4)
	box.add_child(_roster_box)
	if Net.is_host():
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(0, 46)
		for info: Dictionary in Game.LEVELS:
			pick.add_item(str(info["name"]))
		pick.selected = _lobby_level
		pick.item_selected.connect(func(i: int) -> void: _lobby_level = i)
		box.add_child(pick)
		_start_button = UiKit.button("Start Race", func() -> void: Net.host_start_race(_lobby_level), 520)
		box.add_child(_start_button)
	box.add_child(UiKit.button("Leave", func() -> void:
		Net.leave()
		show_screen("race"), 520))
	var p: PanelContainer = UiKit.panel(Vector2(580, 0))
	p.add_child(box)
	_refresh_lobby.call_deferred()
	return _left_column(p, 600)


func _refresh_lobby() -> void:
	if _roster_box == null or not is_instance_valid(_roster_box):
		return
	for c: Node in _roster_box.get_children():
		c.queue_free()
	_roster_box.add_child(UiKit.label("RACERS  (%d/%d)" % [Net.roster.size(), Net.MAX_PLAYERS], 15, UiKit.SOFT))
	var ids: Array = Net.roster.keys()
	ids.sort()
	for id: int in ids:
		var e: Dictionary = Net.roster[id]
		var col: Color = Settings.RACER_COLORS[int(e["color"]) % Settings.RACER_COLORS.size()]
		var tag: String = "  (host)" if id == 1 else ""
		if id == Net.my_id():
			tag += "  (you)"
		var last: String = ""
		if float(e.get("finished", -1.0)) >= 0.0:
			last = "     last race %s" % SaveData.format_time(float(e["finished"]))
		_roster_box.add_child(UiKit.label("%s%s%s" % [e["name"], tag, last], 22, col.lerp(Color.WHITE, 0.3)))
