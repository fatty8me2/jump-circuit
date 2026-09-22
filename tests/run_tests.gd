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
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_progress.json"))
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


## Where the route resumes after a "checkpoint" step: the first static route point
## (from / to / to_center; moving-node targets are skipped) more than 2.5 m (flat)
## from the checkpoint. Returns Vector3.INF when the route has none.
func route_resume_point(lvl: LevelBase, step: int, origin: Vector3) -> Vector3:
	for s: int in range(step + 1, lvl.route.size()):
		var st: Dictionary = lvl.route[s]
		var pts: Array[Vector3] = []
		if st.get("from") is Vector3 and not st.has("from_node"):
			pts.append(st["from"])
		if st.get("to") is Vector3 and not st.has("to_node"):
			pts.append(st["to"])
		if st.get("to_center") is Vector3:
			pts.append(st["to_center"])
		for p: Vector3 in pts:
			if Vector2(p.x - origin.x, p.z - origin.z).length() > 2.5:
				return p
	return Vector3.INF


## Respawning at any checkpoint points the camera at the stage it resumes (within
## 50 deg of the first route point past the checkpoint), not into the void.
func test_w_checkpoints_face_the_route() -> void:
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		var lvl: LevelBase = await load_level(i)
		var label: String = str(Game.LEVELS[i]["name"])
		var worst: float = 0.0
		var worst_cp: int = 0
		var k: int = 0
		for s: int in lvl.route.size():
			if str(lvl.route[s]["kind"]) != "checkpoint" or k >= lvl.checkpoints.size():
				continue
			var cp: Checkpoint = lvl.checkpoints[k]
			k += 1
			var target: Vector3 = route_resume_point(lvl, s, cp.global_position)
			if target == Vector3.INF:
				continue
			# the respawn camera looks along the checkpoint's -Z (LevelBase.respawn)
			var face: Vector3 = -cp.respawn_transform().basis.z
			var to: Vector3 = target - cp.global_position
			var ang: float = rad_to_deg(absf(Vector2(face.x, face.z).angle_to(Vector2(to.x, to.z))))
			if ang > worst:
				worst = ang
				worst_cp = cp.index
		check(k == lvl.checkpoints.size(), "%s: every checkpoint has a route checkpoint step (%d/%d)" % [label, k, lvl.checkpoints.size()])
		check(worst <= 50.0, "%s: respawns face the next stage (worst: checkpoint %d, %.0f deg off)" % [label, worst_cp, worst])
