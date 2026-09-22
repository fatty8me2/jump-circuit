class_name LevelBase
extends Node3D
## Shared level runtime. A concrete level overrides _build() and composes its
## course with `kit`. Everything else - spawning, checkpoints, fast failure and
## respawn, physics-object resets, the run timer, finish, race ghosts - lives here.

signal level_finished(time: float)
signal player_respawned

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var level_id: String = "playground"
var theme_id: String = "gardens"
var music_track: String = "a"
## Absolute floor of the world.
var kill_y: float = -60.0
## Falling this far below the last footing (with nothing underneath) is a fail.
var fall_margin: float = 11.0

var kit: LevelKit
var player: Player
var camera: OrbitCamera
var hud: Hud
var checkpoints: Array[Checkpoint] = []
var current_checkpoint: int = 0
var finished: bool = false
var run_time: float = 0.0
var deaths: int = 0
## Set false by automated tests to skip HUD/camera/audio side effects.
var headless_mode: bool = false

var _spawn: Transform3D = Transform3D.IDENTITY
var _respawning: bool = false
var _started: bool = false
var _pose_tick: int = 0
var _ghosts: Dictionary = {}
var _pause: PauseMenu


func _ready() -> void:
	headless_mode = DisplayServer.get_name() == "headless"
	var info: Dictionary = Game.level_info()
	if Game.level_index >= 0:
		level_id = info["id"]
	_configure()
	Look.use_theme(theme_id)
	Look.build_environment(self)
	kit = LevelKit.new(self, hash(level_id))
	_build()
	_collect_checkpoints()
	_spawn_player()
	if not headless_mode:
		Sfx.music(music_track)
	if Game.race_mode:
		_setup_race()
	else:
		_begin_run()


## Override: set level_id/theme_id/kill_y etc.
func _configure() -> void:
	pass


## Override: build the course with `kit`. Must call set_spawn() and place a finish.
func _build() -> void:
	pass


func set_spawn(pos: Vector3, yaw_deg: float = 0.0) -> void:
	_spawn = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)


func _collect_checkpoints() -> void:
	checkpoints.clear()
	for node: Node in find_children("*", "Checkpoint", true, false):
		checkpoints.append(node as Checkpoint)
	for i: int in checkpoints.size():
		checkpoints[i].index = i + 1
		checkpoints[i].reached.connect(_on_checkpoint)
	for node: Node in find_children("*", "FinishGate", true, false):
		(node as FinishGate).reached.connect(_on_finish)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.connect_feedback()
	player.visual.set_accent(Settings.my_color())
	camera = OrbitCamera.new()
	add_child(camera)
	camera.target = player
	camera.current = true
	hud = Hud.new()
	add_child(hud)
	hud.level = self
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.level = self
	player.teleport(_spawn)
	camera.face(-_spawn.basis.z)
	if not headless_mode and not Game.shot_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _begin_run() -> void:
	_started = true
	run_time = 0.0
	player.control_enabled = true
	if Game.intro_shown_for != level_id:
		Game.intro_shown_for = level_id
		hud.show_intro(Game.level_info()["name"], Game.level_info().get("blurb", ""))


# ---- race -------------------------------------------------------------------------------

func _setup_race() -> void:
	player.control_enabled = false
	# fan racers out across the start so ghosts don't stack; every peer derives the
	# same slots from the same roster, so each ghost waits on its racer's real spot
	var ids: Array = Net.roster.keys()
	ids.sort()
	var base: Transform3D = _spawn
	for i: int in ids.size():
		var xf: Transform3D = base
		xf.origin += base.basis.x * ((float(i) - float(ids.size() - 1) * 0.5) * 1.3)
		if int(ids[i]) == Net.my_id():
			_spawn = xf
		else:
			_add_ghost(int(ids[i]), xf.origin)
	player.teleport(_spawn)
	player.teleported.connect(Net.note_teleport)
	Net.racer_pose.connect(_on_racer_pose)
	Net.roster_changed.connect(_on_roster_changed)
	Net.racer_finished.connect(func(id: int, time: float) -> void:
		if id != Net.my_id() and Net.roster.has(id) and is_inside_tree():
			hud.toast("%s finished - %s" % [Net.roster[id]["name"], SaveData.format_time(time)]))
	hud.start_countdown()


func _add_ghost(id: int, at: Vector3) -> void:
	var g := RemoteRacer.new()
	add_child(g)
	g.setup(str(Net.roster[id]["name"]), Settings.RACER_COLORS[int(Net.roster[id]["color"]) % Settings.RACER_COLORS.size()])
	g.global_position = at
	_ghosts[id] = g


func _on_racer_pose(id: int, pos: Vector3, vel: Vector3, grounded: bool, seq: int) -> void:
	# (poses still arrive for a moment after the scene change back to the lobby)
	if _ghosts.has(id) and is_inside_tree():
		(_ghosts[id] as RemoteRacer).push_state(pos, vel, grounded, seq)


func _on_roster_changed() -> void:
	if not is_inside_tree():
		return
	for id: int in _ghosts.keys():
		if not Net.roster.has(id):
			var g := _ghosts[id] as RemoteRacer
			# (Net.active is already false when it is us leaving or the session ending)
			if Net.active and g.racer_name != "":
				hud.toast("%s left the race" % g.racer_name)
			g.queue_free()
			_ghosts.erase(id)


# ---- main loop ------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if player == null:
		return
	if Game.race_mode:
		if not _started and Game.course_time >= 0.0:
			_started = true
			player.control_enabled = true
			hud.go()
		_pose_tick += 1
		if _pose_tick % 4 == 0:
			Net.send_pose(player.global_position, player.velocity, player.grounded)
	if _started and not finished:
		run_time = Game.course_time
		_check_failure()


func _unhandled_input(event: InputEvent) -> void:
	if finished or player == null:
		return
	if event.is_action_pressed("restart"):
		if current_checkpoint == 0 and not Game.race_mode and _started and Game.level_index >= 0:
			Game.restart_level()
		else:
			respawn()
	elif event.is_action_pressed("dev_next_checkpoint") and Game.dev_mode:
		if current_checkpoint < checkpoints.size():
			var cp: Checkpoint = checkpoints[current_checkpoint]
			player.teleport(cp.respawn_transform())


func _check_failure() -> void:
	if _respawning:
		return
	var p: Vector3 = player.global_position
	if p.y < kill_y:
		fail()
		return
	if not player.grounded and player.velocity.y < -4.0 and p.y < player.last_ground_y - fall_margin:
		# Anything solid still below? Then it's a legitimate drop, not a fall-out.
		var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -80.0, 0), 1)
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			fail()
		elif p.y < player.last_ground_y - fall_margin * 2.2:
			# something is down there, but it is so far below that the progress is
			# lost anyway - a quick respawn beats watching a 30 m fall.
			fail()


func fail() -> void:
	if _respawning or finished:
		return
	deaths += 1
	respawn()


## Instant, safe, correctly oriented. Local physics objects return to their start state.
func respawn() -> void:
	if finished:
		return
	_respawning = true
	var xf: Transform3D = _spawn
	if current_checkpoint > 0:
		xf = checkpoints[current_checkpoint - 1].respawn_transform()
	reset_dynamic_objects()
	player.teleport(xf)
	camera.face(-xf.basis.z)
	hud.flash()
	Sfx.play("respawn", 0.03, 0.7)
	player_respawned.emit()
	_respawning = false


func reset_dynamic_objects() -> void:
	for node: Node in get_tree().get_nodes_in_group("resettable"):
		if node.has_method("reset_state") and is_ancestor_of(node):
			node.call("reset_state")


func _on_checkpoint(cp: Checkpoint) -> void:
	if cp.index <= current_checkpoint or finished:
		return
	current_checkpoint = cp.index
	for other: Checkpoint in checkpoints:
		other.set_active(other.index == cp.index)
	Sfx.play("checkpoint")
	hud.toast("Checkpoint")
	if Game.race_mode:
		Net.send_checkpoint(cp.index)


func _on_finish() -> void:
	if finished:
		return
	finished = true
	player.control_enabled = false
	var time: float = run_time
	Sfx.play("finish")
	level_finished.emit(time)
	if Game.race_mode:
		Net.send_checkpoint(checkpoints.size() + 1)
		Net.send_finished(time)
		SaveData.record_finish(level_id, time, deaths)
		hud.show_race_results()
		return
	var prev_best: float = SaveData.best_time(level_id)
	var is_best: bool = false
	if Game.level_index >= 0:
		is_best = SaveData.record_finish(level_id, time, deaths)
	await _finish_sequence()
	hud.show_results(time, prev_best, is_best, deaths)


## Override for a bespoke ending (level 5's beacon).
func _finish_sequence() -> void:
	await get_tree().create_timer(0.6).timeout


# ---- route annotation ------------------------------------------------------------------------
# Levels describe their intended main path as a list of steps. The automated bot
# (tests/route_bot.gd) plays these steps with real physics, and the validator
# checks every jump against the measured capability envelope.

var route: Array[Dictionary] = []


func r_walk(to: Vector3) -> void:
	route.append({"kind": "walk", "to": to})


## Run to `from`, jump there, steer to `to`. hold=false makes it a tap jump.
func r_jump(from: Vector3, to: Vector3, hold: bool = true) -> void:
	route.append({"kind": "jump", "from": from, "to": to, "hold": hold})


## Step onto a bounce pad at `at`, then steer to `to`.
func r_pad(at: Vector3, to: Vector3) -> void:
	route.append({"kind": "pad", "from": at, "to": to})


## Stand still until `node` comes within `radius` of `point` (moving platforms).
func r_wait(node: Node3D, point: Vector3, radius: float = 1.0) -> void:
	route.append({"kind": "wait", "node": node, "point": point, "radius": radius})


## Like r_jump but the landing spot rides on `node` (offset in its local space).
func r_jump_onto(from: Vector3, node: Node3D, local_offset: Vector3 = Vector3.ZERO, hold: bool = true) -> void:
	route.append({"kind": "jump", "from": from, "to_node": node, "to_local": local_offset, "to": Vector3.ZERO, "hold": hold})


## Jump off whatever we are riding as soon as `node` is within radius of point.
## `stand` (optional) is where to wait on the ride, in the node's local space.
func r_jump_from_ride(node: Node3D, point: Vector3, radius: float, to: Vector3, hold: bool = true, stand: Variant = null) -> void:
	var step: Dictionary = {"kind": "ride_jump", "node": node, "point": point, "radius": radius, "to": to, "hold": hold}
	if stand != null:
		step["stand"] = stand
	route.append(step)


func r_checkpoint() -> void:
	route.append({"kind": "checkpoint"})
