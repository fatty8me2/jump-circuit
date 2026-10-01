class_name JungleFx
extends RefCounted
## Jungle Temple particle kit, built on the shared Fx.emitter: butterflies, pollen and dust motes in
## the god rays, falling leaves, mist on the water, drips from the canopy, waterfall spray, and the
## bursts the level fires on its own events (checkpoints, portal arrivals, the finish). Visual only;
## every amount goes through Fx.count (Settings.particle_scale) inside Fx.emitter.

const JADE := Color(0.25, 0.95, 0.65)
const GOLD := Color(1.0, 0.76, 0.28)
const LEAVES := [Color(0.3, 0.5, 0.14), Color(0.45, 0.58, 0.18), Color(0.56, 0.44, 0.16), Color(0.22, 0.4, 0.12)]


static func _n(amount: int) -> int:
	return roundi(float(amount) * Fx.LEVEL_BOOST)


static func _add(parent: Node3D, p: GPUParticles3D, pos: Vector3) -> GPUParticles3D:
	p.position = pos
	parent.add_child(p)
	return p


static func _leaf_pick() -> PackedColorArray:
	var c := PackedColorArray()
	for l: Color in LEAVES:
		c.append(l)
	return c


## Butterflies flitting about a spot: bright blue morphos and orange wings, flapping (spin) and darting.
static func butterflies(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 10) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 4.0, "preprocess": 4.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1, 0.2, 0), "spread": 180.0, "flatness": 0.4,
		"speed": Vector2(0.8, 2.0), "turbulence": 2.2, "turbulence_scale": 1.6, "tex": Fx.Tex.PETAL,
		"additive": false, "size": 0.32, "scale": Vector2(0.7, 1.2), "angle": Vector2(0, 360), "spin": Vector2(-900, 900),
		"pick": PackedColorArray([Color(0.2, 0.55, 1.0), Color(0.3, 0.7, 1.0), Color(1.0, 0.55, 0.12), Color(1.0, 0.85, 0.2)]),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 8, 8))}), center)


## Pollen and dust motes hanging in the light (glowing a little where the sun catches them).
static func motes(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40, color: Color = Color(2.0, 1.8, 1.1)) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 5.0, "preprocess": 5.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.UP, "spread": 180.0, "speed": Vector2(0.05, 0.25),
		"gravity": Vector3(0.05, 0.02, 0.0), "turbulence": 0.6, "tex": Fx.Tex.DOT, "size": 0.1,
		"scale": Vector2(0.5, 1.3), "color": color, "curve": "pop",
		"aabb": AABB(-extents - Vector3(3, 3, 3), extents * 2.0 + Vector3(6, 6, 6))}), center)


## Leaves spiralling down from the canopy.
static func leaves(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 20) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 7.0, "preprocess": 7.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.DOWN, "spread": 30.0, "speed": Vector2(0.4, 1.0),
		"gravity": Vector3(0.3, -0.6, 0.1), "turbulence": 1.4, "turbulence_scale": 2.0, "tex": Fx.Tex.PETAL,
		"additive": false, "size": 0.28, "scale": Vector2(0.7, 1.3), "angle": Vector2(0, 360), "spin": Vector2(-200, 200),
		"pick": _leaf_pick(), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(6, 20, 6), extents * 2.0 + Vector3(12, 30, 12))}), center)


## Low mist drifting over the water (big soft puffs).
static func mist(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 12) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 9.0, "preprocess": 9.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1, 0.05, 0.3), "spread": 20.0, "speed": Vector2(0.3, 0.9),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 7.0, "scale": Vector2(0.7, 1.4), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-8, 8), "color": Color(0.88, 0.93, 0.86, 0.3),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(15, 6, 15), extents * 2.0 + Vector3(30, 12, 30))}), center)


## Drips falling from a mossy ledge or the canopy.
static func drips(parent: Node3D, center: Vector3, extents: Vector3, fall: float, amount: int = 10) -> GPUParticles3D:
	var life: float = sqrt(2.0 * maxf(fall, 0.5) / 14.0) + 0.1
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.DOWN, "spread": 2.0, "speed": Vector2(0.1, 0.4),
		"gravity": Vector3(0, -14.0, 0), "facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false,
		"size": Vector2(0.03, 0.22), "color": Color(0.8, 0.92, 0.95, 0.6), "fade": PackedFloat32Array([0.4, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(1, fall + 2, 1), extents * 2.0 + Vector3(2, fall + 4, 2))}), center)


## A waterfall's churn: white spray thrown up at its foot and drifting mist.
static func falls_spray(parent: Node3D, pos: Vector3, width: float, amount: int = 40) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var aabb := AABB(Vector3(-width - 8, -2, -10), Vector3(width * 2 + 16, 18, 20))
	n.add_child(Fx.emitter({"amount": _n(amount), "lifetime": 1.6, "preprocess": 1.6, "shape": "box",
		"extents": Vector3(width * 0.45, 0.2, 0.6), "dir": Vector3.UP, "spread": 35.0, "speed": Vector2(3.0, 7.0),
		"gravity": Vector3(0, -9.0, 0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.3, "curve": "puff",
		"angle": Vector2(0, 360), "color": Color(0.92, 0.97, 0.98, 0.55), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": aabb}))
	n.add_child(Fx.emitter({"amount": _n(maxi(amount / 3, 6)), "lifetime": 6.0, "preprocess": 6.0, "shape": "box",
		"extents": Vector3(width * 0.6, 0.5, 2.0), "dir": Vector3(0, 1, 1), "spread": 40.0, "speed": Vector2(0.6, 1.6),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 5.0, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.9, 0.95, 0.95, 0.3), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": aabb}))
	n.add_child(Fx.emitter({"amount": _n(amount), "lifetime": 0.9, "preprocess": 0.9, "shape": "box",
		"extents": Vector3(width * 0.45, 0.2, 0.5), "dir": Vector3.UP, "spread": 50.0, "speed": Vector2(2.0, 6.0),
		"gravity": Vector3(0, -14, 0), "facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false,
		"size": Vector2(0.04, 0.3), "color": Color(0.95, 1.0, 1.0, 0.8), "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": aabb}))
	return n


## Jade sparks rising round a glyph or a brazier (a steady trickle).
static func jade_rise(parent: Node3D, pos: Vector3, radius: float, height: float, amount: int = 14) -> GPUParticles3D:
	var life: float = maxf(height / 1.2, 1.4)
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life,
		"shape": "ring", "ring_radius": radius, "ring_inner": radius * 0.3, "ring_height": 0.2,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.7, 1.4), "turbulence": 0.6,
		"tex": Fx.Tex.STAR, "size": 0.2, "color": Fx.hot(JADE, 1.8), "curve": "pop",
		"aabb": AABB(Vector3(-radius - 3, -2, -radius - 3), Vector3(radius * 2 + 6, height + 6, radius * 2 + 6))}), pos)


## A jade fire in a brazier: a flickering green-white core, sparks and a wisp of smoke.
static func jade_fire(parent: Node3D, pos: Vector3, scale: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var aabb := AABB(Vector3(-2, -1, -2) * scale, Vector3(4, 7, 4) * scale)
	n.add_child(Fx.emitter({"amount": _n(20), "lifetime": 0.55, "shape": "sphere", "radius": 0.14 * scale,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(1.2, 2.2) * scale, "gravity": Vector3(0, 1.5, 0),
		"tex": Fx.Tex.DOT, "size": 0.42 * scale, "curve": "shrink",
		"colors": PackedColorArray([Color(1.6, 3.0, 2.2, 0.0), Color(0.8, 3.0, 1.8, 1.0), Color(0.2, 1.6, 0.9, 0.6), Color(0.05, 0.5, 0.3, 0.0)]),
		"color_offsets": PackedFloat32Array([0.0, 0.12, 0.55, 1.0]), "aabb": aabb}))
	n.add_child(Fx.emitter({"amount": _n(8), "lifetime": 1.4, "shape": "sphere", "radius": 0.15 * scale,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(1.0, 2.5) * scale, "gravity": Vector3(0.2, 0.8, 0),
		"turbulence": 1.2, "tex": Fx.Tex.DOT, "size": 0.08 * scale, "color": Color(1.2, 3.0, 1.8),
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": aabb}))
	var smoke: GPUParticles3D = Fx.emitter({"amount": _n(5), "lifetime": 2.2, "shape": "sphere", "radius": 0.1 * scale,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.8, 1.4) * scale, "gravity": Vector3(0.3, 0.3, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.9 * scale, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.3, 0.34, 0.3, 0.3), "fade": PackedFloat32Array([0.0, 0.7, 0.0]), "aabb": aabb})
	smoke.position = Vector3(0, 0.5 * scale, 0)
	n.add_child(smoke)
	var o := OmniLight3D.new()
	o.light_color = Color(0.4, 1.0, 0.7)
	o.light_energy = 1.4
	o.omni_range = 7.0 * scale
	o.position = Vector3(0, 0.6 * scale, 0)
	n.add_child(o)
	return n


## One-shot: jade and gold stars (checkpoints, the finish, portal arrivals). Not emitting until restart().
static func glints(parent: Node3D, pos: Vector3, amount: int = 40, speed: float = 6.0) -> GPUParticles3D:
	return _add(parent, Fx.burst({"amount": _n(amount), "lifetime": 1.3, "tex": Fx.Tex.STAR, "size": 0.32,
		"speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, -2.0, 0), "damping": Vector2(1.0, 2.0),
		"pick": PackedColorArray([Fx.hot(JADE, 2.2), Fx.hot(GOLD, 2.2)]),
		"aabb": AABB(Vector3(-10, -6, -10), Vector3(20, 16, 20))}), pos)


## One-shot: a puff of leaves bursting out (checkpoints, portal arrivals).
static func leaf_burst(parent: Node3D, pos: Vector3, amount: int = 30, speed: float = 5.0) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 2.2, "one_shot": true, "explosiveness": 0.9,
		"emitting": false, "shape": "sphere", "radius": 0.4, "dir": Vector3.UP, "spread": 70.0,
		"speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, -2.5, 0), "damping": Vector2(1.0, 2.0),
		"turbulence": 1.2, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.3, "angle": Vector2(0, 360),
		"spin": Vector2(-300, 300), "pick": _leaf_pick(), "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": AABB(Vector3(-10, -8, -10), Vector3(20, 18, 20))}), pos)


## One-shot: a column of jade light shooting up (the finish).
static func jade_column(parent: Node3D, pos: Vector3, amount: int = 90) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 2.4, "one_shot": true, "explosiveness": 0.6,
		"emitting": false, "shape": "ring", "ring_radius": 1.4, "ring_inner": 0.2, "ring_height": 0.3,
		"dir": Vector3.UP, "spread": 6.0, "speed": Vector2(10.0, 22.0), "damping": Vector2(2.0, 4.0),
		"tex": Fx.Tex.STAR, "size": 0.45, "color": Fx.hot(JADE, 2.4), "curve": "pop",
		"aabb": AABB(Vector3(-8, -2, -8), Vector3(16, 50, 16))}), pos)
