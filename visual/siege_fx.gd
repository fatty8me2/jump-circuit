class_name SiegeFx
extends RefCounted
## Castle Siege's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is EMBERS and ASH: glowing sparks lifting off the burning
## camps and drifting on the smoke-wind, with grey flakes of ash sifting down through the dusk and thick
## black columns of smoke rising from the fires. Ambient ones are world-space emitters over an area;
## one-shots are built idle and restarted on their event. Visual only.

const EMBER := Color(2.8, 1.0, 0.28)
const GOLD := Color(2.6, 1.9, 0.6)
const CRIMSON := Color(2.6, 0.3, 0.2)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Embers lifting off a region and drifting downwind (world space).
static func embers(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 5.0, "preprocess": 5.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.5, 1.6), "gravity": Vector3(0.5, 0.2, 0.15), "tex": Fx.Tex.DOT,
		"size": 0.13, "pick": PackedColorArray([EMBER, EMBER, GOLD, Color(2.2, 0.6, 0.2)]), "turbulence": 0.9,
		"turbulence_scale": 5.0, "curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 0.8, 0.0]), "aabb": _aabb(ext, 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Grey flakes of ash sifting down through a box (world space).
static func ash(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 8.0, "preprocess": 8.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 30.0, "speed": Vector2(0.2, 0.7), "gravity": Vector3(0.35, -0.12, 0.1),
		"tex": Fx.Tex.DOT, "additive": false, "size": 0.09, "color": Color(0.55, 0.5, 0.48, 0.8), "turbulence": 0.6,
		"turbulence_scale": 4.0, "fade": PackedFloat32Array([0.0, 0.7, 0.7, 0.0]), "aabb": _aabb(ext, 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## A column of thick black smoke rising and leaning downwind from a point (world space).
static func smoke_column(parent: Node, base: Vector3, height: float, width: float, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 7.0, "preprocess": 7.0, "shape": "sphere", "radius": width * 0.3,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(height / 7.0 * 0.8, height / 7.0 * 1.1), "gravity": Vector3(1.2, 0.0, 0.3),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": width, "scale": Vector2(0.7, 1.6), "curve": "puff",
		"color": Color(0.1, 0.075, 0.07, 0.85), "fade": PackedFloat32Array([0.0, 0.8, 0.6, 0.0]),
		"angle": Vector2(0, 360), "spin": Vector2(-20, 20), "turbulence": 0.5, "fixed_fps": 20,
		"aabb": AABB(Vector3(-height, -4, -height), Vector3(height * 2.0, height * 1.3, height * 2.0))})
	p.position = base
	parent.add_child(p)
	return p


## A fire: tongues of flame, a few sparks and a little smoke, on a point (world space).
static func fire(parent: Node, at: Vector3, size: float = 1.0) -> Array[GPUParticles3D]:
	var vis := AABB(Vector3(-4, -1, -4) * size, Vector3(8, 10, 8) * size)
	var flame: GPUParticles3D = Fx.emitter({"amount": int(14.0 * size), "lifetime": 0.8, "shape": "sphere", "radius": 0.18 * size,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(0.9, 1.7) * size, "tex": Fx.Tex.SMOKE, "size": 0.7 * size,
		"colors": PackedColorArray([Color(3.0, 2.0, 0.6, 0.9), Color(2.4, 0.8, 0.2, 0.8), Color(0.8, 0.15, 0.05, 0.0)]),
		"curve": "shrink", "turbulence": 0.4, "fixed_fps": 30, "aabb": vis})
	flame.position = at
	parent.add_child(flame)
	var sparks: GPUParticles3D = Fx.emitter({"amount": int(8.0 * size), "lifetime": 1.4, "shape": "sphere", "radius": 0.2 * size,
		"dir": Vector3.UP, "spread": 35.0, "speed": Vector2(1.5, 3.2) * size, "gravity": Vector3(0.6, 0.0, 0.0),
		"tex": Fx.Tex.DOT, "size": 0.09, "color": EMBER, "curve": "pop", "turbulence": 0.7, "aabb": vis})
	sparks.position = at + Vector3(0, 0.3 * size, 0)
	parent.add_child(sparks)
	var out: Array[GPUParticles3D] = [flame, sparks]
	return out


## A glowing spear-point of flame inside a brazier (cheap: used on every post-top brazier).
static func flicker(parent: Node, at: Vector3) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": 7, "lifetime": 0.6, "shape": "sphere", "radius": 0.1, "dir": Vector3.UP,
		"spread": 10.0, "speed": Vector2(0.6, 1.1), "tex": Fx.Tex.SMOKE, "size": 0.42,
		"colors": PackedColorArray([Color(3.0, 1.9, 0.5, 0.9), Color(2.2, 0.6, 0.15, 0.7), Color(0.6, 0.1, 0.05, 0.0)]),
		"curve": "shrink", "fixed_fps": 24, "aabb": AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))})
	p.position = at
	parent.add_child(p)
	return p


## Checkpoint bloom: embers bursting up, gold stars, and a flat ring across the slab. [0] embers, [1] stars, [2] ring.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var e: GPUParticles3D = Fx.burst({"amount": 46, "lifetime": 1.8, "tex": Fx.Tex.DOT, "size": 0.2, "dir": Vector3.UP,
		"spread": 70.0, "speed": Vector2(2.5, 7.0), "gravity": Vector3(0, -3.0, 0), "damping": Vector2(0.5, 1.5),
		"pick": PackedColorArray([EMBER, GOLD, EMBER]), "curve": "shrink", "aabb": _aabb(Vector3(6, 8, 6))})
	var st: GPUParticles3D = Fx.burst({"amount": 30, "lifetime": 1.3, "tex": Fx.Tex.STAR, "size": 0.32, "dir": Vector3.UP,
		"spread": 60.0, "speed": Vector2(2.0, 6.0), "gravity": Vector3(0, -1.5, 0), "color": Fx.hot(col, 1.6),
		"curve": "pop", "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(3.2, {"color": Fx.hot(col, 1.8), "lifetime": 0.7, "aabb": _aabb(Vector3(6, 4, 6))})
	return [e, st, ring]


## The finale: a fountain of gold and crimson sparks from the banner at the top of the keep.
static func finale(col: Color, amount: int) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.4, "tex": Fx.Tex.STAR, "size": 0.38, "dir": Vector3.UP, "spread": 55.0,
		"speed": Vector2(7.0, 15.0), "gravity": Vector3(0, -6.0, 0), "damping": Vector2(0.3, 0.9),
		"pick": PackedColorArray([Fx.hot(col, 1.6), GOLD, CRIMSON]), "curve": "pop", "aabb": _aabb(Vector3(20, 24, 20))})
