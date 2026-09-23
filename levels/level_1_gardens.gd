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
## The extension (stages 10-18) climbs on east in a serpentine to the summit, ~60 m higher:
##  10 Topiary Runs      the first wall run (a 16 m gap only the trellis panel crosses), the first mantle (3.4 m
##                       hedge wall), hedge-top hops
##  11 The Greenhouse    BRANCH: the planter walkway swept by three sprinkler PISTONS, or the rafters (two mantles
##                       and a blinking seed tray)
##  12 The Hedge Maze    SET PIECE - THE TRIMMER (mechanics/gardens_trimmer.gd): a laser curtain gliding up and down a
##                       30 m hedge alley; follow it in, hop the kill hedges, duck into a side pocket while it comes back,
##                       then out behind it; mantle out of the maze and time two LASER gaps
##  13 The Windmill      board a seed tray on the turning sails, ride it up and leap onto the roof gallery, drop to a
##                       flower pad; shortcut: the vine ladder spiralling up the tower (crosses the trays' path)
##  14 Flower Beds       BRANCH: sprint-bounce three giant flower pads, or the trellis (two chained wall runs)
##  15 The Potting Press a walkway under three slamming CRUSHERS with a gap between, a mantle whose lip sits under a
##                       fourth press, then ride the last press up like a lift; shortcut: four 1 m pot tiles (90 % hops)
##  16 Topiary Chimney   three alternating wall runs up a chimney, the last kick ends in a mantle; tap-hops under
##                       trimmer ceilings
##  17 The Orchard       BRANCH: boost strip into an 11 m leap and a laser bridge, or three hops (an 88 % one) up the
##                       apple terrace to a WARP RING that drops you at the merge deck
##  18 Summit Garden     hop + boost to 20 m/s and a 12 m leap, a wall run over the void, sprint onto the bounce pad at
##                       the foot of the summit wall and mantle its lip at the top of the bounce, a piston and a laser
##                       on the ridge, finish under fireworks
## Shortcuts: the 1 m tiles (5), the mower hub (6), the pink bumper (8), the vine ladder (13), the pot tiles (15).
## Particles (visual/gardens_fx.gd): pollen, petals and dandelion seeds all along the course, plus per-stage effects -
## greenhouse drizzle and sprinkler sprays, the Trimmer's clippings, sail petals, leaf updraft, soil bursts from the
## presses, sparkle rings, petal fountains on every checkpoint lawn and fireworks over the summit (GardensCue).
## The course is built stage by stage in a local frame (heading = local -Z) so it can turn.
## Route variants: 0 = main lines; 1 = every alternative branch (rafters, trellis, warp ring).

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
	_panel(2.3, 1.2, -11.4, -27.6)
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


# ---- stage 13: The Windmill - ride a seed tray up the sails ---------------------------------------
# Four seed trays hang level on the tips of the windmill's sails (a ferris wheel facing you). Board
# one as it sweeps past the foot of the mill, ride it up the far side and leap off at the top onto the
# mill's roof gallery, drop to a flower pad and bounce to the lawn.
# Shortcut: the vine ladder - five 1 m ledges zig-zagging up the tower's side, reached by crossing
# the trays' path at the bottom.
var _trays: Array[MovingPlatform] = []


func _stage_13_windmill() -> Vector3:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	var a1: Dictionary = _blk(Vector3(0, 0.5, -9.0), 2.0, 2.0)
	var deck: Dictionary = _blk(Vector3(0, 1.0, -16.4), 6.0, 3.6, "alt", 1.0)
	var zc: float = -20.0
	var hub := Vector3(0, 1.0 + MILL_R, zc)
	var axis: Vector3 = (_b * Vector3(0, 0, 1)).normalized()
	_trays.clear()
	for i: int in 4:
		_trays.append(kit.orbiter(_w(hub), MILL_R, axis, Vector3(2.4, 0.4, 2.4), MILL_PERIOD, 0.25 * float(i)))
	# the sails, turned by the clock in step with the trays
	var sails := GardensSails.new()
	sails.axis = axis
	sails.period = MILL_PERIOD
	sails.position = _w(hub)
	add_child(sails)
	var arm0: Vector3 = axis.cross(Vector3.UP).normalized()
	var wood: StandardMaterial3D = Look.flat(Color(0.55, 0.38, 0.26), 0.85)
	var cloth: StandardMaterial3D = Look.flat(Color(0.98, 0.94, 0.86), 0.9)
	for i: int in 4:
		var d: Vector3 = arm0.rotated(axis, 0.25 * float(i) * TAU)
		var side: Vector3 = axis.cross(d).normalized()
		var holder := Node3D.new()
		holder.basis = Basis(d, side, axis)
		sails.add_child(holder)
		holder.add_child(Look.box(Vector3(MILL_R - 1.4, 0.22, 0.18), wood, Vector3((MILL_R - 1.4) * 0.5 + 0.1, 0, 0)))
		holder.add_child(Look.box(Vector3(MILL_R - 2.2, 1.5, 0.05), cloth, Vector3((MILL_R - 2.2) * 0.5 + 0.9, 0.9, -0.35)))
		for k: int in 4:
			holder.add_child(Look.box(Vector3(0.08, 1.6, 0.1), wood, Vector3(1.4 + float(k) * 1.1, 0.85, -0.3)))
	sails.add_child(Look.sphere(0.75, Look.flat(Look.c("accent"), 0.5, 0.2, 0.6)))
	# the mill: tower, axle, roof gallery
	kit.block(_w(Vector3(0, 1.5, -24.8)), Vector3(4.6, 20.0, 4.6), Color(0.96, 0.9, 0.8), true, _yaw)
	kit.pipe(_w(hub), _w(hub + Vector3(0, 0, -2.6)), 0.3, Color(0.4, 0.32, 0.26))
	var roof: Dictionary = _blk(Vector3(0, 12.5, -24.8), 6.0, 6.0, "main", 1.0)
	for sx: float in [-1.0, 1.0]:
		kit.lamp(_w(Vector3(sx * 2.6, 12.5, -27.4)), 1.6, false)
		kit.block(_w(Vector3(sx * 2.3, -3.0, -24.8)), Vector3(0.9, 9.0, 5.2), Color(0.86, 0.78, 0.68), false, _yaw)
	kit.pillar(_w(Vector3(0, -8.5, -24.8)), 2.2, 16.0)
	kit.pillar(_w(Vector3(0, 0.0, -16.4)), 1.0, 14.0)
	# down from the roof: a flower pad and the lawn
	var d1: Dictionary = _disc(Vector3(0, 8.5, -33.6), 1.5, "accent")
	kit.pad(_w(d1["c"]), 19.0, 0.0, 0.0, 1.2)
	kit.pillar(_w(Vector3(0, 7.7, -33.6)), 0.7, 12.0)
	var end: Dictionary = _lawn(Vector3(0, 10.5, -44.6), 7.0, true, 90.0)
	# shortcut: the vine ladder up the tower's left side
	var vine: Array[Vector3] = [Vector3(-4.0, 1.0, -23.2), Vector3(-4.6, 2.9, -26.2), Vector3(-3.6, 4.8, -29.4),
			Vector3(-0.6, 6.7, -30.0), Vector3(2.6, 8.6, -29.4), Vector3(4.0, 10.5, -26.4)]
	for v: Vector3 in vine:
		_blk(v, 1.0, 1.0, "accent", 0.5)
		kit.block(_w(v + Vector3(0.1, -1.2, 0)), Vector3(0.25, 2.0, 0.25), HEDGE.lightened(0.15), false, _yaw)
	# route
	_hop(lawn, a1)
	_hop(a1, deck, Vector3(0, 0, 0.8))
	var board := Vector3(0, 1.0, -17.8)
	r_walk(_w(board))
	var bottom: Vector3 = _w(hub + Vector3(0, -MILL_R, 0)) - Vector3(0, 0.2, 0)
	var top: Vector3 = _w(hub + Vector3(0, MILL_R, 0)) - Vector3(0, 0.2, 0)
	route.append({"kind": "x_wait", "nodes": _trays, "locals": [Vector3.ZERO], "point": bottom, "radius": 0.6, "lead": 0.8})
	route.append({"kind": "x_jump", "from": _w(board), "to_local": Vector3(0, 0.2, 0), "picked": true, "hold": true})
	route.append({"kind": "x_jump", "picked": true, "when_local": Vector3.ZERO, "when_point": top, "when_radius": 0.9, "lead": 0.0,
			"to": _w(Vector3(0, 12.5, -24.2)), "hold": true})
	_hop(roof, d1)
	r_pad(_w(d1["c"]), _w(end["c"] + Vector3(0, 0, 2.0)))
	r_checkpoint()
	# effects: petals shed by the sails, a burst on the roof, the lawn fountain
	_amb(_w(hub + Vector3(0, 0, 0.5)), GardensFx.petals(_ext(Vector3(6, 4, 1.5)), 30))
	_cue_near(_w(roof["c"] + Vector3(0, 0.3, 0)), 2.5, GardensFx.sparkle_ring(Look.c("accent2")))
	_cue_near(_w(end["c"] + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	return end["c"]


# ---- stage 14: Flower Beds - BRANCH -------------------------------------------------------------
# LEFT (pink lamps): sprint onto three giant flower pads in a row - each bounce keeps your run speed and
# throws you 8.8 m and 2 m up to the next. RIGHT (cyan lamps): the trellis - wall run the right panel,
# kick across to the left one, run it and kick out onto the terrace. Both land on the terrace.
func _stage_14_flowers() -> Vector3:
	_blk(Vector3(0, 0, -5.0), 12.0, 3.0, "main", 1.0)
	_sign(Vector3(-4.5, 0, -4.6), Color(1.0, 0.45, 0.7))
	_sign(Vector3(4.5, 0, -4.6), WallRunPanel.RUN_COLOR)
	# LEFT - flower pads
	var pads: Array[Vector3] = [Vector3(-4.5, 0, -12.5), Vector3(-4.5, 2.0, -21.3), Vector3(-4.5, 4.0, -30.1)]
	var petal_cols: Array[Color] = [Color(1.0, 0.45, 0.7), Color(1.0, 0.85, 0.3), Color(0.75, 0.55, 1.0)]
	for i: int in 3:
		var pc: Vector3 = pads[i]
		_disc(pc, 1.5, "accent")
		kit.pad(_w(pc), 19.0, 0.0, 0.0, 1.2)
		kit.pillar(_w(pc + Vector3(0, -0.8, 0)), 0.6, 12.0, HEDGE)
		for k: int in 7:
			var a: float = float(k) / 7.0 * TAU
			var petal := Look.sphere(0.55, Look.flat(petal_cols[i], 0.7))
			petal.scale = Vector3(1.0, 0.25, 1.8)
			petal.position = _w(pc + Vector3(cos(a) * 1.9, -0.45, sin(a) * 1.9))
			petal.rotation.y = -a + deg_to_rad(_yaw) + PI * 0.5
			add_child(petal)
		_cue(_w(pc + Vector3(0, 0.3, 0)), GardensFx.sparkle_ring(petal_cols[i]), 1.6)
	# RIGHT - the trellis walkway and its two panels
	_blk(Vector3(5.0, 0, -10.75), 1.6, 8.5, "alt", 0.6)
	_panel(6.8, 1.2, -17.1, -24.5)
	_panel(2.2, 6.0, -23.0, -34.0)
	# the terrace where they meet, and the lawn
	var merge: Dictionary = _blk(Vector3(0.5, 6.0, -41.25), 17.0, 7.5, "main", 1.0)
	kit.pillar(_w(Vector3(0.5, 5.0, -41.25)), 1.6, 16.0)
	var end: Dictionary = _lawn(Vector3(0.5, 7.0, -52.5), 7.0, true, 0.0)
	# giant decorative flowers round the beds
	for fp: Vector3 in [Vector3(-10, -2, -16), Vector3(-9, 0, -30), Vector3(11, -1, -12), Vector3(-11, 3, -44), Vector3(11, 4, -46)]:
		var h: float = kit.rng.randf_range(4.0, 6.0)
		kit.block(_w(fp + Vector3(0, h * 0.5, 0)), Vector3(0.25, h, 0.25), HEDGE, false, _yaw)
		var col: Color = petal_cols[kit.rng.randi_range(0, 2)]
		for k: int in 6:
			var a: float = float(k) / 6.0 * TAU
			var petal := Look.sphere(0.7, Look.flat(col, 0.7))
			petal.scale = Vector3(1.0, 0.3, 1.9)
			petal.position = _w(fp + Vector3(cos(a) * 1.2, h, sin(a) * 1.2))
			petal.rotation.y = -a + deg_to_rad(_yaw) + PI * 0.5
			add_child(petal)
		var mid := Look.sphere(0.6, Look.flat(Color(1.0, 0.85, 0.25), 0.6, 0.0, 0.4))
		mid.position = _w(fp + Vector3(0, h + 0.1, 0))
		add_child(mid)
	if route_variant == 0:
		r_jump(_w(Vector3(-4.5, 0, -6.15)), _w(pads[0]))
		r_pad(_w(pads[0]), _w(pads[1]))
		r_pad(_w(pads[1]), _w(pads[2]))
		r_pad(_w(pads[2]), _w(Vector3(-3.5, 6.0, -39.8)))
	else:
		r_walk(_w(Vector3(5.0, 0, -8.0)))
		r_wallrun(_w(Vector3(5.0, 0, -14.6)), _w(Vector3(6.2, 1.4, -19.1)), _w(Vector3(6.2, 1.4, -22.0)), _w(Vector3(2.8, 5.5, -25.9)))
		r_wallrun(Vector3.ZERO, _w(Vector3(2.8, 5.5, -25.9)), _w(Vector3(2.8, 5.5, -31.9)), _w(Vector3(5.0, 6.0, -40.0)), true, true)
	_hop(merge, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	_amb(_w(Vector3(0, 8.0, -24.0)), GardensFx.petals(_ext(Vector3(10, 3, 16)), 40))
	_amb(_w(Vector3(0, 4.0, -24.0)), GardensFx.pollen(_ext(Vector3(9, 4, 14)), 36))
	_cue_near(_w(end["c"] + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	return end["c"]


# ---- stage 15: The Potting Press - crushers ----------------------------------------------------
# A walkway under three slamming soil presses (read the rhythm, and there is a gap to hop between
# them), then a 3.4 m wall whose lip sits UNDER a fourth press - mantle while it is up and get out
# from under it. The last press is the lift: jump on its back while it rests, ride it up, step off
# onto the high deck. Shortcut: four 1 m pot tiles up the right side (90 % jumps), landing next to
# the wall press.
func _press_clear(c: Crusher, a: float, b: float) -> bool:
	return c.is_clear_for(Game.course_time + a, b - a)


func _stage_15_press() -> Vector3:
	_blk(Vector3(0, 0, -7.75), 2.6, 8.5, "alt", 0.8)
	_blk(Vector3(0, 0, -20.5), 2.6, 11.0, "alt", 0.8)
	var pr: Array[Crusher] = []
	var spots: Array[Vector3] = [Vector3(0, 0, -7.5), Vector3(0, 0, -18.0), Vector3(0, 0, -23.0), Vector3(0, 3.4, -28.6)]
	var phases: Array[float] = [0.0, 0.35, 0.15, 0.6]
	for i: int in 4:
		pr.append(kit.crusher(_w(spots[i]), Vector3(2.8, 1.6, 2.8), 3.2, 2.8, phases[i]))
	_ledge(Vector3(0, 3.4, -29.5), Vector3(3.0, 6.0, 5.0), "alt")
	_blk(Vector3(0, 3.4, -36.0), 4.0, 8.0, "alt", 1.0)
	var lift: Crusher = kit.crusher(_w(Vector3(0, 3.4, -36.5)), Vector3(2.6, 1.6, 2.6), 3.2, 3.2, 0.0)
	kit.plat(_w(Vector3(0, 8.8, -42.3)), Vector3(5.0, 1.0, 5.0), "main", 0.3, _yaw)
	var high: Dictionary = _area(Vector3(0, 8.8, -42.3), 2.5, 2.5)
	var end: Dictionary = _lawn(Vector3(0, 9.8, -51.5), 7.0, true, -90.0)
	kit.pillar(_w(Vector3(0, -0.8, -15.0)), 1.0, 14.0)
	kit.pillar(_w(Vector3(0, 2.4, -36.0)), 1.4, 16.0)
	# the pot tiles (shortcut)
	for v: Vector3 in [Vector3(3.0, 1.0, -8.5), Vector3(3.0, 2.2, -13.8), Vector3(3.0, 3.4, -19.2), Vector3(2.4, 3.4, -24.5)]:
		_blk(v, 1.0, 1.0, "accent", 0.5)
		var pot := Look.cylinder(0.45, 0.8, Look.flat(Color(0.78, 0.42, 0.28), 0.8), Vector3.ZERO, 0.32, 10)
		pot.position = _w(v + Vector3(0, -0.9, 0))
		add_child(pot)
	# potting-shed dressing: sacks, pots, a potting bench along the walkway
	for i: int in 5:
		var z: float = -5.0 - 5.0 * float(i)
		var pot2 := Look.cylinder(0.5, 0.9, Look.flat(Color(0.8, 0.45, 0.3), 0.8), Vector3.ZERO, 0.36, 10)
		pot2.position = _w(Vector3(-2.6, -0.2, z))
		add_child(pot2)
		kit.bush(_w(Vector3(-2.6, 0.25, z)), 0.8)
	# soil bursts when each press slams
	for c: Crusher in pr + [lift]:
		var cc: Crusher = c
		_cue(cc.global_position - Vector3(0, cc.size.y * 0.5 + cc.gap_at(Game.course_time), 0) + Vector3(0, 0.1, 0), GardensFx.soil(),
				0.0, func() -> bool: return cc.gap_at(Game.course_time) < 0.05, 0.6)
	# route
	var p0: Crusher = pr[0]
	var p1: Crusher = pr[1]
	var p2: Crusher = pr[2]
	var p3: Crusher = pr[3]
	r_walk(_w(Vector3(0, 0, -4.3)))
	r_until(func() -> bool: return _press_clear(p0, 0.0, 1.0))
	r_walk(_w(Vector3(0, 0, -11.0)))
	r_until(func() -> bool: return _press_clear(p1, 0.3, 1.3) and _press_clear(p2, 0.6, 1.8))
	r_jump(_w(Vector3(0, 0, -11.65)), _w(Vector3(0, 0, -16.0)))
	r_walk(_w(Vector3(0, 0, -25.4)))
	r_until(func() -> bool: return _press_clear(p3, 0.0, 1.6))
	r_mantle(_w(Vector3(0, 0, -25.6)), _w(Vector3(0, 3.4, -28.2)))
	r_walk(_w(Vector3(0, 3.4, -33.0)))
	r_until(func() -> bool:
		var u: float = fposmod(Game.course_time / lift.period + lift.phase, 1.0)
		return u >= 0.56 and u < 0.64)
	route.append({"kind": "b_jump", "from": _w(Vector3(0, 3.4, -33.3)), "to": _w(Vector3(0, 5.0, -36.5)), "hold": true})
	r_until(func() -> bool:
		var u: float = fposmod(Game.course_time / lift.period + lift.phase, 1.0)
		return u >= 0.02 and u < 0.3)
	route.append({"kind": "b_jump", "from": _w(Vector3(0, 8.2, -36.5)), "to": _w(Vector3(0, 8.8, -41.8)), "hold": true})
	_hop(high, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	_amb(_w(Vector3(0, 3.0, -20.0)), GardensFx.pollen(_ext(Vector3(5, 3, 14)), 30))
	_cue_near(_w(end["c"] + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	return end["c"]


# ---- stage 16: Topiary Chimney - three wall runs up, out by a mantle ------------------------------
# Three ivy trellis panels zig-zag up a chimney over the void: run the right one, kick across to the
# left, kick back to the right, and the last kick throws you at a hedge ledge 3 m above - mantle it.
# Then three tap-hops under red trimmer ceilings to the lawn.
func _stage_16_chimney() -> Vector3:
	_panel(2.3, 1.2, -4.6, -12.0)
	_panel(-2.3, 6.0, -10.5, -18.5)
	_panel(2.3, 9.0, -16.5, -24.5)
	var top: Dictionary = _area(Vector3(-0.75, 11.9, -28.0), 2.25, 2.0)
	_ledge(Vector3(-0.75, 11.9, -28.0), Vector3(4.5, 14.0, 4.0))
	_topiary(Vector3(-2.6, 11.9, -29.6), 0.45)
	r_wallrun(_w(Vector3(0.5, 0, -2.1)), _w(Vector3(1.7, 1.4, -6.6)), _w(Vector3(1.7, 1.4, -9.5)), _w(Vector3(-1.7, 5.5, -13.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 5.5, -13.4)), _w(Vector3(-1.7, 5.5, -16.4)), _w(Vector3(1.7, 8.5, -20.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 8.5, -20.0)), _w(Vector3(1.7, 8.5, -21.4)), _w(Vector3(-0.75, 11.9, -26.6)), true, true)
	# the tap-hop run under trimmer ceilings
	var a: Dictionary = top
	var xs: Array[float] = [1.2, -1.0, 1.0]
	for i: int in 3:
		var b: Dictionary = _blk(Vector3(-0.75 + xs[i], 11.9, -32.6 - 3.3 * float(i)), 1.6, 1.6, "alt", 0.8)
		var ca: Vector3 = a["c"]
		var cb: Vector3 = b["c"]
		_haz((ca + cb) * 0.5 + Vector3(0, 2.95, 0), Vector3(3.0, 0.4, 3.0))
		_hop(a, b, Vector3.ZERO, false)
		a = b
	var end: Dictionary = _lawn(Vector3(0, 11.9, -47.6), 7.0, true, -90.0)
	_hop(a, end, Vector3(0, 0, 1.7))
	r_checkpoint()
	# leaves swirling up the chimney, a sparkle when you top out
	_amb(_w(Vector3(0, 6.0, -15.0)), GardensFx.leaf_updraft(_ext(Vector3(2.0, 4.0, 8.0)), 40))
	_amb(_w(Vector3(0, 1.0, -15.0)), GardensFx.seeds(_ext(Vector3(2.5, 1.0, 8.0)), Vector3(0, 1.6, 0), 20))
	_cue_near(_w(Vector3(-0.75, 12.1, -27.0)), 2.2, GardensFx.sparkle_ring(LedgeBlock.LIP_COLOR))
	_cue_near(_w(end["c"] + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	return end["c"]


# ---- stage 17: The Orchard - BRANCH ------------------------------------------------------------
# LEFT (orange lamps): the runway - a boost strip into an 11 m leap, then a 1.2 m laser bridge with two
# gates to time. RIGHT (blue lamps): three hops up the apple terrace, the last an 88 % leap, into the
# warp ring that drops you out beside the merge deck - quicker, if you stick the landing.
func _stage_17_orchard() -> Vector3:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	_sign(Vector3(-1.5, 0, -4.4), Color(1.0, 0.55, 0.2))
	# LEFT - runway, leap, laser bridge
	var runway: Dictionary = _blk(Vector3(-1.5, 0, -11.25), 3.0, 15.5, "alt", 1.0)
	kit.boost(_w(Vector3(-1.5, 0.02, -14.8)), Vector3(2.4, 0.3, 7.6), _yaw, 17.0)
	var isle: Dictionary = _blk(Vector3(-1.5, 0, -31.0), 3.0, 4.0, "main", 1.0)
	_blk(Vector3(-1.5, 0, -40.0), 1.2, 14.0, "accent", 0.6)
	var f1: LaserGate = _fence(-1.5, 0, -37.0, 1.8, [0.5, 1.4], 2.4, 0.45, 0.0)
	var f2: LaserGate = _fence(-1.5, 0, -42.0, 1.8, [0.5, 1.4], 2.4, 0.45, 0.4)
	kit.pillar(_w(Vector3(-1.5, -1.0, -31.0)), 1.0, 14.0)
	# RIGHT - the apple terrace and its warp ring
	var r1: Dictionary = _blk(Vector3(2.8, 1.0, -8.4), 1.4, 1.4)
	var r2: Dictionary = _blk(Vector3(3.6, 2.0, -13.8), 1.4, 1.4, "alt")
	var terr: Dictionary = _blk(Vector3(4.4, 2.0, -21.2), 3.2, 3.2, "main", 1.0)
	kit.pillar(_w(Vector3(4.4, 1.0, -21.2)), 1.0, 14.0)
	var ring: WarpPortal = kit.portal(_w(Vector3(4.4, 2.0, -21.6)), _yaw, _w(Vector3(3.5, 0, -47.6)), _yaw, 8.0)
	kit.glow_strip(_w(Vector3(2.8, 1.03, -8.4)), Vector3(0.6, 0.06, 0.6), WarpPortal.EXIT_COLOR, _yaw)
	kit.glow_strip(_w(Vector3(3.6, 2.03, -13.8)), Vector3(0.6, 0.06, 0.6), WarpPortal.EXIT_COLOR, _yaw)
	kit.lamp(_w(Vector3(3.0, 0, -2.6)), 3.0, true, WarpPortal.EXIT_COLOR)
	# merge deck and the lawn
	var merge: Dictionary = _blk(Vector3(0.5, 0, -50.0), 10.0, 6.0, "main", 1.0)
	kit.pillar(_w(Vector3(0.5, -1.0, -50.0)), 1.6, 16.0)
	var end: Dictionary = _lawn(Vector3(0.5, 1.0, -60.2), 7.0, true, 0.0)
	# the orchard: apple trees on floating plots either side
	for p: Vector3 in [Vector3(-8, -1, -12), Vector3(-9, 0, -26), Vector3(10, -1, -30), Vector3(-8, -2, -44), Vector3(10, 0, -42), Vector3(9, 1, -8)]:
		kit.disc(_w(p), 2.2, 0.8, "main")
		_apple_tree(p)
	if route_variant == 0:
		r_walk(_w(Vector3(-1.5, 0, -6.0)))
		r_jump(_w(Vector3(-1.5, 0, -18.6)), _w(Vector3(-1.5, 0, -30.4)))
		route[route.size() - 1]["speed"] = 17.0
		r_walk(_w(Vector3(-1.5, 0, -34.4)))
		r_until(func() -> bool: return _dark(f1, 0.0, 0.7))
		r_walk(_w(Vector3(-1.5, 0, -39.8)))
		r_until(func() -> bool: return _dark(f2, 0.0, 0.7))
		r_walk(_w(Vector3(-1.5, 0, -46.0)))
		r_walk(_w(Vector3(0.5, 0, -51.5)))
	else:
		_hop(lawn, r1)
		_hop(r1, r2)
		_hop(r2, terr, Vector3(0, 0, 0.6))
		r_portal(_w(Vector3(4.4, 2.0, -21.6)), ring.exit_point())
		r_walk(_w(Vector3(1.5, 0, -51.5)))
	_hop(merge, end, Vector3(0, 0, 1.8))
	r_checkpoint()
	_cue_near(ring.exit_point() + Vector3(0, 0.6, 0), 2.0, GardensFx.sparkle_ring(WarpPortal.EXIT_COLOR, 44))
	_cue_near(_w(isle["c"] + Vector3(0, 0.3, 0)), 2.2, GardensFx.petal_fountain(30, 4.5))
	_amb(_w(Vector3(0, 5.0, -28.0)), GardensFx.petals(_ext(Vector3(10, 2, 18)), 34, [Color(1, 1, 1), Color(1.0, 0.8, 0.86), Color(1.0, 0.92, 0.95)]))
	_cue_near(_w(end["c"] + Vector3(0, 0.2, 0)), 2.4, GardensFx.petal_fountain())
	return end["c"]


func _apple_tree(p: Vector3) -> void:
	kit.round_tree(_w(p), kit.rng.randf_range(1.2, 1.6), Color(0.35, 0.62, 0.3))
	for k: int in 6:
		var apple := Look.sphere(0.16, Look.flat(Color(0.9, 0.15, 0.12), 0.5))
		apple.position = _w(p + Vector3(kit.rng.randf_range(-1.1, 1.1), kit.rng.randf_range(2.2, 3.4), kit.rng.randf_range(-1.1, 1.1)))
		add_child(apple)


# ---- stage 18: Summit Garden - the finale ---------------------------------------------------------
# Hop to the runway, boost to 20 m/s and leap 12 m, wall run a trellis over the void, sprint onto the
# bounce pad at the foot of the summit wall and mantle its lip at the top of the bounce, then time a
# piston and a laser gate on the ridge path to the summit lawn and the finish (fireworks).
func _stage_18_summit() -> void:
	var lawn: Dictionary = _area(Vector3.ZERO, 3.5, 3.5)
	var h1: Dictionary = _blk(Vector3(1.2, 1.0, -8.6), 1.8, 1.8)
	var runway: Dictionary = _blk(Vector3(0, 1.0, -21.0), 3.2, 14.0, "alt", 1.0)
	kit.boost(_w(Vector3(0, 1.02, -23.5)), Vector3(2.6, 0.3, 7.0), _yaw, 20.0)
	var isle: Dictionary = _blk(Vector3(0, 1.0, -41.5), 3.5, 4.0, "main", 1.0)
	_panel(-2.3, 2.2, -45.0, -61.5)
	var land: Dictionary = _blk(Vector3(2.4, 1.0, -68.0), 3.6, 6.0, "alt", 1.0)
	kit.pad(_w(Vector3(2.4, 1.0, -69.6)), 17.0, 0.0, 0.0, 1.1)
	_ledge(Vector3(2.4, 6.6, -75.0), Vector3(6.0, 10.0, 7.0))
	_blk(Vector3(2.4, 6.6, -84.25), 1.6, 11.5, "accent", 0.8)
	var ram: Piston = kit.piston(_w(Vector3(0.0, 8.25, -82.5)), Vector3(2.2, 1.6, 2.0), _yaw - 90.0, 3.0, 2.4, 0.0, 10.0)
	var gate: LaserGate = _fence(2.4, 6.6, -87.6, 2.4, [0.5, 1.4, 2.3], 2.4, 0.45, 0.3)
	_blk(Vector3(2.4, 6.6, -96.0), 12.0, 12.0, "main", 2.0)
	kit.finish(_w(Vector3(2.4, 6.6, -94.0)), _yaw)
	kit.pillar(_w(Vector3(2.4, 4.6, -96.0)), 2.4, 20.0)
	kit.pillar(_w(Vector3(0, 0, -21.0)), 1.2, 14.0)
	kit.pillar(_w(Vector3(0, 0, -41.5)), 1.2, 14.0)
	kit.pillar(_w(Vector3(2.4, 0, -68.0)), 1.2, 14.0)
	# the summit garden: trees, a ring of lamps, an arch over the finish, hedge walls round the plaza
	for p: Vector3 in [Vector3(-2.5, 6.6, -91.5), Vector3(7.3, 6.6, -91.5), Vector3(-2.6, 6.6, -100.6), Vector3(7.4, 6.6, -100.4)]:
		kit.round_tree(_w(p), kit.rng.randf_range(1.3, 1.7))
	for i: int in 8:
		var ang: float = float(i) / 8.0 * TAU
		kit.lamp(_w(Vector3(2.4 + cos(ang) * 5.2, 6.6, -96.0 + sin(ang) * 5.2)), 2.2, i % 2 == 0, Look.c("accent2"))
	_hedge(Vector3(2.4, 7.2, -101.6), Vector3(12.0, 1.2, 0.8), false)
	kit.banner(_w(Vector3(-0.4, 6.6, -93.2)), 5.0)
	kit.banner(_w(Vector3(5.2, 6.6, -93.2)), 5.0, Look.c("accent2"))
	kit.tree(_w(Vector3(-3.5, 1.0, -9.0)), 1.4)
	# route
	_hop(lawn, h1)
	_hop(h1, runway, Vector3(0, 0, 5.0))
	r_jump(_w(Vector3(0, 1.0, -27.6)), _w(Vector3(0, 1.0, -40.8)))
	route[route.size() - 1]["speed"] = 20.0
	r_wallrun(_w(Vector3(-0.5, 1.0, -43.1)), _w(Vector3(-1.7, 2.4, -47.6)), _w(Vector3(-1.7, 2.4, -59.2)), _w(Vector3(2.4, 1.0, -66.7)))
	r_walk(_w(Vector3(2.4, 1.0, -66.4)))
	var ledge_top: Vector3 = _w(Vector3(2.4, 6.6, -73.2))
	route.append({"kind": "a_fly", "to": ledge_top, "until": func() -> bool: return player.grounded and player.global_position.y > ledge_top.y - 0.3})
	r_walk(_w(Vector3(2.4, 6.6, -79.4)))
	r_until(func() -> bool: return _ram_clear(ram, 0.0, 0.75))
	r_walk(_w(Vector3(2.4, 6.6, -85.6)))
	r_until(func() -> bool: return _dark(gate, 0.0, 0.7))
	r_walk(_w(Vector3(2.4, 6.6, -95.0)))
	# effects: fireworks over the summit on a beat, a blossom burst at the gate
	var colors: Array = [[Color(1.0, 0.45, 0.6), Color(1.0, 0.9, 0.5)], [Color(0.5, 0.8, 1.0), Color(1, 1, 1)], [Color(1.0, 0.7, 0.2), Color(1.0, 0.35, 0.2)], [Color(0.7, 1.0, 0.5), Color(1.0, 1.0, 0.7)]]
	for i: int in 4:
		var off: float = 0.8 * float(i)
		var at: Vector3 = _w(Vector3(2.4 + [-5.0, 5.0, -3.0, 4.0][i], 18.0 + 2.0 * float(i % 2), -96.0 + [-3.0, 2.0, 5.0, -5.0][i]))
		_cue(at, GardensFx.firework(colors[i]), 0.0, func() -> bool: return fposmod(Game.course_time + off, 3.2) < 0.1, 1.0)
	_cue_near(_w(Vector3(2.4, 6.9, -94.0)), 3.0, GardensFx.petal_fountain(70, 8.0))
	_amb(_w(Vector3(2.4, 9.0, -96.0)), GardensFx.petals(_ext(Vector3(6, 2, 6)), 30))
	_amb(_w(Vector3(0, 3.0, -55.0)), GardensFx.seeds(_ext(Vector3(4, 3, 10)), _b * Vector3(-0.8, 0.2, -0.4), 24))


## Course-wide ambient particles, layered: golden pollen hanging over every checkpoint lawn, petals
## drifting down over every other one, and dandelion seeds riding the breeze all along the route.
func _ambience() -> void:
	var i: int = 0
	for cp: Node in find_children("*", "Checkpoint", true, false):
		var p: Vector3 = (cp as Node3D).global_position
		_amb(p + Vector3(0, 2.0, 0), GardensFx.pollen(Vector3(4.0, 2.0, 4.0), 22))
		if i % 2 == 0:
			_amb(p + Vector3(0, 7.0, 0), GardensFx.petals(Vector3(5.0, 1.0, 5.0), 16))
		i += 1
	var last := Vector3(INF, INF, INF)
	for step: Dictionary in route:
		var to: Variant = step.get("to", null)
		if not (to is Vector3) or (to as Vector3) == Vector3.ZERO:
			continue
		var q: Vector3 = to
		if q.distance_to(last) > 28.0:
			_amb(q + Vector3(0, 3.0, 0), GardensFx.seeds(Vector3(6.0, 3.0, 6.0), Vector3(0.7, 0.12, -0.35), 14))
			last = q


func _surroundings() -> void:
	kit.cloud_field(Vector3(-60, -14, -130), Vector3(170, 8, 170), 34)
	kit.cloud_field(Vector3(160, 4, -220), Vector3(100, 8, 110), 20)
	kit.cloud_field(Vector3(40, 125, -160), Vector3(240, 10, 200), 14)
	kit.monolith_ring(Vector3(45, 20, -160), 280.0, 340.0, 24, 40.0)
	for spot: Vector3 in [Vector3(-16, -2, -30), Vector3(14, 3, -75), Vector3(-30, 12, -80), Vector3(-70, 14, -115), Vector3(-100, 16, -80),
			Vector3(-150, 18, -125), Vector3(-108, 20, -150), Vector3(-150, 22, -185), Vector3(-95, 12, -215), Vector3(-45, 14, -170),
			Vector3(-92, 20, -235), Vector3(-40, 20, -262), Vector3(-20, 22, -222),
			Vector3(95, 26, -305), Vector3(90, 30, -250), Vector3(143, 46, -205), Vector3(100, 38, -140), Vector3(190, 64, -245),
			Vector3(140, 60, -300), Vector3(240, 78, -250), Vector3(245, 88, -150), Vector3(180, 80, -140), Vector3(230, 70, -305),
			Vector3(190, 76, -190)]:
		kit.disc(spot, kit.rng.randf_range(2.5, 4.0), 1.0, "main")
		kit.tree(spot + Vector3(0.5, 0, 0.3), kit.rng.randf_range(1.2, 1.9))
		kit.bush(spot + Vector3(-1.2, 0, 0.8))
