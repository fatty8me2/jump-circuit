class_name DoomFx
extends RefCounted
## Doom Fortress particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is SPARKS AND STEAM: showers of welding-bright sparks
## spilling off grinding machinery, white steam jetting from every joint, embers and ash drifting up
## from the forges far below. Ambient ones are world-space emitters over an area; one-shots are built
## idle and restarted on their event. Visual only.

const ALARM := Color(1.0, 0.08, 0.04)
const MOLTEN := Color(1.0, 0.45, 0.08)
const HOT := Color(3.0, 1.3, 0.35)
const WHITE_HOT := Color(3.0, 2.4, 1.6)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## A slow leak of steam from a joint or grate (world space, mix blend).
static func wisps(parent: Node, at: Vector3, height: float = 3.0, amount: int = 12, radius: float = 0.4) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.2, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 14.0, "speed": Vector2(height * 0.3, height * 0.5), "gravity": Vector3(0.2, 0.3, 0.1),
		"damping": Vector2(0.4, 1.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.1, "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-30, 30), "color": Color(0.82, 0.78, 0.76, 0.28), "turbulence": 0.6,
		"fade": PackedFloat32Array([0.0, 0.9, 0.5, 0.0]), "preprocess": 2.2, "aabb": _aabb(Vector3(2, height + 2, 2))})
	p.position = at
	parent.add_child(p)
	return p


## A hard jet of steam, idle until restarted (vent blasts). `up` is the jet direction.
static func jet(height: float, radius: float, tint: Color = Color(0.92, 0.9, 0.88, 0.55), amount: int = 60) -> GPUParticles3D:
	return Fx.emitter({"amount": amount, "lifetime": 0.9, "one_shot": true, "explosiveness": 0.55,
		"shape": "sphere", "radius": radius * 0.6, "dir": Vector3.UP, "spread": 9.0,
		"speed": Vector2(height * 1.4, height * 2.0), "damping": Vector2(height * 1.2, height * 1.8),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.3, "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-60, 60), "color": tint, "fade": PackedFloat32Array([0.9, 0.7, 0.0]),
		"aabb": _aabb(Vector3(radius + 2.0, height + 3.0, radius + 2.0))})


## A hissing warning: thin fast streaks of steam leaking up through a grate (continuous; toggle emitting).
static func hiss(radius: float, color: Color = Color(1.0, 0.98, 0.95, 0.5)) -> GPUParticles3D:
	return Fx.emitter({"amount": 30, "lifetime": 0.45, "emitting": false, "shape": "box",
		"extents": Vector3(radius * 0.7, 0.02, radius * 0.7), "dir": Vector3.UP, "spread": 6.0,
		"speed": Vector2(3.0, 6.0), "facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false,
		"size": Vector2(0.06, 0.6), "color": color, "fade": PackedFloat32Array([0.0, 1.0, 0.0]),
		"aabb": _aabb(Vector3(radius + 1.0, 4.0, radius + 1.0))})


## Welding-bright sparks spraying from a grinding point (continuous, sparse bursts).
static func spark_spray(parent: Node, at: Vector3, dir: Vector3 = Vector3(0, 0.4, 1), amount: int = 18, color: Color = HOT) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 0.7, "explosiveness": 0.6, "shape": "sphere", "radius": 0.15,
		"dir": dir, "spread": 40.0, "speed": Vector2(3.0, 7.0), "gravity": Vector3(0, -14.0, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.03, 0.26), "color": color,
		"aabb": _aabb(Vector3(4, 6, 4))})
	p.position = at
	parent.add_child(p)
	return p


## A one-shot shower of sparks (slams, snaps, breaks).
static func spark_burst(amount: int = 36, color: Color = HOT, ext: Vector3 = Vector3(0.6, 0.1, 0.6)) -> GPUParticles3D:
	return Fx.sparks({"amount": amount, "lifetime": 0.8, "shape": "box", "extents": ext, "dir": Vector3.UP,
		"spread": 75.0, "speed": Vector2(3.0, 8.0), "color": color, "size": Vector2(0.04, 0.32),
		"aabb": _aabb(ext + Vector3(4, 6, 4))})


## Embers rising from the forges and molten channels far below (world space).
static func embers(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 4.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(1.0, 2.6), "gravity": Vector3(0.1, 0.4, 0.0),
		"tex": Fx.Tex.DOT, "size": 0.12, "curve": "pop", "turbulence": 0.9, "turbulence_scale": 3.0,
		"pick": PackedColorArray([Color(3.0, 1.2, 0.3), Color(2.6, 0.6, 0.15), Color(3.0, 1.8, 0.6)]),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 4.0, "aabb": _aabb(ext + Vector3(0, 10, 0))})
	p.position = center
	parent.add_child(p)
	return p


## Smoke and steam rolling through a hall (world space, mix blend), tinted by the alarm light.
static func haze(parent: Node, center: Vector3, ext: Vector3, amount: int, tint: Color = Color(0.32, 0.12, 0.09, 0.22)) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 9.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0.1, 0.2), "spread": 25.0, "speed": Vector2(0.4, 1.2), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 9.0, "scale": Vector2(0.6, 1.4), "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-8, 8), "color": tint, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"preprocess": 9.0, "aabb": _aabb(ext, 16.0)})
	p.position = center
	parent.add_child(p)
	return p


## Molten spatter flicking up off a pour or a channel (continuous; toggle emitting).
static func spatter(ext: Vector3, amount: int = 30) -> GPUParticles3D:
	return Fx.emitter({"amount": amount, "lifetime": 0.6, "emitting": false, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(2.0, 5.5), "gravity": Vector3(0, -16.0, 0),
		"tex": Fx.Tex.DOT, "size": 0.14, "curve": "shrink", "color": Color(3.0, 1.4, 0.35),
		"aabb": _aabb(ext + Vector3(2, 4, 2))})


## A checkpoint banked: a shower of sparks, a puff of steam and an alarm-red ring.
static func cp_burst() -> Array[GPUParticles3D]:
	var sp: GPUParticles3D = Fx.sparks({"amount": 60, "lifetime": 1.1, "explosiveness": 0.95, "shape": "sphere", "radius": 0.4,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(5.0, 10.0), "gravity": Vector3(0, -14.0, 0),
		"color": WHITE_HOT, "size": Vector2(0.05, 0.4), "aabb": _aabb(Vector3.ONE * 8.0)})
	var steam: GPUParticles3D = Fx.burst({"amount": 30, "lifetime": 1.0, "shape": "ring", "ring_radius": 0.8,
		"ring_inner": 0.6, "dir": Vector3.UP, "spread": 80.0, "radial_vel": Vector2(4.0, 7.0), "speed": Vector2(0.5, 1.5),
		"damping": Vector2(4.0, 6.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.1, "curve": "puff",
		"color": Color(0.9, 0.88, 0.86, 0.4), "fade": PackedFloat32Array([0.8, 0.5, 0.0]), "aabb": _aabb(Vector3.ONE * 8.0)})
	var ring: GPUParticles3D = Fx.shockwave(4.0, {"lifetime": 0.5, "color": Color(2.6, 0.4, 0.2), "aabb": _aabb(Vector3.ONE * 6.0)})
	return [sp, steam, ring]


## The reactor going dark at the finish: a huge burst of sparks and a falling cloud of cooling motes.
static func shutdown_burst(radius: float) -> Array[GPUParticles3D]:
	var sp: GPUParticles3D = Fx.sparks({"amount": 140, "lifetime": 1.8, "explosiveness": 1.0, "shape": "sphere", "radius": radius,
		"spread": 180.0, "speed": Vector2(6.0, 14.0), "gravity": Vector3(0, -9.0, 0), "damping": Vector2(1.0, 2.0),
		"color": WHITE_HOT, "size": Vector2(0.08, 0.6), "curve": "flat", "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": _aabb(Vector3.ONE * (radius + 20.0))})
	var cool: GPUParticles3D = Fx.burst({"amount": 90, "lifetime": 3.0, "shape": "sphere", "radius": radius,
		"spread": 180.0, "speed": Vector2(0.5, 2.0), "gravity": Vector3(0, -0.6, 0), "damping": Vector2(0.2, 0.6),
		"tex": Fx.Tex.STAR, "size": 0.3, "color": Color(0.6, 1.4, 2.6), "curve": "pop",
		"aabb": _aabb(Vector3.ONE * (radius + 10.0))})
	var ring: GPUParticles3D = Fx.shockwave(radius * 3.0, {"lifetime": 0.9, "color": Color(0.8, 1.6, 2.8), "aabb": _aabb(Vector3.ONE * radius * 4.0)})
	return [sp, cool, ring]


## Sparks drifting down from the grinding machinery high overhead (world space).
static func falling_sparks(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 2.4, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 20.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -6.0, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.03, 0.22), "color": HOT,
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "preprocess": 2.4, "aabb": _aabb(ext + Vector3(0, 12, 0))})
	p.position = center
	parent.add_child(p)
	return p
