class_name Player
extends CharacterBody3D
## Upright kinematic character. All acceleration, gravity, platform inheritance,
## external impulses and load transfer into dynamic objects are explicit here;
## every number comes from a MovementTuning resource.

signal jumped
signal landed(impact_speed: float)
signal bounced(strength: float)
signal teleported
## A hazard (bumper, hammer) threw the player: `v` is the velocity it imposed.
signal knocked(v: Vector3)
## Latched onto a wall-run panel (`normal` points away from the wall).
signal wall_run_started(normal: Vector3)
signal wall_jumped
## Caught a ledge and started climbing onto it.
signal mantled

@export var tuning: MovementTuning

## Set by the orbit camera every frame; movement is relative to it.
var camera_yaw: float = 0.0
## False during countdowns / finish: gravity still applies, input is ignored.
var control_enabled: bool = true
## Bots and tests set this false and drive cmd_* instead of the keyboard.
var use_device_input: bool = true
var cmd_move: Vector2 = Vector2.ZERO
var cmd_jump: bool = false

# --- read-only state for camera / visuals / debug overlay ---
var grounded: bool = false
var air_time: float = 0.0
var floor_body: Object = null
var platform_velocity: Vector3 = Vector3.ZERO
var last_jump_height: float = 0.0
var last_jump_distance: float = 0.0
var last_ground_y: float = 0.0
var facing_dir: Vector3 = Vector3.FORWARD
## Stick / key magnitude this tick (0 while control is off). Read only by feedback
## (footsteps), never by movement.
var move_input: float = 0.0
## Party-mode power-ups scale movement through these; the main mode never touches them
## (1.0 = the tuned game). speed: run speed; jump: takeoff speed; gravity: both gravities.
var speed_mult: float = 1.0
var jump_mult: float = 1.0
var gravity_mult: float = 1.0
## Party Mode only (0 in the main mode): seconds of stun left (input ignored, like control
## off but gravity and knockback still act), and extra mid-air jumps per airtime.
var party_stun: float = 0.0
var party_air_jumps: int = 0
var _air_jumps_used: int = 0

var _coyote: float = 0.0
var _buffer: float = 0.0
var _jumping: bool = false       # rising from our own jump (variable height applies)
var _jump_was_held: bool = false
var _no_snap: float = 0.0
var _takeoff_pos: Vector3 = Vector3.ZERO
var _apex_y: float = 0.0
var _pad_cooldown: Dictionary = {}
var _jump_press_queued: bool = false
var _teleported: bool = false    # until the next move: ignore the pre-teleport floor/platform
var _platform_layers_saved: int = 0
# wall run: only on bodies with is_wall_run(). _wall_dir is the run direction along the wall.
var _wall_body: Object = null
var _wall_normal: Vector3 = Vector3.ZERO
var _wall_dir: Vector3 = Vector3.ZERO
var _wall_speed: float = 0.0
var _wall_time: float = 0.0
var _wall_coyote: float = 0.0
var _wall_last: Object = null     # the panel last run on: no re-latch to it until we touch ground
# mantle: only on bodies with is_ledge(). A short scripted climb, -1 when not climbing.
var _mantle_t: float = -1.0
var _mantle_from: Vector3 = Vector3.ZERO
var _mantle_to: Vector3 = Vector3.ZERO
var _mantle_dir: Vector3 = Vector3.ZERO


func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/default_tuning.tres") as MovementTuning
	floor_max_angle = deg_to_rad(tuning.floor_max_angle_deg)
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	max_slides = 6
	# Platform velocity is inherited by hand (see _inherit_platform_velocity) so it
	# is applied exactly once and can be filtered.
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	collision_layer = 2
	collision_mask = 1 | 8
	last_ground_y = global_position.y


func _unhandled_input(event: InputEvent) -> void:
	if use_device_input and event.is_action_pressed("jump") and not event.is_echo():
		_jump_press_queued = true


## Bots/tests call this for a jump press edge.
func press_jump() -> void:
	_jump_press_queued = true


func _physics_process(dt: float) -> void:
	var t: MovementTuning = tuning
	var move: Vector2 = cmd_move
	var jump_held: bool = cmd_jump
	if use_device_input:
		move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		jump_held = Input.is_action_pressed("jump")
	if not control_enabled:
		move = Vector2.ZERO
		jump_held = false
		_jump_press_queued = false
	if party_stun > 0.0:
		party_stun = maxf(party_stun - dt, 0.0)
		move = Vector2.ZERO
		jump_held = false
		_jump_press_queued = false
	if move.length() > 1.0:
		move = move.normalized()
	move_input = move.length()
	var wish: Vector3 = Basis(Vector3.UP, camera_yaw) * Vector3(move.x, 0.0, -move.y)

	var was_grounded: bool = grounded
	# Right after a jump or pad launch the stale floor flag must not count
	# (it would grant coyote time and let a buffered jump overwrite the launch).
	# Likewise the floor we stood on before a teleport.
	var on_floor: bool = is_on_floor() and _no_snap <= 0.0 and not _teleported

	# --- timers ---
	if _jump_press_queued:
		_buffer = t.jump_buffer_time
		_jump_press_queued = false
	else:
		_buffer = maxf(_buffer - dt, 0.0)
	if on_floor:
		_coyote = t.coyote_time
	else:
		_coyote = maxf(_coyote - dt, 0.0)
	_no_snap = maxf(_no_snap - dt, 0.0)
	for key: int in _pad_cooldown.keys():
		_pad_cooldown[key] = float(_pad_cooldown[key]) - dt
		if float(_pad_cooldown[key]) <= 0.0:
			_pad_cooldown.erase(key)
	_wall_coyote = maxf(_wall_coyote - dt, 0.0)

	# --- mantle: a scripted climb owns the body until it ends ---
	if _mantle_t >= 0.0:
		_mantle_step(dt)
		return

	# --- wall run / wall jump / ledge grab (airborne only) ---
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		_wall_last = null
		if _wall_body != null:
			_end_wall_run()
	else:
		if _wall_body != null:
			_wall_time += dt
			if _wall_time > t.wall_run_time or wish.dot(_wall_normal) > 0.5 or not _wall_still_there():
				_end_wall_run()
		elif air_time > 0.04 and control_enabled:
			_try_wall_run(hv)
		if _wall_body == null and control_enabled and _try_mantle(wish, hv):
			_mantle_step(dt)
			return
	if (_wall_body != null or _wall_coyote > 0.0) and _buffer > 0.0 and control_enabled:
		_wall_jump()
		hv = Vector3(velocity.x, 0.0, velocity.z)

	# --- horizontal ---
	if _wall_body != null:
		_wall_speed = maxf(_wall_speed, hv.dot(_wall_dir))
		# hug the wall a little so the slide keeps touching it
		hv = _wall_dir * _wall_speed - _wall_normal * 1.0
	elif on_floor:
		hv = _surface_move(hv, wish, dt)
	else:
		hv = _air_move(hv, wish, dt)
	if hv.length() > t.hard_speed_cap:
		hv = hv.normalized() * t.hard_speed_cap
	velocity.x = hv.x
	velocity.z = hv.z

	# --- vertical ---
	if _wall_body != null:
		velocity.y -= t.wall_run_gravity * dt
	elif not on_floor:
		var g: float = t.gravity_fall * gravity_mult
		if velocity.y > 0.0:
			g = t.gravity_rise * gravity_mult
			if _jumping and not jump_held:
				g *= t.jump_cut_multiplier
		if _jumping and jump_held and absf(velocity.y) < t.apex_hang_speed:
			g *= t.apex_hang_multiplier
		velocity.y = maxf(velocity.y - g * dt, -t.max_fall_speed)
		if velocity.y <= 0.0:
			_jumping = false

	# --- jump: fires the same tick the press is seen ---
	if _buffer > 0.0 and (on_floor or _coyote > 0.0) and control_enabled:
		_buffer = 0.0
		_coyote = 0.0
		velocity.y = t.jump_velocity * jump_mult
		_jumping = true
		_no_snap = 0.12
		_begin_flight_stats()
		jumped.emit()
	elif party_air_jumps > 0 and _buffer > 0.0 and not on_floor and control_enabled and _wall_body == null \
			and _air_jumps_used < party_air_jumps:
		# Party Mode double jump (Golden Surge Hair); party_air_jumps is 0 everywhere else
		_air_jumps_used += 1
		_buffer = 0.0
		velocity.y = maxf(velocity.y, t.jump_velocity * jump_mult)
		_jumping = true
		_no_snap = 0.12
		_begin_flight_stats()
		jumped.emit()
	if on_floor:
		_air_jumps_used = 0

	floor_snap_length = 0.0 if _no_snap > 0.0 else t.floor_snap
	var pre_move_velocity: Vector3 = velocity
	move_and_slide()
	if _teleported:
		_teleported = false
		platform_floor_layers = _platform_layers_saved

	# --- post-move bookkeeping ---
	grounded = is_on_floor()
	_scan_collisions(pre_move_velocity, dt)
	if grounded:
		platform_velocity = get_platform_velocity()
		last_ground_y = global_position.y
		if not was_grounded:
			_on_landed(pre_move_velocity)
		air_time = 0.0
	else:
		if was_grounded:
			_inherit_platform_velocity()
			if not _jumping:
				_begin_flight_stats()
		air_time += dt
		_apex_y = maxf(_apex_y, global_position.y)
		floor_body = null
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.5:
		facing_dir = flat.normalized()
	elif wish.length() > 0.1:
		facing_dir = wish.normalized()


## `bias` is a velocity the surface imposes (sliding down a steep board): the
## player's input steers relative to it, so standing still means drifting downhill.
## Ground movement including what the surface itself does to the player:
##  * slip bias on steep tilt boards, conveyor belts (surface_velocity)
##  * slick surfaces (grip < 1): weak traction, and slopes accelerate you downhill
##  * boost strips: drive speed along their arrow up to a target, which the normal
##    over-speed rules then let you carry into jumps
func _surface_move(hv: Vector3, wish: Vector3, dt: float) -> Vector3:
	var bias: Vector3 = _slip_bias()
	var grip: float = 1.0
	var fb: Object = floor_body if (floor_body != null and is_instance_valid(floor_body)) else null
	if fb != null:
		if fb.has_method("surface_velocity"):
			bias += fb.call("surface_velocity") as Vector3
		if fb.has_method("grip"):
			grip = clampf(float(fb.call("grip")), 0.02, 1.0)
	hv = _ground_move(hv, wish, dt, bias, grip)
	if grip < 1.0:
		var n: Vector3 = get_floor_normal()
		var downhill := Vector3(n.x, 0.0, n.z)
		if downhill.length() > 0.02:
			var steep: float = sqrt(maxf(1.0 - n.y * n.y, 0.0))
			hv += downhill.normalized() * tuning.gravity_fall * steep * (1.0 - grip) * dt
	if fb != null and fb.has_method("boost"):
		var b: Dictionary = fb.call("boost")
		var dir: Vector3 = b["dir"]
		var along: float = hv.dot(dir)
		var target: float = float(b["speed"])
		if along < target:
			hv += dir * minf(float(b["accel"]) * dt, target - along)
	return hv


func _ground_move(hv: Vector3, wish: Vector3, dt: float, bias: Vector3 = Vector3.ZERO, grip: float = 1.0) -> Vector3:
	var t: MovementTuning = tuning
	var speed: float = hv.length()
	if wish.length() < 0.01:
		return hv.move_toward(bias, t.ground_brake * grip * dt)
	var top: float = t.max_speed * speed_mult
	if speed > top and hv.dot(wish) > 0.0:
		# Carrying extra momentum (pad landing, platform fling): keep it, let the
		# player steer it, bleed it gently instead of clamping.
		var new_speed: float = move_toward(speed, top, t.overspeed_friction * grip * dt)
		var dir: Vector3 = hv.normalized().slerp(wish.normalized(), clampf(t.overspeed_steer * maxf(grip, 0.35) * dt, 0.0, 1.0))
		return dir.normalized() * new_speed
	var rate: float = t.turn_accel if hv.dot(wish) < 0.0 else t.ground_accel
	return hv.move_toward(wish * top + bias, rate * speed_mult * grip * dt)


func _air_move(hv: Vector3, wish: Vector3, dt: float) -> Vector3:
	var t: MovementTuning = tuning
	var speed: float = hv.length()
	if wish.length() < 0.01:
		hv = hv.move_toward(Vector3.ZERO, t.air_brake * dt)
	else:
		# Input can redirect and correct, but never pushes speed past what the
		# player already earned (or max_speed, whichever is higher).
		var top: float = t.max_speed * speed_mult
		var limit: float = maxf(speed, top * wish.length())
		hv += wish * t.air_accel * speed_mult * dt
		if hv.length() > limit:
			hv = hv.normalized() * limit
	speed = hv.length()
	if speed > t.max_speed * speed_mult:
		hv = hv.normalized() * move_toward(speed, t.max_speed * speed_mult, t.air_overspeed_drag * dt)
	return hv


## Steeply tilted boards slide the player downhill: the balance rule.
## Returns the downhill drift velocity for the current floor (zero on normal ground).
func _slip_bias() -> Vector3:
	if floor_body == null or not floor_body.has_method("is_slippery"):
		return Vector3.ZERO
	var n: Vector3 = get_floor_normal()
	var angle_deg: float = rad_to_deg(acos(clampf(n.dot(Vector3.UP), -1.0, 1.0)))
	if angle_deg <= tuning.slip_start_deg:
		return Vector3.ZERO
	var downhill := Vector3(n.x, 0.0, n.z)
	if downhill.length() < 0.001:
		return Vector3.ZERO
	return downhill.normalized() * (angle_deg - tuning.slip_start_deg) * tuning.slip_speed_per_deg


func _scan_collisions(pre_velocity: Vector3, dt: float) -> void:
	var floor_cos: float = cos(floor_max_angle)
	var found_floor: Object = null
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body == null:
			continue
		var n: Vector3 = col.get_normal()
		if body.has_method("get_launch"):
			if _try_bounce(body, n):
				return
		if n.dot(Vector3.UP) >= floor_cos:
			found_floor = body
		if body is RigidBody3D:
			var rb := body as RigidBody3D
			var into: float = maxf(-pre_velocity.dot(n), 0.0)
			rb.apply_impulse(-n * into * tuning.mass * tuning.prop_push * dt * 8.0, col.get_position() - rb.global_position)
	if grounded:
		# move_and_slide only reports a floor contact on ticks where it actually
		# pushed into it, so identify the floor with a short ray every tick instead:
		# weight must reach tilting boards continuously, not intermittently.
		if found_floor == null:
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.4, 0), global_position - Vector3(0, 0.45, 0), collision_mask)
			q.exclude = [get_rid()]
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				found_floor = hit["collider"]
		if found_floor != null:
			floor_body = found_floor
		if floor_body != null and is_instance_valid(floor_body) and floor_body.has_method("apply_rider_load"):
			floor_body.call("apply_rider_load", global_position, tuning.mass * tuning.gravity_fall)


func _try_bounce(pad: Object, normal: Vector3) -> bool:
	var id: int = pad.get_instance_id()
	if _pad_cooldown.has(id):
		return false
	var surface_up: Vector3 = pad.call("get_surface_up")
	if normal.dot(surface_up) < 0.6:
		return false
	var launch: Dictionary = pad.call("get_launch")
	var v: Vector3 = launch["velocity"]
	_cancel_moves()
	if bool(launch["keep_horizontal"]):
		velocity.y = v.y
	else:
		velocity = v
	_pad_cooldown[id] = 0.2
	_jumping = false
	_no_snap = 0.15
	_coyote = 0.0
	grounded = false
	_begin_flight_stats()
	pad.call("on_bounced", self)
	bounced.emit(v.length())
	return true


# ---- wall run and mantle ----------------------------------------------------

## Ray from chest height; returns the hit only when it is a near-vertical face of a
## body that answers `method` (is_wall_run / is_ledge).
func _probe(from: Vector3, to: Vector3, method: String) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	q.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var body: Object = hit["collider"]
	var n: Vector3 = hit["normal"]
	if body == null or not body.has_method(method) or absf(n.y) > 0.35:
		return {}
	return hit


## Latch onto a wall-run panel beside or ahead of us while moving along it fast enough.
func _try_wall_run(hv: Vector3) -> void:
	var t: MovementTuning = tuning
	if hv.length() < t.wall_run_min_speed or velocity.y < -t.wall_run_max_entry_fall:
		return
	var fwd: Vector3 = hv.normalized()
	var chest: Vector3 = global_position + Vector3(0, 0.9, 0)
	var reach: float = 0.38 + 0.4
	for dir: Vector3 in [fwd.rotated(Vector3.UP, PI * 0.5), fwd.rotated(Vector3.UP, -PI * 0.5), fwd.rotated(Vector3.UP, PI * 0.25), fwd.rotated(Vector3.UP, -PI * 0.25), fwd]:
		var hit: Dictionary = _probe(chest, chest + dir * reach, "is_wall_run")
		if hit.is_empty() or hit["collider"] == _wall_last:
			continue
		var n: Vector3 = hit["normal"]
		n = Vector3(n.x, 0.0, n.z).normalized()
		var along_dir: Vector3 = n.cross(Vector3.UP).normalized()
		if hv.dot(along_dir) < 0.0:
			along_dir = -along_dir
		var along: float = hv.dot(along_dir)
		if along < t.wall_run_min_speed:
			continue
		_wall_body = hit["collider"]
		_wall_normal = n
		_wall_dir = along_dir
		_wall_speed = maxf(along, t.wall_run_speed)
		_wall_time = 0.0
		_jumping = false
		velocity.y = clampf(velocity.y, t.wall_run_lift, t.wall_run_lift_max)
		_begin_flight_stats()
		wall_run_started.emit(n)
		return


## Any part of the body (feet, middle, head) still alongside a panel.
func _wall_still_there() -> bool:
	for h: float in [0.2, 0.65, 1.1]:
		var p: Vector3 = global_position + Vector3(0, h, 0)
		if not _probe(p, p - _wall_normal * (0.38 + 0.5), "is_wall_run").is_empty():
			return true
	return false


func _end_wall_run() -> void:
	if _wall_body == null:
		return
	_wall_last = _wall_body
	_wall_body = null
	_wall_coyote = tuning.wall_coyote_time


## Kick off the wall: away from it and up, keeping the speed along it.
func _wall_jump() -> void:
	var t: MovementTuning = tuning
	var along: float = maxf(Vector3(velocity.x, 0.0, velocity.z).dot(_wall_dir), 0.0)
	if _wall_body != null:
		_wall_last = _wall_body
	_wall_body = null
	_wall_coyote = 0.0
	_buffer = 0.0
	_coyote = 0.0
	velocity = _wall_dir * along + _wall_normal * t.wall_jump_push + Vector3(0, t.wall_jump_velocity, 0)
	_jumping = true
	_no_snap = 0.12
	_begin_flight_stats()
	wall_jumped.emit()
	jumped.emit()


## Catch a ledge in front of us (hands reach mantle_reach above the feet) and climb it.
func _try_mantle(wish: Vector3, hv: Vector3) -> bool:
	var t: MovementTuning = tuning
	var dir: Vector3 = wish if wish.length() > 0.3 else hv
	if dir.length() < 0.3 or velocity.y < -14.0:
		return false
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var feet: Vector3 = global_position
	var hit: Dictionary = {}
	for h: float in [1.6, 1.0, 0.4]:
		hit = _probe(feet + Vector3(0, h, 0), feet + Vector3(0, h, 0) + dir * (0.38 + 0.4), "is_ledge")
		if not hit.is_empty():
			break
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	n = Vector3(n.x, 0.0, n.z).normalized()
	if dir.dot(-n) < 0.5:
		return false
	# find the top just past the face, from hand-reach height down
	var over: Vector3 = (hit["position"] as Vector3) - n * 0.3
	var q := PhysicsRayQueryParameters3D.create(Vector3(over.x, feet.y + t.mantle_reach + 0.05, over.z), Vector3(over.x, feet.y + t.mantle_min, over.z), collision_mask)
	q.exclude = [get_rid()]
	var top: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if top.is_empty() or (top["normal"] as Vector3).y < 0.8:
		return false
	var top_y: float = (top["position"] as Vector3).y
	# room to stand up there
	var sq := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.3
	sq.shape = cap
	var stand: Vector3 = Vector3(over.x, top_y, over.z) - n * 0.25
	sq.transform = Transform3D(Basis.IDENTITY, stand + Vector3(0, 0.72, 0))
	sq.collision_mask = collision_mask
	sq.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(sq, 1).is_empty():
		return false
	_mantle_t = 0.0
	_mantle_from = feet
	_mantle_to = stand + Vector3(0, 0.02, 0)
	_mantle_dir = -n
	velocity = Vector3.ZERO
	_jumping = false
	_buffer = 0.0
	_coyote = 0.0
	facing_dir = -n
	mantled.emit()
	return true


## Up the face first (hands on the lip), then over onto the top.
func _mantle_step(dt: float) -> void:
	_mantle_t += dt
	var k: float = clampf(_mantle_t / tuning.mantle_time, 0.0, 1.0)
	var up: float = clampf(k / 0.6, 0.0, 1.0)
	var over: float = clampf((k - 0.45) / 0.55, 0.0, 1.0)
	up = 1.0 - (1.0 - up) * (1.0 - up)
	over = over * over * (3.0 - 2.0 * over)
	var p: Vector3 = _mantle_from
	p.y = lerpf(_mantle_from.y, _mantle_to.y + 0.05, up)
	var flat_to := Vector3(_mantle_to.x, 0.0, _mantle_to.z)
	var flat_from := Vector3(_mantle_from.x, 0.0, _mantle_from.z)
	var f: Vector3 = flat_from.lerp(flat_to, over)
	p.x = f.x
	p.z = f.z
	global_position = p
	velocity = Vector3.ZERO
	grounded = false
	air_time = 0.0
	if k >= 1.0:
		_mantle_t = -1.0
		global_position = _mantle_to
		velocity = _mantle_dir * tuning.mantle_exit_speed + Vector3(0, -1.0, 0)
		last_ground_y = _mantle_to.y
		_wall_last = null


func is_wall_running() -> bool:
	return _wall_body != null


func is_mantling() -> bool:
	return _mantle_t >= 0.0


## Which side the wall is on, in the player's facing frame: -1 left, +1 right, 0 none.
func wall_side() -> float:
	if _wall_body == null:
		return 0.0
	var right: Vector3 = facing_dir.cross(Vector3.UP)
	return -signf(_wall_normal.dot(right))


func _cancel_moves() -> void:
	_wall_body = null
	_wall_last = null
	_wall_coyote = 0.0
	_mantle_t = -1.0


func _inherit_platform_velocity() -> void:
	var pv: Vector3 = platform_velocity
	pv.y = clampf(pv.y, 0.0, tuning.max_inherited_up_speed)
	velocity += pv
	platform_velocity = Vector3.ZERO


func _on_landed(pre_velocity: Vector3) -> void:
	var impact: float = maxf(-pre_velocity.y, 0.0)
	_jumping = false
	last_jump_height = _apex_y - _takeoff_pos.y
	last_jump_distance = Vector2(global_position.x - _takeoff_pos.x, global_position.z - _takeoff_pos.z).length()
	if floor_body != null and floor_body.has_method("apply_rider_impact"):
		var impulse: float = minf(impact * tuning.mass, tuning.max_impact_impulse)
		floor_body.call("apply_rider_impact", global_position, impulse)
	landed.emit(impact)


func _begin_flight_stats() -> void:
	_takeoff_pos = global_position
	_apex_y = global_position.y


## External velocity change (wind, knockback). Cancels variable-jump gravity.
func add_impulse(dv: Vector3) -> void:
	velocity += dv
	if dv.y > 0.0:
		_jumping = false
		_no_snap = 0.12


## A hazard throws the player: velocity is replaced outright. Like a pad launch,
## coyote time and a buffered press are dropped so a jump pressed on contact
## cannot overwrite the throw - same contact, same result.
## `grounded` is left alone so the floor's velocity is still inherited on takeoff.
func knockback(v: Vector3) -> void:
	_cancel_moves()
	velocity = v
	_jumping = false
	_coyote = 0.0
	_buffer = 0.0
	_no_snap = maxf(_no_snap, 0.12)
	_begin_flight_stats()
	knocked.emit(v)


func teleport(xform: Transform3D) -> void:
	# Position only: the body stays unrotated (facing is visual, from facing_dir).
	global_transform = Transform3D(Basis.IDENTITY, xform.origin)
	_cancel_moves()
	velocity = Vector3.ZERO
	platform_velocity = Vector3.ZERO
	floor_body = null
	_jumping = false
	_buffer = 0.0
	_coyote = 0.0
	_no_snap = 0.0
	_jump_press_queued = false
	grounded = false
	air_time = 0.0
	last_ground_y = xform.origin.y
	facing_dir = -xform.basis.z
	_pad_cooldown.clear()
	_begin_flight_stats()
	last_jump_height = 0.0
	last_jump_distance = 0.0
	# The engine still remembers the old floor: for one move, don't let it carry
	# us (a spinner would add omega x teleport distance). Guarded because two
	# teleports can happen before a physics tick (race setup).
	if not _teleported:
		_platform_layers_saved = platform_floor_layers
	platform_floor_layers = 0
	_teleported = true
	reset_physics_interpolation()
	teleported.emit()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# ---- presentation glue (cosmetic only) ------------------------------------

@onready var visual: PlayerVisual = $Visual as PlayerVisual
var _shadow: Decal


func _enter_tree() -> void:
	if _shadow == null:
		_shadow = BlobShadow.make()
		add_child(_shadow)


func _process(dt: float) -> void:
	if visual != null:
		visual.wall_roll = wall_side()
		visual.animate(dt, velocity, grounded or is_wall_running(), facing_dir)
	if _shadow != null and is_inside_tree():
		BlobShadow.fit(_shadow, get_world_3d().direct_space_state, get_global_transform_interpolated().origin, collision_mask)


func connect_feedback() -> void:
	jumped.connect(func() -> void:
		visual.on_jump()
		Sfx.play("jump", 0.06))
	landed.connect(func(impact: float) -> void:
		visual.on_land(impact)
		Sfx.play("land", 0.08, clampf(impact / 20.0, 0.25, 1.0)))
	bounced.connect(func(strength: float) -> void:
		visual.on_bounce(strength)
		Sfx.play("bounce", 0.04, 1.0, clampf(1.25 - strength / 60.0, 0.75, 1.2)))
	# the hazard plays its own positional hit sound
	knocked.connect(func(v: Vector3) -> void: visual.on_bounce(v.length()))
	wall_run_started.connect(func(_n: Vector3) -> void: Sfx.play("step", 0.08, 0.45, 1.35))
	mantled.connect(func() -> void:
		visual.on_mantle()
		Sfx.play("step", 0.05, 0.5, 0.8))
	teleported.connect(func() -> void:
		visual.on_respawn()
		visual.snap_facing(facing_dir))
	visual.footstep.connect(_on_footstep)


## Quiet, pitch-varied tick per foot plant - only while actually walking: coasting on
## ice, riding a conveyor or sliding down a tilt board with the stick released is silent.
func _on_footstep(speed: float) -> void:
	if move_input < 0.2:
		return
	var fb: Object = floor_body if (floor_body != null and is_instance_valid(floor_body)) else null
	var slick: bool = fb != null and fb.has_method("grip") and float(fb.call("grip")) < 1.0
	Sfx.play("step", 0.1, clampf(speed / 14.0, 0.15, 0.35), 1.3 if slick else 1.0)
