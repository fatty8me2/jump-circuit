extends LevelBase
## Movement playground: one of everything on a big safe floor, for tuning
## resources/default_tuning.tres with the F3 readout open.
## Launch the game with  -- --dev  and pick Playground on the title screen.


func _configure() -> void:
	level_id = "playground"
	theme_id = "gardens"
	kill_y = -30.0


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 0), 0.0)
	kit.plat(Vector3(0, 0, -30), Vector3(90, 2, 110), "main", 3.0)
	# jump rulers: gaps of 3, 4.5, 6 m and steps of 1, 1.6, 2.2 m
	var x: float = -30.0
	for h: float in [1.0, 1.6, 2.2]:
		kit.plat(Vector3(x, h, -10), Vector3(4, h, 4), "alt", 0.0)
		x += 6.0
	var z: float = -22.0
	for gap: float in [3.0, 4.5, 6.0]:
		kit.plat(Vector3(-24, 3.0, z), Vector3(5, 0.5, 4), "accent", 0.0)
		z -= 4.0 + gap
	kit.ramp(Vector3(-24, 1.5, -13.4), Vector3(5, 0.5, 6.4), 28.0)
	# pads
	kit.pad(Vector3(0, 0, -10), 14.0)
	kit.pad(Vector3(4, 0, -10), 20.0)
	kit.pad(Vector3(8, 0, -10), 26.0)
	kit.pad(Vector3(0, 0, -18), 19.0, 40.0)
	kit.pad(Vector3(4, 0, -18), 24.0, 30.0)
	kit.pad(Vector3(8, 0, -18), 22.0, 55.0, -90.0)
	# movers
	var pts: Array[Vector3] = [Vector3.ZERO, Vector3(12, 0, 0)]
	kit.mover(Vector3(14, 1.2, -30), Vector3(4, 0.5, 4), pts, 6.0)
	var lift: Array[Vector3] = [Vector3.ZERO, Vector3(0, 8, 0)]
	kit.mover(Vector3(14, 0.6, -38), Vector3(4, 0.5, 4), lift, 5.0)
	kit.orbiter(Vector3(30, 7, -50), 5.0, Vector3.FORWARD, Vector3(3.5, 0.5, 3.5), 9.0)
	kit.orbiter(Vector3(30, 7, -50), 5.0, Vector3.FORWARD, Vector3(3.5, 0.5, 3.5), 9.0, 0.5)
	var arms: Array[Dictionary] = [{"pos": Vector3(4.5, 0, 0), "size": Vector3(7, 0.5, 2.6)}, {"pos": Vector3(-4.5, 0, 0), "size": Vector3(7, 0.5, 2.6)}]
	kit.spinner(Vector3(0, 1.0, -48), 10.0, arms, 1.8)
	# tilt boards: calm, lively, hanging, sinking
	kit.tilt(Vector3(-12, 1.6, -34), Vector3(9, 0.4, 3.2), {"edge_tilt_deg": 8.0, "max_tilt_deg": 11.0})
	kit.tilt(Vector3(-12, 1.6, -42), Vector3(9, 0.4, 3.2), {"edge_tilt_deg": 18.0, "max_tilt_deg": 24.0})
	kit.tilt(Vector3(-12, 1.6, -52), Vector3(5, 0.4, 5), {"tilt_about_x": true, "edge_tilt_deg": 10.0, "support": "cables"})
	kit.tilt(Vector3(-22, 2.4, -52), Vector3(4.5, 0.4, 4.5), {"tilt_about_z": false, "sink_depth": 1.2, "support": "cables"})
	# collapsing stones
	for i: int in 5:
		kit.collapse(Vector3(18 + i * 4.2, 2.0, -66), 2.6)
	for i: int in 6:
		kit.ball(Vector3(-4 + i * 1.6, 0.6, 6), 0.4, Look.c("accent").lerp(Look.c("accent2"), i / 5.0))
	# momentum toolkit
	kit.boost(Vector3(24, 0.03, -8), Vector3(3, 0.2, 14), 0.0, 20.0)
	kit.boost(Vector3(30, 0.03, -8), Vector3(3, 0.2, 14), 0.0, 28.0)
	kit.conveyor(Vector3(36, 0.03, -8), Vector3(3, 0.2, 14), 180.0, 6.0)
	kit.slick(Vector3(-36, 5.0, -40), Vector3(5, 0.4, 20), 180.0, 25.0)
	kit.slick(Vector3(-36, 0.03, -62), Vector3(8, 0.2, 12))
	kit.hazard(Vector3(20, 0.3, -24), Vector3(6, 0.6, 1.5))
	kit.sweeper(Vector3(30, 0, -30), 5.0, 2, 3.5)
	kit.pendulum(Vector3(10, 9, -66), 8.0, 3.2)
	kit.bumper(Vector3(-4, 0, -30), 16.0)
	kit.bumper(Vector3(-7, 0, -33), 16.0)
	kit.bumper(Vector3(-2, 0, -35), 16.0)
	kit.wind(Vector3(38, 8, -40), Vector3(4, 16, 4), Vector3(0, 70, 0))
	for i: int in 4:
		kit.blink(Vector3(20 + i * 3.5, 1.5, -76), Vector3(2.5, 0.4, 2.5), 3.0, 0.55, i * 0.25)
	kit.checkpoint(Vector3(0, 0, -4), 0.0)
	kit.checkpoint(Vector3(0, 0, -60), 0.0)
	kit.finish(Vector3(0, 0, -80), 0.0)
	kit.cloud_field(Vector3(0, -20, -30), Vector3(120, 5, 120), 14)
