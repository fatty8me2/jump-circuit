class_name AuroraFx
extends RefCounted
## Aurora Run's particle presets: checkpoint bursts, the finish fountain and the plaza motes. Purely cosmetic;
## every emitter goes through Fx (which applies Settings.particle_scale()) and has a visibility AABB.

const GREEN := Color(0.2, 1.0, 0.6)
const TEAL := Color(0.15, 0.9, 1.0)
const VIOLET := Color(0.72, 0.38, 1.0)
const WHITE := Color(0.92, 0.97, 1.0)


static func _aabb(e: Vector3) -> AABB:
	return AABB(-e, e * 2.0)


## Plaza fountain when a checkpoint is banked: stars of light, a ribbon of motes and a ring on the snow.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var stars: GPUParticles3D = Fx.burst({"amount": 60, "lifetime": 1.6, "tex": Fx.Tex.STAR, "size": 0.34, "dir": Vector3.UP,
		"spread": 60.0, "speed": Vector2(3.0, 9.0), "gravity": Vector3(0, -2.0, 0), "damping": Vector2(0.4, 1.0),
		"pick": PackedColorArray([Fx.hot(col, 2.4), Fx.hot(WHITE, 2.0), Fx.hot(VIOLET, 2.2)]), "curve": "shrink", "aabb": _aabb(Vector3(8, 10, 8))})
	var motes: GPUParticles3D = Fx.burst({"amount": 40, "lifetime": 2.4, "tex": Fx.Tex.DOT, "size": 0.3, "dir": Vector3.UP,
		"spread": 40.0, "speed": Vector2(1.0, 4.0), "gravity": Vector3(0, 0.6, 0), "turbulence": 1.2,
		"pick": PackedColorArray([Fx.hot(GREEN, 2.2), Fx.hot(TEAL, 2.2)]), "aabb": _aabb(Vector3(8, 10, 8))})
	var ring: GPUParticles3D = Fx.shockwave(5.0, {"lifetime": 0.8, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(7, 2, 7))})
	return [stars, motes, ring]


## The finish: a fountain of aurora light.
static func finale(col: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.8, "tex": Fx.Tex.STAR, "size": 0.45, "dir": Vector3.UP,
		"spread": 70.0, "speed": Vector2(6.0, 15.0), "gravity": Vector3(0, -3.0, 0), "damping": Vector2(0.4, 1.2),
		"color": Fx.hot(col, 2.6), "curve": "shrink", "aabb": _aabb(Vector3(16, 18, 16))})


## A slow column of motes rising off a lantern, crystal cluster or cairn.
static func rising(extent: Vector3, amount: int = 14, col: Color = TEAL) -> GPUParticles3D:
	return Fx.emitter({"amount": amount, "lifetime": 4.0, "preprocess": 4.0, "shape": "box", "extents": extent * 0.5,
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.4, 1.0), "turbulence": 0.8, "tex": Fx.Tex.DOT, "size": 0.2,
		"curve": "pop", "color": Fx.hot(col, 2.2), "aabb": AABB(-extent - Vector3(3, 3, 3), extent * 2.0 + Vector3(6, 12, 6))})
