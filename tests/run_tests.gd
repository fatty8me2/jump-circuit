extends TestLib
## Headless physics/integration tests.
##   godot --headless --path . res://tests/run_tests.tscn
## Optional user args:  -- --only=<substring>   -- --fps=<n> (cap render rate)

const FWD := Vector2(0, 1)

## -- --level=<index> restricts the per-level tests to one level.
var only_level: int = -1


func _ready() -> void:
	SaveData.path_override = "user://test_progress.json"
	SaveData.wipe()
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--level="):
			only_level = int(a.trim_prefix("--level="))
		elif a.begins_with("--fps="):
			Engine.max_fps = int(a.trim_prefix("--fps="))
	await ticks(3)
	var tests: Array[String] = []
	for m: Dictionary in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_") and (only == "" or n.contains(only)):
			tests.append(n)
	for n: String in tests:
		print("\n== ", n)
		await call(n)
	if world != null:
		world.queue_free()
	print("\n---- metrics ----")
	for k: String in metrics:
		print("  %-34s %s" % [k, str(metrics[k])])
	print("\nRESULT: %d passed, %d failed  (render fps cap: %d)" % [passed, failed, Engine.max_fps])
	SaveData.delete_files()
	get_tree().quit(1 if failed > 0 else 0)


# ---- core movement -----------------------------------------------------------------------

func test_a_run_and_brake() -> void:
	await new_world()
	floor_slab()
	await settle()
	check(player.grounded, "player settles grounded on a slab")
	player.cmd_move = FWD
	var t_to_90: float = -1.0
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	for i: int in 240:
		await get_tree().physics_frame
		if t_to_90 < 0.0 and player.horizontal_speed() >= player.tuning.max_speed * 0.9:
			t_to_90 = float(i + 1) * dt
	near(player.horizontal_speed(), player.tuning.max_speed, 0.05, "run speed settles at max_speed")
	check(t_to_90 > 0.05 and t_to_90 < 0.25, "reaches 90%% speed quickly but not instantly (%.3fs)" % t_to_90)
	metrics["time_to_90pct_speed_s"] = t_to_90
	var z0: float = player.global_position.z
	player.cmd_move = Vector2.ZERO
	await seconds(0.6)
	var brake: float = absf(player.global_position.z - z0)
	check(player.horizontal_speed() < 0.01, "stops fully with no input")
	check(brake > 0.3 and brake < 1.2, "braking distance has weight but is short (%.2fm)" % brake)
	metrics["brake_distance_m"] = brake


func test_b_jump_heights() -> void:
	await new_world()
	floor_slab()
	await settle()
	var y0: float = player.global_position.y
	player.press_jump()
	player.cmd_jump = true
	await get_tree().physics_frame
	check(player.velocity.y > 10.0, "jump fires on the very tick after the press")
	var air: float = await wait_landing()
	var full: float = player.last_jump_height
	player.cmd_jump = false
	await settle()
	await tap_jump(0.03)
	await wait_landing()
	var tap: float = player.last_jump_height
	await settle()
	await tap_jump(0.15)
	await wait_landing()
	var mid: float = player.last_jump_height
	check(full > 2.2 and full < 3.0, "full jump height in design range (%.2fm)" % full)
	check(tap < full * 0.5, "tap jump is much shorter (%.2fm)" % tap)
	check(mid > tap + 0.2 and mid < full - 0.2, "hold duration scales height (%.2fm)" % mid)
	near(player.global_position.y, y0, 0.02, "lands back at floor height")
	metrics["jump_full_height_m"] = full
	metrics["jump_tap_height_m"] = tap
	metrics["jump_full_airtime_s"] = air


func test_c_running_jump_distance() -> void:
	await new_world()
	floor_slab()
	await settle()
	player.cmd_move = FWD
	await seconds(0.8)
	player.press_jump()
	player.cmd_jump = true
	await wait_landing()
	var d_full: float = player.last_jump_distance
	player.cmd_jump = false
	await seconds(0.5)
	await tap_jump(0.03)
	await wait_landing()
	var d_tap: float = player.last_jump_distance
	check(d_full > 6.0 and d_full < 8.5, "full running jump covers %.2fm" % d_full)
	check(d_tap > 2.0 and d_tap < d_full * 0.7, "tap running jump covers %.2fm" % d_tap)
	near(player.horizontal_speed(), player.tuning.max_speed, 0.2, "landing keeps running speed (no landing stall)")
	metrics["run_jump_full_distance_m"] = d_full
	metrics["run_jump_tap_distance_m"] = d_tap


func test_d_coyote_and_buffer() -> void:
	await new_world(Vector3(0, 5.05, 0))
	kit.plat(Vector3(0, 5, 0), Vector3(6, 1, 6), "main", 0.0)
	floor_slab()
	await settle()
	player.cmd_move = FWD
	while player.grounded:
		await get_tree().physics_frame
	await seconds(0.07)
	player.press_jump()
	player.cmd_jump = true
	await ticks(2)
	check(player.velocity.y > 8.0, "coyote: jump still works 0.07s after leaving the edge")
	await wait_landing()
	player.cmd_jump = false
	# too late
	player.teleport(Transform3D(Basis(), Vector3(0, 5.05, 0)))
	await settle()
	player.cmd_move = FWD
	while player.grounded:
		await get_tree().physics_frame
	await seconds(0.25)
	player.press_jump()
	await ticks(2)
	check(player.velocity.y < 0.0, "coyote: no mid-air jump after the window closes")
	# buffer: press shortly before touching down
	while not player.grounded:
		if player.global_position.y < 0.55 and player.velocity.y < 0.0:
			player.press_jump()
			player.cmd_jump = true
			break
		await get_tree().physics_frame
	var jumped_again: bool = false
	for i: int in 30:
		await get_tree().physics_frame
		if player.velocity.y > 8.0:
			jumped_again = true
			break
	check(jumped_again, "buffer: a press just before landing jumps on touchdown")


func test_e_air_control_has_momentum() -> void:
	await new_world()
	floor_slab()
	await settle()
	player.cmd_move = FWD
	await seconds(0.8)
	player.press_jump()
	player.cmd_jump = true
	await ticks(2)
	player.cmd_move = Vector2(0, -1)
	await seconds(0.15)
	check(player.velocity.z < -3.0, "0.15s of opposite input does not reverse a running jump (vz %.2f)" % player.velocity.z)
	await wait_landing()
	check(player.last_jump_distance < 5.0, "but holding back does shorten the jump usefully (%.2fm)" % player.last_jump_distance)
	player.cmd_jump = false
	# standing jump + steer: correction without launch speed
	await settle()
	player.press_jump()
	player.cmd_jump = true
	await ticks(2)
	player.cmd_move = Vector2(1, 0)
	await wait_landing()
	check(player.last_jump_distance > 2.0, "standing jump can be steered sideways (%.2fm)" % player.last_jump_distance)
	metrics["standing_jump_steer_distance_m"] = player.last_jump_distance


func test_f_slopes_edges_ceiling_fall() -> void:
	await new_world(Vector3(0, 0.05, 6))
	floor_slab()
	kit.ramp(Vector3(0, 2.0, -3.46), Vector3(5, 0.5, 8), 30.0)
	await settle()
	player.cmd_move = FWD
	await seconds(1.6)
	check(player.global_position.y > 3.0, "walks up a 30 degree ramp without snagging (y %.2f)" % player.global_position.y)
	# stand on the slope
	player.teleport(Transform3D(Basis(), Vector3(0, 2.3, -3.46)))
	await settle()
	var p0: Vector3 = player.global_position
	await seconds(1.0)
	check(player.grounded and player.global_position.distance_to(p0) < 0.02, "stands still on a slope (no unintended sliding)")
	# ceiling
	kit.plat(Vector3(30, 2.6, 0), Vector3(4, 0.5, 4), "main", 0.0)
	player.teleport(Transform3D(Basis(), Vector3(30, 0.05, 0)))
	await settle()
	player.press_jump()
	player.cmd_jump = true
	var air: float = await wait_landing()
	player.cmd_jump = false
	check(air < 0.6 and player.grounded, "ceiling bonk ends the rise and returns promptly (air %.2fs)" % air)
	# high-speed landing on a thin platform
	kit.plat(Vector3(60, 0, 0), Vector3(4, 0.3, 4), "main", 0.0)
	player.teleport(Transform3D(Basis(), Vector3(60, 70, 0)))
	player.position.y = 70.0
	await wait_landing(8.0)
	check(player.grounded and absf(player.global_position.y - 0.0) < 0.05, "terminal-velocity landing on a 0.3m slab does not tunnel")
	# lip: run across a seam between two flush platforms
	kit.plat(Vector3(90, 0, 0), Vector3(4, 1, 4), "main", 0.0)
	kit.plat(Vector3(90, 0, -4), Vector3(4, 1, 4), "main", 0.0)
	player.teleport(Transform3D(Basis(), Vector3(90, 0.05, 1)))
	await settle()
	player.cmd_move = FWD
	await seconds(0.6)
	near(player.horizontal_speed(), player.tuning.max_speed, 0.05, "no snag crossing a seam between platforms")


# ---- mechanics --------------------------------------------------------------------------------

func test_g_bounce_pads() -> void:
	await new_world(Vector3(0, 3, 0))
	floor_slab()
	var pad: BouncePad = kit.pad(Vector3(0, 0, 0), 20.0)
	var heights: Array[float] = []
	var bounces: Array[int] = [0]
	player.bounced.connect(func(_s: float) -> void: bounces[0] += 1)
	for i: int in 3:
		player.teleport(Transform3D(Basis(), Vector3(0.2 * i, 2.0 + i, 0)))
		while bounces[0] <= i:
			await get_tree().physics_frame
		var apex: float = player.global_position.y
		while player.velocity.y > 0.0:
			await get_tree().physics_frame
			apex = maxf(apex, player.global_position.y)
		heights.append(apex)
		player.cmd_move = Vector2(1, 0)       # steer off the pad
		await wait_landing()
		player.cmd_move = Vector2.ZERO
	var expect: float = 20.0 * 20.0 / (2.0 * player.tuning.gravity_rise) + 0.1
	near(heights[0], expect, 0.25, "vertical pad apex matches v^2/2g")
	check(absf(heights[0] - heights[1]) < 0.05 and absf(heights[1] - heights[2]) < 0.05, "same pad gives the same height regardless of drop height")
	check(bounces[0] == 3, "exactly one bounce trigger per contact (%d)" % bounces[0])
	metrics["pad20_apex_m"] = heights[0]
	# jump buffered into a pad must not override the launch
	player.teleport(Transform3D(Basis(), Vector3(0, 1.0, 0)))
	player.press_jump()
	while bounces[0] < 4:
		player.press_jump()
		await get_tree().physics_frame
	await ticks(3)
	check(player.velocity.y > 18.0, "a buffered jump cannot overwrite a pad launch")
	await wait_landing()
	# angled pad lands where Ballistics predicts
	var apad: BouncePad = kit.pad(Vector3(40, 0, 0), 19.0, 40.0)
	player.cmd_move = Vector2.ZERO
	player.teleport(Transform3D(Basis(), Vector3(40, 1.5, 0)))
	var base_count: int = bounces[0]
	while bounces[0] == base_count:
		await get_tree().physics_frame
	player.cmd_move = FWD
	await wait_landing()
	var launch: Dictionary = apad.get_launch()
	var predicted: Vector3 = Ballistics.landing_point(player.tuning, apad.launch_origin(), launch["velocity"], 0.0)
	var err: float = Vector2(player.global_position.x - predicted.x, player.global_position.z - predicted.z).length()
	check(err < 0.6, "angled pad landing matches the predicted arc (error %.2fm, flew %.1fm, predicted %.1fm)" % [err, absf(player.global_position.z), absf(predicted.z)])
	metrics["pad19@40deg_range_m"] = absf(player.global_position.z)
	check(pad != null, "pads built")


func test_h_moving_platform() -> void:
	await new_world(Vector3(0, 0.5, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -6, 0))
	var pts: Array[Vector3] = [Vector3.ZERO, Vector3(12, 0, 0)]
	var m: MovingPlatform = kit.mover(Vector3(0, 0, 0), Vector3(4, 0.5, 4), pts, 6.0)
	await settle()
	var rel0: Vector3 = player.global_position - m.global_position
	var max_drift: float = 0.0
	for i: int in 360:
		await get_tree().physics_frame
		max_drift = maxf(max_drift, (player.global_position - m.global_position - rel0).length())
	check(player.grounded and max_drift < 0.12, "rides a moving platform through a full stroke without drifting (max %.3fm)" % max_drift)
	# take off mid-stroke: inherit platform velocity exactly once
	while true:
		await get_tree().physics_frame
		if player.platform_velocity.x > 3.5:
			break
	var pv: float = player.platform_velocity.x
	player.press_jump()
	player.cmd_jump = true
	await ticks(3)
	near(player.velocity.x, pv, 0.35, "takeoff inherits platform velocity once (platform %.2f m/s)" % pv)
	await wait_landing()
	player.cmd_jump = false
	# vertical lift
	var lift_pts: Array[Vector3] = [Vector3.ZERO, Vector3(0, 8, 0)]
	var lift: MovingPlatform = kit.mover(Vector3(40, 0, 0), Vector3(4, 0.5, 4), lift_pts, 5.0)
	player.teleport(Transform3D(Basis(), Vector3(40, 0.2, 0) + lift.offset_at(Game.course_time)))
	await seconds(0.3)
	var air_ticks: int = 0
	for i: int in 600:
		await get_tree().physics_frame
		if not player.grounded:
			air_ticks += 1
	check(air_ticks < 4, "stays planted on a lift going up and down (%d airborne ticks of 600)" % air_ticks)


func test_i_rotating_platform() -> void:
	await new_world(Vector3(4, 0.5, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -6, 0))
	var arms: Array[Dictionary] = [{"pos": Vector3(4, 0, 0), "size": Vector3(8, 0.5, 2.5)}]
	var r: RotatingPlatform = kit.spinner(Vector3(0, 0, 0), 8.0, arms)
	await settle()
	var local0: Vector3 = r.global_transform.affine_inverse() * player.global_position
	await seconds(4.0)
	var local1: Vector3 = r.global_transform.affine_inverse() * player.global_position
	check(player.grounded and local0.distance_to(local1) < 0.25, "carried around by a rotating arm (local drift %.3fm over half a turn)" % local0.distance_to(local1))
	var tangential: float = player.platform_velocity.length()
	near(tangential, TAU / 8.0 * 4.0, 0.4, "reports tangential platform speed at r=4")


func test_j_tilt_platform() -> void:
	await new_world(Vector3(0, 0.6, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -8, 0))
	var t: TiltPlatform = kit.tilt(Vector3(0, 0, 0), Vector3(8, 0.4, 2.4), {"edge_tilt_deg": 16.0, "max_tilt_deg": 24.0})
	await settle()
	near(t.tilt_degrees().y, 0.0, 0.8, "centred rider keeps the beam level")
	player.teleport(Transform3D(Basis(), Vector3(2.0, 0.3, 0)))
	var max_tilt: float = 0.0
	for i: int in 300:
		await get_tree().physics_frame
		max_tilt = maxf(max_tilt, absf(t.tilt_degrees().y))
	var rest: float = absf(t.tilt_degrees().y)
	check(rest > 4.0 and rest < 13.0, "standing off-centre tilts the beam proportionally (%.1f deg at x=2)" % rest)
	check(max_tilt <= 24.5, "tilt never exceeds its hard limit (peak %.1f deg)" % max_tilt)
	check(player.grounded, "footing stays stable on the tilted beam")
	# heavy edge landing
	player.teleport(Transform3D(Basis(), Vector3(3.6, 9.0, 0)))
	max_tilt = 0.0
	for i: int in 360:
		await get_tree().physics_frame
		max_tilt = maxf(max_tilt, absf(t.tilt_degrees().y))
	check(max_tilt > 14.0 and max_tilt <= 25.5, "a hard edge landing swings it further but stays bounded (peak %.1f deg)" % max_tilt)
	player.teleport(Transform3D(Basis(), Vector3(0, -7.9, 5)))
	t.reset_state()
	await ticks(3)
	near(t.tilt_degrees().y, 0.0, 0.2, "reset_state returns it level")
	await seconds(1.0)
	near(t.tilt_degrees().y, 0.0, 0.2, "and it stays level afterwards")
	# sinking platform
	var s: TiltPlatform = kit.tilt(Vector3(30, 0, 0), Vector3(4, 0.4, 4), {"tilt_about_z": false, "sink_depth": 0.8, "support": "cables"})
	player.teleport(Transform3D(Basis(), Vector3(30, 0.3, 0)))
	await seconds(2.5)
	near(player.global_position.y, -0.8, 0.2, "weight-sensitive platform sinks by its rated depth")
	check(player.grounded, "rider stays grounded while it sinks")


func test_k_collapsing_platform() -> void:
	await new_world(Vector3(0, 0.3, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -8, 0))
	var c: CollapsingPlatform = kit.collapse(Vector3(0, 0, 0), 2.4, 0.7)
	await seconds(0.5)
	check(player.grounded and player.global_position.y > -0.2, "holds during the warning shake")
	await seconds(0.8)
	check(player.global_position.y < -0.5, "gives way after the delay")
	c.reset_state()
	await ticks(3)
	player.teleport(Transform3D(Basis(), Vector3(0, 0.3, 0)))
	await seconds(0.3)
	check(player.grounded and player.global_position.y > -0.2, "reset_state makes it solid again immediately")
	await wait_landing()
	await seconds(5.0)
	player.teleport(Transform3D(Basis(), Vector3(0, 0.3, 0)))
	await seconds(0.3)
	check(player.grounded and player.global_position.y > -0.2, "also returns by itself after its respawn time")


# ---- levels ---------------------------------------------------------------------------------------

func load_level(index: int) -> LevelBase:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	Game.level_index = index
	Game.race_mode = false
	Game.course_time = 0.0
	Game.course_running = true
	var scene: PackedScene = load(Game.LEVELS[index]["scene"]) as PackedScene
	var lvl: LevelBase = scene.instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	return lvl


func max_jump_reach(dy: float, speed: float = -1.0) -> float:
	var t: MovementTuning = load("res://resources/default_tuning.tres") as MovementTuning
	var v: float = t.max_speed if speed <= 0.0 else speed
	var land: Vector3 = Ballistics.landing_point(t, Vector3.ZERO, Vector3(0, t.jump_velocity, -v), dy)
	return absf(land.z)


## Scans the ground along a route jump and returns (distance, rise) actually
## required: from the takeoff point to 0.4 m past the near edge of the landing.
func required_jump(lvl: LevelBase, from: Vector3, to: Vector3) -> Vector2:
	var space: PhysicsDirectSpaceState3D = lvl.get_world_3d().direct_space_state
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	var total: float = flat.length()
	var dir: Vector3 = flat.normalized()
	var left_ground: bool = false
	var d: float = 0.0
	while d <= total:
		var p: Vector3 = from + dir * d
		if not left_ground:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p + Vector3(0, -0.7, 0), 1)
			if space.intersect_ray(q).is_empty():
				left_ground = true
		else:
			var q2 := PhysicsRayQueryParameters3D.create(Vector3(p.x, to.y + 1.2, p.z), Vector3(p.x, to.y - 0.9, p.z), 1)
			var hit: Dictionary = space.intersect_ray(q2)
			if not hit.is_empty():
				return Vector2(d + 0.4, (hit["position"] as Vector3).y - from.y)
		d += 0.2
	return Vector2(total, to.y - from.y)


func test_m_levels_load_and_validate() -> void:
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		if not ResourceLoader.exists(Game.LEVELS[i]["scene"]):
			check(false, "level %d scene exists" % (i + 1))
			continue
		var lvl: LevelBase = await load_level(i)
		var label: String = str(Game.LEVELS[i]["name"])
		check(lvl.player != null and lvl.find_children("*", "FinishGate", true, false).size() == 1, "%s: loads with a player and one finish gate" % label)
		check(lvl.checkpoints.size() >= 2, "%s: has %d checkpoints" % [label, lvl.checkpoints.size()])
		await seconds(0.5)
		check(lvl.player.grounded, "%s: player spawns on solid ground" % label)
		var worst: float = 0.0
		var jumps: int = 0
		for step: Dictionary in lvl.route:
			if str(step["kind"]) == "jump" and not step.has("to_node"):
				var from: Vector3 = step["from"]
				var to: Vector3 = step["to"]
				var need: Vector2 = required_jump(lvl, from, to)
				var reach: float = max_jump_reach(need.y, float(step.get("speed", -1.0)))
				worst = maxf(worst, need.x / reach)
				jumps += 1
		check(jumps > 0 and worst <= 0.95, "%s: %d required jumps, hardest uses %.0f%% of max reach" % [label, jumps, worst * 100.0])
		metrics["%s hardest jump %%" % Game.LEVELS[i]["id"]] = int(worst * 100.0)


func run_bot(index: int, budget_seconds: float) -> void:
	var lvl: LevelBase = await load_level(index)
	var bot := RouteBot.new()
	lvl.add_child(bot)
	bot.attach(lvl)
	var label: String = str(Game.LEVELS[index]["name"])
	var t: float = 0.0
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	while t < budget_seconds and not bot.done and not bot.stuck:
		await get_tree().physics_frame
		t += dt
	for line: String in bot.log_lines:
		print("        bot: ", line)
	check(bot.done, "%s: bot completes the main route with real physics (%.1fs, %d respawns, reached step %d/%d)" % [label, lvl.run_time, bot.retries, bot.step_index, lvl.route.size()])
	check(bot.retries <= 15, "%s: hard but fair - the bot needed %d respawns" % [label, bot.retries])
	metrics["%s bot time s" % Game.LEVELS[index]["id"]] = snappedf(lvl.run_time, 0.01)
	if bot.done:
		check(SaveData.is_completed(lvl.level_id), "%s: completion saved" % label)


func test_n_bot_levels() -> void:
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		if ResourceLoader.exists(Game.LEVELS[i]["scene"]):
			await run_bot(i, 1200.0)


func test_o_checkpoint_fail_respawn_reset() -> void:
	var lvl: LevelBase = await load_level(0)
	var cp: Checkpoint = lvl.checkpoints[0]
	lvl.player.teleport(cp.respawn_transform())
	await seconds(0.3)
	check(lvl.current_checkpoint == 1 and cp.active, "touching a checkpoint banks it")
	var tilt: TiltPlatform = lvl.kit.tilt(cp.global_position + Vector3(30, 0, 0), Vector3(6, 0.4, 2.4), {"edge_tilt_deg": 9.0})
	await ticks(3)
	lvl.player.teleport(Transform3D(Basis(), tilt.global_position + Vector3(2.5, 0.5, 0)))
	await seconds(1.0)
	check(absf(tilt.tilt_degrees().y) > 3.0, "test board is tilted before the fall")
	# walk off into the void
	lvl.player.teleport(Transform3D(Basis(), cp.global_position + Vector3(60, 0, 0)))
	var t: float = 0.0
	while lvl.deaths == 0 and t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	check(lvl.deaths == 1 and t < 1.2, "fall-out detected and respawned within %.2fs" % t)
	check(lvl.player.global_position.distance_to(cp.global_position) < 1.0, "respawns at the banked checkpoint")
	await ticks(3)
	near(tilt.tilt_degrees().y, 0.0, 0.5, "local physics objects are reset on respawn")
	check(lvl.run_time > 0.0 and not lvl.finished, "run timer keeps going across respawns")


func test_p_save_progress_roundtrip() -> void:
	SaveData.wipe()
	check(not SaveData.is_completed("gardens") and SaveData.best_time("gardens") < 0.0, "fresh save has no progress")
	check(SaveData.record_finish("gardens", 61.5), "first finish is a personal best")
	check(not SaveData.record_finish("gardens", 70.0), "slower run is not a new best")
	check(SaveData.record_finish("gardens", 55.25), "faster run is a new best")
	SaveData.data = {}
	SaveData.load_data()
	check(SaveData.is_completed("gardens"), "completion survives a reload from disk")
	near(SaveData.best_time("gardens"), 55.25, 0.001, "best time survives a reload from disk")
	check(Game.is_level_unlocked(1) and not Game.is_level_unlocked(3), "unlocks follow completion")
	SaveData.wipe()


func test_j2_steep_boards_slide() -> void:
	await new_world(Vector3(4.1, 0.6, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -8, 0))
	var t: TiltPlatform = kit.tilt(Vector3(0, 0, 0), Vector3(9, 0.4, 3.4), {"edge_tilt_deg": 20.0, "max_tilt_deg": 24.0})
	var x0: float = player.global_position.x
	var peak_tilt: float = 0.0
	var slid: float = 0.0
	for i: int in 240:
		await get_tree().physics_frame
		peak_tilt = maxf(peak_tilt, absf(t.tilt_degrees().y))
		if player.grounded and player.floor_body is TiltSurface:
			slid = maxf(slid, player.global_position.x - x0)
	check(slid > 0.35, "standing still on a steep board drifts downhill (slid %.2fm, peak tilt %.1f deg)" % [slid, peak_tilt])
	# a calm board must not slide
	var calm: TiltPlatform = kit.tilt(Vector3(40, 0, 0), Vector3(9, 0.4, 3.4), {"edge_tilt_deg": 8.0, "max_tilt_deg": 11.0})
	player.teleport(Transform3D(Basis(), Vector3(43.2, 0.4, 0)))
	await seconds(1.5)
	x0 = player.global_position.x
	await seconds(1.0)
	check(player.grounded and absf(player.global_position.x - x0) < 0.03, "calm boards (under the slip angle) give firm footing")
	check(calm != null, "built")


func test_q_final_win_condition() -> void:
	SaveData.wipe()
	var lvl: LevelBase = await load_level(Game.LEVELS.size() - 1)
	var finished_time: Array[float] = [-1.0]
	lvl.level_finished.connect(func(t: float) -> void: finished_time[0] = t)
	await seconds(0.5)
	var gate: FinishGate = lvl.find_children("*", "FinishGate", true, false)[0] as FinishGate
	lvl.player.teleport(Transform3D(Basis(), gate.global_position + Vector3(0, 0.3, 0)))
	await seconds(1.5)
	check(lvl.finished and finished_time[0] > 0.0, "entering the summit gate finishes the final level (t=%.2f)" % finished_time[0])
	check(not lvl.player.control_enabled, "control is released for the beacon sequence")
	check(SaveData.is_completed("ascent") and bool(SaveData.data["game_completed"]), "beacon lit: game completion is saved")
	var beam: Node = lvl.get("_beam")
	check(beam != null and (beam as MeshInstance3D).visible, "the beacon beam is switched on")
	SaveData.wipe()


func test_r_menus_build_without_errors() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	await ticks(3)
	for id: String in ["levels", "race", "settings", "victory", "main"]:
		title.call("show_screen", id)
		await ticks(2)
		check(Game.title_screen == id, "title screen builds: %s" % id)
	check(Net.host(24599) == OK, "hosting opens the lobby")
	await ticks(3)
	check(Game.title_screen == "lobby" and Net.roster.size() == 1, "lobby shows the host in the roster")
	Net.leave()
	title.queue_free()
	await ticks(2)
	# pause menu + results on a live level
	var lvl: LevelBase = await load_level(0)
	var pause: PauseMenu = lvl.find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	pause.set_open(true)
	await get_tree().process_frame
	check(get_tree().paused and not lvl.player.control_enabled, "pause freezes a solo run")
	pause.set_open(false)
	check(not get_tree().paused and lvl.player.control_enabled, "resume restores control")
	lvl.hud.show_results(12.34, -1.0, true, 0)
	await ticks(2)
	check(true, "results panel builds")


# ---- momentum toolkit -------------------------------------------------------------------------

func test_s_boost_conveyor_ice() -> void:
	await new_world(Vector3(0, 0.1, 4))
	floor_slab()
	kit.boost(Vector3(0, 0.02, -6), Vector3(3, 0.2, 12), 0.0, 20.0)
	await settle()
	player.cmd_move = FWD
	var peak: float = 0.0
	while player.global_position.z > -11.5:
		await get_tree().physics_frame
		peak = maxf(peak, player.horizontal_speed())
	check(peak > 19.0 and peak < 21.0, "boost strip drives speed to its target (%.1f m/s)" % peak)
	player.press_jump()
	player.cmd_jump = true
	await wait_landing()
	player.cmd_jump = false
	var d: float = player.last_jump_distance
	check(d > 13.0, "a boosted jump carries the momentum (%.1fm vs 7.0m normal)" % d)
	metrics["boost20_jump_distance_m"] = d
	await seconds(0.5)
	check(player.horizontal_speed() > 11.0, "landing and running on keeps over-speed for a while (%.1f m/s after 0.5s)" % player.horizontal_speed())
	metrics["speed_0.5s_after_boost_landing"] = player.horizontal_speed()
	# conveyor
	kit.conveyor(Vector3(40, 0.02, 0), Vector3(4, 0.2, 14), 0.0, 5.0)
	player.teleport(Transform3D(Basis(), Vector3(40, 0.2, 4)))
	await settle()
	near(player.velocity.z, -5.0, 0.3, "standing on a conveyor carries you at belt speed")
	# ice slide: 25 degree slope, 16 m long
	kit.slick(Vector3(80, 6.0, 0), Vector3(5, 0.4, 16), 0.0, 25.0)
	player.teleport(Transform3D(Basis(), Vector3(80, 9.6, -6.5)))
	player.cmd_move = Vector2.ZERO
	var top_speed: float = 0.0
	for i: int in 300:
		await get_tree().physics_frame
		if player.grounded and player.floor_body is SurfacePlatform:
			top_speed = maxf(top_speed, player.horizontal_speed())
	check(top_speed > 12.0, "an ice slide builds speed by itself (%.1f m/s off a 16m, 25deg slide)" % top_speed)
	metrics["ice_slide_exit_speed"] = top_speed


func test_t_hazards_and_toys() -> void:
	var lvl: LevelBase = await load_level(0)
	var base: Vector3 = lvl.checkpoints[0].global_position
	lvl.player.teleport(lvl.checkpoints[0].respawn_transform())
	await seconds(0.3)
	lvl.kit.plat(base + Vector3(40, 0, 0), Vector3(30, 1, 30), "main", 0.0)
	lvl.kit.hazard(base + Vector3(40, 0.3, -6), Vector3(4, 0.6, 2))
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(40, 0.1, 0)))
	lvl.player.use_device_input = false
	await seconds(0.3)
	lvl.player.cmd_move = FWD
	var t: float = 0.0
	while lvl.deaths == 0 and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	lvl.player.cmd_move = Vector2.ZERO
	check(lvl.deaths == 1 and lvl.player.global_position.distance_to(base) < 1.5, "kill brick sends the player back to the checkpoint")
	# bumper
	lvl.kit.bumper(base + Vector3(46, 0, 6), 16.0, 8.0)
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(46, 0.1, 9)))
	await seconds(0.3)
	lvl.player.cmd_move = FWD
	var flung: bool = false
	for i: int in 240:
		await get_tree().physics_frame
		if lvl.player.velocity.z > 12.0:
			flung = true
			break
	lvl.player.cmd_move = Vector2.ZERO
	check(flung, "bumper throws the player straight back at its rated speed")
	await wait_level_landing(lvl)
	# blink platform follows the course clock
	var b: BlinkPlatform = lvl.kit.blink(base + Vector3(34, 3, 8), Vector3(3, 0.4, 3), 2.0, 0.5)
	await seconds(0.2)
	var seen_on: bool = false
	var seen_off: bool = false
	for i: int in 300:
		await get_tree().physics_frame
		var solid: bool = not (b.get_child(0) as CollisionShape3D).disabled
		if absf(fposmod(Game.course_time / 2.0, 1.0) - 0.25) < 0.1:
			seen_on = seen_on or solid
		if absf(fposmod(Game.course_time / 2.0, 1.0) - 0.75) < 0.1:
			seen_off = seen_off or not solid
	check(seen_on and seen_off, "blink platform is solid and gone on schedule")
	# updraft lifts a falling player
	lvl.kit.wind(base + Vector3(52, 6, -8), Vector3(4, 12, 4), Vector3(0, 70, 0))
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(52, 1.0, -8)))
	await seconds(1.2)
	check(lvl.player.global_position.y > base.y + 5.0, "updraft column carries the player upward (y +%.1f)" % (lvl.player.global_position.y - base.y))


func wait_level_landing(lvl: LevelBase) -> void:
	var t: float = 0.0
	while not lvl.player.grounded and t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0


func test_u_pendulum_and_sweeper() -> void:
	await new_world(Vector3(0, 0.1, 0))
	floor_slab()
	var p: Pendulum = kit.pendulum(Vector3(0, 8.2, 0), 7.0, 3.0)
	var peak: float = 0.0
	for i: int in 480:
		await get_tree().physics_frame
		peak = maxf(peak, player.horizontal_speed())
	check(peak > 12.0, "a swinging hammer hurls a player standing in its path (%.1f m/s)" % peak)
	check(absf(player.global_position.x) > 5.0, "and the throw follows the swing axis (ended at x=%.1f)" % player.global_position.x)
	check(p != null, "built")
	var lvl: LevelBase = await load_level(0)
	var base: Vector3 = lvl.checkpoints[0].global_position
	lvl.player.teleport(lvl.checkpoints[0].respawn_transform())
	await seconds(0.3)
	lvl.kit.plat(base + Vector3(60, 0, 0), Vector3(16, 1, 16), "main", 0.0)
	lvl.kit.sweeper(base + Vector3(60, 0, 0), 6.0, 2, 3.0)
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(63, 0.1, 0)))
	var t: float = 0.0
	while lvl.deaths == 0 and t < 3.5:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	check(lvl.deaths == 1, "a sweeper bar kills a player who does not jump it (after %.2fs)" % t)


# ---- run flow, results and save file ----------------------------------------------------------

func test_v_kill_seam_counts_one_fall() -> void:
	var lvl: LevelBase = await load_level(0)
	var base: Vector3 = lvl.checkpoints[0].global_position
	lvl.player.teleport(lvl.checkpoints[0].respawn_transform())
	await seconds(0.3)
	lvl.kit.plat(base + Vector3(40, 0, 0), Vector3(30, 1, 30), "main", 0.0)
	# two 2 m kill bricks side by side, walked into right at their seam
	lvl.kit.hazard(base + Vector3(39, 0.3, -6), Vector3(2, 0.6, 2))
	lvl.kit.hazard(base + Vector3(41, 0.3, -6), Vector3(2, 0.6, 2))
	var respawns: Array[int] = [0]
	lvl.player_respawned.connect(func() -> void: respawns[0] += 1)
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(40, 0.1, 0)))
	lvl.player.use_device_input = false
	await seconds(0.3)
	lvl.player.cmd_move = FWD
	var t: float = 0.0
	while lvl.deaths == 0 and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	lvl.player.cmd_move = Vector2.ZERO
	await ticks(6)
	check(lvl.deaths == 1 and respawns[0] == 1, "one touch across two kill bricks is one fall (falls %d, respawns %d)" % [lvl.deaths, respawns[0]])


func test_v_restart_run_in_place() -> void:
	var lvl: LevelBase = await load_level(0)
	var cp: Checkpoint = lvl.checkpoints[0]
	lvl.player.teleport(cp.respawn_transform())
	await seconds(0.3)
	check(lvl.current_checkpoint == 1 and lvl.splits[0] >= 0.0, "banking a checkpoint records its split (%.2fs)" % lvl.splits[0])
	lvl.deaths = 3
	Game.course_time = 5.0
	lvl.restart_run()
	await ticks(2)
	var any_active: bool = false
	for c: Checkpoint in lvl.checkpoints:
		any_active = any_active or c.active
	check(lvl.deaths == 0 and lvl.current_checkpoint == 0 and not any_active and lvl.splits[0] < 0.0, "restarting clears falls, checkpoints and splits")
	check(Game.course_time < 0.05 and lvl.run_time < 0.05, "restarting zeroes the clock (t=%.3f)" % Game.course_time)
	check(lvl.player.global_position.distance_to(lvl._spawn.origin) < 0.5 and lvl.is_inside_tree(), "restarting puts the player back at the start, in place")


func test_v_bail_while_falling_counts() -> void:
	var lvl: LevelBase = await load_level(0)
	var cp: Checkpoint = lvl.checkpoints[0]
	lvl.player.teleport(cp.respawn_transform())
	await seconds(0.3)
	lvl.manual_respawn()
	await ticks(3)
	check(lvl.deaths == 0, "going back to the checkpoint while standing is free")
	lvl.player.teleport(Transform3D(Basis(), cp.global_position + Vector3(60, 0, 0)))
	await seconds(0.45)
	check(not lvl.player.grounded and lvl.deaths == 0, "falling, not caught by the fall-out check yet (vy %.1f)" % lvl.player.velocity.y)
	lvl.manual_respawn()
	await ticks(3)
	check(lvl.deaths == 1 and lvl.player.global_position.distance_to(cp.global_position) < 1.0, "bailing out with R while falling counts as a fall")


func test_v_save_file_robustness() -> void:
	var keep: String = SaveData.path_override
	SaveData.path_override = "user://test_progress_robust.json"
	SaveData.wipe()
	var t60: float = 0.0
	for i: int in 7200:
		t60 += 1.0 / 120.0
	var shown: Array[String] = [SaveData.format_time(59.996), SaveData.format_time(t60), SaveData.format_time(3599.999), SaveData.format_time(61.5), SaveData.format_time(-1.0)]
	check(shown == ["0:59.99", "1:00.00", "59:59.99", "1:01.50", "--:--.--"], "format_time truncates and carries the minute (%s)" % str(shown))
	SaveData.record_finish("gardens", 62.35, 4, [10.0, -1.0, 30.5])
	check(not SaveData.record_finish("gardens", 62.358, 4), "a run that reads the same as the best is not a new best")
	check(SaveData.record_finish("gardens", 60.0, 5, [9.0, 20.0, 29.0]) and not SaveData.record_finish("gardens", 70.0, 5, [1.0, 2.0, 3.0]), "bests still follow the time")
	SaveData.load_data()
	check(SaveData.best_splits("gardens") == [9.0, 20.0, 29.0], "the best run's splits survive a reload, and slower runs leave them (%s)" % str(SaveData.best_splits("gardens")))
	# a damaged file falls back to the backup and is kept aside
	var f: FileAccess = FileAccess.open(SaveData.path_override, FileAccess.WRITE)
	f.store_string("{\"levels\": {\"gardens\": {\"compl")
	f.close()
	SaveData.load_data()
	check(SaveData.is_completed("gardens") and SaveData.best_time("gardens") > 0.0 and FileAccess.file_exists(SaveData.path_override + ".corrupt"), "a truncated save is restored from the backup")
	f = FileAccess.open(SaveData.path_override, FileAccess.WRITE)
	f.store_string("{\"levels\": {\"gardens\": true, \"foundry\": {\"completed\": \"yes\", \"best\": \"x\", \"runs\": 2}}, \"game_completed\": \"no\"}")
	f.close()
	SaveData.load_data()
	check(not SaveData.is_completed("gardens") and not SaveData.is_completed("foundry") and SaveData.best_time("foundry") < 0.0 and not bool(SaveData.data["game_completed"]), "malformed entries are dropped instead of breaking the accessors")
	f = FileAccess.open(SaveData.path_override, FileAccess.WRITE)
	f.store_string("{\"levels\": [], \"game_completed\": false}")
	f.close()
	SaveData.load_data()
	check(SaveData.record_finish("balance", 90.0, 1) and SaveData.is_completed("balance"), "a malformed level table still records finishes")
	# bests set on an older course layout move aside; unlocks stay
	f = FileAccess.open(SaveData.path_override, FileAccess.WRITE)
	f.store_string("{\"levels\": {\"gardens\": {\"completed\": true, \"best\": 18.22, \"runs\": 1.0, \"fewest_falls\": 0}}, \"game_completed\": false}")
	f.close()
	SaveData.load_data()
	var g: Dictionary = SaveData.data["levels"]["gardens"]
	check(SaveData.is_completed("gardens") and SaveData.best_time("gardens") < 0.0 and SaveData.fewest_falls("gardens") < 0 and is_equal_approx(float(g.get("legacy_best", -1.0)), 18.22), "an old-layout best becomes legacy_best; completion is kept")
	check(SaveData.record_finish("gardens", 250.0, 3), "the first clear of the new layout is a best")
	SaveData.load_data()
	check(is_equal_approx(SaveData.best_time("gardens"), 250.0) and SaveData.fewest_falls("gardens") == 3, "the new-layout best survives a reload")
	SaveData.delete_files()
	check(not FileAccess.file_exists(SaveData.path_override) and not FileAccess.file_exists(SaveData.path_override + ".bak") and not FileAccess.file_exists(SaveData.path_override + ".corrupt"), "delete_files leaves nothing behind")
	SaveData.path_override = keep
	SaveData.wipe()


func test_v_race_go_behind_open_menu() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	Game.level_index = 0
	Game.race_mode = true
	Net.race_start_time = Net.now() + 1.0
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var pause: PauseMenu = lvl.find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	check(Game.course_time < 0.0 and not lvl.player.control_enabled, "the race countdown holds the player (t=%.2f)" % Game.course_time)
	pause.set_open(true)
	var t: float = 0.0
	while Game.course_time < 0.2 and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	check(lvl._started and not lvl.player.control_enabled, "GO behind the open race menu keeps control off")
	var respawns: Array[int] = [0]
	lvl.player_respawned.connect(func() -> void: respawns[0] += 1)
	var ev := InputEventAction.new()
	ev.action = "restart"
	ev.pressed = true
	lvl._unhandled_input(ev)
	check(respawns[0] == 0, "R is ignored behind the open race menu")
	pause.set_open(false)
	check(lvl.player.control_enabled, "closing the menu hands control back")
	Game.race_mode = false
	world.queue_free()
	world = null
	await ticks(2)


func test_v_results_and_splits_display() -> void:
	SaveData.wipe()
	var keep_mode: String = Settings.timer_mode
	Settings.timer_mode = "on"
	var lvl: LevelBase = await load_level(0)
	var best: Array = []
	for i: int in lvl.checkpoints.size():
		best.append(5.0 * (i + 1))
	SaveData.record_finish(lvl.level_id, 100.0, 4, best)
	lvl.hud.checkpoint_reached(1, 4.0)
	check(lvl.hud._toast_sub.text == "-1.00", "a checkpoint shows the split against the best run (%s)" % lvl.hud._toast_sub.text)
	lvl.hud.toast("Someone finished")
	check(lvl.hud._toast_sub.text == "", "a plain toast clears the split line")
	Game.course_time = 150.0
	await ticks(2)
	await get_tree().process_frame
	await get_tree().process_frame
	check(lvl.hud._timer.self_modulate != Color.WHITE, "the timer turns red once the run is slower than the best")
	lvl.hud.show_results(80.0, 100.0, true, 2, 4)
	await ticks(2)
	var buttons: Array[Node] = lvl.hud.find_children("*", "Button", true, false)
	var locked: bool = buttons.size() == 3 and not lvl.hud.results_ready()
	for b: Node in buttons:
		locked = locked and (b as Button).disabled
	check(locked, "results buttons ignore input while the panel fades in")
	var texts: String = ""
	for l: Node in lvl.hud.find_children("*", "Label", true, false):
		texts += (l as Label).text + "|"
	check(texts.contains("-20.00 s") and texts.contains("fewest yet!  (was 4)"), "results call out the time gained and a fewest-falls record")
	await seconds(1.0)
	var live: bool = lvl.hud.results_ready()
	for b: Node in buttons:
		live = live and not (b as Button).disabled
	check(live, "results buttons go live after the fade")
	Settings.timer_mode = keep_mode
	SaveData.wipe()


## Button with exactly this text under `root` (skips menus already being rebuilt).
func find_button(root: Node, text: String) -> Button:
	for n: Node in root.find_children("*", "Button", true, false):
		var live: bool = (n as Button).text == text
		var up: Node = n
		while live and up != null:
			live = not up.is_queued_for_deletion()
			up = up.get_parent()
		if live:
			return n as Button
	return null


## Waits `s` seconds of wall-clock time (headless physics can run ahead of it).
func real_seconds(s: float) -> void:
	var until: int = Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## A left click (press + release) pushed through the viewport at `at`.
func click_at(at: Vector2) -> void:
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		get_viewport().push_input(ev, true)


func test_w_confirm_button_two_press() -> void:
	var fired: Array[int] = [0]
	var b: Button = UiKit.confirm_button("Quit to Title", "Press again to quit", func() -> void: fired[0] += 1)
	add_child(b)
	await ticks(1)
	b.grab_focus()
	b.pressed.emit()
	check(fired[0] == 0 and b.text == "Press again to quit", "a confirm button only arms on the first press")
	b.pressed.emit()
	check(fired[0] == 0, "an instant second press (double-click) does not confirm")
	await real_seconds(0.3)
	b.pressed.emit()
	check(fired[0] == 1, "a second press confirms")
	b.release_focus()
	check(b.text == "Quit to Title", "moving focus away disarms it")
	b.grab_focus()
	b.pressed.emit()
	await real_seconds(3.1)
	check(b.text == "Quit to Title", "an armed button disarms itself after 3 s")
	b.pressed.emit()
	check(fired[0] == 1 and b.text == "Press again to quit", "after that a press only arms it again")
	b.queue_free()
	await ticks(1)


func test_w_pause_menu_keys_confirms_focus() -> void:
	var lvl: LevelBase = await load_level(0)
	var pause: PauseMenu = lvl.find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	get_viewport().push_input(esc)
	check(pause.open and get_tree().paused, "Esc opens the pause menu (its ui_cancel side doesn't shut it again)")
	var f: Control = get_viewport().gui_get_focus_owner()
	check(f is Button and (f as Button).text == "Resume", "the pause menu focuses Resume")
	get_viewport().push_input(esc)
	check(not pause.open and not get_tree().paused, "Esc closes it again")
	var back := InputEventAction.new()
	back.action = "ui_cancel"
	back.pressed = true
	get_viewport().push_input(back)
	check(not pause.open, "ui_cancel (pad B) never opens the menu from gameplay")
	pause.set_open(true)
	get_viewport().push_input(back)
	check(not pause.open, "ui_cancel closes the open menu")
	# Settings -> back: focus returns to the Settings button (closed is what Done emits;
	# emitted directly here so the test never writes the real settings.cfg)
	pause.set_open(true)
	find_button(pause, "Settings").pressed.emit()
	await get_tree().process_frame
	var panels: Array[Node] = pause.find_children("*", "SettingsPanel", true, false)
	check(panels.size() == 1, "the pause menu opens its settings panel")
	(panels[0] as SettingsPanel).closed.emit()
	f = get_viewport().gui_get_focus_owner()
	check(f is Button and (f as Button).text == "Settings", "coming back from Settings focuses the Settings button")
	# run-ending buttons: one press before a checkpoint (like R), two once one is banked
	check(find_button(pause, "Level Select") != null and find_button(pause, "Quit to Title") != null, "solo menu lists Level Select and Quit")
	find_button(pause, "Restart Level").pressed.emit()
	check(not pause.open, "before a checkpoint, Restart Level restarts on one press")
	lvl.current_checkpoint = 1
	pause.set_open(true)
	var restart: Button = find_button(pause, "Restart Level")
	restart.grab_focus()
	restart.pressed.emit()

	check(pause.open and lvl.current_checkpoint == 1 and restart.text == "Press again to restart", "with a checkpoint banked, Restart Level asks for a second press")
	await real_seconds(0.3)
	restart.pressed.emit()
	check(not pause.open and lvl.current_checkpoint == 0 and not get_tree().paused, "the second press restarts the run")
	# losing window focus pauses a solo run; the click that brings the window back is eaten
	lvl.headless_mode = false   # (focus-loss pausing is off in automated runs)
	pause.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(pause.open and get_tree().paused, "losing window focus pauses a solo run")
	await get_tree().process_frame
	var at: Vector2 = find_button(pause, "Resume").get_global_rect().get_center()
	click_at(at)
	check(pause.open, "the click that refocuses the window can't press a menu button")
	pause.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await real_seconds(0.4)
	click_at(at)
	check(not pause.open and not get_tree().paused, "a moment after focus returns, clicks work again")
	lvl.headless_mode = true


func test_w_back_to_back_toasts() -> void:
	var lvl: LevelBase = await load_level(0)
	lvl.hud.toast("First")
	await real_seconds(1.5)
	lvl.hud.toast("Second")
	await real_seconds(0.5)
	var a: float = lvl.hud._toast.modulate.a
	check(a > 0.9 and lvl.hud._toast.text == "Second", "a toast right after another stays readable (alpha %.2f)" % a)


func test_w_race_finish_behind_menu() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	check(Net.host(24596) == OK, "hosting a one-player race")
	Game.level_index = 0
	Game.race_mode = true
	Net.race_start_time = Net.now() - 1.0
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var pause: PauseMenu = lvl.find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	lvl.headless_mode = false
	pause.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not pause.open, "losing focus mid-race doesn't open the menu (the race clock can't pause)")
	lvl.headless_mode = true
	pause.set_open(true)
	check(find_button(pause, "End Race - Everyone to Lobby") != null and find_button(pause, "Close Session (disconnects all)") != null, "the host's race menu can end the race for everyone")
	# a slower racer with a long name: the board must grow leftwards, not off-screen
	Net.roster[2] = {"name": "WWWWWWWWWWWWWW", "color": 1, "cp": 99, "finished": 599.99}
	var t: float = lvl.run_time
	lvl._on_finish()
	check(lvl.finished and not pause.open, "finishing behind the race menu closes it")
	var texts: String = ""
	for l: Node in lvl.hud._results.find_children("*", "Label", true, false):
		texts += (l as Label).text + "|"
	check(texts.contains(SaveData.format_time(t)) and texts.contains("1st place of 2"), "race results show your time and place (%s)" % texts)
	await ticks(3)
	var r: Rect2 = lvl.hud._board.get_global_rect()
	var w: float = lvl.hud._root.size.x
	check(r.size.x > 290.0 and r.end.x <= w - 19.0 and r.position.x > 0.0, "a long standings row widens the board leftwards (%s in %.0f)" % [str(r), w])
	check(get_viewport().gui_get_focus_owner() == null, "no race-results button takes focus right at the line")
	await real_seconds(1.1)
	var f: Control = get_viewport().gui_get_focus_owner()
	check(f is Button and (f as Button).text == "Back to Lobby (everyone)", "then Back to Lobby is focused for keyboard / pad")
	var close: Button = find_button(lvl.hud, "Close Session (disconnects all)")
	close.grab_focus()
	close.pressed.emit()
	check(Net.active and close.text == "Press again to disconnect all", "the host's Close Session asks for a second press")
	Net.leave()
	Game.race_mode = false
	world.queue_free()
	world = null
	await ticks(2)
