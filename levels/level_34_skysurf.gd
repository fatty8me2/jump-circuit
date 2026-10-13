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


func _configure() -> void:
	theme_id = "skysurf"
	music_track = "skysurf"
	kill_y = -160.0
	# 0 = the safe line, 1 = the flow line
	route_variants = 2


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
	_note(c)
	return {"c": c, "r": r}


func _box(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, keel: float = -1.0, rot: float = 0.0) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw + rot)
	_note(c)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5, "rot": rot}


func _note(c: Vector3) -> void:
	_min_y = minf(_min_y, _w(c).y)


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
	_note(mid)
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
	for it: Dictionary in items:
		var c: Vector3 = cur["c"]
		var adv: float = 9.0
		match str(it["t"]):
			"span", "climb":
				adv = float(it["len"])
		var p: float = -c.z - p0
		var xt: float = side * amp * sin(PI * clampf((p + adv) / chord, 0.0, 1.0))
		var ang: float = clampf(rad_to_deg(atan2(-(xt - c.x), adv)), -50.0, 50.0)
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


# ---- the course -----------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	set_spawn(Vector3(0, 0.1, 0), 0.0)
	var yaws: Array[float] = [0.0, -8.0, 7.0, -6.0, 9.0, 0.0, -10.0, 5.0, -7.0, 6.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9, _stage_10]
	var last: int = stages.size() if DEV_LAST <= 0 else mini(DEV_LAST, stages.size())
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
	var cp: Dictionary = _trace(a, 82.0, 1.0, 10.0, items)
	_checkpoint_at(cp)
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Meadow Slide --------------------------------------------------------------------

func _stage_2() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(8.0, 3.2), _H(0.70, -1.5, 1.7), _B(0.70, -1.5, 3.0, 3.0), _H(0.72, -1.5, 1.6, "accent"),
		_S(10.0, 3.0), _H(0.70, -1.5, 1.8), _B(0.72, -1.5, 2.8, 3.4), _S(10.0, 3.2), _H(0.70, -1.5, 1.7),
		_B(0.72, -1.5, 3.0, 3.0), _H(0.70, -1.0, 1.8), _K(0.72, -1.0)]
	var cp: Dictionary = _trace(a, 88.0, -1.0, 12.0, items)
	_checkpoint_at(cp)
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Ribbon Row ----------------------------------------------------------------------

func _stage_3() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(12.0, 3.0), _H(0.72, -0.8, 1.8), _H(0.72, -0.8, 1.6, "accent"), _B(0.74, -0.8, 2.6, 2.6),
		_S(16.0, 3.0), _H(0.70, -0.6, 1.7), _B(0.72, -0.6, 3.0, 3.0), _S(8.0, 3.2), _H(0.72, -0.6, 1.8),
		_H(0.72, -0.6, 1.6), _B(0.72, -0.6, 3.0, 3.0), _K(0.72, -0.6)]
	var cp: Dictionary = _trace(a, 90.0, 1.0, 10.0, items)
	_checkpoint_at(cp)
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Kite Valley ---------------------------------------------------------------------

func _stage_4() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(14.0, 3.2), _H(0.70, -0.4, 1.8), _B(0.72, -0.4, 2.8, 2.8, "accent"), _H(0.70, -0.4, 1.7),
		_S(10.0, 3.0), _B(0.72, -0.4, 3.2, 3.2), _H(0.74, -0.4, 1.6), _S(10.0, 3.0), _H(0.70, -0.4, 1.8),
		_B(0.72, -0.4, 2.8, 3.4), _H(0.70, -0.4, 1.8), _K(0.72, -0.4)]
	var cp: Dictionary = _trace(a, 88.0, -1.0, 11.0, items)
	_checkpoint_at(cp)
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Cloud Canyon --------------------------------------------------------------------

func _stage_5() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(10.0, 3.0), _H(0.70, -1.2, 1.8), _B(0.70, -1.2, 3.0, 3.0), _H(0.72, -1.2, 1.7, "accent"),
		_S(12.0, 3.2), _H(0.70, -1.2, 1.8), _B(0.72, -1.2, 3.0, 3.0), _S(10.0, 3.0), _H(0.70, -1.2, 1.8),
		_H(0.72, -1.2, 1.6), _K(0.72, -1.0)]
	var cp: Dictionary = _trace(a, 90.0, 1.0, 12.0, items)
	_checkpoint_at(cp)
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Cumulus Skim --------------------------------------------------------------------

func _stage_6() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_H(0.68, -0.8, 2.2, "alt"), _H(0.72, -0.8, 2.0), _B(0.70, -0.8, 3.6, 3.2, "alt"), _H(0.74, -0.8, 1.8),
		_H(0.72, -0.8, 2.2, "alt"), _B(0.72, -0.8, 3.0, 3.0), _H(0.70, -0.8, 2.0), _H(0.72, -0.8, 1.8, "accent"),
		_B(0.72, -0.8, 3.4, 3.4, "alt"), _H(0.70, -0.8, 2.0), _K(0.72, -0.8)]
	var cp: Dictionary = _trace(a, 90.0, -1.0, 12.0, items)
	_checkpoint_at(cp)
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
	var cp: Dictionary = _trace(a, 90.0, -1.0, 11.0, items)
	_checkpoint_at(cp)
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Rainbow Bridge ------------------------------------------------------------------

func _stage_9() -> Vector3:
	var a: Dictionary = {"c": Vector3.ZERO, "r": 6.0}
	var items: Array = [_S(14.0, 3.4, "accent"), _H(0.70, -0.6, 1.8), _B(0.70, -0.6, 3.0, 3.0), _S(18.0, 3.2, "accent"),
		_H(0.72, -0.6, 1.8), _B(0.72, -0.6, 3.0, 3.0), _S(12.0, 3.0), _H(0.70, -0.6, 1.8), _B(0.70, -0.6, 3.0, 3.0),
		_H(0.72, -0.6, 1.7), _K(0.72, -0.6)]
	var cp: Dictionary = _trace(a, 92.0, 1.0, 10.0, items)
	_checkpoint_at(cp)
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
