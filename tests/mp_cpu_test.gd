extends Node
## Two-process test of CPU racers over a real (direct ENet) connection - run one host, one client:
##   godot --headless --path . res://tests/mp_cpu_test.tscn -- --role=host --save=party-cpu
##   godot --headless --path . res://tests/mp_cpu_test.tscn -- --role=client --save=party-cpu
## Optional: --port=<n> (default 24578). The host's "Fill with CPUs" tops the roster up to 8 for a
## Party round; the host simulates the CPUs and the client must see them move, bank checkpoints
## and finish; a client's hit on a CPU reaches the host's CPU, a CPU's hit reaches the client,
## and a KO of a CPU is credited on both ends. A watchdog ends the process (exit 1) if it stalls.

var role: String = "host"
var passed: int = 0
var failed: int = 0
var _port: int = 24578
var _done: bool = false
var _trap := TestLib.ErrorTrap.new()
var _seen: Dictionary = {}
var _target: int = 0


func _ready() -> void:
	Net.upnp_enabled = false
	var save: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
		elif a.begins_with("--port="):
			_port = int(a.trim_prefix("--port="))
		elif a.begins_with("--save=") and a.trim_prefix("--save=").is_valid_filename():
			save = a.trim_prefix("--save=")
	OS.add_logger(_trap)
	name = "MpCpuTest"
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	SaveData.path_override = "user://%s_cpu_%s.json" % [save if save != "" else "test", role]
	Settings.player_name = "Host" if role == "host" else "Guest"
	Settings.color_index = 1 if role == "host" else 2
	get_tree().create_timer(170.0, true, false, true).timeout.connect(func() -> void:
		_finish("watchdog: test did not complete in 170 s"))
	_run.call_deferred()


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


func _level() -> LevelBase:
	return get_tree().current_scene as LevelBase


func _on_msg(_from: int, m: Dictionary) -> void:
	if str(m.get("k", "")) == "test":
		_seen[str(m.get("t", ""))] = true
	elif str(m.get("k", "")) == "cwrap" and int(m.get("to", 0)) == _target:
		_seen["wrap"] = true   # (host) the guest's hit on the CPU arrived


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
	Net.party_message.connect(_on_msg)
	await get_tree().create_timer(2.5).timeout   # clock sync
	if role == "host":
		CpuField.fill_online = true
		CpuField.difficulty = "hard"
		Net.host_set_mode("party")
		await get_tree().create_timer(0.5).timeout
		Net.host_start_race(0, 2.0)
	check(await wait_for(func() -> bool: return Game.race_mode and _level() != null and _level().party != null, 12.0), "a party round loads with the party layer")
	var lvl: LevelBase = _level()
	if lvl == null or lvl.party == null:
		_finish("the party round never loaded")
		return
	var p: PartyLayer = lvl.party
	var cpus: Array[int] = CpuField.cpu_ids()
	check(Net.roster.size() == 8 and cpus.size() == 6, "the roster holds 8 racers, 6 of them CPUs (%d / %d)" % [Net.roster.size(), cpus.size()])
	check(lvl._ghosts.size() == 7, "every other racer has a ghost here (%d)" % lvl._ghosts.size())
	var field: CpuField = p.find_child("CpuField", false, false) as CpuField
	check(field != null and (field.racers.size() == 6) == (role == "host"), "only the host simulates the CPUs (%d simulated here)" % (field.racers.size() if field != null else -1))
	check(await wait_for(func() -> bool: return lvl.player.control_enabled, 8.0), "GO")
	lvl.player.use_device_input = false
	p.use_device_input = false
	# -- the CPUs run: the guest sees poses, checkpoints and positions come over the wire
	var start: Dictionary = {}
	for id: int in cpus:
		start[id] = (lvl._ghosts[id] as RemoteRacer).global_position
	await get_tree().create_timer(14.0).timeout
	var moved: int = 0
	var banked: int = 0
	for id: int in cpus:
		if (lvl._ghosts[id] as RemoteRacer).global_position.distance_to(start[id]) > 15.0:
			moved += 1
		if int(Net.roster[id]["cp"]) >= 1:
			banked += 1
	check(moved >= 5, "the CPU ghosts run along the course here (%d of 6 moved)" % moved)
	check(banked >= 1, "their checkpoint progress reaches the roster here (%d CPUs past checkpoint 1)" % banked)
	var target: int = cpus[0]
	_target = target
	var human: int = 1 if role == "client" else Net.my_id()
	var other: int = _other()
	# -- the guest hits CPU `target`; the host's CPU registers it
	if role == "client":
		check(await wait_for(func() -> bool: return bool(_seen.get("go_hit", false)), 10.0), "the host is ready for the guest's hit")
		Net.send_party({"k": "hit", "kb": PowerUp.arr(Vector3(6, 5, 0)), "st": 0.4, "ko": false, "e": "", "ed": 0.0, "s": "shove", "add": false}, target)
	else:
		var r: CpuRacer = field.racers[target]
		r.protect_left = 0.0   # (a respawn grace would swallow the hit)
		Net.send_party({"k": "test", "t": "go_hit"})
		check(await wait_for(func() -> bool: return bool(_seen.get("wrap", false)), 10.0), "a guest's hit on a CPU reaches the host")
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(r.last_hit_by == other or r.walker.mode == RouteWalker.Mode.AIR or r.walker.hold > 0.0, "...and the host's CPU registers it (by %d, hold %.2f)" % [r.last_hit_by, r.walker.hold])
		# the CPU falls right after: the KO is the guest's, on both ends
		r.last_hit_by = other
		r.last_hit_at = field.clock
		r.protect_left = 0.0
		r.walker.die("fall")
	check(await wait_for(func() -> bool: return int(p.kos.get(other if role == "host" else Net.my_id(), 0)) == 1, 6.0), "the KO of a CPU is credited to the guest on this end (kos %s)" % str(p.kos))
	# -- a CPU hits the host: the message reaches whoever was hit, credited to the CPU
	var from_cpu: Array = [0]
	p.hit_taken.connect(func(from_id: int, _src: String) -> void: from_cpu[0] = from_id)
	await get_tree().create_timer(0.5).timeout
	if role == "host":
		var racer: CpuRacer = field.racers[cpus[1]]
		var riv: Dictionary = {}
		for d: Dictionary in field.rivals_of(racer):
			if int(d["id"]) == other:
				riv = d
		check(not riv.is_empty(), "the guest is among a CPU's rivals")
		racer.protect_left = 0.0
		field.hit_rival(racer, riv, Vector3(2, 4, 0), {"st": 0.3, "s": "shove"})
		Net.send_party({"k": "test", "t": "cpu_hit_sent"})
	else:
		check(await wait_for(func() -> bool: return CpuField.is_cpu_id(int(from_cpu[0])), 6.0), "a CPU's hit on the guest arrives, credited to the CPU (%d)" % int(from_cpu[0]))
		check(p.last_hit_by == from_cpu[0], "...and is remembered for KO credit")
	await get_tree().create_timer(0.3).timeout
	# -- a CPU finishes: the guest sees it
	if role == "host":
		var fin: CpuRacer = field.racers[cpus[2]]
		field.cpu_finish(fin)
		Net.send_party({"k": "test", "t": "fin_sent"})
	check(await wait_for(func() -> bool: return float(Net.roster[cpus[2]]["finished"]) >= 0.0 and int(Net.roster[cpus[2]]["cp"]) > lvl.checkpoints.size(), 8.0), "a CPU's finish and final checkpoint show in the standings here")
	check(Net.standings()[0] == cpus[2], "...and it leads the standings")
	Net.send_party({"k": "test", "t": "done_" + role})
	await wait_for(func() -> bool: return bool(_seen.get("done_" + ("client" if role == "host" else "host"), false)), 10.0)
	await get_tree().create_timer(0.5).timeout
	check(_trap.count() == 0, "no engine errors on this end (%s)" % _trap.since(0))
	print("[%s] RESULT: %d passed, %d failed" % [role, passed, failed])
	_done = true
	Net.leave()
	SaveData.delete_files()
	Sfx.quit(1 if failed > 0 else 0)


func _other() -> int:
	for id: int in Net.roster:
		if id != Net.my_id() and not CpuField.is_cpu_id(id):
			return id
	return 0
