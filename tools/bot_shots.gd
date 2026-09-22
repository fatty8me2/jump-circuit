extends Node
## Windowed bot run that saves frames through the REAL follow camera, steering
## the camera yaw toward the direction of travel like a player would.
##   godot --path . res://tools/bot_shots.tscn -- --level=0 --every=1.5 --out=C:/dir/prefix [--max=40]

var _lvl: LevelBase
var _bot: RouteBot
var _every: float = 1.5
var _next: float = 0.5
var _count: int = 0
var _max: int = 40
var _prefix: String = "user://bot"
var _t: float = 0.0


func _arg(key: String, fallback: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.trim_prefix("--%s=" % key)
	return fallback


func _ready() -> void:
	Game.shot_mode = true
	get_window().always_on_top = true
	_every = float(_arg("every", "1.5"))
	_max = int(_arg("max", "40"))
	_prefix = _arg("out", "user://bot")
	Game.level_index = int(_arg("level", "0"))
	Game.course_running = true
	Game.course_time = 0.0
	SaveData.path_override = "user://shots_progress.json"
	_lvl = (load(Game.LEVELS[Game.level_index]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(_lvl)
	await get_tree().process_frame
	_bot = RouteBot.new()
	_bot.keep_camera = true
	_lvl.add_child(_bot)
	_bot.attach(_lvl)


func _process(dt: float) -> void:
	if _bot == null:
		return
	_t += dt
	# aim the camera where the player is heading, the way a human holds the mouse
	var v := Vector3(_lvl.player.velocity.x, 0, _lvl.player.velocity.z)
	if v.length() > 2.0:
		var want: float = atan2(-v.x, -v.z)
		_lvl.camera.yaw = lerp_angle(_lvl.camera.yaw, want, 1.0 - exp(-2.5 * dt))
	if _t >= _next and _count < _max:
		_next += _every
		_count += 1
		var img: Image = get_viewport().get_texture().get_image()
		img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		img.save_png("%s_%02d.png" % [_prefix, _count])
	if _bot.done or _bot.stuck or _count >= _max or _t > 200.0:
		print("bot done=%s respawns=%d frames=%d time=%.1f" % [str(_bot.done), _bot.retries, _count, _lvl.run_time])
		set_process(false)
		await get_tree().create_timer(3.0 if _bot.done else 0.1).timeout
		var img2: Image = get_viewport().get_texture().get_image()
		img2.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		img2.save_png("%s_end.png" % _prefix)
		get_tree().quit()
