class_name Ballistics
extends RefCounted
## Predicts airborne arcs using the same rules as Player (asymmetric gravity,
## over-speed drag, forward held). Used for pad arc previews and level validation.

static func arc(t: MovementTuning, start: Vector3, v0: Vector3, duration: float, step: float = 1.0 / 60.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p: Vector3 = start
	var v: Vector3 = v0
	var time: float = 0.0
	pts.append(p)
	while time < duration:
		var g: float = t.gravity_rise if v.y > 0.0 else t.gravity_fall
		v.y = maxf(v.y - g * step, -t.max_fall_speed)
		var h := Vector3(v.x, 0, v.z)
		var s: float = h.length()
		if s > t.max_speed:
			h = h.normalized() * move_toward(s, t.max_speed, t.air_overspeed_drag * step)
			v.x = h.x
			v.z = h.z
		p += v * step
		time += step
		pts.append(p)
	return pts


## First point on the descending part of the arc at or below target_y.
static func landing_point(t: MovementTuning, start: Vector3, v0: Vector3, target_y: float) -> Vector3:
	var pts: PackedVector3Array = arc(t, start, v0, 6.0)
	for i: int in range(1, pts.size()):
		if pts[i].y <= target_y and pts[i].y < pts[i - 1].y:
			return pts[i]
	return pts[pts.size() - 1]
