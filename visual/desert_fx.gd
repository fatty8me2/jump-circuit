class_name DesertFx
extends RefCounted
## Scarab Sands particle kit, built on the shared Fx.emitter: wind-blown sand, golden dust
## motes in the sunbeams, rolling sand veils, spray off the dune crests, torch fire, sand
## trickling from cracks, and the bursts the level fires on its own events. Visual only.

const SAND := Color(0.95, 0.76, 0.48)
const GOLD := Color(1.0, 0.72, 0.25)
const TURQUOISE := Color(0.2, 0.9, 0.85)


static func _n(amount: int) -> int:
	return roundi(float(amount) * Fx.LEVEL_BOOST)


static func _add(parent: Node3D, p: GPUParticles3D, pos: Vector3) -> GPUParticles3D:
	p.position = pos
	parent.add_child(p)
	return p


## Fine grains skittering along on the wind (ambient layer 1).
static func sand_drift(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 70) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 2.2, "preprocess": 2.2, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1.0, 0.05, 0.25), "spread": 12.0,
		"speed": Vector2(4.0, 8.0), "gravity": Vector3(0, -0.6, 0), "turbulence": 1.0, "turbulence_scale": 3.0,
		"facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false, "size": Vector2(0.035, 0.32),
		"color": Color(0.98, 0.82, 0.58, 0.8), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(12, 4, 12), extents * 2.0 + Vector3(24, 8, 24))}), center)


## Golden dust motes hanging in the light (ambient layer 2, additive glints).
static func motes(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40, color: Color = Color(2.2, 1.6, 0.8)) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 5.0, "preprocess": 5.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.UP, "spread": 180.0, "speed": Vector2(0.05, 0.3),
		"gravity": Vector3(0.15, 0.02, 0.0), "turbulence": 0.6, "tex": Fx.Tex.DOT, "size": 0.12,
		"scale": Vector2(0.5, 1.3), "color": color, "curve": "pop",
		"aabb": AABB(-extents - Vector3(3, 3, 3), extents * 2.0 + Vector3(6, 6, 6))}), center)


## Big soft veils of blown sand rolling past low down (ambient layer 3).
static func veils(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 14) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 7.0, "preprocess": 7.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1.0, 0.1, 0.2), "spread": 15.0, "speed": Vector2(2.0, 4.0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 6.0, "scale": Vector2(0.7, 1.4), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-15, 15), "color": Color(0.96, 0.8, 0.58, 0.28),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(30, 10, 30), extents * 2.0 + Vector3(60, 20, 60))}), center)


## Sand streaming off a dune crest in the wind (a ribbon along `width` metres of crest).
static func crest_spray(parent: Node3D, pos: Vector3, width: float, amount: int = 30) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 3.0, "preprocess": 3.0,
		"shape": "box", "extents": Vector3(1.0, 0.3, width * 0.5), "dir": Vector3(1.0, 0.35, 0.0), "spread": 12.0,
		"speed": Vector2(4.0, 7.0), "gravity": Vector3(0.5, -0.8, 0), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 2.2, "scale": Vector2(0.5, 1.2), "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(1.0, 0.84, 0.6, 0.45), "fade": PackedFloat32Array([0.0, 0.8, 0.4, 0.0]),
		"aabb": AABB(Vector3(-8, -6, -width), Vector3(40, 16, width * 2.0))}), pos)


## A torch / brazier flame: a flickering core, sparks riding the heat and a wisp of smoke.
static func fire(parent: Node3D, pos: Vector3, scale: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var aabb := AABB(Vector3(-2, -1, -2) * scale, Vector3(4, 7, 4) * scale)
	n.add_child(Fx.emitter({"amount": _n(22), "lifetime": 0.55, "shape": "sphere", "radius": 0.12 * scale,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(1.2, 2.2) * scale, "gravity": Vector3(0, 1.5, 0),
		"tex": Fx.Tex.DOT, "size": 0.42 * scale, "curve": "shrink",
		"colors": PackedColorArray([Color(3.2, 2.4, 1.0, 0.0), Color(3.2, 1.8, 0.5, 1.0), Color(2.4, 0.7, 0.15, 0.6), Color(1.0, 0.2, 0.05, 0.0)]),
		"color_offsets": PackedFloat32Array([0.0, 0.12, 0.55, 1.0]), "aabb": aabb}))
	n.add_child(Fx.emitter({"amount": _n(8), "lifetime": 1.4, "shape": "sphere", "radius": 0.15 * scale,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(1.0, 2.5) * scale, "gravity": Vector3(0.2, 0.8, 0),
		"turbulence": 1.2, "tex": Fx.Tex.DOT, "size": 0.08 * scale, "color": Color(3.0, 1.6, 0.5),
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": aabb}))
	var smoke: GPUParticles3D = Fx.emitter({"amount": _n(6), "lifetime": 2.2, "shape": "sphere", "radius": 0.1 * scale,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.8, 1.4) * scale, "gravity": Vector3(0.3, 0.3, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.9 * scale, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.3, 0.26, 0.24, 0.35), "fade": PackedFloat32Array([0.0, 0.7, 0.0]), "aabb": aabb})
	smoke.position = Vector3(0, 0.5 * scale, 0)
	n.add_child(smoke)
	return n


## A thin stream of sand trickling from a crack (decor), with a little puff where it lands.
static func trickle(parent: Node3D, pos: Vector3, height: float, amount: int = 24) -> GPUParticles3D:
	var life: float = sqrt(2.0 * height / 9.8) + 0.1
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life,
		"shape": "box", "extents": Vector3(0.06, 0.02, 0.06), "dir": Vector3.DOWN, "spread": 2.0,
		"speed": Vector2(0.2, 0.5), "gravity": Vector3(0, -9.8, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"additive": false, "size": Vector2(0.05, 0.4), "color": Color(0.95, 0.78, 0.5, 0.85),
		"fade": PackedFloat32Array([0.6, 1.0, 1.0, 0.0]),
		"aabb": AABB(Vector3(-1, -height - 1, -1), Vector3(2, height + 2, 2))}), pos)


## One-shot sand burst (landings, traps firing, the boulder crash). Not emitting until restart().
static func sand_burst(parent: Node3D, pos: Vector3, radius: float, amount: int = 30, speed: float = 4.0) -> GPUParticles3D:
	return _add(parent, Fx.smoke({"amount": _n(amount), "lifetime": 1.2, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, -1.5, 0),
		"size": 1.4, "color": Color(0.96, 0.8, 0.56, 0.7),
		"aabb": AABB(Vector3(-radius - 8, -4, -radius - 8), Vector3(radius * 2 + 16, 14, radius * 2 + 16))}), pos)


## One-shot of glinting gold and turquoise stars (checkpoints, the finish, portal arrivals).
static func glints(parent: Node3D, pos: Vector3, color: Color, amount: int = 40, speed: float = 6.0) -> GPUParticles3D:
	return _add(parent, Fx.burst({"amount": _n(amount), "lifetime": 1.3, "tex": Fx.Tex.STAR, "size": 0.32,
		"speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, -2.0, 0), "damping": Vector2(1.0, 2.0),
		"color": Fx.hot(color, 2.2), "aabb": AABB(Vector3(-10, -6, -10), Vector3(20, 16, 20))}), pos)


## A lazy column of sparkles rising (oases, the sun disc, portal rings).
static func rising_glints(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, amount: int = 24) -> GPUParticles3D:
	var life: float = maxf(height / 1.2, 1.5)
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life,
		"shape": "ring", "ring_radius": radius, "ring_inner": radius * 0.3, "ring_height": 0.2,
		"dir": Vector3.UP, "spread": 8.0, "speed": Vector2(0.8, 1.6), "turbulence": 0.5,
		"tex": Fx.Tex.STAR, "size": 0.22, "color": Fx.hot(color, 2.0), "curve": "pop",
		"aabb": AABB(Vector3(-radius - 3, -2, -radius - 3), Vector3(radius * 2 + 6, height + 6, radius * 2 + 6))}), pos)


## Dragonflies over an oasis pool: a few darting turquoise glints.
static func dragonflies(parent: Node3D, pos: Vector3, extents: Vector3, amount: int = 6) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 3.0, "preprocess": 3.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1, 0, 0), "spread": 180.0, "flatness": 0.8,
		"speed": Vector2(1.5, 3.0), "turbulence": 2.5, "turbulence_scale": 1.5, "tex": Fx.Tex.STAR, "size": 0.14,
		"color": Color(0.4, 2.4, 2.2), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(3, 3, 3), extents * 2.0 + Vector3(6, 6, 6))}), pos)
