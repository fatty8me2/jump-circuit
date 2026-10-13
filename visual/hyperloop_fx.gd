class_name HyperloopFx
extends RefCounted
## Hyperloop's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is CLEAN AIR AT SPEED: cool cyan sparks, white streaks and a
## ring of light. Ambient ones are world-space emitters over an area; one-shots are built idle and
## restarted on their event. Visual only; HDR terms stay under ~2.6.

const CYAN := Color(0.20, 0.88, 1.0)
const WHITE := Color(1.0, 0.99, 0.97)
const CORAL := Color(1.0, 0.60, 0.48)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Checkpoint bloom at a hub: cyan stars fountaining up, white light dust, and a flat ring of light across
## the plate. [0] dust, [1] stars, [2] ring.
static func cp_burst(col: Color = CYAN) -> Array[GPUParticles3D]:
	var dust: GPUParticles3D = Fx.burst({"amount": 40, "lifetime": 2.0, "tex": Fx.Tex.DOT, "size": 0.18,
		"dir": Vector3.UP, "spread": 75.0, "speed": Vector2(2.0, 6.0), "gravity": Vector3(0, -1.5, 0),
		"damping": Vector2(0.8, 1.6), "pick": PackedColorArray([Fx.hot(WHITE, 1.9), Fx.hot(col, 1.9)]),
		"curve": "flat", "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": _aabb(Vector3(8, 9, 8))})
	var stars: GPUParticles3D = Fx.burst({"amount": 46, "lifetime": 1.3, "tex": Fx.Tex.STAR, "size": 0.3,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(3.0, 9.0), "gravity": Vector3(0, -2.0, 0),
		"pick": PackedColorArray([Fx.hot(col, 2.4), Fx.hot(CORAL, 2.0)]), "aabb": _aabb(Vector3(8, 10, 8))})
	var ring: GPUParticles3D = Fx.shockwave(7.5, {"lifetime": 0.8, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(8, 2, 8))})
	return [dust, stars, ring]


## Drifting motes of light rising past the decks (world space).
static func motes(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 6.0, "preprocess": 6.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.2, 0.7), "gravity": Vector3(0.1, 0.06, 0.0), "tex": Fx.Tex.DOT,
		"size": 0.14, "pick": PackedColorArray([Fx.hot(CYAN, 1.8), Fx.hot(WHITE, 1.8)]),
		"turbulence": 0.6, "turbulence_scale": 4.0, "curve": "pop", "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## Finish: a fountain of cyan and white light.
static func finale(col: Color, amount: int = 100) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.6, "tex": Fx.Tex.STAR, "size": 0.45, "dir": Vector3.UP,
		"spread": 180.0, "speed": Vector2(4.0, 12.0), "gravity": Vector3(0, -3.0, 0), "damping": Vector2(0.5, 1.5),
		"color": Fx.hot(col, 2.5), "curve": "shrink", "aabb": _aabb(Vector3(14, 14, 14))})
