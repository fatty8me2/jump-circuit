extends LevelBase
## 5. THE FINAL ASCENT - a night climb up a neon spire complex to the beacon.
## Five stages, each behind a checkpoint, each leaning on one earlier lesson
## and then mixing in another:
##   1 pads + jumps   2 balance + pad   3 ferry + collapsing stones
##   4 lift + turntable   5 the pad chain to the summit
## Set piece: lighting the beacon.

var _beam: MeshInstance3D
var _beacon_light: OmniLight3D
var _beacon_pos: Vector3
var _rings: Array[MeshInstance3D] = []
var _crystal: MeshInstance3D
var _env: Environment


func _configure() -> void:
	theme_id = "ascent"
	music_track = "b"
	kill_y = -30.0


func _build() -> void:
	_stars()
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	var cp: Vector3 = _stage_1()
	cp = _stage_2(cp)
	cp = _stage_3(cp)
	cp = _stage_4(cp)
	cp = _stage_5(cp)
	cp = _stage_6(cp)
	cp = _stage_7(cp)
	cp = _stage_8(cp)
	cp = _stage_9(cp)
	cp = _stage_10(cp)
	cp = _stage_11(cp)
	_stage_12(cp)
	_surroundings()


# ---- helpers ------------------------------------------------------------------------------------------

var _tuning: MovementTuning
var _o: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _basis: Basis = Basis.IDENTITY


## Stage frame: local -Z is "forward", turned by yaw about the stage origin.
func _frame(o: Vector3, yaw_deg: float) -> void:
	_o = o
	_yaw = yaw_deg
	_basis = Basis(Vector3.UP, deg_to_rad(yaw_deg))


func W(x: float, y: float, z: float) -> Vector3:
	return _o + _basis * Vector3(x, y, z)


func D(v: Vector3) -> Vector3:
	return _basis * v


func _sz(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0 else size


func _step(s: Dictionary) -> void:
	route.append(s)


func _speed(v: float) -> void:
	route[route.size() - 1]["speed"] = v


func _wait(test: Callable) -> void:
	route.append({"kind": "b_wait", "test": test})


## Takeoff spot: `inset` inside the edge of an axis-aligned pad of half-extents `half`, heading for `toward`.
func _edge(c: Vector3, half: float, toward: Vector3, inset: float = 0.35) -> Vector3:
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	var k: float = half / maxf(maxf(absf(d.x), absf(d.z)), 0.001)
	return c + d * (k - inset)


## Neon parkour block + the jump onto it from the previous block.
func _hop(a: Vector3, a_half: float, b: Vector3, size: float = 1.8, style: String = "alt", hold: bool = true) -> Vector3:
	kit.plat(b, Vector3(size, 0.8, size), style, 0.0)
	kit.glow_strip(b - Vector3(0, 0.86, 0), Vector3(size * 0.7, 0.08, size * 0.7), Look.c("accent2") if style == "alt" else Look.c("accent"))
	r_jump(_edge(a, a_half, b), b, hold)
	return b


func _cp_plat(c: Vector3, yaw_deg: float, size: float = 5.0) -> void:
	kit.plat(c, Vector3(size, 1.4, size), "main")
	kit.checkpoint(c, yaw_deg)
	kit.pillar(c - Vector3(0, 1.4, 0), 1.0, 40.0)


# ---- stage 1: neon ladder ---------------------------------------------------------------------------------

func _stage_1() -> Vector3:
	_frame(Vector3.ZERO, 0.0)
	set_spawn(Vector3(0, 0.1, 3), 0.0)
	kit.plat(W(0, 0, 0), Vector3(10, 2, 10))
	kit.arch(W(0, 0, -4.2), 5.0, 4.4)
	kit.lamp(W(-4, 0, 4), 3.2)
	kit.lamp(W(4, 0, 4), 3.2, true, Look.c("accent2"))
	# warm-up: three rising diagonals
	var a: Vector3 = W(0, 0, 0)
	a = _hop(a, 5.0, W(0, 1.0, -9.6))
	a = _hop(a, 0.9, W(3.0, 2.0, -14.2))
	a = _hop(a, 0.9, W(0, 3.0, -18.8))
	# head-hitters: low neon ceilings turn a full jump into a short one
	for i: int in 3:
		var z: float = -22.15 - 3.0 * i
		kit.block(W(0, 3.0 + 2.5 + 0.25, z + 1.5), Vector3(3.0, 0.5, 2.6), Look.c("side").lightened(0.1))
		kit.glow_strip(W(0, 3.0 + 2.47, z + 1.5), Vector3(2.6, 0.06, 2.2), Look.c("accent2"))
		a = _hop(a, 0.9 if i == 0 else 0.75, W(0, 3.0, z), 1.5)
	# the ladder: 1.9 m up per block, zig-zag
	var half: float = 0.75
	for i: int in 5:
		var x: float = [2.2, 0.0, -2.2, 0.0, 2.2][i]
		a = _hop(a, half, W(x, 4.9 + 1.9 * i, -32.5 - 4.3 * i), 1.6)
		half = 0.8
	# kill-brick slalom on the landing deck
	kit.plat(W(0, 13.0, -56.4), Vector3(5, 1, 7), "main")
	kit.hazard(W(-1.0, 13.35, -55.0), Vector3(3.0, 0.7, 0.8))
	kit.hazard(W(1.0, 13.35, -57.4), Vector3(3.0, 0.7, 0.8))
	r_jump(_edge(a, 0.8, W(1.6, 13.0, -53.9)), W(1.6, 13.0, -53.9))
	r_walk(W(1.6, 13.0, -55.6))
	r_walk(W(-1.6, 13.0, -56.3))
	r_walk(W(-1.6, 13.0, -58.4))
	var cp: Vector3 = W(0, 13.0, -67.0)
	_cp_plat(cp, 0.0)
	r_jump(W(-1.0, 13.0, -59.55), W(0, 13.0, -65.6))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 2: boost strip -> long leap -> pad at sprint -> small disc -----------------------------------------------

func _stage_2(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	kit.boost(W(0, 0, -8.5), Vector3(3, 0.4, 12), _yaw, 20.0)
	kit.glow_strip(W(0, 0.03, -14.3), Vector3(3, 0.06, 0.25), Look.c("accent2"))
	kit.disc(W(0, 0, -29.1), 2.2, 0.8, "accent")
	kit.pad(W(0, 0, -29.1), 20.0, 0.0, 0.0, 1.5)
	kit.disc(W(0, 4.5, -47.1), 1.7, 0.8, "accent")
	r_jump(W(0, 0, -14.1), W(0, 0, -30.1))
	_speed(19.5)
	r_pad(W(0, 0, -29.1), W(0, 4.5, -47.1))
	# long runway: arrive slow and it is a plain hop, arrive hot and you fly half of it
	var cp: Vector3 = W(0, 5.5, -62.0)
	kit.plat(W(0, 5.5, -60.4), Vector3(5, 1.4, 16), "main")
	kit.checkpoint(cp, 90.0)
	kit.pillar(W(0, 4.1, -60.4), 1.0, 40.0)
	r_jump(W(0, 4.5, -48.45), W(0, 5.5, -55.0))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 3: ice slide -> lip leap -> angled pad -> blink platform -------------------------------------------------

func _stage_3(o: Vector3) -> Vector3:
	_frame(o, 90.0)
	var drop: float = 16.0 * sin(deg_to_rad(25.0))
	var run: float = 16.0 * cos(deg_to_rad(25.0))
	kit.slick(W(0, -drop * 0.5, -2.5 - run * 0.5), Vector3(3.5, 0.4, 16), _yaw, -25.0)
	var lip_z: float = -2.5 - run - 6.0
	kit.slick(W(0, -drop, lip_z + 3.0), Vector3(3.5, 0.4, 6.0), _yaw, 0.0)
	kit.glow_strip(W(0, -drop + 0.03, lip_z + 0.2), Vector3(3.5, 0.06, 0.25), Look.c("accent2"))
	var pad_pos: Vector3 = W(0, -drop - 1.0, lip_z - 18.6)
	kit.disc(pad_pos, 2.2, 0.8, "accent")
	var pad: BouncePad = kit.pad(pad_pos, 28.0, 30.0, _yaw, 1.6)
	var land: Vector3 = Ballistics.landing_point(_tuning, pad.launch_origin(), pad.get_launch()["velocity"], pad_pos.y + 8.5)
	var blink: BlinkPlatform = kit.blink(land, Vector3(3.2, 0.4, 3.2), 3.0, 0.6)
	_wait(func() -> bool: return blink.is_on_at(Game.course_time + 3.3) and blink.is_on_at(Game.course_time + 4.6))
	r_walk(W(0, -drop, lip_z + 2.0))
	r_jump(W(0, -drop, lip_z + 0.4), pad_pos + D(Vector3(0, 0, -0.8)))
	_speed(24.0)
	r_pad(pad_pos, land)
	var cp: Vector3 = land + D(Vector3(0, 1.5, -7.6))
	_cp_plat(cp, 90.0)
	r_jump(land + D(Vector3(0, 0, -1.25)), cp + D(Vector3(0, 0, 1.5)))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 4: lively narrow beams, cross-wind, a hammer ------------------------------------------------------------

## Narrow tilt beam running along the stage heading. `d` = forward distance of its centre.
func _tbeam(d: float, y: float, length: float, width: float, roll: bool, pitch: bool, edge: float) -> TiltPlatform:
	var along_x: bool = absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0
	var opts: Dictionary = {"edge_tilt_deg": edge, "max_tilt_deg": edge + 7.0, "board_mass": 90.0}
	opts["tilt_about_x"] = roll if along_x else pitch
	opts["tilt_about_z"] = pitch if along_x else roll
	return kit.tilt(W(0, y, -d), _sz(Vector3(width, 0.4, length)), opts)


func _stage_4(o: Vector3) -> Vector3:
	_frame(o, 90.0)
	# beam 1: see-saw in a cross-wind
	_tbeam(8.3, 0.0, 9.0, 1.0, false, true, 9.0)
	kit.wind(W(0, 1.6, -8.3), _sz(Vector3(7, 4, 10)), D(Vector3(13, 0, 0)), 14.0)
	r_jump(W(0, 0, -2.15), W(0, 0, -5.0), false)
	r_walk(W(0, 0, -12.0))
	var rest1: Vector3 = W(0, 0.6, -16.6)
	kit.plat(rest1, Vector3(1.8, 0.8, 1.8), "alt", 0.0)
	r_jump(W(0, 0, -12.5), rest1)
	# beam 2: rolls under you, hammer across the middle, wind from the other side
	_tbeam(24.3, 0.6, 9.0, 0.9, true, false, 16.0)
	kit.wind(W(0, 2.2, -24.3), _sz(Vector3(7, 4, 10)), D(Vector3(-13, 0, 0)), 14.0)
	var ham: Pendulum = kit.pendulum(W(0, 0.6 + 8.1, -24.3), 7.0, 2.6, 0.0, _yaw, 50.0)
	kit.arch(W(0, -0.4, -24.3), 9.0, 9.0, _yaw, Look.c("side").lightened(0.2))
	_wait(func() -> bool: return absf(ham.angle_at(Game.course_time + 1.0)) > 0.5 and absf(ham.angle_at(Game.course_time + 1.35)) > 0.4)
	r_jump(W(0, 0.6, -17.15), W(0, 0.6, -21.0))
	r_walk(W(0, 0.6, -28.0))
	var rest2: Vector3 = W(0, 1.4, -32.8)
	kit.plat(rest2, Vector3(1.6, 0.8, 1.6), "alt", 0.0)
	r_jump(W(0, 0.6, -28.5), rest2)
	# beam 3: rolls AND see-saws, thinner, climbing
	_tbeam(40.5, 2.2, 8.0, 0.8, true, true, 11.0)
	r_jump(W(0, 1.4, -33.25), W(0, 2.2, -37.6))
	r_walk(W(0, 2.2, -43.6))
	var cp: Vector3 = W(0, 3.4, -51.0)
	_cp_plat(cp, 0.0)
	r_jump(W(0, 2.2, -44.1), cp + D(Vector3(0, 0, 1.6)))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 5: ferry sling into a collapsing curve --------------------------------------------------------------------

func _stage_5(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	var pts: Array[Vector3] = [Vector3.ZERO, D(Vector3(0, 0, -14))]
	var ferry: MovingPlatform = kit.mover(W(0, 0, -5.2), _sz(Vector3(3, 0.5, 3.4)), pts, 3.4)
	kit.glow_strip(W(-2.2, -0.3, -12.2), _sz(Vector3(0.12, 0.12, 18)), Look.c("accent2"))
	kit.glow_strip(W(2.2, -0.3, -12.2), _sz(Vector3(0.12, 0.12, 18)), Look.c("accent2"))
	_step({"kind": "walk", "to": W(0, 0, -1.6)})
	_step({"kind": "x_wait", "nodes": [ferry], "locals": [Vector3.ZERO], "point": W(0, -0.25, -5.2), "radius": 0.3, "lead": 0.35})
	_step({"kind": "x_jump", "from": W(0, 0, -2.2), "to_node": ferry, "to_local": D(Vector3(0, 0.25, 1.0)), "hold": false})
	_wait(func() -> bool: return ferry.offset_at(Game.course_time).length() > 5.2 and ferry.offset_at(Game.course_time + 0.1).length() > ferry.offset_at(Game.course_time).length())
	var s1: Vector3 = W(0, 0.8, -31.0)
	kit.collapse(s1, 3.2, 0.6)
	_step({"kind": "h_jump", "from_node": ferry, "from_local": D(Vector3(0, 0.25, -1.2)), "to": s1, "sprint": true, "speed": 22.0})
	var stones: Array[Vector3] = [W(-3.0, 1.4, -36.9), W(-8.2, 2.0, -41.0), W(-14.6, 2.6, -42.5), W(-20.9, 3.2, -40.8)]
	var a: Vector3 = s1
	var half: float = 1.6
	for st: Vector3 in stones:
		kit.collapse(st, 2.4, 0.55)
		r_jump(_disc_edge(a, half, st), st)
		a = st
		half = 1.2
	var cp: Vector3 = W(-28.4, 3.8, -39.2)
	_cp_plat(cp, 0.0)
	r_jump(_disc_edge(a, 1.2, cp), cp + (a - cp).normalized() * 1.2)
	r_walk(cp)
	r_checkpoint()
	return cp


func _disc_edge(c: Vector3, radius: float, toward: Vector3, inset: float = 0.35) -> Vector3:
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	return c + d * (radius - inset)


# ---- stage 6: the sling table - turntable, sweeper bars, arm-tip sling ----------------------------------------------

func _ang_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


## True when no sweeper bar comes within `margin` rad of world angle `ang` during [t0, t1].
func _bars_clear(sw: Sweeper, ang: float, t0: float, t1: float, margin: float = 0.5) -> bool:
	var t: float = t0
	while t <= t1:
		for i: int in sw.bar_count:
			if _ang_diff(sw.angle_at(t) + TAU * float(i) / float(sw.bar_count), ang) < margin:
				return false
		t += 0.05
	return true


func _stage_6(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	var hub: Vector3 = W(0, 0, -14.0)
	var arms: Array[Dictionary] = [
		{"pos": Vector3(6.0, 0, 0), "size": Vector3(9.0, 0.5, 2.6)}, {"pos": Vector3(-6.0, 0, 0), "size": Vector3(9.0, 0.5, 2.6)},
	]
	var table: RotatingPlatform = kit.spinner(hub, 6.0, arms, 2.0)
	kit.pillar(hub - Vector3(0, 0.6, 0), 1.2, 40.0)
	var sw: Sweeper = kit.sweeper(hub, 10.0, 2, 12.0, 0.5417, 0.45)
	var board_ang: float = 1.5 * PI
	var release_ang: float = 0.5 * PI
	r_walk(W(0, 0, -1.4))
	_wait(func() -> bool:
		var t: float = Game.course_time
		return _ang_diff(table.angle_at(t + 0.55), board_ang) < 0.1 and _bars_clear(sw, board_ang, t, t + 1.4, 0.6))
	_step({"kind": "x_jump", "from": W(0, 0, -2.2), "to_node": table, "to_local": Vector3(7.6, 0.25, 0)})
	_step({"kind": "x_walk_on", "node": table, "local": Vector3(9.7, 0.25, 0), "tol": 0.4})
	_step({"kind": "h_hop", "node": table, "local": Vector3(9.7, 0.25, 0), "sweepers": [sw],
		"until": func() -> bool: return _ang_diff(table.angle_at(Game.course_time + 0.3), release_ang) < 0.12})
	var cp: Vector3 = hub + D(Vector3(-8.7, 0.6, -10.4))
	_step({"kind": "x_jump", "from_node": table, "from_local": Vector3(9.9, 0.25, 0), "when_node": table, "when_local": Vector3(9.9, 0, 0),
		"when_point": hub + D(Vector3(0, -0.25, -9.9)), "when_radius": 0.8, "lead": 0.0, "to": cp + D(Vector3(0.6, 0, 0)), "speed": 12.0})
	_cp_plat(cp, -90.0)
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 7: neon ladder II - blinking, moving and kill-wrapped blocks ---------------------------------------------

func _stage_7(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	var a: Vector3 = _hop(W(0, 0, 0), 2.5, W(0, 1.2, -6.4), 1.6)
	# blink block
	var k1p: Vector3 = W(2.4, 2.6, -10.6)
	var k1: BlinkPlatform = kit.blink(k1p, Vector3(2.0, 0.5, 2.0), 2.4, 0.6, 0.0)
	_wait(func() -> bool: return k1.is_on_at(Game.course_time + 0.7) and k1.is_on_at(Game.course_time + 1.25))
	r_jump(_edge(a, 0.8, k1p), k1p)
	a = _hop(k1p, 1.0, W(0, 4.2, -14.8), 1.5)
	# sliding block
	var mpts: Array[Vector3] = [D(Vector3(-3, 0, 0)), D(Vector3(3, 0, 0))]
	var m1: MovingPlatform = kit.mover(W(0, 5.4, -19.6), Vector3(2.0, 0.5, 2.0), mpts, 4.0)
	_step({"kind": "x_wait", "nodes": [m1], "locals": [Vector3.ZERO], "point": W(0, 5.15, -19.6), "radius": 1.2, "lead": 0.75})
	_step({"kind": "x_jump", "from": _edge(a, 0.75, W(0, 0, -19.6)), "to_node": m1, "to_local": Vector3(0, 0.25, 0)})
	var b3: Vector3 = W(0, 7.0, -24.4)
	kit.plat(b3, Vector3(1.6, 0.8, 1.6), "alt", 0.0)
	kit.hazard(b3 + D(Vector3(-1.5, 0.5, 0)), _sz(Vector3(0.8, 1.8, 1.6)))
	kit.hazard(b3 + D(Vector3(1.5, 0.5, 0)), _sz(Vector3(0.8, 1.8, 1.6)))
	_step({"kind": "x_jump", "from_node": m1, "from_local": D(Vector3(0, 0.25, -0.6)), "when_node": m1, "when_local": Vector3.ZERO,
		"when_point": W(0, 5.15, -19.6), "when_radius": 1.0, "lead": 0.35, "to": b3})
	# two blinks out of phase: no stopping between them
	var k2p: Vector3 = W(-2.4, 8.7, -28.4)
	var k3p: Vector3 = W(0, 10.4, -32.6)
	var k2: BlinkPlatform = kit.blink(k2p, Vector3(1.9, 0.5, 1.9), 2.4, 0.6, 0.0)
	var k3: BlinkPlatform = kit.blink(k3p, Vector3(1.9, 0.5, 1.9), 2.4, 0.6, -0.36)
	_wait(func() -> bool:
		var t: float = Game.course_time
		return k2.is_on_at(t + 0.7) and k2.is_on_at(t + 1.2) and k3.is_on_at(t + 1.5) and k3.is_on_at(t + 2.2))
	r_jump(_edge(b3, 0.8, k2p), k2p)
	r_jump(_edge(k2p, 0.95, k3p), k3p)
	a = _hop(k3p, 0.95, W(2.2, 12.1, -36.8), 1.5)
	# kill ceiling: tap jumps only
	var b5: Vector3 = W(2.2, 12.1, -40.3)
	kit.hazard(W(2.2, 12.1 + 2.75 + 0.2, -38.55), _sz(Vector3(2.6, 0.4, 3.4)))
	a = _hop(a, 0.75, b5, 1.5, "alt", false)
	a = _hop(a, 0.75, W(0, 13.9, -44.4), 1.5)
	var cp: Vector3 = W(0, 15.5, -50.6)
	_cp_plat(cp, 0.0)
	r_jump(_edge(a, 0.75, cp), cp + D(Vector3(0, 0, 1.6)))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 8: the pinball shaft - bumper to bumper between kill panels --------------------------------------------

func _stage_8(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	kit.plat(W(0, 0, -7.6), _sz(Vector3(1.6, 0.6, 10.2)), "alt", 0.0)
	var rise: float = 3.4
	var zs: Array[float] = [-11.6, -2.74]
	var xs: Array[float] = [0.0, 1.0, -1.0, 1.0, 0.0]
	var contacts: Array[Vector3] = []
	for i: int in 5:
		var front: bool = i % 2 == 0
		var bz: float = zs[i % 2]
		var y: float = rise * i - (0.0 if i == 0 else 0.45)
		kit.bumper(W(xs[i], y, bz), 11.0, 15.0, 0.9)
		var back: float = -1.0 if front else 1.0
		if i > 0:
			kit.plat(W(xs[i], y, bz + back * 0.5), _sz(Vector3(2.4, 0.4, 2.8)), "accent", 0.0)
		kit.hazard(W(xs[i], y + 1.2, bz + back * 2.1), _sz(Vector3(5.0, 4.4, 0.5)))
		contacts.append(W(xs[i], rise * i, bz - back * 1.43))
	# cage bars either side
	for k: int in 6:
		for sx: int in [-1, 1]:
			kit.hazard(W(sx * 3.4, 2.0 + 3.2 * k, -7.2), _sz(Vector3(0.4, 0.4, 11.0)))
	var cp: Vector3 = W(0, rise * 4 + 2.4, -0.9)
	_cp_plat(cp, 90.0)
	kit.glow_strip(cp + D(Vector3(0, 0.03, -2.4)), _sz(Vector3(5, 0.06, 0.2)), Look.c("accent2"))
	r_walk(W(0, 0, -4.0))
	_step({"kind": "kick", "from": W(0, 0, -11.0), "to": contacts[1]})
	for i: int in range(1, 5):
		_step({"kind": "kick", "from": contacts[i], "to": contacts[i + 1] if i < 4 else cp + D(Vector3(0, 0, -0.8))})
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 9: the updraft chimney - ride the column, thread the kill rings ---------------------------------------------

## Square kill frame around an opening. `c` = opening centre (stage-local), in a column centred on `col`.
func _kill_ring(col: Vector3, c: Vector3, open_half: float, outer_half: float) -> void:
	var lo_x: float = col.x - outer_half
	var hi_x: float = col.x + outer_half
	var lo_z: float = col.z - outer_half
	var hi_z: float = col.z + outer_half
	var bars: Array = [
		[lo_x, c.x - open_half, lo_z, hi_z], [c.x + open_half, hi_x, lo_z, hi_z],
		[c.x - open_half, c.x + open_half, lo_z, c.z - open_half], [c.x - open_half, c.x + open_half, c.z + open_half, hi_z],
	]
	for b: Array in bars:
		var sx: float = float(b[1]) - float(b[0])
		var szz: float = float(b[3]) - float(b[2])
		if sx > 0.05 and szz > 0.05:
			kit.hazard(W((float(b[0]) + float(b[1])) * 0.5, c.y, (float(b[2]) + float(b[3])) * 0.5), _sz(Vector3(sx, 0.4, szz)))


func _stage_9(o: Vector3) -> Vector3:
	_frame(o, 90.0)
	var col := Vector3(0, 0, -8.5)
	kit.plat(W(0, 0, -3.6), _sz(Vector3(1.6, 0.5, 2.4)), "alt", 0.0)
	kit.wind(W(col.x, 10.5, col.z), Vector3(5, 29, 5), Vector3(0, 75, 0), 8.0)
	# the chimney mouth below and four corner rails so the column reads as a shaft
	kit.chimney(W(col.x, -16.0, col.z), 11.0, 2.6, false)
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			kit.glow_strip(W(col.x + sx * 2.7, 10.5, col.z + sz * 2.7), Vector3(0.12, 27, 0.12), Look.c("accent"))
	var opens: Array[Vector3] = [Vector3(1.0, 5.0, -8.5), Vector3(-0.9, 10.5, -7.8), Vector3(0.7, 16.0, -9.3), Vector3(0.0, 21.0, -9.5)]
	for c: Vector3 in opens:
		_kill_ring(col, c, 1.5, 3.3)
	r_walk(W(0, 0, -3.0))
	var prev: Vector3 = Vector3(opens[0].x, 0, opens[0].z)
	for c: Vector3 in opens:
		var gate_y: float = o.y + c.y + 0.6
		_step({"kind": "a_fly", "to": W(c.x, c.y, c.z), "until": func() -> bool: return player.global_position.y > gate_y})
		prev = c
	var cp: Vector3 = W(0, 23.0, -13.8)
	_cp_plat(cp, 0.0)
	_step({"kind": "a_fly", "to": cp + D(Vector3(0, 0, 0.8))})
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 10: the belt gauntlet - against the conveyor, under the hammers ------------------------------------------

## True when every hammer in `hams` stays clear of the centre line while we pass under it
## (we are under hammer i from leads[i] - half to leads[i] + half seconds from now).
func _hammers_clear(hams: Array, leads: Array, half: float = 0.45, margin: float = 0.3) -> bool:
	for i: int in hams.size():
		var h: Pendulum = hams[i]
		var dt: float = -half
		while dt <= half:
			if absf(h.angle_at(Game.course_time + float(leads[i]) + dt)) < margin:
				return false
			dt += 0.05
	return true


func _stage_10(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	kit.conveyor(W(0, 0, -16.0), _sz(Vector3(3, 0.4, 27)), _yaw + 180.0, 5.0)
	var hams: Array = []
	for i: int in 3:
		var hz: float = -7.0 - 9.0 * i
		hams.append(kit.pendulum(W(0, 8.2, hz), 7.0, 3.0, -0.173 * i, _yaw, 50.0))
		kit.arch(W(0, -1.0, hz), 8.0, 9.6, _yaw, Look.c("side").lightened(0.2))
	for bz: float in [-11.5, -20.5]:
		kit.hazard(W(0, 0.25, bz), _sz(Vector3(3, 0.5, 0.6)))
	r_walk(W(0, 0, -1.8))
	_wait(func() -> bool: return _hammers_clear(hams, [1.23, 3.25, 5.28]))
	r_walk(W(0, 0, -9.4))
	r_jump(W(0, 0, -9.7), W(0, 0, -14.0))
	r_walk(W(0, 0, -18.4))
	r_jump(W(0, 0, -18.7), W(0, 0, -23.0))
	var rest: Vector3 = W(0, 0, -31.0)
	kit.plat(rest, _sz(Vector3(3, 1, 3)), "alt")
	r_walk(rest)
	# belt 2: too fast to walk - bunny-hop it, kill bars set the rhythm, one last hammer at the exit
	kit.conveyor(W(0, 0, -40.0), _sz(Vector3(2.4, 0.4, 15)), _yaw + 180.0, 7.5)
	for bz: float in [-36.4, -42.4]:
		kit.hazard(W(0, 0.25, bz), _sz(Vector3(2.4, 0.5, 0.6)))
	var last: Pendulum = kit.pendulum(W(0, 8.2, -47.0), 7.0, 2.2, 0.0, _yaw, 50.0)
	kit.arch(W(0, -1.0, -47.0), 8.0, 9.6, _yaw, Look.c("side").lightened(0.2))
	_wait(func() -> bool: return _hammers_clear([last], [2.25], 0.35))
	r_jump(W(0, 0, -32.3), W(0, 0, -38.3))
	r_jump(W(0, 0, -38.8), W(0, 0, -44.4))
	var cp: Vector3 = W(0, 0, -50.2)
	_cp_plat(cp, -90.0)
	r_jump(W(0, 0, -44.6), cp + D(Vector3(0, 0, 0.6)))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 11: the hammer express - get hit on purpose, then the tail-wind beam ---------------------------------------

func _stage_11(o: Vector3) -> Vector3:
	_frame(o, -90.0)
	var a: Vector3 = _hop(W(0, 0, 0), 2.5, W(-3.5, 0.8, -6.4), 1.6)
	a = _hop(a, 0.8, W(-3.5, 1.6, -10.9), 1.6)
	var plate: Vector3 = W(0, 1.6, -13.8)
	kit.plat(plate, Vector3(1.8, 0.8, 1.8), "accent", 0.0)
	var ham: Pendulum = kit.pendulum(plate + Vector3(0, 1.25 + 9.0, 0), 9.0, 3.2, 0.0, _yaw + 90.0, 60.0)
	kit.arch(plate + D(Vector3(0, -12.0, 0)), 9.0, 23.0, _yaw + 90.0, Look.c("side").lightened(0.2))
	# step on right after the head has swept back over the plate; it returns 1.6 s later and hurls us forward
	_wait(func() -> bool:
		var t: float = Game.course_time + 0.75
		var w: float = ham.angle_at(t + 0.02) - ham.angle_at(t)
		var along: float = (ham.global_basis * Vector3.RIGHT).dot(D(Vector3.FORWARD))
		return w * along < 0.0 and ham.angle_at(t) * along < -0.3)
	r_jump(_edge(a, 0.8, plate), plate)
	var land: Vector3 = W(0, -0.9, -27.0)
	kit.plat(W(0, -0.9, -25.0), _sz(Vector3(3.4, 1, 12)), "main")
	kit.boost(W(0, -0.9, -35.0), Vector3(3.4, 0.4, 8), _yaw, 22.0)
	kit.glow_strip(W(0, -0.87, -38.8), _sz(Vector3(3.4, 0.06, 0.25)), Look.c("accent2"))
	_step({"kind": "kick", "from": plate, "to": land})
	# still carrying the hammer's speed: sprint the deck and leap
	var cp: Vector3 = W(0, 0.0, -60.0)
	kit.plat(W(0, 0.0, -57.4), _sz(Vector3(5, 1.4, 14)), "main")
	kit.checkpoint(cp, _yaw)
	kit.pillar(W(0, -1.4, -57.4), 1.0, 40.0)
	r_jump(W(0, -0.9, -38.4), W(0, 0.0, -55.0))
	_speed(22.0)
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 12: the victory lap - six momentum pieces, no ordinary ground, then the summit pad -----------------------

func _stage_12(o: Vector3) -> void:
	_frame(o, -90.0)
	kit.boost(W(0, 0, -10.4), Vector3(3, 0.4, 12), _yaw, 20.0)
	kit.glow_strip(W(0, 0.03, -16.2), _sz(Vector3(3, 0.06, 0.25)), Look.c("accent2"))
	var p1: Vector3 = W(0, 0, -31.0)
	kit.disc(p1, 2.2, 0.8, "accent")
	kit.pad(p1, 20.0, 0.0, 0.0, 1.5)
	kit.slick(W(0, 4.5, -51.0), Vector3(3.6, 0.4, 14), _yaw, 0.0)
	kit.glow_strip(W(0, 4.53, -57.8), _sz(Vector3(3.6, 0.06, 0.25)), Look.c("accent2"))
	kit.boost(W(0, 5.5, -75.0), Vector3(3, 0.4, 14), _yaw, 24.0)
	kit.glow_strip(W(0, 5.53, -81.8), _sz(Vector3(3, 0.06, 0.25)), Look.c("accent2"))
	var p2: Vector3 = W(0, 5.5, -100.0)
	kit.disc(p2, 3.0, 0.8, "accent")
	kit.pad(p2, 24.0, 0.0, 0.0, 1.6)
	var last: Vector3 = W(0, 12.5, -124.5)
	kit.disc(last, 3.2, 0.9, "accent")
	r_walk(W(0, 0, -5.0))
	r_jump(W(0, 0, -16.0), p1 + D(Vector3(0, 0, -0.8)))
	_speed(19.5)
	r_pad(p1, W(0, 4.5, -50.0))
	r_jump(W(0, 4.5, -57.6), W(0, 5.5, -71.5))
	_speed(18.0)
	r_jump(W(0, 5.5, -81.6), p2 + D(Vector3(0, 0, -1.2)))
	_speed(24.0)
	r_pad(p2, last)
	_summit(last, _yaw)


## The last angled pad and everything it throws you at: summit disc, finish gate, beacon.
## The disc is placed from the pad's real arc (Ballistics), so the landing is exact.
func _summit(pad_top: Vector3, yaw_deg: float) -> void:
	var pad: BouncePad = kit.pad(pad_top, 24.0, 35.0, yaw_deg, 2.0)
	var summit_y: float = pad_top.y + 5.0
	var land: Vector3 = Ballistics.landing_point(_tuning, pad.launch_origin(), pad.get_launch()["velocity"], summit_y)
	var dir: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3.FORWARD
	var summit := Vector3(land.x, summit_y, land.z) + dir * 5.0
	kit.disc(summit, 10.0, 1.2, "goal", 9.0)
	kit.finish(summit + dir * 1.5, yaw_deg)
	r_pad(pad_top, summit - dir * 5.0)
	r_walk(summit + dir * 1.5)
	_beacon_pos = summit + dir * 6.5
	_build_beacon(_beacon_pos)
	for i: int in 8:
		var a: float = float(i) / 8.0 * TAU
		kit.lamp(summit + Vector3(cos(a), 0, sin(a)) * 9.0, 2.2, false, Look.c("accent"))
	_summit_pos = summit


var _summit_pos: Vector3 = Vector3.ZERO


func _surroundings() -> void:
	kit.cloud_field(Vector3(0, -18, -120), Vector3(200, 6, 220), 26)
	kit.monolith_ring(Vector3(0, 30, -120), 190.0, 260.0, 22, 40.0)


func _stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = 500
	for i: int in 500:
		var d := Vector3(kit.rng.randf_range(-1, 1), kit.rng.randf_range(0.02, 1), kit.rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * kit.rng.randf_range(0.5, 1.5)), d * 700.0 + Vector3(0, -40, -75)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.92, 1.0)
	mat.disable_fog = true
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_beacon(pos: Vector3) -> void:
	var stone: StandardMaterial3D = Look.flat(Look.c("side").lightened(0.1), 0.7)
	var base := Look.cylinder(2.6, 1.2, stone, pos + Vector3(0, 0.6, 0), 2.0, 8)
	add_child(base)
	add_child(Look.cylinder(1.5, 5.0, stone, pos + Vector3(0, 3.7, 0), 0.9, 8))
	var crystal_mat := StandardMaterial3D.new()
	crystal_mat.albedo_color = Color(0.25, 0.3, 0.45)
	crystal_mat.emission_enabled = true
	crystal_mat.emission = Look.c("accent")
	crystal_mat.emission_energy_multiplier = 0.25
	crystal_mat.roughness = 0.2
	var cm := SphereMesh.new()
	cm.radius = 1.3
	cm.height = 4.2
	cm.radial_segments = 6
	cm.rings = 1
	_crystal = Look.mesh_node(cm, crystal_mat, pos + Vector3(0, 8.6, 0))
	_crystal.set_script(preload("res://visual/spin.gd"))
	_crystal.set("period", 9.0)
	add_child(_crystal)
	for i: int in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = 2.2 + i * 0.9
		tm.outer_radius = 2.38 + i * 0.9
		tm.rings = 48
		tm.ring_segments = 8
		var ring := Look.mesh_node(tm, crystal_mat, pos + Vector3(0, 8.6, 0))
		ring.rotation = Vector3(0.5 * i, 0, 0.35 * i)
		ring.set_script(preload("res://visual/spin.gd"))
		ring.set("period", 6.0 + i * 3.0)
		ring.set("axis", Vector3(0.3, 1, 0.2).normalized())
		add_child(ring)
		_rings.append(ring)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(0.5, 0.95, 1.0, 0.55)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.disable_fog = true
	_beam = Look.cylinder(1.6, 600.0, beam_mat, pos + Vector3(0, 309, 0), 5.0, 24)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.scale = Vector3(0.001, 1, 0.001)
	_beam.visible = false
	add_child(_beam)
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = Look.c("accent")
	_beacon_light.light_energy = 0.6
	_beacon_light.omni_range = 60.0
	_beacon_light.position = pos + Vector3(0, 9, 0)
	add_child(_beacon_light)
	for node: Node in find_children("*", "WorldEnvironment", true, false):
		_env = (node as WorldEnvironment).environment


## The ending: the crystal ignites, a beam splits the sky, the night warms up,
## and the camera pulls back to take it in.
func _finish_sequence() -> void:
	Sfx.play("beacon")
	var mat := _crystal.material_override as StandardMaterial3D
	_beam.visible = true
	if camera != null:
		camera.set_process(false)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(mat, "emission_energy_multiplier", 9.0, 1.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(_beacon_light, "light_energy", 14.0, 2.2)
	tw.tween_property(_beam, "scale", Vector3(1, 1, 1), 1.4).set_delay(1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i: int in _rings.size():
		tw.tween_property(_rings[i], "scale", Vector3.ONE * (1.6 + i * 0.5), 2.0).set_delay(1.0 + i * 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if _env != null:
		tw.tween_property(_env, "ambient_light_energy", _env.ambient_light_energy * 2.4, 3.0).set_delay(1.2)
		tw.tween_property(_env, "glow_intensity", 1.1, 2.0).set_delay(1.0)
	if camera != null and not headless_mode:
		var look_at_pos: Vector3 = _beacon_pos + Vector3(0, 12, 0)
		var start: Vector3 = camera.global_position
		var focus0: Vector3 = player.global_position + Vector3(0, 1.2, 0)
		var away: Vector3 = (start - _beacon_pos)
		away.y = 0.0
		var end_pos: Vector3 = _beacon_pos + away.normalized() * 34.0 + Vector3(0, 9, 0)
		tw.tween_method(func(k: float) -> void:
			camera.global_position = start.lerp(end_pos, k)
			camera.look_at(focus0.lerp(look_at_pos, minf(k * 1.8, 1.0))), 0.0, 1.0, 4.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	SaveData.set_game_completed()
	await get_tree().create_timer(5.2 if not headless_mode else 0.3).timeout
