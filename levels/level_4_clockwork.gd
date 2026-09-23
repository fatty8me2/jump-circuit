extends LevelBase
## 4. CLOCKWORK HEIGHTS (hard mode) - a dusk-lit brass clock tower complex in the sky.
## Eleven stages of timing and momentum: express ferries whose speed you must
## inherit, a launch lift, crumbling spirals on a blink rhythm, a bladed turntable
## you sling off, a ferris wheel of tiny gondolas, a hammer gallery that ends with
## a deliberate hammer launch, an escalator that runs against you, and the set
## piece: THE GREAT CLOCK - no face, only void; ride the long hand in under the
## sweeping second hand, then sling off the racing short hand to reach the tower.

var K := Vector3.ZERO             # clock centre (long-hand level), set in _stage_9
var WHEEL := Vector3.ZERO         # ferris wheel axle
const WHEEL_R: float = 6.0
const WHEEL_PERIOD: float = 6.4

var _spokes: Node3D
var _bell: Node3D
var _second_b: Node3D


func _configure() -> void:
	theme_id = "clockwork"
	music_track = "b"
	kill_y = -60.0
	route_variants = 2


func V(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


## Point on the clock: radius r, angle deg (0 = east/+X, 90 = south/+Z, -90 = north), absolute height y.
func pol(r: float, deg: float, y: float) -> Vector3:
	var a: float = deg_to_rad(deg)
	return Vector3(K.x + cos(a) * r, y, K.z + sin(a) * r)


# ---- route helpers ------------------------------------------------------------------------------

func x_wait(nodes: Array, point: Vector3, radius: float, lead: float, locals: Array = [Vector3.ZERO]) -> void:
	route.append({"kind": "x_wait", "nodes": nodes, "locals": locals, "point": point, "radius": radius, "lead": lead})


func x_walk_on(local: Vector3, node: Node3D = null, tol: float = 0.35) -> void:
	var s: Dictionary = {"kind": "x_walk_on", "local": local, "tol": tol}
	if node != null:
		s["node"] = node
	else:
		s["picked"] = true
	route.append(s)


func x_step(s: Dictionary) -> void:
	route.append(s)


## Stand still until test.call() is true (timing on deterministic hazards).
func t_wait(test: Callable) -> void:
	route.append({"kind": "b_wait", "test": test})


## Stand still until a PATH mover is inside [lo, hi) of its cycle (0 = leaving its first point, 0.5 = at its far point).
func m_wait(m: MovingPlatform, lo: float, hi: float) -> void:
	route.append({"kind": "b_wait", "test": func() -> bool:
		var u: float = fposmod(Game.course_time / m.period + m.phase, 1.0)
		return u >= lo and u < hi})


func speed_flag(v: float) -> void:
	route[route.size() - 1]["speed"] = v


func _mvel(m: MovingPlatform, t: float) -> Vector3:
	return (m.offset_at(t + 0.02) - m.offset_at(t - 0.02)) / 0.04


## True when the hammer stays at least min_deg away from its low point for the whole window.
func _pend_clear(p: Pendulum, t0: float, t1: float, min_deg: float) -> bool:
	var t: float = t0
	while t <= t1:
		if absf(rad_to_deg(p.angle_at(t))) < min_deg:
			return false
		t += 0.04
	return true


func _blink_on(b: BlinkPlatform, t0: float, t1: float) -> bool:
	var t: float = t0
	while t <= t1:
		if not b.is_on_at(t):
			return false
		t += 0.05
	return true


func _flat_dir(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(b.x - a.x, 0, b.z - a.z).normalized()


## Static hop between two small pieces: take off `edge_a` from the centre of a, land just short of the centre of b.
func _hop(a: Vector3, b: Vector3, edge_a: float, hold: bool = true) -> void:
	var dir: Vector3 = _flat_dir(a, b)
	r_jump(a + dir * edge_a, b - dir * 0.15, hold)


func _cp(pos: Vector3, size: Vector3, yaw: float = 0.0, style: String = "main") -> void:
	kit.plat(pos, size, style)
	kit.checkpoint(pos, yaw)
	kit.lamp(pos + Vector3(size.x * 0.5 - 0.5, 0, size.z * 0.5 - 0.5), 2.8)
	kit.lamp(pos + Vector3(-size.x * 0.5 + 0.5, 0, size.z * 0.5 - 0.5), 2.8, false)


func _at(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	return n


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 3), 0.0)
	_stage_1()
	_stage_2()
	_stage_3()
	_stage_4()
	_stage_5()
	_stage_6()
	_stage_7()
	_stage_8()
	_stage_9()
	_stage_10()
	_stage_11()
	_stage_12()
	_stage_13()
	_stage_14()
	_stage_15()
	_stage_16()
	_stage_17()
	_stage_18()
	_build_surroundings()


# =================================================================================================
# 1. WIND-UP: express ferry (inherit its speed), two hammers over a beam, three cracked stones.
#    The only stage with a catch deck.
# =================================================================================================

func _stage_1() -> void:
	kit.plat(V(0, 0, 0), V(14, 2, 14))
	kit.arch(V(0, 0, -5.6), 5.0, 4.4)
	kit.lamp(V(-5.6, 0, -5.6), 3.2)
	kit.lamp(V(5.6, 0, -5.6), 3.2, false)
	kit.block(V(-5.2, 2.0, 4.6), V(2.4, 4.0, 2.4), Look.c("decor"))
	kit.block(V(-5.2, 4.6, 4.6), V(1.6, 1.2, 1.6), Look.c("metal"), false)
	kit.gear(V(-5.2, 2.6, 3.3), 1.5, 10, 0.3, 9.0)
	kit.gear(V(5.6, 1.9, 5.2), 1.9, 12, 0.35, -12.0, Vector3(90, 90, 0))
	kit.block(V(5.9, 1.0, 5.2), V(0.5, 2.0, 1.2), Look.c("decor2"), false)
	kit.ball(V(2.4, 0.6, 0.5), 0.42, Look.c("accent"))

	# catch deck under the ferry with pads back up
	kit.plat(V(0, -3.5, -17.3), V(9, 1.5, 19.4), "alt")
	kit.pad(V(3.2, -3.5, -9.4), 19.0, 0.0, 0.0, 1.1)
	kit.pad(V(-3.2, -3.5, -25.2), 19.0, 0.0, 0.0, 1.1)
	kit.glow_strip(V(0, -3.47, -17.3), V(0.25, 0.05, 18.0))
	var ferry_pts: Array[Vector3] = [Vector3.ZERO, V(0, 0, -8)]
	var ferry: MovingPlatform = kit.mover(V(0, 0, -10.6), V(3.2, 0.5, 3.2), ferry_pts, 4.0)
	for sx: int in [-1, 1]:
		kit.pipe(V(sx * 2.2, -0.7, -7.2), V(sx * 2.2, -0.7, -27.3), 0.12)

	kit.plat(V(0, 0, -30), V(6, 2, 5), "alt")
	kit.lamp(V(2.5, 0, -28), 2.8, false)

	r_walk(V(0, 0, -6.2))
	m_wait(ferry, 0.86, 0.95)
	x_step({"kind": "x_jump", "from": V(0, 0, -6.7), "to_node": ferry, "to_local": V(0, 0.25, 0.8)})
	x_walk_on(V(0, 0.25, 1.15), ferry, 0.25)
	t_wait(func() -> bool:
		var t: float = Game.course_time + 0.3
		return _mvel(ferry, t).z < -7.0 and ferry.offset_at(t).z < -4.0)
	x_step({"kind": "h_jump", "sprint": true, "from_node": ferry, "from_local": V(0, 0.25, -1.35), "to": V(0, 0, -28.8)})

	# hammer beam
	kit.plat(V(0, 0, -40.5), V(1.6, 1.0, 16), "main", 1.0)
	var h1: Pendulum = kit.pendulum(V(0, 8.2, -37), 7.0, 3.2, 0.0)
	var h2: Pendulum = kit.pendulum(V(0, 8.2, -44), 7.0, 3.2, 0.25)
	for z: float in [-37.0, -44.0]:
		for sx: int in [-1, 1]:
			kit.pillar(V(sx * 9.0, 8.6, z), 0.35, 16.0, Look.c("metal"))
		kit.block(V(0, 8.4, z), V(18.6, 0.5, 0.7), Look.c("decor"), false)
	kit.plat(V(0, 0, -50.5), V(4, 1, 4), "alt", 1.5)
	r_walk(V(0, 0, -33.2))
	t_wait(func() -> bool:
		var t: float = Game.course_time
		return _pend_clear(h1, t + 0.2, t + 0.85, 24.0) and _pend_clear(h2, t + 0.95, t + 1.65, 24.0))
	r_walk(V(0, 0, -50.2))

	# three cracked stones
	var c0: Vector3 = V(0, 0, -50.5)
	var stones: Array[Vector3] = [V(0, 0.4, -57.6), V(-2.5, 0.8, -63.0), V(0, 1.2, -68.4)]
	for c: Vector3 in stones:
		kit.collapse(c, 2.0, 0.5)
	_hop(c0, stones[0], 1.7)
	_hop(stones[0], stones[1], 0.7)
	_hop(stones[1], stones[2], 0.7)
	var cp1: Vector3 = V(0, 1.6, -76)
	_cp(cp1, V(7, 2, 7))
	r_jump(stones[2] + V(0, 0, -0.7), cp1 + V(0, 0, 2.6))
	r_walk(cp1)
	r_checkpoint()
	kit.gear(V(-6.5, -1.0, -62), 4.0, 14, 0.6, 14.0, Vector3.ZERO, Look.c("decor"))
	kit.pillar(V(-6.5, -1.3, -62), 0.8, 12.0)


# =================================================================================================
# 2. GEAR TEETH: weave through kill-brick teeth at a sprint, then a rising ladder of small blocks
#    with a head-hitter tap jump in the middle.
# =================================================================================================

func _stage_2() -> void:
	var y: float = 1.6
	kit.plat(V(0, y, -89.5), V(3, 1, 20), "alt", 1.2)
	var tz: Array[float] = [-83.0, -86.2, -89.4, -92.6, -95.8]
	for i: int in tz.size():
		var s: float = 1.0 if i % 2 == 0 else -1.0
		kit.hazard(V(s * 0.75, y + 0.5, tz[i]), V(1.5, 1.0, 1.0))
		r_walk(V(-s * 0.8, y, tz[i] + 1.25))
		r_walk(V(-s * 0.8, y, tz[i] - 1.25))
	kit.gear(V(-3.4, y - 1.2, -89.5), 2.6, 12, 0.5, 6.0, Vector3(90, 90, 0))
	kit.gear(V(3.4, y - 1.2, -89.5), 2.6, 12, 0.5, -6.0, Vector3(90, 90, 0))
	r_walk(V(0, y, -98.6))

	var blocks: Array[Vector3] = [V(1.6, 2.5, -104.8), V(-1.4, 3.6, -110.0), V(1.6, 4.8, -115.1), V(-0.8, 5.8, -120.5)]
	var prev: Vector3 = V(0, y, -98.6)
	var prev_edge: float = 0.65
	for b: Vector3 in blocks:
		kit.plat(b, V(1.6, 0.8, 1.6), "main", 2.5)
		_hop(prev, b, prev_edge)
		prev = b
		prev_edge = 0.5
	# head hitter: kill ceiling forces a tap jump
	var b5: Vector3 = V(-0.8, 5.8, -124.5)
	kit.plat(b5, V(1.6, 0.8, 1.6), "main", 2.5)
	kit.hazard(V(-0.8, 5.8 + 2.95, -122.5), V(2.6, 0.5, 5.6))
	for sx: int in [-1, 1]:
		kit.pillar(V(-0.8 + sx * 1.9, 5.8 + 3.2, -122.5), 0.2, 9.0, Look.c("metal"))
	_hop(prev, b5, 0.5, false)
	var b6: Vector3 = V(1.4, 6.6, -130.0)
	kit.plat(b6, V(1.6, 0.8, 1.6), "main", 2.5)
	_hop(b5, b6, 0.5)
	var cp2: Vector3 = V(0, 7.0, -138.5)
	_cp(cp2, V(6, 2, 6), 0.0, "alt")
	r_jump(b6 + _flat_dir(b6, cp2 + V(0, 0, 2.2)) * 0.5, cp2 + V(0, 0, 2.2))
	r_walk(cp2)
	r_checkpoint()

	# SHORTCUT A: three 1.1 m posts beside the teeth walk (6 m hops onto 1.1 m landings)
	var posts: Array[Vector3] = [V(6.2, 2.0, -82.0), V(6.8, 2.4, -88.0), V(5.4, 2.4, -94.0)]
	for p: Vector3 in posts:
		kit.disc(p, 0.55, 0.5, "accent", 4.0)
		kit.glow_strip(p + V(0, 0.03, 0), V(0.5, 0.05, 0.5), Look.c("accent2"), 45.0)


# =================================================================================================
# 3. EXPRESS: boost strip leap, an express ferry you must sprint off at full speed, and a
#    launch lift whose upward speed carries you to a ledge no jump can reach.
# =================================================================================================

func _stage_3() -> void:
	var y: float = 7.0
	kit.boost(V(0, y, -146.5), V(3, 0.4, 10), 0.0, 19.0)
	kit.plat(V(0, y, -166.5), V(5, 1, 7), "alt", 2.0)
	r_walk(V(0, y, -143.0))
	r_jump(V(0, y, -151.2), V(0, y, -165.0))
	speed_flag(19.0)
	for sx: int in [-1, 1]:
		kit.glow_strip(V(sx * 1.7, y + 0.05, -146.5), V(0.12, 0.1, 10.0), Look.c("accent2"))

	var f_pts: Array[Vector3] = [Vector3.ZERO, V(0, 0, -9)]
	var f2: MovingPlatform = kit.mover(V(0, y, -172.2), V(3.2, 0.5, 3.2), f_pts, 4.0, 0.0)
	for sx: int in [-1, 1]:
		kit.pipe(V(sx * 2.2, y - 0.7, -171.0), V(sx * 2.2, y - 0.7, -184.0), 0.12)
	var l3: Vector3 = V(0, y, -193.4)
	kit.plat(l3, V(4, 1, 4), "main", 3.0)
	r_walk(V(0, y, -169.3))
	m_wait(f2, 0.86, 0.95)
	x_step({"kind": "x_jump", "from": V(0, y, -169.7), "to_node": f2, "to_local": V(0, 0.25, 0.9)})
	x_walk_on(V(0, 0.25, 1.15), f2, 0.25)
	t_wait(func() -> bool:
		var t: float = Game.course_time + 0.3
		return _mvel(f2, t).z < -7.3 and f2.offset_at(t).z < -5.0)
	x_step({"kind": "h_jump", "sprint": true, "from_node": f2, "from_local": V(0, 0.25, -1.35), "to": l3 + V(0, 0, 0.9)})

	# launch lift
	var lift_pts: Array[Vector3] = [Vector3.ZERO, V(0, 6, 0)]
	var lift: MovingPlatform = kit.mover(V(0, y, -197.2), V(3, 0.5, 3), lift_pts, 2.8)
	for sx: int in [-1, 1]:
		kit.pillar(V(sx * 2.0, y + 11.0, -197.2), 0.3, 14.0, Look.c("metal"))
		kit.glow_strip(V(sx * 1.8, y + 3.0, -197.2), V(0.08, 6.0, 0.3), Look.c("accent2"))
	var cp3: Vector3 = V(0, y + 9.4, -202.6)
	_cp(cp3, V(6, 2, 6))
	lift.dwell = 0.2
	x_wait([lift], V(0, y - 0.25, -197.2), 0.3, 0.1)
	x_step({"kind": "x_jump", "from": V(0, y, -195.0), "to_node": lift, "to_local": V(0, 0.25, 0.2), "hold": false})
	x_step({"kind": "h_jump", "to": cp3 + V(0, 0, 1.6), "test": func() -> bool:
		var t: float = Game.course_time + 0.04
		var oy: float = lift.offset_at(t).y
		return _mvel(lift, t).y > 3.0 and oy > 4.0 and oy < 5.7})
	r_walk(cp3)
	r_checkpoint()

# =================================================================================================
# 4. CRUMBLING SPIRAL: a long rising right-hand curve of 1.8 m cracked stones and blink plates on
#    a shared rhythm, one tiny rest block in the middle. No stopping on anything that shakes.
# =================================================================================================

const SPIRAL_R: float = 40.0
const BLINK_PERIOD: float = 2.4
var _cp4 := Vector3.ZERO
var _cp5 := Vector3.ZERO
var _cp6 := Vector3.ZERO
var _cp7 := Vector3.ZERO


func _spiral(i: float) -> Vector3:
	var phi: float = 0.16 * i
	return V(SPIRAL_R - SPIRAL_R * cos(phi), 16.4 + 0.4 * i, -205.0 - SPIRAL_R * sin(phi))


func _stage_4() -> void:
	# kinds: s = cracked stone, b = blink plate, r = rest block. tau = bot arrival time after the go signal.
	var kinds: Array[String] = ["s", "s", "b", "s", "b", "r", "s", "b", "b"]
	var taus: Array[float] = [0.0, 0.0, 2.82, 0.0, 4.55, 0.0, 0.0, 1.76, 2.63]
	var blinks_a: Array = []
	var blinks_b: Array = []
	var prev: Vector3 = _spiral(0)
	var prev_edge: float = 0.3
	var rest_index: int = 5
	var wait_a: int = route.size()
	route.append({})
	for i: int in kinds.size():
		var p: Vector3 = _spiral(float(i + 1))
		if i == rest_index + 1:
			route.append({})
		match kinds[i]:
			"s":
				kit.collapse(p, 1.8, 0.45)
			"b":
				# on-window opens 0.5 s before the rhythm says you arrive
				var open_at: float = taus[i] - 0.5 + (0.0 if i < rest_index else 0.0)
				var b: BlinkPlatform = kit.blink(p, V(2.0, 0.4, 2.0), BLINK_PERIOD, 0.5, -open_at / BLINK_PERIOD)
				(blinks_a if i < rest_index else blinks_b).append([b, taus[i]])
			"r":
				kit.plat(p, V(1.6, 0.8, 1.6), "accent", 3.0)
		_hop_b(prev, p, prev_edge, kinds[i] == "b" or (i > 0 and kinds[i - 1] == "b"))
		prev = p
		prev_edge = 0.55
	route[wait_a] = {"kind": "b_wait", "test": _blink_gate.bind(blinks_a)}
	var wait_b: int = route.find({})
	route[wait_b] = {"kind": "b_wait", "test": _blink_gate.bind(blinks_b)}
	_cp4 = _spiral(10.0) + V(2.3, 0, 0)
	_cp(_cp4, V(6, 2, 6), -90.0, "alt")
	var land: Vector3 = _cp4 + V(-2.2, 0, 0.3)
	r_jump(prev + _flat_dir(prev, land) * 0.55, land)
	r_walk(_cp4)
	r_checkpoint()
	# the great idle gear the run bends around
	kit.gear(V(22, 12.0, -226), 13.0, 26, 1.0, 30.0, Vector3.ZERO, Look.c("decor"))
	kit.gear(V(22, 12.8, -226), 5.0, 12, 0.8, -12.0, Vector3.ZERO)
	kit.pillar(V(22, 11.5, -226), 1.6, 30.0)
	kit.gear(V(40, 14.0, -212), 5.0, 14, 0.7, -11.5, Vector3.ZERO)


## Jump annotation that the validator skips when a blink plate is involved (it may be off at validation time).
func _hop_b(a: Vector3, b: Vector3, edge_a: float, blink: bool) -> void:
	var dir: Vector3 = _flat_dir(a, b)
	if blink:
		route.append({"kind": "b_jump", "from": a + dir * edge_a, "to": b - dir * 0.15, "hold": true})
	else:
		r_jump(a + dir * edge_a, b - dir * 0.15)


func _blink_gate(list: Array) -> bool:
	var t: float = Game.course_time
	for e: Array in list:
		var tau: float = e[1]
		if not _blink_on(e[0], t + tau - 0.3, t + tau + 0.45):
			return false
	return true


# =================================================================================================
# 5. THE BLADED TURNTABLE: board a racing arm, hop the counter-sweeping kill bars, then sprint
#    across the arm tip and sling off it at 16+ m/s to a ledge far below.
# =================================================================================================

func _stage_5() -> void:
	var hub: Vector3 = _cp4 + V(3.0 + 1.8 + 10.5, 0, 0)
	var arms: Array[Dictionary] = [
		{"pos": V(6.5, 0, 0), "size": V(8, 0.5, 3)}, {"pos": V(-6.5, 0, 0), "size": V(8, 0.5, 3)},
		{"pos": V(0, 0, 6.5), "size": V(3, 0.5, 8)}, {"pos": V(0, 0, -6.5), "size": V(3, 0.5, 8)},
	]
	var table: RotatingPlatform = kit.spinner(hub, 7.0, arms, 2.6)
	for a: Dictionary in arms:
		var ap: Vector3 = a["pos"]
		var sz: Vector3 = a["size"]
		var radial: bool = absf(ap.x) > 0.1
		# kill collar: nobody hides near the hub
		kit.hazard(ap.normalized() * 4.4 + V(0, 0.65, 0), V(1.2, 0.8, 3.0) if radial else V(3.0, 0.8, 1.2), 0.0, table)
		table.add_child(Look.box(V(maxf(sz.x - 2.2, 0.3), 0.04, maxf(sz.z - 2.2, 0.3)), Look.flat(Look.c("accent"), 0.4, 0.0, 2.2), ap * 1.15 + V(0, 0.27, 0)))
	var sw: Sweeper = kit.sweeper(hub, 10.4, 2, -3.5, 35.0 / 120.0)
	kit.gear(hub + V(0, -1.2, 0), 7.5, 22, 0.7, 7.0, Vector3.ZERO, Look.c("decor"))
	kit.gear(hub + V(9.5, -2.2, 8.0), 3.4, 12, 0.6, -3.2, Vector3.ZERO)
	kit.pillar(hub + V(0, -1.6, 0), 1.6, 26.0)

	var tips: Array = [V(9.3, 0.25, 0), V(-9.3, 0.25, 0), V(0, 0.25, 9.3), V(0, 0.25, -9.3)]
	var edge: Vector3 = _cp4 + V(2.6, 0, 0)
	r_walk(edge)
	x_wait([table], hub + V(-9.3, 0, 0), 1.2, 0.5, tips)
	x_step({"kind": "x_jump", "from": edge + V(0.15, 0, 0), "picked": true, "to_local": V(9.0, 0.25, 0.6)})
	x_step({"kind": "h_hop", "picked": true, "local": V(8.8, 0.25, 1.0), "sweepers": [sw], "until": func() -> bool:
		var rel: Vector3 = player.global_position - hub
		var deg: float = rad_to_deg(atan2(-rel.z, rel.x))
		return deg > -14.0 and deg < 6.0})
	# sling: tangent line from the 20 degree point
	var a20: float = deg_to_rad(20.0)
	var rdir: Vector3 = V(cos(a20), 0, -sin(a20))
	var tdir: Vector3 = V(-sin(a20), 0, -cos(a20))
	var ledge: Vector3 = hub + rdir * 8.8 + tdir * 16.5 + V(0, -4.0, 0)
	_cp(ledge, V(6, 2, 6), 0.0)
	x_step({"kind": "h_jump", "sprint": true, "picked": true, "from_local": V(8.8, 0.25, -1.25), "to": ledge + V(0, 0, 0.5)})
	r_walk(ledge)
	r_checkpoint()
	_cp5 = ledge

# =================================================================================================
# 6. THE WHEEL: leap onto a 1.6 m gondola, hop the kill bar it carries you into near the top,
#    then dash across the gondola and sling off its forward speed to a ledge 12 m away.
# =================================================================================================

func _wheel_pos(deg: float) -> Vector3:
	# gondola node position at orbit angle deg (0 = far/-Z side, 90 = bottom, 180 = near/+Z side, 270 = top)
	return WHEEL + Vector3(0, -0.25, 0) + Vector3(0, 0, -1).rotated(Vector3.LEFT, deg_to_rad(deg)) * WHEEL_R


func _wheel_deg(p: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(-(p.y - WHEEL.y), -(p.z - WHEEL.z))), 360.0)


func _stage_6() -> void:
	WHEEL = _cp5 + V(0, WHEEL_R, -3.0 - 7.6)
	var cars: Array = []
	for i: int in 6:
		cars.append(kit.orbiter(WHEEL, WHEEL_R, Vector3.LEFT, V(1.6, 0.5, 1.6), WHEEL_PERIOD, float(i) / 6.0))
	_spokes = Node3D.new()
	_spokes.position = WHEEL + V(0, -0.25, 0)
	add_child(_spokes)
	var brass: StandardMaterial3D = Look.flat(Look.c("metal"), 0.45, 0.7)
	for sx: int in [-1, 1]:
		for i: int in 6:
			var holder := Node3D.new()
			holder.rotation.x = -float(i) / 6.0 * TAU
			holder.add_child(Look.box(V(0.12, 0.12, WHEEL_R), brass, V(sx * 1.05, 0, -WHEEL_R * 0.5)))
			_spokes.add_child(holder)
		kit.ring(WHEEL + V(sx * 1.05, -0.25, 0), WHEEL_R + 0.1, Look.c("accent"), Vector3(0, 0, 90))
		kit.block(WHEEL + V(sx * 2.6, -9.0, 0), V(0.9, 19.0, 2.4), Look.c("decor"), false)
		kit.block(WHEEL + V(sx * 2.6, 1.0, 0), V(1.3, 1.6, 3.0), Look.c("metal"), false)
		kit.gear(WHEEL + V(sx * 3.3, -0.25, 0), 2.2, 12, 0.4, -WHEEL_PERIOD, Vector3(0, 0, 90))
		# posts that carry the kill bar
		kit.block(WHEEL + V(sx * 2.6, 4.2, 1.55), V(0.5, 5.0, 0.5), Look.c("decor"), false)
	kit.pipe(WHEEL + V(-2.7, -0.25, 0), WHEEL + V(2.7, -0.25, 0), 0.3)
	kit.hazard(WHEEL + V(0, -0.25, 0), V(1.9, 2.4, 2.4))
	kit.hazard(WHEEL + V(0, 5.8 + 0.5, 1.55), V(5.0, 0.5, 0.5))

	_cp6 = WHEEL + V(0, 3.0, -17.4)
	_cp(_cp6, V(6, 2, 6), 0.0, "alt")
	kit.arch(_cp6 + V(0, 0, -2.4), 4.4, 4.2)

	var edge: Vector3 = _cp5 + V(0, 0, -2.6)
	r_walk(edge)
	x_wait(cars, _wheel_pos(125.0), 0.5, 0.62)
	x_step({"kind": "x_jump", "from": edge + V(0, 0, -0.15), "picked": true, "to_local": V(0, 0.25, 0.1)})
	x_walk_on(V(0, 0.25, 0.4), null, 0.2)
	x_step({"kind": "h_jump", "picked": true, "to_local": V(0, 0.25, 0.4), "test": func() -> bool:
		var d: float = _wheel_deg(player.global_position)
		return d > 243.0 and d < 250.0})
	x_step({"kind": "h_jump", "sprint": true, "picked": true, "from_local": V(0, 0.25, -0.55), "to": _cp6 + V(0, 0, 1.6)})
	r_walk(_cp6)
	r_checkpoint()


# =================================================================================================
# 7. HAMMER GALLERY: a 0.9 m beam with kill studs under three hammers, a ferry whose middle gets
#    hammered, and the anvil - where the great hammer is your ride.
# =================================================================================================

func _stage_7() -> void:
	var o: Vector3 = _cp6
	kit.plat(o + V(0, 0, -13), V(0.9, 0.8, 20), "main", 1.0)
	var taus: Array[float] = [0.62, 1.29, 1.96]
	var hz: Array[float] = [-8.0, -14.0, -20.0]
	var hams: Array = []
	for i: int in 3:
		hams.append(kit.pendulum(o + V(0, 8.2, hz[i]), 7.0, 2.6, 0.25 - taus[i] / 2.6))
		for sx: int in [-1, 1]:
			kit.pillar(o + V(sx * 8.5, 8.6, hz[i]), 0.3, 18.0, Look.c("metal"))
		kit.block(o + V(0, 8.4, hz[i]), V(17.6, 0.5, 0.7), Look.c("decor"), false)
	for z: float in [-11.0, -17.0]:
		kit.hazard(o + V(0, 0.25, z), V(0.9, 0.5, 0.5))
	r_walk(o + V(0, 0, -3.3))
	t_wait(func() -> bool:
		var t: float = Game.course_time
		for i: int in 3:
			if not _pend_clear(hams[i], t + taus[i] - 0.3, t + taus[i] + 0.3, 24.0):
				return false
		return true)
	r_jump(o + V(0, 0, -9.6), o + V(0, 0, -12.6), false)
	r_jump(o + V(0, 0, -15.6), o + V(0, 0, -18.6), false)
	var p7a: Vector3 = o + V(0, 0, -25)
	kit.plat(p7a, V(4, 1, 4), "alt", 2.0)
	r_walk(p7a + V(0, 0, 0.5))

	# the hammered ferry: its middle passes under the hammer exactly at the bottom of the swing
	var f_pts: Array[Vector3] = [Vector3.ZERO, V(0, 0, -10)]
	var ferry: MovingPlatform = kit.mover(o + V(0, 0, -30.1), V(3.2, 0.5, 5.0), f_pts, 5.2)
	kit.pendulum(o + V(0, 8.2, -35.1), 7.0, 2.6, 0.0)
	for sx: int in [-1, 1]:
		kit.pillar(o + V(sx * 8.5, 8.6, -35.1), 0.3, 18.0, Look.c("metal"))
		kit.pipe(o + V(sx * 2.2, -0.7, -27.4), o + V(sx * 2.2, -0.7, -42.8), 0.12)
	kit.block(o + V(0, 8.4, -35.1), V(17.6, 0.5, 0.7), Look.c("decor"), false)
	var p7b: Vector3 = o + V(0, 0, -47.6)
	kit.plat(p7b, V(4, 1, 4), "alt", 2.0)
	m_wait(ferry, 0.89, 0.96)
	x_step({"kind": "x_jump", "from": p7a + V(0, 0, -1.7), "to_node": ferry, "to_local": V(0, 0.25, 1.6)})
	x_walk_on(V(0, 0.25, -1.6), ferry, 0.25)
	t_wait(func() -> bool: return ferry.offset_at(Game.course_time).z < -9.4)
	x_step({"kind": "h_jump", "from_node": ferry, "from_local": V(0, 0.25, -2.2), "to": p7b + V(0, 0, 1.2)})

	# the anvil
	var anvil: Vector3 = o + V(0, 0, -56.2)
	kit.plat(o + V(0, 0, -52.4), V(0.9, 0.8, 5.6), "main", 1.0)
	kit.disc(anvil, 1.1, 0.8, "accent", 3.0)
	var big: Pendulum = kit.pendulum(anvil + V(0, 10.2, 0), 9.0, 3.6, 0.0, 90.0, 60.0)
	for sx: int in [-1, 1]:
		kit.pillar(anvil + V(sx * 3.0, 10.6, 0), 0.4, 22.0, Look.c("metal"))
	kit.block(anvil + V(0, 10.4, 0), V(6.6, 0.6, 0.8), Look.c("decor"), false)
	_cp7 = anvil + V(0, -8.0, -21.0)
	_cp(_cp7, V(9, 2, 12), 0.0)
	r_walk(p7b + V(0, 0, -1.0))
	t_wait(func() -> bool:
		var t: float = Game.course_time
		for k: int in 6:
			if rad_to_deg(big.angle_at(t + 0.35 + 0.1 * float(k))) > -35.0:
				return false
		return rad_to_deg(big.angle_at(t + 1.0)) < -20.0)
	x_step({"kind": "kick", "from": anvil, "to": _cp7 + V(0, 0, 3.0)})
	r_walk(_cp7)
	r_checkpoint()

# =================================================================================================
# 8. THE ESCALATOR: a belt running against you, studded with kill teeth and hop bars, then the
#    big chain - boost strip, 14 m leap onto a bounce pad at full speed, and a 20 m flight to the clock.
# =================================================================================================

func _stage_8() -> void:
	var o: Vector3 = _cp7
	kit.conveyor(o + V(0, 0, -18.0), V(3, 0.4, 25), 180.0, 6.0)
	for sx: int in [-1, 1]:
		kit.block(o + V(sx * 1.7, -0.3, -18.0), V(0.4, 1.0, 25.4), Look.c("decor"), false)
	var teeth: Array[float] = [-9.0, -17.0, -25.0]
	var bars: Array[float] = [-13.0, -21.0]
	r_walk(o + V(0, 0, -5.5))
	for i: int in 3:
		var sd: float = 1.0 if i % 2 == 0 else -1.0
		kit.hazard(o + V(sd * 0.75, 0.5, teeth[i]), V(1.5, 1.0, 0.8))
		r_walk(o + V(-sd * 0.8, 0, teeth[i] + 1.2))
		r_walk(o + V(-sd * 0.8, 0, teeth[i] - 1.2))
		if i < 2:
			kit.hazard(o + V(0, 0.25, bars[i]), V(3.0, 0.5, 0.5))
			r_jump(o + V(0, 0, bars[i] + 1.5), o + V(0, 0, bars[i] - 2.2))
	var p8: Vector3 = o + V(0, 0, -32.0)
	kit.plat(p8, V(4, 1, 3), "alt", 2.0)
	# SHORTCUT B: four 1.0 m posts beside the escalator - 6 m hops instead of fighting the belt
	for i: int in 4:
		var sp: Vector3 = o + V(3.7 + 0.3 * float(i % 2), 0.3, -11.5 - 6.0 * float(i))
		kit.disc(sp, 0.5, 0.5, "accent", 4.0)
		kit.glow_strip(sp + V(0, 0.03, 0), V(0.45, 0.05, 0.45), Look.c("accent2"), 45.0)
	kit.boost(o + V(0, 0, -38.5), V(3, 0.4, 10), 0.0, 22.0)
	for sx: int in [-1, 1]:
		kit.glow_strip(o + V(sx * 1.7, 0.05, -38.5), V(0.12, 0.1, 10.0), Look.c("accent2"))
	var pad_pos: Vector3 = o + V(0, 0, -59.7)
	kit.disc(pad_pos + V(0, -0.1, 0), 2.2, 0.8, "alt", 4.0)
	kit.pad(pad_pos, 17.0, 0.0, 0.0, 2.0)
	var balcony: Vector3 = o + V(0, 1.0, -79.7)
	_cp(balcony, V(5, 1.4, 16), 0.0, "alt")
	r_walk(p8)
	# aim past the pad: the bot must NOT brake to hit it - it has to cross the pad at full boost speed
	r_jump(o + V(0, 0, -43.2), pad_pos + V(0, 0, -0.5))
	speed_flag(22.0)
	r_pad(pad_pos, balcony + V(0, 0, 3.0))
	r_walk(balcony)
	r_checkpoint()
	K = V(o.x, balcony.y, balcony.z - 8.0 - 19.0)


# =================================================================================================
# 9. THE GREAT CLOCK, inward: no face - only void. Leap onto the long hand as its tip sweeps past
#    the balcony, hop the second hand (a kill bar crossing you every 1.4 s), run in, jump to the hub.
# =================================================================================================

func _clock_deg(p: Vector3) -> float:
	return rad_to_deg(atan2(-(p.z - K.z), p.x - K.x))


const LONG_PERIOD: float = -13.0
const SECOND_A_PERIOD: float = 5.0


func _stage_9() -> void:
	# floating dial: hour markers and rings, nothing to stand on
	for h: int in 12:
		var deg: float = -90.0 + 30.0 * h
		var big: bool = h % 3 == 0
		kit.glow_strip(pol(18.2 if big else 18.6, deg, K.y - 0.6), V(0.9 if big else 0.5, 0.1, 3.0 if big else 1.8), Look.c("accent") if big else Look.c("accent2"), 90.0 - deg)
	kit.ring(K + V(0, -0.6, 0), 17.4, Look.c("trim"), Vector3.ZERO)
	kit.ring(K + V(0, -0.6, 0), 20.0, Look.c("accent"), Vector3.ZERO)
	kit.ring(K + V(0, -0.6, 0), 9.0, Look.c("accent2"), Vector3.ZERO)

	# the great hand: minute hand (thin, X) and hour hand (wide, Z) locked in a cross, so a tip
	# sweeps past the balcony every 3.25 s
	var long_arms: Array[Dictionary] = [
		{"pos": V(11.65, 0, 0), "size": V(10.3, 0.5, 2.4)}, {"pos": V(-11.65, 0, 0), "size": V(10.3, 0.5, 2.4)},
		{"pos": V(0, 0, 11.65), "size": V(3.2, 0.5, 10.3)}, {"pos": V(0, 0, -11.65), "size": V(3.2, 0.5, 10.3)},
	]
	var long_hand: RotatingPlatform = kit.spinner(K, LONG_PERIOD, long_arms, 0.0)
	for sx: int in [-1, 1]:
		long_hand.add_child(Look.box(V(8.6, 0.04, 0.3), Look.flat(Look.c("accent"), 0.4, 0.0, 2.4), V(sx * 11.65, 0.27, 0)))
		long_hand.add_child(Look.box(V(0.5, 0.04, 8.6), Look.flat(Look.c("accent2"), 0.4, 0.0, 2.4), V(0, 0.27, sx * 11.65)))
		long_hand.add_child(Look.box(V(4.2, 0.3, 1.0), Look.flat(Look.c("metal"), 0.4, 0.75), V(sx * 4.6, -0.05, 0)))
		long_hand.add_child(Look.box(V(1.0, 0.3, 4.2), Look.flat(Look.c("metal"), 0.4, 0.75), V(0, -0.05, sx * 4.6)))
	var second_a: Sweeper = kit.sweeper(K, 17.0, 2, SECOND_A_PERIOD, 0.0)

	# hub: drum + plinth (static, safe)
	var plinth: Vector3 = K + V(0, 2.2, 0)
	kit.disc(plinth + V(0, -0.8, 0), 2.4, 5.0, "main", 0.0)
	kit.disc(plinth, 3.2, 0.8, "accent", 0.0)
	kit.checkpoint(plinth, 0.0)

	var edge: Vector3 = pol(19.3, 90, K.y)
	var tips: Array = [V(15.3, 0.25, 0), V(-15.3, 0.25, 0), V(0, 0.25, 15.3), V(0, 0.25, -15.3)]
	var rel_w: float = TAU / SECOND_A_PERIOD + TAU / absf(LONG_PERIOD)
	r_walk(edge)
	x_step({"kind": "h_jump", "from": pol(19.15, 90, K.y), "reach": 4.3, "lead": 0.55, "to_node": long_hand, "to_locals": tips,
		"test": func() -> bool:
			# no second-hand bar on the landing spot when we get there
			var gap: float = fposmod(-PI * 0.5 - second_a.angle_at(Game.course_time + 0.55), PI)
			return gap > 0.85})
	x_step({"kind": "h_hop", "picked": true, "local": V(14.8, 0.25, 0), "sweepers": [second_a], "until": func() -> bool:
		# just after a bar has crossed us: the next one is over a second away
		var me: float = deg_to_rad(_clock_deg(player.global_position))
		var gap: float = fposmod(me - second_a.angle_at(Game.course_time), PI)
		return gap / rel_w > 1.1})
	x_walk_on(V(7.4, 0.25, 0), null, 0.4)
	x_step({"kind": "x_jump", "picked": true, "from_local": V(6.9, 0.25, 0), "to_center": plinth, "to_radius": 2.2})
	x_step({"kind": "walk", "to": plinth})
	r_checkpoint()


# =================================================================================================
# 10. THE GREAT CLOCK, outward: the short hand races. Jump its kill collar onto the 1.6 m stem,
#     dodge the upper second hand, then sprint the length of the arrowhead and sling off its tip -
#     the only way to reach the tower ledge.
# =================================================================================================

const SHORT_PERIOD: float = 5.2
const SECOND_B_PERIOD: float = -7.8
const SECOND_B_PHASE: float = 0.0


func _stage_10() -> void:
	var y: float = K.y + 2.2
	var arms: Array[Dictionary] = [
		{"pos": V(5.4, 0, 0), "size": V(4.0, 0.5, 1.6)}, {"pos": V(-5.4, 0, 0), "size": V(4.0, 0.5, 1.6)},
		{"pos": V(7.6, 0, 0), "size": V(2.0, 0.5, 6.0)}, {"pos": V(-7.6, 0, 0), "size": V(2.0, 0.5, 6.0)},
	]
	var short_hand: RotatingPlatform = kit.spinner(V(K.x, y, K.z), SHORT_PERIOD, arms, 0.0, 0.0, 0.5)
	for sx: int in [-1, 1]:
		kit.hazard(V(sx * 4.0, 0.65, 0), V(1.2, 0.8, 1.6), 0.0, short_hand)
		short_hand.add_child(Look.box(V(0.35, 0.04, 5.0), Look.flat(Look.c("accent2"), 0.4, 0.0, 2.4), V(sx * 7.6, 0.27, 0)))
	_second_b = SecondHand.new()
	_second_b.position = V(K.x, y + 0.45, K.z)
	add_child(_second_b)
	var dark: StandardMaterial3D = Look.flat(Color(0.14, 0.15, 0.2), 0.4, 0.7)
	kit.hazard(V(5.1, 0, 0), V(2.2, 0.5, 0.5), 0.0, _second_b)
	# visual hand, lifted clear of a full-jump head at the CP9 respawn (feet 2.47 m + 1.4 m antenna);
	# the hub reaches up into the tower shaft (bottom at K.y + 7) like a clock arbor
	_second_b.add_child(Look.box(V(4.2, 0.2, 0.2), dark, V(2.1, 4.0, 0)))
	_second_b.add_child(Look.box(V(0.2, 4.0, 0.2), dark, V(4.2, 2.0, 0)))
	_second_b.add_child(Look.cylinder(0.3, 1.0, dark, V(0, 4.1, 0), -1.0, 10))

	# tower ledge: down the tangent from the east point, 1.8 m up
	var t0: Vector3 = V(K.x + 7.6, y + 1.8, K.z - 2.7 - 10.8)
	_cp(t0, V(5, 1, 5), -125.0)  # face the tower ladder that curls away toward +X/+Z
	kit.pillar(t0 + V(0, -1.0, 0), 0.5, 3.0, Look.c("metal"))

	# board at 55 deg over the collar and the upper second hand, onto the arrowhead
	var tips: Array = [V(7.0, 0.25, 0), V(-7.0, 0.25, 0)]
	r_walk(pol(2.5, -55, y))
	x_step({"kind": "h_jump", "from": pol(2.85, -55, y), "reach": 4.4, "lead": 0.5, "to_node": short_hand, "to_locals": tips,
		"test": func() -> bool:
			var bar: float = rad_to_deg(wrapf(_second_b_angle(Game.course_time + 0.5) - deg_to_rad(55.0), -PI, PI))
			return absf(bar) > 28.0})
	x_walk_on(V(7.6, 0.25, 1.6), null, 0.3)
	t_wait(func() -> bool:
		var w: float = TAU / SHORT_PERIOD
		var arm: float = deg_to_rad(_clock_deg(player.global_position)) + atan2(1.6, 7.6)
		var at_takeoff: float = rad_to_deg(wrapf(arm + w * 0.55, -PI, PI))
		return at_takeoff >= -10.0 and at_takeoff <= 4.0)
	x_step({"kind": "h_jump", "sprint": true, "picked": true, "from_local": V(7.6, 0.25, -2.75), "to": t0 + V(0, 0, 0.8)})
	r_walk(t0)
	r_checkpoint()
	_t0 = t0


func _second_b_angle(t: float) -> float:
	return fposmod(t / SECOND_B_PERIOD + SECOND_B_PHASE, 1.0) * TAU


## Upper second hand: one kill bar over the short hand, driven like a Sweeper (the bot duck-types it).
class SecondHand extends Node3D:
	var bar_count: int = 1
	var arm_length: float = 6.2
	var period: float = SECOND_B_PERIOD

	func angle_at(t: float) -> float:
		return fposmod(t / period + SECOND_B_PHASE, 1.0) * TAU


# =================================================================================================
# 11. THE TOWER: a 2 m-per-step block ladder, one last express ferry to sprint off, and a
#     crumbling, blinking curl up to the belfry.
# =================================================================================================

var _t0 := Vector3.ZERO


func _stage_11() -> void:
	var a0: float = rad_to_deg(atan2(_t0.z - K.z, _t0.x - K.x))
	var y: float = _t0.y
	var prev: Vector3 = _t0
	var prev_edge: float = 2.2
	for i: int in 3:
		var b: Vector3 = pol(16.2 - 0.4 * i, a0 + 20.0 + 17.0 * i, y + 2.0 * (i + 1))
		kit.plat(b, V(1.6, 0.8, 1.6), "main", 2.0, -(a0 + 20.0 + 17.0 * i))
		_hop(prev, b, prev_edge)
		prev = b
		prev_edge = 0.5
	y += 6.0
	var fa: Vector3 = pol(15.2, a0 + 72.0, y)
	var fb: Vector3 = pol(15.2, a0 + 106.0, y)
	var f_pts: Array[Vector3] = [Vector3.ZERO, fb - fa]
	var ferry: MovingPlatform = kit.mover(fa, V(3.0, 0.5, 3.0), f_pts, 4.0, 0.0, true)
	var d: Vector3 = _flat_dir(fa, fb)
	var l4: Vector3 = fb + d * (1.5 + 9.0 + 1.5) + V(0, 0.6, 0)
	kit.plat(l4, V(3, 0.8, 3), "alt", 2.5, rad_to_deg(atan2(-d.x, -d.z)))
	m_wait(ferry, 0.86, 0.95)
	x_step({"kind": "x_jump", "from": prev + _flat_dir(prev, fa) * 0.5, "to_node": ferry, "to_local": -d * 0.7 + V(0, 0.25, 0)})
	x_walk_on(-d * 1.05 + V(0, 0.25, 0), ferry, 0.25)
	t_wait(func() -> bool:
		var t: float = Game.course_time + 0.3
		return _mvel(ferry, t).dot(d) > 7.3 and ferry.offset_at(t).length() > (fb - fa).length() * 0.55)
	x_step({"kind": "h_jump", "sprint": true, "from_node": ferry, "from_local": d * 1.25 + V(0, 0.25, 0), "to": l4 - d * 0.5})

	# the curl: stone, blink, stone, belfry
	var belfry: Vector3 = K + V(0, y + 5.0 - K.y, 0)
	var r4: float = Vector2(l4.x - K.x, l4.z - K.z).length()
	var a4: float = rad_to_deg(atan2(l4.z - K.z, l4.x - K.x))
	var curl: Array[Vector3] = []
	for i: int in 3:
		curl.append(pol(r4 - 3.9 * (i + 1), a4 + 17.0 * (i + 1), l4.y + 1.1 * (i + 1)))
	kit.collapse(curl[0], 1.8, 0.45)
	var blink: BlinkPlatform = kit.blink(curl[1], V(2.0, 0.4, 2.0), 2.4, 0.5, 0.0)
	kit.collapse(curl[2], 1.8, 0.45)
	r_walk(l4)
	t_wait(func() -> bool:
		var t: float = Game.course_time
		return _blink_on(blink, t + 1.45, t + 2.3))
	_hop(l4, curl[0], 1.4)
	_hop_b(curl[0], curl[1], 0.55, true)
	_hop_b(curl[1], curl[2], 0.55, true)
	var land: Vector3 = belfry + _flat_dir(belfry, curl[2]) * 3.9
	r_jump(curl[2] + _flat_dir(curl[2], land) * 0.55, land)
	r_walk(belfry)
	r_checkpoint()
	kit.disc(belfry, 5.2, 1.0, "accent", 4.0)
	# (the old finish: now checkpoint 11, facing the gantry north into the new half)
	kit.checkpoint(belfry, 0.0)
	_build_belfry(belfry)
	_belfry = belfry


func _build_belfry(belfry: Vector3) -> void:
	for i: int in 4:
		var post: Vector3 = belfry + V(cos(PI * 0.25 + PI * 0.5 * i), 0, sin(PI * 0.25 + PI * 0.5 * i)) * 4.4
		kit.pillar(post + V(0, 9.4, 0), 0.4, 9.4, Look.c("metal"))
	# roof sits clear of the finish ring (tops out near +8.9); the bell hangs on the
	# approach side, off the gate plane, and swings along X
	var roof := Look.cylinder(6.2, 5.0, Look.flat(Look.c("decor2"), 0.7), Vector3.ZERO, 0.0, 8)
	add_child(_at(roof, belfry + V(0, 12.1, 0)))
	add_child(_at(Look.cylinder(6.4, 0.4, Look.flat(Look.c("trim"), 0.5, 0.4), Vector3.ZERO, -1.0, 8), belfry + V(0, 9.6, 0)))
	add_child(_at(Look.sphere(0.5, Look.flat(Look.c("accent"), 0.3, 0.0, 3.0)), belfry + V(0, 15.0, 0)))
	kit.ring(belfry + V(0, 4.0, 0), 7.4, Look.c("accent"), Vector3(90, 0, 0))
	_bell = Node3D.new()
	_bell.position = belfry + V(0, 9.4, 2.6)
	add_child(_bell)
	_bell.add_child(Look.cylinder(0.09, 2.4, Look.flat(Look.c("metal"), 0.4, 0.7), V(0, -1.2, 0), -1.0, 8))
	_bell.add_child(Look.cylinder(1.3, 1.6, Look.flat(Look.c("accent"), 0.35, 0.6, 0.8), V(0, -3.0, 0), 0.6, 20))
	# the tower shaft that carries the belfry, rising from the hub
	kit.pillar(belfry + V(0, -1.0, 0), 1.2, belfry.y - K.y - 8.0, Look.c("decor"))


func _physics_process(dt: float) -> void:
	super(dt)
	if _second_b != null:
		_second_b.rotation.y = _second_b_angle(Game.course_time)


func _snap_to_clock() -> void:
	super()
	if _second_b != null:
		_second_b.rotation.y = _second_b_angle(Game.course_time)
		_second_b.reset_physics_interpolation()


# #################################################################################################
#   THE MOVEMENT - stages 12-21: north from the belfry into the works behind the great clock
# #################################################################################################

var _belfry := Vector3.ZERO
var _cp12 := Vector3.ZERO
var _cp13 := Vector3.ZERO
var _cp14 := Vector3.ZERO


## Adds an effect node (particles or a ClockworkFx trigger) at pos.
func _fx(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	add_child(n)
	return n


## A trigger that restarts `bursts` (built at its origin) as the course clock passes fire_at of each cycle.
func _fx_clock(pos: Vector3, period: float, phase: float, fire_at: Array[float], bursts: Array) -> ClockworkFx:
	var f := ClockworkFx.new()
	f.mode = ClockworkFx.Mode.CLOCK
	f.period = period
	f.phase = phase
	f.fire_at = fire_at
	for b: GPUParticles3D in bursts:
		f.add_child(b)
		f.bursts.append(b)
	_fx(f, pos)
	return f


## A trigger that restarts `bursts` when the player comes within radius.
func _fx_near(pos: Vector3, radius: float, bursts: Array) -> ClockworkFx:
	var f := ClockworkFx.new()
	f.mode = ClockworkFx.Mode.NEAR
	f.radius = radius
	for b: GPUParticles3D in bursts:
		f.add_child(b)
		f.bursts.append(b)
	_fx(f, pos)
	return f


## Stage gate flourish: a ring of brass sparks and a gold puff when you arrive at a new checkpoint.
func _cp_fx(pos: Vector3) -> void:
	_fx_near(pos + V(0, 0.4, 0), 2.4, [
		ClockworkFx.spark_burst(26, Color(1.0, 0.78, 0.3), 7.5, Vector3.UP, 38.0, 0.9),
		ClockworkFx.puff_burst(12, Color(1.0, 0.85, 0.5, 0.55), 3.0, 0.9, 0.8, true, 0.9, 0.2)])


## Takeoff-to-landing hop between static pieces (lands just short of the target centre).
func _hop_to(from: Vector3, b: Vector3, hold: bool = true) -> void:
	r_jump(from, b - _flat_dir(from, b) * 0.15, hold)


## True when every laser in list ([gate, tau]) stays off from tau - w to tau + w seconds from now.
func _lasers_off(list: Array, w: float) -> bool:
	var t: float = Game.course_time
	for e: Array in list:
		var g: LaserGate = e[0]
		var s: float = float(e[1]) - w
		while s <= float(e[1]) + w:
			if g.is_on_at(t + s):
				return false
			s += 0.04
	return true


## True when the piston stays retracted (and is not about to punch) for the whole window.
func _piston_clear(p: Piston, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if p.extension_at(s) > 0.02 or p.is_punching_at(s):
			return false
		s += 0.04
	return true


func _crusher_clear(c: Crusher, t0: float, t1: float) -> bool:
	return c.is_clear_for(t0, t1 - t0)


# =================================================================================================
# 12. THE CHIME GANTRY: out of the belfry along a 1.4 m gantry through three curtains of light that
#     chime in a travelling wave, a first mantle wall, then a rising hop chain through one more chime.
# =================================================================================================

func _stage_12() -> void:
	var o: Vector3 = _belfry
	kit.plat(o + V(0, 0, -13.3), V(1.4, 0.6, 16.6), "main", 1.0)
	for sx: int in [-1, 1]:
		kit.glow_strip(o + V(sx * 0.64, 0.03, -13.3), V(0.07, 0.06, 16.0), Look.c("accent2"))
	var chimes: Array = []
	var lz: Array[float] = [-9.0, -13.5, -18.0]
	for i: int in 3:
		var g: LaserGate = kit.laser(o + V(0, 1.3, lz[i]), V(2.8, 2.6, 0.18), 2.4, 0.45, -0.5 * float(i) / 2.4)
		chimes.append([g, 0.45 + 0.5 * float(i)])
		# a little bell over every chime gate
		kit.block(o + V(0, 3.2, lz[i]), V(3.6, 0.3, 0.5), Look.c("decor"), false)
		add_child(_at(Look.cylinder(0.45, 0.6, Look.flat(Look.c("accent"), 0.35, 0.6, 0.6), Vector3.ZERO, 0.2, 14), o + V(0, 3.75, lz[i])))
	var land: Vector3 = o + V(0, 0, -23.6)
	kit.plat(land, V(4, 1, 4), "alt", 1.5)
	var ledge_top: Vector3 = o + V(0, 3.4, -29.6)
	kit.ledge(ledge_top, V(4.4, 5.0, 8.0))
	r_walk(o + V(0, 0, -5.6))
	r_until(func() -> bool: return _lasers_off(chimes, 0.26))
	r_walk(o + V(0, 0, -23.0))
	r_mantle(o + V(0, 0, -24.0), o + V(0, 3.4, -27.6))

	# the hop chain, the last hop through a fourth chime
	var b1: Vector3 = o + V(1.4, 4.2, -38.8)
	var b2: Vector3 = o + V(-1.2, 5.0, -44.0)
	var b3: Vector3 = o + V(1.0, 5.8, -49.4)
	for b: Vector3 in [b1, b2, b3]:
		kit.plat(b, V(1.6, 0.8, 1.6), "main", 2.5)
	var g4: LaserGate = kit.laser(o + V(-0.1, 7.2, -46.7), V(4.2, 3.6, 0.18), 2.4, 0.4, 0.3)
	_cp12 = o + V(0, 6.2, -57.4)
	_cp(_cp12, V(6, 2, 6))
	_cp_fx(_cp12)
	r_walk(o + V(1.0, 3.4, -32.7))
	_hop_to(o + V(1.1, 3.4, -33.3), b1)
	_hop(b1, b2, 0.5)
	r_until(func() -> bool: return _lasers_off([[g4, 0.35]], 0.25))
	_hop(b2, b3, 0.5)
	r_jump(b3 + V(0, 0, -0.5), _cp12 + V(0, 0, 2.3))
	r_walk(_cp12)
	r_checkpoint()


# =================================================================================================
# 13. THE PENDULUM CASE (fork): RIGHT - run the case wall across a 19 m drop, timing the curtain
#     of light across the panel; LEFT - stand on the anvil and let the great pendulum hurl you.
#     Both land on the counterweight deck; then an express ferry to sprint off.
# =================================================================================================

func _stage_13() -> void:
	var o: Vector3 = _cp12
	# RIGHT: the case wall
	kit.plat(o + V(1.8, 0, -6.5), V(1.6, 0.6, 7.0), "main", 1.0)
	kit.wallrun(o + V(3.5, 1.2, -20.2), V(14, 6, 0.5), 90.0)
	var curtain: LaserGate = kit.laser(o + V(1.7, 3.4, -19.5), V(2.6, 3.6, 0.18), 2.0, 0.4, 0.0)
	kit.banner(o + V(2.7, 0, -3.4), 3.6, Look.c("accent2"))
	# LEFT: the anvil under the great pendulum
	var a: Vector3 = o + V(-5.0, 0, -13.0)
	kit.plat(o + V(-4.9, 0, -2.0), V(3.8, 0.8, 6.0), "alt", 1.2)
	kit.plat(o + V(-5.0, 0, -8.45), V(0.9, 0.8, 6.9), "main", 1.0)
	kit.disc(a, 1.1, 0.8, "accent", 3.0)
	var big: Pendulum = kit.pendulum(a + V(0, 10.2, 0), 9.0, 3.6, 0.0, 90.0, 60.0)
	for sx: int in [-1, 1]:
		kit.pillar(a + V(sx * 3.0, 10.6, 0), 0.4, 22.0, Look.c("metal"))
	kit.block(a + V(0, 10.4, 0), V(6.6, 0.6, 0.8), Look.c("decor"), false)
	kit.banner(o + V(-3.4, 0, -3.8), 3.6, Look.c("accent"))
	# the counterweight deck both routes land on
	var deck: Vector3 = a + V(0, -8.0, -21.0)
	kit.plat(deck + V(0, 0, -2.0), V(9, 2, 16), "alt")
	kit.glow_strip(deck + V(0, 0.03, -2.0), V(0.3, 0.05, 15.0), Look.c("accent"))
	if route_variant == 0:
		r_walk(o + V(1.8, 0, -4.0))
		r_until(func() -> bool: return _lasers_off([[curtain, 1.8]], 0.32))
		r_wallrun(o + V(1.8, 0, -9.6), o + V(3.1, 1.2, -14.2), o + V(3.1, 1.2, -24.2), deck + V(2.5, 0, -1.0))
	else:
		r_walk(o + V(-4.9, 0, -2.0))
		r_walk(a + V(0, 0, 7.6))
		t_wait(func() -> bool:
			var t: float = Game.course_time
			for k: int in 6:
				if rad_to_deg(big.angle_at(t + 0.35 + 0.1 * float(k))) > -35.0:
					return false
			return rad_to_deg(big.angle_at(t + 1.0)) < -20.0)
		x_step({"kind": "kick", "from": a, "to": deck + V(0, 0, 3.0)})
		# the hammer throws you in at 20+ m/s: brake on the long deck
		route.append({"kind": "a_fly", "to": deck + V(0, 0, -3.0), "until": func() -> bool:
			return player.grounded and Vector2(player.velocity.x, player.velocity.z).length() < 3.0})

	# express ferry off the deck
	var d_end: float = deck.z - 10.0
	var f_pts: Array[Vector3] = [Vector3.ZERO, V(0, 0, -9)]
	var ferry: MovingPlatform = kit.mover(V(deck.x, deck.y, d_end - 2.2), V(3.2, 0.5, 3.2), f_pts, 4.0, 0.0)
	for sx: int in [-1, 1]:
		kit.pipe(V(deck.x + sx * 2.2, deck.y - 0.7, d_end - 1.0), V(deck.x + sx * 2.2, deck.y - 0.7, d_end - 14.0), 0.12)
	_cp13 = V(deck.x, deck.y, d_end - 2.2 - 21.2)
	_cp(_cp13, V(5, 2, 5), 0.0, "alt")
	_cp_fx(_cp13)
	r_walk(V(deck.x, deck.y, d_end + 0.7))
	m_wait(ferry, 0.86, 0.95)
	x_step({"kind": "x_jump", "from": V(deck.x, deck.y, d_end + 0.3), "to_node": ferry, "to_local": V(0, 0.25, 0.9)})
	x_walk_on(V(0, 0.25, 1.15), ferry, 0.25)
	t_wait(func() -> bool:
		var t: float = Game.course_time + 0.3
		return _mvel(ferry, t).z < -7.3 and ferry.offset_at(t).z < -5.0)
	x_step({"kind": "h_jump", "sprint": true, "from_node": ferry, "from_local": V(0, 0.25, -1.35), "to": _cp13 + V(0, 0, 0.9)})
	r_walk(_cp13)
	r_checkpoint()


# =================================================================================================
# 14. THE MUSIC BOX: a comb of five pistons fires from both sides in the drum's tune - wait in the
#     pockets between teeth, move on the rests - then step in front of the great key piston ON
#     PURPOSE and let it punch you across the gap.
# =================================================================================================

const COMB_PERIOD: float = 2.4


func _stage_14() -> void:
	var o: Vector3 = _cp13
	kit.plat(o + V(0, 0, -14.75), V(2.0, 0.6, 24.5), "main", 1.2)
	var tune: Array[float] = [0.0, 0.5, 0.2, 0.7, 0.35]
	var pz: Array[float] = [-6.0, -10.5, -15.0, -19.5, -24.0]
	var comb: Array = []
	for i: int in 5:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var pst: Piston = kit.piston(o + V(side * 1.8, 1.5, pz[i]), V(2.2, 1.4, 1.6), 90.0 * side, 2.4, COMB_PERIOD, tune[i], 12.0)
		comb.append(pst)
		# music-box notes when the tooth is struck
		_fx_clock(o + V(side * 1.2, 2.0, pz[i]), COMB_PERIOD, tune[i], [0.45], [
			ClockworkFx.puff_burst(10, Color(1.0, 0.85, 0.4, 0.9), 3.2, 0.35, 1.1, true, 0.0, 1.0),
			ClockworkFx.spark_burst(8, Color(0.6, 0.9, 1.0), 5.0, Vector3(-side, 1.2, 0), 30.0, 0.5)])
	var pockets: Array[float] = [-3.7, -8.25, -12.75, -17.25, -21.75, -26.2]
	r_walk(o + V(0, 0, pockets[0]))
	for i: int in 5:
		var pst: Piston = comb[i]
		r_until(func() -> bool:
			var t: float = Game.course_time
			return _piston_clear(pst, t, t + 0.95))
		r_walk(o + V(0, 0, pockets[i + 1]))

	# the key: a launch plate in front of a big piston that punches toward -X
	var plate: Vector3 = o + V(0, 0, -29.2)
	kit.plat(plate, V(3.0, 0.6, 4.4), "accent", 1.2)
	var key: Piston = kit.piston(plate + V(2.3, 1.7, 0), V(2.6, 1.6, 1.6), 90.0, 2.0, COMB_PERIOD, 0.0, 14.0)
	_fx_clock(plate + V(1.2, 1.0, 0), COMB_PERIOD, 0.0, [0.45], [
		ClockworkFx.puff_burst(16, Color(0.95, 0.92, 1.0, 0.55), 5.0, 1.0, 0.9, false, 0.3, 0.3)])
	_cp14 = plate + V(-16.0, -3.0, 0)
	_cp(_cp14, V(7, 2, 9), 0.0)
	_cp_fx(_cp14)
	t_wait(func() -> bool:
		var u: float = fposmod(Game.course_time / COMB_PERIOD, 1.0)
		return u > 0.12 and u < 0.2)
	x_step({"kind": "kick", "from": plate + V(0.2, 0, 0), "to": _cp14 + V(1.5, 0, 0)})
	r_walk(_cp14)
	r_checkpoint()


# =================================================================================================
# 15. THE ESCAPEMENT (set piece): five pallets tick up and down in alternating parity like the
#     escapement of a tower clock. On every beat one pallet snaps up to the height its neighbour
#     just dropped to - jump across on the beat and the clock carries you 11 m up; miss it and the
#     next pallet is out of reach. A curtain of light between pallets 3 and 4 only lets the on-beat
#     jump through, and the last tick lifts you under a 3.2 m ledge you must mantle.
# =================================================================================================

const ESC_BEAT: float = 1.3
const ESC_SNAP: float = 0.34
const ESC_RISE: float = 2.2
const ESC_TEETH: int = 15
var _cp15 := Vector3.ZERO
var _esc_wheel: Node3D
var _esc_anchor: Node3D
var _esc_ref: ClockworkPallet


func _pallet(low_top: Vector3, size: Vector3, parity: int) -> ClockworkPallet:
	var p := ClockworkPallet.new()
	p.size = size
	p.beat = ESC_BEAT
	p.snap = ESC_SNAP
	p.rise = ESC_RISE
	p.parity = parity
	p.style = "accent"
	p.position = low_top - V(0, size.y * 0.5, 0)
	add_child(p)
	# the pallet's rod slides in a fixed brass sleeve below it
	p.add_child(Look.cylinder(0.22, 4.0, Look.flat(Look.c("metal"), 0.4, 0.7), V(0, -size.y * 0.5 - 2.0, 0), -1.0, 12))
	kit.block(low_top + V(0, -3.6, 0), V(0.9, 3.0, 0.9), Look.c("decor2"), false)
	kit.block(low_top + V(0, -2.0, 0), V(1.2, 0.25, 1.2), Look.c("accent"), false)
	return p


## True just after the beat that levels pallet a (high) with pallet b (low); a = null: b is low.
func _esc_go(a: ClockworkPallet, b: ClockworkPallet, late: float = 0.32) -> bool:
	var t: float = Game.course_time
	var into: float = b.into_beat(t)
	if a != null and not a.is_high_at(t):
		return false
	return not b.is_high_at(t) and into > ESC_SNAP + 0.03 and into < ESC_SNAP + late


func _stage_15() -> void:
	var o: Vector3 = _cp14
	var sz: Vector3 = V(2.6, 0.6, 2.6)
	var pallets: Array[ClockworkPallet] = []
	var tops: Array[Vector3] = []
	for i: int in 5:
		var low: Vector3 = o + V(-1.5 if i % 2 == 0 else 1.5, ESC_RISE * i, -8.4 - 5.2 * i)
		pallets.append(_pallet(low, sz, i % 2))
		tops.append(low)
		# every tick throws gear sparks off the pallet and a puff of steam from its rail
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_fx_clock(low + V(side * 1.6, ESC_RISE * 0.5, 0), ESC_BEAT * 2.0, 0.0, [0.0, 0.5], [
			ClockworkFx.spark_burst(14, Color(1.0, 0.8, 0.35), 6.0, V(side, 1.0, 0), 40.0, 0.6),
			ClockworkFx.puff_burst(8, Color(0.95, 0.92, 1.0, 0.5), 2.4, 0.9, 1.0, false, 0.0, 0.2)])
	_esc_ref = pallets[0]
	# the curtain of light between pallets 3 and 4: dark only on the beat that levels them
	kit.laser(o + V(0, ESC_RISE * 3.0 + 1.4, -21.4), V(5.2, 2.8, 0.18), ESC_BEAT * 2.0, 0.5, 0.5)
	# the exit: a 3.2 m ledge over the top pallet's high rest
	var ledge_top: Vector3 = o + V(-0.5, ESC_RISE * 5.0 + 3.2, -34.5)
	kit.ledge(ledge_top, V(6.0, 6.0, 7.0))
	_cp15 = ledge_top
	kit.checkpoint(_cp15, 0.0)
	kit.lamp(_cp15 + V(2.5, 0, -3.0), 2.8)
	kit.lamp(_cp15 + V(-2.5, 0, -3.0), 2.8, false)
	_cp_fx(_cp15)
	kit.banner(o + V(-3.0, 0, -4.0), 3.6, Look.c("accent"))
	kit.banner(o + V(3.0, 0, -4.0), 3.6, Look.c("accent"))
	_build_escape_wheel(o + V(10.5, ESC_RISE * 2.5 + 1.0, -19.0))
	# warm embers rising through the works
	_fx(ClockworkFx.embers(V(5.0, 6.0, 15.0), 70, Color(1.0, 0.62, 0.25)), o + V(0, 6.0, -19.0))

	r_walk(o + V(-1.0, 0, -3.2))
	r_until(func() -> bool: return _esc_go(null, pallets[0]))
	var d0: Vector3 = _flat_dir(o + V(-1.0, 0, -3.2), tops[0])
	route.append({"kind": "b_jump", "from": o + V(-1.0, 0, -4.1), "to": tops[0] - d0 * 0.2, "hold": true})
	for i: int in 4:
		var a: ClockworkPallet = pallets[i]
		var b: ClockworkPallet = pallets[i + 1]
		var lvl: Vector3 = tops[i] + V(0, ESC_RISE, 0)
		var dir: Vector3 = _flat_dir(lvl, tops[i + 1])
		r_until(func() -> bool: return _esc_go(a, b))
		route.append({"kind": "b_jump", "from": lvl + dir * 0.9, "to": tops[i + 1] - dir * 0.2, "hold": true})
	var p4: ClockworkPallet = pallets[4]
	r_until(func() -> bool:
		var t: float = Game.course_time
		return p4.is_high_at(t) and p4.into_beat(t) > ESC_SNAP + 0.03 and p4.into_beat(t) < ESC_SNAP + 0.3)
	var hi4: Vector3 = tops[4] + V(0, ESC_RISE, 0)
	r_mantle(hi4 + V(0.3, 0, -0.8), V(hi4.x + 0.3, ledge_top.y, ledge_top.z + 1.6))
	r_walk(_cp15)
	r_checkpoint()


# =================================================================================================
# 16. THE STAMPING MILL (fork): LANE - three presses stamp in a travelling wave over a narrow lane;
#     dash from pocket to pocket behind the wave. WALL - leap off the ledge's right corner, run the
#     mill's case wall above the presses and kick down onto the far deck. Both meet under the last
#     press, which hammers the lip of a 3.4 m ledge: mantle up in its rhythm and get out from under.
# =================================================================================================

const MILL_PERIOD: float = 2.6
var _cp16 := Vector3.ZERO


func _stage_16() -> void:
	var o: Vector3 = _cp15
	var lane_c: Vector3 = o + V(0, 0, -14.0)
	kit.plat(lane_c, V(3.2, 0.8, 17.0), "main", 1.4)
	var presses: Array[Crusher] = []
	var pz: Array[float] = [-9.0, -14.0, -19.0]
	for k: int in 3:
		var ph: float = -0.2 * float(k)
		var c: Crusher = kit.crusher(o + V(0, 0, pz[k]), V(3.4, 1.6, 3.0), 3.2, MILL_PERIOD, ph)
		presses.append(c)
		_fx_clock(o + V(0, 0.15, pz[k]), MILL_PERIOD, ph, [0.52], [
			ClockworkFx.puff_burst(16, Color(0.9, 0.8, 0.7, 0.6), 5.0, 0.8, 0.8, false, 0.85, 0.25),
			ClockworkFx.spark_burst(18, Color(1.0, 0.55, 0.2), 7.0, V(0, 1, 0), 75.0, 0.55)])
	# WALL route: the mill's case wall on the right
	kit.wallrun(o + V(4.55, 1.2, -12.5), V(14.0, 7.0, 0.5), 90.0)
	kit.pillar(o + V(4.55, -2.3, -12.5), 0.5, 30.0)
	kit.glow_strip(o + V(4.55, -2.42, -12.5), V(0.2, 0.1, 13.6), Look.c("accent2"))
	kit.banner(o + V(2.6, 0, -2.6), 3.2, Look.c("accent2"))
	kit.banner(o + V(-1.8, 0, -2.6), 3.2, Look.c("accent"))
	# the deck both routes meet on
	var deck: Vector3 = o + V(0, 0, -27.0)
	kit.plat(deck, V(6.0, 1.0, 7.0), "alt", 1.5)
	# the stamped ledge
	var ledge_top: Vector3 = deck + V(0, 3.4, -9.5)
	kit.ledge(ledge_top, V(6.0, 7.0, 12.0))
	var lip: Crusher = kit.crusher(ledge_top + V(0, 0, 4.4), V(3.8, 1.6, 3.2), 2.8, 3.0, 0.1)
	_fx_clock(ledge_top + V(0, 0.15, 4.4), 3.0, 0.1, [0.52], [
		ClockworkFx.puff_burst(20, Color(0.9, 0.8, 0.7, 0.6), 5.5, 0.9, 0.9, false, 0.85, 0.25),
		ClockworkFx.spark_burst(22, Color(1.0, 0.55, 0.2), 8.0, V(0, 1, 0), 75.0, 0.6)])
	_cp16 = ledge_top + V(0, 0, -2.5)
	kit.checkpoint(_cp16, 0.0)
	kit.lamp(_cp16 + V(2.5, 0, -2.5), 2.8)
	kit.lamp(_cp16 + V(-2.5, 0, -2.5), 2.8, false)
	_cp_fx(_cp16)
	# mill chimneys venting steam either side
	for sx: int in [-1, 1]:
		kit.chimney(o + V(sx * 9.0, -9.0, -14.0), 13.0, 1.3, false)
		_fx(ClockworkFx.steam(V(0, 1, 0), 16, 2.6, 1.6), o + V(sx * 9.0, 4.2, -14.0))

	if route_variant == 0:
		# LANE: pocket to pocket behind the wave
		var pockets: Array[float] = [-6.3, -11.5, -16.5, -21.6]
		r_walk(o + V(0, 0, -3.0))
		r_jump(o + V(0, 0, -3.3), o + V(0, 0, pockets[0]))
		for k: int in 3:
			var c: Crusher = presses[k]
			r_until(func() -> bool: return c.is_clear_for(Game.course_time, 1.0))
			r_walk(o + V(0, 0, pockets[k + 1]))
		r_jump(o + V(0, 0, -22.1), deck + V(0, 0, 2.0))
	else:
		# WALL: run the case wall over the presses, kick down onto the deck
		r_walk(o + V(2.7, 0, 1.8))
		r_wallrun(o + V(2.75, 0, -2.1), o + V(3.95, 1.4, -6.6), o + V(3.95, 1.4, -17.4), deck + V(0.6, 0, 1.0))
	var from: Vector3 = deck + V(0, 0, -2.7)
	r_walk(from)
	r_until(func() -> bool:
		var t: float = Game.course_time
		return lip.is_clear_for(t, 1.7))
	r_mantle(from, ledge_top + V(0, 0, 1.8))
	r_walk(_cp16)
	r_checkpoint()


# =================================================================================================
# 17. THE LONGCASE: the inside of a tall case clock with no floor - three case walls zig-zag up
#     the shaft. Run the first, wall-jump across to the second, again to the third, and the last
#     kick throws you at a 3 m ledge you can only mantle. Two cracked stones to the checkpoint.
# =================================================================================================

var _cp17 := Vector3.ZERO
var _case_bob: Node3D


func _case_wall(o: Vector3, x: float, y: float, z0: float, z1: float) -> void:
	var c: Vector3 = o + V(x, y, (z0 + z1) * 0.5)
	kit.wallrun(c, V(absf(z0 - z1), 7.0, 0.5), 90.0)
	kit.pillar(c + V(0, -3.5, 0), 0.45, 24.0, Look.c("metal"))
	kit.glow_strip(c + V(0, -3.62, 0), V(0.2, 0.1, absf(z0 - z1) - 0.4), Look.c("accent2"))


func _stage_17() -> void:
	var o: Vector3 = _cp16 + V(0, 0, -1.0)
	_case_wall(o, 2.3, 1.2, -5.5, -12.0)
	_case_wall(o, -2.3, 6.0, -10.5, -18.5)
	_case_wall(o, 2.3, 9.0, -16.5, -24.5)
	var top: Vector3 = o + V(-0.75, 11.9, -28.0)
	kit.ledge(top, V(4.5, 14.0, 4.0))
	r_wallrun(o + V(0.5, 0, -2.1), o + V(1.7, 1.4, -6.6), o + V(1.7, 1.4, -9.5), o + V(-1.7, 5.5, -13.4))
	r_wallrun(Vector3.ZERO, o + V(-1.7, 5.5, -13.4), o + V(-1.7, 5.5, -16.4), o + V(1.7, 8.5, -20.0), true, true)
	r_wallrun(Vector3.ZERO, o + V(1.7, 8.5, -20.0), o + V(1.7, 8.5, -21.4), top + V(0, 0, 1.4), true, true)
	# the case: a clock face high on the far wall and the great pendulum swinging through the dark below
	var face: Vector3 = o + V(-12.0, 16.0, -16.0)
	kit.ring(face, 6.0, Look.c("accent"), Vector3(0, 0, 90))
	kit.ring(face, 5.2, Look.c("trim"), Vector3(0, 0, 90))
	var dial: Node3D = _at(Look.cylinder(5.4, 0.4, Look.flat(Look.c("decor2"), 0.6), Vector3.ZERO, -1.0, 40), face + V(-0.3, 0, 0))
	dial.rotation_degrees.z = 90.0
	add_child(dial)
	for h: int in 12:
		var a: float = TAU * float(h) / 12.0
		add_child(_at(Look.box(V(0.2, 0.9 if h % 3 == 0 else 0.5, 0.25), Look.flat(Look.c("accent"), 0.35, 0.0, 1.6)), face + V(0.05, cos(a) * 4.5, sin(a) * 4.5)))
	_case_bob = Node3D.new()
	_case_bob.position = o + V(-7.5, 22.0, -15.0)
	add_child(_case_bob)
	_case_bob.add_child(Look.box(V(0.25, 26.0, 0.25), Look.flat(Look.c("metal"), 0.4, 0.7), V(0, -13.0, 0)))
	_case_bob.add_child(Look.cylinder(2.2, 0.5, Look.flat(Look.c("accent"), 0.3, 0.7, 0.6), V(0, -26.0, 0), -1.0, 28))
	_case_bob.get_child(1).rotation.z = PI * 0.5
	_fx(ClockworkFx.motes(V(5.0, 9.0, 12.0), 50, Color(1.0, 0.85, 0.5)), o + V(0, 7.0, -15.0))

	# two cracked stones to the checkpoint
	var s1: Vector3 = o + V(1.0, 12.5, -33.6)
	var s2: Vector3 = o + V(-1.0, 13.1, -38.8)
	kit.collapse(s1, 1.8, 0.45)
	kit.collapse(s2, 1.8, 0.45)
	_cp17 = o + V(0, 13.5, -45.5)
	_cp(_cp17, V(6, 2, 6), 0.0, "alt")
	_cp_fx(_cp17)
	r_walk(top + V(0.9, 0, -1.2))
	_hop(top + V(0.9, 0, -1.2), s1, 0.4)
	_hop(s1, s2, 0.55)
	r_jump(s2 + _flat_dir(s2, _cp17 + V(0, 0, 2.2)) * 0.55, _cp17 + V(0, 0, 2.2))
	r_walk(_cp17)
	r_checkpoint()


# =================================================================================================
# 18. THE CUCKOO (fork): CLIMB - two 3.3 m ledges, each crossed by a curtain of light: mantle,
#     time the curtain, mantle again. DOOR - three 1.1 m perches out to the right lead to the
#     cuckoo's door, a warp that drops you on the top ledge. Every 4 s the cuckoo pops out.
# =================================================================================================

var _cp18 := Vector3.ZERO
var _cuckoo: Node3D
var _cuckoo_home_z: float = 0.0
const CUCKOO_PERIOD: float = 4.0


func _stage_18() -> void:
	var o: Vector3 = _cp17
	# CLIMB
	kit.plat(o + V(0, 0, -8.5), V(3.4, 0.8, 7.0), "main", 1.2)
	var l1: Vector3 = o + V(0, 3.3, -15.0)
	kit.ledge(l1, V(4.0, 6.0, 6.0))
	var l2: Vector3 = o + V(0, 6.6, -24.0)
	kit.ledge(l2, V(6.0, 9.0, 12.0), 0.0, "alt")
	var g1: LaserGate = kit.laser(l1 + V(0, 1.3, -0.4), V(4.4, 2.6, 0.18), 2.4, 0.45, 0.0)
	var g2: LaserGate = kit.laser(l2 + V(0, 1.3, 2.8), V(6.4, 2.6, 0.18), 2.4, 0.45, 0.5)
	kit.banner(o + V(-2.4, 0, -2.6), 3.2, Look.c("accent"))
	# DOOR: perches, then the cuckoo's door
	var perches: Array[Vector3] = [o + V(5.2, 0.6, -7.8), o + V(7.0, 1.4, -13.9), o + V(6.2, 2.2, -19.4)]
	for p: Vector3 in perches:
		kit.disc(p, 0.55, 0.6, "accent", 3.0)
		kit.glow_strip(p + V(0, 0.04, 0), V(0.5, 0.05, 0.5), Look.c("accent2"), 45.0)
	var door: Vector3 = o + V(6.2, 2.6, -25.0)
	kit.plat(door, V(2.4, 0.6, 3.0), "accent", 1.0)
	var exit_floor: Vector3 = l2 + V(0, 0, 1.6)
	var warp: WarpPortal = kit.portal(door + V(0, 0, -0.6), 0.0, exit_floor, 0.0, 7.0)
	kit.banner(o + V(2.6, 0, -2.6), 3.2, Look.c("accent2"))
	_build_cuckoo_house(door + V(0, 0, -2.2))
	_cp18 = l2 + V(0, 0, -3.5)
	kit.checkpoint(_cp18, 0.0)
	kit.lamp(_cp18 + V(2.5, 0, -2.0), 2.8)
	kit.lamp(_cp18 + V(-2.5, 0, -2.0), 2.8, false)
	_cp_fx(_cp18)
	# blue arrival sparkle where the warp drops you
	_fx_near(warp.exit_point() + V(0, 0.8, 0), 1.8, [
		ClockworkFx.puff_burst(24, Color(0.45, 0.75, 1.0, 0.8), 4.0, 0.5, 0.8, true, 0.0, 0.6),
		ClockworkFx.spark_burst(20, Color(0.55, 0.85, 1.0), 6.5, V(0, 1, 0), 70.0, 0.6)])

	if route_variant == 0:
		r_walk(o + V(0, 0, -2.4))
		r_jump(o + V(0, 0, -2.7), o + V(0, 0, -6.0))
		r_walk(o + V(0, 0, -10.8))
		r_mantle(o + V(0, 0, -11.2), l1 + V(0, 0, 1.6))
		r_until(func() -> bool: return _lasers_off([[g1, 0.3]], 0.3))
		r_walk(l1 + V(0, 0, -2.4))
		r_mantle(l1 + V(0, 0, -2.6), l2 + V(0, 0, 4.9))
		r_until(func() -> bool: return _lasers_off([[g2, 0.3]], 0.3))
		r_walk(l2 + V(0, 0, 2.6))
	else:
		r_walk(o + V(2.4, 0, -1.6))
		_hop(o + V(2.4, 0, -1.6), perches[0], 0.9)
		_hop(perches[0], perches[1], 0.4)
		_hop(perches[1], perches[2], 0.4)
		r_jump(perches[2] + V(0, 0, -0.4), door + V(0, 0, 0.8))
		r_portal(door + V(0, 0, -0.9), warp.exit_point())
	r_walk(_cp18)
	r_checkpoint()


## The cuckoo clock facade behind its door, and the bird that pops out on the course clock.
func _build_cuckoo_house(c: Vector3) -> void:
	var wood: StandardMaterial3D = Look.flat(Look.c("decor"), 0.7)
	kit.block(c + V(0, 3.2, -0.6), V(5.2, 6.4, 1.2), Look.c("decor2"), false)
	for sx: int in [-1, 1]:
		var roof := Look.box(V(3.6, 0.4, 2.0), wood, c + V(sx * 1.5, 7.1, -0.4))
		roof.rotation.z = -sx * 0.6
		add_child(roof)
		kit.block(c + V(sx * 2.0, 1.6, 0.2), V(0.5, 3.2, 0.5), Look.c("metal"), false)
	kit.ring(c + V(0, 5.3, 0.05), 1.0, Look.c("accent"), Vector3(90, 0, 0))
	_cuckoo = Node3D.new()
	_cuckoo.position = c + V(0, 5.3, -0.2)
	_cuckoo_home_z = _cuckoo.position.z
	add_child(_cuckoo)
	_cuckoo.add_child(Look.sphere(0.45, Look.flat(Color(0.85, 0.5, 0.35), 0.5)))
	_cuckoo.add_child(Look.sphere(0.3, Look.flat(Color(0.95, 0.65, 0.4), 0.5), V(0, 0.35, 0.25)))
	var beak := Look.box(V(0.12, 0.12, 0.35), Look.flat(Look.c("accent"), 0.4), V(0, 0.33, 0.6))
	_cuckoo.add_child(beak)
	# a puff of feathers every time it calls
	_fx_clock(c + V(0, 5.3, 1.2), CUCKOO_PERIOD, 0.0, [0.1], [
		ClockworkFx.puff_burst(14, Color(1.0, 0.9, 0.7, 0.9), 3.0, 0.25, 1.4, false, 0.0, 0.6),
		ClockworkFx.spark_burst(10, Color(1.0, 0.8, 0.4), 4.0, V(0, 1, 1), 50.0, 0.7)])


## The escape wheel beside the pallets: turns one tooth per beat, with the anchor rocking over it.
func _build_escape_wheel(c: Vector3) -> void:
	var holder: Node3D = kit.gear(c, 8.5, ESC_TEETH, 0.8, 0.0, Vector3(0, 0, 90), Look.c("decor"))
	_esc_wheel = holder.get_child(0)
	kit.pipe(c + V(-1.5, 0, 0), c + V(3.0, 0, 0), 0.5, Look.c("metal"))
	kit.block(c + V(2.6, -9.5, 0), V(1.2, 19.0, 2.4), Look.c("decor2"), false)
	_esc_anchor = Node3D.new()
	_esc_anchor.position = c + V(-0.2, 10.4, 0)
	add_child(_esc_anchor)
	var brass: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.7)
	for sz: int in [-1, 1]:
		var arm := Look.box(V(0.5, 0.5, 7.0), brass, V(0, -1.6, sz * 3.0))
		arm.rotation.x = sz * 0.5
		_esc_anchor.add_child(arm)
		_esc_anchor.add_child(Look.box(V(0.6, 2.2, 0.6), Look.flat(Look.c("accent"), 0.35, 0.6, 0.8), V(0, -3.6, sz * 5.6)))
	_esc_anchor.add_child(Look.cylinder(0.7, 1.0, brass, V(0, 0, 0), -1.0, 16))
	add_child(_at(Look.box(V(0.8, 0.8, 3.0), brass, Vector3.ZERO), c + V(-0.2, 10.4, 0)))


# =================================================================================================
# surroundings
# =================================================================================================

func _build_surroundings() -> void:
	var towers: Array = [
		[V(-13, -4, -30), V(5, 26, 5)], [V(13, -2, -60), V(4, 30, 4)], [V(-12, 2, -110), V(5, 30, 5)],
		[V(14, 4, -150), V(4, 34, 4)], [V(-16, 6, -185), V(5, 38, 5)], [V(-8, 10, -240), V(5, 40, 5)],
		[V(52, 8, -215), V(6, 44, 6)], [V(78, 10, -270), V(5, 40, 5)], [V(46, 12, -300), V(4, 34, 4)],
		[V(78, 12, -350), V(5, 42, 5)], [V(44, 10, -400), V(5, 38, 5)], [V(90, 14, -440), V(6, 46, 6)],
		[V(30, 12, -470), V(5, 40, 5)], [V(95, 16, -495), V(5, 44, 5)],
	]
	for t: Array in towers:
		var c: Vector3 = t[0]
		var sz: Vector3 = t[1]
		kit.block(c, sz, Look.c("decor"), false)
		kit.block(c + V(0, sz.y * 0.5 + 0.4, 0), V(sz.x + 1.0, 0.8, sz.z + 1.0), Look.c("metal"), false)
		var spire := Look.cylinder(sz.x * 0.55, sz.x * 1.4, Look.flat(Look.c("decor2"), 0.7), Vector3.ZERO, 0.0, 4)
		spire.rotation_degrees.y = 45.0
		add_child(_at(spire, c + V(0, sz.y * 0.5 + 0.8 + sz.x * 0.7, 0)))
		kit.glow_strip(c + V(0, sz.y * 0.28, sz.z * 0.5 + 0.03), V(sz.x * 0.35, sz.y * 0.18, 0.06), Look.c("accent"))
		kit.gear(c + V(0, sz.y * 0.05, sz.z * 0.5 + 0.3), sz.x * 0.42, 10, 0.3, kit.rng.randf_range(6.0, 14.0))
	# great gears under and beside the clock
	kit.gear(K + V(0, -19.0, 0), 11.0, 26, 1.2, 40.0, Vector3.ZERO, Look.c("decor"))
	kit.gear(K + V(19.5, -17.0, 9.0), 6.0, 16, 1.0, -18.5, Vector3.ZERO)
	kit.gear(K + V(-21.0, -16.5, -7.0), 7.5, 18, 1.0, -23.0, Vector3.ZERO)
	kit.gear(K + V(-30.0, 8.0, -16.0), 8.0, 20, 0.9, 30.0, Vector3(90, 60, 0), Look.c("decor"))
	kit.gear(K + V(30.0, 4.0, -18.0), 6.0, 16, 0.8, -20.0, Vector3(90, -55, 0))
	kit.gear(V(16, 4, -20), 4.5, 14, 0.6, 16.0, Vector3(90, -35, 0))
	kit.gear(V(-16, 10, -95), 5.0, 14, 0.7, -14.0, Vector3(90, 40, 0), Look.c("decor"))
	kit.gear(V(18, 14, -170), 5.5, 16, 0.7, 18.0, Vector3(90, 70, 0))
	kit.gear(V(74, 24, -320), 5.0, 14, 0.7, -15.0, Vector3(90, -60, 0), Look.c("decor"))
	kit.cloud_field(V(35, -28, -250), V(180, 8, 300), 44)
	kit.cloud_field(V(35, 60, -250), V(200, 10, 320), 14)
	kit.monolith_ring(V(35, 6, -245), 300.0, 370.0, 20, 30.0)


func _process(_dt: float) -> void:
	if _spokes != null:
		_spokes.rotation.x = -fposmod(Game.course_time / WHEEL_PERIOD, 1.0) * TAU
	if _bell != null:
		_bell.rotation.z = sin(Game.course_time * TAU / 4.0) * 0.22
	if _case_bob != null:
		_case_bob.rotation.x = sin(Game.course_time * TAU / 3.2) * 0.22
	if _cuckoo != null:
		# out of its door for a moment every CUCKOO_PERIOD seconds
		var u: float = fposmod(Game.course_time / CUCKOO_PERIOD, 1.0)
		var out: float = clampf(minf(u / 0.06, (0.4 - u) / 0.08), 0.0, 1.0)
		_cuckoo.position.z = _cuckoo_home_z + out * 1.3
		_cuckoo.rotation.x = -sin(u * TAU * 6.0) * 0.3 * out
	if _esc_wheel != null:
		# one tooth per beat, snapping with the pallets
		var t: float = Game.course_time
		var b: float = t / ESC_BEAT
		var k: float = clampf((b - floorf(b)) * ESC_BEAT / ESC_SNAP, 0.0, 1.0)
		_esc_wheel.rotation.y = (floorf(b) + k * k * (3.0 - 2.0 * k)) * TAU / float(ESC_TEETH)
		_esc_anchor.rotation.x = (_esc_ref.level_at(t) - 0.5) * 0.24
