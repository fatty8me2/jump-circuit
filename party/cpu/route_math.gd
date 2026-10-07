class_name RouteMath
extends RefCounted
## Pure helpers for reading a level's route annotations (the `r_*` steps). Shared by the
## test bot (tests/route_bot.gd drives a real Player with them) and the CPU racers
## (party/cpu/route_walker.gd walks a lightweight body along the same steps).


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Where `local` (a point in `n`'s frame) will be in `lead` seconds. Kinematic platforms are
## pure functions of Game.course_time, so they can be asked where they WILL be.
static func future(n: Node3D, local: Vector3, lead: float) -> Vector3:
	var now: float = Game.course_time
	if n is MovingPlatform:
		var m := n as MovingPlatform
		return m.global_position - m.offset_at(now) + m.offset_at(now + lead) + local
	if n is RotatingPlatform:
		var r := n as RotatingPlatform
		return r.global_position + Basis(Vector3.UP, r.angle_at(now + lead)) * local
	return n.global_transform * local


## Frame whose +X runs along the arm `local` points down (a rotating platform's arm).
static func arm_basis(local: Vector3) -> Basis:
	var d: Vector3 = flat(local)
	if d.length() < 0.1:
		return Basis.IDENTITY
	d = d.normalized()
	return Basis(d, Vector3.UP, d.cross(Vector3.UP))


## Seconds until a jump from height `y` with vertical speed `vy` comes back down through
## `y_target` (capped at 4 s), stepped like the real physics.
static func time_to_reach(t: MovementTuning, y: float, vy: float, y_target: float) -> float:
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


## A representative world point for a route step (where the racer is while it runs), or
## Vector3.INF when the step has none (a checkpoint mark, a pure wait on a moving node).
static func anchor(step: Dictionary) -> Vector3:
	for key: String in ["from", "jump_from", "entry", "to", "top", "point"]:
		if step.has(key) and typeof(step[key]) == TYPE_VECTOR3 and (step[key] as Vector3) != Vector3.ZERO:
			return step[key]
	return Vector3.INF
