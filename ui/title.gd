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
## Control a screen builder wants focused first (keyboard / gamepad start point).
var _focus_pref: Control
## Screen shown before the current one: main re-focuses the button that opened it.
var _prev_screen: String = ""
## Main menu controls line; follows the device in use.
var _controls_hint: Label
## Lobby: the game mode and its blurb (+ Party Cup progress).
var _mode_label: Label
var _update_status: Label
var _update_button: Button
var _update_secondary_buttons: Array[Button] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_title("Jump Circuit v%s" % Updater.current_version())
	_build_diorama()
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiKit.theme()
	layer.add_child(_ui)
	Game.input_device_changed.connect(_update_controls_hint)
	Net.roster_changed.connect(_refresh_lobby)
	Net.joined_lobby.connect(func() -> void:
		_volt.set_accent(Settings.my_color())   # the host may have assigned us a free colour
		show_screen("lobby"))
	Net.connection_failed.connect(func(reason: String) -> void:
		Game.title_message = reason
		show_screen("race"))
	# the host's course picker starts on the last raced course (rematch = one click)
	if Net.race_level >= 0:
		_lobby_level = clampi(Net.race_level, 0, Game.LEVELS.size() - 1)
	Updater.update_available.connect(func(_info: Dictionary) -> void:
		if Game.title_screen == "main":
			show_screen("main"))   # redirects to the update prompt (see show_screen)
	Updater.install_status_changed.connect(_on_update_status_changed)
	Updater.install_progress.connect(_on_update_progress)
	Updater.install_failed.connect(_on_update_failed)
	var want: String = Game.title_screen
	if (want == "lobby" and not Net.active) or want == "update":
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
	add_child(Soundscape.make("title"))


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
	# a newer release on GitHub: the first visit to the main menu asks once per launch
	if id == "main" and not Updater.available.is_empty() and not Updater.prompted:
		id = "update"
	if _screen != null:
		_screen.queue_free()
	_roster_box = null
	_status = null
	_start_button = null
	_mode_label = null
	_focus_pref = null
	_prev_screen = Game.title_screen
	Game.title_screen = id
	# a race host may have lent us another colour; leaving the session gives ours back
	_volt.set_accent(Settings.my_color())
	match id:
		"levels":
			_screen = _levels_screen()
		"race":
			_screen = _race_screen()
		"lobby":
			_screen = _lobby_screen()
		"settings":
			_screen = _settings_screen()
		"practice":
			_screen = _practice_screen()
		"victory":
			_screen = _victory_screen()
		"update":
			_screen = _update_screen()
		_:
			_screen = _main_screen()
	_ui.add_child(_screen)
	UiKit.focus_first(_screen, _focus_pref)
	Sfx.music(screen_music(id))


## The score behind each title screen: the main theme on the menus, the lobby groove while
## getting a race or party together, the grand reprise once every course is beaten.
static func screen_music(id: String) -> String:
	match id:
		"race", "lobby", "practice":
			return "lobby"
		"victory":
			return "victory"
	return "title"


## Esc / pad B backs out of a sub-screen exactly like its Back / Done / Leave button.
## A focused LineEdit or an open dropdown consumes Esc before it gets here.
func _unhandled_input(event: InputEvent) -> void:
	# nothing focused (e.g. after a mouse click on a text box that then went away):
	# the first stick / D-pad / A press picks the screen's starting button
	if Game.is_menu_nav(event) and get_viewport().gui_get_focus_owner() == null and _screen != null:
		UiKit.focus_first(_screen, _focus_pref)
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	match Game.title_screen:
		"levels", "victory", "update", "practice":
			show_screen("main")
		"settings":
			Settings.save_settings()  # same as the panel's Done
			show_screen("main")
		"race":
			Net.leave()
			show_screen("main")
		"lobby":
			if Net.is_host():
				return  # a stray Esc must not disband everyone's lobby: use Leave
			Net.leave()
			show_screen("race")
		_:
			return
	Sfx.play("ui", 0.05, 0.6)
	get_viewport().set_input_as_handled()


func _update_controls_hint(pad: bool) -> void:
	if _controls_hint == null or not is_instance_valid(_controls_hint):
		return
	_controls_hint.text = "Left stick move   A jump   Right stick look   Y retry   Start pause" if pad 		else "WASD move   Space jump   Mouse look   R retry   Esc pause"


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
	var levels_btn: Button = UiKit.button("Level Select", func() -> void: show_screen("levels"), 380)
	box.add_child(levels_btn)
	var race_btn: Button = UiKit.button("Race Friends", func() -> void: show_screen("race"), 380)
	box.add_child(race_btn)
	var practice_btn: Button = UiKit.button(PartyNames.mode_name("practice"), func() -> void: show_screen("practice"), 380)
	box.add_child(practice_btn)
	var settings_btn: Button = UiKit.button("Settings", func() -> void: show_screen("settings"), 380)
	box.add_child(settings_btn)
	if Game.dev_mode:
		box.add_child(UiKit.button("Playground (dev)", func() -> void: Game.play_playground(), 380))
	box.add_child(UiKit.button("Quit", func() -> void: Sfx.quit(), 380))
	if not Updater.available.is_empty():
		box.add_child(UiKit.button("Get update  -  v%s" % Updater.available["version"], func() -> void: show_screen("update"), 380))
	if Game.title_message != "":
		box.add_child(UiKit.shadowed(UiKit.label(Game.title_message, 18, Color(1, 0.6, 0.5))))
		Game.title_message = ""
	_controls_hint = UiKit.shadowed(UiKit.label("", 16, Color(1, 1, 1, 0.75)), 5)
	box.add_child(_controls_hint)
	_update_controls_hint(Game.using_pad)
	box.add_child(UiKit.shadowed(UiKit.label("v%s" % Updater.current_version(), 15, UiKit.SOFT), 4))
	var openers: Dictionary = {"levels": levels_btn, "race": race_btn, "lobby": race_btn, "settings": settings_btn, "practice": practice_btn}
	_focus_pref = openers.get(_prev_screen, play)
	return _left_column(box)


## Newer release: what's new and a direct download/install action.
func _update_screen() -> Control:
	Updater.prompted = true
	var info: Dictionary = Updater.available
	_update_status = null
	_update_button = null
	_update_secondary_buttons.clear()
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.shadowed(UiKit.label("UPDATE AVAILABLE", 40, UiKit.GOLD), 8))
	box.add_child(UiKit.shadowed(UiKit.label("Jump Circuit v%s is out  -  you have v%s." % [info.get("version", "?"), Updater.current_version()], 22, Color.WHITE), 6))
	var notes_text: String = str(info.get("notes", ""))
	if notes_text != "":
		var notes: Label = UiKit.label(notes_text, 17, UiKit.SOFT)
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notes.custom_minimum_size = Vector2(520, 0)
		var panel: PanelContainer = UiKit.panel()
		panel.add_child(notes)
		box.add_child(panel)
	var instructions: Label = UiKit.shadowed(UiKit.label("The game will download and install the update, then restart automatically.
Your progress and settings are kept.", 16, Color(1, 1, 1, 0.75)), 5)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.custom_minimum_size = Vector2(520, 0)
	box.add_child(instructions)
	_update_status = UiKit.label("Ready to install.", 16, UiKit.SOFT)
	_update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_status.custom_minimum_size = Vector2(520, 0)
	box.add_child(_update_status)
	_update_button = UiKit.button("Install & Restart", func() -> void:
		if _update_button != null:
			_update_button.disabled = true
		for button: Button in _update_secondary_buttons:
			button.disabled = true
		Updater.install_update(), 380)
	box.add_child(_update_button)
	var remind_button: Button = UiKit.button("Remind Me Later", func() -> void: show_screen("main"), 380)
	_update_secondary_buttons.append(remind_button)
	box.add_child(remind_button)
	var skip_button: Button = UiKit.button("Skip This Version", func() -> void:
		Updater.skip_version()
		show_screen("main"), 380)
	_update_secondary_buttons.append(skip_button)
	box.add_child(skip_button)
	_focus_pref = _update_button
	return _left_column(box, 560.0)


func _on_update_status_changed(message: String) -> void:
	if _update_status != null and is_instance_valid(_update_status):
		_update_status.text = message


func _on_update_progress(downloaded_bytes: int, total_bytes: int) -> void:
	if _update_status == null or not is_instance_valid(_update_status):
		return
	var downloaded_mb: float = float(downloaded_bytes) / 1048576.0
	if total_bytes > 0:
		var total_mb: float = float(total_bytes) / 1048576.0
		var percentage: int = int(100.0 * downloaded_bytes / total_bytes)
		_update_status.text = "Downloading update... %d%% (%.1f / %.1f MB)" % [percentage, downloaded_mb, total_mb]
	else:
		_update_status.text = "Downloading update... %.1f MB" % downloaded_mb


func _on_update_failed(message: String) -> void:
	if _update_button != null and is_instance_valid(_update_button):
		_update_button.disabled = false
		_update_button.text = "Retry Update"
	for button: Button in _update_secondary_buttons:
		if is_instance_valid(button):
			button.disabled = false
	_on_update_status_changed(message)


func _levels_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.shadowed(UiKit.label("LEVEL SELECT", 40, Color.WHITE), 8))
	var first_open: Button = null
	var last_unlocked: Button = null
	# nine courses outgrow a 720p screen: the list scrolls, following the pad / keyboard focus
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var list: VBoxContainer = UiKit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var rows_h: float = float(Game.LEVELS.size()) * 58.0
	scroll.custom_minimum_size = Vector2(532, clampf(rows_h, 180.0, get_viewport().get_visible_rect().size.y - 250.0))
	box.add_child(scroll)
	for i: int in Game.LEVELS.size():
		var info: Dictionary = Game.LEVELS[i]
		var unlocked: bool = Game.is_level_unlocked(i)
		var best: float = SaveData.best_time(info["id"])
		var text: String = "%d   %s" % [i + 1, info["name"]]
		if not unlocked:
			text += "     (clear %s to unlock)" % Game.LEVELS[i - 1]["name"]
		elif best >= 0.0:
			text += "     best %s" % SaveData.format_time(best)
			var ff: int = SaveData.fewest_falls(info["id"])
			if ff >= 0:
				text += "   fewest falls %d" % ff
		var b: Button = UiKit.button(text, func() -> void: Game.play_level(i), 520)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked
		b.tooltip_text = info["blurb"]
		list.add_child(b)
		if unlocked:
			last_unlocked = b
			if first_open == null and not SaveData.is_completed(info["id"]):
				first_open = b
	# start on the first level still to clear (else the last unlocked one)
	_focus_pref = first_open if first_open != null else last_unlocked
	box.add_child(UiKit.button("Back", func() -> void: show_screen("main"), 520))
	return _left_column(box, 540)


## Party Practice: pick any unlocked course; the right column lists every power-up.
func _practice_screen() -> Control:
	var root: HBoxContainer = UiKit.hbox(40)
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.shadowed(UiKit.label(PartyNames.mode_name("practice").to_upper(), 40, Color.WHITE), 8))
	var blurb: Label = UiKit.shadowed(UiKit.label(PartyNames.MODE_BLURBS["practice"], 17, UiKit.SOFT), 5)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(520, 0)
	box.add_child(blurb)
	var first: Button = null
	for i: int in Game.LEVELS.size():
		var unlocked: bool = Game.is_level_unlocked(i)
		var text: String = "%d   %s" % [i + 1, Game.LEVELS[i]["name"]]
		if not unlocked:
			text += "     (locked)"
		var b: Button = UiKit.button(text, func() -> void: Game.play_party_practice(i), 520)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked
		box.add_child(b)
		if unlocked and first == null:
			first = b
	box.add_child(UiKit.button("Back", func() -> void: show_screen("main"), 520))
	var keys: String = "Attack %s    Use item %s    Shove %s    Next tool %s" % [Game.prompt("attack"), Game.prompt("use_item"), Game.prompt("shove"), Game.prompt("cycle_item")]
	box.add_child(UiKit.shadowed(UiKit.label(keys, 16, Color(1, 1, 1, 0.8)), 5))
	root.add_child(box)
	# the power-up list
	var list_panel: PanelContainer = UiKit.panel(Vector2(560, 0))
	var list: VBoxContainer = UiKit.vbox(4)
	list_panel.add_child(list)
	list.add_child(UiKit.label("POWER-UPS", 16, UiKit.TEAL))
	for id: String in PartyItems.PRACTICE_ORDER:
		var row: HBoxContainer = UiKit.hbox(10)
		var icon := PartyIcon.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.item_id = id
		row.add_child(icon)
		var txt: VBoxContainer = UiKit.vbox(0)
		txt.add_child(UiKit.label(PartyNames.item_name(id), 17, PartyNames.item_color(id).lightened(0.3)))
		var d: Label = UiKit.label(PartyNames.item_desc(id), 13, UiKit.SOFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(470, 0)
		txt.add_child(d)
		row.add_child(txt)
		list.add_child(row)
	root.add_child(list_panel)
	_focus_pref = first
	return _left_column(root, 1140)


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
	_focus_pref = UiKit.button("Level Select", func() -> void: show_screen("levels"))
	box.add_child(_focus_pref)
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
	var styles: Array[StyleBoxFlat] = []
	for i: int in Settings.RACER_COLORS.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(36, 44)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Settings.RACER_COLORS[i]
		sb.set_corner_radius_all(8)
		sb.border_color = Color.WHITE
		sb.set_border_width_all(3 if i == Settings.color_index else 0)
		styles.append(sb)
		# ("focus" keeps the theme's gold ring, so keyboard / pad users can see where they are)
		for state: String in ["normal", "hover", "pressed"]:
			sw.add_theme_stylebox_override(state, sb)
		# restyle in place: rebuilding the screen would wipe a typed address and status
		sw.pressed.connect(func() -> void:
			Settings.color_index = i
			Net.preferred_color = -1   # an explicit pick is the player's colour from now on
			Settings.save_settings()
			for j: int in styles.size():
				styles[j].set_border_width_all(3 if j == i else 0)
			_volt.set_accent(Settings.my_color())
			Net.update_identity())
		row.add_child(sw)
	return row


func _race_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label("RACE FRIENDS", 36, Color.WHITE))
	box.add_child(UiKit.label("Up to 8 players. Share a room code to race;\nno router setup or VPN needed.", 17, UiKit.SOFT))
	box.add_child(_identity_row())
	var host_button: Button = UiKit.button("Host a Race", func() -> void:
		var err: Error = Net.host_room()
		if err != OK:
			_set_status("Could not start the relay connection. Check network/relay_url; see docs/RELAY.md."), 440)
	box.add_child(host_button)
	var join_row: HBoxContainer = UiKit.hbox(10)
	var room_input := LineEdit.new()
	room_input.text = Settings.last_room_code
	room_input.placeholder_text = "8-character room code"
	room_input.custom_minimum_size = Vector2(250, 48)
	room_input.max_length = 12
	# Keep what was typed across rebuilds (Back, a failed join).
	room_input.text_changed.connect(func(t: String) -> void: Settings.last_room_code = t.strip_edges().to_upper())
	join_row.add_child(room_input)
	var do_join := func() -> void:
		var code: String = Net._clean_room_code(room_input.text)
		if not Net._valid_room_code(code):
			_set_status("Enter the 8-character room code from the host.")
			return
		Settings.last_room_code = code
		Settings.save_settings()
		_set_status("Joining room %s ...  (Back cancels)" % code)
		var err: Error = Net.join_room(code)
		if err != OK:
			_set_status("Could not start the relay connection. Check network/relay_url; see docs/RELAY.md.")
	join_row.add_child(UiKit.button("Join", do_join, 180))
	room_input.text_submitted.connect(func(_t: String) -> void: do_join.call())
	box.add_child(join_row)
	_status = UiKit.label(Game.title_message, 17, Color(1, 0.7, 0.55))
	Game.title_message = ""
	box.add_child(_status)
	box.add_child(UiKit.button("Back", func() -> void:
		Net.leave()
		show_screen("main"), 440))
	var p: PanelContainer = UiKit.panel(Vector2(560, 0))
	p.add_child(box)
	_focus_pref = host_button
	return _left_column(p, 580)


func _set_status(text: String) -> void:
	if _status != null and is_instance_valid(_status):
		_status.text = text


func _lobby_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.label("RACE LOBBY", 36, Color.WHITE))
	if Net.is_host():
		var code_row: HBoxContainer = UiKit.hbox(10)
		code_row.add_child(UiKit.label("ROOM CODE   %s" % Net.room_code, 23, UiKit.TEAL))
		var copy_button: Button = UiKit.button("Copy", func() -> void:
			DisplayServer.clipboard_set(Net.room_code), 120)
		copy_button.pressed.connect(func() -> void: copy_button.text = "Copied!")
		code_row.add_child(copy_button)
		box.add_child(code_row)
		box.add_child(UiKit.label("Send this code to your friends. They enter it under Race Friends.", 15, UiKit.SOFT))
	else:
		box.add_child(UiKit.label("Connected. The host picks the course and starts the race.", 17, UiKit.TEAL))
	box.add_child(_identity_row())
	if Net.is_host():
		# game mode: Race (unchanged classic), Party, Team Party
		var modes: Array[String] = ["race", "party", "team"]
		var mode_pick := OptionButton.new()
		mode_pick.custom_minimum_size = Vector2(0, 46)
		for m: String in modes:
			mode_pick.add_item("Mode:  %s" % PartyNames.mode_name(m))
		mode_pick.selected = maxi(modes.find(Net.game_mode), 0)
		mode_pick.item_selected.connect(func(i: int) -> void: Net.host_set_mode(modes[i]))
		box.add_child(mode_pick)
	_mode_label = UiKit.label("", 15, UiKit.SOFT)
	_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_label.custom_minimum_size = Vector2(520, 0)
	box.add_child(_mode_label)
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
	var leave: Button = UiKit.button("Leave", func() -> void:
		Net.leave()
		show_screen("race"), 520)
	box.add_child(leave)
	var p: PanelContainer = UiKit.panel(Vector2(580, 0))
	p.add_child(box)
	_refresh_lobby.call_deferred()
	_focus_pref = _start_button if _start_button != null else leave
	return _left_column(p, 600)


func _refresh_lobby() -> void:
	if _roster_box == null or not is_instance_valid(_roster_box):
		return
	# a rebuild must not drop a pad user's focus off the team Swap button they are on
	var keep_swap: int = 0
	var f: Control = get_viewport().gui_get_focus_owner()
	if f != null and _roster_box.is_ancestor_of(f) and f.has_meta("swap_id"):
		keep_swap = int(f.get_meta("swap_id"))
	for c: Node in _roster_box.get_children():
		_roster_box.remove_child(c)
		c.queue_free()
	var mode: String = Net.game_mode
	var team: bool = mode == "team"
	if _mode_label != null and is_instance_valid(_mode_label):
		var t: String = "%s:  %s" % [PartyNames.mode_name(mode), PartyNames.MODE_BLURBS.get(mode, "")]
		if mode != "race" and Net.party_round > 0:
			t += "\n%s: %d round%s played - the next race is round %d." % [PartyNames.CUP, Net.party_round, "" if Net.party_round == 1 else "s", Net.party_round + 1]
		_mode_label.text = t
		_mode_label.add_theme_color_override("font_color", UiKit.GOLD if mode != "race" else UiKit.SOFT)
	if _start_button != null and is_instance_valid(_start_button):
		_start_button.text = "Start Race" if mode == "race" else "Start Round %d" % (Net.party_round + 1)
	_roster_box.add_child(UiKit.label("RACERS  (%d/%d)" % [Net.roster.size(), Net.MAX_PLAYERS], 15, UiKit.SOFT))
	var ids: Array = Net.roster.keys()
	ids.sort()
	if team:
		# grouped by team, each in its team colour
		ids.sort_custom(func(a: int, b: int) -> bool:
			return Net.team_of(a) < Net.team_of(b) or (Net.team_of(a) == Net.team_of(b) and a < b))
	var regrab: Button = null
	for id: int in ids:
		var e: Dictionary = Net.roster[id]
		var col: Color = Settings.RACER_COLORS[int(e["color"]) % Settings.RACER_COLORS.size()]
		var tag: String = "  (host)" if id == 1 else ""
		if id == Net.my_id():
			tag += "  (you)"
		var last: String = ""
		if float(e.get("finished", -1.0)) >= 0.0 and mode == "race":
			last = "     last race %s" % SaveData.format_time(float(e["finished"]))
		var cup: String = ""
		if mode != "race" and Net.party_round > 0 and Game.party != null and Game.party.cup.has(id):
			cup = "     cup %d" % int(Game.party.cup[id])
		if not team:
			_roster_box.add_child(UiKit.label("%s%s%s%s" % [e["name"], tag, last, cup], 22, col.lerp(Color.WHITE, 0.3)))
			continue
		var tm: int = Net.team_of(id)
		var row: HBoxContainer = UiKit.hbox(10)
		var l: Label = UiKit.label("[%s]  %s%s%s" % [PartyNames.team_name(tm), e["name"], tag, cup], 22, PartyNames.team_color(tm).lerp(Color.WHITE, 0.25))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if Net.is_host():
			var other: int = 1 - tm
			var swap: Button = UiKit.button("Move to %s" % PartyNames.team_name(other), func() -> void: Net.host_set_team(id, other), 190)
			swap.custom_minimum_size.y = 40
			swap.set_meta("swap_id", id)
			row.add_child(swap)
			if id == keep_swap:
				regrab = swap
		_roster_box.add_child(row)
	if team:
		var sizes: Array[int] = [0, 0]
		for id: int in ids:
			sizes[Net.team_of(id)] += 1
		_roster_box.add_child(UiKit.label("%s %d  vs  %d %s" % [PartyNames.team_name(0), sizes[0], sizes[1], PartyNames.team_name(1)], 16, UiKit.SOFT))
	if regrab != null:
		regrab.grab_focus.call_deferred()
	if Net.is_host() and mode != "race" and Net.party_round > 0:
		var reset: Button = UiKit.button("Start a New %s" % PartyNames.CUP, func() -> void: Net.host_reset_cup(), 300)
		reset.name = "ResetCup"
		_roster_box.add_child(reset)
