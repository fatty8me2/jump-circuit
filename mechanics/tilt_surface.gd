class_name TiltSurface
extends AnimatableBody3D
## Kinematic skin of a TiltPlatform. Forwards the rider's weight and landing
## impulses to the simulated body.

var owner_platform: Object


func is_slippery() -> bool:
	return true


func apply_rider_load(point: Vector3, force: float) -> void:
	owner_platform.call("rider_load", point, force)


func apply_rider_impact(point: Vector3, impulse: float) -> void:
	owner_platform.call("rider_impact", point, impulse)
