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

const PLAZA_HX: float = 17.0
const PLAZA_HZ: float = 8.0
## Plaza centre z and the drop (m) of each stage, plaza 0 is the start, plaza 9 the finish.
const PLAZA_Z: Array[float] = [0.0, -110.0, -230.0, -360.0, -470.0, -600.0, -750.0, -870.0, -980.0, -1140.0]
const DROP: Array[float] = [11.0, 13.0, 14.0, 11.0, 14.0, 13.0, 14.0, 11.0, 20.0]
## x of the safe lane where it leaves / re-enters a plaza.
const LANE_X: float = 11.0

var _tuning: MovementTuning
var plaza_y: Array[float] = []
var _cp_world: Array[Vector3] = []
## Crevasse gaps the safe line hops: {"z0","z1","x","w"} (the terrain dips under them).
var _gaps: Array[Dictionary] = []
## The last built walkable rect of the safe lane: {"c": top centre, "hx", "hz"}.
var _cur: Dictionary = {}
var _dry: bool = false
var _hop_max: float = 0.0
var deco: AuroraDecor
var sky: AuroraSky
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO


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
	_note_span(a, b, width)


func _deck(a: Dictionary, style: String = "main", thick: float = 1.2) -> void:
	var c: Vector3 = a["c"]
	kit.plat(c, Vector3(float(a["hx"]) * 2.0, thick, float(a["hz"]) * 2.0), style)
	_note_span(c + Vector3(0, 0, float(a["hz"])), c - Vector3(0, 0, float(a["hz"])), float(a["hx"]) * 2.0)


## Tells the terrain where a walkable surface runs (so the valley floor stays well under it).
func _note_span(a: Vector3, b: Vector3, _width: float) -> void:
	var n: int = maxi(int(absf(a.z - b.z) / 6.0), 1)
	for i: int in n + 1:
		var f: float = float(i) / float(n)
		deco.note(lerpf(a.z, b.z, f), lerpf(a.y, b.y, f))


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
	_cur = start
	if route_variant == 0:
		r_walk(Vector3(3.5, y0, PLAZA_Z[k - 1] - 5.5))
		r_walk(Vector3(LANE_X, y0, PLAZA_Z[k - 1] - 5.5))
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
	var size := Vector3(PLAZA_HX * 2.0, 1.6, PLAZA_HZ * 2.0)
	kit.plat(c, size, "main", 2.0)
	_note_span(c + Vector3(0, 0, PLAZA_HZ), c - Vector3(0, 0, PLAZA_HZ), PLAZA_HX * 2.0)
	if k > 0 and k < PLAZA_Z.size() - 1:
		var cp: Checkpoint = kit.checkpoint(c, 0.0)
		_cp_world.append(c)
		var col: Color = AuroraFx.GREEN if k % 2 == 1 else AuroraFx.VIOLET
		var fx: Array[GPUParticles3D] = AuroraFx.cp_burst(col)
		for p: GPUParticles3D in fx:
			p.position = c + Vector3(0, 0.6, 0)
			add_child(p)
		_cp_bursts[cp] = fx
		cp.reached.connect(func(which: Checkpoint) -> void:
			if which.index > current_checkpoint:
				# SOUND: aurora_checkpoint - a stage banked: a bell of ice and a shimmer of light
				WorldAudio.at(self, "aurora_checkpoint", which.global_position, 0.9, 40.0)
				for q: GPUParticles3D in _cp_bursts[which]:
					q.restart()
					q.emitting = true)
	_dress_plaza(k, c)


## Lanterns on the plaza corners, a cairn, crystals, snow banks and a slow rise of lights.
func _dress_plaza(k: int, c: Vector3) -> void:
	var tint: Color = AuroraFx.GREEN if k % 2 == 1 else AuroraFx.VIOLET
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			deco.lantern(c + Vector3(sx * (PLAZA_HX - 0.7), 0, sz * (PLAZA_HZ - 0.7)), AuroraDecor.LAMP.lerp(tint, 0.35))
	deco.cairn(c + Vector3(-PLAZA_HX + 1.6, 0, 2.0), 1.1)
	deco.crystals(c + Vector3(PLAZA_HX - 1.8, 0, -2.2), tint, 1.0)
	deco.bank(c + Vector3(-PLAZA_HX - 1.0, -0.6, -1.0), Vector3(2.4, 1.2, 4.0))
	deco.bank(c + Vector3(PLAZA_HX + 1.2, -0.6, 1.5), Vector3(2.2, 1.0, 3.4))
	var rise: GPUParticles3D = AuroraFx.rising(Vector3(PLAZA_HX * 1.6, 1.0, PLAZA_HZ * 1.6), 16, tint)
	rise.position = c + Vector3(0, 0.6, 0)
	add_child(rise)


# ---- the course ----------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	deco = AuroraDecor.new(self, kit.rng)
	_restyle_environment()
	var y: float = 0.0
	plaza_y.append(0.0)
	for k: int in DROP.size():
		y -= DROP[k]
		plaza_y.append(y)
	set_spawn(Vector3(0, plaza_y[0] + 0.1, 0.0), 0.0)
	for k: int in PLAZA_Z.size():
		_plaza(k)
	for k: int in range(1, 10):
		_lane(k, _lane_ops(k))
		_flow(k)
		if k < 9:
			r_checkpoint()
	kit.finish(Vector3(0, plaza_y[9], PLAZA_Z[9] - 2.0), 0.0)
	if route_variant == 0:
		r_walk(Vector3(0, plaza_y[9], PLAZA_Z[9] - 2.0))
	else:
		r_flow([Vector3(0, plaza_y[9], PLAZA_Z[9] + 4.0), Vector3(0, plaza_y[9], PLAZA_Z[9] - 2.0)], 1.0)
	_finish_pos = Vector3(0, plaza_y[9], PLAZA_Z[9] - 2.0)
	_surroundings()


## The safe line's ops for stage k (see _lane).
func _lane_ops(k: int) -> Array:
	match k:
		1:
			return [["ramp", 24.0, 6.0, 5.0, 0.0], ["hop", 0.60, -1.5, 8.0, 5.0, 0.0], ["ramp", 18.0, 6.0, 5.0, 0.0],
				["hop", 0.68, -1.6, 8.0, 4.6, 2.0], ["fill", 6.0]]
		2:
			return [["ramp", 20.0, 5.0, 5.0, 3.0], ["hop", 0.72, -2.1, 7.0, 4.4, -3.0], ["ramp", 14.0, 5.0, 5.0, 3.0],
				["hop", 0.74, -2.2, 7.0, 4.4, -3.0], ["ramp", 14.0, 5.0, 5.0, 3.0], ["fill", 5.0]]
		3:
			return [["ramp", 16.0, 4.0, 6.0, 0.0], ["hop", 0.66, -2.0, 12.0, 3.2, 0.0], ["hop", 0.70, -2.0, 12.0, 3.2, 0.0],
				["hop", 0.72, -2.0, 12.0, 3.2, 0.0], ["hop", 0.76, -2.0, 8.0, 4.0, 0.0], ["fill", 5.0]]
		4:
			return [["ramp", 10.0, 5.0, 4.0, 0.0], ["hop", 0.58, -0.8, 5.0, 4.4, 2.0], ["hop", 0.58, -0.8, 5.0, 4.4, -2.0],
				["hop", 0.60, -0.8, 5.0, 4.4, 2.0], ["hop", 0.60, -0.8, 5.0, 4.4, -2.0], ["ramp", 16.0, 5.0, 5.0, 0.0], ["fill", 5.0]]
		5:
			return [["ramp", 18.0, 5.0, 6.0, 0.0], ["hop", 0.78, -2.0, 9.0, 4.4, 0.0], ["ramp", 14.0, 5.0, 6.0, 0.0],
				["hop", 0.80, -2.2, 9.0, 4.4, 2.0], ["ramp", 12.0, 5.0, 6.0, 0.0], ["hop", 0.78, -2.0, 8.0, 4.4, -2.0], ["fill", 5.0]]
		6:
			return [["ramp", 22.0, 5.0, 6.0, 0.0], ["hop", 0.74, -2.2, 10.0, 4.4, 0.0], ["ramp", 22.0, 5.0, 6.0, -2.0],
				["hop", 0.76, -2.2, 8.0, 4.4, 2.0], ["fill", 5.0]]
		7:
			return [["ramp", 24.0, 5.0, 5.0, 2.0], ["hop", 0.70, -2.4, 8.0, 4.4, -3.0], ["ramp", 24.0, 5.0, 5.0, 2.0],
				["hop", 0.72, -2.4, 8.0, 4.4, -2.0], ["fill", 5.0]]
		8:
			return [["ramp", 20.0, 6.0, 6.0, 0.0], ["hop", 0.64, -1.8, 10.0, 5.0, 0.0], ["ramp", 20.0, 6.0, 6.0, 0.0],
				["hop", 0.66, -1.8, 8.0, 5.0, 2.0], ["fill", 5.0]]
	return [["ramp", 30.0, 6.0, 6.0, 0.0], ["hop", 0.68, -2.5, 10.0, 5.0, 0.0], ["ramp", 30.0, 6.0, 6.0, 0.0],
		["hop", 0.72, -2.5, 10.0, 5.0, 0.0], ["ramp", 24.0, 6.0, 6.0, 0.0], ["fill", 5.0]]


# ---- the flow line ---------------------------------------------------------------------------------------------

## A level deck that keeps a rider's speed (a FlowSurface with no grade), chevrons optional.
func _fdeck(top: Vector3, size: Vector3, chevrons: bool = true) -> FlowSurface:
	var body := FlowSurface.new()
	body.gain = 0.0
	body.cap = 30.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	if chevrons:
		var bm := BoxMesh.new()
		bm.size = size
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = FlowSurface.material(size, 3.0)
		body.add_child(mi)
	else:
		body.add_child(Look.platform_box(size, "main"))
	body.position = top - Vector3(0, size.y * 0.5, 0)
	add_child(body)
	_note_span(top + Vector3(0, 0, size.z * 0.5), top - Vector3(0, 0, size.z * 0.5), size.x)
	return body


## A flow slope between two top-edge middle points (kit.flow_slope_between), noted for the terrain.
func _fslope(a: Vector3, b: Vector3, width: float, cap: float = 28.0) -> FlowSurface:
	var sl: FlowSurface = kit.flow_slope_between(a, b, width, 0.8, {"cap": cap})
	_note_span(a, b, width)
	return sl


## y on the straight line a -> b at world z.
func _line_y(a: Vector3, b: Vector3, z: float) -> float:
	var t: float = clampf((z - a.z) / (b.z - a.z), 0.0, 1.0)
	return lerpf(a.y, b.y, t)


## Simulates a flight off a launch arc (the Player's air rules, the rings' boosts and an optional draft box)
## and returns {"rings": ring centres, "land": where it comes down through y_land, "path": points, "speed": m/s}.
## `ring_times` are seconds after launch; each ring adds `add` (+12% per link) up to the cap.
func _flight(arc: LaunchArc, hs: float, y_land: float, ring_times: Array[float], add: float, draft: Dictionary = {}) -> Dictionary:
	var t: MovementTuning = _tuning
	var v: Vector3 = arc.launch_velocity(hs)
	var p: Vector3 = arc.lip()
	var fwd: Vector3 = arc.forward()
	var dt: float = 1.0 / 60.0
	var clock: float = 0.0
	var k: int = 0
	var rings: Array[Vector3] = []
	var path := PackedVector3Array()
	path.append(p)
	while clock < 6.0:
		var g: float = t.gravity_rise if v.y > 0.0 else t.gravity_fall
		v.y = maxf(v.y - g * dt, -t.max_fall_speed)
		var h := Vector3(v.x, 0.0, v.z)
		var sp: float = h.length()
		if sp > t.max_speed:
			h = h.normalized() * move_toward(sp, t.max_speed, t.air_overspeed_drag * dt)
			v.x = h.x
			v.z = h.z
		if not draft.is_empty():
			var c: Vector3 = draft["center"]
			var sz: Vector3 = draft["size"]
			if absf(p.x - c.x) <= sz.x * 0.5 and absf(p.y - c.y) <= sz.y * 0.5 and absf(p.z - c.z) <= sz.z * 0.5:
				v = AuroraDraft.glide_step(v, fwd, dt, DRAFT_SINK, DRAFT_PUSH, DRAFT_CAP)
		p += v * dt
		clock += dt
		path.append(p)
		if k < ring_times.size() and clock >= ring_times[k]:
			rings.append(p + Vector3(0, 0.9, 0))
			var hh := Vector3(v.x, 0.0, v.z)
			var hs2: float = hh.length()
			var nh: float = minf(hs2 + add * FlowChain.bonus(k + 1), maxf(30.0, hs2))
			if hs2 > 0.01:
				v.x *= nh / hs2
				v.z *= nh / hs2
			k += 1
		if clock > 0.3 and v.y < 0.0 and p.y <= y_land:
			break
	return {"rings": rings, "land": p, "path": path, "speed": Vector2(v.x, v.z).length()}


## Strings AuroraMotes along `pts`.
func _motes(pts: PackedVector3Array) -> void:
	var m := AuroraMotes.new()
	m.setup(pts)
	add_child(m)


## Motes on a line a -> b every `step` metres, `up` above the floor.
func _mote_line(a: Vector3, b: Vector3, step: float = 7.0, up: float = 1.4) -> void:
	var pts := PackedVector3Array()
	var n: int = maxi(int(a.distance_to(b) / step), 1)
	for i: int in n + 1:
		pts.append(a.lerp(b, float(i) / float(n)) + Vector3(0, up, 0))
	_motes(pts)


func _flow(k: int) -> void:
	match k:
		1:
			_flow_1()
		2:
			_flow_2()
		3:
			_flow_3()
		7:
			_flow_7()
		9:
			_flow_9()
		4:
			_flow_4()
		5:
			_flow_5()
		6:
			_flow_6()
		8:
			_flow_8()
		_:
			_flow_generic(k)


## Stage 1: three boost gates on a flat run, then one long slope down to the plaza.
func _flow_1() -> void:
	var y0: float = plaza_y[0]
	var y1: float = plaza_y[1]
	_fdeck(Vector3(0, y0, -25.0), Vector3(12.0, 1.0, 34.0))
	var gp: Array[Vector3] = [Vector3(0, y0, -14), Vector3(0, y0, -24), Vector3(0, y0, -34)]
	kit.boost_chain(gp, 18.0, 6.0, {"speed_end": 24.0})
	_fslope(Vector3(0, y0, -42), Vector3(0, y1, -102), 10.0)
	_mote_line(Vector3(0, y0, -42), Vector3(0, y1, -102), 6.0, 1.3)
	if route_variant == 1:
		r_flow([Vector3(0, y0, -2), gp[0], gp[1], gp[2], Vector3(0, y0, -42), Vector3(0, y1, -102), Vector3(0, y1, PLAZA_Z[1])])


## Stages with no bespoke line yet: gates, then one slope to the plaza (replaced as the kit lands).
func _flow_generic(k: int) -> void:
	var z0: float = PLAZA_Z[k - 1]
	var z1: float = PLAZA_Z[k]
	var y0: float = plaza_y[k - 1]
	var y1: float = plaza_y[k]
	var ze: float = z0 - 40.0
	_fdeck(Vector3(0, y0, (z0 - 8.0 + ze) * 0.5), Vector3(12.0, 1.0, absf(z0 - 8.0 - ze)))
	var gp: Array[Vector3] = [Vector3(0, y0, z0 - 14), Vector3(0, y0, z0 - 24), Vector3(0, y0, z0 - 34)]
	kit.boost_chain(gp, 18.0, 6.0, {"speed_end": 24.0})
	_fslope(Vector3(0, y0, ze), Vector3(0, y1, z1 + 8.0), 10.0)
	if route_variant == 1:
		r_flow([Vector3(0, y0, z0 - 2.0), gp[0], gp[1], gp[2], Vector3(0, y0, ze), Vector3(0, y1, z1 + 8.0), Vector3(0, y1, z1)])


## Stage 4: gates onto the frozen tarn, then a slalom of eight rings skimming the ice.
func _flow_4() -> void:
	var a := Vector3(0, plaza_y[3], PLAZA_Z[3] - 8.0)
	var b := Vector3(0, plaza_y[4], PLAZA_Z[4] + 8.0)
	_fslope(a, b, 16.0)
	var gp: Array[Vector3] = []
	for z: float in [-374.0, -384.0, -394.0]:
		gp.append(Vector3(0, _line_y(a, b, z), z))
	kit.boost_chain(gp, 18.0, 6.0, {"speed_end": 24.0})
	var rc: Array[Vector3] = []
	for i: int in 8:
		var z: float = -402.0 - 8.0 * float(i)
		rc.append(Vector3(4.0 * sin(TAU * float(i) * 8.0 / 72.0) * (1.0 - float(i) / 8.0), _line_y(a, b, z) + 1.1, z))
	kit.ring_line(rc, {"add_speed": 3.0, "radius": 2.5})
	var mp := PackedVector3Array()
	for i: int in 7:
		mp.append((rc[i] + rc[i + 1]) * 0.5 + Vector3(0, 0.2, 0))
	_motes(mp)
	if route_variant == 1:
		var pts: Array[Vector3] = [Vector3(0, plaza_y[3], PLAZA_Z[3] - 2.0)]
		pts.append_array(gp)
		pts.append_array(rc)
		pts.append(Vector3(0, plaza_y[4], PLAZA_Z[4]))
		r_flow(pts)


const CHUTE_SPEED: float = 28.0


## Stage 5: gates, a steep chute, a flat run to the foot of a launch arc, and four rings along the flight over
## the crevasse to a landing deck that runs into the plaza.
func _flow_5() -> void:
	var y0: float = plaza_y[4]
	var z0: float = PLAZA_Z[4]
	_fdeck(Vector3(0, y0, z0 - 20.0), Vector3(12.0, 1.0, 24.0))
	var gp: Array[Vector3] = [Vector3(0, y0, z0 - 14.0), Vector3(0, y0, z0 - 24.0)]
	kit.boost_chain(gp, 20.0, 6.0, {"speed_end": 24.0})
	var c0 := Vector3(0, y0, z0 - 32.0)
	var c1 := Vector3(0, y0 - 4.6, z0 - 53.0)
	_fslope(c0, c1, 10.0, CHUTE_SPEED)
	_fdeck(Vector3(0, c1.y, c1.z - 8.0), Vector3(10.0, 1.0, 16.0))
	var foot := Vector3(0, c1.y, c1.z - 16.0)
	var arc: LaunchArc = kit.launch_arc(foot, 0.0, 24.0, 8.0, 9.0, {"cap": CHUTE_SPEED})
	var yl: float = plaza_y[5]
	var times5: Array[float] = [0.25, 0.5, 0.75, 1.0]
	var fl: Dictionary = _flight(arc, CHUTE_SPEED, yl, times5, 3.0)
	var land: Vector3 = fl["land"]
	var deck_z0: float = land.z + 9.0
	var deck_z1: float = PLAZA_Z[5] + 8.0
	_fdeck(Vector3(0, yl, (deck_z0 + deck_z1) * 0.5), Vector3(16.0, 1.2, deck_z0 - deck_z1))
	kit.ring_line(fl["rings"] as Array[Vector3], {"add_speed": 3.0, "radius": 2.6})
	_motes(fl["path"] as PackedVector3Array)
	if route_variant == 1:
		r_flow([Vector3(0, y0, z0 - 2.0), gp[0], gp[1], c0, c1, Vector3(c1.x, c1.y, c1.z - 12.0)])
		r_launch(arc, Vector3(0, yl, land.z - 3.0))
		r_flow([Vector3(0, yl, land.z - 3.0), Vector3(0, yl, PLAZA_Z[5])])


const DRAFT_SIZE := Vector3(14.0, 14.0, 44.0)
const DRAFT_PUSH: float = 5.0
const DRAFT_CAP: float = 24.0
const DRAFT_SINK: float = -2.2


## Stage 6: gates and a launch arc over a wide chasm, an Aurora Draft that carries the flight across, rings in
## its stream, and a far shelf that runs down to the plaza.
func _flow_6() -> void:
	var y0: float = plaza_y[5]
	var z0: float = PLAZA_Z[5]
	_fdeck(Vector3(0, y0, z0 - 19.0), Vector3(12.0, 1.0, 22.0))
	var gp: Array[Vector3] = [Vector3(0, y0, z0 - 12.0), Vector3(0, y0, z0 - 22.0)]
	kit.boost_chain(gp, 18.0, 6.0, {"speed_end": 21.0})
	var foot := Vector3(0, y0, z0 - 30.0)
	var arc: LaunchArc = kit.launch_arc(foot, 0.0, 22.0, 8.0, 10.0, {"cap": 21.0})
	var lip: Vector3 = arc.lip()
	var dc := Vector3(0, lip.y + 1.0, lip.z - 22.0)
	var spec: Dictionary = {"center": dc, "size": DRAFT_SIZE}
	var yl: float = plaza_y[6] + 2.5
	var times6: Array[float] = [0.5, 0.85, 1.2, 1.55, 1.9]
	var fl: Dictionary = _flight(arc, 21.0, yl, times6, 2.0, spec)
	var land: Vector3 = fl["land"]
	var d: AuroraDraft = AuroraDraft.new()
	d.size = DRAFT_SIZE
	d.push = DRAFT_PUSH
	d.cap = DRAFT_CAP
	d.sink = DRAFT_SINK
	kit.root.add_child(d)
	d.position = dc
	kit.ring_line(fl["rings"] as Array[Vector3], {"add_speed": 2.0, "radius": 2.8})
	_motes(fl["path"] as PackedVector3Array)
	var shelf_z0: float = land.z + 8.0
	var shelf_z1: float = PLAZA_Z[6] + 8.0 + 30.0
	_fdeck(Vector3(0, yl, (shelf_z0 + shelf_z1) * 0.5), Vector3(16.0, 1.2, maxf(shelf_z0 - shelf_z1, 1.0)))
	_fslope(Vector3(0, yl, shelf_z1), Vector3(0, plaza_y[6], PLAZA_Z[6] + 8.0), 12.0)
	if route_variant == 1:
		r_flow([Vector3(0, y0, z0 - 2.0), gp[0], gp[1], Vector3(0, y0, z0 - 26.0)])
		r_launch(arc, Vector3(0, yl, land.z - 3.0))
		r_flow([Vector3(0, yl, land.z - 3.0), Vector3(0, yl, shelf_z1), Vector3(0, plaza_y[6], PLAZA_Z[6] + 8.0), Vector3(0, plaza_y[6], PLAZA_Z[6])])


## A half-pipe from the end of a flat flow run, carved wall to wall (rim guards on).
func _pipe(start: Vector3, end: Vector3, width: float = 12.0, depth: float = 2.6, opts: Dictionary = {}) -> HalfPipe:
	var pipe: HalfPipe = kit.halfpipe(start, end, width, depth, opts)
	_note_span(start, end, width + 4.0)
	return pipe


## Stage 2 (PINE RUN): two gates, then a long half-pipe carved down through the pines.
func _flow_2() -> void:
	var y0: float = plaza_y[1]
	var z0: float = PLAZA_Z[1]
	_fdeck(Vector3(0, y0, z0 - 20.0), Vector3(12.0, 1.0, 24.0))
	var gp: Array[Vector3] = [Vector3(0, y0, z0 - 12.0), Vector3(0, y0, z0 - 22.0)]
	kit.boost_chain(gp, 18.0, 6.0, {"speed_end": 22.0})
	var pipe: HalfPipe = _pipe(Vector3(0, y0, z0 - 32.0), Vector3(0, plaza_y[2], PLAZA_Z[2] + 8.0), 12.0, 2.6, {"flat": 0.2})
	if route_variant == 1:
		var run: Array[Vector3] = [Vector3(0, y0, z0 - 2.0), gp[0], gp[1], Vector3(0, y0, z0 - 32.0)]
		r_flow(run)
		r_flow(pipe.carve_points(3, 0.55))
		var out: Array[Vector3] = [pipe.centre_point(1.0), Vector3(0, plaza_y[2], PLAZA_Z[2])]
		r_flow(out)


## Stage 3 (RIDGE RAILS): gates, then two ridge rails one after the other (rail to rail) over a gully slope
## that catches anyone who misses (it runs on to the plaza, a little slower).
func _flow_3() -> void:
	var y0: float = plaza_y[2]
	var z0: float = PLAZA_Z[2]
	_fdeck(Vector3(0, y0, z0 - 23.0), Vector3(12.0, 1.0, 30.0))
	var gp: Array[Vector3] = [Vector3(0, y0, z0 - 14.0), Vector3(0, y0, z0 - 24.0)]
	kit.boost_chain(gp, 20.0, 6.0, {"speed_end": 24.0})
	var ga := Vector3(0, y0, z0 - 38.0)
	var gb := Vector3(0, plaza_y[3], PLAZA_Z[3] + 8.0)
	_fslope(ga, gb, 12.0, 26.0)
	var r1: Array[Vector3] = [Vector3(0, y0 + 1.1, z0 - 44.0), Vector3(0, y0 - 0.2, z0 - 58.0), Vector3(-3.0, y0 - 2.2, z0 - 74.0), Vector3(-5.0, y0 - 4.4, z0 - 88.0)]
	var rail1: GrindRail = kit.rail(r1, {"post_to_y": y0 - 16.0})
	var tan1: Vector3 = (r1[3] - r1[2]).normalized()
	var s2: Vector3 = r1[3] + tan1 * 4.5 + Vector3(0, -1.7, 0)
	var r2: Array[Vector3] = [s2, Vector3(s2.x + 2.0, s2.y - 1.1, s2.z - 10.0), Vector3(s2.x + 6.0, s2.y - 2.9, s2.z - 22.0), Vector3(s2.x + 8.0, s2.y - 4.5, s2.z - 34.0)]
	var rail2: GrindRail = kit.rail(r2, {"post_to_y": y0 - 20.0})
	_mote_line(r1[0] + Vector3(0, 1.0, 0), r2[3] + Vector3(0, 1.0, 0), 8.0, 1.0)
	if route_variant == 1:
		var run: Array[Vector3] = [Vector3(0, y0, z0 - 2.0), gp[0], gp[1], Vector3(0, y0, z0 - 36.0)]
		r_flow(run)
		r_rail(rail1, rail1.start_point(), {"from": Vector3(0, y0 - 0.1, z0 - 40.0), "leave": r1[3], "chain_next": true, "to": rail2.start_point()})
		r_rail(rail2, rail2.start_point(), {"chain": true, "to": Vector3(0, plaza_y[3], PLAZA_Z[3] + 2.0)})


## Stage 7 (TWIN PIPES): gates, a half-pipe, a flat run, then a ridge rail over a slope into the plaza.
func _flow_7() -> void:
	var y0: float = plaza_y[6]
	var z0: float = PLAZA_Z[6]
	_fdeck(Vector3(0, y0, z0 - 20.0), Vector3(12.0, 1.0, 24.0))
	var gp: Array[Vector3] = [Vector3(0, y0, z0 - 12.0), Vector3(0, y0, z0 - 22.0)]
	kit.boost_chain(gp, 18.0, 6.0, {"speed_end": 22.0})
	var p0 := Vector3(0, y0, z0 - 32.0)
	var p1 := Vector3(0, y0 - 8.0, z0 - 72.0)
	var pipe: HalfPipe = _pipe(p0, p1, 12.0, 2.6, {"flat": 0.2})
	_fdeck(Vector3(0, p1.y, p1.z - 6.0), Vector3(12.0, 1.0, 12.0))
	var sa := Vector3(0, p1.y, p1.z - 12.0)
	var sb := Vector3(0, plaza_y[7], PLAZA_Z[7] + 8.0)
	_fslope(sa, sb, 12.0, 26.0)
	var r1: Array[Vector3] = [Vector3(0, sa.y + 1.1, sa.z - 4.0), Vector3(0, sa.y - 0.4, sa.z - 14.0), Vector3(3.0, sa.y - 2.0, sa.z - 24.0), Vector3(0, sa.y - 3.4, sa.z - 32.0)]
	var rail1: GrindRail = kit.rail(r1, {"post_to_y": plaza_y[7] - 6.0})
	_mote_line(r1[0] + Vector3(0, 1.0, 0), r1[3] + Vector3(0, 1.0, 0), 7.0, 1.0)
	if route_variant == 1:
		var run: Array[Vector3] = [Vector3(0, y0, z0 - 2.0), gp[0], gp[1], p0]
		r_flow(run)
		r_flow(pipe.carve_points(2, 0.55))
		var onto: Array[Vector3] = [pipe.centre_point(1.0), Vector3(0, p1.y, sa.z + 2.0)]
		r_flow(onto)
		r_rail(rail1, rail1.start_point(), {"from": Vector3(0, sa.y, sa.z - 0.5), "to": Vector3(0, plaza_y[7], PLAZA_Z[7] + 1.0)})


const FIN_SPEED: float = 25.0


## Stage 9 (THE CASCADE): the pure-flow finale. Gates, a long half-pipe, a launch arc over the cascade with a chain of
## eight rings flown along the arc, and a landing slope that runs into the finish.
func _flow_9() -> void:
	var y0: float = plaza_y[8]
	var z0: float = PLAZA_Z[8]
	_fdeck(Vector3(0, y0, z0 - 20.0), Vector3(12.0, 1.0, 24.0))
	var gp: Array[Vector3] = [Vector3(0, y0, z0 - 12.0), Vector3(0, y0, z0 - 22.0)]
	kit.boost_chain(gp, 20.0, 6.0, {"speed_end": 24.0})
	var p0 := Vector3(0, y0, z0 - 32.0)
	var p1 := Vector3(0, y0 - 9.0, z0 - 84.0)
	var pipe: HalfPipe = _pipe(p0, p1, 12.0, 2.6, {"flat": 0.2})
	_fdeck(Vector3(0, p1.y, p1.z - 8.0), Vector3(12.0, 1.0, 16.0))
	var foot := Vector3(0, p1.y, p1.z - 12.0)
	var arc: LaunchArc = kit.launch_arc(foot, 0.0, 22.0, 8.0, 10.0, {"cap": FIN_SPEED})
	var yl: float = plaza_y[9] + 2.0
	var times9: Array[float] = [0.12, 0.26, 0.4, 0.54, 0.68, 0.82, 0.96, 1.1]
	var fl: Dictionary = _flight(arc, FIN_SPEED, yl, times9, 1.5)
	var land: Vector3 = fl["land"]
	var dz0: float = land.z + 10.0
	var dz1: float = PLAZA_Z[9] + 8.0 + 10.0
	_fdeck(Vector3(0, yl, (dz0 + dz1) * 0.5), Vector3(16.0, 1.2, maxf(dz0 - dz1, 1.0)))
	_fslope(Vector3(0, yl, dz1), Vector3(0, plaza_y[9], PLAZA_Z[9] + 8.0), 14.0)
	kit.ring_line(fl["rings"] as Array[Vector3], {"add_speed": 1.5, "radius": 2.8})
	_motes(fl["path"] as PackedVector3Array)
	if route_variant == 1:
		var run: Array[Vector3] = [Vector3(0, y0, z0 - 2.0), gp[0], gp[1], p0]
		r_flow(run)
		r_flow(pipe.carve_points(3, 0.55))
		var onto: Array[Vector3] = [pipe.centre_point(1.0), Vector3(0, p1.y, foot.z - 4.0)]
		r_flow(onto)
		r_launch(arc, Vector3(0, yl, land.z - 3.0))
		var home: Array[Vector3] = [Vector3(0, yl, land.z - 3.0), Vector3(0, yl, dz1), Vector3(0, plaza_y[9], PLAZA_Z[9] + 8.0)]
		r_flow(home)



## Stage 8: gates, one long slope down the moon meadow with a slalom of six rings along it.
func _flow_8() -> void:
	var y0: float = plaza_y[7]
	var z0: float = PLAZA_Z[7]
	var y1: float = plaza_y[8]
	_fdeck(Vector3(0, y0, z0 - 24.0), Vector3(12.0, 1.0, 32.0))
	var gp: Array[Vector3] = [Vector3(0, y0, z0 - 14.0), Vector3(0, y0, z0 - 24.0)]
	kit.boost_chain(gp, 20.0, 6.0, {"speed_end": 24.0})
	var a := Vector3(0, y0, z0 - 40.0)
	var b := Vector3(0, y1, PLAZA_Z[8] + 8.0)
	_fslope(a, b, 14.0)
	var rc: Array[Vector3] = []
	for i: int in 6:
		var z: float = a.z - 10.0 - 9.0 * float(i)
		rc.append(Vector3(3.5 * sin(TAU * float(i) / 5.0), _line_y(a, b, z) + 1.1, z))
	kit.ring_line(rc, {"add_speed": 2.5, "radius": 2.6})
	if route_variant == 1:
		var pts: Array[Vector3] = [Vector3(0, y0, z0 - 2.0), gp[0], gp[1], a]
		pts.append_array(rc)
		pts.append(b)
		pts.append(Vector3(0, y1, PLAZA_Z[8]))
		r_flow(pts)



# ---- look: environment, sky, mountain ---------------------------------------------------------------------------

func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_sun = n as DirectionalLight3D
			else:
				_fill = n as DirectionalLight3D
	_env.fog_density = 0.0021
	_env.fog_aerial_perspective = 0.3
	_env.fog_sky_affect = 0.1
	_env.fog_sun_scatter = 0.05
	_env.glow_intensity = 0.85
	_env.glow_bloom = 0.07
	_env.glow_hdr_threshold = 1.05
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.06
	# the key light is the aurora's cold glow low ahead, the fill its green wash from behind
	_sun.light_color = Color(0.55, 0.88, 0.98)
	_sun.light_energy = 1.05
	_sun.rotation_degrees = Vector3(-26, 172, 0)
	_fill.light_color = Color(0.4, 1.0, 0.75)
	_fill.light_energy = 0.4
	_fill.rotation_degrees = Vector3(-30, -10, 0)
	sky = AuroraSky.attach(self, _env, _sun, _fill, PLAZA_Z[9])


## The mountain: terrain, pines, boulders, the frozen lake past the finish, the ice crown of the finish.
func _surroundings() -> void:
	deco.finish(PLAZA_Z[9], plaza_y[9])
	deco.set_basin((PLAZA_Z[3] + PLAZA_Z[4]) * 0.5, 80.0, 62.0, plaza_y[4] - 4.0)
	deco.build_terrain(150.0, PLAZA_Z[9] - 760.0)
	deco.pines(130.0, PLAZA_Z[9] - 300.0, 150, 150.0)
	deco.boulders(130.0, PLAZA_Z[9] - 300.0, 26, 150.0)
	# the frozen tarn under stage 4 and the lake the mountain empties into
	var tarn_z: float = (PLAZA_Z[3] + PLAZA_Z[4]) * 0.5
	deco.ice_sheet(Vector3(0, plaza_y[4] - 4.0, tarn_z), Vector2(130.0, 150.0))
	deco.ice_sheet(Vector3(0, plaza_y[9] - 12.0, PLAZA_Z[9] - 330.0), Vector2(900.0, 640.0))
	# the finish: a crown of crystals and a pale fountain of motes
	var fin_lamp := OmniLight3D.new()
	fin_lamp.light_color = Color(0.6, 1.0, 0.85)
	fin_lamp.light_energy = 2.5
	fin_lamp.omni_range = 26.0
	fin_lamp.position = _finish_pos + Vector3(0, 5.0, 2.0)
	add_child(fin_lamp)
	deco.crystals(_finish_pos + Vector3(-6.5, 0, 3.0), AuroraFx.GREEN, 1.5)
	deco.crystals(_finish_pos + Vector3(6.5, 0, 3.0), AuroraFx.VIOLET, 1.5)
	var crown: GPUParticles3D = AuroraFx.rising(Vector3(8, 2, 6), 30, AuroraFx.GREEN)
	crown.position = _finish_pos + Vector3(0, 1.0, 2.0)
	add_child(crown)
	for col: Color in [AuroraFx.GREEN, AuroraFx.VIOLET, AuroraFx.TEAL]:
		var b: GPUParticles3D = AuroraFx.finale(col, 70)
		b.position = _finish_pos + Vector3(0, 1.0, 0)
		add_child(b)
		_finish_bursts.append(b)


var _finish_bursts: Array[GPUParticles3D] = []


func _finish_sequence() -> void:
	for b: GPUParticles3D in _finish_bursts:
		b.restart()
		b.emitting = true
	# SOUND: aurora_finish - the sky answers: a rising chord and a shimmer of bells
	WorldAudio.at(self, "aurora_finish", _finish_pos + Vector3(0, 3.0, 0), 1.0, 120.0)
	await get_tree().create_timer(0.9).timeout
