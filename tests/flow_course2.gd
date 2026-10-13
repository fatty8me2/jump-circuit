extends LevelBase
## Test course for the flow kit, part 2 (test_zfk_bot_slice2): boost gates -> a descending half-pipe
## carved wall to wall -> a jump onto a grind rail -> rail to rail -> a launch arc -> a ring chain in the
## air -> a flat-bottomed half-pipe -> finish. Not a real level - never in Game.LEVELS. It doubles as the
## worked example of wiring rails and half-pipes into a route (docs/FLOW_KIT.md).

var pipe1: HalfPipe
var pipe2: HalfPipe
var rail1: GrindRail
var rail2: GrindRail
var arc: LaunchArc
var rings: Array[SpeedRing] = []
var landing: Vector3 = Vector3.ZERO


func _configure() -> void:
	level_id = "flow_test2"
	theme_id = "orbital"
	kill_y = -80.0


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	# 1. run-up deck with two gates, then a long descending half-pipe (flush with the deck at its start)
	kit.plat(Vector3(0, 0, -15), Vector3(18, 2, 40))
	var gate_pts: Array[Vector3] = [Vector3(0, 0, -10), Vector3(0, 0, -22)]
	kit.boost_chain(gate_pts, 18.0, 5.0, {"speed_end": 22.0})
	pipe1 = kit.halfpipe(Vector3(0, 0, -35), Vector3(0, -9, -125), 14.0, 3.0)
	# 2. the run-out deck, with a checkpoint, and rail 1 starting a jump above its far end
	kit.plat(Vector3(0, -9, -142), Vector3(18, 2, 34))
	kit.checkpoint(Vector3(0, -9, -134), 0.0)
	var r1: Array[Vector3] = [Vector3(0, -7.6, -150), Vector3(0, -8.2, -162), Vector3(7, -10.0, -178),
		Vector3(16, -12.5, -190), Vector3(28, -14.5, -196)]
	rail1 = kit.rail(r1, {"post_to_y": -30.0})
	# rail 2 starts under the flight from rail 1's jump-off point and carries on, curving back
	var r2: Array[Vector3] = [Vector3(30, -16.2, -200), Vector3(40, -18.0, -204), Vector3(52, -20.0, -214), Vector3(58, -21.0, -230)]
	rail2 = kit.rail(r2, {"post_to_y": -40.0})
	# 3. the landing deck below rail 2, a launch arc and a ring chain over a gap
	kit.plat(Vector3(58, -21.5, -246), Vector3(18, 2, 34))
	kit.checkpoint(Vector3(58, -21.5, -232), 0.0)
	var gates2: Array[Vector3] = [Vector3(58, -21.5, -237), Vector3(58, -21.5, -246)]
	kit.boost_chain(gates2, 20.0, 5.0, {"speed_end": 27.0})
	arc = kit.launch_arc(Vector3(58, -21.5, -256), 0.0, 24.0, 6.0, 9.0)
	var ring_pts: Array[Vector3] = _ring_points()
	rings = kit.ring_line(ring_pts, {"add_speed": 4.0, "radius": 2.4})
	# 4. a second pipe (flat floor) to finish
	kit.plat(Vector3(landing.x, -21.5, landing.z - 5), Vector3(18, 2, 26))
	pipe2 = kit.halfpipe(Vector3(landing.x, -21.5, landing.z - 18), Vector3(landing.x, -27.5, landing.z - 78), 14.0, 2.4, {"flat": 0.3})
	kit.plat(Vector3(landing.x, -27.5, landing.z - 92), Vector3(18, 2, 28))
	kit.finish(Vector3(landing.x, -27.5, landing.z - 96), 0.0)

	var run: Array[Vector3] = [Vector3(0, 0, -2), Vector3(0, 0, -10), Vector3(0, 0, -22), Vector3(0, 0, -35)]
	r_flow(run)
	r_flow(pipe1.carve_points(3, 0.55))
	var onto: Array[Vector3] = [pipe1.centre_point(1.0), Vector3(0, -9, -134)]
	r_flow(onto)
	r_checkpoint()
	var to_rail: Array[Vector3] = [Vector3(0, -9, -134), Vector3(0, -9, -144)]
	r_flow(to_rail)
	r_rail(rail1, rail1.start_point(), {"from": Vector3(0, -9, -146), "leave": Vector3(28, -14.5, -196) - Vector3(0, 0, 0), "chain_next": true, "to": rail2.start_point()})
	r_rail(rail2, rail2.start_point(), {"chain": true, "to": Vector3(58, -21.5, -243)})
	r_checkpoint()
	var to_arc: Array[Vector3] = [Vector3(58, -21.5, -237), Vector3(58, -21.5, -246), Vector3(58, -21.5, -251)]
	r_flow(to_arc)
	r_launch(arc, landing + Vector3(0, 0, -1))
	r_checkpoint()
	r_flow(pipe2.carve_points(2, 0.5))
	var fin: Array[Vector3] = [pipe2.centre_point(1.0), Vector3(landing.x, -27.5, landing.z - 96)]
	r_flow(fin)


## Four ring centres on the flight off the arc's lip at 24 m/s (see flow_course.gd); sets `landing`.
func _ring_points() -> Array[Vector3]:
	var t: MovementTuning = KitUtil.tuning()
	var lip: Vector3 = arc.lip()
	var v: Vector3 = arc.launch_velocity(24.0)
	var p: Vector3 = lip
	var times: Array[float] = [0.2, 0.42, 0.62]
	var out: Array[Vector3] = []
	var clock: float = 0.0
	var k: int = 0
	var dt: float = 1.0 / 120.0
	while true:
		var g: float = t.gravity_rise if v.y > 0.0 else t.gravity_fall
		v.y = maxf(v.y - g * dt, -t.max_fall_speed)
		p += v * dt
		clock += dt
		if k < times.size() and clock >= times[k]:
			out.append(p + Vector3(0, 0.9, 0))
			var hs: float = Vector2(v.x, v.z).length()
			var nh: float = minf(hs + 4.0 * FlowChain.bonus(k + 1), maxf(30.0, hs))
			v.x *= nh / hs
			v.z *= nh / hs
			k += 1
		if clock > 0.3 and v.y < 0.0 and p.y <= -21.5:
			break
		if clock > 4.0:
			break
	landing = p
	return out
