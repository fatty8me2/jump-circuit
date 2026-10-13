class_name SkysurfFx
extends RefCounted
## Sky Surf's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is PETALS ON THE WIND: pastel petals and glints streaming
## past along the way you are flying, with sparkling motes in the low sunlight. Ambient ones are
## world-space emitters over an area; one-shots are built idle and restarted on their event. Visual only.

static func _pastels() -> PackedColorArray:
	return PackedColorArray([Color(1.0, 0.62, 0.7), Color(1.0, 0.82, 0.62), Color(1.0, 0.95, 0.7), Color(0.72, 0.95, 0.82),
		Color(0.7, 0.9, 1.0), Color(0.86, 0.76, 1.0)])


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Pastel petals streaming across a box in the wind (world space). `wind` is their drift direction.
static func petals(parent: Node, center: Vector3, ext: Vector3, amount: int, wind: Vector3) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 8.0, "preprocess": 8.0, "shape": "box", "extents": ext,
		"dir": wind.normalized(), "spread": 18.0, "speed": Vector2(1.5, 3.5), "tex": Fx.Tex.PETAL, "additive": false,
		"size": 0.34, "pick": _pastels(), "angle": Vector2(0, 360), "spin": Vector2(-120, 120),
		"gravity": Vector3(0, -0.12, 0), "turbulence": 0.9, "turbulence_scale": 5.0, "curve": "pop",
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext + Vector3(30, 8, 30), 10.0)})
	p.position = center
	parent.add_child(p)
	return p


## Sparkling motes hanging in the low sunlight (world space).
static func motes(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 7.0, "preprocess": 7.0, "shape": "box", "extents": ext,
		"dir": Vector3(0.4, 0.2, 0.1), "spread": 180.0, "speed": Vector2(0.05, 0.4), "tex": Fx.Tex.STAR, "size": 0.2,
		"color": Color(1.8, 1.45, 0.95, 0.9), "turbulence": 0.5, "turbulence_scale": 5.0, "curve": "pop",
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## Checkpoint burst: a fountain of petals, stars and a flat ring. [0] petals, [1] stars, [2] ring.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var pet: GPUParticles3D = Fx.burst({"amount": 50, "lifetime": 2.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.34,
		"dir": Vector3.UP, "spread": 55.0, "speed": Vector2(4.0, 10.0), "gravity": Vector3(0, -6.0, 0),
		"damping": Vector2(0.4, 1.0), "scale": Vector2(0.7, 1.3), "angle": Vector2(0, 360), "spin": Vector2(-300, 300),
		"pick": _pastels(), "curve": "shrink", "aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 30, "lifetime": 1.2, "tex": Fx.Tex.STAR, "size": 0.34, "dir": Vector3.UP,
		"spread": 70.0, "speed": Vector2(2.0, 6.0), "gravity": Vector3(0, -1.0, 0), "color": Fx.hot(col, 2.4), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(5.0, {"lifetime": 0.8, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(6, 2, 6))})
	return [pet, stars, ring]
