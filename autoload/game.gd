extends Node
## Flow controller: level catalogue, scene switching, the shared course clock,
## input map setup.

const LEVELS: Array[Dictionary] = [
	{"id": "gardens", "name": "Launch Gardens", "scene": "res://levels/level_1_gardens.tscn", "blurb": "Sunny gardens. Not actually easy.", "medals": {"gold": 170, "silver": 205, "bronze": 260}},
	{"id": "foundry", "name": "Bounce Foundry", "scene": "res://levels/level_2_foundry.tscn", "blurb": "Read the pads, steer the arcs, or burn.", "medals": {"gold": 155, "silver": 185, "bronze": 235}},
	{"id": "balance", "name": "Balance Works", "scene": "res://levels/level_3_balance.tscn", "blurb": "Boards that answer to your weight - and tip you off.", "medals": {"gold": 160, "silver": 190, "bronze": 240}},
	{"id": "clockwork", "name": "Clockwork Heights", "scene": "res://levels/level_4_clockwork.tscn", "blurb": "Watch the rhythm, commit, never stop.", "medals": {"gold": 195, "silver": 235, "bronze": 295}},
	{"id": "reef", "name": "Coral Depths", "scene": "res://levels/level_5_reef.tscn", "blurb": "A sunken reef. Ride the currents, mind the eels.", "medals": {"gold": 135, "silver": 160, "bronze": 200}},
	{"id": "orbital", "name": "Orbital Drift", "scene": "res://levels/level_6_orbital.tscn", "blurb": "A station in low orbit. Run the walls, don't drift.", "medals": {"gold": 160, "silver": 195, "bronze": 245}},
	{"id": "xeno", "name": "Xeno Wilds", "scene": "res://levels/level_7_xeno.tscn", "blurb": "A glowing alien jungle under a ringed giant. Mind what bites.", "medals": {"gold": 155, "silver": 185, "bronze": 235}},
	{"id": "volcano", "name": "Cinder Peak", "scene": "res://levels/level_8_volcano.tscn", "blurb": "The mountain is erupting. Outclimb the lava, dodge the bombs.", "medals": {"gold": 165, "silver": 195, "bronze": 245}},
	{"id": "glacier", "name": "Frostbite Pass", "scene": "res://levels/level_9_glacier.tscn", "blurb": "An ice fortress in a blizzard. Mind the icicles, outrun the avalanche.", "medals": {"gold": 185, "silver": 225, "bronze": 280}},
	{"id": "desert", "name": "Scarab Sands", "scene": "res://levels/level_10_desert.tscn", "blurb": "Dunes, mirages and a sun temple full of traps. When the plate clicks, run.", "medals": {"gold": 160, "silver": 195, "bronze": 245}},
	{"id": "manor", "name": "Phantom Manor", "scene": "res://levels/level_11_manor.tscn", "blurb": "A haunted mansion under a blood moon. Not everything solid stays solid.", "medals": {"gold": 185, "silver": 220, "bronze": 275}},
	{"id": "armada", "name": "Storm Armada", "scene": "res://levels/level_12_armada.tscn", "blurb": "Cross a sky-pirate fleet ship to ship through a thunderstorm. Mind the cannons.", "medals": {"gold": 190, "silver": 230, "bronze": 290}},
	{"id": "candy", "name": "Sugar Rush", "scene": "res://levels/level_13_candy.tscn", "blurb": "A candy dreamworld. Sweet, bouncy, merciless.", "medals": {"gold": 185, "silver": 220, "bronze": 280}},
	{"id": "carrier", "name": "Super Carrier", "scene": "res://levels/level_14_carrier.tscn", "blurb": "Launch day on a supercarrier. Stay out of the foam, off the catapults, up the tower.", "medals": {"gold": 190, "silver": 230, "bronze": 285}},
	{"id": "sakura", "name": "Sakura Peaks", "scene": "res://levels/level_16_sakura.tscn", "blurb": "A feudal-Japan mountain at dusk, through blossoms and pagodas to the castle keep.", "medals": {"gold": 200, "silver": 240, "bronze": 300}},
	{"id": "jungle", "name": "Jungle Temple", "scene": "res://levels/level_17_jungle.tscn", "blurb": "Overgrown ruins, a rolling boulder and a step pyramid. Do not touch the glyphs.", "medals": {"gold": 185, "silver": 220, "bronze": 280}},
	{"id": "frontier", "name": "Wild West Heist", "scene": "res://levels/level_18_frontier.tscn", "blurb": "Rob the train. Run the cars, ride the carts, beat the dynamite to the engine.", "medals": {"gold": 170, "silver": 205, "bronze": 255}},
	{"id": "neon", "name": "Neon City", "scene": "res://levels/level_19_neon.tscn", "blurb": "Rain, neon and hover traffic. Ride the lanes to the top of the tallest tower.", "medals": {"gold": 175, "silver": 210, "bronze": 265}},
	{"id": "doom", "name": "Doom Fortress", "scene": "res://levels/level_20_doom.tscn", "blurb": "Inside a doomsday machine that is tearing itself apart. Nothing here wants you alive.", "medals": {"gold": 200, "silver": 240, "bronze": 300}},  # PROVISIONAL: placeholder course - the lead sets these once it is built and timed
	{"id": "abyss", "name": "The Abyss", "scene": "res://levels/level_21_abyss.tscn", "blurb": "Down a black ocean trench by the light of things that glow. The current is not your friend.", "medals": {"gold": 140, "silver": 165, "bronze": 210}},
	{"id": "tempest", "name": "Tempest Tower", "scene": "res://levels/level_22_tempest.tscn", "blurb": "Climb the outside of a mile-high tower in a hurricane. Lightning picks the tallest thing.", "medals": {"gold": 180, "silver": 220, "bronze": 275}},
	{"id": "void", "name": "The Void", "scene": "res://levels/level_23_void.tscn", "blurb": "Impossible geometry in a dream that is coming apart. Up is a suggestion.", "medals": {"gold": 120, "silver": 145, "bronze": 180}},
	{"id": "ascent", "name": "The Final Ascent", "scene": "res://levels/level_24_ascent.tscn", "blurb": "Everything you know, at its nastiest, up to the beacon.", "medals": {"gold": 180, "silver": 215, "bronze": 270}},
]
## Medal targets ("medals" in each LEVELS entry, whole seconds) come from the route bot:
## Gold = the fastest bot route x 1.12, Silver x 1.35, Bronze x 1.7, each rounded UP to 5 s.
## The bot is frame-perfect, so Gold asks for near-perfect play. This is the reference
## table (fastest route, seconds, from the "(route N): bot completes the main route" lines
## of the full bot runs); tests check every Gold against it. Re-time and update both when a
## course is rebuilt.
const BOT_TIMES: Dictionary = {
	"gardens": 150.3, "foundry": 136.4, "balance": 139.8, "clockwork": 172.1, "reef": 116.1,
	"orbital": 142.5, "xeno": 136.3, "volcano": 144.1, "glacier": 163.4, "desert": 141.2,
	"manor": 161.5, "armada": 168.5, "candy": 162.5, "carrier": 167.4, "sakura": 175.0, "jungle": 162.6, "frontier": 150.0, "neon": 153.4, "abyss": 122.1, "tempest": 159.6, "void": 104.8,
	"ascent": 158.7,
}
const MEDAL_MULT: Dictionary = {"gold": 1.12, "silver": 1.35, "bronze": 1.7}
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


## The level's catalogue entry by id ({} for the playground or an unknown id).
static func level_by_id(level_id: String) -> Dictionary:
	for info: Dictionary in LEVELS:
		if info["id"] == level_id:
			return info
	return {}


## {"gold", "silver", "bronze"} target seconds for a level ({} when it has none).
static func medal_targets(level_id: String) -> Dictionary:
	return level_by_id(level_id).get("medals", {})


## The medal a time earns on a level: 3 gold, 2 silver, 1 bronze, 0 none (or no time,
## time < 0). A time exactly on a target earns it (compared at the shown hundredths).
static func medal_for(level_id: String, time: float) -> int:
	var m: Dictionary = medal_targets(level_id)
	if m.is_empty() or time < 0.0 or not is_finite(time):
		return 0
	var cs: int = SaveData.centiseconds(time)
	var tier: int = 3
	for k: String in ["gold", "silver", "bronze"]:
		if cs <= int(round(float(m[k]) * 100.0)):
			return tier
		tier -= 1
	return 0


## The target for a tier (1-3) on a level, -1 if none.
static func medal_target(level_id: String, tier: int) -> float:
	var m: Dictionary = medal_targets(level_id)
	var key: String = ["", "bronze", "silver", "gold"][clampi(tier, 0, 3)]
	return float(m[key]) if key != "" and m.has(key) else -1.0


func is_level_unlocked(index: int) -> bool:
	return index == 0 or dev_mode or SaveData.is_completed(LEVELS[index - 1]["id"]) or SaveData.is_completed(LEVELS[index]["id"])
