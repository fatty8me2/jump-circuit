class_name TestLib
extends Node
## Tiny async test harness. Tests drive a real Player in a real Jolt world
## through the same cmd_* interface a bot would use.

var passed: int = 0
var failed: int = 0
var metrics: Dictionary = {}
var world: Node3D
var player: Player
var kit: LevelKit
## Records engine/script errors once installed with OS.add_logger (run_tests._ready does).
var trap := ErrorTrap.new()


## Collects every non-warning engine/script error. A runtime error only aborts the
## function it happens in, so without this a test that errors out still reads as green.
class ErrorTrap extends Logger:
	var errors: PackedStringArray = []
	## Errors the current test triggers on purpose (see TestLib.expect_errors).
	var expected: int = 0
	var _mutex := Mutex.new()

	## Can be called from worker threads: keep it trivial (no print, nothing that can error).
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var where: String = "%s:%d" % [file, line]
		if not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
			where = "%s:%d" % [script_backtraces[0].get_frame_file(0), script_backtraces[0].get_frame_line(0)]
		_mutex.lock()
		errors.append("%s @ %s" % [rationale if rationale != "" else code, where])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n: int = errors.size()
		_mutex.unlock()
		return n

	## The errors logged after the first `from` ones, joined for a FAIL line.
	func since(from: int) -> String:
		_mutex.lock()
		var s: String = "; ".join(errors.slice(from))
		_mutex.unlock()
		return s


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  ok    ", what)
	else:
		failed += 1
		print("  FAIL  ", what)


func near(value: float, expected: float, tol: float, what: String) -> void:
	check(absf(value - expected) <= tol, "%s  (got %.3f, want %.3f +/- %.3f)" % [what, value, expected, tol])


## For a test that triggers engine errors on purpose (e.g. feeding a malformed save):
## declares how many, so the runner's "no unexpected errors" check still passes.
func expect_errors(n: int) -> void:
	trap.expected += n


## Awaits physics ticks until cond() is true. On timeout records a FAIL and returns false.
## Lambdas capture locals by value: loops that update a local (apex, peak) use overdue() instead.
func wait_until(cond: Callable, timeout_s: float, what: String) -> bool:
	var limit: int = int(ceil(timeout_s * Engine.physics_ticks_per_second))
	for i: int in limit:
		if cond.call():
			return true
		await get_tree().physics_frame
	if cond.call():
		return true
	check(false, "timed out after %.1fs waiting for %s" % [timeout_s, what])
	return false


## Tick budget for a hand-written wait loop: true (and a FAIL) once `timeout_s` of physics
## time has passed since `since_frame` (an Engine.get_physics_frames() value).
func overdue(since_frame: int, timeout_s: float, what: String) -> bool:
	if Engine.get_physics_frames() - since_frame > int(timeout_s * Engine.physics_ticks_per_second):
		check(false, "timed out after %.1fs waiting for %s" % [timeout_s, what])
		return true
	return false


func ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await ticks(int(round(s * Engine.physics_ticks_per_second)))


## Fresh empty world with a Player standing at `at`. Floor is added by the test.
func new_world(at: Vector3 = Vector3(0, 0.05, 0)) -> void:
	if world != null:
		world.queue_free()
		await ticks(2)
	Game.course_time = 0.0
	Game.course_running = true
	Game.race_mode = false
	Look.use_theme("gardens")
	world = Node3D.new()
	add_child(world)
	kit = LevelKit.new(world, 7)
	player = (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	player.use_device_input = false
	world.add_child(player)
	player.teleport(Transform3D(Basis(), at))


func floor_slab(size: Vector3 = Vector3(200, 1, 200), top: Vector3 = Vector3.ZERO) -> void:
	kit.plat(top, size, "main", 0.0)


func settle() -> void:
	player.cmd_move = Vector2.ZERO
	player.cmd_jump = false
	await seconds(0.4)


func tap_jump(hold_seconds: float) -> void:
	player.press_jump()
	player.cmd_jump = true
	await seconds(hold_seconds)
	player.cmd_jump = false


## Waits until the player lands (or timeout). Returns airtime in seconds.
func wait_landing(timeout: float = 6.0) -> float:
	var t: float = 0.0
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	# first leave the ground
	while player.grounded and t < 0.5:
		await get_tree().physics_frame
		t += dt
	while not player.grounded and t < timeout:
		await get_tree().physics_frame
		t += dt
	return t
