extends Node
## Multiplayer racing over a room-code WebSocket relay, with ENet retained for local/dev tests.
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
const ROOM_CODE_ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
## A relay join still unanswered after this many seconds is reported as unreachable.
const CONNECT_TIMEOUT: float = 10.0

var active: bool = false
## peer id -> {"name": String, "color": int, "cp": int, "finished": float (-1 = still racing),
## "cp_at": float (session time that checkpoint was reached; breaks standings ties)}
var roster: Dictionary = {}
var race_level: int = -1
var race_start_time: float = 0.0
var in_race: bool = false
## Kept for compatibility with the existing local integration harness; room-code play does not use UPnP.
var upnp_enabled: bool = true
## Compatibility text for older menu code.
var upnp_text: String = ""
## The player's own colour while the host has them wearing another one (-1 = none).
## Settings saves this instead of the session colour, and it returns when the session ends.
var preferred_color: int = -1
## Share this short code with friends. The host creates it and the relay routes its sockets.
var room_code: String = ""

var _clock_offset: float = 0.0
var _best_rtt: float = 999.0
var _ping_timer: float = 0.0
var _pings_left: int = 0
var _connect_left: float = -1.0
var _join_port: int = PORT
var _pose_seq: int = 0
var _relay_mode: bool = false
var _relay_host: bool = false
var _relay_peer_id: int = 1
var _relay_ready: bool = false
var _relay_socket: WebSocketPeer
var _relay_connect_left: float = -1.0


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
	return _relay_peer_id if _relay_mode else (multiplayer.get_unique_id() if active else 1)


func is_host() -> bool:
	return _relay_host if _relay_mode else (active and multiplayer.is_server())


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


## Opens a room through the hosted WebSocket relay. This works without router or VPN setup.
func host_room() -> Error:
	leave()
	var code := _new_room_code()
	var url := _relay_url(code, "host")
	if url == "":
		return FAILED
	room_code = code
	return _start_relay(url)


## Joins a room created by `host_room()` using its short share code.
func join_room(code: String) -> Error:
	leave()
	var clean := _clean_room_code(code)
	if not _valid_room_code(clean):
		return ERR_INVALID_PARAMETER
	var url := _relay_url(clean, "join")
	if url == "":
		return FAILED
	room_code = clean
	return _start_relay(url)


func _start_relay(url: String) -> Error:
	_relay_socket = WebSocketPeer.new()
	var err: Error = _relay_socket.connect_to_url(url)
	if err != OK:
		_relay_socket = null
		return err
	_relay_mode = true
	_relay_host = false
	_relay_peer_id = 1
	_relay_ready = false
	_relay_connect_left = CONNECT_TIMEOUT
	active = true
	return OK


func _relay_url(code: String, role: String) -> String:
	var base := str(ProjectSettings.get_setting("network/relay_url", "")).strip_edges().trim_suffix("/")
	if base == "" or base.contains("YOUR_SUBDOMAIN"):
		return ""
	return "%s/ws?room=%s&role=%s" % [base, code.uri_encode(), role]


func _new_room_code() -> String:
	var code := ""
	for _i: int in 8:
		code += ROOM_CODE_ALPHABET[randi() % ROOM_CODE_ALPHABET.length()]
	return code


func _clean_room_code(raw: String) -> String:
	return raw.strip_edges().to_upper().replace(" ", "").replace("-", "")


func _valid_room_code(code: String) -> bool:
	if code.length() != 8:
		return false
	for i: int in code.length():
		if not ROOM_CODE_ALPHABET.contains(code.substr(i, 1)):
			return false
	return true


func leave() -> void:
	if active:
		_shutdown()


func _shutdown() -> void:
	if _relay_socket != null and _relay_socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_relay_socket.close(1000, "Leaving session")
	_relay_socket = null
	_relay_mode = false
	_relay_host = false
	_relay_peer_id = 1
	_relay_ready = false
	_relay_connect_left = -1.0
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
	room_code = ""
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
	if _relay_mode:
		_process_relay(dt)
		return
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


func _process_relay(dt: float) -> void:
	if _relay_socket == null:
		return
	_relay_socket.poll()
	var state := _relay_socket.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		_relay_connect_left -= dt
		if _relay_connect_left <= 0.0:
			_shutdown()
			connection_failed.emit("Could not reach the Jump Circuit relay. Check your internet connection and relay URL.")
		return
	if state == WebSocketPeer.STATE_OPEN:
		_relay_connect_left = -1.0
		while _relay_socket.get_available_packet_count() > 0:
			var message := _relay_socket.get_packet().get_string_from_utf8()
			_handle_relay_packet(message)
			if not _relay_mode or _relay_socket == null:
				return
		if _relay_ready and not is_host() and _pings_left > 0:
			_ping_timer -= dt
			if _ping_timer <= 0.0:
				_ping_timer = 0.25
				_pings_left -= 1
				_relay_send_event("ping", {"client_time": _local_time()}, 1)
				if _pings_left == 0 and _best_rtt >= 999.0:
					_pings_left = 8
		return
	if state == WebSocketPeer.STATE_CLOSED and _relay_mode:
		var reason := _relay_socket.get_close_reason()
		var was_ready := _relay_ready
		_shutdown()
		if was_ready:
			left_session.emit(reason if reason != "" else "The relay connection closed.")
		else:
			connection_failed.emit(reason if reason != "" else "Could not connect to the room. Check the code and try again.")


func _handle_relay_packet(message: String) -> void:
	var decoded: Variant = JSON.parse_string(message)
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var packet: Dictionary = decoded
	match str(packet.get("type", "")):
		"welcome":
			if _relay_ready:
				return
			_relay_peer_id = int(packet.get("id", 0))
			if _relay_peer_id < 1 or _relay_peer_id > MAX_PLAYERS:
				_shutdown()
				connection_failed.emit("The relay returned an invalid player id.")
				return
			_relay_host = _relay_peer_id == 1
			_relay_ready = true
			_relay_connect_left = -1.0
			room_code = str(packet.get("room", room_code))
			_clock_offset = 0.0
			if _relay_host:
				roster = {1: _my_entry()}
				roster_changed.emit()
				joined_lobby.emit()
			else:
				_begin_clock_sync()
				_relay_send_event("register", {"name": Settings.player_name, "color": Settings.color_index}, 1)
		"error":
			var error_reason := str(packet.get("reason", "The relay rejected the room connection."))
			_shutdown()
			connection_failed.emit(error_reason)
		"closed":
			var closed_reason := str(packet.get("reason", "The host closed the session."))
			_shutdown()
			left_session.emit(closed_reason)
		"peer_left":
			if is_host():
				var id := int(packet.get("id", 0))
				if roster.erase(id):
					roster_changed.emit()
					_broadcast_roster()
		"event":
			_handle_relay_event(int(packet.get("from", 0)), str(packet.get("event", "")), packet.get("data", {}))


func _handle_relay_event(from_id: int, event: String, raw_data: Variant) -> void:
	if typeof(raw_data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = raw_data
	match event:
		"register":
			if is_host():
				_register_player(from_id, str(data.get("name", "Runner")), int(data.get("color", 0)))
		"roster":
			if not is_host():
				_sync_roster(_roster_from_wire(data.get("players", [])))
		"kick":
			if from_id == 1 and not is_host():
				_shutdown()
				connection_failed.emit(str(data.get("reason", "The host removed you from the race.")))
		"ping":
			if is_host():
				_relay_send_event("pong", {
					"client_time": float(data.get("client_time", 0.0)),
					"server_time": _local_time(),
				}, from_id)
		"pong":
			if from_id == 1:
				_apply_pong(float(data.get("client_time", 0.0)), float(data.get("server_time", 0.0)))
		"start_race":
			if from_id == 1:
				_start_race(int(data.get("level_index", -1)), float(data.get("start_time", 0.0)))
		"return_lobby":
			if from_id == 1:
				_return_to_lobby()
		"pose":
			var p: Array = data.get("pos", [])
			var v: Array = data.get("vel", [])
			if p.size() == 3 and v.size() == 3:
				_emit_pose(from_id, Vector3(float(p[0]), float(p[1]), float(p[2])),
					Vector3(float(v[0]), float(v[1]), float(v[2])), bool(data.get("grounded", false)), int(data.get("seq", 0)))
		"checkpoint":
			_apply_checkpoint(from_id, int(data.get("index", 0)), float(data.get("at", 0.0)))
		"finished":
			_apply_finished(from_id, float(data.get("time", 0.0)))


func _relay_send_event(event: String, data: Dictionary, to_id: int = 0) -> void:
	if _relay_socket == null or _relay_socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var packet: Dictionary = {"type": "event", "event": event, "data": data}
	if to_id > 0:
		packet["to"] = to_id
	_relay_socket.send_text(JSON.stringify(packet))


func _broadcast_roster() -> void:
	if _relay_mode:
		_relay_send_event("roster", {"players": _roster_to_wire()})
	else:
		_sync_roster.rpc(roster)


func _roster_to_wire() -> Array[Dictionary]:
	var players: Array[Dictionary] = []
	var ids: Array = roster.keys()
	ids.sort()
	for id: int in ids:
		players.append({"id": id, "entry": roster[id]})
	return players


func _roster_from_wire(raw_players: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(raw_players) != TYPE_ARRAY:
		return result
	for raw_player: Variant in raw_players:
		if typeof(raw_player) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = raw_player
		var id := int(player.get("id", 0))
		var entry: Variant = player.get("entry", {})
		if id > 0 and typeof(entry) == TYPE_DICTIONARY:
			result[id] = entry
	return result


# ---- lobby RPCs -----------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, color: int) -> void:
	_register_player(multiplayer.get_remote_sender_id(), player_name, color)


func _register_player(id: int, player_name: String, color: int) -> void:
	if not is_host():
		return
	if in_race and not roster.has(id):
		var race_reason := "A race is in progress - try again in a moment."
		if _relay_mode:
			_relay_send_event("kick", {"reason": race_reason}, id)
		else:
			_kick.rpc_id(id, race_reason)
		return
	# (existing racers re-register on every name / colour change - only newcomers can be turned away)
	if not roster.has(id) and roster.size() >= MAX_PLAYERS:
		var full_reason := "That race is full (%d/%d)." % [roster.size(), MAX_PLAYERS]
		if _relay_mode:
			_relay_send_event("kick", {"reason": full_reason}, id)
		else:
			_kick.rpc_id(id, full_reason)
		return
	var joining: bool = not roster.has(id)
	var entry: Dictionary = roster.get(id, {"cp": 0, "finished": -1.0})
	entry["name"] = player_name.substr(0, 14)
	# a newcomer gets a colour nobody else wears; later explicit picks are honoured
	entry["color"] = _free_color(id, color) if joining else posmod(color, Settings.RACER_COLORS.size())
	roster[id] = entry
	_broadcast_roster()
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
	_apply_pong(client_time, server_time)


func _apply_pong(client_time: float, server_time: float) -> void:
	var rtt: float = _local_time() - client_time
	if rtt < _best_rtt:
		_best_rtt = rtt
		_clock_offset = server_time + rtt * 0.5 - _local_time()


func update_identity() -> void:
	if _relay_mode:
		if not _relay_ready:
			return
		if is_host():
			if roster.has(1):
				roster[1]["name"] = Settings.player_name
				roster[1]["color"] = Settings.color_index
				_broadcast_roster()
				roster_changed.emit()
		else:
			_relay_send_event("register", {"name": Settings.player_name, "color": Settings.color_index}, 1)
		return
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
	if _relay_mode and is_host() and _relay_ready:
		var start_time := now() + countdown
		_start_race(level_index, start_time)
		_relay_send_event("start_race", {"level_index": level_index, "start_time": start_time})
	elif is_host():
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
	if _relay_mode and is_host() and _relay_ready:
		_return_to_lobby()
		_relay_send_event("return_lobby", {})
	elif is_host():
		_return_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _return_to_lobby() -> void:
	if not is_host() and not roster.has(my_id()):
		return
	in_race = false
	if active and not is_host() and not _relay_mode:
		_begin_clock_sync(0.5)   # re-measure between races (corrects crystal drift) while no course clock runs
	elif active and not is_host() and _relay_mode:
		_begin_clock_sync(0.5)
	lobby_requested.emit()


func send_pose(pos: Vector3, vel: Vector3, grounded: bool) -> void:
	if _relay_mode:
		if active and roster.size() > 1:
			_relay_send_event("pose", {
				"pos": [pos.x, pos.y, pos.z],
				"vel": [vel.x, vel.y, vel.z],
				"grounded": grounded,
				"seq": _pose_seq,
			})
		return
	if active and multiplayer.get_peers().size() > 0:
		_pose.rpc(pos, vel, grounded, _pose_seq)


## The local racer teleported (respawn, checkpoint skip): poses sent from now on carry a
## new sequence number, so everyone else snaps our ghost instead of sliding it back.
func note_teleport() -> void:
	_pose_seq = (_pose_seq + 1) % 256


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pose(pos: Vector3, vel: Vector3, grounded: bool, seq: int) -> void:
	_emit_pose(multiplayer.get_remote_sender_id(), pos, vel, grounded, seq)


func _emit_pose(id: int, pos: Vector3, vel: Vector3, grounded: bool, seq: int) -> void:
	if roster.has(id):
		racer_pose.emit(id, pos, vel, grounded, seq)


func send_checkpoint(index: int) -> void:
	if _relay_mode and active:
		var at := now()
		_apply_checkpoint(my_id(), index, at)
		_relay_send_event("checkpoint", {"index": index, "at": at})
	elif active:
		_checkpoint.rpc(index, now())


## `at` is the racer's own session time at the checkpoint: stamping it on arrival would
## let every peer rank itself first in a near-tie.
@rpc("any_peer", "call_local", "reliable")
func _checkpoint(index: int, at: float) -> void:
	_apply_checkpoint(multiplayer.get_remote_sender_id(), index, at)


func _apply_checkpoint(id: int, index: int, at: float) -> void:
	if roster.has(id) and index > int(roster[id]["cp"]):
		roster[id]["cp"] = index
		roster[id]["cp_at"] = at
		roster_changed.emit()


func send_finished(time: float) -> void:
	if _relay_mode and active:
		_apply_finished(my_id(), time)
		_relay_send_event("finished", {"time": time})
	elif active:
		_finished.rpc(time)


@rpc("any_peer", "call_local", "reliable")
func _finished(time: float) -> void:
	_apply_finished(multiplayer.get_remote_sender_id(), time)


func _apply_finished(id: int, time: float) -> void:
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


# ---- router-free lobby ------------------------------------------------------------

## Retained as a no-op for older menu code; room-code sessions need no router mapping.
func try_upnp() -> void:
	upnp_text = "Room-code relay is used; no router setup is needed."
	upnp_result.emit(upnp_text)
