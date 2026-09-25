class_name GlacierFx
extends RefCounted
## Frostbite Pass: palette, ice / snow materials and particle presets. Purely cosmetic.
## Materials are cached (one instance per look) so the renderer can batch them; every
## emitter gets a visibility AABB covering where its particles go.

const ICE := Color(0.62, 0.86, 1.0)
const DEEP := Color(0.14, 0.38, 0.78)
const GLOW := Color(0.45, 0.95, 1.0)
const SNOW := Color(0.93, 0.96, 1.0)
const ROCK := Color(0.2, 0.23, 0.3)
const AURORA_G := Color(0.3, 1.0, 0.6)
const AURORA_V := Color(0.72, 0.42, 1.0)
const WARM := Color(1.0, 0.68, 0.34)
## Hazard tint for icicle frost rings and the avalanche crack (reads as "danger" on white).
const DANGER := Color(1.0, 0.28, 0.4)

const GLASS_SHADER: Shader = preload("res://visual/glacier_glass.gdshader")

static var _mats: Dictionary = {}


## Clear glacier ice for small pieces (icicles, shards, crystals): translucent, glossy, a
## faint inner glow and a bright rim.
static func ice_mat(tint: Color = ICE, emit: float = 0.35, alpha: float = 0.82) -> StandardMaterial3D:
	var key: String = "ice:%s:%.2f:%.2f" % [tint.to_html(), emit, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.roughness = 0.06
	m.metallic = 0.15
	m.metallic_specular = 0.8
	m.rim_enabled = true
	m.rim = 0.7
	m.rim_tint = 0.4
	m.emission_enabled = true
	m.emission = tint.lerp(GLOW, 0.5)
	m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


## Big translucent ice (the frozen falls, fortress walls, seracs): fresnel rim, cloudy
## depth, glowing veins; `streaks` > 0 adds vertical flow lines (frozen water).
static func glass_mat(glow: float = 0.7, streaks: float = 0.0, alpha: float = 0.8, deep: Color = DEEP, shallow: Color = ICE) -> ShaderMaterial:
	var key: String = "glass:%.2f:%.2f:%.2f:%s:%s" % [glow, streaks, alpha, deep.to_html(), shallow.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = GLASS_SHADER
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("streaks", streaks)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("deep_color", deep)
	m.set_shader_parameter("shallow_color", shallow)
	_mats[key] = m
	return m


## Packed snow (matte, faintly blue in the shade).
static func snow_mat(shade: float = 0.0) -> StandardMaterial3D:
	return Look.flat(SNOW.darkened(shade), 0.92)


static func rock_mat(shade: float = 0.0) -> StandardMaterial3D:
	return Look.flat(ROCK.darkened(shade), 0.95)


## A hot (HDR) tint so additive particles bloom.
static func hot(c: Color, k: float = 2.2) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# ---- ambient particles -------------------------------------------------------------------

## Snow falling through a box, slanted by the wind (`drift` is the sideways speed).
static func snowfall(extent: Vector3, amount: int = 90, drift: Vector3 = Vector3(2.5, 0, 0.6)) -> GPUParticles3D:
	var life: float = clampf(extent.y / 2.2, 4.0, 12.0)
	return Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": life, "preprocess": life,
		"shape": "box", "extents": extent * 0.5, "dir": Vector3(0, -1, 0), "spread": 20.0,
		"speed": Vector2(1.2, 2.2), "gravity": drift * 0.4 + Vector3(0, -0.3, 0), "turbulence": 0.8, "turbulence_scale": 5.0,
		"tex": Fx.Tex.DOT, "additive": false, "size": 0.14, "scale": Vector2(0.5, 1.3),
		"color": Color(1.0, 1.0, 1.0, 0.9), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extent * 0.5 - Vector3(8, 8, 8), extent + Vector3(16, 16, 16))})


## Blizzard streaks: fast sideways snow along `dir` (thin quads stretched by velocity).
static func blizzard(extent: Vector3, dir: Vector3, amount: int = 60, speed: float = 14.0) -> GPUParticles3D:
	var along: float = maxf(absf(extent.dot(dir.normalized().abs())), 4.0)
	var life: float = clampf(along / speed, 0.6, 3.0)
	return Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": life, "preprocess": life,
		"shape": "box", "extents": extent * 0.5, "offset": -dir.normalized() * along * 0.35, "dir": dir.normalized() + Vector3(0, -0.12, 0),
		"spread": 6.0, "speed": Vector2(speed * 0.75, speed), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"additive": false, "size": Vector2(0.05, 0.9), "color": Color(0.95, 0.98, 1.0, 0.6),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(-extent * 0.5 - Vector3(10, 6, 10), extent + Vector3(20, 12, 20))})


## Diamond dust: tiny ice crystals glittering in the air (additive stars that twinkle).
static func glitter(extent: Vector3, amount: int = 40, tint: Color = GLOW) -> GPUParticles3D:
	return Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": 3.0, "preprocess": 3.0,
		"shape": "box", "extents": extent * 0.5, "spread": 180.0, "speed": Vector2(0.05, 0.3),
		"gravity": Vector3(0.3, -0.1, 0.0), "turbulence": 0.6, "tex": Fx.Tex.STAR, "size": 0.22,
		"curve": "pop", "color": hot(tint.lerp(Color.WHITE, 0.4), 2.4),
		"aabb": AABB(-extent * 0.5 - Vector3(4, 4, 4), extent + Vector3(8, 8, 8))})


## Wisps of spindrift: big soft puffs blowing off ridges and walls along `dir`.
static func spindrift(extent: Vector3, dir: Vector3, amount: int = 14, size: float = 3.0) -> GPUParticles3D:
	return Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": 3.5, "preprocess": 3.5,
		"shape": "box", "extents": extent * 0.5, "dir": dir.normalized() + Vector3(0, 0.15, 0), "spread": 15.0,
		"speed": Vector2(3.0, 6.0), "damping": Vector2(0.5, 1.0), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": size, "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-30, 30),
		"color": Color(0.92, 0.96, 1.0, 0.35), "fade": PackedFloat32Array([0.0, 0.8, 0.6, 0.0]),
		"aabb": AABB(-extent * 0.5 - Vector3(20, 10, 20), extent + Vector3(40, 20, 40))})


## Aurora motes: slow green / violet sparks drifting upward (around shrines, portals, the finish).
static func aurora_motes(extent: Vector3, amount: int = 30) -> GPUParticles3D:
	return Fx.emitter({"amount": roundi(amount * Fx.LEVEL_BOOST), "lifetime": 4.0, "preprocess": 4.0,
		"shape": "box", "extents": extent * 0.5, "dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.3, 1.0),
		"turbulence": 1.0, "tex": Fx.Tex.DOT, "size": 0.3, "curve": "pop",
		"pick": PackedColorArray([hot(AURORA_G, 2.4), hot(AURORA_V, 2.4), hot(GLOW, 2.2)]),
		"aabb": AABB(-extent * 0.5 - Vector3(4, 4, 4), extent + Vector3(8, 12, 8))})


# ---- one-shot bursts (restart() to fire) ----------------------------------------------------

## A puff of powder snow (landings, shatters, the avalanche's wake).
static func powder(radius: float = 1.0, amount: int = 18, size: float = 1.4) -> GPUParticles3D:
	return Fx.smoke({"amount": amount, "lifetime": 1.2, "shape": "sphere", "radius": radius, "dir": Vector3.UP,
		"spread": 75.0, "speed": Vector2(1.0, 3.5), "size": size, "color": Color(0.95, 0.97, 1.0, 0.75),
		"gravity": Vector3(0, -0.6, 0), "aabb": AABB(Vector3(-8, -3, -8), Vector3(16, 10, 16))})


## Glittering ice sparks thrown out (shatters, checkpoints).
static func frost_burst(tint: Color = GLOW, amount: int = 30, speed: float = 6.0) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 0.9, "speed": Vector2(speed * 0.4, speed), "tex": Fx.Tex.STAR,
		"size": 0.35, "color": hot(tint.lerp(Color.WHITE, 0.3), 2.6), "gravity": Vector3(0, -4.0, 0),
		"aabb": AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))})


## Tumbling chunks of clear ice (lit, they catch the light as they fall).
static func shards(extents: Vector3, amount: int = 18, chunk: float = 0.22) -> GPUParticles3D:
	return Fx.debris({"amount": amount, "lifetime": 1.2, "shape": "box", "extents": extents, "dir": Vector3.UP,
		"spread": 75.0, "speed": Vector2(1.5, 4.5), "chunk": chunk, "color": Color(0.7, 0.9, 1.0),
		"aabb": AABB(Vector3(-6, -14, -6), Vector3(12, 20, 12))})


## A flat frost ring swelling over the floor.
static func frost_ring(radius: float, tint: Color = GLOW) -> GPUParticles3D:
	return Fx.shockwave(radius, {"lifetime": 0.45, "color": hot(tint, 1.6),
		"aabb": AABB(Vector3(-radius - 1, -1, -radius - 1), Vector3(radius * 2 + 2, 2, radius * 2 + 2))})
