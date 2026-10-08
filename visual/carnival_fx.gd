class_name CarnivalFx
extends RefCounted
## Carnival Chaos particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is CONFETTI and FIREWORKS: paper flakes drifting down through
## the string lights, warm glints rising from the midway, and rockets going off over the fairground.
## Ambient ones are world-space emitters over an area; one-shots are built idle and restarted on their
## event. Visual only.

static var CONFETTI: PackedColorArray = PackedColorArray([Color(1.0, 0.35, 0.45), Color(1.0, 0.85, 0.3), Color(0.35, 0.8, 1.0),
		Color(0.5, 0.95, 0.55), Color(0.95, 0.5, 1.0), Color(1.0, 0.6, 0.25)])
static var HOT: PackedColorArray = PackedColorArray([Color(2.4, 0.7, 0.9), Color(2.4, 1.9, 0.6), Color(0.8, 1.8, 2.5),
		Color(0.9, 2.3, 1.0), Color(2.2, 1.0, 2.4)])


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Paper confetti tumbling slowly down through an area (world space, continuous).
static func confetti_drift(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 7.0, "preprocess": 7.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 25.0, "speed": Vector2(0.4, 1.1), "gravity": Vector3(0.12, -0.3, 0.05),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.2, "curve": "flat", "pick": CONFETTI,
		"angle": Vector2(0, 360), "spin": Vector2(-180, 180), "turbulence": 0.7, "turbulence_scale": 5.0,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext + Vector3(0, 6, 0), 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Warm glints rising slowly over the midway (world space, continuous).
static func glints(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 4.0, "preprocess": 4.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.3, 0.9), "tex": Fx.Tex.STAR, "size": 0.2,
		"pick": PackedColorArray([Fx.hot(Color(1.0, 0.8, 0.35), 2.0), Fx.hot(Color(1.0, 0.45, 0.6), 2.0)]),
		"turbulence": 0.5, "turbulence_scale": 4.0, "curve": "pop", "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## A rocket that keeps going off: one burst every `every` s (a looping, explosive emitter). Far scenery.
static func firework(parent: Node, at: Vector3, col: Color, every: float, offset: float, amount: int = 60, speed: float = 14.0) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": every, "explosiveness": 0.97, "preprocess": offset,
		"shape": "sphere", "radius": 0.4, "spread": 180.0, "speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, -3.0, 0),
		"damping": Vector2(1.6, 2.6), "tex": Fx.Tex.STAR, "size": 0.9, "curve": "shrink", "color": Fx.hot(col, 2.2),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(Vector3.ONE * (speed * 2.0), 6.0)})
	p.position = at
	parent.add_child(p)
	return p


## Checkpoint bloom: a spray of confetti, stars in the stage colour and a flat ring of light. [0] confetti,
## [1] stars, [2] ring.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var conf: GPUParticles3D = Fx.burst({"amount": 60, "lifetime": 2.0, "shape": "point", "dir": Vector3.UP, "spread": 70.0,
		"speed": Vector2(3.0, 8.0), "gravity": Vector3(0, -5.0, 0), "damping": Vector2(1.0, 2.5), "tex": Fx.Tex.PETAL,
		"additive": false, "size": 0.26, "curve": "flat", "pick": CONFETTI, "angle": Vector2(0, 360), "spin": Vector2(-400, 400),
		"turbulence": 1.0, "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 40, "lifetime": 1.2, "tex": Fx.Tex.STAR, "size": 0.32,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(2.0, 6.0), "gravity": Vector3(0, -1.0, 0),
		"color": Fx.hot(col, 2.4), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(4.5, {"lifetime": 0.7, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(6, 2, 6))})
	return [conf, stars, ring]


## The finish: a fountain of coloured sparks and confetti.
static func finale(col: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.8, "tex": Fx.Tex.STAR, "size": 0.5, "dir": Vector3.UP,
		"spread": 40.0, "speed": Vector2(8.0, 18.0), "gravity": Vector3(0, -6.0, 0), "damping": Vector2(0.4, 1.0),
		"color": Fx.hot(col, 2.6), "curve": "shrink", "aabb": _aabb(Vector3(16, 20, 16))})


## Steam / popcorn-warm puffs rising from a vent or cart (world space).
static func steam(parent: Node, at: Vector3, amount: int = 14) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.6, "preprocess": 2.6, "shape": "sphere", "radius": 0.2,
		"dir": Vector3.UP, "spread": 14.0, "speed": Vector2(1.0, 1.8), "gravity": Vector3(0.1, 0.3, 0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 1.2, "curve": "puff", "color": Color(1.0, 0.9, 0.8, 0.5),
		"fade": PackedFloat32Array([0.0, 0.8, 0.4, 0.0]), "aabb": _aabb(Vector3(2, 4, 2), 3.0)})
	p.position = at
	parent.add_child(p)
	return p
