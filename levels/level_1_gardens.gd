extends LevelBase
## 1. LAUNCH GARDENS - sunny terrace gardens in the sky, and the first level of a hard obby.
## Nine stages, each ending on a checkpoint lawn. One new idea per stage, then combined:
##   1 Garden Gate      warm-up hops (already 70-80 % jumps)
##   2 Stepping Stones  small-block parkour: rising, diagonal, a narrow beam, a 2 m ladder step
##   3 Spring Beds      bounce pads - vertical pads keep your run speed, so SPRINT onto them
##   4 Runway Lawns     boost strips into 10 m and 12.5 m leaps
##   5 Hedge Trimmers   kill bricks: hop them, tap-jump under a red ceiling, zig-zag past hedges
##   6 The Mower        a sweeper you must hop while circling against its spin
##   7 Frost Chute      an ice slide that fires you across a ravine
##   8 The Great Leap   a 2 m-per-rung ladder up to the ring-gate launch pad (set piece), hard exit
##   9 Grand Circuit    hop + boost -> leap -> pad -> pad -> small landing -> finish
## The course is built stage by stage in a local frame (heading = local -Z) so it can turn.

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _mower: Sweeper
var _fan: Sweeper


func _configure() -> void:
	theme_id = "gardens"
	music_track = "a"
	kill_y = -40.0


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
	_stage_9_circuit()
	_surroundings()


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
	kit.arch(_w(Vector3(0, 0, -9.2)), 3.0, 4.0)
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
# carry the speed pad -> pad -> a 3.2 m disc, last jump to the finish lawn.
func _stage_9_circuit() -> void:
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
	kit.finish(_w(Vector3(0, 2.5, -94.5)), _yaw)
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
	r_walk(_w(Vector3(0, 2.5, -94.5)))


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
