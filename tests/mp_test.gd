extends Node
## Two-process multiplayer integration test (run one host and one client):
##   godot --headless --path . res://tests/mp_test.tscn -- --role=host
##   godot --headless --path . res://tests/mp_test.tscn -- --role=client
## Covers: connect, roster sync, clock sync, synchronized race start, ghost pose
## replication, checkpoint + finish reporting, standings, return to lobby.

var role: String = "host"
var passed: int = 0
var failed: int = 0
var _clock_error: float = 99.0
var _port: int = 24577
## Counts engine/script errors: a runtime error only aborts the function it hits.
var _trap := TestLib.ErrorTrap.new()


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	OS.add_logger(_trap)
	name = "MpTest"
	# survive scene changes
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	SaveData.path_override = "user://test_progress_%s.json" % role
	Settings.player_name = "Host" if role == "host" else "Guest"
	Settings.color_index = 1 if role == "host" else 2
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("[%s]   ok    %s" % [role, what])
	else:
		failed += 1
		print("[%s]   FAIL  %s" % [role, what])


func wait_for(cond: Callable, timeout: float) -> bool:
	var t: float = 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return false


@rpc("authority", "call_remote", "unreliable")
func _host_clock(host_now: float) -> void:
	_clock_error = minf(_clock_error, absf(Net.now() - host_now))


func _level() -> LevelBase:
	return get_tree().current_scene as LevelBase


func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	if role == "host":
		check(Net.host(_port) == OK, "host opens a server")
	else:
		await get_tree().create_timer(0.8).timeout
		check(Net.join("127.0.0.1", _port) == OK, "client starts connecting")
	check(await wait_for(func() -> bool: return Net.roster.size() == 2, 10.0), "both peers see a 2-player roster")
	var names: Array = []
	for id: int in Net.roster:
		names.append(Net.roster[id]["name"])
	names.sort()
	check(names == ["Guest", "Host"], "roster carries both names %s" % str(names))
	await get_tree().create_timer(2.5).timeout       # let clock sync pings run
	if role == "host":
		for i: int in 10:
			_host_clock.rpc(Net.now())
			await get_tree().create_timer(0.05).timeout
		Net.host_start_race(0, 2.0)
	else:
		await wait_for(func() -> bool: return _clock_error < 50.0, 5.0)
		check(_clock_error < 0.05, "client clock matches host within 50 ms (error %.1f ms)" % (_clock_error * 1000.0))
	check(await wait_for(func() -> bool: return Game.race_mode and _level() != null and _level().player != null, 10.0), "race start loads the level on this peer")
	var lvl: LevelBase = _level()
	check(not lvl.player.control_enabled and Game.course_time < 0.0, "players are held during the countdown (t=%.2f)" % Game.course_time)
	check(await wait_for(func() -> bool: return lvl.player.control_enabled, 6.0), "control unlocks at GO")
	check(absf(Game.course_time) < 0.3, "GO happens at course time zero (t=%.2f)" % Game.course_time)
	check(lvl._ghosts.size() == 1, "one ghost racer spawned for the other player")
	# move: host runs forward, guest runs back; each verifies the other's ghost follows
	lvl.player.use_device_input = false
	lvl.player.cmd_move = Vector2(0, 1) if role == "host" else Vector2(0.6, -0.4)
	await get_tree().create_timer(0.7).timeout
	lvl.player.cmd_move = Vector2.ZERO
	await get_tree().create_timer(0.6).timeout
	var ghost: RemoteRacer = lvl._ghosts.values()[0]
	var expect_forward: bool = role != "host"      # the OTHER player is the host -> moved toward -Z
	var gz: float = ghost.global_position.z
	check((gz < 0.5) if expect_forward else (gz > 3.2), "remote racer ghost mirrors the other player (ghost z=%.2f)" % gz)
	# checkpoint + finish
	lvl.player.teleport(lvl.checkpoints[0].respawn_transform())
	await get_tree().create_timer(0.4).timeout
	var other: int = 0
	for id: int in Net.roster:
		if id != Net.my_id():
			other = id
	check(await wait_for(func() -> bool: return int(Net.roster[other]["cp"]) >= 1, 5.0), "other racer's checkpoint progress arrives")
	if role == "client":
		await get_tree().create_timer(1.0).timeout    # host finishes first
	var gate: FinishGate = lvl.find_children("*", "FinishGate", true, false)[0] as FinishGate
	lvl.player.teleport(Transform3D(Basis(), gate.global_position + Vector3(0, 0.3, 0)))
	check(await wait_for(func() -> bool: return Net.all_finished(), 8.0), "both finish times are known to this peer")
	var order: Array[int] = Net.standings()
	check(order.size() == 2 and order[0] == 1, "standings put the host (finished first) on top")
	check(float(Net.roster[order[0]]["finished"]) < float(Net.roster[order[1]]["finished"]), "finish times ordered %.2f < %.2f" % [float(Net.roster[order[0]]["finished"]), float(Net.roster[order[1]]["finished"])])
	if role == "host":
		await get_tree().create_timer(0.5).timeout
		Net.host_return_to_lobby()
	check(await wait_for(func() -> bool: return not Game.race_mode and Game.title_screen == "lobby", 8.0), "everyone returns to the lobby together")
	await get_tree().create_timer(0.5).timeout
	check(Net.active and Net.roster.size() == 2, "session stays connected for the next race")
	check(_trap.count() == 0, ("no engine/script errors during the session %s" % _trap.since(0)).strip_edges())
	OS.remove_logger(_trap)
	print("[%s] RESULT: %d passed, %d failed" % [role, passed, failed])
	if role == "client":
		Net.leave()
	else:
		await get_tree().create_timer(1.0).timeout
		Net.leave()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.path_override))
	get_tree().quit(1 if failed > 0 else 0)
