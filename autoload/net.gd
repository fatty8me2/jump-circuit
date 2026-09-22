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
signal racer_pose(id: int, pos: Vector3, vel: Vector3, grounded: bool)
signal racer_finished(id: int, time: float)
signal lobby_requested
signal upnp_result(text: String)

const PORT: int = 24565
const MAX_PLAYERS: int = 8

var active: bool = false
## peer id -> {"name": String, "color": int, "cp": int, "finished": float (-1 = still racing)}
var roster: Dictionary = {}
var race_level: int = -1
var race_start_time: float = 0.0
var in_race: bool = false

var _clock_offset: float = 0.0
var _best_rtt: float = 999.0
var _ping_timer: float = 0.0
var _pings_left: int = 0
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
	var err: Error = peer.create_server(port, MAX_PLAYERS - 1)
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
	_clock_offset = 0.0
	roster_changed.emit()


func _my_entry() -> Dictionary:
	return {"name": Settings.player_name, "color": Settings.color_index, "cp": 0, "finished": -1.0}


func _on_connected() -> void:
	_pings_left = 8
	_ping_timer = 0.0
	_register.rpc_id(1, Settings.player_name, Settings.color_index)


func _on_peer_disconnected(id: int) -> void:
	if roster.has(id):
		roster.erase(id)
		roster_changed.emit()
	if is_host():
		_sync_roster.rpc(roster)


func _process(dt: float) -> void:
	if active and not is_host() and _pings_left > 0:
		_ping_timer -= dt
		if _ping_timer <= 0.0:
			_ping_timer = 0.25
			_pings_left -= 1
			_ping.rpc_id(1, _local_time())


# ---- lobby RPCs -----------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, color: int) -> void:
	if not is_host():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if in_race and not roster.has(id):
		_kick.rpc_id(id, "A race is in progress - try again in a moment.")
		return
	var entry: Dictionary = roster.get(id, {"cp": 0, "finished": -1.0})
	entry["name"] = player_name.substr(0, 14)
	entry["color"] = color
	roster[id] = entry
	_sync_roster.rpc(roster)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _kick(reason: String) -> void:
	_shutdown()
	connection_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	var first: bool = roster.is_empty()
	roster = new_roster
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
	if not active:
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
	race_level = level_index
	race_start_time = start_time
	in_race = true
	for id: int in roster:
		roster[id]["cp"] = 0
		roster[id]["finished"] = -1.0
	race_starting.emit(level_index, start_time)


func host_return_to_lobby() -> void:
	if is_host():
		_return_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _return_to_lobby() -> void:
	in_race = false
	lobby_requested.emit()


func send_pose(pos: Vector3, vel: Vector3, grounded: bool) -> void:
	if active and multiplayer.get_peers().size() > 0:
		_pose.rpc(pos, vel, grounded)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pose(pos: Vector3, vel: Vector3, grounded: bool) -> void:
	racer_pose.emit(multiplayer.get_remote_sender_id(), pos, vel, grounded)


func send_checkpoint(index: int) -> void:
	if active:
		_checkpoint.rpc(index)


@rpc("any_peer", "call_local", "reliable")
func _checkpoint(index: int) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if roster.has(id):
		roster[id]["cp"] = maxi(int(roster[id]["cp"]), index)
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


## Roster ids ordered by race standing: finished (by time), then checkpoint count.
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
func try_upnp() -> void:
	if _upnp_thread != null:
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker)


func _upnp_worker() -> void:
	var u := UPNP.new()
	var text: String = "No automatic port forwarding: forward UDP %d on the router, or share a LAN/VPN address." % PORT
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_device_count() > 0 and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
		if u.add_port_mapping(PORT, PORT, "Jump Circuit", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
			text = "Internet address: %s  (UDP %d opened via UPnP)" % [u.query_external_address(), PORT]
			_upnp = u
	_upnp_done.call_deferred(text)


func _upnp_done(text: String) -> void:
	if _upnp_thread == null:
		return
	_upnp_thread.wait_to_finish()
	_upnp_thread = null
	upnp_result.emit(text)


func _exit_tree() -> void:
	# never quit with the discovery thread still running
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
