extends Node
## User preferences (user://settings.cfg): camera, audio, graphics, identity.

signal changed

const PATH: String = "user://settings.cfg"
const RACER_COLORS: Array[Color] = [
	Color(1.0, 0.72, 0.2), Color(0.3, 0.85, 0.95), Color(1.0, 0.4, 0.55), Color(0.55, 0.9, 0.4),
	Color(0.75, 0.55, 1.0), Color(1.0, 0.55, 0.25), Color(0.95, 0.95, 0.95), Color(0.35, 0.5, 1.0),
]

var mouse_sensitivity: float = 1.0
var invert_y: bool = false
var fov: float = 72.0
var master_volume: float = 0.8
var sfx_volume: float = 0.9
var music_volume: float = 0.4
## 0 low, 1 medium, 2 high, 3 ultra (saves from before Ultra only ever hold 0-2)
var quality: int = 2
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]
## Particle amount multiplier per quality tier (see particle_scale()).
const PARTICLE_SCALE: Array[float] = [0.45, 0.75, 1.0, 1.75]
var fullscreen: bool = false
var vsync: bool = true
## "auto" hides the timer until a level has been finished once.
var timer_mode: String = "auto"
var player_name: String = "Runner"
var color_index: int = 0
var last_room_code: String = ""
## Party Mode rebinds: action -> {"key": physical keycode, "mouse": button, "pad": button}
## (only what differs from Game.PARTY_BIND_DEFAULTS is needed; 0 / -1 = unbound).
var party_binds: Dictionary = {}

var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	_ensure_buses()
	apply()


func _ensure_buses() -> void:
	for bus_name: String in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


## `path` is only overridden by tests.
func load_settings(path: String = PATH) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		if OS.has_environment("USERNAME"):
			player_name = OS.get_environment("USERNAME")
		_sanitize()
		return
	for prop: String in _props():
		if cf.has_section_key("s", prop):
			# Only take values of the right type (an int is fine for a float): set() would
			# turn a hand-edited fov="abc" into 0.0.
			var v: Variant = cf.get_value("s", prop)
			var cur: Variant = get(prop)
			if typeof(v) == typeof(cur) or (typeof(cur) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				set(prop, v)
	_sanitize()


## Clamps loaded values to what the Settings panel can produce, so a hand-edited or
## future-version settings.cfg can't index out of range or break the camera.
func _sanitize() -> void:
	mouse_sensitivity = _finite_clamp(mouse_sensitivity, 0.2, 3.0, 1.0)
	fov = _finite_clamp(fov, 55.0, 100.0, 72.0)
	master_volume = _finite_clamp(master_volume, 0.0, 1.0, 0.8)
	sfx_volume = _finite_clamp(sfx_volume, 0.0, 1.0, 0.9)
	music_volume = _finite_clamp(music_volume, 0.0, 1.0, 0.4)
	quality = clampi(quality, 0, QUALITY_NAMES.size() - 1)
	color_index = posmod(color_index, RACER_COLORS.size())
	if timer_mode not in ["auto", "on", "off"]:
		timer_mode = "auto"
	player_name = player_name.strip_edges().substr(0, 14)
	if player_name == "":
		player_name = "Runner"
	# party binds: known actions only, int fields only
	var clean: Dictionary = {}
	for action: Variant in party_binds:
		var raw: Variant = party_binds[action]
		if typeof(action) != TYPE_STRING or typeof(raw) != TYPE_DICTIONARY:
			continue
		if str(action) not in ["attack", "use_item", "shove", "cycle_item"]:
			continue
		var b: Dictionary = {}
		for k: String in ["key", "mouse", "pad"]:
			var v: Variant = (raw as Dictionary).get(k, null)
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				b[k] = clampi(int(v), -1, 1 << 30)
		clean[action] = b
	party_binds = clean


static func _finite_clamp(x: float, lo: float, hi: float, fallback: float) -> float:
	return clampf(x, lo, hi) if is_finite(x) else fallback


func save_settings() -> void:
	var cf := ConfigFile.new()
	for prop: String in _props():
		cf.set_value("s", prop, get(prop))
	if Net.preferred_color >= 0:
		# wearing a colour a race host assigned: keep the player's own pick on disk
		cf.set_value("s", "color_index", Net.preferred_color)
	cf.save(PATH)


## F11 / Alt+Enter toggle fullscreen anywhere: menus, paused, even while typing in a
## LineEdit (hence _input, not _unhandled_input).
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_F11 or (k.alt_pressed and (k.physical_keycode == KEY_ENTER or k.physical_keycode == KEY_KP_ENTER)):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply()
	save_settings()


func _props() -> Array[String]:
	return ["mouse_sensitivity", "invert_y", "fov", "master_volume", "sfx_volume", "music_volume",
		"quality", "fullscreen", "vsync", "timer_mode", "player_name", "color_index", "last_room_code", "party_binds"]


## How many particles every emitter builds relative to the High baseline: Low 0.45,
## Medium 0.75, High 1.0, Ultra 1.75. The single source for particle density (Fx and
## PartyFx read it).
func particle_scale() -> float:
	return PARTICLE_SCALE[clampi(quality, 0, PARTICLE_SCALE.size() - 1)]


## Light flashes, heat haze and other screen-reading extras: off on Low only.
func fancy_effects() -> bool:
	return quality >= 1


func my_color() -> Color:
	return RACER_COLORS[color_index % RACER_COLORS.size()]


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		var want: int = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and not (not fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(want)
		# Setting vsync recreates the swapchain even when unchanged (~50 ms per call while
		# dragging a slider), so only touch it on a real change.
		var vs: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode() != vs:
			DisplayServer.window_set_vsync_mode(vs)
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][quality]
		vp.scaling_3d_scale = [0.8, 1.0, 1.0, 1.0][quality]
	if _env != null and is_instance_valid(_sun):
		apply_to_environment(_env, _sun)
	changed.emit()


func apply_to_environment(env: Environment, sun: DirectionalLight3D) -> void:
	_env = env
	_sun = sun
	env.ssao_enabled = quality >= 1
	env.glow_enabled = true
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality >= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [80.0, 120.0, 150.0, 190.0][quality]
