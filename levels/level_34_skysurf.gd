extends LevelBase
## 34. SKY SURF - the second FLOW level (index 32 = `--level=32`). A pastel sunrise cloudscape:
## floating islands hung in a peach-and-lilac sky above a sea of cloud, kites and birds on the
## wind, and the sun just clearing the horizon dead ahead. You are running TOWARD the sunrise.
##
## Two ways through every stage, which part and rejoin at the checkpoint decks:
##   route 0, the SAFE line: friendly hops between wide islands, boardwalks and cloud ramps.
##     Landings 2 m and more, nothing timed, nothing that waits. Nine checkpoints.
##   route 1, the FLOW line: one long breath through the same sky on speed rings, boost gates,
##     wind-ribbon grind rails, cloud slopes and the half-pipe, launched over the gaps by arcs.
##     Missing a ring or a rail costs speed, never life: the safe islands lie under the line.
##
##  1 Dawn Pier          a pier out of the start isle and a handful of cloud hops (first ring chain)
##  2 Meadow Slide       a long grassy cloud slope down to the next isle
##  3 Ribbon Row         two wind-ribbon rails across a wide gap
##  4 Kite Valley        a launch arc and a chain of rings strung between the kites
##  5 Cloud Canyon      a half-pipe carved between two cloud walls
##  6 Cumulus Skim       a launch arc and rings over the cloud tops
##  7 Updraft Terraces   the climb back up through the cloud: terraces and puffs | a rising ribbon
##  8 Gale Run           boost gates, a slope and a rail along the ridge
##  9 Rainbow Bridge     a ring chain along the rainbow
## 10 Sunrise Surge      SET PIECE: pure flow into the sun
##
## Skysurf mechanics (own scripts): SkysurfPuff (a cloud puff that springs you up), SkysurfRibbon
## (streaming wind ribbons that dress the flow line and show where it goes), SkysurfFlock (a flock of
## birds that wheels round the course). Route variants for the bot: 0 = safe line, 1 = flow line.

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _finish_pos: Vector3 = Vector3.ZERO
var _min_y: float = 0.0
## Per stage: the world-space start and end checkpoint areas (for the flow line and the scenery).
var _stage_marks: Array[Dictionary] = []
## Every island and ramp built so far (world centre, rough radius), for the clearance check.
var _isles: Array[Dictionary] = []


func _configure() -> void:
	theme_id = "skysurf"
	music_track = "skysurf"
	kill_y = -160.0
	# 0 = the safe line, 1 = the flow line
	route_variants = 2


var _top_speed: float = 0.0
var _stage_top: float = 0.0


func _physics_process(dt: float) -> void:
	super(dt)
	if player != null and not finished:
		var s: float = Vector2(player.velocity.x, player.velocity.z).length()
		_stage_top = maxf(_stage_top, s)
		_top_speed = maxf(_top_speed, s)


func _on_checkpoint(cp: Checkpoint) -> void:
	if OS.has_environment("SKYSURF_DEBUG") and cp.index > current_checkpoint:
		print("skysurf checkpoint %d at t=%.1f: top speed since the last one %.1f m/s (overall %.1f)" % [cp.index, run_time, _stage_top, _top_speed])
		_stage_top = 0.0
	super(cp)


# ---- local-frame helpers --------------------------------------------------------------------

func _frame(origin: Vector3, yaw_deg: float) -> void:
	_o = origin
	_yaw = yaw_deg
	_b = Basis(Vector3.UP, deg_to_rad(yaw_deg))


func _w(l: Vector3) -> Vector3:
	return _o + _b * l


func _d(v: Vector3) -> Vector3:
	return _b * v


## Unit heading in the stage frame: 0 = straight ahead (-Z), positive turns left (-X).
func _dir(ang_deg: float) -> Vector3:
	var a: float = deg_to_rad(ang_deg)
	return Vector3(-sin(a), 0.0, -cos(a))


## The validator's max reach (m) for a plain running jump that lands `dy` higher (test_m's measure).
func _reach(dy: float) -> float:
	var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, _tuning.jump_velocity, -_tuning.max_speed), dy)
	return absf(land.z)


## How far the near edge of a landing lies from the takeoff spot when the jump needs `pct` of max
## reach by test_m's measure (to 0.4 m past the near edge, scanned in 0.2 m steps).
func _e(pct: float, dy: float) -> float:
	var m: float = pct * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	return float(k) * 0.2 - 0.03


# ---- shapes ---------------------------------------------------------------------------------
# A shape is {"c": local top centre, "r": radius} for a disc or {"c", "hx", "hz", "rot"} for a box
# (rot in degrees about Y, relative to the stage frame).

## Distance from a shape's centre to its outline along local direction `d`, less `inset`.
func _ext(s: Dictionary, d: Vector3, inset: float) -> float:
	if s.has("r"):
		return maxf(float(s["r"]) - inset, 0.05)
	var dl: Vector3 = Basis(Vector3.UP, -deg_to_rad(float(s.get("rot", 0.0)))) * d
	var tx: float = INF if absf(dl.x) < 0.0001 else (float(s["hx"]) - inset) / absf(dl.x)
	var tz: float = INF if absf(dl.z) < 0.0001 else (float(s["hz"]) - inset) / absf(dl.z)
	return maxf(minf(tx, tz), 0.05)


## The takeoff spot on `a`: on the way toward heading `d`, `inset` metres inside the outline.
func _edge(a: Dictionary, d: Vector3, inset: float = 0.35) -> Vector3:
	var c: Vector3 = a["c"]
	return c + d * _ext(a, d, inset)


## An island: a disc (radius r) or a box. Returns its shape.
func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.8, keel: float = -1.0) -> Dictionary:
	kit.disc(_w(c), r, thick, style, keel)
	_note(c, r)
	return {"c": c, "r": r}


func _box(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, keel: float = -1.0, rot: float = 0.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw + rot)
	_note(c, maxf(sx, sz) * 0.5)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5, "rot": rot}


func _note(c: Vector3, radius: float) -> void:
	_min_y = minf(_min_y, _w(c).y)
	_isles.append({"c": _w(c), "r": radius})


# ---- the safe line's building blocks ---------------------------------------------------------
# Items for _trace(): a hop to a disc (H) or a box (B), a boardwalk (S), a cloud ramp (C).

func _H(pct: float, dy: float, r: float = 1.7, style: String = "main") -> Dictionary:
	return {"t": "hop", "pct": pct, "dy": dy, "r": r, "style": style}


func _B(pct: float, dy: float, sx: float = 2.8, sz: float = 2.8, style: String = "main") -> Dictionary:
	return {"t": "hop", "pct": pct, "dy": dy, "sx": sx, "sz": sz, "style": style}


func _S(length: float, width: float = 3.0, style: String = "alt") -> Dictionary:
	return {"t": "span", "len": length, "w": width, "style": style}


## A cloud ramp climbing (or, with a negative dy, descending) `dy` over `length` metres, then a flat
## landing 3 m long.
func _C(length: float, dy: float, width: float = 3.4, style: String = "alt") -> Dictionary:
	return {"t": "climb", "len": length, "dy": dy, "w": width, "style": style}


## The checkpoint deck: one hop onto a big round "goal" island.
func _K(pct: float, dy: float, r: float = 6.0) -> Dictionary:
	return {"t": "cp", "pct": pct, "dy": dy, "r": r}


func _hop(a: Dictionary, ang: float, pct: float, dy: float, shape: Dictionary, style: String, thick: float = 0.8, keel: float = -1.0) -> Dictionary:
	var d: Vector3 = _dir(ang)
	var t: Vector3 = _edge(a, d)
	var s: float = _ext(shape, d, 0.0)
	var c: Vector3 = t + d * (_e(pct, dy) + s)
	c.y = (a["c"] as Vector3).y + dy
	var out: Dictionary
	if shape.has("r"):
		out = _disc(c, float(shape["r"]), style, thick, keel)
	else:
		out = _box(c, float(shape["hx"]) * 2.0, float(shape["hz"]) * 2.0, style, thick, keel, float(shape.get("rot", 0.0)))
	r_jump(_w(t), _w(c), true)
	return out


func _span(a: Dictionary, ang: float, length: float, width: float, style: String = "alt") -> Dictionary:
	var d: Vector3 = _dir(ang)
	var c0: Vector3 = a["c"]
	var p0: Vector3 = c0 + d * (_ext(a, d, 0.0) - 0.3)
	var c: Vector3 = p0 + d * (length * 0.5)
	c.y = c0.y - 0.02
	var out: Dictionary = _box(c, width, length, style, 0.6, 0.0, ang)
	out["c"] = c + Vector3(0, 0.02, 0)
	r_walk(_w(p0 + d * (length - 0.5)))
	return out


func _climb(a: Dictionary, ang: float, length: float, dy: float, width: float, style: String) -> Dictionary:
	var d: Vector3 = _dir(ang)
	var c0: Vector3 = a["c"]
	var p0: Vector3 = c0 + d * (_ext(a, d, 0.0) - 0.15)
	var run: float = length
	var sl: float = sqrt(run * run + dy * dy)
	var mid: Vector3 = p0 + d * (run * 0.5) + Vector3(0, dy * 0.5, 0)
	kit.ramp(_w(mid), Vector3(width, 0.7, sl), rad_to_deg(atan2(dy, run)), _yaw + ang, style)
	_note(mid, sl * 0.5)
	var end: Vector3 = p0 + d * run
	end.y = c0.y + dy
	var landing_c: Vector3 = end + d * 1.5
	var landing: Dictionary = _box(landing_c + Vector3(0, -0.02, 0), width, 3.0, style, 0.6, 0.0, ang)
	landing["c"] = landing_c
	r_walk(_w(Vector3(p0.x, c0.y, p0.z) + d * 1.0))
	r_walk(_w(landing_c))
	return landing


## Trace a winding safe line from `a`: boardwalks and hops that bow out to `side` (+1 = right) by up to
## `amp` metres over a chord of `chord` metres, finishing with the checkpoint deck. Returns that deck.
func _trace(a: Dictionary, chord: float, side: float, amp: float, items: Array) -> Dictionary:
	var cur: Dictionary = a
	var p0: float = -(a["c"] as Vector3).z
	var n_items: int = items.size()
	for ii: int in n_items:
		var it: Dictionary = items[ii]
		var c: Vector3 = cur["c"]
		var adv: float = 9.0
		match str(it["t"]):
			"span", "climb":
				adv = float(it["len"])
		var p: float = -c.z - p0
		var xt: float = side * amp * pow(sin(PI * clampf((p + adv) / chord, 0.0, 1.0)), 0.5)
		var ang: float = clampf(rad_to_deg(atan2(-(xt - c.x), adv)), -55.0, 55.0)
		# leave the start deck sideways, out of the flow line's way, and come back in sideways
		if ii == 0:
			ang = -side * 55.0
		elif ii == n_items - 1:
			ang = side * 40.0
		var style: String = str(it.get("style", "main"))
		match str(it["t"]):
			"hop":
				var shape: Dictionary = {"r": it["r"]} if it.has("r") else {"hx": float(it["sx"]) * 0.5, "hz": float(it["sz"]) * 0.5, "rot": 0.0}
				cur = _hop(cur, ang, float(it["pct"]), float(it["dy"]), shape, style)
			"span":
				cur = _span(cur, ang, float(it["len"]), float(it["w"]), style)
			"climb":
				cur = _climb(cur, ang, float(it["len"]), float(it["dy"]), float(it["w"]), style)
			"cp":
				cur = _hop(cur, ang, float(it["pct"]), float(it["dy"]), {"r": it["r"]}, "goal", 1.0, 7.0)
	return cur


## Make `deck` the stage's checkpoint (facing the next stage) and close the safe route with it.
func _checkpoint_at(deck: Dictionary) -> void:
	kit.checkpoint(_w(deck["c"]), _next_yaw)
	_cp_world.append(_w(deck["c"]))


# ---- the flow line ----------------------------------------------------------------------------
# Every stage's flow line runs straight from the start checkpoint deck A to the end deck B. The
# planner below builds the common figure - boost gates on the deck, a flow slope, a launch arc, a
# chain of rings along the flight, a landing deck flush with B - and solves the slope's length and
# pitch so that the flight comes down 13-26 m short of B at B's height.

func _yaw_of(u: Vector3) -> float:
	return rad_to_deg(atan2(-u.x, -u.z))


## The speed a rider entering a flow slope at `v0` has after `dist` m of grade `pitch_deg`
## (FlowSurface.speed_after's rule: gain 0.55, cap 30).
func _slope_speed(v0: float, dist: float, pitch_deg: float) -> float:
	var a: float = _tuning.gravity_fall * sin(deg_to_rad(pitch_deg)) * 0.55
	var v: float = v0
	var done: float = 0.0
	while done < dist:
		if v < 30.0:
			v = minf(v + a / 60.0, maxf(30.0, v0))
		done += v / 60.0
	return v


## A launch at `hs` from `lip` heading `u`: the flight (the Player's air rules, rings adding speed at
## the given times) down to height `land_y`. Returns {"rings", "landing", "time"}.
func _sim_flight(lip: Vector3, u: Vector3, hs_in: float, ap: float, land_y: float, times: Array[float], add: float) -> Dictionary:
	var hs: float = clampf(hs_in, 8.0, 30.0)
	var vy: float = clampf(hs * tan(deg_to_rad(ap)), 3.0, 18.0)
	var v: Vector3 = u * hs + Vector3(0, vy, 0)
	var p: Vector3 = lip
	var rings: Array[Vector3] = []
	var clock: float = 0.0
	var k: int = 0
	while clock < 6.0:
		var g: float = _tuning.gravity_rise if v.y > 0.0 else _tuning.gravity_fall
		v.y = maxf(v.y - g / 60.0, -_tuning.max_fall_speed)
		var h: float = Vector2(v.x, v.z).length()
		if h > _tuning.max_speed:
			var nh0: float = move_toward(h, _tuning.max_speed, _tuning.air_overspeed_drag / 60.0)
			v.x *= nh0 / h
			v.z *= nh0 / h
		p += v / 60.0
		clock += 1.0 / 60.0
		if k < times.size() and clock >= times[k]:
			rings.append(p + Vector3(0, 0.9, 0))
			var h2: float = maxf(Vector2(v.x, v.z).length(), 0.01)
			var nh: float = minf(h2 + add * FlowChain.bonus(k + 1), maxf(30.0, h2))
			v.x *= nh / h2
			v.z *= nh / h2
			k += 1
		if clock > 0.3 and v.y < 0.0 and p.y <= land_y:
			break
	return {"rings": rings, "landing": p, "time": clock}


## Plan, build and return the standard flow figure between decks A and B (world top-centres of two
## round checkpoint decks, radius 6). opts: rings (count), ring_add, pitch (launch ramp, deg),
## deck (landing deck width), slope_w, v0.
func _flow_arc(a: Vector3, b: Vector3, opts: Dictionary = {}) -> Dictionary:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist: float = flat.length()
	var u: Vector3 = flat / maxf(dist, 0.01)
	var ap: float = float(opts.get("pitch", 24.0))
	var ring_n: int = int(opts.get("rings", 6))
	var ring_add: float = float(opts.get("ring_add", 4.0))
	var v0: float = float(opts.get("v0", 24.0))
	var slope_w: float = float(opts.get("slope_w", 9.0))
	var deck_w: float = float(opts.get("deck", 10.0))
	var arc_len: float = 9.0
	var best: Dictionary = {}
	var best_cost: float = INF
	for pi: int in range(14, 27):
		var pitch: float = float(pi) * 0.5
		for sl: int in range(0, 91):
			if sl == 0 and pi != 20:
				continue
			var len: float = float(sl)
			var run: float = len * cos(deg_to_rad(pitch))
			var foot_s: float = 6.0 + run
			var foot_y: float = a.y - len * sin(deg_to_rad(pitch))
			if foot_y < b.y - 0.5:
				continue
			var hs: float = _slope_speed(v0, len, pitch) if sl > 0 else v0
			var lip: Vector3 = a + u * (foot_s + arc_len * cos(deg_to_rad(ap)))
			lip.y = foot_y + arc_len * sin(deg_to_rad(ap))
			var f1: Dictionary = _sim_flight(lip, u, hs, ap, b.y, [] as Array[float], 0.0)
			var times: Array[float] = []
			for i: int in ring_n:
				times.append(float(f1["time"]) * (0.12 + 0.76 * float(i) / float(maxi(ring_n - 1, 1))))
			var f2: Dictionary = _sim_flight(lip, u, hs, ap, b.y, times, ring_add)
			var s_land: float = ((f2["landing"] as Vector3) - a).dot(u)
			var cost: float = absf(pitch - 10.0) * 2.0 + (16.0 - len) * 0.7 * float(len < 16.0) + absf(s_land - (dist - 19.0)) * 0.1
			if s_land < dist - 26.0 or s_land > dist - 13.0:
				cost += 1000.0 + absf(s_land - (dist - 19.0)) * 10.0
			if cost < best_cost:
				best_cost = cost
				best = {"len": len, "pitch": pitch, "foot_s": foot_s, "foot_y": foot_y, "lip": lip, "rings": f2["rings"], "landing": f2["landing"], "hs": hs}
	if best_cost >= 1000.0:
		push_warning("skysurf: no clean flow figure for a %.1f m stage (best miss cost %.1f)" % [dist, best_cost])
	var yaw: float = _yaw_of(u)
	# the deck: gates, then the slope (if any), then the ramp
	var g1: Vector3 = a + u * 1.6
	var g2: Vector3 = a + u * 4.4
	var gate_pts: Array[Vector3] = [g1, g2]
	kit.boost_chain(gate_pts, 20.0, 5.0, {"speed_end": 24.0})
	var top: Vector3 = a + u * 6.0
	var foot: Vector3 = a + u * float(best["foot_s"])
	foot.y = float(best["foot_y"])
	var slope: FlowSurface = null
	var pts1: Array[Vector3] = [a + u * 0.8, g1, g2]
	if float(best["len"]) > 1.0:
		slope = kit.flow_slope_between(top, foot, slope_w)
		pts1.append(top)
		var pre: Vector3 = foot - u * 2.0
		pre.y = float(best["foot_y"]) + 2.0 * tan(deg_to_rad(float(best["pitch"])))
		pts1.append(pre)
	var arc: LaunchArc = kit.launch_arc(foot, yaw, ap, 6.0, arc_len)
	var ring_pts: Array[Vector3] = []
	for r: Vector3 in (best["rings"] as Array[Vector3]):
		ring_pts.append(r)
	var rings: Array[SpeedRing] = []
	if ring_pts.size() >= 2:
		rings = kit.ring_line(ring_pts, {"add_speed": ring_add, "radius": 2.4})
	# the landing deck, flush with B's deck
	var land: Vector3 = best["landing"]
	var s_land2: float = (land - a).dot(u)
	var s_d0: float = s_land2 - 6.0
	var s_d1: float = dist - 3.0
	var dc: Vector3 = a + u * ((s_d0 + s_d1) * 0.5)
	dc.y = b.y - 0.02
	kit.plat(dc, Vector3(deck_w, 1.4, s_d1 - s_d0), "alt", 3.5, yaw)
	_min_y = minf(_min_y, b.y - 3.0)
	if OS.has_environment("SKYSURF_DEBUG"):
		_report_clearance(a, u, dist, float(best["foot_s"]), float(best["len"]))
	var steps: Array[Dictionary] = []
	steps.append({"kind": "f_line", "pts": pts1, "tol": 2.0})
	var to: Vector3 = land + u * 2.0
	to.y = b.y
	steps.append({"kind": "f_launch", "arc": arc, "to": to})
	var out_pts: Array[Vector3] = [Vector3(land.x, b.y, land.z) + u * 5.0, b]
	steps.append({"kind": "f_line", "pts": out_pts, "tol": 2.0})
	return {"steps": steps, "arc": arc, "slope": slope, "rings": rings, "u": u, "yaw": yaw, "best": best, "dist": dist}


## Debug: islands that crowd the flow corridor of the stage from `a` along `u` (`dist` long).
func _report_clearance(a: Vector3, u: Vector3, dist: float, foot_s: float, slope_len: float) -> void:
	var worst: float = INF
	for isl: Dictionary in _isles:
		var c: Vector3 = isl["c"]
		var rel := Vector3(c.x - a.x, 0.0, c.z - a.z)
		var s: float = rel.dot(u)
		if s < 3.0 or s > dist - 3.0:
			continue
		var lat: float = absf(rel.x * u.z - rel.z * u.x)
		var gap: float = lat - float(isl["r"]) - 6.0
		if gap < 1.0 and absf(c.y - a.y) < 30.0:
			print("   skysurf clearance: island at s=%.0f lateral %.1f r=%.1f gap %.1f (y %.1f)" % [s, lat, float(isl["r"]), gap, c.y])
		worst = minf(worst, gap)
	print("   flow figure: dist %.0f slope %.0f m from s=6 to %.0f, worst island gap %.1f" % [dist, slope_len, foot_s, worst])


## Close a stage: with the flow route selected the safe steps from `s0` are replaced by the flow steps.
func _use_flow(s0: int, plan: Dictionary) -> void:
	if route_variant != 1:
		return
	route.resize(s0)
	for s: Dictionary in (plan["steps"] as Array[Dictionary]):
		route.append(s)


# ---- the course -----------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	set_spawn(Vector3(0, 0.1, 0), 0.0)
	var yaws: Array[float] = [0.0, -8.0, 7.0, -6.0, 9.0, 0.0, -10.0, 5.0, -7.0, 6.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10]
	var dev_last: int = DEV_LAST if not OS.has_environment("SKYSURF_LAST") else int(OS.get_environment("SKYSURF_LAST"))
	var last: int = stages.size() if dev_last <= 0 else mini(dev_last, stages.size())
	_frame(Vector3.ZERO, yaws[0])
	for i: int in last:
		_next_yaw = yaws[i + 1]
		var first_step: int = route.size()
		var end: Vector3 = stages[i].call()
		if OS.has_environment("SKYSURF_DEBUG"):
			print("skysurf stage %d: steps %d..%d, end %s (world %s)" % [i + 1, first_step, route.size() - 1, str(end), str(_w(end))])
			for k: int in range(first_step, route.size()):
				var s: Dictionary = route[k]
				if str(s["kind"]) == "jump":
					print("   step %d jump %s -> %s" % [k, str(s["from"]), str(s["to"])])
				elif str(s["kind"]) == "walk":
					print("   step %d walk -> %s" % [k, str(s["to"])])
		_frame(_w(end), yaws[i + 1])
	if last < stages.size():
		# (dev) the finish gate right after the last stage built
		var fin: Dictionary = _hop({"c": Vector3.ZERO, "r": 6.0}, 0.0, 0.70, 0.0, {"r": 4.0}, "goal", 1.0, 5.0)
		kit.finish(_w(fin["c"]), _yaw)
		_finish_pos = _w(fin["c"])
		r_walk(_w(fin["c"]))
	kill_y = _min_y - 90.0


## The very first isle, with the player on it. A shape; the spawn is at its centre.
func _start_isle() -> Dictionary:
	return _disc(Vector3.ZERO, 7.0, "main", 1.2, 8.0)


# ---- stage 1: Dawn Pier -----------------------------------------------------------------------

func _stage_1() -> Vector3:
	var a: Dictionary = _start_isle()
	var items: Array = [_S(10.0, 3.4), _H(0.64, -0.5, 1.8), _B(0.68, -0.5, 2.8, 2.8), _H(0.70, -0.5, 1.6, "accent"),
		_S(8.0, 3.0), _B(0.72, -0.4, 2.6, 3.2), _H(0.70, -0.4, 1.7), _S(12.0, 3.2), _H(0.68, -0.3, 1.8),
		_B(0.72, -0.3, 3.0, 3.0), _K(0.72, -0.4)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 82.0, 1.0, 15.0, items)
	_checkpoint_at(cp)
	_use_flow(s0, _flow_arc(_o, _w(cp["c"]), {"rings": 5}))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Meadow Slide --------------------------------------------------------------------

func _stage_2() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(8.0, 3.2), _H(0.70, -1.5, 1.7), _B(0.70, -1.5, 3.0, 3.0), _H(0.72, -1.5, 1.6, "accent"),
		_S(10.0, 3.0), _H(0.70, -1.5, 1.8), _B(0.72, -1.5, 2.8, 3.4), _S(10.0, 3.2), _H(0.70, -1.5, 1.7),
		_B(0.72, -1.5, 3.0, 3.0), _H(0.70, -1.0, 1.8), _K(0.72, -1.0)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 88.0, -1.0, 15.0, items)
	_checkpoint_at(cp)
	_use_flow(s0, _flow_arc(_o, _w(cp["c"]), {"rings": 4, "slope_w": 10.0}))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Ribbon Row ----------------------------------------------------------------------

func _stage_3() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(12.0, 3.0), _H(0.72, -0.8, 1.8), _H(0.72, -0.8, 1.6, "accent"), _B(0.74, -0.8, 2.6, 2.6),
		_S(16.0, 3.0), _H(0.70, -0.6, 1.7), _B(0.72, -0.6, 3.0, 3.0), _S(8.0, 3.2), _H(0.72, -0.6, 1.8),
		_H(0.72, -0.6, 1.6), _B(0.72, -0.6, 3.0, 3.0), _K(0.72, -0.6)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 90.0, 1.0, 15.0, items)
	_checkpoint_at(cp)
	# RAIL SPOT: the two wind-ribbon rails go here once the kit's rails land; until then a ring flight
	_use_flow(s0, _flow_arc(_o, _w(cp["c"]), {"rings": 5}))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Kite Valley ---------------------------------------------------------------------

func _stage_4() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(14.0, 3.2), _H(0.70, -0.4, 1.8), _B(0.72, -0.4, 2.8, 2.8, "accent"), _H(0.70, -0.4, 1.7),
		_S(10.0, 3.0), _B(0.72, -0.4, 3.2, 3.2), _H(0.74, -0.4, 1.6), _S(10.0, 3.0), _H(0.70, -0.4, 1.8),
		_B(0.72, -0.4, 2.8, 3.4), _H(0.70, -0.4, 1.8), _K(0.72, -0.4)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 88.0, -1.0, 15.0, items)
	_checkpoint_at(cp)
	_use_flow(s0, _flow_arc(_o, _w(cp["c"]), {"rings": 7, "ring_add": 3.0}))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Cloud Canyon --------------------------------------------------------------------

func _stage_5() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(10.0, 3.0), _H(0.70, -1.2, 1.8), _B(0.70, -1.2, 3.0, 3.0), _H(0.72, -1.2, 1.7, "accent"),
		_S(12.0, 3.2), _H(0.70, -1.2, 1.8), _B(0.72, -1.2, 3.0, 3.0), _S(10.0, 3.0), _H(0.70, -1.2, 1.8),
		_H(0.72, -1.2, 1.6), _K(0.72, -1.0)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 90.0, 1.0, 15.0, items)
	_checkpoint_at(cp)
	# HALF-PIPE SPOT: the carved half-pipe goes here once slice 2 lands; until then slope and ring flight
	_use_flow(s0, _flow_arc(_o, _w(cp["c"]), {"rings": 6, "slope_w": 12.0}))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Cumulus Skim --------------------------------------------------------------------

func _stage_6() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_H(0.68, -0.8, 2.2, "alt"), _H(0.72, -0.8, 2.0), _B(0.70, -0.8, 3.6, 3.2, "alt"), _H(0.74, -0.8, 1.8),
		_H(0.72, -0.8, 2.2, "alt"), _B(0.72, -0.8, 3.0, 3.0), _H(0.70, -0.8, 2.0), _H(0.72, -0.8, 1.8, "accent"),
		_B(0.72, -0.8, 3.4, 3.4, "alt"), _H(0.70, -0.8, 2.0), _K(0.72, -0.8)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 90.0, -1.0, 15.0, items)
	_checkpoint_at(cp)
	_use_flow(s0, _flow_arc(_o, _w(cp["c"]), {"rings": 6}))
	r_checkpoint()
	return cp["c"]


# ---- stage 7: Updraft Terraces ----------------------------------------------------------------

func _stage_7() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(6.0, 3.2), _C(26.0, 4.5, 3.4), _H(0.70, 0.6, 1.9), _B(0.70, 0.6, 3.0, 3.0), _S(6.0, 3.2),
		_C(26.0, 4.5, 3.4), _H(0.70, 0.6, 1.9), _B(0.72, 0.6, 3.0, 3.0), _K(0.74, 0.4)]
	var cp: Dictionary = _trace(a, 90.0, 1.0, 10.0, items)
	_checkpoint_at(cp)
	r_checkpoint()
	return cp["c"]


# ---- stage 8: Gale Run ------------------------------------------------------------------------

func _stage_8() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(12.0, 3.2), _H(0.70, -0.5, 1.8), _B(0.72, -0.5, 3.0, 3.0), _S(10.0, 3.0), _H(0.72, -0.5, 1.7, "accent"),
		_B(0.72, -0.5, 2.8, 3.2), _H(0.70, -0.5, 1.8), _S(10.0, 3.0), _H(0.72, -0.5, 1.7), _B(0.72, -0.5, 3.0, 3.0), _K(0.72, -0.5)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 90.0, -1.0, 15.0, items)
	_checkpoint_at(cp)
	# RAIL SPOT: the ridge rail goes here once the kit's rails land; until then a ring flight
	_use_flow(s0, _flow_arc(_o, _w(cp["c"]), {"rings": 6}))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Rainbow Bridge ------------------------------------------------------------------

func _stage_9() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(14.0, 3.4, "accent"), _H(0.70, -0.6, 1.8), _B(0.70, -0.6, 3.0, 3.0), _S(18.0, 3.2, "accent"),
		_H(0.72, -0.6, 1.8), _B(0.72, -0.6, 3.0, 3.0), _S(12.0, 3.0), _H(0.70, -0.6, 1.8), _B(0.70, -0.6, 3.0, 3.0),
		_H(0.72, -0.6, 1.7), _K(0.72, -0.6)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 92.0, 1.0, 15.0, items)
	_checkpoint_at(cp)
	_use_flow(s0, _flow_arc(_o, _w(cp["c"]), {"rings": 8, "ring_add": 3.0, "pitch": 28.0}))
	r_checkpoint()
	return cp["c"]


# ---- stage 10: Sunrise Surge (the finale) -----------------------------------------------------

func _stage_10() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(10.0, 3.4), _C(30.0, -4.5, 3.6), _H(0.70, -0.5, 1.9), _B(0.72, -0.5, 3.0, 3.0), _S(10.0, 3.2),
		_C(30.0, -4.5, 3.6), _H(0.70, -0.5, 1.9), _B(0.72, -0.5, 3.2, 3.2), {"t": "cp", "pct": 0.72, "dy": -0.4, "r": 7.0}]
	var fin: Dictionary = _trace(a, 100.0, -1.0, 10.0, items)
	kit.finish(_w(fin["c"]), _yaw)
	_finish_pos = _w(fin["c"])
	r_walk(_w(fin["c"]))
	return fin["c"]
