class_name FrontierFx
extends RefCounted
## Wild West Heist particle presets on top of Fx (so every amount goes through Fx.count, i.e.
## Settings.particle_scale()). Ambient ones are world-space emitters over an area. Because the train
## stands still while the world slides past, everything airborne drifts BACK along +Z (the wind of the
## train's speed): dust, cinders, smoke and steam all stream toward the caboose. Visual only.

const WIND: Vector3 = Vector3(0.0, 0.0, 9.0)
const GOLD: Color = Color(2.4, 1.8, 0.7)


static func _aabb(ext: Vector3, extra: float = 8.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Warm dust motes hanging in the low sun over an area, streaming slowly back.
static func dust(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.5, "shape": "box", "extents": ext,
		"speed": Vector2(0.1, 0.5), "spread": 180.0, "gravity": Vector3(0.1, 0.05, 2.5), "tex": Fx.Tex.DOT,
		"size": 0.12, "additive": false, "color": Color(1.0, 0.78, 0.5, 0.75), "turbulence": 0.8,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 3.5, "aabb": _aabb(ext, 20.0)})
	p.position = center
	parent.add_child(p)
	return p


## Glowing cinders blown back off the locomotive's stack, tumbling along the train.
static func cinders(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.6, "shape": "box", "extents": ext,
		"dir": Vector3(0, 0.2, 1), "spread": 25.0, "speed": Vector2(4.0, 8.0), "gravity": Vector3(0, -0.8, 2.0),
		"tex": Fx.Tex.DOT, "size": 0.1, "colors": PackedColorArray([Color(3.2, 1.6, 0.4, 0.0), Color(3.0, 1.2, 0.3, 1.0), Color(1.2, 0.3, 0.1, 0.0)]),
		"turbulence": 1.2, "turbulence_scale": 3.0, "preprocess": 2.6, "aabb": _aabb(ext, 30.0)})
	p.position = center
	parent.add_child(p)
	return p


## Sparks spraying from the wheels under a car (brake shoes biting the rails).
static func wheel_sparks(parent: Node, at: Vector3, amount: int = 14) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.sparks({"amount": amount, "lifetime": 0.45, "one_shot": false, "explosiveness": 0.0,
		"randomness": 0.6, "shape": "box", "extents": Vector3(1.4, 0.05, 0.2), "dir": Vector3(0, 0.35, 1), "spread": 25.0,
		"speed": Vector2(4.0, 9.0), "gravity": Vector3(0, -14.0, 0), "size": Vector2(0.05, 0.4),
		"color": Color(3.2, 1.9, 0.6), "aabb": _aabb(Vector3(2, 2, 6))})
	p.position = at
	parent.add_child(p)
	return p


## The locomotive's smoke plume: thick puffs rising off the stack and rolling back over the train.
static func smoke_plume(parent: Node, at: Vector3, amount: int = 60) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 6.0, "shape": "sphere", "radius": 0.5,
		"dir": Vector3(0, 1, 0.3), "spread": 12.0, "speed": Vector2(5.0, 8.0), "damping": Vector2(1.2, 1.8),
		"gravity": Vector3(0, 0.8, 7.5), "tex": Fx.Tex.SMOKE, "additive": false, "size": 2.4,
		"scale": Vector2(0.8, 1.6), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-30, 30),
		"colors": PackedColorArray([Color(0.22, 0.2, 0.2, 0.0), Color(0.24, 0.21, 0.2, 0.85), Color(0.5, 0.4, 0.36, 0.5), Color(0.8, 0.6, 0.48, 0.0)]),
		"color_offsets": PackedFloat32Array([0.0, 0.08, 0.5, 1.0]), "preprocess": 6.0,
		"aabb": AABB(Vector3(-40, -10, -20), Vector3(80, 60, 120))})
	p.position = at
	parent.add_child(p)
	return p


## Live steam leaking from a valve or cylinder cock, puffing back along the train.
static func steam_leak(parent: Node, at: Vector3, dir: Vector3, amount: int = 16) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 1.4, "shape": "sphere", "radius": 0.15,
		"dir": dir, "spread": 20.0, "speed": Vector2(2.0, 4.0), "damping": Vector2(1.5, 2.5),
		"gravity": Vector3(0, 0.8, 5.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.9, "curve": "puff",
		"angle": Vector2(0, 360), "color": Color(1.0, 1.0, 1.0, 0.55), "fade": PackedFloat32Array([0.0, 0.8, 0.4, 0.0]),
		"preprocess": 1.4, "aabb": _aabb(Vector3(3, 3, 8))})
	p.position = at
	parent.add_child(p)
	return p


## Dry leaves and scraps of tumbleweed whipping back along the roofs.
static func scraps(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.5, "shape": "box", "extents": ext,
		"dir": Vector3(0.1, 0.1, 1), "spread": 25.0, "speed": Vector2(5.0, 9.0), "gravity": Vector3(0, -0.6, 0),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.22,
		"pick": PackedColorArray([Color(0.62, 0.5, 0.3), Color(0.5, 0.36, 0.22), Color(0.72, 0.62, 0.4)]),
		"angle": Vector2(0, 360), "spin": Vector2(-400, 400), "turbulence": 1.4,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 2.5, "aabb": _aabb(ext, 25.0)})
	p.position = center
	parent.add_child(p)
	return p


## Fine dust swirling up off the canyon floor far below in long trailing veils.
static func veils(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 8.0, "shape": "box", "extents": ext,
		"dir": Vector3(0, 0.2, 1), "spread": 15.0, "speed": Vector2(6.0, 10.0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 12.0, "scale": Vector2(0.6, 1.4), "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-10, 10), "color": Color(0.92, 0.66, 0.44, 0.22), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"preprocess": 8.0, "aabb": _aabb(ext, 60.0)})
	p.position = center
	parent.add_child(p)
	return p


## A shower of gold coins and glints (one-shot): a stage of the heist banked.
static func loot(radius: float, amount: int = 40) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 1.4, "shape": "sphere", "radius": radius * 0.3,
		"dir": Vector3.UP, "spread": 45.0, "speed": Vector2(4.0, 8.0), "gravity": Vector3(0, -16.0, 2.0),
		"damping": Vector2(0.5, 1.0), "tex": Fx.Tex.STAR, "size": 0.32, "curve": "flat", "color": GOLD,
		"angle": Vector2(0, 360), "spin": Vector2(-500, 500), "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": _aabb(Vector3.ONE * 6.0)})


## A ring of dust kicked up off the boards (one-shot).
static func dust_ring(radius: float) -> GPUParticles3D:
	return Fx.smoke({"amount": 18, "lifetime": 1.0, "shape": "ring", "ring_radius": radius, "ring_inner": radius * 0.6,
		"dir": Vector3(0, 0.3, 0), "spread": 80.0, "speed": Vector2(1.5, 3.0), "size": 1.1,
		"gravity": Vector3(0, 0.4, 3.0), "color": Color(0.88, 0.68, 0.48, 0.55), "aabb": _aabb(Vector3.ONE * 6.0)})


## Steam blasted from the whistle (one-shot burst, then it fades).
static func whistle_steam(amount: int = 50) -> GPUParticles3D:
	return Fx.smoke({"amount": amount, "lifetime": 2.2, "explosiveness": 0.4, "shape": "sphere", "radius": 0.15,
		"dir": Vector3.UP, "spread": 18.0, "speed": Vector2(6.0, 11.0), "damping": Vector2(1.5, 2.5), "size": 1.4,
		"gravity": Vector3(0, 0.6, 6.0), "color": Color(1.0, 1.0, 1.0, 0.8), "aabb": _aabb(Vector3(4, 12, 14))})


## Fireworks over the finish: a shell of gold and red sparks.
static func firework(color: Color, amount: int = 70) -> GPUParticles3D:
	return Fx.sparks({"amount": amount, "lifetime": 1.5, "explosiveness": 1.0, "shape": "sphere", "radius": 0.3,
		"spread": 180.0, "speed": Vector2(8.0, 12.0), "gravity": Vector3(0, -4.0, 2.0), "damping": Vector2(2.0, 3.0),
		"color": color, "size": Vector2(0.1, 0.6), "curve": "flat", "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": _aabb(Vector3.ONE * 18.0)})
