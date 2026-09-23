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
	{"id": "ascent", "name": "The Final Ascent", "scene": "res://levels/level_7_ascent.tscn", "blurb": "Everything you know, at its nastiest, up to the beacon."},
]
const TITLE_SCENE: String = "res://ui/title.tscn"

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
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
func prompt(action: String) -> String:
	var keys: Dictionary = {"restart": "R", "jump": "Space", "pause": "Esc", "back": "Esc",
		"spectate_prev": "Q", "spectate_next": "E"}
	var pads: Dictionary = {"restart": "Y", "jump": "A", "pause": "Start", "back": "B",
		"spectate_prev": "LB", "spectate_next": "RB"}
	return str((pads if using_pad else keys).get(action, action))


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
	level_index = clampi(index, 0, LEVELS.size() - 1)
	_load_level()


func _on_race_starting(index: int, start_time: float) -> void:
	race_mode = true
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
	if level_index + 1 < LEVELS.size():
		play_level(level_index + 1)
	else:
		goto_title("victory")


func goto_title(screen: String = "main") -> void:
	get_tree().paused = false
	course_running = false
	race_mode = false
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
