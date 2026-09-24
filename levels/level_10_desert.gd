extends LevelBase
## 10. SCARAB SANDS - PLACEHOLDER. A blazing desert of colossal pyramids and an ancient sun temple full of traps.
## The real level is being built against docs/NEW_WORLDS_BRIEF.md; this stub only keeps the level
## list, level select, saves and tests working: two hops, two checkpoints, a walk to the finish, and a
## couple of machines beside the path.


func _configure() -> void:
	theme_id = "desert"
	music_track = "desert"
	kill_y = -40.0


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 0), 0.0)
	kit.plat(Vector3(0, 0, 0), Vector3(14, 2, 14), "main", 0.0)
	kit.plat(Vector3(0, 0.5, -12.0), Vector3(3, 1, 3), "alt", 0.0)
	kit.plat(Vector3(0, 1.0, -21.0), Vector3(6, 1.4, 6), "main", 0.0)
	kit.checkpoint(Vector3(0, 1.0, -21.0), 0.0)
	kit.plat(Vector3(0, 1.0, -34.0), Vector3(6, 1.4, 20), "main", 0.0)
	kit.checkpoint(Vector3(0, 1.0, -32.0), 0.0)
	kit.finish(Vector3(0, 1.0, -42.0), 0.0)
	# machines off to the side (so the level has something to hear and see)
	kit.plat(Vector3(9, 1.0, -34.0), Vector3(6, 1.4, 10), "alt", 0.0)
	kit.laser(Vector3(9, 2.2, -34.0), Vector3(5.0, 2.4, 0.3), 3.0, 0.5, 0.0)
	kit.piston(Vector3(11.5, 1.6, -30.0), Vector3(1.4, 1.2, 1.4), 90.0, 2.0, 3.0, 0.0)
	r_jump(Vector3(0, 0.1, -6.6), Vector3(0, 0.6, -12.0))
	r_jump(Vector3(0, 0.6, -13.2), Vector3(0, 1.1, -20.0))
	r_checkpoint()
	r_walk(Vector3(0, 1.1, -32.0))
	r_checkpoint()
	r_walk(Vector3(0, 1.1, -42.0))
