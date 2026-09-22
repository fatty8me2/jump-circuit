extends Node
## Multiplayer racing over ENet (LAN, VPN or a forwarded UDP port).
## Model: every racer simulates their own character locally - movement stays
## lag-free and nobody's jump depends on someone else's physics. Peers exchange
## lightweight pose snapshots; kinematic obstacles are driven by a shared clock
## so everyone sees the same cycles. Racers do not collide.

signal roster_changed
signal joined_lobby
signal connection_failed(reason: String)
signal left_session(reason: String)
signal race_starting(level_index: int, start_time: float)
## seq changes whenever that racer teleported (respawn), so ghosts snap instead of sliding.
signal racer_pose(id: int, pos: Vector3, vel: Vector3, grounded: bool, seq: int)
signal racer_finished(id: int, time: float)
signal lobby_requested
signal upnp_result(text: String)

const PORT: int = 24565
const MAX_PLAYERS: int = 8
## A join still unanswered after this many seconds is reported as unreachable
## (ENet on its own gives up only after ~30 s).
const CONNECT_TIMEOUT: float = 10.0

var active: bool = false
## peer id -> {"name": String, "color": int, "cp": int, "finished": float (-1 = still racing),
## "cp_at": float (session time that checkpoint was reached; breaks standings ties)}
var roster: Dictionary = {}
var race_level: int = -1
var race_start_time: float = 0.0
var in_race: bool = false
## Off in automated tests: never touch the real router.
var upnp_enabled: bool = true
## Cached UPnP outcome for the current hosting session ("" = not known yet).
var upnp_text: String = ""
## The player's own colour while the host has them wearing another one (-1 = none).
## Settings saves this instead of the session colour, and it returns when the session ends.
var preferred_color: int = -1

var _clock_offset: float = 0.0
var _best_rtt: float = 999.0
var _ping_timer: float = 0.0
var _pings_left: int = 0
var _connect_left: float = -1.0
var _join_port: int = PORT
var _pose_seq: int = 0
var _upnp_thread: Thread
var _upnp: UPNP


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void:
		_shutdown()
		connection_failed.emit("Could not reach that host."))
	multiplayer.server_disconnected.connect(func() -> void:
		_shutdown()
		left_session.emit("The host closed the session."))


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


func is_host() -> bool:
	return active and multiplayer.is_server()


func _local_time() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


## Session clock shared by all peers (the host's clock).
func now() -> float:
	return _local_time() + _clock_offset


# ---- session lifecycle ---------------------------------------------------------

func host(port: int = PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	# one spare slot so a surplus joiner gets a "race is full" answer instead of silence
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	_clock_offset = 0.0
	roster = {1: _my_entry()}
	roster_changed.emit()
	joined_lobby.emit()
	return OK


func join(address: String, port: int = PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address.strip_edges(), port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	_connect_left = CONNECT_TIMEOUT
	_join_port = port
	return OK


func leave() -> void:
	if active:
		_shutdown()


func _shutdown() -> void:
	if _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
		_upnp = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	in_race = false
	roster.clear()
	_best_rtt = 999.0
	_pings_left = 0
	_connect_left = -1.0
	_clock_offset = 0.0
	upnp_text = ""
	if preferred_color >= 0:
		Settings.color_index = preferred_color
		preferred_color = -1
	roster_changed.emit()


func _my_entry() -> Dictionary:
	return {"name": Settings.player_name, "color": Settings.color_index, "cp": 0, "finished": -1.0}


func _on_connected() -> void:
	_connect_left = -1.0
	_begin_clock_sync()
	_register.rpc_id(1, Settings.player_name, Settings.color_index)


## (Re)measure the host clock: a short ping burst, keeping the lowest-RTT sample.
## The old offset stays in use until the first new pong arrives.
func _begin_clock_sync(delay: float = 0.0) -> void:
	_best_rtt = 999.0
	_pings_left = 8
	_ping_timer = delay


func _on_peer_disconnected(id: int) -> void:
	# a kicked joiner was never in the roster: nothing to tell anyone
	if roster.erase(id):
		roster_changed.emit()
		if is_host():
			_sync_roster.rpc(roster)


func _process(dt: float) -> void:
	if _connect_left > 0.0 and active and multiplayer.multiplayer_peer != null \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		_connect_left -= dt
		if _connect_left <= 0.0:
			_shutdown()
			connection_failed.emit("No answer from that address - check it, that the host pressed Host a Race, and that UDP %d is reachable." % _join_port)
			return
	if active and not is_host() and _pings_left > 0:
		_ping_timer -= dt
		if _ping_timer <= 0.0:
			_ping_timer = 0.25
			_pings_left -= 1
			_ping.rpc_id(1, _local_time())
			if _pings_left == 0 and _best_rtt >= 999.0:
				_pings_left = 8   # no pong came back yet: keep trying rather than race on a zero offset


# ---- lobby RPCs -----------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, color: int) -> void:
	if not is_host():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if in_race and not roster.has(id):
		_kick.rpc_id(id, "A race is in progress - try again in a moment.")
		return
	# (existing racers re-register on every name / colour change - only newcomers can be turned away)
	if not roster.has(id) and roster.size() >= MAX_PLAYERS:
		_kick.rpc_id(id, "That race is full (%d/%d)." % [roster.size(), MAX_PLAYERS])
		return
	var joining: bool = not roster.has(id)
	var entry: Dictionary = roster.get(id, {"cp": 0, "finished": -1.0})
	entry["name"] = player_name.substr(0, 14)
	# a newcomer gets a colour nobody else wears; later explicit picks are honoured
	entry["color"] = _free_color(id, color) if joining else posmod(color, Settings.RACER_COLORS.size())
	roster[id] = entry
	_sync_roster.rpc(roster)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _kick(reason: String) -> void:
	_shutdown()
	connection_failed.emit(reason)


## Preferred colour if nobody else in the roster has it, else the first free one
## (MAX_PLAYERS == RACER_COLORS.size(), so one is always free).
func _free_color(id: int, want: int) -> int:
	var n: int = Settings.RACER_COLORS.size()
	want = posmod(want, n)
	var used: Array[int] = []
	for other: int in roster:
		if other != id:
			used.append(posmod(int(roster[other]["color"]), n))
	if not used.has(want):
		return want
	for i: int in n:
		if not used.has(i):
			return i
	return want


@rpc("authority", "call_remote", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	# "joined" = the first snapshot that lists us (the host has accepted our registration)
	var first: bool = not roster.has(my_id()) and new_roster.has(my_id())
	if in_race:
		# cp / finished only move forward during a race: a snapshot the host sent before our
		# own (call_local) checkpoint or finish reached it must not roll them back
		for id: int in new_roster:
			if roster.has(id):
				var old: Dictionary = roster[id]
				var e: Dictionary = new_roster[id]
				if int(old["cp"]) > int(e["cp"]):
					e["cp"] = old["cp"]
					e["cp_at"] = old.get("cp_at", 0.0)
				if float(old["finished"]) >= 0.0 and float(e["finished"]) < 0.0:
					e["finished"] = old["finished"]
	roster = new_roster
	if first:
		# wear the colour the host assigned for this session (it moves newcomers off colours
		# already taken); the player's own pick comes back when the session ends
		var assigned: int = int(roster[my_id()]["color"])
		if assigned != Settings.color_index:
			preferred_color = Settings.color_index
			Settings.color_index = assigned
	roster_changed.emit()
	if first:
		joined_lobby.emit()


@rpc("any_peer", "call_remote", "unreliable")
func _ping(client_time: float) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), client_time, _local_time())


@rpc("authority", "call_remote", "unreliable")
func _pong(client_time: float, server_time: float) -> void:
	var rtt: float = _local_time() - client_time
	if rtt < _best_rtt:
		_best_rtt = rtt
		_clock_offset = server_time + rtt * 0.5 - _local_time()


func update_identity() -> void:
	# still connecting: nothing to send yet (_on_connected registers the current identity)
	if not active or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if is_host():
		roster[1]["name"] = Settings.player_name
		roster[1]["color"] = Settings.color_index
		_sync_roster.rpc(roster)
		roster_changed.emit()
	else:
		_register.rpc_id(1, Settings.player_name, Settings.color_index)


# ---- race flow --------------------------------------------------------------------

func host_start_race(level_index: int, countdown: float = 4.0) -> void:
	if is_host():
		_start_race.rpc(level_index, now() + countdown)


@rpc("authority", "call_local", "reliable")
func _start_race(level_index: int, start_time: float) -> void:
	if not is_host() and not roster.has(my_id()):
		return   # joined a moment ago and not registered yet: the host will turn us away
	race_level = level_index
	race_start_time = start_time
	in_race = true
	for id: int in roster:
		roster[id]["cp"] = 0
		roster[id]["cp_at"] = 0.0
		roster[id]["finished"] = -1.0
	race_starting.emit(level_index, start_time)


func host_return_to_lobby() -> void:
	if is_host():
		_return_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _return_to_lobby() -> void:
	if not is_host() and not roster.has(my_id()):
		return
	in_race = false
	if active and not is_host():
		_begin_clock_sync(0.5)   # re-measure between races (corrects crystal drift) while no course clock runs
	lobby_requested.emit()


func send_pose(pos: Vector3, vel: Vector3, grounded: bool) -> void:
	if active and multiplayer.get_peers().size() > 0:
		_pose.rpc(pos, vel, grounded, _pose_seq)


## The local racer teleported (respawn, checkpoint skip): poses sent from now on carry a
## new sequence number, so everyone else snaps our ghost instead of sliding it back.
func note_teleport() -> void:
	_pose_seq = (_pose_seq + 1) % 256


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pose(pos: Vector3, vel: Vector3, grounded: bool, seq: int) -> void:
	racer_pose.emit(multiplayer.get_remote_sender_id(), pos, vel, grounded, seq)


func send_checkpoint(index: int) -> void:
	if active:
		_checkpoint.rpc(index, now())


## `at` is the racer's own session time at the checkpoint: stamping it on arrival would
## let every peer rank itself first in a near-tie.
@rpc("any_peer", "call_local", "reliable")
func _checkpoint(index: int, at: float) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if roster.has(id) and index > int(roster[id]["cp"]):
		roster[id]["cp"] = index
		roster[id]["cp_at"] = at
		roster_changed.emit()


func send_finished(time: float) -> void:
	if active:
		_finished.rpc(time)


@rpc("any_peer", "call_local", "reliable")
func _finished(time: float) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if roster.has(id) and float(roster[id]["finished"]) < 0.0:
		roster[id]["finished"] = time
		roster_changed.emit()
		racer_finished.emit(id, time)


## Roster ids ordered by race standing: finished (by time), then checkpoint count,
## then who reached that checkpoint first.
func standings() -> Array[int]:
	var ids: Array[int] = []
	for id: int in roster:
		ids.append(id)
	ids.sort_custom(func(a: int, b: int) -> bool:
		var fa: float = float(roster[a]["finished"])
		var fb: float = float(roster[b]["finished"])
		if fa >= 0.0 or fb >= 0.0:
			if fa >= 0.0 and fb >= 0.0:
				return fa < fb
			return fa >= 0.0
		if int(roster[a]["cp"]) != int(roster[b]["cp"]):
			return int(roster[a]["cp"]) > int(roster[b]["cp"])
		var ta: float = float(roster[a].get("cp_at", 0.0))
		var tb: float = float(roster[b].get("cp_at", 0.0))
		if ta != tb:
			return ta < tb
		return a < b)
	return ids


func all_finished() -> bool:
	for id: int in roster:
		if float(roster[id]["finished"]) < 0.0:
			return false
	return not roster.is_empty()


# ---- helpers for the lobby screen ---------------------------------------------------

func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for addr: String in IP.get_local_addresses():
		if addr.contains(":") or addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		out.append(addr)
	return out


## Best-effort automatic port forward so friends can join over the internet.
## Runs once per hosting session; the outcome is cached in upnp_text.
func try_upnp() -> void:
	if not upnp_enabled:
		upnp_result.emit("Automatic port forwarding is off (UDP %d)." % PORT)
		return
	if _upnp_thread != null or upnp_text != "":
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker)


## Worker thread: writes no Net state. Returns [text, UPNP-with-a-mapping or null],
## which the main thread collects through wait_to_finish().
func _upnp_worker() -> Array:
	var u := UPNP.new()
	var text: String = "No automatic port forwarding: forward UDP %d on the router, or share a LAN/VPN address." % PORT
	var mapped: UPNP = null
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_device_count() > 0 and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
		if u.add_port_mapping(PORT, PORT, "Jump Circuit", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
			text = "Internet address: %s  (UDP %d opened via UPnP)" % [u.query_external_address(), PORT]
			mapped = u
	_upnp_done.call_deferred()
	return [text, mapped]


func _upnp_done() -> void:
	if _upnp_thread == null:
		return
	var res: Array = _upnp_thread.wait_to_finish()
	_upnp_thread = null
	var u: UPNP = res[1] as UPNP
	if is_host():
		upnp_text = str(res[0])
		if u != null:
			_upnp = u            # still hosting: keep it, _shutdown removes it on leave
	elif u != null:
		u.delete_port_mapping(PORT, "UDP")   # the host left while discovery was running
	upnp_result.emit(str(res[0]))


func _exit_tree() -> void:
	# never quit with the discovery thread still running, nor leave its mapping behind
	if _upnp_thread != null:
		var res: Array = _upnp_thread.wait_to_finish()
		_upnp_thread = null
		var u: UPNP = res[1] as UPNP
		if u != null:
			u.delete_port_mapping(PORT, "UDP")
	if _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
