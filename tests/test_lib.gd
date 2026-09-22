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


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  ok    ", what)
	else:
		failed += 1
		print("  FAIL  ", what)


func near(value: float, expected: float, tol: float, what: String) -> void:
	check(absf(value - expected) <= tol, "%s  (got %.3f, want %.3f +/- %.3f)" % [what, value, expected, tol])


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
