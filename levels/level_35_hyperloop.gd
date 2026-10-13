extends LevelBase
## 35. HYPERLOOP - the third FLOW level (campaign index 33). Chrome transit tubes and mag-rails threading
## a dawn megastructure: white ceramic decks over a sea of cloud, glass tubes streaking with trains, a
## spire at the centre of it all, and a rose-gold sun on the horizon. Clean white and cool cyan - not
## Neon City's rain, not Orbital Drift's dark metal.
##
## The course is a long descending SPIRAL round the central spire: ten stages, every one turning 30
## degrees at a HUB (a round station plate with a checkpoint). Between hubs the track is a run of ISLANDS
## (10 m decks: a FLOW slab down the middle that keeps your speed, plain white lanes at the sides)
## separated by PITS (a glowing track bed 3.4 m down, with a mag-lift pad that throws a faller back up
## onto the next island - nothing here is a death trap).
##
## Two lines through the same track:
##  - the SAFE line (route 0) keeps to the side lanes and hops each pit on stepping plates (hardest jump
##    <= 82% of max reach, every landing >= 2 m, nothing hazardous to wait for; two pits carry a transit pod);
##  - the FLOW line (route 1) takes the middle at 18-30 m/s: a chain of three boost gates off every hub,
##    launch arcs over the pits with a 4-ring chain in the air (the pit is sized from the flight), grind
##    rails, open tubes (half-pipes), a long flow slope and the finale's Great Ring. Missing any of it
##    drops you onto the safe line.
##
##  1 Terminal Concourse   gates, a first launch arc and a ring chain
##  2 Ring Road            an arc, then a long flow slope down to the hub
##  3 Mag-Rail Yard        an arc, then a long grind rail over a wide pit
##  4 Loop Tube            an arc into an open tube (half-pipe) to carve
##  5 Pod Station          an arc; the safe line crosses on a transit pod
##  6 Switchyard           an arc, then a rail-to-rail switch
##  7 Spire Lift           two launches UP onto higher decks
##  8 Great Tube           an arc into a longer, wider tube
##  9 Overdrive            an arc, then a long rail, flat out
## 10 THE GREAT RING       finale - a wide launch, then a plunge down a long slope through three great
##                         hoops and a line of rings to the finish
##
## Hyperloop mechanics (own scripts): HyperloopPod (rideable pods), HyperloopPulse (lanes of chevron
## lights that show the way), HyperloopTrain (trains in the far tubes). Route variants for the bot:
## 0 = the safe line, 1 = the flow line.

const WHITE := Color(0.95, 0.97, 1.0)
const CYAN := Color(0.20, 0.88, 1.0)
const CORAL := Color(1.0, 0.60, 0.48)

## Testing aid: build every stage but start the player (and the bot's route) at stage N. 0 = off.
const DEV_START: int = 0
## Testing aid: stop building after stage N (a finish gate goes at its end). 0 = build them all.
const DEV_LAST: int = 0

const HUB_R: float = 8.4
## Island half-length reserved inside a hub (the island ends this far before the hub centre).
const HUB_IN: float = 6.2
const ISL_W: float = 9.6
const ISL_THICK: float = 0.8
## Lateral line (m) the safe route hops the pits along.
const LANE: float = 4.0
const STONE: float = 2.6
## The middle flow slab of an island, and the plain side lanes either side of it.
const SLAB_W: float = 5.6
const SIDE_W: float = 2.0
## The launch arcs over the pits, and what the ring chain does in the air.
const RAMP_PITCH: float = 25.0
const RAMP_LEN: float = 9.0
const RAMP_W: float = 5.0
## How far past the pit's near edge the flight is meant to come down.
const PEN: float = 8.0
const RING_ADD: float = 4.0
const RING_CAP: float = 30.0
const RING_R: float = 2.4
## Chain length assumed when the rings of a flight are reached (gates and earlier rings count).
const CHAIN0: int = 5
## The speed and hop the rail-to-rail switch is laid for.
const SWITCH_SPEED: float = 27.0
const SWITCH_HOP: float = 4.0

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var _tuning: MovementTuning
var deco: HyperloopDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order.
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Every deck: {"top": world centre of the top, "size": Vector3 (x across, thick, z along), "yaw": deg}
var _decks: Array[Dictionary] = []
## World centres (top) of every hub, hub 0 = the start plate.
var _hubs: Array[Vector3] = []
## The stage frames (world origin, yaw) in build order, for scenery.
var _stage_frames: Array[Dictionary] = []
## The stage length / drop figures, printed by the tests that care.
var stage_lengths: Array[float] = []
## The flow route's polyline being built (world points), and every launch arc in build order.
var _poly: Array[Vector3] = []
var _arcs: Array[LaunchArc] = []
var _rails: Array[GrindRail] = []
var _pipes: Array[HalfPipe] = []
var _pods: Array[HyperloopPod] = []
var _flow_speed: float = 25.0


func _configure() -> void:
	theme_id = "hyperloop"
	music_track = "hyperloop"
	kill_y = -260.0
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


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## The validator's max reach (m) for a plain running jump that lands `dy` higher (test_m's measure).
func _reach(dy: float) -> float:
	var land: Vector3 = Ballistics.landing_point(_tuning, Vector3.ZERO, Vector3(0, _tuning.jump_velocity, -_tuning.max_speed), dy)
	return absf(land.z)


## How far the near edge of a landing lies past the takeoff's front edge (less the 0.35 m inset) when
## the jump needs `pct` of max reach by test_m's measure (to 0.4 m past the near edge, scanned in
## 0.2 m steps: rounded up, so it needs `pct` to `pct` + 3%).
func _e(pct: float, dy: float) -> float:
	var m: float = pct * _reach(dy)
	var k: int = ceili((m - 0.4) / 0.2 - 0.001)
	return float(k) * 0.2 - 0.03


## Local top centre of a landing `sz` deep straight ahead (-z) of `a`, placed so that the jump from
## 0.35 m inside a's front edge needs `pct` of max reach (see _e).
func _ahead(a: Dictionary, pct: float, dy: float, sz: float, dx: float = 0.0) -> Vector3:
	var ac: Vector3 = a["c"]
	var front: float = ac.z - float(a["hz"])
	return Vector3(ac.x + dx, ac.y + dy, front + 0.35 - _e(pct, dy) - sz * 0.5)


## A walkable deck (local top centre `c`, sx across, sz along).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = ISL_THICK, record: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if record:
		_decks.append({"top": _w(c), "size": Vector3(sx, thick, sz), "yaw": _yaw})
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## An island whose near end is at local z0 (negative), `length` long (-z), top height `y` at the near
## end and `slope` metres lower at the far end. The middle is a FLOW slab (it keeps your speed), the
## sides are plain white lanes (the safe route walks them; they never speed you up).
func _island(z0: float, length: float, y: float, slope: float = 0.0) -> Dictionary:
	var zc: float = z0 - length * 0.5
	var y_end: float = y - slope
	if slope <= 0.001:
		for sx: float in [-1.0, 1.0]:
			_blk(Vector3(sx * (SLAB_W * 0.5 + SIDE_W * 0.5), y, zc), SIDE_W, length, "main", ISL_THICK, false)
		kit.flow_slope_between(_w(Vector3(0, y, z0)), _w(Vector3(0, y, z0 - length)), SLAB_W)
	else:
		var seg: float = sqrt(length * length + slope * slope)
		var pitch: float = rad_to_deg(atan2(slope, length))
		for sx: float in [-1.0, 1.0]:
			kit.ramp(_w(Vector3(sx * (SLAB_W * 0.5 + SIDE_W * 0.5), (y + y_end) * 0.5, zc)), Vector3(SIDE_W, ISL_THICK, seg), -pitch, _yaw, "main")
		kit.flow_slope_between(_w(Vector3(0, y, z0)), _w(Vector3(0, y_end, z0 - length)), SLAB_W)
	_decks.append({"top": _w(Vector3(0, (y + y_end) * 0.5, zc)), "size": Vector3(ISL_W, ISL_THICK, length), "yaw": _yaw})
	return {"c": Vector3(0, y_end, zc), "hx": ISL_W * 0.5, "hz": length * 0.5, "y0": y, "slope": slope}


## A small stepping plate.
func _plate(c: Vector3) -> Dictionary:
	return _blk(c, STONE, STONE, "accent", 0.6)


## A hop from local point `from` (a takeoff spot) to local point `to`.
func _hop_to(from: Vector3, to: Vector3) -> void:
	if route_variant == 0:
		r_jump(_w(from), _w(to), true)


## The round hub plate (checkpoint station) with its centre top at local `c`.
func _hub(c: Vector3, index: int) -> void:
	kit.disc(_w(c), HUB_R, ISL_THICK, "goal", 0.0)
	_hubs.append(_w(c))
	_decks.append({"top": _w(c), "size": Vector3(HUB_R * 2.0, ISL_THICK, HUB_R * 2.0), "yaw": _yaw, "round": true})
	if index > 0:
		var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
		_cp_world.append(_w(c))
		var fx: Array[GPUParticles3D] = HyperloopFx.cp_burst()
		for p: GPUParticles3D in fx:
			p.position = _w(c) + Vector3(0, 0.6, 0)
			add_child(p)
		_cp_bursts[cp] = fx
		cp.reached.connect(func(which: Checkpoint) -> void:
			if which.index > current_checkpoint:
				# SOUND: hyperloop_checkpoint - a clean rising two-note station chime with a soft whoosh
				WorldAudio.at(self, "hyperloop_checkpoint", which.global_position, 0.9, 40.0)
				for p2: GPUParticles3D in (_cp_bursts[which] as Array):
					p2.restart()
					p2.emitting = true)


# ---- the flight over a pit: what a launch arc + ring chain does, simulated ---------------------------------

## Simulates the flight of a rider leaving the lip (local) at horizontal speed `hs0` (forward = -z),
## passing four rings along the way (each adds RING_ADD x the chain bonus up to RING_CAP), until it
## comes down through `target_y`. Returns {"rings": Array[Vector3] (local centres), "landing": Vector3,
## "time": float, "speed": float}.
func _flight(lip: Vector3, hs0: float, target_y: float, ring_count: int = 4) -> Dictionary:
	var t: MovementTuning = _tuning
	var dt: float = 1.0 / 120.0
	var vy0: float = clampf(hs0 * tan(deg_to_rad(RAMP_PITCH)), 3.0, 18.0)
	# pass 1: the flight time (the vertical motion does not depend on the ring boosts)
	var y: float = lip.y
	var vy: float = vy0
	var total: float = 0.0
	while total < 6.0:
		var g: float = t.gravity_rise if vy > 0.0 else t.gravity_fall
		vy = maxf(vy - g * dt, -t.max_fall_speed)
		y += vy * dt
		total += dt
		if total > 0.3 and vy < 0.0 and y <= target_y:
			break
	# pass 2: along the ground, with the rings
	var times: Array[float] = []
	for i: int in ring_count:
		times.append(total * (0.16 + 0.60 * float(i) / float(maxi(ring_count - 1, 1))))
	var p: Vector3 = lip
	var hs: float = hs0
	vy = vy0
	var clock: float = 0.0
	var k: int = 0
	var rings: Array[Vector3] = []
	while clock < total + 0.05:
		var g2: float = t.gravity_rise if vy > 0.0 else t.gravity_fall
		vy = maxf(vy - g2 * dt, -t.max_fall_speed)
		if hs > t.max_speed:
			hs = move_toward(hs, t.max_speed, t.air_overspeed_drag * dt)
		p.y += vy * dt
		p.z -= hs * dt
		clock += dt
		if k < times.size() and clock >= times[k]:
			rings.append(p + Vector3(0, 0.9, 0))
			hs = minf(hs + RING_ADD * FlowChain.bonus(CHAIN0 + k + 1), maxf(RING_CAP, hs))
			k += 1
	return {"rings": rings, "landing": Vector3(0.0, target_y, p.z), "time": total, "speed": hs}


# ---- pits: a launch arc + rings (flow), stepping plates (safe), a track bed with a mag-lift pad ----------------

## Build the launch arc on island `a`, size the pit from the flight it gives at speed `hs0`, build the next
## island `b_len` long (sloping `b_slope` m down), the stepping plates and the track bed, and both routes.
## `drop` is how much lower the far island's near end is (negative = higher). Returns the far island.
func _cross(a: Dictionary, sx: float, drop: float, b_len: float, hs0: float, b_slope: float = 0.0, pod: bool = false) -> Dictionary:
	var ac: Vector3 = a["c"]
	var front: float = ac.z - float(a["hz"])
	var y_a: float = ac.y
	var pitch_rad: float = deg_to_rad(RAMP_PITCH)
	var foot := Vector3(0.0, y_a, front + RAMP_LEN * cos(pitch_rad))
	var lip := Vector3(0.0, y_a + RAMP_LEN * sin(pitch_rad), front)
	var fl: Dictionary = _flight(lip, hs0, y_a - drop)
	var land: Vector3 = fl["landing"]
	var near_z: float = land.z + PEN
	var pit_w: float = front - near_z
	# --- the flow kit pieces
	var arc: LaunchArc = kit.launch_arc(_w(foot), _yaw, RAMP_PITCH, RAMP_W, RAMP_LEN)
	var ring_pts: Array[Vector3] = []
	for rp: Vector3 in (fl["rings"] as Array):
		ring_pts.append(_w(rp))
	kit.ring_line(ring_pts, {"add_speed": RING_ADD, "radius": RING_R, "cap": RING_CAP})
	_arcs.append(arc)
	_pulse(a, foot.z + 2.5)
	# --- the far island, and the safe way over the pit
	var b: Dictionary = _island(near_z, b_len, y_a - drop, b_slope)
	_safe_across(a, b, sx, drop, pit_w, b_len, b_slope, pod)
	# --- the flow route
	if route_variant == 1:
		_poly.append(_w(Vector3(0.0, y_a, foot.z + 2.5)))
		r_flow(_poly.duplicate())
		r_launch(arc, _w(land + Vector3(0, 0, -1.0)))
		_poly = [_w(land)]
		_flow_speed = float(fl["speed"])
	return b


## The safe line over a pit: stepping plates (or a pod) along lane `sx`, the track bed underneath.
func _safe_across(a: Dictionary, b: Dictionary, sx: float, drop: float, pit_w: float, b_len: float, b_slope: float, pod: bool) -> void:
	var ac: Vector3 = a["c"]
	var front: float = ac.z - float(a["hz"])
	var y_a: float = ac.y
	var near_z: float = front - pit_w
	var grade: float = b_slope / maxf(b_len, 1.0)
	var land_to := Vector3(sx, y_a - drop - 2.0 * grade, near_z - 2.0)
	var from_pt := Vector3(sx, y_a, front + 0.35)
	if pod:
		_pod_across(sx, y_a, drop, front, pit_w, from_pt, land_to)
		_bed(a, b)
		return
	var dy_total: float = -drop
	var n: int = 1
	var gap: float = pit_w
	while n < 8:
		gap = (pit_w - float(n - 1) * STONE) / float(n)
		var dy_hop: float = dy_total / float(n)
		if (gap + 0.75) / _reach(dy_hop) <= 0.72:
			break
		n += 1
	var dyh: float = dy_total / float(n)
	var cursor: float = front
	for i: int in n - 1:
		var pc := Vector3(sx, y_a + dyh * float(i + 1), cursor - gap - STONE * 0.5)
		_plate(pc)
		_hop_to(from_pt, pc)
		from_pt = Vector3(sx, pc.y, pc.z - STONE * 0.5 + 0.35)
		cursor = pc.z - STONE * 0.5
	_hop_to(from_pt, land_to)
	_bed(a, b)


## A transit pod shuttling over the pit along lane `sx` (the safe line's ride). Period 9 s, docked 1.8 s
## at each end; the route waits for a dock with 1.5 s still to run, steps on and steps off.
func _pod_across(sx: float, y_a: float, drop: float, front: float, pit_w: float, from_pt: Vector3, land_to: Vector3) -> void:
	var travel: float = pit_w - 5.8
	var p := HyperloopPod.new()
	p.size = Vector3(2.6, 0.5, 5.0)
	var pts: Array[Vector3] = [Vector3.ZERO, _d(Vector3(0.0, -drop, -travel))]
	p.points = pts
	p.period = 8.0
	p.dwell = 0.22
	p.phase = 0.0
	p.rotation_degrees.y = _yaw
	p.position = _w(Vector3(sx, y_a - 0.25, front - 2.9))
	add_child(p)
	_pods.append(p)
	if route_variant != 0:
		return
	var dock_a: Vector3 = p.position
	var dock_b: Vector3 = p.position + _d(Vector3(0.0, -drop, -travel))
	r_walk(_w(from_pt))
	r_until(func() -> bool: return _docked(p, 1.5))
	r_jump_onto(_w(from_pt), p, Vector3(0, 0.25, 0))
	r_jump_from_ride(p, dock_b, 0.9, _w(land_to), true, Vector3(0, 0.25, 0))
	if dock_a == dock_b:
		return


## The pod is parked at its start end for the next `secs` seconds.
static func _docked(p: HyperloopPod, secs: float) -> bool:
	var s: float = 0.0
	while s <= secs:
		if p.offset_at(Game.course_time + s).length() > 0.03:
			return false
		s += 0.05
	return true


# ---- grind rails across a pit -------------------------------------------------------------------------

## A pit crossed by one long rail (flow) or a rail-to-rail pair (`switch`), `pit_w` wide: the flow route jumps
## on at the near island's end, grinds across and is thrown off onto the far island. The safe route is the
## usual stepping plates.
func _cross_rail(a: Dictionary, sx: float, drop: float, b_len: float, pit_w: float, switch: bool = false) -> Dictionary:
	var ac: Vector3 = a["c"]
	var front: float = ac.z - float(a["hz"])
	var y_a: float = ac.y
	var y_b: float = y_a - drop
	var near_z: float = front - pit_w
	var b: Dictionary = _island(near_z, b_len, y_b)
	_safe_across(a, b, sx, drop, pit_w, b_len, 0.0, false)
	var away: float = -signf(sx)
	var low_y: float = minf(y_a, y_b) - 3.4
	var h0: float = 1.3
	var r1: Array[Vector3] = []
	var r2: Array[Vector3] = []
	var leave := Vector3.ZERO
	var land_to := Vector3(0.0, y_b, near_z - 12.0)
	if not switch:
		var zs: Array[float] = [front + 4.0, front - 4.0, front - pit_w * 0.5, near_z + 4.0, near_z - 3.0]
		var xs: Array[float] = [0.0, 0.0, away * 2.0, away * 0.6, 0.0]
		for i: int in zs.size():
			var t: float = clampf((front + 4.0 - zs[i]) / (pit_w + 10.0), 0.0, 1.0)
			r1.append(Vector3(xs[i], y_a + h0 - drop * t, zs[i]))
	else:
		# rail 1 weaves out a little; the rider jumps off it and is caught by rail 2, which is laid ALONG
		# the flight (a hair under it) and then settles onto the far island
		var j: float = away * 3.0
		var zs1: Array[float] = [front + 4.0, front - 4.0, front - 12.0]
		var xs1: Array[float] = [0.0, 0.0, j]
		for i: int in zs1.size():
			var t1: float = clampf((front + 4.0 - zs1[i]) / (pit_w + 10.0), 0.0, 1.0)
			r1.append(Vector3(xs1[i], y_a + h0 - drop * t1, zs1[i]))
		leave = r1[r1.size() - 1]
		var te: Vector3 = (r1[2] - r1[1]).normalized()
		var vel: Vector3 = te * SWITCH_SPEED + Vector3(0.0, SWITCH_HOP, 0.0)
		var fp: Vector3 = leave
		var clock: float = 0.0
		var want: Array[float] = [0.12, 0.26]
		var k: int = 0
		while k < want.size() and clock < 2.0:
			var g: float = _tuning.gravity_rise if vel.y > 0.0 else _tuning.gravity_fall
			vel.y -= g / 120.0
			fp += vel / 120.0
			clock += 1.0 / 120.0
			if clock >= want[k]:
				r2.append(fp - Vector3(0.0, 0.3, 0.0))
				k += 1
		r2.append(Vector3(r2[1].x * 0.35, (r2[1].y + y_b + 1.0) * 0.5, front - 22.0))
		r2.append(Vector3(0.0, y_b + 1.0, near_z - 3.0))
	var w1: Array[Vector3] = []
	for p: Vector3 in r1:
		w1.append(_w(p))
	var rail1: GrindRail = kit.rail(w1, {"post_to_y": _w(Vector3(0, low_y, 0)).y, "post_every": 12.0, "hop": SWITCH_HOP if switch else 6.0})
	_rails.append(rail1)
	var rail2: GrindRail = null
	if switch:
		var w2: Array[Vector3] = []
		for p2: Vector3 in r2:
			w2.append(_w(p2))
		rail2 = kit.rail(w2, {"post_to_y": _w(Vector3(0, low_y, 0)).y, "post_every": 12.0})
		_rails.append(rail2)
	_pulse(a, front + 14.0)
	if route_variant == 1:
		_poly.append(_w(Vector3(0.0, y_a, front + 12.0)))
		r_flow(_poly.duplicate())
		var from_pt: Vector3 = _w(Vector3(0.0, y_a, front + 7.0))
		if not switch:
			r_rail(rail1, rail1.start_point(), {"from": from_pt, "to": _w(land_to)})
		else:
			r_rail(rail1, rail1.start_point(), {"from": from_pt, "leave": _w(leave), "chain_next": true, "to": rail2.start_point()})
			r_rail(rail2, rail2.start_point(), {"chain": true, "to": _w(land_to)})
		_poly = [_w(land_to)]
	return b


# ---- open tubes (half-pipes) -----------------------------------------------------------------------------

## A half-pipe run after island `a`: `length` m of tube dropping `drop`, the safe route on a stepped walkway beside it.
## Returns the world HalfPipe; the caller continues from the matching local end point.
func _pipe_after(a: Dictionary, sx: float, length: float, drop: float, width: float, depth: float) -> HalfPipe:
	var ac: Vector3 = a["c"]
	var z0: float = ac.z - float(a["hz"])
	var y0: float = ac.y
	var start := Vector3(0.0, y0, z0)
	var end := Vector3(0.0, y0 - drop, z0 - length)
	var pipe: HalfPipe = kit.halfpipe(_w(start), _w(end), width, depth, {"taper": 8.0, "shelf": 0.6, "guard": false})
	_pipes.append(pipe)
	# the safe walkway: stepped decks down the side
	var steps: int = int(round(length / 8.0))
	var step_len: float = length / float(steps)
	var side: float = signf(sx) * (width * 0.5 + 0.6 + 1.5)
	var dy: float = drop / float(steps)
	for k: int in steps:
		var top := Vector3(side, y0 - dy * float(k), z0 - step_len * (float(k) + 0.5))
		_blk(top, 2.8, step_len + 0.05, "main", ISL_THICK)
	if route_variant == 0:
		r_walk(_w(Vector3(sx, y0, z0 - 0.2)))
		r_walk(_w(Vector3(side, y0, z0 - 1.5)))
		r_walk(_w(Vector3(side, y0 - dy * float(steps - 1), z0 - length + 1.0)))
		r_walk(_w(Vector3(sx, y0 - drop, z0 - length - 1.5)))
	else:
		_poly.append(pipe.centre_point(0.0))
		r_flow(_poly.duplicate())
		r_flow(pipe.carve_points(2, 0.55))
		_poly = [pipe.centre_point(1.0)]
	return pipe


## The track bed under a pit: a catch deck 3.4 m down with two glowing rails, and a mag-lift pad at
## the far end that throws a faller up onto the next island.
func _bed(a: Dictionary, b: Dictionary) -> void:
	var ac: Vector3 = a["c"]
	var bcn: Vector3 = b["c"]
	var by: float = float(b.get("y0", bcn.y))
	var near_z: float = ac.z - float(a["hz"])
	var far_z: float = bcn.z + float(b["hz"])
	var low_y: float = minf(ac.y, by) - 3.4
	var span: float = near_z - far_z
	var depth: float = span + 6.0
	var bed_w: float = ISL_W + 6.0
	var bed_c := Vector3(0.0, low_y, (near_z + far_z) * 0.5)
	_blk(bed_c, bed_w, depth, "alt", ISL_THICK)
	for sx: float in [-1.0, 1.0]:
		kit.glow_strip(_w(Vector3(sx * 2.2, low_y + 0.03, bed_c.z)), Vector3(0.18, 0.05, depth - 1.0), CYAN, _yaw)
	var pad_at := Vector3(0.0, low_y, far_z + 5.5)
	var target := Vector3(0.0, by, far_z - 5.0)
	var sol: Vector2 = _pad_solve(pad_at, target, far_z)
	kit.pad(_w(pad_at), sol.y, sol.x, _yaw, 1.5)


## The (pitch deg from vertical, strength) of a pad at local `from` that carries a faller up over the far
## island's near face (at local z `face_z`, top at `to.y`) and lands him on local `to`.
func _pad_solve(from: Vector3, to: Vector3, face_z: float) -> Vector2:
	var best := Vector2(15.0, 24.0)
	var best_err: float = INF
	# (BouncePad pitch is measured from the vertical: 0 = straight up)
	var pitch: float = 4.0
	while pitch <= 40.0:
		var s: float = 14.0
		while s <= 34.0:
			var v0 := Vector3(0.0, s * cos(deg_to_rad(pitch)), -s * sin(deg_to_rad(pitch)))
			var pts: PackedVector3Array = Ballistics.arc(_tuning, from + Vector3(0, 0.5, 0), v0, 4.0, 1.0 / 60.0)
			var clear: bool = false
			var land := Vector3.INF
			for i: int in range(1, pts.size()):
				if not clear and pts[i].z <= face_z - 0.6:
					clear = pts[i].y >= to.y + 0.8
					if not clear:
						break
				if clear and pts[i].y <= to.y + 0.05 and pts[i].y < pts[i - 1].y:
					land = pts[i]
					break
			if clear and land != Vector3.INF:
				var err: float = absf(land.z - to.z) + absf(land.x - to.x) + s * 0.01
				if err < best_err:
					best_err = err
					best = Vector2(pitch, s)
			s += 0.5
		pitch += 1.5
	return best


## A lane of chevron lights down the middle of island `a` from its near end to local z `to_z`.
func _pulse(a: Dictionary, to_z: float, from_z: float = INF) -> void:
	var ac: Vector3 = a["c"]
	var z_start: float = (ac.z + float(a["hz"])) if from_z == INF else from_z
	var y0: float = float(a.get("y0", ac.y))
	var pts: Array[Vector3] = []
	pts.append(_w(Vector3(0, y0, z_start - 1.0)))
	pts.append(_w(Vector3(0, y0, to_z)))
	if absf(z_start - to_z) > 6.0:
		HyperloopPulse.lay(self, pts, 3.2, 2.0, 0.07, CYAN)


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	add_child(Ambience.make(theme_id))
	deco = HyperloopDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 2.0), 0.0)
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9]
	var yaws: Array[float] = []
	for i: int in 10:
		yaws.append(30.0 * float(i))
	_frame(Vector3.ZERO, yaws[0])
	# hub 0 is the start plate
	_hub(Vector3.ZERO, 0)
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		_stage_frames.append({"origin": _o, "yaw": _yaw})
		var end: Vector3 = stages[i].call()
		stage_lengths.append(-end.z)
		_frame(_w(end), yaws[i + 1])
	_stage_frames.append({"origin": _o, "yaw": _yaw})
	_stage_10()
	_surroundings()
	_deck_materials()


## The common tail of a stage: the hub is laid HUB_IN beyond the last island, the routes reach its
## centre and bank the checkpoint. Returns the hub centre (local).
func _end_at_hub(last: Dictionary, index: int) -> Vector3:
	var lc: Vector3 = last["c"]
	var z1: float = lc.z - float(last["hz"])
	var hub := Vector3(lc.x, lc.y - 0.05, z1 - HUB_IN)
	_hub(hub, index)
	_pulse(last, z1 + 1.0)
	if route_variant == 0:
		r_walk(_w(hub))
	else:
		_poly.append(_w(Vector3(hub.x, lc.y, hub.z)))
		r_flow(_poly.duplicate())
	r_checkpoint()
	return hub


## The first island of a stage: starts HUB_IN short of the hub centre, 5 cm above the hub plate. The
## flow route leaves the hub through a chain of three gates (20 -> 25 m/s) on it.
func _first(length: float, sx: float) -> Dictionary:
	var a: Dictionary = _island(-HUB_IN, length, 0.05)
	var speeds: Array[float] = [20.0, 22.5, 25.0]
	var pts: Array[Vector3] = [_w(Vector3(0, 0.05, 0))]
	for i: int in 3:
		var gp := Vector3(0, 0.05, -9.0 - 5.0 * float(i))
		kit.boost_gate(_w(gp), _yaw, speeds[i], 5.0)
		pts.append(_w(gp))
	if route_variant == 1:
		_poly = pts
		_flow_speed = 25.0
	else:
		# the safe route keeps to its side lane, clear of the gates
		r_walk(_w(Vector3(sx, 0.05, -8.0)))
	return a


## A middle island's gate (restores the speed at least to `speed`) just after the landing.
func _gate_after_landing(b: Dictionary, speed: float = 28.0) -> void:
	var bc: Vector3 = b["c"]
	var near: float = bc.z + float(b["hz"])
	var gp := Vector3(0, float(b.get("y0", bc.y)), near - PEN - 5.0)
	kit.boost_gate(_w(gp), _yaw, speed, 5.0)
	if route_variant == 1:
		_poly.append(_w(gp))


# ---- the stages ---------------------------------------------------------------------------------------

func _stage_1() -> Vector3:
	var sx: float = LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, 4.0, 30.0, 25.0)
	return _end_at_hub(i2, 1)


## 2 RING ROAD: an arc and ring chain, then a long flow slope down to the hub.
func _stage_2() -> Vector3:
	var sx: float = -LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, 3.5, 32.0, 25.0, 6.0)
	return _end_at_hub(i2, 2)


## 3 MAG-RAIL YARD: an arc and rings, then one long grind rail over a wide pit.
func _stage_3() -> Vector3:
	var sx: float = LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, 3.5, 24.0, 25.0)
	_gate_after_landing(i2)
	var i3: Dictionary = _cross_rail(i2, sx, 4.5, 20.0, 20.0)
	return _end_at_hub(i3, 3)


## 4 LOOP TUBE: an arc, then an open tube (half-pipe) to carve down.
func _stage_4() -> Vector3:
	var sx: float = -LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, 3.0, 14.0, 25.0)
	var pipe: HalfPipe = _pipe_after(i2, sx, 52.0, 6.0, 8.0, 1.7)
	var lc: Vector3 = i2["c"]
	var z_end: float = lc.z - float(i2["hz"]) - 52.0
	var e: Dictionary = _island(z_end, 12.0, lc.y - 6.0)
	if pipe == null:
		return Vector3.ZERO
	return _end_at_hub(e, 4)


## 5 POD STATION: an arc and rings over a pit that the safe line crosses on a transit pod.
func _stage_5() -> Vector3:
	var sx: float = LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, 3.5, 30.0, 25.0, 0.0, true)
	return _end_at_hub(i2, 5)


## 6 SWITCHYARD: an arc, then a rail-to-rail switch over a wide pit.
func _stage_6() -> Vector3:
	var sx: float = -LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, 3.5, 24.0, 25.0)
	_gate_after_landing(i2)
	var i3: Dictionary = _cross_rail(i2, sx, 4.0, 18.0, 24.0, true)
	return _end_at_hub(i3, 6)


## 7 SPIRE LIFT: two launches UP onto higher decks.
func _stage_7() -> Vector3:
	var sx: float = LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, -2.4, 24.0, 25.0)
	_gate_after_landing(i2)
	var i3: Dictionary = _cross(i2, sx, -2.0, 14.0, 29.0)
	return _end_at_hub(i3, 7)


## 8 GREAT TUBE: an arc into a longer, wider tube.
func _stage_8() -> Vector3:
	var sx: float = -LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, 3.5, 14.0, 25.0)
	var pipe: HalfPipe = _pipe_after(i2, sx, 60.0, 10.0, 9.0, 1.9)
	var lc: Vector3 = i2["c"]
	var z_end: float = lc.z - float(i2["hz"]) - 60.0
	var e: Dictionary = _island(z_end, 12.0, lc.y - 10.0)
	if pipe == null:
		return Vector3.ZERO
	return _end_at_hub(e, 8)


## 9 OVERDRIVE: an arc, then a long rail over the last pit, flat out.
func _stage_9() -> Vector3:
	var sx: float = LANE
	var i1: Dictionary = _first(26.0, sx)
	var i2: Dictionary = _cross(i1, sx, 3.5, 24.0, 25.0)
	_gate_after_landing(i2)
	var i3: Dictionary = _cross_rail(i2, sx, 4.5, 20.0, 22.0)
	return _end_at_hub(i3, 9)


## The finale, THE GREAT RING: a first launch over a wide pit, then one long descending slope with a ring
## line racing down it, onto the finish deck with its bumper wall.
func _stage_10() -> void:
	var i1: Dictionary = _first(26.0, -LANE)
	var i2: Dictionary = _cross(i1, -LANE, 5.0, 84.0, 25.0, 15.0)
	var bc: Vector3 = i2["c"]
	var y0: float = float(i2["y0"])
	var near: float = bc.z + float(i2["hz"])
	var z_end: float = bc.z - float(i2["hz"])
	var y_end: float = bc.y
	# the ring line down the slope: nine rings, ~9.5 m apart, 1.4 m over the surface
	var pts: Array[Vector3] = []
	var rpts: Array[Vector3] = []
	for k: int in 9:
		var u: float = (12.0 + 8.0 * float(k)) / 84.0
		var rz: float = near - 84.0 * u
		var ry: float = y0 - 15.0 * u + 1.4
		rpts.append(_w(Vector3(0, ry, rz)))
	kit.ring_line(rpts, {"add_speed": 2.0, "radius": RING_R, "cap": RING_CAP})
	# three great hoops of white ceramic stand round the line: THE GREAT RING you plunge through
	for hk: int in [1, 4, 7]:
		deco.giant_ring(rpts[hk] + Vector3(0, 0.4, 0), 7.5, 0.4, Vector3(90.0, _yaw, 0.0))
	_pulse(i2, z_end, near - PEN)
	# the run-out deck, the finish gate and a bumper wall
	_island(z_end, 40.0, y_end)
	var fin_z: float = z_end - 18.0
	kit.finish(_w(Vector3(0, y_end, fin_z)), _yaw)
	_finish_pos = _w(Vector3(0, y_end, fin_z))
	kit.block(_w(Vector3(0, y_end + 1.6, z_end - 41.5)), Vector3(ISL_W + 2.0, 3.2, 1.6), Color(0.9, 0.95, 1.0), true, _yaw)
	deco.gantry(_w(Vector3(0, y_end, fin_z + 6.0)), _yaw, 11.0, 9.0, CORAL)
	if route_variant == 0:
		r_walk(_w(Vector3(-LANE, y_end, z_end + 1.0)))
		r_walk(_w(Vector3(0, y_end, fin_z)))
	else:
		_poly.append(_w(Vector3(0, y0 - 15.0 * 0.12, near - 12.0)))
		_poly.append(_w(Vector3(0, y_end, z_end)))
		_poly.append(_w(Vector3(0, y_end, fin_z)))
		r_flow(_poly.duplicate())


# ---- environment ----------------------------------------------------------------------------------

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
	_env.sky = HyperloopSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.74, 0.86, 1.0)
	_env.ambient_light_energy = 0.78
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.80, 0.91, 0.98)
	_env.fog_density = 0.0011
	_env.fog_aerial_perspective = 0.4
	_env.fog_sky_affect = 0.3
	_env.fog_sun_scatter = 0.2
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 1.25
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.08
	_env.adjustment_contrast = 1.05
	# a low rose-gold dawn sun, long soft shadows; a cool white skylight fill from the other side
	_sun.light_color = Color(1.0, 0.92, 0.84)
	_sun.light_energy = 1.55
	_sun.rotation_degrees = Vector3(-24, 205, 0)
	_fill.light_color = Color(0.78, 0.9, 1.0)
	_fill.light_energy = 0.42
	_fill.rotation_degrees = Vector3(-30, 25, 0)


## Swap every walkable deck to the ceramic-panel shader (same uniforms as Look's platform shader).
func _deck_materials() -> void:
	var shader: Shader = preload("res://visual/hyperloop_deck.gdshader")
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = shader
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		r.set_shader_parameter("trim_glow", maxf(float(sm.get_shader_parameter("trim_glow")), 0.3))
		m.material_override = r


# ---- scenery ----------------------------------------------------------------------------------------

func _surroundings() -> void:
	# supports and keels under every deck, a gantry over every hub
	for d: Dictionary in _decks:
		var top: Vector3 = d["top"]
		var size: Vector3 = d["size"]
		if d.has("round"):
			deco.keel(top, Vector3(size.x * 0.7, size.y, size.z * 0.7), float(d["yaw"]), 5.0)
		else:
			deco.keel(top, Vector3(size.x * 0.8, size.y, minf(size.z, 12.0) * 0.8), float(d["yaw"]), 2.6)
	for i: int in _hubs.size():
		var h: Vector3 = _hubs[i]
		deco.pylon(h - Vector3(0, ISL_THICK + 5.0, 0), h.y - 150.0, 2.2)
		var yaw_i: float = float((_stage_frames[mini(i, _stage_frames.size() - 1)] as Dictionary)["yaw"])
		# the gantry stands across the line of travel at the hub's rim, flanking the checkpoint
		deco.gantry(h, yaw_i + 90.0, HUB_R * 2.0 - 1.6, 8.5, CORAL if i % 2 == 0 else CYAN)
	_megastructure()


## The centroid and vertical range of the hubs, for placing the great structures round the spiral.
func _course_bounds() -> Dictionary:
	var c := Vector3.ZERO
	var lo: float = INF
	var hi: float = -INF
	for h: Vector3 in _hubs:
		c += h
		lo = minf(lo, h.y)
		hi = maxf(hi, h.y)
	c /= float(maxi(_hubs.size(), 1))
	var r: float = 0.0
	for h: Vector3 in _hubs:
		r = maxf(r, Vector2(h.x - c.x, h.z - c.z).length())
	return {"center": c, "lo": lo, "hi": hi, "radius": r}


## The complex round the course: the central spire, vast rings, radial glass tubes with trains in them,
## and a far skyline of lit silos.
func _megastructure() -> void:
	var bd: Dictionary = _course_bounds()
	var c: Vector3 = bd["center"]
	var lo: float = bd["lo"]
	var hi: float = bd["hi"]
	var course_r: float = maxf(float(bd["radius"]), 60.0)
	var mid_y: float = (lo + hi) * 0.5
	# the central spire
	deco.axis_tower(Vector3(c.x, lo - 260.0, c.z), (hi - lo) + 640.0, 11.0)
	# vast rings round it: three flat ones inside and beyond the course circle, one standing beyond it
	deco.giant_ring(Vector3(c.x, hi + 38.0, c.z), course_r * 0.55, 2.6, Vector3(4, 0, -3))
	deco.giant_ring(Vector3(c.x, mid_y - 24.0, c.z), course_r * 0.78, 3.4, Vector3(-3, 0, 5))
	deco.giant_ring(Vector3(c.x, lo - 70.0, c.z), course_r * 1.15, 4.4, Vector3(2, 0, 2))
	deco.giant_ring(c + Vector3(course_r * 1.9, mid_y + 60.0, -course_r * 0.6), course_r * 1.1, 5.0, Vector3(90, 25, 0))
	# radial tubes from the spire out past the course, alternately above and below it, a train in each
	var n_spokes: int = 7
	for i: int in n_spokes:
		var az: float = TAU * (float(i) + 0.37) / float(n_spokes)
		var dir := Vector3(cos(az), 0.0, sin(az))
		var y: float = hi + 46.0 + float(i % 3) * 26.0 if i % 2 == 0 else lo - 52.0 - float(i % 3) * 22.0
		var a := Vector3(c.x, y, c.z) + dir * 14.0
		var b := Vector3(c.x, y, c.z) + dir * (course_r * 2.4)
		deco.tube(a, b, 4.6)
		HyperloopTrain.make(self, a, b, 5, 70.0 + 9.0 * float(i), float(i) * 0.19)
		deco.pylon(Vector3(b.x, y - 5.0, b.z), lo - 260.0, 3.0)
	# a far skyline of lit silos and slabs
	var silo_mat: StandardMaterial3D = HyperloopDecor.white_mat()
	var glow: StandardMaterial3D = HyperloopDecor.glow_mat(CYAN, 1.8)
	for i: int in 46:
		var az2: float = kit.rng.randf() * TAU
		var dist: float = course_r * kit.rng.randf_range(1.55, 2.9)
		var h: float = kit.rng.randf_range(40.0, 190.0)
		var r: float = kit.rng.randf_range(5.0, 15.0)
		var base_y: float = lo - kit.rng.randf_range(120.0, 260.0)
		var pos := Vector3(c.x + cos(az2) * dist, base_y + h * 0.5, c.z + sin(az2) * dist)
		var silo := Look.cylinder(r, h, silo_mat, pos, r * kit.rng.randf_range(0.7, 1.0), 14)
		silo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(silo)
		var band := Look.cylinder(r * 1.03, 1.2, glow, pos + Vector3(0, h * kit.rng.randf_range(0.1, 0.45), 0), r * 1.03, 14)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(band)
	# banks of cloud drifting below the course and between the decks
	kit.cloud_field(Vector3(c.x, lo - 40.0, c.z), Vector3(course_r * 2.2, 24.0, course_r * 2.2), 70)
	# motes of light along the whole spiral
	for h2: Vector3 in _hubs:
		HyperloopFx.motes(self, h2 + Vector3(0, 6.0, 0), Vector3(60.0, 12.0, 60.0), 40)
