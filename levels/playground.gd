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
	_build_kit_gallery()


# ---- Kit Gallery -------------------------------------------------------------------------------
# East of the main floor (walk through the gap past the spawn, +X): one of each generic kit
# obstacle (docs/KIT_OBSTACLES.md) on a safe floor, labelled. Decks are raised 1-1.4 m so falling
# off just means landing on the floor.

func _build_kit_gallery() -> void:
	kit.plat(Vector3(47.5, 0, -8), Vector3(5, 2, 12), "main", 0.0)
	kit.plat(Vector3(115, 0, -35), Vector3(130, 2, 100), "main", 3.0)
	_gallery_label(Vector3(54, 3.2, -2), "KIT GALLERY")
	# row 1 ---------------------------------------------------------------------------------
	# 1 launch barrel: walk in, wait out the tell, get fired onto the deck
	var landing := Vector3(62, 1.0, -28)
	kit.plat(landing, Vector3(8, 1, 8), "accent", 0.0)
	kit.barrel(Vector3(62, 0, -8), landing, 3.0, 3.0, 0.0)
	_gallery_label(Vector3(62, 4.5, -4), "1  Launch barrel")
	# 2 zipline
	kit.zipline(Vector3(80, 0, -6), Vector3(80, 0, -38), 11.0, 1.4)
	_gallery_label(Vector3(80, 4.5, -4), "2  Zipline  (jump to let go)")
	# 3 cannonball battery firing across a walkway
	kit.battery(Vector3(110, 0, -20), 90.0, 20.0, 9.0, 3.2, 0.0, 0.0)
	_gallery_label(Vector3(104, 4.5, -10), "3  Cannonball battery")
	# 4 rolling log between two decks
	kit.plat(Vector3(124, 1.4, -8), Vector3(8, 1.4, 6), "accent", 0.0)
	kit.log_roller(Vector3(124, 1.4, -21), 16.0, 2.6, 90.0, 3.0, 6.0, 0.0)
	kit.plat(Vector3(124, 1.4, -34), Vector3(8, 1.4, 6), "accent", 0.0)
	_gallery_label(Vector3(124, 5.0, -6), "4  Rolling log")
	# 5 seesaw between two decks
	kit.plat(Vector3(142, 1.0, -10), Vector3(8, 1, 8), "accent", 0.0)
	kit.seesaw(Vector3(142, 1.0, -19), 9.0, 2.6, false, 0.0)
	kit.plat(Vector3(142, 1.0, -28), Vector3(8, 1, 8), "accent", 0.0)
	_gallery_label(Vector3(142, 4.5, -6), "5  Seesaw")
	# row 2 ---------------------------------------------------------------------------------
	# 6 flipper: stand near its tip and get swatted across the gap
	kit.plat(Vector3(62, 1.0, -48.5), Vector3(14, 1, 9), "accent", 0.0)
	kit.flipper(Vector3(62, 1.0, -51), 5.0, 0.0, 80.0, 4.0, 0.0)
	kit.plat(Vector3(62, 1.0, -61), Vector3(14, 1, 10), "accent", 0.0)
	_gallery_label(Vector3(62, 5.0, -45), "6  Flipper paddle")
	# 7 drawbridge
	kit.plat(Vector3(86, 1.0, -46), Vector3(10, 1, 8), "accent", 0.0)
	kit.drawbridge(Vector3(86, 1.0, -50), 8.0, 3.4, 0.0, 9.0, 0.0)
	kit.plat(Vector3(86, 1.0, -62), Vector3(10, 1, 8), "accent", 0.0)
	_gallery_label(Vector3(86, 5.5, -43), "7  Drawbridge")
	# 8 gap wall
	kit.gap_wall(Vector3(106, 0, -52), 0.0, 3.4, 8.0, 0.0)
	_gallery_label(Vector3(106, 6.5, -46), "8  Gap wall")
	# 9 falling blocks: one on the clock, one that waits for you
	kit.falling_block(Vector3(126, 0, -50), Vector3(3, 1.6, 3), 7.0, 5.0, 0.0)
	kit.falling_block(Vector3(126, 0, -62), Vector3(3, 1.6, 3), 7.0, 5.0, 0.0, true)
	_gallery_label(Vector3(126, 9.0, -44), "9  Falling block")
	# 10 spinning hammer
	kit.hammer(Vector3(146, 0, -54), 5.0, 4.8, 0.0, 180.0)
	_gallery_label(Vector3(146, 5.0, -46), "10  Spinning hammer")


func _gallery_label(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.012
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1, 1, 1)
	l.position = pos
	add_child(l)
