class_name ArmadaFx
extends RefCounted
## Storm Armada particle kit, built on the shared Fx.emitter (every amount goes through
## Settings.particle_scale() there): slanting rain, torn cloud wisps blowing through the rigging,
## spray and drips off the hulls, steam from the engine stacks, sparks in the wind, lamp glow motes,
## and the bursts the level fires on its own events (checkpoints, the finish, portal arrivals).
## Visual only.

const RAIN := Color(0.72, 0.8, 0.95, 0.55)
const BRASS := Color(1.0, 0.72, 0.32)
const STORM_BLUE := Color(0.55, 0.75, 1.0)


static func _n(amount: int) -> int:
	return roundi(float(amount) * Fx.LEVEL_BOOST)


static func _add(parent: Node3D, p: GPUParticles3D, pos: Vector3) -> GPUParticles3D:
	p.position = pos
	parent.add_child(p)
	return p


## Rain slanting down on the wind (ambient layer 1), in a box round the route.
static func rain(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 120) -> GPUParticles3D:
	var life: float = clampf(extents.y * 2.0 / 22.0, 0.4, 1.4)
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(0.28, -1.0, 0.12), "spread": 3.0,
		"speed": Vector2(20.0, 25.0), "facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false,
		"size": Vector2(0.025, 0.85), "color": RAIN, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(10, 30, 10), extents * 2.0 + Vector3(20, 60, 20))}), center)


## Torn scud: soft grey wisps of cloud streaming through the fleet (ambient layer 2).
static func scud(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 14) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 9.0, "preprocess": 9.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1.0, 0.02, 0.3), "spread": 10.0, "speed": Vector2(2.5, 5.0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 7.0, "scale": Vector2(0.7, 1.5), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-8, 8), "color": Color(0.6, 0.64, 0.74, 0.3),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(40, 12, 40), extents * 2.0 + Vector3(80, 24, 80))}), center)


## Warm lamp motes and blown sparks drifting past (ambient layer 3, additive glints).
static func motes(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 30, color: Color = Color(2.4, 1.5, 0.7)) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 4.0, "preprocess": 4.0, "local": true,
		"shape": "box", "extents": extents, "dir": Vector3(1, 0.3, 0.2), "spread": 60.0, "speed": Vector2(0.4, 1.4),
		"gravity": Vector3(0.6, 0.2, 0.1), "turbulence": 1.0, "tex": Fx.Tex.DOT, "size": 0.1,
		"scale": Vector2(0.5, 1.3), "color": color, "curve": "pop",
		"aabb": AABB(-extents - Vector3(6, 6, 6), extents * 2.0 + Vector3(12, 12, 12))}), center)


## Rainwater streaming off a hull or a sail's foot: a thin fall of drips.
static func drips(parent: Node3D, pos: Vector3, width: float, height: float = 14.0, amount: int = 16) -> GPUParticles3D:
	var life: float = sqrt(2.0 * height / 9.8) + 0.1
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life,
		"shape": "box", "extents": Vector3(width * 0.5, 0.02, 0.1), "dir": Vector3.DOWN, "spread": 3.0,
		"speed": Vector2(0.5, 1.5), "gravity": Vector3(0, -9.8, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"additive": false, "size": Vector2(0.03, 0.35), "color": Color(0.75, 0.82, 0.95, 0.6),
		"fade": PackedFloat32Array([0.8, 1.0, 0.0]),
		"aabb": AABB(Vector3(-width - 2, -height - 2, -2), Vector3(width * 2 + 4, height + 4, 4))}), pos)


## Steam and coal smoke from an engine stack, torn away downwind.
static func stack_smoke(parent: Node3D, pos: Vector3, scale: float = 1.0, amount: int = 14) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 5.0, "preprocess": 5.0,
		"shape": "sphere", "radius": 0.3 * scale, "dir": Vector3(0.5, 1.0, 0.2), "spread": 10.0,
		"speed": Vector2(1.5, 3.0) * scale, "gravity": Vector3(2.0, 0.4, 0.5), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 2.2 * scale, "scale": Vector2(0.6, 1.4), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-20, 20),
		"color": Color(0.36, 0.36, 0.4, 0.5), "fade": PackedFloat32Array([0.0, 0.9, 0.5, 0.0]),
		"aabb": AABB(Vector3(-6, -4, -6) * scale, Vector3(40, 30, 16) * scale)}), pos)


## Sparks streaming off a lightning-charged rail or a frayed cable (continuous, small).
static func arc_sparks(parent: Node3D, pos: Vector3, extents: Vector3, amount: int = 10) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 0.5, "preprocess": 0.5,
		"shape": "box", "extents": extents, "dir": Vector3(0.6, 1.0, 0), "spread": 50.0, "speed": Vector2(1.0, 3.5),
		"gravity": Vector3(1.5, -6.0, 0), "facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.03, 0.25),
		"color": Color(1.4, 2.0, 3.2), "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 8, 8))}), pos)


## One-shot burst of brass sparks and blue-white glints (checkpoints, portal arrivals).
static func glints(parent: Node3D, pos: Vector3, color: Color, amount: int = 40, speed: float = 6.0) -> GPUParticles3D:
	return _add(parent, Fx.burst({"amount": _n(amount), "lifetime": 1.3, "tex": Fx.Tex.STAR, "size": 0.3,
		"speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, -3.0, 0), "damping": Vector2(1.0, 2.0),
		"color": Fx.hot(color, 2.2), "aabb": AABB(Vector3(-10, -6, -10), Vector3(20, 16, 20))}), pos)


## One-shot puff of steam (checkpoints: the ship's whistle; landings).
static func steam_burst(parent: Node3D, pos: Vector3, radius: float, amount: int = 24, speed: float = 4.0) -> GPUParticles3D:
	return _add(parent, Fx.smoke({"amount": _n(amount), "lifetime": 1.4, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0.8, 0.8, 0),
		"size": 1.5, "color": Color(0.88, 0.9, 0.95, 0.55),
		"aabb": AABB(Vector3(-radius - 8, -4, -radius - 8), Vector3(radius * 2 + 16, 16, radius * 2 + 16))}), pos)


## A lazy column of sparkles rising (portal rings, the flagship's beacon, the finish).
static func rising(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, amount: int = 24) -> GPUParticles3D:
	var life: float = maxf(height / 1.4, 1.5)
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life,
		"shape": "ring", "ring_radius": radius, "ring_inner": radius * 0.3, "ring_height": 0.2,
		"dir": Vector3.UP, "spread": 8.0, "speed": Vector2(1.0, 1.8), "turbulence": 0.5,
		"tex": Fx.Tex.STAR, "size": 0.22, "color": Fx.hot(color, 2.0), "curve": "pop",
		"aabb": AABB(Vector3(-radius - 3, -2, -radius - 3), Vector3(radius * 2 + 6, height + 6, radius * 2 + 6))}), pos)


## A swirling vortex of storm cloud round a ring (the storm-eye portals): wisps orbiting inward.
static func vortex(parent: Node3D, pos: Vector3, radius: float, amount: int = 40) -> GPUParticles3D:
	return _add(parent, Fx.emitter({"amount": _n(amount), "lifetime": 1.6, "preprocess": 1.6, "local": true,
		"shape": "ring", "ring_radius": radius, "ring_inner": radius * 0.8, "ring_height": 0.1, "ring_axis": Vector3(0, 0, 1),
		"dir": Vector3(0, 0, -1), "spread": 20.0, "speed": Vector2(0.2, 0.6), "radial": Vector2(-3.0, -1.5),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.1, "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(90, 200),
		"color": Color(0.55, 0.62, 0.8, 0.5), "fade": PackedFloat32Array([0.0, 1.0, 0.0]),
		"aabb": AABB(Vector3(-radius - 3, -radius - 3, -3), Vector3(radius * 2 + 6, radius * 2 + 6, 6))}), pos)


## A fire burning on a shattered deck edge: a flickering core, sparks and a trail of dark smoke.
static func fire(parent: Node3D, pos: Vector3, scale: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var aabb := AABB(Vector3(-3, -1, -3) * scale, Vector3(6, 9, 6) * scale)
	n.add_child(Fx.emitter({"amount": _n(22), "lifetime": 0.6, "shape": "sphere", "radius": 0.25 * scale,
		"dir": Vector3.UP, "spread": 14.0, "speed": Vector2(1.2, 2.4) * scale, "gravity": Vector3(0.6, 1.5, 0),
		"tex": Fx.Tex.DOT, "size": 0.5 * scale, "curve": "shrink",
		"colors": PackedColorArray([Color(3.0, 2.2, 1.0, 0.0), Color(3.0, 1.6, 0.5, 1.0), Color(2.2, 0.6, 0.15, 0.6), Color(1.0, 0.2, 0.05, 0.0)]),
		"color_offsets": PackedFloat32Array([0.0, 0.12, 0.55, 1.0]), "aabb": aabb}))
	n.add_child(Fx.emitter({"amount": _n(10), "lifetime": 1.4, "shape": "sphere", "radius": 0.2 * scale,
		"dir": Vector3.UP, "spread": 30.0, "speed": Vector2(1.5, 3.5) * scale, "gravity": Vector3(1.2, 0.6, 0),
		"turbulence": 1.2, "tex": Fx.Tex.DOT, "size": 0.08 * scale, "color": Color(3.0, 1.6, 0.5),
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": aabb}))
	var smoke: GPUParticles3D = Fx.emitter({"amount": _n(10), "lifetime": 3.0, "shape": "sphere", "radius": 0.2 * scale,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(1.0, 2.0) * scale, "gravity": Vector3(1.4, 0.4, 0.3),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.4 * scale, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.16, 0.15, 0.16, 0.5), "fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": aabb})
	smoke.position = Vector3(0, 0.6 * scale, 0)
	n.add_child(smoke)
	return n
