extends LevelBase
## Test course for the generic obstacle kit, part 1 (test_zk_bot_slice1): launch barrel, zipline,
## cannonball lane, rolling log, seesaw. Not a real level - never in Game.LEVELS. It doubles as the
## worked example of how a level wires each obstacle into its route (docs/KIT_OBSTACLES.md).

var barrel: LaunchBarrel
var zip: Zipline
var battery: CannonBattery
var rolling: RollingLog
var saw: Seesaw


func _configure() -> void:
	level_id = "kit_test"
	theme_id = "orbital"
	kill_y = -30.0


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 2), 0.0)
	kit.plat(Vector3(0, 0, 0), Vector3(10, 2, 10))
	# 1. launch barrel: walk in, wait out the tell, get fired onto the next deck
	barrel = kit.barrel(Vector3(0, 0, -3), Vector3(0, 0, -17), 3.0, 3.0, 0.0)
	kit.plat(Vector3(0, 0, -17), Vector3(10, 1, 10))
	# 2. zipline: a 26 m cable across a gap
	zip = kit.zipline(Vector3(0, 0, -20), Vector3(0, 0, -46), 11.0, 1.4)
	kit.plat(Vector3(0, 0, -49), Vector3(26, 1, 14))
	kit.checkpoint(Vector3(0, 0, -47), 0.0)
	# 3. cannonballs rolling along X across the path at z = -50
	battery = kit.battery(Vector3(11, 0, -50), 90.0, 22.0, 9.0, 3.2, 0.0, 0.0)
	# 4. rolling log along the path (yaw 90 turns its X axis onto Z); the roll pushes along X
	rolling = kit.log_roller(Vector3(0, 0, -62), 12.0, 2.6, 90.0, 3.0, 6.0, 0.0)
	kit.plat(Vector3(0, 0, -70), Vector3(12, 1, 4))
	# 5. seesaw along Z between two decks
	saw = kit.seesaw(Vector3(0, 0, -76.5), 9.0, 2.6, false, 0.0)
	kit.plat(Vector3(0, 0, -86), Vector3(12, 1, 8))
	kit.finish(Vector3(0, 0, -87), 0.0)

	r_barrel(barrel, Vector3(0, 0, -17))
	r_zipline(zip, Vector3(0, 2.2, -40), 0.6, Vector3(0, 0, -46))
	r_walk(Vector3(0, 0, -47))
	r_checkpoint()
	# lane stretch d 7.5..10.7 m from the muzzle is where the path crosses it
	r_until(func() -> bool: return battery.is_clear_for(7.5, 10.7, 1.3))
	r_walk(Vector3(0, 0, -55))
	r_walk(Vector3(0, 0, -69))
	r_walk(Vector3(0, 0, -76.5))
	r_walk(Vector3(0, 0, -80.4))
	r_jump(Vector3(0, 0, -80.6), Vector3(0, 0, -86))
	r_walk(Vector3(0, 0, -87))
