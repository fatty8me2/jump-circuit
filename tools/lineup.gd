extends Node
## Visual check for the earnable cosmetics: stands a row of racers on a level's start platform
## (that level's light and sky), dressed one item each, saves a PNG and quits.
##   godot --path . res://tools/lineup.tscn -- --kind=character|hat|paint [--base=volt] [--level=0]
##         [--from=0] [--count=12] [--yaw=180] [--out=C:/tmp/lineup.png]

const SAVE := "user://shot_progress.json"


func _arg(name: String, fallback: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return fallback


func _ready() -> void:
	Game.shot_mode = true
	get_tree().create_timer(40.0).timeout.connect(func() -> void:
		printerr("lineup: timed out")
		get_tree().quit(3))
	SaveData.path_override = SAVE
	get_window().always_on_top = true
	var kind: String = _arg("kind", "character")
	var base: String = _arg("base", "volt")
	var index: int = int(_arg("level", "0"))
	Game.level_index = index
	Game.course_running = false
	var lvl := (load(Game.LEVELS[index]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	await get_tree().process_frame
	lvl.player.visible = false
	var ids: Array = (Cosmetics.KINDS[kind]["items"] as Dictionary).keys()
	var from: int = int(_arg("from", "0"))
	ids = ids.slice(from, mini(from + int(_arg("count", "12")), ids.size()))
	var origin: Vector3 = lvl.player.global_position
	var gap: float = 1.25
	var width: float = gap * float(ids.size() - 1)
	for i: int in ids.size():
		var v := PlayerVisual.new()
		lvl.add_child(v)
		v.global_position = origin + Vector3(-width * 0.5 + gap * float(i), 0.0, 0.0)
		v.rotation.y = deg_to_rad(float(_arg("yaw", "180")))
		v.set_accent(Settings.RACER_COLORS[i % Settings.RACER_COLORS.size()])
		match kind:
			"character":
				v.set_character(String(ids[i]))
			"hat":
				v.set_character(base)
				v.set_hat(String(ids[i]))
			"paint":
				v.set_character(base)
				v.set_paint(String(ids[i]))
		var tag := Label3D.new()
		tag.text = String(Cosmetics.item_name(kind, String(ids[i])))
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 28
		tag.outline_size = 8
		tag.pixel_size = 0.004
		tag.position = Vector3(0, 2.05, 0)
		v.add_child(tag)
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = 40.0
	add_child(cam)
	var dist: float = maxf(3.2, width * 0.95 + 2.2)
	cam.global_position = origin + Vector3(0, 1.1, dist)
	cam.look_at(origin + Vector3(0, 0.85, 0))
	cam.make_current()
	await get_tree().create_timer(float(_arg("t", "1.5"))).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(_arg("out", "user://lineup.png"))
	get_tree().quit(0)
