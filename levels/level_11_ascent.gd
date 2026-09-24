extends LevelBase
## 11. THE FINAL ASCENT (the finale) - a night climb up a neon spire complex to the beacon. Hard mode:
## twenty-three stages, each behind a checkpoint, each pushing one earlier idea to its nastiest
## and then mixing in two or three more. The lower spire (1-12):
##   1 neon ladder + head-hitters + kill slalom      2 boost strip -> 15 m leap -> pad at sprint -> small disc
##   3 ice slide -> lip leap -> angled pad -> blink   4 lively narrow tilt beams, cross-wind, a hammer
##   5 ferry sling into a collapsing-stone curve      6 turntable with sweeper bars, arm-tip sling
##   7 neon ladder II (blinks, mover, kill walls)     8 the pinball shaft (bumper to bumper between kill panels)
##   9 the updraft chimney through kill rings         10 the belt gauntlet under sweeping hammers
##   11 the hammer express (get hit on purpose)        12 the victory lap -> the false summit
## The upper spire (13-23) brings the wall run, the mantle and the timed machines:
##   13 signal gap: wall run over the void, mantle, laser fences
##   14 FORK: piston alley (timing) | the scaffold (two mantles + blink), then the crusher bridge
##   15 the data stream: hop laser packets pouring down a belt, mantle out at the uplink
##   16 the chimney: three wall runs zig-zagging up, mantle out of the last kick, kill-ceiling taps
##   17 FORK: the press row (four crushers on a green wave + fence) | blink + guarded portal skip
##   18 FORK: hologram alley (three blinking billboard wall runs) | the gantry (blinks, fence, mantle)
##   19 the press stair: three mantles onto lips a crusher slams, then the ram beam
##   20 the uplink: a faster packet stream, a wall run over the drop, mantle out of the kick
##   21 the piston express: stand in front of two rams and let them throw you across the void
##   22 the billboard chimney: four blinking screens to wall-run up, mantle out of the kick
##   23 the beacon run: boost through a fence and under a press on one rhythm, mantle, summit pad
## Set pieces: the holographic billboards (AscentBillboard: wall-run panels that exist only while
## their ad plays), the data stream (AscentDataStream), and lighting the beacon.
## Shortcuts: A stage 1 side pad, B stage 4 wind-edge blocks, C stage 17 antenna caps,
## D stage 20 side warp ring, E stage 19 service pillar (max-height mantle).
## Particles (visual/ascent_fx.gd): neon motes + data rain along the climb, uplink spark fountains,
## press slam sparks, ram steam, portal arrival showers, checkpoint blooms, beacon embers + fireworks.

var _beam: MeshInstance3D
var _beacon_light: OmniLight3D
var _beacon_pos: Vector3
var _rings: Array[MeshInstance3D] = []
var _crystal: MeshInstance3D
var _env: Environment


func _configure() -> void:
	theme_id = "ascent"
	music_track = "ascent"
	kill_y = -30.0
	route_variants = 2


func _build() -> void:
	# themed air at three depths around the camera (visual only)
	add_child(Ambience.make(theme_id))
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
	cp = _stage_12(cp)
	cp = _stage_13(cp)
	cp = _stage_14(cp)
	cp = _stage_15(cp)
	cp = _stage_16(cp)
	cp = _stage_17(cp)
	cp = _stage_18(cp)
	cp = _stage_19(cp)
	cp = _stage_20(cp)
	cp = _stage_21(cp)
	cp = _stage_22(cp)
	_stage_23(cp)
	_surroundings()
	_ambience()


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
	kit.plat(b, Vector3(size, 0.8, size), style, 0.7)
	kit.glow_strip(b - Vector3(0, 0.86, 0), Vector3(size * 0.7, 0.08, size * 0.7), Look.c("accent2") if style == "alt" else Look.c("accent"))
	r_jump(_edge(a, a_half, b), b, hold)
	return b


## Solid body under a flat boost / ice / conveyor strip so it does not read as a floating sheet.
func _body(top: Vector3, size: Vector3, yaw_deg: float) -> void:
	kit.plat(top - Vector3(0, 0.42, 0), Vector3(size.x * 0.92, 0.5, size.z * 0.985), "main", 1.6, yaw_deg)


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
	# SHORTCUT A: a 1 m side disc (95% leap off the last head-hitter block) carries a strong angled
	# pad that fires you past three ladder blocks onto a 1.2 m catch disc (landing placed by Ballistics)
	var sc: Vector3 = W(-6.2, 3.4, -30.5)
	kit.disc(sc, 1.0, 0.6, "accent")
	var aim: Vector3 = W(-4.6, 13.0, -45.0) - sc
	var sc_pad: BouncePad = kit.pad(sc, 30.0, 38.0, rad_to_deg(atan2(-aim.x, -aim.z)), 0.9)
	var sc_land: Vector3 = Ballistics.landing_point(_tuning, sc_pad.launch_origin(), sc_pad.get_launch()["velocity"], 12.4)
	kit.disc(Vector3(sc_land.x, 12.4, sc_land.z), 1.2, 0.6, "accent")
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
	_body(W(0, 0, -8.5), Vector3(3, 0.4, 12), _yaw)
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
	_body(W(0, -drop, lip_z + 3.0), Vector3(3.5, 0.4, 6.0), _yaw)
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
	# SHORTCUT B: three 1 m blocks along the wind edge skip beam 2 and the hammer (94% jumps in a cross-wind)
	for sb: Vector3 in [W(3.8, 0.9, -22.0), W(3.8, 1.2, -28.5)]:
		kit.plat(sb, Vector3(1.0, 0.8, 1.0), "accent", 0.0)
	# beam 2: rolls under you, hammer across the middle, wind from the other side
	_tbeam(24.3, 0.6, 9.0, 0.9, true, false, 16.0)
	kit.wind(W(0, 2.2, -24.3), _sz(Vector3(7, 4, 10)), D(Vector3(-13, 0, 0)), 14.0)
	var ham: Pendulum = kit.pendulum(W(0, 0.6 + 8.1, -24.3), 7.0, 2.6, 0.0, _yaw, 50.0)
	kit.arch(W(0, -0.4, -24.3), 15.0, 9.0, _yaw, Look.c("side").lightened(0.2))  # posts outside the swing
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
	_cp_plat(cp, 0.0)  # face stage 7's first hop (its frame yaw is 0)
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
	_body(W(0, 0, -16.0), _sz(Vector3(3, 0.4, 27)), _yaw + 180.0)
	var hams: Array = []
	for i: int in 3:
		var hz: float = -7.0 - 9.0 * i
		hams.append(kit.pendulum(W(0, 8.2, hz), 7.0, 3.0, -0.173 * i, _yaw, 50.0))
		kit.arch(W(0, -1.0, hz), 15.0, 9.6, _yaw, Look.c("side").lightened(0.2))  # posts outside the swing
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
	_body(W(0, 0, -40.0), _sz(Vector3(2.4, 0.4, 15)), _yaw + 180.0)
	for bz: float in [-36.4, -42.4]:
		kit.hazard(W(0, 0.25, bz), _sz(Vector3(2.4, 0.5, 0.6)))
	var last: Pendulum = kit.pendulum(W(0, 8.2, -47.0), 7.0, 2.2, 0.0, _yaw, 50.0)
	kit.arch(W(0, -1.0, -47.0), 15.0, 9.6, _yaw, Look.c("side").lightened(0.2))
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
	# gantry straddles the lane, out of the swing and throw plane
	kit.arch(plate + D(Vector3(0, -12.0, 0)), 9.0, 23.0, _yaw, Look.c("side").lightened(0.2))
	# step on right after the head has swept back over the plate; it returns 1.6 s later and hurls us forward
	# (the stage heading is captured now: the frame helpers hold the LAST stage's frame by the time this runs)
	var fwd: Vector3 = D(Vector3.FORWARD)
	_wait(func() -> bool:
		var t: float = Game.course_time + 0.75
		var w: float = ham.angle_at(t + 0.02) - ham.angle_at(t)
		var along: float = (ham.global_basis * Vector3.RIGHT).dot(fwd)
		return w * along < 0.0 and ham.angle_at(t) * along < -0.3)
	r_jump(_edge(a, 0.8, plate), plate)
	var land: Vector3 = W(0, -0.9, -27.0)
	kit.plat(W(0, -0.9, -25.0), _sz(Vector3(3.4, 1, 12)), "main")
	kit.boost(W(0, -0.9, -35.0), Vector3(3.4, 0.4, 8), _yaw, 22.0)
	_body(W(0, -0.9, -35.0), Vector3(3.4, 0.4, 8), _yaw)
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

func _stage_12(o: Vector3) -> Vector3:
	_frame(o, -90.0)
	kit.boost(W(0, 0, -10.4), Vector3(3, 0.4, 12), _yaw, 20.0)
	_body(W(0, 0, -10.4), Vector3(3, 0.4, 12), _yaw)
	kit.glow_strip(W(0, 0.03, -16.2), _sz(Vector3(3, 0.06, 0.25)), Look.c("accent2"))
	var p1: Vector3 = W(0, 0, -31.0)
	kit.disc(p1, 2.2, 0.8, "accent")
	kit.pad(p1, 20.0, 0.0, 0.0, 1.5)
	kit.slick(W(0, 4.5, -51.0), Vector3(3.6, 0.4, 14), _yaw, 0.0)
	_body(W(0, 4.5, -51.0), Vector3(3.6, 0.4, 14), _yaw)
	kit.glow_strip(W(0, 4.53, -57.8), _sz(Vector3(3.6, 0.06, 0.25)), Look.c("accent2"))
	kit.boost(W(0, 5.5, -75.0), Vector3(3, 0.4, 14), _yaw, 24.0)
	_body(W(0, 5.5, -75.0), Vector3(3, 0.4, 14), _yaw)
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
	return _false_summit(last, _yaw)


## Stage 12's angled pad used to throw you onto the beacon summit; the spire now goes on,
## so it lands you on the false summit terrace (checkpoint 12) instead - same exact arc.
func _false_summit(pad_top: Vector3, yaw_deg: float) -> Vector3:
	var pad: BouncePad = kit.pad(pad_top, 24.0, 35.0, yaw_deg, 2.0)
	var y: float = pad_top.y + 5.0
	var land: Vector3 = Ballistics.landing_point(_tuning, pad.launch_origin(), pad.get_launch()["velocity"], y)
	land.y = y
	var dir: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3.FORWARD
	var side: Vector3 = dir.cross(Vector3.UP)
	kit.plat(land + dir * 4.0, _sz(Vector3(9.0, 1.6, 12.0)), "main", 3.0, 0.0)
	kit.pillar(land + dir * 4.0 - Vector3(0, 1.6, 0), 1.6, 60.0)
	var cp: Vector3 = land + dir * 7.5
	kit.checkpoint(cp, yaw_deg)
	for s: float in [-1.0, 1.0]:
		kit.lamp(land + dir * 1.0 + side * s * 4.0, 2.6, true, Look.c("accent"))
		kit.banner(land + dir * 9.6 + side * s * 4.1, 4.6, Look.c("accent2"), yaw_deg)
	# the dead antenna of the false summit: the real beacon burns far above
	var mast: StandardMaterial3D = Look.flat(Look.c("metal").darkened(0.35), 0.6, 0.5)
	add_child(Look.cylinder(0.35, 9.0, mast, land + dir * 4.0 - side * 3.4 + Vector3(0, 4.5, 0), 0.12, 8))
	r_pad(pad_top, land + dir * 0.8)
	r_walk(cp)
	r_checkpoint()
	return cp


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
var _fireworks: Array[AscentFx] = []


# ==== THE UPPER SPIRE (stages 13-23) ==================================================================

## Wall-run panel along the stage heading: `x` = its centre line (local), from z0 to z1 (local, z0 > z1).
func _wall(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> WallRunPanel:
	var w: WallRunPanel = kit.wallrun(W(x, y, (z0 + z1) * 0.5), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	# a pylon holds it up out of the dark
	kit.pillar(W(x, y - height * 0.5, (z0 + z1) * 0.5), 0.5, 40.0)
	kit.glow_strip(W(x, y - height * 0.5 - 0.1, (z0 + z1) * 0.5), _sz(Vector3(0.2, 0.1, absf(z0 - z1) - 0.4)), Look.c("accent"))
	return w


## Mantle wall/pillar: top centre in local coords, size (x, height, z).
func _ledge(top: Vector3, size: Vector3, style: String = "main") -> LedgeBlock:
	return kit.ledge(W(top.x, top.y, top.z), _sz(size), 0.0, style)


## A fence of stacked laser beams across the path at local z, all on one rhythm.
func _fence(x: float, y: float, z: float, width: float, heights: Array, period: float, on: float, phase: float) -> LaserGate:
	var first: LaserGate = null
	for h: float in heights:
		var g: LaserGate = kit.laser(W(x, y + h, z), Vector3(width, 0.22, 0.22), period, on, phase, _yaw)
		if first == null:
			first = g
	return first


## The beam stays dark for the whole window [now + a, now + b].
func _dark(g: LaserGate, a: float, b: float) -> bool:
	var t: float = Game.course_time + a
	while t <= Game.course_time + b:
		if g.is_on_at(t):
			return false
		t += 0.04
	return true


## Checkpoint plinth for the upper spire, at local `c`, facing `yaw_deg` (world).
func _cp_deck(c: Vector3, yaw_deg: float, size: Vector3 = Vector3(5, 1.4, 5)) -> Vector3:
	var p: Vector3 = W(c.x, c.y, c.z)
	kit.plat(p, _sz(size), "main")
	kit.checkpoint(p, yaw_deg)
	kit.pillar(p - Vector3(0, size.y, 0), 1.0, 50.0)
	return p


# ---- stage 13: signal gap - wall run over the void, mantle, laser fences ------------------------------

func _stage_13(o: Vector3) -> Vector3:
	_frame(o, -90.0)
	# the gap: nothing under it but the panel (runs z -5.5 .. -20.5 on the right)
	_wall(2.3, 1.2, -5.5, -20.5)
	var l1: Vector3 = W(-2.4, 0, -25.6)
	kit.plat(l1, _sz(Vector3(3.0, 0.8, 3.0)), "alt", 0.7)
	r_wallrun(W(0.5, 0, -2.1), W(1.7, 1.4, -6.6), W(1.7, 1.4, -18.2), l1 + D(Vector3(0, 0, 0.3)))
	# mantle wall: 3.4 m, too tall to jump
	_ledge(Vector3(-2.4, 3.4, -32.0), Vector3(3.0, 8.0, 3.0))
	r_mantle(W(-2.4, 0, -26.7), W(-2.4, 3.4, -31.4))
	# two laser fences across the next two gaps
	var f1: LaserGate = _fence(-2.4, 3.4, -36.2, 3.2, [0.5, 1.4, 2.3], 2.4, 0.45, 0.0)
	var b1: Vector3 = W(-2.4, 3.4, -39.7)
	kit.plat(b1, _sz(Vector3(2.2, 0.8, 2.2)), "alt", 0.7)
	var f2: LaserGate = _fence(-0.9, 4.4, -42.4, 4.4, [0.5, 1.4, 2.3], 2.4, 0.45, 0.5)
	var b2: Vector3 = W(0.6, 4.4, -45.3)
	kit.plat(b2, _sz(Vector3(1.8, 0.8, 1.8)), "alt", 0.7)
	r_until(func() -> bool: return _dark(f1, 0.1, 0.95))
	r_jump(W(-2.4, 3.4, -33.15), b1)
	r_until(func() -> bool: return _dark(f2, 0.0, 0.8))
	r_jump(_edge(b1, 1.1, b2), b2)
	var cp: Vector3 = _cp_deck(Vector3(0.6, 5.4, -52.0), 0.0)
	r_jump(_edge(b2, 0.9, cp), cp + D(Vector3(0, 0, 1.7)))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 14: the fork - piston alley (timing) or the scaffold (mantles), then the crusher bridge -------

## Piston in the stage frame: `top` local (retracted ram top centre), punching toward local +X (side = 1) or -X (-1).
func _ram(top: Vector3, side: float, face: float, stroke: float, period: float, phase: float, strength: float = 10.0) -> Piston:
	return kit.piston(W(top.x, top.y, top.z), Vector3(face, 1.6, 2.0), _yaw - 90.0 * side, stroke, period, phase, strength)


## Nothing of the ram is in the lane (no punch, not out) during [now + a, now + b].
func _ram_clear(p: Piston, a: float, b: float) -> bool:
	var t: float = Game.course_time + a
	while t <= Game.course_time + b:
		if p.is_punching_at(t) or p.extension_at(t) > 0.03:
			return false
		t += 0.04
	return true


func _stage_14(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	kit.plat(W(0, 0, -4.0), _sz(Vector3(12, 0.8, 3.0)), "main", 1.0)
	# signposts: red-lit alley on the left, gold-lit scaffold on the right
	kit.lamp(W(-5.4, 0, -3.2), 3.0, true, Color(1.0, 0.3, 0.25))
	kit.lamp(W(5.4, 0, -3.2), 3.0, true, LedgeBlock.LIP_COLOR)
	kit.glow_strip(W(-4.0, 0.03, -4.6), _sz(Vector3(1.0, 0.06, 1.6)), Color(1.0, 0.3, 0.25))
	kit.glow_strip(W(4.0, 0.03, -4.6), _sz(Vector3(1.6, 0.06, 1.6)), LedgeBlock.LIP_COLOR)
	# LEFT - piston alley: a 1 m beam, three rams punching across it from the dark
	kit.plat(W(-4.0, 0, -17.5), _sz(Vector3(1.0, 0.6, 24.0)), "alt", 0.0)
	var rams: Array[Piston] = []
	var zs: Array[float] = [-10.0, -16.5, -23.0]
	for i: int in 3:
		rams.append(_ram(Vector3(-5.8, 1.65, zs[i]), 1.0, 2.2, 2.6, 2.4, 0.18 * i))
	# RIGHT - the scaffold: two 3.2 m mantle walls, then a blinking step and the drop to the merge deck
	_ledge(Vector3(4.0, 3.2, -9.5), Vector3(3.0, 6.0, 3.0))
	_ledge(Vector3(4.0, 6.4, -16.0), Vector3(3.0, 9.2, 3.0))
	var bk: Vector3 = W(4.0, 6.4, -22.6)
	var blink: BlinkPlatform = kit.blink(bk, Vector3(1.8, 0.5, 1.8), 2.4, 0.55, 0.3)
	# the merge deck, then one crusher over the bridge to the checkpoint
	kit.plat(W(0, 0, -31.5), _sz(Vector3(12, 0.8, 5.0)), "main", 1.0)
	kit.plat(W(0, 0, -37.75), _sz(Vector3(2.4, 0.6, 7.5)), "alt", 0.0)
	var cr: Crusher = kit.crusher(W(0, 0, -37.8), Vector3(2.8, 1.6, 2.8), 3.2, 2.6, 0.0)
	_slam_fx(cr, W(0, 0, -37.8))
	if route_variant == 0:
		r_walk(W(-4.0, 0, -6.2))
		for i: int in 3:
			var p: Piston = rams[i]
			r_walk(W(-4.0, 0, zs[i] + 2.9))
			r_until(func() -> bool: return _ram_clear(p, 0.0, 0.75))
		r_walk(W(-4.0, 0, -29.6))
	else:
		r_walk(W(4.0, 0, -4.4))
		r_mantle(W(4.0, 0, -5.2), W(4.0, 3.2, -8.9))
		r_mantle(W(4.0, 3.2, -10.6), W(4.0, 6.4, -15.2))
		r_until(func() -> bool: return blink.is_on_at(Game.course_time + 0.7) and blink.is_on_at(Game.course_time + 1.6))
		r_jump(W(4.0, 6.4, -17.15), bk)
		r_jump(bk + D(Vector3(0, 0, -0.55)), W(1.5, 0, -30.8))
	r_walk(W(0, 0, -33.4))
	r_until(func() -> bool: return cr.is_clear_for(Game.course_time, 1.1))
	var cp: Vector3 = _cp_deck(Vector3(0, 0, -44.0), -90.0)
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 15: the data stream - hop the laser packets pouring down the belt, mantle out at the top ----------

func _stage_15(o: Vector3) -> Vector3:
	_frame(o, -90.0)
	var belt_c: Vector3 = W(0, 0, -17.5)
	kit.conveyor(belt_c, Vector3(4.4, 0.4, 30.0), _yaw + 180.0, 4.5)
	_body(belt_c, Vector3(4.4, 0.4, 30.0), _yaw + 180.0)
	for s: float in [-1.0, 1.0]:
		kit.glow_strip(W(s * 2.35, 0.05, -17.5), _sz(Vector3(0.12, 0.12, 30.0)), Look.c("accent2"))
	var stream := AscentDataStream.new()
	stream.length = 30.0
	stream.width = 4.4
	stream.rotation_degrees.y = _yaw
	stream.position = belt_c
	add_child(stream)
	# the uplink the packets pour out of, and the ledge you climb out onto
	kit.arch(W(0, 3.3, -32.9), 5.6, 3.6, _yaw, Look.c("accent2"))
	_uplink_fx(W(0, 3.3 + 3.6, -32.9))
	_ledge(Vector3(0, 3.3, -34.5), Vector3(4.4, 7.0, 4.0))
	_step({"kind": "ascent_stream", "to": W(0, 0, -30.9), "stream": stream})
	r_mantle(W(0, 0, -31.2), W(0, 3.3, -33.4))
	# one last fence before the checkpoint
	var f: LaserGate = _fence(0, 3.3, -38.7, 4.4, [0.5, 1.4, 2.3], 2.0, 0.5, 0.25)
	var cp: Vector3 = _cp_deck(Vector3(0, 3.8, -43.6), 0.0)
	r_until(func() -> bool: return _dark(f, 0.1, 0.75))
	r_jump(W(0, 3.3, -36.15), cp + D(Vector3(0, 0, 1.6)))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 16: the chimney - three wall runs zig-zagging up over the void, mantle out of the last kick ------

func _stage_16(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	_wall(2.3, 1.2, -5.5, -12.0)
	_wall(-2.3, 6.0, -10.5, -18.5)
	_wall(2.3, 9.0, -16.5, -24.5)
	# the ledge the last kick throws you at (top 3 m over the kick: only a mantle gets you up)
	_ledge(Vector3(-0.75, 11.9, -28.0), Vector3(4.5, 14.0, 4.0))
	r_wallrun(W(0.5, 0, -2.1), W(1.7, 1.4, -6.6), W(1.7, 1.4, -9.5), W(-1.7, 5.5, -13.4))
	r_wallrun(Vector3.ZERO, W(-1.7, 5.5, -13.4), W(-1.7, 5.5, -16.4), W(1.7, 8.5, -20.0), true, true)
	r_wallrun(Vector3.ZERO, W(1.7, 8.5, -20.0), W(1.7, 8.5, -21.4), W(-0.75, 11.9, -26.6), true, true)
	# tap-jump run under kill ceilings to the checkpoint
	var a: Vector3 = W(-0.75, 11.9, -28.0)
	var half: float = 2.0
	for i: int in 3:
		var b: Vector3 = W(-0.75 + [1.2, -1.0, 1.0][i], 11.9, -32.6 - 3.3 * i)
		kit.hazard((a + b) * 0.5 + Vector3(0, 2.95, 0), Vector3(3.0, 0.4, 3.0))
		a = _hop(a, half, b, 1.6, "alt", false)
		half = 0.8
	var cp: Vector3 = _cp_deck(Vector3(0, 11.9, -46.6), 0.0)
	r_jump(_edge(a, 0.8, cp), cp + D(Vector3(0, 0, 1.7)))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 17: press row - four crushers and two gaps, or the portal skip up the side ------------------

## The press stays harmless for the whole window [now + a, now + b].
func _press_clear(c: Crusher, a: float, b: float) -> bool:
	return c.is_clear_for(Game.course_time + a, b - a)


func _stage_17(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	# the row: three floor segments, four presses on a rolling rhythm
	kit.plat(W(0, 0, -6.25), _sz(Vector3(2.6, 0.8, 7.5)), "alt", 0.0)
	kit.plat(W(0, 0, -18.25), _sz(Vector3(2.6, 0.8, 9.5)), "alt", 0.0)
	kit.plat(W(0, 0, -30.25), _sz(Vector3(2.6, 0.8, 8.5)), "alt", 0.0)
	var presses: Array[Crusher] = []
	var pz: Array[float] = [-6.3, -15.4, -19.8, -28.6]
	# a "green wave": each press trails the one before it by the time a sprinter needs between them
	var ph: Array[float] = [0.0, 0.3, 0.133, 0.0]
	for i: int in 4:
		presses.append(kit.crusher(W(0, 0, pz[i]), Vector3(2.8, 1.8, 2.8), 3.2, 2.4, ph[i]))
		_slam_fx(presses[i], W(0, 0, pz[i]))
	var fence: LaserGate = _fence(0, 0, -33.3, 2.6, [0.4, 1.3], 2.4, 0.4, 0.4)
	# the merge deck (checkpoint), wide enough for the portal's exit ring
	kit.plat(W(3.0, 0, -38.0), _sz(Vector3(11.0, 1.2, 7.0)), "main", 2.0)
	kit.pillar(W(3.0, -1.2, -38.0), 1.4, 50.0)
	# the portal skip: three small blocks up the right side to an orange ring on a pillar
	var r1: Vector3 = W(5.5, 1.2, -7.0)
	var r2: Vector3 = W(6.0, 2.4, -12.8)
	var pp: Vector3 = W(6.0, 3.4, -18.3)
	kit.plat(r1, _sz(Vector3(1.3, 0.8, 1.3)), "accent", 0.7)
	var rb: BlinkPlatform = kit.blink(r2, Vector3(1.4, 0.5, 1.4), 2.4, 0.6, 0.2)
	kit.plat(pp, _sz(Vector3(2.4, 0.8, 2.4)), "accent", 0.7)
	kit.pillar(pp - Vector3(0, 0.8, 0), 0.7, 40.0)
	var portal: WarpPortal = kit.portal(W(6.0, 3.4, -18.9), _yaw, W(4.5, 0, -35.3), _yaw, 7.0)
	_arrive_fx(W(4.5, 0, -35.3), WarpPortal.EXIT_COLOR)
	# the ring's mouth is guarded: a two-beam fence right in front of it
	var guard: LaserGate = _fence(6.0, 3.4, -18.25, 2.4, [0.5, 1.4], 2.0, 0.5, 0.3)
	kit.glow_strip(r1 + Vector3(0, 0.03, 0), Vector3(0.5, 0.06, 0.5), WarpPortal.ENTRY_COLOR)
	# SHORTCUT C: two 1 m antenna caps off the left of the row - 85-90% leaps that skip presses 2 and 3
	for c: Vector3 in [W(-3.4, 0.5, -15.2), W(-3.4, 0.5, -22.2)]:
		kit.plat(c, Vector3(1.0, 0.8, 1.0), "accent", 0.5)
		kit.glow_strip(c + Vector3(0, 0.03, 0), Vector3(0.4, 0.06, 0.4), Look.c("accent2"))
	if route_variant == 0:
		r_walk(W(0, 0, -3.2))
		r_until(func() -> bool: return _press_clear(presses[0], 0.0, 1.0))
		r_walk(W(0, 0, -9.3))
		r_until(func() -> bool: return _press_clear(presses[1], 0.25, 1.1) and _press_clear(presses[2], 0.6, 1.6))
		r_jump(W(0, 0, -9.65), W(0, 0, -14.6))
		r_walk(W(0, 0, -22.6))
		r_until(func() -> bool: return _press_clear(presses[3], 0.3, 1.2) and _dark(fence, 0.6, 1.6))
		r_jump(W(0, 0, -22.65), W(0, 0, -27.4))
		r_walk(W(0, 0, -32.0))
		r_walk(W(0, 0, -35.8))
	else:
		r_jump(W(2.0, 0, -2.2), r1)
		r_until(func() -> bool: return rb.is_on_at(Game.course_time + 0.5) and rb.is_on_at(Game.course_time + 1.3))
		r_jump(_edge(r1, 0.65, r2), r2)
		r_jump(_edge(r2, 0.7, pp), pp + D(Vector3(0, 0, 0.7)))
		r_until(func() -> bool: return _dark(guard, 0.0, 0.6))
		r_portal(W(6.0, 3.4, -18.9), portal.exit_point())
	var cp: Vector3 = W(1.5, 0, -38.8)
	kit.checkpoint(cp, 0.0)
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 18: hologram alley - ride the billboards while their ads play, or climb the gantry ------------

## Holographic billboard (AscentBillboard, a wall-run panel that blinks out) along the stage heading.
func _billboard(x: float, y: float, z0: float, z1: float, period: float, on: float, phase: float, height: float = 7.0) -> AscentBillboard:
	var b := AscentBillboard.new()
	b.size = Vector3(absf(z0 - z1), height, 0.5)
	b.period = period
	b.on_fraction = on
	b.phase = phase
	b.rotation_degrees.y = _yaw + 90.0
	b.position = W(x, y, (z0 + z1) * 0.5)
	add_child(b)
	kit.pillar(W(x, y - height * 0.5 - 0.4, (z0 + z1) * 0.5), 0.45, 40.0)
	return b


func _stage_18(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	# the fork, readable from the checkpoint: magenta billboards on the left, the gold gantry on the right
	kit.lamp(W(-4.0, 0, -1.6), 3.0, true, AscentBillboard.AD_COLORS[0])
	kit.lamp(W(6.6, 0, -1.6), 3.0, true, LedgeBlock.LIP_COLOR)
	kit.glow_strip(W(-2.0, 0.03, -2.2), Vector3(1.8, 0.06, 0.5), AscentBillboard.AD_COLORS[0])
	kit.glow_strip(W(5.0, 0.03, -2.2), Vector3(1.8, 0.06, 0.5), LedgeBlock.LIP_COLOR)
	# LEFT: three billboards zig-zag up the void; the ad rolls down the alley one screen per second
	var xl: float = -2.0
	var bb: Array[AscentBillboard] = [
		_billboard(xl + 2.3, 1.2, -5.5, -12.0, 3.0, 0.7, 0.0),
		_billboard(xl - 2.3, 6.0, -10.5, -18.5, 3.0, 0.7, -1.0 / 3.0),
		_billboard(xl + 2.3, 9.0, -16.5, -24.5, 3.0, 0.7, -2.0 / 3.0),
	]
	_glitter(W(xl, 6.0, -15.0))
	# RIGHT: the gantry - blinking steps and a laser fence, slower but on solid-ish ground
	var g1: Vector3 = W(5.0, 1.4, -6.9)
	kit.plat(g1, Vector3(1.8, 0.8, 1.8), "alt", 0.7)
	var g2: Vector3 = W(5.8, 3.0, -11.0)
	var k2: BlinkPlatform = kit.blink(g2, Vector3(1.9, 0.5, 1.9), 2.4, 0.6, 0.0)
	var gf: LaserGate = _fence(5.3, 3.0, -13.3, 3.0, [0.6, 1.5, 2.4], 2.4, 0.45, 0.45)
	var g3: Vector3 = W(4.8, 4.6, -15.4)
	kit.plat(g3, Vector3(1.8, 0.8, 1.8), "alt", 0.7)
	var g4: Vector3 = W(5.6, 6.2, -19.4)
	var k4: BlinkPlatform = kit.blink(g4, Vector3(1.9, 0.5, 1.9), 2.4, 0.6, 0.5)
	var g5: Vector3 = W(4.5, 7.9, -23.6)
	kit.plat(g5, _sz(Vector3(3.4, 0.8, 4.8)), "main", 1.0)
	# both routes meet on the relay tower: 3.4 m over the gantry's last deck, so it takes a mantle
	_ledge(Vector3(0.5, 11.3, -30.5), Vector3(12.0, 16.0, 9.0))
	for s: float in [-1.0, 1.0]:
		kit.banner(W(0.5 + s * 5.2, 11.3, -34.2), 4.4, AscentBillboard.AD_COLORS[0] if s < 0.0 else LedgeBlock.LIP_COLOR, _yaw)
	if route_variant == 0:
		r_walk(W(xl + 0.5, 0, -0.4))
		r_until(func() -> bool:
			var t: float = Game.course_time
			return bb[0].solid_through(t, 0.0, 1.4) and bb[1].solid_through(t, 0.9, 2.4) and bb[2].solid_through(t, 1.8, 3.4))
		r_wallrun(W(xl + 0.5, 0, -2.1), W(xl + 1.7, 1.4, -6.6), W(xl + 1.7, 1.4, -9.5), W(xl - 1.7, 5.5, -13.4))
		r_wallrun(Vector3.ZERO, W(xl - 1.7, 5.5, -13.4), W(xl - 1.7, 5.5, -16.4), W(xl + 1.7, 8.5, -20.0), true, true)
		r_wallrun(Vector3.ZERO, W(xl + 1.7, 8.5, -20.0), W(xl + 1.7, 8.5, -21.4), W(xl - 0.75, 11.3, -26.6), true, true)
	else:
		r_jump(W(5.0, 0, -2.35), g1)
		r_until(func() -> bool:
			return k2.is_on_at(Game.course_time + 0.45) and k2.is_on_at(Game.course_time + 1.2) and _dark(gf, 0.8, 1.5))
		r_jump(_edge(g1, 0.9, g2), g2)
		r_jump(_edge(g2, 0.95, g3), g3)
		r_until(func() -> bool: return k4.is_on_at(Game.course_time + 0.45) and k4.is_on_at(Game.course_time + 1.3))
		r_jump(_edge(g3, 0.9, g4), g4)
		r_jump(_edge(g4, 0.95, g5), g5 + D(Vector3(0, 0, 1.2)))
		r_mantle(W(4.5, 7.9, -25.2), W(4.5, 11.3, -27.6))
	var cp: Vector3 = W(0.5, 11.3, -31.5)
	kit.checkpoint(cp, 0.0)
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 19: the press stair - three mantles, each onto a lip a crusher slams --------------------------

func _stage_19(o: Vector3) -> Vector3:
	_frame(o, 0.0)
	# the relay tower's far edge is at local z -3.5
	var presses: Array[Crusher] = []
	for i: int in 3:
		var top: float = 3.2 * float(i + 1)
		var zc: float = -8.5 - 6.0 * float(i)
		_ledge(Vector3(0, top, zc), Vector3(4.4, 9.0 + 3.2 * float(i), 6.0))
		presses.append(kit.crusher(W(0, top, zc + 1.3), Vector3(3.0, 1.6, 2.8), 3.0, 2.6, 0.35 * float(i)))
		_slam_fx(presses[i], W(0, top, zc + 1.3))
	# SHORTCUT E: a 1.4 m service pillar beside the first step - a near max-height running mantle onto it,
	# then a rising leap onto the corner of step 2 beside its press: skips the first mantle and press
	_ledge(Vector3(3.6, 4.1, -7.2), Vector3(1.4, 10.0, 1.4), "alt")
	# the ram beam: a 1 m catwalk over the void, rams punching across it from both sides
	kit.plat(W(0, 9.6, -29.7), _sz(Vector3(1.0, 0.6, 12.4)), "alt", 0.0)
	var rams: Array[Piston] = [
		_ram(Vector3(-1.8, 9.6 + 1.65, -27.0), 1.0, 2.2, 2.6, 2.0, 0.0),
		_ram(Vector3(1.8, 9.6 + 1.65, -32.0), -1.0, 2.2, 2.6, 2.0, 0.35),
	]
	_punch_fx(rams[0], W(0, 9.6 + 0.8, -27.0), D(Vector3.RIGHT))
	_punch_fx(rams[1], W(0, 9.6 + 0.8, -32.0), D(Vector3.LEFT))
	r_walk(W(0, 0, -2.6))
	r_until(func() -> bool: return _press_clear(presses[0], 0.0, 1.8))
	r_mantle(W(0, 0, -3.2), W(0, 3.2, -6.4))
	r_walk(W(0, 3.2, -9.5))
	r_until(func() -> bool: return _press_clear(presses[1], 0.0, 1.8))
	r_mantle(W(0, 3.2, -10.1), W(0, 6.4, -12.4))
	r_walk(W(0, 6.4, -15.5))
	r_until(func() -> bool: return _press_clear(presses[2], 0.0, 1.8))
	r_mantle(W(0, 6.4, -16.1), W(0, 9.6, -18.4))
	r_walk(W(0, 9.6, -24.2))
	r_until(func() -> bool: return _ram_clear(rams[0], 0.0, 0.75))
	r_walk(W(0, 9.6, -29.5))
	r_until(func() -> bool: return _ram_clear(rams[1], 0.0, 0.75))
	var cp: Vector3 = _cp_deck(Vector3(0, 9.6, -38.4), -90.0)
	r_walk(W(0, 9.6, -35.4))
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 20: the uplink - hop the packet stream up the belt, wall-run the void, mantle out of the kick ----

func _stage_20(o: Vector3) -> Vector3:
	_frame(o, -90.0)
	var belt_c: Vector3 = W(0, 0, -19.5)
	kit.conveyor(belt_c, Vector3(4.4, 0.4, 34.0), _yaw + 180.0, 5.0)
	_body(belt_c, Vector3(4.4, 0.4, 34.0), _yaw + 180.0)
	for s: float in [-1.0, 1.0]:
		kit.glow_strip(W(s * 2.35, 0.05, -19.5), _sz(Vector3(0.12, 0.12, 34.0)), Look.c("accent2"))
	var stream := AscentDataStream.new()
	stream.length = 34.0
	stream.width = 4.4
	stream.speed = 6.5
	stream.spacing = 6.8
	stream.pattern = PackedStringArray(["full", "left", "right", "full", "right"])
	stream.rotation_degrees.y = _yaw
	stream.position = belt_c
	add_child(stream)
	kit.arch(W(0, 0, -36.4), 5.6, 3.6, _yaw, Look.c("accent2"))
	_uplink_fx(W(0, 3.6, -36.4))
	# the dish deck at the top of the belt, then nothing but a wall-run panel over the drop
	kit.plat(W(0, 0, -39.0), _sz(Vector3(4.4, 0.8, 5.0)), "main", 1.0)
	_wall(2.3, 1.2, -44.5, -54.5)
	_ledge(Vector3(-0.75, 3.8, -59.6), Vector3(4.5, 13.8, 7.0))
	# SHORTCUT D: a 1 m block off the belt's start and a hidden warp ring on a second one - it drops you
	# onto the belt half way up (into the packets), for two 85-90% leaps onto tiny tops
	var s1: Vector3 = W(4.7, 0.8, -7.2)
	var s2: Vector3 = W(4.7, 1.2, -13.4)
	kit.plat(s1, Vector3(1.0, 0.8, 1.0), "accent", 0.5)
	kit.plat(s2, Vector3(1.2, 0.8, 1.2), "accent", 0.5)
	kit.portal(s2, _yaw, W(0, 0, -21.0), _yaw, 7.0)
	_arrive_fx(W(0, 0, -21.0), WarpPortal.EXIT_COLOR)
	_step({"kind": "ascent_stream", "to": W(0, 0, -36.9), "stream": stream})
	r_wallrun(W(0.5, 0, -41.1), W(1.7, 1.4, -45.6), W(1.7, 1.4, -51.5), W(-0.75, 3.8, -56.7))
	var cp: Vector3 = W(-0.75, 3.8, -60.5)
	kit.checkpoint(cp, -90.0)
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 21: the piston express - stand in front of the rams and let them throw you, twice ------------

func _flat_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


## Bot: hold still on the plate until the ram throws us, then fly (steering only toward) the landing.
func _throw(plate: Vector3, land: Vector3) -> void:
	_step({"kind": "a_fly", "to": plate, "until": func() -> bool: return not player.grounded and _flat_speed() > 10.0})
	_step({"kind": "a_fly", "to": land, "damp": 0.0})


func _stage_21(o: Vector3) -> Vector3:
	_frame(o, -90.0)
	# the ledge top's far edge is at local z -2.6
	var p1: Vector3 = W(0, 0.6, -6.2)
	kit.plat(p1, Vector3(1.8, 0.8, 1.8), "accent", 0.7)
	var ram1: Piston = _ram(Vector3(-1.9, 0.6 + 1.6, -6.2), 1.0, 1.8, 2.0, 3.0, 0.0, 9.0)
	# the gap to the plate is fenced, on the ram's rhythm: dark exactly while the ram is home
	var f1: LaserGate = _fence(0, 0, -3.95, 2.4, [0.5, 1.4, 2.3], 3.0, 0.5, 0.55)
	var l1: Vector3 = W(9.0, -1.0, -6.2)
	kit.plat(l1, _sz(Vector3(6.0, 1.0, 4.5)), "main", 1.2)
	var p2: Vector3 = W(14.4, -0.4, -6.2)
	kit.plat(p2, Vector3(1.8, 0.8, 1.8), "accent", 0.7)
	var ram2: Piston = kit.piston(W(14.4, -0.4 + 1.6, -6.2 + 1.9), Vector3(1.8, 1.6, 2.0), _yaw, 2.0, 3.0, 0.5, 9.0)
	_punch_fx(ram1, p1 + Vector3(0, 0.8, 0), D(Vector3.RIGHT))
	_punch_fx(ram2, p2 + Vector3(0, 0.8, 0), D(Vector3.FORWARD))
	var l2: Vector3 = W(14.4, -2.0, -15.5)
	kit.plat(l2, _sz(Vector3(4.5, 1.0, 6.0)), "main", 1.2)
	_ledge(Vector3(14.4, 1.4, -22.75), Vector3(5.0, 12.0, 8.5))
	r_walk(W(0, 0, -1.6))
	r_until(func() -> bool: return _ram_clear(ram1, 0.2, 1.1) and _dark(f1, 0.0, 0.6))
	r_jump(W(0, 0, -2.25), p1)
	_throw(p1, l1)
	r_until(func() -> bool: return _flat_speed() < 0.5 and _ram_clear(ram2, 0.15, 1.45))
	r_jump(_edge(l1, 3.0, p2), p2)
	_throw(p2, l2)
	r_until(func() -> bool: return _flat_speed() < 0.5)
	r_mantle(W(14.4, -2.0, -17.4), W(14.4, 1.4, -19.9))
	var cp: Vector3 = W(14.4, 1.4, -24.5)
	kit.checkpoint(cp, -90.0)
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 22: the billboard chimney - four blinking screens zig-zag up, mantle out of the last kick --------

func _stage_22(o: Vector3) -> Vector3:
	_frame(o, -90.0)
	# the ledge top's far edge is at local z -2.5
	var per: float = 3.2
	# each screen lights up when a runner who left on the first one's cue reaches it (the chain's real cadence)
	var at: Array[float] = [0.0, 1.1, 1.75, 2.35]
	var bb: Array[AscentBillboard] = [
		_billboard(2.3, 1.2, -5.5, -12.0, per, 0.72, 0.0),
		_billboard(-2.3, 6.0, -10.5, -18.5, per, 0.72, -at[1] / per),
		_billboard(2.3, 9.0, -16.5, -24.5, per, 0.72, -at[2] / per),
		_billboard(-2.3, 12.0, -22.5, -30.5, per, 0.72, -at[3] / per),
	]
	_ledge(Vector3(1.5, 13.9, -33.5), Vector3(6.0, 17.0, 5.0))
	_glitter(W(0, 8.0, -18.0))
	r_walk(W(0.5, 0, -0.4))
	r_until(func() -> bool:
		var t: float = Game.course_time
		for i: int in 4:
			if not bb[i].solid_through(t, at[i], at[i] + 1.5):
				return false
		return true)
	r_wallrun(W(0.5, 0, -2.1), W(1.7, 1.4, -6.6), W(1.7, 1.4, -9.5), W(-1.7, 5.5, -13.4))
	r_wallrun(Vector3.ZERO, W(-1.7, 5.5, -13.4), W(-1.7, 5.5, -16.4), W(1.7, 8.5, -20.0), true, true)
	r_wallrun(Vector3.ZERO, W(1.7, 8.5, -20.0), W(1.7, 8.5, -21.4), W(-1.7, 11.5, -25.0), true, true)
	r_wallrun(Vector3.ZERO, W(-1.7, 11.5, -25.0), W(-1.7, 11.5, -26.4), W(0.75, 13.9, -31.6), true, true)
	var cp: Vector3 = W(1.5, 13.9, -33.5)
	kit.checkpoint(cp, 180.0)
	r_walk(cp)
	r_checkpoint()
	return cp


# ---- stage 23: the beacon run - boost through the fence, under the press, mantle, and the summit pad ------

func _stage_23(o: Vector3) -> void:
	_frame(o, 180.0)
	# the ledge top's far edge is at local z -3.0
	kit.boost(W(0, 0, -8.0), Vector3(3.0, 0.4, 10.0), _yaw, 20.0)
	_body(W(0, 0, -8.0), Vector3(3.0, 0.4, 10.0), _yaw)
	kit.glow_strip(W(0, 0.03, -12.8), _sz(Vector3(3.0, 0.06, 0.25)), Look.c("accent2"))
	var fence: LaserGate = _fence(0, 0, -19.3, 4.0, [0.8, 1.7, 2.6], 2.4, 0.4, 0.0)
	kit.plat(W(0, 0, -30.0), _sz(Vector3(4.4, 1.0, 9.0)), "main", 1.2)
	# the press runs on the fence's rhythm: leave the strip as the beams die and it is up as you land
	var press: Crusher = kit.crusher(W(0, 0, -30.5), Vector3(3.4, 1.6, 2.8), 3.0, 2.4, 0.12)
	_slam_fx(press, W(0, 0, -30.5))
	_ledge(Vector3(0, 3.6, -38.5), Vector3(4.4, 12.0, 8.0))
	r_walk(W(0, 0, -1.0))
	r_until(func() -> bool: return _dark(fence, 0.7, 1.6) and _press_clear(press, 1.5, 2.4))
	r_jump(W(0, 0, -12.7), W(0, 0, -27.0))
	_speed(20.0)
	r_mantle(W(0, 0, -32.8), W(0, 3.6, -36.2))
	_summit(W(0, 3.6, -39.0), _yaw)


# ==== particles ============================================================================================

## Sparks and a dust ring every time a press hits its floor.
func _slam_fx(c: Crusher, floor_top: Vector3) -> void:
	var fx := AscentFx.burst(floor_top + Vector3(0, 0.15, 0), Color(1.0, 0.62, 0.3), func() -> bool: return c.gap_at(Game.course_time) < 0.05, 40, 7.0)
	AscentFx.add_puff(fx, Look.c("cloud_light"), 12, Vector3.UP, 2.0)
	add_child(fx)


## Steam and sparks out of the ram as it punches (`at` = in front of its face, `dir` = the punch direction).
func _punch_fx(p: Piston, at: Vector3, dir: Vector3) -> void:
	var fx := AscentFx.burst(at, Color(0.55, 0.95, 1.0), func() -> bool: return p.is_punching_at(Game.course_time), 30, 8.0, dir + Vector3(0, 0.25, 0), 0.5)
	AscentFx.add_puff(fx, Color(0.8, 0.9, 1.0), 10, dir, 3.0)
	add_child(fx)


## A blue shower where a warp ring drops you off.
func _arrive_fx(at: Vector3, col: Color) -> void:
	add_child(AscentFx.burst(at + Vector3(0, 1.2, 0), col, func() -> bool:
		return player != null and player.global_position.distance_to(at + Vector3(0, 0.5, 0)) < 1.8, 50, 6.0, Vector3.ZERO, 0.9, 0.16))


## Packet uplinks: a magenta spark fountain over the arch the data pours out of.
func _uplink_fx(top: Vector3) -> void:
	add_child(AscentFx.fountain(top + Vector3(0, 0.3, 0), AscentBillboard.AD_COLORS[0], 36, 5.0, 1.2))


## Ambient layers along the whole climb: neon motes round every checkpoint (alternating cyan and
## magenta), big pale glints higher up, data-rain curtains beside the route, a bloom of confetti the
## first time you reach each upper-spire checkpoint, and the hologram alleys' glitter.
func _ambience() -> void:
	var cps: Array[Node] = find_children("*", "Checkpoint", true, false)
	var pts: Array[Vector3] = [_spawn.origin]
	var sides: Array[Vector3] = [Vector3.RIGHT]
	for n: Node in cps:
		var c := n as Node3D
		pts.append(c.global_position)
		sides.append(c.global_basis.x.normalized())
	for i: int in pts.size():
		var col: Color = Look.c("accent") if i % 2 == 0 else Look.c("accent2")
		add_child(AscentFx.motes(pts[i] + Vector3(0, 5.0, 0), Vector3(16, 7, 16), col, 36))
		if i % 3 == 0:
			add_child(AscentFx.motes(pts[i] + Vector3(0, 16.0, 0), Vector3(30, 8, 30), Color(0.75, 0.82, 1.0), 20, 0.45))
		# data rain: curtains well off to both sides (every checkpoint up the spire, every third one below)
		if i >= 12 or i % 3 == 1:
			for s: float in [-1.0, 1.0]:
				var r: GPUParticles3D = AscentFx.rain(pts[i] + sides[i] * s * 13.0 - Vector3(0, 6, 0), Vector3(2.0, 10.0, 12.0), Look.c("accent"), 44)
				r.rotation.y = (cps[i - 1] as Node3D).global_rotation.y if i > 0 else 0.0
				add_child(r)
	for k: int in range(12, cps.size()):
		var at: Vector3 = (cps[k] as Node3D).global_position
		var idx: int = k + 1
		add_child(AscentFx.burst(at + Vector3(0, 0.6, 0), Look.c("accent") if k % 2 == 0 else Look.c("accent2"), func() -> bool:
			return current_checkpoint >= idx, 44, 7.0, Vector3.UP, 1.2, 0.18))


## Hologram-alley glitter: magenta pixel dust hanging between the billboards (stage frame).
func _glitter(at: Vector3) -> void:
	var m: GPUParticles3D = AscentFx.motes(at, Vector3(4.5, 6.0, 10.0), AscentBillboard.AD_COLORS[0], 40, 0.12)
	m.rotation.y = deg_to_rad(_yaw)
	add_child(m)


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
	# embers rising round the dark crystal, and the fireworks the finish sets off
	add_child(AscentFx.fountain(pos + Vector3(0, 1.3, 0), Look.c("accent"), 40, 4.0, 2.2))
	add_child(AscentFx.motes(pos + Vector3(0, 9.0, 0), Vector3(5, 5, 5), Look.c("accent2"), 30, 0.2))
	for i: int in 6:
		var a: float = float(i) / 6.0 * TAU
		var col: Color = [Look.c("accent"), Look.c("accent2"), LedgeBlock.LIP_COLOR][i % 3]
		var fw: AscentFx = AscentFx.burst(pos + Vector3(cos(a) * 9.0, 14.0 + 3.0 * float(i % 2), sin(a) * 9.0), col, Callable(), 90, 11.0, Vector3.ZERO, 1.6, 0.3)
		add_child(fw)
		_fireworks.append(fw)
	add_child(_beacon_light)
	for node: Node in find_children("*", "WorldEnvironment", true, false):
		_env = (node as WorldEnvironment).environment


## The ending: the crystal ignites, a beam splits the sky, the night warms up,
## and the camera pulls back to take it in.
func _finish_sequence() -> void:
	# fanfare_ascent is scored to the beacon lighting; the old riser only without it
	if not Sfx.has_clip("fanfare_ascent"):
		Sfx.play("beacon")
	for i: int in _fireworks.size():
		get_tree().create_timer(1.3 + 0.28 * float(i)).timeout.connect(_fireworks[i].fire)
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
