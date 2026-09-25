class_name VolcanoFx
extends RefCounted
## Cinder Peak particle kit, built on the shared Fx.emitter: rising embers, sifting ash,
## billowing smoke and sulphur steam, lava splashes and bursts, heat haze. Every emitter
## gets a visibility AABB covering where its particles can go; set-piece and ambient
## amounts get the shared Fx.LEVEL_BOOST like the other levels' own effects.

const HAZE_SHADER: Shader = preload("res://visual/volcano_haze.gdshader")

const EMBER := Color(3.2, 1.2, 0.3)
const EMBER_HOT := Color(3.6, 2.2, 0.8)
const LAVA := Color(1.0, 0.45, 0.1)
const SULPHUR := Color(0.95, 0.9, 0.45)


static func _n(amount: int) -> int:
	return roundi(float(amount) * Fx.LEVEL_BOOST)


static func _put(parent: Node3D, p: GPUParticles3D, pos: Vector3) -> GPUParticles3D:
	p.position = pos
	parent.add_child(p)
	return p


## Glowing embers riding the heat up out of a box (continuous).
static func embers(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40, rise: float = 1.4, color: Color = EMBER) -> GPUParticles3D:
	var life: float = 3.6
	var h: float = extents.y + rise * life + 3.0
	return _put(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life, "shape": "box", "extents": extents,
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(rise * 0.5, rise * 1.2), "gravity": Vector3(0.2, 0.35, 0.0),
		"turbulence": 1.3, "turbulence_scale": 3.0, "tex": Fx.Tex.DOT, "size": 0.14, "scale": Vector2(0.45, 1.2),
		"colors": PackedColorArray([Color(color.r, color.g, color.b, 0.0), color, Color(color.r * 0.7, color.g * 0.3, color.b * 0.2, 0.0)]),
		"aabb": AABB(Vector3(-extents.x - 3.0, -extents.y - 1.0, -extents.z - 3.0), Vector3(extents.x * 2.0 + 6.0, h + extents.y, extents.z * 2.0 + 6.0))}), center)


## Grey ash flakes sifting down and tumbling on the wind (continuous).
static func ash(parent: Node3D, center: Vector3, extents: Vector3, amount: int = 40) -> GPUParticles3D:
	var life: float = 6.0
	return _put(parent, Fx.emitter({"amount": _n(amount), "lifetime": life, "preprocess": life, "shape": "box", "extents": extents,
		"dir": Vector3(0.3, -1.0, 0.1), "spread": 25.0, "speed": Vector2(0.4, 1.0), "gravity": Vector3(0.35, -0.35, 0.1),
		"turbulence": 1.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.16, "scale": Vector2(0.5, 1.1),
		"color": Color(0.32, 0.28, 0.27, 0.9), "angle": Vector2(0, 360), "spin": Vector2(-220, 220),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extents - Vector3(6, 10, 6), extents * 2.0 + Vector3(12, 12, 12))}), center)


## A billowing column of smoke (continuous). `tint` is its lit colour.
static func smoke(parent: Node3D, pos: Vector3, radius: float, height: float, amount: int = 16, tint: Color = Color(0.2, 0.16, 0.15, 0.55), size: float = 3.0) -> GPUParticles3D:
	var speed: float = maxf(height / 7.0, 0.6)
	return _put(parent, Fx.emitter({"amount": _n(amount), "lifetime": 7.0, "preprocess": 7.0, "shape": "sphere", "radius": radius,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(speed * 0.7, speed * 1.2), "gravity": Vector3(0.4, 0.2, 0.0),
		"damping": Vector2(0.05, 0.15), "tex": Fx.Tex.SMOKE, "additive": false, "size": size, "scale": Vector2(0.8, 1.6),
		"curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-15, 15), "color": tint,
		"fade": PackedFloat32Array([0.0, 0.8, 0.6, 0.0]), "fade_offsets": PackedFloat32Array([0.0, 0.15, 0.6, 1.0]),
		"aabb": AABB(Vector3(-radius - size * 3.0 - 6.0, -2.0, -radius - size * 3.0 - 6.0), Vector3((radius + size * 3.0 + 6.0) * 2.0, height * 1.6 + size * 3.0, (radius + size * 3.0 + 6.0) * 2.0))}), pos)


## Sulphur steam hissing out of a vent (continuous, pale yellow).
static func steam(parent: Node3D, pos: Vector3, radius: float = 0.6, height: float = 5.0, amount: int = 14) -> GPUParticles3D:
	return smoke(parent, pos, radius, height, amount, Color(0.85, 0.82, 0.55, 0.32), 1.4)


## One-shot spray of molten droplets (bomb impacts, lava splashes).
static func splash(parent: Node3D, pos: Vector3, radius: float = 1.0, amount: int = 40, power: float = 8.0) -> GPUParticles3D:
	return _put(parent, Fx.emitter({"amount": _n(amount), "lifetime": 1.1, "one_shot": true, "explosiveness": 0.92,
		"shape": "sphere", "radius": radius * 0.4, "dir": Vector3.UP, "spread": 65.0, "speed": Vector2(power * 0.5, power),
		"gravity": Vector3(0, -24.0, 0), "damping": Vector2(0.2, 0.8), "tex": Fx.Tex.DOT, "size": 0.26,
		"scale": Vector2(0.5, 1.3), "curve": "shrink", "colors": PackedColorArray([EMBER_HOT, EMBER, Color(1.2, 0.2, 0.05, 0.0)]),
		"aabb": AABB(Vector3(-radius - power, -3.0, -radius - power), Vector3((radius + power) * 2.0, power * 1.6 + 3.0, (radius + power) * 2.0))}), pos)


## One-shot puff of dark smoke and ash (impacts, crust breaking).
static func puff(parent: Node3D, pos: Vector3, radius: float = 1.2, amount: int = 14, tint: Color = Color(0.18, 0.14, 0.13, 0.7)) -> GPUParticles3D:
	return _put(parent, Fx.smoke({"amount": _n(amount), "lifetime": 1.6, "shape": "sphere", "radius": radius * 0.5,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(1.0, 3.0), "size": radius * 1.3, "color": tint,
		"aabb": AABB(Vector3(-radius - 5.0, -2.0, -radius - 5.0), Vector3(radius * 2.0 + 10.0, 10.0, radius * 2.0 + 10.0))}), pos)


## One-shot burst of sparks (checkpoints, the finish, impacts).
static func sparks(parent: Node3D, pos: Vector3, amount: int = 30, power: float = 9.0, color: Color = EMBER_HOT) -> GPUParticles3D:
	return _put(parent, Fx.sparks({"amount": _n(amount), "lifetime": 0.9, "spread": 75.0, "speed": Vector2(power * 0.5, power),
		"gravity": Vector3(0, -12.0, 0), "color": color, "size": Vector2(0.08, 0.6),
		"aabb": AABB(Vector3(-power - 2.0, -4.0, -power - 2.0), Vector3(power * 2.0 + 4.0, power * 1.5 + 4.0, power * 2.0 + 4.0))}), pos)


## One-shot fountain of embers shooting up and raining back (checkpoint bursts, the finish).
static func fountain(parent: Node3D, pos: Vector3, amount: int = 60, power: float = 11.0, color: Color = EMBER) -> GPUParticles3D:
	return _put(parent, Fx.emitter({"amount": _n(amount), "lifetime": 1.8, "one_shot": true, "explosiveness": 0.85,
		"shape": "sphere", "radius": 0.4, "dir": Vector3.UP, "spread": 22.0, "speed": Vector2(power * 0.6, power),
		"gravity": Vector3(0, -14.0, 0), "damping": Vector2(0.3, 1.0), "tex": Fx.Tex.DOT, "size": 0.22,
		"scale": Vector2(0.6, 1.3), "curve": "shrink", "colors": PackedColorArray([EMBER_HOT, color, Color(color.r * 0.5, color.g * 0.2, 0.05, 0.0)]),
		"aabb": AABB(Vector3(-power, -6.0, -power), Vector3(power * 2.0, power * 1.4 + 6.0, power * 2.0))}), pos)


## Lava popping: small blobs flicked up out of a surface (continuous).
static func bubbles(parent: Node3D, center: Vector3, extents: Vector2, amount: int = 14) -> GPUParticles3D:
	return _put(parent, Fx.emitter({"amount": _n(amount), "lifetime": 0.9, "preprocess": 0.9, "shape": "box",
		"extents": Vector3(extents.x, 0.05, extents.y), "dir": Vector3.UP, "spread": 25.0, "speed": Vector2(1.5, 4.0),
		"gravity": Vector3(0, -14.0, 0), "tex": Fx.Tex.DOT, "size": 0.2, "scale": Vector2(0.5, 1.2), "curve": "shrink",
		"colors": PackedColorArray([EMBER_HOT, EMBER, Color(1.0, 0.2, 0.05, 0.0)]),
		"aabb": AABB(Vector3(-extents.x - 2.0, -1.0, -extents.y - 2.0), Vector3(extents.x * 2.0 + 4.0, 5.0, extents.y * 2.0 + 4.0))}), center)


## A heat-shimmer quad standing on a hot surface (Y-billboarded, refracts the view).
static func haze(parent: Node3D, pos: Vector3, width: float, height: float, strength: float = 0.006) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	var m := ShaderMaterial.new()
	m.shader = HAZE_SHADER
	m.set_shader_parameter("strength", strength)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, height * 0.5, 0)
	parent.add_child(mi)
	return mi


## A soft orange light pool (lava glow on the rock around it).
static func glow_light(parent: Node3D, pos: Vector3, energy: float = 2.0, light_range: float = 10.0, color: Color = LAVA) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)
	return l
