class_name OlympusFx
extends RefCounted
## Sky Citadel's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is GOLDEN-HOUR AIR: warm dust motes lit by the low sun
## rising slowly past the marble, white feathers tumbling down out of the sky, and low banks of
## cloud wisps sliding by. Ambient ones are world-space emitters over an area; one-shots are
## built idle and restarted on their event. Visual only; HDR terms stay under ~2.6.

const GOLD := Color(1.0, 0.78, 0.28)
const CREAM := Color(1.0, 0.94, 0.8)
const SKY := Color(0.55, 0.82, 1.0)
const WHITE := Color(1.0, 0.99, 0.95)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Warm dust motes drifting up through a box (world space).
static func motes(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 6.0, "preprocess": 6.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.2, 0.6), "gravity": Vector3(0.12, 0.05, 0.0), "tex": Fx.Tex.DOT,
		"size": 0.16, "pick": PackedColorArray([Fx.hot(GOLD, 1.9), Fx.hot(CREAM, 1.8), Color(1.9, 1.6, 1.1)]),
		"turbulence": 0.7, "turbulence_scale": 4.0, "curve": "pop", "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## White feathers tumbling slowly down through a box (world space).
static func feathers(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 10.0, "preprocess": 10.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 30.0, "speed": Vector2(0.2, 0.7), "gravity": Vector3(0.18, -0.25, 0.05),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.32, "color": Color(1.0, 0.99, 0.95, 0.95),
		"angle": Vector2(0, 360), "spin": Vector2(-90, 90), "turbulence": 0.9, "turbulence_scale": 5.0,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext + Vector3(0, 8, 0), 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Slow banks of cloud wisps sliding across a box (world space), tinted gold by the sun.
static func wisps(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 12.0, "preprocess": 12.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0, 0.2), "spread": 15.0, "speed": Vector2(0.4, 1.2), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 7.0, "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-4, 4),
		"pick": PackedColorArray([Color(1.0, 0.93, 0.8, 0.5), Color(1.0, 0.86, 0.7, 0.42), Color(0.9, 0.86, 0.95, 0.4)]),
		"fade": PackedFloat32Array([0.0, 0.7, 0.7, 0.0]), "aabb": _aabb(ext, 14.0)})
	p.position = center
	parent.add_child(p)
	return p


## A ring of sparkling dust turning slowly round a point (world space) - for gates and the sun disc.
static func halo(parent: Node, center: Vector3, radius: float, amount: int, col: Color, axis: Vector3 = Vector3.UP) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.0, "preprocess": 3.0, "shape": "ring",
		"ring_radius": radius, "ring_inner": radius * 0.85, "ring_axis": axis, "speed": Vector2(0.0, 0.1),
		"tex": Fx.Tex.STAR, "size": 0.2, "color": Fx.hot(col, 1.9), "curve": "pop",
		"aabb": _aabb(Vector3(radius, radius, radius), 4.0)})
	p.position = center
	parent.add_child(p)
	return p


## A waterfall of cloud: mist pouring off an island's edge and dissolving (world space).
static func cloudfall(parent: Node, top: Vector3, width: float, drop: float, amount: int = 40) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.0, "preprocess": 3.0, "shape": "box",
		"extents": Vector3(width * 0.5, 0.1, 0.3), "dir": Vector3.DOWN, "spread": 6.0, "speed": Vector2(drop * 0.25, drop * 0.4),
		"gravity": Vector3(0, -3.0, 0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 2.0, "curve": "puff",
		"angle": Vector2(0, 360), "color": Color(1.0, 0.97, 0.92, 0.55), "fade": PackedFloat32Array([0.0, 0.8, 0.0]),
		"aabb": _aabb(Vector3(width, drop, 4.0), 6.0)})
	p.position = top
	parent.add_child(p)
	return p


## Checkpoint bloom: gold stars and white feathers bursting up and out, and a flat ring of light
## across the slab. [0] feathers, [1] stars, [2] ring.
static func cp_burst(col: Color = GOLD) -> Array[GPUParticles3D]:
	var feathers_p: GPUParticles3D = Fx.burst({"amount": 36, "lifetime": 2.4, "tex": Fx.Tex.PETAL, "additive": false,
		"size": 0.34, "dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.5, 6.0), "gravity": Vector3(0, -2.0, 0),
		"damping": Vector2(1.0, 2.0), "angle": Vector2(0, 360), "spin": Vector2(-300, 300),
		"color": Color(1.0, 0.99, 0.94, 0.95), "curve": "flat", "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 50, "lifetime": 1.4, "tex": Fx.Tex.STAR, "size": 0.3,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 7.0), "gravity": Vector3(0, -1.0, 0),
		"pick": PackedColorArray([Fx.hot(col, 2.4), Fx.hot(CREAM, 2.0)]), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(4.5, {"lifetime": 0.7, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(6, 2, 6))})
	return [feathers_p, stars, ring]


## Finish: a fountain of gold and light out of the sun disc.
static func finale(col: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.6, "tex": Fx.Tex.STAR, "size": 0.45, "dir": Vector3.UP,
		"spread": 180.0, "speed": Vector2(4.0, 11.0), "gravity": Vector3(0, -3.0, 0), "damping": Vector2(0.5, 1.5),
		"color": Fx.hot(col, 2.5), "curve": "shrink", "aabb": _aabb(Vector3(14, 14, 14))})
