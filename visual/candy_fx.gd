class_name CandyFx
extends RefCounted
## Sugar Rush particle presets on top of Fx (so every amount goes through Fx.count, i.e.
## Settings.particle_scale()). Ambient ones are world-space emitters over an area; one-shots are
## built idle and restarted on their event. Visual only.

static var PASTELS: PackedColorArray = PackedColorArray([Color(1.0, 0.45, 0.62), Color(0.45, 0.78, 1.0), Color(1.0, 0.88, 0.35),
		Color(0.55, 0.95, 0.6), Color(0.8, 0.55, 1.0), Color(1.0, 0.62, 0.35), Color(1.0, 1.0, 1.0)])
static var HOT: PackedColorArray = PackedColorArray([Color(2.2, 0.8, 1.2), Color(0.8, 1.6, 2.4), Color(2.4, 2.0, 0.7),
		Color(0.9, 2.2, 1.1), Color(1.7, 1.0, 2.4)])


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## One-shot confetti: paper-like flakes in every candy colour, thrown up and fluttering down.
static func confetti(radius: float, amount: int, speed: float) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 1.8, "shape": "sphere", "radius": radius * 0.4,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(speed * 0.5, speed), "gravity": Vector3(0, -5.0, 0),
		"damping": Vector2(1.5, 3.0), "tex": Fx.Tex.PETAL, "additive": false, "size": 0.22, "curve": "flat",
		"pick": PASTELS, "angle": Vector2(0, 360), "spin": Vector2(-400, 400), "turbulence": 1.0,
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": _aabb(Vector3.ONE * 6.0)})


## Rainbow sprinkles tumbling slowly down through an area (world space, continuous).
static func sprinkles(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 4.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 20.0, "speed": Vector2(0.6, 1.4), "gravity": Vector3(0.1, -0.5, 0.05),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.07, 0.26),
		"pick": PASTELS, "turbulence": 0.8, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"preprocess": 4.0, "aabb": _aabb(ext, 10.0)})
	p.position = center
	parent.add_child(p)
	return p


## Sugar sparkles twinkling in the air over an area.
static func sparkles(parent: Node, center: Vector3, ext: Vector3, amount: int, color: Color = Color(2.2, 1.8, 2.4)) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.2, "shape": "box", "extents": ext,
		"speed": Vector2(0.05, 0.3), "spread": 180.0, "gravity": Vector3(0, 0.1, 0), "tex": Fx.Tex.STAR,
		"size": 0.28, "curve": "pop", "color": color, "turbulence": 0.5, "preprocess": 2.2, "aabb": _aabb(ext)})
	p.position = center
	parent.add_child(p)
	return p


## Pastel soap-bubbles drifting up (dreamy, mid-air).
static func bubbles(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 7.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 30.0, "speed": Vector2(0.3, 0.8), "gravity": Vector3(0.1, 0.05, 0),
		"tex": Fx.Tex.BUBBLE, "additive": false, "size": 0.6, "scale": Vector2(0.4, 1.4), "curve": "flat",
		"pick": PackedColorArray([Color(1.0, 0.8, 0.95, 0.75), Color(0.8, 0.9, 1.0, 0.75), Color(1.0, 1.0, 0.85, 0.75)]),
		"turbulence": 0.6, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 7.0, "aabb": _aabb(ext, 12.0)})
	p.position = center
	parent.add_child(p)
	return p


## Soft wisps of candyfloss drifting through (mix blend).
static func candyfloss(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 9.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0.1, 0.2), "spread": 30.0, "speed": Vector2(0.4, 1.0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 3.2, "scale": Vector2(0.6, 1.4), "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-12, 12), "pick": PackedColorArray([Color(1.0, 0.75, 0.9, 0.3), Color(0.85, 0.82, 1.0, 0.3), Color(1.0, 0.95, 0.98, 0.3)]),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 9.0, "aabb": _aabb(ext, 16.0)})
	p.position = center
	parent.add_child(p)
	return p


## Fat bubbles rising and popping on a chocolate surface (at `center`, the surface height).
static func choco_bubbles(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 1.6, "shape": "box", "extents": Vector3(ext.x, 0.05, ext.z),
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.1, 0.4), "tex": Fx.Tex.BUBBLE, "additive": false,
		"size": 0.6, "scale": Vector2(0.5, 1.4), "curve": "grow", "color": Color(0.55, 0.3, 0.16, 0.9),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 1.6, "aabb": _aabb(ext)})
	p.position = center
	parent.add_child(p)
	return p


## A chocolate splash (one-shot): brown droplets thrown up off the surface.
static func choco_splash(radius: float, amount: int = 30) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 0.9, "shape": "sphere", "radius": radius * 0.5,
		"dir": Vector3.UP, "spread": 40.0, "speed": Vector2(4.0, 9.0), "gravity": Vector3(0, -18.0, 0),
		"tex": Fx.Tex.DOT, "additive": false, "size": 0.35, "curve": "shrink", "color": Color(0.35, 0.18, 0.09, 1.0),
		"fade": PackedFloat32Array([1.0, 1.0]), "aabb": _aabb(Vector3.ONE * 6.0)})


## A firework (one-shot): a shell of coloured sparks and glitter.
static func firework(color: Color, amount: int = 70) -> GPUParticles3D:
	return Fx.sparks({"amount": amount, "lifetime": 1.4, "explosiveness": 1.0, "shape": "sphere", "radius": 0.3,
		"spread": 180.0, "speed": Vector2(8.0, 12.0), "gravity": Vector3(0, -4.0, 0), "damping": Vector2(2.0, 3.0),
		"color": color, "size": Vector2(0.1, 0.6), "curve": "flat", "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": _aabb(Vector3.ONE * 16.0)})


## Glitter rising gently from a spot (portal exits, the finish dais).
static func rising(parent: Node, at: Vector3, radius: float, height: float, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.4, "shape": "ring", "ring_radius": radius,
		"ring_inner": radius * 0.3, "dir": Vector3.UP, "spread": 8.0, "speed": Vector2(height * 0.25, height * 0.45),
		"tex": Fx.Tex.STAR, "size": 0.28, "curve": "pop", "pick": HOT, "preprocess": 2.4,
		"aabb": _aabb(Vector3(radius, height, radius))})
	p.position = at
	parent.add_child(p)
	return p


## Sugar dust falling off an edge in a thin stream (icing sugar sifting down).
static func sift(parent: Node, at: Vector3, fall: float, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.5, "shape": "box", "extents": Vector3(0.3, 0.05, 0.3),
		"dir": Vector3.DOWN, "spread": 6.0, "speed": Vector2(fall * 0.25, fall * 0.4), "gravity": Vector3(0, -1.0, 0),
		"tex": Fx.Tex.DOT, "additive": false, "size": 0.12, "curve": "flat", "color": Color(1.0, 0.97, 1.0, 0.85),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "preprocess": 2.5, "aabb": _aabb(Vector3(1, fall, 1))})
	p.position = at
	parent.add_child(p)
	return p
