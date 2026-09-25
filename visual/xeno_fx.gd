class_name XenoFx
extends RefCounted
## Xeno Wilds particle kit, built on Fx.emitter: the layered ambient life hung round every stage
## (rising spores, blinking fireflies, drifting pollen glints), bursts for the checkpoints, portal
## arrivals and the finish, and the curtains of motes round the set pieces. Every emitter gets a
## visibility AABB sized to what it can reach.


## Spores drifting slowly UP through a box (ambient layer 1): soft lilac / teal dots.
static func spores(center: Vector3, extents: Vector3, amount: int = 60) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": 7.0, "shape": "box", "extents": extents,
		"dir": Vector3.UP, "spread": 30.0, "speed": Vector2(0.2, 0.6), "gravity": Vector3(0.05, 0.12, 0.02),
		"turbulence": 0.6, "turbulence_scale": 6.0, "tex": Fx.Tex.DOT, "size": 0.16, "scale": Vector2(0.5, 1.3), "curve": "pop",
		"pick": PackedColorArray([Color(1.6, 0.9, 2.2), Color(0.7, 2.0, 1.9), Color(2.0, 0.8, 1.6)]),
		"aabb": AABB(-extents - Vector3(2, 2, 2), extents * 2.0 + Vector3(4, 10, 4)), "preprocess": 7.0})
	p.position = center
	return p


## Fireflies: lime / cyan points wandering and blinking in a box (ambient layer 2).
static func fireflies(center: Vector3, extents: Vector3, amount: int = 30) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": 2.2, "shape": "box", "extents": extents,
		"speed": Vector2(0.3, 1.0), "spread": 180.0, "turbulence": 2.0, "turbulence_scale": 3.0,
		"tex": Fx.Tex.DOT, "size": 0.14, "curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 0.2, 1.0, 0.0]),
		"pick": PackedColorArray([Color(1.8, 2.6, 0.5), Color(0.6, 2.4, 2.6)]),
		"aabb": AABB(-extents - Vector3(3, 3, 3), extents * 2.0 + Vector3(6, 6, 6)), "preprocess": 2.2})
	p.position = center
	return p


## Big slow pollen glints drifting across the gaps (ambient layer 3).
static func glints(center: Vector3, extents: Vector3, amount: int = 20, color: Color = Color(1.0, 0.8, 1.0)) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": 6.0, "shape": "box", "extents": extents,
		"speed": Vector2(0.2, 0.5), "spread": 180.0, "gravity": Vector3(0.3, -0.05, 0.1), "tex": Fx.Tex.STAR, "size": 0.4,
		"curve": "pop", "color": Fx.hot(color, 1.6), "aabb": AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 8, 8)), "preprocess": 6.0})
	p.position = center
	return p


## A one-shot fountain of glowing spores and glints (checkpoints, portal arrivals, the finish).
static func burst(color: Color, amount: int = 40, speed: float = 6.0, size: float = 0.25) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 1.3, "dir": Vector3.UP, "spread": 55.0, "speed": Vector2(speed * 0.5, speed),
		"gravity": Vector3(0, -4.0, 0), "damping": Vector2(1.0, 2.0), "size": size, "color": Fx.hot(color, 2.2),
		"aabb": AABB(Vector3(-10, -4, -10), Vector3(20, 18, 20))})


## A lazy swirl of motes round a point (portal rings, the monolith, the finish).
static func swirl(center: Vector3, radius: float, color: Color, amount: int = 30) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": 3.0, "shape": "ring", "ring_radius": radius,
		"ring_inner": radius * 0.6, "ring_height": 0.4, "dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.4, 1.0),
		"tex": Fx.Tex.DOT, "size": 0.18, "curve": "pop", "turbulence": 0.8, "color": Fx.hot(color, 1.8),
		"aabb": AABB(Vector3(-radius - 3.0, -2.0, -radius - 3.0), Vector3(radius * 2.0 + 6.0, 8.0, radius * 2.0 + 6.0)), "preprocess": 3.0})
	p.position = center
	return p


## Fumes rising off an acid lake (big soft lime puffs).
static func fumes(center: Vector3, extents: Vector3, amount: int = 20) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 6.0, "shape": "box", "extents": extents, "dir": Vector3.UP,
		"spread": 15.0, "speed": Vector2(0.6, 1.4), "tex": Fx.Tex.SMOKE, "additive": false, "size": 7.0, "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-10, 10), "color": Color(0.65, 0.95, 0.3, 0.16),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": AABB(-extents - Vector3(10, 5, 10), extents * 2.0 + Vector3(20, 30, 20)), "preprocess": 6.0})
	p.position = center
	return p
