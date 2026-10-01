class_name NeonFx
extends RefCounted
## Neon City particle presets on top of Fx (so every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is RAIN: grey-white streaks lit warm and pink by the
## signs, and splashes and ripples on every rooftop. Ambient ones are world-space emitters over an
## area; one-shots are built idle and restarted on their event. Visual only.

static var SIGN: PackedColorArray = PackedColorArray([Color(2.6, 0.5, 1.6), Color(2.6, 1.4, 0.4), Color(0.4, 2.4, 2.2)])
const MAGENTA := Color(1.0, 0.2, 0.7)
const AMBER := Color(1.0, 0.62, 0.15)
const TEAL := Color(0.1, 0.95, 0.85)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## A curtain of rain falling through a box (world space): pale streaks with a hint of sign colour.
static func rain(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 0.9, "shape": "box", "extents": ext,
		"dir": Vector3(0.12, -1, 0.04), "spread": 2.0, "speed": Vector2(15.0, 19.0), "facing": "velocity",
		"tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.025, 0.85),
		"pick": PackedColorArray([Color(0.82, 0.8, 0.95, 0.55), Color(1.0, 0.75, 0.9, 0.5), Color(1.0, 0.85, 0.7, 0.5)]),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 0.9, "aabb": _aabb(ext + Vector3(0, 8, 0), 10.0)})
	p.position = center
	parent.add_child(p)
	return p


## Rain splashes on a flat surface (world space): little flat ripple rings and droplets popping up.
## `top` is the surface centre, `ext` its half size (x, z).
static func splashes(parent: Node, top: Vector3, ext: Vector2, amount: int) -> void:
	var e := Vector3(ext.x, 0.01, ext.y)
	var r: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 0.45, "shape": "box", "extents": e,
		"speed": Vector2.ZERO, "facing": "flat", "tex": Fx.Tex.RING, "additive": false, "size": 0.32,
		"curve": "grow", "color": Color(0.85, 0.85, 1.0, 0.55), "fade": PackedFloat32Array([0.8, 0.4, 0.0]),
		"preprocess": 0.5, "aabb": _aabb(e, 2.0)})
	r.position = top + Vector3(0, 0.03, 0)
	parent.add_child(r)
	var d: GPUParticles3D = Fx.emitter({"amount": maxi(amount / 2, 4), "lifetime": 0.3, "shape": "box", "extents": e,
		"dir": Vector3.UP, "spread": 35.0, "speed": Vector2(1.0, 2.2), "gravity": Vector3(0, -14.0, 0),
		"tex": Fx.Tex.DOT, "additive": false, "size": 0.05, "color": Color(0.9, 0.9, 1.0, 0.7),
		"preprocess": 0.3, "aabb": _aabb(e, 2.0)})
	d.position = top + Vector3(0, 0.05, 0)
	parent.add_child(d)


## A column of steam hissing up out of a rooftop vent (world space, mix blend).
static func steam(parent: Node, at: Vector3, height: float = 5.0, amount: int = 22, tint: Color = Color(0.85, 0.8, 0.9, 0.35)) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.6, "shape": "sphere", "radius": 0.25,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(height * 0.35, height * 0.55), "gravity": Vector3(0.3, 0.2, 0.1),
		"damping": Vector2(0.6, 1.2), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.4, "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-30, 30), "color": tint, "turbulence": 0.6,
		"fade": PackedFloat32Array([0.0, 0.9, 0.5, 0.0]), "preprocess": 2.6, "aabb": _aabb(Vector3(3, height + 2, 3))})
	p.position = at
	parent.add_child(p)
	return p


## Drips running off a ledge in a thin line (world space): `a` to `b` along the edge.
static func drips(parent: Node, a: Vector3, b: Vector3, amount: int = 10) -> GPUParticles3D:
	var mid: Vector3 = (a + b) * 0.5
	var half: Vector3 = (b - a) * 0.5
	var e := Vector3(absf(half.x) + 0.05, 0.02, absf(half.z) + 0.05)
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 1.2, "shape": "box", "extents": e,
		"dir": Vector3.DOWN, "spread": 2.0, "speed": Vector2(0.5, 1.0), "gravity": Vector3(0, -12.0, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.03, 0.22),
		"color": Color(0.85, 0.85, 1.0, 0.6), "preprocess": 1.2, "aabb": _aabb(e + Vector3(0, 8, 0))})
	p.position = mid
	parent.add_child(p)
	return p


## Sparks spitting from a faulty sign every so often (world space, continuous but sparse).
static func sign_sparks(parent: Node, at: Vector3, color: Color = Color(2.6, 1.6, 0.6)) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": 14, "lifetime": 0.8, "explosiveness": 0.85, "shape": "sphere", "radius": 0.1,
		"dir": Vector3(0, -0.3, 1), "spread": 70.0, "speed": Vector2(2.0, 4.5), "gravity": Vector3(0, -12.0, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.03, 0.22), "color": color,
		"aabb": _aabb(Vector3(3, 6, 3))})
	p.position = at
	parent.add_child(p)
	return p


## Neon motes hanging in the wet air over an area (sign-coloured, slowly drifting).
static func motes(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.0, "shape": "box", "extents": ext,
		"speed": Vector2(0.05, 0.3), "spread": 180.0, "gravity": Vector3(0.1, -0.15, 0.0), "tex": Fx.Tex.DOT,
		"size": 0.12, "curve": "pop", "pick": SIGN, "turbulence": 0.6, "preprocess": 3.0, "aabb": _aabb(ext)})
	p.position = center
	parent.add_child(p)
	return p


## Street-level haze far below: big slow puffs tinted by the sign light (mix blend).
static func haze(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 10.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0.05, 0.2), "spread": 20.0, "speed": Vector2(0.5, 1.4), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 14.0, "scale": Vector2(0.6, 1.4), "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-8, 8), "pick": PackedColorArray([Color(0.5, 0.16, 0.36, 0.28), Color(0.55, 0.32, 0.14, 0.25), Color(0.12, 0.3, 0.32, 0.22)]),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 10.0, "aabb": _aabb(ext, 20.0)})
	p.position = center
	parent.add_child(p)
	return p


## A stream of far traffic: pairs of light streaks flowing along `dir` through a long thin box
## (white headlights one way, red tail lights the other). World space.
static func traffic_stream(parent: Node, center: Vector3, dir: Vector3, length: float, speed: float, amount: int, tail: bool) -> GPUParticles3D:
	var f: Vector3 = dir.normalized()
	var start: Vector3 = center - f * length * 0.5
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": length / speed, "shape": "box",
		"extents": Vector3(0.8, 0.3, 0.8), "dir": f, "spread": 0.0, "speed": Vector2(speed, speed * 1.1),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.18, 2.4), "curve": "flat",
		"color": Color(2.6, 0.25, 0.3) if tail else Color(2.6, 2.4, 2.0), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"preprocess": length / speed, "aabb": _aabb(Vector3(length, 6, length), 10.0)})
	p.position = start
	parent.add_child(p)
	return p


## A checkpoint banked: a shower of neon sparks and a ring of rain-mist blown outward.
static func cp_burst(color: Color) -> Array[GPUParticles3D]:
	var sp: GPUParticles3D = Fx.sparks({"amount": 60, "lifetime": 1.1, "explosiveness": 0.95, "shape": "sphere", "radius": 0.4,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(5.0, 10.0), "gravity": Vector3(0, -14.0, 0),
		"color": Fx.hot(color, 2.4), "size": Vector2(0.05, 0.4), "aabb": _aabb(Vector3.ONE * 8.0)})
	var mist: GPUParticles3D = Fx.burst({"amount": 30, "lifetime": 0.9, "shape": "ring", "ring_radius": 0.8,
		"ring_inner": 0.6, "dir": Vector3.UP, "spread": 80.0, "radial_vel": Vector2(4.0, 7.0), "speed": Vector2(0.5, 1.5),
		"damping": Vector2(4.0, 6.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.0, "curve": "puff",
		"color": Color(0.9, 0.85, 1.0, 0.35), "fade": PackedFloat32Array([0.8, 0.5, 0.0]), "aabb": _aabb(Vector3.ONE * 8.0)})
	var ring: GPUParticles3D = Fx.shockwave(4.0, {"lifetime": 0.5, "color": Fx.hot(color, 2.0), "aabb": _aabb(Vector3.ONE * 6.0)})
	return [sp, mist, ring]


## A firework of neon over the finish (one-shot).
static func firework(color: Color, amount: int = 80) -> GPUParticles3D:
	return Fx.sparks({"amount": amount, "lifetime": 1.5, "explosiveness": 1.0, "shape": "sphere", "radius": 0.3,
		"spread": 180.0, "speed": Vector2(9.0, 13.0), "gravity": Vector3(0, -5.0, 0), "damping": Vector2(2.0, 3.0),
		"color": color, "size": Vector2(0.1, 0.7), "curve": "flat", "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": _aabb(Vector3.ONE * 18.0)})


## Glitter rising round a spot (portal exits, the antenna platform).
static func rising(parent: Node, at: Vector3, radius: float, height: float, amount: int, color: Color) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.2, "shape": "ring", "ring_radius": radius,
		"ring_inner": radius * 0.4, "dir": Vector3.UP, "spread": 6.0, "speed": Vector2(height * 0.3, height * 0.5),
		"tex": Fx.Tex.DOT, "size": 0.16, "curve": "pop", "color": Fx.hot(color, 2.2), "preprocess": 2.2,
		"aabb": _aabb(Vector3(radius, height, radius))})
	p.position = at
	parent.add_child(p)
	return p
