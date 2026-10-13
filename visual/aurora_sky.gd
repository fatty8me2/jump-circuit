class_name AuroraSky
extends Node3D
## Aurora Run's living sky: the star dome (visual/aurora_sky.gdshader) plus five huge animated aurora curtains
## that travel with the player (they are far out, so they read as part of the sky and never come closer), and
## the light the aurora throws on the snow: the fill light and the ambient slowly wash green -> teal -> violet.
## The whole sky brightens as you bank distance and swells while you are in ZEN. Purely visual.

const SKY_SHADER: Shader = preload("res://visual/aurora_sky.gdshader")
const CURTAIN_SHADER: Shader = preload("res://visual/aurora_curtain.gdshader")

const GREEN := Color(0.18, 1.0, 0.55)
const TEAL := Color(0.12, 0.85, 0.95)
const VIOLET := Color(0.70, 0.32, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.8)

var level: LevelBase
var env: Environment
var fill: DirectionalLight3D
var sun: DirectionalLight3D
## Course length used for the progress ramp (z of the finish, negative).
var finish_z: float = -1100.0
var _curtains: Array[Dictionary] = []
var _time: float = 0.0
var _base_ambient: Color = Color.WHITE


## Builds the sky into `lvl`: swaps the environment's sky for the star dome and hangs the curtains.
static func attach(lvl: LevelBase, environment: Environment, sun_light: DirectionalLight3D, fill_light: DirectionalLight3D, end_z: float) -> AuroraSky:
	var s := AuroraSky.new()
	s.name = "AuroraSky"
	s.top_level = true
	s.level = lvl
	s.env = environment
	s.sun = sun_light
	s.fill = fill_light
	s.finish_z = end_z
	lvl.add_child(s)
	s._build()
	return s


func _build() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	env.sky.sky_material = sky_mat
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_base_ambient = env.ambient_light_color
	# offset from the player, yaw, width, height, hem colour, mid colour, crown colour, hue, intensity, seed
	var defs: Array[Dictionary] = [
		{"pos": Vector3(0, 175, -520), "yaw": 0.0, "w": 1250.0, "h": 330.0, "hem": GREEN, "mid": TEAL, "top": VIOLET, "hue": 0.0, "i": 1.0, "seed": 0.0, "fold": 46.0},
		{"pos": Vector3(-420, 150, -330), "yaw": 52.0, "w": 900.0, "h": 280.0, "hem": TEAL, "mid": GREEN, "top": MAGENTA, "hue": 0.5, "i": 0.8, "seed": 3.7, "fold": 34.0},
		{"pos": Vector3(450, 165, -360), "yaw": -50.0, "w": 960.0, "h": 300.0, "hem": GREEN, "mid": TEAL, "top": VIOLET, "hue": 0.2, "i": 0.85, "seed": 7.1, "fold": 38.0},
		{"pos": Vector3(60, 260, -240), "yaw": -8.0, "w": 1300.0, "h": 240.0, "hem": VIOLET, "mid": TEAL, "top": MAGENTA, "hue": 0.8, "i": 0.55, "seed": 11.3, "fold": 52.0},
		{"pos": Vector3(0, 210, 380), "yaw": 180.0, "w": 900.0, "h": 220.0, "hem": GREEN, "mid": TEAL, "top": VIOLET, "hue": 0.3, "i": 0.45, "seed": 15.9, "fold": 30.0},
	]
	for d: Dictionary in defs:
		var q := QuadMesh.new()
		q.size = Vector2(float(d["w"]), float(d["h"]))
		q.subdivide_width = 110
		q.subdivide_depth = 5
		var m := ShaderMaterial.new()
		m.shader = CURTAIN_SHADER
		m.set_shader_parameter("hem_color", d["hem"] as Color)
		m.set_shader_parameter("mid_color", d["mid"] as Color)
		m.set_shader_parameter("top_color", d["top"] as Color)
		m.set_shader_parameter("hue", float(d["hue"]))
		m.set_shader_parameter("seed", float(d["seed"]))
		m.set_shader_parameter("fold", float(d["fold"]))
		m.set_shader_parameter("intensity", float(d["i"]))
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.rotation = Vector3(deg_to_rad(-6.0), deg_to_rad(float(d["yaw"])), 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 400.0
		add_child(mi)
		_curtains.append({"node": mi, "mat": m, "pos": d["pos"], "base": float(d["i"])})
	set_process(true)


func _process(dt: float) -> void:
	_time += dt
	if level == null or level.player == null:
		return
	var pp: Vector3 = level.player.global_position
	for c: Dictionary in _curtains:
		(c["node"] as Node3D).global_position = pp + (c["pos"] as Vector3)
	var progress: float = clampf(pp.z / finish_z, 0.0, 1.0)
	var zen: float = FlowMeter.zen_amount
	var swell: float = 0.62 + 0.38 * progress + 0.35 * zen
	for c: Dictionary in _curtains:
		var m: ShaderMaterial = c["mat"]
		m.set_shader_parameter("intensity", float(c["base"]) * swell)
		m.set_shader_parameter("zen", zen)
	# the aurora's light on the snow: a slow wash from green through teal to violet
	var wave: float = 0.5 + 0.5 * sin(_time * 0.11 + progress * 5.0)
	var tint: Color = GREEN.lerp(VIOLET, wave)
	if fill != null:
		fill.light_color = tint.lerp(Color.WHITE, 0.25)
		fill.light_energy = 0.34 + 0.22 * progress + 0.2 * zen
	if env != null:
		env.ambient_light_color = _base_ambient.lerp(tint, 0.22)
