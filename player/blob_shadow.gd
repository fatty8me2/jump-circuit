class_name BlobShadow
extends RefCounted
## Soft round drop shadow projected straight down: the landing-spot readout.
## Decals are not occluded, so fit() trims the box to end just under the first
## solid surface below - otherwise every platform underneath shows a blob too.

const TOP: float = 0.6       # box top above the feet
const REACH: float = 29.4    # how far down the shadow can land
const UNDER: float = 0.4     # box bottom below the hit (covers tilted boards)

static var _tex: GradientTexture2D


static func make() -> Decal:
	if _tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.75), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0)])
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(0.5, 0.0)
		_tex.width = 128
		_tex.height = 128
	var d := Decal.new()
	d.texture_albedo = _tex
	d.size = Vector3(1.25, TOP + REACH + UNDER, 1.25)
	d.position = Vector3(0, TOP - d.size.y * 0.5, 0)
	d.cull_mask = 1
	d.normal_fade = 0.35
	d.upper_fade = 0.0001
	# after fit() the landing surface sits in the lower half: no fade there
	d.lower_fade = 0.0001
	# size is not interpolated, so the local offset must not be either (the
	# decal still follows its interpolated parent)
	d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return d


## Ends the shadow box just under the first solid surface below `feet`, so the
## blob marks only where you would land. Rays skip areas (kill water, wind).
static func fit(d: Decal, space: PhysicsDirectSpaceState3D, feet: Vector3, mask: int = 1) -> void:
	var depth: float = REACH
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(feet + Vector3(0, 0.3, 0), feet - Vector3(0, REACH, 0), mask)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			depth = maxf(feet.y - (hit["position"] as Vector3).y, 0.0)
	d.size.y = TOP + depth + UNDER
	d.position.y = TOP - d.size.y * 0.5
