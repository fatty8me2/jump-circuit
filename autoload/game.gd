extends Node
## Flow controller: level catalogue, scene switching, the shared course clock,
## input map setup.

const LEVELS: Array[Dictionary] = [
	{"id": "gardens", "name": "Launch Gardens", "scene": "res://levels/level_1_gardens.tscn", "blurb": "Sunny gardens. Not actually easy."},
	{"id": "foundry", "name": "Bounce Foundry", "scene": "res://levels/level_2_foundry.tscn", "blurb": "Read the pads, steer the arcs, or burn."},
	{"id": "balance", "name": "Balance Works", "scene": "res://levels/level_3_balance.tscn", "blurb": "Boards that answer to your weight - and tip you off."},
	{"id": "clockwork", "name": "Clockwork Heights", "scene": "res://levels/level_4_clockwork.tscn", "blurb": "Watch the rhythm, commit, never stop."},
	{"id": "ascent", "name": "The Final Ascent", "scene": "res://levels/level_5_ascent.tscn", "blurb": "Everything you know, at its nastiest, up to the beacon."},
]
const TITLE_SCENE: String = "res://ui/title.tscn"

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


func _setup_input() -> void:
	var keys: Dictionary = {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "restart": [KEY_R], "pause": [KEY_ESCAPE],
		"debug_overlay": [KEY_F3], "dev_next_checkpoint": [KEY_F6], "show_board": [KEY_TAB],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for code: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code as Key
			InputMap.action_add_event(action, ev)
	var pad: Dictionary = {"jump": JOY_BUTTON_A, "restart": JOY_BUTTON_Y, "pause": JOY_BUTTON_START}
	for action: String in pad:
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad[action] as JoyButton
		InputMap.action_add_event(action, jb)
	var axes: Dictionary = {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0]}
	for action: String in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[action][0] as JoyAxis
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)


func _physics_process(dt: float) -> void:
	if race_mode:
		course_time = Net.now() - Net.race_start_time
	elif course_running and not get_tree().paused:
		course_time += dt


# ---- navigation ----------------------------------------------------------------------

func play_level(index: int) -> void:
	race_mode = false
	level_index = clampi(index, 0, LEVELS.size() - 1)
	_load_level()


func _on_race_starting(index: int, start_time: float) -> void:
	race_mode = true
	level_index = index
	course_time = Net.now() - start_time
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
