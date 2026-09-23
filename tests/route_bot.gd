class_name RouteBot
extends Node
## Plays a level's annotated main route through the real Player + physics using
## only move/jump commands (no teleporting). Deliberately simple-minded: if this
## can finish a course, the required jumps have healthy margins.

var level: LevelBase
var player: Player
var step_index: int = 0
var retries: int = 0
var done: bool = false
var stuck: bool = false
var log_lines: Array[String] = []
## When true the real OrbitCamera keeps running (visual capture runs); the bot
## then converts its world-space steering into camera-relative input.
var keep_camera: bool = false

var _phase: int = 0
var _step_time: float = 0.0
var _checkpoint_step: int = 0
var _bounced: bool = false
var _pending_bounce: bool = false
var _was_air: bool = false
var _node_prev: Vector3 = Vector3.ZERO
var _node_vel: Vector3 = Vector3.ZERO
var _cur_deaths: int = 0


func attach(lvl: LevelBase) -> void:
	level = lvl
	player = lvl.player
	player.use_device_input = false
	if not keep_camera:
		player.camera_yaw = 0.0
		lvl.camera.set_process(false)
	player.bounced.connect(func(_s: float) -> void: _bounced = true)
	lvl.player_respawned.connect(_on_respawn)


func _on_respawn() -> void:
	retries += 1
	log_lines.append("respawn during step %d (%s)" % [step_index, str(level.route[mini(step_index, level.route.size() - 1)]["kind"])])
	step_index = _checkpoint_step
	_begin_step()
	if retries > 45:
		stuck = true


func _begin_step() -> void:
	_phase = 0
	_step_time = 0.0
	_bounced = false
	_was_air = false
	player.cmd_move = Vector2.ZERO
	player.cmd_jump = false


func _physics_process(dt: float) -> void:
	if level == null or done or stuck:
		return
	if not keep_camera:
		player.camera_yaw = 0.0
	if level.finished:
		done = true
		player.cmd_move = Vector2.ZERO
		return
	if step_index >= level.route.size():
		# route exhausted: keep heading for the last walk target; give up (stuck) if the finish never triggers
		# (only a walk's `to` is a real spot: r_jump_onto stores a placeholder Vector3.ZERO)
		_step_time += dt
		if not level.route.is_empty():
			var last: Dictionary = level.route[level.route.size() - 1]
			if str(last.get("kind", "")) == "walk":
				_steer_ground(last["to"])
		if _step_time > 8.0:
			log_lines.append("route exhausted at %s without reaching the finish" % str(player.global_position.snapped(Vector3.ONE * 0.01)))
			stuck = true
		return
	var step: Dictionary = level.route[step_index]
	_step_time += dt
	if _step_time > 14.0:
		log_lines.append("timeout in step %d phase %d at %s grounded=%s floor=%s" % [step_index, _phase, str(player.global_position.snapped(Vector3.ONE * 0.01)), str(player.grounded), str(player.floor_body)])
		level.respawn()
		return
	match str(step["kind"]):
		"checkpoint":
			_checkpoint_step = step_index + 1
			_next()
		"walk":
			_steer_ground(step["to"])
			if _flat_dist(step["to"]) < 0.6:
				_next()
		"wait":
			player.cmd_move = Vector2.ZERO
			var n: Node3D = step["node"]
			if n.global_position.distance_to(step["point"]) <= float(step["radius"]):
				_next()
		"jump":
			_do_jump(step, dt)
		"pad":
			_do_pad(step, dt)
		"ride_jump":
			_do_ride_jump(step, dt)
		"x_wait", "x_walk_on", "x_jump", "x_pad":
			_do_ext(step)
		"c_wait", "kick":
			_do_foundry(step)
		"b_wait", "b_jump", "b_sweep":
			_do_balance(step, dt)
		"h_jump", "h_hop":
			_do_clock(step)
		"a_fly":
			_do_ascent(step)
		"w_run", "m_climb", "portal":
			_do_moves(step, dt)


func _next() -> void:
	step_index += 1
	_begin_step()


func _target(step: Dictionary, dt: float) -> Vector3:
	if step.has("to_node"):
		var n: Node3D = step["to_node"]
		var p: Vector3 = n.global_transform * (step["to_local"] as Vector3)
		if _node_prev != Vector3.ZERO and dt > 0.0:
			_node_vel = _node_vel.lerp((p - _node_prev) / dt, 0.3)
		_node_prev = p
		return p
	_node_vel = Vector3.ZERO
	return step["to"]


func _do_jump(step: Dictionary, dt: float) -> void:
	var to: Vector3 = _target(step, dt)
	if _phase == 0:
		var from: Vector3 = step["from"]
		_steer_ground(from)
		var dir: Vector3 = _flat(to - from).normalized()
		var passed: bool = _flat(from - player.global_position).dot(dir) < 0.0 and _flat_dist(from) < 1.5
		if player.grounded and (_flat_dist(from) < 0.3 or passed):
			player.press_jump()
			player.cmd_jump = bool(step["hold"])
			_phase = 1
	else:
		_air_phase(to)


func _do_pad(step: Dictionary, dt: float) -> void:
	var to: Vector3 = _target(step, dt)
	if _phase == 0:
		if _pending_bounce:
			_pending_bounce = false
			_bounced = false
			_phase = 1
			return
		_steer_ground(step["from"])
		if _bounced:
			_bounced = false
			_phase = 1
	else:
		_air_phase(to)


func _do_ride_jump(step: Dictionary, dt: float) -> void:
	var to: Vector3 = _target(step, dt)
	if _phase == 0:
		player.cmd_move = Vector2.ZERO
		var n: Node3D = step["node"]
		if step.has("stand"):
			var spot: Vector3 = n.global_transform * (step["stand"] as Vector3)
			var off: Vector3 = _flat(spot - player.global_position)
			if off.length() > 0.12:
				_set_wish(off.normalized() * clampf(off.length() * 1.5, 0.15, 0.7))
		if n.global_position.distance_to(step["point"]) <= float(step["radius"]) and player.grounded:
			player.press_jump()
			player.cmd_jump = bool(step["hold"])
			_phase = 1
	else:
		_air_phase(to)


func _air_phase(to: Vector3) -> void:
	if not player.grounded:
		_was_air = true
	if player.velocity.y <= 0.0:
		player.cmd_jump = false
	_steer_air(to)
	if _bounced and _was_air:
		_pending_bounce = true
		_next()
	elif player.grounded and _was_air:
		_next()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _flat_dist(p: Vector3) -> float:
	return _flat(p - player.global_position).length()


func _set_wish(world: Vector3) -> void:
	if world.length() > 1.0:
		world = world.normalized()
	var local: Vector3 = Basis(Vector3.UP, -player.camera_yaw) * world
	player.cmd_move = Vector2(local.x, -local.z)


func _steer_ground(to: Vector3) -> void:
	var d: Vector3 = _flat(to - player.global_position)
	if not player.grounded:
		_steer_air(to)
		return
	var want: Vector3 = d.normalized() * clampf(d.length() * 2.0, 0.35, 1.0)
	# conveyor running against us: a gentle approach would stall exactly where the belt
	# cancels it, so compensate the belt drag (only when it opposes the intent)
	var fb: Object = player.floor_body
	if fb != null and is_instance_valid(fb) and fb.has_method("surface_velocity"):
		var belt: Vector3 = _flat(fb.call("surface_velocity"))
		if belt.length() > 0.1 and belt.dot(want) < 0.0:
			want = want - belt / player.tuning.max_speed
	_set_wish(want)


func _time_to_reach(y_target: float) -> float:
	var t: MovementTuning = player.tuning
	var y: float = player.global_position.y
	var vy: float = player.velocity.y
	var time: float = 0.0
	var step: float = 1.0 / 60.0
	while time < 4.0:
		var g: float = t.gravity_rise if vy > 0.0 else t.gravity_fall
		vy = maxf(vy - g * step, -t.max_fall_speed)
		y += vy * step
		time += step
		if vy <= 0.0 and y <= y_target:
			break
	return time


func _steer_air(to: Vector3) -> void:
	var remaining: float = maxf(_time_to_reach(to.y), 0.12)
	var aim: Vector3 = to + _node_vel * remaining
	var need: Vector3 = _flat(aim - player.global_position) / remaining
	var hv: Vector3 = _flat(player.velocity)
	var err: Vector3 = need - hv
	_set_wish(err * 0.6)


# ---- extended steps for deterministic movers / spinners (additive) ---------------------------
# Kinematic platforms are pure functions of Game.course_time, so instead of
# extrapolating a measured velocity these steps ask the platform where it WILL be.
#   x_wait    {nodes, locals, point, radius, lead}      stand still until any node/local is (in `lead` s) near point; remembers the pick
#   x_walk_on {node|picked, local, tol}                 walk to a spot riding on a platform
#   x_jump    {from | from_local(+from_node|picked) | neither = jump where we stand,
#              optional trigger: when_node|picked + when_local + when_point + when_radius + lead, or reach (+lead),
#              target: to | to_node/picked + to_local | to_locals (with reach) | to_center + to_radius, hold}
#   x_pad     {from, target as above}
# "picked": true means: use the node chosen by the last x_wait / reach pick, and
# read locals in the picked arm frame (+X along the picked arm).

var _pick_node: Node3D = null
var _pick_basis: Basis = Basis.IDENTITY


func _future(n: Node3D, local: Vector3, lead: float) -> Vector3:
	var now: float = Game.course_time
	if n is MovingPlatform:
		var m := n as MovingPlatform
		return m.global_position - m.offset_at(now) + m.offset_at(now + lead) + local
	if n is RotatingPlatform:
		var r := n as RotatingPlatform
		return r.global_position + Basis(Vector3.UP, r.angle_at(now + lead)) * local
	return n.global_transform * local


func _arm_basis(local: Vector3) -> Basis:
	var d: Vector3 = _flat(local)
	if d.length() < 0.1:
		return Basis.IDENTITY
	d = d.normalized()
	return Basis(d, Vector3.UP, d.cross(Vector3.UP))


func _x_node(step: Dictionary, key: String) -> Node3D:
	if step.has(key):
		return step[key]
	return _pick_node


func _x_local(step: Dictionary, key: String) -> Vector3:
	var l: Vector3 = step.get(key, Vector3.ZERO)
	if bool(step.get("picked", false)):
		return _pick_basis * l
	return l


func _x_target(step: Dictionary, lead: float) -> Vector3:
	if step.has("to_center"):
		var c: Vector3 = step["to_center"]
		var d: Vector3 = _flat(player.global_position - c)
		if d.length() < 0.01:
			return c
		return c + d.normalized() * float(step["to_radius"])
	if step.has("to_local") or step.has("to_node"):
		return _future(_x_node(step, "to_node"), _x_local(step, "to_local"), lead)
	return step["to"]


func _x_trigger(step: Dictionary) -> bool:
	var lead: float = float(step.get("lead", 0.0))
	if step.has("reach"):
		var me: Vector3 = player.global_position + player.platform_velocity * lead
		var n: Node3D = step["to_node"]
		for l: Vector3 in (step["to_locals"] as Array):
			if _flat(_future(n, l, lead) - me).length() <= float(step["reach"]):
				_pick_node = n
				_pick_basis = _arm_basis(l)
				step["to_local"] = Vector3(_flat(l).length(), l.y, 0.0)
				step["picked"] = true
				return true
		return false
	if step.has("when_point"):
		var wn: Node3D = _x_node(step, "when_node")
		return _future(wn, _x_local(step, "when_local"), lead).distance_to(step["when_point"]) <= float(step["when_radius"])
	return true


func _do_ext(step: Dictionary) -> void:
	match str(step["kind"]):
		"x_wait":
			player.cmd_move = Vector2.ZERO
			var lead: float = float(step.get("lead", 0.0))
			var locals: Array = step.get("locals", [Vector3.ZERO])
			for n: Node3D in (step["nodes"] as Array):
				for l: Vector3 in locals:
					if _future(n, l, lead).distance_to(step["point"]) <= float(step["radius"]):
						_pick_node = n
						_pick_basis = _arm_basis(l)
						_next()
						return
		"x_walk_on":
			var spot: Vector3 = _future(_x_node(step, "node"), _x_local(step, "local"), 0.05)
			_steer_ground(spot)
			if _flat_dist(spot) < float(step.get("tol", 0.35)) and player.grounded:
				_next()
		"x_jump":
			if _phase == 0:
				var ready: bool = player.grounded
				if step.has("from") or step.has("from_local"):
					var from: Vector3 = step["from"] if step.has("from") else _future(_x_node(step, "from_node"), _x_local(step, "from_local"), 0.05)
					_steer_ground(from)
					var to0: Vector3 = _x_target(step, 0.0) if not step.has("to_locals") else from
					var dir: Vector3 = _flat(to0 - from).normalized()
					var passed: bool = _flat(from - player.global_position).dot(dir) < 0.0 and _flat_dist(from) < 1.5
					ready = ready and (_flat_dist(from) < 0.3 or passed)
				else:
					player.cmd_move = Vector2.ZERO
				if ready and _x_trigger(step):
					player.press_jump()
					player.cmd_jump = bool(step.get("hold", true))
					_phase = 1
			else:
				_x_air(step)
		"x_pad":
			if _phase == 0:
				if _pending_bounce:
					_pending_bounce = false
					_bounced = false
					_phase = 1
					return
				_steer_ground(step["from"])
				if _bounced:
					_bounced = false
					_phase = 1
			else:
				_x_air(step)


func _x_air(step: Dictionary) -> void:
	if not player.grounded:
		_was_air = true
	if player.velocity.y <= 0.0:
		player.cmd_jump = false
	var remaining: float = maxf(_time_to_reach(_x_target(step, 0.0).y), 0.12)
	var aim: Vector3 = _x_target(step, remaining)
	remaining = maxf(_time_to_reach(aim.y), 0.12)
	aim = _x_target(step, remaining)
	var need: Vector3 = _flat(aim - player.global_position) / remaining
	_set_wish((need - _flat(player.velocity)) * 0.6)
	if _bounced and _was_air:
		_pending_bounce = true
		_next()
	elif player.grounded and _was_air:
		_next()


# ---- foundry steps (additive): clock waits and being thrown by bumpers / hammers / pads ----------
#   c_wait {period, lo, hi, offset}   stand still until fposmod(course_time / period + offset, 1) is inside [lo, hi)
#   kick   {from, to}                 steer at `from` (ground or air) until something throws us upward
#                                     (bumper, hammer, pad), then air-steer to `to`. Chains like pad steps.

var _fk_prev_vy: float = 0.0
var _fk_pending: bool = false
var _fk_step: int = -1


func _do_foundry(step: Dictionary) -> void:
	if str(step["kind"]) == "c_wait":
		player.cmd_move = Vector2.ZERO
		var u: float = fposmod(Game.course_time / float(step["period"]) + float(step.get("offset", 0.0)), 1.0)
		if u >= float(step["lo"]) and u < float(step["hi"]) and player.grounded:
			_next()
		return
	if _fk_step != step_index or _step_time < 0.02:
		_fk_step = step_index
		_fk_prev_vy = player.velocity.y
		if not _fk_pending and _pending_bounce:
			_fk_pending = true
		_pending_bounce = false
	var vy: float = player.velocity.y
	var kicked: bool = vy - _fk_prev_vy > 3.0
	_fk_prev_vy = vy
	if _phase == 0:
		if _fk_pending:
			_fk_pending = false
			_phase = 1
			return
		_steer_ground(step["from"])
		if kicked:
			_phase = 1
	else:
		if not player.grounded:
			_was_air = true
		_steer_air(step["to"])
		if kicked and _step_time > 0.1:
			_fk_pending = true
			_next()
		elif player.grounded and _was_air:
			_next()


# ---- balance steps (additive): level-supplied conditions, board peaks, sweeper floors ------------
#   b_wait  {test: Callable, hold?: Vector3}  stand still (or hold a world spot against board slip) until test.call() is true
#   b_jump  {from, to, hold, aim?}            exactly a "jump" step the validator skips (catapult jumps off a swung-up board);
#                                             `aim` overrides the air-steer target (cross-wind compensation)
#   b_sweep {to, sweeper, tol?}               walk to `to` across a Sweeper floor, hopping each bar just before it arrives


func _do_balance(step: Dictionary, dt: float) -> void:
	match str(step["kind"]):
		"b_wait":
			player.cmd_move = Vector2.ZERO
			if step.has("hold"):
				var off: Vector3 = _flat((step["hold"] as Vector3) - player.global_position)
				if off.length() > 0.1:
					_set_wish(off.normalized() * clampf(off.length() * 1.5, 0.15, 1.0))
			if player.grounded and bool((step["test"] as Callable).call()):
				_next()
		"b_jump":
			if _phase == 0:
				_do_jump(step, dt)
			else:
				_air_phase(step.get("aim", step["to"]))
		"b_sweep":
			var sw: Sweeper = step["sweeper"]
			var to: Vector3 = step["to"]
			if player.grounded:
				_steer_ground(to)
				var rel: Vector3 = _flat(player.global_position + _flat(player.velocity) * 0.15 - sw.global_position)
				if rel.length() < sw.arm_length + 0.8 and rel.length() > 0.5:
					var me: float = atan2(-rel.z, rel.x)
					var w: float = TAU / sw.period
					for i: int in sw.bar_count:
						var bar: float = sw.angle_at(Game.course_time) + TAU * float(i) / float(sw.bar_count)
						var gap: float = fposmod(me - bar, TAU)
						if gap / absf(w) < 0.3 or TAU - gap < 0.12:
							player.press_jump()
							player.cmd_jump = true
			else:
				if player.velocity.y <= 0.0:
					player.cmd_jump = false
				_steer_air(to)
			if _flat_dist(to) < float(step.get("tol", 0.6)) and player.grounded:
				_next()


# ---- clockwork hard-mode steps (additive) ---------------------------------------------------------
#   h_jump {x_jump fields..., test?: Callable, sprint?: bool}   an x_jump that (a) only fires once test.call() is true and
#                                                              (b) with sprint keeps full stick all the way to the takeoff
#                                                              spot (needed to stack run speed on a fast mover / hand).
#   h_hop  {node|picked, local, sweepers: Array, until: Callable}     hold a spot riding `node` and hop every bar (Sweeper or duck-typed) that is
#                                                              about to cross us; ends (grounded) once until.call() is true.

func _do_clock(step: Dictionary) -> void:
	match str(step["kind"]):
		"h_jump":
			if _phase == 0:
				var ready: bool = player.grounded
				if step.has("from") or step.has("from_local"):
					var from: Vector3 = step["from"] if step.has("from") else _future(_x_node(step, "from_node"), _x_local(step, "from_local"), 0.05)
					_steer_ground(from)
					var d: Vector3 = _flat(from - player.global_position)
					if bool(step.get("sprint", false)) and player.grounded and d.length() > 0.05:
						_set_wish(d.normalized())
					var to0: Vector3 = _x_target(step, 0.0) if not step.has("to_locals") else from
					var dir: Vector3 = _flat(to0 - from).normalized()
					var passed: bool = d.dot(dir) < 0.0 and d.length() < 1.5
					ready = ready and (d.length() < 0.3 or passed)
				else:
					player.cmd_move = Vector2.ZERO
				if step.has("test") and _step_time < 0.03:
					ready = false
				if ready and (not step.has("test") or bool((step["test"] as Callable).call())) and _x_trigger(step):
					player.press_jump()
					player.cmd_jump = bool(step.get("hold", true))
					_phase = 1
			else:
				_x_air(step)
		"h_hop":
			var n: Node3D = _x_node(step, "node")
			var local: Vector3 = _x_local(step, "local")
			if player.grounded:
				var spot: Vector3 = _future(n, local, 0.05)
				var off: Vector3 = _flat(spot - player.global_position)
				player.cmd_move = Vector2.ZERO
				if off.length() > 0.12:
					_set_wish(off.normalized() * clampf(off.length() * 1.5, 0.15, 0.8))
				var lead: float = float(step.get("lead", 0.22))
				var hop: bool = false
				for sw: Node3D in (step["sweepers"] as Array):
					for i: int in int(sw.get("bar_count")):
						var a0: float = _h_gap(sw, i, player.global_position, Game.course_time)
						var a1: float = _h_gap(sw, i, _future(n, local, lead), Game.course_time + lead)
						var r: float = _flat(player.global_position - sw.global_position).length()
						if r < float(sw.get("arm_length")) + 0.9 and r > 0.4 and (absf(a1) * r < 0.75 or (a0 * a1 < 0.0 and absf(a0) < 1.5)):
							hop = true
				if hop:
					player.press_jump()
					player.cmd_jump = true
				elif bool((step["until"] as Callable).call()):
					_next()
			else:
				if player.velocity.y <= 0.0:
					player.cmd_jump = false
				var remaining: float = maxf(_time_to_reach(_future(n, local, 0.0).y), 0.12)
				var aim: Vector3 = _future(n, local, remaining)
				_set_wish((_flat(aim - player.global_position) / remaining - _flat(player.velocity)) * 0.6)


## Signed angle (rad) from bar `i` of a sweeper to world point `p` at course time `t`.
## `sw` is a Sweeper or any Node3D with angle_at(t), bar_count and arm_length (duck typed).
func _h_gap(sw: Node3D, i: int, p: Vector3, t: float) -> float:
	var rel: Vector3 = _flat(p - sw.global_position)
	var me: float = atan2(-rel.z, rel.x)
	var bar: float = float(sw.call("angle_at", t)) + TAU * float(i) / float(int(sw.get("bar_count")))
	return wrapf(me - bar, -PI, PI)


# ---- final ascent steps (additive) ----------------------------------------------------------------
#   a_fly {to, until?: Callable, gain?: float, damp?: float}   position-hold steering toward `to` (ground or air) for places where
#                                                              the ballistic landing estimate is meaningless (updraft columns,
#                                                              drifting under wind). Ends when until.call() is true, or - with no
#                                                              `until` - on landing after having been airborne.

func _do_ascent(step: Dictionary) -> void:
	var off: Vector3 = _flat((step["to"] as Vector3) - player.global_position)
	_set_wish(off * float(step.get("gain", 1.6)) - _flat(player.velocity) * float(step.get("damp", 0.45)))
	if player.velocity.y <= 0.0:
		player.cmd_jump = false
	if not player.grounded:
		_was_air = true
	if step.has("until"):
		if bool((step["until"] as Callable).call()):
			_next()
	elif player.grounded and _was_air:
		_next()


# ---- wall runs, mantles and warps (level extension, additive) -----------------------------------
#   w_run   {from, entry, exit, to, kick, chain}  jump at a wall-run panel toward entry, run it toward exit, kick off
#                                                 (or ride it off the end) and steer to `to`. chain = already airborne:
#                                                 the step ends as soon as the NEXT panel is latched, or on landing.
#   m_climb {from, top}                           jump at a ledge, hold toward it until the mantle is done
#   portal  {to, exit}                            run through the entry ring at `to` until we come out near `exit`

func _do_moves(step: Dictionary, dt: float) -> void:
	match str(step["kind"]):
		"w_run":
			var entry: Vector3 = step["entry"]
			var exit: Vector3 = step["exit"]
			if _phase == 0:
				if bool(step["chain"]):
					_phase = 1
				else:
					_do_jump({"from": step["from"], "to": entry, "hold": true}, dt)
					return
			if _phase == 1:
				if not player.grounded:
					_was_air = true
				if player.is_wall_running():
					_phase = 2
				elif player.grounded and _was_air:
					log_lines.append("w_run %d: landed without latching at %s" % [step_index, str(player.global_position.snapped(Vector3.ONE * 0.01))])
					level.respawn()
					return
				else:
					if player.velocity.y <= 0.0:
						player.cmd_jump = false
					_set_wish(_flat(entry - player.global_position).normalized())
					return
			if _phase == 2:
				var along: Vector3 = _flat(exit - entry).normalized()
				_set_wish(along)
				player.cmd_jump = false
				var left: float = _flat(exit - player.global_position).dot(along)
				if bool(step["kick"]) and left < 0.4 and player.is_wall_running():
					player.press_jump()
					player.cmd_jump = true
					_phase = 3
					_was_air = true
				elif not player.is_wall_running():
					_phase = 3
					_was_air = true
				return
			# phase 3: flying off the wall
			if player.is_wall_running():
				_next()
				return
			_air_phase(step["to"])
		"m_climb":
			var top: Vector3 = step["top"]
			if _phase == 0:
				_do_jump({"from": step["from"], "to": top, "hold": true}, dt)
				return
			if _phase == 1:
				if not player.grounded:
					_was_air = true
				if player.velocity.y <= 0.0:
					player.cmd_jump = false
				_set_wish(_flat(top - player.global_position).normalized())
				if player.is_mantling():
					_phase = 2
				elif player.grounded and _was_air and player.global_position.y < top.y - 0.5:
					log_lines.append("m_climb %d: missed the ledge at %s" % [step_index, str(player.global_position.snapped(Vector3.ONE * 0.01))])
					level.respawn()
				return
			player.cmd_move = Vector2.ZERO
			if not player.is_mantling() and player.grounded:
				_next()
		"portal":
			var exit_p: Vector3 = step["exit"]
			if _flat_dist(exit_p) < 3.0 and absf(player.global_position.y - exit_p.y) < 3.0:
				_next()
				return
			_set_wish(_flat((step["to"] as Vector3) - player.global_position).normalized())
