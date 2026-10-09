class_name FungalFx
extends RefCounted
## Mushroom Hollow's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is warm daylight in a meadow: drifting POLLEN and
## dandelion SEEDS catching the sun, a slow fall of petals and leaves, spore puffs from the
## toadstools. Ambient ones are world-space emitters over an area; one-shots are built idle and
## restarted on their event. Visual only.

const GOLD := Color(1.0, 0.85, 0.4)
const CREAM := Color(1.0, 0.96, 0.82)
const RED := Color(0.92, 0.24, 0.2)
const PINK := Color(1.0, 0.62, 0.72)
const GREEN := Color(0.5, 0.78, 0.3)

static var PETALS: PackedColorArray = PackedColorArray([Color(1.0, 0.72, 0.8), Color(1.0, 0.92, 0.5), Color(0.98, 0.98, 0.95), Color(0.74, 0.88, 0.4)])


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Pollen and tiny seeds glinting gold as they drift across a box (world space).
static func pollen(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 7.0, "preprocess": 7.0, "shape": "box", "extents": ext,
		"dir": Vector3(0.4, 0.2, 0.1), "spread": 80.0, "speed": Vector2(0.15, 0.55), "gravity": Vector3(0.02, 0.03, 0.0),
		"tex": Fx.Tex.DOT, "size": 0.14, "pick": PackedColorArray([Fx.hot(GOLD, 1.6), Fx.hot(CREAM, 1.5), Fx.hot(GOLD, 1.2)]),
		"turbulence": 0.8, "turbulence_scale": 5.0, "curve": "pop", "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## Dandelion fluff rising and wandering on the breeze (white four-point glints).
static func seeds(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 9.0, "preprocess": 9.0, "shape": "box", "extents": ext,
		"dir": Vector3(0.3, 1.0, 0.1), "spread": 35.0, "speed": Vector2(0.3, 0.8), "tex": Fx.Tex.STAR, "size": 0.24,
		"color": Color(1.6, 1.58, 1.4), "turbulence": 0.7, "turbulence_scale": 4.0, "curve": "pop",
		"aabb": _aabb(ext + Vector3(0, 8, 0), 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Petals and small leaves tumbling slowly down through a box (world space).
static func petals(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 8.0, "preprocess": 8.0, "shape": "box", "extents": ext,
		"dir": Vector3(0.3, -1.0, 0.1), "spread": 25.0, "speed": Vector2(0.4, 1.0), "gravity": Vector3(0.1, -0.15, 0.0),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.2, "pick": PETALS, "angle": Vector2(0, 360),
		"spin": Vector2(-120, 120), "turbulence": 0.6, "turbulence_scale": 5.0, "curve": "flat",
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext + Vector3(0, 6, 0), 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Spore puffs rising off a patch of toadstools (a slow smoky drift, world space).
static func spores(parent: Node, center: Vector3, radius: float, amount: int, col: Color = CREAM) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 4.0, "preprocess": 4.0, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.3, 0.9), "tex": Fx.Tex.DOT, "size": 0.18,
		"color": Fx.hot(col, 1.5), "turbulence": 0.6, "turbulence_scale": 4.0, "curve": "pop",
		"aabb": _aabb(Vector3(radius, radius, radius) + Vector3(0, 6, 0), 5.0)})
	p.position = center
	parent.add_child(p)
	return p


## A ring of fireflies-by-day: slow gold glints circling a point (set pieces, the finish).
static func halo(parent: Node, center: Vector3, radius: float, amount: int, col: Color) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.0, "preprocess": 3.0, "shape": "ring",
		"ring_radius": radius, "ring_inner": radius * 0.85, "ring_axis": Vector3.UP, "speed": Vector2(0.0, 0.1),
		"tex": Fx.Tex.STAR, "size": 0.2, "color": Fx.hot(col, 1.8), "curve": "pop", "aabb": _aabb(Vector3(radius, 2, radius), 4.0)})
	p.position = center
	parent.add_child(p)
	return p


## Checkpoint bloom: petals and spores bursting up, stars in the stage colour, and a flat ring of
## light across the slab. [0] petals, [1] stars, [2] ring.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var petals_b: GPUParticles3D = Fx.burst({"amount": 34, "lifetime": 2.2, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.26,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.5, 6.0), "gravity": Vector3(0, -2.5, 0),
		"damping": Vector2(1.0, 2.0), "pick": PETALS, "angle": Vector2(0, 360), "spin": Vector2(-300, 300),
		"curve": "flat", "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 44, "lifetime": 1.3, "tex": Fx.Tex.STAR, "size": 0.3,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 7.0), "gravity": Vector3(0, -1.0, 0),
		"pick": PackedColorArray([Fx.hot(col, 2.3), Fx.hot(CREAM, 2.0)]), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(4.5, {"lifetime": 0.7, "color": Fx.hot(col, 1.5), "aabb": _aabb(Vector3(6, 2, 6))})
	return [petals_b, stars, ring]


## Finish: a fountain of petals, spores and stars off the top of the great toadstool.
static func finale(col: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.8, "tex": Fx.Tex.STAR, "size": 0.45, "dir": Vector3.UP,
		"spread": 180.0, "speed": Vector2(4.0, 11.0), "gravity": Vector3(0, -3.0, 0), "damping": Vector2(0.5, 1.5),
		"color": Fx.hot(col, 2.5), "curve": "shrink", "aabb": _aabb(Vector3(14, 14, 14))})


static func petal_fountain(amount: int = 80) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 3.4, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.34, "dir": Vector3.UP,
		"spread": 60.0, "speed": Vector2(5.0, 12.0), "gravity": Vector3(0, -4.0, 0), "damping": Vector2(0.3, 1.0),
		"pick": PETALS, "angle": Vector2(0, 360), "spin": Vector2(-260, 260), "curve": "flat",
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": _aabb(Vector3(16, 16, 16))})
