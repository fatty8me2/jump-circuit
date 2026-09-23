extends LevelBase
## 1. LAUNCH GARDENS - sunny terrace gardens in the sky, and the first level of a hard obby.
## Eighteen stages, each ending on a checkpoint lawn. One new idea per stage, then combined:
##   1 Garden Gate      warm-up hops (already 70-80 % jumps)
##   2 Stepping Stones  small-block parkour: rising, diagonal, a narrow beam, a 2 m ladder step
##   3 Spring Beds      bounce pads - vertical pads keep your run speed, so SPRINT onto them
##   4 Runway Lawns     boost strips into 10 m and 12.5 m leaps
##   5 Hedge Trimmers   kill bricks: hop them, tap-jump under a red ceiling, zig-zag past hedges
##   6 The Mower        a sweeper you must hop while circling against its spin
##   7 Frost Chute      an ice slide that fires you across a ravine
##   8 The Great Leap   a 2 m-per-rung ladder up to the ring-gate launch pad (set piece), hard exit
##   9 Grand Circuit    hop + boost -> leap -> pad -> pad -> small landing -> the old finish plaza
## The extension (the gardens climb on round a loop to the summit):
##  10 Topiary Runs     the first wall run (a 19 m gap only the panel crosses), the first mantle, hedge hops
##  11 The Greenhouse   BRANCH: a planter walkway swept by three sprinkler pistons, or mantle up to the rafters
##  12 The Hedge Maze   SET PIECE - THE TRIMMER, a laser curtain sweeping a hedge alley (hide in the side
##                      pockets), then two laser gates and a mantle; BRANCH: mantle onto the hedge tops instead
##  13 The Windmill     ride a seed tray on the sails up and leap off the top; shortcut: the vine ladder
##  14 Flower Beds      BRANCH: a sprint-bounce chain over three flower pads, or a zig-zag of two trellis wall runs
##  15 The Potting Press run a line of slamming presses, mantle up under a press, ride a press up like a lift;
##                      shortcut: three 1 m pot tiles past the press line
##  16 Topiary Chimney  three alternating wall runs climbing a chimney, the last kick ends in a mantle
##  17 The Orchard      BRANCH: boost leap + a laser bridge, or an 87 % hop to the warp ring on the apple terrace
##  18 Summit Garden    hop + boost leap, a wall run over the void, a bounce-pad mantle up the summit wall,
##                      a piston and a laser, finish (fireworks)
## The course is built stage by stage in a local frame (heading = local -Z) so it can turn.
## Route variants: 0 = main lines; 1 = every alternative branch (rafters, hedge tops, trellis, portal).

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _mower: Sweeper
var _fan: Sweeper

const HEDGE: Color = Color(0.2, 0.48, 0.26)
const MILL_R: float = 6.0
const MILL_PERIOD: float = 8.0


func _configure() -> void:
	theme_id = "gardens"
	music_track = "a"
	kill_y = -40.0
	route_variants = 2


# ---- local-frame helpers --------------------------------------------------------------------

func _frame(origin: Vector3, yaw_deg: float) -> void:
	_o = origin
	_yaw = yaw_deg
	_b = Basis(Vector3.UP, deg_to_rad(yaw_deg))


func _w(l: Vector3) -> Vector3:
	return _o + _b * l


func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, -1.0, _yaw)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.8) -> Dictionary:
	kit.disc(_w(c), r, thick, style)
	return {"c": c, "r": r}


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## Takeoff spot on `a`: on the line toward `toward`, `inset` metres inside the edge.
func _edge(a: Dictionary, toward: Vector3, inset: float = 0.35) -> Vector3:
	var c: Vector3 = a["c"]
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	if a.has("r"):
		return c + d * (float(a["r"]) - inset)
	var tx: float = INF if absf(d.x) < 0.001 else (float(a["hx"]) - inset) / absf(d.x)
	var tz: float = INF if absf(d.z) < 0.001 else (float(a["hz"]) - inset) / absf(d.z)
	return c + d * minf(tx, tz)


## Route a jump from the edge of `a` to the middle of `b` (+ offset). speed > 0 marks a momentum jump.
func _hop(a: Dictionary, b: Dictionary, off: Vector3 = Vector3.ZERO, hold: bool = true, speed: float = 0.0) -> void:
	var to: Vector3 = (b["c"] as Vector3) + off
	r_jump(_w(_edge(a, to)), _w(to), hold)
	if speed > 0.0:
		route[route.size() - 1]["speed"] = speed


func _haz(c: Vector3, size: Vector3, yaw_extra: float = 0.0) -> void:
	kit.hazard(_w(c), size, _yaw + yaw_extra)


## Hedge-trimmer brick just past block `b`, square to the arrival direction from `a` (punishes overshoot).
func _hedge_behind(a: Dictionary, b: Dictionary, width: float = 1.6) -> void:
	var ca: Vector3 = a["c"]
	var cb: Vector3 = b["c"]
	var d := Vector3(cb.x - ca.x, 0, cb.z - ca.z).normalized()
	var half: float = minf(float(b["hx"]) / maxf(absf(d.x), 0.001), float(b["hz"]) / maxf(absf(d.z), 0.001))
	var yaw_local: float = rad_to_deg(atan2(-d.x, -d.z))
	_haz(cb + d * (half + 0.55) + Vector3(0, 0.55, 0), Vector3(width, 1.5, 0.5), yaw_local)


func _lawn(c: Vector3, size: float = 7.0, cp: bool = true, cp_yaw: float = 0.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 2.0)
	var h: float = size * 0.5 - 0.7
	kit.tree(_w(c + Vector3(-h, 0, h)), kit.rng.randf_range(1.0, 1.4))
	kit.round_tree(_w(c + Vector3(h, 0, h)), kit.rng.randf_range(0.9, 1.2))
	kit.bush(_w(c + Vector3(h, 0, h - 1.3)))
	kit.bush(_w(c + Vector3(-h + 1.4, 0, h)), 1.2)
	kit.pillar(_w(c + Vector3(0, -2.0, 0)), 1.3, 14.0)
	if cp:
		kit.checkpoint(_w(c), _yaw + cp_yaw)
		kit.banner(_w(c + Vector3(-h, 0, -h)), 4.0)
		kit.banner(_w(c + Vector3(h, 0, -h)), 4.0, Look.c("accent2"))
	return d


func _bar_due(sw: Sweeper, world_pt: Vector3, lead: float, tol_deg: float) -> bool:
	var rel: Vector3 = world_pt - sw.global_position
	var pa: float = atan2(-rel.z, rel.x)
	var a: float = sw.angle_at(Game.course_time + lead)
	for i: int in sw.bar_count:
		var d: float = wrapf(a + TAU * float(i) / float(sw.bar_count) - pa, -PI, PI)
		if absf(d) < deg_to_rad(tol_deg):
			return true
	return false


func _bar_clear(sw: Sweeper, world_pt: Vector3, t0: float, t1: float, tol_deg: float) -> bool:
	var lead: float = t0
	while lead <= t1:
		if _bar_due(sw, world_pt, lead, tol_deg):
			return false
		lead += 0.05
	return true


## Bot: wait at `from` until a mower bar will cross the middle of the hop while we are at the top of the jump.
func _mower_hop(from: Vector3, to: Vector3) -> void:
	var mid: Vector3 = _w((from + to) * 0.5)
	route.append({"kind": "b_wait", "test": func() -> bool: return _bar_due(_mower, mid, 0.38, 6.0)})
	r_jump(_w(from), _w(to))


# ---- the course --------------------------------------------------------------------------------

func _build() -> void:
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	_frame(Vector3.ZERO, 0.0)
	var cp1: Vector3 = _stage_1_gate()
	var cp2: Vector3 = _stage_2_stones(cp1)
	_frame(_w(cp2), 90.0)
	var cp3: Vector3 = _stage_3_springs()
	_frame(_w(cp3), 90.0)
	var cp4: Vector3 = _stage_4_runways()
	_frame(_w(cp4), 0.0)
	var cp5: Vector3 = _stage_5_hedges()
	_frame(_w(cp5), 0.0)
	var cp6: Vector3 = _stage_6_mower()
	_frame(_w(cp6), -90.0)
	var cp7: Vector3 = _stage_7_chute()
	_frame(_w(cp7), 0.0)
	var cp8: Vector3 = _stage_8_great_leap()
	_frame(_w(cp8), -90.0)
	var cp9: Vector3 = _stage_9_circuit()
	_frame(_w(cp9), -90.0)
	var cp10: Vector3 = _stage_10_topiary()
	_frame(_w(cp10), 180.0)
	var cp11: Vector3 = _stage_11_greenhouse()
	_frame(_w(cp11), 180.0)
	var cp12: Vector3 = _stage_12_maze()
	_frame(_w(cp12), -90.0)
	var cp13: Vector3 = _stage_13_windmill()
	_frame(_w(cp13), 0.0)
	var cp14: Vector3 = _stage_14_flowers()
	_frame(_w(cp14), 0.0)
	var cp15: Vector3 = _stage_15_press()
	_frame(_w(cp15), -90.0)
	var cp16: Vector3 = _stage_16_chimney()
	_frame(_w(cp16), 180.0)
	var cp17: Vector3 = _stage_17_orchard()
	_frame(_w(cp17), 180.0)
	_stage_18_summit()
	_surroundings()
	_ambience()
	_debug_start()


# Stage 1: warm-up. Big start terrace, then shrinking blocks, a diagonal and rises.
func _stage_1_gate() -> Vector3:
	kit.plat(Vector3(0, 0, 0), Vector3(16, 2, 16))
	var start: Dictionary = _area(Vector3.ZERO, 8.0, 8.0)
	kit.arch(Vector3(0, 0, -6.8), 5.0, 4.2)
	for p: Vector3 in [Vector3(-6, 0, 5), Vector3(6, 0, 5.5), Vector3(-6.2, 0, -4), Vector3(6.3, 0, -3)]:
		kit.tree(p, kit.rng.randf_range(1.0, 1.5))
	kit.bush(Vector3(-5, 0, 0.5))
	kit.bush(Vector3(5.4, 0, 1.2), 1.3)
	kit.round_tree(Vector3(-6.5, 0, 1.5), 1.1)
	kit.ball(Vector3(5.0, 0.6, -5.5), 0.45, Look.c("accent"))
	kit.ball(Vector3(-5.2, 0.6, -6.0), 0.38, Look.c("accent2"))
	kit.pillar(Vector3(0, -2, 0), 2.4, 18.0)

	var a1: Dictionary = _blk(Vector3(0, 0, -13.8), 3.2, 3.2)
	var a2: Dictionary = _blk(Vector3(3.8, 1.0, -20.2), 2.8, 2.8, "alt")
	var a3: Dictionary = _blk(Vector3(0, 2.0, -26.6), 2.6, 2.6)
	var a4: Dictionary = _blk(Vector3(0, 2.0, -33.8), 2.4, 2.4, "alt")
	var lawn: Dictionary = _lawn(Vector3(0, 2.5, -42.6))
	kit.bush(Vector3(1.0, 0, -14.8), 0.7)
	kit.lamp(Vector3(4.9, 1.0, -21.3), 2.4, false)
	_hop(start, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	_hop(a3, a4)
	_hop(a4, lawn, Vector3(0, 0, 1.6))
	r_checkpoint()
	return lawn["c"]


# Stage 2: precision parkour. 1.8 m blocks, 78-88 % jumps, a 0.9 m beam and a 2 m rung.
func _stage_2_stones(from_c: Vector3) -> Vector3:
	var lawn: Dictionary = _area(from_c, 3.5, 3.5)
	var z0: float = from_c.z
	var y0: float = from_c.y
	kit.arch(_w(from_c + Vector3(0, 0, -3.1)), 4.4, 4.0)
	var p1: Dictionary = _blk(Vector3(0, y0, z0 - 9.3), 2.0, 2.0)
	var p2: Dictionary = _blk(Vector3(-3.6, y0 + 1.0, z0 - 14.2), 1.8, 1.8, "alt")
	var p3: Dictionary = _blk(Vector3(-3.6, y0 + 2.5, z0 - 19.5), 1.8, 1.8)
	var p4: Dictionary = _blk(Vector3(2.0, y0 + 2.5, z0 - 24.1), 1.8, 1.8, "alt")
	var beam: Dictionary = _blk(Vector3(2.0, y0 + 2.5, z0 - 32.6), 0.9, 7.0, "accent", 0.6)
	var p5: Dictionary = _blk(Vector3(2.0, y0 + 4.0, z0 - 40.6), 1.8, 1.8)
	var p6: Dictionary = _blk(Vector3(-2.8, y0 + 5.0, z0 - 44.4), 1.8, 1.8, "alt")
	var p7: Dictionary = _blk(Vector3(-2.8, y0 + 7.0, z0 - 49.3), 1.8, 1.8)
	var p8: Dictionary = _blk(Vector3(1.8, y0 + 8.5, z0 - 53.5), 1.8, 1.8, "alt")
	var p9: Dictionary = _blk(Vector3(1.8, y0 + 8.5, z0 - 60.1), 1.6, 1.6)
	var end: Dictionary = _lawn(Vector3(1.8, y0 + 8.5, z0 - 69.2), 7.0, true, 90.0)
	_hop(lawn, p1)
	_hop(p1, p2)
	_hop(p2, p3)
	_hop(p3, p4)
	_hop(p4, beam, Vector3(0, 0, 2.4))
	_hop(beam, p5)
	_hop(p5, p6)
	_hop(p6, p7)
	_hop(p7, p8)
	_hop(p8, p9)
	_hop(p9, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	return end["c"]


# Stage 3: bounce pads. Safe first bounce, then sprint-bounces: the pads are too far apart for a standing bounce.
func _stage_3_springs() -> Vector3:
	kit.pad(_w(Vector3(0, 0, -2.3)), 17.0, 0.0, 0.0, 1.2)
	var l1: Dictionary = _blk(Vector3(0, 4.0, -9.75), 5.0, 8.5, "alt", 1.2)
	kit.bush(_w(Vector3(-2.0, 4.0, -6.2)))
	kit.round_tree(_w(Vector3(2.0, 4.0, -6.4)), 0.8)
	r_pad(_w(Vector3(0, 0, -2.3)), _w(Vector3(0, 4.0, -8.2)))
	kit.pad(_w(Vector3(0, 4.0, -12.7)), 17.0, 0.0, 0.0, 1.1)
	var l2: Dictionary = _blk(Vector3(0, 6.5, -19.8), 2.2, 2.2)
	r_pad(_w(Vector3(0, 4.0, -12.7)), _w(l2["c"]))
	var dc: Dictionary = _disc(Vector3(0, 6.5, -26.6), 1.5, "accent")
	kit.pad(_w(dc["c"]), 19.0, 0.0, 0.0, 1.2)
	_hop(l2, dc)
	var dd: Dictionary = _disc(Vector3(0, 8.5, -35.4), 1.5, "accent")
	kit.pad(_w(dd["c"]), 19.0, 0.0, 0.0, 1.2)
	r_pad(_w(dc["c"]), _w(dd["c"]))
	var l3: Dictionary = _blk(Vector3(0, 10.5, -44.2), 2.2, 2.2, "alt")
	r_pad(_w(dd["c"]), _w(l3["c"]))
	var end: Dictionary = _lawn(Vector3(0, 10.5, -53.4))
	_hop(l3, end, Vector3(0, 0, 1.6))
	r_checkpoint()
	return end["c"]


# Stage 4: boost strips. 17 m/s over a 10 m gap, then 20 m/s over 12.5 m onto a 3 x 4 m lawn, off-axis.
func _stage_4_runways() -> Vector3:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	var r1: Dictionary = _blk(Vector3(0, 0, -13.5), 3.6, 10.0, "alt")
	kit.boost(_w(Vector3(0, 0.02, -14.6)), Vector3(2.6, 0.3, 7.0), _yaw, 17.0)
	var r2: Dictionary = _blk(Vector3(0, 0, -36.0), 4.0, 15.0)
	kit.boost(_w(Vector3(0, 0.02, -39.4)), Vector3(2.6, 0.3, 7.4), _yaw, 20.0)
	var r3: Dictionary = _blk(Vector3(2.0, 0, -58.0), 3.0, 4.0, "alt")
	var q1: Dictionary = _blk(Vector3(-0.8, 1.5, -64.0), 1.8, 1.8)
	var end: Dictionary = _lawn(Vector3(-0.8, 1.5, -73.4), 7.0, true, -90.0)
	kit.arch(_w(Vector3(0, 0, -9.2)), 3.0, 4.0, _yaw)
	kit.lamp(_w(Vector3(1.7, 0, -29.2)), 2.6, false)
	kit.lamp(_w(Vector3(-1.7, 0, -29.2)), 2.6, false)
	_hop(lawn, r1, Vector3(0, 0, 3.6))
	_hop(r1, r2, Vector3(0, 0, 5.4), true, 17.0)
	_hop(r2, r3, Vector3.ZERO, true, 20.0)
	_hop(r3, q1)
	_hop(q1, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	return end["c"]


# Stage 5: kill bricks. Hop a trimmer, long-jump a double, tap-jump under a red ceiling, then zig-zag
# up blocks whose far side is a hedge trimmer (overshoot = respawn). Shortcut: three 1 m tiles straight up the middle.
func _stage_5_hedges() -> Vector3:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	var h1: Dictionary = _blk(Vector3(0, 0, -16.0), 3.0, 18.0, "alt")
	_haz(Vector3(0, 0.3, -11.0), Vector3(3.4, 0.6, 0.7))
	_haz(Vector3(0, 0.3, -15.4), Vector3(3.4, 0.6, 0.9))
	_haz(Vector3(0, 0.3, -16.6), Vector3(3.4, 0.6, 0.9))
	_haz(Vector3(0, 2.95, -21.5), Vector3(3.4, 0.5, 4.4))
	_haz(Vector3(0, 0.225, -21.5), Vector3(3.4, 0.45, 0.4))
	for sx: float in [-1.85, 1.85]:
		for sz: float in [-19.5, -23.5]:
			kit.block(_w(Vector3(sx, 1.35, sz)), Vector3(0.3, 2.7, 0.3), Look.c("metal"), false)
	_hop(lawn, h1, Vector3(0, 0, 7.6))
	r_jump(_w(Vector3(0, 0, -9.4)), _w(Vector3(0, 0, -13.0)))
	r_jump(_w(Vector3(0, 0, -13.9)), _w(Vector3(0, 0, -18.6)))
	r_jump(_w(Vector3(0, 0, -20.3)), _w(Vector3(0, 0, -23.1)), false)
	var z1: Dictionary = _blk(Vector3(2.4, 1.0, -29.9), 1.8, 1.8)
	var z2: Dictionary = _blk(Vector3(-2.4, 2.0, -34.6), 1.8, 1.8, "alt")
	var z3: Dictionary = _blk(Vector3(2.4, 3.0, -39.0), 1.8, 1.8)
	var z4: Dictionary = _blk(Vector3(-1.6, 3.0, -45.0), 1.8, 1.8, "alt")
	var end: Dictionary = _lawn(Vector3(0, 3.0, -54.2))
	_hedge_behind(h1, z1)
	_hedge_behind(z1, z2)
	_hedge_behind(z2, z3)
	_hedge_behind(z3, z4)
	r_jump(_w(Vector3(0.7, 0, -24.65)), _w(z1["c"]))
	_hop(z1, z2)
	_hop(z2, z3)
	_hop(z3, z4)
	_hop(z4, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	# shortcut: 1 m tiles, 90 %+ jumps
	_blk(Vector3(0, 1.2, -31.0), 1.0, 1.0, "accent", 0.5)
	_blk(Vector3(0, 2.4, -36.2), 1.0, 1.0, "accent", 0.5)
	_blk(Vector3(-0.6, 3.0, -41.2), 1.0, 1.0, "accent", 0.5)
	return end["c"]


# Stage 6: The Mower. Circle the west side of the disc AGAINST the blades, hopping each one. The rim and the
# east side are hedge; the red hub can be cleared with a full jump - that is the shortcut.
func _stage_6_mower() -> Vector3:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	var cz: float = -15.0
	var m: Dictionary = _disc(Vector3(0, 0, cz), 7.0, "alt", 1.0)
	_mower = kit.sweeper(_w(Vector3(0, 0, cz)), 5.0, 2, 4.0, 0.0, 0.45)
	_haz(Vector3(0, 0.65, cz), Vector3(2.2, 1.3, 2.2))
	_haz(Vector3(4.3, 0.6, cz), Vector3(5.4, 1.2, 0.6))
	for deg: int in [300, 320, 340, 0, 20, 40, 60, 120, 140, 160, 180, 200, 220, 240]:
		var a: float = deg_to_rad(float(deg))
		_haz(Vector3(cos(a) * 6.35, 0.5, cz - sin(a) * 6.35), Vector3(2.3, 1.0, 1.0), float(deg) + 90.0)
	kit.pillar(_w(Vector3(0, -1.0, cz)), 2.2, 16.0)
	var e := Vector3(0, 0, cz + 6.2)
	var s1 := Vector3(-2.18, 0, cz + 3.11)
	var s2 := Vector3(-3.8, 0, cz)
	var s3 := Vector3(-2.18, 0, cz - 3.11)
	var x := Vector3(0, 0, cz - 6.2)
	_hop(lawn, m, e - (m["c"] as Vector3))
	_mower_hop(e, s1)
	_mower_hop(s1, s2)
	_mower_hop(s2, s3)
	_mower_hop(s3, x)
	var n1: Dictionary = _blk(Vector3(0, 1.0, cz - 12.0), 1.8, 1.8)
	var m2c := Vector3(0, 1.0, cz - 21.0)
	_disc(m2c, 4.5, "alt", 1.0)
	_fan = kit.sweeper(_w(m2c), 4.0, 3, 3.6, 0.0, 0.45)
	kit.pillar(_w(m2c + Vector3(0, -1.0, 0)), 1.6, 16.0)
	var land2: Vector3 = m2c + Vector3(1.6, 0, 3.5)
	var out2: Vector3 = m2c + Vector3(1.6, 0, -3.75)
	var n2: Dictionary = _blk(Vector3(3.0, 2.0, cz - 30.2), 1.8, 1.8, "alt")
	var end: Dictionary = _lawn(Vector3(3.0, 2.0, cz - 39.4), 7.0, true, -90.0)
	_hop(m, n1)
	var land2_w: Vector3 = _w(land2)
	route.append({"kind": "b_wait", "test": func() -> bool: return _bar_clear(_fan, land2_w, 0.6, 1.1, 32.0)})
	r_jump(_w(_edge(n1, land2)), land2_w)
	route.append({"kind": "b_sweep", "to": _w(out2), "sweeper": _fan, "tol": 0.5})
	r_jump(_w(out2), _w(n2["c"]))
	_hop(n2, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	return end["c"]


# Stage 7: Frost Chute. Climb, then a 25 degree ice slide between trimmer posts, jump at the lip: 14.5 m ravine, then an ice rink landing you cannot brake on.
func _stage_7_chute() -> Vector3:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	var i1: Dictionary = _blk(Vector3(0, 1.5, -8.2), 1.8, 1.8)
	var i2: Dictionary = _blk(Vector3(3.4, 3.0, -13.0), 1.8, 1.8, "alt")
	var td: Dictionary = _blk(Vector3(0, 4.0, -19.0), 3.0, 3.0)
	kit.slick(_w(Vector3(0, 4.0 - 3.381, -20.5 - 7.25)), Vector3(3.6, 0.4, 16.0), _yaw, -25.0)
	kit.slick(_w(Vector3(0, -2.762, -38.0)), Vector3(3.6, 0.4, 6.0), _yaw, 0.0)
	_haz(Vector3(-1.55, -2.16, -38.0), Vector3(0.5, 1.2, 2.0))
	_haz(Vector3(1.55, -2.16, -38.0), Vector3(0.5, 1.2, 2.0))
	kit.pillar(_w(Vector3(0, -3.2, -38.0)), 1.2, 12.0)
	kit.pillar(_w(Vector3(0, 3.0, -19.0)), 1.0, 16.0)
	var il: Dictionary = _blk(Vector3(0, -4.0, -59.5), 5.0, 8.0, "alt", 1.5)
	kit.slick(_w(Vector3(0, -4.0, -71.0)), Vector3(3.0, 0.4, 6.0), _yaw, 0.0)
	var rink: Dictionary = _area(Vector3(0, -4.0, -71.0), 1.5, 3.0)
	var i3: Dictionary = _blk(Vector3(0, -3.0, -79.1), 1.8, 1.8)
	var end: Dictionary = _lawn(Vector3(2.6, -3.0, -88.3), 7.0, true, 90.0)
	kit.tree(_w(Vector3(-1.9, -4.0, -62.7)), 1.2)
	_hop(lawn, i1)
	_hop(i1, i2)
	_hop(i2, td)
	r_walk(_w(Vector3(0, 4.0, -19.6)))
	r_jump(_w(Vector3(0, -2.762, -40.5)), _w(Vector3(0, -4.0, -58.5)))
	route[route.size() - 1]["speed"] = 21.0
	_hop(il, rink, Vector3(0, 0, 1.6))
	_hop(rink, i3)
	_hop(i3, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	return end["c"]


# Stage 8: set piece - the Great Leap. A ladder of 1.9 m rungs to the launch deck, the angled pad throws you
# through the ring gate onto a 4.4 m disc, and the way off is a descending diagonal chain.
# Shortcut: the pink bumper on the lawn corner - touch its far side and it hurls you at the third rung.
func _stage_8_great_leap() -> Vector3:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	var g1: Dictionary = _blk(Vector3(0, 1.9, -7.6), 1.7, 1.7)
	var g2: Dictionary = _blk(Vector3(4.0, 3.8, -11.4), 1.7, 1.7, "alt")
	var g3: Dictionary = _blk(Vector3(0.2, 5.7, -15.4), 1.7, 1.7)
	var deck: Dictionary = _blk(Vector3(0.2, 7.6, -21.6), 3.0, 4.6, "alt", 1.2)
	var pad_at := Vector3(0.2, 7.6, -22.5)
	kit.pad(_w(pad_at), 21.0, 40.0, _yaw, 1.3)
	kit.ring(_w(pad_at + Vector3(0, 4.4, -7.2)), 3.0)
	kit.pillar(_w(Vector3(0.2, 6.4, -21.6)), 1.2, 18.0)
	var gl: Dictionary = _disc(Vector3(0.2, 5.6, -37.0), 2.2, "accent")
	kit.pillar(_w(Vector3(0.2, 4.8, -37.0)), 1.0, 16.0)
	var d1: Dictionary = _blk(Vector3(-4.0, 4.6, -44.0), 1.6, 1.6)
	var d2: Dictionary = _blk(Vector3(0.6, 3.6, -50.0), 1.6, 1.6, "alt")
	var d3: Dictionary = _blk(Vector3(0.6, 5.0, -55.4), 1.6, 1.6)
	var end: Dictionary = _lawn(Vector3(0.6, 5.0, -64.6), 7.0, true, -90.0)
	kit.bumper(_w(Vector3(2.6, 0, -2.4)), 13.5, 21.0, 0.7)
	_hop(lawn, g1)
	_hop(g1, g2)
	_hop(g2, g3)
	_hop(g3, deck, Vector3(0, 0, 1.4))
	r_pad(_w(pad_at), _w(gl["c"]))
	_hop(gl, d1)
	_hop(d1, d2)
	_hop(d2, d3)
	_hop(d3, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	return end["c"]


# Stage 9: Grand Circuit. Two hard hops, hop a trimmer on the runway, boost to 20 m/s, leap 12 m onto a pad,
# carry the speed pad -> pad -> a 3.2 m disc, last jump to the old finish plaza - now checkpoint 9, and the
# old finish arch is the gate to the extension.
func _stage_9_circuit() -> Vector3:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	var f1: Dictionary = _blk(Vector3(0, 1.5, -8.0), 1.8, 1.8)
	var f2: Dictionary = _blk(Vector3(-3.6, 1.5, -13.8), 1.6, 1.6, "alt")
	var rw: Dictionary = _blk(Vector3(0, 1.5, -27.0), 3.6, 16.0)
	_haz(Vector3(0, 1.8, -23.6), Vector3(4.0, 0.6, 0.7))
	kit.boost(_w(Vector3(0, 1.52, -30.6)), Vector3(2.6, 0.3, 8.0), _yaw, 20.0)
	var p1: Dictionary = _disc(Vector3(0, 1.5, -49.2), 2.1, "accent")
	kit.pad(_w(p1["c"]), 17.0, 0.0, 0.0, 1.4)
	var p2: Dictionary = _disc(Vector3(0, 2.5, -64.3), 1.7, "accent")
	kit.pad(_w(p2["c"]), 17.0, 0.0, 0.0, 1.4)
	var fl: Dictionary = _disc(Vector3(0, 2.5, -77.8), 1.6, "alt")
	var fin: Dictionary = _blk(Vector3(0, 2.5, -91.2), 12.0, 14.0, "main", 2.0)
	var cp := Vector3(0, 2.5, -88.6)
	kit.checkpoint(_w(cp), _yaw)
	kit.arch(_w(Vector3(0, 2.5, -94.5)), 5.0, 4.6, _yaw)
	kit.banner(_w(Vector3(-2.9, 2.5, -94.9)), 5.0)
	kit.banner(_w(Vector3(2.9, 2.5, -94.9)), 5.0, Look.c("accent2"))
	_cue_near(_w(cp + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	for p: Vector3 in [Vector3(-4.8, 2.5, -88), Vector3(4.8, 2.5, -87.6), Vector3(-5, 2.5, -98.5), Vector3(5, 2.5, -98)]:
		kit.tree(_w(p), kit.rng.randf_range(1.1, 1.6))
	kit.bush(_w(Vector3(-4.6, 2.5, -93)))
	kit.bush(_w(Vector3(4.4, 2.5, -92)), 1.2)
	kit.pillar(_w(Vector3(0, 0.5, -92.6)), 2.0, 18.0)
	kit.pillar(_w(Vector3(0, 0.5, -27)), 1.2, 14.0)
	_hop(lawn, f1)
	_hop(f1, f2)
	_hop(f2, rw, Vector3(0, 0, 6.4))
	r_jump(_w(Vector3(0, 1.5, -22.1)), _w(Vector3(0, 1.5, -25.8)))
	r_jump(_w(Vector3(0, 1.5, -34.4)), _w((p1["c"] as Vector3) + Vector3(0, 0, -0.9)))
	route[route.size() - 1]["speed"] = 20.0
	r_pad(_w(p1["c"]), _w((p2["c"] as Vector3) + Vector3(0, 0, -0.9)))
	r_pad(_w(p2["c"]), _w(fl["c"]))
	_hop(fl, fin, Vector3(0, 0, 5.0))
	r_walk(_w(cp))
	r_checkpoint()
	return cp


# ==== THE EXTENSION (stages 10-18) =============================================================

# ---- helpers for the new half ----------------------------------------------------------------

func _fx_on() -> bool:
	return DisplayServer.get_name() != "headless"


## Half-extents of a local box in world axes (for emission boxes of unrotated emitters).
func _ext(v: Vector3) -> Vector3:
	return (_b * v).abs()


## Feedback trigger at world `pos`: fires `fx` when `test` turns true, or (no test) when the
## player comes within `radius`. Headless runs build nothing.
func _cue(pos: Vector3, fx: GPUParticles3D, radius: float = 0.0, test: Callable = Callable(), cooldown: float = 0.5) -> void:
	if not _fx_on():
		fx.free()
		return
	var c := GardensCue.new()
	c.radius = radius
	c.test = test
	c.cooldown = cooldown
	c.position = pos
	c.add_child(fx)
	add_child(c)


func _cue_near(pos: Vector3, radius: float, fx: GPUParticles3D) -> void:
	_cue(pos, fx, radius)


## Ambient emitter at world `pos` (skipped headless).
func _amb(pos: Vector3, fx: GPUParticles3D) -> void:
	if not _fx_on():
		fx.free()
		return
	fx.position = pos
	add_child(fx)


## Decorative or solid hedge box (local centre, local size).
func _hedge(c: Vector3, size: Vector3, collide: bool = true) -> void:
	kit.block(_w(c), size, HEDGE.lightened(kit.rng.randf_range(0.0, 0.08)), collide, _yaw)


## Clipped topiary ball sitting on a hedge top (decor).
func _topiary(top: Vector3, r: float = 0.5) -> void:
	var n := Look.sphere(r, Look.flat(HEDGE.lightened(0.12), 0.9))
	n.position = _w(top + Vector3(0, r * 0.85, 0))
	add_child(n)


## Wall-run panel along the stage heading at local x, from z0 to z1 (z0 > z1), centre height y.
func _panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> WallRunPanel:
	var w: WallRunPanel = kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	# trellis posts at the ends and ivy on the back face
	var back: float = signf(x) * 0.45
	for z: float in [z0, z1]:
		kit.block(_w(Vector3(x + back, y - 0.5, z)), Vector3(0.35, height + 1.0, 0.35), Look.c("trim"), false, _yaw)
	for i: int in int(absf(z0 - z1) / 2.5):
		var z: float = z0 - 1.25 - 2.5 * float(i)
		kit.block(_w(Vector3(x + back * 1.1, y + kit.rng.randf_range(-1.5, 1.5), z)), Vector3(0.3, kit.rng.randf_range(1.2, 2.6), 0.9), HEDGE.lightened(0.1), false, _yaw)
	kit.pillar(_w(Vector3(x + back, y - height * 0.5, (z0 + z1) * 0.5)), 0.5, 30.0)
	return w


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> LedgeBlock:
	return kit.ledge(_w(top), size, _yaw, style)


## A fence of stacked laser beams across the path (local centre x/z, floor y), one rhythm.
func _fence(x: float, y: float, z: float, width: float, heights: Array, period: float, on: float, phase: float) -> LaserGate:
	var first: LaserGate = null
	for h: float in heights:
		var g: LaserGate = kit.laser(_w(Vector3(x, y + h, z)), Vector3(width, 0.22, 0.22), period, on, phase, _yaw)
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


## Nothing of the ram is out (no punch, not extended) during [now + a, now + b].
func _ram_clear(p: Piston, a: float, b: float) -> bool:
	var t: float = Game.course_time + a
	while t <= Game.course_time + b:
		if p.is_punching_at(t) or p.extension_at(t) > 0.03:
			return false
		t += 0.04
	return true


## Signpost for a fork: a lamp and a glow pad at local `p`.
func _sign(p: Vector3, color: Color) -> void:
	kit.lamp(_w(p + Vector3(0, 0, 0.8)), 3.0, true, color)
	kit.glow_strip(_w(p + Vector3(0, 0.03, 0)), Vector3(1.4, 0.06, 1.4), color, _yaw)


## Dev helper: `-- --gardens_from=N` starts the run on checkpoint N and drops the route before it
## (fast iteration on late stages; the game never passes it).
func _debug_start() -> void:
	var n: int = 0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--gardens_from="):
			n = int(a.trim_prefix("--gardens_from="))
	if n <= 0:
		return
	var cps: Array[Node] = find_children("*", "Checkpoint", true, false)
	if n > cps.size():
		return
	var cp := cps[n - 1] as Node3D
	set_spawn(cp.global_position + Vector3(0, 0.1, 0), cp.global_rotation_degrees.y)
	var seen: int = 0
	var cut: int = 0
	for i: int in route.size():
		if str(route[i]["kind"]) == "checkpoint":
			seen += 1
			if seen == n:
				cut = i + 1
				break
	route = route.slice(cut)


# ---- stage 10: Topiary Runs - the first wall run and the first mantle -------------------------
# From the old finish plaza (now checkpoint 9) through its arch: a 19 m gap with nothing under it
# but a trellis panel on the right - run it and kick off onto the landing. A hedge wall too tall to
# jump (3.4 m) has a gold lip: mantle it. Then hedge-top hops (a trimmer behind the rise) to the lawn.
func _stage_10_topiary() -> Vector3:
	_panel(2.3, 1.2, -12.6, -27.6)
	var l1: Dictionary = _blk(Vector3(-2.4, 0, -33.1), 3.6, 3.6, "alt")
	var wall: Dictionary = _area(Vector3(-2.4, 3.4, -37.2), 1.8, 2.3)
	_ledge(Vector3(-2.4, 3.4, -37.2), Vector3(3.6, 6.0, 4.6))
	var t1: Dictionary = _blk(Vector3(-0.2, 3.4, -45.2), 1.8, 1.8)
	var t2: Dictionary = _blk(Vector3(3.0, 4.4, -50.2), 1.8, 1.8, "alt")
	var beam: Dictionary = _blk(Vector3(3.2, 4.4, -58.6), 0.9, 5.0, "accent", 0.6)
	var end: Dictionary = _lawn(Vector3(3.2, 5.4, -69.0), 7.0, true, -90.0)
	# hedge walls either side of the mantle, topiary on top
	_hedge(Vector3(-4.8, 1.4, -37.2), Vector3(1.2, 4.0, 4.6), false)
	_hedge(Vector3(0.0, 1.4, -37.2), Vector3(1.2, 4.0, 4.6), false)
	_topiary(Vector3(-4.8, 3.4, -37.2), 0.6)
	_topiary(Vector3(0.0, 3.4, -37.2), 0.6)
	for z: float in [-45.2, -58.6]:
		kit.pillar(_w(Vector3(3.2 if z < -50 else -0.2, 2.4 if z < -50 else 1.4, z)), 0.7, 16.0)
	kit.lamp(_w(Vector3(-4.2, 0, -31.8)), 2.6, false)
	kit.tree(_w(Vector3(-5.8, 3.4, -38.6)), 1.1)
	r_wallrun(_w(Vector3(0.5, 0, -9.2)), _w(Vector3(1.7, 1.4, -13.7)), _w(Vector3(1.7, 1.4, -25.3)), _w(Vector3(-2.4, 0, -32.8)))
	r_mantle(_w(Vector3(-2.4, 0, -33.3)), _w(Vector3(-2.4, 3.4, -36.4)))
	_hop(wall, t1)
	_hop(t1, t2)
	_hop(t2, beam, Vector3(0, 0, 1.6))
	_hop(beam, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	_cue_near(_w(end["c"] + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	_amb(_w(Vector3(1.0, 3.0, -20.0)), GardensFx.seeds(Vector3(5, 3, 9), _b * Vector3(-0.6, 0.15, -0.4), 26))
	return end["c"]


# ---- stage 11: The Greenhouse - BRANCH ----------------------------------------------------------
# A fork under the glasshouse frame. LEFT (red lamps): the planter walkway, a 1.2 m beam swept by
# three sprinkler pistons - read the rhythm and walk through. RIGHT (gold lamps): the rafters - two
# mantle walls, a blinking seed tray and the drop to the merge deck. Both rejoin before the lawn.
func _stage_11_greenhouse() -> Vector3:
	_blk(Vector3(0, 0, -5.0), 12.0, 3.0, "main", 1.0)
	_sign(Vector3(-4.0, 0, -4.6), Color(1.0, 0.35, 0.3))
	_sign(Vector3(4.0, 0, -4.6), LedgeBlock.LIP_COLOR)
	# LEFT - the planter walkway and its pistons
	_blk(Vector3(-4.0, 0, -18.5), 1.2, 24.0, "alt", 0.6)
	var rams: Array[Piston] = []
	var zs: Array[float] = [-11.0, -17.5, -24.0]
	for i: int in 3:
		var p: Piston = kit.piston(_w(Vector3(-6.2, 1.65, zs[i])), Vector3(2.2, 1.6, 2.0), _yaw - 90.0, 2.8, 2.4, 0.2 * float(i), 10.0)
		rams.append(p)
		_cue(_w(Vector3(-4.0, 1.0, zs[i])), GardensFx.spray(_b * Vector3(1, 0.5, 0)), 0.0, func() -> bool: return p.is_punching_at(Game.course_time), 0.8)
		# planter boxes between the rams (off the walkway)
		_hedge(Vector3(-6.4, 0.5, zs[i] + 3.25), Vector3(1.6, 1.0, 1.6), false)
		kit.bush(_w(Vector3(-6.4, 1.0, zs[i] + 3.25)), 0.8)
	# sprinkler pipe over the walkway, drizzling
	kit.pipe(_w(Vector3(-4.0, 6.5, -6.0)), _w(Vector3(-4.0, 6.5, -30.0)), 0.12, Look.c("metal"))
	_amb(_w(Vector3(-4.0, 4.0, -18.0)), GardensFx.drizzle(_ext(Vector3(0.5, 2.2, 11.0)), 60))
	# RIGHT - the rafters
	_ledge(Vector3(4.0, 3.2, -9.5), Vector3(3.0, 6.0, 3.0), "alt")
	_ledge(Vector3(4.0, 6.4, -16.0), Vector3(3.0, 9.2, 3.0), "alt")
	var bk: Vector3 = Vector3(4.0, 6.4, -22.6)
	var blink: BlinkPlatform = kit.blink(_w(bk), Vector3(1.8, 0.5, 1.8), 2.4, 0.55, 0.3)
	# merge deck and the lawn
	var merge: Dictionary = _blk(Vector3(0, 0, -31.5), 12.0, 5.0, "main", 1.0)
	var end: Dictionary = _lawn(Vector3(0, 1.5, -40.8), 7.0, true, 0.0)
	# the glasshouse frame: white ribs arching over both routes
	for z: float in [-7.0, -14.0, -21.0, -28.0]:
		for sx: float in [-1.0, 1.0]:
			kit.block(_w(Vector3(sx * 11.5, 4.0, z)), Vector3(0.3, 14.0, 0.3), Look.c("trim"), false, _yaw)
		kit.block(_w(Vector3(0, 11.0, z)), Vector3(23.3, 0.3, 0.3), Look.c("trim"), false, _yaw)
		kit.block(_w(Vector3(0, 12.4, z)), Vector3(12.0, 0.25, 0.25), Look.c("trim"), false, _yaw)
	for sx: float in [-1.0, 1.0]:
		kit.block(_w(Vector3(sx * 11.5, 11.0, -17.5)), Vector3(0.25, 0.25, 21.3), Look.c("trim"), false, _yaw)
	kit.block(_w(Vector3(0, 12.6, -17.5)), Vector3(0.25, 0.25, 21.3), Look.c("trim"), false, _yaw)
	_amb(_w(Vector3(0, 5.0, -18.0)), GardensFx.pollen(_ext(Vector3(9, 4, 12)), 40))
	if route_variant == 0:
		r_walk(_w(Vector3(-4.0, 0, -6.2)))
		for i: int in 3:
			var p: Piston = rams[i]
			r_walk(_w(Vector3(-4.0, 0, zs[i] + 2.9)))
			r_until(func() -> bool: return _ram_clear(p, 0.0, 0.75))
		r_walk(_w(Vector3(-4.0, 0, -29.6)))
	else:
		r_walk(_w(Vector3(4.0, 0, -4.4)))
		r_mantle(_w(Vector3(4.0, 0, -5.9)), _w(Vector3(4.0, 3.2, -9.0)))
		r_mantle(_w(Vector3(4.0, 3.2, -10.6)), _w(Vector3(4.0, 6.4, -15.2)))
		r_until(func() -> bool: return blink.is_on_at(Game.course_time + 0.7) and blink.is_on_at(Game.course_time + 1.6))
		r_jump(_w(Vector3(4.0, 6.4, -17.15)), _w(bk))
		r_jump(_w(bk + Vector3(0, 0, -0.55)), _w(Vector3(1.5, 0, -30.8)))
	_hop(merge, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	_cue_near(_w(end["c"] + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	return end["c"]


# ---- stage 12: The Hedge Maze - SET PIECE: THE TRIMMER -------------------------------------------
# A 30 m hedge alley. The Trimmer - a laser curtain between two shear posts riding the hedge tops -
# glides down the alley and back on the course clock. Follow it in, hop the kill hedges, duck into a
# side pocket while it comes back past you, then run for the exit behind it. Mantle out of the maze and
# cross two laser gaps to the lawn.
var _trim: GardensTrimmer


## Where the Trimmer's beam is along the alley (metres from its start) and whether it is heading out.
func _trim_s(t: float) -> float:
	return _trim.a.z - _trim.offset_at(t).z


func _trim_out(t: float) -> bool:
	return fposmod(t / _trim.period + _trim.phase, 1.0) < 0.5


func _stage_12_maze() -> Vector3:
	var floor_c := Vector3(0, 0, -21.25)
	_blk(floor_c, 3.0, 35.5, "alt", 1.0)
	# hedge walls with pockets: left at -14 and -30, right at -22
	var pockets: Array = [[-1.0, -14.0], [1.0, -22.0], [-1.0, -30.0]]
	for sx: float in [-1.0, 1.0]:
		var cuts: Array[float] = []
		for pk: Array in pockets:
			if float(pk[0]) == sx:
				cuts.append(float(pk[1]))
		var z: float = -5.5
		cuts.append(-37.0 - 1.2)
		for cz: float in cuts:
			var z_end: float = cz + 1.2
			if z - z_end > 0.1:
				_hedge(Vector3(sx * 2.1, 1.2, (z + z_end) * 0.5), Vector3(1.2, 4.4, z - z_end))
			z = cz - 1.2
	for pk: Array in pockets:
		var sx: float = float(pk[0])
		var pz: float = float(pk[1])
		_blk(Vector3(sx * 2.4, 0, pz), 1.8, 2.4, "main", 1.0)
		_hedge(Vector3(sx * 3.9, 1.2, pz), Vector3(1.2, 4.4, 4.8))
		_hedge(Vector3(sx * 3.0, 1.2, pz + 1.8), Vector3(0.6, 4.4, 1.2))
		_hedge(Vector3(sx * 3.0, 1.2, pz - 1.8), Vector3(0.6, 4.4, 1.2))
		kit.glow_strip(_w(Vector3(sx * 2.4, 0.03, pz)), Vector3(1.0, 0.06, 1.6), Look.c("accent2"), _yaw)
		_topiary(Vector3(sx * 3.9, 3.4, pz), 0.55)
	# kill hedges across the alley floor
	for z: float in [-18.0, -26.0]:
		_haz(Vector3(0, 0.25, z), Vector3(3.0, 0.5, 0.5))
	# THE TRIMMER
	_trim = GardensTrimmer.new()
	_trim.a = Vector3(0, 1.5, -6.0)
	_trim.b = Vector3(0, 1.5, -36.0)
	_trim.period = 7.0
	_trim.beam_size = Vector3(3.0, 3.0, 0.25)
	_trim.position = _o
	_trim.rotation_degrees.y = _yaw
	add_child(_trim)
	# the maze beyond the alley (decor hedges, no collision)
	for i: int in 10:
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var zz: float = -6.0 - 3.2 * float(i)
		_hedge(Vector3(sx * kit.rng.randf_range(6.5, 9.0), 0.8, zz), Vector3(kit.rng.randf_range(2.5, 5.0), 3.0, 1.0), false)
		_hedge(Vector3(sx * 10.5, 0.8, zz - 1.6), Vector3(1.0, 3.0, kit.rng.randf_range(2.0, 4.0)), false)
	kit.block(_w(Vector3(0, -0.6, -21.0)), Vector3(22.0, 0.8, 34.0), HEDGE.darkened(0.3), false, _yaw)
	kit.pillar(_w(Vector3(0, -1.0, -21.0)), 2.4, 18.0)
	kit.arch(_w(Vector3(0, 0, -4.6)), 4.0, 4.4, _yaw, HEDGE.lightened(0.15))
	# out of the maze: a 3.4 m hedge wall to mantle, then two laser gaps
	_ledge(Vector3(0, 3.4, -41.5), Vector3(3.6, 6.0, 5.0))
	_hedge(Vector3(-2.4, 1.4, -41.5), Vector3(1.2, 4.0, 5.0), false)
	_hedge(Vector3(2.4, 1.4, -41.5), Vector3(1.2, 4.0, 5.0), false)
	var f1: LaserGate = _fence(0, 3.4, -46.7, 3.2, [0.5, 1.4, 2.3], 2.4, 0.45, 0.0)
	var b1: Dictionary = _blk(Vector3(0, 3.4, -49.6), 1.8, 1.8)
	var f2: LaserGate = _fence(1.5, 4.4, -52.9, 4.4, [0.5, 1.4, 2.3], 2.4, 0.45, 0.5)
	var b2: Dictionary = _blk(Vector3(2.8, 4.4, -54.8), 1.8, 1.8, "alt")
	var end: Dictionary = _lawn(Vector3(2.8, 5.4, -62.8), 7.0, true, 90.0)
	kit.pillar(_w(Vector3(0, 2.4, -49.6)), 0.7, 14.0)
	kit.pillar(_w(Vector3(2.8, 3.4, -54.8)), 0.7, 14.0)
	# route: follow the curtain in, pocket 2 while it comes back, then out behind it
	r_walk(_w(Vector3(0, 0, -4.4)))
	r_until(func() -> bool:
		var u: float = fposmod(Game.course_time / _trim.period + _trim.phase, 1.0)
		return u > 0.1 and u < 0.16)
	r_walk(_w(Vector3(0, 0, -16.4)))
	r_jump(_w(Vector3(0, 0, -16.9)), _w(Vector3(0, 0, -19.4)))
	r_walk(_w(Vector3(0.4, 0, -21.0)))
	r_walk(_w(Vector3(2.5, 0, -22.0)))
	r_until(func() -> bool: return not _trim_out(Game.course_time) and _trim_s(Game.course_time) < 13.0)
	r_walk(_w(Vector3(0, 0, -23.6)))
	r_jump(_w(Vector3(0, 0, -24.9)), _w(Vector3(0, 0, -27.4)))
	r_walk(_w(Vector3(0, 0, -36.0)))
	r_mantle(_w(Vector3(0, 0, -37.4)), _w(Vector3(0, 3.4, -40.6)))
	r_until(func() -> bool: return _dark(f1, 0.1, 0.95))
	r_jump(_w(Vector3(0, 3.4, -43.65)), _w(b1["c"]))
	r_until(func() -> bool: return _dark(f2, 0.0, 0.8))
	_hop(b1, b2)
	_hop(b2, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	_cue_near(_w(end["c"] + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	_amb(_w(Vector3(0, 2.0, -21.0)), GardensFx.fireflies(_ext(Vector3(4, 1.5, 15)), 30))
	return end["c"]


func _stage_13_windmill() -> Vector3:
	return Vector3.ZERO


func _stage_14_flowers() -> Vector3:
	return Vector3.ZERO


func _stage_15_press() -> Vector3:
	return Vector3.ZERO


func _stage_16_chimney() -> Vector3:
	return Vector3.ZERO


func _stage_17_orchard() -> Vector3:
	return Vector3.ZERO


func _stage_18_summit() -> void:
	kit.finish(_w(Vector3.ZERO), _yaw)


func _ambience() -> void:
	pass


func _surroundings() -> void:
	kit.cloud_field(Vector3(-60, -14, -130), Vector3(170, 8, 170), 34)
	kit.cloud_field(Vector3(-60, 60, -130), Vector3(200, 10, 200), 12)
	kit.monolith_ring(Vector3(-60, 10, -130), 190.0, 260.0, 20, 26.0)
	for spot: Vector3 in [Vector3(-16, -2, -30), Vector3(14, 3, -75), Vector3(-30, 12, -80), Vector3(-70, 14, -115), Vector3(-100, 16, -80),
			Vector3(-150, 18, -125), Vector3(-108, 20, -150), Vector3(-150, 22, -185), Vector3(-95, 12, -215), Vector3(-45, 14, -170),
			Vector3(-92, 20, -235), Vector3(-40, 20, -262), Vector3(-20, 22, -222)]:
		kit.disc(spot, kit.rng.randf_range(2.5, 4.0), 1.0, "main")
		kit.tree(spot + Vector3(0.5, 0, 0.3), kit.rng.randf_range(1.2, 1.9))
		kit.bush(spot + Vector3(-1.2, 0, 0.8))
