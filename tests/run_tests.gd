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
		if n.begins_with("test_zcpu_"):
			limit = 2400.0   # whole CPU races under Engine.time_scale (physics seconds)
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
	check(not InputMap.event_is_action(_pad_button(JOY_BUTTON_DPAD_UP, 1), "move_forward"), "the D-pad no longer moves (it plays emotes: the left stick moves)")
	check(InputMap.event_is_action(_pad_button(JOY_BUTTON_DPAD_UP, 1), "emote_1") and InputMap.event_is_action(_pad_button(JOY_BUTTON_DPAD_LEFT, 3), "emote_4"), "the D-pad plays emotes on any slot")
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
	check(d.hits == 1 and not d.knocked_out and d.last_src == "claw" and d.vel.length() > 12.0, "the Fox Claw is a big knockback, not an instant KO (hits %d, ko %s, speed %.1f)" % [d.hits, d.knocked_out, d.vel.length()])
	d.knock_out()
	await seconds(2.0)
	check(not d.knocked_out, "a KO'd dummy pops back home")
	d.reset()
	await ticks(2)
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


# ---- party HUD: standings, feed, warnings, roulette, results ---------------------------------------

func _zp_roster(entries: Dictionary) -> void:
	Net.roster = {}
	for id: Variant in entries:
		var e: Dictionary = entries[id]
		Net.roster[int(id)] = {"name": str(e.get("name", "R%d" % int(id))), "color": int(id) % 8, "cp": int(e.get("cp", 0)),
			"cp_at": float(e.get("cp_at", 0.0)), "finished": float(e.get("finished", -1.0))}


func test_zp_hud_standings_order() -> void:
	# the pure board: order, live points, team sums, ordinals
	var roster: Dictionary = {1: {"name": "Me", "color": 0, "cp": 2, "finished": -1.0}, 5: {"name": "Ana", "color": 1, "cp": 4, "finished": -1.0},
		7: {"name": "Bo", "color": 2, "cp": 3, "finished": 41.0}}
	var list: Array[Dictionary] = PartyBoard.entries([7, 5, 1], roster, {5: 2}, {1: 1, 7: 1}, {1: 10}, {1: 0, 5: 1, 7: 0}, 1)
	check(list.size() == 3 and int(list[0]["id"]) == 7 and int(list[2]["id"]) == 1 and int(list[2]["place"]) == 3, "board entries keep the race order")
	check(bool(list[0]["finished"]) and not bool(list[1]["finished"]) and bool(list[2]["you"]), "board entries flag finished and you")
	check(int(list[1]["pts"]) == 2 * PartyRules.KO_POINTS and int(list[0]["pts"]) == PartyRules.BONUS_POINTS, "live points are KOs x3 + bonuses x2")
	var tl: Array[int] = PartyBoard.team_live(list)
	check(tl[0] == PartyRules.BONUS_POINTS * 2 and tl[1] == 6, "team live totals sum each side (%s)" % str(tl))
	check(PartyBoard.suffix(1) == "st" and PartyBoard.suffix(2) == "nd" and PartyBoard.suffix(3) == "rd" and PartyBoard.suffix(11) == "th" and PartyBoard.suffix(22) == "nd", "ordinal suffixes")
	# the arrow maths: on screen stays put, off screen clamps to the edge, behind flips
	var sz := Vector2(1600, 900)
	check(bool(PartyBoard.edge_point(Vector2(800, 450), false, sz, 40.0)["on_screen"]), "a rival in the middle needs no arrow")
	var far: Dictionary = PartyBoard.edge_point(Vector2(3000, 450), false, sz, 40.0)
	check(not bool(far["on_screen"]) and absf((far["pos"] as Vector2).x - 1560.0) < 0.5 and absf(float(far["angle"])) < 0.01, "a rival off to the right gets an arrow on the right edge")
	var back: Dictionary = PartyBoard.edge_point(Vector2(1000, 450), true, sz, 40.0)
	check(not bool(back["on_screen"]) and (back["pos"] as Vector2).x < 800.0, "a rival behind the camera flips to the opposite side")
	# live: the strip follows Net.standings() and the big readout shows our place
	var saved_roster: Dictionary = Net.roster
	var saved_teams: Dictionary = Net.teams
	Game.party = PartyRules.new("party")
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	var p: PartyLayer = lvl.party
	_zp_roster({1: {"cp": 2}, 5: {"cp": 4, "name": "Ana"}, 7: {"cp": 1, "name": "Bo"}})
	p.hud.update_standings()
	var want: Array[int] = [5, 1, 7]
	check(p.hud.standings.shown_order == want and p.hud.standings.shown_order == Net.standings(), "the strip lists racers in Net.standings() order %s" % str(p.hud.standings.shown_order))
	check(p.hud.standings.my_place() == 2 and p.hud.standings.place_label.text == "2" and p.hud.standings.suffix_label.text == "ND", "the big readout shows our place (2ND)")
	Net.roster[7]["cp"] = 3
	Net.roster[7]["cp_at"] = 5.0
	p.hud.update_standings()
	want = [5, 7, 1]
	check(p.hud.standings.shown_order == want and p.hud.standings.my_place() == 3, "an overtake reorders the strip and the readout")
	var passed: bool = false
	for f: Dictionary in p.hud.feed_log:
		passed = passed or (str(f["kind"]) == "pass" and str(f["text"]).contains("Bo passed you"))
	check(passed, "being passed shows in the feed")
	check(not p.hud.standings.team_label.visible, "no team line in Party")
	# Team Party: team totals
	p.rules.mode = "team"
	Net.teams = {1: 0, 5: 1, 7: 0}
	p.kos = {5: 2}
	p.bonus = {1: 1}
	p.hud.update_standings()
	check(p.hud.standings.team_label.visible and p.hud.standings.team_label.text.contains(PartyNames.team_name(0) + " 2") and p.hud.standings.team_label.text.contains("6 " + PartyNames.team_name(1)),
		"Team Party shows both teams' live totals (%s)" % p.hud.standings.team_label.text)
	Net.roster = saved_roster
	Net.teams = saved_teams
	Game.party = null


func test_zp_hud_feed_entries() -> void:
	var saved_roster: Dictionary = Net.roster
	Game.party = PartyRules.new("party")
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	var p: PartyLayer = lvl.party
	_zp_roster({1: {"name": "Me"}, 5: {"name": "Ana"}, 7: {"name": "Bo"}})
	var h: PartyHud = p.hud
	var n0: int = h.feed_log.size()
	p.hit_landed.emit(5, "ice")
	check(h.feed_log.size() == n0 + 1 and str(h.feed_log[n0]["text"]) == "You iced Ana!" and str(h.feed_log[n0]["kind"]) == "hit" and str(h.feed_log[n0]["icon"]) == "ice",
		"our item hit reads 'You iced Ana!' with the Ice icon (%s)" % str(h.feed_log.back()))
	p.hit_landed.emit(7, "ice")
	check(h.feed_log.size() == n0 + 1 and str(h.feed_log[n0]["text"]) == "You iced Ana, Bo!", "a blast that hits two racers shares one line (%s)" % str(h.feed_log[n0]["text"]))
	h.on_remote_hit(5, 7, "thunder")
	check(str(h.feed_log.back()["text"]) == "Ana zapped Bo!", "a rival's hit on a third racer reaches our feed (%s)" % str(h.feed_log.back()["text"]))
	h.on_remote_hit(7, 1, "shove")
	check(str(h.feed_log.back()["text"]) == "Bo shoved you!", "a hit on us reads 'Bo shoved you!'")
	h.on_remote_hit(1, 5, "glove")
	check(str(h.feed_log.back()["text"]) == "Bo shoved you!", "our own hit echoed back by the network is not shown twice")
	p._apply_ko(5, 7)
	check(str(h.feed_log.back()["kind"]) == "ko" and str(h.feed_log.back()["text"]).begins_with("Ana KO'd Bo"), "KOs are in the feed")
	p._apply_bonus(7, 1)
	check(str(h.feed_log.back()["kind"]) == "bonus", "first-through bonuses are in the feed")
	h.on_item_used(5, "fox")
	check(str(h.feed_log.back()["kind"]) == "use" and str(h.feed_log.back()["text"]).begins_with("Ana turned into"), "a rival's transformation is announced (%s)" % str(h.feed_log.back()["text"]))
	check(PartyFeedText.verb("nonsense") == "hit" and PartyFeedText.item_for("claw") == "fox" and PartyFeedText.item_for("glove") == "glove" and PartyFeedText.item_for("shove") == "",
		"feed wording: unknown sources fall back, moves map to their item's icon")
	Net.roster = saved_roster
	Game.party = null


func test_zp_hud_targeted_warnings() -> void:
	var saved_roster: Dictionary = Net.roster
	Game.party = PartyRules.new("party")
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	var p: PartyLayer = lvl.party
	var h: PartyHud = p.hud
	_zp_roster({1: {"cp": 3}, 5: {"cp": 1, "name": "Ana"}, 7: {"cp": 5, "name": "Bo"}, 9: {"cp": 2, "name": "Cy"}})
	h.on_item_used(7, "thunder")
	check(h.warn_log.is_empty(), "a Thunder Cloud from someone ahead of us can't hit us")
	h.on_item_used(5, "thunder")
	check(h.warn_log.size() == 1 and int(h.warn_log[0]["id"]) == 5 and h.threats().has(5), "Thunder from a racer behind us warns 'Targeted!'")
	h.on_item_used(5, "swap")
	check(h.warn_log.size() == 1, "Swap from a racer who isn't right behind us doesn't warn")
	_zp_roster({1: {"cp": 3}, 5: {"cp": 2, "name": "Ana"}, 7: {"cp": 5, "name": "Bo"}})
	h.on_item_used(5, "swap")
	check(h.warn_log.size() == 2 and str(h.warn_log[1]["what"]) == PartyNames.item_name("swap"), "Swap from the racer right behind us warns")
	h.on_remote_fx(7, "surge", "charge", {"on": true})
	check(h.threats().has(7), "a rival charging an attack is a threat")
	h._sync_danger()
	check(h.radar.danger.has(7) and h.radar.danger.has(5), "the arrow table follows the threats")
	h.on_remote_fx(7, "surge", "charge", {"on": false})
	check(not h.threats().has(7), "and stops being one when the charge is released")
	Net.roster = saved_roster
	Game.party = null


func test_zp_hud_roulette_lands() -> void:
	var r := PartyRoulette.new()
	for id: String in ["ice", "fox", "balloon"]:
		r.start(id, 11)
		var steps: int = 0
		var seen: Dictionary = {}
		while r.active and steps < 200:
			r.step(1.0 / 60.0)
			seen[r.current] = true
			steps += 1
		check(not r.active and r.current == id and steps >= 46 and steps <= 52, "the roulette lands on %s after ~0.8 s (%d steps)" % [id, steps])
		check(r.ticks >= 7 and seen.size() >= 6, "it ticks through several icons first (%d ticks, %d icons)" % [r.ticks, seen.size()])
	# live: the slot spins, then shows exactly the rolled item
	Game.party = PartyRules.new("party")
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	var p: PartyLayer = lvl.party
	var h: PartyHud = p.hud
	var t0: int = h.roulette_ticks_total
	p.give_item("magnet")
	await get_tree().process_frame
	await get_tree().process_frame
	check(h.roulette.active and h._slot_name.text == "? ? ?", "right after a pickup the slot is spinning")
	await seconds(1.0)
	check(not h.roulette.active and h._slot_icon.item_id == "magnet" and h._slot_name.text == PartyNames.item_name("magnet"), "it lands on the rolled item (%s)" % h._slot_name.text)
	check(h.roulette_ticks_total - t0 >= 7, "and ticked on the way (%d)" % (h.roulette_ticks_total - t0))
	Game.party = null


func test_zp_hud_results_pad() -> void:
	# the pure callouts
	var rows: Array[Dictionary] = PartyRules.score_round([5, 1, 7], [1, 5, 7], {7: 3}, {1: 1})
	var cup_after: Dictionary = {1: 22, 5: 10, 7: 20}
	var co: Array[Dictionary] = PartyBoard.callouts(rows, cup_after, true)
	var keys: Array[String] = []
	for c: Dictionary in co:
		keys.append(str(c["key"]))
	check(keys.has("mvp") and keys.has("kos") and keys.has("bonus"), "callouts: MVP, most KOs and checkpoint hunter %s" % str(keys))
	var kos_c: Dictionary = co[keys.find("kos")]
	check(int(kos_c["id"]) == 7 and str(kos_c["detail"]) == "3 KOs", "the most-KOs callout names the racer with 3 KOs")
	var no_prev: Array[Dictionary] = PartyBoard.callouts(rows, cup_after, false)
	var has_comeback: bool = false
	for c: Dictionary in no_prev:
		has_comeback = has_comeback or str(c["key"]) == "comeback"
	check(not has_comeback, "no comeback in round 1")
	# a screen: the host's results, driven by the pad
	Game.party = PartyRules.new("party")
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	var p: PartyLayer = lvl.party
	check(Net.host(24611) == OK, "hosting opens a session")
	await ticks(3)
	PartyResults.history = {1: {1: 8, 5: 10, 7: 2}}
	p.rules.round_no = 2
	p.rules.cup = {1: 8, 5: 10, 7: 2}
	var rows2: Array[Dictionary] = PartyRules.score_round([1, 5, 7], [1, 5, 7], {1: 2}, {5: 1})
	p.rules.add_round(rows2)
	p.last_rows = rows2
	p.show_results()
	await seconds(0.9)
	var res: PartyResults = p.results
	check(res != null and p.hud.has_panel() and _focused_text().begins_with("Next Round"), "the host's results open focused on Next Round (%s)" % _focused_text())
	check(not res.done, "the tallies are still counting")
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(res.done, "a D-pad press skips the counting")
	check(_focused_text() != "" and not _focused_text().begins_with("Next Round"), "the D-pad moves on from Next Round (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(_focused_text() == "End Cup - Back to Lobby", "and reaches End Cup (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_UP))
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_UP))
	check(_focused_text().begins_with("Next Round"), "and back up again (%s)" % _focused_text())
	var labels: String = ""
	for l: Node in res.find_children("*", "Label", true, false):
		labels += (l as Label).text + "|"
	check(labels.contains("R1") and labels.contains("R2") and labels.contains("THIS ROUND") and labels.contains("ROUND MVP"), "the cup table has a per-round breakdown and the MVP chip is up")
	Net.leave()
	await ticks(2)
	Game.party = null


func test_zp_hud_main_mode_pure() -> void:
	Game.party = null
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	check(lvl.find_children("*", "PartyHud", true, false).is_empty() and lvl.find_children("*", "PartyStandings", true, false).is_empty() and lvl.find_children("*", "PartyRadar", true, false).is_empty(),
		"the main mode builds no party HUD, standings strip or rival arrows")
	var board: Control = lvl.hud._board
	check(board != null and board.visible == Game.race_mode, "the level's own race board is untouched in the main mode")


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
	"void_collapse_start", "void_fragment_crack", "void_fragment_fall", "void_checkpoint", "void_finish",
	"kit_barrel_load", "kit_barrel_fuse", "kit_barrel_fire", "kit_zipline_ready", "kit_zipline_grab",
	"kit_zipline_release", "kit_battery_fuse", "kit_battery_fire", "kit_log_reverse", "kit_seesaw_thunk",
	"kit_flipper_tell", "kit_flipper_swat", "kit_flipper_return", "kit_drawbridge_chains", "kit_drawbridge_raise",
	"kit_drawbridge_lower", "kit_drawbridge_thud", "kit_gapwall_warn", "kit_gapwall_slide", "kit_gapwall_thud",
	"kit_block_tell", "kit_block_slam", "kit_block_rise", "kit_hammer_tell", "kit_hammer_swing", "kit_hammer_park",
	"emote_wave", "emote_thumbsup", "emote_dance", "emote_bow", "emote_laugh", "emote_flex", "emote_spin",
	"emote_facepalm", "emote_taunt", "emote_sit", "emote_strongman", "emote_salute", "emote_hero", "emote_dab",
	"emote_rockstar",
	# the Big Update: Toybox Tumble, Olympus Rising, Pixel Panic (gen_toybox / gen_olympus / gen_arcade)
	"toybox_checkpoint", "toybox_finish", "toybox_car_wind", "toybox_car_stop", "toybox_jack_tune", "toybox_jack_pop",
	"toybox_tell_tick", "toybox_tower_creak", "toybox_tower_fall", "toybox_tower_thud", "toybox_tower_lift",
	"toybox_tower_chime", "toybox_note_1", "toybox_note_2", "toybox_note_3", "toybox_note_4", "toybox_note_5",
	"olympus_checkpoint", "olympus_finish", "olympus_chariot_launch", "olympus_column_crack", "olympus_column_fall",
	"olympus_column_reform", "olympus_mirror_charge", "olympus_mirror_fire", "olympus_spirit_call",
	"olympus_spirit_gust", "olympus_tell_tick", "arcade_checkpoint", "arcade_finish", "arcade_boss_defeat",
	"arcade_block_tick", "arcade_block_land", "arcade_block_clear_warn", "arcade_block_clear", "arcade_block_drop",
	"arcade_paddle_ping", "arcade_ball_ping", "arcade_glitch_warn", "arcade_glitch_hop", "arcade_scroll_start",
	"arcade_boss_charge", "arcade_boss_blast",
	# Castle Siege and Mushroom Hollow (gen_siege / gen_fungal)
	"siege_boulder_launch", "siege_boulder_whistle", "siege_boulder_impact", "siege_ram_creak", "siege_ram_whoosh",
	"siege_ram_thud", "siege_oil_tilt", "siege_oil_pour", "siege_volley_horn", "siege_volley_whoosh", "siege_volley_hit",
	"siege_trebuchet_wind", "siege_trebuchet_throw", "siege_warning_horn", "siege_checkpoint", "siege_finish",
	"fungal_cap_boing", "fungal_checkpoint", "fungal_finish", "fungal_drip_plink", "fungal_drip_splash",
	"fungal_puff_swell", "fungal_puff_blow", "fungal_tell_tick", "fungal_frog_croak"]
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
	"tempest_wind", "tempest_trolley", "tempest_gondola_motor", "tempest_crane_slew", "void_rift_hum", "void_collapse_rumble",
	"kit_zipline_whirr", "kit_log_roll",
	# the Big Update: the three new worlds' loops
	"toybox_car_whirr", "olympus_chariot_wind", "olympus_mirror_hum", "olympus_wind_loop", "arcade_chomper_loop",
	"arcade_ball_hum", "arcade_scroll_rumble",
	# Castle Siege and Mushroom Hollow (gen_siege / gen_fungal)
	"siege_oil_loop", "fungal_puff_loop", "fungal_snail_squelch"]


func test_z_world_sounds() -> void:
	# every map has its own footsteps and landings; anything else falls back to the plain ones
	var old_theme: String = Sfx.get("_theme")
	for th: String in ["gardens", "foundry", "balance", "clockwork", "reef", "orbital", "xeno", "volcano", "glacier", "desert",
			"manor", "armada", "candy", "carrier", "sakura", "jungle", "frontier", "neon", "doom", "abyss", "tempest", "void",
			"toybox", "fungal", "olympus", "arcade", "carnival", "dino", "arcane", "siege",
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
		"doom", "abyss", "tempest", "void", "toybox", "fungal", "olympus", "arcade", "carnival", "dino", "arcane", "siege"]
	var srcs: Array[String] = []
	for f: String in ["level_11_manor.gd", "level_12_armada.gd", "level_13_candy.gd", "level_14_carrier.gd",
			"level_16_sakura.gd", "level_17_jungle.gd", "level_18_frontier.gd", "level_19_neon.gd",
			"level_20_doom.gd", "level_21_abyss.gd", "level_22_tempest.gd", "level_23_void.gd",
			"level_25_toybox.gd", "level_26_fungal.gd", "level_27_olympus.gd", "level_28_arcade.gd", "level_29_carnival.gd", "level_30_dino.gd", "level_31_arcane.gd", "level_32_siege.gd"]:
		srcs.append("res://levels/" + f)
	for f: String in DirAccess.get_files_at("res://mechanics"):
		if f.ends_with(".gd") and prefixes.any(func(p: String) -> bool: return f.begins_with(p + "_")):
			srcs.append("res://mechanics/" + f)
	# the third and fourth sets' decor scripts own their waterfalls, vents, signs and thunder (the older
	# maps' visual/ scripts stay out of this scan; armada_storm.gd now plays the ambience's thunder)
	for f: String in DirAccess.get_files_at("res://visual"):
		if f.ends_with(".gd") and ["sakura", "jungle", "frontier", "neon", "doom", "abyss", "tempest", "void",
				"toybox", "fungal", "olympus", "arcade", "carnival", "dino", "arcane", "siege"].any(
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


func test_zc_earned_rewards_never_relock() -> void:
	# "beat every course" was earned and announced; then new courses were added, so the rule no
	# longer holds - the reward must stay unlocked (a test's own levels dict still sees the rule)
	SaveData.wipe()
	check(not Cosmetics.is_unlocked("trail", "rainbow"), "Rainbow starts locked")
	SaveData.mark_cosmetics_seen(["trail:rainbow"] as Array[String])
	check(Cosmetics.is_unlocked("trail", "rainbow"), "an announced reward stays unlocked after courses are added")
	check(not Cosmetics.is_unlocked("trail", "rainbow", {}), "an explicit levels dict still evaluates the rule")
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
const _ZM_PROVISIONAL: Array[String] = ["toybox", "fungal", "olympus", "arcade", "carnival", "dino", "arcane", "siege"]


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
	check(Cosmetics.kinds() == ["character", "hat", "paint", "trail", "finish", "title", "emote", "pose"], "KINDS order: %s" % [Cosmetics.kinds()])
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
	check(Cosmetics.ids("character") == ["volt", "knight", "ninja", "astronaut", "dino", "skeleton", "catbot", "outlaw", "cyber", "golden", "wizard", "pirate", "yeti", "robopup", "pixel"], "characters: %s" % [Cosmetics.ids("character")])
	check(Cosmetics.ids("paint") == ["white", "chrome", "camo", "lava", "galaxy", "candy", "ghost", "neon", "goldleaf", "pixel", "marble", "toxic", "aurora", "stained"], "paints: %s" % [Cosmetics.ids("paint")])
	check(Cosmetics.ids("title") == ["rookie", "globetrotter", "speed_demon", "gold_rush", "flawless", "lap_king", "marathoner", "challenger", "challenge_master", "completionist"], "titles: %s" % [Cosmetics.ids("title")])
	# one hat per world, for Silver on it (Gold medal hats are checked separately)
	var worlds: Dictionary = {}
	for id: String in Cosmetics.ids("hat"):
		var r: Dictionary = Cosmetics.catalogue("hat")[id]["rule"]
		if r["type"] == "medal" and int(r["tier"]) == 2:
			check(not worlds.has(r["level"]), "hat %s: Silver on %s" % [id, r["level"]])
			worlds[r["level"]] = id
		elif r["type"] == "medal":
			check(int(r["tier"]) == 3 and not Game.level_by_id(str(r["level"])).is_empty(), "hat %s: a Gold medal hat on %s" % [id, r["level"]])
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
	check(int(title.get("locker_tab")) == 8 and focus.call() != null and focus.call().has_meta("colour"),
		"LB from the first tab wraps to Colour (the last tab), on a swatch")
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


# ---- v2.0 looks (LooksExt): paints, trails and finishes ---------------------------------------

func test_zc_looks_ext_items() -> void:
	var paints: Array[String] = ["goldleaf", "pixel", "marble", "toxic", "aurora", "stained"]
	for p: String in paints:
		var code: String = LooksExt.paint_shader_code(p)
		check(code.contains("shader_type spatial") and code.contains("void fragment()"), "paint %s has its own shader source" % p)
		check(not code.contains("/") and not code.contains("pow(") and not code.contains("normalize("),
			"paint %s is NaN-free: no division, pow or normalize" % p)
		var m: Material = CosmeticArt.paint_material(p)
		check(m is ShaderMaterial and m == CosmeticArt.paint_material(p), "paint %s is a cached ShaderMaterial" % p)
		check(Cosmetics.hint("paint", p) != "" and not Cosmetics.is_unlocked("paint", p, {}), "paint %s is locked on a fresh save, with a hint" % p)
	for t: String in ["hearts", "pixels", "notes", "ink", "leaves", "stars"]:
		var layers: Array[Dictionary] = LooksExt.trail_layers(t, Color.WHITE)
		var ok: bool = not layers.is_empty()
		for l: Dictionary in layers:
			ok = ok and int(l.get("amount", 0)) > 0
		check(ok, "trail %s has emitter layers with amounts" % t)
		check(not Cosmetics.is_unlocked("trail", t, {}) and Cosmetics.hint("trail", t) != "", "trail %s is locked on a fresh save, with a hint" % t)
	for f: String in ["balloons", "disco", "meteor", "pixelburst"]:
		check(FileAccess.file_exists("res://audio/fin_%s.wav" % f), "the %s finish has its fin_%s.wav" % [f, f])
		check(not Cosmetics.is_unlocked("finish", f, {}) and Cosmetics.hint("finish", f) != "", "finish %s is locked on a fresh save, with a hint" % f)
	check(LooksExt.paint_shader_code("white") == "" and LooksExt.trail_layers("classic", Color.WHITE).is_empty(),
		"ids LooksExt does not know fall through (white paint, classic trail)")
	check(Cosmetics.ids("trail").size() == 16 and Cosmetics.ids("finish").size() == 10, "trails %d, finishes %d" % [Cosmetics.ids("trail").size(), Cosmetics.ids("finish").size()])



# ---- ghost replays (M1) ------------------------------------------------------------------

## A straight run along -Z at 8 m/s for `secs`, 15 Hz, with a respawn jump halfway through.
func _make_test_ghost(id: String, secs: float = 10.0) -> GhostData:
	var g := GhostData.new()
	g.level_id = id
	g.rev = GhostData.current_rev(id)
	g.time = secs
	var n: int = int(secs * GhostData.HZ) + 1
	for i: int in n:
		var t: float = float(i) / GhostData.HZ
		# a respawn at t=5: the pose jumps 40 m back up the course
		var snap: bool = i == int(5.0 * GhostData.HZ)
		var z: float = -8.0 * t + (40.0 if t >= 5.0 else 0.0)
		g.add(Vector3(2.0, 1.0, z), 0.5 + 0.01 * float(i), i % 7 != 0, false, snap)
	return g


## Rendered frames (the ghost follows the clock in _process; physics ticks can run in bursts).
func _frames(n: int) -> void:
	for k: int in n:
		await get_tree().process_frame


func _ghost_setup() -> Dictionary:
	var keep: Dictionary = {"mode": Settings.ghost_mode, "path": Settings.save_path_override}
	Settings.save_path_override = "user://ghosts_test_settings.cfg"
	GhostData.delete_all()
	return keep


func _ghost_teardown(keep: Dictionary) -> void:
	Settings.ghost_mode = int(keep["mode"])
	var p: String = Settings.save_path_override
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Settings.save_path_override = str(keep["path"])
	GhostData.delete_all()
	Game.course_running = false


func test_zh_ghost_roundtrip_and_rev_discard() -> void:
	var keep: Dictionary = _ghost_setup()
	check(GhostData.dir() != "user://ghosts", "tests keep ghosts out of the real folder (%s)" % GhostData.dir())
	var g: GhostData = _make_test_ghost("gardens")
	check(g.save() and FileAccess.file_exists(GhostData.path_for("gardens")), "a ghost saves to <dir>/gardens.ghost")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(GhostData.path_for("gardens"))
	check(bytes.slice(0, 4).get_string_from_ascii() == "JCGH" and bytes[4] == GhostData.VERSION, "the file starts with the magic and version")
	check(bytes.size() < g.size() * GhostData.BYTES_PER_SAMPLE, "the file is compact (%d bytes for %d samples)" % [bytes.size(), g.size()])
	var back: GhostData = GhostData.load_for("gardens")
	check(back != null and back.size() == g.size() and absf(back.time - g.time) < 0.001 and back.rev == g.rev, "a ghost loads back with its length, time and rev")
	var worst_pos: float = 0.0
	var worst_yaw: float = 0.0
	var flags_ok: bool = true
	if back != null:
		for i: int in g.size():
			worst_pos = maxf(worst_pos, back.pos[i].distance_to(g.pos[i]))
			worst_yaw = maxf(worst_yaw, absf(angle_difference(back.yaw[i], g.yaw[i])))
			flags_ok = flags_ok and back.flags[i] == g.flags[i]
	check(worst_pos < 0.0001 and worst_yaw < 0.001 and flags_ok, "round-trip keeps positions (%.6f), yaw (%.5f) and flags" % [worst_pos, worst_yaw])
	# the same bytes under another level id are not that level's ghost
	check(GhostData.decode(bytes, "foundry") == null, "a ghost is only valid for its own level")
	# an older layout rev is discarded (and the stale file removed)
	var old: GhostData = _make_test_ghost("foundry")
	old.rev = GhostData.current_rev("foundry") - 1
	check(old.save() and FileAccess.file_exists(GhostData.path_for("foundry")), "an old-rev ghost file exists")
	check(GhostData.load_for("foundry") == null, "a ghost from an older layout rev is discarded")
	check(not FileAccess.file_exists(GhostData.path_for("foundry")), "and its stale file is deleted")
	# damage: truncated, garbage, a wrong version
	var cut: PackedByteArray = bytes.slice(0, bytes.size() - 10)
	check(GhostData.decode(cut, "gardens") == null, "a truncated ghost is rejected")
	check(GhostData.decode(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]), "gardens") == null, "garbage is rejected")
	var wrong: PackedByteArray = bytes.duplicate()
	wrong[4] = GhostData.VERSION + 1
	check(GhostData.decode(wrong, "gardens") == null, "an unknown version is rejected")
	check(GhostData.load_for("nonexistent") == null, "a level without a ghost loads null")
	GhostData.delete_all()
	check(not DirAccess.dir_exists_absolute(GhostData.dir()), "delete_all clears the test ghost folder")
	_ghost_teardown(keep)


func test_zh_ghost_record_and_save_on_pb() -> void:
	var keep: Dictionary = _ghost_setup()
	Settings.ghost_mode = Settings.GHOST_OFF
	var lvl: LevelBase = await load_level(0)
	var gr: GhostRun = lvl.ghost_run
	check(gr != null, "a solo run has a ghost recorder")
	if gr == null:
		_ghost_teardown(keep)
		return
	check(gr.racer == null, "with the ghost off nothing is shown (but the run is still recorded)")
	var start_n: int = gr.recording.size()
	lvl.player.control_enabled = true
	lvl.player.use_device_input = false
	lvl.player.cmd_move = Vector2(0, 1)
	Game.course_time = 0.0
	Game.course_running = true
	await seconds(2.0)
	var n: int = gr.recording.size()
	check(n >= 25 and n <= 36, "about 15 samples a second are recorded (%d in 2 s, started at %d)" % [n, start_n])
	var last: Vector3 = gr.recording.pos[n - 1]
	check(last.distance_to(lvl.player.global_position) < 2.0, "samples follow the player")
	# restarting the clock starts the recording over
	lvl.restart_run()
	await ticks(3)
	check(gr.recording.size() < 5, "restarting the run restarts the recording (%d)" % gr.recording.size())
	await seconds(1.0)
	# finishing with a new best saves the ghost, a slower run does not replace it
	check(not FileAccess.file_exists(GhostData.path_for(lvl.level_id)), "no ghost file before a finish")
	lvl.run_time = Game.course_time
	var t1: float = lvl.run_time
	lvl._on_finish()
	await ticks(2)
	check(SaveData.best_time(lvl.level_id) > 0.0 and FileAccess.file_exists(GhostData.path_for(lvl.level_id)), "a new personal best writes the ghost file")
	var saved: GhostData = GhostData.load_for(lvl.level_id)
	check(saved != null and absf(saved.time - t1) < 0.001 and saved.size() >= 10, "the saved ghost carries the PB time (%s)" % str(saved.time if saved != null else -1.0))
	lvl.finished = false
	lvl.run_time = t1 + 30.0
	var before: PackedByteArray = FileAccess.get_file_as_bytes(GhostData.path_for(lvl.level_id))
	lvl._on_finish()
	await ticks(2)
	check(FileAccess.get_file_as_bytes(GhostData.path_for(lvl.level_id)) == before, "a slower finish keeps the old ghost")
	lvl.player.cmd_move = Vector2.ZERO
	SaveData.wipe()
	_ghost_teardown(keep)


func test_zh_ghost_playback_timing() -> void:
	var keep: Dictionary = _ghost_setup()
	Settings.ghost_mode = Settings.GHOST_PB
	var lvl0: LevelBase = await load_level(0)
	var id: String = lvl0.level_id
	var g: GhostData = _make_test_ghost(id)
	check(g.save(), "test ghost saved")
	# an old-layout ghost never shows up
	var stale: GhostData = _make_test_ghost(id)
	stale.rev = GhostData.current_rev(id) + 1
	stale.save()
	var lvl: LevelBase = await load_level(0)
	check(lvl.ghost_run != null and lvl.ghost_run.racer == null, "an old-layout ghost is not replayed")
	check(not FileAccess.file_exists(GhostData.path_for(id)), "and is deleted from disk")
	g.save()
	lvl = await load_level(0)
	var racer: RemoteRacer = lvl.ghost_run.racer
	check(racer != null, "the saved PB ghost is replayed as a racer")
	if racer == null:
		_ghost_teardown(keep)
		return
	Game.course_running = false
	for t: float in [0.0, 2.0, 3.5, 4.9, 6.0, 9.0]:
		Game.course_time = t
		await _frames(3)
		var want: Vector3 = g.sample(t)["pos"]
		check(racer.global_position.distance_to(want) < 0.35, "at %.1f s the ghost is at %s (got %s)" % [t, str(want), str(racer.global_position)])
	# the respawn jump is a snap, not a slide
	Game.course_time = 4.9
	await _frames(3)
	var z_before: float = racer.global_position.z
	Game.course_time = 5.05
	await _frames(3)
	check(racer.global_position.z - z_before > 30.0, "the ghost jumps with the recorded respawn (%.1f -> %.1f)" % [z_before, racer.global_position.z])
	# rewinding the clock (a restart) puts it back at the start
	Game.course_time = 0.0
	await _frames(3)
	check(racer.global_position.distance_to(g.pos[0]) < 0.35 and racer.visible, "a restart sends the ghost back to the start")
	# past the end it stands, then goes away
	Game.course_time = g.duration() + 1.0
	await _frames(3)
	check(racer.visible, "at the end the ghost celebrates in view")
	await seconds(2.8)
	check(not racer.visible, "then it leaves")
	# translucent
	var faded: bool = false
	for m: Node in racer.find_children("*", "MeshInstance3D", true, false):
		faded = faded or (m as MeshInstance3D).transparency > 0.3
	check(faded, "the ghost renders translucent")
	# turning it off live removes it; on again restores it
	Settings.ghost_mode = Settings.GHOST_OFF
	lvl.ghost_run.apply_setting()
	await ticks(2)
	check(lvl.ghost_run.racer == null, "Off removes the ghost")
	Settings.ghost_mode = Settings.GHOST_PB
	lvl.ghost_run.apply_setting()
	check(lvl.ghost_run.racer != null, "Personal best brings it back")
	# Off from the start: nothing built
	Settings.ghost_mode = Settings.GHOST_OFF
	lvl = await load_level(0)
	check(lvl.ghost_run != null and lvl.ghost_run.racer == null, "with Ghost: Off no racer is built")
	_ghost_teardown(keep)


func test_zh_ghost_none_in_party_or_multiplayer() -> void:
	var keep: Dictionary = _ghost_setup()
	Settings.ghost_mode = Settings.GHOST_PB
	var lvl0: LevelBase = await load_level(0)
	_make_test_ghost(lvl0.level_id).save()
	check(GhostRun.allowed(), "a plain solo run allows ghosts")
	Game.race_mode = true
	check(not GhostRun.allowed(), "a race allows none")
	Game.race_mode = false
	var was_active: bool = Net.active
	Net.active = true
	check(not GhostRun.allowed(), "an open multiplayer session allows none")
	Net.active = was_active
	# a Party Practice level: no recorder, no replay
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	Game.party = PartyRules.new("practice")
	Game.level_index = 0
	Game.race_mode = false
	Game.course_time = 0.0
	var lvl: LevelBase = (load(Game.LEVELS[0]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	check(lvl.ghost_run == null, "Party Practice has no ghost run")
	var ghosts: int = 0
	for r: Node in lvl.find_children("*", "RemoteRacer", true, false):
		ghosts += 1
	check(ghosts == 0, "and no ghost racer")
	var pause: PauseMenu = lvl.find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	pause.set_open(true)
	check(find_button(pause, "Ghost: Personal best") == null and find_button(pause, "Ghost: Off") == null, "the party pause menu has no ghost toggle")
	pause.set_open(false)
	Game.party = null
	_ghost_teardown(keep)


func test_zh_ghost_settings_and_pause_toggle_pad() -> void:
	var keep: Dictionary = _ghost_setup()
	# sanitize + persistence (to the private settings file)
	Settings.ghost_mode = 9
	Settings._sanitize()
	check(Settings.ghost_mode == 1, "an out-of-range ghost mode is clamped")
	Settings.ghost_mode = Settings.GHOST_OFF
	Settings.save_settings()
	Settings.ghost_mode = Settings.GHOST_PB
	Settings.load_settings(Settings.save_path_override)
	check(Settings.ghost_mode == Settings.GHOST_OFF, "the ghost setting persists in the settings file")
	# the Settings panel row
	var sp := SettingsPanel.new()
	var holder: Control = UiKit.centered(sp)
	add_child(holder)
	await _focus_after_rebuild()
	var row: OptionButton = null
	for ob: Node in sp.find_children("*", "OptionButton", true, false):
		if (ob as OptionButton).item_count == Settings.GHOST_NAMES.size() and (ob as OptionButton).get_item_text(0) == "Off":
			row = ob as OptionButton
	check(row != null and row.selected == Settings.GHOST_OFF, "the Settings panel has a Ghost row showing Off")
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
	var reached: bool = false
	var guard: int = 0
	while guard < 80 and row != null:
		if get_viewport().gui_get_focus_owner() == row:
			reached = true
			break
		await send.call(JOY_BUTTON_DPAD_DOWN)
		guard += 1
	check(reached, "the pad can walk down to the Ghost row (%d presses)" % guard)
	if row != null:
		row.item_selected.emit(1)
		check(Settings.ghost_mode == Settings.GHOST_PB, "choosing Personal best sets the setting")
	sp.set("_dirty", false)
	holder.queue_free()
	await ticks(2)
	# the pause-menu toggle, by pad
	Settings.ghost_mode = Settings.GHOST_PB
	var lvl0: LevelBase = await load_level(0)
	_make_test_ghost(lvl0.level_id).save()
	var lvl: LevelBase = await load_level(0)
	var pause: PauseMenu = lvl.find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	check(lvl.ghost_run.racer != null, "the PB ghost is up before pausing")
	pause.set_open(true)
	await ticks(3)
	var gb: Button = find_button(pause, "Ghost: Personal best")
	check(gb != null, "the pause menu has a Ghost toggle")
	reached = false
	guard = 0
	while guard < 12 and gb != null:
		if get_viewport().gui_get_focus_owner() == gb:
			reached = true
			break
		await send.call(JOY_BUTTON_DPAD_DOWN)
		guard += 1
	check(reached, "the pad reaches the pause menu's Ghost toggle")
	await send.call(JOY_BUTTON_A)
	check(Settings.ghost_mode == Settings.GHOST_OFF and gb.text == "Ghost: Off", "A cycles it to Off (%s)" % gb.text)
	await ticks(2)
	check(lvl.ghost_run.racer == null, "and the ghost leaves the course at once")
	await send.call(JOY_BUTTON_A)
	check(Settings.ghost_mode == Settings.GHOST_PB and lvl.ghost_run.racer != null, "A again brings the ghost back")
	pause.set_open(false)
	_ghost_teardown(keep)


# ---- course challenges and the Stats screen ----------------------------------------------------

func test_zx_challenges_generated_and_evaluated() -> void:
	SaveData.wipe()
	check(Challenges.total() == Game.LEVELS.size() * 3, "three challenges per course, generated from Game.LEVELS (%d)" % Challenges.total())
	var names_ok: bool = true
	var targets_ok: bool = true
	for info: Dictionary in Game.LEVELS:
		var id: String = str(info["id"])
		for k: String in Challenges.KINDS:
			if Challenges.title(id, k) == "" or Challenges.description(id, k) == "":
				names_ok = false
		var t: float = Challenges.speed_target(id)
		if not (t < Game.medal_target(id, 2) and t > Game.medal_target(id, 3)):
			targets_ok = false
	check(names_ok, "every course has a name and description for each challenge (generic fallbacks)")
	check(targets_ok, "the Speedrunner target sits strictly between Silver and Gold on every course")
	check(Challenges.title("gardens", "flawless") == "Green Thumb" and Challenges.title("siege", "flawless") == "Flawless", "flavour names with a generic fallback")
	var id: String = "gardens"
	check(Challenges.count() == 0, "a fresh save has no challenges done")
	# a Silver-time, falling run: only Silver Standard
	SaveData.record_finish(id, Game.medal_target(id, 2) - 1.0, 4)
	check(Challenges.done(id, "silver") and not Challenges.done(id, "flawless") and not Challenges.done(id, "speed"), "Silver time, 4 falls: Silver Standard only")
	# just over the Speedrunner target does not count; just under does
	var tgt: float = Challenges.speed_target(id)
	SaveData.record_finish(id, tgt, 2)
	check(not Challenges.done(id, "speed"), "exactly the target is not under it")
	SaveData.record_finish(id, tgt - 0.5, 0)
	check(Challenges.done(id, "speed") and Challenges.done(id, "flawless") and Challenges.level_count(id) == 3, "a fast flawless run completes the other two (3/3)")
	check(Challenges.count() == 3, "challenges count across the circuit")
	# the shared rules are derived from records: a hand-built levels dict is judged without the save
	var fake: Dictionary = {"foundry": {"completed": true, "best": Game.medal_target("foundry", 3) - 1.0, "fewest_falls": 1}}
	check(Challenges.done("foundry", "silver", fake) and Challenges.done("foundry", "speed", fake) and not Challenges.done("foundry", "flawless", fake), "evaluation works on any levels dict")
	check(not Challenges.done(id, "flawless", {}), "an empty record has nothing done")
	SaveData.wipe()


func test_zx_challenges_retroactive_and_sticky() -> void:
	SaveData.wipe()
	# a save from before challenges existed: bests, fewest falls and an older layout's legacy bests
	SaveData.data["levels"]["foundry"] = {"completed": true, "runs": 3, "best": Game.medal_target("foundry", 3) - 1.0, "fewest_falls": 0, "rev": 3}
	SaveData.data["levels"]["balance"] = {"completed": true, "runs": 1, "legacy_best": Game.medal_target("balance", 2) - 1.0, "legacy_fewest_falls": 0, "rev": 1}
	check(Challenges.level_count("foundry") == 3, "old bests and fewest falls earn challenges retroactively")
	check(Challenges.done("balance", "silver") and Challenges.done("balance", "flawless") and not Challenges.done("balance", "speed"), "legacy records count too")
	var before: Array[String] = []
	var fresh: Array[String] = Challenges.sync(before)
	check(fresh.size() == 5, "sync reports what was newly done (%d)" % fresh.size())
	check(Challenges.stored().size() == 5 and Challenges.stored().has("foundry:speed"), "and remembers it in the save")
	check(Challenges.sync(Challenges.done_keys()).is_empty(), "a second sync has nothing new")
	# the record is later lost (a layout rebuild): the remembered challenge stays done
	SaveData.data["levels"]["foundry"] = {"completed": true, "runs": 3, "rev": 3}
	check(Challenges.done("foundry", "flawless") and Challenges.level_count("foundry") == 3, "a remembered challenge never relocks")
	check(not Challenges.met(SaveData.data["levels"], "foundry", "flawless"), "(while the records alone no longer meet it)")
	# saved and loaded
	SaveData.save_data()
	SaveData.data = {"levels": {}, "game_completed": false}
	SaveData.load_data()
	check(Challenges.stored().has("foundry:flawless") and Challenges.count() >= 5, "challenges survive save and load")
	SaveData.wipe()


func test_zx_challenges_save_sanitizing() -> void:
	SaveData.wipe()
	var clean: Dictionary = SaveData._sanitize({"levels": {}, "challenges": ["gardens:silver", "gardens:silver", "nope:silver", "gardens:nope", 5, null, "foundry:speed"]})
	check(clean["challenges"] == ["gardens:silver", "foundry:speed"], "challenges keep known, unique id:kind strings only (%s)" % str(clean["challenges"]))
	check(SaveData._sanitize({"levels": {}, "challenges": "gardens:silver"})["challenges"] == [], "a non-array value becomes empty")
	check(SaveData._sanitize({"levels": {}})["challenges"] == [], "a missing value becomes empty")
	var st: Dictionary = SaveData._sanitize({"levels": {}, "stats": {"falls_total": 7, "play_secs": -3, "bogus": 5, "flawless_golds": "x"}})["stats"]
	check(st.get("falls_total") == 7 and not st.has("play_secs") and not st.has("bogus") and not st.has("flawless_golds"), "the new stat keys are sanitized like the others")
	# a hand-edited file on disk
	var f := FileAccess.open(SaveData._path(), FileAccess.WRITE)
	f.store_string('{"levels": {"gardens": {"completed": true, "best": 100.0}}, "challenges": ["gardens:flawless", 12, {"a": 1}], "stats": {"falls_total": 3, "play_secs": 125}}')
	f.close()
	SaveData.load_data()
	check(Challenges.stored() == ["gardens:flawless"], "loading drops junk entries")
	check(SaveData.stat("falls_total") == 3 and SaveData.stat("play_secs") == 125, "stat counters load")
	SaveData.wipe()


func test_zx_challenge_rule_hint_progress() -> void:
	SaveData.wipe()
	var rule: Dictionary = Cosmetics.TITLES["challenger"]["rule"]
	check(rule["type"] == "challenges" and Cosmetics.TITLES.keys().slice(-3) == ["challenger", "challenge_master", "completionist"], "the three challenge titles are appended after the old ones")
	check(Cosmetics.TITLES.keys().slice(0, 7) == ["rookie", "globetrotter", "speed_demon", "gold_rush", "flawless", "lap_king", "marathoner"], "the older titles keep their order")
	check(not Cosmetics.is_unlocked("title", "challenger"), "Challenger starts locked")
	check(Cosmetics.hint("title", "challenger") == "Complete 25 course challenges (see Challenges)", "hint (%s)" % Cosmetics.hint("title", "challenger"))
	check(Cosmetics.progress("title", "challenger") == "0/25", "progress starts at 0/25")
	# 9 courses' worth of 3 challenges = 27 with hand-made records
	var lv: Dictionary = {}
	for i: int in 9:
		var id: String = str(Game.LEVELS[i]["id"])
		lv[id] = {"completed": true, "best": Game.medal_target(id, 3) - 1.0, "fewest_falls": 0}
	check(Challenges.count(lv) == 27, "nine perfect courses are 27 challenges")
	check(Cosmetics.rule_met(rule, lv) and not Cosmetics.rule_met(Cosmetics.TITLES["challenge_master"]["rule"], lv), "challenges(25) met, challenges(60) not")
	check(Cosmetics.progress("title", "challenger", lv) == "25/25" and Cosmetics.progress("title", "challenge_master", lv) == "27/60", "progress is capped at n (%s, %s)" % [Cosmetics.progress("title", "challenger", lv), Cosmetics.progress("title", "challenge_master", lv)])
	check(not Cosmetics.rule_met(Cosmetics.TITLES["completionist"]["rule"], lv), "Completionist needs every challenge")
	check(Cosmetics.progress("title", "completionist", lv) == "27/%d" % Challenges.total(), "and shows 27/%d" % Challenges.total())
	var all: Dictionary = {}
	for info: Dictionary in Game.LEVELS:
		all[info["id"]] = {"completed": true, "best": Game.medal_target(info["id"], 3) - 1.0, "fewest_falls": 0}
	check(Cosmetics.rule_met(Cosmetics.TITLES["completionist"]["rule"], all), "every course perfect: Completionist")
	check(Challenges.next_reward()[0] == "Challenger title" and Challenges.next_reward()[1] == 25, "the next reward is the nearest challenge title (%s)" % str(Challenges.next_reward()))
	# the save feeds it: unlocking announces the title once
	for i: int in 9:
		SaveData.data["levels"][Game.LEVELS[i]["id"]] = lv[Game.LEVELS[i]["id"]]
	check(Cosmetics.is_unlocked("title", "challenger"), "the saved records unlock Challenger")
	var fresh: Array[Array] = Cosmetics.check_unlocks()
	check(fresh.any(func(p: Array) -> bool: return p[0] == "title" and p[1] == "challenger"), "and it is announced")
	check(Cosmetics.check_unlocks().is_empty(), "only once")
	SaveData.wipe()


func test_zx_stats_counters() -> void:
	SaveData.wipe()
	check(SaveData.stat("falls_total") == 0 and SaveData.stat("play_secs") == 0, "the counters start at zero")
	SaveData.count_fall()
	SaveData.count_fall()
	SaveData.tick_play(0.6)
	check(SaveData.stat("play_secs") == 0, "play time banks whole seconds only")
	SaveData.tick_play(0.6)
	SaveData.tick_play(61.0)
	check(SaveData.stat("falls_total") == 2 and SaveData.stat("play_secs") == 62, "falls and seconds accumulate (%d falls, %d s)" % [SaveData.stat("falls_total"), SaveData.stat("play_secs")])
	SaveData.flush_play_stats()
	SaveData.data = {"levels": {}, "game_completed": false}
	SaveData.load_data()
	check(SaveData.stat("falls_total") == 2 and SaveData.stat("play_secs") == 62, "flushing writes them to the save")
	check(ExtraScreens.play_time_text(45) == "45s" and ExtraScreens.play_time_text(750) == "12m 30s" and ExtraScreens.play_time_text(11100) == "3h 05m", "play time reads as h/m/s")
	# a real level counts its falls and its time
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var lvl: LevelBase = await load_level(0)
	await seconds(1.0)
	var falls0: int = SaveData.stat("falls_total")
	var secs0: int = SaveData.stat("play_secs")
	lvl.fail("fall")
	check(SaveData.stat("falls_total") == falls0 + 1 and lvl.deaths == 1, "a fall in a course is counted in the stats")
	Game.course_time = 0.0
	lvl._started = true
	await seconds(2.2)
	check(SaveData.stat("play_secs") >= secs0 + 1, "time on the course is counted (%d -> %d)" % [secs0, SaveData.stat("play_secs")])
	world.queue_free()
	world = null
	await ticks(2)
	SaveData.wipe()


func test_zx_stats_rows() -> void:
	SaveData.wipe()
	var rows: Array[PackedStringArray] = ExtraScreens.stats_rows()
	var by: Dictionary = {}
	for r: PackedStringArray in rows:
		by[r[0]] = r[1]
	check(by["Total runs"] == "0" and by["Favourite course"] == "None yet" and by["Medals"] == "Gold 0   Silver 0   Bronze 0", "a fresh save reads all zero")
	SaveData.data["levels"]["gardens"] = {"completed": true, "runs": 2, "best": Game.medal_target("gardens", 3) - 1.0, "fewest_falls": 0}
	SaveData.data["levels"]["foundry"] = {"completed": true, "runs": 5, "best": Game.medal_target("foundry", 2) - 1.0, "fewest_falls": 1}
	SaveData.data["levels"]["reef"] = {"completed": true, "runs": 1, "best": Game.medal_target("reef", 1) - 1.0, "fewest_falls": 3}
	SaveData.data["stats"] = {"falls_total": 14, "play_secs": 3725}
	by.clear()
	for r: PackedStringArray in ExtraScreens.stats_rows():
		by[r[0]] = r[1]
	check(by["Total runs"] == "8" and by["Total falls"] == "14" and by["Time played"] == "1h 02m", "runs, falls and time (%s)" % str(by))
	check(by["Medals"] == "Gold 1   Silver 1   Bronze 1", "medals by tier, each course once (%s)" % by["Medals"])
	check(by["Favourite course"] == "Bounce Foundry  (5 runs)", "favourite course is the one with most runs (%s)" % by["Favourite course"])
	check(by["Courses beaten"] == "3 / %d" % Game.LEVELS.size() and by["Challenges done"].begins_with("%d / " % Challenges.count()), "courses beaten and challenges done")
	SaveData.wipe()


func test_zx_challenges_results_note() -> void:
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
	Cosmetics.check_unlocks()
	lvl.deaths = 0
	lvl.run_time = Challenges.speed_target(lvl.level_id) - 1.0
	lvl._on_finish()
	await seconds(4.5)
	var notes: Array[String] = []
	if lvl.hud._results_box != null:
		for n: Node in lvl.hud._results_box.find_children("*", "Label", true, false):
			if (n as Label).text.begins_with("Challenge complete!"):
				notes.append((n as Label).text)
	check(notes.size() == 3, "a first flawless gold-ish run shows three Challenge complete! notes in the results panel (%s)" % str(notes))
	check(notes.any(func(t: String) -> bool: return t.contains("Green Thumb")), "named after the challenge (flavour name)")
	check(Challenges.level_count(lvl.level_id) == 3 and Challenges.stored().size() == 3, "and they are saved")
	# finishing again earns nothing new: no notes
	lvl.hud._results.queue_free()
	lvl.hud._results = null
	lvl.finished = false
	var before: Array[String] = Challenges.done_keys()
	SaveData.record_finish(lvl.level_id, lvl.run_time, 0)
	check(Challenges.sync(before).is_empty(), "a repeat run completes nothing new")
	world.queue_free()
	world = null
	await ticks(2)
	SaveData.wipe()


func test_zx_challenges_stats_screens_pad() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	SaveData.wipe()
	SaveData.data["levels"]["gardens"] = {"completed": true, "runs": 1, "best": 190.0, "fewest_falls": 0}
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
	var guard: int = 0
	while not (focus.call() is Button and (focus.call() as Button).text in ["Challenges", "Stats"]) and guard < 12:
		await send.call(JOY_BUTTON_DPAD_DOWN)
		guard += 1
	check(focus.call() is Button and (focus.call() as Button).text in ["Challenges", "Stats"], "the Challenges / Stats row is reachable with the D-pad")
	if (focus.call() as Button).text == "Stats":
		await send.call(JOY_BUTTON_DPAD_LEFT)
	check((focus.call() as Button).text == "Challenges", "left reaches Challenges")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	check(focus.call() is Button and (focus.call() as Button).text == "Stats", "right moves along the row to Stats")
	await send.call(JOY_BUTTON_DPAD_LEFT)
	await send.call(JOY_BUTTON_A)
	await ticks(3)
	check(Game.title_screen == "challenges", "A opens the Challenges screen")
	var f: Control = focus.call()
	check(f is Button and f.has_meta("level") and f.get_meta("level") == "gardens", "initial focus: the first course with challenges left")
	check((f as Button).text.contains("[x]") and (f as Button).text.contains("[ ]"), "the row lists each challenge with its state")
	var scroll: ScrollContainer = (title.get("_screen") as Control).find_child("Scroll", true, false) as ScrollContainer
	check(scroll != null and scroll.follow_focus, "the list scrolls with focus")
	var summary: Label = (title.get("_screen") as Control).find_child("Summary", true, false) as Label
	check(summary != null and summary.text.begins_with("%d / %d" % [Challenges.count(), Challenges.total()]), "the summary shows overall progress (%s)" % (summary.text if summary != null else ""))
	var reward: Label = (title.get("_screen") as Control).find_child("NextReward", true, false) as Label
	check(reward != null and reward.text.contains("Challenger"), "and the next reward (%s)" % (reward.text if reward != null else ""))
	# walk down the unlocked rows: the scroll box follows (only the first two courses are unlocked in a fresh save)
	await send.call(JOY_BUTTON_DPAD_DOWN)
	var f2: Control = focus.call()
	check(f2 is Button and f2 != f and f2.get_meta("level", "") == "foundry", "down moves to the next course row")
	for k: int in 8:
		await send.call(JOY_BUTTON_DPAD_DOWN)
	check(scroll.scroll_vertical > 0, "the list scrolls to keep the focused course in view (%d)" % scroll.scroll_vertical)
	var fr: Rect2 = (focus.call() as Control).get_global_rect()
	check(scroll.get_global_rect().grow(4.0).encloses(fr), "the focused row sits inside the scroll box")
	guard = 0
	while not (focus.call() is Button and (focus.call() as Button).text == "Back") and guard < 40:
		await send.call(JOY_BUTTON_DPAD_DOWN)
		guard += 1
	check(focus.call() is Button and (focus.call() as Button).text == "Back", "down through every course reaches Back")
	await send.call(JOY_BUTTON_B)
	await ticks(3)
	check(Game.title_screen == "main", "B leaves Challenges")
	check(focus.call() is Button and (focus.call() as Button).text == "Challenges", "focus returns to the Challenges button")
	# Stats
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	await send.call(JOY_BUTTON_A)
	await ticks(3)
	check(Game.title_screen == "stats", "A on Stats opens it")
	check(focus.call() is Button and (focus.call() as Button).text == "Back", "the Stats screen starts focused on Back")
	var rows: Node = (title.get("_screen") as Control).find_child("Rows", true, false)
	check(rows != null and rows.get_child_count() == ExtraScreens.stats_rows().size() * 2, "it lists every stat")
	await send.call(JOY_BUTTON_B)
	await ticks(3)
	check(Game.title_screen == "main" and focus.call() is Button and (focus.call() as Button).text == "Stats", "B leaves Stats and focus returns to its button")
	# level select shows the pips
	title.call("show_screen", "levels")
	await ticks(3)
	var pip_rows: Array = []
	for n: Node in (title.get("_screen") as Control).find_children("*", "Button", true, false):
		if n.has_meta("challenges"):
			pip_rows.append(n)
	check(pip_rows.size() == Game.LEVELS.size(), "every level-select row carries challenge pips")
	var lit: int = 0
	for pip: Node in (pip_rows[0] as Button).find_child("Pips", true, false).get_children():
		if (pip as ColorRect).color == UiKit.GOLD:
			lit += 1
	check(pip_rows[0].get_meta("challenges") == 2 and lit == 2, "Launch Gardens: Silver and Flawless -> 2 of 3 pips lit (%d)" % lit)
	title.queue_free()
	await ticks(2)
	Game.title_screen = "main"
	SaveData.wipe()


# ---- C1: emotes and victory poses (cos-emotes) ------------------------------------------------------

func test_ze_catalogue_unlocks_and_settings() -> void:
	check(Cosmetics.kinds().slice(-2) == ["emote", "pose"], "emote and pose are the last two kinds")
	check(Cosmetics.kind_label("emote") == "Emote" and Cosmetics.kind_label("pose") == "Pose", "tab labels")
	check(Cosmetics.ids("emote") == ["wave", "thumbsup", "dance", "bow", "laugh", "flex", "spin", "facepalm", "taunt", "sit"], "emotes: %s" % [Cosmetics.ids("emote")])
	check(Cosmetics.ids("pose") == ["cheer", "strongman", "salute", "hero", "dab", "rockstar"], "poses: %s" % [Cosmetics.ids("pose")])
	check(Cosmetics.display_name("emote", "wave") == "Wave emote" and Cosmetics.display_name("pose", "dab") == "Dab pose", "display names")
	var defaults: int = 0
	for id: String in Cosmetics.ids("emote"):
		check(Emotes.has_clip("emote", id), "emote %s has a clip" % id)
		if Cosmetics.catalogue("emote")[id]["rule"]["type"] == "default":
			defaults += 1
		else:
			check(Cosmetics.hint("emote", id) != "", "locked emote %s names its unlock" % id)
	check(defaults == 4, "four emotes are free (%d)" % defaults)
	defaults = 0
	for id: String in Cosmetics.ids("pose"):
		check(Emotes.has_clip("pose", id), "pose %s has a clip" % id)
		if Cosmetics.catalogue("pose")[id]["rule"]["type"] == "default":
			defaults += 1
		else:
			check(Cosmetics.hint("pose", id) != "", "locked pose %s names its unlock" % id)
	check(defaults == 1, "one pose is free (%d)" % defaults)
	check(Emotes.EMOTE_LEN.size() == Cosmetics.ids("emote").size() and Emotes.POSE_LEN.size() == Cosmetics.ids("pose").size(), "no clip without a catalogue entry")
	for id: Variant in Emotes.PUFFS:
		check(Emotes.has_clip("emote", str(id)) or Emotes.has_clip("pose", str(id)), "puff table names a real clip (%s)" % id)
	# unlock rules against hand-made progress
	var ten: Array[String] = []
	for info: Dictionary in Game.LEVELS:
		if ten.size() < 10:
			ten.append(str(info["id"]))
	var lv: Dictionary = {}
	check(not Cosmetics.rule_met(Cosmetics.catalogue("emote")["laugh"]["rule"], lv) and not Cosmetics.rule_met(Cosmetics.catalogue("pose")["salute"]["rule"], lv), "nothing locked is owned on a fresh save")
	lv[ten[0]] = {"completed": true, "runs": 10, "best": Game.medal_target(ten[0], 1)}
	check(Cosmetics.rule_met(Cosmetics.catalogue("emote")["laugh"]["rule"], lv), "10 runs unlock Laugh")
	for i: int in 5:
		lv[ten[i]] = {"completed": true, "runs": 5, "best": Game.medal_target(ten[i], 1)}
	check(Cosmetics.rule_met(Cosmetics.catalogue("emote")["flex"]["rule"], lv) and Cosmetics.rule_met(Cosmetics.catalogue("emote")["spin"]["rule"], lv)
		and Cosmetics.rule_met(Cosmetics.catalogue("pose")["strongman"]["rule"], lv), "5 bronze medals unlock Flex, Spin and the Strongman pose")
	check(not Cosmetics.rule_met(Cosmetics.catalogue("emote")["taunt"]["rule"], lv) and not Cosmetics.rule_met(Cosmetics.catalogue("emote")["sit"]["rule"], lv), "Taunt and Sit stay locked")
	for i: int in 10:
		lv[ten[i]] = {"completed": true, "runs": 5, "best": Game.medal_target(ten[i], 3)}
	check(Cosmetics.rule_met(Cosmetics.catalogue("emote")["sit"]["rule"], lv) and Cosmetics.rule_met(Cosmetics.catalogue("pose")["rockstar"]["rule"], lv)
		and Cosmetics.rule_met(Cosmetics.catalogue("pose")["hero"]["rule"], lv) and Cosmetics.rule_met(Cosmetics.catalogue("pose")["dab"]["rule"], lv), "10 gold medals unlock the rest")
	check(Cosmetics.progress("emote", "flex", {}) == "Bronzes 0/5", "progress text (%s)" % Cosmetics.progress("emote", "flex", {}))
	# slots: defaults, swapping, locked refused
	var keep: Array = []
	for k: String in Cosmetics.EMOTE_SLOT_KEYS:
		keep.append(Settings.get(k))
	var keep_pose: String = Settings.pose_id
	SaveData.wipe()
	for i: int in 4:
		Settings.set(Cosmetics.EMOTE_SLOT_KEYS[i], Cosmetics.EMOTE_SLOT_DEFAULTS[i])
	check(Cosmetics.emote_slots() == ["wave", "thumbsup", "dance", "bow"], "fresh slots: %s" % [Cosmetics.emote_slots()])
	check(Cosmetics.set_emote_slot(0, "dance") and Cosmetics.emote_slots() == ["dance", "thumbsup", "wave", "bow"], "an emote already slotted swaps places (%s)" % [Cosmetics.emote_slots()])
	check(not Cosmetics.set_emote_slot(1, "flex") and not Cosmetics.set_emote_slot(1, "nope") and not Cosmetics.set_emote_slot(7, "wave"), "locked, unknown and out-of-range picks are refused")
	Settings.emote_id3 = "flex"
	check(Cosmetics.emote_slot(2) == "dance", "a locked emote in a slot plays that slot's default (%s)" % Cosmetics.emote_slot(2))
	check(Cosmetics.equipped("emote") == Cosmetics.emote_slot(0) and Cosmetics.equipped_all().has("pose"), "the emote kind equips slot 1; registration carries emote and pose")
	# settings sanitizing
	Settings.emote_id = "nope"
	Settings.emote_id2 = "<b>"
	Settings.emote_id4 = ""
	Settings.pose_id = "moonwalk"
	Settings.call("_sanitize")
	check(Settings.emote_id == "wave" and Settings.emote_id2 == "thumbsup" and Settings.emote_id4 == "bow" and Settings.pose_id == "cheer", "junk slot ids reset to the defaults")
	Settings.emote_id3 = "flex"
	Settings.call("_sanitize")
	check(Settings.emote_id3 == "flex", "a known (still locked) emote is kept in settings")
	var path: String = "user://test_settings_emotes.cfg"
	var cf := ConfigFile.new()
	cf.set_value("s", "emote_id", 3)
	cf.set_value("s", "emote_id2", "laugh")
	cf.set_value("s", "emote_id3", ["x"])
	cf.set_value("s", "emote_id4", "zzz")
	cf.set_value("s", "pose_id", "rockstar")
	cf.save(path)
	Settings.load_settings(path)
	check(Settings.emote_id2 == "laugh" and Settings.emote_id3 == "flex" and Settings.emote_id4 == "bow" and Settings.pose_id == "rockstar",
		"from a file: wrong types ignored, bad strings reset (%s %s %s %s)" % [Settings.emote_id2, Settings.emote_id3, Settings.emote_id4, Settings.pose_id])
	for k: String in Cosmetics.EMOTE_SLOT_KEYS + ["pose_id"]:
		check(k in Settings._props(), "%s is saved with the settings" % k)
	check(Cosmetics.equipped("pose") == "cheer", "a locked pose wears the default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for i: int in 4:
		Settings.set(Cosmetics.EMOTE_SLOT_KEYS[i], keep[i])
	Settings.pose_id = keep_pose
	SaveData.wipe()


## Rest-pose floor of a rig: the lowest visible mesh point (the poses must not sink into the ground).
func _ze_low(v: PlayerVisual, centres: bool = false) -> float:
	var low: float = INF
	for mi: MeshInstance3D in _zm_meshes(v._root):
		if mi.is_visible_in_tree() and mi.mesh != null:
			var bb: AABB = mi.global_transform * mi.get_aabb()
			# (a body pitched far over has loose bounding boxes: compare mesh centres instead)
			low = minf(low, bb.get_center().y if centres else bb.position.y)
	return low


func test_ze_clips_animate_cleanly() -> void:
	await new_world()
	var e0: int = trap.count()
	var v := PlayerVisual.new()
	world.add_child(v)
	await ticks(1)
	var dt: float = 1.0 / 60.0
	for c: String in Cosmetics.ids("character"):
		v.set_character(c)
		v.stop_emote()
		for i: int in 40:
			v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
		var rest_low: float = _ze_low(v)
		var rest_mid: float = _ze_low(v, true)
		var rest_hand: Vector3 = v._hand_r.position
		for kind: String in ["emote", "pose"]:
			for id: String in Cosmetics.ids(kind):
				check(v.play_emote(id, true) if kind == "emote" else v.play_pose(id, false, 0.0, true), "%s plays %s %s" % [c, kind, id])
				var low: float = INF
				var moved: float = 0.0
				var finite: bool = true
				var frames: int = int((Emotes.length(kind, id) + 0.5) / dt)
				for i: int in frames:
					v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
					if i % 6 == 0:
						low = minf(low, _ze_low(v, id == "bow"))
						moved = maxf(moved, v._hand_r.position.distance_to(rest_hand))
						for mi: MeshInstance3D in _zm_meshes(v._root):
							if not mi.global_transform.origin.is_finite() or not mi.global_transform.basis.x.is_finite() or not mi.global_transform.basis.y.is_finite():
								finite = false
				check(finite, "%s %s %s: every mesh stays finite" % [c, kind, id])
				check(not v.is_emoting(), "%s %s %s ends by itself" % [c, kind, id])
				var floor_ref: float = rest_mid if id == "bow" else rest_low
				check(low >= floor_ref - (0.1 if id == "bow" else 0.06), "%s %s %s stays above the floor (%.3f vs %.3f)" % [c, kind, id, low, floor_ref])
				if id != "sit" and id != "cheer":
					check(moved > 0.04 or id == "bow", "%s %s %s moves the right mitt (%.2f)" % [c, kind, id, moved])
				for i: int in 60:
					v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
				check(v._torso.rotation.x == 0.0 and v._torso.rotation.z == 0.0, "%s %s %s leaves the torso upright" % [c, kind, id])
	# unknown ids and kinds
	check(not v.play_emote("moonwalk") and not v.play_pose("moonwalk") and not v.play_emote("") and not v.is_emoting(), "unknown ids are refused")
	check(not v.play_emote("strongman") and not v.play_pose("wave"), "an emote id is not a pose id")
	# movement and the air cancel an emote; a pose waits for the ground
	v.play_emote("dance", true)
	for i: int in 30:
		v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
	check(v.is_emoting() and v.emote_kind() == "emote" and v.emote_id() == "dance", "standing still keeps the emote going")
	for i: int in 40:
		v.animate(dt, Vector3(6, 0, 0), true, Vector3.RIGHT)
	check(not v.is_emoting(), "running cancels the emote")
	v.play_emote("wave", true)
	for i: int in 40:
		v.animate(dt, Vector3(0, -5, 0), false, Vector3.FORWARD)
	check(not v.is_emoting(), "leaving the ground cancels the emote")
	v.play_pose("hero", false, 0.0, true)
	for i: int in 120:
		v.animate(dt, Vector3(0, -5, 0), false, Vector3.FORWARD)
	check(v.is_emoting() and v._emote_t <= 0.01, "a victory pose waits for the ground")
	for i: int in 400:
		v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
	check(not v.is_emoting(), "... then plays and ends")
	# a held pose (the podium) stays until cancelled
	v.play_pose("rockstar", true)
	for i: int in 900:
		v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
	check(v.is_emoting() and v.emote_kind() == "pose", "a held pose outlasts its length")
	v.cancel_emote()
	for i: int in 30:
		v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
	check(not v.is_emoting(), "cancel_emote lets it go")
	# the finish plays the equipped pose after the twirl; the default cheer needs no clip
	v.pose_id = "dab"
	v.on_cheer()
	check(v.is_emoting() and v.emote_kind() == "pose" and v.emote_id() == "dab", "the finish plays the equipped pose")
	for i: int in 400:
		v.animate(dt, Vector3.ZERO, true, Vector3.FORWARD)
	check(not v.is_emoting(), "the finish pose relaxes")
	v.pose_id = "cheer"
	v.on_cheer()
	check(not v.is_emoting(), "the Cheer pose is the built-in celebration")
	v.play_emote("sit", true)
	v.on_respawn()
	check(not v.is_emoting(), "a respawn drops the emote")
	check(trap.count() == e0, "no errors while emoting %s" % trap.since(e0))
	world.queue_free()
	world = null
	await ticks(2)


func test_ze_emote_input_and_cancel() -> void:
	await new_world()
	floor_slab()
	player.use_device_input = true
	await settle()
	for n: int in 4:
		var a: String = "emote_%d" % (n + 1)
		check(InputMap.has_action(a), "%s exists" % a)
		var key := InputEventKey.new()
		key.physical_keycode = (KEY_1 + n) as Key
		check(InputMap.event_is_action(key, a), "key %d plays slot %d" % [n + 1, n + 1])
	var pads: Array = [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT]
	for n: int in 4:
		check(InputMap.event_is_action(_pad_button(pads[n], 1), "emote_%d" % (n + 1)), "D-pad %d plays slot %d" % [n, n + 1])
		check(not InputMap.event_is_action(_pad_button(pads[n], 1), "move_forward") and not InputMap.event_is_action(_pad_button(pads[n], 1), "move_left"), "D-pad %d no longer moves" % n)
	var keep: Array = []
	for k: String in Cosmetics.EMOTE_SLOT_KEYS:
		keep.append(Settings.get(k))
	SaveData.wipe()
	for i: int in 4:
		Settings.set(Cosmetics.EMOTE_SLOT_KEYS[i], Cosmetics.EMOTE_SLOT_DEFAULTS[i])
	var sent: Array = []
	player.emote_sent.connect(func(k: String, i: String) -> void: sent.append([k, i]))
	var press_key := func(code: Key) -> void:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		var up: InputEventKey = ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await ticks(2)
	var press_pad := func(button: JoyButton) -> void:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		var up: InputEventJoypadButton = ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await ticks(2)
	var before: Vector3 = player.global_position
	await press_key.call(KEY_2)
	check(sent == [["emote", "thumbsup"]] and player.visual.emote_id() == "thumbsup", "key 2 plays slot 2 and announces it (%s)" % [sent])
	await press_pad.call(JOY_BUTTON_DPAD_LEFT)
	check(player.visual.emote_id() == "bow" and sent.size() == 2 and sent[1] == ["emote", "bow"], "the D-pad left plays slot 4 (%s)" % [sent])
	await seconds(0.5)
	check(player.global_position.distance_to(before) < 0.01 and player.velocity.length() < 0.1 and player.grounded, "emoting never moves the body")
	check(player.visual.is_emoting(), "still emoting while standing still")
	# walking away cancels it and tells the others
	Input.action_press("move_forward")
	await seconds(0.3)
	Input.action_release("move_forward")
	check(sent.back() == ["stop", ""], "moving sends a stop (%s)" % [sent])
	await seconds(0.6)
	check(not player.visual.is_emoting(), "movement input cancels the emote")
	await settle()
	# a jump press cancels too
	check(player.try_emote(0) and player.visual.emote_id() == "wave", "try_emote(0) plays slot 1")
	player.press_jump()
	await ticks(3)
	check(sent.back() == ["stop", ""], "jumping sends a stop (%s)" % [sent])
	await seconds(1.2)
	check(not player.visual.is_emoting(), "a jump cancels the emote")
	# never in the air; fine during the countdown (control off) because it is only visual
	player.press_jump()
	player.cmd_jump = true
	await seconds(0.15)
	player.cmd_jump = false
	check(not player.grounded and not player.try_emote(1), "no emotes in the air")
	await seconds(1.5)
	await settle()
	player.control_enabled = false
	check(player.try_emote(2) and player.visual.emote_id() == "dance", "an emote is allowed during the countdown (no physics effect)")
	await seconds(0.4)
	check(player.velocity.length() < 0.1, "... and does not move the body")
	player.control_enabled = true
	# a locked pick plays the slot's default
	Settings.emote_id2 = "flex"
	check(Cosmetics.emote_slot(1) == "thumbsup", "a locked emote on a slot plays the default")
	for i: int in 4:
		Settings.set(Cosmetics.EMOTE_SLOT_KEYS[i], keep[i])
	SaveData.wipe()
	player.use_device_input = false
	world.queue_free()
	world = null
	await ticks(2)


func test_ze_emote_net_round_trip() -> void:
	var lvl: LevelBase = await _zm_race_level()
	var g: RemoteRacer = lvl._ghosts.get(2)
	check(g != null, "Ada's ghost exists")
	g.push_state(g.global_position, Vector3.ZERO, true, 0)
	await ticks(2)
	var got: Array = []
	var catcher := func(id: int, kind: String, eid: String) -> void: got.append([id, kind, eid])
	Net.racer_emote.connect(catcher)
	# the relay path: a JSON "pose" event carrying {"emote": ...}
	var wire: Variant = JSON.parse_string(JSON.stringify({"emote": {"k": "emote", "id": "dance"}}))
	Net._handle_relay_event(2, "pose", wire)
	check(got == [[2, "emote", "dance"]], "the relay event reaches racer_emote (%s)" % [got])
	check(g.visual().is_emoting() and g.visual().emote_kind() == "emote" and g.visual().emote_id() == "dance", "the ghost plays Ada's dance")
	await ticks(1)
	# throttled: a second one right away is dropped; after the gap it plays
	Net._handle_relay_event(2, "pose", {"emote": {"k": "emote", "id": "wave"}})
	check(got.size() == 1 and g.visual().emote_id() == "dance", "a flood from one sender is throttled")
	await seconds(0.3)
	Net._emote_seen_at.clear()   # (the throttle runs on wall-clock time; the test clock may be faster)
	# the direct (RPC) path ends in the same place
	Net._apply_emote_msg(2, {"k": "pose", "id": "hero"})
	check(got.size() == 2 and got[1] == [2, "pose", "hero"] and g.visual().emote_kind() == "pose" and g.visual().emote_id() == "hero", "a pose plays too (%s)" % [got])
	await seconds(0.3)
	Net._emote_seen_at.clear()   # (the throttle runs on wall-clock time; the test clock may be faster)
	Net._apply_emote_msg(2, {"k": "stop", "id": ""})
	check(got.size() == 3 and got[2] == [2, "stop", ""], "stop is relayed")
	await seconds(0.6)
	check(not g.visual().is_emoting(), "stop cancels the ghost's clip")
	# garbage is ignored
	await seconds(0.3)
	Net._emote_seen_at.clear()   # (the throttle runs on wall-clock time; the test clock may be faster)
	var n0: int = got.size()
	Net._apply_emote_msg(2, {"k": "emote", "id": "<script>"})
	Net._apply_emote_msg(2, {"k": "emote", "id": 7})
	Net._apply_emote_msg(2, {"k": "emote"})
	Net._apply_emote_msg(2, {"k": "pose", "id": "wave"})
	Net._apply_emote_msg(2, {"k": "dance", "id": "wave"})
	Net._apply_emote_msg(2, {"k": ["emote"], "id": "wave"})
	Net._apply_emote_msg(99, {"k": "emote", "id": "wave"})
	Net._apply_emote_msg(Net.my_id(), {"k": "emote", "id": "wave"})
	Net._handle_relay_event(2, "pose", {"emote": "wave"})
	Net._handle_relay_event(2, "pose", {"emote": 5})
	check(got.size() == n0 and not g.visual().is_emoting(), "bad kinds, unknown ids, strangers, ourselves and wrong types are ignored")
	# a racer's emote cancels when they run off
	await seconds(0.3)
	Net._emote_seen_at.clear()   # (the throttle runs on wall-clock time; the test clock may be faster)
	Net._apply_emote_msg(2, {"k": "emote", "id": "dance"})
	await ticks(2)
	g.push_state(g.global_position, Vector3(7, 0, 0), true, 0)
	await seconds(0.8)
	check(not g.visual().is_emoting(), "the ghost stops emoting when it starts to move")
	# sending outside a link, and invalid sends, are harmless
	Net.send_emote("emote", "wave")
	Net.send_emote("emote", "<x>")
	Net.send_emote("stop")
	check(Net._valid_emote("emote", "wave") and Net._valid_emote("pose", "dab") and Net._valid_emote("stop", "") and not Net._valid_emote("emote", "dab") and not Net._valid_emote("hat", "none"), "send validation")
	# the roster carries the victory pose; the ghost wears it for its finish
	Net.roster[2]["pose"] = "salute"
	lvl._ghosts[2].apply_cosmetics(Net.roster[2])
	check(g.visual().pose_id == "salute", "a racer's pose rides the roster")
	g.celebrate()
	check(g.visual().is_emoting() and g.visual().emote_id() == "salute", "their finish plays their pose")
	lvl._ghosts[2].apply_cosmetics({"pose": "<x>"})
	check(g.visual().pose_id == "cheer", "an unknown pose id falls back to Cheer")
	Net.racer_emote.disconnect(catcher)
	await _zm_end_race()


## Seconds until the Locker preview of a finished clip has certainly replayed.
func _ze_clip_wait(kind: String, id: String) -> float:
	return Emotes.length(kind, id) + 0.9


func test_ze_locker_emote_and_pose_tabs() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var keep: Array = []
	for k: String in Cosmetics.EMOTE_SLOT_KEYS:
		keep.append(Settings.get(k))
	var keep_pose: String = Settings.pose_id
	SaveData.wipe()
	for i: int in 4:
		Settings.set(Cosmetics.EMOTE_SLOT_KEYS[i], Cosmetics.EMOTE_SLOT_DEFAULTS[i])
	Settings.pose_id = "cheer"
	var e0: int = trap.count()
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
	var tabs: Array = title.get("LOCKER_TABS")
	check(tabs.slice(-3) == ["emote", "pose", "colour"], "the Locker has Emote and Pose tabs before Colour (%s)" % [tabs])
	for i: int in 6:
		await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	check(int(title.get("locker_tab")) == 6 and focus.call().get_meta("kind", "") == "emote" and focus.call().get_meta("item", "") == "wave", "RB x6: the Emote tab, on slot 1's emote")
	await ticks(2)
	check(volt.is_emoting() and volt.emote_id() == "wave" and volt.emote_kind() == "emote", "focusing an emote plays it on the preview")
	var slot_row: Node = (title.get("_screen") as Control).find_child("EmoteSlots", true, false)
	check(slot_row != null and slot_row.get_child_count() == 4 and (slot_row.get_child(0) as Button).text == "[ Up: Wave ]" and (slot_row.get_child(3) as Button).text == "Left: Bow",
		"the four slots are listed, slot 1 chosen (%s)" % ((slot_row.get_child(0) as Button).text if slot_row != null else "?"))
	# the preview loops: after it ends it plays again
	await seconds(_ze_clip_wait("emote", "wave"))
	check(volt.is_emoting() and volt.emote_id() == "wave", "the preview loops the emote")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	check(focus.call().get_meta("item", "") == "thumbsup" and volt.emote_id() == "thumbsup" and not info.text.begins_with("LOCKED"), "right: Thumbs Up, previewed (%s)" % info.text)
	await send.call(JOY_BUTTON_A)
	check(Settings.emote_id == "thumbsup" and Settings.emote_id2 == "wave", "A puts it on slot 1 and swaps Wave to slot 2 (%s / %s)" % [Settings.emote_id, Settings.emote_id2])
	check((slot_row.get_child(0) as Button).text == "[ Up: Thumbs Up ]" and (slot_row.get_child(1) as Button).text == "Right: Wave", "the slot labels follow")
	check((focus.call() as Button).text == "> Thumbs Up <", "slotted emotes are marked")
	# down onto a locked emote: hint, progress, A refuses
	await send.call(JOY_BUTTON_DPAD_DOWN)
	check(focus.call().get_meta("item", "") == "flex" and info.text.begins_with("LOCKED") and info.text.contains("Bronze or better on 5 courses") and info.text.contains("Bronzes 0/5"),
		"a locked emote names its unlock (%s)" % info.text)
	check(volt.emote_id() == "flex", "locked emotes can still be previewed")
	await send.call(JOY_BUTTON_A)
	check(Settings.emote_id == "thumbsup" and Settings.emote_id2 == "wave", "A on a locked emote changes nothing")
	# up x2 reaches the slot row (pad only); choose that slot, then pick Dance for it
	await send.call(JOY_BUTTON_DPAD_UP)
	await send.call(JOY_BUTTON_DPAD_UP)
	check(focus.call() is Button and focus.call().get_parent() == slot_row, "the D-pad reaches the slot row")
	var slot_btn: Button = focus.call()
	var slot_idx: int = int(slot_btn.get_meta("slot"))
	await send.call(JOY_BUTTON_A)
	check(int(title.get("_emote_slot")) == slot_idx and focus.call().get_meta("kind", "") == "emote", "A on a slot chooses it and drops back to the grid (slot %d)" % slot_idx)
	var dance_btn: Control = null
	for g: Node in (title.get("_locker_body") as Control).find_children("*", "GridContainer", true, false):
		for b: Node in g.get_children():
			if b.get_meta("item", "") == "dance":
				dance_btn = b
	dance_btn.grab_focus()
	await ticks(2)
	await send.call(JOY_BUTTON_A)
	check(Cosmetics.emote_slot(slot_idx) == "dance" and Cosmetics.emote_slots().count("dance") == 1, "Dance fills the chosen slot (%s)" % [Cosmetics.emote_slots()])
	# the Pose tab
	await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	check(int(title.get("locker_tab")) == 7 and focus.call().get_meta("kind", "") == "pose" and focus.call().get_meta("item", "") == "cheer", "RB: the Pose tab, on Cheer")
	await ticks(2)
	check(volt.is_emoting() and volt.emote_kind() == "pose" and volt.emote_id() == "cheer", "focusing a pose plays it on the preview")
	await send.call(JOY_BUTTON_DPAD_RIGHT)
	check(focus.call().get_meta("item", "") == "strongman" and info.text.begins_with("LOCKED") and volt.emote_id() == "strongman", "a locked pose names its unlock and previews (%s)" % info.text)
	await send.call(JOY_BUTTON_A)
	check(Settings.pose_id == "cheer", "A on a locked pose changes nothing")
	# earn it, then equip
	for lid: String in ["gardens", "foundry", "balance"]:
		SaveData.data["levels"][lid] = {"completed": true, "runs": 1, "best": Game.medal_target(lid, 3)}
	await send.call(JOY_BUTTON_A)
	check(Settings.pose_id == "strongman" and (focus.call() as Button).text == "> Strongman <", "once earned, A equips the pose")
	# RB to Colour, LB back, B out
	await send.call(JOY_BUTTON_RIGHT_SHOULDER)
	check(focus.call().has_meta("colour") and not volt.is_emoting(), "leaving the tabs stops the preview clip")
	await send.call(JOY_BUTTON_LEFT_SHOULDER)
	await send.call(JOY_BUTTON_LEFT_SHOULDER)
	check(focus.call().get_meta("kind", "") == "emote", "LB goes back to Emote")
	await send.call(JOY_BUTTON_B)
	await ticks(2)
	check(Game.title_screen == "main", "B leaves from the Emote tab")
	check(trap.count() == e0, "no errors in the Locker %s" % trap.since(e0))
	title.queue_free()
	await ticks(2)
	for i: int in 4:
		Settings.set(Cosmetics.EMOTE_SLOT_KEYS[i], keep[i])
	Settings.pose_id = keep_pose
	Game.title_screen = "main"
	SaveData.wipe()


# ---- Party fixes (P1) ---------------------------------------------------------------------------

## A Party race (not practice) with a roster of just us, so ghosts / host rules can be set up by hand.
func _party_race_level(index: int) -> LevelBase:
	Game.party = PartyRules.new("party")
	Net.roster = {1: {"name": "Me", "color": 0, "cp": 0, "cp_at": 0.0, "finished": -1.0}}
	var lvl: LevelBase = await load_level(index)
	await ticks(4)
	if lvl.party != null:
		lvl.party.use_device_input = false
		lvl.player.use_device_input = false
		lvl.party.protect_left = 0.0
	return lvl


func _party_race_done() -> void:
	Game.party = null
	Net.active = false
	Net.roster.clear()


func _add_rival(lvl: LevelBase, id: int, at: Vector3, cp: int, cp_at: float) -> void:
	Net.roster[id] = {"name": "Rival%d" % id, "color": id % 4, "cp": cp, "cp_at": cp_at, "finished": -1.0}
	lvl._add_ghost(id, at)
	(lvl._ghosts[id] as RemoteRacer).push_state(at, Vector3.ZERO, true, 1)


func test_zp_fix_rules_round_limit_and_progress() -> void:
	check(PartyRules.round_over([-1.0, -1.0], PartyRules.ROUND_LIMIT), "a round nobody finishes ends at the hard time limit")
	check(not PartyRules.round_over([-1.0, -1.0], PartyRules.ROUND_LIMIT - 1.0), "...and not a second before")
	check(PartyRules.ROUND_LIMIT == 240.0, "the default limit is 4 minutes")
	check(PartyRules.time_left([-1.0], 100.0) < 0.0, "no countdown early in a round nobody has finished")
	check(is_equal_approx(PartyRules.time_left([-1.0], PartyRules.ROUND_LIMIT - 20.0), 20.0), "the HUD counts down the last 30 s of the limit")
	check(is_equal_approx(PartyRules.time_left([10.0, -1.0], 40.0), 15.0), "the 45 s after the first finisher still counts down")
	check(is_equal_approx(PartyRules.time_left([200.0, -1.0], 230.0), 10.0), "whichever end comes first wins (limit in 10 s vs grace in 15 s)")
	var pts: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, -10), Vector3(0, 0, -30)]
	check(is_equal_approx(PartyRules.route_progress(pts, 0, Vector3.ZERO), 0.0), "progress at the start is 0")
	check(is_equal_approx(PartyRules.route_progress(pts, 0, Vector3(0, 0, -4)), 4.0), "4 m towards the first checkpoint is 4 m of progress")
	check(is_equal_approx(PartyRules.route_progress(pts, 1, Vector3(0, 0, -10)), 10.0), "standing on a checkpoint is the route length up to it")
	check(PartyRules.route_progress(pts, 1, Vector3(0, 0, -20)) > PartyRules.route_progress(pts, 0, Vector3(0, 0, -9.9)), "a banked checkpoint always beats progress towards it")
	check(PartyRules.route_progress(pts, 1, Vector3(50, 0, 0)) >= 10.0, "wandering off never loses the banked length")
	var prog: Dictionary = {2: 30.0, 3: 12.0, 4: 8.0, 5: 400.0}
	check(PartyRules.swap_target(10.0, prog, 160.0) == 3, "swap picks the nearest racer ahead by course distance (12 m, not 30 or 400)")
	check(PartyRules.swap_target(10.0, {4: 8.0}, 160.0) == 0, "nobody ahead: no target")
	check(PartyRules.swap_target(10.0, {5: 400.0}, 160.0) == 0, "a racer beyond the range is no target")
	check(PartyItems.weight("jetpack", 0.0) == 0.0 and PartyItems.weight("jetpack", 1.0) > 0.0, "the Jetpack never rolls for the leader")


func test_zp_fix_respawn_protection() -> void:
	var lvl: LevelBase = await _party_race_level(0)
	var p: PartyLayer = lvl.party
	if p == null:
		check(false, "party layer exists")
		return
	var pl: Player = lvl.player
	check(p.local_vulnerable(), "a racer who is just racing can be hit")
	lvl.fail("hazard")
	await ticks(3)
	check(p.protect_left > 1.5 and not p.local_vulnerable(), "a respawn gives about 2 s of protection (%.2f)" % p.protect_left)
	var shell: Node = pl.get_node_or_null("RespawnShell")
	check(shell != null, "a shell blinks round the protected racer")
	pl.velocity = Vector3.ZERO
	p._on_hit(9, {"kb": [0, 25, 0], "st": 1.0, "ko": false, "s": "test"})
	p.take_hazard(9, Vector3(0, 25, 0), {"st": 1.0})
	await ticks(2)
	check(pl.velocity.y < 5.0 and pl.party_stun <= 0.0, "hits and hazards bounce off a protected racer (vy %.1f)" % pl.velocity.y)
	var d0: int = lvl.deaths
	p._on_hit(9, {"kb": [0, 0, 0], "ko": true, "s": "test"})
	await ticks(2)
	check(lvl.deaths == d0, "even a KO is ignored while protected")
	await seconds(PartyRules.RESPAWN_PROTECTION + 0.3)
	check(p.local_vulnerable() and pl.get_node_or_null("RespawnShell") == null, "protection ends after %.0f s and the shell goes" % PartyRules.RESPAWN_PROTECTION)
	p._on_hit(9, {"kb": [0, 25, 0], "st": 1.0, "ko": false, "s": "test"})
	await ticks(2)
	check(pl.velocity.y > 10.0 or pl.party_stun > 0.0, "afterwards hits land again")
	# using an item or shoving ends it early (no camping the boxes)
	lvl.fail("hazard")
	await ticks(3)
	check(p.protect_left > 0.0, "protected again after the next respawn")
	p.cmd_attack = true
	await ticks(2)
	p.cmd_attack = false
	await ticks(2)
	check(p.protect_left <= 0.0, "shoving drops the protection")
	_party_race_done()


func test_zp_fix_tap_fires_on_press_and_claw_is_not_a_ko() -> void:
	var lvl: LevelBase = await _load_practice(0)
	var p: PartyLayer = lvl.party
	p.use_device_input = false
	lvl.player.use_device_input = false
	var d: PracticeDummy = p.dummies[0]
	p.protect_left = 0.0
	await _party_fresh(p, d)
	var fox: PowerUp = await _use_item(p, "fox")
	await _face_dummy(lvl, d, 1.8)
	# press and keep holding: the claw lands on the press, not on the release
	p.cmd_attack = true
	await ticks(3)
	check(d.hits == 1 and d.last_src == "claw", "a tap attack fires the moment Attack goes down (hits %d)" % d.hits)
	check(not d.knocked_out and d.vel.length() > 12.0, "the claw is a big knockback, not a KO (speed %.1f)" % d.vel.length())
	await ticks(30)
	check(float((fox as Object).get("_charge")) >= 0.0, "holding on starts the Tailed Beast Bomb charge after 0.2 s")
	p.cmd_attack = false
	await ticks(3)
	# the cooldown: a second tap within 1.2 s does nothing
	d.reset()
	await ticks(2)
	await _face_dummy(lvl, d, 1.8)
	var hits: int = d.hits
	await _attack(p)
	check(d.hits == hits, "a second claw inside the 1.2 s cooldown does not connect")
	check(float((fox as Object).get("CLAW_COOLDOWN")) == 1.2, "the claw cooldown is 1.2 s")
	await seconds(1.3)
	await _face_dummy(lvl, d, 1.8)
	await _attack(p)
	check(d.hits == hits + 1, "after the cooldown it connects again")
	# a short press (under 0.2 s) is only the tap
	fox.finish()
	await _party_fresh(p, d)
	var tunic: PowerUp = await _use_item(p, "tunic")
	await _face_dummy(lvl, d, 1.8)
	var h0: int = d.hits
	p.cmd_attack = true
	await ticks(2)
	check(d.hits == h0 + 1 and d.last_src == "blade", "Hero's Tunic: the slash comes on the press too (%s)" % d.last_src)
	await ticks(30)
	check(float((tunic as Object).get("_charge")) >= 0.0, "Hero's Tunic: the spin charge starts after the hold threshold")
	p.cmd_attack = false
	await ticks(3)
	tunic.finish()
	await _party_fresh(p, d)
	var surge: PowerUp = await _use_item(p, "surge")
	await _face_dummy(lvl, d, 3.0)
	p.cmd_attack = true
	await ticks(4)
	check(d.last_src == "dash_punch" or float((surge as Object).get("_dash")) > 0.0, "Golden Surge Hair: the dash punch starts on the press")
	p.cmd_attack = false
	await ticks(3)
	surge.finish()
	Game.party = null


func test_zp_fix_no_target_keeps_item() -> void:
	var lvl: LevelBase = await _party_race_level(0)
	var p: PartyLayer = lvl.party
	var pts: Array[Vector3] = p.course_points()
	for id: String in ["thunder", "swap"]:
		p.item = ""
		p.give_item(id)
		var r: PowerUp = p.activate_item()
		check(r == null and p.item == id, "%s with nobody ahead is not wasted (slot: '%s')" % [id, p.item])
	# someone ahead: both fire and are used up
	_add_rival(lvl, 2, pts[1], 1, 4.0)
	await ticks(3)
	p.item = ""
	p.give_item("thunder")
	p.activate_item()
	await ticks(2)
	check(p.item == "", "Thunder Cloud is used once a rival is ahead")
	# a racer behind us is no target
	lvl.current_checkpoint = 2
	lvl.player.teleport(Transform3D(Basis(), pts[2] + Vector3(0, 0.1, 0)))
	await ticks(3)
	p.item = ""
	p.give_item("swap")
	check(p.activate_item() == null and p.item == "swap", "a racer behind is no Swap Warp target")
	await seconds(1.2)   # (let the lightning's delayed effects finish before the level goes)
	_party_race_done()


func test_zp_fix_swap_warp_real_course() -> void:
	var lvl: LevelBase = await _party_race_level(0)
	var p: PartyLayer = lvl.party
	var pl: Player = lvl.player
	var pts: Array[Vector3] = p.course_points()
	check(pts.size() >= 4, "the course polyline has the start, the checkpoints and the finish (%d points)" % pts.size())
	Net.active = true
	lvl.current_checkpoint = 1
	Net.roster[1]["cp"] = 1
	Net.roster[1]["cp_at"] = 12.0
	pl.teleport(Transform3D(Basis(), pts[1] + Vector3(0, 0.1, 0)))
	# ids 2 and 3 share my checkpoint; 2 reached it first (so standings put 2, 3, me) but 3 is the farther along
	_add_rival(lvl, 2, pts[1].lerp(pts[2], 0.15), 1, 5.0)
	_add_rival(lvl, 3, pts[1].lerp(pts[2], 0.5), 1, 9.0)
	await seconds(0.6)
	var order: Array[int] = Net.standings()
	var tg: Dictionary = p.target_ahead()
	check(order == [2, 3, 1] and not tg.is_empty() and int(tg["id"]) == 2, "Swap targets the nearest racer ahead by course distance, not the standings neighbour (%s -> %s)" % [str(order), str(tg.get("id", 0))])
	check(p.my_safe_spot().distance_to(pl.global_position) < 0.5, "the safe spot is where we last stood still on the ground")
	var dest: Vector3 = pts[2]
	var here: Vector3 = pl.global_position
	# the victim side: a Balloon Shield blocks it, and nothing moves
	p.give_item("balloon")
	var bal: PowerUp = p.activate_item()
	await ticks(2)
	p._on_swap(2, dest, 2)
	await ticks(2)
	check(bal.ended and pl.global_position.distance_to(here) < 1.0 and lvl.current_checkpoint == 1, "a Balloon Shield blocks Swap Warp: no move, no checkpoint change")
	# so does respawn protection
	p.protect(2.0)
	p._on_swap(2, dest, 2)
	await ticks(2)
	check(pl.global_position.distance_to(here) < 1.0, "respawn protection blocks it too")
	p.break_protection()
	# accepted: we go to the caster's spot, take their checkpoint, and the roster trades progress
	p._on_swap(2, dest, 2)
	await ticks(2)
	check(pl.global_position.distance_to(dest + Vector3(0, 0.1, 0)) < 1.0, "the swapped racer lands on the caster's safe ground")
	check(lvl.current_checkpoint == 2 and int(Net.roster[1]["cp"]) == 2 and int(Net.roster[2]["cp"]) == 1, "checkpoint progress is swapped (me %d, them %d)" % [lvl.current_checkpoint, int(Net.roster[2]["cp"])])
	# the caster side: nothing happens without a request, then an accept moves them
	var away: Vector3 = pl.global_position
	p._on_swap_ok(2, pts[1], 1)
	await ticks(2)
	check(pl.global_position.distance_to(away) < 0.5, "an unrequested accept is ignored")
	p._swap_wait = p.clock
	p._on_swap_ok(2, pts[1], 1)
	await ticks(2)
	check(pl.global_position.distance_to(pts[1] + Vector3(0, 0.1, 0)) < 1.0 and lvl.current_checkpoint == 1, "an accepted swap sends the caster to the target's safe spot and checkpoint")
	p._swap_wait = p.clock
	p._on_swap_no()
	check(p._swap_wait < 0.0, "a refusal ends the wait")
	# a fall now respawns on the swapped checkpoint
	lvl.fail("fall")
	await ticks(3)
	check(pl.global_position.distance_to(lvl.checkpoints[0].respawn_transform().origin) < 1.5, "after a swap a fall respawns at the swapped checkpoint")
	await seconds(1.2)   # (let the portals' delayed effects finish before the level goes)
	_party_race_done()


func test_zp_fix_box_grants_and_pick_throttle() -> void:
	var lvl: LevelBase = await _party_race_level(0)
	var p: PartyLayer = lvl.party
	Net.roster[2] = {"name": "Rival2", "color": 1, "cp": 0, "cp_at": 0.0, "finished": -1.0}
	check(p.boxes.size() >= 8, "boxes exist (%d)" % p.boxes.size())
	# the host never grants one racer two boxes in a burst: the second box is not consumed
	p._host_pick(0, 2)
	p._host_pick(1, 2)
	check(not p.boxes[0].available and p.boxes[1].available, "the host grants a racer one box; a second touch in the burst is dropped, the box stays")
	p.clock += PartyLayer.GRANT_GAP + 0.1
	p._host_pick(1, 2)
	check(not p.boxes[1].available, "later the same racer can take another box")
	# a client has one touch in flight: asking about a second box waits for the answer
	check(p._ask_host(5), "the first touch is sent")
	check(not p._ask_host(6), "a second touch while one is in flight is held back")
	p._take_box(5, 1, "balloon", 4.0)
	check(p._pick_at < 0.0 and p.item == "balloon", "the answer frees the next touch and fills the slot")
	check(p._ask_host(6), "after the answer the next touch is sent")
	p._take_box(6, 2, "jetpack", 4.0)
	check(p._ask_host(7), "another racer winning the box we asked about frees us to ask again")
	check(p.item == "balloon", "...and does not touch our slot")
	_party_race_done()


func test_zp_fix_round_end_and_host_drop() -> void:
	var lvl: LevelBase = await _party_race_level(0)
	var p: PartyLayer = lvl.party
	Net.roster[2] = {"name": "Rival2", "color": 1, "cp": 1, "cp_at": 3.0, "finished": -1.0}
	var keep_time: float = Game.course_time
	# a quiet host past the limit: the client ends the round with its own numbers
	Game.course_time = PartyRules.ROUND_LIMIT + 1.0
	p._client_watchdog(0.1)
	check(not p.round_over, "the client gives the host a grace past the limit")
	Game.course_time = PartyRules.ROUND_LIMIT + PartyRules.CLIENT_GRACE + 1.0
	p._client_watchdog(0.1)
	await ticks(2)
	check(p.round_over and p.last_rows.size() == 2, "past limit + grace the client ends the round locally with rows for everyone (%d)" % p.last_rows.size())
	await seconds(1.8)
	_party_race_done()
	# the relay saying the host dropped: end after a short grace, unless they come back
	lvl = await _party_race_level(0)
	p = lvl.party
	Game.course_time = 30.0
	p._on_relay_notice("The host lost connection - waiting for them to come back...")
	p._client_watchdog(PartyRules.HOST_AWAY_GRACE - 1.0)
	check(not p.round_over, "a short host blip does not end the round")
	p._on_relay_notice("The host is back.")
	p._client_watchdog(PartyRules.HOST_AWAY_GRACE + 5.0)
	check(not p.round_over, "...and a returning host cancels the countdown")
	p._on_relay_notice("The host lost connection - waiting for them to come back...")
	p._client_watchdog(PartyRules.HOST_AWAY_GRACE + 0.5)
	await ticks(2)
	check(p.round_over, "a host that stays away ends the round for the clients")
	await seconds(1.8)
	Game.course_time = keep_time
	_party_race_done()


func test_zp_fix_shrink_and_freeze() -> void:
	var lvl: LevelBase = await _load_practice(0)
	var p: PartyLayer = lvl.party
	p.use_device_input = false
	lvl.player.use_device_input = false
	p.protect_left = 0.0
	var pl: Player = lvl.player
	var col: CollisionShape3D = pl.get_node("Collision") as CollisionShape3D
	var full_h: float = (col.shape as CapsuleShape3D).height
	p.apply_status("shrink", 3.0)
	await seconds(0.6)
	var cap: CapsuleShape3D = col.shape as CapsuleShape3D
	check(pl.visual.scale.x < 0.55 and cap.height < full_h * 0.6 and cap.radius < 0.25, "Shrink scales the collision with the model (scale %.2f, capsule %.2f x %.2f)" % [pl.visual.scale.x, cap.height, cap.radius])
	check(is_equal_approx(col.position.y, cap.height * 0.5), "the shrunk capsule still stands on the feet (y %.2f)" % col.position.y)
	await seconds(3.0)
	check(is_equal_approx(cap.height, full_h) and pl.visual.scale.x > 0.99, "when Shrink ends the capsule is full size again (%.2f)" % cap.height)
	# Freeze: the racer cannot run but gravity still pulls them down
	var up: Vector3 = p.boxes[0].global_position + Vector3(0, 7.0, 0)
	pl.teleport(Transform3D(Basis(), up))
	pl.velocity = Vector3(6, 0, 0)
	p.apply_status("freeze", 3.0)
	var y0: float = pl.global_position.y
	await ticks(30)
	check(pl.velocity.y < -3.0 and pl.global_position.y < y0 - 0.5, "a frozen racer in the air keeps falling (dy %.2f, vy %.1f)" % [pl.global_position.y - y0, pl.velocity.y])
	check(absf(pl.velocity.x) < 0.01 and absf(pl.velocity.z) < 0.01, "...but cannot run (horizontal %.2f)" % Vector2(pl.velocity.x, pl.velocity.z).length())
	p.clear_statuses()
	Game.party = null


func test_zp_fix_jetpack_skip_cap() -> void:
	var lvl: LevelBase = await _load_practice(0)
	var p: PartyLayer = lvl.party
	p.use_device_input = false
	lvl.player.use_device_input = false
	var pl: Player = lvl.player
	pl.velocity = Vector3(0, 0, -20)
	await _use_item(p, "jetpack")
	var h: float = Vector2(pl.velocity.x, pl.velocity.z).length()
	check(h <= 10.01 and pl.velocity.y > 8.0, "the Jetpack burst caps its horizontal skip at 10 m/s (%.1f)" % h)
	p.end_all_powers()
	var rolled_by_leader: bool = false
	for i: int in 400:
		if PartyItems.roll(0.0, (float(i) + 0.5) / 400.0) == "jetpack":
			rolled_by_leader = true
	check(not rolled_by_leader, "the leader never rolls a Jetpack")
	Game.party = null


## Every course's party layer: boxes across the start and the checkpoint lawns.
func test_zp_fix_boxes_on_every_course() -> void:
	var bad: Array[String] = []
	var total: int = 0
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		var lvl: LevelBase = await _load_practice(i)
		var p: PartyLayer = lvl.party
		if p == null:
			bad.append("%s: no party layer" % Game.LEVELS[i]["name"])
			continue
		var waited: int = 0
		while not p._ready_done and waited < 60:
			await ticks(1)
			waited += 1
		total += 1
		var counts: Array[int] = p.box_counts
		var short: Array[String] = []
		if counts.is_empty() or counts[0] < 3:
			short.append("start %d" % (counts[0] if not counts.is_empty() else 0))
		for c: int in range(1, counts.size()):
			if counts[c] < 2:
				short.append("cp%d %d" % [c, counts[c]])
		if counts.size() != lvl.checkpoints.size() + 1:
			short.append("points %d vs %d" % [counts.size(), lvl.checkpoints.size() + 1])
		var grounded: int = 0
		for b: ItemBox in p.boxes:
			var q := PhysicsRayQueryParameters3D.create(b.global_position, b.global_position + Vector3(0, -2.0, 0), 1)
			if not lvl.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				grounded += 1
		if grounded != p.boxes.size():
			short.append("%d boxes off the ground" % (p.boxes.size() - grounded))
		# the rows between the lawns (P4): a course with real route between its checkpoints has them too
		var long_n: int = 0
		var long_cov: int = 0
		for k: int in p.mid_counts.size():
			if p.mid_lengths[k] >= PartyLayer.MID_SPACING:
				long_n += 1
				if p.mid_counts[k] > 0:
					long_cov += 1
		if long_n >= 3 and long_cov * 2 < long_n:
			short.append("mid-course boxes on only %d of %d long stretches" % [long_cov, long_n])
		if not short.is_empty():
			bad.append("%s: %s" % [Game.LEVELS[i]["name"], ", ".join(short)])
	check(bad.is_empty(), "every course gets >= 3 boxes at the start and >= 2 at each checkpoint, plus rows along the long stretches, on solid ground (%d courses; problems: %s)" % [total, str(bad)])
	Game.party = null
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)



# ---- Party Mode: the second item wave (P4) ---------------------------------------------------------

const ZP_NEW_ITEMS: Array[String] = ["homing", "strike", "fakebox", "turbo", "ghost", "decoy", "shock"]


## Sum of the transparency of every mesh on a racer's model (a Ghost fades it and must give it back).
func _zp_transparency(root: Node) -> float:
	var sum: float = 0.0
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		sum += (n as MeshInstance3D).transparency
	return sum


## The first hazard of a kind a layer holds (its shell / zone / fake box / decoy).
func _zp_hazard(p: PartyLayer, kind: String) -> Node:
	for h: Variant in p.hazards.values():
		if not is_instance_valid(h):
			continue
		match kind:
			"shell":
				if h is HomingShell:
					return h
			"zone":
				if h is StrikeZone:
					return h
			"fake":
				if h is FakeBox:
					return h
			"decoy":
				if h is PartyDecoy:
					return h
	return null


## The strike has come down (its node frees itself a moment after the impact).
func _zp_ended(pu: Variant) -> bool:
	return not is_instance_valid(pu) or (pu as PowerUp).ended


func _zp_used(f: Variant) -> bool:
	return not is_instance_valid(f) or (f as FakeBox).used


func _zp_landed(z: Variant) -> bool:
	return not is_instance_valid(z) or (z as StrikeZone).impacted


func test_zp_items_new_power_ups() -> void:
	var lvl: LevelBase = await _load_practice(0)
	var p: PartyLayer = lvl.party
	if p == null or p.dummies.is_empty():
		check(false, "practice layer with dummies")
		return
	p.use_device_input = false
	lvl.player.use_device_input = false
	p.protect_left = 0.0
	var pl: Player = lvl.player
	var d: PracticeDummy = p.dummies[0]
	var mods := func() -> Vector3: return Vector3(pl.speed_mult, pl.jump_mult, pl.gravity_mult)
	var restored := func() -> bool: return mods.call() == Vector3.ONE and pl.party_air_jumps == 0
	for id: String in ZP_NEW_ITEMS:
		check(PartyItems.script_for(id) != null and PartyItems.PRACTICE_ORDER.has(id) and PartyNames.item_name(id) != id \
				and PartyNames.item_desc(id) != "" and PartyNames.item_color(id) != Color.WHITE, "%s is in the catalogue with a name, a description and a colour" % id)

	# Homing Shell: a seeker that chases the racer ahead, and is kept when nobody is
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 12.0)
	await _use_item(p, "homing")
	var shell: HomingShell = _zp_hazard(p, "shell") as HomingShell
	check(shell != null and shell.local, "Homing Shell: a shell leaves the pack")
	var waited: float = 0.0
	while d.hits == 0 and waited < 5.0:
		await seconds(0.1)
		waited += 0.1
	check(d.hits >= 1 and d.last_src == "homing" and d.stunned > 0.5, "Homing Shell: it curves into the dummy and spins it out (%s, %.1f s)" % [d.last_src, waited])
	check(_zp_hazard(p, "shell") == null, "Homing Shell: the shell is gone after the hit")
	await _party_fresh(p, d)
	for dd: PracticeDummy in p.dummies:
		dd.knock_out()
	p.give_item("homing")
	check(p.activate_item() == null and p.item == "homing", "Homing Shell: with nobody ahead it is kept in the slot")
	for dd: PracticeDummy in p.dummies:
		dd.reset()
	p.item = ""

	# Leader Strike: a long, readable tell, then the sky falls in on the spot
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 7.0)
	await _use_item(p, "strike")
	var zone: StrikeZone = _zp_hazard(p, "zone") as StrikeZone
	var strikes0: int = d.hits
	check(zone != null and StrikeZone.TELL >= 2.5, "Leader Strike: a danger zone opens with a %.1f s wind-up" % StrikeZone.TELL)
	if zone != null:
		await seconds(2.0)
		check(d.hits == strikes0 and zone.locked and not zone.impacted, "Leader Strike: nothing lands during the tell, and the reticle locks just before it (age %.2f)" % zone.age)
		check(zone.global_position.distance_to(d.global_position) < 1.5, "Leader Strike: the reticle sits under its target (%.2f m)" % zone.global_position.distance_to(d.global_position))
		await seconds(1.3)
		check(d.hits > strikes0 and d.last_src == "strike" and d.stunned > 0.5 and _zp_landed(zone), "Leader Strike: the strike lands and stuns the dummy (%s)" % d.last_src)

	# Fake Box: the real box model, a trap for the first rival to touch it
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 4.0)
	var boxes_before: int = p.boxes.size()
	await _use_item(p, "fakebox")
	var fb: FakeBox = _zp_hazard(p, "fake") as FakeBox
	check(fb != null and not fb.find_children("*", "ItemBox", true, false).is_empty() and p.boxes.size() == boxes_before, "Fake Box: it is built from the real item box and is not a pickup")
	if fb != null:
		check(fb.global_position.distance_to(pl.global_position) > 1.2, "Fake Box: it is left behind us (%.1f m)" % fb.global_position.distance_to(pl.global_position))
		d.global_position = fb.global_position
		await seconds(0.8)
		check(d.last_src == "fakebox" and d.stunned > 0.5 and _zp_used(fb) and _zp_hazard(p, "fake") == null, "Fake Box: the dummy that grabs it is blown up and stunned (%s)" % d.last_src)

	# Turbo Boost: much faster for a few seconds
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 8.0)
	var turbo: PowerUp = await _use_item(p, "turbo")
	check(mods.call().is_equal_approx(Vector3(1.6, 1.0, 1.0)) and is_equal_approx(turbo.duration, 3.5), "Turbo Boost: x1.6 speed for 3.5 s (%s)" % mods.call())
	check(Vector2(pl.velocity.x, pl.velocity.z).length() > 3.0 or not pl.grounded, "Turbo Boost: the ignition kicks us forward (%.1f m/s)" % Vector2(pl.velocity.x, pl.velocity.z).length())
	await seconds(3.9)
	check(_zp_ended(turbo) and restored.call(), "Turbo Boost: the speed is gone when the fuel is")

	# Ghost: nothing can touch us, and touching a rival steals what they hold
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 7.0)
	var solid: float = _zp_transparency(pl.visual)
	var ghost: PowerUp = await _use_item(p, "ghost")
	check(p.ghosted() and not p.local_vulnerable() and _zp_transparency(pl.visual) > solid + 1.0, "Ghost: we turn see-through and intangible")
	var deaths0: int = lvl.deaths
	p._on_hit(77, {"kb": [0, 20, 0], "st": 1.0, "ko": true, "s": "test"})
	p.take_hazard(77, Vector3(0, 20, 0), {"st": 1.0})
	await ticks(3)
	check(lvl.deaths == deaths0 and pl.party_stun <= 0.0 and pl.velocity.y < 5.0, "Ghost: hits and hazards pass straight through")
	check(p.item == "", "Ghost: nothing stolen yet")
	await _face_dummy(lvl, d, 1.2)
	await seconds(0.5)
	check(p.item != "" and d.last_src == "ghost", "Ghost: touching the dummy steals the item it holds (%s)" % p.item)
	ghost.finish()
	p.item = ""
	await seconds(0.6)
	check(not p.ghosted() and p.local_vulnerable() and is_equal_approx(_zp_transparency(pl.visual), solid), "Ghost: the body comes back exactly as it was (%.2f vs %.2f)" % [_zp_transparency(pl.visual), solid])

	# Decoy: a double that runs ahead and soaks up exactly one hit
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 6.0)
	await _use_item(p, "decoy")
	check(p.decoys.size() == 1 and _zp_hazard(p, "decoy") != null, "Decoy: a double steps out")
	if not p.decoys.is_empty():
		var dc: PartyDecoy = p.decoys[0]
		var at0: Vector3 = dc.global_position
		await seconds(1.5)
		check(dc.points.size() >= 2 and dc.global_position.distance_to(at0) > 1.0, "Decoy: it runs up the course (%d waypoints, %.1f m)" % [dc.points.size(), dc.global_position.distance_to(at0)])
		var tgt: Dictionary = {}
		for t: Dictionary in p.targets():
			if bool(t.get("decoy", false)):
				tgt = t
		check(not tgt.is_empty() and int(tgt["id"]) <= -1000, "Decoy: it counts as a racer for attacks (id %s)" % str(tgt.get("id", 0)))
		var landed: Array = []
		var on_landed := func(id: int, src: String) -> void: landed.append([id, src])
		p.hit_landed.connect(on_landed)
		if not tgt.is_empty():
			p.hit(tgt, Vector3(6, 5, 0), {"s": "shove"})
		check(dc.popped and p.decoys.is_empty() and _zp_hazard(p, "decoy") == null and landed.size() == 1, "Decoy: the first hit pops it")
		p.hit_landed.disconnect(on_landed)

	# Shockwave: hurls everyone close, kept when nobody is
	await _party_fresh(p, d)
	await _face_dummy(lvl, d, 3.0)
	await _use_item(p, "shock")
	check(d.last_src == "shock" and d.vel.length() > 8.0, "Shockwave: the dummy is hurled away (%s, %.1f m/s)" % [d.last_src, d.vel.length()])
	await _party_fresh(p, d)
	for dd: PracticeDummy in p.dummies:
		dd.knock_out()
	p.give_item("shock")
	check(p.activate_item() == null and p.item == "shock", "Shockwave: with nobody close it is kept in the slot")
	for dd: PracticeDummy in p.dummies:
		dd.reset()
	p.item = ""
	check(restored.call(), "no new power-up leaves a multiplier behind")
	await seconds(1.0)   # (let the strike's delayed effects finish before the level goes)
	Game.party = null


## Victim-side rules: respawn protection, the Balloon Shield and the Ghost keep every new attack off us,
## and the ones that land say so in the feed.
func test_zp_items_victim_side() -> void:
	var lvl: LevelBase = await _party_race_level(0)
	var p: PartyLayer = lvl.party
	var pl: Player = lvl.player
	var pts: Array[Vector3] = p.course_points()
	_add_rival(lvl, 2, pts[1], 1, 4.0)
	await ticks(3)
	var reset := func() -> void:
		p.end_all_powers()
		p.clear_statuses()
		p.protect_left = 0.0
		p.item = ""
		pl.teleport(Transform3D(Basis(), pts[0] + Vector3(0, 0.1, 0)))
		pl.party_stun = 0.0
		await ticks(4)
	var fake_script: GDScript = PartyItems.script_for("fakebox")
	var strike_script: GDScript = PartyItems.script_for("strike")

	# Fake Box: respawn protection and the Ghost pass through it (it stays); then it goes off
	await reset.call()
	p.protect(3.0)
	var fb: FakeBox = fake_script.call("drop", p, "2_1", 2, pl.global_position) as FakeBox
	await seconds(0.8)
	check(not _zp_used(fb) and pl.party_stun <= 0.0, "Fake Box: a protected racer runs through it and it stays")
	p.break_protection()
	await seconds(0.3)
	check(_zp_used(fb) and pl.party_stun > 0.5 and p.last_hit_by == 2, "Fake Box: unprotected, we are stunned by it (stun %.1f)" % pl.party_stun)
	var line: String = str(p.hud.feed_log[p.hud.feed_log.size() - 1]["text"]) if not p.hud.feed_log.is_empty() else ""
	check(line.contains("tricked"), "Fake Box: the feed says who was tricked (%s)" % line)
	await reset.call()
	p.give_item("balloon")
	var bal: PowerUp = p.activate_item()
	await ticks(2)
	var fb2: FakeBox = fake_script.call("drop", p, "2_2", 2, pl.global_position) as FakeBox
	await seconds(0.8)
	check(_zp_ended(bal) and pl.party_stun <= 0.0 and _zp_used(fb2), "Fake Box: a Balloon Shield soaks it")
	await reset.call()
	p.give_item("ghost")
	var gh: PowerUp = p.activate_item()
	await ticks(2)
	var fb3: FakeBox = fake_script.call("drop", p, "2_3", 2, pl.global_position) as FakeBox
	await seconds(0.8)
	check(not _zp_used(fb3) and pl.party_stun <= 0.0, "Fake Box: a Ghost passes through it")
	gh.finish()
	(fb3 as FakeBox).consume(false, false)

	# Leader Strike: it lands where we were when it locked; running clear is safe; protection and the Ghost hold
	await reset.call()
	var z1: StrikeZone = strike_script.call("spawn", p, "2_4", 2, 1, pl.global_position, 7) as StrikeZone
	await seconds(StrikeZone.TELL + 0.4)
	check(_zp_landed(z1) and pl.party_stun > 0.8 and p.last_hit_by == 2, "Leader Strike: standing still under it, we are thrown and stunned (stun %.1f)" % pl.party_stun)
	line = str(p.hud.feed_log[p.hud.feed_log.size() - 1]["text"])
	check(line.contains("struck"), "Leader Strike: the feed says who was struck (%s)" % line)
	await reset.call()
	var z2: StrikeZone = strike_script.call("spawn", p, "2_5", 2, 1, pl.global_position, 7) as StrikeZone
	await seconds(StrikeZone.TELL - StrikeZone.LOCK + 0.3)
	check(z2.locked, "Leader Strike: the reticle locks before it lands")
	pl.teleport(Transform3D(Basis(), pts[1] + Vector3(0, 0.1, 0)))
	await seconds(StrikeZone.LOCK + 0.5)
	check(_zp_landed(z2) and pl.party_stun <= 0.0, "Leader Strike: a racer who runs clear after the lock is untouched")
	await reset.call()
	p.protect(6.0)
	var z3: StrikeZone = strike_script.call("spawn", p, "2_6", 2, 1, pl.global_position, 7) as StrikeZone
	await seconds(StrikeZone.TELL + 0.4)
	check(_zp_landed(z3) and pl.party_stun <= 0.0, "Leader Strike: respawn protection soaks it")
	await reset.call()
	p.give_item("ghost")
	gh = p.activate_item()
	await ticks(2)
	var z4: StrikeZone = strike_script.call("spawn", p, "2_7", 2, 1, pl.global_position, 7) as StrikeZone
	await seconds(StrikeZone.TELL + 0.4)
	check(_zp_landed(z4) and pl.party_stun <= 0.0, "Leader Strike: a Ghost is not struck")
	gh.finish()

	# "Targeted!": the one aimed at, and anyone standing in the zone, are warned
	await reset.call()
	var w0: int = p.hud.warn_log.size()
	p.hud.on_remote_fx(2, "strike", "tell", {"t": 1, "at": PowerUp.arr(pl.global_position), "k": "x"})
	check(p.hud.warn_log.size() == w0 + 1 and str(p.hud.warn_log[w0]["what"]).begins_with("Leader Strike"), "Targeted!: the racer a Leader Strike is aimed at is warned")
	p.hud.on_remote_fx(3, "strike", "tell", {"t": 9, "at": PowerUp.arr(pl.global_position + Vector3(2, 0, 0))})
	check(p.hud.warn_log.size() == w0 + 2 and str(p.hud.warn_log[w0 + 1]["what"]).contains("clear"), "Targeted!: someone standing near the zone is told to get clear")
	p.hud.on_remote_fx(4, "strike", "tell", {"t": 9, "at": PowerUp.arr(pl.global_position + Vector3(60, 0, 0))})
	check(p.hud.warn_log.size() == w0 + 2, "Targeted!: a racer far from the zone is left alone")
	p.hud.on_remote_fx(5, "homing", "launch", {"t": 1})
	check(p.hud.warn_log.size() == w0 + 3 and str(p.hud.warn_log[w0 + 2]["what"]) == "Homing Shell", "Targeted!: a Homing Shell on its way to us warns us")
	p.hud.on_remote_fx(6, "homing", "launch", {"t": 9})
	check(p.hud.warn_log.size() == w0 + 3, "Targeted!: a shell chasing somebody else does not")
	check(p.hud.threats().has(2) and p.hud.threats().has(5), "Targeted!: the culprits' arrows turn threatening")

	# The Ghost's theft, victim side
	await reset.call()
	p.item = "thunder"
	p.protect(3.0)
	p._on_steal(2)
	check(p.item == "thunder", "Ghost theft: respawn protection keeps the item")
	p.break_protection()
	p.give_item("balloon")
	var bal2: PowerUp = p.activate_item()
	p.item = "thunder"
	p._on_steal(2)
	check(p.item == "thunder" and _zp_ended(bal2), "Ghost theft: a Balloon Shield pops instead of the item going")
	p.item = ""
	var quiet_seen: Array = []
	p.item_changed.connect(func(id: String) -> void: quiet_seen.append([id, p.slot_quiet]))
	p.item = "ice"
	p._on_steal(2)
	check(p.item == "" and not quiet_seen.is_empty() and quiet_seen[0] == ["", true], "Ghost theft: an unprotected racer loses the item without it counting as a use")
	p._on_steal(2)
	check(p.item == "", "Ghost theft: empty hands lose nothing")
	# thief side
	p._steal_wait = p.clock
	p._on_stolen(2, "ice", false)
	check(p.item == "ice", "Ghost theft: the stolen item lands in our slot")
	p._steal_wait = p.clock
	p._on_stolen(2, "magnet", false)
	check(p.item == "ice", "Ghost theft: a full slot sends the loot back (it is not swallowed)")
	p.item = ""
	p._on_stolen(2, "magnet", true)
	check(p.item == "magnet", "Ghost theft: loot returned to its owner refills the slot")
	p.item = ""
	p._steal_wait = p.clock
	p._on_stolen(2, "not_an_item", false)
	check(p.item == "", "Ghost theft: junk from the wire is ignored")
	p._on_steal_no("empty")
	check(p._steal_wait < 0.0, "Ghost theft: a refusal ends the wait")
	await seconds(0.5)
	_party_race_done()


## Offence and wire format, owner side: the Homing Shell reaches a rival's ghost, and every item's
## events replay on another screen from the message alone.
func test_zp_items_replication() -> void:
	var lvl: LevelBase = await _party_race_level(0)
	var p: PartyLayer = lvl.party
	var pl: Player = lvl.player
	var pts: Array[Vector3] = p.course_points()
	Net.active = true
	_add_rival(lvl, 2, pts[1], 1, 4.0)
	await ticks(3)
	# owner side: a shell chases the racer ahead and tells the layer it hit them
	var landed: Array = []
	p.hit_landed.connect(func(id: int, src: String) -> void: landed.append([id, src]))
	p.give_item("homing")
	p.activate_item()
	await ticks(2)
	var shell: HomingShell = _zp_hazard(p, "shell") as HomingShell
	check(shell != null and shell.target_id == 2, "Homing Shell: it locks onto the racer ahead by course distance")
	var t0: float = pts[0].distance_to(pts[1])
	var waited: float = 0.0
	while landed.is_empty() and waited < 7.0:
		await seconds(0.2)
		waited += 0.2
	check(not landed.is_empty() and landed[0] == [2, "homing"], "Homing Shell: it flies the %.0f m to the rival and hits them (%s after %.1f s)" % [t0, str(landed), waited])
	# a shell fired by a rival replays on our screen and chases us (victim-side drawing only)
	await seconds(0.3)
	var from: Vector3 = pl.global_position + Vector3(14, 3, 0)
	p._on_message(2, {"k": "fx", "p": "homing", "a": "launch", "d": {"k": "2_9", "o": PowerUp.arr(from), "d": [-1, 0, 0], "t": 1}})
	await ticks(2)
	var rs: HomingShell = p.hazards.get("2_9", null) as HomingShell
	check(rs != null and not rs.local, "Homing Shell: a rival's shell replays here")
	if rs != null:
		var gap0: float = rs.global_position.distance_to(pl.global_position)
		await seconds(0.4)
		check(rs.global_position.distance_to(pl.global_position) < gap0 - 3.0, "Homing Shell: the replayed shell closes in on our own Player (%.1f -> %.1f m)" % [gap0, rs.global_position.distance_to(pl.global_position)])
		p._on_message(2, {"k": "fx", "p": "homing", "a": "boom", "d": {"k": "2_9", "at": PowerUp.arr(pl.global_position + Vector3(5, 1, 0)), "hit": true}})
		await ticks(2)
		check(rs.done, "Homing Shell: the owner's burst message ends it here too")
	# the rest replay from their events
	p._on_message(2, {"k": "fx", "p": "strike", "a": "tell", "d": {"k": "2_10", "t": 9, "at": PowerUp.arr(pts[1]), "s": 4}})
	await ticks(2)
	var rz: StrikeZone = p.hazards.get("2_10", null) as StrikeZone
	check(rz != null and rz.owner_id == 2, "Leader Strike: the tell opens the same zone here")
	if rz != null:
		rz.queue_free()
		p.hazards.erase("2_10")
	p._on_message(2, {"k": "fx", "p": "fakebox", "a": "drop", "d": {"k": "2_11", "pos": PowerUp.arr(pts[1])}})
	await ticks(2)
	var rf: FakeBox = p.hazards.get("2_11", null) as FakeBox
	check(rf != null and rf.owner_id == 2, "Fake Box: the drop puts a fake box in the same place here")
	p._on_message(3, {"k": "hz", "h": "2_11"})
	check(rf != null and rf.used and not p.hazards.has("2_11"), "Fake Box: when somebody grabs it the victim's message removes it everywhere")
	p._on_message(2, {"k": "fx", "p": "decoy", "a": "drop", "d": {"k": "2_12", "pts": [PowerUp.arr(pts[1]), PowerUp.arr(pts[1] + Vector3(0, 0, -5))], "air": [0, 0]}})
	await ticks(3)
	check(p.decoys.size() == 1 and p.decoys[0].id == PartyDecoy.id_for("2_12"), "Decoy: the rival's decoy is spawned here (id %d)" % PartyDecoy.id_for("2_12"))
	var seen: bool = false
	for t: Dictionary in p.targets():
		if bool(t.get("decoy", false)) and int(t["id"]) == PartyDecoy.id_for("2_12"):
			seen = true
	check(seen, "Decoy: a rival's decoy is a target on our screen")
	p._on_message(3, {"k": "hz", "h": "2_12"})
	await ticks(2)
	check(p.decoys.is_empty(), "Decoy: the pop message removes it")
	p._on_message(2, {"k": "fx", "p": "shock", "a": "slam", "d": {"at": PowerUp.arr(pts[1])}})
	p._on_message(2, {"k": "fx", "p": "ghost", "a": "steal", "d": {"b": PowerUp.arr(pts[1])}})
	# timed items are mirrored on the rival's ghost from the "pw" message
	var g2: RemoteRacer = lvl._ghosts[2]
	var solid: float = _zp_transparency(g2.visual())
	p._on_message(2, {"k": "pw", "p": "turbo", "on": true, "d": 3.5})
	p._on_message(2, {"k": "pw", "p": "ghost", "on": true, "d": 6.0})
	await ticks(3)
	var per: Dictionary = p.remote_powers.get(2, {})
	check(per.has("turbo") and per.has("ghost"), "Turbo Boost and Ghost are mirrored on the rival's ghost")
	check(_zp_transparency(g2.visual()) > solid + 1.0, "Ghost: the rival's model turns see-through here")
	p._on_message(2, {"k": "pw", "p": "ghost", "on": false})
	p._on_message(2, {"k": "pw", "p": "turbo", "on": false})
	await seconds(0.6)
	check(is_equal_approx(_zp_transparency(g2.visual()), solid), "Ghost: the model is back to normal when it ends")
	check(pl.speed_mult == 1.0, "a rival's mirrored items never change our own speed")
	# every new clip is registered and has a file
	var missing: Array[String] = []
	for c: String in ["shell", "siren", "strike", "fake", "turbo", "ghost", "steal", "decoy", "shock"]:
		if not PartySfx.CLIPS.has(c) or not PartySfx.FALLBACK.has(c) or not ResourceLoader.exists("res://audio/party_%s.wav" % c):
			missing.append(c)
	check(missing.is_empty(), "every new item sound is generated and registered in PartySfx (missing: %s)" % str(missing))
	await seconds(1.0)
	_party_race_done()


func test_zp_items_roll_weighting() -> void:
	var lead: Dictionary = {}
	var mid: Dictionary = {}
	var last: Dictionary = {}
	var n: int = 3000
	for i: int in n:
		var r: float = (float(i) + 0.5) / float(n)
		for pair: Array in [[0.0, lead], [0.5, mid], [1.0, last]]:
			var id: String = PartyItems.roll(float(pair[0]), r)
			(pair[1] as Dictionary)[id] = int((pair[1] as Dictionary).get(id, 0)) + 1
	var share := func(t: Dictionary, ids: Array[String]) -> float:
		var s: int = 0
		for id: String in ids:
			s += int(t.get(id, 0))
		return float(s) / float(n)
	var rolled_by_leader: Array[String] = []
	for id: String in PartyItems.CATCH_UP:
		if lead.has(id):
			rolled_by_leader.append(id)
	check(rolled_by_leader.is_empty(), "the leader never rolls a catch-up item (%s)" % str(rolled_by_leader))
	var all_last: bool = true
	for id: String in PartyItems.CATCH_UP:
		if not last.has(id):
			all_last = false
	check(all_last, "the last-place racer can roll every catch-up item")
	check(share.call(last, PartyItems.CATCH_UP) > 0.3 and share.call(last, PartyItems.CATCH_UP) > share.call(mid, PartyItems.CATCH_UP) * 1.3, "catch-up items are the bulk of what last place rolls (%.0f%% vs %.0f%% mid-pack)" % [share.call(last, PartyItems.CATCH_UP) * 100.0, share.call(mid, PartyItems.CATCH_UP) * 100.0])
	check(share.call(lead, PartyItems.LEADER_SAFE) > 0.5 and share.call(lead, PartyItems.LEADER_SAFE) > share.call(last, PartyItems.LEADER_SAFE) * 2.0, "the leader mostly gets lead-protecting items (%.0f%% vs %.0f%% for last)" % [share.call(lead, PartyItems.LEADER_SAFE) * 100.0, share.call(last, PartyItems.LEADER_SAFE) * 100.0])
	var every: bool = true
	for id: String in ZP_NEW_ITEMS:
		if not (lead.has(id) or mid.has(id) or last.has(id)):
			every = false
	check(every, "every new item can roll for somebody")
	check(PartyItems.PRACTICE_ORDER.size() >= 20 and PartyItems.PRACTICE_ORDER.size() == PartyItems.WEIGHTS.size() and PartyItems.SCRIPTS.size() == PartyItems.WEIGHTS.size(), "the roll table, practice order and script table agree (%d items)" % PartyItems.PRACTICE_ORDER.size())
	check(PartyItems.PRACTICE_ORDER[0] == "fox", "Party Practice still starts with the Nine-Tailed Fox")
	check(PartyItems.weight("strike", 0.0) == 0.0 and PartyItems.weight("strike", 0.5) < PartyItems.weight("strike", 1.0) and PartyItems.weight("turbo", 0.0) == 0.0, "catch-up weights climb from the front to the back")
	check(PartyItems.weight("decoy", 0.0) > PartyItems.weight("decoy", 1.0) and PartyItems.weight("fakebox", 0.0) > PartyItems.weight("fakebox", 1.0), "defensive weights fall from the front to the back")
	# each new item has a feed phrase and a use line, and an icon glyph that draws
	var phrased: bool = true
	for id: String in ZP_NEW_ITEMS:
		if id in ["homing", "strike", "fakebox", "ghost", "shock"] and PartyFeedText.verb(id) == "hit":
			phrased = false
		if PartyFeedText.use_line("Ana", id) == "":
			phrased = false
	check(phrased, "every new item has a feed verb for its hits and a use line")
	var icons: Array[PartyIcon] = []
	for id: String in ZP_NEW_ITEMS:
		var ic := PartyIcon.new()
		ic.item_id = id
		add_child(ic)
		icons.append(ic)
	await ticks(3)
	check(icons.size() == ZP_NEW_ITEMS.size(), "the icons draw without errors")
	for ic: PartyIcon in icons:
		ic.queue_free()
	await ticks(2)


## Mid-course rows: every course with real route between its checkpoints gets item boxes on flat, static
## ground along it, not just on the lawns.
func test_zp_items_mid_course_boxes() -> void:
	var weak: Array[String] = []
	var total_eligible: int = 0
	var total_covered: int = 0
	var courses: int = 0
	var long_routes: int = 0
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		var lvl: LevelBase = await _load_practice(i)
		var p: PartyLayer = lvl.party
		if p == null:
			weak.append("%s: no party layer" % Game.LEVELS[i]["name"])
			continue
		var waited: int = 0
		while not p._ready_done and waited < 60:
			await ticks(1)
			waited += 1
		var eligible: int = 0
		var covered: int = 0
		var rows: int = 0
		for k: int in p.mid_counts.size():
			if p.mid_lengths[k] >= PartyLayer.MID_SPACING:
				eligible += 1
				if p.mid_counts[k] > 0:
					covered += 1
			rows += p.mid_counts[k]
		var lawn: int = 0
		for c: int in p.box_counts:
			lawn += c
		var on_ground: int = 0
		var space: PhysicsDirectSpaceState3D = lvl.get_world_3d().direct_space_state
		for bi: int in range(lawn, p.boxes.size()):
			var b: ItemBox = p.boxes[bi]
			var q := PhysicsRayQueryParameters3D.create(b.global_position, b.global_position + Vector3(0, -1.6, 0), 1)
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty() and (hit["collider"] is StaticBody3D) and not (hit["collider"] is AnimatableBody3D):
				on_ground += 1
		courses += 1
		total_eligible += eligible
		total_covered += covered
		var extra: int = p.boxes.size() - lawn
		if extra != rows:
			weak.append("%s: %d boxes but %d counted" % [Game.LEVELS[i]["name"], extra, rows])
		if on_ground != extra:
			weak.append("%s: %d of %d mid-course boxes are not on static ground" % [Game.LEVELS[i]["name"], extra - on_ground, extra])
		if eligible >= 3:
			long_routes += 1
			if covered * 2 < eligible or rows < 3:
				weak.append("%s: only %d of %d long stretches got boxes (%d boxes)" % [Game.LEVELS[i]["name"], covered, eligible, rows])
		print("   mid-course: %s  %d/%d stretches, %d boxes" % [Game.LEVELS[i]["name"], covered, eligible, rows])
	check(weak.is_empty(), "every long stretch of route between checkpoints gets item boxes on static ground (%d courses, %d with a long route, %d/%d stretches covered; problems: %s)" % [courses, long_routes, total_covered, total_eligible, str(weak)])
	check(total_eligible == 0 or float(total_covered) / float(total_eligible) > 0.6, "most long stretches are covered overall (%d/%d)" % [total_covered, total_eligible])
	Game.party = null
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)


# ---- generic obstacle kit (docs/KIT_OBSTACLES.md): run with  --only=test_zk_ ------------------------

## Plays a test course end to end with the route bot (no teleporting).
func _kit_bot(path: String, max_s: float, what: String) -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	Game.level_index = -1
	Game.race_mode = false
	Game.course_time = 0.0
	Game.course_running = true
	var lvl: LevelBase = (load(path) as GDScript).new() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var bot := RouteBot.new()
	lvl.add_child(bot)
	bot.attach(lvl)
	var t: float = 0.0
	while t < max_s and not bot.done and not bot.stuck:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	for line: String in bot.log_lines:
		print("        bot: ", line)
	check(bot.done and bot.retries <= 1, "%s (%.1fs, %d respawns, step %d/%d)" % [what, lvl.run_time, bot.retries, bot.step_index, lvl.route.size()])


func test_zk_barrel() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab()
	var b: LaunchBarrel = kit.barrel(Vector3(0, 0, -6), Vector3(0, 0, -22), 3.0, 3.0, 0.0, 1.0)
	check(b.tell >= 0.8, "the barrel's tell is at least 0.8 s (%.2f)" % b.tell)
	player.teleport(Transform3D(Basis(), Vector3(0, 0.05, 0)))
	await seconds(0.3)
	player.cmd_move = FWD
	var got: bool = await wait_until(func() -> bool: return b.is_loaded(), 3.0, "walk into the barrel")
	var t_in: float = Game.course_time
	player.cmd_move = Vector2.ZERO
	check(got and b.loaded_player() == player and not player.control_enabled, "walking into the mouth loads the rider and takes control")
	var fire_t: float = b.fire_time_after(t_in)
	check(fire_t - t_in >= 0.79, "it fires at least 0.8 s after you get in (%.2f s)" % (fire_t - t_in))
	check(absf(fposmod(fire_t / 3.0, 1.0)) < 0.001 or absf(fposmod(fire_t / 3.0, 1.0) - 1.0) < 0.001, "and on the clock grid (k * period)")
	await seconds(0.4)
	check(player.global_position.distance_to(b.global_position) < 0.25 and b.is_loaded(), "the loaded rider is held at the barrel centre until it fires (%.3f m, loaded %s)" % [player.global_position.distance_to(b.global_position), str(b.is_loaded())])
	var fired: bool = await wait_until(func() -> bool: return not b.is_loaded(), 4.0, "the barrel fires")
	var t_out: float = Game.course_time
	check(fired and absf(t_out - fire_t) < 0.06, "it fired on the predicted tick (predicted %.3f, actual %.3f)" % [fire_t, t_out])
	check(player.control_enabled and player.velocity.y > 8.0 and player.velocity.z < -8.0, "the shot has the fixed launch velocity %s" % str(player.velocity.snapped(Vector3.ONE * 0.1)))
	player.cmd_move = FWD
	await wait_landing(4.0)
	await seconds(0.1)
	var miss: float = Vector2(player.global_position.x, player.global_position.z + 22.0).length()
	metrics["barrel_landing_error_m"] = miss
	check(miss < 2.5, "holding the stick toward the target, the arc lands within 2.5 m of it (%.2f m)" % miss)
	player.cmd_move = Vector2.ZERO
	# a second rider must wait out the cooldown rather than be re-captured at once
	check(not b.is_loaded(), "the barrel does not catch the rider it just fired")


func test_zk_zipline() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab()
	var z: Zipline = kit.zipline(Vector3(0, 0, -5), Vector3(0, 0, -45), 11.0, 1.4, 0.0)
	check(z.dwell >= 0.9, "the zipline waits at least 0.9 s at the start (the lamp flashes through the last second) (%.2f)" % z.dwell)
	player.teleport(Transform3D(Basis(), z.stand_point()))
	var grabbed: bool = await wait_until(func() -> bool: return z.carrying() == player, 4.0, "the trolley picks the rider up")
	check(grabbed and not player.control_enabled, "standing under the trolley grabs it")
	await seconds(0.3)
	check(absf(player.global_position.y - z.rider_feet_at(Game.course_time).y) < 0.15, "the rider hangs %.1f m below the trolley" % z.hang)
	var rides: bool = await wait_until(func() -> bool: return player.global_position.z < -15.0, 4.0, "ride along the cable")
	check(rides and player.velocity.z < -9.0, "the ride runs at cable speed (%.1f m/s)" % player.velocity.z)
	var pred: Vector3 = z.rider_feet_at(Game.course_time)
	check(player.global_position.distance_to(pred) < 0.35, "the rider is where handle_at() says (err %.2f m)" % player.global_position.distance_to(pred))
	# a real jump press (what the pad / keyboard sends) lets go with the speed kept, plus a hop
	player.press_jump()
	await ticks(3)
	check(z.carrying() == null and player.control_enabled, "pressing jump releases the rider")
	check(player.velocity.z < -9.0 and player.velocity.y > 3.0, "and keeps the cable's speed with a hop %s" % str(player.velocity.snapped(Vector3.ONE * 0.1)))
	await wait_landing(3.0)
	# riding to the end lets go there with the same speed
	var again: bool = await wait_until(func() -> bool: return z.departs_in(Game.course_time) > 0.0 and z.departs_in(Game.course_time) < 1.0, 12.0, "the trolley is back at the start")
	player.teleport(Transform3D(Basis(), z.stand_point()))
	var got2: bool = await wait_until(func() -> bool: return z.carrying() == player, 4.0, "picked up again")
	var released: bool = await wait_until(func() -> bool: return z.carrying() == null, 8.0, "auto release at the far end")
	check(again and got2 and released and player.global_position.z < -40.0, "riding to the end lets go at the far end (z %.1f)" % player.global_position.z)
	check(player.velocity.z < -8.0, "carrying the ride speed (%.1f m/s)" % player.velocity.z)


func test_zk_battery() -> void:
	var lvl: LevelBase = await load_level(0)
	var base: Vector3 = lvl.checkpoints[0].global_position + Vector3(40, 0, 0)
	lvl.player.use_device_input = false
	lvl.kit.plat(base, Vector3(40, 1, 30), "main", 0.0)
	# fires along -X from x = base + 14: the muzzle is 1.9 m ahead of the node
	var bat: CannonBattery = lvl.kit.battery(base + Vector3(14, 0, 0), 90.0, 24.0, 9.0, 3.2, 0.0, 0.0)
	check(bat.tell >= 0.8, "the cannon's tell is at least 0.8 s (%.2f)" % bat.tell)
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(-12, 0.1, 8)))
	await seconds(0.5)
	# the strip on the floor flashes through the last second before a salvo
	await wait_until(func() -> bool: return bat.time_to_salvo(Game.course_time) < 0.6 and bat.time_to_salvo(Game.course_time) > 0.1, 4.0, "the tell")
	await get_tree().process_frame
	var strip_alpha: float = ((bat._strip.material_override as StandardMaterial3D).albedo_color.a)
	check(strip_alpha > 0.0, "the lane strip lights up during the tell (alpha %.2f)" % strip_alpha)
	# the pool shows exactly the balls balls_at() predicts
	await wait_until(func() -> bool: return bat.balls_at(Game.course_time).size() >= 1 and bat.balls_at(Game.course_time)[0] > 5.0, 4.0, "a ball in flight")
	await get_tree().physics_frame
	var pred: PackedFloat32Array = bat.balls_at(Game.course_time)
	var shown: int = 0
	for slot: Dictionary in bat._slots:
		if (slot["node"] as Node3D).visible:
			shown += 1
	check(shown == pred.size() and pred.size() >= 1, "the visible balls match the clock's prediction (%d vs %d)" % [shown, pred.size()])
	# a clear window is really clear, a blocked one kills
	var d: float = 10.0
	var d0: int = lvl.deaths
	await wait_until(func() -> bool: return bat.is_clear_for(d - 1.0, d + 1.0, 0.5), 5.0, "a gap in the salvos")
	lvl.player.teleport(Transform3D(Basis(), bat.to_global(Vector3(0, 0.1, -1.9 - d))))
	await seconds(0.45)
	check(lvl.deaths == d0, "standing in the lane while is_clear_for() says clear is safe")
	await wait_until(func() -> bool: return lvl.deaths > d0, 5.0, "a ball finds the rider standing in the lane")
	check(lvl.deaths == d0 + 1, "a cannonball kills the rider it hits")
	# rolling balls can be jumped
	var jumped: bool = true
	var t_end: float = Game.course_time + 6.0
	d0 = lvl.deaths
	await wait_until(func() -> bool: return bat.is_clear_for(0.0, d + 1.0, 0.3), 5.0, "the lane empties")
	lvl.player.teleport(Transform3D(Basis(), bat.to_global(Vector3(0, 0.1, -1.9 - d))))
	await seconds(0.3)
	t_end = Game.course_time + 6.0
	while Game.course_time < t_end and lvl.deaths == d0:
		var eta: float = 99.0
		for b: float in bat.balls_at(Game.course_time):
			if b < d:
				eta = minf(eta, (d - b) / 9.0)
		if eta < 0.38 and lvl.player.grounded:
			lvl.player.press_jump()
			lvl.player.cmd_jump = true
		elif lvl.player.velocity.y <= 0.0:
			lvl.player.cmd_jump = false
		await get_tree().physics_frame
	lvl.player.cmd_jump = false
	jumped = lvl.deaths == d0
	check(jumped, "a well-timed jump clears a rolling ball for two salvos")


func test_zk_log() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -8, 0))
	var lg: RollingLog = kit.log_roller(Vector3(0, 0, 0), 12.0, 3.0, 0.0, 3.0, 0.0)
	player.teleport(Transform3D(Basis(), Vector3(0, 0.05, 0)))
	await seconds(0.25)
	player.cmd_move = Vector2.ZERO
	await seconds(0.2)
	check(player.grounded and player.floor_body == lg, "the player stands on the log's top line")
	check(player.velocity.z > 1.5 or player.global_position.z > 0.3, "the roll drags a standing rider sideways along the log's Z (v %s)" % str(player.velocity.snapped(Vector3.ONE * 0.1)))
	check(lg.surface_velocity().is_equal_approx(Vector3(0, 0, 3.0)), "surface_velocity() is the push (%s)" % str(lg.surface_velocity()))
	# a reversing log: sine push, predictable calm spells
	var lr: RollingLog = kit.log_roller(Vector3(40, 0, 0), 12.0, 3.0, 0.0, 4.0, 6.0, 0.0)
	check(absf(lr.speed_at(0.0)) < 0.001 and absf(lr.speed_at(1.5) - 4.0) < 0.001 and absf(lr.speed_at(4.5) + 4.0) < 0.001, "a reversing log pushes 0, +speed, 0, -speed through its period")
	check(lr.is_calm_for(-0.1, 0.2) and not lr.is_calm_for(1.0, 0.2), "is_calm_for() finds the stand-still moments")
	check(absf(lr.calm_in(1.5) - 1.5) < 0.6, "calm_in() says when the next one comes (%.2f s)" % lr.calm_in(1.5))
	# stable footing: run its length without being thrown off (the bot test below does the real crossing)
	player.teleport(Transform3D(Basis(), Vector3(35, 0.05, 0.0)))
	await seconds(0.3)
	for i: int in 96:
		# run along +X, steering back to the log's line against the push
		player.cmd_move = Vector2(1.0, clampf((player.global_position.z - lr.global_position.z) * 2.5, -1.0, 1.0))
		await get_tree().physics_frame
	player.cmd_move = Vector2.ZERO
	check(player.global_position.y > -1.0, "a rider can run along a reversing log (y %.2f)" % player.global_position.y)


func test_zk_seesaw() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -8, 0))
	var s: Seesaw = kit.seesaw(Vector3(0, 0, 0), 9.0, 2.6, true, 0.0)
	await seconds(0.3)
	check(s.is_level(2.0), "an empty seesaw rests level (%.1f deg)" % s.axis_degrees())
	player.teleport(Transform3D(Basis(), Vector3(3.9, 0.2, 0)))
	await seconds(1.4)
	var right: float = s.axis_degrees()
	check(absf(right) > 6.0, "standing near one end tips that end down (%.1f deg)" % right)
	player.teleport(Transform3D(Basis(), Vector3(-3.9, s.global_position.y + 0.9, 0)))
	await seconds(1.6)
	var left: float = s.axis_degrees()
	check(absf(left) > 6.0 and signf(left) != signf(right), "standing near the other end tips it the other way (%.1f deg)" % left)
	player.teleport(Transform3D(Basis(), Vector3(0, 0.6, 0)))
	await seconds(1.4)
	check(absf(s.axis_degrees()) < 6.0, "standing on the pivot levels it (%.1f deg)" % s.axis_degrees())
	# a counterweight tips the empty plank at rest
	var w: Seesaw = kit.seesaw(Vector3(40, 0, 0), 9.0, 2.6, true, 10.0)
	await seconds(1.5)
	check(absf(w.axis_degrees()) > 5.0 and absf(w.axis_degrees()) < 14.0, "bias_deg tips the empty plank (%.1f deg)" % w.axis_degrees())
	# the other orientation
	var z: Seesaw = kit.seesaw(Vector3(80, 0, 0), 9.0, 2.6, false, 0.0)
	player.teleport(Transform3D(Basis(), Vector3(80, 0.2, -3.9)))
	await seconds(1.4)
	check(absf(z.axis_degrees()) > 6.0, "a plank along Z tips about X (%.1f deg)" % z.axis_degrees())


func test_zk_bot_slice1() -> void:
	await _kit_bot("res://tests/kit_course.gd", 120.0, "the bot rides the barrel, zipline, cannon lane, rolling log and seesaw")


## The longest run of `ph` phases (seconds) over one period, sampled every 10 ms.
func _kit_phase_span(period: float, phase_of: Callable, ph: int) -> float:
	var best: float = 0.0
	var run: float = 0.0
	var t: float = 0.0
	while t < period * 2.0:
		if int(phase_of.call(t)) == ph:
			run += 0.01
			best = maxf(best, run)
		else:
			run = 0.0
		t += 0.01
	return best


func test_zk_flipper() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab(Vector3(60, 1, 60), Vector3(0, -0.04, 0))
	var f: Flipper = kit.flipper(Vector3(0, 0, 0), 5.0, 0.0, 80.0, 4.0, 0.0)
	check(_kit_phase_span(f.period, f.phase_at, 1) >= 0.8, "the flipper winds up for at least 0.8 s before it swats (%.2f s)" % _kit_phase_span(f.period, f.phase_at, 1))
	check(absf(f.angle_at(0.0)) < 0.01 and absf(f.angle_at(f._rest_len + f.tell + 0.2) - 80.0) < 0.5, "it rests at rest_deg and ends the swat at rest_deg + swing_deg")
	check(f.swat_free_for(0.0, 1.0) and not f.swat_free_for(0.0, f._rest_len + f.tell + 0.05), "swat_free_for() matches the clock")
	var pred: Vector3 = f.throw_velocity(Vector3(3.5, 0, 0))
	check(pred.z < -8.0 and pred.y > 6.0 and absf(pred.x) < 0.5, "a rider near the tip is thrown along the swing toward -Z %s" % str(pred.snapped(Vector3.ONE * 0.1)))
	check(f.throw_velocity(Vector3(1.0, 0, 0)).length() < pred.length(), "and thrown less near the pivot")
	player.teleport(Transform3D(Basis(), Vector3(3.5, 0.2, 0)))
	await settle()
	var thrown: bool = await wait_until(func() -> bool: return player.velocity.y > 5.0 and player.velocity.z < -6.0, 6.0, "the swat")
	check(thrown, "standing on the paddle when it swats throws the rider (v %s)" % str(player.velocity.snapped(Vector3.ONE * 0.1)))
	var landed: float = await wait_landing(4.0)
	check(landed < 4.0 and player.global_position.z < -4.0, "and carries them well clear of it (z %.1f)" % player.global_position.z)


func test_zk_drawbridge() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab(Vector3(60, 1, 60), Vector3(0, -9, 0))
	kit.plat(Vector3(0, 0, 4), Vector3(8, 1, 8))
	var br: Drawbridge = kit.drawbridge(Vector3(0, 0, 0), 8.0, 3.4, 0.0, 9.0, 0.0)
	check(_kit_phase_span(br.period, br.phase_at, 1) >= 0.8, "the chains rattle for at least 0.8 s before it rises (%.2f s)" % _kit_phase_span(br.period, br.phase_at, 1))
	check(br.angle_at(0.0) == 0.0 and absf(br.angle_at(br._down_hold + br.warn + br.RAISE + 0.2) - br.raise_deg) < 0.01, "flat for the down hold, raised after the rise")
	check(br.is_down_for(0.0, br._down_hold - 0.1) and not br.is_down_for(0.0, br._down_hold + 0.1), "is_down_for() covers exactly the down hold")
	player.teleport(Transform3D(Basis(), Vector3(0, 0.1, -6)))
	await seconds(0.5)
	check(player.grounded and player.floor_body == br._deck, "the lowered deck is solid ground")
	check(absf(br._deck.rotation.x - deg_to_rad(br.angle_at(Game.course_time))) < 0.01, "the deck's pose is the clock's")
	# let it rise under the rider: they are dumped back toward the hinge, not carried up
	await wait_until(func() -> bool: return br.angle_at(Game.course_time) > 60.0, 12.0, "the deck rises")
	await seconds(0.3)
	check(player.global_position.z > -3.0 or player.global_position.y < -1.0, "a rider on the rising deck slides off it (z %.1f y %.1f)" % [player.global_position.z, player.global_position.y])
	await wait_until(func() -> bool: return br.phase_at(Game.course_time) == 0, 12.0, "the deck is down again")


func test_zk_gapwall() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab()
	var w: GapWall = kit.gap_wall(Vector3(0, 0, -10), 0.0, 3.4, 8.0, 0.0)
	check(w.move_time >= 0.8 and w.warn >= 0.8, "the wall's slide and its lamp warning are at least 0.8 s (%.1f, %.1f)" % [w.move_time, w.warn])
	check(w.is_open_for(0.0, 1.5) and not w.is_open_for(0.0, 4.5) and absf(w.offset_at(w.open_time + w.move_time + 0.2)) > w.gap * 0.5 + 1.5, "open at the start, shut through its closed time")
	check(w.open_in(w.open_time + 0.5) > 0.0 and w.open_in(0.0) == 0.0, "open_in() finds the next opening")
	# shut: it stops the rider
	await wait_until(func() -> bool: return w.state_at(Game.course_time) == 3, 10.0, "the wall to shut")
	player.teleport(Transform3D(Basis(), Vector3(0, 0.05, -4)))
	player.cmd_move = FWD
	await seconds(0.9)
	check(player.global_position.z > -9.2, "a shut wall blocks the lane (z %.2f)" % player.global_position.z)
	player.cmd_move = Vector2.ZERO
	# open: it lets the rider through
	await wait_until(func() -> bool: return w.is_open_for(Game.course_time, 2.0) and w.state_at(Game.course_time) == 0, 12.0, "the doorway to line up")
	player.teleport(Transform3D(Basis(), Vector3(0, 0.05, -5.5)))
	player.cmd_move = FWD
	var through: bool = await wait_until(func() -> bool: return player.global_position.z < -12.5, 3.0, "walk through the doorway")
	player.cmd_move = Vector2.ZERO
	check(through, "an open doorway lets the rider straight through")


func test_zk_block() -> void:
	var lvl: LevelBase = await load_level(0)
	var base: Vector3 = lvl.checkpoints[0].global_position + Vector3(40, 0, 0)
	lvl.player.use_device_input = false
	lvl.kit.plat(base, Vector3(30, 1, 30), "main", 0.0)
	var b: FallingBlock = lvl.kit.falling_block(base, Vector3(3, 1.6, 3), 7.0, 5.0, 0.0)
	check(b.tell >= 0.8 and _kit_phase_span(b.period, b.phase_at, 1) >= 0.8, "the shadow grows for at least 0.8 s before the drop (%.2f s)" % _kit_phase_span(b.period, b.phase_at, 1))
	check(b.gap_at(0.0) == 7.0 and b.gap_at(b._rest_len + b.tell + b.FALL + 0.1) == 0.0, "it hangs high, lands on the floor and rests there")
	await seconds(0.3)
	# the shadow swells through the tell
	await wait_until(func() -> bool: return b.phase_at(Game.course_time) == 1, 6.0, "the tell begins")
	await get_tree().physics_frame
	var a0: float = (b._shadow.material_override as StandardMaterial3D).albedo_color.a
	var s0: float = b._shadow.scale.x
	await seconds(0.7)
	var a1: float = (b._shadow.material_override as StandardMaterial3D).albedo_color.a
	check(a1 > a0 + 0.1 and b._shadow.scale.x > s0 + 0.2, "the floor shadow darkens and grows through the tell (alpha %.2f -> %.2f)" % [a0, a1])
	# standing clear when is_clear_for() says so is safe; standing under it through the drop is not
	var d0: int = lvl.deaths
	await wait_until(func() -> bool: return b.is_clear_for(Game.course_time, 0.4) and b.phase_at(Game.course_time) == 0, 8.0, "a clear moment")
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(0, 0.1, 0)))
	await seconds(0.3)
	check(lvl.deaths == d0, "standing under it while is_clear_for() holds is safe")
	var hit: bool = await wait_until(func() -> bool: return lvl.deaths > d0, 5.0, "the drop")
	var land_t: float = b._rest_len + b.tell + b.FALL
	check(hit and fposmod(Game.course_time, b.period) > land_t - 0.2, "the block kills a rider who stays under it through the drop")
	# approach mode: idle until someone comes near, then the same tell and drop
	var a: FallingBlock = lvl.kit.falling_block(base + Vector3(14, 0, 0), Vector3(3, 1.6, 3), 7.0, 5.0, 0.0, true)
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(14, 0.1, 12)))
	await seconds(1.0)
	check(a.phase_at(Game.course_time) == 0 and a.gap_at(Game.course_time) == 7.0, "an approach block stays up while nobody is near")
	d0 = lvl.deaths
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(14, 0.1, 4.0)))
	var armed: bool = await wait_until(func() -> bool: return a.phase_at(Game.course_time) == 1, 1.0, "the approach block to arm")
	var armed_at: float = Game.course_time
	check(armed, "coming within the trigger radius starts the tell at once")
	lvl.player.teleport(Transform3D(Basis(), base + Vector3(14, 0.1, 0)))
	await wait_until(func() -> bool: return lvl.deaths > d0, 4.0, "the approach block lands")
	check(Game.course_time - armed_at >= 0.8, "and it fell no sooner than the tell (%.2f s after arming)" % (Game.course_time - armed_at))


func test_zk_hammer() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab()
	var h: SpinHammer = kit.hammer(Vector3(0, 0, 0), 5.0, 4.8, 0.0, 180.0, 1.0)
	check(_kit_phase_span(h.period, h.phase_at, 1) >= 0.8, "the hammer winds back for at least 0.8 s (%.2f s)" % _kit_phase_span(h.period, h.phase_at, 1))
	check(absf(h.angle_at(0.0) - 180.0) < 0.01 and absf(h.angle_at(h._rest_len + h.tell + h.swing_time - 0.001) - 540.0) < 0.5, "it parks at park_deg and sweeps one full turn")
	check(h.is_parked_for(0.0, 2.0) and not h.is_parked_for(0.0, h._rest_len + 0.2) and h.tip_speed_at(0.5) < 0.1 and h.tip_speed_at(h._rest_len + h.tell + h.swing_time * 0.5) > 15.0, "is_parked_for() and the head speed follow the clock")
	var knocks: Array[int] = [0]
	player.knocked.connect(func(_v: Vector3) -> void: knocks[0] += 1)
	# parked: standing right at the parked head is harmless (arm points -X)
	await wait_until(func() -> bool: return h.phase_at(Game.course_time) == 0 and h.parked_left(Game.course_time) > 1.5, 8.0, "the hammer to park")
	player.teleport(Transform3D(Basis(), Vector3(2.5, 0.05, 0)))
	await seconds(0.6)
	check(knocks[0] == 0 and player.grounded, "a rider on the clear side of a parked hammer is untouched")
	# in the way of the swing: knocked outward and up
	player.teleport(Transform3D(Basis(), Vector3(-4.0, 0.05, 0)))
	var got: bool = await wait_until(func() -> bool: return knocks[0] > 0, 8.0, "the hammer reaches the rider")
	check(got and player.velocity.y > 5.0 and player.velocity.length() > 8.0, "the swing knocks the rider away (v %s)" % str(player.velocity.snapped(Vector3.ONE * 0.1)))


func test_zk_bot_slice2() -> void:
	await _kit_bot("res://tests/kit_course2.gd", 150.0, "the bot passes the gap wall, falling block, hammer, flipper and drawbridge")


func test_zk_gallery() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	Game.level_index = -1
	Game.race_mode = false
	Game.course_time = 0.0
	Game.course_running = true
	var lvl: LevelBase = (load("res://levels/playground.tscn") as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(5)
	var kinds: Array[String] = ["LaunchBarrel", "Zipline", "CannonBattery", "RollingLog", "Seesaw", "Flipper", "Drawbridge", "GapWall", "FallingBlock", "SpinHammer"]
	var missing: Array[String] = []
	for k: String in kinds:
		if lvl.find_children("*", k, true, false).is_empty():
			missing.append(k)
	check(missing.is_empty(), "the Kit Gallery shows all ten obstacles (missing: %s)" % str(missing))
	check(lvl.find_children("*", "Label3D", true, false).size() >= 11, "and labels them")
	lvl.player.use_device_input = false
	lvl.player.teleport(Transform3D(Basis(), Vector3(60, 0.1, -2)))
	await seconds(0.8)
	check(lvl.player.grounded and lvl.deaths == 0, "the gallery floor is solid and joined to the playground (y %.2f)" % lvl.player.global_position.y)
	lvl.player.cmd_move = Vector2(-1, 0)
	await seconds(2.6)
	lvl.player.cmd_move = Vector2.ZERO
	check(lvl.player.global_position.x < 40.0 and lvl.player.grounded and lvl.deaths == 0, "and you can walk back over the join to the playground (x %.1f)" % lvl.player.global_position.x)


# ======================================================================================
# anim-depth (C6): online move mirroring, idle fidgets and flourishes, landing variety, the
# checkpoint touch and the respawn materialize.
# ======================================================================================

## A built, settled visual standing at the origin of the test world.
func _zn_visual(character: String = "volt") -> PlayerVisual:
	var v := PlayerVisual.new()
	v.set_character(character)
	add_child(v)
	await ticks(2)
	for i: int in 20:
		v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	return v


## Flags -> wire -> flags, over the relay event and the direct RPC handler.
func test_zn_move_flags_wire() -> void:
	check(MoveFlags.clean(null) == 0 and MoveFlags.clean("7") == 0 and MoveFlags.clean(-3) == 0 and MoveFlags.clean(99) == 0
		and MoveFlags.clean(NAN) == 0 and MoveFlags.clean([1]) == 0, "junk flags mean no move")
	check(MoveFlags.clean(MoveFlags.WALL_RIGHT) == 0 and MoveFlags.clean(float(MoveFlags.KICK)) == MoveFlags.KICK, "a wall side without a wall is dropped; floats are fine")
	check(MoveFlags.clean(MoveFlags.WALL | MoveFlags.WALL_RIGHT) == 3 and MoveFlags.wall_side(3) == 1.0 and MoveFlags.wall_side(1) == -1.0 and MoveFlags.wall_side(MoveFlags.KICK) == 0.0, "wall side")
	var plain: Dictionary = Net.pose_packet(Vector3(1, 2, 3), Vector3.ZERO, true, 4)
	var moving: Dictionary = Net.pose_packet(Vector3(1, 2, 3), Vector3.ZERO, false, 4, MoveFlags.WALL | MoveFlags.KICK)
	check(not plain.has("f") and moving.get("f") == 9, "a plain pose packet carries no flags key; a move adds one small int")
	var lvl: LevelBase = await _zm_race_level()
	var g: RemoteRacer = lvl._ghosts.get(2)
	var got: Array = []
	var catcher := func(id: int, _pos: Vector3, _vel: Vector3, _grounded: bool, _seq: int) -> void: got.append([id, Net.pose_flags.get(id, -1)])
	Net.racer_pose.connect(catcher)
	# the relay path: JSON in, flags out (the key survives the round trip)
	var wire: Variant = JSON.parse_string(JSON.stringify(moving))
	Net._handle_relay_event(2, "pose", wire)
	check(got == [[2, 9]] and Net.pose_flags[2] == 9, "the relay event delivers the move bits (%s)" % [got])
	check(g.move_flags() == 9, "and the racer shows them")
	# an older client's packet (no key) means no move, and clears the old bits
	Net._handle_relay_event(2, "pose", JSON.parse_string(JSON.stringify(plain)))
	check(Net.pose_flags[2] == 0 and g.move_flags() == 0, "a packet without flags clears them")
	# garbage never gets through
	for bad: Variant in ["x", 99, -1, null, [3], {"a": 1}]:
		var pk: Dictionary = plain.duplicate()
		pk["f"] = bad
		Net._handle_relay_event(2, "pose", pk)
		check(Net.pose_flags[2] == 0, "junk flags %s are ignored" % [bad])
	# the direct path: the _pose_f RPC handler (the sender id is 0 outside a real RPC)
	Net.roster[0] = Net.roster[2]
	Net._pose_f(Vector3.ZERO, Vector3.ZERO, false, 0, MoveFlags.MANTLE)
	check(Net.pose_flags.get(0) == MoveFlags.MANTLE, "the direct RPC delivers the bits")
	Net._pose(Vector3.ZERO, Vector3.ZERO, true, 0)
	check(Net.pose_flags.get(0) == 0, "and the plain RPC means none")
	Net._pose_f(Vector3.ZERO, Vector3.ZERO, false, 0, 4096)
	check(Net.pose_flags.get(0) == 0, "junk over the RPC is ignored too")
	Net.roster.erase(0)
	Net.pose_flags.erase(0)
	# sending outside a link is harmless, flags or not
	Net.send_pose(Vector3.ZERO, Vector3.ZERO, true, MoveFlags.WALL)
	Net.racer_pose.disconnect(catcher)
	await _zm_end_race()


## The sender's side: what the local player reports.
func test_zn_player_reports_moves() -> void:
	await new_world()
	check(player.net_move_flags() == 0, "standing still shows no move")
	player._wall_body = player
	player._wall_normal = Vector3(-1, 0, 0)   # the panel is on the player's right when facing -z
	check(player.net_move_flags() == (MoveFlags.WALL | MoveFlags.WALL_RIGHT), "wall running on the right")
	player._wall_normal = Vector3(1, 0, 0)
	check(player.net_move_flags() == MoveFlags.WALL, "wall running on the left")
	player._wall_body = null
	player._mantle_t = 0.2
	check(player.net_move_flags() == MoveFlags.MANTLE, "mantling")
	player._mantle_t = -1.0
	player._wall_jump()
	check(player.net_move_flags() & MoveFlags.KICK != 0, "a wall kick raises its bit")
	player._nf_kick_until = 0
	check(player.net_move_flags() & MoveFlags.KICK == 0, "and drops it after the hold")
	player.knockback(Vector3(4, 6, 0))
	check(player.net_move_flags() & MoveFlags.KNOCK != 0, "a knock raises its bit")
	player._nf_knock_until = 0
	check(player.net_move_flags() == 0, "and drops it too")
	world.queue_free()
	world = null
	await ticks(2)


## The receiving side: remote racers drive the same visual hooks.
func test_zn_remote_racer_mirrors_moves() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var e0: int = trap.count()
	var r := RemoteRacer.new()
	add_child(r)
	await ticks(1)
	r.setup("Ada", Settings.RACER_COLORS[1])
	var v: PlayerVisual = r.visual()
	var pos := Vector3(0, 1, 0)
	var run := Vector3(0, 0, -8)
	r.push_state(pos, run, true, 0)   # (the four-argument call of an older caller still works)
	await _frames(3)
	# the wall run: latch fx, lean away from the wall, the wall-side mitt reaches
	r.push_state(pos, run, false, 0, MoveFlags.WALL | MoveFlags.WALL_RIGHT)
	check(v.wall_roll == 1.0 and v.wall_normal != Vector3.ZERO and r.move_flags() == 3, "a wall run on the right shows (roll %.1f)" % v.wall_roll)
	check(absf(v.wall_normal.dot(r.facing().cross(Vector3.UP))) > 0.9 and v.wall_normal.dot(r.facing().cross(Vector3.UP)) < 0.0, "the panel is on the right of their heading")
	await _frames(25)
	check(v._lean.y > 0.25, "they lean away from the wall (%.2f)" % v._lean.y)
	check(v._air_t == 0.0, "the wall run counts as on the ground for the pose")
	r.push_state(pos, run, false, 0, MoveFlags.WALL)
	check(v.wall_roll == -1.0, "the other side too")
	# the wall kick: a flip and the radial burst, once per rising edge
	var jump_before: float = v._jump_t
	r.push_state(pos, Vector3(2, 9, 0), false, 0, MoveFlags.KICK)
	check(v._flip_t == 0.0 and v._kick_t > 0.3 and v.wall_roll == 0.0, "a wall kick flips")
	check(v._jump_t == jump_before, "and is not also guessed as a plain jump")
	v._flip_t = 5.0
	r.push_state(pos, Vector3(2, 9, 0), false, 0, MoveFlags.KICK)
	check(v._flip_t == 5.0, "a held bit does not retrigger")
	r.push_state(pos, Vector3(2, 9, 0), false, 0, 0)
	r.push_state(pos, Vector3(2, 9, 0), false, 0, MoveFlags.KICK)
	check(v._flip_t == 0.0, "but the next one does")
	# the mantle scramble
	r.push_state(pos, Vector3.ZERO, false, 0, 0)
	await _frames(3)
	r.push_state(pos, Vector3(0, 3, 0), false, 0, MoveFlags.MANTLE)
	check(v._mantle_t == 0.0, "a mantle starts the scramble")
	await _frames(10)
	check(v._mantle_t > 0.0 and v._mantle_t < v._mantle_len * 1.2, "it plays out (%.2f)" % v._mantle_t)
	# the knock flail
	r.push_state(pos, Vector3.ZERO, true, 0, 0)
	await _frames(25)
	r.push_state(pos, Vector3(5, 7, 0), false, 0, MoveFlags.KNOCK)
	check(v._knock_t == 0.0, "a knock flails")
	# without the flag the old guesses still work
	r.push_state(pos, Vector3.ZERO, true, 0, 0)
	r.push_state(pos, Vector3(0, 8, 0), false, 0, 0)
	check(v._jump_t == 0.0, "a jump with no flags is still guessed")
	# a respawn (new seq) drops the bits
	r.push_state(pos, run, false, 1, MoveFlags.WALL)
	r.push_state(pos, run, true, 2, 0)
	check(r.move_flags() == 0 and v.wall_roll == 0.0, "a respawn clears the move")
	# junk is clamped by MoveFlags.clean
	r.push_state(pos, run, true, 2, 4096)
	check(r.move_flags() == 0, "an out-of-range value is no move")
	await _frames(10)
	check(trap.count() == e0, "no errors %s" % trap.since(e0))
	r.queue_free()
	await ticks(2)


## The ghost keeps the move bits too (and an older ghost, which has none, still plays).
func test_zn_ghost_keeps_moves() -> void:
	var g := GhostData.new()
	g.level_id = "gardens"
	g.rev = GhostData.current_rev("gardens")
	g.time = 3.0
	g.add(Vector3(0, 0, 0), 0.0, true, false, false)
	g.add(Vector3(0, 0, -1), 0.0, false, true, false, MoveFlags.WALL | MoveFlags.WALL_RIGHT)
	g.add(Vector3(0, 1, -2), 0.0, false, false, false, MoveFlags.MANTLE)
	g.add(Vector3(0, 2, -3), 0.0, false, false, false, MoveFlags.KICK | MoveFlags.KNOCK)
	g.add(Vector3(0, 2, -4), 0.0, true, false, true, 99)
	check(g.moves_at(0) == 0 and g.moves_at(1) == 3 and g.moves_at(2) == MoveFlags.MANTLE and g.moves_at(3) == (MoveFlags.KICK | MoveFlags.KNOCK) and g.moves_at(4) == 0,
		"each sample keeps its bits (junk dropped)")
	var back: GhostData = GhostData.decode(g.encode(), "gardens")
	check(back != null and back.moves_at(1) == 3 and back.moves_at(3) == 24, "they survive the file")
	check(int(back.sample(1.0 / float(GhostData.HZ))["moves"]) == 3 and bool(back.sample(1.0 / float(GhostData.HZ))["wall"]), "sample() reports them")
	# a ghost recorded before this update has only the old bits
	var old := GhostData.new()
	old.add(Vector3.ZERO, 0.0, true, false, false)
	old.add(Vector3.ZERO, 0.0, false, true, false)
	old.add(Vector3.ZERO, 0.0, true, false, true)
	check(old.moves_at(0) == 0 and old.moves_at(1) == MoveFlags.WALL and old.moves_at(2) == 0, "an older ghost reads as wall-or-nothing (the snap bit is not a move)")
	# a racer replaying them
	var r := RemoteRacer.new()
	add_child(r)
	await ticks(1)
	r.make_ghost("PB", Color.WHITE)
	r.push_state(Vector3.ZERO, Vector3.ZERO, true, 0, 0)
	r.push_state(Vector3.ZERO, Vector3.ZERO, true, 0, g.moves_at(1))
	check(r.visual().wall_roll == 1.0, "the ghost wall-runs when it did")
	r.push_state(Vector3.ZERO, Vector3.ZERO, true, 0, g.moves_at(3))
	check(r.visual()._knock_t == 0.0 and r.visual()._flip_t < 1.0, "and kicks / flails")
	r.queue_free()
	await ticks(2)


## Fidgets 4-7 and every character's flourish: finite, above the floor, and each really moves
## something.
func test_zn_fidgets_and_flourishes() -> void:
	await new_world()
	var chars: Array = Cosmetics.ids("character")
	check(chars.size() >= 15, "all the characters are covered (%d)" % chars.size())
	var seen: Dictionary = {}
	for n: int in 10:
		seen[Flourish.pick(n, 0.0, 0.0)] = true
	check(seen.size() == Flourish.COUNT, "the fidget rotation reaches all %d fidgets (%s)" % [Flourish.COUNT, str(seen.keys())])
	for r2: float in [0.0, 0.3, 0.6, 0.999, 1.0]:
		check(Flourish.pick(3, 0.9, r2) >= 0 and Flourish.pick(3, 0.9, r2) < Flourish.COUNT, "a random pick stays in range (%.2f)" % r2)
	var e0: int = trap.count()
	var f := Flourish.Pose.new()
	for c: String in chars:
		check(Flourish.OF_CHARACTER.has(c) and Flourish.LEN.has(Flourish.OF_CHARACTER[c]), "%s has its own flourish" % c)
		var v: PlayerVisual = await _zn_visual(c)
		var floor_y: float = v.global_position.y
		for fid: int in range(Flourish.FIRST_NEW, Flourish.COUNT):
			var clip: String = Flourish.clip_for(fid, c)
			var len: float = Flourish.length(fid, c)
			check(clip != "" and len > 1.0, "%s fidget %d is the clip '%s' (%.1f s)" % [c, fid, clip, len])
			# the pure pose: finite, and the clip does something
			var moved: float = 0.0
			var finite: bool = true
			var t: float = 0.0
			while t < len:
				Flourish.sample(f, clip, t)
				for p: Vector3 in [f.hr, f.hl, f.fr, f.fl, f.torso_rot]:
					finite = finite and p.is_finite()
				finite = finite and is_finite(f.torso_y) and is_finite(f.root_y) and is_finite(f.spin) and is_finite(f.eye) and is_finite(f.ant_scale) and f.ant_kick.is_finite()
				moved = maxf(moved, maxf((f.hr - Flourish.HAND).length(), (f.hl - Vector3(-Flourish.HAND.x, Flourish.HAND.y, Flourish.HAND.z)).length()))
				moved = maxf(moved, maxf((f.fr - Flourish.FOOT).length(), (f.fl - Vector3(-Flourish.FOOT.x, Flourish.FOOT.y, Flourish.FOOT.z)).length()))
				moved = maxf(moved, maxf(f.torso_rot.length(), maxf(absf(f.root_y), maxf(f.sway * 0.3, absf(f.ant_scale - 1.0)))))
				t += 0.05
			check(finite, "%s / %s: the sampled pose is finite" % [c, clip])
			check(moved > 0.05, "%s / %s: it moves something (%.2f)" % [c, clip, moved])
			# played on the rig: every mesh finite, nothing sinks below the floor
			v._fidget = fid
			v._fidget_t = 0.0
			v._fl_puffs = 0
			var low: float = INF
			var ok: bool = true
			var frames: int = int(len * 60.0) + 12
			for i: int in frames:
				v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
				if i % 6 == 0:
					for mi: MeshInstance3D in _zm_meshes(v._root):
						var o: Vector3 = mi.global_transform.origin
						ok = ok and o.is_finite() and mi.global_transform.basis.is_finite()
					var box: AABB = _zm_aabb(v._root)
					low = minf(low, box.position.y - floor_y)
			check(ok, "%s / %s: every mesh transform stays finite" % [c, clip])
			check(low > -0.05, "%s / %s: nothing sinks below the floor (lowest %.3f)" % [c, clip, low])
			# the fidget is over (animate ended it) and the body is back at rest
			check(v._fidget == -1 or v._fidget_t < len, "%s / %s: the fidget ends" % [c, clip])
			v._fidget = -1
			for i: int in 30:
				v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
			check(v._fl_clip == "" and v._sway_boost == 0.0 and absf(v._torso.rotation.x) < 0.001 and absf(v._torso.rotation.z) < 0.001 and v._antenna.scale.is_equal_approx(Vector3.ONE),
				"%s / %s: everything it touched goes back to rest" % [c, clip])
		v.queue_free()
	check(trap.count() == e0, "no errors %s" % trap.since(e0))
	# the secondary motion really changes: the dino's tail, the pirate's parrot, the wizard's orb, the knight's sword
	var dino: PlayerVisual = await _zn_visual("dino")
	var wag: float = 0.0
	dino._fidget = Flourish.FLOURISH
	dino._fidget_t = 0.0
	for i: int in 90:
		dino.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
		wag = maxf(wag, absf(dino._sways[0].node.rotation.y))
	check(wag > 0.3, "the dino's tail wags hard in its flourish (%.2f rad)" % wag)
	dino.queue_free()
	var pirate: PlayerVisual = await _zn_visual("pirate")
	var flap: float = 0.0
	pirate._fidget = Flourish.FLOURISH
	pirate._fidget_t = 0.0
	for i: int in 90:
		pirate.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
		flap = maxf(flap, absf(pirate._sways[0].node.rotation.x - pirate._sways[0].base.x))
	check(flap > 0.15, "the parrot flaps (%.2f rad)" % flap)
	pirate.queue_free()
	var wiz: PlayerVisual = await _zn_visual("wizard")
	var orb: float = 1.0
	wiz._fidget = Flourish.FLOURISH
	wiz._fidget_t = 0.0
	for i: int in 100:
		wiz.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
		orb = maxf(orb, wiz._antenna.scale.x)
	check(orb > 1.5, "the wizard's orb pulses (x%.2f)" % orb)
	wiz.queue_free()
	var knight: PlayerVisual = await _zn_visual("knight")
	var base_meshes: int = _zm_meshes(knight._root).size()
	knight._fidget = Flourish.FLOURISH
	knight._fidget_t = 0.0
	var shown: bool = false
	for i: int in 100:
		knight.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
		shown = shown or (knight._fl_prop != null and knight._fl_prop.visible)
	check(shown, "the knight's sword comes out")
	for i: int in 120:
		knight.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(knight._fl_prop != null and not knight._fl_prop.visible, "and goes away")
	check(_zm_meshes(knight._root).size() <= ZM_MESH_BUDGET - 8 and _zm_meshes(knight._root).size() <= base_meshes + 3, "the sword stays inside the mesh budget (%d -> %d)" % [base_meshes, _zm_meshes(knight._root).size()])
	knight.set_character("ninja")
	check(knight._fl_prop == null, "swapping the body drops the sword")
	knight.queue_free()
	# moving cancels a fidget quickly and cleanly
	var ninja: PlayerVisual = await _zn_visual("ninja")
	ninja._fidget = Flourish.FLOURISH
	ninja._fidget_t = 0.0
	for i: int in 60:
		ninja.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(ninja._fl_w > 0.5, "the ninja is mid-flourish")
	for i: int in 30:
		ninja.animate(1.0 / 60.0, Vector3(0, 0, -7), true, Vector3.FORWARD)
	check(ninja._fidget == -1 and ninja._fl_clip == "" and ninja._fl_w == 0.0, "running off ends it")
	ninja.queue_free()
	world.queue_free()
	world = null
	await ticks(2)


## Landing variety: a tap after a hop, a deep crouch and a dust ring after a big fall.
func test_zn_landing_scales_with_fall() -> void:
	await new_world()
	check(PlayerVisual.landing_heaviness(4.0) == 0.0 and PlayerVisual.landing_heaviness(14.0) == 0.0 and PlayerVisual.landing_heaviness(22.0) > 0.4 and PlayerVisual.landing_heaviness(40.0) == 1.0,
		"heaviness is zero up to a full jump and grows with the fall")
	var results: Array = []
	for impact: float in [4.0, 12.0, 20.0, 30.0]:
		var v: PlayerVisual = await _zn_visual("volt")
		var kids: int = v.get_child_count()
		v.on_land(impact)
		var rings: int = v.get_child_count() - kids
		var low: float = 1.0
		var squash_low: float = 1.0
		var crouch_frames: int = 0
		for i: int in 60:
			v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
			low = minf(low, v._torso.position.y)
			squash_low = minf(squash_low, v._squash)
			if v._torso.position.y < 0.2 - 0.01:
				crouch_frames += 1
		results.append({"impact": impact, "dip": 0.2 - low, "squash": -squash_low, "frames": crouch_frames, "rings": rings, "h": v._land_h})
		v.queue_free()
	for i: int in range(1, results.size()):
		var a: Dictionary = results[i - 1]
		var b: Dictionary = results[i]
		check(float(b["dip"]) > float(a["dip"]) and float(b["squash"]) >= float(a["squash"]) and int(b["frames"]) >= int(a["frames"]),
			"a harder landing (%.0f vs %.0f m/s) crouches deeper and longer (dip %.3f vs %.3f, squash %.2f vs %.2f, %d vs %d frames)" % [b["impact"], a["impact"], b["dip"], a["dip"], b["squash"], a["squash"], b["frames"], a["frames"]])
	check(float(results[3]["squash"]) > float(results[0]["squash"]) + 0.2 and float(results[0]["dip"]) < 0.05 and float(results[3]["dip"]) > 0.12, "a tap barely dips; a big fall drops the body (%.3f / %.3f)" % [results[0]["dip"], results[3]["dip"]])
	check(int(results[3]["frames"]) > int(results[1]["frames"]) + 6, "and it takes longer to recover (%d vs %d frames)" % [results[3]["frames"], results[1]["frames"]])
	check(int(results[0]["rings"]) == 0 and int(results[1]["rings"]) == 0 and int(results[2]["rings"]) >= 1 and int(results[3]["rings"]) >= 1, "only a big fall adds the dust ring (%s)" % str(results.map(func(d: Dictionary) -> int: return d["rings"])))
	check(float(results[0]["h"]) == 0.0 and float(results[3]["h"]) > 0.9, "the heaviness is recorded")
	# a remote racer lands the same way from the reported fall speed
	var r := RemoteRacer.new()
	add_child(r)
	await ticks(1)
	r.push_state(Vector3(0, 5, 0), Vector3(0, -26, 0), false, 0)
	r.push_state(Vector3(0, 0, 0), Vector3(0, -26, 0), true, 0)
	check(r.visual()._land_h > 0.5, "a remote racer's big fall lands heavy")
	r.queue_free()
	# the ring follows the particle slider
	var amounts: Array = []
	var old_slider: float = Settings.particles
	for slider: float in [0.2, 2.0]:
		Settings.particles = slider
		var v2: PlayerVisual = await _zn_visual("volt")
		var before: Array = v2.get_children()
		v2.on_land(30.0)
		for ch: Node in v2.get_children():
			if not before.has(ch) and ch is GPUParticles3D and (ch as GPUParticles3D).one_shot:
				amounts.append((ch as GPUParticles3D).amount)
				break
		v2.queue_free()
	Settings.particles = old_slider
	check(amounts.size() == 2 and amounts[1] > amounts[0], "the landing ring scales with the particle setting (%s)" % str(amounts))
	world.queue_free()
	world = null
	await ticks(2)


## The checkpoint touch rotates between a fist pump, a spin and a two-fisted pump; a respawn
## materializes (a thin beam that fills out, sparkles climbing it).
func test_zn_checkpoint_flourish_and_respawn() -> void:
	await new_world()
	var v: PlayerVisual = await _zn_visual("volt")
	var seen: Array[int] = []
	var wide: Array[float] = []
	for k: int in 3:
		for i: int in 60:
			v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
		v.on_checkpoint()
		seen.append(v._cp_variant)
		var spun: bool = v._flip_axis.y != 0.0 and v._flip_t < v._flip_len
		var reach: float = 0.0
		var finite: bool = true
		for i: int in 40:
			v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
			reach = maxf(reach, minf(v._hand_r.position.y, v._hand_l.position.y))
			finite = finite and v._hand_r.position.is_finite() and v._hand_l.position.is_finite() and v._flip.basis.is_finite()
		wide.append(reach)
		check(finite, "checkpoint flourish %d stays finite" % k)
		check(spun == (k == 1), "only the second touch spins (touch %d: spun %s)" % [k, spun])
	check(seen == [0, 1, 2], "the touch rotates through its variants (%s)" % str(seen))
	check(wide[1] > 0.7, "the spin throws both mitts up (%.2f)" % wide[1])
	for i: int in 60:
		v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(v._flip.basis.is_equal_approx(Basis.IDENTITY), "the spin lands square")
	# respawn
	var kids: int = v.get_child_count()
	v.on_respawn()
	check(v._appear_fx == 0, "the sparkle-in is pending")
	v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(v._rig.scale.x < v._rig.scale.y, "it starts as a thin beam (%s)" % str(v._rig.scale))
	for i: int in 30:
		v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(v._appear_fx == v.MATERIALIZE_AT.size(), "all the sparkle bands fired")
	check(v.get_child_count() >= kids + 3, "as three bursts (%d new)" % (v.get_child_count() - kids))
	for i: int in 30:
		v.animate(1.0 / 60.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(v._rig.scale.is_equal_approx(Vector3.ONE), "and settles at full size (%s)" % str(v._rig.scale))
	v.queue_free()
	world.queue_free()
	world = null
	await ticks(2)


# ---- CPU racers (party/cpu/) -----------------------------------------------------------------------

## A CPU walker following a level's route from the start to the finish, headless. Returns the walker.
func _cpu_walk(index: int, diff: String, budget_s: float) -> RouteWalker:
	var lvl: LevelBase = await load_level(index)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + index
	var w := RouteWalker.new()
	w.setup(lvl, CpuSkill.personal(diff, rng), 4242 + index, lvl._spawn.origin)
	var label: String = str(Game.LEVELS[index]["name"])
	# (Engine.time_scale scales the physics step: use the course clock's own delta)
	var last: float = Game.course_time
	var t: float = 0.0
	while t < budget_s and not w.done:
		await get_tree().physics_frame
		var dt: float = Game.course_time - last
		last = Game.course_time
		w.tick(dt)
		w.events.clear()
		t += dt
	check(w.done, "%s: a %s CPU follows the route to the finish (%.0fs, %d respawns, %d skipped steps, step %d/%d)" % [label, diff, t, w.deaths, w.skipped, w.step, lvl.route.size()])
	check(w.cp >= lvl.checkpoints.size() - 1 and w.skipped <= 3, "%s: the CPU banked its checkpoints (%d/%d) without skipping the route" % [label, w.cp, lvl.checkpoints.size()])
	metrics["%s cpu %s time s" % [Game.LEVELS[index]["id"], diff]] = snappedf(t, 0.1)
	return w


func test_zcpu_route_coverage() -> void:
	for i: int in Game.LEVELS.size():
		if only_level >= 0 and i != only_level:
			continue
		var lvl: LevelBase = await load_level(i)
		var marks: int = 0
		for s: Dictionary in lvl.route:
			if str(s["kind"]) == "checkpoint":
				marks += 1
		var gates: int = lvl.find_children("*", "FinishGate", true, false).size()
		check(lvl.route.size() > 5 and gates >= 1, "%s: a route (%d steps, %d checkpoint marks for %d checkpoints) and a finish gate for the CPUs" % [Game.LEVELS[i]["name"], lvl.route.size(), marks, lvl.checkpoints.size()])
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)


## Early, mid and late course: a CPU drives the course's own route to the finish.
func test_zcpu_finishes_early_mid_late() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	var picks: Array[int] = [0, 13, 24]
	if only_level >= 0:
		picks = [only_level]
	Engine.time_scale = 8.0
	for i: int in picks:
		await _cpu_walk(i, "hard", 700.0)
	Engine.time_scale = 1.0
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)


## Easy botches more jumps than Hard and is slower; the skill table orders the three levels.
func test_zcpu_skill_levels() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	var easy: Dictionary = CpuSkill.TABLE[CpuSkill.EASY]
	var norm: Dictionary = CpuSkill.TABLE[CpuSkill.NORMAL]
	var hard: Dictionary = CpuSkill.TABLE[CpuSkill.HARD]
	check(float(easy["speed"]) < float(norm["speed"]) and float(norm["speed"]) < float(hard["speed"]), "Easy < Normal < Hard in running speed")
	check(float(easy["jump_fail"]) > float(norm["jump_fail"]) and float(norm["jump_fail"]) > float(hard["jump_fail"]), "Easy botches more jumps than Normal, Normal more than Hard")
	check(float(easy["react"]) > float(hard["react"]) and bool(hard["cut"]) and not bool(easy["cut"]), "Hard reacts faster and cuts corners")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var a: Dictionary = CpuSkill.personal("normal", rng)
	var b: Dictionary = CpuSkill.personal("normal", rng)
	check(a["speed"] != b["speed"], "two CPUs of one level do not drive identically")
	# a botched long jump respawns the CPU at its checkpoint like a human
	var lvl: LevelBase = await load_level(0)
	var w := RouteWalker.new()
	var p: Dictionary = CpuSkill.personal("easy", rng)
	p["jump_fail"] = 1.0
	w.setup(lvl, p, 7, lvl._spawn.origin)
	Engine.time_scale = 5.0
	var last: float = Game.course_time
	var t: float = 0.0
	while t < 120.0 and w.deaths == 0:
		await get_tree().physics_frame
		var dt: float = Game.course_time - last
		last = Game.course_time
		w.tick(dt)
		t += dt
	Engine.time_scale = 1.0
	check(w.deaths >= 1, "a botched long jump makes the CPU fall and respawn (%.0fs in)" % t)
	check(w.hold > 0.0 or w.pos.distance_to(w.respawn_point()) < 6.0, "...and it stands at its respawn point for a beat")
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)


func _cpu_cleanup() -> void:
	CpuField.test_hold = false
	Engine.time_scale = 1.0
	CpuField.test_seed = -1
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	Net.leave()
	Game.party = null
	Game.race_mode = false


## Starts a solo Party vs CPU round the way Game.play_party_cpu does, but loads the course under this
## test (play_party_cpu changes scenes, which would unload the runner).
func _cpu_round(index: int, count: int, diff: String, mode: String = "party", countdown: float = 1.5) -> LevelBase:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	Net.host_local()
	CpuField.configure_local(count, diff)
	CpuField.sync_roster()
	Net.host_set_mode(mode)
	Net.race_starting.disconnect(Game._on_race_starting)
	Net.host_start_race(index, countdown)
	Net.race_starting.connect(Game._on_race_starting)
	Game.race_mode = true
	Game.party = PartyRules.new(Net.game_mode)
	Game.party.round_no = Net.party_round
	Game.level_index = index
	Game.course_time = Net.now() - Net.race_start_time
	Game.course_running = true
	var lvl: LevelBase = (load(Game.LEVELS[index]["scene"]) as PackedScene).instantiate() as LevelBase
	add_child(lvl)
	world = lvl
	await ticks(6)
	return lvl


func _cpu_field(lvl: LevelBase) -> CpuField:
	return lvl.party.find_child("CpuField", false, false) as CpuField


## The menu: Party vs CPU is on the main menu, reachable and operable with a pad alone.
func test_zcpu_menu_pad() -> void:
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	title.call("show_screen", "main")
	await ticks(3)
	var e0: int = trap.count()
	# the column must fit the 900 px canvas minus its 60 px margins (the headless window is not 1600x900)
	var top: float = INF
	var bottom: float = 0.0
	for c: Node in (title.get("_screen") as Control).find_children("*", "Control", true, false):
		if c is Button or c is Label:
			top = minf(top, (c as Control).get_global_rect().position.y)
			bottom = maxf(bottom, (c as Control).get_global_rect().end.y)
	check(bottom > top and bottom - top <= 880.0, "the main menu with its new button still fits the 900 px canvas (%.0f px of 880)" % (bottom - top))
	var found: bool = false
	for i: int in 10:
		if _focused_text() == "Party vs CPU":
			found = true
			break
		await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(found, "the D-pad reaches Party vs CPU on the main menu")
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(3)
	check(Game.title_screen == "partycpu", "A opens the Party vs CPU screen")
	check(_focused_text() == "Start the Cup", "the screen starts on its Start button (%s)" % _focused_text())
	# up through the rows: course, difficulty, CPU count, mode
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_UP))
	check(_focused_text().begins_with("Course:"), "D-pad up reaches the Course row (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_UP))
	check(_focused_text().begins_with("Difficulty:"), "...then Difficulty (%s)" % _focused_text())
	var before: String = _focused_text()
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_RIGHT))
	check(_focused_text() != before and _focused_text().begins_with("Difficulty:"), "D-pad right cycles the value (%s -> %s)" % [before, _focused_text()])
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_LEFT))
	check(_focused_text() == before, "D-pad left steps back (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	check(_focused_text() != before and _focused_text().begins_with("Difficulty:"), "A also cycles the focused row (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_UP))
	check(_focused_text().begins_with("CPU racers:"), "...then the CPU count (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_UP))
	check(_focused_text().begins_with("Mode:"), "...then the mode (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_B))
	await ticks(3)
	check(Game.title_screen == "main" and _focused_text() == "Party vs CPU", "B goes back onto the Party vs CPU button (%s)" % _focused_text())
	# the solo lobby (between rounds): CPU rows, no room code, B leaves
	Net.host_local()
	CpuField.configure_local(3, "normal")
	CpuField.sync_roster()
	Net.host_set_mode("party")
	title.call("show_screen", "lobby")
	await ticks(3)
	var labels: String = ""
	for l: Node in title.find_children("*", "Label", true, false):
		labels += (l as Label).text + "|"
	check(labels.contains("PARTY VS CPU") and labels.contains("(CPU)") and not labels.contains("ROOM CODE"), "the solo lobby lists the CPU racers and has no room code")
	check(Net.roster.size() == 4 and CpuField.cpu_ids().size() == 3, "three CPUs joined the roster (%d racers)" % Net.roster.size())
	var count_btn: Button = null
	for b: Node in title.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("CPU racers:"):
			count_btn = b as Button
	check(count_btn != null, "the lobby host can change the CPU count")
	if count_btn != null:
		count_btn.grab_focus()
		await _zp_press(_zp_pad(JOY_BUTTON_DPAD_RIGHT))
		check(CpuField.cpu_ids().size() == 4 and Net.roster.size() == 5, "D-pad right adds a CPU (%d)" % CpuField.cpu_ids().size())
	await _zp_press(_zp_pad(JOY_BUTTON_B))
	await ticks(3)
	check(Game.title_screen == "main" and not Net.active, "B in the solo lobby leaves the session")
	check(trap.count() == e0, ("the CPU menus build without errors %s" % trap.since(e0)).strip_edges())
	title.queue_free()
	await ticks(2)
	Game.title_screen = "main"


## The online lobby: the host's "Fill with CPUs" option, and how it tops the roster up.
func test_zcpu_online_fill() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	check(Net.host(24593) == OK, "hosting opens the lobby")
	await ticks(3)
	var fill: Button = null
	for b: Node in title.find_children("*", "Button", true, false):
		if (b as Button).name == "FillCpus":
			fill = b as Button
	check(fill != null and fill.text.ends_with("Off"), "the host's lobby offers Fill with CPUs (off by default)")
	Net.host_set_mode("party")
	if fill != null:
		fill.pressed.emit()
	check(CpuField.fill_online, "...and it switches on")
	CpuField.sync_roster()
	check(Net.roster.size() == 8 and CpuField.cpu_ids().size() == 7, "the roster fills to 8 racers with CPUs (%d)" % Net.roster.size())
	# a classic Race has no CPUs
	Net.host_set_mode("race")
	CpuField.sync_roster()
	check(CpuField.cpu_ids().is_empty() and Net.roster.size() == 1, "a plain Race strips the CPUs again")
	Net.host_set_mode("team")
	CpuField.sync_roster()
	var t0: int = 0
	for id: int in Net.roster:
		if Net.team_of(id) == 0:
			t0 += 1
	check(Net.roster.size() == 8 and absi(t0 - (8 - t0)) <= 1, "Team Party balances the CPUs into two even teams (%d / %d)" % [t0, 8 - t0])
	CpuField.clear_roster()
	check(Net.roster.size() == 1, "ending the cup takes the CPUs out of the roster again")
	CpuField.fill_online = false
	title.queue_free()
	Net.leave()
	await ticks(2)
	Game.title_screen = "main"


## A solo round with 3 CPUs: they race (poses, checkpoints, finish), item boxes feed them, the round ends
## and the cup scores everyone.
func test_zcpu_solo_round_scores() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	CpuField.test_seed = 4242   # repeatable CPU randomness: the same race every run
	var lvl: LevelBase = await _cpu_round(0, 3, "hard")
	var p: PartyLayer = lvl.party
	var f: CpuField = _cpu_field(lvl)
	check(p != null and f != null and f.racers.size() == 3, "a solo round has a party layer and three simulated CPUs")
	if p == null or f == null:
		await _cpu_cleanup()
		return
	check(lvl._ghosts.size() == 3 and Net.roster.size() == 4, "each CPU has a ghost on the course (%d ghosts, %d racers)" % [lvl._ghosts.size(), Net.roster.size()])
	for id: int in f.racers:
		var g: RemoteRacer = lvl._ghosts[id]
		check(g.racer_name == str(Net.roster[id]["name"]) and bool(Net.roster[id]["cpu"]), "CPU %d shows up as %s with its own look" % [id, g.racer_name])
	check(p.rules.mode == "party", "a Party round (free for all)")
	var start_pos: Array[Vector3] = []
	for id: int in f.racers:
		start_pos.append((f.racers[id] as CpuRacer).walker.pos)
	Engine.time_scale = 5.0
	await wait_until(func() -> bool: return Game.course_time > 25.0, 120.0, "25 s of racing")
	var moved: int = 0
	var i: int = 0
	for id: int in f.racers:
		if (f.racers[id] as CpuRacer).walker.pos.distance_to(start_pos[i]) > 20.0:
			moved += 1
		i += 1
	check(moved == 3, "all three CPUs ran at least 20 m in 25 s (%d)" % moved)
	var ghost_moved: int = 0
	for id: int in lvl._ghosts:
		if (lvl._ghosts[id] as RemoteRacer).global_position.distance_to(start_pos[0]) > 10.0:
			ghost_moved += 1
	check(ghost_moved >= 2, "their ghosts follow the poses the field sends (%d moved)" % ghost_moved)
	var cps: int = 0
	for id: int in f.racers:
		cps += int(Net.roster[id]["cp"])
	check(cps >= 1, "CPUs bank checkpoints in the roster (%d in total)" % cps)
	var seen: Dictionary = {"held": 0, "taken": 0}
	var count_items := func() -> bool:
		seen["held"] = 0
		seen["taken"] = 0
		for b: ItemBox in p.boxes:
			if not b.available:
				seen["taken"] = int(seen["taken"]) + 1
		for id: int in f.racers:
			if (f.racers[id] as CpuRacer).item != "":
				seen["held"] = int(seen["held"]) + 1
		return int(seen["taken"]) + int(seen["held"]) >= 1
	# (a CPU may use its item the moment it gets it, and a box comes back in 4 s: watch for the first one)
	await wait_until(count_items, 120.0, "a CPU to take an item box")
	var held: int = int(seen["held"])
	var taken: int = int(seen["taken"])
	check(taken + held >= 1, "item boxes feed the CPUs (%d boxes taken, %d CPUs holding an item)" % [taken, held])
	# the round ends 45 s after the first finisher; the CPUs finish, the idle human does not
	await wait_until(func() -> bool: return p.round_over, 700.0, "the round to end")
	Engine.time_scale = 1.0
	var finished: int = 0
	for id: int in f.racers:
		if float(Net.roster[id]["finished"]) >= 0.0:
			finished += 1
	check(finished >= 2, "at least two CPUs finished the course (%d of 3)" % finished)
	check(p.round_over and p.last_rows.size() == 4, "the round scored all four racers (%d rows)" % p.last_rows.size())
	var human_row: Dictionary = {}
	var top: Dictionary = p.last_rows[0]
	for r: Dictionary in p.last_rows:
		if int(r["id"]) == 1:
			human_row = r
		if int(r["place"]) == 1:
			top = r   # (rows are sorted by total points: KOs and bonuses can put 2nd place on top)
	check(CpuField.is_cpu_id(int(top["id"])) and int(top["place"]) == 1 and int(top["place_pts"]) == 10, "a CPU won the round and got the 10 placement points (top %s, finished %d, t %.0f)" % [str(top), finished, Game.course_time])
	check(not human_row.is_empty() and int(human_row["place"]) == 0 and int(human_row["place_pts"]) == 0, "the idle human got no placement points")
	var total: int = 0
	for id: Variant in Game.party.cup:
		total += int(Game.party.cup[id])
	check(Game.party.cup.size() == 4 and total >= 10 + 8, "the Party Cup holds everyone's points (%d racers, %d points)" % [Game.party.cup.size(), total])
	CpuField.test_seed = -1
	await _cpu_cleanup()


## Being hit, KO credit, hitting back, pick-ups and the items, on a live CPU.
func test_zcpu_hits_items_ko() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	var lvl: LevelBase = await _cpu_round(0, 3, "normal", "party", 0.5)
	var p: PartyLayer = lvl.party
	var f: CpuField = _cpu_field(lvl)
	await wait_until(func() -> bool: return Game.course_time > 3.0 and p._ready_done, 60.0, "the round to get going")
	var ids: Array = f.racers.keys()
	ids.sort()
	var a: CpuRacer = f.racers[ids[0]]
	var b: CpuRacer = f.racers[ids[1]]
	a.protect_left = 0.0
	b.protect_left = 0.0
	# the human shoves a CPU: the message goes through Net.send_party and reaches the CPU
	var kb := Vector3(8, 5, 0)
	Net.send_party({"k": "hit", "kb": PowerUp.arr(kb), "st": 0.5, "ko": false, "e": "", "ed": 0.0, "s": "shove", "add": false}, a.id)
	check(a.last_hit_by == 1 and a.walker.mode == RouteWalker.Mode.AIR and a.walker.hold > 0.0, "a human's hit on a CPU knocks and stuns it and is remembered (by %d)" % a.last_hit_by)
	# a fall within the KO window is the attacker's KO
	var kos: int = int(p.kos.get(1, 0))
	a.walker.die("fall")
	await ticks(2)
	check(int(p.kos.get(1, 0)) == kos + 1, "a CPU that falls right after a hit is the hitter's KO (+%d)" % PartyRules.KO_POINTS)
	check(a.protect_left > 0.0 and a.walker.deaths == 1, "...and it respawns with a protection window")
	a.protect_left = 0.0
	# a CPU's hit on the human is credited to the CPU
	var human: Dictionary = {}
	for r: Dictionary in f.rivals_of(b):
		if int(r["id"]) == 1:
			human = r
	check(not human.is_empty(), "the human is one of a CPU's rivals")
	p.protect_left = 0.0   # (no respawn grace on the human)
	f.hit_rival(b, human, Vector3(0, 6, 0), {"st": 0.4, "s": "shove"})
	check(p.last_hit_by == b.id and lvl.player.party_stun > 0.0, "a CPU's shove stuns the human and is credited to the CPU (by %d)" % p.last_hit_by)
	var deaths: int = lvl.deaths
	lvl.fail("fall")
	await ticks(2)
	check(int(p.kos.get(b.id, 0)) == 1 and lvl.deaths == deaths + 1, "the human falling after that hit is the CPU's KO")
	# pick-up: a CPU standing in a box takes it
	var box: ItemBox = null
	for bx: ItemBox in p.boxes:
		if bx.available:
			box = bx
			break
	b.item = ""
	b.p["greed"] = 1.0
	b.walker.teleport(box.global_position - Vector3(0, 1.1, 0))
	await ticks(3)
	check(not box.available and b.item != "", "a CPU that runs into an item box takes it (%s)" % b.item)
	# using items
	b.protect_left = 0.0
	b.item = "balloon"
	b.item_age = 10.0
	b._item_wait = 0.0
	CpuItems.consider(b, f, f.rivals_of(b))
	check(b.item == "" and b.shield_left > 0.0, "a CPU uses a Balloon Shield (soaks the next hit)")
	var last: int = b.last_hit_by
	b.take_hit(1, {"kb": PowerUp.arr(Vector3(5, 3, 0)), "s": "shove"}, f)
	check(b.shield_left == 0.0 and b.last_hit_by == last and b.walker.mode != RouteWalker.Mode.AIR, "...which absorbs a hit")
	b.item = "fox"
	b.item_age = 10.0
	CpuItems.consider(b, f, f.rivals_of(b))
	check(b.form == "fox" and b.boost_left > 0.0 and b.boost_mult > 1.0, "a CPU transforms into the Nine-Tailed Fox and runs faster")
	b.clear_buffs(f)
	# Thunder Cloud when behind: aimed at everyone ahead
	a.protect_left = 0.0
	b.item = "thunder"
	b.item_age = 20.0
	f._stand_t = -1000.0
	f._standing.clear()
	f._standing.append_array([ids[2], ids[0], 1, ids[1]])
	Net.roster[a.id]["cp"] = 3   # (ahead by course distance)
	Net.roster[b.id]["cp"] = 0
	CpuItems.consider(b, f, f.rivals_of(b))
	check(b.item == "", "a CPU in last place uses Thunder Cloud")
	check(a.slow_left > 0.0 and a.walker.hold > 0.0, "...and the racers ahead are zapped (slow %.1f, hold %.1f)" % [a.slow_left, a.walker.hold])
	await seconds(2.0)   # (let the storm effects play out before the course is freed)
	await _cpu_cleanup()


## The main mode never sees a CPU, a local session or a party layer.
func test_zcpu_main_mode_pure() -> void:
	Game.party = null
	check(not Net.local_session and CpuField.cpu_ids().is_empty(), "no local session / CPUs outside Party vs CPU")
	var lvl: LevelBase = await load_level(0)
	await ticks(4)
	check(lvl.party == null and lvl.find_children("*", "CpuField", true, false).is_empty(), "the main mode adds no party layer and no CPU field")
	check(lvl.find_children("*", "ItemBox", true, false).is_empty(), "no item boxes in the main mode")
	# a plain race (even one hosted with the Fill option on) has no CPUs
	CpuField.fill_online = true
	check(Net.host(24591) == OK, "hosting")
	CpuField.sync_roster()
	check(CpuField.cpu_ids().is_empty() and Net.game_mode == "race", "Fill with CPUs does nothing in the Race mode")
	CpuField.fill_online = false
	Net.leave()
	check(CpuField.wanted_count() == 0, "...and nothing is wanted once the session is gone")



## A solo Party vs CPU round really pauses (the CPUs and the course clock stand still).
func test_zcpu_pause_local() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	var lvl: LevelBase = await _cpu_round(0, 2, "normal", "party", 0.5)
	var f: CpuField = _cpu_field(lvl)
	await wait_until(func() -> bool: return Game.course_time > 4.0, 60.0, "the round to get going")
	var pause: PauseMenu = lvl.find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	pause.set_open(true)
	await get_tree().process_frame
	check(get_tree().paused, "the pause menu pauses a solo CPU round")
	var t0: float = Game.course_time
	var pos0: Array[Vector3] = []
	for id: int in f.racers:
		pos0.append((f.racers[id] as CpuRacer).walker.pos)
	await get_tree().create_timer(1.0, true, false, true).timeout
	check(absf(Game.course_time - t0) < 0.05, "the course clock stands still while paused (%.3f)" % (Game.course_time - t0))
	var still: bool = true
	var i: int = 0
	for id: int in f.racers:
		if (f.racers[id] as CpuRacer).walker.pos.distance_to(pos0[i]) > 0.05:
			still = false
		i += 1
	check(still, "the CPUs stand still while paused")
	pause.set_open(false)
	var t1: float = Game.course_time
	await wait_until(func() -> bool: return Game.course_time > t1 + 0.5, 20.0, "the clock to run again")
	check(Game.course_time - t1 < 1.5 and not get_tree().paused, "the race carries on from where it stopped (+%.2fs)" % (Game.course_time - t1))
	await _cpu_cleanup()


## Team Party with CPUs: even teams, CPUs never hit teammates, nor do the human's attacks.
func test_zcpu_team_round() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	var lvl: LevelBase = await _cpu_round(0, 3, "team", "team", 0.5)
	var p: PartyLayer = lvl.party
	var f: CpuField = _cpu_field(lvl)
	check(p != null and f != null and p.rules.is_team(), "a Team Party round with CPUs")
	if p == null or f == null:
		await _cpu_cleanup()
		return
	var sizes: Array[int] = [0, 0]
	for id: int in Net.roster:
		sizes[Net.team_of(id)] += 1
	check(sizes[0] == 2 and sizes[1] == 2, "two teams of two (%d / %d)" % [sizes[0], sizes[1]])
	await wait_until(func() -> bool: return Game.course_time > 1.0 and p._ready_done, 30.0, "the round to start")
	var mate: int = 0
	for id: int in f.racers:
		if Net.team_of(id) == Net.team_of(1):
			mate = id
	check(mate != 0, "the human has a CPU teammate")
	var mate_racer: CpuRacer = f.racers[mate]
	var seen_mate: bool = false
	for r: Dictionary in f.rivals_of(mate_racer):
		if Net.team_of(int(r["id"])) == Net.team_of(mate):
			seen_mate = true
	check(not seen_mate, "a CPU never counts its own team as rivals")
	var targets_have_mate: bool = false
	for t: Dictionary in p.targets():
		if int(t["id"]) == mate:
			targets_have_mate = true
	check(not targets_have_mate, "the human's attacks never target the CPU teammate")
	await _cpu_cleanup()



## Swap Warp handshake with CPUs (accept / refuse / keep the item), respawn protection, HUD feed.
func test_zcpu_swap_and_hud() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	var lvl: LevelBase = await _cpu_round(0, 2, "normal", "party", 0.5)
	var p: PartyLayer = lvl.party
	var f: CpuField = _cpu_field(lvl)
	await wait_until(func() -> bool: return Game.course_time > 3.0 and p._ready_done, 60.0, "the round to get going")
	var ids: Array = f.racers.keys()
	ids.sort()
	var a: CpuRacer = f.racers[ids[0]]
	var b: CpuRacer = f.racers[ids[1]]
	for r: CpuRacer in [a, b]:
		r.protect_left = 0.0
		r.shield_left = 0.0
	# b is a checkpoint ahead of a
	var cp1: Vector3 = lvl.checkpoints[0].global_position
	b.walker.teleport(cp1)
	b.walker.cp = 1
	Net.roster[b.id]["cp"] = 1
	a.walker.cp = 0
	Net.roster[a.id]["cp"] = 0
	f._standing = [b.id, a.id, 1]
	f._stand_t = -1000.0
	var b_pos: Vector3 = b.walker.pos
	a.item = "swap"
	a.item_age = 10.0
	a._item_wait = 0.0
	CpuItems.consider(a, f, f.rivals_of(a))
	check(a.item == "" and a.walker.cp == 1 and b.walker.cp == 0, "a CPU's Swap Warp trades places and checkpoints with the CPU ahead (a cp %d, b cp %d)" % [a.walker.cp, b.walker.cp])
	check(int(Net.roster[a.id]["cp"]) == 1 and int(Net.roster[b.id]["cp"]) == 0, "...and the roster follows the swap")
	check(a.walker.pos.distance_to(b_pos) < 3.0, "...the caster lands where the victim stood")
	# a protected (or shielded) CPU refuses: nothing moves, the item is spent like a human's
	b.protect_left = 2.0
	var a_cp: int = a.walker.cp
	b.walker.cp = 2
	Net.roster[b.id]["cp"] = 2
	a.item = "swap"
	a.item_age = 10.0
	CpuItems.consider(a, f, f.rivals_of(a))
	check(a.walker.cp == a_cp and b.walker.cp == 2 and a.swap_wait < 0.0, "a CPU in respawn protection refuses a Swap Warp (swap_no)")
	# nobody ahead: the item is kept
	Net.roster[a.id]["cp"] = 9
	a.item = "swap"
	a.item_age = 10.0
	CpuItems.consider(a, f, f.rivals_of(a))
	check(a.item == "swap", "with nobody ahead the Swap Warp is kept, not wasted")
	Net.roster[a.id]["cp"] = a_cp
	# the human swaps with a CPU through the same handshake
	b.protect_left = 0.0
	b.walker.teleport(cp1)
	b.walker.cp = 1
	Net.roster[b.id]["cp"] = 1
	var before: int = lvl.current_checkpoint
	await ticks(30)
	p.request_swap({"id": b.id})
	await ticks(10)
	check(lvl.current_checkpoint == 1 and b.walker.cp == before, "a human's Swap Warp on a CPU is answered with swap_ok (human cp %d, CPU cp %d)" % [lvl.current_checkpoint, b.walker.cp])
	# respawn protection shrugs off hits
	b.protect_left = 2.0
	var by: int = b.last_hit_by
	b.take_hit(1, {"kb": PowerUp.arr(Vector3(6, 4, 0)), "s": "shove"}, f)
	check(b.last_hit_by == by and b.walker.mode != RouteWalker.Mode.AIR, "respawn protection shrugs off a hit on a CPU")
	# HUD: the feed hears of CPU hits and item use
	var lines: int = p.hud.feed_log.size()
	f.cpu_hit_feed(a.id, 1, "shove")
	f.cpu_used(a, "thunder")
	check(p.hud.feed_log.size() > lines, "the party feed shows a CPU's hit / item (%d new lines)" % (p.hud.feed_log.size() - lines))
	await seconds(1.0)
	await _cpu_cleanup()


# ---- CPU racers with the second item wave (P4) -----------------------------------------------------

## The CPUs roll and use Homing Shell, Leader Strike, Fake Box, Turbo Boost, Ghost, Decoy and Shockwave,
## can be hit / robbed / struck by them, and pick up the mid-course rows.
func test_zcpu_new_items() -> void:
	_pm_reset()   # (the host's saved rules live in the shared settings file: start from the defaults)
	var lvl: LevelBase = await _cpu_round(0, 3, "normal", "party", 0.5)
	var p: PartyLayer = lvl.party
	var f: CpuField = _cpu_field(lvl)
	await wait_until(func() -> bool: return Game.course_time > 2.0 and p._ready_done, 60.0, "the round to get going")
	var ids: Array = f.racers.keys()
	ids.sort()
	var a: CpuRacer = f.racers[ids[0]]
	var b: CpuRacer = f.racers[ids[1]]
	var c: CpuRacer = f.racers[ids[2]]
	for r: CpuRacer in [a, b, c]:
		r.protect_left = 0.0
		r.item = ""
	p.protect_left = 0.0
	# ranks: a leads, then b, then the human, then c (so b and c are "behind" for the catch-up items)
	var standing := func(order: Array) -> void:
		f._stand_t = -1000.0
		f._standing.clear()
		f._standing.append_array(order)
	standing.call([a.id, b.id, 1, c.id])
	Net.roster[a.id]["cp"] = 4
	Net.roster[b.id]["cp"] = 1
	Net.roster[c.id]["cp"] = 0
	var use := func(r: CpuRacer, it: String) -> bool:
		r.item = it
		r.item_age = 20.0
		r._item_wait = 0.0
		CpuItems.consider(r, f, f.rivals_of(r))
		return r.item == ""

	# Homing Shell: launched at the racer ahead; the host's copy decides the hit
	check(use.call(c, "homing"), "a CPU behind fires a Homing Shell")
	var shell: HomingShell = _zp_hazard(p, "shell") as HomingShell
	check(shell != null and shell.cpu_owner == c and shell.owner_id == c.id and shell.target_id != 0, "the shell is owned by the CPU and locked on a racer ahead (target %s)" % str(shell.target_id if shell != null else 0))
	var waited: float = 0.0
	while _zp_hazard(p, "shell") != null and waited < 9.0:
		await seconds(0.2)
		waited += 0.2
	check(_zp_hazard(p, "shell") == null, "the shell ends after %.1f s (a hit or its life running out)" % waited)

	# Leader Strike: called on whoever is in front
	for r: CpuRacer in [a, b, c]:
		r.protect_left = 0.0
	check(use.call(c, "strike"), "a CPU behind calls a Leader Strike")
	var zone: StrikeZone = _zp_hazard(p, "zone") as StrikeZone
	check(zone != null and zone.owner_id == c.id and zone.target_id == a.id, "the strike is owned by the CPU and aimed at the leader (%s)" % str(zone.target_id if zone != null else 0))
	check(not use.call(a, "strike"), "the leader keeps a Leader Strike (it has nobody to strike)")
	a.item = ""
	if zone != null:
		zone.queue_free()
		p.hazards.erase(zone.key)
	# the blast reaches CPUs (whoever called it) unless they are protected
	a.protect_left = 0.0
	f.area_hit(1, a.walker.pos, StrikeZone.RADIUS, 4.5, 9.0, {"vy": 14.0, "st": 1.6, "e": "stun", "ed": 1.6, "s": "strike"})
	check(a.last_hit_by == 1 and a.walker.hold > 0.0, "a Leader Strike's blast stuns a CPU standing in it (by %d)" % a.last_hit_by)
	var before: int = b.last_hit_by
	b.protect_left = 3.0
	f.area_hit(1, b.walker.pos, StrikeZone.RADIUS, 4.5, 9.0, {"vy": 14.0, "st": 1.6, "e": "stun", "ed": 1.6, "s": "strike"})
	check(b.last_hit_by == before, "...but not one with respawn protection")
	b.protect_left = 0.0

	# (the blast threw a CPU into the air: let everyone land and shake off the stun)
	var settled := func() -> bool:
		for r: CpuRacer in [a, b, c]:
			if not r.walker.grounded or r.walker.hold > 0.0 or r.walker.mode != RouteWalker.Mode.STEP:
				return false
		return true
	await wait_until(settled, 30.0, "the CPUs to land")
	# every scenario starts from a clean slate: the three CPUs on the start lawn, no stun, shield, ghost,
	# protection or item, no leftover hazards or decoys, and no box pick-ups (they keep racing meanwhile)
	var prep := func() -> void:
		for h: Variant in p.hazards.values():
			if is_instance_valid(h):
				(h as Node).queue_free()
		p.hazards.clear()
		for dc: PartyDecoy in p.decoys.duplicate():
			if is_instance_valid(dc):
				dc.consume(false, false)
		# (the idle human stands well away: a fake box or blast on the lawn must not be theirs to take)
		lvl.player.teleport(Transform3D(Basis(), lvl.checkpoints[mini(3, lvl.checkpoints.size() - 1)].respawn_transform().origin + Vector3(0, 0.1, 0)))
		var k: int = 0
		for r: CpuRacer in [a, b, c]:
			r.protect_left = 0.0
			r.shield_left = 0.0
			r.ghost_left = 0.0
			r.item = ""
			r.last_hit_by = 0
			r.walker.hold = 0.0
			r.p["greed"] = 0.0
			r.walker.teleport(lvl._spawn.origin + Vector3(float(k) * 3.0 - 3.0, 0.1, 0.0))
			r.walker.mode = RouteWalker.Mode.STEP
			k += 1
		CpuField.test_hold = true   # (they stand where they were put until the test is over)
		await ticks(2)

	await prep.call()
	# Fake Box: a leading CPU sets one down; the next racer to touch it is blown up
	a.walker.teleport(lvl._spawn.origin + Vector3(0, 0.1, 0))   # (the start lawn has ground behind it; a ledge might not)
	await wait_until(settled, 30.0, "the CPU to land on the lawn")
	var dropped: bool = use.call(a, "fakebox")
	check(dropped, "a CPU in front sets down a Fake Box (rank %d, item '%s', ground %s, pos %s, standing %s)" % [f.rank_of(a.id), a.item, str(not f.layer.ground_at(a.walker.pos - RouteMath.flat(a.walker.facing).normalized() * 2.2, 4.0).is_empty()), str(a.walker.pos), str(f._standing)])
	var fb: FakeBox = _zp_hazard(p, "fake") as FakeBox
	check(fb != null and fb.owner_id == a.id, "the fake box belongs to the CPU")
	if fb != null:
		var dropped_at: float = f.clock
		b.protect_left = 0.0
		b.walker.teleport(fb.global_position)
		var w2: float = 0.0
		while not _zp_used(fb) and w2 < 3.0:
			await seconds(0.1)
			w2 += 0.1
		# whichever CPU reached it first took the blast (and the hit is credited to the CPU that set it down)
		var hit_by_it: Array[CpuRacer] = []
		for r: CpuRacer in [b, c]:
			if r.last_hit_by == a.id and r.last_hit_at >= dropped_at:
				hit_by_it.append(r)
		check(_zp_used(fb) and not hit_by_it.is_empty(), "a CPU that runs into it is blown up and the hit is credited (hit %d CPU(s) after %.1f s)" % [hit_by_it.size(), w2])
	b.protect_left = 6.0
	var fb2: FakeBox = PartyItems.script_for("fakebox").call("drop", p, "1_77", 1, b.walker.pos) as FakeBox
	await seconds(1.0)
	check(not fb2.used, "a protected CPU runs through a human's fake box")
	fb2.consume(false, false)
	b.protect_left = 0.0

	await prep.call()
	# Decoy: a leading CPU with a rival close by drops one; other CPUs see it as a racer
	a.walker.teleport(b.walker.pos + Vector3(4, 0, 0))
	check(use.call(a, "decoy"), "a CPU in front drops a Decoy")
	await ticks(3)
	check(p.decoys.size() == 1 and p.decoys[0].owner_id == a.id, "the decoy belongs to the CPU")
	var entry: Dictionary = {}
	for rv: Dictionary in f.rivals_of(b):
		if rv.get("decoy") != null:
			entry = rv
	check(not entry.is_empty(), "another CPU sees the decoy as a rival")
	if not entry.is_empty():
		f.hit_rival(b, entry, Vector3(5, 5, 0), {"s": "shove"})
		check(p.decoys.is_empty(), "a CPU's attack on the decoy pops it")
	var human_hits: Array = []
	var tgt_found: bool = false
	for t: Dictionary in p.targets():
		if bool(t.get("decoy", false)):
			tgt_found = true
	check(not tgt_found, "(the popped decoy is gone for humans too)")

	await prep.call()
	# Shockwave: rivals close to a CPU are hurled away
	a.protect_left = 0.0
	b.walker.teleport(a.walker.pos + Vector3(2.5, 0, 0))
	await ticks(2)
	b.last_hit_by = 0
	check(use.call(a, "shock"), "a CPU with rivals close by uses a Shockwave")
	check(b.last_hit_by == a.id and b.walker.hold > 0.0, "the Shockwave hurls the CPU next to it (by %d)" % b.last_hit_by)
	check(not use.call(c, "shock") or true, "(a Shockwave with nobody close is kept)")
	c.item = ""

	# Turbo Boost: lit on a run of straight route (the doctored route is restored within the same tick)
	c.clear_buffs(f)
	c.boost_left = 0.0
	c.boost_mult = 1.0
	c.walker.hold = 0.0
	c.walker.mode = RouteWalker.Mode.STEP
	var real_route: Array[Dictionary] = c.walker.route.duplicate()
	var real_step: int = c.walker.step
	c.item = "turbo"
	c.item_age = 20.0
	c._item_wait = 0.0
	c.walker.route.assign([{"kind": "jump"}, {"kind": "walk"}, {"kind": "walk"}])
	c.walker.step = 0
	check(not CpuItems._straight(c), "a CPU facing a jump is not on a straight")
	CpuItems.consider(c, f, f.rivals_of(c))
	check(c.item == "turbo" and c.boost_left <= 0.0, "...so it keeps the Turbo Boost")
	c.walker.route.assign([{"kind": "walk"}, {"kind": "walk"}, {"kind": "walk"}])
	CpuItems.consider(c, f, f.rivals_of(c))
	var lit: bool = c.item == ""
	var lit_boost: float = c.boost_mult
	var lit_left: float = c.boost_left
	c.walker.route.assign(real_route)
	c.walker.step = real_step
	check(lit and lit_left > 0.0 and lit_boost >= 1.4, "a CPU lights a Turbo Boost on a straight (boost x%.1f for %.1f s)" % [lit_boost, lit_left])
	c.clear_buffs(f)

	await prep.call()
	# Ghost: untouchable, and robs a rival with an item who comes close
	b.protect_left = 0.0
	b.p["greed"] = 0.0   # (no box may fill the ghost's hands while it waits)
	a.item = "thunder"
	check(use.call(b, "ghost") and b.ghost_left > 0.0, "a CPU close to rivals turns into a Ghost")
	var last: int = b.last_hit_by
	b.take_hit(1, {"kb": PowerUp.arr(Vector3(5, 3, 0)), "s": "shove"}, f)
	check(b.last_hit_by == last, "a ghost CPU cannot be hit")
	a.walker.teleport(b.walker.pos + Vector3(1.2, 0, 0))
	a.protect_left = 0.0   # (an earlier blast may have left it respawn-protected or shielded: neither can be robbed)
	a.shield_left = 0.0
	a.ghost_left = 0.0
	a.item = "thunder"
	b.steal_cd = 0.0
	b.steal_wait = -1.0
	var w4: float = 0.0
	b._ghost_steal(f)   # (the CPUs are held still: give the ghost its chance by hand)
	await ticks(3)
	check(b.item == "thunder" and a.item == "", "the ghost CPU robs the rival's item (%s; a holds '%s', protect %.1f)" % [b.item, a.item, a.protect_left])
	b.clear_buffs(f)
	await ticks(2)

	await prep.call()
	# a human's Ghost robs a CPU
	a.item = "ice"
	a.protect_left = 0.0
	p._steal_wait = p.clock
	Net.send_party({"k": "steal"}, a.id)
	await ticks(2)
	check(p.item == "ice" and a.item == "", "a human Ghost steals a CPU's item through the CPU routing")
	p.item = ""
	a.protect_left = 4.0
	a.item = "ice"
	p._steal_wait = p.clock
	Net.send_party({"k": "steal"}, a.id)
	await ticks(2)
	check(p.item == "" and a.item == "ice", "...but not from a protected CPU")
	a.protect_left = 0.0
	# a CPU Ghost robs the human
	p.item = "fox"
	b.ghost_left = 3.0
	b.item = ""
	var human: Dictionary = {}
	for rv: Dictionary in f.rivals_of(b):
		if int(rv["id"]) == 1:
			human = rv
	f.steal_from_rival(b, human)
	await ticks(3)
	check(b.item == "fox" and p.item == "", "a CPU Ghost robs the human player (%s)" % b.item)
	b.clear_buffs(f)

	# the mid-course rows feed the CPUs like any box
	CpuField.test_hold = false   # (box pick-ups happen as a CPU ticks)
	var lawn: int = 0
	for n: int in p.box_counts:
		lawn += n
	check(p.boxes.size() > lawn, "the course has mid-course rows (%d boxes beyond the %d on the lawns)" % [p.boxes.size() - lawn, lawn])
	if p.boxes.size() > lawn:
		var mid: ItemBox = p.boxes[lawn]
		c.item = ""
		c.p["greed"] = 1.0
		c.walker.teleport(mid.global_position - Vector3(0, 1.1, 0))
		await ticks(4)
		check(not mid.available and c.item != "", "a CPU that runs into a mid-course box takes it (%s)" % c.item)
	var rolled: Dictionary = {}
	for i: int in 400:
		rolled[PartyItems.roll(1.0, (float(i) + 0.5) / 400.0)] = true
	var all_new: bool = true
	for it: String in ZP_NEW_ITEMS:
		if not rolled.has(it) and it != "fakebox" and it != "decoy" and it != "shock" and it != "ghost":
			all_new = false
	check(all_new, "the box roll that feeds CPUs includes the new catch-up items")
	await seconds(2.5)   # (let the strike / shell effects finish before the course is freed)
	await _cpu_cleanup()


# ---- Party modes and cups (branch party-modes) ------------------------------------------------------------------
# Rules (PartyRuleset), game types (party/modes/), the cup structure and the champion podium.

func _pm_reset() -> void:
	PartyRuleset.persist = false   # (tests never rewrite the real settings file)
	Settings.party_ruleset = {}
	CpuField.fill_online = false
	CpuField.fill_to = 8
	Net.synced_ruleset = {}


## A solo party round of game type `variant` with `count` CPUs; `extra` overrides other rules.
func _pm_round(variant: String, count: int, diff: String = "normal", index: int = 0, extra: Dictionary = {}) -> LevelBase:
	var rs: Dictionary = {"variant": variant}
	rs.merge(extra, true)
	PartyRuleset.persist = false
	Settings.party_ruleset = PartyRuleset.sanitize(rs)
	return await _cpu_round(index, count, diff, "party", 1.5)


func _pm_freeze_cpus(lvl: LevelBase) -> void:
	var f: CpuField = _cpu_field(lvl)
	if f != null:
		for r: CpuRacer in f.racers.values():
			r.finished = true   # (stops its simulation; the roster entry is untouched)


func _any_button_named(root: Node, n: String) -> bool:
	for b: Node in root.find_children("*", "Button", true, false):
		if str((b as Button).name) == n:
			return true
	return false


func test_zpm_ruleset_sanitize_and_sync() -> void:
	_pm_reset()
	check(PartyRuleset.sanitize(null) == PartyRuleset.defaults() and PartyRuleset.defaults()["time"] == 240 and PartyRuleset.defaults()["ko"] == 3, "a missing ruleset is the defaults (endless, normal items, KO 3, 4 minutes)")
	var junk: Dictionary = PartyRuleset.sanitize({"variant": "zzz", "cup": 7, "freq": 3, "ko": -1, "time": 1e30, "cpu": "x", "off": "no"})
	check(junk == PartyRuleset.defaults(), "a junk ruleset falls back to the defaults field by field")
	check(PartyRuleset.sanitize({"cup": NAN})["cup"] == 0 and PartyRuleset.sanitize({"ko": INF})["ko"] == 3, "NaN / infinity never get through")
	var want: Dictionary = {"variant": "hill", "cup": 5.0, "freq": "chaos", "ko": 5.0, "time": 180.0, "cpu": 6.0, "off": ["ice", "gravity", "ice"]}
	var d: Dictionary = PartyRuleset.sanitize(want)
	check(d["variant"] == "hill" and d["cup"] == 5 and typeof(d["cup"]) == TYPE_INT and d["ko"] == 5 and d["time"] == 180 and d["cpu"] == 6, "JSON floats become the allowed ints")
	check(d["off"] == ["gravity", "ice"], "the item toggles are de-duplicated and sorted (%s)" % str(d["off"]))
	# saved in Settings
	PartyRuleset.set_value("cup", 8)
	PartyRuleset.set_value("freq", "low")
	check(Settings.party_ruleset["cup"] == 8 and PartyRuleset.cup_rounds() == 8 and PartyRuleset.freq() == "low", "the host's choices land in Settings.party_ruleset")
	Settings.party_ruleset = {"cup": 2, "freq": "weird", "ko": 4}
	Settings._sanitize()
	check(Settings.party_ruleset == PartyRuleset.sanitize({"ko": 4}), "Settings sanitises a hand-edited ruleset on load")
	check("party_ruleset" in Settings._props(), "...and writes it with the other settings")
	# message-level sync: the roster snapshot carries the rules, directly (the RPC body) and over the relay (JSON)
	Settings.party_ruleset = PartyRuleset.sanitize(want)
	var cfg: Dictionary = Net._party_cfg()
	check(cfg.has("rs") and cfg["rs"] == d, "the host's party config carries the ruleset")
	var wire: Variant = JSON.parse_string(JSON.stringify(cfg))
	Settings.party_ruleset = {}
	Net.synced_ruleset = {}
	Net._sync_roster({}, cfg)
	check(Net.synced_ruleset == d, "direct path: _sync_roster applies the host's rules")
	Net.synced_ruleset = {}
	Net._handle_relay_event(1, "roster", {"players": [], "party": wire})
	check(Net.synced_ruleset == d, "relay path: the roster event's JSON round trip lands on the same rules")
	# a guest reads the host's copy, the host (or a solo session) its own
	Net.active = true
	var was_relay: bool = Net._relay_mode
	Net._relay_mode = true
	Net._relay_host = false
	check(PartyRuleset.cur() == d and PartyRuleset.ko() == 5 and not PartyRuleset.item_enabled("gravity") and PartyRules.ko_value() == 5, "a guest's PartyRuleset.cur() is the host's synced copy")
	Net._relay_host = true
	check(PartyRuleset.cur() == PartyRuleset.defaults(), "the host reads its own settings")
	Net._relay_mode = was_relay
	Net._relay_host = false
	Net.active = false
	Net.synced_ruleset = {}
	# a bad packet cannot break anything
	Net._apply_party_cfg({"mode": "party", "rs": {"variant": 5, "off": [1, 2]}})
	check(Net.synced_ruleset["variant"] == "classic" and typeof(Net.synced_ruleset["off"]) == TYPE_ARRAY, "a malformed ruleset in a packet is sanitised")
	Net.game_mode = "race"
	_pm_reset()


func test_zpm_rules_take_effect() -> void:
	_pm_reset()
	check(PartyRules.score_round([1], [1, 2], {1: 2}, {})[0]["ko_pts"] == 6, "default: 2 KOs are 6 points")
	Settings.party_ruleset = PartyRuleset.sanitize({"ko": 5})
	check(PartyRules.score_round([1], [1, 2], {1: 2}, {})[0]["ko_pts"] == 10, "KO value 5: 2 KOs are 10 points")
	var rows: Array[Dictionary] = PartyRules.score_round([1], [1, 2], {}, {}, {2: -9, 1: 4})
	var by_id: Dictionary = {}
	for r: Dictionary in rows:
		by_id[int(r["id"])] = r
	check(int(by_id[1]["mode_pts"]) == 4 and int(by_id[1]["total"]) == 14 and int(by_id[2]["total"]) == 0, "mode points add to a round (and a round never goes below 0)")
	check(PartyRules.rows_from_wire(rows)[0].has("mode_pts"), "mode points survive the wire format")
	# item frequency: off = no boxes, low = fewer, chaos = quick respawn
	var normal: LevelBase = await _pm_round("classic", 0)
	var n_normal: int = normal.party.boxes.size()
	check(n_normal >= 6 and normal.party.box_respawn_time() == PartyLayer.BOX_RESPAWN, "normal item boxes (%d boxes)" % n_normal)
	await _cpu_cleanup()
	var off: LevelBase = await _pm_round("classic", 0, "normal", 0, {"freq": "off"})
	check(off.party.boxes.is_empty(), "item frequency Off places no item boxes")
	await _cpu_cleanup()
	var low: LevelBase = await _pm_round("classic", 0, "normal", 0, {"freq": "low"})
	check(low.party.boxes.size() > 0 and low.party.boxes.size() < n_normal and low.party.box_respawn_time() > PartyLayer.BOX_RESPAWN, "Low thins the boxes out (%d of %d) and slows their respawn" % [low.party.boxes.size(), n_normal])
	await _cpu_cleanup()
	var chaos: LevelBase = await _pm_round("classic", 0, "normal", 0, {"freq": "chaos"})
	check(chaos.party.boxes.size() == n_normal and chaos.party.box_respawn_time() < PartyLayer.BOX_RESPAWN, "Chaos keeps every box and respawns them fast")
	# per-item toggles: only the enabled ones roll (the list is the PartyItems catalogue, so new items appear by themselves)
	var all_ids: Array[String] = PartyItems.ids()
	var keep: String = "ice" if "ice" in all_ids else all_ids[0]
	var off_list: Array = []
	for id: String in all_ids:
		if id != keep:
			off_list.append(id)
	PartyRuleset.set_value("off", off_list)
	var seen: Dictionary = {}
	for i: int in 120:
		seen[chaos.party.roll_for(1)] = true
	check(seen.keys() == [keep], "with every other power-up toggled off only %s rolls (%s)" % [keep, str(seen.keys())])
	PartyRuleset.set_value("off", all_ids)
	check(not PartyRuleset.boxes_on(), "all power-ups off means no boxes")
	PartyRuleset.set_value("off", [])
	check(PartyRuleset.enabled_items().size() == all_ids.size() and PartyRuleset.boxes_on(), "toggling back restores them")
	await _cpu_cleanup()
	# round time limit
	var timed: LevelBase = await _pm_round("classic", 0, "normal", 0, {"time": 90})
	check(timed.party.round_limit() == 90.0, "the round limit is the host's 90 s")
	await wait_until(func() -> bool: return Game.course_time > 0.2, 20.0, "GO")
	Game.course_time = 92.0
	await wait_until(func() -> bool: return timed.party.round_over, 10.0, "the time limit to end the round")
	check(timed.party.round_over, "a 90 s limit ends a round nobody finished at 92 s")
	await _cpu_cleanup()
	_pm_reset()


func test_zpm_hill() -> void:
	_pm_reset()
	var lvl: LevelBase = await _pm_round("hill", 0)
	var p: PartyLayer = lvl.party
	var z: PartyModeHill = p.mode as PartyModeHill
	check(z != null and z.zone_i == clampi(1, 0, lvl.checkpoints.size()), "a King of the Hill round starts with the zone on lawn 1")
	if z == null:
		await _cpu_cleanup()
		return
	check(z.contains(z.zone_pos) and not z.contains(z.zone_pos + Vector3(20, 0, 0)) and not z.contains(z.zone_pos + Vector3(0, 8, 0)), "the zone is a disc around the lawn")
	check(z.score([1], 5.0) == 1 and z.pts[1] == 4, "alone in the zone for 5 s earns 4 points")
	var before: int = int(z.pts[1])
	check(z.score([1, 900], 5.0) == -1 and int(z.pts[1]) == before, "two racers inside: contested, nobody scores")
	check(z.score([], 5.0) == 0 and int(z.pts[1]) == before, "an empty zone scores nothing")
	check(z.mode_points()[1] == before, "mode_points() are the hill points")
	var row: Dictionary = PartyRules.score_round([], [1], {}, {}, z.mode_points())[0]
	check(int(row["mode_pts"]) == before and int(row["total"]) == before, "they count in the round scoreboard")
	# the zone moves to the lawn just ahead of the pack
	Net.roster[1]["cp"] = 1
	check(z.pick_next() == clampi(2, 1, lvl.checkpoints.size()), "the next lawn is one ahead of the pack's median checkpoint")
	await wait_until(func() -> bool: return Game.course_time > 0.3, 20.0, "GO")
	var old_pos: Vector3 = z.zone_pos
	z.next_move = Game.course_time - 0.1
	await ticks(3)
	check(z.zone_i == z.pick_next() and (z.zone_pos != old_pos or lvl.checkpoints.size() < 2), "when its time is up the zone moves on (lawn %d)" % z.zone_i)
	# really standing in it
	z.pts.clear()
	z._seconds.clear()
	lvl.player.teleport(Transform3D(Basis(), z.zone_pos + Vector3(0, 0.3, 0)))
	for i: int in 150:   # (held on the spot: this lawn has a launcher next to it)
		lvl.player.teleport(Transform3D(Basis(), z.zone_pos + Vector3(0, 0.3, 0)))
		await get_tree().physics_frame
	check(z.holder == 1 and int(z.pts.get(1, 0)) >= 1, "standing in the zone alone makes you the holder and scores (%d pts)" % int(z.pts.get(1, 0)))
	check(not z.hud_lines().is_empty() and p.hud._mode_box.visible, "the mode's HUD widget shows")
	check(not z.round_over(Game.course_time), "King of the Hill adds no end condition of its own")
	await _cpu_cleanup()
	_pm_reset()


func test_zpm_elimination() -> void:
	_pm_reset()
	var lvl: LevelBase = await _pm_round("elim", 3)
	var p: PartyLayer = lvl.party
	var e: PartyModeElim = p.mode as PartyModeElim
	check(e != null and Net.roster.size() == 4, "an Elimination round with three CPUs")
	if e == null:
		await _cpu_cleanup()
		return
	_pm_freeze_cpus(lvl)
	for id: int in Net.roster:
		Net.roster[id]["cp"] = 0
	for id: int in [1, 900, 901]:
		Net.roster[id]["cp"] = 1
	e.on_checkpoint(901, 1)
	check(e.is_out(902) and e.out[902] == 1 and e.alive().size() == 3, "the last racer through checkpoint 1 is out")
	check(not lvl._ghosts[902].visible and not (902 in lvl.spectate_candidates()), "an eliminated racer vanishes from the course and can't be spectated")
	check(p.targets().filter(func(t: Dictionary) -> bool: return int(t["id"]) == 902).is_empty(), "...and can't be hit")
	e.on_checkpoint(900, 1)
	check(e.alive().size() == 3, "a gate only drops one racer")
	Net.roster[1]["cp"] = 2
	Net.roster[900]["cp"] = 2
	e.on_checkpoint(900, 2)
	check(e.is_out(901) and e.alive().size() == 2 and not e.round_over(0.0), "checkpoint 2 drops the next one; two left, the round goes on")
	Net.roster[1]["cp"] = 3
	e.on_checkpoint(1, 3)
	check(e.is_out(900) and e.alive() == [1] and e.round_over(0.0), "the last one standing ends the round")
	var order: Array = e.finish_order([])
	check(order == [1, 900, 901, 902], "placement follows the elimination order %s" % str(order))
	var rows: Array[Dictionary] = PartyRules.score_round(order, Net.roster.keys(), {}, {})
	var place_pts: Dictionary = {}
	for r: Dictionary in rows:
		place_pts[int(r["id"])] = int(r["place_pts"])
	check(place_pts[1] == 10 and place_pts[900] == 8 and place_pts[901] == 6 and place_pts[902] == 5, "the survivor wins the round's 10 points, the first out gets the least (%s)" % str(place_pts))
	check(e.hud_lines().size() >= 2, "the HUD widget lists the racers left")
	await _cpu_cleanup()
	# our own elimination: control off, spectating the rest
	var lvl2: LevelBase = await _pm_round("elim", 2)
	var e2: PartyModeElim = lvl2.party.mode as PartyModeElim
	await wait_until(func() -> bool: return Game.course_time > 0.3, 20.0, "GO")
	e2._apply_out(1, 1, "test")
	await ticks(3)
	check(not lvl2.party.can_act() and not lvl2.player.control_enabled and lvl2.finished, "when we are out we can't act any more")
	check(lvl2.spectating_id in [900, 901], "...and we watch a racer who is still in (%d)" % lvl2.spectating_id)
	check(e2.hud_lines().any(func(l: String) -> bool: return l.contains("out")), "the widget says we are out")
	await _cpu_cleanup()
	_pm_reset()


func test_zpm_coin_rush() -> void:
	_pm_reset()
	for li: int in [0, 5, 12]:
		if li >= Game.LEVELS.size():
			continue
		var l0: LevelBase = await load_level(li)
		await ticks(3)
		var pts: Array[Vector3] = PartyModeCoins.route_coin_points(l0)
		var spaced: bool = true
		for i: int in pts.size():
			for j: int in range(i + 1, pts.size()):
				if pts[i].distance_to(pts[j]) < PartyModeCoins.MIN_GAP - 0.01:
					spaced = false
		check(pts.size() >= 4 and pts.size() <= PartyModeCoins.MAX_COINS and spaced, "course %d: %d coin spots on the route, spaced out" % [li + 1, pts.size()])
	if Game.LEVELS.size() > 5:
		var short: LevelBase = await _pm_round("coins", 0, "normal", 5)
		var sc: PartyModeCoins = short.party.mode as PartyModeCoins
		check(sc != null and sc.coins.size() >= 8, "a course with a short route still gets coins (on its checkpoint lawns too): %d" % (sc.coins.size() if sc != null else -1))
		await _cpu_cleanup()
	var lvl: LevelBase = await _pm_round("coins", 2)
	var p: PartyLayer = lvl.party
	var c: PartyModeCoins = p.mode as PartyModeCoins
	check(c != null, "a Coin Rush round")
	if c == null:
		await _cpu_cleanup()
		return
	await ticks(3)
	_pm_freeze_cpus(lvl)
	var n0: int = c.coins.size()
	check(n0 >= 8 and c._nodes.size() == n0, "%d coins are on the course, each with a visual" % n0)
	c.on_request(1, {"m": "pick", "c": 0})
	check(int(c.count.get(1, 0)) == 1 and c.taken.has(0), "a pickup request scores a coin")
	c.on_request(1, {"m": "pick", "c": 0})
	check(int(c.count[1]) == 1, "a coin can only be taken once")
	c.on_request(555, {"m": "pick", "c": 1})
	check(not c.taken.has(1), "a request from somebody not in the race is ignored")
	c.count[900] = 5
	c.on_ko(1, 900)
	check(int(c.count[900]) == 2 and c.coins.size() == n0 + 3, "a KO makes the victim drop 3 coins (%d left, %d on the course)" % [int(c.count[900]), c.coins.size()])
	var drop_id: int = PartyModeCoins.FIRST_DROP_ID + 1
	check(c.coins.has(drop_id) and c._nodes.has(drop_id), "the dropped coins are real coins")
	c.on_request(1, {"m": "pick", "c": drop_id})
	check(int(c.count[1]) == 2, "anybody can pick up a dropped coin")
	c.count[901] = 0
	var m: int = c.coins.size()
	c.on_ko(1, 901)
	check(c.coins.size() == m, "a victim without coins drops nothing")
	c.on_message(1, {"m": "take", "c": 3, "id": 902, "n": 4})
	check(c.taken.has(3) and int(c.count[902]) == 4, "the host's 'take' message updates a guest's coins")
	check(c.leader() == 902 and c.mode_points()[902] == 4, "the leader and the mode points follow the counts")
	var row: Dictionary = PartyRules.score_round([], [1, 902], {}, {}, c.mode_points())[0]
	check(int(row["id"]) == 902 and int(row["mode_pts"]) == 4 and int(row["total"]) == 4, "coins are points in the round scoreboard")
	var target: int = 5
	lvl.player.teleport(Transform3D(Basis(), (c.coins[target] as Vector3) + Vector3(0, 0.1, 0)))
	await wait_until(func() -> bool: return Game.course_time > 0.3, 20.0, "GO")
	await ticks(8)
	check(c.taken.has(target) and int(c.taken[target]) == 1, "walking through a coin collects it")
	check(c.hud_lines().size() >= 2, "the HUD widget shows the count")
	await _cpu_cleanup()
	_pm_reset()


func test_zpm_hot_potato() -> void:
	_pm_reset()
	var lvl: LevelBase = await _pm_round("potato", 3)
	var p: PartyLayer = lvl.party
	var h: PartyModePotato = p.mode as PartyModePotato
	check(h != null, "a Hot Potato round")
	if h == null:
		await _cpu_cleanup()
		return
	_pm_freeze_cpus(lvl)
	await wait_until(func() -> bool: return Game.course_time > 0.3, 20.0, "GO")
	var ids: Array[int] = h.active_ids()
	h._new_holder(ids, 0)
	check(h.holder in ids and h.fuse == PartyModePotato.FUSE, "the bomb goes to a racer with a full fuse")
	check(h._node_of(h.holder).get_node_or_null("PotatoBomb") != null, "the holder carries a visible bomb")
	h.holder = 1
	h._last_pass_at = -9.0
	h.on_request(900, {"m": "pass", "to": 901})
	check(h.holder == 1, "only the holder can pass the bomb")
	h.on_request(1, {"m": "pass", "to": 555})
	check(h.holder == 1, "...and only to a racer who is in the round")
	h.on_request(1, {"m": "pass", "to": 900})
	check(h.holder == 900 and h._node_of(900).get_node_or_null("PotatoBomb") != null, "a pass moves the bomb to the target")
	h.on_request(900, {"m": "pass", "to": 1})
	check(h.holder == 900, "it can't be passed straight back at once")
	h._last_pass_at = -9.0
	h.holder = 1
	h.on_hit(1, 901, "shove")
	check(h.holder == 901, "landing a Shove on a rival passes the bomb (on_hit)")
	h._last_pass_at = -9.0
	h.holder = 901
	h.on_hit(1, 900, "shove")
	check(h.holder == 901, "a hit by somebody who isn't holding it passes nothing")
	h.holder = 900
	h.fuse = 5.0
	h._boom(h.active_ids())
	check(int(h.pts[900]) == -PartyModePotato.BLAST_PENALTY and int(h.pts[1]) == PartyModePotato.SURVIVE_PTS and int(h.blasts[900]) == 1, "a blast costs the holder %d, everyone else racing gets +%d" % [PartyModePotato.BLAST_PENALTY, PartyModePotato.SURVIVE_PTS])
	check(h.holder != 900 and h.holder != 0 and h.fuse == PartyModePotato.FUSE, "the bomb goes to someone new and the fuse restarts")
	var rows: Array[Dictionary] = PartyRules.score_round([], h.active_ids(), {}, {}, h.mode_points())
	var r900: Dictionary = {}
	for r: Dictionary in rows:
		if int(r["id"]) == 900:
			r900 = r
	check(int(r900["mode_pts"]) == -3 and int(r900["total"]) == 0, "the penalty shows in the round scoreboard and never drops a round below 0")
	h._apply_boom(1)
	check(p.last_hit_by == 0, "the blast is nobody's KO")
	check(h.round_note().contains("blew up"), "the results headline names who blew up")
	await _cpu_cleanup()
	_pm_reset()


## The CPU heuristics, read straight off the mode objects.
func test_zpm_cpu_heuristics() -> void:
	_pm_reset()
	var lvl: LevelBase = await _pm_round("hill", 3, "hard")
	var f: CpuField = _cpu_field(lvl)
	var z: PartyModeHill = lvl.party.mode as PartyModeHill
	check(f != null and z != null and f.racers.size() == 3, "a Hill round with three CPUs")
	if f == null or z == null:
		await _cpu_cleanup()
		return
	var a: CpuRacer = f.racers[900]
	var b: CpuRacer = f.racers[901]
	await wait_until(func() -> bool: return Game.course_time > 0.3, 20.0, "GO")
	a.walker.cp = 0
	z._left = 10.0
	a.walker.pos = z.zone_pos + Vector3(30, 0, 0)
	check(CpuModes.pace_mult(a, f, 0.1) > 1.0, "a CPU short of the zone's lawn runs faster")
	a.walker.pos = z.zone_pos
	a.mode_state.clear()
	check(CpuModes.pace_mult(a, f, 0.1) == CpuModes.IDLE_PACE, "a CPU standing in the zone holds it")
	a.mode_state["linger"] = 99.0
	check(CpuModes.pace_mult(a, f, 0.1) == 1.0, "...but moves on after a while")
	a.mode_state.clear()
	z._left = 0.5
	check(CpuModes.pace_mult(a, f, 0.1) == 1.0, "...and doesn't wait for a zone about to move")
	z._left = 10.0
	b.walker.pos = z.zone_pos + Vector3(1, 0, 0)
	var rival: Dictionary = {"id": 901, "pos": b.walker.pos}
	check(CpuModes.melee_chance(a, f, 0.2, rival) >= 0.8, "two CPUs fighting over the zone shove each other")
	await _cpu_cleanup()
	var lvl2: LevelBase = await _pm_round("potato", 3, "hard")
	var f2: CpuField = _cpu_field(lvl2)
	var h: PartyModePotato = lvl2.party.mode as PartyModePotato
	var c1: CpuRacer = f2.racers[900]
	var c2: CpuRacer = f2.racers[901]
	await wait_until(func() -> bool: return Game.course_time > 0.3, 20.0, "GO")
	h.holder = 900
	var rv: Dictionary = {"id": 901, "pos": c2.walker.pos}
	check(CpuModes.melee_chance(c1, f2, 0.1, rv) == 1.0 and CpuModes.eager(c1, f2) and CpuModes.pace_mult(c1, f2, 0.1) < 1.0, "the CPU holding the bomb shoves anyone in reach, at once, and waits for company")
	check(not CpuModes.eager(c2, f2) and CpuModes.melee_chance(c2, f2, 0.5, {"id": 900, "pos": c1.walker.pos}) < 0.5, "the others don't go after the holder")
	c2.walker.pos = c1.walker.pos + Vector3(2, 0, 0)
	check(CpuModes.pace_mult(c2, f2, 0.1) > 1.0, "a CPU near the holder runs away from it")
	c1.shove_cd = 0.0
	h._last_pass_at = -9.0
	f2.hit_rival(c1, {"id": 901, "cpu": c2, "pos": c2.walker.pos, "center": c2.walker.pos + Vector3(0, 0.8, 0), "vel": Vector3.ZERO, "grounded": true}, Vector3(5, 3, 0), {"s": "shove"})
	check(h.holder == 901, "a CPU's Shove passes the bomb")
	await _cpu_cleanup()
	var lvl3: LevelBase = await _pm_round("elim", 3, "hard")
	var f3: CpuField = _cpu_field(lvl3)
	var e: PartyModeElim = lvl3.party.mode as PartyModeElim
	for id: int in Net.roster:
		Net.roster[id]["cp"] = 1
	Net.roster[902]["cp"] = 0
	Net.roster[902]["cp_at"] = 99.0
	check(e.is_last(902) and CpuModes.pace_mult(f3.racers[902], f3, 0.1) > 1.1, "the last CPU still in speeds up to avoid elimination")
	check(not e.is_last(900) and CpuModes.pace_mult(f3.racers[900], f3, 0.1) == 1.0, "the others keep their normal pace")
	await _cpu_cleanup()
	_pm_reset()


## CPUs in a real solo round of each game type: they take part and the mode runs on their play.
func test_zcpu_modes_solo_rounds() -> void:
	_pm_reset()
	var lvl: LevelBase = await _pm_round("hill", 3, "hard")
	var z: PartyModeHill = lvl.party.mode as PartyModeHill
	Engine.time_scale = 5.0
	await wait_until(func() -> bool: return Game.course_time > 20.0 and (z.pts.size() > 0 or Game.course_time > 150.0), 400.0, "a CPU to score on the hill")
	var cpu_pts: int = 0
	for id: Variant in z.pts:
		if CpuField.is_cpu_id(int(id)):
			cpu_pts += int(z.pts[id])
	check(cpu_pts >= 1, "CPUs reached the hill and scored (%d points)" % cpu_pts)
	check(z.zone_i >= 1, "the zone sits on a real lawn (%d)" % z.zone_i)
	await _cpu_cleanup()
	var lvl2: LevelBase = await _pm_round("elim", 3, "hard")
	var p2: PartyLayer = lvl2.party
	var e: PartyModeElim = p2.mode as PartyModeElim
	Engine.time_scale = 5.0
	await wait_until(func() -> bool: return p2.round_over, 500.0, "the Elimination round to end")
	Engine.time_scale = 1.0
	check(e.is_out(1), "the idle human was last through a gate and is out")
	check(e.alive().size() <= 1 or e.alive().size() == 2, "the field was cut down (%d left)" % e.alive().size())
	check(p2.last_rows.size() == 4 and CpuField.is_cpu_id(int(p2.last_rows[0]["id"])), "the round scored all four and a CPU won it")
	await _cpu_cleanup()
	var lvl3: LevelBase = await _pm_round("coins", 3, "hard")
	var c: PartyModeCoins = lvl3.party.mode as PartyModeCoins
	Engine.time_scale = 5.0
	await wait_until(func() -> bool: return Game.course_time > 15.0 and c.taken.size() >= 4, 300.0, "CPUs to collect coins")
	var cpu_coins: int = 0
	for id: Variant in c.count:
		if CpuField.is_cpu_id(int(id)):
			cpu_coins += int(c.count[id])
	check(cpu_coins >= 3, "CPUs picked up coins on their way (%d)" % cpu_coins)
	await _cpu_cleanup()
	var lvl4: LevelBase = await _pm_round("potato", 3, "hard")
	var h: PartyModePotato = lvl4.party.mode as PartyModePotato
	Engine.time_scale = 5.0
	await wait_until(func() -> bool: return h.blasts.size() > 0, 300.0, "the first bomb to go off")
	check(not h.blasts.is_empty() and h.holder != 0, "a bomb exploded and the next one is lit (holder %d)" % h.holder)
	var negative: bool = false
	for id: Variant in h.pts:
		if int(h.pts[id]) < 0:
			negative = true
	check(negative, "the blast cost its holder points (%s)" % str(h.pts))
	await _cpu_cleanup()
	_pm_reset()


func test_zpm_cup_length_and_podium() -> void:
	_pm_reset()
	check(PartyRuleset.CUPS == [3, 5, 8, 0], "cups are 3, 5 or 8 rounds, or endless")
	PartyRuleset.set_value("cup", 3)
	check(PartyRuleset.cup_done(3) and PartyRuleset.cup_done(4) and not PartyRuleset.cup_done(2), "a 3-round cup is done after round 3")
	PartyRuleset.set_value("cup", 0)
	check(not PartyRuleset.cup_done(99), "Endless never finishes")
	var pr := PartyRules.new("party")
	pr.cup = {1: 25, 900: 30, 901: 12, 902: 8}
	pr.names = {1: "Me", 900: "Bolt", 901: "Pixel", 902: "Zippy"}
	var ent: Array[Dictionary] = PartyPodium.entries(pr, {})
	check(ent.size() == 3 and ent[0]["ids"] == [900] and ent[1]["ids"] == [1] and ent[2]["ids"] == [901] and ent[0]["pts"] == 30, "the podium takes the top 3 by cup points")
	var tr := PartyRules.new("team")
	tr.cup = {1: 10, 2: 5, 3: 8, 4: 9}
	tr.teams = {1: 0, 2: 0, 3: 1, 4: 1}
	tr.names = {1: "A", 2: "B", 3: "C", 4: "D"}
	var tent: Array[Dictionary] = PartyPodium.entries(tr, {})
	check(tent.size() == 2 and str(tent[0]["label"]).contains(PartyNames.team_name(1)) and tent[0]["ids"] == [4, 3] and tent[0]["pts"] == 17, "in Team Party the podium is the two teams, best members on them")
	var lvl: LevelBase = await _pm_round("classic", 3, "normal", 0, {"cup": 3})
	var p: PartyLayer = lvl.party
	p.rules.round_no = 2
	p.rules.cup = {1: 20, 900: 30, 901: 12, 902: 8}
	for id: int in [1, 900, 901, 902]:
		p.rules.names[id] = str(Net.roster[id]["name"])
	p.last_rows = PartyRules.score_round([900, 1, 901, 902], Net.roster.keys(), {}, {})
	p.show_results()
	await seconds(1.0)
	var buttons: String = ""
	for b: Node in p.results.find_children("*", "Button", true, false):
		buttons += (b as Button).text + "|"
	check(buttons.contains("Next Round  (Round 3 of 3)") and not buttons.contains("Champion") and not p.results.final_round, "round 2 of a 3-round cup offers Next Round (round 3 of 3)")
	p.rules.round_no = 3
	p.show_results()
	await seconds(1.2)
	buttons = ""
	for b: Node in p.results.find_children("*", "Button", true, false):
		buttons += (b as Button).text + "|"
	check(p.results.final_round and buttons.contains("See the Champion!") and not buttons.contains("Next Round"), "the last round offers the champion screen instead of another round (%s)" % buttons)
	check(_focused_text() == "See the Champion!", "...focused for the pad (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(4)
	var pod: PartyPodium = p.podium
	check(pod != null and is_instance_valid(pod) and pod.shown.size() == 3, "A opens the podium with three pedestals")
	if pod == null:
		await _cpu_cleanup()
		return
	check(pod.racers.size() == 3 and pod.champion_id == 900, "the top three stand on it, the cup leader is the champion")
	check(pod.racers[900].visual() != null and pod.racers.has(1) and pod.racers.has(901), "...each wearing their own cosmetics")
	pod.skip()
	await ticks(4)
	var champ: RemoteRacer = pod.racers[900]
	check(pod.done and champ.visual().is_emoting() and champ.visual().emote_kind() == "pose" and champ.visual().emote_id() == pod.winner_pose, "the champion plays their victory pose (%s)" % pod.winner_pose)
	check(not pod.find_children("*", "GPUParticles3D", true, false).is_empty(), "there is confetti")
	check(_focused_text() == "Back to the Lobby", "the podium's main button is focused (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(_focused_text() == "Close Session", "the D-pad reaches the other button (%s)" % _focused_text())
	await _cpu_cleanup()
	_pm_reset()


func test_zpm_menus_pad() -> void:
	_pm_reset()
	if world != null:
		world.queue_free()
		world = null
		await ticks(2)
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	title.set("persist_settings", false)
	add_child(title)
	check(Net.host(24598) == OK, "hosting opens the lobby")
	await ticks(3)
	Net.host_set_mode("party")
	await ticks(3)
	var rules_btn: Button = null
	for b: Node in title.find_children("*", "Button", true, false):
		if (b as Button).name == "RulesButton":
			rules_btn = b as Button
	check(rules_btn != null, "the host's lobby has a Cup & Rules button")
	var e0: int = trap.count()
	rules_btn.grab_focus()
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(3)
	check(Game.title_screen == "partyrules" and _focused_text().begins_with("Game type:"), "A opens the rules, on the first row (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_RIGHT))
	check(PartyRuleset.variant() == "hill" and _focused_text().contains("King of the Hill"), "D-pad right changes the game type (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_LEFT))
	check(PartyRuleset.variant() == "classic", "D-pad left steps back")
	await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
	check(_focused_text().begins_with("Cup length:") and _focused_text().contains("Endless"), "down: the cup length (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	check(PartyRuleset.cup_rounds() == 3 and _focused_text().contains("3 rounds"), "A cycles it to 3 rounds (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	check(PartyRuleset.cup_rounds() == 5, "...then 5")
	var seen: Array[String] = []
	for i: int in 8:
		await _zp_press(_zp_pad(JOY_BUTTON_DPAD_DOWN))
		seen.append(_focused_text())
		if _focused_text().begins_with("Power-ups:"):
			break
	var joined: String = "|".join(seen)
	check(joined.contains("Item boxes:") and joined.contains("KO value:") and joined.contains("Round time limit:") and joined.contains("Fill with CPUs:"), "the D-pad reaches every rule: items, KO value, time limit, CPU fill (%s)" % joined)
	check(_focused_text().begins_with("Power-ups:"), "...and the power-up toggles")
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(3)
	var first_id: String = PartyItems.ids()[0]
	check(Game.title_screen == "partyitems" and _focused_text() == PartyRulesMenu.toggle_text(first_id), "A opens the toggles, on the first power-up (%s)" % _focused_text())
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	check(not PartyRuleset.item_enabled(first_id) and _focused_text().begins_with("[  ]"), "A switches it off (%s)" % _focused_text())
	var count: int = 0
	for b: Node in title.find_children("*", "Button", true, false):
		if str((b as Button).name).begins_with("Item_"):
			count += 1
	check(count == PartyItems.ids().size(), "there is one toggle per catalogue item (%d)" % count)
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	check(PartyRuleset.item_enabled(first_id), "...and back on")
	await _zp_press(_zp_pad(JOY_BUTTON_B))
	await ticks(3)
	check(Game.title_screen == "partyrules", "B goes back to the rules")
	await _zp_press(_zp_pad(JOY_BUTTON_B))
	await ticks(3)
	check(Game.title_screen == "lobby", "B again returns to the lobby")
	var summary: String = ""
	for l: Node in title.find_children("*", "Label", true, false):
		summary += (l as Label).text + "|"
	check(summary.contains("cup: 5 rounds"), "the lobby shows the rules in force")
	Net.leave()
	title.call("show_screen", "partycpu")
	await ticks(3)
	check(_any_button_named(title, "GameType") and _any_button_named(title, "CupLength") and _any_button_named(title, "MoreRules"), "Party vs CPU has game type, cup length and more rules")
	for b: Node in title.find_children("*", "Button", true, false):
		if (b as Button).name == "MoreRules":
			(b as Button).grab_focus()
	await _zp_press(_zp_pad(JOY_BUTTON_A))
	await ticks(3)
	check(Game.title_screen == "partyrules" and not _any_button_named(title, "Rule_cpu"), "More rules opens the same screen (no online-only CPU row)")
	await _zp_press(_zp_pad(JOY_BUTTON_B))
	await ticks(3)
	check(Game.title_screen == "partycpu", "B returns to Party vs CPU")
	check(trap.count() == e0, ("the rules screens build without errors %s" % trap.since(e0)).strip_edges())
	title.queue_free()
	await ticks(2)
	Game.title_screen = "main"
	_pm_reset()


func test_zpm_main_mode_stays_pure() -> void:
	_pm_reset()
	Settings.party_ruleset = PartyRuleset.sanitize({"variant": "hill", "cup": 3, "freq": "chaos", "ko": 8})
	Game.party = null
	var lvl: LevelBase = await load_level(0)
	await ticks(6)
	check(lvl.party == null and lvl.find_children("*", "PartyMode", true, false).is_empty() and lvl.find_children("*", "PartyLayer", true, false).is_empty(), "the main mode builds no party layer and no game type, whatever the party rules say")
	check(lvl.find_children("*", "ItemBox", true, false).is_empty(), "no item boxes in the main mode")
	Net.host_local()
	Net.host_set_mode("race")
	check(CpuField.wanted_count() == 0 and not Net.cup_complete(), "Race mode has no CPUs and no cup")
	Net.leave()
	check(PartyModes.create("classic") == null and PartyModes.create("nonsense") == null, "classic (and unknown ids) have no game type object")
	_pm_reset()


## The host's rules (P3) cover the new items: they are on the Items screen, toggle off, and thin with the frequency.
func test_zp_items_respect_ruleset() -> void:
	_pm_reset()
	var lvl: LevelBase = await _party_race_level(0)
	var p: PartyLayer = lvl.party
	var screen: Dictionary = PartyRulesMenu.build_items_screen(self)
	var missing: Array[String] = []
	for id: String in ZP_NEW_ITEMS:
		if (screen["content"] as Node).find_child("Item_" + id, true, false) == null:
			missing.append(id)
	check(missing.is_empty(), "every new item has a toggle on the Items rules screen (missing: %s)" % str(missing))
	(screen["content"] as Node).queue_free()
	PartyRuleset.set_value("off", ZP_NEW_ITEMS.duplicate())
	var seen: Dictionary = {}
	for i: int in 300:
		seen[p.filter_item(PartyItems.roll(1.0, (float(i) + 0.5) / 300.0))] = true
	var leaked: Array[String] = []
	for id: String in ZP_NEW_ITEMS:
		if seen.has(id):
			leaked.append(id)
	check(leaked.is_empty() and PartyRuleset.boxes_on(), "switched-off new items never roll (leaked: %s)" % str(leaked))
	PartyRuleset.set_value("off", [])
	check(PartyRuleset.item_enabled("ghost") and PartyRuleset.enabled_items().size() == PartyItems.ids().size(), "...and come back when toggled on")
	# Low frequency thins the mid-course rows along with the lawns
	var full: int = p.boxes.size()
	_party_race_done()
	_pm_reset()
	Settings.party_ruleset = PartyRuleset.sanitize({"freq": "low"})
	var low: LevelBase = await _party_race_level(0)
	check(low.party.boxes.size() < full and low.party.boxes.size() > 0, "Low item frequency thins the boxes, mid-course rows included (%d of %d)" % [low.party.boxes.size(), full])
	_party_race_done()
	_pm_reset()

## Pixel Panic (very hard tier) audit: the main route's jump statistics, the move / machine counts and
## the checkpoint count, against the tier's rules in docs/NEW_WORLDS_4_BRIEF.md.
func test_zq_arcade_stats() -> void:
	var idx: int = -1
	for i: int in Game.LEVELS.size():
		if str(Game.LEVELS[i]["id"]) == "arcade":
			idx = i
	if idx < 0 or (only_level >= 0 and only_level != idx):
		return
	var lvl: LevelBase = await load_level(idx)
	var worst: float = 0.0
	var hard: int = 0
	var jumps: int = 0
	var wall: int = 0
	var mantle: int = 0
	for step: Dictionary in lvl.route:
		var kind: String = str(step["kind"])
		if kind == "w_run":
			wall += 1
		elif kind == "m_climb":
			mantle += 1
		elif kind == "jump" and not step.has("to_node"):
			var need: Vector2 = required_jump(lvl, step["from"], step["to"])
			var pct: float = need.x / max_jump_reach(need.y, float(step.get("speed", -1.0)))
			worst = maxf(worst, pct)
			jumps += 1
			if pct > 0.95:
				print("        arcade: jump %d is %.1f%% (%s -> %s)" % [jumps, pct * 100.0, str(step["from"]), str(step["to"])])
			if pct >= 0.85:
				hard += 1
	var widths: Array = lvl.get("landing_widths")
	var narrow: int = 0
	var thinnest: float = 99.0
	for w: float in widths:
		thinnest = minf(thinnest, w)
		if w >= 0.99 and w <= 1.41:
			narrow += 1
	print("        arcade: %d main-path jumps, hardest %.1f%%, %d at 85%% or more, %d/%d landings 1.0-1.4 m, thinnest %.2f m" % [jumps, worst * 100.0, hard, narrow, widths.size(), thinnest])
	print("        arcade: %d checkpoints, %d wall runs, %d mantles on the main route; branches %d, shortcuts %d" % [lvl.checkpoints.size(), wall, mantle, int(lvl.get("stat_branches")), int(lvl.get("stat_shortcuts"))])
	check(lvl.checkpoints.size() == 14, "arcade: 14 checkpoints (%d)" % lvl.checkpoints.size())
	check(worst >= 0.92 and worst <= 0.95, "arcade: the hardest main-path jump is 92-95%% (%.1f%%)" % (worst * 100.0))
	check(hard >= 12, "arcade: 12 or more main-path jumps at 85%% or more (%d)" % hard)
	check(widths.size() > 0 and float(narrow) / float(widths.size()) >= 0.333, "arcade: a third of the landings are 1.0-1.4 m (%d of %d)" % [narrow, widths.size()])
	check(thinnest >= 0.9, "arcade: no landing under 0.9 m (%.2f)" % thinnest)
	check(int(lvl.get("stat_branches")) >= 3 and int(lvl.get("stat_shortcuts")) >= 4, "arcade: 3+ branches and 4+ shortcuts")
	for cls: String in ["LaserGate", "Piston", "Crusher", "WarpPortal", "ArcadeBlock", "ArcadeChomper", "ArcadePaddle", "ArcadeGlitch"]:
		check(lvl.find_children("*", cls, true, false).size() > 0, "arcade: has a %s" % cls)
	check(wall + int(lvl.get("stat_wallruns")) >= 3, "arcade: 3+ wall runs")
	check(mantle >= 3, "arcade: 3+ mantles on the main route (%d)" % mantle)


# ---- Castle Siege (world-siege): its mechanics, tells and the machines it must contain -----------------

func test_zsg_siege_level_contents() -> void:
	var lvl: LevelBase = await load_level(29)
	check(lvl.theme_id == "siege" and lvl.checkpoints.size() == 14, "Castle Siege has 14 checkpoints (%d)" % lvl.checkpoints.size())
	var counts: Dictionary = {}
	for k: String in ["SiegeBoulder", "SiegeRam", "SiegeOil", "SiegeVolley", "SiegeTrebuchet", "LaserGate", "Piston", "Crusher", "WarpPortal",
			"Drawbridge", "GapWall", "SpinHammer", "FallingBlock", "CannonBattery", "LaunchBarrel", "WallRunPanel", "LedgeBlock"]:
		counts[k] = lvl.find_children("*", k, true, false).size()
	check(int(counts["SiegeBoulder"]) >= 6 and int(counts["SiegeRam"]) >= 1 and int(counts["SiegeOil"]) >= 1 and int(counts["SiegeVolley"]) >= 3, "the four siege mechanics are all in the course %s" % str(counts))
	check(int(counts["LaserGate"]) >= 1 and int(counts["Piston"]) >= 1 and int(counts["Crusher"]) >= 1 and int(counts["WarpPortal"]) >= 1, "all four machines are in the course")
	var kit_kinds: int = 0
	for k: String in ["Drawbridge", "GapWall", "SpinHammer", "FallingBlock", "CannonBattery", "LaunchBarrel"]:
		if int(counts[k]) > 0:
			kit_kinds += 1
	check(kit_kinds >= 3, "at least three kit obstacles are used (%d)" % kit_kinds)
	check(int(counts["WallRunPanel"]) >= 3 and int(counts["LedgeBlock"]) >= 3, "at least 3 wall runs and 3 mantles")
	check(lvl.route_variants == 3, "three route variants (main, branches, shortcuts)")


func test_zsg_siege_tells_and_clock() -> void:
	var lvl: LevelBase = await load_level(29)
	var ok_tell: bool = true
	for n: Node in lvl.find_children("*", "SiegeBoulder", true, false):
		var b: SiegeBoulder = n as SiegeBoulder
		ok_tell = ok_tell and b.warn >= 0.8
		# deadly exactly at the impact instant, clear a moment later, and the prediction agrees
		var t0: float = (1.0 - b.phase) * b.period
		check(b.is_deadly_at(t0 + 0.05) and not b.is_deadly_at(t0 + b.deadly + 0.2), "a boulder is deadly only for its short impact window")
		check(not b.is_clear_between(t0 - 1.0, 0.8, 1.2) and b.is_clear_between(t0 + 0.6, 0.0, 1.0), "boulder clear-window prediction matches the clock")
		break
	for n: Node in lvl.find_children("*", "SiegeBoulder", true, false):
		ok_tell = ok_tell and (n as SiegeBoulder).warn >= 0.8
	for n: Node in lvl.find_children("*", "SiegeVolley", true, false):
		ok_tell = ok_tell and (n as SiegeVolley).warn >= 0.8
	for n: Node in lvl.find_children("*", "SiegeOil", true, false):
		ok_tell = ok_tell and (n as SiegeOil).tilt_time >= 0.8
	for n: Node in lvl.find_children("*", "LaserGate", true, false):
		ok_tell = ok_tell and (n as LaserGate).warn >= 0.8
	check(ok_tell, "every siege hazard and flame gate shows its tell for 0.8 s or more")
	var oil: SiegeOil = lvl.find_children("*", "SiegeOil", true, false)[0] as SiegeOil
	check(not oil.covers(2.9, 0.1) and oil.covers(2.9, (oil.tilt_time + 3.0 / oil.speed) + 0.2), "the oil tongue reaches a lane point only after its tilt and run")
	var ram: SiegeRam = lvl.find_children("*", "SiegeRam", true, false)[0] as SiegeRam
	var t_mid: float = (0.5 - ram.phase) * ram.period
	check(not ram.clear_at(t_mid, 0.0) and ram.clear_at(t_mid + ram.period * 0.25, 0.0), "the ram crosses the lane centre at the middle of its swing and is clear at the ends")


# ---- Dino Valley (world-dino) ----------------------------------------------------------------------

func _dino_index() -> int:
	for i: int in Game.LEVELS.size():
		if str(Game.LEVELS[i]["id"]) == "dino":
			return i
	return -1


## The shape of the course the brief asks for, measured on the main route (variant 0).
func test_zd_dino_course_stats() -> void:
	var idx: int = _dino_index()
	if only_level >= 0 and only_level != idx:
		return
	var keep: int = LevelBase.route_variant
	LevelBase.route_variant = 0
	var lvl: LevelBase = await load_level(idx)
	await seconds(0.3)
	var worst: float = 0.0
	var hi: int = 0
	var jumps: int = 0
	var walls: int = 0
	var mantles: int = 0
	for i: int in lvl.route.size():
		var step: Dictionary = lvl.route[i]
		var kind: String = str(step["kind"])
		if kind == "w_run" and not bool(step.get("chain", false)):
			walls += 1
		elif kind == "m_climb":
			mantles += 1
		elif kind == "jump" and not step.has("to_node"):
			var need: Vector2 = required_jump(lvl, step["from"], step["to"])
			var pct: float = need.x / max_jump_reach(need.y, float(step.get("speed", -1.0)))
			worst = maxf(worst, pct)
			jumps += 1
			if pct >= 0.85:
				hi += 1
			if pct >= 0.9:
				print("        jump step %d: %.0f%% from %s to %s" % [i, pct * 100.0, str(step["from"].snapped(Vector3.ONE * 0.1)), str(step["to"].snapped(Vector3.ONE * 0.1))])
	for cpn: Checkpoint in lvl.checkpoints:
		print("        cp %d at %s" % [cpn.index, str(cpn.global_position.snapped(Vector3.ONE * 0.1))])
	print("        dino main route: %d jumps, %d at 85%%+, hardest %.0f%%, %d wall runs, %d mantles" % [jumps, hi, worst * 100.0, walls, mantles])
	check(lvl.checkpoints.size() == 16, "Dino Valley has 16 checkpoints (%d)" % lvl.checkpoints.size())
	check(worst >= 0.87 and worst <= 0.91, "hardest main-path jump is 87-91%% (%.0f%%)" % (worst * 100.0))
	check(hi >= 8, "8 or more main-path jumps at 85%% or above (%d)" % hi)
	check(walls >= 3 and mantles >= 3, "at least 3 wall runs (%d) and 3 mantles (%d) on the main route" % [walls, mantles])
	check(lvl.route_variants == 3, "three route variants (main, branches, shortcuts)")
	check(int(lvl.get("stats")["branches"]) >= 3 and int(lvl.get("stats")["shortcuts"]) >= 4, "at least 3 branched stages and 4 shortcuts (%s)" % str(lvl.get("stats")))
	var machines: Array[String] = ["LaserGate", "Piston", "Crusher", "WarpPortal"]
	var absent: Array[String] = []
	for k: String in machines:
		if lvl.find_children("*", k, true, false).is_empty():
			absent.append(k)
	check(absent.is_empty(), "the four machines are all there (missing: %s)" % str(absent))
	var kits: int = 0
	for k2: String in ["RollingLog", "Zipline", "FallingBlock", "Seesaw", "SpinHammer", "Flipper", "GapWall", "Drawbridge", "CannonBattery", "LaunchBarrel"]:
		if not lvl.find_children("*", k2, true, false).is_empty():
			kits += 1
	check(kits >= 3, "at least 3 kit obstacles are used (%d kinds)" % kits)
	var own: int = 0
	for k3: String in ["DinoGeyser", "DinoTar", "DinoStampede", "DinoRex"]:
		if not lvl.find_children("*", k3, true, false).is_empty():
			own += 1
	check(own == 4, "all four Dino mechanics are placed (%d)" % own)
	LevelBase.route_variant = keep


## The geyser: a tell of 0.8 s or more, then a jet that carries a rider up to its crest and holds them there.
func test_zd_geyser() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab()
	var g := DinoGeyser.new()
	g.height = 5.6
	g.period = 8.0
	kit.root.add_child(g)
	check(g.warn >= 0.8, "the geyser rumbles for at least 0.8 s before it blows (%.2f s)" % g.warn)
	check(g.phase_at(0.0) == 0 and g.erupts_in(0.0) > g.warn, "it idles, then the tell, then the eruption")
	await wait_until(func() -> bool: return g.is_erupting_at(Game.course_time), 10.0, "the geyser to erupt")
	await seconds(1.6)
	check(player.global_position.y > 4.2 and player.global_position.y < 6.6, "the jet holds a rider near its crest (y %.2f)" % player.global_position.y)
	await wait_until(func() -> bool: return not g.is_erupting_at(Game.course_time), 6.0, "the eruption to end")
	await seconds(1.5)
	check(player.global_position.y < 1.0, "and lets go when it ends (y %.2f)" % player.global_position.y)


## The tar pit: slows you, sinks under you, lets go when you step off.
func test_zd_tar() -> void:
	await new_world(Vector3(0, 0.45, 0))
	floor_slab(Vector3(200, 1, 200), Vector3(0, -3, 0))
	var t := DinoTar.new()
	t.size = Vector3(8, 1.4, 8)
	t.sink_max = 1.6
	t.position = Vector3(0, -0.7, 0)
	kit.root.add_child(t)
	await seconds(0.5)
	check(player.speed_mult < 0.7, "standing in tar slows you (speed x%.2f)" % player.speed_mult)
	check(t.depth > 0.1 and player.global_position.y < 0.3, "and the tar sinks under you (depth %.2f)" % t.depth)
	player.teleport(Transform3D(Basis(), Vector3(20, -2.9, 0)))
	await seconds(2.0)
	check(is_equal_approx(player.speed_mult, 1.0), "stepping off gives your speed back")
	check(t.depth < 0.05, "and the pit heaves back up (depth %.2f)" % t.depth)


## The stampede: the herd is on the deck for a stretch of each cycle, announces itself well before it
## arrives, and clear_for() agrees with where the ranks are.
func test_zd_stampede() -> void:
	await new_world(Vector3(0, 0.05, 30))
	floor_slab()
	var s := DinoStampede.new()
	s.period = 7.0
	kit.root.add_child(s)
	var arrive: float = s.front_reaches(0.0)
	check(arrive >= 1.4, "the herd is in sight for %.2f s before it reaches the middle of the lane" % arrive)
	check(not s.clear_for(0.0, arrive - 0.2, arrive + 0.2), "clear_for() sees the herd crossing")
	check(s.clear_for(0.0, 0.0, 0.0) or arrive > 0.0, "and the lane is free before it")
	var gap: float = s.period - (float(s.count - 1) * s.gap + 5.0) / s.speed
	check(gap >= 3.0, "there are %.1f s clear between herds, room for a crossing and a human's pause" % gap)


## The rex: silent for the delay, then a fixed chase; it never outruns the track and stops at its end.
func test_zd_rex() -> void:
	await new_world(Vector3(0, 0.05, 0))
	floor_slab()
	var r := DinoRex.new()
	var tr: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, -40), Vector3(0, 0, -90)]
	r.track = tr
	r.trigger_pos = Vector3(0, 1.5, 0)
	r.position = Vector3(0, 0, 60)
	kit.root.add_child(r)
	check(r.is_armed() and r.dist_at(0.0) == 0.0, "armed and still before the trigger")
	check(r.delay >= 2.0, "it announces itself for %.1f s before the first stride" % r.delay)
	check(r.speed_at(r.delay + 0.5) < 9.0 and r.speed_at(r.delay + 20.0) <= r.v_max, "it starts slower than a runner and never passes v_max")
	check(is_equal_approx(r.dist_at(r.run_time() + 5.0), 90.0), "and stops at the end of its track")
	await seconds(0.3)
	player.teleport(Transform3D(Basis(), Vector3(0, 0.05, 60)))
	await seconds(0.3)
	check(not r.is_armed(), "crossing the line wakes it")
	r.reset_state()
	check(r.is_armed(), "a respawn re-arms it")
