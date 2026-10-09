class_name DinoFx
extends RefCounted
## Dino Valley's particle kit on top of Fx (every amount goes through Fx.count / Settings.particle_scale
## inside Fx.emitter): pollen and gnats in the sunbeams, dragonflies over the water, falling leaves,
## drifting grey ash from the volcano, mist off the river, steaming fumaroles, the checkpoint burst and
## the finale. Ambient ones are world-space emitters over an area. Visual only.

const GOLD := Color(1.0, 0.74, 0.28)
const ORANGE := Color(1.0, 0.5, 0.12)
const TEAL := Color(0.25, 0.82, 0.72)
const LEAVES := [Color(0.3, 0.55, 0.16), Color(0.5, 0.62, 0.2), Color(0.62, 0.5, 0.16), Color(0.24, 0.45, 0.14)]


static func _n(amount: int) -> int:
	return roundi(float(amount) * Fx.LEVEL_BOOST)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


static func _add(parent: Node, p: GPUParticles3D, pos: Vector3) -> GPUParticles3D:
	p.position = pos
	parent.add_child(p)
	return p


static func _leaf_pick() -> PackedColorArray:
	var c := PackedColorArray()
	for l: Color in LEAVES:
		c.append(l)
	return c


## Pollen and gnats hanging in the sun over a box.
static func pollen(parent: Node, center: Vector3, ext: Vector3, amount: int = 40) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 6.0, "preprocess": 6.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 180.0, "speed": Vector2(0.05, 0.3), "gravity": Vector3(0.1, 0.03, 0.0),
		"turbulence": 0.7, "tex": Fx.Tex.DOT, "size": 0.1, "scale": Vector2(0.5, 1.3), "color": Color(2.2, 1.9, 1.0),
		"curve": "pop", "aabb": _aabb(ext)}), center)


## Dragonflies and butterflies darting over a box.
static func insects(parent: Node, center: Vector3, ext: Vector3, amount: int = 10) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 4.0, "preprocess": 4.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0.2, 0), "spread": 180.0, "flatness": 0.4, "speed": Vector2(1.0, 2.6), "turbulence": 2.2,
		"turbulence_scale": 1.6, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.26, "scale": Vector2(0.7, 1.2),
		"angle": Vector2(0, 360), "spin": Vector2(-900, 900),
		"pick": PackedColorArray([Color(0.2, 0.7, 0.9), Color(0.95, 0.5, 0.15), Color(0.9, 0.85, 0.25), Color(0.4, 0.8, 0.4)]),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext)}), center)


## Leaves and seed fluff drifting down through a box.
static func leaves(parent: Node, center: Vector3, ext: Vector3, amount: int = 18) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 7.0, "preprocess": 7.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 30.0, "speed": Vector2(0.4, 1.0), "gravity": Vector3(0.3, -0.6, 0.1),
		"turbulence": 1.4, "turbulence_scale": 2.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.26,
		"scale": Vector2(0.7, 1.3), "angle": Vector2(0, 360), "spin": Vector2(-200, 200), "pick": _leaf_pick(),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext + Vector3(0, 12, 0), 10.0)}), center)


## Fine grey ash snowing down from the volcano's cloud (sparse, slow).
static func ash(parent: Node, center: Vector3, ext: Vector3, amount: int = 30) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 8.0, "preprocess": 8.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 25.0, "speed": Vector2(0.3, 0.8), "gravity": Vector3(0.5, -0.25, 0.1),
		"turbulence": 0.9, "tex": Fx.Tex.DOT, "additive": false, "size": 0.12, "scale": Vector2(0.5, 1.2),
		"color": Color(0.6, 0.58, 0.56, 0.7), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": _aabb(ext + Vector3(0, 12, 0), 8.0)}), center)


## Low mist drifting over water or the valley floor.
static func mist(parent: Node, center: Vector3, ext: Vector3, amount: int = 10) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 10.0, "preprocess": 10.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0.04, 0.3), "spread": 20.0, "speed": Vector2(0.3, 0.9), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 9.0, "scale": Vector2(0.7, 1.4), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-8, 8),
		"color": Color(0.92, 0.95, 0.88, 0.28), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": _aabb(ext, 20.0)}), center)


## A steaming fumarole: a thread of vapour rising from a crack in the ground.
static func fumarole(parent: Node, pos: Vector3, rise: float = 6.0) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(10), "lifetime": 3.5, "preprocess": 3.5, "shape": "sphere", "radius": 0.3,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(rise * 0.4, rise * 0.7), "damping": Vector2(0.2, 0.5),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.3, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.96, 0.96, 0.92, 0.3), "fade": PackedFloat32Array([0.0, 0.8, 0.0]),
		"aabb": AABB(Vector3(-6, -1, -6), Vector3(12, rise * 3.0, 12))}), pos)


## A shower of golden dust rising from a spot (the egg nest, the nest finish).
static func glints(parent: Node, pos: Vector3, amount: int = 30) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 2.6, "preprocess": 2.6, "shape": "sphere", "radius": 1.6,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.5, 1.6), "tex": Fx.Tex.STAR, "size": 0.2,
		"color": Fx.hot(GOLD, 2.0), "turbulence": 0.5, "curve": "pop", "aabb": AABB(Vector3(-4, -1, -4), Vector3(8, 9, 8))}), pos)


## The checkpoint burst: a ring of orange and turquoise sparks (restart() it on the event).
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	var vis := AABB(Vector3(-6, -1, -6), Vector3(12, 12, 12))
	out.append(Fx.sparks({"amount": 70, "lifetime": 1.1, "one_shot": true, "emitting": false, "explosiveness": 0.9,
		"shape": "ring", "ring_radius": 1.6, "ring_inner": 1.2, "dir": Vector3.UP, "spread": 40.0, "speed": Vector2(5.0, 10.0),
		"gravity": Vector3(0, -10, 0), "color": Fx.hot(col, 2.2), "size": Vector2(0.07, 0.5), "aabb": vis}))
	out.append(Fx.burst({"amount": 26, "lifetime": 1.2, "one_shot": true, "emitting": false, "shape": "sphere", "radius": 0.5,
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(1.0, 4.0), "gravity": Vector3(0, -2, 0), "tex": Fx.Tex.PETAL,
		"additive": false, "size": 0.3, "angle": Vector2(0, 360), "spin": Vector2(-300, 300), "pick": _leaf_pick(),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis}))
	return out
