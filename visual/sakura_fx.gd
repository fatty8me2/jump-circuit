class_name SakuraFx
extends RefCounted
## Sakura Peaks particle presets on top of Fx (so every amount goes through Fx.count, i.e.
## Settings.particle_scale()). Ambient ones are world-space emitters over an area; one-shots are
## built idle and restarted on their event. Visual only: nothing here touches gameplay.

static var PETALS: PackedColorArray = PackedColorArray([Color(1.0, 0.72, 0.82), Color(1.0, 0.86, 0.9), Color(0.96, 0.56, 0.7),
		Color(1.0, 0.94, 0.95), Color(1.0, 0.64, 0.76)])
static var EMBER: PackedColorArray = PackedColorArray([Color(2.4, 1.3, 0.5), Color(2.2, 0.9, 0.4), Color(2.6, 1.8, 0.9)])


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Blossom drifting down and sideways on the evening breeze through a box (the level's signature).
static func petals(parent: Node, center: Vector3, ext: Vector3, amount: int, wind: Vector3 = Vector3(0.6, 0, 0.2)) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 6.0, "shape": "box", "extents": ext,
		"dir": Vector3(wind.x, -0.6, wind.z), "spread": 35.0, "speed": Vector2(0.4, 1.2), "gravity": Vector3(wind.x * 0.3, -0.35, wind.z * 0.3),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.16, "scale": Vector2(0.7, 1.3), "curve": "flat",
		"pick": PETALS, "angle": Vector2(0, 360), "spin": Vector2(-200, 200), "turbulence": 0.9, "turbulence_scale": 3.0,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 6.0, "aabb": _aabb(ext, 12.0)})
	p.position = center
	parent.add_child(p)
	return p


## Petals shed from under a tree's canopy (a disc of falling blossom).
static func shed(parent: Node, at: Vector3, radius: float, fall: float, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": maxf(fall / 0.8, 2.0), "shape": "sphere", "radius": radius,
		"dir": Vector3(0.3, -1, 0.1), "spread": 25.0, "speed": Vector2(0.3, 0.8), "gravity": Vector3(0.15, -0.5, 0.05),
		"tex": Fx.Tex.PETAL, "additive": false, "size": 0.15, "curve": "flat", "pick": PETALS,
		"angle": Vector2(0, 360), "spin": Vector2(-240, 240), "turbulence": 1.0,
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "preprocess": 4.0,
		"aabb": AABB(Vector3(-radius - 6.0, -fall - 4.0, -radius - 6.0), Vector3(radius * 2.0 + 12.0, fall + 8.0, radius * 2.0 + 12.0))})
	p.position = at
	parent.add_child(p)
	return p


## Fireflies / lantern motes: warm points wandering in the dusk.
static func fireflies(parent: Node, center: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 4.0, "shape": "box", "extents": ext,
		"speed": Vector2(0.05, 0.3), "spread": 180.0, "gravity": Vector3(0, 0.05, 0), "tex": Fx.Tex.DOT,
		"size": 0.14, "curve": "pop", "pick": PackedColorArray([Color(2.2, 2.0, 0.8), Color(2.0, 1.4, 0.6)]),
		"turbulence": 1.4, "turbulence_scale": 3.0, "preprocess": 4.0, "aabb": _aabb(ext)})
	p.position = center
	parent.add_child(p)
	return p


## Low mist rolling over water or a valley floor (soft, mix blend).
static func mist(parent: Node, center: Vector3, ext: Vector3, amount: int, col: Color = Color(1.0, 0.86, 0.88, 0.22)) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 8.0, "shape": "box", "extents": ext,
		"dir": Vector3(1, 0.05, 0.2), "spread": 30.0, "speed": Vector2(0.2, 0.6), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 4.0, "scale": Vector2(0.7, 1.4), "curve": "puff", "color": col,
		"angle": Vector2(0, 360), "spin": Vector2(-8, 8), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"preprocess": 8.0, "aabb": _aabb(ext, 10.0)})
	p.position = center
	parent.add_child(p)
	return p


## Spray and ripples off falling water (waterfalls, the mill wheel, the koi splashes).
static func spray(parent: Node, at: Vector3, ext: Vector3, amount: int) -> GPUParticles3D:
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 1.4, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -6.0, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.7, "curve": "puff", "color": Color(0.92, 0.95, 1.0, 0.35),
		"angle": Vector2(0, 360), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": _aabb(ext, 6.0)})
	p.position = at
	parent.add_child(p)
	return p


## A waterfall: streaks of water pouring down a sheet from `top` (world), `width` across local X,
## `height` tall, with mist boiling up at its foot. `yaw` turns the sheet. Visual only.
static func waterfall(parent: Node, top: Vector3, width: float, height: float, yaw: float = 0.0) -> void:
	var holder := Node3D.new()
	holder.position = top
	holder.rotation.y = yaw
	parent.add_child(holder)
	var sheet := StandardMaterial3D.new()
	sheet.albedo_color = Color(0.8, 0.88, 0.95, 0.35)
	sheet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheet.roughness = 0.1
	sheet.emission_enabled = true
	sheet.emission = Color(0.9, 0.8, 0.85)
	sheet.emission_energy_multiplier = 0.25
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	var mi := Look.mesh_node(q, sheet, Vector3(0, -height * 0.5, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	var vis := AABB(Vector3(-width - 6.0, -height - 8.0, -8.0), Vector3(width * 2.0 + 12.0, height + 14.0, 16.0))
	var fall: GPUParticles3D = Fx.emitter({"amount": clampi(int(width * height * 0.6), 30, 160), "lifetime": maxf(height / 14.0, 0.6),
		"local": true, "shape": "box", "extents": Vector3(width * 0.5, 0.1, 0.15), "dir": Vector3.DOWN, "spread": 3.0,
		"speed": Vector2(6.0, 9.0), "gravity": Vector3(0, -9.0, 0), "facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false,
		"size": Vector2(0.12, 1.4), "color": Color(0.92, 0.95, 1.0, 0.55), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": vis})
	fall.preprocess = fall.lifetime
	holder.add_child(fall)
	var foot: GPUParticles3D = Fx.emitter({"amount": clampi(int(width * 4.0), 10, 40), "lifetime": 2.2, "local": true,
		"shape": "box", "extents": Vector3(width * 0.5, 0.2, 0.6), "offset": Vector3(0, -height, 0), "dir": Vector3.UP,
		"spread": 40.0, "speed": Vector2(0.8, 2.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 2.2, "curve": "puff",
		"color": Color(0.95, 0.92, 0.96, 0.3), "angle": Vector2(0, 360), "fade": PackedFloat32Array([0.0, 1.0, 0.0]),
		"preprocess": 2.2, "aabb": vis})
	holder.add_child(foot)
	# SOUND: the roar of falling water (a loop, heard close up)
	WorldAudio.loop("sakura_waterfall", holder, -14.0, 28.0, 6.0)


## One-shot: a puff of blossom thrown up and fluttering down (checkpoints, launches, arrivals).
static func petal_pop(radius: float, amount: int, speed: float) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.0, "shape": "sphere", "radius": radius * 0.4,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(speed * 0.4, speed), "gravity": Vector3(0, -2.5, 0),
		"damping": Vector2(1.5, 3.0), "tex": Fx.Tex.PETAL, "additive": false, "size": 0.2, "curve": "flat",
		"pick": PETALS, "angle": Vector2(0, 360), "spin": Vector2(-300, 300), "turbulence": 1.0,
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": _aabb(Vector3.ONE * 6.0)})


## One-shot: warm glints rising (a lantern flaring, a stage banked).
static func glints(amount: int, col: Color = Color(2.4, 1.6, 0.8)) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 1.3, "shape": "sphere", "radius": 0.6, "tex": Fx.Tex.STAR,
		"size": 0.32, "speed": Vector2(1.5, 4.0), "gravity": Vector3(0, 0.6, 0), "curve": "pop", "color": col,
		"aabb": AABB(Vector3(-8, -4, -8), Vector3(16, 14, 16))})


## One-shot firework over the keep: a ring of warm sparks with a falling tail.
static func firework(col: Color, amount: int = 70) -> GPUParticles3D:
	return Fx.sparks({"amount": amount, "lifetime": 1.6, "shape": "sphere", "radius": 0.3, "spread": 180.0,
		"speed": Vector2(7.0, 10.0), "gravity": Vector3(0, -4.0, 0), "damping": Vector2(1.5, 2.5),
		"size": Vector2(0.08, 0.6), "color": col, "aabb": AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))})
