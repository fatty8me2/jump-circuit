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
	_second_b.add_child(Look.box(V(4.2, 0.2, 0.2), dark, V(2.1, 1.2, 0)))
	_second_b.add_child(Look.box(V(0.2, 1.2, 0.2), dark, V(4.2, 0.6, 0)))
	_second_b.add_child(Look.cylinder(0.3, 1.4, dark, V(0, 0.7, 0), -1.0, 10))

	# tower ledge: down the tangent from the east point, 1.8 m up
	var t0: Vector3 = V(K.x + 7.6, y + 1.8, K.z - 2.7 - 10.8)
	_cp(t0, V(5, 1, 5), -45.0)
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
	kit.disc(belfry, 5.2, 1.0, "accent", 4.0)
	kit.finish(belfry, 0.0)
	_build_belfry(belfry)


func _build_belfry(belfry: Vector3) -> void:
	for i: int in 4:
		var post: Vector3 = belfry + V(cos(PI * 0.25 + PI * 0.5 * i), 0, sin(PI * 0.25 + PI * 0.5 * i)) * 4.4
		kit.pillar(post + V(0, 8.0, 0), 0.4, 8.0, Look.c("metal"))
	var roof := Look.cylinder(6.2, 5.0, Look.flat(Look.c("decor2"), 0.7), Vector3.ZERO, 0.0, 8)
	add_child(_at(roof, belfry + V(0, 10.7, 0)))
	add_child(_at(Look.cylinder(6.4, 0.4, Look.flat(Look.c("trim"), 0.5, 0.4), Vector3.ZERO, -1.0, 8), belfry + V(0, 8.2, 0)))
	add_child(_at(Look.sphere(0.5, Look.flat(Look.c("accent"), 0.3, 0.0, 3.0)), belfry + V(0, 13.6, 0)))
	kit.ring(belfry + V(0, 4.0, 0), 7.4, Look.c("accent"), Vector3(90, 0, 0))
	_bell = Node3D.new()
	_bell.position = belfry + V(0, 8.0, 0)
	add_child(_bell)
	_bell.add_child(Look.cylinder(0.09, 2.4, Look.flat(Look.c("metal"), 0.4, 0.7), V(0, -1.2, 0), -1.0, 8))
	_bell.add_child(Look.cylinder(1.3, 1.6, Look.flat(Look.c("accent"), 0.35, 0.6, 0.8), V(0, -3.0, 0), 0.6, 20))
	# the tower shaft that carries the belfry, rising from the hub
	kit.pillar(belfry + V(0, -1.0, 0), 1.2, belfry.y - K.y - 8.0, Look.c("decor"))


func _physics_process(dt: float) -> void:
	super(dt)
	if _second_b != null:
		_second_b.rotation.y = _second_b_angle(Game.course_time)


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
