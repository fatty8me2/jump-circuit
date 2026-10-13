extends LevelBase
## Test course for the flow kit, part 1 (test_zf_bot_slice1): boost-gate chain -> flow slope -> launch
## arc -> a ring chain flown along the arc -> landing. Not a real level - never in Game.LEVELS. It
## doubles as the worked example of wiring each piece into a route (docs/FLOW_KIT.md).

var gates: Array[BoostGate] = []
var slope: FlowSurface
var arc: LaunchArc
var rings: Array[SpeedRing] = []
## Speed (m/s) the course expects at the launch lip; the air rings are placed on that arc.
const LIP_SPEED: float = 26.0
var landing: Vector3 = Vector3.ZERO


func _configure() -> void:
	level_id = "flow_test"
	theme_id = "glacier"
	kill_y = -50.0


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	# 1. a run-up with three boost gates (20 -> 22 -> 24 m/s)
	kit.plat(Vector3(0, 0, -17), Vector3(14, 2, 42))
	var gate_pts: Array[Vector3] = [Vector3(0, 0, -8), Vector3(0, 0, -18), Vector3(0, 0, -28)]
	gates = kit.boost_chain(gate_pts, 20.0, 5.0, {"speed_end": 24.0})
	# 2. a long flow slope: 9 m of drop over 44 m, no bleed, speed builds
	slope = kit.flow_slope_between(Vector3(0, 0, -38), Vector3(0, -9, -82), 10.0)
	# 3. the foot of a launch ramp on the run-out deck
	kit.plat(Vector3(0, -9, -101), Vector3(14, 2, 38))
	kit.checkpoint(Vector3(0, -9, -86), 0.0)
	# a gate just before the ramp restores the speed after a stop at the checkpoint (a route must not
	# depend on arriving at the checkpoint with speed: a respawn starts from standing still)
	kit.boost_gate(Vector3(0, -9, -107), 0.0, LIP_SPEED, 5.0)
	arc = kit.launch_arc(Vector3(0, -9, -112), 0.0, 24.0, 6.0, 9.0)
	# 4. rings flown along the predicted arc (the same rule the ring uses is simulated here)
	var ring_pts: Array[Vector3] = _ring_points()
	rings = kit.ring_line(ring_pts, {"add_speed": 4.0, "radius": 2.4})
	# 5. the landing deck sits where the flight comes down
	kit.plat(Vector3(landing.x, -9, landing.z - 10), Vector3(16, 2, 30))
	kit.checkpoint(Vector3(landing.x, -9, landing.z - 6), 0.0)
	kit.finish(Vector3(landing.x, -9, landing.z - 20), 0.0)

	var run: Array[Vector3] = [Vector3(0, 0, -2), Vector3(0, 0, -8), Vector3(0, 0, -18), Vector3(0, 0, -28),
		Vector3(0, 0, -38), Vector3(0, -9, -82), Vector3(0, -9, -86)]
	r_flow(run)
	r_checkpoint()
	var to_ramp: Array[Vector3] = [Vector3(0, -9, -86), Vector3(0, -9, -107), Vector3(0, -9, -108)]
	r_flow(to_ramp)
	r_launch(arc, landing + Vector3(0, 0, -1))
	r_checkpoint()
	var out: Array[Vector3] = [landing, Vector3(landing.x, -9, landing.z - 20)]
	r_flow(out)


## Centres of four rings on the flight a rider with LIP_SPEED takes off the lip with, simulating the
## Player's air rules and each ring's own boost. Also sets `landing` (where the flight comes down).
func _ring_points() -> Array[Vector3]:
	var t: MovementTuning = KitUtil.tuning()
	var lip: Vector3 = arc.lip()
	var v: Vector3 = arc.launch_velocity(LIP_SPEED)
	var p: Vector3 = lip
	var times: Array[float] = [0.18, 0.40, 0.62, 0.80]
	var out: Array[Vector3] = []
	var clock: float = 0.0
	var k: int = 0
	var dt: float = 1.0 / 60.0
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
		if clock > 0.3 and v.y < 0.0 and p.y <= -9.0:
			break
		if clock > 4.0:
			break
	landing = p
	return out
