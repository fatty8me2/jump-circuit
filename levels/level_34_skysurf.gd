extends LevelBase
## 34. SKY SURF - PLACEHOLDER (FLOW section). A pastel sunrise cloudscape of floating islands and wind ribbons.
## The real level is being built against docs/FLOW_BRIEF.md; this stub only keeps the level
## list, level select, saves and tests working: two hops, two checkpoints and a walk to the finish.


func _configure() -> void:
	theme_id = "skysurf"
	music_track = "skysurf"
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
	r_jump(Vector3(0, 0.1, -6.6), Vector3(0, 0.6, -12.0))
	r_jump(Vector3(0, 0.6, -13.2), Vector3(0, 1.1, -20.0))
	r_checkpoint()
	r_walk(Vector3(0, 1.1, -32.0))
	r_checkpoint()
	r_walk(Vector3(0, 1.1, -42.0))
