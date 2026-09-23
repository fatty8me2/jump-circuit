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
	SaveData.wipe()
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
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
		if n.begins_with("test_") and (only == "" or n.contains(only)):
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
	get_tree().quit(1 if failed > 0 or passed + failed == 0 else 0)


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
	get_tree().quit(2)


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
	var rel: Dictionary = Updater.parse_release({"tag_name": "v9.0.0", "html_url": "https://example.invalid/r", "body": "New levels"})
	check(rel.get("version", "") == "9.0.0" and rel.get("url", "") == "https://example.invalid/r", "a release yields its version and page")
	# a newer release: the main menu asks once, focused on Download; Esc / B backs out to main
	Updater.available = rel
	Updater.prompted = false
	Game.title_screen = "main"
	var title: Node = (load(Game.TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	await ticks(3)
	var focus: Control = get_viewport().gui_get_focus_owner()
	check(Game.title_screen == "update" and focus is Button and (focus as Button).text == "Download", "the update prompt opens with Download focused")
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
	check(Settings.quality == 2 and is_equal_approx(Settings.mouse_sensitivity, 3.0), "out-of-range quality / sensitivity are clamped")
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
	Sfx.music("a")
	await ticks(12)
	Sfx.music("b")
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
