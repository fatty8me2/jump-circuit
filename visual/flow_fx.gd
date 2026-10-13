class_name FlowFx
extends Node
## The picture side of the flow meter (FlowMeter drives it every frame): FOV widening, a screen layer
## with radial speed lines and a vignette, a colour grade and calm bloom on the world environment, a
## stronger player trail, world-space wind streaks and the ZEN highlight hook. Purely cosmetic.
##
## Everything is a smooth function of two eased numbers - `flow` (the meter, 0..1) and `zen` (0..1) -
## so tiers never pop. Settings.flow_fx scales it (Full / Reduced / Off) and Settings.fov_kick gates
## the FOV; particle amounts go through Fx (Settings.particle_scale()).

const OVERLAY_SHADER: Shader = preload("res://visual/flow_overlay.gdshader")
## Per-mode strength of each effect (Settings.flow_fx: 0 Full, 1 Reduced, 2 Off). Reduced drops the
## FOV widening and most of the motion (lines, streaks); Off drops every screen effect.
const MODES: Array[Dictionary] = [
	{"fov": 1.0, "lines": 1.0, "wind": 1.0, "trail": 1.0, "grade": 1.0, "vig": 1.0, "bloom": 1.0, "light": 1.0},
	{"fov": 0.0, "lines": 0.3, "wind": 0.35, "trail": 0.8, "grade": 0.5, "vig": 0.5, "bloom": 0.5, "light": 1.0},
	{"fov": 0.0, "lines": 0.0, "wind": 0.0, "trail": 0.0, "grade": 0.0, "vig": 0.0, "bloom": 0.0, "light": 0.0},
]
const MAX_FOV_ADD: float = 9.0
const ZEN_TINT: Color = Color(0.82, 1.0, 0.96)

var level: LevelBase
var player: Player
var camera: OrbitCamera

## The values last applied (tests and the debug readout read these).
var applied: Dictionary = {}

var _env: Environment
var _base: Dictionary = {}
var _layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _trail: GPUParticles3D
var _ribbon: Swoosh
var _wind: GPUParticles3D
var _tier_seen: int = -1
var _light_sent: float = -1.0


func setup(lvl: LevelBase) -> void:
	level = lvl
	player = lvl.player
	camera = lvl.camera
	for we: Node in lvl.find_children("*", "WorldEnvironment", false, false):
		_env = (we as WorldEnvironment).environment
		break
	if _env != null:
		_base = {"sat": _env.adjustment_saturation, "con": _env.adjustment_contrast, "glow": _env.glow_intensity,
			"bloom": _env.glow_bloom, "hdr": _env.glow_hdr_threshold}
	_layer = CanvasLayer.new()
	_layer.layer = 3   # over the 3D view, under the HUD (5) and the pause menu
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = OVERLAY_SHADER
	_rect.material = _mat
	_rect.visible = false
	_layer.add_child(_rect)
	var accent: Color = player.visual.accent
	_trail = Fx.trail({"amount": 56, "lifetime": 0.55, "size": 0.42, "color": Fx.hot(accent, 1.8), "layers": Fx.LAYER,
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "fade_offsets": PackedFloat32Array([0.0, 0.12, 1.0])})
	player.add_child(_trail)
	_trail.position = Vector3(0, 0.6, 0)
	_ribbon = Swoosh.make(Fx.hot(accent, 1.6), 0.07, 0.35)
	add_child(_ribbon)
	_wind = Fx.emitter({"amount": 38, "lifetime": 0.5, "emitting": false, "fixed_fps": 0, "local": false, "layers": Fx.LAYER,
		"shape": "box", "extents": Vector3(5.5, 2.6, 5.5), "dir": Vector3.BACK, "spread": 3.0, "speed": Vector2(8.0, 10.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.05, 1.5), "scale": Vector2(0.6, 1.0),
		"color": Color(1.5, 1.7, 1.9, 0.55), "fade": PackedFloat32Array([0.0, 0.7, 0.0]),
		"fade_offsets": PackedFloat32Array([0.0, 0.25, 1.0]), "aabb": AABB(Vector3(-12, -8, -12), Vector3(24, 16, 24))})
	level.add_child(_wind)


## Strength table for the current Settings.flow_fx.
static func factors(mode: int) -> Dictionary:
	return MODES[clampi(mode, 0, MODES.size() - 1)]


## `flow` and `zen` are the eased meter (0..1); `tier` 0..4; `vel` the player's velocity.
func apply(dt: float, flow: float, zen: float, tier: int, vel: Vector3) -> void:
	var fx: Dictionary = factors(Settings.flow_fx)
	var a: float = smoothstep(0.08, 0.95, flow)
	var speed: float = Vector2(vel.x, vel.z).length()
	var kick: float = 1.0 if Settings.fov_kick else 0.0

	var fov_add: float = (MAX_FOV_ADD - 2.0) * a + 2.0 * zen
	fov_add *= float(fx["fov"]) * kick
	if camera != null and is_instance_valid(camera):
		camera.flow_fov = fov_add

	# screen layer
	var lines: float = smoothstep(0.3, 0.9, flow) * (1.0 - 0.45 * zen) * float(fx["lines"])
	var vig: float = (0.34 * a) * (1.0 - 0.3 * zen) * float(fx["vig"])
	_rect.visible = lines > 0.01 or vig > 0.01
	if _rect.visible:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
		_mat.set_shader_parameter("lines", lines)
		_mat.set_shader_parameter("vignette", vig)
		_mat.set_shader_parameter("vig_color", Color(0.02, 0.04, 0.10).lerp(Color(0.05, 0.16, 0.20), zen))
		_mat.set_shader_parameter("line_color", Color(0.85, 0.95, 1.0).lerp(Color(1.0, 0.97, 0.85), zen))

	# colour grade and the calm ZEN bloom
	var sat: float = 0.0
	var con: float = 0.0
	var glow: float = 0.0
	var bloom: float = 0.0
	var hdr: float = 0.0
	if _env != null:
		sat = (0.12 * a + 0.06 * zen) * float(fx["grade"])
		con = 0.05 * a * float(fx["grade"])
		glow = 0.22 * zen * float(fx["bloom"])
		bloom = 0.07 * zen * float(fx["bloom"])
		hdr = -0.22 * zen * float(fx["bloom"])
		_env.adjustment_saturation = float(_base["sat"]) + sat
		_env.adjustment_contrast = float(_base["con"]) + con
		_env.glow_intensity = float(_base["glow"]) + glow
		_env.glow_bloom = float(_base["bloom"]) + bloom
		_env.glow_hdr_threshold = maxf(float(_base["hdr"]) + hdr, 0.6)

	# trail and wind
	var trail_k: float = a * float(fx["trail"])
	var moving: bool = speed > 9.0
	var pm := _trail.process_material as ParticleProcessMaterial
	if tier != _tier_seen:
		_tier_seen = tier
		var accent: Color = player.visual.accent
		var c: Color = accent.lerp(ZEN_TINT, 0.7) if tier >= 4 else accent
		pm.color = Fx.hot(c, 1.8 + 0.25 * float(tier))
		_ribbon.color = Fx.hot(c, 1.5 + 0.2 * float(tier))
	_trail.emitting = trail_k > 0.05 and moving
	_trail.amount_ratio = clampf(0.25 + 0.75 * trail_k, 0.1, 1.0)
	_trail.position.y = 0.6
	var ribbon_on: bool = trail_k > 0.3 and moving
	_ribbon.width = 0.05 + 0.07 * a + 0.03 * zen
	_ribbon.feed(player.get_global_transform_interpolated().origin + Vector3(0, 0.62, 0), ribbon_on, dt)

	var wind_k: float = smoothstep(0.3, 0.9, flow) * float(fx["wind"])
	var dir: Vector3 = Vector3(vel.x, 0.0, vel.z)
	if dir.length() > 0.5:
		dir = dir.normalized()
	else:
		dir = Vector3.ZERO
	var wind_on: bool = wind_k > 0.05 and speed > 11.0 and dir != Vector3.ZERO
	_wind.emitting = wind_on
	if wind_on:
		_wind.global_position = player.get_global_transform_interpolated().origin + dir * 6.0 + Vector3(0, 1.3, 0)
		var wm := _wind.process_material as ParticleProcessMaterial
		wm.direction = -dir
		wm.initial_velocity_min = speed * 0.5
		wm.initial_velocity_max = speed * 0.7
		_wind.amount_ratio = clampf(wind_k, 0.1, 1.0)

	# highlight hook: nodes in the "flow_highlight" group get set_flow_highlight(0..1) as ZEN deepens
	var light: float = zen * float(fx["light"])
	if absf(light - _light_sent) > 0.01 or (light == 0.0 and _light_sent != 0.0):
		_light_sent = light
		FlowMeter.zen_amount = light
		get_tree().call_group("flow_highlight", "set_flow_highlight", light)

	applied = {"fov_add": fov_add, "lines": lines, "vignette": vig, "saturation": sat, "contrast": con,
		"glow": glow, "bloom": bloom, "hdr": hdr, "trail": _trail.emitting, "ribbon": ribbon_on, "wind": wind_on,
		"highlight": light, "overlay": _rect.visible}


## A respawn or restart: clear ribbons and drop the camera widening at once.
func reset() -> void:
	if _ribbon != null:
		_ribbon.clear()
	if camera != null and is_instance_valid(camera):
		camera.flow_fov = 0.0


func _exit_tree() -> void:
	if _wind != null and is_instance_valid(_wind) and _wind.get_parent() != null:
		_wind.queue_free()
	if _env != null and not _base.is_empty():
		_env.adjustment_saturation = float(_base["sat"])
		_env.adjustment_contrast = float(_base["con"])
		_env.glow_intensity = float(_base["glow"])
		_env.glow_bloom = float(_base["bloom"])
		_env.glow_hdr_threshold = float(_base["hdr"])
	if _light_sent > 0.0:
		FlowMeter.zen_amount = 0.0
		if is_inside_tree():
			get_tree().call_group("flow_highlight", "set_flow_highlight", 0.0)
