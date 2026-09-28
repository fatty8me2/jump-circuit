class_name CarrierFx
extends RefCounted
## Super Carrier particle kit, built on the shared Fx.emitter (so every amount goes through
## Settings.particle_scale()): sea spray off the bow and the hull, mist over the wake, the hangar's
## foam sprinklers and the bubbles popping on the foam, steam, welding sparks in the refit, heat haze
## off parked jets, sun glitter on the sea, salt glints in the air, and the bursts the level fires on
## its own events (checkpoints in the deck crew's jersey colours, arrivals, the finish flyover smoke).
## Visual only.

const SPRAY := Color(0.95, 0.98, 1.0, 0.8)


## The flight deck crew's jersey colours: yellow, green, red, blue, purple, brown, white.
static func crew() -> PackedColorArray:
	return PackedColorArray([Color(1.0, 0.85, 0.1), Color(0.2, 0.85, 0.3), Color(1.0, 0.2, 0.15),
		Color(0.2, 0.45, 1.0), Color(0.65, 0.3, 0.9), Color(0.55, 0.36, 0.2), Color(0.95, 0.95, 0.95)])


static func _n(amount: int) -> int:
	return roundi(float(amount) * Fx.LEVEL_BOOST)


static func _add(parent: Node3D, p: GPUParticles3D, pos: Vector3) -> GPUParticles3D:
	p.position = pos
	parent.add_child(p)
	return p


## Spray thrown up where the sea meets the hull (a box along the waterline), blown aft.
static func spray(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40, out: Vector3 = Vector3(1, 0, 0)) -> GPUParticles3D:
	return _add(parent, Fx.smoke({"amount": _n(amount), "lifetime": 2.2, "one_shot": false, "explosiveness": 0.0,
		"preprocess": 2.2, "shape": "box", "extents": extents, "dir": (out + Vector3(0, 1.4, 0.6)).normalized(),
		"spread": 25.0, "speed": Vector2(3.0, 7.0), "gravity": Vector3(0, -5.0, 2.5), "damping": Vector2(0.5, 1.2),
		"size": 3.2, "color": Color(0.96, 0.98, 1.0, 0.45),
		"aabb": AABB(-extents - Vector3(20, 10, 20), extents * 2.0 + Vector3(40, 30, 40))}), center)


## Fine droplets flicking off the spray (brighter, smaller, faster).
static func droplets(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 50, out: Vector3 = Vector3(1, 0, 0)) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 1.3, "preprocess": 1.3, "shape": "box",
		"extents": extents, "dir": (out + Vector3(0, 1.8, 0.4)).normalized(), "spread": 30.0, "speed": Vector2(5.0, 10.0),
		"gravity": Vector3(0, -14.0, 2.0), "tex": Fx.Tex.DOT, "size": 0.14, "additive": false, "color": SPRAY,
		"fade": PackedFloat32Array([0.0, 1.0, 0.8, 0.0]),
		"aabb": AABB(-extents - Vector3(16, 8, 16), extents * 2.0 + Vector3(32, 24, 32))}), center)


## Low mist rolling over the wake astern.
static func wake_mist(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 24) -> GPUParticles3D:
	return _add(parent, Fx.smoke({"amount": _n(amount), "lifetime": 6.0, "one_shot": false, "explosiveness": 0.0,
		"preprocess": 6.0, "shape": "box", "extents": extents, "dir": Vector3(0, 0.3, 1), "spread": 20.0,
		"speed": Vector2(2.0, 4.0), "size": 9.0, "curve": "puff", "color": Color(0.95, 0.97, 1.0, 0.22),
		"aabb": AABB(-extents - Vector3(30, 10, 60), extents * 2.0 + Vector3(60, 30, 120))}), center)


## A sprinkler head in the hangar overhead raining foam: blobs falling, a cone of mist.
static func sprinkler(parent: Node3D, pos: Vector3, drop: float, amount: int = 26) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var life: float = sqrt(2.0 * drop / 12.0) + 0.3
	var aabb := AABB(Vector3(-5, -drop - 2, -5), Vector3(10, drop + 4, 10))
	n.add_child(Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life, "shape": "sphere", "radius": 0.2,
		"dir": Vector3.DOWN, "spread": 28.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -12.0, 0),
		"tex": Fx.Tex.DOT, "size": 0.2, "additive": false, "scale": Vector2(0.5, 1.4),
		"color": Color(0.96, 0.96, 0.9, 0.9), "fade": PackedFloat32Array([0.4, 1.0, 1.0, 0.0]), "aabb": aabb}))
	n.add_child(Fx.smoke({"amount": _n(maxi(amount / 3, 4)), "lifetime": 2.4, "one_shot": false, "explosiveness": 0.0,
		"preprocess": 2.4, "shape": "sphere", "radius": 0.3, "dir": Vector3.DOWN, "spread": 35.0, "speed": Vector2(1.0, 2.2),
		"gravity": Vector3(0, -1.2, 0), "size": 2.2, "curve": "puff", "color": Color(0.94, 0.95, 0.92, 0.25), "aabb": aabb}))
	return n


## Bubbles swelling and popping over the foam (a flat box just over its surface).
static func foam_pops(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 1.6, "preprocess": 1.6, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.1, 0.5),
		"tex": Fx.Tex.BUBBLE, "size": 0.35, "curve": "pop", "additive": false, "scale": Vector2(0.5, 1.5),
		"color": Color(1.0, 1.0, 0.97, 0.85),
		"aabb": AABB(-extents - Vector3(2, 2, 2), extents * 2.0 + Vector3(4, 6, 4))}), center)


## A lazy column of steam (vents, the catapult troughs, the pit).
static func steam(parent: Node3D, pos: Vector3, radius: float = 0.4, rise: float = 2.0, amount: int = 14) -> GPUParticles3D:
	return _add(parent, Fx.smoke({"amount": _n(amount), "lifetime": 2.6, "one_shot": false, "explosiveness": 0.0,
		"preprocess": 2.6, "shape": "sphere", "radius": radius, "dir": Vector3.UP, "spread": 14.0,
		"speed": Vector2(rise * 0.6, rise * 1.2), "gravity": Vector3(0.3, 0.4, 0.6), "size": 1.6, "curve": "puff",
		"color": Color(0.95, 0.96, 1.0, 0.35), "aabb": AABB(Vector3(-6, -1, -6), Vector3(12, 12, 12))}), pos)


## A welder at work in the refit: a shower of sparks, a hot core that flickers, smoke.
static func welding(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var aabb := AABB(Vector3(-4, -8, -4), Vector3(8, 12, 8))
	n.add_child(Fx.sparks({"amount": _n(22), "lifetime": 0.9, "one_shot": false, "explosiveness": 0.0,
		"emitting": true, "dir": Vector3(0, 0.3, 0), "spread": 80.0, "speed": Vector2(2.0, 6.0),
		"gravity": Vector3(0, -12.0, 0), "color": Color(3.0, 2.2, 1.0), "aabb": aabb}))
	n.add_child(Fx.emitter({"amount": _n(6), "lifetime": 0.25, "tex": Fx.Tex.STAR, "size": 0.6, "speed": Vector2.ZERO,
		"spread": 0.0, "curve": "pop", "color": Color(2.4, 2.6, 3.0), "aabb": aabb}))
	n.add_child(Fx.smoke({"amount": _n(5), "lifetime": 2.0, "one_shot": false, "explosiveness": 0.0, "preprocess": 2.0,
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.4, 1.0), "size": 0.8, "color": Color(0.7, 0.7, 0.72, 0.3),
		"aabb": aabb}))
	return n


## Heat shimmer and a faint grey haze off a jet idling on deck (behind its nozzles, along +z local).
static func idle_haze(parent: Node3D, pos: Vector3, dir: Vector3) -> GPUParticles3D:
	return _add(parent, Fx.smoke({"amount": _n(10), "lifetime": 1.6, "one_shot": false, "explosiveness": 0.0,
		"preprocess": 1.6, "shape": "sphere", "radius": 0.4, "dir": dir, "spread": 12.0, "speed": Vector2(2.0, 4.0),
		"size": 1.4, "curve": "puff", "color": Color(0.8, 0.8, 0.8, 0.12),
		"aabb": AABB(Vector3(-10, -2, -10), Vector3(20, 8, 20))}), pos)


## Sun glitter dancing on the sea (a flat box on the water toward the sun).
static func glitter(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 60) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 0.8, "preprocess": 0.8, "shape": "box",
		"extents": extents, "speed": Vector2.ZERO, "spread": 0.0, "tex": Fx.Tex.STAR, "size": 1.4, "curve": "pop",
		"color": Color(2.4, 2.3, 2.0), "aabb": AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 8, 8))}), center)


## Salt glints and spray motes hanging in the sunlit air round the course (ambient layer).
static func salt(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 4.0, "preprocess": 4.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(0, 0.1, 1), "spread": 40.0, "speed": Vector2(0.4, 1.4),
		"gravity": Vector3(0, 0.05, 0.6), "turbulence": 0.7, "tex": Fx.Tex.DOT, "size": 0.09, "curve": "pop",
		"color": Color(2.0, 2.1, 2.3), "aabb": AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 8, 8))}), center)


## Dust and grit drifting in the shafts of daylight that fall into the hangar through the refit.
static func shaft_dust(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 6.0, "preprocess": 6.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3.DOWN, "spread": 60.0, "speed": Vector2(0.05, 0.3),
		"turbulence": 0.6, "tex": Fx.Tex.DOT, "size": 0.1, "curve": "pop", "color": Color(2.2, 2.0, 1.7),
		"aabb": AABB(-extents - Vector3(3, 3, 3), extents * 2.0 + Vector3(6, 6, 6))}), center)


## One-shot burst in the deck crew's jersey colours (checkpoints). Not emitting until restart().
static func crew_burst(parent: Node3D, pos: Vector3, amount: int = 60, speed: float = 7.0) -> GPUParticles3D:
	return _add(parent, Fx.burst({"amount": _n(amount), "lifetime": 1.6, "tex": Fx.Tex.PETAL, "additive": false,
		"size": 0.3, "pick": crew(), "speed": Vector2(speed * 0.4, speed), "dir": Vector3.UP, "spread": 50.0,
		"gravity": Vector3(0, -6.0, 0), "damping": Vector2(0.5, 1.5), "angle": Vector2(0, 360), "spin": Vector2(-300, 300),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": AABB(Vector3(-10, -6, -10), Vector3(20, 16, 20))}), pos)


## A puff of catapult-steam white (checkpoints, arrivals).
static func steam_burst(parent: Node3D, pos: Vector3, radius: float = 1.2, amount: int = 30) -> GPUParticles3D:
	return _add(parent, Fx.smoke({"amount": _n(amount), "lifetime": 1.6, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(1.5, 4.5), "size": 1.8, "color": Color(1, 1, 1, 0.6),
		"aabb": AABB(Vector3(-radius - 8, -3, -radius - 8), Vector3(radius * 2 + 16, 14, radius * 2 + 16))}), pos)


## A coloured smoke trail for the finish flyover (world-space, follows the emitter).
static func smoke_trail(color: Color) -> GPUParticles3D:
	return Fx.emitter({"amount": _n(90), "lifetime": 3.0, "fixed_fps": 0, "shape": "sphere", "radius": 0.4,
		"speed": Vector2(0.0, 0.6), "spread": 180.0, "tex": Fx.Tex.SMOKE, "additive": false, "size": 2.6, "curve": "puff",
		"color": color, "fade": PackedFloat32Array([0.9, 0.6, 0.0]), "angle": Vector2(0, 360),
		"aabb": AABB(Vector3(-400, -100, -400), Vector3(800, 300, 800))})
