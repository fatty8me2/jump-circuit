class_name AbyssFx
extends RefCounted
## The Abyss particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is MARINE SNOW - pale flakes sinking for ever through
## the black - with bioluminescent plankton blinking cyan, green and violet in the dark, bubble
## trains from the vents and black smoke from the smokers. Ambient ones are world-space emitters
## over an area; one-shots are built idle and restarted on their event. Visual only.

const CYAN := Color(0.1, 1.0, 0.85)
const GREEN := Color(0.35, 1.0, 0.45)
const VIOLET := Color(0.7, 0.35, 1.0)
const PINK := Color(1.0, 0.35, 0.8)

static var GLOWS: PackedColorArray = PackedColorArray([Color(0.2, 2.4, 2.0), Color(0.7, 2.4, 0.9), Color(1.6, 0.8, 2.6), Color(2.4, 0.8, 1.9)])


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Marine snow sinking through a box (world space): pale, slow, tumbling.
static func snow(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 7.0, "shape": "box", "extents": ext,
		"dir": Vector3(0.1, -1, 0.05), "spread": 25.0, "speed": Vector2(0.15, 0.45), "turbulence": 0.5,
		"turbulence_scale": 3.0, "tex": Fx.Tex.DOT, "additive": false, "size": 0.07, "scale": Vector2(0.5, 1.3),
		"color": Color(0.8, 0.88, 0.9, 0.55), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 7.0,
		"aabb": _aabb(ext)})
	p.position = center
	parent.add_child(p)
	return p


## Bioluminescent plankton hanging in the water over an area, blinking.
static func plankton(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.5, "shape": "box", "extents": ext,
		"speed": Vector2(0.05, 0.25), "spread": 180.0, "turbulence": 0.8, "tex": Fx.Tex.DOT, "size": 0.12,
		"curve": "pop", "pick": GLOWS, "fade": PackedFloat32Array([0.0, 1.0, 0.2, 1.0, 0.0]), "preprocess": 3.5,
		"aabb": _aabb(ext)})
	p.position = center
	parent.add_child(p)
	return p


## A train of bubbles wobbling up from a point (vents, the wreck).
static func bubbles(parent: Node, at: Vector3, height: float = 10.0, amount: int = 18, radius: float = 0.3) -> GPUParticles3D:
	var life: float = height / 2.2
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": life, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 6.0, "speed": Vector2(1.6, 2.6), "turbulence": 1.2, "turbulence_scale": 2.0,
		"tex": Fx.Tex.BUBBLE, "size": 0.18, "scale": Vector2(0.4, 1.2), "color": Color(0.7, 1.1, 1.2, 0.75),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": life, "aabb": _aabb(Vector3(2, height, 2))})
	p.position = at
	parent.add_child(p)
	return p


## Black smoke billowing up out of a hydrothermal chimney, lit orange at its root (mix blend).
static func smoker(parent: Node, at: Vector3, height: float = 12.0, amount: int = 20) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 5.0, "shape": "sphere", "radius": 0.3,
		"dir": Vector3.UP, "spread": 8.0, "speed": Vector2(height * 0.2, height * 0.3), "damping": Vector2(0.3, 0.6),
		"turbulence": 0.7, "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.6, "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-20, 20),
		"colors": PackedColorArray([Color(0.6, 0.3, 0.12, 0.6), Color(0.06, 0.06, 0.07, 0.7), Color(0.03, 0.04, 0.05, 0.0)]),
		"preprocess": 5.0, "aabb": _aabb(Vector3(4, height + 2, 4))})
	p.position = at
	parent.add_child(p)
	return p


## A checkpoint banked: a bloom of bioluminescence - a burst of glowing plankton, a ring of light
## swelling on the rock and a puff of bubbles.
static func cp_burst(color: Color) -> Array[GPUParticles3D]:
	var bloom: GPUParticles3D = Fx.burst({"amount": 60, "lifetime": 1.6, "explosiveness": 0.9, "shape": "sphere", "radius": 0.5,
		"dir": Vector3.UP, "spread": 80.0, "speed": Vector2(2.0, 5.0), "damping": Vector2(2.0, 3.5), "turbulence": 0.6,
		"tex": Fx.Tex.DOT, "size": 0.16, "curve": "pop", "pick": PackedColorArray([Fx.hot(color, 2.4), Fx.hot(color.lerp(Color.WHITE, 0.4), 2.0)]),
		"aabb": _aabb(Vector3.ONE * 8.0)})
	var bub: GPUParticles3D = Fx.burst({"amount": 30, "lifetime": 1.4, "shape": "ring", "ring_radius": 1.2, "ring_inner": 0.4,
		"dir": Vector3.UP, "spread": 15.0, "speed": Vector2(1.5, 3.5), "damping": Vector2(0.5, 1.0), "turbulence": 1.0,
		"tex": Fx.Tex.BUBBLE, "size": 0.18, "curve": "flat", "color": Color(0.8, 1.2, 1.3, 0.8), "aabb": _aabb(Vector3.ONE * 8.0)})
	var ring: GPUParticles3D = Fx.shockwave(4.0, {"lifetime": 0.7, "color": Fx.hot(color, 1.8), "aabb": _aabb(Vector3.ONE * 6.0)})
	return [bloom, bub, ring]


## Glowing motes rising round a spot (portal exits, the finish).
static func rising(parent: Node, at: Vector3, radius: float, height: float, amount: int, color: Color) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.6, "shape": "ring", "ring_radius": radius,
		"ring_inner": radius * 0.4, "dir": Vector3.UP, "spread": 8.0, "speed": Vector2(height * 0.25, height * 0.4),
		"turbulence": 0.5, "tex": Fx.Tex.DOT, "size": 0.14, "curve": "pop", "color": Fx.hot(color, 2.0), "preprocess": 2.6,
		"aabb": _aabb(Vector3(radius, height, radius))})
	p.position = at
	parent.add_child(p)
	return p


## The finish: a great bloom of light out of the conning tower (one-shot).
static func finish_bloom(color: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.4, "explosiveness": 0.95, "shape": "sphere", "radius": 0.6,
		"spread": 180.0, "speed": Vector2(4.0, 9.0), "damping": Vector2(1.5, 2.5), "turbulence": 0.7,
		"tex": Fx.Tex.DOT, "size": 0.22, "curve": "pop", "pick": PackedColorArray([Fx.hot(color, 2.4), Fx.hot(Color(0.8, 1.0, 1.0), 2.0)]),
		"aabb": _aabb(Vector3.ONE * 18.0)})


## Drifting silt over the trench floor far below (big slow dark puffs, mix blend).
static func silt(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 12.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0.05, 0.3), "spread": 25.0, "speed": Vector2(0.2, 0.6), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 10.0, "scale": Vector2(0.6, 1.4), "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-6, 6), "color": Color(0.06, 0.12, 0.15, 0.35), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"preprocess": 12.0, "aabb": _aabb(ext, 16.0)})
	p.position = center
	parent.add_child(p)
	return p
