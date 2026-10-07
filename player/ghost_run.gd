class_name GhostRun
extends Node
## Solo ghost replays, owned by a LevelBase (only ever created for a plain solo run: never
## in Party Mode or a race). It records the local run at GhostData.HZ off the course clock
## and, when Settings.ghost_mode asks for it, replays the saved personal best as a
## translucent RemoteRacer driven by the same clock.

const TINT: Color = Color(0.55, 0.85, 1.0)

var level: LevelBase
var recording: GhostData
## The ghost being replayed (null: none saved, or switched off).
var ghost: GhostData
var racer: RemoteRacer

var _next_t: float = 0.0
var _snap_pending: bool = true
var _seq: int = 0
var _last_t: float = 0.0
var _ended_for: float = 0.0
var _celebrated: bool = false
var _full: bool = false
var _snap_idx: int = -1


func setup(p_level: LevelBase) -> void:
	level = p_level
	_reset_recording()
	level.player.teleported.connect(func() -> void: _snap_pending = true)
	apply_setting()


## Ghosts exist only in a plain solo run on a real course.
static func allowed() -> bool:
	return Game.party == null and not Game.race_mode and not Net.active and Game.level_index >= 0


func _reset_recording() -> void:
	recording = GhostData.new()
	recording.level_id = level.level_id
	recording.rev = GhostData.current_rev(level.level_id)
	_next_t = 0.0
	_snap_pending = true
	_full = false


## Shows or hides the replay to match Settings.ghost_mode (the pause menu calls this live).
func apply_setting() -> void:
	if Settings.ghost_mode == Settings.GHOST_PB:
		if ghost == null:
			ghost = GhostData.load_for(level.level_id)
		if ghost != null and racer == null:
			racer = RemoteRacer.new()
			level.add_child(racer)
			racer.make_ghost("PB  " + SaveData.format_time(ghost.time), TINT)
			racer.visible = false
			_last_t = -1.0
	elif racer != null:
		racer.queue_free()
		racer = null
	set_process(racer != null)


func _physics_process(_dt: float) -> void:
	if level.finished or level.player == null:
		return
	var t: float = Game.course_time
	if t < _next_t - 2.0 / GhostData.HZ - 0.01:
		_reset_recording()   # the run was restarted: the clock went back
	if t < _next_t or _full:
		return
	if recording.size() >= GhostData.MAX_SAMPLES:
		_full = true
		return
	_sample_player()
	_next_t += 1.0 / GhostData.HZ
	# a long stall: don't queue a burst of identical samples
	if _next_t < t - 0.5:
		_next_t = t + 1.0 / GhostData.HZ


func _sample_player() -> void:
	var p: Player = level.player
	recording.add(p.global_position, GhostData.yaw_of(p.facing_dir), p.grounded, p.is_wall_running(), _snap_pending, p.net_move_flags())
	_snap_pending = false


## The run ended on the finish line at `time`: the finished recording (null if it is unusable).
func finish_recording(time: float) -> GhostData:
	if _full or level.player == null:
		return null
	_sample_player()
	recording.time = time
	return recording if recording.size() >= 2 else null


## Saves the finished run as the level's ghost (call on a new personal best only).
func save_best(time: float) -> bool:
	var g: GhostData = finish_recording(time)
	if g == null:
		return false
	var ok: bool = g.save()
	if ok:
		ghost = g
		if racer != null:
			racer.queue_free()
			racer = null
		apply_setting()
	return ok


func _process(dt: float) -> void:
	if racer == null or ghost == null:
		return
	var t: float = Game.course_time + Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second)
	if t < _last_t - 0.25:
		_celebrated = false   # the run restarted: the ghost goes back to the start
		_seq += 1
		_snap_idx = -1
	_last_t = t
	var s: Dictionary = ghost.sample(t)
	if s["ended"]:
		if not _celebrated:
			_celebrated = true
			_ended_for = 0.0
			racer.celebrate()
		_ended_for += dt
		racer.visible = _ended_for < 2.5
	else:
		racer.visible = true
	var v: Vector3 = s["vel"]
	var idx: int = floori(t * GhostData.HZ)
	if bool(s["snap"]) and idx != _snap_idx:
		_snap_idx = idx   # the pose jumps here once (respawn): the ghost respawns too
		_seq += 1
	racer.push_state(s["pos"], v, bool(s["grounded"]) or bool(s["wall"]), _seq, int(s["moves"]))
	racer.set_exact_facing(GhostData.facing_of(float(s["yaw"])))
