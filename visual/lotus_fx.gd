class_name LotusFx
extends RefCounted
## Lotus Drift's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is LANTERNS and FIREFLIES: warm paper lanterns lifting
## slowly into the dusk, fireflies pulsing over the water, lotus petals sliding down the wind, and a
## low drift of mist over the ponds. Ambient ones are world-space emitters over an area; one-shots
## are built idle and restarted on their event. Visual only.

const GOLD := Color(1.0, 0.68, 0.28)
const PINK := Color(1.0, 0.5, 0.7)
const JADE := Color(0.4, 0.92, 0.75)
const CREAM := Color(1.0, 0.94, 0.82)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Fireflies pulsing over a box (world space): slow wander, soft pulse via the pop curve.
static func fireflies(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 4.5, "preprocess": 4.5, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 180.0, "speed": Vector2(0.05, 0.35), "tex": Fx.Tex.DOT, "size": 0.13,
		"pick": PackedColorArray([Fx.hot(Color(0.85, 1.0, 0.4), 2.6), Fx.hot(GOLD, 2.4), Fx.hot(Color(0.7, 1.0, 0.7), 2.2)]),
		"turbulence": 1.1, "turbulence_scale": 3.0, "curve": "pop", "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## Paper sky-lanterns lifting off, drifting up and across (world space).
static func sky_lanterns(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 16.0, "preprocess": 16.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.9, 1.9), "gravity": Vector3(0.18, 0.0, 0.1), "tex": Fx.Tex.DOT,
		"size": 0.55, "pick": PackedColorArray([Fx.hot(GOLD, 2.2), Fx.hot(Color(1.0, 0.5, 0.25), 2.0), Fx.hot(CREAM, 1.8)]),
		"turbulence": 0.5, "turbulence_scale": 2.0, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": _aabb(ext + Vector3(0, 30, 0), 10.0)})
	p.position = center
	parent.add_child(p)
	return p


## Low mist drifting over the water (world space).
static func mist(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 12.0, "preprocess": 12.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0.03, 0.3), "spread": 20.0, "speed": Vector2(0.3, 0.9), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 12.0, "color": Color(0.85, 0.72, 0.8, 0.18), "angle": Vector2(0, 360), "spin": Vector2(-4, 4),
		"curve": "puff", "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext, 14.0)})
	p.position = center
	parent.add_child(p)
	return p


## Petals sliding down the wind through a box (world space).
static func petals(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 8.0, "preprocess": 8.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, -0.35, 0.3), "spread": 30.0, "speed": Vector2(0.6, 1.6), "gravity": Vector3(0.15, -0.3, 0.05),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.2,
		"pick": PackedColorArray([Color(1.0, 0.72, 0.82), Color(1.0, 0.86, 0.9), Color(0.96, 0.6, 0.76)]),
		"turbulence": 1.2, "turbulence_scale": 3.0, "angle": Vector2(0, 360), "spin": Vector2(-180, 180),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext, 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Spray off a waterfall lip / cascade foot (world space, a box).
static func spray(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 1.8, "preprocess": 1.8, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 40.0, "speed": Vector2(0.6, 2.2), "gravity": Vector3(0, -1.8, 0), "tex": Fx.Tex.DOT,
		"size": 0.14, "color": Color(0.9, 1.0, 1.0, 0.7), "turbulence": 0.6, "curve": "shrink",
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext + Vector3(2, 4, 2), 3.0)})
	p.position = center
	parent.add_child(p)
	return p


## Checkpoint bloom: lotus petals fanning out and falling, golden stars, and a ring of light across
## the isle. [0] petals, [1] stars, [2] ring.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var petals_p: GPUParticles3D = Fx.burst({"amount": 46, "lifetime": 2.6, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.26,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 6.0), "gravity": Vector3(0, -2.2, 0), "damping": Vector2(0.8, 1.6),
		"pick": PackedColorArray([Color(1.0, 0.72, 0.82), Color(1.0, 0.9, 0.94), Color(1.0, 0.6, 0.78)]),
		"angle": Vector2(0, 360), "spin": Vector2(-240, 240), "curve": "flat", "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 44, "lifetime": 1.5, "tex": Fx.Tex.STAR, "size": 0.3,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 7.0), "gravity": Vector3(0, -1.0, 0),
		"pick": PackedColorArray([Fx.hot(col, 2.4), Fx.hot(CREAM, 2.0)]), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(4.5, {"lifetime": 0.8, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(6, 2, 6))})
	return [petals_p, stars, ring]


## Finish: a fountain of lanterns' light and petals over the great lotus.
static func finale(col: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 3.0, "tex": Fx.Tex.STAR, "size": 0.45, "dir": Vector3.UP,
		"spread": 180.0, "speed": Vector2(4.0, 12.0), "gravity": Vector3(0, -2.6, 0), "damping": Vector2(0.5, 1.5),
		"color": Fx.hot(col, 2.6), "curve": "shrink", "aabb": _aabb(Vector3(14, 14, 14))})


## Ripple rings spreading over water where something touched it (one-shot; restart it).
static func ripple() -> GPUParticles3D:
	return Fx.shockwave(1.8, {"lifetime": 1.2, "color": Color(0.8, 0.95, 1.0, 0.7), "aabb": _aabb(Vector3(3, 1, 3), 2.0)})
