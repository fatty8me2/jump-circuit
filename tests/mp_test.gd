extends Node
## Two-process multiplayer integration test (run one host and one client):
##   godot --headless --path . res://tests/mp_test.tscn -- --role=host
##   godot --headless --path . res://tests/mp_test.tscn -- --role=client
## Optional: --port=<n> (default 24577; both processes must use the same one).
## Covers: connect, roster sync, clock sync, synchronized race start, ghost pose
## replication, checkpoint + finish reporting, standings, return to lobby; then a Party Mode
## round: mode sync, item boxes decided by the host (a box is consumed once), a Shove and a
## Fox Claw KO crossing the wire, the KO credited on both ends, and identical round scores.
## A watchdog ends the process (exit 1) if the run stalls, so a missing peer never hangs it.

var role: String = "host"
var passed: int = 0
var failed: int = 0
var _clock_error: float = 99.0
var _port: int = 24577
var _done: bool = false
## Counts engine/script errors: a runtime error only aborts the function it hits.
var _trap := TestLib.ErrorTrap.new()


func _ready() -> void:
	Net.upnp_enabled = false   # never open a port on the real router
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
		elif a.begins_with("--port="):
			_port = int(a.trim_prefix("--port="))
	OS.add_logger(_trap)
	name = "MpTest"
	# survive scene changes
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	SaveData.path_override = "user://test_progress_%s.json" % role
	Settings.player_name = "Host" if role == "host" else "Guest"
	Settings.color_index = 1 if role == "host" else 2
	get_tree().create_timer(170.0, true, false, true).timeout.connect(func() -> void:
		_finish("watchdog: test did not complete in 170 s"))
	_run.call_deferred()


## Abort path: report, clean up and quit with a failure (runs at most once).
func _finish(reason: String) -> void:
	if _done:
		return
	_done = true
	failed += 1
	print("[%s]   FAIL  %s" % [role, reason])
	print("[%s] RESULT: %d passed, %d failed" % [role, passed, failed])
	Net.leave()
	SaveData.delete_files()
	Sfx.quit(1)


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
	if Net.roster.size() != 2:
		_finish("no second peer - is the other process running on port %d?" % _port)
		return
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
	if lvl == null or lvl.player == null:
		_finish("the race level never loaded")
		return
	check(not lvl.player.control_enabled and Game.course_time < 0.0, "players are held during the countdown (t=%.2f)" % Game.course_time)
	check(await wait_for(func() -> bool: return lvl.player.control_enabled, 6.0), "control unlocks at GO")
	check(absf(Game.course_time) < 0.3, "GO happens at course time zero (t=%.2f)" % Game.course_time)
	check(lvl._ghosts.size() == 1, "one ghost racer spawned for the other player")
	if lvl._ghosts.is_empty():
		_finish("no ghost to follow")
		return
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
	# give the other peer time to check our ghost before we teleport away (the two
	# processes poll GO independently, so their timelines differ by up to ~50 ms)
	await get_tree().create_timer(0.5).timeout
	# checkpoint + finish
	lvl.player.teleport(lvl.checkpoints[0].respawn_transform())
	await get_tree().create_timer(0.4).timeout
	var other: int = 0
	for id: int in Net.roster:
		if id != Net.my_id():
			other = id
	check(await wait_for(func() -> bool: return other != 0 and Net.roster.has(other) and int(Net.roster[other]["cp"]) >= 1, 5.0), "other racer's checkpoint progress arrives")
	if role == "client":
		await get_tree().create_timer(1.0).timeout    # host finishes first
	var gates: Array[Node] = lvl.find_children("*", "FinishGate", true, false)
	if gates.is_empty():
		_finish("the level has no finish gate")
		return
	var gate: FinishGate = gates[0] as FinishGate
	lvl.player.teleport(Transform3D(Basis(), gate.global_position + Vector3(0, 0.3, 0)))
	check(await wait_for(func() -> bool: return Net.all_finished(), 8.0), "both finish times are known to this peer")
	var order: Array[int] = Net.standings()
	check(order.size() == 2 and order[0] == 1, "standings put the host (finished first) on top")
	if order.size() != 2:
		_finish("a racer dropped out of the roster mid-race")
		return
	check(float(Net.roster[order[0]]["finished"]) < float(Net.roster[order[1]]["finished"]), "finish times ordered %.2f < %.2f" % [float(Net.roster[order[0]]["finished"]), float(Net.roster[order[1]]["finished"])])
	if role == "host":
		await get_tree().create_timer(0.5).timeout
		Net.host_return_to_lobby()
	check(await wait_for(func() -> bool: return not Game.race_mode and Game.title_screen == "lobby", 8.0), "everyone returns to the lobby together")
	await get_tree().create_timer(0.5).timeout
	check(Net.active and Net.roster.size() == 2, "session stays connected for the next race")
	await _party_round()
	_done = true   # the watchdog must not fire during the orderly shutdown below
	check(_trap.count() == 0, ("no engine/script errors during the session %s" % _trap.since(0)).strip_edges())
	OS.remove_logger(_trap)
	print("[%s] RESULT: %d passed, %d failed" % [role, passed, failed])
	if role == "client":
		Net.leave()
	else:
		await get_tree().create_timer(1.0).timeout
		Net.leave()
	SaveData.delete_files()
	Sfx.quit(1 if failed > 0 else 0)


# ---- Party Mode round ------------------------------------------------------------------

var _party_seen: Dictionary = {}


func _on_party_msg(from_id: int, m: Dictionary) -> void:
	var k: String = str(m.get("k", ""))
	if k == "test":
		_party_seen[str(m.get("t", ""))] = true
	elif k == "box":
		_party_seen["box%d" % int(m.get("b", -1))] = int(_party_seen.get("box%d" % int(m.get("b", -1)), 0)) + 1


func _other_id() -> int:
	for id: int in Net.roster:
		if id != Net.my_id():
			return id
	return 0


## Stands `lvl`'s player just behind/beside the other racer's ghost, facing it.
func _face_ghost(lvl: LevelBase, dist: float) -> void:
	var g: RemoteRacer = lvl._ghosts.values()[0]
	var gp: Vector3 = g.global_position
	var from: Vector3 = gp + Vector3(0, 0, dist)
	var dir: Vector3 = (gp - from).normalized()
	lvl.player.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), from + Vector3(0, 0.05, 0)))
	lvl.player.facing_dir = dir
	lvl.camera.yaw = atan2(-dir.x, -dir.z)
	lvl.player.camera_yaw = lvl.camera.yaw


func _party_round() -> void:
	Net.party_message.connect(_on_party_msg)
	if role == "host":
		Net.host_set_mode("party")
	check(await wait_for(func() -> bool: return Net.game_mode == "party", 5.0), "the host's Party mode reaches this peer")
	if role == "host":
		await get_tree().create_timer(0.5).timeout
		Net.host_start_race(0, 2.0)
	check(await wait_for(func() -> bool: return Game.race_mode and _level() != null and _level().player != null and _level().party != null, 10.0), "a party round loads the level with the party layer")
	var lvl: LevelBase = _level()
	if lvl == null or lvl.party == null:
		_finish("the party round never loaded")
		return
	var p: PartyLayer = lvl.party
	check(Game.party != null and Game.party.mode == "party" and Game.party.round_no == 1, "this is round 1 of the Party Cup")
	check(await wait_for(func() -> bool: return lvl.player.control_enabled and not p.boxes.is_empty(), 8.0), "GO, and item boxes are placed (%d)" % p.boxes.size())
	lvl.player.use_device_input = false
	p.use_device_input = false
	var spawn: Transform3D = lvl._spawn
	var other: int = _other_id()
	var box_at := func(i: int) -> Transform3D: return Transform3D(Basis(), p.boxes[i].global_position - Vector3(0, 1.1, 0))
	# -- pickups: the host takes box 0; the guest then touches the same (gone) box, then box 1
	if role == "host":
		await get_tree().create_timer(0.3).timeout
		lvl.player.teleport(box_at.call(0))
		check(await wait_for(func() -> bool: return p.item != "", 2.0), "host picks up box 0 (%s)" % p.item)
		check(not p.boxes[0].available, "box 0 is taken")
	else:
		check(await wait_for(func() -> bool: return not p.boxes[0].available, 5.0), "the host's pickup pops box 0 on this screen too")
		lvl.player.teleport(box_at.call(0))
		await get_tree().create_timer(0.8).timeout
		check(p.item == "" and int(_party_seen.get("box0", 0)) == 1, "a box is consumed once: touching the taken box gives nothing (msgs %d)" % int(_party_seen.get("box0", 0)))
		lvl.player.teleport(box_at.call(1))
		check(await wait_for(func() -> bool: return p.item != "", 3.0), "the host grants the guest box 1 (%s)" % p.item)
		p.item = ""
		lvl.player.teleport(spawn)
		await get_tree().create_timer(0.6).timeout
		Net.send_party({"k": "test", "t": "ready1"})
	# -- a Shove crosses the wire
	var knocked: Array = [0.0]
	var from_host: Array = [""]
	p.hit_taken.connect(func(from_id: int, src: String) -> void:
		from_host[0] = src if from_id == 1 else "other"
		await get_tree().physics_frame
		knocked[0] = maxf(float(knocked[0]), Vector2(lvl.player.velocity.x, lvl.player.velocity.z).length()))
	if role == "host":
		check(await wait_for(func() -> bool: return bool(_party_seen.get("ready1", false)), 8.0), "the guest is back at the start")
		await get_tree().create_timer(0.4).timeout
		var landed: Array = [0]
		p.hit_landed.connect(func(id: int, _src: String) -> void: landed[0] = id)
		_face_ghost(lvl, 1.4)
		await get_tree().create_timer(0.1).timeout
		p.cmd_shove = true
		await get_tree().create_timer(0.1).timeout
		p.cmd_shove = false
		check(int(landed[0]) == other, "the host's Shove connects with the guest's ghost")
	else:
		check(await wait_for(func() -> bool: return str(from_host[0]) != "", 8.0), "the host's hit arrives (%s)" % str(from_host[0]))
		# the handler samples the velocity a physics frame after the hit
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(str(from_host[0]) == "shove" and float(knocked[0]) > 5.0, "the Shove knocks this player away (%.1f m/s)" % float(knocked[0]))
		# straight back before the flight can carry us off the start lawn (a fall would be a KO)
		await get_tree().create_timer(0.3).timeout
		lvl.player.teleport(spawn)
		await get_tree().create_timer(0.6).timeout
		from_host[0] = ""
		Net.send_party({"k": "test", "t": "ready2"})
	# -- a transformation is mirrored, and a Fox Claw KO is credited on both ends
	if role == "host":
		check(await wait_for(func() -> bool: return bool(_party_seen.get("ready2", false)), 8.0), "the guest is back again")
		p.give_item("fox")
		var fox: PowerUp = p.activate_item()
		await get_tree().create_timer(0.5).timeout
		_face_ghost(lvl, 1.6)
		await get_tree().create_timer(0.1).timeout
		p.cmd_attack = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		p.cmd_attack = false
		await get_tree().create_timer(0.2).timeout
		if fox != null and is_instance_valid(fox):
			fox.finish()
	else:
		check(await wait_for(func() -> bool: return (p.remote_powers.get(1, {}) as Dictionary).has("fox"), 6.0), "the host's Nine-Tailed Fox appears on its ghost here")
	check(await wait_for(func() -> bool: return int(p.kos.get(1, 0)) == 1, 6.0), "the Fox Claw KO is credited to the host on this end (kos %s)" % str(p.kos))
	if role == "client":
		check(lvl.deaths >= 1, "the KO sent the guest back to its checkpoint")
	# -- finish: host first, guest second; the host scores the round and everyone shows it
	var gates: Array[Node] = lvl.find_children("*", "FinishGate", true, false)
	var gate: FinishGate = gates[0] as FinishGate
	if role == "client":
		await wait_for(func() -> bool: return float(Net.roster[1]["finished"]) >= 0.0, 10.0)
		await get_tree().create_timer(0.5).timeout
	else:
		await get_tree().create_timer(0.5).timeout
	lvl.player.teleport(Transform3D(Basis(), gate.global_position + Vector3(0, 0.3, 0)))
	check(await wait_for(func() -> bool: return p.round_over and not p.last_rows.is_empty(), 10.0), "the round ends once everyone is home")
	var totals: Dictionary = {}
	for r: Dictionary in p.last_rows:
		totals[int(r["id"])] = int(r["total"])
	check(int(totals.get(1, -1)) == 13 and int(totals.get(other if role == "host" else Net.my_id(), -1)) == 8, "round scores agree: host 10 + 3 (KO) = 13, guest 8 (%s)" % str(totals))
	check(int(Game.party.cup.get(1, -1)) == 13, "the cup total matches on this end (%s)" % str(Game.party.cup))
	check(await wait_for(func() -> bool: return p.results != null and is_instance_valid(p.results) and p.results.is_inside_tree(), 4.0), "the round results panel shows")
	# -- round 2 straight from the results (the host's Next Round), the cup keeps adding up
	if role == "host":
		await get_tree().create_timer(1.0).timeout
		Net.host_start_race(0, 2.0)
	var old_level: int = lvl.get_instance_id()   # an id, not the node: the old level is freed meanwhile
	check(await wait_for(func() -> bool: return Game.party != null and Game.party.round_no == 2 and _level() != null and _level().get_instance_id() != old_level and _level().party != null, 10.0), "Next Round starts round 2 for everyone")
	lvl = _level()
	if lvl == null or lvl.party == null:
		_finish("round 2 never loaded")
		return
	p = lvl.party
	check(int(Game.party.cup.get(1, -1)) == 13, "the cup carries round 1 into round 2")
	check(await wait_for(func() -> bool: return lvl.player.control_enabled, 8.0), "round 2: GO")
	lvl.player.use_device_input = false
	gate = lvl.find_children("*", "FinishGate", true, false)[0] as FinishGate
	if role == "client":
		await wait_for(func() -> bool: return float(Net.roster[1]["finished"]) >= 0.0, 10.0)
		await get_tree().create_timer(0.3).timeout
	else:
		await get_tree().create_timer(0.3).timeout
	lvl.player.teleport(Transform3D(Basis(), gate.global_position + Vector3(0, 0.3, 0)))
	check(await wait_for(func() -> bool: return p.round_over and not p.last_rows.is_empty(), 10.0), "round 2 ends")
	var mine: int = Net.my_id()
	var guest: int = other if role == "host" else mine
	check(int(Game.party.cup.get(1, -1)) == 23 and int(Game.party.cup.get(guest, -1)) == 16, "cup totals after two rounds agree: 23 - 16 (%s)" % str(Game.party.cup))
	if role == "host":
		await get_tree().create_timer(1.5).timeout
		Net.host_return_to_lobby()
	check(await wait_for(func() -> bool: return not Game.race_mode and Game.title_screen == "lobby", 8.0), "back to the lobby after the cup")
	check(Game.party != null and int(Game.party.cup.get(1, -1)) == 23 and Net.party_round == 2, "the Party Cup carries on in the lobby (round %d played)" % Net.party_round)
	await get_tree().create_timer(0.5).timeout
