extends LevelBase
## 33. AURORA RUN - the first FLOW level (docs/FLOW_BRIEF.md). A clear, calm night descent down a snowy
## mountain under a huge rippling aurora. Nothing here kills and nothing makes you wait: the SAFE line is a
## walkable trail down the east side of the mountain (gentle ramps and small gap hops, every jump <= 82%),
## and the FLOW line is one unbroken breath of boost gates, long slopes, carved half-pipes, ridge rails,
## launch arcs and ring chains down the centre of the valley, over 40% faster. Both lines meet on a broad
## plaza at every checkpoint. The course runs straight down -Z, so everything is in world coordinates.
##
##  1 Trailhead        boost gates, a long slope                         | a snow trail and two small hops
##  2 Pine Run         a carved half-pipe through the pines              | switchback terraces
##  3 Ridge Rails      two ridge rails, rail to rail                     | the narrow ridge itself
##  4 Frozen Tarn      a ring chain skimming the frozen lake             | stepping floes
##  5 Glacier Chute    a steep chute, a ring chain, a launch arc         | crevasse hops
##  6 Aurora Draft     a launch arc into the aurora draft and its motes  | the long way round
##  7 Twin Pipes       a half-pipe into a rail                           | long switchbacks
##  8 Moon Meadow      a long slope, a ring chain                        | meadow terraces
##  9 THE CASCADE      SET PIECE: gates -> pipe -> rail -> launch -> ring chain -> slope to the finish
##
## Route variants for the bot: 0 = the safe line, 1 = the flow line. The pure-flow finale has a walkable safe
## line beside it too. Mechanics of its own: AuroraDraft (a ribbon of light that lifts and carries you) and
## AuroraMote (glowing motes along the fast line that add a little flow). Visuals: visual/aurora_*.

const PLAZA_HX: float = 9.0
const PLAZA_HZ: float = 8.0
## Plaza centre z and the drop (m) of each stage, plaza 0 is the start, plaza 9 the finish.
const PLAZA_Z: Array[float] = [0.0, -110.0, -230.0, -360.0, -470.0, -600.0, -720.0, -840.0, -950.0, -1110.0]
const DROP: Array[float] = [11.0, 13.0, 14.0, 11.0, 14.0, 13.0, 14.0, 11.0, 20.0]
## x of the safe lane where it leaves / re-enters a plaza.
const LANE_X: float = 5.0

var _tuning: MovementTuning
var plaza_y: Array[float] = []
var _cp_world: Array[Vector3] = []
## Crevasse gaps the safe line hops: {"z0","z1","x","w"} (the terrain dips under them).
var _gaps: Array[Dictionary] = []
## The last built walkable rect of the safe lane: {"c": top centre, "hx", "hz"}.
var _cur: Dictionary = {}
var _dry: bool = false
var _hop_max: float = 0.0


func _configure() -> void:
	theme_id = "aurora"
	music_track = "aurora"
	kill_y = -260.0
	route_variants = 2


# ---- geometry helpers ---------------------------------------------------------------------------

func _reach(dy: float) -> float:
	var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, _tuning.jump_velocity, -_tuning.max_speed), dy)
	return absf(land.z)


func _rect(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


func _in_rect(p: Vector3, a: Dictionary) -> bool:
	var c: Vector3 = a["c"]
	return absf(p.x - c.x) <= float(a["hx"]) and absf(p.z - c.z) <= float(a["hz"])


## Takeoff spot on `a`: on the line from its centre toward `toward`, `inset` metres inside the edge.
func _edge(a: Dictionary, toward: Vector3, inset: float = 0.35) -> Vector3:
	var c: Vector3 = a["c"]
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	var tx: float = INF if absf(d.x) < 0.001 else (float(a["hx"]) - inset) / absf(d.x)
	var tz: float = INF if absf(d.z) < 0.001 else (float(a["hz"]) - inset) / absf(d.z)
	return c + d * minf(tx, tz)


## What test_m measures for a jump from `t` toward `to` onto rect `land`: (distance, rise).
func _need(t: Vector3, to: Vector3, cur: Dictionary, land: Dictionary) -> Vector2:
	var flat := Vector3(to.x - t.x, 0, to.z - t.z)
	var total: float = flat.length()
	var dir: Vector3 = flat.normalized()
	var left: bool = false
	var d: float = 0.0
	while d <= total + 3.0:
		var p: Vector3 = t + dir * d
		if not left:
			if not _in_rect(p, cur):
				left = true
		elif _in_rect(p, land):
			return Vector2(d + 0.4, (land["c"] as Vector3).y - t.y)
		d += 0.2
	return Vector2(total, to.y - t.y)


func _slab(a: Vector3, b: Vector3, width: float, thick: float = 1.0, style: String = "alt") -> void:
	var d: Vector3 = b - a
	var h: float = Vector2(d.x, d.z).length()
	var pitch: float = rad_to_deg(atan2(d.y, h))
	var yaw: float = rad_to_deg(atan2(-d.x, -d.z))
	kit.ramp((a + b) * 0.5, Vector3(width, thick, d.length()), pitch, yaw, style)


func _deck(a: Dictionary, style: String = "main", thick: float = 1.2) -> void:
	var c: Vector3 = a["c"]
	kit.plat(c, Vector3(float(a["hx"]) * 2.0, thick, float(a["hz"]) * 2.0), style)


# ---- the safe lane ---------------------------------------------------------------------------------

## A gap hop from the current rect onto a new deck (len along z, wid across) `dy` higher, shifted `dx`
## sideways, placed so test_m measures `pct` of max reach.
func _hop(pct: float, dy: float, len_: float, wid: float, dx: float = 0.0, style: String = "main") -> void:
	var cc: Vector3 = _cur["c"]
	var front: float = cc.z - float(_cur["hz"])
	var best_g: float = -1.0
	var best_p: float = 0.0
	var g: float = 0.6
	while g < 9.0:
		var lc := Vector3(cc.x + dx, cc.y + dy, front - g - len_ * 0.5)
		var land: Dictionary = _rect(lc, wid * 0.5, len_ * 0.5)
		var to := Vector3(lc.x, lc.y, front - g - minf(1.4, len_ * 0.5))
		var t: Vector3 = _edge(_cur, to)
		var need: Vector2 = _need(t, to, _cur, land)
		var p: float = need.x / _reach(need.y)
		if p <= pct:
			best_g = g
			best_p = p
		g += 0.05
	if best_g < 0.0:
		push_error("aurora: no hop solution for pct %.2f" % pct)
		return
	_hop_max = maxf(_hop_max, best_p)
	var lc2 := Vector3(cc.x + dx, cc.y + dy, front - best_g - len_ * 0.5)
	var land2: Dictionary = _rect(lc2, wid * 0.5, len_ * 0.5)
	var to2 := Vector3(lc2.x, lc2.y, front - best_g - minf(1.4, len_ * 0.5))
	var t2: Vector3 = _edge(_cur, to2)
	if not _dry:
		_deck(land2, style)
		_gaps.append({"z0": front, "z1": front - best_g, "x": cc.x + dx * 0.5, "w": maxf(float(_cur["hx"]), wid * 0.5) * 2.0 + 4.0})
		if route_variant == 0:
			r_jump(t2, to2, true)
	_cur = land2


## A walkable ramp down from the front edge of the current rect (zlen along z, drop m lower, shifted dx),
## then a short flat deck. `drop` < 0 means "work it out" (the stage spreads the remaining drop evenly).
func _ramp(zlen: float, drop: float, wid: float, dlen: float = 5.0, dx: float = 0.0, style: String = "alt") -> void:
	var cc: Vector3 = _cur["c"]
	var front: float = cc.z - float(_cur["hz"])
	var a := Vector3(cc.x, cc.y, front)
	var b := Vector3(cc.x + dx, cc.y - drop, front - zlen)
	var deck: Dictionary = _rect(Vector3(b.x, b.y, b.z - dlen * 0.5), wid * 0.5, dlen * 0.5)
	if not _dry:
		_slab(a, b, wid, 1.0, style)
		_deck(deck, "main", 1.0)
		if route_variant == 0:
			r_walk(Vector3(b.x, b.y, b.z - 1.0))
	_cur = deck


## Builds a stage's safe lane from plaza `k-1` to plaza `k`. `ops` entries:
##   ["ramp", zlen, wid, dlen, dx]            a ramp down (its drop shares the stage's drop evenly)
##   ["hop", pct, dy, len, wid, dx]           a gap hop
##   ["fill", wid]                            the closing ramp to the plaza (takes the z that is left)
func _lane(k: int, ops: Array) -> void:
	var y0: float = plaza_y[k - 1]
	var y1: float = plaza_y[k]
	var z0: float = PLAZA_Z[k - 1] - PLAZA_HZ
	var z1: float = PLAZA_Z[k] + PLAZA_HZ
	var start: Dictionary = _rect(Vector3(LANE_X, y0, PLAZA_Z[k - 1]), 4.0, PLAZA_HZ)
	# dry pass: z used by everything but the fill, and the drop the hops take
	_dry = true
	_cur = start
	var hop_dy: float = 0.0
	var ramp_z: float = 0.0
	var fill_wid: float = 5.0
	for op: Array in ops:
		match str(op[0]):
			"ramp":
				_ramp(float(op[1]), 0.0, float(op[2]), float(op[3]), float(op[4]))
				ramp_z += float(op[1])
			"hop":
				_hop(float(op[1]), float(op[2]), float(op[3]), float(op[4]), float(op[5]))
				hop_dy += float(op[2])
			"fill":
				fill_wid = float(op[1])
	_dry = false
	var fill_z: float = (float((_cur["c"] as Vector3).z) - float(_cur["hz"])) - z1
	var total_ramp: float = ramp_z + fill_z
	var pitch_drop: float = ((y0 - y1) + hop_dy)  # hop_dy is negative for drops: ramps take what remains
	var per_m: float = pitch_drop / maxf(total_ramp, 1.0)
	print("aurora stage %d: ramps %.1f m + fill %.1f m, ramp pitch %.1f deg, hardest hop so far %.0f%%" % [k, ramp_z, fill_z, rad_to_deg(atan(per_m)), _hop_max * 100.0])
	_cur = start
	if route_variant == 0:
		r_walk(Vector3(LANE_X, y0, PLAZA_Z[k - 1] - 4.0))
	for op: Array in ops:
		match str(op[0]):
			"ramp":
				_ramp(float(op[1]), per_m * float(op[1]), float(op[2]), float(op[3]), float(op[4]))
			"hop":
				_hop(float(op[1]), float(op[2]), float(op[3]), float(op[4]), float(op[5]))
	# the closing ramp lands flush on the plaza's back edge
	var cc: Vector3 = _cur["c"]
	var front: float = cc.z - float(_cur["hz"])
	var a := Vector3(cc.x, cc.y, front)
	var b := Vector3(LANE_X, y1, z1)
	_slab(a, b, fill_wid)
	if route_variant == 0:
		r_walk(b + Vector3(0, 0, -1.5))
		r_walk(Vector3(0.0, y1, PLAZA_Z[k]))


func _plaza(k: int) -> void:
	var c := Vector3(0, plaza_y[k], PLAZA_Z[k])
	kit.plat(c, Vector3(PLAZA_HX * 2.0, 1.6, PLAZA_HZ * 2.0), "main", 2.0)
	if k > 0 and k < PLAZA_Z.size() - 1:
		kit.checkpoint(c, 0.0)
		_cp_world.append(c)


# ---- the course ----------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	var y: float = 0.0
	plaza_y.append(0.0)
	for k: int in DROP.size():
		y -= DROP[k]
		plaza_y.append(y)
	set_spawn(Vector3(0, plaza_y[0] + 0.1, 0.0), 0.0)
	for k: int in PLAZA_Z.size():
		_plaza(k)
	_lane(1, [["ramp", 24.0, 6.0, 5.0, 0.0], ["hop", 0.60, -1.5, 8.0, 5.0, 0.0], ["ramp", 18.0, 6.0, 5.0, 0.0],
		["hop", 0.68, -1.6, 8.0, 4.6, 2.0], ["fill", 6.0]])
	if route_variant == 0:
		r_checkpoint()
	_lane(2, [["ramp", 20.0, 5.0, 5.0, 3.0], ["hop", 0.72, -2.1, 7.0, 4.4, -3.0], ["ramp", 14.0, 5.0, 5.0, 3.0],
		["hop", 0.74, -2.2, 7.0, 4.4, -3.0], ["ramp", 14.0, 5.0, 5.0, 3.0], ["fill", 5.0]])
	if route_variant == 0:
		r_checkpoint()
	_lane(3, [["ramp", 16.0, 4.0, 6.0, 0.0], ["hop", 0.66, -2.0, 12.0, 3.2, 0.0], ["hop", 0.70, -2.0, 12.0, 3.2, 0.0],
		["hop", 0.72, -2.0, 12.0, 3.2, 0.0], ["hop", 0.76, -2.0, 8.0, 4.0, 0.0], ["fill", 5.0]])
	if route_variant == 0:
		r_checkpoint()
	_lane(4, [["ramp", 10.0, 5.0, 4.0, 0.0], ["hop", 0.58, -0.8, 5.0, 4.4, 2.0], ["hop", 0.58, -0.8, 5.0, 4.4, -2.0],
		["hop", 0.60, -0.8, 5.0, 4.4, 2.0], ["hop", 0.60, -0.8, 5.0, 4.4, -2.0], ["ramp", 16.0, 5.0, 5.0, 0.0], ["fill", 5.0]])
	if route_variant == 0:
		r_checkpoint()
	_lane(5, [["ramp", 18.0, 5.0, 6.0, 0.0], ["hop", 0.78, -2.0, 9.0, 4.4, 0.0], ["ramp", 14.0, 5.0, 6.0, 0.0],
		["hop", 0.80, -2.2, 9.0, 4.4, 2.0], ["ramp", 12.0, 5.0, 6.0, 0.0], ["hop", 0.78, -2.0, 8.0, 4.4, -2.0], ["fill", 5.0]])
	if route_variant == 0:
		r_checkpoint()
	_lane(6, [["ramp", 22.0, 5.0, 6.0, 0.0], ["hop", 0.74, -2.2, 10.0, 4.4, 0.0], ["ramp", 22.0, 5.0, 6.0, -2.0],
		["hop", 0.76, -2.2, 8.0, 4.4, 2.0], ["fill", 5.0]])
	if route_variant == 0:
		r_checkpoint()
	_lane(7, [["ramp", 24.0, 5.0, 5.0, 2.0], ["hop", 0.70, -2.4, 8.0, 4.4, -3.0], ["ramp", 24.0, 5.0, 5.0, 2.0],
		["hop", 0.72, -2.4, 8.0, 4.4, -2.0], ["fill", 5.0]])
	if route_variant == 0:
		r_checkpoint()
	_lane(8, [["ramp", 20.0, 6.0, 6.0, 0.0], ["hop", 0.64, -1.8, 10.0, 5.0, 0.0], ["ramp", 20.0, 6.0, 6.0, 0.0],
		["hop", 0.66, -1.8, 8.0, 5.0, 2.0], ["fill", 5.0]])
	if route_variant == 0:
		r_checkpoint()
	_lane(9, [["ramp", 30.0, 6.0, 6.0, 0.0], ["hop", 0.68, -2.5, 10.0, 5.0, 0.0], ["ramp", 30.0, 6.0, 6.0, 0.0],
		["hop", 0.72, -2.5, 10.0, 5.0, 0.0], ["ramp", 24.0, 6.0, 6.0, 0.0], ["fill", 5.0]])
	kit.finish(Vector3(0, plaza_y[9], PLAZA_Z[9] - 2.0), 0.0)
	if route_variant == 0:
		r_walk(Vector3(0, plaza_y[9], PLAZA_Z[9] - 2.0))
	print("aurora: hardest safe hop %.0f%%" % (_hop_max * 100.0))


var _dbg_t: float = 0.0


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	_dbg_t += dt
	if _dbg_t > 0.3 and run_time < 8.0:
		_dbg_t = 0.0
		print("DBG t=%.1f pos=%s vel=%s grounded=%s" % [run_time, str(player.global_position.snapped(Vector3.ONE * 0.01)), str(player.velocity.snapped(Vector3.ONE * 0.1)), str(player.grounded)])
