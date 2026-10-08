class_name ArcaneFx
extends RefCounted
## The Arcane Library's particle presets on top of Fx (every amount goes through Fx.count, i.e.
## Settings.particle_scale()). The signature is LOOSE PAGES: sheets of parchment drifting down through
## the candlelight, turning as they fall, with warm gold motes (candle sparks and dust in the light)
## rising slowly the other way and the odd violet spell-glint. Ambient ones are world-space emitters
## over an area; one-shots are built idle and restarted on their event. Visual only.

const GOLD := Color(1.0, 0.78, 0.35)
const VIOLET := Color(0.62, 0.4, 1.0)
const PARCHMENT := Color(0.96, 0.9, 0.74)


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


static var _page_mesh: QuadMesh


## A loose sheet of parchment (shared; tinted by the particle colour, lit from both sides).
static func page_mesh() -> Mesh:
	if _page_mesh == null:
		_page_mesh = QuadMesh.new()
		_page_mesh.size = Vector2(0.32, 0.42)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.emission_enabled = true
		m.emission = Color(0.22, 0.16, 0.08)
		_page_mesh.material = m
	return _page_mesh


## Loose pages drifting down through a box (world space).
static func pages(parent: Node, center: Vector3, ext: Vector3, amount: int, scale: float = 1.0) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 10.0, "preprocess": 10.0, "shape": "box", "extents": ext,
		"dir": Vector3.DOWN, "spread": 30.0, "speed": Vector2(0.25, 0.8), "gravity": Vector3(0.05, -0.12, 0.0),
		"facing": "mesh", "mesh": page_mesh(), "scale": Vector2(0.7 * scale, 1.5 * scale),
		"pick": PackedColorArray([PARCHMENT, PARCHMENT, Color(0.9, 0.82, 0.62), Color(0.95, 0.86, 0.7)]),
		"angle": Vector2(0, 360), "spin": Vector2(-70, 70), "turbulence": 0.5, "turbulence_scale": 5.0,
		"curve": "pop", "aabb": _aabb(ext + Vector3(0, 6, 0), 8.0)})
	p.position = center
	parent.add_child(p)
	return p


## Gold candle-sparks and dust rising slowly through a box (world space).
static func motes(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 6.0, "preprocess": 6.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.15, 0.5), "tex": Fx.Tex.STAR, "size": 0.2,
		"pick": PackedColorArray([Fx.hot(GOLD, 1.9), Fx.hot(GOLD, 1.5), Fx.hot(VIOLET, 1.7)]),
		"turbulence": 0.6, "turbulence_scale": 4.0, "curve": "pop", "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## A ring of gold dust turning slowly round a point (world space) - for doors and set pieces.
static func halo(parent: Node, center: Vector3, radius: float, amount: int, col: Color) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 3.0, "preprocess": 3.0, "shape": "ring",
		"ring_radius": radius, "ring_inner": radius * 0.85, "ring_axis": Vector3.UP, "speed": Vector2(0.0, 0.1),
		"tex": Fx.Tex.DOT, "size": 0.16, "color": Fx.hot(col, 1.8), "linear": Vector2(0.0, 0.0),
		"radial_vel": Vector2(0.0, 0.0), "curve": "pop", "aabb": _aabb(Vector3(radius, 2, radius), 4.0)})
	p.position = center
	parent.add_child(p)
	return p


## Checkpoint bloom: parchment leaves bursting up and fluttering down, gold stars and a flat ring of
## light across the slab. [0] pages, [1] stars, [2] ring.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var leaves: GPUParticles3D = Fx.burst({"amount": 36, "lifetime": 2.4, "facing": "mesh", "mesh": page_mesh(),
		"dir": Vector3.UP, "spread": 75.0, "speed": Vector2(2.5, 6.0), "gravity": Vector3(0, -2.2, 0),
		"damping": Vector2(1.0, 2.0), "scale": Vector2(0.7, 1.6), "angle": Vector2(0, 360), "spin": Vector2(-260, 260),
		"color": PARCHMENT, "curve": "shrink", "aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 50, "lifetime": 1.4, "tex": Fx.Tex.STAR, "size": 0.3,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 7.0), "gravity": Vector3(0, -1.0, 0),
		"pick": PackedColorArray([Fx.hot(col, 2.4), Fx.hot(GOLD, 2.0)]), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(4.5, {"lifetime": 0.7, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(6, 2, 6))})
	return [leaves, stars, ring]


## Finish: a fountain of gold light and loose leaves out of the open grimoire.
static func finale(col: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.8, "tex": Fx.Tex.STAR, "size": 0.45, "dir": Vector3.UP,
		"spread": 180.0, "speed": Vector2(4.0, 11.0), "gravity": Vector3(0, -3.0, 0), "damping": Vector2(0.5, 1.5),
		"color": Fx.hot(col, 2.6), "curve": "shrink", "aabb": _aabb(Vector3(14, 14, 14))})


## Pages bursting out of an open book at the finish (leaves, not sparks).
static func page_fountain(amount: int = 60) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 3.2, "facing": "mesh", "mesh": page_mesh(), "dir": Vector3.UP,
		"spread": 60.0, "speed": Vector2(5.0, 12.0), "gravity": Vector3(0, -3.5, 0), "damping": Vector2(0.4, 1.0),
		"scale": Vector2(0.8, 1.8), "angle": Vector2(0, 360), "spin": Vector2(-240, 240), "color": PARCHMENT,
		"curve": "shrink", "aabb": _aabb(Vector3(14, 16, 14))})
