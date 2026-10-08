class_name ToyboxFx
extends RefCounted
## Toybox Tumble's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is DUST IN SUNLIGHT: slow golden motes drifting through
## the slanting window beams, with paper confetti and glitter for the celebrations. Ambient ones are
## world-space emitters over an area; one-shots are built idle and restarted on their event. Visual only.

static func _confetti() -> PackedColorArray:
	return PackedColorArray([Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.3, 0.6, 1.0), Color(0.35, 0.85, 0.45), Color(1.0, 0.5, 0.8), Color(1.0, 0.6, 0.2)])


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Golden dust motes drifting through a box (world space).
static func dust(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 8.0, "preprocess": 8.0, "shape": "box", "extents": ext,
		"dir": Vector3(0.3, -0.2, 0.1), "spread": 180.0, "speed": Vector2(0.05, 0.3), "tex": Fx.Tex.DOT, "size": 0.14,
		"color": Color(1.6, 1.35, 0.8, 0.8), "turbulence": 0.5, "turbulence_scale": 5.0, "curve": "pop",
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## Paper confetti fluttering down through a box (world space).
static func flutter(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 9.0, "preprocess": 9.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 25.0, "speed": Vector2(0.4, 1.0), "gravity": Vector3(0.05, -0.15, 0.0),
		"facing": "mesh", "mesh": Fx.chunk_mesh(0.16), "scale": Vector2(0.7, 1.3), "pick": _confetti(),
		"angle": Vector2(0, 360), "spin": Vector2(-120, 120), "turbulence": 0.6, "turbulence_scale": 5.0,
		"curve": "pop", "aabb": _aabb(ext + Vector3(0, 6, 0), 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Checkpoint burst: confetti fountain, stars and a flat ring. [0] confetti, [1] stars, [2] ring.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var conf: GPUParticles3D = Fx.burst({"amount": 46, "lifetime": 1.8, "facing": "mesh", "mesh": Fx.chunk_mesh(0.18),
		"dir": Vector3.UP, "spread": 55.0, "speed": Vector2(4.0, 10.0), "gravity": Vector3(0, -7.0, 0),
		"damping": Vector2(0.4, 1.0), "scale": Vector2(0.7, 1.3), "angle": Vector2(0, 360), "spin": Vector2(-300, 300),
		"pick": _confetti(), "curve": "shrink", "aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 30, "lifetime": 1.2, "tex": Fx.Tex.STAR, "size": 0.34, "dir": Vector3.UP,
		"spread": 70.0, "speed": Vector2(2.0, 6.0), "gravity": Vector3(0, -1.0, 0), "color": Fx.hot(col, 2.4), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(4.5, {"lifetime": 0.7, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(6, 2, 6))})
	return [conf, stars, ring]


## A rising puff of sparkles round a point (world space): the toys come alive.
static func glitter(parent: Node, center: Vector3, radius: float, amount: int, col: Color) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.0, "preprocess": 3.0, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(0.2, 0.6), "tex": Fx.Tex.STAR, "size": 0.2,
		"color": Fx.hot(col, 1.8), "turbulence": 0.6, "curve": "pop", "aabb": _aabb(Vector3(radius, radius * 2.0, radius), 4.0)})
	p.position = center
	parent.add_child(p)
	return p
