class_name ManorFx
extends RefCounted
## Phantom Manor particle kit, built on the shared Fx.emitter (so every amount goes through
## Settings.particle_scale()): ground fog rolling over the graves, will-o'-wisps, dead leaves
## on the wind, dust hanging in the candlelight, candle and torch flames, ectoplasm dripping,
## and the bursts the level fires on its own events. Visual only.

const ECTO := Color(0.55, 1.0, 0.6)
const VIOLET := Color(0.7, 0.4, 1.0)
const BLOOD := Color(1.0, 0.25, 0.2)
const CANDLE := Color(1.0, 0.72, 0.4)


static func _n(amount: int) -> int:
	return roundi(float(amount) * Fx.LEVEL_BOOST)


static func _add(parent: Node3D, p: GPUParticles3D, pos: Vector3) -> GPUParticles3D:
	p.position = pos
	parent.add_child(p)
	return p


## Low, heavy ground fog rolling slowly over the graves and through the halls (ambient layer 1).
static func ground_fog(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 16, color: Color = Color(0.62, 0.58, 0.72, 0.3)) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 9.0, "preprocess": 9.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1.0, 0.0, 0.3), "spread": 25.0, "speed": Vector2(0.4, 1.1),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 7.0, "scale": Vector2(0.7, 1.5), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-8, 8), "color": color,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(14, 6, 14), extents * 2.0 + Vector3(28, 12, 28))}), center)


## Will-o'-wisps: little green and violet lights wandering over the graves (ambient layer 2).
static func wisps(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 14) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 5.0, "preprocess": 5.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.UP, "spread": 180.0, "speed": Vector2(0.2, 0.7),
		"turbulence": 2.2, "turbulence_scale": 2.0, "tex": Fx.Tex.DOT, "size": 0.32, "scale": Vector2(0.6, 1.2),
		"pick": PackedColorArray([Color(0.9, 2.6, 1.2), Color(0.7, 2.2, 1.6), Color(1.6, 0.9, 2.6)]),
		"curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 0.7, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 8, 8))}), center)


## Dead leaves tumbling on the night wind (ambient layer 3, outdoors).
static func leaves(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 30) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 5.0, "preprocess": 5.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1.0, -0.2, 0.3), "spread": 25.0, "speed": Vector2(1.0, 2.6),
		"gravity": Vector3(0.4, -0.5, 0.1), "turbulence": 1.4, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.26,
		"pick": PackedColorArray([Color(0.35, 0.2, 0.12), Color(0.5, 0.3, 0.14), Color(0.25, 0.14, 0.12)]),
		"angle": Vector2(0, 360), "spin": Vector2(-260, 260), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(8, 6, 8), extents * 2.0 + Vector3(16, 12, 16))}), center)


## Dust hanging in the candlelight (ambient layer 3, indoors).
static func dust(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 6.0, "preprocess": 6.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.UP, "spread": 180.0, "speed": Vector2(0.03, 0.2),
		"gravity": Vector3(0.05, -0.02, 0.0), "turbulence": 0.6, "tex": Fx.Tex.DOT, "size": 0.08,
		"scale": Vector2(0.5, 1.3), "color": Color(1.6, 1.2, 0.8), "curve": "pop",
		"aabb": AABB(-extents - Vector3(3, 3, 3), extents * 2.0 + Vector3(6, 6, 6))}), center)


## Ghostly motes drifting up out of the floor of a haunted room (ambient layer 2, indoors).
static func ghost_motes(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 30) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 5.0, "preprocess": 5.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.2, 0.6),
		"turbulence": 1.0, "tex": Fx.Tex.STAR, "size": 0.16, "scale": Vector2(0.5, 1.2),
		"pick": PackedColorArray([Color(0.8, 2.2, 1.1), Color(1.3, 0.8, 2.2)]), "curve": "pop",
		"aabb": AABB(-extents - Vector3(3, 3, 3), extents * 2.0 + Vector3(6, 10, 6))}), center)


## A candle / torch flame: a flickering core and a wisp of smoke. `col` tints it (a ghost
## candle burns green).
static func flame(parent: Node3D, pos: Vector3, scale: float = 1.0, col: Color = CANDLE) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var aabb := AABB(Vector3(-1.5, -1, -1.5) * scale, Vector3(3, 5, 3) * scale)
	var hot: Color = Fx.hot(col, 2.6)
	n.add_child(Fx.emitter({"amount": _n(10), "lifetime": 0.45, "shape": "sphere", "radius": 0.05 * scale,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.5, 1.0) * scale, "gravity": Vector3(0, 1.0, 0),
		"tex": Fx.Tex.DOT, "size": 0.22 * scale, "curve": "shrink",
		"colors": PackedColorArray([Color(hot.r, hot.g, hot.b, 0.0), Color(hot.r, hot.g, hot.b, 1.0), Color(hot.r * 0.7, hot.g * 0.4, hot.b * 0.3, 0.0)]),
		"color_offsets": PackedFloat32Array([0.0, 0.15, 1.0]), "aabb": aabb}))
	var smoke: GPUParticles3D = Fx.emitter({"amount": _n(3), "lifetime": 1.6, "shape": "sphere", "radius": 0.04 * scale,
		"dir": Vector3.UP, "spread": 8.0, "speed": Vector2(0.4, 0.8) * scale, "gravity": Vector3(0.1, 0.3, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.35 * scale, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.2, 0.18, 0.2, 0.3), "fade": PackedFloat32Array([0.0, 0.7, 0.0]), "aabb": aabb})
	smoke.position = Vector3(0, 0.3 * scale, 0)
	n.add_child(smoke)
	return n


## Ectoplasm dripping from a height into the dark (decor), a thin glowing green trickle.
static func drip(parent: Node3D, pos: Vector3, height: float, amount: int = 10) -> GPUParticles3D:
	var life: float = sqrt(2.0 * height / 9.8) + 0.1
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life,
		"shape": "box", "extents": Vector3(0.05, 0.02, 0.05), "dir": Vector3.DOWN, "spread": 2.0,
		"speed": Vector2(0.2, 0.5), "gravity": Vector3(0, -9.8, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.05, 0.35), "color": Color(0.7, 2.2, 0.9, 0.9), "fade": PackedFloat32Array([0.6, 1.0, 1.0, 0.0]),
		"aabb": AABB(Vector3(-1, -height - 1, -1), Vector3(2, height + 2, 2))}), pos)


## One-shot burst of ectoplasm (checkpoints, portal arrivals, the finish). Not emitting until restart().
static func ecto_burst(parent: Node3D, pos: Vector3, radius: float, amount: int = 30, speed: float = 4.0, col: Color = ECTO) -> GPUParticles3D:
	return _add(parent, Fx.smoke({"amount": _n(amount), "lifetime": 1.3, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, 1.2, 0),
		"size": 1.2, "additive": true, "color": Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, 0.55),
		"aabb": AABB(Vector3(-radius - 8, -4, -radius - 8), Vector3(radius * 2 + 16, 16, radius * 2 + 16))}), pos)


## One-shot of glinting stars (checkpoints, the finish, portal arrivals).
static func glints(parent: Node3D, pos: Vector3, color: Color, amount: int = 40, speed: float = 6.0) -> GPUParticles3D:
	return _add(parent, Fx.burst({"amount": _n(amount), "lifetime": 1.4, "tex": Fx.Tex.STAR, "size": 0.3,
		"speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, -1.5, 0), "damping": Vector2(1.0, 2.0),
		"color": Fx.hot(color, 2.2), "aabb": AABB(Vector3(-10, -6, -10), Vector3(20, 16, 20))}), pos)


## A lazy column of ghost-lights rising (portal mirrors, the bell, graves).
static func rising(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, amount: int = 20) -> GPUParticles3D:
	var life: float = maxf(height / 1.2, 1.5)
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life,
		"shape": "ring", "ring_radius": radius, "ring_inner": radius * 0.3, "ring_height": 0.2,
		"dir": Vector3.UP, "spread": 8.0, "speed": Vector2(0.8, 1.5), "turbulence": 0.6,
		"tex": Fx.Tex.STAR, "size": 0.2, "color": Fx.hot(color, 2.0), "curve": "pop",
		"aabb": AABB(Vector3(-radius - 3, -2, -radius - 3), Vector3(radius * 2 + 6, height + 6, radius * 2 + 6))}), pos)


## Blood-red petals of light drifting down (the ballroom, the belfry under the moon).
static func petals(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 30) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 6.0, "preprocess": 6.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.DOWN, "spread": 30.0, "speed": Vector2(0.3, 0.8),
		"gravity": Vector3(0.2, -0.4, 0.1), "turbulence": 1.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.22,
		"pick": PackedColorArray([Color(0.6, 0.05, 0.08), Color(0.8, 0.12, 0.16), Color(0.45, 0.04, 0.1)]),
		"angle": Vector2(0, 360), "spin": Vector2(-180, 180), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(4, 8, 4), extents * 2.0 + Vector3(8, 16, 8))}), center)
