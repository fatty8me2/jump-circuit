extends LevelBase
## PLACEHOLDER for Orbital Drift - replaced by the real course. Kept minimal and valid
## (spawn, two checkpoints, finish, bot route) so menus and tests run meanwhile.


func _configure() -> void:
	theme_id = "orbital"
	music_track = "b"
	kill_y = -40.0


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	kit.plat(Vector3(0, 0, 0), Vector3(12, 2, 12))
	kit.plat(Vector3(0, 0, -11), Vector3(6, 2, 6))
	kit.checkpoint(Vector3(0, 0, -11))
	kit.plat(Vector3(0, 0, -21), Vector3(6, 2, 6))
	kit.checkpoint(Vector3(0, 0, -21))
	kit.plat(Vector3(0, 0, -32), Vector3(10, 2, 10))
	kit.finish(Vector3(0, 0, -34))
	r_jump(Vector3(0, 0, -5.6), Vector3(0, 0, -10))
	r_checkpoint()
	r_jump(Vector3(0, 0, -13.6), Vector3(0, 0, -20))
	r_checkpoint()
	r_jump(Vector3(0, 0, -23.6), Vector3(0, 0, -29))
	r_walk(Vector3(0, 0, -34))
