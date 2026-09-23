extends LevelBase
## Test course for the RouteBot's w_run / m_climb / portal steps (test_x_bot_new_moves):
## a gap only a wall run crosses (kick off onto the landing), a 3.4 m mantle wall, then a
## warp ring out to the finish deck. Not a real level - never in Game.LEVELS.


func _configure() -> void:
	level_id = "moves_test"
	theme_id = "orbital"
	kill_y = -30.0


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 2), 0.0)
	kit.plat(Vector3(0, 0, 0), Vector3(10, 2, 10))
	# 19 m gap along the panel
	kit.wallrun(Vector3(2.0, 1.2, -15), Vector3(14, 6, 0.5), 90.0)
	kit.plat(Vector3(-1, 0, -29), Vector3(8, 2, 10))
	kit.checkpoint(Vector3(-1, 0, -27), 0.0)
	# mantle wall on the landing, portal on top of it
	kit.ledge(Vector3(-1, 3.4, -36), Vector3(6, 3.4, 8))
	var pr: WarpPortal = kit.portal(Vector3(-1, 3.4, -38.5), 0.0, Vector3(14, 0, -40), 0.0)
	kit.plat(Vector3(14, 0, -46), Vector3(10, 2, 16))
	kit.finish(Vector3(14, 0, -50), 0.0)
	r_wallrun(Vector3(0.3, 0, -4.6), Vector3(1.6, 1.2, -9.0), Vector3(1.6, 1.2, -19.0), Vector3(-1.5, 0, -27.0))
	r_checkpoint()
	r_mantle(Vector3(-1, 0, -30.4), Vector3(-1, 3.4, -34.0))
	r_portal(Vector3(-1, 3.4, -38.5), pr.exit_point())
	r_walk(Vector3(14, 0, -50))
