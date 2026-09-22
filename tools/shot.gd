extends Node
## Visual inspection helper: loads a level (or the title), optionally moves the
## player, places a free camera, saves a PNG and quits.
##   godot --path . res://tools/shot.tscn -- --level=0 --cam=0,6,14 --look=0,1,0 --out=C:/tmp/a.png [--player=x,y,z] [--t=1.5] [--follow]

func _arg(name: String, fallback: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return fallback


func _vec(text: String) -> Vector3:
	var p: PackedStringArray = text.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _ready() -> void:
	Game.shot_mode = true
	get_window().always_on_top = true
	var index: int = int(_arg("level", "0"))
	var node: Node
	if index < 0:
		Game.title_screen = _arg("screen", "main")
		node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	else:
		Game.level_index = index
		Game.course_running = true
		Game.course_time = float(_arg("time", "0"))
		node = (load(Game.LEVELS[index]["scene"]) as PackedScene).instantiate()
	add_child(node)
	await get_tree().process_frame
	if index >= 0:
		var lvl := node as LevelBase
		if _arg("player", "") != "":
			lvl.player.teleport(Transform3D(Basis(), _vec(_arg("player", "0,0,0"))))
		if "--follow" not in OS.get_cmdline_user_args():
			var cam := Camera3D.new()
			cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(cam)
			cam.fov = float(_arg("fov", "70"))
			cam.far = 900.0
			cam.global_position = _vec(_arg("cam", "0,6,14"))
			cam.look_at(_vec(_arg("look", "0,1,0")))
			cam.current = true
		elif _arg("yaw", "") != "":
			lvl.camera.yaw = deg_to_rad(float(_arg("yaw", "0")))
			lvl.camera.pitch = deg_to_rad(float(_arg("pitch", "-22")))
	await get_tree().create_timer(float(_arg("t", "1.2"))).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(_arg("out", "user://shot.png"))
	get_tree().quit()
