class_name TempestFx
extends RefCounted
## Tempest Tower particle presets on top of Fx (so every amount goes through Fx.count, i.e.
## Settings.particle_scale()). Ambient ones are world-space emitters over an area; one-shots are built
## idle and restarted on their event. Visual only: nothing here touches gameplay.

## Grey daylight rain, never glowing (this is not Neon City).
const RAIN := Color(0.8, 0.84, 0.9, 0.5)
## Which way the hurricane drives everything across the course (world, mostly sideways).
const WIND := Vector3(0.75, -0.25, 0.3)
static var SCRAPS: PackedColorArray = PackedColorArray([Color(0.22, 0.22, 0.24), Color(0.86, 0.86, 0.84), Color(0.95, 0.55, 0.15),
		Color(0.3, 0.42, 0.62), Color(0.62, 0.6, 0.55), Color(0.85, 0.75, 0.2)])


static func _aabb(ext: Vector3, extra: float = 8.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Wind-driven rain slanting hard across a box (streaks stretched along their flight).
static func rain(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 0.8, "shape": "box", "extents": ext,
		"dir": Vector3(WIND.x, -1.0, WIND.z), "spread": 4.0, "speed": Vector2(16.0, 22.0), "facing": "velocity",
		"tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.025, 0.85), "color": RAIN,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 0.8, "aabb": _aabb(ext, 14.0)})
	p.position = center
	parent.add_child(p)
	return p


## Scraps of insulation, paper and tarp tumbling past on the wind.
static func debris(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.0, "shape": "box", "extents": ext,
		"dir": WIND, "spread": 30.0, "speed": Vector2(6.0, 12.0), "gravity": Vector3(0, -0.8, 0),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.22, "scale": Vector2(0.5, 1.6), "curve": "flat",
		"pick": SCRAPS, "angle": Vector2(0, 360), "spin": Vector2(-700, 700), "turbulence": 1.2, "turbulence_scale": 3.0,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 3.0, "aabb": _aabb(ext, 30.0)})
	p.position = center
	parent.add_child(p)
	return p


## Torn cloud (scud) streaming past at and below the course - big soft grey puffs, mix blend.
static func scud(parent: Node, center: Vector3, ext: Vector3, amount: int, col: Color = Color(0.62, 0.65, 0.7, 0.26)) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 7.0, "shape": "box", "extents": ext,
		"dir": Vector3(WIND.x, 0.0, WIND.z), "spread": 12.0, "speed": Vector2(5.0, 9.0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 9.0, "scale": Vector2(0.7, 1.5), "curve": "puff", "color": col,
		"angle": Vector2(0, 360), "spin": Vector2(-10, 10), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"preprocess": 7.0, "aabb": _aabb(ext, 40.0)})
	p.position = center
	parent.add_child(p)
	return p


## Spray whipped off an edge or a beam end by the wind.
static func spray(parent: Node, at: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 1.0, "shape": "box", "extents": ext,
		"dir": Vector3(WIND.x, 0.4, WIND.z), "spread": 25.0, "speed": Vector2(3.0, 7.0), "gravity": Vector3(0, -4.0, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.8, "curve": "puff", "color": Color(0.86, 0.9, 0.95, 0.3),
		"angle": Vector2(0, 360), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": _aabb(ext, 8.0)})
	p.position = at
	parent.add_child(p)
	return p


## Water pouring off a beam or a slab edge in a ragged line (streaks falling and blowing).
static func drips(parent: Node, a: Vector3, b: Vector3, amount: int = 14) -> GPUParticles3D:
	var mid: Vector3 = (a + b) * 0.5
	var half: Vector3 = (b - a).abs() * 0.5 + Vector3(0.05, 0.02, 0.05)
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 1.2, "shape": "box", "extents": half,
		"dir": Vector3.DOWN, "spread": 8.0, "speed": Vector2(1.0, 2.5), "gravity": Vector3(WIND.x * 6.0, -14.0, WIND.z * 6.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.03, 0.4), "color": RAIN,
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": AABB(-half - Vector3(6, 14, 6), half * 2.0 + Vector3(12, 16, 12))})
	p.position = mid
	parent.add_child(p)
	return p


## Welding sparks raining off a beam joint (a few, all the time).
static func weld(parent: Node, at: Vector3, amount: int = 14) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 0.9, "shape": "sphere", "radius": 0.1,
		"dir": Vector3.DOWN, "spread": 60.0, "speed": Vector2(1.0, 4.0), "gravity": Vector3(WIND.x * 3.0, -12.0, WIND.z * 3.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.03, 0.18), "color": Color(2.6, 1.8, 0.7),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": AABB(Vector3(-6, -14, -6), Vector3(12, 16, 12))})
	p.position = at
	parent.add_child(p)
	return p


## The checkpoint answers: a ring of blue-white sparks off the deck and a burst of spray.
static func cp_burst() -> Array[GPUParticles3D]:
	var a: GPUParticles3D = Fx.sparks({"amount": 46, "shape": "ring", "ring_radius": 2.2, "ring_inner": 1.8,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(3.0, 8.0), "color": Color(1.6, 2.0, 2.8),
		"aabb": AABB(Vector3(-8, -2, -8), Vector3(16, 14, 16))})
	var b: GPUParticles3D = Fx.smoke({"amount": 26, "lifetime": 1.0, "shape": "ring", "ring_radius": 2.4,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(1.0, 3.0), "size": 1.2, "color": Color(0.85, 0.9, 0.95, 0.45),
		"aabb": AABB(Vector3(-8, -2, -8), Vector3(16, 12, 16))})
	return [a, b]


## A burst of signal-flare sparks for the finish (`color` HDR).
static func flare(color: Color, amount: int = 80) -> GPUParticles3D:
	return Fx.sparks({"amount": amount, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 180.0,
		"speed": Vector2(5.0, 14.0), "gravity": Vector3(WIND.x * 2.0, -6.0, WIND.z * 2.0), "color": color, "lifetime": 1.6,
		"aabb": AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))})
