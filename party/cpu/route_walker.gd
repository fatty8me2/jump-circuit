class_name RouteWalker
extends RefCounted
## A lightweight player-like body that follows a level's own route (the `r_*` steps every
## course defines, the same ones tests/route_bot.gd plays with a real Player) - without a
## physics body of its own.
##
## Why not a second real Player: the level's checkpoints, kill zones and finish gate react to
## ANY Player and would bank, kill or finish the human. The walker keeps its own progress and
## only reads the level: it asks platforms where they are (RouteMath.future), evaluates the
## route's timing tests (`r_until`, `r_wait` ...), rides moving platforms by following the
## body it stands on, and uses ray casts for ground, edges and landings.
##
## What it models, human-like on purpose (see CpuSkill):
##  - running at a share of the player's top speed, jumps at their physical air time,
##  - reaction delay + dither before jumps and after waits,
##  - botched long jumps (they fall short and respawn), mistimed obstacles (respawn),
##  - knockback / stun / freeze from items and shoves, and falling off the course,
##  - corner cutting for Hard.
## Output each tick: pos / vel / grounded / seq (a teleport counter) and `events`
## ({"k": "cp" | "fail" | "respawn" | "finish"}), which the owner drains.

enum Mode { STEP, ARC, AIR }

const GROUND_MASK: int = 1 | 8
## A step that has not finished after this long is skipped (waits get longer).
const STEP_LIMIT: float = 40.0
const WAIT_LIMIT: float = 60.0
## No checkpoint for this long: the walker is moved on (a stuck CPU never stalls a round).
const PROGRESS_LIMIT: float = 150.0

var level: LevelBase
var tuning: MovementTuning
var p: Dictionary = {}
var rng := RandomNumberGenerator.new()
var route: Array[Dictionary] = []
var gates: Array[FinishGate] = []
var start_pos: Vector3 = Vector3.ZERO

var pos: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var facing: Vector3 = Vector3(0, 0, -1)
var grounded: bool = true
var seq: int = 0
var step: int = 0
var mode: Mode = Mode.STEP
var done: bool = false
## Highest checkpoint touched (1-based, 0 = none).
var cp: int = 0
var deaths: int = 0
var skipped: int = 0
var events: Array[Dictionary] = []
## Catch-up / item speed factor (set by the owner).
var pace: float = 1.0
## Seconds frozen in place (stun, ice, respawn pause).
var hold: float = 0.0
var enabled_fail: bool = true
## Debug: when set, every finished step is logged as [step, kind, seconds, route time].
var trace: Array = []
var trace_on: bool = false

var _cur: Dictionary = {}
var _phase: int = 0
var _st: float = 0.0
var _wait_t: float = 0.0
var _gate_left: float = -1.0
var _takeoff_left: float = -1.0
var _speed_now: float = 0.0
var _last_ground_y: float = 0.0
var _ground_body: Node3D = null
var _ground_xf: Transform3D = Transform3D.IDENTITY
var _resume: Dictionary = {0: 0}
var _marks: Array[int] = []
var _mark_count: int = 0
var _pick_node: Node3D = null
var _pick_basis: Basis = Basis.IDENTITY
var _candy_pick: Node3D = null
var _since_progress: float = 0.0
var _end_t: float = 0.0
var _fails_at: Dictionary = {}
var _jumped_safe: int = -1
var _teleported: bool = false
# arc
var _arc_from: Vector3 = Vector3.ZERO
var _arc_fn: Callable
var _arc_then: Callable
var _arc_t: float = 0.0
var _arc_T: float = 1.0
var _arc_k: float = 1.0
var _arc_fail: bool = false
var _arc_short: float = 0.7
# airborne (knocked, fell short)
var _av: Vector3 = Vector3.ZERO
var _query := PhysicsRayQueryParameters3D.new()
var _proxy: Player = null


func setup(p_level: LevelBase, params: Dictionary, p_seed: int, at: Vector3) -> void:
	level = p_level
	p = params
	rng.seed = p_seed
	route = level.route
	start_pos = at
	pos = at
	_last_ground_y = at.y
	tuning = load("res://resources/default_tuning.tres") as MovementTuning
	_query.collision_mask = GROUND_MASK
	_proxy = _proxy_for(level)
	for node: Node in level.find_children("*", "FinishGate", true, false):
		gates.append(node as FinishGate)
	for i: int in route.size():
		if str(route[i]["kind"]) == "checkpoint":
			_marks.append(i)
	if _marks.size() == level.checkpoints.size():
		for k: int in _marks.size():
			_resume[k + 1] = _marks[k] + 1
	_enter_step()


# ---- public controls --------------------------------------------------------------------------

## Knocked away (a shove, a punch, a blast): flies on its own and lands, or falls out.
func knock(v: Vector3) -> void:
	if done:
		return
	mode = Mode.AIR
	_av = v
	grounded = false
	_ground_body = null
	_arc_fail = false


func stun(seconds: float) -> void:
	hold = maxf(hold, seconds)
	if mode == Mode.ARC:
		_av = Vector3(vel.x, minf(vel.y, 0.0), vel.z) * 0.4
		mode = Mode.AIR
		grounded = false


## The route's own `until` / `test` callables read `player` (the level's Player). A CPU is not
## that Player, so they are asked with a stand-in: one disabled, invisible, collision-less Player
## per level that is put where the CPU is and swapped in as `level.player` for the call.
static func _proxy_for(lvl: LevelBase) -> Player:
	if lvl.has_meta("cpu_proxy") and is_instance_valid(lvl.get_meta("cpu_proxy")):
		return lvl.get_meta("cpu_proxy") as Player
	var px: Player = (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	px.process_mode = Node.PROCESS_MODE_DISABLED
	px.collision_layer = 0
	px.collision_mask = 0
	px.visible = false
	px.use_device_input = false
	px.name = "CpuProbe"
	lvl.add_child(px)
	lvl.set_meta("cpu_proxy", px)
	return px


func _cond(c: Callable) -> bool:
	if _proxy == null or not is_instance_valid(_proxy):
		return bool(c.call())
	_proxy.global_position = pos
	_proxy.velocity = vel
	_proxy.grounded = grounded
	_proxy.floor_body = _ground_body
	_proxy.last_ground_y = _last_ground_y
	_proxy.facing_dir = facing
	var real: Player = level.player
	level.player = _proxy
	var r: bool = bool(c.call())
	level.player = real
	return r


## Put somewhere else (Swap Warp): resumes the same step from there.
func teleport(to: Vector3) -> void:
	pos = to
	_av = Vector3.ZERO
	mode = Mode.STEP
	grounded = true
	_ground_body = null
	_last_ground_y = to.y
	seq = (seq + 1) % 256
	_teleported = true
	_phase = 0
	_gate_left = -1.0
	_takeoff_left = -1.0
	_arc_fail = false


## After being put somewhere else: carry on from the route step nearest to here.
func relocate(to: Vector3) -> void:
	var best: int = step
	var best_d: float = INF
	for i: int in route.size():
		var a: Vector3 = RouteMath.anchor(route[i])
		if not a.is_finite():
			continue
		var d: float = RouteMath.flat(a - to).length() + absf(a.y - to.y) * 3.0
		if d < best_d:
			best_d = d
			best = i
	step = best
	if _marks.size() == level.checkpoints.size():
		var n: int = 0
		for m: int in _marks:
			if m < step:
				n += 1
		cp = maxi(cp, n)
	_enter_step()


func respawn_point() -> Vector3:
	if cp > 0 and cp <= level.checkpoints.size():
		return level.checkpoints[cp - 1].respawn_transform().origin
	return start_pos


## Share of the course behind it (0..1) by route steps, for catch-up pacing.
func progress() -> float:
	return clampf(float(step) / float(maxi(route.size(), 1)), 0.0, 1.0)


# ---- tick --------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	if done or dt <= 0.0:
		return
	var prev: Vector3 = pos
	_since_progress += dt
	if hold > 0.0 and mode == Mode.STEP:
		hold -= dt
		_ride()
		_set_vel(prev, dt)
		return
	if hold > 0.0:
		hold -= dt
	match mode:
		Mode.ARC:
			_tick_arc(dt)
		Mode.AIR:
			_tick_air(dt)
		_:
			_tick_step(dt)
	_set_vel(prev, dt)
	_check_progress()
	if _since_progress > PROGRESS_LIMIT:
		_force_progress()


func _set_vel(prev: Vector3, dt: float) -> void:
	if _teleported:
		_teleported = false
		vel = Vector3.ZERO
		return
	var v: Vector3 = (pos - prev) / dt
	if v.length() > 45.0:
		v = v.normalized() * 45.0
	vel = vel.lerp(v, 0.6)
	var flat: Vector3 = RouteMath.flat(vel)
	if flat.length() > 0.6:
		facing = flat.normalized()


func _tick_step(dt: float) -> void:
	_ride()
	if step >= route.size():
		_tick_end(dt)
		return
	_st += dt
	if _st > STEP_LIMIT and _wait_t < 1.0:
		_skip("step %d (%s) took too long" % [step, str(_cur.get("kind", ""))])
		return
	if _st > WAIT_LIMIT:
		_skip("wait in step %d (%s) never opened" % [step, str(_cur.get("kind", ""))])
		return
	var s: Dictionary = _cur
	match str(s["kind"]):
		"checkpoint":
			_mark_count += 1
			_next()
		"walk":
			if bool(p.get("cut", false)) and _phase == 0:
				_phase = 1
				var nx: int = step + 1
				if nx < route.size() and str(route[nx]["kind"]) == "walk" and _can_cut(pos, route[nx]["to"] as Vector3):
					_next()
					return
			if _walk_to(s["to"], dt, 0.6):
				_next()
		"jump", "b_jump":
			_do_jump(s, dt, "jump", _fn_for(s))
		"pad", "x_pad", "kick":
			if _phase == 0 and _walk_to(s["from"], dt, 0.35):
				_phase = 1
				_begin_arc(_fn_x(s) if str(s["kind"]) == "x_pad" else _fn_for(s), "pad")
		"wait":
			var n: Node3D = s["node"] if is_instance_valid(s["node"]) else null
			var open: bool = n == null or n.global_position.distance_to(s["point"]) <= float(s["radius"])
			if _wait_gate(open, dt):
				_next()
		"b_wait":
			if s.has("hold") and _wait_t > 0.0:
				var off: Vector3 = RouteMath.flat((s["hold"] as Vector3) - pos)
				if off.length() > 0.15:
					_walk_to(s["hold"], dt, 0.1)
			if _wait_gate(_cond(s["test"] as Callable), dt):
				_next()
		"c_wait":
			var u: float = fposmod(Game.course_time / float(s["period"]) + float(s.get("offset", 0.0)), 1.0)
			if _wait_gate(u >= float(s["lo"]) and u < float(s["hi"]), dt):
				_next()
		"x_wait":
			if _wait_gate(_x_wait_open(s), dt):
				_next()
		"h_hop":
			if _wait_gate(_cond(s["until"] as Callable), dt, false):
				_next()
		"ride_jump":
			if _phase == 0:
				var n2: Node3D = s["node"]
				if s.has("stand") and is_instance_valid(n2):
					var spot: Vector3 = n2.global_transform * (s["stand"] as Vector3)
					if RouteMath.flat(spot - pos).length() > 0.15:
						_walk_to(spot, dt, 0.1)
				var near: bool = is_instance_valid(n2) and n2.global_position.distance_to(s["point"]) <= float(s["radius"])
				if _wait_gate(near, dt):
					_phase = 1
					_begin_arc(_fn_for(s), "jump")
		"x_walk_on":
			var node: Node3D = _x_node(s, "node")
			if node == null:
				_next()
				return
			var spot2: Vector3 = RouteMath.future(node, _x_local(s, "local"), 0.05)
			if _walk_to(spot2, dt, float(s.get("tol", 0.35))):
				_next()
		"x_jump", "h_jump":
			_do_x_jump(s, dt)
		"w_run":
			_do_wall_run(s, dt)
		"m_climb", "b_mantle":
			if _phase == 0 and _walk_to(s["from"], dt, 0.3) and _takeoff(dt):
				_phase = 1
				var top: Vector3 = s["top"]
				_begin_arc(func(_l: float) -> Vector3: return top, "mantle")
		"portal":
			if _walk_to(s["to"], dt, 0.7):
				_phase += 1
				if _phase > 8:
					pos = s["exit"]
					seq = (seq + 1) % 256
					_teleported = true
					_last_ground_y = pos.y
					_next()
		"a_fly", "desert_fly":
			_do_fly(s, dt)
		"ascent_stream", "b_sweep":
			if _walk_to(s["to"], dt, float(s.get("tol", 0.6))):
				_next()
		"candy_board", "candy_ride":
			_do_candy(s, dt)
		_:
			_next()


# ---- stepping through the route -------------------------------------------------------------------

func _enter_step() -> void:
	_phase = 0
	_st = 0.0
	_wait_t = 0.0
	_gate_left = -1.0
	_takeoff_left = -1.0
	_cur = route[step].duplicate() if step < route.size() else {}


func _next() -> void:
	if trace_on and step < route.size():
		trace.append([step, str(route[step]["kind"]), snappedf(_st, 0.01), snappedf(Game.course_time, 0.1)])
	step += 1
	_enter_step()


func _skip(why: String) -> void:
	skipped += 1
	if skipped > 14:
		_force_progress()
		return
	push_warning("RouteWalker: %s - skipping" % why)
	_next()


## Walking never gets it anywhere: jump to the next checkpoint (or the finish).
func _force_progress() -> void:
	_since_progress = 0.0
	if cp < level.checkpoints.size():
		cp += 1
		events.append({"k": "cp", "i": cp})
		var at: Vector3 = respawn_point()
		teleport(at)
		step = _resume_step(cp)
		_enter_step()
		skipped = 0
	else:
		_finish()


func _tick_end(dt: float) -> void:
	_end_t += dt
	if not gates.is_empty():
		var g: FinishGate = gates[0]
		_walk_to(g.global_position, dt, 0.3)
	if _end_t > 10.0:
		_finish()


func _finish() -> void:
	if done:
		return
	done = true
	vel = Vector3.ZERO
	events.append({"k": "finish"})


# ---- progress (checkpoints, the finish) ----------------------------------------------------------------

func _check_progress() -> void:
	for i: int in range(cp, mini(cp + 2, level.checkpoints.size())):
		var c: Checkpoint = level.checkpoints[i]
		var d: Vector3 = pos - c.global_position
		if Vector2(d.x, d.z).length() <= c.radius * 0.95 and d.y > -0.6 and d.y < 3.4:
			cp = i + 1
			_since_progress = 0.0
			skipped = 0
			events.append({"k": "cp", "i": cp})
			if not _resume.has(cp):
				_resume[cp] = _find_resume(cp)
			break
	if not done:
		for g: FinishGate in gates:
			if not is_instance_valid(g):
				continue
			var l: Vector3 = g.global_transform.affine_inverse() * pos
			if absf(l.x) <= g.width * 0.5 + 0.2 and absf(l.z) <= 1.1 and l.y > -0.6 and l.y < g.gate_height:
				_finish()
				return


func _resume_step(at_cp: int) -> int:
	if not _resume.has(at_cp):
		_resume[at_cp] = _find_resume(at_cp)
	return clampi(int(_resume[at_cp]), 0, route.size())


## A route without a mark per checkpoint: resume at the first step (after the previous
## checkpoint's) that is near the checkpoint, else where we are now.
func _find_resume(at_cp: int) -> int:
	if at_cp <= 0:
		return 0
	var at: Vector3 = level.checkpoints[at_cp - 1].global_position
	var from_step: int = int(_resume.get(at_cp - 1, 0))
	for i: int in range(from_step, route.size()):
		var a: Vector3 = RouteMath.anchor(route[i])
		if a.is_finite() and RouteMath.flat(a - at).length() < 8.0 and absf(a.y - at.y) < 4.0:
			return mini(i + 1, route.size())
	return mini(step, route.size())


# ---- failing -------------------------------------------------------------------------------------------

func _fall_floor() -> float:
	return maxf(level.kill_y, _last_ground_y - level.fall_margin * 1.2)


## Fell, or got caught: back to the last checkpoint after a human-sized pause.
func die(cause: String) -> void:
	if done:
		return
	deaths += 1
	events.append({"k": "fail", "cause": cause})
	_fails_at[step] = int(_fails_at.get(step, 0)) + 1
	var at: Vector3 = respawn_point()
	teleport(at)
	step = _resume_step(cp)
	_enter_step()
	hold = float(p["pause"]) * rng.randf_range(0.8, 1.3)
	_speed_now = 0.0
	events.append({"k": "respawn"})


# ---- walking -------------------------------------------------------------------------------------------

func _ray_down(at: Vector3, up: float = 1.0, down: float = 2.5) -> Dictionary:
	_query.from = at + Vector3(0, up, 0)
	_query.to = at + Vector3(0, -down, 0)
	return level.get_world_3d().direct_space_state.intersect_ray(_query)


## Moves toward `target` on the flat at the CPU's running speed; true once within `tol`.
func _walk_to(target: Vector3, dt: float, tol: float, snap: bool = true) -> bool:
	var d: Vector3 = RouteMath.flat(target - pos)
	var dist: float = d.length()
	var top: float = tuning.max_speed * float(p["speed"]) * pace
	var want: float = minf(top, 1.8 + dist * 5.0)
	_speed_now = move_toward(_speed_now, want, 60.0 * dt)
	var mv: float = minf(_speed_now * dt, dist)
	if dist > 0.0001:
		pos += d / dist * mv
	grounded = true
	if snap:
		_snap(dt, target.y)
	return dist - mv <= tol


func _snap(dt: float, fallback_y: float) -> void:
	var hit: Dictionary = _ray_down(pos)
	if not hit.is_empty():
		var gy: float = (hit["position"] as Vector3).y
		pos.y = move_toward(pos.y, gy, 14.0 * dt)
		_last_ground_y = pos.y
	else:
		pos.y = move_toward(pos.y, fallback_y, 5.0 * dt)


## Standing on a moving or turning body: go where it goes.
func _ride() -> void:
	if not grounded:
		_ground_body = null
		return
	var hit: Dictionary = _ray_down(pos, 0.6, 1.2)
	var body: Node3D = null
	if not hit.is_empty() and hit["collider"] is Node3D and not (hit["collider"] is StaticBody3D and not (hit["collider"] is AnimatableBody3D)):
		body = hit["collider"] as Node3D
	if body == null:
		_ground_body = null
		return
	if body == _ground_body and body.is_inside_tree():
		var delta: Transform3D = body.global_transform * _ground_xf.affine_inverse()
		pos = delta * pos
	_ground_body = body
	_ground_xf = body.global_transform


## Can it run straight from `a` to `b` (ground the whole way, nothing in the way)?
func _can_cut(a: Vector3, b: Vector3) -> bool:
	var d: Vector3 = RouteMath.flat(b - a)
	var len: float = d.length()
	if len < 3.0:
		return false
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var wall := PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.6, 0), Vector3(b.x, a.y + 0.6, b.z), 1)
	if not space.intersect_ray(wall).is_empty():
		return false
	var n: int = int(len / 2.0)
	for i: int in range(1, n + 1):
		var q: Vector3 = a + d / len * (len * float(i) / float(n + 1))
		q.y = lerpf(a.y, b.y, float(i) / float(n + 1))
		var hit: Dictionary = _ray_down(q, 1.5, 3.0)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - q.y) > 1.0:
			return false
	return true


# ---- waiting -------------------------------------------------------------------------------------------

## Stands still until `open` has held for the reaction time. A short window can slip by while it
## reacts; after a long wait it stops dithering. Returns true when it should go. `can_fail`: a
## mistimed obstacle catches it now and then (respawn).
func _wait_gate(open: bool, dt: float, can_fail: bool = true) -> bool:
	_wait_t += dt
	_speed_now = 0.0
	if not open:
		_gate_left = -1.0
		return false
	if _gate_left < 0.0:
		_gate_left = float(p["react"]) + rng.randf() * float(p["hesitate"]) * 0.6
		if _wait_t > 12.0:
			_gate_left = 0.0
	_gate_left -= dt
	if _gate_left > 0.0:
		return false
	_gate_left = -1.0
	if can_fail and enabled_fail and _wait_t > 0.6 and rng.randf() < float(p["wait_fail"]) and int(_fails_at.get(step, 0)) < 3:
		die("hazard")
		return false
	return true


## The little dither at a takeoff spot (once per jump).
func _takeoff(dt: float) -> bool:
	if _takeoff_left < 0.0:
		_takeoff_left = rng.randf() * float(p["hesitate"])
		if _takeoff_left > 0.05:
			_speed_now = 0.0
	_takeoff_left -= dt
	return _takeoff_left <= 0.0


func _x_wait_open(s: Dictionary) -> bool:
	var lead: float = float(s.get("lead", 0.0))
	var locals: Array = s.get("locals", [Vector3.ZERO])
	for n: Node3D in (s["nodes"] as Array):
		if not is_instance_valid(n):
			continue
		for l: Vector3 in locals:
			if RouteMath.future(n, l, lead).distance_to(s["point"]) <= float(s["radius"]):
				_pick_node = n
				_pick_basis = RouteMath.arm_basis(l)
				return true
	return false


# ---- jumping -----------------------------------------------------------------------------------------

func _fn_for(s: Dictionary) -> Callable:
	if s.has("to_node") and is_instance_valid(s["to_node"]):
		var n: Node3D = s["to_node"]
		var l: Vector3 = s["to_local"]
		return func(lead: float) -> Vector3: return RouteMath.future(n, l, lead)
	var to: Vector3 = s["to"] if typeof(s.get("to")) == TYPE_VECTOR3 else pos
	return func(_lead: float) -> Vector3: return to


func _fn_x(s: Dictionary) -> Callable:
	return func(lead: float) -> Vector3: return _x_target(s, lead)


func _do_jump(s: Dictionary, dt: float, kind: String, fn: Callable) -> void:
	if _phase != 0:
		return
	if _walk_to(s["from"], dt, 0.3) and _takeoff(dt):
		_phase = 1
		_begin_arc(fn, kind)


func _x_node(s: Dictionary, key: String) -> Node3D:
	if s.has(key) and is_instance_valid(s[key]):
		return s[key]
	return _pick_node


func _x_local(s: Dictionary, key: String) -> Vector3:
	var l: Vector3 = s.get(key, Vector3.ZERO)
	if bool(s.get("picked", false)):
		return _pick_basis * l
	return l


func _x_target(s: Dictionary, lead: float) -> Vector3:
	if s.has("to_center"):
		var c: Vector3 = s["to_center"]
		var d: Vector3 = RouteMath.flat(pos - c)
		if d.length() < 0.01:
			return c
		return c + d.normalized() * float(s["to_radius"])
	if s.has("to_local") or s.has("to_node"):
		var n: Node3D = _x_node(s, "to_node")
		if n != null:
			return RouteMath.future(n, _x_local(s, "to_local"), lead)
	return s["to"] if typeof(s.get("to")) == TYPE_VECTOR3 else pos


func _x_trigger(s: Dictionary) -> bool:
	var lead: float = float(s.get("lead", 0.0))
	if s.has("reach"):
		var n: Node3D = s["to_node"]
		if not is_instance_valid(n):
			return true
		for l: Vector3 in (s["to_locals"] as Array):
			if RouteMath.flat(RouteMath.future(n, l, lead) - pos).length() <= float(s["reach"]):
				_pick_node = n
				_pick_basis = RouteMath.arm_basis(l)
				s["to_local"] = Vector3(RouteMath.flat(l).length(), l.y, 0.0)
				s["picked"] = true
				return true
		return false
	if s.has("when_point"):
		var wn: Node3D = _x_node(s, "when_node")
		if wn == null:
			return true
		return RouteMath.future(wn, _x_local(s, "when_local"), lead).distance_to(s["when_point"]) <= float(s["when_radius"])
	return true


func _do_x_jump(s: Dictionary, dt: float) -> void:
	if _phase != 0:
		return
	var ready: bool = true
	if s.has("from") or s.has("from_local"):
		var from: Vector3 = s["from"] if s.has("from") else RouteMath.future(_x_node(s, "from_node"), _x_local(s, "from_local"), 0.05)
		ready = _walk_to(from, dt, 0.3)
	else:
		_speed_now = 0.0
	if not ready:
		return
	var ok: bool = _x_trigger(s)
	if ok and s.has("test"):
		ok = _cond(s["test"] as Callable)
	if _wait_gate(ok, dt):
		_phase = 1
		_begin_arc(_fn_x(s), "jump")


func _do_wall_run(s: Dictionary, dt: float) -> void:
	var entry: Vector3 = s["entry"]
	var exit_p: Vector3 = s["exit"]
	match _phase:
		0:
			if bool(s["chain"]):
				_phase = 2
				return
			if _walk_to(s["from"], dt, 0.3) and _takeoff(dt):
				_phase = 1
				_begin_arc(func(_l: float) -> Vector3: return entry, "jump", func() -> void:
					_phase = 2
					mode = Mode.STEP)
		2:
			# along the panel
			grounded = false
			var along: Vector3 = exit_p - pos
			var spd: float = tuning.wall_run_speed * maxf(float(p["speed"]), 0.8)
			var mv: float = minf(spd * dt, along.length())
			if along.length() > 0.001:
				pos += along.normalized() * mv
			if along.length() - mv <= 0.3:
				_phase = 3
				_begin_arc(_fn_for(s), "jump")


func _do_fly(s: Dictionary, dt: float) -> void:
	var to: Vector3 = (s["to"] as Callable).call() if s["to"] is Callable else s["to"]
	if _phase == 0 and s.has("jump_from"):
		if _walk_to(s["jump_from"], dt, 0.3):
			_phase = 1
			_begin_arc(func(_l: float) -> Vector3: return (s["to"] as Callable).call() if s["to"] is Callable else s["to"], "jump", func() -> void:
				_phase = 2
				mode = Mode.STEP)
		return
	_phase = maxi(_phase, 1)
	var off: Vector3 = to - pos
	var spd: float = tuning.max_speed * float(p["speed"]) * pace
	pos += off.normalized() * minf(spd * dt, off.length()) if off.length() > 0.001 else Vector3.ZERO
	grounded = off.y > -0.5 and off.y < 0.5 and RouteMath.flat(off).length() < 2.0
	if s.has("until"):
		if _cond(s["until"] as Callable):
			grounded = true
			_next()
	elif off.length() < 1.2:
		grounded = true
		_next()


func _do_candy(s: Dictionary, dt: float) -> void:
	var local: Vector3 = s.get("local", Vector3(0, 0.1, 0))
	if _phase == 0:
		if str(s["kind"]) == "candy_board":
			if not _walk_to(s["from"], dt, 0.35):
				return
			var lead: float = float(s.get("lead", 0.45))
			var found: Node3D = null
			for c: Node3D in (s["cars"] as Array):
				if is_instance_valid(c) and RouteMath.flat(RouteMath.future(c, local, lead) - pos).length() <= float(s["reach"]):
					found = c
					break
			if _wait_gate(found != null, dt):
				_candy_pick = found
				_phase = 1
				var pick: Node3D = found
				_begin_arc(func(l: float) -> Vector3: return RouteMath.future(pick, local, l), "jump")
			return
		# candy_ride: hold our spot on the car until it is time to go
		_speed_now = 0.0
		if not _wait_gate(_cond(s["until"] as Callable), dt, false):
			return
		_candy_pick = null
		if s.has("cars"):
			var best: float = INF
			for c: Node3D in (s["cars"] as Array):
				if not is_instance_valid(c):
					continue
				var dd: float = RouteMath.flat(RouteMath.future(c, local, 0.4) - pos).length()
				if dd < best:
					best = dd
					_candy_pick = c
		_phase = 1
		if _candy_pick != null:
			var pick2: Node3D = _candy_pick
			_begin_arc(func(l: float) -> Vector3: return RouteMath.future(pick2, local, l), "jump")
		else:
			_begin_arc(_fn_for(s), "jump")


# ---- arcs ----------------------------------------------------------------------------------------------

## Shape of a jump from height y0 to y1: [air time, extra rise above the straight line].
func _arc_shape(y0: float, y1: float, kind: String) -> Vector2:
	var h: float = tuning.jump_velocity * tuning.jump_velocity / (2.0 * tuning.gravity_rise)
	var apex: float
	match kind:
		"pad":
			apex = maxf(y0, y1) + 4.0
		"mantle":
			apex = y1 + 0.7
		_:
			apex = y0 + h
			if y1 > apex - 0.35:
				apex = y1 + 0.6
	var t_up: float = sqrt(2.0 * maxf(apex - y0, 0.05) / tuning.gravity_rise)
	var t_dn: float = sqrt(2.0 * maxf(apex - y1, 0.02) / tuning.gravity_fall)
	var t: float = t_up + t_dn
	if kind == "mantle":
		t = maxf(t, 0.95)
	return Vector2(t, maxf(apex - (y0 + y1) * 0.5, 0.25))


func _begin_arc(fn: Callable, kind: String, then: Callable = Callable()) -> void:
	_arc_from = pos
	_arc_fn = fn
	_arc_then = then
	_arc_t = 0.0
	var tgt: Vector3 = fn.call(0.4)
	var shape: Vector2 = _arc_shape(pos.y, tgt.y, kind)
	var flat_d: float = RouteMath.flat(tgt - pos).length()
	var reach: float = tuning.max_speed * (1.8 if kind == "pad" else 1.12)
	_arc_T = maxf(maxf(shape.x, flat_d / reach), 0.35)
	_arc_k = shape.y
	_arc_fail = false
	# a long jump can be botched: it falls short (and, over a drop, respawns like a human)
	if kind == "jump" and enabled_fail and flat_d >= 3.0 and _jumped_safe != step and int(_fails_at.get(step, 0)) < 2 \
			and rng.randf() < float(p["jump_fail"]):
		_arc_fail = true
		_arc_short = rng.randf_range(0.5, 0.82)
	mode = Mode.ARC
	grounded = false
	_ground_body = null


func _tick_arc(dt: float) -> void:
	_arc_t += dt
	var s: float = clampf(_arc_t / _arc_T, 0.0, 1.0)
	var remaining: float = maxf(_arc_T - _arc_t, 0.0)
	var tgt: Vector3 = _arc_fn.call(remaining)
	var end: Vector3 = tgt
	if _arc_fail:
		end = Vector3(lerpf(_arc_from.x, tgt.x, _arc_short), minf(_arc_from.y, tgt.y) - 0.4, lerpf(_arc_from.z, tgt.z, _arc_short))
	pos = Vector3(lerpf(_arc_from.x, end.x, s), lerpf(_arc_from.y, end.y, s) + _arc_k * 4.0 * s * (1.0 - s), lerpf(_arc_from.z, end.z, s))
	grounded = false
	if s < 1.0:
		return
	if _arc_fail:
		_arc_fail = false
		_av = Vector3(vel.x, -2.0, vel.z) * 0.9
		mode = Mode.AIR
		return
	pos = tgt
	mode = Mode.STEP
	grounded = true
	_last_ground_y = pos.y
	_speed_now = minf(RouteMath.flat(vel).length(), tuning.max_speed * float(p["speed"]))
	_ground_body = null
	if _arc_then.is_valid():
		_arc_then.call()
	else:
		_next()


func _tick_air(dt: float) -> void:
	_av.y = maxf(_av.y - tuning.gravity_fall * dt, -tuning.max_fall_speed)
	var drag: float = exp(-0.9 * dt)
	_av.x *= drag
	_av.z *= drag
	var np: Vector3 = pos + _av * dt
	grounded = false
	if _av.y <= 0.0:
		_query.from = pos + Vector3(0, 0.4, 0)
		_query.to = np + Vector3(0, -0.08, 0)
		var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(_query)
		if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.55:
			pos = hit["position"]
			_av = Vector3.ZERO
			mode = Mode.STEP
			grounded = true
			_speed_now = 0.0
			if pos.y < _last_ground_y - 4.0:
				die("fall")
				return
			_last_ground_y = pos.y
			_phase = 0
			_takeoff_left = -1.0
			_gate_left = -1.0
			hold = maxf(hold, 0.3)
			return
	pos = np
	if pos.y < _fall_floor():
		die("fall")
