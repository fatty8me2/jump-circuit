class_name Look
extends RefCounted
## Shared art direction: level themes, material factory, mesh helpers.
## Everything visual in a level pulls colours from Look.theme so a level reads
## as one palette.

const PLATFORM_SHADER: Shader = preload("res://visual/platform.gdshader")
const CLOUD_SHADER: Shader = preload("res://visual/sky_clouds.gdshader")

const THEMES: Dictionary = {
	"gardens": {
		"sky_top": Color(0.12, 0.38, 0.82), "sky_horizon": Color(0.72, 0.87, 0.98), "sky_bottom": Color(0.42, 0.66, 0.90),
		"sun": Color(1.0, 0.95, 0.84), "sun_energy": 1.5, "sun_rot": Vector3(-48, -35, 0),
		"ambient": Color(0.62, 0.74, 0.95), "ambient_energy": 0.75, "fog": Color(0.66, 0.82, 0.97), "fog_density": 0.0011,
		"top": Color(0.40, 0.68, 0.27), "side": Color(0.66, 0.50, 0.36), "trim": Color(1.0, 0.93, 0.74),
		"alt_top": Color(0.85, 0.72, 0.50), "accent": Color(1.0, 0.55, 0.35), "accent2": Color(0.98, 0.80, 0.30),
		"decor": Color(0.30, 0.62, 0.40), "decor2": Color(0.95, 0.55, 0.65), "metal": Color(0.55, 0.50, 0.45),
		"cloud_light": Color(1, 1, 1), "cloud_shade": Color(0.72, 0.82, 0.96),
	},
	"foundry": {
		"sky_top": Color(0.16, 0.10, 0.22), "sky_horizon": Color(0.98, 0.52, 0.28), "sky_bottom": Color(0.45, 0.16, 0.18),
		"sun": Color(1.0, 0.80, 0.60), "sun_energy": 1.6, "sun_rot": Vector3(-32, 40, 0),
		"ambient": Color(0.50, 0.48, 0.75), "ambient_energy": 0.85, "fog": Color(0.80, 0.42, 0.32), "fog_density": 0.0016,
		"top": Color(0.62, 0.65, 0.72), "side": Color(0.27, 0.24, 0.30), "trim": Color(1.0, 0.62, 0.20),
		"alt_top": Color(0.62, 0.42, 0.34), "accent": Color(1.0, 0.45, 0.15), "accent2": Color(0.30, 0.85, 0.90),
		"decor": Color(0.22, 0.20, 0.26), "decor2": Color(1.0, 0.50, 0.12), "metal": Color(0.42, 0.36, 0.34),
		"cloud_light": Color(1.0, 0.72, 0.52), "cloud_shade": Color(0.48, 0.24, 0.32),
	},
	"balance": {
		"sky_top": Color(0.10, 0.34, 0.46), "sky_horizon": Color(0.78, 0.93, 0.88), "sky_bottom": Color(0.30, 0.62, 0.66),
		"sun": Color(1.0, 0.97, 0.90), "sun_energy": 1.35, "sun_rot": Vector3(-58, 20, 0),
		"ambient": Color(0.60, 0.85, 0.85), "ambient_energy": 0.8, "fog": Color(0.66, 0.88, 0.86), "fog_density": 0.0028,
		"top": Color(0.78, 0.83, 0.83), "side": Color(0.32, 0.50, 0.56), "trim": Color(0.15, 0.75, 0.70),
		"alt_top": Color(0.80, 0.62, 0.40), "accent": Color(0.98, 0.78, 0.25), "accent2": Color(0.15, 0.75, 0.70),
		"decor": Color(0.22, 0.38, 0.44), "decor2": Color(0.95, 0.80, 0.35), "metal": Color(0.62, 0.68, 0.70),
		"cloud_light": Color(0.96, 1.0, 0.98), "cloud_shade": Color(0.55, 0.80, 0.82),
	},
	"clockwork": {
		"sky_top": Color(0.17, 0.13, 0.36), "sky_horizon": Color(0.96, 0.70, 0.62), "sky_bottom": Color(0.42, 0.30, 0.56),
		"sun": Color(1.0, 0.82, 0.62), "sun_energy": 1.45, "sun_rot": Vector3(-30, -60, 0),
		"ambient": Color(0.70, 0.60, 0.90), "ambient_energy": 0.75, "fog": Color(0.82, 0.62, 0.70), "fog_density": 0.003,
		"top": Color(0.86, 0.78, 0.62), "side": Color(0.42, 0.30, 0.42), "trim": Color(0.95, 0.72, 0.25),
		"alt_top": Color(0.62, 0.50, 0.68), "accent": Color(0.95, 0.72, 0.25), "accent2": Color(0.55, 0.85, 0.95),
		"decor": Color(0.72, 0.52, 0.22), "decor2": Color(0.40, 0.28, 0.45), "metal": Color(0.80, 0.62, 0.30),
		"cloud_light": Color(1.0, 0.85, 0.80), "cloud_shade": Color(0.50, 0.40, 0.66),
	},
	# Coral Depths: a sunken reef - dense aqua water haze, light from far above, glowing coral.
	"reef": {
		"sky_top": Color(0.10, 0.45, 0.62), "sky_horizon": Color(0.12, 0.62, 0.70), "sky_bottom": Color(0.02, 0.12, 0.22),
		"sun": Color(0.70, 0.95, 1.0), "sun_energy": 1.25, "sun_rot": Vector3(-72, 25, 0),
		"ambient": Color(0.35, 0.75, 0.85), "ambient_energy": 0.95, "fog": Color(0.10, 0.48, 0.58), "fog_density": 0.0075,
		"top": Color(0.92, 0.84, 0.66), "side": Color(0.16, 0.36, 0.42), "trim": Color(0.35, 1.0, 0.85),
		"alt_top": Color(0.95, 0.55, 0.55), "accent": Color(1.0, 0.45, 0.40), "accent2": Color(0.85, 0.40, 1.0),
		"decor": Color(0.95, 0.40, 0.55), "decor2": Color(0.30, 0.95, 0.80), "metal": Color(0.45, 0.58, 0.60),
		"cloud_light": Color(0.60, 0.95, 1.0), "cloud_shade": Color(0.10, 0.40, 0.50),
	},
	# Orbital Drift: a space station in low orbit - black sky, hard white sunlight, a planet below.
	# (levels/level_6_orbital.gd swaps in its own star-and-planet sky shader and planetshine.)
	"orbital": {
		"sky_top": Color(0.0, 0.0, 0.01), "sky_horizon": Color(0.03, 0.04, 0.10), "sky_bottom": Color(0.02, 0.06, 0.16),
		"sun": Color(1.0, 0.98, 0.95), "sun_energy": 2.0, "sun_rot": Vector3(-30, 125, 0),
		"ambient": Color(0.42, 0.50, 0.72), "ambient_energy": 0.6, "fog": Color(0.03, 0.04, 0.09), "fog_density": 0.0016,
		"top": Color(0.80, 0.82, 0.86), "side": Color(0.24, 0.26, 0.32), "trim": Color(1.0, 0.52, 0.10),
		"alt_top": Color(0.52, 0.58, 0.68), "accent": Color(1.0, 0.52, 0.10), "accent2": Color(0.30, 0.85, 1.0),
		"decor": Color(0.20, 0.22, 0.27), "decor2": Color(1.0, 0.76, 0.28), "metal": Color(0.68, 0.70, 0.76),
		"cloud_light": Color(0.85, 0.90, 1.0), "cloud_shade": Color(0.30, 0.40, 0.60),
	},
	"ascent": {
		"sky_top": Color(0.02, 0.03, 0.10), "sky_horizon": Color(0.20, 0.30, 0.58), "sky_bottom": Color(0.05, 0.08, 0.20),
		"sun": Color(0.70, 0.80, 1.0), "sun_energy": 1.1, "sun_rot": Vector3(-42, 150, 0),
		"ambient": Color(0.40, 0.50, 0.90), "ambient_energy": 0.9, "fog": Color(0.12, 0.18, 0.40), "fog_density": 0.003,
		"top": Color(0.78, 0.82, 0.92), "side": Color(0.20, 0.24, 0.42), "trim": Color(0.45, 0.95, 1.0),
		"alt_top": Color(0.50, 0.55, 0.78), "accent": Color(0.45, 0.95, 1.0), "accent2": Color(1.0, 0.55, 0.85),
		"decor": Color(0.16, 0.20, 0.38), "decor2": Color(0.45, 0.95, 1.0), "metal": Color(0.55, 0.60, 0.78),
		"cloud_light": Color(0.50, 0.60, 0.90), "cloud_shade": Color(0.10, 0.14, 0.32),
	},
}

static var theme: Dictionary = THEMES["gardens"]
static var _cache: Dictionary = {}
## Primitive meshes shared by exact parameters: identical decor pieces (gear teeth,
## bolts, posts, lamps) then batch through the renderer's automatic instancing.
## Nothing edits a mesh after creation, so sharing is safe.
static var _meshes: Dictionary = {}


static func use_theme(id: String) -> void:
	theme = THEMES[id]
	_cache.clear()
	_meshes.clear()


static func c(key: String) -> Color:
	return theme[key]


# ---- materials ------------------------------------------------------------

static func flat(color: Color, rough: float = 0.7, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	var key: String = "flat:%s:%.2f:%.2f:%.2f" % [color.to_html(), rough, metal, emit]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m


static func platform_material(half: Vector3, style: String = "main", is_round: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PLATFORM_SHADER
	var top: Color = c("top")
	var side: Color = c("side")
	var trim: Color = c("trim")
	var glow: float = 0.0
	match style:
		"alt":
			top = c("alt_top")
		"accent":
			top = c("alt_top")
			trim = c("accent")
			glow = 0.6
		"mover":
			top = c("alt_top").lerp(c("accent2"), 0.35)
			trim = c("accent2")
			glow = 1.2
		"tilt":
			top = c("alt_top").lerp(c("accent"), 0.2)
			trim = c("accent")
			side = c("metal").darkened(0.3)
			glow = 0.8
		"collapse":
			top = Color(0.85, 0.42, 0.36)
			trim = Color(1.0, 0.85, 0.5)
			side = Color(0.45, 0.22, 0.22)
			glow = 0.5
		"goal":
			top = c("trim").lerp(Color.WHITE, 0.3)
			trim = c("accent")
			glow = 2.0
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("side_color", side)
	m.set_shader_parameter("trim_color", trim)
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("is_round", is_round)
	m.set_shader_parameter("trim_glow", glow)
	return m


# ---- mesh helpers -----------------------------------------------------------

static func mesh_node(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


static func box(size: Vector3, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key: Array = ["b", size]
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return mesh_node(_meshes[key], mat, pos)


static func cylinder(radius: float, height: float, mat: Material, pos: Vector3 = Vector3.ZERO, top_radius: float = -1.0, segments: int = 24) -> MeshInstance3D:
	var top: float = radius if top_radius < 0.0 else top_radius
	var key: Array = ["c", radius, top, height, segments]
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.bottom_radius = radius
		cm.top_radius = top
		cm.height = height
		cm.radial_segments = segments
		cm.rings = 1
		_meshes[key] = cm
	return mesh_node(_meshes[key], mat, pos)


static func sphere(radius: float, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key: Array = ["s", radius]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0
		s.radial_segments = 20
		s.rings = 10
		_meshes[key] = s
	return mesh_node(_meshes[key], mat, pos)


## Box platform visual whose local origin is the box centre.
static func platform_box(size: Vector3, style: String = "main") -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh_node(b, platform_material(size * 0.5, style, false))


static func platform_round(radius: float, height: float, style: String = "main") -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 40
	return mesh_node(cm, platform_material(Vector3(radius, height * 0.5, radius), style, true))


## Tapered keel hanging under a platform so it reads as a floating island.
static func underside(size: Vector3, depth: float, is_round: bool = false) -> MeshInstance3D:
	# round keels depend on diameter and depth; square ones only on depth (the holder scales x/z)
	var key: Array = ["ur", size.x, depth] if is_round else ["uq", depth]
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.height = depth
		cm.rings = 1
		if is_round:
			cm.radial_segments = 24
			cm.top_radius = size.x * 0.5 * 0.92
			cm.bottom_radius = size.x * 0.5 * 0.18
		else:
			cm.radial_segments = 4
			cm.top_radius = 0.7071 * 0.94
			cm.bottom_radius = 0.7071 * 0.22
		_meshes[key] = cm
	var mi: MeshInstance3D = mesh_node(_meshes[key], flat(c("side").darkened(0.18), 0.9))
	if not is_round:
		mi.rotation.y = PI / 4.0
		# CylinderMesh with 4 segments rotated 45deg is a unit square frustum.
		mi.scale = Vector3(1, 1, 1)
		var holder_scale := Vector3(size.x, 1.0, size.z)
		var holder := MeshInstance3D.new()
		holder.scale = holder_scale
		holder.add_child(mi)
		holder.position = Vector3(0, -size.y * 0.5 - depth * 0.5, 0)
		return holder
	mi.position = Vector3(0, -size.y * 0.5 - depth * 0.5, 0)
	return mi


static func cloud_material() -> ShaderMaterial:
	if _cache.has("cloud"):
		return _cache["cloud"]
	var m := ShaderMaterial.new()
	m.shader = CLOUD_SHADER
	m.set_shader_parameter("light_color", c("cloud_light"))
	m.set_shader_parameter("shade_color", c("cloud_shade"))
	_cache["cloud"] = m
	return m


# ---- environment --------------------------------------------------------------

static func build_environment(parent: Node3D) -> WorldEnvironment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = c("sky_top")
	sky_mat.sky_horizon_color = c("sky_horizon")
	sky_mat.ground_horizon_color = c("sky_horizon")
	sky_mat.ground_bottom_color = c("sky_bottom")
	sky_mat.sky_curve = 0.12
	sky_mat.ground_curve = 0.06
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = c("ambient")
	env.ambient_light_energy = float(theme["ambient_energy"]) * 0.72
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = c("fog")
	env.fog_density = float(theme["fog_density"])
	env.fog_aerial_perspective = 0.2
	env.fog_sky_affect = 0.25
	env.fog_sun_scatter = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.35
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = theme["sun_rot"]
	sun.light_color = c("sun")
	sun.light_energy = float(theme["sun_energy"]) * 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)
	# soft fill from the opposite side so shaded faces keep their colour
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, float(Vector3(theme["sun_rot"]).y) + 180.0, 0)
	fill.light_color = c("ambient")
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	parent.add_child(fill)
	Settings.apply_to_environment(env, sun)
	return we
