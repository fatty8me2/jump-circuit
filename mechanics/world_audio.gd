class_name WorldAudio
extends RefCounted
## Machine and world sounds: a thin layer over Sfx that keeps them cheap and out of the way.
##  * Headless runs (tests, bots, route checks) get nothing: no emitter is created and no clip
##    plays, so the physics-only runs pay nothing per frame.
##  * One-shots only play when the camera (the listener) is close enough to hear them, so a
##    level full of lasers switching far away never fills the 16-voice positional pool.
##  * Loops are attached emitters (Sfx.loop_at) with a gate that pauses them while the
##    listener is out of their range or the machine is idle, checked five times a second.
## Everything here is a side effect: gameplay never reads any of it back, and no mechanic's
## state or timing depends on it (obstacles stay pure functions of Game.course_time).

static var _enabled: int = -1


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if DisplayServer.get_name() == "headless" else 1
	return _enabled == 1


## Where the listener is (the active camera), or Vector3.INF when there is none.
static func listener(node: Node) -> Vector3:
	if node == null or not node.is_inside_tree():
		return Vector3.INF
	var cam: Camera3D = node.get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.INF


## True when a sound at `pos` would be heard (the listener is within `radius`).
static func hears(node: Node, pos: Vector3, radius: float) -> bool:
	if not enabled():
		return false
	var l: Vector3 = listener(node)
	return l != Vector3.INF and l.distance_squared_to(pos) < radius * radius


## A positional one-shot at `pos`, only when someone is near enough to hear it.
static func at(node: Node, clip: String, pos: Vector3, volume: float = 1.0, radius: float = 40.0,
		pitch_var: float = 0.05) -> void:
	if hears(node, pos, radius):
		Sfx.play_at(clip, pos, pitch_var, volume)


## The local person's Player in the level `node` belongs to (null outside a level).
static func local_player(node: Node) -> Node3D:
	var n: Node = node
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n == null:
		return null
	return n.get("player") as Node3D


static var _last_played: Dictionary = {}


## False if `key` already sounded within `secs` (several identical machines firing on the same
## beat play it once instead of stacking into a phasey, over-loud copy of the same clip).
static func once(key: String, secs: float) -> bool:
	var now: int = Time.get_ticks_msec()
	if now - int(_last_played.get(key, -1000000)) < int(secs * 1000.0):
		return false
	_last_played[key] = now
	return true


## A gated looping emitter on `parent` (null when headless or the clip is missing). Starts at a
## random point in the loop so identical machines side by side don't phase against each other.
## Drive it with set_active(); change volume_db / pitch_scale on it directly.
static func loop(clip: String, parent: Node3D, volume_db: float = 0.0, max_distance: float = 25.0,
		unit_size: float = 5.0, active: bool = true) -> AudioStreamPlayer3D:
	if not enabled() or parent == null:
		return null
	var p: AudioStreamPlayer3D = Sfx.loop_at(clip, parent, volume_db, max_distance, unit_size)
	if p == null:
		return null
	p.set_meta("want", active)
	var length: float = p.stream.get_length()
	if p.playing and length > 0.0:
		p.seek(randf() * length)
	var gate := Gate.new()
	gate.player = p
	p.add_child(gate)
	Gate.apply(p)
	return p


## Whether the machine wants its loop running (it still only plays while in earshot).
static func set_active(p: AudioStreamPlayer3D, on: bool) -> void:
	if p == null:
		return
	if bool(p.get_meta("want", true)) != on:
		p.set_meta("want", on)
		Gate.apply(p)


## Pauses its loop while the machine is idle or the listener is out of range. Re-applies after
## the game is unpaused (the engine un-pauses every stream it paused, idle machines included).
class Gate extends Timer:
	var player: AudioStreamPlayer3D

	func _ready() -> void:
		wait_time = randf_range(0.18, 0.24)
		timeout.connect(func() -> void: Gate.apply(player))
		start()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_UNPAUSED:
			_reapply.call_deferred()

	func _reapply() -> void:
		Gate.apply(player)

	static func apply(p: AudioStreamPlayer3D) -> void:
		if p == null or not is_instance_valid(p) or not p.is_inside_tree():
			return
		var run: bool = bool(p.get_meta("want", true))
		if run:
			var l: Vector3 = WorldAudio.listener(p)
			run = l != Vector3.INF and l.distance_to(p.global_position) < p.max_distance + 2.0
		if p.stream_paused == run:
			p.stream_paused = not run
