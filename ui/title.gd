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
## Locker: the line describing the focused item, and whether picks are written to
## settings.cfg (tests turn it off so they never touch the player's real settings).
var _locker_info: Label
var persist_settings: bool = true


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
	Net.connection_interrupted.connect(func(_detail: String) -> void: _set_status("Connection lost - reconnecting..."))
	Net.connection_restored.connect(func() -> void: _set_status("Reconnected."))
	Net.relay_notice.connect(func(text: String) -> void: _set_status(text))
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
	_wear_equipped()
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
	if Game.title_screen == "locker":
		_locker_preview(dt)
		return
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
	_locker_info = null
	if id != "locker":
		_wear_equipped()
		_volt.position = Vector3(1.5, maxf(_volt_y, 0.2), 0.5)   # back on the pad after the Locker's laps
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
		"partycpu":
			_screen = _partycpu_screen()
		"locker":
			_screen = _locker_screen()
		"victory":
			_screen = _victory_screen()
		"challenges":
			var ch: Dictionary = ExtraScreens.challenges_screen(func() -> void: show_screen("main"), func(i: int) -> void: Game.play_level(i))
			_screen = _left_column(ch["root"], 780)
			_focus_pref = ch["focus"]
		"stats":
			var st: Dictionary = ExtraScreens.stats_screen(func() -> void: show_screen("main"))
			_screen = _left_column(st["root"], 780)
			_focus_pref = st["focus"]
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
		"race", "lobby", "practice", "partycpu":
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
	if Game.title_screen == "locker" and not event.is_echo():
		if event.is_action_pressed("spectate_prev") or event.is_action_pressed("spectate_next"):
			set_locker_tab(locker_tab + (1 if event.is_action_pressed("spectate_next") else -1))
			get_viewport().set_input_as_handled()
			return
	if not event.is_action_pressed("ui_cancel"):
		return
	match Game.title_screen:
		"levels", "victory", "update", "practice", "locker", "challenges", "stats", "partycpu":
			show_screen("main")
		"settings":
			Settings.save_settings()  # same as the panel's Done
			show_screen("main")
		"race":
			Net.leave()
			show_screen("main")
		"lobby":
			if Net.local_session:
				Net.leave()
				show_screen("main")
				Sfx.play("ui", 0.05, 0.6)
				get_viewport().set_input_as_handled()
				return
			if Net.is_host():
				return  # a stray Esc must not disband everyone's lobby: use Leave
			Net.leave()
			show_screen("race")
		_:
			return
	Sfx.play("ui", 0.05, 0.6)
	get_viewport().set_input_as_handled()


## The Locker's key line follows the device in hand (LB / RB with a pad, Q / E on the keyboard).
func _refresh_locker_hint() -> void:
	if _locker_tab_hint == null or not is_instance_valid(_locker_tab_hint):
		return
	_locker_tab_hint.text = "%s / %s  switch tabs      %s  equip      %s  back" % [Game.prompt("spectate_prev"), Game.prompt("spectate_next"),
		"A" if Game.using_pad else "Enter", Game.prompt("back")]


func _update_controls_hint(pad: bool) -> void:
	_refresh_locker_hint()
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
	var l1: Label = UiKit.shadowed(UiKit.label("JUMP", 84, Color.WHITE), 12)
	var l2: Label = UiKit.shadowed(UiKit.label("CIRCUIT", 84, UiKit.GOLD), 12)
	v.add_child(l1)
	v.add_child(l2)
	v.add_child(UiKit.shadowed(UiKit.label("read the course  -  build momentum  -  land it", 20, UiKit.SOFT), 6))
	return v


func _main_screen() -> Control:
	# everything must fit the 900 px canvas: logo, seven buttons, the hint line and an
	# unlock note or update button (the column has no scroll). Tighter rows since Party vs CPU joined.
	var box: VBoxContainer = UiKit.vbox(6)
	box.add_child(_logo())
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
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
	# Challenges and Stats share a row so the column keeps its height
	var extras: HBoxContainer = UiKit.hbox(8)
	var challenges_btn: Button = UiKit.button("Challenges", func() -> void: show_screen("challenges"), 186)
	var stats_btn: Button = UiKit.button("Stats", func() -> void: show_screen("stats"), 186)
	extras.add_child(challenges_btn)
	extras.add_child(stats_btn)
	box.add_child(extras)
	var race_btn: Button = UiKit.button("Race Friends", func() -> void: show_screen("race"), 380)
	box.add_child(race_btn)
	var practice_btn: Button = UiKit.button(PartyNames.mode_name("practice"), func() -> void: show_screen("practice"), 380)
	box.add_child(practice_btn)
	var partycpu_btn: Button = UiKit.button("Party vs CPU", func() -> void: show_screen("partycpu"), 380)
	box.add_child(partycpu_btn)
	var locker_btn: Button = UiKit.button("Locker", func() -> void: show_screen("locker"), 380)
	box.add_child(locker_btn)
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
	# the controls hint and the version share one line
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	_controls_hint = UiKit.shadowed(UiKit.label("", 16, Color(1, 1, 1, 0.75)), 5)
	foot.add_child(_controls_hint)
	foot.add_child(UiKit.shadowed(UiKit.label("v%s" % Updater.current_version(), 15, UiKit.SOFT), 4))
	box.add_child(foot)
	_update_controls_hint(Game.using_pad)
	# cosmetics earned by progress made before they existed (or not yet announced)
	var fresh: Array[Array] = Cosmetics.check_unlocks()
	if not fresh.is_empty():
		var names: Array[String] = []
		for f: Array in fresh:
			names.append(Cosmetics.display_name(f[0], f[1]))
		if names.size() > 5:
			# a save from before medals can earn a pile at once: name a few
			var more: int = names.size() - 4
			names.resize(4)
			names.append("and %d more" % more)
		var note: Label = UiKit.shadowed(UiKit.label("Unlocked: %s!  See the Locker." % ", ".join(names), 16, UiKit.GOLD), 5)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(420, 0)
		# it takes the spacer's place, so the buttons don't get pushed off the bottom
		box.add_child(note)
		box.move_child(note, 1)
		spacer.queue_free()
	var openers: Dictionary = {"levels": levels_btn, "race": race_btn, "lobby": race_btn, "settings": settings_btn, "practice": practice_btn, "locker": locker_btn, "challenges": challenges_btn, "stats": stats_btn, "partycpu": partycpu_btn}
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
	scroll.custom_minimum_size = Vector2(772, clampf(rows_h, 180.0, get_viewport().get_visible_rect().size.y - 250.0))
	box.add_child(scroll)
	for i: int in Game.LEVELS.size():
		var info: Dictionary = Game.LEVELS[i]
		var unlocked: bool = Game.is_level_unlocked(i)
		var best: float = SaveData.best_time(info["id"])
		var text: String = "%d   %s" % [i + 1, info["name"]]
		var medal: int = SaveData.medal(info["id"])
		if not unlocked:
			text += "     (clear %s to unlock)" % Game.LEVELS[i - 1]["name"]
		else:
			if best >= 0.0:
				text += "     best %s" % SaveData.format_time(best)
				var ff: int = SaveData.fewest_falls(info["id"])
				if ff >= 0:
					text += "   falls %d" % ff
			text += level_medal_text(info["id"], medal, best >= 0.0 or SaveData.is_completed(info["id"]))
		var b: Button = UiKit.button(text, func() -> void: Game.play_level(i), 760)
		b.set_meta("medal", medal)
		if medal > 0:
			b.add_theme_color_override("font_color", Hud.medal_color(medal).lerp(Color.WHITE, 0.35))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked
		b.tooltip_text = info["blurb"]
		_add_challenge_pips(b, info["id"])
		list.add_child(b)
		if unlocked:
			last_unlocked = b
			if first_open == null and not SaveData.is_completed(info["id"]):
				first_open = b
	# start on the first level still to clear (else the last unlocked one)
	_focus_pref = first_open if first_open != null else last_unlocked
	box.add_child(UiKit.button("Back", func() -> void: show_screen("main"), 760))
	return _left_column(box, 780)


## Three pips at a level row's right edge: one lit per course challenge done.
func _add_challenge_pips(b: Button, level_id: String) -> void:
	var n: int = Challenges.level_count(level_id)
	b.set_meta("challenges", n)
	var row: HBoxContainer = UiKit.hbox(5)
	row.name = "Pips"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	for k: int in Challenges.KINDS.size():
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.color = UiKit.GOLD if k < n else Color(1, 1, 1, 0.2)
		row.add_child(pip)
	b.add_child(row)


## Level select's medal part of a row: "   SILVER  -  next Gold 2:40" (the medal is held
## from the faster of the current best and a legacy one). `played` = the course has a clear,
## so the first target is worth showing.
static func level_medal_text(level_id: String, medal: int, played: bool) -> String:
	if Game.medal_targets(level_id).is_empty():
		return ""
	var out: String = ""
	if medal > 0:
		out += "   %s" % Cosmetics.MEDAL_NAMES[medal].to_upper()
	if (played or medal > 0) and medal < 3:
		out += "  -  next %s %s" % [Cosmetics.MEDAL_NAMES[medal + 1], Hud.target_text(Game.medal_target(level_id, medal + 1))]
	elif not played and medal == 0:
		# a course not yet run still shows what Gold asks for
		out += "     Gold target %s" % Hud.target_text(Game.medal_target(level_id, 3))
	return out


## Party vs CPU: the solo party-cup setup (mode, CPU count, difficulty, course) - see party/cpu/cpu_menu.gd.
func _partycpu_screen() -> Control:
	var built: Dictionary = CpuMenu.build_screen(self)
	_focus_pref = built["focus"]
	return _left_column(built["content"], 560)


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
	var list_panel: PanelContainer = UiKit.panel(Vector2(740, 0))
	var list: VBoxContainer = UiKit.vbox(4)
	list_panel.add_child(list)
	list.add_child(UiKit.label("POWER-UPS", 16, UiKit.TEAL))
	# two columns: 21 power-ups no longer fit one
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	list.add_child(grid)
	for id: String in PartyItems.PRACTICE_ORDER:
		var row: HBoxContainer = UiKit.hbox(10)
		var icon := PartyIcon.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.item_id = id
		row.add_child(icon)
		var txt: VBoxContainer = UiKit.vbox(0)
		txt.add_child(UiKit.label(PartyNames.item_name(id), 17, PartyNames.item_color(id).lightened(0.3)))
		var d: Label = UiKit.label(PartyNames.item_desc(id), 12, UiKit.SOFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
		txt.add_child(d)
		row.add_child(txt)
		grid.add_child(row)
	root.add_child(list_panel)
	_focus_pref = first
	return _left_column(root, 1340)


# ---- locker (characters, hats, paints, trails, finishes, titles, colour) ---------------------------

## Locker tabs, in order: one per Cosmetics kind, then the racer colour. LB / RB (Q / E)
## switch tabs; the tab buttons are for the mouse (pad focus stays in the grid).
const LOCKER_TABS: Array[String] = ["character", "hat", "paint", "trail", "finish", "title", "emote", "pose", "colour"]
const LOCKER_COLUMNS: Dictionary = {"character": 5, "hat": 5, "paint": 4, "trail": 5, "finish": 3, "title": 4, "emote": 4, "pose": 3}
var locker_tab: int = 0
## Emotes tab: which of the four D-pad / 1-4 slots the next pick fills (0 up .. 3 left).
var _emote_slot: int = 0
var _emote_slot_row: HBoxContainer
## The emote / pose the Locker preview loops (kind, id), and the pause before it replays.
var _clip_loop: Array[String] = []
var _clip_gap: float = 0.0
var _locker_body: VBoxContainer
var _locker_tabs_row: HBoxContainer
var _locker_tab_hint: Label


## The title Volt wears what is equipped (the Locker previews other things on it).
func _wear_equipped() -> void:
	if _volt == null:
		return
	if _volt.trail_id != Cosmetics.equipped_trail():
		_volt.set_trail(Cosmetics.equipped_trail())
	_volt.finish_id = Cosmetics.equipped_finish()
	if _volt.character_id != Cosmetics.equipped("character"):
		_volt.set_character(Cosmetics.equipped("character"))
	if _volt.hat_id != Cosmetics.equipped("hat"):
		_volt.set_hat(Cosmetics.equipped("hat"))
	if _volt.paint_id != Cosmetics.equipped("paint"):
		_volt.set_paint(Cosmetics.equipped("paint"))
	# (a tab switch drops whatever emote / pose the last tab was previewing)
	_clip_loop = []
	_volt.stop_emote()


## Locker preview: Volt laps the pad platform at a run so the trail streams out, framed
## to the right of the menu column.
func _locker_preview(dt: float) -> void:
	var centre := Vector3(0.5, 0.2, 0.0)
	if LOCKER_TABS[locker_tab] in ["emote", "pose"]:
		# the emote / pose tabs: Volt stands in front of the camera and replays the focused clip
		_volt.position = centre + Vector3(-4.6, 0.0, 0.0)
		var to_cam: Vector3 = _cam.position - _volt.position
		to_cam.y = 0.0
		_volt.animate(dt, Vector3.ZERO, true, to_cam.normalized())
		if not _clip_loop.is_empty() and not _volt.is_emoting():
			_clip_gap -= dt
			if _clip_gap <= 0.0:
				_clip_gap = 0.5
				_play_preview_clip(true)
		_cam.position = centre + Vector3(-7.5, 4.2, 10.5)
		_cam.look_at(centre + Vector3(-4.6, 0.9, 0.0))
		return
	var r: float = 3.4
	var w: float = 3.5   # ~12 m/s: over the speed where every trail (Classic too) shows
	var a: float = _t * w
	var tangent := Vector3(-sin(a), 0, cos(a))
	_volt.position = centre + Vector3(cos(a), 0, sin(a)) * r
	_volt.animate(dt, tangent * r * w, true, tangent)
	_cam.position = centre + Vector3(-7.5, 4.2, 10.5)
	_cam.look_at(centre + Vector3(-4.6, 0.9, 0.0))


func _locker_screen() -> Control:
	var box: VBoxContainer = UiKit.vbox(10)
	box.add_child(UiKit.shadowed(UiKit.label("LOCKER", 40, Color.WHITE), 8))
	var blurb: Label = UiKit.label("Earn medals and beat courses to unlock characters, hats, paint jobs, trails, finishes, titles, emotes and victory poses. Racers online see yours too.", 17, UiKit.SOFT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(720, 0)
	box.add_child(blurb)
	# the tab bar: clickable, never pad-focused (LB / RB switch)
	_locker_tabs_row = UiKit.hbox(6)
	_locker_tabs_row.name = "Tabs"
	for i: int in LOCKER_TABS.size():
		var tb: Button = UiKit.button(_tab_label(LOCKER_TABS[i]), func() -> void: set_locker_tab(i), 0)
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size.y = 38
		tb.add_theme_font_size_override("font_size", 13)
		tb.set_meta("tab", LOCKER_TABS[i])
		_locker_tabs_row.add_child(tb)
	box.add_child(_locker_tabs_row)
	_locker_tab_hint = UiKit.label("", 14, UiKit.SOFT)
	box.add_child(_locker_tab_hint)
	_locker_body = UiKit.vbox(8)
	_locker_body.name = "TabBody"
	_locker_body.custom_minimum_size = Vector2(720, 300)
	box.add_child(_locker_body)
	_locker_info = UiKit.shadowed(UiKit.label("", 18, UiKit.SOFT), 5)
	_locker_info.custom_minimum_size = Vector2(720, 48)
	_locker_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_locker_info)
	var back: Button = UiKit.button("Back", func() -> void: show_screen("main"), 720)
	back.name = "Back"
	back.focus_entered.connect(func() -> void: _set_locker_info("", UiKit.SOFT))
	box.add_child(back)
	var p: PanelContainer = UiKit.panel(Vector2(760, 0))
	p.add_child(box)
	locker_tab = clampi(locker_tab, 0, LOCKER_TABS.size() - 1)
	_focus_pref = _build_locker_tab()
	return _left_column(p, 780)


static func _tab_label(tab: String) -> String:
	return "Colour" if tab == "colour" else Cosmetics.kind_label(tab)


## Switches the Locker to tab `i` (wraps), rebuilding its grid and focusing the worn item.
func set_locker_tab(i: int) -> void:
	if Game.title_screen != "locker" or _locker_body == null or not is_instance_valid(_locker_body):
		return
	locker_tab = posmod(i, LOCKER_TABS.size())
	var first: Control = _build_locker_tab()
	if first != null:
		first.grab_focus()
	Sfx.play("ui", 0.05, 0.7)


## Fills the tab body; returns the control to focus first (the equipped item).
func _build_locker_tab() -> Control:
	var tab: String = LOCKER_TABS[locker_tab]
	for c: Node in _locker_body.get_children():
		_locker_body.remove_child(c)
		c.queue_free()
	for b: Node in _locker_tabs_row.get_children():
		var on: bool = str(b.get_meta("tab")) == tab
		(b as Button).modulate = Color.WHITE if on else Color(0.62, 0.65, 0.75)
		(b as Button).text = ("[ %s ]" if on else "%s") % _tab_label(str(b.get_meta("tab")))
	_refresh_locker_hint()
	_set_locker_info("", UiKit.SOFT)
	# the preview wears what is equipped, plus whatever is focused in this tab
	_wear_equipped()
	_locker_body.add_child(UiKit.label(_tab_label(tab).to_upper(), 16, UiKit.TEAL))
	if tab == "colour":
		return _locker_colours()
	if tab == "emote":
		_locker_body.add_child(_locker_emote_slots())
	var grid: GridContainer = _locker_grid(tab, int(LOCKER_COLUMNS.get(tab, 4)))
	_locker_body.add_child(grid)
	var want: String = Cosmetics.emote_slot(_emote_slot) if tab == "emote" else Cosmetics.equipped(tab)
	for b: Node in grid.get_children():
		if str(b.get_meta("item")) == want:
			return b as Control
	return grid.get_child(0) as Control if grid.get_child_count() > 0 else null


## The four emote slots (D-pad up / right / down / left, keys 1-4): press one to choose it, then
## press an emote in the grid below to put it there.
func _locker_emote_slots() -> Control:
	var col: VBoxContainer = UiKit.vbox(4)
	_emote_slot_row = UiKit.hbox(6)
	_emote_slot_row.name = "EmoteSlots"
	for i: int in Cosmetics.EMOTE_SLOT_KEYS.size():
		var sb: Button = UiKit.button("", func() -> void: _locker_choose_slot(i), 0)
		sb.set_meta("slot", i)
		sb.custom_minimum_size = Vector2(172, 40)
		sb.add_theme_font_size_override("font_size", 15)
		sb.clip_text = true
		sb.focus_entered.connect(func() -> void:
			var held: String = Cosmetics.emote_slot(i)
			_set_locker_info("%s  -  slot %d: %s. Press to fill it with an emote." % [_slot_prompt(i), i + 1, Cosmetics.item_name("emote", held)], UiKit.SOFT)
			_clip_loop = ["emote", held]
			_play_preview_clip(false))
		_emote_slot_row.add_child(sb)
	col.add_child(_emote_slot_row)
	var how: Label = UiKit.label("In game: %s." % ("D-pad up / right / down / left" if Game.using_pad else "keys 1 2 3 4 (the D-pad on a pad)"), 14, UiKit.SOFT)
	col.add_child(how)
	_refresh_emote_slots()
	return col


## "D-pad Up" / "Key 1" for slot `i`, by the device in hand.
func _slot_prompt(i: int) -> String:
	return "D-pad %s" % Cosmetics.EMOTE_SLOT_NAMES[i] if Game.using_pad else "Key %d" % (i + 1)


func _refresh_emote_slots() -> void:
	if _emote_slot_row == null or not is_instance_valid(_emote_slot_row):
		return
	for n: Node in _emote_slot_row.get_children():
		var b := n as Button
		var i: int = int(b.get_meta("slot"))
		var label: String = "%s: %s" % [Cosmetics.EMOTE_SLOT_NAMES[i], Cosmetics.item_name("emote", Cosmetics.emote_slot(i))]
		b.text = "[ %s ]" % label if i == _emote_slot else label
		b.modulate = Color.WHITE if i == _emote_slot else Color(0.75, 0.78, 0.88)


## Picks emote slot `i` and moves on to the emote grid (on that slot's emote).
func _locker_choose_slot(i: int) -> void:
	_emote_slot = clampi(i, 0, Cosmetics.EMOTE_SLOT_KEYS.size() - 1)
	_refresh_emote_slots()
	var want: String = Cosmetics.emote_slot(_emote_slot)
	for g: Node in _locker_body.find_children("*", "GridContainer", true, false):
		for b: Node in g.get_children():
			if str(b.get_meta("item", "")) == want:
				(b as Control).grab_focus()
				return


## Plays the focused emote / pose on the preview Volt (`quiet` for loop repeats).
func _play_preview_clip(quiet: bool) -> void:
	if _clip_loop.size() != 2 or _volt == null:
		return
	if _clip_loop[0] == "pose":
		_volt.play_pose(_clip_loop[1], true, 0.0, quiet)
	else:
		_volt.play_emote(_clip_loop[1], quiet)


## Colour swatches, as on the Race Friends screen.
func _locker_colours() -> Control:
	var colours: HBoxContainer = UiKit.hbox(8)
	colours.name = "Colours"
	var styles: Array[StyleBoxFlat] = []
	var pick: Control = null
	for i: int in Settings.RACER_COLORS.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(52, 52)
		sw.set_meta("colour", i)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Settings.RACER_COLORS[i]
		sb.set_corner_radius_all(8)
		sb.border_color = Color.WHITE
		sb.set_border_width_all(3 if i == Settings.color_index else 0)
		styles.append(sb)
		for state: String in ["normal", "hover", "pressed"]:
			sw.add_theme_stylebox_override(state, sb)
		sw.focus_entered.connect(func() -> void: _set_locker_info("Colour %d  -  your belt, mitts and name" % (i + 1), UiKit.SOFT))
		sw.pressed.connect(func() -> void:
			Settings.color_index = i
			Net.preferred_color = -1
			_save_locker()
			for j: int in styles.size():
				styles[j].set_border_width_all(3 if j == i else 0)
			_volt.set_accent(Settings.my_color())
			Net.update_identity())
		colours.add_child(sw)
		if i == Settings.color_index:
			pick = sw
	_locker_body.add_child(colours)
	return pick


## A grid of item buttons. Focusing one previews it on Volt and names how to unlock it;
## pressing equips it (a locked one is only previewed).
func _locker_grid(kind: String, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = {"trail": "Trails", "finish": "Finishes"}.get(kind, Cosmetics.kind_label(kind) + "s")
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var w: float = (720.0 - 8.0 * float(columns - 1)) / float(columns)
	for id: String in Cosmetics.ids(kind):
		var b: Button = UiKit.button("", func() -> void: _locker_pick(kind, id), w)
		b.set_meta("item", id)
		b.set_meta("kind", kind)
		b.custom_minimum_size.y = 46
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_font_size_override("font_size", 16)
		b.focus_entered.connect(func() -> void: _locker_focus(kind, id))
		b.mouse_entered.connect(func() -> void: _locker_focus(kind, id))
		grid.add_child(b)
	_refresh_locker_grid(grid)
	return grid


static func _equipped(kind: String) -> String:
	return Cosmetics.equipped(kind)


func _refresh_locker_grid(grid: GridContainer) -> void:
	for n: Node in grid.get_children():
		var b := n as Button
		var kind: String = str(b.get_meta("kind"))
		var id: String = str(b.get_meta("item"))
		var item_name: String = Cosmetics.item_name(kind, id)
		var unlocked: bool = Cosmetics.is_unlocked(kind, id)
		if id == _equipped(kind) or (kind == "emote" and Cosmetics.emote_slot_of(id) >= 0):
			b.text = "> %s <" % item_name
		else:
			b.text = item_name if unlocked else "Locked"
		b.modulate = Color.WHITE if unlocked else Color(0.6, 0.62, 0.7)
		b.tooltip_text = item_name if unlocked else "%s  -  %s" % [item_name, Cosmetics.hint(kind, id)]


## The info line for a focused item: "LOCKED  Ninja  -  Gold on Sakura Peaks  (best: Silver)".
func _locker_focus(kind: String, id: String) -> void:
	var item_name: String = Cosmetics.display_name(kind, id)
	if kind == "title":
		item_name = "%s  (%s)" % [item_name, Cosmetics.titled(Settings.player_name, id)]
	if not Cosmetics.is_unlocked(kind, id):
		var prog: String = Cosmetics.progress(kind, id)
		_set_locker_info("LOCKED  %s  -  %s%s" % [item_name, Cosmetics.hint(kind, id), "  (%s)" % prog if prog != "" else ""], Color(1, 0.7, 0.55))
	elif kind == "emote" and Cosmetics.emote_slot_of(id) >= 0:
		_set_locker_info("%s  -  on %s (press to put it on %s instead)" % [item_name, _slot_prompt(Cosmetics.emote_slot_of(id)), _slot_prompt(_emote_slot)], UiKit.GOLD)
	elif id == _equipped(kind):
		_set_locker_info("%s  -  equipped" % item_name, UiKit.GOLD)
	else:
		_set_locker_info(item_name, Color.WHITE)
	_preview(kind, id)


## Puts a focused item on the preview Volt.
func _preview(kind: String, id: String) -> void:
	match kind:
		"trail":
			if _volt.trail_id != id:
				_volt.set_trail(id)
		"character":
			if _volt.character_id != id:
				_volt.set_character(id)
		"hat":
			if _volt.hat_id != id:
				_volt.set_hat(id)
		"paint":
			if _volt.paint_id != id:
				_volt.set_paint(id)
		"emote", "pose":
			# a locked one is previewed too: that is how you see what you are working towards
			_clip_loop = [kind, id]
			_clip_gap = 0.0
			_play_preview_clip(false)


func _locker_pick(kind: String, id: String) -> void:
	if Cosmetics.is_unlocked(kind, id):
		if kind == "emote":
			Cosmetics.set_emote_slot(_emote_slot, id)
			_refresh_emote_slots()
		else:
			Settings.set(Cosmetics.setting_key(kind), id)
		_save_locker()
		Net.update_identity()
		Sfx.play("ui", 0.05, 0.8)
		for g: Node in _screen.find_children("*", "GridContainer", true, false):
			_refresh_locker_grid(g as GridContainer)
		_locker_focus(kind, id)
	if kind == "finish":
		_volt.finish_id = id
		_volt.on_cheer()


func _save_locker() -> void:
	if persist_settings:
		Settings.save_settings()


func _set_locker_info(text: String, color: Color) -> void:
	if _locker_info != null and is_instance_valid(_locker_info):
		_locker_info.text = text
		_locker_info.add_theme_color_override("font_color", color)


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
	box.add_child(UiKit.label("PARTY VS CPU" if Net.local_session else "RACE LOBBY", 36, Color.WHITE))
	if Net.local_session:
		box.add_child(UiKit.label("Solo Party Cup. Pick the course and start the next round.", 17, UiKit.TEAL))
	elif Net.is_host():
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
		if Net.local_session:
			modes = ["party", "team"]
		var mode_pick := OptionButton.new()
		mode_pick.custom_minimum_size = Vector2(0, 46)
		for m: String in modes:
			mode_pick.add_item("Mode:  %s" % PartyNames.mode_name(m))
		mode_pick.selected = maxi(modes.find(Net.game_mode), 0)
		mode_pick.item_selected.connect(func(i: int) -> void: Net.host_set_mode(modes[i]))
		box.add_child(mode_pick)
		CpuMenu.add_lobby_controls(box)
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
		var solo: bool = Net.local_session
		Net.leave()
		show_screen("main" if solo else "race"), 520)
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
		var tag: String = "  (host)" if id == 1 and not Net.local_session else ""
		if id == Net.my_id():
			tag += "  (you)"
		if bool(e.get("cpu", false)):
			tag += "  (CPU)"
		var last: String = ""
		if float(e.get("finished", -1.0)) >= 0.0 and mode == "race":
			last = "     last race %s" % SaveData.format_time(float(e["finished"]))
		var cup: String = ""
		if mode != "race" and Net.party_round > 0 and Game.party != null and Game.party.cup.has(id):
			cup = "     cup %d" % int(Game.party.cup[id])
		if not team:
			_roster_box.add_child(UiKit.label("%s%s%s%s" % [Cosmetics.titled(str(e["name"]), e.get("title")), tag, last, cup], 22, col.lerp(Color.WHITE, 0.3)))
			continue
		var tm: int = Net.team_of(id)
		var row: HBoxContainer = UiKit.hbox(10)
		var l: Label = UiKit.label("[%s]  %s%s%s" % [PartyNames.team_name(tm), Cosmetics.titled(str(e["name"]), e.get("title")), tag, cup], 22, PartyNames.team_color(tm).lerp(Color.WHITE, 0.25))
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
