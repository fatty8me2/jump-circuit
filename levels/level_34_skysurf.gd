extends LevelBase
## 34. SKY SURF - the second FLOW level (index 32 = `--level=32`). A pastel sunrise cloudscape:
## floating islands hung in a peach-and-lilac sky above a sea of cloud, kites and birds on the
## wind, and the sun just clearing the horizon dead ahead. You are running TOWARD the sunrise.
##
## Two ways through every stage, which part and rejoin at the checkpoint decks (the flow line runs
## straight between two decks; the safe line bows out to one side of it and comes in from the side):
##   route 0, the SAFE line: friendly hops between wide islands, boardwalks and cloud ramps.
##     Landings 2 m and more, nothing timed, nothing that waits. Nine checkpoints.
##   route 1, the FLOW line: one long breath through the same sky on speed rings, boost gates,
##     wind-ribbon grind rails, a cloud slide and a half-pipe, launched over the gaps by arcs.
##     Missing a ring costs speed, a missed rail drops you onto a boardwalk under it.
##   Every stage starts with a run-out deck after the checkpoint and a gate chain to get going again.
##
##  1 Dawn Pier          gates, a launch arc and a first chain of five rings | a pier and cloud hops
##  2 Meadow Slide       a long grassy slide strung with six rings | steps down beside it
##  3 Ribbon Row         two wind-ribbon rails caught one off the other | boardwalks and hops
##  4 Kite Valley        a launch arc and seven rings strung between the kites | hops through the kites
##  5 Cloud Canyon       a half-pipe carved wall to wall | boardwalks along the rim
##  6 Cumulus Skim       a launch arc and six rings over the cloud tops | hops between cumulus
##  7 Updraft Terraces   two rails climbing back up through the cloud | a cloud ramp and two cloud PUFFS
##  8 Gale Run           gates and one long swinging ridge rail | boardwalks along the ridge
##  9 Rainbow Bridge     a high launch and a chain of eight rings under the rainbow | the rainbow's boardwalks
## 10 Sunrise Surge      SET PIECE, pure flow: two rails up to a floating isle, then a ten-ring flight into the sun
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
## Which side of the next stage's chord its safe line leaves to (+1 right, -1 left).
var _next_side: float = 1.0
var _tuning: MovementTuning
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _finish_pos: Vector3 = Vector3.ZERO
var _min_y: float = 0.0
## Per stage: the world-space start and end checkpoint areas (for the flow line and the scenery).
var _stage_marks: Array[Dictionary] = []
## Every island and ramp built so far (world centre, rough radius), for the clearance check.
var _isles: Array[Dictionary] = []
var deco: SkysurfDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _cp_bursts: Dictionary = {}
## The flow lines' decorative trails: {"pts": PackedVector3Array, "air": bool, "rail": bool}.
var _flow_paths: Array[Dictionary] = []
## Chord end points in build order (start, every checkpoint, the mid isle, the finish) for the scenery.
var _mid_world: Vector3 = Vector3.INF


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


func fail(cause: String = "fall") -> void:
	if OS.has_environment("SKYSURF_DEBUG") and player != null:
		print("skysurf fail (%s) at %s speed %.1f t=%.1f" % [cause, str(player.global_position.snapped(Vector3.ONE * 0.1)), player.velocity.length(), run_time])
	super(cause)


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
## A cloud puff on the island you stand on throws you up onto a new round island `dy` higher.
func _P(dy: float, r: float = 2.4, strength: float = 20.0, pitch: float = 28.0) -> Dictionary:
	return {"t": "puff", "dy": dy, "r": r, "s": strength, "p": pitch}


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


## A SkysurfPuff at the middle of `a` flings you along heading `ang` onto a new disc `dy` higher.
func _puff_hop(a: Dictionary, ang: float, dy: float, r: float, strength: float, pitch: float) -> Dictionary:
	var c: Vector3 = a["c"]
	var puff := SkysurfPuff.new()
	puff.strength = strength
	puff.pitch_deg = pitch
	puff.radius = 1.2
	puff.rotation_degrees.y = _yaw + ang
	puff.position = _w(c)
	add_child(puff)
	var v: Vector3 = Basis(Vector3.UP, deg_to_rad(ang)) * (Vector3(0, cos(deg_to_rad(pitch)), -sin(deg_to_rad(pitch))) * strength)
	var land: Vector3 = Ballistics.landing_point(_tuning, c + Vector3(0, 0.1, 0), v, c.y + dy)
	var out: Dictionary = _disc(Vector3(land.x, c.y + dy, land.z), r, "main")
	r_pad(_w(c), _w(out["c"]))
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
	var prev_ang: float = 0.0
	var prev_t: String = ""
	for ii: int in n_items:
		var it: Dictionary = items[ii]
		var c: Vector3 = cur["c"]
		var adv: float = 9.0
		match str(it["t"]):
			"span", "climb":
				adv = float(it["len"])
		var p: float = -c.z - p0
		# bow out to `amp` early and hold it until the final approach, which comes in from the side
		var xt: float = side * amp * pow(sin(PI * clampf((p + adv) / chord, 0.0, 0.5)), 0.5)
		var ang: float = clampf(rad_to_deg(atan2(-(xt - c.x), adv)), -55.0, 55.0)
		# the path turns gradually: a hop that follows a boardwalk leaves along it
		var max_turn: float = 8.0 if (prev_t == "span" or prev_t == "climb") else 30.0
		if ii == 0:
			# leave the start deck sideways, out of the flow line's way
			ang = -side * 55.0
		else:
			var raw: float = ang
			if ii >= n_items - 3:
				raw = side * [25.0, 55.0, 85.0][ii - (n_items - 3)]
			ang = prev_ang + clampf(raw - prev_ang, -max_turn, max_turn)
		prev_ang = ang
		prev_t = str(it["t"])
		var style: String = str(it.get("style", "main"))
		match str(it["t"]):
			"hop":
				var shape: Dictionary = {"r": it["r"]} if it.has("r") else {"hx": float(it["sx"]) * 0.5, "hz": float(it["sz"]) * 0.5, "rot": 0.0}
				cur = _hop(cur, ang, float(it["pct"]), float(it["dy"]), shape, style)
			"span":
				cur = _span(cur, ang, float(it["len"]), float(it["w"]), style)
			"climb":
				cur = _climb(cur, ang, float(it["len"]), float(it["dy"]), float(it["w"]), style)
			"puff":
				cur = _puff_hop(cur, ang, float(it["dy"]), float(it["r"]), float(it["s"]), float(it["p"]))
			"cp":
				cur = _hop(cur, ang, float(it["pct"]), float(it["dy"]), {"r": it["r"]}, str(it.get("style", "goal")), 1.0, 7.0)
				# we came in from the side: step to the middle of the deck before the next stage's walk
				r_walk(_w(cur["c"]))
	return cur


## Make `deck` the stage's checkpoint (facing the next stage) and close the safe route with it.
func _checkpoint_at(deck: Dictionary) -> void:
	# face a little toward the side the next safe line departs to (the flow line is still straight ahead)
	var cp: Checkpoint = kit.checkpoint(_w(deck["c"]), _next_yaw - _next_side * 22.0)
	_cp_world.append(_w(deck["c"]))
	var fx: Array[GPUParticles3D] = SkysurfFx.cp_burst(deco.palette(_cp_world.size() + 1))
	for pt: GPUParticles3D in fx:
		pt.position = _w(deck["c"]) + Vector3(0, 0.6, 0)
		add_child(pt)
	_cp_bursts[cp] = fx
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for pt2: GPUParticles3D in (_cp_bursts[which] as Array):
				pt2.restart()
				pt2.emitting = true)


# ---- the flow line ----------------------------------------------------------------------------
# Every stage's flow line runs straight from the start checkpoint deck A to the end deck B. The
# planner below builds the common figure - boost gates on the deck, a flow slope, a launch arc, a
# chain of rings along the flight, a landing deck flush with B - and solves the slope's length and
# pitch so that the flight comes down 13-26 m short of B at B's height.

## Metres from a checkpoint deck's centre to where the flow figure proper begins: room to stand, to get
## going again (the gates sit on this stretch) and for a stopped rider to start from.
const RUNOUT: float = 20.0


func yaw0(u: Vector3) -> float:
	return _yaw_of(u)


## The run-out deck between a checkpoint disc and the first slope / ramp / pipe, flush with the disc.
func _runout_deck(a: Vector3, u: Vector3, yaw: float, width: float) -> void:
	var c: Vector3 = a + u * ((5.5 + RUNOUT) * 0.5)
	c.y = a.y - 0.02
	kit.plat(c, Vector3(width, 1.0, RUNOUT - 5.5), "alt", 2.5, yaw)


func _trail(pts: Array[Vector3], lift: float, air: bool) -> void:
	var pv := PackedVector3Array()
	for q: Vector3 in pts:
		pv.append(q + Vector3(0, lift, 0))
	_flow_paths.append({"pts": pv, "air": air, "rail": false})


func _trail_rail(r: GrindRail) -> void:
	if r == null:
		return
	var pv := PackedVector3Array()
	var n: int = maxi(int(r.length() / 3.0), 2)
	for i: int in n + 1:
		pv.append(r.point_at(r.length() * float(i) / float(n)))
	_flow_paths.append({"pts": pv, "air": false, "rail": true})


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
			var foot_s: float = RUNOUT + run
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
	var g1: Vector3 = a + u * 9.0
	var g2: Vector3 = a + u * 14.0
	_runout_deck(a, u, yaw0(u), 9.0)
	var gate_pts: Array[Vector3] = [g1, g2]
	kit.boost_chain(gate_pts, 20.0, 3.2, {"speed_end": 24.0})
	var top: Vector3 = a + u * RUNOUT
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
	var s_d0: float = maxf(s_land2 - 14.0, float(best["foot_s"]) + 14.0)
	var s_d1: float = dist - 3.0
	var dc: Vector3 = a + u * ((s_d0 + s_d1) * 0.5)
	dc.y = b.y - 0.02
	kit.plat(dc, Vector3(deck_w, 1.4, s_d1 - s_d0), "alt", 3.5, yaw)
	_min_y = minf(_min_y, b.y - 3.0)
	if OS.has_environment("SKYSURF_DEBUG"):
		_report_clearance(a, u, dist, float(best["foot_s"]), float(best["len"]))
	_trail(pts1, 0.7, false)
	_trail(ring_pts, 0.0, true)
	var steps: Array[Dictionary] = []
	steps.append({"kind": "f_line", "pts": pts1, "tol": 2.0})
	var to: Vector3 = land + u * 2.0
	to.y = b.y
	steps.append({"kind": "f_launch", "arc": arc, "to": to})
	var out_pts: Array[Vector3] = [Vector3(land.x, b.y, land.z) + u * 5.0, b]
	steps.append({"kind": "f_line", "pts": out_pts, "tol": 2.0})
	return {"steps": steps, "arc": arc, "slope": slope, "rings": rings, "u": u, "yaw": yaw, "best": best, "dist": dist}


## A flow line of wind-ribbon grind rails between decks A and B: gates on the deck, a run-out deck, a hop
## onto the first rail, (optionally) a second rail caught in the air off the first, and a landing deck
## flush with B. The rails swing side to side (`swing` m) and run from 1.4 m over A's height to 1.4 m over
## B's, so a rising stage (b above a) is a climbing ribbon. opts: two (bool), swing, deck, ext.
func _flow_rails(a: Vector3, b: Vector3, opts: Dictionary = {}) -> Dictionary:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist: float = flat.length()
	var u: Vector3 = flat / maxf(dist, 0.01)
	var side: Vector3 = u.cross(Vector3.UP)
	var yaw: float = _yaw_of(u)
	var swing: float = float(opts.get("swing", 4.0))
	var two: bool = bool(opts.get("two", true))
	var deck_w: float = float(opts.get("deck", 11.0))
	var s0: float = 20.0
	var s_end: float = dist - 26.0
	var y0: float = a.y + 1.4
	var y1: float = b.y + 1.4
	# gates on the deck, then the run-out deck under the first stretch of rail
	var gate_s: Array[float] = [8.0, 10.5, 13.0]
	var gate_pts: Array[Vector3] = []
	for s: float in gate_s:
		gate_pts.append(a + u * s)
	kit.boost_chain(gate_pts, 20.0, 3.2, {"speed_end": 26.0})
	var ext_c: Vector3 = a + u * 19.0
	ext_c.y = a.y - 0.02
	kit.plat(ext_c, Vector3(deck_w - 2.0, 1.0, 27.0), "alt", 3.0, yaw)
	var s_mid: float = lerpf(s0, s_end, 0.56) if two else s_end
	var n1: int = 4
	var r1: Array[Vector3] = []
	for k: int in n1:
		var s: float = lerpf(s0, s_mid, float(k) / float(n1 - 1))
		var t: float = (s - s0) / (s_end - s0)
		var p: Vector3 = a + u * s + side * (swing * sin(TAU * t) * sin(PI * t))
		p.y = lerpf(y0, y1, t)
		r1.append(p)
	var rail1: GrindRail = kit.rail(r1, {"post_to_y": minf(a.y, b.y) - 12.0})
	var rail2: GrindRail = null
	var r2: Array[Vector3] = []
	if two:
		var tan1: Vector3 = (r1[n1 - 1] - r1[n1 - 2])
		tan1.y = 0.0
		tan1 = tan1.normalized()
		var p2: Vector3 = r1[n1 - 1] + tan1 * 4.5
		p2.y = r1[n1 - 1].y - 1.7
		r2.append(p2)
		var n2: int = 3
		for k: int in range(1, n2 + 1):
			var s: float = lerpf((p2 - a).dot(u), s_end, float(k) / float(n2))
			var t: float = (s - s0) / (s_end - s0)
			var p: Vector3 = a + u * s + side * (swing * sin(TAU * t) * sin(PI * t))
			p.y = lerpf(p2.y, y1, float(k) / float(n2))
			r2.append(p)
		rail2 = kit.rail(r2, {"post_to_y": minf(a.y, b.y) - 12.0})
	# a boardwalk under the rails at the landing deck's height (descending stages only): a missed rail
	# drops you onto it, a few metres lower, and you run on to B
	if b.y <= a.y + 0.5:
		var cs0: float = 33.0
		var cs1: float = s_end - 7.0
		if cs1 - cs0 > 6.0:
			var cc: Vector3 = a + u * ((cs0 + cs1) * 0.5)
			cc.y = b.y - 0.02
			kit.plat(cc, Vector3(12.0, 1.0, cs1 - cs0), "alt", 2.5, yaw)
	# the landing deck under the end of the last rail
	var d0: float = s_end - 8.0
	var d1: float = dist - 3.0
	var dc: Vector3 = a + u * ((d0 + d1) * 0.5)
	dc.y = b.y - 0.02
	kit.plat(dc, Vector3(deck_w, 1.4, d1 - d0), "alt", 3.5, yaw)
	_min_y = minf(_min_y, minf(a.y, b.y) - 3.0)
	if OS.has_environment("SKYSURF_DEBUG"):
		_report_clearance(a, u, dist, s_end, s_end - s0)
	_trail_rail(rail1)
	_trail_rail(rail2)
	# the route
	var from_pt: Vector3 = a + u * 15.5
	var pre: Array[Vector3] = [a + u * 0.8]
	pre.append_array(gate_pts)
	pre.append(from_pt)
	var steps: Array[Dictionary] = []
	steps.append({"kind": "f_line", "pts": pre, "tol": 2.0})
	var landing_to: Vector3 = a + u * (s_end + 7.0)
	landing_to.y = b.y
	if two:
		steps.append({"kind": "f_rail", "rail": rail1, "board": rail1.start_point(), "from": from_pt, "leave": rail1.end_point(), "chain_next": true, "to": rail2.start_point()})
		steps.append({"kind": "f_rail", "rail": rail2, "board": rail2.start_point(), "chain": true, "to": landing_to})
	else:
		steps.append({"kind": "f_rail", "rail": rail1, "board": rail1.start_point(), "from": from_pt, "to": landing_to})
	var out_pts: Array[Vector3] = [landing_to + u * 3.0, b]
	steps.append({"kind": "f_line", "pts": out_pts, "tol": 2.0})
	return {"steps": steps, "rail1": rail1, "rail2": rail2, "u": u, "yaw": yaw, "dist": dist}


## A flow line that is one long grassy slide from A's run-out to B's deck, with a chain of rings strung
## along it. opts: rings, width, ring_add.
func _flow_slide(a: Vector3, b: Vector3, opts: Dictionary = {}) -> Dictionary:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist: float = flat.length()
	var u: Vector3 = flat / maxf(dist, 0.01)
	var gate_pts: Array[Vector3] = [a + u * 9.0, a + u * 14.0]
	kit.boost_chain(gate_pts, 20.0, 3.2, {"speed_end": 24.0})
	_runout_deck(a, u, _yaw_of(u), 9.0)
	var start: Vector3 = a + u * RUNOUT
	var end: Vector3 = b - u * 6.0
	var slope: FlowSurface = kit.flow_slope_between(start, end, float(opts.get("width", 10.0)))
	var ring_n: int = int(opts.get("rings", 6))
	var ring_pts: Array[Vector3] = []
	for i: int in ring_n:
		var t: float = lerpf(0.18, 0.88, float(i) / float(maxi(ring_n - 1, 1)))
		ring_pts.append(start.lerp(end, t) + Vector3(0, 1.2, 0))
	var rings: Array[SpeedRing] = kit.ring_line(ring_pts, {"add_speed": float(opts.get("ring_add", 2.0)), "radius": 2.6})
	_min_y = minf(_min_y, minf(a.y, b.y) - 3.0)
	if OS.has_environment("SKYSURF_DEBUG"):
		_report_clearance(a, u, dist, dist - 6.0, dist - RUNOUT)
	var steps: Array[Dictionary] = []
	var pre: Array[Vector3] = [a + u * 0.8, gate_pts[0], gate_pts[1], start]
	steps.append({"kind": "f_line", "pts": pre, "tol": 2.0})
	var line: Array[Vector3] = []
	for r: Vector3 in ring_pts:
		line.append(r - Vector3(0, 1.2, 0))
	line.append(end)
	_trail(line, 0.7, false)
	steps.append({"kind": "f_line", "pts": line, "tol": 2.0})
	var out_pts: Array[Vector3] = [b]
	steps.append({"kind": "f_line", "pts": out_pts, "tol": 2.0})
	return {"steps": steps, "slope": slope, "rings": rings, "u": u, "dist": dist}


## A flow line that is one long half-pipe from A's deck to B's, carved wall to wall.
func _flow_pipe(a: Vector3, b: Vector3, opts: Dictionary = {}) -> Dictionary:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist: float = flat.length()
	var u: Vector3 = flat / maxf(dist, 0.01)
	var gate_pts: Array[Vector3] = [a + u * 9.0, a + u * 14.0]
	_runout_deck(a, u, yaw0(u), 9.0)
	kit.boost_chain(gate_pts, 20.0, 3.2, {"speed_end": 24.0})
	var start: Vector3 = a + u * RUNOUT
	var end: Vector3 = b - u * 6.0
	var pipe: HalfPipe = kit.halfpipe(start, end, float(opts.get("width", 14.0)), float(opts.get("depth", 3.0)), {"flat": float(opts.get("flat", 0.2)), "shelf": 0.5})
	_min_y = minf(_min_y, minf(a.y, b.y) - 3.0)
	if OS.has_environment("SKYSURF_DEBUG"):
		_report_clearance(a, u, dist, dist - 6.0, dist - 12.0)
	var steps: Array[Dictionary] = []
	var pre: Array[Vector3] = [a + u * 0.8, gate_pts[0], gate_pts[1], start]
	steps.append({"kind": "f_line", "pts": pre, "tol": 2.0})
	steps.append({"kind": "f_line", "pts": pipe.carve_points(int(opts.get("swings", 3)), 0.55), "tol": 2.0})
	var out_pts: Array[Vector3] = [pipe.centre_point(1.0), b]
	steps.append({"kind": "f_line", "pts": out_pts, "tol": 2.0})
	return {"steps": steps, "pipe": pipe, "u": u, "dist": dist}


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
	add_child(Ambience.make(theme_id))
	deco = SkysurfDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 0), 0.0)
	var yaws: Array[float] = [0.0, -8.0, 7.0, -6.0, 9.0, 0.0, -10.0, 5.0, -7.0, 6.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10]
	var dev_last: int = DEV_LAST if not OS.has_environment("SKYSURF_LAST") else int(OS.get_environment("SKYSURF_LAST"))
	var last: int = stages.size() if dev_last <= 0 else mini(dev_last, stages.size())
	var sides: Array[float] = [1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in last:
		_next_yaw = yaws[i + 1]
		_next_side = sides[i + 1]
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
	_skin_islands()
	_dress_flow()
	_surroundings()


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
	_use_flow(s0, _flow_slide(_o, _w(cp["c"]), {"rings": 6, "width": 10.0}))
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
	_use_flow(s0, _flow_rails(_o, _w(cp["c"]), {"two": true, "swing": 6.0}))
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
	_use_flow(s0, _flow_pipe(_o, _w(cp["c"]), {"width": 11.0, "depth": 2.4}))
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
	var items: Array = [_S(6.0, 3.2), _C(26.0, 4.5, 3.4), _H(0.70, 0.6, 1.9), _B(0.70, 0.6, 3.4, 3.4), _P(3.8), _P(3.8),
		_S(8.0, 3.2), _H(0.70, 0.4, 1.9), _B(0.72, 0.4, 3.0, 3.0), _K(0.74, 0.4)]
	var s0: int = route.size()
	var cp: Dictionary = _trace(a, 90.0, 1.0, 15.0, items)
	_checkpoint_at(cp)
	# the rising ribbon: two rails climbing back up through the cloud
	_use_flow(s0, _flow_rails(_o, _w(cp["c"]), {"two": true, "swing": 7.0}))
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
	_use_flow(s0, _flow_rails(_o, _w(cp["c"]), {"two": false, "swing": 10.0}))
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
	var s0: int = route.size()
	# first half: to a floating mid isle (no checkpoint), second half: on to the sun isle with the finish gate
	var items1: Array = [_S(14.0, 3.4), _H(0.70, -0.5, 1.9), _B(0.72, -0.5, 3.0, 3.0), _S(14.0, 3.2), _H(0.70, -0.5, 1.9),
		_B(0.72, -0.5, 3.2, 3.2), _S(12.0, 3.2), _H(0.70, -0.5, 1.9), _B(0.72, -0.5, 3.0, 3.0), {"t": "cp", "pct": 0.72, "dy": -0.5, "r": 6.0, "style": "accent"}]
	var mid: Dictionary = _trace(a, 100.0, -1.0, 15.0, items1)
	var items2: Array = [_S(12.0, 3.4), _C(30.0, -4.5, 3.6), _H(0.70, -0.5, 1.9), _B(0.72, -0.5, 3.0, 3.0), _S(14.0, 3.2),
		_H(0.70, -0.5, 1.9), _B(0.72, -0.5, 3.2, 3.2), _H(0.72, -0.4, 1.9), {"t": "cp", "pct": 0.72, "dy": -0.4, "r": 7.0}]
	var fin: Dictionary = _trace(mid, 105.0, 1.0, 15.0, items2)
	kit.finish(_w(fin["c"]), _yaw)
	_finish_pos = _w(fin["c"])
	# the flow line: ribbons up to the mid isle, then the great ring flight into the sun
	var m_w: Vector3 = _w(mid["c"])
	_mid_world = m_w
	var leg1: Dictionary = _flow_rails(_o, m_w, {"two": true, "swing": 7.0})
	var leg2: Dictionary = _flow_arc(m_w, _w(fin["c"]), {"rings": 10, "ring_add": 3.0, "pitch": 28.0, "deck": 12.0})
	var all_steps: Array[Dictionary] = []
	all_steps.append_array(leg1["steps"] as Array[Dictionary])
	all_steps.append_array(leg2["steps"] as Array[Dictionary])
	_use_flow(s0, {"steps": all_steps})
	r_walk(_w(fin["c"]))
	return fin["c"]


# ---- the look ---------------------------------------------------------------------------------

func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_sun = n as DirectionalLight3D
			else:
				_fill = n as DirectionalLight3D
	_env.background_mode = Environment.BG_SKY
	_env.sky = SkysurfSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.96, 0.84, 0.96)
	_env.ambient_light_energy = 0.9
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(1.0, 0.82, 0.82)
	_env.fog_density = 0.0011
	_env.fog_aerial_perspective = 0.45
	_env.fog_sky_affect = 0.1
	_env.fog_sun_scatter = 0.35
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.08
	_env.adjustment_contrast = 1.04
	# the low sun ahead and a little to the right; a cool lilac fill from behind
	_sun.light_color = Color(1.0, 0.84, 0.66)
	_sun.light_energy = 1.8
	_sun.rotation_degrees = Vector3(-22, 152, 0)
	_fill.light_color = Color(0.82, 0.76, 1.0)
	_fill.light_energy = 0.38
	_fill.rotation_degrees = Vector3(-24, 332, 0)


## Swap every platform the kit built onto the island shader (same uniforms, new look).
func _skin_islands() -> void:
	var shader: Shader = preload("res://visual/skysurf_isle.gdshader")
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm != null and sm.shader == Look.PLATFORM_SHADER:
			sm.shader = shader


## Dress the flow line: wind ribbons streaming along every gate run, slope, rail and ring flight.
func _dress_flow() -> void:
	for i: int in _flow_paths.size():
		var f: Dictionary = _flow_paths[i]
		var pts: PackedVector3Array = f["pts"]
		if pts.size() < 2:
			continue
		var air: bool = bool(f["air"])
		var ca: Color = deco.palette(i)
		var cb: Color = deco.palette(i + 3).lerp(Color.WHITE, 0.5)
		var offsets: Array[float] = [0.0]
		if bool(f["rail"]):
			offsets = [-0.8, 0.8]
		for off: float in offsets:
			var q := PackedVector3Array()
			var chord: Vector3 = pts[pts.size() - 1] - pts[0]
			var side: Vector3 = chord.cross(Vector3.UP)
			side = side.normalized() * off if side.length() > 0.001 else Vector3.ZERO
			for p3: Vector3 in pts:
				q.append(p3 + side + (Vector3(0, 0.5, 0) if bool(f["rail"]) else Vector3.ZERO))
			var rb := SkysurfRibbon.new()
			rb.points = q
			rb.width = 1.9 if air else 1.2
			rb.color_a = ca
			rb.color_b = cb
			rb.speed = 8.0
			rb.strength = 0.6 if air else 0.5
			rb.phase = float(i) * 0.7 + off
			rb.build()
			add_child(rb)


## Horizontal distance from `p` to the nearest chord (the straight line between consecutive decks).
func _chord_dist(p: Vector3, chords: Array[Vector3]) -> float:
	var best: float = INF
	for i: int in chords.size() - 1:
		var a: Vector3 = chords[i]
		var b: Vector3 = chords[i + 1]
		var ab: Vector3 = b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _clear_of_isles(p: Vector3, dist: float) -> bool:
	for isl: Dictionary in _isles:
		if (isl["c"] as Vector3).distance_to(p) < dist + float(isl["r"]):
			return false
	return true


func _surroundings() -> void:
	var rng: RandomNumberGenerator = kit.rng
	var chords: Array[Vector3] = [Vector3.ZERO]
	for c: Vector3 in _cp_world:
		chords.append(c)
	if _mid_world != Vector3.INF:
		chords.insert(chords.size(), _mid_world)
	chords.append(_finish_pos)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for c: Vector3 in chords:
		lo = lo.min(c)
		hi = hi.max(c)
	var mid: Vector3 = (lo + hi) * 0.5
	var floor_y: float = lo.y - 70.0
	# the sea of cloud
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4200, 4200)
	sea.mesh = pm
	var smat := ShaderMaterial.new()
	smat.shader = preload("res://visual/skysurf_sea.gdshader")
	var ld: Vector3 = -_sun.global_transform.basis.z
	smat.set_shader_parameter("sun_dir", Vector2(-ld.x, -ld.z))
	sea.material_override = smat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.position = Vector3(mid.x, floor_y, mid.z)
	add_child(sea)
	# cumulus mounds and towers rising from the sea, clear of the course
	for k: int in 60:
		var at := Vector3(rng.randf_range(lo.x - 260.0, hi.x + 260.0), floor_y - 4.0, rng.randf_range(lo.z - 200.0, hi.z + 260.0))
		if _chord_dist(Vector3(at.x, lo.y, at.z), chords) < 60.0:
			continue
		if rng.randf() < 0.45:
			deco.tower(at, rng.randf_range(40.0, 95.0), rng.randf_range(7.0, 14.0))
		else:
			deco.mound(at + Vector3(0, rng.randf_range(0.0, 14.0), 0), rng.randf_range(1.6, 3.2))
	# far floating isles, balloons
	var placed: int = 0
	var tries: int = 0
	while placed < 46 and tries < 600:
		tries += 1
		var ci: int = rng.randi_range(0, chords.size() - 2)
		var base: Vector3 = chords[ci].lerp(chords[ci + 1], rng.randf())
		var lat: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-0.3, 0.3)).normalized() * rng.randf_range(55.0, 210.0)
		var at2: Vector3 = base + lat + Vector3(0, rng.randf_range(-45.0, 40.0), 0)
		var rad: float = rng.randf_range(7.0, 26.0)
		if _chord_dist(at2, chords) < rad + 38.0:
			continue
		deco.far_isle(at2, rad, true)
		placed += 1
	for k: int in 9:
		var ci2: int = rng.randi_range(0, chords.size() - 2)
		var b2: Vector3 = chords[ci2].lerp(chords[ci2 + 1], rng.randf())
		var off2: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-0.2, 0.2)).normalized() * rng.randf_range(70.0, 170.0)
		var bp: Vector3 = b2 + off2 + Vector3(0, rng.randf_range(-10.0, 35.0), 0)
		if _chord_dist(bp, chords) > 45.0:
			deco.balloon(bp, rng.randf_range(9.0, 16.0), deco.palette(k), deco.palette(k + 3))
	# kites: a few along every stage, a whole valley of them in stage 4
	for i2: int in chords.size() - 1:
		var a: Vector3 = chords[i2]
		var b: Vector3 = chords[i2 + 1]
		var n_k: int = 14 if i2 == 3 else 4
		for k: int in n_k:
			var t: float = rng.randf_range(0.1, 0.9)
			var pos: Vector3 = a.lerp(b, t)
			var dir: Vector3 = (b - a)
			dir.y = 0.0
			var side: Vector3 = dir.cross(Vector3.UP).normalized()
			var lat2: float = rng.randf_range(14.0, 48.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			var kp: Vector3 = pos + side * lat2 + Vector3(0, rng.randf_range(6.0, 30.0), 0)
			if not _clear_of_isles(kp, 6.0):
				continue
			deco.kite(kp, rng.randf_range(5.0, 11.0), deco.palette(i2 + k), deco.palette(i2 + k + 2), rng.randf_range(-30.0, 30.0))
	# birds wheeling over the stages
	for i3: int in chords.size() - 1:
		var mid3: Vector3 = chords[i3].lerp(chords[i3 + 1], 0.5)
		var fl := SkysurfFlock.new()
		fl.count = 11
		fl.radius = rng.randf_range(18.0, 30.0)
		fl.height = rng.randf_range(6.0, 16.0)
		fl.seed_value = 40 + i3
		fl.position = mid3 + Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-12.0, 12.0))
		fl.build()
		add_child(fl)
	# petals on the wind and glints in the low sun, over every stage
	for i4: int in chords.size() - 1:
		var m4: Vector3 = chords[i4].lerp(chords[i4 + 1], 0.5)
		var d4: Vector3 = chords[i4 + 1] - chords[i4]
		d4.y = 0.0
		var half: float = d4.length() * 0.5
		var wind: Vector3 = d4.normalized() + Vector3(0.15, 0.0, 0.0)
		SkysurfFx.petals(self, m4 + Vector3(0, 6.0, 0), Vector3(30.0, 9.0, half), 38, wind)
		SkysurfFx.motes(self, m4 + Vector3(0, 5.0, 0), Vector3(26.0, 8.0, half), 26)
	# the start: a pier arch and bunting; pinwheels and bunting on every checkpoint deck
	kit.arch(_w_world(Vector3(0, 0, -9.0)), 8.0, 5.0, 0.0, Look.c("accent"))
	deco.pinwheel(Vector3(-5.0, 0.0, 2.0), 1.3, SkysurfDecor.ROSE, SkysurfDecor.BUTTER, 2.4)
	deco.pinwheel(Vector3(5.0, 0.0, 2.0), 1.3, SkysurfDecor.BUTTER, SkysurfDecor.ROSE, -2.4)
	for k2: int in _cp_world.size():
		var cw: Vector3 = _cp_world[k2]
		var off_a: Vector3 = Vector3(-5.0, 0.0, 0.0)
		var off_b: Vector3 = Vector3(5.0, 0.0, 0.0)
		deco.pinwheel(cw + off_a, 1.3, deco.palette(k2), deco.palette(k2 + 2), 2.6)
		deco.pinwheel(cw + off_b, 1.3, deco.palette(k2 + 2), deco.palette(k2), -2.6)
	# rainbows: over the ring chain of Rainbow Bridge, and a great one behind the finish isle
	if _cp_world.size() >= 9:
		var r9a: Vector3 = _cp_world[7]
		var r9b: Vector3 = _cp_world[8]
		var m9: Vector3 = r9a.lerp(r9b, 0.5)
		var d9: Vector3 = r9b - r9a
		d9.y = 0.0
		d9 = d9.normalized()
		deco.rainbow(m9 + Vector3(0, -2.0, 0), 26.0, rad_to_deg(atan2(d9.x, d9.z)))
	deco.rainbow(_finish_pos + Vector3(0, -3.0, -60.0), 55.0, 0.0)


func _w_world(l: Vector3) -> Vector3:
	return l

