extends Node
## Flow controller: level catalogue, scene switching, the shared course clock,
## input map setup.

const LEVELS: Array[Dictionary] = [
	{"id": "gardens", "name": "Launch Gardens", "scene": "res://levels/level_1_gardens.tscn", "blurb": "Sunny gardens. Not actually easy."},
	{"id": "foundry", "name": "Bounce Foundry", "scene": "res://levels/level_2_foundry.tscn", "blurb": "Read the pads, steer the arcs, or burn."},
	{"id": "balance", "name": "Balance Works", "scene": "res://levels/level_3_balance.tscn", "blurb": "Boards that answer to your weight - and tip you off."},
	{"id": "clockwork", "name": "Clockwork Heights", "scene": "res://levels/level_4_clockwork.tscn", "blurb": "Watch the rhythm, commit, never stop."},
	{"id": "reef", "name": "Coral Depths", "scene": "res://levels/level_5_reef.tscn", "blurb": "A sunken reef. Ride the currents, mind the eels."},
	{"id": "orbital", "name": "Orbital Drift", "scene": "res://levels/level_6_orbital.tscn", "blurb": "A station in low orbit. Run the walls, don't drift."},
	{"id": "xeno", "name": "Xeno Wilds", "scene": "res://levels/level_7_xeno.tscn", "blurb": "A glowing alien jungle under a ringed giant. Mind what bites."},
	{"id": "volcano", "name": "Cinder Peak", "scene": "res://levels/level_8_volcano.tscn", "blurb": "The mountain is erupting. Outclimb the lava, dodge the bombs."},
	{"id": "glacier", "name": "Frostbite Pass", "scene": "res://levels/level_9_glacier.tscn", "blurb": "An ice fortress in a blizzard. Mind the icicles, outrun the avalanche."},
	{"id": "desert", "name": "Scarab Sands", "scene": "res://levels/level_10_desert.tscn", "blurb": "Dunes, mirages and a sun temple full of traps. When the plate clicks, run."},
	{"id": "ascent", "name": "The Final Ascent", "scene": "res://levels/level_11_ascent.tscn", "blurb": "Everything you know, at its nastiest, up to the beacon."},
]
const TITLE_SCENE: String = "res://ui/title.tscn"
## Party Mode actions and their default bindings (Settings can rebind the key / mouse and pad
## button). None of them clash with jump / retry / pause / camera; in the main mode nothing
## listens to them. RT / LT also attack / use (fixed).
const PARTY_ACTIONS: Array[String] = ["attack", "use_item", "shove", "cycle_item"]
const PARTY_BIND_DEFAULTS: Dictionary = {
	"attack": {"key": KEY_F, "mouse": MOUSE_BUTTON_LEFT, "pad": JOY_BUTTON_X},
	"use_item": {"key": KEY_E, "mouse": MOUSE_BUTTON_RIGHT, "pad": JOY_BUTTON_RIGHT_SHOULDER},
	"shove": {"key": KEY_Q, "mouse": 0, "pad": JOY_BUTTON_B},
	"cycle_item": {"key": KEY_C, "mouse": 0, "pad": JOY_BUTTON_LEFT_SHOULDER},
}
const PAD_BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
	JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_MISC1: "Share",
}

## The last input came from a gamepad (true) or keyboard / mouse (false): prompts follow it.
signal input_device_changed(pad: bool)

## Seconds since the course started. Drives every kinematic obstacle.
var course_time: float = 0.0
var course_running: bool = false
var level_index: int = -1
var race_mode: bool = false
var dev_mode: bool = false
## Which title sub-screen to open next time the title loads ("main", "levels", "lobby", "victory").
var title_screen: String = "main"
var title_message: String = ""
## Screenshot tool: never grab the mouse.
var shot_mode: bool = false
## Level whose intro banner was already shown (instant restarts skip it).
var intro_shown_for: String = ""
## Race clock: smoothed error between course_time and the session clock.
var _clock_err_avg: float = 0.0
## See input_device_changed.
var using_pad: bool = false
## Party Mode rules + Party Cup while a party race or Party Practice is on; null in the main
## mode. This is the one switch: levels only add the party layer when it is set.
var party: PartyRules = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	apply_party_binds()
	dev_mode = "--dev" in OS.get_cmdline_user_args()
	Net.race_starting.connect(_on_race_starting)
	Net.lobby_requested.connect(func() -> void: goto_title("lobby"))
	Net.left_session.connect(func(reason: String) -> void:
		if race_mode or title_screen == "lobby":
			title_message = reason
			goto_title("main"))
	# turned away (kicked) while in a race level: back to Race Friends with the reason
	# (on the title itself, the title handles this signal)
	Net.connection_failed.connect(func(reason: String) -> void:
		if race_mode:
			title_message = reason
			goto_title("race"))


func _setup_input() -> void:
	var keys: Dictionary = {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "restart": [KEY_R], "pause": [KEY_ESCAPE],
		"debug_overlay": [KEY_F3], "dev_next_checkpoint": [KEY_F6], "show_board": [KEY_TAB],
		"spectate_prev": [KEY_Q], "spectate_next": [KEY_E],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for code: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code as Key
			InputMap.action_add_event(action, ev)
	# Pad events use device -1 (any pad): new() defaults to device 0, which misses a
	# controller that enumerates on another slot (second pad, wheel, virtual pad).
	var pad: Dictionary = {"jump": JOY_BUTTON_A, "restart": JOY_BUTTON_Y, "pause": JOY_BUTTON_START,
		"move_forward": JOY_BUTTON_DPAD_UP, "move_back": JOY_BUTTON_DPAD_DOWN,
		"move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT,
		"spectate_prev": JOY_BUTTON_LEFT_SHOULDER, "spectate_next": JOY_BUTTON_RIGHT_SHOULDER}
	for action: String in pad:
		var jb := InputEventJoypadButton.new()
		jb.device = -1
		jb.button_index = pad[action] as JoyButton
		InputMap.action_add_event(action, jb)
	var axes: Dictionary = {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0]}
	for action: String in axes:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		var jm := InputEventJoypadMotion.new()
		jm.device = -1
		jm.axis = axes[action][0] as JoyAxis
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)
	# The built-in ui_accept / ui_cancel have no pad buttons: A presses a focused
	# menu button, B goes back.
	var ui_pad: Dictionary = {"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B}
	for action: String in ui_pad:
		var ub := InputEventJoypadButton.new()
		ub.device = -1
		ub.button_index = ui_pad[action] as JoyButton
		if not InputMap.action_has_event(action, ub):
			InputMap.action_add_event(action, ub)


## Tracks which device the player is using so menus can show matching button prompts.
func _input(event: InputEvent) -> void:
	var pad: bool = using_pad
	if event is InputEventJoypadButton:
		pad = pad or event.is_pressed()
	elif event is InputEventJoypadMotion:
		pad = pad or absf((event as InputEventJoypadMotion).axis_value) > 0.5
	elif (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		pad = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 4.0:
		pad = false
	if pad != using_pad:
		using_pad = pad
		input_device_changed.emit(pad)


## Menu input that should give a focus-less menu its starting point instead of doing nothing.
static func is_menu_nav(event: InputEvent) -> bool:
	for a: String in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action_pressed(a):
			return true
	return false


## Button prompt for an action, for whichever device is in use ("R" / "Y").
## Party actions follow their current (rebindable) bindings.
func prompt(action: String) -> String:
	if action in PARTY_ACTIONS:
		return bind_text(action, using_pad)
	var keys: Dictionary = {"restart": "R", "jump": "Space", "pause": "Esc", "back": "Esc",
		"spectate_prev": "Q", "spectate_next": "E"}
	var pads: Dictionary = {"restart": "Y", "jump": "A", "pause": "Start", "back": "B",
		"spectate_prev": "LB", "spectate_next": "RB"}
	return str((pads if using_pad else keys).get(action, action))


# ---- party actions: bindings --------------------------------------------------------

## The binding in force for a party action: {"key", "mouse", "pad"} (0 / -1 = none).
func party_bind(action: String) -> Dictionary:
	var d: Dictionary = (PARTY_BIND_DEFAULTS.get(action, {}) as Dictionary).duplicate()
	var over: Variant = Settings.party_binds.get(action, null)
	if typeof(over) == TYPE_DICTIONARY:
		for k: String in ["key", "mouse", "pad"]:
			if (over as Dictionary).has(k):
				d[k] = int((over as Dictionary)[k])
	return d


## Rebuilds the InputMap events of every party action from its binding.
func apply_party_binds() -> void:
	for action: String in PARTY_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.35)
		InputMap.action_erase_events(action)
		var b: Dictionary = party_bind(action)
		if int(b.get("key", 0)) > 0:
			var k := InputEventKey.new()
			k.physical_keycode = int(b["key"]) as Key
			InputMap.action_add_event(action, k)
		if int(b.get("mouse", 0)) > 0:
			var m := InputEventMouseButton.new()
			m.button_index = int(b["mouse"]) as MouseButton
			InputMap.action_add_event(action, m)
		if int(b.get("pad", -1)) >= 0:
			var jb := InputEventJoypadButton.new()
			jb.device = -1
			jb.button_index = int(b["pad"]) as JoyButton
			InputMap.action_add_event(action, jb)
		var trigger: int = {"attack": JOY_AXIS_TRIGGER_RIGHT, "use_item": JOY_AXIS_TRIGGER_LEFT}.get(action, -1)
		if trigger >= 0:
			var jm := InputEventJoypadMotion.new()
			jm.device = -1
			jm.axis = trigger as JoyAxis
			jm.axis_value = 1.0
			InputMap.action_add_event(action, jm)


## "F / LMB" or "X" for an action's binding.
func bind_text(action: String, pad: bool) -> String:
	var b: Dictionary = party_bind(action)
	if pad:
		return pad_button_name(int(b.get("pad", -1)))
	var parts: PackedStringArray = []
	if int(b.get("key", 0)) > 0:
		parts.append(OS.get_keycode_string(int(b["key"]) as Key))
	if int(b.get("mouse", 0)) > 0:
		parts.append(mouse_button_name(int(b["mouse"])))
	return " / ".join(parts) if not parts.is_empty() else "-"


static func pad_button_name(button: int) -> String:
	if button < 0:
		return "-"
	return str(PAD_BUTTON_NAMES.get(button, "Button %d" % button))


static func mouse_button_name(button: int) -> String:
	return {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
		MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5"}.get(button, "Mouse %d" % button)


## Which fixed game action already uses this input (a rebind onto it is refused), or "".
func fixed_action_for(event: InputEvent) -> String:
	for action: String in ["jump", "restart", "pause", "move_forward", "move_back", "move_left", "move_right",
			"debug_overlay", "show_board", "ui_accept", "ui_cancel"]:
		if InputMap.has_action(action) and InputMap.event_is_action(event, action, true):
			# pad B / A are menu back / confirm too, but only while a menu is open
			if action in ["ui_accept", "ui_cancel"] and event is InputEventJoypadButton:
				continue
			return action
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return "zoom"
	return ""


func _physics_process(dt: float) -> void:
	if race_mode:
		_advance_race_clock(dt)
	elif course_running and not get_tree().paused:
		course_time += dt


## Race clock: step one fixed tick at a time. A frame's physics ticks run back to
## back, so sampling the wall clock per tick moved obstacles in 16 ms / 0.5 ms
## lurches and doubled or zeroed the velocity riders inherit. Then steer gently
## toward the shared session clock.
func _advance_race_clock(dt: float) -> void:
	var target: float = Net.now() - Net.race_start_time
	course_time += dt
	if course_time < 0.0:
		# countdown (players are held): track the session clock exactly, which also
		# absorbs the scene-load gap so GO lands at the same moment on every peer
		course_time = target
		_clock_err_avg = 0.0
		return
	# average out the per-frame sawtooth of the wall-clock target, then nudge (<= 5 %)
	_clock_err_avg = lerpf(_clock_err_avg, target - course_time, 0.02)
	course_time += clampf(_clock_err_avg * 0.01, -dt * 0.05, dt * 0.05)


func _process(_dt: float) -> void:
	# hard re-sync after a long hitch - checked once per frame, after the frame's
	# catch-up physics ticks, so those ticks don't carry the clock past the target
	if race_mode and absf(Net.now() - Net.race_start_time - course_time) > 0.25:
		course_time = Net.now() - Net.race_start_time
		_clock_err_avg = 0.0


# ---- navigation ----------------------------------------------------------------------

func play_level(index: int) -> void:
	race_mode = false
	party = null
	level_index = clampi(index, 0, LEVELS.size() - 1)
	_load_level()


## Party Practice: a solo run of any unlocked level with item boxes, power-ups and practice
## dummies. Nothing is scored or saved.
func play_party_practice(index: int) -> void:
	race_mode = false
	party = PartyRules.new("practice")
	level_index = clampi(index, 0, LEVELS.size() - 1)
	_load_level()


func _on_race_starting(index: int, start_time: float) -> void:
	race_mode = true
	# a party race is the next round of the cup; a plain race switches every party system off
	if Net.game_mode == "race":
		party = null
	else:
		if party == null or party.mode != Net.game_mode or Net.party_round <= 1:
			party = PartyRules.new(Net.game_mode)
		party.round_no = Net.party_round
	level_index = index
	course_time = Net.now() - start_time
	_clock_err_avg = 0.0
	_load_level()


func _load_level() -> void:
	get_tree().paused = false
	if not race_mode:
		course_time = 0.0
	course_running = true
	get_tree().change_scene_to_file(LEVELS[level_index]["scene"])


func play_playground() -> void:
	race_mode = false
	party = null
	level_index = -1
	get_tree().paused = false
	course_time = 0.0
	course_running = true
	get_tree().change_scene_to_file("res://levels/playground.tscn")


func restart_level() -> void:
	if race_mode:
		return
	if level_index < 0:
		play_playground()
	else:
		_load_level()


func next_level() -> void:
	if party != null:
		var n: int = level_index + 1
		if n >= LEVELS.size() or not is_level_unlocked(n):
			n = 0
		play_party_practice(n)
		return
	if level_index + 1 < LEVELS.size():
		play_level(level_index + 1)
	else:
		goto_title("victory")


func goto_title(screen: String = "main") -> void:
	get_tree().paused = false
	course_running = false
	race_mode = false
	# the Party Cup lives on while the session does (back in the lobby between rounds)
	if not Net.active or screen != "lobby":
		party = null
	title_screen = screen
	intro_shown_for = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


func level_info() -> Dictionary:
	if level_index >= 0:
		return LEVELS[level_index]
	return {"id": "playground", "name": "Playground", "blurb": ""}


func is_level_unlocked(index: int) -> bool:
	return index == 0 or dev_mode or SaveData.is_completed(LEVELS[index - 1]["id"]) or SaveData.is_completed(LEVELS[index]["id"])
