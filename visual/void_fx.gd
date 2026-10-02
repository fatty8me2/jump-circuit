class_name VoidFx
extends RefCounted
## The Void's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is FRAGMENTS: pale shards of the broken dream drifting
## slowly down through the dark, turning as they fall, with pink and cyan glints rising the other
## way. Ambient ones are world-space emitters over an area; one-shots are built idle and restarted
## on their event. Visual only.

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.32, 0.9, 1.0)
const WHITE := Color(0.92, 0.9, 1.0)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


static var _shard_mesh: PrismMesh


## A thin triangular sliver of white glass (shared; tinted by the particle colour).
static func shard_mesh() -> Mesh:
	if _shard_mesh == null:
		_shard_mesh = PrismMesh.new()
		_shard_mesh.size = Vector3(0.22, 0.4, 0.03)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.2
		m.metallic = 0.3
		m.emission_enabled = true
		m.emission = Color(0.35, 0.3, 0.45)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shard_mesh.material = m
	return _shard_mesh


## Slow-falling shards of the broken sky drifting down through a box (world space).
static func fragments(parent: Node, center: Vector3, ext: Vector3, amount: int, scale: float = 1.0) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 9.0, "preprocess": 9.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 25.0, "speed": Vector2(0.3, 0.9), "gravity": Vector3(0.05, -0.1, 0.0),
		"facing": "mesh", "mesh": shard_mesh(), "scale": Vector2(0.6 * scale, 1.8 * scale),
		"pick": PackedColorArray([WHITE, WHITE, Color(1.0, 0.8, 0.92), Color(0.82, 0.95, 1.0)]),
		"angle": Vector2(0, 360), "spin": Vector2(-50, 50), "turbulence": 0.4, "turbulence_scale": 6.0,
		"curve": "pop", "aabb": _aabb(ext + Vector3(0, 6, 0), 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Pink and cyan glints rising slowly through a box (world space).
static func motes(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 5.0, "preprocess": 5.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.2, 0.6), "tex": Fx.Tex.STAR, "size": 0.22,
		"pick": PackedColorArray([Fx.hot(PINK, 1.8), Fx.hot(CYAN, 1.8), Color(1.8, 1.75, 2.0)]),
		"turbulence": 0.7, "turbulence_scale": 4.0, "curve": "pop", "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## A ring of light dust turning slowly round a point (world space) - for doors and set pieces.
static func halo(parent: Node, center: Vector3, radius: float, amount: int, col: Color) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.0, "preprocess": 3.0, "shape": "ring",
		"ring_radius": radius, "ring_inner": radius * 0.85, "ring_axis": Vector3.UP, "speed": Vector2(0.0, 0.1),
		"tex": Fx.Tex.DOT, "size": 0.16, "color": Fx.hot(col, 1.8), "linear": Vector2(0.0, 0.0),
		"radial_vel": Vector2(0.0, 0.0), "curve": "pop", "aabb": _aabb(Vector3(radius, 2, radius), 4.0)})
	p.position = center
	parent.add_child(p)
	return p


## Checkpoint bloom: white shards bursting outward and falling slowly, stars in the stage colour,
## and a flat ring of light across the slab. [0] shards, [1] stars, [2] ring.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var shards: GPUParticles3D = Fx.burst({"amount": 40, "lifetime": 2.2, "facing": "mesh", "mesh": shard_mesh(),
		"dir": Vector3.UP, "spread": 80.0, "speed": Vector2(2.5, 6.0), "gravity": Vector3(0, -2.5, 0),
		"damping": Vector2(1.0, 2.0), "scale": Vector2(0.6, 1.6), "angle": Vector2(0, 360), "spin": Vector2(-300, 300),
		"color": WHITE, "curve": "shrink", "aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 50, "lifetime": 1.4, "tex": Fx.Tex.STAR, "size": 0.3,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 7.0), "gravity": Vector3(0, -1.0, 0),
		"pick": PackedColorArray([Fx.hot(col, 2.4), Fx.hot(WHITE, 2.0)]), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(4.5, {"lifetime": 0.7, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(6, 2, 6))})
	return [shards, stars, ring]


## Finish: a fountain of light and glass out of the door in the sky.
static func finale(col: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.6, "tex": Fx.Tex.STAR, "size": 0.45, "dir": Vector3.UP,
		"spread": 180.0, "speed": Vector2(4.0, 11.0), "gravity": Vector3(0, -3.0, 0), "damping": Vector2(0.5, 1.5),
		"color": Fx.hot(col, 2.6), "curve": "shrink", "aabb": _aabb(Vector3(14, 14, 14))})
