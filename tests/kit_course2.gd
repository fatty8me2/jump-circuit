extends LevelBase
## Test course for the generic obstacle kit, part 2 (test_zk_bot_slice2): gap wall, falling block,
## spinning hammer, flipper paddle (ridden as a launcher) and drawbridge. Not a real level - never
## in Game.LEVELS. Worked example of wiring each obstacle into a route (docs/KIT_OBSTACLES.md).

var wall: GapWall
var blk: FallingBlock
var ham: SpinHammer
var flip: Flipper
var bridge: Drawbridge


func _configure() -> void:
	level_id = "kit_test2"
	theme_id = "volcano"
	kill_y = -30.0


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 2), 0.0)
	# 1. gap wall across the first deck
	kit.plat(Vector3(0, 0, -4), Vector3(14, 1, 20))
	wall = kit.gap_wall(Vector3(0, 0, -9), 0.0, 3.4, 8.0, 0.0)
	# 2. falling block over a narrow deck (it spans the full width)
	kit.plat(Vector3(0, 0, -24), Vector3(6, 1, 20))
	kit.checkpoint(Vector3(0, 0, -18), 0.0)
	blk = kit.falling_block(Vector3(0, 0, -25), Vector3(6, 1.6, 3), 7.0, 5.0, 0.0)
	# 3. spinning hammer on a round deck; the path passes the post on the +X side
	kit.disc(Vector3(0, 0, -42), 8.0)
	ham = kit.hammer(Vector3(0, 0, -42), 5.0, 4.8, 0.0, 180.0)
	# 4. flipper: stand near its tip and get swatted over the gap
	kit.plat(Vector3(0, 0, -54), Vector3(14, 1, 9))
	flip = kit.flipper(Vector3(0, 0, -56.5), 5.0, 0.0, 80.0, 4.0, 0.0)
	kit.plat(Vector3(0, 0, -66.5), Vector3(14, 1, 12))
	kit.checkpoint(Vector3(0, 0, -64), 0.0)
	# 5. drawbridge from the far edge of that deck to the finish deck
	bridge = kit.drawbridge(Vector3(0, 0, -72.5), 8.0, 3.4, 0.0, 9.0, 0.0)
	kit.plat(Vector3(0, 0, -86), Vector3(12, 1, 12))
	kit.finish(Vector3(0, 0, -88), 0.0)

	r_walk(Vector3(0, 0, -6))
	r_until(func() -> bool: return wall.is_open_for(Game.course_time, 2.0))
	r_walk(Vector3(0, 0, -18))
	r_checkpoint()
	r_until(func() -> bool: return blk.is_clear_for(Game.course_time, 1.8))
	r_walk(Vector3(0, 0, -31))
	r_walk(Vector3(2, 0, -33))
	r_until(func() -> bool: return ham.is_parked_for(Game.course_time, 2.0))
	r_walk(Vector3(2, 0, -47))
	r_walk(Vector3(3.5, 0, -56.5))
	route.append({"kind": "kick", "from": Vector3(3.5, 0, -56.5), "to": Vector3(0, 0, -66)})
	r_walk(Vector3(0, 0, -64))
	r_checkpoint()
	r_walk(Vector3(0, 0, -70))
	r_until(func() -> bool: return bridge.is_down_for(Game.course_time, 2.2))
	r_walk(Vector3(0, 0, -86))
	r_walk(Vector3(0, 0, -88))
