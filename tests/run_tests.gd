extends TestLib
## Headless physics/integration tests.
##   godot --headless --path . res://tests/run_tests.tscn
## Optional user args:  -- --only=<substring>   -- --level=<0-based index>   -- --fps=<n> (cap render rate)
## A selection that matches nothing (or a bad --level) exits with code 2 instead of a green 0.

const FWD := Vector2(0, 1)

## -- --level=<index> (0-based) restricts the per-level tests to one level.
var only_level: int = -1
## -- --route=all: the bot plays every route variant a level declares (--route=N: just that one).
var all_routes: bool = false
## Per-test watchdog budget in physics seconds (test_n gets 1300 s per level instead).
var watchdog_s: float = 180.0
## Bumped per test so a stale watchdog timer from an earlier test does nothing.
var _test_gen: int = 0
var _ended: bool = false


func _ready() -> void:
	Net.upnp_enabled = false   # hosting in test_r must never open a port on the real router
	SaveData.path_override = "user://test_progress.json"
	# -- --save=<name>: a private test save, so suites running side by side don't share one
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--save=") and a.trim_prefix("--save=").is_valid_filename():
			SaveData.path_override = "user://%s.json" % a.trim_prefix("--save=")
	SaveData.wipe()
	var only: String = ""
	var skip: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--skip="):
			skip = a.trim_prefix("--skip=")
		elif a.begins_with("--level="):
			var v: String = a.trim_prefix("--level=")
			if not v.is_valid_int() or int(v) < 0 or int(v) >= Game.LEVELS.size():
				_usage_error("--level=%s is invalid; use a 0-based index 0..%d" % [v, Game.LEVELS.size() - 1])
				return
			only_level = int(v)
		elif a.begins_with("--route="):
			var rv: String = a.trim_prefix("--route=")
			if rv == "all":
				all_routes = true
			elif rv.is_valid_int() and int(rv) >= 0:
				LevelBase.route_variant = int(rv)
			else:
				_usage_error("--route=%s is invalid; use a variant index or all" % rv)
				return
		elif a.begins_with("--fps="):
			Engine.max_fps = int(a.trim_prefix("--fps="))
	await ticks(3)
	var tests: Array[String] = []
	for m: Dictionary in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_") and (only == "" or n.contains(only)) and (skip == "" or not n.contains(skip)):
			tests.append(n)
	if tests.is_empty():
		_usage_error("--only=%s matched no test_ method" % only)
		return
	OS.add_logger(trap)
	for n: String in tests:
		print("\n== ", n)
		_test_gen += 1
		var gen: int = _test_gen
		# physics-time budget (process_in_physics, scaled): the bot levels get 1300 s each
		var limit: float = 1300.0 * Game.LEVELS.size() if n == "test_n_bot_levels" else watchdog_s
		if n == "test_z_world_sounds":
			# loads every level and walks each machine kind: scale with the level count
			limit = maxf(watchdog_s, 30.0 * Game.LEVELS.size())
		get_tree().create_timer(limit, true, true, false).timeout.connect(func() -> void: _watchdog(n, gen))
		var before: int = trap.count()
		trap.expected = 0
		await call(n)
		if _ended:
			return
		var got: int = trap.count() - before
		if got != trap.expected:
			check(false, "%s logged %d engine/script error(s) (expected %d): %s" % [n, got, trap.expected, trap.since(before)])
	_finish()


func _finish(note: String = "") -> void:
	if _ended:
		return
	_ended = true
	OS.remove_logger(trap)
	if world != null:
		world.queue_free()
	print("\n---- metrics ----")
	for k: String in metrics:
		print("  %-34s %s" % [k, str(metrics[k])])
	if passed + failed == 0:
		print("\nno checks ran")
	print("\nRESULT: %d passed, %d failed  (render fps cap: %d)%s" % [passed, failed, Engine.max_fps, note])
	SaveData.delete_files()
	Sfx.quit(1 if failed > 0 or passed + failed == 0 else 0)


## Per-test backstop: a test still running after its budget fails the whole run
## (instead of the suite hanging with no hint of which test is stuck).
func _watchdog(n: String, gen: int) -> void:
	if gen != _test_gen or _ended:
		return
	check(false, "%s timed out (watchdog)" % n)
	_finish("  (watchdog abort)")


## Bad command-line selection: exit 2 without running anything, so a typo never reads as green.
func _usage_error(msg: String) -> void:
	printerr(msg)
	SaveData.delete_files()
	Sfx.quit(2)


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
	if not await wait_until(func() -> bool: return not player.grounded, 5.0, "walking off the ledge"):
		return
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
	if not await wait_until(func() -> bool: return not player.grounded, 5.0, "walking off the ledge again"):
		return
	await seconds(0.25)
	player.press_jump()
	await ticks(2)
	check(player.velocity.y < 0.0, "coyote: no mid-air jump after the window closes")
	# buffer: press shortly before touching down
	var f0: int = Engine.get_physics_frames()
	while not player.grounded:
		if player.global_position.y < 0.55 and player.velocity.y < 0.0:
			player.press_jump()
			player.cmd_jump = true
			break
		if overdue(f0, 5.0, "the fall toward the floor"):
			return
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
		if not await wait_until(func() -> bool: return bounces[0] > i, 5.0, "pad bounce %d" % (i + 1)):
			return
		var apex: float = player.global_position.y
		var f0: int = Engine.get_physics_frames()
		while player.velocity.y > 0.0:
			if overdue(f0, 5.0, "the pad launch apex"):
				return
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
	var f1: int = Engine.get_physics_frames()
	while bounces[0] < 4:
		if overdue(f1, 5.0, "the buffered-jump pad bounce"):
			return
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
	if not await wait_until(func() -> bool: return bounces[0] != base_count, 5.0, "the angled pad bounce"):
		return
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
	await get_tree().physics_frame
	if not await wait_until(func() -> bool: return player.platform_velocity.x > 3.5, 10.0, "the platform to reach takeoff speed"):
		return
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


func run_bot(index: int, budget_seconds: float, variant: int = -1) -> void:
	var lvl: LevelBase = await load_level(index)
	var bot := RouteBot.new()
	lvl.add_child(bot)
	bot.attach(lvl)
	var label: String = str(Game.LEVELS[index]["name"])
	if variant >= 0 or LevelBase.route_variant > 0:
		label += " (route %d)" % LevelBase.route_variant
	var t: float = 0.0
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	while t < budget_seconds and not bot.done and not bot.stuck:
		await get_tree().physics_frame
		t += dt
	for line: String in bot.log_lines:
		print("        bot: ", line)
	check(bot.done, "%s: bot completes the main route with real physics (%.1fs, %d respawns, reached step %d/%d)" % [label, lvl.run_time, bot.retries, bot.step_index, lvl.route.size()])
	check(bot.retries <= 30, "%s: hard but fair - the bot needed %d respawns" % [label, bot.retries])
	metrics["%s bot time s" % Game.LEVELS[index]["id"]] = snappedf(lvl.run_time, 0.01)
	if bot.done:
		check(SaveData.is_completed(lvl.level_id), "%s: completion saved" % label)


func test_n_bot_levels() -> void:
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		if not ResourceLoader.exists(Game.LEVELS[i]["scene"]):
			check(false, "level %d scene exists" % (i + 1))
			continue
		if not all_routes:
			await run_bot(i, 1200.0)
			continue
		var keep: int = LevelBase.route_variant
		var variants: int = 1
		for v: int in 16:
			LevelBase.route_variant = v
			await run_bot(i, 1200.0, v)
			variants = (world as LevelBase).route_variants if world is LevelBase else 1
			if v + 1 >= variants:
				break
		LevelBase.route_variant = keep


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
	# "race" twice: rebuilding the screen in place is what a colour swatch press does
	# (pressing the real swatch would write the player's settings.cfg)
	for id: String in ["levels", "race", "race", "settings", "victory", "main"]:
		var e0: int = trap.count()
		title.call("show_screen", id)
		await ticks(2)
		# Game.title_screen is set before the builder runs, so also require a live, non-empty screen
		var scr := title.get("_screen") as Control
		check(Game.title_screen == id and scr != null and scr.is_inside_tree() and scr.get_child_count() > 0 and trap.count() == e0, ("title screen builds: %s %s" % [id, trap.since(e0)]).strip_edges())
	var e1: int = trap.count()
	check(Net.host(24599) == OK, "hosting opens the lobby")
	await ticks(3)
	check(Game.title_screen == "lobby" and Net.roster.size() == 1 and trap.count() == e1, ("lobby shows the host in the roster %s" % trap.since(e1)).strip_edges())
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
	# settings inside the pause menu; leave through `closed`, not Done (which saves settings.cfg)
	pause.set_open(true)
	pause.call("_show_settings")
	await ticks(2)
	var sp: Array[Node] = pause.find_children("*", "SettingsPanel", true, false)
	check(pause.get("_settings") != null and sp.size() == 1 and sp[0].get_child_count() > 0, "pause settings panel builds")
	if sp.size() == 1:
		(sp[0] as SettingsPanel).closed.emit()
	await ticks(2)
	check(pause.get("_settings") == null and pause.get("_menu") != null, "settings returns to the pause menu")
	pause.set_open(false)
	check(not get_tree().paused, "pause menu closed again")
	lvl.hud.show_results(12.34, -1.0, true, 0)
	await ticks(2)
	var r := lvl.hud.get("_results") as Control
	check(r != null and r.is_inside_tree(), "results panel builds")
	lvl.hud.show_race_results(12.34)
	await ticks(2)
	var rr := lvl.hud.get("_results") as Control
	check(rr != null and rr != r and rr.is_inside_tree(), "race results panel builds")


# ---- momentum toolkit -------------------------------------------------------------------------

func test_s_boost_conveyor_ice() -> void:
	await new_world(Vector3(0, 0.1, 4))
	floor_slab()
	kit.boost(Vector3(0, 0.02, -6), Vector3(3, 0.2, 12), 0.0, 20.0)
	await settle()
	player.cmd_move = FWD
	var peak: float = 0.0
	var f0: int = Engine.get_physics_frames()
	while player.global_position.z > -11.5:
		if overdue(f0, 5.0, "the run down the boost strip"):
			return
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


# ---- wall run, mantle and the timed machines (level extension) --------------------------------

## Sprint along -Z beside a panel at x=+1.2 (or a plain wall), jump and drift toward it.
func _run_at_wall(wall_run: bool) -> void:
	await new_world(Vector3(0, 0.05, 4))
	kit.plat(Vector3(0, 0, 1), Vector3(8, 1, 10), "main", 0.0)
	if wall_run:
		kit.wallrun(Vector3(1.2, 2.2, -12), Vector3(16, 4.4, 0.5), 90.0)
	else:
		kit.block(Vector3(1.2, 2.2, -12), Vector3(0.5, 4.4, 16), Color.GRAY, true)
	await seconds(0.3)
	player.cmd_move = FWD
	await wait_until(func() -> bool: return player.global_position.z < -3.0, 2.0, "run-up")
	player.press_jump()
	player.cmd_jump = true
	player.cmd_move = Vector2(0.45, 1.0)


func test_x_wall_run_and_wall_jump() -> void:
	await _run_at_wall(true)
	var latched: bool = await wait_until(func() -> bool: return player.is_wall_running(), 0.8, "latch onto the wall-run panel")
	check(latched, "jumping along a wall-run panel latches onto it")
	var z0: float = player.global_position.z
	var y0: float = player.global_position.y
	player.cmd_move = FWD
	player.cmd_jump = false
	await seconds(0.9)
	check(player.is_wall_running(), "the run holds for most of a second")
	var ran: float = z0 - player.global_position.z
	check(ran > 8.0, "running the wall covers ground at speed (%.1f m in 0.9 s)" % ran)
	check(player.global_position.y > y0 - 1.5, "a slow arc, not a fall (%.2f m below the latch point)" % (y0 - player.global_position.y))
	player.press_jump()
	await ticks(2)
	check(not player.is_wall_running() and player.velocity.x < -5.0 and player.velocity.y > 7.0, "a wall jump kicks away from the wall and up (v %s)" % str(player.velocity.snapped(Vector3.ONE * 0.1)))
	check(player.velocity.z < -6.0, "and keeps the speed along the wall (%.1f)" % player.velocity.z)
	# a plain wall never latches
	await _run_at_wall(false)
	var plain: bool = false
	for i: int in 90:
		await get_tree().physics_frame
		plain = plain or player.is_wall_running()
	check(not plain, "an ordinary wall cannot be wall-run")
	player.cmd_move = Vector2.ZERO
	player.cmd_jump = false


## Jumping in just before a panel starts: the diagonal ray sees the face ahead while the body is
## not alongside yet. The run must start once we are beside it, not latch, drop and burn the panel.
func test_x_wall_run_leading_edge() -> void:
	await new_world(Vector3(0, 0.05, 4))
	floor_slab()
	kit.wallrun(Vector3(1.2, 2.6, -12), Vector3(16, 4.4, 0.5), 90.0)   # face at x 0.95, starts at z -4
	await seconds(0.3)
	var starts: Array[float] = []
	player.wall_run_started.connect(func(_n: Vector3) -> void: starts.append(player.global_position.z))
	var kicks: Array[int] = [0]
	player.wall_jumped.connect(func() -> void: kicks[0] += 1)
	player.teleport(Transform3D(Basis(), Vector3(0.45, 1.2, -2.6)))
	player.velocity = Vector3(0, 3.0, -10.0)
	player.cmd_move = FWD
	player.press_jump()      # a buffered press must not turn a false latch into a kick off nothing
	var ran: bool = await wait_until(func() -> bool: return player.is_wall_running(), 0.6, "latch beside the panel")
	await ticks(6)
	check(ran and player.is_wall_running(), "a jump that reaches a panel just before its start still gets the run (starts at z %s)" % str(starts))
	check(kicks[0] == 0, "and no wall jump fires off thin air ahead of the panel")
	check(starts.size() == 1 and starts[0] < -3.9, "it latches once, beside the panel, not ahead of its leading edge (z %s)" % str(starts))
	player.cmd_move = Vector2.ZERO


## Run at a 3.4 m face (too tall to jump onto) and jump near it, holding forward.
func _jump_at_face(ledge: bool) -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab()
	if ledge:
		kit.ledge(Vector3(0, 3.4, -6.5), Vector3(6, 3.4, 5))
	else:
		kit.block(Vector3(0, 1.7, -6.5), Vector3(6, 3.4, 5), Color.GRAY, true)
	await seconds(0.3)
	player.cmd_move = FWD
	await wait_until(func() -> bool: return player.global_position.z < -2.4, 2.0, "run-up to the face")
	player.press_jump()
	player.cmd_jump = true


func test_x_mantle() -> void:
	await _jump_at_face(true)
	var grabbed: bool = await wait_until(func() -> bool: return player.is_mantling(), 1.0, "catch the ledge")
	check(grabbed, "jumping at a gold-lipped ledge grabs it")
	await wait_until(func() -> bool: return not player.is_mantling() and player.grounded, 1.5, "climb onto the top")
	player.cmd_jump = false
	check(player.global_position.y > 3.3 and player.grounded, "and climbs onto its 3.4 m top (y %.2f)" % player.global_position.y)
	await _jump_at_face(false)
	await seconds(1.5)
	player.cmd_move = Vector2.ZERO
	player.cmd_jump = false
	check(player.global_position.y < 1.0 and not player.is_mantling(), "an ordinary 3.4 m block cannot be climbed (y %.2f)" % player.global_position.y)


## A turned crusher turns its press, its deadly underside and its guide frame together.
func test_x_crusher_yaw() -> void:
	var lvl: LevelBase = await load_level(0)
	var base: Vector3 = lvl.checkpoints[0].global_position
	lvl.player.use_device_input = false
	lvl.kit.plat(base + Vector3(40, 0, 0), Vector3(30, 1, 40), "main", 0.0)
	var at: Vector3 = base + Vector3(40, 0, 0)
	# a long, narrow press turned 90: 4 m along world Z, 1.2 m along X
	var cr: Crusher = lvl.kit.crusher(at, Vector3(4, 1.5, 1.2), 3.0, 3.0, 0.0, 90.0)
	var cols: Array[Vector3] = []
	for n: Node in lvl.get_children():
		if n is StaticBody3D and n != cr and (n as Node3D).global_position.distance_to(at) < 4.0 and (n as Node3D).global_position.y > at.y + 1.0:
			cols.append((n as Node3D).global_position - at)
	var along_z: bool = cols.size() == 2
	for c: Vector3 in cols:
		along_z = along_z and absf(c.x) < 0.05 and absf(c.z) > 2.2
	check(along_z, "a crusher turned 90 stands its guide columns on world Z, clear of a path along X (%s)" % str(cols))
	var walk: bool = lvl.kit.crusher(at + Vector3(10, 0, 0), Vector3(3, 1.5, 3)).rotation_degrees.y == 0.0
	check(walk, "the default crusher is unturned (existing levels unchanged)")
	# stand where only the TURNED footprint reaches (1.5 m along Z; unturned it would be 0.6 m)
	await seconds(0.3)   # let the new press settle into the physics server before standing under it
	await wait_until(func() -> bool: return cr.is_clear_for(Game.course_time, 0.4), 3.5, "crusher up")
	var d0: int = lvl.deaths
	lvl.player.teleport(Transform3D(Basis(), at + Vector3(0, 0.1, 1.5)))
	var hit: bool = await wait_until(func() -> bool: return lvl.deaths > d0, 3.5, "turned crusher slams")
	check(hit, "its deadly underside turns with it")


func test_x_lasers_crushers_pistons_portals() -> void:
	var lvl: LevelBase = await load_level(0)
	var base: Vector3 = lvl.checkpoints[0].global_position
	lvl.player.teleport(lvl.checkpoints[0].respawn_transform())
	lvl.player.use_device_input = false
	await seconds(0.3)
	lvl.kit.plat(base + Vector3(40, 0, 0), Vector3(30, 1, 40), "main", 0.0)
	# laser: harmless while off, deadly once it fires
	var gate: LaserGate = lvl.kit.laser(base + Vector3(40, 0.8, -4), Vector3(6, 0.3, 0.3), 2.0, 0.5, 0.0)
	await wait_until(func() -> bool: return gate.time_until_on(Game.course_time) > 0.6, 3.0, "laser off")
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(40, 0.1, -4)))
	await seconds(0.3)
	check(lvl.deaths == 0, "standing in a laser's path while it is off is safe")
	await wait_until(func() -> bool: return lvl.deaths > 0, 1.5, "laser fires")
	check(lvl.deaths == 1, "a laser gate kills once it fires")
	# crusher: slams on a player standing under it
	var cr: Crusher = lvl.kit.crusher(base + Vector3(48, 0, 8), Vector3(3, 1.5, 3), 3.0, 3.0, 0.0)
	await wait_until(func() -> bool: return cr.is_clear_for(Game.course_time, 0.4), 3.5, "crusher up")
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(48, 0.1, 8)))
	await wait_until(func() -> bool: return lvl.deaths > 1, 3.5, "crusher slams")
	check(lvl.deaths == 2, "a crusher kills the player it lands on")
	check(cr.is_clear_for(0.0, 1.0) and not cr.is_clear_for(1.4, 0.3), "crusher timing helper matches its rhythm")
	# piston: shoves a player standing in front of its face
	var pi: Piston = lvl.kit.piston(base + Vector3(34, 1.6, 10), Vector3(3, 1.6, 2), 0.0, 3.0, 2.0, 0.0)
	await wait_until(func() -> bool: return pi.extension_at(Game.course_time) == 0.0 and not pi.is_punching_at(Game.course_time + 0.4), 3.0, "piston retracted")
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(34, 0.1, 8.2)))
	var shoved: bool = await wait_until(func() -> bool: return lvl.player.velocity.z < -12.0, 3.0, "piston punch")
	check(shoved, "a piston shoves the player along its stroke")
	await wait_level_landing(lvl)
	# portal: out of the exit ring, heading its way, speed kept
	lvl.kit.portal(base + Vector3(30, 0, -2), 0.0, base + Vector3(44, 0, -14), 90.0)
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(30, 0.1, 5)))
	await seconds(0.3)
	lvl.player.cmd_move = FWD
	var warped: bool = await wait_until(func() -> bool: return lvl.player.global_position.distance_to(base + Vector3(44, 0.1, -14)) < 3.0, 2.5, "come out of the exit ring")
	check(warped, "a warp portal moves the player to its exit ring")
	check(lvl.player.velocity.x < -6.0, "heading out along the exit's facing with the entry speed (v %s)" % str(lvl.player.velocity.snapped(Vector3.ONE * 0.1)))
	lvl.player.cmd_move = Vector2.ZERO


func test_x_bot_new_moves() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	Game.level_index = -1
	Game.race_mode = false
	Game.course_time = 0.0
	Game.course_running = true
	var lvl: LevelBase = (load("res://tests/moves_course.gd") as GDScript).new() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var bot := RouteBot.new()
	lvl.add_child(bot)
	bot.attach(lvl)
	var t: float = 0.0
	while t < 60.0 and not bot.done and not bot.stuck:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	for line: String in bot.log_lines:
		print("        bot: ", line)
	check(bot.done and bot.retries <= 2, "the bot wall-runs a gap, mantles a wall and takes a portal (%.1fs, %d respawns, step %d/%d)" % [lvl.run_time, bot.retries, bot.step_index, lvl.route.size()])


func test_x_update_check_and_prompt() -> void:
	check(Updater.version_from_tag("v1.2.0") == "1.2.0" and Updater.version_from_tag("1.3") == "1.3.0" and Updater.version_from_tag("jump-circuit-v2.0.1") == "2.0.1", "release tags parse to versions")
	check(Updater.version_from_tag("jump-circuit-multiplayer-keepalive-2026-09-23") == "", "tags without a version are ignored")
	check(Updater.compare_versions("1.10.0", "1.9.3") == 1 and Updater.compare_versions("1.1.0", "1.1.0") == 0 and Updater.compare_versions("1.0.9", "1.1.0") == -1, "versions compare numerically")
	check(Updater.parse_release({"tag_name": "v9.0.0", "prerelease": true}).is_empty() and Updater.parse_release({"tag_name": "v9.0.0", "draft": true}).is_empty(), "drafts and pre-releases never prompt")
	var rel: Dictionary = Updater.parse_release({"tag_name": "v9.0.0", "html_url": "https://example.invalid/r", "body": "New levels", "assets": [{
		"name": "JumpCircuit-v9.0.0.zip",
		"browser_download_url": "https://github.com/fatty8me2/jump-circuit/releases/download/v9.0.0/JumpCircuit-v9.0.0.zip",
		"size": 1024,
	}]})
	check(rel.get("version", "") == "9.0.0" and rel.get("url", "") == "https://example.invalid/r" and rel.get("asset_name", "") == "JumpCircuit-v9.0.0.zip", "a release yields version and downloadable asset")
	# a newer release: the main menu asks once, focused on Install & Restart; Esc / B backs out to main
	Updater.available = rel
	Updater.prompted = false
	Game.title_screen = "main"
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	await ticks(3)
	var focus: Control = get_viewport().gui_get_focus_owner()
	check(Game.title_screen == "update" and focus is Button and (focus as Button).text == "Install & Restart", "the update prompt opens with Install & Restart focused")
	get_viewport().push_input(_key(KEY_ESCAPE))
	get_viewport().push_input(_key(KEY_ESCAPE, false))
	await ticks(3)
	check(Game.title_screen == "main", "Esc leaves the prompt for the main menu")
	title.call("show_screen", "main")
	await ticks(2)
	check(Game.title_screen == "main", "it asks only once per launch")
	title.queue_free()
	Updater.available = {}
	Updater.prompted = false
	await ticks(2)


## The in-game installer, end to end on paths with spaces (the save folder is "...\Jump Circuit\..."):
## 1.2.2 - 1.3.0 quoted the installer's arguments themselves, OS.create_process quoted them again,
## PowerShell got a split path, never ran, and the game quit into nothing. This runs the real
## installer script (with -NoLaunch: no game start, no window) exactly as the game launches it.
func test_x_update_installer_runs() -> void:
	# the handshake: the game only quits once the installer's "started" marker exists
	var root: String = ProjectSettings.globalize_path("user://updater test run")
	for sub: String in ["", "/install dir", "/updates dir", "/stale"]:
		DirAccess.make_dir_recursive_absolute(root + sub)
	var marker: String = root + "/updates dir/probe.zip.started"
	FileAccess.open(marker, FileAccess.WRITE).store_string("1")
	check(await Updater._installer_started(marker, 1.0), "a running installer's marker lets the game hand over")
	DirAccess.remove_absolute(marker)
	check(not await Updater._installer_started(marker, 0.3), "no marker: the game stays open instead of quitting into nothing")
	# stale downloads from an install that never ran are cleared at launch
	for f: String in ["JumpCircuit-v1.3.0-1.zip", "JumpCircuit-v1.3.0-2.zip", "JumpCircuit-v1.3.0-2.zip.started"]:
		FileAccess.open(root + "/stale/" + f, FileAccess.WRITE).store_string("x")
	FileAccess.open(root + "/stale/keep.txt", FileAccess.WRITE).store_string("x")
	check(Updater.clean_stale_downloads(root + "/stale") == 3 and FileAccess.file_exists(root + "/stale/keep.txt"),
		"leftover update downloads are removed, nothing else")
	# arguments go to create_process unquoted (it quotes paths with spaces itself)
	var install_dir: String = root + "/install dir"
	var zip_path: String = root + "/updates dir/JumpCircuit-v9.9.9-1.zip"
	var script_path: String = root + "/updates dir/install_update.ps1"
	var args: PackedStringArray = Updater.installer_arguments(script_path, 0, zip_path, install_dir,
		install_dir + "/JumpCircuit.exe", "9.9.9", true)
	var prequoted: bool = false
	for a: String in args:
		prequoted = prequoted or a.begins_with("\"")
	check(not prequoted and args.has(script_path) and args.has(zip_path), "installer arguments are passed unquoted")
	if OS.get_name() != "Windows":
		return
	# a fake installed game and a fake update archive, then the real installer script
	for f: String in Updater.REQUIRED_UPDATE_FILES:
		FileAccess.open(install_dir + "/" + f, FileAccess.WRITE).store_string("old " + f)
	var zip := ZIPPacker.new()
	zip.open(zip_path)
	for f: String in Updater.REQUIRED_UPDATE_FILES:
		zip.start_file(f)
		zip.write_file(("new " + f).to_utf8_buffer())
		zip.close_file()
	zip.close()
	FileAccess.open(script_path, FileAccess.WRITE).store_string(Updater.WINDOWS_INSTALLER_SCRIPT)
	var pid: int = OS.create_process(Updater.powershell_path(), args, false)
	check(pid > 0, "the installer process starts")
	var waited: float = 0.0
	while waited < 30.0 and FileAccess.file_exists(zip_path):
		await seconds(0.25)
		waited += 0.25
	var replaced: bool = true
	for f: String in Updater.REQUIRED_UPDATE_FILES:
		replaced = replaced and FileAccess.get_file_as_string(install_dir + "/" + f) == "new " + f
	check(replaced and not FileAccess.file_exists(zip_path) and not FileAccess.file_exists(zip_path + ".started"),
		"the installer ran from a path with spaces: game files replaced, download and marker cleaned up (%.1f s)" % waited)
	# tidy up the scratch folders
	for sub: String in ["/install dir", "/updates dir", "/stale", ""]:
		var d: DirAccess = DirAccess.open(root + sub)
		if d != null:
			for f: String in d.get_files():
				d.remove(f)
		DirAccess.remove_absolute(root + sub)


# ---- menus, pad bindings, settings, camera (polish pass B2) ----------------------------------

func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	return k


func _pad_button(button: JoyButton, device: int, pressed: bool = true) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.device = device
	b.button_index = button
	b.pressed = pressed
	return b


func _focus_after_rebuild() -> Control:
	await get_tree().process_frame
	await get_tree().process_frame
	return get_viewport().gui_get_focus_owner()


func test_z_b2_menu_focus_and_back_nav() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	SaveData.wipe()
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	await ticks(3)
	for id: String in ["main", "levels", "settings", "victory", "race"]:
		title.call("show_screen", id)
		var f: Control = await _focus_after_rebuild()
		var screen: Control = title.get("_screen")
		check(f != null and screen.is_ancestor_of(f), "title '%s' starts with a focused control (%s)" % [id, f.get_class() if f != null else "none"])
		if id == "levels":
			check(f is Button and (f as Button).text.begins_with("1 "), "level select starts on the first level still to clear")
		elif id == "settings":
			check(f is HSlider, "settings starts on its first slider")
		elif id == "victory":
			check(f is Button and (f as Button).text == "Level Select", "victory starts on Level Select")
	# Esc backs out of the race screen; main re-focuses the button that opened it
	get_viewport().push_input(_key(KEY_ESCAPE))
	get_viewport().push_input(_key(KEY_ESCAPE, false))
	var back_f: Control = await _focus_after_rebuild()
	check(Game.title_screen == "main" and back_f is Button and (back_f as Button).text == "Race Friends", "Esc on Race Friends returns to main, focused on Race Friends")
	# pad A (any slot) presses the focused button, pad B goes back
	title.call("show_screen", "main")
	await _focus_after_rebuild()
	get_viewport().push_input(_key(KEY_DOWN))
	get_viewport().push_input(_key(KEY_DOWN, false))
	get_viewport().push_input(_pad_button(JOY_BUTTON_A, 3))
	get_viewport().push_input(_pad_button(JOY_BUTTON_A, 3, false))
	await _focus_after_rebuild()
	check(Game.title_screen == "levels", "pad A on slot 3 presses the focused menu button")
	get_viewport().push_input(_pad_button(JOY_BUTTON_B, 1))
	get_viewport().push_input(_pad_button(JOY_BUTTON_B, 1, false))
	var f2: Control = await _focus_after_rebuild()
	check(Game.title_screen == "main" and f2 is Button and (f2 as Button).text == "Level Select", "pad B backs out of level select")
	# a stray Esc never disbands a hosted lobby
	check(Net.host(24597) == OK, "hosting opens the lobby")
	await ticks(3)
	get_viewport().push_input(_key(KEY_ESCAPE))
	get_viewport().push_input(_key(KEY_ESCAPE, false))
	await ticks(2)
	check(Game.title_screen == "lobby" and Net.active, "Esc in a hosted lobby keeps the lobby open")
	Net.leave()
	title.queue_free()
	await ticks(2)
	Game.title_screen = "main"


func test_z_b2_pad_bindings_any_slot() -> void:
	var a: InputEventJoypadButton = _pad_button(JOY_BUTTON_A, 2)
	check(InputMap.event_is_action(a, "jump") and InputMap.event_is_action(a, "ui_accept"), "pad A on any slot jumps and confirms menus")
	check(InputMap.event_is_action(_pad_button(JOY_BUTTON_B, 1), "ui_cancel"), "pad B is menu back")
	check(InputMap.event_is_action(_pad_button(JOY_BUTTON_START, 5), "pause"), "Start pauses from any slot")
	check(InputMap.event_is_action(_pad_button(JOY_BUTTON_DPAD_UP, 1), "move_forward"), "D-pad moves")
	var rs := InputEventJoypadMotion.new()
	rs.device = 1
	rs.axis = JOY_AXIS_RIGHT_X
	rs.axis_value = 0.6
	Input.parse_input_event(rs)
	Input.flush_buffered_events()
	var v: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	near(v.x, 0.5, 0.02, "right stick on slot 1 turns the camera, rescaled past the deadzone")
	var rs0 := rs.duplicate() as InputEventJoypadMotion
	rs0.axis_value = 0.0
	Input.parse_input_event(rs0)
	Input.flush_buffered_events()


func test_z_b2_settings_panel_and_sanitize() -> void:
	var snap: Dictionary = {}
	for p: String in Settings._props():
		snap[p] = Settings.get(p)
	var sp := SettingsPanel.new()
	var holder: Control = UiKit.centered(sp)
	add_child(holder)
	var f: Control = await _focus_after_rebuild()
	check(f is HSlider and sp.is_ancestor_of(f), "the settings panel focuses its first slider by itself (pause menu too)")
	check(not bool(sp.get("_dirty")), "building the panel leaves nothing to save")
	var fov_slider := sp.find_children("*", "HSlider", true, false)[1] as HSlider
	# (a value the slider is not already on: the developer's own settings may be 90)
	var want: float = 80.0 if is_equal_approx(fov_slider.value, 90.0) else 90.0
	fov_slider.value = want
	var readout := fov_slider.get_parent().get_child(1) as Label
	check(readout.text == "%d°" % roundi(want) and is_equal_approx(Settings.fov, want) and bool(sp.get("_dirty")), "FOV applies live, shows its value (%s) and marks the panel dirty" % readout.text)
	Settings.fullscreen = not bool(snap["fullscreen"])
	Settings.changed.emit()
	var fs := sp.get("_fullscreen_check") as CheckButton
	check(fs.button_pressed == Settings.fullscreen and fs.text == ("On" if Settings.fullscreen else "Off"), "the Fullscreen toggle follows an F11 change")
	sp.set("_dirty", false)  # never write the real settings.cfg from a test
	holder.queue_free()
	for p: String in snap:
		Settings.set(p, snap[p])
	Settings.apply()
	await ticks(2)
	# a hand-edited settings.cfg
	var path: String = "user://test_settings_b2.cfg"
	var cf := ConfigFile.new()
	cf.set_value("s", "fov", "abc")
	cf.set_value("s", "quality", 5)
	cf.set_value("s", "mouse_sensitivity", 9.0)
	cf.set_value("s", "music_volume", INF)
	cf.set_value("s", "master_volume", 1)
	cf.set_value("s", "color_index", -3)
	cf.set_value("s", "timer_mode", "sometimes")
	cf.set_value("s", "player_name", "   ")
	cf.save(path)
	Settings.fov = 80.0
	Settings.load_settings(path)
	check(is_equal_approx(Settings.fov, 80.0), "a non-numeric fov in settings.cfg is ignored")
	check(Settings.quality == Settings.QUALITY_NAMES.size() - 1 and is_equal_approx(Settings.mouse_sensitivity, 3.0), "out-of-range quality / sensitivity are clamped")
	check(is_equal_approx(Settings.music_volume, 0.4) and is_equal_approx(Settings.master_volume, 1.0), "inf volume falls back to default, an int volume is accepted")
	check(Settings.color_index == 5 and Settings.timer_mode == "auto" and Settings.player_name == "Runner", "colour wraps, unknown timer mode and blank name fall back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for p: String in snap:
		Settings.set(p, snap[p])
	Settings.apply()


func test_z_b2_camera_respawn_zoom_fov() -> void:
	var cam := OrbitCamera.new()
	add_child(cam)
	cam.set("_fov_kick", 10.0)
	cam.fov = Settings.fov + 10.0
	cam.set("_cur_dist", 2.9)
	cam.face(Vector3.FORWARD)
	check(is_equal_approx(cam.fov, Settings.fov) and float(cam.get("_fov_kick")) == 0.0 and is_equal_approx(float(cam.get("_cur_dist")), cam.distance), "respawn (face) drops the speed FOV kick and the wall-pulled zoom")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	cam._unhandled_input(wheel)
	cam._unhandled_input(wheel)
	var zoomed: float = cam.distance
	cam.queue_free()
	var cam2 := OrbitCamera.new()
	add_child(cam2)
	check(zoomed > 8.0 and is_equal_approx(cam2.distance, zoomed), "wheel zoom carries over to the next camera (%.1f m)" % zoomed)
	var fov0: float = Settings.fov
	Settings.fov = fov0 + 7.0
	Settings.changed.emit()
	check(is_equal_approx(cam2.fov, fov0 + 7.0), "an FOV change shows at once, even with the camera paused")
	Settings.fov = fov0
	Settings.changed.emit()
	cam2.queue_free()
	OrbitCamera.saved_distance = -1.0
	await ticks(2)


# ---- race networking logic (no sockets) ---------------------------------------------------------

func test_race_clock_and_roster_logic() -> void:
	# race clock: fixed steps steered toward the session clock (no per-tick wall-clock lurches)
	var saved_time: float = Game.course_time
	var saved_start: float = Net.race_start_time
	var dt: float = 1.0 / 120.0
	Net.race_start_time = Net.now() + 1.0
	Game.course_time = -1.2
	Game._advance_race_clock(dt)
	near(Game.course_time, Net.now() - Net.race_start_time, 0.002, "race countdown tracks the session clock exactly")
	# 10 s at 60 fps (two ticks back to back per frame), starting 80 ms behind the host;
	# the session clock is simulated (real time spent in the loop is cancelled out)
	var t0: float = Net.now()
	Game.course_time = 4.92
	var lo: float = 1.0
	var hi: float = 0.0
	for f: int in 600:
		Net.race_start_time = (t0 - 5.0) - float(f + 1) / 60.0 + (Net.now() - t0)
		for k: int in 2:
			var before: float = Game.course_time
			Game._advance_race_clock(dt)
			lo = minf(lo, Game.course_time - before)
			hi = maxf(hi, Game.course_time - before)
	var err_end: float = 15.0 - Game.course_time
	check(lo >= dt * 0.949 and hi <= dt * 1.051, "race clock steps stay within 5%% of a tick (%.2f..%.2f ms)" % [lo * 1000.0, hi * 1000.0])
	check(absf(err_end) < 0.01, "race clock converges on the session clock (error %.1f ms)" % (err_end * 1000.0))
	Game.race_mode = true
	Net.race_start_time -= 0.5
	Game._process(0.0)
	Game.race_mode = false
	near(Game.course_time, Net.now() - Net.race_start_time, 0.002, "a long hitch re-syncs the race clock at once")
	Game.course_time = saved_time
	Net.race_start_time = saved_start
	# standings tie-break, colour assignment and forward-only roster merges
	var saved_roster: Dictionary = Net.roster
	Net.roster = {
		5: {"name": "A", "color": 0, "cp": 3, "cp_at": 10.0, "finished": -1.0},
		7: {"name": "B", "color": 1, "cp": 3, "cp_at": 8.0, "finished": -1.0},
		9: {"name": "C", "color": 2, "cp": 2, "cp_at": 1.0, "finished": -1.0},
	}
	var want: Array[int] = [7, 5, 9]
	check(Net.standings() == want, "same checkpoint: whoever reached it first ranks higher %s" % str(Net.standings()))
	check(Net._free_color(11, 0) == 3 and Net._free_color(11, 4) == 4 and Net._free_color(5, 0) == 0, "a newcomer gets a colour nobody else wears")
	Net.in_race = true
	Net.roster[5]["finished"] = 40.0
	Net._sync_roster({
		5: {"name": "A", "color": 0, "cp": 1, "cp_at": 2.0, "finished": -1.0},
		7: {"name": "B", "color": 1, "cp": 3, "cp_at": 8.0, "finished": -1.0},
	})
	check(int(Net.roster[5]["cp"]) == 3 and float(Net.roster[5]["cp_at"]) == 10.0 and float(Net.roster[5]["finished"]) == 40.0 and not Net.roster.has(9),
		"a stale host snapshot can't roll back a racer's checkpoint or finish")
	Net.in_race = false
	Net.roster = saved_roster
	# a respawned racer's ghost snaps (new teleport seq) instead of sliding back
	var g := RemoteRacer.new()
	add_child(g)
	g.push_state(Vector3.ZERO, Vector3.ZERO, true, 0)
	await get_tree().process_frame
	g.push_state(Vector3(6, 0, 0), Vector3.ZERO, true, 0)
	check(g.global_position.length() < 0.01, "a nearby pose eases the ghost (no snap)")
	g.push_state(Vector3(0, 0, 6), Vector3.ZERO, true, 1)
	check(g.global_position.is_equal_approx(Vector3(0, 0, 6)), "a new teleport seq snaps the ghost")
	g.queue_free()


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
	# a long countdown while the level builds (a loaded machine can take > 1 s), then a short one
	Net.race_start_time = Net.now() + 30.0
	Game.course_time = -30.0
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var pause: PauseMenu = lvl.find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	check(Game.course_time < 0.0 and not lvl.player.control_enabled, "the race countdown holds the player (t=%.2f)" % Game.course_time)
	pause.set_open(true)
	Net.race_start_time = Net.now() + 0.3
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


# ---- B4a: knockback, teleport, blob shadow, pad ring, music -----------------------------------

func test_zb4a_knockback_beats_jump_press() -> void:
	await new_world(Vector3(0, 0.05, 2.5))
	floor_slab()
	kit.bumper(Vector3.ZERO, 16.0, 8.0)
	await settle()
	var counts: Array[int] = [0, 0, 0]      # knocked, jumped, bounced
	player.knocked.connect(func(_v: Vector3) -> void:
		counts[0] += 1
		player.press_jump())                 # a reflexive jump press on contact
	player.jumped.connect(func() -> void: counts[1] += 1)
	player.bounced.connect(func(_s: float) -> void: counts[2] += 1)
	player.cmd_move = FWD
	var t: int = 0
	while counts[0] == 0 and t < 240:
		await get_tree().physics_frame
		t += 1
	player.cmd_move = Vector2.ZERO
	var peak_vy: float = player.velocity.y
	for i: int in 40:
		if i < 6:
			player.press_jump()
		await get_tree().physics_frame
		peak_vy = maxf(peak_vy, player.velocity.y)
	check(counts[0] == 1 and counts[2] == 0, "a bumper hit emits knocked once and never bounced (%d/%d)" % [counts[0], counts[2]])
	check(counts[1] == 0 and peak_vy < 8.2, "a jump pressed on contact cannot overwrite the throw (peak vy %.2f, jumps %d)" % [peak_vy, counts[1]])
	await wait_landing()


func test_zb4a_teleport_clears_floor_state() -> void:
	await new_world(Vector3(4, 0.5, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -6, 0))
	var arms: Array[Dictionary] = [{"pos": Vector3(4, 0, 0), "size": Vector3(8, 0.5, 2.5)}]
	var spin: RotatingPlatform = kit.spinner(Vector3(0, 0, 0), 4.0, arms)
	kit.plat(Vector3(60, 0, 0), Vector3(6, 1, 6), "main", 0.0)
	await settle()
	await seconds(0.5)
	check(player.grounded and player.platform_velocity.length() > 3.0, "riding the spinner before the teleport")
	var layers: int = player.platform_floor_layers
	var landings: Array[int] = [0]
	player.landed.connect(func(_i: float) -> void: landings[0] += 1)
	player.teleport(Transform3D(Basis(Vector3.UP, PI), Vector3(60, 0.15, 0)))
	await get_tree().physics_frame
	var shove: float = Vector2(player.global_position.x - 60.0, player.global_position.z).length()
	check(shove < 0.01, "the old spinner does not shove the player on the teleport tick (%.3fm)" % shove)
	check(player.global_basis.is_equal_approx(Basis.IDENTITY), "the body stays unrotated after a rotated teleport")
	check(player.facing_dir.is_equal_approx(Vector3(0, 0, 1)), "facing still follows the teleport heading")
	check(player.platform_floor_layers == layers, "platform layers restored after the teleport move")
	await seconds(0.3)
	check(player.grounded and landings[0] == 1, "lands once on the new pad (%d)" % landings[0])
	check(player.last_jump_distance < 0.05, "jump stats restart at the teleport (%.2fm)" % player.last_jump_distance)
	# two teleports before a tick (race setup) must not lose the saved layers
	player.teleport(Transform3D(Basis(), Vector3(60, 0.15, 1)))
	player.teleport(Transform3D(Basis(), spin.global_transform * Vector3(4, 0.5, 0)))
	await seconds(0.5)
	check(player.platform_floor_layers == layers, "a double teleport keeps platform carry intact")
	var r0: Vector3 = player.global_position
	await seconds(0.5)
	check(player.grounded and Vector2(player.global_position.x - r0.x, player.global_position.z - r0.z).length() > 1.0, "and the spinner carries the player again")


func test_zb4a_blob_shadow_fit() -> void:
	await new_world(Vector3(0, 4.05, 0))
	floor_slab()
	kit.plat(Vector3(0, 4, 0), Vector3(3, 1, 3), "main", 0.0)
	await settle()
	await get_tree().process_frame
	var shadow: Decal = player.get("_shadow")
	near(shadow.size.y, BlobShadow.TOP + BlobShadow.UNDER, 0.1, "standing on a platform: the shadow box ends just under it")
	var d := BlobShadow.make()
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	BlobShadow.fit(d, space, Vector3(3.0, 4.0, 0), 1)
	near(d.size.y, BlobShadow.TOP + 4.0 + BlobShadow.UNDER, 0.05, "past the platform edge the shadow reaches the floor below")
	check(absf(d.position.y + d.size.y * 0.5 - BlobShadow.TOP) < 0.001, "box top stays just above the feet")
	BlobShadow.fit(d, space, Vector3(0, 7.0, 0), 1)
	near(d.size.y, BlobShadow.TOP + 3.0 + BlobShadow.UNDER, 0.05, "above stacked geometry only the first surface is covered")
	BlobShadow.fit(d, space, Vector3(500, 4.0, 0), 1)
	near(d.size.y, BlobShadow.TOP + BlobShadow.REACH + BlobShadow.UNDER, 0.05, "over the void the shadow keeps its full reach")
	d.free()


func test_zb4a_pad_ring_and_music() -> void:
	await new_world(Vector3(0, 2.0, 0))
	floor_slab()
	var pad: BouncePad = kit.pad(Vector3(0, 0, 0), 20.0)
	var bounces: Array[int] = [0]
	player.bounced.connect(func(_s: float) -> void: bounces[0] += 1)
	var t: int = 0
	while bounces[0] == 0 and t < 240:
		await get_tree().physics_frame
		t += 1
	var ring: MeshInstance3D = pad.get("_shock")
	check(ring != null and ring.visible, "a bounce shows the pad's shockwave ring")
	await seconds(0.5)
	check(ring != null and not ring.visible and is_equal_approx(ring.scale.y, 0.3), "the ring expands flat and hides again")
	# music: rapid track changes crossfade without stranding a player
	Sfx.music("title")
	await ticks(12)
	Sfx.music("gardens")
	await ticks(12)
	Sfx.music("foundry")
	await seconds(1.2)
	var players: Array = Sfx.get("_music_players")
	var audible: int = 0
	for m: AudioStreamPlayer in players:
		if m.playing:
			audible += 1
	var cur: AudioStreamPlayer = Sfx.get("_music")
	check(audible <= 1 and is_equal_approx(cur.volume_db, 0.0), "after the crossfades one bed plays at full volume (%d playing)" % audible)
	Sfx.music("")
	await seconds(0.8)
	audible = 0
	for m: AudioStreamPlayer in players:
		if m.playing:
			audible += 1
	check(audible == 0, "music('') fades the bed out and stops it")


# ---- the score: map music with progress layers, fanfares, chimes, the pause muffle ------------

func test_zb4b_scores_and_layers() -> void:
	# every map has a two-layer score whose layers are the same length (they play locked together)
	for info: Dictionary in Game.LEVELS:
		var id: String = info["id"]
		var base: AudioStream = load("res://audio/music_%s.ogg" % id) if ResourceLoader.exists("res://audio/music_%s.ogg" % id) else null
		var hi: AudioStream = load("res://audio/music_%s_hi.ogg" % id) if ResourceLoader.exists("res://audio/music_%s_hi.ogg" % id) else null
		check(base != null and hi != null, "%s has both score layers" % id)
		if base != null and hi != null:
			near(hi.get_length(), base.get_length(), 0.01, "%s layers are the same length" % id)
		check(Sfx.has_clip("fanfare_" + id), "%s has a course fanfare" % id)
		check(Sfx.has_clip("checkpoint_" + id), "%s has a checkpoint chime" % id)
	for track: String in ["title", "lobby", "results", "victory"]:
		check(ResourceLoader.exists("res://audio/music_%s.ogg" % track), "the %s music exists" % track)
	check(Sfx.has_clip("new_best"), "the new-best sparkle exists")
	# the title screens pick their music
	var title_script: GDScript = load("res://ui/title.gd")
	check(title_script.call("screen_music", "main") == "title" and title_script.call("screen_music", "lobby") == "lobby"
		and title_script.call("screen_music", "practice") == "lobby" and title_script.call("screen_music", "victory") == "victory",
		"title screens map to title / lobby / victory music")
	# themed clips: the map's own chime, and the plain one elsewhere
	Sfx.set_theme("reef")
	check(Sfx.themed("checkpoint") == "checkpoint_reef", "themed() prefers the map's own clip")
	Sfx.set_theme("nowhere")
	check(Sfx.themed("checkpoint") == "checkpoint", "themed() falls back to the plain clip")
	Sfx.set_theme("")
	# layers: a map score is a synchronized pair; progress swells the second layer in and out
	Sfx.music("")
	await seconds(0.8)
	Sfx.music("gardens")
	var cur: AudioStreamPlayer = Sfx.get("_music")
	check(cur.stream is AudioStreamSynchronized, "a map score plays both layers locked together")
	check(is_equal_approx(Sfx.music_layer_mix(), 0.0), "the second layer starts out")
	Sfx.music_progress(0.1)
	await seconds(0.5)
	check(is_equal_approx(Sfx.music_layer_mix(), 0.0), "early stages keep it out")
	Sfx.music_progress(1.0)
	await seconds(Sfx.LAYER_FADE + 0.6)
	near(Sfx.music_layer_mix(), 1.0, 0.001, "the last stage brings the second layer fully in")
	Sfx.music_progress(0.0)
	await seconds(Sfx.LAYER_FADE + 0.6)
	near(Sfx.music_layer_mix(), 0.0, 0.001, "a restart takes it back out")
	# a fanfare ducks the score, then hands over to the results music
	check(Sfx.fanfare("fanfare_gardens", "results"), "the course fanfare plays")
	await seconds(0.4)
	var duck: AudioEffectAmplify = null
	var bi: int = AudioServer.get_bus_index("Ducked")
	for i: int in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, i) is AudioEffectAmplify:
			duck = AudioServer.get_bus_effect(bi, i)
	check(duck != null and duck.volume_db < -20.0, "the score ducks under the fanfare")
	var ff: AudioStream = load("res://audio/fanfare_gardens.ogg")
	await seconds(ff.get_length())
	check(Sfx.current_music() == "results" and duck != null and duck.volume_db > -1.0,
		"after the fanfare the results music takes over, un-ducked (%s)" % Sfx.current_music())
	# re-entering a level during a fanfare cancels the hand-over
	Sfx.music("gardens")
	await seconds(1.0)
	Sfx.fanfare("fanfare_gardens", "results")
	await seconds(0.3)
	Sfx.music("gardens")
	await seconds(ff.get_length() + 0.5)
	check(Sfx.current_music() == "gardens" and duck.volume_db > -1.0, "a restart during the fanfare keeps the map's score")
	# the pause muffle
	var lp: AudioEffectLowPassFilter = null
	for i: int in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, i) is AudioEffectLowPassFilter:
			lp = AudioServer.get_bus_effect(bi, i)
	Sfx.muffle(true)
	await seconds(0.6)
	check(lp != null and lp.cutoff_hz < 1500.0 and Sfx.is_muffled(), "pausing muffles the score")
	Sfx.muffle(false)
	await seconds(0.9)
	check(lp != null and lp.cutoff_hz > 15000.0 and not Sfx.is_muffled(), "resuming clears the muffle")
	check(AudioServer.get_bus_index("Ambience") >= 0, "the ambience bus exists")
	Sfx.checkpoint_chime(3)
	Sfx.music("")
	await seconds(0.8)


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


# ---- harness self-checks -------------------------------------------------------------------------

func test_w_error_trap_records_errors() -> void:
	var t := TestLib.ErrorTrap.new()
	var no_trace: Array[ScriptBacktrace] = []
	t._log_error("f", "res://a.gd", 3, "cond", "", false, Logger.ERROR_TYPE_WARNING, no_trace)
	check(t.count() == 0, "error trap ignores warnings")
	t._log_error("f", "res://a.gd", 5, "cond", "why", false, Logger.ERROR_TYPE_SCRIPT, no_trace)
	t._log_error("f", "res://b.gd", 9, "cond2", "", false, Logger.ERROR_TYPE_ERROR, no_trace)
	check(t.count() == 2 and t.since(1) == "cond2 @ res://b.gd:9", "error trap records script and engine errors with where they happened (%s)" % t.since(0))


func test_w2_route_bot_gives_up_when_route_ends() -> void:
	var lvl: LevelBase = await load_level(0)
	lvl.route.clear()
	lvl.r_walk(lvl.player.global_position)
	var bot := RouteBot.new()
	lvl.add_child(bot)
	bot.attach(lvl)
	var f0: int = Engine.get_physics_frames()
	while not bot.stuck and not bot.done and not overdue(f0, 20.0, "the route bot to give up"):
		await get_tree().physics_frame
	var why: String = bot.log_lines[-1] if not bot.log_lines.is_empty() else ""
	check(bot.stuck and not bot.done and why.begins_with("route exhausted"), "route bot gives up soon when its route ends short of the finish (%s)" % why)


## A checkpoint touched in the middle of a step moves the level's respawn point; the bot must
## resume from that checkpoint's steps, not replay the stage before it from the wrong spot.
func test_w2_route_bot_resumes_at_touched_checkpoint() -> void:
	var lvl: LevelBase = await load_level(0)
	var marks: Array[int] = []
	for i: int in lvl.route.size():
		if str(lvl.route[i]["kind"]) == "checkpoint":
			marks.append(i)
	check(marks.size() == lvl.checkpoints.size() and marks.size() >= 2, "level 1's route marks every checkpoint (%d marks, %d checkpoints)" % [marks.size(), lvl.checkpoints.size()])
	var bot := RouteBot.new()
	lvl.add_child(bot)
	bot.attach(lvl)
	await ticks(2)
	bot.set_physics_process(false)
	# the bot is still before checkpoint 1's mark, but the player has touched checkpoint 2
	bot.step_index = 1
	lvl.player.teleport(lvl.checkpoints[1].respawn_transform())
	await wait_until(func() -> bool: return lvl.current_checkpoint == 2, 1.0, "touch checkpoint 2")
	lvl.respawn()
	check(bot.step_index == marks[1] + 1, "after a respawn the bot resumes after checkpoint 2's mark (step %d, want %d)" % [bot.step_index, marks[1] + 1])
	lvl.respawn()
	check(bot.step_index == marks[1] + 1, "and stays there on the next retry")
	bot.queue_free()


## Touching down at the end of a kick step's flight zeroes the fall speed - a jump in vertical
## speed that is not a kick. It must not make the next kick step start "already kicked".
func test_w2_route_bot_landing_is_not_a_kick() -> void:
	var lvl: LevelBase = await load_level(0)
	var cp: Checkpoint = lvl.checkpoints[0]
	lvl.player.teleport(cp.respawn_transform())
	await seconds(0.3)
	var ground: Vector3 = lvl.player.global_position
	lvl.route.clear()
	lvl.route.append({"kind": "kick", "from": ground, "to": ground})
	lvl.route.append({"kind": "kick", "from": ground + Vector3(0, 0, 2), "to": ground + Vector3(0, 0, 8)})
	var bot := RouteBot.new()
	lvl.add_child(bot)
	bot.attach(lvl)
	bot.set("_phase", 1)       # flying after the first kick
	lvl.player.teleport(Transform3D(Basis(), ground + Vector3(0, 6.0, 0)))
	await wait_until(func() -> bool: return bot.step_index == 1, 3.0, "land and move on")
	await ticks(2)
	check(bot.step_index == 1 and int(bot.get("_phase")) == 0 and not bool(bot.get("_fk_pending")),
		"a hard landing ends the kick's flight without counting as the next kick (phase %d)" % int(bot.get("_phase")))
	bot.queue_free()


## A bounce handed on by a step's flight is for the step right after it only.
func test_w2_route_bot_bounce_handover_is_one_step() -> void:
	var lvl: LevelBase = await load_level(0)
	var p: Vector3 = lvl.player.global_position
	lvl.route.clear()
	lvl.route.append({"kind": "walk", "to": p + Vector3(0, 0, -30)})
	var bot := RouteBot.new()
	lvl.add_child(bot)
	bot.attach(lvl)
	bot.set("_pending_bounce", true)
	await ticks(3)
	check(not bool(bot.get("_pending_bounce")), "a walk step does not carry a handed-over bounce on to a later pad or kick")
	bot.queue_free()


# ---- B4b: game feel (respawn veil, checkpoint / finish celebrations, Volt feedback) --------------

## The respawn veil overlays a respawn that has already happened: cause-tinted, never
## brighter than the old white flash, gone within a blink, and control is live at once.
func test_zb4b_respawn_veil_never_delays_control() -> void:
	var lvl: LevelBase = await load_level(0)
	var cp: Checkpoint = lvl.checkpoints[0]
	lvl.player.use_device_input = false
	lvl.player.teleport(cp.respawn_transform())
	await wait_until(func() -> bool: return lvl.current_checkpoint == 1, 1.0, "the first checkpoint")
	var veil: ColorRect = lvl.hud._flash
	var base: Vector3 = cp.global_position + Vector3(40, 0, 0)
	lvl.kit.plat(base, Vector3(20, 1, 20), "main", 0.0)
	lvl.kit.hazard(base + Vector3(0, 0.6, 0), Vector3(4, 1.2, 4))
	await ticks(2)
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(0, 0.1, 0)))
	var f0: int = Engine.get_physics_frames()
	while lvl.deaths == 0 and not overdue(f0, 2.0, "the kill brick"):
		await get_tree().physics_frame
	var c: Color = veil.color
	check(lvl.deaths == 1 and lvl.player.global_position.distance_to(cp.global_position) < 1.0, "a kill brick respawns at the checkpoint at once")
	check(c.r > c.g + 0.25 and c.a <= 0.5, "under a red hazard veil (%s)" % str(c))
	lvl.player.cmd_move = FWD
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(lvl.player.control_enabled and lvl.player.horizontal_speed() > 0.1, "control is live right after the respawn (%.2f m/s)" % lvl.player.horizontal_speed())
	lvl.player.cmd_move = Vector2.ZERO
	await real_seconds(0.45)
	check(veil.color.a < 0.02, "the veil has cleared within 0.45 s (alpha %.3f)" % veil.color.a)
	await ticks(3)
	lvl.manual_respawn()
	c = veil.color
	check(is_equal_approx(c.a, 0.3) and c.r < 0.1, "R while standing gets the lightest, neutral veil (%s)" % str(c))
	await ticks(3)
	lvl.fail()
	c = veil.color
	check(is_equal_approx(c.a, 0.55) and c.r < 0.1, "a fall-out gets a dark veil no stronger than the old flash (%s)" % str(c))
	# an invisible catch net (level 2) is a fall-out, not a hazard hit
	var net := KillZone.new()
	net.size = Vector3(6, 2, 6)
	net.show_mesh = false
	lvl.kit._add(net, base + Vector3(7, 1.0, 0))
	await ticks(3)
	var d0: int = lvl.deaths
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(7, 0.1, 0)))
	f0 = Engine.get_physics_frames()
	while lvl.deaths == d0 and not overdue(f0, 2.0, "the catch net"):
		await get_tree().physics_frame
	c = veil.color
	check(lvl.deaths == d0 + 1 and c.r < 0.1, "an invisible catch net counts as a fall (%s)" % str(c))


## "STAGE n / N" banner merged with the split, ring flare + sparks, and a flare that
## can never relight a ring switched off straight after (F6, close checkpoints).
func test_zb4b_checkpoint_banner_and_flare() -> void:
	SaveData.wipe()
	var keep_mode: String = Settings.timer_mode
	Settings.timer_mode = "on"
	var lvl: LevelBase = await load_level(0)
	var n: int = lvl.checkpoints.size()
	var best: Array = []
	for i: int in n:
		best.append(50.0 * (i + 1))
	SaveData.record_finish(lvl.level_id, 999.0, 4, best)
	var cp: Checkpoint = lvl.checkpoints[0]
	lvl.player.teleport(cp.respawn_transform())
	await wait_until(func() -> bool: return lvl.current_checkpoint == 1, 1.0, "the first checkpoint")
	var toast: Label = lvl.hud._toast
	var sub: Label = lvl.hud._toast_sub
	check(toast.text == "STAGE 2 / %d" % (n + 1) and sub.text.begins_with("-"), "the checkpoint banner names the new stage over the split (%s / %s)" % [toast.text, sub.text])
	var ring: StandardMaterial3D = cp.get("_ring_mat")
	var burst: GPUParticles3D = cp.get("_burst")
	check(ring.emission_energy_multiplier > 2.4 and burst != null and burst.emitting, "the ring flares and throws sparks (%.2f)" % ring.emission_energy_multiplier)
	lvl.player.teleport(lvl.checkpoints[1].respawn_transform())
	await wait_until(func() -> bool: return lvl.current_checkpoint == 2, 1.0, "the second checkpoint")
	await real_seconds(0.8)
	check(not cp.active and is_equal_approx(ring.emission_energy_multiplier, 0.15), "a ring switched off mid-flare stays dark (%.2f)" % ring.emission_energy_multiplier)
	check(toast.scale.is_equal_approx(Vector2.ONE) and lvl.hud._stage.modulate.is_equal_approx(Color.WHITE), "banner and stage counter settle")
	lvl.hud.checkpoint_reached(n, 400.0)
	check(toast.text == "FINAL STAGE" and sub.text != "" and toast.scale.x > 1.2, "the last checkpoint pops a FINAL STAGE banner (%s / %s)" % [toast.text, sub.text])
	lvl.hud.toast("Someone finished")
	check(toast.scale == Vector2.ONE and sub.text == "", "a plain toast doesn't pop and has no split line")
	Settings.timer_mode = keep_mode
	SaveData.wipe()


## PlayerVisual driven frame by frame: footstep cadence and quiet windows, separate
## landing / takeoff puffs, the horizontal-speed streak, and the respawn reset.
func test_zb4b_volt_steps_dust_trail_respawn() -> void:
	var v := PlayerVisual.new()
	add_child(v)
	await ticks(1)
	var steps: Array[int] = [0]
	v.footstep.connect(func(_s: float) -> void: steps[0] += 1)
	var dt: float = 1.0 / 60.0
	var run := Vector3(0, 0, -9)
	for i: int in 120:
		v.animate(dt, run, true, Vector3.FORWARD)
	check(steps[0] >= 10 and steps[0] <= 12, "a 9 m/s run plants about 5.7 steps a second (%d in 2 s)" % steps[0])
	steps[0] = 0
	for i: int in 60:
		v.animate(dt, Vector3(0, 0, -1), true, Vector3.FORWARD)
	for i: int in 60:
		v.animate(dt, run, false, Vector3.FORWARD)
	check(steps[0] == 0, "no steps when shuffling below 1.5 m/s or in the air")
	v.set("_stride", ceilf(float(v.get("_stride")) / PI) * PI - 0.05)
	v.on_land(5.0)
	for i: int in 4:
		v.animate(dt, run, true, Vector3.FORWARD)
	check(steps[0] == 0, "no step right on top of a landing")
	# a buffered jump one tick after a heavy landing keeps the landing puff
	var dust: GPUParticles3D = v.get("_dust")
	var jdust: GPUParticles3D = v.get("_jump_dust")
	v.on_land(22.0)
	v.on_jump()
	check(dust.emitting and is_equal_approx(dust.amount_ratio, 1.0) and jdust.emitting and is_equal_approx(jdust.amount_ratio, 0.5), "the takeoff puff has its own emitter: the full landing puff survives")
	# speed streak follows horizontal speed, plus big launches
	var trail: GPUParticles3D = v.get("_trail")
	v.animate(dt, Vector3(9, 0, 0), true, Vector3.FORWARD)
	var run_off: bool = not trail.emitting
	v.animate(dt, Vector3(9, 12, 0), false, Vector3.FORWARD)
	var hop_off: bool = not trail.emitting
	check(run_off and hop_off, "plain running and ordinary hops leave no streak")
	v.animate(dt, Vector3(12, 0, 0), true, Vector3.FORWARD)
	check(trail.emitting and is_equal_approx(trail.position.y, 0.28), "over 11 m/s on the ground: a low streak")
	v.animate(dt, Vector3(0, 18, 0), false, Vector3.FORWARD)
	check(trail.emitting and is_equal_approx(trail.amount_ratio, 0.75) and is_equal_approx(trail.position.y, 0.5), "a straight-up pad launch keeps a dense streak (%.2f)" % trail.amount_ratio)
	# respawn: the death pose (fast fall, lean) must not carry over or jolt
	for i: int in 30:
		v.animate(dt, Vector3(20, -30, 0), false, Vector3.RIGHT)
	v.on_respawn()
	v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
	var lean: Vector2 = v.get("_lean")
	check(lean.length() < 0.02 and float(v.get("_flare")) > 1.0 and not trail.emitting, "a respawn clears the lean with no jolt and pops the bulb (lean %.3f)" % lean.length())
	# a pop during a run of long frames (0.13 s hitches) must settle, not flip-flop
	v.on_bounce(20.0)
	var peak_late: float = 0.0
	for i: int in 12:
		v.animate(0.13, Vector3.ZERO, true, Vector3.FORWARD)
		if i >= 6:
			peak_late = maxf(peak_late, absf(float(v.get("_squash"))))
	check(peak_late < 0.05, "the squash spring settles through frame hitches (late peak %.3f)" % peak_late)
	v.queue_free()
	# footsteps only sound while the player is actually steering
	await new_world()
	floor_slab()
	await settle()
	player.cmd_move = FWD
	await ticks(2)
	var steering: float = player.move_input
	player.control_enabled = false
	await ticks(1)
	check(is_equal_approx(steering, 1.0) and player.move_input == 0.0, "move_input follows the stick and drops to 0 with control off")
	player.control_enabled = true
	player.cmd_move = Vector2.ZERO


## Crossing the gate: confetti and a brief lamp / veil / glow flare that settles again,
## without touching the shared Look.flat glow material.
func test_zb4b_finish_gate_celebrates() -> void:
	await new_world(Vector3(0, 0.05, 6))
	floor_slab()
	# (away from the origin: Jolt judges the first step from where the player was added)
	var gate: FinishGate = kit.finish(Vector3(0, 0, -20))
	var shared: StandardMaterial3D = Look.flat(Look.c("accent"), 0.3, 0.0, 3.0)
	var reached: Array[int] = [0]
	gate.reached.connect(func() -> void: reached[0] += 1)
	await settle()
	check(reached[0] == 0, "the gate is quiet until the player enters it")
	player.teleport(Transform3D(Basis(), Vector3(0, 0.05, -20)))
	await wait_until(func() -> bool: return reached[0] > 0, 1.0, "the finish gate")
	# (a one-shot reads as emitting only through its short emission window)
	var confetti: GPUParticles3D = gate.get("_confetti")
	var popped: bool = confetti.emitting
	await real_seconds(0.05)
	var lamp: OmniLight3D = gate.get("_lamp")
	var glow: StandardMaterial3D = gate.get("_glow")
	check(reached[0] == 1 and popped and lamp.light_energy > 3.0 and glow.emission_energy_multiplier > 3.0, "crossing the gate pops confetti and flares the lamp (%.2f)" % lamp.light_energy)
	check(is_equal_approx(shared.emission_energy_multiplier, 3.0), "the flare leaves the shared glow material alone")
	await real_seconds(1.3)
	var veil: StandardMaterial3D = gate.get("_veil_mat")
	check(is_equal_approx(lamp.light_energy, 2.5) and is_equal_approx(veil.albedo_color.a, 0.16) and is_equal_approx(glow.emission_energy_multiplier, 3.0), "the gate settles back (lamp %.2f, veil %.2f)" % [lamp.light_energy, veil.albedo_color.a])


# ---- final review fixes ---------------------------------------------------------------------------

## An in-place restart drops the last run's stage banner and poses every clock-driven
## obstacle for t=0 at once (no interpolated sweep across the course).
func test_zf_restart_clears_banner_and_snaps_obstacles() -> void:
	var lvl: LevelBase = await load_level(3)
	lvl.player.teleport(lvl.checkpoints[0].respawn_transform())
	await seconds(0.3)
	var toast: Label = lvl.hud.get("_toast")
	check(lvl.current_checkpoint == 1 and toast.modulate.a > 0.0, "banking a checkpoint shows the stage banner")
	Game.course_time = 40.0
	await ticks(2)
	lvl.restart_run()
	var movers: int = 0
	var snapped: int = 0
	for node: Node in get_tree().get_nodes_in_group("course_clock"):
		if node is MovingPlatform:
			var mp := node as MovingPlatform
			movers += 1
			if mp.position.is_equal_approx((mp.get("_origin") as Vector3) + mp.offset_at(Game.course_time)):
				snapped += 1
	check(movers > 0 and snapped == movers, "restart poses every mover for the new clock before the next tick (%d/%d)" % [snapped, movers])
	check(is_zero_approx(toast.modulate.a) and (lvl.hud.get("_toast_sub") as Label).text == "", "restart clears the stage banner")
	await seconds(0.3)
	check(is_zero_approx(toast.modulate.a), "and it stays cleared on the new run")


## A colour the race host lends on join is for that session only: the player's own
## pick is what gets saved, and it comes back when the session ends.
func test_zf_host_assigned_colour_is_session_only() -> void:
	var saved: int = Settings.color_index
	Net.leave()
	Settings.color_index = 3
	Net._sync_roster({1: {"name": "Me", "color": 0, "cp": 0, "finished": -1.0}})
	check(Settings.color_index == 0 and Net.preferred_color == 3, "joining wears the colour the host assigned")
	Net._shutdown()
	check(Settings.color_index == 3 and Net.preferred_color == -1, "ending the session gives the player's own colour back")
	Settings.color_index = saved


## A controller always works on the main menu: stick and D-pad move, A presses, the
## controls line switches to pad prompts, and a menu that lost focus (a stray mouse
## click) is picked up again by the first pad press instead of ignoring it.
func test_zf_main_menu_controller() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	title.call("show_screen", "main")
	await ticks(3)
	var focused := func() -> String:
		var f: Control = get_viewport().gui_get_focus_owner()
		return (f as Button).text if f is Button else ""
	var first: String = focused.call()
	# press and release a frame apart, like a real pad (Input merges stick motion within a frame)
	var send := func(ev: InputEvent) -> void:
		Input.parse_input_event(ev)
		await get_tree().process_frame
		var up: InputEvent = ev.duplicate()
		if up is InputEventJoypadMotion:
			(up as InputEventJoypadMotion).axis_value = 0.0
		else:
			up.set("pressed", false)
		Input.parse_input_event(up)
	var stick := InputEventJoypadMotion.new()
	stick.device = 2
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = 1.0
	await send.call(stick)
	await ticks(2)
	var after_stick: String = focused.call()
	check(first != "" and after_stick != "" and after_stick != first, "the left stick moves down the main menu ('%s' -> '%s')" % [first, after_stick])
	var hint: Label = title.get("_controls_hint")
	check(Game.using_pad and hint.text.begins_with("Left stick"), "the controls line switches to pad prompts")
	var dpad := InputEventJoypadButton.new()
	dpad.device = 2
	dpad.button_index = JOY_BUTTON_DPAD_UP
	dpad.pressed = true
	await send.call(dpad)
	await ticks(2)
	check(focused.call() == first, "the D-pad moves back up")
	get_viewport().gui_release_focus()
	await send.call(stick)
	await ticks(3)
	check(focused.call() != "", "with nothing focused, the first stick push picks the menu up again (%s)" % focused.call())
	var key := InputEventKey.new()
	key.keycode = KEY_DOWN
	key.pressed = true
	await send.call(key)
	await ticks(2)
	check(not Game.using_pad and hint.text.begins_with("WASD"), "a key press switches the prompts back to keyboard")
	title.queue_free()
	await ticks(2)


# ---- spectating: after you finish a race you can watch the racers still running ----------------
func test_zg_race_spectate_after_finish() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	check(Net.host(24597) == OK, "hosting a race with two other racers")
	Net.roster[2] = {"name": "Ada", "color": 1, "cp": 3, "finished": -1.0, "cp_at": 0.0}
	Net.roster[3] = {"name": "Bo", "color": 2, "cp": 1, "finished": -1.0, "cp_at": 0.0}
	Game.level_index = 0
	Game.race_mode = true
	Net.race_start_time = Net.now() - 1.0
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var far: Vector3 = lvl.player.global_position + Vector3(0, 6, -40)
	lvl._on_racer_pose(2, far, Vector3(0, 0, -8), true, 0)
	lvl._on_racer_pose(3, far + Vector3(20, 0, 0), Vector3.ZERO, true, 0)
	check(not lvl.spectate(1), "no spectating before you finish")
	lvl._on_finish()
	var btn: Button = null
	for n: Node in lvl.hud._results.find_children("*", "Button", true, false):
		if (n as Button).text.begins_with("Spectate"):
			btn = n as Button
	check(btn != null and btn.visible, "race results offer Spectate while others still race")
	await real_seconds(1.1)
	check(get_viewport().gui_get_focus_owner() == btn, "Spectate is focused first for keyboard / pad")
	btn.pressed.emit()
	await ticks(3)
	check(lvl.spectating_id == 2 and lvl.camera.follow == lvl._ghosts[2] and not lvl.hud._results.visible and lvl.hud._spec_bar.visible,
		"Spectate follows the first racer, hides the results and shows the spectate bar")
	check(lvl.hud._spec_name.text == "Ada" and lvl.hud._spec_hint.text.contains("Stage 4 /"), "the bar names the racer and their stage (%s)" % lvl.hud._spec_hint.text)
	await ticks(10)
	check(lvl.camera.global_position.distance_to(far) < 14.0, "the camera orbits the watched racer (%.1f m away)" % lvl.camera.global_position.distance_to(far))
	# RB on a pad, press and release a frame apart
	var rb := InputEventJoypadButton.new()
	rb.device = 0
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	Input.parse_input_event(rb)
	await get_tree().process_frame
	var rb_up: InputEventJoypadButton = rb.duplicate()
	rb_up.pressed = false
	Input.parse_input_event(rb_up)
	await ticks(2)
	check(lvl.spectating_id == 3, "RB switches to the next racer")
	var q := InputEventAction.new()
	q.action = "spectate_prev"
	q.pressed = true
	lvl._unhandled_input(q)
	check(lvl.spectating_id == 2, "LB / Q goes back (wrapping)")
	Net._apply_finished(2, 55.0)
	await ticks(2)
	check(lvl.spectating_id == 3 and lvl.camera.follow == lvl._ghosts[3], "when the watched racer finishes, the camera moves to one still running")
	var b := InputEventAction.new()
	b.action = "ui_cancel"
	b.pressed = true
	lvl._unhandled_input(b)
	await ticks(2)
	check(lvl.spectating_id == -1 and lvl.camera.follow == null and lvl.hud._results.visible and not lvl.hud._spec_bar.visible,
		"B / Esc returns to the results panel")
	check(get_viewport().gui_get_focus_owner() == btn, "and focus lands back on Spectate")
	var rb2 := InputEventAction.new()
	rb2.action = "spectate_next"
	rb2.pressed = true
	lvl._unhandled_input(rb2)
	check(lvl.spectating_id == 3, "RB from the results panel starts spectating directly")
	Net._apply_finished(3, 61.0)
	await ticks(2)
	check(lvl.spectating_id == -1 and lvl.hud._results.visible and not btn.visible, "once everyone is in, spectating ends and the button goes away")
	Net.leave()
	Game.race_mode = false
	world.queue_free()
	world = null
	await ticks(2)


# ---- Party Mode -----------------------------------------------------------------------------------

## Loads a level as Party Practice (item boxes, dummies) and waits for the layer to place them.
func _load_practice(index: int) -> LevelBase:
	Game.party = PartyRules.new("practice")
	var lvl: LevelBase = await load_level(index)
	await ticks(4)
	return lvl


## Stands the player `dist` m in front of a dummy, facing it, on the dummy's lawn.
func _face_dummy(lvl: LevelBase, d: PracticeDummy, dist: float = 1.6) -> void:
	# stand on the dummy's front side (dummies face -Z of their rotation), facing it
	var fwd: Vector3 = Vector3(0, 0, -1).rotated(Vector3.UP, d.rotation.y)
	var at: Vector3 = d.home + fwd * dist
	lvl.player.teleport(Transform3D(Basis.looking_at(d.home - at, Vector3.UP), at + Vector3(0, 0.1, 0)))
	_aim(lvl, atan2(-(d.home - at).x, -(d.home - at).z))
	await ticks(3)


## Points the camera (and so the player's aim) at `yaw`: the OrbitCamera writes camera_yaw.
func _aim(lvl: LevelBase, yaw: float) -> void:
	lvl.player.camera_yaw = yaw
	if lvl.camera != null:
		lvl.camera.yaw = yaw


## Presses the party's Attack for `hold` seconds (0 = a tap).
func _attack(p: PartyLayer, hold: float = 0.0) -> void:
	p.cmd_attack = true
	await ticks(maxi(1, int(hold * 120.0)))
	p.cmd_attack = false
	await ticks(2)


func test_zp_practice_core_loop() -> void:
	var lvl: LevelBase = await _load_practice(0)
	var p: PartyLayer = lvl.party
	check(p != null and p.practice, "Party Practice adds the party layer to the level")
	if p == null:
		return
	p.use_device_input = false
	lvl.player.use_device_input = false
	check(p.boxes.size() >= 3 * (lvl.checkpoints.size() + 1) - 2, "item boxes are placed across the start and every checkpoint lawn (%d boxes, %d checkpoints)" % [p.boxes.size(), lvl.checkpoints.size()])
	check(p.dummies.size() >= 2, "practice dummies stand on the lawns (%d)" % p.dummies.size())
	# every box sits on solid ground
	var grounded: int = 0
	for b: ItemBox in p.boxes:
		var q := PhysicsRayQueryParameters3D.create(b.global_position, b.global_position + Vector3(0, -2.0, 0), 1)
		if not lvl.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			grounded += 1
	check(grounded == p.boxes.size(), "every item box floats just above solid ground (%d/%d)" % [grounded, p.boxes.size()])
	# run through the first box
	var box: ItemBox = p.boxes[0]
	lvl.player.teleport(Transform3D(Basis(), box.global_position - Vector3(0, 1.1, 0)))
	await ticks(3)
	check(p.item == "fox" and not box.available, "touching a box pops it and fills the slot (practice hands out the Nine-Tailed Fox first: %s)" % p.item)
	await seconds(PartyLayer.BOX_RESPAWN + 0.3)
	check(box.available, "the box respawns after %.0f s" % PartyLayer.BOX_RESPAWN)
	# step off the box row so the next box doesn't refill the slot at once
	lvl.player.teleport(Transform3D(Basis(), box.global_position + Vector3(0, -1.1, 6.0)))
	await ticks(2)
	# transform
	var pu: PowerUp = p.activate_item()
	await ticks(2)
	check(pu != null and p.transformation() == pu and p.item == "", "using the item transforms the player")
	check(is_equal_approx(lvl.player.speed_mult, 1.6) and is_equal_approx(lvl.player.jump_mult, 1.35), "the fox runs x1.6 and jumps x1.35 (%.2f, %.2f)" % [lvl.player.speed_mult, lvl.player.jump_mult])
	# claw a dummy
	var d: PracticeDummy = p.dummies[0]
	await _face_dummy(lvl, d, 1.8)
	await _attack(p)
	check(d.hits == 1 and d.knocked_out and d.last_src == "claw", "the Fox Claw KOs a practice dummy (hits %d, ko %s)" % [d.hits, d.knocked_out])
	await seconds(2.0)
	check(not d.knocked_out, "a KO'd dummy pops back home")
	# charge and fire a Tailed Beast Bomb at it from further back
	await _face_dummy(lvl, d, 7.0)
	var before: int = d.hits
	await _attack(p, 1.3)
	await seconds(0.8)
	check(d.hits > before and d.last_src == "beast_bomb", "a charged Tailed Beast Bomb blasts the dummy (%s)" % d.last_src)
	pu.finish()
	await ticks(3)
	check(p.actives.is_empty() and is_equal_approx(lvl.player.speed_mult, 1.0) and is_equal_approx(lvl.player.jump_mult, 1.0), "when it ends the movement multipliers are restored")
	Game.party = null



## Clears powers, statuses, the slot and resets a dummy between power-up checks.
func _party_fresh(p: PartyLayer, d: PracticeDummy) -> void:
	p.end_all_powers()
	p.clear_statuses()
	p.item = ""
	p.cmd_attack = false
	p.cmd_use = false
	p.cmd_cycle = false
	await ticks(2)
	d.reset()
	await ticks(2)


## Gives and uses one item; returns the PowerUp (freed at once for instant items).
func _use_item(p: PartyLayer, id: String) -> PowerUp:
	p.give_item(id)
	var pu: PowerUp = p.activate_item()
	await ticks(2)
	return pu


func test_zp_every_power_up() -> void:
	var lvl: LevelBase = await _load_practice(0)
	var p: PartyLayer = lvl.party
	if p == null or p.dummies.is_empty():
		check(false, "practice layer with dummies")
		return
	p.use_device_input = false
	lvl.player.use_device_input = false
	var pl: Player = lvl.player
	var d: PracticeDummy = p.dummies[0]
	var mods := func() -> Vector3: return Vector3(pl.speed_mult, pl.jump_mult, pl.gravity_mult)
	var restored := func() -> bool: return mods.call() == Vector3.ONE and pl.party_air_jumps == 0

	# Hero's Tunic: blade combo, spin attack, and each tool
	await _party_fresh(p, d)
	var tunic: PowerUp = await _use_item(p, "tunic")
	check(mods.call().is_equal_approx(Vector3(1.15, 1.1, 1.0)), "Hero's Tunic: x1.15 speed, x1.1 jump (%s)" % mods.call())
	await _face_dummy(lvl, d, 1.8)
	await _attack(p)
	check(d.hits == 1 and d.last_src == "blade", "Hero's Tunic: a Legend Blade slash knocks the dummy (%s)" % d.last_src)
	d.reset()
	await _face_dummy(lvl, d, 2.2)
	await _attack(p, 1.0)
	check(d.last_src == "spin", "Hero's Tunic: holding Attack charges a Spin Attack (%s)" % d.last_src)
	for tool: int in 3:
		d.reset()
		(tunic as Object).set("tool", tool)
		(tunic as Object).set("_tool_cd", 0.0)
		await _face_dummy(lvl, d, 6.0)
		var h0: int = d.hits
		p.cmd_use = true
		await ticks(2)
		p.cmd_use = false
		await seconds(1.2)
		var tname: String = ["boomerang", "hookshot", "bombs"][tool]
		check(d.hits > h0 and d.last_src == tname, "Hero's Tunic: the %s hits the dummy (%s)" % [tname, d.last_src])
	p.cmd_cycle = true
	await ticks(2)
	p.cmd_cycle = false
	await ticks(2)
	check(int((tunic as Object).get("tool")) == 0, "Hero's Tunic: Cycle switches to the next tool")
	tunic.finish()
	await ticks(3)
	check(restored.call(), "Hero's Tunic: multipliers restored when it ends")

	# Golden Surge Hair: double jump, dash punch, Energy Wave
	await _party_fresh(p, d)
	var surge: PowerUp = await _use_item(p, "surge")
	check(mods.call().is_equal_approx(Vector3(1.4, 1.2, 1.0)) and pl.party_air_jumps == 1, "Golden Surge Hair: x1.4 speed, x1.2 jump, a double jump (%s, %d)" % [mods.call(), pl.party_air_jumps])
	await _face_dummy(lvl, d, 3.0)
	await _attack(p)
	await ticks(20)
	check(d.last_src == "dash_punch", "Golden Surge Hair: the Dash Punch connects (%s)" % d.last_src)
	d.reset()
	await _face_dummy(lvl, d, 9.0)
	await _attack(p, 1.6)
	await ticks(3)
	check(d.last_src == "wave", "Golden Surge Hair: a charged Energy Wave blasts the dummy (%s)" % d.last_src)
	surge.finish()
	await ticks(3)
	check(restored.call(), "Golden Surge Hair: multipliers and the double jump end with it")

	# instant items aimed at a dummy in front
	var aimed: Dictionary = {"glove": [4.0, "glove"], "shrink": [8.0, "shrink"], "ice": [8.0, "ice"], "gravity": [7.0, "gravity"]}
	for id: String in aimed:
		await _party_fresh(p, d)
		await _face_dummy(lvl, d, float(aimed[id][0]))
		await _use_item(p, id)
		await seconds(1.3)
		check(d.hits >= 1 and d.last_src == str(aimed[id][1]), "%s hits the dummy (%s)" % [PartyNames.item_name(id), d.last_src])
		match id:
			"shrink":
				check(d.shrunk > 0.0, "Shrink Ray: the dummy is shrunk")
			"ice":
				check(d.frozen > 0.0, "Ice Beam: the dummy is frozen solid")
			"gravity":
				check(d.floating > 0.0, "Gravity Bomb: the dummy floats helplessly")
		check(restored.call(), "%s leaves the multipliers at 1" % PartyNames.item_name(id))

	# Thunder Cloud zaps dummies ahead
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 5.0)
	await _use_item(p, "thunder")
	check(d.last_src == "thunder" and d.stunned > 0.0, "Thunder Cloud strikes the dummy (%s)" % d.last_src)

	# Slick Puddle: dropped behind us, onto the dummy standing there
	await _party_fresh(p, d)
	var fwd: Vector3 = Vector3(0, 0, -1).rotated(Vector3.UP, d.rotation.y)
	var at: Vector3 = d.home + fwd * 1.8
	pl.teleport(Transform3D(Basis.looking_at(fwd, Vector3.UP), at + Vector3(0, 0.1, 0)))
	await ticks(3)
	await _use_item(p, "slick")
	await seconds(0.6)
	check(d.last_src == "slick", "Slick Puddle: the dummy behind us slips in it (%s)" % d.last_src)
	check(p.hazards.is_empty(), "the puddle is used up by the slip")

	# Mega Magnet drags the dummy closer
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 6.0)
	var gap0: float = Vector2(d.global_position.x - pl.global_position.x, d.global_position.z - pl.global_position.z).length()
	var mag: PowerUp = await _use_item(p, "magnet")
	await seconds(0.8)
	var gap1: float = Vector2(d.global_position.x - pl.global_position.x, d.global_position.z - pl.global_position.z).length()
	check(d.last_src == "magnet" and gap1 < gap0 - 1.0, "Mega Magnet drags the dummy in (%.1f -> %.1f m)" % [gap0, gap1])
	mag.finish()
	await ticks(3)

	# Swap Warp trades places with the nearest dummy
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 4.0)
	var mine: Vector3 = pl.global_position
	var tgt: Dictionary = p.target_ahead()
	var theirs: Vector3 = (tgt["node"] as PracticeDummy).global_position if not tgt.is_empty() else Vector3.ZERO
	await _use_item(p, "swap")
	await ticks(3)
	check(not tgt.is_empty() and pl.global_position.distance_to(theirs) < 1.0 and (tgt["node"] as PracticeDummy).global_position.distance_to(mine) < 1.5, "Swap Warp: we and the dummy trade places")

	# Balloon Shield soaks a hit
	await _party_fresh(p, d)
	var bal: PowerUp = await _use_item(p, "balloon")
	pl.velocity = Vector3.ZERO
	var deaths0: int = lvl.deaths
	p._on_hit(77, {"kb": [0, 20, 0], "st": 1.0, "ko": true, "s": "test"})
	await ticks(2)
	check(bal.ended and pl.velocity.y < 5.0 and lvl.deaths == deaths0 and pl.party_stun <= 0.0, "Balloon Shield: the next hit - even a KO - is absorbed")

	# Jetpack: launch, low gravity, thrust while Jump is held
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 6.0)
	var jet: PowerUp = await _use_item(p, "jetpack")
	check(pl.velocity.y > 8.0 and is_equal_approx(pl.gravity_mult, 0.5), "Jetpack: a burst up and half gravity (vy %.1f, g x%.2f)" % [pl.velocity.y, pl.gravity_mult])
	pl.cmd_jump = true
	await seconds(0.5)
	pl.cmd_jump = false
	check(float((jet as Object).get("fuel")) < 2.0, "Jetpack: holding Jump burns fuel for thrust")
	jet.finish()
	await ticks(3)
	check(restored.call(), "Jetpack: gravity restored when it ends")
	await seconds(1.5)

	# Tornado wanders off and flings a dummy it catches
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 3.0)
	await _use_item(p, "tornado")
	var tn: PartyTornado = null
	for h: Variant in p.hazards.values():
		if h is PartyTornado:
			tn = h
	check(tn != null, "Tornado: a tornado spins up")
	if tn != null:
		await seconds(0.5)
		d.global_position = tn.global_position
		d.home = d.global_position
		await ticks(4)
		check(d.last_src == "tornado" and d.vel.y > 5.0, "Tornado: it flings the dummy it catches (%s)" % d.last_src)
	check(restored.call(), "no power-up leaves a multiplier behind")
	Game.party = null


func test_zp_main_mode_stays_pure() -> void:
	Game.party = null
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	check(lvl.party == null and lvl.find_children("*", "PartyLayer", true, false).is_empty(), "the main mode adds no party layer")
	check(lvl.find_children("*", "ItemBox", true, false).is_empty() and lvl.find_children("*", "PracticeDummy", true, false).is_empty(), "no item boxes or dummies in the main mode")
	var pl: Player = lvl.player
	check(pl.speed_mult == 1.0 and pl.jump_mult == 1.0 and pl.gravity_mult == 1.0 and pl.party_air_jumps == 0 and pl.party_stun == 0.0, "the main mode's movement multipliers stay 1.0")
	# party buttons do nothing in the main mode
	Input.action_press("attack")
	Input.action_press("use_item")
	await ticks(6)
	Input.action_release("attack")
	Input.action_release("use_item")
	check(pl.speed_mult == 1.0 and lvl.find_children("*", "PowerUp", true, false).is_empty(), "Attack / Use do nothing outside Party Mode")


func test_zp_scoring_rules() -> void:
	check(PartyRules.placement_points(1) == 10 and PartyRules.placement_points(2) == 8 and PartyRules.placement_points(8) == 1 and PartyRules.placement_points(9) == 0 and PartyRules.placement_points(0) == 0, "placement points 10/8/.../1, 0 beyond 8th or unfinished")
	check(PartyRules.ko_credit(5, 10.0, 13.9) == 5 and PartyRules.ko_credit(5, 10.0, 14.1) == 0 and PartyRules.ko_credit(0, 10.0, 11.0) == 0, "a fall within 4 s of a hit is the hitter's KO")
	var rows: Array[Dictionary] = PartyRules.score_round([3, 1], [1, 2, 3], {2: 2, 1: 1}, {3: 1})
	var by: Dictionary = {}
	for r: Dictionary in rows:
		by[int(r["id"])] = r
	check(int(by[3]["total"]) == 12 and int(by[1]["total"]) == 11 and int(by[2]["total"]) == 6, "round totals: place + 3 per KO + 2 per bonus (%d, %d, %d)" % [int(by[3]["total"]), int(by[1]["total"]), int(by[2]["total"])])
	check(int(by[2]["place"]) == 0 and int(by[2]["place_pts"]) == 0 and int(by[2]["ko_pts"]) == 6, "an unfinished racer keeps KO points but gets no placement points")
	check(int(rows[0]["id"]) == 3, "rows are sorted best first")
	check(not PartyRules.round_over([-1.0, -1.0], 100.0), "the round runs until someone finishes")
	check(not PartyRules.round_over([30.0, -1.0], 74.0) and PartyRules.round_over([30.0, -1.0], 75.0), "the round ends 45 s after the first finisher")
	check(PartyRules.round_over([30.0, 40.0], 41.0), "the round ends when everyone is home")
	var teams: Dictionary = PartyRules.balance_teams([4, 1, 3, 2, 5])
	var sizes: Array[int] = [0, 0]
	for id: Variant in teams:
		sizes[int(teams[id])] += 1
	check(absi(sizes[0] - sizes[1]) <= 1 and teams.size() == 5, "teams are balanced (%d vs %d)" % [sizes[0], sizes[1]])
	check(PartyRules.smaller_team({1: 0, 2: 0, 3: 1}) == 1 and PartyRules.smaller_team({1: 0, 2: 1}) == 0, "a newcomer joins the smaller team")
	var pts: Dictionary = {1: 10, 2: 8, 3: 6, 4: 5}
	var tm: Dictionary = {1: 0, 2: 1, 3: 1, 4: 0}
	check(PartyRules.team_totals(pts, tm) == [15, 14] and PartyRules.winning_team(pts, tm) == 0, "team score = sum of its members")
	check(PartyRules.winning_team({1: 5, 2: 5}, {1: 0, 2: 1}) == -1, "equal team totals are a draw")
	var cup := PartyRules.new("team")
	cup.names = {1: "A", 2: "B"}
	cup.teams = {1: 0, 2: 1}
	cup.add_round(PartyRules.score_round([1, 2], [1, 2], {}, {}))
	cup.add_round(PartyRules.score_round([2, 1], [1, 2], {1: 1}, {}))
	check(int(cup.cup[1]) == 21 and int(cup.cup[2]) == 18, "the cup adds rounds up (%s)" % str(cup.cup))
	var back := PartyRules.new("team")
	back.cup_from_wire(JSON.parse_string(JSON.stringify(cup.cup_to_wire())))
	check(int(back.cup[1]) == 21 and str(back.names[2]) == "B" and int(back.teams[2]) == 1, "the cup survives the wire (JSON) intact")
	var wired: Array[Dictionary] = PartyRules.rows_from_wire(JSON.parse_string(JSON.stringify(rows)))
	check(wired.size() == 3 and int(wired[0]["total"]) == 12, "round rows survive the wire (JSON) intact")


func test_zp_item_roll_weighting() -> void:
	var lead: Dictionary = {}
	var last: Dictionary = {}
	for i: int in 1000:
		var r: float = (float(i) + 0.5) / 1000.0
		var a: String = PartyItems.roll(0.0, r)
		var b: String = PartyItems.roll(1.0, r)
		lead[a] = int(lead.get(a, 0)) + 1
		last[b] = int(last.get(b, 0)) + 1
	var wild := func(t: Dictionary) -> int: return int(t.get("fox", 0)) + int(t.get("tunic", 0)) + int(t.get("surge", 0))
	check(wild.call(last) > wild.call(lead) * 4, "the back of the pack rolls far more transformations (%d vs %d per 1000)" % [wild.call(last), wild.call(lead)])
	check(not lead.has("swap") and not lead.has("thunder"), "the leader never rolls Swap Warp or Thunder Cloud")
	check(int(lead.get("balloon", 0)) > int(last.get("balloon", 0)), "the leader gets more defensive items")
	var every: bool = true
	for id: String in PartyItems.PRACTICE_ORDER:
		if not lead.has(id) and not last.has(id):
			every = false
		if PartyItems.script_for(id) == null or PartyNames.item_name(id) == id:
			every = false
	check(every and PartyItems.PRACTICE_ORDER.size() >= 13, "every item can roll and has a script and a display name (%d items)" % PartyItems.PRACTICE_ORDER.size())
	check(PartyItems.place_fraction(1, 4) == 0.0 and PartyItems.place_fraction(4, 4) == 1.0, "race place maps to 0 (leader) .. 1 (last)")


## Presses a pad button (or key) like a real device: press, a frame, release.
func _zp_press(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up: InputEvent = ev.duplicate()
	if up is InputEventJoypadMotion:
		(up as InputEventJoypadMotion).axis_value = 0.0
	else:
		up.set("pressed", false)
	Input.parse_input_event(up)
	await ticks(2)


func _zp_pad(button: JoyButton) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.device = 2
	b.button_index = button
	b.pressed = true
	return b


func _focused_text() -> String:
	var f: Control = get_viewport().gui_get_focus_owner()
	return (f as Button).text if f is Button else ("<%s>" % f.get_class() if f != null else "")


func test_zp_party_menus_pad() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	title.call("show_screen", "main")
	await ticks(3)
	var e0: int = trap.count()
	# main menu -> Party Practice with the pad
	var found: bool = false
	for i: int in 8:
		if _focused_text() == PartyNames.mode_name("practice"):
			found = true
			break
		await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(found, "the D-pad reaches Party Practice on the main menu")
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(3)
	check(Game.title_screen == "practice", "A opens the Party Practice screen")
	check(_focused_text().begins_with("1 "), "the first course is focused (%s)" % _focused_text())
	var first: String = _focused_text()
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(_focused_text() != first and _focused_text() != "", "the D-pad moves through the course list (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_B))
	await ticks(3)
	check(Game.title_screen == "main" and _focused_text() == PartyNames.mode_name("practice"), "B goes back, onto the Party Practice button (%s)" % _focused_text())
	# the lobby's mode picker and team rows
	check(Net.host(24597) == OK, "hosting opens the lobby")
	await ticks(3)
	var pick: Array[Node] = title.find_children("*", "OptionButton", true, false)
	check(Game.title_screen == "lobby" and pick.size() >= 1, "the host's lobby offers a game-mode picker")
	Net.host_set_mode("team")
	await ticks(3)
	var labels: String = ""
	for l: Node in title.find_children("*", "Label", true, false):
		labels += (l as Label).text + "|"
	check(labels.contains("[%s]" % PartyNames.team_name(0)) and labels.contains(PartyNames.mode_name("team")), "Team Party lists racers by team")
	Net.host_set_mode("party")
	await ticks(2)
	check(Net.game_mode == "party" and Net.teams.is_empty(), "switching to Party clears the teams")
	Net.leave()
	await ticks(2)
	title.queue_free()
	await ticks(2)
	check(trap.count() == e0, ("party menus build without errors %s" % trap.since(e0)).strip_edges())

	# Party Practice clear panel: focused, pad-navigable
	var lvl: LevelBase = await _load_practice(0)
	var p: PartyLayer = lvl.party
	p.on_local_finish(42.0)
	await seconds(1.6)
	check(p.results != null and p.hud.has_panel() and _focused_text() == "Run It Again", "the practice results panel opens focused on Run It Again (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(_focused_text() == "Next Course", "the D-pad moves to Next Course (%s)" % _focused_text())

	# a round results panel (a guest's view): scores, cup, focus on its button
	var rows: Array[Dictionary] = PartyRules.score_round([1], [1, 7], {1: 1}, {})
	p.rules.add_round(rows)
	p.last_rows = rows
	p.show_results()
	await seconds(0.9)
	check(p.results.find_children("*", "Label", true, false).size() > 10 and _focused_text() == "Leave Party", "the round results panel builds and focuses its button (%s)" % _focused_text())
	Game.party = null


func test_zp_party_controls_rebind() -> void:
	var keep: Dictionary = Settings.party_binds.duplicate(true)
	Settings.party_binds = {}
	Game.apply_party_binds()
	var pc := PartyControls.new()
	add_child(pc)
	await ticks(2)
	var b: Button = pc.find_child("Bind_attack", true, false) as Button
	check(b != null and b.text.contains("F") and b.text.contains("X"), "the Attack button shows its key and pad bindings (%s)" % (b.text if b != null else ""))
	b.grab_focus()
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(_focused_text().begins_with("Shove"), "the D-pad moves between the bindings (%s)" % _focused_text())
	b.grab_focus()
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(2)
	check(pc.capturing == "attack", "A starts listening for a new Attack input")
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.keycode = KEY_SPACE
	space.pressed = true
	await _zp_press(space)
	check(pc.capturing == "attack" and int(Game.party_bind("attack")["key"]) == KEY_F, "Space (jump) is refused")
	var g := InputEventKey.new()
	g.physical_keycode = KEY_G
	g.keycode = KEY_G
	g.pressed = true
	await _zp_press(g)
	check(pc.capturing == "" and int(Game.party_bind("attack")["key"]) == KEY_G, "G becomes the Attack key")
	var probe := InputEventKey.new()
	probe.physical_keycode = KEY_G
	check(InputMap.event_is_action(probe, "attack"), "the input map follows the new binding")
	# a pad button another party action had moves over to this one
	pc.find_child("Bind_attack", true, false).call("grab_focus")
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(2)
	await _zp_press(_zp_pad(JOY_BUTTON_RIGHT_SHOULDER))
	check(int(Game.party_bind("attack")["pad"]) == JOY_BUTTON_RIGHT_SHOULDER and int(Game.party_bind("use_item")["pad"]) == -1, "RB moves from Use item to Attack")
	check(Game.prompt("attack") in ["G / LMB", "RB"], "prompts show the new binding (%s)" % Game.prompt("attack"))
	# Start cancels a capture
	pc.find_child("Bind_shove", true, false).call("grab_focus")
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(2)
	await _zp_press(_zp_pad(JOY_BUTTON_START))
	check(pc.capturing == "" and int(Game.party_bind("shove")["pad"]) == JOY_BUTTON_B, "Start cancels without changing anything")
	(pc.find_child("ResetBinds", true, false) as Button).pressed.emit()
	await ticks(2)
	check(Settings.party_binds.is_empty() and int(Game.party_bind("attack")["key"]) == KEY_F, "Reset restores the defaults")
	pc.queue_free()
	Settings.party_binds = keep
	Game.apply_party_binds()
	await ticks(2)


func test_zp_relay_party_tunnel() -> void:
	var got: Array = []
	var cb := func(from_id: int, m: Dictionary) -> void: got.append([from_id, m])
	Net.party_message.connect(cb)
	var had: bool = Net.roster.has(5)
	if not had:
		Net.roster[5] = {"name": "Relay", "color": 0, "finished": -1.0, "cp": 0}
	# as the relay delivers it: a pose event carrying {"party": msg, "to": id}
	Net.call("_handle_relay_event", 5, "pose", {"party": {"k": "fx", "p": "glove", "a": "punch"}, "to": 0})
	Net.call("_handle_relay_event", 5, "pose", {"party": {"k": "hit"}, "to": Net.my_id()})
	Net.call("_handle_relay_event", 5, "pose", {"party": {"k": "hit"}, "to": Net.my_id() + 99})
	Net.call("_handle_relay_event", 6, "pose", {"party": {"k": "hit"}, "to": 0})
	check(got.size() == 2 and int(got[0][0]) == 5 and str((got[0][1] as Dictionary)["k"]) == "fx", "party packets ride the relay's pose event: broadcast and addressed-to-us arrive, others are dropped (%d)" % got.size())
	var poses: Array = []
	var pcb := func(id: int, _p: Vector3, _v: Vector3, _g: bool, _s: int) -> void: poses.append(id)
	Net.racer_pose.connect(pcb)
	Net.call("_handle_relay_event", 5, "pose", {"party": {"k": "fx"}, "to": 0})
	check(poses.is_empty(), "a tunnelled party packet is never mistaken for a pose")
	Net.racer_pose.disconnect(pcb)
	Net.party_message.disconnect(cb)
	if not had:
		Net.roster.erase(5)


## A dropped relay link mid-race must not end the session: the game keeps its roster and race,
## reconnects into its old slot (role=rejoin + the session token), and the room is told who is
## away / back. (The relay side is exercised against `wrangler dev`, see docs/RELAY.md.)
func test_zp_relay_resume() -> void:
	Net.leave()
	# the game's own handler would leave for the title screen (freeing this test scene)
	var game_handlers: Array = []
	for c: Dictionary in Net.left_session.get_connections():
		game_handlers.append(c["callable"])
		Net.left_session.disconnect(c["callable"])
	# a relay session in progress: we are player 3 in room ABCDEFGH, mid-race
	Net.set("_relay_mode", true)
	Net.set("_relay_host", false)
	Net.set("_relay_peer_id", 3)
	Net.set("_relay_ready", true)
	Net.set("_relay_session", "abcdef0123456789abcdef01")
	Net.active = true
	Net.in_race = true
	Net.room_code = "ABCDEFGH"
	Net.roster = {1: {"name": "Host", "color": 0, "cp": 2, "finished": -1.0}, 3: {"name": "Me", "color": 1, "cp": 1, "finished": -1.0}}
	var seen: Array = [0, 0, []]
	var on_int := func(_d: String) -> void: seen[0] += 1
	var on_back := func() -> void: seen[1] += 1
	var on_note := func(text: String) -> void: (seen[2] as Array).append(text)
	Net.connection_interrupted.connect(on_int)
	Net.connection_restored.connect(on_back)
	Net.relay_notice.connect(on_note)
	Net.call("_begin_resume", "close code 1006")
	check(Net.is_reconnecting() and Net.active and Net.in_race and Net.roster.size() == 2 and int(seen[0]) == 1,
		"a dropped link starts reconnecting and keeps the session (roster, race)")
	# the relay welcomes us back into the same slot: nothing is reset, no re-register
	Net.call("_handle_relay_packet", JSON.stringify({"type": "welcome", "id": 3, "room": "ABCDEFGH", "resumed": true}))
	check(not Net.is_reconnecting() and bool(Net.get("_relay_ready")) and Net.my_id() == 3 and Net.roster.size() == 2
		and int(Net.roster[1]["cp"]) == 2 and int(seen[1]) == 1, "the welcome back restores the link without resetting anything")
	# others dropping / returning are announced by name
	Net.call("_handle_relay_packet", JSON.stringify({"type": "host_away"}))
	Net.call("_handle_relay_packet", JSON.stringify({"type": "host_back"}))
	check((seen[2] as Array).size() == 2 and str((seen[2] as Array)[0]).contains("host"), "the host dropping and returning is announced")
	# a rejoin the relay refuses ends the session with a clear reason
	var left: Array = [""]
	var on_left := func(reason: String) -> void: left[0] = reason
	Net.left_session.connect(on_left)
	Net.call("_begin_resume", "close code 1006")
	Net.call("_handle_relay_packet", JSON.stringify({"type": "error", "reason": "Could not resume that session."}))
	check(not Net.active and str(left[0]).contains("could not rejoin"), "a refused rejoin leaves the session with the reason")
	# the resume window running out gives up the same way
	Net.set("_relay_mode", true)
	Net.set("_relay_ready", true)
	Net.active = true
	left[0] = ""
	Net.call("_begin_resume", "no reply from the relay for 45 s")
	Net.set("_relay_resume_left", 0.01)
	Net.call("_process_relay", 0.05)
	check(not Net.active and str(left[0]).contains("could not reconnect"), "an expired resume window leaves the session")
	check(str(Net.get("_relay_session")) == "", "leaving forgets the session token")
	Net.connection_interrupted.disconnect(on_int)
	Net.connection_restored.disconnect(on_back)
	Net.relay_notice.disconnect(on_note)
	Net.left_session.disconnect(on_left)
	# the pose stream: at most 15 a second, and only a heartbeat while standing still
	Net.set("_pose_last_at", -100.0)
	Net.set("_pose_last_seq", -1)
	var sent: Array = [0]
	var t0: float = Net.call("_local_time")
	var pos := Vector3.ZERO
	while float(Net.call("_local_time")) - t0 < 1.0:
		var before: float = Net.get("_pose_last_at")
		pos += Vector3(0.1, 0, 0)
		Net.send_pose(pos, Vector3(6, 0, 0), true)
		if float(Net.get("_pose_last_at")) != before:
			sent[0] += 1
		await get_tree().process_frame
	check(int(sent[0]) >= 12 and int(sent[0]) <= 16, "a moving racer sends about 15 poses a second (%d)" % int(sent[0]))
	sent[0] = 0
	t0 = Net.call("_local_time")
	while float(Net.call("_local_time")) - t0 < 1.5:
		var before2: float = Net.get("_pose_last_at")
		Net.send_pose(pos, Vector3.ZERO, true)
		if float(Net.get("_pose_last_at")) != before2:
			sent[0] += 1
		await get_tree().process_frame
	check(int(sent[0]) <= 3, "a racer standing still only sends a heartbeat (%d in 1.5 s)" % int(sent[0]))
	Net.leave()
	for cb: Callable in game_handlers:
		Net.left_session.connect(cb)


func test_zp_party_finish_bar() -> void:
	Game.party = PartyRules.new("party")
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	var p: PartyLayer = lvl.party
	check(p != null and not p.practice, "a Party race level gets the party layer")
	if p == null:
		Game.party = null
		return
	p.on_local_finish(30.0)
	await ticks(3)
	var bar: Node = p.hud.find_child("FinishBar", true, false)
	check(bar != null and not p.hud.has_panel(), "finishing before the round ends shows a small waiting bar, not a full panel")
	check((bar != null and bar.find_child("Spectate", true, false) != null) == not lvl.spectate_candidates().is_empty(), "it offers Spectate exactly when someone is still racing to watch")
	var watched: Array = [0]
	p.hud.show_finished(2, true, func() -> void: watched[0] += 1)
	await ticks(3)
	var f: Control = get_viewport().gui_get_focus_owner()
	check(f != null and f.name == "Spectate", "the Spectate button takes the pad focus")
	var a := InputEventJoypadButton.new()
	a.device = 2
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	Input.parse_input_event(a)
	await get_tree().process_frame
	var up: InputEventJoypadButton = a.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await ticks(3)
	check(int(watched[0]) == 1, "A on Spectate starts watching")
	p.hud.show_round_over()
	await ticks(2)
	check(p.hud.find_child("FinishBar", true, false) == null or (p.hud.find_child("FinishBar", true, false) as Node).is_queued_for_deletion(), "the bar goes when the round ends")
	Game.party = null


# ---- soundscapes --------------------------------------------------------------------------------

## Every map's ambience (sound/soundscape.gd): its bed (and second layer) load as looping Ogg and
## play on the Ambience bus through the pause, every scheduled one-shot has clips and plays in 3D
## on the Ambience bus, and every second layer (the reef's deep, the xeno jungle's depths, the
## volcano's crater, the glacier's blizzard, the desert's sandstorm, the manor's bell tower, the
## armada's flagship, the candy clouds, the carrier's island, the sakura keep, the jungle pyramid's
## top, the frontier train's engine, the neon spire, the doom reactor core, the abyss wreck, the
## tempest spire, the void's fracture, the Ascent's summit wind) takes over as the course runs out.
func test_zs_soundscapes() -> void:
	var unscored: Array[String] = []
	for lv: Dictionary in Game.LEVELS:
		if not Soundscape.THEMES.has(str(lv["id"])):
			unscored.append(str(lv["id"]))
	check(unscored.is_empty(), "every map has a soundscape %s" % str(unscored))
	await new_world()
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	for theme: String in Soundscape.THEMES:
		var spec: Dictionary = Soundscape.THEMES[theme]
		var s: Soundscape = Soundscape.make(theme)
		s.progress_override = 0.0
		world.add_child(s)
		await ticks(2)
		var beds: Array[AudioStreamPlayer] = [s.bed_player()]
		if spec.has("layer"):
			beds.append(s.layer_player())
		for bed: AudioStreamPlayer in beds:
			var ogg: AudioStreamOggVorbis = bed.stream as AudioStreamOggVorbis if bed != null else null
			check(ogg != null and ogg.loop and ogg.get_length() >= 45.0, "%s: bed %s loads as a looping Ogg of 45 s or more" % [theme, bed.name if bed != null else "?"])
			check(bed != null and bed.playing and bed.bus == &"Ambience" and bed.process_mode == Node.PROCESS_MODE_ALWAYS, "%s: bed %s plays on the Ambience bus and keeps playing while paused" % [theme, bed.name if bed != null else "?"])
		var events: Array = spec["events"]
		for i: int in events.size():
			check(s.play_event(i, false), "%s: one-shot %s has clips and plays" % [theme, events[i]["clip"]])
		var on_bus: int = 0
		for n: Node in s.get_children():
			if n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).playing and (n as AudioStreamPlayer3D).bus == &"Ambience":
				on_bus += 1
		check(on_bus == mini(events.size(), Soundscape.POOL_SIZE) and s.active_one_shots() == on_bus, "%s: the one-shots sound in 3D on the Ambience bus (%d)" % [theme, on_bus])
		check(s.process_mode == Node.PROCESS_MODE_INHERIT, "%s: the one-shot schedule pauses with the game" % theme)
		if spec.has("layer"):
			s.set("_fade", 1.0)
			s.progress = 1.0
			s.progress_override = 1.0
			await get_tree().process_frame   # (the mix follows in _process)
			await get_tree().process_frame
			check(s.layer_player().volume_db > -1.0 and s.bed_player().volume_db <= Soundscape.SILENT_DB + 0.1, "%s: at the end of the course the %s bed has taken over (%.1f / %.1f dB)" % [theme, spec["layer"], s.bed_player().volume_db, s.layer_player().volume_db])
		s.queue_free()
		await ticks(1)
	var none: Soundscape = Soundscape.make("no_such_theme")
	world.add_child(none)
	await ticks(2)
	check(none.bed_player() == null and not none.play_event(0), "an unknown theme builds a silent soundscape")
	none.queue_free()
	cam.queue_free()
	# in a level, the layer follows checkpoint progress (levels only add it outside headless runs)
	for i: int in Game.LEVELS.size():
		if Game.LEVELS[i]["id"] != "reef":
			continue
		var lvl: LevelBase = await load_level(i)
		var rs: Soundscape = Soundscape.make(lvl.theme_id)
		lvl.add_child(rs)
		lvl.current_checkpoint = lvl.checkpoints.size()
		await get_tree().process_frame
		await get_tree().process_frame
		check(lvl.theme_id == "reef" and not lvl.checkpoints.is_empty() and rs.progress > 0.0 and rs.progress < 0.2, "reef: reaching the last checkpoint starts easing the deep bed in (progress %.3f)" % rs.progress)


## Clips the world sound code plays (a name may be a set of _1.._N variants).
const WORLD_CLIPS: Array[String] = ["wallstep", "wallkick", "mantle", "wallrun_latch", "land_heavy", "boost",
	"laser_on", "laser_off", "blink_appear", "blink_vanish", "blink_tick", "crusher_shudder", "crusher_slam",
	"crusher_rise", "piston_fire", "piston_clank", "piston_retract", "sweep_whoosh", "pendulum_whoosh",
	"warp_whoosh", "prop_bonk", "platform_reform", "ladle_tip", "ladle_splash", "ladle_hiss", "jelly_bounce",
	"vent_rumble", "vent_burst", "thruster_ignite", "thruster_cough", "thruster_cutoff", "flare_alarm",
	"flare_launch", "gravity_on", "gravity_off", "escape_tick", "escape_tock", "trolley_clunk",
	"counterweight_thud", "billboard_on", "billboard_off", "billboard_glitch", "data_chirp", "data_zip",
	"spore_boing", "snapjaw_snap", "snapjaw_open", "geyser_erupt", "leviathan_call",
	"bomb_launch", "bomb_whistle", "bomb_impact", "basalt_sink", "crust_crack", "crust_break", "eruption_boom",
	"icicle_crack", "icicle_fall", "icicle_shatter", "gust_whoosh", "ice_crack", "ice_break", "avalanche_rumble",
	"snow_thump", "spike_trap", "spike_retract", "quicksand_sink", "mirage_shimmer", "boulder_impact", "stone_grind",
	"manor_phantom_waver", "manor_phantom_form", "manor_phantom_fade", "manor_gaze_open", "manor_chain_creak",
	"manor_board_creak", "manor_board_snap", "manor_coffin_slam", "manor_bell_toll", "manor_mirror_chime",
	"armada_cannon_fuse", "armada_cannon_fire", "armada_cannon_impact", "armada_swing_creak", "armada_rod_charge",
	"armada_lightning_strike", "armada_prop_spinup", "armada_mast_creak", "armada_mast_crash", "armada_ship_bell",
	"armada_salute", "candy_jelly_boing", "candy_jack_wind", "candy_jack_pop", "candy_soldier_turn",
	"candy_train_whistle", "candy_gumball_drop", "candy_gumball_splash", "candy_confetti", "candy_fireworks",
	"carrier_cat_hiss", "carrier_cat_launch", "carrier_cat_retract", "carrier_jet_spool", "carrier_wire_twang",
	"carrier_elevator_start", "carrier_elevator_stop", "carrier_door_klaxon", "carrier_door_grind",
	"carrier_launch_spool", "carrier_launch_shot", "carrier_launch_flyby", "carrier_jbd_raise", "carrier_jbd_lower",
	"carrier_lift_move", "carrier_flyover",
	"sakura_bamboo_creak", "sakura_bamboo_snap", "sakura_bell_bong", "sakura_log_whoosh", "sakura_log_thump",
	"sakura_petal_sink", "sakura_shuriken_ring", "sakura_shoji_rattle", "sakura_shoji_slam", "sakura_gust_rise",
	"sakura_gust", "sakura_mallet_creak", "sakura_ram_creak", "sakura_chime", "sakura_fireworks", "sakura_finish_bell",
	"jungle_vine_creak", "jungle_raft_bump", "jungle_dart_click", "jungle_dart_volley", "jungle_plate_click",
	"jungle_gate_open", "jungle_gate_tick", "jungle_gate_close", "jungle_trap_tick", "jungle_boulder_rumble",
	"jungle_boulder_crash", "jungle_boulder_splash", "jungle_altar",
	"neon_car_horn", "neon_drone_chirp", "neon_drone_zap", "neon_holo_glitch", "neon_holo_off", "neon_holo_on",
	"neon_checkpoint", "neon_finish",
	"frontier_fuse_light", "frontier_dynamite_boom", "frontier_signal_bell", "frontier_signal_clank", "frontier_signal_thwack",
	"frontier_timber_crack", "frontier_collapse_rebuild", "frontier_door_creak", "frontier_door_clack",
	"frontier_door_rattle", "frontier_door_slap", "frontier_steam_sputter", "frontier_steam_burst",
	"frontier_cart_clunk", "frontier_vault_open", "frontier_vault_slam", "frontier_coins", "frontier_whistle",
	"frontier_fireworks",
	"doom_press_warn", "doom_klaxon", "doom_lockdown", "doom_alarm_clear", "doom_catwalk_creak", "doom_catwalk_fall",
	"doom_pour_tilt", "doom_pour_splash", "doom_reactor_charge", "doom_reactor_pulse", "doom_vent_hiss", "doom_vent_blast",
	"doom_checkpoint", "doom_finish",
	"abyss_lamp_dim", "abyss_lamp_out", "abyss_lamp_on", "abyss_vent_rumble", "abyss_vent_burst", "abyss_angler_growl",
	"abyss_angler_snap", "abyss_anchor_creak", "abyss_shrimp_click", "abyss_leviathan_moan", "abyss_surge_whoosh",
	"abyss_checkpoint", "abyss_finish",
	"tempest_gust_rise", "tempest_gust", "tempest_rod_charge", "tempest_lightning_strike", "tempest_scaffold_creak",
	"tempest_scaffold_fall", "tempest_load_bell", "tempest_gondola_start", "tempest_crane_horn", "tempest_ram_hiss",
	"tempest_driver_hiss", "tempest_thunder", "tempest_checkpoint", "tempest_finish_strike", "tempest_beacon",
	"void_phase_warn", "void_phase_swap", "void_rift_enter", "void_tumble_warn", "void_tumble_turn", "void_tumble_thud",
	"void_collapse_start", "void_fragment_crack", "void_fragment_fall", "void_checkpoint", "void_finish"]
const WORLD_LOOPS: Array[String] = ["air_rush", "wallrun_scrape", "ice_slide", "laser_hum", "conveyor_hum",
	"wind_loop", "motor_hum", "warp_hum", "ladle_pour", "vent_loop", "surge_loop", "thruster_burn", "flare_roar",
	"gravity_hum", "scanner_servo", "trolley_run", "pulley_rattle", "trimmer_buzz", "billboard_buzz",
	"drift_hum", "lava_rise", "fumarole_loop", "lavafall_loop", "avalanche_roar", "sandfall_loop", "dustdevil_loop",
	"boulder_roll", "manor_gaze_hum", "manor_possessed_creak", "manor_waltz_box", "armada_hull_creak",
	"armada_prop_loop", "armada_winch_loop", "candy_soldier_march", "candy_train_chug", "candy_gumball_roll",
	"carrier_jet_roar", "carrier_elevator_hum",
	"sakura_shuriken_whir", "sakura_wind", "sakura_waterfall", "sakura_bridge_creak", "jungle_boulder_roll",
	"jungle_waterfall", "neon_car_hum", "neon_drone_hum", "neon_holo_hum", "neon_gondola_motor", "neon_steam_hiss",
	"neon_sign_buzz", "frontier_fuse_hiss", "frontier_collapse_rumble", "frontier_steam_hiss", "frontier_cart_rumble",
	"doom_pour_loop", "doom_reactor_hum", "doom_grate_buzz", "doom_gear_grind", "abyss_current_loop", "abyss_surge_loop",
	"tempest_wind", "tempest_trolley", "tempest_gondola_motor", "tempest_crane_slew", "void_rift_hum", "void_collapse_rumble"]


func test_z_world_sounds() -> void:
	# every map has its own footsteps and landings; anything else falls back to the plain ones
	var old_theme: String = Sfx.get("_theme")
	for th: String in ["gardens", "foundry", "balance", "clockwork", "reef", "orbital", "xeno", "volcano", "glacier", "desert",
			"manor", "armada", "candy", "carrier", "sakura", "jungle", "frontier", "neon", "doom", "abyss", "tempest", "void",
			"ascent"]:
		Sfx.set_theme(th)
		check(Sfx.themed("step") == "step_" + th and Sfx.themed("land") == "land_" + th,
			"%s has its own footsteps and landings" % th)
	Sfx.set_theme("no_such_map")
	check(Sfx.themed("step") == "step" and Sfx.themed("land") == "land", "a map without its own floor falls back to step / land")
	Sfx.set_theme(old_theme)
	var missing: Array[String] = []
	for c: String in WORLD_CLIPS + WORLD_LOOPS:
		if not Sfx.has_clip(c):
			missing.append(c)
	check(missing.is_empty(), "every world sound clip exists %s" % str(missing))
	# every clip the newer maps' scripts ask WorldAudio / Sfx for by name exists (a missing one is
	# silently skipped at runtime, so only this catches a typo). It scans whichever of these map
	# files exist, so a map whose mechanics land later (the frontier's, Doom Fortress's) is covered
	# once they do.
	var prefixes: Array[String] = ["manor", "armada", "candy", "carrier", "sakura", "jungle", "frontier", "neon",
		"doom", "abyss", "tempest", "void"]
	var srcs: Array[String] = []
	for f: String in ["level_11_manor.gd", "level_12_armada.gd", "level_13_candy.gd", "level_14_carrier.gd",
			"level_16_sakura.gd", "level_17_jungle.gd", "level_18_frontier.gd", "level_19_neon.gd",
			"level_20_doom.gd", "level_21_abyss.gd", "level_22_tempest.gd", "level_23_void.gd"]:
		srcs.append("res://levels/" + f)
	for f: String in DirAccess.get_files_at("res://mechanics"):
		if f.ends_with(".gd") and prefixes.any(func(p: String) -> bool: return f.begins_with(p + "_")):
			srcs.append("res://mechanics/" + f)
	# the third and fourth sets' decor scripts own their waterfalls, vents, signs and thunder (the older
	# maps' visual/ scripts stay out of this scan; armada_storm.gd now plays the ambience's thunder)
	for f: String in DirAccess.get_files_at("res://visual"):
		if f.ends_with(".gd") and ["sakura", "jungle", "frontier", "neon", "doom", "abyss", "tempest", "void"].any(
				func(p: String) -> bool: return f.begins_with(p + "_")):
			srcs.append("res://visual/" + f)
	var re := RegEx.create_from_string("\"((?:%s)_[a-z0-9_]+)\"" % "|".join(prefixes))
	var asked: Dictionary = {}
	for path: String in srcs:
		if not FileAccess.file_exists(path):
			continue
		for line: String in FileAccess.get_file_as_string(path).split("
"):
			# a clip held in a table ({"clip": "sakura_ram_creak"}) or handed to a tell node
			# (tell.clip = "abyss_shrimp_click") and played later counts too
			if not (line.contains("WorldAudio.") or line.contains("Sfx.") or line.contains("\"clip\"")
					or line.contains(".clip =") or line.contains("var clip")):
				continue
			for m: RegExMatch in re.search_all(line):
				asked[m.get_string(1)] = true
	var unknown: Array[String] = []
	for c: String in asked:
		if not Sfx.has_clip(c):
			unknown.append(c)
	check(asked.size() >= 100 and unknown.is_empty(),
		"every WorldAudio clip the newer maps name exists (%d named) %s" % [asked.size(), str(unknown)])
	var flat: Array[String] = []
	for c: String in WORLD_LOOPS:
		var s: AudioStreamWAV = load("res://audio/%s.wav" % c) as AudioStreamWAV
		if s == null or s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			flat.append(c)
	check(flat.is_empty(), "every machine / movement loop imports as a loop %s" % str(flat))
	check(not WorldAudio.enabled(), "headless runs make no world sounds (no emitters, no per-frame cost)")
	# the sound side of every level, forced on: builds its emitters, follows the machines through
	# their cycles with the player stood next to each kind, and logs no errors doing it
	WorldAudio._enabled = 1
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		var lvl: LevelBase = await load_level(i)
		var label: String = str(Game.LEVELS[i]["name"])
		var loops: int = lvl.find_children("*", "AudioStreamPlayer3D", true, false).size()
		check(loops > 3 and lvl.player.find_children("*", "PlayerAudio", true, false).size() == 1,
			"%s: builds its sound emitters (%d) and the player's own" % [label, loops])
		var seen: Dictionary = {}
		var heard: int = 0
		var pool: Array = Sfx.get("_pool3d")
		for o: Variant in lvl.find_children("*", "Node3D", true, false):
			# a machine can free its own parts mid-sweep (the carrier's launched jets)
			if not is_instance_valid(o):
				continue
			var n: Node = o
			var sc: Script = n.get_script() as Script
			if sc == null or seen.has(sc) or not sc.resource_path.begins_with("res://mechanics/"):
				continue
			if n is FinishGate or n is Checkpoint:
				continue
			seen[sc] = true
			lvl.player.teleport(Transform3D(Basis(), (n as Node3D).global_position + Vector3(1.5, 2.0, 2.5)))
			lvl.player.cmd_move = Vector2(0.4, 1.0)
			for k: int in 8:
				await seconds(0.1)
				for b: AudioStreamPlayer3D in pool:
					if b.playing:
						heard += 1
		lvl.player.cmd_move = Vector2.ZERO
		check(heard > 0, "%s: the machines' one-shots play near the listener (%d voice-samples)" % [label, heard])
	WorldAudio._enabled = 0
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)


func test_zq_particle_slider() -> void:
	var old_q: int = Settings.quality
	var old_p: float = Settings.particles
	Settings.quality = 2
	Settings.particles = 1.0
	near(Settings.particle_scale(), 1.0, 0.001, "the particle slider at 100% leaves the quality tier as it is")
	Settings.particles = 2.0
	near(Settings.particle_scale(), 2.0, 0.001, "Maximum doubles every emitter")
	Settings.particles = 0.2
	near(Settings.particle_scale(), 0.2, 0.001, "Low keeps a fifth")
	Settings.particles = 9.0
	Settings.call("_sanitize")
	near(Settings.particles, 2.0, 0.001, "a hand-edited value is clamped to the slider range")
	var panel := SettingsPanel.new()
	add_child(panel)
	await ticks(2)
	var found: bool = false
	for l: Node in panel.find_children("*", "Label", true, false):
		found = found or (l as Label).text == "Particles"
	check(found, "Settings has a Particles slider")
	panel.queue_free()
	Settings.quality = old_q
	Settings.particles = old_p


# ---- run it again: race laps ------------------------------------------------------------------
func test_zl_lap_math_and_messages() -> void:
	check(Net.laps_ahead(1, 0, 0, 3) == 1, "exactly one full course ahead is a lap")
	check(Net.laps_ahead(1, 0, 1, 3) == 0 and Net.laps_ahead(1, 1, 1, 3) == 1, "one checkpoint short is not a lap; matching it is")
	check(Net.laps_ahead(2, 3, 0, 3) == 2 and Net.laps_ahead(3, 1, 1, 3) == 3, "several courses ahead count several laps")
	check(Net.host(24598) == OK, "hosting a race")
	var me: int = Net.my_id()
	Net.roster[me]["finished"] = 50.0
	Net.roster[me]["cp"] = 4
	Net.roster[2] = {"name": "Ada", "color": 1, "cp": 1, "finished": -1.0, "cp_at": 5.0}
	Net.roster[3] = {"name": "Bo", "color": 2, "cp": 0, "finished": -1.0, "cp_at": 0.0}
	var order: Array[int] = Net.standings()
	var got: Array = []
	var cb := func(l: int, v: int, n: int) -> void: got.append([l, v, n])
	Net.racer_lapped.connect(cb)
	Net.send_lap(1, 0, 3, false)
	check(got.is_empty() and int(Net.race_laps[me]["lap"]) == 1, "starting a lap only reports progress")
	Net.send_lap(1, 1, 3)
	check(got.size() == 2 and int(got[0][2]) == 1, "a full course ahead laps both racers once (%s)" % str(got))
	Net.send_lap(1, 2, 3)
	check(got.size() == 2, "no repeat message for the same lap")
	Net.send_lap(3, 1, 3)
	check(Net.times_lapped(2) == 3 and int(got[got.size() - 1][2]) == 3, "three courses ahead is the third lap (%s)" % str(got))
	check(Net.standings() == order, "laps never change the standings")
	Net.roster[3]["finished"] = 70.0
	var before: int = got.size()
	Net.send_lap(5, 0, 3)
	var hit_bo: bool = false
	for g: Array in got.slice(before):
		hit_bo = hit_bo or int(g[1]) == 3
	check(not hit_bo, "a racer who has finished can't be lapped")
	Net._apply_lap_msg(2, {"k": "x", "victim": me, "count": 1})
	check(Net.times_lapped(me) == 0, "a racer still on the first run can't send laps")
	Net.leave()
	# the relay path: a lap packet riding the pose event
	Net.roster = {1: {"name": "Host", "color": 0, "cp": 4, "finished": 40.0}, 7: {"name": "Me", "color": 1, "cp": 1, "finished": -1.0}}
	Net.set("_relay_peer_id", 7)
	Net.set("_relay_mode", true)
	Net.active = true
	got.clear()
	var poses: Array = []
	var pcb := func(id: int, _p: Vector3, _v: Vector3, _g: bool, _s: int) -> void: poses.append(id)
	Net.racer_pose.connect(pcb)
	Net.call("_handle_relay_event", 1, "pose", {"lap": {"k": "x", "victim": 7, "count": 3}})
	check(got.size() == 1 and int(got[0][0]) == 1 and int(got[0][1]) == 7 and int(got[0][2]) == 3 and poses.is_empty(),
		"a lap message arrives over the relay's pose event and is never a pose (%s)" % str(got))
	Net.racer_pose.disconnect(pcb)
	Net.racer_lapped.disconnect(cb)
	Net.leave()
	Net.set("_relay_mode", false)


func test_zl_run_it_again() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	check(Net.host(24599) == OK, "hosting a race")
	var me: int = Net.my_id()
	Net.roster[2] = {"name": "Ada", "color": 1, "cp": 0, "finished": -1.0, "cp_at": 0.0}
	Net.roster[3] = {"name": "Bo", "color": 2, "cp": 4, "finished": 30.0, "cp_at": 0.0}
	Game.level_index = 0
	Game.race_mode = true
	Net.race_start_time = Net.now() - 1.0
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	# being lapped (Bo has finished and is running again)
	Net._apply_lap_msg(3, {"k": "x", "victim": me, "count": 1})
	check(lvl.hud._lapped != null and lvl.hud._lapped.text == "Bo lapped you!", "the lapped racer sees NAME lapped you!")
	Net._apply_lap_msg(3, {"k": "x", "victim": me, "count": 3})
	check(lvl.hud._lapped.text == "Bo lapped you 3 TIMES!" and lvl.hud._lapped.get_theme_font_size("font_size") == 64,
		"the third lap is the big one (%s)" % lvl.hud._lapped.text)
	lvl.hud._rebuild_board()
	var board: String = ""
	for l: Node in lvl.hud._board.get_children():
		board += (l as Label).text + "|"
	check(board.contains("lapped x3"), "the board tags a racer lapped three times (%s)" % board)
	# first finish, then Run It Again with the pad
	lvl.run_time = 42.0
	lvl._on_finish()
	var first_time: float = float(Net.roster[me]["finished"])
	var order: Array[int] = Net.standings()
	var btn: Button = null
	for n: Node in lvl.hud._results.find_children("*", "Button", true, false):
		if (n as Button).text == "Run It Again":
			btn = n as Button
	check(btn != null, "race results offer Run It Again")
	await real_seconds(1.1)
	check(_focused_text().begins_with("Spectate"), "Spectate keeps first focus while Ada races (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(_focused_text() == "Run It Again", "the D-pad reaches Run It Again (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(_focused_text() != "Run It Again" and _focused_text() != "", "and moves on past it (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_UP))
	check(_focused_text() == "Run It Again", "and back")
	var seq0: int = int(Net.get("_pose_seq"))
	lvl.current_checkpoint = 3
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(2)
	check(not lvl.finished and lvl.current_checkpoint == 0 and lvl.hud._results == null and lvl.laps_done == 1 and lvl.player.control_enabled,
		"A runs it again: back at the start with checkpoints reset")
	check(int(Net.get("_pose_seq")) != seq0, "the run-again teleport bumps the pose sequence (ghosts snap)")
	check(float(Net.roster[me]["finished"]) == first_time and Net.standings() == order, "the first finish time and placing are kept")
	# a checkpoint on lap 2 is a full course ahead of Ada, still at the start
	lvl._on_checkpoint(lvl.checkpoints[0])
	check(lvl.hud._toast.text == "You lapped Ada" and Net.lap_counts.has(2), "the lapper sees You lapped NAME (%s)" % lvl.hud._toast.text)
	lvl.run_time = lvl._lap_start + 20.0
	lvl._on_finish()
	check(lvl.laps_done == 2 and not lvl.finished and lvl.current_checkpoint == 0 and lvl.hud._toast.text.begins_with("Lap 2 done"),
		"finishing a lap toasts it and starts the next (%s)" % lvl.hud._toast.text)
	check(float(Net.roster[me]["finished"]) == first_time and Net.standings() == order, "laps change neither time nor standings")
	Net.leave()
	Game.race_mode = false
	world.queue_free()
	world = null
	await ticks(2)



# ---- unlockable cosmetics: trails and finish celebrations (Cosmetics, Locker) -----------------

func _cos_levels(ids: Array, extra: Dictionary = {}) -> Dictionary:
	var lv: Dictionary = {}
	for id: Variant in ids:
		lv[id] = {"completed": true, "runs": 1}
	lv.merge(extra, true)
	return lv


func test_zc_cosmetics_unlock_rules() -> void:
	var none: Dictionary = {}
	for kind: String in ["trail", "finish"]:
		for id: String in Cosmetics.ids(kind):
			var is_default: bool = Cosmetics.catalogue(kind)[id]["rule"]["type"] == "default"
			check(Cosmetics.is_unlocked(kind, id, none) == is_default, "%s %s: %s on a fresh save" % [kind, id, "owned" if is_default else "locked"])
			if not is_default:
				check(Cosmetics.hint(kind, id) != "", "%s %s has an unlock hint (%s)" % [kind, id, Cosmetics.hint(kind, id)])
	# every world-themed trail is earned on its own world
	var themed: Dictionary = {"flame": "volcano", "bubbles": "reef", "frost": "glacier", "sand": "desert",
		"wisps": "manor", "sprinkles": "candy", "contrail": "carrier"}
	for trail: String in themed:
		var lv: Dictionary = _cos_levels([themed[trail]])
		check(Cosmetics.is_unlocked("trail", trail, lv), "beating %s unlocks the %s trail" % [themed[trail], trail])
		check(not Cosmetics.is_unlocked("trail", "rainbow", lv), "... but not Rainbow")
	check(not Cosmetics.is_unlocked("trail", "flame", {"volcano": {"completed": false, "runs": 0}}), "an unfinished course unlocks nothing")
	var four: Dictionary = _cos_levels(["gardens", "foundry", "balance", "clockwork"])
	check(not Cosmetics.is_unlocked("finish", "fireworks", four), "4 courses: no Fireworks yet (%s)" % Cosmetics.progress("finish", "fireworks", four))
	four["reef"] = {"completed": true, "runs": 1}
	check(Cosmetics.is_unlocked("finish", "fireworks", four), "5 different courses unlock Fireworks")
	check(not Cosmetics.is_unlocked("finish", "fireworks", {"playground": {"completed": true}, "gardens": {"completed": true}, "x1": {"completed": true}, "x2": {"completed": true}, "x3": {"completed": true}}),
		"only real courses count towards the course milestones")
	check(Cosmetics.is_unlocked("finish", "confetti", {"gardens": {"completed": true, "runs": 25}}), "25 runs (even on one course) unlock the Confetti Cannon")
	check(not Cosmetics.is_unlocked("finish", "confetti", {"gardens": {"completed": true, "runs": 24}}), "24 runs do not")
	check(Cosmetics.is_unlocked("finish", "lightning", _cos_levels(["armada"])), "Storm Armada unlocks the Lightning Bolt")
	check(Cosmetics.is_unlocked("finish", "ghost", {"gardens": {"completed": true, "fewest_falls": 0}}), "a run without a fall unlocks Ghost Spin")
	check(Cosmetics.is_unlocked("finish", "ghost", {"gardens": {"completed": true, "legacy_fewest_falls": 0}}), "... also one set on an older layout")
	check(not Cosmetics.is_unlocked("finish", "ghost", {"gardens": {"completed": true, "fewest_falls": 2}}), "falls every run: no Ghost Spin")
	var all_ids: Array = []
	for info: Dictionary in Game.LEVELS:
		all_ids.append(info["id"])
	var every: Dictionary = _cos_levels(all_ids)
	check(Cosmetics.is_unlocked("trail", "rainbow", every) and Cosmetics.is_unlocked("finish", "jet", every), "every course: Rainbow trail and Jet Flyover")
	every.erase("ascent")
	check(not Cosmetics.is_unlocked("trail", "rainbow", every) and Cosmetics.is_unlocked("finish", "jet", every), "one short of all: no Rainbow (10+ is enough for the jet)")
	check(Cosmetics.unlock_text("trail", "flame") == "Unlocked: Flame trail!", "the toast reads '%s'" % Cosmetics.unlock_text("trail", "flame"))


func test_zc_cosmetics_retroactive_and_one_time_toast() -> void:
	var old_trail: String = Settings.trail_id
	# a save from before cosmetics existed: two worlds beaten, no "cosmetics_seen"
	var f: FileAccess = FileAccess.open(SaveData._path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"game_completed": false, "levels": {
		"reef": {"completed": true, "runs": 3, "best": 380.0, "rev": 1},
		"glacier": {"completed": true, "runs": 1, "best": 420.0, "rev": 1}}}))   # (slower than Bronze: no medal rewards)
	f.close()
	SaveData.load_data()
	check(Cosmetics.is_unlocked("trail", "bubbles") and Cosmetics.is_unlocked("trail", "frost"), "an old save unlocks what it already earned")
	var fresh: Array[Array] = Cosmetics.check_unlocks()
	var keys: Array[String] = []
	for x: Array in fresh:
		keys.append("%s:%s" % [x[0], x[1]])
	check(keys == ["trail:bubbles", "trail:frost"], "announced once, defaults never: %s" % [keys])
	check(Cosmetics.check_unlocks().is_empty(), "the second check announces nothing")
	SaveData.load_data()
	check(Cosmetics.check_unlocks().is_empty(), "... even after reloading the save (seen list stored: %s)" % [SaveData.cosmetics_seen()])
	# the title's main menu shows the retroactive batch once, then never again
	SaveData.data["cosmetics_seen"] = []
	Game.title_screen = "main"
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	title.set("persist_settings", false)
	add_child(title)
	await ticks(2)
	var note_count := func() -> int:
		var n: int = 0
		for l: Node in (title.get("_screen") as Control).find_children("*", "Label", true, false):
			if (l as Label).text.begins_with("Unlocked:"):
				n += 1
		return n
	check(note_count.call() == 1, "the main menu lists retroactive unlocks")
	title.call("show_screen", "main")
	await ticks(2)
	check(note_count.call() == 0, "only the first time")
	title.queue_free()
	await ticks(2)
	# a new finish unlocks exactly its own item
	SaveData.record_finish("volcano", 400.0, 3)   # (slower than Bronze)
	fresh = Cosmetics.check_unlocks()
	check(fresh.size() == 1 and fresh[0] == ["trail", "flame"], "beating Cinder Peak announces the Flame trail (%s)" % [fresh])
	# a hand-edited seen list keeps strings only
	var clean: Dictionary = SaveData._sanitize({"levels": {}, "cosmetics_seen": ["trail:flame", 5, null, "trail:flame", "finish:jet"]})
	check(clean.get("cosmetics_seen") == ["trail:flame", "finish:jet"], "cosmetics_seen is sanitized (%s)" % [clean.get("cosmetics_seen")])
	# a locked pick wears the default in game
	Settings.trail_id = "rainbow"
	check(Cosmetics.equipped_trail() == "classic", "a locked trail in settings falls back to Classic")
	Settings.trail_id = "flame"
	check(Cosmetics.equipped_trail() == "flame", "an unlocked one is worn")
	Settings.trail_id = old_trail
	SaveData.wipe()


func test_zc_settings_sanitize_cosmetic_ids() -> void:
	var old_t: String = Settings.trail_id
	var old_f: String = Settings.finish_id
	Settings.trail_id = "laser_beams"
	Settings.finish_id = ""
	Settings.call("_sanitize")
	check(Settings.trail_id == "classic" and Settings.finish_id == "cheer", "unknown ids fall back to the defaults")
	Settings.trail_id = "frost"
	Settings.finish_id = "jet"
	Settings.call("_sanitize")
	check(Settings.trail_id == "frost" and Settings.finish_id == "jet", "known ids are kept (even if still locked)")
	# a hand-edited settings file with the wrong types
	var path: String = "user://test_settings_cosmetics.cfg"
	var cf := ConfigFile.new()
	cf.set_value("s", "trail_id", 42)
	cf.set_value("s", "finish_id", "nope")
	cf.save(path)
	Settings.load_settings(path)
	check(Settings.trail_id == "frost" and Settings.finish_id == "cheer", "a wrong-typed id is ignored, a bad string resets (%s / %s)" % [Settings.trail_id, Settings.finish_id])
	check("trail_id" in Settings._props() and "finish_id" in Settings._props(), "both picks are saved with the settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.trail_id = old_t
	Settings.finish_id = old_f


func test_zc_locker_pad_navigation() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var old_t: String = Settings.trail_id
	var old_f: String = Settings.finish_id
	SaveData.wipe()
	SaveData.data["levels"]["volcano"] = {"completed": true, "runs": 1}
	Settings.trail_id = "classic"
	Settings.finish_id = "cheer"
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	title.set("persist_settings", false)
	add_child(title)
	title.call("show_screen", "main")
	await ticks(3)
	var send := func(button: JoyButton) -> void:
		var ev := InputEventJoypadButton.new()
		ev.device = 2
		ev.button_index = button
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		var up: InputEventJoypadButton = ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await ticks(2)
	var focus := func() -> Control:
		return get_viewport().gui_get_focus_owner()
	# walk down the main menu to Locker and press A
	var guard: int = 0
	while not (focus.call() is Button and (focus.call() as Button).text == "Locker") and guard < 12:
		await send.call(JOY_BUTTON_DPAD_DOWN)
		guard += 1
	check(focus.call() is Button and (focus.call() as Button).text == "Locker", "the main menu has a Locker entry reachable with the D-pad")
	await send.call(JOY_BUTTON_A)
	await ticks(2)
	check(Game.title_screen == "locker", "A opens the Locker")
	check(focus.call() != null and focus.call().get_meta("kind", "") == "character" and focus.call().get_meta("item", "") == "volt",
		"it opens on the Character tab, on the worn character")
	# RB to the Trail tab (Character > Hat > Paint > Trail)
	for i: int in 3:
		await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	var volt: PlayerVisual = title.get("_volt")
	var f: Control = focus.call()
	check(f != null and f.get_meta("kind", "") == "trail" and f.get_meta("item", "") == "classic", "RB x3 reaches the Trail tab, on the equipped trail")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	f = focus.call()
	check(f != null and f.get_meta("item", "") == "sparkle" and volt.trail_id == "sparkle", "right moves along the trails and previews each on Volt")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	var info: Label = title.get("_locker_info")
	check(focus.call().get_meta("item", "") == "flame" and not info.text.begins_with("LOCKED"), "Flame (Cinder Peak beaten) shows as owned")
	await send.call(JOY_BUTTON_A)
	check(Settings.trail_id == "flame" and (focus.call() as Button).text == "> Flame <", "A equips an unlocked trail")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	check(focus.call().get_meta("item", "") == "bubbles" and info.text.begins_with("LOCKED") and info.text.contains("Coral Depths"),
		"a locked trail can be focused and names its unlock (%s)" % info.text)
	await send.call(JOY_BUTTON_A)
	check(Settings.trail_id == "flame", "A on a locked trail only previews it")
	# RB to the Finish tab
	await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	check(focus.call() != null and focus.call().get_meta("kind", "") == "finish", "RB reaches the Finish tab")
	check(volt.trail_id == "flame", "switching tabs puts the equipped trail back on the preview")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	var fin_id: String = str(focus.call().get_meta("item", ""))
	await send.call(JOY_BUTTON_A)
	var want_fin: String = fin_id if Cosmetics.is_unlocked("finish", fin_id) else "cheer"
	check(Settings.finish_id == want_fin and volt.finish_id == fin_id,
		"A on a finish plays it on Volt (%s), equipping only if owned" % fin_id)
	guard = 0
	while not (focus.call() is Button and (focus.call() as Button).text == "Back") and guard < 4:
		await send.call(JOY_BUTTON_DPAD_DOWN)
		guard += 1
	check(focus.call() is Button and (focus.call() as Button).text == "Back", "down reaches Back")
	await send.call(JOY_BUTTON_DPAD_UP)
	check(focus.call() != null and focus.call().get_meta("kind", "") == "finish", "and up goes back to the Finish row")
	# LB goes back a tab
	await send.call(JOY_BUTTON_LEFT_SHOULDER)
	check(focus.call() != null and focus.call().get_meta("kind", "") == "trail" and focus.call().get_meta("item", "") == "flame",
		"LB goes back to the Trail tab, on the newly equipped Flame")
	await send.call(JOY_BUTTON_B)
	await ticks(2)
	check(Game.title_screen == "main", "B leaves the Locker")
	check(focus.call() is Button and (focus.call() as Button).text == "Locker", "focus returns to the Locker button")
	check(volt.trail_id == "flame", "the title Volt wears the equipped trail again")
	title.queue_free()
	await ticks(2)
	Settings.trail_id = old_t
	Settings.finish_id = old_f
	SaveData.wipe()


func test_zc_trail_and_finish_particles_follow_slider() -> void:
	await new_world()
	var old_q: int = Settings.quality
	var old_p: float = Settings.particles
	Settings.quality = 2
	var v := PlayerVisual.new()
	world.add_child(v)
	await ticks(1)
	for trail: String in Cosmetics.ids("trail"):
		var counts: Array[Array] = []
		for p: float in [1.0, 2.0, 0.2]:
			Settings.particles = p
			v.set_trail(trail)
			var row: Array = []
			for e: GPUParticles3D in v.trail_emitters():
				row.append(e.amount)
			counts.append(row)
		var ok: bool = true
		var specs: Array[Dictionary] = PlayerVisual.trail_layers(trail)
		for i: int in counts[0].size():
			var base: int = int(specs[i]["amount"]) if not specs.is_empty() else 44
			ok = ok and counts[0][i] == base and counts[1][i] == roundi(base * 2.0) and counts[2][i] == maxi(1, roundi(base * 0.2))
		check(ok and v.trail_id == trail, "%s trail: every layer scales with the Particles slider %s" % [trail, counts])
	# a moving Volt streams its trail; standing still stops it
	Settings.particles = 1.0
	v.set_trail("flame")
	v.animate(1.0 / 60.0, Vector3(9, 0, 0), true, Vector3.FORWARD)
	check(v.trail_emitters().all(func(e: GPUParticles3D) -> bool: return e.emitting), "a brisk run lights every layer of an unlocked trail")
	v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(v.trail_emitters().all(func(e: GPUParticles3D) -> bool: return not e.emitting), "standing still puts it out")
	# finish effects: fired through Fx.spawn, so they scale too
	for p: float in [1.0, 2.0]:
		Settings.particles = p
		var before: Array[Node] = v.find_children("*", "GPUParticles3D", true, false)
		v.play_finish("confetti")
		var added: Array[int] = []
		for n: Node in v.find_children("*", "GPUParticles3D", true, false):
			if not before.has(n):
				added.append((n as GPUParticles3D).amount)
		check(added.has(roundi(70 * p)), "the Confetti Cannon fires %d-particle bursts at %.0f%% (%s)" % [roundi(70 * p), p * 100.0, added])
	for id: String in Cosmetics.ids("finish"):
		var e0: int = trap.count()
		v.finish_id = id
		v.on_cheer()
		await ticks(5)
		check(trap.count() == e0, "the %s finish plays without errors %s" % [id, trap.since(e0)])
	await seconds(4.5)
	var leftovers: int = 0
	for n: Node in v.get_children():
		if str(n.name).begins_with("FinishBolt") or str(n.name).begins_with("FinishJet"):
			leftovers += 1
	check(leftovers == 0, "the bolt and the jet clean up after themselves (%d left)" % leftovers)
	Settings.quality = old_q
	Settings.particles = old_p
	world.queue_free()
	world = null
	await ticks(2)


func test_zc_remote_racer_cosmetics() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var r := RemoteRacer.new()
	add_child(r)
	await ticks(1)
	r.setup("Ada", Settings.RACER_COLORS[1])
	r.set_cosmetics("frost", "lightning")
	check(r.visual().trail_id == "frost" and r.visual().finish_id == "lightning", "a remote racer wears the trail and finish they sent")
	r.set_cosmetics("<script>", 7)
	check(r.visual().trail_id == "classic" and r.visual().finish_id == "cheer", "unknown ids from the wire fall back to the defaults")
	r.queue_free()
	# the host keeps each racer's ids in the roster, and they survive the relay's JSON
	check(Net.host(24595) == OK, "hosting a lobby")
	check(Net.roster[1].has("trail") and Net.roster[1].has("finish"), "the host's own entry carries its cosmetics")
	Net._register_player(2, "Ada", 1, {"trail": "wisps", "finish": "ghost"})
	Net._register_player(3, "Bo", 2, {"trail": 99})
	check(Net.roster[2]["trail"] == "wisps" and Net.roster[2]["finish"] == "ghost", "registration stores trail / finish next to the colour")
	check(Net.roster[3]["trail"] == "classic" and Net.roster[3]["finish"] == "cheer", "junk or missing ids register as the defaults")
	var wire: Variant = JSON.parse_string(JSON.stringify({"players": Net._roster_to_wire()}))
	var back: Dictionary = Net._roster_from_wire((wire as Dictionary)["players"])
	check(back.has(2) and back[2]["trail"] == "wisps" and back[2]["finish"] == "ghost", "the ids survive the relay's JSON roster")
	check(Net._register_data().get("trail") == Cosmetics.equipped_trail(), "our relay registration sends our trail")
	# in the race: ghosts wear them and celebrate their own way
	Net.roster[2]["cp"] = 0
	Net.roster[2]["cp_at"] = 0.0
	Net.roster[3]["cp_at"] = 0.0
	Game.level_index = 0
	Game.race_mode = true
	Net.race_start_time = Net.now() - 1.0
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var g: RemoteRacer = lvl._ghosts.get(2)
	check(g != null and g.visual().trail_id == "wisps" and g.visual().finish_id == "ghost", "the race ghost wears Ada's Ghostly Wisps and Ghost Spin")
	var e0: int = trap.count()
	Net._apply_finished(2, 50.0)
	await ticks(5)
	check(trap.count() == e0 and g.visual()._cheer_t < 1.0, "when Ada finishes her ghost celebrates %s" % trap.since(e0))
	Net.leave()
	Game.race_mode = false
	world.queue_free()
	world = null
	await ticks(2)



# ---- medal times and rewards (characters, hats, paints, titles) --------------------------------

## The four worlds still being built carry provisional medal times (no bot time yet).
const _ZM_PROVISIONAL: Array[String] = []


## A levels dict with these bests (id -> seconds), as SaveData stores them.
func _zm_levels(bests: Dictionary, legacy: bool = false) -> Dictionary:
	var lv: Dictionary = {}
	for id: Variant in bests:
		lv[id] = {"completed": true, "runs": 1, ("legacy_best" if legacy else "best"): float(bests[id])}
	return lv


## Every course at `tier` (its target time exactly).
func _zm_all_at(tier: int) -> Dictionary:
	var b: Dictionary = {}
	for info: Dictionary in Game.LEVELS:
		b[info["id"]] = Game.medal_target(str(info["id"]), tier)
	return _zm_levels(b)


func test_zm_medal_for_edges() -> void:
	for info: Dictionary in Game.LEVELS:
		var id: String = info["id"]
		var m: Dictionary = info.get("medals", {})
		check(m.has("gold") and m.has("silver") and m.has("bronze") and m["gold"] is int and m["silver"] is int and m["bronze"] is int,
			"%s has whole-second gold / silver / bronze targets" % id)
		check(int(m["gold"]) < int(m["silver"]) and int(m["silver"]) < int(m["bronze"]), "%s: gold < silver < bronze %s" % [id, m])
		var g: float = float(m["gold"])
		var s: float = float(m["silver"])
		var b: float = float(m["bronze"])
		var ok: bool = Game.medal_for(id, g) == 3 and Game.medal_for(id, g - 30.0) == 3 and Game.medal_for(id, g + 0.01) == 2 \
			and Game.medal_for(id, s) == 2 and Game.medal_for(id, s + 0.01) == 1 and Game.medal_for(id, b) == 1 \
			and Game.medal_for(id, b + 0.01) == 0 and Game.medal_for(id, 9999.0) == 0
		check(ok, "%s: a time on a target earns it, a hundredth over drops a tier" % id)
	check(Game.medal_for("gardens", -1.0) == 0 and Game.medal_for("gardens", INF) == 0 and Game.medal_for("gardens", NAN) == 0,
		"no time / a non-finite time earns nothing")
	check(Game.medal_for("playground", 1.0) == 0 and Game.medal_for("nope", 1.0) == 0, "the playground and unknown ids have no medals")
	# 1/120 s ticks summed: 170 s arrives as 169.99999999 and must still be Gold
	var t: float = 0.0
	for i: int in 170 * 120:
		t += 1.0 / 120.0
	check(Game.medal_for("gardens", t) == 3, "a time that is the target up to float error counts (%.9f)" % t)
	check(Game.medal_target("gardens", 3) == float(Game.medal_targets("gardens")["gold"]) and Game.medal_target("gardens", 0) == -1.0,
		"medal_target reads a tier's time")
	check(Hud.target_text(170.0) == "2:50" and Hud.next_target_text("gardens", 2) == "Next: Gold 2:50" and Hud.next_target_text("gardens", 3) == "",
		"next target reads '%s'" % Hud.next_target_text("gardens", 2))


func test_zm_medal_targets_follow_bot_times() -> void:
	for info: Dictionary in Game.LEVELS:
		var id: String = info["id"]
		if not Game.BOT_TIMES.has(id):
			check(id in _ZM_PROVISIONAL, "%s has a bot time reference (only the placeholder worlds may not)" % id)
			continue
		var bot: float = float(Game.BOT_TIMES[id])
		var m: Dictionary = info["medals"]
		check(float(m["gold"]) >= bot, "%s: Gold %d is never below the fastest bot route (%.1f s)" % [id, int(m["gold"]), bot])
		for k: String in ["gold", "silver", "bronze"]:
			var raw: float = bot * float(Game.MEDAL_MULT[k])
			check(float(m[k]) >= raw - 0.001 and float(m[k]) < raw + 5.0 and int(m[k]) % 5 == 0,
				"%s %s = bot x %.2f rounded up to 5 s (%d vs %.1f)" % [id, k, float(Game.MEDAL_MULT[k]), int(m[k]), raw])
	for id: String in Game.BOT_TIMES:
		check(not Game.level_by_id(id).is_empty(), "bot time %s belongs to a course" % id)


func test_zm_medals_retroactive_and_legacy() -> void:
	# an old save: Launch Gardens beaten on layout rev 1 (now rev 3) in Gold time, Coral Depths
	# on the current layout in Silver time, from before medals existed
	var gold: float = Game.medal_target("gardens", 3)
	var f: FileAccess = FileAccess.open(SaveData._path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"game_completed": false, "levels": {
		"gardens": {"completed": true, "runs": 4, "best": gold - 1.0, "rev": 1},
		"reef": {"completed": true, "runs": 2, "best": Game.medal_target("reef", 2) - 0.5, "rev": 1}}}))
	f.close()
	SaveData.load_data()
	check(SaveData.best_time("gardens") < 0.0 and SaveData.data["levels"]["gardens"].has("legacy_best"), "the old-layout best moved to legacy_best")
	check(SaveData.medal("gardens") == 3, "... and still holds its Gold")
	check(SaveData.medal("reef") == 2, "an old save earns Silver retroactively")
	check(SaveData.medal("orbital") == 0, "an unplayed course has no medal")
	# a slower run on the new layout never takes the medal away
	SaveData.record_finish("gardens", gold + 60.0, 4)
	check(SaveData.best_time("gardens") == gold + 60.0 and SaveData.medal("gardens") == 3, "min(best, legacy_best): a slower new best keeps the Gold")
	# ... and a faster current best than the legacy one counts too
	SaveData.data["levels"]["reef"]["legacy_best"] = 999.0
	check(SaveData.medal("reef") == 2, "the faster of the two counts")
	check(Cosmetics.is_unlocked("hat", "sunhat") and Cosmetics.is_unlocked("hat", "snorkel"), "the medal hats are unlocked from the old save")
	var fresh: Array[Array] = Cosmetics.check_unlocks()
	var keys: Array[String] = []
	for x: Array in fresh:
		keys.append("%s:%s" % [x[0], x[1]])
	check(keys.has("hat:sunhat") and keys.has("hat:snorkel") and not keys.has("hat:none"), "check_unlocks announces medal rewards once (%s)" % [keys])
	check(Cosmetics.check_unlocks().is_empty(), "and only once")
	# the level select shows medals and the next target
	Game.title_screen = "levels"
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	title.set("persist_settings", false)
	add_child(title)
	await ticks(3)
	var rows: Dictionary = {}
	for n: Node in (title.get("_screen") as Control).find_children("*", "Button", true, false):
		if n.has_meta("medal"):
			rows[(n as Button).text.get_slice("   ", 1)] = n
	var g_row: Button = rows.get("Launch Gardens")
	var r_row: Button = rows.get("Coral Depths")
	check(g_row != null and int(g_row.get_meta("medal")) == 3 and g_row.text.contains("GOLD") and not g_row.text.contains("next"),
		"level select: Gold on Launch Gardens, nothing further to chase (%s)" % (g_row.text if g_row != null else "missing"))
	check(r_row != null and r_row.text.contains("SILVER") and r_row.text.contains("next Gold %s" % Hud.target_text(Game.medal_target("reef", 3))),
		"level select: Silver on Coral Depths with the Gold target (%s)" % (r_row.text if r_row != null else "missing"))
	var unplayed: String = str(title.call("level_medal_text", "sakura", 0, false))
	check(unplayed.contains("Gold target %s" % Hud.target_text(Game.medal_target("sakura", 3))),
		"level select: a course not yet run shows its Gold target (%s)" % unplayed)
	title.queue_free()
	await ticks(2)
	Game.title_screen = "main"
	SaveData.wipe()


func test_zm_reward_rules_hints_progress() -> void:
	var none: Dictionary = {}
	var no_stats: Dictionary = {}
	for kind: String in Cosmetics.kinds():
		for id: String in Cosmetics.ids(kind):
			var is_default: bool = Cosmetics.catalogue(kind)[id]["rule"]["type"] == "default"
			check(Cosmetics.is_unlocked(kind, id, none, no_stats) == is_default, "%s %s: %s on a fresh save" % [kind, id, "owned" if is_default else "locked"])
			if not is_default:
				check(Cosmetics.hint(kind, id) != "", "%s %s has a hint (%s)" % [kind, id, Cosmetics.hint(kind, id)])
	# medal{level, tier}
	var g_sak: float = Game.medal_target("sakura", 3)
	check(Cosmetics.is_unlocked("character", "ninja", _zm_levels({"sakura": g_sak})), "Gold on Sakura Peaks: Ninja")
	check(not Cosmetics.is_unlocked("character", "ninja", _zm_levels({"sakura": g_sak + 0.01})), "Silver there is not enough")
	check(Cosmetics.is_unlocked("hat", "kasa", _zm_levels({"sakura": Game.medal_target("sakura", 2)})), "Silver on Sakura Peaks: Straw Kasa")
	check(Cosmetics.is_unlocked("hat", "kasa", _zm_levels({"sakura": g_sak})), "... and Gold counts as Silver or better")
	check(Cosmetics.is_unlocked("paint", "ghost", _zm_levels({"manor": Game.medal_target("manor", 2)}, true)), "a legacy best counts for medals")
	check(Cosmetics.hint("character", "ninja") == "Gold on Sakura Peaks", "medal hint: %s" % Cosmetics.hint("character", "ninja"))
	check(Cosmetics.hint("hat", "witch") == "Silver or better on Phantom Manor", "medal hint: %s" % Cosmetics.hint("hat", "witch"))
	check(Cosmetics.progress("character", "ninja", _zm_levels({"sakura": Game.medal_target("sakura", 2)})) == "best: Silver",
		"medal progress names the best medal held (%s)" % Cosmetics.progress("character", "ninja", _zm_levels({"sakura": Game.medal_target("sakura", 2)})))
	check(Cosmetics.progress("character", "ninja", none) == "best: no medal", "... or none")
	# medals{tier, n}
	var ids: Array[String] = []
	for info: Dictionary in Game.LEVELS:
		ids.append(str(info["id"]))
	var golds: Dictionary = {}
	for i: int in 4:
		golds[ids[i]] = Game.medal_target(ids[i], 3)
	check(not Cosmetics.is_unlocked("paint", "chrome", _zm_levels(golds)) and Cosmetics.progress("paint", "chrome", _zm_levels(golds)) == "Golds 4/5",
		"4 Golds: no Chrome yet (%s)" % Cosmetics.progress("paint", "chrome", _zm_levels(golds)))
	golds[ids[4]] = Game.medal_target(ids[4], 3)
	check(Cosmetics.is_unlocked("paint", "chrome", _zm_levels(golds)) and Cosmetics.is_unlocked("title", "speed_demon", _zm_levels(golds)),
		"5 Golds: Chrome paint and the Speed Demon title")
	check(Cosmetics.is_unlocked("paint", "camo", _zm_levels(golds)), "Golds count towards 'Silver on 5 courses' (Camo)")
	check(Cosmetics.hint("paint", "camo") == "Silver or better on 5 courses" and Cosmetics.hint("character", "knight") == "Bronze or better on 10 courses",
		"medals hints: %s / %s" % [Cosmetics.hint("paint", "camo"), Cosmetics.hint("character", "knight")])
	var bronzes: Dictionary = {}
	for i: int in 10:
		bronzes[ids[i]] = Game.medal_target(ids[i], 1)
	check(Cosmetics.is_unlocked("character", "knight", _zm_levels(bronzes)) and not Cosmetics.is_unlocked("character", "catbot", _zm_levels(bronzes)),
		"10 Bronzes: Knight, but not the Cat-bot (Silver on 10)")
	check(Cosmetics.progress("character", "catbot", _zm_levels(bronzes)) == "Silvers 0/10", "progress: %s" % Cosmetics.progress("character", "catbot", _zm_levels(bronzes)))
	# all_medals{tier}
	var every_gold: Dictionary = _zm_all_at(3)
	check(Cosmetics.is_unlocked("character", "golden", every_gold) and Cosmetics.is_unlocked("title", "gold_rush", every_gold), "every Gold: Golden Volt and Gold Rush")
	var one_short: Dictionary = every_gold.duplicate(true)
	one_short["ascent"]["best"] = Game.medal_target("ascent", 2)
	check(not Cosmetics.is_unlocked("character", "golden", one_short), "one Silver among the Golds: no Golden Volt")
	check(Cosmetics.progress("character", "golden", one_short) == "Golds %d/%d" % [Game.LEVELS.size() - 1, Game.LEVELS.size()],
		"all_medals progress: %s" % Cosmetics.progress("character", "golden", one_short))
	check(Cosmetics.hint("character", "golden") == "Gold on every course", "all_medals hint: %s" % Cosmetics.hint("character", "golden"))
	check(Cosmetics.is_unlocked("hat", "crown", every_gold) and Cosmetics.is_unlocked("title", "globetrotter", every_gold), "and the Crown and Globetrotter")
	# stat{key, n}
	check(not Cosmetics.is_unlocked("hat", "party", none, {"laps_dealt": 2}) and Cosmetics.is_unlocked("hat", "party", none, {"laps_dealt": 3}),
		"lapping racers 3 times: the Party Hat")
	check(Cosmetics.progress("hat", "party", none, {"laps_dealt": 2}) == "2/3" and Cosmetics.progress("title", "lap_king", none, {"laps_dealt": 25}) == "10/10",
		"stat progress counts up and caps")
	check(Cosmetics.is_unlocked("title", "lap_king", none, {"laps_dealt": 10}), "10 laps: Lap King")
	check(Cosmetics.is_unlocked("hat", "halo", none, {"flawless_golds": 1}) and not Cosmetics.is_unlocked("hat", "halo", none, {"flawless_golds": 0}),
		"a flawless Gold: the Halo")
	check(Cosmetics.hint("hat", "party").contains("3 times") and Cosmetics.hint("hat", "halo") != "", "stat hints: %s / %s" % [Cosmetics.hint("hat", "party"), Cosmetics.hint("hat", "halo")])
	check(Cosmetics.stat_value("runs", {"gardens": {"runs": 7}, "reef": {"runs": 3}}, {}) == 10, "the 'runs' stat is the total run count")
	check(Cosmetics.is_unlocked("title", "marathoner", {"gardens": {"completed": true, "runs": 100}}) and Cosmetics.progress("title", "marathoner", {"gardens": {"runs": 40}}) == "40/100",
		"100 runs: Marathoner")
	check(Cosmetics.is_unlocked("title", "flawless", {"gardens": {"completed": true, "fewest_falls": 0}}), "a run without a fall: the Flawless title")
	check(not Cosmetics.rule_met({"type": "stat", "key": "laps_dealt", "n": 1}, none, {"laps_dealt": -5}), "a negative counter counts as zero")
	check(not Cosmetics.rule_met({"type": "bogus"}, none, {}), "an unknown rule type unlocks nothing")
	check(Cosmetics.medal_reward_text(3, "character", "ninja") == "GOLD! New reward: Ninja", "the medal banner reads '%s'" % Cosmetics.medal_reward_text(3, "character", "ninja"))


func test_zm_catalogue_and_kinds() -> void:
	check(Cosmetics.kinds() == ["character", "hat", "paint", "trail", "finish", "title"], "KINDS order: %s" % [Cosmetics.kinds()])
	for kind: String in Cosmetics.kinds():
		var d: String = Cosmetics.default_id(kind)
		check(Cosmetics.has_item(kind, d) and Cosmetics.catalogue(kind)[d]["rule"]["type"] == "default", "%s default %s is in its catalogue and always owned" % [kind, d])
		check(Cosmetics.setting_key(kind) in Settings._props() and Settings.get(Cosmetics.setting_key(kind)) is String, "%s is saved as Settings.%s" % [kind, Cosmetics.setting_key(kind)])
		check(Cosmetics.clean(kind, "<junk>") == d and Cosmetics.clean(kind, 12) == d and Cosmetics.clean(kind, null) == d, "%s: junk ids clean to the default" % kind)
	# the old trail / finish helpers still answer exactly as before
	check(Cosmetics.default_id("trail") == Cosmetics.DEFAULT_TRAIL and Cosmetics.default_id("finish") == Cosmetics.DEFAULT_FINISH, "trail / finish defaults unchanged")
	check(Cosmetics.display_name("trail", "flame") == "Flame trail" and Cosmetics.display_name("finish", "jet") == "Jet Flyover finish", "trail / finish display names unchanged")
	check(Cosmetics.display_name("character", "ninja") == "Ninja" and Cosmetics.display_name("paint", "chrome") == "Chrome paint" and Cosmetics.display_name("title", "lap_king") == "Lap King title",
		"new kinds name themselves")
	check(Cosmetics.catalogue("nope").is_empty() and Cosmetics.default_id("nope") == "", "an unknown kind is empty")
	# the catalogue as planned
	check(Cosmetics.ids("character") == ["volt", "knight", "ninja", "astronaut", "dino", "skeleton", "catbot", "outlaw", "cyber", "golden"], "characters: %s" % [Cosmetics.ids("character")])
	check(Cosmetics.ids("paint") == ["white", "chrome", "camo", "lava", "galaxy", "candy", "ghost", "neon"], "paints: %s" % [Cosmetics.ids("paint")])
	check(Cosmetics.ids("title") == ["rookie", "globetrotter", "speed_demon", "gold_rush", "flawless", "lap_king", "marathoner"], "titles: %s" % [Cosmetics.ids("title")])
	# one hat per world, for Silver on it
	var worlds: Dictionary = {}
	for id: String in Cosmetics.ids("hat"):
		var r: Dictionary = Cosmetics.catalogue("hat")[id]["rule"]
		if r["type"] == "medal":
			check(int(r["tier"]) == 2 and not worlds.has(r["level"]), "hat %s: Silver on %s" % [id, r["level"]])
			worlds[r["level"]] = id
	for info: Dictionary in Game.LEVELS:
		check(worlds.has(info["id"]), "%s has its own Silver hat" % info["name"])
	check(worlds.size() == Game.LEVELS.size(), "%d world hats for %d worlds" % [worlds.size(), Game.LEVELS.size()])
	for id: String in ["crown", "halo", "party"]:
		check(Cosmetics.has_item("hat", id), "special hat %s" % id)
	# every rule names a real course
	for kind: String in Cosmetics.kinds():
		for id: String in Cosmetics.ids(kind):
			var r: Dictionary = Cosmetics.catalogue(kind)[id]["rule"]
			var lid: String = str(r.get("level", r.get("id", "")))
			if lid != "":
				check(not Game.level_by_id(lid).is_empty(), "%s %s names a real course (%s)" % [kind, id, lid])
	check(Cosmetics.titled("Ada", "speed_demon") == "Ada · Speed Demon" and Cosmetics.titled("Bo", "???") == "Bo · Rookie", "titled names")


func test_zm_settings_sanitize_reward_ids() -> void:
	var keep: Dictionary = {}
	for kind: String in Cosmetics.kinds():
		keep[kind] = Settings.get(Cosmetics.setting_key(kind))
	Settings.character_id = "dragon"
	Settings.hat_id = ""
	Settings.paint_id = "chrome"
	Settings.title_id = "lap_king"
	Settings.call("_sanitize")
	check(Settings.character_id == "volt" and Settings.hat_id == "none", "unknown character / hat ids fall back to the defaults")
	check(Settings.paint_id == "chrome" and Settings.title_id == "lap_king", "known ids are kept (even if still locked)")
	var path: String = "user://test_settings_rewards.cfg"
	var cf := ConfigFile.new()
	cf.set_value("s", "character_id", 7)
	cf.set_value("s", "hat_id", "witch")
	cf.set_value("s", "paint_id", "polka")
	cf.set_value("s", "title_id", ["x"])
	cf.save(path)
	Settings.load_settings(path)
	check(Settings.character_id == "volt" and Settings.hat_id == "witch" and Settings.paint_id == "white" and Settings.title_id == "lap_king",
		"from a file: wrong types ignored, bad strings reset (%s / %s / %s / %s)" % [Settings.character_id, Settings.hat_id, Settings.paint_id, Settings.title_id])
	for k: String in ["character_id", "hat_id", "paint_id", "title_id"]:
		check(k in Settings._props(), "%s is saved with the settings" % k)
	# a locked pick is never worn
	SaveData.wipe()
	Settings.hat_id = "witch"
	check(Cosmetics.equipped("hat") == "none", "a locked hat in settings wears No Hat")
	SaveData.data["levels"]["manor"] = {"completed": true, "runs": 1, "best": Game.medal_target("manor", 2)}
	check(Cosmetics.equipped("hat") == "witch", "once earned it is worn")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for kind: String in keep:
		Settings.set(Cosmetics.setting_key(kind), keep[kind])
	SaveData.wipe()


func test_zm_stats_and_flawless_gold() -> void:
	SaveData.wipe()
	check(SaveData.stat("laps_dealt") == 0, "a fresh save has no laps dealt")
	SaveData.add_stat("laps_dealt")
	SaveData.add_stat("laps_dealt", 2)
	SaveData.load_data()
	check(SaveData.stat("laps_dealt") == 3, "laps_dealt is counted and saved")
	check(Cosmetics.is_unlocked("hat", "party"), "3 laps dealt unlock the Party Hat from the real save")
	var clean: Dictionary = SaveData._sanitize({"levels": {}, "stats": {"laps_dealt": 4.0, "flawless_golds": -2, "bogus": 9, "runs": "x"}})
	check(clean.get("stats") == {"laps_dealt": 4}, "stats are sanitized to known non-negative counters (%s)" % [clean.get("stats")])
	check(not SaveData._sanitize({"levels": {}, "stats": "nope"}).has("stats"), "a non-dictionary stats entry is dropped")
	# a Gold with falls is not flawless; a flawless Silver is not a Gold
	SaveData.record_finish("gardens", Game.medal_target("gardens", 3) - 1.0, 2)
	SaveData.record_finish("gardens", Game.medal_target("gardens", 2), 0)
	check(SaveData.stat("flawless_golds") == 0, "neither counts as a flawless Gold")
	SaveData.record_finish("gardens", Game.medal_target("gardens", 3) + 5.0, 0)
	SaveData.record_finish("reef", Game.medal_target("reef", 3), 0)
	check(SaveData.stat("flawless_golds") == 1 and Cosmetics.is_unlocked("hat", "halo"), "a Gold with no falls counts and unlocks the Halo")
	SaveData.wipe()


## A race level with Ada (2) and Bo (3) registered with every cosmetic.
func _zm_race_level() -> LevelBase:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	check(Net.host(24611) == OK, "hosting a race")
	Net._register_player(2, "Ada", 1, {"character": "ninja", "hat": "witch", "paint": "chrome", "trail": "wisps", "finish": "ghost", "title": "speed_demon"})
	Net._register_player(3, "Bo", 2, {"character": "dragon", "hat": 5, "title": "<b>"})
	for id: int in [2, 3]:
		Net.roster[id]["cp_at"] = 0.0
	Game.level_index = 0
	Game.race_mode = true
	Net.race_start_time = Net.now() - 1.0
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	return lvl


func _zm_end_race() -> void:
	Net.leave()
	Game.race_mode = false
	if world != null:
		world.queue_free()
		world = null
	await ticks(2)


func test_zm_remote_racer_all_ids() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var r := RemoteRacer.new()
	add_child(r)
	await ticks(1)
	r.setup("Ada", Settings.RACER_COLORS[1])
	r.apply_cosmetics({"character": "astronaut", "hat": "cowboy", "paint": "lava", "trail": "frost", "finish": "jet", "title": "lap_king"})
	var v: PlayerVisual = r.visual()
	check(v.character_id == "astronaut" and v.hat_id == "cowboy" and v.paint_id == "lava" and v.trail_id == "frost" and v.finish_id == "jet",
		"a remote racer wears every id they sent")
	check(v.hat_node() != null and v.head_anchor().is_ancestor_of(v.hat_node()), "the hat hangs off the head anchor")
	check(r.title_id == "lap_king" and r._label.text == "Ada\nLap King", "the name tag shows the title (%s)" % r._label.text.c_escape())
	r.apply_cosmetics({"character": "<script>", "hat": 7, "paint": null, "title": "emperor"})
	check(v.character_id == "volt" and v.hat_id == "none" and v.paint_id == "white" and v.trail_id == "classic" and v.finish_id == "cheer" and r.title_id == "rookie",
		"unknown or missing ids fall back to every default")
	check(v.hat_node() == null, "No Hat removes the hat")
	r.set_team("Red", Color.RED)
	check(r._label.text == "Ada  [Red]\nRookie", "team tags keep the title (%s)" % r._label.text.c_escape())
	r.queue_free()
	# registration, the relay JSON roster and the race ghosts carry every kind
	var lvl: LevelBase = await _zm_race_level()
	for kind: String in Cosmetics.kinds():
		check(Net.roster[1].has(kind), "the host's own entry carries its %s" % kind)
		check(Net._register_data().get(kind) == Cosmetics.equipped(kind), "our relay registration sends our %s" % kind)
		check(Net._my_cosmetics().get(kind) == Cosmetics.equipped(kind), "our direct registration sends our %s" % kind)
	check(Net.roster[2]["character"] == "ninja" and Net.roster[2]["hat"] == "witch" and Net.roster[2]["paint"] == "chrome" and Net.roster[2]["title"] == "speed_demon",
		"registration stores character / hat / paint / title")
	check(Net.roster[3]["character"] == "volt" and Net.roster[3]["hat"] == "none" and Net.roster[3]["paint"] == "white" and Net.roster[3]["title"] == "rookie",
		"an older client (no keys) or junk ids register as the defaults")
	var wire: Variant = JSON.parse_string(JSON.stringify({"players": Net._roster_to_wire()}))
	var back: Dictionary = Net._roster_from_wire((wire as Dictionary)["players"])
	check(back.has(2) and back[2]["hat"] == "witch" and back[2]["title"] == "speed_demon" and back[2]["character"] == "ninja", "the ids survive the relay's JSON roster")
	var g: RemoteRacer = lvl._ghosts.get(2)
	check(g != null and g.visual().character_id == "ninja" and g.visual().hat_id == "witch" and g.visual().paint_id == "chrome" and g.title_id == "speed_demon",
		"the race ghost wears Ada's character, hat, paint and title")
	var g3: RemoteRacer = lvl._ghosts.get(3)
	check(g3 != null and g3.visual().character_id == "volt" and g3.visual().hat_id == "none", "Bo's ghost wears the defaults")
	await _zm_end_race()


func test_zm_titles_on_roster_and_board() -> void:
	var lvl: LevelBase = await _zm_race_level()
	lvl.hud._rebuild_board()
	var board: String = ""
	for l: Node in lvl.hud._board.get_children():
		board += (l as Label).text + "|"
	check(board.contains("Ada · Speed Demon") and board.contains("Bo · Rookie"), "the race board shows titles (%s)" % board)
	await _zm_end_race()
	# the lobby roster
	check(Net.host(24612) == OK, "hosting a lobby")
	Net._register_player(2, "Ada", 1, {"title": "gold_rush"})
	Game.title_screen = "lobby"
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	title.set("persist_settings", false)
	add_child(title)
	await ticks(4)
	var roster: String = ""
	for l: Node in (title.get("_screen") as Control).find_children("*", "Label", true, false):
		roster += (l as Label).text + "|"
	check(roster.contains("Ada · Gold Rush") and roster.contains("%s · " % Settings.player_name), "the lobby roster shows titles (%s)" % roster)
	title.queue_free()
	await ticks(2)
	Net.leave()
	Game.title_screen = "main"


func test_zm_laps_dealt_counts_in_race() -> void:
	SaveData.wipe()
	var lvl: LevelBase = await _zm_race_level()
	var me: int = Net.my_id()
	Net.roster[me]["finished"] = 40.0
	Net._apply_lap_msg(me, {"k": "x", "victim": 2, "count": 1})
	check(SaveData.stat("laps_dealt") == 1 and lvl.hud._toast.text == "You lapped Ada", "lapping Ada counts a lap dealt (%d)" % SaveData.stat("laps_dealt"))
	Net._apply_lap_msg(me, {"k": "x", "victim": 2, "count": 2})
	Net._apply_lap_msg(me, {"k": "x", "victim": 3, "count": 1})
	check(SaveData.stat("laps_dealt") == 3, "every lap dealt counts (%d)" % SaveData.stat("laps_dealt"))
	Net._apply_lap_msg(me, {"k": "x", "victim": 3, "count": 1})
	check(SaveData.stat("laps_dealt") == 3, "a repeated lap message is not counted twice")
	# being lapped is not dealing a lap
	Net.roster[2]["finished"] = 41.0
	Net.roster[me]["finished"] = -1.0
	Net._apply_lap_msg(2, {"k": "x", "victim": me, "count": 1})
	check(SaveData.stat("laps_dealt") == 3, "being lapped counts nothing")
	await seconds(2.3)
	check(lvl.hud._toast.text == "Unlocked: Party Hat!", "the third lap announces the Party Hat (%s)" % lvl.hud._toast.text)
	await _zm_end_race()
	SaveData.wipe()


func test_zm_results_medal_and_banner() -> void:
	await new_world()
	world.queue_free()
	world = null
	SaveData.wipe()
	Game.level_index = 0
	Game.race_mode = false
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var id: String = lvl.level_id
	# a first clear in Silver time: the panel names the medal and the Gold target
	var t_silver: float = Game.medal_target(id, 2) - 2.0
	var prev: int = SaveData.medal(id)
	SaveData.record_finish(id, t_silver, 3)
	lvl.hud.show_results(t_silver, -1.0, true, 3, -1, prev)
	var ml: Label = lvl.hud._medal_label
	check(ml != null and ml.text == "NEW SILVER MEDAL", "the results panel shows the new medal (%s)" % (ml.text if ml != null else "none"))
	check(lvl.hud._medal_next != null and lvl.hud._medal_next.text == "Next: Gold %s" % Hud.target_text(Game.medal_target(id, 3)), "... and the next target")
	check(lvl.hud._flash.color.a > 0.2, "a new medal flashes the screen")
	await seconds(0.9)   # (the panel's buttons go live first)
	lvl.hud._results.queue_free()
	lvl.hud._results = null
	# a slower run: its own medal, no NEW, the target still Gold
	prev = SaveData.medal(id)
	SaveData.record_finish(id, Game.medal_target(id, 1), 1)
	lvl.hud.show_results(Game.medal_target(id, 1), t_silver, false, 1, 3, prev)
	check(lvl.hud._medal_label.text == "BRONZE MEDAL", "a slower run shows its own medal without NEW (%s)" % lvl.hud._medal_label.text)
	await seconds(0.9)   # (the panel's buttons go live first)
	lvl.hud._results.queue_free()
	lvl.hud._results = null
	prev = SaveData.medal(id)
	SaveData.record_finish(id, 900.0, 1)
	lvl.hud.show_results(900.0, t_silver, false, 1, 1, prev)
	check(lvl.hud._medal_label.text == "No medal this run", "too slow: no medal")
	await seconds(0.9)   # (the panel's buttons go live first)
	lvl.hud._results.queue_free()
	lvl.hud._results = null
	# Gold, as the fifth: the unlock toast (Chrome / Speed Demon) becomes the medal banner
	for other: String in ["foundry", "balance", "clockwork", "reef"]:
		SaveData.data["levels"][other] = {"completed": true, "runs": 1, "best": Game.medal_target(other, 3)}
	Cosmetics.check_unlocks()   # (announce what those earned first)
	prev = SaveData.medal(id)
	lvl.deaths = 4
	lvl.run_time = Game.medal_target(id, 3) - 1.0
	lvl._on_finish()
	await seconds(1.2)
	check(lvl.hud._medal_label != null and lvl.hud._medal_label.text == "NEW GOLD MEDAL" and lvl.hud._medal_next == null, "Gold: nothing further to chase")
	await seconds(0.6)
	# over the open results panel the banner sits inside it, above the buttons (not behind it)
	var banner: String = ""
	if lvl.hud._results_box != null:
		for n: Node in lvl.hud._results_box.find_children("*", "Label", true, false):
			if (n as Label).text.begins_with("GOLD! New reward: "):
				banner = (n as Label).text
	check(banner != "", "the first unlock is the medal banner, inside the results panel (%s)" % banner)
	var buttons_after: bool = true
	if lvl.hud._results_box != null:
		var seen_note: bool = false
		for c: Node in lvl.hud._results_box.get_children():
			if c is VBoxContainer and c.find_children("*", "Label", true, false).any(func(l: Node) -> bool: return (l as Label).text.begins_with("GOLD!")):
				seen_note = true
			elif c is Button and not seen_note:
				buttons_after = false
	check(buttons_after, "the banner comes before the buttons")
	world.queue_free()
	world = null
	await ticks(2)
	SaveData.wipe()


func test_zm_player_visual_hooks() -> void:
	await new_world()
	var v := PlayerVisual.new()
	v.set_hat("crown")   # before _ready: applied when the rig is built
	v.set_paint("ghost")
	world.add_child(v)
	await ticks(1)
	check(v.head_anchor() != null and v.hat_node() != null and v.hat_id == "crown", "a hat picked before the rig exists is mounted on build")
	var ghost: Material = v.paint_parts()[0].material_override if not v.paint_parts().is_empty() else null
	check(ghost is ShaderMaterial and (ghost as ShaderMaterial).shader.code.contains("ALPHA"), "the Ghost paint is see-through")
	var e0: int = trap.count()
	for c: String in Cosmetics.ids("character"):
		v.set_character(c)
		for h: String in Cosmetics.ids("hat"):
			v.set_hat(h)
			check((h == "none") == (v.hat_node() == null), "%s wears hat %s" % [c, h])
		for p: String in Cosmetics.ids("paint"):
			v.set_paint(p)
		for i: int in 30:
			v.animate(1.0 / 60.0, Vector3(6, 0, 0) if i < 20 else Vector3(0, 9, 0), i < 20, Vector3.FORWARD)
		v.on_jump()
		v.on_land(8.0)
		v.on_cheer()
		await ticks(1)
	check(trap.count() == e0, "every character x hat x paint applies and animates without errors %s" % trap.since(e0))
	v.set_character("zzz")
	v.set_hat("zzz")
	v.set_paint("zzz")
	check(v.character_id == "volt" and v.hat_id == "none" and v.paint_id == "white", "unknown ids fall back to the defaults")
	await ticks(1)
	var hats: int = 0
	for n: Node in v.head_anchor().get_children():
		if not n.is_queued_for_deletion():
			hats += 1
	check(hats == 0, "old hats are removed, not stacked (%d left)" % hats)
	world.queue_free()
	world = null
	await ticks(2)


## The character art pass: every body has the named parts the animation drives, every hat
## sits on every head at a sane height, every paint covers the shell (and only the shell),
## picks survive a body swap, the full move cycle animates cleanly, remote racers wear it all
## and no body + hat goes over the mesh budget.
const ZM_MESH_BUDGET: int = 40

func test_zm_character_art() -> void:
	await new_world()
	var e0: int = trap.count()
	# a rig that is never animated: rest-pose measurements
	var r := PlayerVisual.new()
	world.add_child(r)
	await ticks(1)
	var worst: int = 0
	var worst_what: String = ""
	var paint_mats: Array[Material] = []
	for p: String in Cosmetics.ids("paint"):
		var m: Material = CosmeticArt.paint_material(p)
		check((p == "white") == (m == null), "paint %s has its own material (white is the factory finish)" % p)
		if m != null:
			paint_mats.append(m)
			check(m == CosmeticArt.paint_material(p), "paint %s is cached" % p)
	for c: String in Cosmetics.ids("character"):
		r.set_character(c)
		await ticks(1)
		check(r.built_character == c, "%s builds its own body" % c)
		_zm_check_named_parts(r, c)
		var accents: Array[Material] = [r.accent_material("base"), r.accent_material("dark"), r.accent_material("hand"), r.accent_material("glow"), r._bulb_mat]
		var shows_accent: bool = false
		for mi: MeshInstance3D in _zm_meshes(r._root):
			if mi.is_visible_in_tree() and mi.material_override in accents:
				shows_accent = true
		check(shows_accent, "%s shows the racer colour somewhere" % c)
		var body_top: float = _zm_aabb(r._body).end.y
		var anchor_y: float = r.head_anchor().global_position.y
		check(anchor_y >= body_top - 0.06 and anchor_y < body_top + 0.45, "%s: the hat anchor sits on the head (anchor %.2f, body top %.2f)" % [c, anchor_y, body_top])
		var base_count: int = _zm_meshes(r._root).size()
		metrics["zm_meshes_" + c] = base_count
		for h: String in Cosmetics.ids("hat"):
			if h == "none":
				continue
			r.set_hat(h)
			var box: AABB = _zm_aabb(r.hat_node())
			var sane: bool = box.size != Vector3.ZERO and box.end.y > body_top + 0.01 and box.position.y > anchor_y - 0.6 and box.end.y < anchor_y + 0.8
			check(sane, "%s's %s sits on the head (hat %.2f..%.2f, anchor %.2f, body top %.2f)" % [c, h, box.position.y, box.end.y, anchor_y, body_top])
			var n: int = _zm_meshes(r._root).size()
			if n > worst:
				worst = n
				worst_what = "%s + %s" % [c, h]
		for p: String in Cosmetics.ids("paint"):
			r.set_paint(p)
			var want: Material = CosmeticArt.paint_material(p)
			var ok: bool = not r.paint_parts().is_empty() and r.paint_parts().has(r._body)
			for mi: MeshInstance3D in r.paint_parts():
				if want != null and mi.material_override != want:
					ok = false
				if want == null and mi.material_override in paint_mats:
					ok = false
			# the eyes, visor and accent pieces never take the paint
			for mi: MeshInstance3D in [r._eye_l, r._eye_r, r._hand_l, r._hand_r]:
				if mi.material_override in paint_mats:
					ok = false
			check(ok, "%s wears the %s paint on its shell only" % [c, p])
	metrics["zm_meshes_worst"] = "%d (%s)" % [worst, worst_what]
	check(worst <= ZM_MESH_BUDGET, "every body + hat stays within %d meshes (worst %d: %s)" % [ZM_MESH_BUDGET, worst, worst_what])
	# a body swap keeps the hat and the paint
	r.set_hat("viking")
	r.set_paint("lava")
	for c: String in Cosmetics.ids("character"):
		r.set_character(c)
		var kept: bool = r.hat_id == "viking" and r.hat_node() != null and r.head_anchor().is_ancestor_of(r.hat_node())
		for mi: MeshInstance3D in r.paint_parts():
			kept = kept and mi.material_override == CosmeticArt.paint_material("lava")
		check(kept, "switching to %s keeps the Viking Helmet and the Lava paint" % c)
	# no leaks: back on Volt with no hat, the rig is the size it started at
	r.set_hat("none")
	r.set_character("volt")
	await ticks(1)
	check(_zm_meshes(r._root).size() == int(metrics.get("zm_meshes_volt", -1)), "rebuilding bodies leaves nothing behind (%d meshes)" % _zm_meshes(r._root).size())
	# the racer colour follows set_accent everywhere
	r.set_character("dino")
	r.set_accent(Color(0.2, 0.9, 0.3))
	check(r.accent_material("base").albedo_color.is_equal_approx(Color(0.2, 0.9, 0.3)), "set_accent tints the shared accent materials")
	r.set_character("volt")
	r.set_hat("tophat")
	var hidden: bool = not r._antenna.visible
	r.set_hat("halo")
	check(hidden and r._antenna.visible, "a covering hat hides Volt's antenna; the halo leaves it showing")
	r.set_hat("none")
	# the full move cycle on every body, wearing something that moves
	var v := PlayerVisual.new()
	world.add_child(v)
	await ticks(1)
	var hat_cycle: Array[String] = ["propeller", "halo", "antennae", "tophat", "witch"]
	var paint_cycle: Array[String] = ["galaxy", "lava", "neon", "ghost", "camo", "candy", "chrome", "white"]
	var ci: int = 0
	for c: String in Cosmetics.ids("character"):
		v.set_character(c)
		v.set_hat(hat_cycle[ci % hat_cycle.size()])
		v.set_paint(paint_cycle[ci % paint_cycle.size()])
		ci += 1
		var finite: bool = await _zm_move_cycle(v)
		check(finite, "%s runs, jumps, wall runs, mantles, respawns and cheers with a finite pose" % c)
	# secondary motion: the propeller spins with speed, the halo floats, a tail swings
	v.set_character("dino")
	v.set_hat("propeller")
	var spinner: Node3D = v._hat_spin[0] if not v._hat_spin.is_empty() else null
	var tail: Node3D = v._sways[0].node if not v._sways.is_empty() else null
	check(spinner != null and tail != null, "the propeller and the dino's tail are animated parts")
	if spinner != null and tail != null:
		var b0: Basis = spinner.basis
		var t0: Vector3 = tail.rotation
		for i: int in 20:
			v.animate(1.0 / 60.0, Vector3(0, 0, -10), true, Vector3.FORWARD)
		check(not spinner.basis.is_equal_approx(b0), "the propeller turns")
		check(not tail.rotation.is_equal_approx(t0), "the tail swings")
	v.set_hat("halo")
	var bob: Node3D = v._hat_bob
	var y0: float = bob.position.y if bob != null else 0.0
	for i: int in 30:
		v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(bob != null and not is_equal_approx(bob.position.y, y0), "the halo floats")
	# a remote racer builds what it was sent, and animates it
	var rr := RemoteRacer.new()
	world.add_child(rr)
	await ticks(1)
	rr.setup("Ada", Settings.RACER_COLORS[2])
	rr.apply_cosmetics({"character": "skeleton", "hat": "pharaoh", "paint": "galaxy"})
	var rv: PlayerVisual = rr.visual()
	var dressed: bool = rv.built_character == "skeleton" and rv.hat_node() != null and rv.head_anchor().is_ancestor_of(rv.hat_node())
	for mi: MeshInstance3D in rv.paint_parts():
		dressed = dressed and mi.material_override == CosmeticArt.paint_material("galaxy")
	check(dressed, "a remote racer builds the Skeleton in the Pharaoh Headdress and Galaxy paint")
	for i: int in 6:
		rr.push_state(Vector3(0, 0.05, -float(i) * 0.3), Vector3(0, 0, -9), true, 1)
		await ticks(2)
	rr.apply_cosmetics({"character": "astronaut", "hat": "bubble", "paint": "chrome"})
	check(rv.built_character == "astronaut" and rv.hat_id == "bubble" and rv.paint_parts()[0].material_override == CosmeticArt.paint_material("chrome"),
		"a remote racer re-dresses when its picks change")
	check(trap.count() == e0, "the character art builds and animates without errors %s" % trap.since(e0))
	world.queue_free()
	world = null
	await ticks(2)


func _zm_check_named_parts(v: PlayerVisual, c: String) -> void:
	var live := func(n: Node) -> bool: return n != null and is_instance_valid(n) and n.is_inside_tree() and not n.is_queued_for_deletion()
	var belt: Node = v._torso.get_node_or_null("Belt")
	var pack: Node = v._torso.get_node_or_null("Pack")
	var ok: bool = live.call(v._body) and belt is MeshInstance3D and live.call(belt) and pack is MeshInstance3D and live.call(pack)
	ok = ok and live.call(v._eye_l) and live.call(v._eye_r) and live.call(v._antenna) and live.call(v._bulb) and v._bulb_mat != null
	ok = ok and live.call(v._foot_l) and live.call(v._foot_r) and live.call(v._hand_l) and live.call(v._hand_r)
	ok = ok and live.call(v._head_anchor) and v._head_anchor.get_parent() == v._torso
	ok = ok and v._eye_l.get_parent() == v._torso and v._antenna.is_ancestor_of(v._bulb)
	ok = ok and v._foot_l.get_parent() == v._rig and v._hand_l.get_parent() == v._rig
	check(ok, "%s has every named part the animation drives" % c)


## Every MeshInstance3D under `n` that is not on its way out.
func _zm_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var k: Node = stack.pop_back()
		if k.is_queued_for_deletion():
			continue
		if k is MeshInstance3D:
			out.append(k)
		stack.append_array(k.get_children())
	return out


## World-space bounds of the visible meshes under `n` (n itself included).
func _zm_aabb(n: Node) -> AABB:
	var box := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _zm_meshes(n):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Run, jump, land, wall run + wall jump, mantle, a pad launch, a knock, respawn, a checkpoint,
## the finish cheer and an idle long enough for fidgets; true when the pose stays finite.
func _zm_move_cycle(v: PlayerVisual) -> bool:
	var dt: float = 1.0 / 60.0
	var fwd := Vector3.FORWARD
	var finite: bool = true
	var step := func(n: int, vel: Vector3, floor_on: bool) -> void:
		for i: int in n:
			v.animate(dt, vel, floor_on, fwd)
	step.call(40, Vector3(0, 0, -9), true)
	v.on_jump()
	for i: int in 30:
		v.animate(dt, Vector3(0, 9.0 - float(i) * 0.6, -9), false, fwd)
	v.on_land(16.0)
	step.call(10, Vector3(0, 0, -9), true)
	v.on_wall_run(Vector3.RIGHT)
	v.wall_roll = -1.0
	step.call(30, Vector3(0, 0.5, -10), true)
	v.wall_roll = 0.0
	v.on_wall_jump()
	step.call(20, Vector3(4, 6, -8), false)
	v.on_mantle()
	v.on_mantle_grab(v.global_position + Vector3(0, 1.2, -0.5), Vector3.FORWARD)
	step.call(50, Vector3(0, 2, -1), false)
	v.on_land(4.0)
	v.on_bounce(22.0)
	step.call(40, Vector3(0, 14, -6), false)
	v.on_knock(Vector3(8, 4, 0))
	step.call(30, Vector3(4, -6, 0), false)
	v.on_respawn()
	step.call(30, Vector3.ZERO, true)
	v.on_checkpoint()
	step.call(30, Vector3(0, 0, -6), true)
	v.on_cheer()
	step.call(230, Vector3.ZERO, true)
	step.call(260, Vector3.ZERO, true)   # idle: fidgets
	await ticks(1)
	for mi: MeshInstance3D in _zm_meshes(v._root):
		if not (mi.global_transform.origin.is_finite() and mi.global_transform.basis.x.is_finite() and mi.global_transform.basis.y.is_finite()):
			finite = false
	return finite


func test_zm_locker_tabs() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var keep: Dictionary = {}
	for kind: String in Cosmetics.kinds():
		keep[kind] = Settings.get(Cosmetics.setting_key(kind))
	var keep_colour: int = Settings.color_index
	SaveData.wipe()
	# Silver on Phantom Manor: the Witch Hat and the Ghost paint
	SaveData.data["levels"]["manor"] = {"completed": true, "runs": 1, "best": Game.medal_target("manor", 2)}
	for kind: String in Cosmetics.kinds():
		Settings.set(Cosmetics.setting_key(kind), Cosmetics.default_id(kind))
	Game.title_screen = "locker"
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	title.set("persist_settings", false)
	add_child(title)
	await ticks(3)
	var send := func(button: JoyButton) -> void:
		var ev := InputEventJoypadButton.new()
		ev.device = 1
		ev.button_index = button
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		var up: InputEventJoypadButton = ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await ticks(2)
	var focus := func() -> Control:
		return get_viewport().gui_get_focus_owner()
	var info: Label = title.get("_locker_info")
	var volt: PlayerVisual = title.get("_volt")
	check(focus.call() != null and focus.call().get_meta("kind", "") == "character", "the Locker opens on the Character tab")
	# a locked character names its unlock and progress
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	check(focus.call().get_meta("item", "") == "knight" and info.text.begins_with("LOCKED") and info.text.contains("Bronze or better on 10 courses") and info.text.contains("Bronzes 1/10"),
		"a locked character shows its hint and progress (%s)" % info.text)
	check(volt.character_id == "knight", "focusing a character previews it")
	await send.call(JOY_BUTTON_A)
	check(Settings.character_id == "volt", "a locked character cannot be equipped")
	# LB wraps round to Colour
	await send.call(JOY_BUTTON_LEFT_SHOULDER)
	check(int(title.get("locker_tab")) == 6 and focus.call() != null and focus.call().has_meta("colour"),
		"LB from the first tab wraps to Colour, on a swatch")
	check(int(focus.call().get_meta("colour")) == Settings.color_index, "... the worn colour")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	await send.call(JOY_BUTTON_A)
	check(Settings.color_index == posmod(keep_colour + 1, Settings.RACER_COLORS.size()) or Settings.color_index == (int(focus.call().get_meta("colour"))),
		"A on a swatch picks the colour")
	check(volt.character_id == "volt", "leaving the tab puts the worn character back on the preview")
	# RB wraps to Character, again to Hat
	await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	check(focus.call().get_meta("kind", "") == "character", "RB from Colour wraps to Character")
	await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	check(focus.call().get_meta("kind", "") == "hat" and focus.call().get_meta("item", "") == "none", "RB: the Hat tab, on No Hat")
	# 5 hats a row: the Witch Hat is row 3, column 2
	for b: JoyButton in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT]:
		await send.call(b)
	check(focus.call().get_meta("item", "") == "witch" and volt.hat_id == "witch" and volt.hat_node() != null, "the D-pad reaches the Witch Hat and the preview wears it")
	check(not info.text.begins_with("LOCKED"), "Silver on Phantom Manor owns the Witch Hat (%s)" % info.text)
	await send.call(JOY_BUTTON_A)
	check(Settings.hat_id == "witch" and (focus.call() as Button).text == "> Witch Hat <", "A equips it")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	check(info.text.begins_with("LOCKED") and info.text.contains("Silver or better on Storm Armada") and info.text.contains("best: no medal"),
		"the next hat is locked with its hint (%s)" % info.text)
	# Paint tab: Ghost
	await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	check(focus.call().get_meta("kind", "") == "paint" and volt.hat_id == "witch", "RB: the Paint tab (the preview keeps the equipped hat)")
	# 4 paints a row: Ghost is row 2, column 3
	for b: JoyButton in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT]:
		await send.call(b)
	await send.call(JOY_BUTTON_A)
	check(Settings.paint_id == "ghost" and volt.paint_id == "ghost", "the Ghost paint equips and shows")
	# Title tab (RB x3: Trail, Finish, Title)
	for i: int in 3:
		await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	check(focus.call().get_meta("kind", "") == "title" and focus.call().get_meta("item", "") == "rookie", "RB x3: the Title tab, on Rookie")
	check(info.text.contains("%s · Rookie" % Settings.player_name), "a title previews beside your name (%s)" % info.text)
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	check(info.text.begins_with("LOCKED") and info.text.contains("Beat all"), "Globetrotter is locked with its hint (%s)" % info.text)
	# the tab bar is mouse-only: clicking a tab button switches too
	var tabs: Node = (title.get("_screen") as Control).find_child("Tabs", true, false)
	(tabs.get_child(1) as Button).pressed.emit()
	await ticks(2)
	check(focus.call().get_meta("kind", "") == "hat" and focus.call().get_meta("item", "") == "witch", "clicking the Hat tab opens it on the equipped hat")
	check((tabs.get_child(1) as Button).focus_mode == Control.FOCUS_NONE, "tab buttons never take pad focus")
	await send.call(JOY_BUTTON_B)
	await ticks(2)
	check(Game.title_screen == "main", "B leaves the Locker from any tab")
	check(volt.hat_id == "witch" and volt.paint_id == "ghost", "the title Volt wears the equipped hat and paint")
	title.queue_free()
	await ticks(2)
	for kind: String in keep:
		Settings.set(Cosmetics.setting_key(kind), keep[kind])
	Settings.color_index = keep_colour
	Net.preferred_color = -1
	Game.title_screen = "main"
	SaveData.wipe()


## Polish audit: nobody is charged a fall just for loading a course (the player sits at the
## world origin for a tick before the spawn teleport; a kill zone there used to count it).
func test_zz_no_fall_charged_at_load() -> void:
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		var lvl: LevelBase = await load_level(i)
		await seconds(1.0)
		check(lvl.deaths == 0, "%s: no fall counted while standing at the start (%d)" % [Game.LEVELS[i]["name"], lvl.deaths])
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
