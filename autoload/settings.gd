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
## 0 low, 1 medium, 2 high
var quality: int = 2
var fullscreen: bool = false
var vsync: bool = true
## "auto" hides the timer until a level has been finished once.
var timer_mode: String = "auto"
var player_name: String = "Runner"
var color_index: int = 0
var last_ip: String = "127.0.0.1"

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


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		if OS.has_environment("USERNAME"):
			player_name = OS.get_environment("USERNAME").substr(0, 14)
		return
	for prop: String in _props():
		if cf.has_section_key("s", prop):
			set(prop, cf.get_value("s", prop))


func save_settings() -> void:
	var cf := ConfigFile.new()
	for prop: String in _props():
		cf.set_value("s", prop, get(prop))
	cf.save(PATH)


func _props() -> Array[String]:
	return ["mouse_sensitivity", "invert_y", "fov", "master_volume", "sfx_volume", "music_volume",
		"quality", "fullscreen", "vsync", "timer_mode", "player_name", "color_index", "last_ip"]


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
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
		vp.scaling_3d_scale = [0.8, 1.0, 1.0][quality]
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
	sun.directional_shadow_max_distance = [80.0, 120.0, 150.0][quality]
